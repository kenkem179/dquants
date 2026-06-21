# KK-MasterVP XAU M5 — MT5 lock confirmation (2026-06-22)

**Run:** XAUUSD-Exness-KK, M5, real-tick, deposit $10k. Preset `KK-MasterVP-XAUUSD-M5.set`
(TP1=0 lock, `InpEnableReversion=true`, blocked hrs 2,3,14, trail 2.5×ATR).
Window: 2024.12.31 → 2026.05.29 (Exness XAU custom symbol ends ~2026-06-10; tester filled to last bar).
MT5: 122,969,714 ticks, final balance **$94,594** (10k → 94.6k).

## MT5 results (from `trades_mt5_xau_m5.csv`, 1958 trades)
| window | n | win% | PF | net $ (fixed-pnl col) | maxDD$ (ledger) |
|---|---|---|---|---|---|
| FULL 2025-01→2026-05 | 1958 | 53.5% | **1.341** | +84,663 | 11,615 |
| OOS 2026-02→05       | 414  | 56.3% | **1.393** | +44,589 | 10,640 |
| 2025 only            | 1414 | 53.3% | 1.333 | +35,357 | 4,010 |

Exit mix: SL-WIN 1029, SL-LOSS 910, TP 19 (runner-trail dominated, as designed).
By reason: L-BRK +44,398 / S-BRK +39,505 / S-REV +459 / L-REV +301 (reversion ≈ flat-positive, breakout carries it).

## Engine comparison (same .set, `ticks_xau_full.csv`, 90,999,103 ticks)
| window | n | win% | PF |
|---|---|---|---|
| ENG FULL | 1350 | 59.3% | 1.470 |
| ENG OOS 2026-02→ | 426 | 58.2% | 1.448 |

## Verdict — ✅ LOCK CONFIRMED (edge real; MT5 slightly conservative vs engine)
- **OOS trade-count parity: MT5 414 vs engine 426 (97%)** — the window the lock was validated on matches.
- **OOS PF: MT5 1.393 vs engine 1.448** (engine ~4% optimistic) — MT5 confirms the edge, on the honest side.
- **Full-window MT5 is strongly profitable**: PF 1.341, +846% on $10k, 53.5% win over 1958 trades, smooth (2025 ledger DD only $4k).
- ⚠️ Full-window trade count gap (MT5 1958 vs engine 1350) is concentrated in **2025**, driven by the
  XAU tick-source mismatch (MT5 123M ticks vs engine file 91M) — OOS aligns, so it does not affect the lock.
  Engine net $ (+482k) is NOT comparable: it compounds risk on a growing equity differently; use PF/count/win for parity.
- **maxDD%**: read the real value from the MT5 tester .htm report (ledger-$ DD shown here is fixed-notional, not the compounding account %). Engine OOS dd was 8.1%.

**Action:** promote XAU M5 from "⏳ MT5 re-run" to **✅ MT5-CONFIRMED** in the release table.
Still pending: BTC M5 (run not yet provided).
