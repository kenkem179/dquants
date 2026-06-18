# Path-B check: is the gated C++ KenKem engine competitive on OOS? (2026-06-16)

**Path B (user-chosen):** keep the gated C++ engine as the research asset; if it's competitive, port its
selectivity gates into the KK-KenKem EA. **First step: measure the gated engine on OOS (no MT5 needed).**

Binary: `cpp_core/build/kenkem/tick_backtester` (TICK engine — bar engine forbidden per
[[bar-engine-systemic-defect]]). Symbol XAUUSD M1. Configs derived from
`research/kenkem_parity/parity_kenkem_xau.set` (gates ON, governors neutralized); E1+E2+E5 variant just
flips the entry toggles on (E1/E2 then run engine DEFAULT params — NOT the original's proven values).

| config | period (OOS) | trades | win% | net USD | **PF** | maxDD | by-entry net |
|---|---|---:|---:|---:|---:|---:|---|
| E5 only | 2026 Jan–May | 243 | 77.8 | +1,240 | **1.143** | 1,334 | E5 +1,240 |
| E5 only | 2025 Feb–May | 225 | 51.6 | +818 | **1.143** | 1,882 | E5 +818 |
| E1+E2+E5 | 2026 Jan–May | 452 | 62.2 | −1,830 | **0.938** | 3,979 | E1 −792 · E2 −1,489 · E5 +452 |
| E1+E2+E5 | 2025 Feb–May | 493 | 43.2 | +1,200 | **1.053** | 4,140 | E1 +709 · E2 −223 · E5 +715 |

## Findings
- **E5 is a stable, genuine edge: PF 1.143 in BOTH periods.** But that equals KK-KenKem's own self-reported
  ceiling (~1.13–1.15) — so on E5 the engine's extra gates are NOT yet visibly out-performing the distilled EA.
- **E2 loses in both periods; E1 is regime-dependent** (+709 in 2025, −792 in 2026). At engine-default params,
  E1/E2 do not reproduce the original's weight — adding them HURT 2026 (1.143 → 0.938).
- ⟹ **The gated engine does NOT yet demonstrably beat the PF 1.63 baseline.** But the comparison is not yet
  fair (see gaps). The result is informative, not a verdict.

## Two gaps that block a real Path-B verdict (next work, both doable without MT5)
1. **Period mismatch.** The 1.63 baseline (`kenkem/MQL5/Profiles/Tester/v17620ReportTester-227922402.html`)
   is XAU **M1 Sep–Nov 2025**. On-disk ticks only cover Feb–May 2025 + 2026. **Export Sep–Nov 2025 XAU ticks
   from `data/processed/ticks_xauusd_2025.parquet`** → run the engine on the baseline's exact window.
2. **Param fidelity.** E1/E2 here use engine DEFAULTS, not the original `KenKemExpert`'s proven
   hardcoded+tuned E1/E2 params. **Extract those from the original EA source and load them into the engine**,
   then re-test. Only then does "E1/E2 lose" mean anything about the strategy vs the config.

## ⭐ LIKE-FOR-LIKE on the baseline's EXACT window (added 2026-06-16) — the gap is EXITS
Exported the baseline window from `data/processed/ticks_xauusd_2025.parquet` →
`cpp_core/tools/{ticks_xauusd_2025_sepnov.csv, bars_xauusd_2025_sepnov_m1.csv}` (Sep 1–Nov 15 2025,
21.6M ticks) and ran the tick engine on it:

| run | trades | win% | net USD | PF | by-entry net |
|---|---:|---:|---:|---:|---|
| **Original KenKemExpert** (baseline, `v17620ReportTester`) | 260 | — | **+2,456** | **1.63** | (E1+E2) |
| dquants engine E1+E2+E5 (gated, DEFAULT params) | 250 | 62.4 | +1,245 | **1.082** | E1 +302 · E2 +385 · E5 +557 |
| dquants engine E5 only (gated) | 127 | 76.4 | +380 | 1.079 | E5 +380 |

**🔑 CONCLUSION: the engine reproduces the ENTRIES well — near-identical trade count (250 vs 260) and ALL
entries positive on the baseline window — but earns HALF the money at PF 1.08 vs 1.63. The edge gap is
EXIT GEOMETRY, not entries and not the selectivity gates.** The engine closes via its tight native SL/trail;
the original rides winners via managed/laddered exits. This independently re-confirms the standing root cause
([[parity-gate-built]], [[kenkem-e5-root-cause-exits]]).

## Recommendation (revised by the like-for-like)
The real lever is the **exit model**, not the gates. Port the original `KenKemExpert`'s managed exit geometry
(TP ladder / partials / trail / profit-protection — its hardcoded exit params) into the C++ engine's
`trade_manager.hpp`, re-run the Sep–Nov 2025 like-for-like, and watch PF move toward 1.63. Only then is the
engine a faithful, *better-able* base to sweep. The E5 core (stable PF ~1.14 across 3 windows) is already a
solid first KK-KenKem candidate to ship in parallel while the exit work proceeds.
