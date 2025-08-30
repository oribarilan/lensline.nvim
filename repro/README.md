# Bug Reproduction Template

Simple container environment for reproducing lensline.nvim bugs in a clean & isolated environment, using any nvim version.

## Quick Start

```bash
make run
```

**Test with specific Neovim version:**
```bash
make run NVIM_VERSION=v0.9.4   # Older version
make run NVIM_VERSION=latest   # Latest version
```

## Files

- `Dockerfile` - Clean Ubuntu + Neovim + Python LSP
- `init.lua` - Lazy package manager setup with lensline auto-installation
- `sample.py` - Python file with various function patterns
- `Makefile` - Simple build/run commands

## Usage

- nvim will come preloaded with latest lensline.nvim, mason & lua LSP server
- nvim will also come preloaded with telescope (space-s-f for file search, space-s-g for grep)
- running `make run` will build and run the docker container, and open nvim with the init.lua config
- note the by default the lensline config has `debug_mode = true` enabled, be aware that it has some impact on performance.

## Instructions 

- Edit `init.lua` to add the required LSPs, customize lensline config or add other plugins
- **Use `:LenslineDebug`** to get debug logs
