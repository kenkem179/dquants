---
name: kenkem-e5-root-cause-exits
description: WHY KenKem-E5 loses on the canonical tick engine — over-firing is secondary; the killer is exit-management geometry (tiny partial/BE wins vs full-stop losses). golden trace tool built.
metadata: 
  node_type: memory
  type: project
  originSessionId: 98d352eb-3b8a-417c-a4cb-c1076046cc6a
---

**Root cause of KenKem-E5's tick-engine losses, localized 2026-06-15 from the dquants side alone (no MT5
run needed). Two compounding defects, in priority order:**

1. **Exit-management geometry = the dominant killer.** On the 2026-OOS tick run (1580 trades) win rate is
   **70.9%** yet PF **0.72**: avg win **$59 (~0.3R)** vs avg loss **−$200 (full −1R)**, ratio 0.29; max loss
   −$202 ≈ avg loss ⇒ nearly EVERY loss is a full stop-out, while most "wins" are tiny partial-TP / BE-trail
   scratches and few reach the RR-1.22 TP ($241). ≈ −0.08R/trade. The partial→BE→trail logic banks winners at
   ~0.3R but lets losers run to full −1R. **The bar engine HID this** (synthetic 4-point OHLC walk mis-resolves
   the path-dependent exit sequence → fake PF 1.34). PF stays 0.70–0.77 at every entry-frequency setting, so
   this is NOT fixable by entry selectivity alone. → fix via the ProfitManager (C5) surface (giveback-cap /
   BE-protect / partial-trigger), now validatable on the CANONICAL tick engine. See [[bar-engine-systemic-defect]].

2. **Over-firing = secondary, amplifier only.** The E5 gates already pass only ~7–8% of live-trigger bars, but
   `E5_MAX_EMA_CROSS_AGE=48` keeps one EMA-alignment onset eligible ~48 min, so the trigger is "live" 21%/16%
   of bars and **43% of entries fire at trigger age 33–48** (a late chase, not the onset). Tick 2026-OOS BTC:
   age48 → 1580tr / −$25,981 / DD26k; age1 → 353tr / −$5,391 / DD5.5k (~4.5× trades, ~5× DD). Dropping maxage
   to 1–3 massively cuts drawdown but does NOT restore profit (geometry problem persists).

**Tool built:** `cpp_core/tools/kenkem/trace_dumper.cpp` (`make kenkem_trace`) — read-only per-M1-bar decision
trace: every shift-1 indicator + E5 trigger state + each E5 gate sub-decision (sideways / atr-pctile lo+hi /
price-vs-EMA25 / trend-core / adx-floor / htf) for both dirs + raw fire. Schema matches an instrumented MQL5
`FileWrite`, so it's ALSO the C++ side of the golden C++↔MQL5 parity diff. Usage mirrors the backtester
(`--bars-m1 --set --from-ms --to-ms --warmup --out`). Analyze fires with awk on the CSV. The MQL5-instrument +
python-differ half is built-ready but DEFERRED (cause localized on C++ side; the MT5 run is no longer critical).

Commits: `0e167b3` (trace tool + finding), `1f19520` (2026-OOS tick re-baseline). Relates to
[[kenkem-distilled-result]] (its PF claims are invalidated) and the C5 ProfitManager work in
[[phase14-profitmanager-and-todos]].
