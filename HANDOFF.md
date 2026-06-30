# HANDOFF - read first, update last

Last updated: 2026-07-01 by Claude. Branch: `3-codex-handoff`.

## Current Goal
Harden the research/measurement spine so future locks are auditable, and find the next real lever on the two
live-profitable EAs (KenKem XAU M1 = D5-E4Long lock; MasterVP XAU M5 = ProgTrail-ladder lock).

## What Just Changed (2026-07-01 — FundedNext daily-DD fact correction, docs only)
- **Canonicalized FN Stellar-2 daily-DD = 5% (NOT 3%); EA single-prop cap = 4.4% (deliberate ~0.6%
  margin).** The "3%" scattered through CLAUDE.md + risk skills was a stale internal-buffer number
  mis-stated as the FIRM limit; the FN plan doc (`kenkem/notes/PropTrade_FundedNext_Stellar2_Plan.md`)
  itself confirms "Daily Max Loss 5%". Corrected across 3 repos:
  - **dquants:** `docs/BUSINESS-PLAN.md` (blocker → resolved); memory `fundednext-stella2-portfolio.md`
    (added canonical 5%-firm / 4.4%-EA fact).
  - **kenkem:** `pineScript/CLAUDE.md`, `notes/{PropTrade_FundedNext_Stellar2_Plan, kenkem-plan-sl-management-pf25,
    KK-MasterVP-Top1Percent-Profitability-Plan, KK-MasterVP-Monster-EA-Port-Plan}.md` (firm 3%→5%, EA cap 0.03→0.044).
  - **kenkem-pine:** `CLAUDE.md` (×2) + skills `risk-audit` / `bt-data-science` / `pine-quant-review` (firm 3%→5%).
  - DELIBERATELY LEFT: two `kenkem-pine/baselines/*tune-2026-05-09*.md` (frozen historical tuning records).
  - Mixed-portfolio per-leg caps (≈4.2%) untouched — they're intentionally tighter (legs share the 5% budget).
  - Verified: no operational "FundedNext 3%" reference remains. No code/.set changed (the prop .sets already use 4.4%).

## What Just Changed (2026-07-01 — STANDALONE RISK-TIERED .sets, release-config only)
- **New retail risk tiers shipped for BOTH EAs: `-conservative` + `-balanced` standalone (no prop / no
  mix) .sets.** Motivation: operator's as-swept MasterVP XAU personal lock (1% RPT / 10% daily DD /
  soft-block OFF) gave ~11X/yr but swings 10% intraday. These tiers tame drawdown for personal accounts.
  - **MasterVP (XAU+BTC M5, true %-risk):** Conservative = `InpRiskAccPct=0.5 InpMaxDailyDDPct=4.0
    InpSoftBlockDDPct=5.0 InpSoftBlockLotMult=0.5 InpMaxPeakDDPct=8.0`; Balanced = `0.75 / 5.0 / 6.0 /
    0.5 / 10.0`. Deliberately NO `InpPropBaselineEquity` (standalone, not a prop anchor).
  - **KenKem (XAU M1, FIXED-lot ~0.06%/trade):** DD-caps ONLY, base lot `MY_STANDARD_LOT_SIZE=0.15`
    UNCHANGED. Conservative = `MAX_DAILY_LOSS_RATIO=0.04 ACCOUNT_DRAWDOWN_RATIO_TO_SLOWDOWN=0.05
    ACCOUNT_DD_RATIO_TO_SOFT_BLOCK=0.08 SOFT_BLOCK_LOT_MULTIPLIER=0.5`; Balanced = `0.05 / 0.06 / 0.10
    / 0.5`. `MADE_FOR_PROP_TRADING=false` kept → soft-block DE-RISKS (no hard halt). NO prop baseline.
  - Mechanism: added variants to each `release.conf`; re-cut releases IN PLACE (`--no-compile
    --set-version 1.08 / 1.04`, no bump → curated **market editions untouched**); added the 6 files to
    `make_prop_portfolio.sh` COMPONENTS + a "Mode A-Tiered" table in PORTFOLIO.md; rebuilt bundle v1.0.
  - VERIFIED every generated value by grep; as-swept personal sets uncontaminated (still 1%/10%/off).
  - Est. compounding vs 11X (edge fixed, geometric): Conservative ~3.3X, Balanced ~6X, ~½/¾ the DD.
    **UNTESTED in MT5** — operator should backtest before trusting (per release-ask-version-bump rule).
  - Files: `mql5/experts/{KK-MasterVP/releases/1.08, KK-KenKem/releases/1.04, prop-releases/1.0}/…`.

## What Just Changed (2026-06-30 — MIXED PROP PORTFOLIO release, code-touching)
- **Mixed FN-Stella2 portfolio shipped: MasterVP 1.08 + KenKem 1.04 + portfolio bundle v1.0.**
  One $100K account = MasterVP XAU M5 (0.43%) + MasterVP BTC M5 (0.15%, NEW `btcusd-m5-mixed-fn`
  leg) + KenKem XAU M1 (0.1%). Joint DD caps (both EAs, shared equity HWM): daily 4.2% /
  soft-derisk 7.8% / hard-halt 9.2%. KenKem mixed: `MADE_FOR_PROP_TRADING=true` (its soft-block
  threshold = hard halt, so `ACCOUNT_DD_RATIO_TO_SOFT_BLOCK=0.092` IS the 9.2% halt; slowdown
  0.078 = 7.8% de-risk), `ENABLE_PEAK_BALANCE_DECAY=false`, `USE_EQUITY_DD_BASIS=true`.
- **NEW contract-baseline DD anchor (commit 7bfd8de)** — `InpPropBaselineEquity` (MasterVP) /
  `PROP_BASELINE_EQUITY` (KenKem), LIVE-only, baked **100000** into all prop+mixed .sets. Fixes the
  fresh-attach trap: both EAs used to seed the overall-DD HWM to CURRENT equity, so a drawn-down
  prop account read as 0% DD and got a fresh allowance → breach risk. Now DD measures from the
  contract baseline with NO manual file-seeding. Tester-skipped → backtests byte-unchanged.
- **KenKem equity-basis A/B DONE + flipped ON** (commits eddb66a/6153e9e): A(balance) +8.01% vs
  B(equity) +7.63%; −0.38%/yr buys firm-rule-aligned DD measure. Equity basis ON in prop+mixed.
- **Portfolio bundler** `scripts/make_prop_portfolio.sh <ver>` → `mql5/experts/prop-releases/<ver>/`
  now bundles ALL THREE profiles (personal / individual-prop / mixed) for both EAs + PORTFOLIO.md.
  Ran for **v1.0** (12 files). Bump the portfolio version whenever a component bumps. Commits
  7bfd8de (anchor) → c6ae9a5 (3-profile bundle). Memory: `prop-account-state-persistence`.

## Sizing reality + DAILY-anchor gap (verified from code, 2026-06-30 — answered user, NOT yet fixed)
- **KenKem sizes off a FIXED base lot, not %-risk.** `KK-KenKem.mq5:1639` lot = `min(getScaledLotSize()
  [base=MY_STANDARD_LOT_SIZE=0.15 × growth/recovery mults], GetMaxLotSize() [Helpers.mqh:122 = a loose
  MARGIN ceiling ~90+ lots, NOT an SL-distance risk cap])`. So on a large ($94K) account 0.15 wins →
  ~$45–75 risk ≈ **0.05–0.08%/trade** (BELOW the 0.1% target; `COMMON_MAX_RISK_PER_TRADE` barely binds
  at this account size — `MY_STANDARD_LOT_SIZE` is the real lever). Safe/conservative, just light.
  Contrast: **MasterVP IS true %-risk** (`KKPositionSize`, 0.43% XAU / 0.15% BTC). `INITIAL_ACCOUNT_BALANCE`
  auto-detects (KK-KenKem.mq5:101-103) so KenKem risk scales to the live account.
- **OVERALL DD is protected** by the baseline anchor (halt 9.2% = $90,800 > FN $90K floor). **DAILY DD is the
  open gap:** on a fresh/mid-day attach both EAs anchor "day start" to ATTACH TIME (no persisted daily
  start), so they can't see FN's midnight reset — a mid-day start after intraday losses can allow more
  daily loss than FN permits. Backstopped by the overall halt UNLESS FN's daily floor today sits above
  $90,800. Told user: don't trade the rest of a bad day, start fresh tomorrow (anchors align).
- **PROPOSED FIX (user asked, awaiting go):** persist/restore the true daily-start equity (and/or an input
  for FN's day-start) so a mid-day attach measures daily DD from FN's reset, not attach time. PropState
  already has `dayStartEquity`/`dayKey` fields — wire OnInit to adopt them when same FN-day, else reseed.

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
  `InpMinRiskAtrMult=0.6`, on both `releases/1.07/*-prop.set` + `release.conf` (commit 832e9f0).
- **MT5 validation (8.3/9.5): STILL HALTS Aug-2025.** Soft-block works (tail losses halved ~−63→−31) but the 1.2%
  band is too narrow; even at 0.5× ~6 more losses cross to 9.5%. At 0.5% risk the strategy's natural DD exceeds 9.5%.
  → DECISION PENDING: engage soft-block earlier (~5-6%) or trim base risk 0.5→0.3%.
- **Release 1.07 rebuilt in place** (commit f04443d) — all modes (personal/prop/mixed) + Market edition; .ex5 has
  the sizing floor. Fixed a market hide-pass bug that stripped `InpMinRiskAtrMult`'s `input` (added it to whitelist).
- **Account-level HWM persistence BUILT** (commits 4d82d44, 68fb428) — `KK-Common/PropState.mqh` writes the account
  equity HWM to shared COMMON `KK_PropState_<acct>.txt`; RESET = delete the file; Tester-skipped so backtests
  unchanged. MasterVP fully wired (reload no longer resets the DD guard). KenKem ADDITIVELY wired (basis=EQUITY) —
  both legs now maintain the joint HWM, but KenKem's own DD enforcement still runs on peak BALANCE.
- **Prop params retuned (operator):** risk 0.43%, soft-block 8.0%→0.5×, halt 9.5% — 1.07 rebuilt (commit cbb35cb).
  NEEDS a user MT5 re-run to confirm it now clears Aug-2025.

## Open next steps (operator-chosen)
1. ✅ MT5 re-run DONE — 0.43%/8.0/9.5 CLEARS the full window (1541 trades, final $29,874, max bal DD 8.75% < 9.5%). Thin margin (~0.75%) noted.
2. ✅ **KenKem gated equity re-base DONE + A/B RUN + FLIPPED ON** (commits b1b05ae, eddb66a). MT5 XAU M1 2025.05.01→
   2026.05.29 same prop .set: A(balance) $10801 (+8.01%) recovery×2; B(equity) $10763 (+7.63%) recovery×4. −0.38%/yr
   cost (extra throttling on open-position DD) but matches FundedNext's equity-measured DD rule → `USE_EQUITY_DD_BASIS=true`
   now in the prop .set (personal stays balance). ⚠️ NOTE: that prop .set still has `MADE_FOR_PROP_TRADING=false` +
   `ENABLE_PEAK_BALANCE_DECAY=true`, OPPOSITE of the FundedNext deployment requirement — prop-hard-block stays inert
   until those are set true/false. Operator decision before funded deploy.

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
