# Breakout POC-below-edge gate — user assumption → REJECTED (2026-06-24)

## The assumption (user)
> In breakout, only allow Long above mVAH if both mPOC and POC are below current mVAH, and
> only allow Short below mVAL if current mPOC and POC are above mVAL. We can save a lot of
> stupid cost of losing trades.

Intent: skip "late" breakouts where value has already migrated past the edge being broken.

## Implementation (default-OFF, base byte-identical)
- New param `brk_poc_gate` / input key **`InpBrkPocGate`** (`config.hpp`), default `false`.
- Gate in `strategy.hpp::detect_signal` (breakout branch only; reversion untouched):
  - long breakout requires `mPOC < mVAH AND localPOC < mVAH` (current master VP)
  - short breakout requires `mPOC > mVAL AND localPOC > mVAL`
- **mPOC term is structurally always true** — POC lies inside its own value area by construction
  (`POC < VAH`, `POC > VAL` always). So the binding term is the **LOCAL** POC vs the master edge.
  mVAH/mVAL/mPOC = `master_cur`; POC = `local_cur` (108-bar local VP on the M5 lock).
- `make test` green (37+240+13), golden parity unchanged → OFF is byte-identical.

## 6-fold walk-forward result (`wf_mvp_generic.py`, disjoint calendar folds)

| Market | Config | n | PF | net | maxDD | folds+ | worstPF |
|--------|--------|---|----|-----|-------|--------|---------|
| XAU M5 (champion lock) | baseline | 1353 | **1.318** | **21,312** | **7.6%** | 6/6 | **1.094** |
| XAU M5 | gate ON | 847 | 1.214 | 7,979 | 11.4% | 5/6 | 0.846 |
| XAU M3 (M3 lock) | baseline | 1980 | **1.228** | **25,162** | **13.7%** | 4/6 | 0.732 |
| XAU M3 | gate ON | 1458 | 1.137 | 10,222 | 21.5% | 4/6 | 0.756 |

(BTC M5 not run — only XAU fold slices exist; BTC breakout is breakeven anyway.)

## Verdict: REJECTED on every axis
- The gate removes ~30–40% of breakouts (M5 1353→847, M3 1980→1458) but those filtered trades
  are **net profitable**: cutting them craters net **−63% (M5) / −59% (M3)** and makes **DD worse**
  (M5 7.6→11.4%, M3 13.7→21.5%). On M5 the worst fold flips negative (F1 +$1,006 → −$894).
- The microscopic M3 worst-PF bump (0.732→0.756) is meaningless against the net/DD collapse.

## Why the intuition is wrong (mechanism)
The gate only fires in a **trend** regime (breakout path is gated `regime.trend`). The local VP is
108 bars (~9h on M5); the master is 432 bars (~36h). In a healthy, established uptrend the recent
local POC *rises with price* and sits **above** the older master VAH — that is exactly what a strong
trend looks like, not a failed one. So `localPOC < mVAH` rejects breakouts **during the strongest,
most-established trends**, which are the most profitable ones. The filter selects against the edge,
not against the losers. Classic survivorship/intuition trap — same lesson as FVG-SL, VMC,
conviction-protect: a rule that "looks like it skips bad trades" must be validated on the engine, not
eyeballed.

## Disposition
- Keep the code as tested **default-OFF infra** (byte-identical when off; useful as a documented
  negative result). NOT ported to MQL5, NO lock change. Uncommitted per standing user rule.
