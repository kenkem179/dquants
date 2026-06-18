# KK-MasterVP-Monster — Full-Space Joint Optimization Findings

> 🛑 **INVALID FOR DEPLOYMENT (2026-06-15) — engine/MQL5 PARITY DIVERGENCE.** The KK-Monster MQL5 run
> in the MT5 tester (BTC M3, 2025.10→2026.05) made **ZERO trades over 8 months**. The dquants Monster
> C++ engine, on the same config, makes 150–184 profitable trades (PF ~1.65). So the engine and the
> deployable MQL5 disagree completely. Root cause: the C++ engine derives **net volume from tick
> price-deltas** (so its `NetMin` gates of 0.8–0.95 pass and it trades), while the MQL5 keys off a
> volume signal that is ~0 on the Exness feed (broker VOLUME=0 / different net calc), so the same
> `InpBrkNetMin`/`InpImpulseNetMin` gates are NEVER met and nothing fires. **Every PF below is
> engine-internal and does NOT transfer to MT5.** Do not deploy Monster until net-volume parity is
> fixed AND the MQL5 is confirmed to trade in MT5. See `MT5-GROUND-TRUTH.md`. —Claude


The **Monster edition** = the parity-validated KK-MasterVP engine with the **mean-reversion leg
activated** (`InpEnableReversion=true`) and the **entire wired parameter space jointly optimized**
(breakout + reversion + exits + regime + node engine + volatility gate + sizing), vs the first BTC
pass which tuned only 9 exit/economics knobs. Optimizer: `optimize_monster.py <btc|xau>` — 400-trial
TPE, reversion forced on, momentum/flow filters as categorical toggles. Refined from the strong-OOS
**sub-cluster** (a plateau of coherent trials), not a lone best trial.

Window: 2025 M3, train = Aug–Oct, test/OOS = Nov(+Dec for XAU). Run on the headless C++ tick engine
(Layer 3), which is parity-validated against the KK-MasterVP MQL5 module tree.

## BTC Monster (`best_monster_btc.set`)

| metric | value |
|--------|-------|
| FULL net / PF | **+$3934 / 1.228** |
| OOS (Nov) net / PF | **+$421 / 1.081** |
| max DD | $872 |
| trades | 600 (win 60%) |
| breakout leg | +$2863 / PF 1.20 (486 tr) |
| **reversion leg** | **+$1071 / PF 1.35 (114 tr, 64% win)** |
| Monte Carlo (5000) | 96.3% profitable, P5 PF 1.020 |
| rolling | ALL 4 months + ALL 8 half-months positive |

Key: activating reversion **broadened the plateau** (121/400 robust trials vs 16/200 in the
breakout-only pass) and moved `AdxTrendMin` from the fragile 24 peak to a **stable 16–17** cluster.
`UseMomVeto` off unanimously. SlAtrBrk ~2.9, BreakBufAtr ~0.33, RunnerRr ~4.5, BrkRequireFlow on.

## XAU Monster (`best_monster_xau.set`) — strongest result

| metric | value |
|--------|-------|
| FULL net / PF | **+$11,615 / 1.323** |
| OOS (Nov–Dec) net / PF | **+$5086 / 1.276** |
| max DD | **$873** |
| trades | 641 (win ~47%, low-WR high-RR) |
| breakout leg | dominant, PF ~1.23 |
| reversion leg | net-positive ONLY with `UseMomVeto=on` (the momentum gate filters bad VA-edge fades) |
| Monte Carlo (5000) | **99.9% profitable, P5 PF 1.137** |
| rolling | ALL 5 months positive (PF 1.14–1.50); 9/10 half-months (08a flat −$9) |

Key XAU differences from BTC: **`UseMomVeto` ON** (30/30 consensus — opposite of BTC), wider SL is NOT
needed (SlAtrBrk ~2.0), `AdxTrendMin` ~25 (XAU trends cleaner), `Tp1R` high (~1.4) + `Tp1ClosePct` high
(~37%) — XAU takes more partial early. Reversion alone loses on XAU (−$965); the momentum veto is what
makes the dual-leg net-additive. 348/400 robust trials = a very broad plateau, so the best trial is
adopted directly (it dominates the median on net AND PF AND DD).

## Cross-symbol takeaways
- The **reversion leg is genuinely additive** on both symbols, but gated differently: BTC wants
  momentum veto OFF, XAU wants it ON. Symbol-specific toggles matter.
- XAU carries a far larger $ edge than BTC (vppl=100, cleaner trends) at comparable PF.
- Both configs are temporally robust (every month positive) and resampling-robust (MC P5 PF >1).

## Caveats / next
- Absolute $ carry the documented ATR-from-CSV residual vs MT5 (engine reads exported tick CSV, whose
  intrabar extremes are narrower than the MT5 tester's internal model). The **relative** improvement
  and the **param directions/toggles** are the trustworthy signal — same basis on which `best_btc.set`
  already confirmed PF>1 in the live MT5 tester.
- **MQL5 port note:** the user's `kenkem/MQL5/Experts/KK-MasterVP-Monster/` EA already exists and has
  diverged/evolved (NetVolume, StatePersistence, instance-guard, embedded news, on `KKMasterVPv1`).
  These configs must be mapped onto THAT EA's actual input schema (read-only), not a fresh recreation.
- Repro: `python research/optimization/optimize_monster.py btc 400 4` (and `xau`).
