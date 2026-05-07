-- /apps/notes.lua
-- CCOS Notes: create, edit, save, load plain-text notes from /data/notes/

local T = dofile("/system/theme.lua")
local W, H = term.getSize()
local NOTES_DIR = "/data/notes/"

local app = { name = "Notes" }

-- ── State ────────────────────────────────────────────────────────────────────
local MODE         = "list"   -- "list" | "edit"
local noteList     = {}
local listSelected = 1
local listScroll   = 1

local editorLines  = { "" }   -- current file lines
local editorFile   = nil      -- current filename (nil = new)
local cursorLine   = 1
local cursorCol    = 1
local editorScroll = 1

local statusMsg    = ""
local closeBtn_r   = nil

-- ── Geometry ─────────────────────────────────────────────────────────────────
local TITLE_Y    = 1
local TOOLBAR_Y  = 2
local CONTENT_Y  = 3
local CONTENT_H  -- computed in draw

-- ── File helpers ─────────────────────────────────────────────────────────────
local function ensureDir()
    if not fs.exists(NOTES_DIR) then fs.makeDir(NOTES_DIR) end
end

local function refreshList()
    ensureDir()
    noteList = {}
    local files = fs.list(NOTES_DIR)
    table.sort(files)
    for _, f in ipairs(files) do
        if not fs.isDir(NOTES_DIR .. f) then
            noteList[#noteList+1] = f
        end
    end
end

local function loadNote(fname)
    editorFile  = fname
    editorLines = {}
    local path  = NOTES_DIR .. fname
    if not fs.exists(path) then
        editorLines = { "" }
        return
    end
    local f = fs.open(path, "r")
    local line = f.readLine()
    while line ~= nil do
        editorLines[#editorLines+1] = line
        line = f.readLine()
    end
    f.close()
    if #editorLines == 0 then editorLines = { "" } end
    cursorLine = 1 ; cursorCol = 1 ; editorScroll = 1
end

local function saveNote()
    if not editorFile or editorFile == "" then
        -- Prompt for filename using blocking prompt
        local nameY = math.floor(H / 2)
        term.setBackgroundColor(T.panel)
        term.setTextColor(T.accent)
        term.setCursorPos(2, nameY)
        term.write("Save as: " .. string.rep(" ", W - 12))
        term.setCursorPos(11, nameY)
        term.setBackgroundColor(T.inputBg)
        term.setTextColor(T.inputText)
        term.write(string.rep(" ", W - 12))
        term.setCursorPos(11, nameY)
        term.setCursorBlink(true)
        local buf = ""
        while true do
            local ev, p1 = os.pullEvent()
            if ev == "char" then
                buf = buf .. p1
                term.setCursorPos(11, nameY)
                term.write(buf)
            elseif ev == "key" then
                if p1 == keys.enter then break
                elseif p1 == keys.backspace and #buf > 0 then
                    buf = buf:sub(1, -2)
                    term.setCursorPos(11 + #buf, nameY)
                    term.write(" ")
                    term.setCursorPos(11 + #buf, nameY)
                elseif p1 == keys.escape then
                    term.setCursorBlink(false)
                    return
                end
            end
        end
        term.setCursorBlink(false)
        if buf == "" then return end
        if not buf:match("%.") then buf = buf .. ".txt" end
        editorFile = buf
    end
    ensureDir()
    local f = fs.open(NOTES_DIR .. editorFile, "w")
    for _, ln in ipairs(editorLines) do f.writeLine(ln) end
    f.close()
    statusMsg = "Saved: " .. editorFile
    refreshList()
end

local function deleteNote(fname)
    fs.delete(NOTES_DIR .. fname)
    refreshList()
    listSelected = math.min(listSelected, math.max(1, #noteList))
    statusMsg = "Deleted: " .. fname
end

-- ── Draw ─────────────────────────────────────────────────────────────────────
local listCloseBtn = nil
local editCloseBtn = nil
local toolBtns     = {}

local function drawTitleBar(title)
    term.setBackgroundColor(T.titleBar)
    term.setTextColor(T.accent)
    term.setCursorPos(1, TITLE_Y)
    term.write(string.rep(" ", W))
    term.setCursorPos(3, TITLE_Y)
    term.write(title)
    term.setBackgroundColor(T.danger)
    term.setTextColor(T.dangerText)
    term.setCursorPos(W - 1, TITLE_Y)
    term.write(" X")
    return { x = W - 1, y = TITLE_Y, w = 2, h = 1 }
end

local function drawBtn(x, y, label)
    local w = #label + 2
    term.setBackgroundColor(T.btnBg)
    term.setTextColor(T.btnText)
    term.setCursorPos(x, y)
    term.write(" " .. label .. " ")
    return { x = x, y = y, w = w, h = 1, label = label }
end

local function hitBtn(b, mx, my)
    return my == b.y and mx >= b.x and mx < b.x + b.w
end

local function drawListMode()
    CONTENT_H = H - 4
    listCloseBtn = drawTitleBar("Notes")
    -- Toolbar
    term.setBackgroundColor(T.panel)
    term.setTextColor(T.dim)
    term.setCursorPos(1, TOOLBAR_Y)
    term.write(string.rep(" ", W))
    toolBtns = {}
    local bx = 2
    local function addBtn(label)
        local b = drawBtn(bx, TOOLBAR_Y, label)
        toolBtns[#toolBtns+1] = b
        bx = bx + b.w + 1
        return b
    end
    addBtn("New")
    addBtn("Open")
    addBtn("Delete")
    -- List
    term.setBackgroundColor(T.panel)
    term.setTextColor(T.panelText)
    for row = 0, CONTENT_H - 1 do
        local idx = row + listScroll
        local ry  = CONTENT_Y + row
        local fname = noteList[idx]
        term.setCursorPos(1, ry)
        if fname then
            if idx == listSelected then
                term.setBackgroundColor(T.selectBg)
                term.setTextColor(T.selectText)
            else
                term.setBackgroundColor(T.panel)
                term.setTextColor(T.panelText)
            end
            local s = "  " .. fname
            term.write(s:sub(1, W) .. string.rep(" ", W - math.min(#s, W)))
        else
            term.setBackgroundColor(T.panel)
            term.write(string.rep(" ", W))
        end
    end
    -- Status
    term.setBackgroundColor(T.panel)
    term.setTextColor(T.dim)
    term.setCursorPos(1, H - 1)
    local s = "  " .. statusMsg
    term.write(s:sub(1, W) .. string.rep(" ", W - math.min(#s, W)))
end

local function drawEditMode()
    CONTENT_H = H - 4
    editCloseBtn = drawTitleBar("Notes > " .. (editorFile or "New Note"))
    -- Toolbar
    term.setBackgroundColor(T.panel)
    term.setTextColor(T.dim)
    term.setCursorPos(1, TOOLBAR_Y)
    term.write(string.rep(" ", W))
    toolBtns = {}
    local bx = 2
    local function addBtn(label)
        local b = drawBtn(bx, TOOLBAR_Y, label)
        toolBtns[#toolBtns+1] = b
        bx = bx + b.w + 1
    end
    addBtn("Save")
    addBtn("List")
    -- Editor content
    local edW = W - 1
    for row = 0, CONTENT_H - 1 do
        local ln  = editorLines[row + editorScroll]
        local ry  = CONTENT_Y + row
        local isCursor = (row + editorScroll == cursorLine)
        term.setCursorPos(1, ry)
        if isCursor then
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
        else
            term.setBackgroundColor(T.panel)
            term.setTextColor(T.panelText)
        end
        local display = ln or ""
        display = display:sub(1, edW)
        term.write(display .. string.rep(" ", edW - #display))
    end
    -- Cursor blink
    local visualRow = cursorLine - editorScroll
    if visualRow >= 0 and visualRow < CONTENT_H then
        term.setCursorPos(cursorCol, CONTENT_Y + visualRow)
        term.setCursorBlink(true)
    else
        term.setCursorBlink(false)
    end
    -- Status
    term.setBackgroundColor(T.panel)
    term.setTextColor(T.dim)
    term.setCursorPos(1, H - 1)
    local s = string.format("  Ln %d Col %d | %s", cursorLine, cursorCol, statusMsg)
    term.write(s:sub(1, W) .. string.rep(" ", W - math.min(#s, W)))
end

function app.draw()
    W, H = term.getSize()
    term.setCursorBlink(false)
    term.setBackgroundColor(T.panel)
    for row = 1, H do
        term.setCursorPos(1, row)
        term.write(string.rep(" ", W))
    end
    if MODE == "list" then
        drawListMode()
    else
        drawEditMode()
    end
end

-- ── Init ─────────────────────────────────────────────────────────────────────
function app.init()
    W, H = term.getSize()
    refreshList()
    MODE = "list"
    statusMsg = #noteList .. " note(s)"
end

-- ── Editor key handling ───────────────────────────────────────────────────────
local function editorKey(key)
    local line = editorLines[cursorLine]
    if key == keys.left then
        if cursorCol > 1 then cursorCol = cursorCol - 1
        elseif cursorLine > 1 then
            cursorLine = cursorLine - 1
            cursorCol  = #editorLines[cursorLine] + 1
        end
    elseif key == keys.right then
        if cursorCol <= #line then cursorCol = cursorCol + 1
        elseif cursorLine < #editorLines then
            cursorLine = cursorLine + 1
            cursorCol  = 1
        end
    elseif key == keys.up then
        if cursorLine > 1 then
            cursorLine = cursorLine - 1
            cursorCol  = math.min(cursorCol, #editorLines[cursorLine] + 1)
            if cursorLine < editorScroll then editorScroll = cursorLine end
        end
    elseif key == keys.down then
        if cursorLine < #editorLines then
            cursorLine = cursorLine + 1
            cursorCol  = math.min(cursorCol, #editorLines[cursorLine] + 1)
            local visible = H - 4
            if cursorLine >= editorScroll + visible then
                editorScroll = cursorLine - visible + 1
            end
        end
    elseif key == keys.home then
        cursorCol = 1
    elseif key == keys["end"] then
        cursorCol = #line + 1
    elseif key == keys.enter then
        local before = line:sub(1, cursorCol - 1)
        local after  = line:sub(cursorCol)
        editorLines[cursorLine] = before
        table.insert(editorLines, cursorLine + 1, after)
        cursorLine = cursorLine + 1
        cursorCol  = 1
        local visible = H - 4
        if cursorLine >= editorScroll + visible then
            editorScroll = cursorLine - visible + 1
        end
    elseif key == keys.backspace then
        if cursorCol > 1 then
            editorLines[cursorLine] = line:sub(1, cursorCol - 2) .. line:sub(cursorCol)
            cursorCol = cursorCol - 1
        elseif cursorLine > 1 then
            local prevLine = editorLines[cursorLine - 1]
            local newCol   = #prevLine + 1
            editorLines[cursorLine - 1] = prevLine .. line
            table.remove(editorLines, cursorLine)
            cursorLine = cursorLine - 1
            cursorCol  = newCol
            if cursorLine < editorScroll then editorScroll = cursorLine end
        end
    elseif key == keys.delete then
        if cursorCol <= #line then
            editorLines[cursorLine] = line:sub(1, cursorCol - 1) .. line:sub(cursorCol + 1)
        elseif cursorLine < #editorLines then
            editorLines[cursorLine] = line .. editorLines[cursorLine + 1]
            table.remove(editorLines, cursorLine + 1)
        end
    end
end

-- ── Event ─────────────────────────────────────────────────────────────────────
function app.event(ev, ...)
    local args = { ... }
    if ev == "mouse_click" then
        local btn, mx, my = args[1], args[2], args[3]
        -- Close button
        local cb = (MODE == "list") and listCloseBtn or editCloseBtn
        if cb and my == cb.y and mx >= cb.x and mx < cb.x + cb.w then
            term.setCursorBlink(false)
            return false
        end
        -- Toolbar buttons
        for _, b in ipairs(toolBtns) do
            if hitBtn(b, mx, my) then
                if b.label == "New" then
                    editorFile = nil ; editorLines = { "" }
                    cursorLine = 1 ; cursorCol = 1 ; editorScroll = 1
                    statusMsg = "New note"
                    MODE = "edit"
                elseif b.label == "Open" then
                    local fname = noteList[listSelected]
                    if fname then loadNote(fname) ; MODE = "edit" end
                elseif b.label == "Delete" then
                    local fname = noteList[listSelected]
                    if fname then deleteNote(fname) end
                elseif b.label == "Save" then
                    saveNote()
                elseif b.label == "List" then
                    term.setCursorBlink(false)
                    refreshList()
                    MODE = "list"
                    statusMsg = #noteList .. " note(s)"
                end
                return true
            end
        end
        -- List click
        if MODE == "list" and my >= CONTENT_Y and my < CONTENT_Y + CONTENT_H then
            local idx = (my - CONTENT_Y) + listScroll
            if noteList[idx] then
                if idx == listSelected then
                    loadNote(noteList[idx]) ; MODE = "edit"
                else
                    listSelected = idx
                end
            end
        end
        -- Editor click
        if MODE == "edit" and my >= CONTENT_Y and my < CONTENT_Y + (H - 4) then
            local targetLine = (my - CONTENT_Y) + editorScroll
            if targetLine >= 1 and targetLine <= #editorLines then
                cursorLine = targetLine
                cursorCol  = math.min(mx, #editorLines[cursorLine] + 1)
            end
        end

    elseif ev == "mouse_scroll" then
        local dir = args[1]
        if MODE == "list" then
            listScroll = math.max(1, math.min(math.max(1, #noteList - (H-4) + 1), listScroll + dir))
        else
            editorScroll = math.max(1, editorScroll + dir)
        end

    elseif ev == "char" then
        if MODE == "edit" then
            local ch = args[1]
            local line = editorLines[cursorLine]
            editorLines[cursorLine] = line:sub(1, cursorCol - 1) .. ch .. line:sub(cursorCol)
            cursorCol = cursorCol + 1
        end

    elseif ev == "key" then
        local key = args[1]
        if MODE == "edit" then
            if key == keys.escape then
                term.setCursorBlink(false)
                refreshList()
                MODE = "list"
                statusMsg = #noteList .. " note(s)"
            elseif key == keys.s and _G.keys.leftCtrl then
                -- ctrl+s won't fire as a chord in CC; handled via button
                saveNote()
            else
                editorKey(key)
            end
        else
            if key == keys.up then
                listSelected = math.max(1, listSelected - 1)
                if listSelected < listScroll then listScroll = listSelected end
            elseif key == keys.down then
                listSelected = math.min(#noteList, listSelected + 1)
                if listSelected >= listScroll + (H-4) then
                    listScroll = listSelected - (H-4) + 1
                end
            elseif key == keys.enter then
                local fname = noteList[listSelected]
                if fname then loadNote(fname) ; MODE = "edit" end
            elseif key == keys.escape then
                return false
            end
        end
    end

    return true
end

function app.unload()
    term.setCursorBlink(false)
end

return app
