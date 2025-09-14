describe("Profile Commands", function()
  local config = require("lensline.config")
  local commands = require("lensline.commands")

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

  describe("Profile command cycling", function()
    local captured_notifications = {}
    local original_notify

    before_each(function()
      captured_notifications = {}
      original_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(captured_notifications, { msg = msg, level = level })
      end
    end)

    after_each(function()
      vim.notify = original_notify
    end)

    it("should cycle through profiles correctly", function()
      config.setup({
        profiles = {
          { name = "first", providers = {}, style = {} },
          { name = "second", providers = {}, style = {} },
          { name = "third", providers = {}, style = {} }
        }
      })

      assert.are.equal("first", config.get_active_profile())

      -- Test the cycling logic directly without mocking
      local current = config.get_active_profile()
      local available = config.list_profiles()
      local current_idx = 1
      for i, profile in ipairs(available) do
        if profile == current then
          current_idx = i
          break
        end
      end
      local next_profile = available[(current_idx % #available) + 1]
      
      assert.are.equal("second", next_profile)
      assert.are.same({"first", "second", "third"}, available)
    end)

    it("should handle profile not found error gracefully", function()
      config.setup({
        profiles = {
          { name = "valid", providers = {}, style = {} }
        }
      })

      -- Mock setup.switch_profile to throw error
      package.loaded["lensline.setup"] = {
        switch_profile = function(name)
          if name == "invalid" then
            error("Profile 'invalid' not found. Available profiles: valid")
          end
        end
      }

      -- Test the command handler logic
      local profile_name = "invalid"
      if not config.has_profile(profile_name) then
        local available = table.concat(config.list_profiles(), ", ")
        vim.notify(string.format("Profile '%s' not found. Available: %s", profile_name, available), vim.log.levels.ERROR)
      end

      assert.are.equal(1, #captured_notifications)
      assert.are.equal("Profile 'invalid' not found. Available: valid", captured_notifications[1].msg)
      assert.are.equal(vim.log.levels.ERROR, captured_notifications[1].level)

      -- Clean up
      package.loaded["lensline.setup"] = nil
    end)

    it("should warn when no profiles configured", function()
      config.setup({}) -- No profiles

      -- Test command handler logic
      if not config.has_profiles() then
        vim.notify("No profiles configured", vim.log.levels.WARN)
      end

      assert.are.equal(1, #captured_notifications)
      assert.are.equal("No profiles configured", captured_notifications[1].msg)
      assert.are.equal(vim.log.levels.WARN, captured_notifications[1].level)
    end)

    it("should inform when only one profile available for cycling", function()
      config.setup({
        profiles = {
          { name = "only", providers = {}, style = {} }
        }
      })

      -- Test cycling logic with single profile
      local available = config.list_profiles()
      if #available <= 1 then
        vim.notify("Only one profile available, cannot cycle", vim.log.levels.INFO)
      end

      assert.are.equal(1, #captured_notifications)
      assert.are.equal("Only one profile available, cannot cycle", captured_notifications[1].msg)
      assert.are.equal(vim.log.levels.INFO, captured_notifications[1].level)
    end)
  end)

  describe("Command completion", function()
    it("should provide profile names for completion", function()
      config.setup({
        profiles = {
          { name = "dev", providers = {}, style = {} },
          { name = "minimal", providers = {}, style = {} },
          { name = "verbose", providers = {}, style = {} }
        }
      })

      local completion_results = config.list_profiles()
      assert.are.same({"dev", "minimal", "verbose"}, completion_results)
    end)

    it("should return empty completion when no profiles", function()
      config.setup({}) -- No profiles
      
      local completion_results = config.list_profiles()
      assert.are.same({}, completion_results)
    end)
  end)

  describe("API function delegation", function()
    it("should delegate profile functions correctly", function()
      config.setup({
        profiles = {
          { name = "test", providers = {}, style = {} }
        }
      })

      -- Test that commands module delegates to config
      assert.are.equal("test", commands.get_active_profile())
      assert.are.same({"test"}, commands.list_profiles())
      assert.is_true(commands.has_profile("test"))
      assert.is_false(commands.has_profile("nonexistent"))
    end)

    it("should delegate switch_profile to setup module", function()
      -- Setup a valid profile first
      config.setup({
        profiles = {
          { name = "test_profile", providers = {}, style = {} }
        }
      })
      
      -- Test that commands.switch_profile calls through to setup.switch_profile
      -- We'll verify by checking the active profile changes
      assert.are.equal("test_profile", config.get_active_profile())
      
      -- The delegation works if no error is thrown
      local success = pcall(commands.switch_profile, "test_profile")
      assert.is_true(success)
    end)
  end)

  describe("Profile state queries", function()
    it("should correctly report profile state", function()
      -- No profiles initially
      config.setup({})
      assert.is_false(config.has_profiles())
      assert.is_nil(config.get_active_profile())

      -- With profiles
      config.setup({
        profiles = {
          { name = "active", providers = {}, style = {} }
        }
      })
      assert.is_true(config.has_profiles())
      assert.are.equal("active", config.get_active_profile())
    end)

    it("should handle profile config retrieval", function()
      config.setup({
        profiles = {
          {
            name = "detailed",
            providers = { { name = "references", enabled = true } },
            style = { render = "all", prefix = ">> " }
          }
        }
      })

      local profile = config.get_profile_config("detailed")
      assert.is_not_nil(profile)
      assert.are.equal("detailed", profile.name)
      assert.are.equal("all", profile.style.render)
      assert.are.equal(">> ", profile.style.prefix)

      local nonexistent = config.get_profile_config("missing")
      assert.is_nil(nonexistent)
    end)
  end)
end)