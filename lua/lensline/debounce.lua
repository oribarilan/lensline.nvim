-- Debounce utility for event-based refresh system
-- Provides provider-scoped debouncing to prevent excessive updates

local M = {}

-- Store active timers by provider and buffer
local active_timers = {}

-- Helper function to create timer key
local function get_timer_key(provider, bufnr)
    return provider .. ":" .. tostring(bufnr)
end

-- Debounce function with provider and buffer scoping
-- @param provider string: provider name (e.g., "git", "lsp")
-- @param bufnr number: buffer number
-- @param fn function: function to execute after debounce delay
-- @param delay_ms number: delay in milliseconds
function M.debounce(provider, bufnr, fn, delay_ms)
    local key = get_timer_key(provider, bufnr)
    
    -- Cancel existing timer for this provider/buffer combination
    if active_timers[key] then
        if not active_timers[key]:is_closing() then
            active_timers[key]:stop()
            active_timers[key]:close()
        end
        active_timers[key] = nil
    end
    
    -- Create new timer
    local timer = vim.loop.new_timer()
    active_timers[key] = timer
    
    timer:start(delay_ms, 0, function()
        vim.schedule(function()
            -- Clean up timer
            if active_timers[key] == timer then
                timer:close()
                active_timers[key] = nil
            end
            
            -- Execute the function
            fn()
        end)
    end)
end

-- Cancel all debounce timers for a specific buffer
-- @param bufnr number: buffer number
function M.cancel_buffer_timers(bufnr)
    local bufnr_str = tostring(bufnr)
    local to_remove = {}
    
    for key, timer in pairs(active_timers) do
        if key:match(":" .. bufnr_str .. "$") then
            if not timer:is_closing() then
                timer:stop()
                timer:close()
            end
            table.insert(to_remove, key)
        end
    end
    
    for _, key in ipairs(to_remove) do
        active_timers[key] = nil
    end
end

-- Cancel all debounce timers for a specific provider
-- @param provider string: provider name
function M.cancel_provider_timers(provider)
    local prefix = provider .. ":"
    local to_remove = {}
    
    for key, timer in pairs(active_timers) do
        if key:match("^" .. vim.pesc(prefix)) then
            if not timer:is_closing() then
                timer:stop()
                timer:close()
            end
            table.insert(to_remove, key)
        end
    end
    
    for _, key in ipairs(to_remove) do
        active_timers[key] = nil
    end
end

-- Cleanup all active timers (called on plugin disable)
function M.cleanup_all()
    for key, timer in pairs(active_timers) do
        if not timer:is_closing() then
            timer:stop()
            timer:close()
        end
    end
    active_timers = {}
end

-- Get active timer count (for debugging)
function M.get_active_count()
    local count = 0
    for _ in pairs(active_timers) do
        count = count + 1
    end
    return count
end

return M