// KenKem P5 — distilled entry detection: trigger -> gate -> SL/TP. First-match-wins E1->E2->E4,
// long evaluated before short (the EA's dispatch order). Each entry keeps only its essential gates.
//
//   SL  = structure stop (min/max of recent-range & a custom-EMA level, offset by SL_EMA_DISTANCE),
//         arbitrated against ATR cap/floor, plus a spread buffer. Port of CalculateStopLossWithCustomEMA.
//   TP  = entry +/- finalRR * risk, finalRR per entry+direction (E4-short uses E4_RR_SHORT), with a
//         sideway-RR switch when the regime is in the warning band.
#pragma once
#include "kk/kenkem/triggers.hpp"
#include "kk/kenkem/gates.hpp"
#include "kk/kenkem/scoring.hpp"
#include "kk/kenkem/snapshot.hpp"
#include "kk/kenkem/kenkem_config.hpp"
#include <algorithm>
#include <cmath>

namespace kk::kenkem {

struct EntrySignal {
    bool   detected = false;
    bool   is_long  = false;
    int    kind     = 0;          // 1 (E1) / 2 (E2) / 4 (E4)
    double entry = 0, sl = 0, tp = 0, risk = 0;
};

// EA short-RR asymmetry factors (E1/E4 = 0.875, E2 = 0.867).
inline constexpr double KK_E1_SHORT_FACTOR = 0.875;
inline constexpr double KK_E2_SHORT_FACTOR = 0.867;
inline constexpr double KK_E4_SHORT_FACTOR = 0.875;

// recentHigh/recentLow over the last `lookback` closed M1 bars ending at idx (RANGE_HI_LOW_LOOK_BACK_BARS).
inline void recent_range(const TfIndicators& m1, int idx, int lookback, double& hi, double& lo) {
    hi = -1e300; lo = 1e300;
    int start = std::max(0, idx - lookback + 1);
    for (int i = start; i <= idx; ++i) { hi = std::max(hi, m1.bars[i].high); lo = std::min(lo, m1.bars[i].low); }
}

// Custom EMA structure level. E1/E4: ema100 +/- 0.75*|ema100-ema200|; E2: ema100; E5: ema200 (SuperBros).
inline double custom_ema_level(int kind, bool is_long, const Snapshot& s) {
    const double ema100 = s.emaM1[3], ema200 = s.emaM1[4];
    if (kind == 2) return ema100;
    if (kind == 5) return ema200;
    double d = std::fabs(ema100 - ema200) * 0.75;
    return is_long ? (ema100 - d) : (ema100 + d);
}

inline double atr_sl_caps(int kind, const KenKemConfig& c, double& floor_mult) {
    if (kind == 2) { floor_mult = c.e2_atr_sl_floor; return c.e2_atr_sl_cap; }
    if (kind == 4) { floor_mult = c.e4_atr_sl_floor; return c.e4_atr_sl_cap; }
    if (kind == 5) { floor_mult = c.e5_atr_sl_floor; return c.e5_atr_sl_cap; }
    floor_mult = c.e1_atr_sl_floor; return c.e1_atr_sl_cap;
}

// Stop loss price (CalculateStopLossWithCustomEMA). currentPrice = entry anchor (close[1]).
inline double compute_sl(int kind, bool is_long, double entry, const Snapshot& s,
                         double recentHi, double recentLo, const KenKemConfig& c) {
    const double emaLevel = custom_ema_level(kind, is_long, s);
    double baseSL = is_long ? std::min(recentLo, emaLevel) : std::max(recentHi, emaLevel);
    double stop   = is_long ? baseSL - c.sl_ema_distance * c.pip_size
                            : baseSL + c.sl_ema_distance * c.pip_size;
    // ATR arbitration (cap wide, floor tight).
    double floorMult, capMult = atr_sl_caps(kind, c, floorMult);
    if (s.atrM1 > 0.0) {
        double distP = std::fabs(entry - stop) / c.pip_size;
        double atrP  = s.atrM1 / c.pip_size;
        double finalP = distP;
        if (finalP > atrP * capMult)   finalP = atrP * capMult;
        if (finalP < atrP * floorMult) finalP = atrP * floorMult;
        if (finalP != distP) stop = is_long ? entry - finalP * c.pip_size : entry + finalP * c.pip_size;
    }
    return stop;
}

inline double per_side_rr(int kind, bool is_long, const Snapshot& s, const KenKemConfig& c) {
    bool sideway = (s.sideways >= c.sideways_warning_thr);   // warning band (block band already filtered)
    if (kind == 2) {
        if (sideway) return c.e2_rr_sideway;
        return is_long ? c.e2_rr : c.e2_rr * KK_E2_SHORT_FACTOR;
    }
    if (kind == 4) {
        if (sideway) return c.e4_rr_sideway;
        return is_long ? c.e4_rr : c.e4_rr_short * KK_E4_SHORT_FACTOR;
    }
    if (kind == 5) {
        if (sideway) return c.e5_rr_sideway;
        return c.e5_rr;   // E5 has no short-RR asymmetry input
    }
    if (sideway) return c.e1_rr_sideway;
    return is_long ? c.e1_rr : c.e1_rr * KK_E1_SHORT_FACTOR;
}

inline double compute_tp(int kind, bool is_long, double entry, double sl, const Snapshot& s,
                         const KenKemConfig& c) {
    double rr = per_side_rr(kind, is_long, s, c);
    double risk = std::fabs(entry - sl);
    return is_long ? entry + rr * risk : entry - rr * risk;
}

// Per-entry gate (essential filters only). dir true=long.
inline bool entry_gate_ok(int kind, bool is_long, const TfBundle& b, const Snapshot& s,
                          const TfBundle::Align& align, const KenKemConfig& c) {
    if (sideways_blocked(s, c)) return false;
    // Universal regime filter (MIN_ENTRY_ATR_PERCENTILE): the original EA only trades when current
    // ATR sits in the top (100 - thr)% of its recent distribution. This was DEFINED in config but
    // never wired into the distilled engine — its absence is a primary cause of over-trading in chop.
    // 0 disables. Applies to EVERY entry, including E5.
    if (c.min_entry_atr_pctile > 0.0 && s.atr_pctile < c.min_entry_atr_pctile) return false;
    // ATR HIGH block (ENABLE_ATR_HIGH_BLOCK / ATR_PERCENTILE_HIGH): the EA blackswan-blocks entries when
    // current ATR sits in the top of its distribution ("Market volatility is too high"). Previously
    // parsed-but-ignored. 0 disables.
    if (c.enable_atr_high_block && c.atr_percentile_high > 0.0 && s.atr_pctile > c.atr_percentile_high)
        return false;
    const double tol = c.ema_align_tol_pips * c.pip_size;
    // E5 (SuperBros): price on the right side of EMA25 + HTF + ADX floor. The original runs E5 with a
    // trend-quality floor (MIN_TREND_QUALITY_E5), so it is NOT exempt from the hard trend gate.
    if (kind == 5) {
        bool priceOk = is_long ? (s.closeM1 > s.emaM1[1]) : (s.closeM1 < s.emaM1[1]);
        if (!priceOk) return false;
        if (c.e5_require_trend_core && trend_core_score(s, is_long, c) == 0) return false;
        if (c.e5_min_momentum_adx > 0 && s.adx[0] < c.e5_min_momentum_adx) return false;
        return htf_filter_ok(s, is_long, c.e5_htf_filter, c.e5_htf_min_adx, c.e5_htf_min_di_spread);
    }
    if (trend_core_score(s, is_long, c) == 0) return false;          // hard gate (E1/E2/E4)
    // Selectivity filters the EA's .set turns on but the distilled engine parsed-and-ignored: full
    // 0-11 trend-quality minimum, conviction threshold (E2=10!), and the RSI-divergence veto. Their
    // absence was the primary cause of the dquants edition over-trading and losing. See scoring.hpp.
    if (!quality_filters_ok(kind, is_long, b, s, align, c)) return false;
    switch (kind) {
        case 1:  // E1: EMA alignment still holds (M1+M3) + M5 HTF
            if (!emas_ready(b.m1, align.m1 - 1, is_long, true, tol)) return false;
            if (!emas_ready(b.m3, align.m3 - 1, is_long, true, tol)) return false;
            return htf_filter_ok(s, is_long, c.e1_htf_filter, c.e1_htf_min_adx, c.e1_htf_min_di_spread);
        case 2:  // E2: alignment (M1+M3) + M15 HTF (momentum gate deliberately omitted)
            if (!emas_ready(b.m1, align.m1 - 1, is_long, true, tol)) return false;
            if (!emas_ready(b.m3, align.m3 - 1, is_long, true, tol)) return false;
            return htf_filter_ok(s, is_long, c.e2_htf_filter, c.e2_htf_min_adx, c.e2_htf_min_di_spread);
        case 4: { // E4: own ADX min + real-cloud (Senkou) agreement + M5/M15 HTF
            if (s.adx[0] < c.e4_min_momentum_adx) return false;
            bool cloudGreen = s.senkouA_M3 > s.senkouB_M3;
            if (c.e4_require_tenkan_kijun && (is_long ? !cloudGreen : cloudGreen)) return false;
            double thick = std::fabs(s.senkouA_M3 - s.senkouB_M3);
            if (c.e4_min_cloud_thick_atr > 0 && s.atrM1 > 0 && thick < c.e4_min_cloud_thick_atr * s.atrM1) return false;
            return htf_filter_ok(s, is_long, c.e4_htf_filter, c.e4_htf_min_adx, c.e4_htf_min_di_spread);
        }
    }
    return false;
}

// First-match-wins E1->E2->E4, long-before-short. B = forming M1 bar; entry anchor = close[1].
// CONSUMES the trigger that fires (resets it to -1) so one cross/touch == one entry — mirrors the EA
// (which clears lastEMACrossing/Touch/IchiCross on a successful build). `tg` is mutated on success.
inline EntrySignal detect_entry(const TfBundle& b, const KenKemConfig& c, int B,
                                const TfBundle::Align& align, const Snapshot& s,
                                TriggerState& tg) {
    EntrySignal r;
    if (!s.valid) return r;
    const int i1 = align.m1 - 1;
    if (i1 < 0) return r;
    double hi, lo; recent_range(b.m1, i1, c.range_hilo_lookback, hi, lo);
    const double entry = s.closeM1;

    struct Cand { int kind; bool en; int up; int down; int maxage; };
    const Cand cands[4] = {
        { 1, c.enable_e1, tg.ema_up,  tg.ema_down,  c.e1_max_cross_age },
        { 2, c.enable_e2, tg.e75_up,  tg.e75_down,  c.e2_max_touch_age },
        { 4, c.enable_e4, tg.ichi_up, tg.ichi_down, c.e4_max_cross_age },
        { 5, c.enable_e5, tg.e5_up,   tg.e5_down,   c.e5_max_ema_cross_age },
    };
    for (const Cand& cd : cands) {
        if (!cd.en) continue;
        for (int dir = 0; dir < 2; ++dir) {           // long (0) before short (1)
            bool is_long = (dir == 0);
            int fired = is_long ? cd.up : cd.down;
            if (fired < 0) continue;
            if (B - fired > cd.maxage) continue;       // stale trigger
            if (!entry_gate_ok(cd.kind, is_long, b, s, align, c)) continue;
            r.detected = true; r.is_long = is_long; r.kind = cd.kind; r.entry = entry;
            r.sl = compute_sl(cd.kind, is_long, entry, s, hi, lo, c);
            r.tp = compute_tp(cd.kind, is_long, entry, r.sl, s, c);
            r.risk = std::fabs(r.entry - r.sl);
            // consume the fired trigger (one cross/touch -> one entry)
            switch (cd.kind) {
                case 1: (is_long ? tg.ema_up  : tg.ema_down)  = -1; break;
                case 2: (is_long ? tg.e75_up  : tg.e75_down)  = -1; break;
                case 4: (is_long ? tg.ichi_up : tg.ichi_down) = -1; break;
                case 5: (is_long ? tg.e5_up   : tg.e5_down)   = -1; break;
            }
            return r;
        }
    }
    return r;
}

}  // namespace kk::kenkem
