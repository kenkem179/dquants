---
name: python-env-kenkem
description: "How to use the dquants Python research env (native arm64 conda env 'kenkem')"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 93eabcdd-ed73-4c3a-8a0a-c1d68af64676
---

Python research runs in conda env **`kenkem`** (Python 3.11), installed via **native arm64 Miniforge**
at `~/miniforge3` (set up by `scripts/setup_env.sh`).

Activate: `source ~/miniforge3/etc/profile.d/conda.sh && conda activate kenkem`.

**Rosetta pitfall (learned the hard way):** the system Homebrew is x86 (`/usr/local/Homebrew`), so
`brew install --cask miniforge` produces an x86 env that runs under Rosetta on the M5 and hits
libomp/OpenMP dylib failures (lightgbm/xgboost). Fix = install Miniforge natively from the official
installer (not brew) and install compiled libs (lightgbm/xgboost/shap) via **conda-forge**, not pip
wheels. `setup_env.sh` does this. System `python3` is 3.8.2 — never use it. See [[project-kenkem-quant-os]].
