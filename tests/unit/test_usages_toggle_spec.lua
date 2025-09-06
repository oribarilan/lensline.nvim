-- tests/unit/test_usages_toggle_spec.lua
-- unit tests for usages toggle command functionality

local eq = assert.are.same

describe("usages toggle functionality", function()
  local function reset_modules()
    for name,_ in pairs(package.loaded) do
      if name:match("^lensline") then package.loaded[name] = nil end
    end
  end

  before_each(function()
    reset_modules()
  end)

  describe("config toggle state management", function()
    it("starts with usages collapsed by default", function()
      local config = require("lensline.config")
      eq(false, config.get_usages_expanded())
    end)

    it("can set usages expanded state", function()
      local config = require("lensline.config")
      config.set_usages_expanded(true)
      eq(true, config.get_usages_expanded())
      
      config.set_usages_expanded(false)
      eq(false, config.get_usages_expanded())
    end)

    it("toggle_usages_expanded switches state and returns new value", function()
      local config = require("lensline.config")
      -- Start collapsed
      eq(false, config.get_usages_expanded())
      
      -- Toggle to expanded
      local result1 = config.toggle_usages_expanded()
      eq(true, result1)
      eq(true, config.get_usages_expanded())
      
      -- Toggle back to collapsed
      local result2 = config.toggle_usages_expanded()
      eq(false, result2)
      eq(false, config.get_usages_expanded())
    end)
  end)

  describe("toggle command", function()
    it("toggle_usages function exists", function()
      local commands = require("lensline.commands")
      assert.is_function(commands.toggle_usages)
    end)

    it("toggle_usages changes state", function()
      local config = require("lensline.config")
      local commands = require("lensline.commands")
      
      -- Start collapsed
      eq(false, config.get_usages_expanded())
      
      -- Toggle to expanded (test will fail gracefully on setup call)
      local ok1 = pcall(commands.toggle_usages)
      eq(true, config.get_usages_expanded())
      
      -- Toggle back to collapsed
      local ok2 = pcall(commands.toggle_usages)
      eq(false, config.get_usages_expanded())
      
      -- The toggle function exists and changes state even if setup.refresh fails
      assert.is_true(ok1 or ok2, "toggle_usages should exist and be callable")
    end)
  end)

  describe("state persistence", function()
    it("maintains toggle state across config operations", function()
      local config = require("lensline.config")
      -- Set to expanded
      config.set_usages_expanded(true)
      eq(true, config.get_usages_expanded())
      
      -- Other config operations shouldn't affect usages state
      config.set_visible(false)
      config.set_enabled(false)
      eq(true, config.get_usages_expanded())
      
      -- Verify other states work independently
      eq(false, config.is_visible())
      eq(false, config.is_enabled())
      eq(true, config.get_usages_expanded())
    end)

    it("usages state is independent of enabled/visible states", function()
      local config = require("lensline.config")
      -- Test all combinations
      local states = {
        {enabled = true, visible = true, usages = true},
        {enabled = true, visible = false, usages = false},
        {enabled = false, visible = true, usages = true},
        {enabled = false, visible = false, usages = false},
      }
      
      for _, state in ipairs(states) do
        config.set_enabled(state.enabled)
        config.set_visible(state.visible)
        config.set_usages_expanded(state.usages)
        
        eq(state.enabled, config.is_enabled())
        eq(state.visible, config.is_visible())
        eq(state.usages, config.get_usages_expanded())
      end
    end)
  end)

  describe("config defaults", function()
    it("usages provider has correct default configuration", function()
      local config = require("lensline.config")
      local opts = config.get()
      local usages_config = nil
      
      for _, provider in ipairs(opts.providers) do
        if provider.name == "usages" then
          usages_config = provider
          break
        end
      end
      
      assert.is_not_nil(usages_config, "usages provider should be in default config")
      eq("usages", usages_config.name)
      eq(false, usages_config.enabled)  -- disabled by default
      eq(", ", usages_config.inner_separator)
    end)
  end)
end)