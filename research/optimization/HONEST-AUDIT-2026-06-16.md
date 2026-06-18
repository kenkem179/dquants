# HONEST AUDIT — engine-claim vs MT5-reality (2026-06-16)

Triggered by user concern: *"your test results are extremely unreliable; the Monster EA was trash, no
profit."* Correct concern. This file is the unspun scorecard. **The in-repo C++/bar engines are NOT
trustworthy for P&L on KenKem and Monster. Only MT5 deal-stream numbers are treated as truth here.**

## The one rule that explains everything
The dquants engines overstated profit, and the "optimized" `.set` configs swept **EA-hardcoded params
that MT5 silently ignores** — so the deployed EA can't reproduce them and loses. (Root cause already
fixed structurally this session — see `PARAM_SURFACE_AUDIT.md` — but the promoted candidates predate the
fix and are unreliable.)

## Scorecard — what the engine CLAIMED vs what MT5 ACTUALLY did

| EA (dquants port) | Engine claim (in-repo) | MT5 reality | Verdict |
|---|---|---|---|
| **KK-KenKem** (E5/E4 distilled) | OOS PF **1.24–1.62**, +24% | XAU M1: −62% to −93%, PF 0.78–0.87; 2,338–5,762 trades (15–40× over-firing) | ❌ **Blowup** |
| **KK-MasterVP** | signal-exact parity; engine profitable | BTC M3: −19%, PF 0.97; XAU M1: 0 trades (period-dependent) | ⚠️ **Loses on recent OOS** |
| **KK-Monster** | full PF **1.23–1.32**, MC 96–100% profitable | Was 0 trades (BTC, broken net-volume port); now over-fires & loses | ❌ **Parity divergence** |

### Fresh corroboration — today's MT5 journal (`20260616.log`, TP-vs-SL proxy)
| EA | Sym/TF | period | entries | TP | SL | TP-win% |
|---|---|---|---:|---:|---:|---:|
| KK-KenKem | XAU M1 | 03→05/25 | 1164 | 1 | 629 | **0%** |
| KK-MasterVP | XAU M1 | 03→05/25 | 0 | 0 | 0 | n/a (fires nothing) |
| KK-MasterVP | BTC M3 | 03→05/25 | 814 | 63 | 451 | 12% |
| KK-Monster | XAU M1 | 03/25→06/26 | 2576 | 311 | 1411 | 18% |
| KK-Monster | XAU M3 | 03/25→06/26 | 1265 | 153 | 687 | 18% |
| KK-Monster | BTC M3 | 03→12/25 | 1146 | 133 | 667 | 17% |

(TP/SL is a proxy, not net P&L — some closes are trail/session. But 0–18% TP rates + thousands of
trades + avg win $21 / avg loss $156 = death by costs. Consistent with the user's "no profit.")

## The ONLY thing that actually works in MT5
The user's **ORIGINAL `KenKemExpert`** (E1+E2, full selective logic): **143 trades, +24.1%, PF 1.62,
Sharpe 1.85** on XAU M1 2025.08→2026.06. The distilled dquants ports trade 15–40× more and bleed out.
**The edge was in the selectivity the "optimization" stripped.**

## What to trust going forward
1. **No P&L claim is valid unless it comes from the MT5 deal stream** (or a tick engine *proven* to
   reproduce it bar-for-bar). The bar engine disagrees with MT5 on the **sign** of P&L.
2. **MasterVP** is the only port with signal-level parity — but it still loses on recent OOS, so it is
   *parity-validated, not profit-validated*. Don't deploy.
3. **Compiling ≠ validating.** All three compile clean; none is production-eligible.
4. Production recommendation stands: **deploy the user's original `KenKemExpert`**, not any dquants port,
   until a port is MT5-profit-confirmed on recent OOS.
