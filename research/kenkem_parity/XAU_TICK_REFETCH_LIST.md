# XAU tick re-export — missing trading days

These UTC weekdays have **zero ticks** in the exported XAU CSVs but MT5's tester history HAS them
(proven for 2025-04-28..30: the EA trace contains continuous bars there). Each hole gaps the price
across the missing days and poisons ATR/percentile for ~28 bars after it. Re-export full XAU tick
history (or just these ranges) from the same Exness MT5 terminal, then re-run the dquants import
(`/quant-1-import-data`) and rebuild bars (`build_bars.py`).

BTC is complete — no action needed there.

## Ranges to refetch (XAU)
**2024** (export covers 2024-01-01 .. 2024-12-22):
- 2024-08-12
- 2024-09-12
- 2024-09-30
- **2024-11-19 → 2024-12-20**  ← ~5 consecutive weeks, near-total. The big one. Makes any 2024 XAU run unusable.

**2025** (export covers 2025-01-01 .. 2025-07-16):
- 2025-04-28 → 2025-04-30   ← PROVEN hole (Mon–Wed, not holidays)
- 2025-05-16
- 2025-06-03
- 2025-06-30

**2026** (export covers 2026-01-01 .. 2026-04-06):
- 2026-04-01 → 2026-04-03   (right at the export cutoff; refetch if you extend past Apr)

## Skip (legitimate market holidays — XAU closed, MT5 has no ticks either)
- 2024-03-29  (Good Friday)
- 2025-04-18  (Good Friday)

## Verify after refetch
`python cpp_core/tools/common/build_bars.py --sym xauusd --year 2025 --tfs 1` → the
"MISSING weekdays" report should print only the two Good Fridays.
