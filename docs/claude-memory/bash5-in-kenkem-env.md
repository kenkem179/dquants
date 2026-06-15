---
name: bash5-in-kenkem-env
description: "kenkem conda env carries bash 5.2 because macOS only has bash 3.2, needed by sweep scripts"
metadata: 
  node_type: memory
  type: project
  originSessionId: d8787dc7-ae1c-404e-9e11-10875d14712a
---

The machine only has system **bash 3.2** (macOS default; no Homebrew bash). `scripts/export_sweep_data.sh` uses an associative array (`declare -A`), which needs bash ≥4.0 — under 3.2 it crashes with `line 23: btc: unbound variable`.

Fix applied 2026-06-14: installed native arm64 **bash 5.2** into the `kenkem` conda env (`conda install -c conda-forge bash`). With `conda activate kenkem`, `bash` resolves to the env's 5.2 and the sweep scripts run unmodified.

**How to apply:** Always `conda activate kenkem` before running `scripts/run_persist_sweep.sh` / `export_sweep_data.sh` — that puts bash 5.2 on PATH. The scripts were NOT edited. Related: [[xau-data-gap-2025h2]].
