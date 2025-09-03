-- tests/unit/test_presenter_spec.lua
-- unit tests for lensline.presenter (data combination and extmark options)

local eq = assert.are.same

-- minimal debug stub to avoid noise
package.loaded["lensline.debug"] = { log_context = function() end }

describe("presenter", function()
  local function reset_modules()
    for name,_ in pairs(package.loaded) do
      if name:match("^lensline") and name ~= "lensline.debug" then 
        package.loaded[name] = nil 
      end
    end
  end

  before_each(function()
    reset_modules()
  end)

  after_each(function()
    reset_modules()
  end)

  describe("combine_provider_data", function()
    -- table-driven tests for edge cases
    for _, tc in ipairs({
      { name = "nil data", input = nil, providers = {}, expected = {} },
      { name = "empty data", input = {}, providers = {}, expected = {} },
    }) do
      it(("handles %s"):format(tc.name), function()
        local presenter = require("lensline.presenter")
        local result = presenter.combine_provider_data(tc.input, tc.providers)
        eq(tc.expected, result)
      end)
    end

    it("preserves provider order from config", function()
      local presenter = require("lensline.presenter")
      local provider_lens_data = {
        provider_b = {
          { line = 1, text = "B1" },
          { line = 2, text = "B2" }
        },
        provider_a = {
          { line = 1, text = "A1" },
          { line = 2, text = "A2" }
        }
      }
      
      local provider_configs = {
        { name = "provider_a", enabled = true },
        { name = "provider_b", enabled = true }
      }
      
      local result = presenter.combine_provider_data(provider_lens_data, provider_configs)
      
      eq({
        [1] = { "A1", "B1" },
        [2] = { "A2", "B2" }
      }, result)
    end)

    it("skips disabled providers", function()
      local presenter = require("lensline.presenter")
      local provider_lens_data = {
        enabled_provider = {
          { line = 1, text = "enabled" }
        },
        disabled_provider = {
          { line = 1, text = "disabled" }
        }
      }
      
      local provider_configs = {
        { name = "enabled_provider", enabled = true },
        { name = "disabled_provider", enabled = false }
      }
      
      local result = presenter.combine_provider_data(provider_lens_data, provider_configs)
      
      eq({
        [1] = { "enabled" }
      }, result)
    end)

    it("handles sparse arrays", function()
      local presenter = require("lensline.presenter")
      local provider_lens_data = {
        sparse_provider = {
          [1] = { line = 1, text = "first" },
          [3] = { line = 1, text = "third" },
          [5] = { line = 1, text = "fifth" }
        }
      }
      
      local provider_configs = {
        { name = "sparse_provider", enabled = true }
      }
      
      local result = presenter.combine_provider_data(provider_lens_data, provider_configs)
      
      eq({
        [1] = { "first", "third", "fifth" }
      }, result)
    end)

    it("filters invalid items", function()
      local presenter = require("lensline.presenter")
      local provider_lens_data = {
        mixed_provider = {
          { line = 1, text = "valid" },
          { line = 1 }, -- missing text
          { text = "missing_line" }, -- missing line
          { line = 1, text = "also_valid" },
          nil, -- nil item
          { line = 1, text = "" } -- empty text
        }
      }
      
      local provider_configs = {
        { name = "mixed_provider", enabled = true }
      }
      
      local result = presenter.combine_provider_data(provider_lens_data, provider_configs)
      
      eq({
        [1] = { "valid", "also_valid" }
      }, result)
    end)

    it("groups texts by line", function()
      local presenter = require("lensline.presenter")
      local provider_lens_data = {
        multi_provider = {
          { line = 1, text = "line1_first" },
          { line = 2, text = "line2_first" },
          { line = 1, text = "line1_second" },
          { line = 3, text = "line3_only" }
        }
      }
      
      local provider_configs = {
        { name = "multi_provider", enabled = true }
      }
      
      local result = presenter.combine_provider_data(provider_lens_data, provider_configs)
      
      eq({
        [1] = { "line1_first", "line1_second" },
        [2] = { "line2_first" },
        [3] = { "line3_only" }
      }, result)
    end)
  end)

  describe("compute_extmark_opts", function()
    describe("above placement", function()
      it("creates basic virt_lines", function()
        local presenter = require("lensline.presenter")
        local args = { texts = { "test text" } }
        local result = presenter.compute_extmark_opts(args)
        
        eq({
          virt_lines = { { { "test text", "Comment" } } },
          virt_lines_above = true,
          ephemeral = false
        }, result)
      end)

      it("handles custom separator and highlight", function()
        local presenter = require("lensline.presenter")
        local args = {
          placement = "above",
          texts = { "text1", "text2" },
          separator = " | ",
          highlight = "Error"
        }
        
        local result = presenter.compute_extmark_opts(args)
        
        eq({
          virt_lines = { { { "text1 | text2", "Error" } } },
          virt_lines_above = true,
          ephemeral = false
        }, result)
      end)

      it("adds prefix", function()
        local presenter = require("lensline.presenter")
        local args = {
          texts = { "test" },
          prefix = ">> ",
          highlight = "Warning"
        }
        
        local result = presenter.compute_extmark_opts(args)
        
        eq({
          virt_lines = { { { ">> test", "Warning" } } },
          virt_lines_above = true,
          ephemeral = false
        }, result)
      end)

      it("preserves indentation", function()
        local presenter = require("lensline.presenter")
        local args = {
          texts = { "test" },
          line_content = "    function foo()",
          prefix = "| "
        }
        
        local result = presenter.compute_extmark_opts(args)
        
        eq({
          virt_lines = { {
            { "    ", "Comment" },
            { "| test", "Comment" }
          } },
          virt_lines_above = true,
          ephemeral = false
        }, result)
      end)

      it("handles mixed indentation", function()
        local presenter = require("lensline.presenter")
        local args = {
          texts = { "test" },
          line_content = "\t  function foo()"
        }
        
        local result = presenter.compute_extmark_opts(args)
        
        eq({
          virt_lines = { { 
            { "\t  ", "Comment" },
            { "test", "Comment" }
          } },
          virt_lines_above = true,
          ephemeral = false
        }, result)
      end)

      it("sets ephemeral flag", function()
        local presenter = require("lensline.presenter")
        local args = {
          texts = { "test" },
          ephemeral = true
        }
        
        local result = presenter.compute_extmark_opts(args)
        
        assert.is_true(result.ephemeral)
      end)
    end)

    describe("inline placement", function()
      it("creates virt_text at eol", function()
        local presenter = require("lensline.presenter")
        local args = {
          placement = "inline",
          texts = { "test" }
        }
        
        local result = presenter.compute_extmark_opts(args)
        
        eq({
          virt_text = { { " test", "Comment" } },
          virt_text_pos = "eol",
          hl_mode = "combine",
          ephemeral = false
        }, result)
      end)

      it("adds prefix to inline text", function()
        local presenter = require("lensline.presenter")
        local args = {
          placement = "inline",
          texts = { "test" },
          prefix = ">> "
        }
        
        local result = presenter.compute_extmark_opts(args)
        
        eq({
          virt_text = { { " >> test", "Comment" } },
          virt_text_pos = "eol",
          hl_mode = "combine",
          ephemeral = false
        }, result)
      end)

      it("combines texts with separator", function()
        local presenter = require("lensline.presenter")
        local args = {
          placement = "inline",
          texts = { "first", "second" },
          separator = " • "
        }
        
        local result = presenter.compute_extmark_opts(args)
        
        eq({
          virt_text = { { " first • second", "Comment" } },
          virt_text_pos = "eol",
          hl_mode = "combine",
          ephemeral = false
        }, result)
      end)

      it("ignores line_content for inline", function()
        local presenter = require("lensline.presenter")
        local args = {
          placement = "inline",
          texts = { "test" },
          line_content = "    indented line"
        }
        
        local result = presenter.compute_extmark_opts(args)
        
        eq({
          virt_text = { { " test", "Comment" } },
          virt_text_pos = "eol",
          hl_mode = "combine",
          ephemeral = false
        }, result)
      end)
    end)

    describe("edge cases", function()
      -- table-driven tests for edge cases
      for _, tc in ipairs({
        {
          name = "empty texts",
          args = { texts = {} },
          expected = {
            virt_lines = { { { "", "Comment" } } },
            virt_lines_above = true,
            ephemeral = false
          }
        },
        {
          name = "nil line_content",
          args = { texts = { "test" }, line_content = nil },
          expected = {
            virt_lines = { { { "test", "Comment" } } },
            virt_lines_above = true,
            ephemeral = false
          }
        },
        {
          name = "empty prefix",
          args = { texts = { "test" }, prefix = "" },
          expected = {
            virt_lines = { { { "test", "Comment" } } },
            virt_lines_above = true,
            ephemeral = false
          }
        },
      }) do
        it(("handles %s"):format(tc.name), function()
          local presenter = require("lensline.presenter")
          local result = presenter.compute_extmark_opts(tc.args)
          eq(tc.expected, result)
        end)
      end
    end)
  end)
end)