local M = {}

M.defaults = {
  use_nerdfonts = true,   -- enable nerd font icons in built-in providers
  providers = {  -- Array format: order determines display sequence
    {
      name = "lsp_references",
      enabled = true,     -- enable lsp references provider
    },
  },
  style = {
    separator = " • ",
    highlight = "Comment",
    prefix = "┃ ",
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