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
    double atrM1 = 0;        // M1 ATR(14) shift 1
    double rsiM1 = 50;       // M1 RSI(14) shift 1
    double closeM1 = 0, highM1 = 0, lowM1 = 0;   // M1 bar shift 1 OHLC
    // Ichimoku: current cloud = TK lines (EA buffer 0/1); real Senkou cloud (buffer 2/3) for E4 quality.
    double tenkanM1 = 0, kijunM1 = 0;
    double senkouA_M3 = 0, senkouB_M3 = 0;
    // Regime.
    int    sideways = 0;          // 0-100 chop score
    double atr_pctile = 50.0;     // ATR percentile over lookback
    bool   valid = false;
};

// ATR percentile: % of the last `lookback` closed-bar ATRs strictly below the reference ATR.
inline double atr_percentile(const TfIndicators& m1, int ref_idx, double ref_atr, int lookback) {
    if (lookback <= 0 || ref_atr <= 0.0 || ref_idx < 1) return 50.0;
    int below = 0, n = 0;
    for (int i = ref_idx - 1; i >= 0 && n < lookback; --i, ++n)
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
    s.adxS = TfIndicators::get(b.m1.adxS, i1);
    s.diPS = TfIndicators::get(b.m1.diPS, i1);
    s.diMS = TfIndicators::get(b.m1.diMS, i1);
    for (int e = 0; e < 5; ++e) s.emaM1[e] = TfIndicators::get(b.m1.ema[e], i1);
    s.atrM1 = TfIndicators::get(b.m1.atr, i1);
    s.rsiM1 = b.m1.has_rsi ? TfIndicators::get(b.m1.rsi, i1) : 50.0;
    s.closeM1 = b.m1.bars[i1].close; s.highM1 = b.m1.bars[i1].high; s.lowM1 = b.m1.bars[i1].low;
    if (b.m1.has_ichi) { s.tenkanM1 = TfIndicators::get(b.m1.ichi.tenkan, i1); s.kijunM1 = TfIndicators::get(b.m1.ichi.kijun, i1); }
    if (b.m3.has_ichi) {
        int j3 = align.m3 - 1;
        s.senkouA_M3 = TfIndicators::get(b.m3.ichi.span_a_cur, j3);
        s.senkouB_M3 = TfIndicators::get(b.m3.ichi.span_b_cur, j3);
    }
    s.atr_pctile = atr_percentile(b.m1, i1, s.atrM1, cfg.atr_percentile_lookback);
    s.sideways = sideways_score(s, cfg);
    s.valid = true;
    return s;
}

}  // namespace kk::kenkem
