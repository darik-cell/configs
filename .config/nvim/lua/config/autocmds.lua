local markdown = require("config.markdown")
local workspace = require("config.workspace")

local group = vim.api.nvim_create_augroup("nvim-alt", { clear = true })

local function restore_regular_window_state()
  if vim.bo.buftype ~= "" then
    return
  end

  if vim.bo.filetype == "neo-tree" or vim.bo.filetype == "neo-tree-popup" then
    return
  end

  vim.wo.number = true
  vim.wo.relativenumber = true
  vim.wo.signcolumn = "yes"
  vim.wo.winfixheight = false
end

local function remember_regular_file_window()
  if vim.api.nvim_win_get_config(0).relative ~= "" then
    return
  end

  if vim.bo.buftype ~= "" then
    return
  end

  if vim.bo.filetype == "neo-tree" or vim.bo.filetype == "neo-tree-popup" then
    return
  end

  workspace.state().last_file_win = vim.api.nvim_get_current_win()
end

local function autosave_buffer(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if vim.bo[bufnr].buftype ~= "" then
    return
  end

  if not vim.bo[bufnr].modifiable or vim.bo[bufnr].readonly then
    return
  end

  if vim.api.nvim_buf_get_name(bufnr) == "" or not vim.bo[bufnr].modified then
    return
  end

  vim.api.nvim_buf_call(bufnr, function()
    pcall(vim.cmd, "silent update")
  end)
end

vim.api.nvim_create_autocmd({ "TabEnter", "DirChanged" }, {
  group = group,
  callback = function()
    vim.cmd.redrawtabline()
  end,
})

vim.api.nvim_create_autocmd("ColorScheme", {
  group = group,
  callback = function()
    require("config.terminals").refresh_panel_style()
  end,
})

vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
  group = group,
  callback = function()
    restore_regular_window_state()
    remember_regular_file_window()
  end,
})

vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "FocusLost", "BufLeave" }, {
  group = group,
  callback = function(args)
    autosave_buffer(args.buf)
  end,
})

vim.api.nvim_create_autocmd("TextChangedI", {
  group = group,
  callback = function(args)
    if vim.bo[args.buf].filetype ~= "markdown" then
      return
    end

    markdown.maybe_expand_current_fenced_block(args.buf)
  end,
})

vim.api.nvim_create_autocmd("TextYankPost", {
  group = group,
  callback = function()
    vim.highlight.on_yank({
      higroup = "IncSearch",
      timeout = 150,
    })
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "markdown",
  callback = function(args)
    vim.bo[args.buf].textwidth = 0
    vim.wo.wrap = true
    vim.wo.linebreak = true
    vim.wo.spell = false
    vim.wo.conceallevel = 2
    vim.bo[args.buf].omnifunc = "v:lua.require'config.markdown'.complete_anchor"
    vim.opt_local.formatoptions:append({ "n" })
    vim.keymap.set("i", "#", markdown.handle_heading_anchor_trigger, {
      buffer = args.buf,
      expr = true,
      replace_keycodes = false,
      silent = true,
      desc = "Trigger markdown heading anchor completion",
    })
    vim.keymap.set("i", "`", markdown.handle_backtick, {
      buffer = args.buf,
      expr = true,
      replace_keycodes = false,
      silent = true,
      desc = "Insert markdown backticks or fenced block",
    })
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  callback = function()
    pcall(vim.treesitter.start)
    pcall(function()
      vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end)
  end,
})

vim.api.nvim_create_autocmd("LspAttach", {
  group = group,
  callback = function(args)
    local opts = { buffer = args.buf, silent = true }
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
    vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
    vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
  end,
})

vim.api.nvim_create_autocmd("TermOpen", {
  group = group,
  pattern = "term://*",
  callback = function()
    require("config.terminals").on_term_open()
  end,
})

vim.api.nvim_create_autocmd("BufEnter", {
  group = group,
  callback = function()
    local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p")
    if workspace.is_prompt_markdown(path) then
      workspace.set_prompt_path(path)
    end

    if vim.bo.filetype ~= "neo-tree" then
      return
    end

    vim.keymap.set("n", "<leader>m", function()
      local manager = require("neo-tree.sources.manager")
      local state = manager.get_state("filesystem")
      markdown.open_tree_node_in_mdview(state)
    end, {
      buffer = true,
      silent = true,
      desc = "Open selected markdown in mdview",
    })
  end,
})
