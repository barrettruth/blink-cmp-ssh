---@class blink-cmp-ssh : blink.cmp.Source
local M = {}

---@type blink.cmp.CompletionItem[]?
local keywords_cache = nil
---@type table<string, string[]>?
local enums_cache = nil
local loading = false
---@type {ctx: blink.cmp.Context, callback: fun(response: blink.cmp.CompletionResponse)}[]
local pending = {}

function M.new()
  return setmetatable({}, { __index = M })
end

---@return boolean
function M.enabled()
  return vim.bo.filetype == 'sshconfig'
end

---@type table<string, string[]>
local static_enums = {
  AddKeysToAgent = { 'yes', 'no', 'ask', 'confirm' },
  AddressFamily = { 'any', 'inet', 'inet6' },
  BatchMode = { 'yes', 'no' },
  CanonicalizeHostname = { 'yes', 'no', 'always' },
  CanonicalizeFallbackLocal = { 'yes', 'no' },
  CheckHostIP = { 'yes', 'no' },
  ClearAllForwardings = { 'yes', 'no' },
  Compression = { 'yes', 'no' },
  ControlMaster = { 'yes', 'no', 'ask', 'auto', 'autoask' },
  EnableEscapeCommandline = { 'yes', 'no' },
  EnableSSHKeysign = { 'yes', 'no' },
  ExitOnForwardFailure = { 'yes', 'no' },
  FingerprintHash = { 'md5', 'sha256' },
  ForkAfterAuthentication = { 'yes', 'no' },
  ForwardAgent = { 'yes', 'no' },
  ForwardX11 = { 'yes', 'no' },
  ForwardX11Trusted = { 'yes', 'no' },
  GatewayPorts = { 'yes', 'no' },
  GSSAPIAuthentication = { 'yes', 'no' },
  GSSAPIDelegateCredentials = { 'yes', 'no' },
  HashKnownHosts = { 'yes', 'no' },
  HostbasedAuthentication = { 'yes', 'no' },
  IdentitiesOnly = { 'yes', 'no' },
  KbdInteractiveAuthentication = { 'yes', 'no' },
  LogLevel = {
    'QUIET',
    'FATAL',
    'ERROR',
    'INFO',
    'VERBOSE',
    'DEBUG',
    'DEBUG1',
    'DEBUG2',
    'DEBUG3',
  },
  NoHostAuthenticationForLocalhost = { 'yes', 'no' },
  PasswordAuthentication = { 'yes', 'no' },
  PermitLocalCommand = { 'yes', 'no' },
  PermitRemoteOpen = { 'any', 'none' },
  ProxyUseFdpass = { 'yes', 'no' },
  PubkeyAuthentication = { 'yes', 'no', 'unbound', 'host-bound' },
  RequestTTY = { 'yes', 'no', 'force', 'auto' },
  SessionType = { 'none', 'subsystem', 'default' },
  StdinNull = { 'yes', 'no' },
  StreamLocalBindUnlink = { 'yes', 'no' },
  StrictHostKeyChecking = { 'yes', 'no', 'ask', 'accept-new', 'off' },
  TCPKeepAlive = { 'yes', 'no' },
  Tunnel = { 'yes', 'no', 'point-to-point', 'ethernet' },
  UpdateHostKeys = { 'yes', 'no', 'ask' },
  VerifyHostKeyDNS = { 'yes', 'no', 'ask' },
  VisualHostKey = { 'yes', 'no' },
}

---@type table<string, string[]>
local query_to_keywords = {
  cipher = { 'Ciphers' },
  ['cipher-auth'] = { 'Ciphers' },
  mac = { 'MACs' },
  kex = { 'KexAlgorithms' },
  key = { 'HostKeyAlgorithms', 'PubkeyAcceptedAlgorithms' },
  ['key-sig'] = { 'CASignatureAlgorithms' },
}

---@param stdout string
---@return blink.cmp.CompletionItem[]
local function parse_keywords(stdout)
  local Kind = require('blink.cmp.types').CompletionItemKind
  local lines = {}
  for line in (stdout .. '\n'):gmatch('(.-)\n') do
    lines[#lines + 1] = line
  end

  local defs = {}
  for i, line in ipairs(lines) do
    local kw = line:match('^       (%u%a+)%s*$') or line:match('^       (%u%a+)   ')
    if kw then
      local inline = line:match('^       %u%a+%s%s%s+(.+)')
      defs[#defs + 1] = { line = i, keyword = kw, inline = inline }
    end
  end

  local items = {}
  for idx, def in ipairs(defs) do
    local block_end = (defs[idx + 1] and defs[idx + 1].line or #lines) - 1

    local desc_lines = {}
    if def.inline then
      desc_lines[#desc_lines + 1] = '               ' .. def.inline
    end
    for k = def.line + 1, block_end do
      desc_lines[#desc_lines + 1] = lines[k]
    end

    local paragraphs = { {} }
    for _, dl in ipairs(desc_lines) do
      local stripped = vim.trim(dl)
      if stripped == '' then
        if #paragraphs[#paragraphs] > 0 then
          paragraphs[#paragraphs + 1] = {}
        end
      else
        local para = paragraphs[#paragraphs]
        para[#para + 1] = stripped
      end
    end

    local parts = {}
    for _, para in ipairs(paragraphs) do
      if #para > 0 then
        parts[#parts + 1] = table.concat(para, ' ')
      end
    end

    local desc = table.concat(parts, '\n\n')
    desc = desc:gsub(string.char(0xe2, 0x80, 0x90) .. ' ', '')
    desc = desc:gsub('  +', ' ')

    items[#items + 1] = {
      label = def.keyword,
      kind = Kind.Property,
      documentation = desc ~= '' and { kind = 'markdown', value = desc } or nil,
    }
  end
  return items
end

---@param stdout string
---@return table<string, string[]>
local function parse_enums(stdout)
  local enums = {}
  for k, v in pairs(static_enums) do
    enums[k:lower()] = v
  end

  local current_query = nil
  for line in (stdout .. '\n'):gmatch('(.-)\n') do
    local query = line:match('^##(.+)')
    if query then
      current_query = query
    elseif current_query and line ~= '' then
      local keywords = query_to_keywords[current_query]
      if keywords then
        for _, kw in ipairs(keywords) do
          local key = kw:lower()
          if not enums[key] then
            enums[key] = {}
          end
          local seen = {}
          for _, existing in ipairs(enums[key]) do
            seen[existing] = true
          end
          if not seen[line] then
            enums[key][#enums[key] + 1] = line
          end
        end
      end
    end
  end
  return enums
end

---@param ctx blink.cmp.Context
---@param callback fun(response: blink.cmp.CompletionResponse)
local function respond(ctx, callback)
  if not keywords_cache or not enums_cache then
    return
  end
  local before = ctx.line:sub(1, ctx.cursor[2])

  if before:match('^%s*%a*$') then
    callback({
      is_incomplete_forward = false,
      is_incomplete_backward = false,
      items = keywords_cache,
    })
    return
  end

  local keyword = before:match('^%s*(%S+)')
  if keyword then
    local vals = enums_cache[keyword:lower()]
    if vals then
      local Kind = require('blink.cmp.types').CompletionItemKind
      local items = {}
      for _, v in ipairs(vals) do
        items[#items + 1] = {
          label = v,
          kind = Kind.EnumMember,
          filterText = v,
        }
      end
      callback({
        is_incomplete_forward = false,
        is_incomplete_backward = false,
        items = items,
      })
      return
    end
  end

  callback({ items = {} })
end

---@param ctx blink.cmp.Context
---@param callback fun(response: blink.cmp.CompletionResponse)
---@return fun()
function M:get_completions(ctx, callback)
  if keywords_cache then
    respond(ctx, callback)
    return function() end
  end

  pending[#pending + 1] = { ctx = ctx, callback = callback }
  if not loading then
    loading = true
    local man_out, enums_out
    local remaining = 2

    local function on_all_done()
      remaining = remaining - 1
      if remaining > 0 then
        return
      end
      vim.schedule(function()
        local ok_kw, kw = pcall(parse_keywords, man_out)
        if not ok_kw then
          kw = {}
        end
        keywords_cache = kw
        local ok_en, en = pcall(parse_enums, enums_out)
        if not ok_en then
          en = {}
        end
        enums_cache = en
        loading = false
        for _, p in ipairs(pending) do
          respond(p.ctx, p.callback)
        end
        pending = {}
      end)
    end

    vim.system(
      { 'bash', '-c', 'MANWIDTH=80 man -P cat ssh_config 2>/dev/null' },
      {},
      function(result)
        man_out = result.stdout or ''
        on_all_done()
      end
    )
    vim.system({
      'bash',
      '-c',
      'for q in cipher cipher-auth mac kex key key-cert key-plain key-sig protocol-version compression sig; do echo "##$q"; ssh -Q "$q" 2>/dev/null; done',
    }, {}, function(result)
      enums_out = result.stdout or ''
      on_all_done()
    end)
  end
  return function() end
end

return M
