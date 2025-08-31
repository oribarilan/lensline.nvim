local M = {}
local config = require("lensline.config")
local utils = require("lensline.utils")
local lens_explorer = require("lensline.lens_explorer")

local state = {
  active_win = nil,          -- current active window id
  focus = { s = nil, e = nil, key = "nil", bufnr = -1 }, -- active window's focused range
}

-- Debounced recomputation of the focused function for the active window
local debounced_update = (function()
  local delay = function() return config.get().focused_debounce_ms end
  local debounce_fn, timer = utils.debounce(function()
    local win = state.active_win
    if not win or not vim.api.nvim_win_is_valid(win) then 
      return 
    end
    
    local bufnr = vim.api.nvim_win_get_buf(win)
    if not vim.api.nvim_buf_is_loaded(bufnr) then 
      return 
    end

    -- Get cursor position with bounds checking
    local cursor_ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
    if not cursor_ok or not cursor then
      return
    end
    
    local row0 = cursor[1] - 1  -- Convert to 0-based
    local linecount = vim.api.nvim_buf_line_count(bufnr)
    
    -- Safety bounds checking
    if row0 < 0 or row0 >= linecount then
      return
    end

    -- LSP-only function discovery from lens_explorer (async, cached by changedtick)
    lens_explorer.discover_functions_async(bufnr, 1, linecount, function(funcs)
      -- Safety guards
      if not funcs or #funcs == 0 then
        -- No functions found - clear focus
        local key = "nil"
        if key ~= state.focus.key or bufnr ~= state.focus.bufnr then
          state.focus = { s = nil, e = nil, key = key, bufnr = bufnr }
          -- Trigger a redraw; decoration provider will use state.focus
          vim.schedule(function() 
            vim.cmd("redraw!") 
          end)
        end
        return
      end
      
      -- Sort functions by line number for binary search
      table.sort(funcs, function(a, b) return (a.line or 1) < (b.line or 1) end)

      -- Binary search for function containing cursor
      local s, e
      local lo, hi = 1, #funcs
      while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local f = funcs[mid]
        local fs = (f.line or 1) - 1      -- Convert to 0-based
        local fe = (f.end_line or f.line or 1) - 1  -- Convert to 0-based
        
        if row0 < fs then
          hi = mid - 1
        elseif row0 > fe then
          lo = mid + 1
        else
          -- Found containing function
          s, e = fs, fe
          break
        end
      end

      local key = s and (s .. ":" .. e) or "nil"
      if key ~= state.focus.key or bufnr ~= state.focus.bufnr then
        state.focus = { s = s, e = e, key = key, bufnr = bufnr }
        -- Trigger a redraw; decoration provider will use state.focus
        vim.schedule(function() 
          vim.cmd("redraw!") 
        end)
      end
    end)
  end, delay())
  return debounce_fn
end)()

-- Public API
function M.set_active_win(win)
  state.active_win = win
  debounced_update()
end

function M.on_cursor_moved()
  debounced_update()
end

function M.get_focus()
  return state.focus
end

-- Test helper: reset state for unit tests
function M._reset_state_for_test()
  state = {
    active_win = nil,
    focus = { s = nil, e = nil, key = "nil", bufnr = -1 },
  }
end

return M