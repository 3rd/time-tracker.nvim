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
DEV_EXTRA_ARGS=init.lua

help: ## help
	@echo "🔥 ${YELLOW}nvim${RESET}"
	@grep -E '^[a-zA-Z_0-9%-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "${BLUE}%-20s${RESET} %s\n", $$1, $$2}'
.PHONY: help

format: ## run stylua
	@stylua .
.PHONY: format
