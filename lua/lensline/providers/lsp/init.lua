-- lsp provider - focuses only on domain-specific context (lsp clients, caching)
-- no more function discovery - that's handled by infrastructure now

local utils = require("lensline.utils")
local config = require("lensline.config")
local debug = require("lensline.debug")
local cache_service = require("lensline.cache")
local debounce = require("lensline.debounce")

local M = { id = "lsp" }

-- Use new cache interface
local cache = cache_service.cache

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
    local cleared_count = cache.invalidate("lsp", bufnr)
    
    if cleared_count > 0 then
        debug.log_context("LSP", "cleared " .. cleared_count .. " cache entries for buffer " .. bufnr)
    end
end

-- function to cleanup expired cache entries (no-op in event-based system)
function M.cleanup_cache()
    debug.log_context("LSP", "cleanup called - no expired entries in event-based system")
    return 0
end

-- function to get cache statistics (useful for debugging)
function M.cache_stats()
    return {
        name = "lsp",
        provider = "event-based",
        ttl = "none"
    }
end

-- Event-based refresh system setup (called once during plugin initialization)
M.setup = function(config_opts)
    debug.log_context("LSP", "setting up event-based refresh system")
    
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = vim.api.nvim_create_augroup("lensline_lsp_refresh", { clear = true }),
        callback = function(args)
            M.refresh(args.buf, config_opts)
        end,
    })
    
    -- Also refresh on LSP attach/detach events
    vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("lensline_lsp_attach", { clear = true }),
        callback = function(args)
            M.refresh(args.buf, config_opts)
        end,
    })
    
    vim.api.nvim_create_autocmd("LspDetach", {
        group = vim.api.nvim_create_augroup("lensline_lsp_detach", { clear = true }),
        callback = function(args)
            -- Clear cache when LSP detaches
            cache.invalidate("lsp", args.buf)
        end,
    })
    
    debug.log_context("LSP", "lsp provider event-based refresh system initialized")
end

-- Event-based refresh method (called when LSP data needs to be refreshed)
M.refresh = function(bufnr, config_opts)
    if not utils.is_valid_buffer(bufnr) then
        return
    end
    
    -- Check if LSP clients are available
    local clients = utils.get_lsp_clients(bufnr)
    if not clients or #clients == 0 then
        return
    end
    
    -- Get debounce delay from config
    local debounce_delay = config_opts.debounce or 250 -- default 250ms as per design doc
    
    -- Debounce the refresh to avoid excessive LSP requests
    debounce.debounce("lsp", bufnr, function()
        debug.log_context("LSP", string.format("refreshing lsp data for buffer %s", bufnr))
        
        -- Get current changedtick to use as cache key
        local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
        
        -- Check if we already have data for this changedtick
        local existing_data = cache.get("lsp", bufnr, "changedtick")
        if existing_data and existing_data.changedtick == changedtick then
            debug.log_context("LSP", string.format("LSP data already current for changedtick %s", changedtick))
            return
        end
        
        -- Invalidate old cache and fetch new LSP data
        cache.invalidate("lsp", bufnr)
        
        -- Fetch new LSP data asynchronously
        M.fetch_lsp_data_async(bufnr, changedtick, function(lsp_data)
            if lsp_data then
                -- Cache the new LSP data using the "changedtick" key as per design doc
                cache.set("lsp", bufnr, "changedtick", {
                    changedtick = changedtick,
                    references = lsp_data.references,
                    symbols = lsp_data.symbols
                })
                
                debug.log_context("LSP", string.format("cached new lsp data for buffer %s, changedtick %s", bufnr, changedtick))
                
                -- Note: Don't trigger immediate lens refresh - the delayed renderer will handle it
                -- This allows time for async collectors to complete their work
            end
        end)
    end, debounce_delay)
end

-- Async function to fetch LSP data (references, symbols, etc.)
M.fetch_lsp_data_async = function(bufnr, changedtick, callback)
    local clients = utils.get_lsp_clients(bufnr)
    if not clients or #clients == 0 then
        callback(nil)
        return
    end
    
    -- For now, we'll just mark that we have LSP data available
    -- Individual collectors will make their own LSP requests as needed
    -- This maintains the existing pattern while adding event-based invalidation
    callback({
        references = {},  -- Will be populated by collectors as needed
        symbols = {},     -- Will be populated by collectors as needed
        clients = clients,
        uri = vim.uri_from_bufnr(bufnr)
    })
end

-- Update the context creation to use new cache interface
function M.create_context(bufnr)
    return {
        clients = utils.get_lsp_clients(bufnr),
        uri = vim.uri_from_bufnr(bufnr),
        bufnr = bufnr,
        cache_get = function(key)
            local lsp_data = cache.get("lsp", bufnr, "changedtick")
            if lsp_data then
                return lsp_data
            end
            return nil
        end,
        cache_set = function(key, value)
            -- Individual cache entries are not used in new system
            -- All LSP data is stored under "changedtick" key
            debug.log_context("LSP", "Individual cache_set is deprecated in event-based system", "WARN")
        end,
    }
end

return M