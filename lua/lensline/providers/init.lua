local config = require("lensline.config")
local utils = require("lensline.utils")
local lens_explorer = require("lensline.lens_explorer")

local M = {}

-- Available providers following the new architecture
M.available_providers = {
  references = require("lensline.providers.references"),
  diagnostics = require("lensline.providers.diagnostics"),
  last_author = require("lensline.providers.last_author"),
  complexity = require("lensline.providers.complexity"),
  usages = require("lensline.providers.usages"),
}

-- Get enabled providers from config
function M.get_enabled_providers()
  local debug = require("lensline.debug")
  local opts = config.get()
  local enabled = {}
  
  debug.log_context("Providers", "getting enabled providers from config")
  debug.log_context("Providers", "available providers: " .. vim.inspect(vim.tbl_keys(M.available_providers)))
  
  for _, provider_config in ipairs(opts.providers) do
    local provider_name = provider_config.name
    local provider_module = nil
    
    debug.log_context("Providers", "checking provider: " .. provider_name)
    
    -- Check if inline provider (has handler function)
    if provider_config.handler then
      provider_module = provider_config  -- Use config as module for inline providers
      debug.log_context("Providers", "found inline provider: " .. provider_name)
    else
      provider_module = M.available_providers[provider_name]  -- Built-in provider
      debug.log_context("Providers", "built-in provider found: " .. tostring(provider_module ~= nil))
    end
    
    debug.log_context("Providers", "enabled: " .. tostring(provider_config.enabled ~= false))
    
    if provider_module and provider_config.enabled ~= false then
      enabled[provider_name] = {
        module = provider_module,
        config = provider_config
      }
      debug.log_context("Providers", "enabled provider: " .. provider_name)
    elseif not provider_module then
      debug.log_context("Providers", "provider not found: " .. provider_name, "WARN")
    end
  end
  
  debug.log_context("Providers", "total enabled providers: " .. vim.tbl_count(enabled))
  return enabled
end

return M