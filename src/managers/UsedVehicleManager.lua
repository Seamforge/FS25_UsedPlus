--[[
    FS25_UsedPlus - Used Vehicle Manager (CORE)

    v2.7.2 REFACTORED: This is the core manager file.
    Implementation functions have been extracted to usedvehicle/ modules:
    - VehicleSearchSystem.lua   - Search processing, notifications, listing generation
    - VehicleSpawning.lua       - Purchase, spawn, apply condition, dirt, configs
    - VehicleInspection.lua     - Inspection system (request, process, notify)
    - VehiclePersistence.lua    - Save/load XML persistence

    This file contains:
    - Constructor and data structures
    - Lifecycle (loadMapFinished, onHourChanged, delete)
    - Search management (createSearchRequest, registerSearch, cancelSearch)
    - ID generation (generateSearchId, generateListingId)
    - Data access (getSearchesForFarm, getListingsForFarm, getSearchById)
    - Purchase completion helpers
    - Listing management
    - BuyVehicleData hook for applying used condition
]]

-- Use existing table if modules have loaded, otherwise create new
UsedVehicleManager = UsedVehicleManager or {}
local UsedVehicleManager_mt = Class(UsedVehicleManager)

--[[
    Constructor
    Creates manager instance with empty data structures
]]
function UsedVehicleManager.new()
    local self = setmetatable({}, UsedVehicleManager_mt)

    -- Data structures
    self.activeSearches = {}  -- All searches indexed by ID
    self.nextSearchId = 1

    -- Pending used vehicle purchases - tracks listings that need condition applied after spawn
    self.pendingUsedPurchases = {}

    -- v2.7.0: Track total game hours for inspection timing
    self.totalGameHours = 0

    -- Event subscriptions
    self.isServer = g_currentMission:getIsServer()
    self.isClient = g_currentMission:getIsClient()

    return self
end

--[[
    Initialize manager after mission loads
    Subscribe to hourly events for queue processing
]]
function UsedVehicleManager:loadMapFinished()
    if self.isServer then
        g_messageCenter:subscribe(MessageType.HOUR_CHANGED, self.onHourChanged, self)
        -- v2.13.2: Subscribe to sleep state changes (Issue #7)
        g_messageCenter:subscribe(MessageType.SLEEPING, self.onSleepingStateChanged, self)
        self.lastProcessedDay = g_currentMission.environment.currentDay
        UsedPlus.logDebug("UsedVehicleManager subscribed to HOUR_CHANGED, SLEEPING (v2.13.2)")
    end
end

--[[
    Hourly queue processing
    v2.7.0: Checks for day change (1 game day = 1 month) to process monthly success rolls
    v2.7.0: Also tracks total hours and checks for inspection completions EVERY hour
]]
function UsedVehicleManager:onHourChanged()
    if not self.isServer then return end

    -- Check if used vehicle search system is enabled
    local searchEnabled = not UsedPlusSettings or UsedPlusSettings:get("enableUsedVehicleSearch") ~= false
    if not searchEnabled then
        UsedPlus.logDebug("UsedVehicleManager: Search system disabled, skipping HOUR_CHANGED processing")
        return
    end

    -- Track hours for inspection timing
    local lastHour = self.totalGameHours or 0
    self.totalGameHours = lastHour + 1

    -- Check for inspection completions EVERY hour (calls into VehicleInspection module)
    self:processInspectionCompletions()

    local currentDay = g_currentMission.environment.currentDay
    local lastProcessedDay = self.lastProcessedDay or currentDay

    -- Calculate days jumped (handles time skips)
    local daysJumped = currentDay - lastProcessedDay
    if daysJumped <= 0 then
        return
    end

    self.lastProcessedDay = currentDay
    UsedPlus.logDebug(string.format("Processing %d day(s) of search checks (day %d → %d)",
        daysJumped, lastProcessedDay, currentDay))

    -- Process each skipped day
    -- v2.15.0: Track which farms had changes for sync
    local farmsWithChanges = {}

    for dayOffset = 1, daysJumped do
        for _, farm in pairs(g_farmManager:getFarms()) do
            if farm.usedVehicleSearches and #farm.usedVehicleSearches > 0 then
                -- Calls into VehicleSearchSystem module
                self:processSearchesForFarm(farm.farmId, farm)
                farmsWithChanges[farm.farmId] = true
            end
        end
    end

    -- v2.15.0: Broadcast updated search state to all clients
    if g_server ~= nil then
        for farmId, _ in pairs(farmsWithChanges) do
            SyncSearchesEvent.broadcastFullForFarm(farmId)
        end
    end
end

--[[
    v2.13.2: Handle sleep state changes (Issue #7)
    When player wakes up, log for debugging. Inspection/search dialogs deferred during sleep
    are handled via notifications - player can access from portfolio menu.
]]
function UsedVehicleManager:onSleepingStateChanged(isSleeping)
    if not isSleeping then
        UsedPlus.logDebug("UsedVehicleManager: Player woke up - deferred dialogs available via portfolio")
    end
end

--[[
    Create new search request
    Called from network event (client request → server execution)
]]
function UsedVehicleManager:createSearchRequest(farmId, storeItemIndex, storeItemName, basePrice, searchLevel, requestedConfigId)
    if not self.isServer then
        UsedPlus.logError("createSearchRequest must be called on server")
        return nil
    end

    if searchLevel < 1 or searchLevel > 3 then
        UsedPlus.logError(string.format("Invalid search level %d", searchLevel))
        return nil
    end

    local search = UsedVehicleSearch.new(farmId, storeItemIndex, storeItemName, basePrice, searchLevel, requestedConfigId)
    search.id = self:generateSearchId()
    self:registerSearch(search)

    -- Deduct retainer fee
    g_currentMission:addMoney(-search.retainerFee, farmId, MoneyType.OTHER, true, true)

    -- Track statistics
    if g_financeManager then
        g_financeManager:incrementStatistic(farmId, "searchesStarted", 1)
        g_financeManager:incrementStatistic(farmId, "totalSearchFees", search.retainerFee)
    end

    UsedPlus.logDebug(string.format("Created search %s: %s ($%d retainer, %d%% commission, %d months)",
        search.id, storeItemName, search.retainerFee,
        math.floor((search.commissionPercent or 0.08) * 100), search.maxMonths or 1))

    return search
end

--[[
    Register search in manager and farm
]]
function UsedVehicleManager:registerSearch(search)
    self.activeSearches[search.id] = search

    local farm = g_farmManager:getFarmById(search.farmId)
    if farm then
        if farm.usedVehicleSearches == nil then
            farm.usedVehicleSearches = {}
        end
        table.insert(farm.usedVehicleSearches, search)
        -- v2.8.0: WARN level for persistence debugging
        UsedPlus.logWarn(string.format("registerSearch: Added %s to farm %d (now %d searches)",
            search.id, search.farmId, #farm.usedVehicleSearches))
    else
        UsedPlus.logError(string.format("Could not find farm %d to register search", search.farmId))
    end
end

--[[
    Generate unique search ID
]]
function UsedVehicleManager:generateSearchId()
    local id = string.format("SEARCH_%08d", self.nextSearchId)
    self.nextSearchId = self.nextSearchId + 1
    return id
end

--[[
    Generate unique listing ID
]]
function UsedVehicleManager:generateListingId()
    local currentDay = g_currentMission.environment.currentDay or 0
    local id = string.format("LISTING_D%d_%08d", currentDay, self.nextSearchId)
    self.nextSearchId = self.nextSearchId + 1
    return id
end

--[[
    Get all searches for a specific farm
]]
function UsedVehicleManager:getSearchesForFarm(farmId)
    local farm = g_farmManager:getFarmById(farmId)
    if farm and farm.usedVehicleSearches then
        return farm.usedVehicleSearches
    end
    return {}
end

--[[
    Get all listings for a specific farm
    Returns array of available listings from active searches
]]
function UsedVehicleManager:getListingsForFarm(farmId)
    local listings = {}

    local farm = g_farmManager:getFarmById(farmId)
    if farm and farm.usedVehicleSearches then
        for _, search in ipairs(farm.usedVehicleSearches) do
            if search.foundListings then
                for _, listing in ipairs(search.foundListings) do
                    if listing.status == "available" or listing.status == nil then
                        table.insert(listings, listing)
                    end
                end
            end
        end
    end

    -- Include orphaned listings
    if farm and farm.usedVehicleListings then
        for _, listing in ipairs(farm.usedVehicleListings) do
            local isDuplicate = false
            for _, existingListing in ipairs(listings) do
                if existingListing.id == listing.id then
                    isDuplicate = true
                    break
                end
            end
            if not isDuplicate and (listing.status == "available" or listing.status == nil) then
                table.insert(listings, listing)
            end
        end
    end

    return listings
end

--[[
    Get search by ID
]]
function UsedVehicleManager:getSearchById(searchId)
    return self.activeSearches[searchId]
end

--[[
    End a search after a vehicle is purchased from it
]]
function UsedVehicleManager:endSearchAfterPurchase(searchId, farmId)
    if searchId == nil then return end

    local search = self.activeSearches[searchId]
    if search == nil then
        UsedPlus.logDebug(string.format("endSearchAfterPurchase: search %s not found", searchId))
        return
    end

    search.status = "completed"

    local farm = g_farmManager:getFarmById(farmId)
    if farm and farm.usedVehicleSearches then
        for i = #farm.usedVehicleSearches, 1, -1 do
            if farm.usedVehicleSearches[i].id == searchId then
                table.remove(farm.usedVehicleSearches, i)
                break
            end
        end
    end

    self.activeSearches[searchId] = nil

    if g_financeManager then
        g_financeManager:incrementStatistic(farmId, "searchesSucceeded", 1)
    end

    UsedPlus.logDebug(string.format("Search %s ended after direct purchase", searchId))
end

--[[
    Complete a purchase from the portfolio browser
]]
function UsedVehicleManager:completePurchaseFromSearch(search, listing, farmId)
    if search == nil or listing == nil then
        UsedPlus.logError("completePurchaseFromSearch: search or listing is nil")
        return false
    end

    local fullListing = {
        id = listing.id,
        farmId = farmId,
        searchId = search.id,
        storeItemIndex = search.storeItemIndex,
        storeItemName = search.storeItemName,
        damage = listing.damage or 0,
        wear = listing.wear or 0,
        age = listing.age or 1,
        operatingHours = listing.operatingHours or 0,
        price = listing.askingPrice or listing.basePrice or 0,
        basePrice = listing.basePrice or 0,
        commissionAmount = listing.commissionAmount or 0,
        askingPrice = listing.askingPrice or 0,
        configuration = listing.configuration or {},
        usedPlusData = listing.usedPlusData,
        rvbPartsData = listing.rvbPartsData,
        tireConditions = listing.tireConditions
    }

    -- Calls into VehicleSpawning module
    local success = self:purchaseUsedVehicle(fullListing, farmId)

    if success then
        search.status = "completed"

        local farm = g_farmManager:getFarmById(farmId)
        if farm and farm.usedVehicleSearches then
            for i = #farm.usedVehicleSearches, 1, -1 do
                if farm.usedVehicleSearches[i].id == search.id then
                    table.remove(farm.usedVehicleSearches, i)
                    break
                end
            end
        end

        self.activeSearches[search.id] = nil

        if g_financeManager then
            g_financeManager:incrementStatistic(farmId, "searchesSucceeded", 1)
            -- Note: usedPurchases and totalSavingsFromUsed are tracked in purchaseUsedVehicle
            -- Only track commission here since it's search-specific
            if listing.commissionAmount and listing.commissionAmount > 0 then
                g_financeManager:incrementStatistic(farmId, "totalAgentCommissions", listing.commissionAmount)
            end
        end

        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format("Search complete! Your %s has been delivered.", search.storeItemName or "vehicle")
        )
    end

    return success
end

--[[
    Cancel an active search
]]
function UsedVehicleManager:cancelSearch(searchId)
    if not self.isServer then
        UsedPlus.logError("cancelSearch must be called on server")
        return false
    end

    local search = self.activeSearches[searchId]
    if search == nil then
        UsedPlus.logWarn(string.format("Search %s not found for cancellation", searchId))
        return false
    end

    if search.status ~= "active" then
        return false
    end

    search:cancel()

    local farm = g_farmManager:getFarmById(search.farmId)
    if farm and farm.usedVehicleSearches then
        for i = #farm.usedVehicleSearches, 1, -1 do
            if farm.usedVehicleSearches[i].id == searchId then
                table.remove(farm.usedVehicleSearches, i)
                break
            end
        end
    end

    self.activeSearches[searchId] = nil

    if g_financeManager then
        g_financeManager:incrementStatistic(search.farmId, "searchesCancelled", 1)
    end

    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_INFO,
        string.format(g_i18n:getText("usedplus_notification_searchCancelled"), search.storeItemName)
    )

    UsedPlus.logDebug(string.format("Search %s cancelled: %s", searchId, search.storeItemName))
    return true
end

--[[
    Remove a listing from the farm's available listings
]]
function UsedVehicleManager:removeListing(listing, farmId)
    local farm = g_farmManager:getFarmById(farmId)
    if farm and farm.usedVehicleListings then
        for i, l in ipairs(farm.usedVehicleListings) do
            if l.id == listing.id then
                table.remove(farm.usedVehicleListings, i)
                break
            end
        end
    end
end

--[[
    Add listing to game's built-in vehicle sale system
]]
function UsedVehicleManager:addToGameVehicleSaleSystem(listing)
    if g_currentMission.vehicleSaleSystem == nil then
        UsedPlus.logWarn("vehicleSaleSystem not available")
        return nil
    end

    local operatingTime = listing.operatingHours * 60 * 60 * 1000

    local saleEntry = {
        ["timeLeft"] = listing.expirationTTL or 72,
        ["isGenerated"] = false,
        ["xmlFilename"] = listing.storeItemIndex,
        ["boughtConfigurations"] = listing.configuration or {},
        ["age"] = listing.age,
        ["price"] = listing.price,
        ["damage"] = listing.damage,
        ["wear"] = listing.wear,
        ["operatingTime"] = operatingTime,
    }

    local success, result = pcall(function()
        return g_currentMission.vehicleSaleSystem:addSale(saleEntry)
    end)

    if success and result then
        return result
    else
        UsedPlus.logWarn(string.format("vehicleSaleSystem:addSale() failed: %s", tostring(result)))
        return nil
    end
end

--[[
    Get total count of all active searches
]]
function UsedVehicleManager:getTotalSearchCount()
    local count = 0
    for _ in pairs(self.activeSearches) do
        count = count + 1
    end
    return count
end

--[[
    Cleanup on mission unload
]]
function UsedVehicleManager:delete()
    if self.isServer then
        g_messageCenter:unsubscribe(MessageType.HOUR_CHANGED, self)
        g_messageCenter:unsubscribe(MessageType.SLEEPING, self)
    end
    self.activeSearches = {}
    self.pendingUsedPurchases = {}
    UsedPlus.logDebug("UsedVehicleManager cleaned up")
end

--[[
    Hook for BuyVehicleData.onBought - applies used condition to purchased vehicles
]]
function UsedVehicleManager.onVehicleBought(buyVehicleData, loadedVehicles, loadingState, callbackArguments)
    UsedPlus.logInfo(string.format("SPAWN DEBUG: onVehicleBought called - loadingState: %s, vehicles: %d",
        tostring(loadingState), loadedVehicles and #loadedVehicles or 0))

    if loadingState ~= VehicleLoadingState.OK then
        UsedPlus.logWarn(string.format("SPAWN DEBUG: Loading state not OK: %s", tostring(loadingState)))
        return
    end

    if g_usedVehicleManager == nil then
        UsedPlus.logWarn("SPAWN DEBUG: g_usedVehicleManager is nil")
        return
    end

    if g_usedVehicleManager.pendingUsedPurchases == nil or
       next(g_usedVehicleManager.pendingUsedPurchases) == nil then
        UsedPlus.logDebug("SPAWN DEBUG: No pending used purchases")
        return
    end

    local storeItem = buyVehicleData.storeItem
    if storeItem == nil then
        UsedPlus.logWarn("SPAWN DEBUG: storeItem is nil in buyVehicleData")
        return
    end

    local xmlFilename = storeItem.xmlFilename
    local farmId = buyVehicleData.ownerFarmId

    UsedPlus.logInfo(string.format("SPAWN DEBUG: Looking for pending purchase - xml: %s, farmId: %d",
        tostring(xmlFilename), tostring(farmId)))

    -- Find matching pending purchase
    local matchedKey = nil
    local pendingData = nil

    UsedPlus.logInfo(string.format("SPAWN DEBUG: Searching %d pending purchases...",
        table.getn(g_usedVehicleManager.pendingUsedPurchases) or 0))

    for key, data in pairs(g_usedVehicleManager.pendingUsedPurchases) do
        UsedPlus.logInfo(string.format("SPAWN DEBUG: Checking pending: %s (xml: %s, farmId: %d, name: %s)",
            key, tostring(data.xmlFilename), tostring(data.farmId), tostring(data.storeItemName)))
        if data.xmlFilename == xmlFilename and data.farmId == farmId then
            matchedKey = key
            pendingData = data
            UsedPlus.logInfo(string.format("SPAWN DEBUG: MATCH FOUND: %s", key))
            break
        end
    end

    if matchedKey == nil then
        UsedPlus.logWarn(string.format("SPAWN DEBUG: NO MATCH FOUND for xml: %s, farmId: %d",
            tostring(xmlFilename), tostring(farmId)))
        return
    end

    UsedPlus.logInfo(string.format("onVehicleBought: Found pending purchase %s, applying used condition to %d vehicles",
        matchedKey, #loadedVehicles))

    for _, vehicle in ipairs(loadedVehicles) do
        -- Calls into VehicleSpawning module
        g_usedVehicleManager:applyUsedConditionToVehicle(vehicle, pendingData.listing)

        -- Schedule delayed dirt and UYT tire application
        local listingCopy = pendingData.listing
        local dirtKey = "dirt_" .. tostring(g_currentMission.time)
        UsedVehicleManager.pendingDirtApplications = UsedVehicleManager.pendingDirtApplications or {}
        UsedVehicleManager.pendingDirtApplications[dirtKey] = {
            vehicle = vehicle,
            listing = listingCopy
        }
        addTimer(500, "applyDelayedDirt", g_usedVehicleManager, dirtKey)

        if listingCopy.tireConditions and ModCompatibility and ModCompatibility.uytInstalled then
            UsedVehicleManager.pendingUYTTireApplications = UsedVehicleManager.pendingUYTTireApplications or {}
            local uytKey = "uyt_" .. tostring(g_currentMission.time)
            UsedVehicleManager.pendingUYTTireApplications[uytKey] = {
                vehicle = vehicle,
                tireConditions = listingCopy.tireConditions
            }
            addTimer(750, "applyDelayedUYTTireWear", g_usedVehicleManager, uytKey)
        end
    end

    g_usedVehicleManager.pendingUsedPurchases[matchedKey] = nil
end

-- Install the hook when this file loads
if BuyVehicleData ~= nil and BuyVehicleData.onBought ~= nil then
    BuyVehicleData.onBought = Utils.appendedFunction(BuyVehicleData.onBought, UsedVehicleManager.onVehicleBought)
    UsedPlus.logInfo("UsedVehicleManager: Hooked into BuyVehicleData.onBought")
else
    UsedPlus.logWarn("UsedVehicleManager: BuyVehicleData.onBought not available for hooking")
end

UsedPlus.logInfo("UsedVehicleManager loaded")
