local M = {}

-- Reveal a file path in the tree.
-- Expands ancestor directories (triggering lazy load), then uses
-- view:goto_node() which handles scrolling after the render.
function M.reveal(path, view)
  if not view then return end

  local nf    = require("filetreeasy.node_factory")
  local roots = require("filetreeasy.roots")

  path = vim.fn.fnamemodify(path, ":p"):gsub("/$", "")
  local root = roots.find_best(path)
  if not root then return end

  -- Walk down the path, opening each ancestor dir to trigger lazy loading.
  local rel   = path:sub(#root + 2)
  local parts = vim.split(rel, "/", { plain = true })

  local cur_path = root
  for i = 1, #parts - 1 do
    cur_path = cur_path .. "/" .. parts[i]
    local node = nf.find_node(cur_path)
    if node then
      view:send_event("open", node)
    end
  end

  -- Let the open events settle, then goto_node handles the rest.
  vim.schedule(function()
    local file_node = nf.find_node(path)
    if file_node then
      view:goto_node(file_node)
    end
  end)
end

return M
