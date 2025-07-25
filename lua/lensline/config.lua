local M = {}

M.defaults = {
    providers = {
        lsp = {
            enabled = true,     -- enable lsp provider
            performance = {
                cache_ttl = 30000,   -- cache time-to-live in milliseconds (30 seconds)
            },
            -- collectors are auto-loaded from lsp/collectors/ directory
            -- to customize, set providers.lsp.collectors = { your_functions }
            -- see test_collector_config.lua for examples
        },
        diagnostics = {
            enabled = true,     -- enable diagnostics provider
            -- collectors are auto-loaded from diagnostics/collectors/ directory
        },
    },
    style = {
        separator = " • ",
        highlight = "Comment",
        prefix = "┃ ",
    },
    refresh = {
        events = { "BufWritePost", "CursorHold", "LspAttach", "InsertLeave", "TextChanged" },
        debounce_ms = 150,   -- global debounce for all providers
    },
    debug_mode = false,
}

M.options = {}

function M.setup(opts)
    M.options = vim.tbl_deep_extend("force", M.defaults, opts)
end

function M.get()
    return M.options
end

return M