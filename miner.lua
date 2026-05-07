-- /apps/miner.lua
-- CCOS Miner: Minesweeper-style game using the fs/math APIs only.
-- Click to reveal; R-click to flag; uncover all safe cells to win.

local T = dofile("/system/theme.lua")
local app = { name = "Miner" }

local W, H
local closeBtn_r

-- ── Config ────────────────────────────────────────────────────────────────────
local COLS  = 16
local ROWS  = 12
local MINES = 24

-- ── State ─────────────────────────────────────────────────────────────────────
local board       -- [row][col] = { mine, adj, revealed, flagged }
local phase       -- "play" | "win" | "dead"
local mineCount   -- remaining unflagged mine count
local startTime
local elapsed

-- ── Grid geometry ─────────────────────────────────────────────────────────────
local GX, GY   -- top-left of grid on screen
local CW = 3   -- cell width in chars
local CH = 1   -- cell height in rows

local function cellOrigin(col, row)
    return GX + (col - 1) * CW, GY + (row - 1) * CH
end

local function screenToCell(mx, my)
    local col = math.floor((mx - GX) / CW) + 1
    local row = math.floor((my - GY) / CH) + 1
    if col < 1 or col > COLS or row < 1 or row > ROWS then
        return nil, nil
    end
    return col, row
end

-- ── Board logic ───────────────────────────────────────────────────────────────
local function placeMines(safeCol, safeRow)
    local candidates = {}
    for r = 1, ROWS do
        for c = 1, COLS do
            if not (c == safeCol and r == safeRow) then
                candidates[#candidates+1] = { c = c, r = r }
            end
        end
    end
    -- Fisher-Yates shuffle
    for i = #candidates, 2, -1 do
        local j = math.random(i)
        candidates[i], candidates[j] = candidates[j], candidates[i]
    end
    for i = 1, MINES do
        local pos = candidates[i]
        board[pos.r][pos.c].mine = true
    end
    -- Compute adjacency
    for r = 1, ROWS do
        for c = 1, COLS do
            local count = 0
            for dr = -1, 1 do
                for dc = -1, 1 do
                    local nr, nc = r + dr, c + dc
                    if nr >= 1 and nr <= ROWS and nc >= 1 and nc <= COLS then
                        if board[nr][nc].mine then count = count + 1 end
                    end
                end
            end
            board[r][c].adj = count
        end
    end
end

local function initBoard()
    board = {}
    for r = 1, ROWS do
        board[r] = {}
        for c = 1, COLS do
            board[r][c] = { mine = false, adj = 0, revealed = false, flagged = false }
        end
    end
    phase     = "play"
    mineCount = MINES
    startTime = os.clock()
    elapsed   = 0
end

-- Flood-fill reveal
local function reveal(col, row)
    local cell = board[row] and board[row][col]
    if not cell then return end
    if cell.revealed or cell.flagged then return end
    cell.revealed = true
    if cell.mine then
        phase = "dead"
        -- Reveal all mines
        for r = 1, ROWS do
            for c = 1, COLS do
                if board[r][c].mine then board[r][c].revealed = true end
            end
        end
        return
    end
    if cell.adj == 0 then
        for dr = -1, 1 do
            for dc = -1, 1 do
                if not (dr == 0 and dc == 0) then
                    reveal(col + dc, row + dr)
                end
            end
        end
    end
end

local function checkWin()
    for r = 1, ROWS do
        for c = 1, COLS do
            local cell = board[r][c]
            if not cell.mine and not cell.revealed then return end
        end
    end
    phase = "win"
    elapsed = os.clock() - startTime
end

-- ── Draw ──────────────────────────────────────────────────────────────────────
local ADJ_COLORS = {
    [1] = colors.blue,
    [2] = colors.green,
    [3] = colors.red,
    [4] = colors.purple,
    [5] = colors.orange,
    [6] = colors.cyan,
    [7] = colors.magenta,
    [8] = colors.white,
}

function app.draw()
    W, H = term.getSize()
    GX    = math.floor((W - COLS * CW) / 2) + 1
    GY    = 4

    -- Background
    term.setBackgroundColor(T.panel)
    for row = 1, H do
        term.setCursorPos(1, row)
        term.write(string.rep(" ", W))
    end

    -- Title bar
    term.setBackgroundColor(T.titleBar)
    term.setTextColor(T.accent)
    term.setCursorPos(1, 1)
    term.write(string.rep(" ", W))
    term.setCursorPos(3, 1)
    local secs = (phase == "play") and math.floor(os.clock() - (startTime or os.clock()))
                                    or math.floor(elapsed or 0)
    term.write(string.format("Miner  \7%d  Time: %ds", mineCount or MINES, secs))
    term.setBackgroundColor(T.danger)
    term.setTextColor(T.dangerText)
    term.setCursorPos(W - 1, 1)
    term.write(" X")
    closeBtn_r = { x = W - 1, y = 1, w = 2, h = 1 }

    -- Sub-header
    term.setBackgroundColor(T.panel)
    term.setTextColor(T.dim)
    term.setCursorPos(1, 2)
    term.write(string.rep(" ", W))
    term.setCursorPos(2, 2)
    term.write("Left-click: reveal  Right-click: flag  [R] New game")
    term.setCursorPos(1, 3)
    term.write(string.rep(" ", W))

    -- Board
    for r = 1, ROWS do
        for c = 1, COLS do
            local cell  = board[r][c]
            local cx, cy = cellOrigin(c, r)
            if cell.revealed then
                if cell.mine then
                    term.setBackgroundColor(T.danger)
                    term.setTextColor(colors.white)
                    term.setCursorPos(cx, cy)
                    term.write(" * ")
                elseif cell.adj == 0 then
                    term.setBackgroundColor(colors.black)
                    term.setTextColor(T.dim)
                    term.setCursorPos(cx, cy)
                    term.write("   ")
                else
                    term.setBackgroundColor(colors.black)
                    term.setTextColor(ADJ_COLORS[cell.adj] or colors.white)
                    term.setCursorPos(cx, cy)
                    term.write(" " .. cell.adj .. " ")
                end
            elseif cell.flagged then
                term.setBackgroundColor(T.dim)
                term.setTextColor(T.danger)
                term.setCursorPos(cx, cy)
                term.write(" \4 ")
            else
                term.setBackgroundColor(T.btnBg)
                term.setTextColor(T.btnText)
                term.setCursorPos(cx, cy)
                term.write("[ ]")
            end
        end
    end

    -- Status overlay
    if phase == "win" or phase == "dead" then
        local msg  = (phase == "win") and ("YOU WIN! Time: " .. math.floor(elapsed) .. "s") or "BOOM! Game Over"
        local msg2 = "[R] New Game  [ESC] Exit"
        local oy   = GY + ROWS + 1
        term.setBackgroundColor(T.panel)
        term.setTextColor(phase == "win" and T.accent or T.danger)
        term.setCursorPos(math.floor((W - #msg) / 2) + 1, oy)
        term.write(msg)
        term.setTextColor(T.dim)
        term.setCursorPos(math.floor((W - #msg2) / 2) + 1, oy + 1)
        term.write(msg2)
    end
end

-- ── Init ─────────────────────────────────────────────────────────────────────
local firstClick = false

function app.init()
    W, H = term.getSize()
    math.randomseed(os.time())
    initBoard()
    firstClick = true
end

-- ── Event ─────────────────────────────────────────────────────────────────────
function app.event(ev, ...)
    local args = { ... }

    if ev == "mouse_click" then
        local btn, mx, my = args[1], args[2], args[3]
        if closeBtn_r and my == closeBtn_r.y and mx >= closeBtn_r.x then
            return false
        end
        if phase ~= "play" then return true end
        local col, row = screenToCell(mx, my)
        if not col then return true end
        local cell = board[row][col]
        if btn == 1 then  -- left click: reveal
            if not cell.flagged then
                if firstClick then
                    firstClick = false
                    placeMines(col, row)
                    startTime = os.clock()
                end
                reveal(col, row)
                if phase == "play" then checkWin() end
                if phase == "win" then elapsed = os.clock() - startTime end
            end
        elseif btn == 2 then  -- right click: flag
            if not cell.revealed then
                cell.flagged = not cell.flagged
                mineCount = mineCount + (cell.flagged and -1 or 1)
            end
        end

    elseif ev == "key" then
        local key = args[1]
        if key == keys.escape then return false end
        if key == keys.r then
            initBoard()
            firstClick = true
        end
    end

    return true
end

return app
