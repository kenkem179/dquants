# MT5 run — KK-KenKem E5-only XAU (2026-06-16 21:01)

## What was run
- **EA:** `Experts\dquants\KK-KenKem\KK-KenKem.ex5` — `.ex5` compiled **2026-06-16 08:04**.
- **Symbol/TF:** XAUUSD-Exness-KK, M1, "real ticks". **Window:** 2026.01.01 → 2026.05.29.
- **Config:** E5-only (`E1=0 E2=0 E4=0 E5=1`), loose E5 gates (`InpE5MinMomAdx=0.28`, `InpE5HtfMinAdx=12.97`).
- **Artifacts:** `inputs_echo.txt` (78 inputs), `result.txt`, `tester_20260616.log.gz` (full journal).

## Result
**Final balance $2,689.50 from $10,000 — a −73% blow-up.** This is the *same* failure as before the
session work; it did not improve.

## Why it did not change — TWO independent reasons
### 1. The EA tested was NOT the one I edited (the binding mistake)
The MT5 terminal loads the deploy EA via a **symlink**:
```
MT5/.../MQL5/Experts/dquants  →  /Users/tokyotechies/Workspace/KEM/dquants/mql5/experts
```
So the live deploy vehicle is **`dquants/mql5/experts/KenKem/`** (this repo). My session port this
session went into the **kenkem** repo's `KK-Common/KenKem/` — a *separate, parallel, non-deployed copy*
(different structure: 396-line `Engine.mqh` vs the deploy's 190-line one). MT5 never saw it, and the
`.ex5` in use was from 08:04 (before any edit). The input echo proves it: **no `InpUseSessionFilter`
line**, i.e. the session inputs don't exist in the binary that ran. The kenkem-side edits have been
reverted. **Correction logged: all EA reconciliation must edit `dquants/mql5/experts/KenKem/`** (see
[[deploy-ea-is-dquants-mql5-symlinked]]).

### 2. Even correctly applied, SESSIONS was never the bottleneck for this config
The deploy config is **E5-only**, and the engine proves the blow-up is *missing entry selectivity*, not
session timing. On this exact window/config:

| Config in the tick engine | Trades | Win% | Net |
|---|---|---|---|
| Deploy `.set` as-is (engine keeps its ATR-pctile≥65 + E5 trend-quality≥5 + E5 trend-core filters) | **0** | — | $0 |
| Same E5 config, those 3 filters **removed** (= what the deploy EA actually does today) | **357** | 15.7% | **−$4,070** |
| Add back only ATR-pctile≥65 + E5 trend-core (the two cheap ports) | 290 | 13.4% | −$3,317 |

The deploy EA fires ~357 junk E5 trades because it lacks **A2** (ATR-percentile floor), **A7** (E5
trend-quality min), and the **E5 trend-core** gate — all of which the engine has. With all three, the
engine refuses this config entirely (0 trades). **That selectivity is the real fix, not sessions.**

## Corrected next steps (all in THIS repo's `mql5/experts/KenKem/`, symlink auto-delivers to MT5)
1. Port **A2 + E5 trend-core + A7 (`min_tq_e5`)** into `mql5/experts/KenKem/` (Gates/Entries/Snapshot
   already have `AtrPct`, `TrendCore`) — the dominant divergence for the E5 deploy config.
2. Port **sessions (A1/B2)** into the same tree (re-do of this session's work, in the right place).
3. **Recompile** `dquants/KK-KenKem/KK-KenKem.mq5` in MT5 (the symlink means it picks up the repo edits
   directly), reload `KK-KenKem-E5-XAUUSD.set`, re-run the same window.
   Expect the E5 trade count to collapse toward the engine's (few/zero junk trades), ending the −73% bleed.
4. Then `parity_diff.py` engine-vs-MT5 on the matched config (now loadable both sides — `Inp*` + UTF-16
   loaders landed this session).

## Engine reproduction (commands)
```
cpp_core/build/kenkem/tick_backtester --symbol-xau \
  --bars-m1 cpp_core/tools/bars_xauusd_2026_m1.csv \
  --ticks  cpp_core/tools/ticks_xauusd_2026_may_window.csv \
  --set    <KK-KenKem-E5-XAUUSD.set>
```
(The engine now reads MT5's UTF-16 `.set` and the `Inp*` deploy schema — both fixed this session, commit pending.)
