"""Shared paths and constants for the KenKem Quant OS Python pipeline (Layer 1).

Everything downstream resolves locations from here so the raw → processed → features → labels
flow stays one-directional and machine-independent.
"""
from __future__ import annotations

import re
from pathlib import Path

# --- Roots ---
PROJECT_ROOT: Path = Path(__file__).resolve().parents[1]
DATA_DIR: Path = PROJECT_ROOT / "data"
PROCESSED_DIR: Path = DATA_DIR / "processed"
FEATURES_DIR: Path = DATA_DIR / "features"
LABELS_DIR: Path = DATA_DIR / "labels"
REPORTS_DIR: Path = PROJECT_ROOT / "reports"

# --- Raw tick data ---
# MT5 tick exports live in a per-symbol directory, e.g. data/btcusd/BTCUSD_ticks_mt5_2025.csv
RAW_FILENAME_RE = re.compile(r"_ticks_mt5_(?P<year>\d{4})\.csv$", re.IGNORECASE)

# MT5 tick CSV is tab-separated with this header (see docs/KENKEM_QUANT_OS.md §3).
RAW_DELIMITER = "\t"
RAW_HEADER = ["<DATE>", "<TIME>", "<BID>", "<ASK>", "<LAST>", "<VOLUME>", "<FLAGS>"]

# Output schema for processed tick Parquet (LAST/VOLUME are dropped — always 0 on this feed).
PROCESSED_COLUMNS = ["ts", "bid", "ask", "mid", "spread", "flags"]


def symbol_dir(symbol: str) -> Path:
    """Raw directory for a symbol, e.g. 'btcusd' -> data/btcusd/."""
    return DATA_DIR / symbol.lower()


def processed_path(symbol: str, year: int | str) -> Path:
    """Destination Parquet for a symbol/year, e.g. data/processed/ticks_btcusd_2025.parquet."""
    return PROCESSED_DIR / f"ticks_{symbol.lower()}_{year}.parquet"


def clean_path(symbol: str, year: int | str) -> Path:
    """Phase-2 cleaned ticks, e.g. data/processed/ticks_btcusd_2025_clean.parquet."""
    return PROCESSED_DIR / f"ticks_{symbol.lower()}_{year}_clean.parquet"


def bars_path(symbol: str, timeframe: str, year: int | str) -> Path:
    """Phase-3 bars, e.g. data/processed/bars_btcusd_M1_2025.parquet."""
    return PROCESSED_DIR / f"bars_{symbol.lower()}_{timeframe}_{year}.parquet"


def features_path(symbol: str, timeframe: str) -> Path:
    """Phase-3 features (all years, one file per timeframe)."""
    return FEATURES_DIR / f"features_{symbol.lower()}_{timeframe}.parquet"


def labels_path(symbol: str, timeframe: str) -> Path:
    """Phase-4 labels (all years, one file per timeframe)."""
    return LABELS_DIR / f"labels_{symbol.lower()}_{timeframe}.parquet"


def discover_raw_files(symbol: str) -> dict[int, Path]:
    """Map year -> raw CSV path for a symbol, by scanning its directory."""
    found: dict[int, Path] = {}
    d = symbol_dir(symbol)
    if not d.is_dir():
        return found
    for p in sorted(d.glob("*.csv")):
        m = RAW_FILENAME_RE.search(p.name)
        if m:
            found[int(m.group("year"))] = p
    return found
