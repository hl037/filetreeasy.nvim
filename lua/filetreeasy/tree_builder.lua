local treeasy = require("treeasy")
local tree_m  = treeasy.tree
local node_m  = treeasy.node

local M = {}
local CLASS = "filetreeasy"

local _class_ready = false

local CORE_COLORS = {
  dir            = { fg = "#7aa2f7" },
  symlink        = { italic = true },
  current        = { fg = "#ffffff", bold = true },
  visible        = { fg = "#c0caf5" },
  modified       = { fg = "#e0af68" },
  ft_header      = { fg = "#565f89", bold = true },
  ft_root_path   = { fg = "#7aa2f7", bold = true },
  ft_root_delete = { fg = "#f7768e", bold = true },
}

local function setup_class(plugins)
  if _class_ready then return end
  _class_ready = true

  if not treeasy.get_keymap(CLASS) then
    treeasy.set_keymap(CLASS, {
      toggle_collapse = { "<CR>" },
      click           = { "<LeftRelease>" },
      open_rec        = { "<S-CR>" },
      menu            = { "m" },
    })
  end

  if treeasy.get_colors(CLASS) == nil then
    local colors = vim.deepcopy(CORE_COLORS)
    for _, p in ipairs(plugins) do
      if p.default_colors then
        for name, def in pairs(p.default_colors) do colors[name] = def end
      end
    end
    treeasy.set_colors(CLASS, colors)
  end

  if not treeasy.get_symbols(CLASS) then
    treeasy.set_symbols(CLASS, {
      mid = "  ", last = "  ", vert = "  ", space = "  ",
    })
  end
end

-- ── root header ───────────────────────────────────────────────────────────────

local function root_header_text(node, view)
  local rg = node._root_ghost
  local path_tag = "<c:ft_root_path>" .. rg.path .. "</c>"
  local line = rg.deletable
    and ("<c:ft_root_delete><a:delete_root>[X]</a></c> " .. path_tag)
    or  path_tag
  return { "", line }
end

local function make_root_header(root_ghost, parent, index)
  local n = node_m.new({ parent = parent, index = index })
  n._root_ghost    = root_ghost
  n.open_text      = root_header_text
  n.collapsed_text = root_header_text
  n.handler["click"] = function(node, view, ctx)
    for _, area in ipairs(ctx.areas or {}) do
      if area == "delete_root" then
        require("filetreeasy.roots").remove(node._root_ghost.path)
        require("filetreeasy").reload()
        return true
      end
    end
  end
  return n
end

-- ── root section ──────────────────────────────────────────────────────────────
--
-- Structure:
--   fte_ghost  (ghost, is_root_ghost, path, deletable, buf_count)
--     root_header
--     fs_ghost   (ghost, path — children loaded by expand_roots / load_children)

local function make_root_section(root_path, parent, index, deletable)
  root_path = vim.fn.fnamemodify(root_path, ":p"):gsub("/$", "")

  -- fte dir ghost
  local fte_ghost = node_m.new({ parent = parent, index = index })
  fte_ghost.ghost         = true
  fte_ghost.is_root_ghost = true
  fte_ghost.path          = root_path
  fte_ghost.deletable     = deletable or false
  fte_ghost.buf_count     = 0
  fte_ghost.children      = {}

  -- header (child 1)
  local header = make_root_header(fte_ghost, fte_ghost, 1)
  fte_ghost.children[1] = header

  -- fs ghost (child 2) — a ghost whose children = contents of root_path
  local fs_ghost = node_m.new({ parent = fte_ghost, index = 2 })
  fs_ghost.ghost    = true
  fs_ghost.path     = root_path
  fs_ghost.name     = vim.fn.fnamemodify(root_path, ":t")
  fs_ghost.filename = fs_ghost.name
  fs_ghost.is_dir   = true   -- so load_children works on it
  fs_ghost.children = nil    -- loaded by expand_roots
  fte_ghost.children[2] = fs_ghost

  return fte_ghost, fs_ghost
end

-- ── public API ────────────────────────────────────────────────────────────────

function M.build(roots_list, fte, deletable_set)
  setup_class(fte.plugins)
  M.clear_tree(fte)

  deletable_set = deletable_set or {}

  local ghost = node_m.new()
  ghost.ghost    = true
  ghost.children = {}

  local plugin_header = node_m.new({ parent = ghost, index = 1 })
  plugin_header.open_text      = function() return { "<c:ft_header>FileTreeasy.nvim</c>" } end
  plugin_header.collapsed_text = plugin_header.open_text
  ghost.children[1] = plugin_header

  local nf = require("filetreeasy.node_factory")
  for i, root_path in ipairs(roots_list) do
    local node
    if deletable_set[root_path] then
      -- Alt root: simple collapsible node, children loaded lazily.
      node = nf.make_alt_root_node(root_path, ghost, i + 1)
    else
      -- Main root: fte_ghost > header + fs_ghost structure.
      node = make_root_section(root_path, ghost, i + 1, false)
    end
    ghost.children[i + 1] = node
  end

  local t = tree_m.new({ class = CLASS, root = ghost })
  fte.tree = t
  return t
end

function M.get_root_nodes(view)
  local ghost = view._filetreeasy.tree and view._filetreeasy.tree.root
  if not ghost or not ghost.children then return {} end
  local result = {}
  for _, child in ipairs(ghost.children) do
    if child.is_root_ghost then result[#result + 1] = child end
  end
  return result
end

-- For main roots: fs_ghost is children[2] of the fte_ghost.
-- For alt roots: the node itself holds children directly.
function M.get_fs_ghost(rg)
  if rg.is_alt then return rg end
  return rg.children and rg.children[2]
end

function M.clear_tree(fte)
  require("filetreeasy.node_factory").clear_loaded()
  require("filetreeasy.watcher").unwatch_all()
end

function M.open_window(tree, fte)
  local cmd = fte.side == "right" and "botright" or "topleft"
  vim.cmd(cmd .. " " .. fte.width .. "vsplit")
  local win  = vim.api.nvim_get_current_win()
  local view = treeasy.attach_tree(win, tree)
  view._filetreeasy = fte
  require("filetreeasy.views").register(view)
  for _, p in ipairs(fte.plugins) do
    if p.init then p.init(view) end
  end
  return view
end

function M.expand_roots(tree, view)
  local nf = require("filetreeasy.node_factory")
  for _, rg in ipairs(M.get_root_nodes(view)) do
    local fs = M.get_fs_ghost(rg)
    if fs then
      if rg.is_alt then
        -- Alt root: trigger open handler to lazy-load + expand.
        view:set_open(rg, true)
      else
        nf.load_children(fs, view)
      end
    end
  end
end

return M
