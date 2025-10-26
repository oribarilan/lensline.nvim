local M = {}

-- Cache for expensive operations
local cache = {}
local gitignore_cache = {}

-- Clear cache when config changes
function M.clear_cache()
  local debug = require("lensline.debug")
  local cached_count = 0
  for _ in pairs(gitignore_cache) do
    cached_count = cached_count + 1
  end
  
  if cached_count > 0 then
    debug.log_context("Gitignore", "clearing cache (%d files)", cached_count)
  end
  
  cache = {}
  gitignore_cache = {}
end

-- Get cache key for a buffer
local function get_cache_key(bufnr)
  return bufnr .. ":" .. vim.api.nvim_buf_get_changedtick(bufnr)
end

-- Check if file matches any glob pattern
local function matches_glob_pattern(filepath, patterns)
  for _, pattern in ipairs(patterns) do
    -- Convert glob pattern to lua pattern for matching
    local lua_pattern = pattern
      :gsub("([%.%+%-%?%[%]%(%)])", "%%%1") -- Escape lua pattern chars
      :gsub("%*%*", ".-")                   -- ** -> .* (any chars including /)
      :gsub("%*", "[^/]*")                  -- * -> [^/]* (any chars except /)
    
    -- Add anchors for full path matching
    lua_pattern = "^.*" .. lua_pattern .. ".*$"
    
    if filepath:match(lua_pattern) then
      return true
    end
  end
  return false
end

-- Check if a file is gitignored using git check-ignore
local function is_gitignored(filepath)
  if gitignore_cache[filepath] ~= nil then
    return gitignore_cache[filepath]
  end
  
  local git_dir = vim.fn.finddir('.git', vim.fn.fnamemodify(filepath, ':h') .. ';')
  if git_dir == '' then
    gitignore_cache[filepath] = false
    return false
  end
  
  local git_root = vim.fn.fnamemodify(git_dir, ':h')
  local relative_path = vim.fn.fnamemodify(filepath, ':.')
  
  local cmd = {"git", "-C", git_root, "check-ignore", "-q", relative_path}
  vim.fn.system(cmd)
  
  local is_ignored = vim.v.shell_error == 0
  
  gitignore_cache[filepath] = is_ignored
  
  return is_ignored
end

-- Check if file should be excluded based on patterns and gitignore
local function should_exclude_file(bufnr, config)
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == '' then
    return false
  end
  
  -- Normalize path
  filepath = vim.fn.fnamemodify(filepath, ":p")
  
  -- Check glob patterns
  if config.exclude and #config.exclude > 0 then
    if matches_glob_pattern(filepath, config.exclude) then
      return true, "excluded by glob pattern"
    end
  end
  
  -- Check gitignore
  if config.exclude_gitignored then
    if is_gitignored(filepath) then
      return true, "excluded by .gitignore"
    end
  end
  
  return false, nil
end

-- Check if buffer exceeds line limits
local function check_line_limits(bufnr, config)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  
  if config.max_lines and line_count > config.max_lines then
    return true, line_count, "file has " .. line_count .. " lines, exceeds max_lines=" .. config.max_lines
  end
  
  return false, line_count, nil
end

-- Main function to check if processing should be skipped
function M.should_skip(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return true, "invalid buffer"
  end
  
  local config = require("lensline.config").get()
  local limits_config = config.limits or {}
  
  -- Check cache first
  local cache_key = get_cache_key(bufnr)
  if cache[cache_key] then
    local cached = cache[cache_key]
    return cached.should_skip, cached.reason, cached.metadata
  end
  
  local debug = require("lensline.debug")
  
  -- Check file exclusion
  local excluded, exclude_reason = should_exclude_file(bufnr, limits_config)
  if excluded then
    cache[cache_key] = { should_skip = true, reason = exclude_reason }
    debug.log_context("Limits", "skipping buffer " .. bufnr .. ": " .. exclude_reason)
    return true, exclude_reason
  end
  
  -- Check line limits (this doesn't skip, just provides metadata for truncation)
  local exceeds_lines, line_count, line_reason = check_line_limits(bufnr, limits_config)
  local metadata = { 
    line_count = line_count,
    truncate_to = exceeds_lines and limits_config.max_lines or nil
  }
  
  if exceeds_lines then
    debug.log_context("Limits", "buffer " .. bufnr .. " will be truncated: " .. line_reason)
  end
  
  -- Cache result
  cache[cache_key] = { 
    should_skip = false, 
    reason = nil, 
    metadata = metadata 
  }
  
  return false, nil, metadata
end

-- Check if lens count exceeds limits (called after provider execution)
function M.should_skip_lenses(lens_count, config)
  local limits_config = config.limits or {}
  
  if limits_config.max_lenses and lens_count > limits_config.max_lenses then
    local debug = require("lensline.debug")
    debug.log_context("Limits", "skipping " .. lens_count .. " lenses, exceeds max_lenses=" .. limits_config.max_lenses)
    return true, "lens count " .. lens_count .. " exceeds max_lenses=" .. limits_config.max_lenses
  end
  
  return false, nil
end

-- Get adjusted end line for truncation
function M.get_truncated_end_line(bufnr, requested_end_line)
  local should_skip, reason, metadata = M.should_skip(bufnr)
  if should_skip then
    return 0 -- Skip entirely
  end
  
  if metadata and metadata.truncate_to then
    return math.min(requested_end_line, metadata.truncate_to)
  end
  
  return requested_end_line
end

return M