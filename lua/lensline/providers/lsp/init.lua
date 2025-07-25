-- lsp provider - focuses only on domain-specific context (lsp clients, caching)
-- no more function discovery - that's handled by infrastructure now

local utils = require("lensline.utils")
local config = require("lensline.config")
local debug = require("lensline.debug")

local M = {}

-- simple cache for reference counts (keeping existing cache logic for now)
local reference_cache = {}

-- helper function to create cache key
local function get_cache_key(bufnr, line, character)
    local uri = vim.uri_from_bufnr(bufnr)
    return uri .. ":" .. line .. ":" .. character
end

-- helper function to check if cache entry is valid
local function is_cache_valid(entry, timeout_ms)
    if not entry then
        return false
    end
    local current_time = vim.fn.reltime()
    local elapsed_ms = vim.fn.reltimestr(vim.fn.reltime(entry.timestamp, current_time)) * 1000
    return elapsed_ms < timeout_ms
end

-- auto-discover built-in collectors from collectors/ directory
local function load_built_in_collectors()
    local collectors = {}
    local base_path = "lensline.providers.lsp.collectors"
    
    -- for now, manually list collectors - later we can auto-discover
    local collector_files = {
        "references",
        "definitions",     -- now available
        -- "implementations"  -- can add more later
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

-- default collectors used when user doesn't override
M.default_collectors = {
    M.collectors.references,
    M.collectors.definitions,
}

-- provider context creation (domain-specific only - no function discovery)
function M.create_context(bufnr)
    return {
        clients = utils.get_lsp_clients(bufnr),
        uri = vim.uri_from_bufnr(bufnr),
        bufnr = bufnr,
        cache_get = function(key) 
            local opts = config.get()
            local lsp_config = opts.providers.lsp
            local cache_ttl = (lsp_config.performance and lsp_config.performance.cache_ttl) or 30000
            
            local entry = reference_cache[key]
            if is_cache_valid(entry, cache_ttl) then
                return entry.count
            end
            return nil
        end,
        cache_set = function(key, value, ttl) 
            reference_cache[key] = {
                count = value,
                timestamp = vim.fn.reltime()
            }
        end,
        -- lsp-specific context only, no function discovery
    }
end

-- data collection for discovered functions (functions provided by infrastructure)
function M.collect_data_for_functions(bufnr, functions, callback)
    debug.log_context("LSP", "collect_data_for_functions called for " .. #functions .. " functions")
    
    local opts = config.get()
    local lsp_config = opts.providers.lsp
    
    -- check if lsp provider is enabled
    local provider_enabled = lsp_config.enabled
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
    local to_remove = {}
    
    for key, _ in pairs(reference_cache) do
        if key:match("^" .. vim.pesc(uri) .. ":") then
            table.insert(to_remove, key)
        end
    end
    
    for _, key in ipairs(to_remove) do
        reference_cache[key] = nil
    end
    
    if #to_remove > 0 then
        debug.log_context("LSP", "cleared " .. #to_remove .. " cache entries for buffer " .. bufnr)
    end
end

return M