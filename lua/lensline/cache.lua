-- Centralized cache service for lensline providers
-- Provides isolated cache instances with shared validation and TTL logic

local debug = require("lensline.debug")

local M = {}

-- Helper function to check if cache entry is valid (extracted from providers)
local function is_cache_valid(entry, timeout_ms)
    if not entry then
        return false
    end
    local current_time = vim.fn.reltime()
    local elapsed_ms = vim.fn.reltimestr(vim.fn.reltime(entry.timestamp, current_time)) * 1000
    return elapsed_ms < timeout_ms
end

-- Create a new isolated cache instance for a provider
function M.create_cache(name, default_ttl)
    if not name or type(name) ~= "string" then
        error("Cache name must be a non-empty string")
    end
    
    if not default_ttl or type(default_ttl) ~= "number" or default_ttl <= 0 then
        error("Default TTL must be a positive number")
    end
    
    local cache_store = {}
    local cache_name = name
    
    local cache_instance = {
        -- Get value from cache if valid, nil otherwise
        get = function(key, custom_ttl)
            if not key then
                return nil
            end
            
            local ttl = custom_ttl or default_ttl
            local entry = cache_store[key]
            
            if is_cache_valid(entry, ttl) then
                debug.log_context("Cache", string.format("[%s] cache hit for key: %s", cache_name, key))
                return entry.value
            end
            
            if entry then
                debug.log_context("Cache", string.format("[%s] cache expired for key: %s", cache_name, key))
            end
            
            return nil
        end,
        
        -- Set value in cache with timestamp
        set = function(key, value, ttl)
            if not key then
                debug.log_context("Cache", string.format("[%s] cannot set cache with nil key", cache_name), "WARN")
                return
            end
            
            cache_store[key] = {
                value = value,
                timestamp = vim.fn.reltime(),
                ttl = ttl or default_ttl
            }
            
            debug.log_context("Cache", string.format("[%s] cached value for key: %s", cache_name, key))
        end,
        
        -- Clear cache entries matching pattern (lua pattern, not regex)
        clear = function(pattern)
            if not pattern then
                -- Clear all entries
                local count = 0
                for k, _ in pairs(cache_store) do
                    count = count + 1
                end
                cache_store = {}
                debug.log_context("Cache", string.format("[%s] cleared all %d cache entries", cache_name, count))
                return count
            end
            
            local to_remove = {}
            for key, _ in pairs(cache_store) do
                if key:match(pattern) then
                    table.insert(to_remove, key)
                end
            end
            
            for _, key in ipairs(to_remove) do
                cache_store[key] = nil
            end
            
            if #to_remove > 0 then
                debug.log_context("Cache", string.format("[%s] cleared %d cache entries matching pattern: %s", cache_name, #to_remove, pattern))
            end
            
            return #to_remove
        end,
        
        -- Get cache statistics (useful for debugging)
        stats = function()
            local total = 0
            local expired = 0
            
            for key, entry in pairs(cache_store) do
                total = total + 1
                if not is_cache_valid(entry, entry.ttl or default_ttl) then
                    expired = expired + 1
                end
            end
            
            return {
                name = cache_name,
                total_entries = total,
                expired_entries = expired,
                valid_entries = total - expired,
                default_ttl = default_ttl
            }
        end,
        
        -- Cleanup expired entries (memory management)
        cleanup = function()
            local to_remove = {}
            
            for key, entry in pairs(cache_store) do
                if not is_cache_valid(entry, entry.ttl or default_ttl) then
                    table.insert(to_remove, key)
                end
            end
            
            for _, key in ipairs(to_remove) do
                cache_store[key] = nil
            end
            
            if #to_remove > 0 then
                debug.log_context("Cache", string.format("[%s] cleaned up %d expired entries", cache_name, #to_remove))
            end
            
            return #to_remove
        end
    }
    
    debug.log_context("Cache", string.format("created cache instance: %s (default TTL: %dms)", cache_name, default_ttl))
    
    return cache_instance
end

-- Global cleanup function for all cache instances (useful for plugin disable)
function M.cleanup_all()
    -- This would require tracking all instances, but for now we'll rely on 
    -- providers to handle their own cleanup via their cache.cleanup() calls
    debug.log_context("Cache", "global cleanup requested - providers should handle their own cleanup")
end

return M