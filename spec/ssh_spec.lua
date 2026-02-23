local helpers = require('spec.helpers')

local MAN_PAGE = table.concat({
  'SSH_CONFIG(5)                  File Formats Manual                SSH_CONFIG(5)',
  '',
  '       The  possible keywords and their meanings are as follows:',
  '',
  '       Host    Restricts the following declarations (up to  the  next  Host  or',
  '               Match keyword) to be only for those hosts that match one of the',
  '               patterns given after the keyword.',
  '',
  '       StrictHostKeyChecking',
  '               If this flag is set to yes, ssh(1) will never automatically add',
  '               host keys to the ~/.ssh/known_hosts file, and refuses to connect',
  '               to hosts whose host key has changed.',
  '',
  '       Hostname',
  '               Specifies the real host name to log into.',
  '',
}, '\n')

local SSH_Q_OUTPUT = table.concat({
  '##cipher',
  'aes128-ctr',
  'aes256-ctr',
  'chacha20-poly1305@openssh.com',
  '##cipher-auth',
  'chacha20-poly1305@openssh.com',
  '##mac',
  'hmac-sha2-256',
  '##kex',
  'curve25519-sha256',
  '##key',
  'ssh-ed25519',
  '##key-cert',
  '##key-plain',
  '##key-sig',
  'ssh-ed25519',
  '##protocol-version',
  '2',
  '##compression',
  'none',
  'zlib@openssh.com',
  '##sig',
}, '\n')

local function mock_system()
  local original_system = vim.system
  local original_schedule = vim.schedule
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(cmd, _, on_exit)
    local stdout = ''
    if cmd[1] == 'bash' and cmd[3] and cmd[3]:find('man %-P cat ssh_config') then
      stdout = MAN_PAGE
    elseif cmd[1] == 'bash' and cmd[3] and cmd[3]:find('ssh %-Q') then
      stdout = SSH_Q_OUTPUT
    end
    local result = { stdout = stdout, code = 0 }
    if on_exit then
      on_exit(result)
      return {}
    end
    return {
      wait = function()
        return result
      end,
    }
  end
  vim.schedule = function(fn)
    fn()
  end
  return function()
    vim.system = original_system
    vim.schedule = original_schedule
  end
end

describe('blink-cmp-ssh', function()
  local restores = {}

  before_each(function()
    package.loaded['blink-cmp-ssh'] = nil
  end)

  after_each(function()
    for _, fn in ipairs(restores) do
      fn()
    end
    restores = {}
  end)

  describe('enabled', function()
    it('returns true for sshconfig filetype', function()
      local bufnr = helpers.create_buffer({}, 'sshconfig')
      local source = require('blink-cmp-ssh')
      assert.is_true(source.enabled())
      helpers.delete_buffer(bufnr)
    end)

    it('returns false for other filetypes', function()
      local bufnr = helpers.create_buffer({}, 'lua')
      local source = require('blink-cmp-ssh')
      assert.is_false(source.enabled())
      helpers.delete_buffer(bufnr)
    end)
  end)

  describe('get_completions', function()
    it('returns keyword items with Property kind on empty line', function()
      restores[#restores + 1] = mock_system()
      local source = require('blink-cmp-ssh').new()
      local items
      source:get_completions({ line = '', cursor = { 1, 0 } }, function(response)
        items = response.items
      end)
      assert.is_not_nil(items)
      assert.equals(3, #items)
      for _, item in ipairs(items) do
        assert.equals(10, item.kind)
      end
    end)

    it('returns keyword items on partial keyword', function()
      restores[#restores + 1] = mock_system()
      local source = require('blink-cmp-ssh').new()
      local items
      source:get_completions({ line = 'Str', cursor = { 1, 3 } }, function(response)
        items = response.items
      end)
      assert.is_not_nil(items)
      assert.equals(3, #items)
    end)

    it('includes man page documentation in items', function()
      restores[#restores + 1] = mock_system()
      local source = require('blink-cmp-ssh').new()
      local items
      source:get_completions({ line = '', cursor = { 1, 0 } }, function(response)
        items = response.items
      end)
      local strict = vim.iter(items):find(function(item)
        return item.label == 'StrictHostKeyChecking'
      end)
      assert.is_not_nil(strict)
      assert.is_not_nil(strict.documentation)
      assert.is_truthy(strict.documentation.value:find('known_hosts'))
    end)

    it('returns enum values after a known keyword', function()
      restores[#restores + 1] = mock_system()
      local source = require('blink-cmp-ssh').new()
      local items
      source:get_completions(
        { line = 'StrictHostKeyChecking ', cursor = { 1, 22 } },
        function(response)
          items = response.items
        end
      )
      assert.is_not_nil(items)
      assert.is_true(#items > 0)
      for _, item in ipairs(items) do
        assert.equals(20, item.kind)
      end
    end)

    it('returns empty after a non-enum keyword', function()
      restores[#restores + 1] = mock_system()
      local source = require('blink-cmp-ssh').new()
      local items
      source:get_completions({ line = 'Hostname ', cursor = { 1, 9 } }, function(response)
        items = response.items
      end)
      assert.equals(0, #items)
    end)

    it('returns a cancel function', function()
      restores[#restores + 1] = mock_system()
      local source = require('blink-cmp-ssh').new()
      local cancel = source:get_completions({ line = '', cursor = { 1, 0 } }, function() end)
      assert.is_function(cancel)
    end)
  end)
end)
