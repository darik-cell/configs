local function check(condition, message)
  if not condition then
    error(message, 0)
  end
end

local function sorted(values)
  local copy = vim.deepcopy(values)
  table.sort(copy)
  return copy
end

local function verify_plugin_lock()
  local lock_path = vim.fs.joinpath(vim.fn.stdpath("config"), "lazy-lock.json")
  local decoded_ok, lock = pcall(vim.json.decode, table.concat(vim.fn.readfile(lock_path), "\n"))
  check(decoded_ok and type(lock) == "table", "lazy-lock.json is not valid JSON")

  local lazy_root = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy")
  local count = 0
  for name, entry in pairs(lock) do
    local expected = type(entry) == "table" and entry.commit or nil
    check(type(expected) == "string" and #expected == 40 and expected:match("^%x+$"), "Invalid locked commit: " .. name)
    local plugin = vim.fs.joinpath(lazy_root, name)
    local result = vim.system({ "git", "-C", plugin, "rev-parse", "HEAD" }, { text = true }):wait()
    check(result.code == 0, "Lazy plugin is missing: " .. name)
    check(vim.trim(result.stdout or "") == expected, "Lazy plugin commit mismatch: " .. name)
    count = count + 1
  end

  local iterator = vim.fs.dir(lazy_root)
  check(iterator ~= nil, "Lazy plugin directory is missing")
  for name, kind in iterator do
    if kind == "directory" or kind == "link" then
      check(lock[name] ~= nil, "Unexpected Lazy plugin directory: " .. name)
    end
  end
  return count
end

local function main()
  check(package.loaded["config.options"] ~= nil, "Neovim config did not finish loading")
  check(vim.g.colors_name == "darcula-dark", "darcula-dark colorscheme is not active")

  local plugin_count = verify_plugin_lock()

  local tooling = require("config.tooling")
  local treesitter = require("nvim-treesitter")
  local parsers = treesitter.get_installed("parsers")
  local parser_set = {}
  for _, language in ipairs(parsers) do
    parser_set[language] = true
  end
  for _, language in ipairs(tooling.treesitter) do
    check(parser_set[language], "Tree-sitter parser is missing: " .. language)
    local ok, loaded = pcall(vim.treesitter.language.add, language)
    check(ok and loaded == true, "Tree-sitter parser cannot be loaded: " .. language)
  end

  local registry = require("mason-registry")
  local mason_root = require("mason.settings").current.install_root_dir
  local packages = tooling.mason_packages()
  for _, name in ipairs(packages) do
    local package = registry.get_package(name)
    check(package:is_installed(), "Mason package is missing: " .. name)

    local executables = sorted(vim.tbl_keys(package.spec.bin or {}))
    check(#executables > 0, "Mason package declares no executable: " .. name)
    for _, executable in ipairs(executables) do
      local path = vim.fs.joinpath(mason_root, "bin", executable)
      check(vim.fn.executable(path) == 1, ("Mason executable is missing: %s (%s)"):format(executable, name))
    end
  end

  check(type(require("fzf-lua")) == "table", "fzf-lua failed to load")
  check(type(require("config.markdown")) == "table", "config.markdown failed to load")
  check(type(require("config.live_preview")) == "table", "config.live_preview failed to load")
  check(vim.fn.exists(":LivePreview") == 2, ":LivePreview is not available")

  print(("NVIM_VERIFY_OK plugins=%d mason=%d parsers=%d"):format(plugin_count, #packages, #tooling.treesitter))
end

local ok, err = xpcall(main, debug.traceback)
if not ok then
  vim.api.nvim_err_writeln("NVIM_VERIFY_FAILED\n" .. tostring(err))
  vim.cmd("cquit 1")
end

vim.cmd("quitall!")
