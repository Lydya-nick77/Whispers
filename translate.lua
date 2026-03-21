--[[
* translate.lua
*
* Builds a comprehensive list of auto-translate expressions using Ashita's
* ResourceManager data available on the local client.
*
* Usage (from another addon file):
*   local translate = require('translate')
*   local entries = translate.build()                 -- table of { text, source }
*   local list = translate.list()                     -- table of plain strings
*   local ok, count, path = translate.save()          -- writes to data/auto_translate_expressions.txt
]]--

require('common')

local translate = {}

local DEFAULT_STRING_TABLES = T{
    -- Core names.
    'abilities.names',
    'spells.names',

    -- DAT map string tables.
    'action.messages',
    'augments',
    'buffs.names',
    'commands.help',
    'days',
    'directions',
    'emotes',
    'equipment.slots',
    'equipment.slots_old',
    'jobpoints',
    'jobpoints.gifts',
    'jobs.names',
    'jobs.names_abbr',
    'keyitems.names',
    'keyitems.names_plural',
    'keyitems.descriptions',
    'merits',
    'monsters.abilities',
    'monsters.groups',
    'monsters.groups_plural',
    'moonphases',
    'mounts.names',
    'mounts.descriptions',
    'races',
    'regions',
    'titles',
    'weather',
    'weather.effects',
    'zones.names',
    'zones.names_abbr',
    'zones.names_search',

    -- Common guesses for custom/older maps; harmless if absent.
    'autotranslate',
    'autotranslates',
    'words',
    'words.general',
    'words.phrases',
    'phrases',
    'sentences',
}

local function normalize_text(value)
    if type(value) ~= 'string' then
        return nil
    end

    local s = value
        :gsub('[' .. string.char(0x00) .. '-' .. string.char(0x1F) .. ']', '')
        :gsub('%s+', ' ')
        :match('^%s*(.-)%s*$')

    if not s or s == '' then
        return nil
    end

    return s
end

local function add_entry(out, seen, text, source)
    local s = normalize_text(text)
    if not s then
        return
    end

    local key = s:lower()
    if seen[key] then
        return
    end

    seen[key] = true
    table.insert(out, { text = s, source = source })
end

local function collect_string_table(res, table_name, max_index, out, seen)
    local found_any = false
    local empty_run = 0

    for i = 0, max_index do
        local ok, value = pcall(res.GetString, res, table_name, i)
        if ok and type(value) == 'string' then
            local normalized = normalize_text(value)
            if normalized then
                add_entry(out, seen, normalized, 'str:' .. table_name)
                found_any = true
                empty_run = 0
            else
                empty_run = empty_run + 1
            end
        else
            empty_run = empty_run + 1
        end

        -- Once a table starts yielding values, stop after a long empty stretch.
        if found_any and empty_run > 512 then
            break
        end
    end
end

local function collect_items(res, max_index, out, seen)
    for i = 0, max_index do
        local ok, item = pcall(res.GetItemById, res, i)
        if ok and item ~= nil and type(item.Name) == 'table' then
            add_entry(out, seen, item.Name[1], 'item:' .. tostring(i))
        end
    end
end

local function collect_abilities(res, max_index, out, seen)
    for i = 0, max_index do
        local ok, ability = pcall(res.GetAbilityById, res, i)
        if ok and ability ~= nil and type(ability.Name) == 'table' then
            add_entry(out, seen, ability.Name[1], 'ability:' .. tostring(i))
        end
    end
end

local function collect_spells(res, max_index, out, seen)
    for i = 0, max_index do
        local ok, spell = pcall(res.GetSpellById, res, i)
        if ok and spell ~= nil and type(spell.Name) == 'table' then
            add_entry(out, seen, spell.Name[1], 'spell:' .. tostring(i))
        end
    end
end

local function collect_status_icons(res, max_index, out, seen)
    for i = 0, max_index do
        local ok, icon = pcall(res.GetStatusIconByIndex, res, i)
        if ok and icon ~= nil and type(icon.Description) == 'table' then
            add_entry(out, seen, icon.Description[1], 'status:' .. tostring(i))
        end
    end
end

local function sort_entries(entries)
    table.sort(entries, function(a, b)
        if a.text == b.text then
            return a.source < b.source
        end
        return a.text:lower() < b.text:lower()
    end)
end

function translate.build(options)
    options = options or {}

    local res = AshitaCore and AshitaCore:GetResourceManager() or nil
    if res == nil then
        return T{}
    end

    local out = T{}
    local seen = {}

    local string_tables = options.string_tables or DEFAULT_STRING_TABLES
    local string_max_index = tonumber(options.string_max_index or 65535) or 65535

    for _, tbl in ipairs(string_tables) do
        collect_string_table(res, tbl, string_max_index, out, seen)
    end

    if options.include_items ~= false then
        collect_items(res, tonumber(options.item_max_index or 65535) or 65535, out, seen)
    end
    if options.include_abilities ~= false then
        collect_abilities(res, tonumber(options.ability_max_index or 4095) or 4095, out, seen)
    end
    if options.include_spells ~= false then
        collect_spells(res, tonumber(options.spell_max_index or 4095) or 4095, out, seen)
    end
    if options.include_status_icons ~= false then
        collect_status_icons(res, tonumber(options.status_icon_max_index or 4095) or 4095, out, seen)
    end

    sort_entries(out)
    return out
end

function translate.list(options)
    local entries = translate.build(options)
    local lines = T{}

    for _, entry in ipairs(entries) do
        table.insert(lines, entry.text)
    end

    return lines
end

function translate.save(path, options)
    local target = path or (addon.path .. 'data/auto_translate_expressions.txt')

    local dir = target:match('^(.*)[/\\]')
    if dir and dir ~= '' then
        os.execute(string.format('if not exist "%s" mkdir "%s"', dir, dir))
    end

    local entries = translate.build(options)
    local f = io.open(target, 'w')
    if not f then
        return false, 0, target
    end

    f:write('# FFXI auto-translate expression list (resource-derived)\n')
    f:write('# Generated by whispers/translate.lua\n\n')

    for _, entry in ipairs(entries) do
        f:write(string.format('[%s] %s\n', entry.source, entry.text))
    end

    f:close()
    return true, #entries, target
end

return translate
