// vmc_e1_lab — VMC "in action" A/B lab for KenKem E1 (and E2/E4/E5), NON-INVASIVE.
//
// WHY A SEPARATE TOOL: the production KenKem engine (tick_engine.hpp) and the MQL5 EA are already
// working/parity-tuned — we do NOT touch them. This lab runs the REAL TickEngine to produce the
// baseline trade list exactly as KenKem fires today, then REBUILDS the committed per-bar VMC from the
// SAME tick stream and applies VMC as a POST-HOC directional veto on the chosen entry kind (E1 by
// default). We then recompute net/PF/DD/win% on (a) baseline vs (b) VMC-kept, so we can see whether
// VMC's order-flow confirmation improves E1's trade SELECTION — before spending any risk wiring it
// into the live engine.
//
// HONESTY CAVEAT (printed at runtime too): this is a trade-SELECTION test, not a full re-simulation.
// Dropping a trade post-hoc ignores concurrency/margin coupling (a vetoed trade could have blocked or
// freed a later one). The engine is single-position-ish, so the coupling is small, but a confirmed
// win here justifies the next step (an opt-in engine hook), it does not replace it.
//
// It also prints the data-analytics the VMC spec still owed: corr(r_b, bar body) and the sign-
// disagreement rate — the evidence that r_b is (partly) INDEPENDENT of price, not laundered price.
//
// Usage:
//   vmc_e1_lab --bars-m1 <m1.csv> --ticks <ticks.csv> [--symbol-xau|--symbol-btc] [--set <f>]
//       [--from-ms e] [--to-ms e] [--warmup n] [--kind 1|2|4|5] [--vmc-confirm 0.20]
//       [--epsilon-pts 1] [--ewma-span 5] [--d-ref 0.5] [--persist-len 5] [--retention-len 5]
//       [--z-window 120] [--warmup-bars 30] [--out-kept <trades.csv>]
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cmath>
#include <string>
#include <vector>
#include <map>
#include <ctime>
#include "kk/common/bars_csv.hpp"
#include "kk/common/types.hpp"
#include "kk/common/volume_momentum.hpp"
#include "kk/kenkem/kenkem_config.hpp"
#include "kk/kenkem/tick_engine.hpp"

using namespace kk::kenkem;

static std::vector<kk::Bar> aggregate(const std::vector<kk::Bar>& m1, int tf_minutes) {
    const int64_t w = (int64_t)tf_minutes * 60000;
    std::vector<kk::Bar> out;
    for (const kk::Bar& b : m1) {
        int64_t bucket = (b.ts_ms / w) * w;
        if (out.empty() || out.back().ts_ms != bucket) {
            kk::Bar nb = b; nb.ts_ms = bucket; out.push_back(nb);
        } else {
            kk::Bar& cur = out.back();
            if (b.high > cur.high) cur.high = b.high;
            if (b.low  < cur.low)  cur.low  = b.low;
            cur.close = b.close;
            cur.tick_count += b.tick_count;
        }
    }
    return out;
}

static std::string utc(int64_t ts_ms) {
    std::time_t t = (std::time_t)(ts_ms / 1000); std::tm tmv{};
    gmtime_r(&t, &tmv);
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%04d.%02d.%02d %02d:%02d", tmv.tm_year+1900, tmv.tm_mon+1, tmv.tm_mday, tmv.tm_hour, tmv.tm_min);
    return buf;
}

// Recompute portfolio stats from an arbitrary (time-ordered) trade subset. Mirrors the engine's
// accounting: PF = gross win / gross loss, max DD on the running balance curve.
struct Stats { int trades=0, wins=0; double net=0, pf=0, win_rate=0, max_dd=0, end_balance=0; };
static Stats recompute(std::vector<const Trade*> ts, double start_balance) {
    std::sort(ts.begin(), ts.end(), [](const Trade* a, const Trade* b){ return a->t_in < b->t_in; });
    Stats s; s.end_balance = start_balance;
    double bal = start_balance, peak = start_balance, gw = 0, gl = 0;
    for (const Trade* t : ts) {
        s.trades++; s.net += t->pnl; bal += t->pnl;
        if (t->pnl > 0) { s.wins++; gw += t->pnl; } else gl += -t->pnl;
        if (bal > peak) peak = bal;
        double dd = peak - bal; if (dd > s.max_dd) s.max_dd = dd;
    }
    s.end_balance = bal;
    s.pf = gl > 0 ? gw / gl : (gw > 0 ? 1e9 : 0.0);
    s.win_rate = s.trades > 0 ? (double)s.wins / s.trades : 0.0;
    return s;
}

static void print_stats(const char* label, const Stats& s) {
    std::printf("  %-22s trades %4d  win%% %5.1f  net %10.2f  PF %6.3f  maxDD %9.2f\n",
                label, s.trades, 100.0*s.win_rate, s.net, s.pf, s.max_dd);
}

int main(int argc, char** argv) {
    std::string m1_path, ticks_path, set_path, kept_path;
    bool xau = false;
    double spread = -1.0;
    int warmup = 250, target_kind = 1;
    int64_t from_ms = 0, to_ms = 0;
    double vmc_confirm = 0.20;
    kk::VmcParams vp;  // C++ defaults (epsilon=1, ewma=5, d_ref=0.5, persist=5, retention=5, zwin=120, warmup=30)

    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]{ return (i+1 < argc) ? std::string(argv[++i]) : std::string(); };
        if      (a == "--bars-m1")       m1_path = next();
        else if (a == "--ticks")         ticks_path = next();
        else if (a == "--set")           set_path = next();
        else if (a == "--out-kept")      kept_path = next();
        else if (a == "--symbol-xau")    xau = true;
        else if (a == "--symbol-btc")    xau = false;
        else if (a == "--spread")        spread = std::stod(next());
        else if (a == "--warmup")        warmup = std::stoi(next());
        else if (a == "--from-ms")       from_ms = std::stoll(next());
        else if (a == "--to-ms")         to_ms = std::stoll(next());
        else if (a == "--kind")          target_kind = std::stoi(next());
        else if (a == "--vmc-confirm")   vmc_confirm = std::stod(next());
        else if (a == "--epsilon-pts")   vp.epsilon_pts = std::stoi(next());
        else if (a == "--ewma-span")     vp.ewma_span = std::stoi(next());
        else if (a == "--d-ref")         vp.d_ref = std::stod(next());
        else if (a == "--persist-len")   vp.persist_len = std::stoi(next());
        else if (a == "--retention-len") vp.retention_len = std::stoi(next());
        else if (a == "--z-window")      vp.z_window = std::stoi(next());
        else if (a == "--warmup-bars")   vp.warmup_bars = std::stoi(next());
    }
    if (m1_path.empty() || ticks_path.empty()) { std::fprintf(stderr, "need --bars-m1 AND --ticks\n"); return 2; }

    KenKemConfig cfg;
    if (xau) cfg.apply_xauusd_specs(); else cfg.apply_btcusd_specs();
    if (spread < 0) spread = xau ? 0.05 : 2.0;
    if (!set_path.empty()) {
        int n = load_set(cfg, set_path);
        std::fprintf(stderr, "[set] applied %d keys from %s\n", n, set_path.c_str());
    }
    cfg.spread_price = spread;
    if (const char* e = std::getenv("KK_E1_FAITHFUL"))    cfg.e1_faithful_trigger = std::atoi(e) != 0;
    if (const char* e = std::getenv("KK_TRAIL_LIVE_RISK")) cfg.trail_live_risk = std::atoi(e) != 0;

    std::vector<kk::Bar> m1 = kk::load_bars_csv(m1_path, 0, to_ms);
    if (m1.empty()) { std::fprintf(stderr, "no M1 bars from %s\n", m1_path.c_str()); return 1; }
    for (kk::Bar& b : m1) b.spread_mean = spread;
    std::vector<kk::Bar> m3 = aggregate(m1, 3), m5 = aggregate(m1, 5), m15 = aggregate(m1, 15);
    TfBundle bundle = build_tf_bundle(m1, m3, m5, m15, cfg);

    const double point = xau ? 0.01 : 0.01;   // XAU point 0.01; BTC point 0.01 on this feed

    // Index M1 bars by open ts so we can attach spread/tick_count to each closed bar for VMC.
    std::map<int64_t, const kk::Bar*> bar_by_ts;
    for (const kk::Bar& b : m1) bar_by_ts[b.ts_ms] = &b;

    // ---- PASS 1: run the REAL engine to get the baseline trade list. ----
    TickEngine eng(bundle, cfg, warmup, from_ms, to_ms);
    {
        std::FILE* fi = std::fopen(ticks_path.c_str(), "rb");
        if (!fi) { std::fprintf(stderr, "cannot open ticks %s\n", ticks_path.c_str()); return 1; }
        char line[256]; bool first = true; kk::Tick last{};
        while (std::fgets(line, sizeof(line), fi)) {
            if (first) { first = false; if (line[0] < '0' || line[0] > '9') continue; }
            kk::Tick t;
            if (std::sscanf(line, "%lld,%lf,%lf", (long long*)&t.ts_ms, &t.bid, &t.ask) != 3) continue;
            if (to_ms && t.ts_ms >= to_ms) break;
            eng.on_tick(t); last = t;
        }
        std::fclose(fi);
        eng.finish(last.bid, last.ask, last.ts_ms);
    }
    BtResult R = eng.result();

    // ---- PASS 2: rebuild committed per-bar VMC from the SAME ticks. ----
    // vmc_by_close_ts[bar_open_ts] = committed VMC the instant that bar closed (== known at next bar).
    std::map<int64_t, kk::VmcOut> vmc_by_close_ts;
    // independence diagnostic accumulators: corr(r_b, bar_body_in_points)
    double sx=0, sy=0, sxx=0, syy=0, sxy=0; long npairs=0, ndisagree=0, nboth=0;
    // score-scale accumulators: how big are |d| and |vmc| really, and how often gated?
    std::vector<double> all_absd, all_absvmc; long n_gated=0, n_valid=0;
    {
        kk::VolumeMomentum vmc; vmc.init(vp);
        std::FILE* fi = std::fopen(ticks_path.c_str(), "rb");
        if (!fi) { std::fprintf(stderr, "cannot reopen ticks %s\n", ticks_path.c_str()); return 1; }
        char line[256]; bool first = true;
        int64_t cur_bucket = -1;
        while (std::fgets(line, sizeof(line), fi)) {
            if (first) { first = false; if (line[0] < '0' || line[0] > '9') continue; }
            kk::Tick t;
            if (std::sscanf(line, "%lld,%lf,%lf", (long long*)&t.ts_ms, &t.bid, &t.ask) != 3) continue;
            if (to_ms && t.ts_ms >= to_ms) break;
            int64_t bucket = (t.ts_ms / 60000) * 60000;
            if (cur_bucket == -1) cur_bucket = bucket;
            if (bucket != cur_bucket) {
                // bar `cur_bucket` just closed — commit it.
                auto it = bar_by_ts.find(cur_bucket);
                if (it != bar_by_ts.end()) {
                    const kk::Bar& cb = *it->second;
                    const kk::VmcOut& o = vmc.on_bar_close(cb, /*ext_block=*/false, vp);
                    vmc_by_close_ts[cur_bucket] = o;
                    // independence: r_b vs the bar body (close-open) in points.
                    double body = (cb.close - cb.open) / point;
                    sx += o.r; sy += body; sxx += o.r*o.r; syy += body*body; sxy += o.r*body; ++npairs;
                    int sr = o.r > 0 ? 1 : (o.r < 0 ? -1 : 0);
                    int sb = body > 0 ? 1 : (body < 0 ? -1 : 0);
                    if (sr != 0 && sb != 0) { ++nboth; if (sr != sb) ++ndisagree; }
                    // score scale (only over valid, non-gated bars — the bars VMC would actually act on).
                    if (o.valid) ++n_valid;
                    if (o.gated) ++n_gated;
                    if (o.valid && !o.gated) { all_absd.push_back(std::fabs(o.d)); all_absvmc.push_back(std::fabs(o.vmc)); }
                } else {
                    // bar with no M1 row (gap) — commit a synthetic flat bar so state advances.
                    kk::Bar gap{}; gap.ts_ms = cur_bucket; gap.spread_mean = spread;
                    vmc.on_bar_close(gap, false, vp);
                }
                cur_bucket = bucket;
            }
            vmc.on_tick(t.bid, t.ask, point, vp);
        }
        std::fclose(fi);
    }

    // ---- A/B: apply VMC veto to the target kind. ----
    std::vector<const Trade*> base_all, base_kind, kept_kind, kept_portfolio;
    // threshold-free discrimination: does entry-bar flow DIRECTION (sign of dir*d) separate
    // winners from losers? agree = flow points the trade's way; oppose = flat or against.
    std::vector<const Trade*> flow_agree, flow_oppose;
    int vetoed = 0, no_vmc = 0;
    for (const Trade& t : R.list) {
        base_all.push_back(&t);
        bool is_target = (t.kind == target_kind);
        if (is_target) base_kind.push_back(&t);

        bool keep = true;
        if (is_target) {
            int64_t entry_bar_open = (t.t_in / 60000) * 60000;
            int64_t close1_open    = entry_bar_open - 60000;   // close[1] = bar the decision used
            auto it = vmc_by_close_ts.find(close1_open);
            if (it == vmc_by_close_ts.end()) { ++no_vmc; keep = true; }  // no data -> don't veto
            else {
                const kk::VmcOut& o = it->second;
                int dir = t.is_long ? 1 : -1;
                bool confirms = o.valid && !o.gated &&
                                (dir > 0 ? o.vmc >= vmc_confirm : o.vmc <= -vmc_confirm);
                keep = confirms;
                if (!keep) ++vetoed;
                // threshold-free split on flow DIRECTION agreement (uses raw d, not the tiny vmc product).
                double align = dir * o.d;
                if (o.valid && !o.gated && align > 0.0) flow_agree.push_back(&t);
                else flow_oppose.push_back(&t);
            }
            if (keep) kept_kind.push_back(&t);
        }
        if (keep) kept_portfolio.push_back(&t);
    }

    // ---- report ----
    std::printf("=== VMC E1-lab (%s, kind=E%d) ===\n", xau ? "XAUUSD" : "BTCUSD", target_kind);
    std::printf("M1 bars: %d   committed-VMC bars: %zu   baseline trades: %d\n",
                (int)m1.size(), vmc_by_close_ts.size(), R.trades);
    std::printf("VMC params: eps=%d ewma=%d d_ref=%.2f persist=%d retention=%d zwin=%d warmup=%d | confirm=%.3f\n",
                vp.epsilon_pts, vp.ewma_span, vp.d_ref, vp.persist_len, vp.retention_len,
                vp.z_window, vp.warmup_bars, vmc_confirm);

    std::printf("\n-- independence diagnostic (the whole point: is r_b laundered price?) --\n");
    if (npairs > 1) {
        double cov = sxy/npairs - (sx/npairs)*(sy/npairs);
        double vx  = sxx/npairs - (sx/npairs)*(sx/npairs);
        double vy  = syy/npairs - (sy/npairs)*(sy/npairs);
        double corr = (vx > 0 && vy > 0) ? cov/std::sqrt(vx*vy) : 0.0;
        std::printf("  corr(r_b, bar body)         = %+.3f   over %ld bars\n", corr, npairs);
        std::printf("  sign-disagreement rate      = %.1f%%  (%ld of %ld signed bars: r_b vs body disagree)\n",
                    nboth>0 ? 100.0*ndisagree/nboth : 0.0, ndisagree, nboth);
        std::printf("  (low |corr| + healthy disagreement => r_b carries info the OHLC body throws away)\n");
    } else std::printf("  (insufficient bars)\n");

    // score-scale: the threshold MUST live on this scale or the A/B is degenerate (100% veto).
    std::printf("\n-- VMC score scale (valid, non-gated bars only) --\n");
    std::printf("  valid bars %ld   gated %ld (%.1f%%)   acted-on (valid&!gated) %zu\n",
                n_valid, n_gated, n_valid>0 ? 100.0*n_gated/(n_valid+n_gated) : 0.0, all_absvmc.size());
    auto pct = [](std::vector<double>& v, double q){ if(v.empty()) return 0.0; size_t i=(size_t)(q*(v.size()-1)); return v[i]; };
    std::sort(all_absd.begin(), all_absd.end());
    std::sort(all_absvmc.begin(), all_absvmc.end());
    std::printf("  |d|   p50 %.4f  p75 %.4f  p90 %.4f  p99 %.4f  max %.4f\n",
                pct(all_absd,0.50), pct(all_absd,0.75), pct(all_absd,0.90), pct(all_absd,0.99),
                all_absd.empty()?0.0:all_absd.back());
    std::printf("  |vmc| p50 %.4f  p75 %.4f  p90 %.4f  p99 %.4f  max %.4f\n",
                pct(all_absvmc,0.50), pct(all_absvmc,0.75), pct(all_absvmc,0.90), pct(all_absvmc,0.99),
                all_absvmc.empty()?0.0:all_absvmc.back());

    std::printf("\n-- A/B on E%d selection --\n", target_kind);
    std::printf("  E%d baseline trades: %d   VMC vetoed: %d   kept: %d   (no-VMC-data, not vetoed: %d)\n",
                target_kind, (int)base_kind.size(), vetoed, (int)kept_kind.size(), no_vmc);
    Stats sb_all  = recompute(base_all,        cfg.start_balance);
    Stats sb_kind = recompute(base_kind,       cfg.start_balance);
    Stats sk_kind = recompute(kept_kind,       cfg.start_balance);
    Stats sk_port = recompute(kept_portfolio,  cfg.start_balance);
    std::printf("\n  [E%d subset only]\n", target_kind);
    print_stats("baseline E-kind", sb_kind);
    print_stats("VMC-kept E-kind",  sk_kind);
    std::printf("\n  [full portfolio]\n");
    print_stats("baseline all",     sb_all);
    print_stats("VMC-kept (E-kind filtered)", sk_port);

    // The honest, threshold-free test: if flow-agrees trades out-win flow-opposes, VMC has real
    // directional edge on this kind. If they're indistinguishable, VMC is not a useful E%d gate
    // regardless of where you put the threshold.
    std::printf("\n-- threshold-free discrimination on E%d (flow direction vs outcome) --\n", target_kind);
    Stats s_agree  = recompute(flow_agree,  cfg.start_balance);
    Stats s_oppose = recompute(flow_oppose, cfg.start_balance);
    print_stats("flow AGREES dir", s_agree);
    print_stats("flow OPPOSES/flat", s_oppose);
    std::printf("  => edge iff AGREES win%%/PF materially exceeds OPPOSES (need n in both buckets to matter).\n");

    if (!kept_path.empty()) {
        FILE* f = std::fopen(kept_path.c_str(), "w");
        if (f) {
            std::fprintf(f, "entryTimeUTC,dir,kind,entry,realizedUsd,vmc,kept\n");
            for (const Trade& t : R.list) {
                int64_t close1_open = ((t.t_in/60000)*60000) - 60000;
                double vmcval = 0; bool kept = true;
                if (t.kind == target_kind) {
                    auto it = vmc_by_close_ts.find(close1_open);
                    if (it != vmc_by_close_ts.end()) {
                        vmcval = it->second.vmc;
                        int dir = t.is_long ? 1 : -1;
                        kept = it->second.valid && !it->second.gated &&
                               (dir>0 ? vmcval>=vmc_confirm : vmcval<=-vmc_confirm);
                    }
                }
                std::fprintf(f, "%s,%s,E%d,%.3f,%.2f,%+.4f,%d\n",
                             utc(t.t_in).c_str(), t.is_long?"L":"S", t.kind, t.entry, t.pnl, vmcval, kept?1:0);
            }
            std::fclose(f);
            std::fprintf(stderr, "[out] kept-decision ledger -> %s\n", kept_path.c_str());
        }
    }
    return 0;
}
