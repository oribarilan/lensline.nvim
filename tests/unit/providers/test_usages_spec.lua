local eq = assert.are.same

local function with_stub(mod, stub, fn)
  local orig = package.loaded[mod]
  package.loaded[mod] = stub
  local ok, err = pcall(fn)
  package.loaded[mod] = orig
  if not ok then error(err) end
end

describe("providers.usages", function()
  local provider = require("lensline.providers.usages")
  
  -- Mock LSP clients with all capabilities supported
  local mock_lsp_clients_all_supported = {
    {
      server_capabilities = {
        referencesProvider = true,
        definitionProvider = true,
        implementationProvider = true,
      }
    }
  }
  
  -- Mock LSP clients with only references supported (like Python LSP)
  local mock_lsp_clients_refs_only = {
    {
      server_capabilities = {
        referencesProvider = true,
        definitionProvider = false,
        implementationProvider = false,
      }
    }
  }
  
  -- Mock LSP clients with no capabilities
  local mock_lsp_clients_none = {}

  describe("collapsed view (default)", function()
    it("aggregates all usage types when all LSP methods supported", function()
      local calls = {}
      
      -- Mock vim.lsp.get_clients to return clients with all capabilities
      local orig_get_clients = vim.lsp.get_clients
      vim.lsp.get_clients = function() return mock_lsp_clients_all_supported end
      
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb({ {}, {}, {} }) end,
        get_lsp_definitions = function(_, _, cb) cb({ {} }) end,
        get_lsp_implementations = function(_, _, cb) cb({ {}, {} }) end,
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return false end,
        }, function()
          provider.handler(7, { line = 7 }, {}, function(res) table.insert(calls, res) end)
        end)
      end)
      
      -- Restore original function
      vim.lsp.get_clients = orig_get_clients
      
      eq({ { line = 7, text = "6 usages" } }, calls)
    end)

    it("shows total with suffix when all LSP methods supported", function()
      local out
      
      -- Mock vim.lsp.get_clients to return clients with all capabilities
      local orig_get_clients = vim.lsp.get_clients
      vim.lsp.get_clients = function() return mock_lsp_clients_all_supported end
      
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb({ {} }) end,
        get_lsp_definitions = function(_, _, cb) cb({}) end,
        get_lsp_implementations = function(_, _, cb) cb({ {} }) end,
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return false end,
        }, function()
          provider.handler(9, { line = 9 }, {}, function(res) out = res end)
        end)
      end)
      
      -- Restore original function
      vim.lsp.get_clients = orig_get_clients
      
      eq({ line = 9, text = "2 usages" }, out)
    end)

    it("singular form for single usage when all LSP methods supported", function()
      local out
      
      -- Mock vim.lsp.get_clients to return clients with all capabilities
      local orig_get_clients = vim.lsp.get_clients
      vim.lsp.get_clients = function() return mock_lsp_clients_all_supported end
      
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb({ {} }) end,
        get_lsp_definitions = function(_, _, cb) cb({}) end,
        get_lsp_implementations = function(_, _, cb) cb({}) end,
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return false end,
        }, function()
          provider.handler(5, { line = 5 }, {}, function(res) out = res end)
        end)
      end)
      
      -- Restore original function
      vim.lsp.get_clients = orig_get_clients
      
      eq({ line = 5, text = "1 usage" }, out)
    end)

    it("shows zero usages when no usages found with all LSP methods supported", function()
      local out
      
      -- Mock vim.lsp.get_clients to return clients with all capabilities
      local orig_get_clients = vim.lsp.get_clients
      vim.lsp.get_clients = function() return mock_lsp_clients_all_supported end
      
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb({}) end,
        get_lsp_definitions = function(_, _, cb) cb({}) end,
        get_lsp_implementations = function(_, _, cb) cb({}) end,
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return false end,
        }, function()
          provider.handler(3, { line = 3 }, {}, function(res) out = res end)
        end)
      end)
      
      -- Restore original function
      vim.lsp.get_clients = orig_get_clients
      
      eq({ line = 3, text = "0 usages" }, out)
    end)
    
    it("shows only references when only references LSP method supported", function()
      local out
      
      -- Mock vim.lsp.get_clients to return clients with only references capability
      local orig_get_clients = vim.lsp.get_clients
      vim.lsp.get_clients = function() return mock_lsp_clients_refs_only end
      
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb({ {}, {}, {} }) end,
        get_lsp_definitions = function(_, _, cb) cb({ {} }) end, -- Won't be called
        get_lsp_implementations = function(_, _, cb) cb({ {}, {} }) end, -- Won't be called
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return false end,
        }, function()
          provider.handler(7, { line = 7 }, {}, function(res) out = res end)
        end)
      end)
      
      -- Restore original function
      vim.lsp.get_clients = orig_get_clients
      
      eq({ line = 7, text = "3 usages" }, out)
    end)
    
    it("does not call callback when no LSP methods are supported", function()
      local callback_called = false
      
      -- Mock vim.lsp.get_clients to return clients with no capabilities
      local orig_get_clients = vim.lsp.get_clients
      vim.lsp.get_clients = function() return mock_lsp_clients_none end
      
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb({ {} }) end, -- Won't be called
        get_lsp_definitions = function(_, _, cb) cb({ {} }) end, -- Won't be called
        get_lsp_implementations = function(_, _, cb) cb({ {} }) end, -- Won't be called
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return false end,
        }, function()
          provider.handler(1, { line = 1 }, {}, function(res) 
            callback_called = true
          end)
        end)
      end)
      
      -- Restore original function
      vim.lsp.get_clients = orig_get_clients
      
      eq(false, callback_called) -- Callback should not be called
    end)
  end)
  
  describe("expanded view", function()
    it("shows breakdown when all LSP methods supported", function()
      local out
      
      -- Mock vim.lsp.get_clients to return clients with all capabilities
      local orig_get_clients = vim.lsp.get_clients
      vim.lsp.get_clients = function() return mock_lsp_clients_all_supported end
      
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb({ {}, {}, {} }) end,
        get_lsp_definitions = function(_, _, cb) cb({ {} }) end,
        get_lsp_implementations = function(_, _, cb) cb({ {}, {} }) end,
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return true end,
        }, function()
          provider.handler(10, { line = 10 }, {}, function(res) out = res end)
        end)
      end)
      
      -- Restore original function
      vim.lsp.get_clients = orig_get_clients
      
      eq({ line = 10, text = "3 ref, 1 def, 2 impl" }, out)
    end)
    
    it("shows only supported methods in breakdown", function()
      local out
      
      -- Mock vim.lsp.get_clients to return clients with only references capability
      local orig_get_clients = vim.lsp.get_clients
      vim.lsp.get_clients = function() return mock_lsp_clients_refs_only end
      
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb({ {}, {}, {} }) end,
        get_lsp_definitions = function(_, _, cb) cb({ {} }) end, -- Won't be called
        get_lsp_implementations = function(_, _, cb) cb({ {}, {} }) end, -- Won't be called
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return true end,
        }, function()
          provider.handler(8, { line = 8 }, {}, function(res) out = res end)
        end)
      end)
      
      -- Restore original function
      vim.lsp.get_clients = orig_get_clients
      
      eq({ line = 8, text = "3 ref" }, out)
    end)
    
    it("shows zero buckets when configured and all LSP methods supported", function()
      local out
      
      -- Mock vim.lsp.get_clients to return clients with all capabilities
      local orig_get_clients = vim.lsp.get_clients
      vim.lsp.get_clients = function() return mock_lsp_clients_all_supported end
      
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb({ {} }) end,
        get_lsp_definitions = function(_, _, cb) cb({}) end,
        get_lsp_implementations = function(_, _, cb) cb({}) end,
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return true end,
        }, function()
          provider.handler(12, { line = 12 }, { show_zero_buckets = true }, function(res) out = res end)
        end)
      end)
      
      -- Restore original function
      vim.lsp.get_clients = orig_get_clients
      
      eq({ line = 12, text = "1 ref, 0 def, 0 impl" }, out)
    end)
    
    it("uses custom inner separator", function()
      local out
      
      -- Mock vim.lsp.get_clients to return clients with all capabilities
      local orig_get_clients = vim.lsp.get_clients
      vim.lsp.get_clients = function() return mock_lsp_clients_all_supported end
      
      with_stub("lensline.utils", {
        get_lsp_references = function(_, _, cb) cb({ {}, {} }) end,
        get_lsp_definitions = function(_, _, cb) cb({ {} }) end,
        get_lsp_implementations = function(_, _, cb) cb({}) end,
      }, function()
        with_stub("lensline.config", {
          get_usages_expanded = function() return true end,
        }, function()
          provider.handler(15, { line = 15 }, { inner_separator = " | " }, function(res) out = res end)
        end)
      end)
      
      -- Restore original function
      vim.lsp.get_clients = orig_get_clients
      
      eq({ line = 15, text = "2 ref | 1 def" }, out)
    end)
  end)
end)