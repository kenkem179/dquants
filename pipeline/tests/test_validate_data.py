"""Tests for Phase 2 validator — synthetic Parquet built in-memory, never the real files."""
from __future__ import annotations

import datetime as dt

import duckdb
from pathlib import Path
import pytest

from pipeline import config, validate_data
from pipeline.validate_data import validate_file


def _write_ticks(path, rows):
    """rows: list of (ts: datetime, bid, ask). mid/spread/flags derived."""
    con = duckdb.connect()
    con.execute("CREATE TABLE t(ts TIMESTAMP, bid DOUBLE, ask DOUBLE, mid DOUBLE, spread DOUBLE, flags INTEGER)")
    con.executemany(
        "INSERT INTO t VALUES (?,?,?,?,?,?)",
        [(ts, b, a, (b + a) / 2, a - b, 6) for ts, b, a in rows],
    )
    con.execute(f"COPY t TO '{path.as_posix()}' (FORMAT PARQUET)")
    con.close()


def _base(n=0):
    return dt.datetime(2025, 1, 1, 0, 0, 0) + dt.timedelta(seconds=n)


def _read(path):
    return duckdb.sql(f"SELECT * FROM read_parquet('{Path(path).as_posix()}') ORDER BY ts").df()


@pytest.fixture(autouse=True)
def _redirect_dirs(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "PROCESSED_DIR", tmp_path / "processed")
    monkeypatch.setattr(config, "REPORTS_DIR", tmp_path / "reports")
    (tmp_path / "processed").mkdir()
    (tmp_path / "reports").mkdir()


def test_drops_exact_duplicate_keeps_first(tmp_path):
    src = config.PROCESSED_DIR / "ticks_x_2025.parquet"
    _write_ticks(src, [
        (_base(0), 100.0, 101.0),
        (_base(0), 100.0, 101.0),   # exact dup (same ts,bid,ask)
        (_base(1), 100.5, 101.5),
    ])
    rep = validate_file(src, symbol="x", year=2025)
    assert rep.dropped["exact_dup"] == 1
    assert rep.total_kept == 2
    assert rep.passed


def test_keeps_ts_collision(tmp_path):
    """Same timestamp but different price = real sub-ms tick; must be kept, only flagged."""
    src = config.PROCESSED_DIR / "ticks_x_2025.parquet"
    _write_ticks(src, [
        (_base(0), 100.0, 101.0),
        (_base(0), 100.2, 101.2),   # same ts, different price -> collision, keep
    ])
    rep = validate_file(src, symbol="x", year=2025)
    assert rep.flagged["ts_collision"] == 1
    assert rep.dropped["exact_dup"] == 0
    assert rep.total_kept == 2


def test_drops_bad_price_and_negative_spread(tmp_path):
    src = config.PROCESSED_DIR / "ticks_x_2025.parquet"
    _write_ticks(src, [
        (_base(0), 100.0, 101.0),
        (_base(1), 0.0, 101.0),     # bad price (bid<=0)
        (_base(2), 102.0, 101.0),   # negative spread (ask<bid)
        (_base(3), 100.0, 100.5),
    ])
    rep = validate_file(src, symbol="x", year=2025)
    assert rep.dropped["bad_px"] == 1
    assert rep.dropped["neg_spread"] == 1
    assert rep.total_kept == 2
    assert rep.passed


def test_drops_round_trip_spike_but_not_genuine_move(tmp_path):
    src = config.PROCESSED_DIR / "ticks_x_2025.parquet"
    _write_ticks(src, [
        (_base(0), 100.0, 100.2),
        (_base(1), 100.0, 100.2),
        (_base(2), 130.0, 130.2),   # +30% spike that reverts -> drop
        (_base(3), 100.1, 100.3),
        (_base(4), 100.1, 100.3),
    ])
    rep = validate_file(src, symbol="x", year=2025, spike_threshold=0.01)
    assert rep.dropped["spike"] == 1
    df = _read(rep.clean_dst)
    assert not (df["mid"] > 120).any()


def test_genuine_trend_not_flagged_as_spike(tmp_path):
    # A sustained move (does not revert) must NOT be dropped.
    src = config.PROCESSED_DIR / "ticks_x_2025.parquet"
    _write_ticks(src, [
        (_base(0), 100.0, 100.2),
        (_base(1), 105.0, 105.2),   # +5% and stays up
        (_base(2), 105.1, 105.3),
        (_base(3), 105.2, 105.4),
    ])
    rep = validate_file(src, symbol="x", year=2025, spike_threshold=0.01)
    assert rep.dropped["spike"] == 0
    assert rep.total_kept == 4


def test_residual_clean_passes_and_report_written(tmp_path):
    src = config.PROCESSED_DIR / "ticks_x_2025.parquet"
    _write_ticks(src, [(_base(i), 100.0 + i * 0.1, 100.2 + i * 0.1) for i in range(50)])
    rep = validate_file(src, symbol="x", year=2025)
    assert rep.passed
    assert all(v == 0 for v in rep.residual.values())
    assert validate_data.report_path("x", 2025, "md").exists()
    assert validate_data.report_path("x", 2025, "json").exists()
    md = validate_data.report_path("x", 2025, "md").read_text()
    assert "Validation Report" in md and "Residual check" in md


def test_overwrite_guard(tmp_path):
    src = config.PROCESSED_DIR / "ticks_x_2025.parquet"
    _write_ticks(src, [(_base(0), 100.0, 101.0)])
    validate_file(src, symbol="x", year=2025)
    with pytest.raises(FileExistsError):
        validate_file(src, symbol="x", year=2025)
    validate_file(src, symbol="x", year=2025, overwrite=True)


def test_gap_buckets(tmp_path):
    src = config.PROCESSED_DIR / "ticks_x_2025.parquet"
    _write_ticks(src, [
        (_base(0), 100.0, 101.0),
        (_base(2), 100.0, 101.0),    # 2s gap
        (_base(100), 100.0, 101.0),  # 98s gap
    ])
    rep = validate_file(src, symbol="x", year=2025)
    assert rep.gaps["gt_1s"] == 2     # 2s and 98s both > 1s
    assert rep.gaps["gt_60s"] == 1    # only the 98s
    assert rep.gaps["max_gap_s"] == pytest.approx(98.0)
