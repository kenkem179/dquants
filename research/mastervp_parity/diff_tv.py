#!/usr/bin/env python3
"""
diff_tv.py — distributional parity differ: C++ engine trades vs the TradingView trade log.

The TV strategy splits each position into a TP1 (20%) and a TP2 (80%) portion, each with its
own "Trade number" but a SHARED entry (datetime+price+side). We regroup TV rows back into
POSITIONS (sum the portion PnLs) so the comparison is position-for-position with the engine,
which emits one row per round-trip position.

Parity here is DISTRIBUTIONAL, not byte-exact: TV ran the OANDA feed, the engine runs our MT5
feed, and tick volume (which drives the VP engine) differs. We compare SHAPE: position count,
direction mix, win rate, profit factor, net return, trades/day, hour-of-day histogram, and the
exit-reason mix — over the OVERLAPPING date window only.

Usage:
  python3 diff_tv.py --engine <trades_cpp.csv> --tv <KK_..._.csv> [--tz-shift-hours N]
"""
import argparse, csv, datetime as dt
from collections import defaultdict, Counter

def parse_engine(path):
    """Engine CSV -> list of positions: dict(dt, side, entry, pnl, tag)."""
    out = []
    with open(path, newline="") as f:
        r = csv.DictReader(f)
        for row in r:
            t = dt.datetime.strptime(row["entryTimeUTC"], "%Y.%m.%d %H:%M").replace(tzinfo=dt.timezone.utc)
            out.append(dict(dt=t, side=row["dir"], entry=float(row["entry"]),
                            pnl=float(row["realizedUsd"]), tag=row["exitTag"]))
    return out

def parse_tv(path, tz_shift_hours=0):
    """TV CSV -> list of positions (TP1+TP2 portions regrouped by shared entry)."""
    rows = []
    with open(path, newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            rows.append(row)
    # group by Trade number: each has an Entry row + an Exit row
    bynum = defaultdict(dict)
    for row in rows:
        typ = row["Type"].lower()
        kind = "entry" if "entry" in typ else "exit"
        bynum[row["Trade number"]][kind] = row
    # collapse portions into positions keyed by (entry dt, side, entry price)
    pos = {}
    shift = dt.timedelta(hours=tz_shift_hours)
    for num, leg in bynum.items():
        e = leg.get("entry"); x = leg.get("exit")
        if e is None:
            continue
        t = dt.datetime.strptime(e["Date and time"], "%Y-%m-%d %H:%M").replace(tzinfo=dt.timezone.utc) + shift
        side = "L" if "long" in e["Type"].lower() else "S"
        entry = float(e["Price USD"])
        key = (t, side, round(entry, 2))
        pnl = float((x or e)["Net PnL USD"])
        sig = (x or e)["Signal"]
        if key not in pos:
            pos[key] = dict(dt=t, side=side, entry=entry, pnl=0.0, sigs=[], portion_pnls=[])
        pos[key]["pnl"] += pnl
        pos[key]["sigs"].append(sig)
        pos[key]["portion_pnls"].append(pnl)
    out = list(pos.values())
    for p in out:
        # Exit classification from the portion PnLs (compounding-neutral, sign-based):
        #   reached_tp2  = the 80% runner portion booked a clear profit (TP2 hit)
        #   be_win       = small net positive (TP1 banked, runner ~breakeven)
        #   full_loss    = net negative (stopped before/at TP1)
        pnls = p["portion_pnls"]
        runner = max(pnls, key=abs) if pnls else 0.0   # the 80% portion dominates magnitude
        if p["pnl"] <= 0:
            p["tag"] = "LOSS"
        elif runner > 0 and len(pnls) >= 2 and min(pnls) > 0:
            p["tag"] = "TP2"          # both portions positive -> runner reached its target
        else:
            p["tag"] = "BE-WIN"       # net win but runner flat/negative -> BE/partial only
    return out

def stats(positions, lo, hi):
    ps = [p for p in positions if lo <= p["dt"] <= hi]
    n = len(ps)
    if n == 0:
        return dict(n=0)
    longs = sum(1 for p in ps if p["side"] == "L")
    wins = [p["pnl"] for p in ps if p["pnl"] > 0]
    losses = [p["pnl"] for p in ps if p["pnl"] <= 0]
    gross_w = sum(wins); gross_l = -sum(losses)
    days = (hi - lo).days or 1
    hours = Counter(p["dt"].hour for p in ps)
    tags = Counter(p["tag"] for p in ps)
    return dict(n=n, pct_long=100*longs/n, win=100*len(wins)/n,
                pf=(gross_w/gross_l if gross_l > 0 else float("inf")),
                net=sum(p["pnl"] for p in ps), avg_w=(gross_w/len(wins) if wins else 0),
                avg_l=(gross_l/len(losses) if losses else 0), per_day=n/days,
                hours=hours, tags=tags)

def fmt(s):
    if s.get("n", 0) == 0:
        return "  (no positions in window)"
    return (f"  positions   {s['n']}\n"
            f"  % long      {s['pct_long']:.1f}\n"
            f"  win rate    {s['win']:.1f}%\n"
            f"  profit fac  {s['pf']:.3f}\n"
            f"  net P&L     {s['net']:,.0f}\n"
            f"  avg win     {s['avg_w']:,.1f}   avg loss {s['avg_l']:,.1f}\n"
            f"  per day     {s['per_day']:.2f}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True)
    ap.add_argument("--tv", required=True)
    ap.add_argument("--tz-shift-hours", type=float, default=0.0)
    a = ap.parse_args()

    eng = parse_engine(a.engine)
    tv = parse_tv(a.tv, a.tz_shift_hours)
    # overlapping window
    lo = max(min(p["dt"] for p in eng), min(p["dt"] for p in tv))
    hi = min(max(p["dt"] for p in eng), max(p["dt"] for p in tv))
    es, ts = stats(eng, lo, hi), stats(tv, lo, hi)
    q_hi = lo + dt.timedelta(days=90)   # compounding-neutral window (both accounts ~ $10k early)
    eq, tq = stats(eng, lo, q_hi), stats(tv, lo, q_hi)

    print(f"=== overlap window: {lo:%Y-%m-%d} .. {hi:%Y-%m-%d}  (tz-shift {a.tz_shift_hours:+.0f}h) ===\n")
    print("ENGINE (C++ / MT5 feed)"); print(fmt(es)); print()
    print("TRADINGVIEW (Pine / OANDA feed)"); print(fmt(ts)); print()
    if es.get("n") and ts.get("n"):
        print("DELTA (engine vs TV)")
        print(f"  count ratio   {es['n']/ts['n']:.2f}x   ({es['n']} vs {ts['n']})")
        print(f"  win rate      {es['win']-ts['win']:+.1f} pts")
        print(f"  profit factor {es['pf']-ts['pf']:+.3f}")
        print(f"  % long        {es['pct_long']-ts['pct_long']:+.1f} pts")
        print()
        print("HOUR-OF-DAY (UTC) position counts  [hour: eng / tv]")
        line = "  " + "  ".join(f"{h:02d}:{es['hours'].get(h,0)}/{ts['hours'].get(h,0)}" for h in range(24))
        print(line)
        print()
        print(f"  engine exit tags: {dict(es['tags'])}")
        print(f"  tv     exit tags: {dict(ts['tags'])}")
        print()
        print(f"FIRST 90 DAYS (compounding-neutral PF; both accounts ~$10k):")
        print(f"  engine: n={eq['n']} win={eq['win']:.1f}% PF={eq['pf']:.3f} net={eq['net']:,.0f}")
        print(f"  tv    : n={tq['n']} win={tq['win']:.1f}% PF={tq['pf']:.3f} net={tq['net']:,.0f}")

if __name__ == "__main__":
    main()
