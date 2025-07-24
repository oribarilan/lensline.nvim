local config = require("lensline.config")

local M = {}

M.providers = {
    lsp = require("lensline.providers.lsp"),
}

function M.get_enabled_providers()
    local opts = config.get()
    local enabled = {}
    
    -- check each provider type (tech-based: lsp, git, etc.)
    for provider_type, provider_module in pairs(M.providers) do
        local provider_config = opts.providers[provider_type]
        if provider_config then
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
    local enabled_providers = M.get_enabled_providers()
    local all_lens_data = {}
    local pending_providers = 0
    
    -- count enabled providers
    for name, provider in pairs(enabled_providers) do
        pending_providers = pending_providers + 1
    end
    
    if pending_providers == 0 then
        callback({})
        return
    end
    
    -- collect data from each provider
    for name, provider in pairs(enabled_providers) do
        provider.get_lens_data(bufnr, function(lens_data)
            for _, lens in ipairs(lens_data) do
                table.insert(all_lens_data, lens)
            end
            
            pending_providers = pending_providers - 1
            if pending_providers == 0 then
                -- sort by line number before returning
                table.sort(all_lens_data, function(a, b) return a.line < b.line end)
                callback(all_lens_data)
            end
        end)
    end
end

return M