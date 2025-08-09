local eq = assert.are.same

-- Helpers
local function with_patch(tbl, key, new_impl, fn)
  local orig = tbl[key]
  tbl[key] = new_impl
  local ok, err = pcall(fn)
  tbl[key] = orig
  if not ok then error(err) end
end

-- (with_patches helper removed as unused)

-- Fabricate blame porcelain block for a single final line
local function blame_block(final_line, author, time)
  return {
    string.format("%s %d %d 1", "deadbeef", final_line, final_line),
    "author " .. author,
    "author-mail <" .. author:lower():gsub("%s+","_") .. "@example.com>",
    "author-time " .. time,
    "author-tz +0000",
  }
end

describe("blame_cache core behavior", function()
  local blame_cache = require("lensline.blame_cache")

  -- Provide deterministic time
  local fake_mtime = { sec = 123456 }

  local function reset()
    blame_cache.clear_cache()
  end

  local tmp_root = (vim.loop.os_tmpdir() or "/tmp") .. "/lensline_blame_tests"
  if vim.fn.isdirectory(tmp_root) == 0 then
    pcall(vim.fn.mkdir, tmp_root, "p")
  end

  local function make_file(name)
    local path = string.format("%s/%s.lua", tmp_root, name)
    local fh = assert(io.open(path, "w"))
    fh:write("-- test file " .. name .. "\nprint('x')\n")
    fh:close()
    return path
  end

  local function stub_environment(opts)
    opts = opts or {}
    local fs_mtime = opts.mtime or fake_mtime.sec
    local limits_truncate = opts.truncate -- nil means no truncation
    local blame_fail = opts.blame_fail
    local rev_parse_fail = opts.rev_parse_fail
    local blame_lines = opts.blame_lines or {}
    local system_calls = {}

    -- Patch vim.loop.fs_stat
    local function fs_stat_stub(fname)
      if opts.fs_stat_nil then return nil end
      return { mtime = { sec = fs_mtime } }
    end

    -- Patch limits
    local limits = require("lensline.limits")

    local function limits_truncated_end_line(_, requested)
      if limits_truncate then
        return math.min(requested, limits_truncate)
      end
      return requested
    end

    local function systemlist_stub(cmd_tbl)
      -- Capture call
      table.insert(system_calls, cmd_tbl)
      -- Identify call type (index 4 = subcommand: rev-parse / blame)
      local sub = cmd_tbl[4]
      if sub == "rev-parse" then
        -- Simulate non-git repo by returning empty root when requested
        if rev_parse_fail then
          return { "" } -- empty string triggers nil/empty root path branch
        end
        return { "/repo" }
      elseif sub == "blame" then
        -- Cannot modify vim.v.shell_error (readonly in this environment), so only success path is testable
        if blame_fail then
          -- Simulate blame failure by returning an empty table; code only checks shell_error (unmodifiable) so we skip this scenario
          return {}
        end
        return blame_lines
      else
        return {}
      end
    end

    return system_calls, function(run)
      with_patch(vim.loop, "fs_stat", fs_stat_stub, function()
        with_patch(limits, "get_truncated_end_line", limits_truncated_end_line, function()
          with_patch(vim.fn, "systemlist", systemlist_stub, function()
            run()
          end)
        end)
      end)
    end
  end

  -- No explicit deletion of temp files; rely on OS tmp cleanup policy.

  it("cache miss then hit (single file) increments stats appropriately", function()
    reset()
    local f1 = make_file("file_a")
    local system_calls, harness = stub_environment{
      blame_lines = vim.tbl_flatten{
        blame_block(1, "Alice", 1000),
        blame_block(2, "Alice", 1001),
      },
    }

    harness(function()
      local first = blame_cache.get_blame_data(f1, 0)
      eq("Alice", first[1].author)
      local stats1 = blame_cache.get_stats()
      eq(1, stats1.misses)
      eq(0, stats1.hits)

      -- Second call should be hit (no second blame invocation)
      local second = blame_cache.get_blame_data(f1, 0)
      eq(first, second)
      local stats2 = blame_cache.get_stats()
      eq(1, stats2.misses)
      eq(1, stats2.hits)

      -- Ensure only one blame command (rev-parse + blame once)
      local blame_invocations = 0
      for _, cmd in ipairs(system_calls) do
        if cmd[4] == "blame" then blame_invocations = blame_invocations + 1 end
      end
      eq(1, blame_invocations)
    end)
  end)

  it("LRU eviction removes oldest when exceeding max_files", function()
    reset()
    blame_cache.configure({ max_files = 2 })
    local files = { make_file("f1"), make_file("f2"), make_file("f3") }

    local base_lines = vim.tbl_flatten{ blame_block(1, "A", 100), blame_block(2, "B", 101) }

    local system_calls, harness = stub_environment{ blame_lines = base_lines }

    harness(function()
      -- Load first two (misses)
      eq("A", blame_cache.get_blame_data(files[1], 0)[1].author)
      eq("A", blame_cache.get_blame_data(files[2], 0)[1].author)
      -- Access first again to make second oldest
      eq("A", blame_cache.get_blame_data(files[1], 0)[1].author)
      -- Load third -> should evict file 2
      eq("A", blame_cache.get_blame_data(files[3], 0)[1].author)
      local stats = blame_cache.get_stats()
      eq(3, stats.misses) -- each initial load is a miss
      -- Access file 2 again -> miss after eviction
      eq("A", blame_cache.get_blame_data(files[2], 0)[1].author)
      local stats2 = blame_cache.get_stats()
      eq(4, stats2.misses)
    end)
  end)

  it("non-git directory returns nil (rev-parse failure simulated with empty root)", function()
    reset()
    local f1 = make_file("nogit")
    local _, harness = stub_environment{
      rev_parse_fail = true,
      blame_lines = {},
    }
    harness(function()
      local data = blame_cache.get_blame_data(f1, 0)
      eq(nil, data)
    end)
  end)

  -- NOTE: git blame failure path depends on vim.v.shell_error mutation,
  -- which is read-only in this headless test environment; failure scenario skipped.

  it("truncation respects limits.get_truncated_end_line", function()
    reset()
    local f1 = make_file("truncate")
    local system_calls, harness = stub_environment{
      truncate = 1, -- force truncation to line 1
      blame_lines = blame_block(1, "Alice", 1111),
    }
    harness(function()
      local data = blame_cache.get_blame_data(f1, 0)
      eq("Alice", data[1].author)
      -- Ensure blame command used -L 1,1
      local seen_range = false
      for _, cmd in ipairs(system_calls) do
        if cmd[4] == "blame" then
          for i,v in ipairs(cmd) do
            if v == "-L" and cmd[i+1] == "1,1" then
              seen_range = true
            end
          end
        end
      end
      eq(true, seen_range)
    end)
  end)

  it("mixed authors selects most recent timestamp", function()
    reset()
    local f1 = make_file("mixed")
    local lines = vim.tbl_flatten{
      blame_block(1, "OldAuthor", 100),
      blame_block(2, "NewAuthor", 200),
      blame_block(3, "Middle", 150),
    }
    local _, harness = stub_environment{ blame_lines = lines }
    harness(function()
      local data = blame_cache.get_blame_data(f1, 0)
      eq("NewAuthor", data[2].author)
      -- get_function_author should return NewAuthor for range lines 1..3
      local info = blame_cache.get_function_author(f1, 0, { line = 1, end_line = 3 })
      eq("NewAuthor", info.author)
      eq(200, info.time)
    end)
  end)

  it("uncommitted author string maps to 'uncommitted'", function()
    reset()
    local f1 = make_file("uncommitted")
    local lines = vim.tbl_flatten{
      blame_block(1, "Not Committed Yet", 1000),
    }
    local _, harness = stub_environment{ blame_lines = lines }
    harness(function()
      local info = blame_cache.get_function_author(f1, 0, { line = 1, end_line = 1 })
      eq({ author = "uncommitted", time = 1000 }, info)
    end)
  end)

  it("clear_cache resets stats", function()
    reset()
    local f1 = make_file("reset_stats")
    local _, harness = stub_environment{
      blame_lines = blame_block(1, "Alice", 3210),
    }
    harness(function()
      blame_cache.get_blame_data(f1, 0)
      local s1 = blame_cache.get_stats()
      eq(1, s1.misses)
      blame_cache.clear_cache()
      local s2 = blame_cache.get_stats()
      eq(0, s2.misses)
      eq(0, s2.hits)
    end)
  end)
end)