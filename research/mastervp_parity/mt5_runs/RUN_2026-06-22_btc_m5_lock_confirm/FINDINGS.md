# KK-MasterVP BTC M5 — MT5 run (2026-06-22)

**Run:** BTCUSD-Exness M5, real-tick, deposit $10k. Preset `KK-MasterVP-BTCUSD-M5.set`
(TP1=0 lock, `InpEnableReversion=false`, trail 6.0×ATR, no blocked hours).
Window: 2025.01.02 → 2026.06.09. MT5: 163,608,717 ticks, final balance **$10,504** (≈ breakeven).

## MT5 results (`trades_mt5_btc_m5.csv`, 1024 trades)
| window | n | win% | PF | net $ | maxDD$ |
|---|---|---|---|---|---|
| FULL 2025→2026     | 1024 | 50.6% | **1.013** | +504  | 4,227 |
| OOS 2026→          | 314  | 52.2% | **1.237** | +2,862 | 1,124 |
| 2025 only          | 710  | 49.9% | **0.914** | −2,358 | 4,227 |

By reason: **L-BRK −3,511 / S-BRK +4,015** (longs lost, shorts carried it over the full window).
Exit mix: SL-WIN 501, SL-LOSS 506, TP 17.

## vs engine (re-sweep OOS)
- Engine OOS PF **1.250** / n 380  →  MT5 OOS PF **1.237** / n 314.
- **OOS PF parity is GOOD** (Δ ~1%, MT5 honest/slightly conservative). This is NOT a fictional engine
  win — contrast the BTC *reversion* case which the engine inflated. The trail-runner breakout edge is real on 2026 BTC.
- Count gap (314 vs 380) likely tick-source (MT5 164M vs engine BTC file) — same pattern as XAU.

## Verdict — ⚠️ OOS edge confirmed, but full-window only BREAKEVEN
- The lock's headline (OOS PF ~1.21–1.25) **is real and MT5-confirms** on 2026.
- BUT over the full 2025+2026 window it is **flat (PF 1.013, +$504 on $10k)** because **2025 was a losing
  regime** (PF 0.914, −$2,358). The config is regime-fragile on BTC.
- **Not release-grade as-is.** Treat BTC M5 as marginal. This reinforces H7: BTC needs genuine
  per-symbol/per-TF optimization (VP node length + RR + SL), not XAU-style params. The long/short
  asymmetry (longs −3.5k, shorts +4k) is a concrete lead — a directional or regime filter may rescue it.

**Action:** release table → BTC M5 = "OOS-confirmed but full-window breakeven; NOT release-grade" (was ⏳).
Feeds H7 (BTC re-sweep) as priority.
