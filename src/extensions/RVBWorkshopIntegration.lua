--[[
    FS25_UsedPlus - RVB Workshop Integration (Coordinator)

    When Real Vehicle Breakdowns (RVB) is installed, this extension:
    1. Hides our Inspect button (RVB has their own Workshop button)
    2. Injects UsedPlus data into RVB's Workshop Dialog settingsBox
    3. Adds our unique data (Hydraulics, Maintenance Grade) alongside RVB's info
    4. Adds a Repaint button to RVB's dialog (alongside Repair)
    5. Shows Mechanic's Assessment quote (workhorse/lemon hint)
    6. v2.2.0: Hooks RVB repair/service completion for DNA degradation
    7. v2.2.0: Monitors RVB faults for breakdown degradation

    The integration is seamless - our data appears in the same visual style
    as RVB's existing vehicle info rows.

    v2.1.1 - Fixed timing issue: Hook installed on first dialog open (not mission load)
             The rvbWorkshopDialog class doesn't exist until first opened by player
    v2.1.2 - Added Repaint button to RVB's Workshop dialog
    v2.3.1 - Added Mechanic's Assessment using workhorse/lemon quote system
    v2.2.0 - Progressive degradation: DNA affects RVB part lifetimes
             - Hooks RVB service/repair completion for repair degradation
             - Monitors RVB fault states for breakdown degradation
    v2.15.0 - Refactored into sub-modules:
              rvb/RVBRepairButton.lua    - Repair button hook & redirect
              rvb/RVBButtonInjection.lua - Repaint & Tires button injection
              rvb/RVBServiceHooks.lua    - Service button hook & fault tracking
              rvb/RVBDiagnostics.lua     - Data injection & hydraulic diagnostics
]]

-- Sub-modules have already created this table via `or {}` guards
RVBWorkshopIntegration = RVBWorkshopIntegration or {}

-- State fields (coordinator owns these)
RVBWorkshopIntegration.isInitialized = false
RVBWorkshopIntegration.isHooked = false
RVBWorkshopIntegration.showDialogHooked = false

-- v2.2.0: Track previous fault states for breakdown detection
RVBWorkshopIntegration.previousFaultStates = {}  -- { [vehicle] = { [partKey] = faultState, ... } }

-- v2.15.3: Hydraulic toggle state and cost for RVB repair integration
RVBWorkshopIntegration.hydraulicRepairRequested = false
RVBWorkshopIntegration.lastHydraulicRepairCost = 0

--[[
    Initialize the integration
    Called from main.lua after ModCompatibility.init()

    NOTE: We can't hook rvbWorkshopDialog.updateScreen here because the class
    doesn't exist yet! RVB creates it lazily on first open. Instead, we hook
    showDialog to catch when it's first opened and install our hook then.
]]
function RVBWorkshopIntegration:init()
    if self.isInitialized then
        UsedPlus.logDebug("RVBWorkshopIntegration already initialized")
        return
    end

    -- Only initialize if RVB is installed
    if not ModCompatibility or not ModCompatibility.rvbInstalled then
        UsedPlus.logDebug("RVBWorkshopIntegration: RVB not installed, skipping")
        return
    end

    -- Hook showDialog to catch when rvbWorkshopDialog is first opened
    self:hookShowDialog()

    self.isInitialized = true
    UsedPlus.logInfo("RVBWorkshopIntegration initialized - waiting for RVB Workshop to open")
end

--[[
    Hook g_gui.showDialog to detect when rvbWorkshopDialog is opened
    This is where we'll install our updateScreen hook
]]
function RVBWorkshopIntegration:hookShowDialog()
    if self.showDialogHooked then
        return
    end

    -- Store original showDialog function
    local originalShowDialog = g_gui.showDialog

    if originalShowDialog == nil then
        UsedPlus.logWarn("RVBWorkshopIntegration: g_gui.showDialog not found")
        return
    end

    -- Replace with hooked version
    g_gui.showDialog = function(guiSelf, name, ...)
        -- Call original first
        local result = originalShowDialog(guiSelf, name, ...)

        -- Check if this is the RVB Workshop dialog being opened
        if name == "rvbWorkshopDialog" then
            UsedPlus.logDebug("RVBWorkshopIntegration: rvbWorkshopDialog opened")

            -- Try to install our hook on the dialog class (only once)
            if not RVBWorkshopIntegration.isHooked then
                RVBWorkshopIntegration:tryHookUpdateScreen()
            end
        end

        return result
    end

    self.showDialogHooked = true
    UsedPlus.logInfo("RVBWorkshopIntegration: Hooked g_gui.showDialog for RVB detection")
end

--[[
    Try to hook rvbWorkshopDialog:updateScreen
    Called when the dialog is first opened (class now exists)
]]
function RVBWorkshopIntegration:tryHookUpdateScreen()
    if self.isHooked then
        return true
    end

    -- Method 1: Try global class (older RVB versions)
    local dialogClass = rvbWorkshopDialog

    -- Method 2: Try to get from g_gui.guis (dialog instance)
    if dialogClass == nil and g_gui and g_gui.guis then
        local guiEntry = g_gui.guis.rvbWorkshopDialog
        if guiEntry then
            -- The target contains the actual dialog controller
            dialogClass = guiEntry.target
            UsedPlus.logDebug("RVBWorkshopIntegration: Found dialog via g_gui.guis.rvbWorkshopDialog.target")
        end
    end

    -- Method 3: Try _G global table
    if dialogClass == nil and _G then
        dialogClass = _G.rvbWorkshopDialog
        if dialogClass then
            UsedPlus.logDebug("RVBWorkshopIntegration: Found dialog via _G.rvbWorkshopDialog")
        end
    end

    if dialogClass == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: rvbWorkshopDialog class still not found")
        -- Try to log what IS in g_gui.guis for debugging
        if g_gui and g_gui.guis and g_gui.guis.rvbWorkshopDialog then
            local entry = g_gui.guis.rvbWorkshopDialog
            UsedPlus.logDebug(string.format("RVBWorkshopIntegration: g_gui.guis.rvbWorkshopDialog exists, type=%s", type(entry)))
            if type(entry) == "table" then
                for k, v in pairs(entry) do
                    UsedPlus.logDebug(string.format("  .%s = %s", tostring(k), type(v)))
                end
            end
        end
        return false
    end

    -- Get the updateScreen function - could be on the class or metatable
    local originalUpdateScreen = dialogClass.updateScreen

    -- Try metatable if not found directly
    if originalUpdateScreen == nil then
        local mt = getmetatable(dialogClass)
        if mt and mt.__index then
            originalUpdateScreen = mt.__index.updateScreen
            UsedPlus.logDebug("RVBWorkshopIntegration: Found updateScreen in metatable")
        end
    end

    if originalUpdateScreen == nil then
        UsedPlus.logWarn("RVBWorkshopIntegration: rvbWorkshopDialog.updateScreen not found")
        -- Log available methods for debugging
        UsedPlus.logDebug("RVBWorkshopIntegration: Available methods on dialogClass:")
        for k, v in pairs(dialogClass) do
            if type(v) == "function" then
                UsedPlus.logDebug(string.format("  %s()", tostring(k)))
            end
        end
        return false
    end

    -- Replace with hooked version that dispatches to sub-modules
    -- SAFETY: Only injects into settingsBox (left side). Never touches diagnosticsList
    -- or its dataSource — that breaks RVB's toggle mechanism.
    dialogClass.updateScreen = function(dialogSelf)
        -- Call original first (this populates RVB's data and rebuilds settingsBox)
        local result = originalUpdateScreen(dialogSelf)

        -- Inject UsedPlus data into settingsBox (left side only)
        -- RVB deletes and rebuilds settingsBox each updateScreen, so we re-inject after
        pcall(RVBWorkshopIntegration.injectUsedPlusData, RVBWorkshopIntegration, dialogSelf)

        -- Append our hydraulic entry to partBreakdowns so RVB's onClickPart handles it
        -- RVB rebuilds partBreakdowns each updateScreen, so we re-append each time
        pcall(RVBWorkshopIntegration.injectHydraulicPartEntry, RVBWorkshopIntegration, dialogSelf)

        -- Hook setPartsRepairreq on the vehicle to intercept our fake part
        pcall(RVBWorkshopIntegration.hookSetPartsRepairreq, RVBWorkshopIntegration, dialogSelf)

        -- Check for new RVB faults for breakdown degradation tracking
        if dialogSelf.vehicle then
            pcall(RVBWorkshopIntegration.checkForNewFaults, RVBWorkshopIntegration, dialogSelf.vehicle)
        end

        return result
    end

    self.isHooked = true
    UsedPlus.logInfo("RVBWorkshopIntegration: Successfully hooked rvbWorkshopDialog.updateScreen!")

    -- First-open: hook diagnostics methods BEFORE first updateScreen with our hook
    -- This adds our hydraulic row to RVB's diagnostics list without wrapping the dataSource
    -- Must hook on the INSTANCE (the dataSource), not the class
    local dialogInstance = dialogClass
    if rvbWorkshopDialog and rvbWorkshopDialog.INSTANCE then
        dialogInstance = rvbWorkshopDialog.INSTANCE
        UsedPlus.logInfo("RVBWorkshopIntegration: Using rvbWorkshopDialog.INSTANCE for method hooks")
    end
    local hookOk, hookErr = pcall(RVBWorkshopIntegration.hookDiagnosticsMethods, RVBWorkshopIntegration, dialogInstance)
    if not hookOk then
        UsedPlus.logWarn("RVBWorkshopIntegration: hookDiagnosticsMethods failed: " .. tostring(hookErr))
    end

    -- First-open: inject buttons and hooks (these persist across updateScreen calls)
    pcall(RVBWorkshopIntegration.hookRepairButton, RVBWorkshopIntegration, dialogClass)
    pcall(RVBWorkshopIntegration.hookServiceButton, RVBWorkshopIntegration, dialogClass)

    if dialogClass.vehicle then
        pcall(RVBWorkshopIntegration.initializeFaultTracking, RVBWorkshopIntegration, dialogClass.vehicle)
    end

    pcall(RVBWorkshopIntegration.injectRepaintButton, RVBWorkshopIntegration, dialogClass)
    pcall(RVBWorkshopIntegration.injectTiresButton, RVBWorkshopIntegration, dialogClass)

    return true
end

--[[
    Delayed initialization (called after ModCompatibility.init)
]]
function RVBWorkshopIntegration:delayedInit()
    UsedPlus.logDebug("RVBWorkshopIntegration:delayedInit called")
    if not self.isInitialized then
        self:init()
    end
end

UsedPlus.logInfo("RVBWorkshopIntegration loaded")
