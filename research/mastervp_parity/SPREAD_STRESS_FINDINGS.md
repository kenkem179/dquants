# KK-MasterVP — live-spread cost stress (XAU M5 lock)

Quantifies how the locked config holds up as transaction cost rises from the imported feed's
~19-pt gold spread toward the live Exness-KK ~189-pt spread, via the backtester `--extra-spread`
flag (`tick_engine::set_extra_spread` — widens bid/ask symmetrically around mid; signals unchanged).

## 2026 OOS window (Jan–May, the benign-DD window)
| extra_spread | trades | net | PF |
|---|---|---|---|
| +0.00 | 563 | 10,335 | 1.316 |
| +0.05 | 564 | 9,236 | 1.286 |
| +0.10 | 563 | 9,161 | 1.286 |
| **+0.17 (≈ live)** | 562 | 9,077 | **1.282** |
| +0.25 | 563 | 6,939 | 1.224 |

## Full continuous year (2025-06 → 2026-05)
| extra_spread | trades | net | PF |
|---|---|---|---|
| +0.00 | 1,414 | 137,136 | 1.330 |
| **+0.17 (≈ live)** | 1,432 | 80,708 | **1.265** |

## Takeaway
- The edge **survives the real 10× spread**: full-year PF 1.330 → **1.265**, OOS PF 1.316 → 1.282.
  Both clear the ≥1.15 deploy gate. It is NOT a tight-feed artifact.
- Erosion is graceful; only beyond +0.25 (worse than live) does PF fall toward ~1.22.
- Absolute net drops more than PF because sizing compounds (1% risk on a growing balance → bigger
  late-window lots → larger spread $ cost). Combine with WF/MC drawdown honesty (true full-year
  maxDD ~27.7%, MC worst ~55%): **size for ~30-40% peak DD**, do not chase the headline net.
- Live forward results will sit nearer the +0.17 row than the 0-spread lock numbers.
