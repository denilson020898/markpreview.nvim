-- markpreview.export
-- Thin, async bridge to the standalone `md2pdf` script (markdown -> styled
-- self-contained HTML via pandoc -> PDF via a headless Chromium browser).
-- The plugin does not reimplement the pipeline; it just runs the script on the
-- current buffer's file. See scripts/md2pdf.

local M = {}

local function notify(msg, level)
  vim.notify("[markpreview] " .. msg, level or vim.log.levels.INFO)
end

---Export the current markdown buffer.
---@param fmt string|nil  "pdf" (default) or "html"
---@param opts table|nil  { open = boolean } — open the result when done
function M.export(fmt, opts)
  fmt = fmt or "pdf"
  opts = opts or {}
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    notify("buffer has no file on disk — save it first", vim.log.levels.WARN)
    return
  end

  local exe = vim.fn.exepath("md2pdf")
  if exe == "" then
    notify("md2pdf not found on PATH (symlink scripts/md2pdf into ~/.local/bin)", vim.log.levels.ERROR)
    return
  end
  if vim.fn.executable("pandoc") == 0 then
    notify("pandoc is required but not installed", vim.log.levels.ERROR)
    return
  end

  -- Persist pending changes so the export reflects what's on screen.
  if vim.bo.modified then
    vim.cmd("silent keepalt write")
  end

  -- md2pdf writes alongside the input: <name>.pdf, or <name>.html for html.
  local result = vim.fn.fnamemodify(file, ":r") .. (fmt == "html" and ".html" or ".pdf")
  local args = { exe, file }
  if fmt == "html" then
    table.insert(args, "--html-only")
  end

  notify("exporting to " .. fmt .. " …")
  vim.system(args, { text = true }, function(res)
    vim.schedule(function()
      local out = ((res.stdout or "") .. (res.stderr or "")):gsub("%s+$", "")
      if res.code ~= 0 then
        notify("export failed: " .. (out ~= "" and out or ("exit " .. res.code)), vim.log.levels.ERROR)
        return
      end
      notify(out ~= "" and out or ("exported to " .. fmt))
      if opts.open and vim.fn.filereadable(result) == 1 then
        local _, oerr = vim.ui.open(result)
        if oerr then
          notify("exported, but could not open it: " .. oerr, vim.log.levels.WARN)
        end
      end
    end)
  end)
end

return M
