.PHONY: help format format-check lint lint-fix slither audit

# Set default target to help
.DEFAULT_GOAL := help

# Glob pattern for Solidity files
SOL_FILES = 'src/**/*.sol'

help: ## Display help information
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

lint: ## Check Solidity code with Solhint
	@echo "Linting Solidity files..."
	@npx solhint $(SOL_FILES) || yarn solhint $(SOL_FILES)

lint-fix: ## Fix automatically fixable Solhint issues
	@echo "Fixing linting issues in Solidity files..."
	@npx solhint $(SOL_FILES) --fix || yarn solhint $(SOL_FILES) --fix

slither: ## Run Slither security analysis
	@echo "Running Slither security analysis..."
	@slither . --config-file slither.config.json

4naly3er: ## Generate smart contract audit report with 4naly3er
	@echo "Ensuring script is executable..."
	@chmod +x script/generate_4naly3er_report.sh
	@echo "Generating audit report..."
	@./script/generate_4naly3er_report.sh
