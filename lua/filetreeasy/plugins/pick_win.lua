-- Pick-window plugin.
-- Registers itself entirely in init(view).

local M = {}

local CLASS  = "filetreeasy"
M.default_colors = {
  pick_win        = { fg = "#414868" },
  pick_win_active = { fg = "#e0af68", bold = true },
}

-- ── per-view helpers ──────────────────────────────────────────────────────────

local function state(view)
  return view._filetreeasy.pick_win  -- guaranteed set in init
end

local function update_node(path, view)
  local node = view._filetreeasy.node_index[path]
  if node then require("treeasy").tree.update_node(node) end
end

local function disarm(view)
  local s = state(view)
  if s.aug then pcall(vim.api.nvim_del_augroup_by_id, s.aug); s.aug = nil end
  s.path = nil
end

local function cancel(view)
  local s = state(view)
  if not s.path then return end
  local prev = s.path
  disarm(view)
  update_node(prev, view)
end

local function arm(path, view)
  local s = state(view)
  if s.path == path then cancel(view); return end
  local prev = s.path
  disarm(view)
  if prev then update_node(prev, view) end

  s.path = path
  s.aug  = vim.api.nvim_create_augroup(
    "filetreeasy_pick_win_" .. view.window, { clear = true }
  )
  vim.api.nvim_create_autocmd("WinEnter", {
    group    = s.aug,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      if win == view.window then return end
      local bt = vim.bo[vim.api.nvim_win_get_buf(win)].buftype
      if bt == "" or bt == "acwrite" then
        local p = s.path
        disarm(view)
        vim.cmd("edit " .. vim.fn.fnameescape(p))
        update_node(p, view)
      end
      return true
    end,
  })
  update_node(path, view)
end

-- ── init ──────────────────────────────────────────────────────────────────────

function M.init(view)
  local fte = view._filetreeasy

  -- Per-view state.
  fte.pick_win = { path = nil, aug = nil }

  -- Label function: appended to fte.label_fns.
  table.insert(fte.label_fns, function(node, label, v)
    if node.is_dir or not v then return label end
    local s = v._filetreeasy.pick_win
    if s and s.path == node.path then
      return label .. " <a:pick_win><c:pick_win_active>[[♠]]</c></a>"
    end
    return label .. " <a:pick_win><c:pick_win> [♠] </c></a>"
  end)

  -- Treeasy event handlers: registered in fte.plugin_handlers.
  local function add_handler(event, fn)
    if not fte.plugin_handlers[event] then fte.plugin_handlers[event] = {} end
    table.insert(fte.plugin_handlers[event], fn)
  end

  add_handler("click", function(node, v, ctx)
    for _, area in ipairs(ctx.areas or {}) do
      if area == "pick_win" then arm(node.path, v); return true end
    end
    cancel(v)
  end)
  add_handler("enter",    function(_, v) cancel(v) end)
  add_handler("open",     function(_, v) cancel(v) end)
  add_handler("collapse", function(_, v) cancel(v) end)
end

return M
