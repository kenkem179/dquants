# cpp_core — KenKem C++ strategy core

Pure, dependency-free C++20 strategy logic (Layer 2/3). No MT5 APIs, no broker calls —
replays imported tick/bar CSVs headlessly and deterministically. Build: `make` / `make test`.

## Ownership layout

Source is split by **strategy ownership**, mirroring the MQL5 sibling repo
(`kenkem/MQL5/Experts/`). Each bucket appears in `include/`, `tests/`, and `tools/`.

| Bucket       | Folder        | MQL5 counterpart           | What lives here |
|--------------|---------------|----------------------------|-----------------|
| **common**   | `kk/common/`  | `KK-Common`                | Shared infrastructure + generic trade management used across strategies: `types`, `config` (base `Params`), `execution`, `filters` (sessions/news/ATR%), `bars_csv`, `test` (unit harness), `risk_manager`, `position_manager`, `trade_journal`. |
| **mastervp** | `kk/mastervp/`| `KK-MasterVP`              | KK-MasterVP signal/strategy logic: `indicators`, `volume_profile`, `regime`, `node_engine`, `strategy`, `tick_engine` (Layer-3 integrator), `parity_runner` (MT5 bar-level parity). |
| **monster**  | `kk/monster/` | `KK-MasterVP-Monster`      | Monster edition: `monster_config`, `monster_signal`, `tf_net` (multi-TF net volume), `monster_engine`. Reuses `common/` infra (execution, filters, types). |

> KenKem Original and KenKem SuperBros exist only on the MQL5 side
> (`KenKem` expert + `*superbros*` parameter sets). They have **no C++ implementation** —
> the C++ core only implements the Volume-Profile strategies (MasterVP + Monster).

## Directory tree

```
include/kk/{common,mastervp,monster}/*.hpp    strategy code, bucketed
tests/{common,mastervp,monster}/*.cpp         unit tests, bucketed
tests/mastervp/golden/                         frozen MT5-parity fixtures
tools/mastervp/   backtester.cpp, parity_driver.cpp
tools/monster/    monster_backtester.cpp
tools/common/     export_bars.py, export_ticks.py, diff_parity.py, diff_trades.py, validate_parity_py.py
tools/*.set, tools/*.csv                        run configs + generated bar/tick data (gitignored CSVs)
```

## Build

```bash
make            # all tests + parity_driver + backtester + monster_backtester
make test       # build + run every tests/**/ unit test
make monster    # build tools/monster/monster_backtester.cpp -> build/monster_backtester
make BUILD=/tmp/x test   # build into an alternate dir (won't touch a live ./build binary)
```

Dependency rule: `common/` may not include `mastervp/` or `monster/`; the strategy buckets
depend on `common/` (and only on themselves). This keeps each strategy independently testable.
