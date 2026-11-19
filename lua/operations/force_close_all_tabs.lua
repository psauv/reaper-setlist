---Ferme tous les onglets ouverts sans sauvegarde ni popup
local function ForceCloseAllTabs()
    -- 1. Créer un fichier .rpp minimaliste temporaire
    local dummy_path = reaper.GetResourcePath() .. "/reaper_setlist_empty_tmp.rpp"
    local file = io.open(dummy_path, "w")
    if not file then
        error("Unable to create temporary empty project file at: " .. dummy_path)
    end
    file:write("<REAPER_PROJECT 0.1\n>\n")
    file:close()

    -- 2. Nettoyer uniquement les onglets modifiés (dirty)
    local tab_index = 0
    while true do
        local proj = reaper.EnumProjects(tab_index)
        if proj == nil then
            break
        end
        if reaper.IsProjectDirty(proj) == 1 then
            reaper.SelectProjectInstance(proj)
            reaper.Main_openProject("noprompt:" .. dummy_path)
        end
        tab_index = tab_index + 1
    end

    -- 3. Fermer tous les onglets d'un coup (tous devenus propres) et supprimer le fichier temporaire
    reaper.Main_OnCommand(40886, 0) -- File: Close all projects
    os.remove(dummy_path)
end

return ForceCloseAllTabs
