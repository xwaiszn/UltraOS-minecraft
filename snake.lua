-- /apps/snake.lua
-- CCOS Snake: real Snake game using the kernel event loop.
-- Uses os.startTimer for ticking; no inner blocking loops.

local T = dofile("/system/theme.lua")
local app = { name = "Snake" }

local W, H
local GW, GH      -- game grid dimensions
local GX, GY = 2, 3  -- grid top-left on screen

-- ── State ────────────────────────────────────────────────────────────────────
local snake        -- { {x,y}, ... } head at [1]
local dir          -- {dx, dy}
local nextDir      -- buffered next direction
local food         -- {x, y}
local score
local alive
local timerID
local TICK_INTERVAL = 0.15   -- seconds
local closeBtn_r

-- ── Helpers ──────────────────────────────────────────────────────────────────
local function spawnFood()
    -- Find a free cell
    local occupied = {}
    for _, seg in ipairs(snake) do
        occupied[seg.x .. "," .. seg.y] = true
    end
    local free = {}
    for y = 1, GH do
        for x = 1, GW do
            if not occupied[x .. "," .. y] then
                free[#free+1] = { x = x, y = y }
            end
        end
    end
    if #free == 0 then return nil end
    return free[math.random(#free)]
end

local function resetGame()
    GW = W - 3
    GH = H - 5
    local sx = math.floor(GW / 2)
    local sy = math.floor(GH / 2)
    snake    = { { x = sx, y = sy }, { x = sx - 1, y = sy }, { x = sx - 2, y = sy } }
    dir      = { dx = 1, dy = 0 }
    nextDir  = { dx = 1, dy = 0 }
    food     = spawnFood()
    score    = 0
    alive    = true
    timerID  = os.startTimer(TICK_INTERVAL)
end

-- ── Draw ─────────────────────────────────────────────────────────────────────
local function drawCell(x, y, bg, ch)
    term.setBackgroundColor(bg)
    term.setTextColor(colors.black)
    term.setCursorPos(GX + x - 1, GY + y - 1)
    term.write(ch or " ")
end

function app.draw()
    W, H = term.getSize()

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
    term.write("Snake  Score: " .. tostring(score or 0))
    term.setBackgroundColor(T.danger)
    term.setTextColor(T.dangerText)
    term.setCursorPos(W - 1, 1)
    term.write(" X")
    closeBtn_r = { x = W - 1, y = 1, w = 2, h = 1 }

    -- Border
    term.setBackgroundColor(T.dim)
    term.setTextColor(T.panel)
    -- Top border
    term.setCursorPos(GX - 1, GY - 1)
    term.write("+" .. string.rep("-", GW) .. "+")
    -- Bottom border
    term.setCursorPos(GX - 1, GY + GH)
    term.write("+" .. string.rep("-", GW) .. "+")
    for row = 1, GH do
        term.setCursorPos(GX - 1, GY + row - 1)
        term.write("|")
        term.setCursorPos(GX + GW, GY + row - 1)
        term.write("|")
    end

    -- Clear interior
    term.setBackgroundColor(colors.black)
    for row = 1, GH do
        term.setCursorPos(GX, GY + row - 1)
        term.write(string.rep(" ", GW))
    end

    if not alive then
        -- Game over overlay
        term.setBackgroundColor(colors.black)
        term.setTextColor(T.danger)
        local msg   = "  GAME OVER  Score: " .. score .. "  "
        local msg2  = "  [R] Restart  [ESC] Exit  "
        local cx = GX + math.floor((GW - #msg) / 2)
        local cy = GY + math.floor(GH / 2) - 1
        term.setCursorPos(cx, cy)
        term.write(msg)
        term.setTextColor(T.dim)
        term.setCursorPos(GX + math.floor((GW - #msg2) / 2), cy + 1)
        term.write(msg2)
        return
    end

    -- Draw food
    if food then
        drawCell(food.x, food.y, T.danger, "\7")
    end

    -- Draw snake
    for i, seg in ipairs(snake) do
        if i == 1 then
            drawCell(seg.x, seg.y, T.accent, "\2")
        else
            drawCell(seg.x, seg.y, colors.green, " ")
        end
    end

    -- Status
    term.setBackgroundColor(T.panel)
    term.setTextColor(T.dim)
    term.setCursorPos(1, H)
    local hint = "  Arrows/WASD: move | ESC: exit"
    term.write(hint:sub(1, W) .. string.rep(" ", W - math.min(#hint, W)))
end

-- ── Tick logic ────────────────────────────────────────────────────────────────
local function tick()
    if not alive then return end
    dir = nextDir

    local head   = snake[1]
    local newHead = { x = head.x + dir.dx, y = head.y + dir.dy }

    -- Wall collision
    if newHead.x < 1 or newHead.x > GW or newHead.y < 1 or newHead.y > GH then
        alive = false
        return
    end
    -- Self collision
    for _, seg in ipairs(snake) do
        if seg.x == newHead.x and seg.y == newHead.y then
            alive = false
            return
        end
    end

    table.insert(snake, 1, newHead)

    -- Food eaten?
    if food and newHead.x == food.x and newHead.y == food.y then
        score = score + 10
        food  = spawnFood()
        -- Speed up slightly
        if TICK_INTERVAL > 0.07 then
            TICK_INTERVAL = TICK_INTERVAL - 0.005
        end
    else
        table.remove(snake)  -- remove tail
    end
end

-- ── Init ─────────────────────────────────────────────────────────────────────
function app.init()
    W, H = term.getSize()
    math.randomseed(os.time())
    resetGame()
end

-- ── Event ─────────────────────────────────────────────────────────────────────
local DIR_MAP = {
    [keys.up]    = { dx =  0, dy = -1 },
    [keys.down]  = { dx =  0, dy =  1 },
    [keys.left]  = { dx = -1, dy =  0 },
    [keys.right] = { dx =  1, dy =  0 },
    [keys.w]     = { dx =  0, dy = -1 },
    [keys.s]     = { dx =  0, dy =  1 },
    [keys.a]     = { dx = -1, dy =  0 },
    [keys.d]     = { dx =  1, dy =  0 },
}

function app.event(ev, ...)
    local args = { ... }

    if ev == "timer" then
        if args[1] == timerID then
            tick()
            timerID = alive and os.startTimer(TICK_INTERVAL) or nil
        end
        return true

    elseif ev == "key" then
        local key = args[1]
        if key == keys.escape then return false end
        if not alive then
            if key == keys.r then
                TICK_INTERVAL = 0.15
                resetGame()
            end
            return true
        end
        local newDir = DIR_MAP[key]
        if newDir then
            -- Prevent 180-degree reversal
            if not (newDir.dx == -dir.dx and newDir.dy == -dir.dy) then
                nextDir = newDir
            end
        end

    elseif ev == "mouse_click" then
        local btn, mx, my = args[1], args[2], args[3]
        if closeBtn_r and my == closeBtn_r.y and mx >= closeBtn_r.x then
            if timerID then os.cancelTimer(timerID) end
            return false
        end
    end

    return true
end

function app.unload()
    if timerID then os.cancelTimer(timerID) end
end

return app
