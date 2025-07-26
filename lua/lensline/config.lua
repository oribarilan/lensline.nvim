local M = {}

M.defaults = {
    use_nerdfonts = true,   -- enable nerd font icons in built-in collectors
    quiet_lsp = true,       -- suppress noisy LSP log messages (e.g., Pyright reference spam)
    providers = {
        lsp = {
            enabled = true,     -- enable lsp provider
            performance = {
                cache_ttl = 30000,   -- cache time-to-live in milliseconds (30 seconds)
            },
            -- collectors: uses default_collectors from providers/lsp/init.lua unless overridden
            -- to see defaults: require("lensline.providers.lsp").default_collectors
            -- to customize: set providers.lsp.collectors = { your_functions }
            -- see test_collector_config.lua for examples
        },
        diagnostics = {
            enabled = true,     -- enable diagnostics provider
            -- collectors: uses default_collectors from providers/diagnostics/init.lua unless overridden
            -- to see defaults: require("lensline.providers.diagnostics").default_collectors
        },
        git = {
            enabled = true,     -- enable git provider
            performance = {
                cache_ttl = 300000,  -- cache time-to-live in milliseconds (5 minutes)
            },
            -- collectors: uses default_collectors from providers/git/init.lua unless overridden
            -- to see defaults: require("lensline.providers.git").default_collectors
            -- to customize: set providers.git.collectors = { your_functions }
        },
    },
    style = {
        separator = " • ",
        highlight = "Comment",
        prefix = "┃ ",
    },
    refresh = {
        events = { "BufWritePost", "LspAttach", "DiagnosticChanged", "BufEnter" },
        debounce_ms = 150,   -- global debounce for all providers
    },
    debug_mode = false,
}

M.options = {}
M._enabled = false  -- global toggle state

function M.setup(opts)
    M.options = vim.tbl_deep_extend("force", M.defaults, opts)
    M._enabled = true  -- enable by default when setup is called
end

function M.get()
    return M.options
end

function M.is_enabled()
    return M._enabled
end

function M.set_enabled(enabled)
    M._enabled = enabled
end

-- LSP message filtering - surgical "Finding references" suppression
local original_progress_handler = nil
local suppressed_tokens = {}  -- Track tokens for "Finding references" operations

function M.setup_lsp_handlers()
    local opts = M.get()
    if opts.quiet_lsp == false then
        return
    end
    
    local debug = require("lensline.debug")
    
    -- Store original handler if we haven't already
    if not original_progress_handler then
        original_progress_handler = vim.lsp.handlers["$/progress"]
    end
    
    -- Surgical filtering: suppress entire "Finding references" progress cycles
    vim.lsp.handlers["$/progress"] = function(err, result, ctx, config)
        local client = vim.lsp.get_client_by_id(ctx.client_id)
        
        if client and client.name == "pyright" and result and result.value then
            local token = result.token
            local kind = result.value.kind
            local title = result.value.title
            
            -- Track "Finding references" operations by their token
            if kind == "begin" and title == "Finding references" then
                suppressed_tokens[token] = true
                debug.log_context("LSP Filter", string.format("SUPPRESSING begin: %s (token: %s)", title, token or "unknown"))
                return  -- 🧹 Suppress begin event
            end
            
            -- Suppress end events for tracked "Finding references" operations
            if kind == "end" and suppressed_tokens[token] then
                suppressed_tokens[token] = nil  -- Clean up
                debug.log_context("LSP Filter", string.format("SUPPRESSING end: (token: %s)", token or "unknown"))
                return  -- 🧹 Suppress corresponding end event
            end
        end
        
        -- Allow all other progress messages through
        if original_progress_handler then
            return original_progress_handler(err, result, ctx, config)
        end
    end
    
    debug.log_context("LSP Filter", "Surgical LSP filtering enabled - suppressing only 'Finding references' progress")
end

function M.restore_lsp_handlers()
    -- Restore original progress handler when disabling
    if original_progress_handler then
        vim.lsp.handlers["$/progress"] = original_progress_handler
        original_progress_handler = nil
    end
end

return M