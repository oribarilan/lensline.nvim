# lensline.nvim

##### A statusline for your functions.

[![Neovim](https://img.shields.io/badge/Neovim%200.7+-green.svg?style=for-the-badge\&logo=neovim)](https://neovim.io)

<!-- <img alt="lensline" height="260" src="/assets/lensline_banner.png" /> -->

Inline metadata for your code: references, Git blame, and more — right where it matters.

## Planned v1 Features

* **Function-level info**: Display info above functions and methods
* **LSP support**: Show reference counts using built-in LSP, if available
* **Git integration**: Display last modified author using `git blame`, if available
* **Extensible providers**: Plug in your own data sources for any lens component imagined
* **Highly configurable**: Customize style, layout, icons, and more

## Install

```lua
{
  'oribarilan/lensline.nvim',
  event = 'BufReadPre',
  config = function()
    require("lensline").setup()
  end,
}
```

## Configure

lensline.nvim works out of the box with sane defaults. You can customize what data is shown, how it looks, and when it's refreshed.

### Default Configuration

```lua
require("lensline").setup({
  providers = {
    lsp = {
      references = true,    -- enable lsp references feature
      enabled = true,       -- enable lsp provider
      performance = {
        cache_ttl = 30000,  -- cache time-to-live in milliseconds (30 seconds)
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
    debounce_ms = 300,    -- global debounce to trigger refresh (caching used)
  },
  debug_mode = false, -- Enable debug output
})
```

### Built-in Providers

* `lsp`: LSP-based information (references, definitions, etc.)
* `git`: Git-based information (author, blame, etc.) [planned]

### Performance Controls

Global performance controls:
* `refresh.debounce_ms`: single debounce delay for all providers

Per-provider performance controls under `performance` table:
* `cache_ttl`: cache duration in milliseconds

Provider-level controls:
* `enabled`: enable/disable entire provider (defaults to true)
* `references`: enable/disable specific features within provider

### Styling Options

* `separator`: Delimiter between different providers
* `highlight`: Highlight group used for lens text
* `prefix`: Optional prefix before lens content (e.g., "┃ ", ">> ")

### Refresh Options

* `events`: List of autocommands to trigger refresh
* `debounce_ms`: Global debounce for all providers (single UI update)

## Roadmap

* Core features:
* [x] Function-level metadata display
* [x] LSP reference count support
* [ ] Git blame author display
* [x] Custom provider API for extensibility
* [x] Configurable styling and layout
* [x] Debounce refresh for performance
* [ ] Extended LSP features (e.g., diagnostics, definitions)
* Other features:
* [ ] Telescope integration for lens search
* [ ] Clickable lenses with `vim.ui.select` actions
* [ ] Test coverage provider (future)
* [ ] Custom format strings per provider

## Contribute

PRs, issues, and suggestions welcome.

### debugging

set `debug_mode = true` in your config to enable file-based debug logging. use `:LenslineDebug` to view the trace file with detailed lsp request/response info and function detection logs.

```lua
require("lensline").setup({
  debug_mode = true  -- creates trace file in nvim cache dir
})
```

### disabling providers

to disable an entire provider, set `enabled = false`:

```lua
require("lensline").setup({
  providers = {
    lsp = {
      enabled = false  -- disable entire lsp provider
    }
  }
})
```

to disable specific features within a provider:

```lua
require("lensline").setup({
  providers = {
    lsp = {
      references = false  -- disable lsp reference counts only
    }
  }
})
```

### File Structure

```
lensline.nvim/
├── lua/
│   └── lensline/
│       ├── init.lua         -- Plugin entry point (required by `require("lensline")`)
│       ├── core.lua         -- Core logic and setup
│       ├── renderer.lua     -- Virtual text rendering and extmark management
│       ├── providers/
│       │   ├── init.lua     -- Aggregates provider modules
│       │   ├── lsp.lua      -- Reference count provider via LSP
│       │   └── git.lua      -- Git blame author provider
│       └── utils.lua        -- Shared helper functions
├── README.md                -- Plugin documentation
├── LICENSE                  -- License file (e.g. MIT)
```