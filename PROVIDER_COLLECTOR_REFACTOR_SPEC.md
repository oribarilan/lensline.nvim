# Provider-Collector Architecture Refactor Specification

## Overview

This document specifies the refactoring of lensline.nvim from atomic providers to a modular provider-collector architecture. The goal is to eliminate code duplication, improve extensibility, and provide a unified API for both built-in and user-defined functionality.

## Current Architecture Problems

1. **Code Duplication**: LSP and diagnostics providers both duplicate function discovery logic
2. **Limited Extensibility**: Users cannot easily extend providers with custom functionality
3. **Atomic Design**: Each provider is a monolithic unit with limited internal configurability
4. **Performance**: Multiple providers may duplicate expensive operations (LSP requests, function discovery)

## New Architecture: Infrastructure + Provider-Collector System

### Core Concepts

- **Infrastructure Layer**: Core plugin functionality including function discovery, lens positioning, and rendering
- **Provider**: Manages domain-specific context and resources (LSP clients, Git repo, diagnostics)
- **Collector**: Pure function that takes provider context and returns formatted lens text
- **Function Discovery**: Shared infrastructure service that finds functions/symbols to decorate (not provider-specific)
- **Built-in Collectors**: Default collectors shipped with each provider, easily importable and customizable
- **User Collectors**: Custom functions following the same interface as built-in collectors

### Design Principles

1. **Separation of Concerns**: Function discovery is infrastructure, not provider responsibility
2. **Functional Approach**: Collectors are pure functions with consistent signatures per provider
3. **Co-location**: Each provider's collectors are stored alongside the provider logic
4. **No Distinction**: Built-in and user collectors use identical APIs
5. **Easy Customization**: Users can copy built-in collectors and modify only what they need
6. **Provider-Specific Signatures**: Each provider can define its own collector function signature
7. **Shared Infrastructure**: Common functionality (function discovery, caching, rendering) is centralized

## File Structure

```
lua/lensline/
├── infrastructure/
│   ├── function_discovery.lua     # Shared function discovery service
│   ├── cache.lua                   # Shared caching infrastructure
│   └── lens_manager.lua            # Lens positioning and rendering coordination
├── providers/
│   ├── lsp/
│   │   ├── init.lua                # LSP provider logic (context only)
│   │   └── collectors/
│   │       ├── references.lua      # Built-in LSP collector
│   │       ├── definitions.lua     # Built-in LSP collector
│   │       └── implementations.lua # Built-in LSP collector
│   ├── diagnostics/
│   │   ├── init.lua                # Diagnostics provider logic
│   │   └── collectors/
│   │       ├── function_level.lua  # Built-in diagnostics collector
│   │       └── by_severity.lua     # Built-in diagnostics collector
│   ├── git/
│   │   ├── init.lua                # Git provider logic
│   │   └── collectors/
│   │       ├── blame.lua           # Built-in git collector
│   │       └── stats.lua           # Built-in git collector
│   └── init.lua                    # Provider manager (existing file to be updated)
├── core.lua                        # Main orchestration (existing file to be updated)
└── renderer.lua                    # Rendering logic (existing file)
```

## Implementation Specification

### 1. Infrastructure Layer

**Function Discovery Service (`lua/lensline/infrastructure/function_discovery.lua`):**
```lua
local M = {}

-- Central function discovery - shared by all providers
function M.discover_functions(bufnr, callback)
  -- Use LSP document symbols to find all functions/methods
  -- This is infrastructure, not provider-specific
  local clients = vim.lsp.get_active_clients({ bufnr = bufnr })
  
  vim.lsp.buf_request_all(bufnr, "textDocument/documentSymbol", {
    textDocument = vim.lsp.util.make_text_document_params(bufnr)
  }, function(results)
    local functions = {}
    
    for client_id, result in pairs(results) do
      if result.result then
        local symbols = extract_function_symbols(result.result)
        for _, symbol in ipairs(symbols) do
          table.insert(functions, {
            name = symbol.name,
            line = symbol.line,
            character = symbol.character,
            range = symbol.range  -- For range-based collectors
          })
        end
      end
    end
    
    callback(functions)
  end)
end

return M
```

**Lens Manager (`lua/lensline/infrastructure/lens_manager.lua`):**
```lua
local M = {}

-- Orchestrates function discovery + provider data collection + rendering
function M.refresh_buffer_lenses(bufnr)
  local function_discovery = require("lensline.infrastructure.function_discovery")
  local providers = require("lensline.providers")
  local renderer = require("lensline.renderer")
  
  -- 1. Discover functions once (infrastructure)
  function_discovery.discover_functions(bufnr, function(functions)
    
    -- 2. Collect data from all providers
    providers.collect_lens_data(bufnr, functions, function(lens_data)
      
      -- 3. Render lenses
      renderer.render_buffer_lenses(bufnr, lens_data)
    end)
  end)
end

return M
```

### 2. Collector Interface

Each collector is a pure function with provider-specific signature:

**LSP Collectors:**
```lua
-- Signature: function(lsp_context, function_info) -> format_string, value
function(lsp_context, function_info)
  -- lsp_context: { clients, cache_get, cache_set, uri, ... }
  -- function_info: { name, line, character, range }
  -- Returns: format_string, value OR nil, nil
  return "refs: %d", ref_count
end
```

**Diagnostics Collectors:**
```lua
-- Signature: function(diagnostics_context, function_info) -> format_string, value
function(diagnostics_context, function_info)
  -- diagnostics_context: { diagnostics, cache_get, cache_set, ... }
  -- function_info: { name, line, character, range }
  return "diag: %d", diag_count
end
```

**Git Collectors:**
```lua
-- Signature: function(git_context, function_info) -> format_string, value
function(git_context, function_info)
  -- git_context: { repo, branch, cache_get, cache_set, ... }
  -- function_info: { name, line, character, range }
  return "@%s", author_name
end
```

### 3. Provider Implementation

Each provider (e.g., `lua/lensline/providers/lsp/init.lua`) focuses only on domain-specific context:

```lua
local M = {}

-- Auto-discover built-in collectors
local function load_built_in_collectors()
  local collectors = {}
  local base_path = "lensline.providers.lsp.collectors"
  
  -- Auto-discover all .lua files in collectors/ directory
  local collector_files = {
    "references",
    "definitions",
    "implementations"
  }
  
  for _, name in ipairs(collector_files) do
    collectors[name] = require(base_path .. "." .. name)
  end
  
  return collectors
end

-- Export collectors for user import
M.collectors = load_built_in_collectors()

-- Default collectors used when user doesn't override
M.default_collectors = {
  M.collectors.references,
  M.collectors.definitions
}

-- Provider context creation (domain-specific only)
function M.create_context(bufnr)
  return {
    clients = vim.lsp.get_active_clients({ bufnr = bufnr }),
    uri = vim.uri_from_bufnr(bufnr),
    workspace_root = vim.lsp.buf.list_workspace_folders()[1],
    cache_get = function(key) return get_from_cache(key) end,
    cache_set = function(key, value, ttl) set_cache(key, value, ttl) end,
    -- LSP-specific context only, no function discovery
  }
end

-- Data collection for discovered functions (functions provided by infrastructure)
function M.collect_data_for_functions(functions, callback)
  local config = get_provider_config("lsp")
  local collectors = config.collectors or M.default_collectors
  local context = M.create_context(bufnr)
  
  local lens_data = {}
  local pending = 0
  
  for _, func in ipairs(functions) do
    local text_parts = {}
    
    -- Run all collectors for this function
    for _, collector_fn in ipairs(collectors) do
      pending = pending + 1
      
      -- Collectors may be async, so use callback pattern
      local function handle_collector_result(format, value)
        if format and value then
          table.insert(text_parts, string.format(format, value))
        end
        
        pending = pending - 1
        if pending == 0 then
          -- All collectors finished for all functions
          if #text_parts > 0 then
            table.insert(lens_data, {
              line = func.line,
              character = func.character,
              text_parts = text_parts
            })
          end
          callback(lens_data)
        end
      end
      
      -- Call collector with function info from infrastructure
      local format, value = collector_fn(context, func)
      handle_collector_result(format, value)
    end
  end
  
  if pending == 0 then
    callback(lens_data)
  end
end

return M
```

### 4. Updated Provider Manager

The provider manager (`lua/lensline/providers/init.lua`) coordinates with infrastructure:

```lua
local M = {}

M.providers = {
  lsp = require("lensline.providers.lsp"),
  diagnostics = require("lensline.providers.diagnostics"),
  git = require("lensline.providers.git")
}

-- Collect data from all providers using infrastructure-discovered functions
function M.collect_lens_data(bufnr, functions, callback)
  local opts = config.get()
  local all_lens_data = {}
  local enabled_providers = get_enabled_providers()
  local pending_providers = #enabled_providers
  
  if pending_providers == 0 then
    callback({})
    return
  end
  
  -- Each provider gets the same function list from infrastructure
  for _, provider_name in ipairs(enabled_providers) do
    local provider = M.providers[provider_name]
    
    provider.collect_data_for_functions(functions, function(provider_lens_data)
      -- Merge lens data from this provider
      for _, lens in ipairs(provider_lens_data) do
        local key = lens.line .. ":" .. (lens.character or 0)
        if not all_lens_data[key] then
          all_lens_data[key] = {
            line = lens.line,
            character = lens.character,
            text_parts = {}
          }
        end
        
        -- Append text_parts from this provider
        for _, text_part in ipairs(lens.text_parts or {}) do
          table.insert(all_lens_data[key].text_parts, text_part)
        end
      end
      
      pending_providers = pending_providers - 1
      if pending_providers == 0 then
        -- Convert map back to array and sort
        local merged_lens_data = {}
        for _, lens in pairs(all_lens_data) do
          table.insert(merged_lens_data, lens)
        end
        table.sort(merged_lens_data, function(a, b) return a.line < b.line end)
        callback(merged_lens_data)
      end
    end)
  end
end

return M
```

### 5. Built-in Collector Examples

**LSP References Collector (`lua/lensline/providers/lsp/collectors/references.lua`):**
```lua
return function(lsp_context, function_info)
  local cache_key = "refs:" .. function_info.line .. ":" .. function_info.character
  local cached = lsp_context.cache_get(cache_key)
  if cached then
    return "refs: %d", cached
  end
  
  local ref_count = 0
  local position = { line = function_info.line, character = function_info.character }
  
  for _, client in ipairs(lsp_context.clients) do
    local result = client.request_sync("textDocument/references", {
      textDocument = { uri = lsp_context.uri },
      position = position,
      context = { includeDeclaration = false }
    }, 5000)
    
    if result and result.result then
      ref_count = ref_count + #result.result
    end
  end
  
  lsp_context.cache_set(cache_key, ref_count, 30000)
  return "refs: %d", ref_count
end
```

**Diagnostics Function Level Collector (`lua/lensline/providers/diagnostics/collectors/function_level.lua`):**
```lua
return function(diagnostics_context, function_info)
  local diagnostics = vim.diagnostic.get(diagnostics_context.bufnr)
  local counts = {
    [vim.diagnostic.severity.ERROR] = 0,
    [vim.diagnostic.severity.WARN] = 0,
  }
  
  for _, diag in ipairs(diagnostics) do
    if is_in_function_range(diag, function_info.range) then
      counts[diag.severity] = (counts[diag.severity] or 0) + 1
    end
  end
  
  local total = counts[vim.diagnostic.severity.ERROR] + counts[vim.diagnostic.severity.WARN]
  if total > 0 then
    return "diag: %d", total
  end
  
  return nil, nil
end
```

**Git Blame Collector (`lua/lensline/providers/git/collectors/blame.lua`):**
```lua
return function(git_context, function_info)
  local cache_key = "blame:" .. function_info.line
  local cached = git_context.cache_get(cache_key)
  if cached then
    return "@%s", cached
  end
  
  local author = get_git_blame_for_line(git_context.repo, function_info.line)
  if author then
    git_context.cache_set(cache_key, author, 60000)
    return "@%s", author
  end
  
  return nil, nil
end
```

### 6. Configuration API

**User Configuration:**
```lua
-- Import built-in collectors for customization
local lsp = require("lensline.providers.lsp")
local diagnostics = require("lensline.providers.diagnostics")
local git = require("lensline.providers.git")

require("lensline").setup({
  providers = {
    lsp = {
      enabled = true,
      performance = { cache_ttl = 30000 },
      
      collectors = {
        -- Use built-in collectors
        lsp.collectors.references,
        lsp.collectors.definitions,
        
        -- Copy and customize built-in collector
        function(lsp_context, function_info)
          -- Copy references collector logic, modify format
          local cache_key = "refs:" .. function_info.line
          local cached = lsp_context.cache_get(cache_key)
          if cached then return "👁 %d", cached end
          
          local position = { line = function_info.line, character = function_info.character }
          local ref_count = get_references(lsp_context.clients, position)
          lsp_context.cache_set(cache_key, ref_count, 30000)
          return "👁 %d", ref_count  -- Custom icon
        end,
        
        -- Completely custom collector
        function(lsp_context, function_info)
          local test_status = get_test_coverage(function_info)
          return "test: %s", test_status
        end
      }
    },
    
    diagnostics = {
      enabled = true,
      collectors = {
        diagnostics.collectors.function_level,
        
        -- Custom diagnostics collector
        function(diagnostics_context, function_info)
          local error_count = count_errors_only(diagnostics_context.diagnostics, function_info.range)
          return "🔥 %d", error_count
        end
      }
    },
    
    git = {
      enabled = true,
      collectors = {
        git.collectors.blame
      }
    }
  }
})
```

### 7. Migration Strategy

**Phase 1: Create Infrastructure Layer**
1. Create `infrastructure/` directory with function discovery service
2. Create `infrastructure/lens_manager.lua` for orchestration
3. Extract function discovery logic from existing providers into shared service
4. Update core.lua to use lens_manager instead of direct provider calls

**Phase 2: Refactor Providers to Collector System**
1. Create new file structure with providers/ subdirectories and collectors/
2. Extract existing logic (references, diagnostics) into collector functions
3. Implement provider auto-discovery of collectors
4. Update provider manager to coordinate with infrastructure-discovered functions
5. Providers no longer do function discovery - only data collection

**Phase 3: Update Configuration and Cleanup**
1. Update config parsing to handle collectors arrays
2. Update documentation with new configuration format and infrastructure concepts
3. Remove old atomic provider implementations
4. Clean up unused code paths and update tests

## Benefits

1. **Separated Concerns**: Function discovery is infrastructure, not provider responsibility
2. **Eliminated Duplication**: Shared function discovery across all providers, shared LSP context across LSP collectors
3. **Perfect Modularity**: Built-in and user collectors use identical APIs
4. **Easy Customization**: Copy any built-in collector and modify just the format
5. **Performance**: Single function discovery + single provider context shared across all collectors
6. **Extensibility**: Users can add unlimited custom collectors per provider
7. **Clean Organization**: Collectors co-located with provider logic
8. **Infrastructure Reuse**: Function discovery, caching, and lens management are shared services

## Testing Requirements

1. **Unit Tests**: Each collector should be independently testable
2. **Integration Tests**: Provider context creation and collector execution
3. **Performance Tests**: Ensure no regression in lens rendering performance
4. **Configuration Tests**: Verify all configuration scenarios work correctly

## Implementation Notes

- No backward compatibility required (breaking change acceptable)
- Performance settings remain at provider level, not per collector
- Caching is managed by provider context, shared across collectors
- Each provider can define its own collector function signature
- Built-in collectors are automatically discovered from collectors/ directory
- Users import collectors via `require("lensline.providers.{provider}").collectors.{name}`

## Success Criteria

1. **Code Reduction**: 30%+ reduction in duplicated code
2. **Performance**: No regression in lens rendering performance
3. **Extensibility**: Users can easily add custom collectors
4. **Maintainability**: Built-in collectors are independently maintainable
5. **User Experience**: Simple configuration API with powerful customization options