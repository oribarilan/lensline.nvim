# Minimal test harness (local LuaRocks tree in .rocks + custom runner)
NVIM ?= nvim
TEST_DIR := $(shell pwd)/tests/unit
ROCKS_TREE := .rocks
LUA_VERSION := 5.1
DOCKER_TEST_IMAGE := lensline-tests
# Force architecture to match Neovim prebuilt tarball (linux64 = x86_64)
DOCKER_PLATFORM ?= linux/amd64

.PHONY: test
test:
	@eval "$$(luarocks --lua-version=$(LUA_VERSION) --tree ./$(ROCKS_TREE) path)" \
	  && $(NVIM) --headless -u tests/minimal_init.lua \
	    -c "lua require('lensline.test_runner').run()" \
	  || { echo '[test] failures'; exit 1; }

.PHONY: d-test
d-test:
	@echo "[docker] Building test image $(DOCKER_TEST_IMAGE) for $(DOCKER_PLATFORM)"
	@docker buildx build --platform $(DOCKER_PLATFORM) -f Dockerfile.test -t $(DOCKER_TEST_IMAGE) .
	@echo "[docker] Running test container on $(DOCKER_PLATFORM)"
	@docker run --rm --platform $(DOCKER_PLATFORM) $(DOCKER_TEST_IMAGE)

.PHONY: clean-rocks
clean-rocks:
	@rm -rf ./$(ROCKS_TREE)
	@echo "[clean-rocks] Removed local rocks tree ./$(ROCKS_TREE)"