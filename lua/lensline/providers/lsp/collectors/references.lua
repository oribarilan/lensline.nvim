-- lsp references collector - non-blocking with background updates
-- returns cached data immediately, triggers async update in background

-- helper function to format references count
local function format_references(count)
    local config = require("lensline.config")
    local opts = config.get()
    
    if opts.use_nerdfonts then
        return " " .. count
    else
        return count .. " refs"
    end
end

return function(lsp_context, function_info)
    -- In the new event-based system, the LSP data is cached at provider level
    -- We need to get the LSP cache data and check if references are available
    local cache_service = require("lensline.cache")
    local cache = cache_service.cache
    local bufnr = lsp_context.bufnr
    
    -- Get the LSP data from the new cache system
    local cache_key = "refs:" .. function_info.line .. ":" .. function_info.character
    local lsp_data = cache.get("lsp", bufnr, "changedtick")
    
    local debug = require("lensline.debug")
    debug.log_context("LSP", string.format("references collector: cache_key=%s, lsp_data=%s",
        cache_key, lsp_data and "present" or "nil"))
    
    -- Check if we have cached reference data for this specific function
    if lsp_data and lsp_data.references and lsp_data.references[cache_key] then
        local ref_data = lsp_data.references[cache_key]
        if ref_data.count then
            debug.log_context("LSP", string.format("returning cached reference count: %s", ref_data.count))
            return "%s", format_references(ref_data.count)
        end
    end
    
    debug.log_context("LSP", "no cached reference data found, proceeding to async request")
    
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
    debug.log_context("LSP", string.format("starting async reference request for %s:%s", position.line, position.character))
    
    -- Add a small delay to throttle rapid requests and avoid overwhelming LSP server
    vim.defer_fn(function()
        -- Validate buffer still exists before making LSP request
        if not vim.api.nvim_buf_is_valid(lsp_context.bufnr) then
            debug.log_context("LSP", string.format("buffer %s no longer valid, skipping LSP request", lsp_context.bufnr))
            return
        end
        
        local params = {
            textDocument = vim.lsp.util.make_text_document_params(lsp_context.bufnr),
            position = position,
            context = { includeDeclaration = false }
        }
        
        debug.log_context("LSP", "making LSP buf_request_all for references")
        vim.lsp.buf_request_all(lsp_context.bufnr, "textDocument/references", params, function(results)
            -- Validate buffer still exists in callback
            if not vim.api.nvim_buf_is_valid(lsp_context.bufnr) then
                debug.log_context("LSP", string.format("buffer %s no longer valid in callback, skipping cache update", lsp_context.bufnr))
                return
            end
            
            debug.log_context("LSP", string.format("LSP references callback received: %s",
                results and "results present" or "no results"))
            
            local total_count = 0
            
            for client_id, result in pairs(results or {}) do
                debug.log_context("LSP", string.format("client %s result: %s",
                    client_id, result and "present" or "nil"))
                if result.result and type(result.result) == "table" then
                    total_count = total_count + #result.result
                    debug.log_context("LSP", string.format("client %s found %s references",
                        client_id, #result.result))
                end
            end
            
            debug.log_context("LSP", string.format("total reference count: %s", total_count))
            
            -- don't subtract 1 since we already set includeDeclaration = false
            -- this should exclude the function declaration automatically
            
            -- Store reference data in the new cache system
            local cache_service = require("lensline.cache")
            local cache = cache_service.cache
            local bufnr = lsp_context.bufnr
            
            -- Recreate cache key inside callback scope
            local cache_key = "refs:" .. position.line .. ":" .. position.character
            
            -- Get existing LSP data or create new structure
            local lsp_data = cache.get("lsp", bufnr, "changedtick") or {
                changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
                references = {}
            }
            
            -- Update references data
            lsp_data.references = lsp_data.references or {}
            lsp_data.references[cache_key] = { count = total_count }
            
            -- Store back in cache - that's all the collector should do
            cache.set("lsp", bufnr, "changedtick", lsp_data)
            
            -- Trigger delayed renderer to pick up the new async data
            -- Use the same debounce mechanism as the delayed renderer
            local debounce = require("lensline.debounce")
            debounce.debounce("delayed_renderer", bufnr, function()
                vim.schedule(function()
                    local lens_manager = require("lensline.core.lens_manager")
                    if lens_manager and lens_manager.refresh_buffer_lenses then
                        lens_manager.refresh_buffer_lenses(bufnr)
                    end
                end)
            end, 50) -- Short 50ms delay since data is already ready
        end)
    end, 100) -- 100ms delay to throttle rapid LSP requests
    
    -- return placeholder for now
    local config = require("lensline.config")
    local opts = config.get()
    local placeholder = opts.use_nerdfonts and " ?" or "? refs"
    return "%s", placeholder
end
