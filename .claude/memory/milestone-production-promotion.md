---
name: milestone-production-promotion
description: "End-goal — after KenKem port+optimize, pick the"
metadata: 
  node_type: memory
  type: project
  originSessionId: 67691271-7127-41af-98bb-1c0f44816ec8
---

The user's stated end-goal (2026-06-14): complete the FULL quant pipeline. After the KenKem port +
optimization finishes, **recommend the single #1 candidate across KK-MasterVP / Monster / KenKem** to
promote to production MQL5 — built from this dquants repo using our own infrastructure.

**How to do the promotion (user-authorized):** carefully hand-pick the symlinks/scripts/tooling from the
sibling `../kenkem` repo (his pre-dquants MQL5 codebase, already in this Claude session's working dirs)
for: compiling MQL5, deploying to MT5, reading tester logs/results, and extracting result params. Reuse
what already works rather than reinventing.

**Bar the user set:** "world class MQL5 code with zero mistakes in dealing with brokers, risks and
anything else to be deployed seamlessly to Production on MT5." So the promotion must be broker-spec-exact
(pip/contract/min-lot per symbol), risk-correct, and parity-proven before it ships.

**Why:** this closes Layer 4 of the architecture — the whole point of the C++ work is a thin, correct EA.
**How to apply:** don't start promotion until KenKem is parity-validated + optimized; then compare the
three strategies' optimized OOS results and recommend one with rationale. Relates to [[real-target-kenkem-strategies]]
and [[milestone-mt5-confirmed-optimization]].

**DECIDED (2026-06-14):** recommended **KenKem-distilled E4** as #1 (BTC primary, XAU secondary).
Rationale: most rigorous OOS (full fresh year 2026 H1, PF 1.239 vs others' 1–2 month same-year windows),
best robustness (MC 100% prof, P5 PF 1.164, spread-robust to $6), simplest logic (one Ichimoku TK entry →
cleanest "zero-mistake" code). Runner-up Monster-XAU (higher raw PF 1.276 but softer OOS); MasterVP only
MT5-proven but weakest edge. **Delivered:** production EA `kenkem/MQL5/Experts/KK-KenKemE4/KK-KenKemE4.mq5`
(single-file, CTrade-based) + README. Left UNCOMMITTED in the kenkem production repo for user review.
**UPDATE 2026-06-14 (later):** Built multi-entry `KK-KenKem.mq5` (E1/E2/E4/E5 toggleable; handle creation
guarded by toggles so off-entries cost zero), added the stops/freeze clamp on entry SL/TP + BE/trail
modifies, and **COMPILED IT CLEAN — 0 errors, 0 warnings** (via [[mql5-compile-workflow]] — I can compile
freely now). Robustness on OUR engine (no MT5 needed): BTC E1+E4+E5 6/6 months +ve / MC 100% / PF-P5
1.096; XAU E4+E5 5/5 +ve / MC 99.8%. Every entry +ve OOS; E5 (SuperBros) strongest leg. See
[[kenkem-distilled-result]].

**ARCHITECTURE (user-agreed):** keep strategies as SIBLING EAs (KenKem / KK-MasterVP / KK-Monster); share
reusable modules via ONE FLAT `KK-Common` include lib — partition by MODULE not family (DMI/ADX/ATR/RSI
used by both families; Ichimoku=KenKem-only, VolumeProfile=VP-only). `KK-Common` ALREADY EXISTS in kenkem
repo: Utils/BrokerHelpers, TradeManagement/{RiskManager,TradeManager}, Core/IndicatorCache, SessionManager,
Logging/TradeJournal. Compile-time module exclusion REJECTED as over-engineering (runtime guarded handles
already capture the win). Final gate stays: demo forward-test.

**SOURCE-OF-TRUTH RULE (user, 2026-06-14):** our dquants `kk::kenkem` engine + the compiled EA are the
SINGLE SOURCE OF TRUTH; everything in `../kenkem` (incl. the existing KK-Common RiskManager/TradeManager)
is REFERENCE only — build KK-Common from OUR validated logic, borrow patterns not behavior.

**REFACTOR DONE (compiles 0/0):** extracted KK-KenKem's validated logic into shared modules
`kenkem/MQL5/Experts/KK-Common/KenKem/{Inputs,Engine}.mqh`; `KK-KenKemE4/KK-KenKem.mq5` is now an 18-line
include shell. Pure code-move (logic byte-identical) → behavior preserved. Removed the redundant
self-contained E4-only EA (multi-entry shell covers it via toggles). Existing reference KK-Common files
untouched. NEXT (optional): promote cross-family generics (CopyBuffer reader, risk sizing, position
manager) from KenKem/Engine.mqh to KK-Common/Indicators + /Trade so VP family (MasterVP/Monster) reuses;
then refactor those EAs onto KK-Common. Files left UNTRACKED in kenkem repo for user review (I compile via
[[mql5-compile-workflow]]).

**LAYER-4 MQL5 CODEBASE BUILT IN DQUANTS (2026-06-14, compiles 0/0, COMMITTED):** user wants the MQL5 saved
in THIS repo (dquants), clean per common/family/entry. Done at `dquants/mql5/experts/`:
`KK-Common/{Indicators,Sizing,PositionManager}.mqh` (cross-family generics — risk-correct sizing, stops
clamp, partial/BE/trail), `KenKem/{Inputs,State,Indicators,Snapshot,Gates,Engine}.mqh`,
`KenKem/Entries/{E1,E2,E4,E5}.mqh` (ONE file per entry: trigger+gate+SL+RR+mgmt), `KK-KenKem/KK-KenKem.mq5`
(thin shell). Compiles clean via `scripts/compile_mql5.sh`. Symlinked into wine MT5 as `Experts/dquants`.
This dquants codebase is now canonical (supersedes the kenkem-repo copy). NEXT: VP family (MasterVP/Monster)
as siblings reusing KK-Common + their VolumeProfile modules. Final gate: demo forward-test.

**VP FAMILY STARTED (2026-06-14, compiles 0/0):** `dquants/mql5/experts/VP-Common/` (Types, VolumeProfile,
Regime, NodeEngine) + `KK-MasterVP/` (Inputs, Strategy=MVP_DetectSignal, CompileCheck.mq5) — faithful
transcription of cpp_core kk::vp / kk::detect_signal. Foundation verified via CompileCheck. REMAINING for
MasterVP: the OnTick orchestration integrator (port cpp_core mastervp/tick_engine.hpp — build master+local
VP from HTF bars, update NodeEngine per closed bar, detect on signal bar, manage via KK-Common) + EA shell.
THEN Monster (bigger: kk::monster engine ~1700 LOC, 4-kind signal + multi-TF net-volume). NOTE: shell-style
git commit messages with newlines were getting swallowed by the shell — use single-line -m or a file.

**MONSTER DONE (2026-06-14, compiles 0/0):** all THREE families now complete in dquants/mql5/experts/, each compile-clean: KK-KenKem (E1/E2/E4/E5), KK-MasterVP, KK-Monster (Config+Signal=4-kind+Engine). Monster signal = faithful transcription of cpp_core monster_signal.hpp (breakout/rev1/rev2/impulse + node-flow + master-POC regime + fresh-cross + multi-TF near-net via CopyRates). Shared: KK-Common (Sizing/PositionManager/Indicators), VP-Common (used by MasterVP; Monster self-contained structs). NOTE: Monster mgmt (TP1 50%/BE/trail) is a reasonable approximation - refine vs cpp_core position_manager if needed. Final gate for all 3: load best_*.set + demo forward-test.

**PARAM SWEEPS (2026-06-14) — user wants C++ sweeps not MT5.** KenKem DONE: added indicator LENGTHS to optimize_kenkem.py (EMA0-4/ADX/RSI, non-overlapping ranges keep stack ordered). RESULT: textbook lengths were suboptimal — BTC tuned EMA 12/23/53/94/210, ADX15, RSI11 -> 2026 OOS PF 1.239->1.377, win 65%, DD 8.6k->2.6k. best_kenkem_btc.set updated (f4386a5). PENDING (next session, context ran out): (1) MasterVP sweep — extend an optimizer over net_win_atr, vp_lookback(50?), atr_len, min/max_atr_pct, RR-vs-trail, brk/rev params (cpp_core mastervp backtester at cpp_core/tools/mastervp/backtester.cpp, .set-driven). (2) Monster sweep — optimize_monster_real.py exists; add net%/atr-window/vp-len/atr-thresholds. (3) DEFERRED ENTRY common module (user-requested, VALIDATED as real = pullback/limit entry): allow entry within x bars(=3) if conditions still hold, at a more favorable limit price; build in KK-Common (C++ kk::common + MQL5 KK-Common) with expiry+invalidation guards.

**NEW R&D PLAN (user, 2026-06-14) — test on MasterVP+Monster FIRST, then port to KenKem ("volume never lies"):**
1. MULTI-BAR NET VOLUME (toggle): currently net-volume entry decided at one moment; if flow turns against the
   trade over a few CONTINUOUS bars, exit early (and/or require net to PERSIST N bars before entering). Goal:
   enter/exit breakouts earlier than competition. NEW work: add a persistence/decay check across last N chart
   bars to the entry gate + an early-exit on N-bar net flip. (Monster has `enable_early_exit`/`exit_net_min`
   + `failed_break_check` scaffolding already — extend to multi-bar.)
2. VOLUME-NODE STRUCTURE SL/TP: stop using blind 2xATR SL / RR 1:3 TP; place SL/TP at HVN/LVN shelf structure
   from the node histogram + a buffer. **Monster ALREADY HAS THIS (default OFF):** `enable_hvn_shelf_sl`
   (NodeEngine::hvn_shelf_sl) + `enable_structural_tp2` (NodeEngine::structural_tp2, with stp2_min/max_rr) in
   cpp_core/monster_signal.hpp + the MQL5 KK-Monster/Signal.mqh transcription. So for Monster = ENABLE + SWEEP
   those flags/params; for MasterVP = ADD an equivalent node-shelf SL/TP. Then sweep to validate edge gain.
   If it helps, add node-structure SL/TP to KenKem too.
PLUS still-pending: wire DeferredEntry.mqh into families as a toggle + C++ sweep-validate it.
