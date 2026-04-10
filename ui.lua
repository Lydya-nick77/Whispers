local imgui = require('imgui')
local bit = require('bit')
local decoration = require('decoration')
local ffi = require('ffi')

pcall(ffi.cdef, [[
    int16_t GetKeyState(int32_t vkey);
]])

local ui = {}

-- Persistent across frames; track latest message identity per tab so autoscroll
-- still fires when the tab is capped and count does not increase.
local last_message_keys = {}
local last_message_refs = {}
local color_cache = {
    base_colors = nil,
    cfg = nil,
    colors = nil,
    value = nil,
}
local build_effective_colors

local function build_message_key(message)
    if not message then return nil end
    return table.concat({
        tostring(message.time or message.timestamp or ''),
        tostring(message.sender or ''),
        tostring(message.text or ''),
        tostring(message.chat_mode or ''),
        tostring(message.source_tab or ''),
    }, '|')
end


local VK_CONTROL = 0x11
local VK_SHIFT = 0x10
local VK_MENU = 0x12
local VK_TAB = 0x09

local function is_vkey_down(vkey)
    local ok, value = pcall(function()
        return ffi.C.GetKeyState(vkey)
    end)
    return ok and value and bit.band(value, 0x8000) ~= 0
end

local function build_main_tab_names(default_tabs, player_order, normalize_name)
    local names = {}
    for _, tab in ipairs(default_tabs) do
        local name = normalize_name(tab.canonical)
        names[#names + 1] = name
    end
    for _, name in ipairs(player_order) do
        names[#names + 1] = name
    end
    return names
end

local function resolve_effective_colors(base_colors, cfg, force_refresh)
    local cfg_colors = (cfg and cfg.colors) or nil
    if not force_refresh
        and color_cache.base_colors == base_colors
        and color_cache.cfg == cfg
        and color_cache.colors == cfg_colors
        and color_cache.value ~= nil then
        return color_cache.value
    end

    local resolved = build_effective_colors(base_colors, cfg)
    color_cache.base_colors = base_colors
    color_cache.cfg = cfg
    color_cache.colors = cfg_colors
    color_cache.value = resolved
    return resolved
end

local function ensure_selected_tab(state, tells, names)
    if state.selected ~= nil and tells[state.selected] ~= nil then
        for _, name in ipairs(names) do
            if name == state.selected then
                return
            end
        end
    end

    state.selected = nil
    for _, name in ipairs(names) do
        if tells[name] ~= nil then
            state.selected = name
            break
        end
    end
end

build_effective_colors = function(base_colors, cfg)
    local effective = {}
    for k, v in pairs(base_colors or {}) do
        if type(v) == 'table' then
            effective[k] = {
                tonumber(v[1]) or 1.0,
                tonumber(v[2]) or 1.0,
                tonumber(v[3]) or 1.0,
                tonumber(v[4]) or 1.0,
            }
        end
    end

    local saved = (cfg and cfg.colors) or {}
    for k, v in pairs(saved) do
        if type(v) == 'table' then
            effective[k] = {
                tonumber(v[1]) or 1.0,
                tonumber(v[2]) or 1.0,
                tonumber(v[3]) or 1.0,
                tonumber(v[4]) or 1.0,
            }
        end
    end

    return effective
end

local function push_xiui_config_theme()
    -- Matches XIDB chrome.lua push_theme() exactly: dark background with gold accents.
    local gold = { 0.957, 0.855, 0.592, 1.0 }
    local gold_dark = { 0.765, 0.684, 0.474, 1.0 }
    local gold_darker = { 0.573, 0.512, 0.355, 1.0 }
    local bg_dark = { 0.0, 0.0, 0.0, 1.0 }
    local bg_medium = { 0.098, 0.090, 0.075, 1.0 }
    local bg_light = { 0.137, 0.125, 0.106, 1.0 }
    local bg_lighter = { 0.176, 0.161, 0.137, 1.0 }
    local text_light = { 0.878, 0.855, 0.812, 1.0 }
    local border_dark = { 0.3, 0.275, 0.235, 1.0 }
    local border_gold = { gold_dark[1], gold_dark[2], gold_dark[3], 0.85 }
    local button_base = { 0.176, 0.149, 0.106, 0.95 }
    local button_hover = { 0.286, 0.239, 0.165, 0.95 }
    local button_active = { 0.420, 0.353, 0.243, 0.95 }

    imgui.PushStyleColor(ImGuiCol_WindowBg, bg_dark)
    imgui.PushStyleColor(ImGuiCol_ChildBg, { 0, 0, 0, 0 })
    imgui.PushStyleColor(ImGuiCol_TitleBg, bg_medium)
    imgui.PushStyleColor(ImGuiCol_TitleBgActive, bg_light)
    imgui.PushStyleColor(ImGuiCol_TitleBgCollapsed, bg_dark)
    imgui.PushStyleColor(ImGuiCol_FrameBg, { 0.125, 0.110, 0.086, 0.98 })
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, { 0.173, 0.153, 0.122, 0.98 })
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, { 0.231, 0.200, 0.157, 0.98 })
    imgui.PushStyleColor(ImGuiCol_Header, bg_light)
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, bg_lighter)
    imgui.PushStyleColor(ImGuiCol_HeaderActive, { gold[1], gold[2], gold[3], 0.3 })
    imgui.PushStyleColor(ImGuiCol_Border, border_gold)
    imgui.PushStyleColor(ImGuiCol_Text, text_light)
    imgui.PushStyleColor(ImGuiCol_TextDisabled, gold_dark)
    imgui.PushStyleColor(ImGuiCol_Button, button_base)
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, button_hover)
    imgui.PushStyleColor(ImGuiCol_ButtonActive, button_active)
    imgui.PushStyleColor(ImGuiCol_CheckMark, gold)
    imgui.PushStyleColor(ImGuiCol_SliderGrab, gold_dark)
    imgui.PushStyleColor(ImGuiCol_SliderGrabActive, gold)
    imgui.PushStyleColor(ImGuiCol_ScrollbarBg, bg_medium)
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrab, bg_lighter)
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabHovered, border_dark)
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabActive, gold_dark)
    imgui.PushStyleColor(ImGuiCol_Separator, border_dark)
    imgui.PushStyleColor(ImGuiCol_PopupBg, bg_medium)
    imgui.PushStyleColor(ImGuiCol_Tab, bg_medium)
    imgui.PushStyleColor(ImGuiCol_TabHovered, bg_light)
    imgui.PushStyleColor(ImGuiCol_TabActive, { gold[1], gold[2], gold[3], 0.3 })
    imgui.PushStyleColor(ImGuiCol_TabUnfocused, bg_dark)
    imgui.PushStyleColor(ImGuiCol_TabUnfocusedActive, bg_medium)
    imgui.PushStyleColor(ImGuiCol_ResizeGrip, gold_darker)
    imgui.PushStyleColor(ImGuiCol_ResizeGripHovered, gold_dark)
    imgui.PushStyleColor(ImGuiCol_ResizeGripActive, gold)

    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 12, 12 })
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 8, 6 })
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 8, 7 })
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4.0)
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6.0)
    imgui.PushStyleVar(ImGuiStyleVar_ChildRounding, 4.0)
    imgui.PushStyleVar(ImGuiStyleVar_PopupRounding, 4.0)
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarRounding, 4.0)
    imgui.PushStyleVar(ImGuiStyleVar_GrabRounding, 4.0)
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 1.0)
    imgui.PushStyleVar(ImGuiStyleVar_ChildBorderSize, 1.0)
    imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1.0)
end

local function pop_xiui_config_theme()
    imgui.PopStyleVar(12)
    imgui.PopStyleColor(34)
end

local function build_config_sections(context)
    local sections = {
        { key = 'global', label = 'Global' },
    }

    local default_tabs = (context.config and context.config.default_tabs) or {}
    for _, tab in ipairs(default_tabs) do
        local canonical = context.normalize_name(tab.canonical or '')
        if canonical ~= '' then
            table.insert(sections, {
                key = canonical,
                label = tostring(tab.display or tab.canonical or canonical),
            })
        end
    end

    table.insert(sections, { key = 'tells', label = 'Tells' })

    return sections
end

local function get_unread_blink_tabs_for_edit(cfg, base_unread_cfg)
    cfg.unread = cfg.unread or {}
    cfg.unread.blink_tabs = cfg.unread.blink_tabs or {}
    local edited = cfg.unread.blink_tabs
    local base = (base_unread_cfg and base_unread_cfg.blink_tabs) or {}

    local function get_value(tab_name)
        if edited[tab_name] ~= nil then
            return edited[tab_name] ~= false
        end
        if base[tab_name] ~= nil then
            return base[tab_name] ~= false
        end
        if edited.default ~= nil then
            return edited.default ~= false
        end
        if base.default ~= nil then
            return base.default ~= false
        end
        return true
    end

    return edited, get_value
end

local function get_section_blink_target(context, section_key)
    if section_key == 'tells' then
        return 'default', 'Tells (Player Tabs)'
    end

    local default_tabs = (context.config and context.config.default_tabs) or {}
    for _, tab in ipairs(default_tabs) do
        local canonical = context.normalize_name(tab.canonical or '')
        if canonical == section_key then
            local label = tostring(tab.display or tab.canonical or canonical)
            return canonical, label
        end
    end

    return nil, nil
end

local function get_section_color_entries(context, section_key)
    if section_key == 'tells' then
        return {
            { key = 'tell', label = 'Tell Messages' },
        }
    end
    if section_key == context.linkshell1_tab then
        return {
            { key = 'linkshell1', label = 'Linkshell 1' },
        }
    end
    if section_key == context.linkshell2_tab then
        return {
            { key = 'linkshell2', label = 'Linkshell 2' },
        }
    end
    if section_key == context.party_tab then
        return {
            { key = 'party', label = 'Party' },
        }
    end
    if section_key == context.say_tab then
        return {
            { key = 'say', label = 'Say' },
        }
    end

    return {}
end

local function tab_color_row(label, cfg, context, key, base_colors, cflags)
    local default_color = (base_colors and base_colors[key]) or { 1.0, 1.0, 1.0, 1.0 }
    local saved_colors = cfg.colors or {}
    local src = saved_colors[key] or default_color
    local c = T{ src[1] or 1.0, src[2] or 1.0, src[3] or 1.0, (src[4] ~= nil) and src[4] or 1.0 }
    if imgui.ColorEdit4(label .. '##tab_color_' .. key, c, cflags) then
        cfg.colors = cfg.colors or {}
        cfg.colors[key] = { c[1], c[2], c[3], c[4] }
        context.settings.save()
    end
end

local function render_config_window(context)
    local state = context.state
    if not state.config_is_open or not state.config_is_open[1] then
        return
    end

    push_xiui_config_theme()

    imgui.SetNextWindowSize({ 900, 650 }, ImGuiCond_FirstUseEver)
    imgui.SetNextWindowPos({ 50, 50 }, ImGuiCond_FirstUseEver)
    local title = 'Whispers config - v' .. tostring(context.addon_version or '')
    local no_saved_settings = tonumber(ImGuiWindowFlags_NoSavedSettings) or 0
    local no_docking = tonumber(ImGuiWindowFlags_NoDocking) or 0
    local no_collapse = tonumber(ImGuiWindowFlags_NoCollapse) or 0
    local flags = bit.bor(no_saved_settings, no_docking, no_collapse)
    if imgui.Begin(title, state.config_is_open, flags) then
        local gold = { 0.957, 0.855, 0.592, 1.0 }
        local border_dark = { 0.3, 0.275, 0.235, 1.0 }
        local tab_color = { 0.098, 0.090, 0.075, 1.0 }
        local tab_hover_color = { 0.137, 0.125, 0.106, 1.0 }
        local tab_active_color = { gold[1], gold[2], gold[3], 0.3 }
        local tab_selected_color = { gold[1], gold[2], gold[3], 0.25 }
        local button_hover_color = { 0.137, 0.125, 0.106, 1.0 }
        local button_active_color = { 0.176, 0.161, 0.137, 1.0 }
        local selected_button_color = { gold[1], gold[2], gold[3], 0.25 }

        local sections = build_config_sections(context)
        if type(state.config_selected_section) ~= 'string' or state.config_selected_section == '' then
            state.config_selected_section = sections[1].key
        end

        local selected_exists = false
        for _, section in ipairs(sections) do
            if section.key == state.config_selected_section then
                selected_exists = true
                break
            end
        end
        if not selected_exists then
            state.config_selected_section = sections[1].key
        end
        if state.config_selected_mode ~= 'settings' and state.config_selected_mode ~= 'color settings' then
            state.config_selected_mode = 'settings'
        end

        local sidebar_width = 180

        imgui.BeginChild('WhispersConfigSidebar', { sidebar_width, 0 }, false)
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 10, 8 })

        for _, section in ipairs(sections) do
            local is_selected = (section.key == state.config_selected_section)
            if is_selected then
                imgui.PushStyleColor(ImGuiCol_Button, selected_button_color)
                imgui.PushStyleColor(ImGuiCol_ButtonHovered, selected_button_color)
                imgui.PushStyleColor(ImGuiCol_ButtonActive, selected_button_color)
            else
                imgui.PushStyleColor(ImGuiCol_Button, { 0, 0, 0, 0 })
                imgui.PushStyleColor(ImGuiCol_ButtonHovered, button_hover_color)
                imgui.PushStyleColor(ImGuiCol_ButtonActive, button_active_color)
            end

            local btn_pos_x, btn_pos_y = imgui.GetCursorScreenPos()
            if imgui.Button(section.label, { sidebar_width - 16, 32 }) then
                state.config_selected_section = section.key
            end

            if is_selected then
                local draw_list = imgui.GetWindowDrawList()
                draw_list:AddRectFilled(
                    { btn_pos_x, btn_pos_y + 4 },
                    { btn_pos_x + 3, btn_pos_y + 28 },
                    imgui.GetColorU32(gold),
                    1.5
                )
            end

            imgui.PopStyleColor(3)
        end

        imgui.PopStyleVar()
        imgui.EndChild()

        imgui.SameLine()

        imgui.BeginChild('WhispersConfigContent', { 0, 0 }, false)
        local selected_label = 'Global'
        for _, section in ipairs(sections) do
            if section.key == state.config_selected_section then
                selected_label = section.label
                break
            end
        end

        local tab_width = 140
        local tab_height = 28

        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 12, 6 })

        local settings_tab_pos_x, settings_tab_pos_y = imgui.GetCursorScreenPos()
        if state.config_selected_mode == 'settings' then
            imgui.PushStyleColor(ImGuiCol_Button, tab_selected_color)
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, tab_selected_color)
            imgui.PushStyleColor(ImGuiCol_ButtonActive, tab_selected_color)
        else
            imgui.PushStyleColor(ImGuiCol_Button, tab_color)
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, tab_hover_color)
            imgui.PushStyleColor(ImGuiCol_ButtonActive, tab_active_color)
        end
        if imgui.Button('settings', { tab_width, tab_height }) then
            state.config_selected_mode = 'settings'
        end
        if state.config_selected_mode == 'settings' then
            local draw_list = imgui.GetWindowDrawList()
            draw_list:AddRectFilled(
                { settings_tab_pos_x + 4, settings_tab_pos_y + tab_height - 3 },
                { settings_tab_pos_x + tab_width - 4, settings_tab_pos_y + tab_height },
                imgui.GetColorU32(gold),
                1.0
            )
        end
        imgui.PopStyleColor(3)

        imgui.SameLine()

        local color_tab_pos_x, color_tab_pos_y = imgui.GetCursorScreenPos()
        if state.config_selected_mode == 'color settings' then
            imgui.PushStyleColor(ImGuiCol_Button, tab_selected_color)
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, tab_selected_color)
            imgui.PushStyleColor(ImGuiCol_ButtonActive, tab_selected_color)
        else
            imgui.PushStyleColor(ImGuiCol_Button, tab_color)
            imgui.PushStyleColor(ImGuiCol_ButtonHovered, tab_hover_color)
            imgui.PushStyleColor(ImGuiCol_ButtonActive, tab_active_color)
        end
        if imgui.Button('color settings', { tab_width, tab_height }) then
            state.config_selected_mode = 'color settings'
        end
        if state.config_selected_mode == 'color settings' then
            local draw_list = imgui.GetWindowDrawList()
            draw_list:AddRectFilled(
                { color_tab_pos_x + 4, color_tab_pos_y + tab_height - 3 },
                { color_tab_pos_x + tab_width - 4, color_tab_pos_y + tab_height },
                imgui.GetColorU32(gold),
                1.0
            )
        end
        imgui.PopStyleColor(3)
        imgui.PopStyleVar()

        imgui.Spacing()
        imgui.PushStyleColor(ImGuiCol_Separator, border_dark)
        imgui.Separator()
        imgui.PopStyleColor()
        imgui.Spacing()

        imgui.BeginChild('WhispersConfigSettingsContent', { 0, 0 }, false)
        local cfg = context.get_cfg()
        local min_scale = tonumber((context.ui_cfg or {}).min_font_scale) or 0.5
        if state.config_selected_mode == 'settings' then
            if state.config_selected_section == 'global' then
                local default_open = tonumber(ImGuiTreeNodeFlags_DefaultOpen) or 32
                imgui.PushStyleColor(ImGuiCol_Header,        { gold[1], gold[2], gold[3], 0.15 })
                imgui.PushStyleColor(ImGuiCol_HeaderHovered, { gold[1], gold[2], gold[3], 0.25 })
                if imgui.CollapsingHeader('Font Settings', default_open) then
                    imgui.Spacing()
                    local fs_default = tonumber((context.config and context.config.font_scale) or 1.0)
                    local fs = T{ tonumber(cfg.font_scale or fs_default) }
                    imgui.SetNextItemWidth(200)
                    if imgui.SliderFloat('##global_font_scale', fs, min_scale, 2.0) then
                        cfg.font_scale = math.max(min_scale, fs[1])
                        context.settings.save()
                    end
                    imgui.SameLine()
                    imgui.Text('Font Scale')
                    imgui.Spacing()
                    local mfs_default = tonumber((context.config and context.config.message_font_scale) or 1.1)
                    local mfs = T{ tonumber(cfg.message_font_scale or mfs_default) }
                    imgui.SetNextItemWidth(200)
                    if imgui.SliderFloat('##global_msg_font_scale', mfs, min_scale, 2.0) then
                        cfg.message_font_scale = math.max(min_scale, mfs[1])
                        context.settings.save()
                    end
                    imgui.SameLine()
                    imgui.Text('Message Font Scale')
                    imgui.Spacing()
                    local opacity_val = T{ tonumber(cfg.window_bg_opacity) or 0.95 }
                    imgui.SetNextItemWidth(200)
                    if imgui.SliderFloat('##global_opacity', opacity_val, 0.0, 1.0) then
                        cfg.window_bg_opacity = math.max(0.0, math.min(1.0, opacity_val[1]))
                        context.settings.save()
                    end
                    imgui.SameLine()
                    imgui.Text('Window Transparency')
                    imgui.Spacing()
                end
                imgui.Spacing()
                if imgui.CollapsingHeader('Log Files & Limits##global_logs', 0) then
                    local base_behavior = (context.config and context.config.behavior) or {}
                    local storage_defaults = (context.get_storage_defaults and context.get_storage_defaults()) or {}
                    local default_ttl_secs = tonumber(storage_defaults.ttl_seconds or base_behavior.message_ttl_seconds) or 86400
                    local default_max_lines = tonumber(storage_defaults.max_messages_per_tab or base_behavior.max_messages_per_tab) or 300

                    imgui.Spacing()
                    imgui.Text('Chat Log File (messages.dat)')

                    local chat_ttl_hours = T{ math.max(1, math.floor(((tonumber(cfg.chat_ttl_seconds) or default_ttl_secs) + 1800) / 3600)) }
                    imgui.SetNextItemWidth(200)
                    if imgui.SliderInt('##chat_ttl_hours_global', chat_ttl_hours, 1, 720) then
                        cfg.chat_ttl_seconds = math.max(60, math.floor(chat_ttl_hours[1] * 3600))
                        if context.apply_storage_constraints then context.apply_storage_constraints(false) end
                        context.settings.save()
                    end
                    imgui.SameLine()
                    imgui.Text('TTL (hours)')

                    local chat_max_lines = T{ math.max(1, math.floor(tonumber(cfg.chat_max_messages_per_tab) or default_max_lines)) }
                    imgui.SetNextItemWidth(200)
                    if imgui.SliderInt('##chat_max_lines_global', chat_max_lines, 1, 5000) then
                        cfg.chat_max_messages_per_tab = math.max(1, math.floor(chat_max_lines[1]))
                        if context.apply_storage_constraints then context.apply_storage_constraints(false) end
                        context.settings.save()
                    end
                    imgui.SameLine()
                    imgui.Text('Max lines kept per chat tab')

                    imgui.Spacing()
                end
                imgui.PopStyleColor(2)
            else
                local blink_key, blink_label = get_section_blink_target(context, state.config_selected_section)
                if blink_key ~= nil then
                    local edited_blink_tabs, get_blink_value = get_unread_blink_tabs_for_edit(cfg, context.unread_cfg)
                    local checkbox_id = tostring(blink_key):gsub('[^%w_]', '_')
                    local blink_value = T{ get_blink_value(blink_key) }

                    imgui.Spacing()
                    imgui.Text('Unread Blink')
                    if imgui.Checkbox('Blink tab when new messages are received##blink_section_' .. checkbox_id, blink_value) then
                        edited_blink_tabs[blink_key] = (blink_value[1] == true)
                        context.settings.save()
                    end
                    imgui.SameLine()
                    imgui.TextDisabled('(' .. blink_label .. ')')
                end
                if blink_key == nil then
                    imgui.Text(selected_label .. ' settings coming soon.')
                end
            end
        else
            if state.config_selected_section == 'global' then
                imgui.Text('Select a tab on the left to edit its colors.')
            else
                local entries = get_section_color_entries(context, state.config_selected_section)
                if #entries > 0 then
                    local base_colors = (context.config and context.config.colors) or {}
                    local cflags = bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs)
                    imgui.Spacing()
                    for _, entry in ipairs(entries) do
                        tab_color_row(entry.label, cfg, context, entry.key, base_colors, cflags)
                    end
                    imgui.Spacing()
                else
                    imgui.Text(selected_label .. ' color settings coming soon.')
                end
            end
        end
        imgui.EndChild()
        imgui.EndChild()
    end
    imgui.End()

    pop_xiui_config_theme()
end

local function is_unread_blink_enabled(base_unread_cfg, unread_override, tab_name)
    local override_tabs = (type(unread_override) == 'table' and type(unread_override.blink_tabs) == 'table') and unread_override.blink_tabs or nil
    local base_tabs = (type(base_unread_cfg) == 'table' and type(base_unread_cfg.blink_tabs) == 'table') and base_unread_cfg.blink_tabs or nil

    if override_tabs ~= nil and override_tabs[tab_name] ~= nil then
        return override_tabs[tab_name] ~= false
    end
    if base_tabs ~= nil and base_tabs[tab_name] ~= nil then
        return base_tabs[tab_name] ~= false
    end
    if override_tabs ~= nil and override_tabs.default ~= nil then
        return override_tabs.default ~= false
    end
    if base_tabs ~= nil and base_tabs.default ~= nil then
        return base_tabs.default ~= false
    end

    return true
end

local function is_focus_input_shortcut_down(context)
    local shortcut_cfg = (((context.ui_cfg or {}).shortcuts or {}).focus_input or {})
    if shortcut_cfg.enabled == false then
        return false
    end

    local vkey = tonumber(shortcut_cfg.vkey or 0)
    if vkey <= 0 then
        return false
    end

    -- Never allow TAB to act as the focus-input shortcut;
    -- TAB is used for navigation in-game and should not focus this input.
    if vkey == VK_TAB then
        return false
    end

    if shortcut_cfg.require_ctrl and not is_vkey_down(VK_CONTROL) then
        return false
    end
    if shortcut_cfg.require_shift and not is_vkey_down(VK_SHIFT) then
        return false
    end
    if shortcut_cfg.require_alt and not is_vkey_down(VK_MENU) then
        return false
    end

    return is_vkey_down(vkey)
end

local function update_focus_input_request(context)
    local shortcut_down = is_focus_input_shortcut_down(context)
    local was_down = context.state.focus_shortcut_was_down == true
    context.state.focus_shortcut_was_down = shortcut_down

    if not shortcut_down or was_down then
        return
    end

    local selected = context.state.selected
    if selected ~= nil and not context.is_read_only_tab(selected) then
        context.state.focus_input_requested = selected
    end
end

local function render_message(context, name, display, message, local_player_canonical, party_member_canonicals, visible_player_canonicals, hostile_actor_canonicals, is_fixed_channel, is_linkshell, is_linkshell1, is_linkshell2, is_say)
    local color_cfg = context.effective_color_cfg or context.color_cfg
    local normalize_name = context.normalize_name

    -- Lazy render cache: the expensive per-message string operations (os.date, format_message_line,
    -- map_line_brace_indices, regex extraction) are computed once and reused on every subsequent frame.
    -- The cache is invalidated only when local_player_canonical changes (essentially never mid-session).
    local rc = message._rc
    if rc == nil or rc.pc ~= local_player_canonical then
        rc = { pc = local_player_canonical }

        local raw_text = message.text or ''
        local display_text = raw_text

        local sender_for_fmt = message.sender
        if sender_for_fmt ~= nil and is_fixed_channel then
            local sender_c = normalize_name(sender_for_fmt)
            local display_c = normalize_name(display)
            if sender_c == '' or sender_c == name or sender_c == display_c then
                sender_for_fmt = nil
            end
        end

        local lt, prefix_len = context.format_message_line(
            os.date(context.msg_cfg.timestamp_format, message.time),
            sender_for_fmt,
            display_text,
            local_player_canonical,
            is_fixed_channel)
        rc.lt = lt
        rc.lb = context.map_line_brace_indices(prefix_len, message.auto_translate_braces)

        message._rc = rc
    end

    local line_text   = rc.lt
    local line_braces = rc.lb

    if is_linkshell then
        if is_linkshell1 then
            imgui.PushStyleColor(ImGuiCol_Text, color_cfg.linkshell1)
        elseif is_linkshell2 then
            imgui.PushStyleColor(ImGuiCol_Text, color_cfg.linkshell2)
        end
        context.text_wrapped_bold_with_translate_braces(line_text, line_braces)
        if is_linkshell1 or is_linkshell2 then
            imgui.PopStyleColor()
        end
    elseif is_say then
        local say_color = color_cfg.say or { 1.0, 1.0, 1.0, 1.0 }
        imgui.PushStyleColor(ImGuiCol_Text, say_color)
        context.text_wrapped_bold_with_translate_braces(line_text, line_braces)
        imgui.PopStyleColor()
    else
        local line_color
        if name == 'party' then
            line_color = color_cfg.party or color_cfg.tell
        else
            line_color = color_cfg.tell
        end
        imgui.PushStyleColor(ImGuiCol_Text, line_color)
        context.text_wrapped_bold_with_translate_braces(line_text, line_braces)
        imgui.PopStyleColor()
    end
end

function ui.render(context)
    local state = context.state
    local show_config_window = state.config_is_open and state.config_is_open[1]
    if not state.is_open[1] and not show_config_window then
        return
    end

    local cfg = context.get_cfg()
    local tells = context.get_tells()
    local display_names = context.get_display_names()
    local unread = context.get_unread()
    local last_msg_count = context.get_last_msg_count()
    local player_order = context.get_player_order()
    local config = context.config
    local ui_cfg = context.ui_cfg
    local base_unread_cfg = context.unread_cfg or {}
    local unread_override = (cfg and cfg.unread) or {}
    local blink_speed_hz = tonumber(unread_override.blink_speed_hz) or tonumber(base_unread_cfg.blink_speed_hz) or 2
    local unread_tab_color_a = unread_override.tab_color_a or base_unread_cfg.tab_color_a
    local unread_tab_color_b = unread_override.tab_color_b or base_unread_cfg.tab_color_b
    local blink_on = (math.floor(os.clock() * blink_speed_hz) % 2) == 0
    local chat_layout_cfg = ui_cfg.chat_layout or {}
    local read_only_footer_padding = tonumber(chat_layout_cfg.read_only_footer_padding) or 12
    local input_row_padding = tonumber(chat_layout_cfg.input_row_padding) or 12
    local min_chat_height = tonumber(chat_layout_cfg.min_chat_height) or 1

    cfg.window = cfg.window or {
        x = config.default_window.x,
        y = config.default_window.y,
        width = config.default_window.width,
        height = config.default_window.height,
    }

    local local_player_canonical = context.normalize_name(context.get_local_player_name() or '')
    local party_member_canonicals = context.get_party_member_canonicals and context.get_party_member_canonicals() or {}
    local visible_player_canonicals = context.get_visible_player_canonicals and context.get_visible_player_canonicals() or {}
    local visible_non_player_canonicals = context.get_visible_non_player_canonicals and context.get_visible_non_player_canonicals() or {}

    local style = config.style
    local effective_color_cfg = resolve_effective_colors(context.color_cfg, cfg, show_config_window)
    context.effective_color_cfg = effective_color_cfg
    local style_var_count, style_color_count = decoration.push(style, cfg.window_bg_opacity)
    local window_flags = decoration.window_flags(style)
    local font_scale = tonumber(cfg.font_scale or config.font_scale) or config.font_scale
    if font_scale < ui_cfg.min_font_scale then
        font_scale = ui_cfg.min_font_scale
    end
    local message_font_scale = tonumber(cfg.message_font_scale or config.message_font_scale) or font_scale
    if message_font_scale < ui_cfg.min_font_scale then
        message_font_scale = ui_cfg.min_font_scale
    end

    if state.is_open[1] then
        imgui.SetNextWindowPos({ cfg.window.x, cfg.window.y }, ImGuiCond_FirstUseEver)
        imgui.SetNextWindowSize({ cfg.window.width, cfg.window.height }, ImGuiCond_FirstUseEver)

        if imgui.Begin('Whispers', state.is_open, window_flags) then
            imgui.SetWindowFontScale(font_scale)

            if next(tells) == nil then
                imgui.Text(context.msg_cfg.no_recent_tells)
            else
                if imgui.BeginTabBar('##WhispersTabBar', decoration.tab_bar_flags(style)) then
                    local names = build_main_tab_names(config.default_tabs, player_order, context.normalize_name)
                    ensure_selected_tab(state, tells, names)
                    update_focus_input_request(context)

                    for _, name in ipairs(names) do
                        if tells[name] == nil then goto skip_missing_tab end

                        local msgs = tells[name]
                        local display = display_names[name] or name
                        local is_unread = unread[name] and (state.selected ~= name)
                        local blink_unread = is_unread and is_unread_blink_enabled(base_unread_cfg, unread_override, name)
                        local label = display .. '##' .. name
                        local pushed = 0
                        local tab_flags = ImGuiTabItemFlags_None
                        if is_unread then
                            tab_flags = bit.bor(tab_flags, ImGuiTabItemFlags_UnsavedDocument)
                        end
                        if blink_unread then
                            local clr = blink_on and unread_tab_color_a or unread_tab_color_b
                            imgui.PushStyleColor(ImGuiCol_TabActive, clr); pushed = pushed + 1
                            imgui.PushStyleColor(ImGuiCol_Tab, clr); pushed = pushed + 1
                        end
                        if state.selected == name then
                            tab_flags = bit.bor(tab_flags, ImGuiTabItemFlags_SetSelected)
                        end

                        local opened = imgui.BeginTabItem(label, nil, tab_flags)
                        if imgui.IsItemClicked(0) then
                            state.selected = name
                            unread[name] = nil
                        end
                        if pushed > 0 then
                            for i = 1, pushed do
                                imgui.PopStyleColor()
                            end
                        end

                        if opened then
                            if state.selected == name then
                                unread[name] = nil
                            end

                            local was_newly_selected = (last_msg_count[name] == nil)
                            local is_linkshell = context.is_linkshell_tab(name)
                            local is_fixed_channel = context.is_fixed_channel_tab(name)
                            local is_linkshell1 = (name == context.linkshell1_tab)
                            local is_linkshell2 = (name == context.linkshell2_tab)
                            local is_say = (name == context.say_tab)
                            local is_read_only = context.is_read_only_tab(name)
                            local is_all_tab = (name == 'all')
                            local _, avail_height = imgui.GetContentRegionAvail()
                            local line_height = imgui.GetTextLineHeight()
                            local controls_reserved_height = line_height + read_only_footer_padding
                            controls_reserved_height = controls_reserved_height + line_height + input_row_padding
                            if is_all_tab then
                                controls_reserved_height = 0
                            end
                            local chat_height = math.max(min_chat_height, (avail_height or 0) - controls_reserved_height)

                            imgui.BeginChild('##chat_' .. name, { 0, chat_height }, false)
                            imgui.SetWindowFontScale(message_font_scale)

                            if is_all_tab then
                                -- Build a merged, time-sorted view of all other tabs
                                local all_msgs = {}
                                for src_name, src_msgs in pairs(tells) do
                                    if src_name ~= 'all' and type(src_msgs) == 'table' then
                                        for _, msg in ipairs(src_msgs) do
                                            table.insert(all_msgs, { msg = msg, tab = src_name })
                                        end
                                    end
                                end
                                table.sort(all_msgs, function(a, b)
                                    return (a.msg.time or 0) < (b.msg.time or 0)
                                end)
                                for _, entry in ipairs(all_msgs) do
                                    local src = entry.tab
                                    local src_display = display_names[src] or src
                                    local src_is_linkshell = context.is_linkshell_tab(src)
                                    local src_is_fixed = context.is_fixed_channel_tab(src)
                                    local src_is_ls1 = (src == context.linkshell1_tab)
                                    local src_is_ls2 = (src == context.linkshell2_tab)
                                    local src_is_say = (src == context.say_tab)
                                    render_message(context, src, src_display, entry.msg, local_player_canonical, party_member_canonicals, visible_player_canonicals, visible_non_player_canonicals, src_is_fixed, src_is_linkshell, src_is_ls1, src_is_ls2, src_is_say)
                                end
                                local total_count = #all_msgs
                                if total_count > (last_msg_count[name] or 0) or was_newly_selected then
                                    imgui.SetScrollHereY(ui_cfg.scroll_to_bottom_fraction or 1.0)
                                end
                                last_msg_count[name] = total_count
                                last_message_keys[name] = nil
                                last_message_refs[name] = nil
                            else
                                for i = 1, #msgs do
                                    render_message(context, name, display, msgs[i], local_player_canonical, party_member_canonicals, visible_player_canonicals, visible_non_player_canonicals, is_fixed_channel, is_linkshell, is_linkshell1, is_linkshell2, is_say)
                                end
                                local latest_message = msgs[#msgs]
                                local latest_key = build_message_key(latest_message)
                                local latest_ref_changed = (latest_message ~= nil and latest_message ~= last_message_refs[name])
                                local has_new_message = (#msgs > (last_msg_count[name] or 0))
                                    or latest_ref_changed
                                    or (latest_key ~= nil and latest_key ~= last_message_keys[name])
                                if has_new_message or was_newly_selected then
                                    imgui.SetScrollHereY(ui_cfg.scroll_to_bottom_fraction or 1.0)
                                end
                                last_msg_count[name] = #msgs
                                last_message_keys[name] = latest_key
                                last_message_refs[name] = latest_message
                            end
                            imgui.EndChild()

                            if not is_all_tab then
                                imgui.Separator()
                                if not is_read_only then
                                    local input_id = '##whispers_input_' .. name
                                    if state.focus_input_requested == name then
                                        imgui.SetKeyboardFocusHere()
                                        state.focus_input_requested = nil
                                    end
                                    -- Keep this text box clickable, but out of TAB focus traversal.
                                    local tab_focus_guard = nil
                                    if imgui.PushItemFlag ~= nil and imgui.PopItemFlag ~= nil and ImGuiItemFlags_NoTabStop ~= nil then
                                        imgui.PushItemFlag(ImGuiItemFlags_NoTabStop, true)
                                        tab_focus_guard = 'item_flag'
                                    elseif imgui.PushAllowKeyboardFocus ~= nil and imgui.PopAllowKeyboardFocus ~= nil then
                                        imgui.PushAllowKeyboardFocus(false)
                                        tab_focus_guard = 'allow_keyboard_focus'
                                    end

                                    local enter_pressed = imgui.InputText(input_id, state.input_text, ui_cfg.input_max_length, ImGuiInputTextFlags_EnterReturnsTrue)

                                    if tab_focus_guard == 'item_flag' then
                                        imgui.PopItemFlag()
                                    elseif tab_focus_guard == 'allow_keyboard_focus' then
                                        imgui.PopAllowKeyboardFocus()
                                    end
                                    if enter_pressed then
                                        context.queue_tab_message(name, display, state.input_text[1] or '')
                                    end

                                    imgui.SameLine()
                                end

                                if imgui.Button('Clear') then
                                    context.clear_tab(name)
                                end

                                if is_read_only then
                                    -- Keep footer height consistent so switching tabs does not visually resize content.
                                    imgui.Dummy({ 0, line_height + input_row_padding })
                                end
                            end

                            imgui.EndTabItem()
                        end

                        ::skip_missing_tab::
                    end

                    imgui.EndTabBar()
                end
            end
 
            local posX, posY = imgui.GetWindowPos()
            local sizeX, sizeY = imgui.GetWindowSize()
            local changed = false
            if posX ~= cfg.window.x then cfg.window.x = posX; changed = true end
            if posY ~= cfg.window.y then cfg.window.y = posY; changed = true end
            if sizeX ~= cfg.window.width then cfg.window.width = sizeX; changed = true end
            if sizeY ~= cfg.window.height then cfg.window.height = sizeY; changed = true end
            if changed then
                context.settings.save()
            end

            imgui.End()
        end
    end

    decoration.pop(style_var_count, style_color_count)
    render_config_window(context)
end

return ui