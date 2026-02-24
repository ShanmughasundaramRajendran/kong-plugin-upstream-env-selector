SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
.PHONY: help test test-integration test-pongo test-functional test-all lint npm-install package compose-up compose-up-redis compose-down seed-redis demo compose-build

PONGO ?= pongo
PONGO_KONG_IMAGE ?= kong/kong-gateway:latest
BASE_URL ?= http://localhost:8000
ROUTE_PATH ?= /api/orders

help:
	@echo "Targets:"
	@echo "  make test               - run unit tests (busted) via pongo"
	@echo "  make test-integration   - run integration tests via pongo (requires spec helpers http_server support)"
	@echo "  make test-pongo         - run unit + integration tests via pongo"
	@echo "  make test-functional    - run mocha functional tests against running local compose stack"
	@echo "  make test-all           - run pongo tests, then mocha functional tests"
	@echo "  make lint               - basic Lua lint (luacheck) via pongo if available"
	@echo "  make npm-install        - install Node.js dev dependencies for mocha tests"
	@echo "  make package            - build distributable zip"
	@echo "  make compose-build      - build local Kong image (Kong latest + lua-resty-redis)"
	@echo "  make compose-up         - start local demo with docker-compose (static mode)"
	@echo "  make compose-up-redis   - start local demo with docker-compose (redis mode)"
	@echo "  make compose-down       - stop local demo"
	@echo "  make seed-redis         - seed redis keys for redis mode demo"
	@echo "  make demo               - run a few curl requests against local demo"
	@echo ""
	@echo "Environment overrides:"
	@echo "  PONGO_KONG_IMAGE=kong/kong-gateway:latest (default, used by test/lint targets)"
	@echo ""

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

npm-install:
	@npm install

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

package:
	@rm -f kong-plugin-upstream-env-selector_complete.zip
	@zip -r kong-plugin-upstream-env-selector_complete.zip kong spec rockspecs examples .github docker-compose.yml Makefile Dockerfile package.json test bruno -x "*.DS_Store"
	@echo "Created kong-plugin-upstream-env-selector_complete.zip"

compose-up:
	@echo "Starting docker-compose (static mapping) ..."
	@cp -f examples/declarative/kong.yml examples/declarative/kong_active.yml
	@docker compose up -d
	@echo "Kong proxy: http://localhost:8000  admin: http://localhost:8001"

compose-up-redis:
	@echo "Starting docker-compose (redis mapping) ..."
	@cp -f examples/declarative/kong_redis.yml examples/declarative/kong_active.yml
	@docker compose up -d
	@echo "Kong proxy: http://localhost:8000  admin: http://localhost:8001"
	@echo "Now run: make seed-redis"

compose-down:
	@docker compose down -v --remove-orphans

seed-redis:
	@examples/scripts/seed_redis.sh

demo:
	@examples/scripts/test_requests.sh

compose-build:
	@docker compose build
