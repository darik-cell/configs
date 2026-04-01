local M = {
  state_by_tab = {},
  last_prompt_path = nil,
}

function M.current_tab()
  return vim.api.nvim_get_current_tabpage()
end

function M.state(tabpage)
  tabpage = tabpage or M.current_tab()

  if not M.state_by_tab[tabpage] then
    M.state_by_tab[tabpage] = {
      terminals = {},
      last_terminal_slot = nil,
      terminal_history = {},
      last_file_win = nil,
      bottom_win = nil,
      bottom_terminal_height = 14,
      agent_term = nil,
      agent_win = nil,
      prompt_path = nil,
    }
  end

  return M.state_by_tab[tabpage]
end

function M.current_cwd(tabpage)
  tabpage = tabpage or M.current_tab()
  local tabnr = vim.api.nvim_tabpage_get_number(tabpage)
  local ok, cwd = pcall(vim.fn.getcwd, -1, tabnr)
  if ok and cwd ~= "" then
    return cwd
  end

  return vim.uv.cwd() or vim.loop.cwd()
end

function M.tab_title(tabpage)
  return vim.fs.basename(M.current_cwd(tabpage))
end

function M.is_markdown(path)
  if not path or path == "" then
    return false
  end

  local lowered = path:lower()
  return lowered:match("%.md$") ~= nil or lowered:match("%.markdown$") ~= nil
end

function M.prompt_dir(tabpage)
  return vim.fs.joinpath(M.current_cwd(tabpage), ".ai", "prompts")
end

function M.ensure_prompt_dir(tabpage)
  local dir = M.prompt_dir(tabpage)
  vim.fn.mkdir(dir, "p")
  return dir
end

function M.make_prompt_name(timestamp)
  timestamp = timestamp or os.time()

  local months = {
    "января",
    "февраля",
    "марта",
    "апреля",
    "мая",
    "июня",
    "июля",
    "августа",
    "сентября",
    "октября",
    "ноября",
    "декабря",
  }
  local weekdays = {
    ["0"] = "ВС",
    ["1"] = "ПН",
    ["2"] = "ВТ",
    ["3"] = "СР",
    ["4"] = "ЧТ",
    ["5"] = "ПТ",
    ["6"] = "СБ",
  }

  local day = os.date("%d", timestamp)
  local month = months[tonumber(os.date("%m", timestamp))]
  local weekday = weekdays[os.date("%w", timestamp)]
  local hm = os.date("%H:%M", timestamp)
  return ("%s-%s-%s-%s.md"):format(day, month, weekday, hm)
end

function M.new_prompt_path(tabpage)
  local dir = M.ensure_prompt_dir(tabpage)
  local name = M.make_prompt_name()
  local path = vim.fs.joinpath(dir, name)
  if vim.uv.fs_stat(path) == nil then
    return path
  end

  local stem = name:gsub("%.md$", "")
  local index = 1
  while true do
    local candidate = vim.fs.joinpath(dir, ("%s-%02d.md"):format(stem, index))
    if vim.uv.fs_stat(candidate) == nil then
      return candidate
    end
    index = index + 1
  end
end

function M.set_prompt_path(path, tabpage)
  tabpage = tabpage or M.current_tab()
  local st = M.state(tabpage)
  st.prompt_path = path and vim.fn.fnamemodify(path, ":p") or nil
  if st.prompt_path then
    M.last_prompt_path = st.prompt_path
  end
end

function M.prompt_path(tabpage)
  return M.state(tabpage).prompt_path
end

function M.last_created_prompt_path()
  return M.last_prompt_path
end

function M.is_prompt_markdown(path, tabpage)
  path = vim.fn.fnamemodify(path or "", ":p")
  if not M.is_markdown(path) then
    return false
  end

  path = vim.fs.normalize(path)
  if path:match("/%.ai/prompts/") then
    return true
  end

  local dir = vim.fs.normalize(M.prompt_dir(tabpage))
  return path:sub(1, #dir + 1) == dir .. "/"
end

function M.new_tab()
  local cwd = M.current_cwd()
  vim.cmd.tabnew()
  vim.cmd(("tcd %s"):format(vim.fn.fnameescape(cwd)))
end

function M.close_other_tabs()
  vim.cmd.tabonly()
end

function M.goto_tab(index)
  local target = index == 0 and 10 or index
  if target > vim.fn.tabpagenr("$") then
    return
  end

  vim.cmd(("tabnext %d"):format(target))
end

return M
