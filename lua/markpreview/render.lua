-- markpreview.render
-- In-buffer markdown rendering (a focused subset of render-markdown.nvim) built
-- on the bundled treesitter `markdown` + `markdown_inline` grammars:
--   - heading markers -> per-level icon + colour
--   - list bullets -> • / ○ / ◆ … ; task checkboxes -> ☐ / ☑
--   - fenced code blocks -> background band + language label
--   - block quotes -> a coloured bar
--   - thematic breaks -> a full-width rule
--   - inline **bold** / *italic* / `code` / ~~strike~~ / [links] -> concealed markers
--
-- Concealing relies on `conceallevel=2` + `concealcursor=''` (set per window in
-- markpreview.init); with `concealcursor` empty the raw text is revealed on the
-- line the cursor is on, so editing always sees the source.

local M = {}

local ns = vim.api.nvim_create_namespace("markpreview_render")

-- Filetypes we will actually render (set from markpreview.init config). Guards
-- against the buffer's filetype changing away from markdown after attach.
M.filetypes = { "markdown", "markdown.mdx" }

M.config = {
  enable = true,
  conceal = true,
  heading = { enable = true, icons = { "󰲡", "󰲣", "󰲥", "󰲧", "󰲩", "󰲫" } },
  bullet = { enable = true, icons = { "●", "○", "◆", "◇" } },
  checkbox = { enable = true, checked = "󰱒", unchecked = "󰄱" },
  code = { enable = true },
  quote = { enable = true, icon = "▋" },
  hr = { enable = true, char = "─" },
  link = { enable = true, icon = "" },
}

-- Highlight groups (all `default`, so a colorscheme / the user can override).
function M.setup_highlights()
  local set = function(name, val)
    val.default = true
    vim.api.nvim_set_hl(0, name, val)
  end
  set("MarkpreviewH1", { link = "@markup.heading.1.markdown" })
  set("MarkpreviewH2", { link = "@markup.heading.2.markdown" })
  set("MarkpreviewH3", { link = "@markup.heading.3.markdown" })
  set("MarkpreviewH4", { link = "@markup.heading.4.markdown" })
  set("MarkpreviewH5", { link = "@markup.heading.5.markdown" })
  set("MarkpreviewH6", { link = "@markup.heading.6.markdown" })
  set("MarkpreviewBullet", { link = "Special" })
  set("MarkpreviewChecked", { link = "DiagnosticOk" })
  set("MarkpreviewUnchecked", { link = "Comment" })
  set("MarkpreviewQuote", { link = "@markup.quote" })
  set("MarkpreviewLink", { link = "@markup.link.label.markdown_inline" })
  set("MarkpreviewCodeInfo", { link = "Comment" })
  set("MarkpreviewCodeBlock", { link = "ColorColumn" })
  set("MarkpreviewHr", { link = "@markup.heading" })
  set("MarkpreviewBold", { bold = true })
  set("MarkpreviewItalic", { italic = true })
  set("MarkpreviewStrike", { strikethrough = true })
  set("MarkpreviewInlineCode", { link = "@markup.raw.markdown_inline" })
end

local block_query, inline_query
local function queries()
  if not block_query then
    block_query = vim.treesitter.query.parse(
      "markdown",
      [[
        (atx_heading) @heading
        (list_item) @list_item
        (block_quote_marker) @quote
        (thematic_break) @hr
        (fenced_code_block) @code
        (pipe_table) @table
      ]]
    )
    inline_query = vim.treesitter.query.parse(
      "markdown_inline",
      [[
        (emphasis_delimiter) @delim
        (code_span_delimiter) @delim
        (emphasis) @italic
        (strong_emphasis) @bold
        (strikethrough) @strike
        (code_span) @code
        (inline_link) @link
        (image) @image
      ]]
    )
  end
  return block_query, inline_query
end

local function mark(buf, row, col, opts)
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, col, opts)
end

---Find the first child of `node` whose type is in `set` (a lookup table).
local function child_in(node, set)
  for c in node:iter_children() do
    if set[c:type()] then
      return c
    end
  end
end

local BULLET_MARKERS = { list_marker_minus = true, list_marker_star = true, list_marker_plus = true }
local TASK_MARKERS = { task_list_marker_checked = true, task_list_marker_unchecked = true }

local function render_block(buf, root, ctx)
  local cfg = M.config
  local q = (queries())
  for id, node in q:iter_captures(root, buf, ctx.srow, ctx.erow + 1) do
    local cap = q.captures[id]
    local sr, sc, er, ec = node:range()

    if cap == "table" then
      -- Tables are left as markpreview-aligned monospace text; record their
      -- rows so inline markup inside cells is NOT concealed (which would shrink
      -- cell widths and break the column alignment). Clamp to the rendered band.
      for r = math.max(sr, ctx.srow), math.min(er - 1, ctx.erow, ctx.line_count - 1) do
        ctx.in_table[r] = true
      end
    elseif cap == "heading" and cfg.heading.enable then
      local marker
      for c in node:iter_children() do
        if c:type():match("^atx_h%d_marker$") then
          marker = c
          break
        end
      end
      if marker then
        local level = tonumber(marker:type():match("atx_h(%d)_marker")) or 1
        local icon = cfg.heading.icons[level] or cfg.heading.icons[#cfg.heading.icons]
        local hlg = "MarkpreviewH" .. level
        local mr, mc, _, mec = marker:range()
        mark(buf, mr, mc, { end_col = mec, conceal = icon, hl_group = hlg })
        local inline = child_in(node, { inline = true })
        if inline then
          local ir, ic, ier, iec = inline:range()
          mark(buf, ir, ic, { end_row = ier, end_col = iec, hl_group = hlg })
        end
      end
    elseif cap == "list_item" then
      local marker = child_in(node, BULLET_MARKERS)
      local task = child_in(node, TASK_MARKERS)
      if task and cfg.checkbox.enable then
        if marker then
          local r, c, _, e = marker:range()
          mark(buf, r, c, { end_col = e, conceal = "" })
        end
        local tr, tc, _, tec = task:range()
        local checked = task:type() == "task_list_marker_checked"
        mark(buf, tr, tc, {
          end_col = tec,
          conceal = checked and cfg.checkbox.checked or cfg.checkbox.unchecked,
          hl_group = checked and "MarkpreviewChecked" or "MarkpreviewUnchecked",
        })
      elseif marker and cfg.bullet.enable then
        local r, c = marker:range()
        local depth = math.floor(c / 2)
        local icon = cfg.bullet.icons[(depth % #cfg.bullet.icons) + 1]
        mark(buf, r, c, { end_col = c + 1, conceal = icon, hl_group = "MarkpreviewBullet" })
      end
    elseif cap == "quote" and cfg.quote.enable then
      mark(buf, sr, sc, { end_col = sc + 1, conceal = cfg.quote.icon, hl_group = "MarkpreviewQuote" })
    elseif cap == "hr" and cfg.hr.enable then
      -- Skip any window's cursor row so the raw `---` is visible/editable there.
      if sr < ctx.line_count and not ctx.cursor_rows[sr] then
        local line = vim.api.nvim_buf_get_lines(buf, sr, sr + 1, false)[1] or ""
        mark(buf, sr, 0, {
          end_col = #line,
          conceal = "",
          virt_text = { { string.rep(cfg.hr.char, ctx.hr_width), "MarkpreviewHr" } },
          virt_text_pos = "overlay",
        })
      end
    elseif cap == "code" and cfg.code.enable then
      for r = math.max(sr, ctx.srow), math.min(er - 1, ctx.erow, ctx.line_count - 1) do
        mark(buf, r, 0, { line_hl_group = "MarkpreviewCodeBlock" })
      end
      for c in node:iter_children() do
        local t = c:type()
        local cr, cc, _, cec = c:range()
        if t == "fenced_code_block_delimiter" then
          mark(buf, cr, cc, { end_col = cec, conceal = "" })
        elseif t == "info_string" then
          mark(buf, cr, cc, { end_col = cec, hl_group = "MarkpreviewCodeInfo" })
        end
      end
    end
  end
end

local function render_inline(buf, root, ctx)
  local cfg = M.config
  local _, q = queries()
  for id, node in q:iter_captures(root, buf, ctx.srow, ctx.erow + 1) do
    local cap = q.captures[id]
    local sr, sc, er, ec = node:range()

    if ctx.in_table[sr] then
      -- skip inline markup inside table cells to preserve column alignment
    elseif cap == "delim" then
      if cfg.conceal then
        mark(buf, sr, sc, { end_row = er, end_col = ec, conceal = "" })
      end
    elseif cap == "bold" then
      mark(buf, sr, sc, { end_row = er, end_col = ec, hl_group = "MarkpreviewBold" })
    elseif cap == "italic" then
      mark(buf, sr, sc, { end_row = er, end_col = ec, hl_group = "MarkpreviewItalic" })
    elseif cap == "strike" then
      mark(buf, sr, sc, { end_row = er, end_col = ec, hl_group = "MarkpreviewStrike" })
    elseif cap == "code" then
      mark(buf, sr, sc, { end_row = er, end_col = ec, hl_group = "MarkpreviewInlineCode" })
    elseif cap == "link" or cap == "image" then
      if cfg.link.enable then
        local texttype = cap == "link" and "link_text" or "image_description"
        local text = child_in(node, { [texttype] = true })
        if text then
          local tr, tc, ter, tec = text:range()
          if cfg.conceal then
            mark(buf, sr, sc, { end_row = tr, end_col = tc, conceal = "" })
            mark(buf, ter, tec, { end_row = er, end_col = ec, conceal = "" })
          end
          mark(buf, tr, tc, { end_row = ter, end_col = tec, hl_group = "MarkpreviewLink" })
          if cfg.link.icon ~= "" then
            mark(buf, tr, tc, { virt_text = { { cfg.link.icon, "MarkpreviewLink" } }, virt_text_pos = "inline" })
          end
        end
      end
    end
  end
end

---Re-render the buffer. Only the visible window range (plus a margin) is
---decorated, so cost is bounded by the viewport, not the file size — this is
---what keeps scrolling/typing fast in large documents.
function M.render(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if not M.config.enable or vim.b[buf].markpreview_render_off then
    return
  end
  -- The buffer's filetype may have changed after attach (`:set ft=python`);
  -- only ever render configured markdown filetypes.
  if not vim.tbl_contains(M.filetypes, vim.bo[buf].filetype) then
    return
  end

  local lc = vim.api.nvim_buf_line_count(buf)

  -- One band per window showing this buffer (margin bounded by that window's
  -- height — never by the gap between two far-apart windows), plus the set of
  -- cursor rows. If the buffer isn't displayed, there's nothing to render.
  local bands, cursor_rows, hr_width = {}, {}, 80
  for i, w in ipairs(vim.fn.win_findbuf(buf)) do
    local wi = vim.fn.getwininfo(w)[1]
    if wi then
      local margin = math.max(20, wi.botline - wi.topline)
      bands[#bands + 1] = { math.max(0, wi.topline - 1 - margin), math.min(lc - 1, wi.botline - 1 + margin) }
      cursor_rows[vim.api.nvim_win_get_cursor(w)[1] - 1] = true
      if i == 1 then
        hr_width = math.max(1, wi.width - (wi.textoff or 0))
      end
    end
  end
  if #bands == 0 then
    return
  end
  -- Merge overlapping/adjacent bands into a minimal set of disjoint ranges.
  table.sort(bands, function(a, b)
    return a[1] < b[1]
  end)
  local merged = { bands[1] }
  for i = 2, #bands do
    local last = merged[#merged]
    if bands[i][1] <= last[2] + 1 then
      last[2] = math.max(last[2], bands[i][2])
    else
      merged[#merged + 1] = bands[i]
    end
  end

  local ok, parser = pcall(vim.treesitter.get_parser, buf, "markdown")
  if not ok or not parser then
    return
  end

  for _, band in ipairs(merged) do
    local srow, erow = band[1], band[2]
    parser:parse({ srow, 0, erow + 1, 0 })
    local ctx = {
      line_count = lc,
      in_table = {},
      hr_width = hr_width,
      cursor_rows = cursor_rows,
      srow = srow,
      erow = erow,
    }
    for _, tree in ipairs(parser:trees()) do
      render_block(buf, tree:root(), ctx)
    end
    local inline = parser:children()["markdown_inline"]
    if inline then
      for _, tree in ipairs(inline:trees()) do
        render_inline(buf, tree:root(), ctx)
      end
    end
  end
end

-- Debounced re-render, one libuv timer per buffer.
local timers = {}
function M.schedule(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local t = timers[buf]
  if not t then
    t = vim.uv.new_timer()
    timers[buf] = t
  end
  t:stop()
  t:start(
    40,
    0,
    vim.schedule_wrap(function()
      if vim.api.nvim_buf_is_valid(buf) then
        M.render(buf)
      end
    end)
  )
end

---Toggle rendering for a buffer.
function M.toggle(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  vim.b[buf].markpreview_render_off = not vim.b[buf].markpreview_render_off
  M.render(buf)
end

function M.clear(buf)
  local t = timers[buf]
  if t then
    t:stop()
    if not t:is_closing() then
      t:close()
    end
    timers[buf] = nil
  end
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
end

return M
