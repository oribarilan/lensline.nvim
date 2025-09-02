# testing guidelines (simple, reliable, low‑maintenance)

this doc explains how to write new tests that are stable, clear, and easy to keep green over time. it assumes lua + busted + plenary in a headless neovim.

## goals
- test the **public behavior**, not private internals
- keep tests **deterministic** (no flaky time/race/randomness)
- keep tests **fast** (finish in seconds, not minutes)
- keep tests **small and local** (each spec owns its setup, no hidden magic)
- failures must be **actionable** (a failing message tells you what to fix)

---

## quick setup (suggested layout)

```
tests/
  minimal_init.lua
  helpers/
    await.lua
    fake_time.lua
    tmp.lua
    git_repo.lua
  unit/
    test_utils_spec.lua
  integration/
    test_renderer_spec.lua
```

minimal `tests/minimal_init.lua` template (headless, hermetic env):

```lua
-- run with: nvim --headless -u tests/minimal_init.lua -c "lua require('busted').run()"
vim.opt.shadafile = "NONE"
vim.opt.shada = ""
vim.opt.runtimepath:append(vim.fn.getcwd())
vim.g.mapleader = " "

-- stable env
vim.env.TZ = "UTC"
vim.env.LANG = "C.UTF-8"

-- seed rng for deterministic tests
math.randomseed(123456); for _=1,3 do math.random() end

-- ensure plenary is on rtp (adjust path as needed)
-- vim.opt.runtimepath:append(vim.fn.getcwd() .. "/.deps/plenary") -- if vendored

-- expose busted
package.preload["busted"] = function()
  return require("plenary.busted")
end
```

> keep `minimal_init.lua` tiny. add helpers under `tests/helpers/`, not here.

---

## how to write good tests

### 1) test the contract, not the guts
- prefer assertions on **results** and **side effects** that users rely on
- avoid asserting on internal fields, iteration order, or incidental formatting
- example: “renderer adds 1 extmark at line x with label y” is good; “renderer called `ns_id = 42`” is brittle

### 2) unit first, integration second
- **unit tests**: pure lua logic (formatting, diffing, data transforms). no neovim api, no filesystem. fast and cheap.
- **integration tests**: thin seams where we touch neovim api, filesystem, or git. keep the scenario small and observable.

### 3) small helpers, repeated everywhere
put tiny helpers in `tests/helpers/` and use them across specs.

`tests/helpers/await.lua` (condition > fixed sleep):

```lua
local M = {}
function M.await(pred, timeout_ms, step_ms)
  local uv = vim.uv or vim.loop
  local start = uv.now()
  timeout_ms = timeout_ms or 200
  step_ms = step_ms or 5
  while (uv.now() - start) < timeout_ms do
    if pred() then return true end
    vim.wait(step_ms)
  end
  return false
end
return M
```

`tests/helpers/fake_time.lua` (clock you can advance):

```lua
local T = { t = 0 }
function T:now() return self.t end
function T:advance(ms) self.t = self.t + ms end
function T:sleep(ms) self:advance(ms) end
return T
```

`tests/helpers/tmp.lua` (per-spec temp dirs, auto-clean suggested):

```lua
local Path = require("plenary.path")
local M = {}
local root = vim.fn.stdpath("data") .. "/tests-tmp"
vim.fn.mkdir(root, "p")
function M.mktd(prefix)
  local uv = vim.uv or vim.loop
  local dir = string.format("%s/%s_%d", root, prefix or "case", uv.now())
  vim.fn.mkdir(dir, "p"); return dir
end
function M.rmrf(dir) if dir then Path:new(dir):rmdir({ recursive = true }) end end
return M
```

`tests/helpers/git_repo.lua` (deterministic git fixture):

```lua
local M = {}
local function sh(cmd, cwd)
  local opts = cwd and { cwd = cwd } or nil
  local out = vim.fn.system(cmd, opts)
  assert(vim.v.shell_error == 0, (table.concat(cmd, " ") .. " -> " .. out))
  return out
end
function M.make(dir)
  sh({ "git", "init" }, dir)
  sh({ "git", "config", "user.email", "dev@example.com" }, dir)
  sh({ "git", "config", "user.name", "dev" }, dir)
  local env = "GIT_AUTHOR_DATE=2001-01-01T00:00:00Z GIT_COMMITTER_DATE=2001-01-01T00:00:00Z "
  sh({ "bash", "-lc", env .. "echo hello > a.lua && git add a.lua && git commit -m init" }, dir)
  sh({ "bash", "-lc", env .. "echo world >> a.lua && git commit -am update" }, dir)
  return dir
end
return M
```

### 4) patterns that kill flakes (use these by default)
- **never** use blind sleeps; use `await(predicate)` or explicit events (autocmds, callbacks)
- **seed randomness** once in `minimal_init.lua`; avoid asserting on random values
- **use per-test tmp dirs** and clean them in `after_each`
- **freeze the clock** by injecting a clock dependency (when code cares about time)
- **reset module state** between specs when singletons/caches exist:
  ```lua
  local function reset_modules()
    for name,_ in pairs(package.loaded) do
      if name:match("^lensline") then package.loaded[name] = nil end
    end
  end
  before_each(reset_modules); after_each(reset_modules)
  ```
- **pin env**: set `TZ=UTC`, `LANG=C.UTF-8`
- **deterministic git**: use the `git_repo` helper; don’t rely on host git config

### 5) table-driven tests (cheap scale)
write many small cases with the same structure:

```lua
describe("utils.trim", function()
  local trim = require("lensline.utils").trim
  for _,tc in ipairs({
    { "hello",       "hello" },
    { " hello ",     "hello" },
    { "\thello\n",   "hello" },
  }) do
    it(("trims %q"):format(tc[1]), function()
      assert.equals(tc[2], trim(tc[1]))
    end)
  end
end)
```

### 6) neovim integration test example (tiny and observable)

```lua
local await = require("tests.helpers.await").await

describe("renderer inserts extmarks", function()
  local ns
  before_each(function()
    ns = vim.api.nvim_create_namespace("test")
  end)

  it("adds a label on line 1", function()
    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "function foo()" })
    -- act: call your entrypoint that renders
    require("lensline.renderer").render(buf, ns, { label = "x" })

    -- assert: wait until extmark appears (no blind sleep)
    local ok = await(function()
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
      return #marks == 1 and marks[1][4].virt_text and marks[1][4].virt_text[1][1] == "x"
    end, 200)
    assert.is_true(ok, "expected 1 extmark with label x")
  end)
end)
```

---

## when to mock vs integrate

- mock **small, pure** dependencies when they make a unit test simpler (e.g., inject a fake clock or rng).  
- prefer **real** integration for neovim api calls (we’re already in headless nvim). keep the scenario tiny.  
- avoid deep stubs of the neovim api; test through the public surface instead.

---

## assertions that age well
- assert on **shape and invariants** (counts, presence, ids) rather than exact byte-for-byte render unless formatting is the product
- if using golden files, keep them short and stable; update only with a clear reason; store alongside the spec
- failure messages should say **what was expected and why it matters**

---

## performance and reliability
- keep specs **short**; prefer many tiny tests over one huge scenario
- run with `--shuffle` locally to catch order dependence early
- avoid global side effects; if unavoidable, **reset** them in `after_each`
- aim for **< 5s** total on a dev machine for fast feedback

---

## naming and structure
- file names: `test_*.lua` or `*_spec.lua`
- group by product area: `tests/unit/providers/...`, `tests/integration/renderer/...`
- test names should read like a sentence: `it("adds a label on line 1", function() ... end)`

---

## ci (minimal and boring)
- run on ubuntu with two neovim versions you support (e.g., `0.10.x` and `nightly`)
- set `TZ=UTC`, `LANG=C.UTF-8`
- command should be the same as local: `nvim --headless -u tests/minimal_init.lua -c "lua require('busted').run()"`

example job step (github actions):

```yaml
- uses: rhysd/action-setup-vim@v1
  with:
    neovim: true
    version: "0.10.2"
- run: |
    luarocks install busted
    nvim --headless -u tests/minimal_init.lua -c "lua require('busted').run()"
  env:
    TZ: "UTC"
    LANG: "C.UTF-8"
```

---

## checklist for every new test
- [ ] tests a **public** behavior
- [ ] **no blind sleeps** (uses `await` or events)
- [ ] **no randomness** without a seeded/injected rng
- [ ] uses its **own tmp dir** and cleans up
- [ ] passes with `--shuffle`
- [ ] failure message is clear and useful

---

## final notes
- keep helpers tiny and boring; resist adding a clever framework around tests
- prefer incremental improvements; when a test flakes, simplify the scenario and add the missing helper or reset step
- if a test is hard to write, the code may need a seam (e.g., allow passing `time` or `rng`). small seams make code more testable without leaking internals
