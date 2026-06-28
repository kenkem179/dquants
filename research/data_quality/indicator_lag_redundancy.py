#!/usr/bin/env python3
"""
R2 - Indicator lag and redundancy audit (Phase 1, BUILD-PLAN).

Measures, with numbers, for the EMA / RSI / DMI / ADX feature families on a
chosen symbol/timeframe feature set:

  1. LAG          - cross-correlation lag (bars) between each indicator's change
                    and an ATR-normalised price impulse. Coincident (lag~0) vs
                    lagging (lag>0) and by how much.
  2. REDUNDANCY   - pairwise |Pearson| among the headline indicators, plus the
                    specific near-duplicate tests (ADX vs |DI-spread|,
                    RSI vs short-EMA distance, etc.).
  3. HALF-LIFE    - predictive-information decay: mutual information / |IC| of
                    feature[t-lag] against the FORWARD return as `lag` grows;
                    half-life = #bars until MI/IC falls to half its lag-0 value.
  4. INCREMENTAL  - does each indicator add OOS predictive value AFTER
                    price/volatility/VP structure is conditioned on? Two views,
                    both per-fold so it is never one-shot:
                      (a) conditional / partial IC: corr of the part of the
                          feature orthogonal to the base set with the part of
                          the forward return orthogonal to the base set;
                      (b) nested ridge OOS R^2: base-only vs base+family,
                          walk-forward, incremental OOS R^2.
  5. STABILITY    - per-fold univariate IC mean/std/sign-agreement.

Decision rule (applied in the report, not here): a lagging indicator may stay
as a regime/state filter ONLY if it improves OOS robustness or conditional
MFE/MAE. It cannot be the sole reason for an entry, SL or target.

RESEARCH-ONLY. Reads processed feature/label Parquet; writes nothing except the
CSV/JSON artefacts it is told to. Never edits upstream artefacts.

Usage:
    conda run -n kenkem python research/data_quality/indicator_lag_redundancy.py \
        --symbol xauusd --tf M1 --out research/data_quality
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import spearmanr
from sklearn.feature_selection import mutual_info_regression
from sklearn.linear_model import Ridge
from sklearn.preprocessing import StandardScaler

PROJECT_ROOT = Path(__file__).resolve().parents[2]

# Headline indicators we audit, grouped by family. These are the lagging
# transforms the doctrine flags; engineered slopes/accels included where they
# are the actual signal a strategy would read.
FAMILIES = {
    "EMA": ["ema_12_dist", "ema_25_dist", "ema_50_dist", "ema_200_dist",
            "ema_12_slope", "ema_50_slope", "ema_200_slope", "ema_compression"],
    "RSI": ["rsi_7", "rsi_14", "rsi_21", "rsi_7_slope", "rsi_14_slope",
            "rsi_14_accel"],
    "DMI": ["di_plus", "di_minus", "di_spread"],
    "ADX": ["adx", "adx_slope", "adx_accel"],
}
ALL_INDICATORS = [c for v in FAMILIES.values() for c in v]

# Base "already known" structure the indicators must beat: price momentum,
# volatility, and VP structure. NO EMA/RSI/DMI/ADX here by construction.
BASE_FEATURES = ["ret_1", "ret_5", "atr", "atr_pct", "atr_slope",
                 "dist_poc", "dist_vah", "dist_val"]

HORIZONS = [1, 5, 10, 20, 60]   # forward-return horizons (bars)
N_FOLDS = 6
MI_SAMPLE = 120_000             # rows subsampled for mutual-information (speed)
RNG = np.random.default_rng(7)


# --------------------------------------------------------------------------- #
# data loading
# --------------------------------------------------------------------------- #
def load(symbol: str, tf: str) -> pd.DataFrame:
    fpath = PROJECT_ROOT / "data" / "features" / f"features_{symbol}_{tf}.parquet"
    lpath = PROJECT_ROOT / "data" / "labels" / f"labels_{symbol}_{tf}.parquet"
    if not fpath.exists():
        raise FileNotFoundError(f"feature parquet missing: {fpath}")
    feat = pd.read_parquet(fpath)
    df = feat.sort_values("ts").reset_index(drop=True)

    # price-based reference series (no lookahead for contemporaneous quantities)
    df["ret_1"] = df["close"].pct_change()
    df["ret_5"] = df["close"].pct_change(5)
    # ATR-normalised 1-bar price impulse (the thing indicators should track)
    df["impulse"] = df["close"].diff() / df["atr"].replace(0, np.nan)

    # forward returns at each horizon (label look-forward from t)
    for h in HORIZONS:
        df[f"fwd_{h}"] = df["close"].shift(-h) / df["close"] - 1.0

    if lpath.exists():
        lab = pd.read_parquet(lpath)
        df = df.merge(lab[["ts", "hit_tp_before_sl"]], on="ts", how="left")
    return df


# --------------------------------------------------------------------------- #
# 1. LAG  - cross-correlation of d(indicator) vs price impulse across leads/lags
# --------------------------------------------------------------------------- #
def lag_table(df: pd.DataFrame, max_lag: int = 12) -> pd.DataFrame:
    impulse = df["impulse"].to_numpy()
    rows = []
    for col in ALL_INDICATORS:
        if col not in df.columns:
            continue
        x = df[col].to_numpy(float)
        dx = np.diff(x, prepend=x[0])          # indicator change
        best_lag, best_corr = 0, 0.0
        contemp = np.nan
        for k in range(-max_lag, max_lag + 1):
            # k>0: indicator change correlated with impulse k bars in the PAST
            #      => indicator LAGS price by k bars.
            a = dx
            b = np.roll(impulse, k)
            m = np.isfinite(a) & np.isfinite(b)
            if m.sum() < 1000:
                continue
            c = np.corrcoef(a[m], b[m])[0, 1]
            if k == 0:
                contemp = c
            if abs(c) > abs(best_corr):
                best_corr, best_lag = c, k
        rows.append(dict(indicator=col, family=_fam(col),
                         peak_lag_bars=best_lag, peak_corr=round(best_corr, 4),
                         contemp_corr=round(float(contemp), 4)))
    return pd.DataFrame(rows)


def _fam(col: str) -> str:
    for fam, cols in FAMILIES.items():
        if col in cols:
            return fam
    return "?"


# --------------------------------------------------------------------------- #
# 2. REDUNDANCY  - pairwise |Pearson| + named near-duplicate checks
# --------------------------------------------------------------------------- #
def redundancy(df: pd.DataFrame, thresh: float = 0.90):
    cols = [c for c in ALL_INDICATORS if c in df.columns]
    sub = df[cols].replace([np.inf, -np.inf], np.nan).dropna()
    corr = sub.corr(method="pearson")

    pairs = []
    for i in range(len(cols)):
        for j in range(i + 1, len(cols)):
            r = corr.iloc[i, j]
            if abs(r) >= thresh:
                pairs.append(dict(a=cols[i], b=cols[j], corr=round(float(r), 4)))
    pairs.sort(key=lambda d: -abs(d["corr"]))

    # named hypotheses from the task
    named = {}
    if {"adx", "di_spread"} <= set(df.columns):
        named["adx_vs_abs_di_spread"] = round(float(
            np.corrcoef(df["adx"], df["di_spread"].abs())[0, 1]), 4)
    if {"rsi_14", "ema_12_dist"} <= set(df.columns):
        named["rsi14_vs_ema12_dist"] = round(float(
            _nan_corr(df["rsi_14"], df["ema_12_dist"])), 4)
    if {"rsi_7", "rsi_14"} <= set(df.columns):
        named["rsi7_vs_rsi14"] = round(float(_nan_corr(df["rsi_7"], df["rsi_14"])), 4)
    if {"adx", "di_spread"} <= set(df.columns):
        named["adx_vs_signed_di_spread"] = round(float(
            _nan_corr(df["adx"], df["di_spread"])), 4)
    if {"ema_50_dist", "dist_kijun"} <= set(df.columns):
        named["ema50_dist_vs_dist_kijun"] = round(float(
            _nan_corr(df["ema_50_dist"], df["dist_kijun"])), 4)
    return corr, pairs, named


def _nan_corr(a, b):
    a = np.asarray(a, float); b = np.asarray(b, float)
    m = np.isfinite(a) & np.isfinite(b)
    if m.sum() < 100:
        return np.nan
    return np.corrcoef(a[m], b[m])[0, 1]


# --------------------------------------------------------------------------- #
# 3. HALF-LIFE  - MI / |IC| decay of feature[t-lag] vs forward return
# --------------------------------------------------------------------------- #
def half_life(df: pd.DataFrame, horizon: int = 5,
              lags=(0, 1, 2, 3, 5, 10, 20, 40)) -> pd.DataFrame:
    target_col = f"fwd_{horizon}"
    rows = []
    for col in ALL_INDICATORS:
        if col not in df.columns:
            continue
        ic0 = None
        ics, mis = {}, {}
        for lag in lags:
            x = df[col].shift(lag)
            y = df[target_col]
            m = np.isfinite(x) & np.isfinite(y)
            if m.sum() < 5000:
                continue
            xv, yv = x[m].to_numpy(), y[m].to_numpy()
            ic = spearmanr(xv, yv).correlation
            ics[lag] = abs(ic)
            # MI on a subsample (speed)
            if m.sum() > MI_SAMPLE:
                idx = RNG.choice(m.sum(), MI_SAMPLE, replace=False)
                xm, ym = xv[idx], yv[idx]
            else:
                xm, ym = xv, yv
            mi = mutual_info_regression(xm.reshape(-1, 1), ym,
                                        random_state=0, n_neighbors=3)[0]
            mis[lag] = mi
            if lag == 0:
                ic0 = abs(ic)
        if not ics:
            continue
        hl = _half_life_from(ics)
        rows.append(dict(indicator=col, family=_fam(col),
                         ic0=round(ics.get(0, np.nan), 5),
                         ic_lag5=round(ics.get(5, np.nan), 5),
                         ic_lag20=round(ics.get(20, np.nan), 5),
                         mi0=round(mis.get(0, np.nan), 6),
                         halflife_bars=hl))
    return pd.DataFrame(rows)


def _half_life_from(ic_by_lag: dict) -> float:
    lags = sorted(ic_by_lag)
    base = ic_by_lag[lags[0]]
    if base <= 0:
        return np.nan
    half = base / 2.0
    prev_l, prev_v = lags[0], base
    for l in lags[1:]:
        v = ic_by_lag[l]
        if v <= half:
            # linear interpolation between prev and this lag
            if prev_v == v:
                return float(l)
            frac = (prev_v - half) / (prev_v - v)
            return round(prev_l + frac * (l - prev_l), 1)
        prev_l, prev_v = l, v
    # never decayed to half within the window: sentinel = beyond last lag.
    return float(lags[-1] + 1)  # interpret as ">last_lag" in the report


# --------------------------------------------------------------------------- #
# 4. INCREMENTAL VALUE  - per-fold partial IC + nested ridge OOS R^2
# --------------------------------------------------------------------------- #
def _folds(n: int, k: int):
    edges = np.linspace(0, n, k + 1, dtype=int)
    return [(edges[i], edges[i + 1]) for i in range(k)]


def partial_ic_per_fold(df: pd.DataFrame, horizon: int = 5) -> pd.DataFrame:
    """Conditional IC: corr( resid(feature|base), resid(fwd_ret|base) ) within
    each time fold. Measures linear predictive value AFTER price/vol/VP is known."""
    base_cols = [c for c in BASE_FEATURES if c in df.columns]
    target = f"fwd_{horizon}"
    use = base_cols + [target] + [c for c in ALL_INDICATORS if c in df.columns]
    d = df[use + ["ts"]].replace([np.inf, -np.inf], np.nan).dropna().reset_index(drop=True)
    folds = _folds(len(d), N_FOLDS)

    out = {}
    for col in [c for c in ALL_INDICATORS if c in d.columns]:
        fold_pic = []
        for (a, b) in folds:
            seg = d.iloc[a:b]
            if len(seg) < 2000:
                continue
            Xb = StandardScaler().fit_transform(seg[base_cols].to_numpy())
            fr = _orthogonal_resid(seg[col].to_numpy(), Xb)
            yr = _orthogonal_resid(seg[target].to_numpy(), Xb)
            m = np.isfinite(fr) & np.isfinite(yr)
            if m.sum() < 1000:
                continue
            pic = spearmanr(fr[m], yr[m]).correlation
            fold_pic.append(pic)
        if fold_pic:
            arr = np.array(fold_pic)
            same_sign = np.mean(np.sign(arr) == np.sign(arr.mean()))
            out[col] = dict(
                family=_fam(col),
                mean_partial_ic=round(float(arr.mean()), 5),
                std_partial_ic=round(float(arr.std()), 5),
                abs_mean=round(float(abs(arr.mean())), 5),
                sign_agreement=round(float(same_sign), 3),
                n_folds=len(arr),
                t_stat=round(float(arr.mean() / (arr.std() / np.sqrt(len(arr)) + 1e-12)), 2),
            )
    return pd.DataFrame(out).T.reset_index().rename(columns={"index": "indicator"})


def _orthogonal_resid(y, X):
    """Residual of y after OLS-regressing on X (with intercept)."""
    Xi = np.column_stack([np.ones(len(X)), X])
    beta, *_ = np.linalg.lstsq(Xi, y, rcond=None)
    return y - Xi @ beta


def nested_oos_r2(df: pd.DataFrame, horizon: int = 5) -> dict:
    """Walk-forward ridge: base-only vs base+family vs base+all-indicators.
    Reports incremental OOS R^2 (test-set, mean over folds)."""
    base_cols = [c for c in BASE_FEATURES if c in df.columns]
    target = f"fwd_{horizon}"
    keep = base_cols + [target] + [c for c in ALL_INDICATORS if c in df.columns]
    d = df[keep].replace([np.inf, -np.inf], np.nan).dropna().reset_index(drop=True)
    folds = _folds(len(d), N_FOLDS)

    def wf_r2(feat_cols):
        r2s = []
        for fi in range(1, len(folds)):          # expanding window
            tr_end = folds[fi][0]
            te_a, te_b = folds[fi]
            tr = d.iloc[:tr_end]; te = d.iloc[te_a:te_b]
            if len(tr) < 5000 or len(te) < 1000:
                continue
            sc = StandardScaler().fit(tr[feat_cols].to_numpy())
            Xtr = sc.transform(tr[feat_cols].to_numpy())
            Xte = sc.transform(te[feat_cols].to_numpy())
            ytr = tr[target].to_numpy(); yte = te[target].to_numpy()
            mdl = Ridge(alpha=10.0).fit(Xtr, ytr)
            pred = mdl.predict(Xte)
            ss_res = np.sum((yte - pred) ** 2)
            ss_tot = np.sum((yte - ytr.mean()) ** 2)
            r2s.append(1 - ss_res / ss_tot)
        return float(np.mean(r2s)) if r2s else np.nan

    base_r2 = wf_r2(base_cols)
    res = {"base_oos_r2": round(base_r2, 6), "horizon": horizon,
           "base_features": base_cols}
    for fam, cols in FAMILIES.items():
        cc = [c for c in cols if c in d.columns]
        r2 = wf_r2(base_cols + cc)
        res[f"base+{fam}_oos_r2"] = round(r2, 6)
        res[f"incremental_{fam}"] = round(r2 - base_r2, 6)
    allc = [c for c in ALL_INDICATORS if c in d.columns]
    r2_all = wf_r2(base_cols + allc)
    res["base+ALL_oos_r2"] = round(r2_all, 6)
    res["incremental_ALL"] = round(r2_all - base_r2, 6)
    return res


# --------------------------------------------------------------------------- #
# 5. STABILITY  - per-fold univariate IC
# --------------------------------------------------------------------------- #
def ic_stability(df: pd.DataFrame, horizon: int = 5) -> pd.DataFrame:
    target = f"fwd_{horizon}"
    d = df[["ts", target] + [c for c in ALL_INDICATORS if c in df.columns]]
    d = d.replace([np.inf, -np.inf], np.nan).reset_index(drop=True)
    folds = _folds(len(d), N_FOLDS)
    rows = []
    for col in [c for c in ALL_INDICATORS if c in d.columns]:
        ics = []
        for (a, b) in folds:
            seg = d.iloc[a:b]
            m = np.isfinite(seg[col]) & np.isfinite(seg[target])
            if m.sum() < 1000:
                continue
            ics.append(spearmanr(seg[col][m], seg[target][m]).correlation)
        if ics:
            arr = np.array(ics)
            rows.append(dict(indicator=col, family=_fam(col),
                             mean_ic=round(float(arr.mean()), 5),
                             std_ic=round(float(arr.std()), 5),
                             sign_agreement=round(float(
                                 np.mean(np.sign(arr) == np.sign(arr.mean()))), 3)))
    return pd.DataFrame(rows)


# --------------------------------------------------------------------------- #
# orchestration
# --------------------------------------------------------------------------- #
def run(symbol: str, tf: str, out_dir: Path, horizon: int = 5) -> dict:
    df = load(symbol, tf)
    n = len(df)
    lag = lag_table(df)
    corr, pairs, named = redundancy(df)
    hl = half_life(df, horizon=horizon)
    pic = partial_ic_per_fold(df, horizon=horizon)
    nested = nested_oos_r2(df, horizon=horizon)
    stab = ic_stability(df, horizon=horizon)

    tag = f"{symbol}_{tf}"
    out_dir.mkdir(parents=True, exist_ok=True)
    lag.to_csv(out_dir / f"r2_lag_{tag}.csv", index=False)
    corr.round(4).to_csv(out_dir / f"r2_corr_matrix_{tag}.csv")
    hl.to_csv(out_dir / f"r2_halflife_{tag}.csv", index=False)
    pic.to_csv(out_dir / f"r2_partial_ic_{tag}.csv", index=False)
    stab.to_csv(out_dir / f"r2_ic_stability_{tag}.csv", index=False)
    bundle = dict(symbol=symbol, tf=tf, n_rows=int(n), horizon=horizon,
                  redundant_pairs=pairs, named_redundancy=named, nested_oos=nested)
    (out_dir / f"r2_summary_{tag}.json").write_text(json.dumps(bundle, indent=2))
    return dict(df_rows=n, lag=lag, corr=corr, pairs=pairs, named=named,
                halflife=hl, partial_ic=pic, nested=nested, stability=stab)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--symbol", default="xauusd")
    ap.add_argument("--tf", default="M1")
    ap.add_argument("--horizon", type=int, default=5)
    ap.add_argument("--out", default=str(PROJECT_ROOT / "research" / "data_quality"))
    args = ap.parse_args()
    res = run(args.symbol, args.tf, Path(args.out), horizon=args.horizon)

    pd.set_option("display.width", 160)
    pd.set_option("display.max_rows", 80)
    print(f"\n=== {args.symbol} {args.tf}  rows={res['df_rows']:,}  horizon={args.horizon} ===")
    print("\n--- 1. LAG (peak cross-corr of d(indicator) vs ATR-norm impulse) ---")
    print(res["lag"].to_string(index=False))
    print("\n--- 2. REDUNDANCY: pairs with |Pearson| >= 0.90 ---")
    for p in res["pairs"]:
        print(f"  {p['a']:>16s} ~ {p['b']:<16s} r={p['corr']}")
    print("  named:", json.dumps(res["named"]))
    print("\n--- 3. PREDICTIVE-INFO HALF-LIFE (vs fwd return) ---")
    print(res["halflife"].to_string(index=False))
    print("\n--- 4a. PARTIAL IC per-fold (after base price/vol/VP) ---")
    print(res["partial_ic"].to_string(index=False))
    print("\n--- 4b. NESTED RIDGE OOS R^2 ---")
    print(json.dumps(res["nested"], indent=2))
    print("\n--- 5. UNIVARIATE IC STABILITY across folds ---")
    print(res["stability"].to_string(index=False))


if __name__ == "__main__":
    main()
