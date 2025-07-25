-- lsp definitions collector
-- example of how easy it is to add new collectors

return function(lsp_context, function_info)
    local cache_key = "defs:" .. function_info.line .. ":" .. function_info.character
    local cached = lsp_context.cache_get(cache_key)
    if cached then 
        return "def: %d", cached 
    end
    
    local def_count = 0
    local position = { line = function_info.line, character = function_info.character }
    
    -- check that we have lsp clients that support definitions
    if not lsp_context.clients or #lsp_context.clients == 0 then
        return nil, nil
    end
    
    -- check if any client supports textDocument/definition  
    local supports_definitions = false
    for _, client in ipairs(lsp_context.clients) do
        if client.supports_method("textDocument/definition") then
            supports_definitions = true
            break
        end
    end
    
    if not supports_definitions then
        return nil, nil
    end
    
    -- QUICK FIX: avoid blocking UI with sync requests
    -- for now, return placeholder while we fix async handling
    lsp_context.cache_set(cache_key, 0, 30000)
    return "def: %s", "?"
end