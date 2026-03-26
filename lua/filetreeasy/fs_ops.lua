local M = {}

local function err(msg)  vim.notify("[filetreeasy] " .. msg, vim.log.levels.ERROR) end
local function info(msg) vim.notify("[filetreeasy] " .. msg, vim.log.levels.INFO)  end

local function parent_dir(path)  return vim.fn.fnamemodify(path, ":h") end
local function mkdir_p(path)     vim.fn.mkdir(path, "p") end

local function node_parent_path(node)
  return node.is_dir and node.path or parent_dir(node.path)
end

-- Reload the dir node and notify treeasy.
local function refresh(node, view)
  local target = node.is_dir and node or node.parent
  if not target then return end
  if target.children ~= nil then
    require("filetreeasy.watcher").unwatch(target.path)
    target.children = nil
    require("filetreeasy.node_factory").load_children(target, view)
    require("treeasy").tree.update_node(target)
  end
end

-- ── path input (full path editable in cmdline) ───────────────────────────────

local function input_path(prompt, default, cb)
  vim.ui.input({ prompt = prompt, default = default or "", completion = "file" }, cb)
end

local function confirm(prompt, cb)
  vim.ui.input({ prompt = prompt .. " [y/N]: " }, function(a)
    cb(a and a:lower() == "y")
  end)
end

-- ── operations ───────────────────────────────────────────────────────────────

local function do_add(node, view)
  local base = node_parent_path(node)
  input_path("Add (/ = dir): ", base .. "/", function(full)
    if not full or full == "" or full == base .. "/" then return end
    if full:sub(-1) == "/" then
      mkdir_p(full)
      info("Created dir: " .. full)
    else
      mkdir_p(parent_dir(full))
      if not pcall(vim.fn.writefile, {}, full) then
        err("Cannot create: " .. full)
      end
    end
    refresh(node, view)
  end)
end

local function do_move(node, view)
  input_path("Move to: ", node.path, function(dest)
    if not dest or dest == "" or dest == node.path then return end
    if not dest:find("/") then dest = parent_dir(node.path) .. "/" .. dest end
    mkdir_p(parent_dir(dest))
    if vim.fn.rename(node.path, dest) == 0 then
      local bufnr = vim.fn.bufnr(node.path)
      if bufnr ~= -1 then vim.api.nvim_buf_set_name(bufnr, dest) end
      info("Moved to: " .. dest)
    else
      err("Move failed")
    end
    refresh(node, view)
  end)
end

local function do_delete(node, view)
  confirm("Delete " .. node.path .. "?", function(yes)
    if not yes then return end
    if vim.fn.delete(node.path, node.is_dir and "rf" or "") == 0 then
      info("Deleted: " .. node.path)
    else
      err("Failed to delete: " .. node.path)
    end
    refresh(node, view)
  end)
end

local function do_copy(node, view)
  input_path("Copy to: ", node_parent_path(node) .. "/", function(dest)
    if not dest or dest == "" then return end
    mkdir_p(parent_dir(dest))
    local out = vim.fn.system({ "cp", "-r", node.path, dest })
    if vim.v.shell_error ~= 0 then err("Copy failed: " .. out)
    else info("Copied to: " .. dest) end
    refresh(node, view)
  end)
end

local function do_link_to(node, view)
  input_path("Link at: ", node_parent_path(node) .. "/", function(dest)
    if not dest or dest == "" then return end
    mkdir_p(parent_dir(dest))
    local out = vim.fn.system({ "ln", "-s", node.path, dest })
    if vim.v.shell_error ~= 0 then err("Link failed: " .. out)
    else info("Link: " .. dest .. " → " .. node.path) end
    refresh(node, view)
  end)
end

local function do_link_from(node, view)
  local base = node_parent_path(node)
  input_path("Link target: ", nil, function(target)
    if not target or target == "" then return end
    local link = base .. "/" .. vim.fn.fnamemodify(target, ":t")
    local out = vim.fn.system({ "ln", "-s", target, link })
    if vim.v.shell_error ~= 0 then err("Link failed: " .. out)
    else info("Link: " .. link .. " → " .. target) end
    refresh(node, view)
  end)
end

-- ── popup menu ────────────────────────────────────────────────────────────────

local MENU = {
  { key = "a", label = "add",       fn = do_add       },
  { key = "m", label = "move",      fn = do_move      },
  { key = "d", label = "delete",    fn = do_delete     },
  { key = "c", label = "copy",      fn = do_copy      },
  { key = "t", label = "link to",   fn = do_link_to   },
  { key = "f", label = "link from", fn = do_link_from },
}

function M.open_menu(node, view)
  -- Build popup lines.
  local lines = { " " .. node.name .. " " }
  local max_w = #lines[1]
  for _, item in ipairs(MENU) do
    local line = "  [" .. item.key .. "] " .. item.label .. "  "
    lines[#lines + 1] = line
    max_w = math.max(max_w, #line)
  end
  -- Pad to uniform width.
  for i, l in ipairs(lines) do
    lines[i] = l .. string.rep(" ", max_w - #l)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden  = "wipe"

  local win_w = max_w + 2
  local win_h = #lines
  local ui    = vim.api.nvim_list_uis()[1]
  local popup = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row      = math.floor((ui.height - win_h) / 2),
    col      = math.floor((ui.width  - win_w) / 2),
    width    = win_w,
    height   = win_h,
    style    = "minimal",
    border   = "rounded",
    title    = " fs ops ",
    title_pos = "center",
  })

  -- Highlight the header line.
  vim.api.nvim_buf_add_highlight(buf, -1, "Title", 0, 0, -1)

  local function close()
    if vim.api.nvim_win_is_valid(popup) then
      vim.api.nvim_win_close(popup, true)
    end
  end

  -- Single-key bindings — no Enter needed.
  for _, item in ipairs(MENU) do
    local fn = item.fn
    vim.keymap.set("n", item.key, function()
      close()
      fn(node, view)
    end, { buffer = buf, nowait = true })
  end

  vim.keymap.set("n", "q",      close, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>",  close, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<C-c>",  close, { buffer = buf, nowait = true })
end

return M
