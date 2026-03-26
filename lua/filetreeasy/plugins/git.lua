-- Git status plugin.
-- Registers itself entirely in init(view).

local M = {}

local CLASS  = "filetreeasy"
M.default_colors = {
  git_staged        = { fg = "#9ece6a" },
  git_modified      = { fg = "#e0af68" },
  git_untracked     = { fg = "#7dcfff" },
  git_ignored       = { fg = "#565f89" },
  git_conflict      = { fg = "#f7768e" },
  git_conflict_name = { fg = "#f7768e", underline = true },
  git_deleted       = { fg = "#f7768e" },
  git_renamed       = { fg = "#bb9af7" },
}

local ICONS = {
  staged = "●", modified = "✚", deleted = "✖", renamed = "➜",
  untracked = "?", ignored = "◌", conflict = "═",
}

-- ── git helpers (module-level, shared across views) ───────────────────────────

local _root_cache = {}  -- dir -> git_root|false

local function git_root_of(dir)
  if _root_cache[dir] ~= nil then return _root_cache[dir] end
  local out  = vim.fn.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" })
  local root = vim.v.shell_error == 0 and vim.trim(out) or false
  _root_cache[dir] = root
  return root
end

local function xy_to_status(x, y)
  if (x=="D" and y=="D") or (x=="A" and y=="A") or x=="U" or y=="U" then return "conflict" end
  if x=="?" and y=="?" then return "untracked" end
  if x=="!" and y=="!" then return "ignored"   end
  if y=="D"            then return "deleted"   end
  if y=="M" or y=="T"  then return "modified"  end
  if x=="R"            then return "renamed"   end
  if x~=" " and x~="?" then return "staged"   end
end

local function parse_status(git_root)
  local out = vim.fn.system({ "git", "-C", git_root, "status", "--porcelain", "-u", "--ignored" })
  if vim.v.shell_error ~= 0 then return {} end
  local result = {}
  for line in out:gmatch("[^\n]+") do
    local x, y, path = line:match("^(.)(.) (.+)$")
    if x and y and path then
      local actual = path:match("^.+ %-> (.+)$") or path
      local status = xy_to_status(x, y)
      if status then result[git_root .. "/" .. actual] = status end
    end
  end
  return result
end

-- ── per-view helpers ──────────────────────────────────────────────────────────

local function gs(view)
  return view._filetreeasy.git  -- guaranteed set in init
end

local function get_statuses(view, git_root)
  local g = gs(view)
  if not g.statuses[git_root] or g.dirty[git_root] then
    g.statuses[git_root] = parse_status(git_root)
    g.dirty[git_root]    = false
  end
  return g.statuses[git_root]
end

local function status_of(path, view)
  local root = git_root_of(vim.fn.fnamemodify(path, ":h"))
  if not root then return nil end
  return get_statuses(view, root)[path]
end

local function refresh_changed(view)
  local fte    = view._filetreeasy
  local tree_m = require("treeasy").tree
  local g      = gs(view)
  for root in pairs(g.statuses) do g.dirty[root] = true end
  for _, node in pairs(fte.node_index) do
    if not node.is_dir then
      local new_status = status_of(node.path, view)
      if new_status ~= node._git_status then
        node._git_status = new_status
        tree_m.update_node(node)
      end
    end
  end
end

-- ── init ──────────────────────────────────────────────────────────────────────

function M.init(view)
  local fte = view._filetreeasy

  -- Per-view state.
  fte.git = { statuses = {}, dirty = {} }

  -- Label function.
  table.insert(fte.label_fns, function(node, label, v)
    local status = node._git_status
    if status == nil and v then
      status = status_of(node.path, v)
      node._git_status = status
    end
    if not status then return label end
    local icon_tag = "<c:git_" .. status .. ">" .. (ICONS[status] or "·") .. "</c> "
    if status == "conflict" then
      label = "<c:git_conflict_name>" .. label .. "</c>"
    end
    return icon_tag .. label
  end)

  -- Autocmds for external changes.
  local aug = vim.api.nvim_create_augroup(
    "filetreeasy_git_" .. view.window, { clear = true }
  )
  vim.api.nvim_create_autocmd({ "BufWritePost", "FocusGained", "ShellCmdPost" }, {
    group    = aug,
    callback = function() vim.schedule(function() refresh_changed(view) end) end,
  })

  -- Filetreeasy hooks.
  table.insert(fte.hooks.fs_change, function()
    vim.schedule(function() refresh_changed(view) end)
  end)
  table.insert(fte.hooks.root_change, function()
    _root_cache = {}
    fte.git = { statuses = {}, dirty = {} }
    vim.schedule(function() refresh_changed(view) end)
  end)
end

return M
