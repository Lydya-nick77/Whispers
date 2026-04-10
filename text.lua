local text = {}

local ffi = require('ffi')
pcall(ffi.cdef, [[
    int MultiByteToWideChar(uint32_t CodePage, uint32_t dwFlags, char* lpMultiByteStr, int cbMultiByte, wchar_t* lpWideCharStr, int32_t cchWideChar);
    int WideCharToMultiByte(uint32_t CodePage, uint32_t dwFlags, wchar_t* lpWideCharStr, int32_t cchWideChar, char* lpMultiByteStr, int32_t cbMultiByte, const char* lpDefaultChar, bool* lpUsedDefaultChar);
]])

local function sjis_to_utf8(input)
    if not input or #input == 0 then return input end
    local src = ffi.new('char[?]', #input + 1)
    ffi.copy(src, input)
    local wlen = ffi.C.MultiByteToWideChar(932, 0, src, -1, nil, 0)
    local wbuf = ffi.new('wchar_t[?]', wlen)
    ffi.C.MultiByteToWideChar(932, 0, src, -1, wbuf, wlen)
    local clen = ffi.C.WideCharToMultiByte(65001, 0, wbuf, -1, nil, 0, nil, nil)
    local cbuf = ffi.new('char[?]', clen)
    ffi.C.WideCharToMultiByte(65001, 0, wbuf, -1, cbuf, clen, nil, nil)
    return ffi.string(cbuf)
end

function text.trim(s)
    if not s then
        return s
    end
    return s:match('^%s*(.-)%s*$')
end

function text.normalize_name(n)
    if not n then
        return ''
    end
    return text.trim(n):lower()
end

function text.normalize_chat_text(parsed_text, keep_translate_brackets)
    local clean = parsed_text:strip_colors():strip_translate(keep_translate_brackets == true)

    while clean:endswith('\n') or clean:endswith('\r') do
        if clean:endswith('\n') then clean = clean:trimend('\n') end
        if clean:endswith('\r') then clean = clean:trimend('\r') end
    end

    -- SimpleLog uses Shift-JIS arrow glyphs that ImGui default fonts can render as "??".
    -- Convert them to ASCII arrows so combat lines remain readable in this window.
    clean = clean:gsub(string.char(0x81, 0xA8), ' -> ')
    clean = clean:gsub(string.char(0x81, 0xAA), ' => ')
    clean = clean:gsub(string.char(0x81, 0xF4), '~')   -- music note ♪

    -- Convert any remaining Shift-JIS (CP932) bytes to valid UTF-8 so ImGui doesn't
    -- crash on sequences like 0x81 0xF4 (♪ music note).  0x07 is an ASCII control byte
    -- that CP932 passes through unchanged, so the gsub below still works after conversion.
    clean = sjis_to_utf8(clean)

    return clean:gsub(string.char(0x07), '\n')
end

function text.find_autotranslate_brace_indices(text_with_braces, text_without_braces)
    local with_text = text_with_braces or ''
    local without_text = text_without_braces or ''
    local brace_indices = {}

    local i, j = 1, 1
    while i <= #with_text do
        local c = with_text:sub(i, i)
        local d = without_text:sub(j, j)

        if j <= #without_text and c == d then
            i = i + 1
            j = j + 1
        elseif c == '{' or c == '}' then
            table.insert(brace_indices, i)
            i = i + 1
        else
            i = i + 1
            if j <= #without_text then
                j = j + 1
            end
        end
    end

    return brace_indices
end

function text.map_line_brace_indices(prefix_len, message_brace_indices)
    if type(message_brace_indices) ~= 'table' or #message_brace_indices == 0 then
        return nil
    end

    local mapped = {}
    for _, idx in ipairs(message_brace_indices) do
        if type(idx) == 'number' then
            local n = math.floor(idx)
            if n > 0 then
                table.insert(mapped, prefix_len + n)
            end
        end
    end

    if #mapped == 0 then
        return nil
    end

    return mapped
end

function text.format_message_line(time_text, sender_name, message_text, local_player_canonical, is_fixed_channel)
    message_text = message_text or ''

    if sender_name == nil or sender_name == '' then
        local prefix = string.format('[%s] ', time_text)
        return prefix .. message_text, #prefix
    end

    local is_self_channel_message = is_fixed_channel
        and local_player_canonical ~= ''
        and text.normalize_name(sender_name) == local_player_canonical
    if is_self_channel_message then
        local prefix = string.format('[%s] (%s) ', time_text, sender_name)
        return prefix .. message_text, #prefix
    end

    local prefix = string.format('[%s] %s: ', time_text, sender_name)
    return prefix .. message_text, #prefix
end

function text.create_renderer(imgui, ui_cfg, color_cfg)
    local function text_wrapped_bold(text_value)
        local x, y = imgui.GetCursorPos()
        imgui.TextWrapped(text_value)
        local after_x, after_y = imgui.GetCursorPos()
        imgui.SetCursorPos({ x + ui_cfg.bold_offset_x, y })
        imgui.TextWrapped(text_value)
        imgui.SetCursorPos({ after_x, after_y })
    end

    local function build_brace_masks(text_value, brace_indices)
        if text_value == nil or text_value == '' or type(brace_indices) ~= 'table' or #brace_indices == 0 then
            return nil, nil
        end

        local braces = {}
        for _, idx in ipairs(brace_indices) do
            if type(idx) == 'number' then
                local n = math.floor(idx)
                if n > 0 then
                    braces[n] = true
                end
            end
        end

        local open_parts = {}
        local close_parts = {}
        local has_open = false
        local has_close = false

        for i = 1, #text_value do
            local ch = text_value:sub(i, i)
            if ch == '\n' or ch == '\r' then
                open_parts[#open_parts + 1] = ch
                close_parts[#close_parts + 1] = ch
            elseif braces[i] and ch == '{' then
                open_parts[#open_parts + 1] = ch
                close_parts[#close_parts + 1] = ' '
                has_open = true
            elseif braces[i] and ch == '}' then
                open_parts[#open_parts + 1] = ' '
                close_parts[#close_parts + 1] = ch
                has_close = true
            else
                open_parts[#open_parts + 1] = ' '
                close_parts[#close_parts + 1] = ' '
            end
        end

        local open_mask = has_open and table.concat(open_parts) or nil
        local close_mask = has_close and table.concat(close_parts) or nil
        return open_mask, close_mask
    end

    local function text_wrapped_bold_with_translate_braces(text_value, brace_indices)
        local x, y = imgui.GetCursorPos()
        text_wrapped_bold(text_value)
        local after_x, after_y = imgui.GetCursorPos()

        local open_mask, close_mask = build_brace_masks(text_value, brace_indices)
        if open_mask ~= nil then
            imgui.SetCursorPos({ x, y })
            imgui.PushStyleColor(ImGuiCol_Text, color_cfg.autotranslate_open or { 0.25, 1.0, 0.25, 1.0 })
            text_wrapped_bold(open_mask)
            imgui.PopStyleColor()
        end

        if close_mask ~= nil then
            imgui.SetCursorPos({ x, y })
            imgui.PushStyleColor(ImGuiCol_Text, color_cfg.autotranslate_close or { 1.0, 0.25, 0.25, 1.0 })
            text_wrapped_bold(close_mask)
            imgui.PopStyleColor()
        end

        imgui.SetCursorPos({ after_x, after_y })
    end

    return {
        text_wrapped_bold_with_translate_braces = text_wrapped_bold_with_translate_braces,
    }
end

return text