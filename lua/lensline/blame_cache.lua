local M = {}

-- Cache storage (keys are normalized paths)
local cache = {
  data = {},
  access_order = {},
  max_files = 50,
  hits = 0,
  misses = 0
}

local pending = {}

local function normalized_path(filename)
  if filename == "" then
    return filename
  end
  return vim.fn.fnamemodify(filename, ":p")
end

local function pending_key(normalized, end_line)
  return normalized .. ":" .. tostring(end_line)
end

local function update_access_order(filename)
  -- Remove from current position
  for i, name in ipairs(cache.access_order) do
    if name == filename then
      table.remove(cache.access_order, i)
      break
    end
  end
  
  -- Add to end (most recently used)
  table.insert(cache.access_order, filename)
end

-- Evict least recently used entry
local function evict_lru()
  if #cache.access_order == 0 then
    return
  end
  
  local oldest_file = cache.access_order[1]
  cache.data[oldest_file] = nil
  table.remove(cache.access_order, 1)
  
  local debug = require("lensline.debug")
  debug.log_context("BlameCache", "evicted LRU entry: " .. oldest_file)
end

-- Get file modification time
local function get_file_mtime(filename)
  local stat = vim.loop.fs_stat(filename)
  return stat and stat.mtime.sec or 0
end

local function spawn_command_async(cmd, callback)
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)
  local stdout_chunks = {}
  local stderr_chunks = {}

  local handle
  handle = vim.loop.spawn(cmd[1], {
    args = vim.list_slice(cmd, 2),
    stdio = { nil, stdout, stderr },
  }, function(code, signal)
    stdout:close()
    stderr:close()
    handle:close()

    vim.schedule(function()
      if code == 0 then
        local output = table.concat(stdout_chunks, "")
        local lines = {}
        for line in output:gmatch("([^\n]*)\n?") do
          if line ~= "" then
            table.insert(lines, line)
          end
        end
        callback(nil, lines)
      else
        local err = table.concat(stderr_chunks, "")
        callback({ code = code, message = err }, nil)
      end
    end)
  end)

  if not handle then
    stdout:close()
    stderr:close()
    callback({ message = "Failed to spawn command" }, nil)
    return
  end

  stdout:read_start(function(err, data)
    if data then
      table.insert(stdout_chunks, data)
    end
  end)

  stderr:read_start(function(err, data)
    if data then
      table.insert(stderr_chunks, data)
    end
  end)
end

M.spawn_command_async = spawn_command_async

-- Parse git blame output and create line-by-line author map
local function parse_blame_to_line_map(blame_output)
  local line_authors = {}
  local current_line = nil
  local current_author = nil
  local current_time = nil
  
  for _, line in ipairs(blame_output) do
    -- Check for commit hash line (start of new blame block)
    -- Format: "hash original_line final_line [num_lines]"
    local hash, orig_line, final_line = line:match("^([a-f0-9]+) (%d+) (%d+)")
    if hash and final_line then
      current_line = tonumber(final_line)
      -- Reset for new blame block
      current_author = nil
      current_time = nil
    end
    
    -- Extract author name
    local author = line:match("^author (.+)$")
    if author then
      current_author = author
    end
    
    -- Extract author timestamp
    local time_str = line:match("^author%-time (%d+)$")
    if time_str then
      current_time = tonumber(time_str)
      
      -- Store author info for this line when we have all data
      if current_author and current_time and current_line then
        line_authors[current_line] = {
          author = current_author,
          time = current_time
        }
      end
    end
  end
  
  return line_authors
end

local function finish_pending(pend_key, line_authors)
  local callbacks = pending[pend_key]
  pending[pend_key] = nil
  if callbacks then
    for _, cb in ipairs(callbacks) do
      cb(line_authors)
    end
  end
end

function M.get_blame_data(filename, bufnr, callback)
  local debug = require("lensline.debug")
  local limits = require("lensline.limits")
  local normalized = normalized_path(filename)
  if normalized == "" then
    debug.log_context("BlameCache", "empty filename")
    callback(nil)
    return
  end

  local current_mtime = get_file_mtime(filename)
  if current_mtime == 0 then
    debug.log_context("BlameCache", "file not found or inaccessible: " .. filename)
    callback(nil)
    return
  end

  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  local end_line = limits.get_truncated_end_line(bufnr, total_lines)
  if end_line == 0 then
    debug.log_context("BlameCache", "file should be skipped entirely: " .. filename)
    callback(nil)
    return
  end

  local cache_entry = cache.data[normalized]
  if cache_entry and cache_entry.mtime == current_mtime and cache_entry.end_line == end_line then
    cache.hits = cache.hits + 1
    update_access_order(normalized)
    debug.log_context("BlameCache", "cache hit for " .. normalized .. " (lines 1-" .. end_line .. ")")
    callback(cache_entry.line_authors)
    return
  end

  local pend_key = pending_key(normalized, end_line)
  if pending[pend_key] then
    table.insert(pending[pend_key], callback)
    return
  end

  cache.misses = cache.misses + 1
  debug.log_context("BlameCache", "cache miss for " .. normalized .. " (lines 1-" .. end_line .. ")")
  pending[pend_key] = { callback }

  local file_dir = vim.fn.fnamemodify(filename, ":h")
  local git_root_cmd = { "git", "-C", file_dir, "rev-parse", "--show-toplevel" }

  M.spawn_command_async(git_root_cmd, function(err, git_root_result)
    if err or not git_root_result or #git_root_result == 0 then
      debug.log_context("BlameCache", "not in git repository: " .. filename)
      finish_pending(pend_key, nil)
      return
    end

    local git_root = git_root_result[1]
    local lines_range = "1," .. end_line
    local blame_cmd = { "git", "-C", git_root, "blame", "--line-porcelain", "-L", lines_range, filename }

    M.spawn_command_async(blame_cmd, function(blame_err, blame_output)
      if blame_err then
        debug.log_context("BlameCache", "git blame failed for " .. filename .. ": " .. (blame_err.message or "unknown error"))
        finish_pending(pend_key, nil)
        return
      end

      local line_authors = parse_blame_to_line_map(blame_output)
      if vim.tbl_count(cache.data) >= cache.max_files then
        evict_lru()
      end

      cache.data[normalized] = {
        mtime = current_mtime,
        end_line = end_line,
        line_authors = line_authors
      }
      update_access_order(normalized)
      debug.log_context("BlameCache", "cached blame data for " .. normalized .. " (" .. vim.tbl_count(line_authors) .. " lines)")
      finish_pending(pend_key, line_authors)
    end)
  end)
end

-- Helper function to estimate function end line when not provided
local function estimate_function_end(bufnr, start_line)
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, math.min(start_line + 50, total_lines), false)
  
  local end_line = start_line
  local indent_level = nil
  
  for i, line in ipairs(lines) do
    local current_line = start_line + i - 1

    if not line:match("^%s*$") then
      local current_indent = #line:match("^%s*")

      if indent_level == nil then
        indent_level = current_indent
      else
        if current_indent <= indent_level and i > 1 then
          -- Make sure it's not just a continuation of the function signature
          if not line:match("^%s*[%w_(),:%s]*:?%s*$") then
            end_line = current_line - 1
            break
          end
        end

        if current_indent > indent_level then
          end_line = current_line
        end
      end
    end
  end
  
  -- Add a safety margin if we reached the scan limit
  if end_line == start_line + #lines - 1 and end_line < total_lines then
    end_line = math.min(start_line + 20, total_lines)  -- Conservative default
  end
  
  return end_line
end

function M.get_function_author(filename, bufnr, func_info, callback)
  M.get_blame_data(filename, bufnr, function(line_authors)
    if not line_authors then
      callback(nil)
      return
    end

    local function_start = func_info.line
    local function_end = func_info.end_line
    if not function_end then
      function_end = estimate_function_end(bufnr, function_start)
    end

    local latest_author, latest_time = nil, 0
    for line = function_start, function_end do
      local line_info = line_authors[line]
      if line_info and line_info.time > latest_time then
        latest_author = line_info.author
        latest_time = line_info.time
      end
    end

    if latest_author and latest_time > 0 then
      if latest_author == "Not Committed Yet" then
        callback({ author = "uncommitted", time = nil })
        return
      end
      callback({ author = latest_author, time = latest_time })
      return
    end
    callback(nil)
  end)
end

-- Configure cache settings
function M.configure(config)
  cache.max_files = config.max_files or 50
  
  local debug = require("lensline.debug")
  debug.log_context("BlameCache", "configured with max_files=" .. cache.max_files)
end

-- Get cache statistics
function M.get_stats()
  return {
    hits = cache.hits,
    misses = cache.misses,
    hit_rate = cache.hits + cache.misses > 0 and (cache.hits / (cache.hits + cache.misses)) or 0,
    cached_files = vim.tbl_count(cache.data),
    max_files = cache.max_files
  }
end

function M.clear_cache()
  cache.data = {}
  cache.access_order = {}
  cache.hits = 0
  cache.misses = 0
  for k in pairs(pending) do
    pending[k] = nil
  end
  local debug = require("lensline.debug")
  debug.log_context("BlameCache", "cache cleared")
end

return M