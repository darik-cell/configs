local workspace = require("config.workspace")

local M = {}

local function fzf()
  return require("fzf-lua")
end

local function project_opts(opts)
  opts = opts or {}
  opts.cwd = workspace.current_cwd()
  return opts
end

function M.files()
  fzf().files(project_opts())
end

function M.live_grep()
  fzf().live_grep(project_opts())
end

function M.buffers()
  fzf().buffers()
end

function M.oldfiles()
  fzf().oldfiles(project_opts({
    cwd_only = true,
  }))
end

function M.help_tags()
  fzf().helptags()
end

return M
