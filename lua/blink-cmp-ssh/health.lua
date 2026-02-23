local M = {}

function M.check()
  vim.health.start('blink-cmp-ssh')

  local ok = pcall(require, 'blink.cmp')
  if ok then
    vim.health.ok('blink.cmp is installed')
  else
    vim.health.error('blink.cmp is not installed')
  end

  local bin = vim.fn.exepath('ssh')
  if bin ~= '' then
    vim.health.ok('ssh executable found: ' .. bin)
  else
    vim.health.error('ssh executable not found')
    return
  end

  local man_bin = vim.fn.exepath('man')
  if man_bin ~= '' then
    vim.health.ok('man executable found: ' .. man_bin)
  else
    vim.health.warn('man executable not found (keyword descriptions will be unavailable)')
  end

  local result = vim.system({ 'ssh', '-Q', 'cipher' }):wait()
  if result.code == 0 and result.stdout and result.stdout ~= '' then
    vim.health.ok('ssh -Q cipher produces output')
  else
    vim.health.warn('ssh -Q cipher failed (enum completions will be unavailable)')
  end
end

return M
