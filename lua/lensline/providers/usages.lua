-- Usages Provider
-- Shows aggregated count of references, definitions, and implementations
-- Supports toggle between total count and breakdown view
return {
  name = "usages",
  event = { "LspAttach", "BufWritePost" },
  handler = function(bufnr, func_info, provider_config, callback)
    local utils = require("lensline.utils")
    local config = require("lensline.config")
    
    -- Track completion of async LSP calls
    local results = { refs = nil, defs = nil, impls = nil }
    local completed = 0
    local total_calls = 3
    
    local function check_completion()
      completed = completed + 1
      if completed == total_calls then
        -- All LSP calls complete, aggregate results
        local ref_count = results.refs and #results.refs or 0
        local def_count = results.defs and #results.defs or 0
        local impl_count = results.impls and #results.impls or 0
        local total_count = ref_count + def_count + impl_count
        
        -- Check if toggle is enabled for expanded view
        local show_expanded = config.get_usages_expanded()
        
        local text
        local show_zero_buckets = provider_config.show_zero_buckets or false
        
        if show_expanded and (total_count > 0 or show_zero_buckets) then
          -- Show breakdown: "3 ref, 1 def, 2 impl"
          local parts = {}
          local inner_separator = provider_config.inner_separator or ", "
          
          if ref_count > 0 or show_zero_buckets then
            table.insert(parts, ref_count .. " ref")
          end
          if def_count > 0 or show_zero_buckets then
            table.insert(parts, def_count .. " def")
          end
          if impl_count > 0 or show_zero_buckets then
            table.insert(parts, impl_count .. " impl")
          end
          
          text = table.concat(parts, inner_separator)
        else
          -- Show total: "6 usages" / "1 usage" (no icons, just text)
          local suffix = total_count == 1 and " usage" or " usages"
          text = total_count .. suffix
        end
        
        callback({
          line = func_info.line,
          text = text
        })
      end
    end
    
    -- Make async LSP requests
    utils.get_lsp_references(bufnr, func_info, function(references)
      results.refs = references
      check_completion()
    end)
    
    utils.get_lsp_definitions(bufnr, func_info, function(definitions)
      results.defs = definitions
      check_completion()
    end)
    
    utils.get_lsp_implementations(bufnr, func_info, function(implementations)
      results.impls = implementations
      check_completion()
    end)
  end
}