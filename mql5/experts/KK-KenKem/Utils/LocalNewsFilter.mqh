//+------------------------------------------------------------------+
//|                                            LocalNewsFilter.mqh   |
//|              KenKem EA - Local CSV-Based News Filter             |
//|              Works in both Backtesting and Live Trading          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

//================================================================
// LOCAL NEWS FILTER
// Reads high-impact news events from local CSV file
// No external API calls required - works in backtesting
//================================================================

// News event structure for local storage
struct LocalNewsEvent {
    datetime time;           // Event time (UTC)
    string   event;          // Event name
    string   impact;         // High/Medium/Low
    string   actual;         // Actual value (if available)
    string   forecast;       // Forecast value
    string   previous;       // Previous value
};

// Global array for cached news events (high-impact only after load-time filtering)
LocalNewsEvent g_localNews[];
datetime g_lastNewsFileLoad = 0;
int g_localNewsCount = 0;
bool g_newsFileLoadAttempted = false;

// Per-minute result caches (news granularity is per-minute, skip redundant scans)
datetime g_isNearNewsCacheMinute = 0;
bool g_isNearNewsCacheResult = false;
datetime g_nextNewsCacheMinute = 0;
bool g_nextNewsCacheFound = false;
datetime g_nextNewsCacheTime = 0;
string g_nextNewsCacheEvent = "";

// News file path (relative to MQL5/Files)
string NEWS_CSV_FILE = "KenKem\\HighImpactNews_USD.csv";

//+------------------------------------------------------------------+
//| Load news events from local CSV file                             |
//| Returns: Number of events loaded                                 |
//| Note: Uses FILE_COMMON for Strategy Tester compatibility         |
//| Place CSV in: [Common Data Folder]/Files/KenKem/HighImpactNews_USD.csv |
//| Find path via: MT5 -> File -> Open Data Folder -> go up -> Common |
//+------------------------------------------------------------------+
int LoadLocalNewsFromCSV() {
    // Try FILE_COMMON first (works in both live and Strategy Tester)
    int fileHandle = FileOpen(NEWS_CSV_FILE, FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
    
    if (fileHandle == INVALID_HANDLE) {
        // Fallback to terminal-specific folder
        fileHandle = FileOpen(NEWS_CSV_FILE, FILE_READ | FILE_CSV | FILE_ANSI, ',');
        if (fileHandle == INVALID_HANDLE) {
            if (showDebug) {
                Print("LOCAL NEWS: CSV file not found: ", NEWS_CSV_FILE);
                Print("LOCAL NEWS: Place file in Terminal Common Data -> Files/KenKem/HighImpactNews_USD.csv");
                Print("LOCAL NEWS: Find path: MT5 -> File -> Open Data Folder -> go up one level -> Common -> Files");
            }
            return 0;
        }
    }
    
    // Reset array
    ArrayResize(g_localNews, 0);
    int eventCount = 0;
    int lineNum = 0;
    
    while (!FileIsEnding(fileHandle)) {
        lineNum++;
        
        // Read first field (DateTime or comment)
        string dateTimeStr = FileReadString(fileHandle);
        
        // Skip empty lines and comments
        if (StringLen(dateTimeStr) == 0) {
            FileReadString(fileHandle); // Skip to next line
            continue;
        }
        if (StringGetCharacter(dateTimeStr, 0) == '#') {
            // Skip rest of comment line
            while (!FileIsLineEnding(fileHandle) && !FileIsEnding(fileHandle)) {
                FileReadString(fileHandle);
            }
            continue;
        }
        
        // Skip header line
        if (dateTimeStr == "DateTime") {
            // Skip rest of header line
            while (!FileIsLineEnding(fileHandle) && !FileIsEnding(fileHandle)) {
                FileReadString(fileHandle);
            }
            continue;
        }
        
        // Parse event data
        string eventName = FileReadString(fileHandle);
        string impact = FileReadString(fileHandle);
        string actual = FileReadString(fileHandle);
        string forecast = FileReadString(fileHandle);
        string previous = FileReadString(fileHandle);
        
        // Parse datetime (format: YYYY-MM-DD HH:MM)
        datetime eventTime = ParseNewsDateTime(dateTimeStr);
        
        // Pre-filter: only store high-impact events (all runtime checks need high-only)
        if (eventTime > 0 && StringLen(eventName) > 0 && impact == "High") {
            if (eventCount >= ArraySize(g_localNews)) {
                ArrayResize(g_localNews, eventCount + 128);  // Batch resize to reduce reallocation
            }
            
            g_localNews[eventCount].time = eventTime;
            g_localNews[eventCount].event = eventName;
            g_localNews[eventCount].impact = impact;
            g_localNews[eventCount].actual = "";
            g_localNews[eventCount].forecast = "";
            g_localNews[eventCount].previous = "";
            
            eventCount++;
        }
    }
    
    FileClose(fileHandle);
    ArrayResize(g_localNews, eventCount);  // Trim to actual size
    g_localNewsCount = eventCount;
    g_lastNewsFileLoad = TimeCurrent();
    g_newsFileLoadAttempted = true;
    
    if (showDebug && eventCount > 0) {
        Print("LOCAL NEWS: Loaded ", eventCount, " high-impact USD events from CSV");
    }
    
    return eventCount;
}

//+------------------------------------------------------------------+
//| Parse datetime string from CSV (YYYY-MM-DD HH:MM format)         |
//+------------------------------------------------------------------+
datetime ParseNewsDateTime(string dateTimeStr) {
    // Expected format: "2025-01-03 13:30"
    if (StringLen(dateTimeStr) < 16) return 0;
    
    // Split by space
    int spacePos = StringFind(dateTimeStr, " ");
    if (spacePos < 0) return 0;
    
    string datePart = StringSubstr(dateTimeStr, 0, spacePos);
    string timePart = StringSubstr(dateTimeStr, spacePos + 1);
    
    // Parse date (YYYY-MM-DD)
    int year = (int)StringToInteger(StringSubstr(datePart, 0, 4));
    int month = (int)StringToInteger(StringSubstr(datePart, 5, 2));
    int day = (int)StringToInteger(StringSubstr(datePart, 8, 2));
    
    // Parse time (HH:MM)
    int hour = (int)StringToInteger(StringSubstr(timePart, 0, 2));
    int minute = (int)StringToInteger(StringSubstr(timePart, 3, 2));
    
    // Create MqlDateTime structure
    MqlDateTime dt;
    dt.year = year;
    dt.mon = month;
    dt.day = day;
    dt.hour = hour;
    dt.min = minute;
    dt.sec = 0;
    
    return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Check if current time is near any high-impact news event         |
//| Uses local CSV data - works in backtesting                       |
//+------------------------------------------------------------------+
bool IsNearLocalNews(datetime checkTime = 0) {
    if (!ENABLE_NEWS_FILTER) return false;
    
    if (checkTime == 0) checkTime = TimeCurrent();
    
    // Per-minute cache: news granularity is per-minute, result cannot change within same minute
    datetime currentMinute = checkTime / 60;
    if (currentMinute == g_isNearNewsCacheMinute && g_isNearNewsCacheMinute > 0) {
        return g_isNearNewsCacheResult;
    }
    
    if (g_localNewsCount == 0 && !g_newsFileLoadAttempted) {
        LoadLocalNewsFromCSV();
    }
    
    if (g_localNewsCount == 0) {
        g_isNearNewsCacheMinute = currentMinute;
        g_isNearNewsCacheResult = false;
        return false;
    }
    
    int bufferBefore = NEWS_MINUTES_BEFORE * 60;
    int bufferAfter = NEWS_MINUTES_AFTER * 60;
    
    // Binary search: find first event where time >= checkTime - bufferAfter
    datetime windowStart = checkTime - (datetime)bufferAfter;
    int lo = 0, hi = g_localNewsCount - 1, startIdx = g_localNewsCount;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        if (g_localNews[mid].time >= windowStart) {
            startIdx = mid;
            hi = mid - 1;
        } else {
            lo = mid + 1;
        }
    }
    
    bool result = false;
    for (int i = startIdx; i < g_localNewsCount; i++) {
        int timeDiff = (int)(g_localNews[i].time - checkTime);
        
        // Stop scanning if events are too far in the future
        if (timeDiff > bufferBefore) break;
        
        // Check if within the avoidance window (already filtered to high-impact at load time)
        if (timeDiff >= -bufferAfter && timeDiff <= bufferBefore) {
            if (showDebug) {
                int minutesUntil = timeDiff / 60;
                string timeStr = (minutesUntil >= 0) ? 
                    ("in " + IntegerToString(minutesUntil) + " min") : 
                    (IntegerToString(-minutesUntil) + " min ago");
                Print("LOCAL NEWS FILTER: Blocking - HIGH impact '", 
                      g_localNews[i].event, "' ", timeStr);
            }
            result = true;
            break;
        }
    }
    
    g_isNearNewsCacheMinute = currentMinute;
    g_isNearNewsCacheResult = result;
    return result;
}

//+------------------------------------------------------------------+
//| Get next upcoming high-impact news event                         |
//+------------------------------------------------------------------+
bool GetNextHighImpactNews(datetime checkTime, datetime &newsTime, string &newsEvent) {
    // Per-minute cache: result cannot change within the same minute
    datetime currentMinute = checkTime / 60;
    if (currentMinute == g_nextNewsCacheMinute && g_nextNewsCacheMinute > 0) {
        if (g_nextNewsCacheFound) {
            newsTime = g_nextNewsCacheTime;
            newsEvent = g_nextNewsCacheEvent;
        }
        return g_nextNewsCacheFound;
    }
    
    if (g_localNewsCount == 0 && !g_newsFileLoadAttempted) {
        LoadLocalNewsFromCSV();
    }
    
    // Binary search: find first event where time > checkTime (already high-impact only)
    int lo = 0, hi = g_localNewsCount - 1, startIdx = g_localNewsCount;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        if (g_localNews[mid].time > checkTime) {
            startIdx = mid;
            hi = mid - 1;
        } else {
            lo = mid + 1;
        }
    }
    
    bool found = (startIdx < g_localNewsCount);
    
    g_nextNewsCacheMinute = currentMinute;
    g_nextNewsCacheFound = found;
    if (found) {
        g_nextNewsCacheTime = g_localNews[startIdx].time;
        g_nextNewsCacheEvent = g_localNews[startIdx].event;
        newsTime = g_nextNewsCacheTime;
        newsEvent = g_nextNewsCacheEvent;
    }
    
    return found;
}

//+------------------------------------------------------------------+
//| Get minutes until next high-impact news                          |
//| Returns -1 if no upcoming news within 24 hours                   |
//+------------------------------------------------------------------+
int GetMinutesUntilNextNews(datetime checkTime = 0) {
    if (checkTime == 0) checkTime = TimeCurrent();
    
    datetime newsTime;
    string newsEvent;
    
    if (GetNextHighImpactNews(checkTime, newsTime, newsEvent)) {
        int seconds = (int)(newsTime - checkTime);
        if (seconds > 0 && seconds < 86400) {  // Within 24 hours
            return seconds / 60;
        }
    }
    
    return -1;
}

//+------------------------------------------------------------------+
//| Check if should close positions before news (local version)      |
//+------------------------------------------------------------------+
bool ShouldCloseForLocalNews(datetime checkTime = 0) {
    if (!ENABLE_NEWS_FILTER) return false;
    
    if (checkTime == 0) checkTime = TimeCurrent();
    
    datetime newsTime;
    string newsEvent;
    
    if (GetNextHighImpactNews(checkTime, newsTime, newsEvent)) {
        int secondsUntil = (int)(newsTime - checkTime);
        
        // Close positions NEWS_MINUTES_BEFORE before high impact news
        if (secondsUntil > 0 && secondsUntil <= NEWS_MINUTES_BEFORE * 60) {
            if (showDebug) {
                Print("LOCAL NEWS: Should close positions - '", newsEvent, 
                      "' in ", (secondsUntil / 60), " minutes");
            }
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Initialize local news filter (call in OnInit)                    |
//+------------------------------------------------------------------+
void InitLocalNewsFilter() {
    g_localNewsCount = 0;
    g_newsFileLoadAttempted = false;
    ArrayResize(g_localNews, 0);
    
    // Reset per-minute caches
    g_isNearNewsCacheMinute = 0;
    g_isNearNewsCacheResult = false;
    g_nextNewsCacheMinute = 0;
    g_nextNewsCacheFound = false;
    g_nextNewsCacheTime = 0;
    g_nextNewsCacheEvent = "";
    
    int loaded = LoadLocalNewsFromCSV();
    
    if (loaded > 0) {
        Print("LOCAL NEWS FILTER: Initialized with ", loaded, " high-impact events");
        
        // Show next 3 upcoming events (already filtered to high-impact at load time)
        datetime currentTime = TimeCurrent();
        int shown = 0;
        for (int i = 0; i < g_localNewsCount && shown < 3; i++) {
            if (g_localNews[i].time > currentTime) {
                int minutesUntil = (int)((g_localNews[i].time - currentTime) / 60);
                Print("  - Next: ", g_localNews[i].event, " in ", minutesUntil, " minutes");
                shown++;
            }
        }
    } else {
        Print("LOCAL NEWS FILTER: No events loaded. Copy HighImpactNews_USD.csv to MQL5/Files/KenKem/");
    }
}

//+------------------------------------------------------------------+
//| Unified news check - uses local CSV, falls back to API           |
//+------------------------------------------------------------------+
bool IsNearAnyNews() {
    // Use local CSV if loaded (works in backtesting)
    if (g_localNewsCount > 0) {
        return IsNearLocalNews();
    }
    
    // Try loading once if not yet attempted
    if (!g_newsFileLoadAttempted && LoadLocalNewsFromCSV() > 0) {
        return IsNearLocalNews();
    }
    
    // Fallback to MT5 calendar API (live trading only)
    return IsNearImportantNews();
}
//+------------------------------------------------------------------+
