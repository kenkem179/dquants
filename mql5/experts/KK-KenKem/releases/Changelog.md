# KK-KenKem — Changelog

## 1.04 — 2026-06-30

- Built `2026-06-30T12:19:31Z` · commit `b70c7d8` on `3-codex-handoff`
- EA: `KK-KenKem-1.04.ex5` (locked build of `KK-KenKem.mq5`)
- Mixed FN-Stella2 portfolio: retune mixed leg (risk 0.1%, joint DD daily 4.2% / soft-derisk 7.8% / hard-halt 9.2%) with MADE_FOR_PROP_TRADING=true (soft-block threshold = hard halt), ENABLE_PEAK_BALANCE_DECAY=false, USE_EQUITY_DD_BASIS=true. Rebuild required so USE_EQUITY_DD_BASIS (added post-1.03) is compiled into the binary; prop set also gains equity basis.
- Variants: `xauusd-m1` `xauusd-m1-prop` `xauusd-m1-mixed-fn`

## 1.03 — 2026-06-23

- Built `2026-06-23T10:16:18Z` · commit `51b63e6` on `reliableBaseline`
- EA: `KK-KenKem-1.03.ex5` (locked build of `KK-KenKem.mq5`)
- Add Mixed-Portfolio FN-Stellar2 00K variant (xauusd-m1-mixed-fn); disable heavy per-bar trace on all deployment variants (trade journal stays on)
- Variants: `xauusd-m1` `xauusd-m1-prop` `xauusd-m1-mixed-fn`

## 1.02 — 2026-06-23

- Built `2026-06-23T08:25:37Z` · commit `2c02a55` on `reliableBaseline`
- EA: `KK-KenKem-1.02.ex5` (locked build of `KK-KenKem.mq5`)
- MQL5-Market edition: whitelist-strip + lock-bake (D5-E4Long). Dialog exposes only 21 safe knobs (E1/E2 toggles, risk, daily-DD, RR, trades/session, news blackout, prop mode); all strategy internals hidden + frozen at the validated lock.
- Variants: `xauusd-m1` `xauusd-m1-prop`

## 1.01 — 2026-06-23

- Built `2026-06-23T07:23:14Z` · commit `7bcbe35` on `reliableBaseline`
- EA: `KK-KenKem-1.01.ex5` (locked build of `KK-KenKem.mq5`)
- MQL5 Market hardening: clamp lot to SYMBOL_VOLUME_LIMIT in NormalizeLotSize (margin + stop-distance guards already present)
- Variants: `xauusd-m1` `xauusd-m1-prop`

## 1.0 — 2026-06-21

- Built `2026-06-21T22:59:43Z` · commit `8303652` on `reliableBaseline`
- EA: `KK-KenKem-1.0.ex5` (locked build of `KK-KenKem.mq5`)
- D5-E4Long LOCK (E1+E2+E4-long): MT5 +1427.17 / PF 1.428 / 126 tr; MC P(profit) 94.9%; overfitting gate PSR 0.953 / MinTRL 122<126 PASS. Ships personal (as-swept) + prop (daily-loss 4.4% / account-DD 9%) variants.
- Variants: `xauusd-m1` `xauusd-m1-prop`

## Unreleased

- ⭐ **Current LOCK = D5-E4Long** (E1 + E2 + E4-long; E4 shorts are net-losers, off).
  MT5-confirmed **+1427.17 / PF 1.428 / 126 trades**; MC-hardened P(profit) 94.9%;
  overfitting gate **PSR 0.953 / MinTRL 122 < 126 PASS** — the only KenKem config to
  clear the gate. Preset: `research/kenkem_parity/KK-KenKem-XAUUSD-M1-D5-E4Long.set`.
  Not yet cut as a versioned dquants release — run `make release STRATEGY=KK-KenKem`
  (first release lands at the dev `#property version` 1.0) to package it.
- Engine-only experiment (NOT in the EA): E1 Kaufman Efficiency-Ratio chop filter →
  **WEAK / not locked** (narrow small-n OOS spike, pooled-net-negative). Committed
  default-OFF as infra; `D6-E1ER.set` is engine-only. See
  `research/optimization/KENKEM-E1-EFFICIENCY-RATIO-2026-06-22.md`.

## 1.8.154-legacy — 2026-06-21

- Manually released by the user (pre-dates the `make_release.sh` auto-bump tooling).
- EA: `KenKemExpert-1.8.154.ex5` — the **original profitable KenKemExpert** build (from
  the `../kenkem` source), kept here as the ground-truth baseline the clean C++→MQL5
  rewrite must reproduce. This is **NOT** the new dquants `KK-KenKem` EA — different EA,
  kept for side-by-side forward-test reference.
- Param set: `KK-KenKem-XAUUSD-M1-1.8.154.set` → symlink to
  `research/kenkem_parity/KK-KenKem-XAUUSD-M1-D4-E5.set`.
- ⚠️ Version tag `1.8.154-legacy` is **non-standard** (not `<major>.<minor>`), so
  `make_release.sh` ignores it when scanning `releases/` for the latest version — new
  dquants releases start fresh at the dev `#property version` (1.0).
