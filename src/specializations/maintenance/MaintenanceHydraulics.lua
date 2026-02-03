--[[
    MaintenanceHydraulics.lua
    Hydraulic surge, runaway, implement stuck, and implement malfunction functions

    Extracted from UsedPlusMaintenance.lua for modularity
]]

-- Ensure UsedPlusMaintenance table exists (modules load before main spec)
UsedPlusMaintenance = UsedPlusMaintenance or {}

--[[
    v2.4.0: Check for hydraulic surge event (time-limited hard steering pull)
    Called every 1 second from onUpdate periodic checks
]]
function UsedPlusMaintenance.checkHydraulicSurge(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if malfunctions are enabled
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then return end

    local config = UsedPlusMaintenance.CONFIG
    local currentTime = g_currentMission.time or 0

    -- Don't trigger if disabled
    if not config.enableHydraulicSurge then return end

    -- v2.8.0: Check global malfunction cooldown (prevents cascade failures)
    if UsedPlusMaintenance.isInGlobalCooldown(vehicle) then return end

    -- Don't trigger new surge if one is already active
    if spec.hydraulicSurgeActive then return end

    -- Don't trigger during cooldown
    if currentTime < (spec.hydraulicSurgeCooldownEnd or 0) then return end

    -- Only trigger at meaningful speeds (not crawling around the farm)
    local speed = 0
    if vehicle.getLastSpeed then
        speed = vehicle:getLastSpeed()
    end
    if speed < config.hydraulicSurgeMinSpeed then return end

    -- Get hydraulic reliability
    local hydraulicReliability = ModCompatibility.getHydraulicReliability(vehicle)

    -- Only trigger below threshold
    if hydraulicReliability >= config.hydraulicSurgeThreshold then return end

    -- Calculate chance based on reliability (worse reliability = higher chance)
    local reliabilityFactor = (config.hydraulicSurgeThreshold - hydraulicReliability) / config.hydraulicSurgeThreshold
    local baseChance = config.hydraulicSurgeBaseChance * reliabilityFactor * 3  -- Scales up to 1.5% at 0% reliability

    -- v2.5.2: Apply fluid multiplier (low fluid = even higher chance)
    local fluidMultiplier = UsedPlusMaintenance.getHydraulicFluidChanceMultiplier(vehicle)
    local chance = baseChance * fluidMultiplier

    if math.random() < chance then
        -- TRIGGER SURGE!
        spec.hydraulicSurgeActive = true
        local baseDuration = math.random(config.hydraulicSurgeDurationMin, config.hydraulicSurgeDurationMax)

        -- v2.5.2: Apply severity multiplier to duration (low fluid = longer surges)
        local severityMultiplier = UsedPlusMaintenance.getHydraulicFluidSeverityMultiplier(vehicle)
        local duration = math.floor(baseDuration * severityMultiplier)

        spec.hydraulicSurgeEndTime = currentTime + duration
        spec.hydraulicSurgeFadeStartTime = spec.hydraulicSurgeEndTime - config.hydraulicSurgeFadeTime
        spec.hydraulicSurgeDirection = math.random() < 0.5 and -1 or 1

        -- v2.8.0: Record malfunction time for global cooldown
        UsedPlusMaintenance.recordMalfunctionTime(vehicle)

        -- Show red popup warning (consistent with other malfunctions)
        local directionText = spec.hydraulicSurgeDirection < 0 and
            (g_i18n:getText("usedPlus_directionLeft") or "left") or
            (g_i18n:getText("usedPlus_directionRight") or "right")

        UsedPlusMaintenance.showWarning(vehicle,
            string.format(g_i18n:getText("usedplus_warning_hydraulicSurge") or "POWER STEERING LOSS - Vehicle pulling %s!", directionText)
        )

        UsedPlus.logDebug(string.format("Hydraulic surge triggered on %s (direction=%s, duration=%dms, reliability=%.1f%%)",
            vehicle:getName(), directionText, duration, hydraulicReliability * 100))
    end
end

--[[
    v2.5.0: RUNAWAY ENGINE - Check if conditions are met to trigger runaway
    Requires BOTH oil AND hydraulic fluid critically low (<10%)
    This simulates governor failure from lack of lubrication + hydraulic pressure
]]
function UsedPlusMaintenance.checkRunawayCondition(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if malfunctions are enabled
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Don't trigger if disabled
    if not config.enableRunaway then return end

    -- v2.8.0: Check global malfunction cooldown (prevents cascade failures)
    if UsedPlusMaintenance.isInGlobalCooldown(vehicle) then return end

    -- Don't trigger if already in runaway
    if spec.runawayActive then return end

    -- Need to be moving above minimum speed
    local speed = 0
    if vehicle.getLastSpeed then
        speed = vehicle:getLastSpeed()
    end
    if speed < config.runawayMinSpeed then return end

    -- Check if BOTH fluids are critically low
    local oilLevel = spec.oilLevel or 1.0
    local hydraulicLevel = spec.hydraulicFluidLevel or 1.0

    local oilCritical = oilLevel < config.runawayOilThreshold
    local hydraulicCritical = hydraulicLevel < config.runawayHydraulicThreshold

    if oilCritical and hydraulicCritical then
        -- TRIGGER RUNAWAY!
        spec.runawayActive = true
        spec.runawayStartTime = g_currentMission.time or 0
        spec.runawayPreviousSpeed = speed
        spec.runawayPreviousDamage = vehicle:getVehicleDamage() or 0

        -- v2.8.0: Record malfunction time for global cooldown
        UsedPlusMaintenance.recordMalfunctionTime(vehicle)

        UsedPlusMaintenance.showWarning(vehicle,
            g_i18n:getText("usedplus_warning_runaway") or
            "ENGINE RUNAWAY! Governor failure - TURN OFF ENGINE!",
            5000, "runaway")

        UsedPlus.logDebug(string.format("RUNAWAY triggered on %s (oil=%.1f%%, hydraulic=%.1f%%, speed=%.1f km/h)",
            vehicle:getName(), oilLevel * 100, hydraulicLevel * 100, speed))
    end
end

--[[
    v2.5.0: Update runaway state per-frame
    Checks for END conditions: engine off, crash detected, fluids restored
    Called every frame when runaway is active
]]
function UsedPlusMaintenance.updateRunawayState(vehicle, dt)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end
    if not spec.runawayActive then return end

    local config = UsedPlusMaintenance.CONFIG
    local currentTime = g_currentMission.time or 0

    -- Condition 1: Engine turned off
    local motorized = vehicle.spec_motorized
    if motorized and not motorized.isMotorStarted then
        UsedPlusMaintenance.endRunaway(vehicle, "engine_off")
        return
    end

    -- Condition 2: Crash detected (sudden speed loss while moving)
    local currentSpeed = 0
    if vehicle.getLastSpeed then
        currentSpeed = vehicle:getLastSpeed()
    end

    -- dt is in milliseconds, convert to seconds for per-second delta
    local dtSeconds = dt / 1000
    if dtSeconds > 0 and currentSpeed > 2 then
        local speedDelta = (spec.runawayPreviousSpeed - currentSpeed) / dtSeconds
        if speedDelta > config.runawayCrashSpeedDelta then
            -- Was moving fast, suddenly slowed = crash!
            UsedPlusMaintenance.endRunaway(vehicle, "crash")
            return
        end
    end

    -- Condition 3: Damage increased significantly (backup crash detection)
    local currentDamage = vehicle:getVehicleDamage() or 0
    if currentDamage - (spec.runawayPreviousDamage or 0) > 0.02 then
        UsedPlusMaintenance.endRunaway(vehicle, "damage")
        return
    end

    -- Condition 4: Fluids restored (player refilled while running - unlikely but possible)
    local oilLevel = spec.oilLevel or 1.0
    local hydraulicLevel = spec.hydraulicFluidLevel or 1.0
    local oilOK = oilLevel >= config.runawayOilThreshold
    local hydraulicOK = hydraulicLevel >= config.runawayHydraulicThreshold
    if oilOK or hydraulicOK then
        UsedPlusMaintenance.endRunaway(vehicle, "fluids_restored")
        return
    end

    -- Update tracking for next frame
    spec.runawayPreviousSpeed = currentSpeed
    spec.runawayPreviousDamage = currentDamage
end

--[[
    v2.5.0: End runaway state and show appropriate message
    @param reason - Why runaway ended: "engine_off", "crash", "damage", "fluids_restored"
]]
function UsedPlusMaintenance.endRunaway(vehicle, reason)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    spec.runawayActive = false

    local messages = {
        engine_off = g_i18n:getText("usedplus_runaway_end_engineOff") or "Engine stopped - runaway ended.",
        crash = g_i18n:getText("usedplus_runaway_end_crash") or "Impact detected - runaway ended.",
        damage = g_i18n:getText("usedplus_runaway_end_damage") or "Vehicle damaged - runaway ended.",
        fluids_restored = g_i18n:getText("usedplus_runaway_end_fluids") or "Fluids restored - governor recovered."
    }

    -- Show info (not warning - the danger is over)
    g_currentMission:showBlinkingWarning(messages[reason] or "Runaway ended.", 3000)

    -- v2.5.2: Fire API event
    UsedPlusMaintenance.fireMalfunctionEnded(vehicle, "runaway")

    UsedPlus.logDebug("Runaway ended on " .. vehicle:getName() .. ": " .. reason)
end

--[[
    v2.5.0: Check for implement stuck DOWN malfunction
    Hydraulic lift failure prevents raising the implement
]]
function UsedPlusMaintenance.checkImplementStuckDown(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if malfunctions are enabled
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then return end

    local config = UsedPlusMaintenance.CONFIG

    if not config.enableImplementStuckDown then return end

    -- v2.8.0: Check global malfunction cooldown (prevents cascade failures)
    if UsedPlusMaintenance.isInGlobalCooldown(vehicle) then return end

    if spec.implementStuckDown then return end  -- Already stuck

    local hydraulicReliability = ModCompatibility.getHydraulicReliability(vehicle)
    if hydraulicReliability >= config.implementStuckDownThreshold then return end

    -- Check if any implement is lowered
    local implements = nil
    if vehicle.getAttachedImplements then
        implements = vehicle:getAttachedImplements()
    end
    if not implements or #implements == 0 then return end

    for _, impl in pairs(implements) do
        local implement = impl.object
        if implement and implement.getIsLowered and implement:getIsLowered() then
            -- Has a lowered implement - can get stuck!
            local reliabilityFactor = (config.implementStuckDownThreshold - hydraulicReliability) / config.implementStuckDownThreshold
            local baseChance = config.implementStuckDownChance * reliabilityFactor * 2

            -- v2.5.2: Apply fluid multiplier (low fluid = higher chance)
            local fluidMultiplier = UsedPlusMaintenance.getHydraulicFluidChanceMultiplier(vehicle)
            local chance = baseChance * fluidMultiplier

            if math.random() < chance then
                -- STUCK!
                spec.implementStuckDown = true

                -- v2.5.2: Apply severity multiplier to duration (low fluid = stuck longer)
                local severityMultiplier = UsedPlusMaintenance.getHydraulicFluidSeverityMultiplier(vehicle)
                local duration = math.floor(config.implementStuckDownDuration * severityMultiplier)
                spec.implementStuckDownEndTime = (g_currentMission.time or 0) + duration

                -- v2.8.0: Record malfunction time for global cooldown
                UsedPlusMaintenance.recordMalfunctionTime(vehicle)

                UsedPlusMaintenance.showWarning(vehicle,
                    g_i18n:getText("usedplus_warning_stuckDown") or
                    "HYDRAULIC LIFT FAILURE - Implement cannot raise!")

                UsedPlus.logDebug(string.format("Implement stuck DOWN on %s (reliability=%.1f%%, fluidMult=%.2fx, duration=%ds)",
                    vehicle:getName(), hydraulicReliability * 100, fluidMultiplier, duration / 1000))
                return
            end
        end
    end
end

--[[
    v2.5.0: Check for implement stuck UP malfunction
    Hydraulic valve failure prevents lowering the implement
]]
function UsedPlusMaintenance.checkImplementStuckUp(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if malfunctions are enabled
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then return end

    local config = UsedPlusMaintenance.CONFIG

    if not config.enableImplementStuckUp then return end

    -- v2.8.0: Check global malfunction cooldown (prevents cascade failures)
    if UsedPlusMaintenance.isInGlobalCooldown(vehicle) then return end

    if spec.implementStuckUp then return end  -- Already stuck

    local hydraulicReliability = ModCompatibility.getHydraulicReliability(vehicle)
    if hydraulicReliability >= config.implementStuckUpThreshold then return end

    -- Check if any implement is raised
    local implements = nil
    if vehicle.getAttachedImplements then
        implements = vehicle:getAttachedImplements()
    end
    if not implements or #implements == 0 then return end

    for _, impl in pairs(implements) do
        local implement = impl.object
        if implement and implement.getIsLowered then
            if not implement:getIsLowered() then
                -- Has a raised implement - can get stuck!
                local reliabilityFactor = (config.implementStuckUpThreshold - hydraulicReliability) / config.implementStuckUpThreshold
                local baseChance = config.implementStuckUpChance * reliabilityFactor * 2

                -- v2.5.2: Apply fluid multiplier (low fluid = higher chance)
                local fluidMultiplier = UsedPlusMaintenance.getHydraulicFluidChanceMultiplier(vehicle)
                local chance = baseChance * fluidMultiplier

                if math.random() < chance then
                    -- STUCK!
                    spec.implementStuckUp = true

                    -- v2.5.2: Apply severity multiplier to duration (low fluid = stuck longer)
                    local severityMultiplier = UsedPlusMaintenance.getHydraulicFluidSeverityMultiplier(vehicle)
                    local duration = math.floor(config.implementStuckUpDuration * severityMultiplier)
                    spec.implementStuckUpEndTime = (g_currentMission.time or 0) + duration

                    -- v2.8.0: Record malfunction time for global cooldown
                    UsedPlusMaintenance.recordMalfunctionTime(vehicle)

                    UsedPlusMaintenance.showWarning(vehicle,
                        g_i18n:getText("usedplus_warning_stuckUp") or
                        "HYDRAULIC VALVE FAILURE - Implement cannot lower!")

                    UsedPlus.logDebug(string.format("Implement stuck UP on %s (reliability=%.1f%%, fluidMult=%.2fx, duration=%ds)",
                        vehicle:getName(), hydraulicReliability * 100, fluidMultiplier, duration / 1000))
                    return
                end
            end
        end
    end
end

--[[
    v2.5.0: Check for implement steering pull malfunction
    Asymmetric drag from implements causes steering bias
]]
function UsedPlusMaintenance.checkImplementPull(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if malfunctions are enabled
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then return end

    local config = UsedPlusMaintenance.CONFIG

    if not config.enableImplementPull then return end

    -- v2.8.0: Check global malfunction cooldown (prevents cascade failures)
    if UsedPlusMaintenance.isInGlobalCooldown(vehicle) then return end

    if spec.implementPullActive then return end  -- Already active

    local hydraulicReliability = ModCompatibility.getHydraulicReliability(vehicle)
    if hydraulicReliability >= config.implementPullThreshold then return end

    -- Need attached implements
    local implements = nil
    if vehicle.getAttachedImplements then
        implements = vehicle:getAttachedImplements()
    end
    if not implements or #implements == 0 then return end

    local reliabilityFactor = (config.implementPullThreshold - hydraulicReliability) / config.implementPullThreshold
    local baseChance = config.implementPullChance * reliabilityFactor * 2

    -- v2.5.2: Apply fluid multiplier (low fluid = higher chance)
    local fluidMultiplier = UsedPlusMaintenance.getHydraulicFluidChanceMultiplier(vehicle)
    local chance = baseChance * fluidMultiplier

    if math.random() < chance then
        -- ACTIVATE!
        spec.implementPullActive = true

        -- v2.5.2: Apply severity multiplier to duration
        local severityMultiplier = UsedPlusMaintenance.getHydraulicFluidSeverityMultiplier(vehicle)
        local duration = math.floor(config.implementPullDuration * severityMultiplier)
        spec.implementPullEndTime = (g_currentMission.time or 0) + duration

        spec.implementPullDirection = math.random() < 0.5 and -1 or 1

        -- v2.8.0: Record malfunction time for global cooldown
        UsedPlusMaintenance.recordMalfunctionTime(vehicle)

        local directionText = spec.implementPullDirection < 0 and
            (g_i18n:getText("usedPlus_directionLeft") or "left") or
            (g_i18n:getText("usedPlus_directionRight") or "right")

        UsedPlusMaintenance.showWarning(vehicle,
            string.format(g_i18n:getText("usedplus_warning_implementPull") or
            "IMPLEMENT DRAG - Pulling %s!", directionText))

        UsedPlus.logDebug(string.format("Implement pull activated on %s (direction=%s, reliability=%.1f%%, fluidMult=%.2fx)",
            vehicle:getName(), directionText, hydraulicReliability * 100, fluidMultiplier))
    end
end

--[[
    v2.5.0: Check for implement speed drag malfunction
    Hydraulic system can't maintain implement position under load
]]
function UsedPlusMaintenance.checkImplementDrag(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if malfunctions are enabled
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then return end

    local config = UsedPlusMaintenance.CONFIG

    if not config.enableImplementDrag then return end

    -- v2.8.0: Check global malfunction cooldown (prevents cascade failures)
    if UsedPlusMaintenance.isInGlobalCooldown(vehicle) then return end

    if spec.implementDragActive then return end  -- Already active

    local hydraulicReliability = ModCompatibility.getHydraulicReliability(vehicle)
    if hydraulicReliability >= config.implementDragThreshold then return end

    -- Need lowered implements (under load)
    local implements = nil
    if vehicle.getAttachedImplements then
        implements = vehicle:getAttachedImplements()
    end
    if not implements or #implements == 0 then return end

    local hasLoweredImpl = false
    for _, impl in pairs(implements) do
        local implement = impl.object
        if implement and implement.getIsLowered and implement:getIsLowered() then
            hasLoweredImpl = true
            break
        end
    end
    if not hasLoweredImpl then return end

    local reliabilityFactor = (config.implementDragThreshold - hydraulicReliability) / config.implementDragThreshold
    local baseChance = config.implementDragChance * reliabilityFactor * 2

    -- v2.5.2: Apply fluid multiplier (low fluid = higher chance)
    local fluidMultiplier = UsedPlusMaintenance.getHydraulicFluidChanceMultiplier(vehicle)
    local chance = baseChance * fluidMultiplier

    if math.random() < chance then
        -- ACTIVATE!
        spec.implementDragActive = true

        -- v2.5.2: Apply severity multiplier to duration
        local severityMultiplier = UsedPlusMaintenance.getHydraulicFluidSeverityMultiplier(vehicle)
        local duration = math.floor(config.implementDragDuration * severityMultiplier)
        spec.implementDragEndTime = (g_currentMission.time or 0) + duration

        -- v2.8.0: Record malfunction time for global cooldown
        UsedPlusMaintenance.recordMalfunctionTime(vehicle)

        UsedPlusMaintenance.showWarning(vehicle,
            g_i18n:getText("usedplus_warning_implementDrag") or
            "HYDRAULIC STRAIN - Speed reduced!")

        UsedPlus.logDebug(string.format("Implement drag activated on %s (reliability=%.1f%%, fluidMult=%.2fx)",
            vehicle:getName(), hydraulicReliability * 100, fluidMultiplier))
    end
end

--[[
    v2.5.0: Check for reduced turning radius malfunction
    Power steering failure reduces steering effectiveness
]]
function UsedPlusMaintenance.checkReducedTurning(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if malfunctions are enabled
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then return end

    local config = UsedPlusMaintenance.CONFIG

    if not config.enableReducedTurning then return end

    -- v2.8.0: Check global malfunction cooldown (prevents cascade failures)
    if UsedPlusMaintenance.isInGlobalCooldown(vehicle) then return end

    if spec.reducedTurningActive then return end  -- Already active

    local hydraulicReliability = ModCompatibility.getHydraulicReliability(vehicle)
    if hydraulicReliability >= config.reducedTurningThreshold then return end

    local reliabilityFactor = (config.reducedTurningThreshold - hydraulicReliability) / config.reducedTurningThreshold
    local baseChance = config.reducedTurningChance * reliabilityFactor * 2

    -- v2.5.2: Apply fluid multiplier (low fluid = higher chance)
    local fluidMultiplier = UsedPlusMaintenance.getHydraulicFluidChanceMultiplier(vehicle)
    local chance = baseChance * fluidMultiplier

    if math.random() < chance then
        -- ACTIVATE!
        spec.reducedTurningActive = true

        -- v2.5.2: Apply severity multiplier to duration
        local severityMultiplier = UsedPlusMaintenance.getHydraulicFluidSeverityMultiplier(vehicle)
        local duration = math.floor(config.reducedTurningDuration * severityMultiplier)
        spec.reducedTurningEndTime = (g_currentMission.time or 0) + duration

        -- v2.8.0: Record malfunction time for global cooldown
        UsedPlusMaintenance.recordMalfunctionTime(vehicle)

        UsedPlusMaintenance.showWarning(vehicle,
            g_i18n:getText("usedplus_warning_reducedTurning") or
            "POWER STEERING WEAK - Turning limited!")

        UsedPlus.logDebug(string.format("Reduced turning activated on %s (reliability=%.1f%%, fluidMult=%.2fx)",
            vehicle:getName(), hydraulicReliability * 100, fluidMultiplier))
    end
end

--[[
    v1.6.0: Check for implement malfunctions
    Handles surge (random lift), drop (sudden lower), PTO toggle, and hitch failure
    Called every 1 second from periodic checks
]]
function UsedPlusMaintenance.checkImplementMalfunctions(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if malfunctions are enabled
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then return end

    -- v2.8.0: Check global malfunction cooldown (prevents cascade failures)
    if UsedPlusMaintenance.isInGlobalCooldown(vehicle) then return end

    local config = UsedPlusMaintenance.CONFIG
    local hydraulicReliability = spec.hydraulicReliability or 1.0
    local electricalReliability = spec.electricalReliability or 1.0

    -- Get attached implements
    if not vehicle.getAttachedImplements then return end
    local implements = vehicle:getAttachedImplements()
    if implements == nil or #implements == 0 then return end

    -- Process each implement
    for _, implement in pairs(implements) do
        local attachedVehicle = implement.object
        if attachedVehicle then
            -- Implement Surge (random lift) - hydraulic pressure spike
            if config.enableImplementSurge and hydraulicReliability < config.implementSurgeThreshold then
                UsedPlusMaintenance.checkImplementSurge(vehicle, attachedVehicle, hydraulicReliability)
            end

            -- Implement Drop (sudden lower) - hydraulic valve failure
            if config.enableImplementDrop and hydraulicReliability < config.implementDropThreshold then
                UsedPlusMaintenance.checkImplementDrop(vehicle, attachedVehicle, hydraulicReliability)
            end

            -- PTO Toggle - electrical relay failure
            if config.enablePTOToggle and electricalReliability < config.ptoToggleThreshold then
                UsedPlusMaintenance.checkPTOToggle(vehicle, attachedVehicle, electricalReliability)
            end

            -- Hitch Failure - implement detaches (VERY RARE)
            if config.enableHitchFailure and hydraulicReliability < config.hitchFailureThreshold then
                UsedPlusMaintenance.checkHitchFailure(vehicle, implement, hydraulicReliability)
            end
        end
    end
end

--[[
    v1.6.0: Check for implement surge (random lift)
    Simulates hydraulic pressure spike lifting a lowered implement
]]
function UsedPlusMaintenance.checkImplementSurge(vehicle, implement, hydraulicReliability)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if malfunctions are enabled (redundant but safe)
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then return end

    -- v2.7.0: Skip if hydraulics are seized (implements already locked)
    if spec.hydraulicsSeized then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Only affects lowered implements
    if not implement.getIsLowered or not implement:getIsLowered() then
        return
    end

    -- Calculate surge chance based on reliability
    local reliabilityFactor = (config.implementSurgeThreshold - hydraulicReliability) / config.implementSurgeThreshold
    local baseChance = reliabilityFactor * config.implementSurgeChance

    -- v2.5.2: Apply fluid multiplier (low fluid = higher chance)
    local fluidMultiplier = UsedPlusMaintenance.getHydraulicFluidChanceMultiplier(vehicle)
    local surgeChance = baseChance * fluidMultiplier

    if math.random() < surgeChance then
        -- v2.7.0: SEIZURE ESCALATION CHECK
        -- When hydraulic malfunction triggers, roll for permanent seizure
        if UsedPlusMaintenance.rollForSeizure(vehicle, "hydraulic") then
            -- ESCALATE to permanent seizure!
            UsedPlusMaintenance.seizeComponent(vehicle, "hydraulic")
            return  -- Don't do temporary surge
        end

        -- === Existing temporary surge code (unchanged) ===
        -- Surge! Lift the implement
        if implement.setLoweredAll then
            implement:setLoweredAll(false)

            -- v2.8.0: Record malfunction time for global cooldown
            UsedPlusMaintenance.recordMalfunctionTime(vehicle)

            if not spec.hasShownSurgeWarning and UsedPlusMaintenance.shouldShowWarning(vehicle) then
                g_currentMission:showBlinkingWarning(
                    g_i18n:getText("usedPlus_implementSurge") or "Hydraulic surge - implement raised!",
                    3000
                )
                spec.hasShownSurgeWarning = true
            end

            UsedPlus.logDebug(string.format("Implement surge on %s - %s raised",
                vehicle:getName(), implement:getName()))
        end
    end
end

--[[
    v1.6.0: Check for implement drop (sudden lower)
    Simulates hydraulic valve failure dropping a raised implement
]]
function UsedPlusMaintenance.checkImplementDrop(vehicle, implement, hydraulicReliability)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if malfunctions are enabled (redundant but safe)
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then return end

    -- v2.7.0: Skip if hydraulics are seized (implements already locked)
    if spec.hydraulicsSeized then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Only affects raised implements
    if not implement.getIsLowered or implement:getIsLowered() then
        return
    end

    -- Calculate drop chance based on reliability
    local reliabilityFactor = (config.implementDropThreshold - hydraulicReliability) / config.implementDropThreshold
    local baseChance = reliabilityFactor * config.implementDropChance

    -- v2.5.2: Apply fluid multiplier (low fluid = higher chance)
    local fluidMultiplier = UsedPlusMaintenance.getHydraulicFluidChanceMultiplier(vehicle)
    local dropChance = baseChance * fluidMultiplier

    if math.random() < dropChance then
        -- v2.7.0: SEIZURE ESCALATION CHECK
        -- When hydraulic malfunction triggers, roll for permanent seizure
        if UsedPlusMaintenance.rollForSeizure(vehicle, "hydraulic") then
            -- ESCALATE to permanent seizure!
            UsedPlusMaintenance.seizeComponent(vehicle, "hydraulic")
            return  -- Don't do temporary drop
        end

        -- === Existing temporary drop code (unchanged) ===
        -- Drop! Lower the implement suddenly
        if implement.setLoweredAll then
            implement:setLoweredAll(true)
            spec.failureCount = (spec.failureCount or 0) + 1  -- v1.6.0: Count as breakdown

            -- v2.8.0: Record malfunction time for global cooldown
            UsedPlusMaintenance.recordMalfunctionTime(vehicle)

            -- v2.7.0: Apply DNA-based breakdown degradation (lemons degrade faster)
            UsedPlusMaintenance.applyBreakdownDegradation(vehicle, "Hydraulic")

            -- v1.7.0: Hydraulic failure while fluid is low = permanent damage
            UsedPlusMaintenance.applyHydraulicDamageOnFailure(vehicle)

            if not spec.hasShownDropWarning and UsedPlusMaintenance.shouldShowWarning(vehicle) then
                g_currentMission:showBlinkingWarning(
                    g_i18n:getText("usedPlus_implementDrop") or "Hydraulic failure - implement dropped!",
                    3000
                )
                spec.hasShownDropWarning = true
            end

            UsedPlus.logDebug(string.format("Implement drop on %s - %s lowered",
                vehicle:getName(), implement:getName()))
        end
    end
end

--[[
    v1.6.0: Check for PTO toggle (power randomly on/off)
    Simulates electrical relay failure toggling implement power
]]
function UsedPlusMaintenance.checkPTOToggle(vehicle, implement, electricalReliability)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if malfunctions are enabled (redundant but safe)
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then return end

    -- v2.7.0: Skip if electrical is seized (already permanently dead)
    if spec.electricalSeized then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Only affects implements that can be turned on/off
    if not implement.getIsTurnedOn then
        return
    end

    -- Calculate toggle chance based on reliability
    local reliabilityFactor = (config.ptoToggleThreshold - electricalReliability) / config.ptoToggleThreshold
    local toggleChance = reliabilityFactor * config.ptoToggleChance

    if math.random() < toggleChance then
        -- Toggle! Switch power state
        local isOn = implement:getIsTurnedOn()
        if implement.setIsTurnedOn then
            implement:setIsTurnedOn(not isOn)

            -- v2.8.0: Record malfunction time for global cooldown
            UsedPlusMaintenance.recordMalfunctionTime(vehicle)

            if not spec.hasShownPTOWarning and UsedPlusMaintenance.shouldShowWarning(vehicle) then
                local stateText = isOn and
                    (g_i18n:getText("usedPlus_ptoOff") or "off") or
                    (g_i18n:getText("usedPlus_ptoOn") or "on")
                g_currentMission:showBlinkingWarning(
                    string.format(g_i18n:getText("usedPlus_ptoToggle") or "Electrical fault - PTO switched %s!", stateText),
                    3000
                )
                spec.hasShownPTOWarning = true
            end

            UsedPlus.logDebug(string.format("PTO toggle on %s - %s turned %s",
                vehicle:getName(), implement:getName(), isOn and "off" or "on"))
        end
    end
end

--[[
    v1.6.0: Check for hitch failure (implement detaches)
    VERY RARE - only at critical hydraulic reliability
    Simulates complete hydraulic hitch failure
]]
function UsedPlusMaintenance.checkHitchFailure(vehicle, implementInfo, hydraulicReliability)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if malfunctions are enabled (redundant but safe)
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then return end

    local config = UsedPlusMaintenance.CONFIG
    local implement = implementInfo.object
    if implement == nil then return end

    -- Calculate failure chance (very low)
    local reliabilityFactor = (config.hitchFailureThreshold - hydraulicReliability) / config.hitchFailureThreshold
    local baseChance = reliabilityFactor * config.hitchFailureChance

    -- v2.5.2: Apply fluid multiplier (low fluid = higher chance)
    local fluidMultiplier = UsedPlusMaintenance.getHydraulicFluidChanceMultiplier(vehicle)
    local failureChance = baseChance * fluidMultiplier

    if math.random() < failureChance then
        -- Hitch failure! Detach the implement
        local jointDescIndex = implementInfo.jointDescIndex

        -- Try to detach using the vehicle's method
        if vehicle.detachImplementByObject then
            vehicle:detachImplementByObject(implement)
            spec.failureCount = (spec.failureCount or 0) + 1  -- v1.6.0: Count as major breakdown

            -- v2.8.0: Record malfunction time for global cooldown
            UsedPlusMaintenance.recordMalfunctionTime(vehicle)

            -- v2.7.0: Apply DNA-based breakdown degradation (lemons degrade faster)
            UsedPlusMaintenance.applyBreakdownDegradation(vehicle, "Hydraulic")

            -- v1.7.0: Hitch failure while fluid is low = permanent damage
            UsedPlusMaintenance.applyHydraulicDamageOnFailure(vehicle)

            if not spec.hasShownHitchWarning and UsedPlusMaintenance.shouldShowWarning(vehicle) then
                g_currentMission:showBlinkingWarning(
                    g_i18n:getText("usedPlus_hitchFailure") or "HITCH FAILURE - Implement detached!",
                    5000
                )
                spec.hasShownHitchWarning = true
            end

            UsedPlus.logDebug(string.format("Hitch failure on %s - %s detached!",
                vehicle:getName(), implement:getName()))
        end
    end
end

--[[
    Check for electrical cutout on attached implements
    Poor electrical reliability causes random implement shutoffs
    Phase 5 feature
]]
function UsedPlusMaintenance.checkImplementCutout(vehicle, dt)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if malfunctions are enabled
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then return end

    -- v2.7.0: Skip if electrical is seized (already permanently dead)
    if spec.electricalSeized then return end

    -- v2.8.0: Check global malfunction cooldown (prevents cascade failures)
    if UsedPlusMaintenance.isInGlobalCooldown(vehicle) then return end

    local config = UsedPlusMaintenance.CONFIG
    local currentTime = g_currentMission.time or 0

    -- v1.8.0: Use ModCompatibility to get electrical reliability
    local electricalReliability = ModCompatibility.getElectricalReliability(vehicle)

    -- Check if we're in cutout recovery
    if spec.isCutout then
        if currentTime > spec.cutoutEndTime then
            spec.isCutout = false
            UsedPlus.logDebug("Electrical cutout ended for " .. vehicle:getName())
        else
            return
        end
    end

    -- Calculate cutout chance (threshold check)
    if electricalReliability >= 0.5 then
        return
    end

    -- Chance increases with lower reliability
    local reliabilityFactor = (0.5 - electricalReliability) / 0.5
    local baseChance = reliabilityFactor * config.cutoutBaseChance

    if math.random() < baseChance then
        -- v2.7.0: SEIZURE ESCALATION CHECK
        -- When electrical malfunction triggers, roll for permanent seizure
        if UsedPlusMaintenance.rollForSeizure(vehicle, "electrical") then
            -- ESCALATE to permanent seizure!
            UsedPlusMaintenance.seizeComponent(vehicle, "electrical")
            return  -- Don't do temporary cutout
        end

        -- === Existing temporary cutout code (unchanged) ===
        spec.isCutout = true
        spec.cutoutEndTime = g_currentMission.time + config.cutoutDurationMs
        spec.failureCount = (spec.failureCount or 0) + 1

        -- v2.8.0: Record malfunction time for global cooldown
        UsedPlusMaintenance.recordMalfunctionTime(vehicle)

        -- Try to raise/stop implements
        if vehicle.getAttachedAIImplements then
            local implements = vehicle:getAttachedAIImplements()
            if implements then
                for _, implement in pairs(implements) do
                    if implement.object and implement.object.aiImplementEndLine then
                        implement.object:aiImplementEndLine()
                    end
                end
            end
        end

        -- Also try direct child vehicles
        local childVehicles = vehicle:getChildVehicles()
        if childVehicles then
            for _, childVehicle in pairs(childVehicles) do
                if childVehicle.aiImplementEndLine then
                    childVehicle:aiImplementEndLine()
                end
                -- Turn off PTO if possible
                if childVehicle.setIsTurnedOn then
                    childVehicle:setIsTurnedOn(false)
                end
            end
        end

        -- Show warning to player
        if UsedPlusMaintenance.shouldShowWarning(vehicle) then
            g_currentMission:showBlinkingWarning(
                g_i18n:getText("usedPlus_electricalCutout") or "Electrical fault - implements offline!",
                3000
            )
        end

        -- Stop AI worker if active
        local rootVehicle = vehicle:getRootVehicle()
        if rootVehicle and rootVehicle.getIsAIActive and rootVehicle:getIsAIActive() then
            if rootVehicle.stopCurrentAIJob then
                local errorMessage = nil
                if AIMessageErrorVehicleBroken and AIMessageErrorVehicleBroken.new then
                    errorMessage = AIMessageErrorVehicleBroken.new()
                end
                rootVehicle:stopCurrentAIJob(errorMessage)
            end
        end

        UsedPlus.logDebug(string.format("Electrical cutout on %s (failures: %d)", vehicle:getName(), spec.failureCount))
    end
end

--[[
    v1.6.0: Trigger electrical implement cutout
    Called when cutout malfunction fires
    @param vehicle - The vehicle with the electrical failure
]]
function UsedPlusMaintenance.triggerImplementCutout(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG

    -- v2.7.0: SEIZURE ESCALATION CHECK
    -- When electrical malfunction triggers, roll for permanent seizure
    if UsedPlusMaintenance.rollForSeizure(vehicle, "electrical") then
        -- ESCALATE to permanent seizure!
        UsedPlusMaintenance.seizeComponent(vehicle, "electrical")
        return  -- Don't do temporary cutout
    end

    -- v2.8.0: Record malfunction time for global cooldown
    UsedPlusMaintenance.recordMalfunctionTime(vehicle)

    -- === Existing temporary cutout code (unchanged) ===
    spec.isCutout = true
    spec.cutoutEndTime = g_currentMission.time + config.cutoutDurationMs
    spec.failureCount = (spec.failureCount or 0) + 1

    -- Try to raise/stop implements
    if vehicle.getAttachedAIImplements then
        local implements = vehicle:getAttachedAIImplements()
        if implements then
            for _, implement in pairs(implements) do
                if implement.object and implement.object.aiImplementEndLine then
                    implement.object:aiImplementEndLine()
                end
            end
        end
    end

    -- Also try direct child vehicles
    local childVehicles = vehicle:getChildVehicles()
    if childVehicles then
        for _, childVehicle in pairs(childVehicles) do
            if childVehicle.aiImplementEndLine then
                childVehicle:aiImplementEndLine()
            end
            -- Turn off PTO if possible
            if childVehicle.setIsTurnedOn then
                childVehicle:setIsTurnedOn(false)
            end
        end
    end

    -- Show warning to player
    if UsedPlusMaintenance.shouldShowWarning(vehicle) then
        g_currentMission:showBlinkingWarning(
            g_i18n:getText("usedPlus_electricalCutout") or "Electrical fault - implements offline!",
            3000
        )
    end

    -- Stop AI worker if active
    local rootVehicle = vehicle:getRootVehicle()
    if rootVehicle and rootVehicle.getIsAIActive and rootVehicle:getIsAIActive() then
        if rootVehicle.stopCurrentAIJob then
            local errorMessage = nil
            if AIMessageErrorVehicleBroken and AIMessageErrorVehicleBroken.new then
                errorMessage = AIMessageErrorVehicleBroken.new()
            end
            rootVehicle:stopCurrentAIJob(errorMessage)
        end
    end

    UsedPlus.logDebug(string.format("Electrical cutout on %s (failures: %d)", vehicle:getName(), spec.failureCount))
end

UsedPlus.logDebug("MaintenanceHydraulics module loaded")
