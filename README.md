# markpreview.nvim

An in-editor **markdown editing & navigation layer** for Neovim:

1. **Folding** — nested folds by heading depth (`#`…`######`, plus setext
   `===` / `---`). Fenced code and frontmatter are skipped so `#` comments and
   `---` separators don't create phantom folds.
2. **Table editing** — align GFM tables, add/delete rows & columns, and edit a
   cell in a floating window (each `<br>` is a line — press Enter to add one)
   from wherever the cursor sits. Alignment, wide/CJK widths and `|`/`\`
   escaping are all handled.
3. **No wrap** — `nowrap` by default with smooth horizontal scrolling, and a
   one-key toggle to flip into word-aware soft wrap.
4. **Export** — `:MarkExportPdf` / `:MarkExportHtml` via the bundled `md2pdf`
   script (pandoc → styled HTML → headless Chromium → PDF). Minimal deps.

It is **complementary** to renderers like
[render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim):
that handles how markdown *looks*, this handles how you *move through and edit* it.

## Install (lazy.nvim, local checkout)

```lua
{
  dir = "/home/son/Projects/markpreview.nvim",
  main = "markpreview",
  ft = { "markdown", "markdown.mdx" },
  opts = {},
}
```

## Default mappings (buffer-local, `<localleader>` = `\`)

The table keys mirror `hjkl`:

| Mapping            | Action               |
| ------------------ | -------------------- |
| `<localleader>tf`  | format / align table |
| `<localleader>tc`  | edit current cell    |
| `<localleader>tj`  | add row **below**    |
| `<localleader>tk`  | add row **above**    |
| `<localleader>tl`  | add column **right** |
| `<localleader>th`  | add column **left**  |
| `<localleader>td`  | delete row           |
| `<localleader>tD`  | delete column        |
| `<localleader>w`   | toggle wrap          |
| `<localleader>p`   | export to PDF        |

Folding uses the native commands: `za` toggle, `zR` open all, `zM` close all,
`zj`/`zk` to jump between folds.

## Commands

`:MarkTableFormat`, `:MarkTableCellEdit`, `:MarkTableRowBelow`,
`:MarkTableRowAbove`, `:MarkTableColRight`, `:MarkTableColLeft`,
`:MarkTableRowDelete`, `:MarkTableColDelete`, `:MarkWrapToggle`,
`:MarkFoldRefresh`, `:MarkExportPdf`, `:MarkExportHtml`.

## Export to PDF / HTML

A standalone `scripts/md2pdf` does **Markdown → (pandoc) self-contained styled
HTML → (headless Chromium) PDF** — no LaTeX, no pip/npm installs. Symlink it
onto your `PATH` to use it anywhere, and `:MarkExportPdf` will pick it up:

```sh
ln -s ~/Projects/markpreview.nvim/scripts/md2pdf ~/.local/bin/md2pdf
md2pdf notes.md            # -> notes.pdf
md2pdf notes.md --html-only # -> notes.html
```

Requires `pandoc` and a Chromium-family browser (Chrome/Chromium/Brave/Edge,
auto-detected). `wkhtmltopdf` works only if forced via `MD2PDF_ENGINE`.

## Configuration

See `:help markpreview-config` for the full default table. Everything can be
disabled per-section (`folding.enable`, `tables.enable`, `wrap.enable`,
`keymaps.enable`) or per-mapping (set an individual key to `false`).
