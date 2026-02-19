--[[
    FS25_UsedPlus - Core Module

    This file MUST load FIRST before all other UsedPlus files.
    Defines the UsedPlus global and logging functions that all other files depend on.

    Load order in modDesc.xml:
    1. UsedPlusCore.lua (this file) - defines globals
    2. All other files - can use UsedPlus.logInfo(), etc.
    3. main.lua - extends UsedPlus with initialization logic
]]

-- Define global UsedPlus table
UsedPlus = {}

-- Mod metadata
UsedPlus.MOD_NAME = "FS25_UsedPlus"
UsedPlus.MOD_DIR = g_currentModDirectory
UsedPlus.VERSION = "2.15.0.35"  -- Synced by build.js from modDesc.xml
UsedPlus.DEBUG = false  -- v2.13.3: Disabled — set to true for development only

-- Log levels control what gets printed
UsedPlus.LOG_LEVEL = {
    ERROR = 1,    -- Always printed
    WARN = 2,     -- Always printed
    INFO = 3,     -- Only when DEBUG = true
    DEBUG = 4,    -- Only when DEBUG = true
    TRACE = 5,    -- Only when DEBUG = true (verbose)
}

--[[
    Centralized logging function
    @param message - The message to log
    @param level - Log level (default: INFO)
    @param prefix - Optional prefix (default: "UsedPlus")
]]
function UsedPlus.log(message, level, prefix)
    level = level or UsedPlus.LOG_LEVEL.INFO
    prefix = prefix or "UsedPlus"

    -- Always print errors and warnings
    if level <= UsedPlus.LOG_LEVEL.WARN then
        print(string.format("[%s] %s", prefix, message))
        return
    end

    -- Only print info/debug/trace when DEBUG is enabled
    if UsedPlus.DEBUG then
        print(string.format("[%s] %s", prefix, message))
    end
end

-- Convenience logging functions
function UsedPlus.logError(message, prefix)
    UsedPlus.log("ERROR: " .. message, UsedPlus.LOG_LEVEL.ERROR, prefix)
end

function UsedPlus.logWarn(message, prefix)
    UsedPlus.log("WARN: " .. message, UsedPlus.LOG_LEVEL.WARN, prefix)
end

function UsedPlus.logInfo(message, prefix)
    UsedPlus.log(message, UsedPlus.LOG_LEVEL.INFO, prefix)
end

function UsedPlus.logDebug(message, prefix)
    UsedPlus.log(message, UsedPlus.LOG_LEVEL.DEBUG, prefix)
end

function UsedPlus.logTrace(message, prefix)
    UsedPlus.log(message, UsedPlus.LOG_LEVEL.TRACE, prefix)
end

--[[
    DEBUG UTILITY: Dump complete GUI state for forensic analysis
    Use only for debugging GUI/dialog issues - should not be called in production code
    @param context - String describing when/where this dump was taken
]]
function UsedPlus.dumpGuiState(context)
    UsedPlus.logInfo(string.format("┌─── GUI STATE DUMP: %s ───", context))

    -- Current GUI
    local currentGui = g_gui.currentGui
    UsedPlus.logInfo(string.format("│ currentGui: %s", currentGui and currentGui.name or "nil"))
    if currentGui then
        UsedPlus.logInfo(string.format("│   - isOpen: %s", tostring(currentGui.isOpen)))
        UsedPlus.logInfo(string.format("│   - isVisible: %s", tostring(currentGui.isVisible)))
    end

    -- Current modal
    local currentModal = g_gui.currentModal
    UsedPlus.logInfo(string.format("│ currentModal: %s", currentModal and currentModal.name or "nil"))

    -- Dialog visibility
    local dialogVisible = g_gui:getIsDialogVisible()
    UsedPlus.logInfo(string.format("│ isDialogVisible: %s", tostring(dialogVisible)))

    -- Check our specific dialog
    local ourDialog = g_gui.guis["UnifiedPurchaseDialogPlaceable"]
    if ourDialog then
        UsedPlus.logInfo(string.format("│ UnifiedPurchaseDialogPlaceable exists: true"))
        UsedPlus.logInfo(string.format("│   - isOpen: %s", tostring(ourDialog.isOpen)))
        UsedPlus.logInfo(string.format("│   - isVisible: %s", tostring(ourDialog.isVisible)))
        UsedPlus.logInfo(string.format("│   - target: %s", tostring(ourDialog.target)))
    else
        UsedPlus.logInfo(string.format("│ UnifiedPurchaseDialogPlaceable: NOT IN g_gui.guis"))
    end

    -- GUI screens stack
    if g_gui.screenStack and #g_gui.screenStack > 0 then
        UsedPlus.logInfo(string.format("│ screenStack (%d items):", #g_gui.screenStack))
        for i, screen in ipairs(g_gui.screenStack) do
            UsedPlus.logInfo(string.format("│   [%d] %s", i, screen.name or "unnamed"))
        end
    else
        UsedPlus.logInfo("│ screenStack: empty")
    end

    -- Dialogs stack
    if g_gui.dialogs and #g_gui.dialogs > 0 then
        UsedPlus.logInfo(string.format("│ dialogs stack (%d items):", #g_gui.dialogs))
        for i, dialog in ipairs(g_gui.dialogs) do
            UsedPlus.logInfo(string.format("│   [%d] %s (visible=%s)",
                i,
                dialog.name or "unnamed",
                tostring(dialog.isVisible)))
        end
    else
        UsedPlus.logInfo("│ dialogs stack: empty")
    end

    UsedPlus.logInfo("└────────────────────────────────────")
end

UsedPlus.logInfo("UsedPlusCore loaded")
