# ⭐ UPDATE 2026-06-17 (later) — trigger expire-then-rearm FIXED → 3/9; wall is now E1 over-fire + skip rules

The "1–11 bars early / trigger timing" framing below was **incomplete**. After forming-accel the engine
fired a *largely different set* than the EA, so I re-diagnosed from the EA `trades.csv` (which is a full
DETECTION log: 108 candidates, `Status=SKIPPED_*` for rejects, only 9 executed). Findings:

**Root cause of the E4 misses = trigger expire-then-rearm was missing.** Proven with the trace_dumper
(now dumps `tenkanM3,kijunM3,ichiup_age,ichidn_age`): at 02.18, the engine's combined M1∧M3 cloud crosses
up FRESH at 01:09 / 01:35 / **02:02**, but `st.ichi_up` stayed pinned at the 00:36 cross (age climbed to
94) because the distilled `detect_entry` only `continue`d on a stale trigger — it never reset it to −1.
The EA (`Entry1.mqh:103-109`, `Entry2.mqh:102-147`, `Entry4.mqh:106-108`) **resets `lastX=-1` on age
expiry**, so a later re-cross re-arms. Ported that reset (E1/E2/E4; E5 re-arms on alignment onset, left).
**Effect: 02.18 02:10 L-E4 now fires EXACT (4899.99) → match 2/9 → 3/9, PF 0.04 → 0.49, all 28 tests green.**

**The remaining gap is now cleanly classified (engine 20 trades vs EA 9, 3 match):**
- **11 PHANTOMS, ALL E1** (EA never detected at that bar): 02.04 14:43, 02.05 09:15, 02.10 09:12/14:20,
  02.12 06:37/15:00, 02.13 14:50, 02.26 05:15/08:34/13:37, 02.27 05:30. ⇒ the E1 EMA-cross trigger/gate
  OVER-DETECTS. **Biggest lever now.** Prime suspects: B2 EMA-stack gate shift (`emas_ready_entry` reads
  align.tf−3 vs verified −2), and/or the E1 EMA-cross trigger `emas_ready` shift / HTF block-counter.
- **6 EA-SKIPPED** (engine executes what the EA detected then SKIPPED): 02.06 14:40 L-E1, 02.16 12:16 S-E4,
  02.19 00:04 S-E4, 02.20 01:01 L-E4, 02.20 13:47 L-E1, 02.25 09:08 S-E4. ⇒ missing skip rules (the
  DEFERRED limiters in risk_exec.hpp: daily/DD room, consec-loss block, etc.). Note the skipped S-E4s
  pre-empt nothing now, but 02.16 12:16 S-E4 (phantom) still suppresses the real 02.16 13:29 S-E1.
- **6 EA-executed MISSED**: 02.04 07:45 / 02.09 14:32 L-E1, 02.16 13:29 S-E1 (E1 — blocked by phantoms /
  skip), 02.06 12:07 / 02.16 09:02 L-E4, 02.23 07:38 S-E4 (E4 — no fresh re-cross armed before the EA bar,
  or a gate edge; revisit after E1 over-fire is fixed since phantoms occupy slots).

### ▶️ NEXT (resume here, priority): 1) E1 phantom over-detection (B2 EMA shift + E1 trigger/HTF). 2) skip
rules (port deferred limiters). 3) re-check the 3 remaining E4 misses once slots aren't occupied by phantoms.
Repro of the cloud/age diagnosis: `build/kenkem/trace_dumper ... ` then compare engine `tenkanM3>kijunM3`
& `ichiup_age` vs EA `senkouA_m3>senkouB_m3` (EA trace cols are buffer-SWAPPED: its `tenkan/kijun`=M3 Senkou
buf2/3, its `senkouA_m3/senkouB_m3`=M3 real Tenkan/Kijun buf0/1 = the actual cloud-cross inputs).

---
# 1.8.154 parity — post-routing diagnosis (the wall is detection TIMING, not limiters)

_2026-06-17 (Opus 4.8). Follow-on to `PARITY_1.8.154_DETECTION_DIAGNOSIS.md` and
`CPP_VS_MQL_FAITHFULNESS_AUDIT.md`, after committing the execute-stage risk routing (commit `976fb34`)._

## What landed (commit 976fb34) — D1 high-risk routing + B1 ATR-stage + faithful lot
The distilled tick engine never had the EA's EXECUTE stage; it opened every detected+ATR-passing trade
with risk-based lots. Now ported faithfully (`cpp_core/include/kk/kenkem/risk_exec.hpp`):
- **Faithful lot** = `min(maxLotsBasedOnRisk, marginCap, scaledLot=std-lot×profit-scale)`, normalized.
  Confirmed vs the MT5 ledger (lot ≈ 0.15 std; high-risk resize to `maxLoss×0.98` ⇒ e.g. 0.12).
- **B1**: ATR-percentile / ATR-high gate moved OUT of per-candidate detection and applied ONCE at execute
  on the single detected candidate (a detected-but-ATR-blocked type still consumes the bar slot).
- **D1**: `potentialLossUSD >= getMaxLossUSD(type)` ⇒ high-risk path (accept flag, MAX_HIGH_RISK/session,
  sideway-warning veto, CheckMomentumForLevel, lot resize, session TP shrink); else normal path
  (opposing-dir + GetEntryBlockReason ATR subset). Min-seconds(60) + per-session high-risk counter tracked.

**Effect on the Feb-2026 XAU anchor:** 45 trades → **19** (E1 18→6, E2 13→6, E4 14→7). All 28 C++ tests pass.

## The match did NOT improve (1/9 → 0/9) — and we now know exactly why
| Probe (anchor, Feb window) | trades | exact-bar match /9 |
|---|---|---|
| baseline (pre-routing) | 45 | 1/9 |
| + routing (this commit) | 19 | 0/9 |
| + routing + **offset-0 atr_pctile ORACLE** | 16 | **0/9** |
| + routing + oracle + **max_concurrent=20** | 16 | **0/9** |

Three things are now RULED OUT as the parity blocker:
1. **atr_pctile** — feeding MT5's exact per-bar percentile (join is **offset 0**: engine `bar.ts_ms` ==
   MT5 trace `ts_ms`; all 9 EA bars then sit in [65,90] and pass) still gives 0/9. The engine's own
   percentile IS wrong at 4 bars (46.9/62.5/96.9/21.9 vs MT5 68–88) but correcting it doesn't unlock them.
2. **max-concurrent crowding** — raising the cap to 20 changes nothing (still 16 trades, 0/9). Slots are
   not the constraint.
3. **the limiters** (session-loss/SLTP/min-seconds) — they bind rarely on this window.

## ROOT CAUSE: the engine fires the right type+direction 1–11 bars TOO EARLY
The 16 engine trades vs the 9 EA trades, lined up in time, show the engine pre-empting the EA's bar:

| engine fire | EA fire | gap | mechanism |
|---|---|---|---|
| 02.17 **13:18** S-E4 | 02.17 **13:20** S-E4 | −2 bars, SAME type | engine consumes the ichi_down trigger 2 bars early ⇒ EA's 13:20 bar has no armed trigger ⇒ empty |
| 02.16 **13:18** S-E4 | 02.16 **13:29** S-E1 | −11 bars | early S-E4 opens a short; the real S-E1 is a different trigger but the early fire shifts state |
| 02.04 **07:44** L-E2 | 02.04 **07:45** L-E1 | −1 bar | engine detects L-E2 one bar before the EA's L-E1 |

The `entry_trace` gate dump confirms the gates PASS at the EA bars (e.g. 02.16 13:29 E1S PASS, 02.17 13:20
E4S PASS, tq ok), but in the live run the **trigger was already consumed / an opposite-dir position is
already open** from the early phantom fire. So this is NOT an over-fire of *extra* trades crowding via
slots — it is the *same* trade detected at the *wrong (earlier) bar*, which then blocks the EA's bar via
(a) trigger consumption (one cross → one entry) and (b) HasOpposingDirectionPosition.

### Why early? — forming-vs-closed bar reads (the C1 axis), plus trigger timing
The gate inputs cross their thresholds one-or-more bars earlier in the engine because acceleration / HTF
ADX / trend-quality are read on CLOSED bars while the EA reads the FORMING bar (shift 0). Direct evidence
at the two pure tq misses (gates, not timing): **02.17 03:28 S-E4 tq=8 vs needed 9** and **02.23 07:38
S-E4 tq=8 vs 9** — the documented 1-point acceleration gap (audit C1). The same forming/closed skew makes
*other* bars cross early. The ichi/EMA-cross TRIGGER timing (audit B3) compounds it.

## The 9 EA bars, decomposed (engine behaviour after routing + correct atr_pctile)
| EA bar | type | engine gate at that bar | true blocker |
|---|---|---|---|
| 02.04 07:45 | L-E1 | E1L gate ok | engine fired L-E2 at 07:44 (−1) |
| 02.06 12:07 | L-E4 | tq ok | early/again no armed trigger at the bar |
| 02.09 14:32 | L-E1 | tq ok | engine's own atr_pctile wrong (96.9) — oracle fixes ATR but bar still pre-empted |
| 02.16 09:02 | L-E4 | tq ok | atr_pctile wrong (21.9) + timing |
| 02.16 13:29 | S-E1 | **E1S PASS** | pre-empted by early 13:18 S-E4 (trigger/opposite) |
| 02.17 03:28 | S-E4 | **tq=8<9** | C1 forming-accel (pure detection miss) |
| 02.17 13:20 | S-E4 | **E4S PASS** | ichi_down trigger consumed by 13:18 S-E4 (−2) |
| 02.18 02:10 | L-E4 | E4L gate ok, age 94 | ichi-cross age / trigger timing |
| 02.23 07:38 | S-E4 | **tq=8<9** | C1 forming-accel (pure detection miss) |

## ▶️ NEXT ACTIONS (resume here) — detection-input fidelity, in priority order
1. **C1 forming-bar acceleration** for trend-quality + conviction + the high-risk E1-accel momentum.
   Aggregate the M1 bars in the current M3/M5 bucket up to decision time into a FORMING HTF bar and feed
   {forming, closed-1, closed-2} to `kk_trend_accel` / `kk_adx_accel` (reuse `kk::ind::dmi_adx_mt5_form`).
   Directly recovers 02.17 03:28 + 02.23 07:38 (tq 8→9) and should re-time many early fires.
2. **Trigger timing (B3)**: the ichi-cross / EMA75-touch / EMA-cross triggers fire on closed-bar reads;
   align them to the EA's forming-bar evaluation so the cross is detected on the SAME bar (kills the −1/−2
   early fires that consume the trigger before the EA's bar, e.g. 02.17 13:18 vs 13:20).
3. **EMA-stack gate shift (B2)**: `emas_ready_entry` reads align.tf−3; the verified snapshot value is
   align.tf−2 (`GetEMA(...,1)`). One bar too old near crossovers.
4. **atr_pctile production fidelity** (for non-oracle runs): the engine percentile (forming `s.atrM1`)
   diverges from MT5's intra-bar `cache.atrM1`. Not the parity blocker (oracle-proven), but wrong on ~4
   bars; revisit only after 1–3, and only if production ATR-regime selectivity matters.

## Repro
- Engine: `cd cpp_core && ./build/kenkem/tick_backtester --bars-m1 tools/bars_xauusd_2026_m1.csv --ticks
  tools/ticks_xauusd_2026_window.csv --symbol-xau --set ../research/kenkem_parity/anchor_1.8.154.set
  --from-ms 1769889600000 --to-ms 1772337600000 --out <o>` (`--pctile-oracle /tmp/oracle0.csv` to add the
  ATR oracle; build oracle0 = `ts_ms,atr_pctile` straight from `parity_trace.csv`, **offset 0**).
- Gate dump: `./build/kenkem/entry_trace --bars-m1 ... --only <ts_ms,...> --out <o>` (NOTE: its
  `gate_reason` still has a STALE in-dumper ATR check → `atr_lo/atr_hi` labels are a red herring post-B1).
- Ground truth: `mt5_runs/RUN_2026-06-17_1.8.154_xau_feb/{trades,parity_trace}.csv` (9 executed = E1×3,E4×6).
