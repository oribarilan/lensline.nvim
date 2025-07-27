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
