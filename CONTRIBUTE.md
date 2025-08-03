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
│       ├── init.lua         -- Plugin entry point and public API
│       ├── config.lua       -- Configuration management and defaults
│       ├── setup.lua        -- Setup logic, autocommands, and orchestration
│       ├── renderer.lua     -- Virtual text rendering and extmark management
│       ├── debug.lua        -- Debug logging system
│       ├── utils.lua        -- Shared helper functions (LSP, function detection)
│       └── providers/
│           ├── init.lua     -- Provider coordination and registry
│           ├── ref_count.lua -- LSP reference counting provider
│           └── last_author.lua -- Git blame provider
├── README.md                -- User documentation
├── CONTRIBUTE.md            -- This file
├── LICENSE                  -- MIT license
└── TODO.md                  -- Development roadmap
```

## Debug System

When `debug_mode = true` is set in your config:

- **`:LenslineDebug` command**: Automatically created to open the current debug log file in a new tab
- **Log rotation**: Debug logs are automatically rotated when they exceed 500KB, keeping up to 3 files (main + 2 rotated) per session
- **Session isolation**: Each Neovim session creates separate debug files, with old sessions cleaned up on startup
- **Performance**: When `debug_mode = false` (default), no debug files are created and logging has zero performance impact

Debug logs contain detailed information about provider execution, LSP interactions, and system events - useful for troubleshooting issues or understanding plugin behavior.

## Release Process

1. **Update Version**: Increment the version in `README.md` in the `install` section.
2. **Merge**: Merge changes into the main branch.
3. **Merge to release branch**: Merge the main branch into the `release/0.1.x` branch.
4. **Tag Release**: Create a new tag for the release (e.g., `0.1.0`) on the `release/0.1.x` branch.