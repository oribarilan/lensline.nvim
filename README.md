<div align="center">

# lensline.nvim
##### A status bar for your functions

[![Neovim v0.8.3](https://img.shields.io/github/actions/workflow/status/oribarilan/lensline.nvim/ci.yml?branch=main&label=Neovim%20v0.8.3)](https://github.com/oribarilan/lensline.nvim/actions/workflows/ci.yml?query=branch%3Amain) [![Neovim stable](https://img.shields.io/github/actions/workflow/status/oribarilan/lensline.nvim/ci.yml?branch=main&label=Neovim%20stable)](https://github.com/oribarilan/lensline.nvim/actions/workflows/ci.yml?query=branch%3Amain)
 

<p>

[![Neovim](https://img.shields.io/badge/Neovim%200.8+-green.svg?style=for-the-badge&logo=neovim)](https://neovim.io)

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

</div>

# 💡 What is lensline?
A lightweight Neovim plugin that displays customizable, contextual information directly above (or beside) functions, like references and authorship.

<p align="center">
  <img alt="lensline demo" src="https://github.com/user-attachments/assets/40235fbf-be12-4f35-ad57-efe49aa244e2" width="50%" />
</p>

## 🎯 Why use lensline?

- **🔍 Glanceable insights**: Instantly see relevant context such as references, git authorship, and complexity, shown right above the function you’re working on.
- **🧘 Seamless & distraction-free**: Lenses appear automatically as you code, blending into your workflow without stealing focus or requiring interaction.
- **🧩 Modular & customizable**: Lens attributes are independent and configurable. Choose which ones to use, arrange them how you like, and customize their appearance, or define your own.

## 📦 Install

We recommend using a specific tagged release (`tag = '2.0.0'`) for stability, or the `release/2.x` branch to receive the latest non-breaking updates.

<a href="https://github.com/oribarilan/lensline.nvim/releases/latest">
    <img alt="Latest release" src="https://img.shields.io/github/v/release/oribarilan/lensline.nvim?style=for-the-badge&logo=rocket&color=C9CBFF&logoColor=D9E0EE&labelColor=302D41&include_prerelease&sort=semver" />
</a>

Or

<a href="https://github.com/oribarilan/lensline.nvim/tree/release/1.x">
  <img alt="Branch release/1.x" src="https://img.shields.io/static/v1?label=Branch&message=release/1.x&style=for-the-badge&logo=git&color=C9CBFF&labelColor=302D41&logoColor=D9E0EE" />
</a>

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'oribarilan/lensline.nvim',
  tag = '2.0.0', -- or: branch = 'release/2.x' for latest non-breaking updates
  event = 'LspAttach',
  config = function()
    require("lensline").setup()
  end,
}
```

Or with any other plugin manager:

<details>
<summary><strong>vim-plug</strong></summary>

```vim
Plug 'oribarilan/lensline.nvim', { 'tag': '2.0.0' }
```

or

```vim
Plug 'oribarilan/lensline.nvim', { 'branch': 'release/1.x' }
```

</details>

<details>
<summary><strong>packer.nvim</strong></summary>

```lua
use {
    'oribarilan/lensline.nvim',
    tag = '2.0.0', -- or: branch = 'release/2.x' for latest non-breaking updates
}
```
</details>

## ⚙️ Configure

lensline.nvim works out of the box with sensible defaults. You can customize it to your liking either with simple configuration or by writing custom providers.

<details>
<summary><strong>Default Configuration</strong></summary>

> **Note**: This configuration is for the actively developed release. For v2.x configuration docs, see the [v2.x branch documentation](https://github.com/oribarilan/lensline.nvim/tree/release/2.x).

```lua
{
  'oribarilan/lensline.nvim',
  event = 'LspAttach',
  config = function()
    require("lensline").setup({
      -- Profile configuration (first profile used as default)
      -- Note: omitting 'providers' or 'style' in a profile inherits defaults
      -- You can also override just specific properties (e.g., style = { placement = "inline" })
      profiles = {
        {
          name = "default",
          providers = {  -- Array format: order determines display sequence
            {
              name = "usages",
              enabled = true,       -- enable usages provider by default (replaces references)
              include = { "refs" }, -- refs-only setup to match references provider behavior
              breakdown = true,     -- false = aggregate count, true = breakdown by type
              show_zero = true,     -- show zero counts when LSP supports the capability
              labels = {
                refs = "refs",
                impls = "impls",
                defs = "defs",
                usages = "usages",
              },
              icon_for_single = "󰌹 ",  -- icon when only one attribute or aggregate display
              inner_separator = ", ",   -- separator between breakdown items
            },
            {
              name = "last_author",
              enabled = true,         -- enabled by default with caching optimization
              cache_max_files = 50,   -- maximum number of files to cache blame data for (default: 50)
            },
            -- additional built-in or custom providers can be added here
          },
          style = {
            separator = " • ",      -- separator between all lens attributes
            highlight = "Comment",  -- highlight group for lens text
            prefix = "┃ ",         -- prefix before lens content
            placement = "above",    -- "above" | "inline" - where to render lenses (consider prefix = "" for inline)
            use_nerdfont = true,    -- enable nerd font icons in built-in providers
            render = "all",         -- "all" | "focused" (only active window's focused function)
          }
        }
        -- You can define additional profiles here and switch between them at runtime
        -- , {
        --   name = "minimal",
        --   providers = { { name = "diagnostics", enabled = true } },
        --   style = { render = "focused" }
        -- }
      }
      -- global settings (apply to all profiles)
      limits = {
        -- exclude = {
            -- file patterns that lensline will not process for lenses
            -- see config.lua for extensive list of default patterns
        -- },
        exclude_append = {},       -- additional patterns to append to exclude list (empty by default)
        exclude_gitignored = true,  -- respect .gitignore by not processing ignored files
        max_lines = 1000,          -- process only first N lines of large files
        max_lenses = 70,          -- skip rendering if too many lenses generated
      },
      debounce_ms = 500,        -- unified debounce delay for all providers
      focused_debounce_ms = 150, -- debounce delay for focus tracking in focused mode
      silence_lsp = true,       -- suppress noisy LSP log messages (e.g., Pyright reference spam)
      debug_mode = false,       -- enable debug output for development, see CONTRIBUTE.md
    })
  end,
}
```

</details>

### Style Customizations

<details>
<summary><strong>Minimalistic</strong> - Inline rendering with focused mode</summary>

For a more subtle, distraction-free experience, try this minimal configuration that renders lenses inline with your code and only shows them for the currently focused function:

<p align="center">
  <img alt="lensline minimal style" src="https://github.com/user-attachments/assets/9061c1e6-f43b-4fef-9c59-96376417629a" width="70%" />
</p>

```lua
{
  'oribarilan/lensline.nvim',
  tag = '2.0.0',
  event = 'LspAttach',
  config = function()
    require("lensline").setup({
      style = {
        placement = 'inline',
        prefix = '',
      },
      style = {
        placement = 'inline',
        prefix = '',
        render = "focused", -- or "all" for showing lenses in all functions
      },
    })
  end,
}
```

</details>

### Lens Attribute Customization

#### Design Philosophy

<details>

**lensline** takes an opinionated approach to defaults while prioritizing extensibility over configuration bloat:

- **Opinionated defaults**: Built-in providers to commonly-used functionality inspired by popular IDEs (VSCode, JetBrains) - reference counts & git blame info
- **Extension over configuration**: Provider expose a minimal set of configs. For customization, lensline encourages writing custom providers

This design keeps the plugin lightweight while enabling unlimited customization. The provider based approach scales better than trying to support everything through configuration.

</details>

#### Built-in Providers

<details>
<summary><strong>usages Provider</strong> - LSP symbol usage</summary>

**Provider Name**: `usages`

**Events**: `LspAttach`, `BufWritePost`

**What it shows**: Information about symbol usage via LSP - references, definitions, and implementations

**Features**:
- **Capability detection** - Only queries LSP for supported capabilities
- **Flexible aggregation** - Choose which usage types to include (`refs`, `defs`, `impls`)
- **Two display modes** - Aggregate count (usages) or breakdown by type

**Configuration**:
- `enabled`: Enable/disable the provider (default: `true`)
- `include`: Array of usage types to aggregate (default: `{ "refs" }`)
  - `"refs"`: References (excludes declarations to avoid double-counting)
  - `"defs"`: Definitions
  - `"impls"`: Implementations
- `breakdown`: Display mode (default: `false`)
  - `false`: Show single aggregate count ("8 usages")
  - `true`: Show breakdown by type ("5 refs, 2 defs, 1 impls")
- `show_zero`: Show zero counts when LSP supports the capability (default: `true`)
- `labels`: Custom labels for each usage type and aggregate
- `icon_for_single`: Icon when only one attribute or aggregate display (default: "󰌹 ")
- `inner_separator`: Separator between breakdown items (default: ", ")

**Examples**:

Default refs-only configuration (matches old references provider):
```lua
{
  name = "usages",
  enabled = true,
  include = { "refs" },        -- Only show references
  breakdown = false,           -- Aggregate display
  show_zero = true,
}
```

Full usage tracking with breakdown:
```lua
{
  name = "usages",
  enabled = true,
  include = { "refs", "defs", "impls" },  -- Track all usage types
  breakdown = true,                       -- Show "5 refs, 2 defs, 1 impls"
  show_zero = true,
}
```

<img width="370" height="127" alt="Image" src="https://github.com/user-attachments/assets/1573f29d-0bed-4a13-947b-15d8b530904c" />

</details>

<details>
<summary><strong>references Provider</strong> - LSP reference counting (DEPRECATED)</summary>

> **⚠️ DEPRECATED**: The `references` provider is deprecated in favor of the more flexible `usages` provider. Use `usages` with `include = { "refs" }` for equivalent functionality.

**Provider Name**: `references`

**Events**: `LspAttach`, `BufWritePost`

**What it shows**: Number of references to functions/methods using LSP `textDocument/references`

**Configuration**:
- `enabled`: Enable/disable the provider (default: `false` - disabled by default, use `usages` instead)

> **Note**: LSP noise suppression is now controlled globally via the `silence_lsp` configuration option, not per-provider.

**Migration**: Replace with:
```lua
{
  name = "usages",
  enabled = true,
  include = { "refs" },
  breakdown = false,
  show_zero = true,
}
```

</details>

<details>
<summary><strong>last_author Provider</strong> - Git blame information</summary>

**Provider Name**: `last_author`

**Events**: `BufRead`, `BufWritePost`

**What it shows**: Most recent git author and relative time for each function

<img width="406" height="233" alt="Image" src="https://github.com/user-attachments/assets/673b87ec-b39c-4ce9-bff8-53e1a1ac4ef0" />

</details>

<details>
<summary><strong>diagnostics Provider</strong> - Diagnostic aggregation</summary>

**Provider Name**: `diagnostics`

**Events**: `DiagnosticChanged`, `BufReadPost`

**What it shows**: Shows the count of the highest severity diagnostic type within each function (that passes the severity filter). 

**Display Format**:
- `2E`, `3W`, `1I`, `4H` (E=Error, W=Warning, I=Info, H=Hint) or uses nerd font icons if enabled

**Configuration**:
- `enabled`: Enable/disable the provider (default: `false` - disabled by default)
- `min_level`: Minimum diagnostic severity to display (default: `"WARN"`)
  - Valid values: `"ERROR"`, `"WARN"`, `"INFO"`, `"HINT"`
  - Can also use numeric values: `vim.diagnostic.severity.ERROR`, etc.

**Example Configuration**:
```lua
{
  name = "diagnostics",
  enabled = true,      -- Must be explicitly enabled
  min_level = "ERROR", -- Only show errors
}
```

<img width="1105" height="143" alt="Image" src="https://github.com/user-attachments/assets/fedff22b-82ec-4177-938f-188a6afae542" />

</details>

<details>
<summary><strong>complexity Provider</strong> - Code complexity analysis</summary>

> **Note**: The complexity heuristic is evolving and needs more real-world usage to fine-tune the scoring. Feedback is welcomed to improve accuracy across different languages and patterns.

**Provider Name**: `complexity`

**Events**: `BufWritePost`, `TextChanged`

**What it shows**: Function complexity indicators using language-aware research-based scoring that analyzes control flow patterns (branches, loops, conditionals) rather than superficial metrics like line count.
Note that complexity is calculated using a heuristic that may evolve over time, but will always be documented in the changelog.
You are welcome to open issues or PRs to improve the heuristic for specific languages / patterns.

![Complexity Provider Demo](https://github.com/user-attachments/assets/f6f5af14-237c-4cd2-b1ba-700ae0014ab3)

**Display Format**: `Cx: S/M/L/XL` where:
- **S** (Small) - Simple sequential functions
- **M** (Medium) - Functions with basic branching
- **L** (Large) - Functions with significant complexity
- **XL** (Extra Large) - Highly complex functions

**Language Support**: Automatically detects and uses language-specific patterns for:
- Lua, JavaScript, TypeScript, Python, Go
- Falls back to generic patterns for other languages

**Heuristic**:
- Counts decision points: `if / elseif / switch / case / try / catch / finally`, loops, and exception-ish constructs (e.g. `pcall`, `try`, `catch`)
- Logical operators inside condition headers (`and`, `or`, `not`, `&&`, `||`, ternary markers) add conditional weight
- Loops are weighted higher than simple branches; exception constructs add to branch weight
- Indentation depth (max leading spaces) adds a small nesting penalty; line count adds a tiny capped contribution (capped at 30 LOC, low weight)
- Plain `else` is not counted (no added decision)
- Language-specific weight multiplier adjusts overall score slightly (e.g. Python < JS due to typical verbosity differences)
- Thresholds (raw score → label): `<=5 => S`, `<=12 => M`, `<=20 => L`, else `XL`
- Goal: highlight genuinely complex control flow, not just long or indented code; small helpers with a single branch can still remain S if overall score stays low

**Stability**:
- Heuristic may evolve; future changes will be versioned in the changelog if thresholds or weights shift.

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



#### Custom Providers

lensline supports custom providers for unlimited extensibility:

- **Create inline providers** - Define simple providers directly in your config 
- **Use composable utilities** - Leverage built-in utilities for LSP, function analysis, and styling

##### Examples

Here are a few examples for inspiration. For comprehensive provider  guidance, see [`providers.md`](providers.md).

<details>
<summary><strong>Zero Reference Warning</strong> - Modify existing references behavior</summary>

![lensline demo](https://github.com/user-attachments/assets/c5910040-370b-49c9-95a8-97d15fd9109c)

Shows a warning when functions have zero references, helping identify unused code.

```lua
require("lensline").setup({
  providers = {
    -- Replace the default references with this enhanced version
    {
      name = "references_with_warning",
      enabled = true,
      event = { "LspAttach", "BufWritePost" },
      handler = function(bufnr, func_info, provider_config, callback)
        local utils = require("lensline.utils")
        
        utils.get_lsp_references(bufnr, func_info, function(references)
          if references then
            local count = #references
            local icon, text
            
            if count == 0 then
              icon = utils.if_nerdfont_else("⚠️ ", "WARN ")
              text = icon .. "No references"
            else
              icon = utils.if_nerdfont_else("󰌹 ", "")
              local suffix = utils.if_nerdfont_else("", " refs")
              text = icon .. count .. suffix
            end
            
            callback({ line = func_info.line, text = text })
          else
            callback(nil)
          end
        end)
      end
    }
  }
})
```

</details>

<details>
<summary><strong>Function Length</strong> - Show function line count</summary>

Displays the number of lines in each function, helping identify long functions that might need refactoring.

![Function Length Provider Demo](https://github.com/user-attachments/assets/1d574aee-e1dc-4b5b-ab1c-252b1fcefd28)

```lua
require("lensline").setup({
  providers = {
    { name = "usages", enabled = true, include = { "refs" }, breakdown = false },
    
    {
      name = "function_length",
      enabled = true,
      event = { "BufWritePost", "TextChanged" },
      handler = function(bufnr, func_info, provider_config, callback)
        local utils = require("lensline.utils")
        local function_lines = utils.get_function_lines(bufnr, func_info)
        local func_line_count = math.max(0, #function_lines - 1) -- Subtract 1 for signature
        local total_lines = vim.api.nvim_buf_line_count(bufnr)
        
        -- Show line count for all functions
        callback({
          line = func_info.line,
          text = string.format("(%d/%d lines)", func_line_count, total_lines)
        })
      end
    }
  }
})
```

</details>

For detailed guidelines and more examples, see [providers.md](providers.md).

## Multiple Profiles

lensline supports multiple profiles for different development contexts. Switch between complete sets of providers and styling depending on your workflow.

### Basic Setup

<details open>
<summary><strong>basic setup</strong> - two-profile starter config</summary>

```lua
require("lensline").setup({
  -- Profile definitions, first is default
  profiles = {
    {
      name = "basic",
      providers = {
        { name = "usages", enabled = true, include = { "refs" }, breakdown = false },
        { name = "last_author", enabled = true }
      },
      style = { render = "all", placement = "above" }
    },
    {
      name = "informative",
      providers = {
        { name = "usages", enabled = true, include = { "refs", "defs", "impls" }, breakdown = true },
        { name = "diagnostics", enabled = true, min_level = "HINT" },
        { name = "complexity", enabled = true }
      },
      style = { render = "focused", placement = "inline" }
    }
  },
})
```

</details>

### Switching Profiles

**Commands:**
```vim
:LenslineProfile basic            " Switch to 'basic' profile
:LenslineProfile                  " Cycle to next profile
```

**Programmatic API:**
```lua
local lensline = require("lensline")

-- Switch profiles
lensline.switch_profile("base")

-- Query profile information
local current = lensline.get_active_profile()     -- "base"
local available = lensline.list_profiles()        -- {"base", "informative"}
local has_profile = lensline.has_profile("informative")  -- true/false
```

## 💻 Commands

lensline provides separate control over engine functionality and visual display through distinct commands:

### Engine Control

Control the entire lensline engine (providers, autocommands, resource allocation).

```vim
:LenslineEnable        " Start all providers and functionality
:LenslineDisable       " Stop all providers and free resources
:LenslineToggleEngine  " Toggle enable/disable engine
:LenslineToggle        " DEPRECATED: Will be removed in v2, currently toggles view
```

<details>
<summary><strong>Programmatic API - Engine Control</strong></summary>

```lua
local lensline = require("lensline")

-- Engine control (full functionality)
lensline.enable()
lensline.disable()
lensline.toggle_engine()
if lensline.is_enabled() then
  print("Engine is running")
end

-- Legacy (deprecated)
lensline.toggle()  -- Shows warning, calls toggle_view()
```

</details>

### Visual Display Control

Control visual rendering while keeping providers running in background.

```vim
:LenslineShow        " Show lens visual display
:LenslineHide        " Hide lens visual display (providers still active)
:LenslineToggleView  " Toggle show/hide visual display (most common)
```

<details>
<summary><strong>Programmatic API - Visual Display</strong></summary>

```lua
local lensline = require("lensline")

-- View control (visibility only)
lensline.show()
lensline.hide()
lensline.toggle_view()
if lensline.is_visible() then
  print("Lenses are visible")
end
```

</details>

## 🤝 Contribute

PRs, issues, and suggestions welcome.

For development setup, debugging, and technical details, see [CONTRIBUTE.md](CONTRIBUTE.md).

## 🙏 Thanks to

- [lazy.nvim](https://github.com/folke/lazy.nvim) & [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for inspiration on a (hopefully) good README.md

- The inventor of the code-lens feature

- [flaticon](https://www.flaticon.com/) for the ape icon
