# Minimal test harness (local LuaRocks tree in .rocks + busted for Lua 5.1 / Neovim LuaJIT)
NVIM ?= nvim
TEST_DIR := $(shell pwd)/tests/unit
ROCKS_TREE := .rocks
LUA_VERSION := 5.1


.PHONY: test
test:
	@eval "$$(luarocks --lua-version=$(LUA_VERSION) --tree ./$(ROCKS_TREE) path)" \
	  && $(NVIM) --headless -u tests/minimal_init.lua \
	    -c "lua require('lensline.test_runner').run()" \
	  || { echo '[test] failures'; exit 1; }

.PHONY: clean-rocks
clean-rocks:
	@rm -rf ./$(ROCKS_TREE)
	@echo "[clean-rocks] Removed local rocks tree ./$(ROCKS_TREE)"