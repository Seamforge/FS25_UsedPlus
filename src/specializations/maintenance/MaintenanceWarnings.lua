--[[
    MaintenanceWarnings.lua
    Warning helpers, repair handlers, and malfunction timers

    Extracted from UsedPlusMaintenance.lua for modularity
]]

-- Ensure UsedPlusMaintenance table exists (modules load before main spec)
UsedPlusMaintenance = UsedPlusMaintenance or {}

--[[
    v1.6.0: Check if warnings should be shown for this vehicle
    Warnings should ONLY show when:
    1. Player is actively controlling THIS vehicle (isActiveForInput)
    2. Startup grace period has expired (not immediately after load/purchase)

    This prevents phantom warnings when standing outside vehicles or on game start.
    @param vehicle - The vehicle to check
    @return boolean - true if warnings can be shown, false otherwise
]]
function UsedPlusMaintenance.shouldShowWarning(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return false end

    -- Check startup grace period - no warnings during first few seconds
    if spec.startupGracePeriod and spec.startupGracePeriod > 0 then
        return false
    end

    -- v1.7.3: Use multiple methods to check if player is in/controlling this vehicle
    -- Method 1: Check if player has entered this vehicle
    if vehicle.getIsEntered and vehicle:getIsEntered() then
        return true
    end

    -- Method 2: Check if this is the HUD's controlled vehicle
    if g_currentMission and g_currentMission.controlledVehicle then
        local rootVehicle = vehicle:getRootVehicle()
        if rootVehicle == g_currentMission.controlledVehicle then
            return true
        end
    end

    -- Method 3: Check stored isActiveForInput from last onUpdate frame
    if spec.lastIsActiveForInput then
        return true
    end

    -- Method 4: Fallback to getIsControlled
    if vehicle.getIsControlled and vehicle:getIsControlled() then
        return true
    end

    return false
end

--[[
    Show a blinking warning message to the player
    Only shows if shouldShowWarning returns true
    @param vehicle - The vehicle triggering the warning
    @param message - The warning text to display
    @param duration - Optional duration in ms (default 2500)
    @param malfunctionType - Optional malfunction type for API event
]]
function UsedPlusMaintenance.showWarning(vehicle, message, duration, malfunctionType)
    if not UsedPlusMaintenance.shouldShowWarning(vehicle) then
        return
    end

    -- Client-only: Don't waste server CPU on UI calls
    if g_dedicatedServer then
        return
    end

    duration = duration or 2500

    if g_currentMission and g_currentMission.showBlinkingWarning then
        g_currentMission:showBlinkingWarning(message, duration)
    end

    -- v2.5.2: Fire API event for malfunction if type specified
    if malfunctionType and UsedPlusAPI then
        UsedPlusAPI.fireEvent("onMalfunctionTriggered", vehicle, malfunctionType, message)
    end
end

--[[
    v2.5.2: Helper to fire malfunction ended event
    @param vehicle - The vehicle
    @param malfunctionType - Type of malfunction that ended
]]
function UsedPlusMaintenance.fireMalfunctionEnded(vehicle, malfunctionType)
    if UsedPlusAPI then
        UsedPlusAPI.fireEvent("onMalfunctionEnded", vehicle, malfunctionType)
    end
end

--[[
    v2.5.0: Update malfunction timers and enforce stuck states
    Called every 1 second from periodic checks
]]
function UsedPlusMaintenance.updateMalfunctionTimers(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    local currentTime = g_currentMission.time or 0

    -- Check implement stuck down - also ENFORCE the stuck state
    if spec.implementStuckDown then
        if currentTime >= spec.implementStuckDownEndTime then
            spec.implementStuckDown = false
            UsedPlus.logDebug("Implement stuck down cleared on " .. vehicle:getName())
        else
            -- ENFORCE: If any implement got raised, force it back down!
            if vehicle.getAttachedImplements then
                local implements = vehicle:getAttachedImplements()
                if implements then
                    for _, impl in pairs(implements) do
                        local implement = impl.object
                        if implement and implement.getIsLowered and implement.setLoweredAll then
                            if not implement:getIsLowered() then
                                -- Player tried to raise it - force it back down!
                                implement:setLoweredAll(true)
                                UsedPlus.logTrace("Enforcing stuck DOWN on " .. vehicle:getName())
                            end
                        end
                    end
                end
            end
        end
    end

    -- Check implement stuck up - also ENFORCE the stuck state
    if spec.implementStuckUp then
        if currentTime >= spec.implementStuckUpEndTime then
            spec.implementStuckUp = false
            UsedPlus.logDebug("Implement stuck up cleared on " .. vehicle:getName())
        else
            -- ENFORCE: If any implement got lowered, force it back up!
            if vehicle.getAttachedImplements then
                local implements = vehicle:getAttachedImplements()
                if implements then
                    for _, impl in pairs(implements) do
                        local implement = impl.object
                        if implement and implement.getIsLowered and implement.setLoweredAll then
                            if implement:getIsLowered() then
                                -- Player tried to lower it - force it back up!
                                implement:setLoweredAll(false)
                                UsedPlus.logTrace("Enforcing stuck UP on " .. vehicle:getName())
                            end
                        end
                    end
                end
            end
        end
    end

    -- Check implement pull
    if spec.implementPullActive and currentTime >= spec.implementPullEndTime then
        spec.implementPullActive = false
        UsedPlus.logDebug("Implement pull cleared on " .. vehicle:getName())
    end

    -- Check implement drag
    if spec.implementDragActive and currentTime >= spec.implementDragEndTime then
        spec.implementDragActive = false
        UsedPlus.logDebug("Implement drag cleared on " .. vehicle:getName())
    end

    -- Check reduced turning
    if spec.reducedTurningActive and currentTime >= spec.reducedTurningEndTime then
        spec.reducedTurningActive = false
        UsedPlus.logDebug("Reduced turning cleared on " .. vehicle:getName())
    end
end

--[[
    v2.2.0: Apply repair degradation to UsedPlus systems
    Called when ANY repair completes (shop, RVB, or vanilla)

    Lemons lose more ceiling/durability per repair
    Legendary workhorses (DNA >= 0.90) are IMMUNE to repair degradation

    @param vehicle - The vehicle being repaired
]]
function UsedPlusMaintenance.applyRepairDegradation(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return end

    local dna = spec.workhorseLemonScale or 0.5

    -- Legendary workhorses (DNA >= 0.90) are immune to repair degradation
    if dna >= 0.90 then
        UsedPlus.logDebug(string.format("Legendary workhorse - no repair degradation for %s (DNA %.2f)",
            vehicle:getName(), dna))
        return
    end

    -- Degradation formula: 0-2% ceiling loss per repair based on DNA
    local ceilingDegradation = (1 - dna) * 0.02

    -- Reduce max reliability ceiling (how high reliability can be restored)
    spec.maxReliabilityCeiling = math.max(0.30,
        (spec.maxReliabilityCeiling or 1.0) * (1 - ceilingDegradation))

    -- Also slightly reduce max durability of each component: 0-1% per repair
    local componentDegradation = (1 - dna) * 0.01
    spec.maxEngineDurability = math.max(0.30,
        (spec.maxEngineDurability or 1.0) * (1 - componentDegradation))
    spec.maxHydraulicDurability = math.max(0.30,
        (spec.maxHydraulicDurability or 1.0) * (1 - componentDegradation))
    spec.maxElectricalDurability = math.max(0.30,
        (spec.maxElectricalDurability or 1.0) * (1 - componentDegradation))

    UsedPlus.logDebug(string.format("UsedPlus repair degradation: ceiling=%.1f%%, engine=%.1f%%, hydraulic=%.1f%%, electrical=%.1f%% (DNA %.2f)",
        spec.maxReliabilityCeiling * 100,
        spec.maxEngineDurability * 100,
        spec.maxHydraulicDurability * 100,
        spec.maxElectricalDurability * 100,
        dna))
end

--[[
    v2.2.0: Apply breakdown degradation to UsedPlus systems
    Called when UsedPlus detects a failure event (stall, cutout, drift, etc.)

    Everyone loses ceiling/durability on breakdown, but lemons lose MORE
    Legendary workhorses (DNA >= 0.95) take only 30% breakdown damage

    @param vehicle - The vehicle with the breakdown
    @param component - The component that failed (Engine, Hydraulic, Electrical)
]]
function UsedPlusMaintenance.applyBreakdownDegradation(vehicle, component)
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return end

    local dna = spec.workhorseLemonScale or 0.5

    -- Base: 3% ceiling loss, Lemon bonus: 0-5% extra
    local baseDegradation = 0.03
    local lemonBonus = (1 - dna) * 0.05
    local totalDegradation = baseDegradation + lemonBonus

    -- Legendary workhorses (DNA >= 0.95) take only 30% breakdown damage
    if dna >= 0.95 then
        totalDegradation = totalDegradation * 0.3
    end

    -- Reduce overall ceiling
    spec.maxReliabilityCeiling = math.max(0.30,
        (spec.maxReliabilityCeiling or 1.0) * (1 - totalDegradation))

    -- Reduce max durability of the specific component that failed (extra 50% damage)
    local componentExtraDamage = totalDegradation * 1.5
    if component == "Engine" then
        spec.maxEngineDurability = math.max(0.30,
            (spec.maxEngineDurability or 1.0) * (1 - componentExtraDamage))
    elseif component == "Hydraulic" then
        spec.maxHydraulicDurability = math.max(0.30,
            (spec.maxHydraulicDurability or 1.0) * (1 - componentExtraDamage))
    elseif component == "Electrical" then
        spec.maxElectricalDurability = math.max(0.30,
            (spec.maxElectricalDurability or 1.0) * (1 - componentExtraDamage))
    end

    -- Increment breakdown counter
    spec.failureCount = (spec.failureCount or 0) + 1

    UsedPlus.logDebug(string.format("UsedPlus breakdown on %s: ceiling=%.1f%%, DNA=%.2f, degradation=%.1f%%",
        component or "unknown", spec.maxReliabilityCeiling * 100, dna, totalDegradation * 100))
end

--[[
    PUBLIC API: Update reliability after repair
    Called from VehicleSellingPointExtension when repair completes

    v1.4.0: Now implements Workhorse/Lemon Scale system
    v2.2.0: UNIFIED degradation - also degrades component durability and RVB parts
    - Lemons (0.0) lose 2% ceiling per repair
    - Workhorses (DNA >= 0.90) are IMMUNE to repair degradation
    - Reliability scores are capped by BOTH overall ceiling AND component durability
]]
function UsedPlusMaintenance.onVehicleRepaired(vehicle, repairCost)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Update maintenance history
    spec.repairCount = spec.repairCount + 1
    spec.totalRepairCost = spec.totalRepairCost + repairCost
    spec.lastRepairDate = g_currentMission.environment.dayTime or 0

    -- v2.2.0: Apply UNIFIED degradation (ceiling + component durability)
    -- This replaces the old v1.4.0 inline ceiling degradation
    if UsedPlusMaintenance.CONFIG.enableLemonScale then
        UsedPlusMaintenance.applyRepairDegradation(vehicle)
    end

    -- v2.2.0: Apply repair bonus, capped by BOTH overall ceiling AND component durability
    local repairBonus = UsedPlusMaintenance.CONFIG.reliabilityRepairBonus

    -- Engine: capped by overall ceiling AND component durability
    local engineCap = math.min(
        spec.maxReliabilityCeiling or 1.0,
        spec.maxEngineDurability or 1.0
    )
    spec.engineReliability = math.min(engineCap, spec.engineReliability + repairBonus)

    -- Hydraulic: capped by overall ceiling AND component durability
    local hydraulicCap = math.min(
        spec.maxReliabilityCeiling or 1.0,
        spec.maxHydraulicDurability or 1.0
    )
    spec.hydraulicReliability = math.min(hydraulicCap, spec.hydraulicReliability + repairBonus)

    -- Electrical: capped by overall ceiling AND component durability
    local electricalCap = math.min(
        spec.maxReliabilityCeiling or 1.0,
        spec.maxElectricalDurability or 1.0
    )
    spec.electricalReliability = math.min(electricalCap, spec.electricalReliability + repairBonus)

    -- v2.2.0: Also apply RVB degradation if RVB is installed
    if ModCompatibility and ModCompatibility.rvbInstalled then
        ModCompatibility.applyRVBRepairDegradation(vehicle)
    end

    -- Reset warning flags so they can trigger again if problems return
    spec.hasShownDriftWarning = false
    spec.hasShownDriftMidpointWarning = false
    spec.speedWarningTimer = 0

    -- v2.15.0: Reset steering pull state - workshop repair clears steering issues
    spec.steeringPullDirection = 0
    spec.steeringPullInitialized = false
    spec.steeringPullSurgeActive = false
    spec.steeringPullSurgeTimer = 0
    spec.hasShownPullWarning = false

    UsedPlus.logDebug(string.format("Vehicle repaired: %s - ceiling=%.1f%%, engine=%.2f (cap %.2f), hydraulic=%.2f (cap %.2f), electrical=%.2f (cap %.2f)",
        vehicle:getName(),
        (spec.maxReliabilityCeiling or 1.0) * 100,
        spec.engineReliability, engineCap,
        spec.hydraulicReliability, hydraulicCap,
        spec.electricalReliability, electricalCap))
end

--============================================================================
-- v2.1.0: CROSS-MOD DEFERRED SYNC
-- Syncs stored RVB/UYT data when those mods are installed after vehicle purchase
--============================================================================

--[[
    Check if we have stored RVB/UYT data that needs to be synced
    Called on vehicle load and periodically
]]
function UsedPlusMaintenance.checkAndSyncCrossModData(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Check if we need to sync RVB data
    if spec.storedRvbPartsData and not spec.rvbDataSynced then
        if ModCompatibility and ModCompatibility.rvbInstalled then
            -- RVB is now installed! Sync the stored data
            local success = ModCompatibility.initializeRVBPartsFromListing(vehicle, spec.storedRvbPartsData)
            if success then
                spec.rvbDataSynced = true
                UsedPlus.logInfo(string.format("Deferred RVB sync completed for %s", vehicle:getName()))
            end
        end
    end

    -- Check if we need to sync tire data
    if spec.storedTireConditions and not spec.tireDataSynced then
        if ModCompatibility and ModCompatibility.uytInstalled then
            -- UYT is now installed! Sync the stored data
            local success = ModCompatibility.initializeTiresFromListing(vehicle, spec.storedTireConditions)
            if success then
                spec.tireDataSynced = true
                UsedPlus.logInfo(string.format("Deferred UYT tire sync completed for %s", vehicle:getName()))
            end
        end
    end
end

--[[
    Store RVB/UYT data on the vehicle for persistence and deferred sync
    Called from ModCompatibility.applyListingDataToVehicle
]]
function UsedPlusMaintenance.storeListingData(vehicle, rvbPartsData, tireConditions)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    if rvbPartsData then
        spec.storedRvbPartsData = rvbPartsData
        -- If RVB is installed now, mark as synced
        if ModCompatibility and ModCompatibility.rvbInstalled then
            spec.rvbDataSynced = true
        end
        UsedPlus.logDebug(string.format("Stored RVB parts data for %s (synced=%s)",
            vehicle:getName(), tostring(spec.rvbDataSynced)))
    end

    if tireConditions then
        spec.storedTireConditions = tireConditions
        -- If UYT is installed now, mark as synced
        if ModCompatibility and ModCompatibility.uytInstalled then
            spec.tireDataSynced = true
        end
        UsedPlus.logDebug(string.format("Stored tire conditions for %s (synced=%s)",
            vehicle:getName(), tostring(spec.tireDataSynced)))
    end
end

UsedPlus.logDebug("MaintenanceWarnings module loaded")
