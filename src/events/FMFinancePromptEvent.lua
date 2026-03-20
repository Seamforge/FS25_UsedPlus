--[[
    FMFinancePromptEvent - Server→Client prompt for FM negotiated purchase payment
    v2.15.5: Issue #29 — Farmland Market negotiation + financing integration

    Sent by the server when it intercepts a FarmlandStateEvent with a negotiated
    price (from FM). The client receives this and shows the UnifiedLandPurchaseDialog
    with Cash/Finance/Lease options at the negotiated price.
]]

FMFinancePromptEvent = {}
local FMFinancePromptEvent_mt = Class(FMFinancePromptEvent, Event)

InitEventClass(FMFinancePromptEvent, "FMFinancePromptEvent")

function FMFinancePromptEvent.emptyNew()
    local self = Event.new(FMFinancePromptEvent_mt)
    return self
end

function FMFinancePromptEvent.new(farmlandId, farmId, negotiatedPrice, landName)
    local self = FMFinancePromptEvent.emptyNew()
    self.farmlandId = farmlandId
    self.farmId = farmId
    self.negotiatedPrice = negotiatedPrice
    self.landName = landName or ""
    return self
end

--[[
    Send prompt to the client that initiated the purchase.
    Handles both MP clients and single-player/host.
    @param connection - The client connection (from FarmlandStateEvent.run)
    @param farmlandId - Farmland being purchased
    @param farmId - Buying farm ID
    @param negotiatedPrice - Price from FM negotiation
    @param landName - Display name for the field
]]
function FMFinancePromptEvent.sendToClient(connection, farmlandId, farmId, negotiatedPrice, landName)
    local event = FMFinancePromptEvent.new(farmlandId, farmId, negotiatedPrice, landName)
    if g_server ~= nil and connection ~= nil and not connection:getIsServer() then
        -- MP: send to the specific client
        connection:sendEvent(event)
    elseif g_server ~= nil then
        -- Single-player / host: show dialog directly
        FMFinancePromptEvent.showPaymentDialog(farmlandId, farmId, negotiatedPrice, landName)
    else
        UsedPlus.logWarn("[FM-INTEGRATION] sendToClient: No server — cannot send prompt")
    end
end

function FMFinancePromptEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmlandId)
    streamWriteInt32(streamId, self.farmId)
    streamWriteFloat32(streamId, self.negotiatedPrice)
    streamWriteString(streamId, self.landName)
end

function FMFinancePromptEvent:readStream(streamId, connection)
    self.farmlandId = streamReadInt32(streamId)
    self.farmId = streamReadInt32(streamId)
    self.negotiatedPrice = streamReadFloat32(streamId)
    self.landName = streamReadString(streamId)
    self:run(connection)
end

function FMFinancePromptEvent:run(connection)
    -- Only execute on client (connection IS server means we're on client receiving from server)
    if connection ~= nil and not connection:getIsServer() then
        return
    end

    -- Show payment dialog on this client
    FMFinancePromptEvent.showPaymentDialog(self.farmlandId, self.farmId, self.negotiatedPrice, self.landName)
end

--[[
    Show the payment dialog with the negotiated price.
    Called on the client after receiving the prompt from the server.
]]
function FMFinancePromptEvent.showPaymentDialog(farmlandId, farmId, negotiatedPrice, landName)
    -- Only show to the player whose farm matches
    if g_currentMission and g_currentMission:getFarmId() ~= farmId then
        return
    end

    local farmland = g_farmlandManager:getFarmlandById(farmlandId)
    if not farmland then
        UsedPlus.logWarn(string.format("[FM-INTEGRATION] Farmland %d not found on client", farmlandId))
        return
    end

    if not DialogLoader.ensureLoaded("UnifiedLandPurchaseDialog") then
        UsedPlus.logWarn("[FM-INTEGRATION] Failed to load UnifiedLandPurchaseDialog")
        return
    end

    local dialog = DialogLoader.getDialog("UnifiedLandPurchaseDialog")
    if dialog then
        dialog:setFMNegotiatedData(farmlandId, farmland, negotiatedPrice, nil)
        dialog:setInitialMode(UnifiedLandPurchaseDialog.MODE_FINANCE)
        g_gui:showDialog("UnifiedLandPurchaseDialog")
        UsedPlus.logInfo(string.format("[FM-INTEGRATION] Payment dialog shown: farmland=%d, price=%.0f", farmlandId, negotiatedPrice))
    else
        UsedPlus.logWarn("[FM-INTEGRATION] Dialog instance not found")
    end
end

UsedPlus.logInfo("FMFinancePromptEvent loaded")
