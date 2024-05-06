SHELL         = /usr/bin/env bash
SOURCE        = $(realpath $(dir $(realpath $(lastword $(MAKEFILE_LIST)))))
.SHELLFLAGS   = -eu -o pipefail -c
.DEFAULT_GOAL = help

# colors
BLACK         = $(shell tput -Txterm setaf 0)
RED           = $(shell tput -Txterm setaf 1)
GREEN         = $(shell tput -Txterm setaf 2)
YELLOW        = $(shell tput -Txterm setaf 3)
MAGENTA       = $(shell tput -Txterm setaf 5)
CYAN          = $(shell tput -Txterm setaf 6)
WHITE         = $(shell tput -Txterm setaf 7)
BLUE          = $(shell tput -Txterm setaf 4)
RESET         = $(shell tput -Txterm sgr0)

# log helper
define print_mod_start
	@echo "╭── $(1)"
endef
define print_mod
	@echo "│ • $(1)"
endef
define print_mod_end
	@echo "╰──────"
endef

DEV_FEEDKEYS=:e\n
DEV_ARGS=-l ./development/dev.lua 

help: ## help
	@echo "🔥 ${YELLOW}nvim${RESET}"
	@grep -E '^[a-zA-Z_0-9%-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "${BLUE}%-20s${RESET} %s\n", $$1, $$2}'
.PHONY: help

dev: ## watch
	@watchexec --stop-timeout=0 --no-process-group --ignore-nothing --stop-signal SIGKILL -e "lua,vim" -r -c clear "nvim -S ./development/bootstrap.lua $(DEV_ARGS)"
.PHONY: dev

test: ## run tests
	@./development/test.sh
.PHONY: test

test-watch: ## run tests (watch)
	@./development/test.sh --watch
.PHONY: test-watch

check: ## run luacheck
	@luacheck .
.PHONY: check

format: ## run stylua
	@stylua .
.PHONY: format
