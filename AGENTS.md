# Agent Guide for lensline.nvim

## Build/Test Commands
- Run all tests: `make test`
- Run single test: `nvim --headless -u tests/minimal_init.lua -c "lua require('lensline.test_runner').run('tests/unit/test_config_spec.lua')"`
- Docker tests: `make d-test` (tests on Neovim v0.8.3 and stable)
- Clean dependencies: `make clean-rocks`

## Code Style

### Lua Conventions
- **NO COMMENTS** - Code should be self-documenting. Only add comments when explicitly requested by maintainers
- Module pattern: `local M = {}` ... `return M`
- Local functions before module functions
- Use `local` for all non-exported functions

### Imports & Dependencies
- Group requires at top: `local config = require("lensline.config")`
- Never assume external libraries exist - check neighboring files first
- Built-in dependencies: Neovim API, vim.loop/vim.uv (no external deps except luassert for tests)

### Naming & Types
- Functions: `snake_case` (e.g., `get_function_lines`, `is_valid_buffer`)
- Variables: `snake_case` (e.g., `func_info`, `bufnr`, `provider_cfg`)
- Constants: `snake_case` or `SCREAMING_SNAKE_CASE` for true constants
- Module tables: `M` for module exports
- Private functions: prefix with `local function` (not in M table)

### Error Handling
- Use `pcall` for operations that may fail (LSP, file I/O, buffer ops)
- Callbacks receive `nil` on failure, result on success
- Validate buffer handles: `vim.api.nvim_buf_is_valid(bufnr)`
- Log errors via `debug.log_context()` when debug_mode enabled

## Testing (see testing_guidelines.md for full details)
- Test files: `tests/unit/test_*_spec.lua` pattern (both prefix and suffix required)
- Assertions: `local eq = assert.are.same` preferred for table comparisons
- Reset modules in `before_each`/`after_each` to prevent state leakage
- Clean up buffers created in tests
- Use `await()` helper instead of blind sleeps for async operations
- Table-driven tests for multiple similar cases
