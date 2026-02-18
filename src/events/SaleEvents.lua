--[[
    FS25_UsedPlus - Sale Events (Consolidated)

    Network events for vehicle sale operations:
    - CreateSaleListingEvent: Create an agent-based sale listing
    - SaleListingActionEvent: Accept/Decline/Cancel sale offers

    Pattern from: TakeLoanEvent, FS25_ADVANCED_PATTERNS.md
]]

--============================================================================
-- CREATE SALE LISTING EVENT
-- Network event for creating an agent-based sale listing
--============================================================================

CreateSaleListingEvent = {}
local CreateSaleListingEvent_mt = Class(CreateSaleListingEvent, Event)

InitEventClass(CreateSaleListingEvent, "CreateSaleListingEvent")

function CreateSaleListingEvent.emptyNew()
    local self = Event.new(CreateSaleListingEvent_mt)
    return self
end

-- v2.8.0: Updated to support separate agentTier and priceTier parameters
function CreateSaleListingEvent.new(farmId, vehicleId, agentTier, priceTier)
    local self = CreateSaleListingEvent.emptyNew()
    self.farmId = farmId
    self.vehicleId = vehicleId
    self.agentTier = agentTier
    self.priceTier = priceTier or 2  -- Default to Market price tier
    return self
end

function CreateSaleListingEvent.sendToServer(farmId, vehicleId, agentTier, priceTier)
    if g_server ~= nil then
        CreateSaleListingEvent.execute(farmId, vehicleId, agentTier, priceTier)
    else
        g_client:getServerConnection():sendEvent(
            CreateSaleListingEvent.new(farmId, vehicleId, agentTier, priceTier)
        )
    end
end

function CreateSaleListingEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteInt32(streamId, self.vehicleId)
    streamWriteInt8(streamId, self.agentTier)
    streamWriteInt8(streamId, self.priceTier)
end

function CreateSaleListingEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.vehicleId = streamReadInt32(streamId)
    self.agentTier = streamReadInt8(streamId)
    self.priceTier = streamReadInt8(streamId)
    self:run(connection)
end

function CreateSaleListingEvent.execute(farmId, vehicleId, agentTier, priceTier)
    local vehicle = nil
    if g_currentMission and g_currentMission.vehicleSystem then
        for _, v in pairs(g_currentMission.vehicleSystem.vehicles) do
            if v.id == vehicleId then
                vehicle = v
                break
            end
        end
    end

    if vehicle == nil then
        UsedPlus.logError(string.format("CreateSaleListingEvent - Vehicle %d not found", vehicleId))
        return false
    end

    if vehicle.ownerFarmId ~= farmId then
        UsedPlus.logError(string.format("CreateSaleListingEvent - Vehicle not owned by farm %d", farmId))
        return false
    end

    -- Validate agentTier (0=Private, 1=Local, 2=Regional, 3=National)
    if agentTier < 0 or agentTier > 3 then
        UsedPlus.logError(string.format("CreateSaleListingEvent - Invalid agent tier: %d", agentTier))
        return false
    end

    -- Validate priceTier (1=Quick, 2=Market, 3=Premium)
    priceTier = priceTier or 2
    if priceTier < 1 or priceTier > 3 then
        UsedPlus.logError(string.format("CreateSaleListingEvent - Invalid price tier: %d", priceTier))
        return false
    end

    if g_vehicleSaleManager then
        local listing = g_vehicleSaleManager:createSaleListing(farmId, vehicle, agentTier, priceTier)
        if listing then
            UsedPlus.logDebug(string.format("CreateSaleListingEvent: Created listing %s (agent=%d, price=%d)", listing.id, agentTier, priceTier))
            return true
        end
    end

    UsedPlus.logError("CreateSaleListingEvent - Failed to create listing")
    return false
end

function CreateSaleListingEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- v2.7.2: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, self.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("CREATE_SALE_LISTING_REJECTED",
            string.format("Unauthorized create sale listing attempt for farmId %d, vehicle %d: %s",
                self.farmId, self.vehicleId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    local success = CreateSaleListingEvent.execute(self.farmId, self.vehicleId, self.agentTier, self.priceTier)
    if success then
        TransactionResponseEvent.sendToClient(connection, self.farmId, true, "usedplus_mp_success_listed")
    else
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_failed")
    end
end

--============================================================================
-- SALE LISTING ACTION EVENT
-- Consolidated event for Accept/Decline/Cancel actions
--============================================================================

SaleListingActionEvent = {}
local SaleListingActionEvent_mt = Class(SaleListingActionEvent, Event)

InitEventClass(SaleListingActionEvent, "SaleListingActionEvent")

SaleListingActionEvent.ACTION_ACCEPT = 1
SaleListingActionEvent.ACTION_DECLINE = 2
SaleListingActionEvent.ACTION_CANCEL = 3

SaleListingActionEvent.ACTION_NAMES = {
    [1] = "Accept",
    [2] = "Decline",
    [3] = "Cancel"
}

function SaleListingActionEvent.emptyNew()
    local self = Event.new(SaleListingActionEvent_mt)
    return self
end

function SaleListingActionEvent.new(listingId, actionType)
    local self = SaleListingActionEvent.emptyNew()
    self.listingId = listingId
    self.actionType = actionType
    return self
end

function SaleListingActionEvent.sendToServer(listingId, actionType)
    if g_server ~= nil then
        SaleListingActionEvent.execute(listingId, actionType)
    else
        g_client:getServerConnection():sendEvent(
            SaleListingActionEvent.new(listingId, actionType)
        )
    end
end

-- Convenience methods
function SaleListingActionEvent.acceptOffer(listingId)
    SaleListingActionEvent.sendToServer(listingId, SaleListingActionEvent.ACTION_ACCEPT)
end

function SaleListingActionEvent.declineOffer(listingId)
    SaleListingActionEvent.sendToServer(listingId, SaleListingActionEvent.ACTION_DECLINE)
end

function SaleListingActionEvent.cancelListing(listingId)
    SaleListingActionEvent.sendToServer(listingId, SaleListingActionEvent.ACTION_CANCEL)
end

function SaleListingActionEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.listingId)
    streamWriteUInt8(streamId, self.actionType)
end

function SaleListingActionEvent:readStream(streamId, connection)
    self.listingId = streamReadString(streamId)
    self.actionType = streamReadUInt8(streamId)
    self:run(connection)
end

function SaleListingActionEvent.execute(listingId, actionType)
    if g_vehicleSaleManager == nil then
        UsedPlus.logError("SaleListingActionEvent - VehicleSaleManager not available")
        return false
    end

    local success = false
    local actionName = SaleListingActionEvent.ACTION_NAMES[actionType] or "Unknown"

    if actionType == SaleListingActionEvent.ACTION_ACCEPT then
        success = g_vehicleSaleManager:acceptOffer(listingId)
    elseif actionType == SaleListingActionEvent.ACTION_DECLINE then
        success = g_vehicleSaleManager:declineOffer(listingId)
    elseif actionType == SaleListingActionEvent.ACTION_CANCEL then
        success = g_vehicleSaleManager:cancelListing(listingId)
    else
        UsedPlus.logError(string.format("SaleListingActionEvent - Unknown action type: %d", actionType))
        return false
    end

    if success then
        UsedPlus.logDebug(string.format("SaleListingActionEvent: %s on listing %s", actionName, listingId))
    else
        UsedPlus.logError(string.format("SaleListingActionEvent - Failed to %s listing %s", actionName:lower(), listingId))
    end

    return success
end

function SaleListingActionEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- v2.7.2 SECURITY: Validate action type is one of the known values
    local validActions = {
        [SaleListingActionEvent.ACTION_ACCEPT] = true,
        [SaleListingActionEvent.ACTION_DECLINE] = true,
        [SaleListingActionEvent.ACTION_CANCEL] = true
    }
    if not validActions[self.actionType] then
        UsedPlus.logError(string.format("[SECURITY] Invalid action type: %s", tostring(self.actionType)))
        return
    end

    -- v2.7.2 SECURITY: Require VehicleSaleManager and listing to exist
    if g_vehicleSaleManager == nil then
        UsedPlus.logError("[SECURITY] VehicleSaleManager not available")
        return
    end

    local listing = g_vehicleSaleManager:getListingById(self.listingId)
    if listing == nil then
        -- Listing not found - could be already processed or invalid ID
        UsedPlus.logWarn(string.format("[SECURITY] Listing %s not found", self.listingId))
        return
    end

    -- v2.7.2: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, listing.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("SALE_ACTION_REJECTED",
            string.format("Unauthorized sale action %d for listing %s (farmId %d): %s",
                self.actionType, self.listingId, listing.farmId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, listing.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    local success = SaleListingActionEvent.execute(self.listingId, self.actionType)
    local actionName = SaleListingActionEvent.ACTION_NAMES[self.actionType] or "Action"
    if success then
        TransactionResponseEvent.sendToClient(connection, listing.farmId, true, "usedplus_mp_success_sale_action")
    end
    -- Note: execute() handles errors internally with logging
end

-- Legacy compatibility aliases
AcceptSaleOfferEvent = {
    sendToServer = function(listingId) SaleListingActionEvent.acceptOffer(listingId) end
}
DeclineSaleOfferEvent = {
    sendToServer = function(listingId) SaleListingActionEvent.declineOffer(listingId) end
}
CancelSaleListingEvent = {
    sendToServer = function(listingId) SaleListingActionEvent.cancelListing(listingId) end
}

--============================================================================
-- MODIFY LISTING PRICE EVENT
-- Network event for changing the asking price of an active listing
--============================================================================

ModifyListingPriceEvent = {}
local ModifyListingPriceEvent_mt = Class(ModifyListingPriceEvent, Event)

InitEventClass(ModifyListingPriceEvent, "ModifyListingPriceEvent")

function ModifyListingPriceEvent.emptyNew()
    local self = Event.new(ModifyListingPriceEvent_mt)
    return self
end

function ModifyListingPriceEvent.new(listingId, newPrice)
    local self = ModifyListingPriceEvent.emptyNew()
    self.listingId = listingId
    self.newPrice = newPrice
    return self
end

function ModifyListingPriceEvent.sendToServer(listingId, newPrice)
    if g_server ~= nil then
        ModifyListingPriceEvent.execute(listingId, newPrice)
    else
        g_client:getServerConnection():sendEvent(
            ModifyListingPriceEvent.new(listingId, newPrice)
        )
    end
end

function ModifyListingPriceEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.listingId)
    streamWriteFloat32(streamId, self.newPrice)
end

function ModifyListingPriceEvent:readStream(streamId, connection)
    self.listingId = streamReadString(streamId)
    self.newPrice = streamReadFloat32(streamId)
    self:run(connection)
end

function ModifyListingPriceEvent.execute(listingId, newPrice)
    if g_vehicleSaleManager == nil then
        UsedPlus.logError("ModifyListingPriceEvent - VehicleSaleManager not available")
        return false
    end

    return g_vehicleSaleManager:modifyAskingPrice(listingId, newPrice)
end

function ModifyListingPriceEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- v2.7.2 SECURITY: Helper to check for NaN and Infinity values
    local function isInvalidNumber(v)
        return v == nil or v ~= v or v == math.huge or v == -math.huge
    end

    -- v2.7.2 SECURITY: Validate price is positive and reasonable (including infinity check)
    if isInvalidNumber(self.newPrice) or self.newPrice <= 0 or self.newPrice > 100000000 then
        UsedPlus.logError(string.format("[SECURITY] Invalid price: %s", tostring(self.newPrice)))
        TransactionResponseEvent.sendToClient(connection, 0, false, "usedplus_mp_error_invalid_params")
        return
    end

    -- v2.7.2 SECURITY: Require VehicleSaleManager and listing to exist
    if g_vehicleSaleManager == nil then
        UsedPlus.logError("[SECURITY] VehicleSaleManager not available")
        return
    end

    local listing = g_vehicleSaleManager:getListingById(self.listingId)
    if listing == nil then
        UsedPlus.logWarn(string.format("[SECURITY] Listing %s not found", self.listingId))
        return
    end

    -- v2.7.2: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, listing.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("MODIFY_PRICE_REJECTED",
            string.format("Unauthorized price modify for listing %s (farmId %d): %s",
                self.listingId, listing.farmId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, listing.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    local success = ModifyListingPriceEvent.execute(self.listingId, self.newPrice)
    if success then
        TransactionResponseEvent.sendToClient(connection, listing.farmId, true, "usedplus_mp_success_price_modified")
    else
        TransactionResponseEvent.sendToClient(connection, listing.farmId, false, "usedplus_mp_error_failed")
    end
end

--============================================================================
-- TRADE-IN VEHICLE EVENT
-- Network event for trading in a vehicle (delete vehicle + credit owner)
--============================================================================

TradeInVehicleEvent = {}
local TradeInVehicleEvent_mt = Class(TradeInVehicleEvent, Event)

InitEventClass(TradeInVehicleEvent, "TradeInVehicleEvent")

function TradeInVehicleEvent.emptyNew()
    local self = Event.new(TradeInVehicleEvent_mt)
    return self
end

function TradeInVehicleEvent.new(farmId, vehicleId, tradeInValue)
    local self = TradeInVehicleEvent.emptyNew()
    self.farmId = farmId
    self.vehicleId = vehicleId
    self.tradeInValue = tradeInValue
    return self
end

function TradeInVehicleEvent.sendToServer(farmId, vehicleId, tradeInValue)
    if g_server ~= nil then
        TradeInVehicleEvent.execute(farmId, vehicleId, tradeInValue)
    else
        g_client:getServerConnection():sendEvent(
            TradeInVehicleEvent.new(farmId, vehicleId, tradeInValue)
        )
    end
end

function TradeInVehicleEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteInt32(streamId, self.vehicleId)
    streamWriteFloat32(streamId, self.tradeInValue)
end

function TradeInVehicleEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.vehicleId = streamReadInt32(streamId)
    self.tradeInValue = streamReadFloat32(streamId)
    self:run(connection)
end

function TradeInVehicleEvent.execute(farmId, vehicleId, tradeInValue)
    -- Find the vehicle by id
    local vehicle = nil
    local vehicleName = "Unknown"
    if g_currentMission and g_currentMission.vehicleSystem then
        for _, v in pairs(g_currentMission.vehicleSystem.vehicles) do
            if v ~= nil and v.id == vehicleId then
                vehicle = v
                -- Get vehicle name for logging/history
                if v.getName then
                    vehicleName = v:getName()
                elseif v.storeItem and v.storeItem.name then
                    vehicleName = g_i18n:getText(v.storeItem.name) or v.storeItem.name
                end
                break
            end
        end
    end

    if vehicle == nil then
        UsedPlus.logError(string.format("TradeInVehicleEvent - Vehicle %d not found", vehicleId))
        return false, "usedplus_mp_error_vehicle_not_found"
    end

    -- Verify ownership
    if vehicle.ownerFarmId ~= farmId then
        UsedPlus.logError(string.format("TradeInVehicleEvent - Vehicle %d not owned by farm %d", vehicleId, farmId))
        return false, "usedplus_mp_error_not_owner"
    end

    -- Credit the farm using changeBalance (bypasses FSBaseMission.addMoney which
    -- crashes with 'attempt to index nil with id' when called from nested dialog callbacks)
    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then
        UsedPlus.logError(string.format("TradeInVehicleEvent - Farm %d not found", farmId))
        return false, "usedplus_mp_error_farm_not_found"
    end
    farm:changeBalance(tradeInValue, MoneyType.OTHER)

    -- v2.12.1: Do NOT delete vehicle here — just return success.
    -- The vehicle deletion is handled separately by the caller to avoid
    -- modifying the vehicle list during FSBaseMission:update() iteration.
    -- Store vehicle reference for caller to handle deletion.
    TradeInVehicleEvent._pendingDeleteVehicle = vehicle
    TradeInVehicleEvent._pendingDeleteVehicleId = vehicleId

    -- Record credit event if CreditHistory exists
    if CreditHistory and CreditHistory.recordEvent then
        CreditHistory.recordEvent(farmId, "VEHICLE_TRADE_IN", vehicleName)
    end

    UsedPlus.logInfo(string.format("TradeInVehicleEvent: Traded in '%s' for $%.2f (farm %d) - deletion deferred to caller",
        vehicleName, tradeInValue, farmId))

    return true, nil
end

function TradeInVehicleEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- Helper to check for NaN and Infinity values
    local function isInvalidNumber(v)
        return v == nil or v ~= v or v == math.huge or v == -math.huge
    end

    -- Validate tradeInValue is positive and reasonable
    if isInvalidNumber(self.tradeInValue) or self.tradeInValue <= 0 or self.tradeInValue > 100000000 then
        UsedPlus.logError(string.format("[SECURITY] Invalid trade-in value: %s", tostring(self.tradeInValue)))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_invalid_params")
        return
    end

    -- Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, self.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("TRADE_IN_REJECTED",
            string.format("Unauthorized trade-in attempt for farmId %d, vehicle %d: %s",
                self.farmId, self.vehicleId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    local success, failureKey = TradeInVehicleEvent.execute(self.farmId, self.vehicleId, self.tradeInValue)
    if success then
        TransactionResponseEvent.sendToClient(connection, self.farmId, true, "usedplus_mp_success_trade_in")
    else
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, failureKey or "usedplus_mp_error_failed")
    end
end

--============================================================================

UsedPlus.logInfo("SaleEvents loaded (CreateSaleListingEvent, SaleListingActionEvent, ModifyListingPriceEvent, TradeInVehicleEvent)")
