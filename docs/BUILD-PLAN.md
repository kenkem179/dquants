# KenKem Quant OS - Active Build Plan

Executable open work only. Completed/rejected items live in `docs/BUILD-PLAN-ARCHIVED.md`.

Standing doctrine is summarized in `docs/CODEX-MEMORY.md`; the full architecture/SOP is in
`docs/KENKEM_QUANT_OS.md`. Update `HANDOFF.md` last after every meaningful session.

Legend: `[~]` in progress, `[ ]` todo, blocked = needs user/MT5/external action.

---

## Priority 0 - Current Baton

- [~] **PF1 - KK-MasterVP Profiler <-> KK-MasterVP EA parity.**
  Steps 1-3 are done in code and compile 0/0: the Profiler now uses the EA stack for signal/gates, pure-UTC
  session gates, one-position/max-trades gates, and lock-faithful exit replay including TP1->BE->ATR trail,
  ProgTrail ladder 2.0R/0.75/0.2, and runner cap. Performance was bounded by replaying only the lookback window
  and drawing sparse stop-path segments.

  **Blocked on user:** attach the Profiler on XAU M5 with the lock `.set` and visually compare entries, verdicts,
  and stop paths against sampled EA backtest trades. Daily-DD is the only expected non-reproducible gate.

  **Next after user OK:** commit any remaining worktree changes, run the Profiler market builder, package a
  versioned Profiler release, and update this plan + handoff.

- [ ] **MasterVP 1.07 upload follow-through.**
  EA 1.07 was re-cut without a version bump and includes the broadcast compliance disclaimer. User action:
  upload `releases/1.07/market/KK-MasterVP-Market-1.07.ex5`.

---

## Priority 1 - MT5-Judged Exit Work

> Exit-side levers must be validated in MT5, not locked from C++ engine numbers. The engine over-credits trailed
> runners and missed the final RR/trail plateau.

- [~] **H9 - Re-validate the exit cluster on the MT5 optimizer.**
  Prepared: internal `KK-MasterVP-Debug.mq5` exposes all optimizer params; curated market EA remains
  byte-identical. Optimizer `.set` grids exist for partial TP, BE/trail/RR, and ProgTrail ladder; plan:
  `research/mastervp_parity/H9_MT5_OPTIMIZER_PLAN.md`.

  **Blocked on user MT5 optimizer runs:** run grids A -> C -> B on XAU M5, every tick based on real ticks,
  2025.06.01-2026.05.29, dep 10k, rank by PF/robustness not peak net. A true multi-rung TP ladder still needs
  a default-OFF code build if the user greenlights Grid D.

---

## Priority 2 - KenKem Research

- [ ] **KenKem M1 lock maintenance.**
  Current practical decision: accept **KenKem XAU M1-only**. The M3/K1 lever was tested and rejected; E5 stays
  off unless a future latch/parity pass is explicitly requested. Preserve `KK-KenKem XAU M1 D5-E4Long` as the
  validated KenKem edge unless fresh MT5 evidence supersedes it.

- [ ] **K2 - BTCUSD KenKem sweeps across M1/M3/M5.**
  High prior of rejection. Hard prerequisites before trusting any BTC number:
  pip-denominated decision params converted to ATR-relative, BTC parity reference per timeframe, realistic BTC
  spread/commission/weekend costs, per-quarter + WF/MC, overfitting gate with sweep context, and final MT5
  confirm. Do not inherit XAU blocked hours or XAU pip thresholds.

- [ ] **K3 - Add a Volume Profile dimension to KenKem.**
  Reuse existing MasterVP VP code rather than inventing a new VP engine. Start with distance-based VP features
  (VAH/VAL/POC) and run edge autopsy before sweeps. Any node-net/absorption feature is blocked by the known
  MQL<->C++ node-net value parity gap.

---

## Priority 3 - MasterVP Research Levers

- [ ] **H6 - FVG-anchored stop-loss.**
  Default-OFF structural SL candidate. Needs user-confirmed geometry before implementation: for long entries,
  which bullish FVG below VAH and which edge/buffer should anchor SL; mirror for shorts above VAL. Validate by
  A/B, 6-fold WF, MC, overfitting gate, then MQL only after DSR-pass.

- [ ] **H8 - BTC 24h-minus-blocked session ablation.**
  Config-first study. Confirm weekend handling first; derive BTC-specific blocked hours empirically; include
  realistic BTC costs. XAU is only a control. BTC locks require MT5 confirm.

- [ ] **T4 - Monster impulse sub-optimization and cross-symbol coverage.**
  Low priority; Monster is retired unless the user explicitly reopens it.

- [ ] **T5 - Cost realism.**
  Add commission + slippage assumptions before any new BTC deploy claim.

- [ ] **C1 - Dead-code cleanup.**
  Audit default-OFF research features unused by recent locks, then remove one feature per commit with tests and
  locked-run byte-diff safety. Confirm scope before deleting reversion history.

---

## Deployment/Ops

- [ ] **D5 - Account-level concurrent-risk cap.**
  Layer-4 live MT5 only. Sum open risk across KK EAs via terminal GlobalVariables and block new entries when
  account-level simultaneous risk exceeds a cap, e.g. 2-3%. Keep pure cap math unit-testable.

- [ ] **D4 - Trial-expiry deadline on account-locked marketplace builds.**
  Bake hidden compile-time expiry into per-account market builds. Use broker `TimeCurrent()`, alert once, block
  new entries after expiry, skip in tester/optimization. Confirm behavior for already-open positions before
  implementation; recommended behavior is to let existing trades manage out.
