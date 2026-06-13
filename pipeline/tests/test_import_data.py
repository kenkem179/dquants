"""Tests for Phase 1 importer — run on tiny synthetic MT5-format CSVs, never the real 12GB files."""
from __future__ import annotations

import datetime as dt

import duckdb
import pytest

from pipeline import config
from pipeline.import_data import import_file, import_symbol

# A handful of rows in the exact raw MT5 export format (tab-separated, with the <...> header).
# Includes: a 3-digit millisecond fraction, a zero-fraction time, and one negative-spread row
# (ask < bid) to confirm it is REPORTED but not removed at this phase.
_RAW = "\t".join(config.RAW_HEADER) + "\n" + "\n".join(
    [
        "2024.01.01\t00:00:00.036\t42250.77\t42273.01\t0.00\t0\t6",
        "2024.01.01\t00:00:00.830\t42245.72\t42268.59\t0.00\t0\t6",
        "2024.01.01\t00:00:01.000\t42240.00\t42250.00\t0.00\t0\t6",
        "2024.01.01\t00:00:02.500\t42300.00\t42290.00\t0.00\t0\t6",  # negative spread
    ]
)


@pytest.fixture()
def raw_csv(tmp_path):
    p = tmp_path / "TEST_ticks_mt5_2024.csv"
    p.write_text(_RAW)
    return p


def _read(parquet):
    return duckdb.sql(f"SELECT * FROM read_parquet('{parquet.as_posix()}') ORDER BY ts").df()


def test_schema_and_columns(raw_csv, tmp_path):
    dst = tmp_path / "out.parquet"
    import_file(raw_csv, dst, symbol="test", year=2024)
    df = _read(dst)
    assert list(df.columns) == config.PROCESSED_COLUMNS
    assert len(df) == 4


def test_millisecond_fraction_preserved(raw_csv, tmp_path):
    """'.830' must become 830 ms (830000 us), not 830 us — the classic silent-corruption bug."""
    dst = tmp_path / "out.parquet"
    import_file(raw_csv, dst, symbol="test", year=2024)
    df = _read(dst)
    ts0, ts1 = df.iloc[0]["ts"], df.iloc[1]["ts"]
    assert ts0 == dt.datetime(2024, 1, 1, 0, 0, 0, 36000)
    assert ts1 == dt.datetime(2024, 1, 1, 0, 0, 0, 830000)


def test_mid_and_spread_derived(raw_csv, tmp_path):
    dst = tmp_path / "out.parquet"
    import_file(raw_csv, dst, symbol="test", year=2024)
    df = _read(dst)
    row = df.iloc[0]
    assert row["mid"] == pytest.approx((42250.77 + 42273.01) / 2)
    assert row["spread"] == pytest.approx(42273.01 - 42250.77)


def test_last_volume_dropped(raw_csv, tmp_path):
    dst = tmp_path / "out.parquet"
    import_file(raw_csv, dst, symbol="test", year=2024)
    df = _read(dst)
    assert "LAST" not in df.columns and "<LAST>" not in df.columns
    assert "volume" not in df.columns and "<VOLUME>" not in df.columns


def test_stats_report_negative_spread_without_removing(raw_csv, tmp_path):
    dst = tmp_path / "out.parquet"
    stats = import_file(raw_csv, dst, symbol="test", year=2024)
    assert stats.rows == 4                 # nothing removed at import
    assert stats.negative_spread == 1      # but the bad row is flagged
    assert stats.null_ts == 0
    assert stats.monotonic is True
    assert stats.matches_source()          # wc -l cross-check == rows


def test_overwrite_guard(raw_csv, tmp_path):
    dst = tmp_path / "out.parquet"
    import_file(raw_csv, dst, symbol="test", year=2024)
    with pytest.raises(FileExistsError):
        import_file(raw_csv, dst, symbol="test", year=2024)
    # force=overwrite succeeds
    import_file(raw_csv, dst, symbol="test", year=2024, overwrite=True)


def test_non_monotonic_detected(tmp_path):
    raw = "\t".join(config.RAW_HEADER) + "\n" + "\n".join(
        [
            "2024.01.01\t00:00:05.000\t100.0\t101.0\t0\t0\t6",
            "2024.01.01\t00:00:01.000\t100.0\t101.0\t0\t0\t6",  # earlier than previous
        ]
    )
    src = tmp_path / "X_ticks_mt5_2024.csv"
    src.write_text(raw)
    stats = import_file(src, tmp_path / "o.parquet", symbol="x", year=2024)
    assert stats.monotonic is False


def test_import_symbol_discovers_and_skips(tmp_path, monkeypatch):
    # Point the pipeline's data dir at a temp symbol dir with two yearly files.
    sym_dir = tmp_path / "test"
    sym_dir.mkdir()
    (sym_dir / "TEST_ticks_mt5_2024.csv").write_text(_RAW)
    (sym_dir / "TEST_ticks_mt5_2025.csv").write_text(_RAW)
    monkeypatch.setattr(config, "DATA_DIR", tmp_path)
    monkeypatch.setattr(config, "PROCESSED_DIR", tmp_path / "processed")

    res = import_symbol("test")
    assert {r.year for r in res} == {2024, 2025}
    # Re-running skips existing files (no overwrite) -> empty result.
    assert import_symbol("test") == []
