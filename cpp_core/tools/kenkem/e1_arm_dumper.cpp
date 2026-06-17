// E1 arm-bar dumper. Replays update_triggers() bar-by-bar (faithful to the engine) and emits EVERY
// E1 arm transition (the bar where tg.ema_up / tg.ema_down flips from -1 to a value). Purpose: since
// arming is a faithful port, we can apply the engine's arm bars to MT5's actual E1 trade entries and
// measure MT5's age-at-fire — answering whether MT5 fires late (like the engine) or only near the arm.
// Output: ts_ms,dt,dir  (dir = L / S).  Bar-based, no ticks, fast (~10s for 2yr).
#include <cstdio>
#include <cstdint>
#include <string>
#include <vector>
#include <ctime>
#include "kk/common/bars_csv.hpp"
#include "kk/common/types.hpp"
#include "kk/kenkem/kenkem_config.hpp"
#include "kk/kenkem/tf_cache.hpp"
#include "kk/kenkem/triggers.hpp"

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
        else if (a == "--from-ms")    from_ms = std::stoll(next());
        else if (a == "--to-ms")      to_ms = std::stoll(next());
    }
    if (m1_path.empty() || out_path.empty()) { std::fprintf(stderr, "need --bars-m1 AND --out\n"); return 2; }

    KenKemConfig cfg;
    if (xau) cfg.apply_xauusd_specs(); else cfg.apply_btcusd_specs();
    if (spread < 0) spread = xau ? 0.05 : 2.0;
    if (!set_path.empty()) { int n = load_set(cfg, set_path); std::fprintf(stderr, "[set] applied %d keys from %s\n", n, set_path.c_str()); }

    std::vector<kk::Bar> m1 = kk::load_bars_csv(m1_path, 0, to_ms);
    if (m1.empty()) { std::fprintf(stderr, "no M1 bars\n"); return 1; }
    for (kk::Bar& b : m1) b.spread_mean = spread;
    std::vector<kk::Bar> m3 = aggregate(m1, 3), m5 = aggregate(m1, 5), m15 = aggregate(m1, 15);
    TfBundle B = build_tf_bundle(m1, m3, m5, m15, cfg);

    FILE* f = std::fopen(out_path.c_str(), "w");
    if (!f) { std::fprintf(stderr, "cannot open out\n"); return 1; }
    std::fprintf(f, "ts_ms,dt,dir\n");

    TriggerState tg;
    int prev_up = -1, prev_down = -1;
    const int N = B.m1.size();
    int64_t armsL = 0, armsS = 0;
    for (int b = 1; b < N; ++b) {
        const kk::Bar& bar = B.m1.bars[b];
        if (to_ms && bar.ts_ms >= to_ms) break;
        const TfBundle::Align al = B.align_at(bar.ts_ms);
        update_triggers(B, cfg, b, al, tg);
        bool in_window = (!from_ms || bar.ts_ms >= from_ms) && b >= warmup;
        // Detect a fresh arm: trigger went from -1 to a set value this bar.
        if (in_window && tg.ema_up != -1 && prev_up == -1)   { std::fprintf(f, "%lld,%s,L\n", (long long)bar.ts_ms, utc(bar.ts_ms).c_str()); ++armsL; }
        if (in_window && tg.ema_down != -1 && prev_down == -1){ std::fprintf(f, "%lld,%s,S\n", (long long)bar.ts_ms, utc(bar.ts_ms).c_str()); ++armsS; }
        prev_up = tg.ema_up; prev_down = tg.ema_down;
    }
    std::fclose(f);
    std::fprintf(stderr, "[e1_arm] L arms %lld  S arms %lld -> %s\n", (long long)armsL, (long long)armsS, out_path.c_str());
    return 0;
}
