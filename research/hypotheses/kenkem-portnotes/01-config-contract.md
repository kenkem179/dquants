# KenKem EA — Config Contract (Port Notes 01)

Source of truth (read directly, do not paraphrase formulas):
- `kenkem/MQL5/Experts/KenKem/Config/InputParams.mqh` (694 lines)
- `kenkem/MQL5/Experts/KenKem/Config/RuntimeConfig.mqh` (79 lines)
- Supporting (for runtime wiring): `Core/GlobalState.mqh`, `Core/Indicators/EMAHelpers.mqh`,
  `KenKemExpert-1.8.154-dev.mq5` (OnInit)

**Scope of this port:** Only entries **E1, E2, E4** are being ported. E3, E5, adaptive, news,
limit-orders, and conservative-trade-management are OUT of scope but their input names are listed so
they can be deliberately ignored.

> ⚠️ **Port-critical surprise up front:** the *declared* EMA input defaults are **10 / 25 / 71 / 97 /
> 192** (NOT the "round" 10/25/75/100/200). And `RuntimeConfig.mqh` contains a SECOND, contradictory
> hardcoded EMA set (25/75/100/200) in `CFG.emaFast/emaMid/emaSlow/emaLong` — **that CFG set is dead
> code**; the live EMAs come from the `INPUT_EMA*_PERIOD` inputs via `EMA_PERIOD_ARRAY`. See §3 and §5.

---

## 1. Complete `input` declaration table

Note: MQL5 treats only declarations prefixed with the `input` keyword as user-tunable. Many globals in
this file are plain `double`/`int`/`bool` (NO `input` keyword) — they are effectively compile-time
constants, not optimizer-exposed. The "input?" column records this distinction exactly as written.

### GENERAL ACCOUNT AND SYMBOL SETUP
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| INITIAL_ACCOUNT_BALANCE | double | 3500.0 | no | Auto-detected from account; fallback if detection fails |
| LEVERAGE | int | 500 | no | (none) |
| MY_STANDARD_LOT_SIZE | double | 0.15 | yes | My Standard Lot Size |
| MAX_HIGH_RISK_TRADES_PER_SESSION | int | 5 | yes | (none) |
| MAX_SLTP_COUNT_PER_SESSION | int | 7 | yes | (none) |
| MAX_SESSION_LOSSES | int | 4 | yes | Hard stop: block new entries after N real losses per session |
| AUTO_DETECT_SYMBOL_PARAMS | bool | true | no | Auto-detect pip size and contract size from symbol info |
| PIP_SIZE | double | 0.01 | no | Fallback pip size if auto-detect disabled |
| CONTRACT_SIZE | double | 100 | no | Fallback contract size if auto-detect disabled |

### QUICK STRATEGY CUSTOMIZATION
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| MAX_DAILY_LOSS_RATIO | double | 0.072 | yes | (none) |
| ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN | double | 0.105 | yes | (none) |
| ACCOUNT_DD_RATIO_TO_SOFT_BLOCK | double | 0.13 | yes | "Soft" block at x% DD (continue with micro lots) |
| SOFT_BLOCK_LOT_MULTIPLIER | double | 0.3 | yes | Lot multiplier in soft block mode |
| ENABLE_E1_ENTRIES | bool | true | yes | Enable E1 trend discovery strategy |
| ENABLE_E2_ENTRIES | bool | true | yes | Enable E2 pull back strategy |
| ENABLE_E3_ENTRIES | bool | false | yes | Enable E3 trend reversal strategy |
| ENABLE_E4_ENTRIES | bool | true | yes | Enable E4 smart early trend strategy |
| ENABLE_E5_ENTRIES | bool | false | yes | Enable E5 SuperBros EMA alignment strategy |
| COMMON_MAX_RISK_PER_TRADE | double | 0.02 | yes | (none) |
| MAX_LOSS_RATIO_E1 | double | `COMMON_MAX_RISK_PER_TRADE * 1.05` (= 0.021) | no | (derived) |
| MAX_LOSS_RATIO_E2 | double | `COMMON_MAX_RISK_PER_TRADE * 1` (= 0.02) | no | (derived) |
| MAX_LOSS_RATIO_E3 | double | `COMMON_MAX_RISK_PER_TRADE * 0.97` (= 0.0194) | no | (derived) |
| MAX_LOSS_RATIO_E4 | double | `COMMON_MAX_RISK_PER_TRADE * 1.02` (= 0.0204) | no | (derived) |
| MAX_LOSS_RATIO_E5 | double | `COMMON_MAX_RISK_PER_TRADE * 1.0` (= 0.02) | no | (derived) |
| INCREASE_LOT_SIZE_BASED_ON_PROFIT | bool | true | yes | (none) |
| VOL_LOT_ADJ_E1 | bool | false | yes | E1: Scale lots by volatility (default:FALSE) |
| VOL_LOT_ADJ_E2 | bool | false | yes | E2: Scale lots by volatility (default:FALSE) |
| VOL_LOT_ADJ_E3 | bool | false | yes | E3: Scale lots by volatility (default:TRUE) [comment contradicts value] |
| VOL_LOT_ADJ_E4 | bool | false | yes | E4: Scale lots by volatility (default:FALSE) |
| VOL_LOT_ADJ_E5 | bool | false | yes | E5: Scale lots by volatility (default:FALSE) |

### GENERAL RISK MANAGEMENT
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| MAX_AGGREGATE_RISK_RATIO | double | `MAX_LOSS_RATIO_E1 * 4` (= 0.084) | no | (derived) |
| RECOVERY_MODE_TRIGGER_RATIO | double | 0.9 | yes | (none) |
| RECOVERY_MODE_EXIT_RATIO | double | 0.95 | yes | (none) |
| RECOVERY_MODE_LOT_MULTIPLIER | double | 0.6 | yes | (none) |
| RECOVERY_MODE_BOOST_MULTIPLIER | double | 0.65 | yes | (none) |
| SIGNAL_ONLY_DURING_PROTECTION | bool | true | yes | Send signals but block trades in DD/Recovery/SoftBlock modes |
| VOL_LOT_MIN_MULT | double | 0.4 | yes | Min lot multiplier for adjustment (high volatility) |
| VOL_LOT_MAX_MULT | double | 1.2 | yes | Max lot multiplier for adjustment (low volatility) |
| E1_USE_RECOVERY_LADDER | bool | false | no | E1: Use gradual recovery (OFF for trend-following) |
| E2_USE_RECOVERY_LADDER | bool | false | no | E2: Use gradual recovery (OFF) |
| E3_USE_RECOVERY_LADDER | bool | true | no | E3: Use gradual recovery (ON for counter-trend) |
| E4_USE_RECOVERY_LADDER | bool | false | no | E4: Use gradual recovery (OFF - same as E1) |
| E5_USE_RECOVERY_LADDER | bool | false | no | E5: Use gradual recovery (OFF) |
| RECOVERY_LADDER_STEP | double | 0.10 | no | Step size for lot adjustment (10%) |
| RECOVERY_LADDER_MIN_MULT | double | 0.30 | no | Minimum recovery lot multiplier (40%) [comment says 40, value 0.30] |
| RECOVERY_LADDER_MAX_MULT | double | 1.00 | no | Maximum recovery lot multiplier (100%) |

### PEAK BALANCE DECAY (Recovery Escape)
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| ENABLE_PEAK_BALANCE_DECAY | bool | true | yes | Gradually ease peak during recovery |
| PEAK_DECAY_GRACE_HOURS | int | 40 | yes | Hours before decay starts (3 days grace) |
| PEAK_DECAY_INTERVAL_HOURS | int | 20 | yes | How often to apply decay (daily) |
| PEAK_DECAY_RATE | double | 0.10 | yes | Fraction of gap to close per interval (10%) |
| PEAK_DECAY_MAX_TOTAL | double | 0.50 | yes | (none) |

### CONVICTION SCORING (0-12 scale)
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| USE_CONVICTION_SCORING_E1 | bool | true | no | E1: DISABLED - Conviction scoring filters GOOD early entries (ADX not yet high) |
| CONVICTION_THRESHOLD_E1 | int | 7 | yes | E1: Min score 6/12 (NOT USED when disabled) |
| USE_CONVICTION_SCORING_E2 | bool | true | no | E2: DISABLED - Test E1 first, then enable |
| CONVICTION_THRESHOLD_E2 | int | 10 | yes | E2: Min score 5/12 (50%=balanced, 6=conservative) |
| USE_CONVICTION_SCORING_E3 | bool | false | no | E3: DISABLED - Counter-trend needs separate validation |
| CONVICTION_THRESHOLD_E3 | int | 6 | no | E3: Min score 6/12 (50%=balanced, 7=58%, 8=67%) |
| USE_HTF_VETO_E1 | bool | false | no | E1: HTF veto (blocks if against M3/M5 trend, integrated in conviction) |
| USE_HTF_VETO_E2 | bool | false | no | E2: HTF veto (blocks if against M3/M5 trend) |
| USE_HTF_VETO_E3 | bool | false | no | E3: HTF veto (not needed for reversal entries) |
| USE_CONVICTION_SCORING_E4 | bool | true | no | E4: Conviction scoring (same as E1 - early trend) |
| CONVICTION_THRESHOLD_E4 | int | 9 | yes | E4: Min score 8/12 (stricter than E1 - early entry needs higher quality) |
| USE_HTF_VETO_E4 | bool | false | no | E4: HTF veto (same as E1) |

### TREND QUALITY SCORING (0-11 scale, +1 for ATR)
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| ENABLE_TREND_QUALITY_GATES | bool | true | yes | Gate: require ADX>=1, DI>=1, MTF>=1 before scoring (blocks weak-trend inflation) |
| MIN_TREND_QUALITY_E1 | int | 6 | yes | E1: Min score 7/11 (64%=strict, +1 for ATR component) |
| USE_ICHIMOKU_E1 | bool | true | no | E1: Add Ichimoku Cloud alignment bonus (0-2 points) |
| MIN_TREND_QUALITY_E2 | int | 9 | yes | E2: Min score 9/11 (82%=strict, +1 for ATR component) |
| USE_ICHIMOKU_E2 | bool | false | no | E2: Add Ichimoku Cloud alignment bonus (0-2 points) |
| MIN_TREND_QUALITY_E4 | int | 9 | yes | E4: Min trend quality (v1.7.993: was 7, now HARD BLOCK) |
| USE_ICHIMOKU_E4 | bool | false | no | E4: NO Ichimoku bonus - Pine uses E1's score which excludes Ichimoku (Ichi is the TRIGGER, not quality) |
| MIN_TREND_QUALITY_E5 | int | 5 | yes | E5: Min trend quality (Pine v1-stable default 5/11; 0=disabled). NO Ichimoku — score range 0-11. |
| USE_ACCELERATION_BONUS | bool | true | yes | Add bonus points for trend acceleration |
| ICHIMOKU_TENKAN | int | 9 | no | Ichimoku Tenkan-sen period |
| ICHIMOKU_KIJUN | int | 26 | no | Ichimoku Kijun-sen period |
| ICHIMOKU_SENKOU | int | 52 | no | Ichimoku Senkou Span B period |

### SIDEWAYS DETECTION FOR ENTRY BLOCKING
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| MAX_SPREAD_PIPS | double | 0.0 | yes | Block entries when spread exceeds this (0 = disabled) |
| SPREAD_BLOCK_CONSECUTIVE_BARS | int | 3 | yes | Require N consecutive high-spread bars before blocking (avoids single-tick spikes) |
| MAX_SPREAD_ATR_RATIO | double | 0.30 | yes | Block if spread > ATR * this ratio (0 = disabled). E.g., 0.30 = 30% of ATR |
| ATR_SIDEWAYS_PERCENTILE | double | 30.0 | yes | ATR percentile below this = sideways market (0=disabled) |
| SIDEWAYS_BLOCK_THRESHOLD | int | 53 | yes | (none) |
| SIDEWAYS_WARNING_THRESHOLD | int | 43 | yes | (none) |
| ENABLE_SIDEWAY_EARLY_EXIT | bool | false | yes | (none) |
| SIDEWAY_EXIT_CONSECUTIVE_BARS | int | 4 | yes | (none) |
| EMA_SPREAD_TIGHT_ATR | double | 1.75 | yes | (none) |
| EMA_SPREAD_MODERATE_ATR | double | 3.25 | yes | (none) |
| EMA_SPREAD_WIDE_ATR | double | 4.0 | yes | (none) |
| ATR_PERCENTILE_LOW | double | 20.0 | yes | (none) |
| ATR_PERCENTILE_HIGH | double | 90.0 | yes | Block entries when ATR > this percentile (0 = disabled) |
| ENABLE_ATR_HIGH_BLOCK | bool | true | yes | Toggle ATR-too-high entry blocking (false = allow entries in volatile markets) |
| MIN_ENTRY_ATR_PERCENTILE | double | 65.0 | yes | Min ATR percentile for all entries (0=disabled, 55=active regime filter) |
| ATR_PERCENTILE_LOOKBACK | int | 32 | yes | (none) |
| ENABLE_BLACK_SWAN_PROTECTION | bool | true | yes | Enable Black Swan volatility spike protection |
| BLACKSWAN_BLOCK_COOLDOWN_MINS | int | 10 | yes | (none) |

### LOT SCALING FINE-TUNING
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| PROFIT_SCALING_WEIGHT_CURRENT | double | 0.65 | yes | Weight for current balance in profit scaling (0.65 = 65%) |
| PROFIT_SCALING_WEIGHT_INITIAL | double | 0.35 | yes | Weight for initial balance in profit scaling (0.35 = 35%) |
| MIN_RISK_FLOOR_RATIO | double | 0.005 | yes | Minimum risk floor (0.5% of account) to allow any trade |

### PROFIT PROTECTION (High Water Mark)
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| ENABLE_PROFIT_PROTECTION | bool | true | yes | (none) |
| PROFIT_PROTECTION_TRIGGER_RATIO | double | 0.3 | yes | (none) |
| PROFIT_PROTECTION_LOT_MULTIPLIER | double | 0.75 | yes | (none) |
| MIN_PROFIT_TO_PROTECT_RATIO | double | 0.05 | yes | (none) |

### WINNING STREAK COOLDOWN
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| ENABLE_WIN_STREAK_COOLDOWN | bool | true | yes | (none) |
| WIN_STREAK_COOLDOWN_TRIGGER | int | 3 | yes | (none) |
| WIN_STREAK_COOLDOWN_LOT_MULT | double | 0.60 | yes | (none) |
| WIN_STREAK_COOLDOWN_TRADES | int | 2 | yes | (none) |
| MAX_CONSECUTIVE_LOSSES_PER_ENTRY_TYPE | int | 3 | yes | (none) |
| ENTRY_BLOCK_AFTER_CONSECUTIVE_LOSS_MINS | int | 60 | yes | (none) |
| LOSING_STREAK_ESCALATION_THRESHOLD | int | 2 | yes | (none) |
| MAX_CONCURRENT_POSITIONS_ALLOWED | int | 2 | yes | (none) |
| BLOCK_OPPOSITE_DIRECTION_ENTRIES | bool | true | yes | CRITICAL: Block entries opposing active positions (prevents hedge losses) |
| CLOSE_ALL_TRADES_AT_SESSION_END | bool | true | yes | (none) |

### ENTRY SETUP AND EXECUTION
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| ENTRY_SHIFT | int | 1 | yes | Bar shift for entry detection (0=current bar, 1=previous bar) |
| USE_LIVE_PRICE_FOR_ENTRY_NOT_CLOSED_PRICE | bool | false | no | Use current live price for entry |

### STOP LOSS CONFIGURATION
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| SL_EMA_DISTANCE | int | 27 | yes | SL distance from EMA 100/200 (in pips) |
| MIN_SL_SPREAD_MULT | double | 0.5 | yes | (none) |
| E1_USE_ATR_SL_ARBITRATION | bool | true | yes | E1: Enable ATR vs Structure SL arbitration |
| E1_ATR_SL_CAP_MULTIPLIER | double | 4.0 | yes | E1: Max SL = ATR * this (caps wide SL) |
| E1_ATR_SL_FLOOR_MULTIPLIER | double | 1.2 | yes | E1: Min SL = ATR * this (floors tight SL) |
| E2_USE_ATR_SL_ARBITRATION | bool | true | yes | E2: Enable ATR vs Structure SL arbitration |
| E2_ATR_SL_CAP_MULTIPLIER | double | 3.0 | yes | E2: Max SL = ATR * this (caps wide SL) |
| E2_ATR_SL_FLOOR_MULTIPLIER | double | 1.1 | yes | E2: Min SL = ATR * this (floors tight SL) |
| E3_USE_ATR_SL | bool | true | yes | E3: Use pure ATR-based SL |
| E3_ATR_MULTIPLIER_SL | double | 3.0 | yes | E3: SL = ATR * this (1.0-1.5 for reversals) |
| E4_USE_ATR_SL_ARBITRATION | bool | true | yes | E4: Use ATR SL arbitration (like E1) |
| E4_ATR_SL_CAP_MULTIPLIER | double | 4.0 | yes | E4: ATR SL cap multiplier |
| E4_ATR_SL_FLOOR_MULTIPLIER | double | 1.25 | yes | E4: ATR SL floor multiplier |
| E5_USE_ATR_SL_ARBITRATION | bool | false | yes | E5: ATR SL arbitration (OFF by default - Pine uses EMA200) |
| E5_ATR_SL_CAP_MULTIPLIER | double | 4.0 | yes | E5: ATR SL cap multiplier |
| E5_ATR_SL_FLOOR_MULTIPLIER | double | 1.2 | yes | E5: ATR SL floor multiplier |
| ATR_PERIOD_FOR_SL | int | 14 | yes | ATR calculation period |
| ATR_LOOKBACK_FOR_ADAPTIVE | int | 120 | yes | Long-term ATR lookback (vol adjustment) |
| TRADE_SLTP_MAX_RETRIES | int | 12 | yes | Max retries for SL/TP modification after order |
| TRADE_SLTP_RETRY_DELAY_MS | int | 80 | yes | Delay between retries (milliseconds) |
| RANGE_HI_LOW_LOOK_BACK_BARS | int | 18 | yes | Range Hi/Lo lookback window (bars) |
| MIN_SECONDS_BETWEEN_ENTRIES | int | 60 | yes | Minimum seconds between any entries |
| HIGH_RISK_MAX_BARS | int | 70 | yes | Max bars to hold high-risk trades (30-50 recommended) |

### MOMENTUM FILTERING
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| MIN_MOMENTUM_ADX_REQUIRED | double | 19.7 | yes | Minimum ADX for momentum confirmation (v1.7.66: 19.0) |
| ADX_LOW_THRESHOLD | double | 14.5 | yes | ADX < this => weak or no trend (v1.7.66: 13.5) |
| ADX_HIGH_THRESHOLD | double | 25.0 | yes | ADX > this => very strong trend |
| REQUIRE_ADX_CONFLUENCE | bool | true | yes | ADX confluence required (v1.7.66: true) |
| EMA_ALIGNMENT_TOLERANCE_PIPS | double | 23.0 | yes | Allow EMA misalignment within X pips (0=strict, 25=lenient) |

### RSI DIVERGENCE VETO (E1/E2/E4)
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| ENABLE_RSI_DIVERGENCE_VETO | bool | true | yes | Block entries when RSI diverges against trade direction on M3 |
| RSI_DIV_LOOKBACK | int | 16 | yes | M3 bars to scan for divergence (10 = ~30 min window) |
| RSI_DIV_MIN_PRICE_DIFF_PIPS | double | 60 | yes | Min price difference between swing points (pips, filters noise) |
| RSI_DIV_MIN_RSI_DIFF | double | 6.5 | yes | Min RSI difference for valid divergence (points, filters noise) |

### EXTREME MOMENTUM BYPASS
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| EXTREME_DI_SPREAD_THRESHOLD | double | 16.0 | yes | DI spread >= this triggers extreme momentum bypass |
| EXTREME_RSI_THRESHOLD_HIGH | double | 70.5 | yes | RSI >= this for long signals extreme momentum |
| EXTREME_RSI_THRESHOLD_LOW | double | 29.5 | yes | RSI <= this for short signals extreme momentum |

### DYNAMIC TP/SL SETUP
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| ENABLE_PRE_BE_STRUCTURE_PROTECTION | bool | true | yes | Tighten SL before BE on structure break in trade direction |
| PRE_BE_TRIGGER_R | double | 0.5 | yes | Min profit in R before pre-BE structure SL tightening is allowed |
| PRE_BE_BOS_LOOKBACK_BARS | int | 6 | yes | Lookback bars (excluding breakout bar) to define prior structure |
| PRE_BE_BOS_BREACH_BUFFER_PIPS | double | 1.0 | yes | Minimum breach distance beyond prior structure (pips) |
| PRE_BE_SWING_BUFFER_PIPS | int | 8 | yes | SL buffer from breakout candle extreme (pips) |
| PRE_BE_MIN_SL_IMPROVEMENT_PIPS | int | 2 | yes | Minimum SL improvement per update (pips) |
| PRE_BE_REQUIRE_M3_ACCEL_CONFIRM | bool | true | yes | Require M3 acceleration confirmation to reduce M1 fake breaks |
| R_MULT_BE_TRIGGER | double | 0.87 | yes | Move SL to BE when profit reaches this × risk (1.0=1R, 0.8=0.8R, 0=disabled) |
| R_MULT_BE_BUFFER | double | 0.055 | yes | Buffer above entry when moving to BE (2% of risk distance) |
| ALLOW_PARTIAL_TP | bool | true | yes | (none) |
| ALLOW_TP_EXTENSION | bool | true | yes | (none) |
| MIN_TP_PROGRESS_FOR_EXTENSION | double | 0.92 | yes | (none) |
| PARTIAL_TP_RETRACE_RATIO | double | 0.15 | yes | (none) |
| USE_DYNAMIC_TP_EXTENSION | bool | true | yes | (none) |
| USE_DYNAMIC_RR_SCALING | bool | true | yes | (none) |
| ATR_TP_EXTENSION_MULTIPLIER | double | 0.035 | yes | (none) |
| TP_EXTENSION_MIN_PIPS | double | 7.0 | yes | (none) |
| TP_EXTENSION_MAX_PIPS | double | 60.0 | yes | (none) |
| ENABLE_EARLY_CUT_NEAR_SL | bool | false | yes | (none) |
| ENABLE_FAST_ADX_PANIC_EXIT_E1 | bool | true | yes | (none) |
| ENABLE_FAST_ADX_PANIC_EXIT_E2 | bool | true | yes | (none) |
| ENABLE_FAST_ADX_PANIC_EXIT_E3 | bool | true | yes | (none) |
| ENABLE_FAST_ADX_PANIC_EXIT_E4 | bool | true | yes | (none) |
| ENABLE_FAST_ADX_PANIC_EXIT_E5 | bool | true | yes | E5: Exit when ADX collapses (prevents holding dying trades) |
| ENABLE_SCORE_DROP_EXIT_E1 | bool | false | yes | (none) |
| SCORE_DROP_THRESHOLD_E1 | int | 3 | yes | (none) |
| ENABLE_SCORE_DROP_EXIT_E2 | bool | true | yes | (none) |
| SCORE_DROP_THRESHOLD_E2 | int | 2 | yes | (none) |
| ENABLE_SCORE_DROP_EXIT_E3 | bool | true | yes | (none) |
| SCORE_DROP_THRESHOLD_E3 | int | 3 | yes | (none) |
| ENABLE_SCORE_DROP_EXIT_E4 | bool | true | yes | E4: Exit on momentum score drop (0-6 scale, includes Ichimoku cloud position) |
| SCORE_DROP_THRESHOLD_E4 | int | 3 | yes | E4: Momentum drop threshold (2 = moderate sensitivity) |
| ENABLE_SCORE_DROP_EXIT_E5 | bool | false | yes | E5: Score drop exit (OFF - no momentum tracking) |
| SCORE_DROP_THRESHOLD_E5 | int | 3 | yes | E5: Score drop threshold |
| SCORE_DROP_CONSECUTIVE_CHECKS | int | 3 | yes | (none) |
| ENABLE_ADX_DROP_BASED_EXIT | bool | false | yes | (none) |
| ADX_DROP_EXIT_BARS | int | 3 | yes | (none) |
| PANIC_MIN_SL_USED_RATIO | double | 0.6 | yes | (none) |
| PANIC_MIN_SL_USED_RATIO_E3 | double | 0.45 | yes | (none) |
| PANIC_MIN_PROFIT_GIVEBACK | double | 0.5 | yes | (none) |
| ENABLE_DI_FLIP_FAST_EXIT_E1 | bool | false | yes | (none) |
| ENABLE_DI_FLIP_FAST_EXIT_E2 | bool | false | yes | (none) |
| ENABLE_DI_FLIP_FAST_EXIT_E3 | bool | false | yes | (none) |
| ENABLE_DI_FLIP_FAST_EXIT_E4 | bool | false | yes | (none) |
| ENABLE_DI_FLIP_FAST_EXIT_E5 | bool | false | yes | (none) |
| DI_FLIP_MIN_SPREAD_M1 | double | 4.0 | yes | Min opposing DI spread on M1 to confirm flip |
| DI_FLIP_MIN_ADX_M1 | double | 18.0 | yes | Min ADX at flip time (below = noise, no energy) |
| DI_FLIP_CONSECUTIVE_M1_BARS | int | 2 | yes | Consecutive M1 bars required to confirm flip |
| DI_FLIP_MIN_SL_USED_RATIO | double | 0.4 | yes | Min fraction of SL consumed before exit fires |

### E1 TRADE MANAGEMENT (Trend Continuation)
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| BLOCK_E1_WHEN_E4_ACTIVE | bool | false | yes | E1: Block E1 detection when E4 trade is active |
| E1_HTF_TREND_FILTER | HTF_TREND_MODE enum | HTF_M5_ONLY (=1) | yes | (none) |
| E1_HTF_MIN_ADX | double | 18.5 | yes | (none) |
| E1_HTF_MIN_DI_SPREAD | double | 4.0 | yes | (none) |
| ACCEPT_HIGH_RISK_E1_ENTRIES | bool | true | yes | Enable high-risk E1 entries with strict momentum filters |
| HIGH_RISK_E1_MOMENTUM_CHECK | HIGH_RISK_MOMENTUM_LEVEL enum | M1_AND_M3 (=3) | yes | E1 momentum strictness for high-risk entries (RECOMMENDED: E1_ACCEL_M1_OR_M3) |
| E1_HIGH_RISK_MIN_ADX | double | 19.5 | yes | E1: Min ADX for high-risk (early trend, slightly lower OK) |
| E1_HIGH_RISK_MIN_DI_SPREAD | double | 4.0 | yes | E1: Min DI spread for high-risk (early trend) |
| HIGH_RISK_TP_MULTIPLIER_ASIA | double | 0.65 | yes | High-risk TP % for ASIA session (conservative - low volatility) |
| HIGH_RISK_TP_MULTIPLIER_EU | double | 0.65 | yes | High-risk TP % for EU session (baseline - moderate volatility) |
| HIGH_RISK_TP_MULTIPLIER_US | double | 0.7 | yes | High-risk TP % for US session (aggressive - high volatility) |
| E1_MIN_MOMENTUM_ADX | double | 19.5 | yes | (none) |
| E1_MAX_CROSS_AGE | int | 80 | yes | E1: Max bars since EMA cross (stale trigger expiry) |
| E1_MOMENTUM_BYPASS_LEVEL | int | 1 | yes | (none) |
| E1_RR | double | 1.9 | yes | Entry 1's Reward (KEM) |
| E1_RR_SIDEWAY | double | 1.2 | yes | Entry 1's Reward 2 (CHE in KEM) |
| E1_PARTIAL_TP_TRIGGER | double | 0.90 | yes | E1: Take partial at 90% (let trends run longer) |
| E1_PARTIAL_TP_RATIO | double | 0.20 | yes | E1: Take only 20% partial (keep 80% riding) |
| E1_SL_TO_BREAKEVEN_BUFFER | double | 0.07 | yes | E1: BE buffer (7% - tight protection after partial) |
| E1_TRAILING_SL_FACTOR | double | 0.40 | yes | E1: Trailing 40% = generous room for trend continuation |
| E1_MAX_TP_EXTENSIONS | int | 40 | yes | E1: More extensions (40x - trends can run far) |
| E1_EARLY_CUT_SL_RATIO | double | 0.89 | yes | E1: Early cut at 89% to SL |
| E1_ENABLE_LADDERED_EXTENSIONS | bool | true | yes | E1: Enable Phase 2 laddered TP extensions after partial TP |
| E1_LADDER_STAGE1_MULTIPLIER | double | 1.05 | yes | E1: Stage 1 profit target |
| E1_LADDER_STAGE2_MULTIPLIER | double | 1.11 | yes | E1: Stage 2 profit target |
| E1_LADDER_STAGE3_MULTIPLIER | double | 1.17 | yes | E1: Stage 3 profit target |
| E1_LADDER_STAGE1_TRAIL_RATIO | double | 0.45 | yes | E1: Stage 1 trailing SL ratio (45% - wider for runners) |
| E1_LADDER_STAGE2_TRAIL_RATIO | double | 0.55 | yes | E1: Stage 2 trailing SL ratio (55%) |
| E1_LADDER_STAGE3_TRAIL_RATIO | double | 0.65 | yes | E1: Stage 3 trailing SL ratio (65% - max room) |

### E2 TRADE MANAGEMENT (Secondary Continuation)
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| ACCEPT_HIGH_RISK_E2_ENTRIES | bool | true | yes | Enable high-risk E2 entries (more selective than E1) |
| HIGH_RISK_E2_MOMENTUM_CHECK | HIGH_RISK_MOMENTUM_LEVEL enum | M1_AND_M3 (=3) | yes | E2 momentum strictness for high-risk entries |
| E2_HIGH_RISK_MIN_ADX | double | 21.5 | yes | E2: Min ADX for high-risk (pullback, need stronger) |
| E2_HIGH_RISK_MIN_DI_SPREAD | double | 5.0 | yes | E2: Min DI spread for high-risk (pullback) |
| E2_MIN_MOMENTUM_ADX | double | 20.0 | yes | E2: Min ADX for momentum (pullback, need stronger) |
| E2_MAX_TOUCH_AGE | int | 36 | yes | E2: Max bars since EMA75 touch to allow entry (expire stale triggers) |
| E2_HTF_TREND_FILTER | HTF_TREND_MODE enum | HTF_M15_ONLY (=3) | yes | E2: HTF trend filter mode (matches E1/E4 pattern) |
| E2_HTF_MIN_ADX | double | 23.0 | yes | E2: Min HTF ADX for valid trend signal |
| E2_HTF_MIN_DI_SPREAD | double | 3.0 | yes | E2: Min HTF DI spread for valid trend signal |
| E2_RR | double | 1.575 | yes | Entry 2's Reward |
| E2_RR_SIDEWAY | double | 1.1 | yes | Entry 2's Reward 2 (in sideway market) |
| E2_PARTIAL_TP_TRIGGER | double | 0.70 | yes | E2: Partial TP trigger (70% - balanced) |
| E2_PARTIAL_TP_RATIO | double | 0.25 | yes | E2: Take 20% partial (keep 80% riding) [comment says 20, value 0.25] |
| E2_SL_TO_BREAKEVEN_BUFFER | double | 0.07 | yes | E2: BE buffer (7% - balanced) |
| E2_TRAILING_SL_FACTOR | double | 0.45 | yes | E2: Trailing SL (45% - moderate room for continuation) |
| E2_MAX_TP_EXTENSIONS | int | 30 | yes | (none) |
| E2_EARLY_CUT_SL_RATIO | double | 0.88 | yes | E2: Early cut at 88% to SL |
| E2_ENABLE_LADDERED_EXTENSIONS | bool | true | yes | E2: Enable Phase 2 laddered TP extensions after partial TP |
| E2_LADDER_STAGE1_MULTIPLIER | double | 1.04 | yes | E2: Stage 1 profit target |
| E2_LADDER_STAGE2_MULTIPLIER | double | 1.09 | yes | E2: Stage 2 profit target |
| E2_LADDER_STAGE3_MULTIPLIER | double | 1.14 | yes | E2: Stage 3 profit target |
| E2_LADDER_STAGE1_TRAIL_RATIO | double | 0.40 | yes | E2: Stage 1 trailing SL ratio (40% - balanced) |
| E2_LADDER_STAGE2_TRAIL_RATIO | double | 0.50 | yes | E2: Stage 2 trailing SL ratio (50%) |
| E2_LADDER_STAGE3_TRAIL_RATIO | double | 0.60 | yes | E2: Stage 3 trailing SL ratio (60%) |

### E4 TRADE MANAGEMENT (Ichimoku Cloud Cross - Early Trend)
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| BLOCK_E4_WHEN_E1_ACTIVE | bool | false | yes | (none) |
| E4_MAX_SIDEWAY_SCORE | int | 40 | yes | (none) |
| E4_REQUIRE_M5_DI_ALIGN | bool | true | yes | (none) |
| E4_HTF_TREND_FILTER | HTF_TREND_MODE enum | HTF_M5_OR_M15 (=4) | yes | (none) |
| E4_HTF_MIN_ADX | double | 20.5 | yes | (none) |
| E4_HTF_MIN_DI_SPREAD | double | 6.0 | yes | (none) |
| ACCEPT_HIGH_RISK_E4_ENTRIES | bool | true | yes | (none) |
| HIGH_RISK_E4_MOMENTUM_CHECK | HIGH_RISK_MOMENTUM_LEVEL enum | E1_ACCEL_M1_AND_M3 (=11) | yes | (none) |
| E4_HIGH_RISK_MIN_ADX | double | 20.5 | yes | (none) |
| E4_HIGH_RISK_MIN_DI_SPREAD | double | 4.0 | yes | (none) |
| E4_MIN_MOMENTUM_ADX | double | 19.75 | yes | (none) |
| E4_MIN_CLOUD_THICKNESS_ATR_MULT | double | 0.11 | yes | Min current cloud thickness (ATR multiplier, 0=disabled) |
| E4_REQUIRE_TENKAN_KIJUN_ALIGN | bool | true | yes | Require Tenkan > Kijun (LONG) / Tenkan < Kijun (SHORT) |
| E4_REQUIRE_CHIKOU_CLEAR | bool | false | yes | Require Chikou span clear of price 26 bars ago |
| E4_MOMENTUM_BYPASS_LEVEL | int | 1 | yes | (none) |
| E4_MAX_CROSS_AGE | int | 20 | yes | (none) |
| E4_RR | double | 2.4 | yes | (none) |
| E4_RR_SHORT | double | 1.8 | yes | (none) |
| E4_RR_SIDEWAY | double | 1.15 | yes | (none) |
| E4_PARTIAL_TP_TRIGGER | double | 0.7 | yes | (none) |
| E4_PARTIAL_TP_RATIO | double | 0.2 | yes | (none) |
| E4_SL_TO_BREAKEVEN_BUFFER | double | 0.07 | yes | (none) |
| E4_TRAILING_SL_FACTOR | double | 0.5 | yes | E4: Disabled - no trailing SL [comment misleading; value 0.5 active] |
| E4_MAX_TP_EXTENSIONS | int | 30 | yes | E4: Max TP extensions (same as E1) |
| E4_EARLY_CUT_SL_RATIO | double | 0.85 | yes | (none) |
| E4_ENABLE_LADDERED_EXTENSIONS | bool | true | yes | (none) |
| E4_LADDER_STAGE1_MULTIPLIER | double | 1.1 | yes | E4: Stage 1 profit target |
| E4_LADDER_STAGE2_MULTIPLIER | double | 1.18 | yes | E4: Stage 2 profit target |
| E4_LADDER_STAGE3_MULTIPLIER | double | 1.27 | yes | E4: Stage 3 profit target |
| E4_LADDER_STAGE1_TRAIL_RATIO | double | 0.45 | yes | E4: Stage 1 trailing SL ratio (same as E1) |
| E4_LADDER_STAGE2_TRAIL_RATIO | double | 0.55 | yes | E4: Stage 2 trailing SL ratio (same as E1) |
| E4_LADDER_STAGE3_TRAIL_RATIO | double | 0.65 | yes | E4: Stage 3 trailing SL ratio (same as E1) |

### ICHIMOKU CLOUD EARLY EXIT
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| EXIT_IN_ICHI_CLOUD_E1 | bool | false | yes | E1: Exit if price closes inside cloud for N bars |
| EXIT_IN_ICHI_CLOUD_E2 | bool | false | yes | E2: Exit if price closes inside cloud for N bars |
| EXIT_IN_ICHI_CLOUD_E4 | bool | false | yes | E4: Exit if price closes inside cloud for N bars |
| ICHI_CLOUD_EXIT_BARS | int | 3 | yes | Consecutive bars in cloud to trigger exit |

### HIGH RISK OVERRIDE (Optional Aggressive Exit)
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| ALLOW_HIGH_RISK_PARTIAL_TP_OVERRIDE | bool | true | yes | (none) |
| HIGH_RISK_PARTIAL_TP_TRIGGER | double | 0.55 | yes | (none) |
| HIGH_RISK_PARTIAL_TP_RATIO | double | 0.42 | yes | (none) |

### INDICATOR PERIODS (group commented out — plain globals, NOT inputs)
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| RSI_LEN | int | 14 | no | RSI period for super trend |
| ADX_LEN | int | 14 | no | ADX period (standard) |
| RSI_BULL_LEVEL | double | 70.0 | no | RSI > this => bullish momentum |
| RSI_BEAR_LEVEL | double | 30.0 | no | RSI < this => bearish momentum |

### SESSION SETUP (group commented out — plain globals)
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| IGNORE_VALID_SESSIONS | bool | false | no | DANGER: Ignore KEM's Valid Sessions |
| JAPAN_START | int | 900 | no | Tokyo Session Start (JST) |
| JAPAN_END | int | 1230 | no | Tokyo Session End (JST) |
| LONDON_START | int | 1400 | no | Post Tokyo -> London Session Start (JST) |
| LONDON_END | int | 1830 | no | London Session End (JST) |
| NY_START | int | 2100 | no | New York Session Start (JST) |
| NY_END | int | 2400 | no | New York Session End (JST) |

(Session times appear under the NEWS group in source order; grouped here logically. `AVOID_NEWS_TRADING`
and the news inputs themselves are listed in the OUT-OF-SCOPE section below.)

### OTHERS / misc plain globals
| Variable | Type | Default | `input`? | Trailing `//` comment |
|---|---|---|---|---|
| showDebug | bool | true | yes | Show Debug Info |
| ENABLE_CSV_EXPORT | bool | false | no | Export trade data to CSV (analytics only - disable for performance) |
| ENABLE_EMAIL_ALERTS | bool | false | no | Enable email alerts |
| EMAIL_SUBJECT_PREFIX | string | `"KenKem " + VERSION` | no | Email subject prefix |
| minimumLotSize | double | 0.01 | no | Minimum Lot Size (0.01 for XAUUSD) |
| FEE_PERCENT | double | 0.01 | no | Fee per trade (%) |
| MARGIN_LEVEL_PERCENT | int | 30 | no | Maintenance Margin Level (%) |
| ALLOWED_ACCOUNT_ID | string | "" | no | Internal: empty=any account, set by release script |

### TIMEFRAME + EMA CONFIGURATION
(Full verbatim block in §3.) Inputs: `INPUT_TF0..INPUT_TF4`, `INPUT_EMA0_PERIOD..INPUT_EMA4_PERIOD`.

---

## 2. In-scope vs out-of-scope inputs

### IN SCOPE — needed for E1 / E2 / E4 parity
- **Symbol/account mechanics:** INITIAL_ACCOUNT_BALANCE, LEVERAGE, MY_STANDARD_LOT_SIZE,
  AUTO_DETECT_SYMBOL_PARAMS, PIP_SIZE, CONTRACT_SIZE, minimumLotSize, FEE_PERCENT, ENTRY_SHIFT.
- **Entry enables:** ENABLE_E1_ENTRIES, ENABLE_E2_ENTRIES, ENABLE_E4_ENTRIES.
- **Risk per trade:** COMMON_MAX_RISK_PER_TRADE, MAX_LOSS_RATIO_E1/E2/E4, MAX_AGGREGATE_RISK_RATIO,
  MIN_RISK_FLOOR_RATIO, the lot-scaling weights, VOL_LOT_* (E1/E2/E4 variants).
- **Conviction / trend-quality gates:** USE_CONVICTION_SCORING_E1/E2/E4, CONVICTION_THRESHOLD_E1/E2/E4,
  USE_HTF_VETO_E1/E2/E4, ENABLE_TREND_QUALITY_GATES, MIN_TREND_QUALITY_E1/E2/E4,
  USE_ICHIMOKU_E1/E2/E4, USE_ACCELERATION_BONUS, ICHIMOKU_TENKAN/KIJUN/SENKOU.
- **Momentum filtering:** MIN_MOMENTUM_ADX_REQUIRED, ADX_LOW_THRESHOLD, ADX_HIGH_THRESHOLD,
  REQUIRE_ADX_CONFLUENCE, EMA_ALIGNMENT_TOLERANCE_PIPS, and all E1/E2/E4 `*_MIN_MOMENTUM_ADX`,
  `*_HIGH_RISK_MIN_ADX`, `*_HIGH_RISK_MIN_DI_SPREAD`, `*_HTF_*`, `*_MOMENTUM_BYPASS_LEVEL`,
  `*_MAX_CROSS_AGE`, E2_MAX_TOUCH_AGE, ACCEPT_HIGH_RISK_E1/E2/E4_ENTRIES,
  HIGH_RISK_E1/E2/E4_MOMENTUM_CHECK, E4_REQUIRE_M5_DI_ALIGN, E4_MAX_SIDEWAY_SCORE,
  E4_MIN_CLOUD_THICKNESS_ATR_MULT, E4_REQUIRE_TENKAN_KIJUN_ALIGN, E4_REQUIRE_CHIKOU_CLEAR.
- **RSI divergence veto** (explicitly E1/E2/E4): ENABLE_RSI_DIVERGENCE_VETO, RSI_DIV_LOOKBACK,
  RSI_DIV_MIN_PRICE_DIFF_PIPS, RSI_DIV_MIN_RSI_DIFF.
- **Extreme momentum bypass:** EXTREME_DI_SPREAD_THRESHOLD, EXTREME_RSI_THRESHOLD_HIGH/LOW.
- **SL config (E1/E2/E4 variants):** SL_EMA_DISTANCE, MIN_SL_SPREAD_MULT,
  E1/E2/E4_USE_ATR_SL_ARBITRATION, E1/E2/E4_ATR_SL_CAP_MULTIPLIER, E1/E2/E4_ATR_SL_FLOOR_MULTIPLIER,
  ATR_PERIOD_FOR_SL, ATR_LOOKBACK_FOR_ADAPTIVE, RANGE_HI_LOW_LOOK_BACK_BARS.
- **TP/RR + management:** E1_RR/E1_RR_SIDEWAY, E2_RR/E2_RR_SIDEWAY, E4_RR/E4_RR_SHORT/E4_RR_SIDEWAY,
  all E1/E2/E4 PARTIAL_TP_*, SL_TO_BREAKEVEN_BUFFER, TRAILING_SL_FACTOR, MAX_TP_EXTENSIONS,
  EARLY_CUT_SL_RATIO, ENABLE_LADDERED_EXTENSIONS + LADDER_STAGE*/TRAIL_RATIO, the shared DYNAMIC TP/SL
  block, R_MULT_BE_*, PRE_BE_* block, HIGH_RISK_TP_MULTIPLIER_*, HIGH_RISK_PARTIAL_TP_* override.
- **Exit logic (E1/E2/E4 variants):** ENABLE_FAST_ADX_PANIC_EXIT_E1/E2/E4 (+ PANIC_* shared),
  ENABLE_SCORE_DROP_EXIT_E1/E2/E4 + SCORE_DROP_THRESHOLD_E1/E2/E4 + SCORE_DROP_CONSECUTIVE_CHECKS,
  ENABLE_DI_FLIP_FAST_EXIT_E1/E2/E4 + DI_FLIP_* shared, EXIT_IN_ICHI_CLOUD_E1/E2/E4 + ICHI_CLOUD_EXIT_BARS.
- **Sideways/ATR regime + protection blocks** (apply to all entries incl. E1/E2/E4): the entire
  SIDEWAYS DETECTION group, PROFIT PROTECTION, WIN STREAK COOLDOWN, PEAK BALANCE DECAY, GENERAL RISK
  MANAGEMENT (recovery mode), session limits (MAX_*_PER_SESSION, MAX_SESSION_LOSSES,
  CLOSE_ALL_TRADES_AT_SESSION_END, BLOCK_OPPOSITE_DIRECTION_ENTRIES, MAX_CONCURRENT_POSITIONS_ALLOWED).
- **Timeframe + EMA config:** INPUT_TF0..TF4, INPUT_EMA0_PERIOD..EMA4_PERIOD, RSI_LEN, ADX_LEN,
  RSI_BULL_LEVEL, RSI_BEAR_LEVEL.
- **Session windows** (entry gating): IGNORE_VALID_SESSIONS, JAPAN/LONDON/NY_START/END.

### OUT OF SCOPE — list so they can be deliberately ignored
- **E3 (counter-trend reversal):** ENABLE_E3_ENTRIES, MAX_LOSS_RATIO_E3, VOL_LOT_ADJ_E3,
  E3_USE_RECOVERY_LADDER, USE_CONVICTION_SCORING_E3, CONVICTION_THRESHOLD_E3, USE_HTF_VETO_E3,
  E3_USE_ATR_SL, E3_ATR_MULTIPLIER_SL, E3_RR, E3_RR_SIDEWAY, all `E3_*` in the E3 TRADE MANAGEMENT,
  E3 EXHAUSTION DETECTION, E3 REGIME GATE, E3 M1 ROTATION TRIGGER, E3 RR BY EXHAUSTION SCORE, and E3
  LADDERED TP EXTENSIONS groups; ENABLE_FAST_ADX_PANIC_EXIT_E3, ENABLE_SCORE_DROP_EXIT_E3,
  SCORE_DROP_THRESHOLD_E3, ENABLE_DI_FLIP_FAST_EXIT_E3, PANIC_MIN_SL_USED_RATIO_E3,
  CONS_*_E3, LIMIT_*_E3.
- **E5 (SuperBros EMA alignment):** ENABLE_E5_ENTRIES, MAX_LOSS_RATIO_E5, VOL_LOT_ADJ_E5,
  E5_USE_RECOVERY_LADDER, MIN_TREND_QUALITY_E5, all `E5_*` in E5 TRADE MANAGEMENT group,
  ENABLE_FAST_ADX_PANIC_EXIT_E5, ENABLE_SCORE_DROP_EXIT_E5, SCORE_DROP_THRESHOLD_E5,
  ENABLE_DI_FLIP_FAST_EXIT_E5, CONS_*_E5, LIMIT_*_E5.
- **News avoidance:** ENABLE_NEWS_FILTER, AVOID_HIGH_IMPACT_NEWS, AVOID_MEDIUM_IMPACT_NEWS,
  NEWS_MINUTES_BEFORE, NEWS_MINUTES_AFTER, AVOID_NEWS_TRADING, ENABLE_NEWS_COUNTDOWN_IN_TELEGRAM.
- **Adaptive learning:** ENABLE_ADAPTIVE_E1/E2/E3/E4/E5 and ALL `ADAPTIVE_*` internal params
  (lines 617–679) — note these are plain globals, not inputs.
- **Limit order execution:** ENABLE_LIMIT_ORDERS, LIMIT_USE_E1..E5, LIMIT_ATR_OFFSET_E1..E5,
  LIMIT_MAX_OFFSET_SL_RATIO, LIMIT_EXPIRY_BARS_E1..E5, LIMIT_FALLBACK_TO_MARKET, LIMIT_MAX_PENDING.
- **Conservative trade management:** ENABLE_CONSERVATIVE_TRADE_MGMT and all `CONS_*` params (E1..E5).
- **Notifications / Telegram / Discord:** NotificationMode, MADE_FOR_PROP_TRADING,
  ENABLE_HEALTH_CHECK_MESSAGES, HEALTH_CHECK_INTERVAL_MINUTES, ENABLE_EMA_TOUCH_ALERTS,
  SEND_LOW_CONFIDENCE_SIGNALS, TELEGRAM_*, DISCORD_*, DISCORD_USE_EMBEDS, ENABLED_SIGNAL_THREADING,
  PNL_UPDATE_COOLDOWN_MINUTES, ENABLE_EMAIL_ALERTS, EMAIL_SUBJECT_PREFIX, ENABLE_CSV_EXPORT,
  ENABLE_NEWS_COUNTDOWN_IN_TELEGRAM, MARGIN_LEVEL_PERCENT, ALLOWED_ACCOUNT_ID, showDebug (logging only).

---

## 3. TIMEFRAME and EMA config — VERBATIM

From `InputParams.mqh` lines 681–693:

```mql5
input group "===== TIMEFRAME CONFIGURATION ====="
input ENUM_TIMEFRAMES INPUT_TF0 = PERIOD_M1;    // TF0: Primary entry timeframe
input ENUM_TIMEFRAMES INPUT_TF1 = PERIOD_M3;    // TF1: Confirmation timeframe
input ENUM_TIMEFRAMES INPUT_TF2 = PERIOD_M5;    // TF2: Context timeframe
input ENUM_TIMEFRAMES INPUT_TF3 = PERIOD_M15;   // TF3: Regime timeframe
input ENUM_TIMEFRAMES INPUT_TF4 = PERIOD_H1;    // TF4: Anchor timeframe (reserved)

input group "===== EMA PERIOD CONFIGURATION ====="
input int INPUT_EMA0_PERIOD = 10;    // EMA0: Fast EMA period
input int INPUT_EMA1_PERIOD = 25;    // EMA1: Signal EMA period
input int INPUT_EMA2_PERIOD = 71;    // EMA2: Pullback EMA period
input int INPUT_EMA3_PERIOD = 97;   // EMA3: Bounce EMA period
input int INPUT_EMA4_PERIOD = 192;   // EMA4: Anchor EMA period
```

> **THE LIVE EMA PERIODS ARE 10 / 25 / 71 / 97 / 192 — NOT 10/25/75/100/200.** The index labels
> (EMA0=fast, EMA1=signal, EMA2=pullback, EMA3=bounce, EMA4=anchor) and the index *enum* in
> `GlobalState.mqh` (`enum EMA_PERIODS {EMA_10=0, EMA_25=1, EMA_75=2, EMA_100=3, EMA_200=4}`) are
> NAMED after the round numbers, which is a trap: the enum names are just labels — actual periods come
> from the inputs above. Likewise `#define EMA2 2 // Pullback (default 75)` comments are stale.

For port: TF index map (`GlobalState.mqh` lines 177–190):
`TF0=M1, TF1=M3, TF2=M5, TF3=M15, TF4=H1 (reserved)`; `NUM_TF 4`, `NUM_EMA 5`.

---

## 4. RuntimeConfig.mqh — input → runtime transformation (quoted)

The `RuntimeConfig` struct instance is the global `CFG`. It is populated by `InitializeConfig()`,
which is called once in `OnInit` (`KenKemExpert-1.8.154-dev.mq5:92`, after balance auto-detect).

```mql5
void InitializeConfig() {
    // Start with M1 configuration (S30 support added later in Phase 4)
    CFG.useS30 = false;
    CFG.emaFast = 25;
    CFG.emaMid = 75;
    CFG.emaSlow = 100;
    CFG.emaLong = 200;
    CFG.rsiPeriod = 14;
    CFG.adxPeriod = 14;
    ...
}
```

### 4a. EMA fields in CFG are DEAD CODE (critical)
`CFG.emaFast=25, emaMid=75, emaSlow=100, emaLong=200` are hardcoded here and **never read for EMA
computation.** A grep for `CFG.emaFast / emaMid / emaSlow / emaLong` outside RuntimeConfig.mqh returns
ZERO hits. The actual EMA handles are built in `OnInit` from `EMA_PERIOD_ARRAY`, which is filled from
the inputs:

```mql5
// KenKemExpert-1.8.154-dev.mq5 (OnInit), same in 1.8.14/.15/.151/.153
EMA_PERIOD_ARRAY[EMA0] = INPUT_EMA0_PERIOD;   // 10
EMA_PERIOD_ARRAY[EMA1] = INPUT_EMA1_PERIOD;   // 25
EMA_PERIOD_ARRAY[EMA2] = INPUT_EMA2_PERIOD;   // 71
EMA_PERIOD_ARRAY[EMA3] = INPUT_EMA3_PERIOD;   // 97
EMA_PERIOD_ARRAY[EMA4] = INPUT_EMA4_PERIOD;   // 192
...
emaHandles[tf][ema] = iMA(_Symbol, TF_ARRAY[tf], EMA_PERIOD_ARRAY[ema], 0, MODE_EMA, PRICE_CLOSE);
```

`GetEMA(tfIdx, emaIdx, shift)` just indexes `emaBuffers[...]` which are CopyBuffer'd from those
handles. So the EMAs the strategy actually uses are **10/25/71/97/192** (per the inputs), and
`CFG.ema*` (25/75/100/200) must be IGNORED in the port. (The `// 1.6` style comments in
`InitializeConfig` are also stale — e.g. `CFG.rrLongE1 = E1_RR; // 1.6` but `E1_RR` input is 1.9.)

### 4b. Confirmation timeframe (USED)
```mql5
if (CFG.useS30) {
    CFG.confirmationTF = TF_ARRAY[TF1];   // S30 → M3 (6x ratio)
    CFG.confirmationTFIndex = TF1;
} else {
    CFG.confirmationTF = TF_ARRAY[TF2];   // M1 → M5 (5x ratio)
    CFG.confirmationTFIndex = TF2;
}
```
`useS30` is hardcoded false, so at runtime **confirmationTF = M5, confirmationTFIndex = TF2 (=2)**.
`CFG.confirmationTFIndex` IS read in `Entries/EntryHelpers.mqh` for conviction EMA lookups
(`emaBuffers[GetEMABufferIndex(CFG.confirmationTFIndex, EMA2/EMA3)]`).

### 4c. Asymmetric RR (USED — long vs short per entry)
```mql5
CFG.rrLongE1 = E1_RR;            // 1.9 (input), comment "1.6" is stale
CFG.rrShortE1 = E1_RR * 0.875;  // 1.9*0.875 = 1.6625

CFG.rrLongE2 = E2_RR;            // 1.575 (input)
CFG.rrShortE2 = E2_RR * 0.867;  // 1.575*0.867 = 1.365525

CFG.rrLongE3 = E3_RR;            // OUT OF SCOPE
CFG.rrShortE3 = E3_RR * 0.778;  // OUT OF SCOPE

CFG.rrLongE4 = E4_RR;            // 2.4 (input)
CFG.rrShortE4 = E4_RR_SHORT * 0.875;  // NOTE: uses E4_RR_SHORT (1.8), NOT E4_RR → 1.8*0.875 = 1.575

CFG.rrLongE5 = E5_RR;           // OUT OF SCOPE
CFG.rrShortE5 = E5_RR;          // OUT OF SCOPE
```
**Port-critical asymmetry quirks:**
- E1 short = `E1_RR * 0.875`, E2 short = `E2_RR * 0.867`. Long legs use the raw input RR.
- **E4 is special:** `rrLongE4 = E4_RR (2.4)` but `rrShortE4 = E4_RR_SHORT (1.8) * 0.875 = 1.575` —
  the short leg multiplies a *different* input (E4_RR_SHORT), not E4_RR.
- These `CFG.rrLong*/rrShort*` are the values actually used to compute TP in Entry1/2/4.mqh:
  `result.takeProfit = currentPrice ± (slDistance * CFG.rrLongEx / rrShortEx)`. The sideway variant
  (`E1_RR_SIDEWAY` etc.) is applied separately via `IsInSidewayRange()` (see Entry4.mqh:144/195).

### 4d. Session type (USED, but trivially constant at init)
```mql5
CFG.sessionType = 1;  // Default London (most active)
```
Initialized to 1; recomputed at runtime elsewhere (session detection logic not in this struct's init).

---

## 5. Inputs whose RUNTIME value differs from declared default

| Symbol | Declared default | Runtime value | Where / mechanism |
|---|---|---|---|
| **CFG.emaFast/Mid/Slow/Long** | 25/75/100/200 (in RuntimeConfig) | **unused** — effective EMAs are 10/25/71/97/192 | Dead struct fields; live EMAs from `EMA_PERIOD_ARRAY` ← INPUT_EMA*_PERIOD, OnInit lines 255-259 |
| **INITIAL_ACCOUNT_BALANCE** | 3500.0 | broker account balance (if >0) | `OnInit`: `detectedBalance=AccountInfoDouble(ACCOUNT_BALANCE); if(detectedBalance>0) INITIAL_ACCOUNT_BALANCE=detectedBalance;` (1.8.154:84-87). Backtester must seed this to the tester deposit. |
| **LEVERAGE** | 500 | auto-detected leverage if available | `OnInit` (around line 81): `Print("[INIT] Leverage:", LEVERAGE, (detectedLeverage>0 ? "(auto-detected)" : "(fallback)"))` |
| **PIP_SIZE / pipSize** | 0.01 (PIP_SIZE fallback) | per-symbol: GOLD→`10^-digits`; forex 3/5-digit→0.0001, 2-digit→0.01, 1-digit→0.1; **BTCUSD→1**; **ETHUSD→0.1** | `OnInit` symbol-detect block 118-163. NB: code uses a separate runtime `pipSize` var, not the `PIP_SIZE` input directly. |
| **CONTRACT_SIZE / contractSize** | 100 (CONTRACT_SIZE fallback) | `SymbolInfoDouble(SYMBOL_TRADE_CONTRACT_SIZE)` if >0; BTCUSD→1, ETHUSD→1 | `OnInit` 119/126/140/154/160 |
| **minimumLotSize** | 0.01 | `SymbolInfoDouble(SYMBOL_VOLUME_MIN)` (fallback 0.01); BTCUSD→0.01, ETHUSD→0.1 | `OnInit` 127/142/156/162 |
| **MY_STANDARD_LOT_SIZE** (via runtime `myStandardLotSize`) | 0.15 | **×2 for BTCUSD, ×10 for ETHUSD** | `OnInit` 155/161: `myStandardLotSize = myStandardLotSize * 2;` (BTC) / `* 10` (ETH) |
| **CFG.confirmationTF** | (M3 branch in code) | **M5 / index TF2** | `useS30=false` branch in `InitializeConfig` |
| **CFG.rrShortE1/E2/E4** | — (derived) | E1: E1_RR*0.875; E2: E2_RR*0.867; **E4: E4_RR_SHORT*0.875** | `InitializeConfig` 57/60/66 |

**Per-symbol branching summary (critical for BTC vs XAU parity):**
- `XAUUSD`/`GOLD`: pipSize = `10^-digits` (i.e. broker `_Point`, NOT the 10× forex convention),
  contractSize from broker, minLot from broker.
- `BTCUSD`: pipSize=1, contractSize=1, minLot=0.01, **standardLot ×2**.
- `ETHUSD`: pipSize=0.1, contractSize=1, minLot=0.1, **standardLot ×10**.
- Other/forex: digit-based pip detection only when `AUTO_DETECT_SYMBOL_PARAMS` (default true).

A C++ port must replicate these per-symbol overrides exactly, seed INITIAL_ACCOUNT_BALANCE from the
tester deposit, and use the INPUT_EMA periods (10/25/71/97/192) — never the CFG 25/75/100/200 set.
