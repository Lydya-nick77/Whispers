-- Whispers addon configuration
local config = {}

-- Default window dimensions and position (persisted via the settings module)
config.default_window = {
    width  = 500,
    height = 220,
    x      = 100,
    y      = 100,
}

config.default_combat_window = {
    width  = 500,
    height = 220,
    x      = 620,
    y      = 100,
}

-- Global font scale for the Whispers window. 1.0 = default size.
config.font_scale = 1.0

-- Font scale applied to chat messages only (tabs and buttons are unaffected). 1.0 = default size.
config.message_font_scale = 1.1

-- UI behavior and rendering constants.
config.ui = {
    min_font_scale = 0.5,
    input_max_length = 512,
    bold_offset_x = 0.8,
    scroll_to_bottom_fraction = 1.0,  -- 0.0 = top, 1.0 = bottom; fraction to jump to on new messages
    shortcuts = {
        focus_input = {
            enabled = true,
            vkey = 0x52,      -- Ctrl+R
            require_ctrl = true,
            require_shift = false,
            require_alt = false,
        },
    },
    chat_layout = {
        min_chat_height = 1,
        read_only_footer_padding = 12,
        input_row_padding = 12,
    },
}

-- Static text and formatting used in the UI.
config.messages = {
    no_recent_tells = 'No recent tells',
    unknown_sender = 'Unknown',
    unknown_tab_canonical = 'unknown',
    timestamp_format = '%H:%M:%S',
}

-- Chat parsing behavior.
config.parser = {
    patterns = {
        '^%[%d%]%s*<([^>]+)>%s*(.*)$',
        '^<([^>]+)>%s*(.*)$',
        '^%(([^%)]+)%)%s*(.*)$',
        '^(.-) tells you[,:%s]*["\']?(.-)["\']?$',
        '^(.-)>>%s*(.*)$',
        '^(.-)%>%>%s*(.*)$',
        '^(.-)%s+shouts%s*:%s*(.*)$',                -- "Name shouts: text"
        '^(.-)%s+yells across[^:]*:%s*(.*)$',        -- "Name yells across Vana'diel: text"
    },
    name_colon_pattern = '^([%a][%w_%-]+)%s*:%s*(.*)$',
    leading_timestamp_pattern = '^%s*[%[%{<]?%d%d:%d%d:?%d?%d?[%]%}>]?%s*',
}

-- Fallback text matching for combat lines when chat mode IDs are not mapped.
config.combat = {
    fallback_patterns = {
        '^.+ begin casting .+$',
        '^.+ begins casting .+$',
        '^.+ start casting .+$',
        '^.+ starts casting .+$',
        '^.+ casts .+$',
        '^.+ readies .+$',
        '^.+ uses .+$',
        '^.+ use an .+$',
        '^%b[]%s*.+%s*%-%>%s*.+$',
        '^%b[]%s*.+%s*%=%>%s*.+$',
    },
    loot_patterns = {
        '^you find .+ on the .+%.$',
        '^you find .+ on .+%.$',
        '^you find nothing on the .+%.$',
        '^you find nothing on .+%.$',
        '^you take .+ out of delivery slot %d+%.?$',
        '^you do not meet the requirements to obtain .+%.$',
        '^.+ abjuration lost%.?$',
        '^.+ lot for .+: [%d,]+ points%.?$',
        '^the money the buyer paid for .+ you put on auction, [%d,]+ gil%.?$',
        '^you obtains? %d+ gil%s*%.?$',
        '^.+ obtains? %d+ gil%s*%.?$',
        '^you gains? [%d,]+ experience points?%s*%.?$',
        '^.+ gains? [%d,]+ experience points?%s*%.?$',
        '^you gains? [%d,]+ limit points?%s*%.?$',
        '^.+ gains? [%d,]+ limit points?%s*%.?$',
        '^you gains? [%d,]+ capacity points?%s*%.?$',
        '^.+ gains? [%d,]+ capacity points?%s*%.?$',
    },
}

-- Crafting / HELM messages (synthesis, mining, logging, excavating, harvesting).
config.crafting_helm = {
    fallback_patterns = {
        '^.+synthesis.+$',
        '^.+synthesize[s]? .+$',
        '^.+synthesi[sz]ed .+$',
        '^.+starts? synthesiz?ing%.?$',
        '^.+uses an? [^%.]+ crystal%.?$',
        '^.+craft result:.+$',
        '^%-+%s*nq synthesis.+$',
        '^%-+%s*hq synthesis.+$',
        '^%-+%s*break%s*%(.+%).+$',
        '^%-+%s*hq tier %d.+$',
        '^.+dig up an? .+$',
        '^.+cut off an? .+$',
        '^.+harvest an? .+$',
        '^.+uses an? pickaxe%.?$',
        '^.+uses an? hatchet%.?$',
        '^.+uses an? sickle%.?$',
        '^.+uses .+ and finds .+$',
        '^.+uses .+ but finds nothing%.?$',
        '^.+unable to mine anything%.?$',
        '^.+unable to log anything%.?$',
        '^.+unable to harvest anything%.?$',
        '^.+our pickaxe breaks%.?$',
        '^.+our hatchet breaks%.?$',
        '^.+our sickle breaks%.?$',
        '^.+obtained [%d,]+ .+%.?$',
        '^.+obtained an? .+%.?$',
        '^.+obtained some .+%.?$',
        '^.+lost an? .+$',
    },
}

-- Runtime behavior controls.
config.behavior = {
    dedupe_seconds = 3,
    pending_match_seconds = 5,
    message_ttl_seconds = 86400,
    max_messages_per_tab = 300,
}

config.tabs = {
    all = 'all',
    linkshell1 = 'linkshell 1',
    linkshell2 = 'linkshell 2',
    party = 'party',
    combat = 'combat log',
    say = 'say',
    yells = 'yells',
    crafting_helm = 'crafting/helm',
    server = 'server',
    read_only = {},
}

config.tabs.read_only = {
    [config.tabs.combat] = true,
    [config.tabs.yells] = true,
    [config.tabs.crafting_helm] = true,
    [config.tabs.server] = true,
}

-- Combat log mode IDs mirrored from SimpleLog block_modes.
config.combat_log_mode_ids = {
    20, 21, 22, 23, 24, 25, 26, 27,
    28, 29, 30, 31, 32, 33, 34, 35,
    40, 41, 42, 43,
    56, 57, 58, 59, 60, 61, 62, 63,
    104, 109, 114, 129,
    162, 163, 164, 165,
    181, 185, 186, 187, 188,
}

config.packets = {
    examine = {
        incoming_id = 0x0009,
        message_offset = 0x0A + 1,
        message_id = 89,
        route_tab = config.tabs.yells,
        text = 'examines you.',
        chat_mode = 15,
    },
}

-- Unread tab blinking behavior.
config.unread = {
    blink_speed_hz = 2,
    tab_color_a = { 1.0, 0.5, 0.2, 1.0 },
    tab_color_b = { 1.0, 0.2, 0.2, 1.0 },
    -- Per-tab blink toggle (uses canonical tab names). Unknown tabs fall back to `default`.
    blink_tabs = {
        default = true,
        [config.tabs.all] = true,
        [config.tabs.linkshell1] = true,
        [config.tabs.linkshell2] = true,
        [config.tabs.party] = true,
        [config.tabs.say] = true,
        [config.tabs.yells] = true,
        [config.tabs.crafting_helm] = true,
        [config.tabs.server] = true,
        [config.tabs.combat] = true,
    },
}

-- Combat log message type filters (enabled by default).
config.combat_filters = {
    general       = true,
    loot_gain     = true,
    player_item   = true,
    player_action = true,
    enemy_action  = true,
}

-- Addon command configuration.
config.commands = {
    toggle = '/whispers',
    clear_all = '/whispersclear',
    direct_tell_prefix = '/tell',
    observe_chat_commands = {
        ['/s'] = config.tabs.say,
        ['/p'] = config.tabs.party,
        ['/a'] = config.tabs.party,
        ['/l'] = config.tabs.linkshell1,
        ['/l2'] = config.tabs.linkshell2,
    },
}

-- Window styling
config.style = {
    -- Window behavior flags
    no_title_bar                   = true,   -- Hide the title bar completely
    no_collapse                    = true,   -- Disable the collapse arrow (only relevant when no_title_bar is false)
    no_close_tab_with_middle_mouse = true,   -- Prevent closing tabs by middle-clicking

    -- Shape rounding
    window_rounding    = 10.0,  -- Corner radius for the main window
    window_border_size = 1.0,   -- Border thickness (0 = no border)
    tab_rounding       = 6.0,   -- Corner radius for tabs
    frame_rounding     = 5.0,   -- Corner radius for input fields
    frame_border_size  = 0.0,   -- Border for input fields
    scrollbar_rounding = 4.0,   -- Corner radius for scrollbar thumb
    scrollbar_size     = 8.0,   -- Scrollbar width in pixels (default is 14)

    -- Color theme: RGBA tables {r, g, b, a} each in 0.0–1.0 range.
    -- Set any value to nil to inherit the default ImGui color.
    theme = {
        -- Window chrome
        window_bg          = { 0.07, 0.07, 0.11, 0.00 },  -- Fully transparent main window background
        title_bg           = { 0.08, 0.09, 0.17, 1.00 },  -- Dark indigo title bar (unfocused)
        title_bg_active    = { 0.12, 0.14, 0.28, 1.00 },  -- Slightly brighter when focused
        title_bg_collapsed = { 0.07, 0.07, 0.12, 0.90 },  -- Collapsed state
        border             = { 0.30, 0.32, 0.52, 0.00 },  -- Transparent main window border

        -- Tab bar
        tab                = { 0.07, 0.08, 0.15, 0.90 },  -- Inactive tab
        tab_hovered        = { 0.18, 0.20, 0.36, 1.00 },  -- Hovered tab
        tab_active         = { 0.22, 0.26, 0.46, 1.00 },  -- Selected tab

        -- Chat child panel
        child_bg           = { 0.04, 0.04, 0.08, 0.70 },  -- Darker inset for the message area
        scrollbar_bg       = { 0.02, 0.02, 0.05, 0.40 },
        scrollbar_grab     = { 0.20, 0.22, 0.38, 0.70 },
        scrollbar_grab_hov = { 0.28, 0.30, 0.50, 0.90 },
        separator          = { 0.24, 0.26, 0.42, 0.70 },

        -- Input field
        frame_bg           = { 0.09, 0.09, 0.17, 0.80 },
        frame_bg_hovered   = { 0.13, 0.14, 0.24, 0.90 },
        frame_bg_active    = { 0.17, 0.18, 0.30, 1.00 },

        -- Buttons
        button             = { 0.11, 0.12, 0.22, 1.00 },
        button_hovered     = { 0.20, 0.22, 0.38, 1.00 },
        button_active      = { 0.28, 0.32, 0.52, 1.00 },
    },
}

-- Maps incoming FFXI chat mode IDs to their tab name and reply command
config.chat_mode_tabs = {
    [1]   = { tab = 'Say',         command = '/s'  },
    [9]   = { tab = 'Say',         command = '/s'  },
    [13]  = { tab = 'Party',       command = '/p'  },
    [215] = { tab = 'Party',       command = '/a'  },
    [2]   = { tab = 'Linkshell 1', command = '/l'  },
    [3]   = { tab = 'Linkshell 2', command = '/l2' },
    [14]  = { tab = 'Linkshell 1', command = '/l'  },
    [214] = { tab = 'Linkshell 2', command = '/l2' },
    [10]  = { tab = 'Yells',       command = '/shout' },
    [11]  = { tab = 'Yells',       command = '/yell' },
    [15]  = { tab = 'Yells' },  -- emote
    [8]   = { tab = 'Crafting/HELM' },
    [121] = { tab = 'All' },
    [150] = { tab = 'Server' }, -- server / message
    [151] = { tab = 'Server' }, -- server / system
    [152] = { tab = 'Server' }, -- server / message2
}

for _, mode_id in ipairs(config.combat_log_mode_ids) do
    if config.chat_mode_tabs[mode_id] == nil then
        config.chat_mode_tabs[mode_id] = { tab = 'Combat Log' }
    end
end

-- Maps canonical (lowercase) tab names to their outgoing chat command prefix
config.tab_commands = {
    [config.tabs.say] = '/s',
    [config.tabs.party] = '/p',
    [config.tabs.linkshell1] = '/l',
    [config.tabs.linkshell2] = '/l2',
}

-- Text colors for chat tabs (RGBA, each component 0.0–1.0)
config.colors = {
    all = { 1.0, 1.0, 1.0, 1.0 },              -- White (All tab)
    linkshell1 = { 0.86,  1.0,  0.76,  1.0 },  -- Yellow/green
    linkshell2 = { 0.35, 1.0,   0.35,  1.0 },  -- Light green
    party = { 0.20, 0.95, 1.0, 1.0 },          -- Cyan (party/alliance)
    combat = { 0.92, 0.92, 0.92, 1.0 },        -- Light gray (matches SimpleLog combat output)
    combat_loot_gain = { 0.4, 1.0, 0.4, 1.0 }, -- Green (loot, gil, EXP/LP/CP gains in combat log)
    combat_player_item = { 0.4, 1.0, 0.4, 1.0 },   -- Green (player item use)
    combat_player_action = { 1.0, 1.0, 0.4, 1.0 }, -- Yellow (player abilities/spells)
    combat_enemy_action = { 1.0, 0.4, 0.4, 1.0 },  -- Red (enemy abilities/spells)
    tell = { 0.95, 0.45, 1.0, 1.0 },          -- Purple (tells)
    say = { 1.0, 1.0, 1.0, 1.0 },              -- White (Say tab)
    crafting_helm = { 0.78, 1.0, 0.78, 1.0 },  -- Light green (crafting / HELM)
    crafting_helm_loss = { 1.0, 0.35, 0.35, 1.0 }, -- Red for break / loss results
    server = { 1.0, 1.0, 1.0, 1.0 },           -- White (server messages)
    yells = { 1.0, 0.52, 0.45, 1.0 },          -- Red (yell)
    shout = { 1.0, 0.36, 0.20, 1.0 },          -- Orange-red (shout)
    emote = { 0.95, 0.45, 1.0, 1.0 },          -- Purple (emotes in Yells tab)
    autotranslate_open = { 0.25, 1.0, 0.25, 1.0 },   -- Green '{'
    autotranslate_close = { 1.0, 0.25, 0.25, 1.0 },  -- Red '}'
}

-- Tabs that are always present on load, even before any messages arrive
-- Order: All, LS1, LS2, Party, Say, Yells/Shouts, Crafting/HELM, Server, then Combat Log at the end
config.default_tabs = {
    { canonical = config.tabs.all, display = 'All' },
    { canonical = config.tabs.linkshell1, display = 'LS 1' },
    { canonical = config.tabs.linkshell2, display = 'LS 2' },
    { canonical = config.tabs.party, display = 'Party' },
    { canonical = config.tabs.say, display = 'Say' },
    { canonical = config.tabs.yells, display = 'Yells/Shouts' },
    { canonical = config.tabs.crafting_helm, display = 'Crafting/HELM' },
    { canonical = config.tabs.server, display = 'Server' },
    { canonical = config.tabs.combat, display = 'Combat Log' },
}

return config
