local MASON_TIMEOUT_MS = 600000
local REGISTRY_TIMEOUT_MS = 300000

local function describe(value)
  return type(value) == "string" and value or vim.inspect(value)
end

local function wait_for(label, timeout, predicate)
  if not vim.wait(timeout, predicate, 100) then
    error(("Timed out while %s"):format(label))
  end
end

local function update_registry(registry)
  local finished, succeeded, result = false, false, nil
  registry.update(function(ok, value)
    succeeded, result, finished = ok, value, true
  end)

  wait_for("updating the Mason registry", REGISTRY_TIMEOUT_MS, function()
    return finished
  end)
  if not succeeded then
    error("Mason registry update failed: " .. describe(result))
  end
end

local function install_package(registry, name)
  local package = registry.get_package(name)

  if package:is_installing() or package:is_uninstalling() then
    wait_for(("waiting for Mason package %s"):format(name), MASON_TIMEOUT_MS, function()
      return not package:is_installing() and not package:is_uninstalling()
    end)
  end
  if package:is_installed() then
    return
  end

  local finished, succeeded, result = false, false, nil
  package:install({}, function(ok, value)
    succeeded, result, finished = ok, value, true
  end)

  wait_for(("installing Mason package %s"):format(name), MASON_TIMEOUT_MS, function()
    return finished
  end)
  if not succeeded or not package:is_installed() then
    error(("Mason package %s failed to install: %s"):format(name, describe(result)))
  end
end

local function main()
  local tooling = require("config.tooling")
  local registry = require("mason-registry")
  local packages = tooling.mason_packages()

  update_registry(registry)
  for _, name in ipairs(packages) do
    install_package(registry, name)
  end

  local installed = tooling.install_treesitter({
    wait = true,
    timeout = MASON_TIMEOUT_MS,
    install_opts = { max_jobs = 4, summary = true },
  })
  if installed ~= true then
    error("Tree-sitter did not install every requested parser")
  end

  local present = {}
  for _, language in ipairs(require("nvim-treesitter").get_installed("parsers")) do
    present[language] = true
  end
  for _, language in ipairs(tooling.treesitter) do
    if not present[language] then
      error("Tree-sitter parser is missing: " .. language)
    end
  end

  print(("NVIM_BOOTSTRAP_OK mason=%d parsers=%d"):format(#packages, #tooling.treesitter))
end

local ok, err = xpcall(main, debug.traceback)
if not ok then
  vim.api.nvim_err_writeln("NVIM_BOOTSTRAP_FAILED\n" .. tostring(err))
  vim.cmd("cquit 1")
end

vim.cmd("quitall!")
