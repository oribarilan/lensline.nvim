local M = {}

M.defaults = {
    use_nerdfonts = true,   -- enable nerd font icons in built-in collectors
    providers = {  -- Array format: order determines display sequence
        {
            type = "lsp",
            enabled = true,     -- enable lsp provider
            silent_progress = true,  -- silently suppress LSP progress spam (e.g., Pyright "Finding references")
                                    -- only affects known spammy progress messages surfaced by noice.nvim/fidget.nvim
                                    -- has no effect on other LSPs or other Pyright events (diagnostics, hover, etc.)
            performance = {
                cache_ttl = 30000,   -- cache time-to-live in milliseconds (30 seconds)
            },
            -- collectors: array of functions, order determines display order
            -- collectors = { function1, function2, function3 }
        },
        {
            type = "diagnostics",
            enabled = true,     -- enable diagnostics provider
            -- collectors: array of functions, order determines display order
        },
        {
            type = "git",
            enabled = true,     -- enable git provider
            performance = {
                cache_ttl = 300000,  -- cache time-to-live in milliseconds (5 minutes)
            },
            -- collectors: array of functions, order determines display order
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

-- LSP progress filtering setup
function M.setup_lsp_handlers()
    local opts = M.get()
    
    -- Find LSP config in array format
    local lsp_config = nil
    for _, provider_config in ipairs(opts.providers) do
        if provider_config.type == "lsp" then
            lsp_config = provider_config
            break
        end
    end
    
    -- Check if LSP silent_progress is enabled (default: true)
    if lsp_config and lsp_config.silent_progress ~= false then
        local silent_progress = require("lensline.silent_progress")
        silent_progress.setup()
    end
end

function M.restore_lsp_handlers()
    local silent_progress = require("lensline.silent_progress")
    silent_progress.teardown()
end

function M.clear_suppressed_tokens()
    local silent_progress = require("lensline.silent_progress")
    silent_progress.clear_tokens()
end

return M