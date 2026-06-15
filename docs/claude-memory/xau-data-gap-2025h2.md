---
name: xau-data-gap-2025h2
description: Imported XAU tick data is missing 2025-07-16 through 2025-12-31; affects XAU param sweeps
metadata: 
  node_type: memory
  type: project
  originSessionId: d8787dc7-ae1c-404e-9e11-10875d14712a
---

The Exness XAUUSD tick download imported on 2026-06-14 (from `~/Downloads/tickdata/ExnessTickData-XAU-2024-202604/XAUUSD_ticks_mt5_2025_2026.csv`) is **missing 2025-07-16 → 2025-12-31** (~5.5 months; July 2025 itself is partial). The combined file jumps from 2025-07-16 straight to 2026-01-01. Verified at import: 0 parse failures, so this is a genuine gap in the source download, not an import bug.

`data/processed/ticks_xauusd_2025.parquet` therefore only covers 2025-01-01 → 2025-07-16 (34.2M rows).

**Why:** `scripts/export_sweep_data.sh` configures the XAU sweep window as **2025-08-01 → 2025-12-01**, which lies entirely inside the missing range — so the XAU persistence sweep cannot run on this data until the gap is filled. The BTC sweep window (2025-08-11 → 2025-12-01) IS fully covered by `ticks_btcusd_2025.parquet` (full year), so BTC sweeps are unaffected.

**How to apply:** Before running an XAU sweep, either re-download XAU H2-2025 ticks from Exness and re-import (`python -m pipeline.import_multiyear`), or change the XAU window to a covered range (e.g. within Jan–Jul 2025). BTC sweeps need no change. Multi-year Exness exports are split per-year by `pipeline/import_multiyear.py`. Related: [[bash5-in-kenkem-env]].
