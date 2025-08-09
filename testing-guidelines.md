# Testing Guidelines (busted-only)

Single lightweight harness using Neovim headless + busted. No plenary, no Docker, no coverage by default.

## 1. Scope
- We keep only unit tests for now under `tests/unit/`
- Focus: deterministic, fast (<1s), no external network / git / LSP server spawning
- Future (optional): integration, e2e, coverage (outlined below)

## 2. Prerequisites
Use a LOCAL LuaRocks tree (isolated per repo).

Initial one‑time dependency install (or upgrade):
```bash
rm -rf ./.rocks
luarocks --lua-version=5.1 --tree ./.rocks install busted
```
(Installs busted and its deps into an isolated `./.rocks` tree – ignored by git)

Ensure `nvim` is on PATH (Neovim 0.8+).

## 3. Run Tests
Standard:
```bash
make test
```
(Automatically evals LuaRocks env from `./.rocks` then launches Neovim headless)

First time (or after upgrading deps):
```bash
rm -rf ./.rocks
luarocks --lua-version=5.1 --tree ./.rocks install busted
make test
```

Underlying command (for reference only):
```
nvim --headless -u tests/minimal_init.lua -c "lua require('busted.runner')({ paths={'tests/unit'}, standalone=true })" +qall
```
See [Makefile](Makefile:1) and [tests/minimal_init.lua](tests/minimal_init.lua:1).

## 4. File Naming
All Lua test files MUST:
- start with: `test_`
- end with: `_spec.lua`

Example: `tests/unit/test_utils_spec.lua`

Rationale: predictable discovery & grouped listing.

## 5. Writing Tests
Pattern:
```lua
local eq = assert.are.same

describe("module.feature", function()
  it("does X when Y", function()
    local mod = require("lensline.utils")
    eq("expected", mod.some_call("input"))
  end)
end)
```

Guidelines:
- One focused behavior per `it(...)`.
- Assertions: minimal; failure message should be self-evident.
- Prefer table equality via `assert.are.same`.
- Avoid brittle timing; use `vim.wait(cond_timeout)` when needed (e.g., debounce).

## 6. Helpers / Stubbing
Use a tiny local helper instead of global utilities:
```lua
local function with_stub(mod, stub, fn)
  local orig = package.loaded[mod]
  package.loaded[mod] = stub
  local ok, err = pcall(fn)
  package.loaded[mod] = orig
  if not ok then error(err) end
end
```
Return original modules after test to prevent cross-test contamination.

When stubbing Neovim APIs (rare), restore them in `after_each`:
```lua
local orig = vim.lsp.buf_request
vim.lsp.buf_request = function(...) ... end
-- test
vim.lsp.buf_request = orig
```

## 7. Buffer Lifecycle
- Create scratch buffers: `vim.api.nvim_create_buf(false, true)`
- Always delete if still valid at test end to prevent handle leakage.

## 8. Adding New Test Cases
1. Identify public function / provider branch not covered.
2. Create (or extend) a describe block in an existing file if logically related.
3. Keep file size reasonable (< ~300 lines); create a new file if it grows beyond that.
4. Run `make test` and ensure green before commit.

## 9. LSP-related Tests
We do NOT start real language servers. Instead:
- Stub capability checks (`lensline.lens_explorer` methods)
- Stub `vim.lsp.buf_request` to synchronously invoke the handler with a fabricated result / error.

## 10. Style Checklist (Per PR)
- [ ] New/changed logic covered (happy path + one failure/edge)
- [ ] No sleeps (`vim.wait` only if truly needed)
- [ ] No persistent global state leakage
- [ ] Names follow `test_..._spec.lua`
- [ ] Fast (avoid large loops / heavy fixtures)

## 11. Future (Optional) Extensions (NOT enabled now)
These are intentionally deferred. If/when introduced, document them explicitly:
- Integration tests (`tests/integration/`) using real `vim.api` side effects
- E2E scenario tests (`tests/e2e/`) exercising user-facing flows
- Coverage (luacov) triggered via an env flag `COVERAGE=1`
- CI workflow file running `make test` across matrix of Neovim versions

## 12. Quick Reference
| Action | Command |
|--------|---------|
| Install/upgrade local deps | `rm -rf ./.rocks && luarocks --lua-version=5.1 --tree ./.rocks install busted` |
| Run all unit tests | `make test` |
| Run single file | `nvim --headless -u tests/minimal_init.lua -c "lua require('busted.runner')({ paths={'tests/unit/test_utils_spec.lua'}, standalone=true })" +qall` |
| Clean local rocks tree | `rm -rf ./.rocks` |

Keep it boring; keep it green.
