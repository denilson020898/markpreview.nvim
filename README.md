# markpreview.nvim

An in-editor **markdown editing & navigation layer** for Neovim:

1. **Folding** — nested folds by heading depth (`#`…`######`, plus setext
   `===` / `---`). Fenced code and frontmatter are skipped so `#` comments and
   `---` separators don't create phantom folds.
2. **Table editing** — align GFM tables and add/delete rows & columns from
   wherever the cursor sits. Alignment, wide/CJK widths and `\|` escapes are
   all handled.
3. **No wrap** — `nowrap` by default with smooth horizontal scrolling, and a
   one-key toggle to flip into word-aware soft wrap.

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
| `<localleader>tj`  | add row **below**    |
| `<localleader>tk`  | add row **above**    |
| `<localleader>tl`  | add column **right** |
| `<localleader>th`  | add column **left**  |
| `<localleader>td`  | delete row           |
| `<localleader>tD`  | delete column        |
| `<localleader>w`   | toggle wrap          |

Folding uses the native commands: `za` toggle, `zR` open all, `zM` close all,
`zj`/`zk` to jump between folds.

## Commands

`:MarkTableFormat`, `:MarkTableRowBelow`, `:MarkTableRowAbove`,
`:MarkTableColRight`, `:MarkTableColLeft`, `:MarkTableRowDelete`,
`:MarkTableColDelete`, `:MarkWrapToggle`, `:MarkFoldRefresh`.

## Configuration

See `:help markpreview-config` for the full default table. Everything can be
disabled per-section (`folding.enable`, `tables.enable`, `wrap.enable`,
`keymaps.enable`) or per-mapping (set an individual key to `false`).
