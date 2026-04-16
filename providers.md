# Providers

This guide is for **users** who want to create custom providers for lensline.nvim. For project development and contributing to the codebase, see [`CONTRIBUTE.md`](CONTRIBUTE.md).

## Architecture

**lensline** uses a simple **Provider** architecture:

- **Providers** are self-contained modules that handle specific data sources (LSP, git, etc.)
- Each provider defines its own event triggers and data collection logic
- Providers operate independently, allowing for easy addition or removal
- All providers use a unified async callback pattern

## Provider API

A provider is a Lua module that returns a table with the following structure:

```lua
-- custom_provider.lua
return {
  name = "my_custom_provider",
  event = { "BufWritePost" },  -- events that trigger this provider
  handler = function(bufnr, func_info, provider_config, callback)
    -- bufnr: buffer number
    -- func_info: { line = number, name = string, character = number, end_line = number? }
    -- provider_config: this provider's configuration from setup()
    -- callback: function to call with result
    
    -- Your custom logic here
    local custom_data = get_my_custom_data(func_info)
    
    -- Always call callback with lens item or nil
    callback({
      line = func_info.line,
      text = "💩 " .. custom_data,
      highlight = "DiagnosticWarn", -- optional: override highlight for this result
    })
    -- or callback(nil) if no lens should be shown
  end
}
```

### Handler Function

- **Parameters**: `(bufnr, func_info, provider_config, callback)`
- **Return**: Nothing (always use callback)
- **Callback**: Called with lens item `{ line = number, text = string, highlight = string? }` or `nil`
- **provider_config**: Contains this provider's configuration options
- **Debug logging**: Automatic - no need to add debug logging in provider handlers

### func_info Structure

The `func_info` parameter contains:
- **`line`**: Function start line number (1-based)
- **`name`**: Function name
- **`character`**: Character position in line
- **`end_line`**: Function end line number (optional - may be `nil` if unknown)

**Note**: `end_line` may be `nil` in several scenarios:
- LSP server doesn't provide complete range information
- File processing was truncated due to performance limits (`max_lines` config)
- Function definition spans beyond the processed range

Always check if it exists before using it. The [`utils.get_function_lines()`](lua/lensline/utils.lua) utility handles this automatically with fallback logic.

### Per-Result Highlights

Provider callbacks can optionally include a `highlight` field in their result to override the highlight group for that specific lens item. This is useful for providers that want to use different colors based on the result (e.g., red for high complexity, green for low).

```lua
handler = function(bufnr, func_info, provider_config, callback)
  local severity = get_severity(func_info)
  callback({
    line = func_info.line,
    text = severity .. " severity",
    highlight = severity == "high" and "DiagnosticError" or "DiagnosticOk",
  })
end
```

The highlight fallback chain is:
1. Result `highlight` (from callback) -- per-item override
2. Provider config `highlight` (from setup) -- per-provider default
3. Global `style.highlight` -- fallback for all providers

Omitting `highlight` or setting it to `""` falls back to the next level in the chain.

### Utility Functions

For common provider patterns, use the utility functions:

```lua
local utils = require("lensline.utils")

-- Check if nerdfonts are enabled
if utils.is_using_nerdfonts() then
  -- nerdfonts enabled
end

-- Choose value based on nerdfont setting
local icon = utils.if_nerdfont_else("📏", "Lines:")

-- Get function content as array of lines (including signature)
local function_lines = utils.get_function_lines(bufnr, func_info)
local function_text = table.concat(function_lines, "\n")

-- Get LSP references for composable LSP-based providers
utils.get_lsp_references(bufnr, func_info, function(references)
  if references then
    local count = #references
    -- Custom logic here
  end
end)

-- Check if LSP references are available
if utils.has_lsp_references_capability(bufnr) then
  -- LSP references supported
end
```

### Examples

**Sync provider (immediate callback):**
```lua
handler = function(bufnr, func_info, provider_config, callback)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  callback({ line = func_info.line, text = "📄 " .. line_count .. " lines" })
end
```

**Async provider (delayed callback):**
```lua
handler = function(bufnr, func_info, provider_config, callback)
  vim.lsp.buf_request(bufnr, "textDocument/hover", params, function(err, result)
    if result then
      callback({ line = func_info.line, text = "ℹ️ hover available" })
    else
      callback(nil)
    end
  end)
end
```

**Using provider config:**
```lua
handler = function(bufnr, func_info, provider_config, callback)
  local threshold = provider_config.threshold or 10
  local count = get_some_count(func_info)
  
  if count > threshold then
    callback({ line = func_info.line, text = "⚠️ " .. count })
  else
    callback(nil)
  end
end
```

## Registration

### Built-in Providers

Built-in providers are automatically available:

```lua
require("lensline").setup({
  providers = {
    { name = "references", enabled = true },
    { name = "last_author", enabled = true },
    { name = "complexity", enabled = true },
    { name = "diagnostics", enabled = true },
  }
})
```

### Inline Providers

For simple custom providers, define them directly in your config:

```lua
require("lensline").setup({
  providers = {
    { name = "references", enabled = true },
    
    -- Simple line counter
    {
      name = "line_counter",
      enabled = true,
      event = { "BufWritePost", "TextChanged" },
      handler = function(bufnr, func_info, provider_config, callback)
        local utils = require("lensline.utils")
        local total_lines = vim.api.nvim_buf_line_count(bufnr)
        local func_lines = "?"
        
        if func_info.end_line then
          func_lines = func_info.end_line - func_info.line + 1
        end
        
        local icon = utils.if_nerdfont_else("📏 ", "Lines: ")
        callback({
          line = func_info.line,
          text = string.format("%s%s/%d", icon, func_lines, total_lines)
        })
      end
    },
    
    -- TODO counter example
    {
      name = "todo_counter",
      enabled = true,
      event = { "BufWritePost" },
      handler = function(bufnr, func_info, provider_config, callback)
        local utils = require("lensline.utils")
        local function_lines = utils.get_function_lines(bufnr, func_info)
        local todos = 0
        
        for _, line in ipairs(function_lines) do
          if line:match("TODO") or line:match("FIXME") then
            todos = todos + 1
          end
        end
        
        if todos > 0 then
          local icon = utils.if_nerdfont_else("📝 ", "TODOs: ")
          callback({ line = func_info.line, text = icon .. todos .. " TODOs" })
        else
          callback(nil)
        end
      end
    },
    
    -- Popular/Unpopular function provider using LSP utilities
    {
      name = "popularity",
      enabled = true,
      event = { "LspAttach", "BufWritePost" },
      handler = function(bufnr, func_info, provider_config, callback)
        local utils = require("lensline.utils")
        
        utils.get_lsp_references(bufnr, func_info, function(references)
          if references then
            local count = #references
            local threshold = provider_config.threshold or 3
            local label = count >= threshold and "Popular" or "Unpopular"
            local icon = utils.if_nerdfont_else("📈 ", "")
            callback({
              line = func_info.line,
              text = icon .. label .. " (" .. count .. ")"
            })
          else
            callback(nil)
          end
        end)
      end
    },
    
    -- Unused function detector
    {
      name = "unused_detector",
      enabled = true,
      event = { "LspAttach", "BufWritePost" },
      handler = function(bufnr, func_info, provider_config, callback)
        local utils = require("lensline.utils")
        
        utils.get_lsp_references(bufnr, func_info, function(references)
          if references and #references == 0 then
            local icon = utils.if_nerdfont_else("🚫 ", "")
            callback({
              line = func_info.line,
              text = icon .. "Unused"
            })
          else
            callback(nil)  -- Only show for unused functions
          end
        end)
      end
    }
  }
})
```

### External Provider Files

For complex providers, create separate files and register them:

```lua
-- Add your custom provider to the registry
local providers = require("lensline.providers")
providers.available_providers.my_custom_provider = require("path.to.custom_provider")

require("lensline").setup({
  providers = {
    { name = "references", enabled = true },
    { name = "my_custom_provider", enabled = true },
  }
})
```

## Quick Start Guide

For simple providers, use the **inline provider** approach - define them directly in your config:

```lua
require("lensline").setup({
  providers = {
    { name = "references", enabled = true },
    
    -- Custom inline provider
    {
      name = "my_provider",
      enabled = true,
      event = { "BufWritePost" },
      handler = function(bufnr, func_info, provider_config, callback)
        local utils = require("lensline.utils")
        -- Use utilities for common patterns
        local lines = utils.get_function_lines(bufnr, func_info)
        local icon = utils.if_nerdfont_else("🔧 ", "Tool: ")
        callback({ line = func_info.line, text = icon .. "Custom" })
      end
    }
  }
})
```

## Available Utilities

The [`utils.lua`](lua/lensline/utils.lua) module provides organized utility functions:

**Core Utilities:**
- `utils.debounce(fn, delay)` - Debounce function calls
- `utils.is_valid_buffer(bufnr)` - Buffer validation

**Style & Configuration:**
- `utils.is_using_nerdfonts()` - Check if nerdfonts are enabled
- `utils.if_nerdfont_else(nerdfont_value, fallback_value)` - Conditional styling

**Buffer & Function Analysis:**
- `utils.get_function_lines(bufnr, func_info)` - Extract function content with smart end detection

**LSP Utilities:**
- `utils.has_lsp_references_capability(bufnr)` - Check LSP references support
- `utils.get_lsp_references(bufnr, func_info, callback)` - Get LSP references asynchronously