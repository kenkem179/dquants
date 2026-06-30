# KK-MasterVP — release 1.08

- Built: `2026-06-30T15:59:31Z` (UTC)
- Source commit: `942fdee` on `3-codex-handoff`
- EA: `KK-MasterVP-1.08.ex5` (locked build of `KK-MasterVP.mq5`)

## Parameter sets

| variant | .set file | base preset | overrides |
|---------|-----------|-------------|-----------|
| xauusd-m5 | `KK-MasterVP-1.08-xauusd-m5.set` | `KK-MasterVP-XAUUSD-M5.set` | InpExportParity=true |
| btcusd-m5 | `KK-MasterVP-1.08-btcusd-m5.set` | `KK-MasterVP-BTCUSD-M5.set` | InpExportParity=true |
| xauusd-m5-conservative | `KK-MasterVP-1.08-xauusd-m5-conservative.set` | `KK-MasterVP-XAUUSD-M5.set` | InpRiskAccPct=0.5 InpMaxDailyDDPct=4.0 InpSoftBlockDDPct=5.0 InpSoftBlockLotMult=0.5 InpMaxPeakDDPct=8.0 InpExportParity=true |
| xauusd-m5-balanced | `KK-MasterVP-1.08-xauusd-m5-balanced.set` | `KK-MasterVP-XAUUSD-M5.set` | InpRiskAccPct=0.75 InpMaxDailyDDPct=5.0 InpSoftBlockDDPct=6.0 InpSoftBlockLotMult=0.5 InpMaxPeakDDPct=10.0 InpExportParity=true |
| btcusd-m5-conservative | `KK-MasterVP-1.08-btcusd-m5-conservative.set` | `KK-MasterVP-BTCUSD-M5.set` | InpRiskAccPct=0.5 InpMaxDailyDDPct=4.0 InpSoftBlockDDPct=5.0 InpSoftBlockLotMult=0.5 InpMaxPeakDDPct=8.0 InpExportParity=true |
| btcusd-m5-balanced | `KK-MasterVP-1.08-btcusd-m5-balanced.set` | `KK-MasterVP-BTCUSD-M5.set` | InpRiskAccPct=0.75 InpMaxDailyDDPct=5.0 InpSoftBlockDDPct=6.0 InpSoftBlockLotMult=0.5 InpMaxPeakDDPct=10.0 InpExportParity=true |
| xauusd-m5-prop | `KK-MasterVP-1.08-xauusd-m5-prop.set` | `KK-MasterVP-XAUUSD-M5.set` | InpRiskAccPct=0.43 InpMaxDailyDDPct=4.4 InpSoftBlockDDPct=8.0 InpSoftBlockLotMult=0.5 InpMaxPeakDDPct=9.5 InpPropBaselineEquity=100000 InpExportParity=true |
| btcusd-m5-prop | `KK-MasterVP-1.08-btcusd-m5-prop.set` | `KK-MasterVP-BTCUSD-M5.set` | InpRiskAccPct=0.43 InpMaxDailyDDPct=4.4 InpSoftBlockDDPct=8.0 InpSoftBlockLotMult=0.5 InpMaxPeakDDPct=9.5 InpPropBaselineEquity=100000 InpExportParity=true |
| xauusd-m5-mixed-fn | `KK-MasterVP-1.08-xauusd-m5-mixed-fn.set` | `KK-MasterVP-XAUUSD-M5.set` | InpRiskAccPct=0.43 InpMaxDailyDDPct=4.2 InpMaxPeakDDPct=9.2 InpSoftBlockDDPct=7.8 InpSoftBlockLotMult=0.4 InpPropBaselineEquity=100000 InpExportParity=true |
| btcusd-m5-mixed-fn | `KK-MasterVP-1.08-btcusd-m5-mixed-fn.set` | `KK-MasterVP-BTCUSD-M5.set` | InpRiskAccPct=0.15 InpMaxDailyDDPct=4.2 InpMaxPeakDDPct=9.2 InpSoftBlockDDPct=7.8 InpSoftBlockLotMult=0.4 InpPropBaselineEquity=100000 InpExportParity=true |
