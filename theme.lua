-- /system/theme.lua
-- Shared color constants.  Apps dofile() this instead of ui.lua
-- to avoid re-running the full UI subsystem.

return {
    bg         = colors.gray,
    panel      = colors.black,
    panelText  = colors.white,
    accent     = colors.cyan,
    accentText = colors.black,
    dim        = colors.lightGray,
    danger     = colors.red,
    dangerText = colors.white,
    titleBar   = colors.black,
    titleText  = colors.cyan,
    btnBg      = colors.lightGray,
    btnText    = colors.black,
    selectBg   = colors.cyan,
    selectText = colors.black,
    inputBg    = colors.white,
    inputText  = colors.black,
}
