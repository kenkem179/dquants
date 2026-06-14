#!/usr/bin/env python3
"""
mt5_log_truth.py — Reconstruct MT5-TRUE performance from the MetaTrader 5 Strategy Tester
deal stream, with NO dependency on any dquants engine.

Why this exists: the dquants C++/MQL5 numbers were over-trusted. This tool reads the tester's
OWN deal log (the ground truth MT5 actually executed), reconstructs every round-trip trade by
net-position accounting, and computes the standard 9-column perf metrics. It then CROSS-CHECKS
the reconstructed net against each pass's reported "final balance" line — if they agree, the
metrics are trustworthy MT5 truth; if not, the row is flagged.

Logs are UTF-16LE. Deal lines look like:
  CS  0  00:31:56.681  Trades  2025.10.01 02:00:00   deal #2 buy 0.31 BTCUSD-Exnes-0406 at 114588.20 done (based on order #2)

Usage:
  python mt5_log_truth.py /path/to/logs/20260615.log [more logs...]
"""
import re
import sys
import math
from datetime import datetime

# Broker contract value (USD profit per 1.0 price unit per 1.0 lot) = value_per_price_per_lot.
# XAUUSD: 100 oz/lot -> $100 per $1 move. BTCUSD (Exness): 1 -> $1 per $1 move.
def vppl_for(symbol: str) -> float:
    s = symbol.upper()
    if s.startswith("XAU"):
        return 100.0
    if s.startswith("BTC"):
        return 1.0
    return 1.0  # default; flagged via balance cross-check

RUN_RE   = re.compile(r"testing of Experts\\(.+?)\.ex5 from ([\d.]+ [\d:]+) to ([\d.]+ [\d:]+)")
SYMBOL_RE= re.compile(r"^([A-Za-z0-9\-]+),(M\d+): testing of")
DEAL_RE  = re.compile(
    r"\bTrades\b\s+([\d.]+ [\d:]+)\s+deal #(\d+)\s+(buy|sell)\s+([\d.]+)\s+(\S+)\s+at\s+([\d.]+)\s+done")
BAL_RE   = re.compile(r"final balance ([\d.]+) USD")


def parse_dt(s: str) -> datetime:
    return datetime.strptime(s, "%Y.%m.%d %H:%M:%S")


class Run:
    def __init__(self, expert, symbol, tf, start, end):
        self.expert, self.symbol, self.tf = expert, symbol, tf
        self.start, self.end = start, end
        self.deals = []        # (dt, dir(+1/-1), vol, price)
        self.final_balance = None


def split_runs(path):
    runs = []
    cur = None
    with open(path, "r", encoding="utf-16-le", errors="replace") as f:
        for raw in f:
            line = raw.replace("\x00", "")
            m = RUN_RE.search(line)
            if m:
                # symbol/tf are at the front of the same line: "SYMBOL,Mx: testing of ..."
                seg = line.split("Tester")[-1].strip()
                sm = SYMBOL_RE.search(seg)
                symbol = sm.group(1) if sm else "?"
                tf = sm.group(2) if sm else "?"
                cur = Run(m.group(1), symbol, tf, m.group(2), m.group(3))
                runs.append(cur)
                continue
            if cur is None:
                continue
            bm = BAL_RE.search(line)
            if bm:
                cur.final_balance = float(bm.group(1))
                continue
            dm = DEAL_RE.search(line)
            if dm:
                dt = parse_dt(dm.group(1))
                direction = 1 if dm.group(3) == "buy" else -1
                vol = float(dm.group(4))
                price = float(dm.group(6))
                if cur.symbol == "?":
                    cur.symbol = dm.group(5)
                cur.deals.append((dt, direction, vol, price))
    return runs


def reconstruct(run: Run, initial=10000.0):
    """Net-position accounting: track signed position with weighted-avg entry; realize PnL on
    the portion closed by an opposing deal (handles partial scale-outs and reversals)."""
    vppl = vppl_for(run.symbol)
    pos = 0.0          # signed lots
    avg = 0.0          # avg entry price of the open position
    trades = []        # realized PnL per closing event (a 'trade' = a reduction in |position|)
    for dt, d, vol, price in run.deals:
        signed = d * vol
        if pos == 0 or (pos > 0 and signed > 0) or (pos < 0 and signed < 0):
            # opening or adding in same direction -> update weighted avg
            new_pos = pos + signed
            avg = (avg * abs(pos) + price * abs(signed)) / abs(new_pos) if new_pos != 0 else 0.0
            pos = new_pos
        else:
            # opposing -> close up to |pos|, realize; remainder reverses
            close_vol = min(abs(signed), abs(pos))
            direction = 1.0 if pos > 0 else -1.0
            pnl = (price - avg) * direction * close_vol * vppl
            trades.append((dt, pnl))
            remaining_open = abs(pos) - close_vol
            remaining_signed = abs(signed) - close_vol
            if remaining_open > 0:
                pos = direction * remaining_open       # still open, avg unchanged
            elif remaining_signed > 0:
                pos = -direction * remaining_signed     # reversed
                avg = price
            else:
                pos = 0.0
                avg = 0.0
    return trades, vppl


def metrics(run: Run, trades, initial=10000.0):
    if not trades:
        return dict(trades=0, net=0.0, recon_final=initial)
    pnls = [p for _, p in trades]
    net = sum(pnls)
    wins = [p for p in pnls if p > 0]
    losses = [p for p in pnls if p < 0]
    gross_win = sum(wins)
    gross_loss = -sum(losses)
    pf = gross_win / gross_loss if gross_loss > 0 else float("inf")
    # equity curve + max drawdown
    bal = initial
    peak = initial
    maxdd = 0.0
    for p in pnls:
        bal += p
        peak = max(peak, bal)
        maxdd = max(maxdd, peak - bal)
    # per-trade Sharpe (mean/std), annualized by trades/day * 252 not meaningful here -> report raw
    mean = net / len(pnls)
    std = math.sqrt(sum((p - mean) ** 2 for p in pnls) / len(pnls)) if len(pnls) > 1 else 0.0
    sharpe = (mean / std * math.sqrt(len(pnls))) if std > 0 else 0.0
    days = max(1.0, (trades[-1][0] - trades[0][0]).total_seconds() / 86400.0)
    return dict(
        trades=len(pnls),
        net=net,
        net_pct=net / initial * 100.0,
        pf=pf,
        win_pct=len(wins) / len(pnls) * 100.0,
        maxdd=maxdd,
        maxdd_pct=maxdd / peak * 100.0 if peak else 0.0,
        recovery=net / maxdd if maxdd > 0 else float("inf"),
        sharpe=sharpe,
        avg_win=gross_win / len(wins) if wins else 0.0,
        avg_loss=-gross_loss / len(losses) if losses else 0.0,
        trades_day=len(pnls) / days,
        recon_final=initial + net,
    )


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    rows = []
    for path in sys.argv[1:]:
        for run in split_runs(path):
            tr, vppl = reconstruct(run)
            m = metrics(run, tr)
            m["expert"] = run.expert.split("\\")[-1]
            m["symbol"] = run.symbol
            m["tf"] = run.tf
            m["start"] = run.start
            m["end"] = run.end
            m["final_balance"] = run.final_balance
            m["vppl"] = vppl
            m["log"] = path.split("/")[-1]
            rows.append(m)

    hdr = ("LOG          EXPERT                SYM/TF         WINDOW                       "
           "TR    NET$     NET%   PF    WIN%  MAXDD%  RECOV  SHARPE  T/DAY  | RECON  REPORTED  OK?")
    print(hdr)
    print("-" * len(hdr))
    for m in rows:
        if m["trades"] == 0:
            ok = "—" if m["final_balance"] in (None, 10000.0) else "??"
            print(f"{m['log'][:11]:11}  {m['expert'][:20]:20}  {m['symbol'][:9]:9}/{m['tf']:3}  "
                  f"{m['start'][:10]}->{m['end'][:10]}   "
                  f"{0:4}   {'ZERO TRADES':>40}   | {10000.0:7.0f}  {str(m['final_balance']):>8}  {ok}")
            continue
        rep = m["final_balance"]
        ok = "?"
        if rep is not None:
            ok = "OK" if abs(m["recon_final"] - rep) <= max(50.0, 0.02 * abs(rep)) else f"OFF({m['recon_final']-rep:+.0f})"
        pf = "inf" if m["pf"] == float("inf") else f"{m['pf']:.2f}"
        rec = "inf" if m["recovery"] == float("inf") else f"{m['recovery']:.2f}"
        print(f"{m['log'][:11]:11}  {m['expert'][:20]:20}  {m['symbol'][:9]:9}/{m['tf']:3}  "
              f"{m['start'][:10]}->{m['end'][:10]}   "
              f"{m['trades']:4}  {m['net']:7.0f}  {m['net_pct']:6.1f}  {pf:>4}  {m['win_pct']:4.0f}  "
              f"{m['maxdd_pct']:5.1f}  {rec:>5}  {m['sharpe']:5.2f}  {m['trades_day']:4.1f}  "
              f"| {m['recon_final']:7.0f}  {rep if rep else 0:8.0f}  {ok}")


if __name__ == "__main__":
    main()
