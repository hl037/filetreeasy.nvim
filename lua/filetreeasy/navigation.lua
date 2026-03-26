local M = {}

local function is_under(path, root)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

local function find_best_rg(path, view)
  local builder = require("filetreeasy.tree_builder")
  local best, blen = nil, 0
  for _, rg in ipairs(builder.get_root_nodes(view)) do
    local r = rg.path or ""
    if is_under(path, r) and #r > blen then best, blen = rg, #r end
  end
  return best
end

-- Walk path components through the tree starting from fs_ghost.children.
-- For each part: find matching child in current children list, then if there
-- are more parts, open that child (triggers lazy load) and descend.
local function walk_to(fs_ghost, parts, view)
  local nf = require("filetreeasy.node_factory")

  -- Ensure fs_ghost's children are loaded (may not be on a fresh rebuild).
  if not fs_ghost.children then
    nf.load_children(fs_ghost, view)
  end

  local children = fs_ghost.children
  if not children then return nil end

  local node
  for i, part in ipairs(parts) do
    node = nil
    for _, child in ipairs(children) do
      if child.filename == part then node = child; break end
    end
    if not node then return nil end
    if i < #parts then
      -- More parts remain: open this dir to load its children.
      if not node.is_dir then return nil end
      view:set_open(node, true)
      children = node.children
      if not children then return nil end
    end
  end
  return node
end

function M.reveal(path, view)
  if not view then return end

  local roots   = require("filetreeasy.roots")
  local ft      = require("filetreeasy")
  local builder = require("filetreeasy.tree_builder")

  path = vim.fn.fnamemodify(path, ":p"):gsub("/$", "")

  local rg

  -- 1. Global registry: deepest match already in view → nothing to do.
  --    If found but not yet displayed → add it as alt root.
  local global_root = roots.find_best(path)
  if global_root then
    rg = find_best_rg(path, view)
    if not rg then
      -- Add the global root as an alt root alongside existing ones.
      ft.add_alt_root(view, global_root)
      rg = find_best_rg(path, view)
    end
  end

  -- 2. File is under one of the currently displayed roots.
  if not rg then rg = find_best_rg(path, view) end

  -- 3. Not found anywhere: add parent as new alt root.
  if not rg then
    local parent = vim.fn.fnamemodify(path, ":h")
    roots.add(parent)
    ft.add_alt_root(view, parent)
    rg = find_best_rg(path, view)
    if not rg then return end
  end

  local fs_ghost = builder.get_fs_ghost(rg)
  if not fs_ghost then return end

  local rel = path:sub(#rg.path + 2)
  if rel == "" then
    if not view:is_node_visible(fs_ghost) then view:goto_node(fs_ghost) end
    return
  end

  local target = walk_to(fs_ghost, vim.split(rel, "/", { plain = true }), view)
  if target then
    if not view:is_node_visible(target) then
      view:goto_node(target)
    end
  end
end

return M
