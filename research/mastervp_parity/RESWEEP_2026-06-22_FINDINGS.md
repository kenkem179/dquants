# KK-MasterVP post-Monster-merge re-sweep — 2026-06-22

After absorbing the Monster impulse path into KK-MasterVP (OFF by default) and retiring the
Monster edition, re-swept all 4 cases (XAU/BTC × M3/M5) on the consolidated engine to confirm
nothing regressed and to check whether the now-first-class impulse lever opens any OOS gain.
Tool: `research/mastervp_parity/resweep_2026-06-22.py` (single train/oos split; ~5s/run).
OOS windows: XAU 2026-02→05, BTC 2026-01→06.

## (A) Regression — engine reproduces every lock ✅
| case | lock OOS (doc) | re-sweep OOS | verdict |
|---|---|---|---|
| XAU-M3 | PF 1.114 / dd 17.5% / +4575 | **PF 1.114 / dd 17.5% / +4575** | exact |
| XAU-M5 | front-runner | PF 1.422 / dd 8.1% / +10211 | strong, consistent |
| BTC-M5 | PF 1.214 / dd 14.2% | PF 1.250 / dd 14.8% / +5116 | reproduces |
| BTC-M3 | no edge | PF 0.772 / dd 60% / −5552 | confirms no edge |

**The Monster merge broke nothing.** The engine is unchanged (impulse was already in the C++
`kk/mastervp`); consolidation did not shift any algo.

## (B) Impulse opportunity — the genuinely new lever
All locks run the ATR band OFF (`InpMaxAtrPct=0`), so impulse (fires only ABOVE the ceiling)
could never fire before. Tested ceiling-only vs ceiling+impulse on OOS:

- **XAU-M5 — mild candidate.** ceiling 0.158: PF 1.422→**1.687** (only), **1.715** (+impulse),
  net +10211→+11430, **dd 8.1→7.8%**, calmar 5.81→**6.32**. *Most* of the gain is the CEILING
  (cutting noisy high-vol breakouts); impulse adds a sliver (+886 net, +0.03 PF).
- **BTC-M5 — ceiling 0.3 candidate.** PF 1.250→**1.390**, net +5116→+7534, calmar 2.21→**2.82**.
  Again ceiling-driven; impulse marginal (+172 net). ⚠️ BTC/Exness feed is historically
  MT5-over-optimistic — engine-only, MT5-confirm before trusting.
- **XAU-M3 — risk-trim only.** ceiling 0.158+impulse: dd 17.5→**12.8%** at calmar 1.60≈1.55,
  but net +4575→+3066 (below baseline). A lower-DD variant, not a net win.
- **BTC-M3 — nothing helps.** Still no edge with any ceiling/impulse combo.

**Verdict on impulse:** by itself it is NOT a free win on the current locks. What it surfaced is
that a **vol ceiling** helps XAU-M5 (0.158) and BTC-M5 (0.3); impulse only recovers a fraction of
the capped trades. That ceiling idea is the real "missed chance" — but it needs the full
WF + Monte-Carlo + overfitting-gate pass before any lock (single-window gains are not lockable).

## (C) Plateau probe — single-window lever upticks are the curve-fit trap
±1-step probes show higher `InpBreakBufAtr`/`InpSlAtrBrk` beating the lock ON THIS ONE WINDOW
(e.g. XAU-M3 sl 1.0→1.3 = +6138 vs +4575; XAU-M5 break_buf 0.85→1.0 = +11694). These are exactly
the per-window optima the 6-fold WF locks deliberately rejected — NOT actionable without re-running
the walk-forward. Noted, not chased.

## Recommended next step (optional)
Run the existing WF+MC harness (`wf_mastervp.py` / `wf_mc.py`) on the **XAU-M5 ceiling 0.158
(+impulse)** variant — the one candidate that improved PF AND net AND dd on the OOS window — to
see if the ceiling survives per-fold; gate it before any lock. BTC-M5 ceiling 0.3 is secondary
(feed caveat). Nothing here is locked.
