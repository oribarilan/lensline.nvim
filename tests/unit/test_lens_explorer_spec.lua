local eq = assert.are.same
local lens_explorer = require("lensline.lens_explorer")

-- Helper to temporarily patch vim.lsp.get_clients (newer API) or get_active_clients (older)
local function with_clients(clients, fn)
  local orig_get_clients = vim.lsp.get_clients
  local orig_get_active = vim.lsp.get_active_clients
  -- Provide both so code path choosing either works
  vim.lsp.get_clients = function(_) return clients end
  vim.lsp.get_active_clients = function(_) return clients end
  local ok, err = pcall(fn)
  vim.lsp.get_clients = orig_get_clients
  vim.lsp.get_active_clients = orig_get_active
  if not ok then error(err) end
end

describe("lens_explorer.has_lsp_capability()", function()
  it("no active clients returns false", function()
    with_clients({}, function()
      eq(false, lens_explorer.has_lsp_capability(0, "textDocument/references"))
    end)
  end)

  it("nil client list handled gracefully (returns false)", function()
    -- Simulate API returning nil
    local orig_get_clients = vim.lsp.get_clients
    local orig_get_active = vim.lsp.get_active_clients
    vim.lsp.get_clients = function(_) return nil end
    vim.lsp.get_active_clients = function(_) return nil end
    local ok, err = pcall(function()
      eq(false, lens_explorer.has_lsp_capability(0, "textDocument/references"))
    end)
    vim.lsp.get_clients = orig_get_clients
    vim.lsp.get_active_clients = orig_get_active
    if not ok then error(err) end
  end)

  it("single client with references capability returns true", function()
    with_clients({
      { name = "one", server_capabilities = { referencesProvider = true } }
    }, function()
      eq(true, lens_explorer.has_lsp_capability(0, "textDocument/references"))
    end)
  end)

  it("multiple clients: one lacking, one providing -> true", function()
    with_clients({
      { name = "a", server_capabilities = { referencesProvider = false } },
      { name = "b", server_capabilities = { referencesProvider = true } },
    }, function()
      eq(true, lens_explorer.has_lsp_capability(0, "textDocument/references"))
    end)
  end)

  it("documentSymbol capability respected", function()
    with_clients({
      { name = "sym", server_capabilities = { documentSymbolProvider = true } },
    }, function()
      eq(true, lens_explorer.has_lsp_capability(0, "textDocument/documentSymbol"))
      eq(false, lens_explorer.has_lsp_capability(0, "textDocument/references"))
    end)
  end)
end)