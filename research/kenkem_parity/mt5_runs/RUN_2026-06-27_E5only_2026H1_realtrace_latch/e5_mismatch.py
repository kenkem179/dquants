import pandas as pd, numpy as np
RUN="research/kenkem_parity/mt5_runs/RUN_2026-06-27_E5only_2026H1_realtrace_latch"
rt = pd.read_csv(f"{RUN}/realtrace_XAUUSD-Exness-KK.csv").sort_values("ts_ms").reset_index(drop=True)
ev = pd.read_csv(f"{RUN}/engine_e5v.csv", header=None,
    names=["tag","ts","e25c","e75c","e100c","e200c","alB2","alB3","dn1","dn2","e5up","e5dn","e25_b1","e25_b3","alB1","alB3b"]).sort_values("ts").reset_index(drop=True)
ev["alB1_prev"]=ev.alB1.shift(1).fillna(0).astype(int)
m = rt.merge(ev[["ts","alB1","alB1_prev","alB2"]], left_on="ts_ms", right_on="ts", how="inner")
onset = m[(m.aligned_bull==1)&(m.prev_aligned_bull==0)].copy()
# mismatch = EA onset but engine prior-bar B-1 aligned (so engine stateful latch wouldn't fire)
mis = onset[onset.alB1_prev==1]
ok  = onset[onset.alB1_prev==0]
print(f"# EA bull onsets={len(onset)}  engine-reproduced={len(ok)}  MISMATCH={len(mis)}")
print("\n## MISMATCH bars — distribution of EA context fields:")
for col in ["gate","final_decision"]:
    print(f"  [{col}]:", mis[col].value_counts().to_dict())
print(f"  up_age: {mis.up_age.value_counts().to_dict()}")
print(f"  detected==1: {int((mis.detected==1).sum())}/{len(mis)};  sideway_block==1: {int((mis.sideway_block==1).sum())}")
# time gap to the PREVIOUS realtrace (interesting) row — were there skipped interesting bars?
rt_ts = rt.ts_ms.values
def prev_gap(ts):
    i = np.searchsorted(rt_ts, ts)
    return (ts - rt_ts[i-1])/60000 if i>0 else -1
mis["gap_min"]=mis.ts_ms.apply(prev_gap); ok2=ok.copy(); ok2["gap_min"]=ok.ts_ms.apply(prev_gap)
print(f"\n## minutes since prior realtrace row: MISMATCH median={mis.gap_min.median():.0f} mean={mis.gap_min.mean():.0f}  | OK median={ok2.gap_min.median():.0f}")
print(f"   MISMATCH gap distribution: 1min={int((mis.gap_min==1).sum())}  2-5={int(((mis.gap_min>1)&(mis.gap_min<=5)).sum())}  >5={int((mis.gap_min>5).sum())}")
print(f"   OK       gap distribution: 1min={int((ok2.gap_min==1).sum())}  2-5={int(((ok2.gap_min>1)&(ok2.gap_min<=5)).sum())}  >5={int((ok2.gap_min>5).sum())}")
