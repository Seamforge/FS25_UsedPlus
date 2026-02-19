--[[
    FS25_UsedPlus - Set Payment Configuration Event

    Network event for syncing payment configuration changes
    Pattern from: FinancePaymentEvent

    Flow:
    1. Client: Player changes payment mode/multiplier in DealDetailsDialog
    2. Client: SetPaymentConfigEvent.sendToServer(dealId, mode, customAmount, multiplier)
    3. Server: Validates deal ownership
    4. Server: Updates deal payment configuration
    5. Server: Broadcasts to all clients for sync

    Data transmitted:
    - Deal ID (string)
    - Payment Mode (int)
    - Custom Amount (float, optional)
    - Payment Multiplier (float, 1.0-3.0)
]]

SetPaymentConfigEvent = {}
local SetPaymentConfigEvent_mt = Class(SetPaymentConfigEvent, Event)

InitEventClass(SetPaymentConfigEvent, "SetPaymentConfigEvent")

--[[
    Constructor (empty event for receiving)
]]
function SetPaymentConfigEvent.emptyNew()
    local self = Event.new(SetPaymentConfigEvent_mt)
    return self
end

--[[
    Constructor with data (for sending)
]]
function SetPaymentConfigEvent.new(dealId, paymentMode, customAmount, multiplier)
    local self = SetPaymentConfigEvent.emptyNew()

    self.dealId = dealId
    self.paymentMode = paymentMode
    self.customAmount = customAmount or 0
    self.multiplier = multiplier or 1.0

    return self
end

--[[
    Static function to send event from client to server
]]
function SetPaymentConfigEvent.sendToServer(dealId, paymentMode, customAmount, multiplier)
    if g_server ~= nil then
        -- Single-player or server - execute directly
        SetPaymentConfigEvent.execute(dealId, paymentMode, customAmount, multiplier)
    else
        -- Multiplayer client - send to server
        g_client:getServerConnection():sendEvent(
            SetPaymentConfigEvent.new(dealId, paymentMode, customAmount, multiplier)
        )
    end
end

--[[
    Static execute method - performs the actual work
]]
function SetPaymentConfigEvent.execute(dealId, paymentMode, customAmount, multiplier)
    -- Validate finance manager
    if g_financeManager == nil then
        UsedPlus.logError("FinanceManager not initialized")
        return false
    end

    -- Get the deal
    local deal = g_financeManager:getDealById(dealId)
    if deal == nil then
        UsedPlus.logError(string.format("Deal %s not found", dealId))
        return false
    end

    -- Check if deal supports payment configuration
    if deal.setPaymentMode == nil then
        UsedPlus.logWarn(string.format("Deal %s does not support payment configuration", dealId))
        return false
    end

    -- Apply payment mode configuration
    deal:setPaymentMode(paymentMode, customAmount)

    -- Apply payment multiplier if provided
    if multiplier and multiplier >= 1.0 and deal.setPaymentMultiplier then
        deal:setPaymentMultiplier(multiplier)
    end

    -- Log the change
    local modeNames = {"Skip", "Minimum", "Standard", "Extra", "Custom"}
    local modeName = modeNames[paymentMode + 1] or "Unknown"

    UsedPlus.logDebug(string.format("Payment config updated for deal %s: mode=%s, multiplier=%.1fx, amount=$%.2f",
        dealId, modeName, multiplier or 1.0, customAmount or 0))

    return true
end

--[[
    Serialize event data to network stream
]]
function SetPaymentConfigEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.dealId)
    streamWriteInt32(streamId, self.paymentMode)
    streamWriteFloat32(streamId, self.customAmount)
    streamWriteFloat32(streamId, self.multiplier)
end

--[[
    Deserialize event data from network stream
]]
function SetPaymentConfigEvent:readStream(streamId, connection)
    self.dealId = streamReadString(streamId)
    self.paymentMode = streamReadInt32(streamId)
    self.customAmount = streamReadFloat32(streamId)
    self.multiplier = streamReadFloat32(streamId)

    self:run(connection)
end

--[[
    Execute event on server (multiplayer)
]]
function SetPaymentConfigEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- v2.7.2: Validate farm ownership to prevent multiplayer exploits
    if g_financeManager then
        local deal = g_financeManager:getDealById(self.dealId)
        if deal then
            local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, deal.farmId)
            if not isAuthorized then
                NetworkSecurity.logSecurityEvent("PAYMENT_CONFIG_REJECTED",
                    string.format("Unauthorized payment config change for deal %s (farmId %d): %s",
                        self.dealId, deal.farmId, errorMsg or "unknown"),
                    connection)
                return
            end
        end
    end

    -- Delegate to static execute method
    local success = SetPaymentConfigEvent.execute(self.dealId, self.paymentMode, self.customAmount, self.multiplier)

    -- v2.15.0: Broadcast deal update to all clients
    if success then
        local deal = g_financeManager and g_financeManager:getDealById(self.dealId)
        if deal then
            SyncFinanceDealsEvent.broadcastUpdateDeal(deal.farmId, self.dealId)
        end
    end
end

UsedPlus.logInfo("SetPaymentConfigEvent loaded")
