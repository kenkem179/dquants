// KenKem P4a — decision-time indicator snapshot (the distilled CachedIndicators).
//
// DESIGN NOTE (de-bloat): the original EA reads a mix of shift-0 (forming) and shift-1 (closed) bars.
// This minimal redesign reads EVERYTHING at shift 1 (last CLOSED bar) — clean, deterministic, and
// strictly no-lookahead. We are NOT byte-matching the MT5 EA (the user authorized distilling KenKem to
// its essential winning core), so the value comes from a real validated edge, not buffer parity.
//
// Built once per forming M1 bar B. `align` gives each TF's forming index at open_time(B); shift 1 =
// align.tf - 1 = that TF's last closed bar.
#pragma once
#include "kk/kenkem/tf_cache.hpp"
#include "kk/kenkem/kenkem_config.hpp"
#include <algorithm>

namespace kk::kenkem {

struct Snapshot {
    // ADX(14)/DI per TF [M1,M3,M5,M15] at shift 1.
    double adx[4]  = {0,0,0,0};
    double diP[4]  = {0,0,0,0};
    double diM[4]  = {0,0,0,0};
    // M1 ADX(9) "short".
    double adxS = 0, diPS = 0, diMS = 0;
    // M1 EMA0..4 at shift 1 (for SL structure + sideways).
    double emaM1[5] = {0,0,0,0,0};
    double atrM1 = 0;        // M1 ATR(14) shift 0 (forming bar)
    double rsiM1 = 50;       // M1 RSI(14) RAW at shift 1 — GetRSIValue (conviction/sideways logic)
    double rsiM1_avg5 = 50;  // M1 mean of RSI shifts 0..4 — GetRSIAverage (the trace `rsi` column only)
    double closeM1 = 0, highM1 = 0, lowM1 = 0;   // M1 bar shift 1 OHLC
    // Ichimoku: current cloud = TK lines (EA buffer 0/1); real Senkou cloud (buffer 2/3) for E4 quality.
    double tenkanM1 = 0, kijunM1 = 0;
    double senkouA_M3 = 0, senkouB_M3 = 0;     // M3 real Senkou A/B "current" cloud (EA buf 2/3 → TK-align)
    double tenkanM3 = 0, kijunM3 = 0;          // M3 real Tenkan/Kijun (EA buf 0/1 → E4 cloud THICKNESS)
    double atrM3 = 0;                          // M3 ATR(14) shift-0 forming (E4 cloud-thickness threshold)
    // Regime.
    int    sideways = 0;          // 0-100 chop score
    double atr_pctile = 50.0;     // ATR percentile over lookback
    bool   valid = false;
};

// ATR percentile — faithful port of CalculateATRPercentile (RiskManager.mqh:215). MT5 copies the ATR
// buffer at shifts 1..lookback (CopyBuffer start=1, count=lookback) and counts how many are strictly
// below the FORMING-bar ATR (cache.atrM1 = shift 0). So the distribution INCLUDES the last closed bar
// (shift 1 = ref_idx) and spans `lookback` bars ending at ref_idx. ref_atr = s.atrM1 (forming step).
inline double atr_percentile(const TfIndicators& m1, int ref_idx, double ref_atr, int lookback) {
    if (lookback <= 0 || ref_atr <= 0.0 || ref_idx < 0) return 50.0;
    int below = 0, n = 0;
    for (int i = ref_idx; i >= 0 && n < lookback; --i, ++n)
        if (m1.atr[i] < ref_atr) ++below;
    return n > 0 ? (double)below / (double)n * 100.0 : 50.0;
}

// Sideways score 0-100 (distilled from TrendIdentifier GetSidewaysScore): EMA convergence(25) +
// ADX weakness(25) + DI indecision(20) + RSI neutral(15) + ATR compression(15). Single shift-1 reads.
inline int sideways_score(const Snapshot& s, const KenKemConfig& cfg) {
    int score = 0;
    // 1. EMA convergence (EMA1..4 band width in ATR units).
    double mx = std::max({s.emaM1[1], s.emaM1[2], s.emaM1[3], s.emaM1[4]});
    double mn = std::min({s.emaM1[1], s.emaM1[2], s.emaM1[3], s.emaM1[4]});
    double spread = (s.atrM1 > 0) ? (mx - mn) / s.atrM1 : 999.0;
    if (spread < cfg.ema_spread_tight_atr)         score += 25;
    else if (spread < cfg.ema_spread_moderate_atr) score += 15;
    else if (spread < cfg.ema_spread_wide_atr)     score += 8;
    // 2. ADX weakness (M1 + M3).
    int adxScore = 0;
    if (s.adx[0] < 15)      adxScore += 15;
    else if (s.adx[0] < 20) adxScore += 10;
    else if (s.adx[0] < 25) adxScore += 5;
    if (s.adx[1] < 18)      adxScore += 10;
    else if (s.adx[1] < 22) adxScore += 5;
    score += std::min(25, adxScore);
    // 3. DI indecision (M1).
    double di = std::fabs(s.diP[0] - s.diM[0]);
    if (di < 2.0)      score += 12;
    else if (di < 4.0) score += 8;
    else if (di < 6.0) score += 4;
    // 4. RSI neutral.
    double r = s.rsiM1;
    if (r >= 45 && r <= 55)      score += 15;
    else if (r >= 40 && r <= 60) score += 10;
    else if (r >= 35 && r <= 65) score += 5;
    // 5. ATR compression.
    if (s.atr_pctile < 15)      score += 15;
    else if (s.atr_pctile < 25) score += 10;
    else if (s.atr_pctile < 35) score += 5;
    return score;
}

// Build the snapshot for forming M1 bar B. Requires shift-1 available on M1 (align.m1 >= 1).
inline Snapshot build_snapshot(const TfBundle& b, const KenKemConfig& cfg, int B,
                               const TfBundle::Align& align) {
    Snapshot s;
    const int i1 = align.m1 - 1;
    if (i1 < 0) return s;   // no closed M1 bar yet
    (void)B;

    const TfIndicators* tf[4] = { &b.m1, &b.m3, &b.m5, &b.m15 };
    const int idx[4] = { align.m1 - 1, align.m3 - 1, align.m5 - 1, align.m15 - 1 };
    for (int t = 0; t < 4; ++t) {
        int j = idx[t];
        s.adx[t] = TfIndicators::get(tf[t]->adx, j);
        s.diP[t] = TfIndicators::get(tf[t]->diP, j);
        s.diM[t] = TfIndicators::get(tf[t]->diM, j);
    }
    // adxS/diPS/diMS: the EA's E5 trace mirrors the M1 ADX(14) into these columns (they are NOT
    // separate-period gate inputs), so mirror M1 here for parity rather than computing ADX(9).
    s.adxS = s.adx[0]; s.diPS = s.diP[0]; s.diMS = s.diM[0];

    // FAITHFUL SHIFTS (decoded from KenKemExpert.mq5 — see research/kenkem_parity/INDICATOR_PARITY_SPEC.md):
    //  - EMA: GetEMA(...,ENTRY_SHIFT) reads a NON-series CopyBuffer(...,0,ENTRY_SHIFT+3) at index 1,
    //    which lands 2 closed bars behind `close` (empirically ema[i] == EMA(close)[i-2]). → i1-2.
    //  - close: iClose(...,ENTRY_SHIFT) = last CLOSED bar = i1.
    //  - ATR/RSI/high/low: read at shift 0 (the FORMING bar) — at the first tick of a new bar
    //    O=H=L=C=open, so model the forming bar as a single point at its open (no lookahead).
    for (int e = 0; e < 5; ++e) s.emaM1[e] = TfIndicators::get(b.m1.ema[e], i1 - 2);

    const int fi = align.m1;                      // forming-bar index (shift 0)
    const bool has_form = (fi >= 0 && fi < b.m1.size());
    const double open_f = has_form ? b.m1.bars[fi].open : b.m1.bars[i1].close;
    const double prevC  = b.m1.bars[i1].close;

    // ATR shift-0: one Wilder (SMMA) step from the closed-bar ATR using the forming-bar TR.
    // Forming bar at first tick has H=L=open, so TR = |open - prevClose|.
    {
        const double atr_closed = TfIndicators::get(b.m1.atr, i1);
        const double tr_form = std::fabs(open_f - prevC);
        const int n = KENKEM_CACHE_ATR_PERIOD;
        s.atrM1 = (atr_closed > 0.0) ? (atr_closed * (n - 1) + tr_form) / n : atr_closed;
    }

    // RSI: TWO distinct reads in the EA, kept separate here.
    //  - LOGIC (conviction C3, sideways): GetRSIValue(TF0,14,ENTRY_SHIFT) = RAW iRSI at shift 1 = rsi[i1].
    //  - TRACE column only: GetRSIAverage(TF0,RSI_LEN,5) = mean of iRSI shifts 0..4 (forming + 4 closed),
    //    counting only values > 0. Forming (shift 0) uses one Wilder step on the gap open-prevClose.
    if (b.m1.has_rsi) {
        s.rsiM1 = TfIndicators::get(b.m1.rsi, i1);
        const int n = cfg.rsi_len;
        double rsi_form = kk::ind::rsi_wilder_step(
            TfIndicators::get(b.m1.rsi_ag, i1), TfIndicators::get(b.m1.rsi_al, i1), prevC, open_f, n);
        double vals[5] = { rsi_form,
                           TfIndicators::get(b.m1.rsi, i1),
                           TfIndicators::get(b.m1.rsi, i1 - 1),
                           TfIndicators::get(b.m1.rsi, i1 - 2),
                           TfIndicators::get(b.m1.rsi, i1 - 3) };
        double sum = 0.0; int cnt = 0;
        for (double v : vals) if (v > 0.0) { sum += v; ++cnt; }
        s.rsiM1_avg5 = cnt > 0 ? sum / cnt : 0.0;
    } else { s.rsiM1 = 50.0; s.rsiM1_avg5 = 50.0; }

    // close = last closed bar; high/low = forming bar (shift 0) which is a single point at its open.
    s.closeM1 = prevC;
    s.highM1 = open_f; s.lowM1 = open_f;
    if (b.m1.has_ichi) { s.tenkanM1 = TfIndicators::get(b.m1.ichi.tenkan, i1); s.kijunM1 = TfIndicators::get(b.m1.ichi.kijun, i1); }
    if (b.m3.has_ichi) {
        int j3 = align.m3 - 1;
        s.senkouA_M3 = TfIndicators::get(b.m3.ichi.span_a_cur, j3);   // EA "Tenkan_M3" (buf2) → TK-align
        s.senkouB_M3 = TfIndicators::get(b.m3.ichi.span_b_cur, j3);   // EA "Kijun_M3"  (buf3)
        s.tenkanM3   = TfIndicators::get(b.m3.ichi.tenkan, j3);       // EA "SpanA_M3_Current" (buf0) → thickness
        s.kijunM3    = TfIndicators::get(b.m3.ichi.kijun,  j3);       // EA "SpanB_M3_Current" (buf1)
    }
    // M3 ATR shift-0 forming (one Wilder step from closed M3 ATR using the M3 forming-bar gap TR).
    {
        const int fj = align.m3, jj = align.m3 - 1;
        if (jj >= 0) {
            const double atr_c = TfIndicators::get(b.m3.atr, jj);
            const double opf = (fj >= 0 && fj < b.m3.size()) ? b.m3.bars[fj].open : b.m3.bars[jj].close;
            const double trf = std::fabs(opf - b.m3.bars[jj].close);
            const int n = KENKEM_CACHE_ATR_PERIOD;
            s.atrM3 = (atr_c > 0.0) ? (atr_c * (n - 1) + trf) / n : atr_c;
        }
    }
    // ATR percentile reference: the EA reads cache.atrM1 at ENTRY time (mid-bar, not first tick), so its
    // reference reflects the bar's realized range — empirically ≈ the CLOSED-bar ATR (atr[i1]), NOT the
    // first-tick forming model (which is systematically ~7% low and drags the percentile down, wrongly
    // tripping the MIN_ENTRY_ATR_PERCENTILE/ATR_HIGH gates). Intrabar exactness is unreachable from M1
    // bars; the closed-bar ATR is the faithful-in-spirit, MT5-tracking proxy. See research/kenkem_parity.
    s.atr_pctile = atr_percentile(b.m1, i1, TfIndicators::get(b.m1.atr, i1), cfg.atr_percentile_lookback);
    s.sideways = sideways_score(s, cfg);
    s.valid = true;
    return s;
}

}  // namespace kk::kenkem
