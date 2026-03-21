local tabs = {}

function tabs.create(config, tab_cfg, normalize_name, trim)
    local fixed_channel_tabs = {}
    local linkshell_tabs = {}
    local default_tab_displays = {}
    local read_only_tabs = {}
    local all_tab = normalize_name(tab_cfg.all or 'all')
    local linkshell1_tab = normalize_name(tab_cfg.linkshell1 or 'linkshell 1')
    local linkshell2_tab = normalize_name(tab_cfg.linkshell2 or 'linkshell 2')
    local party_tab = normalize_name(tab_cfg.party or 'party')
    local say_tab = normalize_name(tab_cfg.say or 'say')
    local combat_tab = normalize_name(tab_cfg.combat or 'combat log')
    local yells_tab = normalize_name(tab_cfg.yells or 'yells')
    local crafting_helm_tab = normalize_name(tab_cfg.crafting_helm or 'crafting/helm')
    local server_tab = normalize_name(tab_cfg.server or 'server')

    for _, tab in ipairs(config.default_tabs) do
        local canonical = normalize_name(tab.canonical)
        fixed_channel_tabs[canonical] = true
        default_tab_displays[canonical] = tab.display
    end

    for canonical, enabled in pairs(tab_cfg.read_only or {}) do
        if enabled then
            read_only_tabs[normalize_name(canonical)] = true
        end
    end

    linkshell_tabs[linkshell1_tab] = true
    linkshell_tabs[linkshell2_tab] = true

    local linkshell1_info = {
        tab = linkshell1_tab,
    }
    local linkshell2_info = {
        tab = linkshell2_tab,
    }

    local function infer_linkshell_tab_info(text_value)
        if not text_value then
            return nil, text_value
        end

        local t = trim(text_value)
        local idx = t:match('^%[(%d)%]%s*')
        if idx == '1' then
            t = t:gsub('^%[1%]%s*', '', 1)
            return linkshell1_info, t
        elseif idx == '2' then
            t = t:gsub('^%[2%]%s*', '', 1)
            return linkshell2_info, t
        end

        return nil, text_value
    end

    local function get_tab_display_name(canonical, display_names)
        local normalized = normalize_name(canonical)
        if normalized == '' then
            return canonical
        end

        return default_tab_displays[normalized] or display_names[normalized] or canonical
    end

    return {
        all_tab = all_tab,
        linkshell1_tab = linkshell1_tab,
        linkshell2_tab = linkshell2_tab,
        party_tab = party_tab,
        say_tab = say_tab,
        combat_tab = combat_tab,
        yells_tab = yells_tab,
        crafting_helm_tab = crafting_helm_tab,
        server_tab = server_tab,
        is_fixed_channel_tab = function(name)
            return fixed_channel_tabs[name] == true
        end,
        is_linkshell_tab = function(name)
            return linkshell_tabs[name] == true
        end,
        is_read_only_tab = function(name)
            return read_only_tabs[name] == true
        end,
        infer_linkshell_tab_info = infer_linkshell_tab_info,
        get_tab_display_name = get_tab_display_name,
    }
end

return tabs