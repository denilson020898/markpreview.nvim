-- markpreview.wrap
-- No-wrap by default for markdown, with comfortable horizontal scrolling and a
-- toggle that flips to soft, word-aware wrapping when you want it.

local M = {}

---Apply the configured wrap/scroll options to a window. Note: `sidescroll`
---is a global option and is handled once in markpreview.setup(), not here.
---@param win integer  -- window handle (0 = current)
---@param cfg table    -- markpreview `wrap` config
function M.apply(win, cfg)
  win = (win == nil or win == 0) and vim.api.nvim_get_current_win() or win
  local set = function(name, value)
    vim.api.nvim_set_option_value(name, value, { win = win })
  end
  set("wrap", cfg.wrap)
  set("linebreak", cfg.linebreak)
  set("breakindent", cfg.breakindent)
  set("sidescrolloff", cfg.sidescrolloff)
end

---Toggle wrap in the current window. When turning wrap on, also enable
---word-aware soft wrapping (linebreak + breakindent) so prose reads cleanly.
function M.toggle()
  local on = not vim.wo.wrap
  vim.wo.wrap = on
  if on then
    vim.wo.linebreak = true
    vim.wo.breakindent = true
  end
  vim.notify("[markpreview] wrap " .. (on and "ON" or "OFF"), vim.log.levels.INFO)
end

return M
