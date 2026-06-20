// vmc_mvp_lab — VMC "support factor" lab for KK-MasterVP (BTCUSD, M5/M3), NON-INVASIVE.
//
// CONTEXT: MasterVP is a Volume-Profile strategy (entries key off VAH/VAL nodes + body/regime), NOT an
// EMA-momentum stack. So VMC's tick-flow net delta is far LESS redundant with the trigger than it was on
// KenKem E1/E5 (where corr(flow,price)~0.5 made VMC restate the entry). The user's directive: wire VMC as
// a SUPPORT/CONFIDENCE factor — "assist the confidence to enter when momentary net volume delta needs a
// support factor." MasterVP already wants a flow factor (DetectSignal's ns.net / sfp_flow_min) but that
// `node_net` is the laundered-price node-engine dirProxy; VMC is the honest tick-based version.
//
// HOW (zero edits to the MasterVP engine/EA): run the REAL MasterVP TickEngine to get baseline trades,
// rebuild the committed per-bar VMC from the SAME tick stream (bucketed to --tf-min), then evaluate VMC as
// a directional support factor on those entries. Reports: independence diagnostic, VMC score scale, a
// threshold-free flow-direction discrimination split (does flow-supports out-win flow-opposes?), a
// magnitude-confirm A/B, and VMC-vs-node_net agreement (does the honest flow agree with the laundered one?).
//
// HONESTY CAVEAT (printed): post-hoc SELECTION, not a re-sim — ignores concurrency/margin coupling. A
// positive result justifies an opt-in engine hook; it does not replace it.
//
// Usage:
//   vmc_mvp_lab --bars <tf.csv> --ticks <ticks.csv> [--symbol-btc|--symbol-xau] [--set <f>]
//       [--tf-min 5] [--trade-from-ms e] [--vmc-confirm 0.01] [--epsilon-pts 1] [--ewma-span 5]
//       [--d-ref 0.10] [--persist-len 5] [--retention-len 5] [--z-window 120] [--warmup-bars 30]
//       [--out-kept <ledger.csv>]
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cmath>
#include <string>
#include <vector>
#include <map>
#include <algorithm>
#include <ctime>
#include "kk/common/config.hpp"
#include "kk/common/bars_csv.hpp"
#include "kk/common/volume_momentum.hpp"
#include "kk/mastervp/tick_engine.hpp"

static std::string utc(int64_t ts_ms) {
    std::time_t t = (std::time_t)(ts_ms / 1000); std::tm tmv{};
    gmtime_r(&t, &tmv);
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%04d.%02d.%02d %02d:%02d", tmv.tm_year+1900, tmv.tm_mon+1, tmv.tm_mday, tmv.tm_hour, tmv.tm_min);
    return buf;
}

struct Stats { int trades=0, wins=0; double net=0, pf=0, win_rate=0, max_dd=0; };
static Stats recompute(std::vector<const kk::TradeRecord*> ts, double start_balance) {
    std::sort(ts.begin(), ts.end(), [](const kk::TradeRecord* a, const kk::TradeRecord* b){ return a->entry_ts_ms < b->entry_ts_ms; });
    Stats s; double bal = start_balance, peak = start_balance, gw = 0, gl = 0;
    for (const kk::TradeRecord* t : ts) {
        s.trades++; s.net += t->realized_usd; bal += t->realized_usd;
        if (t->realized_usd > 0) { s.wins++; gw += t->realized_usd; } else gl += -t->realized_usd;
        if (bal > peak) peak = bal;
        double dd = peak - bal; if (dd > s.max_dd) s.max_dd = dd;
    }
    s.pf = gl > 0 ? gw / gl : (gw > 0 ? 1e9 : 0.0);
    s.win_rate = s.trades > 0 ? (double)s.wins / s.trades : 0.0;
    return s;
}
static void print_stats(const char* label, const Stats& s) {
    std::printf("  %-26s trades %4d  win%% %5.1f  net %10.2f  PF %6.3f  maxDD %9.2f\n",
                label, s.trades, 100.0*s.win_rate, s.net, s.pf, s.max_dd);
}

int main(int argc, char** argv) {
    std::string bars_path, ticks_path, set_path, kept_path;
    bool xau = false;
    int tf_min = 5;
    int64_t trade_from_ms = 0;
    double vmc_confirm = 0.01;
    kk::VmcParams vp; vp.d_ref = 0.10;   // on-scale defaults learned from the KenKem lab

    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]{ return (i+1 < argc) ? std::string(argv[++i]) : std::string(); };
        if      (a == "--bars")          bars_path = next();
        else if (a == "--ticks")         ticks_path = next();
        else if (a == "--set")           set_path = next();
        else if (a == "--out-kept")      kept_path = next();
        else if (a == "--symbol-xau")    xau = true;
        else if (a == "--symbol-btc")    xau = false;
        else if (a == "--tf-min")        tf_min = std::stoi(next());
        else if (a == "--trade-from-ms") trade_from_ms = std::stoll(next());
        else if (a == "--vmc-confirm")   vmc_confirm = std::stod(next());
        else if (a == "--epsilon-pts")   vp.epsilon_pts = std::stoi(next());
        else if (a == "--ewma-span")     vp.ewma_span = std::stoi(next());
        else if (a == "--d-ref")         vp.d_ref = std::stod(next());
        else if (a == "--persist-len")   vp.persist_len = std::stoi(next());
        else if (a == "--retention-len") vp.retention_len = std::stoi(next());
        else if (a == "--z-window")      vp.z_window = std::stoi(next());
        else if (a == "--warmup-bars")   vp.warmup_bars = std::stoi(next());
    }
    if (bars_path.empty() || ticks_path.empty()) { std::fprintf(stderr, "need --bars AND --ticks\n"); return 2; }

    kk::Params p;
    if (xau) p.apply_xauusd_specs(); else p.apply_btcusd_specs();
    if (!set_path.empty()) {
        int n = kk::load_set(p, set_path, /*mimic_mt5_noninput=*/true);
        std::fprintf(stderr, "[set] applied %d keys from %s\n", n, set_path.c_str());
    }
    const double point = p.mintick > 0 ? p.mintick : 0.01;
    const int64_t tf_ms = (int64_t)tf_min * 60000;

    std::vector<kk::Bar> bars = kk::load_bars_csv(bars_path);
    if (bars.empty()) { std::fprintf(stderr, "no bars from %s\n", bars_path.c_str()); return 1; }
    std::map<int64_t, const kk::Bar*> bar_by_ts;
    for (const kk::Bar& b : bars) bar_by_ts[b.ts_ms] = &b;

    // ---- PASS 1: run the REAL MasterVP engine for the baseline trade list. ----
    kk::TickEngine eng(p);
    eng.load_bars(bars, trade_from_ms);
    {
        std::FILE* fi = std::fopen(ticks_path.c_str(), "rb");
        if (!fi) { std::fprintf(stderr, "cannot open ticks %s\n", ticks_path.c_str()); return 1; }
        char line[256]; bool first = true; kk::Tick last{};
        while (std::fgets(line, sizeof(line), fi)) {
            if (first) { first = false; if (line[0] < '0' || line[0] > '9') continue; }
            kk::Tick t;
            if (std::sscanf(line, "%lld,%lf,%lf", (long long*)&t.ts_ms, &t.bid, &t.ask) != 3) continue;
            eng.on_tick(t); last = t;
        }
        std::fclose(fi);
        eng.finish(last.bid, last.ask, last.ts_ms);
    }
    const std::vector<kk::TradeRecord>& trades = eng.trades();

    // ---- PASS 2: rebuild committed per-bar VMC from the SAME ticks (bucketed to tf_min). ----
    std::map<int64_t, kk::VmcOut> vmc_by_close_ts;
    double sx=0, sy=0, sxx=0, syy=0, sxy=0; long npairs=0, ndisagree=0, nboth=0;
    std::vector<double> all_absd, all_absvmc; long n_gated=0, n_valid=0;
    {
        kk::VolumeMomentum vmc; vmc.init(vp);
        std::FILE* fi = std::fopen(ticks_path.c_str(), "rb");
        if (!fi) { std::fprintf(stderr, "cannot reopen ticks %s\n", ticks_path.c_str()); return 1; }
        char line[256]; bool first = true; int64_t cur_bucket = -1;
        while (std::fgets(line, sizeof(line), fi)) {
            if (first) { first = false; if (line[0] < '0' || line[0] > '9') continue; }
            kk::Tick t;
            if (std::sscanf(line, "%lld,%lf,%lf", (long long*)&t.ts_ms, &t.bid, &t.ask) != 3) continue;
            int64_t bucket = (t.ts_ms / tf_ms) * tf_ms;
            if (cur_bucket == -1) cur_bucket = bucket;
            if (bucket != cur_bucket) {
                auto it = bar_by_ts.find(cur_bucket);
                if (it != bar_by_ts.end()) {
                    const kk::Bar& cb = *it->second;
                    const kk::VmcOut& o = vmc.on_bar_close(cb, /*ext_block=*/false, vp);
                    vmc_by_close_ts[cur_bucket] = o;
                    double body = (cb.close - cb.open) / point;
                    sx += o.r; sy += body; sxx += o.r*o.r; syy += body*body; sxy += o.r*body; ++npairs;
                    int sr = o.r > 0 ? 1 : (o.r < 0 ? -1 : 0);
                    int sb = body > 0 ? 1 : (body < 0 ? -1 : 0);
                    if (sr != 0 && sb != 0) { ++nboth; if (sr != sb) ++ndisagree; }
                    if (o.valid) ++n_valid;
                    if (o.gated) ++n_gated;
                    if (o.valid && !o.gated) { all_absd.push_back(std::fabs(o.d)); all_absvmc.push_back(std::fabs(o.vmc)); }
                } else {
                    kk::Bar gap{}; gap.ts_ms = cur_bucket;
                    vmc.on_bar_close(gap, false, vp);
                }
                cur_bucket = bucket;
            }
            vmc.on_tick(t.bid, t.ask, point, vp);
        }
        std::fclose(fi);
    }

    // ---- evaluate VMC as a support factor on MasterVP entries ----
    std::vector<const kk::TradeRecord*> base_all, kept, flow_agree, flow_oppose;
    long n_vmc_node_agree=0, n_vmc_node_both=0; int vetoed=0, no_vmc=0;
    for (const kk::TradeRecord& t : trades) {
        base_all.push_back(&t);
        int64_t entry_bar_open = (t.entry_ts_ms / tf_ms) * tf_ms;
        int64_t close1_open    = entry_bar_open - tf_ms;   // close[F-1] = bar the signal/decision used
        auto it = vmc_by_close_ts.find(close1_open);
        bool keep = true;
        if (it == vmc_by_close_ts.end()) { ++no_vmc; keep = true; }
        else {
            const kk::VmcOut& o = it->second;
            int dir = t.is_long ? 1 : -1;
            bool confirms = o.valid && !o.gated && (dir>0 ? o.vmc>=vmc_confirm : o.vmc<=-vmc_confirm);
            keep = confirms; if (!keep) ++vetoed;
            double align = dir * o.d;
            if (o.valid && !o.gated && align > 0.0) flow_agree.push_back(&t); else flow_oppose.push_back(&t);
            // VMC honest flow vs MasterVP's laundered node_net: do their signs agree at entry?
            int sd = o.d > 0 ? 1 : (o.d < 0 ? -1 : 0);
            int sn = t.node_net > 0 ? 1 : (t.node_net < 0 ? -1 : 0);
            if (sd != 0 && sn != 0) { ++n_vmc_node_both; if (sd == sn) ++n_vmc_node_agree; }
        }
        if (keep) kept.push_back(&t);
    }

    // ---- report ----
    std::printf("=== VMC MasterVP-lab (%s, M%d) ===\n", xau ? "XAUUSD" : "BTCUSD", tf_min);
    std::printf("bars: %zu   committed-VMC bars: %zu   baseline trades: %zu\n",
                bars.size(), vmc_by_close_ts.size(), trades.size());
    std::printf("VMC params: eps=%d ewma=%d d_ref=%.2f persist=%d retention=%d zwin=%d warmup=%d | confirm=%.3f | point=%.5f\n",
                vp.epsilon_pts, vp.ewma_span, vp.d_ref, vp.persist_len, vp.retention_len,
                vp.z_window, vp.warmup_bars, vmc_confirm, point);

    std::printf("\n-- independence diagnostic (is r_b laundered price? lower = more independent) --\n");
    if (npairs > 1) {
        double cov = sxy/npairs - (sx/npairs)*(sy/npairs);
        double vx  = sxx/npairs - (sx/npairs)*(sx/npairs);
        double vy  = syy/npairs - (sy/npairs)*(sy/npairs);
        double corr = (vx > 0 && vy > 0) ? cov/std::sqrt(vx*vy) : 0.0;
        std::printf("  corr(r_b, bar body) = %+.3f over %ld bars   sign-disagreement %.1f%% (%ld/%ld)\n",
                    corr, npairs, nboth>0?100.0*ndisagree/nboth:0.0, ndisagree, nboth);
    }
    std::printf("  VMC-vs-MasterVP node_net sign agreement: %.1f%% (%ld/%ld entries)\n",
                n_vmc_node_both>0 ? 100.0*n_vmc_node_agree/n_vmc_node_both : 0.0, n_vmc_node_agree, n_vmc_node_both);

    std::printf("\n-- VMC score scale (valid, non-gated bars) --\n");
    std::printf("  valid %ld  gated %ld (%.1f%%)  acted-on %zu\n",
                n_valid, n_gated, n_valid>0?100.0*n_gated/(n_valid+n_gated):0.0, all_absvmc.size());
    auto pct = [](std::vector<double>& v, double q){ if(v.empty()) return 0.0; size_t i=(size_t)(q*(v.size()-1)); return v[i]; };
    std::sort(all_absd.begin(), all_absd.end()); std::sort(all_absvmc.begin(), all_absvmc.end());
    std::printf("  |d|   p50 %.4f p75 %.4f p90 %.4f p99 %.4f max %.4f\n",
                pct(all_absd,0.5),pct(all_absd,0.75),pct(all_absd,0.9),pct(all_absd,0.99), all_absd.empty()?0.0:all_absd.back());
    std::printf("  |vmc| p50 %.4f p75 %.4f p90 %.4f p99 %.4f max %.4f\n",
                pct(all_absvmc,0.5),pct(all_absvmc,0.75),pct(all_absvmc,0.9),pct(all_absvmc,0.99), all_absvmc.empty()?0.0:all_absvmc.back());

    std::printf("\n-- A/B: VMC magnitude-confirm support gate --\n");
    std::printf("  baseline %zu  VMC vetoed %d  kept %zu  (no-VMC-data %d)\n",
                trades.size(), vetoed, kept.size(), no_vmc);
    Stats sb = recompute(base_all, p.start_balance);
    Stats sk = recompute(kept,     p.start_balance);
    print_stats("baseline (all entries)", sb);
    print_stats("VMC-confirm kept",       sk);

    std::printf("\n-- threshold-free discrimination (flow direction vs outcome) --\n");
    Stats sa = recompute(flow_agree,  p.start_balance);
    Stats so = recompute(flow_oppose, p.start_balance);
    print_stats("flow SUPPORTS dir", sa);
    print_stats("flow OPPOSES/flat", so);
    std::printf("  => VMC is a useful support factor iff SUPPORTS win%%/PF materially beats OPPOSES.\n");

    // Confirm-threshold plateau sweep (reuses the single VMC pass; no file re-read). A real edge is a
    // PLATEAU across thresholds, not a single lucky knob. confirm=0 keeps every valid/non-gated entry
    // whose flow merely agrees in sign; higher confirm demands a stronger |vmc|.
    std::printf("\n-- magnitude-confirm threshold sweep (support gate) --\n");
    const double grid[] = {0.000, 0.005, 0.010, 0.020, 0.030, 0.050};
    std::printf("  %-8s %6s %6s %10s %7s\n", "confirm", "kept", "win%", "net", "PF");
    for (double thr : grid) {
        std::vector<const kk::TradeRecord*> kk_keep;
        for (const kk::TradeRecord& t : trades) {
            int64_t c1 = ((t.entry_ts_ms/tf_ms)*tf_ms) - tf_ms;
            auto it = vmc_by_close_ts.find(c1);
            bool keep = true;
            if (it != vmc_by_close_ts.end()) {
                const kk::VmcOut& o = it->second; int dir = t.is_long?1:-1;
                keep = o.valid && !o.gated && (dir>0 ? o.vmc>=thr : o.vmc<=-thr);
            }
            if (keep) kk_keep.push_back(&t);
        }
        Stats s = recompute(kk_keep, p.start_balance);
        std::printf("  %-8.3f %6d %6.1f %10.2f %7.3f\n", thr, s.trades, 100.0*s.win_rate, s.net, s.pf);
    }

    if (!kept_path.empty()) {
        FILE* f = std::fopen(kept_path.c_str(), "w");
        if (f) {
            std::fprintf(f, "entryTimeUTC,dir,entry,realizedUsd,vmc,d,node_net,kept\n");
            for (const kk::TradeRecord& t : trades) {
                int64_t close1_open = ((t.entry_ts_ms/tf_ms)*tf_ms) - tf_ms;
                double vmcval=0, dval=0; bool kp=true;
                auto it = vmc_by_close_ts.find(close1_open);
                if (it != vmc_by_close_ts.end()) {
                    vmcval = it->second.vmc; dval = it->second.d;
                    int dir = t.is_long ? 1 : -1;
                    kp = it->second.valid && !it->second.gated && (dir>0?vmcval>=vmc_confirm:vmcval<=-vmc_confirm);
                }
                std::fprintf(f, "%s,%s,%.2f,%.2f,%+.4f,%+.4f,%+.3f,%d\n",
                             utc(t.entry_ts_ms).c_str(), t.is_long?"L":"S", t.entry, t.realized_usd,
                             vmcval, dval, t.node_net, kp?1:0);
            }
            std::fclose(f);
            std::fprintf(stderr, "[out] kept-decision ledger -> %s\n", kept_path.c_str());
        }
    }
    return 0;
}
