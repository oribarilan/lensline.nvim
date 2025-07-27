-- git provider - focuses on git-specific context (blame, history, etc.)
-- follows the same pattern as other providers

local utils = require("lensline.utils")
local config = require("lensline.config")
local debug = require("lensline.debug")
local cache_service = require("lensline.cache")
local debounce = require("lensline.debounce")

local M = { id = "git" }

-- Use new cache interface
local cache = cache_service.cache

-- helper function to create cache key
local function get_cache_key(bufnr, line)
    local file_path = vim.api.nvim_buf_get_name(bufnr)
    return file_path .. ":" .. line
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
            
            return git_cache.get(key, cache_ttl)
        end,
        cache_set = function(key, value, ttl)
            git_cache.set(key, value, ttl)
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
    local cleared_count = cache.invalidate("git", bufnr)
    
    if cleared_count > 0 then
        debug.log_context("Git", "cleared " .. cleared_count .. " cache entries for buffer " .. bufnr)
    end
end

-- function to cleanup expired cache entries (no-op in event-based system)
function M.cleanup_cache()
    debug.log_context("Git", "cleanup called - no expired entries in event-based system")
    return 0
end

-- function to get cache statistics (useful for debugging)
function M.cache_stats()
    return {
        name = "git",
        provider = "event-based",
        ttl = "none"
    }
end

-- Event-based refresh system setup (called once during plugin initialization)
M.setup = function(config_opts)
    debug.log_context("Git", "setting up event-based refresh system")
    
    vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
        group = vim.api.nvim_create_augroup("lensline_git_refresh", { clear = true }),
        callback = function(args)
            M.refresh(args.buf, config_opts)
        end,
    })
    
    debug.log_context("Git", "git provider event-based refresh system initialized")
end

-- Event-based refresh method (called when git data needs to be refreshed)
M.refresh = function(bufnr, config_opts)
    if not utils.is_valid_buffer(bufnr) then
        return
    end
    
    local file_path = vim.api.nvim_buf_get_name(bufnr)
    if not file_path or file_path == "" then
        return
    end
    
    -- Get debounce delay from config
    local debounce_delay = config_opts.debounce or 500 -- default 500ms as per design doc
    
    -- Debounce the refresh to avoid excessive git operations
    debounce.debounce("git", bufnr, function()
        debug.log_context("Git", string.format("refreshing git data for buffer %s", bufnr))
        
        -- Invalidate cache for this buffer
        cache.invalidate("git", bufnr)
        
        -- Fetch new git data asynchronously
        M.fetch_git_data_async(bufnr, function(git_data)
            if git_data then
                -- Cache the new git data using the "file" key as per design doc
                cache.set("git", bufnr, "file", git_data)
                
                debug.log_context("Git", string.format("cached new git data for buffer %s", bufnr))
                
                -- Note: Don't trigger immediate lens refresh - the delayed renderer will handle it
                -- This allows time for async collectors to complete their work
            end
        end)
    end, debounce_delay)
end

-- Async function to fetch git data (blame, last_commit, etc.)
M.fetch_git_data_async = function(bufnr, callback)
    local file_path = vim.api.nvim_buf_get_name(bufnr)
    
    -- Check if we're in a git repository first
    vim.system({"git", "rev-parse", "--is-inside-work-tree"}, {
        cwd = vim.fn.fnamemodify(file_path, ":h")
    }, function(result)
        if result.code ~= 0 then
            debug.log_context("Git", "not in a git repository")
            callback(nil)
            return
        end
        
        -- Fetch git blame data
        vim.system({"git", "blame", "--porcelain", file_path}, {
            cwd = vim.fn.fnamemodify(file_path, ":h")
        }, function(blame_result)
            if blame_result.code ~= 0 then
                debug.log_context("Git", "failed to get git blame data")
                callback(nil)
                return
            end
            
            local blame_data = M.parse_blame_output(blame_result.stdout)
            
            -- Fetch last commit info
            vim.system({"git", "log", "-1", "--format=%H|%an|%at|%s", file_path}, {
                cwd = vim.fn.fnamemodify(file_path, ":h")
            }, function(log_result)
                local last_commit = nil
                if log_result.code == 0 and log_result.stdout then
                    local parts = vim.split(log_result.stdout:gsub("\n", ""), "|")
                    if #parts >= 4 then
                        last_commit = {
                            hash = parts[1],
                            author = parts[2],
                            timestamp = tonumber(parts[3]),
                            message = parts[4]
                        }
                    end
                end
                
                -- Return combined git data
                callback({
                    blame = blame_data,
                    last_commit = last_commit,
                    file_path = file_path,
                    cache = {} -- Initialize cache storage for collector data
                })
            end)
        end)
    end)
end

-- Parse git blame porcelain output into a structured format
M.parse_blame_output = function(blame_output)
    if not blame_output or blame_output == "" then
        return {}
    end
    
    local lines = vim.split(blame_output, "\n")
    local blame_data = {}
    local current_commit = nil
    local line_num = 0
    
    for _, line in ipairs(lines) do
        if line:match("^[0-9a-f]+") then
            -- New commit line
            local parts = vim.split(line, " ")
            current_commit = parts[1]
            line_num = tonumber(parts[3])
        elseif line:match("^author ") then
            if current_commit and line_num then
                if not blame_data[line_num] then
                    blame_data[line_num] = {}
                end
                blame_data[line_num].author = line:match("^author (.+)")
                blame_data[line_num].commit = current_commit
            end
        elseif line:match("^author%-time ") then
            if current_commit and line_num then
                if not blame_data[line_num] then
                    blame_data[line_num] = {}
                end
                blame_data[line_num].timestamp = tonumber(line:match("^author%-time (%d+)"))
            end
        end
    end
    
    return blame_data
end

-- Update the context creation to use new cache interface
function M.create_context(bufnr)
    return {
        file_path = vim.api.nvim_buf_get_name(bufnr),
        bufnr = bufnr,
        cache_get = function(key)
            local git_data = cache.get("git", bufnr, "file")
            if git_data and git_data.cache and key then
                return git_data.cache[key]
            end
            return nil
        end,
        cache_set = function(key, value)
            -- Store individual cache entries in the git data structure
            local git_data = cache.get("git", bufnr, "file") or { cache = {} }
            git_data.cache = git_data.cache or {}
            git_data.cache[key] = value
            cache.set("git", bufnr, "file", git_data)
        end,
    }
end

return M