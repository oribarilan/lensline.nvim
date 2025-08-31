local M = {}
local config = require("lensline.config")
local renderer = require("lensline.renderer")
local focus = require("lensline.focus")
local presenter = require("lensline.presenter")

M.ns = vim.api.nvim_create_namespace("lensline_focused_ephemeral")


-- Provider callbacks
function M.on_win(winid, bufnr)
  local debug = require("lensline.debug")
  
  -- Only in focused mode
  if (config.get().render ~= "focused") then
    debug.log_context("FocusedRenderer", "skipping window " .. winid .. " - not in focused mode")
    return false
  end
  
  -- Only the active window draws
  local active = vim.api.nvim_get_current_win()
  if winid ~= active then
    debug.log_context("FocusedRenderer", "skipping window " .. winid .. " - not active (active: " .. active .. ")")
    return false
  end
  
  debug.log_context("FocusedRenderer", "rendering window " .. winid .. " (active)")
  return true
end

function M.on_line(winid, bufnr, lnum)
  -- lnum is 0-based
  local f = focus.get_focus()
  
  -- Quick checks without verbose logging (this function is called frequently)
  if not f or bufnr ~= f.bufnr or f.s == nil or f.e == nil then
    return false
  end
  
  if lnum < f.s or lnum > f.e then
    return false
  end

  local opts = config.get()
  local combined = renderer.compute_combined_lines(bufnr)
  local texts = combined[lnum + 1]  -- our map is 1-based
  if not texts or #texts == 0 then
    return false
  end

  local line_text = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ""
  local extopts = presenter.compute_extmark_opts({
    placement = opts.style.placement,
    texts = texts,
    separator = opts.style.separator,
    highlight = opts.style.highlight,
    prefix = opts.style.prefix,
    line_content = line_text,
    ephemeral = true
  })

  -- Emit ephemeral extmark for this line
  pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns, lnum, 0, extopts)
end

function M.enable()
  local debug = require("lensline.debug")
  
  if M._prov then
    debug.log_context("FocusedRenderer", "already enabled")
    return
  end
  
  debug.log_context("FocusedRenderer", "enabling decoration provider")
  local result = vim.api.nvim_set_decoration_provider(M.ns, {
    on_win  = function (_, winid, bufnr, _top, _bot)
      return M.on_win(winid, bufnr)
    end,
    on_line = function (_, winid, bufnr, lnum)
      M.on_line(winid, bufnr, lnum)
    end,
  })
  -- Mark as enabled even if result is nil (decoration provider was set)
  M._prov = result or true
  debug.log_context("FocusedRenderer", "decoration provider enabled, result: " .. tostring(result) .. ", _prov: " .. tostring(M._prov))
end

function M.disable()
  if not M._prov then 
    return 
  end
  
  -- Unset by setting a new provider without callbacks
  vim.api.nvim_set_decoration_provider(M.ns, {})
  M._prov = nil
  -- No need to clear: ephemeral marks disappear on next redraw
end

-- Test helper: check if decoration provider is enabled
function M._is_enabled_for_test()
  return M._prov ~= nil
end

-- Test helper: reset state for unit tests
function M._reset_state_for_test()
  M._prov = nil
end

return M