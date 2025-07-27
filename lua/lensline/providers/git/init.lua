-- git provider - focuses on git-specific context (blame, history, etc.)
-- follows the same pattern as other providers

local utils = require("lensline.utils")
local config = require("lensline.config")
local debug = require("lensline.debug")

local M = {}

-- simple cache for git blame information
local git_cache = {}

-- helper function to create cache key
local function get_cache_key(bufnr, line)
    local file_path = vim.api.nvim_buf_get_name(bufnr)
    return file_path .. ":" .. line
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
    local base_path = "lensline.providers.git.collectors"
    
    -- manually list available collectors
    local collector_files = {
        "last_author",
    }
    
    for _, name in ipairs(collector_files) do
        local ok, collector = pcall(require, base_path .. "." .. name)
        if ok then
            collectors[name] = collector
            debug.log_context("Git", "loaded built-in collector: " .. name)
        else
            debug.log_context("Git", "failed to load collector " .. name .. ": " .. collector, "WARN")
        end
    end
    
    return collectors
end

-- export collectors for user import
M.collectors = load_built_in_collectors()

-- ========================================
-- DEFAULT COLLECTORS FOR GIT PROVIDER
-- ========================================
-- these are enabled by default unless user provides custom collectors array
-- to see all available collectors: require("lensline.providers.git").collectors
-- to customize: set providers.git.collectors = { your_functions } in setup()
M.default_collectors = {
    M.collectors.last_author,  -- show last author and time for each function
    -- add new built-in collectors here as they're created
}

-- provider context creation (domain-specific only)
function M.create_context(bufnr)
    return {
        file_path = vim.api.nvim_buf_get_name(bufnr),
        bufnr = bufnr,
        cache_get = function(key)
            local opts = config.get()
            -- Find git config in array format
            local git_config = nil
            for _, provider_config in ipairs(opts.providers) do
                if provider_config.type == "git" then
                    git_config = provider_config
                    break
                end
            end
            local cache_ttl = (git_config and git_config.performance and git_config.performance.cache_ttl) or 300000 -- 5 minutes default
            
            local entry = git_cache[key]
            if is_cache_valid(entry, cache_ttl) then
                return entry.data
            end
            return nil
        end,
        cache_set = function(key, value, ttl) 
            git_cache[key] = {
                data = value,
                timestamp = vim.fn.reltime()
            }
        end,
        -- git-specific context only, no function discovery
    }
end

-- data collection for discovered functions (functions provided by infrastructure)
function M.collect_data_for_functions(bufnr, functions, callback)
    debug.log_context("Git", "collect_data_for_functions called for " .. #functions .. " functions")
    
    local opts = config.get()
    
    -- Find git config in array format
    local git_config = nil
    for _, provider_config in ipairs(opts.providers) do
        if provider_config.type == "git" then
            git_config = provider_config
            break
        end
    end
    
    -- check if git provider is enabled
    local provider_enabled = git_config and git_config.enabled
    if provider_enabled == nil then
        provider_enabled = true -- default to enabled
    end
    
    if not provider_enabled then
        debug.log_context("Git", "git provider is disabled")
        callback({})
        return
    end
    
    if not utils.is_valid_buffer(bufnr) then
        debug.log_context("Git", "buffer " .. bufnr .. " is not valid", "WARN")
        callback({})
        return
    end
    
    -- check if we're in a git repository
    local file_path = vim.api.nvim_buf_get_name(bufnr)
    if file_path == "" then
        debug.log_context("Git", "buffer has no file path")
        callback({})
        return
    end
    
    -- get collectors from config or use defaults
    local collectors = (git_config and git_config.collectors) or M.default_collectors
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
    
    debug.log_context("Git", "found git info for " .. #lens_data .. " functions")
    callback(lens_data)
end

-- function to clear cache for a specific buffer when file is modified
function M.clear_cache(bufnr)
    local file_path = vim.api.nvim_buf_get_name(bufnr)
    local to_remove = {}
    
    for key, _ in pairs(git_cache) do
        if key:match("^" .. vim.pesc(file_path) .. ":") then
            table.insert(to_remove, key)
        end
    end
    
    for _, key in ipairs(to_remove) do
        git_cache[key] = nil
    end
    
    if #to_remove > 0 then
        debug.log_context("Git", "cleared " .. #to_remove .. " cache entries for buffer " .. bufnr)
    end
end

return M