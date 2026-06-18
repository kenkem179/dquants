---
name: mt5-reality-all-three-fail
description: MT5 ground truth (2026-06) — all 3 promoted strategies fail the recent OOS window; dquants numbers were overstated
metadata: 
  node_type: memory
  type: project
  originSessionId: 7f6d0397-7b89-4d5f-842e-9b83928da35a
---

On 2026-06-15 the user ran the dquants-promoted MQL5 EAs in the MT5 tester (Exness real ticks). Ground
truth across all three, recent OOS window:

- **KenKem (E5-only, XAU M1, 2025.08→2026.06):** PF 0.85, $10k→$3.8k (−62%); looser configs −94%. 86%
  win but avg win $21 vs avg loss $156 = negative-skew blowup. Engine is a bar-OHLC walk, never tick-
  validated. See [[kenkem-bar-engine-invalid]].
- **KK-MasterVP (BTC M3):** PERIOD-DEPENDENT, not robust. Recent OOS 2025.10→2026.05 = $10k→$8.04k
  (−20%, 3461 deals). Profitable only on longer/partly-in-sample windows (full-2025→mid-2026 was +36%,
  +11%). My "best_btc.set confirmed PF>1 in MT5" cherry-picked a favorable window. MasterVP passed
  trade-level PARITY (engine reproduces MT5 trades) — but parity ≠ profitable; I conflated the two.
- **KK-Monster (BTC M3):** ZERO trades over 8 months in MT5, but the dquants Monster C++ engine makes
  150–184 profitable trades (PF ~1.65) on the SAME config → hard **engine/MQL5 PARITY DIVERGENCE**
  (confirmed 2026-06-15). Root cause: C++ engine derives net volume from tick PRICE-DELTAS (NetMin
  gates 0.8–0.95 pass → trades); MQL5 keys off a volume signal ~0 on the Exness feed (broker VOLUME=0)
  → same gates never met → nothing fires. Monster PF is engine-internal, does NOT transfer to MT5.
  Do not deploy until net-volume parity fixed + MQL5 confirmed to trade. See [[rnd-volume-features]].

**Original KenKem works:** the user's ORIGINAL `KenKemExpert` (E1+E2, NOT E5) is MT5-profitable
(+24%, PF 1.62, 143 trades) on the same XAU M1 OOS window. The distilled port over-traded (E5-only,
2k–6k trades) because it dropped the original's selectivity (conviction, session caps, cooldowns,
ATR-percentile). Production rec = deploy the ORIGINAL; treat all distilled configs as unverified.

**Lesson / rule:** dquants optimization numbers are ENGINE-INTERNAL and were promoted on favorable
windows without MT5 confirmation on the true recent OOS window. Going forward: nothing is "validated"
until it trades correctly AND is profitable in MT5 (or a parity-locked tick engine) on the SAME recent
OOS window. Stop reporting engine PF as truth. Corrects [[milestone-mt5-confirmed-optimization]] and
[[milestone-production-promotion]] (both overstated). [[perf-table-format]] tables must label every
number IS/OOS + engine-vs-MT5.
