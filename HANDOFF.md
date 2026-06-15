# HANDOFF — read me first, update me last

_Last updated: 2026-06-15 by Claude (Opus 4.8). Branch `1-reorganize-code`._

## 🎯 Goal (user, restated 2026-06-15)
Make the **dquants tick backtest engines reproduce MT5 "Every tick based on real ticks" exactly** so the
engine can be trusted for parameter sweeps. **CRITICAL scope clarification:** ALL entry types **E1–E5**
must act identically across the original MQL5 EA and the dquants C++ engine — not just one entry.

## 📍 Where we are (per strategy)
| Strategy | Tick-engine parity vs MT5 | Notes |
|---|---|---|
| **MasterVP** | ✅ Validated (signal-exact; misses = MT5 iATR tick-jitter on a knife-edge gate) | Trustworthy for sweeps now |
| **Monster** | ✅ Zero-trade bug fixed (`*100` unit fix), engine matches oracle | |
| **KenKem** | 🔴 C++ inverts verdict (C++ PF 0.90 vs MT5 1.23, XAU/E5). Gap narrowed 394→218 vs MT5 136 | E5 only so far; E3 missing in C++ |

## ✅ What just changed this session (commits)
- **dquants `a4fe28a`** — Corrected a MIS-diagnosis: the "daily-DD predictive-vs-reactive parity bug"
  is NOT a bug. MT5 `IsDailyDDHit(ComputeRiskBudgetUSD())` is predictive too (RiskManager.mqh:142-147),
  byte-identical to `kk::common::risk_manager::is_daily_dd_hit`. **Do NOT flip it** — would break parity.
  The only real MasterVP/Monster divergence is the broker `tick_value≈0.1` glitch. See
  `research/kenkem_parity/MASTERVP_MONSTER_PARITY.md`.
- **kenkem `bbc3301`** — Built the EA-side **per-bar E5 decision trace**: `Parity/BarTrace.mqh` +
  `Entry5::TraceBar()` + 4 hooks in `KenKemExpert.mq5`. Emits the identical 61-col schema as the C++
  `cpp_core/tools/kenkem/trace_dumper`. Behind `InpExportBarTrace` (default off). **Compiles clean.**
- **dquants (uncommitted as of writing)** — added `InpExportBarTrace=true` to `parity_kenkem_{xau,btc}.set`;
  added RUN A / RUN B sections to `research/kenkem_parity/RUN_GUIDE_PARITY.md`; this HANDOFF.md +
  CLAUDE.md handoff mandate.

## ⛔ BLOCKED ON USER — two MT5 runs (see `research/kenkem_parity/RUN_GUIDE_PARITY.md` top)
- **RUN A**: KenKem XAUUSD-Exness-KK, M1, real ticks, `parity_kenkem_xau.set` → produces
  `trades_*.csv` + `trace_*.csv`. Unblocks the E5 field-by-field diff.
- **RUN B (path B, user chose)**: clean MasterVP + Monster reference on a correctly-configured XAU symbol
  (sane lot size, no blow-up) → validates the real strategy, replacing the broker-glitched "2426-Good" oracle.

## ▶️ NEXT ACTIONS (in order)
1. **(needs RUN A)** Diff EA `trace_*.csv` vs C++ `trace_xau_paritywin.csv` field-by-field. Hypothesis to
   test first: the EA's **ADX/session early-`return` at `Entry5.mqh:115-132` happens BEFORE trigger-onset
   tracking (153-188)** — so on low-ADX bars the EA skips updating `m_prevBullishAligned`, landing its
   onset on a different bar than the C++ (which evolves triggers every bar). Likely source of the ~3-min
   entry lag + extra longs. The trace will confirm/refute per-bar.
2. **(needs RUN B)** Re-diff MasterVP/Monster with `diff_aligned.py`; over-fire should largely close once
   sizing matches. Then add one-position-at-a-time concurrency to the monster engine.
3. **ALL-ENTRIES generalization (the user's real goal):** the C++ KenKem engine covers **E1/E2/E4/E5 but
   NOT E3** (entries.hpp: "First-match-wins E1→E2→E4" + E5). Both trace tools are **E5-only**. To validate
   all entries: (a) add **E3** to the C++ engine, (b) generalize the per-bar trace (C++ `trace_dumper` AND
   EA `BarTrace`/`TraceBar`) to emit per-entry gate columns for E1/E2/E3/E4, (c) parity-diff each entry.

## 🔑 Key facts / gotchas
- Python: use `~/miniforge3/envs/kenkem/bin/python` (NOT system python3, NOT `conda activate`).
- Compile MQL5 here: `bash scripts/compile_mql5.sh <abs path to .mq5>` (wine64 + MetaEditor).
- MT5 tester output: `kenkem/Tester/Agent-127.0.0.1-3000/MQL5/Files/<strategy>/`. Symbol is
  `XAUUSD-Exness-KK`, not plain XAUUSD. Confirm export inputs show `true` in the tester log.
- Adopt a toggle to a locked `.set` ONLY if **net↑ AND drawdown↓**; rank on 2026 OOS; report the 9-col table.
- Use the **tick engine**, never the bar engine, for any P&L claim (bar engine disagrees on sign).

## 📚 Durable plan & memory
`docs/BUILD-PLAN.md` (phase plan, keep ticking) · `~/.claude/.../memory/MEMORY.md` (cross-session facts) ·
`research/kenkem_parity/` (PARITY_RESULT_XAU.md, MASTERVP_MONSTER_PARITY.md, RUN_GUIDE_PARITY.md).
