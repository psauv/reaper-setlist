local NormalizePath = require "normalize_path"

---Resolves a path to an absolute path (if relative, resolves against base_path or REAPER resource path).
---@param path string
---@param base_path? string
---@return string
local function GetAbsolutePath(path, base_path)
    if not path or path == "" then
        return path
    end

    local normalized = NormalizePath(path)

    -- If path does not start with "/" (Unix/macOS) or "C:/" (Windows), treat as relative
    if not normalized:match("^/") and not normalized:match("^%a:/") then
        local base = NormalizePath(base_path or reaper.GetResourcePath()):gsub("/$", "")
        for part in normalized:gmatch("[^/]+") do
            if part == ".." then
                base = base:match("(.+)/[^/]+$") or base
            elseif part ~= "." then
                base = base .. "/" .. part
            end
        end
        return base
    end

    return normalized
end

return GetAbsolutePath
