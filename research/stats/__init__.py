"""Statistical rigor layer for dquants — overfitting control & multiple-testing correction.

The methods here are the backtest-selection 'best practices' (Bailey & Lopez de Prado) that guard
our sweep->lock workflow against multiple-testing bias. See overfitting.py for the why.
"""
from .overfitting import (  # noqa: F401
    sharpe_ratio,
    probabilistic_sharpe_ratio,
    expected_max_sharpe,
    deflated_sharpe_ratio,
    min_track_record_length,
    prob_backtest_overfit,
    bonferroni,
    benjamini_hochberg,
    overfitting_report,
    print_report,
)
