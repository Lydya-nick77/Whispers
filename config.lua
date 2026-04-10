-- Whispers addon configuration
local config = {}

-- Default window dimensions and position (persisted via the settings module)
config.default_window = {
    width  = 500,
    height = 220,
    x      = 100,
    y      = 100,
}

-- Global font scale for the Whispers window. 1.0 = default size.
config.font_scale = 1.0

-- Font scale applied to chat messages only (tabs and buttons are unaffected). 1.0 = default size.
config.message_font_scale = 1.1

-- UI behavior and rendering constants.
config.ui = {
    min_font_scale = 0.5,
    input_max_length = 119,
    bold_offset_x = 0.8,
    scroll_to_bottom_fraction = 1.0,  -- 0.0 = top, 1.0 = bottom; fraction to jump to on new messages
    chat_layout = {
        min_chat_height = 1,
        read_only_footer_padding = 4,
        input_row_padding = 4,
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
    },
    name_colon_pattern = '^([%a][%w_%-]+)%s*:%s*(.*)$',
    leading_timestamp_pattern = '^%s*[%[%{<]?%d%d:%d%d:?%d?%d?[%]%}>]?%s*',
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
    say = 'say',
    read_only = { all = true },
}

config.packets = {
    examine = {
        incoming_id = 0x0009,
        message_offset = 0x0A + 1,
        message_id = 89,
        route_tab = config.tabs.say,
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
        [config.tabs.linkshell1] = true,
        [config.tabs.linkshell2] = true,
        [config.tabs.party] = true,
        [config.tabs.say] = true,
    },
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

-- Window styling (XIDB-matched: dark background with gold accents)
config.style = {
    -- Window behavior flags
    no_title_bar                   = true,   -- Hide the title bar completely
    no_collapse                    = true,   -- Disable the collapse arrow (only relevant when no_title_bar is false)
    no_close_tab_with_middle_mouse = true,   -- Prevent closing tabs by middle-clicking

    -- Shape rounding (matches XIDB chrome)
    window_rounding    = 6.0,   -- Corner radius for the main window
    window_border_size = 1.0,   -- Border thickness
    tab_rounding       = 4.0,   -- Corner radius for tabs
    frame_rounding     = 4.0,   -- Corner radius for input fields
    frame_border_size  = 1.0,   -- Border for input fields
    scrollbar_rounding = 4.0,   -- Corner radius for scrollbar thumb
    scrollbar_size     = 8.0,   -- Scrollbar width in pixels (default is 14)

    -- Color theme: RGBA tables {r, g, b, a} each in 0.0–1.0 range.
    -- Set any value to nil to inherit the default ImGui color.
    theme = {
        -- Window chrome
        window_bg          = { 0.00, 0.00, 0.00, 0.95 },  -- Near-opaque black (XIDB bg_dark)
        title_bg           = { 0.098, 0.090, 0.075, 1.00 },  -- XIDB bg_medium
        title_bg_active    = { 0.137, 0.125, 0.106, 1.00 },  -- XIDB bg_light
        title_bg_collapsed = { 0.00,  0.00,  0.00,  1.00 },  -- XIDB bg_dark
        border             = { 0.765, 0.684, 0.474, 0.85 },  -- XIDB border_gold

        -- Tab bar
        tab                = { 0.098, 0.090, 0.075, 1.00 },  -- XIDB bg_medium
        tab_hovered        = { 0.137, 0.125, 0.106, 1.00 },  -- XIDB bg_light
        tab_active         = { 0.957, 0.855, 0.592, 0.30 },  -- XIDB gold at 30% alpha

        -- Chat child panel
        child_bg           = { 0.00, 0.00, 0.00, 1.00 },  -- XIDB ChildBg (pure black)
        scrollbar_bg       = { 0.098, 0.090, 0.075, 1.00 },  -- XIDB bg_medium
        scrollbar_grab     = { 0.176, 0.161, 0.137, 1.00 },  -- XIDB bg_lighter
        scrollbar_grab_hov = { 0.30,  0.275, 0.235, 1.00 },  -- XIDB border_dark
        separator          = { 0.30,  0.275, 0.235, 1.00 },  -- XIDB border_dark

        -- Input field
        frame_bg           = { 0.125, 0.110, 0.086, 0.98 },  -- XIDB FrameBg
        frame_bg_hovered   = { 0.173, 0.153, 0.122, 0.98 },  -- XIDB FrameBgHovered
        frame_bg_active    = { 0.231, 0.200, 0.157, 0.98 },  -- XIDB FrameBgActive

        -- Buttons
        button             = { 0.176, 0.149, 0.106, 0.95 },  -- XIDB button_base
        button_hovered     = { 0.286, 0.239, 0.165, 0.95 },  -- XIDB button_hover
        button_active      = { 0.420, 0.353, 0.243, 0.95 },  -- XIDB button_active
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
}

-- Maps canonical (lowercase) tab names to their outgoing chat command prefix
config.tab_commands = {
    [config.tabs.say] = '/s',
    [config.tabs.party] = '/p',
    [config.tabs.linkshell1] = '/l',
    [config.tabs.linkshell2] = '/l2',
}

-- Text colors for chat tabs (RGBA, each component 0.0–1.0)
config.colors = {
    linkshell1 = { 0.86,  1.0,  0.76,  1.0 },  -- Yellow/green
    linkshell2 = { 0.35, 1.0,   0.35,  1.0 },  -- Light green
    party = { 0.20, 0.95, 1.0, 1.0 },          -- Cyan (party/alliance)
    tell = { 0.95, 0.45, 1.0, 1.0 },          -- Purple (tells)
    say = { 1.0, 1.0, 1.0, 1.0 },              -- White (Say tab)
    autotranslate_open = { 0.25, 1.0, 0.25, 1.0 },   -- Green '{'
    autotranslate_close = { 1.0, 0.25, 0.25, 1.0 },  -- Red '}'
}

-- Tabs that are always present on load, even before any messages arrive
config.default_tabs = {
    { canonical = config.tabs.all, display = 'All' },
    { canonical = config.tabs.linkshell1, display = 'LS 1' },
    { canonical = config.tabs.linkshell2, display = 'LS 2' },
    { canonical = config.tabs.party, display = 'Party' },
    { canonical = config.tabs.say, display = 'Say' },
}

return config
