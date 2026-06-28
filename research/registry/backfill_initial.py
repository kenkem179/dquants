#!/usr/bin/env python3
"""Back-fill the experiment registry with the experiments already decided (R3 done-when:
"immediately useful"). Idempotent — re-running overwrites the same content-derived yaml files.

Every number below is transcribed from a source-of-record (docs/BUILD-PLAN(-ARCHIVED).md,
HANDOFF.md, ~/.claude memory facts, research/execution/COST_HEADROOM_GATE_2026-06-28.md).
Where a field is genuinely unknown it is left None -> yaml null -> blank in index.csv.
NOTHING is fabricated; blank != zero. `source_refs` records provenance for each row.

Run:  conda run -n kenkem python research/registry/backfill_initial.py
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from registry import make_record, append_row, rebuild_index  # noqa: E402

ENGINE_COST = ("C++ tick engine: modeled spread from feed; NO commission/slippage/swap. "
               "Engine over-credits runner/E4 exits -> ranking proxy, not P&L truth.")
MT5_COST = ("MT5 Strategy Tester every-tick, real broker spread; commission/swap per tester "
            "account. Final exit judge.")

RECORDS = [
    # ---------------- LOCKS ----------------
    dict(
        strategy="kenkem", symbol="XAUUSD", timeframe="M1", decision="LOCK",
        label="d5-e4long", date="2026-06-22", hypothesis_id="K1/D5-E4Long",
        train_start="2025-03", train_end="2026-05", oos_start="2026-01", oos_end="2026-05",
        commit_hash=None, data_source="ticks_xau_full.csv (XAU M1, 2025-03..2026-05)",
        set_path="mql5/experts/Presets/KK-KenKem/KK-KenKem-XAUUSD-M1-D5-E4Long.set",
        cost_model=MT5_COST, n_trials=None, sr_trial_std=None,
        net_usd=1427, pf=1.428, max_dd_pct=None, sharpe=None, n_trades=126, win_pct=None,
        psr=0.953, dsr=None, mintrl=122, mintrl_sufficient=True, pbo=None, gate_verdict="PASS",
        mt5_confirmed=True,
        artifacts=["research/kenkem_parity/KK-KenKem-XAUUSD-M1-D5-E4Long.set"],
        supersedes="kenkem-xauusd-m1-lock-d3-noe4",
        notes=("CURRENT KenKem lock (released 1.03). E1+E2+E4-long (E4_LONG_ONLY=true). "
               "OOS 2026 +497/PF1.523; MC P(profit) 94.9%, netP5 -7. GATE PASS PSR 0.953, "
               "MinTRL 122<126. E4 engine exits fictional -> E1 carries the book."),
        source_refs=["memory:best-experts-release-table", "memory:kenkem-e1-efficiency-ratio-weak"],
    ),
    dict(
        strategy="kenkem", symbol="XAUUSD", timeframe="M1", decision="LOCK",
        label="d3-noe4", date="2026-06-20", hypothesis_id="K1/D3-noE4",
        train_start="2025-03", train_end="2026-05", oos_start="2026-01", oos_end="2026-05",
        commit_hash="fc448b1", data_source="ticks_xau_full.csv (XAU M1, 2025-03..2026-05)",
        set_path="mql5/experts/Presets/KK-KenKem/KK-KenKem-XAUUSD-M1-D3-noE4.set",
        cost_model=MT5_COST, n_trials=None, sr_trial_std=None,
        net_usd=1049, pf=1.39, max_dd_pct=None, sharpe=None, n_trades=102, win_pct=None,
        psr=0.92, dsr=None, mintrl=139, mintrl_sufficient=False, pbo=None, gate_verdict="WARN",
        mt5_confirmed=True,
        artifacts=["research/kenkem_parity/mt5_runs/2026-06-20_D3-noE4/"],
        superseded_by="kenkem-xauusd-m1-lock-d5-e4long",
        notes=("Prior KenKem lock, MT5-confirmed +1049/PF1.39. E4 OFF (engine E4 exits fictional). "
               "OOS 2026 +327/PF1.47; profitable quarters 4/6. Gate WARN: MinTRL 139>102 (sample "
               "too short). Superseded by D5-E4Long. .set must be flush-left for MT5 Load."),
        source_refs=["memory:kenkem-xau-d3-opt-lock", "memory:best-experts-release-table"],
    ),
    dict(
        strategy="mastervp", symbol="XAUUSD", timeframe="M5", decision="LOCK",
        label="progtrail-ladder", date="2026-06-26", hypothesis_id="M5/H9-ProgTrail",
        train_start="2025-06", train_end="2026-05", oos_start="2026-01", oos_end="2026-05",
        commit_hash="c64a34e", data_source="XAU M5 ticks 2025.06-2026.05 ($10k every-tick)",
        set_path="mql5/experts/Presets/KK-MasterVP/KK-MasterVP-XAUUSD-M5.set",
        cost_model=MT5_COST, n_trials=36, sr_trial_std=0.0135,
        net_usd=86034, pf=1.4246, max_dd_pct=None, sharpe=0.109, n_trades=1423, win_pct=None,
        psr=1.000, dsr=1.000, mintrl=192, mintrl_sufficient=True, pbo=None, gate_verdict="PASS",
        mt5_confirmed=True,
        artifacts=["research/mastervp_parity/H9_results/"],
        supersedes="mastervp-xauusd-m5-lock-rr4-trail275",
        notes=("CURRENT MasterVP lock. Adds ProgTrail late-arm ladder Trigger 2.0R/Inc 0.75/"
               "Step 0.2 on RR4/Trail2.75 base. net flat-risk +86,034 vs prior 83,228 (+3.4%), "
               "gain concentrated in 2026 (1.4372->1.4581). GATE DSR 1.000 PASS. WARN: InpPmProg* "
               "are HIDDEN globals -> baked as compiled defaults, .set can't drive prod EA. "
               "Pending 1 production-EA confirmation run."),
        source_refs=["memory:mastervp-progtrail-ladder-lock", "memory:best-experts-release-table"],
    ),
    dict(
        strategy="mastervp", symbol="XAUUSD", timeframe="M5", decision="LOCK",
        label="rr4-trail275", date="2026-06-25", hypothesis_id="M5/runner-RR4",
        train_start="2025-06", train_end="2026-05", oos_start="2026-01", oos_end="2026-05",
        commit_hash=None, data_source="XAU M5 ticks 2025.06-2026.05 ($10k every-tick)",
        set_path="mql5/experts/Presets/KK-MasterVP/KK-MasterVP-XAUUSD-M5.set",
        cost_model=MT5_COST, n_trials=336, sr_trial_std=None,
        net_usd=83227, pf=1.413, max_dd_pct=21.1, sharpe=0.108, n_trades=1423, win_pct=52.6,
        psr=1.000, dsr=1.000, mintrl=198, mintrl_sufficient=True, pbo=None, gate_verdict="PASS",
        mt5_confirmed=True,
        artifacts=["research/mastervp_parity/mt5_runs/2026-06-25_xau_m5_RR4_T2.75_confirm/"],
        superseded_by="mastervp-xauusd-m5-lock-progtrail-ladder",
        notes=("RunnerRr 4.0 / TrailAtrMult 2.75 / BeBufAtr 0.02 (no ladder). net flat-risk 83,227 "
               "(compounded +87,836) / PF 1.413 / maxDD 21.1%. Decisive: 231-pass fine trail sweep "
               "showed Trail 2.75>>2.5 (invisible to step-1.0 grid). GATE DSR 1.000 (n_trials=336). "
               "Superseded by ProgTrail ladder."),
        source_refs=["memory:mastervp-runner5-bebuf-lock"],
    ),
    dict(
        strategy="monster", symbol="BTCUSD", timeframe="M3", decision="LOCK",
        label="anti-chase", date="2026-06-20", hypothesis_id="Monster/anti-chase",
        train_start=None, train_end=None, oos_start=None, oos_end=None,
        commit_hash=None, data_source="BTCUSD M3 (Exness MT5 feed, full 2026)",
        set_path="mql5/experts/Presets/KK-MasterVP-Monster/KK-MasterVP-Monster-BTCUSD.set",
        cost_model=ENGINE_COST + " 6-fold WF + MC(20k). MT5 NOT confirmed (engine-only lock).",
        n_trials=None, sr_trial_std=None,
        net_usd=5444, pf=1.199, max_dd_pct=10.6, sharpe=None, n_trades=375, win_pct=None,
        psr=None, dsr=None, mintrl=None, mintrl_sufficient=None, pbo=None, gate_verdict=None,
        mt5_confirmed=False,
        artifacts=["research/monster_parity/wf_monster.py"],
        notes=("Engine WF lock: InpBreakMaxAtr 5->3 + InpBreakBufAtr 0.25->0.1. Pooled PF "
               "1.140->1.199, net +31%, maxDD 13.7->10.6%, worst-fold 1.099, 6/6 folds. MC "
               "P(profit) 97.1%, PF5th 1.035; 99th-pctile DD 30.5% (size for 30-40% peak). "
               "NOT MT5-confirmed: MT5 had it marginal ~PF1.03; Monster edition RETIRED 2026-06-22 "
               "(impulse delta folded into KK-MasterVP InpEnableImpulse, default OFF). Engine "
               "param-opt ceiling ~PF1.20; user's TV 'crazily profitable' gap is structural (feed)."),
        source_refs=["memory:monster-anti-chase-opt-locked", "memory:best-experts-release-table"],
    ),
    # ---------------- REJECTS ----------------
    dict(
        strategy="mastervp", symbol="BTCUSD", timeframe="M5", decision="REJECT",
        label="no-robust-edge", date="2026-06-27", hypothesis_id="M7/BTC-M5",
        train_start="2025-01", train_end="2026-06", oos_start="2026-04", oos_end="2026-06",
        commit_hash=None, data_source="BTCUSD M5 (Exness MT5 feed, Jan25-Jun26)",
        set_path="mql5/experts/Presets/KK-MasterVP/KK-MasterVP-BTCUSD-M5.set",
        cost_model=ENGINE_COST + " + MT5 disconfirm run.",
        n_trials=None, sr_trial_std=None,
        net_usd=-1892, pf=1.058, max_dd_pct=None, sharpe=None, n_trades=None, win_pct=None,
        psr=None, dsr=None, mintrl=None, mintrl_sufficient=None, pbo=None, gate_verdict="FAIL",
        mt5_confirmed=True,
        artifacts=["research/mastervp_parity/btc_revisit_2026-06-27/",
                   "research/mastervp_parity/btc_exit_resweep_2026-06-27/"],
        notes=("CLOSED. Full window (Jan25-Jun26) net -1,892 LOSER; engine OOS PF 1.214 but MT5 "
               "disconfirms PF 1.058. WF 3/6 folds+, recent fold negative. Regime-dependent (only "
               "2025H1 loses) but not release-grade; no regime lever rescues it. Per-trade autopsy: "
               "ADX/diSpread/brkDistAtr/spreadAtr all non-monotone. PF/net are MT5-disconfirm numbers."),
        source_refs=["memory:btc-no-robust-edge-closed", "memory:best-experts-release-table"],
    ),
    dict(
        strategy="mastervp", symbol="BTCUSD", timeframe="M3", decision="REJECT",
        label="overfit-oos-collapse", date="2026-06-27", hypothesis_id="M7/BTC-M3",
        train_start="2025-01", train_end="2026-06", oos_start="2026-01", oos_end="2026-06",
        commit_hash=None, data_source="BTCUSD M3 (Exness MT5 feed)",
        set_path=None, cost_model=ENGINE_COST,
        n_trials=None, sr_trial_std=None,
        net_usd=None, pf=0.668, max_dd_pct=81.0, sharpe=None, n_trades=None, win_pct=None,
        psr=None, dsr=None, mintrl=None, mintrl_sufficient=None, pbo=None, gate_verdict="FAIL",
        mt5_confirmed=False,
        artifacts=["research/mastervp_parity/btc_revisit_2026-06-27/"],
        notes=("DEAD. Train-fittable to PF 1.09 but OOS-catastrophic PF 0.668, 81% DD; train-up => "
               "OOS-down anti-correlated; broad scan ZERO PF>1 OOS at any master/ADX/SL/trail. Pure "
               "overfit. Do not re-sweep VP-length/ADX/SL/trail/reversion."),
        source_refs=["memory:btc-no-robust-edge-closed", "archive:H7-BTC-M3"],
    ),
    dict(
        strategy="kenkem", symbol="XAUUSD", timeframe="M3", decision="REJECT",
        label="rr-rescale-overfit", date="2026-06-27", hypothesis_id="K1/M3-extension",
        train_start="2025-03", train_end="2026-05", oos_start="2025-Q4", oos_end="2026",
        commit_hash=None, data_source="XAU M3 bars on 3x-clock proxy (M9/M15/M45 HTF)",
        set_path=None, cost_model=ENGINE_COST + " M1-base engine resampled x3 (research proxy).",
        n_trials=None, sr_trial_std=None,
        net_usd=1600, pf=1.22, max_dd_pct=None, sharpe=None, n_trades=217, win_pct=None,
        psr=None, dsr=None, mintrl=122, mintrl_sufficient=True, pbo=None, gate_verdict="FAIL",
        mt5_confirmed=False,
        artifacts=["research/kenkem_parity/m3_sweep/M3_SWEEP_FINDINGS_2026-06-27.md"],
        notes=("REJECT. Sample not the blocker (217 tr > MinTRL 122). M3 E1-dominant; only RR moves "
               "train PF but RR lift OVERFITS: OOS (2025Q4+2026) PF 0.81-0.88, net-negative at every "
               "RR. Worse than M1 lock on full window too (best PF 1.22/net 1.6k/maxDD 1391 vs M1 "
               "PF 1.33/net 3.5k/maxDD 512). Strict-alignment+gate hypothesis did not pan out. Accept "
               "KenKem M1-only. (PF/net shown = best M3 config, still rejected.)"),
        source_refs=["memory:kenkem-m3-sweep-rejected"],
    ),
    dict(
        strategy="kenkem", symbol="XAUUSD", timeframe="M1", decision="REJECT",
        label="e1-efficiency-ratio", date="2026-06-22", hypothesis_id="K1/E1-ER-filter",
        train_start="2025-03", train_end="2026-05", oos_start="2026-01", oos_end="2026-05",
        commit_hash="6bca71b", data_source="ticks_xau_full.csv (XAU M1)",
        set_path=None, cost_model=ENGINE_COST + " (E1 book only is trustworthy).",
        n_trials=None, sr_trial_std=None,
        net_usd=None, pf=None, max_dd_pct=None, sharpe=None, n_trades=21, win_pct=None,
        psr=None, dsr=None, mintrl=None, mintrl_sufficient=False, pbo=None, gate_verdict="FAIL",
        mt5_confirmed=False,
        artifacts=["research/optimization/KENKEM-E1-EFFICIENCY-RATIO-2026-06-22.md"],
        notes=("WEAK, NOT locked -> default-OFF infra. Kaufman Efficiency-Ratio chop filter on E1. "
               "Full D5-E4Long book pooled net NEGATIVE at every ER_MIN. 2026-OOS gain real in the "
               "trustworthy E1 book but a NARROW small-n spike (gain only 0.20-0.25, gone at "
               "0.15/0.30, n=21 OOS-E1) not a plateau; per-trade Sharpe +2.6% only. D6-E1ER.set is "
               "ENGINE-ONLY (EA lacks the filter). Revisit only if a wider re-sweep makes it a plateau."),
        source_refs=["memory:kenkem-e1-efficiency-ratio-weak"],
    ),
    # ---------------- STOPs (Codex pre-gates) ----------------
    dict(
        strategy="mastervp", symbol="BTCUSD", timeframe="M3", decision="STOP",
        label="event-taxonomy-pregate", date="2026-06-28", hypothesis_id="M1a/Codex-Step-5",
        train_start=None, train_end=None, oos_start=None, oos_end=None,
        commit_hash="78187ba", data_source="canonical BTC M3 trade stream (478 trades)",
        set_path=None, cost_model=ENGINE_COST + " model-free mfeR + realized usd autopsy.",
        n_trials=None, sr_trial_std=None,
        net_usd=-75.30, pf=0.995, max_dd_pct=-19.5, sharpe=None, n_trades=478, win_pct=57.3,
        psr=None, dsr=None, mintrl=None, mintrl_sufficient=None, pbo=None, gate_verdict=None,
        mt5_confirmed=False,
        artifacts=["research/mastervp_parity/btc_m3_event_taxonomy_2026-06-28/BTC_M3_EVENT_TAXONOMY.md"],
        notes=("STOP. Pre-gate before any new BTC M3 sweep. Stream breakeven/negative (478 tr, PF "
               "0.995). brkDistAtr/adx/diSpread/runwayAtr/nodeNet/spreadAtr all non-monotone -> no "
               "structural pre-entry variable earns a sweep. No new BTC M3 alpha build justified."),
        source_refs=["docs:BTC_M3_EVENT_TAXONOMY", "HANDOFF:Codex-Step-5"],
    ),
    dict(
        strategy="mastervp", symbol="BTCUSD", timeframe="M3", decision="STOP",
        label="cost-headroom-gate", date="2026-06-28", hypothesis_id="R5a/Codex-Step-8",
        train_start=None, train_end=None, oos_start=None, oos_end=None,
        commit_hash="78187ba", data_source="trades_cpp_btcusd_2025_M3.csv (478 trades)",
        set_path=None,
        cost_model="Offline fixed-USD cost stress (research/execution/cost_model.py); +1..50 USD/trade.",
        n_trials=None, sr_trial_std=None,
        net_usd=-75.30, pf=0.995, max_dd_pct=-19.5, sharpe=-0.0016, n_trades=478, win_pct=57.3,
        psr=None, dsr=None, mintrl=None, mintrl_sufficient=None, pbo=None, gate_verdict=None,
        mt5_confirmed=False,
        artifacts=["research/execution/COST_HEADROOM_GATE_2026-06-28.md"],
        notes=("STOP for BTC. No cost headroom: mean PnL/trade -0.158; +1 USD/trade -> net -553.30 / "
               "PF 0.97. Higher-precision cost work BLOCKED: exports lack lot/commission/slippage/"
               "exit_ts. Do not spend search budget on BTC M3 params."),
        source_refs=["docs:COST_HEADROOM_GATE_2026-06-28", "HANDOFF:Codex-Step-8"],
    ),
    # ---------------- KenKem VP overlay pre-gates ----------------
    dict(
        strategy="kenkem", symbol="XAUUSD", timeframe="M1", decision="STOP",
        label="vp-candidate-rules", date="2026-06-28", hypothesis_id="K1b/Codex-Step-4",
        train_start="2025-03", train_end="2026-05", oos_start=None, oos_end=None,
        commit_hash="78187ba",
        data_source="D5-E4Long autopsy stream + causal rolling/session tick-activity VP",
        set_path=None, cost_model=ENGINE_COST + " VP entry-location cells; MinTRL + quarter robustness.",
        n_trials=None, sr_trial_std=None,
        net_usd=None, pf=None, max_dd_pct=None, sharpe=None, n_trades=141, win_pct=None,
        psr=None, dsr=None, mintrl=None, mintrl_sufficient=False, pbo=None, gate_verdict=None,
        mt5_confirmed=False,
        artifacts=["research/kenkem_parity/vp_entry_audit/KENKEM_M1_VP_CANDIDATE_RULES.md"],
        notes=("STOP. Do not change KenKem EA. VP-location hard filters either fail MinTRL or remain "
               "quarter-sensitive. VP may be useful as unified event schema or sizing/state variable, "
               "NOT an entry filter."),
        source_refs=["docs:KENKEM_M1_VP_CANDIDATE_RULES", "HANDOFF:Codex-Step-4"],
    ),
    dict(
        strategy="kenkem", symbol="XAUUSD", timeframe="M1", decision="STOP",
        label="vp-sizing-overlay", date="2026-06-28", hypothesis_id="K1c/Codex-Step-7",
        train_start="2025-03", train_end="2026-05", oos_start=None, oos_end=None,
        commit_hash="78187ba",
        data_source="D5-E4Long base stream (141 trades) + walk-forward VP cell sizing",
        set_path=None, cost_model=ENGINE_COST + " walk-forward-by-quarter VP risk-weighting overlay.",
        n_trials=None, sr_trial_std=None,
        net_usd=1847.38, pf=1.483, max_dd_pct=None, sharpe=None, n_trades=141, win_pct=None,
        psr=None, dsr=None, mintrl=None, mintrl_sufficient=None, pbo=None, gate_verdict=None,
        mt5_confirmed=False,
        artifacts=["research/kenkem_parity/vp_sizing_overlay/KENKEM_M1_VP_SIZING_OVERLAY.md"],
        notes=("STOP. Do not implement KenKem VP sizing. Base 141 tr net 1987.64 / PF 1.517; "
               "walk-forward cell-sizing overlay FALLS to net 1847.38 / PF 1.483. The stronger "
               "EntryVP_diagnostic result is IN-SAMPLE only. (net/pf shown = the rejected overlay.)"),
        source_refs=["docs:KENKEM_M1_VP_SIZING_OVERLAY", "HANDOFF:Codex-Step-7"],
    ),
    # ---------------- RESEARCH-ONLY audits ----------------
    dict(
        strategy="kenkem", symbol="XAUUSD", timeframe="M1", decision="RESEARCH-ONLY",
        label="vp-entry-audit", date="2026-06-28", hypothesis_id="K1a/Codex-Step-3",
        train_start="2025-03", train_end="2026-05", oos_start=None, oos_end=None,
        commit_hash="78187ba",
        data_source="D5-E4Long trade stream joined to causal rolling/session tick-activity VP",
        set_path=None, cost_model=ENGINE_COST + " audit only (no entry-logic change).",
        n_trials=None, sr_trial_std=None,
        net_usd=None, pf=None, max_dd_pct=None, sharpe=None, n_trades=141, win_pct=None,
        psr=None, dsr=None, mintrl=None, mintrl_sufficient=None, pbo=None, gate_verdict=None,
        mt5_confirmed=False,
        artifacts=["research/kenkem_parity/vp_entry_audit/KENKEM_M1_VP_ENTRY_AUDIT.md"],
        notes=("RESEARCH-ONLY first-pass audit. Causal rolling VP location MAY differentiate "
               "entry-family quality, but proceed to VP rules only if VP context explains MFE/MAE or "
               "reduces chop losses without cutting sample below MinTRL. Fed K1b/K1c (both STOP)."),
        source_refs=["docs:KENKEM_M1_VP_ENTRY_AUDIT", "HANDOFF:Codex-Step-3"],
    ),
    dict(
        strategy="mastervp", symbol="BTCUSD", timeframe="M3", decision="RESEARCH-ONLY",
        label="tick-profile-proxy-validation", date="2026-06-28", hypothesis_id="R1/Codex-Step-2",
        train_start=None, train_end=None, oos_start=None, oos_end=None,
        commit_hash="78187ba", data_source="BTCUSD M3 tick-count VP under deterministic perturbation",
        set_path=None, cost_model="N/A (data-quality validation, not a P&L experiment).",
        n_trials=None, sr_trial_std=None,
        net_usd=None, pf=None, max_dd_pct=None, sharpe=None, n_trades=None, win_pct=None,
        psr=None, dsr=None, mintrl=None, mintrl_sufficient=None, pbo=None, gate_verdict=None,
        mt5_confirmed=False,
        artifacts=["research/data_quality/BTCUSD_M3_MASTERVP_TICK_PROFILE_PROXY_VALIDATION.md",
                   "research/data_quality/EVIDENCE_TIERS.md"],
        notes=("PASS-WARN. BTC M3 tick-count POC usually stable under perturbation, but remains "
               "QUOTE-ACTIVITY VP only (local MT5 feed LAST/VOLUME are 100% zero) and needs "
               "cross-feed/real-volume validation before any traded-volume claim."),
        source_refs=["docs:BTCUSD_M3_MASTERVP_TICK_PROFILE_PROXY_VALIDATION",
                     "HANDOFF:Codex-Step-2", "memory:btcusd-data-quirks"],
    ),
]


def main():
    ids = []
    for d in RECORDS:
        rec = make_record(**d)
        ids.append(append_row(rec, rebuild=False))
    n = rebuild_index()
    print(f"back-filled {len(ids)} experiment(s); index.csv now has {n} row(s)")
    for i in ids:
        print("  ", i)


if __name__ == "__main__":
    main()
