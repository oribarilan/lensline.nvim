# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- **ref_count** provider - displays LSP reference counts above functions
- **last_author** provider - shows git blame information for function authors
- **complexity** provider (beta) - analyzes and displays function complexity metrics
- **diag_summary** provider (beta) - summarizes LSP diagnostics for functions
- Customizable styling and layout options
- Automatic function detection using treesitter
- Modular design allowing easy addition of custom providers
- Debug logging system with automatic log rotation
- Limits on provider execution time to prevent performance issues