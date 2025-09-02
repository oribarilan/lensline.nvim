# Contributing to lensline.nvim

This is a guide for **project contributors** who want to contribute code, fixes, or improvements to the lensline.nvim codebase itself. For using lensline or creating custom providers, see [`README.md`](README.md) and [`providers.md`](providers.md).

We welcome contributions as issues, pull requests, or suggestions. This document outlines how to contribute effectively to the project development.

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
        { name = "references", enabled = true },
        { name = "last_author", enabled = true },
      }
    })
  end,
}
```

## Setup

Prerequisites:
- Neovim (>= 0.9 recommended)
- LuaRocks available on PATH

Install local (isolated) dependency (luassert only):
```bash
# from repo root
rm -rf .rocks
luarocks --lua-version=5.1 --tree ./.rocks install luassert
```

Run tests:
```bash
make test
```

Or run manually (equivalent headless invocation):
```bash
eval "$(luarocks --lua-version=5.1 --tree ./.rocks path)" \
  && nvim --headless -u tests/minimal_init.lua \
     -c "lua require('lensline.test_runner').run()" +qall
```

## Testing

See [testing_guidelines.md](testing_guidelines.md:1) for detailed practices (naming rules, stubbing, LSP strategy).

Notes:
- Local isolated deps live in ./.rocks (git-ignored); no global installs needed.
- Minimal harness: custom in-repo runner (no busted, plenary, docker, or coverage by default).
- Test file naming: must match `test_.*_spec.lua` (example: `tests/unit/test_utils_spec.lua`).
- Runtime bootstrap: [tests/minimal_init.lua](tests/minimal_init.lua:1) and runner: [lua/lensline/test_runner.lua](lua/lensline/test_runner.lua:1).

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
│       ├── utils.lua          -- Organized utility functions (core, style, buffer, LSP)
│       ├── blame_cache.lua    -- Git blame caching system
│       ├── limits.lua         -- File processing limits and exclusions
│       └── providers/
│           ├── init.lua       -- Provider coordination and registry
│           ├── references.lua -- LSP reference counting provider
│           ├── last_author.lua -- Git blame provider
│           ├── complexity.lua -- Code complexity analysis provider (beta)
│           └── diagnostics.lua -- LSP diagnostics aggregation provider (beta)
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
- **Buffered logging**: Uses in-memory buffer (100 entries) that flushes to disk in batches for ~99% better performance
- **Performance**: When `debug_mode = false` (default), no debug files are created and logging has zero performance impact
- **Reliability**: VimLeavePre autocommand ensures logs persist on normal shutdown
- **Manual flush**: If needed, you can use `require("lensline.debug").flush()` to force immediate write 

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
5. **Merge to release branch**: Merge the main branch into the appropriate release branch:
   - For v1.x releases: merge into `release/1.x` branch
6. **Tag Release**: Create a new tag for the release (e.g., `v1.0.0`, `v1.1.0`) on the appropriate release branch