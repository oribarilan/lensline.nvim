local eq = assert.are.same

-- Test state tracking
local created_buffers = {}
local original_vim_api = {}

-- Module state reset function
local function reset_modules()
  package.loaded["lensline.config"] = nil
  package.loaded["lensline.setup"] = nil
  package.loaded["lensline.focused_renderer"] = nil
  package.loaded["lensline.focus"] = nil
  package.loaded["lensline.executor"] = nil
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
  original_vim_api.nvim_create_augroup = vim.api.nvim_create_augroup
  original_vim_api.nvim_del_augroup_by_id = vim.api.nvim_del_augroup_by_id
  original_vim_api.nvim_del_augroup_by_name = vim.api.nvim_del_augroup_by_name
  original_vim_api.nvim_create_autocmd = vim.api.nvim_create_autocmd
  original_vim_api.nvim_list_bufs = vim.api.nvim_list_bufs
  original_vim_api.nvim_set_decoration_provider = vim.api.nvim_set_decoration_provider
  original_vim_api.nvim_create_namespace = vim.api.nvim_create_namespace
  
  -- Set up mocks
  vim.api.nvim_create_augroup = function(name, opts) return math.random(1000) end
  vim.api.nvim_del_augroup_by_id = function() end
  vim.api.nvim_del_augroup_by_name = function() end
  vim.api.nvim_create_autocmd = function() end
  vim.api.nvim_list_bufs = function() return {} end
  vim.api.nvim_set_decoration_provider = function() return true end
  vim.api.nvim_create_namespace = function() return 123 end
  
  -- Mock LSP
  if not vim.lsp then vim.lsp = {} end
  if not vim.lsp.handlers then vim.lsp.handlers = {} end
end

-- Cleanup vim API mocks
local function cleanup_vim_mocks()
  for key, original_func in pairs(original_vim_api) do
    vim.api[key] = original_func
  end
  original_vim_api = {}
  
  -- Clean up LSP mocks
  vim.lsp = nil
end

-- Mock modules setup
local function setup_module_mocks()
  package.loaded["lensline.executor"] = {
    setup_event_listeners = function() end,
    cleanup = function() end,
  }
  package.loaded["lensline.renderer"] = {
    clear_buffer = function() end,
  }
  package.loaded["lensline.lens_explorer"] = {
    cleanup_cache = function() end,
  }
  package.loaded["lensline.debug"] = { 
    log_context = function() end -- Silent for tests
  }
end

describe("focused rendering setup integration", function()
  before_each(function()
    reset_modules()
    setup_vim_mocks()
    setup_module_mocks()
    created_buffers = {}
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
  
  describe("initialization with render modes", function()
    local render_mode_test_cases = {
      {
        name = "should enable focused mode when render='focused'",
        render_mode = "focused",
        expected_focused = true
      },
      {
        name = "should not enable focused mode when render='all'",
        render_mode = "all",
        expected_focused = false
      }
    }
    
    for _, case in ipairs(render_mode_test_cases) do
      it(case.name, function()
        local config = require("lensline.config")
        local setup = require("lensline.setup")
        local focused_renderer = require("lensline.focused_renderer")
        local focus = require("lensline.focus")
        
        config.setup({ style = { render = case.render_mode } })
        focus._reset_state_for_test()
        focused_renderer._reset_state_for_test()
        
        setup.initialize()
        
        eq(case.expected_focused, focused_renderer._is_enabled_for_test())
      end)
    end
    
    it("should default to 'all' mode when render not specified", function()
      local config = require("lensline.config")
      local setup = require("lensline.setup")
      local focused_renderer = require("lensline.focused_renderer")
      local focus = require("lensline.focus")
      
      config.setup({}) -- No render specified
      focus._reset_state_for_test()
      focused_renderer._reset_state_for_test()
      
      local opts = config.get()
      eq("all", opts.style.render)
      
      setup.initialize()
      eq(false, focused_renderer._is_enabled_for_test())
    end)
  end)
  
  describe("enable and disable flow", function()
    local enable_disable_test_cases = {
      {
        name = "should enable focused mode when enabling lensline with render='focused'",
        render_mode = "focused",
        action = function(setup, config) 
          setup.enable()
          return true, config.is_enabled()
        end,
        expected_focused = true,
        expected_enabled = true
      },
      {
        name = "should not enable focused mode when enabling lensline with render='all'",
        render_mode = "all",
        action = function(setup, config) 
          setup.enable()
          return false, config.is_enabled()
        end,
        expected_focused = false,
        expected_enabled = true
      }
    }
    
    for _, case in ipairs(enable_disable_test_cases) do
      it(case.name, function()
        local config = require("lensline.config")
        local setup = require("lensline.setup")
        local focused_renderer = require("lensline.focused_renderer")
        local focus = require("lensline.focus")
        
        config.setup({ style = { render = case.render_mode } })
        focus._reset_state_for_test()
        focused_renderer._reset_state_for_test()
        
        local expected_focused, expected_enabled = case.action(setup, config)
        
        eq(case.expected_focused, focused_renderer._is_enabled_for_test())
        eq(case.expected_enabled, config.is_enabled())
      end)
    end
    
    it("should disable focused mode when disabling lensline", function()
      local config = require("lensline.config")
      local setup = require("lensline.setup")
      local focused_renderer = require("lensline.focused_renderer")
      local focus = require("lensline.focus")
      
      config.setup({ style = { render = "focused" } })
      focus._reset_state_for_test()
      focused_renderer._reset_state_for_test()
      
      setup.enable()
      eq(true, focused_renderer._is_enabled_for_test())
      
      setup.disable()
      eq(false, focused_renderer._is_enabled_for_test())
      eq(false, config.is_enabled())
    end)
    
    it("should handle multiple enable/disable cycles correctly", function()
      local config = require("lensline.config")
      local setup = require("lensline.setup")
      local focused_renderer = require("lensline.focused_renderer")
      local focus = require("lensline.focus")
      
      config.setup({ style = { render = "focused" } })
      focus._reset_state_for_test()
      focused_renderer._reset_state_for_test()
      
      -- First cycle
      setup.enable()
      eq(true, focused_renderer._is_enabled_for_test())
      
      setup.disable()
      eq(false, focused_renderer._is_enabled_for_test())
      
      -- Second cycle
      setup.enable()
      eq(true, focused_renderer._is_enabled_for_test())
      
      setup.disable()
      eq(false, focused_renderer._is_enabled_for_test())
    end)
  end)
  
  describe("mode switching", function()
    local mode_switch_test_cases = {
      {
        name = "should handle switching from 'all' to 'focused' mode",
        initial_mode = "all",
        target_mode = "focused",
        expected_initial = false,
        expected_final = true
      },
      {
        name = "should handle switching from 'focused' to 'all' mode",
        initial_mode = "focused",
        target_mode = "all",
        expected_initial = true,
        expected_final = false
      }
    }
    
    for _, case in ipairs(mode_switch_test_cases) do
      it(case.name, function()
        local config = require("lensline.config")
        local setup = require("lensline.setup")
        local focused_renderer = require("lensline.focused_renderer")
        local focus = require("lensline.focus")
        
        -- Initial mode setup
        config.setup({ style = { render = case.initial_mode } })
        focus._reset_state_for_test()
        focused_renderer._reset_state_for_test()
        
        setup.initialize()
        eq(case.expected_initial, focused_renderer._is_enabled_for_test())
        
        -- Switch to target mode
        config.setup({ style = { render = case.target_mode } })
        focus._reset_state_for_test()
        focused_renderer._reset_state_for_test()
        
        setup.initialize()
        eq(case.expected_final, focused_renderer._is_enabled_for_test())
      end)
    end
  end)
  
  describe("configuration validation", function()
    it("should accept valid render values", function()
      local config = require("lensline.config")
      
      config.setup({ style = { render = "all" } })
      eq("all", config.get().style.render)

      config.setup({ style = { render = "focused" } })
      eq("focused", config.get().style.render)
    end)
    
    it("should preserve other config options when setting render", function()
      local config = require("lensline.config")
      
      config.setup({
        style = { render = "focused" },
        debounce_ms = 250,
        providers = {
          { name = "custom", enabled = true }
        }
      })
      
      local opts = config.get()
      eq("focused", opts.style.render)
      eq(250, opts.debounce_ms)
      eq("custom", opts.providers[1].name)
    end)
    
    it("should handle invalid render values gracefully", function()
      local config = require("lensline.config")
      local setup = require("lensline.setup")
      local focused_renderer = require("lensline.focused_renderer")
      local focus = require("lensline.focus")
      
      config.setup({ style = { render = "invalid_mode" } })
      focus._reset_state_for_test()
      focused_renderer._reset_state_for_test()
      
      setup.initialize()
      
      -- Should not enable focused mode for invalid values
      eq(false, focused_renderer._is_enabled_for_test())
    end)
  end)
end)