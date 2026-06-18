# MT5 GROUND TRUTH — what actually happens in the MetaTrader tester

**This file supersedes the optimistic PF tables in `KENKEM-RESULTS.md`.** Every number here is
reconstructed from the MT5 Strategy Tester's OWN deal stream (the trades MT5 actually executed on real
Exness ticks), with **no dquants engine involved**. The reconstruction is validated by matching
reconstructed final balance against each pass's reported `final balance` line — see
`research/validation/mt5_log_truth.py` (run it on `../kenkem/Tester/Agent-127.0.0.1-3000/logs/*.log`).
Cross-check passes on ~all rows; it even reproduces the MT5 report screenshot's PF 0.85 exactly.

Reconstruction omits commission/swap (~$50 over a multi-thousand-trade run), so net is within ~0.5%.

Generated 2026-06-15 from logs 20260613 / 20260614 / 20260615.

---

## Headline: all three dquants-promoted EAs FAIL the recent OOS window

| dquants-promoted EA | Symbol/TF | Recent OOS window | MT5 result | Verdict |
|---|---|---|---|---|
| **KK-KenKem** (E5-only distilled) | XAU M1 | 2025.08→2026.06 | **−62% to −93%**, PF 0.78–0.87 | **Blowup** |
| **KK-MasterVP** | BTC M3 | 2025.10→2026.05 | **−19.1%**, PF 0.97 | Loses |
| **KK-Monster** | BTC M3 | 2025.10→2026.05 | **0 trades** | Broken port |

The dquants `KENKEM-RESULTS.md` claimed XAU E5 OOS PF **1.62** and similar — those were
**engine-internal, never MT5-confirmed**. MT5 truth is the opposite sign.

---

## KenKem (XAU M1) — the original works; the dquants port broke it

All same symbol, same window (2025.08→2026.06), MT5-true:

| EA | Trades | Net% | PF | Win% | MaxDD% | Sharpe |
|---|--:|--:|--:|--:|--:|--:|
| **`KenKemExpert`** (user's ORIGINAL, full multi-entry) | **143** | **+24.1** | **1.62** | 47 | 9.2 | 1.85 |
| `KenKemExpert-1.8.154-dev` (variant a) | 176 | +19.6 | 1.44 | 47 | 4.0 | 1.47 |
| `KenKemExpert-1.8.154-dev` (variant b) | 283 | +11.2 | 1.17 | 44 | 4.8 | 0.79 |
| `KenKemExpert-1.8.154-dev` (variant c) | 559 | −2.5 | 0.98 | 48 | 12.3 | −0.16 |
| **`KK-KenKem`** (dquants E5-only, PROMOTED) — 3 cfgs | **2,338–5,762** | **−62 to −93** | 0.78–0.87 | 68 | 70–94 | −2 to −4.7 |

**The key fact:** the original selective EA (143 trades, PF 1.62, +24%) is genuinely profitable. The
dquants "distilled E5-only" port trades **15–40× more** and blows up. The distillation/optimization
removed the selectivity that WAS the edge. The over-trading + tiny-partial / full-SL asymmetry (86%
win, avg win $21 vs avg loss $156) bleeds the account out on costs.

---

## KK-MasterVP — period-dependent, net-negative on recent windows

MT5-true across windows (BTC M3 unless noted). PF hovers around 1.0 = no robust edge:

| Window | Trades | Net% | PF | MaxDD% | note |
|---|--:|--:|--:|--:|---|
| 2025.01→2025.08 | 425 | −30.1 | 0.47 | 30 | worst |
| 2025.03→2026.06 | 2,983 | −23.6 | 0.93 | 30 | |
| **2025.10→2026.05** (recent OOS) | 2,757 | **−19.1** | 0.97 | 37 | the promoted window |
| 2026.01→2026.06 (cfg a / b) | 1,082–1,113 | −8.1 / +4.0 | 0.94 / 1.03 | 20–24 | |
| 2025.08→2026.06 | 2,325 | **+36.5** | 1.08 | 27 | best (longest, partly IS) — the cherry-picked one |
| XAU M3 2025.08→2026.06 | 1,902 | −3.3 | 0.99 | 25 | |

MasterVP's C++ tick engine IS trade-level parity-validated (it reproduces these MT5 trades). But
**parity ≠ profitability**: the strategy itself is ~breakeven and loses on most recent windows. The
"+36.5% / PF 1.08" headline was the single most favorable (and partly in-sample) window.

---

## KK-Monster — broken or catastrophic

| Run | Trades | Result |
|---|--:|---|
| dquants `KK-Monster` BTC M3 2025.10→2026.05 (PROMOTED) | **0** | fires nothing — gate filters every bar (suspect: ATR% ceiling `InpMinAtrPct=0.04`/`InpMaxAtrPct=0.2`) |
| Older `…-Monster` BTC M3 2026.03→2026.06 | 568 | −25.2%, PF 0.85 |
| Older `…-Monster` BTC M3 2025.01→2025.11 | 1,555 | **−79.9%**, PF 0.77 |
| Older `…-Monster` BTC M1 2025.01→2025.11 | 3,016 | **−82.4%**, PF 0.85 |

Every dquants Monster sweep number has **no working MT5 counterpart**: the promoted config doesn't
trade, and when Monster does trade it loses catastrophically. Worthless as-is.

---

## Engineering fixes shipped 2026-06-15 (autopilot)

**1. KenKem tick engine (`cpp_core/include/kk/kenkem/tick_engine.hpp`) — VALIDATED against MT5.**
The distilled `kk::kenkem` was a bar-OHLC walk that reported E5-only at PF 1.69 / +$42k for a config
MT5 lost 62% on. The new tick engine replays the real bid/ask stream through the same signal/SL/TP
front-half. Result on the exact ungated E5 config MT5 ran:

| Engine | PF | Net% | verdict |
|---|--:|--:|---|
| bar-OHLC walk (old) | 1.69 | +420 | fantasy |
| **tick engine (new)** | **0.855** | **−74.6** | matches MT5 |
| MT5 truth (2026 window) | 0.85 | −74.1 | — |

Reproduces MT5 PF to within 0.005. Run: `make kenkem_tick && ./build/kenkem/tick_backtester --bars-m1
tools/bars_xauusd_2025h2_2026_m1.csv --ticks tools/ticks_xauusd_window.csv --symbol-xau --from-ms
1754006400000 --set <cfg>`. (Trade count 1074 vs MT5 2338 — the window tick file has 38M ticks vs MT5's
85M, so fewer intrabar re-entries; the economics match.)

**2. Wired the dropped governors** the distilled engine defined but never enforced: universal
`min_entry_atr_pctile` (the original's MIN_ENTRY_ATR_PERCENTILE=65), a per-UTC-day entry cap, and an
E5 trend-core gate. Necessary but NOT sufficient — even gated, the bar engine still lied (PF 1.69);
only the tick engine tells the truth.

**3. Through the validated tick engine, every dquants-tuned KenKem config still loses** (they were
Optuna-overfit to the fantasy bar engine): E5 −74%, E1+E2 −58% (E1 the loser), E1-only −44%, E2-only
PF 1.02 (marginal). The original `KenKemExpert` wins only because of conviction scoring + session caps +
cooldowns the distillation never ported (full spec captured for a future faithful port).

## What this means for the process

The failure is systemic, not three unlucky picks: dquants numbers were **optimized against the
project's own simulators and promoted on favorable windows without MT5 confirmation on the true recent
OOS window.** Action items:
1. **MT5 (or a parity-locked tick engine) is the only gate.** No PF is "real" until confirmed in MT5
   on the recent OOS window.
2. **Re-baseline against the ORIGINAL `KenKemExpert`** (it works on XAU M1) — understand why the
   distillation over-trades, instead of replacing it.
3. **Drop Monster** until the zero-trade port bug is fixed and it's shown to trade at all.
4. **Every perf table cell** must be labeled IS/OOS and engine-vs-MT5. No more unlabeled PF.
