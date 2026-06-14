// KK-MasterVP-Monster — CANONICAL decision types + pure logic, faithfully ported from the EA's
// MQL5/Include/KKVP/SignalCore_Monster.mqh (779 LOC). The MQL file-scope globals (node arrays,
// master-POC history ring, fresh-cross registry, overhead rings, net-context) are encapsulated here
// into structs so the engine is deterministic + reentrant; the LOGIC is byte-for-byte the Pine spec.
//
// Reuses kk::VPResult from types.hpp. Everything else lives in kk::monster to stay separate from the
// KK-MasterVP engine.
#pragma once
#include "kk/common/types.hpp"
#include "kk/monster/monster_config.hpp"
#include <vector>
#include <cmath>
#include <algorithm>
#include <string>

namespace kk::monster {

using kk::VPResult;

inline int clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }

// Monster regime read for the current confirmed bar (master-POC slope).
struct MonsterRegime {
    bool   slope_known = false;
    double slope_norm  = 0.0;
    bool   mpoc_slope_up = false;
    bool   mpoc_slope_dn = false;
    bool   poc_stable    = true;
};

// Entry kinds (Pine longKind/shortKind): 1=breakout 2=rev POC-cross 3=rev edge-cross 4=impulse
enum Kind { KIND_NONE = 0, KIND_BRK = 1, KIND_REV1 = 2, KIND_REV2 = 3, KIND_IMP = 4 };

struct Signal {
    bool   valid  = false;
    bool   is_long = false;
    int    kind   = KIND_NONE;
    double entry  = 0.0;
    double sl     = 0.0;
    double tp1    = 0.0;
    double tp2    = 0.0;
    double risk   = 0.0;
    double lot    = 0.0;
    double edge   = 0.0;       // master edge broken (mVah long / mVal short); 0 for reversion
    std::string reason;
    // diagnostic features (trade journal; no trading effect)
    double f_brk_dist_atr = 0.0;
    double f_body_pct     = 0.0;
    double f_slope        = 0.0;
    double f_net_m1       = 0.0;
    double f_net_m3       = 0.0;
    double f_net_m5       = 0.0;
    double f_atr_pct      = 0.0;
    void reset() { *this = Signal{}; }
};

inline bool signal_is_rev(const Signal& s) { return s.kind == KIND_REV1 || s.kind == KIND_REV2; }

// Build POC/VAH/VAL from a populated histogram (Pine f_vp core / BuildVAFromHist) — VERBATIM.
inline void build_va_from_hist(const std::vector<double>& hist, int bins, double lo, double step,
                               double va_pct, VPResult& res) {
    double total = 0.0; int pocIdx = 0; double pocVol = -1.0;
    for (int b = 0; b < bins; b++) { double hv = hist[b]; total += hv; if (hv > pocVol) { pocVol = hv; pocIdx = b; } }
    double target = total * (va_pct * 0.01);
    double acc = hist[pocIdx];
    int loIdx = pocIdx, hiIdx = pocIdx;
    while (acc < target && (loIdx > 0 || hiIdx < bins - 1)) {
        double nextL = (loIdx > 0) ? hist[loIdx - 1] : -1.0;
        double nextH = (hiIdx < bins - 1) ? hist[hiIdx + 1] : -1.0;
        if (nextH >= nextL) { hiIdx += 1; acc += hist[hiIdx]; }
        else                { loIdx -= 1; acc += hist[loIdx]; }
    }
    res.poc = lo + (pocIdx + 0.5) * step;
    res.vah = lo + (hiIdx + 1.0) * step;
    res.val = lo + loIdx * step;
}

// Compute a volume profile over bars[start..start+len) using tick_count weight into each bar's hlc3
// bin (Pine f_vp). `skip_old` drops the oldest N bars (predicted/aged master). Returns valid=false
// if the window is degenerate. Bars are oldest->newest (index 0 = oldest); `newest_idx` is the
// inclusive newest bar of the window (the shift-1 confirmed bar).
inline VPResult compute_vp(const std::vector<kk::Bar>& bars, int newest_idx, int len, int bins,
                           double va_pct, int skip_old, double mintick) {
    VPResult r; r.valid = false;
    if (newest_idx < 0 || bins < 1) return r;
    int useLen = std::max(bins, len - skip_old);
    int oldest = newest_idx - useLen + 1;
    if (oldest < 0) return r;
    double hi = -1e300, lo = 1e300;
    for (int i = oldest; i <= newest_idx; i++) { hi = std::max(hi, bars[i].high); lo = std::min(lo, bars[i].low); }
    if (!(hi > lo)) return r;
    double step = (hi - lo) / bins;
    if (step <= 0.0) return r;
    std::vector<double> hist(bins, 0.0);
    for (int i = oldest; i <= newest_idx; i++) {
        double hlc3 = (bars[i].high + bars[i].low + bars[i].close) / 3.0;
        double vol = bars[i].tick_count > 0 ? (double)bars[i].tick_count : 1.0;
        int bi = clampi((int)std::floor((hlc3 - lo) / step), 0, bins - 1);
        hist[bi] += vol;
    }
    build_va_from_hist(hist, bins, lo, step, va_pct, r);
    r.hi = hi; r.lo = lo; r.valid = true;
    (void)mintick;
    return r;
}

//==================================================================
// NODE ENGINE — synthetic buy/sell pressure over the sliding master range.
//==================================================================
struct NodeEngine {
    std::vector<double> buy, sell, touch;
    double mLo = 0.0, mHi = 0.0, mStep = 0.0;
    int bins = 40;

    void init(int n) { bins = n; buy.assign(n, 0.0); sell.assign(n, 0.0); touch.assign(n, 0.0); mLo = mHi = mStep = 0.0; }

    int pick_idx(double px) const {
        if (mStep <= 0.0) return 0;
        return clampi((int)std::floor((px - mLo) / mStep), 0, bins - 1);
    }

    // Pure node accumulation for ONE just-closed bar (NodeAccumulate) — VERBATIM.
    void accumulate(double o, double h, double l, double c, double vol, double atr,
                    const VPResult& masterVP, const MonsterConfig& cfg) {
        if (!masterVP.valid) return;
        double lo = masterVP.lo, hi = masterVP.hi;
        double step = (hi - lo) / bins;
        if (step <= 0.0) return;
        mLo = lo; mHi = hi; mStep = step;
        if (o <= 0.0 || h <= 0.0 || l <= 0.0 || c <= 0.0 || h < l) return;
        double touchDist = std::max(cfg.node_touch_atr * atr, 2.0 * cfg.mintick);
        double dirProxy = (c - o) / std::max(h - l, cfg.mintick);
        double buyProxy = vol * std::max(dirProxy, 0.0);
        double sellProxy = vol * std::max(-dirProxy, 0.0);
        for (int b = 0; b < bins; b++) { buy[b] *= cfg.node_decay; sell[b] *= cfg.node_decay; touch[b] *= cfg.node_decay; }
        int lowIdx = clampi((int)std::floor((l - lo) / step), 0, bins - 1);
        int highIdx = clampi((int)std::floor((h - lo) / step), 0, bins - 1);
        double span = std::max((double)(highIdx - lowIdx + 1), 1.0);
        for (int b = lowIdx; b <= highIdx; b++) {
            double nodePx = lo + (b + 0.5) * step;
            bool touched = (std::fabs(c - nodePx) <= touchDist) || (l <= nodePx && h >= nodePx);
            if (touched) { touch[b] += 1.0; buy[b] += buyProxy / span; sell[b] += sellProxy / span; }
        }
    }

    // Chart-TF near-net from node arrays (NetM3Weighted) — VERBATIM.
    double net_m3_weighted(double px, double atrChart, const MonsterConfig& cfg) const {
        if (mStep <= 0.0 || atrChart <= 0.0) return 0.0;
        double nd = cfg.net_win_atr * atrChart;
        double mx = 0.0;
        if (cfg.use_weighted_net)
            for (int b = 0; b < bins; b++) { double bpx = mLo + (b + 0.5) * mStep; if (std::fabs(bpx - px) <= nd) mx = std::max(mx, buy[b] + sell[b]); }
        double tB = 0.0, tS = 0.0;
        for (int b = 0; b < bins; b++) {
            double bpx = mLo + (b + 0.5) * mStep;
            if (std::fabs(bpx - px) > nd) continue;
            double bv = buy[b], sv = sell[b], w = 1.0;
            if (cfg.use_weighted_net && mx > 0.0) { double tier = (bv + sv) / mx; w = (tier > 0.66) ? cfg.w_hvn : (tier < 0.33 ? cfg.w_lvn : cfg.w_mvn); }
            if (bv > sv) tB += (bv - sv) * w; else tS += (sv - bv) * w;
        }
        double tot = tB + tS;
        return (tot > 0.0) ? (tB - tS) / tot : 0.0;
    }

    // f_band_node: total node volume + net of master bins inside [lo,hi].
    void band_node(double lo, double hi, double& vol, double& net) const {
        vol = 0.0; net = 0.0;
        if (mStep <= 0.0 || hi <= lo) return;
        double bv = 0.0, sv = 0.0;
        for (int b = 0; b < bins; b++) { double bpx = mLo + (b + 0.5) * mStep; if (bpx >= lo && bpx <= hi) { bv += buy[b]; sv += sell[b]; } }
        vol = bv + sv;
        if (vol > 0.0) net = (bv - sv) / vol;
    }

    // HVN-shelf SL (edge candidate; OFF by default) — VERBATIM.
    double hvn_shelf_sl(bool isLong, double entry, double atrv, double fallbackSl, const MonsterConfig& cfg) const {
        if (mStep <= 0.0 || atrv <= 0.0) return fallbackSl;
        double nearB = isLong ? entry - cfg.shelf_near_atr * atrv : entry + cfg.shelf_near_atr * atrv;
        double farB  = isLong ? entry - cfg.shelf_far_atr  * atrv : entry + cfg.shelf_far_atr  * atrv;
        double winLo = std::min(nearB, farB), winHi = std::max(nearB, farB);
        double bestVol = 0.0, bestPx = 0.0;
        for (int b = 0; b < bins; b++) {
            double bpx = mLo + (b + 0.5) * mStep;
            if (bpx < winLo || bpx > winHi) continue;
            double v = buy[b] + sell[b];
            if (v > bestVol) { bestVol = v; bestPx = bpx; }
        }
        if (bestVol <= 0.0) return fallbackSl;
        double cand = isLong ? bestPx - cfg.shelf_buf_atr * atrv : bestPx + cfg.shelf_buf_atr * atrv;
        if (isLong && cand >= entry) return fallbackSl;
        if (!isLong && cand <= entry) return fallbackSl;
        return cand;
    }

    // Structural TP2 (edge candidate; OFF by default) — VERBATIM.
    double structural_tp2(bool isLong, double entry, double risk, double tp1Px, double atrv,
                          const VPResult& pred, double fallbackTp2, const MonsterConfig& cfg) const {
        if (risk <= 0.0 || atrv <= 0.0) return fallbackTp2;
        double cand = 0.0;
        if (mStep > 0.0) {
            double mxVol = 0.0;
            for (int b = 0; b < bins; b++) mxVol = std::max(mxVol, buy[b] + sell[b]);
            if (mxVol > 0.0) {
                if (isLong) {
                    for (int b = 0; b < bins; b++) { double bpx = mLo + (b + 0.5) * mStep; if (bpx <= tp1Px) continue; if ((buy[b] + sell[b]) >= cfg.stp2_hvn_frac * mxVol) { cand = bpx - cfg.stp2_edge_off_atr * atrv; break; } }
                } else {
                    for (int b = bins - 1; b >= 0; b--) { double bpx = mLo + (b + 0.5) * mStep; if (bpx >= tp1Px) continue; if ((buy[b] + sell[b]) >= cfg.stp2_hvn_frac * mxVol) { cand = bpx + cfg.stp2_edge_off_atr * atrv; break; } }
                }
            }
        }
        if (cand <= 0.0 && pred.valid) cand = isLong ? pred.vah : pred.val;
        if (cand <= 0.0) return fallbackTp2;
        double candR = isLong ? (cand - entry) / risk : (entry - cand) / risk;
        double rr = std::min(std::max(candR, cfg.stp2_min_rr), cfg.stp2_max_rr);
        return isLong ? entry + rr * risk : entry - rr * risk;
    }
};

// Failed-break exit test (edge candidate) — VERBATIM. progressR = signed R from signal entry.
inline int failed_break_check(bool isLong, double edge, double closeSig, double netM3,
                              double progressR, int barsHeld, const MonsterConfig& cfg) {
    if (edge <= 0.0 || closeSig <= 0.0) return 0;
    if (barsHeld <= cfg.fail_break_bars) {
        if (isLong && closeSig < edge) return 1;
        if (!isLong && closeSig > edge) return 1;
    }
    if (progressR < cfg.fail_break_r_gate) {
        if (isLong && netM3 <= -cfg.fail_break_net_flip) return 2;
        if (!isLong && netM3 >= cfg.fail_break_net_flip) return 2;
    }
    return 0;
}

// Overhead band-volume percentrank rings (Pine ta.percentrank, strict <).
struct OverheadHistory {
    std::vector<double> longHist, shortHist;
    int count = 0, cap = 200;
    void init(int look) { cap = std::max(look, 1); longHist.assign(cap, 0.0); shortHist.assign(cap, 0.0); count = 0; }
    double percentrank(const std::vector<double>& hist, double cur, int look, bool& valid) const {
        if (look <= 0) { valid = false; return 0.0; }
        valid = (count >= look);
        if (!valid) return 0.0;
        int less = 0; for (int i = 0; i < look; i++) if (hist[i] < cur) less++;
        return 100.0 * less / look;
    }
    void push(double volLong, double volShort) {
        if (cap <= 0) return;
        int top = std::min(count, cap - 1);
        for (int i = top; i > 0; i--) { longHist[i] = longHist[i - 1]; shortHist[i] = shortHist[i - 1]; }
        longHist[0] = volLong; shortHist[0] = volShort;
        if (count < cap) count++;
    }
};

// Master-POC history ring + regime computation.
struct MPocHistory {
    std::vector<double> hist;
    int count = 0;
    void init(int slope_bars) { int capn = std::max(slope_bars + 2, 4); hist.assign(capn, 0.0); count = 0; }
    void push(double mPoc) {
        int capn = (int)hist.size(); if (capn <= 0) return;
        for (int i = std::min(count, capn - 1); i > 0; i--) hist[i] = hist[i - 1];
        hist[0] = mPoc; if (count < capn) count++;
    }
    bool bars_ago(int barsAgo, double& out) const {
        if (barsAgo < 1 || barsAgo > count) return false;
        out = hist[barsAgo - 1]; return (out > 0.0);
    }
    void compute_regime(double atrv, double mPoc, bool pMPocValid, double pMPoc,
                        const MonsterConfig& cfg, MonsterRegime& r) const {
        r.slope_known = false; r.slope_norm = 0.0; r.mpoc_slope_up = false; r.mpoc_slope_dn = false;
        double pocAgo;
        if (mPoc > 0.0 && atrv > 0.0 && bars_ago(cfg.impulse_trend_slope_bars, pocAgo)) {
            r.slope_known = true;
            r.slope_norm = (mPoc - pocAgo) / atrv;
            r.mpoc_slope_up = (mPoc > pocAgo);
            r.mpoc_slope_dn = (mPoc < pocAgo);
        }
        r.poc_stable = true;
        if (pMPocValid && atrv > 0.0) r.poc_stable = (std::fabs(pMPoc - mPoc) <= cfg.poc_stable_max_atr * atrv);
    }
};

// Fresh-cross registry (Pine ta.crossover/under of close vs master levels on confirmed bars).
struct CrossRegistry {
    int xiUpVah = -1, xiDnVal = -1, xiUpPoc = -1, xiDnPoc = -1, xiUpVal = -1, xiDnVah = -1;
    double prevClose = 0.0, prevMVah = 0.0, prevMVal = 0.0, prevMPoc = 0.0;
    bool prevLvlValid = false;
    int lastLongEntryBar = -1, lastShortEntryBar = -1;

    static bool fresh(int xi, int bars, int sigBarIdx) { return (xi >= 0) && (sigBarIdx - xi) <= bars; }

    void update_fresh_crosses(double closeSig, const VPResult& m, int sigBarIdx) {
        if (m.valid && prevLvlValid && prevClose > 0.0) {
            if (closeSig > m.vah && prevClose <= prevMVah) xiUpVah = sigBarIdx;
            if (closeSig < m.val && prevClose >= prevMVal) xiDnVal = sigBarIdx;
            if (closeSig > m.poc && prevClose <= prevMPoc) xiUpPoc = sigBarIdx;
            if (closeSig < m.poc && prevClose >= prevMPoc) xiDnPoc = sigBarIdx;
            if (closeSig > m.val && prevClose <= prevMVal) xiUpVal = sigBarIdx;
            if (closeSig < m.vah && prevClose >= prevMVah) xiDnVah = sigBarIdx;
        }
        if (m.valid) { prevClose = closeSig; prevMVah = m.vah; prevMVal = m.val; prevMPoc = m.poc; prevLvlValid = true; }
        else prevLvlValid = false;
    }
    void consume_cross(int kind, bool isLong) {
        if (kind == KIND_BRK)       { if (isLong) xiUpVah = -1; else xiDnVal = -1; }
        else if (kind == KIND_REV1) { if (isLong) xiUpPoc = -1; else xiDnPoc = -1; }
        else if (kind == KIND_REV2) { if (isLong) xiUpVal = -1; else xiDnVah = -1; }
    }
};

// Per-bar multi-TF net context + overhead raw reads (set by the engine before evaluate).
struct NetContext {
    double netM1 = 0.0, netM3 = 0.0, netM5 = 0.0, netM15 = 0.0;
    bool hasM1 = false, hasM5 = false, hasM15 = false;
    bool ovhRawLong = false, ovhRawShort = false;
};

// FULL MONSTER ENTRY EVALUATION (EvaluateMonsterSignals) — faithful port. Picks at most ONE entry
// per direction. atrCeilOk = (ATR% <= maxAtrPct); inVolCeilBand = (maxAtrPct>0 && ATR% > maxAtrPct).
inline void evaluate_monster_signals(const MonsterConfig& cfg, double o, double h, double l, double c,
                                     const VPResult& masterCur, const VPResult& localCur, const VPResult& predCur,
                                     const MonsterRegime& reg, double atrv, double atrPct,
                                     bool atrCeilOk, bool inVolCeilBand, int sigBarIdx,
                                     const NodeEngine& node, const CrossRegistry& cross, const NetContext& net,
                                     Signal& longSig, Signal& shortSig) {
    longSig.reset(); shortSig.reset();
    bool lvlsOk = masterCur.valid && localCur.valid;
    if (!lvlsOk || atrv <= 0.0) return;
    if (c <= 0.0 || o <= 0.0 || h <= 0.0 || l <= 0.0 || h < l) return;

    double mVah = masterCur.vah, mVal = masterCur.val, mPoc = masterCur.poc;
    double vah = localCur.vah, val = localCur.val, poc = localCur.poc;

    // shared net gates
    bool netLongOk  = (net.netM3 >=  cfg.brk_net_min_m3)
                   || (cfg.net_confirm_m1_or_m3 && net.hasM1 && net.netM1 >=  cfg.brk_net_min)
                   || (cfg.net_confirm_m5       && net.hasM5 && net.netM5 >=  cfg.brk_net_min);
    bool netShortOk = (net.netM3 <= -cfg.brk_net_min_m3)
                   || (cfg.net_confirm_m1_or_m3 && net.hasM1 && net.netM1 <= -cfg.brk_net_min)
                   || (cfg.net_confirm_m5       && net.hasM5 && net.netM5 <= -cfg.brk_net_min);
    bool oppLongOk  = (net.netM3 > -cfg.brk_opp_max) && (!net.hasM5 || net.netM5 > -cfg.brk_opp_max);
    bool oppShortOk = (net.netM3 <  cfg.brk_opp_max) && (!net.hasM5 || net.netM5 <  cfg.brk_opp_max);
    bool rNetLongOk  = (net.netM3 >=  cfg.rev_net_min)
                    || (cfg.net_confirm_m1_or_m3 && net.hasM1 && net.netM1 >=  cfg.rev_net_min)
                    || (cfg.net_confirm_m5       && net.hasM5 && net.netM5 >=  cfg.rev_net_min);
    bool rNetShortOk = (net.netM3 <= -cfg.rev_net_min)
                    || (cfg.net_confirm_m1_or_m3 && net.hasM1 && net.netM1 <= -cfg.rev_net_min)
                    || (cfg.net_confirm_m5       && net.hasM5 && net.netM5 <= -cfg.rev_net_min);
    bool rOppLongOk  = (net.netM3 > -cfg.rev_opp_max) && (!net.hasM5 || net.netM5 > -cfg.rev_opp_max);
    bool rOppShortOk = (net.netM3 <  cfg.rev_opp_max) && (!net.hasM5 || net.netM5 <  cfg.rev_opp_max);

    // regime gate
    bool gateBrkL = !cfg.enable_regime_gate || (reg.slope_known && reg.slope_norm >=  cfg.regime_tau_high);
    bool gateBrkS = !cfg.enable_regime_gate || (reg.slope_known && reg.slope_norm <= -cfg.regime_tau_high);
    bool gateRev  = !cfg.enable_regime_gate || (reg.slope_known && std::fabs(reg.slope_norm) <= cfg.regime_tau_low);
    // poc stability
    bool brkPocOk = !cfg.brk_require_poc_stable || reg.poc_stable;
    bool revPocOk = !cfg.rev_require_poc_stable || reg.poc_stable;
    // HTF bias
    bool htfBull = net.hasM5 && net.hasM15 && (net.netM5 >=  cfg.htf_bias_min) && (net.netM15 >=  cfg.htf_bias_min);
    bool htfBear = net.hasM5 && net.hasM15 && (net.netM5 <= -cfg.htf_bias_min) && (net.netM15 <= -cfg.htf_bias_min);
    bool gateHtfL = !cfg.enable_htf_bias || (cfg.htf_require_align ? htfBull : !htfBear);
    bool gateHtfS = !cfg.enable_htf_bias || (cfg.htf_require_align ? htfBear : !htfBull);
    // overhead veto
    bool ovhBlockL = cfg.brk_overhead_veto && net.ovhRawLong;
    bool ovhBlockS = cfg.brk_overhead_veto && net.ovhRawShort;

    // BREAKOUT (kind 1)
    double slBrkL = std::min(mVah - cfg.brk_sl_buf_atr * atrv, c - cfg.brk_sl_atr_mult * atrv);
    double riskBrkL = c - slBrkL;
    bool recentLong = (cross.lastLongEntryBar >= 0) && (sigBarIdx - cross.lastLongEntryBar) <= cfg.brk_rr_lookback_bars;
    double rrBrkL = recentLong ? cfg.brk_rr_near : cfg.brk_rr_far;
    double tpBrkL = c + rrBrkL * riskBrkL;
    bool sigBrkL = cfg.enable_breakout
                && CrossRegistry::fresh(cross.xiUpVah, cfg.brk_fresh_bars, sigBarIdx)
                && (vah <= mVah + cfg.brk_local_tol_atr * atrv)
                && (c >= mVah + cfg.brk_entry_buf_atr * atrv)
                && (cfg.brk_max_dist_atr <= 0.0 || c <= mVah + cfg.brk_max_dist_atr * atrv)
                && netLongOk && oppLongOk && (riskBrkL > 0.0)
                && gateBrkL && gateHtfL && !ovhBlockL && brkPocOk;

    double slBrkS = std::max(mVal + cfg.brk_sl_buf_atr * atrv, c + cfg.brk_sl_atr_mult * atrv);
    double riskBrkS = slBrkS - c;
    bool recentShort = (cross.lastShortEntryBar >= 0) && (sigBarIdx - cross.lastShortEntryBar) <= cfg.brk_rr_lookback_bars;
    double rrBrkS = recentShort ? cfg.brk_rr_near : cfg.brk_rr_far;
    double tpBrkS = c - rrBrkS * riskBrkS;
    bool sigBrkS = cfg.enable_breakout
                && CrossRegistry::fresh(cross.xiDnVal, cfg.brk_fresh_bars, sigBarIdx)
                && (val >= mVal - cfg.brk_local_tol_atr * atrv)
                && (c <= mVal - cfg.brk_entry_buf_atr * atrv)
                && (cfg.brk_max_dist_atr <= 0.0 || c >= mVal - cfg.brk_max_dist_atr * atrv)
                && netShortOk && oppShortOk && (riskBrkS > 0.0)
                && gateBrkS && gateHtfS && !ovhBlockS && brkPocOk;

    // MEAN-REVERSION variant 1: POC cross -> VAH/VAL-family TP (kind 2)
    double slRevL1 = std::min(c - cfg.rev_sl_atr_mult * atrv, std::max(mPoc + cfg.rev_poc_sl_off_atr * atrv, poc) - cfg.rev_sl_buf_atr * atrv);
    double riskRevL1 = c - slRevL1;
    double tpRevL1 = (mVah > vah + atrv) ? mVah : std::max(mVah, vah);
    double rrRevL1 = (riskRevL1 > 0.0) ? (tpRevL1 - c) / riskRevL1 : -1.0;
    bool sigRevL1 = cfg.enable_reversion
                 && CrossRegistry::fresh(cross.xiUpPoc, cfg.rev_fresh_bars, sigBarIdx)
                 && (c >= std::max(mPoc + cfg.rev_anchor_off_atr * atrv, poc) + cfg.rev_entry_dist_atr * atrv)
                 && (cfg.rev_max_dist_atr <= 0.0 || c <= mPoc + cfg.rev_max_dist_atr * atrv)
                 && rNetLongOk && rOppLongOk && (riskRevL1 > 0.0) && (tpRevL1 > c)
                 && (rrRevL1 >= cfg.rev_min_rr) && gateRev && revPocOk;

    double slRevS1 = std::max(c + cfg.rev_sl_atr_mult * atrv, std::min(mPoc - cfg.rev_poc_sl_off_atr * atrv, poc) + cfg.rev_sl_buf_atr * atrv);
    double riskRevS1 = slRevS1 - c;
    double tpRevS1 = (mVal < val - atrv) ? mVal : std::min(mVal, val);
    double rrRevS1 = (riskRevS1 > 0.0) ? (c - tpRevS1) / riskRevS1 : -1.0;
    bool sigRevS1 = cfg.enable_reversion
                 && CrossRegistry::fresh(cross.xiDnPoc, cfg.rev_fresh_bars, sigBarIdx)
                 && (c <= std::min(mPoc - cfg.rev_anchor_off_atr * atrv, poc) - cfg.rev_entry_dist_atr * atrv)
                 && (cfg.rev_max_dist_atr <= 0.0 || c >= mPoc - cfg.rev_max_dist_atr * atrv)
                 && rNetShortOk && rOppShortOk && (riskRevS1 > 0.0) && (tpRevS1 < c)
                 && (rrRevS1 >= cfg.rev_min_rr) && gateRev && revPocOk;

    // MEAN-REVERSION variant 2: VAL/VAH cross -> POC-family TP (kind 3)
    double slRevL2 = std::min(c - cfg.rev_sl_atr_mult * atrv, std::max(mVal + cfg.rev_anchor_off_atr * atrv, val) - cfg.rev_sl_buf_atr * atrv);
    double riskRevL2 = c - slRevL2;
    double tpRevL2 = (mPoc > poc + atrv) ? mPoc : std::max(mPoc, poc);
    double rrRevL2 = (riskRevL2 > 0.0) ? (tpRevL2 - c) / riskRevL2 : -1.0;
    bool sigRevL2 = cfg.enable_reversion
                 && CrossRegistry::fresh(cross.xiUpVal, cfg.rev_fresh_bars, sigBarIdx)
                 && (c >= std::max(mVal + cfg.rev_anchor_off_atr * atrv, val) + cfg.rev_entry_dist_atr * atrv)
                 && (cfg.rev_max_dist_atr <= 0.0 || c <= mVal + cfg.rev_max_dist_atr * atrv)
                 && rNetLongOk && rOppLongOk && (riskRevL2 > 0.0) && (tpRevL2 > c)
                 && (rrRevL2 >= cfg.rev_min_rr) && gateRev && revPocOk;

    double slRevS2 = std::max(c + cfg.rev_sl_atr_mult * atrv, std::min(mVah - cfg.rev_anchor_off_atr * atrv, vah) + cfg.rev_sl_buf_atr * atrv);
    double riskRevS2 = slRevS2 - c;
    double tpRevS2 = (mPoc < poc - atrv) ? mPoc : std::min(mPoc, poc);
    double rrRevS2 = (riskRevS2 > 0.0) ? (c - tpRevS2) / riskRevS2 : -1.0;
    bool sigRevS2 = cfg.enable_reversion
                 && CrossRegistry::fresh(cross.xiDnVah, cfg.rev_fresh_bars, sigBarIdx)
                 && (c <= std::min(mVah - cfg.rev_anchor_off_atr * atrv, vah) - cfg.rev_entry_dist_atr * atrv)
                 && (cfg.rev_max_dist_atr <= 0.0 || c >= mVah - cfg.rev_max_dist_atr * atrv)
                 && rNetShortOk && rOppShortOk && (riskRevS2 > 0.0) && (tpRevS2 < c)
                 && (rrRevS2 >= cfg.rev_min_rr) && gateRev && revPocOk;

    // IMPULSE-THRUST (kind 4) — fires ONLY above the volatility ceiling.
    double candleH = h - l;
    bool impThrustBull = (c > o) && (candleH >= cfg.impulse_candle_atr * atrv);
    bool impThrustBear = (c < o) && (candleH >= cfg.impulse_candle_atr * atrv);
    bool impNetLongOk = net.hasM1 && (net.netM1 >=  cfg.impulse_net_min);
    bool impNetShortOk = net.hasM1 && (net.netM1 <= -cfg.impulse_net_min);
    double pPocRef = predCur.valid ? predCur.poc : mPoc;
    double pVahRef = predCur.valid ? predCur.vah : mVah;
    double pValRef = predCur.valid ? predCur.val : mVal;
    bool impTrendLong = reg.mpoc_slope_up && (pPocRef >= mPoc);
    bool impTrendShort = reg.mpoc_slope_dn && (pPocRef <= mPoc);
    bool impEntryL = (c >= mVah + cfg.impulse_entry_buf_atr * atrv) && (cfg.impulse_max_dist_atr <= 0.0 || c <= pVahRef + cfg.impulse_max_dist_atr * atrv);
    bool impEntryS = (c <= mVal - cfg.impulse_entry_buf_atr * atrv) && (cfg.impulse_max_dist_atr <= 0.0 || c >= pValRef - cfg.impulse_max_dist_atr * atrv);
    double slImpL = std::min(mVah - cfg.brk_sl_buf_atr * atrv, c - cfg.brk_sl_atr_mult * atrv);
    double riskImpL = c - slImpL;
    double tpImpL = c + cfg.impulse_rr * riskImpL;
    bool sigImpL = cfg.enable_impulse && inVolCeilBand && impThrustBull && impEntryL && impTrendLong && impNetLongOk && (riskImpL > 0.0);
    double slImpS = std::max(mVal + cfg.brk_sl_buf_atr * atrv, c + cfg.brk_sl_atr_mult * atrv);
    double riskImpS = slImpS - c;
    double tpImpS = c - cfg.impulse_rr * riskImpS;
    bool sigImpS = cfg.enable_impulse && inVolCeilBand && impThrustBear && impEntryS && impTrendShort && impNetShortOk && (riskImpS > 0.0);

    // pick one entry per direction (Pine priority chain)
    int longKind = KIND_NONE; double longSL = 0, longTP2 = 0, longRisk = 0;
    if (sigImpL) { longKind = KIND_IMP; longSL = slImpL; longTP2 = tpImpL; longRisk = riskImpL; }
    else if (atrCeilOk && sigBrkL) { longKind = KIND_BRK; longSL = slBrkL; longTP2 = tpBrkL; longRisk = riskBrkL; }
    else if (atrCeilOk && sigRevL1 && (!sigRevL2 || rrRevL1 >= rrRevL2)) { longKind = KIND_REV1; longSL = slRevL1; longTP2 = tpRevL1; longRisk = riskRevL1; }
    else if (atrCeilOk && sigRevL2) { longKind = KIND_REV2; longSL = slRevL2; longTP2 = tpRevL2; longRisk = riskRevL2; }

    int shortKind = KIND_NONE; double shortSL = 0, shortTP2 = 0, shortRisk = 0;
    if (sigImpS) { shortKind = KIND_IMP; shortSL = slImpS; shortTP2 = tpImpS; shortRisk = riskImpS; }
    else if (atrCeilOk && sigBrkS) { shortKind = KIND_BRK; shortSL = slBrkS; shortTP2 = tpBrkS; shortRisk = riskBrkS; }
    else if (atrCeilOk && sigRevS1 && (!sigRevS2 || rrRevS1 >= rrRevS2)) { shortKind = KIND_REV1; shortSL = slRevS1; shortTP2 = tpRevS1; shortRisk = riskRevS1; }
    else if (atrCeilOk && sigRevS2) { shortKind = KIND_REV2; shortSL = slRevS2; shortTP2 = tpRevS2; shortRisk = riskRevS2; }

    // Phase-4 structural SL/TP2 overrides (brk/imp only; both default OFF)
    if (longKind == KIND_BRK || longKind == KIND_IMP) {
        double rrL = (longKind == KIND_IMP) ? cfg.impulse_rr : rrBrkL;
        if (cfg.enable_hvn_shelf_sl) { double s = node.hvn_shelf_sl(true, c, atrv, longSL, cfg); if (s != longSL && c - s > 0.0) { longSL = s; longRisk = c - s; longTP2 = c + rrL * longRisk; } }
        if (cfg.enable_structural_tp2) longTP2 = node.structural_tp2(true, c, longRisk, c + cfg.tp1_rr_brk * longRisk, atrv, predCur, longTP2, cfg);
    }
    if (shortKind == KIND_BRK || shortKind == KIND_IMP) {
        double rrS = (shortKind == KIND_IMP) ? cfg.impulse_rr : rrBrkS;
        if (cfg.enable_hvn_shelf_sl) { double s = node.hvn_shelf_sl(false, c, atrv, shortSL, cfg); if (s != shortSL && s - c > 0.0) { shortSL = s; shortRisk = s - c; shortTP2 = c - rrS * shortRisk; } }
        if (cfg.enable_structural_tp2) shortTP2 = node.structural_tp2(false, c, shortRisk, c - cfg.tp1_rr_brk * shortRisk, atrv, predCur, shortTP2, cfg);
    }

    double rng = std::max(h - l, cfg.mintick);

    if (longKind != KIND_NONE) {
        bool brkFam = (longKind == KIND_BRK || longKind == KIND_IMP);
        longSig.valid = true; longSig.is_long = true; longSig.kind = longKind;
        longSig.entry = c; longSig.sl = longSL; longSig.risk = longRisk;
        longSig.tp1 = c + (brkFam ? cfg.tp1_rr_brk : cfg.tp1_rr_rev) * longRisk;
        longSig.tp2 = longTP2; longSig.edge = brkFam ? mVah : 0.0;
        longSig.reason = (longKind == KIND_BRK) ? "L-BRK" : (longKind == KIND_REV1) ? "L-MR1" : (longKind == KIND_REV2) ? "L-MR2" : "L-IMP";
        longSig.f_brk_dist_atr = (c - mVah) / atrv;
        longSig.f_body_pct = std::fabs(c - o) / rng;
        longSig.f_slope = reg.slope_known ? reg.slope_norm : 0.0;
        longSig.f_net_m1 = net.hasM1 ? net.netM1 : 0.0;
        longSig.f_net_m3 = net.netM3;
        longSig.f_net_m5 = net.hasM5 ? net.netM5 : 0.0;
        longSig.f_atr_pct = atrPct;
    }
    if (shortKind != KIND_NONE) {
        bool brkFam = (shortKind == KIND_BRK || shortKind == KIND_IMP);
        shortSig.valid = true; shortSig.is_long = false; shortSig.kind = shortKind;
        shortSig.entry = c; shortSig.sl = shortSL; shortSig.risk = shortRisk;
        shortSig.tp1 = c - (brkFam ? cfg.tp1_rr_brk : cfg.tp1_rr_rev) * shortRisk;
        shortSig.tp2 = shortTP2; shortSig.edge = brkFam ? mVal : 0.0;
        shortSig.reason = (shortKind == KIND_BRK) ? "S-BRK" : (shortKind == KIND_REV1) ? "S-MR1" : (shortKind == KIND_REV2) ? "S-MR2" : "S-IMP";
        shortSig.f_brk_dist_atr = (mVal - c) / atrv;
        shortSig.f_body_pct = std::fabs(c - o) / rng;
        shortSig.f_slope = reg.slope_known ? reg.slope_norm : 0.0;
        shortSig.f_net_m1 = net.hasM1 ? net.netM1 : 0.0;
        shortSig.f_net_m3 = net.netM3;
        shortSig.f_net_m5 = net.hasM5 ? net.netM5 : 0.0;
        shortSig.f_atr_pct = atrPct;
    }
}

}  // namespace kk::monster
