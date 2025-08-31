local eq = assert.are.same

-- Minimal debug stub to avoid noise
package.loaded["lensline.debug"] = { log_context = function() end }

local presenter = require("lensline.presenter")

describe("presenter", function()
  describe("combine_provider_data", function()
    it("returns empty table when provider_lens_data is nil", function()
      local result = presenter.combine_provider_data(nil, {})
      eq({}, result)
    end)

    it("returns empty table when provider_lens_data is empty", function()
      local result = presenter.combine_provider_data({}, {})
      eq({}, result)
    end)

    it("preserves provider order from config", function()
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
      
      -- Should combine in config order: A first, then B
      eq({
        [1] = { "A1", "B1" },
        [2] = { "A2", "B2" }
      }, result)
    end)

    it("skips disabled providers", function()
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

    it("handles sparse arrays with numeric indices", function()
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
      
      -- Should preserve numeric order: 1, 3, 5
      eq({
        [1] = { "first", "third", "fifth" }
      }, result)
    end)

    it("ignores invalid items without line or text", function()
      local provider_lens_data = {
        mixed_provider = {
          { line = 1, text = "valid" },
          { line = 1 }, -- missing text
          { text = "missing_line" }, -- missing line
          { line = 1, text = "also_valid" },
          nil, -- nil item
          { line = 1, text = "" } -- empty text should be ignored
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

    it("groups multiple texts by line", function()
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
      it("creates virt_lines with default values", function()
        local args = {
          texts = { "test text" }
        }
        
        local result = presenter.compute_extmark_opts(args)
        
        eq({
          virt_lines = { { { "test text", "Comment" } } },
          virt_lines_above = true,
          ephemeral = false
        }, result)
      end)

      it("handles custom separator and highlight", function()
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

      it("adds prefix when configured", function()
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

      it("preserves line indentation", function()
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

      it("handles mixed indentation types", function()
        local args = {
          texts = { "test" },
          line_content = "\t  function foo()" -- tab + spaces
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

      it("sets ephemeral when requested", function()
        local args = {
          texts = { "test" },
          ephemeral = true
        }
        
        local result = presenter.compute_extmark_opts(args)
        
        assert.is_true(result.ephemeral)
      end)
    end)

    describe("inline placement", function()
      it("creates virt_text at end of line", function()
        local args = {
          placement = "inline",
          texts = { "test" }
        }
        
        local result = presenter.compute_extmark_opts(args)
        
        eq({
          virt_text = { { " test", "Comment" } },
          virt_text_pos = "eol",
          ephemeral = false
        }, result)
      end)

      it("adds prefix to inline text", function()
        local args = {
          placement = "inline",
          texts = { "test" },
          prefix = ">> "
        }
        
        local result = presenter.compute_extmark_opts(args)
        
        eq({
          virt_text = { { " >> test", "Comment" } },
          virt_text_pos = "eol",
          ephemeral = false
        }, result)
      end)

      it("combines multiple texts with separator", function()
        local args = {
          placement = "inline",
          texts = { "first", "second" },
          separator = " • "
        }
        
        local result = presenter.compute_extmark_opts(args)
        
        eq({
          virt_text = { { " first • second", "Comment" } },
          virt_text_pos = "eol",
          ephemeral = false
        }, result)
      end)

      it("ignores line_content for inline placement", function()
        local args = {
          placement = "inline",
          texts = { "test" },
          line_content = "    indented line"
        }
        
        local result = presenter.compute_extmark_opts(args)
        
        -- Should not include indentation for inline
        eq({
          virt_text = { { " test", "Comment" } },
          virt_text_pos = "eol",
          ephemeral = false
        }, result)
      end)
    end)

    describe("edge cases", function()
      it("handles empty texts array", function()
        local args = {
          texts = {}
        }
        
        local result = presenter.compute_extmark_opts(args)
        
        eq({
          virt_lines = { { { "", "Comment" } } },
          virt_lines_above = true,
          ephemeral = false
        }, result)
      end)

      it("handles nil line_content", function()
        local args = {
          texts = { "test" },
          line_content = nil
        }
        
        local result = presenter.compute_extmark_opts(args)
        
        eq({
          virt_lines = { { { "test", "Comment" } } },
          virt_lines_above = true,
          ephemeral = false
        }, result)
      end)

      it("handles empty string prefix", function()
        local args = {
          texts = { "test" },
          prefix = ""
        }
        
        local result = presenter.compute_extmark_opts(args)
        
        eq({
          virt_lines = { { { "test", "Comment" } } },
          virt_lines_above = true,
          ephemeral = false
        }, result)
      end)
    end)
  end)
end)