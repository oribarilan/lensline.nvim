-- lsp references collector - non-blocking with background updates
-- returns cached data immediately, triggers async update in background

return function(lsp_context, function_info)
    local cache_key = "refs:" .. function_info.line .. ":" .. function_info.character
    local cached = lsp_context.cache_get(cache_key)
    
    -- if we have cached data, return it immediately
    if cached then
        return "refs: %d", cached
    end
    
    -- check basic requirements
    if not lsp_context.clients or #lsp_context.clients == 0 then
        return nil, nil
    end
    
    local supports_references = false
    for _, client in ipairs(lsp_context.clients) do
        if client.supports_method("textDocument/references") then
            supports_references = true
            break
        end
    end
    
    if not supports_references then
        return nil, nil
    end
    
    -- return placeholder immediately, start background update
    local position = { line = function_info.line, character = function_info.character }
    
    -- start async update in background (fire and forget)
    vim.schedule(function()
        local params = {
            textDocument = vim.lsp.util.make_text_document_params(lsp_context.bufnr),
            position = position,
            context = { includeDeclaration = false }
        }
        
        vim.lsp.buf_request_all(lsp_context.bufnr, "textDocument/references", params, function(results)
            local total_count = 0
            
            for client_id, result in pairs(results) do
                if result.result and type(result.result) == "table" then
                    total_count = total_count + #result.result
                end
            end
            
            -- cache the result for next time
            lsp_context.cache_set(cache_key, total_count, 30000)
            
            -- trigger a refresh so the updated count shows up
            local core = require("lensline.core")
            core.refresh_current_buffer()
        end)
    end)
    
    -- return placeholder for now
    return "refs: %s", "..."
end