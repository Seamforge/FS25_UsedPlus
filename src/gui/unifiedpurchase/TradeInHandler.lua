--[[
    TradeInHandler - Trade-in vehicle discovery, validation, value calculation

    Purpose: Handle all trade-in related operations.
    Stateless functions that operate on PurchaseContext.

    Responsibilities:
    - Load eligible trade-in vehicles for farm
    - Calculate trade-in value based on condition, age, credit
    - Set selected trade-in vehicle
    - Execute trade-in transaction
]]

TradeInHandler = {}

--[[
    Load eligible trade-in vehicles for the current farm
    Updates context: eligibleTradeIns
    @param context - PurchaseContext instance
    @param farmId - Farm ID to load vehicles for
]]
function TradeInHandler.loadEligible(context, farmId)
    context.eligibleTradeIns = {}

    -- v1.4.0: Check settings system for trade-in feature toggle
    local tradeInEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("TradeIn")
    if not tradeInEnabled then
        UsedPlus.logDebug("Trade-in system disabled by settings")
        return
    end

    -- Get credit-based trade-in multiplier (returns baseTradeInPercent to baseTradeInPercent+15%)
    local creditMultiplier = CreditCalculations.getTradeInMultiplier(context)

    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if vehicle.ownerFarmId == farmId and
           vehicle.propertyState == VehiclePropertyState.OWNED then
            -- Check if vehicle has outstanding finance
            local hasFinance = false
            if g_financeManager then
                local deals = g_financeManager:getDealsForFarm(farmId)
                if deals then
                    for _, deal in ipairs(deals) do
                        if deal.status == "active" and deal.itemId == vehicle.configFileName then
                            hasFinance = true
                            break
                        end
                    end
                end
            end

            -- Only add if no outstanding finance
            if not hasFinance then
                -- Get base sell price (what vanilla would give you)
                local sellPrice = vehicle:getSellPrice() or 0

                -- Get vehicle condition using TradeInCalculations helpers
                local damageLevel = 0
                local wearLevel = 0
                local conditionMultiplier = 1.0

                if TradeInCalculations then
                    damageLevel = TradeInCalculations.getVehicleDamage(vehicle)
                    wearLevel = TradeInCalculations.getVehicleWear(vehicle)
                    conditionMultiplier = TradeInCalculations.calculateConditionMultiplier(damageLevel, wearLevel)
                end

                -- Calculate trade-in value:
                -- 1. Start with vanilla sell price
                -- 2. Apply credit-based percentage (50-65%)
                -- 3. Apply condition multiplier (damage + wear penalty, 70-100%)
                local tradeInValue = math.floor(sellPrice * creditMultiplier * conditionMultiplier)

                -- Calculate condition percentages for display
                local repairPercent = math.floor((1 - damageLevel) * 100)
                local paintPercent = math.floor((1 - wearLevel) * 100)

                table.insert(context.eligibleTradeIns, {
                    vehicle = vehicle,
                    name = vehicle:getFullName() or "Unknown",
                    value = tradeInValue,
                    sellPrice = sellPrice,  -- Store for reference
                    creditMultiplier = creditMultiplier,
                    conditionMultiplier = conditionMultiplier,
                    damageLevel = damageLevel,
                    wearLevel = wearLevel,
                    repairPercent = repairPercent,
                    paintPercent = paintPercent,
                    condition = math.floor((repairPercent + paintPercent) / 2),  -- Average condition
                    operatingHours = vehicle.operatingTime or 0
                })
            end
        end
    end
end

--[[
    Calculate trade-in value for a vehicle
    @param context - PurchaseContext instance (for credit multiplier)
    @param vehicle - Vehicle to evaluate
    @return tradeInValue - Calculated value
]]
function TradeInHandler.calculateValue(context, vehicle)
    if not vehicle then
        return 0
    end

    -- Get credit-based trade-in multiplier
    local creditMultiplier = CreditCalculations.getTradeInMultiplier(context)

    -- Get base sell price
    local sellPrice = vehicle:getSellPrice() or 0

    -- Get vehicle condition
    local damageLevel = 0
    local wearLevel = 0
    local conditionMultiplier = 1.0

    if TradeInCalculations then
        damageLevel = TradeInCalculations.getVehicleDamage(vehicle)
        wearLevel = TradeInCalculations.getVehicleWear(vehicle)
        conditionMultiplier = TradeInCalculations.calculateConditionMultiplier(damageLevel, wearLevel)
    end

    -- Calculate trade-in value
    local tradeInValue = math.floor(sellPrice * creditMultiplier * conditionMultiplier)

    return tradeInValue
end

--[[
    Set the selected trade-in vehicle
    Updates context: tradeInVehicle, tradeInValue, tradeInEnabled
    @param context - PurchaseContext instance
    @param vehicle - Vehicle to trade in (or nil to disable)
]]
function TradeInHandler.setTradeIn(context, vehicle)
    if vehicle == nil then
        context.tradeInEnabled = false
        context.tradeInVehicle = nil
        context.tradeInValue = 0
    else
        context.tradeInEnabled = true
        context.tradeInVehicle = vehicle
        context.tradeInValue = TradeInHandler.calculateValue(context, vehicle)
    end
end

--[[
    Execute trade-in transaction (remove vehicle from game, credit farm)
    @param context - PurchaseContext instance
    @param farmId - Farm ID
    @return success
]]
function TradeInHandler.execute(context, farmId)
    if not context.tradeInVehicle then
        return false
    end

    local vehicleId = context.tradeInVehicle.id
    local tradeInValue = context.tradeInValue or 0

    -- v2.8.0: Use network event for multiplayer synchronization
    -- Event handles: farm credit, vehicle deletion, credit history
    TradeInVehicleEvent.sendToServer(farmId, vehicleId, tradeInValue)

    return true
end

--[[
    Get trade-in item details from eligible list by index
    @param context - PurchaseContext instance
    @param index - Index in eligibleTradeIns list (1-based)
    @return item - Trade-in item details or nil
]]
function TradeInHandler.getItemByIndex(context, index)
    if index < 1 or index > #context.eligibleTradeIns then
        return nil
    end
    return context.eligibleTradeIns[index]
end
