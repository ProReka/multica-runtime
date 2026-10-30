# Multica Runtime — developer tasks.
#
# Docker is never required to lint or test the description of the images; the
# heavy lifting happens in GitHub Actions. `make build` and `make test` are for
# contributors who explicitly want a local image.

SHELL := /bin/bash
.DEFAULT_GOAL := help

VARIANTS ?= base,node,python,php,go,flutter,devops,qa,design,autoscaler
IMAGE_PREFIX ?= multica-runtime
PYTHON ?= python3

.PHONY: help lint test-versions test-python test-shell test-runtime build test push docs docs-build clean

help: ## Show this help
	@printf 'Multica Runtime\n\n'
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf '\nVariables: VARIANTS=%s IMAGE_PREFIX=%s\n' "$(VARIANTS)" "$(IMAGE_PREFIX)"
	@printf 'CI builds and publishes images; local Docker is optional.\n'

lint: test-versions test-python test-shell ## Run every check that needs no Docker
	@printf '\nAll lint checks passed.\n'

test-versions: ## Verify versions.env is well-formed and every ARG is supplied
	@scripts/check-versions.sh

test-python: ## Run the autoscaler unit tests
	@cd autoscaler && $(PYTHON) -m unittest -v

test-shell: ## Syntax-check and (when installed) shellcheck every shell script
	@set -e; for f in $$(find . -path ./.git -prune -o -name '*.sh' -print); do bash -n "$$f"; done
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck --severity=warning $$(find . -path ./.git -prune -o -name '*.sh' -print); \
	else \
		echo "shellcheck not installed; skipping (CI runs it)"; \
	fi
	@bash scripts/test-worktrees.sh
	@$(PYTHON) scripts/test-ci-plan.py
	@$(PYTHON) scripts/test-ci-release.py
	@$(PYTHON) scripts/test-checkout-recovery.py
	@printf 'Shell scripts OK.\n'

build: ## Build images locally (VARIANTS=base,node,...)
	@VARIANTS=$(VARIANTS) scripts/build.sh

test: ## Smoke-test locally built images (VARIANTS=base,node,...)
	@IMAGE_PREFIX=$(IMAGE_PREFIX) scripts/test-image.sh $$(echo $(VARIANTS) | tr ',' ' ')

test-runtime: ## Start variant services locally (VARIANT=php|design, needs Docker)
	@IMAGE=$(IMAGE_PREFIX):$(VARIANT) scripts/test-runtime.sh $(VARIANT)

push: ## Build and push multi-arch images (PUSH=1)
	@PUSH=1 VARIANTS=$(VARIANTS) scripts/build.sh

docs: ## Serve the documentation locally
	@command -v mkdocs >/dev/null 2>&1 || { echo "pip install -r docs/requirements.txt"; exit 1; }
	@mkdocs serve

docs-build: ## Build the documentation once
	@command -v mkdocs >/dev/null 2>&1 || { echo "pip install -r docs/requirements.txt"; exit 1; }
	@mkdocs build --strict

clean: ## Remove local caches (never touches Docker images)
	@find . -name '__pycache__' -type d -prune -exec rm -rf {} +
	@rm -rf site
	@printf 'Caches removed.\n'
