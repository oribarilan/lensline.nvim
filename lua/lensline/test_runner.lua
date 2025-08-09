-- lensline.test_runner - minimal self-contained spec runner (no external busted needed)
local M = {}

local results = {
  total = 0,
  failed = 0,
  failures = {},
}

-- Simple DSL (single-level suites sufficient for current specs)
local current_suite = nil
local suites = {}

local function safe_call(fn)
  if not fn then return true end
  return xpcall(fn, debug.traceback)
end

local function run_case(suite, case)
  -- before_each hooks
  for _, hook in ipairs(suite.before_each) do
    local okb, errb = safe_call(hook)
    if not okb then
      results.total = results.total + 1
      results.failed = results.failed + 1
      table.insert(results.failures, {
        suite = suite.name,
        name = case.name .. " (before_each)",
        err = errb,
      })
      return
    end
  end

  local ok, err = xpcall(case.fn, debug.traceback)
  results.total = results.total + 1
  if not ok then
    results.failed = results.failed + 1
    table.insert(results.failures, {
      suite = suite.name,
      name = case.name,
      err = err,
    })
  end

  -- after_each hooks
  for _, hook in ipairs(suite.after_each) do
    local oka, erra = safe_call(hook)
    if not oka then
      results.failed = results.failed + 1
      table.insert(results.failures, {
        suite = suite.name,
        name = case.name .. " (after_each)",
        err = erra,
      })
    end
  end
end

local function run_suite(suite)
  for _, case in ipairs(suite.cases) do
    run_case(suite, case)
  end
end

-- DSL globals
_G.describe = function(name, body)
  local prev = current_suite
  local suite = {
    name = name,
    cases = {},
    before_each = {},
    after_each = {},
  }
  table.insert(suites, suite)
  current_suite = suite
  body()
  current_suite = prev
end

_G.it = function(name, fn)
  if not current_suite then
    error("it() called outside describe()")
  end
  table.insert(current_suite.cases, { name = name, fn = fn })
end

_G.before_each = function(fn)
  if not current_suite then
    error("before_each() called outside describe()")
  end
  table.insert(current_suite.before_each, fn)
end

_G.after_each = function(fn)
  if not current_suite then
    error("after_each() called outside describe()")
  end
  table.insert(current_suite.after_each, fn)
end

function M.run()
  -- Discover and load spec files
  local files = vim.fn.globpath('tests/unit','**/*_spec.lua',0,1)
  table.sort(files)
  for _, f in ipairs(files) do
    local okf, errf = pcall(dofile, f)
    if not okf then
      print('[spec load error]', f, errf)
      vim.cmd('cq 1')
      return
    end
  end

  -- Execute collected suites
  for _, s in ipairs(suites) do
    run_suite(s)
  end

  if results.failed > 0 then
    print(string.format('[tests] %d failed / %d total', results.failed, results.total))
    for i, fail in ipairs(results.failures) do
      print(string.format('  %d) %s :: %s', i, fail.suite, fail.name))
      print('     ' .. fail.err:gsub('\n', '\n     '))
    end
    vim.cmd('cq 1')
    return
  end

  print(string.format('[tests] all passed (%d)', results.total))
  vim.cmd('qa')
end

return M