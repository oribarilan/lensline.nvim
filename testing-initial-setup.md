# Testing — Initial Setup (Neovim + Plenary + Docker)

This doc gets you from zero to a repeatable, Dockerized test rig for a Neovim plugin using **[plenary.nvim](https://github.com/nvim-lua/plenary.nvim)**.

---

## Goals

- Same test command locally and in CI
- Hermetic, fast, deterministic runs
- Minimal Neovim runtime (no user config leakage)

---

## Stack Overview

- **Neovim**: run in `--headless` mode
- **plenary.nvim**: test runner (`plenary.busted`), async helpers
- **Docker**: pins toolchain + deps
- **Makefile**: one-liners you reuse locally/CI
- *(Optional)* `luacov` for coverage

---

## Repo Layout (suggested)

```
.
├── lua/
│   └── <your_plugin>/...
├── tests/
│   ├── unit/                  # pure Lua / API boundary tests
│   ├── integration/           # exercises Neovim APIs + your plugin
│   ├── e2e/                   # launch real nvim and simulate usage
│   ├── fixtures/              # sample files, golden outputs, etc.
│   ├── helpers/               # test utils (spawn nvim, waiters, etc.)
│   └── minimal_init.lua       # minimal runtime for test env
├── Dockerfile.test
├── Makefile
└── .github/workflows/ci.yml
```

Keep tests small and named after the behavior under test.

---

## Minimal Neovim Runtime for Tests

Create `tests/minimal_init.lua` to force a hermetic runtime:

```lua
-- tests/minimal_init.lua
-- Keep this file tiny and deterministic.

-- Disable native plugins & user config
vim.opt.runtimepath = vim.env.VIMRUNTIME .. "," .. vim.fn.getcwd()
vim.g.loaded_matchparen = 1
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Add plugin under test + plenary to runtimepath
local root = vim.fn.getcwd()
vim.opt.runtimepath:append(root)                  -- your plugin
vim.opt.runtimepath:append(root .. "/.deps/plenary") -- vendored plenary (or use a plugin manager below)

-- If you prefer Lazy to pull deps in tests, do something like:
-- local lazypath = root .. "/.deps/lazy/lazy.nvim"
-- vim.opt.runtimepath:append(lazypath)
-- require("lazy").setup({
--   { "nvim-lua/plenary.nvim" },
--   { dir = root }, -- your plugin
-- }, {
--   root = root .. "/.deps/lazy",
-- })
```

> Pin plenary with a specific commit or vendor it to `.deps/plenary` for stability.

---

## Makefile targets

```makefile
.PHONY: test
test:
	@nvim --headless -u tests/minimal_init.lua \
	  -c "lua require('plenary.busted').run({ \
	        minimal_init = 'tests/minimal_init.lua', \
	        output = 'nvim', \
	        paths = { 'tests/unit', 'tests/integration' }, \
	      })" +qall

.PHONY: test-e2e
test-e2e:
	@nvim --headless -u tests/minimal_init.lua \
	  -c "lua require('plenary.busted').run({ \
	        minimal_init = 'tests/minimal_init.lua', \
	        output = 'nvim', \
	        paths = { 'tests/e2e' }, \
	      })" +qall

.PHONY: coverage
coverage:
	@COVERAGE=1 nvim --headless -u tests/minimal_init.lua \
	  -c "lua require('plenary.busted').run({ \
	        minimal_init = 'tests/minimal_init.lua', \
	        output = 'nvim', \
	      })" +qall || true
	@luacov && luacov-console -s
```

---

## Dockerfile

`Dockerfile.test` (Ubuntu-based; pin to reduce drift):

```dockerfile
FROM ubuntu:22.04

# 1) Base tools
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl git ca-certificates build-essential pkg-config libstdc++6 \
    neovim lua5.1 luarocks \
 && rm -rf /var/lib/apt/lists/*

# 2) Optional: install luacheck/luacov
RUN luarocks install luacheck && luarocks install luacov && luarocks install luacov-console

# 3) Workspace
WORKDIR /workspace
COPY . /workspace

# 4) Vendor plenary (or use a manager)
RUN mkdir -p .deps && \
    git clone --depth=1 https://github.com/nvim-lua/plenary.nvim .deps/plenary

# 5) Default command: run tests
CMD ["bash", "-lc", "make test"]
```

Build & run:

```bash
docker build -f Dockerfile.test -t myplugin-tests .
docker run --rm -it myplugin-tests
```

---

## CI (GitHub Actions)

`.github/workflows/ci.yml`

```yaml
name: tests

on:
  push:
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build test image
        run: docker build -f Dockerfile.test -t myplugin-tests .
      - name: Run tests
        run: docker run --rm myplugin-tests
```

This keeps local and CI environments identical.

---

## Commands Recap

```bash
# Local (host has nvim installed)
make test
make test-e2e
make coverage  # optional

# Docker
docker build -f Dockerfile.test -t myplugin-tests .
docker run --rm -it myplugin-tests
```

Done. You now have a reproducible test harness.
