-- /apps/filemanager.lua
-- CCOS File Manager: navigate, view, copy, delete files using the fs API.

local ui     = dofile("/system/ui.lua")
local kernel = nil   -- set at init via _ENV reference trick avoided; ui re-init done below

-- ── State ────────────────────────────────────────────────────────────────────
local app = { name = "File Manager" }

local W, H           -- screen size
local cwd            = "/"
local entries        = {}    -- {name, isDir, size}
local selected       = 1
local scrollOffset   = 1
local statusMsg      = ""
local closeBtn       = nil
local LIST_Y         = 3
local LIST_H         -- computed

local ACTION_BTNS    = {}  -- drawn buttons

-- ── Helpers ──────────────────────────────────────────────────────────────────
local function loadDir(path)
    entries = {}
    if path ~= "/" then
        entries[#entries+1] = { name = "..", isDir = true, size = 0 }
    end
    local ok, list = pcall(fs.list, path)
    if ok then
        table.sort(list)
        for _, name in ipairs(list) do
            local full = fs.combine(path, name)
            local isDir = fs.isDir(full)
            local size  = isDir and 0 or (fs.getSize and fs.getSize(full) or 0)
            entries[#entries+1] = { name = name, isDir = isDir, size = size }
        end
    end
    selected     = 1
    scrollOffset = 1
    statusMsg    = path
end

local function currentEntry()
    return entries[selected]
end

local function navigate(entry)
    if not entry then return end
    if entry.name == ".." then
        cwd = fs.getDir(cwd)
        if cwd == "" then cwd = "/" end
    elseif entry.isDir then
        cwd = fs.combine(cwd, entry.name)
    end
    loadDir(cwd)
end

local function deleteSelected()
    local e = currentEntry()
    if not e or e.name == ".." then return end
    local path = fs.combine(cwd, e.name)
    local ok, err = pcall(fs.delete, path)
    if ok then
        statusMsg = "Deleted: " .. e.name
        loadDir(cwd)
    else
        statusMsg = "Error: " .. tostring(err)
    end
end

local function viewFile()
    local e = currentEntry()
    if not e or e.isDir then return end
    local path = fs.combine(cwd, e.name)
    local f = fs.open(path, "r")
    if not f then statusMsg = "Cannot open file" ; return end
    local lines = {}
    local line = f.readLine()
    while line ~= nil do
        lines[#lines+1] = line
        line = f.readLine()
    end
    f.close()

    -- Simple paged viewer
    local vW, vH = W - 4, H - 6
    local vX, vY = 3, 4
    local vOff   = 1
    local function drawViewer()
        ui.setColors(colors.black, colors.white)
        for row = 0, vH - 1 do
            local ln = lines[row + vOff] or ""
            term.setCursorPos(vX, vY + row)
            term.write(ln:sub(1, vW) .. string.rep(" ", vW - math.min(#ln, vW)))
        end
        ui.setColors(colors.black, colors.cyan)
        term.setCursorPos(vX, vY + vH)
        term.write(string.format(" Lines %d/%d  [UP/DN scroll] [Q/ESC close] ", vOff, #lines))
    end
    ui.drawPanel(1, 2, W, H - 1, colors.black)
    ui.setColors(colors.black, colors.cyan)
    term.setCursorPos(2, 2)
    term.write("Viewing: " .. e.name)
    drawViewer()
    while true do
        local ev, p1 = os.pullEvent()
        if ev == "key" then
            if p1 == keys.up    then vOff = math.max(1, vOff - 1)  ; drawViewer()
            elseif p1 == keys.down then
                if vOff + vH - 1 < #lines then vOff = vOff + 1 end
                drawViewer()
            elseif p1 == keys.q or p1 == keys.escape then break
            end
        elseif ev == "mouse_scroll" then
            local dir = p1
            vOff = math.max(1, math.min(math.max(1, #lines - vH + 1), vOff + dir))
            drawViewer()
        end
    end
end

-- ── Draw ─────────────────────────────────────────────────────────────────────
local function formatEntry(e, w)
    local prefix = e.isDir and "[D] " or "    "
    local suffix = e.isDir and "/" or (" " .. e.size .. "B")
    local mid    = w - #prefix - #suffix
    if mid < 1 then mid = 1 end
    local name = e.name:sub(1, mid)
    return prefix .. name .. string.rep(" ", mid - #name) .. suffix
end

function app.draw()
    W, H = term.getSize()
    LIST_H = H - 5

    -- Background
    ui.setColors(ui.theme.bg, ui.theme.panelText)
    for row = 1, H do
        term.setCursorPos(1, row)
        term.write(string.rep(" ", W))
    end

    -- Title bar
    closeBtn = ui.drawTitleBar("File Manager", 1)

    -- Path bar
    ui.setColors(ui.theme.panel, ui.theme.dim)
    ui.fillRect(1, 2, W, 1)
    term.setCursorPos(2, 2)
    ui.setColors(ui.theme.panel, ui.theme.accent)
    term.write(cwd:sub(1, W - 2))

    -- File list panel
    ui.drawPanel(1, LIST_Y, W, LIST_H, ui.theme.panel)
    local itemW = W - 2
    for row = 0, LIST_H - 1 do
        local idx = row + scrollOffset
        local e   = entries[idx]
        local ry  = LIST_Y + row
        if e then
            local isSelected = (idx == selected)
            if isSelected then
                ui.setColors(ui.theme.selectBg, ui.theme.selectText)
            elseif e.isDir then
                ui.setColors(ui.theme.panel, ui.theme.accent)
            else
                ui.setColors(ui.theme.panel, ui.theme.panelText)
            end
            local line = formatEntry(e, itemW)
            term.setCursorPos(2, ry)
            term.write(line)
        else
            ui.setColors(ui.theme.panel, ui.theme.panelText)
            term.setCursorPos(2, ry)
            term.write(string.rep(" ", itemW))
        end
    end

    -- Action buttons row
    local btnY = H - 2
    ui.setColors(ui.theme.bg, ui.theme.dim)
    ui.fillRect(1, btnY, W, 1)
    ACTION_BTNS = {}
    local bx = 2
    local function addBtn(label)
        local b = ui.drawButton(bx, btnY, label, false)
        ACTION_BTNS[#ACTION_BTNS+1] = b
        bx = bx + b.w + 1
        return b
    end
    addBtn("Open")
    addBtn("View")
    addBtn("Delete")

    -- Status bar
    ui.setColors(ui.theme.panel, ui.theme.dim)
    ui.fillRect(1, H - 1, W, 1)
    term.setCursorPos(2, H - 1)
    term.write(statusMsg:sub(1, W - 2))
end

-- ── Init ─────────────────────────────────────────────────────────────────────
function app.init()
    W, H = term.getSize()
    -- Fetch kernel reference to restore ui theme
    local k_ok, k = pcall(dofile, "/system/kernel.lua")
    -- We can't re-run kernel; ui is already loaded. Pull theme from cached.
    ui = dofile("/system/ui.lua")
    ui.W = W ; ui.H = H
    ui.theme = (function()
        -- Manually re-declare theme to avoid circular dep
        return {
            bg=colors.gray, panel=colors.black, panelText=colors.white,
            accent=colors.cyan, accentText=colors.black, dim=colors.lightGray,
            danger=colors.red, dangerText=colors.white, titleBar=colors.black,
            titleText=colors.cyan, btnBg=colors.lightGray, btnText=colors.black,
            btnHover=colors.cyan, btnHoverTxt=colors.black,
            inputBg=colors.white, inputText=colors.black,
            selectBg=colors.cyan, selectText=colors.black,
        }
    end)()
    loadDir(cwd)
end

-- ── Event ────────────────────────────────────────────────────────────────────
function app.event(ev, ...)
    local args = { ... }
    if ev == "mouse_click" then
        local btn, mx, my = args[1], args[2], args[3]
        if closeBtn and ui.hitTitleClose(closeBtn, mx, my) then return false end

        -- Action buttons
        for _, b in ipairs(ACTION_BTNS) do
            if ui.hitButton(b, mx, my) then
                if b.label == "Open"   then navigate(currentEntry()) end
                if b.label == "View"   then viewFile() end
                if b.label == "Delete" then deleteSelected() end
                return true
            end
        end

        -- List click
        if my >= LIST_Y and my < LIST_Y + LIST_H then
            local idx = (my - LIST_Y) + scrollOffset
            if idx == selected and entries[idx] then
                navigate(currentEntry())
            elseif entries[idx] then
                selected = idx
            end
        end

    elseif ev == "mouse_scroll" then
        local dir, mx, my = args[1], args[2], args[3]
        scrollOffset = math.max(1, math.min(math.max(1, #entries - LIST_H + 1), scrollOffset + dir))

    elseif ev == "key" then
        local key = args[1]
        if key == keys.up then
            selected = math.max(1, selected - 1)
            if selected < scrollOffset then scrollOffset = selected end
        elseif key == keys.down then
            selected = math.min(#entries, selected + 1)
            if selected >= scrollOffset + LIST_H then scrollOffset = selected - LIST_H + 1 end
        elseif key == keys.enter then
            navigate(currentEntry())
        elseif key == keys.delete then
            deleteSelected()
        elseif key == keys.escape then
            return false
        end
    end

    return true
end

function app.unload()
    -- nothing to clean up
end

return app
