//+------------------------------------------------------------------+
//|                                       NewsCalendarEmbedded.mqh    |
//|     KK-Common - GENERATED. High-impact USD news calendar embedded |
//|     as a string so the .ex5 is self-contained (MQL5 Market rule)  |
//|     even when no CSV is present in MQL5/Files/.                    |
//|                                                                   |
//|     DO NOT EDIT BY HAND. Regenerate from the source CSV:          |
//|       Data/HighImpactNews_USD.csv  ->  this file.                 |
//|     (#resource cannot be read back as text at runtime in MQL5,    |
//|      so the calendar is embedded as a string constant instead.)   |
//+------------------------------------------------------------------+
#property strict
#ifndef KKC_NEWSCALENDAR_EMBEDDED_MQH
#define KKC_NEWSCALENDAR_EMBEDDED_MQH

// Returns the embedded calendar as newline-separated CSV text (same format the
// filesystem CSV uses; the NewsFilter parser is identical for both paths).
string EmbeddedNewsCsv() {
   string s = "";
   s += "# High Impact USD News Events\n";
   s += "# Format: DateTime (UTC), Event Name, Impact, Actual, Forecast, Previous\n";
   s += "# Source: Forex Factory / Investing.com\n";
   s += "# Last Updated: 2026-02-14\n";
   s += "# Note: Add events manually or use scripts/download_news.py to update\n";
   s += "#\n";
   s += "# Common High Impact USD Events:\n";
   s += "# - FOMC Rate Decision (8x/year)\n";
   s += "# - Non-Farm Payrolls (monthly, first Friday)\n";
   s += "# - CPI (monthly)\n";
   s += "# - GDP (quarterly)\n";
   s += "# - Fed Chair Speech\n";
   s += "# - Unemployment Claims (weekly)\n";
   s += "# - Retail Sales (monthly)\n";
   s += "# - ISM Manufacturing PMI (monthly)\n";
   s += "# - Core PCE Price Index (monthly)\n";
   s += "\n";
   s += "DateTime,Event,Impact,Actual,Forecast,Previous\n";
   s += "2025-01-03 13:30,Non-Farm Payrolls,High,256K,160K,212K\n";
   s += "2025-01-10 13:30,CPI m/m,High,0.4%,0.3%,0.3%\n";
   s += "2025-01-10 13:30,Core CPI m/m,High,0.2%,0.3%,0.3%\n";
   s += "2025-01-15 13:30,Retail Sales m/m,High,0.4%,0.6%,0.8%\n";
   s += "2025-01-16 13:30,Unemployment Claims,High,217K,210K,201K\n";
   s += "2025-01-29 19:00,FOMC Statement,High,,,\n";
   s += "2025-01-29 19:00,Fed Interest Rate Decision,High,4.50%,4.50%,4.50%\n";
   s += "2025-01-30 13:30,GDP q/q,High,2.3%,2.6%,3.1%\n";
   s += "2025-01-31 13:30,Core PCE Price Index m/m,High,0.2%,0.2%,0.1%\n";
   s += "2025-02-07 13:30,Non-Farm Payrolls,High,143K,170K,307K\n";
   s += "2025-02-12 13:30,CPI m/m,High,0.5%,0.3%,0.4%\n";
   s += "2025-02-12 13:30,Core CPI m/m,High,0.4%,0.3%,0.2%\n";
   s += "2025-02-14 13:30,Retail Sales m/m,High,-0.9%,-0.1%,0.7%\n";
   s += "2025-02-21 14:45,Flash Manufacturing PMI,High,51.6,51.5,51.2\n";
   s += "2025-02-28 13:30,Core PCE Price Index m/m,High,0.3%,0.3%,0.2%\n";
   s += "2025-03-07 13:30,Non-Farm Payrolls,High,151K,160K,125K\n";
   s += "2025-03-12 12:30,CPI m/m,High,0.2%,0.3%,0.5%\n";
   s += "2025-03-12 12:30,Core CPI m/m,High,0.2%,0.3%,0.4%\n";
   s += "2025-03-19 18:00,FOMC Statement,High,,,\n";
   s += "2025-03-19 18:00,Fed Interest Rate Decision,High,4.50%,4.50%,4.50%\n";
   s += "2025-03-27 12:30,GDP q/q,High,2.4%,2.3%,2.3%\n";
   s += "2025-03-28 12:30,Core PCE Price Index m/m,High,0.4%,0.3%,0.3%\n";
   s += "2025-04-04 12:30,Non-Farm Payrolls,High,228K,135K,117K\n";
   s += "2025-04-10 12:30,CPI m/m,High,-0.1%,0.1%,0.2%\n";
   s += "2025-04-10 12:30,Core CPI m/m,High,0.1%,0.3%,0.2%\n";
   s += "2025-04-16 12:30,Retail Sales m/m,High,1.4%,1.3%,0.2%\n";
   s += "2025-04-30 12:30,GDP q/q,High,-0.3%,0.4%,2.4%\n";
   s += "2025-05-02 12:30,Non-Farm Payrolls,High,177K,138K,185K\n";
   s += "2025-05-07 18:00,FOMC Statement,High,,,\n";
   s += "2025-05-07 18:00,Fed Interest Rate Decision,High,4.50%,4.50%,4.50%\n";
   s += "2025-05-13 12:30,CPI m/m,High,0.2%,0.3%,-0.1%\n";
   s += "2025-05-13 12:30,Core CPI m/m,High,0.2%,0.3%,0.1%\n";
   s += "2025-05-15 12:30,Retail Sales m/m,High,0.1%,0.0%,1.7%\n";
   s += "2025-05-29 12:30,GDP q/q,High,-0.2%,-0.2%,-0.3%\n";
   s += "2025-05-30 12:30,Core PCE Price Index m/m,High,0.2%,0.2%,0.0%\n";
   s += "2025-06-06 12:30,Non-Farm Payrolls,High,272K,185K,165K\n";
   s += "2025-06-11 12:30,CPI m/m,High,0.0%,0.1%,0.2%\n";
   s += "2025-06-11 12:30,Core CPI m/m,High,0.2%,0.3%,0.2%\n";
   s += "2025-06-18 18:00,FOMC Statement,High,,,\n";
   s += "2025-06-18 18:00,Fed Interest Rate Decision,High,4.50%,4.50%,4.50%\n";
   s += "2025-06-26 12:30,GDP q/q,High,-0.2%,-0.2%,-0.2%\n";
   s += "2025-06-27 12:30,Core PCE Price Index m/m,High,0.1%,0.1%,0.2%\n";
   s += "2025-07-03 12:30,Non-Farm Payrolls,High,206K,190K,218K\n";
   s += "2025-07-10 12:30,CPI m/m,High,-0.1%,0.1%,0.0%\n";
   s += "2025-07-10 12:30,Core CPI m/m,High,0.1%,0.2%,0.2%\n";
   s += "2025-07-16 12:30,Retail Sales m/m,High,0.0%,0.0%,0.3%\n";
   s += "2025-07-30 12:30,GDP q/q,High,2.8%,2.0%,-0.2%\n";
   s += "2025-07-30 18:00,FOMC Statement,High,,,\n";
   s += "2025-07-30 18:00,Fed Interest Rate Decision,High,4.50%,4.50%,4.50%\n";
   s += "2025-07-31 12:30,Core PCE Price Index m/m,High,0.2%,0.2%,0.1%\n";
   s += "2025-08-01 12:30,Non-Farm Payrolls,High,114K,176K,179K\n";
   s += "2025-08-14 12:30,CPI m/m,High,0.2%,0.2%,-0.1%\n";
   s += "2025-08-14 12:30,Core CPI m/m,High,0.2%,0.2%,0.1%\n";
   s += "2025-08-15 12:30,Retail Sales m/m,High,1.0%,0.4%,0.0%\n";
   s += "2025-08-29 12:30,Core PCE Price Index m/m,High,0.2%,0.2%,0.2%\n";
   s += "2025-09-05 12:30,Non-Farm Payrolls,High,142K,161K,89K\n";
   s += "2025-09-11 12:30,CPI m/m,High,0.2%,0.2%,0.2%\n";
   s += "2025-09-11 12:30,Core CPI m/m,High,0.3%,0.2%,0.2%\n";
   s += "2025-09-17 12:30,Retail Sales m/m,High,0.1%,0.2%,1.1%\n";
   s += "2025-09-18 18:00,FOMC Statement,High,,,\n";
   s += "2025-09-18 18:00,Fed Interest Rate Decision,High,5.00%,5.25%,5.50%\n";
   s += "2025-09-26 12:30,GDP q/q,High,3.0%,3.0%,3.0%\n";
   s += "2025-09-27 12:30,Core PCE Price Index m/m,High,0.1%,0.2%,0.2%\n";
   s += "2025-10-04 12:30,Non-Farm Payrolls,High,254K,147K,159K\n";
   s += "2025-10-10 12:30,CPI m/m,High,0.2%,0.1%,0.2%\n";
   s += "2025-10-10 12:30,Core CPI m/m,High,0.3%,0.2%,0.3%\n";
   s += "2025-10-17 12:30,Retail Sales m/m,High,0.4%,0.3%,0.1%\n";
   s += "2025-10-30 12:30,GDP q/q,High,2.8%,3.0%,3.0%\n";
   s += "2025-10-31 12:30,Core PCE Price Index m/m,High,0.3%,0.3%,0.2%\n";
   s += "2025-11-01 12:30,Non-Farm Payrolls,High,12K,113K,223K\n";
   s += "2025-11-07 19:00,FOMC Statement,High,,,\n";
   s += "2025-11-07 19:00,Fed Interest Rate Decision,High,4.75%,4.75%,5.00%\n";
   s += "2025-11-13 13:30,CPI m/m,High,0.2%,0.2%,0.2%\n";
   s += "2025-11-13 13:30,Core CPI m/m,High,0.3%,0.3%,0.3%\n";
   s += "2025-11-15 13:30,Retail Sales m/m,High,0.4%,0.3%,0.8%\n";
   s += "2025-11-27 13:30,GDP q/q,High,2.8%,2.8%,2.8%\n";
   s += "2025-11-27 13:30,Core PCE Price Index m/m,High,0.3%,0.3%,0.3%\n";
   s += "2025-12-06 13:30,Non-Farm Payrolls,High,227K,214K,36K\n";
   s += "2025-12-11 13:30,CPI m/m,High,0.3%,0.3%,0.2%\n";
   s += "2025-12-11 13:30,Core CPI m/m,High,0.3%,0.3%,0.3%\n";
   s += "2025-12-17 13:30,Retail Sales m/m,High,0.7%,0.5%,0.7%\n";
   s += "2025-12-18 19:00,FOMC Statement,High,,,\n";
   s += "2025-12-18 19:00,Fed Interest Rate Decision,High,4.50%,4.50%,4.75%\n";
   s += "2025-12-20 13:30,Core PCE Price Index m/m,High,0.2%,0.2%,0.3%\n";
   s += "2025-12-23 13:30,GDP q/q,High,3.1%,2.8%,2.8%\n";
   s += "2026-01-10 13:30,Non-Farm Payrolls,High,256K,165K,212K\n";
   s += "2026-01-15 13:30,CPI m/m,High,0.4%,0.3%,0.3%\n";
   s += "2026-01-15 13:30,Core CPI m/m,High,0.2%,0.2%,0.3%\n";
   s += "2026-01-16 13:30,Retail Sales m/m,High,0.4%,0.5%,0.8%\n";
   s += "2026-01-29 19:00,FOMC Statement,High,,,\n";
   s += "2026-01-29 19:00,Fed Interest Rate Decision,High,4.50%,4.50%,4.50%\n";
   s += "2026-01-30 13:30,GDP q/q,High,2.3%,2.5%,3.1%\n";
   s += "2026-02-07 13:30,Non-Farm Payrolls,High,143K,175K,307K\n";
   s += "2026-02-12 13:30,CPI m/m,High,0.5%,0.3%,0.4%\n";
   s += "2026-02-12 13:30,Core CPI m/m,High,0.4%,0.2%,0.2%\n";
   s += "2026-02-14 13:30,Retail Sales m/m,High,-0.9%,0.0%,0.7%\n";
   s += "2026-03-06 13:30,Non-Farm Payrolls,High,,165K,143K\n";
   s += "2026-03-11 12:30,CPI m/m,High,,0.3%,0.5%\n";
   s += "2026-03-11 12:30,Core CPI m/m,High,,0.3%,0.4%\n";
   s += "2026-03-18 18:00,FOMC Statement,High,,,\n";
   s += "2026-03-18 18:00,Fed Interest Rate Decision,High,,4.50%,4.50%\n";
   s += "2026-03-27 12:30,GDP q/q,High,,2.3%,2.3%\n";
   s += "2026-04-03 12:30,Non-Farm Payrolls,High,,160K,\n";
   s += "2026-04-09 12:30,CPI m/m,High,,0.2%,\n";
   s += "2026-05-06 18:00,FOMC Statement,High,,,\n";
   s += "2026-05-06 18:00,Fed Interest Rate Decision,High,,,\n";
   s += "2026-06-17 18:00,FOMC Statement,High,,,\n";
   s += "2026-06-17 18:00,Fed Interest Rate Decision,High,,,\n";
   s += "2026-07-29 18:00,FOMC Statement,High,,,\n";
   s += "2026-07-29 18:00,Fed Interest Rate Decision,High,,,\n";
   s += "2026-09-16 18:00,FOMC Statement,High,,,\n";
   s += "2026-09-16 18:00,Fed Interest Rate Decision,High,,,\n";
   s += "2026-11-04 18:00,FOMC Statement,High,,,\n";
   s += "2026-11-04 18:00,Fed Interest Rate Decision,High,,,\n";
   s += "2026-12-16 19:00,FOMC Statement,High,,,\n";
   s += "2026-12-16 19:00,Fed Interest Rate Decision,High,,,\n";
   return s;
}

#endif // KKC_NEWSCALENDAR_EMBEDDED_MQH
