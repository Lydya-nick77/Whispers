local bit = require('bit')

local presence = {}

function presence.create(normalize_name, trim)
    local player_spawn_flags = {
        [1] = true,    -- other player
        [9] = true,    -- in alliance
        [13] = true,   -- in party
        [525] = true,  -- self
    }

    local player_entity_types = {
        [1] = true,
    }

    local spawn_flag_player_mask = 0x01

    local visible_player_cache = {}
    local visible_non_player_cache = {}
    local visible_player_cache_expires = 0

    local function classify_entity(name, spawn_flags, entity_type, members, non_players)
        local canonical = normalize_name(trim(name or ''))
        if canonical == '' then
            return
        end

        local is_player = player_spawn_flags[spawn_flags]
            or player_entity_types[entity_type]
            or bit.band(spawn_flags, spawn_flag_player_mask) == spawn_flag_player_mask

        if is_player then
            members[canonical] = true
        else
            non_players[canonical] = true
        end
    end

    local function scan_entities(members, non_players)
        if type(GetEntity) == 'function' then
            for i = 0, 1023 do
                local entity = GetEntity(i)
                if entity ~= nil then
                    classify_entity(
                        entity.Name,
                        tonumber(entity.SpawnFlags or -1) or -1,
                        tonumber(entity.EntityType or entity.Type or -1) or -1,
                        members,
                        non_players
                    )
                end
            end
            return
        end

        local manager = AshitaCore and AshitaCore:GetMemoryManager() or nil
        local entity = manager and manager:GetEntity() or nil
        if entity == nil then
            return
        end

        for i = 0, 1023 do
            classify_entity(
                entity:GetName(i),
                tonumber(entity:GetSpawnFlags(i) or -1) or -1,
                tonumber(entity:GetType(i) or -1) or -1,
                members,
                non_players
            )
        end
    end

    local function get_local_player_name()
        local manager = AshitaCore and AshitaCore:GetMemoryManager() or nil
        local party = manager and manager:GetParty() or nil
        if party == nil then
            return nil
        end

        local name = party:GetMemberName(0)
        if name == nil or name == '' then
            return nil
        end

        return trim(name)
    end

    local function get_party_member_canonicals()
        local members = {}
        local manager = AshitaCore and AshitaCore:GetMemoryManager() or nil
        local party = manager and manager:GetParty() or nil
        if party == nil then
            return members
        end

        for i = 0, 17 do
            local member_name = party:GetMemberName(i)
            if member_name ~= nil and member_name ~= '' then
                local canonical = normalize_name(trim(member_name))
                if canonical ~= '' then
                    members[canonical] = true
                end
            end
        end

        return members
    end

    local function get_visible_player_canonicals()
        local now = os.clock()
        if now < visible_player_cache_expires then
            return visible_player_cache
        end

        local members = {}
        local non_players = {}
        scan_entities(members, non_players)

        visible_player_cache = members
        visible_non_player_cache = non_players
        visible_player_cache_expires = now + 1.0

        return visible_player_cache
    end

    local function get_visible_non_player_canonicals()
        get_visible_player_canonicals()
        return visible_non_player_cache
    end

    return {
        get_local_player_name = get_local_player_name,
        get_party_member_canonicals = get_party_member_canonicals,
        get_visible_player_canonicals = get_visible_player_canonicals,
        get_visible_non_player_canonicals = get_visible_non_player_canonicals,
    }
end

return presence
