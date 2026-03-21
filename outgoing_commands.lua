local outgoing_commands = {}

function outgoing_commands.create(context)
    local parser = context.parser
    local trim = context.trim
    local normalize_name = context.normalize_name
    local remember_pending_outgoing = context.remember_pending_outgoing
    local tab_commands = context.tab_commands
    local command_cfg = context.command_cfg

    local all_tab = context.all_tab
    local party_tab = context.party_tab
    local say_tab = context.say_tab
    local linkshell1_tab = context.linkshell1_tab
    local linkshell2_tab = context.linkshell2_tab
    local yells_tab = context.yells_tab

    local command_to_tab = {
        ['/p'] = party_tab,
        ['/s'] = say_tab,
        ['/l'] = linkshell1_tab,
        ['/l2'] = linkshell2_tab,
        ['/sh'] = yells_tab,
        ['/y'] = yells_tab,
    }

    local function queue_chat_command(command_text)
        pcall(function()
            AshitaCore:GetChatManager():QueueCommand(1, command_text)
        end)
    end

    local function queue_tab_message(name, display, message, state)
        local msg = trim(message)
        if msg == '' or name == nil or name == '' then
            return nil, false
        end

        -- Special handling for All tab: parse slash commands.
        if name == all_tab then
            local all_msg = msg
            if state.all_tab_active_command ~= nil and trim(msg):match('^/') == nil then
                all_msg = parser.apply_all_tab_command_prefix(msg, state.all_tab_active_command, trim)
            end

            local command, remaining_text = parser.parse_all_tab_command(all_msg, trim)
            if command then
                local final_text = trim(remaining_text)
                local command_lower = command:lower()
                if command_lower == '/t' then
                    local target, tell_text = final_text:match('^([%a%d%s_%-]+)%s+(.*)')
                    if target and trim(tell_text or '') ~= '' then
                        local tell_body = trim(tell_text)
                        remember_pending_outgoing(normalize_name(target), tell_body)
                        queue_chat_command(string.format('%s %s %s', command, trim(target), tell_body))
                    else
                        queue_chat_command(all_msg)
                    end
                else
                    local dest_tab = command_to_tab[command_lower]
                    if dest_tab ~= nil and final_text ~= '' then
                        remember_pending_outgoing(dest_tab, final_text)
                    end
                    if final_text ~= '' then
                        queue_chat_command(string.format('%s %s', command, final_text))
                    else
                        queue_chat_command(command)
                    end
                end

                state.all_tab_active_command = nil
                state.input_text[1] = ''
                state.is_open[1] = true
                return nil, false
            end

            return nil, false
        end

        remember_pending_outgoing(name, msg)

        local command = tab_commands[name]
        if command ~= nil then
            queue_chat_command(string.format('%s %s', command, msg))
        else
            queue_chat_command(string.format('%s %s %s', command_cfg.direct_tell_prefix, display, msg))
        end

        state.input_text[1] = ''
        state.is_open[1] = true

        return nil, false
    end

    return {
        queue_tab_message = queue_tab_message,
    }
end

return outgoing_commands
