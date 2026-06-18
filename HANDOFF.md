# HANDOFF — read me first, update me last

_Last updated: 2026-06-18 PM by Claude (Opus 4.8). Branch `reliableBaseline`. Build GREEN._

## 🎯 Goal: KenKem **E1 perfect parity** (then E2, E4, E5), engine ⇄ MT5. Ground truth = the EA.

## 📍 STATE: E1 NOT at parity (511 vs 78). Over-fire DEFINITIVELY localized to the ARM/LATCH lifecycle — NOT the gate. The "mtf-seed" theory is DEAD (it was 119 bars, not the seed).

### The numbers (E1-ONLY, full 2yr, current config) — reproduced 2026-06-18 PM
- Engine **511** E1 trades vs MT5 **78** (6.5×). diff_kk: **matched 46 / MISSED 32 / OVERFIRE 465**.
- Matched timing near-perfect (median +0min, 40/46 exact-minute) → the matched logic is sound.

### ⭐ DEFINITIVE finding (per-gate confusion matrix — do not re-litigate)
Built engine-side first-fail gate diagnostic (NO EA rerun: MT5 `kke1gate.csv` already has per-gate labels):
`e1_first_fail_label()` (entries.hpp) + `KK_EMIT_GATE_REASON=1` → `GR,ts,dir,label` (tick_engine.hpp) +
`research/kenkem_parity/diff_gate_reason.py` (auto +60s offset → confusion matrix). Self-check: diagnostic
PASS=3990 == production EGATE PASS (faithful by construction).
1. **The GATE is CORRECT.** On 40,779 bars BOTH armed: MT5 blocks `htf_trend` 21,019 → engine PASSes **0**.
   **Total engine-PASS-where-MT5-BLOCK = 122** (119 mtf + 3 tq). The mtf "seed" is just 119 bars — a rounding
   error, NOT the cause. (htf_trend hypothesis tested and REJECTED; mtf-seed theory KILLED.)
2. **THE SEED = arm/latch TIMING.** Engine PASS 3990 = **486 on MT5-armed bars + 3504 on MT5-DORMANT bars**
   (no arm row at all). ~3504 over-passes happen where MT5's latch is dormant → it's WHEN the engine is armed,
   not whether the gate passes. Engine armed at **46,344** bars MT5 isn't; MT5 armed at 14,969 bars engine isn't.
3. **Cross/touch inversion persists:** engine cross 4065 / touch 2220 vs MT5 cross 1174 / touch 3146.
   Self-amplifying loop: each extra fire consumes+frees the latch → cross re-grabs on the next M1 flicker →
   starves touch. The ~2891 extra cross-arms is the lever.

### RULED OUT as the cause (all MATCH the EA — so the cross over-arm is NOT param-driven)
- EMA_ALIGNMENT_TOLERANCE_PIPS=23, pip_size=0.001 (XAU), E1_MAX_CROSS_AGE=28, HTF enum/params
  (E1=M5-only, ADX≥18.5, DI≥4.0), conviction wiring. The gate (incl. mtf/htf_trend) — see finding #1.

### ▶️ NEXT ACTION — the ARM lifecycle, NOT the gate
Localize why engine cross-arms 3.5× MT5 (4065 vs 1174) while touch-arms LESS (2220 vs 3146). Either (a) the
engine registers more M1 "just-cross" flicker arms, or (b) engine touch-arming under-fires → latch free → cross
re-grabs. Compare engine `KK_EMIT_ARMS`/ARMFIRE per-arm src+tf vs MT5's reconstructed arm bars (expiry `age N`
→ arm_idx=expiry−N + `[EMA200 Touch]` lines from `tester.log`). Suspect: M1 just-cross sensitivity
(triggers.hpp:84-99) and the EMA200 touch read (triggers.hpp:101-119). **Do NOT touch the gate.**

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
# per-armed-bar FIRST-FAIL gate label (the confusion-matrix diagnostic — proves gate vs arm):
KK_EMIT_GATE_REASON=1 ./build/kenkem/tick_backtester ... 2>/tmp/greason.txt   (GR,ts_ms,L|S,<label>)
python3 ../research/kenkem_parity/diff_gate_reason.py --engine /tmp/greason.txt \
  --mt5 ../research/kenkem_parity/mt5_runs/RUN_2026-06-18_1.8.154_xau_2yr_E1only_trace/kke1gate.csv
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
