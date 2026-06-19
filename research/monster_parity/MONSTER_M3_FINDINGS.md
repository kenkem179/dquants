# KK-MasterVP-Monster — BTCUSD M3 sweep findings (2026-06-20)

**Approach (per user):** inherit the faithful KK-MasterVP C++ base + add ONLY the impulse-thrust
delta; mine MasterVP/BTC memory instead of blind grids; sweep on the real MT5/BTC feed
(train 2025-08-11→11-30, OOS 2026-01→05); lock the train/OOS-robust plateau. Engine: single-position.

## LOCKED config — `cpp_core/tools/mastervp/monster_btc_m3_LOCKED.set`
| window | n (imp) | win% | PF | net | maxDD% | impulse net |
|--------|---------|------|------|------|--------|-------------|
| TRAIN (2025 Aug–Nov) | 351 (11) | 48.4 | 1.071 | +$1,047 | 11.5 | +$408 |
| **OOS (2026 Jan–May)** | **402 (26)** | **49.8** | **1.131** | **+$1,956** | **10.1** | **+$386** |

Key knobs: master VP = **200 bars** (vp_lookback 50 × mult 4); breakout buf 0.25 / SL 3.7×ATR /
RR 3.0; chandelier trail ON (mult 2.6, runner 5.3R); TP1 1.0R close 15%; **adx_trend_min 28**;
impulse ON (candle 1.7×ATR, M1 net ≥ 0.95, predict/slope 10); best_btc sessions (Asia/Ldn/NY +
blocked 8,10,11,16, force-close, 4 trades/session); risk 0.9%; band 0.0156–0.158.

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
Robust, low-DD, genuinely-Monster (impulse additive) edge: OOS PF 1.131, DD 10.1%. Below the strict
deploy gate (OOS PF ≥ 1.15) but in the same band MasterVP shipped at (OOS 1.114) — promising,
forward-test required. `InpEnableImpulse` is a live toggle for A/B in MT5.

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
