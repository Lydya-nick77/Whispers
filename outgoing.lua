local outgoing = {}

function outgoing.create(behavior_cfg, normalize_name, trim, normalize_message_text)
    local pending = {}

    local function prune(now)
        local current = now or os.time()

        for i = #pending, 1, -1 do
            if (current - pending[i].time) > behavior_cfg.pending_match_seconds then
                table.remove(pending, i)
            end
        end
    end

    local function remember(tab_name, message)
        local canonical = normalize_name(tab_name)
        local text_value = trim(message or '')
        local normalized = normalize_message_text(text_value)
        if canonical == '' or normalized == '' then
            return
        end

        prune()
        table.insert(pending, {
            tab = canonical,
            text = text_value,
            normalized = normalized,
            time = os.time(),
        })
    end

    local function take_pending(tab_name, incoming_text)
        local canonical = normalize_name(tab_name)
        local normalized_incoming = normalize_message_text(incoming_text)
        if canonical == '' or normalized_incoming == '' then
            return nil
        end

        prune()

        for i = #pending, 1, -1 do
            local entry = pending[i]
            if entry.tab == canonical then
                local has_match = normalized_incoming == entry.normalized
                    or normalized_incoming:find(entry.normalized, 1, true) ~= nil
                    or entry.normalized:find(normalized_incoming, 1, true) ~= nil

                if has_match then
                    table.remove(pending, i)
                    return entry
                end
            end
        end

        return nil
    end

    local function take_any(incoming_text)
        local normalized_incoming = normalize_message_text(incoming_text)
        if normalized_incoming == '' then
            return nil
        end

        prune()

        for i = #pending, 1, -1 do
            local entry = pending[i]
            local has_match = normalized_incoming == entry.normalized
                or normalized_incoming:find(entry.normalized, 1, true) ~= nil
                or entry.normalized:find(normalized_incoming, 1, true) ~= nil

            if has_match then
                table.remove(pending, i)
                return entry
            end
        end

        return nil
    end

    local function clear()
        for i = #pending, 1, -1 do
            table.remove(pending, i)
        end
    end

    return {
        remember = remember,
        take_pending = take_pending,
        take_any = take_any,
        clear = clear,
    }
end

return outgoing