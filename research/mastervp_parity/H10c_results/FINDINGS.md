# H10c — Session-giveback stop (InpGivebackPct) → MT5 VERDICT: REJECT (2026-06-26)

**Verdict: REJECT. Default stays OFF (= the lock, byte-identical). No deployment change.**

MT5 optimizer, KK-MasterVP-Debug, XAUUSD M5, *Every tick based on real ticks*, 2025.06.01–2026.05.29,
deposit 10k, rank by PF. Grid = `InpGivebackPct ∈ {0,10,…,90}`, 10 passes, `0` = OFF control in-run.
Base = current FINAL LOCK incl. ProgTrail late-arm ladder (RR4.0/Trail2.75/BeBuf0.02; ProgTrail 2.0/0.75/0.2).
Parsed from `.opt` cache via `scripts/parse_mt5_opt.py`. Raw: `giveback_sweep.csv` + the `.opt`.

| InpGivebackPct | Net | PF | Trades | EqDD% |
|---:|---:|---:|---:|---:|
| **0 (OFF = LOCK)** | **90,781** | **1.448** | **1425** | **14.5** |
| 60 | 7,752 | 1.309 | 438 | 22.2 |
| 30 | 5,885 | 1.282 | 360 | 23.4 |
| 10 | 5,142 | 1.275 | 322 | 21.8 |
| 70 | 6,708 | 1.259 | 462 | 23.7 |
| 20 | 4,795 | 1.251 | 331 | 21.9 |
| 40 | 5,023 | 1.218 | 392 | 23.5 |
| 80 | 5,829 | 1.216 | 481 | 25.5 |
| 90 | 5,198 | 1.186 | 510 | 26.4 |
| 50 | 4,225 | 1.185 | 403 | 22.1 |

**Parser validated:** the `0.0` row reproduces the known ProgTrail lock EXACTLY (90,781 / 1.448 / 1425 /
14.5) → column assignment correct.

## Why it loses on every axis (not even the usual consolation)

- **Net collapses ~92%** (90,781 → ~4–8k): once the day's giveback threshold trips, the EA stands down for
  the rest of the day → trade count falls 1425 → 322–510. On XAU's trend-runner edge those skipped days are
  where the fat tail lives; removing them removes the profit.
- **maxDD gets WORSE, not better** (14.5% → 22–26%) at every setting. A stand-down stop normally buys *some*
  DD reduction as a consolation; here it doesn't, because the lock's low 14.5% DD comes from the
  ProgTrail-protected compounding runner. Strip the winners and the equity curve is choppier and the losing
  days dominate a smaller base → higher DD%. The mechanism fails even at its one structural advantage.
- **Monotone-ish in the wrong direction:** no plateau, no sweet spot, no value within reach of the lock. The
  full pooled run fails so decisively that per-fold sub-decomposition is moot — nothing beats OFF to sub-fold.

## What this confirms

This is the 4th independent angle to falsify the user's "MasterVP gives good trades back" thrust **on XAU**:
(1) 7 per-trade profit-locks ([[mastervp-profit-lock-ladder]]), (2) volume-flow conditioned exit
([[mastervp-flow-exit-rejected]]), (3) entry trade-count/streak cap (H10b), and now (4) session-giveback
stop. A day "giving it back" is indistinguishable in advance from a day that's about to run again — exactly
the pullback-vs-reversal ambiguity the flow study proved. The giveback is **opportunity cost on individual
days, not capital risk** (the BE arm already caps per-trade downside).

**The ONLY giveback mechanism that works on XAU is the ProgTrail late-arm ladder** ([[mastervp-progtrail-ladder-lock]],
locked in 1.07, +3.4%) — it locks profit on *matured* winners without standing the EA down. The infra
(`InpGivebackPct`, default-OFF, byte-identical) stays in the tree, inert; it may yet help on a mean-reverting
instrument, but on XAU's trend-runner edge it is closed.

**▶ Next genuinely-open MasterVP lever: H7 (BTC M3 — never properly swept).**
</content>
