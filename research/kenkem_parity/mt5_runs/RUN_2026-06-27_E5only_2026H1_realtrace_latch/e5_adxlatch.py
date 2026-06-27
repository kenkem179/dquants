import pandas as pd, numpy as np
RUN="research/kenkem_parity/mt5_runs/RUN_2026-06-27_E5only_2026H1_realtrace_latch"
rt = pd.read_csv(f"{RUN}/realtrace_XAUUSD-Exness-KK.csv")
ev = pd.read_csv(f"{RUN}/engine_e5v.csv", header=None,
    names=["tag","ts","e25c","e75c","e100c","e200c","alB2","alB3","dn1","dn2","e5up","e5dn","e25_b1","e25_b3","alB1","alB3b"])
ed = pd.read_csv("/tmp/e5d.csv", header=None,
    names=["tag","ts","diP0","diM0","diPF0","diMF0","adx0","adxF0","adx2","diP2","diM2","adxF2","diPF2","diMF2","adx3","diP3","diM3","adxF3","diPF3","diMF3"])
g = ev[["ts","alB1"]].merge(ed[["ts","adx0","adxF0"]], on="ts", how="inner").sort_values("ts").reset_index(drop=True)
ADXMIN=18.0
for adxcol in ["adxF0","adx0"]:
    prev=0; onset=np.zeros(len(g),dtype=int)
    al=g.alB1.values; passg=(g[adxcol].values>=ADXMIN)
    for i in range(len(g)):
        if passg[i]:
            onset[i]= 1 if (al[i]==1 and prev==0) else 0
            prev=al[i]            # latch updates ONLY on ADX-passing bars
        # else: frozen, no onset
    g[f"onset_{adxcol}"]=onset
# compare to EA bull onsets
ea_onset_ts = set(rt[(rt.aligned_bull==1)&(rt.prev_aligned_bull==0)].ts_ms)
print(f"# EA bull-onset bars: {len(ea_onset_ts)}")
for adxcol in ["adxF0","adx0"]:
    eng_ts = set(g[g[f'onset_{adxcol}']==1].ts)
    inter=len(ea_onset_ts & eng_ts)
    print(f"## ADX-gated latch ({adxcol}>= {ADXMIN}): engine onsets={len(eng_ts)}  "
          f"match EA={inter}/{len(ea_onset_ts)} ({100*inter/len(ea_onset_ts):.1f}%)  "
          f"engine-extra={len(eng_ts-ea_onset_ts)}")
# baseline: ungated stateful B-1 latch (every bar)
prev=0; ons=np.zeros(len(g),dtype=int); al=g.alB1.values
for i in range(len(g)):
    ons[i]=1 if(al[i]==1 and prev==0) else 0; prev=al[i]
eng_ts=set(g[ons==1].ts); inter=len(ea_onset_ts&eng_ts)
print(f"## UNGATED B-1 latch (every bar): onsets={len(eng_ts)} match EA={inter}/{len(ea_onset_ts)} ({100*inter/len(ea_onset_ts):.1f}%)")
