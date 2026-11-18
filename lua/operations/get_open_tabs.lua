---@param proj ReaProject
---@return table<string, boolean>
local function ExtractTagsFromProject(proj)
    local tags = {}
    local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)
    local total = num_markers + num_regions

    for i = 0, total - 1 do
        local retval, isrgn, _, _, name = reaper.EnumProjectMarkers3(proj, i)
        if retval > 0 and not isrgn and name then
            for tag_name, inner_content in name:gmatch("%[([^%]]+)%]%(([^%)]*)%)") do
                local trimmed = tag_name:match("^%s*(.-)%s*$")
                local outside_braces = inner_content:gsub("(%b{})", "PLACEHOLDER"):match("^%s*(.-)%s*$")
                local is_active = (#outside_braces > 0) and (outside_braces:match("%s") ~= nil)
                tags[trimmed] = is_active
            end
        end
    end
    return tags
end

---@return ReaperTab[]
---@return number active_index
local GetOpenTabs = function()
    ---@type ReaperTab[]
    local tabs = {}
    local tab_index = 0

    local active_project = reaper.EnumProjects(-1)
    local active_project_index = -1

    while true do
        local proj = reaper.EnumProjects(tab_index)
        if proj == nil then
            break
        end

        local tab_name = reaper.GetProjectName(proj)
        if not tab_name or tab_name == "" then
            break
        end

        local duration = reaper.GetProjectLength(proj)
        local normalized_tab_name = tab_name:gsub("\\", "/")
        local is_dirty = reaper.IsProjectDirty(proj) == 1
        local is_active = (proj == active_project)
        if is_active then
            active_project_index = tab_index
        end

        ---@type ReaperTab
        local tab = {
            index = tab_index,
            name = normalized_tab_name,
            dirty = is_dirty,
            length = duration,
            tags = ExtractTagsFromProject(proj)
        }

        table.insert(tabs, tab)
        tab_index = tab_index + 1
    end

    return tabs, active_project_index
end

return GetOpenTabs
