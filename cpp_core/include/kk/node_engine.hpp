// Synthetic order-flow node engine — exact port of Core/NodeStateEngine.mqh.
// Per-bin decayed buy/sell/touch arrays over the SLIDING master [lo,hi] grid (faithful to Pine —
// the grid moves every bar; do not "fix" the slide). Update once per just-closed bar.
#pragma once
#include <vector>
#include <cmath>
#include <algorithm>
#include "kk/types.hpp"
#include "kk/config.hpp"
#include "kk/volume_profile.hpp"   // clamp_i

namespace kk {

class NodeEngine {
public:
    void init(int bins) {
        bins_ = bins;
        buy_.assign(bins, 0.0);
        sell_.assign(bins, 0.0);
        touch_.assign(bins, 0.0);
        m_lo_ = m_hi_ = m_step_ = 0.0;
    }

    // One just-closed bar. masterVP supplies the current sliding master lo/hi.
    void update(const VPResult& masterVP, const Bar& bar, double atr, const Params& p) {
        if (!masterVP.valid) return;
        const double m_lo = masterVP.lo, m_hi = masterVP.hi;
        const double m_step = (m_hi - m_lo) / bins_;
        if (m_step <= 0.0) return;             // Pine guards mStep>0 (no decay when invalid)
        m_lo_ = m_lo; m_hi_ = m_hi; m_step_ = m_step;

        const double o = bar.open, h = bar.high, l = bar.low, c = bar.close;
        const double vol = static_cast<double>(bar.tick_count);
        if (o <= 0 || h <= 0 || l <= 0 || c <= 0 || h < l) return;   // stale-bar guard

        const double touch_dist = std::max(p.node_touch_atr * atr, 2.0 * p.pip_size);
        const double dir_proxy  = (c - o) / std::max(h - l, p.mintick);
        const double buy_proxy  = vol * std::max(dir_proxy, 0.0);
        const double sell_proxy = vol * std::max(-dir_proxy, 0.0);

        for (int b = 0; b < bins_; ++b) { buy_[b] *= p.node_decay; sell_[b] *= p.node_decay; touch_[b] *= p.node_decay; }

        const int low_idx  = vp::clamp_i(static_cast<int>(std::floor((l - m_lo) / m_step)), 0, bins_ - 1);
        const int high_idx = vp::clamp_i(static_cast<int>(std::floor((h - m_lo) / m_step)), 0, bins_ - 1);
        const double span = std::max(static_cast<double>(high_idx - low_idx + 1), 1.0);
        for (int b = low_idx; b <= high_idx; ++b) {
            const double node_px = m_lo + (b + 0.5) * m_step;
            const bool touched = (std::fabs(c - node_px) <= touch_dist) || (l <= node_px && h >= node_px);
            if (touched) {
                touch_[b] += 1.0;
                buy_[b]   += buy_proxy / span;
                sell_[b]  += sell_proxy / span;
            }
        }
    }

    int pick_idx(double px) const {
        if (m_step_ <= 0.0) return 0;
        return vp::clamp_i(static_cast<int>(std::floor((px - m_lo_) / m_step_)), 0, bins_ - 1);
    }

    NodeState state_at(int idx, const Params& p) const {
        NodeState ns;
        if (idx < 0 || idx >= bins_) return ns;
        const double b = buy_[idx], s = sell_[idx], t = touch_[idx];
        const double net = (b - s) / std::max(b + s, 1.0);
        const bool absorbed = (t >= p.node_saturation) && (std::fabs(net) <= p.node_neutral_band);
        ns.state = absorbed ? 0 : (net > p.node_neutral_band ? 1 : (net < -p.node_neutral_band ? -1 : 0));
        ns.net = net; ns.touch = t; ns.absorbed = absorbed;
        return ns;
    }

    NodeState state_at_price(double px, const Params& p) const { return state_at(pick_idx(px), p); }

private:
    int bins_ = 0;
    std::vector<double> buy_, sell_, touch_;
    double m_lo_ = 0.0, m_hi_ = 0.0, m_step_ = 0.0;
};

}  // namespace kk
