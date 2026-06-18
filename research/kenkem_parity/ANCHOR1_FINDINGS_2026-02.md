# Anchor #1 diagnosis — KenKemExpert XAU M1 Feb 2026 (real ticks)

First real ground-truth diff of the clean rewrite. **Verdict: wholesale divergence — the existing C++
is a deliberate distillation, not a faithful port. Data + EMA/ADX are correct; rebuild the strategy layer.**

## Trade-level (parity_diff.py)
- **MT5: 9 trades** (E4×7, E1×1, E2×1) · net −208.89 · PF 0.632 · exits mostly managed "EA"
- **C++: 49 trades** (E1×21, E2×16, E4×12) · net −532 · PF 0.880
- **matched pairs: 0 / 9.** Zero temporal overlap. C++ over-fires ~5× AND has the wrong entry mix
  (MT5 is E4-dominated; C++ is E1/E2-dominated).

## Indicator parity (bar-trace diff, best-shift per field over Feb)
| field | best shift | Δ@best | meaning |
|---|---|---|---|
| close | −1 | **0.0001** | **bars are EXACTLY MT5's** — parquet ticks == MT5 feed (verified) |
| ema0/1/4 | **+1** | **0.0001** | EMA *formula* correct, but series sits **2 bars off** from close/ADX |
| adx_m1/m3, diP | −1 | **0.0000** | ADX/DI formula correct, shift consistent with close |
| atr | −1 | 0.43 | **genuine formula/source diff** (EA reads ATR shift-0; Wilder seeding) |
| rsi | 0 | 2.18 | **genuine formula diff** (MT5 Wilder RSI not matched) |

(tenkan/kijun/senkou diffs are expected — the EA emits 0 in the E5 trace; ignore.)

## Root cause (decisive)
1. **`snapshot.hpp:5-6` states it outright:** *"We are NOT byte-matching the MT5 EA (the user authorized
   distilling KenKem to its essential winning core)."* The whole engine (snapshot/gates/entries/exits)
   was built as an approximation. **That mandate is revoked** → the strategy layer must be re-derived
   faithfully from `KenKemExpert.mq5`.
2. EMA/ADX/DI **formulas are correct and reusable**; only the EMA series **alignment** is off (a tf_cache
   indexing bug — close/ADX land at shift −1, EMA at +1, a 2-bar internal gap).
3. **ATR & RSI need MT5-faithful formulas** (ATR shift-0 + Wilder; RSI Wilder) — see [[kenkem-parity-traps]].
4. The over-fire + wrong mix = distilled gates (missing conviction / RSI-div / trend-quality / sessions /
   high-risk momentum checks the real EA applies, esp. on E1/E2).

## Reusable vs rewrite
- **Keep:** bar loader, EMA/ADX/DI formulas (`kk::ind`), the tick-replay harness, config loader, parity
  CSV schema, parity_diff.py, the trace tooling.
- **Rewrite faithfully (from the EA):** snapshot shift convention (ENTRY_SHIFT=1, ALL fields one shift),
  ATR/RSI formulas, triggers, the full gate/quality/conviction/RSI-div/ATR-pctile/session stack, SL/TP,
  and the managed exit path (partial/BE/trail/ladder/panic/score-drop/session-end).

## Next: Stage 1 = indicator parity to ~0
Lock one shift convention so close+ema+adx+atr+rsi ALL match the MT5 trace at the SAME shift, fix ATR
(shift-0/Wilder) and RSI (Wilder). Re-run the bar-trace diff → expect ~0 on every indicator column
before touching entries. Reference run: `REFERENCE_RUN_RECIPE.md`. Data staged in `cpp_core/tools/`.
