--[[
    MaintenanceSpeed.lua
    Speed governance and limitation functions

    Extracted from UsedPlusMaintenance.lua for modularity
]]

-- Ensure UsedPlusMaintenance table exists (modules load before main spec)
UsedPlusMaintenance = UsedPlusMaintenance or {}

--[[
    Calculate speed limit factor based on reliability, damage, and conditions
    Updates spec.maxSpeedFactor which is used by getCanMotorRun speed governor
    Called every 1 second from periodic checks
]]
function UsedPlusMaintenance.calculateSpeedLimit(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Get current damage
    local damage = 0
    if vehicle.getDamageAmount then
        damage = vehicle:getDamageAmount() or 0
    end

    -- v1.8.0: Use ModCompatibility to get engine reliability
    -- If RVB is installed, this returns health derived from RVB parts
    -- Otherwise, returns our native engineReliability
    -- This enables "symptoms before failure" - we provide gradual degradation
    -- leading up to RVB's final failure event
    local engineReliability = ModCompatibility.getEngineReliability(vehicle)

    -- Calculate speed factor from RELIABILITY (applies even at 0% damage!)
    -- 100% reliability = 100% speed
    -- 50% reliability = 70% speed
    -- 10% reliability = 46% speed
    -- 0% reliability = 40% speed (absolute minimum before RVB's 7km/h kicks in)
    local reliabilitySpeedFactor = 0.4 + (engineReliability * 0.6)

    -- Damage ALSO reduces speed (stacks with reliability)
    local maxReduction = config.speedDegradationMax
    local damageSpeedFactor = 1 - (damage * maxReduction)

    -- v1.7.0: Flat tire severely limits speed
    -- v1.8.0: Skip flat tire logic if UYT/RVB handles tires
    -- v2.8.0: Also respect malfunctions setting
    local flatTireSpeedFactor = 1.0
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if spec.hasFlatTire and config.enableFlatTire and malfunctionsEnabled and not ModCompatibility.shouldDeferTireFailure() then
        flatTireSpeedFactor = config.flatTireSpeedReduction  -- 0.5 = 50% max speed
    end

    -- v2.5.0: Implement drag reduces speed
    local implementDragFactor = 1.0
    if spec.implementDragActive and config.enableImplementDrag then
        -- Check if any implement is actually lowered
        local hasLoweredImpl = false
        if vehicle.getAttachedImplements then
            local implements = vehicle:getAttachedImplements()
            if implements then
                for _, impl in pairs(implements) do
                    local implement = impl.object
                    if implement and implement.getIsLowered and implement:getIsLowered() then
                        hasLoweredImpl = true
                        break
                    end
                end
            end
        end
        if hasLoweredImpl then
            implementDragFactor = config.implementDragSpeedMult  -- 0.6 = 60% max speed
        else
            -- Implement was raised, clear the drag effect
            spec.implementDragActive = false
        end
    end

    -- Combined factor (multiplicative stacking)
    local finalFactor = reliabilitySpeedFactor * damageSpeedFactor * flatTireSpeedFactor * implementDragFactor
    finalFactor = math.max(finalFactor, 0.2)  -- Never below 20% speed (even with flat)

    -- v2.5.0: RUNAWAY ENGINE - Overrides ALL reductions!
    -- When runaway is active, the governor has failed - vehicle accelerates beyond normal max
    if spec.runawayActive and config.enableRunaway then
        local currentTime = g_currentMission.time or 0
        local elapsed = currentTime - (spec.runawayStartTime or 0)

        -- Ramp up speed boost over time (10 seconds to full)
        local rampProgress = math.min(elapsed / config.runawaySpeedRampTime, 1.0)
        local speedBoost = 1.0 + ((config.runawaySpeedBoostMax - 1.0) * rampProgress)

        -- OVERRIDE normal speed factor - vehicle goes FASTER than normal max!
        finalFactor = speedBoost

        UsedPlus.logTrace(string.format("RUNAWAY: speed boost %.1f%% (ramp %.1f%%)",
            speedBoost * 100, rampProgress * 100))
    end

    -- Store for use by getCanMotorRun speed governor
    spec.maxSpeedFactor = finalFactor

    -- Calculate actual limited speed for display/warnings
    local baseMaxSpeed = 50
    if vehicle.spec_drivable and vehicle.spec_drivable.cruiseControl then
        baseMaxSpeed = vehicle.spec_drivable.cruiseControl.maxSpeed or 50
    end
    spec.currentMaxSpeed = baseMaxSpeed * finalFactor

    -- Only show warnings if there's actual degradation (below 95%)
    if finalFactor >= 0.95 then
        spec.hasShownSpeedWarning = false
        spec.speedWarningTimer = 0
        return
    end

    -- Show warning when speed degradation is first noticed
    -- v1.6.0: Only show if player is controlling this vehicle
    if not spec.hasShownSpeedWarning and UsedPlusMaintenance.shouldShowWarning(vehicle) then
        local speedPercent = math.floor(finalFactor * 100)
        if not g_dedicatedServer then
            g_currentMission:showBlinkingWarning(
                string.format(g_i18n:getText("usedPlus_speedDegraded") or "Engine struggling - max speed reduced to %d%%!", speedPercent),
                4000
            )
        end
        spec.hasShownSpeedWarning = true
        spec.speedWarningTimer = 0
        UsedPlus.logDebug(string.format("Speed degradation: %d%% (max %d km/h)", speedPercent, math.floor(spec.currentMaxSpeed)))
    end
end

--[[
    v1.5.1: Placeholder for per-frame speed enforcement (not needed with governor approach)
    The actual enforcement now happens in getCanMotorRun() which is called every frame
]]
function UsedPlusMaintenance.enforceSpeedLimit(vehicle, dt)
    -- Speed enforcement is now handled by the governor in getCanMotorRun()
    -- This function exists for future enhancements (e.g., HUD display updates)
end

UsedPlus.logDebug("MaintenanceSpeed module loaded")
