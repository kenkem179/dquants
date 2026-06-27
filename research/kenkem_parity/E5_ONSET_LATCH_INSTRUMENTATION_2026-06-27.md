# E5 onset-latch realtrace instrumentation — built, awaiting 1 MT5 run (2026-06-27)

**Goal:** close the last E5-parity gap — the **42/51 missed E5 trades = M1 onset BAR-PAIRING** (engine arms
`aligned@B-2 && !aligned@B-3`; MT5's realtrace VALUES imply `aligned@B-1 && !aligned@B-2`). The engine EMA
values MATCH MT5 exactly; only WHICH bar-pair the onset latches differs. A naive global shift REGRESSED
(recall 52.8→41.7%, net −617→−1231; arming+fire coupled). The correct fix needs the EA's EXACT latch
internals, which the realtrace lacked — so this session ADDED them. (Path chosen by user: instrument + MT5 run.)

## What was instrumented (kenkem repo — diagnostic only, default-OFF, lock untouched)
4 new columns on the real-path E5 trace, exposing the onset latch state per armed/fired bar:
- `prev_aligned_bull` / `prev_aligned_bear` — the `m_prevBullishAligned`/`m_prevBearishAligned` the onset
  COMPARED against (`aligned@cur && !m_prevAligned`), captured BEFORE the once-per-bar overwrite.
- `last_bull_signal` / `last_bear_signal` — the armed-bar index (`m_lastBullishSignal/Bearish`, −1 if none).

**Files (kenkem repo working tree — NOT committed there; user manages that repo):**
- `MQL5/Experts/KenKem/Parity/RealTrace.mqh` — 4 fields on `E5RealRow` + header + writer.
- `MQL5/Experts/KenKem/Entries/Entry5.mqh` — persistent members `m_rtPrevBull/m_rtPrevBear` (init false),
  latched in the once-per-bar onset block BEFORE `m_prev*Aligned` is overwritten, copied into `m_rt` in the
  per-tick snapshot (m_rt is RTReset() every Detect tick, so a persistent store is REQUIRED — a direct m_rt
  write would be zeroed on whatever later tick writes the row).
- **Compiled clean: `KenKemExpert.ex5` (version 1.8.154), 0 errors.** ⚠️ The realtrace-wired EA is
  `KenKemExpert.mq5` (includes RealTrace.mqh at line 41, before Entry5 at 47) — NOT `KenKemExpert-1.8.154-dev.mq5`
  (that snapshot has NO RealTrace include → does not compile headless; red herring). `kenkem/MQL5/` IS the MT5
  data folder, so the fresh `.ex5` is live for the tester.

## ▶ USER MT5 RUN (exact — per [[mt5-run-instructions-must-be-exact]])
- **EA:** `KenKemExpert` (the one just compiled; NOT the `-1.8.154-dev` variant)
- **Symbol:** your XAUUSD (the same symbol the prior E5 realtrace runs used, e.g. `XAUUSD-Exness-KK`)
- **Timeframe:** **M1**
- **Date range:** **2026.01.01 → 2026.06.01** (the fresh 2026 selection-break window, MT5 truth = 108 E5 / +949)
- **Model:** Every tick based on real ticks
- **Inputs:** Load `dquants/KK-KenKem/KK-KenKem-E5only-2026H1-RealTrace.set` (E5-only; E1/E2/E3/E4 OFF;
  `InpExportRealTrace=true`). *(staged at `research/kenkem_parity/KK-KenKem-E5only-2026H1-RealTrace.set`;
  run `scripts/sync_presets.sh` if loading via the organized view.)*
- **Deposit:** 10000. After the run, the trace lands at
  `kenkem/Tester/Agent-127.0.0.1-3000/MQL5/Files/KenKem/realtrace_<symbol>.csv` (+ trades CSV). I auto-collect.

## ▶ NEXT (me, once the trace is in)
Extend `diff_e5_valuediff.py` to read the 4 new columns: for each of the 42 onset-arming misses, read the EA's
`aligned@cur && !prev_aligned` to pin the EXACT bar the EA armed, diff vs the engine's B-2 onset, and port the
engine's `triggers.hpp` E5 onset to the EA's exact pairing (NOT a blind shift). Validate: 2026 recall RISES
AND 2025 stays matched (near-perfect now) AND fire-bar coupling holds (no overfire blow-up). The 42 misses
carry **+466 net** (representative of E5's +949), so success ≈ doubles E5's captured edge → enough sample to
revisit enabling E5 in the lock. If the port regresses 2025 or can't beat the 52.8% ceiling → accept ceiling,
E5 stays OFF, fall back to the surgical E2/chop sweep ([[kenkem-e5-2026-selection-break]], LOCK_EDGE_AUTOPSY).
