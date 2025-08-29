local M = {}

-- Cache storage
local cache = {
  data = {},           -- { filename -> { mtime, end_line, line_authors } }
  access_order = {},   -- [filename1, filename2, ...] (LRU order)
  max_files = 50,      -- Default, will be configurable
  
  -- Stats for debugging
  hits = 0,
  misses = 0
}

-- Update access order for LRU
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

-- Get cached blame data or fetch from git
function M.get_blame_data(filename, bufnr)
  local debug = require("lensline.debug")
  local limits = require("lensline.limits")
  
  -- Get current file mtime and truncated end line
  local current_mtime = get_file_mtime(filename)
  if current_mtime == 0 then
    debug.log_context("BlameCache", "file not found or inaccessible: " .. filename)
    return nil
  end
  
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  local end_line = limits.get_truncated_end_line(bufnr, total_lines)
  
  if end_line == 0 then
    debug.log_context("BlameCache", "file should be skipped entirely: " .. filename)
    return nil
  end
  
  -- Check cache
  local cache_entry = cache.data[filename]
  if cache_entry and 
     cache_entry.mtime == current_mtime and 
     cache_entry.end_line == end_line then
    -- Cache hit
    cache.hits = cache.hits + 1
    update_access_order(filename)
    debug.log_context("BlameCache", "cache hit for " .. filename .. " (lines 1-" .. end_line .. ")")
    return cache_entry.line_authors
  end
  
  -- Cache miss - fetch from git
  cache.misses = cache.misses + 1
  debug.log_context("BlameCache", "cache miss for " .. filename .. " (lines 1-" .. end_line .. ")")
  
  -- Get git root
  local file_dir = vim.fn.fnamemodify(filename, ":h")
  local git_root_cmd = { "git", "-C", file_dir, "rev-parse", "--show-toplevel" }
  local git_root_result = vim.fn.systemlist(git_root_cmd)
  local git_root = git_root_result[1]
  
  if vim.v.shell_error ~= 0 or not git_root or git_root == "" then
    debug.log_context("BlameCache", "not in git repository: " .. filename)
    return nil
  end
  
  -- Run git blame for the truncated range
  local lines_range = "1," .. end_line
  local blame_cmd = { "git", "-C", git_root, "blame", "--line-porcelain", "-L", lines_range, filename }
  local blame_output = vim.fn.systemlist(blame_cmd)
  
  if vim.v.shell_error ~= 0 then
    debug.log_context("BlameCache", "git blame failed for " .. filename .. ": " .. vim.v.shell_error)
    return nil
  end
  
  -- Parse blame output to line map
  local line_authors = parse_blame_to_line_map(blame_output)
  
  -- Store in cache (evict if necessary)
  if vim.tbl_count(cache.data) >= cache.max_files then
    evict_lru()
  end
  
  cache.data[filename] = {
    mtime = current_mtime,
    end_line = end_line,
    line_authors = line_authors
  }
  
  update_access_order(filename)
  debug.log_context("BlameCache", "cached blame data for " .. filename .. " (" .. vim.tbl_count(line_authors) .. " lines)")
  
  return line_authors
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

-- Get author info for a specific function range
function M.get_function_author(filename, bufnr, func_info)
  local line_authors = M.get_blame_data(filename, bufnr)
  if not line_authors then
    return nil
  end
  
  local function_start = func_info.line
  local function_end = func_info.end_line
  
  -- If no end_line provided, estimate it
  if not function_end then
    function_end = estimate_function_end(bufnr, function_start)
  end
  
  -- Find the most recent author in the function range
  local latest_author, latest_time = nil, 0
  
  for line = function_start, function_end do
    local line_info = line_authors[line]
    if line_info and line_info.time > latest_time then
      latest_author = line_info.author
      latest_time = line_info.time
    end
  end
  
  if latest_author and latest_time > 0 then
    -- Handle uncommitted changes - don't include misleading timestamp
    if latest_author == "Not Committed Yet" then
      return {
        author = "uncommitted",
        time = nil  -- No meaningful timestamp for uncommitted changes
      }
    end
    
    return {
      author = latest_author,
      time = latest_time
    }
  end
  
  return nil
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

-- Clear cache (useful for testing or config changes)
function M.clear_cache()
  cache.data = {}
  cache.access_order = {}
  cache.hits = 0
  cache.misses = 0
  
  local debug = require("lensline.debug")
  debug.log_context("BlameCache", "cache cleared")
end

return M