# KK-MasterVP C++ tick backtester — dependency-free build (Apple clang, C++20).
# Targets:
#   make test     build + run all unit tests in tests/
#   make parity   build the parity harness driver (tools/parity_driver.cpp)
#   make          build everything
#   make clean
CXX      := clang++
CXXFLAGS := -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
BUILD    := build

TEST_SRCS := $(wildcard tests/*.cpp)
TEST_BINS := $(patsubst tests/%.cpp,$(BUILD)/%,$(TEST_SRCS))
HEADERS   := $(wildcard include/kk/*.hpp)
PARITY    := $(BUILD)/parity_driver
BACKTEST  := $(BUILD)/backtester

all: $(TEST_BINS) $(PARITY) $(BACKTEST)

$(BUILD)/%: tests/%.cpp $(HEADERS)
	@mkdir -p $(BUILD)
	$(CXX) $(CXXFLAGS) $< -o $@

parity: $(PARITY)
$(PARITY): tools/parity_driver.cpp $(HEADERS)
	@mkdir -p $(BUILD)
	$(CXX) $(CXXFLAGS) $< -o $@

backtester: $(BACKTEST)
$(BACKTEST): tools/backtester.cpp $(HEADERS)
	@mkdir -p $(BUILD)
	$(CXX) $(CXXFLAGS) $< -o $@

test: $(TEST_BINS)
	@fail=0; for t in $(TEST_BINS); do echo "==== $$t ===="; $$t || fail=1; done; \
	 if [ $$fail -eq 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi; exit $$fail

clean:
	rm -rf $(BUILD)

.PHONY: all test parity backtester clean
