--[[
    FS25_UsedPlus - Bulk Sync Handler (Multiplayer Join-Time Sync)

    When a client finishes loading in multiplayer, the server sends
    ALL current state for every farm: finance deals, sale listings,
    searches, statistics, and credit/payment data.

    Uses targeted connection:sendEvent() (not broadcastEvent) to
    only send to the joining client.

    v2.15.0 - Issue #17: Fix multiplayer data sync for dedicated servers
]]

BulkSyncHandler = {}

--[[
    Initialize the bulk sync handler.
    Hooks FSBaseMission.onConnectionFinishedLoading to trigger sync.
    Called from main.lua or wherever mod initialization happens.
]]
function BulkSyncHandler.install()
    -- Only install on server (server sends data to joining clients)
    if g_server == nil then
        UsedPlus.logDebug("BulkSyncHandler: Not server, skipping install")
        return
    end

    -- Hook into FSBaseMission.onConnectionFinishedLoading
    if FSBaseMission.onConnectionFinishedLoading ~= nil then
        local originalFunc = FSBaseMission.onConnectionFinishedLoading
        FSBaseMission.onConnectionFinishedLoading = function(mission, connection, ...)
            -- Call original first (ensures game state is fully loaded for client)
            originalFunc(mission, connection, ...)

            -- Then send our mod data
            BulkSyncHandler.syncAllDataToConnection(connection)
        end
        UsedPlus.logInfo("BulkSyncHandler installed - will sync data to joining clients")
    else
        UsedPlus.logWarn("BulkSyncHandler: FSBaseMission.onConnectionFinishedLoading not found, cannot hook")
    end
end

--[[
    Send ALL mod data to a specific client connection.
    Called when a client finishes loading into the game.
    @param connection - The network connection to the joining client
]]
function BulkSyncHandler.syncAllDataToConnection(connection)
    if connection == nil then
        UsedPlus.logWarn("BulkSyncHandler: nil connection, skipping sync")
        return
    end

    UsedPlus.logInfo("BulkSyncHandler: Starting bulk sync for joining client")

    local totalEvents = 0

    -- Get all farms
    local farms = g_farmManager:getFarms()
    if farms == nil then
        UsedPlus.logWarn("BulkSyncHandler: No farms found")
        return
    end

    for _, farm in pairs(farms) do
        local farmId = farm.farmId

        -- Skip spectator farm (farmId 0) and invalid farms
        if farmId ~= nil and farmId > 0 then
            -- 1. Sync finance deals
            if g_financeManager then
                local deals = g_financeManager:getDealsForFarm(farmId) or {}
                if #deals > 0 then
                    SyncFinanceDealsEvent.sendToConnection(connection, farmId, deals)
                    totalEvents = totalEvents + 1
                    UsedPlus.logDebug(string.format("BulkSync: Sent %d finance deals for farm %d", #deals, farmId))
                end
            end

            -- 2. Sync sale listings
            if g_vehicleSaleManager then
                local listings = g_vehicleSaleManager:getListingsForFarm(farmId) or {}
                if #listings > 0 then
                    SyncSaleListingsEvent.sendToConnection(connection, farmId, listings)
                    totalEvents = totalEvents + 1
                    UsedPlus.logDebug(string.format("BulkSync: Sent %d sale listings for farm %d", #listings, farmId))
                end
            end

            -- 3. Sync used vehicle searches
            if g_usedVehicleManager then
                local searches = g_usedVehicleManager:getSearchesForFarm(farmId) or {}
                if #searches > 0 then
                    SyncSearchesEvent.sendToConnection(connection, farmId, searches)
                    totalEvents = totalEvents + 1
                    UsedPlus.logDebug(string.format("BulkSync: Sent %d searches for farm %d", #searches, farmId))
                end
            end

            -- 4. Sync statistics
            if g_financeManager and g_financeManager.statisticsByFarm[farmId] then
                local stats = g_financeManager:getStatistics(farmId)
                SyncStatisticsEvent.sendToConnection(connection, farmId, stats)
                totalEvents = totalEvents + 1
            end

            -- 5. Sync payment tracker / credit data
            if PaymentTracker and PaymentTracker.farmData[farmId] then
                local data = PaymentTracker.getFarmData(farmId)
                local payments = data.payments or {}
                -- Send last 24 payments
                local startIdx = math.max(1, #payments - 23)
                local recentPayments = {}
                for i = startIdx, #payments do
                    table.insert(recentPayments, payments[i])
                end
                SyncPaymentTrackerEvent.sendToConnection(connection, farmId, data.stats, recentPayments)
                totalEvents = totalEvents + 1
            end
        end
    end

    -- 6. Sync global settings (not per-farm)
    UsedPlusSettingsEvent.sendAllToConnection(connection)
    totalEvents = totalEvents + 1

    UsedPlus.logInfo(string.format("BulkSyncHandler: Sent %d sync events to joining client", totalEvents))
end

UsedPlus.logInfo("BulkSyncHandler loaded - multiplayer join-time sync ready")
