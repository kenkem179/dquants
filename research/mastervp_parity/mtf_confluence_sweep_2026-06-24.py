#!/usr/bin/env python3
"""
mtf_confluence_sweep_2026-06-24.py — walk-forward eval of the KK-MasterVP M5+M3 multi-timeframe
confluence idea (research/mastervp_parity/MTF_CONFLUENCE_SPEC_2026-06-24.md), XAU only.

Arms (all over the SAME 6 disjoint folds = slice_ticks_by_fold.FOLDS):
  A) M5 lock (champion)     : main=M5 bars, M5 lock set, MTF off  -> the bar to beat (MT5 +62,732)
  B) M3 base (MTF off)      : main=M3 bars, M3 lock set, MTF off  -> isolates "is M3 just noisier M5?"
  C) M3 + confluence gate   : main=M3 + M5 overlay, gate on, M5-ATR SL off
  D) M3 + gate + M5-ATR SL  : + InpMtfSlFromHtf=true (rule 2)
  E) M3 + gate(+SL) + EXIT x : + early exit, InpMtfExitNetMin in {0.25..0.55} (rule 3 sweep)

Decision rule (T1): a variant is interesting only if it beats the M5 lock on POOLED result AND does
not degrade worst-fold PF. Engine is a RANKING proxy (exit model over-credits runners) -> any keeper
needs an MT5 A/B before a lock. Run the overfitting gate on the winner's pooled trades.

Usage (from repo root, after `make -C cpp_core backtester` + fold slices exist):
  python3 research/mastervp_parity/mtf_confluence_sweep_2026-06-24.py [--exit-arm C|D] [--dump LABEL CSV]
"""
import argparse, csv, subprocess, sys, tempfile
from pathlib import Path
from slice_ticks_by_fold import FOLDS

ROOT = Path(__file__).resolve().parents[2]
BT = ROOT / "cpp_core/build/backtester"
T = ROOT / "cpp_core/tools"
SLICE = T / "fold_slices"
START_BAL = 10000.0

M3_BARS = T / "bars_xauusd_2025_2026_m3.csv"
M5_BARS = T / "bars_xauusd_2025_2026_m5.csv"
M5_LOCK = T / "mastervp/kkmastervp_xau_m5_LOCKED.set"
M3_LOCK = T / "mastervp/kkmastervp_xau_m3_LOCKED.set"


def read_base(path):
    out = []
    for line in Path(path).read_text().splitlines():
        s = line.split(";", 1)[0].strip()
        if "=" in s:
            k, v = s.split("=", 1)
            out.append((k.strip(), v.strip()))
    return out


def write_set(base_kv, overrides, path):
    d = dict(base_kv); d.update({k: str(v) for k, v in overrides.items()})
    with open(path, "w") as f:
        for k, v in d.items():
            f.write(f"{k}={v}\n")


def run_fold(bars, m5, set_path, fold, out_csv, ticks):
    name, frm, to = fold
    cmd = [str(BT), "--bars", str(bars), "--ticks", str(ticks), "--set-all", str(set_path),
           "--trade-from-ms", str(frm), "--trade-to-ms", str(to), "--symbol-xau", "--out", str(out_csv)]
    if m5:
        cmd += ["--bars-m5", str(m5)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-400:]); return None
    return out_csv


def read_trades(p):
    with open(p) as f:
        return [float(row["realizedUsd"]) for row in csv.DictReader(f)]


def stats(pnls):
    n = len(pnls)
    if n == 0:
        return dict(n=0, win=0.0, pf=0.0, net=0.0, maxdd_pct=0.0)
    wins = [p for p in pnls if p > 0]; gl = -sum(p for p in pnls if p <= 0); gw = sum(wins)
    eq = peak = START_BAL; maxdd = 0.0
    for p in pnls:
        eq += p; peak = max(peak, eq); maxdd = max(maxdd, peak - eq)
    return dict(n=n, win=100*len(wins)/n, pf=(gw/gl if gl > 0 else float("inf")),
                net=sum(pnls), maxdd_pct=100*maxdd/peak if peak else 0.0)


def eval_arm(bars, m5, set_path, tmpd, idx, dump=None):
    per, pool, rows_dump = [], [], []
    for j, fold in enumerate(FOLDS):
        tp = SLICE / f"ticks_xau_{fold[0]}.csv"
        oc = tmpd / f"a{idx}_f{j}.csv"
        if run_fold(bars, m5, set_path, fold, oc, tp) is None:
            per.append(stats([])); continue
        pnls = read_trades(oc); per.append(stats(pnls)); pool += pnls
        if dump:
            lines = Path(oc).read_text().splitlines()
            if j == 0:
                rows_dump.append(lines[0])
            rows_dump += lines[1:]
    if dump and rows_dump:
        Path(dump).write_text("\n".join(rows_dump) + "\n")
    m = stats(pool)
    pfs = [f["pf"] for f in per if f["n"] > 0]
    m["per"] = per
    m["worst_pf"] = min(pfs) if pfs else 0.0
    m["folds_pf1"] = sum(1 for f in per if f["pf"] > 1.0)
    m["folds_pos"] = sum(1 for f in per if f["net"] > 0)
    return m


def fmt(m):
    return (f"n={m['n']:4d} win={m['win']:4.1f} PF={m['pf']:.3f} net={m['net']:8,.0f} "
            f"dd={m['maxdd_pct']:4.1f}% | +={m['folds_pos']}/6 PF>1={m['folds_pf1']}/6 worstPF={m['worst_pf']:.3f}")


def perfold(m):
    return "        " + "  ".join(f"{fd[0]}:PF{f['pf']:.2f}/${f['net']:,.0f}" for fd, f in zip(FOLDS, m["per"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sl", choices=["off", "on"], default="on",
                    help="exit sweep stacks on the gate arm with M5-ATR SL on (default) or off")
    ap.add_argument("--arm-r", default="0.0", help="InpMtfExitArmR for the exit sweep")
    ap.add_argument("--dump", nargs=2, metavar=("LABEL", "CSV"), help="dump pooled trades of an arm by label")
    ap.add_argument("--mode", choices=["gate", "exitonly"], default="gate",
                    help="gate=full MTF confluence arms; exitonly=rule-3 early exit on the pure M3 base")
    a = ap.parse_args()

    tmpd = Path(tempfile.mkdtemp(prefix="mtf_"))
    m3kv = read_base(M3_LOCK); m5kv = read_base(M5_LOCK)
    gate = {"InpEnableMtfConfluence": "true", "InpMtfGateBufAtr": "0.0"}
    sl_on = {"InpMtfSlFromHtf": "true"}; sl_off = {"InpMtfSlFromHtf": "false"}

    arms = []
    # A champion + B base (always shown)
    arms.append(("A M5lock champion", M5_BARS, None, m5kv, {}))
    arms.append(("B M3base MTFoff", M3_BARS, None, m3kv, {}))
    if a.mode == "gate":
        # C gate, D gate+M5SL
        arms.append(("C M3+gate", M3_BARS, M5_BARS, m3kv, {**gate, **sl_off}))
        arms.append(("D M3+gate+M5SL", M3_BARS, M5_BARS, m3kv, {**gate, **sl_on}))
        # E early-exit sweep on top of the chosen SL setting
        base_exit = {**gate, **(sl_on if a.sl == "on" else sl_off)}
        for x in ["0.25", "0.30", "0.35", "0.40", "0.45", "0.50", "0.55"]:
            ov = {**base_exit, "InpEnableMtfExit": "true", "InpMtfExitNetMin": x, "InpMtfExitArmR": a.arm_r}
            arms.append((f"E exit{x}(sl={a.sl},armR={a.arm_r})", M3_BARS, M5_BARS, m3kv, ov))
    else:  # exitonly: rule-3 early exit on the PURE M3 base (no confluence gate, no M5 overlay)
        for x in ["0.25", "0.30", "0.35", "0.40", "0.45", "0.50", "0.55"]:
            ov = {"InpEnableMtfExit": "true", "InpMtfExitNetMin": x, "InpMtfExitArmR": a.arm_r}
            arms.append((f"X M3base+exit{x}(armR={a.arm_r})", M3_BARS, None, m3kv, ov))

    print(f"# MTF confluence WF sweep — XAU, 6 folds, exit-sweep SL={a.sl} armR={a.arm_r}", flush=True)
    results = []
    for i, (label, bars, m5, base_kv, ov) in enumerate(arms):
        sp = tmpd / f"a{i}.set"; write_set(base_kv, ov, sp)
        dump = a.dump[1] if (a.dump and a.dump[0] == label) else None
        m = eval_arm(bars, m5, sp, tmpd, i, dump=dump)
        m["_label"] = label
        results.append(m)
        print(f"  {label:34s} {fmt(m)}", flush=True)
        print(perfold(m), flush=True)
        if dump:
            print(f"    [dump] {label} pooled trades -> {dump}", flush=True)

    champ = results[0]
    print(f"\n=== vs champion (A M5lock: PF {champ['pf']:.3f} net {champ['net']:,.0f} worstPF {champ['worst_pf']:.3f}) ===")
    for m in results[1:]:
        dn = m["net"] - champ["net"]; dpf = m["pf"] - champ["pf"]
        beats = "BEATS" if (m["net"] > champ["net"] and m["worst_pf"] >= champ["worst_pf"]) else ""
        print(f"  {m['_label']:34s} dNet={dn:+8,.0f} dPF={dpf:+.3f} worstPF={m['worst_pf']:.3f} {beats}")


if __name__ == "__main__":
    main()
