local config = require("lensline.config")

local M = {}

M.providers = {
    lsp = require("lensline.providers.lsp"),
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

function M.collect_lens_data(bufnr, callback)
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
    
    local provider_results = {}
    local pending_providers = #provider_order
    
    -- collect data from each provider
    for _, provider_type in ipairs(provider_order) do
        local provider = enabled_providers[provider_type]
        provider.get_lens_data(bufnr, function(lens_data)
            provider_results[provider_type] = lens_data
            
            pending_providers = pending_providers - 1
            if pending_providers == 0 then
                -- merge lens data preserving provider configuration order
                local merged_lens_data = {}
                local line_lens_map = {}
                
                -- process providers in configuration order
                for _, provider_type in ipairs(provider_order) do
                    local lens_data = provider_results[provider_type] or {}
                    
                    for _, lens in ipairs(lens_data) do
                        local key = lens.line .. ":" .. (lens.character or 0)
                        if not line_lens_map[key] then
                            line_lens_map[key] = {
                                line = lens.line,
                                character = lens.character,
                                text_parts = {}
                            }
                            table.insert(merged_lens_data, line_lens_map[key])
                        end
                        
                        -- append text_parts from this provider
                        for _, text_part in ipairs(lens.text_parts or {}) do
                            table.insert(line_lens_map[key].text_parts, text_part)
                        end
                    end
                end
                
                -- sort by line number before returning
                table.sort(merged_lens_data, function(a, b) return a.line < b.line end)
                callback(merged_lens_data)
            end
        end)
    end
end

return M