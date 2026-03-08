--[[
    FS25_UsedPlus - Service Truck Discovery System

    The Service Truck is a premium endgame tool that must be DISCOVERED
    through National Agent transactions, not simply purchased from shop.

    Prerequisites (ALL required):
    - 3+ OBD Scanner uses
    - 700+ credit score (Good or better)
    - Owns a vehicle with reliability ceiling < 90%
    - Has not already discovered the truck

    Trigger: 20% chance after any National Agent transaction (buy or sell)

    Purchase: CASH ONLY - $67,500 (10% connection discount)

    v2.9.0 - Service Truck System
]]

ServiceTruckDiscovery = {}

-- Constants
ServiceTruckDiscovery.DISCOVERY_CHANCE = 0.20  -- 20% chance per eligible transaction
ServiceTruckDiscovery.REQUIRED_OBD_USES = 3
ServiceTruckDiscovery.REQUIRED_CREDIT_SCORE = 700
ServiceTruckDiscovery.REQUIRED_CEILING_THRESHOLD = 0.90
ServiceTruckDiscovery.BASE_PRICE = 75000
ServiceTruckDiscovery.DISCOUNT_PERCENT = 0.10  -- 10% connection discount
ServiceTruckDiscovery.DISCOUNTED_PRICE = 67500  -- $75,000 * 0.90
ServiceTruckDiscovery.OPPORTUNITY_EXPIRY_DAYS = 30  -- Game days until opportunity expires
ServiceTruckDiscovery.PITY_TIMER_THRESHOLD = 10  -- Guarantee discovery after this many eligible transactions

-- State tracking (per farm)
ServiceTruckDiscovery.farmData = {}

--[[
    Initialize farm data structure
]]
function ServiceTruckDiscovery.initFarmData(farmId)
    if ServiceTruckDiscovery.farmData[farmId] == nil then
        ServiceTruckDiscovery.farmData[farmId] = {
            -- Discovery state
            hasDiscovered = false,           -- True once truck is discovered
            hasPurchased = false,            -- True once truck is purchased

            -- Opportunity tracking
            opportunityActive = false,       -- True if opportunity is currently available
            opportunityExpiry = 0,           -- Game time when opportunity expires

            -- Pity timer
            eligibleTransactions = 0,        -- Count of transactions that met prerequisites

            -- Prerequisites tracking (for UI display)
            obdUsesCount = 0,                -- Tracked separately for discovery
        }
    end
    return ServiceTruckDiscovery.farmData[farmId]
end

--[[
    Get farm data, initializing if needed
]]
function ServiceTruckDiscovery.getFarmData(farmId)
    return ServiceTruckDiscovery.initFarmData(farmId)
end

--[[
    Check if player meets all prerequisites for discovery
]]
function ServiceTruckDiscovery.checkPrerequisites(farmId)
    local data = ServiceTruckDiscovery.getFarmData(farmId)

    -- Already discovered or purchased - no need to discover again
    if data.hasDiscovered or data.hasPurchased then
        return false, "already_discovered"
    end

    -- Opportunity already active
    if data.opportunityActive then
        return false, "opportunity_active"
    end

    -- Check OBD uses
    local obdUses = ServiceTruckDiscovery.getOBDUsageCount(farmId)
    if obdUses < ServiceTruckDiscovery.REQUIRED_OBD_USES then
        return false, "obd_uses", obdUses
    end

    -- Check credit score
    local creditScore = 650  -- Default
    if CreditBureau and CreditBureau.getCreditScore then
        creditScore = CreditBureau.getCreditScore(farmId)
    end
    if creditScore < ServiceTruckDiscovery.REQUIRED_CREDIT_SCORE then
        return false, "credit_score", creditScore
    end

    -- Check for vehicle with degraded ceiling
    local hasDegradedVehicle = ServiceTruckDiscovery.checkForDegradedCeiling(farmId)
    if not hasDegradedVehicle then
        return false, "no_degraded_ceiling"
    end

    return true, "eligible"
end

--[[
    Get OBD Scanner usage count for farm
    Counts unique component diagnoses across all vehicles
]]
function ServiceTruckDiscovery.getOBDUsageCount(farmId)
    local count = 0

    if g_currentMission and g_currentMission.vehicleSystem then
        for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles) do
            if vehicle:getOwnerFarmId() == farmId then
                local maintSpec = vehicle.spec_usedPlusMaintenance
                if maintSpec and maintSpec.obdDiagnosesUsed then
                    -- Count each diagnosed component
                    if maintSpec.obdDiagnosesUsed.engine then count = count + 1 end
                    if maintSpec.obdDiagnosesUsed.electrical then count = count + 1 end
                    if maintSpec.obdDiagnosesUsed.hydraulic then count = count + 1 end
                end
            end
        end
    end

    return count
end

--[[
    Check if farm owns any vehicle with ceiling < threshold
]]
function ServiceTruckDiscovery.checkForDegradedCeiling(farmId)
    if g_currentMission and g_currentMission.vehicleSystem then
        for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles) do
            if vehicle:getOwnerFarmId() == farmId then
                local maintSpec = vehicle.spec_usedPlusMaintenance
                if maintSpec and maintSpec.maxReliabilityCeiling then
                    if maintSpec.maxReliabilityCeiling < ServiceTruckDiscovery.REQUIRED_CEILING_THRESHOLD then
                        return true
                    end
                end
            end
        end
    end
    return false
end

--[[
    Called when a National Agent transaction completes
    Returns true if discovery was triggered
]]
function ServiceTruckDiscovery.onNationalAgentTransaction(farmId, transactionType)
    local data = ServiceTruckDiscovery.getFarmData(farmId)

    -- Check prerequisites
    local eligible, reason = ServiceTruckDiscovery.checkPrerequisites(farmId)
    if not eligible then
        UsedPlus.logDebug("ServiceTruckDiscovery: Not eligible - %s", reason)
        return false
    end

    -- Increment eligible transaction counter
    data.eligibleTransactions = data.eligibleTransactions + 1
    UsedPlus.logInfo("ServiceTruckDiscovery: Eligible transaction #%d (type: %s)",
        data.eligibleTransactions, transactionType or "unknown")

    -- Roll for discovery (or pity timer)
    local roll = math.random()
    local threshold = ServiceTruckDiscovery.DISCOVERY_CHANCE

    -- Pity timer: guarantee after threshold
    if data.eligibleTransactions >= ServiceTruckDiscovery.PITY_TIMER_THRESHOLD then
        threshold = 1.0  -- 100% chance
        UsedPlus.logInfo("ServiceTruckDiscovery: Pity timer triggered!")
    end

    if roll <= threshold then
        -- Discovery triggered!
        ServiceTruckDiscovery.triggerDiscovery(farmId, transactionType)
        return true
    else
        UsedPlus.logDebug("ServiceTruckDiscovery: Roll failed (%.2f > %.2f)", roll, threshold)
        return false
    end
end

--[[
    Trigger the Service Truck discovery
]]
function ServiceTruckDiscovery.triggerDiscovery(farmId, transactionType)
    local data = ServiceTruckDiscovery.getFarmData(farmId)

    data.hasDiscovered = true
    data.opportunityActive = true
    data.opportunityExpiry = g_currentMission.time +
        (ServiceTruckDiscovery.OPPORTUNITY_EXPIRY_DAYS * 24 * 60 * 60 * 1000)  -- Convert days to ms

    UsedPlus.logInfo("ServiceTruckDiscovery: TRIGGERED for farm %d via %s transaction!",
        farmId, transactionType or "unknown")

    -- Show discovery dialog (only for local player's farm)
    if farmId == g_currentMission:getFarmId() then
        ServiceTruckDiscovery.showDiscoveryDialog()
    end

    -- Sync to other players in multiplayer
    if g_server ~= nil then
        ServiceTruckDiscoveryEvent.broadcastDiscovery(farmId)
    elseif g_client ~= nil then
        -- Client triggered - send to server
        ServiceTruckDiscoveryEvent.sendDiscoveryToServer(farmId)
    end
end

--[[
    Show the discovery dialog
]]
function ServiceTruckDiscovery.showDiscoveryDialog()
    -- Use the DialogLoader pattern for consistent lazy loading
    DialogLoader.show("ServiceTruckDiscoveryDialog", "setDiscoveryData", ServiceTruckDiscovery.DISCOUNTED_PRICE)
end

--[[
    Called when player accepts the opportunity
    Returns true if purchase successful
]]
function ServiceTruckDiscovery.acceptOpportunity(farmId)
    local data = ServiceTruckDiscovery.getFarmData(farmId)

    if not data.opportunityActive then
        UsedPlus.logWarn("ServiceTruckDiscovery: No active opportunity for farm %d", farmId)
        return false, "no_opportunity"
    end

    -- Check cash
    local farm = g_farmManager:getFarmById(farmId)
    if not farm then
        return false, "invalid_farm"
    end

    local currentMoney = farm.money
    if currentMoney < ServiceTruckDiscovery.DISCOUNTED_PRICE then
        return false, "insufficient_funds", currentMoney
    end

    -- Execute purchase (server-side)
    if g_server ~= nil or g_currentMission:getIsServer() then
        -- Deduct money
        g_currentMission:addMoney(-ServiceTruckDiscovery.DISCOUNTED_PRICE, farmId,
            MoneyType.VEHICLE_RUNNING_COSTS, true, true)

        -- Spawn the service truck
        local success = ServiceTruckDiscovery.spawnServiceTruck(farmId)

        if success then
            data.hasPurchased = true
            data.opportunityActive = false
            data.opportunityExpiry = 0

            UsedPlus.logInfo("ServiceTruckDiscovery: Farm %d purchased Service Truck for $%d",
                farmId, ServiceTruckDiscovery.DISCOUNTED_PRICE)

            -- Show success notification
            if farmId == g_currentMission:getFarmId() then
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_OK,
                    g_i18n:getText("usedplus_serviceTruck_purchaseSuccess")
                )
            end

            return true
        else
            -- Refund on spawn failure
            g_currentMission:addMoney(ServiceTruckDiscovery.DISCOUNTED_PRICE, farmId,
                MoneyType.VEHICLE_RUNNING_COSTS, true, true)
            return false, "spawn_failed"
        end
    else
        -- Client - send to server
        ServiceTruckDiscoveryEvent.sendPurchaseToServer(farmId)
        return true  -- Optimistic
    end
end

--[[
    Spawn the service truck for the farm
]]
function ServiceTruckDiscovery.spawnServiceTruck(farmId)
    local storeItem = g_storeManager:getItemByXMLFilename("FS25_UsedPlus/vehicles/serviceTruck/serviceTruck.xml")
    if not storeItem then
        UsedPlus.logError("ServiceTruckDiscovery: Could not find service truck store item!")
        return false
    end

    -- Find a spawn point (use shop spawn location)
    local x, y, z = 0, 0, 0
    local rx, ry, rz = 0, 0, 0

    if g_currentMission.shopPlaceable then
        local spawnPoint = g_currentMission.shopPlaceable:getVehicleSpawnPoint()
        if spawnPoint then
            x, y, z = getWorldTranslation(spawnPoint)
            rx, ry, rz = getWorldRotation(spawnPoint)
        end
    end

    -- Spawn the vehicle
    local vehicle = g_currentMission.vehicleSystem:loadVehicle(
        storeItem.xmlFilename,
        x, y, z,
        rx, ry, rz,
        true,  -- addToPhysics
        farmId,
        nil,   -- propertyState
        nil,   -- asyncCallbackFunction
        nil,   -- asyncCallbackObject
        nil,   -- asyncCallbackArguments
        nil,   -- configurations
        nil    -- boughtConfigurations
    )

    if vehicle then
        UsedPlus.logInfo("ServiceTruckDiscovery: Service truck spawned successfully")
        return true
    else
        UsedPlus.logError("ServiceTruckDiscovery: Failed to spawn service truck")
        return false
    end
end

--[[
    Called when player declines the opportunity
]]
function ServiceTruckDiscovery.declineOpportunity(farmId)
    local data = ServiceTruckDiscovery.getFarmData(farmId)

    -- Keep opportunity active but player passed for now
    -- They can still access it from Finance Manager until expiry
    UsedPlus.logInfo("ServiceTruckDiscovery: Farm %d declined opportunity (expires in %d days)",
        farmId, ServiceTruckDiscovery.OPPORTUNITY_EXPIRY_DAYS)

    -- Show reminder notification
    if farmId == g_currentMission:getFarmId() then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_serviceTruck_opportunitySaved")
        )
    end
end

--[[
    Check for expired opportunities (called on hour change)
]]
function ServiceTruckDiscovery.checkExpiredOpportunities()
    local currentTime = g_currentMission.time

    for farmId, data in pairs(ServiceTruckDiscovery.farmData) do
        if data.opportunityActive and data.opportunityExpiry > 0 then
            if currentTime >= data.opportunityExpiry then
                data.opportunityActive = false
                data.opportunityExpiry = 0
                -- Note: hasDiscovered stays true, so they won't get another chance
                -- unless we want to allow re-discovery

                UsedPlus.logInfo("ServiceTruckDiscovery: Opportunity expired for farm %d", farmId)

                if farmId == g_currentMission:getFarmId() then
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_WARNING,
                        g_i18n:getText("usedplus_serviceTruck_opportunityExpired")
                    )
                end
            end
        end
    end
end

--[[
    Get remaining days until opportunity expires
]]
function ServiceTruckDiscovery.getOpportunityRemainingDays(farmId)
    local data = ServiceTruckDiscovery.getFarmData(farmId)

    if not data.opportunityActive then
        return 0
    end

    local remainingMs = data.opportunityExpiry - g_currentMission.time
    if remainingMs <= 0 then
        return 0
    end

    return math.ceil(remainingMs / (24 * 60 * 60 * 1000))  -- Convert ms to days
end

--[[
    Check if Service Truck should be visible in shop
    Returns false to hide from shop (must use discovery system)
]]
function ServiceTruckDiscovery.isServiceTruckVisibleInShop(farmId)
    -- Always hidden from regular shop - must be discovered
    return false
end

--[[
    Get discovery status for UI display
]]
function ServiceTruckDiscovery.getDiscoveryStatus(farmId)
    local data = ServiceTruckDiscovery.getFarmData(farmId)

    return {
        hasDiscovered = data.hasDiscovered,
        hasPurchased = data.hasPurchased,
        opportunityActive = data.opportunityActive,
        remainingDays = ServiceTruckDiscovery.getOpportunityRemainingDays(farmId),
        eligibleTransactions = data.eligibleTransactions,
        price = ServiceTruckDiscovery.DISCOUNTED_PRICE
    }
end

--[[
    Get prerequisites status for UI display
]]
function ServiceTruckDiscovery.getPrerequisitesStatus(farmId)
    local obdUses = ServiceTruckDiscovery.getOBDUsageCount(farmId)
    local creditScore = 650
    if CreditBureau and CreditBureau.getCreditScore then
        creditScore = CreditBureau.getCreditScore(farmId)
    end
    local hasDegradedVehicle = ServiceTruckDiscovery.checkForDegradedCeiling(farmId)

    return {
        obdUses = obdUses,
        obdRequired = ServiceTruckDiscovery.REQUIRED_OBD_USES,
        obdMet = obdUses >= ServiceTruckDiscovery.REQUIRED_OBD_USES,

        creditScore = creditScore,
        creditRequired = ServiceTruckDiscovery.REQUIRED_CREDIT_SCORE,
        creditMet = creditScore >= ServiceTruckDiscovery.REQUIRED_CREDIT_SCORE,

        hasDegradedVehicle = hasDegradedVehicle,
        ceilingMet = hasDegradedVehicle
    }
end

--[[
    Save discovery data to savegame
]]
function ServiceTruckDiscovery.saveToXML(xmlFile, key)
    for farmId, data in pairs(ServiceTruckDiscovery.farmData) do
        local farmKey = string.format("%s.farm(%d)", key, farmId - 1)

        xmlFile:setInt(farmKey .. "#farmId", farmId)
        xmlFile:setBool(farmKey .. "#hasDiscovered", data.hasDiscovered)
        xmlFile:setBool(farmKey .. "#hasPurchased", data.hasPurchased)
        xmlFile:setBool(farmKey .. "#opportunityActive", data.opportunityActive)
        xmlFile:setFloat(farmKey .. "#opportunityExpiry", data.opportunityExpiry)
        xmlFile:setInt(farmKey .. "#eligibleTransactions", data.eligibleTransactions)
    end

    UsedPlus.logDebug("ServiceTruckDiscovery: Saved data for %d farms",
        table.size(ServiceTruckDiscovery.farmData))
end

--[[
    Load discovery data from savegame
]]
function ServiceTruckDiscovery.loadFromXML(xmlFile, key)
    ServiceTruckDiscovery.farmData = {}

    local i = 0
    while true do
        local farmKey = string.format("%s.farm(%d)", key, i)
        if not xmlFile:hasProperty(farmKey) then
            break
        end

        local farmId = xmlFile:getInt(farmKey .. "#farmId", 0)
        if farmId > 0 then
            local data = ServiceTruckDiscovery.initFarmData(farmId)
            data.hasDiscovered = xmlFile:getBool(farmKey .. "#hasDiscovered", false)
            data.hasPurchased = xmlFile:getBool(farmKey .. "#hasPurchased", false)
            data.opportunityActive = xmlFile:getBool(farmKey .. "#opportunityActive", false)
            data.opportunityExpiry = xmlFile:getFloat(farmKey .. "#opportunityExpiry", 0)
            data.eligibleTransactions = xmlFile:getInt(farmKey .. "#eligibleTransactions", 0)
        end

        i = i + 1
    end

    UsedPlus.logDebug("ServiceTruckDiscovery: Loaded data for %d farms",
        table.size(ServiceTruckDiscovery.farmData))
end

--[[
    Reset discovery state (for testing)
]]
function ServiceTruckDiscovery.resetDiscovery(farmId)
    local data = ServiceTruckDiscovery.getFarmData(farmId)
    data.hasDiscovered = false
    data.hasPurchased = false
    data.opportunityActive = false
    data.opportunityExpiry = 0
    data.eligibleTransactions = 0
    UsedPlus.logInfo("ServiceTruckDiscovery: Reset discovery state for farm %d", farmId)
end


UsedPlus.logInfo("ServiceTruckDiscovery loaded - Endgame tool discovery system ready")
