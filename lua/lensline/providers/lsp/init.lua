-- lsp provider - focuses only on domain-specific context (lsp clients, caching)
-- no more function discovery - that's handled by infrastructure now

local utils = require("lensline.utils")
local config = require("lensline.config")
local debug = require("lensline.debug")
local cache_service = require("lensline.cache")

local M = {}

-- create isolated cache instance for LSP provider
local lsp_cache = cache_service.create_cache("lsp", 15000) -- 15 second default TTL (balanced for active development)

-- helper function to create cache key
local function get_cache_key(bufnr, line, character)
    local uri = vim.uri_from_bufnr(bufnr)
    return uri .. ":" .. line .. ":" .. character
end

-- auto-discover built-in collectors from collectors/ directory
local function load_built_in_collectors()
    local collectors = {}
    local base_path = "lensline.providers.lsp.collectors"
    
    -- manually list available collectors
    local collector_files = {
        "references",
        -- add more collectors here as needed
    }
    
    for _, name in ipairs(collector_files) do
        local ok, collector = pcall(require, base_path .. "." .. name)
        if ok then
            collectors[name] = collector
            debug.log_context("LSP", "loaded built-in collector: " .. name)
        else
            debug.log_context("LSP", "failed to load collector " .. name .. ": " .. collector, "WARN")
        end
    end
    
    return collectors
end

-- export collectors for user import
M.collectors = load_built_in_collectors()

-- ========================================
-- DEFAULT COLLECTORS FOR LSP PROVIDER
-- ========================================
-- these are enabled by default unless user provides custom collectors array
-- to see all available collectors: require("lensline.providers.lsp").collectors
-- to customize: set providers.lsp.collectors = { your_functions } in setup()
M.default_collectors = {
    M.collectors.references,  -- lsp reference counting with smart async updates
    -- add new built-in collectors here as they're created
}

-- provider context creation (domain-specific only - no function discovery)
function M.create_context(bufnr)
    return {
        clients = utils.get_lsp_clients(bufnr),
        uri = vim.uri_from_bufnr(bufnr),
        bufnr = bufnr,
        cache_get = function(key)
            local opts = config.get()
            -- Find lsp config in array format
            local lsp_config = nil
            for _, provider_config in ipairs(opts.providers) do
                if provider_config.type == "lsp" then
                    lsp_config = provider_config
                    break
                end
            end
            local cache_ttl = (lsp_config and lsp_config.performance and lsp_config.performance.cache_ttl) or 15000 -- 15s default balances freshness vs performance
            
            return lsp_cache.get(key, cache_ttl)
        end,
        cache_set = function(key, value, ttl)
            lsp_cache.set(key, value, ttl)
        end,
        -- lsp-specific context only, no function discovery
    }
end

-- data collection for discovered functions (functions provided by infrastructure)
function M.collect_data_for_functions(bufnr, functions, callback)
    debug.log_context("LSP", "collect_data_for_functions called for " .. #functions .. " functions")
    
    local opts = config.get()
    
    -- Find lsp config in array format
    local lsp_config = nil
    for _, provider_config in ipairs(opts.providers) do
        if provider_config.type == "lsp" then
            lsp_config = provider_config
            break
        end
    end
    
    -- check if lsp provider is enabled
    local provider_enabled = lsp_config and lsp_config.enabled
    if provider_enabled == nil then
        provider_enabled = true
    end
    
    if not provider_enabled then
        debug.log_context("LSP", "lsp provider is disabled")
        callback({})
        return
    end
    
    -- get collectors from config or use defaults
    local collectors = lsp_config.collectors or M.default_collectors
    local context = M.create_context(bufnr)
    
    if not utils.is_valid_buffer(bufnr) then
        debug.log_context("LSP", "buffer " .. bufnr .. " is not valid", "WARN")
        callback({})
        return
    end
    
    local lens_data = {}
    
    for _, func in ipairs(functions) do
        local text_parts = {}
        
        -- run all collectors for this function (simple sync approach)
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
    
    callback(lens_data)
end

-- function to clear cache for a specific buffer when file is modified
function M.clear_cache(bufnr)
    local uri = vim.uri_from_bufnr(bufnr)
    local pattern = "^" .. vim.pesc(uri) .. ":"
    
    local cleared_count = lsp_cache.clear(pattern)
    
    if cleared_count > 0 then
        debug.log_context("LSP", "cleared " .. cleared_count .. " cache entries for buffer " .. bufnr)
    end
end

-- function to cleanup expired cache entries (memory management)
function M.cleanup_cache()
    return lsp_cache.cleanup()
end

-- function to get cache statistics (useful for debugging)
function M.cache_stats()
    return lsp_cache.stats()
end

return M