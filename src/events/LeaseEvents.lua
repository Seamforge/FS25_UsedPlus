--[[
    FS25_UsedPlus - Lease Events (Consolidated)

    Network events for leasing operations:
    - LeaseVehicleEvent: Lease a vehicle
    - LeaseEndEvent: Handle lease end (return or buyout)
    - TerminateLeaseEvent: End lease early with penalties

    Pattern from: FinanceVehicleEvent, Game's vehicle return system
]]

--============================================================================
-- LEASE VEHICLE EVENT
-- Network event for leasing a vehicle
--============================================================================

LeaseVehicleEvent = {}
local LeaseVehicleEvent_mt = Class(LeaseVehicleEvent, Event)

InitEventClass(LeaseVehicleEvent, "LeaseVehicleEvent")

function LeaseVehicleEvent.emptyNew()
    local self = Event.new(LeaseVehicleEvent_mt)
    return self
end

function LeaseVehicleEvent.new(farmId, vehicleConfig, vehicleName, basePrice, downPayment, termYears)
    local self = LeaseVehicleEvent.emptyNew()
    self.farmId = farmId
    self.vehicleConfig = vehicleConfig
    self.vehicleName = vehicleName
    self.basePrice = basePrice
    self.downPayment = downPayment
    self.termYears = termYears
    return self
end

function LeaseVehicleEvent.sendToServer(farmId, vehicleConfig, vehicleName, basePrice, downPayment, termYears, configurations)
    UsedPlus.logDebug(string.format("LeaseVehicleEvent.sendToServer: farmId=%s, vehicle=%s, price=%.0f, down=%.0f, years=%.2f",
        tostring(farmId), tostring(vehicleName), basePrice or 0, downPayment or 0, termYears or 0))

    local event = LeaseVehicleEvent.new(farmId, vehicleConfig, vehicleName, basePrice, downPayment, termYears)
    event.configurations = configurations or {}

    if g_server ~= nil then
        UsedPlus.logDebug("LeaseVehicleEvent: Running on server directly")
        event:run(nil)  -- v2.9.1: Server doesn't need connection
    elseif g_client then
        UsedPlus.logDebug("LeaseVehicleEvent: Sending to server from client")
        g_client:getServerConnection():sendEvent(event)
    else
        UsedPlus.logError("LeaseVehicleEvent: g_client is nil, cannot send to server")
    end
end

function LeaseVehicleEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteString(streamId, self.vehicleConfig)
    streamWriteString(streamId, self.vehicleName)
    streamWriteFloat32(streamId, self.basePrice)
    streamWriteFloat32(streamId, self.downPayment)
    streamWriteInt32(streamId, self.termYears)

    local configCount = 0
    for _ in pairs(self.configurations or {}) do
        configCount = configCount + 1
    end
    streamWriteInt32(streamId, configCount)

    for configName, configValue in pairs(self.configurations or {}) do
        streamWriteString(streamId, configName)
        streamWriteInt32(streamId, configValue)
    end
end

function LeaseVehicleEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.vehicleConfig = streamReadString(streamId)
    self.vehicleName = streamReadString(streamId)
    self.basePrice = streamReadFloat32(streamId)
    self.downPayment = streamReadFloat32(streamId)
    self.termYears = streamReadInt32(streamId)

    self.configurations = {}
    local configCount = streamReadInt32(streamId)

    -- v2.7.2 SECURITY: Prevent unbounded loop DoS attack
    -- CRITICAL: We must ALWAYS consume the stream data, even if count is invalid
    -- Otherwise the stream pointer gets out of sync and causes packet corruption
    local MAX_CONFIGS = 100
    local isValidCount = (configCount >= 0 and configCount <= MAX_CONFIGS)
    if not isValidCount then
        UsedPlus.logWarn(string.format("[SECURITY] Invalid configCount rejected: %d (max %d) - draining stream", configCount, MAX_CONFIGS))
    end

    -- Always read the exact number of items declared in the stream
    -- Only store them if the count was valid
    local safeCount = math.max(0, math.min(configCount, MAX_CONFIGS * 2))  -- Cap at 2x max to prevent extreme DoS
    for i = 1, safeCount do
        local configName = streamReadString(streamId)
        local configValue = streamReadInt32(streamId)
        -- v2.7.2 SECURITY: Only store if count was valid and key is safe
        if isValidCount and configName and not configName:match("^__") and configName ~= "" then
            self.configurations[configName] = configValue
        end
    end

    self:run(connection)
end

function LeaseVehicleEvent:run(connection)
    UsedPlus.logDebug("LeaseVehicleEvent:run() ENTERED")

    if connection ~= nil and connection:getIsServer() then
        return
    end

    UsedPlus.logDebug("LeaseVehicleEvent:run() - passed connection check")

    -- v2.7.2: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, self.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("LEASE_REJECTED",
            string.format("Unauthorized lease attempt for farmId %d: %s", self.farmId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    UsedPlus.logDebug("LeaseVehicleEvent:run() - passed security check")

    -- v2.6.2: Validate lease system is enabled
    if UsedPlusSettings and UsedPlusSettings:get("enableLeaseSystem") == false then
        UsedPlus.logWarn("LeaseVehicleEvent rejected: Lease system disabled in settings")
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_disabled")
        return
    end

    UsedPlus.logDebug("LeaseVehicleEvent:run() - lease system enabled")

    if g_financeManager == nil then
        UsedPlus.logError("FinanceManager not initialized")
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_manager")
        return
    end

    UsedPlus.logDebug("LeaseVehicleEvent:run() - g_financeManager exists")

    local farm = g_farmManager:getFarmById(self.farmId)
    if farm == nil then
        UsedPlus.logError(string.format("Farm %d not found", self.farmId))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_farm_not_found")
        return
    end

    UsedPlus.logDebug(string.format("LeaseVehicleEvent:run() - farm found, money=%.0f, downPayment=%.0f", farm.money, self.downPayment))

    if farm.money < self.downPayment then
        UsedPlus.logError(string.format("Insufficient funds for down payment ($%.2f required, $%.2f available)",
            self.downPayment, farm.money))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_insufficient_funds")
        return
    end

    UsedPlus.logDebug("LeaseVehicleEvent:run() - calling createLeaseDeal")

    local deal = g_financeManager:createLeaseDeal(
        self.farmId, self.vehicleConfig, self.vehicleName,
        self.basePrice, self.downPayment, self.termYears
    )

    if deal then
        UsedPlus.logInfo(string.format("LeaseVehicleEvent:run() - deal created: %s (ID: %s)", self.vehicleName, deal.id))
        TransactionResponseEvent.sendToClient(connection, self.farmId, true, "usedplus_mp_success_leased")

        -- v2.15.0: Broadcast deal sync to all clients
        SyncFinanceDealsEvent.broadcastAddForFarm(self.farmId)

        local storeItem = g_storeManager:getItemByXMLFilename(self.vehicleConfig)
        UsedPlus.logDebug(string.format("LeaseVehicleEvent:run() - storeItem=%s for config=%s", tostring(storeItem ~= nil), self.vehicleConfig))

        if storeItem then
            -- Spawn the vehicle using the game's proper API
            UsedPlus.logDebug("LeaseVehicleEvent:run() - calling spawnLeasedVehicle")
            local success = self:spawnLeasedVehicle(storeItem, self.farmId, self.configurations or {}, deal)
            UsedPlus.logDebug(string.format("LeaseVehicleEvent:run() - spawnLeasedVehicle returned: %s", tostring(success)))

            if success then
                UsedPlus.logInfo(string.format("Spawned leased vehicle: %s", self.vehicleName))

                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_OK,
                    string.format(g_i18n:getText("usedplus_notification_leaseSigned"), self.vehicleName, g_i18n:formatMoney(deal.monthlyPayment, 0, true, true))
                )
            else
                UsedPlus.logError(string.format("Failed to spawn leased vehicle: %s", self.vehicleName))
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_OK,
                    string.format(g_i18n:getText("usedplus_notification_leaseSignedCollect"), self.vehicleName)
                )
            end
        else
            UsedPlus.logError(string.format("Could not find storeItem for leased vehicle: %s", self.vehicleConfig))
        end
    else
        UsedPlus.logError(string.format("Failed to create lease deal for %s", self.vehicleName))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_failed")
    end
end

--[[
    Spawn a leased vehicle using the game's proper vehicle buying API
    Uses BuyVehicleEvent just like financed purchases (FinanceManager.lua:466)
    @param storeItem - The store item to spawn
    @param farmId - Owner farm ID
    @param configurations - Vehicle configurations
    @param deal - The lease deal (to link vehicle to deal)
    @return boolean success
]]
function LeaseVehicleEvent:spawnLeasedVehicle(storeItem, farmId, configurations, deal)
    -- Use BuyVehicleData/BuyVehicleEvent - the proper game API for spawning vehicles
    -- Pattern from FinanceManager.lua createFinanceDeal() which works correctly

    if not BuyVehicleData or not BuyVehicleEvent then
        UsedPlus.logError("BuyVehicleData or BuyVehicleEvent not available")
        return false
    end

    local buyData = BuyVehicleData.new()
    buyData:setOwnerFarmId(farmId)
    buyData:setPrice(0)  -- Leased, no purchase price (already paid via down payment)
    buyData:setStoreItem(storeItem)

    -- Apply user-selected configurations
    local vehicleConfigs = configurations or {}
    buyData:setConfigurations(vehicleConfigs)

    -- Debug log configurations being applied
    local configCount = 0
    for k, v in pairs(vehicleConfigs) do
        UsedPlus.logDebug(string.format("  Lease config: %s = %s", tostring(k), tostring(v)))
        configCount = configCount + 1
    end
    UsedPlus.logDebug(string.format("Total lease configurations applied: %d", configCount))

    -- Spawn vehicle using BuyVehicleEvent
    -- ALWAYS use client->server path, even in single player
    -- This is how the normal shop flow works - BuyVehicleEvent:run() expects a real connection
    local buyEvent = BuyVehicleEvent.new(buyData)

    UsedPlus.logDebug("spawnLeasedVehicle: Sending BuyVehicleEvent via client connection")
    if g_client then
        g_client:getServerConnection():sendEvent(buyEvent)
    else
        UsedPlus.logError("spawnLeasedVehicle: g_client is nil, cannot send BuyVehicleEvent to server")
        return false
    end

    return true
end

function LeaseVehicleEvent:getVehicleSpawnPosition()
    if g_currentMission.player then
        local playerX, playerY, playerZ = getWorldTranslation(g_currentMission.player.rootNode)
        local dirX, _, dirZ = localDirectionToWorld(g_currentMission.player.rootNode, 0, 0, 1)
        return playerX + dirX * 5, playerY, playerZ + dirZ * 5
    end
    local mapSize = g_currentMission.terrainSize / 2
    return mapSize, 200, mapSize
end

--============================================================================
-- LEASE END EVENT
-- Network event for handling lease end (return or buyout)
--============================================================================

LeaseEndEvent = {}
local LeaseEndEvent_mt = Class(LeaseEndEvent, Event)

InitEventClass(LeaseEndEvent, "LeaseEndEvent")

LeaseEndEvent.ACTION_RETURN = 1
LeaseEndEvent.ACTION_BUYOUT = 2

function LeaseEndEvent.emptyNew()
    local self = Event.new(LeaseEndEvent_mt)
    return self
end

function LeaseEndEvent.new(dealId, action, amount)
    local self = LeaseEndEvent.emptyNew()
    self.dealId = dealId
    self.action = action
    self.amount = amount
    return self
end

function LeaseEndEvent.sendToServer(dealId, action, amount)
    local event = LeaseEndEvent.new(dealId, action, amount)
    if g_server ~= nil then
        event:run(nil)  -- v2.9.1: Server doesn't need connection
    elseif g_client then
        g_client:getServerConnection():sendEvent(event)
    else
        UsedPlus.logError("LeaseEndEvent: g_client is nil, cannot send to server")
    end
end

function LeaseEndEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.dealId)
    streamWriteInt32(streamId, self.action)
    streamWriteFloat32(streamId, self.amount)
end

function LeaseEndEvent:readStream(streamId, connection)
    self.dealId = streamReadString(streamId)
    self.action = streamReadInt32(streamId)
    self.amount = streamReadFloat32(streamId)
    self:run(connection)
end

function LeaseEndEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    if g_financeManager == nil then
        UsedPlus.logError("FinanceManager not initialized")
        -- Note: No farmId available yet, can't send response
        return
    end

    local deal = g_financeManager:getDealById(self.dealId)
    if deal == nil then
        UsedPlus.logError(string.format("Lease deal %s not found", self.dealId))
        -- Note: No farmId available, can't send response
        return
    end

    -- v2.7.2: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, deal.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("LEASE_END_REJECTED",
            string.format("Unauthorized lease end attempt for deal %s (farmId %d): %s",
                self.dealId, deal.farmId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, deal.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    if deal.dealType ~= 2 then
        UsedPlus.logError(string.format("Deal %s is not a lease", self.dealId))
        TransactionResponseEvent.sendToClient(connection, deal.farmId, false, "usedplus_mp_error_invalid_deal_type")
        return
    end

    local farm = g_farmManager:getFarmById(deal.farmId)
    if farm == nil then
        UsedPlus.logError(string.format("Farm %d not found", deal.farmId))
        TransactionResponseEvent.sendToClient(connection, deal.farmId, false, "usedplus_mp_error_farm_not_found")
        return
    end

    if self.action == LeaseEndEvent.ACTION_RETURN then
        self:processReturn(deal, farm, connection)
    elseif self.action == LeaseEndEvent.ACTION_BUYOUT then
        self:processBuyout(deal, farm, connection)
    else
        UsedPlus.logError(string.format("Unknown lease end action: %d", self.action))
        TransactionResponseEvent.sendToClient(connection, deal.farmId, false, "usedplus_mp_error_invalid_action")
    end
end

function LeaseEndEvent:processReturn(deal, farm, connection)
    if self.amount > 0 then
        if farm.money < self.amount then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_ERROR,
                string.format(g_i18n:getText("usedplus_notification_insufficientDamagePenalty"),
                    g_i18n:formatMoney(self.amount, 0, true, true))
            )
            TransactionResponseEvent.sendToClient(connection, deal.farmId, false, "usedplus_mp_error_insufficient_funds")
            return
        end
        g_currentMission:addMoney(-self.amount, deal.farmId, MoneyType.OTHER, true, true)
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format(g_i18n:getText("usedplus_notification_damagePenaltyPaid"), g_i18n:formatMoney(self.amount, 0, true, true))
        )
    end

    -- v2.15.4: Clear lease flags before removal (Issue #34)
    local vehicle = deal:findVehicle()
    if vehicle then
        UsedPlus.logDebug(string.format("LeaseEndEvent:processReturn - found vehicle for %s (objectId=%s)", deal.itemName, tostring(deal.objectId)))
        vehicle.isLeased = false
        vehicle.leaseDealId = nil
        if vehicle.delete then
            vehicle:delete()
        end
    else
        -- v2.15.4: Vehicle not found — clear orphaned flags as safety net
        UsedPlus.logWarn(string.format("LeaseEndEvent:processReturn - vehicle NOT found for %s (objectId=%s, config=%s)", deal.itemName or "?", tostring(deal.objectId), tostring(deal.vehicleConfig)))
        if deal.vehicleConfig then
            for _, v in pairs(g_currentMission.vehicleSystem.vehicles) do
                if v.configFileName == deal.vehicleConfig and v.ownerFarmId == deal.farmId and v.isLeased then
                    UsedPlus.logWarn(string.format("LeaseEndEvent:processReturn - clearing orphaned isLeased on %s", v:getName()))
                    v.isLeased = false
                    v.leaseDealId = nil
                end
            end
        end
    end

    deal.status = "completed"
    g_financeManager:removeDeal(deal.id)

    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format(g_i18n:getText("usedplus_notification_leaseReturnComplete"), deal.itemName)
    )
    TransactionResponseEvent.sendToClient(connection, deal.farmId, true, "usedplus_mp_success_lease_returned")

    -- v2.15.0: Broadcast deal removal to all clients
    SyncFinanceDealsEvent.broadcastAddForFarm(deal.farmId)

    UsedPlus.logDebug(string.format("Lease returned: %s (penalty: $%.2f)", deal.itemName, self.amount))
end

function LeaseEndEvent:processBuyout(deal, farm, connection)
    if farm.money < self.amount then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_ERROR,
            string.format(g_i18n:getText("usedplus_notification_insufficientBuyout"),
                g_i18n:formatMoney(self.amount, 0, true, true))
        )
        TransactionResponseEvent.sendToClient(connection, deal.farmId, false, "usedplus_mp_error_insufficient_funds")
        return
    end

    g_currentMission:addMoney(-self.amount, deal.farmId, MoneyType.SHOP_VEHICLE_BUY, true, true)

    local vehicle = deal:findVehicle()
    if vehicle then
        vehicle.isLeased = false
        vehicle.leaseDealId = nil
    end

    deal.status = "completed"
    g_financeManager:removeDeal(deal.id)

    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format(g_i18n:getText("usedplus_notification_leaseBuyoutComplete"),
            deal.itemName, g_i18n:formatMoney(self.amount, 0, true, true))
    )
    TransactionResponseEvent.sendToClient(connection, deal.farmId, true, "usedplus_mp_success_lease_buyout")

    -- v2.15.0: Broadcast deal removal to all clients
    SyncFinanceDealsEvent.broadcastAddForFarm(deal.farmId)

    if CreditHistory then
        CreditHistory.recordEvent(deal.farmId, "DEAL_PAID_OFF", deal.itemName)
    end
    UsedPlus.logDebug(string.format("Lease bought out: %s for $%.2f", deal.itemName, self.amount))
end

--============================================================================
-- TERMINATE LEASE EVENT
-- Network event for ending lease early with penalties
--============================================================================

TerminateLeaseEvent = {}
local TerminateLeaseEvent_mt = Class(TerminateLeaseEvent, Event)

InitEventClass(TerminateLeaseEvent, "TerminateLeaseEvent")

function TerminateLeaseEvent.emptyNew()
    local self = Event.new(TerminateLeaseEvent_mt)
    return self
end

function TerminateLeaseEvent.new(dealId, farmId)
    local self = TerminateLeaseEvent.emptyNew()
    self.dealId = dealId
    self.farmId = farmId
    return self
end

function TerminateLeaseEvent.sendToServer(dealId, farmId)
    local event = TerminateLeaseEvent.new(dealId, farmId)
    if g_server ~= nil then
        event:run(nil)  -- v2.9.1: Server doesn't need connection
    elseif g_client then
        g_client:getServerConnection():sendEvent(event)
    else
        UsedPlus.logError("TerminateLeaseEvent: g_client is nil, cannot send to server")
    end
end

function TerminateLeaseEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.dealId)
    streamWriteInt32(streamId, self.farmId)
end

function TerminateLeaseEvent:readStream(streamId, connection)
    self.dealId = streamReadString(streamId)
    self.farmId = streamReadInt32(streamId)
    self:run(connection)
end

function TerminateLeaseEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- v2.7.2: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, self.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("TERMINATE_LEASE_REJECTED",
            string.format("Unauthorized lease termination attempt for farmId %d: %s",
                self.farmId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    if g_financeManager == nil then
        UsedPlus.logError("FinanceManager not initialized")
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_manager")
        return
    end

    local deal = g_financeManager:getDealById(self.dealId)
    if deal == nil then
        UsedPlus.logError(string.format("Deal %s not found", self.dealId))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_deal_not_found")
        return
    end

    if deal.dealType ~= 2 and deal.dealType ~= 3 then
        UsedPlus.logError(string.format("Deal %s is not a lease (type: %d)", self.dealId, deal.dealType or 0))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_invalid_deal_type")
        return
    end

    local isLandLease = (deal.dealType == 3)

    if deal.farmId ~= self.farmId then
        UsedPlus.logError(string.format("Farm %d does not own deal %s", self.farmId, self.dealId))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    local farm = g_farmManager:getFarmById(self.farmId)
    if farm == nil then
        UsedPlus.logError(string.format("Farm %d not found", self.farmId))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_farm_not_found")
        return
    end

    -- Land lease termination
    if isLandLease then
        local farmlandId = deal.farmlandId or deal.itemId
        if farmlandId then
            g_farmlandManager:setLandOwnership(farmlandId, FarmlandManager.NO_OWNER_FARM_ID)
            UsedPlus.logDebug(string.format("Land lease terminated: Field %d reverted to NPC", farmlandId))
        end

        deal.status = "terminated"
        deal.currentBalance = 0
        g_financeManager:removeDeal(deal.id)

        if CreditHistory then
            CreditHistory.recordEvent(self.farmId, "LAND_LEASE_TERMINATED", deal.landName or deal.itemName)
        end

        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format(g_i18n:getText("usedplus_notification_landLeaseTerminatedReturned"), deal.landName or deal.itemName or "Field")
        )
        TransactionResponseEvent.sendToClient(connection, self.farmId, true, "usedplus_mp_success_lease_terminated")

        -- v2.15.0: Broadcast deal removal to all clients
        SyncFinanceDealsEvent.broadcastAddForFarm(self.farmId)
        return
    end

    -- Vehicle lease termination
    local vehicle = deal:findVehicle()

    local totalPenalty = 0

    if vehicle and deal.calculateDamagePenalty then
        local damagePenalty = deal:calculateDamagePenalty(vehicle)
        totalPenalty = totalPenalty + damagePenalty
    end

    if deal.calculateEarlyTerminationFee then
        local terminationFee = deal:calculateEarlyTerminationFee()
        totalPenalty = totalPenalty + terminationFee
    end

    if farm.money < totalPenalty then
        UsedPlus.logError(string.format("Insufficient funds for lease termination ($%.2f required)", totalPenalty))
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_insufficientFundsTermination"), g_i18n:formatMoney(totalPenalty))
        )
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_insufficient_funds")
        return
    end

    if totalPenalty > 0 then
        g_currentMission:addMoney(-totalPenalty, self.farmId, MoneyType.LEASING_COSTS, true, true)
    end

    if vehicle then
        vehicle.isLeased = false
        vehicle.leaseDealId = nil
        if vehicle.delete then
            vehicle:delete()
        end
    end

    deal.status = "terminated"
    deal.currentBalance = 0
    g_financeManager:removeDeal(deal.id)

    if CreditHistory then
        CreditHistory.recordEvent(self.farmId, "LEASE_TERMINATED_EARLY", deal.vehicleName)
    end

    local notificationText
    if totalPenalty > 0 then
        notificationText = string.format(g_i18n:getText("usedplus_notification_leaseTerminated"), deal.vehicleName, g_i18n:formatMoney(totalPenalty))
    else
        notificationText = string.format(g_i18n:getText("usedplus_notification_leaseTerminatedNoPenalty"), deal.vehicleName)
    end

    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, notificationText)
    TransactionResponseEvent.sendToClient(connection, self.farmId, true, "usedplus_mp_success_lease_terminated")

    -- v2.15.0: Broadcast deal removal to all clients
    SyncFinanceDealsEvent.broadcastAddForFarm(self.farmId)

    UsedPlus.logDebug(string.format("Lease terminated: %s (penalty: $%.2f)", deal.vehicleName, totalPenalty))
end

--============================================================================
-- LEASE RENEWAL EVENT
-- Network event for handling lease renewal with equity rollover
--============================================================================

LeaseRenewalEvent = {}
local LeaseRenewalEvent_mt = Class(LeaseRenewalEvent, Event)

InitEventClass(LeaseRenewalEvent, "LeaseRenewalEvent")

-- Action constants (match LeaseRenewalDialog)
LeaseRenewalEvent.ACTION_RETURN = 1
LeaseRenewalEvent.ACTION_BUYOUT = 2
LeaseRenewalEvent.ACTION_RENEW = 3

function LeaseRenewalEvent.emptyNew()
    local self = Event.new(LeaseRenewalEvent_mt)
    return self
end

function LeaseRenewalEvent.new(dealId, action, data)
    local self = LeaseRenewalEvent.emptyNew()
    self.dealId = dealId
    self.action = action
    self.data = data or {}
    return self
end

function LeaseRenewalEvent.sendToServer(dealId, action, data)
    local event = LeaseRenewalEvent.new(dealId, action, data)
    if g_server ~= nil then
        event:run(nil)  -- v2.9.1: Server doesn't need connection
    elseif g_client then
        g_client:getServerConnection():sendEvent(event)
    else
        UsedPlus.logError("LeaseRenewalEvent: g_client is nil, cannot send to server")
    end
end

function LeaseRenewalEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.dealId)
    streamWriteInt32(streamId, self.action)

    -- Serialize data based on action
    if self.action == LeaseRenewalEvent.ACTION_RETURN then
        streamWriteFloat32(streamId, self.data.depositRefund or 0)
        streamWriteFloat32(streamId, self.data.damagePenalty or 0)
    elseif self.action == LeaseRenewalEvent.ACTION_BUYOUT then
        streamWriteFloat32(streamId, self.data.buyoutPrice or 0)
        streamWriteFloat32(streamId, self.data.equityApplied or 0)
        streamWriteFloat32(streamId, self.data.depositRefund or 0)
    elseif self.action == LeaseRenewalEvent.ACTION_RENEW then
        streamWriteFloat32(streamId, self.data.equityRollover or 0)
        streamWriteFloat32(streamId, self.data.newResidualValue or 0)
    end
end

function LeaseRenewalEvent:readStream(streamId, connection)
    self.dealId = streamReadString(streamId)
    self.action = streamReadInt32(streamId)
    self.data = {}

    -- v2.7.2 SECURITY: Validate action is one of the valid values
    local validActions = {
        LeaseRenewalEvent.ACTION_RETURN,
        LeaseRenewalEvent.ACTION_BUYOUT,
        LeaseRenewalEvent.ACTION_RENEW
    }
    local isValidAction = false
    for _, validAction in ipairs(validActions) do
        if self.action == validAction then
            isValidAction = true
            break
        end
    end
    if not isValidAction then
        UsedPlus.logError(string.format("[SECURITY] Invalid lease renewal action: %d", self.action))
        -- CRITICAL: Don't read action-specific data - writeStream wrote none for invalid actions.
        -- Reading here would consume bytes from the next event, corrupting the entire TCP stream.
        self:run(connection)
        return
    end

    -- Deserialize data based on action
    if self.action == LeaseRenewalEvent.ACTION_RETURN then
        self.data.depositRefund = streamReadFloat32(streamId)
        self.data.damagePenalty = streamReadFloat32(streamId)
    elseif self.action == LeaseRenewalEvent.ACTION_BUYOUT then
        self.data.buyoutPrice = streamReadFloat32(streamId)
        self.data.equityApplied = streamReadFloat32(streamId)
        self.data.depositRefund = streamReadFloat32(streamId)
    elseif self.action == LeaseRenewalEvent.ACTION_RENEW then
        self.data.equityRollover = streamReadFloat32(streamId)
        self.data.newResidualValue = streamReadFloat32(streamId)
    end

    self:run(connection)
end

function LeaseRenewalEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    if g_financeManager == nil then
        UsedPlus.logError("FinanceManager not initialized")
        -- Note: No farmId available yet, can't send response
        return
    end

    local deal = g_financeManager:getDealById(self.dealId)
    if deal == nil then
        UsedPlus.logError(string.format("Deal %s not found", self.dealId))
        -- Note: No farmId available, can't send response
        return
    end

    -- v2.7.2: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, deal.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("LEASE_RENEWAL_REJECTED",
            string.format("Unauthorized lease renewal attempt for deal %s (farmId %d): %s",
                self.dealId, deal.farmId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, deal.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    local farm = g_farmManager:getFarmById(deal.farmId)
    if farm == nil then
        UsedPlus.logError(string.format("Farm %d not found", deal.farmId))
        TransactionResponseEvent.sendToClient(connection, deal.farmId, false, "usedplus_mp_error_farm_not_found")
        return
    end

    local isLandLease = (deal.itemType == "land") or
                        (deal.itemId and string.find(deal.itemId or "", "farmland"))

    if self.action == LeaseRenewalEvent.ACTION_RETURN then
        self:processReturn(deal, farm, isLandLease, connection)
    elseif self.action == LeaseRenewalEvent.ACTION_BUYOUT then
        self:processBuyout(deal, farm, isLandLease, connection)
    elseif self.action == LeaseRenewalEvent.ACTION_RENEW then
        self:processRenew(deal, farm, isLandLease, connection)
    else
        UsedPlus.logError(string.format("Unknown lease renewal action: %d", self.action))
        TransactionResponseEvent.sendToClient(connection, deal.farmId, false, "usedplus_mp_error_invalid_action")
    end
end

--[[
    Process return action - give back asset, refund deposit
]]
function LeaseRenewalEvent:processReturn(deal, farm, isLandLease, connection)
    local depositRefund = self.data.depositRefund or 0

    -- Refund security deposit
    if depositRefund > 0 then
        g_currentMission:addMoney(depositRefund, deal.farmId, MoneyType.OTHER, true, true)
        UsedPlus.logDebug(string.format("Refunded security deposit: $%d", depositRefund))
    end

    if isLandLease then
        -- Revert land ownership
        local farmlandId = tonumber(deal.itemId) or tonumber(string.match(deal.itemId or "", "farmland_(%d+)"))
        if farmlandId then
            g_farmlandManager:setLandOwnership(farmlandId, FarmlandManager.NO_OWNER_FARM_ID)
        end

        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notification_landLeaseReturned"),
                deal.itemName, UIHelper.Text.formatMoney(depositRefund))
        )
    else
        -- Remove vehicle (v2.15.4: Clear lease flags before removal — Issue #34)
        local vehicle = self:findVehicle(deal)
        if vehicle then
            UsedPlus.logDebug(string.format("LeaseRenewalEvent:processReturn - found vehicle for %s (objectId=%s)", deal.itemName, tostring(deal.objectId)))
            vehicle.isLeased = false
            vehicle.leaseDealId = nil
            if vehicle.delete then
                vehicle:delete()
            end
        else
            -- v2.15.4: Vehicle not found — clear isLeased on ALL matching vehicles as safety net
            UsedPlus.logWarn(string.format("LeaseRenewalEvent:processReturn - vehicle NOT found for %s (objectId=%s, config=%s)", deal.itemName, tostring(deal.objectId), tostring(deal.vehicleConfig or deal.itemId)))
            local configFile = deal.itemId or deal.vehicleConfig
            if configFile then
                for _, v in pairs(g_currentMission.vehicleSystem.vehicles) do
                    if v.configFileName == configFile and v.ownerFarmId == deal.farmId and v.isLeased then
                        UsedPlus.logWarn(string.format("LeaseRenewalEvent:processReturn - clearing orphaned isLeased flag on %s", v:getName()))
                        v.isLeased = false
                        v.leaseDealId = nil
                    end
                end
            end
        end

        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notification_vehicleReturned"),
                deal.itemName, UIHelper.Text.formatMoney(depositRefund))
        )
    end

    -- Mark deal as completed and remove
    deal.status = "completed"
    g_financeManager:removeDeal(deal.id)

    -- Record credit event
    if CreditHistory then
        CreditHistory.recordEvent(deal.farmId, "LEASE_RETURNED", deal.itemName)
    end

    TransactionResponseEvent.sendToClient(connection, deal.farmId, true, "usedplus_mp_success_lease_returned")

    -- v2.15.0: Broadcast deal removal to all clients
    SyncFinanceDealsEvent.broadcastAddForFarm(deal.farmId)

    UsedPlus.logDebug(string.format("Lease returned: %s (refund: $%d)", deal.itemName, depositRefund))
end

--[[
    Process buyout action - purchase asset at residual minus equity
]]
function LeaseRenewalEvent:processBuyout(deal, farm, isLandLease, connection)
    local buyoutPrice = self.data.buyoutPrice or 0
    local equityApplied = self.data.equityApplied or 0
    local depositRefund = self.data.depositRefund or 0

    -- Check if farm can afford (net cost is buyout minus deposit refund)
    local netCost = buyoutPrice - depositRefund
    if netCost > farm.money then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_ERROR,
            string.format(g_i18n:getText("usedplus_notification_insufficientBuyout"),
                UIHelper.Text.formatMoney(netCost))
        )
        TransactionResponseEvent.sendToClient(connection, deal.farmId, false, "usedplus_mp_error_insufficient_funds")
        return
    end

    -- Charge buyout price
    if buyoutPrice > 0 then
        g_currentMission:addMoney(-buyoutPrice, deal.farmId, MoneyType.SHOP_VEHICLE_BUY, true, true)
    end

    -- Refund deposit separately (so it shows in finances)
    if depositRefund > 0 then
        g_currentMission:addMoney(depositRefund, deal.farmId, MoneyType.OTHER, true, true)
    end

    if isLandLease then
        -- Land is already owned - just remove the lease
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notification_landPurchasedEquity"),
                deal.itemName, UIHelper.Text.formatMoney(equityApplied))
        )
    else
        -- Vehicle becomes owned (update flags)
        local vehicle = self:findVehicle(deal)
        if vehicle then
            vehicle.isLeased = false
            vehicle.leaseDealId = nil
        end

        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notification_vehiclePurchasedEquity"),
                deal.itemName, UIHelper.Text.formatMoney(equityApplied))
        )
    end

    -- Mark deal as completed and remove
    deal.status = "completed"
    g_financeManager:removeDeal(deal.id)

    -- Record credit event
    if CreditHistory then
        CreditHistory.recordEvent(deal.farmId, "LEASE_BOUGHT_OUT", deal.itemName)
    end

    TransactionResponseEvent.sendToClient(connection, deal.farmId, true, "usedplus_mp_success_lease_buyout")

    -- v2.15.0: Broadcast deal removal to all clients
    SyncFinanceDealsEvent.broadcastAddForFarm(deal.farmId)

    UsedPlus.logDebug(string.format("Lease bought out: %s (price: $%d, equity: $%d)",
        deal.itemName, buyoutPrice, equityApplied))
end

--[[
    Process renew action - extend lease with equity rollover
]]
function LeaseRenewalEvent:processRenew(deal, farm, isLandLease, connection)
    local equityRollover = self.data.equityRollover or 0
    local newResidualValue = self.data.newResidualValue or deal.residualValue or 0

    -- Reset months paid but keep accumulated data
    local previousMonthsPaid = deal.monthsPaid

    -- Update deal for new term
    deal.monthsPaid = 0
    deal.status = "active"

    -- Apply equity rollover - reduce residual value
    deal.residualValue = newResidualValue

    -- Track accumulated equity across renewals
    deal.totalEquityAccumulated = (deal.totalEquityAccumulated or 0) + equityRollover

    -- Reset expiration warnings if applicable
    deal.warned3Months = false
    deal.warned1Month = false
    deal.warned1Week = false

    -- Recalculate current balance for UI
    local remainingMonths = deal.termMonths - deal.monthsPaid
    deal.currentBalance = deal.monthlyPayment * remainingMonths + deal.residualValue

    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format(g_i18n:getText("usedplus_notification_leaseRenewed"),
            deal.itemName, UIHelper.Text.formatMoney(equityRollover))
    )

    -- Record credit event
    if CreditHistory then
        CreditHistory.recordEvent(deal.farmId, "LEASE_RENEWED", deal.itemName)
    end

    TransactionResponseEvent.sendToClient(connection, deal.farmId, true, "usedplus_mp_success_lease_renewed")

    -- v2.15.0: Broadcast deal update (renewal) to all clients
    SyncFinanceDealsEvent.broadcastAddForFarm(deal.farmId)

    UsedPlus.logDebug(string.format("Lease renewed: %s (equity rollover: $%d, new residual: $%d)",
        deal.itemName, equityRollover, newResidualValue))
end

--[[
    Find vehicle for a deal
]]
function LeaseRenewalEvent:findVehicle(deal)
    -- v2.15.4: Enhanced logging for Issue #34 diagnosis
    if deal.objectId then
        local vehicle = NetworkUtil.getObject(deal.objectId)
        if vehicle then
            UsedPlus.logDebug(string.format("findVehicle: found by objectId %s", tostring(deal.objectId)))
            return vehicle
        end
        UsedPlus.logDebug(string.format("findVehicle: objectId %s returned nil, trying configFile fallback", tostring(deal.objectId)))
    end

    local configFile = deal.itemId or deal.vehicleConfig
    if configFile then
        for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
            if vehicle.configFileName == configFile and
               vehicle.ownerFarmId == deal.farmId then
                UsedPlus.logDebug(string.format("findVehicle: found by configFile match: %s", configFile))
                return vehicle
            end
        end
        UsedPlus.logDebug(string.format("findVehicle: no vehicle matches configFile=%s farmId=%d", configFile, deal.farmId or 0))
    else
        UsedPlus.logWarn("findVehicle: no configFile available (itemId and vehicleConfig both nil)")
    end

    return nil
end

--============================================================================

UsedPlus.logInfo("LeaseEvents loaded (LeaseVehicleEvent, LeaseEndEvent, TerminateLeaseEvent, LeaseRenewalEvent)")
