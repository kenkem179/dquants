//+------------------------------------------------------------------+
//|                                                   CSVExport.mqh  |
//|              KenKem EA v1.7.51 - CSV Export Functions            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

//================================================================
// CSV EXPORT FUNCTIONS
// Trade logging and data export to CSV files
//================================================================

// Minimal CSV escaping for text fields
string CsvEscape(string s) {
    if (StringFind(s, ",") >= 0 || StringFind(s, "\"") >= 0) {
        StringReplace(s, "\"", "\"\"");
        return "\"" + s + "\"";
    }
    return s;
}

// Buffered CSV flush: write all buffered rows and flush once
void FlushCSVBuffer() {
    if (!ENABLE_CSV_EXPORT) return;
    if (csvFileHandle == INVALID_HANDLE) return;
    if (csvBuffer.count <= 0) return;
    
    for (int i = 0; i < csvBuffer.count; i++) {
        FileWriteString(csvFileHandle, csvBuffer.data[i]);
    }
    FileFlush(csvFileHandle);
    csvBuffer.count = 0;
    lastCSVFlush = TimeCurrent();
}

// Initialize CSV Export (creates monthly files with full indicator columns)
void InitializeCSVExport() {
    if (!ENABLE_CSV_EXPORT) return;
    
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int currentMonth = dt.year * 100 + dt.mon;
    
    // Check if we need a new file (new month or first time)
    if (currentMonth != lastLoggedMonth) {
        // Close existing file if open
        if (csvFileHandle != INVALID_HANDLE) {
            FlushCSVBuffer();
            FileClose(csvFileHandle);
            csvFileHandle = INVALID_HANDLE;
        }
        
        // Create new monthly filename (include symbol and account ID to differentiate)
        // NOTE: Version NOT included - avoids file fragmentation on upgrades
        long accountId = AccountInfoInteger(ACCOUNT_LOGIN);
        currentCSVFileName = StringFormat("%04d%02d_KenKem_%s_%d_trades.csv", dt.year, dt.mon, _Symbol, accountId);
        
        // Force delete existing file to ensure fresh start with new header format
        if (FileIsExist(currentCSVFileName, FILE_COMMON)) {
            FileDelete(currentCSVFileName, FILE_COMMON);
        }
        if (FileIsExist(currentCSVFileName)) {
            FileDelete(currentCSVFileName);
        }
        
        csvFileHandle = FileOpen(currentCSVFileName, FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
        
        if (csvFileHandle != INVALID_HANDLE) {
            // Write header row with all indicator values (47 columns total)
            FileWrite(csvFileHandle, 
                      "Timestamp", "MagicNumber", "EntryType", "Status", "CurrentPrice", "EntryPrice", "StopLoss", "TakeProfit",
                      "LotSize", "RiskPips", "RewardPips", "RR", "RawSLPips", "BufferedSLPips", "ATR_M1", "SpreadPips",
                      // ADX indicators (M1, M3, M5) - 9 columns
                      "ADX_M1", "DIPlus_M1", "DIMinus_M1", "ADX_M3", "DIPlus_M3", "DIMinus_M3", "ADX_M5", "DIPlus_M5", "DIMinus_M5",
                      // RSI indicators (M1, M3, M5) x 3 periods - 9 columns
                      "RSI7_M1", "RSI14_M1", "RSI21_M1", "RSI7_M3", "RSI14_M3", "RSI21_M3", "RSI7_M5", "RSI14_M5", "RSI21_M5",
                      // EMA indicators (M1, M3, M5) x 4 periods - 12 columns (no EMA12)
                      "EMA25_M1", "EMA75_M1", "EMA100_M1", "EMA200_M1",
                      "EMA25_M3", "EMA75_M3", "EMA100_M3", "EMA200_M3",
                      "EMA25_M5", "EMA75_M5", "EMA100_M5", "EMA200_M5");
            
            lastLoggedMonth = currentMonth;
            
            // Print detailed file location information
            string terminalDataPath = TerminalInfoString(TERMINAL_DATA_PATH);
            string fullFilePath = terminalDataPath + "\\MQL5\\Files\\" + currentCSVFileName;
            
            Print("CSV Export initialized successfully!");
            Print("CSV File Name: ", currentCSVFileName);
            Print("Terminal Data Path: ", terminalDataPath);
            Print("Full File Path: ", fullFilePath);
            Print("To find file: MT5 -> File -> Open Data Folder -> MQL5 -> Files");
            
        } else {
            Print("Failed to create CSV file: ", currentCSVFileName);
            Print("Check if MT5 has write permissions to MQL5\\Files folder");
        }
    }
}

// Export trade event to CSV with full indicator data (ASYNC - non-blocking)
void ExportTradeEventToCSV(Trade &dtrade, string eventType, string reason = "") {
    // PERFORMANCE: Early exit if CSV disabled
    if (!ENABLE_CSV_EXPORT) return;
    
    // PERFORMANCE: Limit skipped trades to 1 per minute to reduce I/O
    if (eventType == "SKIP") {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        int currentMinute = dt.year * 100000000 + dt.mon * 1000000 + dt.day * 10000 + dt.hour * 100 + dt.min;
        
        if (currentMinute == lastSkippedMinute) {
            return; // Skip logging this skipped trade
        }
        lastSkippedMinute = currentMinute;
    }
    
    // PERFORMANCE: Initialize CSV only when needed (monthly check)
    InitializeCSVExport();
    if (csvFileHandle == INVALID_HANDLE) return;
    
    // PERFORMANCE: Fast status mapping using switch statement
    string status = "";
    if (eventType == "SKIP") {
        status = "SKIPPED_" + (StringFind(dtrade.type, "L-") == 0 ? "BUY" : "SELL");
    } else if (eventType == "ENTRY") {
        status = dtrade.isLong ? "BUY" : "SELL";
    } else if (eventType == "CLOSED_WON") {
        status = dtrade.isLong ? "BUY_WON" : "SELL_WON";
    } else if (eventType == "CLOSED_LOST") {
        status = dtrade.isLong ? "BUY_LOST" : "SELL_LOST";
    } else if (eventType == "SKIPPED_BUY_WON") {
        status = "SKIPPED_BUY_WON";
    } else if (eventType == "SKIPPED_SELL_WON") {
        status = "SKIPPED_SELL_WON";
    } else if (eventType == "SKIPPED_BUY_LOST") {
        status = "SKIPPED_BUY_LOST";
    } else if (eventType == "SKIPPED_SELL_LOST") {
        status = "SKIPPED_SELL_LOST";
    } else if (eventType == "SKIPPED_EARLY_EXIT") {
        status = "SKIPPED_EARLY_EXIT";
    } else if (eventType == "PARTIAL_TP") {
        status = "PARTIAL_TP";
    }
    
    // PERFORMANCE: Pre-calculate values once
    double riskPips = 0, rewardPips = 0, rrRatio = 0;
    if (dtrade.entryPrice > 0 && dtrade.stopLoss > 0 && dtrade.takeProfit > 0) {
        riskPips = MathAbs(dtrade.entryPrice - dtrade.stopLoss) / pipSize;
        rewardPips = MathAbs(dtrade.takeProfit - dtrade.entryPrice) / pipSize;
        rrRatio = rewardPips / MathMax(riskPips, 0.1);
    }
    
    // PERFORMANCE: Avoid indicator cache work for skipped events
    bool isSkippedEvent = (eventType == "SKIPPED" || eventType == "SKIPPED_WON" || eventType == "SKIPPED_LOST");
    double currentPrice = 0.0;
    if (!isSkippedEvent) {
        // Use cached indicator values (already updated in OnTick per new bar)
        currentPrice = cache.currentPrice;
    } else {
        // Fast path for skipped events
        currentPrice = iClose(_Symbol, PERIOD_M1, ENTRY_SHIFT);
    }
    
    // PERFORMANCE: Build CSV row as single string (faster than multiple concatenations)
    string row = "";
    StringReserve(row, 1024); // Reserve 1KB for the row
    
    // SAFETY: Ensure magicNumber is set (fallback from id if needed)
    if (dtrade.magicNumber == 0) {
        if (dtrade.id != "") {
            dtrade.magicNumber = GetTradeMagic(dtrade.id);
        }
        if (dtrade.magicNumber == 0) {
            dtrade.magicNumber = GetTradeMagic("");
        }
    }
    
    row = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + ",";
    row += IntegerToString(dtrade.magicNumber) + ",";
    row += CsvEscape(dtrade.type) + ",";
    row += status + ",";
    row += DoubleToString(currentPrice, _Digits) + ",";
    row += DoubleToString(dtrade.entryPrice, _Digits) + ",";
    row += DoubleToString(dtrade.stopLoss, _Digits) + ",";
    row += DoubleToString(dtrade.takeProfit, _Digits) + ",";
    // Trade metrics (4 columns)
    row += DoubleToString(dtrade.lotSize, 2) + ",";
    row += DoubleToString(riskPips, 1) + ",";
    row += DoubleToString(rewardPips, 1) + ",";
    row += DoubleToString(rrRatio, 2) + ",";
    row += DoubleToString(dtrade.rawSLDistancePips, 1) + ",";
    row += DoubleToString(dtrade.bufferedSLDistancePips, 1) + ",";
    row += DoubleToString(cache.atrM1 / pipSize, 1) + ",";  // ATR in pips
    row += DoubleToString(lastSpreadPips, 1) + ",";          // Spread in pips
    if (!isSkippedEvent) {
        // PERFORMANCE: Use cached ADX values (M1, M3, M5) - 9 columns
        row += DoubleToString(cache.adx[0], 2) + ",";
        row += DoubleToString(cache.diPlus[0], 2) + ",";
        row += DoubleToString(cache.diMinus[0], 2) + ",";
        row += DoubleToString(cache.adx[1], 2) + ",";
        row += DoubleToString(cache.diPlus[1], 2) + ",";
        row += DoubleToString(cache.diMinus[1], 2) + ",";
        row += DoubleToString(cache.adx[2], 2) + ",";
        row += DoubleToString(cache.diPlus[2], 2) + ",";
        row += DoubleToString(cache.diMinus[2], 2) + ",";

        // Full indicator data for real trades
        row += DoubleToString(GetRSICurrent(PERIOD_M1, 7), 2) + ",";
        row += DoubleToString(GetRSICurrent(PERIOD_M1, 14), 2) + ",";
        row += DoubleToString(GetRSICurrent(PERIOD_M1, 21), 2) + ",";
        row += DoubleToString(GetRSICurrent(PERIOD_M3, 7), 2) + ",";
        row += DoubleToString(GetRSICurrent(PERIOD_M3, 14), 2) + ",";
        row += DoubleToString(GetRSICurrent(PERIOD_M3, 21), 2) + ",";
        row += DoubleToString(GetRSICurrent(PERIOD_M5, 7), 2) + ",";
        row += DoubleToString(GetRSICurrent(PERIOD_M5, 14), 2) + ",";
        row += DoubleToString(GetRSICurrent(PERIOD_M5, 21), 2) + ",";

        // EMA indicators
        row += DoubleToString(GetEMA_1m(EMA1, 0), _Digits) + ",";
        row += DoubleToString(GetEMA_1m(EMA2, 0), _Digits) + ",";
        row += DoubleToString(GetEMA_1m(EMA3, 0), _Digits) + ",";
        row += DoubleToString(GetEMA_1m(EMA4, 0), _Digits) + ",";
        row += DoubleToString(GetEMA_3m(EMA1, 0), _Digits) + ",";
        row += DoubleToString(GetEMA_3m(EMA2, 0), _Digits) + ",";
        row += DoubleToString(GetEMA_3m(EMA3, 0), _Digits) + ",";
        row += DoubleToString(GetEMA_3m(EMA4, 0), _Digits) + ",";
        row += DoubleToString(GetEMA_5m(EMA1, 0), _Digits) + ",";
        row += DoubleToString(GetEMA_5m(EMA2, 0), _Digits) + ",";
        row += DoubleToString(GetEMA_5m(EMA3, 0), _Digits) + ",";
        row += DoubleToString(GetEMA_5m(EMA4, 0), _Digits) + "\n";
    } else {
        // PERFORMANCE: Minimal data for skipped trades - use zeros for all indicator columns
        // Note: ATR and Spread already added above, so only indicator columns here
        row += "0,0,0,0,0,0,0,0,0,";  // 9 ADX columns
        row += "0,0,0,0,0,0,0,0,0,";  // 9 RSI columns
        row += "0,0,0,0,0,0,0,0,0,0,0,0\n";  // 12 EMA columns
    }

    // Append to buffer (flush happens at session end via UpdateSessionTracking)
    if (csvBuffer.count < CSV_BUFFER_SIZE) {
        csvBuffer.data[csvBuffer.count++] = row;
    }
    
    // Safety: flush if buffer is full (prevents data loss)
    if (csvBuffer.count >= CSV_BUFFER_SIZE) {
        FlushCSVBuffer();
    }
}
