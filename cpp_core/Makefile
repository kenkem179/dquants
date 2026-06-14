# KenKem C++ strategy core — dependency-free build (Apple clang, C++20).
#
# Source is split by strategy ownership (mirrors the MQL5 sibling repo):
#   include/kk/common/    shared infra + generic trade-mgmt  (≈ KK-Common)
#   include/kk/mastervp/  KK-MasterVP signal/strategy logic   (≈ KK-MasterVP)
#   include/kk/monster/   KK-MasterVP-Monster logic           (≈ KK-MasterVP-Monster)
# Tests and tools mirror the same common/ mastervp/ monster/ buckets.
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
             $(wildcard include/kk/monster/*.hpp)
PARITY    := $(BUILD)/parity_driver
BACKTEST  := $(BUILD)/backtester
MONSTER   := $(BUILD)/monster_backtester

all: $(TEST_BINS) $(PARITY) $(BACKTEST) $(MONSTER)

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

test: $(TEST_BINS)
	@fail=0; for t in $(TEST_BINS); do echo "==== $$t ===="; $$t || fail=1; done; \
	 if [ $$fail -eq 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi; exit $$fail

clean:
	rm -rf $(BUILD)

.PHONY: all test parity backtester monster clean
