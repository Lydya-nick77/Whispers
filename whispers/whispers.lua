--[[
* MIT License
*
* Copyright (c) 2023 lydya [github.com/lydya]
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
]]--

-- Whispers - is a simple chat replacement addon with tabs.
-- This addon captures incoming tells and certain chat messages, organizes whispers into tabs by sender, and provides a quick reply interface. 
-- The main file (whispers.lua) handles addon setup, message routing, and event wiring.
-- The ui module (ui.lua) renders the window, while decoration.lua provides ImGui styling.
-- The config module (config.lua) defines default settings and constants.
-- It also allows to copy and paste messages in chat.

addon.name    = 'Whispers'
addon.author  = 'Lydya'
addon.version = '1.8.0'
addon.desc    = 'Addon to replace the chat log with tabs and combat log window.'

require('common')
local imgui = require('imgui')
local bit = require('bit')
local settings    = require('settings')
local config      = require('config')
local storage     = require('storage')
local text_lib    = require('text')
local tabs        = require('tabs')
local parser      = require('parser')
local outgoing    = require('outgoing')
local outgoing_commands = require('outgoing_commands')
local presence    = require('presence')
local ui          = require('ui')

local ui_cfg = config.ui
local msg_cfg = config.messages
local parser_cfg = config.parser
local combat_cfg = config.combat or {}
local crafting_cfg = config.crafting_helm or {}
local behavior_cfg = config.behavior
local unread_cfg = config.unread
local command_cfg = config.commands
local color_cfg = config.colors
local tab_cfg = config.tabs or {}
local packet_cfg = config.packets or {}
local trim = text_lib.trim
local normalize_name = text_lib.normalize_name
local normalize_chat_text = text_lib.normalize_chat_text
local find_autotranslate_brace_indices = text_lib.find_autotranslate_brace_indices
local map_line_brace_indices = text_lib.map_line_brace_indices
local format_message_line = text_lib.format_message_line
local renderer = text_lib.create_renderer(imgui, ui_cfg, color_cfg)
local text_wrapped_bold_with_translate_braces = renderer.text_wrapped_bold_with_translate_braces

local state = {
    is_open = T{ true },
    combat_is_open = T{ true },
    config_is_open = T{ false },
    config_selected_section = 'global',
    config_selected_mode = 'settings',
    selected = nil,
    input_text = T{ '' },
    all_tab_input_active = false,
    all_tab_active_command = nil,
    all_tab_escape_was_down = false,
    all_tab_pending_command = nil,
    all_tab_pending_base_text = nil,
    all_tab_shortcut_keys = {},
}

-- Default settings (see config.lua)
local default_settings = T{
    window = T(config.default_window),
    combat_window = T(config.default_combat_window),
    font_scale = config.font_scale,
    message_font_scale = config.message_font_scale,
    chat_ttl_seconds = tonumber((config.behavior or {}).message_ttl_seconds) or 86400,
    combat_ttl_seconds = tonumber((config.behavior or {}).message_ttl_seconds) or 86400,
    chat_max_messages_per_tab = tonumber((config.behavior or {}).max_messages_per_tab) or 300,
    combat_max_messages_per_tab = tonumber((config.behavior or {}).max_messages_per_tab) or 300,
    theme = T{},
    colors = T{},
    unread = T{
        blink_tabs = T(config.unread.blink_tabs or {}),
    },
    window_bg_theme = '-None-',
    window_bg_opacity = 1.0,
    combat_bg_theme = '-None-',
    combat_bg_opacity = 1.0,
    combat_filters = T{},
    combat_filter_disabled = T{},
}

-- Load persisted settings
local cfg = settings.load(default_settings)

-- Register update handler (if settings are reloaded externally)
settings.register('settings', 'whispers_settings_update', function(s)
    if (s ~= nil) then
        cfg = s
    end
end)

-- map of sender -> list of { time = os.time(), text = string }
local tells, display_names = storage.make_default_tells(config.default_tabs)
local unread = {}
local last_msg_count = {}
local combat_last_msg_count = 0
local player_order = {}  -- Track the order players are first received
local player_order_seen = {}

-- Persistence: save/load messages across addon reloads (24-hour TTL)
local save_dir  = addon.path .. 'data'
local chat_save_file = addon.path .. 'data/messages.dat'
local combat_save_file = addon.path .. 'data/combat_messages.dat'
local combat_tab_canonical = normalize_name((tab_cfg and tab_cfg.combat) or 'combat log')
local default_message_ttl_seconds = tonumber(behavior_cfg.message_ttl_seconds) or 86400
local default_max_messages_per_tab = tonumber(behavior_cfg.max_messages_per_tab) or 300

local save_needed = false
local save_last_clock = 0
local save_messages
local mark_save_needed

local function clamp_int(value, fallback, min_value)
    local n = math.floor(tonumber(value) or fallback or 0)
    if min_value ~= nil and n < min_value then
        n = min_value
    end
    return n
end

local function get_chat_ttl_seconds()
    return clamp_int(cfg.chat_ttl_seconds, default_message_ttl_seconds, 60)
end

local function get_combat_ttl_seconds()
    return clamp_int(cfg.combat_ttl_seconds, default_message_ttl_seconds, 60)
end

local function get_chat_max_messages_per_tab()
    return clamp_int(cfg.chat_max_messages_per_tab, default_max_messages_per_tab, 1)
end

local function get_combat_max_messages_per_tab()
    return clamp_int(cfg.combat_max_messages_per_tab, default_max_messages_per_tab, 1)
end

local function trim_messages_by_limits()
    local chat_max = get_chat_max_messages_per_tab()
    local combat_max = get_combat_max_messages_per_tab()

    for canonical, tab_msgs in pairs(tells) do
        if type(tab_msgs) == 'table' then
            local max_msgs = (canonical == combat_tab_canonical) and combat_max or chat_max
            while #tab_msgs > max_msgs do
                table.remove(tab_msgs, 1)
            end
        end
    end
end

local function trim_messages_by_ttl()
    local now = os.time()
    local chat_cutoff = now - get_chat_ttl_seconds()
    local combat_cutoff = now - get_combat_ttl_seconds()

    for canonical, tab_msgs in pairs(tells) do
        if type(tab_msgs) == 'table' and #tab_msgs > 0 then
            local cutoff = (canonical == combat_tab_canonical) and combat_cutoff or chat_cutoff
            local write_index = 1
            for read_index = 1, #tab_msgs do
                local msg = tab_msgs[read_index]
                if type(msg) == 'table' and type(msg.time) == 'number' and msg.time >= cutoff then
                    tab_msgs[write_index] = msg
                    write_index = write_index + 1
                end
            end
            for i = #tab_msgs, write_index, -1 do
                tab_msgs[i] = nil
            end
        end
    end
end

local function apply_storage_constraints(force_save)
    trim_messages_by_ttl()
    trim_messages_by_limits()
    if force_save then
        save_needed = false
        save_last_clock = os.clock()
        save_messages()
    else
        mark_save_needed()
    end
end

save_messages = function()
    trim_messages_by_ttl()
    trim_messages_by_limits()

    local chat_tells = {}
    local combat_tells = {}
    for canonical, msgs in pairs(tells) do
        if canonical == combat_tab_canonical then
            combat_tells[canonical] = msgs
        else
            chat_tells[canonical] = msgs
        end
    end

    storage.save_messages(save_dir, chat_save_file, chat_tells, display_names, player_order)
    storage.save_messages(save_dir, combat_save_file, combat_tells, display_names, player_order)
end

mark_save_needed = function()
    save_needed = true
end

local function flush_save_if_needed()
    if save_needed then
        local now = os.clock()
        if (now - save_last_clock) >= 3.0 then
            save_needed = false
            save_last_clock = now
            save_messages()
        end
    end
end

storage.load_messages(chat_save_file, tells, display_names, player_order, get_chat_ttl_seconds())
storage.load_messages(combat_save_file, tells, display_names, player_order, get_combat_ttl_seconds())
trim_messages_by_limits()
for _, canonical in ipairs(player_order) do
    player_order_seen[canonical] = true
end

local chat_mode_tabs = config.chat_mode_tabs
local tab_commands    = config.tab_commands
local tab_context = tabs.create(config, tab_cfg, normalize_name, trim)
local all_tab = tab_context.all_tab
local linkshell1_tab = tab_context.linkshell1_tab
local linkshell2_tab = tab_context.linkshell2_tab
local party_tab = tab_context.party_tab
local say_tab = tab_context.say_tab
local combat_tab = tab_context.combat_tab
local yells_tab = tab_context.yells_tab
local crafting_helm_tab = tab_context.crafting_helm_tab
local server_tab = tab_context.server_tab
local is_fixed_channel_tab = tab_context.is_fixed_channel_tab
local is_linkshell_tab = tab_context.is_linkshell_tab
local is_read_only_tab = tab_context.is_read_only_tab
local infer_linkshell_tab_info = tab_context.infer_linkshell_tab_info

local function add_tell(sender, text, from, auto_translate_braces, chat_mode, source_tab)
    local original_tab = sender or ''
    local canonical = normalize_name(original_tab)
    if canonical == '' then canonical = msg_cfg.unknown_tab_canonical end
    local source_canonical = normalize_name(source_tab or canonical)
    if source_canonical == '' then
        source_canonical = canonical
    end
    text = text or ''
    local now = os.time()
    local mode_num = nil
    if type(chat_mode) == 'number' then
        mode_num = math.floor(chat_mode)
    end
    tells[canonical] = tells[canonical] or {}
    local from_name = nil
    if from and tostring(from) ~= '' then
        from_name = trim(tostring(from))
    else
        from_name = display_names[canonical] or original_tab or msg_cfg.unknown_sender
    end
    local last = tells[canonical][#tells[canonical]]
    if last and last.text == text and last.sender == from_name and last.chat_mode == mode_num and last.source_tab == source_canonical and (now - last.time) <= behavior_cfg.dedupe_seconds then
        if not display_names[canonical] or display_names[canonical] == '' then
            display_names[canonical] = original_tab
        end
        return canonical, false
    end
    local braces = nil
    if type(auto_translate_braces) == 'table' and #auto_translate_braces > 0 then
        braces = {}
        for _, idx in ipairs(auto_translate_braces) do
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
    table.insert(tells[canonical], {
        time = now,
        text = text,
        sender = from_name,
        auto_translate_braces = braces,
        chat_mode = mode_num,
        source_tab = source_canonical,
    })
    if not display_names[canonical] or display_names[canonical] == '' then
        display_names[canonical] = original_tab
    end
    -- Track player insertion order (skip fixed channel tabs)
    if not is_fixed_channel_tab(canonical) then
        if player_order_seen[canonical] ~= true then
            table.insert(player_order, canonical)
            player_order_seen[canonical] = true
        end
    end
    -- Enforce per-tab message cap (trim oldest entries)
    local max_msgs = (canonical == combat_tab_canonical) and get_combat_max_messages_per_tab() or get_chat_max_messages_per_tab()
    local tab_msgs = tells[canonical]
    while #tab_msgs > max_msgs do
        table.remove(tab_msgs, 1)
    end
    mark_save_needed()
    return canonical, true
end
local parse_chat_line = function(text)
    return parser.parse_chat_line(text, parser_cfg, trim)
end
local strip_channel_label = function(text, tab_label)
    return parser.strip_channel_label(text, tab_label, trim)
end
local infer_self_message_body = function(text, player_name)
    return parser.infer_self_message_body(text, player_name, trim)
end
local normalize_message_text = function(text)
    return parser.normalize_message_text(text, trim)
end
local parse_examine_sender = function(packet_data)
    return parser.parse_examine_sender(packet_data, trim)
end
local is_combat_log_line = function(text)
    return parser.is_combat_log_line(text, combat_cfg.fallback_patterns, trim)
end
local is_mob_loot_line = function(text)
    return parser.is_mob_loot_line(text, combat_cfg.loot_patterns, trim)
end
local is_crafting_helm_line = function(text)
    return parser.is_combat_log_line(text, crafting_cfg.fallback_patterns, trim)
end
local is_skill_up_line = function(text)
    local value = tostring(text or ''):lower()
    if value == '' then
        return false
    end

    -- Covers both combat and crafting progression lines.
    -- Examples: "... skill rises 0.1 points.", "... skill reaches level N.",
    -- and "Your Triple Attack Rate modification has risen to level N."
    return (value:match('skill rises %d+%.%d+ points%.?$') ~= nil)
        or (value:match('skill reaches level %d+%.?$') ~= nil)
        or (value:match('^your .+ modification has risen to level %d+%.?$') ~= nil)
end

local pending_outgoing = outgoing.create(behavior_cfg, normalize_name, trim, normalize_message_text)
local remember_pending_outgoing = pending_outgoing.remember
local take_pending_outgoing = pending_outgoing.take_pending
local take_any_pending_outgoing = pending_outgoing.take_any
local pending_linkshell_announcement = nil

local presence_tracker = presence.create(normalize_name, trim)
local get_local_player_name = presence_tracker.get_local_player_name
local get_party_member_canonicals = presence_tracker.get_party_member_canonicals
local get_visible_player_canonicals = presence_tracker.get_visible_player_canonicals
local get_visible_non_player_canonicals = presence_tracker.get_visible_non_player_canonicals

local function open_tab_for_message(canonical, is_new, suppress_unread)
    local was_open = state.is_open[1]
    if is_new and canonical ~= state.selected and not suppress_unread then
        unread[canonical] = os.time()
    end

    state.is_open[1] = true
    if (not was_open) or (not state.selected) then
        state.selected = canonical
    end
end

local function get_tab_display_name(canonical)
    return tab_context.get_tab_display_name(canonical, display_names)
end

local function remove_player_from_order(canonical)
    if canonical == nil or canonical == '' then
        return
    end

    player_order_seen[canonical] = nil
    for i = #player_order, 1, -1 do
        if player_order[i] == canonical then
            table.remove(player_order, i)
            break
        end
    end
end

local function clear_tab(name)
    if is_fixed_channel_tab(name) then
        tells[name] = {}
    else
        tells[name] = nil
        display_names[name] = nil
        remove_player_from_order(name)
    end
    unread[name] = nil
    last_msg_count[name] = nil
    if name == combat_tab then
        combat_last_msg_count = 0
    end
    save_messages()
end

local outgoing_router = outgoing_commands.create({
    parser = parser,
    trim = trim,
    normalize_name = normalize_name,
    remember_pending_outgoing = remember_pending_outgoing,
    tab_commands = tab_commands,
    command_cfg = command_cfg,
    all_tab = all_tab,
    party_tab = party_tab,
    say_tab = say_tab,
    linkshell1_tab = linkshell1_tab,
    linkshell2_tab = linkshell2_tab,
    yells_tab = yells_tab,
})

local function queue_tab_message(name, display, message)
    return outgoing_router.queue_tab_message(name, display, message, state)
end

local render_context = {
    config = config,
    ui_cfg = ui_cfg,
    msg_cfg = msg_cfg,
    unread_cfg = unread_cfg,
    color_cfg = color_cfg,
    state = state,
    settings = settings,
    all_tab = all_tab,
    party_tab = party_tab,
    linkshell1_tab = linkshell1_tab,
    linkshell2_tab = linkshell2_tab,
    say_tab = say_tab,
    combat_tab = combat_tab,
    yells_tab = yells_tab,
    crafting_helm_tab = crafting_helm_tab,
    server_tab = server_tab,
    apply_all_tab_command_prefix = function(text, command)
        return parser.apply_all_tab_command_prefix(text, command, trim)
    end,
    normalize_name = normalize_name,
    map_line_brace_indices = map_line_brace_indices,
    format_message_line = format_message_line,
    text_wrapped_bold_with_translate_braces = text_wrapped_bold_with_translate_braces,
    is_linkshell_tab = is_linkshell_tab,
    is_fixed_channel_tab = is_fixed_channel_tab,
    is_read_only_tab = is_read_only_tab,
    get_cfg = function()
        return cfg
    end,
    get_tells = function()
        return tells
    end,
    get_display_names = function()
        return display_names
    end,
    get_unread = function()
        return unread
    end,
    get_last_msg_count = function()
        return last_msg_count
    end,
    get_combat_last_msg_count = function()
        return combat_last_msg_count
    end,
    set_combat_last_msg_count = function(value)
        combat_last_msg_count = tonumber(value) or 0
    end,
    get_player_order = function()
        return player_order
    end,
    get_local_player_name = get_local_player_name,
    get_party_member_canonicals = get_party_member_canonicals,
    get_visible_player_canonicals = get_visible_player_canonicals,
    get_visible_non_player_canonicals = get_visible_non_player_canonicals,
    queue_tab_message = queue_tab_message,
    clear_tab = clear_tab,
    apply_storage_constraints = apply_storage_constraints,
    get_storage_defaults = function()
        return {
            ttl_seconds = default_message_ttl_seconds,
            max_messages_per_tab = default_max_messages_per_tab,
        }
    end,
    addon_version = addon.version,
}

ashita.events.register('command', 'whispers_command', function (e)
    local args = e.command:args();
    local raw = trim(e.command or '')
    local direct_tell_prefix = trim(command_cfg.direct_tell_prefix or '/tell'):lower()

    if not e.injected then
        local prefix, remainder = raw:match('^(%S+)%s*(.*)$')
        local prefix_lower = prefix and prefix:lower() or nil

        if prefix_lower == direct_tell_prefix then
            local target, tell_message = trim(remainder or ''):match('^(%S+)%s+(.+)$')
            if target ~= nil and trim(tell_message or '') ~= '' then
                remember_pending_outgoing(target, tell_message)
            end
        else
            local observed_tab = prefix_lower and command_cfg.observe_chat_commands[prefix_lower] or nil
            if observed_tab ~= nil and trim(remainder or '') ~= '' then
                remember_pending_outgoing(observed_tab, remainder)
            end
        end
    end

    if (#args == 0 or not args[1]:any(command_cfg.toggle)) then
        return;
    end

    e.blocked = true;
    local subcommand = (args[2] and tostring(args[2]):lower()) or ''
    if subcommand == 'ui' or subcommand == 'chat' then
        local should_open = not (state.is_open[1] or state.combat_is_open[1])
        state.is_open[1] = should_open
        state.combat_is_open[1] = should_open
        return;
    end

    state.config_is_open[1] = true
end);

-- Incoming text handler: capture tells and linkshell chat.
ashita.events.register('text_in', 'whispers_text_in', function (e)
    local mode = bit.band(e.mode_modified or e.mode or 0, 0x000000FF);
    local tab_info = chat_mode_tabs[mode]

    -- Prefer the modified message (cleaned by Ashita) when available
    local raw = e.message_modified or e.message or ''

    -- Build both variants so only true auto-translate braces are colorized later.
    local parsed_with_braces = AshitaCore:GetChatManager():ParseAutoTranslate(raw, true)
    local parsed_without_braces = AshitaCore:GetChatManager():ParseAutoTranslate(raw, false)
    local clean = normalize_chat_text(parsed_with_braces, true)
    local clean_without_translate_braces = normalize_chat_text(parsed_without_braces, false)

    -- Remove common leading timestamps like [HH:MM:SS] or {HH:MM:SS}
    local cleaned_no_ts = clean:gsub(parser_cfg.leading_timestamp_pattern, '')
    local cleaned_no_ts_plain = clean_without_translate_braces:gsub(parser_cfg.leading_timestamp_pattern, '')
    local cleaned_no_ts_plain_lower = cleaned_no_ts_plain:lower()
    local parenthesized_sender, parenthesized_body = cleaned_no_ts_plain:match('^%s*%(([^%)]+)%)%s*(.+)$')
    local explicit_party_format = (
        parenthesized_sender ~= nil
        and trim(parenthesized_sender) ~= ''
        and trim(parenthesized_body or '') ~= ''
    )

    local claimed_pending = nil
    local claimed_linkshell_announcement = nil
    local matched_pending = false

    local force_all_tab = (
        cleaned_no_ts_plain_lower:match('^%s*[%a%s%-]*moogle%s*:') ~= nil
        or cleaned_no_ts_plain_lower:match('^.+ wishes to trade with you%.?$') ~= nil
    )
    if force_all_tab then
        tab_info = { tab = all_tab }
    end

    -- Route party system feedback messages to the Party tab.
    local force_party_tab = (
        cleaned_no_ts_plain_lower:match('there are no party members') ~= nil
        or explicit_party_format
    )
    if force_party_tab then
        tab_info = { tab = party_tab }
    end

    if pending_linkshell_announcement ~= nil then
        if os.clock() > (pending_linkshell_announcement.expires or 0) then
            pending_linkshell_announcement = nil
        else
            local continuation_text = trim(cleaned_no_ts_plain or '') or ''
            local current_tab = tab_info and normalize_name(tab_info.tab) or ''
            if continuation_text:match('^["\']') and (current_tab == '' or current_tab == say_tab) then
                tab_info = {
                    tab = pending_linkshell_announcement.tab,
                }
                claimed_linkshell_announcement = pending_linkshell_announcement
            end
        end
    end

    -- Route addon/system notices to Server, not Say or Combat.
    local force_server_tab = (
        cleaned_no_ts_plain_lower:match('^%[addons%]')
        or cleaned_no_ts_plain_lower:match('^%[ashita%]')
        or cleaned_no_ts_plain_lower:match('^%[conquest%]')
        or cleaned_no_ts_plain_lower:match('^%[fps%]')
        or cleaned_no_ts_plain_lower:match('^%[luashitacast%]')
        or cleaned_no_ts_plain_lower:match('^%[xiui%]')
        or cleaned_no_ts_plain_lower:match('^%[points%]')
    )
    if force_server_tab then
        tab_info = { tab = server_tab }
    end

    local force_combat_loot_tab = (not force_server_tab)
        and (is_mob_loot_line(cleaned_no_ts_plain) or is_mob_loot_line(cleaned_no_ts))
    if force_combat_loot_tab then
        tab_info = {
            tab = combat_tab,
        }
    end

    if (not force_server_tab and not force_all_tab and not force_party_tab and not force_combat_loot_tab) and (mode ~= 12 and (is_skill_up_line(cleaned_no_ts_plain) or is_skill_up_line(cleaned_no_ts))) then
        tab_info = {
            tab = combat_tab,
        }
    elseif (not force_server_tab and not force_all_tab and not force_party_tab and not force_combat_loot_tab) and (mode ~= 12 and (is_crafting_helm_line(cleaned_no_ts_plain) or is_crafting_helm_line(cleaned_no_ts))) then
        tab_info = {
            tab = crafting_helm_tab,
        }
    elseif (not force_server_tab and not force_all_tab and not force_party_tab and not force_combat_loot_tab) and (mode ~= 12 and tab_info == nil) then
        if is_combat_log_line(cleaned_no_ts_plain) or is_combat_log_line(cleaned_no_ts) then
            tab_info = {
                tab = combat_tab,
            }
        else
            local inferred_tab_info, inferred_text = infer_linkshell_tab_info(cleaned_no_ts)
            if inferred_tab_info ~= nil then
                tab_info = inferred_tab_info
                cleaned_no_ts = inferred_text
                local _, inferred_plain = infer_linkshell_tab_info(cleaned_no_ts_plain)
                cleaned_no_ts_plain = inferred_plain or cleaned_no_ts_plain
            else
                claimed_pending = take_any_pending_outgoing(cleaned_no_ts)
                if claimed_pending == nil then
                    return;
                end
                matched_pending = true

                tab_info = {
                    tab = get_tab_display_name(claimed_pending.tab),
                }
                cleaned_no_ts = claimed_pending.text
                cleaned_no_ts_plain = claimed_pending.text
            end
        end
    end

    if tab_info ~= nil then
        cleaned_no_ts = strip_channel_label(cleaned_no_ts, tab_info.tab)
        cleaned_no_ts_plain = strip_channel_label(cleaned_no_ts_plain, tab_info.tab)

        local lsmsg_header_sender = cleaned_no_ts:match('^%[%d%]%s*<([^>]+)>%s*$')
            or cleaned_no_ts:match('^<([^>]+)>%s*$')
        if lsmsg_header_sender ~= nil and is_linkshell_tab(normalize_name(tab_info.tab)) then
            pending_linkshell_announcement = {
                tab = tab_info.tab,
                sender = trim(lsmsg_header_sender),
                expires = os.clock() + 3.0,
            }
            return;
        end
    end

    local tab_canonical = tab_info and normalize_name(tab_info.tab) or nil

    local sender, body = parse_chat_line(cleaned_no_ts)
    local _, body_plain = parse_chat_line(cleaned_no_ts_plain)
    if claimed_pending ~= nil then
        sender = get_local_player_name() or sender or msg_cfg.unknown_sender
        body = claimed_pending.text
        body_plain = claimed_pending.text
    end

    if claimed_linkshell_announcement ~= nil then
        if sender == nil or sender == '' then
            sender = claimed_linkshell_announcement.sender
        end
        pending_linkshell_announcement = nil
    end

    if tab_canonical ~= nil and sender and normalize_name(sender) == tab_canonical then
        local reparsed_sender, reparsed_body = parse_chat_line(body or '')
        local reparsed_sender_plain, reparsed_body_plain = parse_chat_line(body_plain or '')
        if reparsed_sender and normalize_name(reparsed_sender) ~= tab_canonical then
            sender = reparsed_sender
            body = reparsed_body
            if reparsed_sender_plain and normalize_name(reparsed_sender_plain) ~= tab_canonical then
                body_plain = reparsed_body_plain
            else
                body_plain = reparsed_body or body_plain
            end
        else
            sender = nil
            body = trim(body or cleaned_no_ts)
            body_plain = trim(body_plain or cleaned_no_ts_plain)
        end
    end

    if (mode == 12 and (not sender or sender == '')) then
        sender = msg_cfg.unknown_sender
    end

    if tab_canonical ~= nil and tab_canonical ~= '' and (not sender or sender == '') then
        local pending = take_pending_outgoing(tab_canonical, body or cleaned_no_ts)
        if pending ~= nil then
            sender = get_local_player_name() or msg_cfg.unknown_sender
            body = pending.text
            body_plain = pending.text
            matched_pending = true
        end
    end

    if tab_canonical == 'party' and (not sender or sender == '') then
        local me = get_local_player_name()
        local inferred_body = infer_self_message_body(cleaned_no_ts, me)
        local inferred_body_plain = infer_self_message_body(cleaned_no_ts_plain, me)
        if inferred_body ~= nil then
            sender = me or msg_cfg.unknown_sender
            body = inferred_body
            body_plain = inferred_body_plain or inferred_body
        end
        -- Modes 13/215 are real game party/alliance channels; never drop them.
    end

    if tab_canonical == 'party' and mode == 1 then
        local me = normalize_name(get_local_player_name() or '')
        local who = normalize_name(sender or '')
        local from_me = (me ~= '' and who == me)
        if (not matched_pending) and (not from_me) and (not explicit_party_format) then
            return;
        end
    end

    local tab_name = sender
    local from_name = sender
    if tab_info ~= nil then
        tab_name = tab_info.tab
        -- For fixed channel tabs (Party, LS1, LS2), don't fall back to the tab name as sender.
        -- If no sender was parsed the message will render without a name prefix.
        local is_channel = is_fixed_channel_tab(normalize_name(tab_info.tab))
        from_name = sender or (not is_channel and tab_info.tab) or nil
    end

    local auto_translate_braces = find_autotranslate_brace_indices(body, body_plain)
    local canonical, is_new = add_tell(tab_name, body, from_name, auto_translate_braces, mode)
    if canonical ~= nil and canonical ~= '' and canonical ~= combat_tab and canonical ~= crafting_helm_tab and canonical ~= all_tab then
        add_tell(all_tab, body, from_name, auto_translate_braces, mode, canonical)
    end

    local me = normalize_name(get_local_player_name() or '')
    local who = normalize_name(from_name or '')
    local sent_by_me = matched_pending or (me ~= '' and who == me)
    open_tab_for_message(canonical, is_new, sent_by_me)
end);

ashita.events.register('packet_in', 'whispers_packet_in', function (e)
    local examine_cfg = packet_cfg.examine or {}
    local incoming_id = tonumber(examine_cfg.incoming_id) or 0x0009
    if e.id ~= incoming_id then
        return
    end

    local data = e.data_modified or e.data or ''
    if data == '' then
        return
    end

    local message_offset = tonumber(examine_cfg.message_offset) or (0x0A + 1)
    local message_id = struct.unpack('H', data, message_offset)
    if message_id ~= (tonumber(examine_cfg.message_id) or 89) then
        return
    end

    local examiner = parse_examine_sender(data)
    local route_tab = normalize_name(examine_cfg.route_tab or yells_tab)
    local text = tostring(examine_cfg.text or 'examines you.')
    local chat_mode = tonumber(examine_cfg.chat_mode) or 15
    local canonical, is_new = add_tell(route_tab, text, examiner, nil, chat_mode)
    if canonical ~= nil and canonical ~= '' and canonical ~= combat_tab and canonical ~= crafting_helm_tab and canonical ~= all_tab then
        add_tell(all_tab, text, examiner, nil, chat_mode, canonical)
    end
    open_tab_for_message(canonical, is_new)
end)

ashita.events.register('d3d_present', 'whispers_present', function ()
    flush_save_if_needed()
    ui.render(render_context)
end);

ashita.events.register('unload', 'whispers_unload', function ()
    ui.destroy_backgrounds()
end);

-- Helper command to clear all stored tells
ashita.events.register('command', 'whispers_clear_all', function (e)
    local args = e.command:args();
    if (#args == 0 or not args[1]:any(command_cfg.clear_all)) then
        return;
    end

    e.blocked = true;
    tells, display_names = storage.make_default_tells(config.default_tabs)
    unread = {}
    last_msg_count = {}
    combat_last_msg_count = 0
    player_order = {}
    player_order_seen = {}
    pending_outgoing.clear()
    pending_linkshell_announcement = nil
    state.selected = nil
    save_messages()
end);
