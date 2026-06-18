# HANDOFF — read me first, update me last

_Last updated: 2026-06-18 by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN, 28 C++ checks pass._

## 🎯 Goal: KenKem **E1 perfect parity** (then E2, E4, E5), engine ⇄ MT5. Ground truth = the EA.

## 📍 STATE: over-fire root cause LOCALIZED to a feedback loop; seed not yet fixed.

### The numbers (E1-ONLY, full 2yr, current pip-fixed config)
- Engine **531** E1 trades vs MT5 **78** (6.8× over-fire). diff_kk: **matched 46 / MISSED 32 / OVERFIRE 465**.
- Matched timing near-perfect (median +0min, 40/46 exact-minute) → the matched logic is sound.

### What is TRUE (evidence-backed, do not re-litigate)
1. **Arm GEOMETRY is correct.** Direction-change arms: engine **1197** ≈ MT5 **1174** ≈ alternation **1193**.
   The prior "engine over-arms 4×" was an ARTIFACT (engine raw count vs a mis-measured MT5 ~1000). DEAD.
2. **Cross/touch split is INVERTED:** MT5 cross 1174 / touch 3146 (touch-dominated); engine cross 4059 /
   touch 2195 (cross-dominated). Engine cross = 1197 genuine + **2860 SPURIOUS same-dir re-arms** (1694
   M1-alone). MT5 re-arms same-dir via TOUCH, not cross.
3. **Overfire decomposition (485 bars vs MT5 KKE1ARM/KKE1GATE):** 77% MT5 was DORMANT (no arm) · 11% MT5
   gate-PASSED but didn't fire (position-open) · 5% MT5 gate-BLOCK (21 mtf, 3 price_pos). **Gate leak is minor.**
4. **MECHANISM = feedback loop.** MT5 holds its latch armed for long stretches (median 97 bars; the 28-bar
   expiry only runs when DetectE1Entry is reached, so it expires LATE — `Expired stale … age 30/58/521`).
   While armed, MT5's latch SUPPRESSES M1-fan flickers (MT5 sees 8016 M1 just-crosses, arms only 1174).
   The engine fires more → clears its latch → latch FREE when flickers hit → arms on flicker → fires →
   repeat. Cross has PRIORITY over touch for the shared latch → engine touch starves (2195 vs 3146).
5. **Seed = arm→fire CONVERSION: engine gate PASSES 3990 vs MT5 554 (7.2×); pass→fire ratio similar
   (13% vs 14%).** So the gate is the seed, not the post-gate routing.
6. **⭐ SEED PINPOINTED to the `mtf` gate.** Built `KK_EMIT_GATE` (engine `EGATE,ts,dir,PASS|BLOCK` per
   armed bar). On 41,670 bars BOTH evaluated: agree 40,868 BLOCK + 375 PASS; **engine PASS where MT5 BLOCK
   = 277, of which 270 are MT5's `mtf` gate** (`isAllTimeframeEMAsReadyForEntry`). 150 engine-BLOCK/MT5-PASS.
   The ~270-bar `mtf` leak is the seed that the re-arm loop amplifies into 3436 extra dormant-zone passes.

### RULED OUT this session
- **EMA shift trap** (`KK_E1_EMA_TRAP=1` → 549 trades, WORSE; flicker count is shift-invariant).
- **occ-before-expiry ordering** in `entries.hpp` — reordered to expiry→occ to match EA Entry1.mqh:103
  (faithful, tests pass) but NEUTRAL on results. KEPT as a correctness fix.

### ▶️ NEXT ACTION — break down the `mtf` leak (270 bars)
Engine MTF (`entries.hpp:154-165`) and EA `isAllTimeframeEMAsReadyForEntry` (KenKemExpert.mq5:1946-1994) look
logically identical (bypass-lvl-1: `m1_ready && ((m3_ready && m5_dir) || extreme)`; extreme = M1 DI-spread≥16).
So the leak is at the **boundary inputs** — prime suspect the `extreme` DI bypass or m1/m3 ready tolerance edge,
a per-bar DI/EMA micro-difference. NEITHER trace carries DI today → instrument BOTH sides: add the MTF
sub-components (m1_ready, m3_ready, m5_dir, extreme, M1 DI±) to the engine `EGATE` AND the EA `KKE1GATE,mtf`
detail (needs a small EA recompile + one rerun), then compare at the 270 leak bars to see which sub-check flips.

## 🔁 Repro (full 2yr ≈ 2min, 5GB tick stream)
```
cd cpp_core && make kenkem_tick
# trades + consumption-aware arm count:
./build/kenkem/tick_backtester --bars-m1 tools/bars_xauusd_2024_2026_m1.csv \
  --ticks tools/ticks_xauusd_2024_2026.csv --symbol-xau --spread 0.05 --to-ms 1780272000000 \
  --set ../research/kenkem_parity/anchor_E1_only_trace.set --out /tmp/e.csv
python3 research/kenkem_parity/diff_kk.py --engine /tmp/e.csv \
  --mt5 research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/trades.csv --kind E1
# per-bar engine latch age:  KK_EMIT_ARMSTATE=1 ... 2>/tmp/estate.txt  (ESTATE,ts_ms,armU_age,armD_age)
# per-arm src/tf:            KK_EMIT_ARMS=1 ...      2>/tmp/armfire.txt (ARMFIRE,ts_ms,L|S,cross|touch,tfbits)
# per-armed-bar gate verdict:KK_EMIT_GATE=1 ...      2>/tmp/egate.txt   (EGATE,ts_ms,L|S,PASS|BLOCK)  vs MT5 kke1gate.csv
```

## 📦 Data & instruments
- MT5 ground truth: `kenkem/Tester/Agent-127.0.0.1-3000/logs/20260618.log` — E1-only, E1_ARM_TRACE=true,
  **418k `KKE1ARM` per-bar latch rows** (`ts,jcU(m1m3m5),jcD,rU(m1m3),rD,armU,armD,e2U,e2D`).
  Trades+gate: `research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/`
  (trades.csv 78, kke1gate.csv 55748).
- EA inputs added: `E1_GATE_TRACE` (Entry1.mqh → KKE1GATE), `E1_ARM_TRACE` (EMAHelpers.mqh → KKE1ARM).
  EA compiles from `kenkem/MQL5/Experts/KenKem/` (MT5 `Experts\KenKem\KenKemExpert.ex5` maps here — NOT the
  dquants copy for THIS expert; verified via run log).
- Engine instruments: `KK_EMIT_ARMSTATE` (new, ESTATE per-bar age), `KK_EMIT_ARMS` (ARMFIRE), `e1_arm_dumper`
  (raw bar-only arms, no consumption). Analysis: `/tmp/{armdiff,noarm,join_gate,overfire}.py`,
  MT5 extracts `/tmp/{mt5_arms,mt5_armstate,mt5_jc}.csv`.

## 🧱 After E1→E5 parity is LOCKED (user's explicit next phase)
Convert all pip-denominated params to ATR-relative per `docs/PIP_TO_ATR_INVENTORY.md`. NOT before — parity
is the ground truth. See memory [[goal-pip-to-atr-relative]] and [[kenkem-e1-overfire-trendcore]].
