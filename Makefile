# Minimal test harness (local LuaRocks tree in .rocks + busted for Lua 5.1 / Neovim LuaJIT)
NVIM ?= nvim
TEST_DIR := $(shell pwd)/tests/unit
ROCKS_TREE := .rocks
LUA_VERSION := 5.1
DOCKER_TEST_IMAGE := lensline-tests


.PHONY: test
test:
	@eval "$$(luarocks --lua-version=$(LUA_VERSION) --tree ./$(ROCKS_TREE) path)" \
	  && $(NVIM) --headless -u tests/minimal_init.lua \
	    -c "lua require('lensline.test_runner').run()" \
	  || { echo '[test] failures'; exit 1; }

.PHONY: d-test
d-test:
	@echo "[docker] Building test image $(DOCKER_TEST_IMAGE)"
	@docker build -f Dockerfile.test -t $(DOCKER_TEST_IMAGE) .
	@echo "[docker] Running test container"
	@docker run --rm $(DOCKER_TEST_IMAGE)

.PHONY: clean-rocks
clean-rocks:
	@rm -rf ./$(ROCKS_TREE)
	@echo "[clean-rocks] Removed local rocks tree ./$(ROCKS_TREE)"