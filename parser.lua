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

function parser.is_combat_log_line(text_value, patterns, trim)
    local normalized = parser.normalize_message_text(text_value, trim)
    if normalized == '' then
        return false
    end

    for _, pattern in ipairs(patterns or {}) do
        if normalized:match(pattern) then
            return true
        end
    end

    return false
end

function parser.is_mob_loot_line(text_value, patterns, trim)
    local normalized = parser.normalize_message_text(text_value, trim)
    if normalized == '' then
        return false
    end

    for _, pattern in ipairs(patterns or {}) do
        if normalized:match(pattern) then
            return true
        end
    end

    return false
end

function parser.parse_examine_sender(packet_data, trim)
    if type(packet_data) ~= 'string' or packet_data == '' then
        return nil
    end

    local payload = packet_data:sub(0x0D + 1, 0x0D + 128)
    local name = payload:match('^string2%s+([^%z]+)')
    return trim(name)
end

-- Parses slash commands from input text for the All tab.
-- Returns command, remaining_text, or nil if no slash command found.
function parser.parse_all_tab_command(text, trim)
    local trimmed = trim(text or '')
    if not trimmed:match('^/') then
        return nil, text
    end
    
    -- Extract command and text
    local cmd, rest = trimmed:match('^(/[%a%d]+)%s*(.*)')
    if not cmd then
        return nil, text
    end
    
    local cmd_lower = cmd:lower()
    
    -- Map commands to their output forms
    local command_map = {
        ['/p'] = '/p',
        ['/party'] = '/p',
        ['/s'] = '/s',
        ['/say'] = '/s',
        ['/l'] = '/l',
        ['/linkshell'] = '/l',
        ['/l2'] = '/l2',
        ['/linkshell2'] = '/l2',
        ['/sh'] = '/sh',
        ['/shout'] = '/sh',
        ['/y'] = '/y',
        ['/yell'] = '/y',
        ['/t'] = '/t',
        ['/tell'] = '/t',
        ['/m'] = '/t',
        ['/msg'] = '/t',
    }
    
    local mapped_command = command_map[cmd_lower]
    if mapped_command then
        return mapped_command, rest
    end

    -- Allow any slash command (eg. /whispers, /xiui, /addon reload whispers).
    return cmd_lower, rest
end

    function parser.apply_all_tab_command_prefix(text, command, trim)
        local target_command = trim(command or ''):lower()
        if target_command == '' then
            return tostring(text or '')
        end

        local existing_text = tostring(text or '')
        local trimmed_text = trim(existing_text)
        local existing_command, remainder = parser.parse_all_tab_command(trimmed_text, trim)
        local body = trim(remainder or '')

        if existing_command ~= nil then
            if body == '' then
                return target_command .. ' '
            end

            return string.format('%s %s', target_command, body)
        end

        if trimmed_text == '' then
            return target_command .. ' '
        end

        return string.format('%s %s', target_command, trimmed_text)
    end

return parser