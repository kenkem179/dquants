// Sessions + time/volatility/spread filters — port of Utils/SessionManager.mqh. Pure + headless.
// All times are UTC (the EA applies InpBrokerGMTOffset=0, so server == UTC == our tick ts).
//
// Sessions (minute-of-day, UTC):  Asia 1 = [0,360)  London 2 = [420,660)  NY 3 = [750,990).
// SessionId 0 = no session (entries blocked + open positions force-closed).
// Blocked hours veto NEW entries during the listed UTC hours ("8,10,11,16", ranges like "9-11" ok).
// Max trades/session: counter increments on fill, resets when the sessionId changes.
// ATR% band: entry only if min_atr_pct <= atr1/price*100 <= max_atr_pct.
// Spread: entry only if (ask-bid)/pip <= max_spread_pips.
#pragma once
#include <array>
#include <string>
#include <vector>
#include <ctime>
#include "kk/config.hpp"

namespace kk {

// Decompose epoch-ms (UTC) into the fields the filters need.
struct UtcParts { int year, mon, day, hour, min; int day_key; int min_of_day; };
inline UtcParts utc_parts(int64_t ts_ms) {
    const std::time_t t = static_cast<std::time_t>(ts_ms / 1000);
    std::tm tmv{};
#if defined(_WIN32)
    gmtime_s(&tmv, &t);
#else
    gmtime_r(&t, &tmv);
#endif
    UtcParts u;
    u.year = tmv.tm_year + 1900; u.mon = tmv.tm_mon + 1; u.day = tmv.tm_mday;
    u.hour = tmv.tm_hour; u.min = tmv.tm_min;
    u.day_key = u.year * 10000 + u.mon * 100 + u.day;
    u.min_of_day = u.hour * 60 + u.min;
    return u;
}

class Sessions {
public:
    // Parse "HH:MM-HH:MM" windows + the blocked-hours string from Params once.
    void init(const Params& p) {
        asia_ = parse_window(p.asia_sess);
        ldn_  = parse_window(p.ldn_sess);
        ny_   = parse_window(p.ny_sess);
        parse_blocked(p.blocked_hours);
        max_trades_ = p.max_trades_per_session;
        cur_id_ = -1; trades_this_session_ = 0;
    }

    // Asia 1 / London 2 / NY 3 / none 0, at a UTC minute-of-day.
    int session_id(int min_of_day) const {
        if (in_win(min_of_day, asia_)) return 1;
        if (in_win(min_of_day, ldn_))  return 2;
        if (in_win(min_of_day, ny_))   return 3;
        return 0;
    }

    // Per bar: returns the current sessionId, resetting the per-session trade counter on a change.
    int update(int min_of_day) {
        const int id = session_id(min_of_day);
        if (id != cur_id_) { trades_this_session_ = 0; cur_id_ = id; }
        return id;
    }

    bool is_blocked_hour(int hour) const { return hour >= 0 && hour < 24 && blocked_[hour]; }
    bool max_trades_ok() const { return trades_this_session_ < max_trades_; }
    void on_fill() { ++trades_this_session_; }
    int  trades_this_session() const { return trades_this_session_; }

private:
    struct Win { int lo = 0, hi = 0; bool valid = false; };
    static bool in_win(int m, const Win& w) { return w.valid && m >= w.lo && m < w.hi; }

    static Win parse_window(const std::string& s) {
        Win w; const auto dash = s.find('-');
        if (dash == std::string::npos) return w;
        auto hm = [](const std::string& t) -> int {
            const auto c = t.find(':');
            if (c == std::string::npos) return -1;
            return std::stoi(t.substr(0, c)) * 60 + std::stoi(t.substr(c + 1));
        };
        const int lo = hm(s.substr(0, dash)), hi = hm(s.substr(dash + 1));
        if (lo < 0 || hi < 0) return w;
        w.lo = lo; w.hi = hi; w.valid = true;
        return w;
    }

    void parse_blocked(const std::string& raw) {
        blocked_.fill(false);
        std::string s; for (char ch : raw) if (ch != ' ') s += ch;
        size_t i = 0;
        while (i < s.size()) {
            size_t j = s.find(',', i);
            if (j == std::string::npos) j = s.size();
            const std::string tok = s.substr(i, j - i);
            if (!tok.empty()) {
                const auto d = tok.find('-');
                if (d == std::string::npos) {
                    const int h = atoi_safe(tok);
                    if (h >= 0 && h < 24) blocked_[h] = true;
                } else {
                    int lo = atoi_safe(tok.substr(0, d)), hi = atoi_safe(tok.substr(d + 1));
                    if (lo > hi) std::swap(lo, hi);
                    for (int h = lo; h <= hi; ++h) if (h >= 0 && h < 24) blocked_[h] = true;
                }
            }
            i = j + 1;
        }
    }
    static int atoi_safe(const std::string& t) {
        for (char c : t) if (c < '0' || c > '9') return -1;
        return t.empty() ? -1 : std::stoi(t);
    }

    Win asia_, ldn_, ny_;
    std::array<bool, 24> blocked_{};
    int max_trades_ = 4, cur_id_ = -1, trades_this_session_ = 0;
};

// Volatility band: entry only if min_atr_pct <= atr1/price*100 <= max_atr_pct (0 ceiling = off).
inline bool atr_pct_ok(double atr1, double price, const Params& p) {
    if (price <= 0.0) return false;
    const double pct = atr1 / price * 100.0;
    if (pct < p.min_atr_pct) return false;
    if (p.max_atr_pct > 0.0 && pct > p.max_atr_pct) return false;
    return true;
}

// Spread gate: (ask-bid)/pip <= max_spread_pips (0 = off).
inline bool spread_ok(double bid, double ask, const Params& p) {
    if (p.max_spread_pips <= 0.0 || p.pip_size <= 0.0) return true;
    return (ask - bid) / p.pip_size <= p.max_spread_pips;
}

// TP1 cost-clearance: live spread must not eat the TP1 partial (frac<=0 = off).
inline bool spread_vs_tp1_ok(double bid, double ask, double tp1, double entry, const Params& p) {
    if (p.max_spread_tp1_frac <= 0.0) return true;
    const double tp1_dist = std::fabs(tp1 - entry);
    return tp1_dist > 0.0 && (ask - bid) <= p.max_spread_tp1_frac * tp1_dist;
}

}  // namespace kk
