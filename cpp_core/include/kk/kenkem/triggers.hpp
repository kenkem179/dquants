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

    // ---- E1: EMA-stack cross (M1/M3 strict, M5 non-strict); just-crossed = !ready@s2 && ready@s1 ----
    auto just_up = [&](const TfIndicators& s, int s1, int s2, bool strict) {
        return !emas_ready(s, s2, true, strict, tol) && emas_ready(s, s1, true, strict, tol);
    };
    auto just_dn = [&](const TfIndicators& s, int s1, int s2, bool strict) {
        return !emas_ready(s, s2, false, strict, tol) && emas_ready(s, s1, false, strict, tol);
    };
    bool m1Up = just_up(bundle.m1, m1s1, m1s2, true);
    bool m3Up = just_up(bundle.m3, m3s1, m3s2, true);
    bool m5Up = just_up(bundle.m5, m5s1, m5s2, false);
    if (st.ema_up == -1 && (m1Up || m3Up || m5Up) &&
        emas_ready(bundle.m1, m1s1, true, true, tol) && emas_ready(bundle.m3, m3s1, true, true, tol)) {
        st.ema_up = B; st.ema_down = -1; ++st.arm_e1_cross;
    }
    bool m1Dn = just_dn(bundle.m1, m1s1, m1s2, true);
    bool m3Dn = just_dn(bundle.m3, m3s1, m3s2, true);
    bool m5Dn = just_dn(bundle.m5, m5s1, m5s2, false);
    if (st.ema_down == -1 && (m1Dn || m3Dn || m5Dn) &&
        emas_ready(bundle.m1, m1s1, false, true, tol) && emas_ready(bundle.m3, m3s1, false, true, tol)) {
        st.ema_down = B; st.ema_up = -1; ++st.arm_e1_cross;
    }

    // ---- E1 alt: EMA200 touch with full M1+M3 alignment (EMAHelpers.mqh:259-283) ----
    if (m1s1 >= 0) {
        const double ema200 = bundle.m1.ema[4][m1s1];
        const double lo = bundle.m1.bars[m1s1].low, hi = bundle.m1.bars[m1s1].high;
        if (lo <= ema200 && hi >= ema200) {
            if (st.ema_up == -1 && emas_ready(bundle.m1, m1s1, true, true, tol) &&
                emas_ready(bundle.m3, m3s1, true, true, tol)) {
                st.ema_up = B; st.ema_down = -1; ++st.arm_e1_touch;
            } else if (st.ema_down == -1 && emas_ready(bundle.m1, m1s1, false, true, tol) &&
                       emas_ready(bundle.m3, m3s1, false, true, tol)) {
                st.ema_down = B; st.ema_up = -1; ++st.arm_e1_touch;
            }
        }
    }

    // ---- E2: EMA75 touch; direction by close vs EMA75; stores B (= Bars-1) ----
    if (m1s1 >= 0) {
        const double ema75 = bundle.m1.ema[2][m1s1];
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

    // ---- E5: SuperBros — fresh STRICT M1 4-EMA alignment onset (no tolerance). Onset = aligned@s1 &
    // not aligned@s2. Reset when alignment breaks (consumed-lock: won't re-arm while continuously
    // aligned, since entry consumes e5_*; re-arms only on a fresh onset after a break). ----
    if (cfg.enable_e5) {
        bool up1 = emas_ready(bundle.m1, m1s1, true,  true, 0.0);
        bool up2 = emas_ready(bundle.m1, m1s2, true,  true, 0.0);
        bool dn1 = emas_ready(bundle.m1, m1s1, false, true, 0.0);
        bool dn2 = emas_ready(bundle.m1, m1s2, false, true, 0.0);
        if (!up1) st.e5_up = -1;
        else if (!up2 && st.e5_up == -1) { st.e5_up = B; st.e5_down = -1; }
        if (!dn1) st.e5_down = -1;
        else if (!dn2 && st.e5_down == -1) { st.e5_down = B; st.e5_up = -1; }
    }
}

}  // namespace kk::kenkem
