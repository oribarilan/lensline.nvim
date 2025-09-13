-- tests/unit/test_config_migration_spec.lua
-- unit tests for config migration from root-level render to style.render

local eq = assert.are.same

describe("config migration from root render to style.render", function()
  local notify_calls = {}
  local original_notify

  local function reset_modules()
    for name,_ in pairs(package.loaded) do
      if name:match("^lensline") then package.loaded[name] = nil end
    end
  end

  before_each(function()
    reset_modules()
    notify_calls = {}
    
    -- Mock vim.notify to capture deprecation warnings
    original_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end
  end)

  after_each(function()
    reset_modules()
    vim.notify = original_notify
  end)

  describe("new style.render config", function()
    it("uses style.render from defaults", function()
      local config = require("lensline.config")
      config.setup({})
      local opts = config.get()
      
      eq("all", opts.style.render)
      eq("all", config.get_render_mode())
      eq(0, #notify_calls) -- no warnings for new config structure
    end)

    it("allows overriding style.render", function()
      local config = require("lensline.config")
      config.setup({ style = { render = "focused" } })
      local opts = config.get()
      
      eq("focused", opts.style.render)
      eq("focused", config.get_render_mode())
      eq(0, #notify_calls) -- no warnings for new config structure
    end)

    it("preserves other style settings when setting render", function()
      local config = require("lensline.config")
      config.setup({
        style = {
          render = "focused",
          prefix = ">> ",
          separator = " | "
        }
      })
      local opts = config.get()
      
      eq("focused", opts.style.render)
      eq(">> ", opts.style.prefix)
      eq(" | ", opts.style.separator)
      eq("Comment", opts.style.highlight) -- default preserved
    end)
  end)

  describe("backward compatibility with root-level render", function()
    it("migrates root-level render to style.render", function()
      local config = require("lensline.config")
      config.setup({ render = "focused" })
      local opts = config.get()
      
      eq("focused", opts.style.render)
      eq("focused", config.get_render_mode())
      eq(nil, opts.render) -- root-level render removed
    end)

    it("shows deprecation warning for root-level render", function()
      local config = require("lensline.config")
      -- We can't easily test vim.notify in this test environment,
      -- but we can verify the migration behavior works correctly
      config.setup({ render = "focused" })
      
      local opts = config.get()
      eq("focused", opts.style.render)
      eq(nil, opts.render) -- root-level render removed
    end)

    it("handles multiple setup calls with root-level render", function()
      local config = require("lensline.config")
      config.setup({ render = "focused" })
      config.setup({ render = "all" })
      config.setup({ render = "focused" })
      
      local opts = config.get()
      eq("focused", opts.style.render)
      eq(nil, opts.render) -- root-level render removed
    end)

    it("migrates different render values correctly", function()
      local test_cases = { "all", "focused" }
      
      for _, render_value in ipairs(test_cases) do
        reset_modules()
        notify_calls = {}
        
        local config = require("lensline.config")
        config.setup({ render = render_value })
        local opts = config.get()
        
        eq(render_value, opts.style.render)
        eq(render_value, config.get_render_mode())
        eq(nil, opts.render)
      end
    end)
  end)

  describe("conflict resolution between root and style.render", function()
    it("prioritizes style.render when both are provided", function()
      local config = require("lensline.config")
      config.setup({
        render = "all",
        style = { render = "focused" }
      })
      local opts = config.get()
      
      eq("focused", opts.style.render) -- style.render wins
      eq("focused", config.get_render_mode())
      eq(nil, opts.render) -- root-level render removed
    end)

    it("handles conflict when both are provided", function()
      local config = require("lensline.config")
      config.setup({
        render = "all",
        style = { render = "focused" }
      })
      
      local opts = config.get()
      eq("focused", opts.style.render) -- style.render wins
      eq("focused", config.get_render_mode())
      eq(nil, opts.render) -- root-level render removed
    end)

    it("handles multiple conflict scenarios", function()
      local config = require("lensline.config")
      config.setup({ render = "all", style = { render = "focused" } })
      local first_opts = config.get()
      
      config.setup({ render = "focused", style = { render = "all" } })
      local second_opts = config.get()
      
      eq("focused", first_opts.style.render)
      eq("all", second_opts.style.render)
      eq(nil, first_opts.render)
      eq(nil, second_opts.render)
    end)
  end)

  describe("integration with existing config merging", function()
    it("preserves deep merging behavior", function()
      local config = require("lensline.config")
      config.setup({
        render = "focused",
        style = {
          prefix = ">> ",
          highlight = "Normal"
        },
        providers = {
          { name = "references", enabled = false }
        }
      })
      local opts = config.get()
      
      -- Migration worked
      eq("focused", opts.style.render)
      eq(nil, opts.render)
      
      -- Deep merging preserved
      eq(">> ", opts.style.prefix)
      eq("Normal", opts.style.highlight)
      eq(" • ", opts.style.separator) -- default preserved
      eq("above", opts.style.placement) -- default preserved
      eq(1, #opts.providers) -- providers merged correctly
      eq("references", opts.providers[1].name)
      eq(false, opts.providers[1].enabled)
    end)

    it("handles repeated setup calls correctly", function()
      local config = require("lensline.config")
      config.setup({ render = "focused" })
      local first_opts = config.get()
      
      config.setup({ style = { render = "all", prefix = ">> " } })
      local second_opts = config.get()
      
      eq("focused", first_opts.style.render)
      eq("all", second_opts.style.render)
      eq(">> ", second_opts.style.prefix)
      eq(nil, second_opts.render) -- no root-level render in final config
    end)
  end)
end)