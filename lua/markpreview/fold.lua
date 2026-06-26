-- markpreview.fold
-- Heading-based folding for markdown using a cached `foldexpr`.
--
-- Folds nest by ATX heading depth (`#` = 1 .. `######` = 6) and, optionally,
-- by setext headings (a paragraph line underlined with `===` or `---`).
-- Fenced code blocks and YAML/TOML frontmatter are skipped so that `#`
-- comments inside code or `---` separators don't create phantom folds.
--
-- The per-line fold levels are computed once per buffer change (keyed by
-- `changedtick`) and cached, so the `foldexpr` itself is a cheap table lookup.

local M = {}

-- Set by markpreview.setup(); see markpreview defaults.
M.config = {
  setext = true,
  fold_text = true,
}

-- bufnr -> { tick = <changedtick>, levels = { [lnum] = "<foldexpr value>" } }
local cache = {}

---Is `line` the opening of a fenced code block? Returns the fence char and
---run length, or nil. Up to 3 leading spaces are allowed (CommonMark).
local function fence_open(line)
  local indent, ticks = line:match("^(%s*)(`+)")
  if ticks and #indent <= 3 and #ticks >= 3 then
    return "`", #ticks
  end
  local indent2, tildes = line:match("^(%s*)(~+)")
  if tildes and #indent2 <= 3 and #tildes >= 3 then
    return "~", #tildes
  end
  return nil
end

---ATX heading level for `line` (1..6) or 0 if it is not a heading.
local function atx_level(line)
  local hashes, rest = line:match("^ ? ? ?(#+)(.*)$")
  if hashes and #hashes <= 6 then
    -- A heading marker must be followed by whitespace or end-of-line.
    if rest == "" or rest:sub(1, 1):match("%s") then
      return #hashes
    end
  end
  return 0
end

---Can `raw` be the text of a setext heading? Only ordinary paragraph text
---qualifies — not a heading, blockquote, list item, table row, fenced/indented
---code, or a `===`/`---` underline itself. Used both to decide eligibility and
---to walk back to the first line of a multi-line setext heading.
local function is_para_text(raw)
  if raw == nil then
    return false
  end
  if raw:match("^    ") or raw:match("^\t") then
    return false -- indented code block
  end
  local t = vim.trim(raw)
  if t == "" or t == "+++" then
    return false
  end
  if atx_level(raw) > 0 then
    return false -- ATX heading
  end
  if t:match("^=+$") or t:match("^%-+$") then
    return false -- a setext underline / thematic break, not paragraph text
  end
  if t:find("|") ~= nil then
    return false -- table row
  end
  if t:match("^>") or t:match("^[-*+]%s") or t:match("^%d+[.)]%s") then
    return false -- blockquote / bullet / ordered list
  end
  if t:match("^```") or t:match("^~~~") then
    return false -- fenced code marker
  end
  return true
end

---Compute the `foldexpr` value for every line in `buf`.
---@param buf integer
---@return table<integer,string>
local function compute(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local n = #lines
  local hl = {} -- heading level per 1-indexed line (0 = none)
  for i = 1, n do
    hl[i] = 0
  end

  -- Frontmatter: a leading `---` (or `+++`) fence delimited block. Lines
  -- 1..front_end are ignored for heading detection.
  local front_end = 0
  if n >= 1 then
    local first = vim.trim(lines[1])
    if first == "---" or first == "+++" then
      for i = 2, n do
        if vim.trim(lines[i]) == first then
          front_end = i
          break
        end
      end
    end
  end

  local in_fence = false
  local fchar, flen = nil, 0
  local setext = M.config.setext

  for i = 1, n do
    if i > front_end then
      local line = lines[i]
      if in_fence then
        -- A closing fence: same char, run length >= opening, nothing but the
        -- fence chars (and trailing whitespace) on the line.
        local indent, run = line:match("^(%s*)([`~]+)%s*$")
        if run and #indent <= 3 and run:sub(1, 1) == fchar and #run >= flen then
          in_fence = false
        end
      else
        local fc, fl = fence_open(line)
        if fc then
          in_fence = true
          fchar, flen = fc, fl
        else
          local lvl = atx_level(line)
          if lvl > 0 then
            hl[i] = lvl
          elseif setext and i > 1 and i - 1 > front_end and hl[i - 1] == 0 then
            -- A setext underline turns the WHOLE preceding paragraph into a
            -- heading. Fold from the paragraph's first line, not the last.
            local level = 0
            if line:match("^=+%s*$") then
              level = 1
            elseif line:match("^%-+%s*$") then
              level = 2
            end
            if level > 0 and is_para_text(lines[i - 1]) then
              local start = i - 1
              while start - 1 > front_end and hl[start - 1] == 0 and is_para_text(lines[start - 1]) do
                start = start - 1
              end
              hl[start] = level
            end
          end
        end
      end
    end
  end

  local levels = {}
  for i = 1, n do
    levels[i] = hl[i] > 0 and (">" .. hl[i]) or "="
  end
  return levels
end

---`foldexpr` entry point. Wired up as `v:lua.require'markpreview.fold'.expr()`.
function M.expr()
  local buf = vim.api.nvim_get_current_buf()
  -- Guard: a window may keep `foldexpr` after switching to a non-markdown
  -- buffer. Only compute heading folds for buffers we actually attached to.
  if not vim.b[buf].markpreview_attached then
    return "0"
  end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local c = cache[buf]
  if not c or c.tick ~= tick then
    c = { tick = tick, levels = compute(buf) }
    cache[buf] = c
  end
  return c.levels[vim.v.lnum] or "="
end

---A compact, readable fold label. Wired up as the window `foldtext`.
function M.foldtext()
  local first = vim.fn.getline(vim.v.foldstart)
  local hashes = first:match("^%s*(#+)") or ""
  local title = vim.trim((first:gsub("^%s*#+%s*", "")))
  if title == "" then
    title = vim.trim(first)
  end
  local count = vim.v.foldend - vim.v.foldstart + 1
  local marker = #hashes > 0 and hashes or "▸"
  return string.format("%s %s  (%d lines) ", marker, title, count)
end

---Drop the cache for a buffer (called on BufDelete/BufWipeout).
function M.clear(buf)
  cache[buf] = nil
end

return M
