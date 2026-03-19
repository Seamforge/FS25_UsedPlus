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
UsedPlus.VERSION = "2.15.4.74"  -- Synced by build.js from modDesc.xml
UsedPlus.DEBUG = false

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


UsedPlus.logInfo("UsedPlusCore loaded")
