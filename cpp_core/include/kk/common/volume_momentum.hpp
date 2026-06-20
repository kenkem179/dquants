// Volume Momentum Confirmation (VMC) — timeframe-agnostic order-flow confirmation built from the
// tick-rule on mid, for a feed with NO real volume (LAST/VOLUME == 0; only bid/ask + tick_count).
//
// WHY THIS EXISTS: ADX/DI/RSI lag because they smooth price. VMC measures the *path* inside a bar —
// how many up-ticks vs down-ticks — which the bar OHLC throws away. A bar can close green while
// logging more down-ticks (distribution into strength): that disagreement is the one component
// genuinely independent of the EMA/price stack. To KEEP it independent we sign by tick *direction
// counts only* and never weight by price distance (that would re-launder price into the score, the
// flaw in the node-engine dirProxy=(close-open)/(high-low)). See research/hypotheses/VMC-SPEC.md.
//
// TIMEFRAME-AGNOSTIC: the engine has no notion of minutes. Feed it ticks, then call on_bar_close()
// at each bar boundary of WHATEVER timeframe you aggregate (M1/M3/M5/…). All windows are in BARS.
//
// PARITY: every sign decision is done in INTEGER POINTS (mid rounded to the symbol point grid with
// round-half-away-from-zero, == MQL5 (long)MathRound(mid/point)), so the C++ tick engine and the
// MQL5 CopyTicksRange path produce bit-identical up/dn. prev_mid_pts is carried CONTINUOUSLY across
// bar boundaries; only the per-bar up/dn accumulators reset. Flat ticks (|dmid| < epsilon) are
// excluded from up/dn entirely (no carry-forward) — cleaner and avoids quiet periods inflating flow.
#pragma once
#include <vector>
#include <cmath>
#include <algorithm>
#include <cstdint>
#include "kk/common/types.hpp"

namespace kk {

// All knobs are .set-sweepable. Defaults are timeframe-neutral starting points (windows in BARS).
struct VmcParams {
    // -- tick signing --
    int    epsilon_pts     = 1;     // dead-band: a tick counts only if |dmid| >= this many points (Roll-bounce guard)
    // -- direction leg D = EWMA(r) (the tick-CVD slope; r is already a [-1,1] ratio, so no z-score) --
    int    ewma_span       = 5;     // EWMA span over the per-bar delta ratio r
    double d_ref           = 0.5;   // delta-ratio counted as "full" directional strength: dterm=clamp(D/d_ref,-1,1)
    // -- persistence leg P --
    int    persist_len     = 5;     // L: lookback bars for sign-agreement fraction
    // -- retention leg R --
    int    retention_len   = 5;     // window (bars) for mean(|r|) absorption proxy
    // -- regime gate G (z-scores belong here, NOT in direction: they flag unusual/toxic conditions) --
    int    z_window        = 120;   // W: rolling window (bars) for the spread/tick-count baseline
    double spread_z_max    = 2.5;   // suppress when spread z-score exceeds this (toxic widening)
    double tickcount_z_max = 3.0;   // suppress when tick-count z-score exceeds this (toxic burst / VPIN proxy)
    // -- validity --
    int    warmup_bars     = 30;    // VMC invalid until this many bars committed (caller decides fallback)
};

// One committed (or peeked) reading. vmc is the single signed confirmation score in [-1, 1].
struct VmcOut {
    double r         = 0.0;   // last bar delta_ratio (signed)/gross  in [-1,1]
    double cvd       = 0.0;   // cumulative signed informative ticks (diagnostic / divergence)
    double d         = 0.0;   // EWMA(r): smoothed signed flow direction in [-1,1]
    double persist   = 0.0;   // P in [0,1]
    double retention = 0.0;   // R in [0,1]
    double spread_z  = 0.0;   // diagnostic
    double tick_z    = 0.0;   // diagnostic
    double vmc       = 0.0;   // = clamp(d_z/k_d,-1,1) * P * R, forced 0 if gated/invalid
    bool   gated     = false; // regime-suppressed (or warmup) this bar
    bool   valid     = false; // warmup satisfied
};

class VolumeMomentum {
public:
    // cap rings to the largest window we read from.
    void init(const VmcParams& p) {
        const int cap = std::max({p.z_window, p.persist_len, p.retention_len, 1});
        r_.assign(cap, 0.0); spr_.assign(cap, 0.0); tck_.assign(cap, 0.0);
        head_ = 0; count_ = 0; cap_ = cap;
        prev_mid_pts_ = INT64_MIN; up_ = dn_ = 0; cvd_ = 0.0;
        d_ = 0.0; d_init_ = false; bars_seen_ = 0;
        out_ = VmcOut{};
    }

    // --- sub-bar: classify one tick by the tick rule on mid, in integer points. ---
    // point = SymbolInfoDouble(SYMBOL_POINT). prev_mid_pts is carried across bars (NOT reset on close).
    void on_tick(double bid, double ask, double point, const VmcParams& p) {
        if (point <= 0.0) return;
        const int64_t mid_pts = pts(0.5 * (bid + ask), point);
        if (prev_mid_pts_ == INT64_MIN) { prev_mid_pts_ = mid_pts; return; }  // first tick = seed only
        const int64_t d = mid_pts - prev_mid_pts_;
        prev_mid_pts_ = mid_pts;
        if (d >= p.epsilon_pts)       ++up_;
        else if (d <= -p.epsilon_pts) ++dn_;
        // else: flat tick — carries no direction, excluded from gross.
    }

    // --- bar boundary: commit the just-closed bar and recompute the score. ---
    // ext_block: caller-supplied news/session/weekend suppression (clock logic lives in SessionManager/
    // NewsFilter, NOT here). Returns the committed reading. Resets up/dn for the next bar.
    const VmcOut& on_bar_close(const Bar& closed, bool ext_block, const VmcParams& p) {
        const int gross = up_ + dn_;
        const double r  = gross > 0 ? double(up_ - dn_) / double(gross) : 0.0;
        cvd_ += double(up_ - dn_);

        write_(r, closed.spread_mean, double(closed.tick_count));
        ++bars_seen_;
        up_ = dn_ = 0;

        compute_(r, ext_block, p);
        return out_;
    }

    // --- forming-bar (shift-0) provisional read; does NOT mutate state (no lookahead/repaint). ---
    // Uses up/dn accumulated so far this bar as a provisional r. For forming_bar_mode=1 only.
    VmcOut peek_forming(const Bar& forming_so_far, bool ext_block, const VmcParams& p) const {
        VolumeMomentum tmp(*this);                      // cheap: rings are small fixed vectors
        const int gross = tmp.up_ + tmp.dn_;
        const double r   = gross > 0 ? double(tmp.up_ - tmp.dn_) / double(gross) : 0.0;
        tmp.cvd_ += double(tmp.up_ - tmp.dn_);
        tmp.write_(r, forming_so_far.spread_mean, double(forming_so_far.tick_count));
        ++tmp.bars_seen_;
        tmp.compute_(r, ext_block, p);
        return tmp.out_;
    }

    const VmcOut& out() const { return out_; }

    // E5 gate helper: does the committed score confirm the proposed trade direction?
    bool confirms(int dir, double min_confirm) const {
        if (!out_.valid || out_.gated) return false;
        if (dir > 0) return out_.vmc >=  min_confirm;
        if (dir < 0) return out_.vmc <= -min_confirm;
        return false;
    }

private:
    // round-half-away-from-zero to the point grid; matches MQL5 (long)MathRound(x/point).
    static int64_t pts(double price, double point) {
        const double q = price / point;
        return (int64_t)(q >= 0.0 ? std::floor(q + 0.5) : std::ceil(q - 0.5));
    }
    // write one bar's values into the three rings at head_, then advance head_ once.
    void write_(double r, double spread, double tick_count) {
        r_[head_] = r; spr_[head_] = spread; tck_[head_] = tick_count;
        head_ = (head_ + 1) % cap_;
        if (count_ < cap_) ++count_;
    }

    // population mean/std over the last min(count_, win) ring entries (recomputed each bar -> no FP drift,
    // identical op-order to the MQL5 port).
    void stats_(const std::vector<double>& ring, int win, double& mean, double& sd) const {
        const int n = std::min(count_, win);
        if (n <= 0) { mean = 0.0; sd = 0.0; return; }
        double s = 0.0, s2 = 0.0;
        for (int k = 0; k < n; ++k) {
            const double v = ring[idx_back_(k)];
            s += v; s2 += v * v;
        }
        mean = s / n;
        double var = s2 / n - mean * mean;
        sd = var > 0.0 ? std::sqrt(var) : 0.0;
    }
    // k=0 is the most recent committed value.
    int idx_back_(int k) const { return ((head_ - 1 - k) % cap_ + cap_) % cap_; }

    void compute_(double r, bool ext_block, const VmcParams& p) {
        out_ = VmcOut{};
        out_.r = r; out_.cvd = cvd_;
        out_.valid = bars_seen_ >= p.warmup_bars;

        // Direction = EWMA of the per-bar delta ratio (tick-CVD slope). r is already a [-1,1] ratio,
        // so this is comparable across symbols/brokers with NO z-score (z-scoring would zero out a
        // sustained push as its own mean catches up — wrong for a "confirm strong momentum" gate).
        const double a = 2.0 / (p.ewma_span + 1.0);
        d_ = d_init_ ? a * r + (1.0 - a) * d_ : r;
        d_init_ = true;
        out_.d = d_;

        const int dir = d_ > 0.0 ? 1 : (d_ < 0.0 ? -1 : 0);
        int agree = 0, pn = std::min(count_, p.persist_len);
        for (int k = 0; k < pn; ++k) {
            const double rk = r_[idx_back_(k)];
            const int sk = rk > 0.0 ? 1 : (rk < 0.0 ? -1 : 0);
            if (dir != 0 && sk == dir) ++agree;
        }
        out_.persist = pn > 0 ? double(agree) / double(pn) : 0.0;

        int rn = std::min(count_, p.retention_len); double rabs = 0.0;
        for (int k = 0; k < rn; ++k) rabs += std::fabs(r_[idx_back_(k)]);
        out_.retention = rn > 0 ? rabs / rn : 0.0;

        double smu, ssd; stats_(spr_, p.z_window, smu, ssd);
        double tmu, tsd; stats_(tck_, p.z_window, tmu, tsd);
        out_.spread_z = ssd > 0.0 ? (spr_[idx_back_(0)] - smu) / ssd : 0.0;
        out_.tick_z   = tsd > 0.0 ? (tck_[idx_back_(0)] - tmu) / tsd : 0.0;

        out_.gated = ext_block || !out_.valid ||
                     out_.spread_z > p.spread_z_max || out_.tick_z > p.tickcount_z_max;

        const double dterm = std::max(-1.0, std::min(1.0, d_ / p.d_ref));
        out_.vmc = out_.gated ? 0.0 : dterm * out_.persist * out_.retention;
    }

    std::vector<double> r_, spr_, tck_;
    int     head_ = 0, count_ = 0, cap_ = 0;
    int64_t prev_mid_pts_ = INT64_MIN;
    int     up_ = 0, dn_ = 0;
    double  cvd_ = 0.0;
    double  d_ = 0.0; bool d_init_ = false;
    int     bars_seen_ = 0;
    VmcOut  out_;
};

}  // namespace kk
