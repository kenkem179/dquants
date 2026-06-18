# Pip → ATR-relative conversion inventory

Goal: eliminate every hardcoded pip value / pip-denominated param and re-express ATR-relative.
**Sequencing: do this AFTER per-entry MT5 parity (E1→E2→E4→E5) is locked.** Parity is the ground truth;
converting first destroys the reference. The 3-digit-gold `pip_size` 0.01-vs-0.001 bug (10× wrong EMA
tolerance) is exactly the class of fragility this removes.

Convention for each: today `param_pips × pip_size` (a price distance). Target `param_atr × ATR` (ATR = the
EA's M1 ATR used elsewhere). Keep EA input ↔ engine field 1:1 so parity holds by construction. Pick each
`param_atr` default so that at a representative ATR it ≈ the current pip distance, then re-tune on a plateau.

## A. DECISION params expressed in pips — CONVERT (engine field ← EA input, default)
| # | Engine field (`kenkem_config.hpp`) | EA input (`InputParams.mqh`) | default | used by | notes |
|---|---|---|---|---|---|
| 1 | `ema_align_tol_pips` | `EMA_ALIGNMENT_TOLERANCE_PIPS` | 23.0 | E1/E2 arm + MTF gate (`triggers.hpp:61`, `entries.hpp:126`) | ⭐ most impactful — the arm-tolerance |
| 2 | `rsi_div_min_price_pips` | `RSI_DIV_MIN_PRICE_DIFF_PIPS` | 60 | RSI-divergence veto (`scoring.hpp:265/271`) | already compared as price diff |
| 3 | `tp_ext_min_pips` | `TP_EXTENSION_MIN_PIPS` | 7.0 | TP extension (exit) | |
| 4 | `tp_ext_max_pips` | `TP_EXTENSION_MAX_PIPS` | 60.0 | TP extension (exit) | |
| 5 | `e5_min_sl_pips` | `E5_MIN_SL_PIPS` | 50.0 | E5 min SL floor (`entries.hpp:66`) | |
| 6 | `sl_ema_distance` | `SL_EMA_DISTANCE` | 27 | SL offset below/above EMA (`entries.hpp:76-77`) | int "pips" |
| 7 | `min_sl_spread_mult` | `MIN_SL_SPREAD_MULT` | 0.5 | SL min vs spread | spread-relative, not pip — review |
| 8 | (EA-only?) | `MAX_SPREAD_PIPS` | 0.0 | spread gate | 0 today (inactive); spread is its own scale |
| 9 | (exit-side) | `PRE_BE_BOS_BREACH_BUFFER_PIPS` | 1.0 | pre-breakeven structure | exit layer |
| 10 | (exit-side) | `PRE_BE_SWING_BUFFER_PIPS` | 8 | pre-breakeven | exit layer |
| 11 | (exit-side) | `PRE_BE_MIN_SL_IMPROVEMENT_PIPS` | 2 | pre-breakeven | exit layer |
| 12 | (E3, disabled) | `E3_SL_EMA_BUFFER` | 40 | E3 SL | E3 off — low priority |

## B. Hardcoded pip LITERALS in code — CONVERT
- `entries.hpp:225`: `5.0 * c.pip_size` — E1 price-gate threshold (bare 5 pips). EA equiv in the E1 price check.
- (sweep for any other bare `N * pip_size` / `* _Point` constants during conversion.)

## C. P&L / value scaling — DO **NOT** convert (these are contract value, must stay pip/point based)
- `risk_exec.hpp:64` `pointValue = contract_size * pip_size`; EA `:1802` same. Defines money-per-price-move.
- Lot-sizing `baselineATR / pipSize` (EA `:340`) is a display; the underlying risk math uses pointValue.

## D. Display/derived only (distance ÷ pip_size for logging) — harmless, leave or drop
- EA `riskPips/rewardPips/savedPips/bufferPips/trailPips` (logging). `scoring.hpp:100` `avgGap` (scoring —
  used in a decision, so its scale matters; revisit when converting #1).

## Open questions for the user
- ATR source for normalization: the M1 ATR already in the snapshot (`s.atrM1`)? Same period the EA uses?
- One global ATR multiple per concept, or keep per-entry granularity (E1/E2/E4/E5 separate)?
- Exit-layer pips (#9-11, TP ext) in the same pass, or entries-first then exits?
