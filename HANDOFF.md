# HANDOFF — read me first, update me last

_Last updated: 2026-06-17 by Claude (Opus 4.8) — faithful E1/E2 done; ATR wall ratified; over-fire is next. Branch `1-reorganize-code`. Build GREEN, tests pass._

## 🎯 Goal (CLEAN-SLATE RESET — autopilot, 3 strategies)
User was "super disappointed" by the distilled KK-KenKem and ordered a faithful rewrite, then expanded
to autopilot across THREE strategies. The arc: **C++ reproduces the original EA EXACTLY → use C++ for
fast param sweeps → port the tuned logic BACK to MQL5.** Order: **KenKem → MasterVP → MonsterEdition**
(for Monster, read the Pine code properly — user named it). Acceptance: C++ trades == MT5 trades within
tick-fill tolerance, then regenerate the EA from the same logic so it ties out at baseline.

**Ground truth = the original EA source** (read it, never guess). For KenKem:
`kenkem/MQL5/Experts/KenKem/KenKemExpert.mq5` + its `Core/`,`Entries/`,`TradeManagement/`,`Utils/` mqh.

## ✅ Anchor LOCKED · ✅ Stage 1 DONE (indicators bit-exact)
Anchor: latest `KenKemExpert.mq5` @ defaults · XAUUSD M1 · every-tick real ticks · **Feb 2026** ·
deposit 10000 / 1:500 · config E1+E2+E4 on, E3+E5 off.
MT5 ground truth: `kenkem/Tester/Agent-127.0.0.1-3000/MQL5/Files/KenKem/{trades,trace}_XAUUSD-Exness-KK.csv`
(9 trades: E4×7,E1×1,E2×1; 27379-row bar trace).

**Stage 1 (commit `680e55d`): 5/6 indicator families now bit-exact** vs the MT5 trace (joined
`cpp_ts−60000 == mt5_ts`): ema0-4 Δ0.00008, rsi Δ0.00046, high/low Δ0.00001, close/adx ~0. ATR Δ0.31 is
a documented ~2% tick-completeness residual (NOT formula — bid/mid/ask all give 0.306). Full write-up +
THE REUSABLE METHODOLOGY: **`research/kenkem_parity/INDICATOR_PARITY_SPEC.md`**. Fixes were in
`indicators.hpp` (rsi_wilder_mt5/step), `tf_cache.hpp` (rsi_ag/al), `snapshot.hpp` (per-indicator shifts:
EMA i1-2, ATR/RSI/high-low forming-bar-first-tick). The EMA "shift 1" is really shift 2 — non-series
`CopyBuffer` index inversion. This trap WILL recur in MasterVP/Monster.

## 🔄 Stage 2-4 IN PROGRESS — CURRENT: validation config (ATR gate off) = **4/9 matched, 129 trades** (commit `26955b5`)
Build GREEN, all C++ tests pass. The faithful entry layer is now ported (E1/E2/E4 gates, scoring, RSI-div);
**4 EA specs** in `research/kenkem_parity/` (`SPEC_E4/E1_E2/PIPELINE/EXITS.md`, file:line). Two gaps remain:
the **over-fire** (downstream limiters — the big lever) and a **1-point acceleration gap** (5 trades). See
▶️ NEXT ACTIONS below. History of how we got here (durable traps worth keeping):

- Config audit: C++ defaults already faithful (sessions UTC 0-330/500-930/1200-1500 = JST windows,
  ATR-pctile 65, conviction 7/10/9, tq 6/9/9, RSI-div). Over-fire is gate COMPUTATION + limiters, not config.
- RSI raw-vs-avg conflation fixed (conviction/sideways use RAW shift-1 `rsiM1`; trace uses `rsiM1_avg5`).
- **Faithful E4 gate (SPEC_E4 §4 Steps 0-4) → FIRST exact trade match**: C++ `02.17 13:20 S 4913.004`
  == MT5 to the cent. Added snapshot `tenkanM3/kijunM3/atrM3`.
- 🪤 **Ichimoku buffer-swap trap (CRITICAL, reusable):** MT5 iIchimoku buffers are 0=Tenkan,1=Kijun,
  2=SenkouA,3=SenkouB,4=Chikou, but the EA's var NAMES are swapped: `ichimokuSpanA/B_M3`=buf0/1=REAL
  Tenkan/Kijun; `ichimokuTenkan/Kijun_M3`=buf2/3=REAL Senkou A/B. So E4 cloud THICKNESS uses real
  Tenkan/Kijun (snapshot.tenkanM3/kijunM3) × atrM3; the "TK-align" check is real SenkouA>SenkouB
  (snapshot.senkouA/B_M3). Verify the same swap in MasterVP/Monster.

### ✅ DONE (commits `2d7117a`, `45d0722`)
- **Faithful E1/E2 gates** ported 1:1 from `Entry1.mqh`/`Entry2.mqh` (ADX floor, HTF block-counter for
  E1 / require-aligned for E2, MTF m1&((m3&m5dir)||extremeDI), price-vs-EMA25, HasSufficientMomentum).
  **Gate EMA reads now use the GetEMA(...,1) non-series entry shift `align.tf-3`** (was raw shift-1 →
  off by 2). New helpers in `gates.hpp` (incl. `#include triggers.hpp` for `emas_ready`).
- **ATR-percentile recipe** fixed: distribution = closed ATR shifts **1..32** (was off-by-one), ref =
  **closed-bar ATR** (= MT5 `cache.atrM1`, proven by trace; first-tick forming model was ~7% low).
- **New tool `tools/kenkem/entry_trace_dumper.cpp`** (`build/kenkem/entry_trace`) — per-bar E1/E2/E4
  gate-decision trace (first failing gate + tq component breakdown). The localizer that cracked this.

### 🧱 THE WALL (RESOLVED — tick-fidelity-limited, decision ratified below)
`detect_entry` runs **once per bar at the new-bar's first tick** (KenKemExpert.mq5:2494). The dominant
entry filter is **MIN_ENTRY_ATR_PERCENTILE=65 + ATR_HIGH_BLOCK>90** (RiskManager.mqh:284-308, under
`ENABLE_BLACK_SWAN_PROTECTION=true`). At all 9 MT5 entries the MT5 percentile sits 68-88 (passes); mine
swings wildly and wrongly blocks ~3. **Root cause:** percentile *ranking* is hypersensitive to the
irreducible ±0.2/bar ATR noise between the exported ticks and MT5's internal tick stream. My M1 bars are
ALREADY tick-accurate (tick-built ATR == my bar ATR to 4 dp) → **NOT fixable by rebuilding**. Proof:
disabling the 2 ATR gates lifts matched pairs **1→4** (engine 47→129 trades).

### ✅ DECISION RATIFIED (user, 2026-06-17): disable MIN_ENTRY_ATR_PERCENTILE + ATR_HIGH for the parity
diff ONLY. ⚠️ User says this ATR-regime filter is a PROFITABILITY lever for MasterVP/Monster — never
delete it; keep + sweep once parity holds. Validation set: `/tmp/noatr.set` (MIN_ENTRY_ATR_PERCENTILE=0,
ENABLE_ATR_HIGH_BLOCK=false). See [[atr-percentile-parity-wall]].

### ▶️ NEXT ACTIONS (resume here) — commit `45d0722`, build GREEN, validation config = **4/9 matched, 129 trades**
The 5 still-missed MT5 trades (ATR off) are ALL a **1-point acceleration gap**: 3 E4 trend-quality 8-vs-9,
1 E2 conviction 9-vs-10. Cause = EA reads iADX **shift-0 (forming)** in HasTrendAcceleration; first-tick
model is right for M1 but wrong for M3/M5 (partial bar) and HURT parity → reverted to closed-bar window.
1. **OVER-FIRE is the big lever** (129→9): downstream limiters not faithfully modeled — verify in
   `engine.hpp`/`tick_engine.hpp`: **MAX_SESSION_LOSSES=4**, one-entry-per-bar (`lastEntryBarIndex`),
   min-seconds-off-last-SUCCESSFUL-entry, block-opposite, max_concurrent=2, day cap, MAX_SLTP_COUNT=7.
   Use `build/kenkem/entry_trace` at the 103 engine-only bars to see which limiter SHOULD block.
2. **Acceleration gap** (optional, for the last ~4 trades): model M3/M5 forming bars by aggregating M1
   bars in the current HTF bucket up to decision time (reuse `kk::ind::dmi_adx_mt5_form`), then feed
   {forming,closed,closed-1} to `kk_trend_accel`/`kk_adx_accel`. Non-trivial; do AFTER over-fire.
3. Then SL/TP + managed exits ("EA" tag) → exitPrice/realizedUsd. Re-diff each step. Target 9/9.
4. Then **Stage 5** KK-KenKem regen; then **MasterVP**, then **MonsterEdition** (read Pine).

**Tooling:** `cpp_core/tools/kenkem/entry_trace_dumper.cpp` (`build/kenkem/entry_trace`) — per-bar
E1/E2/E4 first-failing-gate + tq component breakdown (stderr in `--only` mode). The Stage-2 localizer.

⚠️ EXITS caveat: `SPEC_EXITS.md` was mapped for the E5 path; our config is E1/E2/E4 — re-verify the
E1/E2/E4 exit toggles (panic/score-drop/session-end) before porting exits.

## 🔑 Key facts / gotchas
- Rebuild + run: `cd cpp_core && make kenkem_tick kenkem_trace && make test`. Binaries in `build/kenkem/`.
- Trade diff window-aligns automatically. Trace diff MUST join `cpp_ts−60000 == mt5_ts`.
- **Tick engine only** for P&L ([[bar-engine-systemic-defect]]). EMA non-series shift-2 trap. shift-0 =
  forming bar first-tick (O=H=L=C=open), model as one Wilder step — never read the future bar's OHLC.
- Edit the DEPLOY EA at `dquants/mql5/experts/KenKem/` ([[deploy-ea-is-dquants-mql5-symlinked]]).
- Python: `~/miniforge3/envs/kenkem/bin/python`. Per-step: test→commit→push→tick docs.
- Staged data: `cpp_core/tools/{ticks_xauusd_2026feb.csv, bars_xauusd_2025h2_2026_m1.csv}`.

## 📚 Durable refs
`research/kenkem_parity/INDICATOR_PARITY_SPEC.md` (Stage 1 + methodology) · `ANCHOR1_FINDINGS_2026-02.md` ·
`REFERENCE_RUN_RECIPE.md` · `research/validation/parity_diff.py` · `docs/KENKEM_QUANT_OS.md` ·
`~/.claude/.../memory/MEMORY.md` ([[kenkem-clean-rewrite-2026-06]]).
