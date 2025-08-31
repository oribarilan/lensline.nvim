local eq = assert.are.same

-- Minimal debug stub to avoid noise
package.loaded["lensline.debug"] = { log_context = function() end }

local config = require("lensline.config")
local setup = require("lensline.setup")
local focused_renderer = require("lensline.focused_renderer")

-- Mock vim.api functions for testing
local function setup_vim_mocks()
  _G.vim.api.nvim_create_augroup = function(name, opts) return math.random(1000) end
  _G.vim.api.nvim_del_augroup_by_id = function() end
  _G.vim.api.nvim_del_augroup_by_name = function() end
  _G.vim.api.nvim_create_autocmd = function() end
  _G.vim.api.nvim_list_bufs = function() return {} end
  _G.vim.api.nvim_set_decoration_provider = function() return true end
  _G.vim.api.nvim_create_namespace = function() return 123 end
  
  -- Mock other required functions
  _G.vim.lsp = { handlers = {} }
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
end

describe("focused rendering setup integration", function()
  before_each(function()
    setup_vim_mocks()
    
    -- Reset module state
    local focus = require("lensline.focus")
    focus._reset_state_for_test()
    focused_renderer._reset_state_for_test()
  end)
  
  describe("initialization with render modes", function()
    it("should enable focused mode when render='focused'", function()
      config.setup({ render = "focused" })
      
      setup.initialize()
      
      -- Check that focused renderer is enabled
      eq(true, focused_renderer._is_enabled_for_test())
    end)
    
    it("should not enable focused mode when render='all'", function()
      config.setup({ render = "all" })
      
      setup.initialize()
      
      -- Check that focused renderer is not enabled
      eq(false, focused_renderer._is_enabled_for_test())
    end)
    
    it("should default to 'all' mode when render not specified", function()
      config.setup({})  -- No render specified
      
      local opts = config.get()
      eq("all", opts.render)
      
      setup.initialize()
      eq(false, focused_renderer._is_enabled_for_test())
    end)
  end)
  
  describe("enable/disable flow", function()
    it("should enable focused mode when enabling lensline with render='focused'", function()
      config.setup({ render = "focused" })
      
      setup.enable()
      
      eq(true, focused_renderer._is_enabled_for_test())
      eq(true, config.is_enabled())
    end)
    
    it("should disable focused mode when disabling lensline", function()
      config.setup({ render = "focused" })
      setup.enable()
      
      eq(true, focused_renderer._is_enabled_for_test())
      
      setup.disable()
      
      eq(false, focused_renderer._is_enabled_for_test())
      eq(false, config.is_enabled())
    end)
    
    it("should handle multiple enable/disable cycles correctly", function()
      config.setup({ render = "focused" })
      
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
    it("should handle switching from 'all' to 'focused' mode", function()
      -- Start with 'all' mode
      config.setup({ render = "all" })
      setup.initialize()
      eq(false, focused_renderer._is_enabled_for_test())
      
      -- Switch to 'focused' mode
      config.setup({ render = "focused" })
      setup.initialize()
      eq(true, focused_renderer._is_enabled_for_test())
    end)
    
    it("should handle switching from 'focused' to 'all' mode", function()
      -- Start with 'focused' mode
      config.setup({ render = "focused" })
      setup.initialize()
      eq(true, focused_renderer._is_enabled_for_test())
      
      -- Switch to 'all' mode
      config.setup({ render = "all" })
      setup.initialize()
      eq(false, focused_renderer._is_enabled_for_test())
    end)
  end)
  
  describe("configuration validation", function()
    it("should accept valid render values", function()
      config.setup({ render = "all" })
      eq("all", config.get().render)
      
      config.setup({ render = "focused" })
      eq("focused", config.get().render)
    end)
    
    it("should preserve other config options when setting render", function()
      config.setup({ 
        render = "focused",
        debounce_ms = 250,
        providers = {
          { name = "custom", enabled = true }
        }
      })
      
      local opts = config.get()
      eq("focused", opts.render)
      eq(250, opts.debounce_ms)
      eq("custom", opts.providers[1].name)
    end)
    
    it("should handle invalid render values gracefully", function()
      -- The config system should accept any value, but the setup logic
      -- should treat anything other than "focused" as "all"
      config.setup({ render = "invalid_mode" })
      
      setup.initialize()
      
      -- Should not enable focused mode for invalid values
      eq(false, focused_renderer._is_enabled_for_test())
    end)
  end)
end)