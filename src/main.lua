--[[
    FS25_UsedPlus - Main Initialization

    main.lua is the entry point that initializes the mod
    Pattern from: EnhancedLoanSystem, BuyUsedEquipment main initialization
    Reference: FS25_ADVANCED_PATTERNS.md - Game System Modification via Function Hooking

    Responsibilities:
    - Initialize global managers (g_financeManager, g_usedVehicleManager)
    - Hook into mission lifecycle (load, save, start)
    - Extend game classes (Farm, ShopConfigScreen, etc.)
    - Register GUI screens
    - Subscribe to game events

    Load order:
    - UsedPlusCore.lua loads FIRST (defines UsedPlus global and logging)
    - This file loads LAST (after all dependencies) to set up lifecycle hooks
]]

-- UsedPlus global is already defined by UsedPlusCore.lua
-- Just set up the class metatable for instance methods
local UsedPlus_mt = Class(UsedPlus)

--[[
    Constructor
    Creates singleton instance
]]
function UsedPlus.new()
    local self = setmetatable({}, UsedPlus_mt)

    self.isInitialized = false

    return self
end

--[[
    Initialize mod after mission loads
    Called from mission lifecycle hook
]]
function UsedPlus:initialize()
    if self.isInitialized then
        UsedPlus.logWarn("Already initialized, skipping")
        return
    end

    UsedPlus.logInfo("Initializing mod...")

    -- Create global managers (pattern from EnhancedLoanSystem)
    g_financeManager = FinanceManager.new()

    -- UsedVehicleManager: Only initialize if BUE not integrated
    if ModCompatibility.shouldInitUsedVehicleManager() then
        g_usedVehicleManager = UsedVehicleManager.new()
        UsedPlus.logInfo("UsedVehicleManager initialized")
    else
        g_usedVehicleManager = nil
        UsedPlus.logInfo("UsedVehicleManager skipped - BuyUsedEquipment handles used search")
    end

    g_vehicleSaleManager = VehicleSaleManager.new()  -- NEW - Agent-based vehicle sales

    -- Register managers with mission for event handling
    if g_currentMission then
        addModEventListener(g_financeManager)
        if g_usedVehicleManager ~= nil then
            addModEventListener(g_usedVehicleManager)
        end
        addModEventListener(g_vehicleSaleManager)  -- NEW
    end

    -- Initialize extensions that require delayed initialization
    -- Note: ShopConfigScreenExtension and InGameMenuMapFrameExtension
    -- install hooks at load time with safety checks

    if FarmlandManagerExtension and FarmlandManagerExtension.init then
        FarmlandManagerExtension:init()
    end

    if VehicleExtension and VehicleExtension.init then
        VehicleExtension:init()
    end

    -- Initialize vehicle sell hook (ESC -> Vehicles -> Sell button)
    -- This must be called after mission loads because InGameMenuVehiclesFrame
    -- may not exist at script load time
    if InGameMenuVehiclesFrameExtension and InGameMenuVehiclesFrameExtension.init then
        InGameMenuVehiclesFrameExtension:init()
    end

    -- Initialize workshop screen hook (Repair/Repaint screen -> Inspect button)
    if WorkshopScreenExtension and WorkshopScreenExtension.init then
        WorkshopScreenExtension:init()
    end

    -- v2.8.0: Initialize placeable financing hooks (Construction menu)
    -- BuyPlaceableData and Placeable classes may not exist at script load time
    if BuyPlaceableDataExtension and BuyPlaceableDataExtension.init then
        BuyPlaceableDataExtension:init()
    end
    if PlaceableSystemExtension and PlaceableSystemExtension.init then
        PlaceableSystemExtension:init()
    end

    -- v2.1.0: Initialize RVB Workshop integration (injects UsedPlus data into RVB dialog)
    -- This may need delayed init since RVB may not be fully loaded yet
    if RVBWorkshopIntegration and RVBWorkshopIntegration.init then
        RVBWorkshopIntegration:init()
    end

    -- Register GUI screens (will be populated when GUI classes exist)
    -- g_gui:loadProfiles is handled by modDesc.xml <gui> entries

    -- Register all dialogs with DialogLoader for centralized lazy loading
    if DialogLoader and DialogLoader.registerAll then
        DialogLoader.registerAll()

        -- Pre-load problem dialogs that fail with lazy loading
        -- These dialogs have XML parsing issues when loaded on-demand, so load them upfront
        UsedPlus.logWarn("Pre-loading problem dialogs at startup...")
        DialogLoader.ensureLoaded("SearchDetailsDialog")
        DialogLoader.ensureLoaded("CreditReportDialog")
        DialogLoader.ensureLoaded("UsedSearchDialog")
        DialogLoader.ensureLoaded("PaymentHistoryDialog")
        UsedPlus.logWarn("Pre-loading complete")
    end

    -- Register input actions for hotkeys
    self:registerInputActions()

    self.isInitialized = true

    UsedPlus.logInfo("Initialization complete")
    UsedPlus.logDebug("FinanceManager: " .. tostring(g_financeManager ~= nil))
    UsedPlus.logDebug("UsedVehicleManager: " .. tostring(g_usedVehicleManager ~= nil))
end

--[[
    Mission lifecycle hooks
    Pattern from: EnhancedLoanSystem, BuyUsedEquipment
    Hook into mission load/save/start for mod integration
]]

-- Hook mission load finished (before mission starts)
Mission00.loadMission00Finished = Utils.appendedFunction(
    Mission00.loadMission00Finished,
    function(mission)
        UsedPlus.logWarn("Mission00.loadMission00Finished hook fired")

        if UsedPlus.instance == nil then
            UsedPlus.instance = UsedPlus.new()
        end

        UsedPlus.instance:initialize()

        -- v2.8.0: Initialize VehicleInfoExtension hook (Vehicle class now available)
        if VehicleInfoExtension and VehicleInfoExtension.init then
            VehicleInfoExtension.init()
        end

        -- v2.8.0: FALLBACK - If FSBaseMission.loadItemsFinished hook didn't fire,
        -- try to get missionInfo directly from the mission object
        if UsedPlus.pendingMissionInfo == nil then
            UsedPlus.logWarn("pendingMissionInfo is nil - trying to get missionInfo from mission object...")

            -- Try various ways to get missionInfo
            local missionInfo = nil

            -- Method 1: mission.missionInfo (common pattern)
            if mission and mission.missionInfo then
                missionInfo = mission.missionInfo
                UsedPlus.logWarn("Got missionInfo from mission.missionInfo")
            end

            -- Method 2: g_currentMission.missionInfo
            if missionInfo == nil and g_currentMission and g_currentMission.missionInfo then
                missionInfo = g_currentMission.missionInfo
                UsedPlus.logWarn("Got missionInfo from g_currentMission.missionInfo")
            end

            -- Method 3: Try g_careerScreen (for career mode)
            if missionInfo == nil and g_careerScreen and g_careerScreen.currentSavegame then
                -- Build missionInfo-like object from savegame data
                local savegame = g_careerScreen.currentSavegame
                if savegame and savegame.savegameDirectory then
                    missionInfo = { savegameDirectory = savegame.savegameDirectory }
                    UsedPlus.logWarn("Built missionInfo from g_careerScreen.currentSavegame")
                end
            end

            -- Method 4: Try to find savegameDirectory from g_currentMission
            if missionInfo == nil and g_currentMission then
                local savegameDir = g_currentMission.savegameDirectory
                if savegameDir then
                    missionInfo = { savegameDirectory = savegameDir }
                    UsedPlus.logWarn("Built missionInfo from g_currentMission.savegameDirectory")
                end
            end

            if missionInfo then
                UsedPlus.pendingMissionInfo = missionInfo
                UsedPlus.logWarn(string.format("Fallback succeeded: savegameDirectory=%s",
                    missionInfo.savegameDirectory or "nil"))
            else
                UsedPlus.logError("CRITICAL: Could not get missionInfo from any source!")
            end
        end

        -- v2.8.0: DON'T load savegame data here - farms don't exist yet!
        -- Moved to onStartMission where farms are guaranteed to be loaded

        -- v1.8.0: Initialize cross-mod compatibility (RVB, UYT detection)
        ModCompatibility.init()

        -- v2.1.0: Delayed RVB integration init (RVB may have loaded after our init())
        if RVBWorkshopIntegration and RVBWorkshopIntegration.delayedInit then
            RVBWorkshopIntegration:delayedInit()
        end
    end
)

-- Hook mission start (after map fully loaded)
Mission00.onStartMission = Utils.appendedFunction(
    Mission00.onStartMission,
    function(mission)
        UsedPlus.logWarn("Mission00.onStartMission hook fired")

        -- v2.8.0: NOW load savegame data - farms are guaranteed to exist at this point!
        -- Check if farms exist
        local farm1 = g_farmManager and g_farmManager:getFarmById(1)
        UsedPlus.logWarn(string.format("Farm check: g_farmManager=%s, farm1=%s",
            tostring(g_farmManager ~= nil), tostring(farm1 ~= nil)))

        if farm1 then
            UsedPlus.loadSavegameData()
        else
            UsedPlus.logError("CRITICAL: Farm 1 still doesn't exist in onStartMission!")
        end

        -- Initialize managers (call loadMapFinished)
        UsedPlus.logDebug("Initializing managers...")
        if g_financeManager and g_financeManager.loadMapFinished then
            g_financeManager:loadMapFinished()
            UsedPlus.logDebug("FinanceManager initialized")
        end

        if g_usedVehicleManager and g_usedVehicleManager.loadMapFinished then
            g_usedVehicleManager:loadMapFinished()
            UsedPlus.logDebug("UsedVehicleManager initialized")
        end

        -- NEW - Initialize Vehicle Sale Manager for agent-based sales
        if g_vehicleSaleManager and g_vehicleSaleManager.loadMapFinished then
            g_vehicleSaleManager:loadMapFinished()
            UsedPlus.logDebug("VehicleSaleManager initialized")
        end

        -- v2.0.0: Initialize Difficulty Scaling Manager (GMNGjoy pattern)
        if g_difficultyScalingManager and g_difficultyScalingManager.init then
            g_difficultyScalingManager:init()
            UsedPlus.logDebug("DifficultyScalingManager initialized")
        end

        -- v2.0.0: Initialize Bank Interest Manager (Evan Kirsch pattern)
        if g_bankInterestManager and g_bankInterestManager.init then
            g_bankInterestManager:init()
            UsedPlus.logDebug("BankInterestManager initialized")
        end

        -- ESC InGameMenu integration using EnhancedLoanSystem pattern
        UsedPlus.logDebug("Adding InGameMenu (ESC) integration...")

        -- Create frame instance and store global reference for refresh
        local financeFrame = FinanceManagerFrame.new()
        g_usedPlusFinanceFrame = financeFrame

        -- Load GUI XML
        local xmlPath = Utils.getFilename("gui/FinanceManagerFrame.xml", UsedPlus.MOD_DIR)
        g_gui:loadGui(xmlPath, "usedPlusManager", financeFrame, true)

        -- Initialize frame
        if financeFrame then
            -- Add to InGameMenu (following EnhancedLoanSystem pattern)
            UsedPlus.addInGameMenuPage(financeFrame, "InGameMenuUsedPlus", {0, 0, 1024, 1024}, 3, function() return true end)
            UsedPlus.logInfo("Finance Manager page added to InGameMenu (ESC)")
        else
            UsedPlus.logError("Failed to create FinanceManagerFrame")
        end
    end
)

-- ESC Menu integration moved to loadMapFinished hook (see below)

-- Shop Menu Page Injection Function
-- Pattern from GarageMenu mod (working example)
function UsedPlus.addShopMenuPage(frame, pageName, uvs, predicateFunc, insertAfter)
    UsedPlus.logDebug(string.format("addShopMenuPage called for: %s", pageName))

    -- Remove existing control ID to avoid warnings
    g_shopMenu.controlIDs[pageName] = nil

    -- Find insertion position
    local targetPosition = 0
    for i = 1, #g_shopMenu.pagingElement.elements do
        local child = g_shopMenu.pagingElement.elements[i]
        if child == g_shopMenu[insertAfter] then
            targetPosition = i + 1
            break
        end
    end
    UsedPlus.logTrace(string.format("  Target position: %d", targetPosition))

    -- Add frame to menu
    g_shopMenu[pageName] = frame
    g_shopMenu.pagingElement:addElement(g_shopMenu[pageName])
    g_shopMenu:exposeControlsAsFields(pageName)
    UsedPlus.logTrace("  Added to shop menu")

    -- Reorder in elements array
    for i = 1, #g_shopMenu.pagingElement.elements do
        local child = g_shopMenu.pagingElement.elements[i]
        if child == g_shopMenu[pageName] then
            table.remove(g_shopMenu.pagingElement.elements, i)
            table.insert(g_shopMenu.pagingElement.elements, targetPosition, child)
            break
        end
    end

    -- Reorder in pages array
    for i = 1, #g_shopMenu.pagingElement.pages do
        local child = g_shopMenu.pagingElement.pages[i]
        if child.element == g_shopMenu[pageName] then
            table.remove(g_shopMenu.pagingElement.pages, i)
            table.insert(g_shopMenu.pagingElement.pages, targetPosition, child)
            break
        end
    end
    UsedPlus.logTrace("  Reordered in arrays")

    -- Update layout
    g_shopMenu.pagingElement:updateAbsolutePosition()
    g_shopMenu.pagingElement:updatePageMapping()

    -- Register page with predicate
    g_shopMenu:registerPage(g_shopMenu[pageName], nil, predicateFunc)
    UsedPlus.logTrace("  Registered page")

    -- Add tab icon
    local iconFileName = Utils.getFilename("icon.dds", UsedPlus.MOD_DIR)
    g_shopMenu:addPageTab(g_shopMenu[pageName], iconFileName, GuiUtils.getUVs(uvs))
    UsedPlus.logTrace("  Added icon tab")

    -- Reorder in pageFrames array
    for i = 1, #g_shopMenu.pageFrames do
        local child = g_shopMenu.pageFrames[i]
        if child == g_shopMenu[pageName] then
            table.remove(g_shopMenu.pageFrames, i)
            table.insert(g_shopMenu.pageFrames, targetPosition, child)
            break
        end
    end

    -- Rebuild tab list
    g_shopMenu:rebuildTabList()
    UsedPlus.logDebug("  Shop menu page injection complete")
end

-- InGame Menu Page Injection Function
-- Pattern from EnhancedLoanSystem mod (proven working example)
function UsedPlus.addInGameMenuPage(frame, pageName, uvs, position, predicateFunc)
    UsedPlus.logDebug(string.format("addInGameMenuPage called for: %s at position %d", pageName, position))

    -- Get InGameMenu controller
    local inGameMenu = g_gui.screenControllers[InGameMenu]

    if not inGameMenu then
        UsedPlus.logError("InGameMenu controller not found")
        return
    end

    -- Remove existing control ID to avoid warnings
    inGameMenu.controlIDs[pageName] = nil
    UsedPlus.logTrace("  Cleared control ID")

    -- Add frame to menu
    inGameMenu[pageName] = frame
    inGameMenu.pagingElement:addElement(inGameMenu[pageName])
    UsedPlus.logTrace("  Frame added to pagingElement")

    -- Expose controls as fields
    inGameMenu:exposeControlsAsFields(pageName)

    -- Reorder in elements array
    for i = 1, #inGameMenu.pagingElement.elements do
        local child = inGameMenu.pagingElement.elements[i]
        if child == inGameMenu[pageName] then
            table.remove(inGameMenu.pagingElement.elements, i)
            table.insert(inGameMenu.pagingElement.elements, position, child)
            UsedPlus.logTrace(string.format("  Reordered in elements array at index %d", position))
            break
        end
    end

    -- Reorder in pages array
    for i = 1, #inGameMenu.pagingElement.pages do
        local child = inGameMenu.pagingElement.pages[i]
        if child.element == inGameMenu[pageName] then
            table.remove(inGameMenu.pagingElement.pages, i)
            table.insert(inGameMenu.pagingElement.pages, position, child)
            UsedPlus.logTrace(string.format("  Reordered in pages array at index %d", position))
            break
        end
    end

    -- Update layout
    inGameMenu.pagingElement:updateAbsolutePosition()
    inGameMenu.pagingElement:updatePageMapping()
    UsedPlus.logTrace("  Layout updated")

    -- Register page with predicate
    inGameMenu:registerPage(inGameMenu[pageName], position, predicateFunc)
    UsedPlus.logTrace("  Page registered")

    -- Add tab icon
    local iconFileName = Utils.getFilename("icon.dds", UsedPlus.MOD_DIR)
    inGameMenu:addPageTab(inGameMenu[pageName], iconFileName, GuiUtils.getUVs(uvs))
    UsedPlus.logTrace("  Tab icon added")

    -- Reorder in pageFrames array
    for i = 1, #inGameMenu.pageFrames do
        local child = inGameMenu.pageFrames[i]
        if child == inGameMenu[pageName] then
            table.remove(inGameMenu.pageFrames, i)
            table.insert(inGameMenu.pageFrames, position, child)
            UsedPlus.logTrace(string.format("  Reordered in pageFrames array at index %d", position))
            break
        end
    end

    -- Rebuild tab list
    inGameMenu:rebuildTabList()
    UsedPlus.logDebug("  InGameMenu integration complete!")
end

-- v2.8.1: Removed FSBaseMission.loadItemsFinished hook (doesn't exist in FS25)
-- The existing Mission00.loadMission00Finished and FSBaseMission.onStartMission hooks work correctly

--[[
    Load savegame data after managers are created
    Called from Mission00.loadMission00Finished after initialize()
]]
function UsedPlus.loadSavegameData()
    local missionInfo = UsedPlus.pendingMissionInfo
    if missionInfo == nil then
        -- v2.8.0: Upgrade to WARN so we can diagnose persistence issues
        UsedPlus.logWarn("loadSavegameData: No pending missionInfo (new game or hook didn't fire)")
        return
    end

    -- v2.8.0: WARN so it always shows for persistence debugging
    UsedPlus.logWarn(string.format("loadSavegameData: Loading from %s",
        missionInfo.savegameDirectory or "nil"))

    if g_financeManager then
        g_financeManager:loadFromXMLFile(missionInfo)
    else
        UsedPlus.logWarn("g_financeManager is nil, cannot load finance data!")
    end

    if g_usedVehicleManager then
        g_usedVehicleManager:loadFromXMLFile(missionInfo)
    else
        UsedPlus.logWarn("g_usedVehicleManager is nil, cannot load used vehicle data!")
    end

    if g_vehicleSaleManager then
        g_vehicleSaleManager:loadFromXMLFile(missionInfo)
    else
        UsedPlus.logWarn("g_vehicleSaleManager is nil, cannot load sale data!")
    end

    -- v2.9.0: Load Service Truck Discovery state
    if ServiceTruckDiscovery then
        local savegameDir = missionInfo.savegameDirectory
        if savegameDir then
            local xmlPath = savegameDir .. "/usedPlus_serviceTruckDiscovery.xml"
            if fileExists(xmlPath) then
                local xmlFile = XMLFile.load("serviceTruckDiscovery", xmlPath)
                if xmlFile then
                    ServiceTruckDiscovery.loadFromXML(xmlFile, "serviceTruckDiscovery")
                    xmlFile:delete()
                    UsedPlus.logInfo("Service Truck Discovery data loaded")
                end
            end
        end
    end

    -- v2.9.6: Initialize settings system with dual-persistence
    if UsedPlusSettings and UsedPlusSettings.init then
        UsedPlusSettings:init(missionInfo.savegameDirectory)
    else
        UsedPlus.logWarn("UsedPlusSettings is nil, cannot load settings!")
    end

    UsedPlus.logInfo("Savegame data loaded successfully")

    -- Clear the stored missionInfo
    UsedPlus.pendingMissionInfo = nil
end

-- Hook savegame save (save mod data to savegame)
FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(
    FSCareerMissionInfo.saveToXMLFile,
    function(missionInfo)
        -- v2.8.0: WARN level for persistence debugging
        UsedPlus.logWarn(string.format("saveToXMLFile hook: Saving to %s",
            missionInfo and missionInfo.savegameDirectory or "nil"))

        if g_financeManager then
            g_financeManager:saveToXMLFile(missionInfo)
        end

        if g_usedVehicleManager then
            g_usedVehicleManager:saveToXMLFile(missionInfo)
        end

        -- NEW - Save vehicle sale listings
        if g_vehicleSaleManager then
            g_vehicleSaleManager:saveToXMLFile(missionInfo)
        end

        -- v2.9.0: Save Service Truck Discovery state
        if ServiceTruckDiscovery and missionInfo and missionInfo.savegameDirectory then
            local xmlPath = missionInfo.savegameDirectory .. "/usedPlus_serviceTruckDiscovery.xml"
            local xmlFile = XMLFile.create("serviceTruckDiscovery", xmlPath, "serviceTruckDiscovery")
            if xmlFile then
                ServiceTruckDiscovery.saveToXML(xmlFile, "serviceTruckDiscovery")
                xmlFile:save()
                xmlFile:delete()
                UsedPlus.logInfo("Service Truck Discovery data saved")
            end
        end

        -- v2.9.6: Save settings to savegame
        if UsedPlusSettings and UsedPlusSettings.saveToXMLFile then
            UsedPlusSettings:saveToXMLFile(missionInfo)
        end

        UsedPlus.logWarn("saveToXMLFile hook: Complete")
    end
)

--[[
    Farm class extension
    Pattern from: BuyUsedEquipment FarmExtension
    Add custom data to Farm for tracking deals and searches
]]

-- Extend Farm constructor to add custom data
local originalFarmNew = Farm.new
function Farm.new(...)
    local farm = originalFarmNew(...)

    if farm ~= nil then
        -- v2.8.0: Check if arrays already exist (don't overwrite loaded data!)
        if farm.usedVehicleSearches == nil then
            farm.financeDeals = {}        -- Active finance/lease deals
            farm.usedVehicleSearches = {} -- Active search requests (for buying)
            farm.vehicleSaleListings = {} -- NEW - Active sale listings (for selling)
        else
            -- Arrays already exist - log this unusual case
            UsedPlus.logWarn(string.format("Farm.new: Farm %d already has usedVehicleSearches (%d items) - preserving!",
                farm.farmId or 0, #farm.usedVehicleSearches))
        end
    end

    return farm
end

-- Extend Farm save to persist custom data
Farm.saveToXMLFile = Utils.appendedFunction(
    Farm.saveToXMLFile,
    function(self, xmlFile, key)
        -- Farm-specific data saved by managers
        -- This hook ensures farm extensions are preserved
    end
)

-- Extend Farm load to restore custom data
local originalFarmLoadFromXMLFile = Farm.loadFromXMLFile
function Farm.loadFromXMLFile(self, xmlFile, key)
    local success = originalFarmLoadFromXMLFile(self, xmlFile, key)

    if success then
        -- v2.8.0: Preserve existing data if already populated by UsedPlus load
        local hadSearches = self.usedVehicleSearches ~= nil and #self.usedVehicleSearches > 0
        self.financeDeals = self.financeDeals or {}
        self.usedVehicleSearches = self.usedVehicleSearches or {}
        self.vehicleSaleListings = self.vehicleSaleListings or {}

        if hadSearches then
            UsedPlus.logWarn(string.format("Farm.loadFromXMLFile: Farm %d preserved %d searches",
                self.farmId or 0, #self.usedVehicleSearches))
        end
    end

    return success
end

--[[
    Input action registration
    Allows player to open Finance Manager with hotkey (Ctrl+F)
]]
function UsedPlus:registerInputActions()
    -- Input action defined in modDesc.xml <actions>
    -- Action name: USEDPLUS_OPEN_FINANCE_MANAGER

    -- Register input action handler
    local _, eventId = g_inputBinding:registerActionEvent(
        InputAction.USEDPLUS_OPEN_FINANCE_MANAGER,
        self,
        function()
            UsedPlus.instance:onOpenFinanceManager()
        end,
        false,
        true,
        false,
        true
    )

    if eventId then
        g_inputBinding:setActionEventText(eventId, g_i18n:getText("usedplus_action_openFinanceManager"))
        g_inputBinding:setActionEventTextVisibility(eventId, true)
        UsedPlus.logInfo("Finance Manager hotkey registered (Shift+F)")
    end
end

--[[
    Open Finance Manager dialog
    Called by hotkey or ESC menu button
]]
function UsedPlus:onOpenFinanceManager()
    -- Open Finance Manager Frame
    local financeManagerFrame = g_gui:showDialog("FinanceManagerFrame")
    if financeManagerFrame then
        UsedPlus.logDebug("Finance Manager opened")
    else
        UsedPlus.logError("Failed to open Finance Manager")
    end
end

--[[
    ESC Menu Integration
    v2.7.2: Finance Manager accessible via Shift+F hotkey
    ESC menu button integration deferred (low priority since hotkey works well)
]]

--[[
    Cleanup on mission unload
    Free resources and unregister managers
]]
Mission00.delete = Utils.prependedFunction(
    Mission00.delete,
    function(mission)
        UsedPlus.logInfo("Mission unloading, cleaning up")

        -- Managers handle their own cleanup via delete()
        if g_financeManager then
            g_financeManager:delete()
            g_financeManager = nil
        end

        if g_usedVehicleManager then
            g_usedVehicleManager:delete()
            g_usedVehicleManager = nil
        end

        -- NEW - Cleanup vehicle sale manager
        if g_vehicleSaleManager then
            g_vehicleSaleManager:delete()
            g_vehicleSaleManager = nil
        end

        if UsedPlus.instance then
            UsedPlus.instance.isInitialized = false
        end
    end
)

--[[
    Console commands (admin-level)
    Pattern from: MoneyCommandMod
    Available to admins regardless of debug mode
]]

-- Admin permission check (3-tier system from MoneyCommandMod)
function UsedPlus:isAdmin()
    if g_currentMission:getIsServer() then
        return true
    elseif g_currentMission.isMasterUser then
        return true
    elseif g_currentMission.userManager and g_currentMission.userManager:getUserByUserId(g_currentMission.playerUserId) then
        local user = g_currentMission.userManager:getUserByUserId(g_currentMission.playerUserId)
        if user and user:getIsMasterUser() then
            return true
        end
    end
    return false
end

-- Add money console command
-- NOTE: Console commands use UsedPlus table directly (not instance) because addConsoleCommand
-- is called at load time before instance exists. We use UsedPlus.isAdmin() as static function.
addConsoleCommand("upAddMoney", "Add money to your farm (admin only). Usage: upAddMoney <amount>", "consoleCommandAddMoney", UsedPlus)

function UsedPlus.consoleCommandAddMoney(self, amountStr)
    -- Check admin permissions
    if not self:isAdmin() then
        return "Error: Only administrators can use this command."
    end

    -- Validate amount parameter
    local amount = tonumber(amountStr)
    if not amount then
        return "Error: Invalid amount. Usage: upAddMoney <amount>"
    end

    -- Get current farm
    if not g_currentMission then
        return "Error: Not in a game."
    end

    local farm = g_farmManager:getFarmById(g_currentMission:getFarmId())
    if not farm then
        return "Error: Farm not found."
    end

    -- Add/remove money
    farm:changeBalance(amount, MoneyType.OTHER)

    local action = amount >= 0 and "added to" or "removed from"
    UsedPlus.logInfo(string.format("%s %s farm (new balance: %s)",
        g_i18n:formatMoney(math.abs(amount), 0, true, true),
        action,
        g_i18n:formatMoney(farm.money, 0, true, true)))

    return string.format("%s %s your farm. New balance: %s",
        g_i18n:formatMoney(math.abs(amount), 0, true, true),
        action,
        g_i18n:formatMoney(farm.money, 0, true, true))
end

-- Set money console command (sets exact amount)
addConsoleCommand("upSetMoney", "Set your farm's money to exact amount (admin only). Usage: upSetMoney <amount>", "consoleCommandSetMoney", UsedPlus)

function UsedPlus.consoleCommandSetMoney(self, amountStr)
    -- Check admin permissions
    if not self:isAdmin() then
        return "Error: Only administrators can use this command."
    end

    -- Validate amount parameter
    local amount = tonumber(amountStr)
    if not amount or amount < 0 then
        return "Error: Invalid amount. Usage: upSetMoney <amount> (must be >= 0)"
    end

    -- Get current farm
    if not g_currentMission then
        return "Error: Not in a game."
    end

    local farm = g_farmManager:getFarmById(g_currentMission:getFarmId())
    if not farm then
        return "Error: Farm not found."
    end

    -- Calculate difference and apply
    local currentMoney = farm.money
    local difference = amount - currentMoney
    farm:changeBalance(difference, MoneyType.OTHER)

    UsedPlus.logInfo(string.format("Farm money set to %s (was %s)",
        g_i18n:formatMoney(amount, 0, true, true),
        g_i18n:formatMoney(currentMoney, 0, true, true)))

    return string.format("Farm money set to %s (was %s)",
        g_i18n:formatMoney(amount, 0, true, true),
        g_i18n:formatMoney(currentMoney, 0, true, true))
end

-- Set credit score console command (for testing)
addConsoleCommand("upSetCredit", "Adjust credit score factors (admin only). Usage: upSetCredit info", "consoleCommandSetCredit", UsedPlus)

function UsedPlus.consoleCommandSetCredit(self, action)
    -- Check admin permissions
    if not self:isAdmin() then
        return "Error: Only administrators can use this command."
    end

    -- Get current farm
    if not g_currentMission then
        return "Error: Not in a game."
    end

    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)
    if not farm then
        return "Error: Farm not found."
    end

    -- Calculate and display credit info
    local score = CreditScore.calculate(farmId)
    local rating, level = CreditScore.getRating(score)
    local adjustment = CreditScore.getInterestAdjustment(score)
    local assets = CreditScore.calculateAssets(farm)
    local debt = CreditScore.calculateDebt(farm)
    local ratio = assets > 0 and (debt / assets * 100) or 0

    UsedPlus.logInfo("=== Credit Score Report ===")
    UsedPlus.logInfo(string.format("  Score: %d (%s)", score, rating))
    UsedPlus.logInfo(string.format("  Interest Adjustment: %+.1f%%", adjustment))
    UsedPlus.logInfo(string.format("  Total Assets: %s", g_i18n:formatMoney(assets, 0, true, true)))
    UsedPlus.logInfo(string.format("  Total Debt: %s", g_i18n:formatMoney(debt, 0, true, true)))
    UsedPlus.logInfo(string.format("  Debt-to-Asset Ratio: %.1f%%", ratio))
    UsedPlus.logInfo("===========================")

    return string.format("Credit Score: %d (%s) | Interest: %+.1f%% | Debt Ratio: %.1f%%",
        score, rating, adjustment, ratio)
end

-- Pay off all finance deals (admin command)
addConsoleCommand("upPayoffAll", "Pay off all finance deals instantly (admin only)", "consoleCommandPayoffAll", UsedPlus)

function UsedPlus.consoleCommandPayoffAll(self)
    -- Check admin permissions
    if not self:isAdmin() then
        return "Error: Only administrators can use this command."
    end

    if not g_financeManager then
        return "Error: Finance Manager not initialized."
    end

    local farmId = g_currentMission:getFarmId()
    local deals = g_financeManager:getDealsForFarm(farmId)

    if not deals or #deals == 0 then
        return "No active finance deals to pay off."
    end

    local paidCount = 0
    local totalPaid = 0

    for _, deal in ipairs(deals) do
        if deal.status == "active" then
            local balance = deal.currentBalance or 0
            deal.currentBalance = 0
            deal.status = "paid"
            deal.monthsPaid = deal.termMonths
            paidCount = paidCount + 1
            totalPaid = totalPaid + balance
        end
    end

    UsedPlus.logInfo(string.format("Paid off %d deals, total: %s",
        paidCount, g_i18n:formatMoney(totalPaid, 0, true, true)))

    return string.format("Paid off %d deals (%s total)", paidCount,
        g_i18n:formatMoney(totalPaid, 0, true, true))
end

-- Admin Control Panel console command (admin only)
addConsoleCommand("upAdminCP", "Open UsedPlus Admin Control Panel (admin only, must be in vehicle)", "consoleCommandAdminCP", UsedPlus)

function UsedPlus.consoleCommandAdminCP(self)
    -- Check admin permissions
    if not self:isAdmin() then
        return "Error: Only administrators can use this command."
    end

    -- Must be in a vehicle - try multiple detection methods
    local vehicle = nil

    -- Method 1: Check HUD controlled vehicle (most reliable when in vehicle)
    if g_currentMission.hud and g_currentMission.hud.controlledVehicle then
        vehicle = g_currentMission.hud.controlledVehicle
    end

    -- Method 2: Fallback to standard controlledVehicle
    if vehicle == nil and g_currentMission.controlledVehicle then
        vehicle = g_currentMission.controlledVehicle
    end

    -- Method 3: Check if player is entered in any vehicle
    if vehicle == nil and g_currentMission.player then
        -- Iterate through all vehicles to find one the player is in
        for _, v in pairs(g_currentMission.vehicles) do
            if v.getIsEntered and v:getIsEntered() then
                vehicle = v
                break
            end
        end
    end

    if vehicle == nil then
        return "Error: Must be in a vehicle to open Admin Panel."
    end

    -- Open the Admin Control Panel
    DialogLoader.show("AdminControlPanel", "setVehicle", vehicle)

    return "Opening Admin Control Panel..."
end

--[[
    Debug console commands (if DEBUG mode enabled)
    Useful for testing and troubleshooting
]]
if UsedPlus.DEBUG then
    -- Add console command to check credit score
    addConsoleCommand("upCreditScore", "Display current farm's credit score", "consoleCommandCreditScore", UsedPlus)

    function UsedPlus:consoleCommandCreditScore()
        local farmId = g_currentMission.player.farmId
        local score = CreditScore.calculate(farmId)
        local rating, level = CreditScore.getRating(score)

        UsedPlus.logInfo(string.format("Credit Score: %d (%s)", score, rating))

        return string.format("Credit Score: %d (%s)", score, rating)
    end

    -- Add console command to list active deals
    addConsoleCommand("upListDeals", "List all active finance/lease deals", "consoleCommandListDeals", UsedPlus)

    function UsedPlus:consoleCommandListDeals()
        if g_financeManager == nil then
            UsedPlus.logWarn("FinanceManager not initialized")
            return "FinanceManager not initialized"
        end

        local farmId = g_currentMission.player.farmId
        local deals = g_financeManager:getDealsForFarm(farmId)

        if #deals == 0 then
            UsedPlus.logInfo("No active deals for farm " .. farmId)
            return "No active deals"
        end

        UsedPlus.logInfo(string.format("Active deals for farm %d:", farmId))
        for i, deal in ipairs(deals) do
            UsedPlus.logInfo(string.format("  %d. %s - $%.2f balance, %d/%d months",
                i, deal.itemName, deal.currentBalance, deal.monthsPaid, deal.termMonths))
        end

        return string.format("%d active deals", #deals)
    end

    -- Add console command to list active searches
    addConsoleCommand("upListSearches", "List all active used vehicle searches", "consoleCommandListSearches", UsedPlus)

    function UsedPlus:consoleCommandListSearches()
        if g_usedVehicleManager == nil then
            UsedPlus.logWarn("UsedVehicleManager not initialized")
            return "UsedVehicleManager not initialized"
        end

        local farmId = g_currentMission.player.farmId
        local farm = g_farmManager:getFarmById(farmId)

        if farm.usedVehicleSearches == nil or #farm.usedVehicleSearches == 0 then
            UsedPlus.logInfo("No active searches for farm " .. farmId)
            return "No active searches"
        end

        UsedPlus.logInfo(string.format("Active searches for farm %d:", farmId))
        for i, search in ipairs(farm.usedVehicleSearches) do
            UsedPlus.logInfo(string.format("  %d. %s - %s, TTL: %d hours",
                i, search.storeItemName, search:getTierName(), search.ttl))
        end

        return string.format("%d active searches", #farm.usedVehicleSearches)
    end

    -- ========== v2.8.0: MALFUNCTION DEBUG COMMANDS ==========
    -- These commands allow testing of malfunction system without waiting for random events

    addConsoleCommand("upStall", "Force engine stall on current vehicle", "consoleCommandStall", UsedPlus)

    function UsedPlus:consoleCommandStall()
        local vehicle = g_currentMission.controlledVehicle
        if not vehicle then
            return "Error: Not in a vehicle"
        end

        local spec = vehicle.spec_usedPlusMaintenance
        if not spec then
            return "Error: Vehicle has no UsedPlus maintenance data"
        end

        if UsedPlusMaintenance and UsedPlusMaintenance.triggerEngineStall then
            UsedPlusMaintenance.triggerEngineStall(vehicle)
            return "Triggered engine stall on " .. (vehicle:getName() or "vehicle")
        else
            return "Error: triggerEngineStall function not found"
        end
    end

    addConsoleCommand("upMisfire", "Force engine misfire on current vehicle", "consoleCommandMisfire", UsedPlus)

    function UsedPlus:consoleCommandMisfire()
        local vehicle = g_currentMission.controlledVehicle
        if not vehicle then
            return "Error: Not in a vehicle"
        end

        local spec = vehicle.spec_usedPlusMaintenance
        if not spec then
            return "Error: Vehicle has no UsedPlus maintenance data"
        end

        -- Simulate a misfire by setting the state directly
        local config = UsedPlusMaintenance.CONFIG
        spec.misfireActive = true
        spec.misfireEndTime = (g_currentMission.time or 0) + math.random(config.misfireDurationMin, config.misfireDurationMax)
        UsedPlusMaintenance.recordMalfunctionTime(vehicle)

        return "Triggered engine misfire on " .. (vehicle:getName() or "vehicle")
    end

    addConsoleCommand("upSurge", "Force hydraulic surge on current vehicle", "consoleCommandSurge", UsedPlus)

    function UsedPlus:consoleCommandSurge()
        local vehicle = g_currentMission.controlledVehicle
        if not vehicle then
            return "Error: Not in a vehicle"
        end

        local spec = vehicle.spec_usedPlusMaintenance
        if not spec then
            return "Error: Vehicle has no UsedPlus maintenance data"
        end

        local config = UsedPlusMaintenance.CONFIG
        local currentTime = g_currentMission.time or 0

        spec.hydraulicSurgeActive = true
        spec.hydraulicSurgeEndTime = currentTime + math.random(config.hydraulicSurgeDurationMin, config.hydraulicSurgeDurationMax)
        spec.hydraulicSurgeFadeStartTime = spec.hydraulicSurgeEndTime - config.hydraulicSurgeFadeTime
        spec.hydraulicSurgeDirection = math.random() < 0.5 and -1 or 1
        UsedPlusMaintenance.recordMalfunctionTime(vehicle)

        local directionText = spec.hydraulicSurgeDirection < 0 and "left" or "right"
        return string.format("Triggered hydraulic surge (%s) on %s", directionText, vehicle:getName() or "vehicle")
    end

    addConsoleCommand("upOverheat", "Force overheating on current vehicle", "consoleCommandOverheat", UsedPlus)

    function UsedPlus:consoleCommandOverheat()
        local vehicle = g_currentMission.controlledVehicle
        if not vehicle then
            return "Error: Not in a vehicle"
        end

        local spec = vehicle.spec_usedPlusMaintenance
        if not spec then
            return "Error: Vehicle has no UsedPlus maintenance data"
        end

        -- Set engine temperature to critical level
        spec.engineTemperature = 0.85
        spec.hasShownOverheatWarning = false
        spec.hasShownOverheatCritical = false
        UsedPlusMaintenance.recordMalfunctionTime(vehicle)

        return "Set engine temperature to 85% (overheating threshold) on " .. (vehicle:getName() or "vehicle")
    end

    addConsoleCommand("upCutout", "Force electrical cutout on current vehicle", "consoleCommandCutout", UsedPlus)

    function UsedPlus:consoleCommandCutout()
        local vehicle = g_currentMission.controlledVehicle
        if not vehicle then
            return "Error: Not in a vehicle"
        end

        local spec = vehicle.spec_usedPlusMaintenance
        if not spec then
            return "Error: Vehicle has no UsedPlus maintenance data"
        end

        if UsedPlusMaintenance and UsedPlusMaintenance.triggerImplementCutout then
            UsedPlusMaintenance.triggerImplementCutout(vehicle)
            return "Triggered electrical cutout on " .. (vehicle:getName() or "vehicle")
        else
            return "Error: triggerImplementCutout function not found"
        end
    end

    addConsoleCommand("upFlatTire", "Force flat tire on current vehicle", "consoleCommandFlatTire", UsedPlus)

    function UsedPlus:consoleCommandFlatTire()
        local vehicle = g_currentMission.controlledVehicle
        if not vehicle then
            return "Error: Not in a vehicle"
        end

        local spec = vehicle.spec_usedPlusMaintenance
        if not spec then
            return "Error: Vehicle has no UsedPlus maintenance data"
        end

        spec.hasFlatTire = true
        spec.flatTireSide = math.random() < 0.5 and -1 or 1
        spec.hasShownFlatTireWarning = true
        spec.failureCount = (spec.failureCount or 0) + 1
        UsedPlusMaintenance.recordMalfunctionTime(vehicle)

        local sideText = spec.flatTireSide < 0 and "left" or "right"
        return string.format("Triggered flat tire (%s side) on %s", sideText, vehicle:getName() or "vehicle")
    end

    addConsoleCommand("upRunaway", "Force engine runaway on current vehicle", "consoleCommandRunaway", UsedPlus)

    function UsedPlus:consoleCommandRunaway()
        local vehicle = g_currentMission.controlledVehicle
        if not vehicle then
            return "Error: Not in a vehicle"
        end

        local spec = vehicle.spec_usedPlusMaintenance
        if not spec then
            return "Error: Vehicle has no UsedPlus maintenance data"
        end

        spec.runawayActive = true
        spec.runawayStartTime = g_currentMission.time or 0
        spec.runawayPreviousSpeed = vehicle.getLastSpeed and vehicle:getLastSpeed() or 0
        spec.runawayPreviousDamage = vehicle:getVehicleDamage() or 0
        UsedPlusMaintenance.recordMalfunctionTime(vehicle)

        UsedPlusMaintenance.showWarning(vehicle,
            g_i18n:getText("usedplus_warning_runaway") or "ENGINE RUNAWAY! Governor failure - TURN OFF ENGINE!",
            5000, "runaway")

        return "Triggered engine runaway on " .. (vehicle:getName() or "vehicle")
    end

    addConsoleCommand("upSeizure", "Force engine seizure on current vehicle (PERMANENT)", "consoleCommandSeizure", UsedPlus)

    function UsedPlus:consoleCommandSeizure()
        local vehicle = g_currentMission.controlledVehicle
        if not vehicle then
            return "Error: Not in a vehicle"
        end

        local spec = vehicle.spec_usedPlusMaintenance
        if not spec then
            return "Error: Vehicle has no UsedPlus maintenance data"
        end

        if UsedPlusMaintenance and UsedPlusMaintenance.seizeComponent then
            UsedPlusMaintenance.seizeComponent(vehicle, "engine")
            return "PERMANENT: Engine seized on " .. (vehicle:getName() or "vehicle") .. " - requires major repair!"
        else
            return "Error: seizeComponent function not found"
        end
    end

    addConsoleCommand("upMalfInfo", "Show malfunction state for current vehicle", "consoleCommandMalfInfo", UsedPlus)

    function UsedPlus:consoleCommandMalfInfo()
        local vehicle = g_currentMission.controlledVehicle
        if not vehicle then
            return "Error: Not in a vehicle"
        end

        local spec = vehicle.spec_usedPlusMaintenance
        if not spec then
            return "Error: Vehicle has no UsedPlus maintenance data"
        end

        local config = UsedPlusMaintenance.CONFIG
        local currentTime = (g_currentMission.time or 0) / 1000
        local lastMalf = spec.lastMalfunctionTime or 0
        local cooldown = config.globalMalfunctionCooldown or 45
        local remaining = math.max(0, cooldown - (currentTime - lastMalf))

        local isFieldWork = UsedPlusMaintenance.isDoingFieldWork and UsedPlusMaintenance.isDoingFieldWork(vehicle) or false

        local info = string.format(
            "=== Malfunction State for %s ===\n" ..
            "Overall Reliability: %.1f%%\n" ..
            "Engine: %.1f%% | Hydraulic: %.1f%% | Electrical: %.1f%%\n" ..
            "DNA (Workhorse/Lemon): %.2f\n" ..
            "Last Malfunction: %.1fs ago\n" ..
            "Cooldown Remaining: %.1fs\n" ..
            "Field Work Active: %s\n" ..
            "Seizures: Engine=%s, Hydraulic=%s, Electrical=%s\n" ..
            "Flat Tire: %s | Runaway: %s | Overheating: %s",
            vehicle:getName() or "vehicle",
            ((spec.engineReliability or 1) + (spec.hydraulicReliability or 1) + (spec.electricalReliability or 1)) / 3 * 100,
            (spec.engineReliability or 1) * 100,
            (spec.hydraulicReliability or 1) * 100,
            (spec.electricalReliability or 1) * 100,
            spec.workhorseLemonScale or 0.5,
            currentTime - lastMalf,
            remaining,
            isFieldWork and "Yes" or "No",
            spec.engineSeized and "SEIZED" or "OK",
            spec.hydraulicsSeized and "SEIZED" or "OK",
            spec.electricalSeized and "SEIZED" or "OK",
            spec.hasFlatTire and "YES" or "No",
            spec.runawayActive and "ACTIVE" or "No",
            spec.engineTemperature and spec.engineTemperature > 0.6 and string.format("%.0f%%", spec.engineTemperature * 100) or "No"
        )

        -- Print to log and return summary
        print(info)
        return string.format("Reliability: %.0f%%, Cooldown: %.1fs remaining",
            ((spec.engineReliability or 1) + (spec.hydraulicReliability or 1) + (spec.electricalReliability or 1)) / 3 * 100,
            remaining)
    end

    addConsoleCommand("upResetCooldown", "Reset malfunction cooldown for current vehicle", "consoleCommandResetCooldown", UsedPlus)

    function UsedPlus:consoleCommandResetCooldown()
        local vehicle = g_currentMission.controlledVehicle
        if not vehicle then
            return "Error: Not in a vehicle"
        end

        local spec = vehicle.spec_usedPlusMaintenance
        if not spec then
            return "Error: Vehicle has no UsedPlus maintenance data"
        end

        spec.lastMalfunctionTime = 0
        return "Reset malfunction cooldown for " .. (vehicle:getName() or "vehicle")
    end

    -- Service Truck Discovery commands (v2.9.0)
    addConsoleCommand("upDiscoverServiceTruck", "Trigger Service Truck discovery (bypasses prerequisites)", "consoleCommandDiscoverServiceTruck", UsedPlus)

    function UsedPlus:consoleCommandDiscoverServiceTruck()
        local farmId = g_currentMission:getFarmId()
        if not farmId or farmId == 0 then
            return "Error: No valid farm"
        end

        if not ServiceTruckDiscovery then
            return "Error: ServiceTruckDiscovery not loaded"
        end

        -- Force trigger discovery (bypasses prerequisites and RNG)
        ServiceTruckDiscovery.triggerDiscovery(farmId, "console_command")
        return string.format("Service Truck discovery triggered for farm %d! Check for popup.", farmId)
    end

    addConsoleCommand("upResetServiceTruck", "Reset Service Truck discovery state (for retesting)", "consoleCommandResetServiceTruck", UsedPlus)

    function UsedPlus:consoleCommandResetServiceTruck()
        local farmId = g_currentMission:getFarmId()
        if not farmId or farmId == 0 then
            return "Error: No valid farm"
        end

        if not ServiceTruckDiscovery then
            return "Error: ServiceTruckDiscovery not loaded"
        end

        ServiceTruckDiscovery.resetDiscovery(farmId)
        return string.format("Service Truck discovery state reset for farm %d. Can be discovered again.", farmId)
    end

    addConsoleCommand("upServiceTruckStatus", "Show Service Truck discovery prerequisites status", "consoleCommandServiceTruckStatus", UsedPlus)

    function UsedPlus:consoleCommandServiceTruckStatus()
        local farmId = g_currentMission:getFarmId()
        if not farmId or farmId == 0 then
            return "Error: No valid farm"
        end

        if not ServiceTruckDiscovery then
            return "Error: ServiceTruckDiscovery not loaded"
        end

        local prereqs = ServiceTruckDiscovery.getPrerequisitesStatus(farmId)
        local status = ServiceTruckDiscovery.getDiscoveryStatus(farmId)

        local lines = {
            "=== Service Truck Discovery Status ===",
            string.format("Farm ID: %d", farmId),
            "",
            "Prerequisites:",
            string.format("  OBD Uses: %d / %d %s", prereqs.obdUses, prereqs.obdRequired, prereqs.obdMet and "[OK]" or "[X]"),
            string.format("  Credit Score: %d / %d %s", prereqs.creditScore, prereqs.creditRequired, prereqs.creditMet and "[OK]" or "[X]"),
            string.format("  Has Degraded Vehicle: %s %s", prereqs.hasDegradedVehicle and "Yes" or "No", prereqs.ceilingMet and "[OK]" or "[X]"),
            "",
            "Discovery State:",
            string.format("  Discovered: %s", status.hasDiscovered and "Yes" or "No"),
            string.format("  Purchased: %s", status.hasPurchased and "Yes" or "No"),
            string.format("  Opportunity Active: %s", status.opportunityActive and "Yes" or "No"),
            string.format("  Remaining Days: %d", status.remainingDays or 0),
            string.format("  Eligible Transactions: %d", status.eligibleTransactions or 0),
        }

        for _, line in ipairs(lines) do
            print(line)
        end

        return "Status printed to console"
    end
end

UsedPlus.logInfo("Main initialization loaded")
