# PF1 Step 1 — Profiler ↔ EA DELTA AUDIT (2026-06-27)

**Goal of PF1:** the KK-MasterVP-Profiler indicator must show the entry/exit/verdict on the
EXACT candle, with the EXACT outcome, that the **released** KK-MasterVP EA executes. It may
NEVER display one thing while the EA does another.

## 🔴 HEADLINE FINDING — the single-source EA-twin was REVERTED; the released Profiler is the loose standalone scout

Memory [[mastervp-profiler-indicator-parity]] and BUILD-PLAN PF1 both assert "entries already
route through shared `Decision.mqh`." **This is FALSE in the current/released code.** Git history:

| Commit | What it did |
|---|---|
| `a5e2f66` | indicator(A): added shared `Decision.mqh`, behaviour-neutral Engine refactor |
| `9d4ea91` | indicator(B): Profiler **rebuilt as the EA twin** (includes shared stack, calls `MVP_DetectSignal`+`MVP_DeterministicGatesPass`, exact-candle parity) |
| **`32cea71`** | **profiler: "restore standalone original"** — *overwrote the gutted EA-twin with the kenkem standalone original* (+2109 lines). **THIS REVERTED Phase B.** |
| `1fb0421`…`47f1e6c` | further work + **market release 1.01** — all on the standalone scout |

The revert message: *"Overwrote the **gutted** EA-twin with the **kenkem standalone original**."*
The EA-twin had exact parity but lost the rich cockpit (histogram, hybrid tick-delta tint,
DPI-aware auto-size panel). The standalone was restored for visuals, accepting looser parity.

**Net:** the released Profiler 1.01 = the standalone scout that its OWN `CLAUDE.md` says it
replaced. Confirmed directly:
- `KK-MasterVP-Profiler.mq5:72` — only `#include`s `AccountLock.mqh`. Does NOT include
  `Decision.mqh` / `Strategy.mqh` / `Inputs.mqh` / `SessionNews.mqh`.
- grep for `MVP_DetectSignal` / `MVP_DeterministicGatesPass` / `SN_UpdateSession` in the
  `.mq5` → **zero hits**. Entry detection is a standalone, stateless `RescanSetups()` (line 1913).

## Concrete divergence checklist (current released Profiler vs released EA lock)

### A. ENTRY DETECTION — `RescanSetups()` (`.mq5:1913–2025`) vs EA `MVP_DetectSignal` (`Strategy.mqh:16–164`)
- [ ] **Breakout-only.** Profiler detects only an edge-clear breakout + near-price net ≥ `InpSetNetMin`(0.80).
      EA also has reversion (`InpEnableReversion` — OFF in lock, so OK) + impulse + extreme-rev (OFF). For the
      locked breakout-only config the entry *family* matches, but the **gate stack does not** (below).
- [ ] **No deterministic gate stack.** Profiler applies only single-position + net-confirm. EA applies
      `MVP_DeterministicGatesPass` (`Decision.mqh:63–76`): quality(MTF/RSI, OFF), **session≠0**, ATR%
      band (OFF), **ATR-ticks floor**, **blocked-hour veto**, news veto (OFF). → Profiler marks entries
      in blocked UTC hours (4,16,17) and outside Asia/London/NY sessions that the EA rejects.
- [ ] **No max-trades/session.** EA gates `SN_MaxTradesOk()` (`InpMaxTradesPerSession`); Profiler has only
      a single-open-setup rule.
- [ ] **Entry buffer param mismatch:** EA `InpBreakBufAtr` vs Profiler `InpSetEntryBufAtr`; values not
      guaranteed equal (Profiler has its own `InpSet*` schema, not driven by the EA `.set`).

### B. EXIT REPLAY — `RescanSetups()` forward loop (`.mq5:1997–2011`) vs EA `ProfitManager.mqh`+`Engine.mqh`
- [ ] **🔴 NO ProgTrail ladder.** EA lock runs `InpPmProgTrail=true`, Trigger 2.0R / Increment 0.75R /
      Step 0.20R (`Inputs.mqh:178–181`; logic `ProfitManager.mqh:67–74`). Profiler exit replay does only
      TP1 → a single BE ratchet at `InpSetBeTrigR`(0.3R) → SL. The whole post-2.0R ratchet that defines
      the current lock is absent → WON/LOST/BE verdict + drawn stop path diverge.
- [ ] **🔴 NO ATR chandelier trail.** EA trails at `InpTrailAtrMult`=2.75 after TP1 (`Engine.mqh:495–508`);
      Profiler has no trail at all.
- [ ] **Runner cap absent.** EA `InpRunnerRr`=4.0; Profiler uses `InpSetTp2R`(1.8R) as a hard target.
- [ ] **BE buffer value differs:** EA `InpBeBufAtr`=0.02 vs Profiler `InpSetBeBufAtr`=0.05.
- [ ] **BE semantics trap:** Profiler "BE" = SL hit after its 0.3R ratchet; EA BE = `InpBeAfterTp1` after TP1.
      Different events → same label.

### C. SESSION / TIME — EA `SessionNews.mqh` vs Profiler
- [ ] **No session/blocked-hour replay.** EA: UTC auto-offset, Asia 21–03 / London 03–11 / NY 14–21 UTC,
      blocked hours 4/16/17, day-roll UTC 00:00. Profiler draws blocked-hour shading but does NOT gate
      entries on session or blocked hours.

### D. Verdict computation — Profiler tags (`.mq5:2078–2085`) are computed from the simplified exit (B),
      so they inherit every exit divergence above. Not independently wrong, but not the EA's realized outcome.

## Implication for Steps 2–3

The BUILD-PLAN's premise ("entries already route through shared `Decision.mqh`; the exit path is the
only gap") is **wrong** — BOTH the entry path and the exit path are standalone reimplementations now.
Bringing this to true parity is the full Phase-A/B single-source rebuild again (which was reverted once
for visual reasons), NOT a small exit patch.

## ✅ RESOLUTION (2026-06-27) — user chose: graft shared EA logic onto the rich shell, indicator-only

Steps 2–3 DONE (indicator file only; EA untouched, still compiles 0/0):
- **Symbol declash:** renamed the standalone's private `VPResult`/`NodeState` → `VizVP`/`VizNodeState`
  and its display copies of `InpVpBins`/`InpVpLookback`/`InpMasterMult`/`InpVaPct`/`InpAtrLen`/`InpNode*`/
  `InpSlAtrBrk`/`InpBreakBufAtr`/`InpBreakMaxAtr`/`InpTfNetLook` → `InpViz*`, so the included EA stack
  (`Types/VolumeProfile/Regime/NodeEngine` + `Inputs/Strategy/Decision/SessionNews`) owns the
  authoritative symbols.
- **Single-source replay:** `RescanSetups` REWRITTEN as the EA-exact replay — `MVP_DetectSignal` +
  `MVP_DeterministicGatesPass` + pure-UTC `SN_UpdateSession`/`SN_IsBlockedHour`/`SN_InNewsWindow` +
  one-position + `SN_MaxTradesOk`, shift map = Engine.mqh OnNewBar (fill at open[b], entry=close[b-1]).
- **Exit faithful to the lock:** TP1 → BE-after-TP1 → ATR chandelier trail (2.75) → **ProgTrail late-arm
  ladder** (Trigger 2.0R / Inc 0.75R / Step 0.2R, peak-R bar equivalent) → runner cap (RunnerRr 4.0).
  Verdict by **realized exit R** (WON/LOST/BE) — fixes the twin's stale "WON at TP1 touch" (lock banks 0%
  at TP1). Laddered stop path drawn (`InpVizShowTrailPath`).
- **Rich cockpit preserved:** histogram, hybrid tick-delta, exec-health, net telemetry, projection,
  EMA ribbon, auto-size panel all unchanged — they're display context, not EA-behaviour claims.
- **Account-lock:** indicator's own `ALLOWED_ACCOUNT_*`/`ACCESS_EXPIRY` removed (now from Inputs.mqh,
  avoids double-def). ⚠ deploy follow-up: point the per-account Profiler bake at the shared lock file.
- Compiles **0 errors / 0 warnings**. EA recompiles 0/0 (proves untouched).

**▶ REMAINING = Step 4(ii) user MT5 visual spot-check** (cannot run headless): attach the indicator on
XAU M5 with the EA lock `.set`, confirm entry markers land on the EA backtest's entry candles and the
WON/LOST/BE verdict + stop path match a sample of realized trades. Known un-reproducible-from-chart:
predictive daily-DD (`IsDailyDDHit`, needs live equity) — documented, not chased.
