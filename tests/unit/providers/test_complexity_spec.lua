local eq = assert.are.same

-- Minimal module stub helper (full replacement)
local function with_stub(mod, stub, fn)
  local orig = package.loaded[mod]
  package.loaded[mod] = stub
  local ok, err = pcall(fn)
  package.loaded[mod] = orig
  if not ok then error(err) end
end

describe("providers.complexity.estimate_complexity", function()
  local provider = require("lensline.providers.complexity") -- loads file & defines global estimate_complexity
  it("S: trivial function yields Small", function()
    local label, score = estimate_complexity({
      "local function foo()", "return 1", "end"
    }, "lua")
    eq("S", label)
    assert.is_true(score <= 5)
  end)

  it("M: if / elseif / else structure yields Medium", function()
    local lines = {
      "local function foo(x)",
      "if x == 1 then",
      "  return 1",
      "elseif x == 2 then",
      "  return 2",
      "else",
      "  return 3",
      "end",
      "end",
    }
    local label, score = estimate_complexity(lines, "lua")
    eq("M", label)
    assert.is_true(score > 5 and score <= 12)
  end)

  it("L: multiple branches + loop", function()
    local lines = {
      "local function foo(t)",
      "for i,v in ipairs(t) do",
      "  if v > 10 then",
      "    if v % 2 == 0 then",
      "      t[i] = v / 2",
      "    else",
      "      t[i] = v * 2",
      "    end",
      "  end",
      "end",
      "return t",
      "end",
    }
    local label, score = estimate_complexity(lines, "lua")
    eq("L", label)
    assert.is_true(score > 12 and score <= 20)
  end)

  it("XL: heavy branching + loops + nesting", function()
    local lines = {
      "local function big(a,b,c)",
      "for i=1,10 do",
      "  if a then",
      "    for j=1,5 do",
      "      if b and c or (a and b) then",
      "        if j % 2 == 0 then",
      "          a = a + 1",
      "        else",
      "          b = b + 2",
      "        end",
      "      end",
      "    end",
      "  elseif b then",
      "    while c do",
      "      if a or b then c = false end",
      "    end",
      "  else",
      "    a = 0",
      "  end",
      "end",
      "return a + (b or 0)",
      "end",
    }
    local label, score = estimate_complexity(lines, "lua")
    eq("XL", label)
    assert.is_true(score > 20)
  end)

  it("conditionals: logical operators counted", function()
    local lines = {
      "local function foo(a,b,c)",
      "if a and b or c then return true end",
      "end",
    }
    local label, score = estimate_complexity(lines, "lua")
    -- One 'if' branch (3), two logical ops (and/or => 2*2 =4), LOC(3)*0.1=0.3 => 7.3 => Medium
    eq("M", label)
  end)

  it("comments ignored in scoring", function()
    local lines = {
      "local function foo()", "-- if while for repeat",
      "return 0", "end",
    }
    local label, _ = estimate_complexity(lines, "lua")
    eq("S", label)
  end)

  it("indentation increases score (affects label boundary)", function()
    local shallow = {
      "local function foo(x)",
      "if x then return 1 end",
      "end",
    }
    local deep = {
      "local function foo(x)",
      "if x then",
      "        if x > 1 then",
      "                if x > 2 then",
      "                        return 3",
      "                end",
      "        end",
      "end",
      "end",
    }
    local _, score_shallow = estimate_complexity(shallow, "lua")
    local _, score_deep = estimate_complexity(deep, "lua")
    assert.is_true(score_deep > score_shallow)
  end)

  it("language weight adjusts score (python weight 0.9 reduces)", function()
    local lines = {
      "def foo(x):",
      "    if x and x > 1:",
      "        return x",
    }
    local _, score_default = estimate_complexity(lines, "lua") -- weight 1.0
    local _, score_python = estimate_complexity(lines, "python") -- weight 0.9
    assert.is_true(score_python <= score_default)
  end)
  it("rust: match + if yields Medium", function()
    local lines = {
      "fn foo(x: i32) -> i32 {",
      "    if x &gt; 10 {",
      "        return x - 1;",
      "    }",
      "    match x {",
      "        0 =&gt; 0,",
      "        1 =&gt; 1,",
      "        _ =&gt; x,",
      "    }",
      "}",
    }
    local label = (estimate_complexity(lines, "rust"))
    eq("M", label)
  end)

  it("csharp: loop + nested if + try/catch escalates to XL", function()
    local lines = {
      "int Foo(int x) {",
      "    if (x &gt; 0 &amp;&amp; x &lt; 10) {",
      "        for (int i = 0; i &lt; x; i++) {",
      "            if (i % 2 == 0) {",
      "                x += i;",
      "            }",
      "        }",
      "    }",
      "    try {",
      "        DoThing();",
      "    } catch (Exception e) {",
      "        throw;",
      "    }",
      "    return x;",
      "}",
    }
    local label = (estimate_complexity(lines, "cs"))
    -- Expect high complexity due to multiple branches, loop, try/catch
    eq("XL", label)
  end)
  it("ordering regression: S < M < L < XL sequence holds", function()
    local cases = {
      {
        lines = { "local function a()", "return 1", "end" },           -- S
      },
      {
        lines = {
          "local function b(x)",
          "if x then return 1 end",
          "end",
        },                                                             -- expect >= M
      },
      {
        lines = {
          "local function c(t)",
          "for i,v in ipairs(t) do",
          "  if v > 1 then",
          "    v = v + 1",
          "  end",
          "end",
          "end",
        },                                                             -- expect >= L
      },
      {
        lines = {
          "local function d(a,b,c)",
          "for i=1,5 do",
          "  if a then",
          "    while b do",
          "      if c or a and b then b = false end",
          "    end",
          "  end",
          "end",
          "end",
        },                                                             -- expect XL
      },
    }
    local numeric = { S = 1, M = 2, L = 3, XL = 4 }
    local last = 0
    for _, c in ipairs(cases) do
      local label = (estimate_complexity(c.lines, "lua"))
      assert.is_true(numeric[label] >= last, "non-monotonic ordering at label " .. label)
      last = numeric[label]
    end
  end)

  it("deep indentation without control flow stays Small", function()
    local lines = {
      "local function indent_only()",
      "          local x = 1",
      "                local y = x + 2",
      "                        local z = y + 3",
      "                              return z",
      "end",
    }
    local label = (estimate_complexity(lines, "lua"))
    eq("S", label)
  end)

  it("pure boolean assignment (no if) does not count conditionals", function()
    local lines = {
      "local function flags(a,b,c)",
      "local ok = a and b or c and (a or b)",
      "return ok",
      "end",
    }
    local label = (estimate_complexity(lines, "lua"))
    eq("S", label)
  end)
  it("csharp alias filetype yields same label as cs", function()
    local lines = {
      "int Foo(int x) {",
      "    if (x > 0) {",
      "        return x;",
      "    }",
      "    return x;",
      "}",
    }
    local label_cs = (estimate_complexity(lines, "cs"))
    local label_alias = (estimate_complexity(lines, "csharp"))
    eq(label_cs, label_alias)
  end)
  it("csharp: single if with deep indentation normalizes to Medium", function()
    local lines = {
      'public void GetMarried() {',
      '    Console.WriteLine("start");',
      '    if (Age < 18) {',
      '                Console.WriteLine("Too young");',
      '    } else {',
      '                Console.WriteLine("Congrats");',
      '    }',
      '    GrowOld();',
      '    GrowOld();',
      '}',
    }
    local label = (estimate_complexity(lines, "cs"))
    eq("M", label)
  end)
end)

describe("providers.complexity.handler", function()
  it("returns nil for unsaved buffer (empty name)", function()
    local provider = require("lensline.providers.complexity")
    local bufnr = vim.api.nvim_create_buf(false, true)
    local called
    with_stub("lensline.utils", {
      is_valid_buffer = function() return true end,
      get_function_lines = function() return { "local function foo()", "return 1", "end" } end,
    }, function()
      with_stub("lensline.debug", { log_context = function() end }, function()
        provider.handler(bufnr, { line = 1, name = "foo" }, {}, function(res) called = res end)
      end)
    end)
    eq(nil, called) -- unsaved buffer => nil
    if vim.api.nvim_buf_is_valid(bufnr) then vim.api.nvim_buf_delete(bufnr, { force = true }) end
  end)

  it("filters below min_level", function()
    local provider = require("lensline.providers.complexity")
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/tmp/complexity_filter.lua")
    local out
    with_stub("lensline.utils", {
      is_valid_buffer = function() return true end,
      get_function_lines = function() return { "local function foo()", "return 1", "end" } end, -- Small
    }, function()
      with_stub("lensline.debug", { log_context = function() end }, function()
        provider.handler(bufnr, { line = 1, name = "foo" }, { min_level = "L" }, function(res) out = res end)
      end)
    end)
    eq(nil, out)
    if vim.api.nvim_buf_is_valid(bufnr) then vim.api.nvim_buf_delete(bufnr, { force = true }) end
  end)

  it("returns lens when meets min_level", function()
    local provider = require("lensline.providers.complexity")
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/tmp/complexity_ok.lua")
    local out
    -- Provide lines that yield L (>= required)
    local lines = {
      "local function foo(t)",
      "for i,v in ipairs(t) do",
      "  if v > 10 then",
      "    if v % 2 == 0 then",
      "      v = v / 2",
      "    else",
      "      v = v * 2",
      "    end",
      "  end",
      "end",
      "return t",
      "end",
    }
    with_stub("lensline.utils", {
      is_valid_buffer = function() return true end,
      get_function_lines = function() return lines end,
    }, function()
      with_stub("lensline.debug", { log_context = function() end }, function()
        provider.handler(bufnr, { line = 42, name = "foo" }, { min_level = "L" }, function(res) out = res end)
      end)
    end)
    eq({ line = 42, text = "Cx: L" }, out)
    if vim.api.nvim_buf_is_valid(bufnr) then vim.api.nvim_buf_delete(bufnr, { force = true }) end
  end)
end)