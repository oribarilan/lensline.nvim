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
local current_file = nil

local function safe_call(fn)
  if not fn then return true end
  return xpcall(fn, debug.traceback)
end

local function run_case(suite, case)
  -- before_each hooks
  for _, hook in ipairs(suite.before_each) do
    local okb, errb = safe_call(hook)
    if not okb then
      case.failed = true
      results.total = results.total + 1
      results.failed = results.failed + 1
      table.insert(results.failures, {
        suite = suite.name,
        name = case.name .. " (before_each)",
        err = errb,
        file = suite.file,
      })
      return
    end
  end

  local ok, err = xpcall(case.fn, debug.traceback)
  results.total = results.total + 1
  if not ok then
    case.failed = true
    results.failed = results.failed + 1
    table.insert(results.failures, {
      suite = suite.name,
      name = case.name,
      err = err,
      file = suite.file,
    })
  end

  -- after_each hooks
  for _, hook in ipairs(suite.after_each) do
    local oka, erra = safe_call(hook)
    if not oka then
      case.failed = true
      results.failed = results.failed + 1
      table.insert(results.failures, {
        suite = suite.name,
        name = case.name .. " (after_each)",
        err = erra,
        file = suite.file,
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
    file = current_file,
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
  table.insert(current_suite.cases, { name = name, fn = fn, failed = false })
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

local function compute_file_stats()
  local file_stats = {}
  for _, s in ipairs(suites) do
    local fname = s.file or "<unknown>"
    local stat = file_stats[fname]
    if not stat then
      stat = { total = 0, failed = 0 }
      file_stats[fname] = stat
    end
    for _, c in ipairs(s.cases) do
      stat.total = stat.total + 1
      if c.failed then stat.failed = stat.failed + 1 end
    end
  end
  return file_stats
end

local function print_file_stats(file_stats)
  local files = {}
  for f,_ in pairs(file_stats) do table.insert(files, f) end
  table.sort(files)
  for _, f in ipairs(files) do
    local st = file_stats[f]
    local passed = st.total - st.failed
    local status = (st.failed == 0) and "OK" or "FAIL"
    print(string.format("[tests:file] %s %d/%d passed (%s)", f, passed, st.total, status))
  end
end

function M.run()
  -- Discover and load spec files
  local files = vim.fn.globpath('tests/unit','**/*_spec.lua',0,1)
  table.sort(files)
  for _, f in ipairs(files) do
    current_file = f
    local okf, errf = pcall(dofile, f)
    current_file = nil
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

  -- Per-file stats
  local file_stats = compute_file_stats()
  print_file_stats(file_stats)

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