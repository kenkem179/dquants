# KK-KenKem — Expert Advisor User Guide (internal / full edition)

A practical, plain-language guide to running the **KK-KenKem** Expert Advisor on MetaTrader 5. This is the **internal / full** guide: it documents **every** input group, including the technical internals that are *hidden* in the marketplace edition. Use it for our own personal and prop-account deployments, and as the reference when tuning.

Built and validated on **XAUUSD (Gold)** on the **M1** timeframe, with M3 / M5 / M15 / H1 used internally for confirmation. The current locked configuration is **D5-E4Long** (engines E1 + E2 + E4-long): in MT5 testing it produced **+1,427 / PF 1.428 / 126 trades** and passes the overfitting gate.

**Important — please read first.** This document is educational and informational only. It is not financial advice, not an investment recommendation, and not a solicitation to buy or sell anything. KK-KenKem is an automated trading program: when enabled, it can open, modify, and close real positions on your account according to its rules. Every default value was chosen from historical backtests and walk-forward checks. **A backtest is a study of the past. It does not predict, promise, or guarantee future results.** Markets change, brokers differ, and live conditions (spread, slippage, latency, gaps) are never identical to a test. Trading leveraged products carries a high risk of loss, including the loss of your entire capital. You alone are responsible for your decisions and their consequences. Test on demo first.

---

## 1. What KK-KenKem is (in one minute)

KK-KenKem is a **multi-engine, trend-following scalping EA** for Gold on M1. Instead of one signal, it runs several independent entry "engines," each looking for a different shape of opportunity, all sharing one risk manager and one trade manager:

- **E1 — Trend discovery / continuation.** The core engine. Detects a fresh, healthy trend (EMA structure + ADX/DI strength + trend-quality score) and rides it, letting winners run.
- **E2 — Pullback continuation.** Waits for price to pull back to a key EMA inside an established trend, then joins in the trend direction.
- **E3 — Trend reversal (counter-trend).** Looks for exhaustion at extremes and fades it. **Off by default** — counter-trend is the riskiest engine.
- **E4 — Smart early trend (Ichimoku cloud cross).** Enters a trend early on a cloud cross with strict quality filters. **On (long-only)** in the locked config.
- **E5 — EMA-alignment ("SuperBros").** A simple, clean multi-EMA alignment entry. **Off by default.**

Around those engines sit a **regime filter** (multi-timeframe EMA trend, ADX, sideways detection, ATR-percentile volatility band), a **risk manager** (daily-loss cap, account-drawdown slowdown and soft-block, recovery mode, win-streak and loss-streak cooldowns, black-swan protection), and a **trade manager** (structure stop with ATR arbitration, partial take-profit, break-even, trailing, laddered TP extensions, and several fast-exit safety valves).

**What it is not:** not a guaranteed income system, not "set and forget," not a martingale or grid. It is a rule-based tool that does exactly what its settings say.

## 2. Strategy building blocks

- **Timeframes.** Attach to **M1**. The EA reads M3, M5, M15 and H1 internally for confirmation and higher-timeframe trend agreement.
- **EMAs.** Five EMAs — 10 / 25 / 71 / 97 / 192 — define the fast signal, the pullback shelves, and the slow trend anchor.
- **Momentum.** ADX and DI spread measure trend strength and direction; RSI provides momentum and divergence context.
- **Conviction & trend-quality scoring.** Before an engine fires, the setup is scored (conviction 0-12, trend quality 0-11). Weak setups are filtered out.
- **Sessions.** Tokyo / London / New York windows (defined in UTC) gate when the EA is allowed to trade.

## 3. Installing and attaching

1. Copy `KK-KenKem.ex5` into your MetaTrader 5 `MQL5/Experts/` folder (or a subfolder).
2. Restart MetaTrader 5, or right-click Navigator → Expert Advisors → **Refresh**.
3. Open an **XAUUSD M1** chart.
4. Drag **KK-KenKem** onto the chart.
5. In the settings window, **Common** tab, tick **Allow Algo Trading**. In **Inputs**, leave the defaults or click **Load** and pick a shipped `.set` preset (see §4).
6. Enable the global **Algo Trading** button in the toolbar. A smiling face on the chart means it is live.

To test, use **View → Strategy Tester** with **Every tick based on real ticks** for the most realistic modelling. **Backtest results are historical and do not guarantee future performance.**

## 4. The shipped presets

- **`KK-KenKem-XAUUSD-M1-D5-E4Long.set`** — the locked, validated configuration (E1 + E2 + E4-long). This is the source of the defaults.
- The release also packages **personal** and **prop** variants. The prop variant tightens the risk limiters to common funded-account rules: **max daily loss 4.4%**, slowdown easing in at **7%**, and a **9%** account-drawdown soft-block ceiling.

Load one from the Inputs tab → **Load**, re-read the disclaimer, and demo-test before trusting it.

## 5. Settings, in plain language (full edition)

The inputs are grouped as they appear in the dialog. You do **not** need to change most of them — the defaults are the tested configuration. Conventions:

- **RR** ("reward-to-risk") means the target distance as a multiple of the stop distance. RR 1.9 = a target 1.9x the stop away.
- **ATR** measures typical price movement; many distances are expressed as ATR multiples so the EA adapts to quiet or busy markets.
- **Ratio** inputs are fractions of balance: 0.072 = 7.2%, 0.02 = 2%.

### General account & symbol setup
- **MY_STANDARD_LOT_SIZE** — the baseline lot the sizing logic scales from.
- **MAX_HIGH_RISK_TRADES_PER_SESSION / MAX_SLTP_COUNT_PER_SESSION / MAX_SESSION_LOSSES** — caps on how many high-risk entries, total SL/TP placements, and real losses are allowed per session before new entries are blocked.
- Symbol pip/contract size are auto-detected from the broker.

### Quick strategy customization (the main knobs)
- **MAX_DAILY_LOSS_RATIO** — pause trading once the day's loss reaches this fraction of balance.
- **ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN** — begin reducing risk when overall drawdown reaches this level.
- **ACCOUNT_DD_RATIO_TO_SOFT_BLOCK** — at this drawdown, "soft block": keep running but on micro lots (`SOFT_BLOCK_LOT_MULTIPLIER`).
- **ENABLE_E1..E5_ENTRIES** — master on/off per engine. Locked config: E1 on, E2 on, E3 off, E4 on, E5 off.
- **COMMON_MAX_RISK_PER_TRADE** — base risk per trade as a fraction of balance; each engine applies a small multiplier around it.
- **VOL_LOT_ADJ_E1..E5 / INCREASE_LOT_SIZE_BASED_ON_PROFIT** — optional volatility- and profit-based lot scaling.

### General risk management
- **RECOVERY_MODE_* / RECOVERY_LADDER_*** — after a drawdown, optionally trade smaller and step size back up gradually as the account recovers.
- **SIGNAL_ONLY_DURING_PROTECTION** — in protective modes, compute signals but don't place trades.
- **VOL_LOT_MIN/MAX_MULT** — bounds on volatility-based lot adjustment.

### Peak-balance decay (recovery escape)
- **ENABLE_PEAK_BALANCE_DECAY** and the `PEAK_DECAY_*` values gradually ease the high-water mark during a long recovery so the EA isn't frozen forever after a peak.

### Conviction scoring (0-12)
- **CONVICTION_THRESHOLD_E1/E2/E4** — minimum conviction score required to enter. Higher = stricter, fewer but cleaner trades.
- **USE_HTF_VETO_E1/E2/E4** — block entries that fight the higher-timeframe trend.

### Trend-quality scoring (0-11)
- **ENABLE_TREND_QUALITY_GATES** — require minimum ADX / DI / multi-timeframe agreement before scoring.
- **MIN_TREND_QUALITY_E1/E2/E4/E5** — minimum trend-quality score per engine.
- **USE_ICHIMOKU_E1/E2** and **ICHIMOKU_TENKAN/KIJUN/SENKOU** — optional Ichimoku alignment bonus and its periods.

### Sideways / volatility entry blocking
- **MAX_SPREAD_PIPS / MAX_SPREAD_ATR_RATIO / SPREAD_BLOCK_CONSECUTIVE_BARS** — block entries when the spread is too wide (absolute or relative to ATR).
- **ATR_SIDEWAYS_PERCENTILE / SIDEWAYS_BLOCK_THRESHOLD / SIDEWAYS_WARNING_THRESHOLD** — detect and avoid flat, choppy markets.
- **MIN_ENTRY_ATR_PERCENTILE / ATR_PERCENTILE_HIGH / ENABLE_ATR_HIGH_BLOCK** — only trade inside a sensible volatility band (the locked value requires ATR above the 70th percentile).
- **ENABLE_BLACK_SWAN_PROTECTION / BLACKSWAN_BLOCK_COOLDOWN_MINS** — stand aside after a volatility spike.

### Profit protection & streak cooldowns
- **ENABLE_PROFIT_PROTECTION + PROFIT_PROTECTION_*** — once the day is meaningfully green, reduce size to protect gains.
- **ENABLE_WIN_STREAK_COOLDOWN + WIN_STREAK_*** — ease off after a hot streak (mean-reversion of luck).
- **MAX_CONSECUTIVE_LOSSES_PER_ENTRY_TYPE / ENTRY_BLOCK_AFTER_CONSECUTIVE_LOSS_MINS** — cool down an engine after repeated losses.
- **MAX_CONCURRENT_POSITIONS_ALLOWED / BLOCK_OPPOSITE_DIRECTION_ENTRIES** — cap open positions and prevent hedging against yourself.
- **CLOSE_ALL_TRADES_AT_SESSION_END** — flatten everything when the session closes.

### Stop-loss configuration
- **SL_EMA_DISTANCE / MIN_SL_SPREAD_MULT** — structure-based stop placement.
- **E1/E2/E4/E5_USE_ATR_SL_ARBITRATION + *_ATR_SL_CAP/FLOOR_MULTIPLIER** — clamp the structure stop within ATR bounds (a smart hybrid: never absurdly tight or absurdly wide). E3 uses a pure ATR stop.
- **ATR_PERIOD_FOR_SL / ATR_LOOKBACK_FOR_ADAPTIVE** — ATR settings for stops.
- **HIGH_RISK_MAX_BARS / MIN_SECONDS_BETWEEN_ENTRIES / RANGE_HI_LOW_LOOK_BACK_BARS** — holding-time cap, entry throttle, and range window.

### Momentum, RSI divergence & extreme-momentum bypass
- **MIN_MOMENTUM_ADX_REQUIRED / ADX_LOW/HIGH_THRESHOLD / REQUIRE_ADX_CONFLUENCE** — momentum confirmation.
- **ENABLE_RSI_DIVERGENCE_VETO + RSI_DIV_*** — block entries when RSI diverges against the trade.
- **EXTREME_DI_SPREAD_THRESHOLD / EXTREME_RSI_THRESHOLD_*** — allow strong-momentum entries to bypass some filters.

### Dynamic TP/SL & fast exits
- **ENABLE_PRE_BE_STRUCTURE_PROTECTION + PRE_BE_*** — tighten the stop on a structure break before break-even is reached.
- **R_MULT_BE_TRIGGER / R_MULT_BE_BUFFER** — when and where to move to break-even.
- **ALLOW_PARTIAL_TP / ALLOW_TP_EXTENSION / USE_DYNAMIC_TP_EXTENSION / USE_DYNAMIC_RR_SCALING** — partial-profit and target-extension behaviour. (The locked config sets `USE_DYNAMIC_RR_SCALING=false`.)
- **ENABLE_FAST_ADX_PANIC_EXIT_E1..E5 / ENABLE_SCORE_DROP_EXIT_* / ENABLE_DI_FLIP_FAST_EXIT_*** — fast exits when the trend's energy collapses (ADX falls, score drops, DI flips).

### Per-engine trade management (E1 / E2 / E3 / E4 / E5)
Each engine has its own block of:
- **Ex_RR / Ex_RR_SIDEWAY** — reward-to-risk in trending vs sideways conditions.
- **Ex_PARTIAL_TP_TRIGGER / Ex_PARTIAL_TP_RATIO** — when to bank a partial and how much.
- **Ex_SL_TO_BREAKEVEN_BUFFER / Ex_TRAILING_SL_FACTOR / Ex_MAX_TP_EXTENSIONS / Ex_EARLY_CUT_SL_RATIO** — break-even, trailing tightness, how far targets can extend, and where to cut a loser early.
- **Ex_ENABLE_LADDERED_EXTENSIONS + Ex_LADDER_STAGE*_*** — staged "let it run" trailing after the partial.
- HTF filters (**Ex_HTF_TREND_FILTER / Ex_HTF_MIN_ADX / Ex_HTF_MIN_DI_SPREAD**) and high-risk momentum strictness per engine.
- **E4_LONG_ONLY** — the locked config trades E4 long-only (E4 shorts were net-negative in MT5 isolation; longs ran PF ~1.40).

### Other engine-specific groups
- **E3 exhaustion / regime gate / M1 rotation / RR-by-score** — the counter-trend engine's detailed filters (only relevant when E3 is enabled).
- **Ichimoku cloud early exit** and **conservative trade-management mode** — optional alternative exit styles.
- **Limit-order execution (ENABLE_LIMIT_ORDERS + LIMIT_*)** — optionally enter with limit orders instead of market orders.

### Sessions & news
- **JAPAN/LONDON/NY_START/END** (UTC) and **IGNORE_VALID_SESSIONS** — the trading windows.
- **ENABLE_NEWS_FILTER / AVOID_HIGH_IMPACT_NEWS / AVOID_MEDIUM_IMPACT_NEWS / NEWS_MINUTES_BEFORE / NEWS_MINUTES_AFTER** — pause around economic releases.

### Notifications, telegram, discord, adaptive learning
- Alerting (Telegram / Discord / email), health checks, and the optional **adaptive-learning** layer (off by default) live here. These are operational, not strategy, settings.
- **MADE_FOR_PROP_TRADING** — simplified alerts plus a hard block near maximum balance drawdown, for funded accounts.
- **ALLOWED_ACCOUNT_ID** — internal account lock (empty = any account).

### Timeframe & EMA configuration
- **INPUT_TF0..TF4** and **INPUT_EMA0..EMA4_PERIOD** define the timeframe ladder (M1/M3/M5/M15/H1) and the EMA periods (10/25/71/97/192). These are the strategy's core skeleton — change only with full re-validation.

## 6. A calm way to run it

1. Attach to **XAUUSD M1**, load the personal (or prop) preset, enable Algo Trading.
2. Set **COMMON_MAX_RISK_PER_TRADE** to a level you are comfortable losing on a single trade.
3. Leave the engines at the locked selection (E1 + E2 + E4-long) unless you have your own testing.
4. Let the daily-loss, drawdown and profit-protection limiters do their job — don't disable them to "trade more."
5. Demo first, then start small. Re-check behaviour after broker or spread changes.

## 7. Troubleshooting & FAQ

- **It isn't trading.** Check Algo Trading is on, the chart is M1 XAUUSD, you're inside a session window, the spread is under `MAX_SPREAD_PIPS`, and you're not in a protective (drawdown / cooldown / news) mode.
- **Very few trades.** That's by design — the conviction, trend-quality and volatility filters reject weak setups. Loosening them increases trade count but lowers average quality.
- **Lots look small.** Risk-based sizing shrinks lots when the stop is wide or the account is in a protective mode.
- **Different results than the backtest.** Expected — spread, slippage, latency and broker feed differ from any test. Validate on the account you'll actually run.

## 8. Glossary

- **RR** — reward-to-risk; target distance as a multiple of the stop.
- **ATR** — Average True Range; a volatility measure.
- **ADX / DI** — trend-strength and directional indicators.
- **Conviction / trend-quality score** — internal 0-12 / 0-11 setup-quality ratings.
- **Soft block** — continue trading on micro lots after a drawdown threshold.
- **HTF** — higher timeframe.

## 9. Full disclaimer

This Expert Advisor is provided for trading-automation and educational purposes. It is **not financial, investment, legal, or tax advice**, and **no profit or outcome is promised or guaranteed**. All settings are derived from historical data; past and tested performance does not indicate future results. Automated trading of leveraged products such as Gold carries a high risk of loss — you may lose some, all, or more than your deposited capital. You are solely responsible for configuring, testing, supervising and using this product, and for all decisions and their consequences. Test on a demo account before trading live, and consider consulting an independent, appropriately licensed professional.
