#!/usr/bin/env python3
"""Feature #1 — entry-persistence (DI-spread proxy) — quick coarse sweep on the parity C++ engines.

Carries the gate into BOTH engines (run Monster first, then KK-MasterVP) and measures it against the
SAME basis as MONSTER-FINDINGS/FINDINGS: BTCUSD/XAUUSD M3, train=Aug–Oct, test/OOS=Nov(+Dec for XAU).
The gate requires the directional DI-spread (long: DI+−DI-, short: DI-−DI+) to hold >= min for N
consecutive closed bars before entry. We sweep N ∈ {1,2,3} × min ∈ {3,4,6,8} on top of each engine's
current best .set, plus a baseline (gate off) so the delta is attributable to feature #1 alone.

Usage:
  python research/optimization/sweep_entry_persist.py <monster|masterv> <btc|xau> [base.set]

Output: sweep_persist_<engine>_<sym>.csv  +  a printed table (baseline first, then the grid).
The relative net/PF delta and which (N,min) cells beat baseline are the trustworthy signal (the
absolute $ carry the documented ATR-from-CSV residual vs MT5, same as the other findings).
"""
import csv, os, subprocess, sys, tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HERE = os.path.dirname(__file__)
T = os.path.join(ROOT, "cpp_core/tools")

# Per-engine: binary, the data files it needs, and how it is invoked.
ENGINES = {
    "monster": dict(
        bin=os.path.join(ROOT, "cpp_core/build/monster_backtester"),
        default_set=lambda s: os.path.join(HERE, f"best_monster_real_{s}.set"),
        argv=lambda c, out, st: [
            "--bars-m3", c["m3"], "--bars-m1", c["m1"], "--bars-m5", c["m5"],
            "--ticks", c["ticks"], "--out", out, "--trade-from-ms", str(c["trade_from"]),
            c["flag"], "--set", st],
    ),
    "masterv": dict(
        bin=os.path.join(ROOT, "cpp_core/build/backtester"),
        default_set=lambda s: os.path.join(HERE, f"best_{s}.set"),
        argv=lambda c, out, st: [
            "--bars", c["m3"], "--ticks", c["ticks"], "--out", out,
            "--trade-from-ms", str(c["trade_from"]), c["flag"], "--set", st],
    ),
}

SYM = {
    "btc": dict(m3=f"{T}/bars_btcusd_2025_m3.csv", m1=f"{T}/bars_btcusd_2025_m1.csv",
                m5=f"{T}/bars_btcusd_2025_m5.csv", ticks=f"{T}/ticks_btcusd_2025_window.csv",
                flag="--symbol-btc", trade_from=1754870400000, split="2025.11.01"),
    "xau": dict(m3=f"{T}/bars_xauusd_2025_m3.csv", m1=f"{T}/bars_xauusd_2025_m1.csv",
                m5=f"{T}/bars_xauusd_2025_m5.csv", ticks=f"{T}/ticks_xauusd_window.csv",
                flag="--symbol-xau", trade_from=1754006400000, split="2025.11.01"),
}

PERSIST_BARS = [1, 2, 3]
PERSIST_MIN = [3.0, 4.0, 6.0, 8.0]


def read_base_set(path):
    ov = {}
    if path and os.path.exists(path):
        for line in open(path):
            line = line.split(";")[0].strip()
            if "=" in line:
                k, v = line.split("=", 1)
                ov[k.strip()] = v.strip()
    return ov


def write_set(path, ov):
    with open(path, "w") as f:
        for k, v in ov.items():
            f.write(f"{k}={v}\n")


def metrics(x):
    if not x:
        return dict(n=0, net=0.0, pf=0.0, dd=0.0)
    net = sum(x); gp = sum(t for t in x if t > 0); gl = -sum(t for t in x if t < 0)
    cum = pk = dd = 0.0
    for t in x:
        cum += t; pk = max(pk, cum); dd = max(dd, pk - cum)
    return dict(n=len(x), net=net, pf=(gp / gl if gl > 0 else 0.0), dd=dd)


def run(engine, cfg, base_ov, persist):
    """One backtest with `persist` (dict of Inp* overrides) layered on the base .set."""
    ov = dict(base_ov, **persist)
    tmp = tempfile.gettempdir()
    tag = "_".join(f"{k}{v}" for k, v in persist.items()) or "base"
    st = os.path.join(tmp, f"persist_{engine}_{tag}.set")
    out = os.path.join(tmp, f"persist_{engine}_{tag}.csv")
    write_set(st, ov)
    r = subprocess.run([ENGINES[engine]["bin"], *ENGINES[engine]["argv"](cfg, out, st)],
                       cwd=ROOT, capture_output=True, text=True)
    train, test = [], []
    if r.returncode == 0 and os.path.exists(out):
        for row in csv.DictReader(open(out)):
            u = float(row["realizedUsd"])
            (train if row["entryTimeUTC"] < cfg["split"] else test).append(u)
    for p in (st, out):
        try: os.remove(p)
        except OSError: pass
    return metrics(train), metrics(test), metrics(train + test)


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ENGINES or sys.argv[2] not in SYM:
        print(__doc__); sys.exit(2)
    engine, sym = sys.argv[1], sys.argv[2]
    base_set = sys.argv[3] if len(sys.argv) > 3 else ENGINES[engine]["default_set"](sym)
    cfg = SYM[sym]

    binp = ENGINES[engine]["bin"]
    if not os.path.exists(binp):
        sys.exit(f"missing binary {binp} — build with: cd cpp_core && make {'monster' if engine=='monster' else 'backtester'}")
    missing = [cfg[k] for k in (["m3", "m1", "m5", "ticks"] if engine == "monster" else ["m3", "ticks"])
               if not os.path.exists(cfg[k])]
    if missing:
        sys.exit("missing data files (export bars/ticks on the data machine first):\n  " + "\n  ".join(missing))

    base_ov = read_base_set(base_set)
    print(f"[persist:{engine}:{sym}] base .set = {base_set if os.path.exists(base_set) else '(engine defaults)'} "
          f"({len(base_ov)} keys)")

    rows = []
    # baseline (gate explicitly OFF)
    tr, te, full = run(engine, cfg, base_ov, {"InpEnableEntryPersist": "false"})
    rows.append(dict(bars=0, min=0.0, **{"full_net": full["net"], "full_pf": full["pf"],
               "full_dd": full["dd"], "n": full["n"], "oos_net": te["net"], "oos_pf": te["pf"]}))
    base_net = full["net"]

    for n in PERSIST_BARS:
        for m in PERSIST_MIN:
            persist = {"InpEnableEntryPersist": "true", "InpPersistBars": n, "InpPersistDiMin": m}
            tr, te, full = run(engine, cfg, base_ov, persist)
            rows.append(dict(bars=n, min=m, full_net=full["net"], full_pf=full["pf"],
                       full_dd=full["dd"], n=full["n"], oos_net=te["net"], oos_pf=te["pf"]))

    res = os.path.join(HERE, f"sweep_persist_{engine}_{sym}.csv")
    with open(res, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader(); w.writerows(rows)

    print(f"\n  N  min   full_net   full_pf  full_dd   n   oos_net  oos_pf   Δnet")
    for r in rows:
        lbl = "base" if r["bars"] == 0 else f"{r['bars']}  {r['min']:.0f}"
        dn = "" if r["bars"] == 0 else f"{r['full_net']-base_net:+.0f}"
        print(f"  {lbl:>5}  {r['full_net']:8.0f}  {r['full_pf']:6.3f}  {r['full_dd']:7.0f}  "
              f"{r['n']:4d}  {r['oos_net']:7.0f}  {r['oos_pf']:6.3f}  {dn:>7}")
    print(f"\n  -> {res}")


if __name__ == "__main__":
    main()
