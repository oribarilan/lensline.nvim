<div align="center">

# lensline.nvim
##### A status bar for your functions

[![Neovim](https://img.shields.io/badge/Neovim%200.8+-green.svg?style=for-the-badge&logo=neovim)](https://neovim.io)
<p>
<a href="https://github.com/oribarilan/lensline.nvim/releases/latest">
    <img alt="Latest release" src="https://img.shields.io/github/v/release/oribarilan/lensline.nvim?style=for-the-badge&logo=rocket&color=C9CBFF&logoColor=D9E0EE&labelColor=302D41&include_prerelease&sort=semver" />
</a>
<a href="https://github.com/LazyVim/LazyVim/blob/main/LICENSE">
    <img alt="License" src="https://img.shields.io/github/license/oribarilan/lensline.nvim?style=for-the-badge&logo=googledocs&color=ee999f&logoColor=D9E0EE&labelColor=302D41" />
</a>
<a href="https://github.com/oribarilan/lensline.nvim">
    <img alt="Repo Size" src="https://img.shields.io/github/repo-size/oribarilan/lensline.nvim?color=%23DDB6F2&label=SIZE&logo=hackthebox&style=for-the-badge&logoColor=D9E0EE&labelColor=302D41"/>
</a>
</p>

<p>
    <img height="150" alt="lensline ape" src="https://github.com/user-attachments/assets/79904cf2-0c2b-4767-813c-3a36f7199ee0" />
</p>

</div>

# What is lensline?
A lightweight Neovim plugin that displays customizable, contextual information directly above functions, like references, diagnostics, and git authorship.

![lensline demo](https://github.com/user-attachments/assets/fa6870bd-b8b0-4b8e-a6f7-6077d835f11c)

## Why use lensline?

- **🔍 Glanceable insights**: Instantly see relevant context such as references, git authorship, and complexity, shown right above the function you’re working on.
- **🧘 Seamless & distraction-free**: Lenses appear automatically as you code, blending into your workflow without stealing focus or requiring interaction.
- **🧩 Modular & customizable**: Lens attributes are independent and configurable. Choose which ones to use, arrange them how you like, and customize their appearance, or define your own.

## Install

We recommend using the latest tagged release (`tag = '0.1.x'`) or the `release/0.1.x` branch.

<a href="https://github.com/oribarilan/lensline.nvim/releases/latest">
    <img alt="Latest release" src="https://img.shields.io/github/v/release/oribarilan/lensline.nvim?style=for-the-badge&logo=rocket&color=C9CBFF&logoColor=D9E0EE&labelColor=302D41&include_prerelease&sort=semver" />
</a>

or

<a href="https://github.com/oribarilan/lensline.nvim/tree/release/0.1.x">
  <img alt="Branch release/0.1.x" src="https://img.shields.io/static/v1?label=Branch&message=release/0.1.x&style=for-the-badge&logo=git&color=C9CBFF&labelColor=302D41&logoColor=D9E0EE" />
</a>

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'oribarilan/lensline.nvim',
  tag = '0.1.3', -- or: branch = 'release/0.1.x'
  event = 'LspAttach',
  config = function()
    require("lensline").setup()
  end,
}
```

Or with any other package manager:

<details>
<summary><strong>vim-plug</strong></summary>

```vim
Plug 'oribarilan/lensline.nvim', { 'tag': '0.1.3' }
``` 

or

```vim
Plug 'oribarilan/lensline.nvim', { 'branch': 'release/0.1.x' }
```

</details>

<details>
<summary><strong>packer.nvim</strong></summary>

```lua
use {
    'oribarilan/lensline.nvim',
    tag = '0.1.3', -- or: branch = 'release/0.1.x'
}
```
</details>

## Configure

lensline.nvim works out of the box with sensible defaults. You can customize it to your liking either with simple configuration or by writing custom providers. 

### Default Configuration

```lua
{
  'oribarilan/lensline.nvim',
  event = 'LspAttach',
  config = function()
    require("lensline").setup({
      providers = {  -- Array format: order determines display sequence
        {
          name = "ref_count",
          enabled = true,     -- enable reference count provider
          quiet_lsp = true,   -- suppress noisy LSP log messages (e.g., Pyright reference spam)
        },
        {
          name = "diag_summary",
          enabled = false,    -- (BETA) disabled by default - enable explicitly to use
          min_level = "WARN", -- only show WARN and ERROR by default (HINT, INFO, WARN, ERROR)
        },
        {
          name = "last_author",
          enabled = true,         -- enabled by default with caching optimization
          cache_max_files = 50,   -- maximum number of files to cache blame data for (default: 50)
        },
        {
          name = "complexity",
          enabled = false,    -- (BETA) disabled by default - enable explicitly to use
          min_level = "L",    -- only show L (Large) and XL (Extra Large) complexity by default
        },
      },
      style = {
        separator = " • ",      -- separator between all lens attributes
        highlight = "Comment",  -- highlight group for lens text
        prefix = "┃ ",         -- prefix before lens content
        use_nerdfont = true,    -- enable nerd font icons in built-in providers
      },
      limits = {
        exclude = { 
            -- see config.lua for extensive list of default patterns 
        },
        exclude_gitignored = true,  -- respect .gitignore by not processing ignored files
        max_lines = 1000,          -- process only first N lines of large files
        max_lenses = 70,          -- skip rendering if too many lenses generated
      },
      debounce_ms = 500,        -- unified debounce delay for all providers
      debug_mode = false,       -- enable debug output for development, see CONTRIBUTE.md
    })
  end,
}
```

### Design Philosophy

**lensline** takes an opinionated approach to defaults while prioritizing extensibility over configuration bloat:

- **Opinionated defaults**: Built-in providers to commonly-used functionality inspired by popular IDEs (VSCode, IntelliJ) - reference counts & git blame info
- **Extension over configuration**: Provider expose a minimal set of configs. For customization, lensline encourages writing custom providers

This design keeps the plugin lightweight while enabling unlimited customization. The provider based approach scales better than trying to support everything through configuration.

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
<summary><strong>diag_summary Provider (BETA)</strong> - Diagnostic aggregation</summary>

> **⚠️ Beta Feature**: This provider is currently in beta. While functional, it may have edge cases or performance considerations. Feedback and bug reports are welcome!

**Provider Name**: `diag_summary`

**Events**: `DiagnosticChanged`, `BufEnter`

**What it shows**: Aggregated diagnostic counts per function (errors, warnings, info, hints)

**Display Format**:
- With nerdfonts: `1 2 3 4` (using diagnostic icons)
- Without nerdfonts: `1E 2W 3I 4H` (E=Error, W=Warning, I=Info, H=Hint)

**Configuration**:
- `enabled`: Enable/disable the provider (default: `false` - disabled by default)
- `min_level`: Minimum diagnostic severity to display (default: `"WARN"`)
  - Valid values: `"ERROR"`, `"WARN"`, `"INFO"`, `"HINT"`
  - Can also use numeric values: `vim.diagnostic.severity.ERROR`, etc.

**Example Configuration**:
```lua
{
  name = "diag_summary",
  enabled = true,      -- Must be explicitly enabled
  min_level = "ERROR", -- Only show errors
}
```

</details>

<details>
<summary><strong>complexity Provider (BETA)</strong> - Code complexity analysis</summary>

> **⚠️ Beta Feature**: This provider is currently in beta. While the complexity analysis uses research-based heuristics, it may have edge cases, performance considerations, and may need refinement for different coding styles and languages. Feedback and bug reports are welcome!

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

### Custom Providers

lensline supports custom providers for unlimited extensibility. You can create your own provider, or contribute additional built-in ones. Please see [providers.md](providers.md) for detailed guidelines on writing custom providers.

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

## Roadmap

Currently we are focused on making out first v1.0.0 release, which focuses on core functionality and performance.

Here we are listing the core features plan. For a more detailed history of changes, please see the [CHANGELOG.md](CHANGELOG.md).

### v0.1.x
- [x] Core lensline plugin with modular provider system
- [x] 4 built-in providers: `ref_count`, `last_author`, `complexity` (beta), `diag_summary` (beta)
- [x] Customizable styling and layout options
- [x] Efficient sync function discovery
- [x] Async function discovery
- [x] Efficient rendering (batched extmark operations, incremental updates, stale-first strategy)

### v0.2.x
- [ ] Graduate beta providers (`complexity`, `diag_summary`)
- [ ] Streamlined provider API

### Potential Features (post v1.0.0)

- [ ] Test coverage provider
- [ ] Class level lens
- [ ] References - some LSP count self, some don't, address this

## Contribute

PRs, issues, and suggestions welcome.

For development setup, debugging, and technical details, see [CONTRIBUTE.md](CONTRIBUTE.md).

## Thanks to

- [lazy.nvim](https://github.com/folke/lazy.nvim) & [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for inspiration on a (hopefully) good README.md

- The inventor of the code-lens feature

- [flaticon](https://www.flaticon.com/) for the ape icon