import pandas as pd, numpy as np
f="/Users/tokyotechies/Workspace/KEM/dquants/research/kenkem_parity/lock_trades_maeR_full.csv"
df=pd.read_csv(f)
df['k']=df['kind'].str[1:].astype(int)
df['sgn']=np.where(df['dir']=='L',1,-1)
df['realR']=df['sgn']*(df['exitPrice']-df['entry'])/df['riskPrice']
df['giveR']=df['mfeR']-df['realR']
df['win']=df['realizedUsd']>0
RR={1:1.9,2:1.575,4:2.4}; TRIG={1:0.90,2:0.70,4:0.70}
print("== PER-ENTRY excursion & capture (lock full window, %d trades) =="%len(df))
print(f"{'':4} {'n':>3} {'net$':>6} {'win%':>5} {'mfeR':>5} {'realR':>6} {'giveR':>6} {'capt%':>6} {'maeR':>5}")
for k in [1,2,4]:
    g=df[df.k==k]
    capt=100*g.realR.sum()/g.mfeR.sum()
    print(f"E{k:<3} {len(g):3d} {g.realizedUsd.sum():6.0f} {100*g.win.mean():5.1f} "
          f"{g.mfeR.mean():5.2f} {g.realR.mean():+6.2f} {g.giveR.mean():6.2f} {capt:6.1f} {g.maeR.mean():5.2f}")
print("\n== partial/bank reachability vs where trades actually peak ==")
for k in [1,2,4]:
    g=df[df.k==k]; trig=TRIG[k]*RR[k]
    print(f"E{k}: first bank at {trig:.2f}R | trades reaching it: {100*(g.mfeR>=trig).mean():.0f}% | "
          f"median peak mfeR={g.mfeR.median():.2f}R | reach 1R:{100*(g.mfeR>=1).mean():.0f}% reach 0.5R:{100*(g.mfeR>=0.5).mean():.0f}%")
print("\n== giveback concentration: peaked >=1R but exited <=0.3R (round-tripped a real profit) ==")
for k in [1,2,4]:
    g=df[df.k==k]; bled=g[(g.mfeR>=1.0)&(g.realR<=0.3)]
    extra = f", avg surrendered {bled.giveR.mean():.2f}R, ${-bled.realizedUsd.sum():.0f} left on table" if len(bled) else ""
    print(f"E{k}: {len(bled)}/{len(g)} ({100*len(bled)/len(g):.0f}%){extra}")
print("\n== SL tightness check (would a tighter stop kill winners?) ==")
for k in [1,2,4]:
    g=df[df.k==k]; L=g[~g.win]; W=g[g.win]
    print(f"E{k}: losers maeR mean={L.maeR.mean():.2f} median={L.maeR.median():.2f} (n={len(L)}) | "
          f"winners dipping >=0.5R adverse: {(W.maeR>=0.5).sum()}/{len(W)} ({100*(W.maeR>=0.5).mean():.0f}%) | "
          f">=0.75R: {(W.maeR>=0.75).sum()}")
