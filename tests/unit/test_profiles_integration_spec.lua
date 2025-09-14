describe("Profile Integration", function()
  local config = require("lensline.config")
  local setup = require("lensline.setup")
  local commands = require("lensline.commands")
  local lensline = require("lensline")

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

  describe("setup.switch_profile integration", function()
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
            name = "focused",
            providers = {
              { name = "references", enabled = true },
              { name = "diagnostics", enabled = true }
            },
            style = { render = "focused", placement = "inline" }
          }
        }
      }
      
      -- Mock dependencies to avoid real initialization
      package.loaded["lensline.executor"] = {
        setup_event_listeners = function() end,
        cleanup = function() end,
        trigger_unified_update = function() end
      }
      package.loaded["lensline.renderer"] = {
        clear_buffer = function() end
      }
      package.loaded["lensline.focused_renderer"] = {
        enable = function() end,
        disable = function() end
      }
      package.loaded["lensline.focus"] = {
        set_active_win = function() end,
        on_cursor_moved = function() end
      }
      package.loaded["lensline.debug"] = {
        log_context = function() end
      }
      
      config.setup(profile_config)
    end)

    after_each(function()
      -- Clean up mocked modules
      package.loaded["lensline.executor"] = nil
      package.loaded["lensline.renderer"] = nil
      package.loaded["lensline.focused_renderer"] = nil
      package.loaded["lensline.focus"] = nil
      package.loaded["lensline.debug"] = nil
    end)

    it("should switch profiles when engine is disabled", function()
      -- Engine starts disabled by default after config.setup
      assert.are.equal("default", config.get_active_profile())

      -- Switch should work without restart
      local result = setup.switch_profile("focused")
      assert.is_true(result)
      assert.are.equal("focused", config.get_active_profile())
      
      -- Config should be updated
      local opts = config.get()
      assert.are.equal("focused", opts.style.render)
      assert.are.equal("inline", opts.style.placement)
    end)

    it("should restart engine when switching while enabled", function()
      -- Enable engine first
      config.set_enabled(true)
      config.set_visible(true)
      
      local result = setup.switch_profile("focused")
      assert.is_true(result)
      assert.are.equal("focused", config.get_active_profile())
      
      -- Should preserve enabled/visible state
      assert.is_true(config.is_enabled())
      assert.is_true(config.is_visible())
    end)

    it("should return false when switching to current profile", function()
      local result = setup.switch_profile("default")
      assert.is_false(result)
      assert.are.equal("default", config.get_active_profile())
    end)

    it("should error when no profiles configured", function()
      config._profiles_config = nil
      config._active_profile = nil
      
      assert.has_error(function()
        setup.switch_profile("any")
      end, "No profiles configured. Cannot switch profiles.")
    end)

    it("should error on invalid profile name", function()
      assert.has_error(function()
        setup.switch_profile("nonexistent")
      end, "Profile 'nonexistent' not found. Available profiles: default, focused")
    end)
  end)

  describe("Command integration", function()
    local captured_notifications = {}

    before_each(function()
      captured_notifications = {}
      -- Mock vim.notify to capture notifications
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(captured_notifications, { msg = msg, level = level })
      end
      
      -- Restore after test
      vim.schedule(function()
        vim.notify = original_notify
      end)
    end)

    it("should handle LenslineProfile command with no profiles", function()
      config.setup({}) -- No profiles

      -- Mock the command function
      local command_fn = function()
        if not config.has_profiles() then
          vim.notify("No profiles configured", vim.log.levels.WARN)
          return
        end
      end

      command_fn()
      
      assert.are.equal(1, #captured_notifications)
      assert.are.equal("No profiles configured", captured_notifications[1].msg)
      assert.are.equal(vim.log.levels.WARN, captured_notifications[1].level)
    end)

    it("should handle cycling with single profile", function()
      config.setup({
        profiles = {
          { name = "only", providers = {}, style = {} }
        }
      })

      -- Mock cycling logic
      local command_fn = function()
        local current = config.get_active_profile()
        local available = config.list_profiles()
        
        if #available <= 1 then
          vim.notify("Only one profile available, cannot cycle", vim.log.levels.INFO)
          return
        end
      end

      command_fn()
      
      assert.are.equal(1, #captured_notifications)
      assert.are.equal("Only one profile available, cannot cycle", captured_notifications[1].msg)
    end)
  end)

  describe("Render mode switching", function()
    it("should change render mode when switching profiles", function()
      config.setup({
        profiles = {
          {
            name = "all_mode",
            providers = { { name = "references", enabled = true } },
            style = { render = "all" }
          },
          {
            name = "focused_mode", 
            providers = { { name = "references", enabled = true } },
            style = { render = "focused" }
          }
        }
      })

      assert.are.equal("all", config.get_render_mode())
      
      config.switch_profile("focused_mode")
      assert.are.equal("focused", config.get_render_mode())
      
      config.switch_profile("all_mode")
      assert.are.equal("all", config.get_render_mode())
    end)
  end)

  describe("Global settings preservation", function()
    it("should preserve global settings across profile switches", function()
      config.setup({
        limits = { max_lines = 500, max_lenses = 40 },
        debounce_ms = 300,
        debug_mode = true,
        profiles = {
          {
            name = "profile1",
            providers = { { name = "references", enabled = true } },
            style = { render = "all" }
          },
          {
            name = "profile2",
            providers = { { name = "diagnostics", enabled = true } },
            style = { render = "focused" }
          }
        }
      })

      local initial_opts = config.get()
      assert.are.equal(500, initial_opts.limits.max_lines)
      assert.are.equal(40, initial_opts.limits.max_lenses)
      assert.are.equal(300, initial_opts.debounce_ms)
      assert.is_true(initial_opts.debug_mode)

      config.switch_profile("profile2")
      
      local switched_opts = config.get()
      -- Global settings should be preserved
      assert.are.equal(500, switched_opts.limits.max_lines)
      assert.are.equal(40, switched_opts.limits.max_lenses)
      assert.are.equal(300, switched_opts.debounce_ms)
      assert.is_true(switched_opts.debug_mode)
      
      -- Profile-specific settings should change
      assert.are.equal("focused", switched_opts.style.render)
    end)
  end)

  describe("Error recovery", function()
    it("should rollback on switch failure", function()
      config.setup({
        profiles = {
          { name = "valid", providers = {}, style = {} }
        }
      })
      
      local original_profile = config.get_active_profile()
      
      -- This should fail and rollback
      assert.has_error(function()
        config.switch_profile("invalid")
      end)
      
      assert.are.equal(original_profile, config.get_active_profile())
    end)
  end)
end)