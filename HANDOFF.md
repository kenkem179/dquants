# HANDOFF — read me first, update me last

_Last updated: 2026-06-17 by Claude (Opus 4.8). Branch `1-reorganize-code`._

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

## 🔄 Stage 2-4 IN PROGRESS (entry/gate/exit parity → match the 9 trades)
With exact indicators the tick engine fires **50 trades (E1 17/E2 16/E4 17) vs MT5 9; 0/9 matched.** The
existing C++ entry layer (`triggers/gates/entries/engine.hpp`) is the OLD DISTILLATION — its own comments
admit gates were "parsed-and-ignored," session is UTC (EA uses JST), concurrency/cooldown are author-added
backstops with knobs, trend-quality is 0-6 not the real 0-13. **Must rebuild faithfully from the EA.**
Tell: MT5 fires ~1 trade/day at session-gated times; C++ fires many/day → missing session + conviction +
trend-quality + RSI-div + concurrency gating.

**4 EA specs DONE** in `research/kenkem_parity/`: `SPEC_E4.md` `SPEC_E1_E2.md` `SPEC_PIPELINE.md`
`SPEC_EXITS.md` (all with file:line). Config audit: **C++ defaults already faithful** (sessions UTC
0-330/500-930/1200-1500 = JST windows, ATR-pctile 65, conviction 7/10/9, tq 6/9/9, RSI-div). So the
over-fire is **gate COMPUTATION**, not config.

**Progress so far (commits 30e8807, <e4>):**
- Fixed RSI raw-vs-avg conflation (conviction/sideways use RAW shift-1 `rsiM1`; trace uses `rsiM1_avg5`).
- **Faithful E4 gate (SPEC_E4 §4 Steps 0-4) → FIRST exact trade match**: C++ `02.17 13:20 S 4913.004`
  == MT5 to the cent. E4 17→12, matched pairs 0→1. Added snapshot `tenkanM3/kijunM3/atrM3`.
- 🪤 **Ichimoku buffer-swap trap (CRITICAL, reusable):** MT5 iIchimoku buffers are 0=Tenkan,1=Kijun,
  2=SenkouA,3=SenkouB,4=Chikou, but the EA's var NAMES are swapped: `ichimokuSpanA/B_M3`=buf0/1=REAL
  Tenkan/Kijun; `ichimokuTenkan/Kijun_M3`=buf2/3=REAL Senkou A/B. So E4 cloud THICKNESS uses real
  Tenkan/Kijun (snapshot.tenkanM3/kijunM3) × atrM3; the "TK-align" check is real SenkouA>SenkouB
  (snapshot.senkouA/B_M3). Verify the same swap in MasterVP/Monster.

### ▶️ NEXT ACTION (resume here)
Current: tick engine **45 trades (E1 17/E2 16/E4 12) vs MT5 9; 1/9 matched.** E1/E2 over-fire is the
big remaining pollution (also occupies concurrency slots + opposite-block, starving the other 6 E4s).
1. **Build an entry-decision trace** (per-bar, per-entry trigger-age + each gate flag + conviction/
   trend-quality scores, mirroring `detect_entry`) — same instrument that cracked Stage 1. Diff at the
   9 MT5 entry bars to localize which gate diverges instead of guessing.
2. **Faithful E1/E2 gates** per `SPEC_E1_E2.md`: E1 add `HasSufficientMomentum` (ADX≥20 confluence + DI
   M1/M3/M5) + ADX≥19.5 floor + E1 HTF = block-counter-only (not require); E2 verify M15-strong-require.
   Check conviction/trend-quality scoring shifts (scoring.hpp reads acceleration at i1; EA uses shift-0).
3. Then concurrency/cooldown faithfulness (MAX_SESSION_LOSSES=4 not modeled; one-per-bar; min_seconds
   off last SUCCESSFUL entry) → then SL/TP + managed exits ("EA" tag) to match exitPrice/realizedUsd.
4. Re-diff each step: `tick_backtester` → `research/validation/parity_diff.py`. Target 9/9.
5. Then **Stage 5** KK-KenKem regen; then **MasterVP**, then **MonsterEdition** (read Pine).

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
