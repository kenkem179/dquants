// Minimal CSV loader for the bid M3 bars produced by cpp_core/tools/export_bars.py.
// Header: ts_ms,open,high,low,close,tick_count  (ts_ms = epoch milliseconds UTC).
#pragma once
#include <vector>
#include <string>
#include <fstream>
#include <sstream>
#include "kk/common/types.hpp"

namespace kk {

// Load bars from `path`. Returns empty on open failure (check .empty()). Skips the header
// row. `t_from_ms`/`t_to_ms` (inclusive/exclusive) optionally clip the range; 0 = no bound.
inline std::vector<Bar> load_bars_csv(const std::string& path,
                                      int64_t t_from_ms = 0, int64_t t_to_ms = 0) {
    std::vector<Bar> bars;
    std::ifstream f(path);
    if (!f) return bars;
    std::string line;
    std::getline(f, line);  // header
    while (std::getline(f, line)) {
        if (line.empty()) continue;
        std::stringstream ss(line);
        std::string cell;
        Bar b;
        int col = 0;
        while (std::getline(ss, cell, ',')) {
            switch (col) {
                case 0: b.ts_ms = std::stoll(cell); break;
                case 1: b.open  = std::stod(cell); break;
                case 2: b.high  = std::stod(cell); break;
                case 3: b.low   = std::stod(cell); break;
                case 4: b.close = std::stod(cell); break;
                case 5: b.tick_count = std::stoll(cell); break;
                default: break;
            }
            ++col;
        }
        if (col < 6) continue;
        if (t_from_ms && b.ts_ms < t_from_ms) continue;
        if (t_to_ms && b.ts_ms >= t_to_ms) continue;
        bars.push_back(b);
    }
    return bars;
}

}  // namespace kk
