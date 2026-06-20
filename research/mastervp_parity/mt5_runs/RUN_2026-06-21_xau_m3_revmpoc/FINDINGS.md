# RUN 2026-06-21 — KK-MasterVP XAUUSD M3 RevMpoc (CONTAMINATED collect)

**Expert** KK-MasterVP.ex5 · **XAUUSD-Exness-KK M3** · 2025.06.01–2026.05.31 · every-tick · Agent-3000.

## Result (MT5 actual, from exported parity CSV — 2106 trades)
- **PF 1.013 · net +1,171 USD · win 49.8% · final balance 11,171**
- by entryReason: L-BRK 1135, S-BRK 846 (breakout 1981) · S-REV 61, L-REV 43 (reversion 104) · L-XREV 8, S-XREV 13 (XRev 21)

## ⚠️ CONTAMINATION — not a clean reversion-only A/B
The loaded `.set` (old RevMpoc) OMITTED `InpEnableExtremeReversion` and `InpExportParity`; MT5 RETAINS the
prior input-dialog value for any key absent from a loaded `.set`, so **XRev leaked ON** (true from the earlier
XRev runs) and parity export leaked ON. So this run = reversion@mPOC **+ XRev(trailing)**, not reversion-only.
Confirmed by inputs_echo.txt: `InpEnableExtremeReversion=true`, `InpExportParity=true`.

## Fix shipped
Both presets now PIN every behavioral toggle explicitly so dialog state can't leak; they differ in ONLY 3
keys (the reversion controls):
- `KK-MasterVP-XAUUSD-M3-BASE.set`   — EnableReversion=false, RevTpMpoc=false, TrailRev=-1
- `KK-MasterVP-XAUUSD-M3-RevMpoc.set` — EnableReversion=true,  RevTpMpoc=true,  TrailRev=0
Both: ExtremeReversion=false, TrailBrk/Imp/XRev=-1, XRevTpMpoc=false, ExportParity=true.

## NEXT — clean A/B (each ~14s, parity CSV auto-exported)
Run BOTH on XAUUSD M3, 2025.06.01–2026.05.31, every-tick:
1. `KK-MasterVP-XAUUSD-M3-BASE.set`   (the reference)
2. `KK-MasterVP-XAUUSD-M3-RevMpoc.set` (reversion banked at mPOC)
Compare net / PF / maxDD. Engine predicted reversion@mPOC trims OOS maxDD 17.5→13.5% at flat-to-up net.

## NOTE on the weak headline
PF 1.013 (even with the breakout majority) is far below the engine's XAU M3 (~PF 1.26 train / 1.11 OOS) —
the known engine-over-optimism gap, and consistent with XAU **M5** (not M3) being the MT5-validated winner.
The clean base run will set the true reference.
