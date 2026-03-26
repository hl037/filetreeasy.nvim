local treeasy = require("treeasy")
local tree_m  = treeasy.tree
local node_m  = treeasy.node

local M = {}

-- ── devicons (module-level cache, shared across all views) ───────────────────

local _devicons            = nil
local _icon_hls_registered = {}

local function get_devicons()
  if _devicons ~= nil then return _devicons end
  local ok, d = pcall(require, "nvim-web-devicons")
  _devicons = ok and d or false
  return _devicons
end

local function file_icon(node, fte)
  if fte.devicons then
    local d = get_devicons()
    if d then
      local icon, hl = d.get_icon(node.name, nil, { default = true })
      if icon and hl then
        if not _icon_hls_registered[hl] then
          local def = vim.api.nvim_get_hl(0, { name = hl, link = false })
          if def and next(def) then treeasy.set_colors("filetreeasy", { [hl] = def }) end
          _icon_hls_registered[hl] = true
        end
        return "<c:" .. hl .. ">" .. icon .. "</c> "
      end
    end
  end
  local fi = fte.icons.file
  return (fi and fi ~= "") and (fi .. " ") or ""
end

-- ── buffer state ──────────────────────────────────────────────────────────────

local function buf_state(node, fte)
  local bufnr = vim.fn.bufnr(node.path)
  if bufnr == -1 then return nil end
  local ok, modified = pcall(function() return vim.bo[bufnr].modified end)
  local is_current = fte.current_buf == bufnr
  local visible = false
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then visible = true; break end
  end
  return { modified = ok and modified or false, current = is_current, visible = visible }
end

-- ── label pipeline ────────────────────────────────────────────────────────────

local function build_label(node, fte, view)
  local label = node.name
  for _, fn in ipairs(fte.label_fns) do
    label = fn(node, label, view)
  end
  return label
end

-- ── text generation ───────────────────────────────────────────────────────────

local function make_text(node, view, is_open)
  local fte    = view._filetreeasy
  local prefix = node.is_dir
    and (is_open and fte.icons.dir_open or fte.icons.dir_closed)
    or  file_icon(node, fte)

  local label  = build_label(node, fte, view)
  local suffix = ""

  if node.is_link then
    label  = "<c:symlink>" .. label .. "</c>"
    suffix = " <c:symlink>-> " .. (node.link_target or "?") .. "</c>"
  elseif node.is_dir then
    label = "<c:dir>" .. label .. "</c>"
  else
    local st = buf_state(node, fte)
    if st then
      if st.current then
        label = "<c:current>" .. label .. "</c>"
      elseif st.visible then
        label = "<c:visible>" .. label .. "</c>"
      end
      if st.modified then
        suffix = suffix .. " <c:modified>" .. fte.icons.modified .. "</c>"
      end
    end
  end

  return { prefix .. label .. suffix }
end

-- ── plugin handler dispatch ───────────────────────────────────────────────────

local function run_plugin_handlers(event, node, view, ctx)
  local handlers = view._filetreeasy.plugin_handlers[event]
  if not handlers then return false end
  for _, fn in ipairs(handlers) do
    if fn(node, view, ctx) then return true end
  end
  return false
end

-- ── shared handlers (one function per type, no closures) ─────────────────────

local function h_dir_open(node, view, ctx)
  run_plugin_handlers("open", node, view, ctx)
  if node.children ~= nil then return end
  M.load_children(node, view)
end

local function h_dir_collapse(node, view, ctx)
  run_plugin_handlers("collapse", node, view, ctx)
  require("filetreeasy.watcher").unwatch(node.path)
end

local function h_dir_enter(node, view, ctx)
  run_plugin_handlers("enter", node, view, ctx)
  view:_handle_event("toggle_collapse", node, ctx)
end

local function h_dir_click(node, view, ctx)
  run_plugin_handlers("click", node, view, ctx)
  view:_handle_event("toggle_collapse", node, ctx)
end

local function h_file_enter(node, view, ctx)
  if ctx.label_pos.col_index < 0 then return end
  if run_plugin_handlers("enter", node, view, ctx) then return end
  M.open_file(node, view)
end

local function h_file_click(node, view, ctx)
  if ctx.label_pos.col_index < 0 then return end
  if run_plugin_handlers("click", node, view, ctx) then return end
  M.open_file(node, view)
end

local function h_menu(node, view)
  require("filetreeasy.fs_ops").open_menu(node, view)
end

-- Close all buffers under an alt root, with save confirmation, then remove root.
local function close_alt_root(node, view)
  local bufs_to_close = {}
  local modified = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local path = vim.api.nvim_buf_get_name(buf)
      if path ~= "" and (path == node.path or path:sub(1, #node.path + 1) == node.path .. "/") then
        table.insert(bufs_to_close, buf)
        if vim.bo[buf].modified then table.insert(modified, buf) end
      end
    end
  end

  local function do_close()
    for _, buf in ipairs(bufs_to_close) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    require("filetreeasy.roots").remove(node.path)
    require("filetreeasy").reload()
  end

  if #modified == 0 then
    do_close()
  else
    local names = table.concat(vim.tbl_map(function(b)
      return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t")
    end, modified), ", ")
    vim.ui.input({
      prompt = #modified .. " unsaved file(s): " .. names .. ". Close anyway? [y/N]: "
    }, function(ans)
      if ans and ans:lower() == "y" then do_close() end
    end)
  end
end

-- ── alt root shared handlers ─────────────────────────────────────────────────

local function h_alt_open(node, view, ctx)
  run_plugin_handlers("open", node, view, ctx)
  if node.children ~= nil then return end
  M.load_children(node, view)
end

local function h_alt_collapse(node, view, ctx)
  run_plugin_handlers("collapse", node, view, ctx)
  require("filetreeasy.watcher").unwatch(node.path)
end

local function h_alt_enter(node, view, ctx)
  run_plugin_handlers("enter", node, view, ctx)
  view:_handle_event("toggle_collapse", node, ctx)
end

local function h_alt_click(node, view, ctx)
  if ctx.label_pos.col_index < 0 then return end
  for _, area in ipairs(ctx.areas or {}) do
    if area == "delete_root" then
      close_alt_root(node, view)
      return true
    end
  end
  run_plugin_handlers("click", node, view, ctx)
  view:_handle_event("toggle_collapse", node, ctx)
end

-- ── alt root text ─────────────────────────────────────────────────────────────

local function alt_root_open_text(node)
  local path_tag = "<c:ft_root_path>" .. node.path .. "</c>"
  return { "", "<c:ft_root_delete><a:delete_root>[X]</a></c> " .. path_tag }
end

local function alt_root_collapsed_text(node)
  local path_tag = "<c:ft_root_path>" .. node.path .. "</c>"
  return { "", "<c:ft_root_delete><a:delete_root>[X]</a></c> " .. path_tag }
end

-- ── public: make alt root node ────────────────────────────────────────────────

function M.make_alt_root_node(root_path, parent, index)
  root_path = vim.fn.fnamemodify(root_path, ":p"):gsub("/$", "")

  -- Count buffers already open under this path.
  local buf_count = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local p = vim.api.nvim_buf_get_name(buf)
      if p ~= "" and (p == root_path or p:sub(1, #root_path + 1) == root_path .. "/") then
        buf_count = buf_count + 1
      end
    end
  end
  local n = node_m.new({ parent = parent, index = index })
  n.path          = root_path
  n.name          = vim.fn.fnamemodify(root_path, ":t")
  n.filename      = n.name
  n.is_dir        = true
  n.is_root_ghost = true
  n.is_alt        = true
  n.deletable     = true
  n.buf_count     = buf_count
  n.children      = nil  -- lazy
  n.open_text      = alt_root_open_text
  n.collapsed_text = alt_root_collapsed_text
  n.handler["open"]     = h_alt_open
  n.handler["collapse"] = h_alt_collapse
  n.handler["enter"]    = h_alt_enter
  n.handler["click"]    = h_alt_click
  n.handler["menu"]     = h_menu
  return n
end

-- ── shared text wrappers ──────────────────────────────────────────────────────
-- open_text / collapsed_text receive (node, view) per treeasy API.

local function dir_open_text(node, view)      return make_text(node, view, true)  end
local function dir_collapsed_text(node, view) return make_text(node, view, false) end
local function file_text(node, view)          return make_text(node, view, false) end

-- ── node constructor ──────────────────────────────────────────────────────────

local function make_node(parent, name, path, is_dir, index, fte)
  local n = node_m.new({ parent = parent, index = index })
  n.path     = path
  n.name     = name
  n.filename = name
  n.is_dir   = is_dir

  if is_dir then
    n.children       = nil
    n.open_text      = dir_open_text
    n.collapsed_text = dir_collapsed_text
    n.handler["open"]     = h_dir_open
    n.handler["collapse"] = h_dir_collapse
    n.handler["enter"]    = h_dir_enter
    n.handler["click"]    = h_dir_click
  else
    n.open_text      = file_text
    n.collapsed_text = file_text
    n.handler["enter"] = h_file_enter
    n.handler["click"] = h_file_click
  end
  n.handler["menu"] = h_menu

  return n
end

-- ── public API ────────────────────────────────────────────────────────────────

function M.load_children(node, view)
  local fte     = view._filetreeasy
  node.children = {}
  local ok, entries = pcall(vim.fn.readdir, node.path)
  if not ok or type(entries) ~= "table" then return end

  local dirs, files = {}, {}
  for _, name in ipairs(entries) do
    if name ~= "." and name ~= ".." then
      local p    = node.path .. "/" .. name
      local stat = vim.loop.fs_lstat(p)
      if stat then
        local is_link     = stat.type == "link"
        local link_target = nil
        local real_type   = stat.type
        if is_link then
          link_target = vim.loop.fs_readlink(p)
          local rs = vim.loop.fs_stat(p)
          real_type = rs and rs.type or "file"
        end
        local t = { name = name, path = p, is_link = is_link, link_target = link_target }
        if real_type == "directory" then
          table.insert(dirs, t)
        else
          table.insert(files, t)
        end
      end
    end
  end

  table.sort(dirs,  function(a, b) return a.name < b.name end)
  table.sort(files, function(a, b) return a.name < b.name end)

  local idx = 1
  for _, e in ipairs(dirs) do
    local n = make_node(node, e.name, e.path, true, idx, fte)
    n.is_link = e.is_link; n.link_target = e.link_target
    node.children[idx] = n; idx = idx + 1
  end
  for _, e in ipairs(files) do
    local n = make_node(node, e.name, e.path, false, idx, fte)
    n.is_link = e.is_link; n.link_target = e.link_target
    node.children[idx] = n; idx = idx + 1
  end

  -- Watch this directory; fire hooks on change.
  require("filetreeasy.watcher").watch(node.path, function(dir_path)
    if not node.children then return end
    require("filetreeasy.watcher").unwatch(node.path)
    node.children = nil
    M.load_children(node, view)
    tree_m.update_node(node)
    for _, fn in ipairs(fte.hooks.fs_change) do fn(dir_path) end
  end)
end

-- Walk all currently-loaded file/dir nodes in the tree (skip ghosts/headers).
-- fn(node) is called on each node; return true to stop early.
function M.walk_loaded(view, fn)
  local builder = require("filetreeasy.tree_builder")
  local function recurse(node)
    if node.path and not node.ghost then
      if fn(node) then return true end
    end
    if node.children then
      for _, child in ipairs(node.children) do
        if recurse(child) then return true end
      end
    end
  end
  for _, rg in ipairs(builder.get_root_nodes(view)) do
    local fs_ghost = builder.get_fs_ghost(rg)
    if fs_ghost then recurse(fs_ghost) end
  end
end

-- Find the loaded node matching path exactly, or nil.
function M.find_loaded_node(view, path)
  local found
  M.walk_loaded(view, function(node)
    if node.path == path then found = node; return true end
  end)
  return found
end

function M.clear_loaded()
  _icon_hls_registered = {}
end

function M.open_file(node, view)
  -- If the file is already visible in a window, just focus it.
  local bufnr = vim.fn.bufnr(node.path)
  if bufnr ~= -1 then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == bufnr and win ~= view.window then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
  end
  -- Use last known edit window, fallback to get_edit_win.
  local fte = view._filetreeasy
  local win = fte.last_win
  if not win or not vim.api.nvim_win_is_valid(win) or win == view.window then
    win = M.get_edit_win(view)
  end
  if win then
    vim.api.nvim_set_current_win(win)
    vim.cmd("edit " .. vim.fn.fnameescape(node.path))
  else
    vim.cmd("vsplit " .. vim.fn.fnameescape(node.path))
  end
end

function M.get_edit_win(view)
  local tree_win = view and view.window
  local cur = vim.api.nvim_get_current_win()
  if cur ~= tree_win then
    local bt = vim.bo[vim.api.nvim_win_get_buf(cur)].buftype
    if bt == "" or bt == "acwrite" then return cur end
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= tree_win then
      local bt = vim.bo[vim.api.nvim_win_get_buf(win)].buftype
      if bt == "" or bt == "acwrite" then return win end
    end
  end
  return nil
end

return M
