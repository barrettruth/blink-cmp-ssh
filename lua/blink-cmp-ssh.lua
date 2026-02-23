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

---@param fragment string
---@return string[]?
local function parse_value_list(fragment)
  fragment = fragment:gsub('%b()', '')
  fragment = fragment:gsub('"', '')
  fragment = fragment:gsub(' or ', ', ')
  fragment = fragment:gsub(' and ', ', ')
  local vals = {}
  local seen = {}
  for piece in (fragment .. ','):gmatch('%s*(.-),%s*') do
    piece = vim.trim(piece)
    if piece ~= '' and not piece:find('%s') then
      local val = piece:match('^([%a][%a%d-]+)$')
      if val then
        if not seen[val] then
          seen[val] = true
          vals[#vals + 1] = val
        end
      end
    end
  end
  return #vals >= 2 and vals or nil
end

---@param man_stdout string
---@return table<string, string[]>
local function extract_enums_from_man(man_stdout)
  local lines = {}
  for line in (man_stdout .. '\n'):gmatch('(.-)\n') do
    lines[#lines + 1] = line
  end

  local defs = {}
  for i, line in ipairs(lines) do
    local kw = line:match('^       (%u[%a%d]+)%s*$') or line:match('^       (%u[%a%d]+)  ')
    if kw then
      defs[#defs + 1] = { line = i, keyword = kw }
    end
  end

  local enums = {}
  for idx, def in ipairs(defs) do
    local block_end = (defs[idx + 1] and defs[idx + 1].line or #lines) - 1
    local parts = {}
    for k = def.line + 1, block_end do
      parts[#parts + 1] = lines[k]
    end
    local text = table.concat(parts, ' ')
    text = text:gsub(string.char(0xe2, 0x80, 0x90) .. '%s+', '')
    text = text:gsub('%s+', ' ')

    local list = text:match('[Tt]he argument must be (.-)%.')
      or text:match('[Tt]he argument to this keyword must be (.-)%.')
      or text:match('[Tt]he argument may be one of:? (.-)%.')
      or text:match('[Tt]he argument may be (.-)%.')
      or text:match('[Tt]he possible values are:? (.-)%.')
      or text:match('[Vv]alid arguments are (.-)%.')
      or text:match('[Vv]alid options are:? (.-)%.')
      or text:match('[Aa]ccepted values are (.-)%.')
    local vals = list and parse_value_list(list)

    if not vals then
      local fvals = {}
      local fseen = {}
      local function add(v)
        if v and #v >= 2 and not fseen[v] then
          fseen[v] = true
          fvals[#fvals + 1] = v
        end
      end
      for v1, v2 in text:gmatch(' is set to "?([%a][%a%d-]+)"? or "?([%a][%a%d-]+)"?') do
        add(v1)
        add(v2)
      end
      for v in text:gmatch(' is set to "?([%a][%a%d-]+)"?') do
        add(v)
      end
      for v in text:gmatch('%u[%a%d]+ set to "?([%a][%a%d-]+)"?') do
        add(v)
      end
      for v in text:gmatch('When set to "?([%a][%a%d-]+)"?') do
        add(v)
      end
      for v in text:gmatch('[Ss]etting %S+ to "?([%a][%a%d-]+)"?') do
        add(v)
      end
      for v in text:gmatch('value %S+ be set to "?([%a][%a%d-]+)"?') do
        add(v)
      end
      local these = text:match('[Tt]hese options are:? (.-)%.')
      if these then
        local tv = parse_value_list(these)
        if tv then
          for _, v in ipairs(tv) do
            add(v)
          end
        end
      end
      for v in text:gmatch('[Tt]he default is "?([%a][%a%d-]+)"?') do
        if v ~= 'to' then
          add(v)
        end
      end
      for v in text:gmatch('[Tt]he default, "?([%a][%a%d-]+)"?') do
        add(v)
      end
      for v in text:gmatch('[Aa]n argument of "?([%a][%a%d-]+)"?') do
        add(v)
      end
      for v in text:gmatch('[Aa] value of "?([%a][%a%d-]+)"?') do
        add(v)
      end
      if #fvals >= 2 then
        vals = fvals
      end
    end

    if vals then
      enums[def.keyword:lower()] = vals
    end
  end
  return enums
end

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
    local kw = line:match('^       (%u[%a%d]+)%s*$') or line:match('^       (%u[%a%d]+)  ')
    if kw then
      local inline = line:match('^       %u[%a%d]+%s%s+(.+)')
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
---@param man_enums table<string, string[]>
---@return table<string, string[]>
local function parse_enums(stdout, man_enums)
  local enums = {}
  for k, v in pairs(man_enums) do
    enums[k] = v
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
        local ok_me, me = pcall(extract_enums_from_man, man_out)
        if not ok_me then
          me = {}
        end
        local ok_en, en = pcall(parse_enums, enums_out, me)
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
