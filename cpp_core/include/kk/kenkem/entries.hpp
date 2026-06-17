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
    int    age      = -1;         // DIAGNOSTIC: bars since the fired trigger was armed (B - fired)
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
// spread_price = live spread in price (used by the E5 EMA200 stop's 2*spread buffer).
inline double compute_sl(int kind, bool is_long, double entry, const Snapshot& s,
                         double recentHi, double recentLo, const KenKemConfig& c,
                         double spread_price = 0.0) {
    // E5 (SuperBros): pure EMA200 stop — Entry5.mqh. rawSL = ema200 -/+ 2*spread; slDist =
    // max(|entry-rawSL|, E5_MIN_SL_PIPS); ATR cap applied ONLY if E5_USE_ATR_SL_ARBITRATION.
    // No recentLo/Hi, no SL_EMA_DISTANCE offset (those are the E1/E2/E4 structure stop).
    if (kind == 5) {
        const double ema200 = s.emaM1[4];
        const double rawSL = is_long ? ema200 - 2.0 * spread_price : ema200 + 2.0 * spread_price;
        const double minSL = c.e5_min_sl_pips * c.pip_size;
        double slDist = std::max(std::fabs(entry - rawSL), minSL);
        if (c.e5_use_atr_sl_arb && s.atrM1 > 0.0) {
            double atrCap = c.e5_atr_sl_cap * s.atrM1;
            if (atrCap >= minSL && slDist > atrCap) slDist = atrCap;
        }
        return is_long ? entry - slDist : entry + slDist;
    }
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
    // NOTE (B1): the ATR-percentile regime filters (MIN_ENTRY_ATR_PERCENTILE / ENABLE_ATR_HIGH_BLOCK)
    // are NOT applied here. The EA evaluates them at EXECUTE (GetEntryBlockReason), AFTER detection has
    // already committed the bar's single slot to one entry type — so an ATR-failing E2 still SUPPRESSES
    // E4 on that bar instead of letting E4 fire. Applying them per-candidate inside detection (the old
    // behaviour) changed the E1->E2->E4 priority. The check now lives in risk_exec.hpp::entry_blocked_by_atr,
    // called once on the single detected candidate by the engine's execute stage.
    const double tol = c.ema_align_tol_pips * c.pip_size;
    // E5 (SuperBros): price on the right side of EMA25 + HTF + ADX floor. The original runs E5 with a
    // trend-quality floor (MIN_TREND_QUALITY_E5), so it is NOT exempt from the hard trend gate.
    if (kind == 5) {
        bool priceOk = is_long ? (s.closeM1 > s.emaM1[1]) : (s.closeM1 < s.emaM1[1]);
        if (!priceOk) return false;
        if (c.e5_require_trend_core && trend_core_score(s, is_long, c) == 0) return false;
        if (c.e5_min_momentum_adx > 0 && s.adx[0] < c.e5_min_momentum_adx) return false;
        // MIN_TREND_QUALITY_E5 (Entry5.mqh:204-220): GetTrendQualityScore(state,5) — no Ichimoku,
        // no per-component hard gate, 0-11. The distilled engine omitted this entirely (only checked
        // trend_core != 0) → a primary cause of E5 over-firing vs the EA. 0 disables.
        if (c.min_tq_e5 > 0 && trend_quality_score(b, align, s, is_long, 5, c) < c.min_tq_e5) return false;
        return htf_filter_ok(s, is_long, c.e5_htf_filter, c.e5_htf_min_adx, c.e5_htf_min_di_spread);
    }
    if (trend_core_score(s, is_long, c) == 0) return false;          // hard gate (E1/E2/E4)
    // Selectivity filters the EA's .set turns on but the distilled engine parsed-and-ignored: full
    // 0-11 trend-quality minimum, conviction threshold (E2=10!), and the RSI-divergence veto. Their
    // absence was the primary cause of the dquants edition over-trading and losing. See scoring.hpp.
    if (!quality_filters_ok(kind, is_long, b, s, align, c)) return false;
    switch (kind) {
        case 1: {  // E1 faithful gate — CheckE1EntryConditions_Internal (Entry1.mqh:215-314), IN ORDER.
            // E1.5 ADX floor (cache.adx[0] < E1_MIN_MOMENTUM_ADX).
            if (s.adx[0] < c.e1_min_momentum_adx) return false;
            // E1.6 HTF M5 block-COUNTER-only (NOT require-aligned).
            if (!htf_block_counter_ok(s, is_long, c.e1_htf_filter, c.e1_htf_min_adx, c.e1_htf_min_di_spread))
                return false;
            // E1.7 MTF EMA: m1_ready(strict) && ((m3_ready(strict) && m5_directional) || extremeMomentum).
            //   (E1_MOMENTUM_BYPASS_LEVEL=1; reads at the GetEMA entry shift align.tf-3.)
            {
                bool m1_ready = emas_ready_entry(b.m1, align.m1, is_long, true, tol);
                bool m3_ready = emas_ready_entry(b.m3, align.m3, is_long, true, tol);
                bool m5_dir   = m5_directional_ok(b.m5, align.m5, is_long);
                double m1di   = is_long ? (s.diP[0] - s.diM[0]) : (s.diM[0] - s.diP[0]);
                bool extreme  = m1di >= c.extreme_di_spread;
                bool pass;
                if (c.e1_momentum_bypass == 0)      pass = m1_ready && m3_ready && m5_dir;
                else if (c.e1_momentum_bypass == 1) pass = m1_ready && ((m3_ready && m5_dir) || extreme);
                else                                pass = m1_ready || extreme;
                if (!pass) return false;
            }
            // E1.8 price vs EMA25 (currentPrice = close[1]).
            if (is_long ? (s.closeM1 <= s.emaM1[1]) : (s.closeM1 >= s.emaM1[1])) return false;
            // E1.9 trend-quality, E1.11 RSI-div enforced by quality_filters_ok above.
            // E1.10 HasSufficientMomentum (E1 only).
            if (!has_sufficient_momentum(s, is_long, c)) return false;
            return true;
        }
        case 2: {  // E2 faithful gate — CheckE2EntryConditions_Internal (Entry2.mqh:192-274), IN ORDER.
            // E2.5 HTF M15 REQUIRE strong-aligned (direction must match) — htf_filter_ok = require-aligned.
            if (!htf_filter_ok(s, is_long, c.e2_htf_filter, c.e2_htf_min_adx, c.e2_htf_min_di_spread))
                return false;
            // E2.6 MTF EMA: m1 && m3 && m5 ALL strict (no momentum bypass), at the GetEMA entry shift.
            if (!emas_ready_entry(b.m1, align.m1, is_long, true, tol)) return false;
            if (!emas_ready_entry(b.m3, align.m3, is_long, true, tol)) return false;
            if (!emas_ready_entry(b.m5, align.m5, is_long, true, tol)) return false;
            // E2.7 price vs EMA25.
            if (is_long ? (s.closeM1 <= s.emaM1[1]) : (s.closeM1 >= s.emaM1[1])) return false;
            // E2.8 trend-quality(>=9), E2.10 RSI-div enforced by quality_filters_ok. HasSufficientMomentum
            // deliberately omitted for E2 (Entry2.mqh:263-266).
            return true;
        }
        case 4: { // E4 faithful gate — SPEC_E4 §4 Steps 0-4. (Step5 trend-quality≥9, Step6 RSI-div,
                  // post-detection conviction≥9 are already enforced by quality_filters_ok above.)
            // STEP 0 — Ichimoku quality (M3). Cloud THICKNESS uses REAL Tenkan/Kijun (EA buf0/1) vs
            // atrM3; the "Tenkan/Kijun align" check is actually REAL Senkou A/B (EA buf2/3) = cloud color.
            double thick = std::fabs(s.tenkanM3 - s.kijunM3);
            if (c.e4_min_cloud_thick_atr > 0.0 && s.atrM3 > 0.0 &&
                thick < c.e4_min_cloud_thick_atr * s.atrM3) return false;
            if (c.e4_require_tenkan_kijun) {
                bool cloudGreen = s.senkouA_M3 > s.senkouB_M3;
                if (is_long ? !cloudGreen : cloudGreen) return false;
            }
            // STEP 0.1 — E4 sideway block (stricter than the global 53 guard).
            if (s.sideways > c.e4_max_sideway_score) return false;
            // STEP 0.5 — HTF M5-OR-M15 directional BLOCK: block on any opposing VALID HTF.
            {
                double sp5 = s.diP[2] - s.diM[2], sp15 = s.diP[3] - s.diM[3];
                bool m5Valid  = s.adx[2] >= c.e4_htf_min_adx && std::fabs(sp5)  >= c.e4_htf_min_di_spread;
                bool m15Valid = s.adx[3] >= c.e4_htf_min_adx && std::fabs(sp15) >= c.e4_htf_min_di_spread;
                bool m5Bull = s.diP[2] > s.diM[2], m15Bull = s.diP[3] > s.diM[3];
                bool blockL = (m5Valid && !m5Bull) || (m15Valid && !m15Bull);
                bool blockS = (m5Valid &&  m5Bull) || (m15Valid &&  m15Bull);
                if (is_long ? blockL : blockS) return false;
            }
            // STEP 1 — M5 DI alignment (skip if M5 ranging: adx[2] < ADX_LOW_THRESHOLD).
            if (s.adx[2] >= c.adx_low_threshold) {
                if (is_long ? (s.diP[2] <= s.diM[2]) : (s.diM[2] <= s.diP[2])) return false;
            }
            // STEP 2 — EMA stack: M1 (25>71>97) ALWAYS + (M3 same OR extreme M1 DI spread >= 16).
            auto stk = [&](double e1,double e2,double e3){ return is_long ? (e1>e2 && e2>e3) : (e1<e2 && e2<e3); };
            if (!stk(s.emaM1[1], s.emaM1[2], s.emaM1[3])) return false;
            const int m3i = align.m3 - 3;   // M3 EMA at the same non-series lag as M1 (closed-2)
            bool m3Aligned = stk(TfIndicators::get(b.m3.ema[1], m3i),
                                 TfIndicators::get(b.m3.ema[2], m3i),
                                 TfIndicators::get(b.m3.ema[3], m3i));
            double m1di = is_long ? (s.diP[0] - s.diM[0]) : (s.diM[0] - s.diP[0]);
            if (!(m3Aligned || m1di >= c.extreme_di_spread)) return false;
            // STEP 3 — price vs EMA25 & M1 cloud (real Tenkan/Kijun), 5-pip tolerance.
            {
                const double tol = 5.0 * c.pip_size, ema25 = s.emaM1[1];
                const double cloudTop = std::max(s.tenkanM1, s.kijunM1);
                const double cloudBot = std::min(s.tenkanM1, s.kijunM1);
                if (is_long) { if (s.closeM1 <= ema25 - tol || s.closeM1 <= cloudTop - tol) return false; }
                else         { if (s.closeM1 >= ema25 + tol || s.closeM1 >= cloudBot + tol) return false; }
            }
            // STEP 4 — M1 ADX minimum.
            if (s.adx[0] < c.e4_min_momentum_adx) return false;
            return true;
        }
    }
    return false;
}

// First-match-wins E1->E2->E4, long-before-short. B = forming M1 bar; entry anchor = close[1].
// CONSUMES the trigger that fires (resets it to -1) so one cross/touch == one entry — mirrors the EA
// (which clears lastEMACrossing/Touch/IchiCross on a successful build). `tg` is mutated on success.
// `occ[kind][dir]` (dir 0=long,1=short) = a position of that kind+direction is already open. The EA
// blocks a new entry while one is open (CheckOpenPositions -> checkOpen{L,S}E{n}==-1 in *AllConditions)
// WITHOUT consuming the trigger, so it re-fires once that slot frees. Pass nullptr to disable (bar engine).
inline EntrySignal detect_entry(const TfBundle& b, const KenKemConfig& c, int B,
                                const TfBundle::Align& align, const Snapshot& s,
                                TriggerState& tg, const bool (*occ)[2] = nullptr) {
    EntrySignal r;
    if (!s.valid) return r;
    const int i1 = align.m1 - 1;
    if (i1 < 0) return r;
    double hi, lo; recent_range(b.m1, i1, c.range_hilo_lookback, hi, lo);
    const double entry = s.closeM1;

    // Clear one trigger (kind, direction) — shared by the stale-expiry reset and the on-fire consume.
    auto clear_trigger = [&](int kind, bool lng) {
        switch (kind) {
            case 1: (lng ? tg.ema_up  : tg.ema_down)  = -1; break;
            case 2: (lng ? tg.e75_up  : tg.e75_down)  = -1; break;
            case 4: (lng ? tg.ichi_up : tg.ichi_down) = -1; break;
            case 5: (lng ? tg.e5_up   : tg.e5_down)   = -1; break;
        }
    };

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
            if (occ && occ[cd.kind][dir]) continue;    // slot occupied -> block WITHOUT consuming
            if (B - fired > cd.maxage) {               // stale trigger
                // EA Entry1/2/4 RESET lastX=-1 on expiry (Entry1.mqh:103-109, Entry2.mqh:102-147,
                // Entry4.mqh:106-108) so a later fresh cross/touch can re-arm. The distilled engine only
                // skipped, pinning the trigger at its first cross forever -> a re-cross (e.g. M1 cloud
                // dips below then back above while M3 stays bullish) could never re-arm, and the entry
                // aged out permanently. E5 re-arms on alignment onset (update_triggers), not age -> leave.
                if (cd.kind != 5) clear_trigger(cd.kind, is_long);
                continue;
            }
            if (!entry_gate_ok(cd.kind, is_long, b, s, align, c)) continue;
            r.detected = true; r.is_long = is_long; r.kind = cd.kind; r.entry = entry; r.age = B - fired;
            r.sl = compute_sl(cd.kind, is_long, entry, s, hi, lo, c, b.m1.bars[i1].spread_mean);
            r.tp = compute_tp(cd.kind, is_long, entry, r.sl, s, c);
            r.risk = std::fabs(r.entry - r.sl);
            clear_trigger(cd.kind, is_long);           // consume the fired trigger (one cross/touch -> one entry)
            return r;
        }
    }
    return r;
}

}  // namespace kk::kenkem
