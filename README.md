# lensline.nvim

[![Neovim](https://img.shields.io/badge/Neovim%200.8+-green.svg?style=for-the-badge&logo=neovim)](https://neovim.io)

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

<details>
<summary><strong>complexity Provider</strong> - Code complexity analysis</summary>

**Provider Name**: `complexity`

**Events**: `BufWritePost`, `TextChanged`

**What it shows**: Function complexity indicators using research-based scoring that analyzes control flow patterns (branches, loops, conditionals) rather than superficial metrics like line count.

**Display Format**: `Cx: S/M/L/XL` where:
- **S** (Small) - Simple sequential functions
- **M** (Medium) - Functions with basic branching
- **L** (Large) - Functions with significant complexity
- **XL** (Extra Large) - Highly complex functions

**Configuration**:
- `enabled`: Enable/disable the provider (default: `false`)
- `min_level`: Minimum complexity level to display (default: `"L"`) - filters out noise from simple functions

**Example**:
```lua
{
  name = "complexity",
  enabled = true,
  min_level = "L",  -- only show L and XL complexity (default)
}
```

To show all complexity levels including simple functions:
```lua
{
  name = "complexity",
  enabled = true,
  min_level = "S",  -- show all: S, M, L, XL
}
```

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
* [x] Configurable layout style
* [x] Per-provider debounce timing
* [x] Toggle command (`:LenslineToggle`)
* [x] LSP progress message filtering
* [ ] Clickable lenses with `vim.ui.select` actions
* [ ] Test coverage provider
* [x] Method complexity provider (research-based scoring with configurable filtering)
* [ ] Class level lens
* [ ] Diagnostics provider (errors/warnings per function)
* [ ] References - some LSP count self, some don't, address this

## Contribute

PRs, issues, and suggestions welcome.

For development setup, debugging, and technical details, see [CONTRIBUTE.md](CONTRIBUTE.md).

### Quick Development Setup

Set `debug_mode = true` in your config to enable file-based debug logging:

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
    
    -- Add debug command for easy access to logs
    vim.api.nvim_create_user_command('LenslineDebug', function()
      local debug = require('lensline.debug')
      local debug_file = debug.get_debug_file()
      if debug_file and vim.loop.fs_stat(debug_file) then
        vim.cmd('edit ' .. debug_file)
      else
        print('No debug file found. Enable debug_mode in your config.')
      end
    end, {})
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