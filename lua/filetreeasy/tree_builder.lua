local treeasy = require("treeasy")
local tree_m  = treeasy.tree
local node_m  = treeasy.node

local M = {}
local CLASS = "filetreeasy"

local _class_ready = false

local CORE_COLORS = {
  dir      = { fg = "#7aa2f7" },
  symlink  = { italic = true },
  header   = { fg = "#565f89", bold = true },
  current  = { fg = "#ffffff", bold = true },
  visible  = { fg = "#c0caf5" },
  modified = { fg = "#e0af68" },
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
        for name, def in pairs(p.default_colors) do
          colors[name] = def
        end
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

function M.build(roots_list, fte)
  setup_class(fte.plugins)

  local nf = require("filetreeasy.node_factory")
  M.clear_tree(fte)

  local ghost = node_m.new()
  ghost.ghost    = true
  ghost.children = {}

  for i, root_path in ipairs(roots_list) do
    local rnode = nf.new_root_node(root_path, ghost, i, fte)
    ghost.children[i] = rnode
  end

  return tree_m.new({ class = CLASS, root = ghost })
end

function M.clear_tree(fte)
  require("filetreeasy.node_factory").clear_index(fte)
  require("filetreeasy.watcher").unwatch_all()
end

function M.open_window(tree, fte)
  local cmd = fte.side == "right" and "botright" or "topleft"
  vim.cmd(cmd .. " " .. fte.width .. "vsplit")
  local win  = vim.api.nvim_get_current_win()
  local view = treeasy.attach_tree(win, tree)

  view._filetreeasy = fte

  require("filetreeasy.views").register(view)

  -- Core calls init(view) on each plugin — that's it.
  -- Plugins self-register into fte.label_fns, fte.plugin_handlers, fte.hooks.
  for _, p in ipairs(fte.plugins) do
    if p.init then p.init(view) end
  end

  return view
end

function M.expand_roots(tree, view)
  local ghost = tree.root
  if not ghost or not ghost.children then return end
  for _, rnode in ipairs(ghost.children) do
    view:set_open(rnode, true)
  end
end

return M
