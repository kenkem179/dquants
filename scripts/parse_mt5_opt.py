#!/usr/bin/env python3
"""Parse an MT5 Strategy-Tester optimization cache (.opt) into a ranked CSV.

MT5 writes no human-readable optimization export to disk; the per-pass results live
only in Tester/cache/<...>.opt as a binary blob. Reverse-engineered layout (MT5
build ~4xxx, validated against the KK-MasterVP XAU M5 lock baseline):

  * N fixed-size records sit at the TAIL of the file: START = filesize - N*REC.
  * REC = 280 (fixed stats block) + 8 * n_swept_params  (params appended per record).
  * Stats block offsets (float64 unless noted), constant across grids, VERIFIED
    exact against an MT5 ReportOptimizer XML export across all 30 OPT-A rows:
        +8   initial deposit        +24  net profit
        +32  gross profit           +40  gross loss
        +152 equity drawdown %      +176 expected payoff
        +184 profit factor          +192 recovery factor
        +200 sharpe ratio           +228 (int32) total trades
  * Swept params are appended at +280, +288, ... in EA input-DECLARATION order
    (NOT .set order). We auto-assign each param column by matching the observed
    value-set to each swept param's declared {start..stop} grid, which is robust
    whenever the grids are disjoint (they are for H9 A/B/C).

Usage:
  parse_mt5_opt.py <file.opt> --passes N \
      --param NAME start step stop [--param NAME start step stop ...] \
      [--rank PF|Net] [--out results.csv] [--bar 1.413]
"""
import argparse, csv, struct, sys

STAT = dict(deposit=8, net=24, gprofit=32, gloss=40, ddEq=152, ep=176, pf=184, recovery=192, sharpe=200)
TRADES_OFF = 228


def grid_values(start, step, stop):
    n = int(round((stop - start) / step)) + 1
    return [round(start + i * step, 10) for i in range(n)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('opt')
    ap.add_argument('--passes', type=int, required=True)
    ap.add_argument('--param', nargs=4, action='append', metavar=('NAME', 'START', 'STEP', 'STOP'), required=True)
    ap.add_argument('--rank', default='PF', choices=['PF', 'Net'])
    ap.add_argument('--out')
    ap.add_argument('--bar', type=float)
    a = ap.parse_args()

    params = [(n, grid_values(float(s), float(st), float(sp))) for n, s, st, sp in a.param]
    b = open(a.opt, 'rb').read()
    N, REC = a.passes, 280 + 8 * len(params)
    START = len(b) - N * REC
    if START < 0:
        sys.exit(f"file too small: {len(b)} bytes < {N}*{REC}")

    rows = []
    for i in range(N):
        r = b[START + i * REC:START + (i + 1) * REC]
        d = lambda o: struct.unpack_from('<d', r, o)[0]
        row = {k: d(o) for k, o in STAT.items()}
        row['Trades'] = struct.unpack_from('<i', r, TRADES_OFF)[0]
        raw = [d(280 + 8 * j) for j in range(len(params))]
        # assign each record param-slot to the swept param whose grid contains it
        for slot, val in enumerate(raw):
            name, vals = params[slot]
            match = next((v for v in vals if abs(v - val) < 1e-6), round(val, 6))
            row[name] = match
        rows.append(row)

    rows = [x for x in rows if x['Trades'] > 0]
    rows.sort(key=lambda x: -(x['pf'] if a.rank == 'PF' else x['net']))

    pcols = [p[0] for p in params]
    if a.out:
        with open(a.out, 'w', newline='') as f:
            w = csv.writer(f)
            w.writerow(pcols + ['Net', 'PF', 'Trades', 'EqDDPct', 'ExpPayoff', 'Recovery', 'Sharpe'])
            for x in rows:
                w.writerow([x[c] for c in pcols] + [round(x['net'], 2), round(x['pf'], 4), x['Trades'],
                                                    round(x['ddEq'], 2), round(x['ep'], 2),
                                                    round(x['recovery'], 3), round(x['sharpe'], 3)])
    head = '  '.join(f'{c:>10}' for c in pcols) + f"  {'Net':>10}  {'PF':>6}  {'Trd':>5}  {'EqDD%':>5}"
    print(head); print('-' * len(head))
    for x in rows:
        flag = ' BEAT' if (a.bar and x['pf'] > a.bar) else ''
        print('  '.join(f'{x[c]:>10}' for c in pcols) + f"  {x['net']:>10,.0f}  {x['pf']:>6.3f}  {x['Trades']:>5}  {x['ddEq']:>5.1f}{flag}")
    if a.bar:
        print(f"\nPF bar {a.bar}: {sum(1 for x in rows if x['pf'] > a.bar)}/{len(rows)} passes beat it")


if __name__ == '__main__':
    main()
