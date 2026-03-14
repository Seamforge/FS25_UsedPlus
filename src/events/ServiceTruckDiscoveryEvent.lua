--[[
    FS25_UsedPlus - Service Truck Discovery Events for Multiplayer

    Handles synchronization of Service Truck discovery and purchase:
    - ServiceTruckDiscoveryEvent: Sync when discovery is triggered
    - ServiceTruckPurchaseEvent: Sync when purchase is made

    v2.9.0 - Service Truck System
]]

--[[
    ===============================================
    ServiceTruckDiscoveryEvent
    Sent when a farm discovers the service truck
    ===============================================
]]

ServiceTruckDiscoveryEvent = {}
ServiceTruckDiscoveryEvent_mt = Class(ServiceTruckDiscoveryEvent, Event)

InitEventClass(ServiceTruckDiscoveryEvent, "ServiceTruckDiscoveryEvent")

function ServiceTruckDiscoveryEvent.emptyNew()
    local self = Event.new(ServiceTruckDiscoveryEvent_mt)
    return self
end

function ServiceTruckDiscoveryEvent.new(farmId)
    local self = ServiceTruckDiscoveryEvent.emptyNew()
    self.farmId = farmId
    return self
end

function ServiceTruckDiscoveryEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self:run(connection)
end

function ServiceTruckDiscoveryEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
end

function ServiceTruckDiscoveryEvent:run(connection)
    -- Validate farmId
    if self.farmId == nil or self.farmId <= 0 then
        UsedPlus.logWarn("ServiceTruckDiscoveryEvent: Invalid farmId")
        return
    end

    if g_server ~= nil then
        -- Server: Process discovery and broadcast to all clients
        ServiceTruckDiscoveryEvent.executeDiscovery(self.farmId)

        -- Broadcast to all clients (except the one that sent it)
        g_server:broadcastEvent(ServiceTruckDiscoveryEvent.new(self.farmId), nil, connection)
    else
        -- Client: Update local state from server broadcast
        ServiceTruckDiscoveryEvent.executeDiscovery(self.farmId)
    end
end

-- Execute discovery logic (shared between server and client)
function ServiceTruckDiscoveryEvent.executeDiscovery(farmId)
    if ServiceTruckDiscovery == nil then
        UsedPlus.logDebug("ServiceTruckDiscoveryEvent: ServiceTruckDiscovery not available")
        return false
    end

    -- Mark as discovered using ServiceTruckDiscovery's farm data
    local data = ServiceTruckDiscovery.getFarmData(farmId)
    data.hasDiscovered = true
    data.opportunityActive = true
    data.opportunityExpiry = g_currentMission.time +
        (ServiceTruckDiscovery.OPPORTUNITY_EXPIRY_DAYS * 24 * 60 * 60 * 1000)

    UsedPlus.logDebug(string.format("ServiceTruckDiscoveryEvent: Farm %d discovered service truck", farmId))
    return true
end

-- Static helper: Send discovery to server (called by client)
function ServiceTruckDiscoveryEvent.sendDiscoveryToServer(farmId)
    if g_server ~= nil then
        -- Single-player or server: execute directly and broadcast
        ServiceTruckDiscoveryEvent.executeDiscovery(farmId)
    elseif g_client then
        -- Multiplayer client: send to server
        g_client:getServerConnection():sendEvent(ServiceTruckDiscoveryEvent.new(farmId))
    else
        UsedPlus.logError("ServiceTruckDiscoveryEvent: g_client is nil, cannot send to server")
    end
end

-- Static helper: Broadcast discovery from server to all clients
function ServiceTruckDiscoveryEvent.broadcastDiscovery(farmId)
    if g_server ~= nil then
        ServiceTruckDiscoveryEvent.executeDiscovery(farmId)
        g_server:broadcastEvent(ServiceTruckDiscoveryEvent.new(farmId))
    end
end


--[[
    ===============================================
    ServiceTruckPurchaseEvent
    Sent when a farm purchases the service truck
    ===============================================
]]

ServiceTruckPurchaseEvent = {}
ServiceTruckPurchaseEvent_mt = Class(ServiceTruckPurchaseEvent, Event)

InitEventClass(ServiceTruckPurchaseEvent, "ServiceTruckPurchaseEvent")

function ServiceTruckPurchaseEvent.emptyNew()
    local self = Event.new(ServiceTruckPurchaseEvent_mt)
    return self
end

function ServiceTruckPurchaseEvent.new(farmId, success, errorMessage)
    local self = ServiceTruckPurchaseEvent.emptyNew()
    self.farmId = farmId
    self.success = success or false
    self.errorMessage = errorMessage or ""
    return self
end

function ServiceTruckPurchaseEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.success = streamReadBool(streamId)
    self.errorMessage = streamReadString(streamId)
    self:run(connection)
end

function ServiceTruckPurchaseEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteBool(streamId, self.success)
    streamWriteString(streamId, self.errorMessage or "")
end

function ServiceTruckPurchaseEvent:run(connection)
    -- Validate farmId
    if self.farmId == nil or self.farmId <= 0 then
        UsedPlus.logWarn("ServiceTruckPurchaseEvent: Invalid farmId")
        return
    end

    if g_server ~= nil then
        -- Server: Process purchase request from client
        local success, errorMsg = ServiceTruckPurchaseEvent.executePurchase(self.farmId)

        -- Send result back to requesting client
        if connection ~= nil then
            connection:sendEvent(ServiceTruckPurchaseEvent.new(self.farmId, success, errorMsg or ""))
        end

        -- If successful, broadcast to all other clients so their UI updates
        if success then
            g_server:broadcastEvent(ServiceTruckPurchaseEvent.new(self.farmId, true, ""), nil, connection)
        end
    else
        -- Client: Handle result from server
        if self.success then
            UsedPlus.logDebug(string.format("ServiceTruckPurchaseEvent: Farm %d purchase confirmed by server", self.farmId))

            -- Update local state using ServiceTruckDiscovery's farm data
            if ServiceTruckDiscovery ~= nil then
                local data = ServiceTruckDiscovery.getFarmData(self.farmId)
                data.hasPurchased = true
                data.opportunityActive = false
            end

            -- Show success notification to local player if this is their farm
            local localFarmId = g_currentMission:getFarmId()
            if localFarmId == self.farmId then
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_OK,
                    g_i18n:getText("usedplus_serviceTruck_purchaseSuccess") or "Service Truck purchased!"
                )
            end
        else
            -- Show error notification to local player if this is their farm
            local localFarmId = g_currentMission:getFarmId()
            if localFarmId == self.farmId then
                local errorText = self.errorMessage
                if errorText == "" then
                    errorText = g_i18n:getText("usedplus_serviceTruck_purchaseFailed") or "Purchase failed"
                end
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                    errorText
                )
            end
        end
    end
end

-- Execute purchase logic (server-side only)
-- Delegates to ServiceTruckDiscovery.acceptOpportunity which handles all the logic
function ServiceTruckPurchaseEvent.executePurchase(farmId)
    if g_server == nil then
        UsedPlus.logError("ServiceTruckPurchaseEvent.executePurchase: Must run on server")
        return false, "Server error"
    end

    if ServiceTruckDiscovery == nil then
        UsedPlus.logError("ServiceTruckPurchaseEvent: ServiceTruckDiscovery not available")
        return false, "Manager not available"
    end

    -- Delegate to ServiceTruckDiscovery which has all the purchase logic
    local success, reason, extra = ServiceTruckDiscovery.acceptOpportunity(farmId)

    if not success then
        local errorMsg = "Purchase failed"
        if reason == "insufficient_funds" then
            errorMsg = g_i18n:getText("usedplus_mp_error_insufficient_funds") or "Insufficient funds"
        elseif reason == "spawn_failed" then
            errorMsg = "Failed to spawn vehicle"
        elseif reason == "no_opportunity" then
            errorMsg = "Opportunity expired"
        elseif reason == "invalid_farm" then
            errorMsg = g_i18n:getText("usedplus_mp_error_farm_not_found") or "Farm not found"
        end
        return false, errorMsg
    end

    UsedPlus.logInfo(string.format("ServiceTruckPurchaseEvent: Farm %d purchased service truck", farmId))
    return true, nil
end

-- Static helper: Send purchase request to server (called by client)
function ServiceTruckPurchaseEvent.sendPurchaseToServer(farmId)
    if g_server ~= nil then
        -- Single-player or server: execute directly
        local success, errorMsg = ServiceTruckPurchaseEvent.executePurchase(farmId)

        if success then
            -- Show notification
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_OK,
                g_i18n:getText("usedplus_serviceTruck_purchased") or "Service Truck purchased!"
            )
        else
            -- Show error
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                errorMsg or "Purchase failed"
            )
        end

        return success, errorMsg
    elseif g_client then
        -- Multiplayer client: send to server
        g_client:getServerConnection():sendEvent(ServiceTruckPurchaseEvent.new(farmId, false, ""))
        return true, nil  -- Request sent, actual result will come via callback
    else
        UsedPlus.logError("ServiceTruckPurchaseEvent: g_client is nil, cannot send to server")
        return false, "g_client is nil"
    end
end


--[[
    ===============================================
    ServiceTruckDiscoverySyncEvent
    Full state sync when a client joins
    ===============================================
]]

ServiceTruckDiscoverySyncEvent = {}
ServiceTruckDiscoverySyncEvent_mt = Class(ServiceTruckDiscoverySyncEvent, Event)

InitEventClass(ServiceTruckDiscoverySyncEvent, "ServiceTruckDiscoverySyncEvent")

function ServiceTruckDiscoverySyncEvent.emptyNew()
    local self = Event.new(ServiceTruckDiscoverySyncEvent_mt)
    return self
end

function ServiceTruckDiscoverySyncEvent.new(discoveryState, purchaseState)
    local self = ServiceTruckDiscoverySyncEvent.emptyNew()
    self.discoveryState = discoveryState or {}
    self.purchaseState = purchaseState or {}
    return self
end

function ServiceTruckDiscoverySyncEvent:readStream(streamId, connection)
    -- Read discovery state
    self.discoveryState = {}
    local discoveryCount = streamReadInt32(streamId)

    -- Security: Cap at reasonable maximum
    local MAX_FARMS = 16
    discoveryCount = math.min(discoveryCount, MAX_FARMS)

    for i = 1, discoveryCount do
        local farmId = streamReadInt32(streamId)
        local discovered = streamReadBool(streamId)
        if farmId > 0 and farmId <= MAX_FARMS then
            self.discoveryState[farmId] = discovered
        end
    end

    -- Read purchase state
    self.purchaseState = {}
    local purchaseCount = streamReadInt32(streamId)
    purchaseCount = math.min(purchaseCount, MAX_FARMS)

    for i = 1, purchaseCount do
        local farmId = streamReadInt32(streamId)
        local purchased = streamReadBool(streamId)
        if farmId > 0 and farmId <= MAX_FARMS then
            self.purchaseState[farmId] = purchased
        end
    end

    self:run(connection)
end

function ServiceTruckDiscoverySyncEvent:writeStream(streamId, connection)
    -- Write discovery state
    local discoveryCount = 0
    for _ in pairs(self.discoveryState) do
        discoveryCount = discoveryCount + 1
    end
    streamWriteInt32(streamId, discoveryCount)

    for farmId, discovered in pairs(self.discoveryState) do
        streamWriteInt32(streamId, farmId)
        streamWriteBool(streamId, discovered)
    end

    -- Write purchase state
    local purchaseCount = 0
    for _ in pairs(self.purchaseState) do
        purchaseCount = purchaseCount + 1
    end
    streamWriteInt32(streamId, purchaseCount)

    for farmId, purchased in pairs(self.purchaseState) do
        streamWriteInt32(streamId, farmId)
        streamWriteBool(streamId, purchased)
    end
end

function ServiceTruckDiscoverySyncEvent:run(connection)
    -- Client: Apply synced state from server
    if g_server == nil and ServiceTruckDiscovery ~= nil then
        -- Apply synced data to each farm
        for farmId, discovered in pairs(self.discoveryState) do
            local data = ServiceTruckDiscovery.getFarmData(farmId)
            data.hasDiscovered = discovered
        end
        for farmId, purchased in pairs(self.purchaseState) do
            local data = ServiceTruckDiscovery.getFarmData(farmId)
            data.hasPurchased = purchased
            if purchased then
                data.opportunityActive = false
            end
        end

        UsedPlus.logDebug("ServiceTruckDiscoverySyncEvent: Synced discovery/purchase state from server")
    end
end

-- Static helper: Send full sync to a specific client (called by server when client joins)
function ServiceTruckDiscoverySyncEvent.sendToClient(connection)
    if g_server ~= nil and ServiceTruckDiscovery ~= nil then
        -- Build state tables from farm data
        local discoveryState = {}
        local purchaseState = {}

        for farmId, data in pairs(ServiceTruckDiscovery.farmData) do
            discoveryState[farmId] = data.hasDiscovered or false
            purchaseState[farmId] = data.hasPurchased or false
        end

        connection:sendEvent(ServiceTruckDiscoverySyncEvent.new(discoveryState, purchaseState))
        UsedPlus.logDebug("ServiceTruckDiscoverySyncEvent: Sent sync to joining client")
    end
end


UsedPlus.logInfo("ServiceTruckDiscoveryEvent loaded - Multiplayer discovery/purchase sync ready")
