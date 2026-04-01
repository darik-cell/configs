local workspace = require("config.workspace")

local M = {}

function M.render()
  local parts = {}
  local current = vim.api.nvim_get_current_tabpage()

  for index, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    local digit = index == 10 and 0 or index
    local label = ("%d %s"):format(digit, workspace.tab_title(tabpage))
    local hl = tabpage == current and "%#TabLineSel#" or "%#TabLine#"
    parts[#parts + 1] = ("%%%dT%s %s "):format(index, hl, label)
  end

  parts[#parts + 1] = "%#TabLineFill#%T"
  return table.concat(parts)
end

function M.setup()
  vim.opt.tabline = "%!v:lua.require'config.tabline'.render()"
end

return M
