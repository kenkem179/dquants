"""Execution realism for retail FX — cost stress, breakeven cost, slippage/spread/tail models.

See cost_model.py for the API; the point is to answer "does the edge survive worse-than-assumed
costs?" rather than trusting one optimistic spread number. Mirrors KenKemExpert's abnormal-spread /
black-swan avoidance philosophy, but as an offline robustness stress on the engine's trade stream.
"""
from .cost_model import (
    load_trades, breakeven_cost, apply_cost, cost_stress_sweep,
    SESSION_SPREAD_MULT, session_of,
)

__all__ = [
    "load_trades", "breakeven_cost", "apply_cost", "cost_stress_sweep",
    "SESSION_SPREAD_MULT", "session_of",
]
