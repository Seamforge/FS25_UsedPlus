--[[
    FS25_UsedPlus - Land Events (Consolidated)

    Network events for land operations:
    - PurchaseLandCashEvent: Cash purchase of farmland
    - LandLeaseEvent: Create a land lease
    - LandLeaseBuyoutEvent: Buy out a land lease

    Pattern from: FinanceVehicleEvent, LeaseVehicleEvent
]]

--============================================================================
-- PURCHASE LAND CASH EVENT
-- Network event for cash purchase of farmland (no financing)
--============================================================================

PurchaseLandCashEvent = {}
local PurchaseLandCashEvent_mt = Class(PurchaseLandCashEvent, Event)

InitEventClass(PurchaseLandCashEvent, "PurchaseLandCashEvent")

function PurchaseLandCashEvent.emptyNew()
    local self = Event.new(PurchaseLandCashEvent_mt)
    return self
end

function PurchaseLandCashEvent.new(farmId, farmlandId, landPrice, landName, baseLandPrice)
    local self = PurchaseLandCashEvent.emptyNew()
    self.farmId = farmId
    self.farmlandId = farmlandId
    self.landPrice = landPrice
    self.landName = landName or ""
    self.baseLandPrice = baseLandPrice or landPrice  -- Base price before credit adjustment
    return self
end

function PurchaseLandCashEvent.sendToServer(farmId, farmlandId, landPrice, landName, baseLandPrice)
    local event = PurchaseLandCashEvent.new(farmId, farmlandId, landPrice, landName, baseLandPrice)
    if g_server ~= nil then
        -- Single player / host - execute directly
        event:run(nil)  -- v2.9.1: Server doesn't need connection
    else
        -- Multiplayer client - send to server
        g_client:getServerConnection():sendEvent(event)
    end
end

function PurchaseLandCashEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteInt32(streamId, self.farmlandId)
    streamWriteFloat32(streamId, self.landPrice)
    streamWriteString(streamId, self.landName or "")
    streamWriteFloat32(streamId, self.baseLandPrice or self.landPrice)
end

function PurchaseLandCashEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.farmlandId = streamReadInt32(streamId)
    self.landPrice = streamReadFloat32(streamId)
    self.landName = streamReadString(streamId)
    self.baseLandPrice = streamReadFloat32(streamId)
    self:run(connection)
end

function PurchaseLandCashEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- v2.7.2: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, self.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("LAND_CASH_PURCHASE_REJECTED",
            string.format("Unauthorized land cash purchase attempt for farmId %d, farmland %d: %s",
                self.farmId, self.farmlandId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    -- Validate price is reasonable
    if self.landPrice <= 0 or self.landPrice > 100000000 then
        UsedPlus.logError(string.format("[SECURITY] Invalid land price: $%.0f", self.landPrice))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_invalid_params")
        return
    end

    -- Validate farmland exists
    local farmland = g_farmlandManager:getFarmlandById(self.farmlandId)
    if farmland == nil then
        UsedPlus.logError(string.format("Farmland %d not found", self.farmlandId))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_land_not_found")
        return
    end

    -- Validate land is not already owned
    local currentOwner = g_farmlandManager:getFarmlandOwner(self.farmlandId)
    if currentOwner ~= 0 and currentOwner ~= FarmlandManager.NO_OWNER_FARM_ID then
        UsedPlus.logError(string.format("Farmland %d is already owned by farm %d", self.farmlandId, currentOwner))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_land_owned")
        return
    end

    -- Validate farm exists and has sufficient funds
    local farm = g_farmManager:getFarmById(self.farmId)
    if farm == nil then
        UsedPlus.logError(string.format("Farm %d not found", self.farmId))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_farm_not_found")
        return
    end

    if farm.money < self.landPrice then
        UsedPlus.logError(string.format("Insufficient funds: have $%.0f, need $%.0f", farm.money, self.landPrice))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_insufficient_funds")
        return
    end

    -- Execute the purchase on server
    UsedPlus.logDebug(string.format("Processing cash land purchase: %s (ID %d) for $%.0f by farm %d",
        self.landName, self.farmlandId, self.landPrice, self.farmId))

    -- Transfer land ownership
    g_farmlandManager:setLandOwnership(self.farmlandId, self.farmId)

    -- Deduct payment
    g_currentMission:addMoney(-self.landPrice, self.farmId, MoneyType.PURCHASE_LAND, true, true)

    -- Notify about property change
    g_messageCenter:publish(MessageType.FARM_PROPERTY_CHANGED, self.farmId)

    -- Record credit history if available
    if CreditHistory then
        CreditHistory.recordEvent(self.farmId, "LAND_CASH_PURCHASE", self.landName)
    end

    -- Track land purchase statistics
    if g_financeManager then
        g_financeManager:incrementStatistic(self.farmId, "landPurchases", 1)
        -- Calculate and track credit discount savings
        local savings = (self.baseLandPrice or self.landPrice) - self.landPrice
        if savings > 0 then
            g_financeManager:incrementStatistic(self.farmId, "totalSavingsFromLand", savings)
            UsedPlus.logDebug(string.format("Tracked land credit savings: $%.0f (base $%.0f - paid $%.0f)",
                savings, self.baseLandPrice or 0, self.landPrice))
        end
    end

    -- Send success response
    TransactionResponseEvent.sendToClient(connection, self.farmId, true, "usedplus_mp_success_land_purchased")

    -- v2.15.0: Broadcast statistics sync to all clients
    SyncStatisticsEvent.broadcastForFarm(self.farmId)

    -- Notification
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format("Purchased %s for %s",
            self.landName,
            g_i18n:formatMoney(self.landPrice, 0, true, true))
    )

    UsedPlus.logDebug(string.format("Land cash purchase complete: %s", self.landName))
end

--============================================================================
-- LAND LEASE EVENT
-- Network event for creating land leases
-- v2.8.0: Updated to use termMonths and include security deposit/monthly payment
--============================================================================

LandLeaseEvent = {}
local LandLeaseEvent_mt = Class(LandLeaseEvent, Event)

InitEventClass(LandLeaseEvent, "LandLeaseEvent")

function LandLeaseEvent.emptyNew()
    local self = Event.new(LandLeaseEvent_mt)
    return self
end

--[[
    v2.8.0: Updated parameters
    @param farmId - Farm ID
    @param farmlandId - Farmland ID
    @param fieldName - Display name of the land
    @param landPrice - Value of the land (for buyout)
    @param termMonths - Lease term in MONTHS (not years)
    @param securityDeposit - Security deposit amount (credit-based)
    @param monthlyPayment - Monthly lease payment (acreage-based)
]]
function LandLeaseEvent.new(farmId, farmlandId, fieldName, landPrice, termMonths, securityDeposit, monthlyPayment)
    local self = LandLeaseEvent.emptyNew()
    self.farmId = farmId
    self.farmlandId = farmlandId
    self.fieldName = fieldName
    self.landPrice = landPrice
    self.termMonths = termMonths
    self.securityDeposit = securityDeposit or 0
    self.monthlyPayment = monthlyPayment or 0
    return self
end

function LandLeaseEvent.sendToServer(farmId, farmlandId, fieldName, landPrice, termMonths, securityDeposit, monthlyPayment)
    local event = LandLeaseEvent.new(farmId, farmlandId, fieldName, landPrice, termMonths, securityDeposit, monthlyPayment)
    if g_server ~= nil then
        event:run(nil)  -- v2.9.1: Server doesn't need connection
    else
        g_client:getServerConnection():sendEvent(event)
    end
end

function LandLeaseEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteInt32(streamId, self.farmlandId)
    streamWriteString(streamId, self.fieldName or "")
    streamWriteFloat32(streamId, self.landPrice)
    streamWriteInt32(streamId, self.termMonths)
    streamWriteFloat32(streamId, self.securityDeposit)
    streamWriteFloat32(streamId, self.monthlyPayment)
end

function LandLeaseEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.farmlandId = streamReadInt32(streamId)
    self.fieldName = streamReadString(streamId)
    self.landPrice = streamReadFloat32(streamId)
    self.termMonths = streamReadInt32(streamId)
    self.securityDeposit = streamReadFloat32(streamId)
    self.monthlyPayment = streamReadFloat32(streamId)
    self:run(connection)
end

function LandLeaseEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- v2.7.2: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, self.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("LAND_LEASE_REJECTED",
            string.format("Unauthorized land lease attempt for farmId %d, farmland %d: %s",
                self.farmId, self.farmlandId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    if g_financeManager == nil then
        UsedPlus.logError("FinanceManager not initialized")
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_manager")
        return
    end

    local farm = g_farmManager:getFarmById(self.farmId)
    if farm == nil then
        UsedPlus.logError(string.format("Farm %d not found", self.farmId))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_farm_not_found")
        return
    end

    -- v2.8.0: Validate term is reasonable (1-60 months)
    if self.termMonths < 1 or self.termMonths > 60 then
        UsedPlus.logError(string.format("Invalid lease term: %d months (must be 1-60)", self.termMonths))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_invalid_params")
        return
    end

    -- v2.8.0: Validate payment values
    if self.securityDeposit < 0 or self.securityDeposit > 10000000 then
        UsedPlus.logError(string.format("[SECURITY] Invalid security deposit: $%.0f", self.securityDeposit))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_invalid_params")
        return
    end
    if self.monthlyPayment < 0 or self.monthlyPayment > 1000000 then
        UsedPlus.logError(string.format("[SECURITY] Invalid monthly payment: $%.0f", self.monthlyPayment))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_invalid_params")
        return
    end

    local farmland = g_farmlandManager:getFarmlandById(self.farmlandId)
    if farmland == nil then
        UsedPlus.logError(string.format("Farmland %d not found", self.farmlandId))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_land_not_found")
        return
    end

    local currentOwner = g_farmlandManager:getFarmlandOwner(self.farmlandId)
    if currentOwner ~= 0 and currentOwner ~= FarmlandManager.NO_OWNER_FARM_ID then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            "This land is already owned and cannot be leased."
        )
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_land_owned")
        return
    end

    -- v2.8.0: Check if farm has sufficient funds for security deposit
    if self.securityDeposit > 0 and farm.money < self.securityDeposit then
        UsedPlus.logError(string.format("Insufficient funds for security deposit: have $%.0f, need $%.0f",
            farm.money, self.securityDeposit))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_insufficient_funds")
        return
    end

    local existingDeals = g_financeManager:getDealsForFarm(self.farmId)
    for _, deal in ipairs(existingDeals) do
        if deal.dealType == 3 and deal.farmlandId == self.farmlandId then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_INFO,
                "You already have a lease on this land."
            )
            TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_already_leased")
            return
        end
    end

    -- v2.8.0: Convert termMonths to years for LandLeaseDeal (it expects years)
    local termYears = math.max(1, math.ceil(self.termMonths / 12))

    UsedPlus.logDebug(string.format("Creating land lease: %s ($%.2f, %d months / %d years)",
        self.fieldName, self.landPrice, self.termMonths, termYears))

    -- v2.8.0: Deduct security deposit on server
    if self.securityDeposit > 0 then
        g_currentMission:addMoney(-self.securityDeposit, self.farmId, MoneyType.LEASING_COSTS, true, true)
        UsedPlus.logDebug(string.format("Security deposit deducted: $%.0f", self.securityDeposit))
    end

    -- Create lease deal
    local deal = LandLeaseDeal.new(
        self.farmId, self.farmlandId, self.fieldName, self.landPrice, termYears
    )

    -- v2.8.0: Override calculated monthly payment with client-provided value
    -- (Client calculates based on acreage, soil quality, and credit score)
    if self.monthlyPayment > 0 then
        deal.monthlyPayment = self.monthlyPayment
    end

    -- v2.8.0: Store security deposit in deal for potential refund on termination
    deal.securityDeposit = self.securityDeposit
    deal.termMonths = self.termMonths  -- Store actual term in months

    g_financeManager:registerDeal(deal)
    g_farmlandManager:setLandOwnership(self.farmlandId, self.farmId)

    -- Notify about property change
    g_messageCenter:publish(MessageType.FARM_PROPERTY_CHANGED, self.farmId)

    if CreditHistory then
        CreditHistory.recordEvent(self.farmId, "LAND_LEASE_STARTED", self.fieldName)
    end

    TransactionResponseEvent.sendToClient(connection, self.farmId, true, "usedplus_mp_success_land_leased")

    -- v2.15.0: Broadcast deal sync to all clients
    SyncFinanceDealsEvent.broadcastAddForFarm(self.farmId)

    -- Format term display for notification
    local termDisplay
    if self.termMonths < 12 then
        termDisplay = string.format("%d months", self.termMonths)
    elseif self.termMonths == 12 then
        termDisplay = "1 year"
    else
        termDisplay = string.format("%d years", termYears)
    end

    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format("Land lease started! %s for %s at %s/month",
            self.fieldName, termDisplay,
            g_i18n:formatMoney(deal.monthlyPayment, 0, true, true))
    )

    UsedPlus.logDebug(string.format("Land lease created: id=%s, monthly=%s, deposit=%s",
        deal.id,
        g_i18n:formatMoney(deal.monthlyPayment, 0, true, true),
        g_i18n:formatMoney(self.securityDeposit, 0, true, true)))
end

--============================================================================
-- LAND LEASE BUYOUT EVENT
-- Network event for buying out a land lease
--============================================================================

LandLeaseBuyoutEvent = {}
local LandLeaseBuyoutEvent_mt = Class(LandLeaseBuyoutEvent, Event)

InitEventClass(LandLeaseBuyoutEvent, "LandLeaseBuyoutEvent")

function LandLeaseBuyoutEvent.emptyNew()
    local self = Event.new(LandLeaseBuyoutEvent_mt)
    return self
end

function LandLeaseBuyoutEvent.new(dealId)
    local self = LandLeaseBuyoutEvent.emptyNew()
    self.dealId = dealId
    return self
end

function LandLeaseBuyoutEvent.sendToServer(dealId)
    local event = LandLeaseBuyoutEvent.new(dealId)
    if g_server ~= nil then
        event:run(nil)  -- v2.9.1: Server doesn't need connection
    else
        g_client:getServerConnection():sendEvent(event)
    end
end

function LandLeaseBuyoutEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.dealId)
end

function LandLeaseBuyoutEvent:readStream(streamId, connection)
    self.dealId = streamReadString(streamId)
    self:run(connection)
end

function LandLeaseBuyoutEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    if g_financeManager == nil then
        UsedPlus.logError("FinanceManager not initialized")
        -- Note: No farmId available yet for response
        return
    end

    local deal = g_financeManager:getDealById(self.dealId)
    if deal == nil then
        UsedPlus.logError(string.format("Land lease deal %s not found", self.dealId))
        -- Note: No farmId available - deal not found
        return
    end

    -- v2.7.2: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, deal.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("LAND_BUYOUT_REJECTED",
            string.format("Unauthorized land buyout attempt for deal %s (farmId %d): %s",
                self.dealId, deal.farmId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, deal.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    if deal.dealType ~= 3 then
        UsedPlus.logError(string.format("Deal %s is not a land lease (type: %d)", self.dealId, deal.dealType))
        TransactionResponseEvent.sendToClient(connection, deal.farmId, false, "usedplus_mp_error_invalid_deal_type")
        return
    end

    if deal.status ~= "active" then
        UsedPlus.logError(string.format("Deal %s is not active (status: %s)", self.dealId, deal.status))
        TransactionResponseEvent.sendToClient(connection, deal.farmId, false, "usedplus_mp_error_deal_not_active")
        return
    end

    local farm = g_farmManager:getFarmById(deal.farmId)
    if farm == nil then
        UsedPlus.logError(string.format("Farm %d not found", deal.farmId))
        TransactionResponseEvent.sendToClient(connection, deal.farmId, false, "usedplus_mp_error_farm_not_found")
        return
    end

    local buyoutPrice = deal:calculateBuyoutPrice()

    if farm.money < buyoutPrice then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_ERROR,
            string.format("Insufficient funds for buyout. Need %s",
                g_i18n:formatMoney(buyoutPrice, 0, true, true))
        )
        TransactionResponseEvent.sendToClient(connection, deal.farmId, false, "usedplus_mp_error_insufficient_funds")
        return
    end

    g_currentMission:addMoney(-buyoutPrice, deal.farmId, MoneyType.PURCHASE_LAND, true, true)

    deal.status = "completed"
    g_financeManager:removeDeal(deal.id)

    if CreditHistory then
        CreditHistory.recordEvent(deal.farmId, "LAND_LEASE_BUYOUT", deal.landName)
    end

    TransactionResponseEvent.sendToClient(connection, deal.farmId, true, "usedplus_mp_success_land_buyout")

    -- v2.15.0: Broadcast deal removal to all clients
    SyncFinanceDealsEvent.broadcastAddForFarm(deal.farmId)

    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format("Congratulations! %s is now fully yours for %s",
            deal.landName, g_i18n:formatMoney(buyoutPrice, 0, true, true))
    )

    UsedPlus.logDebug(string.format("Land lease bought out: %s for $%.2f", deal.landName, buyoutPrice))
end

--============================================================================

UsedPlus.logInfo("LandEvents loaded (PurchaseLandCashEvent, LandLeaseEvent, LandLeaseBuyoutEvent)")
