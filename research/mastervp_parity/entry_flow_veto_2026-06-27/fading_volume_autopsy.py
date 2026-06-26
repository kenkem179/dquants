# H12b — fading-volume (magnitude) entry veto autopsy. Pure-Python join of the lock's trades
# (entryTimeUTC == signal-bar open) to the M5 bars (tick_count), model-free outcomes (mfeR/reach1R).
# Tests: do LOW/dying-volume breakouts underperform? Verdict: NO (equal-or-better). No engine change.
# Usage: python3 fading_volume_autopsy.py <trades.csv> <bars_m5.csv>
import csv, sys, statistics as st
from datetime import datetime, timezone
trades_csv = sys.argv[1] if len(sys.argv)>1 else '/tmp/tr_lock_v2.csv'
bars_csv   = sys.argv[2] if len(sys.argv)>2 else 'cpp_core/tools/bars_xauusd_2025_2026_m5.csv'
B=list(csv.DictReader(open(bars_csv)))
ts=[int(b['ts_ms']) for b in B]; idx={t:i for i,t in enumerate(ts)}
h=[float(b['high']) for b in B]; l=[float(b['low']) for b in B]; c=[float(b['close']) for b in B]
vol=[float(b['tick_count']) for b in B]; nB=len(B); AL=14; LOOK=50
tr=[0.0]*nB
for i in range(nB): tr[i]=h[i]-l[i] if i==0 else max(h[i]-l[i],abs(h[i]-c[i-1]),abs(l[i]-c[i-1]))
atr=[0.0]*nB
if nB>=AL:
    atr[AL-1]=sum(tr[:AL])/AL
    for i in range(AL,nB): atr[i]=(atr[i-1]*(AL-1)+tr[i])/AL
def volrel(i):
    s=max(0,i-LOOK+1); w=vol[s:i+1]; m=sum(w)/len(w); return vol[i]/m if m>0 else 1.0
def volslope(i):
    s=max(0,i-LOOK+1); w=vol[s:i+1]; m=sum(w)/len(w); r=vol[max(0,i-2):i+1]; return (sum(r)/len(r))/m if m>0 else 1.0
def nearfrac(i):
    a=atr[i]
    if a<=0: return None
    win=2.4*a; s=max(0,i-LOOK+1); near=tot=0.0
    for j in range(s,i+1):
        p=(h[j]+l[j]+c[j])/3.0; tot+=vol[j]
        if abs(p-c[i])<=win: near+=vol[j]
    return near/tot if tot>0 else 0.0
def ems(s): return int(datetime.strptime(s,'%Y.%m.%d %H:%M').replace(tzinfo=timezone.utc).timestamp()*1000)
T=[]
for r in csv.DictReader(open(trades_csv)):
    i=idx.get(ems(r['entryTimeUTC']))
    if i is None: continue
    r['mfeR']=float(r['mfeR']); r['usd']=float(r['realizedUsd'])
    r['volRel']=volrel(i); r['volSlope']=volslope(i); r['nearFrac']=nearfrac(i); T.append(r)
def stats(sub,lbl):
    mfe=st.mean(x['mfeR'] for x in sub); reach=100*sum(1 for x in sub if x['mfeR']>=1)/len(sub)
    print(f"  {lbl:22s}: n={len(sub):4d}  mfeR={mfe:.3f}  reach1R={reach:4.1f}%  usd/tr={sum(x['usd'] for x in sub)/len(sub):6.1f}")
for key,lbl in [('volRel','breakout-bar rel volume'),('volSlope','participation slope'),('nearFrac','near-price partic frac')]:
    v=sorted(x[key] for x in T if x[key] is not None); n=len(v); q=[v[0],v[n//4],v[n//2],v[3*n//4],v[-1]+1]
    print(f"\n=== {lbl} (low=dying -> high) ===")
    for a,b,nm in [(q[0],q[1],'Q1 LOWEST(dying)'),(q[1],q[2],'Q2'),(q[2],q[3],'Q3'),(q[3],q[4],'Q4 HIGHEST')]:
        stats([x for x in T if x[key] is not None and a<=x[key]<b],nm)
