local eq = assert.are.same

local function reset_modules()
  for name, _ in pairs(package.loaded) do
    if name:match("^lensline") then package.loaded[name] = nil end
  end
end

describe("lens_explorer.extract_symbols_recursive selectionRange support", function()
  before_each(reset_modules)
  after_each(reset_modules)

  it("uses selectionRange.start.character when available", function()
    local lens_explorer = require("lensline.lens_explorer")

    -- gopls DocumentSymbol for: func (c *Client) doWithRetry(...)
    local symbols = {
      {
        name = "(*Client).doWithRetry",
        kind = vim.lsp.protocol.SymbolKind.Method,
        range = {
          start = { line = 10, character = 0 },
          ["end"] = { line = 30, character = 1 },
        },
        selectionRange = {
          start = { line = 10, character = 22 },
          ["end"] = { line = 10, character = 33 },
        },
      },
    }

    local functions = {}
    lens_explorer.extract_symbols_recursive(symbols, functions, 1, 50)

    eq(1, #functions)
    eq("(*Client).doWithRetry", functions[1].name)
    eq(11, functions[1].line)
    eq(22, functions[1].character, "should use selectionRange character, not range character")
  end)

  it("falls back to range.start.character when selectionRange is absent", function()
    local lens_explorer = require("lensline.lens_explorer")

    local symbols = {
      {
        name = "doSomething",
        kind = vim.lsp.protocol.SymbolKind.Function,
        range = {
          start = { line = 5, character = 4 },
          ["end"] = { line = 10, character = 1 },
        },
      },
    }

    local functions = {}
    lens_explorer.extract_symbols_recursive(symbols, functions, 1, 20)

    eq(1, #functions)
    eq(4, functions[1].character, "should fall back to range.start.character")
  end)
end)

describe("utils qualified name resolution", function()
  local utils
  local created_buffers = {}

  local function make_buf(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    table.insert(created_buffers, bufnr)
    if lines and #lines > 0 then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    end
    return bufnr
  end

  local orig_lsp = {}

  before_each(function()
    reset_modules()
    utils = require("lensline.utils")
    created_buffers = {}
    orig_lsp = {}
  end)

  after_each(function()
    for _, bufnr in ipairs(created_buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    for key, fn in pairs(orig_lsp) do
      vim.lsp[key] = fn
    end
    reset_modules()
  end)

  local function stub_lsp_for_references(response)
    orig_lsp.get_clients = vim.lsp.get_clients
    orig_lsp.get_active_clients = vim.lsp.get_active_clients
    orig_lsp.buf_request = vim.lsp.buf_request

    local mock_client = {
      name = "gopls",
      server_capabilities = { referencesProvider = true, documentSymbolProvider = true },
    }
    vim.lsp.get_clients = function(_) return { mock_client } end
    vim.lsp.get_active_clients = function(_) return { mock_client } end

    local captured_params = nil
    vim.lsp.buf_request = function(bufnr, method, params, handler)
      if method == "textDocument/references" then
        captured_params = params
        handler(nil, response, {})
      end
    end

    return function() return captured_params end
  end

  it("resolves short name from qualified gopls method name", function()
    local bufnr = make_buf({
      "func (c *Client) doWithRetry(ctx context.Context, buildReq func() (*http.Request, error)) ([]byte, error) {",
    })

    local func_info = {
      line = 1,
      character = 0,
      name = "(*Client).doWithRetry",
    }

    local mock_refs = {
      { uri = "file:///test.go", range = { start = { line = 50, character = 10 } } },
      { uri = "file:///test.go", range = { start = { line = 60, character = 10 } } },
      { uri = "file:///test.go", range = { start = { line = 70, character = 10 } } },
    }

    local get_params = stub_lsp_for_references(mock_refs)

    local result = nil
    utils.get_lsp_references(bufnr, func_info, function(refs)
      result = refs
    end)

    eq(3, result and #result or 0, "should find 3 references")

    local params = get_params()
    assert.is_not_nil(params, "LSP request should have been made")
    -- "func (c *Client) doWithRetry..." -> "doWithRetry" starts at col 17
    eq(17, params.position.character, "should resolve to 'doWithRetry', not 'func'")
  end)

  it("works with non-qualified function names", function()
    local bufnr = make_buf({
      "func doRequest(httpClient *http.Client, req *http.Request) ([]byte, error) {",
    })

    local func_info = {
      line = 1,
      character = 0,
      name = "doRequest",
    }

    local mock_refs = {
      { uri = "file:///test.go", range = { start = { line = 50, character = 10 } } },
    }

    local get_params = stub_lsp_for_references(mock_refs)

    local result = nil
    utils.get_lsp_references(bufnr, func_info, function(refs)
      result = refs
    end)

    eq(1, result and #result or 0)

    local params = get_params()
    assert.is_not_nil(params)
    eq(5, params.position.character, "should resolve to 'doRequest' position")
  end)

  it("uses func_info.character as last resort when name not found in line", function()
    local bufnr = make_buf({
      "some unrelated line content",
    })

    local func_info = {
      line = 1,
      character = 7,
      name = "nonExistentFunction",
    }

    local get_params = stub_lsp_for_references({})

    utils.get_lsp_references(bufnr, func_info, function(_) end)

    local params = get_params()
    assert.is_not_nil(params)
    eq(7, params.position.character, "should fall back to func_info.character")
  end)
end)
