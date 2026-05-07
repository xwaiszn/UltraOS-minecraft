-- /apps/downloader.lua
-- CCOS Downloader: fetches files via http.get or pastebin API and saves them.
-- No fake downloads; real HTTP only.

local T = dofile("/system/theme.lua")
local app = { name = "Downloader" }

local W, H
local closeBtn_r

-- ── State ────────────────────────────────────────────────────────────────────
local MODE      = "menu"    -- "menu" | "url" | "pastebin" | "progress" | "result"
local inputBuf  = ""
local inputMode = nil       -- "url" | "paste" | "dest"
local urlBuf    = ""
local destBuf   = ""
local statusMsg = ""
local resultMsg = ""
local logLines  = {}
local MAX_LOG   = 12
local menuSel   = 1

local MENU_OPTS = {
    { label = "Download from URL",      id = "url"      },
    { label = "Download from Pastebin", id = "pastebin" },
}

-- ── Logging ──────────────────────────────────────────────────────────────────
local function log(msg)
    logLines[#logLines+1] = msg
    if #logLines > MAX_LOG then table.remove(logLines, 1) end
end

-- ── Download logic ────────────────────────────────────────────────────────────
-- Returns true, content or false, errMsg
local function httpGet(url)
    if not http then
        return false, "HTTP API not available (enable in CC config)"
    end
    log("Requesting: " .. url:sub(1, 50))
    local ok, response = pcall(http.get, url)
    if not ok then
        return false, "http.get error: " .. tostring(response)
    end
    if not response then
        return false, "Server returned nil (check URL/internet)"
    end
    local content = response.readAll()
    response.close()
    if not content then return false, "Empty response" end
    return true, content
end

local function pastebinGet(code)
    -- Pastebin raw URL
    local url = "https://pastebin.com/raw/" .. code:match("^%s*(.-)%s*$")
    return httpGet(url)
end

local function saveContent(destPath, content)
    -- Ensure parent directory exists
    local parent = fs.getDir(destPath)
    if parent and parent ~= "" and not fs.exists(parent) then
        fs.makeDir(parent)
    end
    local f = fs.open(destPath, "w")
    if not f then return false, "Cannot open destination: " .. destPath end
    f.write(content)
    f.close()
    return true
end

-- ── Draw ─────────────────────────────────────────────────────────────────────
local function drawTitleBar()
    term.setBackgroundColor(T.titleBar)
    term.setTextColor(T.accent)
    term.setCursorPos(1, 1)
    term.write(string.rep(" ", W))
    term.setCursorPos(3, 1)
    term.write("Downloader")
    term.setBackgroundColor(T.danger)
    term.setTextColor(T.dangerText)
    term.setCursorPos(W - 1, 1)
    term.write(" X")
    closeBtn_r = { x = W - 1, y = 1, w = 2, h = 1 }
end

local function drawLog()
    local logY = H - MAX_LOG - 1
    term.setBackgroundColor(colors.black)
    term.setTextColor(T.dim)
    for row = 0, MAX_LOG - 1 do
        term.setCursorPos(1, logY + row)
        local ln = logLines[row + math.max(1, #logLines - MAX_LOG + 1)] or ""
        term.write(("  " .. ln):sub(1, W) .. string.rep(" ", W - math.min(#ln + 2, W)))
    end
    -- divider
    term.setBackgroundColor(T.panel)
    term.setTextColor(T.dim)
    term.setCursorPos(1, logY - 1)
    term.write(string.rep("\140", W))
    term.setCursorPos(2, logY - 1)
    term.write(" Log ")
end

local menuBtns = {}

local function drawMenu()
    term.setBackgroundColor(T.panel)
    for row = 2, H do
        term.setCursorPos(1, row)
        term.write(string.rep(" ", W))
    end
    drawTitleBar()
    drawLog()

    local logY = H - MAX_LOG - 1
    term.setBackgroundColor(T.panel)
    term.setTextColor(T.panelText)
    term.setCursorPos(2, 3)
    term.write("Choose download method:")

    menuBtns = {}
    for i, opt in ipairs(MENU_OPTS) do
        local y = 4 + i
        if i == menuSel then
            term.setBackgroundColor(T.selectBg)
            term.setTextColor(T.selectText)
        else
            term.setBackgroundColor(T.panel)
            term.setTextColor(T.panelText)
        end
        term.setCursorPos(2, y)
        local s = "  " .. opt.label .. string.rep(" ", W - 4 - #opt.label)
        term.write(s:sub(1, W - 2))
        menuBtns[i] = { x = 2, y = y, w = W - 2, h = 1, id = opt.id }
    end

    term.setBackgroundColor(T.panel)
    term.setTextColor(T.dim)
    term.setCursorPos(2, logY - 2)
    term.write("Up/Dn: select  Enter: confirm  ESC: exit")
end

-- Input screen: collects URL/pastebin code + destination path
local INPUT_FIELDS = {}
local inputStep    = 1   -- 1 = source, 2 = destination
local sourceLabel  = ""

local function drawInputScreen()
    term.setBackgroundColor(T.panel)
    for row = 2, H do
        term.setCursorPos(1, row)
        term.write(string.rep(" ", W))
    end
    drawTitleBar()
    drawLog()
    local logY = H - MAX_LOG - 1

    term.setBackgroundColor(T.panel)
    term.setTextColor(T.accent)
    term.setCursorPos(2, 3)
    term.write(inputMode == "url" and "Download from URL" or "Download from Pastebin")

    local labels = {
        inputMode == "url" and "URL:" or "Pastebin code:",
        "Save to (path):"
    }
    local bufs = { urlBuf, destBuf }

    for i = 1, 2 do
        local y = 4 + i * 2
        term.setBackgroundColor(T.panel)
        term.setTextColor(T.panelText)
        term.setCursorPos(2, y)
        term.write(labels[i])
        -- Input box
        term.setBackgroundColor(T.inputBg)
        term.setTextColor(T.inputText)
        term.setCursorPos(2, y + 1)
        local val = bufs[i] or ""
        term.write(val:sub(-(W - 4)) .. string.rep(" ", W - 4 - math.min(#val, W - 4)))
    end

    -- Highlight active field
    local activeY = 4 + inputStep * 2 + 1
    term.setBackgroundColor(T.selectBg)
    term.setTextColor(T.selectText)
    term.setCursorPos(2, activeY)
    local val = (inputStep == 1 and urlBuf or destBuf)
    term.write(val:sub(-(W - 4)) .. string.rep(" ", W - 4 - math.min(#val, W - 4)))
    term.setCursorPos(2 + math.min(#val, W - 5), activeY)
    term.setCursorBlink(true)

    -- Buttons
    local btnY = logY - 3
    term.setBackgroundColor(T.accent)
    term.setTextColor(T.accentText)
    term.setCursorPos(2, btnY)
    term.write(" Download ")
    term.setBackgroundColor(T.panel)
    term.setTextColor(T.dim)
    term.setCursorPos(14, btnY)
    term.write(" Cancel ")
    INPUT_FIELDS = {
        dl     = { x = 2,  y = btnY, w = 10, h = 1 },
        cancel = { x = 14, y = btnY, w = 8,  h = 1 },
    }

    term.setBackgroundColor(T.panel)
    term.setTextColor(T.dim)
    term.setCursorPos(2, logY - 2)
    term.write("Tab: switch field  Enter: download  ESC: back")
end

local function drawResultScreen()
    term.setBackgroundColor(T.panel)
    for row = 2, H do
        term.setCursorPos(1, row)
        term.write(string.rep(" ", W))
    end
    drawTitleBar()
    drawLog()
    local logY = H - MAX_LOG - 1

    term.setBackgroundColor(T.panel)
    term.setTextColor(T.panelText)
    term.setCursorPos(2, 3)
    term.write(resultMsg:sub(1, W - 2))

    term.setBackgroundColor(T.accent)
    term.setTextColor(T.accentText)
    term.setCursorPos(2, 5)
    term.write(" OK ")
end

function app.draw()
    W, H = term.getSize()
    term.setCursorBlink(false)
    if MODE == "menu" then
        drawMenu()
    elseif MODE == "input" then
        drawInputScreen()
    elseif MODE == "result" then
        drawResultScreen()
    end
end

-- ── Download execution ────────────────────────────────────────────────────────
local function doDownload()
    term.setCursorBlink(false)
    MODE = "menu"   -- suppress draw during blocking call
    log("Starting download...")
    local ok, content

    if inputMode == "url" then
        ok, content = httpGet(urlBuf)
    else
        ok, content = pastebinGet(urlBuf)
    end

    if not ok then
        log("FAILED: " .. content)
        resultMsg = "Download failed: " .. content
        MODE = "result"
        return
    end

    log("Received " .. #content .. " bytes")
    local saveOk, saveErr = saveContent(destBuf, content)
    if not saveOk then
        log("SAVE ERROR: " .. tostring(saveErr))
        resultMsg = "Save error: " .. tostring(saveErr)
    else
        log("Saved to: " .. destBuf)
        resultMsg = "Saved " .. #content .. " bytes to " .. destBuf
    end
    MODE = "result"
end

-- ── Init ─────────────────────────────────────────────────────────────────────
function app.init()
    W, H = term.getSize()
    MODE      = "menu"
    menuSel   = 1
    urlBuf    = ""
    destBuf   = "/downloads/"
    inputStep = 1
    logLines  = {}
    log("Downloader ready")
    if not http then log("WARNING: HTTP is disabled in CC config") end
end

-- ── Event ─────────────────────────────────────────────────────────────────────
function app.event(ev, ...)
    local args = { ... }

    if ev == "mouse_click" then
        local btn, mx, my = args[1], args[2], args[3]
        if closeBtn_r and my == closeBtn_r.y and mx >= closeBtn_r.x then
            term.setCursorBlink(false)
            return false
        end

        if MODE == "menu" then
            for i, b in ipairs(menuBtns) do
                if my == b.y and mx >= b.x and mx < b.x + b.w then
                    if i == menuSel then
                        -- activate
                        inputMode = b.id
                        inputStep = 1
                        urlBuf    = ""
                        destBuf   = "/downloads/"
                        MODE      = "input"
                    else
                        menuSel = i
                    end
                    return true
                end
            end

        elseif MODE == "input" then
            -- Field click (step 1 area or step 2 area)
            local f1y = 4 + 1 * 2 + 1
            local f2y = 4 + 2 * 2 + 1
            if my == f1y then inputStep = 1
            elseif my == f2y then inputStep = 2
            end
            -- Button clicks
            if INPUT_FIELDS.dl and my == INPUT_FIELDS.dl.y and mx >= INPUT_FIELDS.dl.x and mx < INPUT_FIELDS.dl.x + INPUT_FIELDS.dl.w then
                if urlBuf ~= "" and destBuf ~= "" then
                    doDownload()
                else
                    log("Please fill all fields")
                end
            elseif INPUT_FIELDS.cancel and my == INPUT_FIELDS.cancel.y and mx >= INPUT_FIELDS.cancel.x and mx < INPUT_FIELDS.cancel.x + INPUT_FIELDS.cancel.w then
                MODE = "menu"
                term.setCursorBlink(false)
            end

        elseif MODE == "result" then
            MODE = "menu"
        end

    elseif ev == "char" then
        local ch = args[1]
        if MODE == "input" then
            if inputStep == 1 then urlBuf  = urlBuf  .. ch
            else                   destBuf = destBuf .. ch end
        end

    elseif ev == "key" then
        local key = args[1]
        if key == keys.escape then
            term.setCursorBlink(false)
            if MODE == "input" then MODE = "menu"
            elseif MODE == "result" then MODE = "menu"
            else return false end
            return true
        end

        if MODE == "menu" then
            if key == keys.up   then menuSel = math.max(1, menuSel - 1)
            elseif key == keys.down then menuSel = math.min(#MENU_OPTS, menuSel + 1)
            elseif key == keys.enter then
                inputMode = MENU_OPTS[menuSel].id
                inputStep = 1 ; urlBuf = "" ; destBuf = "/downloads/"
                MODE = "input"
            end

        elseif MODE == "input" then
            if key == keys.backspace then
                if inputStep == 1 and #urlBuf  > 0 then urlBuf  = urlBuf:sub(1, -2)
                elseif inputStep == 2 and #destBuf > 0 then destBuf = destBuf:sub(1, -2) end
            elseif key == keys.tab then
                inputStep = (inputStep == 1) and 2 or 1
            elseif key == keys.enter then
                if inputStep == 1 then inputStep = 2
                else
                    if urlBuf ~= "" and destBuf ~= "" then doDownload()
                    else log("Fill both fields") end
                end
            end

        elseif MODE == "result" then
            if key == keys.enter then MODE = "menu" end
        end
    end

    return true
end

function app.unload()
    term.setCursorBlink(false)
end

return app
