local eq = assert.are.same

-- Simple module stub helper (full replacement)
local function with_stub(mod, stub, fn)
  local orig = package.loaded[mod]
  package.loaded[mod] = stub
  local ok, err = pcall(fn)
  package.loaded[mod] = orig
  if not ok then error(err) end
end

-- Temporary patch for vim.diagnostic.get
local function with_diagnostics(list, fn)
  local orig = vim.diagnostic.get
  vim.diagnostic.get = function(_) return list end
  local ok, err = pcall(fn)
  vim.diagnostic.get = orig
  if not ok then error(err) end
end

-- Prepare config BEFORE requiring provider (provider needs config.get().style.use_nerdfont)
local config = require("lensline.config")
config.setup({
  style = {
    use_nerdfont = false, -- explicit to test fallback letters; individual tests can override via setup if needed
  },
})

local provider = require("lensline.providers.diag_summary")

-- Reusable function range covering lines 0..20 fully
local func_range = {
  start = { line = 0, character = 0 },
  ["end"] = { line = 20, character = 200 },
}

describe("providers.diag_summary", function()
  it("returns nil when there are no diagnostics", function()
    local called = false
    with_stub("lensline.debug", { log_context = function() end }, function()
      with_stub("lensline.utils", {
        is_valid_buffer = function() return true end,
      }, function()
        with_diagnostics({}, function()
          provider.handler(5, { line = 1, range = func_range }, {}, function(res)
            called = true
            eq(nil, res)
          end)
        end)
      end)
    end)
    eq(true, called)
  end)

  it("returns nil when only warnings but min_level=ERROR", function()
    local out = "unset"
    with_stub("lensline.debug", { log_context = function() end }, function()
      with_stub("lensline.utils", {
        is_valid_buffer = function() return true end,
      }, function()
        with_diagnostics({
          { lnum = 2, col = 0, severity = vim.diagnostic.severity.WARN },
        }, function()
          provider.handler(3, { line = 1, range = func_range }, { min_level = "ERROR" }, function(res)
            out = res
          end)
        end)
      end)
    end)
    eq(nil, out)
  end)

  it("aggregates and filters diagnostics (min_level=WARN) showing only ERROR & WARN", function()
    local out
    -- Reset config to ensure nerdfont disabled for predictable fallback letters
    config.setup({ style = { use_nerdfont = false } })
    with_stub("lensline.debug", { log_context = function() end }, function()
      with_stub("lensline.utils", {
        is_valid_buffer = function() return true end,
      }, function()
        with_diagnostics({
          { lnum = 1, col = 0, severity = vim.diagnostic.severity.ERROR },
          { lnum = 3, col = 1, severity = vim.diagnostic.severity.ERROR },
          { lnum = 4, col = 2, severity = vim.diagnostic.severity.WARN },
          { lnum = 5, col = 0, severity = vim.diagnostic.severity.INFO },
          { lnum = 6, col = 0, severity = vim.diagnostic.severity.HINT },
        }, function()
          provider.handler(9, { line = 1, range = func_range }, { min_level = "WARN" }, function(res)
            out = res
          end)
        end)
      end)
    end)
    eq({ line = 1, text = "2E 1W" }, out)
  end)

  it("includes INFO when numeric min_level = vim.diagnostic.severity.INFO", function()
    local out
    config.setup({ style = { use_nerdfont = false } })
    with_stub("lensline.debug", { log_context = function() end }, function()
      with_stub("lensline.utils", {
        is_valid_buffer = function() return true end,
      }, function()
        with_diagnostics({
          { lnum = 1, col = 0, severity = vim.diagnostic.severity.ERROR },
          { lnum = 2, col = 0, severity = vim.diagnostic.severity.WARN },
          { lnum = 3, col = 0, severity = vim.diagnostic.severity.WARN },
          { lnum = 4, col = 0, severity = vim.diagnostic.severity.INFO },
          { lnum = 7, col = 0, severity = vim.diagnostic.severity.HINT },
        }, function()
          provider.handler(11, { line = 1, range = func_range }, { min_level = vim.diagnostic.severity.INFO }, function(res)
            out = res
          end)
        end)
      end)
    end)
    -- HINT excluded because severity.HINT (4) > min_level (3)
    eq({ line = 1, text = "1E 2W 1I" }, out)
  end)
end)