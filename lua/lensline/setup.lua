local config = require("lensline.config")
local utils = require("lensline.utils")
local renderer = require("lensline.renderer")
local providers = require("lensline.providers")
local debug = require("lensline.debug")

local M = {}

local autocmd_group = nil

function M.initialize()
  local opts = config.get()
  
  -- Initialize debug system first
  debug.init()
  
  debug.log_context("Core", "initializing plugin with new provider architecture")
  debug.log_context("Core", "config: " .. vim.inspect(opts))
  
  -- Setup core autocommands for cleanup
  M.setup_core_autocommands()
  
  -- Setup provider event listeners
  providers.setup_event_listeners()
  
  debug.log_context("Core", "plugin initialized successfully")
end

function M.setup_core_autocommands()
  if autocmd_group then
    vim.api.nvim_del_augroup_by_id(autocmd_group)
  end
  
  autocmd_group = vim.api.nvim_create_augroup("lensline_core", { clear = true })
  
  -- Buffer cleanup on deletion
  vim.api.nvim_create_autocmd("BufDelete", {
    group = autocmd_group,
    callback = function(event)
      renderer.clear_buffer(event.buf)
    end,
  })
  
  -- Window events for visibility optimization
  vim.api.nvim_create_autocmd({ "WinScrolled", "WinEnter" }, {
    group = autocmd_group,
    callback = function(event)
      -- Trigger refresh for visible-only providers when scrolling
      local bufnr = vim.api.nvim_get_current_buf()
      if utils.is_valid_buffer(bufnr) then
        M.refresh_buffer_visible_providers(bufnr)
      end
    end,
  })
  
  debug.log_context("Core", "core autocommands initialized")
end

function M.refresh_buffer_visible_providers(bufnr)
  local enabled_providers = providers.get_enabled_providers()
  
  for name, provider_info in pairs(enabled_providers) do
    if provider_info.module.only_visible then
      providers.trigger_provider(bufnr, name, provider_info.module, provider_info.config)
    end
  end
end

function M.refresh_current_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  if not utils.is_valid_buffer(bufnr) then
    return
  end
  
  debug.log_context("Core", "manual refresh requested for buffer " .. bufnr)
  
  -- Clear existing lens data
  renderer.clear_buffer(bufnr)
  
  -- Trigger all providers
  local enabled_providers = providers.get_enabled_providers()
  for name, provider_info in pairs(enabled_providers) do
    providers.trigger_provider(bufnr, name, provider_info.module, provider_info.config)
  end
end

function M.enable()
  config.set_enabled(true)
  M.initialize()
end

function M.disable()
  config.set_enabled(false)
  
  debug.log_context("Core", "disabling lensline")
  
  -- Cleanup autocommands
  if autocmd_group then
    vim.api.nvim_del_augroup_by_id(autocmd_group)
    autocmd_group = nil
  end
  
  -- Clear all buffer renderers
  local buffers = vim.api.nvim_list_bufs()
  for _, bufnr in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      renderer.clear_buffer(bufnr)
    end
  end
  
  debug.log_context("Core", "lensline disabled")
end

return M