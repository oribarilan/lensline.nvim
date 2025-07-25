local M = {}

M.defaults = {
    providers = {
        lsp = {
            references = true,  -- enable lsp references feature
            enabled = true,     -- enable lsp provider (defaults to true if absent)
            performance = {
                cache_ttl = 30000,   -- cache time-to-live in milliseconds (30 seconds)
            },
        },
        diagnostics = {
            enabled = true,     -- enable diagnostics provider (defaults to true if absent)
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