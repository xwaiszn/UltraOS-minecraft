-- /system/app_loader.lua
-- CCOS App Loader: discovers apps on disk and validates their interface.

local appLoader = {}
local _kernel   = nil

function appLoader.init(kernel)
    _kernel = kernel
end

-- Returns a list of { name, path } for every .lua file in /apps/
function appLoader.listApps()
    local apps = {}
    if not fs.exists(_kernel.PATHS.apps) then return apps end
    local files = fs.list(_kernel.PATHS.apps)
    table.sort(files)
    for _, fname in ipairs(files) do
        if fname:match("%.lua$") then
            local path = _kernel.PATHS.apps .. fname
            if not fs.isDir(path) then
                apps[#apps + 1] = {
                    name = fname:gsub("%.lua$", ""),
                    path = path,
                }
            end
        end
    end
    return apps
end

-- Attempt to load an app and verify it has required fields.
-- Returns ok, errorMessage
function appLoader.validate(appPath)
    if not fs.exists(appPath) then
        return false, "File not found: " .. appPath
    end
    local fn, err = loadfile(appPath)
    if not fn then return false, "Parse error: " .. tostring(err) end
    local ok, mod = pcall(fn)
    if not ok then return false, "Runtime error: " .. tostring(mod) end
    if type(mod) ~= "table" then return false, "App must return a table" end
    if type(mod.name) ~= "string" then return false, "App missing .name string" end
    if type(mod.draw) ~= "function" then return false, "App missing .draw() function" end
    if type(mod.event) ~= "function" then return false, "App missing .event() function" end
    return true
end

-- Installs an app by writing its source to /apps/<name>.lua
-- source: string containing Lua source code
-- name:   filename without extension
function appLoader.install(name, source)
    local path = _kernel.PATHS.apps .. name .. ".lua"
    local f = fs.open(path, "w")
    if not f then return false, "Cannot write to " .. path end
    f.write(source)
    f.close()
    return true
end

function appLoader.uninstall(name)
    local path = _kernel.PATHS.apps .. name .. ".lua"
    if fs.exists(path) then
        fs.delete(path)
        return true
    end
    return false, "App not found"
end

return appLoader
