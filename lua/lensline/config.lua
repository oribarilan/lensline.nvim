local M = {}

M.defaults = {
  providers = {  -- Array format: order determines display sequence
    {
      name = "references",
      enabled = true,     -- enable references provider
      quiet_lsp = true,   -- suppress noisy LSP log messages (e.g., Pyright reference spam)
    },
    {
      name = "diagnostics",
      enabled = false,    -- disabled by default - enable explicitly to use
      min_level = "WARN", -- only show WARN and ERROR by default (HINT, INFO, WARN, ERROR)
    },
    {
      name = "last_author",
      enabled = true,    -- enable by default with caching optimization
      cache_max_files = 50,  -- maximum number of files to cache blame data for
    },
    {
      name = "complexity",
      enabled = false,    -- disabled by default - enable explicitly to use
      min_level = "L",    -- only show L (Large) and XL (Extra Large) complexity by default
    },
  },
  style = {
    separator = " • ",
    highlight = "Comment",
    prefix = "┃ ",
    placement = "above",   -- "above" | "inline" - where to render lenses
    use_nerdfont = true,   -- enable nerd font icons in built-in providers
    render = "all",        -- "all" (existing behavior) | "focused" (only active window's focused function)
  },
  limits = {
    exclude = {
      -- Common
      ".git/**",
      "build*/**",        -- Covers `build`, `build_debug`, etc.

      -- JavaScript/TypeScript
      "node_modules/**",
      "dist/**",
      "out/**",
      ".next/**",
      "*.min.js",
      "*.min.css",

      -- Python
      ".venv/**",
      "venv/**",
      "env/**",
      "__pycache__/**",
      ".mypy_cache/**",

      -- Rust
      "target/**",

      -- Java
      "build/**",         -- Gradle build output
      "target/**",        -- Maven build output (also used in Rust)
      ".gradle/**",       -- Gradle metadata
      ".settings/**",     -- Eclipse project settings
      ".classpath",       -- Eclipse metadata
      ".project",         -- Eclipse metadata

      -- C# (.NET / MSBuild)
      "bin/**",           -- Compiled binaries
      "obj/**",           -- Intermediate object files
      "*.dll",            -- Assemblies (expensive to parse)
      "*.exe",            -- Binaries
      "*.pdb",            -- Debug symbols
      "*.csproj",         -- Metadata (can include but probably not needed for lenses)
    },
    exclude_gitignored = true,
    max_lines = 1000,
    max_lenses = 70,
  },
  debounce_ms = 500,  -- unified debounce delay for all providers (in milliseconds)
  focused_debounce_ms = 150,  -- debounce delay for focus tracking in focused mode (in milliseconds)
  provider_timeout_ms = 5000, -- provider execution timeout (ms) for async safety net (test override supported)
  debug_mode = false,
}

M.options = M.defaults
M._enabled = false  -- global toggle state - Level 1: Engine control
M._visible = true   -- global visibility state - Level 2: View control

-- Track deprecation warnings to avoid spam
local _deprecation_warnings = {}

function M.setup(opts)
  opts = opts or {}
  
  -- Handle backward compatibility for root-level render config
  if opts.render ~= nil then
    local warning_key = "root_render_deprecated"
    if not _deprecation_warnings[warning_key] then
      vim.notify(
        "[lensline] DEPRECATED: 'render' config moved to 'style.render'\n" ..
        "Please update: { style = { render = \"" .. opts.render .. "\" } }\n" ..
        "Root-level 'render' will be removed in v2",
        vim.log.levels.WARN
      )
      _deprecation_warnings[warning_key] = true
    end
    
    -- Migrate root-level render to style.render if not already set
    opts.style = opts.style or {}
    if opts.style.render == nil then
      opts.style.render = opts.render
    else
      -- Both locations specified - warn about conflict
      local conflict_key = "render_conflict"
      if not _deprecation_warnings[conflict_key] then
        vim.notify(
          "[lensline] WARNING: Both 'render' and 'style.render' specified\n" ..
          "Using 'style.render' value: '" .. opts.style.render .. "'\n" ..
          "Remove root-level 'render' to avoid this warning",
          vim.log.levels.WARN
        )
        _deprecation_warnings[conflict_key] = true
      end
    end
    
    -- Remove root-level render from final config
    opts.render = nil
  end
  
  M.options = vim.tbl_deep_extend("force", M.defaults, opts)
  M._enabled = true  -- enable by default when setup is called
  M._visible = true  -- visible by default when setup is called
end

function M.get()
  return M.options
end

function M.get_render_mode()
  local opts = M.get()
  -- Always use style.render since we migrate in setup()
  return opts.style.render
end

function M.is_enabled()
  return M._enabled
end

function M.set_enabled(enabled)
  M._enabled = enabled
end

function M.is_visible()
  return M._visible
end

function M.set_visible(visible)
  M._visible = visible
end

-- LSP message filtering - surgical "Finding references" suppression
local original_progress_handler = nil
local suppressed_tokens = {}  -- Track tokens for "Finding references" operations

function M.setup_lsp_handlers()
  local opts = M.get()
  
  -- Check if any LSP provider has quiet_lsp enabled
  local should_setup_filtering = false
  for _, provider in ipairs(opts.providers) do
    if provider.name == "references" and provider.quiet_lsp ~= false then
      should_setup_filtering = true
      break
    end
  end
  
  if not should_setup_filtering then
    return
  end
  
  local debug = require("lensline.debug")
  
  -- Store original handler if we haven't already
  if not original_progress_handler then
    original_progress_handler = vim.lsp.handlers["$/progress"]
  end
  
  -- Surgical filtering: suppress entire "Finding references" progress cycles
  vim.lsp.handlers["$/progress"] = function(err, result, ctx, config)
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    
    if client and client.name == "pyright" and result and result.value then
      local token = result.token
      local kind = result.value.kind
      local title = result.value.title
      
      -- Track "Finding references" operations by their token
      if kind == "begin" and title == "Finding references" then
        suppressed_tokens[token] = true
        debug.log_context("LSP Filter", string.format("SUPPRESSING begin: %s (token: %s)", title, token or "unknown"))
        return  -- 🧹 Suppress begin event
      end
      
      -- Suppress end events for tracked "Finding references" operations
      if kind == "end" and suppressed_tokens[token] then
        suppressed_tokens[token] = nil  -- Clean up
        debug.log_context("LSP Filter", string.format("SUPPRESSING end: (token: %s)", token or "unknown"))
        return  -- 🧹 Suppress corresponding end event
      end
    end
    
    -- Allow all other progress messages through
    if original_progress_handler then
      return original_progress_handler(err, result, ctx, config)
    end
  end
  
  debug.log_context("LSP Filter", "Surgical LSP filtering enabled - suppressing only 'Finding references' progress")
end

function M.restore_lsp_handlers()
  -- Restore original progress handler when disabling
  if original_progress_handler then
    vim.lsp.handlers["$/progress"] = original_progress_handler
    original_progress_handler = nil
  end
end

return M