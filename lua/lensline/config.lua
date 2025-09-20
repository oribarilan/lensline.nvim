local M = {}

M.defaults = {
  providers = {  -- Array format: order determines display sequence
    {
      name = "usages",
      enabled = true,       -- enable usages provider by default
      include = { "refs" }, -- refs-only setup
      breakdown = true,
      show_zero = true,     -- show zero counts 
      labels = {
        refs = "refs",
        impls = "impls",
        defs = "defs",
        usages = "usages",
      },
      icon_for_single = "󰌹 ",
      inner_separator = ", ",
    },
    {
      name = "references",
      enabled = false,    -- deprecated: use usages provider instead
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

-- Profile state management
M._profiles_config = nil  -- stores the full config with profiles
M._active_profile = nil   -- currently active profile name

-- Track deprecation warnings to avoid spam
local _deprecation_warnings = {}
M._deprecation_warnings = _deprecation_warnings  -- Expose for testing

-- Check if config uses legacy format (providers/style at root level)
local function has_legacy_config(opts)
  return opts.providers ~= nil or opts.style ~= nil
end

-- Check if config uses new profiles format
local function has_profiles_config(opts)
  return opts.profiles ~= nil and type(opts.profiles) == "table"
end

-- Extract global settings that apply to all profiles
local function extract_global_settings(opts)
  local global_keys = {
    "limits", "debounce_ms", "focused_debounce_ms",
    "provider_timeout_ms", "debug_mode"
  }
  
  local global_settings = {}
  for _, key in ipairs(global_keys) do
    if opts[key] ~= nil then
      global_settings[key] = opts[key]
    end
  end
  
  return global_settings
end

-- Extract profile-specific settings (providers and style)
local function extract_profile_settings(opts)
  return {
    providers = opts.providers,
    style = opts.style
  }
end

-- Convert legacy config to profiles format
local function migrate_legacy_to_profiles(opts)
  local global_settings = extract_global_settings(opts)
  local profile_settings = extract_profile_settings(opts)
  
  -- Create default profile from legacy config
  local migrated_config = vim.tbl_deep_extend("force", global_settings, {
    profiles = {
      {
        name = "default",
        providers = profile_settings.providers or M.defaults.providers,
        style = profile_settings.style or M.defaults.style
      }
    }
  })
  
  return migrated_config
end

-- Validate profiles array structure
local function validate_profiles(profiles)
  if type(profiles) ~= "table" then
    error("profiles must be an array")
  end
  
  if #profiles == 0 then
    error("profiles array cannot be empty")
  end
  
  local profile_names = {}
  for i, profile in ipairs(profiles) do
    if type(profile) ~= "table" then
      error(string.format("profile at index %d must be a table", i))
    end
    
    if type(profile.name) ~= "string" or profile.name == "" then
      error(string.format("profile at index %d must have a non-empty name", i))
    end
    
    if profile_names[profile.name] then
      error(string.format("duplicate profile name: %s", profile.name))
    end
    profile_names[profile.name] = true
    
    -- Validate that profile only contains providers and style
    for key, _ in pairs(profile) do
      if key ~= "name" and key ~= "providers" and key ~= "style" then
        vim.notify(
          string.format("[lensline] WARNING: Profile '%s' contains unexpected key '%s'. Only 'providers' and 'style' are supported in profiles.", profile.name, key),
          vim.log.levels.WARN
        )
      end
    end
  end
end

-- Get profile by name from profiles array
local function get_profile_by_name(profiles, name)
  for _, profile in ipairs(profiles) do
    if profile.name == name then
      return profile
    end
  end
  return nil
end

-- Merge individual provider configs with their defaults
local function merge_provider_configs(user_providers, default_providers)
  if not user_providers then
    return {}  -- If no providers specified, return empty array (don't use defaults)
  end
  
  -- Create lookup table for default providers by name
  local defaults_by_name = {}
  for _, default_provider in ipairs(default_providers) do
    defaults_by_name[default_provider.name] = default_provider
  end
  
  -- Merge each user provider with its defaults
  local merged_providers = {}
  for _, user_provider in ipairs(user_providers) do
    local provider_name = user_provider.name
    local default_provider = defaults_by_name[provider_name] or {}
    
    -- Deep merge user provider config with defaults
    local merged_provider = vim.tbl_deep_extend("force", default_provider, user_provider)
    table.insert(merged_providers, merged_provider)
  end
  
  return merged_providers
end

-- Resolve active profile configuration
local function resolve_active_config(full_config, profile_name)
  if not full_config.profiles then
    return full_config  -- Legacy mode
  end
  
  local active_profile = get_profile_by_name(full_config.profiles, profile_name)
  if not active_profile then
    error(string.format("Profile '%s' not found", profile_name))
  end
  
  -- Merge global settings with active profile
  local global_settings = extract_global_settings(full_config)
  
  -- Properly merge provider configs with defaults
  local merged_providers = merge_provider_configs(active_profile.providers, M.defaults.providers)
  
  local resolved_config = vim.tbl_deep_extend("force", M.defaults, global_settings, {
    providers = merged_providers,
    style = active_profile.style or {}
  })
  
  return resolved_config
end

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
  
  -- Handle profile configuration
  local final_config
  
  if has_profiles_config(opts) then
    -- New profiles format
    validate_profiles(opts.profiles)
    M._profiles_config = opts
    M._active_profile = opts.active_profile or opts.profiles[1].name  -- first profile is default
    
    -- Resolve active profile configuration
    final_config = resolve_active_config(M._profiles_config, M._active_profile)
  elseif has_legacy_config(opts) then
    -- Legacy format with deprecation warning
    local warning_key = "legacy_config_deprecated"
    if not _deprecation_warnings[warning_key] then
      vim.notify(
        "[lensline] DEPRECATED: Root-level 'providers' and 'style' config will be removed in v2\n" ..
        "Please migrate to profiles format:\n" ..
        "{ profiles = { { name = \"default\", providers = {...}, style = {...} } } }\n" ..
        "See documentation for migration guide",
        vim.log.levels.WARN
      )
      _deprecation_warnings[warning_key] = true
    end
    
    -- Auto-migrate legacy config
    local migrated_config = migrate_legacy_to_profiles(opts)
    M._profiles_config = migrated_config
    M._active_profile = "default"
    
    final_config = resolve_active_config(M._profiles_config, M._active_profile)
  else
    -- No profiles and no legacy config - use defaults
    final_config = opts
    M._profiles_config = nil
    M._active_profile = nil
  end
  
  M.options = vim.tbl_deep_extend("force", M.defaults, final_config)
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

-- Profile management functions

function M.has_profiles()
  return M._profiles_config ~= nil
end

function M.get_active_profile()
  return M._active_profile
end

function M.list_profiles()
  if not M._profiles_config or not M._profiles_config.profiles then
    return {}
  end
  
  local names = {}
  for _, profile in ipairs(M._profiles_config.profiles) do
    table.insert(names, profile.name)
  end
  return names
end

function M.has_profile(name)
  if not M._profiles_config or not M._profiles_config.profiles then
    return false
  end
  
  return get_profile_by_name(M._profiles_config.profiles, name) ~= nil
end

function M.get_profile_config(name)
  if not M._profiles_config or not M._profiles_config.profiles then
    return nil
  end
  
  return get_profile_by_name(M._profiles_config.profiles, name)
end

function M.switch_profile(name)
  if not M._profiles_config or not M._profiles_config.profiles then
    error("No profiles configured. Cannot switch profiles.")
  end
  
  if not M.has_profile(name) then
    error(string.format("Profile '%s' not found. Available profiles: %s",
      name, table.concat(M.list_profiles(), ", ")))
  end
  
  if M._active_profile == name then
    return  -- Already active, no-op
  end
  
  -- Store previous profile for potential rollback
  local previous_profile = M._active_profile
  
  -- Switch to new profile
  M._active_profile = name
  
  -- Resolve new configuration
  local success, new_config = pcall(resolve_active_config, M._profiles_config, M._active_profile)
  if not success then
    -- Rollback on error
    M._active_profile = previous_profile
    error(string.format("Failed to switch to profile '%s': %s", name, new_config))
  end
  
  -- Update active configuration
  M.options = vim.tbl_deep_extend("force", M.defaults, new_config)
  
  return true
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