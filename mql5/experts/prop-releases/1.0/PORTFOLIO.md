# Prop Release Bundle — v1.0

Self-contained folder for the VPS: two EA binaries + ALL THREE deployment
profiles. Copy the whole folder over, then deploy **case by case** —

- **Mode A — Personal:** one strategy alone on a personal account (as-swept lock).
- **Mode B — Individual prop accounts:** one strategy per its own prop account.
- **Mode C — Mixed portfolio:** all three legs on ONE shared FN-Stella2 account.

Same `.ex5` for every mode; only the `.set` differs.

Components: MasterVP `1.08` · KenKem `1.04` · portfolio `1.0`.

## Mode A — Personal (one strategy alone, as-swept lock)
| strategy | symbol · TF | .set |
|----------|-------------|------|
| MasterVP XAU | XAUUSD · M5 | `KK-MasterVP-1.08-xauusd-m5.set` |
| MasterVP BTC | BTCUSD · M5 | `KK-MasterVP-1.08-btcusd-m5.set` |
| KenKem XAU   | XAUUSD · M1 | `KK-KenKem-1.04-xauusd-m1.set` |

No prop DD caps and no contract-baseline anchor (runs the locked params as swept).
Use these for personal/non-funded accounts where firm drawdown rules don't apply.

## Mode A-Tiered — Personal, risk-tiered (tamed drawdown, standalone)
Same locked edge as Mode A, but with lower per-trade risk + tighter daily DD + an
ACTIVE soft-block (de-risk to half-lots before any hard cap) — for personal accounts
that find the as-swept 1% RPT / 10% daily / soft-block-off profile too aggressive.
Still standalone: **no** contract-baseline anchor, **no** shared HWM.

| strategy | symbol · TF | Conservative .set | Balanced .set |
|----------|-------------|-------------------|---------------|
| MasterVP XAU | XAUUSD · M5 | `KK-MasterVP-1.08-xauusd-m5-conservative.set` | `KK-MasterVP-1.08-xauusd-m5-balanced.set` |
| MasterVP BTC | BTCUSD · M5 | `KK-MasterVP-1.08-btcusd-m5-conservative.set` | `KK-MasterVP-1.08-btcusd-m5-balanced.set` |
| KenKem XAU   | XAUUSD · M1 | `KK-KenKem-1.04-xauusd-m1-conservative.set`   | `KK-KenKem-1.04-xauusd-m1-balanced.set`   |

DD tiers (MasterVP is true %-risk; KenKem keeps its fixed base lot and tiers DD caps only):

| tier | MasterVP RPT | daily DD | soft-block → lot | hard halt | KenKem daily / slowdown / soft-block |
|------|-------------|----------|------------------|-----------|--------------------------------------|
| Conservative | 0.5%  | 4% | 5% → 0.5x | 8%  | 4% / 5% / 8% → 0.5x (no hard halt; soft-block de-risks) |
| Balanced     | 0.75% | 5% | 6% → 0.5x | 10% | 5% / 6% / 10% → 0.5x (no hard halt; soft-block de-risks) |

Compounding trade-off vs the ~11X as-swept XAU run (geometric, edge fixed): Conservative
≈ ~3.3X, Balanced ≈ ~6X — roughly half / three-quarters the drawdown. Test before trusting.

## Mode B — Individual prop accounts (one strategy each)
| strategy | symbol · TF | .set | DD caps (daily / soft / hard) |
|----------|-------------|------|-------------------------------|
| MasterVP XAU | XAUUSD · M5 | `KK-MasterVP-1.08-xauusd-m5-prop.set` | 4.4% / 8.0%→0.5x / 9.5% |
| MasterVP BTC | BTCUSD · M5 | `KK-MasterVP-1.08-btcusd-m5-prop.set` | 4.4% / 8.0%→0.5x / 9.5% |
| KenKem XAU   | XAUUSD · M1 | `KK-KenKem-1.04-xauusd-m1-prop.set`   | 4.4% / slowdown 7% / soft-block 9% |

Run each on its OWN account (don't share the equity HWM across unrelated accounts).
Note: KenKem prop keeps `MADE_FOR_PROP_TRADING=false` (soft-block = micro-lots, no
hard halt) — its 9% soft-block is the de-risk floor, not a kill switch.

## Mode C — Mixed (all legs on one shared account)
| leg | symbol · TF | .set | risk/trade |
|-----|-------------|------|-----------|
| MasterVP XAU | XAUUSD · M5 | `KK-MasterVP-1.08-xauusd-m5-mixed-fn.set` | 0.43% |
| MasterVP BTC | BTCUSD · M5 | `KK-MasterVP-1.08-btcusd-m5-mixed-fn.set` | 0.15% |
| KenKem XAU   | XAUUSD · M1 | `KK-KenKem-1.04-xauusd-m1-mixed-fn.set` | 0.10% |

**Joint DD caps (all legs share ONE equity HWM):** daily 4.2% · soft-derisk 7.8% ·
hard-halt 9.2%. Attach all three on the SAME account so the shared-file HWM is joint.

## Overall-DD anchor (no manual seeding needed — prop + mixed)
Every prop + mixed set bakes the contract-baseline anchor (`InpPropBaselineEquity` /
`PROP_BASELINE_EQUITY` = **100000**). On a fresh attach the overall-DD high-water
mark is seeded at the contract size, so a drawn-down account reads its TRUE drawdown
(not 0%). **Change this to your contract size for a $50K/$200K account.** The HWM
trails UP from the baseline as new equity peaks print, and persists to the shared
file `Common/Files/KK_PropState_<login>.txt` (RESET = delete that file).

## Deploy
1. Copy both `.ex5` into `MQL5/Experts/` (or the symlinked `Experts/dquants/` path).
2. Pick a mode and attach the chart(s); load the matching `.set` (Inputs -> Load).
3. KenKem only: clear any stale `KKG.*` global variables before attach.
4. Set the baseline input to your account's contract size if not $100K.
5. Confirm in the log: MasterVP prints `prop baseline floor applied: peakEquity=...`.

> Bundle assembled by `scripts/make_prop_portfolio.sh 1.0`. Bump the portfolio
> version whenever a component EA is re-released.
