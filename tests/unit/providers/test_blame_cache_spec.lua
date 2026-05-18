local eq = assert.are.same
local test_utils = require("tests.test_utils")
local await = test_utils.await

local function with_patch(tbl, key, new_impl, fn)
  local orig = tbl[key]
  tbl[key] = new_impl
  local ok, err = pcall(fn)
  tbl[key] = orig
  if not ok then
    error(err)
  end
end

local function blame_block(final_line, author, time)
  return {
    string.format("%s %d %d 1", "deadbeef", final_line, final_line),
    "author " .. author,
    "author-mail <" .. author:lower():gsub("%s+", "_") .. "@example.com>",
    "author-time " .. time,
    "author-tz +0000",
  }
end

describe("blame_cache core behavior", function()
  local blame_cache = require("lensline.blame_cache")
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
    local spawn_calls = {}

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

    local function spawn_stub(cmd, callback)
      table.insert(spawn_calls, cmd)
      local args = { unpack(cmd, 2) }
      local is_rev_parse = false
      local is_blame = false
      for _, arg in ipairs(args) do
        if arg == "rev-parse" then
          is_rev_parse = true
        end
        if arg == "blame" then
          is_blame = true
        end
      end
      if is_rev_parse then
        if rev_parse_fail then
          callback({ message = "not a git repo" }, nil)
        else
          callback(nil, { "/repo" })
        end
      elseif is_blame then
        if blame_fail then
          callback({ message = "blame failed" }, nil)
        else
          callback(nil, blame_lines)
        end
      else
        callback({ message = "unknown command" }, nil)
      end
    end

    return spawn_calls, function(run)
      with_patch(vim.loop, "fs_stat", fs_stat_stub, function()
        with_patch(limits, "get_truncated_end_line", limits_truncated_end_line, function()
          with_patch(blame_cache, "spawn_command_async", spawn_stub, function()
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
    local spawn_calls, harness = stub_environment({
      blame_lines = vim.tbl_flatten({
        blame_block(1, "Alice", 1000),
        blame_block(2, "Alice", 1001),
      }),
    })

    harness(function()
      local first = await(function(cb)
        blame_cache.get_blame_data(f1, 0, cb)
      end)
      eq("Alice", first[1].author)
      local stats1 = blame_cache.get_stats()
      eq(1, stats1.misses)
      eq(0, stats1.hits)

      -- Second call should be hit (no second blame invocation)
      local second = await(function(cb)
        blame_cache.get_blame_data(f1, 0, cb)
      end)
      eq(first, second)
      local stats2 = blame_cache.get_stats()
      eq(1, stats2.misses)
      eq(1, stats2.hits)

      -- Ensure only one blame command (rev-parse + blame once)
      local blame_invocations = 0
      for _, cmd in ipairs(spawn_calls) do
        for _, arg in ipairs(cmd) do
          if arg == "blame" then
            blame_invocations = blame_invocations + 1
            break
          end
        end
      end
      eq(1, blame_invocations)
    end)
  end)

  it("LRU eviction removes oldest when exceeding max_files", function()
    reset()
    blame_cache.configure({ max_files = 2 })
    local files = { make_file("f1"), make_file("f2"), make_file("f3") }
    local base_lines = vim.tbl_flatten({ blame_block(1, "A", 100), blame_block(2, "B", 101) })
    local _, harness = stub_environment({ blame_lines = base_lines })

    harness(function()
      local data1 = await(function(cb)
        blame_cache.get_blame_data(files[1], 0, cb)
      end)
      eq("A", data1[1].author)
      local data2 = await(function(cb)
        blame_cache.get_blame_data(files[2], 0, cb)
      end)
      eq("A", data2[1].author)
      local data1again = await(function(cb)
        blame_cache.get_blame_data(files[1], 0, cb)
      end)
      eq("A", data1again[1].author)
      local data3 = await(function(cb)
        blame_cache.get_blame_data(files[3], 0, cb)
      end)
      eq("A", data3[1].author)
      local stats = blame_cache.get_stats()
      eq(3, stats.misses)
      local data2again = await(function(cb)
        blame_cache.get_blame_data(files[2], 0, cb)
      end)
      eq("A", data2again[1].author)
      local stats2 = blame_cache.get_stats()
      eq(4, stats2.misses)
    end)
  end)

  it("non-git directory returns nil (rev-parse failure simulated with empty root)", function()
    reset()
    local f1 = make_file("nogit")
    local _, harness = stub_environment({
      rev_parse_fail = true,
      blame_lines = {},
    })
    harness(function()
      local data = await(function(cb)
        blame_cache.get_blame_data(f1, 0, cb)
      end)
      eq(nil, data)
    end)
  end)

  -- NOTE: git blame failure path depends on vim.v.shell_error mutation,
  -- which is read-only in this headless test environment; failure scenario skipped.

  it("truncation respects limits.get_truncated_end_line", function()
    reset()
    local f1 = make_file("truncate")
    local spawn_calls, harness = stub_environment({
      truncate = 1,
      blame_lines = blame_block(1, "Alice", 1111),
    })
    harness(function()
      local data = await(function(cb)
        blame_cache.get_blame_data(f1, 0, cb)
      end)
      eq("Alice", data[1].author)
      local seen_range = false
      for _, cmd in ipairs(spawn_calls) do
        local has_blame = false
        for _, arg in ipairs(cmd) do
          if arg == "blame" then
            has_blame = true
            break
          end
        end
        if has_blame then
          for i, v in ipairs(cmd) do
            if v == "-L" and cmd[i + 1] == "1,1" then
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
    local lines = vim.tbl_flatten({
      blame_block(1, "OldAuthor", 100),
      blame_block(2, "NewAuthor", 200),
      blame_block(3, "Middle", 150),
    })
    local _, harness = stub_environment({ blame_lines = lines })
    harness(function()
      local data = await(function(cb)
        blame_cache.get_blame_data(f1, 0, cb)
      end)
      eq("NewAuthor", data[2].author)
      -- get_function_author should return NewAuthor for range lines 1..3
      local info = await(function(cb)
        blame_cache.get_function_author(f1, 0, { line = 1, end_line = 3 }, cb)
      end)
      eq("NewAuthor", info.author)
      eq(200, info.time)
    end)
  end)

  it("uncommitted author string maps to 'uncommitted'", function()
    reset()
    local f1 = make_file("uncommitted")
    local lines = vim.tbl_flatten({
      blame_block(1, "Not Committed Yet", 1000),
    })
    local _, harness = stub_environment({ blame_lines = lines })
    harness(function()
      local info = await(function(cb)
        blame_cache.get_function_author(f1, 0, { line = 1, end_line = 1 }, cb)
      end)
      eq({ author = "uncommitted", time = nil }, info)
    end)
  end)

  it("only one git blame runs per file when multiple callers request same file", function()
    reset()
    local f1 = make_file("concurrent")
    local blame_invoked = 0
    local resolve_blame
    local blame_lines = vim.tbl_flatten({
      blame_block(1, "Alice", 1000),
      blame_block(2, "Bob", 1001),
    })
    local function delaying_spawn(cmd, callback)
      local args = { unpack(cmd, 2) }
      local is_rev_parse, is_blame = false, false
      for _, arg in ipairs(args) do
        if arg == "rev-parse" then is_rev_parse = true end
        if arg == "blame" then is_blame = true end
      end
      if is_rev_parse then
        callback(nil, { "/repo" })
        return
      end
      if is_blame then
        blame_invoked = blame_invoked + 1
        resolve_blame = function()
          callback(nil, blame_lines)
        end
        return
      end
      callback({ message = "unknown" }, nil)
    end

    local _, harness = stub_environment({ blame_lines = blame_lines })
    harness(function()
      with_patch(blame_cache, "spawn_command_async", delaying_spawn, function()
        local results = {}
        local done = 0
        for i = 1, 3 do
          blame_cache.get_blame_data(f1, 0, function(data)
            results[i] = data
            done = done + 1
          end)
        end
        eq(0, done)
        assert(resolve_blame, "blame should have been started")
        resolve_blame()
        local wait_start = vim.loop.hrtime()
        while done < 3 do
          vim.loop.run("nowait")
          vim.wait(10, function()
            return done >= 3
          end, 100)
          if (vim.loop.hrtime() - wait_start) / 1000000 > 2000 then
            error("timeout waiting for 3 callbacks")
          end
        end
        eq(1, blame_invoked)
        eq("Alice", results[1][1].author)
        eq("Alice", results[2][1].author)
        eq("Alice", results[3][1].author)
      end)
    end)
  end)

  it("spawn timeout kills hung process and returns timeout error", function()
    local original_timeout = blame_cache.spawn_timeout_ms
    blame_cache.spawn_timeout_ms = 100

    local err_received, data_received
    local done = false
    blame_cache.spawn_command_async({ "sleep", "60" }, function(err, data)
      err_received = err
      data_received = data
      done = true
    end)

    local wait_start = vim.loop.hrtime()
    while not done do
      vim.loop.run("nowait")
      vim.wait(50, function() return done end, 25)
      if (vim.loop.hrtime() - wait_start) / 1000000 > 5000 then
        blame_cache.spawn_timeout_ms = original_timeout
        error("timeout waiting for spawn callback after kill")
      end
    end

    blame_cache.spawn_timeout_ms = original_timeout

    assert(err_received ~= nil, "expected error from timed-out command")
    assert(
      tostring(err_received.message or ""):match("timed out"),
      "expected 'timed out' in error message, got: " .. tostring(err_received.message)
    )
    eq(nil, data_received)
  end)

  it("clear_cache resets stats", function()
    reset()
    local f1 = make_file("reset_stats")
    local _, harness = stub_environment({
      blame_lines = blame_block(1, "Alice", 3210),
    })
    harness(function()
      await(function(cb)
        blame_cache.get_blame_data(f1, 0, cb)
      end)
      local s1 = blame_cache.get_stats()
      eq(1, s1.misses)
      blame_cache.clear_cache()
      local s2 = blame_cache.get_stats()
      eq(0, s2.misses)
      eq(0, s2.hits)
    end)
  end)
end)