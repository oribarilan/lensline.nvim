local eq = assert.are.same

describe("limits.should_skip_async", function()
  local original_finddir
  local original_spawn

  before_each(function()
    package.loaded["lensline.limits"] = nil
    package.loaded["lensline.config"] = nil
    original_finddir = vim.fn.finddir
    local blame_cache = require("lensline.blame_cache")
    original_spawn = blame_cache.spawn_command_async
  end)

  after_each(function()
    vim.fn.finddir = original_finddir
    local blame_cache = require("lensline.blame_cache")
    blame_cache.spawn_command_async = original_spawn
  end)

  local function set_git_dir(path)
    vim.fn.finddir = function(pattern, p)
      if pattern == ".git" then
        return path
      end
      return original_finddir(pattern, p)
    end
  end

  -- Stub spawn so check-ignore commands report a fixed exit. ignored=true
  -- means exit 0 (file is gitignored); ignored=false means exit 1.
  local function stub_check_ignore(ignored, counter)
    local blame_cache = require("lensline.blame_cache")
    blame_cache.spawn_command_async = function(cmd, callback)
      if type(cmd) == "table" and cmd[1] == "git" and cmd[4] == "check-ignore" then
        if counter then counter.count = counter.count + 1 end
        if ignored then
          callback(nil, {})
        else
          callback({ code = 1, message = "" }, nil)
        end
      else
        callback({ code = 1, message = "" }, nil)
      end
    end
  end

  it("returns skip=true for invalid bufnr", function()
    local limits = require("lensline.limits")
    limits.clear_cache()
    local skip, reason
    limits.should_skip_async(99999, function(s, r)
      skip, reason = s, r
    end)
    eq(true, skip)
    eq("invalid buffer", reason)
  end)

  it("returns skip=false when buffer has no name", function()
    local limits = require("lensline.limits")
    limits.clear_cache()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local skip
    limits.should_skip_async(bufnr, function(s) skip = s end)
    eq(false, skip)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("skips files matching exclude glob without spawning git", function()
    local limits = require("lensline.limits")
    limits.clear_cache()
    local counter = { count = 0 }
    stub_check_ignore(false, counter)

    local config = require("lensline.config")
    config.options.limits = { exclude = { "*.min.js" }, exclude_gitignored = true }

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/tmp/bundle.min.js")

    local skip, reason
    limits.should_skip_async(bufnr, function(s, r)
      skip, reason = s, r
    end)

    eq(true, skip)
    eq("excluded by glob pattern", reason)
    eq(0, counter.count)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("does not spawn git when exclude_gitignored is false", function()
    local limits = require("lensline.limits")
    limits.clear_cache()
    local counter = { count = 0 }
    stub_check_ignore(true, counter)
    set_git_dir("/test/.git")

    local config = require("lensline.config")
    config.options.limits = { exclude_gitignored = false }

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/test/node_modules/foo.js")

    local skip
    limits.should_skip_async(bufnr, function(s) skip = s end)

    eq(false, skip)
    eq(0, counter.count)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("returns skip=true with reason when git check-ignore reports ignored", function()
    local limits = require("lensline.limits")
    limits.clear_cache()
    local counter = { count = 0 }
    stub_check_ignore(true, counter)
    set_git_dir("/test/.git")

    local config = require("lensline.config")
    config.options.limits = { exclude_gitignored = true }

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/test/node_modules/pkg.js")

    local skip, reason
    limits.should_skip_async(bufnr, function(s, r)
      skip, reason = s, r
    end)

    eq(true, skip)
    eq("excluded by .gitignore", reason)
    eq(1, counter.count)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("returns skip=false when git check-ignore reports not ignored", function()
    local limits = require("lensline.limits")
    limits.clear_cache()
    local counter = { count = 0 }
    stub_check_ignore(false, counter)
    set_git_dir("/test/.git")

    local config = require("lensline.config")
    config.options.limits = { exclude_gitignored = true }

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/test/src/main.lua")

    local skip
    limits.should_skip_async(bufnr, function(s) skip = s end)

    eq(false, skip)
    eq(1, counter.count)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("caches gitignore results across calls for the same filepath", function()
    local limits = require("lensline.limits")
    limits.clear_cache()
    local counter = { count = 0 }
    stub_check_ignore(true, counter)
    set_git_dir("/test/.git")

    local config = require("lensline.config")
    config.options.limits = { exclude_gitignored = true }

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/test/.gen/output.txt")

    for _ = 1, 3 do
      limits.should_skip_async(bufnr, function(_) end)
    end

    eq(1, counter.count)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("deduplicates concurrent in-flight checks for the same filepath", function()
    local limits = require("lensline.limits")
    limits.clear_cache()
    set_git_dir("/test/.git")

    -- Use a manual stub that doesn't call back immediately; we drive it.
    local spawn_count = 0
    local resolve
    local blame_cache = require("lensline.blame_cache")
    blame_cache.spawn_command_async = function(cmd, callback)
      spawn_count = spawn_count + 1
      resolve = function() callback(nil, {}) end
    end

    local config = require("lensline.config")
    config.options.limits = { exclude_gitignored = true }

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/test/.gen/output.txt")

    local results = {}
    for i = 1, 3 do
      limits.should_skip_async(bufnr, function(s)
        results[i] = s
      end)
    end

    eq(1, spawn_count)
    eq(0, #results) -- nothing has resolved yet
    assert(resolve, "spawn should have started")
    resolve()
    eq(3, #vim.tbl_keys(results))
    eq(true, results[1])
    eq(true, results[2])
    eq(true, results[3])

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("clear_cache forces a fresh git check on the next call", function()
    local limits = require("lensline.limits")
    limits.clear_cache()
    local counter = { count = 0 }
    stub_check_ignore(false, counter)
    set_git_dir("/test/.git")

    local config = require("lensline.config")
    config.options.limits = { exclude_gitignored = true }

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/test/src/main.lua")

    limits.should_skip_async(bufnr, function(_) end)
    eq(1, counter.count)

    -- Cached: no new spawn.
    limits.should_skip_async(bufnr, function(_) end)
    eq(1, counter.count)

    limits.clear_cache()

    -- After clearing, the next call must hit git again.
    limits.should_skip_async(bufnr, function(_) end)
    eq(2, counter.count)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("checks each distinct filepath at most once across many calls", function()
    local limits = require("lensline.limits")
    limits.clear_cache()
    local checked = {}
    local blame_cache = require("lensline.blame_cache")
    blame_cache.spawn_command_async = function(cmd, callback)
      if type(cmd) == "table" and cmd[1] == "git" and cmd[4] == "check-ignore" then
        table.insert(checked, cmd[6])
      end
      callback({ code = 1, message = "" }, nil)
    end
    set_git_dir("/test/.git")

    local config = require("lensline.config")
    config.options.limits = { exclude_gitignored = true }

    local buffers = {}
    for i = 1, 5 do
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, "/test/src/file_" .. i .. ".lua")
      table.insert(buffers, bufnr)
      limits.should_skip_async(bufnr, function(_) end)
      -- Repeat call for the same buffer must not add another check.
      limits.should_skip_async(bufnr, function(_) end)
    end

    eq(5, #checked)
    for _, bufnr in ipairs(buffers) do
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("treats files outside a git repo as not gitignored without spawning", function()
    local limits = require("lensline.limits")
    limits.clear_cache()
    local counter = { count = 0 }
    stub_check_ignore(true, counter)
    vim.fn.finddir = function(pattern)
      if pattern == ".git" then return "" end
      return original_finddir(pattern)
    end

    local config = require("lensline.config")
    config.options.limits = { exclude_gitignored = true }

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/tmp/loose_file.lua")

    local skip
    limits.should_skip_async(bufnr, function(s) skip = s end)

    eq(false, skip)
    eq(0, counter.count)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
