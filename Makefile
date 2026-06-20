# dquants — convenience targets
.PHONY: help release release-no-compile

help:
	@echo "dquants make targets"
	@echo "===================="
	@echo "  make release STRATEGY=<name>             Compile + package a versioned EA release"
	@echo "  make release-no-compile STRATEGY=<name>  Package using the existing dev .ex5"
	@echo ""
	@echo "  <name> is a folder under mql5/experts/ (e.g. KK-MasterVP)."
	@echo "  Version is read from '#property version' in the .mq5 (MQL5 <major>.<minor>)."
	@echo "  Output: mql5/experts/<name>/releases/<version>/"

release:
	@test -n "$(STRATEGY)" || { echo "usage: make release STRATEGY=<name>"; exit 1; }
	@./scripts/make_release.sh "$(STRATEGY)"

release-no-compile:
	@test -n "$(STRATEGY)" || { echo "usage: make release-no-compile STRATEGY=<name>"; exit 1; }
	@./scripts/make_release.sh "$(STRATEGY)" --no-compile
