-- /apps/appstore.lua
-- CCOS App Store: maintains a catalog of apps, installs them from pastebin/URLs,
-- and persists installed state to /data/appstore.json.

local T = dofile("/system/theme.lua")
local app = { name = "App Store" }

local W, H
local closeBtn_r

-- ── Persistence ───────────────────────────────────────────────────────────────
local STATE_FILE = "/data/appstore.json"

local function loadState()
    if not fs.exists(STATE_FILE) then return {} end
    local f = fs.open(STATE_FILE, "r")
    if not f then return {} end
    local raw = f.readAll() ; f.close()
    -- Minimal JSON parser for flat string→bool object
    local state = {}
    for key, val in raw:gmatch('"([^"]+)"%s*:%s*(true)') do
        state[key] = true
    end
    return state
end

local function saveState(state)
    local parts = {"{"}
    local first  = true
    for k, v in pairs(state) do
        if not first then parts[#parts+1] = "," end
        parts[#parts+1] = string.format('"%s":%s', k, tostring(v))
        first = false
    end
    parts[#parts+1] = "}"
    local f = fs.open(STATE_FILE, "w")
    if f then f.write(table.concat(parts)) ; f.close() end
end

-- ── Catalog ───────────────────────────────────────────────────────────────────
-- Apps in the catalog.  source can be:
--   { type="pastebin", code="XXXX" }   – fetched from pastebin
--   { type="url",      url="https://..." }
--   { type="builtin" }                 – already on disk; never re-installed
--
-- For a real deployment, replace codes/urls with actual content.
-- Builtins are the apps that ship with CCOS.

local CATALOG = {
    {
        id      = "filemanager",
        name    = "File Manager",
        author  = "CCOS",
        desc    = "Navigate, view, and delete files on disk.",
        version = "1.0",
        source  = { type = "builtin" },
    },
    {
        id      = "notes",
        name    = "Notes",
        author  = "CCOS",
        desc    = "Write and save plain-text notes.",
        version = "1.0",
        source  = { type = "builtin" },
    },
    {
        id      = "calculator",
        name    = "Calculator",
        author  = "CCOS",
        desc    = "Safe math expression evaluator.",
        version = "1.0",
        source  = { type = "builtin" },
    },
    {
        id      = "snake",
        name    = "Snake",
        author  = "CCOS",
        desc    = "Classic snake game.",
        version = "1.0",
        source  = { type = "builtin" },
    },
    {
        id      = "pong",
        name    = "Pong",
        author  = "CCOS",
        desc    = "Single-player vs AI pong.",
        version = "1.0",
        source  = { type = "builtin" },
    },
    {
        id      = "miner",
        name    = "Miner",
        author  = "CCOS",
        desc    = "Minesweeper-style game.",
        version = "1.0",
        source  = { type = "builtin" },
    },
    {
        id      = "downloader",
        name    = "Downloader",
        author  = "CCOS",
        desc    = "Download files from URLs or Pastebin.",
        version = "1.0",
        source  = { type = "builtin" },
    },
    -- Add community apps here with type="pastebin" or type="url"
    -- Example (replace XXXXXXXX with a real pastebin code):
    -- {
    --     id = "mypaint",
    --     name = "MiniPaint",
    --     author = "community",
    --     desc = "Pixel canvas painter.",
    --     version = "0.1",
    --     source = { type = "pastebin", code = "XXXXXXXX" },
    -- },
}

-- ── State ─────────────────────────────────────────────────────────────────────
local installed  = {}
local selected   = 1
local scroll     = 1
local statusMsg  = ""
local MODE       = "list"   -- "list" | "detail"
local actionBtns = {}
local listBtns   = {}

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function fetchSource(src)
    if src.type == "builtin" then
        return nil, "Built-in app; no download needed"
    end
    if not http then
        return nil, "HTTP disabled in CC config"
    end
    local url
    if src.type == "pastebin" then
        url = "https://pastebin.com/raw/" .. src.code
    elseif src.type == "url" then
        url = src.url
    else
        return nil, "Unknown source type"
    end
    local ok, resp = pcall(http.get, url)
    if not ok or not resp then
        return nil, "HTTP request failed"
    end
    local content = resp.readAll()
    resp.close()
    if not content or #content == 0 then
        return nil, "Empty response"
    end
    return content, nil
end

local function installApp(entry)
    if entry.source.type == "builtin" then
        installed[entry.id] = true
        saveState(installed)
        statusMsg = entry.name .. " marked as installed"
        return true
    end
    statusMsg = "Downloading " .. entry.name .. "..."
    local content, err = fetchSource(entry.source)
    if not content then
        statusMsg = "Install failed: " .. err
        return false
    end
    local path = "/apps/" .. entry.id .. ".lua"
    local f    = fs.open(path, "w")
    if not f then
        statusMsg = "Cannot write to " .. path
        return false
    end
    f.write(content)
    f.close()
    installed[entry.id] = true
    saveState(installed)
    statusMsg = entry.name .. " installed!"
    return true
end

local function uninstallApp(entry)
    if entry.source.type == "builtin" then
        statusMsg = "Cannot uninstall built-in app"
        return
    end
    local path = "/apps/" .. entry.id .. ".lua"
    if fs.exists(path) then fs.delete(path) end
    installed[entry.id] = nil
    saveState(installed)
    statusMsg = entry.name .. " removed"
end

local LIST_Y = 3
local function listH()
    return H - LIST_Y - 2
end

-- ── Draw ─────────────────────────────────────────────────────────────────────
local function drawTitleBar(subtitle)
    term.setBackgroundColor(T.titleBar)
    term.setTextColor(T.accent)
    term.setCursorPos(1, 1)
    term.write(string.rep(" ", W))
    term.setCursorPos(3, 1)
    term.write("App Store" .. (subtitle and ("  " .. subtitle) or ""))
    term.setBackgroundColor(T.danger)
    term.setTextColor(T.dangerText)
    term.setCursorPos(W - 1, 1)
    term.write(" X")
    closeBtn_r = { x = W - 1, y = 1, w = 2, h = 1 }
end

local function drawListMode()
    term.setBackgroundColor(T.panel)
    for row = 1, H do
        term.setCursorPos(1, row)
        term.write(string.rep(" ", W))
    end
    drawTitleBar(#CATALOG .. " apps")

    -- Column header
    term.setBackgroundColor(T.panel)
    term.setTextColor(T.dim)
    term.setCursorPos(1, 2)
    local hdr = string.format("  %-20s %-8s %s", "Name", "Version", "Status")
    term.write(hdr:sub(1, W))

    listBtns = {}
    local lh = listH()
    for row = 0, lh - 1 do
        local idx = row + scroll
        local entry = CATALOG[idx]
        local ry    = LIST_Y + row
        term.setCursorPos(1, ry)
        if entry then
            local isSel  = (idx == selected)
            local isInst = installed[entry.id]
            if isSel then
                term.setBackgroundColor(T.selectBg)
                term.setTextColor(T.selectText)
            else
                term.setBackgroundColor(T.panel)
                term.setTextColor(T.panelText)
            end
            local status = isInst and "[installed]" or "[ available]"
            local line   = string.format("  %-20s %-8s %s",
                entry.name:sub(1, 20), entry.version, status)
            term.write(line:sub(1, W) .. string.rep(" ", W - math.min(#line, W)))
            listBtns[#listBtns+1] = { x = 1, y = ry, w = W, h = 1, idx = idx }
        else
            term.setBackgroundColor(T.panel)
            term.write(string.rep(" ", W))
        end
    end

    -- Status
    term.setBackgroundColor(T.panel)
    term.setTextColor(T.dim)
    term.setCursorPos(1, H - 1)
    local hint = "  Up/Dn: select  Enter/Click: details  ESC: exit"
    term.write(hint:sub(1, W))
    term.setCursorPos(1, H)
    term.write(("  " .. statusMsg):sub(1, W) .. string.rep(" ", W))
end

local function drawDetailMode()
    local entry = CATALOG[selected]
    if not entry then MODE = "list" ; return end

    term.setBackgroundColor(T.panel)
    for row = 1, H do
        term.setCursorPos(1, row)
        term.write(string.rep(" ", W))
    end
    drawTitleBar(entry.name)

    local isInst = installed[entry.id]
    term.setBackgroundColor(T.panel)
    term.setTextColor(T.accent)
    term.setCursorPos(2, 3)
    term.write(entry.name .. " v" .. entry.version)
    term.setTextColor(T.dim)
    term.setCursorPos(2, 4)
    term.write("by " .. entry.author)
    term.setTextColor(T.panelText)
    -- Description word-wrap
    local words = {}
    for w in entry.desc:gmatch("%S+") do words[#words+1] = w end
    local line_buf = ""
    local ly = 6
    for _, word in ipairs(words) do
        if #line_buf + #word + 1 > W - 4 then
            term.setCursorPos(2, ly) ; term.write(line_buf) ; ly = ly + 1 ; line_buf = word
        else
            line_buf = line_buf == "" and word or (line_buf .. " " .. word)
        end
    end
    if line_buf ~= "" then term.setCursorPos(2, ly) ; term.write(line_buf) end

    term.setTextColor(T.dim)
    term.setCursorPos(2, ly + 2)
    term.write("Source: " .. entry.source.type)
    term.setCursorPos(2, ly + 3)
    term.write("Status: " .. (isInst and "Installed" or "Not installed"))

    -- Action buttons
    actionBtns = {}
    local bx = 2
    local btnY = H - 3

    local function addBtn(label, bg, fg)
        local w = #label + 2
        term.setBackgroundColor(bg)
        term.setTextColor(fg)
        term.setCursorPos(bx, btnY)
        term.write(" " .. label .. " ")
        actionBtns[#actionBtns+1] = { x = bx, y = btnY, w = w, label = label }
        bx = bx + w + 1
    end

    if isInst then
        addBtn("Uninstall", T.danger, T.dangerText)
    else
        addBtn("Install", T.accent, T.accentText)
    end
    addBtn("Back", T.btnBg, T.btnText)

    term.setBackgroundColor(T.panel)
    term.setTextColor(T.dim)
    term.setCursorPos(1, H)
    term.write(("  " .. statusMsg):sub(1, W) .. string.rep(" ", W))
end

function app.draw()
    W, H = term.getSize()
    if MODE == "list" then
        drawListMode()
    else
        drawDetailMode()
    end
end

-- ── Init ─────────────────────────────────────────────────────────────────────
function app.init()
    W, H    = term.getSize()
    installed = loadState()
    -- Mark builtins as installed if their file exists
    for _, entry in ipairs(CATALOG) do
        if entry.source.type == "builtin" then
            if fs.exists("/apps/" .. entry.id .. ".lua") then
                installed[entry.id] = true
            end
        end
    end
    saveState(installed)
    MODE     = "list"
    selected = 1
    scroll   = 1
    statusMsg= ""
end

-- ── Event ─────────────────────────────────────────────────────────────────────
function app.event(ev, ...)
    local args = { ... }

    if ev == "mouse_click" then
        local btn, mx, my = args[1], args[2], args[3]
        if closeBtn_r and my == closeBtn_r.y and mx >= closeBtn_r.x then return false end

        if MODE == "list" then
            for _, b in ipairs(listBtns) do
                if my == b.y and mx >= b.x and mx < b.x + b.w then
                    if b.idx == selected then
                        MODE = "detail"
                    else
                        selected = b.idx
                    end
                    return true
                end
            end
        elseif MODE == "detail" then
            for _, b in ipairs(actionBtns) do
                if my == b.y and mx >= b.x and mx < b.x + b.w then
                    if b.label == "Back" then
                        MODE = "list"
                    elseif b.label == "Install" then
                        installApp(CATALOG[selected])
                    elseif b.label == "Uninstall" then
                        uninstallApp(CATALOG[selected])
                    end
                    return true
                end
            end
        end

    elseif ev == "key" then
        local key = args[1]
        if key == keys.escape then
            if MODE == "detail" then MODE = "list"
            else return false end
            return true
        end
        if MODE == "list" then
            if key == keys.up then
                selected = math.max(1, selected - 1)
                if selected < scroll then scroll = selected end
            elseif key == keys.down then
                selected = math.min(#CATALOG, selected + 1)
                if selected >= scroll + listH() then scroll = selected - listH() + 1 end
            elseif key == keys.enter then
                MODE = "detail"
            end
        elseif MODE == "detail" then
            if key == keys.i then
                local entry = CATALOG[selected]
                if installed[entry.id] then uninstallApp(entry)
                else installApp(entry) end
            end
        end
    end

    return true
end

return app
