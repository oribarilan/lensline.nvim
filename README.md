# lensline.nvim

A lightweight Neovim plugin that displays contextual information about functions using virtual text lenses.

## Core Features

* **Function-level info**: Display info above functions and methods
* **LSP**: Show reference counts using built-in LSP, if available
* **Diagnostics**: Display diagnostics for functions and lines
* **Git**: Display last author, if available
* **Extensible providers & collectors**: Plug in your own data sources using the provider-collector architecture
* **Highly configurable**: Customize style, layout, icons, and more

## Install

```lua
{
  'oribarilan/lensline.nvim',
  event = 'LspAttach',
  config = functio 
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
      enabled = true,       -- enable lsp provider
      performance = {
        cache_ttl = 30000,  -- cache time-to-live in milliseconds (30 seconds)
      },
      -- collectors: uses default_collectors from providers/lsp/init.lua unless overridden
      -- to see defaults: require("lensline.providers.lsp").default_collectors
      -- to customize: set providers.lsp.collectors = { your_functions }
    },
    diagnostics = {
      enabled = true,       -- enable diagnostics provider
      -- collectors: uses default_collectors from providers/diagnostics/init.lua unless overridden
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
  debug_mode = false, -- Enable debug output, use for development
})
```

### Architecture: Providers and Collectors

**lensline** uses a **Provider-Collector** architecture for extensibility:

- **Providers** manage domain-specific resources (LSP clients, diagnostics, git repos)
- **Collectors** are functions that generate lens text using provider context
- Built-in collectors handle common use cases, custom collectors enable unlimited extensibility

### Built-in Providers & Collectors

* `lsp`: LSP-based information
  - `references`: Reference counting with smart async updates
* `diagnostics`: Diagnostic information
  - `function_level`: Errors, warnings, info, hints aggregated per function
* `git`: Git-based information [planned]

### Customizing Collectors

You can override default collectors with custom functions:

```lua
local lsp = require("lensline.providers.lsp")

require("lensline").setup({
  providers = {
    lsp = {
      collectors = {
        -- use built-in collector
        lsp.collectors.references,
        
        -- add custom collector
        function(lsp_context, function_info)
          local my_data = get_my_custom_data(function_info)
          return "custom: %s", my_data
        end
      }
    }
  }
})
```

### Performance Controls

Global performance controls:
* `refresh.debounce_ms`: single debounce delay for all providers

Per-provider performance controls under `performance` table:
* `cache_ttl`: cache duration in milliseconds

Provider-level controls:
* `enabled`: enable/disable entire provider (defaults to true)
* `collectors`: array of collector functions (uses provider defaults if not specified)

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
* [x] Extended LSP features (diagnostics)
* [ ] Extended LSP features (definitions)
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

to customize collectors within a provider:

```lua
require("lensline").setup({
  providers = {
    lsp = {
      collectors = {
        -- only enable custom collectors, disable built-in defaults
        function(lsp_context, function_info)
          return "custom: %s", "data"
        end
      }
    }
  }
})
```

### Known Issues

* **C# Reference Counts**: May show +1 due to LSP server differences in handling `includeDeclaration`

### File Structure

```
lensline.nvim/
├── lua/
│   └── lensline/
│       ├── init.lua         -- Plugin entry point
│       ├── core.lua         -- Core logic and setup
│       ├── renderer.lua     -- Virtual text rendering and extmark management
│       ├── infrastructure/
│       │   ├── function_discovery.lua -- Shared function discovery
│       │   └── lens_manager.lua       -- Orchestration layer
│       ├── providers/
│       │   ├── init.lua     -- Provider coordination
│       │   ├── lsp/
│       │   │   ├── init.lua           -- LSP provider
│       │   │   └── collectors/
│       │   │       └── references.lua -- Reference counting collector
│       │   └── diagnostics/
│       │       ├── init.lua           -- Diagnostics provider
│       │       └── collectors/
│       │           └── function_level.lua -- Function diagnostics collector
│       └── utils.lua        -- Shared helper functions
├── README.md                -- Plugin documentation
├── LICENSE                  -- License file
```