-- /system/kernel.lua
-- CCOS Kernel: manages the event loop, loaded app, and system API.

local kernel = {}

-- ── Version ────────────────────────────────────────────────────────────────
kernel.VERSION = "1.0.0"

-- ── Screen geometry ────────────────────────────────────────────────────────
local W, H = term.getSize()
kernel.W = W
kernel.H = H

-- ── Runtime state ──────────────────────────────────────────────────────────
local _currentApp   = nil   -- table returned by an app module
local _needRedraw   = true  -- flag: UI must re-render this tick
local _running      = true

-- ── System paths ───────────────────────────────────────────────────────────
kernel.PATHS = {
    system   = "/system/",
    apps     = "/apps/",
    data     = "/data/",
    notes    = "/data/notes/",
}

-- Ensure critical directories exist
for _, path in pairs(kernel.PATHS) do
    if not fs.exists(path) then fs.makeDir(path) end
end

-- ── Logging ────────────────────────────────────────────────────────────────
local _logFile = "/data/kernel.log"
function kernel.log(msg)
    local f = fs.open(_logFile, "a")
    if f then
        f.writeLine("[" .. os.time() .. "] " .. tostring(msg))
        f.close()
    end
end

-- ── Module loader ──────────────────────────────────────────────────────────
-- Loads a Lua file and returns its exported table.
-- The file must end with:  return <table>
local _moduleCache = {}
function kernel.require(path)
    if _moduleCache[path] then return _moduleCache[path] end
    if not fs.exists(path) then
        error("kernel.require: file not found: " .. path)
    end
    local fn, err = loadfile(path)
    if not fn then error("kernel.require: " .. tostring(err)) end
    local result = fn()
    _moduleCache[path] = result
    return result
end

-- ── App lifecycle ──────────────────────────────────────────────────────────
-- An app module must expose:
--   app.name    (string)
--   app.init()  called once when launched
--   app.draw()  called to render; must not yield
--   app.event(ev, ...)  called with each event; return true to keep running
--   app.unload()  called before switching away (optional)

function kernel.launchApp(appPath)
    if _currentApp and _currentApp.unload then
        pcall(_currentApp.unload)
    end
    _moduleCache[appPath] = nil          -- force re-load for fresh state
    local ok, mod = pcall(kernel.require, appPath)
    if not ok then
        kernel.log("Failed to load app: " .. appPath .. " | " .. tostring(mod))
        return false, tostring(mod)
    end
    if type(mod) ~= "table" then
        return false, "App did not return a table"
    end
    _currentApp = mod
    if _currentApp.init then
        local ok2, err2 = pcall(_currentApp.init)
        if not ok2 then
            kernel.log("App init error: " .. tostring(err2))
            _currentApp = nil
            return false, err2
        end
    end
    _needRedraw = true
    return true
end

function kernel.returnToDesktop()
    if _currentApp and _currentApp.unload then
        pcall(_currentApp.unload)
    end
    _currentApp = nil
    _moduleCache["/system/ui.lua"] = nil   -- force desktop redraw
    _needRedraw = true
end

function kernel.requestRedraw()
    _needRedraw = true
end

-- ── Shutdown ────────────────────────────────────────────────────────────────
function kernel.shutdown()
    _running = false
end

-- ── Main event loop ─────────────────────────────────────────────────────────
local function boot()
    kernel.log("CCOS " .. kernel.VERSION .. " booting")

    -- Load subsystems
    local ui        = kernel.require("/system/ui.lua")
    local appLoader = kernel.require("/system/app_loader.lua")

    ui.init(kernel)
    appLoader.init(kernel)

    -- Initial draw
    ui.drawDesktop()

    -- ── Event loop ──────────────────────────────────────────────────────────
    while _running do
        local ev = { os.pullEvent() }
        local evName = ev[1]

        -- Give the event to the active app first
        if _currentApp then
            local ok, keepRunning = pcall(_currentApp.event, table.unpack(ev))
            if not ok then
                kernel.log("App event error: " .. tostring(keepRunning))
                kernel.returnToDesktop()
            elseif keepRunning == false then
                kernel.returnToDesktop()
            end
        else
            -- No app open: desktop handles events
            ui.handleEvent(table.unpack(ev))
        end

        -- Render pass
        if _needRedraw then
            _needRedraw = false
            if _currentApp and _currentApp.draw then
                pcall(_currentApp.draw)
            else
                ui.drawDesktop()
            end
        end
    end

    -- Cleanup
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    print("CCOS has shut down.")
end

boot()
