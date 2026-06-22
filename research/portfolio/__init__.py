"""Portfolio construction for combining multiple engine trade streams (EA x symbol x timeframe).

The retail-FX answer to "I run one EA on two timeframes / two symbols — how do I size them together?"
See portfolio.py for the API; QUANT_MATURITY_ASSESSMENT.md (docs/) for the why.
"""
from .portfolio import (
    load_stream, build_returns_matrix, shrink_cov_constant_corr,
    weights_equal, weights_inverse_variance, weights_risk_parity,
    weights_hrp, weights_max_sharpe, weights_kelly,
    portfolio_metrics, allocate, ALLOC_METHODS,
)

__all__ = [
    "load_stream", "build_returns_matrix", "shrink_cov_constant_corr",
    "weights_equal", "weights_inverse_variance", "weights_risk_parity",
    "weights_hrp", "weights_max_sharpe", "weights_kelly",
    "portfolio_metrics", "allocate", "ALLOC_METHODS",
]
