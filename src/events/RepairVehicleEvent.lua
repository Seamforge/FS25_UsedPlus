--[[
    FS25_UsedPlus - Repair Vehicle Event

    Network event for partial vehicle repair
    Pattern from: FinanceVehicleEvent (working reference)
    Reference: FS25_ADVANCED_PATTERNS.md - Network Synchronization

    Flow:
    1. Client: Player opens Repair dialog, selects repair percentages
    2. Client: Player clicks "Pay Cash" or "Finance"
    3. Client: RepairVehicleEvent:sendToServer(params)
    4. Server: Receives event, validates
    5. Server: Applies partial repair via addDamageAmount/addWearAmount
    6. Server: Deducts cost or creates finance deal
    7. Server: Broadcasts update to all clients

    Data transmitted:
    - Vehicle ID (network object ID)
    - Farm ID (int)
    - Repair percent (float 0-1)
    - Repaint percent (float 0-1)
    - Total cost (float)
    - Is financed (bool)
    - Finance term months (int, optional)
]]

RepairVehicleEvent = {}
local RepairVehicleEvent_mt = Class(RepairVehicleEvent, Event)

InitEventClass(RepairVehicleEvent, "RepairVehicleEvent")

--[[
    Constructor (empty event for receiving)
]]
function RepairVehicleEvent.emptyNew()
    local self = Event.new(RepairVehicleEvent_mt)
    return self
end

--[[
    Constructor with data (for sending)
]]
function RepairVehicleEvent.new(vehicleId, farmId, repairPercent, repaintPercent, totalCost, isFinanced, termMonths, monthlyPayment, downPayment)
    local self = RepairVehicleEvent.emptyNew()

    self.vehicleId = vehicleId
    self.farmId = farmId
    self.repairPercent = repairPercent or 0
    self.repaintPercent = repaintPercent or 0
    self.totalCost = totalCost or 0
    self.isFinanced = isFinanced or false
    self.termMonths = termMonths or 6
    self.monthlyPayment = monthlyPayment or 0
    self.downPayment = downPayment or 0

    return self
end

--[[
    Static helper to send event from client
    @param vehicle - The vehicle object to repair
    @param farmId - Farm ID
    @param repairPercent - Percentage of damage to repair (0-1)
    @param repaintPercent - Percentage of wear to repair (0-1)
    @param totalCost - Total cost of repair
    @param isFinanced - Whether to finance the repair
    @param termMonths - Finance term in months (if financed)
    @param monthlyPayment - Monthly payment amount (if financed)
    @param downPayment - Down payment amount (if financed)
]]
function RepairVehicleEvent.sendToServer(vehicle, farmId, repairPercent, repaintPercent, totalCost, isFinanced, termMonths, monthlyPayment, downPayment)
    -- Get vehicle network ID
    local vehicleId = nil
    if vehicle and vehicle.id then
        vehicleId = NetworkUtil.getObjectId(vehicle)
    end

    if vehicleId == nil then
        UsedPlus.logError("RepairVehicleEvent - Could not get vehicle network ID")
        return
    end

    if g_server ~= nil then
        -- Single-player or server - execute directly
        RepairVehicleEvent.execute(vehicleId, farmId, repairPercent, repaintPercent, totalCost, isFinanced, termMonths, monthlyPayment, downPayment)
    else
        -- Multiplayer client - send to server
        g_client:getServerConnection():sendEvent(
            RepairVehicleEvent.new(vehicleId, farmId, repairPercent, repaintPercent, totalCost, isFinanced, termMonths, monthlyPayment, downPayment)
        )
    end
end

--[[
    Serialize event data to network stream
]]
function RepairVehicleEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObjectId(streamId, self.vehicleId)
    streamWriteInt32(streamId, self.farmId)
    streamWriteFloat32(streamId, self.repairPercent)
    streamWriteFloat32(streamId, self.repaintPercent)
    streamWriteFloat32(streamId, self.totalCost)
    streamWriteBool(streamId, self.isFinanced)
    streamWriteInt32(streamId, self.termMonths)
    streamWriteFloat32(streamId, self.monthlyPayment)
    streamWriteFloat32(streamId, self.downPayment)
end

--[[
    Deserialize event data from network stream
]]
function RepairVehicleEvent:readStream(streamId, connection)
    self.vehicleId = NetworkUtil.readNodeObjectId(streamId)
    self.farmId = streamReadInt32(streamId)
    self.repairPercent = streamReadFloat32(streamId)
    self.repaintPercent = streamReadFloat32(streamId)
    self.totalCost = streamReadFloat32(streamId)
    self.isFinanced = streamReadBool(streamId)
    self.termMonths = streamReadInt32(streamId)
    self.monthlyPayment = streamReadFloat32(streamId)
    self.downPayment = streamReadFloat32(streamId)

    self:run(connection)
end

--[[
    Execute business logic
]]
function RepairVehicleEvent.execute(vehicleId, farmId, repairPercent, repaintPercent, totalCost, isFinanced, termMonths, monthlyPayment, downPayment)
    -- v2.8.0: Apply default values FIRST before validation
    -- These are optional parameters that may not be passed for cash payments
    local termMonths = termMonths or 6
    local monthlyPayment = monthlyPayment or 0
    local downPayment = downPayment or 0

    -- v2.7.2 SECURITY: Helper to check for NaN and Infinity values
    -- Note: No longer checks for nil since defaults are applied above
    local function isInvalidNumber(v)
        return v ~= v or v == math.huge or v == -math.huge
    end

    -- v2.7.2 SECURITY: Clamp percentage values to valid 0-1 range
    -- Prevents negative, >100%, NaN, or infinity values that could corrupt vehicle state
    if isInvalidNumber(repairPercent) then repairPercent = 0 end
    if isInvalidNumber(repaintPercent) then repaintPercent = 0 end
    repairPercent = math.max(0, math.min(1, repairPercent))
    repaintPercent = math.max(0, math.min(1, repaintPercent))

    -- v2.7.2 SECURITY: Validate cost values (including infinity check)
    if isInvalidNumber(totalCost) or totalCost < 0 or totalCost > 10000000 then
        UsedPlus.logError(string.format("[SECURITY] Invalid totalCost: %s", tostring(totalCost)))
        return false
    end
    if isInvalidNumber(downPayment) or downPayment < 0 then
        UsedPlus.logError(string.format("[SECURITY] Invalid downPayment: %s", tostring(downPayment)))
        return false
    end
    if isInvalidNumber(monthlyPayment) or monthlyPayment < 0 then
        UsedPlus.logError(string.format("[SECURITY] Invalid monthlyPayment: %s", tostring(monthlyPayment)))
        return false
    end

    -- Get vehicle from network ID
    local vehicle = NetworkUtil.getObject(vehicleId)
    if vehicle == nil then
        UsedPlus.logError("RepairVehicleEvent - Vehicle not found")
        return false
    end

    -- Validate farm
    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then
        UsedPlus.logError(string.format("RepairVehicleEvent - Farm %d not found", farmId))
        return false
    end

    -- Get vehicle name using consolidated utility
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local vehicleName = UIHelper.Vehicle.getFullName(storeItem)

    -- Determine work type for itemType field (NOT appended to name - that causes truncation)
    local workType = "service"  -- fallback
    if repairPercent > 0 and repaintPercent > 0 then
        workType = "repair_repaint"
    elseif repairPercent > 0 then
        workType = "repair"
    elseif repaintPercent > 0 then
        workType = "repaint"
    end

    -- Process payment
    if isFinanced then
        -- Create finance deal for repair
        if g_financeManager then
            -- Convert term months to years for createFinanceDeal
            -- For short-term repairs, we use fractional years (e.g., 6 months = 0.5 years)
            -- But createFinanceDeal validates termYears >= 1, so we use minimum 1 year
            local termYears = math.max(1, math.ceil(termMonths / 12))

            -- Calculate financed amount (total cost minus down payment)
            local financedAmount = totalCost - downPayment

            local deal = g_financeManager:createFinanceDeal(
                farmId,
                workType,  -- itemType: "repair", "repaint", or "repair_repaint"
                tostring(vehicleId),  -- itemId
                vehicleName,  -- itemName: just "Brand Model" (type shown separately)
                financedAmount,  -- price (amount being financed, not total cost)
                0,  -- downPayment already deducted from price above
                termYears,  -- term in YEARS (not months)
                0,  -- cashBack
                {}  -- configurations (N/A)
            )

            if deal then
                -- Deduct down payment if any
                if downPayment > 0 then
                    g_currentMission:addMoney(-downPayment, farmId, MoneyType.VEHICLE_REPAIR, true)
                    UsedPlus.logDebug(string.format("Down payment deducted: $%d", downPayment))
                end

                UsedPlus.logDebug(string.format("Repair financed: %s, financed amount: $%d, down payment: $%d, term: %d years",
                    vehicleName, financedAmount, downPayment, termYears))
            else
                UsedPlus.logError("Failed to create finance deal for repair")
                return false
            end
        else
            UsedPlus.logError("FinanceManager not available for repair financing")
            return false
        end
    else
        -- Cash payment - deduct immediately
        if farm.money < totalCost then
            UsedPlus.logError(string.format("Insufficient funds for repair. Need $%d, have $%.2f",
                totalCost, farm.money))
            return false
        end

        -- Deduct money
        g_currentMission:addMoney(-totalCost, farmId, MoneyType.VEHICLE_REPAIR, true)
    end

    -- Apply repairs
    local repairsApplied = false

    -- Apply mechanical repair (reduce damage)
    if repairPercent > 0 and vehicle.getDamageAmount and vehicle.addDamageAmount then
        local currentDamage = vehicle:getDamageAmount() or 0
        if currentDamage > 0.001 then
            -- Calculate damage to remove (negative value reduces damage)
            local damageToRemove = currentDamage * repairPercent
            vehicle:addDamageAmount(-damageToRemove, true)
            repairsApplied = true

            UsedPlus.logDebug(string.format("Applied mechanical repair: %.1f%% of %.1f%% damage removed",
                repairPercent * 100, currentDamage * 100))
        end
    end

    -- Apply repaint (reduce wear)
    if repaintPercent > 0 and vehicle.getWearTotalAmount and vehicle.addWearAmount then
        local currentWear = vehicle:getWearTotalAmount() or 0
        if currentWear > 0.001 then
            -- Calculate wear to remove (negative value reduces wear)
            local wearToRemove = currentWear * repaintPercent
            vehicle:addWearAmount(-wearToRemove, true)
            repairsApplied = true

            UsedPlus.logDebug(string.format("Applied repaint: %.1f%% of %.1f%% wear removed",
                repaintPercent * 100, currentWear * 100))
        end
    end

    -- v2.7.0: Workshop repair clears all seizures
    -- Any repair work at a proper workshop fixes seized components
    if repairPercent > 0 and UsedPlusMaintenance and UsedPlusMaintenance.clearSeizure then
        local hadSeizures = UsedPlusMaintenance.hasAnySeizure(vehicle)
        if hadSeizures then
            UsedPlusMaintenance.clearSeizure(vehicle, "all")
            UsedPlus.logDebug("Workshop repair: All seizures cleared")
        end
    end

    -- v2.7.0: Workshop repair fixes fuel leaks (engine-related issue)
    if repairPercent > 0 and UsedPlusMaintenance and UsedPlusMaintenance.repairFuelLeak then
        local spec = vehicle.spec_usedPlusMaintenance
        if spec and spec.hasFuelLeak then
            UsedPlusMaintenance.repairFuelLeak(vehicle)
            UsedPlus.logDebug("Workshop repair: Fuel leak fixed")
        end
    end

    -- v2.7.0: Workshop repair also fixes flat tires
    if repairPercent > 0 and UsedPlusMaintenance and UsedPlusMaintenance.repairFlatTire then
        local spec = vehicle.spec_usedPlusMaintenance
        if spec and spec.hasFlatTire then
            UsedPlusMaintenance.repairFlatTire(vehicle)
            UsedPlus.logDebug("Workshop repair: Flat tire fixed")
        end
    end

    -- v2.7.0: Update vehicle reliability via UsedPlusMaintenance
    -- This applies repair degradation (lemons degrade faster) and repair bonuses
    if repairPercent > 0 and UsedPlusMaintenance and UsedPlusMaintenance.onVehicleRepaired then
        UsedPlusMaintenance.onVehicleRepaired(vehicle, totalCost)
        UsedPlus.logDebug("Notified UsedPlusMaintenance of repair completion")
    end

    UsedPlus.logDebug(string.format("Repair completed: %s, repairs applied: %s, cost: $%d, financed: %s",
        vehicleName, tostring(repairsApplied), totalCost, tostring(isFinanced)))

    return true
end

--[[
    Execute event on server (called after readStream in multiplayer)
]]
function RepairVehicleEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- v2.7.2: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, self.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("REPAIR_REJECTED",
            string.format("Unauthorized repair attempt for farmId %d, vehicle %s: %s",
                self.farmId, tostring(self.vehicleId), errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    local success = RepairVehicleEvent.execute(
        self.vehicleId,
        self.farmId,
        self.repairPercent,
        self.repaintPercent,
        self.totalCost,
        self.isFinanced,
        self.termMonths,
        self.monthlyPayment,
        self.downPayment
    )
    if success then
        TransactionResponseEvent.sendToClient(connection, self.farmId, true, "usedplus_mp_success_repair")

        -- v2.15.0: Broadcast statistics sync to all clients
        SyncStatisticsEvent.broadcastForFarm(self.farmId)
    else
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_repair_failed")
    end
end

UsedPlus.logInfo("RepairVehicleEvent loaded")
