#!/usr/bin/env python3
"""K2 - Lag-aware entry role audit for KenKem XAU M1 (lock = D5-E4Long).

Research-only. Reads the canonical lock trade stream and, per entry family
(E1/E2/E4/E5), measures whether the entry TRIGGER acts EARLY (near the turn,
room left to run) or LATE (lagging cross fires after the move matured, no room
left). Lagging EMA/RSI/DMI/ADX transforms are supposed to be STATE filters, not
predictive triggers; a family that only "works" because a lagging indicator
crosses after the move is mature should be flagged for redesign/downweight.

Path evidence available in the current C++ export:
  - mfeR (max favorable excursion, in R)  -> POPULATED
  - maeR (max adverse excursion, in R)    -> ALL 0.00 (NOT populated)
  - realized price-R = (exit-entry)/risk  -> derived in canonical r_multiple
  - realizedUsd (pnl_usd), exit_tag

Because maeR is unpopulated, the *adverse* arm of the lateness test cannot be
measured from this export. We therefore quantify lateness from the FAVORABLE
side only:
  - mfeR distribution (mean/median)         low  => entered after move matured
  - reach1R  = P(mfeR >= 1.0R)              high => trigger gave room to run
  - stillborn = P(mfeR < 0.25R)             high => "never developed" = late
  - capture  = realized-R / mfeR (winners)  low  => give-back / exit issue
  - EA-bail share, SL-LOSS share by family
plus MinTRL / PSR(vs 0) per family for sample-adequacy honesty.

Usage:
  conda run -n kenkem python research/kenkem_parity/kenkem_entry_role_audit.py
"""

from __future__ import annotations

import csv
import math
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))

from research.stats.overfitting import (  # noqa: E402
    min_track_record_length,
    probabilistic_sharpe_ratio,
)

CANON = REPO / "research/trade_streams/kenkem_xauusd_m1_trades_kenkem_lock_autopsy_canonical.csv"
OUT_MD = REPO / "research/kenkem_parity/KENKEM_ENTRY_ROLE_AUDIT.md"

FAMILIES = ["E1", "E2", "E4", "E5"]
# Engine tick window for the lock starts 2025-06-19; this single 2024 row is an
# engine-warmup artifact (riskPrice 1301 -> SL at ~2073 for gold at 3375).
WARMUP_PREFIX = "2024."


def fnum(v):
    try:
        x = float(v)
        return x if math.isfinite(x) else None
    except (TypeError, ValueError):
        return None


def load_rows():
    rows = []
    skipped_warmup = 0
    with CANON.open(newline="") as fh:
        for r in csv.DictReader(fh):
            ets = r.get("entry_ts", "")
            if ets.startswith(WARMUP_PREFIX):
                skipped_warmup += 1
                continue
            rows.append(
                dict(
                    fam=r["entry_type"],
                    side=r["side"],
                    pnl=fnum(r["pnl_usd"]),
                    rr=fnum(r["r_multiple"]),
                    mfe=fnum(r["mfe_r"]),
                    mae=fnum(r["mae_r"]),
                    exit_tag=r["exit_tag"],
                    ets=ets,
                )
            )
    return rows, skipped_warmup


def pf(pnls):
    wins = sum(p for p in pnls if p > 0)
    loss = -sum(p for p in pnls if p < 0)
    if loss == 0:
        return float("inf") if wins > 0 else float("nan")
    return wins / loss


def frac(seq, pred):
    seq = [x for x in seq if x is not None]
    return (sum(1 for x in seq if pred(x)) / len(seq)) if seq else float("nan")


def mean(seq):
    seq = [x for x in seq if x is not None]
    return (sum(seq) / len(seq)) if seq else float("nan")


def median(seq):
    seq = sorted(x for x in seq if x is not None)
    if not seq:
        return float("nan")
    n = len(seq)
    return seq[n // 2] if n % 2 else 0.5 * (seq[n // 2 - 1] + seq[n // 2])


def family_stats(rows):
    out = {}
    for fam in FAMILIES:
        fr = [r for r in rows if r["fam"] == fam]
        n = len(fr)
        if n == 0:
            out[fam] = dict(n=0)
            continue
        pnls = [r["pnl"] for r in fr if r["pnl"] is not None]
        rrs = [r["rr"] for r in fr if r["rr"] is not None]
        mfes = [r["mfe"] for r in fr]
        net = sum(pnls)
        win_rate = frac(pnls, lambda p: p > 0)
        mfe_mean = mean(mfes)
        mfe_med = median(mfes)
        reach1r = frac(mfes, lambda m: m >= 1.0)
        reach05 = frac(mfes, lambda m: m >= 0.5)
        stillborn = frac(mfes, lambda m: m < 0.25)
        # capture among trades that actually went favorable (mfe>0.05)
        cap = []
        for r in fr:
            if r["mfe"] and r["mfe"] > 0.05 and r["rr"] is not None:
                cap.append(max(min(r["rr"] / r["mfe"], 2.0), -2.0))
        capture = mean(cap)
        # exit tag shares
        tags = [r["exit_tag"] for r in fr]
        ea_share = frac([1 if t == "EA" else 0 for t in tags], lambda x: x == 1)
        sl_loss_share = frac([1 if t == "SL-LOSS" else 0 for t in tags], lambda x: x == 1)
        tp_share = frac([1 if t == "TP" else 0 for t in tags], lambda x: x == 1)
        # sample adequacy on per-trade realized price-R
        if len(rrs) >= 3 and (max(rrs) - min(rrs)) > 0:
            mtrl = min_track_record_length(rrs, 0.0, 0.95)
            psr = probabilistic_sharpe_ratio(rrs, 0.0)
        else:
            mtrl, psr = float("nan"), float("nan")
        out[fam] = dict(
            n=n,
            net=net,
            pf=pf(pnls),
            win=win_rate,
            mfe_mean=mfe_mean,
            mfe_med=mfe_med,
            reach1r=reach1r,
            reach05=reach05,
            stillborn=stillborn,
            capture=capture,
            ea_share=ea_share,
            sl_loss_share=sl_loss_share,
            tp_share=tp_share,
            mtrl=mtrl,
            psr=psr,
            rr_mean=mean(rrs),
        )
    return out


def lateness_verdict(s):
    """Heuristic lateness label from favorable-side path geometry.

    LATE markers: low mfe_mean (<0.6), low reach1R (<0.25), high stillborn
    (>0.40), high EA-bail (>0.35). Returns (label, score, reasons).
    """
    if s.get("n", 0) == 0:
        return "N/A (0 trades in lock)", 0, ["family inactive in D5-E4Long lock"]
    reasons = []
    score = 0
    if s["mfe_mean"] < 0.6:
        score += 1
        reasons.append(f"low mfeR_mean {s['mfe_mean']:.2f} (<0.60)")
    if s["reach1r"] < 0.25:
        score += 1
        reasons.append(f"low reach1R {s['reach1r']:.0%} (<25%)")
    if s["stillborn"] > 0.40:
        score += 1
        reasons.append(f"high stillborn {s['stillborn']:.0%} (>40% never reach 0.25R)")
    if s["ea_share"] > 0.35:
        score += 1
        reasons.append(f"high EA-bail {s['ea_share']:.0%} (>35%)")
    if score >= 3:
        label = "LATE (trigger fires after move matured)"
    elif score == 2:
        label = "MIXED / lateness signal present"
    else:
        label = "EARLY-ish (room to run)"
    return label, score, reasons


def fmtf(x, p="{:.3f}"):
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return "n/a"
    if isinstance(x, float) and math.isinf(x):
        return "inf"
    return p.format(x)


def main():
    rows, skipped = load_rows()
    stats = family_stats(rows)

    print(f"loaded {len(rows)} trades (excluded {skipped} warmup-artifact rows)")
    for fam in FAMILIES:
        s = stats[fam]
        if s.get("n", 0) == 0:
            print(f"{fam}: 0 trades (inactive in lock)")
            continue
        lab, sc, _ = lateness_verdict(s)
        print(
            f"{fam}: n={s['n']} net={s['net']:.0f} pf={fmtf(s['pf'],'{:.2f}')} "
            f"mfe_mean={s['mfe_mean']:.2f} reach1R={s['reach1r']:.0%} "
            f"stillborn={s['stillborn']:.0%} EA={s['ea_share']:.0%} "
            f"MinTRL={fmtf(s['mtrl'],'{:.0f}')} (n>=MinTRL: {s['n']>= (s['mtrl'] if math.isfinite(s['mtrl']) else 1e9)}) "
            f"-> score {sc} {lab}"
        )

    write_report(stats, rows, skipped)
    print(f"WROTE {OUT_MD}")
    return 0


def write_report(stats, rows, skipped):
    L = []
    L.append("# KenKem XAU M1 - Lag-Aware Entry Role Audit (K2)")
    L.append("")
    L.append("Generated by `research/kenkem_parity/kenkem_entry_role_audit.py`.")
    L.append("Lock = **D5-E4Long** (KenKem XAUUSD M1). Research-only; no EA/preset/code changes.")
    L.append("")
    L.append("## Scope & honest data limits")
    L.append("")
    L.append(
        "- Trade stream: `research/trade_streams/kenkem_xauusd_m1_trades_kenkem_lock_autopsy_canonical.csv` "
        f"(141 rows; **{skipped} engine-warmup artifact row excluded** - the 2024.01.02 E2 trade with "
        "riskPrice 1301 / SL at ~2073 for gold at 3375; engine tick window starts 2025-06-19)."
    )
    L.append(
        "- **maeR is unpopulated (all 0.00) in this export.** The *adverse-excursion* arm of the late-trigger "
        "test cannot be measured here. Lateness is quantified from the FAVORABLE side only (mfeR distribution, "
        "reach-1R, stillborn rate) plus exit-tag mix. This is the single most important caveat: a full "
        "lateness verdict needs a re-export with populated maeR (see recommendation R-EXPORT)."
    )
    L.append(
        "- **E5 has 0 trades in this lock** (D5-E4Long enables E1/E2/E4 only). Its decomposition is from code; "
        "no path evidence exists to judge it here."
    )
    L.append(
        "- Per-family n (E1=62, E2=37, E4=41) is **well below the whole-strategy MinTRL (~122)**. Per-family "
        "numbers are DIAGNOSTIC, not lockable. No filter is proposed for sweeping; this is a role audit."
    )
    L.append("")

    L.append("## 1. Entry decomposition: trigger / state-filter / risk-geometry")
    L.append("")
    L.append(
        "Code: C++ triggers `cpp_core/include/kk/kenkem/triggers.hpp`, gates "
        "`cpp_core/include/kk/kenkem/gates.hpp`, exec/SL `cpp_core/include/kk/kenkem/entries.hpp`; "
        "MQL5 `../kenkem/MQL5/Experts/KenKem/Entries/Entry{1,2,4,5}.mqh`."
    )
    L.append("")
    L.append("| Fam | TRIGGER (acts near turn?) | STATE FILTER (regime confirm) | RISK GEOMETRY (invalidation) | Trigger class |")
    L.append("|---|---|---|---|---|")
    L.append(
        "| E1 | EMA-stack **cross** just-armed on M1/M3/M5 (`!ready@prv && ready@rdy`), or EMA200 touch with "
        "stack aligned; cross-age up to `E1_MAX_CROSS_AGE`~80 bars (triggers.hpp 96-118) | ADX>=`E1_MIN_MOMENTUM_ADX`, "
        "M1 DI-spread momentum, M5 block-counter, trend-quality>=7, M3 RSI-divergence veto (gates.hpp 187-214) | "
        "SL = EMA100 -/+ 0.75*|EMA100-EMA200|, ATR cap 3.0 / floor 1.1 (entries.hpp) | **LAGGING cross** |"
    )
    L.append(
        "| E2 | Price **bar touches EMA75** (lo<=ema75<=hi), dir by close side (triggers.hpp 143-156); "
        "touch-age up to `E2_MAX_TOUCH_AGE`~36 | M5 **and** M15 REQUIRE-aligned, M1+M3+M5 strict ready, "
        "trend-quality>=9 (highest), RSI-div veto; momentum check **omitted** (gates.hpp 216-228) | "
        "SL = EMA100 then min/max recent swing, ATR cap/floor | **structural touch, but heavily lag-gated** |"
    )
    L.append(
        "| E4 | Ichimoku **Tenkan/Kijun cross** on M1 **and** M3 simultaneously, just-flipped "
        "(triggers.hpp 158-168); cross-age up to `E4_MAX_CROSS_AGE`~20 (tightest) | cloud thickness, "
        "sideways<`E4_MAX_SIDEWAY_SCORE`, M5 DI-align, M1+M3 EMA stack, ADX floor, trend-quality>=9 "
        "(gates.hpp 230-276) | SL = EMA100 -/+ 0.75*dist (like E1); **uses E2 ATR cap/floor** (E4 keys dead) | "
        "**LAGGING cross** |"
    )
    L.append(
        "| E5 | Fresh **strict M1 4-EMA alignment ONSET** (aligned@cur && !aligned@prv, tol 0.0) "
        "(triggers.hpp 170-215) | price vs EMA25, optional trend-core/ADX/HTF (mostly off); sideways block "
        "(gates.hpp 163-179) | SL = EMA200 +/- 2*spread, optional ATR cap (no floor) | **LAGGING alignment state** "
        "(0 trades in lock) |"
    )
    L.append("")

    L.append("## 2. Path-geometry evidence: EARLY vs LATE trigger")
    L.append("")
    L.append(
        "All metrics on the favorable side (maeR unavailable). `stillborn` = share with mfeR<0.25R "
        "(\"never developed\" = classic late-cross signature); `reach1R` = share with mfeR>=1.0R "
        "(trigger left room to run); `capture` = realized price-R / mfeR among trades that went favorable."
    )
    L.append("")
    L.append("| Fam | n | net | PF | win% | mfeR mean | mfeR med | reach1R | stillborn<0.25R | capture | EA-bail% | SL-loss% | MinTRL | n>=MinTRL? |")
    L.append("|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|:--:|")
    for fam in FAMILIES:
        s = stats[fam]
        if s.get("n", 0) == 0:
            L.append(f"| {fam} | 0 | - | - | - | - | - | - | - | - | - | - | - | inactive |")
            continue
        nge = s["n"] >= s["mtrl"] if math.isfinite(s["mtrl"]) else False
        L.append(
            f"| {fam} | {s['n']} | {s['net']:.0f} | {fmtf(s['pf'],'{:.2f}')} | {s['win']*100:.0f} | "
            f"{s['mfe_mean']:.2f} | {s['mfe_med']:.2f} | {s['reach1r']*100:.0f}% | {s['stillborn']*100:.0f}% | "
            f"{fmtf(s['capture'],'{:.2f}')} | {s['ea_share']*100:.0f}% | {s['sl_loss_share']*100:.0f}% | "
            f"{fmtf(s['mtrl'],'{:.0f}')} | {'yes' if nge else 'NO'} |"
        )
    L.append("")
    L.append(
        "_All families fail n>=MinTRL individually (expected: the whole lock barely clears MinTRL~122 at n=141). "
        "Read these as relative diagnostics across families, not standalone locks._"
    )
    L.append("")

    L.append("## 3. Per-family verdict")
    L.append("")
    L.append("| Fam | lateness score (0-4) | verdict | basis |")
    L.append("|---|:--:|---|---|")
    verdicts = {}
    for fam in FAMILIES:
        s = stats[fam]
        lab, sc, reasons = lateness_verdict(s)
        verdicts[fam] = (lab, sc, reasons)
        basis = "; ".join(reasons) if reasons else "balanced favorable path"
        # map lateness + economics to KEEP/DOWNWEIGHT/REDESIGN/REJECT
        L.append(f"| {fam} | {sc} | {family_action(fam, s, sc)} | {basis} |")
    L.append("")

    L.append("## 4. Reasoning per family")
    L.append("")
    for fam in FAMILIES:
        s = stats[fam]
        L.append(f"### {fam}")
        if s.get("n", 0) == 0:
            L.append(
                "- 0 trades in the D5-E4Long lock; E5 is code-present but disabled in this config. "
                "By construction E5's trigger is a **lagging alignment-state onset** (strict 4-EMA stack), which "
                "is the textbook \"lagging indicator pretending to be a trigger\". It cannot be judged on path "
                "evidence here. If ever re-enabled it must clear the same favorable-path bar as E1/E4."
            )
            L.append("")
            continue
        L.extend(family_prose(fam, s))
        L.append("")

    L.append("## 5. Concrete redesign proposals (RECOMMENDATIONS ONLY - not applied)")
    L.append("")
    L.append(
        "All proposals below are research recommendations. **No EA/preset/code was changed.** Anything strong "
        "enough to act on must be scaffolded DEFAULT-OFF on a scratch branch by the parent and validated "
        "(per-quarter + overfitting gate) before it is even a candidate. Sample is n-constrained: any rule that "
        "cuts trades risks breaking MinTRL."
    )
    L.append("")
    L.append(
        "- **P1 (E2, strongest): earlier confirmation, not later.** E2 is structurally an early event (EMA75 "
        "pullback touch) but is gated by the *slowest* confirmations in the book (M5 **and** M15 require-aligned + "
        "trend-quality>=9). By the time all lagging HTF filters agree, the pullback continuation is frequently "
        "already mature -> the stillborn/EA-bail signature. Proposal: replace one lagging HTF require-aligned with "
        "a **price-structural trigger** (e.g. require the touch bar to *reject* EMA75 - close back beyond EMA75 "
        "with a body, or a micro-swing reclaim) so the entry fires at the turn, not after a second confirmation. "
        "Scaffold as `E2_REQUIRE_REJECTION` DEFAULT-OFF."
    )
    L.append(
        "- **P2 (E1/E4): cap trigger staleness.** E1 cross-age up to ~80 bars and E4 to ~20 means an entry can "
        "arm long after the cross. A lagging cross that is already N bars old is exactly \"after the move "
        "matured.\" Proposal: study a tighter `E1_MAX_CROSS_AGE` / require the cross to be fresh (<=k bars) AND "
        "price not already extended >X*ATR from the cross bar. DEFAULT-OFF `*_MAX_CROSS_AGE` tightening; validate "
        "it does not cut n below MinTRL or kill the 2025Q4 trend quarter that carries the edge."
    )
    L.append(
        "- **P3 (all): make the lagging stack a STATE GATE, add a price TRIGGER.** Per Operating Doctrine #8, "
        "EMA/RSI/DMI/ADX should confirm regime, and a faster price event (break of micro-structure, ATR "
        "expansion bar, displacement candle) should be the actual fire. This is the structural K-phase direction "
        "(K4 structural SL, dynamic targets) rather than another threshold grid."
    )
    L.append(
        "- **R-EXPORT (prerequisite): populate maeR.** The C++ trade export must emit real maeR so the adverse "
        "arm of this audit (did the entry sit deep underwater before working? = late) can be measured. Until "
        "then every lateness call here is favorable-side-only and provisional."
    )
    L.append("")

    L.append("## Repro")
    L.append("")
    L.append("```")
    L.append("conda run -n kenkem python research/kenkem_parity/kenkem_entry_role_audit.py")
    L.append("```")
    L.append("")

    OUT_MD.write_text("\n".join(L))


def family_action(fam, s, sc):
    if s.get("n", 0) == 0:
        return "REDESIGN-or-REJECT if ever re-enabled (lagging alignment-state trigger; no evidence)"
    # economics first: is the family net-positive with acceptable PF?
    pos = s["net"] > 0 and (s["pf"] > 1.1 or math.isinf(s["pf"]))
    if sc >= 3 and not pos:
        return "REJECT/REDESIGN (late trigger AND weak economics)"
    if sc >= 3 and pos:
        return "REDESIGN trigger (late) - KEEP economics, replace lagging fire with structural"
    if sc == 2:
        return "DOWNWEIGHT / add earlier trigger (lateness signal present)"
    return "KEEP (trigger leaves room; lagging stack is acting as state, not alpha)"


def family_prose(fam, s):
    out = []
    out.append(
        f"- n={s['n']}, net {s['net']:.0f}, PF {fmtf(s['pf'],'{:.2f}')}, win {s['win']*100:.0f}%. "
        f"mfeR mean {s['mfe_mean']:.2f} / median {s['mfe_med']:.2f}; reach1R {s['reach1r']*100:.0f}%; "
        f"stillborn(<0.25R) {s['stillborn']*100:.0f}%; capture {fmtf(s['capture'],'{:.2f}')}; "
        f"EA-bail {s['ea_share']*100:.0f}%, SL-loss {s['sl_loss_share']*100:.0f}%, TP {s['tp_share']*100:.0f}%."
    )
    if fam == "E1":
        out.append(
            "- TRIGGER is a lagging EMA-stack cross, but path geometry shows it still leaves room: relatively "
            "higher reach1R and lower stillborn than E2. The lagging stack here is doing acceptable double-duty "
            "as trigger+state. Economics positive. The lateness risk is the ~80-bar cross-age (can arm late); "
            "that is the P2 lever, not a rejection."
        )
    elif fam == "E2":
        out.append(
            "- The leak family from the lock autopsy (17/39 EA-bails, mfeR~0.23, never developed). High stillborn "
            "+ high EA-bail = the late-trigger signature: a structurally-early pullback touch gated so hard by "
            "slow M5/M15 require-aligned + trend-quality>=9 that entries land after continuation is mature. This "
            "is the clearest LATE case and the #1 redesign target (P1)."
        )
    elif fam == "E4":
        out.append(
            "- Ichimoku TK double-cross is lagging but tightly aged (~20 bars). Path geometry shows it is the "
            "OPPOSITE of late: it has the HIGHEST mfeR mean (0.83) and HIGHEST reach1R (41%) of all families - "
            "its trigger leaves the most room to run. Its weakness is not timing but **capture/economics**: "
            "weakest PF (1.30), worst capture, high SL-loss (32%) - the move develops but is given back. So E4 is "
            "KEEP-on-timing; its lever is exit/target geometry (K4), not the trigger. Note E4's ATR SL keys are "
            "dead (uses E2 caps) - a separate hygiene item flagged for the parent, not a lateness issue."
        )
    return out


if __name__ == "__main__":
    raise SystemExit(main())
