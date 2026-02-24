SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help npm-install test test-integration test-pongo test-functional test-all \
	lint compose-build compose-up compose-down clean demo package

PONGO ?= pongo
PONGO_KONG_IMAGE ?= kong/kong-gateway:latest
BASE_URL ?= http://localhost:8000
ROUTE_PATH ?= /api/orders

help:
	@echo "Targets:"
	@echo "  make compose-build      Build local Kong image"
	@echo "  make compose-up         Start local docker stack"
	@echo "  make compose-down       Stop and remove local docker stack"
	@echo "  make clean              Remove local stack and local built image"
	@echo "  make demo               Run sample curl scenarios"
	@echo "  make npm-install        Install Node dependencies for Mocha"
	@echo "  make test               Run Pongo unit tests"
	@echo "  make test-integration   Run Pongo integration tests"
	@echo "  make test-pongo         Run unit + integration tests"
	@echo "  make test-functional    Run Mocha functional tests"
	@echo "  make test-all           Run Pongo and Mocha suites"
	@echo "  make lint               Run luacheck in Pongo image if available"
	@echo "  make package            Build zip package"
	@echo ""
	@echo "Environment overrides:"
	@echo "  PONGO_KONG_IMAGE=kong/kong-gateway:latest"
	@echo "  BASE_URL=http://localhost:8000"
	@echo "  ROUTE_PATH=/api/orders"
	@echo ""

npm-install:
	@npm install

test:
	@KONG_IMAGE=$(PONGO_KONG_IMAGE) $(PONGO) run -- -v spec/unit

test-integration:
	@KONG_IMAGE=$(PONGO_KONG_IMAGE) $(PONGO) run -- -v spec/integration

test-pongo:
	@$(MAKE) test
	@$(MAKE) test-integration

lint:
	@echo "Running luacheck if present in pongo image..."
	-@KONG_IMAGE=$(PONGO_KONG_IMAGE) $(PONGO) run -- luacheck kong/plugins/upstream-env-selector

test-functional:
	@echo "Waiting for Kong proxy readiness..."
	@for i in $$(seq 1 30); do \
		if curl -fsS "$(BASE_URL)" >/dev/null 2>&1; then \
			break; \
		fi; \
		sleep 1; \
	done
	@BASE_URL=$(BASE_URL) ROUTE_PATH=$(ROUTE_PATH) npm run test:functional

test-all:
	@$(MAKE) test-pongo
	@$(MAKE) npm-install
	@$(MAKE) test-functional

compose-build:
	@docker compose build

compose-up:
	@echo "Starting docker-compose stack..."
	@docker compose up -d --build
	@echo "Kong proxy: http://localhost:8000  admin: http://localhost:8001"

compose-down:
	@docker compose down -v --remove-orphans

clean:
	@docker compose down -v --remove-orphans --rmi local
	-@$(PONGO) down

demo:
	@examples/scripts/test_requests.sh

package:
	@rm -f kong-plugin-upstream-env-selector_complete.zip
	@zip -r kong-plugin-upstream-env-selector_complete.zip kong spec rockspecs config .github docker-compose.yml Makefile Dockerfile package.json test bruno examples/scripts -x "*.DS_Store"
	@echo "Created kong-plugin-upstream-env-selector_complete.zip"
