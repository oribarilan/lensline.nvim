# Testing — Ongoing Guidelines (Plenary Best Practices)

This doc explains **how to write** new tests well, now that the setup is in place (see *Testing — Initial Setup*). It uses **plenary.nvim** as the test framework and assumes the minimal runtime from setup.

---

## What to Test (and where)

- **Unit** (`tests/unit/`): Pure Lua logic, no timers, no Neovim IO where possible.
- **Integration** (`tests/integration/`): Real Neovim API calls (`vim.api`, autocmds, highlights). Small fixtures.
- **E2E** (`tests/e2e/`): Simulate a user flow end to end; keep these short and stable.

> Thumb rule: **80% unit/integration, 20% e2e**.

---

## Writing Tests with Plenary (Busted style)

Unit example:

```lua
local eq = assert.are.same
describe("path util", function()
  it("normalizes doubles and dots", function()
    local util = require("<your_plugin>.util")
    eq("a/b/c", util.normalize("a//b/./c"))
  end)
end)
```

Async / event-driven example:

```lua
local async = require("plenary.async")
local eq = assert.are.same

describe("api behavior", function()
  it("writes lines", async.tests(function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello", "world" })
    eq({ "hello", "world" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end))
end)
```

Use `plenary.async.util.await_schedule()` or `vim.wait()` around event boundaries. Avoid random sleeps.

---

## Isolation & Determinism

- Reset state between tests: clear created buffers, autocmds, highlights, augroups.
- Avoid hidden globals; keep helpers in `tests/helpers/`.
- Use temp dirs for file fixtures (`plenary.path`, `vim.loop.fs_*`).
- Seed randomness if any: `math.randomseed(1234)` in `minimal_init.lua` (guard it if needed).
- Pin all external deps (Neovim, plenary, plugin manager) for CI stability.

---

## Fixtures & Golden Files

- Keep fixtures tiny and focused under `tests/fixtures/`.
- Golden outputs: compare stable strings/files. Re-generate only when behavior changes *intentionally*—guard regeneration behind an env var.
- Prefer deterministic formatting to reduce diffs (strip trailing spaces, normalize newlines).

---

## Mocking Strategy

- Test via public API first. Only mock when you **must** (e.g., OS, time, git).
- For `vim.api` heavy code, create thin adapters and mock those in unit tests, then cover the adapter with integration tests.
- For timers/schedulers, prefer awaiting events over stubbing time. If needed, stub `vim.loop.now()` in a local scope.

---

## Performance Budgets (Optional but useful)

- Add `tests/perf/` with small micro-benchmarks (e.g., init under 10ms for a 1k-line file).
- Fail CI if budgets exceed known thresholds. Keep margins — perf tests can be noisy.

---

## Coverage (Optional)

Integrate `luacov`:

- In `tests/minimal_init.lua`:
  ```lua
  if os.getenv("COVERAGE") == "1" then
    require("luacov")
  end
  ```
- Run via `make coverage` (see setup doc) and review `luacov.report.out` / console summary.
- Target **trend** improvements; don’t chase 100% blindly.

---

## Naming, Structure, Readability

- Test file naming: all Lua test files MUST start with `test_` and end with `_spec.lua` (e.g. `tests/unit/test_feature_x_spec.lua`). This keeps globbing predictable and visually groups tests. Avoid other prefixes.
- One behavior per `it(...)`. Clear wording: `"does X when Y"`.
- Keep assertions few and relevant. The first failure should tell the story.
- Prefer small helpers over copy/paste (put them in `tests/helpers/`).
- Limit e2e assertions to smoke-level checks; detailed logic belongs in unit/integration.

---

## Common Pitfalls

- Leaking user config or unpinned deps (flaky tests).
- Arbitrary sleeps (use events/awaits).
- Big fixtures or too many e2e tests (slow CI).
- Global state bleed (not cleaning up autocmds/buffers).
- Over-mocking: tests become tautologies.

---

## Checklist for New Features

- [ ] Unit tests cover core logic (happy + one failure path).
- [ ] Integration tests hit real Neovim APIs touched by the feature.
- [ ] E2E test exercises a realistic user flow (1–3 assertions).
- [ ] Fixtures are small and live under `tests/fixtures/`.
- [ ] No arbitrary sleeps; event waits are explicit.
- [ ] State is reset (buffers/autocmds/highlights) after each test.
- [ ] Versions pinned; test passes locally and in Docker.
- [ ] Optional: coverage checked, perf budget respected.

---

## Quick Commands (for day-to-day)

```bash
# run unit + integration fast
make test

# run e2e only (when changing UX flows)
make test-e2e

# before merging a heavy change
docker build -f Dockerfile.test -t myplugin-tests . && docker run --rm myplugin-tests

# coverage snapshot (optional)
make coverage
```

Keep it boring, keep it green.  Small reliable tests beat clever ones.
