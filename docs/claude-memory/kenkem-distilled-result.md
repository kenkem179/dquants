---
name: kenkem-distilled-result
description: KenKem distilled to a toggleable entry MENU (E1/E2/E4/E5); 2026-OOS sweep recommends E2+E5 both symbols (E5 most robust, E1 overfits, E4 drags XAU)
metadata: 
  node_type: memory
  type: project
  originSessionId: 67691271-7127-41af-98bb-1c0f44816ec8
---

> ⚠️ **2026-06-15 CORRECTION — every PF/net figure below is a BAR-engine number and is INVALIDATED.**
> Re-baselined the locked E5 sets on the canonical TICK engine over 2026 OOS: **BTC PF 0.718 (−$25,981),
> XAU PF 0.889 (−$4,261)** — both LOSE. The bar engine flips the sign (BTC bar PF 1.339 same window). So
> the "BTC OOS PF 1.239 / XAU 1.083 / E5 prod PF 1.792/1.619" claims here are artifacts; the
> **production promotion of KenKem-E5 rests on numbers that don't survive the faithful engine.** Cause =
> [[bar-engine-systemic-defect]] + unresolved ~30× over-firing. Also: the deployed `Inp*` `.set` is silently
> ignored by `load_set` (UPPERCASE-only) AND holds different values than the validated set. Full evidence:
> `research/kenkem_parity/SYSTEMIC.md`. Do NOT trust any number below until the tick engine reproduces it.

KenKem port pivoted (user directive 2026-06-14): distill the bloated ~9.7k-LOC EA to its essential
winning core rather than byte-reproduce it. Built `kk::kenkem` C++ engine (config→tf_cache→triggers→
snapshot→gates→entries→trade_manager→engine, 8 unit tests / 131 checks) + `tools/kenkem/backtester.cpp`
+ `optimize_kenkem.py`. Validation = quant SOP (NOT MT5 byte-parity, which the distillation makes moot).

**Entries are a toggleable MENU** (user corrected my over-pruning — E5/SuperBros belongs in KenKem and
was wrongly skipped; it's the BEST standalone). Standalone BTC-2025 PF: E5 1.147 / E4 1.090 / E1 1.064 /
E2 1.036 — all profitable. E5 = fresh STRICT M1 4-EMA alignment onset + price>EMA25, sideways+HTF only
(no hard gate), SL at EMA200. E4 = Ichimoku Tenkan/Kijun cross (the EA mislabels iIchimoku buffers 0/1
as "cloud" = really TK lines; see [[kenkem-parity-traps]]).
**Entry-set comparison refreshed 2026-06-14** (`sweep_kenkem_entrysets.py`, 400 trials/combo on 2025,
ranked by 2026 true-OOS PF — supersedes the older E4-centric read below). Every combo OOS-profitable.
- BTC OOS PF: E5 1.523 > **E2+E5 1.348 (net $125k, IS≈OOS)** > E4 1.291 > E2 1.273 > ALL 1.207; E1 worst
  (1.121) and all E1 combos OVERFIT (IS PF collapses OOS).
- XAU OOS PF: E5 1.636 > E1 1.380 > E2 1.355 > E1+E5 1.307 > **E2+E5 1.270** ; **E4 DEGRADES OOS** (1.262→1.168).
- **E5 is the most robust entry on both symbols; E1 weakest/overfits; E4 drags XAU. RECOMMEND E2+E5 both.**
  Tuned configs saved as `best_kenkem_<combo>_<sym>.set`. Current locked prod is BTC=E5-only / XAU=E2+E4+E5;
  swap to E2+E5 pending user sign-off (locked `.set` files NOT yet changed).

**Validated numbers** (fixed-fraction sizing $10k, costs modelled):
- BTC: 2025 PF 1.270 (test-split 1.201) → **2026 true-OOS PF 1.239** net +$61k DD $8.6k win 57%.
  MC 5000 bootstraps 100% profitable, PF-P5 1.164. Spread-robust to $6 (PF 1.173).
- XAU: 2025 PF 1.207 → **2026 OOS PF 1.083** net +$14k.

Artifacts: `research/optimization/best_kenkem_{btc,xau}.set`, `KENKEM-RESULTS.md`, bars
`cpp_core/tools/bars_*_{2025,2026}_m1.csv`. Engine on branch 1-reorganize-code.

**PROMOTED 2026-06-15 (E5-only, first full end-to-end deploy):** user asked to promote E5 to see the
dquants pipeline's end goal. Locked `best_kenkem_{btc,xau}.set` ← `best_tuned_e5_{btc,xau}` (E5 only).
MT5 deploy = thin EA `mql5/experts/KK-KenKem/KK-KenKem.mq5` (compiles 0/0; defaults now E5-only BTC) +
per-symbol `KK-KenKem-E5-{BTCUSD,XAUUSD}.set` (magics 4242410/4242411). Engine in `mql5/experts/KenKem/`
(E1/E2/E4/E5 all ported, toggleable) + `KK-Common/`. **MT5 visibility:** single symlink
`MQL5/Experts/dquants -> dquants/mql5/experts`, so all dquants EAs sit under Navigator→Experts→dquants→…
(isolated from ../kenkem symlinks). E5-only validated 2026-OOS: BTC PF 1.792 net +72.9k DD 2.48k recov
29.4 Sharpe 17.7 ~12.8 trades/day; XAU PF 1.619 net +28.4k DD 1.16k recov 24.4 Sharpe 10.8 ~7.1/day.
**Remaining Phase-10 gate:** one-off MT5-tester↔C++ parity diff + demo forward-test before live.

**Next:** compare vs Monster + MasterVP OOS → confirm #1 (see [[milestone-production-promotion]]); E2+E5
remains the higher-net alternative if user prefers net over risk-adjusted PF.
