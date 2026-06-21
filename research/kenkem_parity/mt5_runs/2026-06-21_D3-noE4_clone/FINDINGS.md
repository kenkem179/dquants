# P4 PARITY — KK-KenKem dquants clone vs legacy KenKemExpert (D3-noE4, E1+E2)

**Date:** 2026-06-21. **Verdict: ✅ EXACT PARITY (trade-for-trade byte-identical).**

## Run
- **EA:** `dquants\KK-KenKem\KK-KenKem` (faithful full clone of KenKemExpert v1.8.154, commit `12bbe21`).
- **Symbol/TF:** XAUUSD M1. **Range:** 2025.03.02–2026.05.29. **Model:** every tick.
- **Preset:** `KK-KenKem-XAUUSD-M1-D3-noE4.set` (E1+E2 only — `ENABLE_E4=false`, `ENABLE_E5=false`;
  `USE_DYNAMIC_RR_SCALING=false`, `E1_ATR_SL_CAP=3.5`, `SIDEWAYS=45`, `MIN_ATR_PCTILE=70`).
  `.set` itself sets `InpExportTradeJournal=true` + `InpExportBarTrace=true`.
- **Output collected from:** `Tester/Agent-127.0.0.1-3000/MQL5/Files/KenKem/`
  (`trades_*.csv` kept here; 150 MB `trace_*.csv` left in place per gitignore; `realtrace_*` ~empty, E5 off).

## Result
| metric | lock log (2026-06-20, legacy EA) | clone (this run) |
|---|---|---|
| trades | 102 | 102 |
| net USD | +1048.88 | +1048.88 |
| PF | 1.389 | 1.389 |
| wins | 53 | 53 |

`diff <(sort lock) <(sort clone)` → **IDENTICAL**. The dquants EA reproduces the legacy EA exactly.

## Meaning
- The faithful-clone methodology is validated: parity by construction holds.
- KK-KenKem is now the dquants-native baseline for KenKem, equal to the MT5-confirmed +1049/PF1.39 lock.
- Unlocks: (P5) prune cosmetics with this exact-parity run as the safety net (re-run → must stay 102/+1048.88);
  and the candidate confirmations (D4 entry-filter improvement; D4-E5; D4-E2RR14) — all MT5-gated.
