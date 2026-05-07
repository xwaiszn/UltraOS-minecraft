-- /apps/pong.lua
-- CCOS Pong: single-player vs AI pong using kernel timer events.

local T = dofile("/system/theme.lua")
local app = { name = "Pong" }

local W, H
local closeBtn_r

-- ── Game constants ────────────────────────────────────────────────────────────
local TICK  = 0.05
local PAD_H = 5
local PAD_W = 1
local SCORE_WIN = 7

-- ── State ────────────────────────────────────────────────────────────────────
local playerY, aiY
local ballX, ballY
local ballDX, ballDY
local playerScore, aiScore
local timerID
local phase         -- "play" | "serve" | "win"
local winner
local serveTimer

-- ── Helpers ───────────────────────────────────────────────────────────────────
local GX1, GX2, GY1, GY2  -- game area bounds
local function initGeometry()
    W, H = term.getSize()
    GX1 = 3         -- left paddle x
    GX2 = W - 2     -- right paddle x
    GY1 = 3         -- top game row
    GY2 = H - 2     -- bottom game row
end

local function resetBall(toRight)
    ballX  = math.floor((GX1 + GX2) / 2)
    ballY  = math.floor((GY1 + GY2) / 2)
    ballDX = toRight and 1 or -1
    ballDY = (math.random(0, 1) == 0) and 1 or -1
end

local function resetGame()
    initGeometry()
    playerY     = math.floor((GY1 + GY2 - PAD_H) / 2)
    aiY         = playerY
    playerScore = 0
    aiScore     = 0
    phase       = "serve"
    serveTimer  = os.startTimer(1.5)
    resetBall(true)
    timerID = os.startTimer(TICK)
end

-- ── Draw ──────────────────────────────────────────────────────────────────────
function app.draw()
    W, H = term.getSize()
    -- Background
    term.setBackgroundColor(colors.black)
    for row = 1, H do
        term.setCursorPos(1, row)
        term.write(string.rep(" ", W))
    end

    -- Title / close
    term.setBackgroundColor(T.titleBar)
    term.setTextColor(T.accent)
    term.setCursorPos(1, 1)
    term.write(string.rep(" ", W))
    term.setCursorPos(3, 1)
    term.write(string.format("Pong   YOU %d  :  %d AI", playerScore, aiScore))
    term.setBackgroundColor(T.danger)
    term.setTextColor(T.dangerText)
    term.setCursorPos(W - 1, 1)
    term.write(" X")
    closeBtn_r = { x = W - 1, y = 1, w = 2, h = 1 }

    -- Top / bottom borders
    term.setBackgroundColor(T.dim)
    term.setCursorPos(1, GY1 - 1)
    term.write(string.rep("\140", W))
    term.setCursorPos(1, GY2 + 1)
    term.write(string.rep("\140", W))

    -- Center dashed line
    term.setBackgroundColor(colors.black)
    term.setTextColor(T.dim)
    local cx = math.floor((GX1 + GX2) / 2)
    for row = GY1, GY2 do
        if row % 2 == 0 then
            term.setCursorPos(cx, row)
            term.write("|")
        end
    end

    -- Player paddle (left)
    term.setBackgroundColor(T.accent)
    for row = 0, PAD_H - 1 do
        local ry = playerY + row
        if ry >= GY1 and ry <= GY2 then
            term.setCursorPos(GX1, ry)
            term.write(" ")
        end
    end

    -- AI paddle (right)
    term.setBackgroundColor(colors.red)
    for row = 0, PAD_H - 1 do
        local ry = aiY + row
        if ry >= GY1 and ry <= GY2 then
            term.setCursorPos(GX2, ry)
            term.write(" ")
        end
    end

    -- Ball
    term.setBackgroundColor(colors.white)
    term.setTextColor(colors.black)
    if ballX >= GX1 and ballX <= GX2 and ballY >= GY1 and ballY <= GY2 then
        term.setCursorPos(ballX, ballY)
        term.write("O")
    end

    -- Phase messages
    if phase == "serve" then
        term.setBackgroundColor(colors.black)
        term.setTextColor(T.dim)
        local msg = "Serving..."
        term.setCursorPos(math.floor(W / 2) - math.floor(#msg / 2), math.floor(H / 2))
        term.write(msg)
    elseif phase == "win" then
        term.setBackgroundColor(colors.black)
        term.setTextColor(T.accent)
        local msg  = (winner == "player") and "YOU WIN!" or "AI WINS!"
        local msg2 = "[R] Restart  [ESC] Exit"
        local cx2 = math.floor(W / 2)
        term.setCursorPos(cx2 - math.floor(#msg / 2), math.floor(H / 2) - 1)
        term.write(msg)
        term.setTextColor(T.dim)
        term.setCursorPos(cx2 - math.floor(#msg2 / 2), math.floor(H / 2))
        term.write(msg2)
    end

    -- Controls hint
    term.setBackgroundColor(colors.black)
    term.setTextColor(T.dim)
    term.setCursorPos(1, H)
    local hint = "  W/S or Up/Dn: move paddle | ESC: exit"
    term.write(hint:sub(1, W))
end

-- ── Tick ──────────────────────────────────────────────────────────────────────
local keysHeld = {}

local function tick()
    if phase ~= "play" then return end

    -- Player movement from held keys
    if keysHeld[keys.up] or keysHeld[keys.w] then
        playerY = math.max(GY1, playerY - 1)
    end
    if keysHeld[keys.down] or keysHeld[keys.s] then
        playerY = math.min(GY2 - PAD_H + 1, playerY + 1)
    end

    -- AI: simple tracking with speed limit
    local aiCenter = aiY + math.floor(PAD_H / 2)
    if ballY < aiCenter and aiY > GY1 then
        aiY = aiY - 1
    elseif ballY > aiCenter and aiY + PAD_H - 1 < GY2 then
        aiY = aiY + 1
    end

    -- Move ball
    ballX = ballX + ballDX
    ballY = ballY + ballDY

    -- Top/bottom bounce
    if ballY < GY1 then ballY = GY1 ; ballDY = 1 end
    if ballY > GY2 then ballY = GY2 ; ballDY = -1 end

    -- Left paddle collision (player)
    if ballX == GX1 and ballY >= playerY and ballY < playerY + PAD_H then
        ballDX = 1
        -- Angle based on hit position
        local relHit = ballY - (playerY + PAD_H / 2)
        ballDY = (relHit > 0) and 1 or ((relHit < 0) and -1 or ballDY)
        ballX  = GX1 + 1
    end

    -- Right paddle collision (AI)
    if ballX == GX2 and ballY >= aiY and ballY < aiY + PAD_H then
        ballDX = -1
        local relHit = ballY - (aiY + PAD_H / 2)
        ballDY = (relHit > 0) and 1 or ((relHit < 0) and -1 or ballDY)
        ballX  = GX2 - 1
    end

    -- Scoring
    if ballX < GX1 then
        aiScore = aiScore + 1
        if aiScore >= SCORE_WIN then
            phase  = "win"
            winner = "ai"
        else
            phase = "serve"
            serveTimer = os.startTimer(1.5)
            resetBall(true)
        end
    elseif ballX > GX2 then
        playerScore = playerScore + 1
        if playerScore >= SCORE_WIN then
            phase  = "win"
            winner = "player"
        else
            phase = "serve"
            serveTimer = os.startTimer(1.5)
            resetBall(false)
        end
    end
end

-- ── Init ─────────────────────────────────────────────────────────────────────
function app.init()
    math.randomseed(os.time())
    keysHeld = {}
    resetGame()
end

-- ── Event ─────────────────────────────────────────────────────────────────────
function app.event(ev, ...)
    local args = { ... }

    if ev == "timer" then
        if args[1] == timerID then
            tick()
            timerID = os.startTimer(TICK)
        elseif args[1] == serveTimer and phase == "serve" then
            phase = "play"
        end
        return true

    elseif ev == "key" then
        local key = args[1]
        if key == keys.escape then return false end
        if phase == "win" and key == keys.r then
            keysHeld = {}
            resetGame()
            return true
        end
        keysHeld[key] = true

    elseif ev == "key_up" then
        keysHeld[args[1]] = false

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
