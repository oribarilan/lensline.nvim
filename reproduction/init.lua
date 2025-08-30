-- Minimal Neovim configuration for lensline bug reproduction

-- Basic settings
vim.opt.number = true
vim.opt.signcolumn = "yes"

-- Disable plugins that might interfere
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Add lensline to runtime path (modify this path as needed)
local lensline_path = "/repro/lensline.nvim"
vim.opt.rtp:prepend(lensline_path)

-- Setup lensline with debug mode
local function setup_lensline()
  local ok, lensline = pcall(require, "lensline")
  if not ok then
    print("ERROR: lensline.nvim not found. Clone it to " .. lensline_path)
    return
  end
  
  lensline.setup({
    debug_mode = true,  -- Enable debug logging
    providers = {
      { name = "references", enabled = true },
      { name = "last_author", enabled = true },
    }
  })
  
  print("Lensline loaded. Use :LenslineDebug for logs")
end

-- Auto-setup
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.defer_fn(setup_lensline, 100)
  end,
})

-- LSP setup for Python
vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function()
    vim.lsp.start({
      name = "pyright",
      cmd = { "pyright-langserver", "--stdio" },
      root_dir = vim.fn.getcwd(),
    })
  end,
})