-- markpreview.nvim
-- An in-editor markdown layer: heading folding, GFM table editing, and
-- no-wrap with comfortable horizontal scrolling. Complements (does not
-- replace) renderers like render-markdown.nvim.

local M = {}

local unpack = table.unpack or unpack

local defaults = {
  -- Filetypes the plugin attaches to.
  filetypes = { "markdown", "markdown.mdx" },

  folding = {
    enable = true,
    default_level = 99, -- start fully open; use zM/zR/za to fold
    setext = true, -- also fold `===` / `---` underlined headings
    fold_text = true, -- pretty "## Heading  (N lines)" fold labels
  },

  wrap = {
    enable = true,
    wrap = false, -- no wrap in markdown by default
    linebreak = true, -- break at word boundaries when wrap is on
    breakindent = true,
    sidescrolloff = 8, -- keep context when scrolling a long no-wrap line
    sidescroll = 1, -- global: scroll one column at a time (set false to leave it)
  },

  tables = {
    enable = true,
    auto_format = false, -- re-align the current table on InsertLeave
  },

  export = {
    open = true, -- open the produced PDF/HTML in the system viewer when done
    theme = nil, -- nil = md2pdf default (dark HTML, light PDF); or "dark"/"light"
    font = nil, -- nil = md2pdf default ("Hack Nerd Font"); or any family name
    width = nil, -- nil = md2pdf default ("60rem" HTML column); or e.g. "none"
  },

  -- In-buffer rendering (headings, lists, checkboxes, code, quotes, inline …).
  -- Per-element options live in markpreview.render; merged over its defaults.
  render = {
    enable = true,
  },

  keymaps = {
    enable = true,
    -- Table editing (buffer-local, normal mode). Set any to false to skip it.
    format = "<localleader>tf",
    cell_edit = "<localleader>tc",
    row_below = "<localleader>tj",
    row_above = "<localleader>tk",
    col_right = "<localleader>tl",
    col_left = "<localleader>th",
    row_delete = "<localleader>td",
    col_delete = "<localleader>tD",
    -- View / export.
    wrap_toggle = "<localleader>w",
    export_pdf = "<localleader>p",
    render_toggle = "<localleader>r",
  },
}

M.config = vim.deepcopy(defaults)

-- Shared autocommand group, created in setup().
local augroup

---Apply window-local fold + wrap options to `win` ONCE (0/nil = current window).
---Idempotent per window: foldlevel/foldenable/wrap are only set on first init so
---that manual `zM`/`:MarkWrapToggle` are preserved across re-displays (BufWinEnter).
function M.ensure_window(win)
  win = (win == nil or win == 0) and vim.api.nvim_get_current_win() or win
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  if vim.w[win].markpreview_view_init then
    return
  end
  vim.w[win].markpreview_view_init = true

  local cfg = M.config
  if cfg.folding.enable then
    require("markpreview.fold").config = cfg.folding
    local set = function(name, value)
      vim.api.nvim_set_option_value(name, value, { win = win })
    end
    set("foldmethod", "expr")
    set("foldexpr", "v:lua.require'markpreview.fold'.expr()")
    if cfg.folding.fold_text then
      set("foldtext", "v:lua.require'markpreview.fold'.foldtext()")
    end
    set("foldenable", true)
    set("foldlevel", cfg.folding.default_level)
  end
  if cfg.wrap.enable then
    require("markpreview.wrap").apply(win, cfg.wrap)
  end
  if cfg.render.enable then
    -- conceallevel makes the rendered markers show; empty concealcursor reveals
    -- the raw source on the cursor line so editing always sees the markup.
    vim.api.nvim_set_option_value("conceallevel", 2, { win = win })
    vim.api.nvim_set_option_value("concealcursor", "", { win = win })
  end
end

local function setup_commands(buf)
  local tbl = function()
    return require("markpreview.table")
  end
  local cmd = function(name, fn, desc)
    vim.api.nvim_buf_create_user_command(buf, name, fn, { desc = desc })
  end
  cmd("MarkTableFormat", function()
    tbl().format()
  end, "Markdown: format/align the table under the cursor")
  cmd("MarkTableCellEdit", function()
    tbl().cell_edit()
  end, "Markdown: edit the current cell in a floating window (<br> = new line)")
  cmd("MarkTableRowBelow", function()
    tbl().add_row("below")
  end, "Markdown: add a table row below")
  cmd("MarkTableRowAbove", function()
    tbl().add_row("above")
  end, "Markdown: add a table row above")
  cmd("MarkTableColRight", function()
    tbl().add_column("right")
  end, "Markdown: add a table column to the right")
  cmd("MarkTableColLeft", function()
    tbl().add_column("left")
  end, "Markdown: add a table column to the left")
  cmd("MarkTableRowDelete", function()
    tbl().delete_row()
  end, "Markdown: delete the current table row")
  cmd("MarkTableColDelete", function()
    tbl().delete_column()
  end, "Markdown: delete the current table column")
  cmd("MarkWrapToggle", function()
    require("markpreview.wrap").toggle()
  end, "Markdown: toggle line wrap")
  cmd("MarkExportPdf", function()
    require("markpreview.export").export("pdf", M.config.export)
  end, "Markdown: export this file to PDF (pandoc + headless browser)")
  cmd("MarkExportHtml", function()
    require("markpreview.export").export("html", M.config.export)
  end, "Markdown: export this file to a self-contained HTML")
  cmd("MarkRenderToggle", function()
    require("markpreview.render").toggle(buf)
  end, "Markdown: toggle in-buffer rendering")
  cmd("MarkFoldRefresh", function()
    require("markpreview.fold").clear(buf)
    vim.cmd("normal! zx")
  end, "Markdown: recompute heading folds")
end

local function setup_keymaps(buf)
  local km = M.config.keymaps
  local map = function(lhs, fn, desc)
    if lhs and lhs ~= "" then
      vim.keymap.set("n", lhs, fn, { buffer = buf, silent = true, desc = desc })
    end
  end
  local tbl = function(method, ...)
    local args = { ... }
    return function()
      require("markpreview.table")[method](unpack(args))
    end
  end
  map(km.format, tbl("format"), "MD table: format/align")
  map(km.cell_edit, tbl("cell_edit"), "MD table: edit cell (float, <br>=new line)")
  map(km.row_below, tbl("add_row", "below"), "MD table: add row below")
  map(km.row_above, tbl("add_row", "above"), "MD table: add row above")
  map(km.col_right, tbl("add_column", "right"), "MD table: add column right")
  map(km.col_left, tbl("add_column", "left"), "MD table: add column left")
  map(km.row_delete, tbl("delete_row"), "MD table: delete row")
  map(km.col_delete, tbl("delete_column"), "MD table: delete column")
  map(km.wrap_toggle, function()
    require("markpreview.wrap").toggle()
  end, "MD: toggle wrap")
  map(km.export_pdf, function()
    require("markpreview.export").export("pdf", M.config.export)
  end, "MD: export to PDF")
  map(km.render_toggle, function()
    require("markpreview.render").toggle(0)
  end, "MD: toggle in-buffer rendering")
end

local function setup_autoformat(buf)
  -- Buffer-local autocmd in the shared group: auto-removed on buffer wipe, so
  -- no per-buffer augroup is leaked. Only fires when actually inside a table.
  vim.api.nvim_create_autocmd("InsertLeave", {
    buffer = buf,
    group = augroup,
    callback = function()
      local t = require("markpreview.table")
      if t.is_table_here() then
        pcall(t.format)
      end
    end,
  })
end

local function setup_render(buf)
  local render = require("markpreview.render")
  -- CursorMoved is included so the horizontal-rule overlay reveals the raw
  -- `---` on the line being edited (inline conceal is handled by concealcursor).
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave", "CursorMoved" }, {
    buffer = buf,
    group = augroup,
    callback = function()
      render.schedule(buf)
    end,
  })
  render.render(buf)
end

---Attach the plugin to a buffer (idempotent). Buffer-local setup runs once;
---window options are applied only to windows that actually display `buf`.
function M.attach(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if not vim.b[buf].markpreview_attached then
    vim.b[buf].markpreview_attached = true
    setup_commands(buf)
    if M.config.keymaps.enable then
      setup_keymaps(buf)
    end
    if M.config.tables.enable and M.config.tables.auto_format then
      setup_autoformat(buf)
    end
    if M.config.render.enable then
      setup_render(buf)
    end
  end
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    M.ensure_window(win)
  end
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  require("markpreview.fold").config = M.config.folding

  -- Merge the render config over markpreview.render's full defaults (icons etc).
  local render = require("markpreview.render")
  render.config = vim.tbl_deep_extend("force", render.config, M.config.render or {})
  render.filetypes = M.config.filetypes
  render.setup_highlights()

  -- `sidescroll` is a global option; set it once for smooth no-wrap scrolling.
  if M.config.wrap.enable and M.config.wrap.sidescroll then
    vim.api.nvim_set_option_value("sidescroll", M.config.wrap.sidescroll, {})
  end

  augroup = vim.api.nvim_create_augroup("markpreview", { clear = true })
  local fts = M.config.filetypes

  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = fts,
    callback = function(ev)
      M.attach(ev.buf)
    end,
  })

  -- Re-apply window-local fold/wrap options when a markdown buffer is shown in
  -- another window or split (these options don't follow the buffer). The
  -- per-window guard in ensure_window keeps this from clobbering manual state.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = augroup,
    callback = function(ev)
      if vim.tbl_contains(fts, vim.bo[ev.buf].filetype) then
        M.attach(ev.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = augroup,
    callback = function(ev)
      require("markpreview.fold").clear(ev.buf)
      require("markpreview.render").clear(ev.buf)
    end,
  })

  -- Re-link highlight groups when the colorscheme changes.
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup,
    callback = function()
      require("markpreview.render").setup_highlights()
    end,
  })

  -- Attach to any markdown buffers that are already open at setup time. Reset
  -- the per-buffer guard first: a re-setup() recreates `augroup` with
  -- clear=true (dropping the buffer-local render/autoformat autocmds), so we
  -- must let attach() fully re-run to re-register them.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.tbl_contains(fts, vim.bo[buf].filetype) then
      vim.b[buf].markpreview_attached = nil
      M.attach(buf)
    end
  end
end

return M
