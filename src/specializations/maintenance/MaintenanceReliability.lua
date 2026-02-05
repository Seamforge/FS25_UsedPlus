--[[
    MaintenanceReliability.lua
    DNA system, reliability scoring, seizure escalation, inspection cache

    Extracted from UsedPlusMaintenance.lua for modularity
]]

-- Ensure UsedPlusMaintenance table exists (modules load before main spec)
UsedPlusMaintenance = UsedPlusMaintenance or {}

--[[
    Generate workhorse/lemon scale for a NEW vehicle (purchased from dealership)
    Bell curve centered at 0.6 (slightly workhorse-biased)
]]
function UsedPlusMaintenance.generateNewVehicleScale()
    -- Bell curve centered at 0.6 using sum of randoms
    local r1 = math.random()
    local r2 = math.random()
    local scale = 0.3 + (r1 * 0.5) + (r2 * 0.2)
    return math.min(1.0, math.max(0.0, scale))
end

--[[
    Generate workhorse/lemon scale for a USED vehicle (from used market)

    v2.8.0: REBALANCED - Uses positive modifier system instead of hard-clamped ranges.

    The triangular distribution (sum of 2 randoms / 2) is centered at 0.5 with a
    natural bell curve shape. Each quality tier adds a POSITIVE modifier to shift
    the center point, making workhorses more likely at higher tiers while keeping
    BOTH outcomes (lemon and workhorse) achievable at every tier.

    Expected outcomes:
    - Poor:      ~10% workhorse (>0.80), ~16% lemon (<0.30)
    - Any:       ~12% workhorse, ~14% lemon
    - Fair:      ~14% workhorse, ~12% lemon
    - Good:      ~17% workhorse, ~9% lemon
    - Excellent: ~20% workhorse, ~7% lemon

    This enables the "diamond in the rough" scenario (finding workhorse at Poor)
    and prevents Excellent from being a guaranteed safe bet.

    @param qualityLevel - Optional quality tier (1=Any, 2=Poor, 3=Fair, 4=Good, 5=Excellent)
    @return scale - DNA value 0.0 (lemon) to 1.0 (workhorse)
]]
function UsedPlusMaintenance.generateUsedVehicleScale(qualityLevel)
    -- === ADMIN PANEL DNA OVERRIDE (ONE-SHOT) ===
    if UsedPlus.forcedDNA then
        local dnaValue = UsedPlus.forcedDNA
        UsedPlus.forcedDNA = nil  -- Clear immediately (one-shot behavior)

        -- Log consumption for debugging
        local label = "AVERAGE"
        if dnaValue < 0.3 then
            label = "LEMON"
        elseif dnaValue > 0.7 then
            label = "WORKHORSE"
        end

        UsedPlus.logInfo(string.format("DNA OVERRIDE CONSUMED: Forced %.2f (%s) for vehicle generation",
            dnaValue, label))

        return dnaValue
    end

    -- === NORMAL GENERATION (existing code continues below) ===
    -- Base roll: triangular distribution (sum of 2 randoms / 2)
    -- Centers at 0.5, ranges 0.0-1.0, natural bell curve peaks in middle
    local r1 = math.random()
    local r2 = math.random()
    local baseRoll = (r1 + r2) / 2

    -- Get tier modifier (default to Fair/neutral if invalid tier)
    local modifier = UsedPlusMaintenance.DNA_TIER_MODIFIERS[qualityLevel]
    if modifier == nil then
        modifier = UsedPlusMaintenance.DNA_TIER_MODIFIERS[3]  -- Fair = 0.06
    end

    -- Apply modifier and clamp to valid range
    local scale = baseRoll + modifier
    scale = math.min(1.0, math.max(0.0, scale))

    UsedPlus.logDebug(string.format(
        "Generated DNA: qualityLevel=%d, modifier=%.2f, baseRoll=%.3f, result=%.3f",
        qualityLevel or 0, modifier, baseRoll, scale))

    return scale
end

--[[
    Calculate initial ceiling for used vehicle based on previous ownership
    Simulates unknown repair history from age and hours
    @param workhorseLemonScale - The vehicle's DNA (0.0-1.0)
    @param estimatedPreviousRepairs - Estimated from age/hours
    @return Initial ceiling value (0.3-1.0)
]]
function UsedPlusMaintenance.calculateInitialCeiling(workhorseLemonScale, estimatedPreviousRepairs)
    -- Degradation rate based on DNA: Lemons (0.0) = 1%, Workhorses (1.0) = 0%
    local degradationRate = (1 - workhorseLemonScale) * UsedPlusMaintenance.CONFIG.ceilingDegradationMax
    local totalDegradation = degradationRate * estimatedPreviousRepairs
    local ceiling = 1.0 - totalDegradation
    return math.max(UsedPlusMaintenance.CONFIG.minReliabilityCeiling, ceiling)
end

--[[
    PUBLIC API: Generate random reliability scores for a used vehicle listing
    Called from UsedVehicleManager when generating sale items

    v1.4.0: Now includes workhorseLemonScale and calculates initial ceiling
    based on estimated previous repairs from age/hours

    @param damage - Vehicle damage level (0-1)
    @param age - Vehicle age in years
    @param hours - Operating hours
    @param qualityLevel - Optional quality tier (1=Any, 2=Poor, 3=Fair, 4=Good, 5=Excellent)
                          Affects DNA distribution - higher tiers bias toward workhorses
]]
function UsedPlusMaintenance.generateReliabilityScores(damage, age, hours, qualityLevel)
    -- Base reliability inversely related to damage
    local reliabilityBase = 1 - (damage or 0)

    -- Add variance - a high-damage vehicle MIGHT have good engine, or might not
    local function randomVariance(maxVariance)
        return (math.random() * 2 - 1) * maxVariance
    end

    local engineReliability = reliabilityBase + randomVariance(0.2)
    local hydraulicReliability = reliabilityBase + randomVariance(0.25)
    local electricalReliability = reliabilityBase + randomVariance(0.15)

    -- Clamp to 0.1-1.0 (never completely dead, never perfect if used)
    engineReliability = math.max(0.1, math.min(1.0, engineReliability))
    hydraulicReliability = math.max(0.1, math.min(1.0, hydraulicReliability))
    electricalReliability = math.max(0.1, math.min(1.0, electricalReliability))

    -- v1.4.0: Generate workhorse/lemon scale (DNA correlated with quality tier)
    local workhorseLemonScale = UsedPlusMaintenance.generateUsedVehicleScale(qualityLevel)

    -- v1.4.0: Estimate previous repairs from age/hours and calculate initial ceiling
    local estimatedRepairs = math.floor((hours or 0) / 500)  -- ~1 repair per 500 hours
    estimatedRepairs = estimatedRepairs + (age or 0)  -- Plus ~1 per year
    local maxReliabilityCeiling = UsedPlusMaintenance.calculateInitialCeiling(
        workhorseLemonScale, estimatedRepairs)

    -- Cap reliability scores by the calculated ceiling
    engineReliability = math.min(engineReliability, maxReliabilityCeiling)
    hydraulicReliability = math.min(hydraulicReliability, maxReliabilityCeiling)
    electricalReliability = math.min(electricalReliability, maxReliabilityCeiling)

    -- v1.7.0: Generate tire condition based on age and hours
    -- Tires wear roughly 10% per 500 operating hours
    local tireWearFromHours = (hours or 0) / 5000  -- 10% per 500 hours
    local tireWearFromAge = (age or 0) * 0.05  -- 5% per year from age
    local tireCondition = math.max(0.1, 1.0 - tireWearFromHours - tireWearFromAge + randomVariance(0.1))
    tireCondition = math.min(1.0, tireCondition)

    -- Tire quality - used vehicles typically have normal tires
    -- Rarely retreads (lemons) or quality (workhorses)
    local tireQuality = 2  -- Normal
    if workhorseLemonScale < 0.3 then
        -- Lemons may have retreads
        if math.random() < 0.3 then
            tireQuality = 1  -- Retread
        end
    elseif workhorseLemonScale > 0.7 then
        -- Workhorses may have quality tires
        if math.random() < 0.2 then
            tireQuality = 3  -- Quality
        end
    end

    -- v1.7.0: Generate fluid levels (oil tends to be ok, hydraulic varies more)
    local oilLevel = math.max(0.2, 1.0 - (hours or 0) / 20000 + randomVariance(0.2))  -- Depletes slowly
    oilLevel = math.min(1.0, oilLevel)

    local hydraulicFluidLevel = math.max(0.3, 1.0 - (hours or 0) / 15000 + randomVariance(0.25))
    hydraulicFluidLevel = math.min(1.0, hydraulicFluidLevel)

    -- Lemons more likely to have fluid issues
    if workhorseLemonScale < 0.3 then
        oilLevel = oilLevel * 0.7
        hydraulicFluidLevel = hydraulicFluidLevel * 0.6
    end

    -- v1.9.4: Generate leak status for used vehicles
    -- Leak probability increases with age, hours, and lemon status
    local leakBaseChance = 0.05 + (age or 0) * 0.02 + (hours or 0) / 10000

    -- Lemons have higher leak chance, workhorses lower
    local leakModifier = 1.5 - workhorseLemonScale  -- 1.5 for lemons, 0.5 for workhorses
    leakBaseChance = leakBaseChance * leakModifier

    local hasOilLeak = math.random() < leakBaseChance * 0.8
    local hasHydraulicLeak = math.random() < leakBaseChance * 0.6
    local hasFuelLeak = math.random() < leakBaseChance * 0.3

    -- Leak severity (1.0 = slow drip, 3.0 = significant leak)
    local oilLeakSeverity = hasOilLeak and (1.0 + math.random() * 2.0) or 0
    local hydraulicLeakSeverity = hasHydraulicLeak and (1.0 + math.random() * 2.0) or 0
    local fuelLeakMultiplier = hasFuelLeak and (1.0 + math.random() * 0.5) or 1.0

    UsedPlus.logDebug(string.format("Generated reliability: DNA=%.2f, ceiling=%.1f%%, est.repairs=%d, tires=%.0f%%, oil=%.0f%%, leaks=[oil=%s,hyd=%s,fuel=%s]",
        workhorseLemonScale, maxReliabilityCeiling * 100, estimatedRepairs, tireCondition * 100, oilLevel * 100,
        tostring(hasOilLeak), tostring(hasHydraulicLeak), tostring(hasFuelLeak)))

    return {
        engineReliability = engineReliability,
        hydraulicReliability = hydraulicReliability,
        electricalReliability = electricalReliability,
        workhorseLemonScale = workhorseLemonScale,
        maxReliabilityCeiling = maxReliabilityCeiling,
        wasInspected = false,

        -- v1.7.0: Tire and fluid data
        tireCondition = tireCondition,
        tireQuality = tireQuality,
        oilLevel = oilLevel,
        hydraulicFluidLevel = hydraulicFluidLevel,

        -- v1.9.4: Leak status for inspection reports
        hasOilLeak = hasOilLeak,
        oilLeakSeverity = oilLeakSeverity,
        hasHydraulicLeak = hasHydraulicLeak,
        hydraulicLeakSeverity = hydraulicLeakSeverity,
        hasFuelLeak = hasFuelLeak,
        fuelLeakMultiplier = fuelLeakMultiplier
    }
end

--[[
    PUBLIC API: Get rating text for reliability score
    Returns rating string and icon for inspection reports
]]
function UsedPlusMaintenance.getRatingText(reliability)
    if reliability >= 0.8 then
        return "Good", "✓"
    elseif reliability >= 0.6 then
        return "Acceptable", "✓"
    elseif reliability >= 0.4 then
        return "Below Average", "⚠"
    elseif reliability >= 0.2 then
        return "Poor", "⚠"
    else
        return "Critical", "✗"
    end
end

--[[
    PUBLIC API: Generate inspector notes based on reliability data
    Used in inspection reports
]]
function UsedPlusMaintenance.generateInspectorNotes(reliabilityData)
    local notes = {}

    if reliabilityData.engineReliability < 0.5 then
        table.insert(notes, "Engine shows signs of hard use. Expect occasional stalling under load.")
    end
    if reliabilityData.hydraulicReliability < 0.5 then
        table.insert(notes, "Hydraulic system worn. Implements may drift when raised.")
    end
    if reliabilityData.electricalReliability < 0.5 then
        table.insert(notes, "Electrical issues detected. Implements may cut out unexpectedly.")
    end

    if #notes == 0 then
        table.insert(notes, "Vehicle in acceptable mechanical condition.")
    end

    return table.concat(notes, " ")
end

--[[
    PUBLIC API: Get current vehicle state for inspection comparison
    Returns hours, damage, wear values
]]
function UsedPlusMaintenance.getCurrentVehicleState(vehicle)
    local hours = 0
    if vehicle.getOperatingTime then
        hours = math.floor((vehicle:getOperatingTime() or 0) / 3600000)  -- Convert ms to hours
    end

    local damage = 0
    if vehicle.getDamageAmount then
        damage = vehicle:getDamageAmount() or 0
    end

    local wear = 0
    if vehicle.getWearTotalAmount then
        wear = vehicle:getWearTotalAmount() or 0
    end

    return {
        hours = hours,
        damage = damage,
        wear = wear
    }
end

--[[
    PUBLIC API: Check if inspection cache is still valid
    Returns true if cache exists AND vehicle state hasn't changed significantly
    @param vehicle - The vehicle to check
    @param tolerance - How much change is allowed before requiring new inspection (default 0.05 = 5%)
]]
function UsedPlusMaintenance.isInspectionCacheValid(vehicle, tolerance)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then
        return false
    end

    -- No cache exists
    if not spec.hasInspectionCache then
        return false
    end

    tolerance = tolerance or 0.05  -- 5% tolerance by default

    -- Get current state
    local currentState = UsedPlusMaintenance.getCurrentVehicleState(vehicle)

    -- Compare with cached values
    local hoursDiff = math.abs(currentState.hours - spec.inspectionCacheHours)
    local damageDiff = math.abs(currentState.damage - spec.inspectionCacheDamage)
    local wearDiff = math.abs(currentState.wear - spec.inspectionCacheWear)

    -- Hours: allow 10 hours difference before requiring new inspection
    if hoursDiff > 10 then
        UsedPlus.logDebug(string.format("Inspection cache invalid: hours changed by %d", hoursDiff))
        return false
    end

    -- Damage: any significant change invalidates cache
    if damageDiff > tolerance then
        UsedPlus.logDebug(string.format("Inspection cache invalid: damage changed by %.1f%%", damageDiff * 100))
        return false
    end

    -- Wear: any significant change invalidates cache
    if wearDiff > tolerance then
        UsedPlus.logDebug(string.format("Inspection cache invalid: wear changed by %.1f%%", wearDiff * 100))
        return false
    end

    UsedPlus.logDebug("Inspection cache is still valid")
    return true
end

--[[
    PUBLIC API: Update inspection cache with current vehicle state
    Called after player pays for inspection
    @param vehicle - The vehicle to cache
]]
function UsedPlusMaintenance.updateInspectionCache(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then
        UsedPlus.logWarn("Cannot update inspection cache - spec not found")
        return false
    end

    local currentState = UsedPlusMaintenance.getCurrentVehicleState(vehicle)

    spec.hasInspectionCache = true
    spec.inspectionCacheHours = currentState.hours
    spec.inspectionCacheDamage = currentState.damage
    spec.inspectionCacheWear = currentState.wear

    UsedPlus.logDebug(string.format("Inspection cache updated: hours=%d, damage=%.1f%%, wear=%.1f%%",
        currentState.hours, currentState.damage * 100, currentState.wear * 100))

    return true
end

--[[
    PUBLIC API: Clear inspection cache
    Called when vehicle is repaired or condition changes significantly
    @param vehicle - The vehicle to clear cache for
]]
function UsedPlusMaintenance.clearInspectionCache(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    spec.hasInspectionCache = false
    spec.inspectionCacheHours = 0
    spec.inspectionCacheDamage = 0
    spec.inspectionCacheWear = 0

    UsedPlus.logDebug("Inspection cache cleared for " .. vehicle:getName())
end

--[[
    PUBLIC API: Get current reliability data for a vehicle
    Used for inspection reports and vehicle info display

    v1.4.0: Now includes workhorseLemonScale and maxReliabilityCeiling
]]
function UsedPlusMaintenance.getReliabilityData(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then
        return nil
    end

    -- Calculate average reliability
    local avgReliability = (spec.engineReliability + spec.hydraulicReliability + spec.electricalReliability) / 3

    -- v1.4.0: Calculate resale modifier based on average reliability
    -- Formula: 0.7 + (avgReliability * 0.3) => Range: 0.7 to 1.0
    -- A 50% reliable vehicle sells for 85% of normal value
    -- A 90% reliable vehicle sells for 97% of normal value
    local resaleModifier = 0.7 + (avgReliability * 0.3)

    -- v1.7.0: Get tire quality name
    local tireQualityName = "Normal"
    if spec.tireQuality == 1 then
        tireQualityName = "Retread"
    elseif spec.tireQuality == 3 then
        tireQualityName = "Quality"
    end

    return {
        purchasedUsed = spec.purchasedUsed,
        wasInspected = spec.wasInspected,
        engineReliability = spec.engineReliability,
        hydraulicReliability = spec.hydraulicReliability,
        electricalReliability = spec.electricalReliability,
        workhorseLemonScale = spec.workhorseLemonScale,
        maxReliabilityCeiling = spec.maxReliabilityCeiling,
        repairCount = spec.repairCount,
        totalRepairCost = spec.totalRepairCost,
        failureCount = spec.failureCount,
        avgReliability = avgReliability,
        resaleModifier = resaleModifier,  -- v1.4.0: Reliability affects resale value

        -- v1.7.0: Tire data
        tireCondition = spec.tireCondition,
        tireQuality = spec.tireQuality,
        tireQualityName = tireQualityName,
        tireMaxTraction = spec.tireMaxTraction,
        hasFlatTire = spec.hasFlatTire,

        -- v1.7.0: Fluid data
        oilLevel = spec.oilLevel,
        hasOilLeak = spec.hasOilLeak,
        oilLeakSeverity = spec.oilLeakSeverity,
        engineReliabilityCeiling = spec.engineReliabilityCeiling,

        hydraulicFluidLevel = spec.hydraulicFluidLevel,
        hasHydraulicLeak = spec.hasHydraulicLeak,
        hydraulicLeakSeverity = spec.hydraulicLeakSeverity,
        hydraulicReliabilityCeiling = spec.hydraulicReliabilityCeiling,

        -- v1.7.0: Fuel leak data
        hasFuelLeak = spec.hasFuelLeak,
        fuelLeakMultiplier = spec.fuelLeakMultiplier
    }
end

-- ===========================================================================
-- v2.8.0: GLOBAL MALFUNCTION COOLDOWN AND FIELD WORK PROTECTION
-- ===========================================================================

--[[
    v2.8.0: Check if vehicle is in global malfunction cooldown period
    Prevents cascade failures by ensuring minimum time between ANY malfunction
    @param vehicle - The vehicle to check
    @return boolean - True if in cooldown (should skip malfunction checks)
]]
function UsedPlusMaintenance.isInGlobalCooldown(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return false end

    local config = UsedPlusMaintenance.CONFIG
    local cooldown = config.globalMalfunctionCooldown or 45

    -- Get current time in seconds
    local currentTime = (g_currentMission.time or 0) / 1000

    -- Check if we're within cooldown period
    local lastMalfunctionTime = spec.lastMalfunctionTime or 0
    if (currentTime - lastMalfunctionTime) < cooldown then
        return true  -- Still in cooldown
    end

    return false
end

--[[
    v2.8.0: Record that a malfunction just occurred (updates global cooldown timer)
    Should be called by all malfunction trigger functions
    @param vehicle - The vehicle that experienced a malfunction
]]
function UsedPlusMaintenance.recordMalfunctionTime(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return end

    spec.lastMalfunctionTime = (g_currentMission.time or 0) / 1000

    -- Mark dirty for network sync
    if vehicle.raiseDirtyFlags and spec.dirtyFlag then
        vehicle:raiseDirtyFlags(spec.dirtyFlag)
    end
end

--[[
    v2.8.0: Detect if vehicle is actively working a field
    Active field work = implements lowered and working (plowing, cultivating, sowing, etc.)
    Returns true if field work detected, which triggers reduced malfunction chance
    @param vehicle - The vehicle to check
    @return boolean - True if actively doing field work
]]
function UsedPlusMaintenance.isDoingFieldWork(vehicle)
    -- Check for active implements doing work
    if not vehicle.getAttachedImplements then
        return false
    end

    local implements = vehicle:getAttachedImplements()
    if not implements or #implements == 0 then
        return false
    end

    for _, implement in pairs(implements) do
        local impl = implement.object
        if impl then
            -- Check if implement is turned on (active work)
            if impl.getIsTurnedOn and impl:getIsTurnedOn() then
                return true
            end

            -- Check if implement is lowered AND is a ground-engaging tool
            if impl.getIsLowered and impl:getIsLowered() then
                -- Check for ground-engaging tool specializations
                if impl.spec_cultivator or impl.spec_plow or impl.spec_sowingMachine
                   or impl.spec_sprayer or impl.spec_mower or impl.spec_tedder
                   or impl.spec_windrower or impl.spec_baler or impl.spec_forageWagon
                   or impl.spec_combine or impl.spec_harvester then
                    return true
                end
            end
        end
    end

    return false
end

--[[
    v2.8.0: Get the field work protection multiplier (or 1.0 if not doing field work)
    @param vehicle - The vehicle to check
    @return number - Multiplier to apply to failure probability (0.3 during field work, 1.0 otherwise)
]]
function UsedPlusMaintenance.getFieldWorkMultiplier(vehicle)
    local config = UsedPlusMaintenance.CONFIG

    if UsedPlusMaintenance.isDoingFieldWork(vehicle) then
        return config.fieldWorkProtectionMultiplier or 0.3
    end

    return 1.0
end

-- ===========================================================================
-- v2.7.0: SEIZURE ESCALATION SYSTEM
-- ===========================================================================

--[[
    Calculate failure probability based on damage, reliability, hours, and load
    Returns probability per second (0.0-1.0)

    v1.8.0: Added optional reliabilityOverride parameter for ModCompatibility integration
    When RVB is installed, callers pass in reliability derived from RVB part health

    @param vehicle - The vehicle to check
    @param failureType - "engine", "hydraulic", or "electrical"
    @param reliabilityOverride - Optional: use this reliability instead of spec value
]]
function UsedPlusMaintenance.calculateFailureProbability(vehicle, failureType, reliabilityOverride)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return 0 end

    -- Get current damage
    local damage = 0
    if vehicle.getDamageAmount then
        damage = vehicle:getDamageAmount() or 0
    end

    -- Get operating hours
    local hours = 0
    if vehicle.getOperatingTime then
        hours = (vehicle:getOperatingTime() or 0) / 3600000  -- Convert ms to hours
    end

    -- Get engine load (0-1)
    local load = 0
    if vehicle.getMotorLoadPercentage then
        load = vehicle:getMotorLoadPercentage() or 0
    end

    -- v1.8.0: Use override if provided (from ModCompatibility)
    -- Otherwise fall back to spec values
    local reliability = reliabilityOverride
    if reliability == nil then
        if failureType == "engine" then
            reliability = spec.engineReliability or 1.0
        elseif failureType == "hydraulic" then
            reliability = spec.hydraulicReliability or 1.0
        elseif failureType == "electrical" then
            reliability = spec.electricalReliability or 1.0
        else
            reliability = 1.0
        end
    end

    -- v2.7.0 ENHANCED: Progressive Malfunction Frequency
    local config = UsedPlusMaintenance.CONFIG
    local exponent = config.progressiveFailureExponent or 2.0
    local multiplier = config.progressiveFailureMultiplier or 0.025
    local reliabilityFactor = math.pow(1 - reliability, exponent)  -- Quadratic curve
    local baseChance = 0.00001 + (reliabilityFactor * multiplier)  -- 0.001% to 2.5% per second

    -- 2. DAMAGE MULTIPLIER (amplifies base chance, doesn't gate it)
    local damageMultiplier = 1.0 + (damage * 2.0)

    -- 3. HOURS CONTRIBUTION (high hours = slightly more prone to issues)
    local hoursMultiplier = 1.0 + math.min(hours / 20000, 0.5)

    -- 4. LOAD CONTRIBUTION (high load with low reliability = very risky)
    local loadMultiplier = 1.0 + (load * (1 - reliability) * 3.0)

    -- v2.5.2: FLUID CONTRIBUTION (low fluid = higher failure chance)
    local fluidMultiplier = 1.0
    if failureType == "engine" then
        fluidMultiplier = UsedPlusMaintenance.getOilChanceMultiplier(vehicle)
    elseif failureType == "hydraulic" then
        fluidMultiplier = UsedPlusMaintenance.getHydraulicFluidChanceMultiplier(vehicle)
    end

    -- Combined probability
    local probability = baseChance * damageMultiplier * hoursMultiplier * loadMultiplier * fluidMultiplier
    probability = probability * UsedPlusMaintenance.CONFIG.failureRateMultiplier

    -- v2.8.0: Apply USER's malfunction frequency multiplier from settings
    -- This allows players to tune malfunction frequency to their preference (25%-200%)
    local userFrequencyMultiplier = 1.0
    if UsedPlusSettings and UsedPlusSettings.get then
        userFrequencyMultiplier = UsedPlusSettings:get("malfunctionFrequencyMultiplier") or 1.0
    end
    probability = probability * userFrequencyMultiplier

    -- v2.8.0: Apply field work protection multiplier (70% less failures during active work)
    local fieldWorkMultiplier = UsedPlusMaintenance.getFieldWorkMultiplier(vehicle)
    probability = probability * fieldWorkMultiplier

    -- Cap at 5% per second max (allows for truly terrible engines)
    return math.min(probability, 0.05)
end

--[[
    Get the DNA-variable seizure threshold for this vehicle
    Lemons have a HIGH threshold (seizure zone starts early)
    Workhorses have a LOW threshold (seizure zone starts very late)
    @param vehicle - The vehicle to check
    @return number - Reliability threshold below which seizure can occur (0.0-1.0)
]]
function UsedPlusMaintenance.getSeizureThreshold(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return 0.25 end  -- Default if no spec

    local config = UsedPlusMaintenance.CONFIG
    local dna = spec.workhorseLemonScale or 0.5

    -- DNA 0.0 (lemon):     threshold = 0.40 (seizure zone starts at 40%)
    -- DNA 0.5 (average):   threshold = 0.25 (seizure zone starts at 25%)
    -- DNA 1.0 (workhorse): threshold = 0.10 (seizure zone starts at 10%)
    local baseThreshold = config.seizureBaseThreshold or 0.40
    local dnaReduction = dna * (config.seizureDNAReduction or 0.30)

    return baseThreshold - dnaReduction
end

--[[
    Roll the seizure die when a malfunction triggers
    Should ONLY be called when a malfunction has already been rolled/triggered
    @param vehicle - The vehicle experiencing malfunction
    @param component - "engine", "hydraulic", or "electrical"
    @return true if this malfunction should escalate to permanent seizure
]]
function UsedPlusMaintenance.rollForSeizure(vehicle, component)
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return false end

    local config = UsedPlusMaintenance.CONFIG

    -- Check if seizure system is enabled
    if not config.enableSeizureEscalation then
        return false
    end

    -- Get component reliability
    local reliability
    if component == "engine" then
        reliability = spec.engineReliability or 1.0
    elseif component == "hydraulic" then
        reliability = spec.hydraulicReliability or 1.0
    elseif component == "electrical" then
        reliability = spec.electricalReliability or 1.0
    else
        return false
    end

    -- Get DNA-variable threshold
    local threshold = UsedPlusMaintenance.getSeizureThreshold(vehicle)

    -- Only roll die if below threshold
    if reliability >= threshold then
        return false  -- Normal temporary malfunction, no seizure risk
    end

    -- Calculate seizure chance based on how far below threshold
    local depth = (threshold - reliability) / threshold  -- 0.0 to 1.0
    local minChance = config.seizureMinChance or 0.05
    local maxChance = config.seizureMaxChance or 0.50
    local seizureChance = minChance + (depth * (maxChance - minChance))

    -- DNA penalty: lemons have higher seizure chance
    local dna = spec.workhorseLemonScale or 0.5
    local lemonPenalty = (1 - dna) * (config.seizureLemonPenalty or 0.20)
    seizureChance = seizureChance + lemonPenalty

    -- Cap at 70% max (always some hope!)
    seizureChance = math.min(seizureChance, 0.70)

    -- Roll the die!
    local roll = math.random()
    local seized = roll < seizureChance

    UsedPlus.logDebug(string.format(
        "Seizure roll for %s %s: reliability=%.1f%%, threshold=%.1f%%, chance=%.1f%%, roll=%.3f, result=%s",
        vehicle:getName(), component, reliability * 100, threshold * 100, seizureChance * 100, roll, tostring(seized)))

    return seized
end

--[[
    Stop AI worker if active on this vehicle
    Called when a severe malfunction (like seizure) occurs
    @param vehicle - The vehicle to stop AI on
]]
function UsedPlusMaintenance.stopAIOnFailure(vehicle)
    local rootVehicle = vehicle:getRootVehicle()
    if rootVehicle and rootVehicle.getIsAIActive and rootVehicle:getIsAIActive() then
        if rootVehicle.stopCurrentAIJob then
            local errorMessage = nil
            if AIMessageErrorVehicleBroken and AIMessageErrorVehicleBroken.new then
                errorMessage = AIMessageErrorVehicleBroken.new()
            end
            rootVehicle:stopCurrentAIJob(errorMessage)
            UsedPlus.logDebug(string.format("AI worker stopped on %s due to seizure", vehicle:getName()))
        end
    end
end

--[[
    Seize a component permanently (requires repair to fix)
    @param vehicle - The vehicle to seize
    @param component - "engine", "hydraulic", or "electrical"
]]
function UsedPlusMaintenance.seizeComponent(vehicle, component)
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return end

    local currentTime = g_currentMission.time or 0

    if component == "engine" then
        spec.engineSeized = true
        spec.engineSeizedTime = currentTime

        -- Stop motor immediately
        if vehicle.stopMotor then
            vehicle:stopMotor()
        end

        -- Show critical warning
        if UsedPlusMaintenance.shouldShowWarning(vehicle) then
            if not g_dedicatedServer then
                g_currentMission:showBlinkingWarning(
                    g_i18n:getText("usedplus_engine_seized") or "ENGINE SEIZED! Repair required!",
                    5000
                )
            end
        end

        -- Stop AI
        UsedPlusMaintenance.stopAIOnFailure(vehicle)

    elseif component == "hydraulic" then
        spec.hydraulicsSeized = true
        spec.hydraulicsSeizedTime = currentTime

        if UsedPlusMaintenance.shouldShowWarning(vehicle) then
            if not g_dedicatedServer then
                g_currentMission:showBlinkingWarning(
                    g_i18n:getText("usedplus_hydraulics_seized") or "HYDRAULICS SEIZED! Implements locked!",
                    5000
                )
            end
        end

    elseif component == "electrical" then
        spec.electricalSeized = true
        spec.electricalSeizedTime = currentTime

        -- Turn off all electrical systems
        if vehicle.deactivateLights then
            vehicle:deactivateLights()
        end

        if UsedPlusMaintenance.shouldShowWarning(vehicle) then
            if not g_dedicatedServer then
                g_currentMission:showBlinkingWarning(
                    g_i18n:getText("usedplus_electrical_seized") or "ELECTRICAL FAILURE! Systems dead!",
                    5000
                )
            end
        end

        UsedPlusMaintenance.stopAIOnFailure(vehicle)
    end

    -- Record failure for DNA tracking
    spec.failureCount = (spec.failureCount or 0) + 1

    UsedPlus.logInfo(string.format("SEIZURE: %s component has seized on %s",
        component, vehicle:getName()))

    -- Mark dirty for network sync
    if vehicle.raiseDirtyFlags and spec.dirtyFlag then
        vehicle:raiseDirtyFlags(spec.dirtyFlag)
    end
end

--[[
    Clear seizure state for a component (after repair)
    @param vehicle - The vehicle to repair
    @param component - "engine", "hydraulic", "electrical", or "all"
]]
function UsedPlusMaintenance.clearSeizure(vehicle, component)
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return end

    if component == "engine" or component == "all" then
        spec.engineSeized = false
        spec.engineSeizedTime = 0
    end

    if component == "hydraulic" or component == "all" then
        spec.hydraulicsSeized = false
        spec.hydraulicsSeizedTime = 0
    end

    if component == "electrical" or component == "all" then
        spec.electricalSeized = false
        spec.electricalSeizedTime = 0
    end

    UsedPlus.logDebug(string.format("Seizure cleared for %s on %s", component, vehicle:getName()))

    -- Mark dirty for network sync
    if vehicle.raiseDirtyFlags and spec.dirtyFlag then
        vehicle:raiseDirtyFlags(spec.dirtyFlag)
    end
end

--[[
    Get list of seized components for a vehicle
    @param vehicle - The vehicle to check
    @return table - Array of seized component names
]]
function UsedPlusMaintenance.getSeizedComponents(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return {} end

    local seized = {}
    if spec.engineSeized then table.insert(seized, "engine") end
    if spec.hydraulicsSeized then table.insert(seized, "hydraulic") end
    if spec.electricalSeized then table.insert(seized, "electrical") end
    return seized
end

--[[
    Check if vehicle has any seized components
    @param vehicle - The vehicle to check
    @return boolean - True if any component is seized
]]
function UsedPlusMaintenance.hasAnySeizure(vehicle)
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return false end
    return spec.engineSeized or spec.hydraulicsSeized or spec.electricalSeized
end

--[[
    PUBLIC API: Set maintenance data when purchasing a used vehicle
    Called from UsedVehicleManager when purchase completes

    v1.4.0: Now transfers workhorseLemonScale and maxReliabilityCeiling
]]
function UsedPlusMaintenance.setUsedPurchaseData(vehicle, usedPlusData)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then
        UsedPlus.logWarn("Cannot set used purchase data - spec not found")
        return false
    end

    -- Mark as purchased used
    spec.purchasedUsed = true
    spec.purchaseDate = g_currentMission.environment.dayTime or 0
    spec.purchasePrice = usedPlusData.price or 0
    spec.purchaseDamage = usedPlusData.damage or 0
    spec.purchaseHours = usedPlusData.operatingHours or 0
    spec.wasInspected = usedPlusData.wasInspected or false

    -- Transfer hidden reliability scores
    spec.engineReliability = usedPlusData.engineReliability or 1.0
    spec.hydraulicReliability = usedPlusData.hydraulicReliability or 1.0
    spec.electricalReliability = usedPlusData.electricalReliability or 1.0

    -- v1.6.0: Reset grace period - prevents warnings immediately after purchase
    spec.startupGracePeriod = 2000

    -- v1.4.0: Transfer Workhorse/Lemon Scale data
    spec.workhorseLemonScale = usedPlusData.workhorseLemonScale or 0.5
    spec.maxReliabilityCeiling = usedPlusData.maxReliabilityCeiling or 1.0

    -- v1.7.0: Transfer tire data
    spec.tireCondition = usedPlusData.tireCondition or 1.0
    spec.tireQuality = usedPlusData.tireQuality or 2

    -- Apply tire quality modifiers
    local config = UsedPlusMaintenance.CONFIG
    if spec.tireQuality == 1 then  -- Retread
        spec.tireMaxTraction = config.tireRetreadTractionMult
        spec.tireFailureMultiplier = config.tireRetreadFailureMult
    elseif spec.tireQuality == 3 then  -- Quality
        spec.tireMaxTraction = config.tireQualityTractionMult
        spec.tireFailureMultiplier = config.tireQualityFailureMult
    else  -- Normal (2)
        spec.tireMaxTraction = config.tireNormalTractionMult
        spec.tireFailureMultiplier = config.tireNormalFailureMult
    end

    -- v1.7.0: Transfer fluid data
    spec.oilLevel = usedPlusData.oilLevel or 1.0
    spec.hydraulicFluidLevel = usedPlusData.hydraulicFluidLevel or 1.0

    -- v1.7.0: Initialize reliability ceilings (separate from DNA ceiling)
    spec.engineReliabilityCeiling = spec.maxReliabilityCeiling
    spec.hydraulicReliabilityCeiling = spec.maxReliabilityCeiling

    -- Initialize maintenance history
    spec.repairCount = 0
    spec.totalRepairCost = 0
    spec.failureCount = 0

    UsedPlus.logDebug(string.format("Set used purchase data for %s: DNA=%.2f, ceiling=%.1f%%, engine=%.2f, tires=%.0f%%, oil=%.0f%%",
        vehicle:getName(), spec.workhorseLemonScale, spec.maxReliabilityCeiling * 100,
        spec.engineReliability, spec.tireCondition * 100, spec.oilLevel * 100))

    return true
end

UsedPlus.logDebug("MaintenanceReliability module loaded")
