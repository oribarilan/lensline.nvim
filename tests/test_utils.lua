-- Test utilities for lensline tests
local M = {}

-- Helper function to stub modules using the existing pattern
function M.with_stub(mod_name, stub, fn)
  local orig = package.loaded[mod_name]
  package.loaded[mod_name] = stub
  local ok, err = pcall(fn)
  package.loaded[mod_name] = orig
  if not ok then error(err) end
end

-- Stub config with enabled state and clear executor cache
-- This ensures executor picks up the stubbed config when required
function M.with_enabled_config(config, fn)
  M.with_stub("lensline.config", {
    is_enabled = function() return true end,
    is_visible = function() return true end,
    get = function() return config.get() end,
  }, function()
    -- Clear executor from cache so it picks up stubbed config
    package.loaded["lensline.executor"] = nil
    fn()
  end)
end

-- Convenience function for common debug stub
function M.stub_debug_silent()
  package.loaded["lensline.debug"] = { log_context = function() end }
end

function M.await(async_fn, timeout_ms)
  timeout_ms = timeout_ms or 5000
  local done = false
  local result = nil

  async_fn(function(...)
    result = { ... }
    done = true
  end)

  if done then
    if not result then
      return nil
    end
    if #result == 1 then
      return result[1]
    end
    return unpack(result)
  end

  local start = vim.loop.hrtime()
  while not done do
    local elapsed = (vim.loop.hrtime() - start) / 1000000
    if elapsed > timeout_ms then
      error(string.format("await timeout after %dms", timeout_ms))
    end
    vim.loop.run("nowait")
    vim.wait(1, function()
      return done
    end, 1)
  end

  if not result then
    return nil
  end
  if #result == 1 then
    return result[1]
  end
  return unpack(result)
end

return M