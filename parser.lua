local parser = {}

function parser.parse_chat_line(text_value, parser_cfg, trim)
    local sender, body

    for _, pattern in ipairs(parser_cfg.patterns) do
        sender, body = text_value:match(pattern)
        if sender then
            return trim(sender), trim(body)
        end
    end

    sender, body = text_value:match(parser_cfg.name_colon_pattern)
    if sender then
        return trim(sender), trim(body)
    end

    return nil, trim(text_value)
end

local function escape_lua_pattern(text_value)
    return (text_value:gsub('([%(%)%.%%%+%-%*%?%[%]%^%$])', '%%%1'))
end

function parser.strip_channel_label(text_value, tab_label, trim)
    local t = trim(text_value or '')
    local label = trim(tab_label or '')
    if t == '' or label == '' then
        return t
    end

    local escaped = escape_lua_pattern(label)
    return t:gsub('^%s*' .. escaped .. '%s*:%s*', '', 1)
end

function parser.infer_self_message_body(text_value, player_name, trim)
    local t = trim(text_value or '')
    local name = trim(player_name or '')
    if t == '' or name == '' then
        return nil
    end

    local escaped = escape_lua_pattern(name)
    local body = t:match('^%s*' .. escaped .. '%s*:%s*(.*)$')
        or t:match('^%s*' .. escaped .. '%s*>>%s*(.*)$')
        or t:match('^%s*%(' .. escaped .. '%)%s*(.*)$')
        or t:match('^.-%f[%a]' .. escaped .. '%f[%A]%s*:%s*(.*)$')
        or t:match('^.-%f[%a]' .. escaped .. '%f[%A]%s*>>%s*(.*)$')
        or t:match('^.-%(' .. escaped .. '%)%s*(.*)$')

    if body == nil then
        return nil
    end

    body = trim(body)
    if body == '' then
        return nil
    end

    return body
end

function parser.normalize_message_text(text_value, trim)
    if not text_value then
        return ''
    end

    return trim(text_value):gsub('%s+', ' '):lower()
end

function parser.parse_examine_sender(packet_data, trim)
    if type(packet_data) ~= 'string' or packet_data == '' then
        return nil
    end

    local payload = packet_data:sub(0x0D + 1, 0x0D + 128)
    local name = payload:match('^string2%s+([^%z]+)')
    return trim(name)
end

return parser