local storage = {}

function storage.make_default_tells(default_tabs)
    local tells = {}
    local display_names = {}

    for _, tab in ipairs(default_tabs) do
        tells[tab.canonical] = {}
        display_names[tab.canonical] = tab.display
    end

    return tells, display_names
end

function storage.save_messages(save_dir, save_file, tells, display_names, player_order)
    os.execute(string.format('if not exist "%s" mkdir "%s"', save_dir, save_dir))

    local handle = io.open(save_file, 'w')
    if not handle then
        return
    end

    handle:write('return {\n')
    handle:write('  tells = {\n')
    for canonical, msgs in pairs(tells) do
        handle:write(string.format('    [%q] = {\n', canonical))
        for _, message in ipairs(msgs) do
            local brace_suffix = ''
            local mode_suffix = ''
            local source_tab_suffix = ''
            if type(message.auto_translate_braces) == 'table' and #message.auto_translate_braces > 0 then
                local brace_parts = {}
                for _, idx in ipairs(message.auto_translate_braces) do
                    if type(idx) == 'number' then
                        local n = math.floor(idx)
                        if n > 0 then
                            table.insert(brace_parts, tostring(n))
                        end
                    end
                end
                if #brace_parts > 0 then
                    brace_suffix = ',auto_translate_braces={' .. table.concat(brace_parts, ',') .. '}'
                end
            end
            if type(message.chat_mode) == 'number' then
                local mode_num = math.floor(message.chat_mode)
                if mode_num >= 0 then
                    mode_suffix = string.format(',chat_mode=%d', mode_num)
                end
            end
            if type(message.source_tab) == 'string' and message.source_tab ~= '' then
                source_tab_suffix = string.format(',source_tab=%q', message.source_tab)
            end
            handle:write(string.format('      {time=%d,text=%q,sender=%q%s%s},\n',
                message.time or 0, message.text or '', message.sender or '', brace_suffix, mode_suffix .. source_tab_suffix))
        end
        handle:write('    },\n')
    end
    handle:write('  },\n')
    handle:write('  display_names = {\n')
    for canonical, display in pairs(display_names) do
        handle:write(string.format('    [%q]=%q,\n', canonical, display))
    end
    handle:write('  },\n')
    handle:write('  player_order = {\n')
    for _, canonical in ipairs(player_order) do
        handle:write(string.format('    %q,\n', canonical))
    end
    handle:write('  },\n')
    handle:write('}\n')
    handle:close()
end

function storage.load_messages(save_file, tells, display_names, player_order, save_ttl)
    local handle = io.open(save_file, 'r')
    if not handle then
        return
    end

    local content = handle:read('*all')
    handle:close()
    if not content or content == '' then
        return
    end

    local loader = load(content)
    if not loader then
        return
    end

    local ok, data = pcall(loader)
    if not ok or type(data) ~= 'table' then
        return
    end

    local cutoff = os.time() - save_ttl
    if type(data.tells) == 'table' then
        for canonical, msgs in pairs(data.tells) do
            if type(msgs) == 'table' then
                local filtered = {}
                for _, message in ipairs(msgs) do
                    if type(message) == 'table' and type(message.time) == 'number' and message.time >= cutoff then
                        local braces = nil
                        local mode_num = nil
                        if type(message.auto_translate_braces) == 'table' then
                            braces = {}
                            for _, idx in ipairs(message.auto_translate_braces) do
                                if type(idx) == 'number' then
                                    local n = math.floor(idx)
                                    if n > 0 then
                                        table.insert(braces, n)
                                    end
                                end
                            end
                            if #braces == 0 then
                                braces = nil
                            end
                        end
                        if type(message.chat_mode) == 'number' then
                            mode_num = math.floor(message.chat_mode)
                        end
                        local source_tab = nil
                        if type(message.source_tab) == 'string' and message.source_tab ~= '' then
                            source_tab = tostring(message.source_tab)
                        end
                        table.insert(filtered, {
                            time = message.time,
                            text = tostring(message.text or ''),
                            sender = tostring(message.sender or ''),
                            auto_translate_braces = braces,
                            chat_mode = mode_num,
                            source_tab = source_tab,
                        })
                    end
                end
                if #filtered > 0 then
                    tells[canonical] = filtered
                end
            end
        end
    end

    if type(data.display_names) == 'table' then
        for canonical, display in pairs(data.display_names) do
            if type(canonical) == 'string' and type(display) == 'string' then
                if not display_names[canonical] or display_names[canonical] == '' then
                    display_names[canonical] = display
                end
            end
        end
    end

    if type(data.player_order) == 'table' then
        for _, canonical in ipairs(data.player_order) do
            if type(canonical) == 'string' and tells[canonical] ~= nil then
                local already_seen = false
                for _, existing in ipairs(player_order) do
                    if existing == canonical then
                        already_seen = true
                        break
                    end
                end
                if not already_seen then
                    table.insert(player_order, canonical)
                end
            end
        end
    end
end

return storage