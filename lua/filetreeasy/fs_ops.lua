local M = {}

local OPERATIONS = { "add", "move", "delete", "copy", "link to", "link from" }

-- ── helpers ──────────────────────────────────────────────────────────────────

local function err(msg) vim.notify("[filetreeasy] " .. msg, vim.log.levels.ERROR) end
local function info(msg) vim.notify("[filetreeasy] " .. msg, vim.log.levels.INFO) end

local function mkdir_p(path)
  -- path is a dir path; create it and all parents
  vim.fn.mkdir(path, "p")
end

local function parent_dir(path)
  return vim.fn.fnamemodify(path, ":h")
end

local function node_parent_path(node)
  return node.is_dir and node.path or parent_dir(node.path)
end

local function refresh(node, view)
  -- Refresh the parent directory node.
  local nf      = require("filetreeasy.node_factory")
  local treeasy = require("treeasy")
  local tree_m  = treeasy.tree

  local target = node.is_dir and node or nf.find_node(parent_dir(node.path))
  if not target then target = node.parent end
  if not target then return end

  if target.children ~= nil then
    nf.remove_from_index(target)
    require("filetreeasy.watcher").unwatch(target.path)
    target.children = nil
    nf.load_children(target, view)
    tree_m.update_node(target)
  end
end

-- ── input helpers ─────────────────────────────────────────────────────────────

local function input(prompt, default, cb)
  vim.ui.input({ prompt = prompt, default = default or "" }, cb)
end

local function confirm(prompt, cb)
  vim.ui.input({ prompt = prompt .. " [y/N]: " }, function(ans)
    cb(ans and ans:lower() == "y")
  end)
end

-- ── operations ───────────────────────────────────────────────────────────────

local function do_add(node, view)
  local base = node_parent_path(node)
  input("Add (trailing / = dir): " .. base .. "/", nil, function(name)
    if not name or name == "" then return end
    local full = base .. "/" .. name
    if name:sub(-1) == "/" then
      mkdir_p(full)
      info("Created dir: " .. full)
    else
      mkdir_p(parent_dir(full))
      local ok, e = pcall(vim.fn.writefile, {}, full)
      if not ok then err("Cannot create file: " .. (e or "")) end
    end
    refresh(node, view)
  end)
end

local function do_move(node, view)
  local base = parent_dir(node.path)
  input("Move/rename to: ", node.path, function(dest)
    if not dest or dest == "" or dest == node.path then return end
    -- Relative input → same parent dir (rename).
    if not dest:find("/") then dest = base .. "/" .. dest end
    mkdir_p(parent_dir(dest))
    local ok, e = pcall(vim.fn.rename, node.path, dest)
    if ok then
      -- Update any open buffer pointing to old path.
      local bufnr = vim.fn.bufnr(node.path)
      if bufnr ~= -1 then vim.api.nvim_buf_set_name(bufnr, dest) end
      info("Moved to: " .. dest)
    else
      err("Move failed: " .. (e or ""))
    end
    refresh(node, view)
  end)
end

local function do_delete(node, view)
  confirm("Delete " .. node.path .. "?", function(yes)
    if not yes then return end
    local flag = node.is_dir and "rf" or ""
    local ok   = vim.fn.delete(node.path, flag) == 0
    if ok then info("Deleted: " .. node.path)
    else      err("Failed to delete: " .. node.path) end
    refresh(node, view)
  end)
end

local function do_copy(node, view)
  input("Copy to: ", parent_dir(node.path) .. "/", function(dest)
    if not dest or dest == "" then return end
    mkdir_p(parent_dir(dest))
    local cmd = "cp -r " .. vim.fn.shellescape(node.path)
                         .. " " .. vim.fn.shellescape(dest)
    local out  = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then err("Copy failed: " .. out)
    else                           info("Copied to: " .. dest) end
    refresh(node, view)
  end)
end

-- link to: create a symlink elsewhere that points TO this node.
--   ln -s node.path <link_location>
local function do_link_to(node, view)
  input("Create link at: ", parent_dir(node.path) .. "/", function(dest)
    if not dest or dest == "" then return end
    mkdir_p(parent_dir(dest))
    local cmd = "ln -s " .. vim.fn.shellescape(node.path)
                          .. " " .. vim.fn.shellescape(dest)
    local out  = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then err("Link failed: " .. out)
    else                           info("Link created: " .. dest .. " → " .. node.path) end
    refresh(node, view)
  end)
end

-- link from: create a symlink inside/near this node pointing to another path.
--   ln -s <target> <node.parent>/<basename(target)>
local function do_link_from(node, view)
  local base = node_parent_path(node)
  input("Link target (source path): ", nil, function(target)
    if not target or target == "" then return end
    local link_name = base .. "/" .. vim.fn.fnamemodify(target, ":t")
    local cmd = "ln -s " .. vim.fn.shellescape(target)
                          .. " " .. vim.fn.shellescape(link_name)
    local out  = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then err("Link failed: " .. out)
    else                           info("Link created: " .. link_name .. " → " .. target) end
    refresh(node, view)
  end)
end

-- ── public ───────────────────────────────────────────────────────────────────

function M.open_menu(node, view)
  vim.ui.select(OPERATIONS, {
    prompt = "filetreeasy [" .. node.name .. "]:",
  }, function(choice)
    if not choice then return end
    if     choice == "add"       then do_add(node, view)
    elseif choice == "move"      then do_move(node, view)
    elseif choice == "delete"    then do_delete(node, view)
    elseif choice == "copy"      then do_copy(node, view)
    elseif choice == "link to"   then do_link_to(node, view)
    elseif choice == "link from" then do_link_from(node, view)
    end
  end)
end

return M
