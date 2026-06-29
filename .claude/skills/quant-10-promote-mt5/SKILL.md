---
name: quant-10-promote-mt5
description: Phase 10 of the KenKem Quant OS SOP — promote a validated C++ strategy core into a thin MQL5 Expert Advisor with forward-test plan. Use only after walk-forward + Monte Carlo pass.
---

# Phase 10 — Promote to MT5

The final step. Only run after a strategy passes the full validation chain (§7 of the master plan) —
**including the Phase 9 overfitting gate: a config that did not clear Deflated Sharpe (DSR) ≥ 0.95 is
not promotable.** If you can't point to a DSR-PASS (or an explicitly-accepted WARN), go back, don't promote.

## Input
A validated strategy whose logic lives in `cpp_core/` (Layer 2, pure C++20).

## Output
- A `Strategy` subclass in `cpp_core/` with deterministic unit tests (`cpp_core/tests/`).
- A thin MQL5 EA in `mql5/experts/` + shared `mql5/include/`.
- A forward-test plan (demo/VPS) in `docs/`.

## How
- Keep all decision logic in C++ (Layer 2). Port only the **pure functions** —
  `LongSignal/ShortSignal/CalculateSL/CalculateTP` — into MQL5; they translate ~1:1.
- The EA is thin: `OnTick() → Strategy.Update() → if LongSignal() OrderSend(...)`. MT5-specific calls
  (`OrderSend/PositionSelect/CopyRates/iATR`) live **only** here (Layer 4).
- **Verify parity:** the MQL5 EA must produce the same signals as the C++ core on the same ticks before
  it is trusted.

## Presets & MT5 loading (keep this organized)
- A locked/deploy `.set` is the source of truth in its **EA folder** (`mql5/experts/<EXPERT>/`),
  or in `research/kenkem_parity/` for KenKem M1 lock candidates. That is also what `release.conf`
  and run READMEs reference — never move it out from under them.
- Surface it for one-click loading: run **`./scripts/sync_presets.sh`**. This rebuilds the tidy
  by-expert symlink view at `mql5/experts/Presets/<EXPERT>/` (zero drift) AND relinks it into MT5
  at `MQL5/Profiles/Tester/dquants`. The user then loads via Strategy Tester → Inputs → Load →
  `dquants/<expert>/<name>.set`.
- After a fresh clone (or if the MT5 link vanished), run `sync_presets.sh` once.
- Don't hand-copy single `.set` into the flat `MQL5/Presets/` dir — that habit is superseded.
  See `mql5/experts/Presets/README.md`.

## Acceptance
- C++ unit tests + tick backtest pass deterministically.
- MQL5 EA reproduces C++ signals on identical tick data (parity check).
- Risk controls + logging present; demo forward-test plan written.
- MT5 Strategy Tester used only as a final sanity check, never as the source of truth.

See `docs/KENKEM_QUANT_OS.md` §1, §5, §7 (Phase 10).

## Prop-account hardening (MANDATORY when the deploy target is a prop account)

When producing a `.set` (or a multi-chart portfolio bundle) for a prop firm (FundedNext etc.), the
locked edge `.set` is NOT safe to ship as-is — locks carry prop-HOSTILE risk defaults. Confirm the
firm's **daily DD %, overall DD %, static-vs-trailing, account size, and current DD** first (these
change the math; never guess them), then bake protection in. Reference recipe + a worked example live
in memory `[[fundednext-stella2-portfolio]]`.

- **Shared Guardian (now in BOTH `KK-MasterVP` and `KK-KenKem`):** arm it in every `.set` —
  `InpGuardEnable=true`, `InpGuardDDAnchor=1` (static), `InpGuardInitialBalance=<firm initial, e.g.
  100000>` (**pins** the anchor to the firm line so the floor is correct at any attach balance and you
  need NOT clear GVs), `InpGuardOverallDDPct`/`InpGuardDailyLossPct` so `anchor×(pct−buffer)` halts
  **above** the firm floor with margin, `InpGuardFlatten=true`. It shares anchors across all KK EAs via
  login-keyed GlobalVariables (VPS-persistent); any breach latches all → each EA flattens only its OWN
  positions (MVP by magic `InpMVPMagic`; KenKem by comment `"KenKemST"`). Set the SAME guardian values
  in every chart's `.set`.
- **KenKem second layer (still arm it):** `MADE_FOR_PROP_TRADING=true` and
  **`ENABLE_PEAK_BALANCE_DECAY=false`** (decay drifts the DD anchor down and loosens the block — load-
  bearing), plus `ACCOUNT_DD_RATIO_TO_SOFT_BLOCK` / `…_TO_SLOWDOWN` / `MAX_DAILY_LOSS_RATIO` inside the
  firm lines and small `COMMON_MAX_RISK_PER_TRADE` × `MAX_CONCURRENT_POSITIONS_ALLOWED`.
- **Same-symbol portfolios** (e.g. MVP XAU M5 + KenKem XAU M1): safe — KenKem only manages `"KenKemST"`
  trades, MVP filters by magic; but KenKem risk-counting is symbol-only so it self-throttles when the
  other holds the symbol (conservative).
- **Allocation:** most risk to the MT5-proven money-makers, humble the thin/unconfirmed ones; size to
  *survive first* while in DD. Per-trade % = risk-if-SL-hit, NOT a per-EA DD cap — account DD is capped
  only by the shared Guardian. Keep budget DETERMINISTIC per EA (don't auto-split across EAs).
  **Op step:** have the user reload the recompiled `.ex5` (re-attach / restart MT5).
