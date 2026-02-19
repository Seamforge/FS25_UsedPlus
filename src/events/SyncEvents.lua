--[[
    FS25_UsedPlus - Sync Events (Multiplayer State Propagation)

    Contains 5 sync event classes for broadcasting server state to clients.
    These events have INVERTED guard logic vs mutating events:
    - Mutating events: Client→Server (execute on server, guard rejects server-to-client)
    - Sync events: Server→Client (execute on client, guard rejects client-to-server)

    v2.15.0 - Issue #17: Fix multiplayer data sync for dedicated servers

    Event Classes:
    1. SyncFinanceDealsEvent - Finance/lease/loan deals (FULL_SYNC, ADD, REMOVE, UPDATE)
    2. SyncSaleListingsEvent - Vehicle sale listings (FULL_SYNC)
    3. SyncSearchesEvent - Used vehicle searches + found listings (FULL_SYNC)
    4. SyncStatisticsEvent - Per-farm statistics counters (FULL_SYNC)
    5. SyncPaymentTrackerEvent - Credit/payment history (FULL_SYNC)
]]

-- Sync mode constants (shared across all sync events)
local SYNC_MODE = {
    FULL_SYNC = 1,  -- Replace all data for a farm
    ADD = 2,        -- Add/replace a single entry
    REMOVE = 3,     -- Remove a single entry by ID
    UPDATE = 4,     -- Update mutable fields of a single entry
}

--============================================================================
-- SYNC FINANCE DEALS EVENT
-- Syncs finance/lease/loan deals to clients
--============================================================================

SyncFinanceDealsEvent = {}
local SyncFinanceDealsEvent_mt = Class(SyncFinanceDealsEvent, Event)

InitEventClass(SyncFinanceDealsEvent, "SyncFinanceDealsEvent")

function SyncFinanceDealsEvent.emptyNew()
    local self = Event.new(SyncFinanceDealsEvent_mt)
    return self
end

function SyncFinanceDealsEvent.new(farmId, mode, deals, removeDealId)
    local self = SyncFinanceDealsEvent.emptyNew()
    self.farmId = farmId
    self.mode = mode or SYNC_MODE.FULL_SYNC
    self.deals = deals or {}
    self.removeDealId = removeDealId or ""
    return self
end

--[[ Static broadcast helpers ]]

-- Full sync of all deals for a farm (used after add/major changes)
function SyncFinanceDealsEvent.broadcastAddForFarm(farmId)
    if g_server == nil then return end
    local deals = g_financeManager and g_financeManager:getDealsForFarm(farmId) or {}
    g_server:broadcastEvent(SyncFinanceDealsEvent.new(farmId, SYNC_MODE.FULL_SYNC, deals))
    UsedPlus.logTrace(string.format("SyncFinanceDeals: Broadcast FULL_SYNC for farm %d (%d deals)", farmId, #deals))
end

-- Remove a single deal by ID
function SyncFinanceDealsEvent.broadcastRemoveDeal(farmId, dealId)
    if g_server == nil then return end
    g_server:broadcastEvent(SyncFinanceDealsEvent.new(farmId, SYNC_MODE.REMOVE, {}, dealId))
    UsedPlus.logTrace(string.format("SyncFinanceDeals: Broadcast REMOVE deal %s for farm %d", dealId, farmId))
end

-- Update a single deal's mutable fields
function SyncFinanceDealsEvent.broadcastUpdateDeal(farmId, dealId)
    if g_server == nil then return end
    local deal = g_financeManager and g_financeManager:getDealById(dealId) or nil
    if deal then
        g_server:broadcastEvent(SyncFinanceDealsEvent.new(farmId, SYNC_MODE.UPDATE, {deal}))
        UsedPlus.logTrace(string.format("SyncFinanceDeals: Broadcast UPDATE deal %s for farm %d", dealId, farmId))
    end
end

-- Targeted sync to a specific connection (for bulk sync on join)
function SyncFinanceDealsEvent.sendToConnection(connection, farmId, deals)
    if connection == nil then return end
    connection:sendEvent(SyncFinanceDealsEvent.new(farmId, SYNC_MODE.FULL_SYNC, deals))
end

function SyncFinanceDealsEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteInt32(streamId, self.mode)

    if self.mode == SYNC_MODE.REMOVE then
        streamWriteString(streamId, self.removeDealId)
        return
    end

    -- Write deals array
    local count = #self.deals
    streamWriteInt32(streamId, count)

    for _, deal in ipairs(self.deals) do
        -- Identity
        streamWriteString(streamId, deal.id or "")
        streamWriteInt32(streamId, deal.dealType or 1)
        streamWriteInt32(streamId, deal.farmId or self.farmId)
        streamWriteString(streamId, deal.itemType or "")
        streamWriteString(streamId, deal.itemId or "")
        streamWriteString(streamId, deal.itemName or "")

        -- Financial terms
        streamWriteFloat32(streamId, deal.originalPrice or 0)
        streamWriteFloat32(streamId, deal.downPayment or 0)
        streamWriteFloat32(streamId, deal.cashBack or 0)
        streamWriteFloat32(streamId, deal.amountFinanced or 0)
        streamWriteInt32(streamId, deal.termMonths or 12)
        streamWriteFloat32(streamId, deal.interestRate or 0)
        streamWriteFloat32(streamId, deal.monthlyPayment or 0)

        -- Payment status
        streamWriteFloat32(streamId, deal.currentBalance or 0)
        streamWriteInt32(streamId, deal.monthsPaid or 0)
        streamWriteFloat32(streamId, deal.totalInterestPaid or 0)
        streamWriteString(streamId, deal.status or "active")
        streamWriteInt32(streamId, deal.createdDate or 0)
        streamWriteInt32(streamId, deal.createdMonth or 1)
        streamWriteInt32(streamId, deal.createdYear or 2025)
        streamWriteInt32(streamId, deal.missedPayments or 0)

        -- Payment configuration
        streamWriteInt32(streamId, deal.paymentMode or 2)
        streamWriteFloat32(streamId, deal.paymentMultiplier or 1.0)
        streamWriteFloat32(streamId, deal.configuredPayment or 0)
        streamWriteFloat32(streamId, deal.lastPaymentAmount or 0)
        streamWriteFloat32(streamId, deal.accruedInterest or 0)

        -- Lease-specific fields
        streamWriteFloat32(streamId, deal.residualValue or 0)
        streamWriteFloat32(streamId, deal.securityDeposit or 0)
        streamWriteFloat32(streamId, deal.depreciation or 0)
        streamWriteFloat32(streamId, deal.tradeInValue or 0)

        -- Object ID (for leased vehicles)
        streamWriteInt32(streamId, deal.objectId or 0)

        -- Land lease fields
        streamWriteInt32(streamId, deal.farmlandId or 0)
        streamWriteString(streamId, deal.landName or "")

        -- v2.15.0: Collateral items (cash loans)
        local collateralCount = deal.collateralItems and #deal.collateralItems or 0
        streamWriteInt32(streamId, collateralCount)
        for _, item in ipairs(deal.collateralItems or {}) do
            streamWriteString(streamId, item.vehicleId or "")
            streamWriteInt32(streamId, item.objectId or 0)
            streamWriteString(streamId, item.configFile or "")
            streamWriteString(streamId, item.name or "")
            streamWriteFloat32(streamId, item.value or 0)
            streamWriteInt32(streamId, item.farmId or 0)
        end

        -- v2.15.0: Repossessed items (loan default history)
        local repossessedCount = deal.repossessedItems and #deal.repossessedItems or 0
        streamWriteInt32(streamId, repossessedCount)
        for _, item in ipairs(deal.repossessedItems or {}) do
            streamWriteString(streamId, item.name or "")
            streamWriteFloat32(streamId, item.value or 0)
            streamWriteString(streamId, item.configFile or "")
            streamWriteInt32(streamId, item.repossessedDate or 0)
            streamWriteInt32(streamId, item.repossessedMonth or 1)
            streamWriteInt32(streamId, item.repossessedYear or 2025)
            streamWriteBool(streamId, item.notFound or false)
        end
    end
end

function SyncFinanceDealsEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.mode = streamReadInt32(streamId)

    if self.mode == SYNC_MODE.REMOVE then
        self.removeDealId = streamReadString(streamId)
        self:run(connection)
        return
    end

    local count = streamReadInt32(streamId)
    self.deals = {}

    for _ = 1, count do
        local data = {}
        -- Identity
        data.id = streamReadString(streamId)
        data.dealType = streamReadInt32(streamId)
        data.farmId = streamReadInt32(streamId)
        data.itemType = streamReadString(streamId)
        data.itemId = streamReadString(streamId)
        data.itemName = streamReadString(streamId)

        -- Financial terms
        data.originalPrice = streamReadFloat32(streamId)
        data.downPayment = streamReadFloat32(streamId)
        data.cashBack = streamReadFloat32(streamId)
        data.amountFinanced = streamReadFloat32(streamId)
        data.termMonths = streamReadInt32(streamId)
        data.interestRate = streamReadFloat32(streamId)
        data.monthlyPayment = streamReadFloat32(streamId)

        -- Payment status
        data.currentBalance = streamReadFloat32(streamId)
        data.monthsPaid = streamReadInt32(streamId)
        data.totalInterestPaid = streamReadFloat32(streamId)
        data.status = streamReadString(streamId)
        data.createdDate = streamReadInt32(streamId)
        data.createdMonth = streamReadInt32(streamId)
        data.createdYear = streamReadInt32(streamId)
        data.missedPayments = streamReadInt32(streamId)

        -- Payment configuration
        data.paymentMode = streamReadInt32(streamId)
        data.paymentMultiplier = streamReadFloat32(streamId)
        data.configuredPayment = streamReadFloat32(streamId)
        data.lastPaymentAmount = streamReadFloat32(streamId)
        data.accruedInterest = streamReadFloat32(streamId)

        -- Lease-specific
        data.residualValue = streamReadFloat32(streamId)
        data.securityDeposit = streamReadFloat32(streamId)
        data.depreciation = streamReadFloat32(streamId)
        data.tradeInValue = streamReadFloat32(streamId)

        -- Object ID
        data.objectId = streamReadInt32(streamId)
        if data.objectId == 0 then data.objectId = nil end

        -- Land lease
        data.farmlandId = streamReadInt32(streamId)
        data.landName = streamReadString(streamId)
        if data.farmlandId == 0 then data.farmlandId = nil end
        if data.landName == "" then data.landName = nil end

        -- v2.15.0: Collateral items
        local collateralCount = streamReadInt32(streamId)
        data.collateralItems = {}
        for _ = 1, collateralCount do
            local item = {
                vehicleId = streamReadString(streamId),
                objectId = streamReadInt32(streamId),
                configFile = streamReadString(streamId),
                name = streamReadString(streamId),
                value = streamReadFloat32(streamId),
                farmId = streamReadInt32(streamId)
            }
            table.insert(data.collateralItems, item)
        end

        -- v2.15.0: Repossessed items
        local repossessedCount = streamReadInt32(streamId)
        data.repossessedItems = {}
        for _ = 1, repossessedCount do
            local item = {
                name = streamReadString(streamId),
                value = streamReadFloat32(streamId),
                configFile = streamReadString(streamId),
                repossessedDate = streamReadInt32(streamId),
                repossessedMonth = streamReadInt32(streamId),
                repossessedYear = streamReadInt32(streamId),
                notFound = streamReadBool(streamId)
            }
            table.insert(data.repossessedItems, item)
        end

        table.insert(self.deals, data)
    end

    self:run(connection)
end

function SyncFinanceDealsEvent:run(connection)
    -- Sync events execute on CLIENT when received FROM SERVER
    if connection == nil or not connection:getIsServer() then
        return
    end

    if g_financeManager == nil then return end

    if self.mode == SYNC_MODE.REMOVE then
        -- Remove a single deal
        local deal = g_financeManager:getDealById(self.removeDealId)
        if deal then
            g_financeManager:removeDeal(self.removeDealId)
            UsedPlus.logTrace(string.format("SyncFinanceDeals: Removed deal %s on client", self.removeDealId))
        end
        return
    end

    if self.mode == SYNC_MODE.UPDATE then
        -- Update mutable fields of existing deals
        for _, data in ipairs(self.deals) do
            local deal = g_financeManager:getDealById(data.id)
            if deal then
                deal.currentBalance = data.currentBalance
                deal.monthsPaid = data.monthsPaid
                deal.totalInterestPaid = data.totalInterestPaid
                deal.status = data.status
                deal.missedPayments = data.missedPayments
                deal.paymentMode = data.paymentMode
                deal.paymentMultiplier = data.paymentMultiplier
                deal.configuredPayment = data.configuredPayment
                deal.lastPaymentAmount = data.lastPaymentAmount
                deal.accruedInterest = data.accruedInterest
                UsedPlus.logTrace(string.format("SyncFinanceDeals: Updated deal %s on client", data.id))
            end
        end
        return
    end

    -- FULL_SYNC: Replace all deals for this farm
    -- First remove existing deals for this farm
    local existingDeals = g_financeManager:getDealsForFarm(self.farmId)
    if existingDeals then
        local idsToRemove = {}
        for _, deal in ipairs(existingDeals) do
            table.insert(idsToRemove, deal.id)
        end
        for _, id in ipairs(idsToRemove) do
            g_financeManager:removeDeal(id)
        end
    end

    -- Then add all synced deals
    for _, data in ipairs(self.deals) do
        local deal = FinanceDeal.fromSyncData(data)
        if deal then
            g_financeManager:registerDeal(deal)
        end
    end

    UsedPlus.logTrace(string.format("SyncFinanceDeals: FULL_SYNC applied %d deals for farm %d", #self.deals, self.farmId))
end

--============================================================================
-- SYNC SALE LISTINGS EVENT
-- Syncs vehicle sale listings to clients
--============================================================================

SyncSaleListingsEvent = {}
local SyncSaleListingsEvent_mt = Class(SyncSaleListingsEvent, Event)

InitEventClass(SyncSaleListingsEvent, "SyncSaleListingsEvent")

function SyncSaleListingsEvent.emptyNew()
    local self = Event.new(SyncSaleListingsEvent_mt)
    return self
end

function SyncSaleListingsEvent.new(farmId, listings)
    local self = SyncSaleListingsEvent.emptyNew()
    self.farmId = farmId
    self.listings = listings or {}
    return self
end

-- Broadcast full listing sync for a farm
function SyncSaleListingsEvent.broadcastFullForFarm(farmId)
    if g_server == nil then return end
    local listings = {}
    if g_vehicleSaleManager then
        listings = g_vehicleSaleManager:getListingsForFarm(farmId) or {}
    end
    g_server:broadcastEvent(SyncSaleListingsEvent.new(farmId, listings))
    UsedPlus.logTrace(string.format("SyncSaleListings: Broadcast FULL_SYNC for farm %d (%d listings)", farmId, #listings))
end

-- Targeted sync to a specific connection
function SyncSaleListingsEvent.sendToConnection(connection, farmId, listings)
    if connection == nil then return end
    connection:sendEvent(SyncSaleListingsEvent.new(farmId, listings))
end

function SyncSaleListingsEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)

    local count = #self.listings
    streamWriteInt32(streamId, count)

    for _, listing in ipairs(self.listings) do
        streamWriteString(streamId, listing.id or "")
        streamWriteInt32(streamId, listing.farmId or self.farmId)
        streamWriteString(streamId, tostring(listing.vehicleId or ""))
        streamWriteString(streamId, listing.vehicleConfigFile or "")
        streamWriteString(streamId, listing.vehicleName or "")
        streamWriteString(streamId, listing.vehicleImageFile or "")
        streamWriteFloat32(streamId, listing.vanillaSellPrice or 0)

        -- Condition
        streamWriteInt32(streamId, listing.repairPercent or 100)
        streamWriteInt32(streamId, listing.paintPercent or 100)
        streamWriteInt32(streamId, listing.operatingHours or 0)

        -- Sale parameters
        streamWriteInt32(streamId, listing.saleTier or 2)
        streamWriteInt32(streamId, listing.priceTier or 2)
        streamWriteFloat32(streamId, listing.agentFee or 0)
        streamWriteFloat32(streamId, listing.expectedMinPrice or 0)
        streamWriteFloat32(streamId, listing.expectedMaxPrice or 0)

        -- Timing
        streamWriteInt32(streamId, listing.ttl or 0)
        streamWriteInt32(streamId, listing.tts or 0)
        streamWriteInt32(streamId, listing.hoursElapsed or 0)

        -- Offer data
        streamWriteFloat32(streamId, listing.currentOffer or 0)
        streamWriteInt32(streamId, listing.offerExpiresIn or 0)
        streamWriteInt32(streamId, listing.offersReceived or 0)
        streamWriteInt32(streamId, listing.offersDeclined or 0)
        streamWriteBool(streamId, listing.offerShownToUser or false)

        -- Status
        streamWriteString(streamId, listing.status or "active")
        streamWriteInt32(streamId, listing.createdAt or 0)
        streamWriteInt32(streamId, listing.completedAt or 0)
        streamWriteFloat32(streamId, listing.finalSalePrice or 0)
    end
end

function SyncSaleListingsEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)

    local count = streamReadInt32(streamId)
    self.listings = {}

    for _ = 1, count do
        local data = {}
        data.id = streamReadString(streamId)
        data.farmId = streamReadInt32(streamId)
        data.vehicleId = streamReadString(streamId)
        data.vehicleConfigFile = streamReadString(streamId)
        data.vehicleName = streamReadString(streamId)
        data.vehicleImageFile = streamReadString(streamId)
        data.vanillaSellPrice = streamReadFloat32(streamId)

        data.repairPercent = streamReadInt32(streamId)
        data.paintPercent = streamReadInt32(streamId)
        data.operatingHours = streamReadInt32(streamId)

        data.saleTier = streamReadInt32(streamId)
        data.priceTier = streamReadInt32(streamId)
        data.agentFee = streamReadFloat32(streamId)
        data.expectedMinPrice = streamReadFloat32(streamId)
        data.expectedMaxPrice = streamReadFloat32(streamId)

        data.ttl = streamReadInt32(streamId)
        data.tts = streamReadInt32(streamId)
        data.hoursElapsed = streamReadInt32(streamId)

        local offer = streamReadFloat32(streamId)
        data.currentOffer = offer > 0 and offer or nil
        data.offerExpiresIn = streamReadInt32(streamId)
        data.offersReceived = streamReadInt32(streamId)
        data.offersDeclined = streamReadInt32(streamId)
        data.offerShownToUser = streamReadBool(streamId)

        data.status = streamReadString(streamId)
        data.createdAt = streamReadInt32(streamId)
        data.completedAt = streamReadInt32(streamId)
        data.finalSalePrice = streamReadFloat32(streamId)

        table.insert(self.listings, data)
    end

    self:run(connection)
end

function SyncSaleListingsEvent:run(connection)
    -- Sync events execute on CLIENT when received FROM SERVER
    if connection == nil or not connection:getIsServer() then
        return
    end

    if g_farmManager == nil then return end

    -- Replace all listings for this farm on the client
    local farm = g_farmManager:getFarmById(self.farmId)
    if farm == nil then return end

    -- Clear existing listings for this farm
    farm.vehicleSaleListings = {}

    -- Reconstruct listings from sync data
    for _, data in ipairs(self.listings) do
        local listing = setmetatable({}, getmetatable(VehicleSaleListing) and getmetatable(VehicleSaleListing) or {})

        -- Copy all fields directly (no side effects)
        for k, v in pairs(data) do
            listing[k] = v
        end

        table.insert(farm.vehicleSaleListings, listing)
    end

    -- Rebuild manager's activeListings cache from farm data
    if g_vehicleSaleManager then
        -- Clear cache entries for this farm, then re-add
        for id, listing in pairs(g_vehicleSaleManager.activeListings) do
            if listing.farmId == self.farmId then
                g_vehicleSaleManager.activeListings[id] = nil
            end
        end
        for _, listing in ipairs(farm.vehicleSaleListings) do
            if listing.id and (listing.status == "active" or listing.status == "pending" or listing.status == "declined") then
                g_vehicleSaleManager.activeListings[listing.id] = listing
            end
        end
    end

    UsedPlus.logTrace(string.format("SyncSaleListings: Applied %d listings for farm %d", #self.listings, self.farmId))
end

--============================================================================
-- SYNC SEARCHES EVENT
-- Syncs used vehicle searches + found listings to clients
--============================================================================

SyncSearchesEvent = {}
local SyncSearchesEvent_mt = Class(SyncSearchesEvent, Event)

InitEventClass(SyncSearchesEvent, "SyncSearchesEvent")

function SyncSearchesEvent.emptyNew()
    local self = Event.new(SyncSearchesEvent_mt)
    return self
end

function SyncSearchesEvent.new(farmId, searches)
    local self = SyncSearchesEvent.emptyNew()
    self.farmId = farmId
    self.searches = searches or {}
    return self
end

-- Broadcast full search sync for a farm
function SyncSearchesEvent.broadcastFullForFarm(farmId)
    if g_server == nil then return end
    local searches = {}
    if g_usedVehicleManager then
        searches = g_usedVehicleManager:getSearchesForFarm(farmId) or {}
    end
    g_server:broadcastEvent(SyncSearchesEvent.new(farmId, searches))
    UsedPlus.logTrace(string.format("SyncSearches: Broadcast FULL_SYNC for farm %d (%d searches)", farmId, #searches))
end

-- Targeted sync to a specific connection
function SyncSearchesEvent.sendToConnection(connection, farmId, searches)
    if connection == nil then return end
    connection:sendEvent(SyncSearchesEvent.new(farmId, searches))
end

function SyncSearchesEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)

    local count = #self.searches
    streamWriteInt32(streamId, count)

    for _, search in ipairs(self.searches) do
        -- Identity
        streamWriteString(streamId, search.id or "")
        streamWriteInt32(streamId, search.farmId or self.farmId)
        streamWriteString(streamId, search.storeItemIndex or "")
        streamWriteString(streamId, search.storeItemName or "")
        streamWriteFloat32(streamId, search.basePrice or 0)
        streamWriteInt32(streamId, search.searchLevel or 1)
        streamWriteInt32(streamId, search.qualityLevel or 1)
        streamWriteString(streamId, search.status or "active")
        streamWriteInt32(streamId, search.createdAt or 0)

        -- Fee structure
        streamWriteFloat32(streamId, search.retainerFee or 0)
        streamWriteFloat32(streamId, search.commissionPercent or 0)
        streamWriteFloat32(streamId, search.creditFeeModifier or 0)

        -- Monthly tracking
        streamWriteInt32(streamId, search.maxMonths or 1)
        streamWriteInt32(streamId, search.monthsElapsed or 0)
        streamWriteInt32(streamId, search.lastCheckDay or 0)
        streamWriteFloat32(streamId, search.monthlySuccessChance or 0)
        streamWriteInt32(streamId, search.maxListings or 10)
        streamWriteInt32(streamId, search.guaranteedMinimum or 0)

        -- Found listings
        local listingCount = search.foundListings and #search.foundListings or 0
        streamWriteInt32(streamId, listingCount)

        for _, listing in ipairs(search.foundListings or {}) do
            streamWriteString(streamId, listing.id or "")
            streamWriteFloat32(streamId, listing.basePrice or listing.price or 0)
            streamWriteFloat32(streamId, listing.commissionAmount or 0)
            streamWriteFloat32(streamId, listing.askingPrice or listing.price or 0)
            streamWriteFloat32(streamId, listing.damage or 0)
            streamWriteFloat32(streamId, listing.wear or 0)
            streamWriteInt32(streamId, listing.age or 0)
            streamWriteInt32(streamId, listing.operatingHours or 0)
            streamWriteInt32(streamId, listing.foundMonth or 0)
            streamWriteString(streamId, listing.qualityName or "")

            -- Negotiation data
            streamWriteString(streamId, listing.sellerPersonality or "reasonable")
            streamWriteInt32(streamId, listing.daysOnMarket or 0)
            streamWriteString(streamId, listing.whisperType or "standard")
            streamWriteBool(streamId, listing.negotiationLocked or false)
            streamWriteInt32(streamId, listing.negotiationLockExpires or 0)

            -- Inspection data
            streamWriteString(streamId, listing.inspectionState or "")
            streamWriteInt32(streamId, listing.inspectionTier or 0)

            -- UsedPlus data (reliability/DNA)
            local hasUsedPlusData = listing.usedPlusData ~= nil
            streamWriteBool(streamId, hasUsedPlusData)
            if hasUsedPlusData then
                streamWriteFloat32(streamId, listing.usedPlusData.engineReliability or 0.5)
                streamWriteFloat32(streamId, listing.usedPlusData.hydraulicReliability or 0.5)
                streamWriteFloat32(streamId, listing.usedPlusData.electricalReliability or 0.5)
                streamWriteFloat32(streamId, listing.usedPlusData.workhorseLemonScale or 0.5)
                streamWriteBool(streamId, listing.usedPlusData.wasInspected or false)
            end

            -- v2.15.0: Remaining inspection fields
            streamWriteInt32(streamId, listing.inspectionRequestedAtHour or 0)
            streamWriteInt32(streamId, listing.inspectionCompletesAtHour or 0)
            streamWriteInt32(streamId, listing.inspectionFarmId or 0)
            streamWriteFloat32(streamId, listing.inspectionCostPaid or 0)
            streamWriteBool(streamId, listing.listingOnHold or false)

            -- v2.15.0: RVB parts data (6 parts x 3 fields each)
            local hasRvbData = listing.rvbPartsData ~= nil
            streamWriteBool(streamId, hasRvbData)
            if hasRvbData then
                local rvbParts = { "ENGINE", "THERMOSTAT", "GENERATOR", "BATTERY", "SELFSTARTER", "GLOWPLUG" }
                for _, partName in ipairs(rvbParts) do
                    local part = listing.rvbPartsData[partName]
                    if part then
                        streamWriteBool(streamId, true)
                        streamWriteFloat32(streamId, part.life or 1.0)
                        streamWriteInt32(streamId, part.operatingHours or 0)
                        streamWriteInt32(streamId, part.lifetime or 1000)
                    else
                        streamWriteBool(streamId, false)
                    end
                end
            end

            -- v2.15.0: Tire conditions (4 wheel positions)
            local hasTireData = listing.tireConditions ~= nil
            streamWriteBool(streamId, hasTireData)
            if hasTireData then
                streamWriteFloat32(streamId, listing.tireConditions.FL or 1.0)
                streamWriteFloat32(streamId, listing.tireConditions.FR or 1.0)
                streamWriteFloat32(streamId, listing.tireConditions.RL or 1.0)
                streamWriteFloat32(streamId, listing.tireConditions.RR or 1.0)
            end

            -- v2.15.0: Other metadata
            streamWriteInt32(streamId, listing.qualityLevel or 0)
            streamWriteInt32(streamId, listing.expirationMonths or 0)
            streamWriteString(streamId, listing.mechanicQuote or "")
            streamWriteString(streamId, listing.fluidAssessment or "")
        end
    end
end

function SyncSearchesEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)

    local count = streamReadInt32(streamId)
    self.searches = {}

    for _ = 1, count do
        local data = {}
        data.id = streamReadString(streamId)
        data.farmId = streamReadInt32(streamId)
        data.storeItemIndex = streamReadString(streamId)
        data.storeItemName = streamReadString(streamId)
        data.basePrice = streamReadFloat32(streamId)
        data.searchLevel = streamReadInt32(streamId)
        data.qualityLevel = streamReadInt32(streamId)
        data.status = streamReadString(streamId)
        data.createdAt = streamReadInt32(streamId)

        data.retainerFee = streamReadFloat32(streamId)
        data.commissionPercent = streamReadFloat32(streamId)
        data.creditFeeModifier = streamReadFloat32(streamId)

        data.maxMonths = streamReadInt32(streamId)
        data.monthsElapsed = streamReadInt32(streamId)
        data.lastCheckDay = streamReadInt32(streamId)
        data.monthlySuccessChance = streamReadFloat32(streamId)
        data.maxListings = streamReadInt32(streamId)
        data.guaranteedMinimum = streamReadInt32(streamId)

        -- Found listings
        local listingCount = streamReadInt32(streamId)
        data.foundListings = {}

        for _ = 1, listingCount do
            local listing = {}
            listing.id = streamReadString(streamId)
            listing.basePrice = streamReadFloat32(streamId)
            listing.commissionAmount = streamReadFloat32(streamId)
            listing.askingPrice = streamReadFloat32(streamId)
            listing.damage = streamReadFloat32(streamId)
            listing.wear = streamReadFloat32(streamId)
            listing.age = streamReadInt32(streamId)
            listing.operatingHours = streamReadInt32(streamId)
            listing.foundMonth = streamReadInt32(streamId)
            listing.qualityName = streamReadString(streamId)

            -- Negotiation
            listing.sellerPersonality = streamReadString(streamId)
            listing.daysOnMarket = streamReadInt32(streamId)
            listing.whisperType = streamReadString(streamId)
            listing.negotiationLocked = streamReadBool(streamId)
            listing.negotiationLockExpires = streamReadInt32(streamId)

            -- Inspection
            listing.inspectionState = streamReadString(streamId)
            if listing.inspectionState == "" then listing.inspectionState = nil end
            listing.inspectionTier = streamReadInt32(streamId)
            if listing.inspectionTier == 0 then listing.inspectionTier = nil end

            -- UsedPlus data
            local hasUsedPlusData = streamReadBool(streamId)
            if hasUsedPlusData then
                listing.usedPlusData = {
                    engineReliability = streamReadFloat32(streamId),
                    hydraulicReliability = streamReadFloat32(streamId),
                    electricalReliability = streamReadFloat32(streamId),
                    workhorseLemonScale = streamReadFloat32(streamId),
                    wasInspected = streamReadBool(streamId)
                }
            end

            -- v2.15.0: Remaining inspection fields
            listing.inspectionRequestedAtHour = streamReadInt32(streamId)
            if listing.inspectionRequestedAtHour == 0 then listing.inspectionRequestedAtHour = nil end
            listing.inspectionCompletesAtHour = streamReadInt32(streamId)
            if listing.inspectionCompletesAtHour == 0 then listing.inspectionCompletesAtHour = nil end
            listing.inspectionFarmId = streamReadInt32(streamId)
            if listing.inspectionFarmId == 0 then listing.inspectionFarmId = nil end
            listing.inspectionCostPaid = streamReadFloat32(streamId)
            if listing.inspectionCostPaid == 0 then listing.inspectionCostPaid = nil end
            listing.listingOnHold = streamReadBool(streamId)

            -- v2.15.0: RVB parts data
            local hasRvbData = streamReadBool(streamId)
            if hasRvbData then
                listing.rvbPartsData = {}
                local rvbParts = { "ENGINE", "THERMOSTAT", "GENERATOR", "BATTERY", "SELFSTARTER", "GLOWPLUG" }
                for _, partName in ipairs(rvbParts) do
                    local hasPart = streamReadBool(streamId)
                    if hasPart then
                        listing.rvbPartsData[partName] = {
                            life = streamReadFloat32(streamId),
                            operatingHours = streamReadInt32(streamId),
                            lifetime = streamReadInt32(streamId)
                        }
                    end
                end
            end

            -- v2.15.0: Tire conditions
            local hasTireData = streamReadBool(streamId)
            if hasTireData then
                listing.tireConditions = {
                    FL = streamReadFloat32(streamId),
                    FR = streamReadFloat32(streamId),
                    RL = streamReadFloat32(streamId),
                    RR = streamReadFloat32(streamId)
                }
            end

            -- v2.15.0: Other metadata
            listing.qualityLevel = streamReadInt32(streamId)
            if listing.qualityLevel == 0 then listing.qualityLevel = nil end
            listing.expirationMonths = streamReadInt32(streamId)
            if listing.expirationMonths == 0 then listing.expirationMonths = nil end
            listing.mechanicQuote = streamReadString(streamId)
            if listing.mechanicQuote == "" then listing.mechanicQuote = nil end
            listing.fluidAssessment = streamReadString(streamId)
            if listing.fluidAssessment == "" then listing.fluidAssessment = nil end

            -- Copy parent search info for convenience
            listing.storeItemIndex = data.storeItemIndex
            listing.storeItemName = data.storeItemName
            listing.farmId = data.farmId
            listing.price = listing.askingPrice

            table.insert(data.foundListings, listing)
        end

        table.insert(self.searches, data)
    end

    self:run(connection)
end

function SyncSearchesEvent:run(connection)
    -- Sync events execute on CLIENT when received FROM SERVER
    if connection == nil or not connection:getIsServer() then
        return
    end

    if g_farmManager == nil then return end

    -- Replace all searches for this farm on the client
    local farm = g_farmManager:getFarmById(self.farmId)
    if farm == nil then return end

    -- Clear existing searches for this farm
    farm.usedVehicleSearches = {}

    -- Reconstruct searches from sync data
    for _, data in ipairs(self.searches) do
        local search = setmetatable({}, getmetatable(UsedVehicleSearch) and getmetatable(UsedVehicleSearch) or {})

        -- Copy all fields directly
        for k, v in pairs(data) do
            search[k] = v
        end

        -- Compute deprecated fields for compatibility
        search.searchCost = search.retainerFee or 0
        search.ttl = ((search.maxMonths or 1) - (search.monthsElapsed or 0)) * 24
        search.tts = search.ttl + 999

        table.insert(farm.usedVehicleSearches, search)
    end

    -- Rebuild manager's activeSearches cache from farm data
    if g_usedVehicleManager then
        -- Clear cache entries for this farm, then re-add
        for id, search in pairs(g_usedVehicleManager.activeSearches) do
            if search.farmId == self.farmId then
                g_usedVehicleManager.activeSearches[id] = nil
            end
        end
        for _, search in ipairs(farm.usedVehicleSearches) do
            if search.id and search.status == "active" then
                g_usedVehicleManager.activeSearches[search.id] = search
            end
        end
    end

    UsedPlus.logTrace(string.format("SyncSearches: Applied %d searches for farm %d", #self.searches, self.farmId))
end

--============================================================================
-- SYNC STATISTICS EVENT
-- Syncs per-farm statistics counters to clients
--============================================================================

SyncStatisticsEvent = {}
local SyncStatisticsEvent_mt = Class(SyncStatisticsEvent, Event)

InitEventClass(SyncStatisticsEvent, "SyncStatisticsEvent")

function SyncStatisticsEvent.emptyNew()
    local self = Event.new(SyncStatisticsEvent_mt)
    return self
end

function SyncStatisticsEvent.new(farmId, stats)
    local self = SyncStatisticsEvent.emptyNew()
    self.farmId = farmId
    self.stats = stats or {}
    return self
end

-- Broadcast statistics for a farm
function SyncStatisticsEvent.broadcastForFarm(farmId)
    if g_server == nil then return end
    local stats = g_financeManager and g_financeManager:getStatistics(farmId) or {}
    g_server:broadcastEvent(SyncStatisticsEvent.new(farmId, stats))
    UsedPlus.logTrace(string.format("SyncStatistics: Broadcast for farm %d", farmId))
end

-- Targeted sync to a specific connection
function SyncStatisticsEvent.sendToConnection(connection, farmId, stats)
    if connection == nil then return end
    connection:sendEvent(SyncStatisticsEvent.new(farmId, stats))
end

function SyncStatisticsEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)

    -- Used Vehicle Search statistics
    streamWriteInt32(streamId, self.stats.searchesStarted or 0)
    streamWriteInt32(streamId, self.stats.searchesSucceeded or 0)
    streamWriteInt32(streamId, self.stats.searchesFailed or 0)
    streamWriteInt32(streamId, self.stats.searchesCancelled or 0)
    streamWriteFloat32(streamId, self.stats.totalSearchFees or 0)
    streamWriteFloat32(streamId, self.stats.totalSavingsFromUsed or 0)
    streamWriteInt32(streamId, self.stats.usedPurchases or 0)

    -- Inspection statistics
    streamWriteInt32(streamId, self.stats.inspectionsPurchased or 0)
    streamWriteFloat32(streamId, self.stats.totalInspectionFees or 0)

    -- Vehicle Sale statistics
    streamWriteInt32(streamId, self.stats.salesListed or 0)
    streamWriteInt32(streamId, self.stats.salesCompleted or 0)
    streamWriteInt32(streamId, self.stats.salesCancelled or 0)
    streamWriteFloat32(streamId, self.stats.totalSaleProceeds or 0)
    streamWriteFloat32(streamId, self.stats.totalAgentCommissions or 0)

    -- Land purchase statistics
    streamWriteFloat32(streamId, self.stats.totalSavingsFromLand or 0)
    streamWriteInt32(streamId, self.stats.landPurchases or 0)

    -- Finance deal statistics
    streamWriteInt32(streamId, self.stats.dealsCreated or 0)
    streamWriteInt32(streamId, self.stats.dealsCompleted or 0)
    streamWriteFloat32(streamId, self.stats.totalAmountFinanced or 0)
    streamWriteFloat32(streamId, self.stats.totalInterestPaid or 0)

    -- Negotiation statistics
    streamWriteInt32(streamId, self.stats.negotiationsAttempted or 0)
    streamWriteInt32(streamId, self.stats.negotiationsWon or 0)
    streamWriteInt32(streamId, self.stats.negotiationsCountered or 0)
    streamWriteInt32(streamId, self.stats.negotiationsRejected or 0)
    streamWriteFloat32(streamId, self.stats.totalNegotiationSavings or 0)
end

function SyncStatisticsEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)

    self.stats = {}
    self.stats.searchesStarted = streamReadInt32(streamId)
    self.stats.searchesSucceeded = streamReadInt32(streamId)
    self.stats.searchesFailed = streamReadInt32(streamId)
    self.stats.searchesCancelled = streamReadInt32(streamId)
    self.stats.totalSearchFees = streamReadFloat32(streamId)
    self.stats.totalSavingsFromUsed = streamReadFloat32(streamId)
    self.stats.usedPurchases = streamReadInt32(streamId)

    self.stats.inspectionsPurchased = streamReadInt32(streamId)
    self.stats.totalInspectionFees = streamReadFloat32(streamId)

    self.stats.salesListed = streamReadInt32(streamId)
    self.stats.salesCompleted = streamReadInt32(streamId)
    self.stats.salesCancelled = streamReadInt32(streamId)
    self.stats.totalSaleProceeds = streamReadFloat32(streamId)
    self.stats.totalAgentCommissions = streamReadFloat32(streamId)

    self.stats.totalSavingsFromLand = streamReadFloat32(streamId)
    self.stats.landPurchases = streamReadInt32(streamId)

    self.stats.dealsCreated = streamReadInt32(streamId)
    self.stats.dealsCompleted = streamReadInt32(streamId)
    self.stats.totalAmountFinanced = streamReadFloat32(streamId)
    self.stats.totalInterestPaid = streamReadFloat32(streamId)

    self.stats.negotiationsAttempted = streamReadInt32(streamId)
    self.stats.negotiationsWon = streamReadInt32(streamId)
    self.stats.negotiationsCountered = streamReadInt32(streamId)
    self.stats.negotiationsRejected = streamReadInt32(streamId)
    self.stats.totalNegotiationSavings = streamReadFloat32(streamId)

    self:run(connection)
end

function SyncStatisticsEvent:run(connection)
    -- Sync events execute on CLIENT when received FROM SERVER
    if connection == nil or not connection:getIsServer() then
        return
    end

    if g_financeManager == nil then return end

    -- Replace statistics for this farm
    g_financeManager.statisticsByFarm[self.farmId] = self.stats

    UsedPlus.logTrace(string.format("SyncStatistics: Applied stats for farm %d", self.farmId))
end

--============================================================================
-- SYNC PAYMENT TRACKER EVENT
-- Syncs credit/payment history to clients
--============================================================================

SyncPaymentTrackerEvent = {}
local SyncPaymentTrackerEvent_mt = Class(SyncPaymentTrackerEvent, Event)

InitEventClass(SyncPaymentTrackerEvent, "SyncPaymentTrackerEvent")

function SyncPaymentTrackerEvent.emptyNew()
    local self = Event.new(SyncPaymentTrackerEvent_mt)
    return self
end

function SyncPaymentTrackerEvent.new(farmId, trackerStats, payments)
    local self = SyncPaymentTrackerEvent.emptyNew()
    self.farmId = farmId
    self.trackerStats = trackerStats or {}
    self.payments = payments or {}
    return self
end

-- Broadcast payment tracker for a farm
function SyncPaymentTrackerEvent.broadcastForFarm(farmId)
    if g_server == nil then return end
    if PaymentTracker == nil then return end

    local data = PaymentTracker.getFarmData(farmId)
    local stats = data.stats
    -- Send last 24 payments for credit scoring
    local payments = data.payments or {}
    local startIdx = math.max(1, #payments - 23)
    local recentPayments = {}
    for i = startIdx, #payments do
        table.insert(recentPayments, payments[i])
    end

    g_server:broadcastEvent(SyncPaymentTrackerEvent.new(farmId, stats, recentPayments))
    UsedPlus.logTrace(string.format("SyncPaymentTracker: Broadcast for farm %d (%d payments)", farmId, #recentPayments))
end

-- Targeted sync to a specific connection
function SyncPaymentTrackerEvent.sendToConnection(connection, farmId, trackerStats, payments)
    if connection == nil then return end
    connection:sendEvent(SyncPaymentTrackerEvent.new(farmId, trackerStats, payments))
end

function SyncPaymentTrackerEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)

    -- Stats
    streamWriteInt32(streamId, self.trackerStats.totalPayments or 0)
    streamWriteInt32(streamId, self.trackerStats.onTimePayments or 0)
    streamWriteInt32(streamId, self.trackerStats.latePayments or 0)
    streamWriteInt32(streamId, self.trackerStats.missedPayments or 0)
    streamWriteInt32(streamId, self.trackerStats.currentStreak or 0)
    streamWriteInt32(streamId, self.trackerStats.longestStreak or 0)
    streamWriteInt32(streamId, self.trackerStats.lastMissedIndex or 0)

    -- Payments
    local count = #self.payments
    streamWriteInt32(streamId, count)
    for _, p in ipairs(self.payments) do
        streamWriteString(streamId, p.dealId or "")
        streamWriteString(streamId, p.dealType or "")
        streamWriteString(streamId, p.status or "on_time")
        streamWriteInt32(streamId, p.amount or 0)
        streamWriteInt32(streamId, p.period or 1)
        streamWriteInt32(streamId, p.year or 1)
    end
end

function SyncPaymentTrackerEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)

    self.trackerStats = {}
    self.trackerStats.totalPayments = streamReadInt32(streamId)
    self.trackerStats.onTimePayments = streamReadInt32(streamId)
    self.trackerStats.latePayments = streamReadInt32(streamId)
    self.trackerStats.missedPayments = streamReadInt32(streamId)
    self.trackerStats.currentStreak = streamReadInt32(streamId)
    self.trackerStats.longestStreak = streamReadInt32(streamId)
    self.trackerStats.lastMissedIndex = streamReadInt32(streamId)

    local count = streamReadInt32(streamId)
    self.payments = {}
    for _ = 1, count do
        local p = {}
        p.dealId = streamReadString(streamId)
        p.dealType = streamReadString(streamId)
        p.status = streamReadString(streamId)
        p.amount = streamReadInt32(streamId)
        p.period = streamReadInt32(streamId)
        p.year = streamReadInt32(streamId)
        table.insert(self.payments, p)
    end

    self:run(connection)
end

function SyncPaymentTrackerEvent:run(connection)
    -- Sync events execute on CLIENT when received FROM SERVER
    if connection == nil or not connection:getIsServer() then
        return
    end

    if PaymentTracker == nil then return end

    -- Replace payment data for this farm
    local data = PaymentTracker.getFarmData(self.farmId)
    data.stats = self.trackerStats
    data.payments = self.payments

    UsedPlus.logTrace(string.format("SyncPaymentTracker: Applied %d payments for farm %d", #self.payments, self.farmId))
end

UsedPlus.logInfo("SyncEvents loaded - 5 sync event classes ready for multiplayer state propagation")
