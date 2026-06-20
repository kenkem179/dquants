# VMC — Volume Momentum Confirmation (SPEC)

**Status:** v1 implemented in common modules (C++ + MQL5), parity-ready, **not yet validated on data.**
**Owner module:** `kk::VolumeMomentum` (`cpp_core/include/kk/common/volume_momentum.hpp`) ⇄
`CVolumeMomentum` (`kenkem/MQL5/Experts/KK-Common/Core/VolumeMomentum.mqh`).
**First consumer:** KenKem **E5** (M1 4-EMA scalper) as an A/B confirmation gate. Timeframe-agnostic by design (M1/M3/M5).

## 1. Hypothesis
Price/ADX/DI/RSI lag because they smooth price. The *direction of order flow* leads. On a feed with
**no real volume** (`VOLUME=LAST=0`; only per-bar `tick_count` + tick bid/ask), the best available proxy
for flow is the **tick rule on mid** (Lee-Ready 1991; López de Prado 2018). A composite of
**flow direction + persistence + retention** should catch trend onset/continuation that lagging ADX misses.

## 2. Research verdict (why a bespoke composite, not an off-the-shelf algo)
Every published method assumes real volume we don't have:
- **VPIN** (Easley-LdP-O'Hara 2012) — volume-bucket imbalance → **regime/toxicity gate only**, NOT direction
  (Andersen-Bondarenko: tick-VPIN is circular with tick-count). Used here as the spread/tick-count z gate.
- **OFI** (Cont-Kukanov-Stoikov 2014) — best short-horizon directional signal, but needs **L2 depth** → excluded.
- **CVD / run bars / long-memory of order flow** (Bouchaud, LdP) — the directional + persistence constructs we DO adopt.
- Flow edge is **sub-minute→M1 and decays by M5** → test **E5 (M1) first**; expect it to *augment*, not auto-replace, ADX.

**Circularity guard (the core design rule):** sign by tick **direction counts only**, never weight by price
distance. The node-engine `dirProxy=(close-open)/(high-low)` is re-laundered price and is **rejected**. A bar can
close green while logging more down-ticks (`r<0`) — that disagreement is the one component independent of the EMA stack.

## 3. Algorithm (exact)
Per tick within bar *b* (mid = (bid+ask)/2, integer points `mid_pts = round(mid/point)`):
```
d = mid_pts - prev_mid_pts          # prev carried CONTINUOUSLY across bars; only up/dn reset per bar
s = +1 if d >=  epsilon_pts
    -1 if d <= -epsilon_pts
     0 otherwise (flat — EXCLUDED from gross, no carry-forward)
```
Per bar: `up=Σ(s=+1)`, `dn=Σ(s=-1)`, `gross=up+dn`, **`r_b = (up-dn)/max(gross,1) ∈ [-1,1]`** (the "% net delta retained").

Three legs:
- **Direction** `D = EWMA(r_b, span=ewma_span) ∈ [-1,1]` — the tick-CVD slope. *No z-score* (r is already a ratio;
  z-scoring zeroes out a sustained push as its own mean catches up — wrong for a "confirm strong momentum" gate).
- **Persistence** `P = (#last L bars with sign(r_b)==sign(D)) / L ∈ [0,1]` (`L=persist_len`). Long-memory proxy.
- **Retention** `R = mean(|r_b|) over last retention_len bars ∈ [0,1]` (absorption: high=clean push, low=contested).

**Regime gate** `G` (suppress → VMC=0): `ext_block` (news/session/weekend, from SessionManager/NewsFilter)
OR `spread_z > spread_z_max` OR `tick_z > tickcount_z_max` (z over `z_window`) OR warmup not met.

**Score:** `VMC = clamp(D/d_ref, -1, 1) · P · R ∈ [-1,1]`, forced **0** if gated/invalid.

## 4. Params (.set-sweepable; timeframe-neutral defaults, windows in BARS)
| param | default | sweep | role |
|---|---|---|---|
| `epsilon_pts` | 1 | 0–3 | tick dead-band (Roll-bounce guard) |
| `ewma_span` | 5 | 3–10 | smooth r into D |
| `d_ref` | 0.5 | 0.3–0.8 | delta-ratio = "full strength" |
| `persist_len` | 5 | 3–10 | persistence lookback |
| `retention_len` | 5 | 3–10 | mean\|r\| window |
| `z_window` | 120 | 60–240 | spread/tick z baseline |
| `spread_z_max` | 2.5 | 2–4 | toxic-spread suppress |
| `tickcount_z_max` | 3.0 | 2.5–5 | toxic-burst suppress |
| `warmup_bars` | 30 | fixed | validity gate |
| **E5 wiring** | | | |
| `use_vmc_gate` | false | {0,1} | master A/B switch |
| `vmc_min_confirm` | 0.20 | 0.05–0.5 | gate threshold |
| `forming_bar_mode` | 0 (closed) | {0,1} | shift-1 vs intrabar |

## 5. E5 integration (A/B, not a rip-out)
E5 currently has **no active momentum gate** (`E5_MIN_MOMENTUM_ADX=0`, `useADXFilter=false`) → cleanest experiment:
- **Baseline:** E5 unchanged. **Treatment:** add `if(use_vmc_gate && !g_vmc.Confirms(dir, vmc_min_confirm)) skip;`
  in `Entry5::Decision()` (long: `vmc ≥ +thr`; short: `≤ −thr`).
- No ADX double-count (ADX off). Optional later arm: **divergence veto** + extend to E1–E4 (which *do* gate on ADX)
  only if E5 OOS improves with costs.

## 6. No-repaint / forming-bar (Q7)
v1 gates on the **committed (last-closed, shift-1)** reading → zero lookahead/repaint, guaranteed parity. Cost =
1-bar lag. `forming_bar_mode=1` (v2) uses `PeekForming()` (provisional, non-mutating) with a **latched** decision;
enable only after v1 parity is proven, since intrabar parity needs EA + engine to fire at the identical trigger tick.

## 7. Parity plan (C++ ⇄ MQL5)
Bit-identical by construction: **all signing in integer points** (`round(mid/point)` = `(long)MathRound`),
prev_mid carried across bars, flat ticks excluded, population mean/var recomputed from the ring each bar
(identical op-order), EWMA seeded on first value. Live MQL5: `CopyTicksRange(bar_open, next_bar_open)` per closed
bar → feed `OnTick()` in order → `OnBarClose()`. **Validation:** feed both engines the same tick slice; assert
integer fields exact, float fields `<1e-9`; emit `parity_vmc_*.csv` (r,cvd,d,persist,retention,vmc,gated).

## 8. Tests
C++ `tests/common/test_volume_momentum.cpp` (17 checks, all pass): dead-band, cross-bar carry,
**independence (green bar + majority down-ticks ⇒ r<0)**, warmup/gating, persistence+`Confirms()`,
determinism, peek-no-mutate. MQL5 compiles 0 errors / 0 warnings via `KK-Common-CompileCheck.mq5`.

## 9. Next steps (open)
1. **Data analytics** (pending): on real imported ticks, measure (a) corr(r_b, bar return) — confirm partial
   independence; (b) does `r_b`/`D` lead price vs ADX at M1; (c) `r_b` distribution per symbol (set `d_ref`).
2. Wire `use_vmc_gate` into E5; C++ tick-engine A/B sweep (`vmc_min_confirm`, `ewma_span`, `persist_len`) on
   XAU M1 + BTC M1; plateau check; walk-forward; **all costed**.
3. MQL5 parity diff harness + `parity_vmc_*.csv`.
4. If E5 wins: divergence-veto arm; extend to E1–E4 replacing ADX/DI/RSI.
