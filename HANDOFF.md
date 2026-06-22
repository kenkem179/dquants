# HANDOFF — read me first, update me last

## ▶ ACTIVE THREAD 2026-06-22 (b) — KK-MasterVP: VP-length re-sweep ✅ + FVG-anchored SL ✅ REJECTED
**Goal:** make sure we're not missing edge on BTC-M3, BTC-M5, XAU-M3, then add the user's FVG-beyond-SL idea.
1. **✅ VP-length re-sweep DONE — no missed edge.** On corrected M1-resampled bars (a stale per-year XAU
   bar file was missing whole trading days — fixed via `cpp_core/tools/resample_m1.py`): XAU-M3 lock 480 &
   BTC-M5 lock 720 both sit on robust train+OOS plateaus with the lowest OOS DD; **BTC-M3 breakout is
   structurally dead at every VP length** (PF 0.75–0.90 both windows). Secondary ADX/break-buf/SL sweep
   confirms all locks on the joint basis (the one OOS spike, XAU SL1.3, degrades TRAIN = curve-fit trap).
   Findings: `research/mastervp_parity/VP_LENGTH_RESWEEP_2026-06-22.md`.
2. **✅ FVG-anchored SL — FULLY TESTED → REJECTED (NOT ported to MQL5).** Engine feature
   `kk::apply_fvg_sl` (`cpp_core/include/kk/mastervp/fvg_sl.hpp`, default OFF, +4 tests, `make test`
   green) re-anchors a breakout stop / gates entry on a significant 3-bar FVG beyond VAL/VAH. Tested
   THREE forms on all targets: (a) **stop-relocation** = inert-to-marginal (where it cuts OOS dd it's
   just a wider stop trading away TRAIN PF — curve-fit trap); (b) **entry-gate `InpFvgRequire`** showed
   a tempting single-split XAU-M3 OOS jump (1.320→1.504) BUT **per-month walk-forward killed it**
   (`_fvg_wf.out`): OFF wins total net by ~$8.6k over 11 folds, the gate guts the best month
   (2026.01 −$6.7k), sign is regime-dependent (worsened 2025.07, reversed on BTC-M5); the "6/11 folds"
   was a PF-ratio artifact on low-net months; (c) **BTC-M3 unrescuable** — no entry edge, FVG only
   bleeds less. Full study: `research/mastervp_parity/FVG_SL_STUDY_2026-06-22.md`. **Verdict: keep all
   locks OFF; feature stays as tested default-OFF infra, NOT ported (WF failed → no gate run needed).**
   The chart "before/after" examples were survivorship — confirms [[vmc-momentum-module-result]] lesson.
3. **▶ NEXT (recorded, not yet tested):** user assumption that mean-reversion should fade LOCAL VP, not
   master (`[[reversion-local-vp-assumption]]`; code currently fades master). Plan in BUILD-PLAN — the
   one remaining open MasterVP research lever after VP-length + FVG both came up empty.
_Below: KenKem thread (separate)._

_Last updated: 2026-06-22 by Claude (Opus 4.8). Branch `reliableBaseline`. **⭐ KenKem LOCK = D5-E4Long** (E1+E2+E4-long; MT5 +1427/PF1.428/126tr; MC-hardened P(profit) 94.9%; gate PSR 0.953/MinTRL 122<126 PASS — the ONLY KenKem config to clear the gate; commit `c5719e8`). **THIS SESSION (2026-06-22, commit `6bca71b`): tested the live E1 frontier = a new Kaufman Efficiency-Ratio (ER) chop filter → WEAK, NOT locked.** New engine keys `E1_ER_PERIOD/E1_ER_MIN/E1_ER_ABANDON` (default OFF = exact base parity, `make test` 28/28, no lookahead, post-gate E1 drop). The E1-only grid plateau (N=5 dominant, +1160/PF1.6) was a LIMITER-CHOKED-REGIME ARTIFACT (83 E1 trades) that does NOT transfer to the free-fire lock book (189 E1): in the FULL D5-E4Long book the ER filter is **pooled-net-NEGATIVE** (3327–3401 vs OFF 3477) for only flat-to-marginal PF; the 2026-OOS gain is real but lives in the **trustworthy E1 book** (by-kind decomp: OOS-E1 +20.9→+127.0, PF 1.02→1.15 at ER_MIN 0.20; E2 flat-positive; E4 swings are FICTIONAL noise) AND is a **narrow small-n spike, NOT a plateau** (gain only at 0.20–0.25, gone at 0.15/0.30, n=21 OOS-E1). Gate: per-trade Sharpe 0.110→0.113 (+2.6%, engine can't distinguish). **Verdict: D5-E4Long STAYS lock; ER committed default-OFF as infra.** `D6-E1ER.set` is **ENGINE-ONLY** (the MQL5 EA does NOT implement ER → loading it just re-runs D5 → NOT a valid MT5 A/B). Findings: `research/optimization/KENKEM-E1-EFFICIENCY-RATIO-2026-06-22.md`. **⛔ AUTOPILOT BOUNDARY REACHED for E1/E2/E4/E5:** every remaining lever is either MT5-gated (E1 MTF-EMA value-diff dump; E5 latch-internal dump) or unsafe-to-parity (E4 intrabar-exit fix touches the SHARED `manage_tick` that holds the validated E1/E2 lock — deliberately untouched). **DECISION POINT for user:** (1) chase the narrow OOS-E1 ER signal? → requires porting ER into the MQL5 EA (default-OFF) then MT5 A/B D5-E4Long vs D6-E1ER — I judged that port NOT worth this thin evidence; (2) or `make release STRATEGY=KK-KenKem` to package the confirmed D5-E4Long lock (left for user sign-off, semi-outward-facing). — Prior thrust context below: **🔴 KenKem CLEAN REWRITE** (see the red KenKem section + `docs/BUILD-PLAN-KENKEM-REWRITE.md`). **GOAL:** kill trash dquants KK-KenKem, rewrite cleanly transcribing **E1+E2+E5 faithfully from the original KenKemExpert MQL5** (`../kenkem`), E4 excluded (MT5 net-loser). Decisions locked: scope=E1+E2+E5, source=KenKemExpert MQL5. **APPROACH PIVOT (this session, with rationale):** the "surgical clean-module rewrite" was abandoned for a **FAITHFUL FULL CLONE** — because Alerts are woven into the trading files (EntryBase/RiskManager/TradeManager/EMAHelpers all call them), so surgically excising them risks the very parity the user demands. Methodology: clone faithfully → **parity by construction** → confirm parity in MT5 (P4) → THEN prune cosmetics with a known-good safety net (a parity failure after pruning is then unambiguously the prune, not a port bug). **P1–P3 DONE + compiling 0/0 (this session):** `mql5/experts/KK-KenKem/` is now a faithful clone of `KenKemExpert.mq5` v1.8.154 — all **31 `.mqh`** (Config/Core/Entries/TradeManagement/Utils/Parity/Alerts/DataCollection) + Data CSV + the `.mq5` (header reset to `#property version "1.0"`, `#define VERSION "KK-KenKem 1.0-dev"`). **Compiles 0 errors / 0 warnings in dquants.** VERIFIED: **all 412 keys** of D3-noE4 / D4 / D4-E5 / D4-E2RR14 `.set` resolve (0 missing); parity export (`Parity/{BarTrace,TradeJournal}.mqh`, inputs `InpExportBarTrace`/`InpExportTradeJournal`) is built in. Excluded subsystems present-but-INERT in tester (NotificationMode=disabled, ENABLE_CSV_EXPORT=false, ENABLE_ADAPTIVE_*=false, WebRequest off in tester, E4 off via `.set`) → zero logic change. **DEPLOYED:** EA visible to MT5 via `Experts\dquants` symlink (`KK-KenKem/KK-KenKem.ex5`); `sync_presets.sh` re-run → candidate `.set` loadable from Tester→Inputs→Load→`dquants/KK-KenKem/`. (Prior `9de0342`: P0 kill old EA + build-plan + `make_release.sh` auto-bump; legacy at `KK-KenKem/releases/1.8.154-legacy/` = match target. The keystone commit `3e94e3c` shell+Inputs is superseded by the clone — its `Inputs.mqh` removed; `Config/InputParams.mqh` is the live one.) **P4 ✅ EXACT PARITY (2026-06-21):** user ran KK-KenKem (XAU M1, 2025.03.02–2026.05.29, D3-noE4.set); collected to `mt5_runs/2026-06-21_D3-noE4_clone/`. Clone trades are **byte-for-byte identical** to the legacy lock log — n=**102**, net=**+1048.88**, PF=**1.389**, wins=53 (sorted-rows `diff` clean). **dquants KK-KenKem == legacy KenKemExpert, trade-for-trade.** Faithful-clone methodology validated. **D4 + LEVER ISOLATION DONE → D4 REJECTED, D3-noE4 STAYS LOCK (2026-06-21):** ran D4 (+1382/1.489 pooled) + D4-ADXonly (+1121/1.407) + D4-TAonly (+1295/1.467). Per-period decomp (`mt5_runs/2026-06-21_D4-LEVER-ISOLATION.md`): **every D4 variant is WORSE out-of-sample (2026)** than D3-noE4 (OOS +326.86/1.475) — all gains are in-sample 2025Q4 curve-fit; ADX23 is the OOS degrader (causes 2026Q2 +56.95→+11.86), touch-age60 milder but still sub-baseline OOS. **OVERFITTING GATE on D3-noE4** (`research/stats/gate.py`, new CLAUDE.md mandate): ⚠️ **WARN/under-powered** — PSR-vs-0 **0.922** (below 0.95 PASS), **MinTRL 136 > 102 trades** (sample too short), DSR n/a (sweep doesn't log `sr_trial_std`). So D3-noE4 is best+exact-parity but NOT statistically confirmable at 95% on 102 trades. **⭐ D5-E4Long = NEW LOCK CANDIDATE, FIRST TO CLEAR THE GATE (2026-06-22):** entry-isolation runs (E4-only, E3-only) showed E4/E3 are net-losers standalone BUT both fail entirely on the SHORT side (E4 longs PF1.40, shorts PF0.555; E3 dead/20tr). Added default-OFF `E4_LONG_ONLY` input (Entry4 short-detect guarded; base stays exact-parity) + compiled headless via `scripts/compile_mql5.sh` (0/0). **GOTCHA:** first D5 run used a STALE cached binary (MT5 was running; external compile doesn't hot-reload) — fixed by MT5 clean-restart (`pkill terminal64` + clear Bases/MQL5 Cache + relaunch); verify the new input appears in the run-log dump. Valid run `mt5_runs/2026-06-22_D5-E4Long/` (E4=25L/0S confirmed): **pooled +1427.17/PF1.428/126tr** (vs lock +1048.88/1.389/102 → +36% net, PF↑), **2026 OOS +497.15/1.523** (vs +326.86/1.475 → better net AND PF), **gate PSR 0.955 PASS (≥0.95), MinTRL 118<126 SUFFICIENT** — the FIRST KenKem config to clear the gate (lock was WARN). 2026Q2 soft (−119) is ALL E4-long lumpiness (4tr, 2 stop-outs); E1+E2 core was +73 there (>lock's +57) → not a regime break. E5 stays OFF (noise). **NEXT:** (a) ⭐ harden D5-E4Long via walk-forward + Monte-Carlo (CLAUDE.md §7) watching E4-long per-fold stability (small n=25), then adopt as lock + `make release STRATEGY=KK-KenKem` + update best-experts table; (b) or lock+release now if user accepts. **D4-E5 DONE → E5 REJECTED (2026-06-21):** ran D4-E5 (XAU M1, every-tick), collected to `mt5_runs/2026-06-21_D4-E5/` (+FINDINGS.md). E5 = 258 trades @ **PF 1.082** (near-breakeven); pooled E1+E2+E5 +2112.32/PF1.258/356 (more net, LOWER PF than D3-noE4's 1.389; OOS PF craters 1.475→1.188). **Gate: E5-alone PSR 0.718 / MinTRL 2095≫258 = NOISE.** The full-stream "PASS" (PSR 0.966, MinTRL 287<356) is a sample-count artifact of pooling noise with signal — per-trade Sharpe FELL 0.138→0.096. **Decision: keep D3-noE4 (E1+E2) lock, E5 stays OFF.** Right way to clear the gate = more E1+E2 history, not E5 dilution. **NEXT (all MT5-gated → user picks):** (a) ⭐ **E4-only** (`KK-KenKem-XAUUSD-M1-E4only.set`) + **E3-only** (`KK-KenKem-XAUUSD-M1-E3only.set`) — user wants standalone E4 & E3 edge isolated (E3 is a full 1193-line counter-trend impl, not a stub; E3 historically "horrible" but user wants to rework it in dquants). Both built from D3-noE4 w/ only that one entry on; same XAU M1 2025.03.02–2026.05.29 every-tick. (b) **D4-E2RR14** refinement. (c) **P5 prune** cosmetics then RE-RUN D3-noE4 → must stay 102/+1048.88 (the `2026-06-21_D3-noE4_clone/` run is the safety net), then `make release STRATEGY=KK-KenKem`. (d) accept D3-noE4 as WARN-status lock + MT5 demo forward-test. **BLOCKED ON USER:** all MT5 runs (I can't run MT5 headless). **FOLLOW-UP:** wire `sr_trial_std` into the KenKem sweep so DSR becomes computable (research/stats README "Still open"). — Prior context still valid: presets organized under `mql5/experts/Presets/` + MT5-symlinked (🗂️ section); MT5 `.set` Load needs flush-left. MasterVP unchanged: **XAU M5 (+60,264/PF 1.40 MT5) is the sole validated front-runner**; BTC M5 reversion FICTIONAL→reverted/not-deployable._

## 📦 PROP-VARIANT RELEASES CUT — KK-KenKem v1.0 + KK-MasterVP v1.01 (2026-06-22)
User: "always release the prop variant (Max daily loss 4.4%, Max account drawdown 9%); release both
KK-KenKem and KK-MasterVP." **DONE.**
- **STANDING RULE (memory [[ea-release-versioning-convention]]):** every release now ships a `*-prop`
  variant encoding firm limits **daily loss 4.4% + account drawdown 9%**. Per-EA override keys:
  MasterVP `InpMaxDailyDDPct=4.4 InpMaxPeakDDPct=9.0` (+`InpRiskAccPct=0.5`); KenKem
  `MAX_DAILY_LOSS_RATIO=0.044 ACCOUNT_DD_RATIO_TO_SOFT_BLOCK=0.09 ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN=0.07`
  (soft-block IS the 9% ceiling — KenKem has no hard-halt input).
- **KK-KenKem v1.0** (first versioned release) — D5-E4Long LOCK. New `release.conf` + dev preset
  `KK-KenKem-XAUUSD-M1-D5-E4Long.set`; variants `xauusd-m1` (as-swept) + `xauusd-m1-prop`. Compiles 0/0.
- **KK-MasterVP v1.01** (bumped 1.00→1.01) — prop DD caps updated 4.0/8.0 → **4.4/9.0**; 4 variants
  (xau/btc M5 × personal/prop). Compiles 0/0.
- **make_release.sh BUGFIX:** version-scan pipeline died under `set -euo pipefail` when `releases/` held
  only a non-numeric tag (KenKem's `1.8.154-legacy`) — grep exit-1 killed the script. Added `|| true`.
- Both `releases/Changelog.md` auto-updated (MasterVP's auto-created). `.ex5` gitignored; `.set`+RELEASE.md
  +Changelog committed.

## 🟢 KK-MasterVP — MONSTER MERGED IN + EDITION RETIRED + 4-CASE RE-SWEEP (2026-06-22, commit 59cd9dc)
User: "Monster = MasterVP + one impulse delta — bring impulse into MasterVP OFF-by-default without
hurting MasterVP, then kill Monster completely." **DONE + committed/pushed (`59cd9dc`).**
- **Impulse ported into KK-MasterVP, OFF by default (`InpEnableImpulse=false`), byte-identical when OFF**
  by construction (impulse branch never runs; the gate's new `isImpulse=false` param skips ONLY the ATR%
  band for impulse; M1-ATR handle unused). New `MVP_DetectImpulse` (Strategy.mqh, 1:1 w/ cpp
  `kk::detect_impulse`) + `NetVolume.mqh` (`M1NetNear`). EA compiles **0/0**; `make test` ALL PASS
  (golden parity green). C++ side already had impulse in `kk/mastervp` (enable_impulse=false) — unchanged.
- **Monster retired (scope = CODE + BUILD only; research/ + memory KEPT as history, user's choice):**
  rm `KK-MasterVP-Monster` + `KK-Monster` EAs + presets + Presets view; deprecated cpp `kk/monster` fork
  + tools/monster + tests/monster; `monster_*.set` in tools/mastervp; auto-forwards. Makefile + sync_presets.sh
  + run_persist_sweep.sh de-Monstered. Preset tree re-synced.
- **4-CASE RE-SWEEP** (`research/mastervp_parity/resweep_2026-06-22.py` + `RESWEEP_2026-06-22_FINDINGS.md`):
  (A) **all 4 locks reproduce exactly** → consolidation broke nothing. (B) impulse alone is NOT a free
  win on the band-off locks; what it surfaced is that a **VOL CEILING** helps **XAU-M5 (0.158)** (PF
  1.422→1.715, dd 8.1→7.8%, net +10211→+11430) and **BTC-M5 (0.3)** (PF 1.250→1.390) on the OOS window —
  impulse only recovers a sliver of the capped trades. (C) single-window lever upticks are the curve-fit
  trap the WF locks reject. **Nothing locked** — the XAU-M5 ceiling+impulse variant is the one candidate
  worth a full WF+MC+gate pass (BTC-M5 secondary, feed caveat). BTC-M3 still no edge.

## 🧪 RESEARCH-PROCESS UPGRADE — parity-Gate-0 + edge-autopsy + pre-gate signal export (2026-06-21, THIS SESSION)
Closed the "guess-and-sweep with no analytics in the middle" gap the user flagged. Three layers, all
verified, **committed this session**:
- **C++ (enabler, ~40 LOC, ZERO regression):** engine now emits the **pre-gate raw signal stream** —
  `backtester --signals-out <csv>` → every `DetectSignal` (25k) + conditioning features, before gates.
  New `cpp_core/include/kk/common/signal_journal.hpp`; `tick_engine.hpp` collects at the `++raw_signals_`
  site (opt-in `set_collect_signals`); trades **byte-identical** with/without the flag, `make test` all pass.
- **SOP skills (new ordering):** `/quant-0-parity-baseline` (FIRST gate — engine must reproduce an MT5
  run, or N/A→UNVALIDATED if no reference; **never a hard block** per user) → `/quant-6b-edge-autopsy`
  (conditional expectancy/IC/cost-margin/gate-ablation on the raw signals) → `/quant-7-backtest` →
  `/quant-8-sensitivity` (both now say "sweep INSIDE the parity envelope").
- **Notebook `research/mastervp_parity/MasterVP_End_to_End.ipynb`** (29 cells, executes 0-error in
  `kenkem`): full lifecycle words→data→algo→**§0 parity gate**→**§4b edge autopsy**→backtest→sweep→
  WF+MC→§8 candidate re-parity→decision. **Key honest findings:** raw breakout signal HAS edge
  (fwd(20)=+0.135 ATR, t=6.24, net of cost +0.074 ATR); gates RAISE expectancy (0.172 vs 0.133);
  feature IC ≈ 0 (don't tune knobs); **engine↔MT5 = NEAR-MATCH not truth** (XAU M5 best ref: 86% match,
  PF Δ0.9%, net Δ2.4% → strict FAIL) ⇒ engine is a RANKING proxy, re-confirm every lock in MT5.
- Memory: [[engine-pregate-signal-export]], [[parity-is-gate-0]]. **NEXT (optional):** generate an MT5
  XAU M3 BASE run so §0 study-config parity flips N/A→real verdict; extend autopsy to BTC.

## 🧪 RESEARCH-PROCESS UPGRADE — overfitting / multiple-testing gate (2026-06-21, THIS SESSION)
Closed the "swept N configs, locked the best, never deflated for selection bias" gap. New
**strategy-agnostic** layer `research/stats/` (works for KenKem/MasterVP/Monster/BTC via one tool):
- `overfitting.py` — Bailey & López de Prado: Probabilistic Sharpe (PSR), **Deflated Sharpe (DSR)**,
  Min Track Record Length, Probability of Backtest Overfitting (PBO/CSCV), Bonferroni/BH. 8 pytest green.
- `gate.py` — universal CLI: auto-detects `entryTimeUTC`|`ts_ms` + `realizedUsd`|`pnlUsd`, so every
  engine's trades CSV loads through one path. `run_gate()`/`print_gate()` reusable.
- **Wired:** `mastervp_parity/wf_mc.py` (refactored to delegate) + `optimization/robustness_kenkem.py`
  print the gate; `report_metrics.py` gained Sortino/VaR/CVaR; both lifecycle notebooks
  (`MasterVP_End_to_End` §7/§9, ds-study `12_overfitting…` Step 6) show it. `wf_monster.py` = grid-sweep
  → run `gate.py` on its locked CSV directly.
- **Sweep context CLOSED (2026-06-22):** `research/stats/sweep_context.py` wired into ALL FIVE
  `optimize_*.py` — each objective records its trial's per-trade Sharpe, and post-study the harness
  prints `n_trials`+`sr_trial_std`, drops a `<best>.set.sweepctx.json` sidecar, and echoes the exact
  `gate.py` command. No more placeholder dispersion for real sweeps. (Verified: all 5 import clean +
  reporter emits real numbers/sidecar.)
- **Now enforced:** CLAUDE.md non-negotiables + §7 chain + Phase 9/10 skills. **Verdict: DSR ≥ 0.95 = PASS,
  0.90–0.95 = WARN (state it), < 0.90 = FAIL (don't lock).** Memory: [[overfitting-gate-mandatory]].

## 🗂️ PRESETS ARE ORGANIZED + MT5-LINKED (2026-06-21) — how to load any `.set`
All deploy/A-B presets are surfaced, by expert, under **`mql5/experts/Presets/<EXPERT>/`**
(`KK-MasterVP`, `KK-MasterVP-Monster`, `KK-KenKem`). Entries are **symlinks** to the canonical
source (`mql5/experts/<EXPERT>/*.set`; KenKem D3/D4 lock candidates → `research/kenkem_parity/*.set`)
so there is **zero drift** — edit the source, the view follows. This tree is symlinked into MT5:
`MQL5/Profiles/Tester/dquants -> dquants/mql5/experts/Presets`, so in the Strategy Tester →
**Inputs → Load** you open `dquants/<expert>/` and pick the preset directly.
- **Add a new deploy preset:** drop the real `.set` in the EA folder (or `research/kenkem_parity/`
  for KenKem locks), then run **`./scripts/sync_presets.sh`** (idempotent; rebuilds the tree + relinks MT5).
- After a fresh clone, run `sync_presets.sh` once to recreate the MT5 link. See `mql5/experts/Presets/README.md`.
- ⚠️ Old per-run habit of `cp`-ing single `.set` into the flat `MQL5/Presets/` dir is now superseded —
  everything loads from `Profiles/Tester/dquants/`. (The flat `MQL5/Presets/` dir is MT5's separate
  chart-attach mechanism; leave it.) MT5 `.set` Load still needs flush-left `key=val` (no indent).

## 🆕 PER-ENTRY-TYPE TRAIL OVERRIDE — BUILT + verified + presets ready for MT5 (2026-06-21)
User asked: let each entry family override the global `trail_runner` SAFELY, then sweep + ship MT5 sets.
**DONE.** Tri-state per family `trail_brk/rev/imp/xrev` (`InpTrailBrk/Rev/Imp/XRev`): **-1 inherit (default
everywhere → base byte-identical) / 0 fixed-TP no-trail / 1 force trail.** Resolved once per position at open
(cpp `PositionManager` from Signal flags; EA `KKResolveTrail` from `reason`, XREV>IMP>REV>BRK). Lets reversion/XRev
bank a fixed mPOC TP while breakout keeps trailing — the additive deploy that was impossible before.
- **Safety**: `make test` 30 OK (+2 per-type-trail cases) incl. golden parity; XAU M3 base OOS UNCHANGED (PF 1.114/
  net +4575.4/dd 17.5%) with overrides -1. C++ + BOTH EAs compile **0/0**.
- **Additive sweep (OOS):** the one real candidate = **XAU M3 + reversion @ mPOC** (`InpEnableReversion=true,
  InpRevTpMpoc=true, InpTrailRev=0`): PF 1.114→**1.123**, net +4575→**+4888**, **maxDD 17.5→13.5%** (humble bank
  trims DD). XAU M5 / BTC reversion @ mPOC HURT; XRev @ mPOC ≤ trailing (BTC trends → far edge wins).
- **User's MT5 XRev screenshots (2026-06-21):** BTC M3 +XRev net 3070→**3561** (PF 1.09→1.10, DD 14.4→15.7% — "ok");
  XAU M3 +XRev net 10422→**9353** (PF 1.09→1.08, DD↑ — "not great", MT5 disconfirms engine's mild XAU help).
- **▶️ NEW MT5 A/B:** Expert `KK-MasterVP`, XAUUSD **M3**, 2025.06–2026.05, every-tick — preset
  `KK-MasterVP-XAUUSD-M3-RevMpoc.set` vs base `KK-MasterVP-XAUUSD.set`. Both copied to MT5 Tester + kenkem Presets.
  Engine: net +4575→+4888, maxDD **17.5→13.5%** — watch whether MT5 confirms the DD trim. Commit: see below.

## 🆕 KK-MasterVP EXTREME REVERSION (XRev) — BUILT, OFF by default, awaiting MT5 A/B (2026-06-20)
Built the `research/hypotheses/strategy-descriptions/KK-MasterVP-ExtremeReversion.md` plan: failed-breakout
liquidity-sweep reversal entry family. **Toggle OFF by default → locked base BYTE-IDENTICAL** (golden test
`test_parity_golden` unchanged + empirical 103/103 trades identical). Full writeup: `research/mastervp_parity/XREV_FINDINGS.md`.
- **C++**: `extreme_reversion.hpp` (pure detector) + `is_extreme_rev` Signal + 13 `xrev_*` params/keys +
  precompute lookbacks & priority dispatch in `tick_engine.hpp` (gated). 9-case golden test green; `make test` 28 OK.
- **MQL5**: `ExtremeReversion.mqh` 1:1 port wired into BOTH `KK-MasterVP/Engine.mqh` and
  `KK-MasterVP-Monster/Engine.mqh`, `InpXRev*` default OFF. Both EAs compile **0/0**.
- **Sweep (isolated + additive, train/OOS; 6-fold WF infeasible — ~1-2 tr/fold, the family is RARE):**
  upper-wick sweep-tail is the strongest discriminator; `BigCandleAtr` must stay ≤0.6 (1.0 overfits → OOS PF 0.54);
  node-net gate is noise. Candidate: Wick0.5/BigCandle0.6/Body0.3/Closes2/Age40/RR2.0/Net0.0/NodeOff/SL0.7.
- **Additive verdict (real overlay):** BTC M3 (Monster, impulse+M1) OOS PF **1.284→1.330**, net +4288→+5138,
  dd **7.1→6.6%** (HELP, +9 tr, dd↓). XAU M3 OOS PF 1.114→1.122 (mild help). XAU M5 1.422→1.401 (HURT — don't enable M5).
- **⚠️ CAVEAT:** the big win (BTC M3) is on the BTC/Exness feed that's historically MT5-OVER-optimistic on
  reversion ([[mastervp-t3-reversion-lock]] revNet eng +5,414 vs MT5 −76). XRev is also reversion on BTC. Sample 9 tr.
- **▶️ MT5 A/B (toggle `InpEnableExtremeReversion`):** (1) **DECISIVE: BTC M3** — Expert KK-MasterVP-Monster,
  BTCUSD M3, 2025.08–2026.06, every-tick, preset `KK-MasterVP-Monster-BTCUSD-M3-XRev.set` vs toggle=false.
  (2) XAU M3 — Expert KK-MasterVP, XAUUSD M3, 2025.06–2026.05, preset `KK-MasterVP-XAUUSD-M3-XRev.set` vs false.
  Presets copied to MT5 Tester Presets + kenkem Presets. Ship only if MT5 beats base on BOTH net AND PF.

## 🎨 KK-MasterVP-Profiler INDICATOR — EA-twin REVERTED → standalone reborn + UX hardening (2026-06-21)
**User killed the EA-twin Phase-A/B build** ("total failure") and asked to restore the **exact standalone
kenkem original**. THIS session = restore + align to EA + fix look/feel. All UNCOMMITTED (working tree also
holds an unrelated KenKem-rewrite session — DO NOT broad-commit; commit ONLY the Profiler `.mq5` + its log).
Indicator compiles **0 errors / 0 warnings** after every change.
- **RESTORED:** `cp` kenkem `MQL5/Indicators/KK-MasterVP-Profiler/KK-MasterVP-Profiler.mq5` (2048-line,
  self-contained, NO shared includes) over the gutted 469-line EA-twin. (The old `Decision.mqh` EA refactor
  from Phase A still exists in `KK-MasterVP/` and is harmless/unused by the indicator now.)
- **VP defaults aligned to the EA** (`KK-MasterVP/Inputs.mqh`): `InpVpLookback` 50→**120**, `InpMasterMult`
  3→**4** (master VP = **480 bars**), `InpVpBins` 40→**30**. POC/VAH/VAL now match the EA.
- **`InpVpAbsoluteM5` (M5-absolute VP window) — BUILT then REMOVED.** User wanted a toggle to interpret
  lookback as M5 bars and scale to chart TF; once told it's only *near*-identical (not bit-exact: bar-feed
  binning granularity differs), user said drop it. Fully reverted from EA + indicator. Don't re-add.
- **Label/UX tweaks (user-requested):** histogram "Net Vol"→**"Net"**; POC/VAH/VAL state tags drop the % delta
  (`mPOC ▲90%`→`mPOC ▲`, `TagText` no longer prints pct); `InpSetShowRejects` default **false** (no more
  `xS chase 7.2ATR` reject labels by default).
- **🩹 BLINKING FIXED (root-caused):** the 480-bar **real-tick** window (`CopyTicksRange` ~24h) intermittently
  fails on BTC M3; `OnTimer` retried every 5s → histogram flipped TICK(fine)↔BAR(chunky) + net%s flipped.
  **Fix = `InpUseRealTicks` default `false`** → structure ALWAYS bar feed (deterministic, EA-exact, OnTimer
  thrash now dormant). User chose this over a sticky-tick option.
- **Resolution 2×:** `InpHistBins` 120→**240** + raised internal clamp **200→600** (the old cap silently
  throttled it). Thinner/finer rows.
- **🔀 HYBRID net-delta (user's idea, BUILT):** structure (background buy/sell rows) = bar feed (stable);
  the **bright net-delta slice + near "Net%"/over/under + bias arrow** = REAL tick-rule signed volume.
  New `ComputeTickDelta()` bins ticks over a **capped recent window** (reliable, unlike full 480) into
  `g_binTBuy/g_binTSell`; `BinDeltaNet(bin)` returns tick-net where covered else bar-net (strict superset).
  New inputs `InpHistTickDelta`=true, `InpHistTickBars`=200. Panel feed tag now `[BAR+tickD]` turquoise /
  `[BAR]` orange / `[TICK]`. CAVEAT: delta is true-tick only within `InpHistTickBars` (recent prices),
  bar-net for the older/upper part of a tall profile.
- **🩹 PANEL OVERFLOW on Retina/scaled Macs FIXED:** top-right table had a hardcoded `w=184` box → text spilled
  the border. `DrawPanel` now builds all rows first, measures the widest with DPI-aware `TextGetSize`
  (`TextSetFont("Consolas",-80)` matches OBJ_LABEL rendering) via new `PanelTextW`/`PanelTextW1`, and sizes
  the box to fit (+12px pad each side). Auto-correct across displays.
- **⏳ NEXT:** user re-attaches the indicator (saved chart inputs override new defaults — must re-add or set
  `InpUseRealTicks=false`/`InpHistBins=240` manually) and eyeballs BTC M3 + a Retina screen. Then commit just
  the Profiler `.mq5` (+compile log). Indicator `CLAUDE.md` still describes the dead EA-twin design — rewrite
  it to the standalone reality before/at commit.

## 🔥 PROFITABILITY UPLIFT — T2 hour-block + T3-EXIT + T3-REVERSION (2026-06-20) ✅ DONE
6-fold WF with PER-FOLD recent-regime decomposition (the T1 discipline). New diag
`research/mastervp_parity/hour_atr_decomp.py` (per-broker-hour net/PF + per-fold split).
- **MasterVP (XAU M5) — WIN, LOCKED `InpBlockedHoursStr=2,3,14`** (ref-tz UTC+10 = block UTC04 Asian-lunch
  lull + UTC16,17 late-London chop). Pooled PF 1.243→**1.296**, net +16.6%, maxDD 12.5→**10.0%**, worst-fold
  1.102→**1.196**; 5/6 folds improve, BOTH recent folds rise (F5 +533, F6 +640) → passes recent-regime check.
  MC(20k): P(profit)99.9%, PF 5th-pctile 1.158, maxDD median 22.2%/95th 34.7% (all better than baseline lock).
  REJECTED: news hr0 (net-harmful — post-data hr has continuation winners), Asia hr10 + hr18 (over-block),
  ATR upper-band `InpMaxAtrPct` (non-monotonic curve-fit noise, costs net). `InpBlockedHoursStr` is a REAL EA
  input (same UTC+10 frame via `SN_RefTime`) → ships via `.set`, NO recompile. Engine lock + EA preset
  `KK-MasterVP-XAUUSD-M5.set` updated + redeployed (kenkem Presets + MT5 Tester Presets). **✅ MT5 CONFIRMED**
  (`mt5_runs/RUN_2026-06-20_xau_m5_T2_hourblock`): blocked hours UTC04/16/17 EXACTLY empty in MT5 (block
  ported faithfully via `SN_RefTime`); PF 1.370 engine vs 1.366 MT5 (0.3%), lag 3.2%, 468/535 matched.
  net Δ 9.2% = known feed-noise (strict-gate FAIL only). On this window block lifted PF 1.339→1.370. CLEARED for demo.
- **Monster (BTC M3) — NO CHANGE (re-validated).** T2 was already done in its lock (`8,10,11,16` + best_btc
  cluster sessions + active ATR band 0.158). Top pooled candidate `8,9,10,11,16` (PF→1.231) is ANOTHER T1
  trap: gain carried by 2025 (F1 +787/F2 +247) while recent F5 −372/F6 −321 + dd worse → REJECTED. Keep current.
- **T1 (gate sweep) — DONE earlier:** MasterVP gates tested→reverted to baseline (commit ded3e81); Monster
  gates negative. MT5 parity confirmed faithful. See [[mastervp-m5-gate-sweep-lock]]. 🔑 LESSON (reconfirmed
  twice in T2): decompose per-fold (esp. recent OOS) BEFORE locking — pooled WF avg hides regime shifts.
- **T3-EXIT (XAU M5) — WIN, LOCKED `InpTp1ClosePct` 20→0** (commit 4f45ec3). The Pine 20% partial was
  INHERITED verbatim, never WF-swept (the M5 lock only swept entry/risk). Per-fold sweep
  (`wf_mastervp.py --grid InpTp1ClosePct`) is MONOTONIC (0<10<20<35<50 on PF/net/dd/worst-fold) → banking
  any partial caps the trailed runner. 0%: pooled PF 1.296→**1.335**, net +15.3% (19.3k→22.3k), maxDD
  10.0→**9.2%**, worst-fold 1.196→**1.219**; ALL 6 folds improve incl. both recent. Matches Monster/BTC.
  EA recompiled 0/0; shipped `KK-MasterVP-XAUUSD-M5-LOCKED.set` (MT5 Presets). ⏳ needs MT5 re-run.
  LESSON: WF-sweep even pre-tuned "faithful" values. See [[mastervp-tp1-partial-zero-is-best]].
- **⏳ IN FLIGHT: full exit-block joint WF sweep** (`InpTp1ClosePct × InpTp1R × InpTrailAtrMult`, 33 combos
  × 6 folds, `research/mastervp_parity/exit_block_sweep.out`) — the entry side got a joint sweep, the exit
  side never did. Lock the whole exit block the same way once it lands.
- **T3-REVERSION (mean-reversion activation) — DONE, 2 WINS / 2 REJECTS** (`research/mastervp_parity/wf_t3.py`,
  generalized 4-config harness). Reversion fires ONLY in balance (non-trend) regime = complement of breakout
  → additive. Swept enable→retest→body→sl×4 configs, 6-fold WF + MC, per-fold recent-regime discipline:
  - **BTC M5 (KK-MasterVP) — 🧨 MT5-DISCONFIRMED → REVERTED to breakout-only (2026-06-20).** Engine WF
    sweep had claimed a WIN (`InpEnableReversion=true`…, pooled PF 1.217→1.308, net +62%, revNet +5,158).
    **User ran the locked set in MT5 → BAD.** `mt5_runs/RUN_2026-06-20_btc_m5_locked_reversion/FINDINGS.md`:
    fair overlap window engine **PF 1.293 / +10,129 / win 59.6%** vs MT5 **PF 1.058 / +1,761 / win 51.2%**;
    engine **revNet +5,414 vs MT5 −76** → the reversion edge is FICTIONAL on the BTC/Exness feed. Only 57%
    of trades match (XAU ~86%); on matched, exits agree 89% but engine over-wins +8 pts (feed round-trips
    intrabar: 45% continuation vs 94% OANDA — already measured). Same shape as Monster BTC M3 (1.178→1.031).
    **ACTION TAKEN:** flipped `InpEnableReversion` true→false in engine set + all 3 EA presets + MT5 Presets.
    **BTC M5 MasterVP = NOT live-deployable** (breakeven live); the 57% entry-match gap must be closed first.
    **XAU M5 is the sole validated front-runner** (same-session MT5: +60,264 / PF 1.400 / 1294 trades).
  - **XAU M5 (KK-MasterVP) — WIN, LOCKED** `InpEnableReversion=true` at DEFAULT rev params (no tuning beat
    them). Measured ON TOP of the T3-EXIT TP1=0 base: pooled PF 1.335→**1.344**, net +3.6%, maxDD 9.2→**7.8%**,
    6/6 folds, worst-fold 1.219→**1.223** (rises), F6 1.49→1.52. revNet small (+48) = mostly dd-smoothing, not
    standalone edge. MC(20k): P(profit) 100%, PF 5th 1.198, 11/12 months & 7/8 folds, full-stream maxDD med 23.3%.
  - **XAU M3 — REJECT** (revNet ~+27 break-even, maxDD 14.2→15.9% worse, worst-fold 0.731→0.674 deepens).
  - **Monster BTC M3 — REJECT** (default rev: folds PF>1 6/6→4/6, F3+F6 go negative, maxDD 10.6→13.8%).
  Both wins: engine locks + EA presets (`KK-MasterVP-{XAUUSD,BTCUSD}-M5.set`) updated + redeployed (kenkem
  Presets + MT5 Tester Presets). All rev keys are REAL EA inputs → ship via `.set`, NO recompile. ⏳ needs MT5 re-run.

## 📚 ds-study learning track — RELIABILITY HALF ADDED (NB 11 + 12, additive)
Added two notebooks teaching the half that made MasterVP *reliable* (00→10 only taught finding an edge).
**NB 11 `parity_ground_truth`** — ground-truth ladder, diff-config-before-logic (real `.set` diff),
Wilder-vs-SMA ATR bug reproduced on real M1 bars (6.9% mean / 23% bucket flip), trade-level PASS/FAIL
matcher (real `_locked_oos.csv`). **NB 12 `overfitting_and_drawdown_honesty`** — peak-vs-plateau,
walk-forward (11/12 months PF>1) + Monte-Carlo (P(profit) 99.6%, PF 5th 1.10) on real `_wf_fullrun.csv`,
drawdown honesty (calmest 4mo 13.9% vs full-year 27.7% vs MC95th 38.7%). Both executed 0-errors against
real artifacts; README/GLOSSARY updated additively; generator `ds-study/scratch/_gen_nb11_12.py`. Nothing deleted.

## 🟢 KK-MasterVP — TRADE-LEVEL PARITY VERIFIER SHIPPED (production gate, commit 5fc34c9)
**User ask:** make perfect MQL EA editions from the C++ pipeline for production; chose the
**MasterVP parity verifier** track + deploy via **MT5 demo forward-test first**.
- **Gap found & closed:** the shipped KK-MasterVP EA had NO trade-export, so "compiles" could
  never be upgraded to "proven-faithful." Added `mql5/experts/KK-MasterVP/Parity.mqh` — a
  trade-level journal byte-compatible with the C++ `kk::to_trades_csv` ledger (21 cols, matched
  rounding), gated by **`InpExportParity`** (default OFF). Wired into `Engine.mqh` (init/close,
  fill-capture, per-tick MFE/MAE, `OnTradeTransaction` → realized P&L across TP1 partial+final,
  TP/SL-WIN/SL-LOSS/EA tags). Compiles **0/0**.
- **Chain proven:** engine-vs-engine smoke (108 trades, May-2026 XAU M5) → `parity_diff.py` **PASS**.
- **Procedure documented:** `research/mastervp_parity/PARITY_WORKFLOW.md` (3 steps: MT5 tester with
  `InpExportParity=true` → C++ backtester same window/set → `parity_diff.py` PASS/FAIL).
- **✅ FIRST PARITY RUN → FAIL → ROOT-CAUSED → EA FIXED** (`research/mastervp_parity/mt5_runs/
  RUN_2026-06-20_xau_m5_parity/`). XAU M5, 2026.01-06: EA 631 vs engine 563, 416 matched, entries
  FAITHFUL (entryΔ≈0), SL formula identical.
  - **ROOT CAUSE = EA runner-TP PORT BUG (not spread).** Exit-tag decomp: MT5 **170 TP** / 175 SL-WIN /
    286 SL-LOSS vs engine **10 TP** / 313 SL-WIN / 239 SL-LOSS. EA capped broker TP at `sig.tp2`=1.8R;
    engine uses 10R runner backstop + chandelier trail (`position_manager.hpp:93-97`, trail_runner=true,
    enable_struct_tp=false, runner_rr=10). **FIXED `Engine.mqh:226`:** TP=`sig.entry±sig.risk·InpRunnerRr`
    when InpTrailRunner. EA recompiles **0/0**. Memory [[mastervp-feed-spread-10x-mismatch]].
  - **SPREAD = real but MINOR:** engine feed 18.9pts vs live Exness 189pts (10×), but `--extra-spread 0.170`
    moved PF only 1.31→1.28 (~$2/trade). Added `--extra-spread` to backtester (`tick_engine::set_extra_spread`,
    golden tests green) for live-cost stress. (My first "spread=root cause" call was WRONG — corrected.)
  - ATR-mode hypothesis tested + DISCONFIRMED.
- **✅ TP FIX CONFIRMED — NEAR-PARITY** (`RUN_2026-06-20_xau_m5_parity_v2_tpfix/`). MT5 re-run after the
  fix: trades 631→**561** (engine 563), TP exits 170→**7** (engine 10), exit-mismatch 141→**39**, matched
  416→**483**, net Δ **409%→2.42%**, PF **1.304 vs engine 1.316**. The runner-TP port bug WAS the parity
  gap. `parity_diff.py` still says FAIL only because net Δ 2.42% > strict 1.0% gate — but that residual is
  **feed-level noise** (bar/ATR value diffs + spread on ~80 boundary trades + 39 exit flips), NOT a logic
  bug. Signal/entry/exit mechanics are faithfully reproduced.
- **▶️ NEXT ACTIONS:**
  1. **Demo forward-test** — the EA now demonstrably reproduces the validated engine; XAU M5 is cleared.
  2. Stress the lock for live PF: `--extra-spread 0.17` (engine PF holds ~1.28 at real Exness cost).
  3. Replicate the runner-TP fix + add `Parity.mqh` into **KK-MasterVP-Monster**, then parity-run it.
  4. (optional) decide whether ~2-3% feed noise is the accepted parity floor for this pair.
  KenKem still NOT production-eligible (E5 parity open).

## 🟣 KK-MasterVP-Monster (BTC) — WALK-FORWARD RE-LOCK this session (robustness ↑, EA re-shipped)
**User ask (this session):** autopilot the walk-forward / multi-fold robustness path I proposed last
time (instead of more single-split sweeping), then auto-produce the MQL EA. **DONE — committed/pushed.**
- **WHY WF:** the prior audit left the inherited secondary params at spec defaults to avoid curve-fitting
  one OOS window. The rigorous test (SOP `/quant-9-walkforward`) is **6 disjoint folds** (2 in the 2025
  train ticks, 4 in the 2026 OOS ticks), adopting a change only if robust ACROSS folds (improves pooled
  result AND the worst fold). Harness `research/monster_parity/wf_monster.py` + engine `--trade-to-ms`
  fold cap (the latter committed by the parallel MasterVP agent — already in HEAD).
- **RESULT — 3 secondary params re-tuned, the rest CONFIRMED at defaults:**
  - Re-locked: `InpDiSpreadMin` 6→4, `InpImpulseTrendSlopeBars` 10→6 (dominant lever, impNet +45%),
    `InpTp1ClosePct` 15→0 (no TP1 bank; BE-after-TP1 still de-risks at 1R). They **stack constructively**
    (tested jointly — repo's "sequential wins can fail jointly" guard): convert the two losing 2026 folds
    to positive → **6/6 folds PF>1, worst-fold PF 1.001** (was 0.867), pooled PF 1.106→**1.140**, dd
    16.0→**13.7%**. On the ORIGINAL single split: **OOS PF 1.131→1.192** (now clears the ≥1.15 deploy
    gate), OOS net +1,956→**+3,014**, OOS dd 10.1→**9.5%**, train also up (1.071→1.084).
  - CONFIRMED inherited-correct by WF: EMA 24/194 (outright best), ema_sep 0.25, node touch 0.05 + gate
    ON, impulse entry_buf 0.4 (flat/inert). REJECTED: impulse max_dist 3.0 (worsens worst fold). Daily-DD
    limiters structurally INERT (6/8/10 identical) — kept 6% as live-safety floor. Full table in
    `research/monster_parity/MONSTER_M3_FINDINGS.md` (WALK-FORWARD section).
- **EA RE-SHIPPED** `mql5/experts/KK-MasterVP-Monster/` recompiles **0/0**; the 3 params updated in
  `Inputs.mqh` defaults + all 4 presets (EA folder + `kenkem/MQL5/Presets/`, impulse + NoImpulse). M1-net
  via iVolume=tick_volume. **MANUAL MT5 FORWARD-TEST is the next action.** `InpEnableImpulse` toggles A/B.
- **M5:** still NOT robust on BTC (prior session) — Monster ships **M3 only**.

## 🟠 KK-MasterVP-Monster (BTC M3) — EA fixed + parity-ready + spread-stressed (this session)
- **EA FIXED:** ported the runner-TP fix (`Engine.mqh`: TP=`sig.entry±sig.risk·InpRunnerRr`=5.3R when
  InpTrailRunner, mirrors monster_engine.hpp:275-287; was capped at sig.tp2=3.0R) + added trade-level
  `Parity.mqh` (InpExportParity). Compiles **0/0**. Engine lock reproduces OOS PF 1.192.
- **SPREAD-FRAGILE:** OOS PF 1.192→1.172(+1)→1.157(+2.5)→**1.121(+5)**. Thinner than XAU M5. Cost-aware
  SL re-tune found NO robust improvement (wider SL curve-fits train, degrades OOS). Lock SL=3.7 is the
  OOS-optimum. `research/monster_parity/MONSTER_SPREAD_ROBUSTNESS.md`.
- **✅ PARITY RUN DONE** (`research/monster_parity/mt5_runs/RUN_2026-06-20_btc_m3_parity/`). BTC M3,
  2026.01-06. TP fix CONFIRMED (MT5 TP=3, exit dist 154/3/148/115 ≈ engine 159/3/144/99). Entries faithful.
  **BTC spread ~$11 ≈ engine feed — NO 10× inflation (unlike XAU);** engine PF was already realistic-cost.
  **BUT net Δ 498%: engine +2,801/PF 1.178 vs MT5 +469/PF 1.031.** Matched 345 agree; gap = unmatched
  (75 MT5-only / 59 engine-only) → EA takes ~75 trades the engine doesn't near session boundaries.
  **→ Monster is MARGINAL live (PF ~1.03), NOT clearly deployable.** XAU M5 is the strong candidate.
- **▶️ NEXT for Monster (only if pursuing it):** diagnose the 75 MT5-only entries — compare entry-gate /
  MaxTradesPerSession / cooldown counting between EA & engine near session/force-close boundaries.
  Otherwise deprioritize vs the XAU M5 forward-test.

## 🔀 ACTIVE THRUST (2026-06-20): KK-MasterVP Pine-faithful rebuild → param sweep → EA
**User pivoted** from KenKem E1–E5 parity to optimizing **KK-MasterVP on XAUUSD M3**. KenKem state
preserved below (📌 PAUSED) — not abandoned.

- **Goal:** reproduce the profitable TradingView Pine (`research/mastervp_parity/KK-MasterVP.pine`,
  PF 1.24 / 5,204 trades / +2583%/yr OANDA XAU) in the C++ engine, then *add missing risk management*
  (daily-DD, consec-loss, anti-chase, ATR-pctile gate, trail/stall exit) via disciplined param sweeps,
  then port to an MQL5 EA for the user's manual MT5 forward test.
- **User chose:** Fresh **Pine-faithful** build · **XAUUSD M3** first · objective **Robust PF + plateau**.
- **User directive (autopilot):** "go autopilot until the C++ engine is super faithful, nothing left to
  sweep while I sleep, then produce the MQL EA for manual testing."
- **✅ S0 DONE (commit a087b52, pushed):** engine aligned to ref Pine via `tools/mastervp/pine_faithful_xau.set`
  + `backtester --set-all` (applies ALL keys incl. MQL non-inputs). Built `research/mastervp_parity/diff_tv.py`
  (regroups TV TP1+TP2 portions → positions; distributional compare). **Entry model is FAITHFUL:** over
  2025-06-19..2026-05-29, engine 2610 positions vs TV 2445 (1.07×), win 56.4 vs 57.8%, hours aligned, TP1-rate
  aligned, %long ±4. **Two fixes found:** (a) `broker_gmt_offset` was DEAD — wired it; the TV hour fingerprint
  proves Pine sessions ran in **UTC+10** (Asia-open 00:00→14:00 UTC spike; gap 21-24→11-13 UTC empty); set
  offset=10. (b) added `min_atr_ticks` floor (Pine=40), default 0/off so golden test intact.
- **🔑 KEY FINDING — residual PF gap is FEED-DRIVEN, not a bug:** baseline PF 1.01 vs TV 1.25 at MATCHING win
  rate. BE on/off experiment proved it: on OANDA a break that reaches 0.8R continues to 1.8R **94%** of the
  time; on our **MT5/Exness feed only ~45%** (it round-trips). So the TV edge leans on OANDA's smooth
  post-breakout continuation — the edge must be REBUILT for the real feed via exit/risk sweeps. This is the point.
- **✅ SWEEPS DONE + EA SHIPPED (this session) — autopilot endpoint reached:**
  - **S1 entry:** break_buf 0.7 / adx 22 / di 8 best. **S4 exit:** chandelier trail beats fixed-TP2,
    `trail_atr_mult=2.0 + sl_atr_brk=1.0`. **S6b risk:** daily-DD **10%** (plateau 8/10/12),
    loss-streak limiter HURTS (off), risk **1.0%** (lowest-DD plateau). **Q1 (ATR-pctile gate):** inert on
    MasterVP — keep off. **Q2 (anti-chase break_max_atr):** capping HURTS on this feed (2 ATR → negative) — off.
  - **⭐ S8/S8b VP-length (user-requested):** train peak **85×4 (PF 1.271) COLLAPSES to break-even OOS** (curve-fit);
    long-window generalizes. **LOCKED master VP = 480 bars (24h M3) = `InpVpLookback=120 × InpMasterMult=4`.**
    **TRAIN PF 1.264 / OOS PF 1.114, OOS net +4,575, OOS maxDD 17.5%.** Sits interior to a broad OOS plateau
    (480→720 bars all OOS PF 1.11–1.15; <360 collapses, >720 falls off).
  - **⭐ DISCOVERY: local VP is INERT in breakout-only mode** — breakout keys off the MASTER VP's VAH/VAL only;
    local VP is consumed only by reversion (off). Master length is the sole driver. See
    `research/mastervp_parity/VP_LENGTH_STUDY.md`. → user's multi-TF VP idea is a real *future* enrichment
    (turn the dead local/HTF-M5/M15 VP into a breakout AGREEMENT gate; build in C++ + sweep + OOS first).
  - **Locked config:** `cpp_core/tools/mastervp/kkmastervp_xau_m3_LOCKED.set`. OOS validator: `/tmp/vp_oos.py` pattern.
- **✅ MQL5 EA SHIPPED (compiles 0/0):** `mql5/experts/KK-MasterVP/` — `Engine.mqh` now ports the FULL C++ safety
  gate stack (quality→session→ATR-ticks floor→spread→max-trades→daily-DD predictive→blocked-hour→peak-DD→
  cooldown→news) + RiskManager (daily-DD 10% + 12h cooldown) + broker-UTC auto-detect (sessions trade the same
  wall-clock hours on ANY broker). Fixed the old EA's hardcoded MTF/RSI veto → now flag-gated (Pine has neither).
  `SessionNews.mqh` = self-contained Sessions (filters.hpp port) + NewsFilter (CSV+embedded calendar) for the
  user's KenKem-style session config + news avoidance (default OFF; live-only overlay, not in backtest PF).
  Preset `KK-MasterVP-XAUUSD.set` shipped to EA folder + `../kenkem/MQL5/Presets/`. **READY FOR MANUAL MT5 TEST.**
- **✅ M5 DEDICATED SWEEP DONE (this session) — M5 BEATS M3 on every axis:** master-len → entry → exit →
  risk, each train→OOS, plateau-picked (`research/mastervp_parity/M5_SWEEP_FINDINGS.md`). Inertness
  re-confirmed (master bars = sole driver). **Locked M5: master 432 bars (36h) = 108×4 · break_buf 0.85 ·
  sl_atr_brk 1.2 · trail 2.5** (rest = M3 lock). Caught the trail overfit-trap (train loves 4.0, OOS peaks
  2.0–2.5). Daily-DD inert on M5 (kept 10% as live net). Result: **OOS PF 1.327 / dd 10.3% / win 58.6% /
  net 7,886 / n 442** vs M3 lock OOS PF 1.114 / dd 17.5%, AND more tail-robust (M5 top-10 = 121% of net vs
  M3 208%). Engine lock `cpp_core/tools/mastervp/kkmastervp_xau_m5_LOCKED.set`; EA preset
  `mql5/experts/KK-MasterVP/KK-MasterVP-XAUUSD-M5.set` (+ kenkem Presets) — attach EA to an **M5** chart.
- **✅ BTCUSD SWEEP DONE (this session, NO-SESSION 24/7, M3+M5):** `research/mastervp_parity/BTC_SWEEP_FINDINGS.md`.
  **M3 BTC = NO edge** (train tunes to PF 1.13 but every config collapses OOS PF 0.72–0.83, dd 57–75% — overfit;
  train/OOS anti-correlated; NOT shipped). **M5 BTC = modest plateau-robust edge** at a LONG master: master
  **720 bars (60h) = VpLookback24×MasterMult30 · adx30 · break_buf1.0 · sl2.2 · trail6.0**, 24/7 sessions.
  Positive on BOTH train+OOS across a 4-D plateau (master×adx×sl×trail): **TRAIN PF 1.155/dd13.9% · OOS PF
  1.214/dd14.2%/win57.4/net+4,228**. ⚠️ tail-skewed (OOS top10=219% of net — lower-conviction than XAU; the
  trend-breakout fat-tail shape). Lock `cpp_core/tools/mastervp/kkmastervp_btc_m5_LOCKED.set`; EA preset
  `KK-MasterVP-BTCUSD-M5.set` (+ kenkem Presets, attach to BTCUSD M5 chart). `sweep.py` now has `--symbol btc`;
  combined BTC bars `bars_btcusd_2025_2026_{m3,m5}.csv` built (gitignored). Train win only 3.5mo = main limiter.
- **✅ WF + MONTE-CARLO HARDENING DONE (this session) — XAU M5 lock CLEARED for forward-test:**
  `research/mastervp_parity/WF_MC_FINDINGS.md`. Added C++ `--trade-to-ms` fold cap (`tick_engine
  ::set_trade_to_ms`; golden tests green) + `wf_mc.py` (stability+MC) + `wf_reopt.py` (anchored re-opt) +
  continuous tick file `ticks_xau_full.csv` (gitignored). Canonical continuous stream (1,413 trades over
  2025-06→2026-05, x4.11/+311%, PF 1.260): **walk-forward 11/12 months & 7/8 equal folds PF>1** (only
  Aug-2025 negative, trendless chop); **anchored re-opt 4/5 OOS folds PF>1, WF-eff ~1.0**, and the FIXED
  432b lock BEATS per-fold re-optimization (5/5 vs 4/5) → **not a curve-fit, no periodic re-tuning needed.**
  **Monte-Carlo (20k):** P(profit) 99.6%, PF 5th-pctile 1.108, risk-of-ruin ≤50%=0.06% at 1%/trade.
  ⚠️ **DRAWDOWN HONESTY:** the headline OOS dd 10.3% was a benign 4-month window — true full-year maxDD
  **27.7%** (MC 95th ~38%, worst ~55%); size for **~30-40% peak**, not 10%. **No param change**; EA preset
  annotated + re-synced to kenkem Presets; EA recompiles **0/0**.
- **▶️ NEXT (when user returns):** manual MT5 forward-test — XAU **M5 preset is the validated front-runner**
  (XAU M3 A/B; BTCUSD-M5 candidate but lower-conviction/tail-skewed). Remaining optional research: same
  WF+MC pass on the M3/BTC locks, and the local/HTF-VP breakout-agreement gate. Note: EA news/session
  overlays diverge intentionally from the backtest (live-safety), so forward results may be fewer than OOS PF.
- **Data:** combined bars `cpp_core/tools/bars_xauusd_2025_2026_m3.csv`; full ticks `ticks_xauusd_2024_2026.csv`
  (5.2GB); train/oos cuts above. TV log: `~/Downloads/KK_-_Master_VP_OANDA_XAUUSD_2026-06-20.csv`.

---

## 🟢 KenKem E1/E2/E4/E5 — HONEST SWEEP DONE + MT5-READY CANDIDATES (2026-06-21, THIS SESSION)
User: "focus E1/E2/E5/E4; find issues in trash KK-KenKem; rewrite + sweep best combos (RR/ATR/ADX);
I'll MT5-test after. Do NOT mislead me with C++ results again." **Delivered the SWEEP (testable now)
+ made the EA rewrite execution-ready; did NOT ship unvalidated EA logic (that's the next focused pass).**
- **Engine re-verified as a trustworthy measuring stick:** reproduces every documented baseline EXACTLY
  (E1E2E4 +2101, D3-noE4 +1247, D4 +1695/PF1.419, D4+E5 +2092). `make test` 28 OK.
- **Trust boundary (from prior parity work, applied throughout):** E1 entry+exit = trustworthy; E2 entry
  trustworthy / exit mildly optimistic; **E4 exits FICTIONAL (MT5: net loser)**; **E5 ~53% recall + exit
  optimism**. So E4/E5 net/PF are MT5-gated; only E1+E2 engine numbers translate.
- **E4 exit bug NOT fixed (deliberate):** `manage_tick` is shared with the VALIDATED E1/E2 parity; rewriting
  it risks regressing +1247/+1695. E4 verdict stays MT5's. (Task documented.)
- **Sweep (RR/ATR/ADX × individual/combined), full writeup `research/optimization/KENKEM-E1E2E4E5-SWEEP-2026-06-21.md`:**
  confirms the lock is robust at plateau — **no hidden magic combo**. DYN_RR off = the one robust RR lever;
  E1cap3.5 / ATRpct70 / sideways45 / ADX23 / E2-touch60 = the D4 levers. ⚠️ the E4 fiction even flips the
  ADX-gate sign (helps the clean E1+E2 book, craters the E4-contaminated book) → run sweeps E4-OFF.
- **CANDIDATES (flush-left, load into legacy KenKemExpert.ex5; in `research/kenkem_parity/`):**
  `D3-noE4` (✅MT5-CONFIRMED +1049/PF1.39), `D4` (🟡engine-best E1+E2 +1695, entry-side→MT5-confirm),
  `D4-E5` (🔴engine flips 26Q2 −427; MT5 decides), `D4-E4` (🔴engine flips 26Q2 −115 + exits fiction; MT5
  decides), **`D4-E2RR14`** (🟡D4+E2_RR1.4, +1775/PF1.44 — the ONE refinement that survived `d5` joint
  per-quarter testing; cross-age60/E1cap3.0 were base-dependent illusions, D5-all3 flipped 26Q2 −33).
  **4 exact MT5 run asks in the findings doc** (run #1=D4 first; #4=D4-E2RR14 follow-up). Sweep COMPLETE
  (all 9 families in `research/optimization/sweep_logs_2026-06-21/`).
- **EA rewrite = execution-ready, not started:** open question RESOLVED (live path = OOP Entry1/2/4/5
  `Detect()` via `DetectNewEntry`, first-match E1→E2→E3→E4→E5); verbatim input map + lock defaults + module
  order captured in `docs/BUILD-PLAN-KENKEM-REWRITE.md` "Execution-ready facts". Next pass = P1→P6 transcription.

## 🔴 KenKem — CLEAN REWRITE IS THE ACTIVE THRUST (2026-06-21) — read `docs/BUILD-PLAN-KENKEM-REWRITE.md`
**User directive:** the dquants `KK-KenKem` MQL5 EA was TRASH (no profit); the profitable EA the user
runs is the original **KenKemExpert** (`../kenkem`). Everything now lives in dquants; `../kenkem` is
reference only. **Mission: kill KK-KenKem, rewrite it CLEANLY transcribing E1+E2+E5 FAITHFULLY from
KenKemExpert's own MQL5** (NOT the C++ engine — it has E4-exit fiction + E5 ~53% recall). E4 excluded
(MT5 net-loser). Decisions locked: scope=**E1+E2+E5**, source=**KenKemExpert MQL5**. Memory
[[kenkem-clean-rewrite-from-mql-2026-06-21]]. **P0 DONE** (old EA git-rm'd; phased plan written).
Keystone trick: transcribe KenKemExpert input NAMES verbatim → existing `D3-noE4.set` loads directly →
parity = same-`.set` MT5 diff vs `mt5_runs/2026-06-20_D3-noE4/` (+1049/PF1.39/102tr). **NEXT = P1
foundation** (Inputs subset + State + Indicators + Snapshot, compile 0/0). The optimization notes below
(D3-noE4 lock, D4/E5 candidates) remain valid as the param/parity ground truth FOR the rewrite.

## 🟢 KenKem XAU M1 — OPTIMIZATION: D3-noE4 LOCKED (MT5-confirmed) → D4 candidate awaiting MT5 (2026-06-20)
Pivoted parity→profit. Harness `research/optimization/sweep_kenkem_opt.py` (TICK engine; line-mutates a
base `.set`; reports ALL + 2025/2026-OOS + per-quarter; families: `combos sl tp gates cand wf reorder
e1e2 e1e2b`). Data = XAU 2025-03→2026-05 (15mo). Full writeup w/ all evidence:
**`research/optimization/KENKEM-D3-OPT-FINDINGS.md`** (read the top ⚠️ block first).

**⚠️ MAJOR THIS SESSION — engine D3 was INFLATED by an E4 EXIT BUG (MT5 confirm overturned it):**
- Two `.set` runs were silently ignored by MT5 because the preset had **leading whitespace** on every
  line — **MT5's Tester→Load only accepts flush-left `key=value`** (engine parser tolerates indent). FIXED
  (strip WS, re-sync Presets). *Lesson: every KenKem `.set` we ship MUST be flush-left; verify with
  `grep -cE '^[[:space:]]+'` = 0.*
- Real MT5 D3 = **+905 / PF 1.22 / 155 tr** vs engine +2194/PF1.40. Time-aligned diff
  (`research/kenkem_parity/mt5_runs/2026-06-20_D3/`): ENTRY parity FINE (141/155 matched, over/under-fire
  net ~0); **E1 exit-CLEAN** (eng +883 vs MT5 +868); **E4 EXITS BROKEN** — 48/48 matched E4 have IDENTICAL
  entry time+price but engine books +747 vs MT5 **−42** (engine TP where MT5 hits SL; SL levels differ only
  ~0.29 → engine MISSES the intrabar adverse path; engine `maeR` is a 0.00 stub). E2 mildly optimistic.
- ⇒ engine "E4 is best (PF1.51)" + the reorder-rejection rationale are ARTIFACTS. **In MT5, E4 is a net
  LOSER.** Engine sweep numbers carry exit-optimism bias: worst E4, mild E2, ~none E1 (entry-side trustworthy).

**✅ LOCK = D3-noE4 (E4 OFF), `research/kenkem_parity/KK-KenKem-XAUUSD-M1-D4...` → `KK-KenKem-XAUUSD-M1-D3-noE4.set`.**
MT5 A/B confirmed: **+1049 / PF 1.39 / 102 tr** (`mt5_runs/2026-06-20_D3-noE4/`) vs full-D3 +905/PF1.22;
OOS 2026 +243/1.23→**+327/1.47**; profitable quarters 3/6→**4/6** (25Q2 +231, 26Q2 flips −279→+57; only
26Q1 liked E4, outweighed). D3 keys: `USE_DYNAMIC_RR_SCALING=false`, `E1_ATR_SL_CAP_MULTIPLIER=3.5`,
`SIDEWAYS_BLOCK_THRESHOLD=45`, `MIN_ENTRY_ATR_PERCENTILE=70`, **+ `ENABLE_E4_ENTRIES=false`**.

**🆕 D4 CANDIDATE (engine, NOT yet MT5-confirmed) `KK-KenKem-XAUUSD-M1-D4.set` (in Presets, flush-left):**
D3-noE4 **+ `E1_MIN_MOMENTUM_ADX` 19.5→23 + `E2_MAX_TOUCH_AGE` 36→60**. Both are ENTRY filters (the side
the engine models faithfully) → should translate to MT5. Engine ALL +1247→**+1695 / PF 1.42**, Sharpe
2.47→**3.12**, OOS +251→**+293**, per-quarter keeps BOTH 2026 quarters positive (26Q1 +202, 26Q2 +91).
Levers ADDITIVE (e1e2b: S1+ADX23 +1397, S2+TA60 +1470, S3 both +1695). REJECTED: `min_TQ_E1=8` (redundant
w/ ADX23), `E1_RR=1.5` (pooled-OOS +353 illusion — per-quarter 26Q2 FLIPS to −98). ATRpct70 + sideways45
already optimal; E1 HTF-DI & low min_TQ inert; cross-age 100-120 = overfit trap.

▶️ **NEXT ACTIONS (in priority order):**
1. **MT5-confirm D4** — run KenKemExpert (XAU M1, 2025.03.02–2026.05.29, every-tick) w/ `KK-KenKem-XAUUSD-M1-D4.set`.
   Auto-collect→diff vs engine /tmp-style (use `cpp_core/build/kenkem/tick_backtester --set <D4.set> --symbol-xau
   --out X.trades.csv`, then time-align by (minute,dir,kind)). Expect ~+1100–1300 if entry-faithfulness holds.
   If confirmed, D4 becomes the new lock (update preset name + memory + this section).
2. **E5 evaluation (user explicitly asked why E5 was ignored — it was wrongly dismissed on engine numbers).**
   ✅ PRESET READY: `KK-KenKem-XAUUSD-M1-D4-E5.set` (D4 + `ENABLE_E5_ENTRIES=true`, flush-left, staged in
   Presets). Engine reference (DIRECTIONAL only — ~53% E5 recall + exit optimism, [[kenkem-e5-2026-selection-break]]):
   D4 148tr/+1695/PF1.419 → D4+E5 397tr/+2092/**PF 1.184** (E5's 248 tr = +435 @ PF~1.04, dilutes book +
   nibbles E1/E2 via slot contention). Engine says "dilutes", but it MISSES ~half of real E5 + the accidental
   first run = **E5-only +1019/331tr in MT5** → only MT5 settles it. **RUN #2 after D4:** Load D4-E5 preset,
   same XAU M1 2025.03.02–2026.05.29 every-tick; SHIP E5 only if E1+E2+E5 beats D4 on BOTH net AND PF.
3. **Engine E4 intrabar-exit fix** — so future E4/E2 exit sweeps are trustworthy (per-tick barrier check at
   `cpp_core/include/kk/kenkem/trade_manager.hpp:110-114` looks correct; suspect entry-bar arming / exit
   granularity or trail level. The MAE stub should also be implemented for diagnosis). Unlocks revisiting E4.
- Stubborn losers in EVERY config: 25Q1 (sparse early data) + 25Q3 (summer chop) — a session/vol filter is
  the likely lever there (untested).

## 🟢 KenKem E4 — FIRST PARITY DIFF → SL-cap bug fixed → recall 78.7%→94.3% (2026-06-20, commit af8b798)
First-ever E4 benchmark (engine vs `RUN_2026-06-19_..._E4only`, 244 MT5 trades; feed the run's
`inputs_echo.txt` DIRECTLY as `--set` — section headers parse to empty keys, harmless; zero transcription risk).
- **ROOT (systematic): engine SL +39.5% too wide in 190/192 matched** (pinned to the 4.0×ATR cap; MT5 ~2.9×ATR).
  The EA's `CalculateStopLossWithCustomEMA` (EntryBase.mqh) picks cap/floor via `(entryType==1)?E1:E2` →
  **entryType=4 falls through to E2 (cap 3.0/floor 1.1); the `E4_ATR_SL_*` inputs are PARSED but DEAD.**
  Engine had faithfully coded the *documented* 4.0/1.25. Fixed `atr_sl_caps(kind==4)`→e2 bounds.
- **CASCADE (wider SL was binding occupancy/risk limiters, suppressing entries):** matched **192→230 (94.3%)**,
  missed 52→14, overfire 23→24, |Δrisk(SL)| median 0.93→**0.166**, |ΔpnlUSD| median 12.96→**7.96**, exact-min 230/230.
- **E4 recall now MAXED** (with E1 93% / E2 96%): the 14 missed net **−409 (4/14 win, EA-cut losers)** — don't chase.
  Residual SL bias +5.9% = the shared forming-vs-closed ATR floor (E1/E2 have it too; untouched). E1/E2 byte-identical.
- Added `test_e4_sl_uses_e2_cap`. ▶️ **E4 exits not yet diffed** (matched |Δpnl| 7.96 is small; lower priority).
  Next per user's pick: **E1 22-not-armed overfire** (mine committed `kke1arm.csv.gz` vs engine `triggers.hpp`).

## 🟢 KenKem E5 — real-path trace COLLECTED → 1 fix shipped (+8 recall) → residual decomposed (2026-06-20)
_Real-path E5 entry trace ran clean: `mt5_runs/RUN_2026-06-20_1.8.154_xau_2026H1_E5only_realtrace/`
(`realtrace_*.csv` = 4,914 armed/fired E5 bar snapshots w/ the LIVE per-bar `final_decision`; 108 E5 +949).
Engine repro (commit **2f5143c**, `MT5_E5_2026.set`, `--from-ms 1767225600000 --to-ms 1780272000000`).
Full writeup: **`research/kenkem_parity/E5_REALTRACE_FINDINGS.md`**._

_**✅ FIX SHIPPED — `hr_momentum_level(E5)` = NONE (risk_exec.hpp).** EA `Entry5::GetHighRiskMomentumCheck()`
is hardcoded `NONE` (InputParams.mqh NONE=-1) → the E5 high-risk route applies NO momentum gate; the engine
had no kind==5 case so it fell through to `c.hr_momentum_e1`=3 (M1_AND_M3), wrongly filtering E5 HR entries.
**matched 49→57, missed 59→51, recall 45.4→52.8%** (recovered 8 of the 40 HIGH_RISK_ROUTE misses). Golden 28/28._

_**✅ RESIDUAL 51 missed VALUE-DIFFED (v2cols run, this session) — decomposition OVERTURNED.** The richer
realtrace (10 new gate-INPUT cols, kenkem `ebd1bde`) + 2 new env-gated engine dumps (`KK_E5_VALDUMP`:
E5V=M1 EMA stack@B-1/B-2/B-3 + alignment verdict; E5D=M1/M5/M15 DI+ADX closed&forming) → tool
`diff_e5_valuediff.py`. The prior "26 unarmed + 15 htf + 7 trend_core" was a MISATTRIBUTION:_
- _**42 M1 onset/arming** — engine never arms the M1 4-EMA strict-alignment onset (the near-sole root)._
- _**1 htf** — engine M5 **closed** adx/di == EA realtrace EXACTLY (20.7,20.0,17.6); NOT an HTF value diff._
- _**2 trend_core / 2 armed-pass / 4 nojoin** — negligible. HTF & trend-core were arming misclassifications._

_**ROOT (proven, NOT a value/seeding bug):** the onset BAR-PAIRING. `KK_E5_VALDUMP` shift-test → the EA's
logged alignment `ema25` matches the engine stack at **B-1 (m1s1) EXACTLY 42/42** (engine EMA values are
correct == MT5 at the same bar), but the engine onset reads **B-2 (m1s2, faithful)**. **BUT a naive global
fresh shift REGRESSES** (`KK_E5_FRESH_ONSET`: recall 52.8→41.7%, matched 57→45, overfire 33→53) — arming &
fire are coupled, faithful B-2 is net-best. The 42 are marginal near-tie alignment bars._

_**Worth chasing:** the 51 missed MT5 trades net **+466 (53% win)** — REPRESENTATIVE of the full E5 edge
(+949/52%), unlike E1's all-loser misses. Recovering ≈ half the E5 P&L. Full writeup: `E5_REALTRACE_FINDINGS.md`._

### ▶️ NEXT for E5 — DECISION POINT (recall is at the faithful 52.8% ceiling)
The 42 onset misses need the EA's **exact latch internals**, not a shift (the shift regressed). To port
MT5's precise `aligned@cur && !aligned@prv` pairing, the realtrace must add `m_prevBullishAligned`/
`m_prevBearishAligned` (prior-bar alignment) + `m_lastBullishSignal`/`m_lastBearishSignal` (armed-bar idx).
**Options:** (A) add those 4 cols to RealTrace.mqh + 1 more MT5 run → port the exact latch (regression risk,
real +466 edge); (B) accept the 52.8% faithful ceiling and move to **E1/E2/E4** parity (per user's E5→E1
directive). _Recommend B unless the user wants to push E5 recall._ Engine instruments + analysis committed.

## 🎯 (KenKem) Goal: optimize E5 then E1 (user directive). Parity first (foundation), then param sweep.
Ground truth E5 = `research/kenkem_parity/mt5_runs/RUN_2026-06-19_1.8.154_xau_2yr_E5only_cd120/`
(trades.csv 656 trades net +1267 PF 1.10; trace.csv.gz per-bar E5 TraceBar; inputs_echo.txt).

## ▶️ THIS SESSION (2026-06-20) — E5 entry onset FIXED; E5 exit parity is the next blocker
1. **[committed d1704ab] E5 onset off-by-one** — `triggers.hpp` E5 read M1 alignment at B-1/B-2 (1 bar
   too fresh); MT5's trapped GetEMA → onset = aligned@B-2 && !aligned@B-3. Gated on `kFaithful`
   (e5_cur=m1s2, e5_prv=m1s2-1). Result (MT5_E5_ONLY.set vs E5only_cd120):
   matched **295→399**, missed 361→257, overfire 344→233, exact-minute **66→342**, |Δentry| **0.286→0**.
   See memory [[kenkem-e5-onset-trap-fix]]. Tool added: `research/kenkem_parity/diff_e5_trace.py`.
2. **[DIAGNOSED, not fixed] E5 EXIT parity = the P&L gap.** On 399 matched trades: tag-agree 61%,
   engine net **−489 vs MT5 +733** (Δ −1222). Per-cell P&L drain:
   - **EA→SL-LOSS (67): Δ −1826** — MT5 cuts losers early ("EA"); engine rides to full SL. #1 drain.
   - **TP→SL-WIN (25): Δ −1050** — engine trails too tight, exits before MT5 reaches TP.
   - (the full MT5-"EA" row nets ~even +21; the killers are specifically EA→SL-LOSS and TP→SL-WIN.)
   ROOT (partly localized): `exits.hpp:55-63` `panic_exit_enabled`/`score_drop_enabled` for E5
   FALL THROUGH to the E1 flags (stale comment "E3/E5 not used"). In the E5 set E1-panic=true so panic
   IS on, but fidelity differs (per-tick vs once-per-bar ADX-collapse; unmodeled `minADXToHold=18`
   hold-exit + `ENABLE_PRE_BE_STRUCTURE_PROTECTION=true` PRE_BE_TRIGGER_R=0.5 structure SL move +
   E5_TRAILING_SL_FACTOR=0.38 / E5_PARTIAL_TP_TRIGGER=0.8 trailing). Needs E5-specific exit fields +
   panic/pre-BE/trail parity pass.

## ▶️ NEXT ACTIONS (in order)
1. **E5 exit parity**: add `panic_exit_e5`/`score_drop_e5`/`di_flip_e5` config fields + parse
   `ENABLE_*_E5`; route `panic_exit_enabled(5)`→e5 flag. Then attack EA→SL-LOSS (panic ADX-collapse
   fidelity / minADXToHold=18 hold-exit) and TP→SL-WIN (trailing/PRE-BE). Re-diff with
   `matched_exit_crosstab.py`; target matched-net sign-match + tag-agree >80%.
2. **Then E5 sweep** on the C++ engine over real ticks (existing harness: `research/optimization/
   sweep_e5_exits.py`; 9-col table via `report_metrics.py`). Lock best combo in a `.set` under
   `kenkem/MQL5/Presets`. Candidate knobs: E5_MAX_EMA_CROSS_AGE, MIN_TREND_QUALITY_E5,
   E5_MIN_MOMENTUM_ADX, E5_RR, E5_HTF_*, trailing/partial, MIN_ENTRY_ATR_PERCENTILE.
3. Then repeat for E1 (entry parity already ~93%; focus E1 exits + sweep).
4. After E1→E5 locked: pip→ATR-relative per `docs/PIP_TO_ATR_INVENTORY.md`. NOT before.

## 🔁 Repro E5 (~24s tick run, ~4s trace)
```
cd cpp_core && make test && make kenkem_trace kenkem_tick
./build/kenkem/tick_backtester --bars-m1 tools/bars_xauusd_2024_2026_m1.csv \
  --ticks tools/ticks_xauusd_2024_2026.csv --symbol-xau --spread 0.05 \
  --set ../research/kenkem_parity/MT5_E5_ONLY.set --out /tmp/e5.csv
M=research/kenkem_parity/mt5_runs/RUN_2026-06-19_1.8.154_xau_2yr_E5only_cd120/trades.csv
python research/kenkem_parity/diff_kk.py --engine /tmp/e5.csv --mt5 $M --kind E5         # 399/257/233
python research/kenkem_parity/matched_exit_crosstab.py --engine /tmp/e5.csv --mt5 $M     # exit P&L cells
./build/kenkem/trace_dumper --bars-m1 tools/bars_xauusd_2024_2026_m1.csv --symbol-xau \
  --spread 0.05 --set ../research/kenkem_parity/MT5_E5_ONLY.set --out /tmp/e5_trace_eng.csv
python research/kenkem_parity/diff_e5_trace.py --eng /tmp/e5_trace_eng.csv \
  --mt5 research/kenkem_parity/mt5_runs/RUN_2026-06-19_1.8.154_xau_2yr_E5only_cd120/trace.csv.gz
```

## 📌 E1 context (prior sessions, unchanged this session)
Ground truth = MT5 run `research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1E2/`
(echoed inputs in `inputs_echo.txt`; engine `.set` must mirror them exactly).

## ▶️ THIS SESSION — re-ran E1/E2 on this machine; found+fixed the real E1 blocker
Fresh baseline on complete data (162.7M ticks, ~24s/run), all matches exact-minute (pure selection problem):

| Kind | Window | MT5 | Eng | Matched | Missed | Overfire | Recall |
|------|--------|-----|-----|---------|--------|----------|--------|
| E1 | Full      | 183 | 238 | **171** | 12 | 67 | **93.4%** |
| E1 | Gap-free  |  82 | 107 |  **78** |  4 | 29 | **95.1%** |
| E2 | Full      | 142 | 159 | **136** |  6 | 23 | **95.8%** |
| E2 | Gap-free  |  69 |  79 |  **65** |  4 | 14 | **94.2%** |

**ROOT CAUSE of the old "E1 50% recall" = a single config mismatch, NOT an engine bug.**
- `anchor_E1E2.set` had `E1_MAX_CROSS_AGE=28` but the MT5 run echoed **80**. (28 was a live-trading
  "cut over-trading" cap baked into both the set and `kenkem_config.hpp:199` default.) A full set-vs-echo
  diff showed this was the **ONLY** value mismatch of 193 keys.
- Effect: engine expired armed crosses at age 28 while MT5 held them to 80 → MT5 fired E1 on bars the
  engine had already dropped. **Fixed set → E1 recall 50%→93.4%** (matched 92→171, missed 91→12). E2 unchanged.
- Diagnostic that nailed it (reproducible): categorized the old 91 missed E1 via `KK_EMIT_GATE_REASON`:
  56 = armed-then-expired (cross-age!), 18 = never-armed, only **17 gate-blocks (1 sideways)**. The prior
  HANDOFF's "sideways over-block, highest-leverage" was wrong — sideways blocks 1 of 91.
- Also corrected: the "E1↔E2 interaction (78→183 E1)" was a **lot-size artifact** — the E1-only set runs
  `MY_STANDARD_LOT_SIZE=100` (MT5 account limiters choke E1 to 78), the E1E2 set runs 0.15 (limiters off,
  183 fire). Not a real entry interaction.

## 🟡 RESIDUAL = E1 overfire (68 full / 29 gap-free) — NOW LOCALIZED at trade level. E2 overfire 23/14.
Using the new MT5 gate trace (`RUN_2026-06-19_..._E1E2_gatetrace/kke1gate.csv`, 104k per-armed-bar E1
verdicts, aligned at engine = MT5 + 60s), each of the 68 overfire trades was matched to MT5's verdict:
- **41/68 = MT5_BLOCK:mtf** → the engine's MTF (M3/M5 EMA-alignment) gate is too PERMISSIVE; MT5 armed the
  cross and blocked it on MTF, the engine passed & fired. Confusion matrix: 240 bar-evals engine-PASS where
  MT5=mtf (+10 trend_quality); EVERY other gate matches ~100% (htf 58,672/58,832, price_pos/momentum/
  trend_strength/rsi_div clean). NOT a shift bug — M3/M5 reads already use `align_tf-2` (gates.hpp:88,94).
  It's genuine M3/M5 EMA VALUE divergence near the `tol` band.
- **~~22/68 = MT5_not_armed~~ → CORRECTED (2026-06-20): only ~8, and NOT phantom arms.** Cross-referencing
  each of the 67 current overfire against the actual `kke1arm.csv.gz` arm-state at the entry bar: **0 had
  MT5 armU/armD = −1** (the gate-trace "not_armed" label conflated expired/consumed arms). 59/67 = MT5
  DID arm → downstream block (the 41 MTF + ATR/limiter exec). The remaining **8 are arm-TIMING offsets on
  REAL crosses** (engine-early detection e.g. 2024-02-21 13:15 fires 8min before MT5's armU=0@13:23;
  re-arm-after-age-80-expiry e.g. 2025-04-29; one opposite-dir). Net **+377 engine-FAVORABLE, 5/8 wins** →
  NOT worth a fix (regression risk on the 171 matched, heterogeneous, no single bug). The 59 armed-gate
  overfire net only +35 (near-neutral). **CONCLUSION: E1 overfire has NO clean local fix; the only
  actionable lever is the MT5 M3/M5 EMA-at-entry dump (item 3) for the 41 MTF value-diff.**
- 5/68 = MT5_PASS (benign timing/occupancy near-miss).
- Reverse (engine BLOCK where MT5 PASS) is tiny: 8 conviction + 2 mtf + 1 tq = the engine-only conviction
  gate slightly over-blocks → a minor missed-entry source.

## ▶️ NEXT ACTIONS (in order)
1. **[committed]** `E1_MAX_CROSS_AGE=80` in `anchor_E1E2.set` (E1 recall 50→93%). `kenkem_config.hpp:199`
   default stays 28 (live-trading opt) — parity is driven by the `.set`.
2. **[ENGINE, no new MT5 data]** Mine `kke1arm.csv.gz` vs the engine's E1 arm decisions to fix the 22
   MT5_not_armed overfire (cross-detection divergence). diff against the engine's cross-arm logic
   (`triggers.hpp` ema cross arming).
3. **[USER]** One MT5 re-run dumping **M3/M5 EMA1..4 at ENTRY_SHIFT** (the BarTrace lacks them — only M1
   ema0..4 + per-TF ADX/DI present). Needed to value-diff the 41 MTF-gate overfire. This is the long-standing
   M3/M5-alignment ceiling, now pinpointed to exactly the MTF gate.
4. **✅ E4 DONE** (commit af8b798, recall 94.3%) — see the E4 section at the top. Entry recall maxed;
   E4 exits not yet diffed (low priority, matched |Δpnl| 7.96 already small).
5. After E1→E5 LOCKED: pip→ATR-relative per `docs/PIP_TO_ATR_INVENTORY.md`. NOT before.

## 📁 NEW: MT5 gate-trace run (committed this session)
`research/kenkem_parity/mt5_runs/RUN_2026-06-19_1.8.154_xau_2yr_E1E2_gatetrace/` — from
`MT5_E1E2_GATETRACE.set` (≡ reference run + E1_GATE_TRACE/E1_ARM_TRACE). trades.csv (325, **byte-identical
to the reference** → trace didn't perturb logic), kke1gate.csv (104,221), kke1arm.csv.gz (509,662),
trace.csv.gz (per-bar BarTrace), tester.log.gz, inputs_echo.txt. Confusion tool: `diff_gate_reason.py`.

## 🔁 Repro (~24s/run)
```
cd cpp_core && make test                     # 28 checks green
KK_E1_FAITHFUL=1 ./build/kenkem/tick_backtester \
  --bars-m1 tools/bars_xauusd_2024_2026_m1.csv --ticks tools/ticks_xauusd_2024_2026.csv \
  --symbol-xau --spread 0.05 --set ../research/kenkem_parity/anchor_E1E2.set --out /tmp/e1e2.csv
M=research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1E2/trades.csv
python research/kenkem_parity/diff_kk.py --engine /tmp/e1e2.csv --mt5 $M --kind E1   # 171/12/67
python research/kenkem_parity/diff_kk.py --engine /tmp/e1e2.csv --mt5 $M --kind E2   # 136/6/23
# gate-reason diagnostic (categorize missed E1):
KK_E1_FAITHFUL=1 KK_EMIT_GATE_REASON=1 ./build/kenkem/tick_backtester ... 2>/tmp/gr.txt
```

## 📦 Data / instruments
- Complete data: `cpp_core/tools/{bars_xauusd_2024_2026_m1.csv, ticks_xauusd_2024_2026.csv}` (849,963 M1
  bars / 162.7M ticks, 2024-01 → 2026-05). Research parquets `data/processed/ticks_xauusd_{2024,2025,2026}.parquet`.
- MT5 ref runs: `RUN_2026-06-18_1.8.154_xau_2yr_E1E2/` (325 trades = 183 E1 + 142 E2; the diff target) and
  `..._E1only_trace/` (78 E1, lot=100, has `kke1gate.csv`).
- Sets: `anchor_E1E2.set` (E1+E2, lot 0.15, now E1_MAX_CROSS_AGE=80 ✓), `anchor_E1_only_trace.set`
  (E1 only, lot=100 — limiter regime, do not use for the free-fire baseline).
- 3 core engine fixes confirmed PRESENT in this branch (verified by code read): ATR=SMA-of-TR
  (`tf_cache.hpp:42`), MTF-EMA shift (`snapshot.hpp:131`), sideways 5-bar-avg (`snapshot.hpp:85-98`).
