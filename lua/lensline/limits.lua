local M = {}

-- Cache the gitignore decision per filepath; this is the only state worth
-- holding onto across calls. Glob matching is cheap and stable; line-count
-- truncation is recomputed on demand.
local gitignore_cache = {}
-- Pending async gitignore checks: filepath -> list of callbacks waiting for
-- the in-flight `git check-ignore` to return. Used to deduplicate concurrent
-- callers asking about the same file.
local gitignore_pending = {}

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

  gitignore_cache = {}
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

-- Resolve whether a file is gitignored. Cache hits resolve synchronously
-- via cb; on cache miss, spawns `git check-ignore` off the main thread (via
-- blame_cache.spawn_command_async) and queues concurrent callers so only
-- one process is spawned per filepath.
local function is_gitignored_async(filepath, cb)
  local cached = gitignore_cache[filepath]
  if cached == true or cached == false then
    cb(cached)
    return
  end

  local git_dir = vim.fn.finddir('.git', vim.fn.fnamemodify(filepath, ':h') .. ';')
  if git_dir == '' then
    gitignore_cache[filepath] = false
    cb(false)
    return
  end

  -- A check is already in flight for this filepath; queue and wait.
  if gitignore_pending[filepath] then
    table.insert(gitignore_pending[filepath], cb)
    return
  end

  gitignore_pending[filepath] = { cb }
  local git_root = vim.fn.fnamemodify(git_dir, ':h')
  local relative_path = vim.fn.fnamemodify(filepath, ':.')
  local cmd = { "git", "-C", git_root, "check-ignore", "-q", relative_path }

  local blame_cache = require("lensline.blame_cache")
  blame_cache.spawn_command_async(cmd, function(err, _)
    -- git check-ignore exits 0 when the file IS ignored; non-zero (which
    -- spawn_command_async surfaces as err) means not ignored.
    local is_ignored = (err == nil)
    gitignore_cache[filepath] = is_ignored
    local callbacks = gitignore_pending[filepath]
    gitignore_pending[filepath] = nil
    if callbacks then
      for _, queued_cb in ipairs(callbacks) do
        queued_cb(is_ignored)
      end
    end
  end)
end

-- Async gate: callers must wait for cb(skip, reason) before proceeding into
-- any work that touches providers, blame, or function discovery. This is the
-- single entry point that may spawn `git check-ignore`; downstream helpers
-- (e.g. get_truncated_end_line) assume the gitignore decision is settled.
function M.should_skip_async(bufnr, cb)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    cb(true, "invalid buffer")
    return
  end

  local config = require("lensline.config").get()
  local limits_config = config.limits or {}

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == '' then
    cb(false)
    return
  end
  filepath = vim.fn.fnamemodify(filepath, ":p")

  if limits_config.exclude and #limits_config.exclude > 0 then
    if matches_glob_pattern(filepath, limits_config.exclude) then
      cb(true, "excluded by glob pattern")
      return
    end
  end

  if limits_config.exclude_gitignored then
    is_gitignored_async(filepath, function(is_ignored)
      if is_ignored then
        cb(true, "excluded by .gitignore")
      else
        cb(false)
      end
    end)
    return
  end

  cb(false)
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

-- Apply max_lines truncation. Precondition: callers must have already passed
-- should_skip_async for this buffer; this function does not re-check exclusion
-- or gitignore status.
function M.get_truncated_end_line(bufnr, requested_end_line)
  local limits_config = (require("lensline.config").get().limits) or {}
  if limits_config.max_lines then
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    if line_count > limits_config.max_lines then
      return math.min(requested_end_line, limits_config.max_lines)
    end
  end
  return requested_end_line
end

return M
