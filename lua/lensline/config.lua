local M = {}

M.defaults = {
    providers = {
        lsp = {
            references = true,  -- enable lsp references feature
            enabled = true,     -- enable lsp provider (defaults to true if absent)
            performance = {
                debounce_ms = 150,   -- delay before triggering after burst of events
                cache_ttl = 30000,   -- cache time-to-live in milliseconds (30 seconds)
            },
        },
    },
    style = {
        separator = " • ",
        highlight = "Comment",
        prefix = "┃ ",
    },
    refresh = {
        events = { "BufWritePost", "CursorHold", "LspAttach", "InsertLeave", "TextChanged" },
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