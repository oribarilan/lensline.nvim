-- Usages Provider
-- Shows aggregated count of references, definitions, and implementations
-- Supports toggle between total count and breakdown view
return {
  name = "usages",
  event = { "LspAttach", "BufWritePost" },
  handler = function(bufnr, func_info, provider_config, callback)
    local utils = require("lensline.utils")
    local config = require("lensline.config")
    
    -- Self-contained LSP capability checking
    local function check_lsp_capability(method)
      local clients = vim.lsp.get_clients and vim.lsp.get_clients({ bufnr = bufnr }) or vim.lsp.get_active_clients({ bufnr = bufnr })
      if not clients or #clients == 0 then
        return false
      end
      
      local capability_map = {
        ["textDocument/references"] = "referencesProvider",
        ["textDocument/definition"] = "definitionProvider",
        ["textDocument/implementation"] = "implementationProvider",
      }
      
      for _, client in ipairs(clients) do
        if client.server_capabilities and client.server_capabilities[capability_map[method]] then
          return true
        end
      end
      return false
    end
    
    -- Define available LSP methods and check which are supported
    local methods_to_check = {
      { method = "textDocument/references", func = utils.get_lsp_references, key = "refs", label = "ref" },
      { method = "textDocument/definition", func = utils.get_lsp_definitions, key = "defs", label = "def" },
      { method = "textDocument/implementation", func = utils.get_lsp_implementations, key = "impls", label = "impl" }
    }
    
    local supported_methods = {}
    for _, method_info in ipairs(methods_to_check) do
      if check_lsp_capability(method_info.method) then
        table.insert(supported_methods, method_info)
      end
    end
    
    -- Early exit if no LSP methods are supported - don't show provider at all
    if #supported_methods == 0 then
      return -- Don't call callback - provider will show nothing
    end
    
    -- Track completion of async LSP calls (only for supported methods)
    local results = {}
    local completed = 0
    local expected_calls = #supported_methods
    local timeout_timer = nil
    
    local function check_completion()
      completed = completed + 1
      if completed == expected_calls then
        -- Cancel timeout timer if all calls completed
        if timeout_timer then
          timeout_timer:stop()
          timeout_timer:close()
        end
        
        -- All supported LSP calls complete, aggregate results
        local counts = {}
        local total_count = 0
        
        for _, method_info in ipairs(supported_methods) do
          local count = results[method_info.key] and #results[method_info.key] or 0
          counts[method_info.key] = count
          total_count = total_count + count
        end
        
        -- Check if toggle is enabled for expanded view
        local show_expanded = config.get_usages_expanded()
        
        local text
        local show_zero_buckets = provider_config.show_zero_buckets or false
        
        if show_expanded and (total_count > 0 or show_zero_buckets) then
          -- Show breakdown: "3 ref, 1 def" (only for supported methods)
          local parts = {}
          local inner_separator = provider_config.inner_separator or ", "
          
          for _, method_info in ipairs(supported_methods) do
            local count = counts[method_info.key]
            if count > 0 or show_zero_buckets then
              table.insert(parts, count .. " " .. method_info.label)
            end
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
    
    -- Set up timeout to prevent indefinite waiting (5 seconds)
    timeout_timer = vim.defer_fn(function()
      if completed < expected_calls then
        -- Force completion with partial results after timeout
        check_completion()
      end
    end, 5000)
    
    -- Make async LSP requests only for supported methods
    for _, method_info in ipairs(supported_methods) do
      method_info.func(bufnr, func_info, function(result)
        results[method_info.key] = result
        check_completion()
      end)
    end
  end
}