# Makefile for the zweig project

SHELL := /bin/bash

.PHONY: all help check-basher check-shellcheck check-uvx check-docker \
        install_deps prepare test smoke lint docker-build docker-run

.DEFAULT_GOAL := help

help: ## Show this help
	@echo "Zweig - Developer Commands"
	@echo "==========================="
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_.-]+:.*##/ {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

all: install_deps ## Default target (installs deps)

check-basher: ## Verify basher is installed
	@if ! command -v basher >/dev/null 2>&1; then \
		echo "Error: 'basher' is not installed or not in PATH."; \
		echo "  Install: curl -s https://raw.githubusercontent.com/basherpm/basher/master/install.sh | bash"; \
		exit 1; \
	fi

check-shellcheck: ## Verify shellcheck is installed
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "Error: 'shellcheck' is not installed or not in PATH."; \
		echo "  Install: brew install shellcheck (macOS) or apt-get install -y shellcheck (Ubuntu)."; \
		exit 1; \
	fi

check-uvx: ## Verify uvx is installed
	@if ! command -v uvx >/dev/null 2>&1; then \
		echo "Error: 'uvx' is not installed or not in PATH."; \
		echo "  Install: https://docs.astral.sh/uv/getting-started/installation/"; \
		exit 1; \
	fi

check-docker: ## Verify docker is installed
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "Error: 'docker' is not installed or not in PATH."; \
		exit 1; \
	fi

prepare: check-uvx ## Install commit-msg hook (uvx pre-commit)
	uvx pre-commit install --hook-type commit-msg

install_deps: check-basher ## Install basher deps from ./deps
	@if [ -s deps ]; then \
		echo "Installing basher deps..."; \
		xargs -r basher install < deps; \
	else \
		echo "No deps file or empty; skipping basher install."; \
	fi

test: ## Run test suite
	@./tests/run_tests.sh

smoke: ## Run smoke tests
	bash tests/smoke.sh

lint: check-shellcheck ## Run shellcheck
	@echo "Running shellcheck..."
	@shellcheck $$(git ls-files '*.sh') bin/zg
	@echo "Shellcheck passed."

docker-build: check-docker ## Build the Docker image for zweig-e2e
	@echo "Building Docker image 'zweig-e2e'..."
	docker build -t zweig-e2e .

docker-run: check-docker ## Run Docker container interactively (mount .gitconfig and test repo)
	@echo "Running Docker container from image 'zweig-e2e' with volume mounts..."
	docker run -it \
	  -v ~/.gitconfig:/home/zweig/.gitconfig \
	  -v $(PWD)/.test-repo:/app/test-repo \
	  zweig-e2e
