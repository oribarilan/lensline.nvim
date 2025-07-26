local M = {}

M.defaults = {
    use_nerdfonts = true,   -- enable nerd font icons in built-in collectors
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

return M