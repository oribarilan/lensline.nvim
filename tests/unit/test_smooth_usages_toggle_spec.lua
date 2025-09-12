local eq = assert.are.same

local function with_stub(mod, stub, fn)
  local orig = package.loaded[mod]
  package.loaded[mod] = stub
  local ok, err = pcall(fn)
  package.loaded[mod] = orig
  if not ok then error(err) end
end

describe("smooth usages toggle", function()
  local commands = require("lensline.commands")

  it("calls targeted usages provider refresh instead of full buffer refresh", function()
    local targeted_refresh_called = false
    local full_refresh_called = false
    
    -- Mock vim.api.nvim_get_current_buf and nvim_buf_line_count
    local orig_get_current_buf = vim.api.nvim_get_current_buf
    local orig_buf_line_count = vim.api.nvim_buf_line_count
    vim.api.nvim_get_current_buf = function() return 1 end
    vim.api.nvim_buf_line_count = function() return 100 end
    
    with_stub("lensline.config", {
      toggle_usages_expanded = function() return true end,
    }, function()
      with_stub("lensline.providers", {
        get_enabled_providers = function()
          return { usages = { module = {}, config = { name = "usages", enabled = true } } }
        end
      }, function()
        with_stub("lensline.executor", {
          execute_usages_provider_only = function(bufnr)
            targeted_refresh_called = true
            eq(1, bufnr) -- Verify correct buffer number passed
          end,
        }, function()
          with_stub("lensline.setup", {
            refresh_current_buffer = function()
              full_refresh_called = true
            end,
          }, function()
            -- Mock vim.notify to avoid noise in tests
            local orig_notify = vim.notify
            vim.notify = function() end
            
            commands.toggle_usages()
            
            -- Restore vim.notify
            vim.notify = orig_notify
          end)
        end)
      end)
    end)
    
    -- Restore original functions
    vim.api.nvim_get_current_buf = orig_get_current_buf
    vim.api.nvim_buf_line_count = orig_buf_line_count
    
    -- Verify that targeted refresh was called and full refresh was NOT called
    eq(true, targeted_refresh_called)
    eq(false, full_refresh_called)
  end)

  it("handles usages provider disabled gracefully", function()
    local targeted_refresh_called = false
    local notifications = {}
    
    -- Mock vim.api.nvim_get_current_buf
    local orig_get_current_buf = vim.api.nvim_get_current_buf
    vim.api.nvim_get_current_buf = function() return 1 end
    
    with_stub("lensline.config", {
      toggle_usages_expanded = function() return true end, -- State should still toggle
    }, function()
      with_stub("lensline.providers", {
        get_enabled_providers = function()
          return {} -- No usages provider enabled
        end
      }, function()
        with_stub("lensline.executor", {
          execute_usages_provider_only = function(bufnr)
            targeted_refresh_called = true
          end,
        }, function()
          -- Mock vim.notify to capture notifications
          local orig_notify = vim.notify
          vim.notify = function(msg, level)
            table.insert(notifications, {msg = msg, level = level})
          end
          
          commands.toggle_usages()
          
          -- Restore vim.notify
          vim.notify = orig_notify
        end)
      end)
    end)
    
    -- Restore original function
    vim.api.nvim_get_current_buf = orig_get_current_buf
    
    -- Verify that targeted refresh was NOT called when provider disabled
    eq(false, targeted_refresh_called)
    
    -- Verify warning notification was shown
    local has_warning = false
    for _, notif in ipairs(notifications) do
      if notif.msg:match("disabled") and notif.level == vim.log.levels.WARN then
        has_warning = true
        break
      end
    end
    eq(true, has_warning)
  end)
end)