local outgoing_commands = {}

function outgoing_commands.create(context)
    local trim = context.trim
    local remember_pending_outgoing = context.remember_pending_outgoing
    local tab_commands = context.tab_commands
    local command_cfg = context.command_cfg
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
