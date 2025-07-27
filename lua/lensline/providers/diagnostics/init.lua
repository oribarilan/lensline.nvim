-- diagnostics provider - focuses only on domain-specific context (diagnostics data)
-- no more function discovery - that's handled by infrastructure now

local utils = require("lensline.utils")
local config = require("lensline.config")
local debug = require("lensline.debug")

local M = {}

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

local collector_utils = require("lensline.utils.collector")

-- ========================================
-- DEFAULT COLLECTORS FOR DIAGNOSTICS PROVIDER
-- ========================================
-- these are enabled by default unless user provides custom collectors array
-- to see all available collectors: require("lensline.providers.diagnostics").collectors
-- to customize: set providers.diagnostics.collectors = { your_functions } in setup()
M.default_collectors = {
    -- diagnostic summary removed from defaults - users can add it manually if needed
    -- { collect = M.collectors.summary, priority = 20 },  -- diagnostic summary for each function
    -- add new built-in collectors here as they're created
}

-- provider context creation (domain-specific only)
function M.create_context(bufnr)
    return {
        diagnostics = vim.diagnostic.get(bufnr),
        bufnr = bufnr,
        cache_get = function(key) 
            -- diagnostics don't need much caching since they're already fast
            return nil
        end,
        cache_set = function(key, value, ttl) 
            -- no-op for now
        end,
        -- diagnostics-specific context only, no function discovery
    }
end

-- data collection for discovered functions (functions provided by infrastructure)
function M.collect_data_for_functions(bufnr, functions, callback)
    debug.log_context("Diagnostics", "collect_data_for_functions called for " .. #functions .. " functions")
    
    local opts = config.get()
    local diagnostics_config = opts.providers.diagnostics
    
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
    -- sort collectors by priority
    local sorted_collectors = collector_utils.sort_collectors(collectors)
    local context = M.create_context(bufnr)
    
    local lens_data = {}
    
    for _, func in ipairs(functions) do
        local text_parts = {}
        
        -- run all collectors for this function
        for _, collector in ipairs(sorted_collectors) do
            local format, value = collector.collect(context, func)
            if format and value then
                table.insert(text_parts, {
                    text = string.format(format, value),
                    order = collector.priority
                })
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

return M