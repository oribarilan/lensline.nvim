-- tests/unit/providers/test_diagnostics_spec.lua
-- unit tests for lensline.providers.diagnostics (diagnostic filtering and aggregation)

local eq = assert.are.same

describe("providers.diagnostics.handler", function()
  local provider = require("lensline.providers.diagnostics")
  local config = require("lensline.config")

  local function reset_modules()
    for name,_ in pairs(package.loaded) do
      if name:match("^lensline") then package.loaded[name] = nil end
    end
    provider = require("lensline.providers.diagnostics")
    config = require("lensline.config")
  end

  local function with_stub(mod, stub, fn)
    local orig = package.loaded[mod]
    package.loaded[mod] = stub
    local ok, err = pcall(fn)
    package.loaded[mod] = orig
    if not ok then error(err) end
  end

  local function with_diagnostics(list, fn)
    local orig = vim.diagnostic.get
    vim.diagnostic.get = function(_) return list end
    local ok, err = pcall(fn)
    vim.diagnostic.get = orig
    if not ok then error(err) end
  end

  local function call_handler(diagnostics, provider_config, expected_result)
    local func_info = { line = 1, end_line = 21, name = "test_function" }
    local result = "unset"
    local called = false

    with_stub("lensline.debug", { log_context = function() end }, function()
      with_stub("lensline.utils", { is_valid_buffer = function() return true end }, function()
        with_diagnostics(diagnostics, function()
          provider.handler(5, func_info, provider_config or {}, function(res)
            called = true
            result = res
          end)
        end)
      end)
    end)

    eq(true, called)
    eq(expected_result, result)
  end

  before_each(function()
    reset_modules()
    config.setup({ style = { use_nerdfont = false } }) -- predictable fallback letters
  end)

  after_each(function()
    reset_modules()
  end)

  it("returns nil when no diagnostics found", function()
    call_handler({}, {}, nil)
  end)

  -- table-driven tests for min_level filtering scenarios
  for _, case in ipairs({
    {
      name = "filters out warnings when min_level=ERROR",
      diagnostics = {
        { lnum = 2, col = 0, severity = vim.diagnostic.severity.WARN },
      },
      min_level = "ERROR",
      expected = nil
    },
    {
      name = "includes errors when min_level=ERROR",
      diagnostics = {
        { lnum = 1, col = 0, severity = vim.diagnostic.severity.ERROR },
        { lnum = 2, col = 0, severity = vim.diagnostic.severity.WARN },
      },
      min_level = "ERROR",
      expected = { line = 1, text = "1E" }
    },
    {
      name = "includes warnings when min_level=WARN",
      diagnostics = {
        { lnum = 1, col = 0, severity = vim.diagnostic.severity.ERROR },
        { lnum = 3, col = 1, severity = vim.diagnostic.severity.ERROR },
        { lnum = 4, col = 2, severity = vim.diagnostic.severity.WARN },
        { lnum = 5, col = 0, severity = vim.diagnostic.severity.INFO }, -- filtered out
        { lnum = 6, col = 0, severity = vim.diagnostic.severity.HINT }, -- filtered out
      },
      min_level = "WARN",
      expected = { line = 1, text = "2E" } -- shows count of highest severity (ERROR=2)
    },
    {
      name = "includes info when min_level=INFO",
      diagnostics = {
        { lnum = 1, col = 0, severity = vim.diagnostic.severity.ERROR },
        { lnum = 2, col = 0, severity = vim.diagnostic.severity.WARN },
        { lnum = 3, col = 0, severity = vim.diagnostic.severity.WARN },
        { lnum = 4, col = 0, severity = vim.diagnostic.severity.INFO },
        { lnum = 7, col = 0, severity = vim.diagnostic.severity.HINT }, -- filtered out
      },
      min_level = vim.diagnostic.severity.INFO, -- numeric version
      expected = { line = 1, text = "1E" } -- shows count of highest severity (ERROR=1)
    },
  }) do
    it(("diagnostic filtering: %s"):format(case.name), function()
      call_handler(case.diagnostics, { min_level = case.min_level }, case.expected)
    end)
  end

  -- table-driven tests for aggregation scenarios
  for _, case in ipairs({
    {
      name = "prioritizes errors over warnings",
      diagnostics = {
        { lnum = 1, col = 0, severity = vim.diagnostic.severity.WARN },
        { lnum = 2, col = 0, severity = vim.diagnostic.severity.WARN },
        { lnum = 3, col = 0, severity = vim.diagnostic.severity.ERROR },
      },
      expected = { line = 1, text = "1E" } -- shows ERROR count, not WARN count
    },
    {
      name = "shows warning count when no errors",
      diagnostics = {
        { lnum = 1, col = 0, severity = vim.diagnostic.severity.WARN },
        { lnum = 2, col = 0, severity = vim.diagnostic.severity.WARN },
        { lnum = 3, col = 0, severity = vim.diagnostic.severity.INFO },
      },
      expected = { line = 1, text = "2W" }
    },
    {
      name = "shows info count when no errors or warnings",
      diagnostics = {
        { lnum = 1, col = 0, severity = vim.diagnostic.severity.INFO },
        { lnum = 2, col = 0, severity = vim.diagnostic.severity.INFO },
        { lnum = 3, col = 0, severity = vim.diagnostic.severity.HINT },
      },
      expected = { line = 1, text = "2I" }
    },
  }) do
    it(("diagnostic aggregation: %s"):format(case.name), function()
      call_handler(case.diagnostics, { min_level = "HINT" }, case.expected)
    end)
  end
end)