-- /apps/calculator.lua
-- CCOS Calculator: safe expression evaluator using a recursive-descent parser.
-- No load(), no loadstring(), no eval() — hand-written parser only.

local T = dofile("/system/theme.lua")
local app = { name = "Calculator" }

local W, H
local display    = "0"
local expression = ""
local history    = {}   -- list of strings
local MAX_HIST   = 8
local closeBtn_r = nil
local BTNS       = {}

-- ── Safe math parser ─────────────────────────────────────────────────────────
-- Grammar:
--   expr   = term   { ('+' | '-') term }
--   term   = factor { ('*' | '/') factor }
--   factor = unary
--   unary  = '-' unary | power
--   power  = atom '^' unary | atom
--   atom   = number | '(' expr ')' | func '(' expr ')'
--
-- Supported functions: sin, cos, tan, sqrt, abs, floor, ceil, log

local function parseError(msg) error("ParseError: " .. msg) end

local _src, _pos

local function peek() return _src:sub(_pos, _pos) end
local function advance() _pos = _pos + 1 end

local function skipWS()
    while _pos <= #_src and peek():match("%s") do advance() end
end

local function parseNumber()
    skipWS()
    local start = _pos
    if peek() == "-" then advance() end
    while _pos <= #_src and (peek():match("%d") or peek() == ".") do advance() end
    local s = _src:sub(start, _pos - 1)
    local n = tonumber(s)
    if not n then parseError("Expected number near pos " .. start) end
    return n
end

local function parseExpr()  -- forward declaration
end

local FUNCS = {
    sin = math.sin, cos = math.cos, tan = math.tan,
    sqrt = math.sqrt, abs = math.abs,
    floor = math.floor, ceil = math.ceil,
    log = math.log,
}

local function parseAtom()
    skipWS()
    local c = peek()
    if c == "(" then
        advance()
        local v = parseExpr()
        skipWS()
        if peek() ~= ")" then parseError("Expected ')'") end
        advance()
        return v
    end
    -- Function call?
    if c:match("%a") then
        local fname = ""
        while _pos <= #_src and peek():match("%a") do
            fname = fname .. peek()
            advance()
        end
        skipWS()
        if peek() ~= "(" then parseError("Unknown token: " .. fname) end
        advance()
        local arg = parseExpr()
        skipWS()
        if peek() ~= ")" then parseError("Expected ')' after function") end
        advance()
        local fn = FUNCS[fname]
        if not fn then parseError("Unknown function: " .. fname) end
        return fn(arg)
    end
    -- Plain number
    return parseNumber()
end

local function parseUnary()
    skipWS()
    if peek() == "-" then
        advance()
        return -parseUnary()
    end
    return parseAtom()
end

local function parsePower()
    local base = parseUnary()
    skipWS()
    if peek() == "^" then
        advance()
        local exp = parseUnary()
        return base ^ exp
    end
    return base
end

local function parseTerm()
    local v = parsePower()
    while true do
        skipWS()
        local c = peek()
        if c == "*" then
            advance()
            v = v * parsePower()
        elseif c == "/" then
            advance()
            local d = parsePower()
            if d == 0 then parseError("Division by zero") end
            v = v / d
        else
            break
        end
    end
    return v
end

parseExpr = function()
    local v = parseTerm()
    while true do
        skipWS()
        local c = peek()
        if c == "+" then
            advance()
            v = v + parseTerm()
        elseif c == "-" then
            advance()
            v = v - parseTerm()
        else
            break
        end
    end
    return v
end

local function evaluate(expr)
    if expr == "" then return nil, "Empty expression" end
    _src = expr
    _pos = 1
    local ok, result = pcall(parseExpr)
    if not ok then
        return nil, tostring(result):gsub("ParseError: ", "")
    end
    skipWS()
    if _pos <= #_src then
        return nil, "Unexpected '" .. peek() .. "'"
    end
    -- Format result
    if result ~= result then return nil, "Not a number" end
    if result == math.huge or result == -math.huge then return nil, "Overflow" end
    -- If integer, show without decimal
    if result == math.floor(result) and math.abs(result) < 1e12 then
        return tostring(math.floor(result)), nil
    end
    return string.format("%.8g", result), nil
end

-- ── Button layout ─────────────────────────────────────────────────────────────
local BTN_ROWS = {
    { "7", "8", "9", "/" },
    { "4", "5", "6", "*" },
    { "1", "2", "3", "-" },
    { "0", ".", "=", "+" },
    { "C", "DEL", "(", ")" },
    { "^", "sqrt(", "sin(", "cos(" },
}

local function buildButtons()
    BTNS = {}
    local btnW = 6
    local btnH = 1
    local startX = 2
    local startY = H - #BTN_ROWS - 1
    for row, rowBtns in ipairs(BTN_ROWS) do
        local y = startY + row - 1
        for col, label in ipairs(rowBtns) do
            local x = startX + (col - 1) * (btnW + 1)
            BTNS[#BTNS+1] = {
                label = label,
                x = x, y = y,
                w = btnW, h = btnH,
            }
        end
    end
end

-- ── Draw ─────────────────────────────────────────────────────────────────────
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
    term.write("Calculator")
    term.setBackgroundColor(T.danger)
    term.setTextColor(T.dangerText)
    term.setCursorPos(W - 1, 1)
    term.write(" X")
    closeBtn_r = { x = W - 1, y = 1, w = 2, h = 1 }

    -- Expression display
    term.setBackgroundColor(colors.black)
    term.setTextColor(T.dim)
    term.setCursorPos(1, 2)
    term.write(string.rep(" ", W))
    term.setCursorPos(2, 2)
    local expShow = expression:sub(-(W - 3))
    term.write(expShow)

    -- Result display
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 3)
    term.write(string.rep(" ", W))
    local dispShow = display:sub(-(W - 3))
    term.setCursorPos(W - 1 - #dispShow, 3)
    term.write(dispShow)

    -- History
    local histY = 4
    local histH = H - #BTN_ROWS - 4
    term.setBackgroundColor(T.panel)
    term.setTextColor(T.dim)
    for row = 0, histH - 1 do
        term.setCursorPos(1, histY + row)
        term.write(string.rep(" ", W))
    end
    local hStart = math.max(1, #history - histH + 1)
    for i = hStart, #history do
        local ry = histY + (i - hStart)
        if ry < histY + histH then
            term.setCursorPos(2, ry)
            term.write(history[i]:sub(1, W - 2))
        end
    end

    -- Buttons
    buildButtons()
    for _, b in ipairs(BTNS) do
        local isAccent = (b.label == "=" or b.label == "C")
        if isAccent then
            term.setBackgroundColor(T.accent)
            term.setTextColor(T.accentText)
        else
            term.setBackgroundColor(T.btnBg)
            term.setTextColor(T.btnText)
        end
        term.setCursorPos(b.x, b.y)
        local pad = b.w - #b.label
        local lp  = math.floor(pad / 2)
        local rp  = pad - lp
        term.write(string.rep(" ", lp) .. b.label .. string.rep(" ", rp))
    end
end

-- ── Input logic ───────────────────────────────────────────────────────────────
local function pressKey(label)
    if label == "C" then
        expression = ""
        display     = "0"
    elseif label == "DEL" then
        expression = expression:sub(1, -2)
        if expression == "" then display = "0"
        else display = expression end
    elseif label == "=" then
        if expression ~= "" then
            local result, err = evaluate(expression)
            if err then
                display = "Error: " .. err
                history[#history+1] = expression .. " = ERR"
            else
                history[#history+1] = expression .. " = " .. result
                if #history > MAX_HIST then
                    table.remove(history, 1)
                end
                display     = result
                expression  = result
            end
        end
    else
        expression = expression .. label
        display    = expression
    end
end

-- ── Init ─────────────────────────────────────────────────────────────────────
function app.init()
    W, H = term.getSize()
    expression = ""
    display    = "0"
    history    = {}
end

-- ── Event ─────────────────────────────────────────────────────────────────────
function app.event(ev, ...)
    local args = { ... }
    if ev == "mouse_click" then
        local btn, mx, my = args[1], args[2], args[3]
        if closeBtn_r and my == closeBtn_r.y and mx >= closeBtn_r.x then
            return false
        end
        for _, b in ipairs(BTNS) do
            if my == b.y and mx >= b.x and mx < b.x + b.w then
                pressKey(b.label)
                return true
            end
        end
    elseif ev == "key" then
        local key = args[1]
        if key == keys.escape then return false end
        if key == keys.enter  then pressKey("=") ; return true end
        if key == keys.backspace then pressKey("DEL") ; return true end
    elseif ev == "char" then
        local ch = args[1]
        local allowed = ch:match("[0-9%.%+%-%*/%(%)%^]")
        if allowed then pressKey(ch) end
    end
    return true
end

return app
