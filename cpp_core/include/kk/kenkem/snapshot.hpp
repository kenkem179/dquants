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
    // FORMING-bar (shift-0) ADX/DI per TF — the value MT5's iADX returns at buffer index 0 on the M1
    // detection tick (HasTrendAcceleration / IsAccelerating read shift 0). For M1 this is the first-tick
    // H=L=C=open bar; for M3/M5/M15 it is the partially-accumulated current-bucket bar (aggregated from
    // the CLOSED M1 bars in the bucket). Acceleration checks read {forming, shift1, shift2}. Defaults to
    // the shift-1 closed value so an un-set TF degrades to the old closed-window behaviour.
    double adxF[4] = {0,0,0,0};
    double diPF[4] = {0,0,0,0};
    double diMF[4] = {0,0,0,0};
    // M1 ADX(9) "short".
    double adxS = 0, diPS = 0, diMS = 0;
    // M1 EMA0..4 at shift 1 (for SL structure + sideways).
    double emaM1[5] = {0,0,0,0,0};
    double atrM1 = 0;        // M1 ATR(14) shift 0 (forming bar) — used by sideways/atr_pctile (per-bar, validated)
    double atrM1_sl = 0;     // M1 ATR(14) LAST CLOSED bar — used ONLY for compute_sl arbitration. The EA's
                             // cache.atrM1=iATR(0) is read on the first tick of the new bar, by which time the
                             // forming bar already carries a few ticks of REAL range; the engine's first-tick
                             // forming step instead uses TR=|open-prevClose|≈0, mechanically shrinking ATR by
                             // ~1/14 (≈7%). Empirically (78 E1 entries vs 1.8.154 trace) the last-closed-bar
                             // Wilder ATR matches MT5's atr at entry bars (median ratio 1.003 vs forming 0.933),
                             // and since the 4.0× ATR-SL CAP binds on most E1 trades, the forming shrink fed a
                             // ~7% TIGHT SL. See HANDOFF "SL/TP LEVELS" diagnosis.
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
    //  - EMA (v1.8.154): GetEMA(...,1) reads NON-series CopyBuffer(emaHandle,0,0,ENTRY_SHIFT+3=4,tmp)
    //    then tmp[1]. start=0,count=4 non-series => tmp[3]=shift0..tmp[1]=shift2. So EA EMA == series-
    //    shift 2 == i1-1. Verified bit-exact (0.00000) vs the 1.8.154 trace (periods 10/25/71/97/192).
    //  - close: iClose(...,ENTRY_SHIFT) = last CLOSED bar = i1.
    //  - ATR/RSI/high/low: read at shift 0 (the FORMING bar) — at the first tick of a new bar
    //    O=H=L=C=open, so model the forming bar as a single point at its open (no lookahead).
    for (int e = 0; e < 5; ++e) s.emaM1[e] = TfIndicators::get(b.m1.ema[e], i1 - 1);

    const int fi = align.m1;                      // forming-bar index (shift 0)
    const bool has_form = (fi >= 0 && fi < b.m1.size());
    const double open_f = has_form ? b.m1.bars[fi].open : b.m1.bars[i1].close;
    const double prevC  = b.m1.bars[i1].close;

    // FORMING-bar (shift-0) ADX/DI per TF — what MT5's iADX returns at buffer index 0 on the M1 detection
    // tick, used by HasTrendAcceleration / IsAccelerating (read {shift0,1,2}). Default to the shift-1
    // closed value, then overwrite with one Wilder forming step where history allows. For M1 the bucket is
    // its own first-tick (H=L=C=open_f); for M3/M5/M15 the forming bar = the CLOSED M1 bars accumulated in
    // the current HTF bucket (+ the first tick), so the partial bar is reconstructed WITHOUT lookahead
    // (it never reads the complete b.m{3,5,15} bar at align.tf, which already contains future M1 data).
    for (int t = 0; t < 4; ++t) { s.adxF[t] = s.adx[t]; s.diPF[t] = s.diP[t]; s.diMF[t] = s.diM[t]; }
    {
        const int alignTf[4] = { align.m1, align.m3, align.m5, align.m15 };
        for (int t = 0; t < 4; ++t) {
            const TfIndicators& T = *tf[t];
            const int fIdx = alignTf[t];          // forming HTF bar index (the bucket containing t_F)
            const int ci   = fIdx - 1;            // last CLOSED HTF bar (the Wilder step's prev state)
            if (ci < 1 || fIdx >= T.size()) continue;
            const int64_t bucketOpen = T.bars[fIdx].ts_ms;
            double fH = open_f, fL = open_f;      // include the forming M1 first tick (= open_f)
            for (int j = i1; j >= 0; --j) {       // accumulate CLOSED M1 bars in this bucket
                if (b.m1.bars[j].ts_ms < bucketOpen) break;
                fH = std::max(fH, b.m1.bars[j].high);
                fL = std::min(fL, b.m1.bars[j].low);
            }
            const kk::ind::DmiStep st = kk::ind::dmi_adx_mt5_form_bar(
                T.bars[ci].high, T.bars[ci].low, T.bars[ci].close,
                T.diP[ci], T.diM[ci], T.adx[ci], fH, fL, open_f, cfg.adx_len);
            s.adxF[t] = st.adx; s.diPF[t] = st.plus_di; s.diMF[t] = st.minus_di;
        }
    }

    // ATR shift-0: MT5 iATR(0) is a rolling SMA of TR, so the forming bar slides the n-window by one —
    // add the forming-bar TR and drop the oldest closed TR: atr0 = atr_closed + (tr_form - tr[i1-(n-1)])/n.
    // (NOT a Wilder step.) Forming bar at first tick has H=L=open, so tr_form = |open - prevClose|.
    // Verified to match MT5's per-bar forming ATR to <1e-4 over 848,532 bars.
    {
        const double atr_closed = TfIndicators::get(b.m1.atr, i1);   // SMA(TR,14) at last closed bar
        const double tr_form = std::fabs(open_f - prevC);
        const int n = KENKEM_CACHE_ATR_PERIOD;
        const double tr_drop = TfIndicators::get(b.m1.tr, i1 - (n - 1));  // oldest TR leaving the window
        s.atrM1 = (atr_closed > 0.0) ? atr_closed + (tr_form - tr_drop) / n : atr_closed;
        s.atrM1_sl = atr_closed;   // last-closed-bar SMA iATR(14) for SL arbitration (see field comment)
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
    // M3 ATR shift-0 forming: MT5 iATR(0) SMA window-slide from closed M3 ATR using the M3 forming gap TR.
    {
        const int fj = align.m3, jj = align.m3 - 1;
        if (jj >= 0) {
            const double atr_c = TfIndicators::get(b.m3.atr, jj);
            const double opf = (fj >= 0 && fj < b.m3.size()) ? b.m3.bars[fj].open : b.m3.bars[jj].close;
            const double trf = std::fabs(opf - b.m3.bars[jj].close);
            const int n = KENKEM_CACHE_ATR_PERIOD;
            const double tr_drop = TfIndicators::get(b.m3.tr, jj - (n - 1));
            s.atrM3 = (atr_c > 0.0) ? atr_c + (trf - tr_drop) / n : atr_c;
        }
    }
    // ATR percentile (v1.8.154 CalculateATRPercentile, RiskManager.mqh:215): currentATR = cache.atrM1
    // = the FORMING-bar ATR (shift 0) = s.atrM1; distribution = closed ATR shifts 1..32 (ref_idx=i1),
    // counted strictly < currentATR, ×100/32. (The earlier closed-ref proxy was wrong; the EA uses
    // shift-0 forming as the reference, verified against the fresh 1.8.154 atr_pctile column.)
    s.atr_pctile = atr_percentile(b.m1, i1, s.atrM1, cfg.atr_percentile_lookback);
    s.sideways = sideways_score(s, cfg);
    s.valid = true;
    return s;
}

}  // namespace kk::kenkem
