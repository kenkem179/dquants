#!/usr/bin/env python3
"""Normalise a KK MT5 optimizer .set into the canonical full-pipe form MT5 exports:
  swept param      ->  Name=value||start||step||stop||Y
  every other num  ->  Name=value||value||0||value||N      (force checkbox OFF)
  every other bool ->  Name=value||false||0||true||N        (force checkbox OFF)
  string/session   ->  Name=value                           (not optimizable)

Two bugs this fixes:
  1. The bogus multi-line comma encoding (Name,F / Name,1..3) MT5 silently ignores.
  2. Bare `Name=value` lines do NOT clear a checkbox that a PREVIOUS run left ticked,
     so loading grid B after grid A kept A's params checked -> cartesian blow-up
     ("thousands of passes"). An explicit ||N on every param force-resets the panel.

Idempotent: already-correct ||Y / ||N lines are preserved. In place per argv path."""
import re
import sys

ENC = re.compile(r'^([A-Za-z_]\w*),([F123])=(.*?)\s*$')
BASE = re.compile(r'^([A-Za-z_]\w*)=(.*?)\s*$')
NUM = re.compile(r'^-?\d+(\.\d+)?$')


def convert(path):
    with open(path) as fh:
        lines = fh.read().splitlines()

    opt = {}
    for ln in lines:
        m = ENC.match(ln)
        if m:
            opt.setdefault(m.group(1), {})[m.group(2)] = m.group(3)

    out, swept, disabled = [], [], 0
    for ln in lines:
        if ENC.match(ln):
            continue  # fold comma-encoding into the base line
        m = BASE.match(ln)
        if not m:
            out.append(ln)
            continue
        name, value = m.group(1), m.group(2)
        # already-pipe lines: keep as-is (idempotent)
        if '||' in value:
            out.append(ln)
            if value.rstrip().endswith('Y'):
                swept.append(name)
            continue
        if name in opt and opt[name].get('F') == '1':
            o = opt[name]
            out.append(f"{name}={value}||{o.get('1', value)}||{o.get('2', '0')}||{o.get('3', value)}||Y")
            swept.append(name)
        elif value in ('true', 'false'):
            out.append(f'{name}={value}||false||0||true||N')
            disabled += 1
        elif NUM.match(value):
            out.append(f'{name}={value}||{value}||0||{value}||N')
            disabled += 1
        else:
            out.append(ln)  # string / session / hour-list: not optimizable

    with open(path, 'w') as fh:
        fh.write('\n'.join(out) + '\n')
    print(f'{path}: {len(swept)} swept (||Y): {", ".join(swept)}  |  {disabled} pinned (||N)')


if __name__ == '__main__':
    for p in sys.argv[1:]:
        convert(p)
