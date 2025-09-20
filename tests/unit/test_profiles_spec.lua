describe("Profile Management", function()
  local config = require("lensline.config")
  local setup = require("lensline.setup")
  local lensline = require("lensline")

  before_each(function()
    -- Reset config state
    config.options = vim.deepcopy(config.defaults)
    config._enabled = false
    config._visible = true
    config._profiles_config = nil
    config._active_profile = nil
    -- Reset deprecation warnings to ensure clean test state
    for k in pairs(config._deprecation_warnings) do
      config._deprecation_warnings[k] = nil
    end
  end)

  describe("Legacy Configuration", function()
    it("should work with existing single config", function()
      local legacy_config = {
        providers = {
          { name = "references", enabled = true },
          { name = "diagnostics", enabled = false }
        },
        style = { render = "all" },
        limits = { max_lines = 500 }
      }

      config.setup(legacy_config)

      assert.are.equal("default", config.get_active_profile())
      assert.is_true(config.has_profiles())
      assert.are.same({"default"}, config.list_profiles())
    end)

    it("should auto-migrate legacy config to profiles", function()
      local legacy_config = {
        providers = { { name = "references", enabled = true } },
        style = { render = "all" },
        limits = { max_lines = 500 }
      }

      config.setup(legacy_config)

      -- Should auto-migrate to profile format
      assert.are.equal("default", config.get_active_profile())
      assert.is_true(config.has_profiles())
      assert.are.same({"default"}, config.list_profiles())
      
      -- Should preserve the original configuration
      local opts = config.get()
      assert.are.equal("all", opts.style.render)
      assert.are.equal(500, opts.limits.max_lines)
    end)
  end)

  describe("Profile Configuration", function()
    it("should handle profiles array correctly", function()
      local profile_config = {
        limits = { max_lines = 1000 },
        debounce_ms = 300,
        profiles = {
          {
            name = "default",
            providers = { { name = "references", enabled = true } },
            style = { render = "all" }
          },
          {
            name = "dev",
            providers = {
              { name = "references", enabled = true },
              { name = "diagnostics", enabled = true }
            },
            style = { render = "focused" }
          }
        }
      }

      config.setup(profile_config)

      assert.are.equal("default", config.get_active_profile())
      assert.are.same({"default", "dev"}, config.list_profiles())
      assert.is_true(config.has_profile("dev"))
      assert.is_false(config.has_profile("nonexistent"))
    end)

    it("should use first profile as default", function()
      local profile_config = {
        profiles = {
          {
            name = "first",
            providers = { { name = "references", enabled = true } },
            style = { render = "all" }
          },
          {
            name = "second",
            providers = { { name = "diagnostics", enabled = true } },
            style = { render = "focused" }
          }
        }
      }

      config.setup(profile_config)

      assert.are.equal("first", config.get_active_profile())
    end)

    it("should respect active_profile override", function()
      local profile_config = {
        profiles = {
          {
            name = "default",
            providers = { { name = "references", enabled = true } },
            style = { render = "all" }
          },
          {
            name = "dev",
            providers = { { name = "diagnostics", enabled = true } },
            style = { render = "focused" }
          }
        },
        active_profile = "dev"
      }

      config.setup(profile_config)

      assert.are.equal("dev", config.get_active_profile())
    end)
  end)

  describe("Profile Validation", function()
    it("should reject empty profiles array", function()
      local invalid_config = {
        profiles = {}
      }

      assert.has_error(function()
        config.setup(invalid_config)
      end, "profiles array cannot be empty")
    end)

    it("should reject profiles without names", function()
      local invalid_config = {
        profiles = {
          {
            providers = { { name = "references", enabled = true } },
            style = { render = "all" }
          }
        }
      }

      assert.has_error(function()
        config.setup(invalid_config)
      end)
    end)

    it("should reject duplicate profile names", function()
      local invalid_config = {
        profiles = {
          {
            name = "duplicate",
            providers = { { name = "references", enabled = true } },
            style = { render = "all" }
          },
          {
            name = "duplicate",
            providers = { { name = "diagnostics", enabled = true } },
            style = { render = "focused" }
          }
        }
      }

      assert.has_error(function()
        config.setup(invalid_config)
      end, "duplicate profile name: duplicate")
    end)

    it("should warn about unexpected keys in profiles", function()
      local notify_calls = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notify_calls, { msg = msg, level = level })
      end

      local config_with_unexpected = {
        profiles = {
          {
            name = "test",
            providers = { { name = "references", enabled = true } },
            style = { render = "all" },
            unexpected_key = "should warn"
          }
        }
      }

      config.setup(config_with_unexpected)

      -- Should have warning about unexpected key
      local found_warning = false
      for _, call in ipairs(notify_calls) do
        if string.find(call.msg, "unexpected key") then
          found_warning = true
          break
        end
      end
      assert.is_true(found_warning)

      vim.notify = original_notify
    end)
  end)

  describe("Profile Switching", function()
    local profile_config

    before_each(function()
      profile_config = {
        limits = { max_lines = 1000 },
        profiles = {
          {
            name = "default",
            providers = { { name = "references", enabled = true } },
            style = { render = "all", placement = "above" }
          },
          {
            name = "dev",
            providers = {
              { name = "references", enabled = true },
              { name = "diagnostics", enabled = true }
            },
            style = { render = "focused", placement = "inline" }
          }
        }
      }
      config.setup(profile_config)
    end)

    it("should switch profiles correctly", function()
      assert.are.equal("default", config.get_active_profile())

      config.switch_profile("dev")

      assert.are.equal("dev", config.get_active_profile())
      
      -- Check that configuration was updated
      local opts = config.get()
      assert.are.equal("focused", opts.style.render)
      assert.are.equal("inline", opts.style.placement)
    end)

    it("should error on non-existent profile", function()
      assert.has_error(function()
        config.switch_profile("nonexistent")
      end)
    end)

    it("should be no-op when switching to current profile", function()
      local initial_profile = config.get_active_profile()
      config.switch_profile(initial_profile)
      assert.are.equal(initial_profile, config.get_active_profile())
    end)

    it("should rollback on switch failure", function()
      local original_profile = config.get_active_profile()
      
      -- This should fail and rollback
      assert.has_error(function()
        config.switch_profile("nonexistent")
      end)
      
      assert.are.equal(original_profile, config.get_active_profile())
    end)
  end)

  describe("API Functions", function()
    it("should return empty list when no profiles", function()
      config.setup({})
      assert.are.same({}, config.list_profiles())
      assert.is_false(config.has_profiles())
      assert.is_nil(config.get_active_profile())
    end)

    it("should return correct profile config", function()
      local profile_config = {
        profiles = {
          {
            name = "test",
            providers = { { name = "references", enabled = true } },
            style = { render = "all" }
          }
        }
      }
      config.setup(profile_config)

      local profile = config.get_profile_config("test")
      assert.is_not_nil(profile)
      assert.are.equal("test", profile.name)
      assert.are.equal("all", profile.style.render)
    end)
  end)

  describe("Default Inheritance", function()
    it("should inherit default providers when profile providers is nil", function()
      local profile_config = {
        profiles = {
          {
            name = "style_only",
            -- providers = nil (not specified)
            style = { placement = "inline", prefix = "" }
          }
        }
      }
      
      config.setup(profile_config)
      
      local opts = config.get()
      
      -- Should have default providers, not empty array
      assert.is_not_nil(opts.providers)
      assert.is_true(#opts.providers > 0)
      
      -- Check for default providers
      local has_references = false
      local has_last_author = false
      for _, provider in ipairs(opts.providers) do
        if provider.name == "references" then
          has_references = true
          assert.is_false(provider.enabled)  -- references is disabled by default
        elseif provider.name == "last_author" then
          has_last_author = true
          assert.is_true(provider.enabled)
        end
      end
      
      assert.is_true(has_references, "Should have references provider from defaults")
      assert.is_true(has_last_author, "Should have last_author provider from defaults")
      
      -- Style should be merged with defaults
      assert.are.equal("inline", opts.style.placement)
      assert.are.equal("", opts.style.prefix)
      assert.are.equal(" • ", opts.style.separator) -- from defaults
      assert.are.equal("Comment", opts.style.highlight) -- from defaults
    end)
    
    it("should inherit default style when profile style is nil", function()
      local profile_config = {
        profiles = {
          {
            name = "providers_only",
            providers = { { name = "references", enabled = false } },
            -- style = nil (not specified)
          }
        }
      }
      
      config.setup(profile_config)
      
      local opts = config.get()
      
      -- Should have default style, not empty object
      assert.are.equal(" • ", opts.style.separator)
      assert.are.equal("Comment", opts.style.highlight)
      assert.are.equal("┃ ", opts.style.prefix)
      assert.are.equal("above", opts.style.placement)
      assert.are.equal("all", opts.style.render)
      assert.is_true(opts.style.use_nerdfont)
      
      -- Providers should be overridden
      assert.are.equal(1, #opts.providers)
      assert.are.equal("references", opts.providers[1].name)
      assert.is_false(opts.providers[1].enabled)
    end)
    
    it("should inherit both defaults when profile has neither providers nor style", function()
      local profile_config = {
        profiles = {
          {
            name = "minimal",
            -- providers = nil
            -- style = nil
          }
        }
      }
      
      config.setup(profile_config)
      
      local opts = config.get()
      
      -- Should be exactly like defaults
      assert.is_true(#opts.providers > 0)
      assert.are.equal(" • ", opts.style.separator)
      assert.are.equal("Comment", opts.style.highlight)
      assert.are.equal("┃ ", opts.style.prefix)
      assert.are.equal("above", opts.style.placement)
      assert.are.equal("all", opts.style.render)
    end)
    
    it("should handle empty providers array vs nil providers differently", function()
      local empty_providers_config = {
        profiles = {
          {
            name = "empty_providers",
            providers = {}, -- explicitly empty
            style = { placement = "inline" }
          }
        }
      }
      
      config.setup(empty_providers_config)
      
      local opts = config.get()
      
      -- Empty array should result in no providers (explicit choice)
      assert.are.equal(0, #opts.providers)
      assert.are.equal("inline", opts.style.placement)
    end)
    
    it("should deep merge style properties correctly", function()
      local partial_style_config = {
        profiles = {
          {
            name = "partial_style",
            style = {
              placement = "inline",
              prefix = "",
              -- separator, highlight, use_nerdfont, render not specified
            }
          }
        }
      }
      
      config.setup(partial_style_config)
      
      local opts = config.get()
      
      -- Specified properties should override
      assert.are.equal("inline", opts.style.placement)
      assert.are.equal("", opts.style.prefix)
      
      -- Unspecified properties should inherit defaults
      assert.are.equal(" • ", opts.style.separator)
      assert.are.equal("Comment", opts.style.highlight)
      assert.are.equal("all", opts.style.render)
      assert.is_true(opts.style.use_nerdfont)
    end)
  end)

  describe("Integration with lensline API", function()
    it("should export profile functions", function()
      assert.is_function(lensline.switch_profile)
      assert.is_function(lensline.get_active_profile)
      assert.is_function(lensline.list_profiles)
      assert.is_function(lensline.has_profile)
    end)
  end)
end)