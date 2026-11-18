---Parse un objet JSON plat de type {"Tag 1":true,"Tag 2":false} en table Lua
---@param raw_json string
---@return table<string, boolean>
local function ParseTagsJson(raw_json)
    local tags = {}
    if not raw_json or raw_json == "" then
        return tags
    end

    for key, val in raw_json:gmatch('"([^"]+)"%s*:%s*(%a+)') do
        if val == "true" then
            tags[key] = true
        elseif val == "false" then
            tags[key] = false
        end
    end

    return tags
end

---Applique l'état (actif/inactif) d'un bloc d'actions tout en préservant les accolades {...}
---@param inner_content string
---@param is_active boolean
---@return string
local function FormatTagBlock(inner_content, is_active)
    -- 1. Protéger les blocs entre accolades {...}
    local braces = {}
    local protected = inner_content:gsub("(%b{})", function(block)
        table.insert(braces, block)
        return "___BRACE_" .. #braces .. "___"
    end)

    -- 2. Nettoyer les séparateurs existants hors accolades (espaces ou "|")
    protected = protected:gsub("|", " ")
    local tokens = {}
    for token in protected:gmatch("%S+") do
        table.insert(tokens, token)
    end

    -- 3. Reconstruire selon l'état demandé
    local result = ""
    if is_active then
        if #tokens > 0 then
            result = " " .. table.concat(tokens, " ") .. " "
        end
    else
        result = table.concat(tokens, "|")
    end

    -- 4. Restaurer les blocs entre accolades {...} intacts
    result = result:gsub("___BRACE_(%d+)___", function(idx)
        return braces[tonumber(idx)] or ""
    end)

    return result
end

---Met à jour les marqueurs taggués du projet actif selon les chunks JSON reçus
---@param tag_chunks string[]
local function SetSongMarkerTags(tag_chunks)
    if not tag_chunks or type(tag_chunks) ~= "table" then
        return
    end

    local raw_json = table.concat(tag_chunks)
    local tags = ParseTagsJson(raw_json)

    local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
    local total = num_markers + num_regions

    for i = 0, total - 1 do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber, color = reaper.EnumProjectMarkers3(0, i)
        if retval > 0 and not isrgn and name then
            local changed = false
            local new_name = name:gsub("%[([^%]]+)%]%(([^%)]*)%)", function(tag_name, inner_content)
                local trimmed_name = tag_name:match("^%s*(.-)%s*$")
                if tags[trimmed_name] ~= nil then
                    changed = true
                    local formatted = FormatTagBlock(inner_content, tags[trimmed_name])
                    return "[" .. tag_name .. "](" .. formatted .. ")"
                end
                return "[" .. tag_name .. "](" .. inner_content .. ")"
            end)

            if changed and new_name ~= name then
                reaper.SetProjectMarkerByIndex2(0, i, isrgn, pos, rgnend, markrgnindexnumber, new_name, color, 0)
            end
        end
    end
end

return SetSongMarkerTags
