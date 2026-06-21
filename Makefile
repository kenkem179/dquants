# dquants — convenience targets
.PHONY: help release release-no-compile

help:
	@echo "dquants make targets"
	@echo "===================="
	@echo "  make release STRATEGY=<name> [NOTES=\"...\"]             Compile + package a versioned EA release"
	@echo "  make release-no-compile STRATEGY=<name> [NOTES=\"...\"]  Package using the existing dev .ex5"
	@echo ""
	@echo "  <name> is a folder under mql5/experts/ (e.g. KK-MasterVP)."
	@echo "  Version is read from '#property version' in the .mq5 (MQL5 <major>.<minor>)."
	@echo "  Output: mql5/experts/<name>/releases/<version>/"
	@echo "  NOTES=\"...\" records a one-line description in releases/Changelog.md (newest on top)."

release:
	@test -n "$(STRATEGY)" || { echo "usage: make release STRATEGY=<name> [NOTES=\"...\"]"; exit 1; }
	@./scripts/make_release.sh "$(STRATEGY)" $(if $(NOTES),--notes "$(NOTES)")

release-no-compile:
	@test -n "$(STRATEGY)" || { echo "usage: make release-no-compile STRATEGY=<name> [NOTES=\"...\"]"; exit 1; }
	@./scripts/make_release.sh "$(STRATEGY)" --no-compile $(if $(NOTES),--notes "$(NOTES)")
