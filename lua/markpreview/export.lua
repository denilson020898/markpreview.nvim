-- markpreview.export
-- Thin, async bridge to the standalone `md2pdf` script (markdown -> styled
-- self-contained HTML via pandoc -> PDF via a headless Chromium browser).
-- The plugin does not reimplement the pipeline; it just runs the script on the
-- current buffer's file. See scripts/md2pdf.

local M = {}

local function notify(msg, level)
  vim.notify("[markpreview] " .. msg, level or vim.log.levels.INFO)
end

---Export the current markdown buffer. `fmt` is "pdf" (default) or "html".
function M.export(fmt)
  fmt = fmt or "pdf"
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

  local args = { exe, file }
  if fmt == "html" then
    table.insert(args, "--html-only")
  end

  notify("exporting to " .. fmt .. " …")
  vim.system(args, { text = true }, function(res)
    vim.schedule(function()
      local out = ((res.stdout or "") .. (res.stderr or "")):gsub("%s+$", "")
      if res.code == 0 then
        notify(out ~= "" and out or ("exported to " .. fmt))
      else
        notify("export failed: " .. (out ~= "" and out or ("exit " .. res.code)), vim.log.levels.ERROR)
      end
    end)
  end)
end

return M
