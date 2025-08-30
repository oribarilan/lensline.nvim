-- Minimal Neovim configuration for lensline bug reproduction
-- Uses Lazy package manager to install lensline automatically

-- Basic settings
vim.opt.number = true
vim.opt.signcolumn = "yes"

-- Clipboard settings - share with OS clipboard
vim.opt.clipboard = "unnamedplus"

-- Leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

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
      
      -- LSP status check for debugging
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "lua",
        callback = function()
          vim.defer_fn(function()
            local clients = vim.lsp.get_clients({bufnr = 0})
            if #clients == 0 then
              print("⚠ No LSP clients. Use :Mason to check status or :LenslineDebug for logs")
            end
          end, 2000)
        end,
      })
    end,
  },
  -- Telescope for file navigation
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("telescope").setup({})
      
      -- Key bindings
      local builtin = require("telescope.builtin")
      vim.keymap.set("n", "<leader>sf", builtin.find_files, { desc = "Search files" })
      vim.keymap.set("n", "<leader>sg", builtin.live_grep, { desc = "Search grep" })
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