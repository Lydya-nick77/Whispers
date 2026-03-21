-- Whispers - ImGui styling helpers
-- Reads config.style and exposes push/pop/flags helpers so the main
-- render loop stays free of ImGui style mechanics.
local imgui = require('imgui')
local bit   = require('bit')

local decoration = {}

-- Pushes all style vars and colors defined in config.style onto the ImGui stack.
-- Returns (var_count, color_count) so the caller can pop them later with decoration.pop().
function decoration.push(style)
    local theme       = style.theme or {}
    local var_count   = 0
    local color_count = 0
    local function push_var(var, val) imgui.PushStyleVar(var, val);   var_count   = var_count   + 1 end
    local function push_clr(col, val) imgui.PushStyleColor(col, val); color_count = color_count + 1 end

    -- Shape / layout vars
    push_var(ImGuiStyleVar_WindowRounding,    style.window_rounding    or 8.0)
    push_var(ImGuiStyleVar_WindowBorderSize,  style.window_border_size or 1.0)
    push_var(ImGuiStyleVar_TabRounding,       style.tab_rounding       or 4.0)
    push_var(ImGuiStyleVar_FrameRounding,     style.frame_rounding     or 4.0)
    push_var(ImGuiStyleVar_FrameBorderSize,   style.frame_border_size  or 0.0)
    push_var(ImGuiStyleVar_ScrollbarRounding, style.scrollbar_rounding or 4.0)
    push_var(ImGuiStyleVar_ScrollbarSize,     style.scrollbar_size     or 14.0)

    -- Window chrome
    push_clr(ImGuiCol_WindowBg,             theme.window_bg          or {0,0,0,0.9})
    push_clr(ImGuiCol_TitleBg,              theme.title_bg           or {0,0,0,1})
    push_clr(ImGuiCol_TitleBgActive,        theme.title_bg_active    or {0,0,0,1})
    push_clr(ImGuiCol_TitleBgCollapsed,     theme.title_bg_collapsed or {0,0,0,0.9})
    push_clr(ImGuiCol_Border,               theme.border             or {0.4,0.4,0.4,0.5})

    -- Tab bar
    push_clr(ImGuiCol_Tab,                  theme.tab                or {0,0,0,0.8})
    push_clr(ImGuiCol_TabHovered,           theme.tab_hovered        or {0.2,0.2,0.4,1})
    push_clr(ImGuiCol_TabActive,            theme.tab_active         or {0.2,0.25,0.45,1})

    -- Chat child panel
    push_clr(ImGuiCol_ChildBg,              theme.child_bg           or {0,0,0,0.5})
    push_clr(ImGuiCol_ScrollbarBg,          theme.scrollbar_bg       or {0,0,0,0.4})
    push_clr(ImGuiCol_ScrollbarGrab,        theme.scrollbar_grab     or {0.2,0.2,0.4,0.8})
    push_clr(ImGuiCol_ScrollbarGrabHovered, theme.scrollbar_grab_hov or {0.3,0.3,0.5,0.9})
    push_clr(ImGuiCol_Separator,            theme.separator          or {0.3,0.3,0.5,0.6})

    -- Input field
    push_clr(ImGuiCol_FrameBg,              theme.frame_bg           or {0.1,0.1,0.2,0.7})
    push_clr(ImGuiCol_FrameBgHovered,       theme.frame_bg_hovered   or {0.15,0.15,0.3,0.9})
    push_clr(ImGuiCol_FrameBgActive,        theme.frame_bg_active    or {0.2,0.2,0.35,1})

    -- Buttons
    push_clr(ImGuiCol_Button,               theme.button             or {0.1,0.1,0.2,1})
    push_clr(ImGuiCol_ButtonHovered,        theme.button_hovered     or {0.2,0.2,0.38,1})
    push_clr(ImGuiCol_ButtonActive,         theme.button_active      or {0.28,0.3,0.5,1})

    return var_count, color_count
end

-- Pops the exact number of style entries pushed by decoration.push().
function decoration.pop(var_count, color_count)
    imgui.PopStyleColor(color_count)
    imgui.PopStyleVar(var_count)
end

-- Returns the ImGuiWindowFlags bitmask for the main window based on config.style.
function decoration.window_flags(style)
    local flags = ImGuiWindowFlags_None
    if style.no_title_bar then flags = bit.bor(flags, ImGuiWindowFlags_NoTitleBar) end
    if style.no_collapse   then flags = bit.bor(flags, ImGuiWindowFlags_NoCollapse) end
    return flags
end

-- Returns the ImGuiTabBarFlags bitmask for the tab bar based on config.style.
function decoration.tab_bar_flags(style)
    local flags = ImGuiTabBarFlags_None
    if style.no_close_tab_with_middle_mouse then
        flags = bit.bor(flags, ImGuiTabBarFlags_NoCloseWithMiddleMouseButton)
    end
    return flags
end

return decoration
