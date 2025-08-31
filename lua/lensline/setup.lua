local config = require("lensline.config")
local utils = require("lensline.utils")
local renderer = require("lensline.renderer")
local executor = require("lensline.executor")
local debug = require("lensline.debug")
local focused_renderer = require("lensline.focused_renderer")
local focus = require("lensline.focus")

local M = {}

local autocmd_group = nil
local focused_mode_group = nil

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
  
  -- Setup render mode (focused vs all)
  if opts.render == "focused" then
    M.enable_focused_mode()
  else
    M.disable_focused_mode()  -- Ensure focused mode is disabled
  end
  
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
  
  -- Initial buffer setup only - providers handle their own specific events
  -- BufReadPost ensures proper initialization without interfering with buffer switching
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = autocmd_group,
    callback = function(event)
      local bufnr = event.buf or vim.api.nvim_get_current_buf()
      if utils.is_valid_buffer(bufnr) then
        executor.trigger_unified_update(bufnr)
      end
    end,
  })
  
  debug.log_context("Core", "core autocommands initialized")
end

-- Enable focused mode with proper event handlers
function M.enable_focused_mode()
  focused_renderer.enable()

  -- Clean up any existing focused mode autocommands
  if focused_mode_group then
    vim.api.nvim_del_augroup_by_id(focused_mode_group)
  end

  focused_mode_group = vim.api.nvim_create_augroup("LenslineFocusedMode", { clear = true })

  -- Track active window changes
  vim.api.nvim_create_autocmd({ "WinEnter" }, {
    group = focused_mode_group,
    callback = function(args)
      focus.set_active_win(args.win or vim.api.nvim_get_current_win())
    end,
  })

  -- Track cursor movements for focus updates
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = focused_mode_group,
    callback = function()
      focus.on_cursor_moved()
    end,
  })
  
  -- Initialize focus tracking for current window/cursor position
  vim.schedule(function()
    focus.set_active_win(vim.api.nvim_get_current_win())
  end)
  
  debug.log_context("Core", "focused mode enabled")
end

-- Disable focused mode and clean up resources
function M.disable_focused_mode()
  if focused_mode_group then
    vim.api.nvim_del_augroup_by_id(focused_mode_group)
    focused_mode_group = nil
  end
  
  focused_renderer.disable()
  debug.log_context("Core", "focused mode disabled")
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
  
  -- Apply render mode after enabling
  local opts = config.get()
  if opts.render == "focused" then
    M.enable_focused_mode()
  end
end

function M.disable()
  config.set_enabled(false)
  
  debug.log_context("Core", "disabling lensline")
  
  -- Cleanup focused mode resources
  M.disable_focused_mode()
  
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