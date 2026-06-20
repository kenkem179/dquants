#!/usr/bin/env python3
"""KenKem optimization sweep harness (TICK engine — the validated one).

Mutates a base .set line-by-line (format-preserving), runs the tick_backtester, and reports
9-col metrics OVERALL + per-period split (2025 = train-ish, 2026 = OOS) so every lever is judged
for robustness, not a single pooled peak (the MasterVP lesson: decompose before locking).

Usage:
  python sweep_kenkem_opt.py            # runs the configured sweep families
  (edit FAMILIES at the bottom to choose what to run)
"""
import sys, os, csv, subprocess, datetime as dt, tempfile
sys.path.insert(0, os.path.dirname(__file__))
from report_metrics import full_metrics

ROOT = "/Users/tokyotechies/Workspace/KEM/dquants"
BIN = f"{ROOT}/cpp_core/build/kenkem/tick_backtester"
BARS = f"{ROOT}/research/kenkem_parity/bars_xauusd_M1_kk.csv"
TICKS = f"{ROOT}/research/kenkem_parity/ticks_xau_full.csv"
BASE = f"{ROOT}/research/kenkem_parity/anchor_E1E2E4.set"
SPLIT = "2026.01.01"   # < SPLIT -> 2025 bucket; >= SPLIT -> 2026 OOS bucket


def write_set(overrides, path):
    """Replace KEY=VALUE lines that match an override; append any new keys. Preserves formatting."""
    base = open(BASE).read().splitlines()
    seen = set()
    out = []
    for ln in base:
        s = ln.strip()
        if "=" in s and not s.startswith("="):
            k = s.split("=", 1)[0].strip()
            if k in overrides:
                indent = ln[: len(ln) - len(ln.lstrip())]
                out.append(f"{indent}{k}={overrides[k]}")
                seen.add(k)
                continue
        out.append(ln)
    for k, v in overrides.items():
        if k not in seen:
            out.append(f"  {k}={v}")
    open(path, "w").write("\n".join(out) + "\n")


def run(overrides):
    with tempfile.NamedTemporaryFile("w", suffix=".set", delete=False) as f:
        setp = f.name
    write_set(overrides, setp)
    outp = setp + ".trades.csv"
    r = subprocess.run([BIN, "--bars-m1", BARS, "--ticks", TICKS, "--set", setp,
                        "--symbol-xau", "--out", outp],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-500:] + "\n")
        return None
    rows = []
    with open(outp) as fh:
        for x in csv.DictReader(fh):
            d = x["entryTimeUTC"][:10]
            t = dt.datetime.strptime(x["entryTimeUTC"], "%Y.%m.%d %H:%M")
            ts = int(t.replace(tzinfo=dt.timezone.utc).timestamp() * 1000)
            rows.append((ts, float(x["realizedUsd"]), d, x.get("kind", "")))
    os.unlink(setp); os.unlink(outp)
    return rows


def metr(rows, bucket=None):
    if bucket == "2025":
        rows = [r for r in rows if r[2] < SPLIT]
    elif bucket == "2026":
        rows = [r for r in rows if r[2] >= SPLIT]
    return full_metrics([(t, p) for t, p, _, _ in rows])


def fmt(m):
    return (f"n={m['n']:4d} net={m['net']:+8.0f} PF={m['pf']:.3f} "
            f"dd={m['dd']:6.0f} sh={m['sharpe']:+.2f}")


def report(label, overrides):
    rows = run(overrides)
    if rows is None:
        print(f"{label:34s} FAILED"); return None
    a, y5, y6 = metr(rows), metr(rows, "2025"), metr(rows, "2026")
    print(f"{label:34s} ALL {fmt(a)} | 25 {fmt(y5)} | 26 {fmt(y6)}")
    return {"all": a, "2025": y5, "2026": y6, "rows": rows}


def bykind(label, overrides):
    """Like report() but also breaks net/PF down per entry kind (independence + priority-steal view)."""
    rows = run(overrides)
    if rows is None:
        print(f"{label:22s} FAILED"); return None
    a = metr(rows)
    parts = []
    for k in ("E1", "E2", "E4", "E5"):
        kr = [(t, p) for t, p, _, kk in rows if kk == k]
        if kr:
            m = full_metrics(kr)
            parts.append(f"{k} n={m['n']:3d} net={m['net']:+6.0f} PF={m['pf']:.2f}")
    print(f"{label:22s} ALL n={a['n']:4d} net={a['net']:+8.0f} PF={a['pf']:.3f} | " + "  ".join(parts))
    return {"all": a, "rows": rows}


ON = {f"ENABLE_E{i}_ENTRIES": "true" for i in (1, 2, 3, 4, 5)}
def combo(*kinds):
    o = {f"ENABLE_E{i}_ENTRIES": ("true" if i in kinds else "false") for i in (1, 2, 3, 4, 5)}
    return o


if __name__ == "__main__":
    fam = sys.argv[1] if len(sys.argv) > 1 else "smoke"

    if fam == "smoke":
        report("baseline E1E2E4", {})

    elif fam == "combos":
        print("== ENTRY COMBOS (per-kind net exposes priority-steal; first-match-wins E1>E2>E4>E5) ==")
        for name, ks in [("E1", (1,)), ("E2", (2,)), ("E4", (4,)), ("E5", (5,)),
                         ("E1E2", (1,2)), ("E1E4", (1,4)), ("E1E5", (1,5)), ("E4E5", (4,5)),
                         ("E1E2E4", (1,2,4)), ("E1E4E5", (1,4,5)), ("E1E2E4E5", (1,2,4,5)),
                         ("E1E2E4E5+E3", (1,2,3,4,5))]:
            bykind(name, combo(*ks))

    elif fam == "sl":
        print("== SL ATR CAP/FLOOR SWEEP (E2 cap also drives E4 — dead E4 keys) ==")
        report("base cap4.0/3.0 flr1.2/1.1", {})
        for cap in ("2.5", "3.0", "3.5", "4.0", "4.5", "5.0"):
            report(f"E1cap={cap}", {"E1_ATR_SL_CAP_MULTIPLIER": cap})
        for cap in ("2.0", "2.5", "3.0", "3.5", "4.0"):
            report(f"E2cap={cap}(+E4)", {"E2_ATR_SL_CAP_MULTIPLIER": cap})
        for flr in ("0.8", "1.0", "1.2", "1.5", "1.8"):
            report(f"E1flr={flr}", {"E1_ATR_SL_FLOOR_MULTIPLIER": flr})
        for flr in ("0.8", "1.0", "1.1", "1.4", "1.7"):
            report(f"E2flr={flr}(+E4)", {"E2_ATR_SL_FLOOR_MULTIPLIER": flr})

    elif fam == "tp":
        print("== TP / RR SWEEP (SL fixed by ATR, TP = RR*risk) ==")
        report("base RR E1=1.9 E2=1.575 E4=2.4", {})
        for rr in ("1.4", "1.7", "1.9", "2.2", "2.6", "3.0"):
            report(f"E1_RR={rr}", {"E1_RR": rr})
        for rr in ("1.2", "1.4", "1.575", "1.9", "2.3"):
            report(f"E2_RR={rr}", {"E2_RR": rr})
        for rr in ("1.8", "2.1", "2.4", "2.8", "3.2"):
            report(f"E4_RR={rr}", {"E4_RR": rr})
        report("DYN_RR off", {"USE_DYNAMIC_RR_SCALING": "false"})

    elif fam == "cand":
        print("== STACKED CANDIDATES (judge on 2026 OOS robustness, not pooled peak) ==")
        DYN = {"USE_DYNAMIC_RR_SCALING": "false"}
        SL = {"E1_ATR_SL_CAP_MULTIPLIER": "3.5"}
        noE2 = {"ENABLE_E2_ENTRIES": "false"}
        report("C0 baseline", {})
        report("C1 DYNoff", DYN)
        report("C2 DYNoff+E1cap3.5", {**DYN, **SL})
        report("C3 C2+E1_RR1.7", {**DYN, **SL, "E1_RR": "1.7"})
        report("C4 C2 dropE2", {**DYN, **SL, **noE2})
        report("C5 C2 dropE2+E4RR1.8", {**DYN, **SL, **noE2, "E4_RR": "1.8"})
        report("C6 DYNoff dropE2", {**DYN, **noE2})
        report("C7 DYNoff+E1RR1.7+E4RR1.8", {**DYN, "E1_RR": "1.7", "E4_RR": "1.8"})

    elif fam == "wf":
        # Quarter-by-quarter: does C2 robustly beat baseline in EVERY window (not just pooled)?
        QTRS = [("25Q2", "2025.03.01", "2025.06.30"), ("25Q3", "2025.07.01", "2025.09.30"),
                ("25Q4", "2025.10.01", "2025.12.31"), ("26Q1", "2026.01.01", "2026.03.31"),
                ("26Q2", "2026.04.01", "2026.05.31")]
        C2 = {"USE_DYNAMIC_RR_SCALING": "false", "E1_ATR_SL_CAP_MULTIPLIER": "3.5"}
        D3 = {**C2, "SIDEWAYS_BLOCK_THRESHOLD": "45", "MIN_ENTRY_ATR_PERCENTILE": "70"}
        for name, ov in [("BASE", {}), ("C2", C2), ("D3", D3)]:
            rows = run(ov)
            print(f"-- {name} --")
            for q, lo, hi in QTRS:
                qr = [(t, p) for t, p, d, _ in rows if lo <= d <= hi]
                m = full_metrics(qr)
                print(f"   {q} n={m['n']:3d} net={m['net']:+7.0f} PF={m['pf']:.3f} dd={m['dd']:6.0f}")

    elif fam == "cand2":
        print("== STACKED CANDIDATES ROUND 2 (fold in the master ATR-pctile + sideways levers) ==")
        # 'free' robust levers: dynamic-RR off + sideways-block 45 (both help OOS, neutral/positive 2025)
        FREE = {"USE_DYNAMIC_RR_SCALING": "false", "SIDEWAYS_BLOCK_THRESHOLD": "45",
                "E1_ATR_SL_CAP_MULTIPLIER": "3.5"}
        noE2 = {"ENABLE_E2_ENTRIES": "false"}
        report("D0 baseline", {})
        report("D1 FREE", FREE)
        report("D2 FREE dropE2", {**FREE, **noE2})
        report("D3 FREE +ATRpct70", {**FREE, "MIN_ENTRY_ATR_PERCENTILE": "70"})
        report("D4 FREE +ATRpct75", {**FREE, "MIN_ENTRY_ATR_PERCENTILE": "75"})
        report("D5 FREE dropE2 +ATRpct70", {**FREE, **noE2, "MIN_ENTRY_ATR_PERCENTILE": "70"})
        report("D6 FREE dropE2 +ATRpct75", {**FREE, **noE2, "MIN_ENTRY_ATR_PERCENTILE": "75"})

    elif fam == "gates":
        print("== GATE ABLATION (which filters actually earn their keep) ==")
        report("base (all gates on)", {})
        # ADX floors
        for v in ("12", "16", "19.5", "23", "27"):
            report(f"E1_MIN_ADX={v}", {"E1_MIN_MOMENTUM_ADX": v})
        for v in ("14", "18", "20", "24"):
            report(f"E4_MIN_ADX={v}", {"E4_MIN_MOMENTUM_ADX": v})
        # HTF DI spread
        for v in ("2.0", "4.0", "6.0", "8.0"):
            report(f"E1_HTF_DI={v}", {"E1_HTF_MIN_DI_SPREAD": v})
        # trend-quality minimums
        for v in ("0", "4", "6", "8", "10"):
            report(f"min_TQ_E1={v}", {"MIN_TREND_QUALITY_E1": v})
        for v in ("0", "7", "9", "11"):
            report(f"min_TQ_E4={v}", {"MIN_TREND_QUALITY_E4": v})
        # RSI divergence veto
        report("RSI_DIV_VETO off", {"ENABLE_RSI_DIVERGENCE_VETO": "false"})
        # ATR-high regime block + percentile
        report("ATR_HIGH_BLOCK off", {"ENABLE_ATR_HIGH_BLOCK": "false"})
        for v in ("40", "55", "65", "75", "85"):
            report(f"MIN_ATR_PCTILE={v}", {"MIN_ENTRY_ATR_PERCENTILE": v})
        # sideways gate
        for v in ("45", "53", "61", "70"):
            report(f"SIDEWAYS_BLOCK={v}", {"SIDEWAYS_BLOCK_THRESHOLD": v})
        # conviction
        report("CONVICTION_E1=0", {"CONVICTION_THRESHOLD_E1": "0"})
        report("CONVICTION_E4=0", {"CONVICTION_THRESHOLD_E4": "0"})
