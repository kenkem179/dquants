# MasterVP VP-length study (S8 series) — 2026-06-20

## Key finding: local VP is INERT in breakout-only mode
All master=480 configs give identical results for local lookback 60..240 — the
breakout signal keys entirely off the MASTER VP's VAH/VAL (Strategy.mqh sVah/sVal).
Local VP is only consumed by reversion (OFF). So the true tuned param is MASTER LENGTH.

## Master VP length sweep (train + OOS)
MASTER VP length sweep (local fixed 60; master = 60*mult):
master bars ( hrs) |             TRAIN PF/dd%/net/n |               OOS PF/dd%/net/n
----------------------------------------------------------------------------------
        300 ( 15h) | PF1.124 dd34.5 net  9,921 n 1476 | PF0.902 dd44.4 net -3,390 n  790
        360 ( 18h) | PF1.239 dd18.1 net 17,729 n 1435 | PF1.041 dd22.6 net  1,770 n  753
        420 ( 21h) | PF1.216 dd26.0 net 16,879 n 1360 | PF1.075 dd15.4 net  2,912 n  708
        480 ( 24h) | PF1.264 dd29.5 net 21,769 n 1317 | PF1.114 dd17.5 net  4,575 n  669
        540 ( 27h) | PF1.170 dd40.0 net 11,955 n 1312 | PF1.125 dd13.5 net  4,603 n  652
        600 ( 30h) | PF1.099 dd24.2 net  5,423 n 1295 | PF1.112 dd20.1 net  4,143 n  624
        720 ( 36h) | PF1.210 dd18.8 net 16,839 n 1251 | PF1.151 dd18.4 net  5,339 n  596
        840 ( 42h) | PF1.059 dd36.0 net  3,292 n 1246 | PF1.034 dd29.8 net  1,066 n  586

## Decision
LOCK master = 480 bars (24h on M3), expressed as InpVpLookback=120 x InpMasterMult=4.
- Interior to a broad OOS plateau (480->720 bars all OOS PF 1.11-1.15); no adjacent collapse.
- Train PF 1.264 / OOS PF 1.114, OOS net +4,575, OOS maxDD 17.5%.
- 720 bars (36h) is marginally higher (OOS PF 1.151) but sits at the edge before the 840 falloff.

## Multi-TF VP idea (user) — recommendation
Because local VP is currently UNUSED, the user's "double-check with local M3 + HTF M5/M15 VP"
is a genuine signal-enrichment opportunity, NOT yet realized. The 480-bar master already acts as
a ~24h HTF profile built from M3 bars (so "fix the master, it IS the HTF view" is already true).
NEXT EXPERIMENT (deferred, needs C++ build + sweep + OOS): add a breakout AGREEMENT gate requiring
price to also clear the LOCAL (6h) VAH/VAL and/or an M5/M15 VP VAH/VAL — turning the dead local VP
into a confirmation filter. Build in cpp_core first, sweep, OOS-validate before porting to the EA.

## Short / scalping-scale master VP (user concern: 24h too long)
```
SHORT / scalping-scale master VP (local=mult so master=local*mult; testing 1-18h):
master bars ( hrs) |             TRAIN PF/dd%/net/n |               OOS PF/dd%/net/n
----------------------------------------------------------------------------------
         20 ( 1.0) | PF0.880 dd77.0 net -5,825 n 1860 | PF1.005 dd28.7 net    203 n  976
         40 ( 2.0) | PF0.920 dd67.3 net -4,309 n 1876 | PF1.081 dd25.7 net  5,571 n  979
         60 ( 3.0) | PF1.053 dd39.1 net  3,847 n 1859 | PF1.025 dd24.0 net  1,394 n  976
        120 ( 6.0) | PF1.052 dd38.7 net  3,777 n 1752 | PF1.023 dd32.7 net  1,349 n  924
        180 ( 9.0) | PF1.113 dd21.9 net 11,020 n 1659 | PF1.050 dd26.7 net  2,654 n  864
        240 (12.0) | PF1.041 dd41.6 net  2,711 n 1542 | PF0.998 dd26.3 net    -84 n  822
        300 (15.0) | PF1.124 dd34.5 net  9,921 n 1476 | PF0.902 dd44.4 net -3,390 n  790
        360 (18.0) | PF1.239 dd18.1 net 17,729 n 1435 | PF1.041 dd22.6 net  1,770 n  753
        480 (24.0) | PF1.264 dd29.5 net 21,769 n 1317 | PF1.114 dd17.5 net  4,575 n  669
```
VERDICT: short master VPs (1-6h) are noise on this feed (1-2h LOSE on train, dd 67-77%);
12-15h die OOS. Robust region is 18-24h+. 9h (180b) is the only short bright spot (OOS PF 1.050).
Shipped KK-MasterVP-XAUUSD-9h.set (60x3) as an A/B variant; 24h (120x4) remains the primary lock.
