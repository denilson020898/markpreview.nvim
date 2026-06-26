-- markpreview.table
-- Lightweight GFM table editing: format/align, add or delete rows and columns,
-- all driven from wherever the cursor sits inside a pipe table.
--
-- A "table" here is a run of consecutive non-blank lines that each contain a
-- `|`. The delimiter row (`| --- | :--: |`) is detected and used to recover
-- per-column alignment; everything is re-aligned on every edit. Display width
-- (`strdisplaywidth`) is used for padding so CJK / wide glyphs line up.

local M = {}

local function notify(msg, level)
  vim.notify("[markpreview] " .. msg, level or vim.log.levels.WARN)
end

local function strwidth(s)
  return vim.fn.strdisplaywidth(s)
end

---Split one table line into trimmed cells, honouring `\|` escapes and an
---optional leading/trailing border pipe.
---@param line string
---@return string[]
local function split_row(line)
  local s = vim.trim(line)
  s = s:gsub("^|", "")
  s = s:gsub("|%s*$", "")
  local cells, buf, i = {}, "", 1
  while i <= #s do
    local ch = s:sub(i, i)
    if ch == "\\" then
      buf = buf .. s:sub(i, i + 1)
      i = i + 2
    elseif ch == "|" then
      cells[#cells + 1] = vim.trim(buf)
      buf, i = "", i + 1
    else
      buf = buf .. ch
      i = i + 1
    end
  end
  cells[#cells + 1] = vim.trim(buf)
  return cells
end

---Is this the `--- | :--: | ---:` delimiter row?
local function is_delim_row(cells)
  if #cells == 0 then
    return false
  end
  for _, c in ipairs(cells) do
    if not c:match("^:?%-+:?$") then
      return false
    end
  end
  return true
end

---Alignment encoded by a delimiter cell: "left" | "right" | "center" | "none".
local function align_of(cell)
  local l = cell:sub(1, 1) == ":"
  local r = cell:sub(-1) == ":"
  if l and r then
    return "center"
  elseif r then
    return "right"
  elseif l then
    return "left"
  end
  return "none"
end

local function pad(cell, width, align)
  local extra = width - strwidth(cell)
  if extra <= 0 then
    return cell
  end
  if align == "right" then
    return string.rep(" ", extra) .. cell
  elseif align == "center" then
    local left = math.floor(extra / 2)
    return string.rep(" ", left) .. cell .. string.rep(" ", extra - left)
  end
  return cell .. string.rep(" ", extra)
end

local function make_delim(width, align)
  if align == "center" then
    return ":" .. string.rep("-", math.max(1, width - 2)) .. ":"
  elseif align == "right" then
    return string.rep("-", math.max(1, width - 1)) .. ":"
  elseif align == "left" then
    return ":" .. string.rep("-", math.max(1, width - 1))
  end
  return string.rep("-", width)
end

---The run of table lines surrounding 1-indexed line `lnum`, or nil.
---@return integer? start, integer? finish
local function table_range(buf, lnum)
  local function is_row(l)
    if l < 1 or l > vim.api.nvim_buf_line_count(buf) then
      return false
    end
    local txt = vim.api.nvim_buf_get_lines(buf, l - 1, l, false)[1]
    if txt == nil then
      return false
    end
    -- A table row must carry a border pipe (leading or trailing). This keeps
    -- the range from swallowing prose / inline code that merely contains a '|'
    -- (e.g. `cmd | grep x`), which would otherwise be reformatted as cells.
    local t = vim.trim(txt)
    return t ~= "" and (t:sub(1, 1) == "|" or t:sub(-1) == "|")
  end
  if not is_row(lnum) then
    return nil
  end
  local s, e = lnum, lnum
  while is_row(s - 1) do
    s = s - 1
  end
  while is_row(e + 1) do
    e = e + 1
  end
  return s, e
end

---Read the table at [s, e] into a matrix of cells plus the delimiter row index.
local function read_table(buf, s, e)
  local rows, delim = {}, nil
  for l = s, e do
    local line = vim.api.nvim_buf_get_lines(buf, l - 1, l, false)[1]
    rows[#rows + 1] = split_row(line)
    if not delim and is_delim_row(rows[#rows]) then
      delim = #rows
    end
  end
  return rows, delim
end

---Render the matrix back to aligned text lines.
local function render(rows, delim)
  local ncols = 0
  for _, r in ipairs(rows) do
    ncols = math.max(ncols, #r)
  end
  for _, r in ipairs(rows) do
    for j = #r + 1, ncols do
      r[j] = ""
    end
  end

  local aligns, widths = {}, {}
  for j = 1, ncols do
    aligns[j] = delim and align_of(rows[delim][j] or "") or "none"
    widths[j] = 3 -- room for at least "---"
  end
  for ri, r in ipairs(rows) do
    if ri ~= delim then
      for j = 1, ncols do
        widths[j] = math.max(widths[j], strwidth(r[j] or ""))
      end
    end
  end

  local out = {}
  for ri, r in ipairs(rows) do
    local parts = {}
    for j = 1, ncols do
      parts[j] = (ri == delim) and make_delim(widths[j], aligns[j]) or pad(r[j] or "", widths[j], aligns[j])
    end
    out[ri] = "| " .. table.concat(parts, " | ") .. " |"
  end
  return out
end

---1-indexed cell index the cursor (byte col) sits in, matching split_row's cells.
local function cell_index_at(line, col)
  local pipes, i = {}, 1
  while i <= #line do
    local ch = line:sub(i, i)
    if ch == "\\" then
      i = i + 2
    else
      if ch == "|" then
        pipes[#pipes + 1] = i
      end
      i = i + 1
    end
  end
  if #pipes == 0 then
    return 1
  end
  local left_border = vim.trim(line:sub(1, pipes[1] - 1)) == ""
  local right_border = vim.trim(line:sub(pipes[#pipes] + 1)) == ""
  local idx = 1
  for k, p in ipairs(pipes) do
    local is_border = (k == 1 and left_border) or (k == #pipes and right_border)
    if not is_border then
      if col > p then
        idx = idx + 1
      else
        break
      end
    end
  end
  return idx
end

---Byte column of the first content char of rendered cell `k` (for cursor reset).
---Skips escaped pipes (`\|`) so cells containing them don't shift the count.
local function cell_start_col(line, k)
  local count, i = 0, 1
  while i <= #line do
    local ch = line:sub(i, i)
    if ch == "\\" then
      i = i + 2
    elseif ch == "|" then
      count = count + 1
      if count == k then
        local j = i + 1
        return (line:sub(j, j) == " ") and j + 1 or j
      end
      i = i + 1
    else
      i = i + 1
    end
  end
  return 1
end

---First all-dash delimiter row index in a matrix, or nil.
local function find_delim(rows)
  for idx, r in ipairs(rows) do
    if is_delim_row(r) then
      return idx
    end
  end
  return nil
end

---Resolve cursor context, returning everything an edit needs, or nil.
local function context()
  local buf = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(0) -- {row(1-idx), col(0-idx)}
  local lnum = pos[1]
  local s, e = table_range(buf, lnum)
  if not s then
    notify("cursor is not inside a table")
    return nil
  end
  local rows, delim = read_table(buf, s, e)
  return {
    buf = buf,
    s = s,
    e = e,
    rows = rows,
    delim = delim,
    row_in_tbl = lnum - s + 1, -- 1-indexed row within the table
    col = cell_index_at(vim.fn.getline(lnum), pos[2] + 1),
  }
end

---Write `out` over [s, e] and place the cursor at (target_row, target_col_cell).
local function commit(ctx, out, target_row, target_cell)
  vim.api.nvim_buf_set_lines(ctx.buf, ctx.s - 1, ctx.e, false, out)
  target_row = math.max(1, math.min(target_row, #out))
  local line = out[target_row]
  local lnum = ctx.s + target_row - 1
  local col = target_cell and (cell_start_col(line, target_cell) - 1) or 0
  vim.api.nvim_win_set_cursor(0, { lnum, math.max(0, math.min(col, #line - 1)) })
end

---Format / re-align the table under the cursor.
function M.format()
  local ctx = context()
  if not ctx then
    return
  end
  commit(ctx, render(ctx.rows, ctx.delim), ctx.row_in_tbl, ctx.col)
end

---Insert an empty row. `dir` is "above" or "below". Rows are always inserted
---into the body (never above the header or the delimiter).
function M.add_row(dir)
  local ctx = context()
  if not ctx then
    return
  end
  local first_body = ctx.delim and ctx.delim + 1 or 2
  local at
  if dir == "above" then
    at = math.max(first_body, ctx.row_in_tbl)
  else
    at = math.max(first_body, ctx.row_in_tbl + 1)
  end

  local ncols = 0
  for _, r in ipairs(ctx.rows) do
    ncols = math.max(ncols, #r)
  end
  local blank = {}
  for j = 1, ncols do
    blank[j] = ""
  end
  table.insert(ctx.rows, at, blank)
  commit(ctx, render(ctx.rows, ctx.delim), at, 1)
end

---Insert an empty column. `dir` is "left" or "right" of the current cell.
function M.add_column(dir)
  local ctx = context()
  if not ctx then
    return
  end
  local at = (dir == "right") and ctx.col + 1 or ctx.col
  for ri, r in ipairs(ctx.rows) do
    table.insert(r, at, ri == ctx.delim and "-" or "")
  end
  commit(ctx, render(ctx.rows, ctx.delim), ctx.row_in_tbl, at)
end

---Delete the current row (refuses to delete the header or delimiter row).
function M.delete_row()
  local ctx = context()
  if not ctx then
    return
  end
  if ctx.row_in_tbl == 1 or ctx.row_in_tbl == ctx.delim then
    notify("refusing to delete the header / delimiter row")
    return
  end
  if #ctx.rows <= (ctx.delim and ctx.delim or 1) then
    notify("nothing left to delete")
    return
  end
  table.remove(ctx.rows, ctx.row_in_tbl)
  -- The delimiter may have shifted up if the removed row was above it; re-detect.
  commit(ctx, render(ctx.rows, find_delim(ctx.rows)), ctx.row_in_tbl, ctx.col)
end

---Delete the current column.
function M.delete_column()
  local ctx = context()
  if not ctx then
    return
  end
  local ncols = 0
  for _, r in ipairs(ctx.rows) do
    ncols = math.max(ncols, #r)
  end
  if ncols <= 1 then
    notify("refusing to delete the last column")
    return
  end
  for _, r in ipairs(ctx.rows) do
    if ctx.col <= #r then
      table.remove(r, ctx.col)
    end
  end
  commit(ctx, render(ctx.rows, ctx.delim), ctx.row_in_tbl, math.max(1, ctx.col - 1))
end

---Quietly report whether the cursor is inside a table (used by auto_format so
---it never notifies or rewrites on ordinary prose lines).
function M.is_table_here()
  local buf = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  return (table_range(buf, lnum)) ~= nil
end

-- Matches a <br> line break in any common form: <br>, <br/>, <br />, <BR>.
local BR_PATTERN = "%s*<%s*[Bb][Rr]%s*/?%s*>%s*"

---Set the cell at absolute line `lnum`, column index `col`, to `value`, then
---re-align the table and restore the cursor to that cell.
local function set_cell(buf, lnum, col, value)
  local s, e = table_range(buf, lnum)
  if not s then
    return
  end
  local rows = read_table(buf, s, e)
  local r = lnum - s + 1
  local row = rows[r]
  if not row then
    return
  end
  for j = #row + 1, col do
    row[j] = ""
  end
  row[col] = value
  local out = render(rows, find_delim(rows))
  vim.api.nvim_buf_set_lines(buf, s - 1, e, false, out)
  local target = out[r] or ""
  local pos = { s + r - 1, math.max(0, cell_start_col(target, col) - 1) }
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_get_buf(win) == buf then
      pcall(vim.api.nvim_win_set_cursor, win, pos)
    end
  end
end

---Open a floating editor for the cell under the cursor. The cell is shown as
---multi-line text (each `<br>` becomes a real line), so adding a line break is
---just pressing Enter. On save the lines are rejoined with `<br>`, pipes are
---escaped, and the table is re-aligned. <CR>/q/<C-s> (or leaving the window)
---save; <C-c> cancels.
function M.cell_edit()
  local ctx = context()
  if not ctx then
    return
  end
  if ctx.row_in_tbl == ctx.delim then
    notify("cannot edit the delimiter row")
    return
  end
  local buf, col = ctx.buf, ctx.col
  local lnum = ctx.s + ctx.row_in_tbl - 1
  local cell = (ctx.rows[ctx.row_in_tbl] or {})[col] or ""

  -- De-serialize for comfortable editing: <br> -> newline, \| -> |.
  local display = cell:gsub(BR_PATTERN, "\n"):gsub("\\|", "|")
  local lines = vim.split(display, "\n", { plain = true })
  if #lines == 0 then
    lines = { "" }
  end

  local fbuf = vim.api.nvim_create_buf(false, true)
  vim.bo[fbuf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(fbuf, 0, -1, false, lines)

  local title = " edit cell  (Enter = new line · <CR>/q save · <C-c> cancel) "
  local width = vim.fn.strdisplaywidth(title)
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l) + 2)
  end
  width = math.min(width, math.max(40, math.floor(vim.o.columns * 0.7)))
  local win = vim.api.nvim_open_win(fbuf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = math.min(math.max(#lines, 1), 12),
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  })
  vim.wo[win].wrap = true

  local done = false
  local function finish(save)
    if done then
      return
    end
    done = true
    local value
    if save and vim.api.nvim_buf_is_valid(fbuf) then
      local body = vim.api.nvim_buf_get_lines(fbuf, 0, -1, false)
      while #body > 1 and vim.trim(body[#body]) == "" do
        table.remove(body)
      end
      local parts = {}
      for _, l in ipairs(body) do
        parts[#parts + 1] = (vim.trim(l):gsub("|", "\\|"))
      end
      value = table.concat(parts, "<br>")
    end
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if value ~= nil then
      set_cell(buf, lnum, col, value)
    end
  end

  local map = function(mode, lhs, fn)
    vim.keymap.set(mode, lhs, fn, { buffer = fbuf, nowait = true, silent = true })
  end
  map("n", "<CR>", function()
    finish(true)
  end)
  map("n", "q", function()
    finish(true)
  end)
  map({ "n", "i" }, "<C-s>", function()
    finish(true)
  end)
  map({ "n", "i" }, "<C-c>", function()
    finish(false)
  end)
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = fbuf,
    once = true,
    callback = function()
      finish(true)
    end,
  })
end

return M
