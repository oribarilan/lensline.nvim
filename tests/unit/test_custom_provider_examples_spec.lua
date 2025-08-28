-- Tests for the custom provider examples shown in README.md
-- These tests verify that the examples actually work as documented

local eq = assert.are.same
local utils = require("lensline.utils")
local config = require("lensline.config")

-- Helper to stub modules
local function with_stub(module_name, stub_tbl, fn)
  local orig = package.loaded[module_name]
  package.loaded[module_name] = stub_tbl
  local ok, err = pcall(fn)
  package.loaded[module_name] = orig
  if not ok then error(err) end
end

describe("Custom Provider Examples", function()
  before_each(function()
    config.setup({})
  end)

  describe("Zero Reference Warning Example", function()
    it("should show warning for functions with zero references", function()
      local handler_called = false
      local result_text = nil
      local result_line = nil

      -- Mock callback function
      local callback = function(result)
        handler_called = true
        if result then
          result_text = result.text
          result_line = result.line
        end
      end

      -- Mock func_info
      local func_info = {
        line = 10,
        name = "test_function",
        character = 0
      }

      -- Setup config for fallback text
      config.setup({ style = { use_nerdfont = false } })

      -- Create mock utils with get_lsp_references
      local mock_utils = {
        get_lsp_references = function(bufnr, func_info_param, callback_param)
          -- Simulate zero references
          callback_param({}) -- Empty references array
        end,
        if_nerdfont_else = utils.if_nerdfont_else
      }

      -- Stub utils module
      with_stub("lensline.utils", mock_utils, function()
        -- Define the handler from README.md example
        local handler = function(bufnr, func_info, provider_config, callback)
          local utils = require("lensline.utils")
          
          utils.get_lsp_references(bufnr, func_info, function(references)
            if references then
              local count = #references
              local icon, text
              
              if count == 0 then
                icon = utils.if_nerdfont_else("⚠️ ", "WARN ")
                text = icon .. "No references"
              else
                icon = utils.if_nerdfont_else("󰌹 ", "")
                local suffix = utils.if_nerdfont_else("", " refs")
                text = icon .. count .. suffix
              end
              
              callback({ line = func_info.line, text = text })
            else
              callback(nil)
            end
          end)
        end

        -- Test the handler
        handler(1, func_info, {}, callback)
      end)

      -- Verify results
      assert.is_true(handler_called, "Handler callback should be called")
      eq(10, result_line, "Should return correct line number")
      eq("WARN No references", result_text, "Should show warning for zero references")
    end)

    it("should show reference count for functions with references", function()
      local handler_called = false
      local result_text = nil

      local callback = function(result)
        handler_called = true
        if result then
          result_text = result.text
        end
      end

      local func_info = {
        line = 15,
        name = "popular_function",
        character = 0
      }

      config.setup({ style = { use_nerdfont = false } })

      local mock_utils = {
        get_lsp_references = function(bufnr, func_info_param, callback_param)
          callback_param({1, 2, 3, 4, 5}) -- 5 references
        end,
        if_nerdfont_else = utils.if_nerdfont_else
      }

      with_stub("lensline.utils", mock_utils, function()
        local handler = function(bufnr, func_info, provider_config, callback)
          local utils = require("lensline.utils")
          
          utils.get_lsp_references(bufnr, func_info, function(references)
            if references then
              local count = #references
              local icon, text
              
              if count == 0 then
                icon = utils.if_nerdfont_else("⚠️ ", "WARN ")
                text = icon .. "No references"
              else
                icon = utils.if_nerdfont_else("󰌹 ", "")
                local suffix = utils.if_nerdfont_else("", " refs")
                text = icon .. count .. suffix
              end
              
              callback({ line = func_info.line, text = text })
            else
              callback(nil)
            end
          end)
        end

        handler(1, func_info, {}, callback)
      end)

      assert.is_true(handler_called)
      eq("5 refs", result_text, "Should show reference count")
    end)
  end)

  describe("Function Length Example", function()
    it("should calculate and display function line count", function()
      local handler_called = false
      local result_text = nil
      local result_line = nil

      local callback = function(result)
        handler_called = true
        if result then
          result_text = result.text
          result_line = result.line
        end
      end

      local func_info = {
        line = 20,
        name = "test_function",
        character = 0,
        end_line = 25 -- Function spans 6 lines (20-25)
      }

      -- Create a test buffer to get real line count behavior
      local test_bufnr = vim.api.nvim_create_buf(false, true)
      local test_lines = {}
      for i = 1, 100 do
        table.insert(test_lines, "line " .. i)
      end
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, test_lines)

      local mock_utils = {
        get_function_lines = function(bufnr, func_info_param)
          return {
            "function test_function()",
            "  local x = 1",
            "  if x > 0 then",
            "    return x + 1",
            "  end",
            "end"
          }
        end
      }

      with_stub("lensline.utils", mock_utils, function()
        local handler = function(bufnr, func_info, provider_config, callback)
          local utils = require("lensline.utils")
          local function_lines = utils.get_function_lines(bufnr, func_info)
          local func_line_count = math.max(0, #function_lines - 1) -- Subtract 1 for signature
          local total_lines = vim.api.nvim_buf_line_count(bufnr)
          
          callback({
            line = func_info.line,
            text = string.format("(%d/%d lines)", func_line_count, total_lines)
          })
        end

        handler(test_bufnr, func_info, {}, callback)
      end)

      -- Clean up test buffer
      vim.api.nvim_buf_delete(test_bufnr, { force = true })

      -- Verify results
      assert.is_true(handler_called, "Handler callback should be called")
      eq(20, result_line, "Should return correct line number")
      eq("(5/100 lines)", result_text, "Should show correct line count (6 lines - 1 for signature = 5)")
    end)

    it("should handle functions without end_line gracefully", function()
      local handler_called = false
      local result_text = nil

      local callback = function(result)
        handler_called = true
        if result then
          result_text = result.text
        end
      end

      local func_info = {
        line = 30,
        name = "incomplete_function",
        character = 0
        -- No end_line provided
      }

      -- Create a test buffer with 100 lines
      local test_bufnr = vim.api.nvim_create_buf(false, true)
      local test_lines = {}
      for i = 1, 100 do
        table.insert(test_lines, "line " .. i)
      end
      vim.api.nvim_buf_set_lines(test_bufnr, 0, -1, false, test_lines)

      local mock_utils = {
        get_function_lines = function(bufnr, func_info_param)
          return {
            "function incomplete_function()",
            "  -- function body"
          }
        end
      }

      with_stub("lensline.utils", mock_utils, function()
        local handler = function(bufnr, func_info, provider_config, callback)
          local utils = require("lensline.utils")
          local function_lines = utils.get_function_lines(bufnr, func_info)
          local func_line_count = math.max(0, #function_lines - 1)
          local total_lines = vim.api.nvim_buf_line_count(bufnr)
          
          callback({
            line = func_info.line,
            text = string.format("(%d/%d lines)", func_line_count, total_lines)
          })
        end

        handler(test_bufnr, func_info, {}, callback)
      end)

      -- Clean up test buffer
      vim.api.nvim_buf_delete(test_bufnr, { force = true })

      assert.is_true(handler_called)
      eq("(1/100 lines)", result_text, "Should handle missing end_line gracefully")
    end)
  end)

  describe("Provider Configuration Integration", function()
    it("should handle provider configuration parameters correctly", function()
      local handler_called = false
      local config_used = nil

      local callback = function(result)
        handler_called = true
      end

      local func_info = {
        line = 40,
        name = "configurable_function",
        character = 0
      }

      local provider_config = {
        custom_prefix = "TEST:",
        enabled = true
      }

      -- Test a handler that uses provider_config
      local handler = function(bufnr, func_info, provider_config, callback)
        config_used = provider_config
        local prefix = provider_config.custom_prefix or "DEFAULT:"
        
        callback({
          line = func_info.line,
          text = prefix .. " configured"
        })
      end

      handler(1, func_info, provider_config, callback)

      assert.is_true(handler_called)
      eq("TEST:", config_used.custom_prefix, "Should receive provider configuration")
      assert.is_true(config_used.enabled, "Should pass through configuration values")
    end)
  end)
end)