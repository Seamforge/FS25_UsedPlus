--[[
    FS25_UsedPlus - Vehicle Info Box Extension

    v2.8.0: Adds Oil Level, Hydraulic Fluid, and Tire Condition to the vehicle info display
    (the box that appears bottom-right when pointing at a vehicle)

    Pattern from: InfoDisplayExtension, HirePurchasing

    NOTE: Hook is deferred until mission loads because Vehicle class isn't available
    during mod file parsing.
]]

VehicleInfoExtension = {}
VehicleInfoExtension.hooked = false

--[[
    Get color based on fluid level (red when low, green when full)
    @param level - Fluid level 0-1
    @return RGBA color table
]]
function VehicleInfoExtension.getLevelColor(level)
    -- Clamp level to 0-1
    level = math.max(0, math.min(1, level))

    -- Red (low) to Yellow (mid) to Green (full)
    local r, g, b
    if level < 0.5 then
        -- Red to Yellow (0-0.5)
        r = 1
        g = level * 2
        b = 0
    else
        -- Yellow to Green (0.5-1)
        r = 1 - ((level - 0.5) * 2)
        g = 1
        b = 0
    end

    return {r, g, b, 1}
end

--[[
    Format fluid level as percentage string
    @param level - Fluid level 0-1
    @return Formatted string like "75%"
]]
function VehicleInfoExtension.formatLevel(level)
    return string.format("%d%%", math.floor((level or 0) * 100))
end

--[[
    Show lease/finance deal info in the vehicle info box
    Pattern from: FS25_HirePurchasing VehicleExtension.lua
    @param vehicle - The vehicle object (self from Vehicle.showInfo)
    @param box - The info display box
]]
function VehicleInfoExtension.showFinanceInfo(vehicle, box)
    if g_financeManager == nil then return end

    local farmId = g_currentMission:getFarmId()

    -- Check for active lease
    if g_financeManager:hasActiveLease(vehicle) then
        local deal = g_financeManager:getLeaseDealForVehicle(vehicle)
        if deal then
            box:addLine(g_i18n:getText("usedplus_info_dealType"), g_i18n:getText("usedplus_info_leased"))
            if deal.monthlyPayment then
                box:addLine(g_i18n:getText("usedplus_lease_monthlyPayment"),
                    g_i18n:formatMoney(deal.monthlyPayment, 0, true, true))
            end
            local remaining = (deal.termMonths or 0) - (deal.monthsPaid or 0)
            box:addLine(g_i18n:getText("usedplus_info_monthsRemaining"), tostring(remaining))
        end
        return
    end

    -- Check for active finance
    if g_financeManager:hasActiveFinance(vehicle) then
        local deal = g_financeManager:getFinanceDealForVehicle(vehicle)
        if deal then
            box:addLine(g_i18n:getText("usedplus_info_dealType"), g_i18n:getText("usedplus_info_financed"))
            if deal.monthlyPayment then
                box:addLine(g_i18n:getText("usedplus_finance_monthlyPayment"),
                    g_i18n:formatMoney(deal.monthlyPayment, 0, true, true))
            end
            local remaining = (deal.termMonths or 0) - (deal.monthsPaid or 0)
            box:addLine(g_i18n:getText("usedplus_info_monthsRemaining"), tostring(remaining))
        end
    end
end

--[[
    Hook into Vehicle.showInfo to add our fluid levels and finance/lease info
    @param box - The info display box
]]
function VehicleInfoExtension:showInfo(box)
    -- Show lease/finance info (applies to all vehicles, not just those with maintenance spec)
    VehicleInfoExtension.showFinanceInfo(self, box)

    -- Get our maintenance specialization
    local spec = self.spec_usedPlusMaintenance
    if spec == nil then
        return
    end

    -- Spec exists - show the levels

    -- Oil Level
    if spec.oilLevel ~= nil then
        local level = spec.oilLevel
        local color = VehicleInfoExtension.getLevelColor(level)
        local isLow = level < 0.25

        box:addLine(
            g_i18n:getText("usedplus_info_oil_level"),
            VehicleInfoExtension.formatLevel(level),
            isLow,  -- Accentuate if critically low
            color
        )
    end

    -- Hydraulic Fluid Level
    if spec.hydraulicFluidLevel ~= nil then
        local level = spec.hydraulicFluidLevel
        local color = VehicleInfoExtension.getLevelColor(level)
        local isLow = level < 0.25

        box:addLine(
            g_i18n:getText("usedplus_info_hydraulic_level"),
            VehicleInfoExtension.formatLevel(level),
            isLow,
            color
        )
    end

    -- v2.8.0: Tire Condition (unified with UYT→Native fallback)
    -- Only show our native tire data when UYT isn't tracking this vehicle
    -- This prevents duplicate displays (RVB/UYT shows theirs, we show ours for unsupported)
    if ModCompatibility and ModCompatibility.getUnifiedTireCondition then
        local tireData = ModCompatibility.getUnifiedTireCondition(self)

        -- Only show our display if using NATIVE tracking (UYT not tracking this vehicle)
        -- This handles the "no free passes" case - vehicles UYT doesn't support
        if tireData and tireData.source == "Native" then
            local level = tireData.condition

            -- Only show if there's actual wear (condition < 1.0)
            -- or if vehicle has traveled significantly (shows we're tracking)
            local totalDistance = 0
            if spec.wheelDistances then
                for i = 1, #spec.wheelDistances do
                    totalDistance = totalDistance + (spec.wheelDistances[i] or 0)
                end
            end

            -- Show if: worn tires OR traveled more than 5km total
            if level < 1.0 or totalDistance > 5000 then
                local color = VehicleInfoExtension.getLevelColor(level)
                local isLow = level < 0.25

                box:addLine(
                    g_i18n:getText("usedplus_info_tire_condition"),
                    VehicleInfoExtension.formatLevel(level),
                    isLow,
                    color
                )
            end
        end
    end
end

--[[
    Initialize the hook - called when mission loads
    This is necessary because Vehicle class isn't available during mod file parsing
]]
function VehicleInfoExtension.init()
    if VehicleInfoExtension.hooked then
        return  -- Already hooked
    end

    if Vehicle ~= nil and Vehicle.showInfo ~= nil then
        Vehicle.showInfo = Utils.appendedFunction(Vehicle.showInfo, VehicleInfoExtension.showInfo)
        VehicleInfoExtension.hooked = true
        UsedPlus.logInfo("VehicleInfoExtension: Hooked into Vehicle.showInfo")
    else
        UsedPlus.logWarn("VehicleInfoExtension: Vehicle.showInfo not available for hooking")
    end
end

-- Try immediate hook (in case Vehicle is already available)
if Vehicle ~= nil and Vehicle.showInfo ~= nil then
    VehicleInfoExtension.init()
else
    -- Defer hook to mission load via Mission00.loadMission00Finished
    -- This is handled by main.lua calling VehicleInfoExtension.init()
    UsedPlus.logInfo("VehicleInfoExtension: Deferring hook until mission loads")
end

UsedPlus.logInfo("VehicleInfoExtension loaded")
