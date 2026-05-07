-- CCOS Startup: bootstraps the kernel
-- Place this file at the root of your CC:Tweaked computer

local ok, err = pcall(function()
    if not fs.exists("/system/kernel.lua") then
        error("Kernel not found. Ensure /system/kernel.lua exists.")
    end
    dofile("/system/kernel.lua")
end)

if not ok then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.red)
    term.clear()
    term.setCursorPos(1, 1)
    print("=== CCOS BOOT FAILURE ===")
    print(tostring(err))
    print("")
    print("Press any key to exit.")
    os.pullEvent("key")
end
