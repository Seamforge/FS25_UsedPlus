--[[
    MaintenanceEngine.lua
    Engine stall, misfire, overheating, and motor override functions

    Extracted from UsedPlusMaintenance.lua for modularity
]]

-- Ensure UsedPlusMaintenance table exists (modules load before main spec)
UsedPlusMaintenance = UsedPlusMaintenance or {}

--[[
    Check for engine stall
    Stalling more likely with high damage + low reliability + high load

    v1.8.0: "Symptoms Before Failure" integration
    Our stalls are TEMPORARY (engine dies but restarts after cooldown)
    RVB's ENGINE FAULT is PERMANENT (7km/h cap until repaired)
    We provide the "symptoms", RVB provides the "failure"
    So we KEEP our stalls active even when RVB is installed!
]]
function UsedPlusMaintenance.checkEngineStall(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if malfunctions are enabled
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then return end

    -- v2.7.0: Skip if engine is seized (already permanently dead)
    if spec.engineSeized then return end

    -- v2.8.0: Check global malfunction cooldown (prevents cascade failures)
    if UsedPlusMaintenance.isInGlobalCooldown(vehicle) then
        return
    end

    -- Cooldown check (prevent stalling every frame)
    if spec.stallCooldown > 0 then
        return
    end

    -- Only check running engines
    if vehicle.getIsMotorStarted and not vehicle:getIsMotorStarted() then
        return
    end

    -- v1.8.0: Use ModCompatibility to get engine reliability
    -- If RVB installed, this provides "symptom stalls" based on RVB part health
    local engineReliability = ModCompatibility.getEngineReliability(vehicle)

    -- Calculate stall probability using the compatibility-aware reliability
    local stallChance = UsedPlusMaintenance.calculateFailureProbability(vehicle, "engine", engineReliability)

    if math.random() < stallChance then
        -- STALL! (temporary - player can restart after cooldown)
        UsedPlusMaintenance.triggerEngineStall(vehicle)
    end
end

--[[
    Actually perform the engine stall
    Stops the motor and notifies the player
    @param vehicle - The vehicle to stall
    @param isFirstStart - Optional: true if this is a first-start stall (different message)
]]
function UsedPlusMaintenance.triggerEngineStall(vehicle, isFirstStart)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- v2.7.0: SEIZURE ESCALATION CHECK
    -- When malfunction triggers, roll for permanent seizure vs temporary stall
    -- First-start stalls don't escalate (give player a chance)
    if not isFirstStart then
        if UsedPlusMaintenance.rollForSeizure(vehicle, "engine") then
            -- ESCALATE to permanent seizure!
            UsedPlusMaintenance.seizeComponent(vehicle, "engine")
            return  -- Don't do temporary stall
        end
    end

    -- v2.8.0: Record malfunction time for global cooldown
    UsedPlusMaintenance.recordMalfunctionTime(vehicle)

    -- === Existing temporary stall code (unchanged) ===
    -- Stop the motor
    if vehicle.stopMotor then
        vehicle:stopMotor()
    end

    spec.isStalled = true
    spec.stallCooldown = UsedPlusMaintenance.CONFIG.stallCooldownMs
    spec.failureCount = (spec.failureCount or 0) + 1

    -- v1.7.0: Check for permanent damage from low fluids
    -- Engine stall while oil is critically low = permanent engine damage
    UsedPlusMaintenance.applyOilDamageOnFailure(vehicle)

    -- v1.5.1: Set recovery period - engine cannot restart for X seconds
    -- This defeats auto-start and forces the player to actually stop
    local currentTime = g_currentMission.time or 0
    local recoveryDuration = UsedPlusMaintenance.CONFIG.stallRecoveryDurationMs
    spec.stallRecoveryEndTime = currentTime + recoveryDuration

    -- Show warning to player (include recovery time)
    local recoverySeconds = math.ceil(recoveryDuration / 1000)
    local message
    if isFirstStart then
        -- First-start stall - different message
        message = g_i18n:getText("usedPlus_firstStartStall")
        if message == "usedPlus_firstStartStall" then
            message = "Engine failed to start! Wait %d seconds..."
        else
            message = message .. " Wait %d seconds..."
        end
    else
        -- Normal stall during operation
        message = g_i18n:getText("usedPlus_engineStalledRecovery")
        if message == "usedPlus_engineStalledRecovery" then
            message = "Engine stalled! Wait %d seconds..."
        end
    end
    -- v1.7.2: Show warning - first-start stalls ALWAYS show (intentional feedback)
    -- Normal stalls respect shouldShowWarning (checks grace period, control state)
    local shouldShow = isFirstStart or UsedPlusMaintenance.shouldShowWarning(vehicle)
    if shouldShow then
        g_currentMission:showBlinkingWarning(
            string.format(message, recoverySeconds),
            recoveryDuration
        )
        UsedPlus.logDebug("Stall warning shown to player")
    else
        UsedPlus.logDebug("Stall warning suppressed (not controlling or grace period)")
    end

    -- Stop AI worker if active
    local rootVehicle = vehicle:getRootVehicle()
    if rootVehicle and rootVehicle.getIsAIActive and rootVehicle:getIsAIActive() then
        if rootVehicle.stopCurrentAIJob then
            -- Try to create error message
            local errorMessage = nil
            if AIMessageErrorVehicleBroken and AIMessageErrorVehicleBroken.new then
                errorMessage = AIMessageErrorVehicleBroken.new()
            end
            rootVehicle:stopCurrentAIJob(errorMessage)
        end
    end

    UsedPlus.logDebug(string.format("Engine stalled on %s (failures: %d, firstStart: %s)",
        vehicle:getName(), spec.failureCount, tostring(isFirstStart or false)))
end

--[[
    v1.6.0: Update misfire state per-frame
    Handles active misfire timing and burst mode
    Called every frame for responsive stuttering effect
]]
function UsedPlusMaintenance.updateMisfireState(vehicle, dt)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local currentTime = g_currentMission.time or 0

    -- Check if currently in a misfire
    if spec.misfireActive then
        if currentTime >= spec.misfireEndTime then
            -- Misfire ended
            spec.misfireActive = false

            -- Check for burst mode (multiple quick misfires)
            if spec.misfireBurstRemaining and spec.misfireBurstRemaining > 0 then
                spec.misfireBurstRemaining = spec.misfireBurstRemaining - 1
                -- Schedule next misfire in burst (50-150ms gap)
                local gapMs = math.random(50, 150)
                spec.misfireActive = true
                local duration = math.random(
                    UsedPlusMaintenance.CONFIG.misfireDurationMin,
                    UsedPlusMaintenance.CONFIG.misfireDurationMax
                )
                spec.misfireEndTime = currentTime + gapMs + duration
            end
        end
    end
end

--[[
    v1.6.0: Check for new engine misfire events
    Called every 1 second from periodic checks
    Triggers random misfires based on engine reliability
]]
function UsedPlusMaintenance.checkEngineMisfire(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if malfunctions are enabled
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then return end

    local config = UsedPlusMaintenance.CONFIG
    local engineReliability = spec.engineReliability or 1.0

    -- Only misfire if below threshold
    if engineReliability >= config.misfireThreshold then
        spec.hasShownMisfireWarning = false
        return
    end

    -- v2.8.0: Check global malfunction cooldown (prevents cascade failures)
    if UsedPlusMaintenance.isInGlobalCooldown(vehicle) then
        return
    end

    -- Don't start new misfire if one is active
    if spec.misfireActive then
        return
    end

    -- Only misfire if engine is running
    if not vehicle.getIsMotorStarted or not vehicle:getIsMotorStarted() then
        return
    end

    -- Calculate misfire chance based on reliability
    -- At threshold (60%): 0% chance
    -- At 0%: max chance (15%)
    local reliabilityFactor = (config.misfireThreshold - engineReliability) / config.misfireThreshold
    local baseMisfireChance = reliabilityFactor * config.misfireMaxChancePerCheck

    -- Higher load = more likely to misfire
    local load = 0
    if vehicle.getMotorLoadPercentage then
        load = vehicle:getMotorLoadPercentage() or 0
    end
    local loadChance = baseMisfireChance * (0.5 + load * 0.5)  -- 50-100% of base chance

    -- v2.5.2: Apply oil multiplier (low oil = higher chance)
    local oilMultiplier = UsedPlusMaintenance.getOilChanceMultiplier(vehicle)
    local misfireChance = loadChance * oilMultiplier

    if math.random() < misfireChance then
        -- Trigger misfire!
        spec.misfireActive = true
        local baseDuration = math.random(config.misfireDurationMin, config.misfireDurationMax)

        -- v2.5.2: Apply oil severity multiplier to duration
        local severityMultiplier = UsedPlusMaintenance.getOilSeverityMultiplier(vehicle)
        local duration = math.floor(baseDuration * severityMultiplier)
        spec.misfireEndTime = (g_currentMission.time or 0) + duration

        -- v2.8.0: Record malfunction time for global cooldown
        UsedPlusMaintenance.recordMalfunctionTime(vehicle)

        -- Check for burst mode
        if math.random() < config.misfireBurstChance then
            spec.misfireBurstRemaining = math.random(1, config.misfireBurstCount)
        else
            spec.misfireBurstRemaining = 0
        end

        -- Show warning (once per session)
        if not spec.hasShownMisfireWarning and UsedPlusMaintenance.shouldShowWarning(vehicle) then
            g_currentMission:showBlinkingWarning(
                g_i18n:getText("usedPlus_engineMisfire") or "Engine misfiring!",
                2000
            )
            spec.hasShownMisfireWarning = true
        end

        UsedPlus.logDebug(string.format("Engine misfire on %s (duration=%dms, burst=%d)",
            vehicle:getName(), duration, spec.misfireBurstRemaining or 0))
    end
end

--[[
    v1.6.0: Update engine temperature
    Heat builds when running, dissipates when off
    Overheating causes forced stall and cooldown period
]]
function UsedPlusMaintenance.updateEngineTemperature(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if malfunctions are enabled
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then
        -- Reset temperature if malfunctions disabled
        spec.engineTemperature = 0
        spec.hasShownOverheatWarning = false
        spec.hasShownOverheatCritical = false
        return
    end

    local config = UsedPlusMaintenance.CONFIG
    local engineReliability = spec.engineReliability or 1.0
    local currentTime = g_currentMission.time or 0

    -- Only affected if below threshold
    if engineReliability >= config.overheatThreshold then
        -- Good engine - temperature stays at 0
        spec.engineTemperature = math.max(0, (spec.engineTemperature or 0) - config.overheatCoolRateOff)
        spec.hasShownOverheatWarning = false
        spec.hasShownOverheatCritical = false
        return
    end

    local isRunning = vehicle.getIsMotorStarted and vehicle:getIsMotorStarted()

    if isRunning then
        -- Engine running - heat builds up
        local load = 0
        if vehicle.getMotorLoadPercentage then
            load = vehicle:getMotorLoadPercentage() or 0
        end

        -- Heat rate scales with inverse reliability
        -- At 50% reliability: 1x heat rate
        -- At 25% reliability: 1.5x heat rate
        -- At 0% reliability: 2x heat rate
        local reliabilityFactor = 1 + (1 - engineReliability / config.overheatThreshold)

        local heatRate = config.overheatHeatRateBase + (load * config.overheatHeatRateLoad)
        heatRate = heatRate * reliabilityFactor

        -- v2.5.2: Low oil makes engine run hotter (oil is coolant + lubricant!)
        local oilMultiplier = UsedPlusMaintenance.getOilSeverityMultiplier(vehicle)
        heatRate = heatRate * oilMultiplier

        spec.engineTemperature = math.min(1.0, (spec.engineTemperature or 0) + heatRate)

        -- Check for warning thresholds
        if spec.engineTemperature >= config.overheatWarningTemp then
            if not spec.hasShownOverheatWarning and UsedPlusMaintenance.shouldShowWarning(vehicle) then
                local tempPercent = math.floor(spec.engineTemperature * 100)
                g_currentMission:showBlinkingWarning(
                    string.format(g_i18n:getText("usedPlus_engineOverheating") or "Engine overheating! (%d%%)", tempPercent),
                    3000
                )
                spec.hasShownOverheatWarning = true
            end
        end

        -- Check for critical overheat (force stall)
        if spec.engineTemperature >= config.overheatStallTemp then
            if not spec.isOverheated then
                -- Force stall!
                if vehicle.stopMotor then
                    vehicle:stopMotor()
                end
                spec.isOverheated = true
                spec.overheatCooldownEndTime = currentTime + config.overheatCooldownMs
                spec.failureCount = (spec.failureCount or 0) + 1  -- v1.6.0: Count as breakdown

                -- v2.7.0: Apply DNA-based breakdown degradation (lemons degrade faster)
                UsedPlusMaintenance.applyBreakdownDegradation(vehicle, "Engine")

                if UsedPlusMaintenance.shouldShowWarning(vehicle) then
                    g_currentMission:showBlinkingWarning(
                        g_i18n:getText("usedPlus_engineOverheated") or "ENGINE OVERHEATED! Let it cool down!",
                        5000
                    )
                end
                spec.hasShownOverheatCritical = true

                UsedPlus.logDebug(string.format("Engine overheated on %s - forced stall", vehicle:getName()))
            end
        end
    else
        -- Engine off - cool down
        local coolRate = config.overheatCoolRateOff
        spec.engineTemperature = math.max(0, (spec.engineTemperature or 0) - coolRate)

        -- Check if cooled enough to restart
        if spec.isOverheated then
            if currentTime >= spec.overheatCooldownEndTime and spec.engineTemperature <= config.overheatRestartTemp then
                spec.isOverheated = false
                spec.hasShownOverheatWarning = false
                spec.hasShownOverheatCritical = false
                UsedPlus.logDebug(string.format("Engine cooled on %s - can restart", vehicle:getName()))
            end
        end
    end
end

UsedPlus.logDebug("MaintenanceEngine module loaded")
