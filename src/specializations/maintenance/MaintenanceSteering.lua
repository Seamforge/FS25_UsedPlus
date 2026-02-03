--[[
    MaintenanceSteering.lua
    Steering pull, degradation, drift, and related effects

    Extracted from UsedPlusMaintenance.lua for modularity
]]

-- Ensure UsedPlusMaintenance table exists (modules load before main spec)
UsedPlusMaintenance = UsedPlusMaintenance or {}

--[[
    v1.6.0: Update steering pull surge timer and trigger surge events
    Called every 1 second from onUpdate periodic checks
    Surges create "oh crap" moments where pull temporarily intensifies
]]
function UsedPlusMaintenance.updateSteeringPullSurge(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Only process if pull is active (direction initialized)
    if not spec.steeringPullInitialized or spec.steeringPullDirection == 0 then
        return
    end

    -- Don't start new surge if one is already active
    if spec.steeringPullSurgeActive then
        return
    end

    local config = UsedPlusMaintenance.CONFIG

    -- Decrement surge timer
    spec.steeringPullSurgeTimer = (spec.steeringPullSurgeTimer or 0) - config.updateIntervalMs

    -- Check if it's time for a surge
    if spec.steeringPullSurgeTimer <= 0 then
        -- Trigger surge!
        spec.steeringPullSurgeActive = true
        spec.steeringPullSurgeEndTime = (g_currentMission.time or 0) + config.steeringPullSurgeDuration

        UsedPlus.logDebug(string.format("Steering pull surge triggered on %s (direction=%d, duration=%dms)",
            vehicle:getName(), spec.steeringPullDirection, config.steeringPullSurgeDuration))
    end
end

--[[
    v1.5.1: Apply steering degradation for worn feel
    Poor hydraulic reliability causes loose, sloppy steering response
    Makes the vehicle feel "old" and worn
]]
function UsedPlusMaintenance.applySteeringDegradation(vehicle, dt)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Only apply steering degradation if hydraulic reliability is low
    local hydraulicReliability = spec.hydraulicReliability or 1.0
    if hydraulicReliability >= 0.8 then
        return  -- Steering fine above 80% reliability
    end

    -- Calculate steering "slop" factor (0 = perfect, 1 = very loose)
    -- At 80% reliability: 0% slop
    -- At 50% reliability: 37.5% slop
    -- At 10% reliability: 87.5% slop
    local slopFactor = (0.8 - hydraulicReliability) / 0.8
    slopFactor = math.min(slopFactor, 0.9)  -- Max 90% slop

    -- Add random steering "wander" based on slop
    -- This creates the feeling of loose steering that doesn't hold straight
    if vehicle.spec_drivable and vehicle.spec_drivable.steeringAngle then
        -- Only apply wander when moving
        local speed = 0
        if vehicle.getLastSpeed then
            speed = vehicle:getLastSpeed()
        end

        if speed > 5 then  -- Only above 5 km/h
            -- Random micro-adjustments to steering
            local wanderAmount = slopFactor * 0.002 * (math.random() - 0.5)

            -- Apply steering wander (very subtle)
            spec.steeringWander = (spec.steeringWander or 0) + wanderAmount
            spec.steeringWander = spec.steeringWander * 0.95  -- Decay

            -- Clamp wander
            spec.steeringWander = math.max(-0.03, math.min(0.03, spec.steeringWander))
        else
            spec.steeringWander = 0
        end
    end
end

--[[
    v2.7.2: Apply steering pull DIRECTLY to wheel angles (bypasses input system)

    The setSteeringInput() hook modifies player input values, but FS25's internal
    processing may smooth, clamp, or ignore small input changes. This function
    applies steering pull directly to wheel physics like RVB does, ensuring
    the player FEELS the pull effect.

    Called every frame from onUpdate when steering effects are active.
    Pattern from: VehicleBreakdowns.lua adjustSteeringAngle()
]]
function UsedPlusMaintenance.applyDirectSteeringPull(vehicle, dt)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if malfunctions are enabled
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then
        -- Reset steering pull state when disabled
        spec.steeringPullActive = false
        spec.steeringPullStrength = 0
        return
    end

    -- Only run on server (physics is server-authoritative)
    if not vehicle.isServer then return end

    -- Check if vehicle has wheel physics
    if not vehicle.spec_wheels or not vehicle.spec_wheels.wheels then return end
    if not vehicle.isAddedToPhysics then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Calculate total pull from all active sources
    local totalPullAngle = 0  -- In radians
    local pullActive = false
    local pullSource = nil

    -- Get current speed (pull only affects moving vehicles)
    local speed = 0
    if vehicle.getLastSpeed then
        speed = vehicle:getLastSpeed()
    end

    -- ========== HYDRAULIC SURGE (highest priority - "oh crap" moment) ==========
    if spec.hydraulicSurgeActive and config.enableHydraulicSurge then
        local currentTime = g_currentMission.time or 0

        if currentTime < spec.hydraulicSurgeEndTime then
            -- Calculate surge strength (with fade)
            local surgeStrength = config.hydraulicSurgeStrength or 0.35
            if currentTime >= (spec.hydraulicSurgeFadeStartTime or 0) then
                local fadeProgress = (currentTime - spec.hydraulicSurgeFadeStartTime) / (config.hydraulicSurgeFadeTime or 2000)
                fadeProgress = math.min(fadeProgress, 1.0)
                surgeStrength = surgeStrength * (1 - fadeProgress)
            end

            -- Speed factor - more effect at higher speeds, but still present
            local speedFactor = 0.5  -- Minimum 50% effect
            if speed > 5 then
                speedFactor = math.min(0.5 + (speed / 40) * 0.5, 1.0)
            end

            -- Convert strength to steering angle (radians)
            -- Max steering angle is typically ~0.5 radians (28 degrees)
            -- 35% pull = ~0.175 radians = ~10 degrees pull
            totalPullAngle = surgeStrength * speedFactor * (spec.hydraulicSurgeDirection or 1) * 0.5
            pullActive = true
            pullSource = "surge"
        end
    end

    -- ========== FLAT TIRE PULL (high priority - persistent until repaired) ==========
    -- v2.8.0: Also respect malfunctions setting
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if spec.hasFlatTire and config.enableFlatTire and malfunctionsEnabled and not pullActive then
        local flatPullStrength = config.flatTirePullStrength or 0.25

        -- Speed factor - more noticeable at speed
        local speedFactor = 0.3  -- Minimum 30% effect
        if speed > 3 then
            speedFactor = math.min(0.3 + (speed / 40) * 0.7, 1.0)
        end

        -- Convert to angle (flat tires cause significant pull)
        totalPullAngle = flatPullStrength * speedFactor * (spec.flatTireSide or 1) * 0.5
        pullActive = true
        pullSource = "flattire"
    end

    -- ========== HYDRAULIC DEGRADATION PULL (lower priority - chronic condition) ==========
    if not pullActive and config.enableSteeringDegradation then
        local hydraulicReliability = ModCompatibility.getHydraulicReliability(vehicle)

        if hydraulicReliability < config.steeringPullThreshold then
            -- Initialize pull direction once (vehicle "personality")
            if not spec.steeringPullInitialized then
                spec.steeringPullDirection = math.random() < 0.5 and -1 or 1
                spec.steeringPullInitialized = true
            end

            -- Calculate pull factor (worse reliability = more pull)
            local pullFactor = (config.steeringPullThreshold - hydraulicReliability) / config.steeringPullThreshold
            local basePullStrength = pullFactor * (config.steeringPullMax or 0.15)

            -- Speed factor - no pull below min speed
            local speedFactor = 0
            if speed > (config.steeringPullSpeedMin or 5) then
                speedFactor = math.min((speed - config.steeringPullSpeedMin) /
                    ((config.steeringPullSpeedMax or 25) - config.steeringPullSpeedMin), 1.0)
            end

            -- Surge multiplier (intermittent intensification)
            local surgeMultiplier = 1.0
            if spec.steeringPullSurgeActive then
                surgeMultiplier = config.steeringPullSurgeMultiplier or 1.5
            end

            if speedFactor > 0 then
                totalPullAngle = basePullStrength * speedFactor * surgeMultiplier *
                    (spec.steeringPullDirection or 1) * 0.5
                pullActive = true
                pullSource = "hydraulic"
            end
        end
    end

    -- ========== APPLY PULL TO STEERABLE WHEELS ==========
    if pullActive and math.abs(totalPullAngle) > 0.001 then
        -- Track for API reporting
        spec.steeringPullActive = true
        spec.steeringPullStrength = math.abs(totalPullAngle) / 0.5  -- Normalize to 0-1

        -- Get brake force safely (may not exist on all vehicles)
        local brakeForce = 0
        if vehicle.getBrakeForce then
            brakeForce = vehicle:getBrakeForce() or 0
        end

        -- Apply to each steerable wheel
        for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
            if wheel.steeringAxleScale ~= 0 and wheel.steeringAxleScale ~= nil then
                -- This wheel can steer - apply pull adjustment
                local pullAdjustment = totalPullAngle * wheel.steeringAxleScale

                -- Blend with current steering angle (don't replace, add bias)
                local currentAngle = wheel.steeringAngle or 0
                local newAngle = currentAngle + pullAdjustment

                -- Clamp to max steering angle (fallback to 0.5 radians ~28 degrees)
                local maxAngle = wheel.steeringAngleMax or 0.5
                newAngle = math.max(-maxAngle, math.min(maxAngle, newAngle))

                -- Apply directly to physics
                wheel.steeringAngle = newAngle

                -- Update physics engine with new angle
                if wheel.node and wheel.wheelShape then
                    local wheelBrake = brakeForce * (wheel.brakeFactor or 1)
                    local rotDamping = wheel.rotationDamping or 0

                    -- Wrap in pcall for safety (setWheelShapeProps is engine function)
                    pcall(function()
                        setWheelShapeProps(
                            wheel.node,
                            wheel.wheelShape,
                            0,  -- motorTorque (unchanged)
                            wheelBrake,
                            wheel.steeringAngle,
                            rotDamping
                        )
                    end)
                end
            end
        end

        -- Debug logging (occasional, not every frame)
        if math.random() < 0.01 then  -- 1% chance per frame = ~every 1-2 seconds
            UsedPlus.logDebug(string.format("Direct steering pull active: %.3f rad (%s) on %s",
                totalPullAngle, pullSource, vehicle:getName()))
        end
    else
        spec.steeringPullActive = false
        spec.steeringPullStrength = 0
    end
end

--[[
    Check for hydraulic drift on attached implements
    Poor hydraulic reliability causes raised implements to slowly lower
    Phase 5 feature
    v1.4.0: Added visual warnings so players understand why implements are lowering
]]
function UsedPlusMaintenance.checkHydraulicDrift(vehicle, dt)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if malfunctions are enabled
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if not malfunctionsEnabled then
        -- Reset warning flags when disabled
        spec.hasShownDriftWarning = false
        spec.hasShownDriftMidpointWarning = false
        return
    end

    -- v2.7.0: Skip if hydraulics are seized (implements already locked)
    if spec.hydraulicsSeized then return end

    -- v1.8.0: Use ModCompatibility to get hydraulic reliability
    -- Note: RVB doesn't have hydraulic parts, so this will use native UsedPlus reliability
    -- This is a UNIQUE UsedPlus feature that complements RVB!
    local hydraulicReliability = ModCompatibility.getHydraulicReliability(vehicle)

    -- Only drift if hydraulic reliability is below threshold
    -- BALANCE NOTE (v1.2): Removed damage gate - low reliability causes drift even when repaired
    if hydraulicReliability >= UsedPlusMaintenance.CONFIG.hydraulicDriftThreshold then
        -- Reset warning flags when hydraulics are healthy (so warnings trigger again if they degrade)
        spec.hasShownDriftWarning = false
        spec.hasShownDriftMidpointWarning = false
        return
    end

    -- v1.4.0: Show one-time warning when drift conditions are first detected
    -- v1.6.0: Only show if player is controlling this vehicle
    if not spec.hasShownDriftWarning and UsedPlusMaintenance.shouldShowWarning(vehicle) then
        local reliabilityPercent = math.floor(hydraulicReliability * 100)
        if not g_dedicatedServer then
            g_currentMission:showBlinkingWarning(
                string.format(g_i18n:getText("usedPlus_hydraulicWeak") or "Hydraulics weak (%d%%) - implements may drift!", reliabilityPercent),
                4000
            )
        end
        spec.hasShownDriftWarning = true
        UsedPlus.logDebug(string.format("Hydraulic drift warning shown: %d%% reliability", reliabilityPercent))
    end

    -- Get current damage - amplifies drift speed but doesn't gate it
    local damage = 0
    if vehicle.getDamageAmount then
        damage = vehicle:getDamageAmount() or 0
    end

    -- Calculate drift speed based on reliability (lower = faster drift)
    -- Damage amplifies drift speed (up to 3x at 100% damage)
    local baseSpeed = UsedPlusMaintenance.CONFIG.hydraulicDriftSpeed
    local reliabilityFactor = 1 - hydraulicReliability  -- 0.5 reliability = 0.5 factor
    local damageMultiplier = 1.0 + (damage * 2.0)  -- 0% damage = 1x, 100% = 3x

    -- v2.5.2: Low hydraulic fluid makes drift faster (fluid pressure is what holds implements up!)
    local fluidMultiplier = UsedPlusMaintenance.getHydraulicFluidSeverityMultiplier(vehicle)

    local driftSpeed = baseSpeed * reliabilityFactor * damageMultiplier * fluidMultiplier * (dt / 1000)  -- Convert to per-second

    -- Check all child vehicles (attached implements)
    local childVehicles = vehicle:getChildVehicles()
    if childVehicles then
        for _, childVehicle in pairs(childVehicles) do
            -- Pass parent spec so child can trigger midpoint warning
            UsedPlusMaintenance.applyHydraulicDriftToVehicle(childVehicle, driftSpeed, dt, spec)
        end
    end
end

--[[
    Apply hydraulic drift to a single vehicle's cylindered tools
    @param vehicle - The implement vehicle to check
    @param driftSpeed - How fast to drift (radians per second)
    @param dt - Delta time in milliseconds
    @param parentSpec - The parent vehicle's UsedPlusMaintenance spec (for warning flags)
]]
function UsedPlusMaintenance.applyHydraulicDriftToVehicle(vehicle, driftSpeed, dt, parentSpec)
    if vehicle.spec_cylindered == nil then return end

    local spec = vehicle.spec_cylindered
    local movingTools = spec.movingTools

    if movingTools == nil then return end

    for i, tool in pairs(movingTools) do
        -- Only process if tool is NOT actively being moved by player
        if tool.move == 0 and tool.node and tool.rotationAxis then
            local curRot = {getRotation(tool.node)}
            local currentAngle = curRot[tool.rotationAxis] or 0

            -- Check if tool is raised (near max rotation)
            local maxRot = tool.rotMax or 0
            local minRot = tool.rotMin or 0

            -- Only drift if above 50% of range (considered "raised")
            local range = maxRot - minRot
            local midpoint = minRot + (range * 0.5)

            if currentAngle > midpoint then
                -- Apply drift toward minimum (lowering)
                local newAngle = currentAngle - driftSpeed

                -- Don't go below midpoint
                if newAngle > midpoint then
                    curRot[tool.rotationAxis] = newAngle
                    setRotation(tool.node, curRot[1], curRot[2], curRot[3])

                    -- Mark dirty for network sync
                    if Cylindered and Cylindered.setDirty then
                        Cylindered.setDirty(vehicle, tool)
                    end

                    -- Only log occasionally to avoid spam
                    if math.random() < 0.01 then
                        UsedPlus.logTrace("Hydraulic drift active on implement")
                    end
                else
                    -- v1.4.0: Implement just reached midpoint (fully drifted down)
                    -- Show warning once per session when this happens
                    if parentSpec and not parentSpec.hasShownDriftMidpointWarning then
                        g_currentMission:addIngameNotification(
                            FSBaseMission.INGAME_NOTIFICATION_INFO,
                            g_i18n:getText("usedPlus_hydraulicDrifted") or "Implement lowered due to hydraulic failure"
                        )
                        parentSpec.hasShownDriftMidpointWarning = true
                        UsedPlus.logDebug("Hydraulic drift midpoint warning shown - implement fully lowered")
                    end
                end
            end
        end
    end
end

UsedPlus.logDebug("MaintenanceSteering module loaded")
