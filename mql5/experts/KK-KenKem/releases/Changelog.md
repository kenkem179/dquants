# KK-KenKem — Changelog

_Newest on top. Each dquants release (`make release STRATEGY=KK-KenKem`) appends its
entry here automatically; pass `NOTES="..."` (or `--notes`) to set the description._

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
