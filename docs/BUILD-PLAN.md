# KenKem Quant OS — Build Plan &amp; Progress Tracker

Living checklist. Source of truth = MQL5 (kenkem/MQL5/Experts/). Pipeline rules = research/PIPELINE-CONTRACT.md.Each step: build → make -C cpp_core test → commit → push. Legend: [x] done · [~] in progress · [ ] todo.

Completed phases are archived in BUILD_PLAN_ARCHIVED.md: data pipeline (Phase1–5), Phase 6, Phase 7 (MasterVP tick engine + parity), Phase 8 (optimization), Phase 9 (light WFA/MC),Phase 11 (MasterVP-Monster), Phase 12 (real-Monster engine), Phase 13 (KenKem engine), R&amp;D F1/F2/DeferredEntry,ProfitManager round-1. This file tracks only live + deferred work.

## 🎯 The one goal

Mode: autopilot



Make the dquants tick engines reproduce MT5 “every tick” exactly, then run trustworthy sweeps to rank aproduction candidate that ≥ the user’s original KenKemExpert version 1.8.154 (not exactly proven to be optimal due to the lack of automated testing).



