import pandas as pd, numpy as np
RUN="research/kenkem_parity/mt5_runs/RUN_2026-06-27_E5only_2026H1_realtrace_latch"
rt = pd.read_csv(f"{RUN}/realtrace_XAUUSD-Exness-KK.csv")
# engine E5V: ts, e25c,e75c,e100c,e200c, up1(al@B2),up2(al@B3),dn1,dn2,e5up,e5dn,e25_b1,e25_b3,al_b1,al_b3
ev = pd.read_csv(f"{RUN}/engine_e5v.csv", header=None,
    names=["tag","ts","e25c","e75c","e100c","e200c","alB2","alB3","dn1","dn2","e5up","e5dn","e25_b1","e25_b3","alB1","alB3b"])
print(f"# EA realtrace rows={len(rt)}  engine E5V rows={len(ev)}")
print(f"# ts overlap: EA ts range {rt.ts_ms.min()}..{rt.ts_ms.max()}  ENG {ev.ts.min()}..{ev.ts.max()}")
# join EA armed/fired bull-onset bars to engine alignment at same ts
m = rt.merge(ev[["ts","alB1","alB2","alB3","e25_b1","e25c"]], left_on="ts_ms", right_on="ts", how="inner")
print(f"# joined rows = {len(m)} of {len(rt)} EA rows")

# EA bull ONSET bars: aligned_bull=1 AND prev_aligned_bull=0
onset = m[(m.aligned_bull==1) & (m.prev_aligned_bull==0)]
print(f"\n## EA bull-onset bars (aligned_bull=1 & prev_aligned_bull=0): n={len(onset)}")
print("   engine alignment at those bars — which pairing does the EA onset correspond to?")
print(f"   engine alB1 (B-1): mean={onset.alB1.mean():.3f}  ==1: {int((onset.alB1==1).sum())}/{len(onset)}")
print(f"   engine alB2 (B-2): mean={onset.alB2.mean():.3f}  ==0: {int((onset.alB2==0).sum())}/{len(onset)}")
print(f"   engine alB3 (B-3): mean={onset.alB3.mean():.3f}")
print(f"   -> EA onset==engine(alB1=1 & alB2=0) [B1/B2 pairing]: {int(((onset.alB1==1)&(onset.alB2==0)).sum())}/{len(onset)}")
print(f"   -> EA onset==engine(alB2=1 & alB3=0) [B2/B3 faithful]: {int(((onset.alB2==1)&(onset.alB3==0)).sum())}/{len(onset)}")

# verify EA's logged ema25 matches engine B-1 vs B-2 (the prior 42/42 claim)
d_b1 = (onset.ema25 - onset.e25_b1).abs()
d_b2 = (onset.ema25 - onset.e25c).abs()
print(f"\n## EA logged ema25 vs engine: |Δ| to B-1 mean={d_b1.mean():.4f}  to B-2(cur) mean={d_b2.mean():.4f}")
print(f"   EA ema25 matches B-1 (|Δ|<0.01): {int((d_b1<0.01).sum())}/{len(onset)};  matches B-2: {int((d_b2<0.01).sum())}/{len(onset)}")

# EA prev_aligned (its 'prev') vs engine alB2 (al@B-2): if EA prev==engine B2, EA's prev-bar IS engine B2 -> EA cur=B1
print(f"\n## consistency: EA prev_aligned_bull vs engine alB2: agree {int((onset.prev_aligned_bull==onset.alB2).sum())}/{len(onset)}")
print(f"##              EA aligned_bull     vs engine alB1: agree {int((onset.aligned_bull==onset.alB1).sum())}/{len(onset)}")
