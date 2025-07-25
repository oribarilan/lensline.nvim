-- example configuration showing the new collector system
-- this demonstrates how users can customize and extend providers

-- import built-in collectors for customization
local lsp = require("lensline.providers.lsp")
local diagnostics = require("lensline.providers.diagnostics")

require("lensline").setup({
  debug_mode = true,  -- enable to see the new infrastructure in action
  
  providers = {
    lsp = {
      enabled = true,
      performance = { cache_ttl = 30000 },
      
      collectors = {
        -- use built-in collectors
        lsp.collectors.references,
        lsp.collectors.definitions,
        
        -- example: copy and customize built-in collector (just change format)
        function(lsp_context, function_info)
          -- copy references collector logic, modify format
          local cache_key = "refs:" .. function_info.line
          local cached = lsp_context.cache_get(cache_key)
          if cached then return "👁 %d", cached end
          
          local position = { line = function_info.line, character = function_info.character }
          -- simplified version for demo - could copy full logic from references.lua
          return "👁 refs", "?"  -- placeholder for demo
        end,
        
        -- example: completely custom collector
        function(lsp_context, function_info)
          -- user's custom logic here
          return "custom: %s", "demo"
        end
      }
    },
    
    diagnostics = {
      enabled = true,
      collectors = {
        diagnostics.collectors.function_level,
        
        -- example: custom diagnostics collector
        function(diagnostics_context, function_info)
          -- count only errors
          local error_count = 0
          for _, diag in ipairs(diagnostics_context.diagnostics) do
            if diag.severity == vim.diagnostic.severity.ERROR then
              error_count = error_count + 1
            end
          end
          if error_count > 0 then
            return "🔥 %d", error_count
          end
          return nil, nil
        end
      }
    }
  }
})

-- this file shows:
-- 1. how to import built-in collectors
-- 2. how to use them as-is
-- 3. how to copy and customize them
-- 4. how to create completely custom collectors
-- 5. all with the same simple function interface