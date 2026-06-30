# HANDOFF - read first, update last

Last updated: 2026-06-30 by Claude. Branch: `3-codex-handoff`.

## Current Goal
Harden the research/measurement spine so future locks are auditable, and find the next real lever on the two
live-profitable EAs (KenKem XAU M1 = D5-E4Long lock; MasterVP XAU M5 = ProgTrail-ladder lock).

## What Just Changed (2026-06-30 — MasterVP prod fix, code-touching)
- **FIXED the MasterVP XAU M5 equity/deposit-load spike** ("equity went up like crazy then crashed").
  Root cause from 2 user MT5 runs + the EA's own `trades_*.csv`: 6 trades on the **20:55 daily-rollover bar**
  (spread blown to 112–420 pips vs ~25 normal) had `riskPrice ≈ one spread`, collapsing the EA's post-clamp
  sizing `risk` → `KKPositionSize` exploded the lot ~12× (capped only by broker VOLUME_LIMIT). The C++ engine
  never showed it because it sizes on the clean `sig.risk` (~1.2×ATR).
  - Fix: `Inputs.mqh` +`InpMinRiskAtrMult=0.6`; `Engine.mqh` floors the SIZING distance at 0.6×ATR
    (`sizeRisk=max(risk,0.6*AtrAt(1))`) — **real sl/tp unchanged**, only the lot. EA recompiled 0/0.
  - Mirrored 1:1 into C++ (`config.hpp min_risk_atr_mult=0.6` + both `mastervp/tick_engine.hpp` compute_lot
    sites) — **guaranteed no-op** (min engine slAtr=0.7>0.6); all C++ tests pass, deterministic.
  - Impact: only those 6 trades change (losses −547→~−177, book +21,650→~+22,020); 1,541 healthy trades
    byte-identical; spikes gone. Memory: `mastervp-sizing-risk-floor-fix`.
  - User MT5 re-run CONFIRMED spikes gone.
- **Prop "flat tail" diagnosed + RECOVERY MODE wired (.set only).** After the sizing fix the XAU M5 **prop**
  run stopped trading 2025-08-26 (flat ~9 mo). Cause: `IsPeakDDHalt` (`InpMaxPeakDDPct=9.0`) is a one-way trap
  (monotonic `g_peakEquity`; halted → no trades → can't recover). It fired on a ~9% equity DD from the 2025-08-13
  peak (real winners, not a sizing artifact) — a NORMAL DD (full-year natural ~27.7%) that exceeds the FundedNext
  9% limit at 0.5% risk. NOT a sizing bug. Fix (operator-set, FN ~10% firm limit): `InpSoftBlockDDPct=8.3`
  `InpSoftBlockLotMult=0.5` (HALF risk at the cliff, auto-resets when DD<8.3%) + `InpMaxPeakDDPct→9.5` + explicit
  `InpMinRiskAtrMult=0.6`, on both `releases/1.07/*-prop.set` + `release.conf` (commit 832e9f0). **NEXT = user MT5
  re-run of the XAU M5 prop set.** Flagged concern: 8.3→9.5 is a narrow 1.2% band (soft-block only de-risks the
  final approach); Aug-2025 reached ~9.5% DD so it may still halt — fallback = lower the trigger / trim base risk.

## What Just Changed (overnight autopilot, 4 parallel research-only agents)
- **Snapshot of Codex's 8-step handoff committed** (`78187ba`) — was previously uncommitted.
- **R6 / exit-model calibration — PARTIAL** (`ab614d9`): `research/mastervp_parity/EXIT_MODEL_CALIBRATION.md` +
  `exit_model_calibration.py`. Engine over-credits MasterVP XAU M5 exits ~30% on matched 2026-OOS trades
  (runner/TP 27–32%, winner gross 13.6%, exit-only net +31%). Matched mfeR ~identical → gap is exit-FILL
  placement, not data/entry. Policy: haircut runner P&L 30% / winner gross 15%; engine exit gains ≤0.015 PF = noise;
  exit-geometry ranking still needs MT5.
- **K2 / KenKem entry-role audit — DONE** (`c65d099`): `research/kenkem_parity/KENKEM_ENTRY_ROLE_AUDIT.md` +
  `kenkem_entry_role_audit.py`. Only **E2** is a late trigger (mfeR 0.59, 30% stillborn, 43% EA-bail). E1/E4
  lagging crosses leave the MOST room (lateness hypothesis did NOT generalize — honest partial-negative).
- **R3 / experiment registry — DONE** (`c6a95f8`): `research/registry/` (registry.py + SCHEMA + README +
  15 back-filled experiments + index.csv). validate 15/15, idempotent. Future runs MUST `append_row()`.
- **R2 / indicator lag & redundancy — DONE** (`0faa63c`): `research/data_quality/INDICATOR_LAG_REDUNDANCY_AUDIT.md`
  (+ built the missing XAU M1 feature/label stack, 849,963 bars). Nested WF OOS R² increment flat-to-negative for
  EVERY family → EMA/RSI/DMI/ADX are state variables, not standalone alpha. ADX = no directional value.
- BUILD-PLAN ticked: R2 [x], R3 [x], K2 [x], R6 [~].
- **Quant-literature digest (Chan 2nd ed + Peng Liu) → plan + tooling upgrade** (commits 7d4ef03, b1209d2):
  - Digest: `docs/QUANT-LITERATURE-SYNTHESIS-2026-06-29.md` (technique-by-technique, skeptical; dquants already ahead
    on overfitting stats so mined for what we lacked).
  - New research tools (self-tested, no EA touch): `research/risk/kelly_sizing.py` (empirical fat-tail-safe Kelly +
    risk-of-ruin) and `research/stats/half_life.py` (OU half-life for mean-reversion timing).
  - Live sizing finding: KenKem XAU M1 half-Kelly 0.087 carries **44% risk-of-ruin(50% DD)** → size ~1–2%/trade.
  - BUILD-PLAN: +Operating Doctrine #9 (Kelly sizing) & #10 (regime-conditioned exits); P1 OU half-life regime;
    P3 empirical Kelly; M4 metalabeling; K6 CPO; K4/M6 regime-conditioned stop + half-life timing; R9 (new) worst-fold
    BO sweep objective; G4 Calmar + recent-weighting. All gated; nothing locks without DSR/PSR/MinTRL + MT5.

## Current Blocker (what stops the next step, and on whom)
- **maeR is unmeasured.** The C++ trade export populates `maeR` as 0.00, so K2's lateness call is favorable-side
  only, and R6's haircut can't be tightened on the adverse side. This is the single highest-leverage infra fix.
- **R6 full close needs a full-window MT5 per-trade export** (KK-MasterVP XAU M5, 2025.06.01→2026.05.29, lock
  `.set`, `InpExportParity=true`) — a *user MT5 run*. Until then haircuts are a documented lower bound.
- Product release blocker remains user MT5 visual spot-check for `KK-MasterVP-Profiler` on XAU M5 (P0.1).

## Exact Next Action
1. **Infra (no EA risk):** populate `maeR` (and richer exit fields) in the C++ engine trade export, regenerate the
   canonical streams via `research/tools/normalize_trades.py`, then re-run K2's adverse-side check. Unblocks K2 + R6.
2. **EA lead (default-OFF scratch branch only):** scaffold `E2_REQUIRE_REJECTION` — replace one lagging HTF
   require-aligned on E2 with a price-structural reject/reclaim fire on the EMA75 touch bar. Then gate + per-quarter
   before it can ever be a candidate. NOT yet scaffolded this session (held pending maeR + user sign-off; see below).
3. **MT5 ask for the user:** the R6 full-window export above.
4. **From the quant-lit digest (highest-value, gated):** (a) compute per-stream empirical Kelly/RoR and set live size
   at the drawdown-capped fraction (P3); (b) build the P1 regime label (OU half-life) and re-test exits *conditioned
   on regime* (K4/M6) — this is the most promising reframe of the MasterVP giveback-stop rejections.

## Decisions To Preserve
- All four overnight items are research-only; released `.ex5`/`.set` are byte-identical (verified each commit).
- Engine MasterVP exit-side wins are now quantitatively discounted (~30%), not just caveated — apply the R6 haircut
  to any future engine exit claim before believing it.
- KenKem E1/E4 triggers are sound; E2 is the only redesign candidate, and only on provisional (favorable-side)
  evidence until maeR exists. Do NOT touch the KenKem EA from current evidence.
- EMA/RSI/DMI/ADX may stay as state/regime filters only; none may be the sole basis for an entry/SL/target (R2).
- Every future sweep/backtest/MT5 run writes a `research/registry/` row (R3).
- Per user (this session): if a finding warrants an EA change, scaffold it DEFAULT-OFF on a scratch branch, never
  the lock, never merged.
