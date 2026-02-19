--[[
    FS25_UsedPlus - Fault Tracer Result Event

    Network event for applying Fault Tracer minigame results.
    Sends reliability gain, ceiling gain, and oil consumption to server
    so multiplayer state stays in sync.

    v2.12.0 - Fault Tracer Minigame
]]

FaultTracerResultEvent = {}
local FaultTracerResultEvent_mt = Class(FaultTracerResultEvent, Event)

InitEventClass(FaultTracerResultEvent, "FaultTracerResultEvent")

function FaultTracerResultEvent.emptyNew()
    local self = Event.new(FaultTracerResultEvent_mt)
    return self
end

function FaultTracerResultEvent.new(vehicleId, truckId, component, reliabilityGain, ceilingGain, oilUsed)
    local self = FaultTracerResultEvent.emptyNew()
    self.vehicleId = vehicleId
    self.truckId = truckId
    self.component = component
    self.reliabilityGain = reliabilityGain
    self.ceilingGain = ceilingGain
    self.oilUsed = oilUsed
    return self
end

--[[
    Static helper to send event from client.
    @param vehicleId number - Vehicle entity ID
    @param truckId number - Service Truck entity ID
    @param component string - "engine"|"electrical"|"hydraulic"
    @param reliabilityGain number - Reliability improvement (0.0-1.0)
    @param ceilingGain number - Ceiling improvement (0.0-1.0)
    @param oilUsed number - Total oil consumed (liters)
]]
function FaultTracerResultEvent.sendToServer(vehicleId, truckId, component, reliabilityGain, ceilingGain, oilUsed)
    if g_server ~= nil then
        -- Single-player or server - execute directly
        FaultTracerResultEvent.execute(vehicleId, truckId, component, reliabilityGain, ceilingGain, oilUsed)
    else
        -- Multiplayer client - send to server
        g_client:getServerConnection():sendEvent(
            FaultTracerResultEvent.new(vehicleId, truckId, component, reliabilityGain, ceilingGain, oilUsed)
        )
    end
end

function FaultTracerResultEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.vehicleId)
    streamWriteInt32(streamId, self.truckId)
    streamWriteString(streamId, self.component)
    streamWriteFloat32(streamId, self.reliabilityGain)
    streamWriteFloat32(streamId, self.ceilingGain)
    streamWriteFloat32(streamId, self.oilUsed)
end

function FaultTracerResultEvent:readStream(streamId, connection)
    self.vehicleId = streamReadInt32(streamId)
    self.truckId = streamReadInt32(streamId)
    self.component = streamReadString(streamId)
    self.reliabilityGain = streamReadFloat32(streamId)
    self.ceilingGain = streamReadFloat32(streamId)
    self.oilUsed = streamReadFloat32(streamId)
    self:run(connection)
end

function FaultTracerResultEvent:run(connection)
    local success = FaultTracerResultEvent.execute(self.vehicleId, self.truckId, self.component, self.reliabilityGain, self.ceilingGain, self.oilUsed)

    -- v2.15.0: Broadcast statistics sync to all clients
    if success and g_server ~= nil then
        -- Extract farmId from vehicle for stats sync
        local vehicle = nil
        if g_currentMission and g_currentMission.vehicleSystem then
            for _, v in pairs(g_currentMission.vehicleSystem.vehicles) do
                if v.id == self.vehicleId then
                    vehicle = v
                    break
                end
            end
        end
        if vehicle and vehicle:getOwnerFarmId() then
            SyncStatisticsEvent.broadcastForFarm(vehicle:getOwnerFarmId())
        end
    end
end

--[[
    Execute the repair result on the server.
    Validates all inputs, applies reliability/ceiling gains, consumes oil.
]]
function FaultTracerResultEvent.execute(vehicleId, truckId, component, reliabilityGain, ceilingGain, oilUsed)
    -- Helper to check for NaN and Infinity values
    local function isInvalidNumber(v)
        return v == nil or v ~= v or v == math.huge or v == -math.huge
    end

    -- Validate component
    local validComponents = { engine = true, electrical = true, hydraulic = true }
    if not validComponents[component] then
        UsedPlus.logError(string.format("[SECURITY] FaultTracerResultEvent - Invalid component: %s", tostring(component)))
        return false
    end

    -- Validate numeric ranges
    if isInvalidNumber(reliabilityGain) or reliabilityGain < 0 or reliabilityGain > 0.50 then
        UsedPlus.logError(string.format("[SECURITY] FaultTracerResultEvent - Invalid reliabilityGain: %s", tostring(reliabilityGain)))
        return false
    end
    if isInvalidNumber(ceilingGain) or ceilingGain < 0 or ceilingGain > 0.10 then
        UsedPlus.logError(string.format("[SECURITY] FaultTracerResultEvent - Invalid ceilingGain: %s", tostring(ceilingGain)))
        return false
    end
    if isInvalidNumber(oilUsed) or oilUsed < 0 or oilUsed > 100 then
        UsedPlus.logError(string.format("[SECURITY] FaultTracerResultEvent - Invalid oilUsed: %s", tostring(oilUsed)))
        return false
    end

    -- Find target vehicle
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
        UsedPlus.logError(string.format("FaultTracerResultEvent - Vehicle %d not found", vehicleId))
        return false
    end

    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then
        UsedPlus.logError(string.format("FaultTracerResultEvent - Vehicle %d has no maintenance spec", vehicleId))
        return false
    end

    -- Find service truck
    local truck = nil
    if g_currentMission and g_currentMission.vehicleSystem then
        for _, v in pairs(g_currentMission.vehicleSystem.vehicles) do
            if v.id == truckId then
                truck = v
                break
            end
        end
    end

    if truck == nil then
        UsedPlus.logError(string.format("FaultTracerResultEvent - Service Truck %d not found", truckId))
        return false
    end

    -- Apply reliability gain
    if component == "engine" then
        maintSpec.engineReliability = math.min(1.0, (maintSpec.engineReliability or 0) + reliabilityGain)
    elseif component == "electrical" then
        maintSpec.electricalReliability = math.min(1.0, (maintSpec.electricalReliability or 0) + reliabilityGain)
    elseif component == "hydraulic" then
        maintSpec.hydraulicReliability = math.min(1.0, (maintSpec.hydraulicReliability or 0) + reliabilityGain)
    end

    -- Apply ceiling restoration
    maintSpec.maxReliabilityCeiling = math.min(1.0,
        (maintSpec.maxReliabilityCeiling or 1.0) + ceilingGain)

    -- Consume oil from service truck
    local truckSpec = truck.spec_serviceTruck
    if truckSpec ~= nil and truckSpec.oilFillUnit ~= nil then
        local oilFillType = g_fillTypeManager:getFillTypeIndexByName("OIL")
        if oilFillType ~= nil then
            truck:addFillUnitFillLevel(
                truck:getOwnerFarmId(),
                truckSpec.oilFillUnit,
                -oilUsed,
                oilFillType,
                ToolType.UNDEFINED, nil)
        end
    end

    local vehicleName = vehicle:getName() or "Vehicle"
    UsedPlus.logInfo(string.format("FaultTracer: Applied +%.1f%% reliability, +%.1f%% ceiling to %s (%s). Oil used: %.1fL",
        reliabilityGain * 100, ceilingGain * 100, vehicleName, component, oilUsed))

    return true
end

UsedPlus.logInfo("FaultTracerResultEvent loaded - Fault Tracer multiplayer event ready")
