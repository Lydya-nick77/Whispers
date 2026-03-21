local imgui = require('imgui')
local bit = require('bit')
local decoration = require('decoration')
local ffi = require('ffi')
local windowBg = require('windowbackground')

-- Module-level background handles (created lazily, persist across frames)
local _bg = {
    main        = nil,
    main_theme  = nil,
    combat      = nil,
    combat_theme = nil,
}

pcall(ffi.cdef, [[
    int16_t GetKeyState(int32_t vkey);
]])

local ui = {}

-- Persistent across frames; track latest message identity per tab so autoscroll
-- still fires when the tab is capped and count does not increase.
local last_message_keys = {}
local last_message_refs = {}
local combat_last_message_key = nil
local style_cache = {
    base_config = nil,
    cfg = nil,
    theme = nil,
    value = nil,
}
local color_cache = {
    base_colors = nil,
    cfg = nil,
    colors = nil,
    value = nil,
}
local build_effective_style
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
local VK_ESCAPE = 0x1B
local all_tab_shortcut_commands = {
    [0x48] = '/sh',
    [0x4C] = '/l',
    [0x50] = '/p',
    [0x53] = '/s',
    [0x54] = '/t',
    [0x59] = '/y',
}

local function is_vkey_down(vkey)
    local ok, value = pcall(function()
        return ffi.C.GetKeyState(vkey)
    end)
    return ok and value and bit.band(value, 0x8000) ~= 0
end

local function build_main_tab_names(default_tabs, player_order, normalize_name, combat_tab)
    local names = {}
    for _, tab in ipairs(default_tabs) do
        local name = normalize_name(tab.canonical)
        if name ~= combat_tab then
            names[#names + 1] = name
        end
    end
    for _, name in ipairs(player_order) do
        if name ~= combat_tab then
            names[#names + 1] = name
        end
    end
    return names
end

local function resolve_effective_style(base_config, cfg, force_refresh)
    local cfg_theme = (cfg and cfg.theme) or nil
    if not force_refresh
        and style_cache.base_config == base_config
        and style_cache.cfg == cfg
        and style_cache.theme == cfg_theme
        and style_cache.value ~= nil then
        return style_cache.value
    end

    local resolved = build_effective_style(base_config, cfg)
    style_cache.base_config = base_config
    style_cache.cfg = cfg
    style_cache.theme = cfg_theme
    style_cache.value = resolved
    return resolved
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

build_effective_style = function(base_config, cfg)
    local config_style = base_config.style or {}
    local effective = {}
    for k, v in pairs(config_style) do effective[k] = v end
    local base_theme = {}
    for k, v in pairs(config_style.theme or {}) do base_theme[k] = v end
    local saved = (cfg and cfg.theme) or {}
    for k, v in pairs(saved) do
        if type(v) == 'table' then
            base_theme[k] = v
        elseif type(v) == 'number' then
            effective[k] = v
        end
    end
    effective.theme = base_theme
    return effective
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
    -- Match XIUI config window look-and-feel: dark background with gold accents.
    local gold = { 0.957, 0.855, 0.592, 1.0 }
    local gold_dark = { 0.765, 0.684, 0.474, 1.0 }
    local gold_darker = { 0.573, 0.512, 0.355, 1.0 }
    local bg_dark = { 0.051, 0.051, 0.051, 0.95 }
    local bg_medium = { 0.098, 0.090, 0.075, 1.0 }
    local bg_light = { 0.137, 0.125, 0.106, 1.0 }
    local bg_lighter = { 0.176, 0.161, 0.137, 1.0 }
    local text_light = { 0.878, 0.855, 0.812, 1.0 }
    local border_dark = { 0.3, 0.275, 0.235, 1.0 }

    imgui.PushStyleColor(ImGuiCol_WindowBg, bg_dark)
    imgui.PushStyleColor(ImGuiCol_ChildBg, { 0, 0, 0, 0 })
    imgui.PushStyleColor(ImGuiCol_TitleBg, bg_medium)
    imgui.PushStyleColor(ImGuiCol_TitleBgActive, bg_light)
    imgui.PushStyleColor(ImGuiCol_TitleBgCollapsed, bg_dark)
    imgui.PushStyleColor(ImGuiCol_FrameBg, bg_medium)
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, bg_light)
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, bg_lighter)
    imgui.PushStyleColor(ImGuiCol_Header, bg_light)
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, bg_lighter)
    imgui.PushStyleColor(ImGuiCol_HeaderActive, { gold[1], gold[2], gold[3], 0.3 })
    imgui.PushStyleColor(ImGuiCol_Border, border_dark)
    imgui.PushStyleColor(ImGuiCol_Text, text_light)
    imgui.PushStyleColor(ImGuiCol_TextDisabled, gold_dark)
    imgui.PushStyleColor(ImGuiCol_Button, bg_medium)
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, bg_light)
    imgui.PushStyleColor(ImGuiCol_ButtonActive, bg_lighter)
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
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 6, 4 })
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 8, 6 })
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 4.0)
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6.0)
    imgui.PushStyleVar(ImGuiStyleVar_ChildRounding, 4.0)
    imgui.PushStyleVar(ImGuiStyleVar_PopupRounding, 4.0)
    imgui.PushStyleVar(ImGuiStyleVar_ScrollbarRounding, 4.0)
    imgui.PushStyleVar(ImGuiStyleVar_GrabRounding, 4.0)
end

local function pop_xiui_config_theme()
    imgui.PopStyleVar(9)
    imgui.PopStyleColor(34)
end

local function build_config_sections(context)
    local sections = {
        { key = 'global', label = 'Global' },
    }

    local default_tabs = (context.config and context.config.default_tabs) or {}
    local combat_tab = context.combat_tab
    for _, tab in ipairs(default_tabs) do
        local canonical = context.normalize_name(tab.canonical or '')
        if canonical ~= '' and canonical ~= combat_tab then
            table.insert(sections, {
                key = canonical,
                label = tostring(tab.display or tab.canonical or canonical),
            })
        end
    end

    table.insert(sections, { key = 'tells', label = 'Tells' })
    table.insert(sections, { key = 'combat log', label = 'Combat Log' })

    return sections
end

local function color_row(label, theme_overrides, key, base_default, cflags, cfg, context)
    local src = theme_overrides[key] or base_default or { 0, 0, 0, 1 }
    local c = T{ src[1] or 0, src[2] or 0, src[3] or 0, (src[4] ~= nil) and src[4] or 1.0 }
    if imgui.ColorEdit4(label .. '##wtheme_' .. key, c, cflags) then
        cfg.theme = cfg.theme or {}
        cfg.theme[key] = { c[1], c[2], c[3], c[4] }
        context.settings.save()
    end
end

local function shape_slider(label, theme_overrides, key, base_default, min_v, max_v, cfg, context)
    local val = T{ tonumber(theme_overrides[key] or base_default) or 0 }
    imgui.SetNextItemWidth(200)
    if imgui.SliderFloat('##wshape_' .. key, val, min_v, max_v) then
        cfg.theme = cfg.theme or {}
        cfg.theme[key] = val[1]
        context.settings.save()
    end
    imgui.SameLine()
    imgui.Text(label)
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
    local combat_tab = context.combat_tab
    for _, tab in ipairs(default_tabs) do
        local canonical = context.normalize_name(tab.canonical or '')
        if canonical == section_key and canonical ~= combat_tab then
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
    if section_key == context.yells_tab then
        return {
            { key = 'yells', label = 'Yell' },
            { key = 'shout', label = 'Shout' },
            { key = 'emote', label = 'Emote' },
        }
    end
    if section_key == context.crafting_helm_tab then
        return {
            { key = 'crafting_helm', label = 'Crafting / HELM' },
            { key = 'crafting_helm_loss', label = 'Crafting Break / Loss' },
        }
    end
    if section_key == context.server_tab then
        return {
            { key = 'server', label = 'Server Text' },
        }
    end
    if section_key == context.combat_tab then
        return {
            { key = 'combat', label = 'White Damage' },
            { key = 'combat_loot_gain', label = 'Combat Loot / Exp Gain' },
            { key = 'combat_player_item', label = 'Item Used' },
            { key = 'combat_player_action', label = 'Player Spell or Abilities' },
            { key = 'combat_enemy_action', label = 'Enemy Spell or Abilities' },
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
                imgui.Spacing()
                if imgui.CollapsingHeader('Theme##global_theme', 0) then
                    local th = cfg.theme or {}
                    local base_style = (context.config and context.config.style) or {}
                    local base_theme = base_style.theme or {}
                    local cflags = bit.bor(ImGuiColorEditFlags_AlphaBar, ImGuiColorEditFlags_NoInputs)
                    imgui.PushStyleColor(ImGuiCol_Button,        { 0.5, 0.2, 0.2, 1.0 })
                    imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.7, 0.3, 0.3, 1.0 })
                    imgui.PushStyleColor(ImGuiCol_ButtonActive,  { 0.8, 0.2, 0.2, 1.0 })
                    if imgui.Button('Reset Theme to Default') then
                        cfg.theme = T{}
                        context.settings.save()
                    end
                    imgui.PopStyleColor(3)
                    imgui.Spacing()
                    if imgui.CollapsingHeader('Window##theme_win', default_open) then
                        imgui.Spacing()
                        color_row('Window Background',  th, 'window_bg',          base_theme.window_bg          or {0.07, 0.07, 0.11, 0.00}, cflags, cfg, context)
                        color_row('Border',             th, 'border',             base_theme.border             or {0.30, 0.32, 0.52, 0.00}, cflags, cfg, context)
                        shape_slider('Window Rounding',    th, 'window_rounding',    base_style.window_rounding    or 10.0, 0.0, 20.0, cfg, context)
                        shape_slider('Window Border Size', th, 'window_border_size', base_style.window_border_size or  1.0, 0.0,  4.0, cfg, context)
                        imgui.Spacing()
                    end
                    if imgui.CollapsingHeader('Tab Bar##theme_tabs', 0) then
                        imgui.Spacing()
                        color_row('Tab',         th, 'tab',        base_theme.tab        or {0.07, 0.08, 0.15, 0.90}, cflags, cfg, context)
                        color_row('Tab Hovered', th, 'tab_hovered', base_theme.tab_hovered or {0.18, 0.20, 0.36, 1.00}, cflags, cfg, context)
                        color_row('Tab Active',  th, 'tab_active',  base_theme.tab_active  or {0.22, 0.26, 0.46, 1.00}, cflags, cfg, context)
                        shape_slider('Tab Rounding', th, 'tab_rounding', base_style.tab_rounding or 6.0, 0.0, 12.0, cfg, context)
                        imgui.Spacing()
                    end
                    if imgui.CollapsingHeader('Chat Area##theme_chat', 0) then
                        imgui.Spacing()
                        color_row('Background',              th, 'child_bg',          base_theme.child_bg          or {0.04, 0.04, 0.08, 0.70}, cflags, cfg, context)
                        color_row('Separator',               th, 'separator',          base_theme.separator          or {0.24, 0.26, 0.42, 0.70}, cflags, cfg, context)
                        color_row('Scrollbar',               th, 'scrollbar_bg',       base_theme.scrollbar_bg       or {0.02, 0.02, 0.05, 0.40}, cflags, cfg, context)
                        color_row('Scrollbar Grab',          th, 'scrollbar_grab',     base_theme.scrollbar_grab     or {0.20, 0.22, 0.38, 0.70}, cflags, cfg, context)
                        color_row('Scrollbar Grab Hovered',  th, 'scrollbar_grab_hov', base_theme.scrollbar_grab_hov or {0.28, 0.30, 0.50, 0.90}, cflags, cfg, context)
                        shape_slider('Scrollbar Rounding', th, 'scrollbar_rounding', base_style.scrollbar_rounding or 4.0, 0.0, 12.0, cfg, context)
                        shape_slider('Scrollbar Size',     th, 'scrollbar_size',     base_style.scrollbar_size     or 8.0, 1.0, 20.0, cfg, context)
                        imgui.Spacing()
                    end
                    if imgui.CollapsingHeader('Input & Buttons##theme_inputbtn', 0) then
                        imgui.Spacing()
                        color_row('Input Background',         th, 'frame_bg',          base_theme.frame_bg          or {0.09, 0.09, 0.17, 0.80}, cflags, cfg, context)
                        color_row('Input Background Hovered', th, 'frame_bg_hovered',  base_theme.frame_bg_hovered  or {0.13, 0.14, 0.24, 0.90}, cflags, cfg, context)
                        color_row('Input Background Active',  th, 'frame_bg_active',   base_theme.frame_bg_active   or {0.17, 0.18, 0.30, 1.00}, cflags, cfg, context)
                        shape_slider('Frame Rounding',    th, 'frame_rounding',    base_style.frame_rounding    or 5.0, 0.0, 12.0, cfg, context)
                        shape_slider('Frame Border Size', th, 'frame_border_size', base_style.frame_border_size or 0.0, 0.0,  4.0, cfg, context)
                        imgui.Spacing()
                        color_row('Button',         th, 'button',         base_theme.button         or {0.11, 0.12, 0.22, 1.00}, cflags, cfg, context)
                        color_row('Button Hovered', th, 'button_hovered', base_theme.button_hovered or {0.20, 0.22, 0.38, 1.00}, cflags, cfg, context)
                        color_row('Button Active',  th, 'button_active',  base_theme.button_active  or {0.28, 0.32, 0.52, 1.00}, cflags, cfg, context)
                        imgui.Spacing()
                    end
                end
                imgui.PopStyleColor(2)
                imgui.Spacing()
                if imgui.CollapsingHeader('Window Backgrounds##global_bg', 0) then
                    local bg_themes = { '-None-', 'Plain', 'Window1', 'Window2', 'Window3', 'Window4', 'Window5', 'Window6', 'Window7', 'Window8' }

                    imgui.Spacing()
                    imgui.Text('Main Window')
                    local cur_main = tostring(cfg.window_bg_theme or '-None-')
                    imgui.SetNextItemWidth(200)
                    if imgui.BeginCombo('##main_bg_theme', cur_main) then
                        for _, v in ipairs(bg_themes) do
                            local selected = (cur_main == v)
                            if imgui.Selectable(v, selected) then
                                cfg.window_bg_theme = v
                                context.settings.save()
                            end
                            if selected then imgui.SetItemDefaultFocus() end
                        end
                        imgui.EndCombo()
                    end
                    imgui.SameLine()
                    imgui.Text('Theme')
                    local main_op = T{ tonumber(cfg.window_bg_opacity) or 1.0 }
                    imgui.SetNextItemWidth(200)
                    if imgui.SliderFloat('##main_bg_opacity', main_op, 0.0, 1.0) then
                        cfg.window_bg_opacity = main_op[1]
                        context.settings.save()
                    end
                    imgui.SameLine()
                    imgui.Text('Opacity')

                    imgui.Spacing()
                    imgui.Text('Combat Log')
                    local cur_combat = tostring(cfg.combat_bg_theme or '-None-')
                    imgui.SetNextItemWidth(200)
                    if imgui.BeginCombo('##combat_bg_theme', cur_combat) then
                        for _, v in ipairs(bg_themes) do
                            local selected = (cur_combat == v)
                            if imgui.Selectable(v, selected) then
                                cfg.combat_bg_theme = v
                                context.settings.save()
                            end
                            if selected then imgui.SetItemDefaultFocus() end
                        end
                        imgui.EndCombo()
                    end
                    imgui.SameLine()
                    imgui.Text('Theme')
                    local combat_op = T{ tonumber(cfg.combat_bg_opacity) or 1.0 }
                    imgui.SetNextItemWidth(200)
                    if imgui.SliderFloat('##combat_bg_opacity', combat_op, 0.0, 1.0) then
                        cfg.combat_bg_opacity = combat_op[1]
                        context.settings.save()
                    end
                    imgui.SameLine()
                    imgui.Text('Opacity')
                    imgui.Spacing()
                end
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
                if state.config_selected_section == context.combat_tab then
                    imgui.Spacing()
                    local base_behavior = (context.config and context.config.behavior) or {}
                    local storage_defaults = (context.get_storage_defaults and context.get_storage_defaults()) or {}
                    local default_ttl_secs = tonumber(storage_defaults.ttl_seconds or base_behavior.message_ttl_seconds) or 86400
                    local default_max_lines = tonumber(storage_defaults.max_messages_per_tab or base_behavior.max_messages_per_tab) or 300
                    local default_open = tonumber(ImGuiTreeNodeFlags_DefaultOpen) or 32

                    imgui.PushStyleColor(ImGuiCol_Header,        { gold[1], gold[2], gold[3], 0.15 })
                    imgui.PushStyleColor(ImGuiCol_HeaderHovered, { gold[1], gold[2], gold[3], 0.25 })

                    if imgui.CollapsingHeader('Logging##combat_logging', default_open) then
                        imgui.Spacing()
                        imgui.Text('Combat Log File (combat_messages.dat)')

                        local combat_ttl_hours = T{ math.max(1, math.floor(((tonumber(cfg.combat_ttl_seconds) or default_ttl_secs) + 1800) / 3600)) }
                        imgui.SetNextItemWidth(200)
                        if imgui.SliderInt('##combat_ttl_hours_section', combat_ttl_hours, 1, 720) then
                            cfg.combat_ttl_seconds = math.max(60, math.floor(combat_ttl_hours[1] * 3600))
                            if context.apply_storage_constraints then context.apply_storage_constraints(false) end
                            context.settings.save()
                        end
                        imgui.SameLine()
                        imgui.Text('TTL (hours)')

                        local combat_max_lines = T{ math.max(1, math.floor(tonumber(cfg.combat_max_messages_per_tab) or default_max_lines)) }
                        imgui.SetNextItemWidth(200)
                        if imgui.SliderInt('##combat_max_lines_section', combat_max_lines, 1, 5000) then
                            cfg.combat_max_messages_per_tab = math.max(1, math.floor(combat_max_lines[1]))
                            if context.apply_storage_constraints then context.apply_storage_constraints(false) end
                            context.settings.save()
                        end
                        imgui.SameLine()
                        imgui.Text('Max lines kept in combat log window')
                        imgui.Spacing()
                    end

                    if imgui.CollapsingHeader('Filters##combat_filters', default_open) then
                        imgui.Spacing()
                        local base_filters = (context.config and context.config.combat_filters) or {}
                        local disabled_filters = cfg.combat_filter_disabled or {}
                        local legacy_filters = cfg.combat_filters or {}
                        local filter_kinds = {
                            { key = 'general',       label = 'General Combat Text' },
                            { key = 'loot_gain',     label = 'Loot Finds / EXP Gains' },
                            { key = 'player_item',   label = 'Player Item Use' },
                            { key = 'player_action', label = 'Player Spells & Abilities' },
                            { key = 'enemy_action',  label = 'Enemy Spells & Abilities' },
                        }
                        for _, entry in ipairs(filter_kinds) do
                            local key = entry.key
                            local is_enabled
                            if disabled_filters[key] == true then
                                is_enabled = false
                            elseif legacy_filters[key] ~= nil then
                                is_enabled = (legacy_filters[key] ~= false)
                            else
                                is_enabled = (base_filters[key] ~= false)
                            end

                            local checkbox_val = T{ is_enabled }
                            if imgui.Checkbox(entry.label .. '##combat_filter_' .. entry.key, checkbox_val) then
                                local enabled_now = (checkbox_val[1] == true)
                                cfg.combat_filter_disabled = cfg.combat_filter_disabled or T{}
                                cfg.combat_filters = cfg.combat_filters or T{}
                                if enabled_now then
                                    cfg.combat_filter_disabled[key] = nil
                                    cfg.combat_filters[key] = true
                                else
                                    cfg.combat_filter_disabled[key] = true
                                    cfg.combat_filters[key] = false
                                end
                                context.settings.save()
                            end
                        end
                        imgui.Spacing()
                    end

                    imgui.PopStyleColor(2)
                    imgui.Spacing()
                elseif blink_key == nil then
                    imgui.Text(selected_label .. ' settings coming soon.')
                end
            end
        else
            if state.config_selected_section == 'global' then
                imgui.Text('Select a tab on the left to edit its colors.')
            elseif state.config_selected_section == context.all_tab then
                imgui.Spacing()
                imgui.TextWrapped('The colors of the text in this tab comes from the color picked in the other tabs.')
                imgui.Spacing()
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

local function is_actor_friendly(actor_normalized, local_player_canonical, party_member_canonicals, visible_player_canonicals)
    if actor_normalized == 'you' or actor_normalized == local_player_canonical then
        return true
    end

    return (party_member_canonicals and party_member_canonicals[actor_normalized] == true)
        or (visible_player_canonicals and visible_player_canonicals[actor_normalized] == true)
end

local function trim_text(text_value)
    return tostring(text_value or ''):match('^%s*(.-)%s*$')
end

local function strip_leading_embedded_timestamp(text_value)
    local text = tostring(text_value or '')
    -- Some combat lines arrive with their own [HH:MM:SS] prefix; strip it so UI timestamp stays consistent.
    return text:gsub('^%s*[%[%{<]?%d%d:%d%d:?%d?%d?[%]%}>]?%s*', '', 1)
end

local function extract_combat_actor_name(text_value)
    local text = trim_text(text_value)
    if text == '' then
        return nil
    end

    local actor = text:match('^(.-)%s+starts casting%f[%A]')
        or text:match('^(.-)%s+begins casting%f[%A]')
        or text:match('^(.-)%s+casts%f[%A]')
        or text:match('^(.-)%s+readies%f[%A]')
        or text:match('^(.-)%s+uses%f[%A]')

    if actor == nil then
        actor = text:match('^([^%s]+)')
    end

    actor = trim_text(actor)
    if actor == '' then
        return nil
    end

    return actor
end

local function is_player_like_actor_name(actor_name)
    local actor = trim_text(actor_name)
    if actor == '' then
        return false
    end

    return actor:match('^[A-Z][A-Za-z]+$') ~= nil
end

local function is_crafting_loss_or_break_line(text_value)
    local text = trim_text(text_value):lower()
    if text == '' then
        return false
    end

    return text:match(' lost an? .+$') ~= nil
        or text:match('^%-+%s*break%s*%(.+%).+$') ~= nil
        or text:match(' our pickaxe breaks%.?$') ~= nil
        or text:match(' our hatchet breaks%.?$') ~= nil
        or text:match(' our sickle breaks%.?$') ~= nil
end

local function is_trade_notice_line(text_value)
    local text = trim_text(text_value):lower()
    if text == '' then
        return false
    end

    return text:match('^.+ wishes to trade with you%.?$') ~= nil
end

local function is_combat_loot_or_gain_line(text_value)
    local text = trim_text(text_value):lower()
    if text == '' then
        return false
    end

    return text:match('^you find .+ on the .+%.$') ~= nil
        or text:match('^you find .+ on .+%.$') ~= nil
        or text:match('^you find nothing on the .+%.$') ~= nil
        or text:match('^you find nothing on .+%.$') ~= nil
        or text:match('^you take .+ out of delivery slot %d+%.?$') ~= nil
        or text:match('^you do not meet the requirements to obtain .+%.$') ~= nil
        or text:match('^.+ abjuration lost%.?$') ~= nil
        or text:match('^.+ lot for .+: [%d,]+ points%.?$') ~= nil
        or text:match('^you obtains? an? .+%.$') ~= nil
        or text:match('^.+ obtains? an? .+%.$') ~= nil
        or text:match('^you obtains? some .+%.$') ~= nil
        or text:match('^.+ obtains? some .+%.$') ~= nil
        or text:match('^the money the buyer paid for .+ you put on auction, [%d,]+ gil%.?$') ~= nil
        or text:match('^you obtains? [%d,]+ gil%s*%.?$') ~= nil
        or text:match('^.+ obtains? [%d,]+ gil%s*%.?$') ~= nil
        or text:match('^you gains? [%d,]+ experience points?%s*%.?$') ~= nil
        or text:match('^.+ gains? [%d,]+ experience points?%s*%.?$') ~= nil
        or text:match('^you gains? [%d,]+ limit points?%s*%.?$') ~= nil
        or text:match('^.+ gains? [%d,]+ limit points?%s*%.?$') ~= nil
        or text:match('^you gains? [%d,]+ capacity points?%s*%.?$') ~= nil
        or text:match('^.+ gains? [%d,]+ capacity points?%s*%.?$') ~= nil
end

local function get_combat_message_kind(msg, local_player_canonical, normalize_name, party_member_canonicals, visible_player_canonicals, hostile_actor_canonicals)
    local rc = msg._rc
    local is_loot, actor, actor_n, is_action, is_item
    if rc ~= nil and rc.pc == local_player_canonical then
        is_loot   = rc.is_loot_or_gain
        actor     = rc.actor
        actor_n   = rc.actor_n
        is_action = rc.is_action
        is_item   = rc.is_item
    else
        local display_text = strip_leading_embedded_timestamp(tostring(msg.text or ''))
        is_loot = is_combat_loot_or_gain_line(display_text)
        if not is_loot then
            local tl = display_text:lower()
            is_action = tl:find('starts casting') or tl:find('begins casting') or
                        tl:find('casts') or tl:find('readies') or tl:find('uses')
            if is_action then
                is_item = tl:find('uses a ') or tl:find('uses an ')
                actor   = extract_combat_actor_name(display_text)
                actor_n = actor and normalize_name(actor) or ''
            end
        end
    end
    if is_loot then return 'loot_gain' end
    if is_action and actor then
        local is_player_action = is_actor_friendly(actor_n, local_player_canonical, party_member_canonicals, visible_player_canonicals)
        local is_known_non_player = (hostile_actor_canonicals and hostile_actor_canonicals[actor_n] == true)
        local is_likely_player = is_player_like_actor_name(actor)
        if is_player_action or (not is_known_non_player and is_likely_player) then
            return is_item and 'player_item' or 'player_action'
        else
            return 'enemy_action'
        end
    end
    return 'general'
end

local function apply_all_tab_input_shortcuts(context, name, input_before)
    if name ~= context.all_tab or not imgui.IsItemActive() then
        context.state.all_tab_shortcut_keys = {}
        return
    end

    local ctrl_down = is_vkey_down(VK_CONTROL)
    if not ctrl_down then
        context.state.all_tab_shortcut_keys = {}
        return
    end

    local shortcut_keys = context.state.all_tab_shortcut_keys or {}
    local applied_command = nil
    for vkey, command in pairs(all_tab_shortcut_commands) do
        local is_down = is_vkey_down(vkey)
        local was_down = shortcut_keys[vkey] == true
        if is_down and not was_down then
            applied_command = command
        end
        shortcut_keys[vkey] = is_down
    end
    context.state.all_tab_shortcut_keys = shortcut_keys

    if applied_command ~= nil then
        context.state.all_tab_pending_command = applied_command
        context.state.all_tab_pending_base_text = input_before
    end
end

local function apply_all_tab_escape_clear(context, name)
    if name ~= context.all_tab then
        context.state.all_tab_escape_was_down = false
        return
    end

    local esc_down = is_vkey_down(VK_ESCAPE)
    local was_down = context.state.all_tab_escape_was_down == true
    context.state.all_tab_escape_was_down = esc_down

    if esc_down and not was_down then
        context.state.all_tab_active_command = nil
        context.state.input_text[1] = ''
    end
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

local function render_message(context, name, display, message, local_player_canonical, party_member_canonicals, visible_player_canonicals, hostile_actor_canonicals, is_fixed_channel, is_linkshell, is_linkshell1, is_linkshell2, is_say, is_combat, is_crafting_helm, is_yells, is_server)
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
        if is_combat then
            display_text = strip_leading_embedded_timestamp(raw_text)
        end

        local sender_for_fmt = message.sender
        if sender_for_fmt ~= nil and is_fixed_channel and not is_combat then
            local sender_c = normalize_name(sender_for_fmt)
            local display_c = normalize_name(display)
            if sender_c == '' or sender_c == name or sender_c == display_c then
                sender_for_fmt = nil
            end
        end
        if is_combat then sender_for_fmt = nil end

        local lt, prefix_len = context.format_message_line(
            os.date(context.msg_cfg.timestamp_format, message.time),
            sender_for_fmt,
            display_text,
            local_player_canonical,
            is_fixed_channel)
        rc.lt = lt
        rc.lb = context.map_line_brace_indices(prefix_len, message.auto_translate_braces)

        if is_combat then
            rc.display_text = display_text
            local actor = extract_combat_actor_name(display_text)
            rc.actor = actor
            rc.actor_n = actor and normalize_name(actor) or ''
            local tl = display_text:lower()
            rc.is_loot_or_gain = is_combat_loot_or_gain_line(display_text)
            rc.is_action = tl:find('starts casting') or tl:find('begins casting') or
                           tl:find('casts') or tl:find('readies') or tl:find('uses')
            rc.is_item   = tl:find('uses a ') or tl:find('uses an ')
        end

        if is_crafting_helm then
            rc.is_loss = is_crafting_loss_or_break_line(raw_text)
        end

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
    elseif is_yells then
        local yells_color = color_cfg.yells or color_cfg.tell
        if message.chat_mode == 15 then
            yells_color = color_cfg.emote or color_cfg.tell
        elseif message.chat_mode == 10 then
            yells_color = color_cfg.shout or color_cfg.yells or color_cfg.tell
        end
        imgui.PushStyleColor(ImGuiCol_Text, yells_color)
        context.text_wrapped_bold_with_translate_braces(line_text, line_braces)
        imgui.PopStyleColor()
    elseif is_say then
        local say_color = color_cfg.say or { 1.0, 1.0, 1.0, 1.0 }
        imgui.PushStyleColor(ImGuiCol_Text, say_color)
        context.text_wrapped_bold_with_translate_braces(line_text, line_braces)
        imgui.PopStyleColor()
    elseif is_combat then
        local combat_color = color_cfg.combat or color_cfg.tell
        local actor_name = rc.actor
        local actor_normalized = rc.actor_n
        local is_player_action = is_actor_friendly(actor_normalized, local_player_canonical, party_member_canonicals, visible_player_canonicals)
        local is_known_non_player = (hostile_actor_canonicals and hostile_actor_canonicals[actor_normalized] == true)
        local is_likely_player = is_player_like_actor_name(actor_name)
        if rc.is_loot_or_gain then
            combat_color = color_cfg.combat_loot_gain or { 0.4, 1.0, 0.4, 1.0 }
        elseif rc.is_action and actor_name then
            if is_player_action or (not is_known_non_player and is_likely_player) then
                if rc.is_item then
                    combat_color = color_cfg.combat_player_item or { 0.4, 1.0, 0.4, 1.0 }
                else
                    combat_color = color_cfg.combat_player_action or { 1.0, 1.0, 0.4, 1.0 }
                end
            else
                combat_color = color_cfg.combat_enemy_action or { 1.0, 0.4, 0.4, 1.0 }
            end
        end
        imgui.PushStyleColor(ImGuiCol_Text, combat_color)
        context.text_wrapped_bold_with_translate_braces(line_text, line_braces)
        imgui.PopStyleColor()
    elseif is_crafting_helm then
        local crafting_color = color_cfg.crafting_helm or color_cfg.server or color_cfg.say or color_cfg.tell
        if rc.is_loss then
            crafting_color = color_cfg.crafting_helm_loss or color_cfg.yells or crafting_color
        end
        imgui.PushStyleColor(ImGuiCol_Text, crafting_color)
        context.text_wrapped_bold_with_translate_braces(line_text, line_braces)
        imgui.PopStyleColor()
    elseif is_server then
        local server_color = color_cfg.server or color_cfg.say or color_cfg.tell
        imgui.PushStyleColor(ImGuiCol_Text, server_color)
        context.text_wrapped_bold_with_translate_braces(line_text, line_braces)
        imgui.PopStyleColor()
    else
        local line_color
        if name == 'party' then
            line_color = color_cfg.party or color_cfg.tell
        elseif name == 'all' then
            if is_trade_notice_line(message.text or '') then
                line_color = color_cfg.all or color_cfg.say or { 1.0, 1.0, 1.0, 1.0 }
            else
            local source_tab = normalize_name(message.source_tab or '')
            if source_tab == '' then
                local mode_num = tonumber(message.chat_mode)
                local mode_info = (mode_num and context.config and context.config.chat_mode_tabs and context.config.chat_mode_tabs[mode_num]) or nil
                if mode_info and mode_info.tab then
                    source_tab = normalize_name(mode_info.tab)
                end
            end

            if source_tab == context.linkshell1_tab then
                line_color = color_cfg.linkshell1 or color_cfg.tell
            elseif source_tab == context.linkshell2_tab then
                line_color = color_cfg.linkshell2 or color_cfg.tell
            elseif source_tab == context.party_tab then
                line_color = color_cfg.party or color_cfg.tell
            elseif source_tab == context.say_tab then
                line_color = color_cfg.say or color_cfg.tell
            elseif source_tab == context.yells_tab then
                local yells_color = color_cfg.yells or color_cfg.tell
                if message.chat_mode == 15 then
                    yells_color = color_cfg.emote or color_cfg.tell
                elseif message.chat_mode == 10 then
                    yells_color = color_cfg.shout or color_cfg.yells or color_cfg.tell
                end
                line_color = yells_color
            elseif source_tab == context.crafting_helm_tab then
                line_color = color_cfg.crafting_helm or color_cfg.server or color_cfg.say or color_cfg.tell
            elseif source_tab == context.server_tab then
                line_color = color_cfg.server or color_cfg.say or color_cfg.tell
            else
                line_color = color_cfg.tell
            end
            end
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
    if not state.is_open[1] and not state.combat_is_open[1] and not show_config_window then
        return
    end

    local cfg = context.get_cfg()
    local tells = context.get_tells()
    local display_names = context.get_display_names()
    local unread = context.get_unread()
    local last_msg_count = context.get_last_msg_count()
    local combat_last_msg_count = (context.get_combat_last_msg_count and context.get_combat_last_msg_count()) or 0
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
    if state.selected ~= context.all_tab then
        state.all_tab_input_active = false
    end

    cfg.window = cfg.window or {
        x = config.default_window.x,
        y = config.default_window.y,
        width = config.default_window.width,
        height = config.default_window.height,
    }

    cfg.combat_window = cfg.combat_window or {
        x = config.default_combat_window.x,
        y = config.default_combat_window.y,
        width = config.default_combat_window.width,
        height = config.default_combat_window.height,
    }

    local local_player_canonical = context.normalize_name(context.get_local_player_name() or '')
    local party_member_canonicals = context.get_party_member_canonicals and context.get_party_member_canonicals() or {}
    local visible_player_canonicals = context.get_visible_player_canonicals and context.get_visible_player_canonicals() or {}
    local visible_non_player_canonicals = context.get_visible_non_player_canonicals and context.get_visible_non_player_canonicals() or {}

    local style = resolve_effective_style(config, cfg, show_config_window)
    local effective_color_cfg = resolve_effective_colors(context.color_cfg, cfg, show_config_window)
    context.effective_color_cfg = effective_color_cfg
    local style_var_count, style_color_count = decoration.push(style)
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
            -- Update window background primitive
            local main_theme = tostring(cfg.window_bg_theme or '-None-')
            if not _bg.main then
                _bg.main = windowBg.create(main_theme)
                _bg.main_theme = main_theme
            elseif _bg.main_theme ~= main_theme then
                windowBg.setTheme(_bg.main, main_theme)
                _bg.main_theme = main_theme
            end
            local _wx, _wy = imgui.GetWindowPos()
            local _ww, _wh = imgui.GetWindowSize()
            windowBg.update(_bg.main, _wx, _wy, _ww, _wh, {
                theme     = main_theme,
                bgOpacity = tonumber(cfg.window_bg_opacity) or 1.0,
            })

            imgui.SetWindowFontScale(font_scale)

            if next(tells) == nil then
                imgui.Text(context.msg_cfg.no_recent_tells)
            else
                if imgui.BeginTabBar('##WhispersTabBar', decoration.tab_bar_flags(style)) then
                    local names = build_main_tab_names(config.default_tabs, player_order, context.normalize_name, context.combat_tab)
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
                            local is_combat = (name == context.combat_tab)
                            local is_crafting_helm = (name == context.crafting_helm_tab)
                            local is_yells = (name == context.yells_tab)
                            local is_server = (name == context.server_tab)
                            local is_read_only = context.is_read_only_tab(name)
                            local _, avail_height = imgui.GetContentRegionAvail()
                            local line_height = imgui.GetTextLineHeight()
                            local controls_reserved_height = line_height + read_only_footer_padding
                            controls_reserved_height = controls_reserved_height + line_height + input_row_padding
                            local chat_height = math.max(min_chat_height, (avail_height or 0) - controls_reserved_height)

                            imgui.BeginChild('##chat_' .. name, { 0, chat_height }, false)
                            imgui.SetWindowFontScale(message_font_scale)
                            for i = 1, #msgs do
                                render_message(context, name, display, msgs[i], local_player_canonical, party_member_canonicals, visible_player_canonicals, visible_non_player_canonicals, is_fixed_channel, is_linkshell, is_linkshell1, is_linkshell2, is_say, is_combat, is_crafting_helm, is_yells, is_server)
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
                            imgui.EndChild()

                            imgui.Separator()
                            if not is_read_only then
                                if name == context.all_tab and state.all_tab_pending_command ~= nil then
                                    state.all_tab_active_command = state.all_tab_pending_command
                                    state.input_text[1] = state.all_tab_pending_base_text or (state.input_text[1] or '')
                                    state.all_tab_pending_command = nil
                                    state.all_tab_pending_base_text = nil
                                end
                                local input_before = state.input_text[1] or ''
                                local input_id = '##whispers_input_' .. name
                                if name == context.all_tab and state.all_tab_active_command ~= nil then
                                    local prefix_text = state.all_tab_active_command .. ' '
                                    local prefix_width = (imgui.CalcTextSize(prefix_text) or 0) + 18
                                    local prefix_buffer = T{ prefix_text }
                                    if imgui.SetNextItemWidth ~= nil then
                                        imgui.SetNextItemWidth(prefix_width)
                                    end
                                    imgui.InputText('##whispers_prefix_' .. name, prefix_buffer, 16, ImGuiInputTextFlags_ReadOnly)
                                    imgui.SameLine()
                                end
                                if state.focus_input_requested == name then
                                    imgui.SetKeyboardFocusHere()
                                    state.focus_input_requested = nil
                                end
                                local was_all_tab_input_active = state.all_tab_input_active == true
                                local enter_pressed = imgui.InputText(input_id, state.input_text, ui_cfg.input_max_length, ImGuiInputTextFlags_EnterReturnsTrue)
                                if name == context.all_tab and trim_text(state.input_text[1] or ''):match('^/') ~= nil then
                                    -- If the user starts typing an explicit slash command, stop forcing shortcut prefix mode.
                                    state.all_tab_active_command = nil
                                end
                                state.all_tab_input_active = (name == context.all_tab) and imgui.IsItemActive() or false
                                apply_all_tab_escape_clear(context, name)
                                apply_all_tab_input_shortcuts(context, name, input_before)
                                if enter_pressed then
                                    context.queue_tab_message(name, display, state.input_text[1] or '')
                                end

                                imgui.SameLine()
                                if imgui.Button('Send') then
                                    context.queue_tab_message(name, display, state.input_text[1] or '')
                                end

                                imgui.SameLine()
                            end

                            if imgui.Button('Clear') then
                                context.clear_tab(name)
                            end

                            imgui.SameLine()
                            local combat_toggle_label = state.combat_is_open[1] and 'Hide Combat Log' or 'Show Combat Log'
                            if imgui.Button(combat_toggle_label .. '##main_window_footer') then
                                state.combat_is_open[1] = not state.combat_is_open[1]
                            end

                            if is_read_only then
                                -- Keep footer height consistent so switching tabs does not visually resize content.
                                imgui.Dummy({ 0, line_height + input_row_padding })
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
            -- Second pass: sync primitive to the final post-drag bounds for this frame.
            windowBg.update(_bg.main, posX, posY, sizeX, sizeY, {
                theme     = main_theme,
                bgOpacity = tonumber(cfg.window_bg_opacity) or 1.0,
            })
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
    else
        if _bg.main then windowBg.hide(_bg.main) end
    end

    if state.combat_is_open[1] then
        imgui.SetNextWindowPos({ cfg.combat_window.x, cfg.combat_window.y }, ImGuiCond_FirstUseEver)
        imgui.SetNextWindowSize({ cfg.combat_window.width, cfg.combat_window.height }, ImGuiCond_FirstUseEver)

        if imgui.Begin('Whispers Combat Log', state.combat_is_open, window_flags) then
            -- Update combat log background primitive
            local combat_theme = tostring(cfg.combat_bg_theme or '-None-')
            if not _bg.combat then
                _bg.combat = windowBg.create(combat_theme)
                _bg.combat_theme = combat_theme
            elseif _bg.combat_theme ~= combat_theme then
                windowBg.setTheme(_bg.combat, combat_theme)
                _bg.combat_theme = combat_theme
            end
            local _cx, _cy = imgui.GetWindowPos()
            local _cw, _ch = imgui.GetWindowSize()
            windowBg.update(_bg.combat, _cx, _cy, _cw, _ch, {
                theme     = combat_theme,
                bgOpacity = tonumber(cfg.combat_bg_opacity) or 1.0,
            })

            imgui.SetWindowFontScale(font_scale)

            local combat_name = context.combat_tab
            local combat_display = display_names[combat_name] or 'Combat Log'
            local combat_msgs = tells[combat_name] or {}

            -- Header row: title left, Clear button right-aligned
            imgui.Text('Combat Log')
            imgui.SameLine()
            local avail_w = imgui.GetContentRegionAvail()
            local btn_w = imgui.CalcTextSize('Clear') + 16
            imgui.SetCursorPosX(imgui.GetCursorPosX() + avail_w - btn_w)
            if imgui.Button('Clear##combat_window_hdr') then
                context.clear_tab(combat_name)
                combat_last_message_key = nil
                if context.set_combat_last_msg_count then
                    context.set_combat_last_msg_count(0)
                end
            end
            imgui.Separator()

            local _, avail_height = imgui.GetContentRegionAvail()
            local line_height = imgui.GetTextLineHeight()
            local chat_height = math.max(min_chat_height, (avail_height or 0))

            imgui.BeginChild('##combat_window_chat', { 0, chat_height }, false)
            imgui.SetWindowFontScale(message_font_scale)
            local combat_filter_disabled = cfg.combat_filter_disabled or {}
            local combat_filter_overrides = cfg.combat_filters or {}
            local combat_filter_base = (context.config and context.config.combat_filters) or {}
            for i = 1, #combat_msgs do
                local msg = combat_msgs[i]
                local kind = get_combat_message_kind(msg, local_player_canonical, context.normalize_name, party_member_canonicals, visible_player_canonicals, visible_non_player_canonicals)
                local filter_enabled
                if combat_filter_disabled[kind] == true then
                    filter_enabled = false
                elseif combat_filter_overrides[kind] ~= nil then
                    filter_enabled = (combat_filter_overrides[kind] ~= false)
                else
                    filter_enabled = (combat_filter_base[kind] ~= false)
                end
                if filter_enabled then
                    render_message(context, combat_name, combat_display, msg, local_player_canonical, party_member_canonicals, visible_player_canonicals, visible_non_player_canonicals, true, false, false, false, false, true, false, false, false)
                end
            end
            local combat_latest_key = build_message_key(combat_msgs[#combat_msgs])
            local combat_has_new_message = (#combat_msgs > combat_last_msg_count)
                or (combat_latest_key ~= nil and combat_latest_key ~= combat_last_message_key)
            if combat_has_new_message then
                imgui.SetScrollHereY(ui_cfg.scroll_to_bottom_fraction or 1.0)
            end
            combat_last_message_key = combat_latest_key
            if context.set_combat_last_msg_count then
                context.set_combat_last_msg_count(#combat_msgs)
            end
            imgui.EndChild()

            local posX, posY = imgui.GetWindowPos()
            local sizeX, sizeY = imgui.GetWindowSize()
            -- Second pass: sync primitive to the final post-drag bounds for this frame.
            windowBg.update(_bg.combat, posX, posY, sizeX, sizeY, {
                theme     = combat_theme,
                bgOpacity = tonumber(cfg.combat_bg_opacity) or 1.0,
            })
            local changed = false
            if posX ~= cfg.combat_window.x then cfg.combat_window.x = posX; changed = true end
            if posY ~= cfg.combat_window.y then cfg.combat_window.y = posY; changed = true end
            if sizeX ~= cfg.combat_window.width then cfg.combat_window.width = sizeX; changed = true end
            if sizeY ~= cfg.combat_window.height then cfg.combat_window.height = sizeY; changed = true end
            if changed then
                context.settings.save()
            end

            imgui.End()
        end
    else
        if _bg.combat then windowBg.hide(_bg.combat) end
    end

    decoration.pop(style_var_count, style_color_count)
    render_config_window(context)
end

function ui.destroy_backgrounds()
    if _bg.main then
        windowBg.destroy(_bg.main)
        _bg.main = nil
        _bg.main_theme = nil
    end
    if _bg.combat then
        windowBg.destroy(_bg.combat)
        _bg.combat = nil
        _bg.combat_theme = nil
    end
end

return ui