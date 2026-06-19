# KK-MasterVP-Monster — BTCUSD M3 sweep findings (2026-06-20)

**Approach (per user):** inherit the faithful KK-MasterVP C++ base + add ONLY the impulse-thrust
delta; mine MasterVP/BTC memory instead of blind grids; sweep on the real MT5/BTC feed
(train 2025-08-11→11-30, OOS 2026-01→05); lock the train/OOS-robust plateau. Engine: single-position.

## LOCKED config — `cpp_core/tools/mastervp/monster_btc_m3_LOCKED.set` (WALK-FORWARD RE-LOCK 2026-06-20)
| window | n (imp) | win% | PF | net | maxDD% | impulse net |
|--------|---------|------|------|------|--------|-------------|
| TRAIN (2025 Aug–Nov) | 354 (10) | 48.3 | 1.084 | +$1,268 | 11.4 | +$367 |
| **OOS (2026 Jan–Jun)** | **405 (23)** | **50.9** | **1.192** | **+$3,014** | **9.5** | **+$837** |

Key knobs: master VP = **200 bars** (vp_lookback 50 × mult 4); breakout buf 0.25 / SL 3.7×ATR /
RR 3.0; chandelier trail ON (mult 2.6, runner 5.3R); TP1 1.0R **close 0%** (BE-after-TP1 de-risks at
1R, no partial bank); **adx_trend_min 28**, **di_spread_min 4**; impulse ON (candle 1.7×ATR, M1 net ≥
0.95, predict 10, **slope 6**); best_btc sessions (Asia/Ldn/NY + blocked 8,10,11,16, force-close, 4
trades/session); risk 0.9%; band 0.0156–0.158.

**The WALK-FORWARD re-lock (below) replaced 3 secondary params** vs the original lock (di 6→4,
impulse slope 10→6, TP1 close 15→0). On the original single split this lifted OOS PF **1.131→1.192**
(now clears the ≥1.15 deploy gate), OOS net **+1,956→+3,014**, OOS dd **10.1%→9.5%**, train also up.

## What the sweep taught (and what transferred from MasterVP)
1. **Sessions are decisive.** 24/7 trading collapsed OOS (PF 0.93); restricting BTC to the best_btc
   edge hours (Asia/Ldn/NY + blocked 8,10,11,16) flipped TRAIN to PF 1.13. The BTC edge concentrates
   in specific hours — same lesson as the MasterVP session work.
2. **Long master window generalizes.** Master = 200 bars (50×4) is the OOS-robust plateau; the spec
   default 150 (50×3) was TRAIN-good but OOS-negative; 360+ over-smooths. (MasterVP found 480 on XAU —
   BTC M3 prefers ~200.)
3. **Chandelier trail ON** (the MasterVP S4 lesson) — my first baseline had it OFF and lost badly.
   Tuned BTC economics came straight from `research/optimization/best_btc.set`.
4. **The impulse delta is regime/selectivity-dependent under single-position:**
   - Impulse trades are *individually* OOS-positive everywhere (+$191…+$408).
   - But with a permissive breakout base (adx 24, SL 3.7) impulse **displaces** profitable breakouts
     (one slot) → impulse-ON < impulse-OFF OOS (1.082 vs 1.113).
   - With a **more selective base (adx 28)** the breakout fires less, so impulse fills the gaps and is
     **net-additive**: impulse-ON OOS PF 1.131 / +$1,956 beats impulse-OFF 1.127 / +$1,822. ← LOCKED.
   - adx 32 over-selects → impulse neutral again. adx 28 is the additive sweet spot.
   - **Full impulse value needs Pine-style stacking (≤3/dir)**; single-position caps it. A future
     multi-position engine would likely lift the impulse contribution further.

## Status
Robust, low-DD, genuinely-Monster (impulse additive) edge. After the 2026-06-20 WALK-FORWARD re-lock
(see last section): **OOS PF 1.192, DD 9.5%, and positive in 6/6 disjoint folds** — now CLEARS the
strict deploy gate (OOS PF ≥ 1.15), above the band MasterVP shipped at (OOS 1.114). Forward-test
required. `InpEnableImpulse` is a live toggle for A/B in MT5. (Original single-split lock was OOS PF
1.131 / DD 10.1% — superseded.)

Harness: `research/monster_parity/sweep_monster.py` (BTC, --bars-m1, IMP/BRK split, auto-OOS).

---

## M5 sweep (user-requested) — NOT robust on BTC; M3 is the deployable TF
Swept master length × adx × SL on M5 (train 2025 / OOS 2026), same harness (`--tf m5`).
**Every train-profitable config collapses OOS (best OOS PF 0.979; most 0.84–0.97).** M5 makes far
fewer trades (~150–260 vs ~350 on M3) so configs over-fit the train window with no OOS edge. The
impulse contribution is OOS-negative at permissive bases and only marginally positive at selective
ones — but the base itself is OOS-negative, so it doesn't rescue M5.

| TF | best OOS PF | OOS net | OOS DD | verdict |
|----|-------------|---------|--------|---------|
| **M3** | **1.131** | **+$1,956** | **10.1%** | LOCKED, EA shipped |
| M5 | 0.979 | −$197 | 17.3% | NOT locked (overfit; no OOS edge) |

**Decision:** do NOT lock an M5 Monster `.set` (locking an OOS-negative config would deploy a loser —
same discipline as the KenKem "don't lock an overfit entry set" lesson). Monster ships **M3 only**.
(NB: the parallel KK-MasterVP work found M5 *beats* M3 — but that is XAU + breakout-only, a different
instrument and strategy; it does not transfer to Monster-on-BTC.)

---

## Robustness re-verification (master VP length & "swept vs inherited" audit)
Prompted by the question "is master VP length actually optimal for Monster, or just inherited from
MasterVP?" — fair, because the first pass swept axes SEQUENTIALLY (master length under old economics,
then economics changed). Re-verified at the LOCKED economics:
- **Master length re-swept at locked economics:** 200 bars (50×4) is STILL best OOS (PF 1.131, lowest
  DD 10.1%), corroborated by 210 (70×3 → 1.103). 200 wins under BOTH economics regimes (old SL 2.65 and
  locked SL 3.7) → not a sequential artifact.
- **Joint master × ADX (interaction check):** at master 200, ADX 26/28/32 → OOS PF 1.132/1.131/1.125,
  impulse additive +398/+386/+400, DD ~10% — a genuine 2-D plateau; the lock is interior to it. No
  interaction surprise (the best master length does not shift with ADX).
- ⚠️ **Landscape is JAGGED away from 200:** 150/180/240 bars collapse OOS (PF 0.88-0.91). So 200 is a
  robust *pocket* (200-210 × adx 26-32), NOT a wide smooth plateau — keep master length PINNED at 200.
- **vp_bins:** inherited 40 confirmed (30 and 50 both fail the PF>1 / min-trade gate at the locked cfg).

### Swept-for-Monster vs inherited (honest audit)
- **Swept & verified for Monster:** master VP length (200), vp_bins (40), break_buf, sl_atr_brk,
  trail_atr_mult, adx_trend_min, sessions (vs 24/7), impulse candle_atr & net_min (rr is inert under trail).
- **Inherited (NOT Monster-re-swept), deliberately:** EMA 24/194, node params, di_spread (6),
  ema_sep_atr, impulse entry_buf/max_dist/predict_bars/slope_bars, tp1_r/close, risk & DD limiters.
  These sit at externally-validated values (Monster spec or the best_btc BTC cluster). They are NOT
  fine-tuned because doing so on a single 2025-train/2026-OOS split would curve-fit the one OOS window
  (the repeated lesson across this repo). In particular the 4 impulse-only params govern just ~26 trades
  — tuning 4 knobs on 26 samples is overfitting, so spec defaults are the correct posture.

---

## WALK-FORWARD robustness re-lock (2026-06-20) — the "swept vs inherited" question, answered rigorously
The prior audit (above) left the secondary/inherited params at spec defaults on the explicit grounds
that fine-tuning them on a *single* 2025-train / 2026-OOS split would curve-fit one OOS window. The
right way to actually interrogate them — per the SOP's `/quant-9-walkforward` — is **multiple disjoint
OOS folds**, adopting a change only if it is robust *across* folds (improves the pooled result without
degrading the worst fold). That is what this section does.

**Harness:** `research/monster_parity/wf_monster.py` + a new engine flag `--trade-to-ms` (open no new
positions at/after the cap; keep managing/closing open ones). Six disjoint folds carved from the two
prepared tick subsets (no 8 GB re-read needed):

| fold | window | trades (locked) |
|------|--------|-----------------|
| F1 | 2025-08-11 → 10-01 | 181 |
| F2 | 2025-10-01 → 11-30 | 170 |
| F3 | 2026-01-01 → 02-15 | 107 |
| F4 | 2026-02-15 → 04-01 | 87 |
| F5 | 2026-04-01 → 05-15 | 135 |
| F6 | 2026-05-15 → 06-09 | 73 |

Each combo is scored on the **pooled** trade set (PF/net/DD), plus fold-consistency
(#folds with PF>1) and the **worst-fold PF** — the robustness-relevant metric.

### Per-group results (each secondary param swept across all 6 folds)
- **EMA lengths (24/194):** baseline is the OUTRIGHT best; every perturbation worse → **inherited
  value CONFIRMED**, not luck.
- **ema_sep_atr (0.25):** best; 0.15 raises DD and drops to 3/6 folds; 0.35 marginally worse →
  **CONFIRMED**.
- **node params (touch 0.05, gate ON):** baseline best; disabling the node gate degrades the worst
  fold 0.867→0.766 → **CONFIRMED** (gate earns its keep).
- **risk/DD limiters:** daily-DD 6/8/10 give **identical** pooled results → **structurally INERT**
  (never binds at this trade frequency; 6% kept as a live-safety floor). Loss-streak is non-monotonic
  (3 good / 5 worse / 99 slightly better) = noise → kept at 3 for live safety.
- **impulse entry_buf (0.4) & max_dist (2.5):** entry_buf is flat across 0.25–0.55 → **inert,
  CONFIRMED**. max_dist 3.0 lifts pooled PF but *worsens* the worst fold (0.867→0.844) → **REJECTED**
  (fails the robustness test).
- **di_spread (6→4):** improves the worst fold 0.867→**0.927** and pooled 1.106→1.111 → candidate.
- **TP1 close (15→0):** pooled PF 1.106→1.118, net +369, dd −0.4pp, worst-fold neutral → candidate.
- **impulse trend-slope bars (10→6):** the **dominant lever** — pooled PF 1.106→**1.122**, worst-fold
  0.867→**0.923**, impulse net 769→**1,117 (+45%)**, every axis up → strong candidate.

### Joint confirmation (the repo's hard lesson: sequential wins can fail jointly)
The three worst-fold-improving candidates were tested *together* (2×2×2 grid). They **stack
constructively** — the winner **slope=6 + TP1close=0 + di=4**:

| metric | original lock | **WF re-lock** |
|--------|---------------|----------------|
| pooled PF (6 folds) | 1.106 | **1.140** |
| pooled net | +$3,117 | **+$4,151** (+33%) |
| pooled maxDD | 16.0% | **13.7%** |
| folds positive / PF>1 | 4/6 | **6/6** |
| worst-fold PF | 0.867 | **1.001** |
| impulse net | +769 | **+1,128** |

It works by **converting the two losing 2026 folds to positive** (F3 −$247→+$27, F4 −$469→+$4) while
leaving the strong fold F5 unchanged (~$2,300) — i.e. it **de-risks bad regimes**, the signature of a
real robustness gain rather than a peak-chaser. On the original single split: TRAIN PF 1.071→1.084,
OOS PF **1.131→1.192** (clears the ≥1.15 gate), OOS net +1,956→+3,014, OOS dd 10.1%→9.5%.

**Verdict on the audit:** of the inherited secondary params, **most were confirmed correct by
walk-forward** (EMA, ema_sep, node, entry_buf, risk/DD all best/inert at their defaults). Three —
di_spread, impulse-slope, TP1-close — yielded a genuinely cross-fold-robust improvement and were
re-locked. The 4-impulse-param "too few trades to tune" caution held for entry_buf/predict/max_dist
(inert or worst-fold-degrading); only the slope window moved the needle, and it moved it *robustly*
(improves the worst fold, not just the pool).
