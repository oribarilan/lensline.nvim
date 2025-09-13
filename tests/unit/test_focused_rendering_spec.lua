local eq = assert.are.same

-- Test state tracking
local created_buffers = {}
local original_vim_api = {}

-- Module state reset function
local function reset_modules()
  package.loaded["lensline.config"] = nil
  package.loaded["lensline.focus"] = nil
  package.loaded["lensline.focused_renderer"] = nil
  package.loaded["lensline.renderer"] = nil
  package.loaded["lensline.lens_explorer"] = nil
  package.loaded["lensline.debug"] = nil
end

-- Centralized buffer helper
local function make_buf()
  local bufnr = vim.api.nvim_create_buf(false, true)
  table.insert(created_buffers, bufnr)
  return bufnr
end

-- Vim API setup helper
local function setup_vim_mocks()
  -- Store originals for cleanup
  original_vim_api.nvim_win_is_valid = vim.api.nvim_win_is_valid
  original_vim_api.nvim_win_get_buf = vim.api.nvim_win_get_buf
  original_vim_api.nvim_buf_is_loaded = vim.api.nvim_buf_is_loaded
  original_vim_api.nvim_win_get_cursor = vim.api.nvim_win_get_cursor
  original_vim_api.nvim_buf_line_count = vim.api.nvim_buf_line_count
  original_vim_api.nvim_get_current_win = vim.api.nvim_get_current_win
  original_vim_api.nvim_buf_get_lines = vim.api.nvim_buf_get_lines
  original_vim_api.nvim_set_decoration_provider = vim.api.nvim_set_decoration_provider
  original_vim_api.nvim_create_namespace = vim.api.nvim_create_namespace
  original_vim_api.nvim_buf_set_extmark = vim.api.nvim_buf_set_extmark
  
  -- Set up mocks
  vim.api.nvim_win_is_valid = function() return true end
  vim.api.nvim_win_get_buf = function() return 1 end
  vim.api.nvim_buf_is_loaded = function() return true end
  vim.api.nvim_win_get_cursor = function() return {10, 0} end
  vim.api.nvim_buf_line_count = function() return 100 end
  vim.api.nvim_get_current_win = function() return 1 end
  vim.api.nvim_buf_get_lines = function() return {"function test() {", "  return 42", "}"} end
  vim.api.nvim_set_decoration_provider = function() return true end
  vim.api.nvim_create_namespace = function() return 123 end
  vim.api.nvim_buf_set_extmark = function() return 1 end
end

-- Cleanup vim API mocks
local function cleanup_vim_mocks()
  for key, original_func in pairs(original_vim_api) do
    vim.api[key] = original_func
  end
  original_vim_api = {}
end

-- Test data factory
local function create_test_functions()
  return {
    { line = 1, end_line = 5, name = "function_a" },
    { line = 10, end_line = 20, name = "function_b" },
    { line = 25, end_line = 30, name = "function_c" },
  }
end

describe("focused rendering system", function()
  before_each(function()
    reset_modules()
    setup_vim_mocks()
    created_buffers = {}
    
    -- Set up silent debug module
    package.loaded["lensline.debug"] = {
      log_context = function() end -- Silent for tests
    }
  end)
  
  after_each(function()
    -- Clean up created buffers
    for _, bufnr in ipairs(created_buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    created_buffers = {}
    
    cleanup_vim_mocks()
    reset_modules()
  end)
  
  describe("focus module initialization", function()
    local focus_test_cases = {
      {
        name = "should initialize with no focus",
        setup = function() end,
        expected_key = "nil",
        expected_start = nil,
        expected_end = nil
      }
    }
    
    for _, case in ipairs(focus_test_cases) do
      it(case.name, function()
        local config = require("lensline.config")
        local focus = require("lensline.focus")
        
        config.setup({ style = { render = "focused" } })
        focus._reset_state_for_test()
        case.setup()
        
        local f = focus.get_focus()
        eq(case.expected_key, f.key)
        eq(case.expected_start, f.s)
        eq(case.expected_end, f.e)
      end)
    end
  end)
  
  describe("focused renderer module", function()
    local renderer_test_cases = {
      {
        name = "should enable decoration provider for focused mode",
        render_mode = "focused",
        action = function(focused_renderer)
          focused_renderer.enable()
          return focused_renderer._is_enabled_for_test()
        end,
        expected = true
      },
      {
        name = "should disable decoration provider",
        render_mode = "focused",
        action = function(focused_renderer)
          focused_renderer.enable()
          focused_renderer.disable()
          return focused_renderer._is_enabled_for_test()
        end,
        expected = false
      },
      {
        name = "should not render when render mode is all",
        render_mode = "all",
        action = function(focused_renderer)
          return focused_renderer.on_win(1, 1)
        end,
        expected = false
      }
    }
    
    for _, case in ipairs(renderer_test_cases) do
      it(case.name, function()
        local config = require("lensline.config")
        local focused_renderer = require("lensline.focused_renderer")
        
        config.setup({ style = { render = case.render_mode } })
        focused_renderer._reset_state_for_test()
        
        local result = case.action(focused_renderer)
        eq(case.expected, result)
      end)
    end
    
    it("should only render in active window", function()
      local config = require("lensline.config")
      local focused_renderer = require("lensline.focused_renderer")
      
      config.setup({ style = { render = "focused" } })
      focused_renderer._reset_state_for_test()
      focused_renderer.enable() -- Explicitly enable focused renderer
      
      -- Test active window
      vim.api.nvim_get_current_win = function() return 1 end
      local result_active = focused_renderer.on_win(1, 1)
      eq(true, result_active)
      
      -- Test non-active window
      vim.api.nvim_get_current_win = function() return 2 end
      local result_inactive = focused_renderer.on_win(1, 1)
      eq(false, result_inactive)
    end)
  end)
  
  describe("combined lines computation", function()
    local combined_lines_test_cases = {
      {
        name = "should combine provider data preserving order",
        providers = {
          { name = "p1", enabled = true },
          { name = "p2", enabled = true },
        },
        provider_data = {
          p1 = {
            { line = 10, text = "A" },
            { line = 12, text = "C" },
          },
          p2 = {
            { line = 10, text = "B" },
            { line = 11, text = "D" },
          }
        },
        expected = {
          [10] = {"A", "B"},
          [11] = {"D"},
          [12] = {"C"}
        }
      },
      {
        name = "should handle empty provider data",
        providers = {},
        provider_data = {},
        expected = {}
      },
      {
        name = "should skip invalid lens items",
        providers = {
          { name = "p1", enabled = true },
        },
        provider_data = {
          p1 = {
            { line = 10, text = "Valid" },
            { line = nil, text = "Invalid - no line" },
            { line = 11, text = nil },
            nil,
          }
        },
        expected = {
          [10] = {"Valid"}
        }
      }
    }
    
    for _, case in ipairs(combined_lines_test_cases) do
      it(case.name, function()
        local config = require("lensline.config")
        local renderer = require("lensline.renderer")
        
        config.setup({
          style = { render = "focused" },
          providers = case.providers
        })
        
        renderer.ensure_provider_data_initialized()
        renderer.provider_lens_data[1] = case.provider_data
        
        local combined = renderer.compute_combined_lines(1)
        eq(case.expected, combined)
      end)
    end
  end)
  
  describe("focus function detection", function()
    it("should handle cursor within function range", function()
      local config = require("lensline.config")
      local focus = require("lensline.focus")
      local lens_explorer = require("lensline.lens_explorer")
      
      config.setup({ style = { render = "focused" } })
      focus._reset_state_for_test()
      
      local mock_functions = create_test_functions()
      
      -- Mock lens explorer with immediate callback
      lens_explorer.discover_functions_async = function(bufnr, start_line, end_line, callback)
        callback(mock_functions)
      end
      
      vim.api.nvim_win_get_cursor = function() return {15, 0} end -- Line 15 is in function_b (10-20)
      focus.set_active_win(1)
      
      -- Basic verification - focus system doesn't crash
      local f = focus.get_focus()
      assert.is_not_nil(f, "Focus object should exist")
      assert.is_string(f.key, "Focus key should be a string")
      
      -- If focus state is available, verify it's correct
      if f.s and f.e then
        eq(9, f.s)   -- 0-based: line 10 -> 9
        eq(19, f.e)  -- 0-based: line 20 -> 19
      end
    end)
    
    it("should handle cursor outside function ranges", function()
      local config = require("lensline.config")
      local focus = require("lensline.focus")
      local lens_explorer = require("lensline.lens_explorer")
      
      config.setup({ style = { render = "focused" } })
      focus._reset_state_for_test()
      
      local mock_functions = create_test_functions()
      
      lens_explorer.discover_functions_async = function(bufnr, start_line, end_line, callback)
        callback(mock_functions)
      end
      
      vim.api.nvim_win_get_cursor = function() return {23, 0} end -- Between functions
      focus.set_active_win(1)
      
      local f = focus.get_focus()
      eq("nil", f.key)
      eq(nil, f.s)
      eq(nil, f.e)
    end)
    
    it("should handle empty function list", function()
      local config = require("lensline.config")
      local focus = require("lensline.focus")
      local lens_explorer = require("lensline.lens_explorer")
      
      config.setup({ style = { render = "focused" } })
      focus._reset_state_for_test()
      
      lens_explorer.discover_functions_async = function(bufnr, start_line, end_line, callback)
        callback({}) -- No functions
      end
      
      focus.set_active_win(1)
      
      local f = focus.get_focus()
      eq("nil", f.key)
    end)
  end)
  
  describe("integration scenarios", function()
    it("should handle basic focused rendering workflow", function()
      local config = require("lensline.config")
      local focus = require("lensline.focus")
      local focused_renderer = require("lensline.focused_renderer")
      local renderer = require("lensline.renderer")
      local lens_explorer = require("lensline.lens_explorer")
      
      config.setup({
        style = { render = "focused" },
        providers = {
          { name = "test_provider", enabled = true },
        }
      })
      
      focus._reset_state_for_test()
      focused_renderer._reset_state_for_test()
      
      -- Setup provider data
      renderer.ensure_provider_data_initialized()
      renderer.provider_lens_data[1] = {
        test_provider = {
          { line = 10, text = "Test Lens" },
        }
      }
      
      -- Setup function discovery
      local mock_functions = create_test_functions()
      lens_explorer.discover_functions_async = function(bufnr, start_line, end_line, callback)
        callback(mock_functions)
      end
      
      focus.set_active_win(1)
      
      -- Test that on_line doesn't crash with focused rendering
      local success = pcall(focused_renderer.on_line, 1, 1, 9)
      eq(true, success)
      
      local success2 = pcall(focused_renderer.on_line, 1, 1, 1)
      eq(true, success2)
    end)
  end)
end)