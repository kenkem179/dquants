// kenkem_entry_trace — per-bar E1/E2/E4 entry-DECISION trace (the Stage-2 localizer).
//
// For every forming M1 bar it evaluates the E1/E2/E4 gate stack for BOTH directions and reports, per
// (kind,dir), the FIRST gate that rejects (or PASS) plus the key scores — mirroring entry_gate_ok()
// in entries.hpp exactly, but recording each sub-decision instead of short-circuiting. Diff this at the
// MT5 entry bars: MT5 took the trade there, so every faithful gate MUST pass; whichever gate this trace
// shows rejecting at an MT5 bar is the divergent gate. Conversely at engine-only fire bars it shows what
// (if anything) should have blocked. READ-ONLY: no trades, no P&L, no concurrency (that is downstream).
//
// Usage: kenkem_entry_trace --bars-m1 <m1.csv> [--symbol-xau|--symbol-btc] [--set <f>]
//        [--from-ms e] [--to-ms e] [--warmup n] [--only <ts_ms,ts_ms,...>] --out <csv>
#include <cstdio>
#include <cstdint>
#include <string>
#include <vector>
#include <set>
#include <ctime>
#include <cmath>
#include "kk/common/bars_csv.hpp"
#include "kk/common/types.hpp"
#include "kk/kenkem/kenkem_config.hpp"
#include "kk/kenkem/tf_cache.hpp"
#include "kk/kenkem/triggers.hpp"
#include "kk/kenkem/snapshot.hpp"
#include "kk/kenkem/gates.hpp"
#include "kk/kenkem/scoring.hpp"
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
    char buf[32]; std::snprintf(buf, sizeof(buf), "%04d.%02d.%02d %02d:%02d",
        tmv.tm_year+1900, tmv.tm_mon+1, tmv.tm_mday, tmv.tm_hour, tmv.tm_min);
    return buf;
}

// Reproduce entry_gate_ok(kind,dir) but return the FIRST failing gate label (or "PASS").
static const char* gate_reason(int kind, bool is_long, const TfBundle& b, const Snapshot& s,
                               const TfBundle::Align& align, const KenKemConfig& c) {
    const double tol = c.ema_align_tol_pips * c.pip_size;
    if (sideways_blocked(s, c)) return "sideways";
    if (c.min_entry_atr_pctile > 0.0 && s.atr_pctile < c.min_entry_atr_pctile) return "atr_lo";
    if (c.enable_atr_high_block && c.atr_percentile_high > 0.0 && s.atr_pctile > c.atr_percentile_high) return "atr_hi";
    if (trend_core_score(s, is_long, c) == 0) return "trendcore";
    // quality_filters_ok breakdown
    {
        int min_tq    = (kind==2)?c.min_tq_e2:(kind==4)?c.min_tq_e4:c.min_tq_e1;
        bool use_conv = (kind==2)?c.use_conviction_e2:(kind==4)?c.use_conviction_e4:c.use_conviction_e1;
        int conv_thr  = (kind==2)?c.conviction_thr_e2:(kind==4)?c.conviction_thr_e4:c.conviction_thr_e1;
        if (trend_quality_score(b, align, s, is_long, kind, c) < min_tq) return "tq";
        if (use_conv && conviction_score(b, align, s, is_long, c) < conv_thr) return "conv";
        if (rsi_divergence_veto(b, align, is_long, c)) return "rsidiv";
    }
    if (kind == 1) {
        if (s.adx[0] < c.e1_min_momentum_adx) return "e1_adxfloor";
        if (!htf_block_counter_ok(s, is_long, c.e1_htf_filter, c.e1_htf_min_adx, c.e1_htf_min_di_spread)) return "e1_htf";
        bool m1r = emas_ready_entry(b.m1, align.m1, is_long, true, tol);
        bool m3r = emas_ready_entry(b.m3, align.m3, is_long, true, tol);
        bool m5d = m5_directional_ok(b.m5, align.m5, is_long);
        double m1di = is_long ? (s.diP[0]-s.diM[0]) : (s.diM[0]-s.diP[0]);
        bool ext = m1di >= c.extreme_di_spread;
        bool pass = (c.e1_momentum_bypass==0) ? (m1r&&m3r&&m5d)
                  : (c.e1_momentum_bypass==1) ? (m1r&&((m3r&&m5d)||ext)) : (m1r||ext);
        if (!pass) return "e1_mtf";
        if (is_long ? (s.closeM1<=s.emaM1[1]) : (s.closeM1>=s.emaM1[1])) return "e1_price";
        if (!has_sufficient_momentum(s, is_long, c)) return "e1_mom";
        return "PASS";
    }
    if (kind == 2) {
        if (!htf_filter_ok(s, is_long, c.e2_htf_filter, c.e2_htf_min_adx, c.e2_htf_min_di_spread)) return "e2_htf";
        if (!emas_ready_entry(b.m1, align.m1, is_long, true, tol)) return "e2_m1";
        if (!emas_ready_entry(b.m3, align.m3, is_long, true, tol)) return "e2_m3";
        if (!emas_ready_entry(b.m5, align.m5, is_long, true, tol)) return "e2_m5";
        if (is_long ? (s.closeM1<=s.emaM1[1]) : (s.closeM1>=s.emaM1[1])) return "e2_price";
        return "PASS";
    }
    if (kind == 4) return entry_gate_ok(4, is_long, b, s, align, c) ? "PASS" : "e4_block";
    return "?";
}

int main(int argc, char** argv) {
    std::string m1_path, set_path, out_path, only_csv;
    bool xau=false; double spread=-1.0; int warmup=250; int64_t from_ms=0, to_ms=0;
    for (int i=1;i<argc;++i){ std::string a=argv[i]; auto nx=[&]{return (i+1<argc)?std::string(argv[++i]):std::string();};
        if(a=="--bars-m1")m1_path=nx(); else if(a=="--set")set_path=nx(); else if(a=="--out")out_path=nx();
        else if(a=="--symbol-xau")xau=true; else if(a=="--symbol-btc")xau=false; else if(a=="--spread")spread=std::stod(nx());
        else if(a=="--warmup")warmup=std::stoi(nx()); else if(a=="--from-ms")from_ms=std::stoll(nx());
        else if(a=="--to-ms")to_ms=std::stoll(nx()); else if(a=="--only")only_csv=nx(); }
    if(m1_path.empty()||out_path.empty()){ std::fprintf(stderr,"need --bars-m1 AND --out\n"); return 2; }
    std::set<int64_t> only;
    if(!only_csv.empty()){ size_t p=0; while(p<only_csv.size()){ size_t q=only_csv.find(',',p);
        std::string t=only_csv.substr(p,q==std::string::npos?q:q-p); if(!t.empty()) only.insert(std::stoll(t));
        if(q==std::string::npos)break; p=q+1; } }

    KenKemConfig cfg; if(xau)cfg.apply_xauusd_specs(); else cfg.apply_btcusd_specs();
    if(spread<0) spread = xau?0.05:2.0;
    if(!set_path.empty()){ int n=load_set(cfg,set_path); std::fprintf(stderr,"[set] %d keys from %s\n",n,set_path.c_str()); }

    std::vector<kk::Bar> m1 = kk::load_bars_csv(m1_path, 0, to_ms);
    if(m1.empty()){ std::fprintf(stderr,"no M1 bars\n"); return 1; }
    for(kk::Bar& b:m1) b.spread_mean=spread;
    std::vector<kk::Bar> m3=aggregate(m1,3), m5=aggregate(m1,5), m15=aggregate(m1,15);
    TfBundle B = build_tf_bundle(m1,m3,m5,m15,cfg);

    FILE* f=std::fopen(out_path.c_str(),"w"); if(!f){std::fprintf(stderr,"cannot open out\n");return 1;}
    std::fprintf(f,"ts_ms,dt,session,sideways,atr_pctile,atr_form,atr_closed,adx_m1,adx_m3,adx_m5,adx_m15,"
        "e1up,e1dn,e2up,e2dn,e4up,e4dn,"
        "tqL_e1,tqS_e1,tqL_e4,tqS_e4,convL,convS,"
        "E1L_age,E1L,E1S_age,E1S,E2L_age,E2L,E2S_age,E2S,E4L_age,E4L,E4S_age,E4S\n");

    TriggerState tg; const int N=B.m1.size(); int64_t rows=0;
    for(int bi=1; bi<N; ++bi){
        const kk::Bar& bar=B.m1.bars[bi];
        if(to_ms && bar.ts_ms>=to_ms) break;
        const TfBundle::Align al=B.align_at(bar.ts_ms);
        update_triggers(B,cfg,bi,al,tg);
        if(from_ms && bar.ts_ms<from_ms) continue;
        if(bi<warmup) continue;
        if(!only.empty() && !only.count(bar.ts_ms)) continue;
        Snapshot s=build_snapshot(B,cfg,bi,al); if(!s.valid) continue;
        bool session=in_valid_session(bar.ts_ms,cfg);
        // DIAG: tq component breakdown for both directions (only-mode).
        if(!only.empty()){
            const int j3=al.m3-1;
            for(int dl=0;dl<2;++dl){ bool L=(dl==0);
                int adxPts=(s.adx[0]>=cfg.adx_high_threshold)?2:(s.adx[0]>=cfg.min_momentum_adx)?1:0;
                double sp=L?(s.diP[0]-s.diM[0]):(s.diM[0]-s.diP[0]);
                int spPts=(sp>=3)?2:(sp>=1)?1:0;
                int acc=kk_trend_accel(B.m1,al.m1-1,L,5)?2:kk_trend_accel(B.m1,al.m1-1,L,3)?1:0;
                auto ag=[&](int tf){return L?(s.diP[tf]>s.diM[tf]):(s.diM[tf]>s.diP[tf]);};
                int al3=(ag(0)?1:0)+(ag(1)?1:0)+(ag(2)?1:0); int mtf=(al3==3)?2:(al3>=2)?1:0;
                int dcnt=kk_dir_bar_count(B.m1,al.m1-1,5,L); bool eng=kk_has_engulf(B.m1,al.m1-1,5,L);
                int pa=(dcnt>=4||eng)?1:0;
                int m3a=(j3>=0&&kk_trend_accel(B.m3,j3,L,3))?1:0;
                int atrp=(s.atr_pctile>=cfg.atr_percentile_low)?1:0;
                std::fprintf(stderr,"  %s %s adx=%d di=%d accel=%d mtf=%d(%d/3) pa=%d(cnt%d/eng%d) m3acc=%d atr=%d  SUM=%d\n",
                    utc(bar.ts_ms).c_str(), L?"L":"S", adxPts,spPts,acc,mtf,al3,pa,dcnt,eng,m3a,atrp,
                    adxPts+spPts+acc+mtf+pa+m3a+atrp);
            }
        }
        auto age=[&](int fired){ return fired>=0?(bi-fired):-1; };
        const int i1d = al.m1 - 1;
        double atr_closed = (i1d >= 0) ? TfIndicators::get(B.m1.atr, i1d) : 0.0;
        std::fprintf(f,"%lld,%s,%d,%d,%.1f,%.5f,%.5f,%.2f,%.2f,%.2f,%.2f,"
            "%d,%d,%d,%d,%d,%d,"
            "%d,%d,%d,%d,%d,%d,"
            "%d,%s,%d,%s,%d,%s,%d,%s,%d,%s,%d,%s\n",
            (long long)bar.ts_ms, utc(bar.ts_ms).c_str(), session?1:0, s.sideways, s.atr_pctile,
            s.atrM1, atr_closed,
            s.adx[0],s.adx[1],s.adx[2],s.adx[3],
            age(tg.ema_up),age(tg.ema_down),age(tg.e75_up),age(tg.e75_down),age(tg.ichi_up),age(tg.ichi_down),
            trend_quality_score(B,al,s,true,1,cfg), trend_quality_score(B,al,s,false,1,cfg),
            trend_quality_score(B,al,s,true,4,cfg), trend_quality_score(B,al,s,false,4,cfg),
            conviction_score(B,al,s,true,cfg), conviction_score(B,al,s,false,cfg),
            age(tg.ema_up), gate_reason(1,true,B,s,al,cfg),  age(tg.ema_down), gate_reason(1,false,B,s,al,cfg),
            age(tg.e75_up), gate_reason(2,true,B,s,al,cfg),  age(tg.e75_down), gate_reason(2,false,B,s,al,cfg),
            age(tg.ichi_up),gate_reason(4,true,B,s,al,cfg),  age(tg.ichi_down),gate_reason(4,false,B,s,al,cfg));
        ++rows;
    }
    std::fclose(f);
    std::fprintf(stderr,"[entry-trace] %lld rows -> %s\n",(long long)rows,out_path.c_str());
    return 0;
}
