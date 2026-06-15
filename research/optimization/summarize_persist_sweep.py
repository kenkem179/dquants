#!/usr/bin/env python3
"""Consolidate the feature-#1 (entry-persistence) sweep CSVs into one findings markdown.

Reads every research/optimization/sweep_persist_<engine>_<sym>.csv produced by sweep_entry_persist.py
and writes FEATURE1-FINDINGS.md: per engine/symbol, the baseline row + the best grid cell by full net
that ALSO holds OOS (oos_net>0 and oos_pf>=1), with the Δ vs baseline. A cell is only worth keeping if
it beats baseline on the Nov OOS split — in-sample improvement alone is overfitting.

Usage: python research/optimization/summarize_persist_sweep.py
"""
import csv, glob, os

HERE = os.path.dirname(__file__)


def load(path):
    rows = []
    for r in csv.DictReader(open(path)):
        rows.append({k: (float(v) if k not in ("n",) else int(float(v))) for k, v in r.items()})
    return rows


def pick(rows):
    base = next((r for r in rows if r["bars"] == 0), None)
    cells = [r for r in rows if r["bars"] != 0]
    # OOS-robust winners: positive OOS net AND OOS PF>=1, ranked by full net.
    robust = [r for r in cells if r["oos_net"] > 0 and r["oos_pf"] >= 1.0]
    best = max(robust, key=lambda r: r["full_net"]) if robust else None
    return base, best, len(robust), len(cells)


def main():
    paths = sorted(glob.glob(os.path.join(HERE, "sweep_persist_*.csv")))
    if not paths:
        print("no sweep_persist_*.csv yet — run scripts/run_persist_sweep.sh first")
        return
    out = os.path.join(HERE, "FEATURE1-FINDINGS.md")
    lines = ["# Feature #1 — entry-persistence (DI-spread proxy) — sweep findings", "",
             "Directional DI-spread (long: DI+−DI-, short: DI-−DI+) must hold ≥ `min` for `N` consecutive",
             "closed bars before entry. Grid N∈{1,2,3} × min∈{3,4,6,8} vs baseline (gate off), on the C++",
             "tick engines (Exness BTC/XAU M3, train Aug–Oct, OOS = Nov). A cell is **kept only if it beats",
             "baseline on the OOS split** — in-sample-only gains are discarded as overfit.", ""]
    for p in paths:
        name = os.path.basename(p)[len("sweep_persist_"):-len(".csv")]   # <engine>_<sym>
        rows = load(p)
        base, best, n_robust, n_cells = pick(rows)
        lines.append(f"## {name}")
        if not base:
            lines.append("_no baseline row — rerun the sweep_\n"); continue
        lines.append(f"- baseline: net **{base['full_net']:.0f}** / PF {base['full_pf']:.3f} / "
                     f"DD {base['full_dd']:.0f} / {base['n']} tr · OOS net {base['oos_net']:.0f} PF {base['oos_pf']:.3f}")
        if best:
            verdict = "KEEP" if best["full_net"] > base["full_net"] else "marginal"
            lines.append(f"- best OOS-robust cell **N={best['bars']:.0f}, min={best['min']:.0f}**: net "
                         f"**{best['full_net']:.0f}** (Δ{best['full_net']-base['full_net']:+.0f}) / "
                         f"PF {best['full_pf']:.3f} / DD {best['full_dd']:.0f} / {best['n']} tr · "
                         f"OOS net {best['oos_net']:.0f} PF {best['oos_pf']:.3f}  → **{verdict}**")
            lines.append(f"- {n_robust}/{n_cells} grid cells were OOS-robust "
                         f"({'broad plateau' if n_robust >= n_cells/2 else 'narrow — treat as fragile'})")
        else:
            lines.append(f"- **no cell beat baseline OOS** (0/{n_cells} robust) → feature #1 is net-neutral/"
                         "negative for this engine+symbol; leave the gate OFF.")
        lines.append("")
    open(out, "w").write("\n".join(lines))
    print(f"wrote {out}")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
