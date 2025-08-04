local config = require("lensline.config")
local utils = require("lensline.utils")
local renderer = require("lensline.renderer")
local executor = require("lensline.executor")
local debug = require("lensline.debug")

local M = {}

local autocmd_group = nil

function M.initialize()
  local opts = config.get()
  
  -- Debug system will be lazily initialized on first use if debug_mode = true
  debug.log_context("Core", "initializing plugin with new provider architecture")
  debug.log_context("Core", "config: " .. vim.inspect(opts))
  
  -- Setup LSP handlers for noise suppression
  config.setup_lsp_handlers()
  
  -- Setup core autocommands for cleanup
  M.setup_core_autocommands()
  
  -- Setup provider event listeners via executor
  executor.setup_event_listeners()
  
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
  
  -- Initial buffer setup - only when actually needed
  -- Removed aggressive WinEnter/BufEnter that was causing infinite loops
  -- The providers themselves already handle the necessary events:
  -- - last_author: BufRead, BufWritePost
  -- - ref_count: LspAttach, BufWritePost
  -- - diag_summary: DiagnosticChanged, BufEnter
  -- - complexity: BufWritePost, TextChanged
  --
  -- We only need to handle the initial case when a buffer is first loaded
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = autocmd_group,
    callback = function(event)
      local bufnr = event.buf or vim.api.nvim_get_current_buf()
      if utils.is_valid_buffer(bufnr) then
        -- Use the debounced executor for initial setup
        executor.trigger_unified_update(bufnr)
      end
    end,
  })
  
  debug.log_context("Core", "core autocommands initialized")
end


function M.refresh_current_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  if not utils.is_valid_buffer(bufnr) then
    return
  end
  
  debug.log_context("Core", "manual refresh requested for buffer " .. bufnr)
  
  -- Clear existing lens data
  renderer.clear_buffer(bufnr)
  
  -- Use the unified update mechanism to trigger all providers via executor
  executor.trigger_unified_update(bufnr)
end

function M.enable()
  config.set_enabled(true)
  M.initialize()
end

function M.disable()
  config.set_enabled(false)
  
  debug.log_context("Core", "disabling lensline")
  
  -- Cleanup provider resources (debounce timers and event listeners) via executor
  executor.cleanup()
  
  -- Restore LSP handlers
  config.restore_lsp_handlers()
  
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