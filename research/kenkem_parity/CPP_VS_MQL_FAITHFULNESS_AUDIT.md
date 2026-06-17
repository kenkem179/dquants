# C++ ↔ MQL5 KenKem faithfulness audit (1:1 mirror check)

_2026-06-17 (Opus 4.8). Module-by-module audit of whether the dquants C++ engine faithfully mirrors
`KenKemExpert.mq5` v1.8.154's pure decision logic. Config audited: E1/E2/E4 ON, E3/E5/news-calendar/
limit-orders OFF, XAUUSD. Method: 8 parallel module audits + manual verification of load-bearing claims._

## VERDICT: NOT 1:1. Detection is mostly faithful; the RISK/LIMITER back-half, EXIT management, and
## dynamic lot-sizing are largely UN-ported, plus three confirmed off-by-one / stage bugs in detection.
Empirically the engine fires 45 trades where the EA executes 9. The audit explains why, mechanistically.

## Architecture note (what 1:1 even means here)
By the Layer-2/Layer-4 design, the C++ is PURE LOGIC; MT5 I/O (alerts, Telegram/Discord, CSV export,
OrderSend/broker plumbing) is intentionally absent and that is CORRECT — not a divergence. The I/O sweep
confirmed alerts + CSV export are cleanly separable (they only read decision state, mutate only
dedup/message-id/log state no gate reads). The ONE exception is `BrokerHelpers.CheckTradeStatusOnBroker…`
which is really the trade-close handler (classifies win/loss/BE, increments session counters gates read)
— and that IS replicated in the tick engine. So "1:1" = the pure decision logic below.

---
## A. FAITHFUL 1:1 (verified matching)
| Module | C++ | Status |
|---|---|---|
| Indicator primitives EMA/ADX/DI/RSI/ATR/Ichimoku math | indicators.hpp, tf_cache.hpp | ✅ match (ADX=MT5 iADX kernel, RSI Wilder, Ichimoku) |
| Snapshot EMA read (`GetEMA(...,1)`=series shift 2) | snapshot.hpp:116 | ✅ bit-exact vs trace |
| E1 gate structure: block-counter HTF, MTF momentum-bypass, extreme-DI=16, price-vs-EMA25, HasSufficientMomentum | entries.hpp case 1, gates.hpp | ✅ match |
| E2 gate structure: HTF require-aligned, M1∧M3∧M5 strict EMA, price-vs-EMA25, TQ≥9, RSI-div, touch-age=36, momentum-omitted | entries.hpp case 2 | ✅ match (but see C3 EMA shift + B1 stage) |
| E4 gate: Ichimoku buffer-SWAP (thickness=real Tenkan/Kijun, color=real Senkou A/B, price-vs-cloud), HTF M5-or-M15 block, M5 DI, EMA stack, ADX min | entries.hpp case 4 | ✅ structurally faithful (buffer-swap correct) |
| Trend-quality / conviction / sideways scoring ARITHMETIC (point values, thresholds, bands, clamps) | scoring.hpp | ✅ formulas match (but see C1 shift) |
| SL entry-placement (EMA-distance, MIN_SL_SPREAD, ATR cap/floor arbitration, buffered SL, per-side RR) | entries.hpp compute_sl/tp | ✅ match |
| Session window boundaries (UTC 0-330 / 500-930 / 1200-1500, inclusive) | kenkem_config.hpp, engine.hpp | ✅ match |
| Per-entry risk ratios (E1 2.10% / E2 2.00% / E4 2.04%), XAU pip/contract/pip-value | kenkem_config.hpp | ✅ match |
| ~40 scoring/RR/SL/threshold param defaults vs InputParams.mqh | kenkem_config.hpp | ✅ spot-checked equal; session keys EA-locked |
| Session-loss / SLTP counters (MAX_SESSION_LOSSES=4 `>=`, MAX_SLTP=7 `>`), reset on session change | tick_engine.hpp:129-228 | ✅ faithfully ported |
| max-concurrent=2, block-opposite-direction, one-detection-per-bar | tick_engine.hpp | ✅ match |

---
## B. CONFIRMED DETECTION BUGS (I verified these by reading the code)
| # | What | MQL | C++ | Severity |
|---|---|---|---|---|
| B1 | **ATR-percentile gate applied at the WRONG STAGE.** EA applies MIN_ENTRY_ATR_PERCENTILE / ATR-high in `GetEntryBlockReason` at EXECUTE — *after* detection sets `detectedTrade.type`, so a detected-but-ATR-blocked E2 still occupies the bar's single slot and SUPPRESSES E4. C++ applies it per-candidate INSIDE the first-match detection loop, so an ATR-failing E2 is skipped and E4 fires on the same bar. Changes which type fires + count. (NOTE: ATR-pctile itself is oracle-proven NOT to be the parity blocker, but the STAGE bug changes priority.) | RiskManager.mqh:284-311 | entries.hpp:123-128 | CRITICAL |
| B2 | **EMA-stack gate reads one bar too old.** `emas_ready_entry`/`m5_directional_ok` read EMA at `align_tf - 3` (series shift 3); the EA's `GetEMA(...,1)` = series shift 2 = `align_tf - 2` (the value the VERIFIED snapshot uses at `i1-1`). gates.hpp:79 comment claims align-3==snapshot shift — it does NOT. Affects E1/E2/E4 EMA-alignment near crossovers. | EMAHelpers.mqh GetEMAValues | gates.hpp:83, 89 | MODERATE (rare flips) |
| B3 | **EMA-touch/cross TRIGGER shift inconsistency.** snapshot got the non-series buffer-trap fix (`i1-1`) but triggers.hpp E1-cross / EMA200-touch / EMA75-touch read EMA lines at plain series shift 1/2, inconsistent with the EA's non-series `GetEMA` mapping. | EMAHelpers.mqh:261-314 | triggers.hpp:85-108 | MODERATE |
| C1 | **Acceleration/ADX read CLOSED bars, EA reads FORMING (shift 0).** trend-quality (M1/M3 accel) + conviction (ADX-accel, RSI-velocity, price-action) read the window {closed1,2,3}; EA reads {forming,1,2}. The whole window is one bar stale → the documented `tqS_e4=8 vs EA 9` "1-pt gap" and a systematic ±1 bias on E2's tight TQ≥9 / CONV≥10 gates. Consistent across all 4 logic agents. | TrendIdentifier.mqh:162, ADXRSIHelpers.mqh:302; EntryHelpers.mqh:111 | scoring.hpp:32-50,120 | CRITICAL (boundary flips) |

---
## C. UN-PORTED RISK / LIMITER LOGIC (the over-fire drivers — 45 vs 9)
Verified: the kenkem engines roll their OWN inline limiters and never use the common `RiskManager` /
`Sessions` classes (those are MasterVP/Monster — dead code for KenKem). Missing:
| # | Missing limiter | MQL | Effect |
|---|---|---|---|
| D1 | **High-risk routing** — `potentialLossUSD >= getMaxLossUSD(type)` → `HandleHighRiskEntry` with its own gates (accept-high-risk, IsInSidewayRange(10), CheckMomentumForLevel, MAX_HIGH_RISK_TRADES=5). In the EA EVERY E2 routed here and was SKIPPED. C++ has no getMaxLossUSD / high-risk branch → opens E2 + high-risk E1/E4 the EA rejects. | mq5:2344-2053 | CRITICAL — #1 over-fire cause |
| D2 | **MIN_SECONDS_BETWEEN_ENTRIES=60** absent in the TICK engine (bar engine has it) | RiskManager.mqh:334 | CRITICAL |
| D3 | **Per-type consecutive-loss timed block** absent in tick engine; bar engine's win-reset resets SAME bucket but EA resets OPPOSITE direction | RiskManager.mqh:46-161 | CRITICAL |
| D4 | **Global losing-streak cooldown** (escalating timed block, vetoes ALL detection) not ported | RiskManager.mqh:30-33,120 | CRITICAL |
| D5 | **MAX_AGGREGATE_RISK_RATIO** open-risk cap not ported | RiskManager.mqh:323 | CRITICAL |
| D6 | **Cross-type E1↔E4 same-direction suppression** (block E1 if same-dir E4 open & vice-versa); C++ `occ[]` only blocks same kind+dir | mq5:2186,2278 | CRITICAL |
| D7 | **Drawdown / recovery / soft-block / signal-only** state machine not ported (rarely binds on short OOS) | RiskManager.mqh:393-705 | MODERATE |
| D8 | **Daily-loss limit** (`max_daily_loss_ratio` parsed, never enforced) | RiskManager.mqh:313 | MODERATE |
| D9 | **Black-swan cooldown + spread / spread-ATR blocks** (only the ATR-high percentile veto exists, not its cooldown side-effect) | RiskManager.mqh:244-302 | MODERATE |

---
## D. UN-PORTED EXIT / TRADE-MANAGEMENT LOGIC (changes SL/TP/exit on essentially every trade)
| # | Missing / divergent | MQL | C++ | Severity |
|---|---|---|---|---|
| E1 | **Partial-TP gating**: EA waits for trend-weakening OR retrace at the trigger; C++ fires partial immediately at the level | TradeManager.mqh:750-754 | trade_manager.hpp:92-101 | CRITICAL |
| E2 | **Breakeven buffer basis**: EA `entry ± origTpDist*beBuf` (TP-distance); C++ `entry ± be_buf*risk` (risk) | TradeManager.mqh:770 | trade_manager.hpp:98 | CRITICAL |
| E3 | **Trailing distance**: EA `origTpDist*trailFactor/(tpExt+1)*volMult` (off TP-dist, shrinks per extension, vol-scaled); C++ `trail_factor*risk` (off risk, flat) | TradeManager.mqh:886 | trade_manager.hpp:103 | CRITICAL |
| E4 | **R-multiple BE @0.87R** (move SL to entry+0.055·risk), ON by default — MISSING | TradeManager.mqh:402-454 | absent | CRITICAL |
| E5 | **Pre-BE structure protection** (ON by default) + **TP extension** (ON, E1 maxExt=40) — MISSING/inert | TradeManager.mqh:284-395,606-669 | absent/inert | CRITICAL |
| E6 | Config-gated exits (ADX-drop, DI-flip, exit-in-cloud, sideway-early, early-cut-near-SL, high-risk-time HIGH_RISK_MAX_BARS) — MISSING | TradeManager.mqh:1044-1519 | absent | MODERATE (toggle-dependent) |

---
## E. UN-PORTED DYNAMIC LOT-SIZING (matches at baseline, diverges as balance/DD move)
Session windows + risk ratios + symbol economics MATCH. Missing in sizing: the `*0.98` risk haircut;
profit-scaling (risk grows with balance); daily/DD risk caps + min-risk floor; and ALL state multipliers
(recovery 0.6 / soft-block 0.3 / profit-protection 0.75 / win-streak 0.60 / recovery-ladder / VOL_LOT).
Config fields exist but are never read in C++ sizing. Plus the missing **12:20-12:45 UTC `AVOID_NEWS_TRADING`
daily veto** (default true, in `IsNowInValidSession`) — the only sizing/session item that changes WHICH
bars can fire. (SessionManager.mqh:120-122; absent in C++.)

---
## Verification status
- Verified by me directly: B1 (stage), B2 (gates align-3 ≠ snapshot align-2), D1 (no high-risk branch in
  tick_engine/entries), E-news (AVOID_NEWS_TRADING default true + 1220-1245 veto, absent in C++).
- High-confidence agent findings (read full files, cited line numbers), not yet re-verified line-by-line:
  the rest of C/D/E. Treat as a strong punch list; re-confirm each at fix time.
- Corrected agent errors: one audit wrongly said "EA never applies MIN_ENTRY_ATR_PERCENTILE" (it does, at
  execute → B1) and wrongly said the gate EMA shift is fine (it's off by one → B2). ATR-pctile remains
  oracle-disproven as the *parity blocker* (separate from B1's stage issue).

## Fix order to REACH 1:1 (recommend)
1. **D1 high-risk routing** + **B1 ATR stage** — biggest over-fire levers (kills phantom E2, restores priority).
2. **D2-D6 limiters** (min-seconds, per-type block, global streak, aggregate-risk, cross-type suppression).
3. **C1 forming-bar accel** (recovers the 1-pt-gap E2/E4) + **B2/B3 EMA shifts**.
4. **E1-E5 exit management** (partial gating, BE/trail basis, R-mult BE, pre-BE, TP-extension).
5. **E lot-sizing** state multipliers + **news veto**.
Re-run the trade diff after each; target engine→EA executed-set parity.
