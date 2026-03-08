--[[
    MaintenanceTires.lua
    Tire wear, friction, quality, and flat tire functions

    Extracted from UsedPlusMaintenance.lua for modularity
]]

-- Ensure UsedPlusMaintenance table exists (modules load before main spec)
UsedPlusMaintenance = UsedPlusMaintenance or {}

--[[
    Track distance traveled per-frame for tire wear calculation
    Uses 3D position delta to measure actual distance moved

    v2.8.0: Also tracks per-wheel distances for unified tire tracking
    This ensures ALL vehicles have tire wear tracked, regardless of UYT support
]]
function UsedPlusMaintenance.trackDistanceTraveled(vehicle, dt)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Get current position
    local x, y, z = getWorldTranslation(vehicle.rootNode)
    local currentPos = {x = x, y = y, z = z}

    -- Calculate distance from last position
    if spec.lastPosition ~= nil then
        local dx = currentPos.x - spec.lastPosition.x
        local dy = currentPos.y - spec.lastPosition.y
        local dz = currentPos.z - spec.lastPosition.z
        local distance = math.sqrt(dx*dx + dy*dy + dz*dz)

        -- Only count if moving (ignore tiny movements/jitter)
        if distance > 0.01 then
            spec.distanceTraveled = (spec.distanceTraveled or 0) + distance

            -- v2.8.0: Track per-wheel distances (for unified tire tracking)
            -- Initialize per-wheel tracking if needed
            if not spec.wheelDistances then
                spec.wheelDistances = {}
                spec.wheelConditions = {}
                local wheelCount = 4  -- Track up to 4 wheels
                if vehicle.spec_wheels and vehicle.spec_wheels.wheels then
                    wheelCount = math.min(#vehicle.spec_wheels.wheels, 4)
                end
                for i = 1, wheelCount do
                    spec.wheelDistances[i] = 0
                    spec.wheelConditions[i] = spec.tireCondition or 1.0
                end
            end

            -- Update per-wheel distances (all wheels travel same distance for now)
            for i = 1, #spec.wheelDistances do
                spec.wheelDistances[i] = spec.wheelDistances[i] + distance
            end
        end
    end

    spec.lastPosition = currentPos
end

--[[
    Apply tire wear based on accumulated distance
    Called every 1 second from periodic checks

    v2.3.0: Quality and DNA-based wear multipliers
    - Retread tires wear 2x faster, Quality tires wear 33% slower
    - Lemons (low DNA) are harder on tires, workhorses (high DNA) are gentler
    - When UYT is installed, also modifies UYT's distance tracking
]]
function UsedPlusMaintenance.applyTireWear(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end
    if spec.hasFlatTire then return end  -- No additional wear with flat

    local config = UsedPlusMaintenance.CONFIG

    -- Convert accumulated distance to km
    local distanceKm = (spec.distanceTraveled or 0) / 1000

    if distanceKm > 0 then
        -- v2.3.0: Calculate quality-based wear multiplier
        local qualityWearMult = config.tireNormalWearMult
        if spec.tireQuality == 1 then  -- Retread
            qualityWearMult = config.tireRetreadWearMult
        elseif spec.tireQuality == 3 then  -- Quality
            qualityWearMult = config.tireQualityWearMult
        end

        -- v2.3.0: Calculate DNA-based wear multiplier
        local dnaWearMult = 1.0
        if config.tireDNAWearEnabled then
            local dna = spec.workhorseLemonScale or 0.5
            -- Lemons (DNA=0) get max wear (1.4x), Workhorses (DNA=1) get min wear (0.6x)
            dnaWearMult = config.tireDNAWearMaxMult - (dna * (config.tireDNAWearMaxMult - config.tireDNAWearMinMult))
        end

        -- Combined wear multiplier
        local totalWearMult = qualityWearMult * dnaWearMult

        -- Calculate wear amount with multipliers
        local wearRate = config.tireWearRatePerKm
        local wearAmount = distanceKm * wearRate * totalWearMult

        -- Apply wear to UsedPlus tire condition
        -- v2.8.0: Apply smoothing to reduce UI jitter (EMA factor 0.3 = balanced)
        local rawCondition = math.max(0, (spec.tireCondition or 1.0) - wearAmount)
        spec.tireCondition = Smoothing.emaCondition(rawCondition, spec.tireCondition, 0.3)

        -- v2.8.0: Update per-wheel conditions based on per-wheel distances
        -- This provides native tire tracking even when UYT doesn't support the vehicle
        if spec.wheelDistances and spec.wheelConditions then
            local baseDistance = config.tireWearDistanceBase or 240000  -- 240km default
            for i = 1, #spec.wheelDistances do
                -- Calculate wear from distance traveled
                local wheelWear = math.min(1.0, spec.wheelDistances[i] / baseDistance)
                -- Apply quality and DNA multipliers to per-wheel wear
                local adjustedWear = wheelWear * totalWearMult
                spec.wheelConditions[i] = math.max(0, 1.0 - adjustedWear)
            end
        end

        -- v2.3.0: Apply wear multiplier to UYT if installed
        if ModCompatibility.uytInstalled then
            UsedPlusMaintenance.applyWearMultiplierToUYT(vehicle, totalWearMult, distanceKm)
        end

        -- Reset distance counter
        spec.distanceTraveled = 0

        -- Check for warnings
        if spec.tireCondition <= config.tireCriticalThreshold and not spec.hasShownTireCriticalWarning then
            spec.hasShownTireCriticalWarning = true
            UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_tireCritical"))
        elseif spec.tireCondition <= config.tireWarnThreshold and not spec.hasShownTireWarnWarning then
            spec.hasShownTireWarnWarning = true
            UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_tireWorn"))
        end
    end
end

--[[
    v2.3.0: Apply wear rate multiplier to UYT's tire distance tracking
    UYT calculates wear from distance traveled per wheel. We modify that distance
    to effectively change the wear rate based on tire quality and DNA.

    @param vehicle - The vehicle
    @param wearMult - Combined quality + DNA wear multiplier (e.g., 1.4 for lemons with retreads)
    @param distanceKm - Distance traveled this update in km
]]
function UsedPlusMaintenance.applyWearMultiplierToUYT(vehicle, wearMult, distanceKm)
    if not ModCompatibility.uytInstalled then return end
    if not UseYourTyres then return end
    if not vehicle.spec_wheels or not vehicle.spec_wheels.wheels then return end

    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return end

    -- Initialize tracking if needed
    if not spec.uytPreviousDistances then
        spec.uytPreviousDistances = {}
    end

    -- Distance delta in meters (what we added this frame)
    local distanceMeters = distanceKm * 1000

    -- Apply multiplier to each wheel's UYT distance
    for i, wheel in ipairs(vehicle.spec_wheels.wheels) do
        if wheel.uytTravelledDist ~= nil then
            local prevDist = spec.uytPreviousDistances[i] or 0
            local currentDist = wheel.uytTravelledDist

            -- Only modify if distance increased (wheel is moving)
            if currentDist > prevDist then
                local delta = currentDist - prevDist

                -- If wearMult > 1, add extra distance to simulate faster wear
                -- If wearMult < 1, reduce the distance to simulate slower wear
                if wearMult ~= 1.0 then
                    local adjustedDelta = delta * wearMult
                    local adjustment = adjustedDelta - delta
                    wheel.uytTravelledDist = currentDist + adjustment
                end
            end

            -- Track for next update
            spec.uytPreviousDistances[i] = wheel.uytTravelledDist
        end
    end
end

--[[
    Check for tire-related malfunctions (flat tire, low traction)
    Called every 1 second from periodic checks
    v1.8.0: Defers flat tire trigger to UYT/RVB when those mods are installed
    v2.3.0: When UYT installed, uses UYT wear to influence flat probability (NOT defer)
]]
function UsedPlusMaintenance.checkTireMalfunctions(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG

    -- Skip if already have flat tire
    if spec.hasFlatTire then return end

    -- v2.8.0: Check global malfunction cooldown (prevents cascade failures)
    if UsedPlusMaintenance.isInGlobalCooldown(vehicle) then return end

    -- v2.3.0: Determine effective tire condition for flat tire check
    -- When UYT is installed, use UYT's worst tire wear to influence probability
    -- This creates a unified experience where UYT wear affects flat tire chance
    local effectiveWear = 1.0 - (spec.tireCondition or 1.0)  -- Default: use our condition

    if ModCompatibility and ModCompatibility.uytInstalled then
        -- Use the worst UYT tire wear to influence flat probability
        local uytWorstWear = ModCompatibility.getWorstUYTTireWear(vehicle)
        if uytWorstWear > 0 then
            -- Blend UYT wear with our condition - UYT takes priority when it has data
            -- More worn UYT tires = higher flat probability
            effectiveWear = math.max(effectiveWear, uytWorstWear)
        end
    end

    local effectiveCondition = 1.0 - effectiveWear

    -- v1.8.0: Check if we should defer flat tire to RVB (but NOT UYT - we integrate with UYT)
    -- RVB has its own tire failure mechanics, UYT doesn't have flat tires at all
    local shouldDeferFlatTire = ModCompatibility and ModCompatibility.rvbInstalled

    -- Check for flat tire (only if tires are worn and vehicle is moving)
    if config.enableFlatTire and effectiveCondition < config.flatTireThreshold and not shouldDeferFlatTire then
        -- Calculate chance based on effective tire condition and quality
        local conditionFactor = 1 - (effectiveCondition / config.flatTireThreshold)

        -- v2.3.0: When UYT installed, flat chance increases with UYT wear
        -- Base chance scales from 1x at 0% wear to 3x at 100% wear
        local uytWearBonus = 1.0
        if ModCompatibility and ModCompatibility.uytInstalled then
            local uytWorstWear = ModCompatibility.getWorstUYTTireWear(vehicle)
            uytWearBonus = 1.0 + (uytWorstWear * 2.0)  -- 1x to 3x based on UYT wear
        end

        local chance = config.flatTireBaseChance * conditionFactor * (spec.tireFailureMultiplier or 1.0) * uytWearBonus

        if math.random() < chance then
            -- Flat tire!
            spec.hasFlatTire = true
            spec.flatTireSide = math.random() < 0.5 and -1 or 1  -- Random left or right
            spec.hasShownFlatTireWarning = true
            spec.failureCount = (spec.failureCount or 0) + 1

            -- v2.8.0: Record malfunction time for global cooldown
            UsedPlusMaintenance.recordMalfunctionTime(vehicle)

            local sideText = spec.flatTireSide < 0 and "left" or "right"
            UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_flatTire"))
            UsedPlus.logDebug(string.format("Flat tire triggered on %s side for %s (UYT bonus: %.1fx)",
                sideText, vehicle:getName(), uytWearBonus))
        end
    end

    -- Check for low traction warning (weather-aware)
    if config.enableLowTraction and spec.tireCondition < config.lowTractionThreshold then
        if not spec.hasShownLowTractionWarning then
            -- Check weather conditions
            local isWet = false
            local isSnow = false

            if g_currentMission and g_currentMission.environment then
                local weather = g_currentMission.environment.weather
                if weather then
                    isWet = weather:getIsRaining() or false
                    -- v2.9.1: getSnowHeight doesn't exist - use snowDepth property or check season
                    if weather.snowDepth then
                        isSnow = weather.snowDepth > 0
                    elseif g_currentMission.environment.currentSeason == Environment.SEASON_WINTER then
                        -- Fallback: assume snow in winter
                        isSnow = true
                    end
                end
            end

            if isWet or isSnow or spec.tireCondition < config.lowTractionThreshold * 0.5 then
                spec.hasShownLowTractionWarning = true
                UsedPlusMaintenance.showWarning(vehicle, g_i18n:getText("usedplus_warning_lowTraction"))
            end
        end
    end
end

--[[
    Get current tire traction multiplier based on condition, quality, and weather
    Used by friction system and display
]]
function UsedPlusMaintenance.getTireTractionMultiplier(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return 1.0 end

    local config = UsedPlusMaintenance.CONFIG
    local condition = spec.tireCondition or 1.0
    local qualityTraction = spec.tireMaxTraction or 1.0

    -- Base traction from tire condition (linear interpolation)
    -- At 100% condition: 100% of quality traction
    -- At 0% condition: 60% of quality traction (CONFIG.tireFrictionMinMultiplier)
    local minFriction = config.tireFrictionMinMultiplier
    local conditionTraction = minFriction + (condition * (1.0 - minFriction))

    local finalTraction = qualityTraction * conditionTraction

    -- Weather penalties (only if tire friction is enabled)
    if config.enableTireFriction then
        local isWet = false
        local isSnow = false

        if g_currentMission and g_currentMission.environment then
            local weather = g_currentMission.environment.weather
            if weather then
                isWet = weather:getIsRaining() or false
                -- Check for snow on ground
                if weather.getSnowHeight then
                    isSnow = weather:getSnowHeight() > 0
                end
            end
        end

        if isSnow then
            finalTraction = finalTraction * (1.0 - config.tireFrictionSnowPenalty)
        elseif isWet then
            finalTraction = finalTraction * (1.0 - config.tireFrictionWetPenalty)
        end
    end

    -- Flat tire = severe traction loss
    if spec.hasFlatTire then
        finalTraction = finalTraction * 0.5
    end

    return math.max(0.3, finalTraction)  -- Never below 30%
end

--[[
    v1.7.0: Calculate tire friction scale for a vehicle
    Returns a multiplier (0.1 to 1.1) based on:
    - Tire condition (worn tires = less grip)
    - Tire quality (retread=0.85, normal=1.0, quality=1.1)
    - Flat tire (severely reduced)
]]
function UsedPlusMaintenance.getTireFrictionScale(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return 1.0 end

    local config = UsedPlusMaintenance.CONFIG

    -- Base friction from tire quality
    local qualityScale = spec.tireMaxTraction or 1.0

    -- Condition-based friction reduction
    -- New tires (1.0) = full friction
    -- Worn tires (0.3) = ~85% friction
    -- Critical tires (0.15) = ~70% friction
    local condition = spec.tireCondition or 1.0
    local conditionScale = 0.7 + (condition * 0.3)  -- Range: 0.7 to 1.0

    -- Flat tire = severe friction loss on that side
    local flatTireScale = 1.0
    if spec.hasFlatTire then
        flatTireScale = config.flatTireFrictionMult or 0.3  -- 30% friction with flat
    end

    -- Combine all factors
    local finalScale = qualityScale * conditionScale * flatTireScale

    -- Clamp to reasonable range
    return math.max(0.1, math.min(1.1, finalScale))
end

--[[
    v1.7.0: Hook into WheelPhysics.updateTireFriction
    Modifies tire friction based on UsedPlus tire condition system
    Pattern from: FS25_useYourTyres
]]
function UsedPlusMaintenance.hookTireFriction(physWheel)
    -- Safety check: ensure physWheel and vehicle exist
    if physWheel == nil or physWheel.vehicle == nil then return end
    if not physWheel.vehicle.isServer then return end
    if not physWheel.vehicle.isAddedToPhysics then return end

    local vehicle = physWheel.vehicle
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG
    if not config.enableTireFriction then return end

    -- Calculate our friction scale
    local usedPlusFrictionScale = UsedPlusMaintenance.getTireFrictionScale(vehicle)

    -- Only modify if we have a meaningful change
    if usedPlusFrictionScale >= 0.99 and usedPlusFrictionScale <= 1.01 then return end

    -- Apply friction modification
    -- The base game (or other mods like useYourTyres) will have already called
    -- setWheelShapeTireFriction, so we need to call it again with our modifier
    local frictionCoeff = physWheel.frictionScale * physWheel.tireGroundFrictionCoeff * usedPlusFrictionScale

    setWheelShapeTireFriction(
        physWheel.wheel.node,
        physWheel.wheelShape,
        physWheel.maxLongStiffness,
        physWheel.maxLatStiffness,
        physWheel.maxLatStiffnessLoad,
        frictionCoeff
    )
end

--[[
    Set tire quality and apply modifiers
    Called when tires are replaced/retreaded
    @param quality 1=Retread, 2=Normal, 3=Quality
]]
function UsedPlusMaintenance.setTireQuality(vehicle, quality)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local config = UsedPlusMaintenance.CONFIG

    spec.tireQuality = quality
    spec.tireCondition = 1.0  -- New tires
    spec.hasFlatTire = false
    spec.flatTireSide = 0
    spec.hasShownTireWarnWarning = false
    spec.hasShownTireCriticalWarning = false
    spec.hasShownFlatTireWarning = false
    spec.hasShownLowTractionWarning = false

    if quality == 1 then  -- Retread
        spec.tireMaxTraction = config.tireRetreadTractionMult
        spec.tireFailureMultiplier = config.tireRetreadFailureMult
    elseif quality == 3 then  -- Quality
        spec.tireMaxTraction = config.tireQualityTractionMult
        spec.tireFailureMultiplier = config.tireQualityFailureMult
    else  -- Normal (2)
        spec.tireMaxTraction = config.tireNormalTractionMult
        spec.tireFailureMultiplier = config.tireNormalFailureMult
    end

    -- v2.3.0: Reset UYT distance tracking for accurate wear multiplier application
    spec.uytPreviousDistances = {}

    -- v2.8.0: Reset per-wheel distances and conditions
    if spec.wheelDistances then
        for i = 1, #spec.wheelDistances do
            spec.wheelDistances[i] = 0
            spec.wheelConditions[i] = 1.0  -- New tires = 100% condition
        end
    end

    -- v2.3.0: Sync tire replacement to UYT (resets their distance counters)
    -- Pass quality so retreads can start with pre-existing wear (reconditioned casings)
    if ModCompatibility and ModCompatibility.uytInstalled then
        ModCompatibility.syncTireReplacementWithUYT(vehicle, quality)
    end

    UsedPlus.logDebug(string.format("Tires replaced on %s: quality=%d, traction=%.0f%%, failureMult=%.1f",
        vehicle:getName(), quality, spec.tireMaxTraction * 100, spec.tireFailureMultiplier))
end

--[[
    Fix flat tire (requires tire replacement via Tires dialog)
]]
function UsedPlusMaintenance.repairFlatTire(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    spec.hasFlatTire = false
    spec.flatTireSide = 0
    spec.hasShownFlatTireWarning = false

    if vehicle.raiseDirtyFlags and spec.dirtyFlag then
        vehicle:raiseDirtyFlags(spec.dirtyFlag)
    end

    UsedPlus.logDebug(string.format("Flat tire fixed for %s", vehicle:getName()))
end

UsedPlus.logDebug("MaintenanceTires module loaded")
