-- tests/unit/test_custom_provider_examples_spec.lua
-- tests for custom provider examples to verify they work as documented

local eq = assert.are.same

describe("custom provider examples", function()
  local utils = require("lensline.utils")
  local config = require("lensline.config")
  local created_buffers = {}

  local function reset_modules()
    for name,_ in pairs(package.loaded) do
      if name:match("^lensline") then package.loaded[name] = nil end
    end
    utils = require("lensline.utils")
    config = require("lensline.config")
  end

  local function with_stub(module_name, stub_tbl, fn)
    local orig = package.loaded[module_name]
    package.loaded[module_name] = stub_tbl
    local ok, err = pcall(fn)
    package.loaded[module_name] = orig
    if not ok then error(err) end
  end

  local function make_buf(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    table.insert(created_buffers, bufnr)
    if lines and #lines > 0 then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    end
    return bufnr
  end

  -- reference counter provider handler from examples
  local function reference_counter_handler(bufnr, func_info, provider_config, callback)
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

  -- function length provider handler from examples
  local function function_length_handler(bufnr, func_info, provider_config, callback)
    local utils = require("lensline.utils")
    local function_lines = utils.get_function_lines(bufnr, func_info)
    local func_line_count = math.max(0, #function_lines - 1) -- subtract 1 for signature
    local total_lines = vim.api.nvim_buf_line_count(bufnr)
    
    callback({
      line = func_info.line,
      text = string.format("(%d/%d lines)", func_line_count, total_lines)
    })
  end

  before_each(function()
    reset_modules()
    created_buffers = {}
  end)

  after_each(function()
    for _, bufnr in ipairs(created_buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    reset_modules()
  end)

  -- table-driven tests for reference counter examples
  for _, case in ipairs({
    {
      name = "shows warning for zero references (no nerdfont)",
      use_nerdfont = false,
      references = {},
      expected_text = "WARN No references"
    },
    {
      name = "shows warning for zero references (with nerdfont)",
      use_nerdfont = true,
      references = {},
      expected_text = "⚠️ No references"
    },
    {
      name = "shows reference count (no nerdfont)",
      use_nerdfont = false,
      references = {1, 2, 3, 4, 5},
      expected_text = "5 refs"
    },
    {
      name = "shows reference count (with nerdfont)",
      use_nerdfont = true,
      references = {1, 2, 3, 4, 5},
      expected_text = "󰌹 5"
    }
  }) do
    it(("reference counter: %s"):format(case.name), function()
      config.setup({ style = { use_nerdfont = case.use_nerdfont } })
      
      local func_info = { line = 10, name = "test_function", character = 0 }
      local result = nil
      local called = false

      local mock_utils = {
        get_lsp_references = function(bufnr, func_info_param, callback_param)
          callback_param(case.references)
        end,
        if_nerdfont_else = utils.if_nerdfont_else
      }

      with_stub("lensline.utils", mock_utils, function()
        reference_counter_handler(1, func_info, {}, function(res)
          called = true
          result = res
        end)
      end)

      eq(true, called)
      eq({ line = 10, text = case.expected_text }, result)
    end)
  end

  it("reference counter handles nil references gracefully", function()
    config.setup({ style = { use_nerdfont = false } })
    
    local func_info = { line = 5, name = "test_function", character = 0 }
    local result = "unset"
    local called = false

    local mock_utils = {
      get_lsp_references = function(bufnr, func_info_param, callback_param)
        callback_param(nil) -- simulate LSP failure
      end,
      if_nerdfont_else = utils.if_nerdfont_else
    }

    with_stub("lensline.utils", mock_utils, function()
      reference_counter_handler(1, func_info, {}, function(res)
        called = true
        result = res
      end)
    end)

    eq(true, called)
    eq(nil, result)
  end)

  -- table-driven tests for function length examples
  for _, case in ipairs({
    {
      name = "calculates function length with end_line",
      func_lines = {
        "function test_function()",
        "  local x = 1",
        "  if x > 0 then",
        "    return x + 1",
        "  end",
        "end"
      },
      buffer_total_lines = 100,
      expected_text = "(5/100 lines)" -- 6 lines - 1 for signature = 5
    },
    {
      name = "handles short functions",
      func_lines = {
        "function short()",
        "  return 42",
        "end"
      },
      buffer_total_lines = 50,
      expected_text = "(2/50 lines)" -- 3 lines - 1 for signature = 2
    },
    {
      name = "handles single line functions",
      func_lines = {
        "function single() end"
      },
      buffer_total_lines = 20,
      expected_text = "(0/20 lines)" -- 1 line - 1 for signature = 0 (max with 0)
    }
  }) do
    it(("function length: %s"):format(case.name), function()
      local bufnr = make_buf({})
      -- set up buffer with correct total line count
      local buffer_lines = {}
      for i = 1, case.buffer_total_lines do
        buffer_lines[i] = "line " .. i
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, buffer_lines)
      
      local func_info = { line = 20, name = "test_function", character = 0 }
      local result = nil
      local called = false

      local mock_utils = {
        get_function_lines = function(bufnr, func_info_param)
          return case.func_lines
        end
      }

      with_stub("lensline.utils", mock_utils, function()
        function_length_handler(bufnr, func_info, {}, function(res)
          called = true
          result = res
        end)
      end)

      eq(true, called)
      eq({ line = 20, text = case.expected_text }, result)
    end)
  end

  it("provider configuration integration works correctly", function()
    local func_info = { line = 40, name = "configurable_function", character = 0 }
    local provider_config = { custom_prefix = "TEST:", enabled = true }
    local result = nil
    local called = false
    local received_config = nil

    local handler = function(bufnr, func_info, provider_config, callback)
      received_config = provider_config
      local prefix = provider_config.custom_prefix or "DEFAULT:"
      
      callback({
        line = func_info.line,
        text = prefix .. " configured"
      })
    end

    handler(1, func_info, provider_config, function(res)
      called = true
      result = res
    end)

    eq(true, called)
    eq({ line = 40, text = "TEST: configured" }, result)
    eq("TEST:", received_config.custom_prefix)
    eq(true, received_config.enabled)
  end)
end)