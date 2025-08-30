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

- `Dockerfile` - Clean Ubuntu + Neovim + Lua LSP
- `init.lua` - Lazy package manager setup with lensline auto-installation
- `sample.lua` - Lua file with various function patterns
- `Makefile` - Simple build/run commands

## Usage

- Neovim comes preloaded with latest lensline.nvim, Mason & Lua LSP server
- Telescope included for navigation (`<Space>sf` for files, `<Space>sg` for grep)
- Running `make run` builds and runs the container, automatically opening Neovim
- Debug mode enabled by default (`debug_mode = true`) - may impact performance

## Customization

- Edit `init.lua` to add required LSPs, customize lensline config, or add plugins
- Use `:LenslineDebug` for debug logs
- Use `:Mason` to check LSP installation status
