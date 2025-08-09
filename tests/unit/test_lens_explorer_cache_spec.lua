local eq = assert.are.same

-- Test lens_explorer async discovery cache + LRU eviction behavior
-- Focused paths:
--   Cache miss populates cache ([lua/lensline/lens_explorer.lua:171])
--   Cache hit with unchanged changedtick returns cached path ([lua/lensline/lens_explorer.lua:122])
--   Changed buffer (changedtick) triggers fresh LSP call
--   LRU eviction when cache size exceeds MAX_CACHE_SIZE (default 50) ([lua/lensline/lens_explorer.lua:26])

describe("lens_explorer async discovery cache & LRU eviction", function()
  local lens_explorer
  local original_buf_request
  local request_calls
  local function reset_request_stub()
    request_calls = 0
    vim.lsp.buf_request = function(bufnr, method, params, handler)
      request_calls = request_calls + 1
      -- Simulate one function symbol for this buffer
      local line0 = 0 -- zero indexed
      local result = {
        {
          name = "fn_" .. bufnr,
          kind = vim.lsp.protocol.SymbolKind.Function,
          range = {
            start = { line = line0, character = 0 },
            ["end"] = { line = line0, character = 10 },
          }
        }
      }
      -- Async-style callback (simulate short delay)
      vim.defer_fn(function()
        handler(nil, result, {})
      end, 5)
    end
  end

  before_each(function()
    package.loaded["lensline.lens_explorer"] = nil
    package.loaded["lensline.debug"] = { log_context = function() end }
    original_buf_request = vim.lsp.buf_request
    reset_request_stub()
    lens_explorer = require("lensline.lens_explorer")

    -- Stub client/capability helpers to always allow document symbols
    lens_explorer.get_lsp_clients = function(_) return {
      { name = "dummy", server_capabilities = { documentSymbolProvider = true } }
    } end
    lens_explorer.has_lsp_capability = function(_, _) return true end

    -- Clear internal caches (wipe existing table; do not reassign to preserve internal reference)
    if lens_explorer.function_cache then
      for k in pairs(lens_explorer.function_cache) do
        lens_explorer.function_cache[k] = nil
      end
    end
  end)

  after_each(function()
    vim.lsp.buf_request = original_buf_request
  end)

  it("cache miss then hit then invalidation via changedtick", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1" })

    local first_funcs
    lens_explorer.discover_functions_async(bufnr, 1, 1, function(funcs)
      first_funcs = funcs
    end)

    vim.wait(300, function() return first_funcs ~= nil end)
    eq(1, request_calls) -- initial LSP call
    eq(1, #first_funcs)
    -- (Cache presence not asserted directly to avoid internal pointer brittleness)

    -- Second call without buffer modification -> cache hit (no new request)
    local second_funcs
    lens_explorer.discover_functions_async(bufnr, 1, 1, function(funcs)
      second_funcs = funcs
    end)
    vim.wait(200, function() return second_funcs ~= nil end)
    eq(1, request_calls) -- still one request
    eq(1, #second_funcs)
    -- Modify buffer to change changedtick
    vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "line2" })

    local third_funcs
    lens_explorer.discover_functions_async(bufnr, 1, 2, function(funcs)
      third_funcs = funcs
    end)
    vim.wait(300, function() return third_funcs ~= nil end)
    eq(2, request_calls) -- second LSP call due to changedtick
    eq(1, #third_funcs)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("LRU eviction removes oldest entry after exceeding MAX_CACHE_SIZE (shrunk for test)", function()
    -- Shrink cache size for deterministic + fast eviction scenario
    if lens_explorer._set_max_cache_size_for_test then
      lens_explorer._set_max_cache_size_for_test(5)
    end
    local NEW_MAX = 5
    local TARGET = 8 -- create 8 buffers so first 3 should be evicted (5 retained)
    local created = {}
    local callbacks_completed = 0

    for i = 1, TARGET do
      local b = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(b, 0, -1, false, { "buf" .. i })
      created[#created + 1] = b
      lens_explorer.discover_functions_async(b, 1, 1, function()
        callbacks_completed = callbacks_completed + 1
      end)
    end

    -- Allow async symbol callbacks to finish (5ms each + overhead)
    vim.wait(600, function() return callbacks_completed == TARGET end)

    local count = 0
    for _ in pairs(lens_explorer.function_cache) do count = count + 1 end
    assert.is_true(count <= NEW_MAX, "expected cache size <= " .. NEW_MAX .. ", got " .. count)

    -- Oldest buffer should have been evicted deterministically
    assert.is_nil(lens_explorer.function_cache[created[1]], "expected oldest buffer to be evicted")

    -- Newest buffer should still be present
    assert.is_not_nil(lens_explorer.function_cache[created[#created]], "expected newest buffer to remain in cache")

    -- Cleanup all created buffers
    for _, b in ipairs(created) do
      if vim.api.nvim_buf_is_valid(b) then
        vim.api.nvim_buf_delete(b, { force = true })
      end
    end
  end)
end)