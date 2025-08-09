-- tests/unit/test_utils_spec.lua
-- Unit tests for lensline.utils (1-3 focused tests per public function)

local eq = assert.are.same
local utils = require("lensline.utils")
local config = require("lensline.config")

-- Helpers to stub modules
local function with_stub(module_name, stub_tbl, fn)
  local orig = package.loaded[module_name]
  package.loaded[module_name] = stub_tbl
  local ok, err = pcall(fn)
  package.loaded[module_name] = orig
  if not ok then error(err) end
end

describe("utils.style helpers", function()
  before_each(function()
    config.setup({})
  end)

  it("if_nerdfont_else picks nerdfont branch when enabled", function()
    config.setup({ style = { use_nerdfont = true } })
    eq("NF", utils.if_nerdfont_else("NF", "FB"))
  end)

  it("if_nerdfont_else picks fallback when disabled", function()
    config.setup({ style = { use_nerdfont = false } })
    eq("FB", utils.if_nerdfont_else("NF", "FB"))
  end)

  it("is_using_nerdfonts reflects config", function()
    config.setup({ style = { use_nerdfont = true } })
    eq(true, utils.is_using_nerdfonts())
    config.setup({ style = { use_nerdfont = false } })
    eq(false, utils.is_using_nerdfonts())
  end)
end)

describe("utils.is_valid_buffer()", function()
  it("returns true for a valid loaded buffer and false after wipe", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    eq(true, utils.is_valid_buffer(bufnr))
    vim.api.nvim_buf_delete(bufnr, { force = true })
    eq(false, utils.is_valid_buffer(bufnr))
  end)
end)

describe("utils.debounce()", function()
  it("invokes only last call within delay window", function()
    local calls = {}
    local fn = function(arg) table.insert(calls, arg) end
    local debounced, timer = utils.debounce(fn, 20)
    debounced(1)
    debounced(2)
    debounced(3)
    -- Wait until we get one call or timeout
    vim.wait(200, function() return #calls > 0 end)
    eq({ 3 }, calls)
    timer:stop()
    timer:close()
  end)
end)

describe("utils.get_function_lines()", function()
  local bufnr
  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
  end)
  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("returns direct slice when end_line provided", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "function foo()",
      "  return 42",
      "end",
      "print('after')",
    })
    local lines = utils.get_function_lines(bufnr, { line = 1, end_line = 3 })
    eq({ "function foo()", "  return 42", "end" }, lines)
  end)

  it("estimates end when end_line missing (brace counting)", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "function bar(x) {",
      "  if (x) {",
      "    return x + 1",
      "  }",
      "}", -- closing outer function
      "print('after')",
    })
    local lines = utils.get_function_lines(bufnr, { line = 1 }) -- no end_line
    eq({
      "function bar(x) {",
      "  if (x) {",
      "    return x + 1",
      "  }",
      "}",
    }, lines)
  end)

  it("applies safety limit when no closing brace within 100 lines", function()
    local lines_tbl = { "function long_fn() {" }
    for i = 1, 120 do
      lines_tbl[#lines_tbl + 1] = "  print('x')"
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines_tbl)
    local lines = utils.get_function_lines(bufnr, { line = 1 })
    eq(101, #lines) -- 1 function line + 100 additional due to safety cap
  end)
end)

describe("utils.has_lsp_references_capability()", function()
  it("returns false when no clients", function()
    with_stub("lensline.lens_explorer", {
      get_lsp_clients = function() return {} end,
      has_lsp_capability = function() return false end,
    }, function()
      eq(false, utils.has_lsp_references_capability(0))
    end)
  end)

  it("returns true when capability present", function()
    with_stub("lensline.lens_explorer", {
      get_lsp_clients = function() return { { name = "dummy" } } end,
      has_lsp_capability = function(_, _) return true end,
    }, function()
      eq(true, utils.has_lsp_references_capability(0))
    end)
  end)
end)

describe("utils.get_lsp_references()", function()
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
    with_stub("lensline.debug", {
      log_context = function() end,
    }, function()
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
        -- Ensure an error log line was produced
        local joined = table.concat(debug_msgs, "\n")
        eq(true, joined:match("request error") ~= nil)
      end)
    end)
  end)
end)
-- Additional utility tests (section 6 TODO items)

describe("utils.debounce() manual cancellation", function()
  it("stopping + closing timer prevents scheduled call", function()
    local utils = require("lensline.utils")
    local calls = 0
    local debounced, timer = utils.debounce(function() calls = calls + 1 end, 60)
    debounced()
    -- Cancel before it fires
    timer:stop()
    timer:close()
    vim.wait(120, function() return calls > 0 end)
    eq(0, calls)
  end)
end)

describe("utils.is_using_nerdfonts() pre-setup", function()
  it("returns false before config.setup invoked", function()
    package.loaded["lensline.config"] = nil
    local cfg = require("lensline.config") -- reloaded (options empty)
    package.loaded["lensline.config"] = cfg
    local utils = require("lensline.utils")
    eq(false, utils.is_using_nerdfonts())
  end)
end)

describe("utils.get_function_lines braces in strings/comments", function()
  it("ignores braces inside strings so function not cut early", function()
    local utils = require("lensline.utils")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "function foo() {",
      "  local s = \"not a real } brace\" -- } inside comment too",
      "}",
      "after()",
    })
    local lines = utils.get_function_lines(buf, { line = 1 })
    eq({ "function foo() {", "  local s = \"not a real } brace\" -- } inside comment too", "}" }, lines)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)