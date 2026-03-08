--[[
    CollateralUtils.lua
    Utility functions for managing loan collateral (pledged vehicles/equipment)

    Handles:
    - Identifying pledgeable assets
    - Auto-selecting collateral based on loan amount
    - Checking if vehicles are pledged
    - Calculating collateral values
]]

CollateralUtils = {}

-- Loan-to-Value ratio (bank won't lend 100% of collateral value)
CollateralUtils.LTV_RATIO = 0.75  -- Can borrow up to 75% of collateral value

-- Minimum vehicle value to be considered as collateral
CollateralUtils.MIN_VEHICLE_VALUE = 5000

--[[
    Get the current market value of a vehicle
    Uses depreciation based on operating hours and condition

    @param vehicle - The vehicle object
    @return number - Current market value
]]
function CollateralUtils.getVehicleValue(vehicle)
    if not vehicle then return 0 end

    -- Get base price from store item
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    if not storeItem then return 0 end

    local basePrice = storeItem.price or 0
    if basePrice <= 0 then return 0 end

    -- Get operating hours
    local operatingHours = 0
    if vehicle.getOperatingTime then
        operatingHours = vehicle:getOperatingTime() / (1000 * 60 * 60)  -- Convert ms to hours
    end

    -- Get damage/wear
    local damage = 0
    if vehicle.getDamageAmount then
        damage = vehicle:getDamageAmount()
    elseif vehicle.damage then
        damage = vehicle.damage
    end

    -- Calculate depreciation
    local hourlyDepreciation = 0
    local conditionDepreciation = 0

    -- Use DepreciationCalculations if available
    if DepreciationCalculations and DepreciationCalculations.calculateUsedPrice then
        local usedPrice = DepreciationCalculations.calculateUsedPrice(basePrice, operatingHours, damage)
        return math.max(0, usedPrice)
    end

    -- Fallback depreciation calculation
    -- Hours: ~2% per 100 hours, capped at 50%
    hourlyDepreciation = math.min(0.50, operatingHours * 0.0002)

    -- Condition: damage directly reduces value
    conditionDepreciation = damage * 0.4  -- 40% value loss at 100% damage

    local totalDepreciation = math.min(0.80, hourlyDepreciation + conditionDepreciation)
    local currentValue = basePrice * (1 - totalDepreciation)

    return math.max(0, math.floor(currentValue))
end

--[[
    Get all vehicles that can be pledged as collateral for a farm
    Excludes:
    - Leased vehicles
    - Already-pledged vehicles
    - Vehicles under active finance (the financed item IS the collateral)
    - Vehicles worth less than minimum threshold

    @param farmId - The farm ID
    @return table - Array of {vehicle, value, name, configFile, vehicleId}
]]
function CollateralUtils.getPledgeableVehicles(farmId)
    local pledgeable = {}

    if not g_currentMission or not g_currentMission.vehicleSystem then
        return pledgeable
    end

    -- Get list of vehicles already pledged or under finance
    local excludedVehicles = CollateralUtils.getExcludedVehicleIds(farmId)

    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        -- Must be owned by this farm
        if vehicle.ownerFarmId == farmId then
            -- Check if it's a real vehicle (not a pallet or other object)
            local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
            if storeItem and storeItem.price and storeItem.price > 0 then

                -- Get vehicle identifier
                local vehicleId = CollateralUtils.getVehicleIdentifier(vehicle)

                -- Skip if excluded (leased, financed, or already pledged)
                if not excludedVehicles[vehicleId] then
                    local value = CollateralUtils.getVehicleValue(vehicle)

                    -- Only include if above minimum value
                    if value >= CollateralUtils.MIN_VEHICLE_VALUE then
                        table.insert(pledgeable, {
                            vehicle = vehicle,
                            value = value,
                            name = vehicle:getName() or storeItem.name or g_i18n:getText("usedplus_common_unknownVehicle"),
                            configFile = vehicle.configFileName,
                            vehicleId = vehicleId,
                            objectId = NetworkUtil.getObjectId(vehicle)
                        })
                    end
                end
            end
        end
    end

    -- Sort by value descending (highest value first)
    table.sort(pledgeable, function(a, b) return a.value > b.value end)

    return pledgeable
end

--[[
    Get a unique identifier for a vehicle
    Uses multiple properties for robustness

    @param vehicle - The vehicle object
    @return string - Unique identifier
]]
function CollateralUtils.getVehicleIdentifier(vehicle)
    if not vehicle then return "" end

    -- Prefer the vehicle's internal ID if available
    if vehicle.id then
        return "id:" .. tostring(vehicle.id)
    end

    -- Fall back to network object ID + config
    local objectId = NetworkUtil.getObjectId(vehicle) or 0
    local configFile = vehicle.configFileName or ""

    return string.format("obj:%d:%s", objectId, configFile)
end

--[[
    Get set of vehicle IDs that cannot be pledged
    (already financed, leased, or pledged to another loan)

    @param farmId - The farm ID
    @return table - Set of excluded vehicle identifiers
]]
function CollateralUtils.getExcludedVehicleIds(farmId)
    local excluded = {}

    if not g_financeManager then
        return excluded
    end

    local deals = g_financeManager:getDealsForFarm(farmId)
    if not deals then
        return excluded
    end

    for _, deal in pairs(deals) do
        if deal.status == "active" then
            -- Exclude the financed/leased vehicle itself
            if deal.itemType == "vehicle" and deal.objectId then
                local vehicle = NetworkUtil.getObject(deal.objectId)
                if vehicle then
                    local vehicleId = CollateralUtils.getVehicleIdentifier(vehicle)
                    excluded[vehicleId] = true
                end
            end

            -- Exclude vehicles pledged as collateral to loans
            if deal.collateralItems then
                for _, item in ipairs(deal.collateralItems) do
                    if item.vehicleId then
                        excluded[item.vehicleId] = true
                    end
                end
            end
        end
    end

    -- Also check lease deals
    if g_financeManager.leaseDeals then
        for _, deal in pairs(g_financeManager.leaseDeals[farmId] or {}) do
            if deal.status == "active" and deal.objectId then
                local vehicle = NetworkUtil.getObject(deal.objectId)
                if vehicle then
                    local vehicleId = CollateralUtils.getVehicleIdentifier(vehicle)
                    excluded[vehicleId] = true
                end
            end
        end
    end

    return excluded
end


--[[
    Calculate total land value for a farm

    @param farmId - The farm ID
    @return number - Total land value
]]
function CollateralUtils.calculateLandValue(farmId)
    local totalValue = 0

    if g_farmlandManager then
        local farmlands = g_farmlandManager:getOwnedFarmlandIdsByFarmId(farmId)
        if farmlands then
            for _, fieldId in ipairs(farmlands) do
                local farmland = g_farmlandManager:getFarmlandById(fieldId)
                if farmland then
                    totalValue = totalValue + (farmland.price or 0)
                end
            end
        end
    end

    return totalValue
end

--[[
    Calculate total existing debt for a farm

    @param farmId - The farm ID
    @return number - Total outstanding debt
]]
function CollateralUtils.calculateExistingDebt(farmId)
    local totalDebt = 0

    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(farmId)
        if deals then
            for _, deal in pairs(deals) do
                if deal.status == "active" then
                    totalDebt = totalDebt + (deal.currentBalance or 0)
                end
            end
        end
    end

    return totalDebt
end

--[[
    Check if a specific vehicle is pledged as collateral to any active loan

    @param vehicle - The vehicle object
    @return boolean - True if pledged
    @return table|nil - The deal it's pledged to (if any)
]]
function CollateralUtils.isVehiclePledged(vehicle)
    if not vehicle or not g_financeManager then
        return false, nil
    end

    local vehicleId = CollateralUtils.getVehicleIdentifier(vehicle)
    local farmId = vehicle.ownerFarmId

    local deals = g_financeManager:getDealsForFarm(farmId)
    if not deals then
        return false, nil
    end

    for _, deal in pairs(deals) do
        if deal.status == "active" and deal.collateralItems then
            for _, item in ipairs(deal.collateralItems) do
                if item.vehicleId == vehicleId then
                    return true, deal
                end
            end
        end
    end

    return false, nil
end

--[[
    Find a pledged vehicle by its stored identifiers
    Used during repossession

    @param collateralItem - The stored collateral item data
    @param farmId - The farm ID
    @return vehicle|nil - The vehicle object if found
]]
function CollateralUtils.findPledgedVehicle(collateralItem, farmId)
    if not collateralItem or not g_currentMission then
        return nil
    end

    -- Try by objectId first (most reliable if still valid)
    if collateralItem.objectId then
        local vehicle = NetworkUtil.getObject(collateralItem.objectId)
        if vehicle and vehicle.ownerFarmId == farmId then
            return vehicle
        end
    end

    -- Try by vehicleId
    if collateralItem.vehicleId then
        for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
            if vehicle.ownerFarmId == farmId then
                local currentId = CollateralUtils.getVehicleIdentifier(vehicle)
                if currentId == collateralItem.vehicleId then
                    return vehicle
                end
            end
        end
    end

    -- Last resort: match by configFile and name
    if collateralItem.configFile then
        for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
            if vehicle.ownerFarmId == farmId and
               vehicle.configFileName == collateralItem.configFile then
                local vehicleName = vehicle:getName() or ""
                if vehicleName == collateralItem.name then
                    return vehicle
                end
            end
        end
    end

    return nil
end

--[[
    Format collateral summary for display

    @param collateralItems - Array of collateral items
    @return string - Formatted summary (e.g., "3 vehicles worth $250,000")
]]
function CollateralUtils.formatCollateralSummary(collateralItems)
    if not collateralItems or #collateralItems == 0 then
        return "No collateral pledged"
    end

    local count = #collateralItems
    local totalValue = 0

    for _, item in ipairs(collateralItems) do
        totalValue = totalValue + (item.value or 0)
    end

    local vehicleWord = count == 1 and "vehicle" or "vehicles"
    return string.format("%d %s worth %s",
        count,
        vehicleWord,
        g_i18n:formatMoney(totalValue, 0, true, true))
end

--[[
    Get a detailed list of collateral items for display

    @param collateralItems - Array of collateral items
    @return table - Array of formatted strings
]]
function CollateralUtils.getCollateralDetailList(collateralItems)
    local details = {}

    if not collateralItems then
        return details
    end

    for _, item in ipairs(collateralItems) do
        local line = string.format("%s - %s",
            item.name or "Unknown",
            g_i18n:formatMoney(item.value or 0, 0, true, true))
        table.insert(details, line)
    end

    return details
end

-- Register globally
if g_modManager then
    UsedPlus.logDebug("CollateralUtils loaded")
end
