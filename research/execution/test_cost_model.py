#!/usr/bin/env python3
"""Tests for the execution cost model. Run: pytest research/execution/test_cost_model.py"""
import os
import sys
from datetime import datetime

import numpy as np
import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from execution import cost_model as C  # noqa: E402


def _trades(pnls, hour=10, lot=0.1):
    return [dict(dt=datetime(2025, 1, 1 + i % 27, hour), pnl=p, lot=lot, mae_r=1.0)
            for i, p in enumerate(pnls)]


def test_session_mapping():
    assert C.session_of(datetime(2025, 1, 1, 21, 30)) == "rollover"
    assert C.session_of(datetime(2025, 1, 1, 2)) == "asia"
    assert C.session_of(datetime(2025, 1, 1, 8)) == "london"
    assert C.session_of(datetime(2025, 1, 1, 14)) == "overlap"
    assert C.session_of(datetime(2025, 1, 1, 18)) == "ny"


def test_breakeven_equals_mean_pnl():
    trades = _trades([10, -5, 8, -3, 20])
    be = C.breakeven_cost(trades)
    assert be["breakeven_cost_per_trade"] == pytest.approx(np.mean([10, -5, 8, -3, 20]))


def test_fixed_cost_reduces_net_by_n_times_cost():
    trades = _trades([10, -5, 8, -3, 20])
    pnls = C.apply_cost(trades, fixed_usd=2.0)
    base_net = sum(t["pnl"] for t in trades)
    assert pnls.sum() == pytest.approx(base_net - 2.0 * len(trades))


def test_cost_monotonically_degrades_net():
    trades = _trades([5, 5, 5, 5, 5, 5, 5, 5])
    rows = C.cost_stress_sweep(trades, [0.5, 1.0, 2.0, 5.0], mode="fixed_usd")
    nets = [st["net"] for _, _, st in rows]
    assert all(nets[i] >= nets[i + 1] for i in range(len(nets) - 1))  # higher cost -> lower net


def test_pip_based_cost_uses_lot_and_pip_value():
    trades = _trades([100, 100], lot=0.1)
    # 2 extra pips * pip_value 10 * lot 0.1 = 2.0 per trade
    pnls = C.apply_cost(trades, extra_pips=2.0, pip_value=10.0)
    assert pnls.sum() == pytest.approx(200.0 - 2.0 * 2)


def test_tail_spike_only_hits_a_fraction():
    trades = _trades([0.0] * 1000, lot=1.0)
    pnls = C.apply_cost(trades, base_spread_pips=1.0, pip_value=10.0,
                        tail_frac=0.1, tail_mult=10.0, seed=42)
    hit = (pnls < -1e-9).sum()
    assert 60 <= hit <= 140  # ~10% of 1000, allowing sampling noise


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
