// kenkem_trace_dumper — GOLDEN per-bar decision trace for the distilled KenKem engine.
//
// Purpose: localize the residual E5 over-firing (SYSTEMIC.md plan #2). For every forming M1 bar in a
// window, emit the FULL decision-time state — every indicator the engine reads (shift-1), the E5 trigger
// state, and each sub-decision of the E5 gate for BOTH directions — so it can be diffed field-by-field
// against an identical trace emitted by the deployed MQL5 EA (FileWrite). The FIRST bar where any field
// diverges localizes the bug to indicator-drift vs trigger-state vs gate-decision.
//
// This is a READ-ONLY observer: it mirrors engine.hpp's per-bar sequence (update_triggers -> snapshot ->
// gate) but places NO trades and tracks NO P&L. `sig_fire` = (fresh E5 trigger within max-age) && gate
// passes && in a valid UTC session — the raw signal-level fire, which is exactly where over-firing is
// born (concurrency/cooldown layers are downstream and intentionally excluded). On a fire the trigger is
// consumed, mirroring the engine's one-cross-one-entry re-arm semantics.
//
// Schema is E5-centric (production config is E5-only) but dumps all four TFs' indicators so the same
// trace also serves a full C++<->MQL5 indicator-parity check. The MQL5 side emits the identical columns.
//
// Usage:
//   kenkem_trace_dumper --bars-m1 <m1.csv> [--symbol-btc|--symbol-xau] [--set <file>]
//        [--from-ms <e>] [--to-ms <e>] [--warmup <bars>] --out <trace.csv>
#include <cstdio>
#include <cstdint>
#include <string>
#include <vector>
#include <ctime>
#include <cmath>
#include "kk/common/bars_csv.hpp"
#include "kk/common/types.hpp"
#include "kk/kenkem/kenkem_config.hpp"
#include "kk/kenkem/tf_cache.hpp"
#include "kk/kenkem/triggers.hpp"
#include "kk/kenkem/snapshot.hpp"
#include "kk/kenkem/gates.hpp"
#include "kk/kenkem/entries.hpp"
#include "kk/kenkem/engine.hpp"   // in_valid_session

using namespace kk::kenkem;

static std::vector<kk::Bar> aggregate(const std::vector<kk::Bar>& m1, int tf_minutes) {
    const int64_t w = (int64_t)tf_minutes * 60000;
    std::vector<kk::Bar> out;
    for (const kk::Bar& b : m1) {
        int64_t bucket = (b.ts_ms / w) * w;
        if (out.empty() || out.back().ts_ms != bucket) { kk::Bar nb = b; nb.ts_ms = bucket; out.push_back(nb); }
        else { kk::Bar& c = out.back(); if (b.high>c.high) c.high=b.high; if (b.low<c.low) c.low=b.low; c.close=b.close; c.tick_count+=b.tick_count; }
    }
    return out;
}

static std::string utc(int64_t ts_ms) {
    std::time_t t = (std::time_t)(ts_ms / 1000); std::tm tmv{}; gmtime_r(&t, &tmv);
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%04d.%02d.%02d %02d:%02d", tmv.tm_year+1900, tmv.tm_mon+1, tmv.tm_mday, tmv.tm_hour, tmv.tm_min);
    return buf;
}

// Re-implements the E5 branch of entry_gate_ok() but RECORDS each sub-decision instead of short-circuiting,
// so the trace shows exactly which check blocks the trade. The combined `pass` MUST equal entry_gate_ok().
struct E5Gate {
    int  trig_age = -1;        // B - fired (-1 = no live trigger this dir)
    bool in_age = false;       // trig_age in [0, e5_max_ema_cross_age]
    bool sideways_blk = false; // sideways_blocked
    bool atr_lo_blk = false;   // atr_pctile < min_entry_atr_pctile
    bool atr_hi_blk = false;   // atr_pctile > atr_percentile_high (when enabled)
    bool price_ok = false;     // close vs EMA25 (emaM1[1])
    int  trendcore = 0;        // trend_core_score (0 = hard-gate trip)
    bool tc_ok = false;        // !require || trendcore>0
    int  tq = 0;               // graded GetTrendQualityScore(state,5) (0-13)
    bool tq_ok = false;        // min_tq_e5<=0 || tq >= min_tq_e5  (the #1 over-fire suspect)
    bool adx_ok = false;       // adx[0] >= e5_min_momentum_adx (or floor disabled)
    bool htf_ok = false;       // htf_filter_ok
    bool pass = false;         // overall gate
    bool fire = false;         // in_age && pass (raw signal fire)
};

static E5Gate eval_e5(bool is_long, int B, const TfBundle& b, const TfBundle::Align& al,
                      const TriggerState& tg, const Snapshot& s, const KenKemConfig& c) {
    E5Gate g;
    int fired = is_long ? tg.e5_up : tg.e5_down;
    g.trig_age = (fired >= 0) ? (B - fired) : -1;
    g.in_age   = (fired >= 0) && (B - fired <= c.e5_max_ema_cross_age);
    g.sideways_blk = sideways_blocked(s, c);
    g.atr_lo_blk   = (c.min_entry_atr_pctile > 0.0 && s.atr_pctile < c.min_entry_atr_pctile);
    g.atr_hi_blk   = (c.enable_atr_high_block && c.atr_percentile_high > 0.0 && s.atr_pctile > c.atr_percentile_high);
    g.price_ok     = is_long ? (s.closeM1 > s.emaM1[1]) : (s.closeM1 < s.emaM1[1]);
    g.trendcore    = trend_core_score(s, is_long, c);
    g.tc_ok        = (!c.e5_require_trend_core) || (g.trendcore > 0);
    // Graded trend-quality floor — applied by detect_entry (entries.hpp:140) but previously OMITTED here,
    // so the trace under-modeled the gate. This is the suspected counter-trend-LONG divergence.
    g.tq           = trend_quality_score(b, al, s, is_long, 5, c);
    g.tq_ok        = (c.min_tq_e5 <= 0) || (g.tq >= c.min_tq_e5);
    g.adx_ok       = (c.e5_min_momentum_adx <= 0) || (s.adx[0] >= c.e5_min_momentum_adx);
    g.htf_ok       = htf_filter_ok(s, is_long, c.e5_htf_filter, c.e5_htf_min_adx, c.e5_htf_min_di_spread);
    g.pass = !g.sideways_blk && !g.atr_lo_blk && !g.atr_hi_blk && g.price_ok && g.tc_ok && g.tq_ok && g.adx_ok && g.htf_ok;
    g.fire = g.in_age && g.pass;
    return g;
}

int main(int argc, char** argv) {
    std::string m1_path, set_path, out_path;
    bool xau = false; double spread = -1.0; int warmup = 250; int64_t from_ms = 0, to_ms = 0;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]{ return (i+1 < argc) ? std::string(argv[++i]) : std::string(); };
        if      (a == "--bars-m1")    m1_path = next();
        else if (a == "--set")        set_path = next();
        else if (a == "--out")        out_path = next();
        else if (a == "--symbol-xau") xau = true;
        else if (a == "--symbol-btc") xau = false;
        else if (a == "--spread")     spread = std::stod(next());
        else if (a == "--warmup")     warmup = std::stoi(next());
        else if (a == "--from-ms")    from_ms = std::stoll(next());
        else if (a == "--to-ms")      to_ms = std::stoll(next());
    }
    if (m1_path.empty() || out_path.empty()) { std::fprintf(stderr, "need --bars-m1 AND --out\n"); return 2; }

    KenKemConfig cfg;
    if (xau) cfg.apply_xauusd_specs(); else cfg.apply_btcusd_specs();
    if (spread < 0) spread = xau ? 0.05 : 2.0;
    if (!set_path.empty()) { int n = load_set(cfg, set_path); std::fprintf(stderr, "[set] applied %d keys from %s\n", n, set_path.c_str()); }

    std::vector<kk::Bar> m1 = kk::load_bars_csv(m1_path, 0, to_ms);
    if (m1.empty()) { std::fprintf(stderr, "no M1 bars from %s\n", m1_path.c_str()); return 1; }
    for (kk::Bar& b : m1) b.spread_mean = spread;
    std::vector<kk::Bar> m3 = aggregate(m1, 3), m5 = aggregate(m1, 5), m15 = aggregate(m1, 15);
    TfBundle B = build_tf_bundle(m1, m3, m5, m15, cfg);

    FILE* f = std::fopen(out_path.c_str(), "w");
    if (!f) { std::fprintf(stderr, "cannot open out %s\n", out_path.c_str()); return 1; }
    std::fprintf(f,
        "ts_ms,dt,"
        "ema0,ema1,ema2,ema3,ema4,"
        "adx_m1,adx_m3,adx_m5,adx_m15,diP_m1,diP_m3,diP_m5,diP_m15,diM_m1,diM_m3,diM_m5,diM_m15,"
        "adxS,diPS,diMS,atr,rsi,close,high,low,tenkan,kijun,senkouA_m3,senkouB_m3,sideways,atr_pctile,"
        "e5up_age,e5dn_age,"
        "L_inage,L_swblk,L_atrlo,L_atrhi,L_price,L_tcore,L_tq,L_tqok,L_adx,L_htf,L_pass,L_fire,"
        "S_inage,S_swblk,S_atrlo,S_atrhi,S_price,S_tcore,S_tq,S_tqok,S_adx,S_htf,S_pass,S_fire,"
        "session,fire_dir\n");

    TriggerState tg;
    const int N = B.m1.size();
    int64_t rows = 0, fires = 0;
    for (int b = 1; b < N; ++b) {
        const kk::Bar& bar = B.m1.bars[b];
        if (to_ms && bar.ts_ms >= to_ms) break;
        const TfBundle::Align al = B.align_at(bar.ts_ms);
        update_triggers(B, cfg, b, al, tg);                 // mirror engine ordering (state evolves every bar)
        if (from_ms && bar.ts_ms < from_ms) continue;        // warm triggers/indicators silently before window
        if (b < warmup) continue;
        Snapshot s = build_snapshot(B, cfg, b, al);
        if (!s.valid) continue;

        E5Gate L = eval_e5(true,  b, B, al, tg, s, cfg);
        E5Gate S = eval_e5(false, b, B, al, tg, s, cfg);
        bool session = in_valid_session(bar.ts_ms, cfg);
        // Consume on a session-valid fire (long before short), mirroring detect_entry's one-shot semantics.
        int fire_dir = 0;
        if (session && L.fire)      { fire_dir =  1; tg.e5_up = -1; }
        else if (session && S.fire) { fire_dir = -1; tg.e5_down = -1; }
        if (fire_dir) ++fires;

        auto e5age = [&](int fired){ return fired >= 0 ? (b - fired) : -1; };
        std::fprintf(f,
            "%lld,%s,"
            "%.5f,%.5f,%.5f,%.5f,%.5f,"
            "%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,"
            "%.3f,%.3f,%.3f,%.5f,%.3f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%d,%.2f,"
            "%d,%d,"
            "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,"
            "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,"
            "%d,%d\n",
            (long long)bar.ts_ms, utc(bar.ts_ms).c_str(),
            s.emaM1[0],s.emaM1[1],s.emaM1[2],s.emaM1[3],s.emaM1[4],
            s.adx[0],s.adx[1],s.adx[2],s.adx[3], s.diP[0],s.diP[1],s.diP[2],s.diP[3], s.diM[0],s.diM[1],s.diM[2],s.diM[3],
            s.adxS,s.diPS,s.diMS, s.atrM1,s.rsiM1_avg5, s.closeM1,s.highM1,s.lowM1, s.tenkanM1,s.kijunM1, s.senkouA_M3,s.senkouB_M3, s.sideways,s.atr_pctile,
            e5age(tg.e5_up), e5age(tg.e5_down),
            L.in_age,L.sideways_blk,L.atr_lo_blk,L.atr_hi_blk,L.price_ok,L.trendcore,L.tq,L.tq_ok,L.adx_ok,L.htf_ok,L.pass,L.fire,
            S.in_age,S.sideways_blk,S.atr_lo_blk,S.atr_hi_blk,S.price_ok,S.trendcore,S.tq,S.tq_ok,S.adx_ok,S.htf_ok,S.pass,S.fire,
            session?1:0, fire_dir);
        ++rows;
    }
    std::fclose(f);
    std::fprintf(stderr, "[trace] %lld bars, %lld signal-fires -> %s\n", (long long)rows, (long long)fires, out_path.c_str());
    return 0;
}
