local config = require("lensline.config")

local M = {}

M.providers = {
    lsp = require("lensline.providers.lsp"),  -- now points to new lsp/ directory
    diagnostics = require("lensline.providers.diagnostics"),
    git = require("lensline.providers.git"),
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

-- coordinates with infrastructure-discovered functions for provider collection
function M.collect_lens_data_with_functions(bufnr, functions, callback)
    local opts = config.get()
    local all_lens_data = {}
    
    -- collect enabled providers (simple iteration, no complex ordering)
    local enabled_providers = {}
    for provider_type, provider_config in pairs(opts.providers) do
        local provider_module = M.providers[provider_type]
        if provider_module and provider_config then
            local provider_enabled = provider_config.enabled
            if provider_enabled == nil then
                provider_enabled = true
            end
            
            if provider_enabled then
                table.insert(enabled_providers, {
                    type = provider_type,
                    module = provider_module
                })
            end
        end
    end
    
    if #enabled_providers == 0 then
        callback({})
        return
    end
    
    local pending_providers = #enabled_providers
    local callback_called = false
    local provider_timeouts = {}
    
    -- Helper function to handle provider completion
    local function provider_completed(provider_type, provider_lens_data)
        -- Clean up timeout for this provider
        if provider_timeouts[provider_type] then
            vim.fn.timer_stop(provider_timeouts[provider_type])
            provider_timeouts[provider_type] = nil
        end
        
        -- Merge lens data from this provider
        if provider_lens_data then
            for _, lens in ipairs(provider_lens_data) do
                local key = lens.line .. ":" .. (lens.character or 0)
                if not all_lens_data[key] then
                    all_lens_data[key] = {
                        line = lens.line,
                        character = lens.character,
                        text_parts = {}
                    }
                end
                
                -- append text_parts from this provider (collectors handle their own priority ordering)
                for _, text_part in ipairs(lens.text_parts or {}) do
                    table.insert(all_lens_data[key].text_parts, text_part)
                end
            end
        end
        
        pending_providers = pending_providers - 1
        if pending_providers == 0 and not callback_called then
            callback_called = true
            -- convert map back to array and sort
            local merged_lens_data = {}
            for _, lens in pairs(all_lens_data) do
                table.insert(merged_lens_data, lens)
            end
            table.sort(merged_lens_data, function(a, b) return a.line < b.line end)
            callback(merged_lens_data)
        end
    end
    
    -- Error handling: timeout ensures callback fires, pcall protects against provider crashes
    -- If providers hang or fail, we still return results (even if empty) within 3 seconds
    vim.defer_fn(function()
        if not callback_called then
            callback_called = true
            vim.notify("Lensline: Provider collection timed out", vim.log.levels.WARN)
            callback({}) -- Return empty result
        end
    end, 3000)
    
    -- each provider gets the same function list from infrastructure
    for _, provider_info in ipairs(enabled_providers) do
        local provider_type = provider_info.type
        local provider = provider_info.module
        
        -- Set up timeout for this specific provider
        provider_timeouts[provider_type] = vim.fn.timer_start(3000, function()
            vim.notify("Lensline: " .. provider_type .. " provider timed out", vim.log.levels.WARN)
            provider_completed(provider_type, nil) -- Complete with no data
        end)
        
        -- call provider method that accepts pre-discovered functions
        local success, err = pcall(function()
            provider.collect_data_for_functions(bufnr, functions, function(provider_lens_data)
                provider_completed(provider_type, provider_lens_data)
            end)
        end)
        
        if not success then
            vim.notify("Lensline: " .. provider_type .. " provider failed: " .. tostring(err), vim.log.levels.ERROR)
            provider_completed(provider_type, nil) -- Complete with no data
        end
    end
end

return M