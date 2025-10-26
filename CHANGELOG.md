# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- _No changes yet_

### Changed
- _No changes yet_

### Fixed
- Faster startup time and more efficient caching by replacing gitignored caching from eager & bulk to lazy and per-file. This solves issues with large repos where initial caching could take a long time.

### Breaking
- _No changes yet_

## [v2.0.0] - 2025-09-27

### Added
- **Profile support**: Support for multiple provider/style configurations (profiles) with hot-swapping
- New profile management commands and APIs
- **usages provider**: New flexible LSP symbol usages provider that replaces `references` as the default
  - Supports references, definitions, and implementations
  - Configurable aggregation mode (showing `usages` total or breakdown by type)
  - Default configuration shows `references` only as the previous `references` provider
- **exclude_append**: New configuration option to extend the default exclude list without repeating all patterns
- **silence_lsp**: New global configuration option to suppress LSP request noise

### Changed
- `references` provider is now deprecated (still available for backward compatibility), will be removed in v3.0.0
- **LSP configuration architecture**: Moved from per-provider `quiet_lsp` to global `silence_lsp` for cleaner configuration
- Improved provider configuration merging logic to properly inherit defaults in all scenarios

### Fixed
- Fixed configuration merge bug where profile style inheritance used empty object instead of defaults
- Fixed provider merging to properly use `merge_provider_configs` function for correct inheritance behavior
- Fixed missing test coverage for partial provider inheritance scenarios

### Breaking (in v2.0.0)
- **render**: `render` config moved from root level to `style.render` for better organization
- **profiles**: New `profiles` config option for defining multiple profiles; legacy single config format is no longer supported
- **quiet_lsp**: Removed per-provider `quiet_lsp` configuration, replaced with global `silence_lsp` setting

## [v1.1.2] - 2025-01-09
### Fixed
- Fixed lua_ls anonymous functions array-style names (e.g., `[1]`, `[2]`, `[3]`) bypassing function filtering and incorrectly showing lenses

## [v1.1.lua  2025-01-07
### Fixed
- Fixed inline lens rendering not displaying correctly due to incorrect column positioning in extmarks
- Fixed extra trailing space in the references attribute for nerdfont (default) mode
- Fixed inline lens virtual text not inheriting cursorline background highlight

### Improved
- Debug system now uses buffered logging for better performance when debug mode is enabled
- Added devcontainer (used with an experimental plugin)
- Added comprehensive regression tests for extmark property validation to prevent placement issues

## [v1.1.0] - 2025-01-02

### Added
- New commands: `:LenslineShow`, `:LenslineHide`, `:LenslineToggleView`, `:LenslineToggleEngine` with programmatic API equivalents
- Lens placement can now be configured with "above" (existing) and "inline" (new) modes for another style option (consider `prefix = ""` for inline)
- Added Focused lens rendering mode: the option to only render a lens on the function that contains the cursor in the active window
- Docker-based bug reproduction environment
- GitHub issue template for streamlined bug reporting

### Changed
- Commands extracted to dedicated `commands.lua` module for better code organization
- Test suite improved with comprehensive state cleanup, randomized execution order, and enhanced cross-environment reliability
- Updated README with new main screenshot and added minimal style showcase with inline placement example

### Deprecated
- `:LenslineToggle` command (will be removed in v2.0) - use `:LenslineToggleView` or `:LenslineToggleEngine` instead

## [v0.2.1] - 2025-08-27

### Added
- Language-specific complexity pattern detection for Lua, JavaScript, TypeScript, Python, and Go
- Comprehensive buffer and file validation for complexity provider
- Initial automated test suite covering core executor, renderer, limits, and provider logic
- PR CI gate (GitHub Actions) executing test suite and requiring passing status before merge

### Changed
- Renamed `ref_count` provider to `references` for clarity
- Graduated `diagnostics` provider from beta (renamed from `diag_summary`)
- Graduated `complexity` provider from beta with enhanced language-aware algorithm
- Improved complexity provider performance with single-pass parsing
- Enhanced complexity provider error handling and validation following common provider patterns

### Fixed
- Fixed missing configuration requirement in complexity provider
- Fixed inconsistent error handling in complexity provider
- Fixed missing configuration requirement in diagnostics provider
- Fixed critical range access bug in diagnostics provider (func_info.range doesn't exist)
- Fixed diagnostics provider coordinate system handling (0-based vs 1-based)

### Removed
- Removed old `diag_summary` provider (replaced by `diagnostics`)

## [v0.2.0] - 2025-08-07

### Added
- Inline provider support for defining custom providers directly in configuration
- Composable utility functions for common provider patterns
- Centralized debug logging for all providers

### Changed
- Streamlined provider API with unified async callback pattern
- Simplified provider development with reduced boilerplate code
- All built-in providers updated to use new streamlined API

### Fixed
- Improved provider execution flow and reliability

## [v0.1.4] - 2025-08-06

### Added
- Anonymous function filtering: Lenses now only appear on named functions, filtering out anonymous functions, lambdas, and callbacks across many common languages (Lua, JavaScript, TypeScript, Python, Go, Rust, C, C++, C#, Java, Ruby, PHP, Kotlin, Swift)

### Changed
- Function discovery now uses asynchronous LSP calls to eliminate UI hangs during file operations
- Rendering system optimized with batched extmark operations and incremental updates for better performance
- Stale-first rendering strategy provides immediate user feedback while fresh data loads in background

### Fixed

### Removed

## [v0.1.3] - 2025-01-04

### Added
- Initial changelog setup
- Centralized lens discovery system to reduce repetitive work across providers
- LRU cache for lens discovery to improve performance and reduce redundant computations

### Changed
- Debug files now capped at 1.5 MB with automatic rotation for better log management
- Unified debouncing system across all providers for consistent performance
- Lens rendering optimized to only re-render when content actually changes
- Function search made more reliable for both lens discovery and reference counting

### Fixed
- `last_author` provider performance significantly improved with per-file caching
- `last_author` provider now only triggers for modified files, reducing unnecessary git operations

### Removed

## [v0.1.2] - 2024-12-15

### Added
- Core lensline plugin with modular provider system
- **references** provider - displays LSP reference counts above functions
- **last_author** provider - shows git blame information for function authors
- **complexity** provider (beta) - analyzes and displays function complexity metrics
- **diagnostics** provider (beta) - summarizes LSP diagnostics for functions
- Customizable styling and layout options
- Automatic function detection using treesitter
- Modular design allowing easy addition of custom providers
- Debug logging system with automatic log rotation
- Limits on provider execution time to prevent performance issues
