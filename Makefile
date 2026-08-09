# Makefile for the zweig project

# Variables
SHELL := /bin/bash


# Targets
.PHONY: all install_deps test lint prepare help docker-build docker-run

all: install_deps ## Default target (installs deps)

prepare: ## Install commit-msg hook (uvx pre-commit)
	uvx pre-commit install --hook-type commit-msg

install_deps: ## Install basher deps from ./deps
	@if ! command -v basher >/dev/null 2>&1; then \
		echo "basher could not be found. Install:"; \
		echo "  curl -s https://raw.githubusercontent.com/basherpm/basher/master/install.sh | bash"; \
		exit 1; \
	fi
	@if [ -s deps ]; then \
		echo "Installing basher deps..."; \
		xargs -r basher install < deps; \
	else \
		echo "No deps file or empty; skipping basher install."; \
	fi

test: install_deps ## Run test suite
	@./tests/run_tests.sh

smoke: ## Run smoke tests
	bash tests/smoke.sh

lint: ## Run shellcheck
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "shellcheck not installed. On macOS: brew install shellcheck; on Ubuntu: sudo apt-get install -y shellcheck."; \
		exit 1; \
	fi
	@echo "Running shellcheck..."
	@shellcheck $$(git ls-files '*.sh') bin/zg
	@echo "Shellcheck passed."

docker-build: ## Build the Docker image for zweig-e2e
	@echo "Building Docker image 'zweig-e2e'..."
	docker build -t zweig-e2e .

docker-run: ## Run Docker container interactively (mount .gitconfig and test repo)
	@echo "Running Docker container from image 'zweig-e2e' with volume mounts..."
	docker run -it \
	  -v ~/.gitconfig:/home/zweig/.gitconfig \
	  -v $(PWD)/.test-repo:/app/test-repo \
	  zweig-e2e



# Self-documenting help. Prints targets and their descriptions.
.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_.-]+:.*##/ {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)