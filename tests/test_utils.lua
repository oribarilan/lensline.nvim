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

return M