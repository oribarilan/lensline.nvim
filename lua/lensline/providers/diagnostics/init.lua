-- diagnostics provider - focuses only on domain-specific context (diagnostics data)
-- no more function discovery - that's handled by infrastructure now

local utils = require("lensline.utils")
local config = require("lensline.config")
local debug = require("lensline.debug")
local cache_service = require("lensline.cache")

local M = {}

-- create optional cache instance for Diagnostics provider (disabled by default since diagnostics are fast)
local diagnostics_cache = nil

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
    -- Initialize cache if enabled in config
    local opts = config.get()
    local diagnostics_config = nil
    for _, provider_config in ipairs(opts.providers) do
        if provider_config.type == "diagnostics" then
            diagnostics_config = provider_config
            break
        end
    end
    
    -- Enable cache if explicitly requested in config
    local cache_enabled = diagnostics_config and diagnostics_config.performance and diagnostics_config.performance.enable_cache
    if cache_enabled and not diagnostics_cache then
        local cache_ttl = (diagnostics_config.performance and diagnostics_config.performance.cache_ttl) or 5000 -- 5 second default
        diagnostics_cache = cache_service.create_cache("diagnostics", cache_ttl)
    end
    
    return {
        diagnostics = vim.diagnostic.get(bufnr),
        bufnr = bufnr,
        cache_get = function(key)
            if diagnostics_cache then
                local cache_ttl = (diagnostics_config and diagnostics_config.performance and diagnostics_config.performance.cache_ttl) or 5000
                return diagnostics_cache.get(key, cache_ttl)
            end
            return nil
        end,
        cache_set = function(key, value, ttl)
            if diagnostics_cache then
                diagnostics_cache.set(key, value, ttl)
            end
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
    if not diagnostics_cache then
        return
    end
    
    local file_path = vim.api.nvim_buf_get_name(bufnr)
    local pattern = "^" .. vim.pesc(file_path) .. ":"
    
    local cleared_count = diagnostics_cache.clear(pattern)
    
    if cleared_count > 0 then
        debug.log_context("Diagnostics", "cleared " .. cleared_count .. " cache entries for buffer " .. bufnr)
    end
end

-- function to cleanup expired cache entries (memory management)
function M.cleanup_cache()
    if diagnostics_cache then
        return diagnostics_cache.cleanup()
    end
    return 0
end

-- function to get cache statistics (useful for debugging)
function M.cache_stats()
    if diagnostics_cache then
        return diagnostics_cache.stats()
    end
    return { name = "diagnostics", total_entries = 0, expired_entries = 0, valid_entries = 0, default_ttl = 0, enabled = false }
end

return M
