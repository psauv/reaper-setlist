---Déplace un onglet de projet de from_index vers to_index via les actions natives REAPER
---@param from_index_str string
---@param to_index_str string
local function MoveProjectTab(from_index_str, to_index_str)
    local from_idx = tonumber(from_index_str)
    local to_idx = tonumber(to_index_str)

    if from_idx == nil or to_idx == nil or from_idx == to_idx then
        return
    end

    local target_proj = reaper.EnumProjects(from_idx)
    if not target_proj then
        return
    end

    local original_proj = reaper.EnumProjects(-1)
    reaper.SelectProjectInstance(target_proj)

    local diff = to_idx - from_idx
    if diff > 0 then
        -- 3243 = Project tabs: Move project tab right by one
        for _ = 1, diff do
            reaper.Main_OnCommand(3243, 0)
        end
    else
        -- 3242 = Project tabs: Move project tab left by one
        for _ = 1, -diff do
            reaper.Main_OnCommand(3242, 0)
        end
    end

    -- Restaurer l'onglet actif d'origine
    if original_proj then
        reaper.SelectProjectInstance(original_proj)
    end
end

return MoveProjectTab
