-- Collector utility functions for priority-based ordering
local M = {}

-- Normalize collector input to standard format
local function normalize_collector(collector, index)
    if type(collector) == "function" then
        -- Plain function: use default priority
        return {
            priority = math.huge, -- no priority = goes last
            collect = collector,
            _original_index = index
        }
    elseif type(collector) == "table" and #collector == 2 then
        -- Tuple format: {function, priority}
        return {
            priority = collector[2],
            collect = collector[1],
            _original_index = index
        }
    elseif type(collector) == "table" and collector.collect then
        -- Object format: {collect = fn, priority = num}
        return {
            priority = collector.priority or math.huge,
            collect = collector.collect,
            _original_index = index
        }
    else
        error("Invalid collector format: " .. vim.inspect(collector))
    end
end

-- Sort collectors by priority with deterministic fallback
function M.sort_collectors(collectors)
    local normalized = {}
    
    -- Normalize all collectors
    for i, collector in ipairs(collectors) do
        table.insert(normalized, normalize_collector(collector, i))
    end
    
    -- Sort by priority, then by original index
    table.sort(normalized, function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        return a._original_index < b._original_index
    end)
    
    return normalized
end

return M