-- installer.lua
-- Run this once on a fresh CC:Tweaked computer to install CCOS

local BASE = "https://github.com/xwaiszn/UltraOS-minecraft"

local FILES = {
    "startup.lua",
    "system/kernel.lua",
    "system/ui.lua",
    "system/app_loader.lua",
    "system/theme.lua",
    "apps/filemanager.lua",
    "apps/notes.lua",
    "apps/calculator.lua",
    "apps/snake.lua",
    "apps/pong.lua",
    "apps/miner.lua",
    "apps/downloader.lua",
    "apps/appstore.lua",
}

local function download(path)
    local url = BASE .. "/" .. path
    print("Downloading: " .. path)
    local ok, res = pcall(http.get, url)
    if not ok or not res then
        print("  FAILED: " .. path)
        return false
    end
    local content = res.readAll()
    res.close()
    if not content or #content == 0 then
        print("  EMPTY: " .. path)
        return false
    end
    -- Create parent directories
    local dir = path:match("^(.*)/[^/]+$")
    if dir and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local f = fs.open(path, "w")
    if not f then print("  WRITE FAILED: " .. path) ; return false end
    f.write(content)
    f.close()
    return true
end

local failed = 0
for _, path in ipairs(FILES) do
    if not download(path) then failed = failed + 1 end
end

if failed == 0 then
    print("")
    print("CCOS installed! Rebooting...")
    os.sleep(1)
    os.reboot()
else
    print("")
    print(failed .. " file(s) failed. Check your internet settings.")
end