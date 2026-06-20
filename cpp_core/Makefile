# KenKem C++ strategy core — dependency-free build (Apple clang, C++20).
#
# Source is split by strategy ownership (mirrors the MQL5 sibling repo):
#   include/kk/common/    shared infra + generic trade-mgmt  (≈ KK-Common)
#   include/kk/mastervp/  KK-MasterVP signal/strategy logic   (≈ KK-MasterVP)
#   include/kk/monster/   KK-MasterVP-Monster logic           (≈ KK-MasterVP-Monster)
#   include/kk/kenkem/    KenKem original multi-entry EA      (≈ KenKem/E1,E2,E4)
# Tests and tools mirror the same common/ mastervp/ monster/ kenkem/ buckets.
#
# Targets:
#   make test     build + run all unit tests in tests/**/
#   make parity   build the MasterVP parity harness (tools/mastervp/parity_driver.cpp)
#   make monster  build the Monster backtester      (tools/monster/monster_backtester.cpp)
#   make          build everything
#   make clean
# Override the output dir to verify without touching a live build: make BUILD=/tmp/xyz test
CXX      := clang++
CXXFLAGS := -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
BUILD    := build

TEST_SRCS := $(wildcard tests/*/*.cpp)
TEST_BINS := $(patsubst tests/%.cpp,$(BUILD)/%,$(TEST_SRCS))
HEADERS   := $(wildcard include/kk/common/*.hpp) \
             $(wildcard include/kk/mastervp/*.hpp) \
             $(wildcard include/kk/monster/*.hpp) \
             $(wildcard include/kk/kenkem/*.hpp)
PARITY    := $(BUILD)/parity_driver
BACKTEST  := $(BUILD)/backtester
MONSTER   := $(BUILD)/monster_backtester
KENKEM    := $(BUILD)/kenkem/backtester
KENKEMTICK:= $(BUILD)/kenkem/tick_backtester
KENKEMTRACE:= $(BUILD)/kenkem/trace_dumper
KENKEMENTRY:= $(BUILD)/kenkem/entry_trace
KENKEMVMC := $(BUILD)/kenkem/vmc_e1_lab
MVPVMC    := $(BUILD)/mastervp/vmc_mvp_lab

all: $(TEST_BINS) $(PARITY) $(BACKTEST) $(MONSTER) $(KENKEM) $(KENKEMTICK) $(KENKEMTRACE) $(KENKEMENTRY) $(KENKEMVMC) $(MVPVMC)

$(BUILD)/%: tests/%.cpp $(HEADERS)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $< -o $@

parity: $(PARITY)
$(PARITY): tools/mastervp/parity_driver.cpp $(HEADERS)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $< -o $@

backtester: $(BACKTEST)
$(BACKTEST): tools/mastervp/backtester.cpp $(HEADERS)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $< -o $@

monster: $(MONSTER)
$(MONSTER): tools/monster/monster_backtester.cpp $(HEADERS)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $< -o $@

kenkem: $(KENKEM)
$(KENKEM): tools/kenkem/backtester.cpp $(HEADERS)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $< -o $@

kenkem_tick: $(KENKEMTICK)
$(KENKEMTICK): tools/kenkem/tick_backtester.cpp $(HEADERS)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $< -o $@

kenkem_trace: $(KENKEMTRACE)
$(KENKEMTRACE): tools/kenkem/trace_dumper.cpp $(HEADERS)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $< -o $@

# Per-bar E1/E2/E4 gate-decision localizer (the Stage-2 parity tool). See PARITY_1.8.154_DETECTION_DIAGNOSIS.md.
kenkem_entry: $(KENKEMENTRY)
$(KENKEMENTRY): tools/kenkem/entry_trace_dumper.cpp $(HEADERS)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $< -o $@

# VMC-vs-E1 selection A/B lab (non-invasive: reuses the real TickEngine, adds a post-hoc VMC veto).
kenkem_vmc: $(KENKEMVMC)
$(KENKEMVMC): tools/kenkem/vmc_e1_lab.cpp $(HEADERS)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $< -o $@

# VMC support-factor lab for MasterVP (BTC M5/M3) — non-invasive, reuses the real MasterVP TickEngine.
mvp_vmc: $(MVPVMC)
$(MVPVMC): tools/mastervp/vmc_mvp_lab.cpp $(HEADERS)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $< -o $@

test: $(TEST_BINS)
	@fail=0; for t in $(TEST_BINS); do echo "==== $$t ===="; $$t || fail=1; done; \
	 if [ $$fail -eq 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi; exit $$fail

clean:
	rm -rf $(BUILD)

.PHONY: all test parity backtester monster kenkem kenkem_tick kenkem_trace kenkem_entry clean
