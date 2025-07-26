-- Silent Progress - LSP progress message filtering to suppress known spam
-- Surgically suppresses specific noisy progress messages (e.g., Pyright "Finding references")
-- while preserving all other LSP functionality

local M = {}

local original_progress_handler = nil
local suppressed_tokens = {}  -- Track tokens for spammy operations
local token_cleanup_timer = nil

-- Known spammy progress messages to suppress
-- Structure: [lsp_client_name] = { [progress_title] = true }
local SPAM_PATTERNS = {
    pyright = {
        ["Finding references"] = true,
        -- Add other spammy Pyright messages here if discovered
    }
    -- Add other LSP servers here if needed:
    -- pylsp = {
    --     ["Some spammy message"] = true,
    -- }
}

local function cleanup_stale_tokens()
    -- Clear all tokens every 5 minutes to prevent memory leaks
    -- This handles cases where begin events don't get matching end events
    suppressed_tokens = {}
end

local function setup_token_cleanup()
    if token_cleanup_timer then
        return
    end
    
    token_cleanup_timer = vim.loop.new_timer()
    token_cleanup_timer:start(300000, 300000, vim.schedule_wrap(cleanup_stale_tokens)) -- 5 minutes
end

local function create_progress_handler()
    return function(err, result, ctx, config)
        local client = vim.lsp.get_client_by_id(ctx.client_id)
        
        -- Only check clients we have spam patterns for (performance optimization)
        if client and SPAM_PATTERNS[client.name] and result and result.value then
            local token = result.token
            local kind = result.value.kind
            local title = result.value.title
            local spam_patterns = SPAM_PATTERNS[client.name]
            
            -- Track spammy operations by their token
            if kind == "begin" and title and spam_patterns[title] then
                suppressed_tokens[token] = true
                return  -- 🧹 Suppress begin event
            end
            
            -- Suppress end events for tracked spammy operations
            if kind == "end" and suppressed_tokens[token] then
                suppressed_tokens[token] = nil  -- Clean up
                return  -- 🧹 Suppress corresponding end event
            end
        end
        
        -- Allow all other progress messages through
        if original_progress_handler then
            return original_progress_handler(err, result, ctx, config)
        end
    end
end

function M.setup()
    local debug = require("lensline.debug")
    
    -- Store original handler if we haven't already
    if not original_progress_handler then
        original_progress_handler = vim.lsp.handlers["$/progress"]
    end
    
    setup_token_cleanup()
    
    -- Install our filtering handler
    vim.lsp.handlers["$/progress"] = create_progress_handler()
    
    debug.log_context("Silent Progress", "LSP progress filtering enabled - suppressing known spam")
end

function M.teardown()
    -- Restore original progress handler
    if original_progress_handler then
        vim.lsp.handlers["$/progress"] = original_progress_handler
        original_progress_handler = nil
    end
    
    -- Clean up timer and tokens
    if token_cleanup_timer then
        if not token_cleanup_timer:is_closing() then
            token_cleanup_timer:stop()
            token_cleanup_timer:close()
        end
        token_cleanup_timer = nil
    end
    
    suppressed_tokens = {}
end

function M.clear_tokens()
    -- Clear tokens when LSP clients detach to prevent memory leaks
    suppressed_tokens = {}
end

-- For debugging/inspection
function M.get_spam_patterns()
    return SPAM_PATTERNS
end

function M.get_suppressed_count()
    local count = 0
    for _ in pairs(suppressed_tokens) do
        count = count + 1
    end
    return count
end

return M