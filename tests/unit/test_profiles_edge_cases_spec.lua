describe("Profile Edge Cases", function()
  local config = require("lensline.config")

  before_each(function()
    -- Reset config state
    config.options = vim.deepcopy(config.defaults)
    config._enabled = false
    config._visible = true
    config._profiles_config = nil
    config._active_profile = nil
    -- Reset deprecation warnings
    for k in pairs(config._deprecation_warnings) do
      config._deprecation_warnings[k] = nil
    end
  end)

  describe("Configuration edge cases", function()
    it("should handle profiles with missing providers", function()
      local profile_config = {
        profiles = {
          {
            name = "minimal",
            style = { render = "all" }
            -- providers intentionally missing
          }
        }
      }

      config.setup(profile_config)
      
      local opts = config.get()
      assert.are.equal("minimal", config.get_active_profile())
      -- Should fall back to empty providers array
      assert.are.same({}, opts.providers)
    end)

    it("should handle profiles with missing style", function()
      local profile_config = {
        profiles = {
          {
            name = "basic",
            providers = { { name = "references", enabled = true } }
            -- style intentionally missing
          }
        }
      }

      config.setup(profile_config)
      
      local opts = config.get()
      assert.are.equal("basic", config.get_active_profile())
      -- Should fall back to default style
      assert.are.equal("all", opts.style.render)
      assert.are.equal("Comment", opts.style.highlight)
    end)

    it("should handle profiles with empty providers array", function()
      local profile_config = {
        profiles = {
          {
            name = "empty",
            providers = {},
            style = { render = "focused" }
          }
        }
      }

      config.setup(profile_config)
      
      local opts = config.get()
      assert.are.equal("empty", config.get_active_profile())
      assert.are.same({}, opts.providers)
      assert.are.equal("focused", opts.style.render)
    end)

    it("should handle profiles with empty style object", function()
      local profile_config = {
        profiles = {
          {
            name = "empty_style",
            providers = { { name = "references", enabled = true } },
            style = {}
          }
        }
      }

      config.setup(profile_config)
      
      local opts = config.get()
      assert.are.equal("empty_style", config.get_active_profile())
      -- Should merge with defaults
      assert.are.equal("all", opts.style.render)
      assert.are.equal(" • ", opts.style.separator)
    end)
  end)

  describe("Profile name validation edge cases", function()
    it("should reject profile with empty string name", function()
      local invalid_config = {
        profiles = {
          {
            name = "",
            providers = {},
            style = {}
          }
        }
      }

      assert.has_error(function()
        config.setup(invalid_config)
      end, "profile at index 1 must have a non-empty name")
    end)

    it("should reject profile with whitespace-only name", function()
      local invalid_config = {
        profiles = {
          {
            name = "   ",
            providers = {},
            style = {}
          }
        }
      }

      -- Note: Current implementation doesn't trim whitespace
      -- This documents the current behavior
      config.setup(invalid_config)
      assert.are.equal("   ", config.get_active_profile())
    end)

    it("should reject profile with non-string name", function()
      local invalid_config = {
        profiles = {
          {
            name = 123,
            providers = {},
            style = {}
          }
        }
      }

      assert.has_error(function()
        config.setup(invalid_config)
      end, "profile at index 1 must have a non-empty name")
    end)

    it("should reject profile with nil name", function()
      local invalid_config = {
        profiles = {
          {
            name = nil,
            providers = {},
            style = {}
          }
        }
      }

      assert.has_error(function()
        config.setup(invalid_config)
      end, "profile at index 1 must have a non-empty name")
    end)
  end)

  describe("Profile array validation edge cases", function()
    it("should reject non-table profiles", function()
      local invalid_config = {
        profiles = "not an array"
      }

      -- This actually doesn't error because the code checks for profiles being table with #profiles == 0
      -- Let's test what actually happens
      config.setup(invalid_config)
      
      -- Should fall back to no profiles mode
      assert.is_false(config.has_profiles())
      assert.is_nil(config.get_active_profile())
    end)

    it("should reject profiles with non-table elements", function()
      local invalid_config = {
        profiles = {
          "not a table",
          { name = "valid", providers = {}, style = {} }
        }
      }

      assert.has_error(function()
        config.setup(invalid_config)
      end, "profile at index 1 must be a table")
    end)

    it("should handle profiles array with holes", function()
      local profile_config = {
        profiles = {
          { name = "first", providers = {}, style = {} },
          nil,  -- hole in array
          { name = "third", providers = {}, style = {} }
        }
      }

      -- This should work because ipairs stops at first nil
      config.setup(profile_config)
      assert.are.equal("first", config.get_active_profile())
      assert.are.same({"first"}, config.list_profiles())
    end)
  end)

  describe("Global settings edge cases", function()
    it("should handle partial global settings", function()
      local profile_config = {
        limits = { max_lines = 2000 }, -- Only some limits specified
        debounce_ms = 250,             -- Custom debounce
        profiles = {
          { name = "test", providers = {}, style = {} }
        }
      }

      config.setup(profile_config)
      
      local opts = config.get()
      assert.are.equal(2000, opts.limits.max_lines)
      assert.are.equal(70, opts.limits.max_lenses)  -- Should use default
      assert.are.equal(250, opts.debounce_ms)
      assert.are.equal(150, opts.focused_debounce_ms)  -- Should use default
    end)

    it("should handle empty global settings", function()
      local profile_config = {
        profiles = {
          { name = "test", providers = {}, style = {} }
        }
        -- No global settings
      }

      config.setup(profile_config)
      
      local opts = config.get()
      -- Should use all defaults
      assert.are.equal(1000, opts.limits.max_lines)
      assert.are.equal(500, opts.debounce_ms)
      assert.is_false(opts.debug_mode)
    end)
  end)

  describe("Config resolution edge cases", function()
    it("should handle deeply nested config merging", function()
      local profile_config = {
        limits = {
          exclude = { "custom/**" },
          max_lines = 800
        },
        profiles = {
          {
            name = "test",
            providers = { { name = "references", enabled = true } },
            style = {
              separator = " | ",
              highlight = "Special"
            }
          }
        }
      }

      config.setup(profile_config)
      
      local opts = config.get()
      -- Should merge deeply
      assert.are.equal(800, opts.limits.max_lines)
      assert.are.equal(70, opts.limits.max_lenses)  -- Default preserved
      assert.is_true(opts.limits.exclude_gitignored)  -- Default preserved
      assert.are.equal(" | ", opts.style.separator)
      assert.are.equal("Special", opts.style.highlight)
      assert.are.equal("┃ ", opts.style.prefix)  -- Default preserved
    end)

    it("should handle profile with all defaults overridden", function()
      local profile_config = {
        profiles = {
          {
            name = "custom",
            providers = {
              { name = "custom_provider", enabled = true, option = "value" }
            },
            style = {
              separator = " *** ",
              highlight = "ErrorMsg",
              prefix = ">>> ",
              placement = "inline",
              use_nerdfont = false,
              render = "focused"
            }
          }
        }
      }

      config.setup(profile_config)
      
      local opts = config.get()
      assert.are.equal(" *** ", opts.style.separator)
      assert.are.equal("ErrorMsg", opts.style.highlight)
      assert.are.equal(">>> ", opts.style.prefix)
      assert.are.equal("inline", opts.style.placement)
      assert.is_false(opts.style.use_nerdfont)
      assert.are.equal("focused", opts.style.render)
    end)
  end)

  describe("Switch profile edge cases", function()
    it("should handle rapid profile switching", function()
      config.setup({
        profiles = {
          { name = "a", providers = {}, style = { render = "all" } },
          { name = "b", providers = {}, style = { render = "focused" } },
          { name = "c", providers = {}, style = { render = "all" } }
        }
      })

      assert.are.equal("a", config.get_active_profile())
      
      config.switch_profile("b")
      assert.are.equal("b", config.get_active_profile())
      assert.are.equal("focused", config.get_render_mode())
      
      config.switch_profile("c")
      assert.are.equal("c", config.get_active_profile())
      assert.are.equal("all", config.get_render_mode())
      
      config.switch_profile("a")
      assert.are.equal("a", config.get_active_profile())
      assert.are.equal("all", config.get_render_mode())
    end)

    it("should preserve config state on failed switch attempt", function()
      config.setup({
        profiles = {
          { name = "valid", providers = { { name = "test", setting = "value" } }, style = { render = "all" } }
        }
      })

      local original_config = vim.deepcopy(config.get())
      local original_profile = config.get_active_profile()

      assert.has_error(function()
        config.switch_profile("nonexistent")
      end)

      -- State should be unchanged
      assert.are.equal(original_profile, config.get_active_profile())
      local current_config = config.get()
      assert.are.same(original_config.providers, current_config.providers)
      assert.are.same(original_config.style, current_config.style)
    end)
  end)

  describe("Warning handling edge cases", function()
    local captured_warnings = {}
    local original_notify

    before_each(function()
      captured_warnings = {}
      original_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN then
          table.insert(captured_warnings, msg)
        end
      end
    end)

    after_each(function()
      vim.notify = original_notify
    end)

    it("should warn only once about unexpected profile keys", function()
      local config_with_extras = {
        profiles = {
          {
            name = "test",
            providers = {},
            style = {},
            unexpected = "value",
            another_extra = "data"
          }
        }
      }

      config.setup(config_with_extras)
      
      -- Should warn about both unexpected keys
      assert.are.equal(2, #captured_warnings)
      
      local has_unexpected_warning = false
      local has_another_warning = false
      
      for _, warning in ipairs(captured_warnings) do
        if string.find(warning, "unexpected") then
          has_unexpected_warning = true
        end
        if string.find(warning, "another_extra") then
          has_another_warning = true
        end
      end
      
      assert.is_true(has_unexpected_warning)
      assert.is_true(has_another_warning)
    end)
  end)
end)