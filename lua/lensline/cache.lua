-- Event-based cache service for lensline providers
-- Provides the cache interface with provider/buffer scoped invalidation

local debug = require("lensline.debug")

local M = {}

-- Global cache store: cache[provider][bufnr][key] = value
local cache_store = {}

-- Cache interface implementation
local cache = {
    -- Get cached value for provider/buffer/key
    get = function(provider, bufnr, key)
        if not provider or not bufnr or not key then
            return nil
        end
        
        local provider_cache = cache_store[provider]
        if not provider_cache then
            return nil
        end
        
        local buffer_cache = provider_cache[bufnr]
        if not buffer_cache then
            return nil
        end
        
        local value = buffer_cache[key]
        if value ~= nil then
            debug.log_context("Cache", string.format("[%s] cache hit for buffer %s, key: %s", provider, bufnr, key))
            return value
        end
        
        return nil
    end,
    
    -- Set cached value for provider/buffer/key  
    set = function(provider, bufnr, key, value)
        if not provider or not bufnr or not key then
            debug.log_context("Cache", "cannot set cache with nil provider/bufnr/key", "WARN")
            return
        end
        
        -- Initialize provider cache if needed
        if not cache_store[provider] then
            cache_store[provider] = {}
        end
        
        -- Initialize buffer cache if needed
        if not cache_store[provider][bufnr] then
            cache_store[provider][bufnr] = {}
        end
        
        cache_store[provider][bufnr][key] = value
        debug.log_context("Cache", string.format("[%s] cached value for buffer %s, key: %s", provider, bufnr, key))
    end,
    
    -- Invalidate all cache entries for a provider/buffer
    invalidate = function(provider, bufnr)
        if not provider or not bufnr then
            return 0
        end
        
        local provider_cache = cache_store[provider]
        if not provider_cache or not provider_cache[bufnr] then
            return 0
        end
        
        local count = 0
        for key, _ in pairs(provider_cache[bufnr]) do
            count = count + 1
        end
        
        provider_cache[bufnr] = nil
        
        if count > 0 then
            debug.log_context("Cache", string.format("[%s] invalidated %d cache entries for buffer %s", provider, count, bufnr))
        end
        
        return count
    end,
    
    -- Invalidate all cache entries for a buffer (all providers)
    invalidate_all = function(bufnr)
        if not bufnr then
            return 0
        end
        
        local total_count = 0
        
        for provider, provider_cache in pairs(cache_store) do
            if provider_cache[bufnr] then
                local count = 0
                for key, _ in pairs(provider_cache[bufnr]) do
                    count = count + 1
                end
                
                provider_cache[bufnr] = nil
                total_count = total_count + count
                
                if count > 0 then
                    debug.log_context("Cache", string.format("[%s] invalidated %d cache entries for buffer %s", provider, count, bufnr))
                end
            end
        end
        
        return total_count
    end
}

-- Expose the cache interface
M.cache = cache

-- Global cleanup function for all cache instances
function M.cleanup_all()
    local total_cleared = 0
    
    for provider, provider_cache in pairs(cache_store) do
        for bufnr, buffer_cache in pairs(provider_cache) do
            for key, _ in pairs(buffer_cache) do
                total_cleared = total_cleared + 1
            end
        end
    end
    
    cache_store = {}
    
    debug.log_context("Cache", string.format("global cleanup: cleared %d total cache entries", total_cleared))
end

-- Get global cache statistics (for debugging)
function M.get_global_stats()
    local stats = {
        providers = {},
        total_entries = 0
    }
    
    for provider, provider_cache in pairs(cache_store) do
        local provider_total = 0
        local buffer_count = 0
        
        for bufnr, buffer_cache in pairs(provider_cache) do
            buffer_count = buffer_count + 1
            for key, _ in pairs(buffer_cache) do
                provider_total = provider_total + 1
            end
        end
        
        stats.providers[provider] = {
            total_entries = provider_total,
            buffer_count = buffer_count
        }
        stats.total_entries = stats.total_entries + provider_total
    end
    
    return stats
end

return M