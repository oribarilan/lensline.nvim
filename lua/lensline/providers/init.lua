local config = require("lensline.config")

local M = {}

M.providers = {
    lsp = require("lensline.providers.lsp"),  -- now points to new lsp/ directory
    diagnostics = require("lensline.providers.diagnostics"),
}

function M.get_enabled_providers()
    local opts = config.get()
    local enabled = {}
    
    -- iterate through providers in the order they appear in config
    -- to preserve user-specified rendering order
    for provider_type, provider_config in pairs(opts.providers) do
        local provider_module = M.providers[provider_type]
        if provider_module and provider_config then
            -- check if provider is enabled (defaults to true if absent)
            local provider_enabled = provider_config.enabled
            if provider_enabled == nil then
                provider_enabled = true  -- default to true if not specified
            end
            
            if provider_enabled then
                enabled[provider_type] = provider_module
            end
        end
    end
    
    return enabled
end

-- legacy function - kept temporarily for any old references
-- the new architecture uses collect_lens_data_with_functions
function M.collect_lens_data(bufnr, callback)
    -- fallback to old behavior if needed, but shouldn't be called
    callback({})
end

-- new function that coordinates with infrastructure-discovered functions
-- this replaces the old collect_lens_data for the new architecture
function M.collect_lens_data_with_functions(bufnr, functions, callback)
    local opts = config.get()
    local all_lens_data = {}
    
    -- get providers in configuration order
    local provider_order = {}
    local enabled_providers = {}
    
    for provider_type, provider_config in pairs(opts.providers) do
        local provider_module = M.providers[provider_type]
        if provider_module and provider_config then
            local provider_enabled = provider_config.enabled
            if provider_enabled == nil then
                provider_enabled = true
            end
            
            if provider_enabled then
                table.insert(provider_order, provider_type)
                enabled_providers[provider_type] = provider_module
            end
        end
    end
    
    if #provider_order == 0 then
        callback({})
        return
    end
    
    local pending_providers = #provider_order
    
    -- each provider gets the same function list from infrastructure
    for _, provider_type in ipairs(provider_order) do
        local provider = enabled_providers[provider_type]
        
        -- call new provider method that accepts pre-discovered functions
        if provider.collect_data_for_functions then
            provider.collect_data_for_functions(bufnr, functions, function(provider_lens_data)
                -- merge lens data from this provider
                for _, lens in ipairs(provider_lens_data) do
                    local key = lens.line .. ":" .. (lens.character or 0)
                    if not all_lens_data[key] then
                        all_lens_data[key] = {
                            line = lens.line,
                            character = lens.character,
                            text_parts = {}
                        }
                    end
                    
                    -- append text_parts from this provider
                    for _, text_part in ipairs(lens.text_parts or {}) do
                        table.insert(all_lens_data[key].text_parts, text_part)
                    end
                end
                
                pending_providers = pending_providers - 1
                if pending_providers == 0 then
                    -- convert map back to array and sort
                    local merged_lens_data = {}
                    for _, lens in pairs(all_lens_data) do
                        table.insert(merged_lens_data, lens)
                    end
                    table.sort(merged_lens_data, function(a, b) return a.line < b.line end)
                    callback(merged_lens_data)
                end
            end)
        else
            -- fallback to old method for backward compatibility during transition
            provider.get_lens_data(bufnr, function(provider_lens_data)
                for _, lens in ipairs(provider_lens_data) do
                    local key = lens.line .. ":" .. (lens.character or 0)
                    if not all_lens_data[key] then
                        all_lens_data[key] = {
                            line = lens.line,
                            character = lens.character,
                            text_parts = {}
                        }
                    end
                    
                    for _, text_part in ipairs(lens.text_parts or {}) do
                        table.insert(all_lens_data[key].text_parts, text_part)
                    end
                end
                
                pending_providers = pending_providers - 1
                if pending_providers == 0 then
                    local merged_lens_data = {}
                    for _, lens in pairs(all_lens_data) do
                        table.insert(merged_lens_data, lens)
                    end
                    table.sort(merged_lens_data, function(a, b) return a.line < b.line end)
                    callback(merged_lens_data)
                end
            end)
        end
    end
end

return M