"""Phase 5 — Discovery Engine.

Find which features actually drive the forward outcome — *not* a model to deploy. Produces ranked
drivers (correlation + mutual information + LightGBM-SHAP), a feature-redundancy map, and market
regimes (KMeans), all written to ``research/discovery/``.

Targets:
* ``fwd_ret_20`` — continuous forward return (correlation / MI / regression view).
* ``tp_first`` — binary from ``hit_tp_before_sl`` (drop timeouts/NaN): the scalper's real question,
  "does TP get hit before SL?". Drives the LightGBM-SHAP ranking.

Drivers are reported with **direction** (sign) and **per-year stability** (sign consistent across
2024/2025/2026), per the acceptance criteria. Heavy steps (MI, SHAP) run on fixed-seed subsamples for
tractability on ~1.3M rows; sample sizes are logged.

Usage:  python -m research.discovery.discover --symbol btcusd --timeframe M1
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

from pipeline import config

log = logging.getLogger("discover")

ID_COLS = {"ts", "close"}
DISCRETE = {"hour", "dow", "session"}
REGIME_FEATURES = ["adx", "atr_pct", "ema_compression", "di_spread", "ema_50_slope"]
REGIME_NAMES = ["Strong Trend", "Weak Trend", "Compression", "Expansion", "Reversal"]
PRIMARY_RET = "fwd_ret_20"

MI_SAMPLE = 150_000
SHAP_SAMPLE = 80_000
SEED = 7


# ---------------- data ----------------

def load_dataset(symbol: str, timeframe: str) -> pd.DataFrame:
    feats = pd.read_parquet(config.features_path(symbol, timeframe))
    labs = pd.read_parquet(config.labels_path(symbol, timeframe))
    df = feats.merge(labs, on="ts", how="inner")
    if "session" in df.columns:
        df["session"] = df["session"].astype("category").cat.codes.astype("int16")
    return df


def feature_columns(df: pd.DataFrame) -> list[str]:
    label_cols = {c for c in df.columns if c.startswith("fwd_ret_")} | {"hit_tp_before_sl", "tp_first"}
    return [c for c in df.columns if c not in ID_COLS and c not in label_cols]


# ---------------- pure helpers (unit-tested) ----------------

def redundancy_groups(corr: pd.DataFrame, threshold: float = 0.9) -> list[list[str]]:
    """Group features whose pairwise |corr| >= threshold (union-find over the abs-corr graph)."""
    cols = list(corr.columns)
    parent = {c: c for c in cols}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        parent[find(a)] = find(b)

    a = corr.abs()
    for i, ci in enumerate(cols):
        for cj in cols[i + 1:]:
            if a.loc[ci, cj] >= threshold:
                union(ci, cj)
    groups: dict[str, list[str]] = {}
    for c in cols:
        groups.setdefault(find(c), []).append(c)
    return [sorted(g) for g in groups.values() if len(g) > 1]


def representative_reduction(
    corr: pd.DataFrame, threshold: float = 0.9, priority: list[str] | None = None
) -> tuple[list[str], dict[str, str]]:
    """Greedy de-duplication: walk features in ``priority`` order, keep each unless it correlates
    ≥ ``threshold`` with an already-kept feature (then drop it, mapped to that representative).

    Unlike single-linkage grouping this is actionable and avoids transitive chaining: passing
    priority = SHAP-importance order keeps the *important* feature and drops its redundant peers.
    Returns (kept, {dropped_feature: representative}).
    """
    cols = priority or list(corr.columns)
    cols = [c for c in cols if c in corr.columns]
    a = corr.abs()
    kept: list[str] = []
    dropped: dict[str, str] = {}
    for c in cols:
        rep = next((k for k in kept if a.loc[c, k] >= threshold), None)
        if rep is None:
            kept.append(c)
        else:
            dropped[c] = rep
    return kept, dropped


def name_regimes(centroids: pd.DataFrame) -> dict[int, str]:
    """Map KMeans cluster ids -> the 5 named regimes via a deterministic rule on centroid stats.

    centroids indexed by cluster id, columns include adx, atr_pct, ema_compression, di_spread.
    """
    c = centroids.copy()
    c["abs_di"] = c["di_spread"].abs()
    remaining = set(c.index)
    out: dict[int, str] = {}

    # Compression: lowest combined volatility+trend energy.
    comp = (c["atr_pct"] + c["adx"] / 100.0)
    k = comp.loc[list(remaining)].idxmin(); out[k] = "Compression"; remaining.discard(k)
    # Expansion: highest volatility of the rest.
    k = c["atr_pct"].loc[list(remaining)].idxmax(); out[k] = "Expansion"; remaining.discard(k)
    # Strong Trend: highest ADX of the rest.
    k = c["adx"].loc[list(remaining)].idxmax(); out[k] = "Strong Trend"; remaining.discard(k)
    # Of the final two: higher ADX = Weak Trend, the other = Reversal.
    rem = sorted(remaining, key=lambda i: c["adx"].loc[i], reverse=True)
    if rem:
        out[rem[0]] = "Weak Trend"
    for i in rem[1:]:
        out[i] = "Reversal"
    return out


def sign_stability(per_year: dict[int, float], min_abs: float = 0.003) -> str:
    """Summarize per-year correlation signs: 'stable+', 'stable-', or 'unstable'."""
    signs = {np.sign(v) for v in per_year.values() if abs(v) >= min_abs}
    if signs == {1.0}:
        return "stable+"
    if signs == {-1.0}:
        return "stable-"
    return "unstable"


# ---------------- analyses ----------------

def correlation_and_mi(df: pd.DataFrame, features: list[str]) -> pd.DataFrame:
    from sklearn.feature_selection import mutual_info_classif, mutual_info_regression

    sub = df.dropna(subset=features + [PRIMARY_RET, "tp_first"])
    spear = {f: sub[f].corr(sub[PRIMARY_RET], method="spearman") for f in features}

    mi_df = sub.sample(min(MI_SAMPLE, len(sub)), random_state=SEED)
    X = mi_df[features].to_numpy()
    disc_mask = np.array([f in DISCRETE for f in features])
    log.info("  MI on %s rows...", f"{len(mi_df):,}")
    mi_ret = mutual_info_regression(X, mi_df[PRIMARY_RET].to_numpy(),
                                    discrete_features=disc_mask, random_state=SEED)
    mi_tp = mutual_info_classif(X, mi_df["tp_first"].to_numpy().astype(int),
                                discrete_features=disc_mask, random_state=SEED)
    return pd.DataFrame({
        "feature": features,
        f"spearman_{PRIMARY_RET}": [spear[f] for f in features],
        "mi_fwd_ret_20": mi_ret,
        "mi_tp_first": mi_tp,
    }).sort_values("mi_tp_first", ascending=False).reset_index(drop=True)


def per_year_stability(df: pd.DataFrame, features: list[str]) -> pd.DataFrame:
    rows = []
    df = df.copy()
    df["year"] = df["ts"].dt.year
    years = sorted(df["year"].unique())
    for f in features:
        per = {}
        for y in years:
            g = df[df["year"] == y].dropna(subset=[f, PRIMARY_RET])
            per[y] = g[f].corr(g[PRIMARY_RET], method="spearman") if len(g) > 100 else np.nan
        rows.append({"feature": f, **{f"corr_{y}": per[y] for y in years},
                     "stability": sign_stability({y: v for y, v in per.items() if pd.notna(v)})})
    return pd.DataFrame(rows)


def shap_importance(df: pd.DataFrame, features: list[str]) -> pd.DataFrame:
    import lightgbm as lgb
    import shap

    sub = df.dropna(subset=features + ["tp_first"])
    sub = sub[sub["hit_tp_before_sl"].isin([1.0, -1.0])]
    X, y = sub[features], sub["tp_first"].astype(int)
    log.info("  LightGBM on %s rows (tp_first base rate %.3f)...", f"{len(X):,}", y.mean())
    model = lgb.LGBMClassifier(
        n_estimators=300, learning_rate=0.05, num_leaves=63,
        subsample=0.8, colsample_bytree=0.8, random_state=SEED, n_jobs=-1, verbose=-1,
    )
    model.fit(X, y)

    samp = X.sample(min(SHAP_SAMPLE, len(X)), random_state=SEED)
    log.info("  SHAP on %s rows...", f"{len(samp):,}")
    expl = shap.TreeExplainer(model)
    sv = expl.shap_values(samp)
    sv = sv[1] if isinstance(sv, list) else sv     # class-1 contributions
    mean_abs = np.abs(sv).mean(axis=0)
    # direction: sign of correlation between feature value and its SHAP contribution
    direction = [np.sign(np.corrcoef(samp[f], sv[:, i])[0, 1]) if mean_abs[i] > 0 else 0.0
                 for i, f in enumerate(features)]
    return pd.DataFrame({
        "feature": features, "shap_importance": mean_abs,
        "direction": ["↑tp" if d > 0 else "↓tp" if d < 0 else "·" for d in direction],
    }).sort_values("shap_importance", ascending=False).reset_index(drop=True)


def discover_regimes(df: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    from sklearn.cluster import MiniBatchKMeans
    from sklearn.preprocessing import StandardScaler

    sub = df.dropna(subset=REGIME_FEATURES).copy()
    Xs = StandardScaler().fit_transform(sub[REGIME_FEATURES])
    km = MiniBatchKMeans(n_clusters=5, random_state=SEED, n_init=10, batch_size=10_000)
    sub["cluster"] = km.fit_predict(Xs)

    centroids = sub.groupby("cluster")[REGIME_FEATURES].mean()
    mapping = name_regimes(centroids)
    sub["regime"] = sub["cluster"].map(mapping)

    summary = sub.groupby("regime").agg(
        bars=("regime", "size"),
        tp_rate=("tp_first", "mean"),
        mean_fwd_ret_20=(PRIMARY_RET, "mean"),
        adx=("adx", "mean"),
        atr_pct=("atr_pct", "mean"),
        ema_compression=("ema_compression", "mean"),
    ).reset_index()
    summary["pct_of_bars"] = (summary["bars"] / summary["bars"].sum()).round(4)
    regimes_out = sub[["ts", "regime"]].copy()
    return summary.sort_values("bars", ascending=False).reset_index(drop=True), regimes_out


# ---------------- orchestration & report ----------------

def run(symbol: str, timeframe: str) -> dict:
    config.DISCOVERY_DIR.mkdir(parents=True, exist_ok=True)
    t0 = time.perf_counter()
    df = load_dataset(symbol, timeframe)
    df["tp_first"] = (df["hit_tp_before_sl"] == 1.0).astype("float")
    df.loc[~df["hit_tp_before_sl"].isin([1.0, -1.0]), "tp_first"] = np.nan
    features = feature_columns(df)
    log.info("[%s %s] %s rows, %s features", symbol, timeframe, f"{len(df):,}", len(features))

    log.info("Correlation + mutual information...")
    cmi = correlation_and_mi(df, features)
    log.info("Per-year stability...")
    stab = per_year_stability(df, features)
    log.info("LightGBM + SHAP...")
    shp = shap_importance(df, features)
    log.info("Redundancy...")
    corr_mat = df.dropna(subset=features)[features].corr(method="spearman")
    redun = redundancy_groups(corr_mat, threshold=0.9)
    kept, dropped = representative_reduction(corr_mat, threshold=0.9,
                                             priority=list(shp["feature"]))
    log.info("Regimes (KMeans)...")
    regime_summary, regimes_out = discover_regimes(df)

    # merge driver tables
    drivers = (shp.merge(cmi, on="feature", how="left")
                  .merge(stab[["feature", "stability"]], on="feature", how="left"))

    tag = f"{symbol}_{timeframe}"
    drivers.to_csv(config.DISCOVERY_DIR / f"drivers_{tag}.csv", index=False)
    cmi.to_csv(config.DISCOVERY_DIR / f"correlation_mi_{tag}.csv", index=False)
    stab.to_csv(config.DISCOVERY_DIR / f"stability_{tag}.csv", index=False)
    regime_summary.to_csv(config.DISCOVERY_DIR / f"regimes_summary_{tag}.csv", index=False)
    regimes_out.to_parquet(config.DISCOVERY_DIR / f"regimes_{tag}.parquet", index=False)
    (config.DISCOVERY_DIR / f"redundancy_{tag}.json").write_text(
        json.dumps({"linkage_groups": redun, "keep": kept, "drop": dropped}, indent=2))

    _plots(tag, drivers, regime_summary, df)
    md = _render_md(symbol, timeframe, len(df), len(features), drivers,
                    kept, dropped, regime_summary)
    (config.DISCOVERY_DIR / f"discovery_{tag}.md").write_text(md)

    elapsed = round(time.perf_counter() - t0, 1)
    log.info("Done in %ss -> %s", elapsed, config.DISCOVERY_DIR / f"discovery_{tag}.md")
    return dict(symbol=symbol, timeframe=timeframe, n_rows=len(df), n_features=len(features),
                redundancy_groups=len(redun), elapsed_s=elapsed)


def _plots(tag, drivers, regime_summary, df):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception as exc:  # noqa: BLE001
        log.warning("matplotlib unavailable, skipping plots (%s)", exc)
        return
    top = drivers.head(15).iloc[::-1]
    fig, ax = plt.subplots(figsize=(7, 5))
    ax.barh(top["feature"], top["shap_importance"], color="#3b7dd8")
    ax.set_title(f"SHAP importance (top 15) — {tag}")
    fig.tight_layout(); fig.savefig(config.DISCOVERY_DIR / f"shap_{tag}.png", dpi=120); plt.close(fig)

    fig, ax = plt.subplots(figsize=(7, 4))
    rs = regime_summary.sort_values("tp_rate")
    ax.barh(rs["regime"], rs["tp_rate"], color="#d8743b")
    ax.axvline(df["tp_first"].mean(), ls="--", c="k", lw=1, label="overall")
    ax.set_title(f"TP-before-SL rate by regime — {tag}"); ax.legend()
    fig.tight_layout(); fig.savefig(config.DISCOVERY_DIR / f"regimes_{tag}.png", dpi=120); plt.close(fig)


def _render_md(symbol, tf, n_rows, n_features, drivers, kept, dropped, regime_summary) -> str:
    base = drivers["mi_tp_first"].notna()
    L = [
        f"# Discovery — {symbol.upper()} {tf}",
        "",
        f"- Rows: {n_rows:,} · Features: {n_features}",
        f"- Target: `tp_first` (TP-before-SL, 1×ATR/H60) and `{PRIMARY_RET}`",
        "- Heavy steps subsampled (MI / SHAP); see CSVs for full tables.",
        "",
        "## Top drivers (by SHAP importance)",
        "",
        "| # | feature | SHAP | dir | MI(tp) | Spearman(ret) | stability |",
        "|--:|---|--:|:--:|--:|--:|:--:|",
    ]
    for i, r in drivers.head(15).iterrows():
        L.append(
            f"| {i+1} | `{r['feature']}` | {r['shap_importance']:.4f} | {r['direction']} | "
            f"{r['mi_tp_first']:.4f} | {r[f'spearman_{PRIMARY_RET}']:+.4f} | {r['stability']} |"
        )
    L += [
        "",
        "**Direction** = sign of feature↔SHAP correlation (↑tp raises TP-first probability). "
        "**stability** = forward-return correlation sign consistent across 2024/2025/2026.",
        "",
        f"## Feature redundancy (|Spearman| ≥ 0.9) — keep {len(kept)}, drop {len(dropped)}",
        "",
        "Greedy reduction in SHAP-importance order: keep the more important feature, drop peers "
        "redundant with it. (Avoids the transitive-chaining artifact of single-linkage grouping; "
        "raw linkage groups are in the redundancy JSON.)",
        "",
        "| drop | redundant with (kept) |",
        "|---|---|",
    ]
    if dropped:
        # group dropped by representative for readability
        by_rep: dict[str, list[str]] = {}
        for d, rep in dropped.items():
            by_rep.setdefault(rep, []).append(d)
        for rep in sorted(by_rep):
            L.append(f"| {', '.join(f'`{x}`' for x in sorted(by_rep[rep]))} | `{rep}` |")
    else:
        L.append("| none | — |")
    L += [
        "",
        "## Market regimes (KMeans, k=5)",
        "",
        "| regime | bars | % | TP rate | mean fwd_ret_20 | ADX | ATR%ile | EMA compr |",
        "|---|--:|--:|--:|--:|--:|--:|--:|",
    ]
    for _, r in regime_summary.iterrows():
        L.append(
            f"| {r['regime']} | {int(r['bars']):,} | {r['pct_of_bars']:.1%} | {r['tp_rate']:.4f} "
            f"| {r['mean_fwd_ret_20']:+.6f} | {r['adx']:.1f} | {r['atr_pct']:.2f} "
            f"| {r['ema_compression']:.4f} |"
        )
    L += [
        "",
        "Regime names are assigned heuristically from centroid stats (ADX / ATR percentile / EMA "
        "compression) — verify against the centroid columns above. Each regime should be researched "
        "separately in Phase 6+. Per-bar regime tags: `regimes_" + f"{symbol}_{tf}" + ".parquet`.",
        "",
    ]
    return "\n".join(L)


def _parse_args(argv=None):
    p = argparse.ArgumentParser(description="Phase 5 — discovery engine")
    p.add_argument("--symbol", default="btcusd")
    p.add_argument("--timeframe", default="M1", choices=["M1", "M3"])
    return p.parse_args(argv)


def main(argv=None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    args = _parse_args(argv)
    run(args.symbol, args.timeframe)
    return 0


if __name__ == "__main__":
    sys.exit(main())
