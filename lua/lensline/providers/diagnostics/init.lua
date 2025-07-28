-- DEPRECATED: This diagnostics provider is deprecated and kept as dead code for reference.
-- The new architecture uses a simpler provider structure.
--
-- diagnostics provider - focuses only on domain-specific context (diagnostics data)
-- no more function discovery - that's handled by infrastructure now

local utils = require("lensline.utils")
local config = require("lensline.config")
local debug = require("lensline.debug")
local cache_service = require("lensline.cache")
local debounce = require("lensline.debounce")

local M = { id = "diagnostics" }

-- Use new cache interface
local cache = cache_service.cache

-- auto-discover built-in collectors from collectors/ directory
local function load_built_in_collectors()
    local collectors = {}
    local base_path = "lensline.providers.diagnostics.collectors"
    
    -- manually list available collectors
    local collector_files = {
        "summary",
    }
    
    for _, name in ipairs(collector_files) do
        local ok, collector = pcall(require, base_path .. "." .. name)
        if ok then
            collectors[name] = collector
            debug.log_context("Diagnostics", "loaded built-in collector: " .. name)
        else
            debug.log_context("Diagnostics", "failed to load collector " .. name .. ": " .. collector, "WARN")
        end
    end
    
    return collectors
end

-- export collectors for user import
M.collectors = load_built_in_collectors()

-- ========================================
-- DEFAULT COLLECTORS FOR DIAGNOSTICS PROVIDER
-- ========================================
-- these are enabled by default unless user provides custom collectors array
-- to see all available collectors: require("lensline.providers.diagnostics").collectors
-- to customize: set providers.diagnostics.collectors = { your_functions } in setup()
M.default_collectors = {
    -- diagnostic summary removed from defaults - users can add it manually if needed
    -- add new built-in collectors here as they're created
}

-- provider context creation (domain-specific only)
function M.create_context(bufnr)
    return {
        diagnostics = vim.diagnostic.get(bufnr),
        bufnr = bufnr,
        cache_get = function(key)
            local diag_data = cache.get("diagnostics", bufnr, "changedtick")
            if diag_data then
                return diag_data.diagnostics
            end
            return nil
        end,
        cache_set = function(key, value)
            -- Individual cache entries are not used in new system
            debug.log_context("Diagnostics", "Individual cache_set is deprecated in event-based system", "WARN")
        end,
        -- diagnostics-specific context only, no function discovery
    }
end

-- data collection for discovered functions (functions provided by infrastructure)
function M.collect_data_for_functions(bufnr, functions, callback)
    debug.log_context("Diagnostics", "collect_data_for_functions called for " .. #functions .. " functions")
    
    local opts = config.get()
    
    -- Find diagnostics config in array format
    local diagnostics_config = nil
    for _, provider_config in ipairs(opts.providers) do
        if provider_config.type == "diagnostics" then
            diagnostics_config = provider_config
            break
        end
    end
    
    -- check if diagnostics provider is enabled (defaults to true)
    local provider_enabled = true
    if diagnostics_config and diagnostics_config.enabled ~= nil then
        provider_enabled = diagnostics_config.enabled
    end
    
    if not provider_enabled then
        debug.log_context("Diagnostics", "diagnostics provider is disabled")
        callback({})
        return
    end
    
    if not utils.is_valid_buffer(bufnr) then
        debug.log_context("Diagnostics", "buffer " .. bufnr .. " is not valid", "WARN")
        callback({})
        return
    end
    
    -- get collectors from config or use defaults
    local collectors = diagnostics_config.collectors or M.default_collectors
    local context = M.create_context(bufnr)
    
    local lens_data = {}
    
    for _, func in ipairs(functions) do
        local text_parts = {}
        
        -- run all collectors for this function
        for _, collector_fn in ipairs(collectors) do
            local format, value = collector_fn(context, func)
            if format and value then
                table.insert(text_parts, string.format(format, value))
            end
        end
        
        if #text_parts > 0 then
            table.insert(lens_data, {
                line = func.line,
                character = func.character,
                text_parts = text_parts
            })
        end
    end
    
    debug.log_context("Diagnostics", "found diagnostics for " .. #lens_data .. " functions")
    callback(lens_data)
end

-- function to clear cache for a specific buffer when file is modified
function M.clear_cache(bufnr)
    local cleared_count = cache.invalidate("diagnostics", bufnr)
    
    if cleared_count > 0 then
        debug.log_context("Diagnostics", "cleared " .. cleared_count .. " cache entries for buffer " .. bufnr)
    end
end

-- function to cleanup expired cache entries (no-op in event-based system)
function M.cleanup_cache()
    debug.log_context("Diagnostics", "cleanup called - no expired entries in event-based system")
    return 0
end

-- function to get cache statistics (useful for debugging)
function M.cache_stats()
    return {
        name = "diagnostics",
        provider = "event-based",
        ttl = "none"
    }
end

-- Event-based refresh system setup (called once during plugin initialization)
M.setup = function(config_opts)
    debug.log_context("Diagnostics", "setting up event-based refresh system")
    
    -- Set up LSP diagnostic handler to trigger refresh on diagnostics updates
    local original_handler = vim.lsp.handlers["textDocument/publishDiagnostics"]
    
    vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
        -- Call original handler first
        if original_handler then
            original_handler(err, result, ctx, config)
        else
            vim.lsp.diagnostic.on_publish_diagnostics(err, result, ctx, config)
        end
        
        -- Trigger our refresh (no debounce needed for push-based diagnostics)
        if result and result.uri then
            local bufnr = vim.uri_to_bufnr(result.uri)
            if vim.api.nvim_buf_is_valid(bufnr) then
                M.refresh(bufnr, config_opts)
            end
        end
    end
    
    debug.log_context("Diagnostics", "diagnostics provider event-based refresh system initialized")
end

-- Event-based refresh method (called when diagnostics data changes)
M.refresh = function(bufnr, config_opts)
    if not utils.is_valid_buffer(bufnr) then
        return
    end
    
    debug.log_context("Diagnostics", string.format("refreshing diagnostics data for buffer %s", bufnr))
    
    -- No debounce needed for diagnostics as they are push-based from LSP
    -- Get current changedtick to use as cache key
    local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
    
    -- Invalidate old cache
    cache.invalidate("diagnostics", bufnr)
    
    -- Get fresh diagnostics data
    local diagnostics_data = {
        changedtick = changedtick,
        diagnostics = vim.diagnostic.get(bufnr),
        timestamp = vim.fn.reltime()
    }
    
    -- Cache the new diagnostics data using the "changedtick" key as per design doc
    cache.set("diagnostics", bufnr, "changedtick", diagnostics_data)
    
    debug.log_context("Diagnostics", string.format("cached new diagnostics data for buffer %s, changedtick %s", bufnr, changedtick))
    
    -- Note: Don't trigger immediate lens refresh - the delayed renderer will handle it
    -- This maintains consistency with other providers and prevents multiple rapid refreshes
end

-- Update the context creation to use new cache interface
function M.create_context(bufnr)
    return {
        diagnostics = vim.diagnostic.get(bufnr),
        bufnr = bufnr,
        cache_get = function(key)
            local diag_data = cache.get("diagnostics", bufnr, "changedtick")
            if diag_data then
                return diag_data.diagnostics
            end
            return nil
        end,
        cache_set = function(key, value)
            -- Individual cache entries are not used in new system
            -- All diagnostics data is stored under "changedtick" key
            debug.log_context("Diagnostics", "Individual cache_set is deprecated in event-based system", "WARN")
        end,
    }
end

return M
