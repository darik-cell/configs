local workspace = require("config.workspace")
local fuzzy_filter = require("neo-tree.sources.common.filters.filter_fzy")

local M = {}
local fuzzy_ns = vim.api.nvim_create_namespace("nvim-alt-neo-tree-fuzzy")
local fuzzy_hl = "NeoTreeFuzzyMatch"

local function tree_command()
  return require("neo-tree.command")
end

local function manager()
  return require("neo-tree.sources.manager")
end

local function filesystem_commands()
  return require("neo-tree.sources.filesystem.commands")
end

local function renderer()
  return require("neo-tree.ui.renderer")
end

local function current_file_path()
  if vim.bo.buftype ~= "" then
    return nil
  end

  local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p")
  if path == "" then
    return nil
  end

  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "file" then
    return nil
  end

  return path
end

local function selected_node_path(state)
  local node = state and state.tree and state.tree:get_node() or nil
  if not node or node.type == "message" then
    return nil, nil
  end

  local path = node.path or node:get_id()
  if not path or path == "" then
    return nil, nil
  end

  return vim.fn.fnamemodify(path, ":p"), node
end

local function search_terms(pattern)
  if type(pattern) ~= "string" then
    return {}
  end

  local terms = {}
  for term in pattern:gmatch("%S+") do
    terms[#terms + 1] = term
  end
  return terms
end

local function node_match_positions(node, pattern)
  if not node or node.skip_node or node.type == "message" then
    return nil
  end

  local name = node.name
  if type(name) ~= "string" or name == "" then
    return nil
  end

  local terms = search_terms(pattern)
  if #terms == 0 then
    return nil
  end

  local positions = {}
  for _, term in ipairs(terms) do
    if not fuzzy_filter.has_match(term, name, false) then
      return nil
    end

    for _, pos in ipairs(fuzzy_filter.positions(term, name, false)) do
      positions[pos] = true
    end
  end

  local ordered = {}
  for pos in pairs(positions) do
    ordered[#ordered + 1] = pos
  end
  table.sort(ordered)
  if #ordered == 0 then
    return nil
  end

  return ordered
end

local function visible_match_nodes(state)
  if not state or not state.tree then
    return {}
  end

  local pattern = state.search_pattern
  if not pattern or pattern == "" then
    return {}
  end

  local matches = {}
  for _, node in ipairs(renderer().get_all_visible_nodes(state.tree)) do
    if node_match_positions(node, pattern) then
      matches[#matches + 1] = node
    end
  end
  return matches
end

local function current_node_linenr(state)
  if not state or not state.tree then
    return nil
  end

  local node = state.tree:get_node()
  if not node then
    return nil
  end

  local _, linenr = state.tree:get_node(node:get_id())
  return linenr
end

local function focus_match(state, direction, scroll_padding)
  local matches = visible_match_nodes(state)
  if #matches == 0 then
    return
  end

  local current_line = current_node_linenr(state) or 0
  local target = nil

  if direction > 0 then
    for _, node in ipairs(matches) do
      local _, linenr = state.tree:get_node(node:get_id())
      if linenr and linenr > current_line then
        target = node
        break
      end
    end
    target = target or matches[1]
  else
    for index = #matches, 1, -1 do
      local node = matches[index]
      local _, linenr = state.tree:get_node(node:get_id())
      if linenr and linenr < current_line then
        target = node
        break
      end
    end
    target = target or matches[#matches]
  end

  if target then
    renderer().focus_node(state, target:get_id(), true, nil, scroll_padding or 0)
  end
end

local function clear_fuzzy_highlights(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, fuzzy_ns, 0, -1)
  end
end

local function highlight_name_matches(state, node, positions)
  local _, linenr = state.tree:get_node(node:get_id())
  if not linenr then
    return
  end

  local line = vim.api.nvim_buf_get_lines(state.bufnr, linenr - 1, linenr, false)[1]
  if type(line) ~= "string" or line == "" then
    return
  end

  local start_col = line:find(node.name, 1, true)
  if not start_col then
    return
  end

  for _, pos in ipairs(positions) do
    local col = start_col + pos - 2
    vim.api.nvim_buf_set_extmark(state.bufnr, fuzzy_ns, linenr - 1, col, {
      end_col = col + 1,
      hl_group = fuzzy_hl,
      priority = 250,
      strict = false,
    })
  end
end

local function is_regular_target_window(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end

  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local bt = vim.bo[buf].buftype
  local ft = vim.bo[buf].filetype

  if ft == "neo-tree" or ft == "neo-tree-popup" then
    return false
  end

  if vim.w[win].nvim_alt_bottom_window then
    return false
  end

  if bt ~= "" and bt ~= "terminal" then
    return false
  end

  return true
end

local function preferred_open_window()
  local current_tab = vim.api.nvim_get_current_tabpage()
  local current = vim.api.nvim_get_current_win()
  local fallback

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(current_tab)) do
    if is_regular_target_window(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local bt = vim.bo[buf].buftype
      local ft = vim.bo[buf].filetype
      if bt == "" and ft ~= "neo-tree" and ft ~= "neo-tree-popup" then
        return win
      end

      if not fallback then
        fallback = win
      end
    end
  end

  return fallback or current
end

local function open_file_in_target(path)
  local escaped = vim.fn.fnameescape(path)
  local target = preferred_open_window()

  if not is_regular_target_window(target) then
    vim.cmd("belowright split")
    target = vim.api.nvim_get_current_win()
  end

  vim.api.nvim_set_current_win(target)
  if vim.bo.buftype == "terminal" then
    vim.cmd.stopinsert()
    vim.api.nvim_win_set_buf(target, vim.api.nvim_create_buf(false, false))
  end
  vim.cmd(("hide edit %s"):format(escaped))
end

local function copy_path(path)
  vim.fn.setreg("+", path)
  vim.fn.setreg('"', path)
  vim.notify(path, vim.log.levels.INFO, { title = "Absolute path copied" })
end

function M.open_tree()
  local args = {
    action = "focus",
    source = "filesystem",
    position = "float",
    dir = workspace.current_cwd(),
  }

  local reveal_file = current_file_path()
  if reveal_file then
    args.reveal_file = reveal_file
    args.reveal_force_cwd = true
  end

  tree_command().execute(args)
end

function M.fuzzy_next_match(state, scroll_padding)
  focus_match(state, 1, scroll_padding)
end

function M.fuzzy_prev_match(state, scroll_padding)
  focus_match(state, -1, scroll_padding)
end

function M.highlight_fuzzy_matches(state)
  if not state or state.name ~= "filesystem" then
    return
  end

  clear_fuzzy_highlights(state.bufnr)
  if not state.search_pattern or state.search_pattern == "" then
    return
  end

  vim.api.nvim_set_hl(0, fuzzy_hl, { link = "Search", default = true })

  for _, node in ipairs(visible_match_nodes(state)) do
    local positions = node_match_positions(node, state.search_pattern)
    if positions then
      highlight_name_matches(state, node, positions)
    end
  end
end

function M.copy_cursor_path()
  if vim.bo.filetype == "neo-tree" then
    local state = manager().get_state("filesystem")
    return M.copy_selected_path(state)
  end

  local path = current_file_path()
  if not path then
    vim.notify("Nothing to copy from this buffer", vim.log.levels.WARN)
    return
  end

  copy_path(path)
end

function M.copy_selected_path(state)
  local path = selected_node_path(state)
  if not path then
    vim.notify("No path under cursor", vim.log.levels.WARN)
    return
  end

  copy_path(path)
end

function M.set_root_and_tcd(state)
  local path, node = selected_node_path(state)
  if not path then
    vim.notify("No directory target under cursor", vim.log.levels.WARN)
    return
  end

  local target = node.type == "directory" and path or vim.fs.dirname(path)
  vim.cmd(("tcd %s"):format(vim.fn.fnameescape(target)))

  tree_command().execute({
    action = "focus",
    source = "filesystem",
    position = state.current_position or "float",
    dir = target,
  })
end

function M.open_selected(state)
  local path, node = selected_node_path(state)
  if not path or not node then
    return
  end

  if node.type ~= "file" then
    filesystem_commands().open(state)
    return
  end

  open_file_in_target(path)
end

function M.open_path(path)
  if not path or path == "" then
    return
  end

  open_file_in_target(vim.fn.fnamemodify(path, ":p"))
end

function M.scroll(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "n", false)
end

return M
