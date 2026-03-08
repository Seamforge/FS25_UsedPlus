--[[
    MaintenanceFluids.lua
    Oil, hydraulic fluid, and fuel leak systems

    Extracted from UsedPlusMaintenance.lua for modularity
]]

-- Ensure UsedPlusMaintenance table exists (modules load before main spec)
UsedPlusMaintenance = UsedPlusMaintenance or {}

--[[
    v2.5.2: Calculate fluid multiplier for malfunction CHANCE
    @param fluidLevel - Current fluid level (0.0-1.0)
    @param multiplierConfig - Config value for max multiplier effect
    @return number - Multiplier (1.0 = no effect, higher = more likely to malfunction)
]]
function UsedPlusMaintenance.getFluidChanceMultiplier(fluidLevel, multiplierConfig)
    local config = UsedPlusMaintenance.CONFIG

    -- Full fluid = no penalty (1.0x)
    -- Empty fluid = max penalty (1.0 + multiplierConfig)
    -- Example: At 20% fluid with multiplier 2.0: 1.0 + (0.8 * 2.0) = 2.6x chance
    local deficit = 1.0 - (fluidLevel or 1.0)
    local multiplier = 1.0 + (deficit * (multiplierConfig or 2.0))

    return multiplier
end

--[[
    v2.5.2: Calculate fluid multiplier for malfunction SEVERITY (duration/intensity)
    @param fluidLevel - Current fluid level (0.0-1.0)
    @param multiplierConfig - Config value for max severity multiplier
    @return number - Multiplier (1.0 = no effect, higher = longer/worse malfunctions)
]]
function UsedPlusMaintenance.getFluidSeverityMultiplier(fluidLevel, multiplierConfig)
    local config = UsedPlusMaintenance.CONFIG

    -- Same formula as chance, but typically with a lower multiplier
    -- so severity doesn't get TOO extreme
    local deficit = 1.0 - (fluidLevel or 1.0)
    local multiplier = 1.0 + (deficit * (multiplierConfig or 1.5))

    return multiplier
end

--[[
    v2.5.2: Get hydraulic fluid chance multiplier for a vehicle
    Convenience wrapper that reads vehicle spec and config
    @param vehicle - Vehicle to check
    @return number - Chance multiplier (1.0 = no effect)
]]
function UsedPlusMaintenance.getHydraulicFluidChanceMultiplier(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return 1.0 end

    local config = UsedPlusMaintenance.CONFIG
    local fluidLevel = spec.hydraulicFluidLevel or 1.0

    return UsedPlusMaintenance.getFluidChanceMultiplier(fluidLevel, config.hydraulicFluidChanceMultiplier)
end

--[[
    v2.5.2: Get hydraulic fluid severity multiplier for a vehicle
    @param vehicle - Vehicle to check
    @return number - Severity multiplier (1.0 = no effect)
]]
function UsedPlusMaintenance.getHydraulicFluidSeverityMultiplier(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return 1.0 end

    local config = UsedPlusMaintenance.CONFIG
    local fluidLevel = spec.hydraulicFluidLevel or 1.0

    return UsedPlusMaintenance.getFluidSeverityMultiplier(fluidLevel, config.hydraulicFluidSeverityMultiplier)
end

--[[
    v2.5.2: Get oil chance multiplier for a vehicle
    @param vehicle - Vehicle to check
    @return number - Chance multiplier (1.0 = no effect)
]]
function UsedPlusMaintenance.getOilChanceMultiplier(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return 1.0 end

    local config = UsedPlusMaintenance.CONFIG
    local oilLevel = spec.oilLevel or 1.0

    return UsedPlusMaintenance.getFluidChanceMultiplier(oilLevel, config.oilChanceMultiplier)
end

--[[
    v2.5.2: Get oil severity multiplier for a vehicle
    @param vehicle - Vehicle to check
    @return number - Severity multiplier (1.0 = no effect)
]]
function UsedPlusMaintenance.getOilSeverityMultiplier(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return 1.0 end

    local config = UsedPlusMaintenance.CONFIG
    local oilLevel = spec.oilLevel or 1.0

    return UsedPlusMaintenance.getFluidSeverityMultiplier(oilLevel, config.oilSeverityMultiplier)
end

--[[
    Update oil system: depletion, leak processing, damage
    Called every 1 second from periodic checks
]]
function UsedPlusMaintenance.updateOilSystem(vehicle, dt)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Only deplete oil when engine is running
    local motor = vehicle.spec_motorized
    if motor == nil or not motor.isMotorStarted then return end

    -- Base depletion rate (per second, converted from per hour)
    local baseRate = config.oilDepletionRatePerHour / 3600

    -- v2.8.0: Leak multiplier - only apply if malfunctions enabled
    local leakMult = 1.0
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if spec.hasOilLeak and malfunctionsEnabled then
        if spec.oilLeakSeverity == 1 then
            leakMult = config.oilLeakMinorMult
        elseif spec.oilLeakSeverity == 2 then
            leakMult = config.oilLeakModerateMult
        else
            leakMult = config.oilLeakSevereMult
        end
    end

    -- v2.15.1: Apply user-configurable drain rate multiplier
    local drainMult = UsedPlusSettings and UsedPlusSettings:get("fluidDrainRateMultiplier") or 1.0

    -- Apply depletion
    local depletion = baseRate * leakMult * drainMult * (dt / 1000)  -- dt is in ms
    spec.oilLevel = math.max(0, (spec.oilLevel or 1.0) - depletion)

    -- Check for low oil damage
    if spec.oilLevel <= config.oilCriticalThreshold then
        -- Track that we ran low (for permanent damage on failure)
        spec.wasLowOil = true

        -- Apply accelerated engine wear
        local wearAmount = 0.001 * config.oilLowDamageMultiplier
        spec.engineReliability = math.max(0.1, spec.engineReliability - wearAmount)

        -- Critical warning
        if not spec.hasShownOilCriticalWarning then
            spec.hasShownOilCriticalWarning = true
            UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_oilCritical"))
        end
    elseif spec.oilLevel <= config.oilWarnThreshold then
        -- Low warning
        if not spec.hasShownOilWarnWarning then
            spec.hasShownOilWarnWarning = true
            UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_oilLow"))
        end
    end

    -- Leak warning
    if spec.hasOilLeak and not spec.hasShownOilLeakWarning then
        spec.hasShownOilLeakWarning = true
        local severityText = spec.oilLeakSeverity == 1 and "minor" or
                            (spec.oilLeakSeverity == 2 and "moderate" or "severe")
        UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_oilLeak"))
    end
end

--[[
    Apply permanent engine damage when failure occurs while oil was low
    Called when engine stall or failure happens
]]
function UsedPlusMaintenance.applyOilDamageOnFailure(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    if spec.wasLowOil and spec.oilLevel <= UsedPlusMaintenance.CONFIG.oilCriticalThreshold then
        local damage = UsedPlusMaintenance.CONFIG.oilPermanentDamageOnFailure
        spec.engineReliabilityCeiling = math.max(
            UsedPlusMaintenance.CONFIG.minReliabilityCeiling,
            (spec.engineReliabilityCeiling or 1.0) - damage
        )

        -- Cap current reliability to new ceiling
        spec.engineReliability = math.min(spec.engineReliability, spec.engineReliabilityCeiling)

        UsedPlus.logDebug(string.format("Permanent engine damage! Ceiling now %.0f%% for %s",
            spec.engineReliabilityCeiling * 100, vehicle:getName()))

        UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_engineDamage"))
    end
end

--[[
    Update hydraulic fluid system: depletion, leak processing, damage
    Called every 1 second from periodic checks
]]
function UsedPlusMaintenance.updateHydraulicFluidSystem(vehicle, dt)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Only deplete hydraulic fluid when doing hydraulic actions
    -- Check if any implement is raised/lowered
    local isUsingHydraulics = false

    -- Check attacherJoints for raised implements
    if vehicle.spec_attacherJoints then
        for _, joint in pairs(vehicle.spec_attacherJoints.attacherJoints or {}) do
            if joint.moveAlpha and joint.moveAlpha > 0 and joint.moveAlpha < 1 then
                isUsingHydraulics = true
                break
            end
        end
    end

    -- Check for cylinder movement
    if vehicle.spec_cylindered then
        for _, movingTool in pairs(vehicle.spec_cylindered.movingTools or {}) do
            if movingTool.isActive then
                isUsingHydraulics = true
                break
            end
        end
    end

    -- v2.8.0: Leak only depletes if malfunctions enabled
    local leakMult = 1.0
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if spec.hasHydraulicLeak and malfunctionsEnabled then
        if spec.hydraulicLeakSeverity == 1 then
            leakMult = config.hydraulicLeakMinorMult
        elseif spec.hydraulicLeakSeverity == 2 then
            leakMult = config.hydraulicLeakModerateMult
        else
            leakMult = config.hydraulicLeakSevereMult
        end
    end

    -- v2.15.1: Apply user-configurable drain rate multiplier
    local drainMult = UsedPlusSettings and UsedPlusSettings:get("fluidDrainRateMultiplier") or 1.0

    -- Apply depletion
    local depletion = 0
    if isUsingHydraulics then
        depletion = config.hydraulicFluidDepletionPerAction * leakMult * drainMult
    elseif spec.hasHydraulicLeak and malfunctionsEnabled then
        -- Passive leak depletion (slower than active use)
        depletion = config.hydraulicFluidDepletionPerAction * 0.1 * leakMult * drainMult
    end

    if depletion > 0 then
        spec.hydraulicFluidLevel = math.max(0, (spec.hydraulicFluidLevel or 1.0) - depletion)
    end

    -- Check for low hydraulic fluid damage
    if spec.hydraulicFluidLevel <= config.hydraulicFluidCriticalThreshold then
        spec.wasLowHydraulicFluid = true

        -- Apply accelerated hydraulic wear
        local wearAmount = 0.001 * config.hydraulicFluidLowDamageMultiplier
        spec.hydraulicReliability = math.max(0.1, spec.hydraulicReliability - wearAmount)

        if not spec.hasShownHydraulicCriticalWarning then
            spec.hasShownHydraulicCriticalWarning = true
            UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_hydraulicCritical"))
        end
    elseif spec.hydraulicFluidLevel <= config.hydraulicFluidWarnThreshold then
        if not spec.hasShownHydraulicWarnWarning then
            spec.hasShownHydraulicWarnWarning = true
            UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_hydraulicLow"))
        end
    end

    -- Leak warning
    if spec.hasHydraulicLeak and not spec.hasShownHydraulicLeakWarning then
        spec.hasShownHydraulicLeakWarning = true
        UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_hydraulicLeak"))
    end
end

--[[
    Apply permanent hydraulic damage when failure occurs while fluid was low
]]
function UsedPlusMaintenance.applyHydraulicDamageOnFailure(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    if spec.wasLowHydraulicFluid and spec.hydraulicFluidLevel <= UsedPlusMaintenance.CONFIG.hydraulicFluidCriticalThreshold then
        local damage = UsedPlusMaintenance.CONFIG.hydraulicFluidPermanentDamageOnFailure
        spec.hydraulicReliabilityCeiling = math.max(
            UsedPlusMaintenance.CONFIG.minReliabilityCeiling,
            (spec.hydraulicReliabilityCeiling or 1.0) - damage
        )

        spec.hydraulicReliability = math.min(spec.hydraulicReliability, spec.hydraulicReliabilityCeiling)

        UsedPlus.logDebug(string.format("Permanent hydraulic damage! Ceiling now %.0f%% for %s",
            spec.hydraulicReliabilityCeiling * 100, vehicle:getName()))

        UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_hydraulicDamage"))
    end
end

--[[
    Check for new leaks (oil, hydraulic, fuel)
    Called every 1 second from periodic checks
]]
function UsedPlusMaintenance.checkForNewLeaks(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Check for new oil leak
    if config.enableOilLeak and not spec.hasOilLeak then
        if spec.engineReliability < config.oilLeakThreshold then
            local reliabilityFactor = 1 - (spec.engineReliability / config.oilLeakThreshold)
            local chance = config.oilLeakBaseChance * reliabilityFactor

            if math.random() < chance then
                spec.hasOilLeak = true
                -- Determine severity based on reliability
                if spec.engineReliability < 0.15 then
                    spec.oilLeakSeverity = 3  -- Severe
                elseif spec.engineReliability < 0.25 then
                    spec.oilLeakSeverity = 2  -- Moderate
                else
                    spec.oilLeakSeverity = 1  -- Minor
                end
                UsedPlus.logDebug(string.format("Oil leak (severity %d) triggered for %s",
                    spec.oilLeakSeverity, vehicle:getName()))
            end
        end
    end

    -- Check for new hydraulic leak
    if config.enableHydraulicLeak and not spec.hasHydraulicLeak then
        if spec.hydraulicReliability < config.hydraulicLeakThreshold then
            local reliabilityFactor = 1 - (spec.hydraulicReliability / config.hydraulicLeakThreshold)
            local chance = config.hydraulicLeakBaseChance * reliabilityFactor

            if math.random() < chance then
                spec.hasHydraulicLeak = true
                if spec.hydraulicReliability < 0.15 then
                    spec.hydraulicLeakSeverity = 3
                elseif spec.hydraulicReliability < 0.25 then
                    spec.hydraulicLeakSeverity = 2
                else
                    spec.hydraulicLeakSeverity = 1
                end
                UsedPlus.logDebug(string.format("Hydraulic leak (severity %d) triggered for %s",
                    spec.hydraulicLeakSeverity, vehicle:getName()))
            end
        end
    end

    -- Check for new fuel leak
    if config.enableFuelLeak and not spec.hasFuelLeak then
        if spec.engineReliability < config.fuelLeakThreshold then
            local reliabilityFactor = 1 - (spec.engineReliability / config.fuelLeakThreshold)
            local chance = config.fuelLeakBaseChance * reliabilityFactor

            if math.random() < chance then
                spec.hasFuelLeak = true
                -- Random multiplier between min and max
                spec.fuelLeakMultiplier = config.fuelLeakMinMult +
                    (math.random() * (config.fuelLeakMaxMult - config.fuelLeakMinMult))

                if not spec.hasShownFuelLeakWarning then
                    spec.hasShownFuelLeakWarning = true
                    UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_fuelLeak"))
                end

                UsedPlus.logDebug(string.format("Fuel leak (%.1fx consumption) triggered for %s",
                    spec.fuelLeakMultiplier, vehicle:getName()))
            end
        end
    end
end

--[[
    Get fuel consumption multiplier (for fuel leak effect)
    Returns 1.0 normally, or higher if fuel leak active
]]
function UsedPlusMaintenance.getFuelConsumptionMultiplier(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return 1.0 end

    -- v2.8.0: Respect malfunctions setting - if disabled, no fuel leak penalty
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if spec.hasFuelLeak and malfunctionsEnabled then
        return spec.fuelLeakMultiplier or 1.0
    end

    return 1.0
end

--[[
    v1.7.0: Process fuel leak - drain fuel from tank
    Called every 1 second from periodic checks
    Drains fuel at a rate based on the leak multiplier
]]
function UsedPlusMaintenance.processFuelLeak(vehicle, dt)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    if not spec.hasFuelLeak then return end

    -- v2.8.0: Respect malfunctions setting - if disabled, no fuel leak drain
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Only leak when engine is running (fuel system pressurized)
    local motor = vehicle.spec_motorized
    if motor == nil or not motor.isMotorStarted then return end

    -- Get fuel fill unit
    local fuelFillUnitIndex = nil
    if vehicle.getConsumerFillUnitIndex then
        fuelFillUnitIndex = vehicle:getConsumerFillUnitIndex(FillType.DIESEL)
        -- Also check methane if no diesel
        if fuelFillUnitIndex == nil then
            fuelFillUnitIndex = vehicle:getConsumerFillUnitIndex(FillType.METHANE)
        end
    end

    if fuelFillUnitIndex == nil then return end

    -- Calculate leak rate (liters per second based on multiplier)
    -- Base leak: ~0.5 L/s, scaled by multiplier (1.5x to 3x)
    local baseFuelLeakRate = config.fuelLeakBaseDrainRate or 0.5
    local leakRate = baseFuelLeakRate * (spec.fuelLeakMultiplier - 1.0)

    -- dt is in seconds (1 second from periodic check)
    local fuelDrained = leakRate * 1.0  -- 1 second interval

    if fuelDrained > 0 then
        local currentFuel = vehicle:getFillUnitFillLevel(fuelFillUnitIndex)

        if currentFuel > 0 then
            -- Drain fuel using addFillUnitFillLevel with negative amount
            vehicle:addFillUnitFillLevel(
                vehicle:getOwnerFarmId(),
                fuelFillUnitIndex,
                -fuelDrained,
                vehicle:getFillUnitFillType(fuelFillUnitIndex),
                ToolType.UNDEFINED,
                nil
            )

            UsedPlus.logDebug(string.format("Fuel leak: drained %.2f L from %s (mult %.1fx)",
                fuelDrained, vehicle:getName(), spec.fuelLeakMultiplier))
        end
    end
end

--[[
    Refill oil (full change or top up)
    @param isFullChange true for full change (resets wasLowOil), false for top up
]]
function UsedPlusMaintenance.refillOil(vehicle, isFullChange)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    spec.oilLevel = 1.0
    spec.hasOilLeak = false
    spec.oilLeakSeverity = 0
    spec.hasShownOilWarnWarning = false
    spec.hasShownOilCriticalWarning = false
    spec.hasShownOilLeakWarning = false

    if isFullChange then
        spec.wasLowOil = false
    end

    UsedPlus.logDebug(string.format("Oil %s for %s",
        isFullChange and "changed" or "topped up", vehicle:getName()))
end

--[[
    Refill hydraulic fluid (full change or top up)
    @param isFullChange true for full change (resets wasLowHydraulicFluid), false for top up
]]
function UsedPlusMaintenance.refillHydraulicFluid(vehicle, isFullChange)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    spec.hydraulicFluidLevel = 1.0
    spec.hasHydraulicLeak = false
    spec.hydraulicLeakSeverity = 0
    spec.hasShownHydraulicWarnWarning = false
    spec.hasShownHydraulicCriticalWarning = false
    spec.hasShownHydraulicLeakWarning = false

    if isFullChange then
        spec.wasLowHydraulicFluid = false
    end

    UsedPlus.logDebug(string.format("Hydraulic fluid %s for %s",
        isFullChange and "changed" or "topped up", vehicle:getName()))
end

--[[
    Fix fuel leak (repair required)
]]
function UsedPlusMaintenance.repairFuelLeak(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    spec.hasFuelLeak = false
    spec.fuelLeakMultiplier = 1.0
    spec.hasShownFuelLeakWarning = false

    if vehicle.raiseDirtyFlags and spec.dirtyFlag then
        vehicle:raiseDirtyFlags(spec.dirtyFlag)
    end

    UsedPlus.logDebug(string.format("Fuel leak repaired for %s", vehicle:getName()))
end

UsedPlus.logDebug("MaintenanceFluids module loaded")
