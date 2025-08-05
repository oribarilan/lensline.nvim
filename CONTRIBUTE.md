# Contributing to lensline.nvim

We welcome contributions as issues, pull requests, or suggestions. This document outlines how to contribute effectively.

## Development Setup

Set up your Neovim config to use the local version:

Example for with lazy:

```lua
return {
  dir = '~/path/to/lensline.nvim', -- Path to your local clone
  dev = true, -- Enables development mode
  event = 'BufReadPre',
  config = function()
    require("lensline").setup({
      debug_mode = true,  -- enable debug logging and LenslineDebug command
      providers = {
        { name = "ref_count", enabled = true },
        { name = "last_author", enabled = true },
      }
    })
  end,
}
```

## Architecture Overview

### File Structure

```
lensline.nvim/
├── lua/
│   └── lensline/
│       ├── init.lua           -- Plugin entry point and public API
│       ├── config.lua         -- Configuration management and defaults
│       ├── setup.lua          -- Setup logic, autocommands, and orchestration
│       ├── renderer.lua       -- Virtual text rendering and extmark management
│       ├── executor.lua       -- Provider execution and coordination
│       ├── lens_explorer.lua  -- Function detection using LSP document symbols
│       ├── debug.lua          -- Debug logging system
│       ├── utils.lua          -- Shared helper functions (LSP, function detection)
│       ├── blame_cache.lua    -- Git blame caching system
│       ├── limits.lua         -- File processing limits and exclusions
│       └── providers/
│           ├── init.lua       -- Provider coordination and registry
│           ├── ref_count.lua  -- LSP reference counting provider
│           ├── last_author.lua -- Git blame provider
│           ├── complexity.lua -- Code complexity analysis provider (beta)
│           └── diag_summary.lua -- LSP diagnostics aggregation provider (beta)
├── README.md                  -- User documentation
├── CONTRIBUTE.md              -- This file
├── CHANGELOG.md               -- Release notes and version history
├── providers.md               -- Provider development guide
├── LICENSE                    -- MIT license
└── .gitignore                 -- Git ignore patterns
```

## Performance Architecture

### Async Function Discovery
Function detection uses asynchronous LSP calls (`vim.lsp.buf_request`) to prevent UI blocking during file operations. The system employs a stale-first rendering strategy: cached function data renders immediately for responsive user feedback, while fresh LSP data updates in the background. The nature of this design gurantees a self-healing mechanism.

### Efficient Rendering
The renderer uses batched extmark operations and incremental updates to minimize API overhead. Only changed content triggers re-rendering, and all extmark modifications are grouped into single operations for optimal performance.

## Debug System

When `debug_mode = true` is set in your config:

- **`:LenslineDebug` command**: Automatically created to open the current debug log file in a new tab
- **Log rotation**: Debug logs are automatically rotated when they exceed 500KB, keeping up to 3 files (main + 2 rotated) per session
- **Session isolation**: Each Neovim session creates separate debug files, with old sessions cleaned up on startup
- **Performance**: When `debug_mode = false` (default), no debug files are created and logging has zero performance impact

Debug logs contain detailed information about provider execution, LSP interactions, and system events - useful for troubleshooting issues or understanding plugin behavior.

## Changelog Maintenance

We maintain a [`CHANGELOG.md`](CHANGELOG.md) file to track all user-facing changes. This helps users understand what's new, changed, or fixed in each release.

### Adding Changes During Development

When making user-facing changes, add them to the `## [Unreleased]` section at the top of [`CHANGELOG.md`](CHANGELOG.md):

- **Added** — for new features
- **Changed** — for updates or improvements
- **Fixed** — for bug fixes
- **Removed** — for anything deprecated or dropped

Use bullet points and keep entries short and clear. Only include **user-facing** changes (not internal refactoring, formatting, etc.)

Example:
```markdown
## [Unreleased]
### Added
- Support for multiple git providers
- New `complexity` provider for function complexity analysis

### Fixed
- Crash on startup if config was missing
- Memory leak in blame cache system
```

## Release Process

1. **Update Changelog**: Rename the `[Unreleased]` section to the version you're releasing
   Example: `## [Unreleased]` → `## [v0.1.2] - 2025-08-03`
2. **Create fresh Unreleased section**: Add a new empty `[Unreleased]` section at the top for future changes
3. **Update Version**: Increment the version in `README.md` in the `install` section
4. **Merge**: Merge changes into the main branch
5. **Merge to release branch**: Merge the main branch into the `release/0.1.x` branch
6. **Tag Release**: Create a new tag for the release (e.g., `v0.1.2`) on the `release/0.1.x` branch