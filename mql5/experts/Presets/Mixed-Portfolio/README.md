# Mixed Portfolio — MasterVP M5 + KenKem M1 on XAUUSD (FundedNext Stellar-2 $100K)

Two validated, **near-uncorrelated** XAUUSD edges run on ONE $100K account:

| EA | chart | strategy | role |
|---|---|---|---|
| **KK-MasterVP** | XAUUSD **M5** | volume-profile breakout (+reversion) | primary $ engine |
| **KK-KenKem** | XAUUSD **M1** | Ichimoku/EMA entries (E1+E2+E4-long) | gentle diversifier |

Despite both being XAUUSD, their daily-return correlation is **≈0.08** — they fire on different
signals, so combining them lowers drawdown for the same return (a genuine free lunch). See
`research/portfolio/MASTERVP_3BOOK_FINDINGS_2026-06-23.md`.

## Files
- `KK-MasterVP-XAUUSD-M5-FN-Stellar2-100k.set` — attach to a **XAUUSD M5** chart.
- `KK-KenKem-XAUUSD-M1-FN-Stellar2-100k.set` — attach to a **XAUUSD M1** chart.

Both are the **validated locks** (KK-MasterVP-XAUUSD-M5.set / KK-KenKem-XAUUSD-M1-D5-E4Long.set) with
**only the risk/DD keys changed** for the prop book. No strategy/entry/exit params were touched.

## How to run
1. Open **two** XAUUSD charts on the SAME $100K account: one M5, one M1.
2. Attach KK-MasterVP to M5, load the `...MasterVP...FN-Stellar2-100k.set`.
3. Attach KK-KenKem to M1, load the `...KenKem...FN-Stellar2-100k.set`.
4. Both EAs auto-detect the $100K balance and size as a % of it — no manual lot setting.

## Risk design (FundedNext Stellar-2: max daily DD 5% / max account DD 10%)
**Key fact:** both EAs measure drawdown against the **shared account equity** (MasterVP via
`g_peakEquity`/`g_dayStartEquity`; KenKem via `AccountInfoDouble(ACCOUNT_BALANCE)`/`peakAccountBalance`).
So the DD caps act **jointly, not additively** — when the combined account drops X%, each EA
independently sees X% and halts. We therefore set both EAs to the *same* sub-limit below the hard caps.

| control | MasterVP | KenKem | purpose |
|---|---|---|---|
| per-trade risk | `InpRiskAccPct=0.08`% | `COMMON_MAX_RISK_PER_TRADE=0.002` (0.2%) | sized so even the **unhalted** book fits the caps |
| daily halt | `InpMaxDailyDDPct=3.5` | `MAX_DAILY_LOSS_RATIO=0.035` | joint ~3.5% account daily halt (1.5% buffer to 5% hard) |
| account DD | `InpMaxPeakDDPct=8.0` (HARD) + `InpSoftBlockDDPct=5.0`→0.4× | `...SLOWDOWN=0.05` + `...SOFT_BLOCK=0.08` | brake at 5%, stop by 8% (2% buffer to 10% hard) |

## Validated combined book (MT5 streams, 2025-03 → 2026-05, conservative *unhalted* replay)
- worst single day **−2.9%** (vs 5% hard cap) · max account DD **−7.7%** (vs 10% hard cap)
- ≈ **+3.1% / month**, ~127%/yr equivalent at this sizing
- The −2.9% / −7.7% are *without* relying on the halts — the soft-block/hard-halt are extra safety net.

## Caveats
- KenKem is only 126 trades and *barely* cleared the overfitting gate (PSR 0.955) — kept deliberately
  small (0.2% risk). It smooths the curve; it is not the profit driver.
- Both are long-trend-biased XAUUSD: the 0.08 correlation is a benign-regime number. A sharp gold
  shock can hit both at once — the 2–3% buffers under each hard cap exist for exactly that.
- Numbers are from MT5-confirmed backtests on the Exness feed; a FundedNext server will differ in
  spread/fills. Forward-test on the FundedNext demo before the funded phase.
