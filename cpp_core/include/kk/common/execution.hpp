// Execution simulator — the fill model for the headless backtester. Mirrors the MT5
// tester's market-order behaviour for KK-MasterVP (TradeManager.mqh OpenTrade):
//
//   * Entry is a MARKET order sent on the first tick of the bar AFTER the signal bar
//     (the new-bar OnTick that detected the just-closed signal bar). It fills at that
//     tick's ASK for a long and BID for a short.
//   * Commission is $0 on both Exness symbols (applied in PositionManager via specs).
//   * Slippage: the MT5 tester fills at the requested market price within InpDeviationPoints
//     (200 pts) with no extra slippage model, so the faithful fill is simply the tick's
//     ask/bid. `slippage_price` is the seam where a future microstructure model would add
//     adverse slippage; it defaults to 0 (parity with the tester).
//
// Pure + headless. No state — one function the TickEngine calls at fill time.
#pragma once
#include "kk/common/types.hpp"
#include "kk/common/config.hpp"

namespace kk {

struct ExecutionSimulator {
    // Price a market fill for `is_long` against the current tick. Long buys the ask,
    // short sells the bid; optional adverse slippage widens the fill against the trader.
    static double fill_price(bool is_long, const Tick& t, double slippage_price = 0.0) {
        return is_long ? (t.ask + slippage_price) : (t.bid - slippage_price);
    }

    // Convenience: the spread paid at the fill tick (for the journal's cost-quality cols).
    static double entry_spread(const Tick& t) { return t.ask - t.bid; }
};

}  // namespace kk
