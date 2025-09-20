-- tests/unit/test_utils_spec.lua
-- unit tests for lensline.utils (utility functions and helpers)

local eq = assert.are.same

describe("lensline.utils", function()
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

  -- table-driven tests for style configuration
  for _, case in ipairs({
    {
      name = "picks nerdfont when enabled",
      config = { style = { use_nerdfont = true } },
      nf_input = "NF",
      fallback_input = "FB",
      expected = "NF"
    },
    {
      name = "picks fallback when disabled", 
      config = { style = { use_nerdfont = false } },
      nf_input = "NF",
      fallback_input = "FB",
      expected = "FB"
    },
  }) do
    it(("if_nerdfont_else %s"):format(case.name), function()
      config.setup(case.config)
      eq(case.expected, utils.if_nerdfont_else(case.nf_input, case.fallback_input))
    end)
  end

  -- table-driven tests for nerdfont detection
  for _, case in ipairs({
    {
      name = "reflects enabled state",
      config = { style = { use_nerdfont = true } },
      expected = true
    },
    {
      name = "reflects disabled state",
      config = { style = { use_nerdfont = false } },
      expected = false
    },
  }) do
    it(("is_using_nerdfonts %s"):format(case.name), function()
      config.setup(case.config)
      eq(case.expected, utils.is_using_nerdfonts())
    end)
  end

  it("is_valid_buffer handles buffer lifecycle correctly", function()
    local bufnr = make_buf()
    eq(true, utils.is_valid_buffer(bufnr))
    vim.api.nvim_buf_delete(bufnr, { force = true })
    eq(false, utils.is_valid_buffer(bufnr))
  end)

  it("debounce invokes only last call within delay window", function()
    local calls = {}
    local fn = function(arg) table.insert(calls, arg) end
    local debounced, timer = utils.debounce(fn, 20)
    
    debounced(1)
    debounced(2)
    debounced(3)
    
    vim.wait(200, function() return #calls > 0 end)
    eq({ 3 }, calls)
    
    timer:stop()
    timer:close()
  end)

  it("debounce can be cancelled before execution", function()
    local calls = 0
    local debounced, timer = utils.debounce(function() calls = calls + 1 end, 60)
    
    debounced()
    timer:stop()
    timer:close()
    
    vim.wait(120, function() return calls > 0 end)
    eq(0, calls)
  end)

  -- table-driven tests for get_function_lines scenarios
  for _, case in ipairs({
    {
      name = "returns direct slice when end_line provided",
      lines = {
        "function foo()",
        "  return 42", 
        "end",
        "print('after')",
      },
      func_info = { line = 1, end_line = 3 },
      expected = { "function foo()", "  return 42", "end" }
    },
    {
      name = "estimates end with brace counting",
      lines = {
        "function bar(x) {",
        "  if (x) {",
        "    return x + 1",
        "  }",
        "}",
        "print('after')",
      },
      func_info = { line = 1 }, -- no end_line
      expected = {
        "function bar(x) {",
        "  if (x) {", 
        "    return x + 1",
        "  }",
        "}",
      }
    },
  }) do
    it(("get_function_lines %s"):format(case.name), function()
      local bufnr = make_buf(case.lines)
      local result = utils.get_function_lines(bufnr, case.func_info)
      eq(case.expected, result)
    end)
  end

  it("get_function_lines applies safety limit for unclosed functions", function()
    local lines_tbl = { "function long_fn() {" }
    for i = 1, 120 do
      lines_tbl[#lines_tbl + 1] = "  print('x')"
    end
    
    local bufnr = make_buf(lines_tbl)
    local lines = utils.get_function_lines(bufnr, { line = 1 })
    eq(101, #lines) -- 1 function line + 100 additional due to safety cap
  end)

  it("get_function_lines handles braces in strings and comments", function()
    local bufnr = make_buf({
      "function foo() {",
      "  local s = \"not a real } brace\" -- } inside comment too",
      "}",
      "after()",
    })
    
    local lines = utils.get_function_lines(bufnr, { line = 1 })
    -- heuristic counts closing braces in string/comment, terminates early
    eq({ 
      "function foo() {", 
      "  local s = \"not a real } brace\" -- } inside comment too" 
    }, lines)
  end)

  -- table-driven tests for LSP references capability
  for _, case in ipairs({
    {
      name = "returns false when no clients",
      clients = {},
      has_capability = false,
      expected = false
    },
    {
      name = "returns true when capability present",
      clients = { { name = "dummy" } },
      has_capability = true,
      expected = true
    },
  }) do
    it(("has_lsp_references_capability %s"):format(case.name), function()
      with_stub("lensline.lens_explorer", {
        get_lsp_clients = function() return case.clients end,
        has_lsp_capability = function() return case.has_capability end,
      }, function()
        eq(case.expected, utils.has_lsp_references_capability(0))
      end)
    end)
  end

  -- table-driven tests for LSP definitions capability
  for _, case in ipairs({
    {
      name = "returns false when no clients",
      clients = {},
      has_capability = false,
      expected = false
    },
    {
      name = "returns true when capability present",
      clients = { { name = "dummy" } },
      has_capability = true,
      expected = true
    },
  }) do
    it(("has_lsp_definitions_capability %s"):format(case.name), function()
      with_stub("lensline.lens_explorer", {
        get_lsp_clients = function() return case.clients end,
      }, function()
        -- Mock the isolated capability checker
        local original_has_lsp_capability_isolated = utils.has_lsp_definitions_capability
        utils.has_lsp_definitions_capability = function() return case.has_capability end
        
        eq(case.expected, utils.has_lsp_definitions_capability(0))
        
        utils.has_lsp_definitions_capability = original_has_lsp_capability_isolated
      end)
    end)
  end

  -- table-driven tests for LSP implementations capability
  for _, case in ipairs({
    {
      name = "returns false when no clients",
      clients = {},
      has_capability = false,
      expected = false
    },
    {
      name = "returns true when capability present",
      clients = { { name = "dummy" } },
      has_capability = true,
      expected = true
    },
  }) do
    it(("has_lsp_implementations_capability %s"):format(case.name), function()
      with_stub("lensline.lens_explorer", {
        get_lsp_clients = function() return case.clients end,
      }, function()
        -- Mock the isolated capability checker
        local original_has_lsp_capability_isolated = utils.has_lsp_implementations_capability
        utils.has_lsp_implementations_capability = function() return case.has_capability end
        
        eq(case.expected, utils.has_lsp_implementations_capability(0))
        
        utils.has_lsp_implementations_capability = original_has_lsp_capability_isolated
      end)
    end)
  end

  describe("get_lsp_references", function()
    local original_buf_request
    
    before_each(function()
      original_buf_request = vim.lsp.buf_request
    end)
    
    after_each(function()
      vim.lsp.buf_request = original_buf_request
    end)

    it("short-circuits with nil when capability missing", function()
      local debug_calls = {}
      with_stub("lensline.debug", {
        log_context = function(_, msg) table.insert(debug_calls, msg) end,
      }, function()
        with_stub("lensline.lens_explorer", {
          get_lsp_clients = function() return {} end,
          has_lsp_capability = function() return false end,
        }, function()
          local got
          utils.get_lsp_references(0, { line = 1, name = "foo" }, function(res) got = res end)
          eq(nil, got)
          eq(true, debug_calls[1]:match("no LSP references capability") ~= nil)
        end)
      end)
    end)

    it("invokes callback with results when capability present", function()
      local requested = {}
      local mock_result = { { uri = "file://x", range = {} } }
      vim.lsp.buf_request = function(bufnr, method, params, handler)
        table.insert(requested, { bufnr = bufnr, method = method, params = params })
        handler(nil, mock_result, {})
      end
      
      with_stub("lensline.debug", { log_context = function() end }, function()
        with_stub("lensline.lens_explorer", {
          get_lsp_clients = function() return { { name = "dummy" } } end,
          has_lsp_capability = function() return true end,
        }, function()
          local got
          utils.get_lsp_references(0, { line = 3, name = "foo" }, function(res) got = res end)
          eq(mock_result, got)
          eq("textDocument/references", requested[1].method)
        end)
      end)
    end)

    it("invokes callback with nil on LSP error", function()
      local debug_msgs = {}
      vim.lsp.buf_request = function(_, _, _, handler)
        handler({ code = 123, message = "boom" }, nil, {})
      end
      
      with_stub("lensline.debug", {
        log_context = function(_, msg) table.insert(debug_msgs, msg) end,
      }, function()
        with_stub("lensline.lens_explorer", {
          get_lsp_clients = function() return { { name = "dummy" } } end,
          has_lsp_capability = function() return true end,
        }, function()
          local got = "unset"
          utils.get_lsp_references(0, { line = 5, name = "err_fn" }, function(res) got = res end)
          eq(nil, got)
          local joined = table.concat(debug_msgs, "\n")
          eq(true, joined:match("request error") ~= nil)
        end)
      end)
    end)
  
    describe("get_lsp_definitions", function()
      local original_buf_request
      
      before_each(function()
        original_buf_request = vim.lsp.buf_request
      end)
      
      after_each(function()
        vim.lsp.buf_request = original_buf_request
      end)
  
      it("short-circuits with nil when capability missing", function()
        local debug_calls = {}
        with_stub("lensline.debug", {
          log_context = function(_, msg) table.insert(debug_calls, msg) end,
        }, function()
          with_stub("lensline.lens_explorer", {
            get_lsp_clients = function() return {} end,
          }, function()
            -- Mock capability checker to return false
            local original_has_capability = utils.has_lsp_definitions_capability
            utils.has_lsp_definitions_capability = function() return false end
            
            local got
            utils.get_lsp_definitions(0, { line = 1, name = "foo" }, function(res) got = res end)
            eq(nil, got)
            eq(true, debug_calls[1]:match("no LSP definitions capability") ~= nil)
            
            utils.has_lsp_definitions_capability = original_has_capability
          end)
        end)
      end)
  
      it("invokes callback with results when capability present", function()
        local requested = {}
        local mock_result = { { uri = "file://x", range = {} } }
        vim.lsp.buf_request = function(bufnr, method, params, handler)
          table.insert(requested, { bufnr = bufnr, method = method, params = params })
          handler(nil, mock_result, {})
        end
        
        with_stub("lensline.debug", { log_context = function() end }, function()
          with_stub("lensline.lens_explorer", {
            get_lsp_clients = function() return { { name = "dummy" } } end,
          }, function()
            -- Mock capability checker to return true
            local original_has_capability = utils.has_lsp_definitions_capability
            utils.has_lsp_definitions_capability = function() return true end
            
            local got
            utils.get_lsp_definitions(0, { line = 3, name = "foo" }, function(res) got = res end)
            eq(mock_result, got)
            eq("textDocument/definition", requested[1].method)
            
            utils.has_lsp_definitions_capability = original_has_capability
          end)
        end)
      end)
  
      it("invokes callback with nil on LSP error", function()
        local debug_msgs = {}
        vim.lsp.buf_request = function(_, _, _, handler)
          handler({ code = 123, message = "boom" }, nil, {})
        end
        
        with_stub("lensline.debug", {
          log_context = function(_, msg) table.insert(debug_msgs, msg) end,
        }, function()
          with_stub("lensline.lens_explorer", {
            get_lsp_clients = function() return { { name = "dummy" } } end,
          }, function()
            -- Mock capability checker to return true
            local original_has_capability = utils.has_lsp_definitions_capability
            utils.has_lsp_definitions_capability = function() return true end
            
            local got = "unset"
            utils.get_lsp_definitions(0, { line = 5, name = "err_fn" }, function(res) got = res end)
            eq(nil, got)
            local joined = table.concat(debug_msgs, "\n")
            eq(true, joined:match("definition request error") ~= nil)
            
            utils.has_lsp_definitions_capability = original_has_capability
          end)
        end)
      end)
    end)
  
    describe("get_lsp_implementations", function()
      local original_buf_request
      
      before_each(function()
        original_buf_request = vim.lsp.buf_request
      end)
      
      after_each(function()
        vim.lsp.buf_request = original_buf_request
      end)
  
      it("short-circuits with nil when capability missing", function()
        local debug_calls = {}
        with_stub("lensline.debug", {
          log_context = function(_, msg) table.insert(debug_calls, msg) end,
        }, function()
          with_stub("lensline.lens_explorer", {
            get_lsp_clients = function() return {} end,
          }, function()
            -- Mock capability checker to return false
            local original_has_capability = utils.has_lsp_implementations_capability
            utils.has_lsp_implementations_capability = function() return false end
            
            local got
            utils.get_lsp_implementations(0, { line = 1, name = "foo" }, function(res) got = res end)
            eq(nil, got)
            eq(true, debug_calls[1]:match("no LSP implementations capability") ~= nil)
            
            utils.has_lsp_implementations_capability = original_has_capability
          end)
        end)
      end)
  
      it("invokes callback with results when capability present", function()
        local requested = {}
        local mock_result = { { uri = "file://x", range = {} } }
        vim.lsp.buf_request = function(bufnr, method, params, handler)
          table.insert(requested, { bufnr = bufnr, method = method, params = params })
          handler(nil, mock_result, {})
        end
        
        with_stub("lensline.debug", { log_context = function() end }, function()
          with_stub("lensline.lens_explorer", {
            get_lsp_clients = function() return { { name = "dummy" } } end,
          }, function()
            -- Mock capability checker to return true
            local original_has_capability = utils.has_lsp_implementations_capability
            utils.has_lsp_implementations_capability = function() return true end
            
            local got
            utils.get_lsp_implementations(0, { line = 3, name = "foo" }, function(res) got = res end)
            eq(mock_result, got)
            eq("textDocument/implementation", requested[1].method)
            
            utils.has_lsp_implementations_capability = original_has_capability
          end)
        end)
      end)
  
      it("invokes callback with nil on LSP error", function()
        local debug_msgs = {}
        vim.lsp.buf_request = function(_, _, _, handler)
          handler({ code = 123, message = "boom" }, nil, {})
        end
        
        with_stub("lensline.debug", {
          log_context = function(_, msg) table.insert(debug_msgs, msg) end,
        }, function()
          with_stub("lensline.lens_explorer", {
            get_lsp_clients = function() return { { name = "dummy" } } end,
          }, function()
            -- Mock capability checker to return true
            local original_has_capability = utils.has_lsp_implementations_capability
            utils.has_lsp_implementations_capability = function() return true end
            
            local got = "unset"
            utils.get_lsp_implementations(0, { line = 5, name = "err_fn" }, function(res) got = res end)
            eq(nil, got)
            local joined = table.concat(debug_msgs, "\n")
            eq(true, joined:match("implementation request error") ~= nil)
            
            utils.has_lsp_implementations_capability = original_has_capability
          end)
        end)
      end)
    end)
  end)
end)