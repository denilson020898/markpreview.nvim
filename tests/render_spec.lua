-- Headless test for the in-buffer renderer.
-- Run:  nvim --headless -u NONE -i NONE -n -l tests/render_spec.lua
--
-- Covers the rendered extmarks plus the regressions found in review:
--   - table cells are NOT inline-concealed (alignment preserved)
--   - rendering stops when a buffer's filetype leaves markdown
--   - the horizontal-rule overlay reveals the raw `---` on the cursor line
--   - live-render autocmds survive a second setup()

local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(repo)
require("markpreview").setup({})
local R = require("markpreview.render")
local ns = vim.api.nvim_get_namespaces()["markpreview_render"]

local fails = 0
local function check(name, cond, extra)
  print((cond and "PASS  " or "FAIL  ") .. name .. (extra and ("  -> " .. tostring(extra)) or ""))
  if not cond then
    fails = fails + 1
  end
end
local function md(lines)
  local b = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(b)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].filetype = "markdown"
  return b
end
local function marks(b)
  return vim.api.nvim_buf_get_extmarks(b, ns, 0, -1, { details = true })
end
local function on_row(b, row, pred)
  for _, m in ipairs(marks(b)) do
    if m[2] == row and pred(m[4]) then
      return true
    end
  end
  return false
end

-- core rendering ------------------------------------------------------------
do
  local b = md({
    "# H1", -- 0
    "### H3", -- 1
    "- bullet", -- 2
    "- [ ] todo", -- 3
    "- [x] done", -- 4
    "> quote", -- 5
    "", -- 6
    "---", -- 7
    "", -- 8
    "p **b** *i* `c` ~~s~~ [l](http://x)", -- 9
    "", -- 10
    "```lua", -- 11
    "x = 1", -- 12
    "```", -- 13
  })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  R.render(b)
  check("H1 icon", on_row(b, 0, function(d) return d.conceal == "󰲡" and d.hl_group == "MarkpreviewH1" end))
  check("H3 icon", on_row(b, 1, function(d) return d.conceal == "󰲥" and d.hl_group == "MarkpreviewH3" end))
  check("bullet", on_row(b, 2, function(d) return d.conceal == "●" end))
  check("unchecked", on_row(b, 3, function(d) return d.conceal == "󰄱" end))
  check("checked", on_row(b, 4, function(d) return d.conceal == "󰱒" end))
  check("quote bar", on_row(b, 5, function(d) return d.conceal == "▋" end))
  check("hr overlay", on_row(b, 7, function(d) return d.virt_text and d.virt_text[1][1]:find("─") ~= nil end))
  check("inline bold", on_row(b, 9, function(d) return d.hl_group == "MarkpreviewBold" end))
  check("inline code", on_row(b, 9, function(d) return d.hl_group == "MarkpreviewInlineCode" end))
  check("inline delim concealed", on_row(b, 9, function(d) return d.conceal == "" end))
  check("link text hl", on_row(b, 9, function(d) return d.hl_group == "MarkpreviewLink" end))
  local bands = 0
  for _, m in ipairs(marks(b)) do
    if m[4].line_hl_group == "MarkpreviewCodeBlock" then bands = bands + 1 end
  end
  check("code block band", bands >= 3, bands)
end

-- table cells keep raw markup (alignment preserved) -------------------------
do
  local b = md({ "| H | N |", "| - | - |", "| **b** | `c` |", "", "out **b** x" })
  R.render(b)
  local touched = {}
  for _, m in ipairs(marks(b)) do touched[m[2]] = true end
  check("table rows not inline-rendered", not (touched[0] or touched[1] or touched[2]), vim.inspect(touched))
  check("inline still rendered outside tables", touched[4] == true)
end

-- filetype guard ------------------------------------------------------------
do
  local b = md({ "# H", "x" })
  R.render(b)
  check("renders markdown", #marks(b) > 0)
  vim.bo[b].filetype = "python"
  R.render(b)
  check("cleared when ft leaves markdown", #marks(b) == 0, #marks(b))
end

-- HR reveals raw source on the cursor line ----------------------------------
do
  local b = md({ "above", "", "---", "", "below" })
  local function hr() return on_row(b, 2, function(d) return d.virt_text ~= nil end) end
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  R.render(b)
  check("HR hidden on cursor line", not hr())
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  R.render(b)
  check("HR shown off cursor line", hr())
end

-- toggle + re-setup ---------------------------------------------------------
do
  local b = md({ "# T", "x" })
  R.toggle(b)
  check("toggle off clears", #marks(b) == 0)
  R.toggle(b)
  check("toggle on re-renders", #marks(b) > 0)
  require("markpreview").setup({})
  local au = vim.api.nvim_get_autocmds({ group = "markpreview", event = "TextChanged", buffer = b })
  check("live-render autocmd survives re-setup", #au > 0, #au)
end

print(string.rep("-", 40))
print(fails == 0 and "ALL RENDER SPEC TESTS PASSED" or (fails .. " RENDER SPEC TEST(S) FAILED"))
vim.cmd(fails == 0 and "qa!" or "cq")
