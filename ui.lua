-- /system/ui.lua
-- CCOS UI: desktop renderer, dock, and reusable widget library.
-- All drawing is done through this module to maintain a consistent theme.

local ui = {}
local _kernel = nil

-- ── Theme ───────────────────────────────────────────────────────────────────
ui.theme = {
    bg          = colors.gray,        -- desktop background
    panel       = colors.black,       -- dock / panel background
    panelText   = colors.white,
    accent      = colors.cyan,        -- primary accent (icons, highlights)
    accentText  = colors.black,
    dim         = colors.lightGray,   -- secondary text / inactive
    danger      = colors.red,
    dangerText  = colors.white,
    titleBar    = colors.black,
    titleText   = colors.cyan,
    btnBg       = colors.lightGray,
    btnText     = colors.black,
    btnHover    = colors.cyan,
    btnHoverTxt = colors.black,
    inputBg     = colors.white,
    inputText   = colors.black,
    selectBg    = colors.cyan,
    selectText  = colors.black,
}

-- ── Init ────────────────────────────────────────────────────────────────────
function ui.init(kernel)
    _kernel = kernel
    ui.W, ui.H = kernel.W, kernel.H
end

-- ── Low-level helpers ───────────────────────────────────────────────────────
function ui.setColors(bg, fg)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
end

-- Fill a rectangle with the current background color
function ui.fillRect(x, y, w, h)
    local line = string.rep(" ", w)
    for row = y, y + h - 1 do
        term.setCursorPos(x, row)
        term.write(line)
    end
end

-- Write text clipped to width chars; pads with spaces
function ui.writeClipped(x, y, text, width)
    term.setCursorPos(x, y)
    local s = tostring(text)
    if #s > width then s = s:sub(1, width) end
    term.write(s .. string.rep(" ", width - #s))
end

-- Horizontal line of a single char
function ui.hline(x, y, w, char)
    char = char or "\140"
    term.setCursorPos(x, y)
    term.write(string.rep(char, w))
end

-- ── Widget: Button ──────────────────────────────────────────────────────────
-- Returns the button's bounding box for hit testing.
-- highlight: force accent color (e.g. for selected state)
function ui.drawButton(x, y, label, highlight)
    local w = #label + 2
    if highlight then
        ui.setColors(_kernel and ui.theme.accent or colors.cyan, ui.theme.accentText)
    else
        ui.setColors(ui.theme.btnBg, ui.theme.btnText)
    end
    term.setCursorPos(x, y)
    term.write(" " .. label .. " ")
    return { x = x, y = y, w = w, h = 1, label = label }
end

-- Test whether (mx, my) is inside a button returned by drawButton
function ui.hitButton(btn, mx, my)
    return mx >= btn.x and mx < btn.x + btn.w
       and my == btn.y
end

-- ── Widget: Title bar ───────────────────────────────────────────────────────
-- Draws a full-width title bar at row y.
-- Returns the close-button bounding box.
function ui.drawTitleBar(title, y)
    y = y or 1
    ui.setColors(ui.theme.titleBar, ui.theme.titleText)
    ui.fillRect(1, y, ui.W, 1)
    term.setCursorPos(3, y)
    term.write(title)
    -- Close button
    ui.setColors(ui.theme.danger, ui.theme.dangerText)
    term.setCursorPos(ui.W - 1, y)
    term.write(" X")
    return { x = ui.W - 1, y = y, w = 2, h = 1 }
end

function ui.hitTitleClose(closeBtn, mx, my)
    return ui.hitButton(closeBtn, mx, my)
end

-- ── Widget: Panel ───────────────────────────────────────────────────────────
function ui.drawPanel(x, y, w, h, bgColor)
    bgColor = bgColor or ui.theme.panel
    ui.setColors(bgColor, ui.theme.panelText)
    ui.fillRect(x, y, w, h)
end

-- ── Widget: Scrollable list ─────────────────────────────────────────────────
-- items: array of strings
-- selected: 1-based index or nil
-- Returns list of {x,y,w,h,index} hit areas
function ui.drawList(x, y, w, h, items, selected, offset)
    offset = offset or 1
    local hits = {}
    for row = 0, h - 1 do
        local idx = row + offset
        local item = items[idx]
        local ry = y + row
        if item then
            if idx == selected then
                ui.setColors(ui.theme.selectBg, ui.theme.selectText)
            else
                ui.setColors(ui.theme.panel, ui.theme.panelText)
            end
            ui.writeClipped(x, ry, item, w)
            hits[#hits + 1] = { x = x, y = ry, w = w, h = 1, index = idx }
        else
            ui.setColors(ui.theme.panel, ui.theme.panelText)
            ui.writeClipped(x, ry, "", w)
        end
    end
    return hits
end

-- ── Widget: Text input ──────────────────────────────────────────────────────
-- Draws an input field and returns its text after the user presses Enter.
-- Blocks; suitable for single-prompt use inside an app's event handler.
-- (For non-blocking input, handle char/key events in your app directly.)
function ui.prompt(x, y, w, initial)
    initial = initial or ""
    local buf = initial
    ui.setColors(ui.theme.inputBg, ui.theme.inputText)
    ui.fillRect(x, y, w, 1)
    term.setCursorPos(x, y)
    term.write(buf)
    term.setCursorBlink(true)
    while true do
        local ev, p1, p2 = os.pullEvent()
        if ev == "char" then
            if #buf < w - 1 then
                buf = buf .. p1
                term.setCursorPos(x, y)
                ui.setColors(ui.theme.inputBg, ui.theme.inputText)
                ui.writeClipped(x, y, buf, w)
                term.setCursorPos(x + #buf, y)
            end
        elseif ev == "key" then
            if p1 == keys.enter then
                break
            elseif p1 == keys.backspace then
                if #buf > 0 then
                    buf = buf:sub(1, -2)
                    ui.setColors(ui.theme.inputBg, ui.theme.inputText)
                    ui.writeClipped(x, y, buf, w)
                    term.setCursorPos(x + #buf, y)
                end
            elseif p1 == keys.escape then
                buf = nil
                break
            end
        end
    end
    term.setCursorBlink(false)
    return buf
end

-- ── Widget: Message dialog ──────────────────────────────────────────────────
function ui.showMessage(title, lines, color)
    color = color or ui.theme.panel
    local dw = 40
    local dh = #lines + 4
    local dx = math.floor((ui.W - dw) / 2)
    local dy = math.floor((ui.H - dh) / 2)
    ui.drawPanel(dx, dy, dw, dh, color)
    ui.setColors(color, ui.theme.accent)
    term.setCursorPos(dx + 2, dy + 1)
    term.write(title)
    ui.setColors(color, ui.theme.panelText)
    for i, line in ipairs(lines) do
        term.setCursorPos(dx + 2, dy + 1 + i)
        term.write(tostring(line):sub(1, dw - 4))
    end
    local okBtn = { x = dx + math.floor(dw/2) - 2, y = dy + dh - 1 }
    ui.drawButton(okBtn.x, okBtn.y, " OK ", false)
    while true do
        local ev, btn, mx, my = os.pullEvent()
        if ev == "mouse_click" then
            if my == okBtn.y and mx >= okBtn.x and mx <= okBtn.x + 5 then
                break
            end
        elseif ev == "key" and (btn == keys.enter or btn == keys.space) then
            break
        end
    end
end

-- ── Dock definition ─────────────────────────────────────────────────────────
-- Each dock item: { label, icon, appPath }
local _dockItems = {
    { label = "Files",   icon = "\4",  appPath = "/apps/filemanager.lua" },
    { label = "Notes",   icon = "\168",appPath = "/apps/notes.lua"       },
    { label = "Calc",    icon = "\15", appPath = "/apps/calculator.lua"  },
    { label = "Snake",   icon = "\16", appPath = "/apps/snake.lua"       },
    { label = "Pong",    icon = "\7",  appPath = "/apps/pong.lua"        },
    { label = "Miner",   icon = "\4",  appPath = "/apps/miner.lua"       },
    { label = "Store",   icon = "\5",  appPath = "/apps/appstore.lua"    },
    { label = "DL",      icon = "\25", appPath = "/apps/downloader.lua"  },
    { label = "Shutdown",icon = "\215",appPath = "__shutdown__"           },
}

local _dockHitAreas = {}

local DOCK_Y    = ui.H  -- will be set after init
local ITEM_W    = 9     -- chars per dock item

function ui.drawDock()
    DOCK_Y = ui.H  -- bottom row
    ui.setColors(ui.theme.panel, ui.theme.accent)
    ui.fillRect(1, DOCK_Y, ui.W, 1)
    _dockHitAreas = {}
    local x = 1
    for i, item in ipairs(_dockItems) do
        local label = item.icon .. " " .. item.label
        local w = #label + 2
        ui.setColors(ui.theme.panel, ui.theme.accent)
        term.setCursorPos(x, DOCK_Y)
        term.write(" " .. label .. " ")
        _dockHitAreas[#_dockHitAreas + 1] = {
            x = x, y = DOCK_Y, w = w, h = 1, item = item
        }
        x = x + w + 1
        if x > ui.W then break end
    end
end

function ui.handleDockClick(mx, my)
    if my ~= DOCK_Y then return false end
    for _, area in ipairs(_dockHitAreas) do
        if mx >= area.x and mx < area.x + area.w then
            local item = area.item
            if item.appPath == "__shutdown__" then
                _kernel.shutdown()
            else
                local ok, err = _kernel.launchApp(item.appPath)
                if not ok then
                    ui.showMessage("Launch Error", { err }, colors.black)
                    _kernel.requestRedraw()
                end
            end
            return true
        end
    end
    return false
end

-- ── Desktop ─────────────────────────────────────────────────────────────────
local _wallpaperLines = {
    "   ____  ____  ___  ____  ",
    "  / __/ / __/ / _ \\/ __/  ",
    " / /__ / /__ / // /\\ \\    ",
    " \\___/ \\___/ \\___/___/    ",
    "  ComputerCraft OS v1.0    ",
}

function ui.drawDesktop()
    -- Background
    ui.setColors(ui.theme.bg, ui.theme.dim)
    for row = 1, ui.H - 1 do
        ui.fillRect(1, row, ui.W, 1)
    end
    -- Centered ASCII art logo
    local startY = math.floor((ui.H - 1 - #_wallpaperLines) / 2) + 1
    ui.setColors(ui.theme.bg, ui.theme.accent)
    for i, line in ipairs(_wallpaperLines) do
        local sx = math.floor((ui.W - #line) / 2) + 1
        term.setCursorPos(sx, startY + i - 1)
        term.write(line)
    end
    -- Hint text
    ui.setColors(ui.theme.bg, ui.theme.dim)
    term.setCursorPos(1, ui.H - 2)
    local hint = "  Click an icon in the dock to launch an app"
    term.write(hint:sub(1, ui.W))
    -- Dock
    ui.drawDock()
end

-- ── Desktop event handler ───────────────────────────────────────────────────
function ui.handleEvent(ev, ...)
    local args = { ... }
    if ev == "mouse_click" then
        local btn, mx, my = args[1], args[2], args[3]
        ui.handleDockClick(mx, my)
    end
end

return ui
