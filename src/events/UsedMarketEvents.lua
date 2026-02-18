--[[
    FS25_UsedPlus - Used Market Events (Consolidated)

    Network events for used vehicle marketplace:
    - RequestUsedItemEvent: Initiate used vehicle search
    - UsedItemFoundEvent: Notify clients of successful search

    Pattern from: BuyUsedEquipment async search requests
]]

--============================================================================
-- REQUEST USED ITEM EVENT
-- Network event for initiating used vehicle search
--============================================================================

RequestUsedItemEvent = {}
local RequestUsedItemEvent_mt = Class(RequestUsedItemEvent, Event)

InitEventClass(RequestUsedItemEvent, "RequestUsedItemEvent")

function RequestUsedItemEvent.emptyNew()
    local self = Event.new(RequestUsedItemEvent_mt)
    return self
end

function RequestUsedItemEvent.new(farmId, storeItemIndex, storeItemName, basePrice, searchLevel, qualityLevel)
    local self = RequestUsedItemEvent.emptyNew()
    self.farmId = farmId
    self.storeItemIndex = storeItemIndex
    self.storeItemName = storeItemName
    self.basePrice = basePrice
    self.searchLevel = searchLevel
    self.qualityLevel = qualityLevel or 1
    return self
end

function RequestUsedItemEvent.sendToServer(farmId, storeItemIndex, storeItemName, basePrice, searchLevel, qualityLevel)
    if g_server ~= nil then
        RequestUsedItemEvent.execute(farmId, storeItemIndex, storeItemName, basePrice, searchLevel, qualityLevel)
    else
        g_client:getServerConnection():sendEvent(
            RequestUsedItemEvent.new(farmId, storeItemIndex, storeItemName, basePrice, searchLevel, qualityLevel)
        )
    end
end

function RequestUsedItemEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObjectId(streamId, self.farmId)
    streamWriteInt32(streamId, self.storeItemIndex)
    streamWriteString(streamId, self.storeItemName)
    streamWriteFloat32(streamId, self.basePrice)
    streamWriteInt32(streamId, self.searchLevel)
    streamWriteInt32(streamId, self.qualityLevel or 1)
end

function RequestUsedItemEvent:readStream(streamId, connection)
    self.farmId = NetworkUtil.readNodeObjectId(streamId)
    self.storeItemIndex = streamReadInt32(streamId)
    self.storeItemName = streamReadString(streamId)
    self.basePrice = streamReadFloat32(streamId)
    self.searchLevel = streamReadInt32(streamId)
    self.qualityLevel = streamReadInt32(streamId)
    self:run(connection)
end

--[[
    Execute the search request on server
    v1.5.0: Multi-find agent model - retainer fee upfront, commission on purchase
]]
function RequestUsedItemEvent.execute(farmId, storeItemIndex, storeItemName, basePrice, searchLevel, qualityLevel)
    if g_usedVehicleManager == nil then
        UsedPlus.logError("UsedVehicleManager not initialized")
        return false
    end

    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then
        UsedPlus.logError(string.format("Farm %d not found", farmId))
        return false
    end

    if searchLevel < 1 or searchLevel > 3 then
        UsedPlus.logError(string.format("Invalid search level: %d", searchLevel))
        return false
    end

    local qualityLevel = qualityLevel or 1  -- Default to "Any Condition" (index 1 in v1.5.0)
    if qualityLevel < 1 or qualityLevel > 5 then
        UsedPlus.logWarn(string.format("Invalid quality level: %d, defaulting to 1", qualityLevel))
        qualityLevel = 1
    end

    -- v1.5.0: Multi-find agent model with retainer + commission
    -- Must match UsedVehicleSearch.SEARCH_TIERS
    local SEARCH_TIERS = {
        { retainerFlat = 500,  retainerPercent = 0 },       -- Local: $500 flat
        { retainerFlat = 1000, retainerPercent = 0.005 },   -- Regional: $1000 + 0.5%
        { retainerFlat = 2000, retainerPercent = 0.008 }    -- National: $2000 + 0.8%
    }

    local tier = SEARCH_TIERS[searchLevel]

    -- Calculate retainer fee: flat + percentage of vehicle price
    local baseRetainer = tier.retainerFlat + math.floor(basePrice * tier.retainerPercent)

    -- Apply credit fee modifier (better credit = cheaper agents)
    local creditFeeModifier = 0
    if UsedVehicleSearch and UsedVehicleSearch.getCreditFeeModifier then
        creditFeeModifier = UsedVehicleSearch.getCreditFeeModifier(farmId)
    end
    local retainerFee = math.floor(baseRetainer * (1 + creditFeeModifier))

    if farm.money < retainerFee then
        UsedPlus.logError(string.format("Insufficient funds for retainer fee ($%d required)", retainerFee))
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_insufficientFunds"), g_i18n:formatMoney(retainerFee))
        )
        return false
    end

    local MAX_ACTIVE_SEARCHES = 5
    local activeSearches = g_usedVehicleManager:getSearchesForFarm(farmId)
    local activeCount = 0
    if activeSearches then
        for _, search in ipairs(activeSearches) do
            if search.status == "active" then
                activeCount = activeCount + 1
            end
        end
    end

    if activeCount >= MAX_ACTIVE_SEARCHES then
        UsedPlus.logError(string.format("Maximum active searches reached (%d/%d)", activeCount, MAX_ACTIVE_SEARCHES))
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format("Maximum %d active searches allowed.", MAX_ACTIVE_SEARCHES)
        )
        return false
    end

    local search = g_usedVehicleManager:createSearchRequest(
        farmId, storeItemIndex, storeItemName, basePrice, searchLevel, qualityLevel
    )

    if search then
        UsedPlus.logDebug(string.format("Search request created: %s (ID: %s, retainer: $%d)",
            storeItemName, search.id, retainerFee))
        return true
    else
        UsedPlus.logError(string.format("Failed to create search request for %s", storeItemName))
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_searchFailed")
        )
        return false
    end
end

function RequestUsedItemEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- v2.7.2: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, self.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("USED_SEARCH_REJECTED",
            string.format("Unauthorized used search attempt for farmId %d: %s",
                self.farmId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    local success = RequestUsedItemEvent.execute(
        self.farmId, self.storeItemIndex, self.storeItemName,
        self.basePrice, self.searchLevel, self.qualityLevel
    )
    if success then
        TransactionResponseEvent.sendToClient(connection, self.farmId, true, "usedplus_mp_success_search_started")
    else
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_search_failed")
    end
end

--============================================================================
-- USED ITEM FOUND EVENT
-- Server→Client notification of successful search
--============================================================================

UsedItemFoundEvent = {}
local UsedItemFoundEvent_mt = Class(UsedItemFoundEvent, Event)

InitEventClass(UsedItemFoundEvent, "UsedItemFoundEvent")

function UsedItemFoundEvent.emptyNew()
    local self = Event.new(UsedItemFoundEvent_mt)
    return self
end

function UsedItemFoundEvent.new(farmId, listingId, storeItemName, usedPrice, generationName, operatingHours, damage, wear)
    local self = UsedItemFoundEvent.emptyNew()
    self.farmId = farmId
    self.listingId = listingId
    self.storeItemName = storeItemName
    self.usedPrice = usedPrice
    self.generationName = generationName
    self.operatingHours = operatingHours
    self.damage = damage
    self.wear = wear
    return self
end

function UsedItemFoundEvent:sendToClients(farmId, listingId, storeItemName, usedPrice, generationName, operatingHours, damage, wear)
    if g_server ~= nil then
        g_server:broadcastEvent(
            UsedItemFoundEvent.new(farmId, listingId, storeItemName, usedPrice, generationName, operatingHours, damage, wear)
        )
    else
        UsedPlus.logWarn("UsedItemFoundEvent should only be sent by server")
    end
end

function UsedItemFoundEvent:sendToFarm(farmId, listingId, storeItemName, usedPrice, generationName, operatingHours, damage, wear)
    if g_server ~= nil then
        local farm = g_farmManager:getFarmById(farmId)
        if farm == nil then
            UsedPlus.logWarn(string.format("Farm %d not found for notification", farmId))
            return
        end

        local farmManager = g_farmManager:getFarmById(farmId).userId
        if farmManager == nil or farmManager == 0 then
            self:sendToClients(farmId, listingId, storeItemName, usedPrice, generationName, operatingHours, damage, wear)
            return
        end

        local connection = g_server:getClientConnection(farmManager)
        if connection then
            connection:sendEvent(
                UsedItemFoundEvent.new(farmId, listingId, storeItemName, usedPrice, generationName, operatingHours, damage, wear)
            )
        end
    end
end

function UsedItemFoundEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObjectId(streamId, self.farmId)
    streamWriteString(streamId, self.listingId)
    streamWriteString(streamId, self.storeItemName)
    streamWriteFloat32(streamId, self.usedPrice)
    streamWriteString(streamId, self.generationName)
    streamWriteInt32(streamId, self.operatingHours)
    streamWriteFloat32(streamId, self.damage)
    streamWriteFloat32(streamId, self.wear)
end

function UsedItemFoundEvent:readStream(streamId, connection)
    self.farmId = NetworkUtil.readNodeObjectId(streamId)
    self.listingId = streamReadString(streamId)
    self.storeItemName = streamReadString(streamId)
    self.usedPrice = streamReadFloat32(streamId)
    self.generationName = streamReadString(streamId)
    self.operatingHours = streamReadInt32(streamId)
    self.damage = streamReadFloat32(streamId)
    self.wear = streamReadFloat32(streamId)
    self:run(connection)
end

function UsedItemFoundEvent:run(connection)
    UsedPlus.logDebug(string.format("Used vehicle found: %s (Listing ID: %s, Price: $%.2f)",
        self.storeItemName, self.listingId, self.usedPrice))

    local isLocalFarm = false
    if g_currentMission and g_currentMission.player then
        isLocalFarm = (g_currentMission.player.farmId == self.farmId)
    end

    if isLocalFarm then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notification_vehicleFound"),
                self.storeItemName, self.generationName, g_i18n:formatMoney(self.usedPrice))
        )

        if g_soundManager then
            g_soundManager:playSample(SoundManager.SOUND_SAMPLES.NOTIFICATION_MONEY)
        end
    end
end

--============================================================================
-- CANCEL SEARCH EVENT
-- Network event for cancelling an active used vehicle search
--============================================================================

CancelSearchEvent = {}
local CancelSearchEvent_mt = Class(CancelSearchEvent, Event)

InitEventClass(CancelSearchEvent, "CancelSearchEvent")

function CancelSearchEvent.emptyNew()
    local self = Event.new(CancelSearchEvent_mt)
    return self
end

function CancelSearchEvent.new(searchId)
    local self = CancelSearchEvent.emptyNew()
    self.searchId = searchId
    return self
end

--[[
    Send cancel request to server
    Convenience method for client-side calls
]]
function CancelSearchEvent.sendToServer(searchId)
    if g_server ~= nil then
        -- Single player or server - execute directly
        CancelSearchEvent.execute(searchId)
    else
        -- Multiplayer client - send to server
        g_client:getServerConnection():sendEvent(CancelSearchEvent.new(searchId))
    end
end

function CancelSearchEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.searchId)
end

function CancelSearchEvent:readStream(streamId, connection)
    self.searchId = streamReadString(streamId)
    self:run(connection)
end

--[[
    Execute the cancellation on server
]]
function CancelSearchEvent.execute(searchId)
    if g_usedVehicleManager == nil then
        UsedPlus.logError("UsedVehicleManager not initialized for cancel")
        return false
    end

    return g_usedVehicleManager:cancelSearch(searchId)
end

function CancelSearchEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- v2.7.2: Validate farm ownership to prevent multiplayer exploits
    if g_usedVehicleManager then
        local search = g_usedVehicleManager:getSearchById(self.searchId)
        if search then
            local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, search.farmId)
            if not isAuthorized then
                NetworkSecurity.logSecurityEvent("CANCEL_SEARCH_REJECTED",
                    string.format("Unauthorized cancel search attempt for search %s (farmId %d): %s",
                        self.searchId, search.farmId, errorMsg or "unknown"),
                    connection)
                TransactionResponseEvent.sendToClient(connection, search.farmId, false, "usedplus_mp_error_unauthorized")
                return
            end
        end
    end

    local success = CancelSearchEvent.execute(self.searchId)
    -- success/failure is handled by manager, response optional
end

--============================================================================
-- DECLINE LISTING EVENT
-- v1.5.0: Network event for declining a listing from portfolio
-- Removes listing from search's foundListings and syncs across clients
--============================================================================

DeclineListingEvent = {}
local DeclineListingEvent_mt = Class(DeclineListingEvent, Event)

InitEventClass(DeclineListingEvent, "DeclineListingEvent")

function DeclineListingEvent.emptyNew()
    local self = Event.new(DeclineListingEvent_mt)
    return self
end

function DeclineListingEvent.new(searchId, listingId)
    local self = DeclineListingEvent.emptyNew()
    self.searchId = searchId
    self.listingId = listingId
    return self
end

--[[
    Send decline request to server
    Convenience method for client-side calls
]]
function DeclineListingEvent.sendToServer(searchId, listingId)
    if g_server ~= nil then
        -- Single player or server - execute directly
        DeclineListingEvent.execute(searchId, listingId)
    else
        -- Multiplayer client - send to server
        g_client:getServerConnection():sendEvent(DeclineListingEvent.new(searchId, listingId))
    end
end

function DeclineListingEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.searchId)
    streamWriteString(streamId, self.listingId)
end

function DeclineListingEvent:readStream(streamId, connection)
    self.searchId = streamReadString(streamId)
    self.listingId = streamReadString(streamId)
    self:run(connection)
end

--[[
    Execute the decline on server
    Removes listing from search's foundListings array
]]
function DeclineListingEvent.execute(searchId, listingId)
    if g_usedVehicleManager == nil then
        UsedPlus.logError("UsedVehicleManager not initialized for decline")
        return false
    end

    -- Find the search
    local search = g_usedVehicleManager:getSearchById(searchId)
    if search == nil then
        UsedPlus.logWarn(string.format("Search %s not found for decline", searchId))
        return false
    end

    -- Remove listing from foundListings
    local listings = search.foundListings
    if listings == nil then
        UsedPlus.logWarn(string.format("Search %s has no foundListings", searchId))
        return false
    end

    local removed = false
    for i = #listings, 1, -1 do
        if listings[i].id == listingId then
            table.remove(listings, i)
            removed = true
            UsedPlus.logDebug(string.format("Declined listing %s from search %s", listingId, searchId))
            break
        end
    end

    if not removed then
        UsedPlus.logWarn(string.format("Listing %s not found in search %s", listingId, searchId))
        return false
    end

    -- Track statistic
    if g_financeManager and search.farmId then
        g_financeManager:incrementStatistic(search.farmId, "listingsDeclined", 1)
    end

    return true
end

function DeclineListingEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- v2.7.2: Validate farm ownership to prevent multiplayer exploits
    if g_usedVehicleManager then
        local search = g_usedVehicleManager:getSearchById(self.searchId)
        if search then
            local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, search.farmId)
            if not isAuthorized then
                NetworkSecurity.logSecurityEvent("DECLINE_LISTING_REJECTED",
                    string.format("Unauthorized decline listing attempt for search %s (farmId %d): %s",
                        self.searchId, search.farmId, errorMsg or "unknown"),
                    connection)
                TransactionResponseEvent.sendToClient(connection, search.farmId, false, "usedplus_mp_error_unauthorized")
                return
            end
        end
    end

    DeclineListingEvent.execute(self.searchId, self.listingId)
end

--============================================================================
-- PURCHASE USED VEHICLE EVENT
-- v2.7.2: Network event for completing a used vehicle purchase from search
-- Handles money deduction and vehicle spawning via UsedVehicleManager
--============================================================================

PurchaseUsedVehicleEvent = {}
local PurchaseUsedVehicleEvent_mt = Class(PurchaseUsedVehicleEvent, Event)

InitEventClass(PurchaseUsedVehicleEvent, "PurchaseUsedVehicleEvent")

function PurchaseUsedVehicleEvent.emptyNew()
    local self = Event.new(PurchaseUsedVehicleEvent_mt)
    return self
end

function PurchaseUsedVehicleEvent.new(farmId, searchId, listingId)
    local self = PurchaseUsedVehicleEvent.emptyNew()
    self.farmId = farmId
    self.searchId = searchId
    self.listingId = listingId
    return self
end

--[[
    Send purchase request to server
    Convenience method for client-side calls
]]
function PurchaseUsedVehicleEvent.sendToServer(farmId, searchId, listingId)
    if g_server ~= nil then
        -- Single player or server - execute directly
        PurchaseUsedVehicleEvent.execute(farmId, searchId, listingId)
    else
        -- Multiplayer client - send to server
        g_client:getServerConnection():sendEvent(PurchaseUsedVehicleEvent.new(farmId, searchId, listingId))
    end
end

function PurchaseUsedVehicleEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteString(streamId, self.searchId)
    streamWriteString(streamId, self.listingId)
end

function PurchaseUsedVehicleEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.searchId = streamReadString(streamId)
    self.listingId = streamReadString(streamId)
    self:run(connection)
end

--[[
    Execute the purchase on server
    Finds listing from search, completes purchase via manager
    Returns success boolean
]]
function PurchaseUsedVehicleEvent.execute(farmId, searchId, listingId)
    if g_usedVehicleManager == nil then
        UsedPlus.logError("UsedVehicleManager not initialized for purchase")
        return false
    end

    -- Get the search
    local search = g_usedVehicleManager:getSearchById(searchId)
    if search == nil then
        UsedPlus.logError(string.format("Search %s not found for purchase", searchId))
        return false
    end

    -- Find the listing in foundListings
    local listing = nil
    if search.foundListings then
        for _, l in ipairs(search.foundListings) do
            if l.id == listingId then
                listing = l
                break
            end
        end
    end

    if listing == nil then
        UsedPlus.logError(string.format("Listing %s not found in search %s", listingId, searchId))
        return false
    end

    -- Complete purchase via manager (handles money deduction and vehicle spawning)
    local success = g_usedVehicleManager:completePurchaseFromSearch(search, listing, farmId)

    if success then
        -- Mark search as completed
        search.status = "completed"
        UsedPlus.logDebug(string.format("Purchase completed: listing %s from search %s for farm %d",
            listingId, searchId, farmId))
    else
        UsedPlus.logError(string.format("Failed to complete purchase: listing %s from search %s",
            listingId, searchId))
    end

    return success
end

function PurchaseUsedVehicleEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, self.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("PURCHASE_USED_VEHICLE_REJECTED",
            string.format("Unauthorized purchase attempt for farmId %d, search %s: %s",
                self.farmId, self.searchId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    local success = PurchaseUsedVehicleEvent.execute(self.farmId, self.searchId, self.listingId)
    if success then
        TransactionResponseEvent.sendToClient(connection, self.farmId, true, "usedplus_mp_success_vehicle_purchased")
    else
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_purchase_failed")
    end
end

--============================================================================

UsedPlus.logInfo("UsedMarketEvents loaded (RequestUsedItemEvent, UsedItemFoundEvent, CancelSearchEvent, DeclineListingEvent, PurchaseUsedVehicleEvent)")
