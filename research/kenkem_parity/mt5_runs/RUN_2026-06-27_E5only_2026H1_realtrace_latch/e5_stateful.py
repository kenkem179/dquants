import pandas as pd, numpy as np
RUN="research/kenkem_parity/mt5_runs/RUN_2026-06-27_E5only_2026H1_realtrace_latch"
rt = pd.read_csv(f"{RUN}/realtrace_XAUUSD-Exness-KK.csv")
ev = pd.read_csv(f"{RUN}/engine_e5v.csv", header=None,
    names=["tag","ts","e25c","e75c","e100c","e200c","alB2","alB3","dn1","dn2","e5up","e5dn","e25_b1","e25_b3","alB1","alB3b"])
ev = ev.sort_values("ts").reset_index(drop=True)
# STATEFUL B-1 latch model: prev = B-1 alignment on the PREVIOUS processed bar (shift by one E5V row)
ev["alB1_prev"] = ev["alB1"].shift(1).fillna(0).astype(int)
ev["stateful_onset_bull"] = ((ev.alB1==1) & (ev.alB1_prev==0)).astype(int)
m = rt.merge(ev[["ts","alB1","alB1_prev","alB2","stateful_onset_bull"]], left_on="ts_ms", right_on="ts", how="inner")

# 1) Does EA prev_aligned_bull == engine's STATEFUL prev (alB1 on previous bar)?
onset = m[(m.aligned_bull==1) & (m.prev_aligned_bull==0)]
allrows = m
print(f"## model check on ALL joined armed/fired rows (n={len(allrows)}):")
print(f"   EA prev_aligned_bull == engine alB1_prev (STATEFUL B-1 latch): "
      f"{int((allrows.prev_aligned_bull==allrows.alB1_prev).sum())}/{len(allrows)} "
      f"({100*(allrows.prev_aligned_bull==allrows.alB1_prev).mean():.1f}%)")
print(f"   (vs positional B-2: EA prev==alB2: {100*(allrows.prev_aligned_bull==allrows.alB2).mean():.1f}%)")

# 2) Does the stateful model reproduce the EA's onset flag on these bars?
print(f"\n## EA bull-onset bars (n={len(onset)}):")
print(f"   engine STATEFUL onset (B-1 now & B-1 prev=0) also fires: "
      f"{int((onset.stateful_onset_bull==1).sum())}/{len(onset)} "
      f"({100*(onset.stateful_onset_bull==1).mean():.1f}%)")
# 3) full agreement of the onset FLAG across all rows
ag = (allrows.aligned_bull.eq(1) & allrows.prev_aligned_bull.eq(0)).astype(int)
print(f"\n## onset-flag agreement (EA vs engine STATEFUL) across all {len(allrows)} rows: "
      f"{100*(ag==allrows.stateful_onset_bull).mean():.2f}%  "
      f"(disagreements: {int((ag!=allrows.stateful_onset_bull).sum())})")
