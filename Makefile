# Minimal test harness (requires busted installed; optional local install via `make deps`)
NVIM ?= nvim
TEST_DIR := tests/unit
ROCKS_TREE := .rocks
LUA_VERSION := 5.1

.PHONY: test
test:
	@$(NVIM) --headless -u tests/minimal_init.lua -c "lua require('busted.runner')({ paths={'$(TEST_DIR)'}, standalone=true })" +qall || { echo '[test] failures'; exit 1; }