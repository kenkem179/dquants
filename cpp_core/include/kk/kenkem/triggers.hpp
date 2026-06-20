// KenKem P3 — entry trigger state machines (faithful port of EMAHelpers.mqh UpdateEmaTouches +
// the E4 Ichimoku cloud-cross block in UpdateIndicatorCache).
//
// Updated ONCE per new M1 bar B (the forming bar; ENTRY_SHIFT=1 => reads close at B-1). Each trigger
// records the bar index B at which it fired; entries consume it and expire it by age (E1=80, E2=36,
// E4=20). Setting one direction always clears the opposite (mirrors the EA).
//
// ICHIMOKU BUFFER MAPPING (parity-critical — the EA mislabels buffers, replicate exactly):
//   EA cache.ichimokuSpanA/B_*_Current = iIchimoku CopyBuffer 0/1 = REAL Tenkan / Kijun lines.
//     => the "cloud cross" trigger is actually a Tenkan-vs-Kijun (TK) cross, per TF, on M1 AND M3.
//   EA cache.ichimokuTenkan/Kijun_M3   = CopyBuffer 2/3 = REAL Senkou A / B ("current" cloud) — used
//     by the E4 quality gate (P4), NOT here.
// So here: cloud-bullish(TF) := tenkan[shift] > kijun[shift].  (my IchimokuBuf.tenkan/.kijun)
#pragma once
#include "kk/kenkem/tf_cache.hpp"
#include "kk/kenkem/kenkem_config.hpp"
#include <cstdint>
#include <cstdlib>
#include <cstdio>

namespace kk::kenkem {

// EMA-stack alignment with tolerance — isEMAsReadyForEntry (KenKemExpert.mq5:1912).
// Uses EMA1>EMA2>EMA3(>EMA4 if strict) for long; reversed for short. idx = absolute bar index.
// tol = EMA_ALIGNMENT_TOLERANCE_PIPS * pipSize. EMA0 (fast/10) is NOT part of the stack.
inline bool emas_ready(const TfIndicators& s, int idx, bool is_long, bool strict, double tol) {
    if (idx < 0 || idx >= s.size()) return false;
    const double e1 = s.ema[1][idx], e2 = s.ema[2][idx], e3 = s.ema[3][idx], e4 = s.ema[4][idx];
    if (is_long) {
        bool a = e1 > e2 - tol;
        bool b = e2 > e3 - tol;
        bool c = !strict || (e3 > e4 - tol);
        return a && b && c;
    } else {
        bool a = e1 < e2 + tol;
        bool b = e2 < e3 + tol;
        bool c = !strict || (e3 < e4 + tol);
        return a && b && c;
    }
}

// Trigger state — bar indices where each trigger last fired (-1 = inactive). Persists across bars.
struct TriggerState {
    int ema_up = -1, ema_down = -1;     // lastEMACrossingUp/Down (E1)
    int e75_up = -1, e75_down = -1;     // lastEma75TouchUp/Down (E2)
    int ichi_up = -1, ichi_down = -1;   // lastIchiCloudCrossUp/Down (E4, TK cross)
    int e5_up = -1, e5_down = -1;       // E5 SuperBros fresh strict-alignment onset
    long arm_e1_cross = 0, arm_e1_touch = 0;  // DIAGNOSTIC: E1 arm-event source split
    int e1_cross_tf = 0;                // DIAGNOSTIC: bitmask of TF that tripped last cross arm (1=M1,2=M3,4=M5)
};

// Cloud (TK) bullish on a TF at absolute index idx: real Tenkan > real Kijun.
inline bool cloud_bullish(const TfIndicators& s, int idx) {
    if (!s.has_ichi || idx < 0 || idx >= s.size()) return false;
    return s.ichi.tenkan[idx] > s.ichi.kijun[idx];
}

// Update all triggers for forming M1 bar B. align = each TF's forming index at open_time(B).
// (shift 1 = forming-1 = last closed bar; shift 2 = forming-2.)
inline void update_triggers(const TfBundle& bundle, const KenKemConfig& cfg, int B,
                            const TfBundle::Align& align, TriggerState& st) {
    const double tol = cfg.ema_align_tol_pips * cfg.pip_size;
    const int m1s1 = B - 1,            m1s2 = B - 2;
    const int m3s1 = align.m3 - 1,     m3s2 = align.m3 - 2;
    const int m5s1 = align.m5 - 1,     m5s2 = align.m5 - 2;

    // EMA non-series TRAP (parity-critical): the EA reads EMA alignment via GetEMA(tf,ema,shift), which
    // hits MT5's non-series CopyBuffer trap and actually returns series-shift (shift+1) — i.e. one bar
    // STALER than the nominal closed-bar shift. The validated SIGNAL path already corrects this
    // (snapshot.hpp:124 reads emaM1 at i1-1 = align.m1-2). The TRIGGER path historically did NOT, reading
    // EMAs one bar too fresh → ~97% spurious E1 cross-arms. Apply the same -1 trap here. Price low/high
    // come from iLow/iHigh (series, NOT trapped) and stay at m1s1. KK_E1_EMA_TRAP=0 reverts (A/B).
    static const int kTrap = [] { const char* e = std::getenv("KK_E1_EMA_TRAP"); return e ? std::atoi(e) : 0; }();
    const int m1e1 = m1s1 - kTrap, m1e2 = m1s2 - kTrap;
    const int m3e1 = m3s1 - kTrap, m3e2 = m3s2 - kTrap;
    const int m5e1 = m5s1 - kTrap, m5e2 = m5s2 - kTrap;

    // EA BUFFER-INVERSION TRAP (the REAL trap — supersedes the uniform kTrap above for the E1 cross).
    // emaBuffers is a FIXED [.][30] array filled from a NON-series CopyBuffer tempBuffer, so element[0]
    // is the OLDEST bar. With ENTRY_SHIFT=1 (bufferSize=4) the EA's GetEMA(shift) maps INVERTED:
    //   GetEMA(shift=1) -> tempBuffer[1] = series bar 2 = B-2   (the "ready"/latch bar)
    //   GetEMA(shift=2) -> tempBuffer[2] = series bar 1 = B-1   (the "prev" bar)
    // So the EA's "just crossed up" = !ready@shift2 && ready@shift1 = !ready@(B-1) && ready@(B-2):
    // alignment PRESENT at the older bar (B-2) and ABSENT at the newer bar (B-1). The old engine read
    // the two bars in natural order (ready@B-1, prev@B-2) — a chronological cross — which is INVERTED
    // vs the EA and the documented cause of the ~3.5x E1 cross over-arm. The validated SIGNAL path
    // already reads single EMAs at B-2 (snapshot.hpp), consistent with shift1->B-2 here.
    // Controlled by cfg.e1_faithful_trigger (default true). The tick_backtester CLI lets KK_E1_FAITHFUL
    // override it for A/B runs; synthetic engine-mechanics tests set it false to keep their legacy scenario.
    const bool kFaithful = cfg.e1_faithful_trigger;
    // "ready"/latch bar = EA shift1 ; "prev" bar = EA shift2.
    const int m1_rdy = kFaithful ? m1s2 : m1e1, m1_prv = kFaithful ? m1s1 : m1e2;
    const int m3_rdy = kFaithful ? m3s2 : m3e1, m3_prv = kFaithful ? m3s1 : m3e2;
    const int m5_rdy = kFaithful ? m5s2 : m5e1, m5_prv = kFaithful ? m5s1 : m5e2;

    // ---- E1: EMA-stack cross (M1/M3 strict, M5 non-strict); just-crossed = !ready@prv && ready@rdy ----
    auto just_up = [&](const TfIndicators& s, int rdy, int prv, bool strict) {
        return !emas_ready(s, prv, true, strict, tol) && emas_ready(s, rdy, true, strict, tol);
    };
    auto just_dn = [&](const TfIndicators& s, int rdy, int prv, bool strict) {
        return !emas_ready(s, prv, false, strict, tol) && emas_ready(s, rdy, false, strict, tol);
    };
    bool m1Up = just_up(bundle.m1, m1_rdy, m1_prv, true);
    bool m3Up = just_up(bundle.m3, m3_rdy, m3_prv, true);
    bool m5Up = just_up(bundle.m5, m5_rdy, m5_prv, false);
    if (st.ema_up == -1 && (m1Up || m3Up || m5Up) &&
        emas_ready(bundle.m1, m1_rdy, true, true, tol) && emas_ready(bundle.m3, m3_rdy, true, true, tol)) {
        st.ema_up = B; st.ema_down = -1; ++st.arm_e1_cross;
        st.e1_cross_tf = (m1Up?1:0)|(m3Up?2:0)|(m5Up?4:0);
    }
    bool m1Dn = just_dn(bundle.m1, m1_rdy, m1_prv, true);
    bool m3Dn = just_dn(bundle.m3, m3_rdy, m3_prv, true);
    bool m5Dn = just_dn(bundle.m5, m5_rdy, m5_prv, false);
    if (st.ema_down == -1 && (m1Dn || m3Dn || m5Dn) &&
        emas_ready(bundle.m1, m1_rdy, false, true, tol) && emas_ready(bundle.m3, m3_rdy, false, true, tol)) {
        st.ema_down = B; st.ema_up = -1; ++st.arm_e1_cross;
        st.e1_cross_tf = (m1Dn?1:0)|(m3Dn?2:0)|(m5Dn?4:0);
    }

    // ---- E1 alt: EMA200 touch with full M1+M3 alignment (EMAHelpers.mqh:259-283) ----
    // EA: ema200 + M1/M3 alignment via GetEMA(...,ENTRY_SHIFT) (trapped => series-shift2 = m1s1-1), but
    // bar low/high via iLow/iHigh(ENTRY_SHIFT) (series shift1 = m1s1, untrapped). KK_TOUCH_SHIFT is an
    // additional experimental offset on top of the trap (default 0).
    static const int touch_sh = [] { const char* e = std::getenv("KK_TOUCH_SHIFT"); return e ? std::atoi(e) : 0; }();
    // Faithful: EA reads ema200 = GetEMA(TF0,EMA4,1) and alignment via isEMAsReadyForEntry(...,1) — both
    // at shift1 = B-2 (inverted buffer); bar low/high use iLow/iHigh(1) = series 1 = B-1 (untrapped).
    const int e1t = (kFaithful ? m1s2 : m1s1 - kTrap) - touch_sh;
    const int e3t = (kFaithful ? m3s2 : m3s1 - kTrap) - touch_sh;
    if (m1s1 >= 0 && e1t >= 0 && e3t >= 0) {
        const double ema200 = bundle.m1.ema[4][e1t];
        const double lo = bundle.m1.bars[m1s1].low, hi = bundle.m1.bars[m1s1].high;
        if (lo <= ema200 && hi >= ema200) {
            if (st.ema_up == -1 && emas_ready(bundle.m1, e1t, true, true, tol) &&
                emas_ready(bundle.m3, e3t, true, true, tol)) {
                st.ema_up = B; st.ema_down = -1; ++st.arm_e1_touch;
            } else if (st.ema_down == -1 && emas_ready(bundle.m1, e1t, false, true, tol) &&
                       emas_ready(bundle.m3, e3t, false, true, tol)) {
                st.ema_down = B; st.ema_up = -1; ++st.arm_e1_touch;
            }
        }
    }

    // ---- E2: EMA75 touch; direction by close vs EMA75; stores B (= Bars-1) ----
    // EA (EMAHelpers.mqh:285-288): ema75 = GetEMA(TF0,EMA2,ENTRY_SHIFT) — TRAPPED (inverted buffer) =>
    // series-shift2 = B-2; bar low/high/close = iLow/iHigh/iClose(ENTRY_SHIFT=1) — series shift1 = B-1
    // (untrapped). Same buffer-inversion trap as the E1 EMA200 touch above (which used e1t), previously
    // missed here. Mirror it: EMA75 at e2t (B-2 faithful), bar lo/hi/cl stay at m1s1 (B-1).
    const int e2t = (kFaithful ? m1s2 : m1s1 - kTrap) - touch_sh;
    if (m1s1 >= 0 && e2t >= 0) {
        const double ema75 = bundle.m1.ema[2][e2t];
        const double lo = bundle.m1.bars[m1s1].low, hi = bundle.m1.bars[m1s1].high, cl = bundle.m1.bars[m1s1].close;
        if (lo <= ema75 && hi >= ema75) {
            if (cl > ema75)      { st.e75_up = B; st.e75_down = -1; }
            else if (cl < ema75) { st.e75_down = B; st.e75_up = -1; }
        }
    }

    // ---- E4: Ichimoku TK cross — both M1 AND M3 flip together (curr vs prev = shift1 vs shift2) ----
    if (cfg.enable_e4) {
        bool m1c = cloud_bullish(bundle.m1, m1s1), m3c = cloud_bullish(bundle.m3, m3s1);
        bool m1p = cloud_bullish(bundle.m1, m1s2), m3p = cloud_bullish(bundle.m3, m3s2);
        bool bothBull_c =  m1c &&  m3c, bothBull_p =  m1p &&  m3p;
        bool bothBear_c = !m1c && !m3c, bothBear_p = !m1p && !m3p;
        bool up   = bothBull_c && !bothBull_p;
        bool down = bothBear_c && !bothBear_p;
        if (up   && st.ichi_up   == -1) { st.ichi_up = B;   st.ichi_down = -1; }
        if (down && st.ichi_down == -1) { st.ichi_down = B; st.ichi_up = -1; }
    }

    // ---- E5: SuperBros — fresh STRICT M1 4-EMA alignment onset (no tolerance). ----
    // PARITY-CRITICAL shift: Entry5.mqh reads alignment via the SAME trapped GetEMA(TF0,EMAx,ENTRY_SHIFT)
    // as E1/E2 (buffer-inversion: GetEMA shift1 -> series B-2). isBullishAligned uses ONLY shift1, so the
    // "current" aligned bar is B-2 (= m1s2). m_prevBullishAligned is the PRIOR M1 bar's isBullishAligned,
    // i.e. aligned at that bar's shift1 = B-3 (= m1s2-1). Onset = aligned@cur && !aligned@prv; reset when
    // alignment breaks at cur. The old engine read cur=B-1/prv=B-2 (one bar too FRESH) -> detected the
    // onset a bar early -> the e5up/dn_age and signal-fire timing diverged from MT5 (median -1 bar). The
    // legacy (non-faithful) path keeps the chronological B-1/B-2 read for the engine-mechanics tests.
    if (cfg.enable_e5) {
        // NOTE (KK_E5_VALDUMP shift-test, 42/42): the EA realtrace alignment EMAs match the engine stack
        // at m1s1 (B-1), one bar fresher than this faithful m1s2 (B-2) onset read. But the global fresh
        // shift (cur=m1s1/prv=m1s2) REGRESSES net recall 52.8%->41.7% (arming/fire coupling) — so faithful
        // B-2 is net-best; the 42 onset misses need the EA's exact latch internals, not a shift.
        // See research/kenkem_parity/E5_REALTRACE_FINDINGS.md (RESOLVED section).
        const int e5_cur = kFaithful ? m1s2 : m1s1;
        const int e5_prv = kFaithful ? m1s2 - 1 : m1s2;
        if (e5_cur >= 0 && e5_prv >= 0) {
            bool up1 = emas_ready(bundle.m1, e5_cur, true,  true, 0.0);
            bool up2 = emas_ready(bundle.m1, e5_prv, true,  true, 0.0);
            bool dn1 = emas_ready(bundle.m1, e5_cur, false, true, 0.0);
            bool dn2 = emas_ready(bundle.m1, e5_prv, false, true, 0.0);
            if (!up1) st.e5_up = -1;
            else if (!up2 && st.e5_up == -1) { st.e5_up = B; st.e5_down = -1; }
            if (!dn1) st.e5_down = -1;
            else if (!dn2 && st.e5_down == -1) { st.e5_down = B; st.e5_up = -1; }
            // PARITY value-diff (KK_E5_VALDUMP): the engine's M1 4-EMA stack at the onset read-bar
            // (e5_cur=m1s2) + the strict-alignment verdicts, joined on ts_ms vs the EA realtrace's
            // ema25/75/100/200 + aligned_bull/bear. Diagnoses the 26 "unarmed" detection-misses.
            static const bool e5v = std::getenv("KK_E5_VALDUMP") != nullptr;
            if (e5v) {
                const TfIndicators& m1 = bundle.m1;
                // ema25 at B-1/B-2/B-3 (m1s1/m1s2/m1s2-1) to test the 1-bar-shift hypothesis vs
                // the EA's ema25 (logged at GetEMA shift1 = B-2). If the FRESHER bar's stack matches
                // the EA better, the engine onset read is one bar too stale.
                const double e25_b1 = (m1s1   >= 0) ? m1.ema[1][m1s1]   : 0.0;
                const double e25_b3 = (e5_prv >= 0) ? m1.ema[1][e5_prv] : 0.0;
                const int al_b1 = (m1s1   >= 0 && emas_ready(m1, m1s1,   true, true, 0.0)) ? 1 : 0;
                const int al_b3 = (e5_prv >= 0 && emas_ready(m1, e5_prv, true, true, 0.0)) ? 1 : 0;
                std::fprintf(stderr, "E5V,%lld,%.5f,%.5f,%.5f,%.5f,%d,%d,%d,%d,%d,%d,%.5f,%.5f,%d,%d\n",
                    (long long)bundle.m1.bars[B].ts_ms,
                    m1.ema[1][e5_cur], m1.ema[2][e5_cur], m1.ema[3][e5_cur], m1.ema[4][e5_cur],
                    up1?1:0, up2?1:0, dn1?1:0, dn2?1:0, st.e5_up, st.e5_down,
                    e25_b1, e25_b3, al_b1, al_b3);
            }
        }
    }
}

}  // namespace kk::kenkem
