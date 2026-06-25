# dquants — convenience targets
.PHONY: help release release-no-compile account-releases

help:
	@echo "dquants make targets"
	@echo "===================="
	@echo "  make release STRATEGY=<name> [NOTES=\"...\"]             Compile + package a versioned EA release"
	@echo "  make release-no-compile STRATEGY=<name> [NOTES=\"...\"]  Package using the existing dev .ex5"
	@echo "  make account-releases STRATEGY=<name> [ACCOUNTS=<file>] [EXPIRY=YYYY.MM.DD] Build ONE account-locked build per account"
	@echo ""
	@echo "  <name> is a folder under mql5/experts/ OR mql5/indicators/ (e.g. KK-MasterVP, KK-MasterVP-Profiler)."
	@echo "  EXPIRY sets a default access end-date for every account (per-account dates can override in the list)."
	@echo "  Version is read from '#property version' in the .mq5 (MQL5 <major>.<minor>)."
	@echo "  Output: mql5/experts/<name>/releases/<version>/  (account builds -> .../accounts/)"
	@echo "  NOTES=\"...\" records a one-line description in releases/Changelog.md (newest on top)."
	@echo "  account-releases bakes each MT5 account into the marketplace (internals-hidden) build;"
	@echo "  accounts default to scripts/deployment_accounts[.<name>].txt (gitignored) or pass ACCOUNTS=<file>."

release:
	@test -n "$(STRATEGY)" || { echo "usage: make release STRATEGY=<name> [NOTES=\"...\"]"; exit 1; }
	@./scripts/make_release.sh "$(STRATEGY)" $(if $(NOTES),--notes "$(NOTES)")

release-no-compile:
	@test -n "$(STRATEGY)" || { echo "usage: make release-no-compile STRATEGY=<name> [NOTES=\"...\"]"; exit 1; }
	@./scripts/make_release.sh "$(STRATEGY)" --no-compile $(if $(NOTES),--notes "$(NOTES)")

account-releases:
	@test -n "$(STRATEGY)" || { echo "usage: make account-releases STRATEGY=<name> [ACCOUNTS=<file>] [EXPIRY=YYYY.MM.DD]"; exit 1; }
	@./scripts/make_account_releases.sh "$(STRATEGY)" $(if $(ACCOUNTS),--accounts "$(ACCOUNTS)") $(if $(EXPIRY),--expiry "$(EXPIRY)")
