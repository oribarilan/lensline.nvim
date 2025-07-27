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
    -- Note: pairs() doesn't preserve order, so we use a fixed order that matches typical config
    local provider_order = {}
    local enabled_providers = {}
    
    -- Define the expected order (matching typical config definition order)
    local known_provider_order = {"lsp", "diagnostics", "git"}
    
    for _, provider_type in ipairs(known_provider_order) do
        local provider_config = opts.providers[provider_type]
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
    
    -- Handle any additional providers not in the known list (for extensibility)
    for provider_type, provider_config in pairs(opts.providers) do
        local provider_module = M.providers[provider_type]
        if provider_module and provider_config and not enabled_providers[provider_type] then
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
    local callback_called = false
    local provider_timeouts = {}
    
    -- Helper function to safely call the final callback once
    local function safe_callback(merged_lens_data)
        if not callback_called then
            callback_called = true
            -- Clean up any remaining timeouts
            for _, timeout_handle in pairs(provider_timeouts) do
                vim.fn.timer_stop(timeout_handle)
            end
            callback(merged_lens_data)
        end
    end
    
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
                
                -- Find order index for this provider
                local order_index = 1
                for i, p_type in ipairs(provider_order) do
                    if p_type == provider_type then
                        order_index = i
                        break
                    end
                end
                
                -- append text_parts from this provider with order information
                for _, text_part in ipairs(lens.text_parts or {}) do
                    table.insert(all_lens_data[key].text_parts, {
                        text = text_part,
                        order = order_index
                    })
                end
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
            safe_callback(merged_lens_data)
        end
    end
    
    -- Set up global timeout to ensure callback is always called
    vim.defer_fn(function()
        if not callback_called then
            vim.notify("Lensline: Some providers timed out", vim.log.levels.WARN)
            -- convert current data to final result
            local merged_lens_data = {}
            for _, lens in pairs(all_lens_data) do
                table.insert(merged_lens_data, lens)
            end
            table.sort(merged_lens_data, function(a, b) return a.line < b.line end)
            safe_callback(merged_lens_data)
        end
    end, 5000) -- 5 second global timeout
    
    -- each provider gets the same function list from infrastructure
    for order_index, provider_type in ipairs(provider_order) do
        local provider = enabled_providers[provider_type]
        
        -- Set up timeout for this specific provider
        provider_timeouts[provider_type] = vim.fn.timer_start(3000, function()
            vim.notify("Lensline: " .. provider_type .. " provider timed out", vim.log.levels.WARN)
            provider_completed(provider_type, nil) -- Complete with no data
        end)
        
        -- call new provider method that accepts pre-discovered functions
        if provider.collect_data_for_functions then
            local success, err = pcall(function()
                provider.collect_data_for_functions(bufnr, functions, function(provider_lens_data)
                    provider_completed(provider_type, provider_lens_data)
                end)
            end)
            
            if not success then
                vim.notify("Lensline: " .. provider_type .. " provider failed: " .. tostring(err), vim.log.levels.ERROR)
                provider_completed(provider_type, nil) -- Complete with no data
            end
        else
            -- fallback to old method for backward compatibility during transition
            local success, err = pcall(function()
                provider.get_lens_data(bufnr, function(provider_lens_data)
                    provider_completed(provider_type, provider_lens_data)
                end)
            end)
            
            if not success then
                vim.notify("Lensline: " .. provider_type .. " provider failed: " .. tostring(err), vim.log.levels.ERROR)
                provider_completed(provider_type, nil) -- Complete with no data
            end
        end
    end
end

return M