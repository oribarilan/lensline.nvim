-- Minimal Neovim configuration for lensline bug reproduction
-- Uses Lazy package manager to install lensline automatically

-- Basic settings
vim.opt.number = true
vim.opt.signcolumn = "yes"

-- Disable built-in plugins that might interfere
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- Setup lazy.nvim
require("lazy").setup({
  -- Mason for LSP management
  {
    "williamboman/mason.nvim",
    config = function()
      require("mason").setup()
      print("Mason initialized. Installing lua-language-server...")
    end,
  },
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "mason.nvim" },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = { "lua_ls" },
        automatic_installation = true,
      })
      print("Mason-lspconfig setup complete. LSP servers will install automatically.")
    end,
  },
  {
    "neovim/nvim-lspconfig",
    dependencies = { "mason-lspconfig.nvim" },
    config = function()
      local lspconfig = require("lspconfig")
      
      -- Setup LSP directly - simpler and more reliable
      lspconfig.lua_ls.setup({
        settings = {
          Lua = {
            runtime = {
              version = 'LuaJIT',
            },
            diagnostics = {
              globals = {'vim'},
            },
            workspace = {
              library = vim.api.nvim_get_runtime_file("", true),
            },
            telemetry = {
              enable = false,
            },
          },
        }
      })
      
      -- Add autocmd to check LSP status when opening Lua files
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "lua",
        callback = function()
          vim.defer_fn(function()
            local clients = vim.lsp.get_clients({bufnr = 0})
            if #clients > 0 then
              print("✓ LSP clients active:", vim.tbl_map(function(c) return c.name end, clients))
            else
              print("⚠ No LSP clients yet. Mason may still be installing lua_ls.")
              print("  Run :Mason to check installation status")
              print("  Wait a moment and reopen the file")
            end
          end, 2000)
        end,
      })
      
      print("LSP configured with Mason. Installing lua_ls automatically...")
      print("DEBUG: To see debug output, use:")
      print("  - :messages (to see print() output)")
      print("  - :LspLog (to see LSP logs)")
      print("  - :LenslineDebug (for lensline debug info)")
      print("  - :Mason (to see Mason status)")
    end,
  },
  {
    "oribarilan/lensline.nvim",
    dependencies = { "nvim-lspconfig" },
    config = function()
      require("lensline").setup({
        debug_mode = true,  -- Enable debug logging for bug reports
        providers = {
          { name = "references", enabled = true },
          { name = "last_author", enabled = true },
        }
      })
      print("Lensline loaded with debug mode enabled. Use :LenslineDebug for logs.")
    end,
  }
}, {
  -- Lazy configuration
  install = {
    missing = true,
  },
  checker = {
    enabled = false,
  },
})