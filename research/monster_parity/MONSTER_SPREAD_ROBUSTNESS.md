# Monster (BTC M3) — spread robustness + cost-aware re-tune attempt

Applied the MasterVP cost-parity lens to the Monster lock (`monster_btc_m3_LOCKED.set`,
WF OOS PF 1.192). Run via the shared mastervp `backtester` + `--extra-spread` (Monster inherits
the base; the `tools/monster/` fork is deprecated).

## Spread sensitivity (OOS 2026, lock as-is)
| extra spread | trades | net | PF |
|---|---|---|---|
| +0.0 | 405 | 3,014 | 1.192 |
| +1.0 | 405 | 2,674 | 1.172 |
| +2.5 | 403 | 2,470 | 1.157 |
| +5.0 | 403 | 1,899 | **1.121** |

Monster is **thinner and more spread-fragile** than the XAU M5 MasterVP lock (which held PF ~1.27
at real spread). A +5 cost pushes Monster under the 1.15 deploy gate.

## Cost-aware SL re-tune (evaluated at +2.5 spread, BOTH windows — adopt only if robust on both)
| InpSlAtrBrk | TRAIN 2025 | OOS 2026 |
|---|---|---|
| 3.0 | PF 0.925 | PF 1.038 |
| **3.7 (lock)** | PF 1.039 | **PF 1.157** |
| 4.5 | PF 1.054 | PF 1.116 |
| 5.5 | PF 1.103 | PF 1.062 |

**No re-tune beats the lock on both windows.** Wider SL improves TRAIN (5.5 → 1.103) but degrades
OOS (1.157 → 1.062) — a curve-fit to train. The locked SL=3.7 is already the OOS-optimum at elevated
cost. The WF lock stands; Monster cannot be meaningfully improved on the engine alone.

## Conclusion / next gate
- EA fixed (runner-TP) + parity journal wired; compiles 0/0. Engine lock reproduces OOS PF 1.192.
- Monster's edge is real but thin and spread-sensitive. **The deploy decision hinges on the LIVE BTC
  spread**, which we don't yet know — the imported feed's spread unit on BTC is ambiguous, so the
  `+N` stress is only a proxy.
- **Required next step = a Monster MT5 parity run (BTC M3)** to (1) confirm the EA reproduces the
  engine after the TP fix, and (2) pin the real Exness BTC spread. Only then is cost-robust re-tuning
  (or a no-go) justified. Do NOT re-tune to a spread proxy before we have that number.
