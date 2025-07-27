# lensline.nvim

A lightweight Neovim plugin that displays contextual information about functions using virtual text lenses.

* **Batteries included** so you can just use it out of the box with ref count and last author (git blame) info
* **Make it your own** with custom providers for your own data sources

## Install

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'oribarilan/lensline.nvim',
  event = 'LspAttach',
  config = function()
    require("lensline").setup()
  end,
}
```

## Configure

lensline.nvim works out of the box with sane defaults. You can customize what data is shown, how it looks, and when it's refreshed.

### Default Configuration

```lua
{
  'oribarilan/lensline.nvim',
  event = 'LspAttach',
  config = function()
    require("lensline").setup({
      use_nerdfonts = true,     -- enable nerd font icons in built-in providers
      providers = {  -- Array format: order determines display sequence
        {
          name = "ref_count",
          enabled = true,         -- show LSP reference counts
          quiet_lsp = true,       -- suppress noisy LSP progress messages (default: true)
        },
        {
          name = "last_author",
          enabled = true,         -- show git blame info (latest author + time)
        },
      },
      style = {
        separator = " • ",      -- separator between all lens parts
        highlight = "Comment",  -- highlight group for lens text
        prefix = "┃ ",         -- prefix before lens content
      },
      debug_mode = false,       -- enable debug output for development
    })
  end,
}
```

### Architecture: Simple Providers

**lensline** uses a simple **Provider** architecture:

- **Providers** are self-contained modules that handle specific data sources (LSP, git, etc.)
- Each provider defines its own event triggers, debounce timing, and data collection logic
- Providers return lens items with line numbers and formatted text for display

### Design Philosophy

**lensline** takes an opinionated approach to defaults while prioritizing extensibility over configuration bloat:

- **Opinionated defaults**: Built-in collectors provide commonly-used functionality inspired by popular IDEs (VSCode, IntelliJ) - reference counts, diagnostic summaries, git blame info
- **Extension over configuration**: Rather than adding endless config options for styling and filtering, lensline encourages writing custom collectors for specific needs
- **Clean collector API**: Simple function signature makes it easy to create custom collectors that integrate seamlessly with the existing system
- **No configuration bloat**: Instead of complex nested options, customization happens through code - more powerful and maintainable

This design keeps the plugin lightweight while enabling unlimited customization. The collector-based approach scales better than trying to support everything through configuration.

### Built-in Providers

<details>
<summary><strong>ref_count Provider</strong> - LSP reference counting</summary>

**Provider Name**: `ref_count`

**Events**: `LspAttach`, `BufWritePost`

**What it shows**: Number of references to functions/methods using LSP `textDocument/references`

**Configuration**:
- `enabled`: Enable/disable the provider (default: `true`)
- `quiet_lsp`: Suppress noisy LSP progress messages like "Finding references..." (default: `true`). This occures with Pyright in combination with noice.nvim or fidget.nvim.

</details>

<details>
<summary><strong>last_author Provider</strong> - Git blame information</summary>

**Provider Name**: `last_author`

**Events**: `BufRead`, `BufWritePost`

**What it shows**: Most recent git author and relative time for each function

</details>

### Creating Custom Providers

You can create custom providers by adding them to the provider registry. A provider is a Lua module that returns a table with the following structure:

```lua
-- custom_provider.lua
return {
  name = "my_custom_provider",
  event = { "BufWritePost" },  -- events that trigger this provider
  debounce = 1000,             -- debounce delay in milliseconds
  handler = function(bufnr, func_info, callback)
    -- bufnr: buffer number
    -- func_info: { line = number, name = string, character = number }
    -- callback: function to call with result (for async) or nil (for sync)
    
    -- Your custom logic here
    local custom_data = get_my_custom_data(func_info)
    
    -- For synchronous providers, return the lens item:
    if not callback then
      return {
        line = func_info.line,
        text = "💩 " .. custom_data
      }
    end
    
    -- For async providers, call the callback:
    callback({
      line = func_info.line,
      text = "💩 " .. custom_data
    })
    return nil
  end
}
```

Then register it in your configuration by adding it to the providers registry:

```lua
-- Add your custom provider to the registry
local providers = require("lensline.providers")
providers.available_providers.my_custom_provider = require("path.to.custom_provider")

require("lensline").setup({
  providers = {
    { name = "ref_count", enabled = true },
    { name = "my_custom_provider", enabled = true },
  }
})
```

## Commands

### `:LenslineToggle`

Toggle the entire lensline functionality on and off. When disabled, ALL extension functionality is turned off and no resources are used for collecting lens attributes.

```vim
:LenslineToggle
```

You can also control this programmatically:

```lua
local lensline = require("lensline")

-- check current state
if lensline.is_enabled() then
  print("Lensline is enabled")
end

-- manually enable/disable
lensline.enable()
lensline.disable()

-- toggle
lensline.toggle()
```

## Potential Features

* [x] Function-level metadata display
* [x] LSP reference count support
* [x] Git blame author display
* [x] Custom provider API for extensibility
* [x] Configurable styling and layout
* [x] Per-provider debounce timing
* [x] Toggle command (`:LenslineToggle`)
* [x] LSP progress message filtering
* [ ] Telescope integration for lens search
* [ ] Clickable lenses with `vim.ui.select` actions
* [ ] Test coverage provider
* [ ] Method complexity provider
* [ ] Class level lens
* [ ] Diagnostics provider (errors/warnings per function)
* [ ] References - some LSP count self, some don't, address this

## Contribute

PRs, issues, and suggestions welcome.

### debugging

set `debug_mode = true` in your config to enable file-based debug logging. use `:LenslineDebug` to view the trace file with detailed lsp request/response info and function detection logs.

Minimal plugin configuration for development, with lazy.nvim package manager:

```lua
return {
  dir = '~/path/to/lensline.nvim', -- Path to your local lensline.nvim clone
  dev = true, -- Enables development mode
  event = 'BufReadPre',
  config = function()
    require("lensline").setup({
      debug_mode = true,  -- enable debug logging
      providers = {
        { name = "ref_count", enabled = true },
        { name = "last_author", enabled = true },
      }
    })
  end,
}
```

### File Structure

```
lensline.nvim/
├── lua/
│   └── lensline/
│       ├── init.lua         -- Plugin entry point
│       ├── config.lua       -- Configuration management
│       ├── setup.lua        -- Setup logic and orchestration
│       ├── renderer.lua     -- Virtual text rendering and extmark management
│       ├── debug.lua        -- Debug logging system
│       ├── utils.lua        -- Shared helper functions
│       └── providers/
│           ├── init.lua     -- Provider coordination and registry
│           ├── ref_count.lua -- LSP reference counting provider
│           └── last_author.lua -- Git blame provider
├── README.md                -- Plugin documentation
├── LICENSE                  -- License file
```