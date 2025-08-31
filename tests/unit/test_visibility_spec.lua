local eq = assert.are.same
local config = require("lensline.config")
local lensline = require("lensline")

describe("lensline visibility system", function()
  
  describe("config visibility state", function()
    it("should have visibility true by default after setup", function()
      config.setup({})
      eq(true, config.is_visible())
    end)
    
    it("should allow setting visibility state", function()
      config.setup({})
      
      config.set_visible(false)
      eq(false, config.is_visible())
      
      config.set_visible(true)
      eq(true, config.is_visible())
    end)
    
    it("should maintain separate enabled and visible states", function()
      config.setup({})
      
      -- Both should start as true
      eq(true, config.is_enabled())
      eq(true, config.is_visible())
      
      -- Disable engine but keep visible
      config.set_enabled(false)
      eq(false, config.is_enabled())
      eq(true, config.is_visible())
      
      -- Enable engine but hide visibility
      config.set_enabled(true)
      config.set_visible(false)
      eq(true, config.is_enabled())
      eq(false, config.is_visible())
    end)
  end)
  
  describe("public API functions", function()
    it("should provide show/hide functions", function()
      eq("function", type(lensline.show))
      eq("function", type(lensline.hide))
      eq("function", type(lensline.is_visible))
    end)
    
    it("should provide toggle functions", function()
      eq("function", type(lensline.toggle_view))
      eq("function", type(lensline.toggle_engine))
    end)
    
    it("should maintain backward compatibility with deprecated toggle", function()
      eq("function", type(lensline.toggle))
    end)
  end)
  
  describe("visibility state behavior", function()
    it("should toggle visibility correctly", function()
      config.setup({})
      
      -- Start visible
      eq(true, config.is_visible())
      
      -- Hide
      lensline.hide()
      eq(false, config.is_visible())
      
      -- Show
      lensline.show()
      eq(true, config.is_visible())
    end)
    
    it("should toggle engine correctly", function()
      config.setup({})
      
      -- Start enabled
      eq(true, config.is_enabled())
      
      -- Disable engine - note: this affects initialization state
      config.set_enabled(false)
      eq(false, config.is_enabled())
      
      -- Re-enable
      config.set_enabled(true)
      eq(true, config.is_enabled())
    end)
    
    it("should handle toggle_view correctly", function()
      config.setup({})
      
      local original_visible = config.is_visible()
      
      lensline.toggle_view()
      eq(not original_visible, config.is_visible())
      
      lensline.toggle_view()
      eq(original_visible, config.is_visible())
    end)
  end)
end)