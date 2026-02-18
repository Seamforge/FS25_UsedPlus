--[[
    FS25_UsedPlus - Maintenance Events

    Network events for vehicle maintenance operations:
    - FieldRepairEvent: Field service kit repairs (seizure clearing)
    - RefillFluidsEvent: Oil/hydraulic fluid refills
    - ReplaceTiresEvent: Tire replacement

    v2.8.0: Part of GitHub Issue #1 fix - Multiplayer synchronization
]]

--============================================================================
-- FIELD REPAIR EVENT
-- Network event for field service kit repairs (seizure clearing)
--============================================================================

FieldRepairEvent = {}
local FieldRepairEvent_mt = Class(FieldRepairEvent, Event)

InitEventClass(FieldRepairEvent, "FieldRepairEvent")

function FieldRepairEvent.emptyNew()
    local self = Event.new(FieldRepairEvent_mt)
    return self
end

function FieldRepairEvent.new(farmId, vehicleId, component, cost)
    local self = FieldRepairEvent.emptyNew()
    self.farmId = farmId
    self.vehicleId = vehicleId
    self.component = component or "all"
    self.cost = cost or 0
    return self
end

--[[
    Static helper to send event from client
    @param farmId - Farm ID
    @param vehicleId - Vehicle ID (not network ID)
    @param component - Component to repair ("engine", "transmission", "hydraulics", "all")
    @param cost - Cost of repair
]]
function FieldRepairEvent.sendToServer(farmId, vehicleId, component, cost)
    if g_server ~= nil then
        -- Single-player or server - execute directly
        FieldRepairEvent.execute(farmId, vehicleId, component, cost)
    else
        -- Multiplayer client - send to server
        g_client:getServerConnection():sendEvent(
            FieldRepairEvent.new(farmId, vehicleId, component, cost)
        )
    end
end

function FieldRepairEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteInt32(streamId, self.vehicleId)
    streamWriteString(streamId, self.component)
    streamWriteFloat32(streamId, self.cost)
end

function FieldRepairEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.vehicleId = streamReadInt32(streamId)
    self.component = streamReadString(streamId)
    self.cost = streamReadFloat32(streamId)
    self:run(connection)
end

function FieldRepairEvent.execute(farmId, vehicleId, component, cost)
    -- Apply defaults
    local component = component or "all"
    local cost = cost or 0

    -- v2.8.0 SECURITY: Helper to check for NaN and Infinity values
    local function isInvalidNumber(v)
        return v == nil or v ~= v or v == math.huge or v == -math.huge
    end

    -- Validate cost
    if isInvalidNumber(cost) or cost < 0 or cost > 10000000 then
        UsedPlus.logError(string.format("[SECURITY] FieldRepairEvent - Invalid cost: %s", tostring(cost)))
        return false
    end

    -- Validate component string (accept both singular and plural forms for hydraulic/electrical)
    local validComponents = {
        engine = true,
        transmission = true,
        hydraulic = true,
        hydraulics = true,
        electrical = true,
        all = true
    }
    if not validComponents[component] then
        UsedPlus.logError(string.format("[SECURITY] FieldRepairEvent - Invalid component: %s", tostring(component)))
        return false
    end

    -- Normalize to forms expected by UsedPlusMaintenance.clearSeizure
    -- clearSeizure uses: "engine", "hydraulic", "electrical", "all"
    if component == "hydraulics" then
        component = "hydraulic"
    end

    -- Find vehicle by ID
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
        UsedPlus.logError(string.format("FieldRepairEvent - Vehicle %d not found", vehicleId))
        return false
    end

    -- Validate farm ownership
    if vehicle.ownerFarmId ~= farmId then
        UsedPlus.logError(string.format("FieldRepairEvent - Vehicle not owned by farm %d", farmId))
        return false
    end

    -- Validate farm exists
    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then
        UsedPlus.logError(string.format("FieldRepairEvent - Farm %d not found", farmId))
        return false
    end

    -- Check sufficient funds
    if farm.money < cost then
        UsedPlus.logError(string.format("FieldRepairEvent - Insufficient funds. Need $%.2f, have $%.2f", cost, farm.money))
        return false
    end

    -- Deduct cost
    if cost > 0 then
        g_currentMission:addMoney(-cost, farmId, MoneyType.VEHICLE_REPAIR, true, true)
        UsedPlus.logDebug(string.format("FieldRepairEvent - Deducted $%.2f for field repair", cost))
    end

    -- Apply repair: clear seizure
    if UsedPlusMaintenance and UsedPlusMaintenance.clearSeizure then
        UsedPlusMaintenance.clearSeizure(vehicle, component)
        UsedPlus.logDebug(string.format("FieldRepairEvent - Cleared seizure on %s for vehicle %d", component, vehicleId))
    else
        UsedPlus.logWarn("FieldRepairEvent - UsedPlusMaintenance not available, seizure not cleared")
    end

    -- v2.8.0: Also restore reliability to minimum threshold after seizure repair
    -- This ensures multiplayer clients get synced reliability values
    local spec = vehicle.spec_usedPlusMaintenance
    if spec then
        local minReliability = 0.30  -- Default minimum after seizure repair
        if UsedPlusMaintenance and UsedPlusMaintenance.CONFIG then
            minReliability = UsedPlusMaintenance.CONFIG.seizureRepairMinReliability or 0.30
        end
        local vehicleCeiling = spec.maxReliabilityCeiling or 1.0
        local effectiveMinReliability = math.min(minReliability, vehicleCeiling)

        if component == "engine" or component == "all" then
            spec.engineReliability = math.max(spec.engineReliability or 0, effectiveMinReliability)
        end
        if component == "hydraulic" or component == "all" then
            spec.hydraulicReliability = math.max(spec.hydraulicReliability or 0, effectiveMinReliability)
        end
        if component == "electrical" or component == "all" then
            spec.electricalReliability = math.max(spec.electricalReliability or 0, effectiveMinReliability)
        end

        UsedPlus.logDebug(string.format("FieldRepairEvent - Reliability restored to %.0f%% for %s",
            effectiveMinReliability * 100, component))
    end

    return true
end

function FieldRepairEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- v2.8.0: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, self.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("FIELD_REPAIR_REJECTED",
            string.format("Unauthorized field repair attempt for farmId %d, vehicle %d: %s",
                self.farmId, self.vehicleId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    local success = FieldRepairEvent.execute(self.farmId, self.vehicleId, self.component, self.cost)
    if success then
        TransactionResponseEvent.sendToClient(connection, self.farmId, true, "usedplus_mp_success_field_repair")
    else
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_field_repair_failed")
    end
end

--============================================================================
-- REFILL FLUIDS EVENT
-- Network event for oil/hydraulic fluid refills
--============================================================================

RefillFluidsEvent = {}
local RefillFluidsEvent_mt = Class(RefillFluidsEvent, Event)

InitEventClass(RefillFluidsEvent, "RefillFluidsEvent")

function RefillFluidsEvent.emptyNew()
    local self = Event.new(RefillFluidsEvent_mt)
    return self
end

function RefillFluidsEvent.new(farmId, vehicleId, fluidType, cost)
    local self = RefillFluidsEvent.emptyNew()
    self.farmId = farmId
    self.vehicleId = vehicleId
    self.fluidType = fluidType or "both"
    self.cost = cost or 0
    return self
end

--[[
    Static helper to send event from client
    @param farmId - Farm ID
    @param vehicleId - Vehicle ID (not network ID)
    @param fluidType - Type of fluid ("oil", "hydraulic", "both")
    @param cost - Cost of refill
]]
function RefillFluidsEvent.sendToServer(farmId, vehicleId, fluidType, cost)
    if g_server ~= nil then
        -- Single-player or server - execute directly
        RefillFluidsEvent.execute(farmId, vehicleId, fluidType, cost)
    else
        -- Multiplayer client - send to server
        g_client:getServerConnection():sendEvent(
            RefillFluidsEvent.new(farmId, vehicleId, fluidType, cost)
        )
    end
end

function RefillFluidsEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteInt32(streamId, self.vehicleId)
    streamWriteString(streamId, self.fluidType)
    streamWriteFloat32(streamId, self.cost)
end

function RefillFluidsEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.vehicleId = streamReadInt32(streamId)
    self.fluidType = streamReadString(streamId)
    self.cost = streamReadFloat32(streamId)
    self:run(connection)
end

function RefillFluidsEvent.execute(farmId, vehicleId, fluidType, cost)
    -- Apply defaults
    local fluidType = fluidType or "both"
    local cost = cost or 0

    -- v2.8.0 SECURITY: Helper to check for NaN and Infinity values
    local function isInvalidNumber(v)
        return v == nil or v ~= v or v == math.huge or v == -math.huge
    end

    -- Validate cost
    if isInvalidNumber(cost) or cost < 0 or cost > 10000000 then
        UsedPlus.logError(string.format("[SECURITY] RefillFluidsEvent - Invalid cost: %s", tostring(cost)))
        return false
    end

    -- Validate fluid type string
    local validFluidTypes = { oil = true, hydraulic = true, both = true }
    if not validFluidTypes[fluidType] then
        UsedPlus.logError(string.format("[SECURITY] RefillFluidsEvent - Invalid fluidType: %s", tostring(fluidType)))
        return false
    end

    -- Find vehicle by ID
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
        UsedPlus.logError(string.format("RefillFluidsEvent - Vehicle %d not found", vehicleId))
        return false
    end

    -- Validate farm ownership
    if vehicle.ownerFarmId ~= farmId then
        UsedPlus.logError(string.format("RefillFluidsEvent - Vehicle not owned by farm %d", farmId))
        return false
    end

    -- Validate farm exists
    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then
        UsedPlus.logError(string.format("RefillFluidsEvent - Farm %d not found", farmId))
        return false
    end

    -- Check sufficient funds
    if farm.money < cost then
        UsedPlus.logError(string.format("RefillFluidsEvent - Insufficient funds. Need $%.2f, have $%.2f", cost, farm.money))
        return false
    end

    -- Deduct cost
    if cost > 0 then
        g_currentMission:addMoney(-cost, farmId, MoneyType.VEHICLE_REPAIR, true, true)
        UsedPlus.logDebug(string.format("RefillFluidsEvent - Deducted $%.2f for fluid refill", cost))
    end

    -- Apply fluid refills based on type
    if UsedPlusMaintenance then
        if fluidType == "oil" or fluidType == "both" then
            if UsedPlusMaintenance.refillOil then
                UsedPlusMaintenance.refillOil(vehicle)
                UsedPlus.logDebug(string.format("RefillFluidsEvent - Refilled oil for vehicle %d", vehicleId))
            else
                UsedPlus.logWarn("RefillFluidsEvent - UsedPlusMaintenance.refillOil not available")
            end
        end

        if fluidType == "hydraulic" or fluidType == "both" then
            if UsedPlusMaintenance.refillHydraulicFluid then
                UsedPlusMaintenance.refillHydraulicFluid(vehicle)
                UsedPlus.logDebug(string.format("RefillFluidsEvent - Refilled hydraulic fluid for vehicle %d", vehicleId))
            else
                UsedPlus.logWarn("RefillFluidsEvent - UsedPlusMaintenance.refillHydraulicFluid not available")
            end
        end
    else
        UsedPlus.logWarn("RefillFluidsEvent - UsedPlusMaintenance not available, fluids not refilled")
    end

    return true
end

function RefillFluidsEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- v2.8.0: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, self.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("REFILL_FLUIDS_REJECTED",
            string.format("Unauthorized fluid refill attempt for farmId %d, vehicle %d: %s",
                self.farmId, self.vehicleId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    local success = RefillFluidsEvent.execute(self.farmId, self.vehicleId, self.fluidType, self.cost)
    if success then
        TransactionResponseEvent.sendToClient(connection, self.farmId, true, "usedplus_mp_success_refill_fluids")
    else
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_refill_fluids_failed")
    end
end

--============================================================================
-- REPLACE TIRES EVENT
-- Network event for tire replacement
--============================================================================

ReplaceTiresEvent = {}
local ReplaceTiresEvent_mt = Class(ReplaceTiresEvent, Event)

InitEventClass(ReplaceTiresEvent, "ReplaceTiresEvent")

function ReplaceTiresEvent.emptyNew()
    local self = Event.new(ReplaceTiresEvent_mt)
    return self
end

function ReplaceTiresEvent.new(farmId, vehicleId, tireType, cost)
    local self = ReplaceTiresEvent.emptyNew()
    self.farmId = farmId
    self.vehicleId = vehicleId
    self.tireType = tireType or "standard"
    self.cost = cost or 0
    return self
end

--[[
    Static helper to send event from client
    @param farmId - Farm ID
    @param vehicleId - Vehicle ID (not network ID)
    @param tireQuality - Quality tier: 1=Retread, 2=Normal, 3=Quality (matches TiresDialog constants)
    @param cost - Cost of tire replacement
]]
function ReplaceTiresEvent.sendToServer(farmId, vehicleId, tireQuality, cost)
    if g_server ~= nil then
        -- Single-player or server - execute directly
        ReplaceTiresEvent.execute(farmId, vehicleId, tireQuality, cost)
    else
        -- Multiplayer client - send to server
        g_client:getServerConnection():sendEvent(
            ReplaceTiresEvent.new(farmId, vehicleId, tireQuality, cost)
        )
    end
end

function ReplaceTiresEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteInt32(streamId, self.vehicleId)
    streamWriteString(streamId, self.tireType)
    streamWriteFloat32(streamId, self.cost)
end

function ReplaceTiresEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.vehicleId = streamReadInt32(streamId)
    self.tireType = streamReadString(streamId)
    self.cost = streamReadFloat32(streamId)
    self:run(connection)
end

function ReplaceTiresEvent.execute(farmId, vehicleId, tireQuality, cost)
    -- Apply defaults
    -- tireQuality: 1=Retread, 2=Normal, 3=Quality (matches TiresDialog constants)
    local tireQuality = tonumber(tireQuality) or 2
    local cost = cost or 0

    -- v2.8.0 SECURITY: Helper to check for NaN and Infinity values
    local function isInvalidNumber(v)
        return v == nil or v ~= v or v == math.huge or v == -math.huge
    end

    -- Validate cost
    if isInvalidNumber(cost) or cost < 0 or cost > 10000000 then
        UsedPlus.logError(string.format("[SECURITY] ReplaceTiresEvent - Invalid cost: %s", tostring(cost)))
        return false
    end

    -- Validate tire quality (1=Retread, 2=Normal, 3=Quality)
    if isInvalidNumber(tireQuality) or tireQuality < 1 or tireQuality > 3 then
        UsedPlus.logError(string.format("[SECURITY] ReplaceTiresEvent - Invalid tireQuality: %s", tostring(tireQuality)))
        return false
    end

    -- Find vehicle by ID
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
        UsedPlus.logError(string.format("ReplaceTiresEvent - Vehicle %d not found", vehicleId))
        return false
    end

    -- Validate farm ownership
    if vehicle.ownerFarmId ~= farmId then
        UsedPlus.logError(string.format("ReplaceTiresEvent - Vehicle not owned by farm %d", farmId))
        return false
    end

    -- Validate farm exists
    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then
        UsedPlus.logError(string.format("ReplaceTiresEvent - Farm %d not found", farmId))
        return false
    end

    -- Check sufficient funds
    if farm.money < cost then
        UsedPlus.logError(string.format("ReplaceTiresEvent - Insufficient funds. Need $%.2f, have $%.2f", cost, farm.money))
        return false
    end

    -- Deduct cost
    if cost > 0 then
        g_currentMission:addMoney(-cost, farmId, MoneyType.VEHICLE_REPAIR, true, true)
        UsedPlus.logDebug(string.format("ReplaceTiresEvent - Deducted $%.2f for tire replacement", cost))
    end

    -- Apply tire replacement
    if UsedPlusMaintenance then
        -- Set tire quality tier (1=Retread, 2=Normal, 3=Quality)
        if UsedPlusMaintenance.setTireQuality then
            UsedPlusMaintenance.setTireQuality(vehicle, tireQuality)
            UsedPlus.logDebug(string.format("ReplaceTiresEvent - Set tire quality to %d for vehicle %d", tireQuality, vehicleId))
        else
            UsedPlus.logWarn("ReplaceTiresEvent - UsedPlusMaintenance.setTireQuality not available")
        end

        -- v2.8.0: Tire replacement also repairs flat tires
        if UsedPlusMaintenance.repairFlatTire then
            UsedPlusMaintenance.repairFlatTire(vehicle)
            UsedPlus.logDebug(string.format("ReplaceTiresEvent - Repaired flat tire for vehicle %d", vehicleId))
        end
    else
        UsedPlus.logWarn("ReplaceTiresEvent - UsedPlusMaintenance not available, tires not replaced")
    end

    return true
end

function ReplaceTiresEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- v2.8.0: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, self.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("REPLACE_TIRES_REJECTED",
            string.format("Unauthorized tire replacement attempt for farmId %d, vehicle %d: %s",
                self.farmId, self.vehicleId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    local success = ReplaceTiresEvent.execute(self.farmId, self.vehicleId, self.tireType, self.cost)
    if success then
        TransactionResponseEvent.sendToClient(connection, self.farmId, true, "usedplus_mp_success_replace_tires")
    else
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_replace_tires_failed")
    end
end

--============================================================================

UsedPlus.logInfo("MaintenanceEvents loaded (FieldRepairEvent, RefillFluidsEvent, ReplaceTiresEvent)")
