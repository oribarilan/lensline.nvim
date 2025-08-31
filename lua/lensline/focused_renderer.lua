local M = {}
local config = require("lensline.config")
local renderer = require("lensline.renderer")
local focus = require("lensline.focus")

M.ns = vim.api.nvim_create_namespace("lensline_focused_ephemeral")

-- Create extmark opts (reuse existing styles from renderer.lua)
local function make_opts(placement, texts, sep, hl, prefix, line_text)
  local text_join = table.concat(texts, sep)
  
  if placement == "inline" then
    -- Inline: virtual text at end of line, with prefix if configured
    local virt_text = {}
    
    -- Add prefix if configured
    if prefix and prefix ~= "" then
      table.insert(virt_text, { prefix, hl })
    end
    
    table.insert(virt_text, { text_join, hl })
    
    -- Combine all parts into a single string with a leading space
    local inline_text = " " .. table.concat(vim.tbl_map(function(t) return t[1] end, virt_text), "")
    
    return {
      virt_text = { { inline_text, hl } },
      virt_text_pos = "eol",
      ephemeral = true
    }
  else
    -- Above: virtual lines above function, with prefix and indentation
    local leading_whitespace = line_text:match("^%s*") or ""
    local virt_text = {}
    
    if leading_whitespace ~= "" then
      table.insert(virt_text, { leading_whitespace, hl })
    end
    
    if prefix and prefix ~= "" then
      table.insert(virt_text, { prefix, hl })
    end
    
    table.insert(virt_text, { text_join, hl })
    
    return {
      virt_lines = { virt_text },
      virt_lines_above = true,
      ephemeral = true
    }
  end
end

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
  local extopts = make_opts(
    opts.style.placement or "above",
    texts,
    opts.style.separator or " • ",
    opts.style.highlight or "Comment",
    opts.style.prefix or "",
    line_text
  )

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