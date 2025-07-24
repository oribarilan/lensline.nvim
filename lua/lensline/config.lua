local M = {}

M.defaults = {
    providers = {
        references = true,
    },
    style = {
        separator = " • ",
        highlight = "Comment",
        prefix = "┃ ",
    },
    refresh = {
        events = { "BufWritePost", "CursorHold", "LspAttach" },
        debounce_ms = 150,
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