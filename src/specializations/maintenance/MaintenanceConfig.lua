--[[
    MaintenanceConfig.lua
    Configuration, inspector quotes, and inspection tier functions

    Extracted from UsedPlusMaintenance.lua for modularity
]]

-- Ensure UsedPlusMaintenance table exists (modules load before main spec)
UsedPlusMaintenance = UsedPlusMaintenance or {}

-- Configuration defaults
UsedPlusMaintenance.CONFIG = {
    -- Feature toggles
    enableFailures = true,
    enableInspection = true,
    enableSpeedDegradation = true,
    enableSteeringDegradation = true, -- v1.5.1: Worn steering feels loose/sloppy
    enableResaleModifier = true,
    enableHydraulicDrift = true,
    enableElectricalCutout = true,
    enableLemonScale = true,          -- Workhorse/Lemon DNA system

    -- Balance tuning
    failureRateMultiplier = 1.0,      -- Global failure frequency
    speedDegradationMax = 0.5,        -- Max 50% speed reduction

    -- v2.7.0: Tiered Inspection System (replaces instant inspection)
    -- Inspections now take time and cost more, but reveal more information
    inspectionTiers = {
        {  -- Tier 1: Quick Glance
            name = "Quick Glance",
            baseCost = 1000,          -- $1,000 base fee
            percentCost = 0.02,       -- + 2% of vehicle price
            maxCost = 2500,           -- Cap at $2,500
            durationHours = 2,        -- 2 game hours
            revealLevel = 1           -- Overall rating only
        },
        {  -- Tier 2: Standard Inspection
            name = "Standard",
            baseCost = 2000,          -- $2,000 base fee
            percentCost = 0.03,       -- + 3% of vehicle price
            maxCost = 5000,           -- Cap at $5,000
            durationHours = 6,        -- 6 game hours
            revealLevel = 2           -- Full reliability + RVB/tire
        },
        {  -- Tier 3: Comprehensive Inspection
            name = "Comprehensive",
            baseCost = 4000,          -- $4,000 base fee
            percentCost = 0.05,       -- + 5% of vehicle price
            maxCost = 10000,          -- Cap at $10,000
            durationHours = 12,       -- 12 game hours
            revealLevel = 3           -- Full + DNA hint + repair estimate
        }
    },

    -- Legacy inspection cost (kept for backwards compatibility)
    inspectionCostBase = 200,         -- Base inspection cost (DEPRECATED - use inspectionTiers)
    inspectionCostPercent = 0.01,     -- + 1% of vehicle price (DEPRECATED - use inspectionTiers)

    -- Thresholds
    damageThresholdForFailures = 0.2, -- Failures start at 20% damage
    reliabilityRepairBonus = 0.15,    -- Each repair adds 15% reliability
    maxReliabilityAfterRepair = 0.95, -- Can never fully restore (legacy, superseded by ceiling)

    -- Workhorse/Lemon Scale settings (v1.4.0+)
    ceilingDegradationMax = 0.01,     -- Max 1% ceiling loss per repair (for lemons)
    minReliabilityCeiling = 0.30,     -- Ceiling can never go below 30%

    -- Timing
    stallCooldownMs = 30000,          -- 30 seconds between stalls
    updateIntervalMs = 1000,          -- Check failures every 1 second

    -- Hydraulic drift settings
    hydraulicDriftSpeed = 0.001,      -- Radians per second of drift
    hydraulicDriftThreshold = 0.5,    -- Only drift if reliability below 50%

    -- Electrical cutout settings
    cutoutCheckIntervalMs = 5000,     -- Check for cutout every 5 seconds
    cutoutDurationMs = 3000,          -- Cutout lasts 3 seconds
    cutoutBaseChance = 0.03,          -- 3% base chance per check

    -- v1.5.1: Stall recovery settings
    stallRecoveryDurationMs = 5000,   -- 5 seconds before engine can restart after stall

    -- v1.6.0: Steering pull settings (worn vehicles pull to one side)
    steeringPullThreshold = 0.7,          -- Pull starts when hydraulic reliability drops below 70%
    steeringPullMax = 0.15,               -- Max 15% steering bias at lowest reliability
    steeringPullSpeedMin = 5,             -- No pull below 5 km/h
    steeringPullSpeedMax = 25,            -- Full pull effect at 25+ km/h
    steeringPullSurgeIntervalMin = 30000, -- Minimum 30 seconds between surge events
    steeringPullSurgeIntervalMax = 90000, -- Maximum 90 seconds between surge events
    steeringPullSurgeDuration = 3000,     -- Surge lasts 3 seconds
    steeringPullSurgeMultiplier = 1.5,    -- Pull is 50% stronger during surge

    -- v1.6.0: Engine misfiring settings (worn engine stutters/hiccups)
    -- v2.8.0 REBALANCED: Lowered threshold so misfires start at worse condition
    enableMisfiring = true,
    misfireThreshold = 0.45,              -- Misfires start below 45% engine reliability (was 0.6)
    misfireCheckIntervalMs = 500,         -- Check for misfire every 500ms
    misfireMaxChancePerCheck = 0.15,      -- Max 15% chance per check at 0% reliability
    misfireDurationMin = 100,             -- Minimum 100ms per misfire
    misfireDurationMax = 300,             -- Maximum 300ms per misfire
    misfireBurstChance = 0.3,             -- 30% chance of burst (multiple quick misfires)
    misfireBurstCount = 3,                -- Up to 3 misfires in a burst

    -- v1.6.0: Engine overheating settings (worn engine builds heat)
    -- v2.8.0 REBALANCED: Lowered threshold so overheating starts at worse condition
    enableOverheating = true,
    overheatThreshold = 0.35,             -- Overheating effects start below 35% engine reliability (was 0.5)
    overheatHeatRateBase = 0.002,         -- Base heat gain per second when running
    overheatHeatRateLoad = 0.008,         -- Additional heat per second at full load
    overheatCoolRateOff = 0.015,          -- Cool rate when engine off
    overheatCoolRateIdle = 0.005,         -- Cool rate when idling
    overheatWarningTemp = 0.7,            -- Show warning at 70% temperature
    overheatStallTemp = 0.95,             -- Force stall at 95% temperature
    overheatRestartTemp = 0.4,            -- Must cool to 40% to restart
    overheatCooldownMs = 20000,           -- Minimum 20 second cooldown after overheat

    -- v1.6.0: Implement surge settings (implements randomly lift)
    -- v2.8.0 REBALANCED: Lowered thresholds so problems start at worse condition
    enableImplementSurge = true,
    implementSurgeThreshold = 0.30,       -- Surge starts below 30% hydraulic reliability (was 0.4)
    implementSurgeChance = 0.002,         -- 0.2% chance per check when lowered

    -- v1.6.0: Implement drop settings (implements suddenly drop)
    -- v2.8.0 REBALANCED: Lowered threshold
    enableImplementDrop = true,
    implementDropThreshold = 0.25,        -- Drop starts below 25% hydraulic reliability (was 0.35)
    implementDropChance = 0.001,          -- 0.1% chance per check when raised

    -- v1.6.0: PTO toggle settings (power randomly turns on/off)
    enablePTOToggle = true,
    ptoToggleThreshold = 0.4,             -- Toggle starts below 40% electrical reliability
    ptoToggleChance = 0.003,              -- 0.3% chance per check

    -- v1.6.0: Hitch failure settings (implement detaches - VERY RARE)
    enableHitchFailure = true,
    hitchFailureThreshold = 0.15,         -- Only below 15% hydraulic reliability
    hitchFailureChance = 0.0001,          -- 0.01% chance per check (VERY rare)

    -- v2.4.0: Hydraulic surge event (temporary hard steering pull - "oh crap" moment)
    -- v2.8.0 REBALANCED: Lowered threshold
    enableHydraulicSurge = true,
    hydraulicSurgeThreshold = 0.45,       -- Can trigger below 45% hydraulic reliability (was 0.6)
    hydraulicSurgeBaseChance = 0.005,     -- 0.5% chance per second check
    hydraulicSurgeDurationMin = 5000,     -- Minimum 5 seconds
    hydraulicSurgeDurationMax = 15000,    -- Maximum 15 seconds
    hydraulicSurgeStrength = 0.3,         -- 30% steering bias (strong but recoverable)
    hydraulicSurgeFadeTime = 2000,        -- Fade out over last 2 seconds
    hydraulicSurgeCooldown = 60000,       -- 60 second cooldown between surges
    hydraulicSurgeMinSpeed = 10,          -- Only trigger above 10 km/h (meaningful driving)

    -- v2.5.0: RUNAWAY ENGINE (governor failure when both fluids critically low)
    enableRunaway = true,
    runawayOilThreshold = 0.10,           -- Oil must be below 10%
    runawayHydraulicThreshold = 0.10,     -- Hydraulic must be below 10%
    runawaySpeedBoostMax = 1.5,           -- Up to 150% normal max speed
    runawaySpeedRampTime = 10000,         -- 10 seconds to reach full boost
    runawayBrakeEffectiveness = 0.4,      -- Brakes 40% as effective during runaway
    runawayCrashSpeedDelta = 15,          -- Speed drop > 15 km/h per second = crash detected
    runawayMinSpeed = 5,                  -- Only trigger when already moving >5 km/h

    -- v2.5.0: Implement stuck down (hydraulic lift failure - can't raise)
    enableImplementStuckDown = true,
    implementStuckDownThreshold = 0.25,   -- Below 25% hydraulic reliability
    implementStuckDownChance = 0.001,     -- 0.1% chance per check when lowered
    implementStuckDownDuration = 45000,   -- 45 seconds until clears

    -- v2.5.0: Implement stuck up (hydraulic valve failure - can't lower)
    enableImplementStuckUp = true,
    implementStuckUpThreshold = 0.25,     -- Below 25% hydraulic reliability
    implementStuckUpChance = 0.001,       -- 0.1% chance per check when raised
    implementStuckUpDuration = 45000,     -- 45 seconds until clears

    -- v2.5.0: Implement causes steering pull (asymmetric drag from attached implements)
    enableImplementPull = true,
    implementPullThreshold = 0.4,         -- Below 40% hydraulic reliability
    implementPullMaxStrength = 0.15,      -- 15% steering bias from implement drag
    implementPullChance = 0.0005,         -- 0.05% chance per check to activate
    implementPullDuration = 60000,        -- 60 seconds until clears

    -- v2.5.0: Implement causes speed drag (hydraulic can't maintain position under load)
    enableImplementDrag = true,
    implementDragThreshold = 0.35,        -- Below 35% hydraulic reliability
    implementDragSpeedMult = 0.6,         -- 60% max speed when dragging
    implementDragChance = 0.0005,         -- 0.05% chance per check to activate
    implementDragDuration = 45000,        -- 45 seconds until clears

    -- v2.5.0: Reduced turning radius (power steering failure)
    enableReducedTurning = true,
    reducedTurningThreshold = 0.3,        -- Below 30% hydraulic reliability
    reducedTurningLimit = 0.65,           -- 65% of normal steering travel
    reducedTurningChance = 0.0008,        -- 0.08% chance per check to activate
    reducedTurningDuration = 30000,       -- 30 seconds until clears

    -- v2.5.2: FLUID LEVEL MULTIPLIERS
    hydraulicFluidChanceMultiplier = 2.0,     -- Low fluid up to 3x malfunction chance
    hydraulicFluidSeverityMultiplier = 1.5,   -- Low fluid up to 2.5x duration/severity
    hydraulicFluidCriticalThreshold = 0.25,   -- Below 25% fluid = severe penalties

    oilChanceMultiplier = 2.0,                -- Low oil up to 3x engine malfunction chance
    oilSeverityMultiplier = 1.5,              -- Low oil up to 2.5x duration/severity
    oilCriticalThreshold = 0.25,              -- Below 25% oil = severe penalties

    fluidCalculationMode = "multiplicative",

    -- v2.7.0: Progressive Malfunction Frequency Enhancement
    -- v2.8.0 REBALANCED (GitHub Issue #1): Reduced frequency, flatter curve
    progressiveFailureExponent = 1.5,         -- Flatter curve for more gradual degradation (was 2.0)
    progressiveFailureMultiplier = 0.008,     -- ~3x less frequent failures (was 0.025)

    -- v2.8.0 REBALANCED: Global malfunction cooldown and field work protection
    globalMalfunctionCooldown = 45,           -- Seconds between ANY malfunction (prevents cascade)
    fieldWorkProtectionMultiplier = 0.3,      -- 70% less failures during active field work

    -- v2.7.0: Seizure Escalation System
    enableSeizureEscalation = true,           -- Master toggle for seizure system
    seizureBaseThreshold = 0.40,              -- Lemon (DNA 0.0) seizure zone starts at 40% reliability
    seizureDNAReduction = 0.30,               -- Workhorse (DNA 1.0) reduces threshold by 30% to 10%
    seizureMinChance = 0.05,                  -- 5% seizure chance at threshold
    seizureMaxChance = 0.50,                  -- 50% seizure chance at 0% reliability
    seizureLemonPenalty = 0.20,               -- Lemons get +20% seizure chance on top

    seizureRepairCostMult = 0.05,             -- 5% of vehicle price per seized component
    seizureRepairMinReliability = 0.30,       -- OBD Scanner repair restores to at least 30%

    -- v2.7.0: Workshop additional repair costs
    workshopFuelLeakRepairCostMult = 0.02,    -- 2% of vehicle price to repair fuel leak
    workshopFlatTireRepairCostMult = 0.01,    -- 1% of vehicle price to repair flat tire (per tire)

    -- v1.7.0: Tire System Settings
    enableTireWear = true,
    tireWearRatePerKm = 0.001,            -- 0.1% condition loss per km
    tireWearDistanceBase = 240000,        -- 240km for full tire lifecycle (matches UYT default)
    tireWarnThreshold = 0.3,              -- Warn when tires below 30%
    tireCriticalThreshold = 0.15,         -- Critical warning below 15%

    -- Tire quality tiers (Retread = 1, Normal = 2, Quality = 3)
    tireRetreadCostMult = 0.40,           -- 40% of normal cost
    tireRetreadTractionMult = 0.85,       -- 85% traction
    tireRetreadFailureMult = 3.0,         -- 3x failure chance
    tireNormalCostMult = 1.0,             -- 100% cost (baseline)
    tireNormalTractionMult = 1.0,         -- 100% traction (baseline)
    tireNormalFailureMult = 1.0,          -- 1x failure chance (baseline)
    tireQualityCostMult = 1.50,           -- 150% of normal cost
    tireQualityTractionMult = 1.10,       -- 110% traction
    tireQualityFailureMult = 0.5,         -- 0.5x failure chance

    -- v2.3.0: Tire wear rate multipliers (quality affects how fast tires wear)
    tireRetreadWearMult = 2.0,            -- Retread wears 2x faster
    tireNormalWearMult = 1.0,             -- Normal baseline
    tireQualityWearMult = 0.67,           -- Quality wears 33% slower

    -- v2.3.0: DNA-based tire wear (lemons are harder on tires)
    tireDNAWearEnabled = true,            -- Enable DNA influence on tire wear
    tireDNAWearMinMult = 0.6,             -- Workhorse (DNA=1.0): 0.6x wear
    tireDNAWearMaxMult = 1.4,             -- Lemon (DNA=0.0): 1.4x wear

    -- v2.3.0: Retread initial wear (retreads are reconditioned casings)
    tireRetreadInitialWear = 0.35,        -- Retreads start at 35% wear (reconditioned)

    -- v2.3.0: Quality tire life bonus (premium tires have extended life)
    tireQualityLifeBonus = 0.15,          -- Quality tires get 15% bonus life (start at -15% wear)

    -- v1.7.0: Flat tire malfunction
    enableFlatTire = true,
    flatTireThreshold = 0.2,              -- Flat tire possible below 20% condition
    flatTireBaseChance = 0.0005,          -- 0.05% chance per check
    flatTireSpeedReduction = 0.5,         -- 50% max speed with flat
    flatTirePullStrength = 0.25,          -- Steering pull strength (0-1)
    flatTireFrictionMult = 0.3,           -- 30% friction with flat tire

    -- v1.7.0: Tire friction physics hook
    enableTireFriction = true,            -- Hook into WheelPhysics for friction reduction

    -- v1.7.0: Low traction malfunction (weather-aware)
    enableLowTraction = true,
    lowTractionThreshold = 0.25,          -- Low traction warnings below 25% condition
    lowTractionWetMultiplier = 1.5,       -- 50% worse in rain
    lowTractionSnowMultiplier = 2.0,      -- 100% worse in snow

    -- v1.7.0: Friction reduction based on tire condition
    tireFrictionMinMultiplier = 0.6,      -- Minimum 60% friction at 0% condition
    tireFrictionWetPenalty = 0.15,        -- Additional 15% loss when wet
    tireFrictionSnowPenalty = 0.25,       -- Additional 25% loss in snow

    -- v1.7.0: Oil System Settings
    enableOilSystem = true,
    oilDepletionRatePerHour = 0.01,       -- 1% per operating hour (100 hours to empty)
    oilWarnThreshold = 0.25,              -- Warn when oil below 25%
    oilCriticalThreshold = 0.10,          -- Critical warning below 10%
    oilLowDamageMultiplier = 2.0,         -- 2x engine wear when low on oil
    oilPermanentDamageOnFailure = 0.10,   -- 10% permanent ceiling drop if failure while low

    -- v1.7.0: Oil leak malfunction
    enableOilLeak = true,
    oilLeakThreshold = 0.4,               -- Leaks possible below 40% engine reliability
    oilLeakBaseChance = 0.0003,           -- 0.03% chance per check
    oilLeakMinorMult = 2.0,               -- Minor leak: 2x depletion
    oilLeakModerateMult = 5.0,            -- Moderate leak: 5x depletion
    oilLeakSevereMult = 10.0,             -- Severe leak: 10x depletion

    -- v1.7.0: Hydraulic Fluid System Settings
    enableHydraulicFluidSystem = true,
    hydraulicFluidDepletionPerAction = 0.00001, -- v2.15.4: 10x slower base drain (~28 hrs active use to empty, Issue #43)
    -- Base drain creates gradual reliability pressure; leaks (2x-10x mult) create real urgency.
    hydraulicFluidWarnThreshold = 0.25,   -- Warn when below 25%
    hydraulicFluidCriticalThreshold = 0.10, -- Critical warning below 10%
    hydraulicFluidLowDamageMultiplier = 2.0, -- 2x hydraulic wear when low
    hydraulicFluidPermanentDamageOnFailure = 0.10, -- 10% permanent ceiling drop

    -- v1.7.0: Hydraulic leak malfunction
    enableHydraulicLeak = true,
    hydraulicLeakThreshold = 0.4,         -- Leaks possible below 40% hydraulic reliability
    hydraulicLeakBaseChance = 0.0003,     -- 0.03% chance per check
    hydraulicLeakMinorMult = 2.0,         -- Minor leak: 2x depletion
    hydraulicLeakModerateMult = 5.0,      -- Moderate leak: 5x depletion
    hydraulicLeakSevereMult = 10.0,       -- Severe leak: 10x depletion

    -- v1.7.0: Fuel leak malfunction (engine issue)
    enableFuelLeak = true,
    fuelLeakThreshold = 0.35,             -- Fuel leaks possible below 35% engine reliability
    fuelLeakBaseChance = 0.0002,          -- 0.02% chance per check
    fuelLeakMinMult = 2.0,                -- Minimum 2x fuel consumption
    fuelLeakMaxMult = 5.0,                -- Maximum 5x fuel consumption
    fuelLeakBaseDrainRate = 0.5,          -- Base leak rate: 0.5 L/s when engine running
}

--[[
    Inspector Quote System (v1.4.0)
    50 quotes across 10 tiers that hint at vehicle DNA quality
    Each tier has 5 quotes: 2 technical, 2 superstitious, 1 country
]]
UsedPlusMaintenance.INSPECTOR_QUOTES = {
    catastrophic = {  -- 0.00 - 0.09
        "usedplus_quote_cat_1",
        "usedplus_quote_cat_2",
        "usedplus_quote_cat_3",
        "usedplus_quote_cat_4",
        "usedplus_quote_cat_5",
    },
    terrible = {  -- 0.10 - 0.19
        "usedplus_quote_ter_1",
        "usedplus_quote_ter_2",
        "usedplus_quote_ter_3",
        "usedplus_quote_ter_4",
        "usedplus_quote_ter_5",
    },
    poor = {  -- 0.20 - 0.29
        "usedplus_quote_poor_1",
        "usedplus_quote_poor_2",
        "usedplus_quote_poor_3",
        "usedplus_quote_poor_4",
        "usedplus_quote_poor_5",
    },
    belowAverage = {  -- 0.30 - 0.39
        "usedplus_quote_below_1",
        "usedplus_quote_below_2",
        "usedplus_quote_below_3",
        "usedplus_quote_below_4",
        "usedplus_quote_below_5",
    },
    slightlyBelow = {  -- 0.40 - 0.49
        "usedplus_quote_slight_1",
        "usedplus_quote_slight_2",
        "usedplus_quote_slight_3",
        "usedplus_quote_slight_4",
        "usedplus_quote_slight_5",
    },
    average = {  -- 0.50 - 0.59
        "usedplus_quote_avg_1",
        "usedplus_quote_avg_2",
        "usedplus_quote_avg_3",
        "usedplus_quote_avg_4",
        "usedplus_quote_avg_5",
    },
    aboveAverage = {  -- 0.60 - 0.69
        "usedplus_quote_above_1",
        "usedplus_quote_above_2",
        "usedplus_quote_above_3",
        "usedplus_quote_above_4",
        "usedplus_quote_above_5",
    },
    good = {  -- 0.70 - 0.79
        "usedplus_quote_good_1",
        "usedplus_quote_good_2",
        "usedplus_quote_good_3",
        "usedplus_quote_good_4",
        "usedplus_quote_good_5",
    },
    excellent = {  -- 0.80 - 0.89
        "usedplus_quote_exc_1",
        "usedplus_quote_exc_2",
        "usedplus_quote_exc_3",
        "usedplus_quote_exc_4",
        "usedplus_quote_exc_5",
    },
    legendary = {  -- 0.90 - 1.00
        "usedplus_quote_leg_1",
        "usedplus_quote_leg_2",
        "usedplus_quote_leg_3",
        "usedplus_quote_leg_4",
        "usedplus_quote_leg_5",
    },
}

--[[
    v2.8.0: DNA Tier Modifiers (replaces hard-clamped QUALITY_DNA_RANGES)

    Uses base triangular roll (0.0-1.0, centered at 0.5) + tier modifier.
    ALL modifiers are POSITIVE - higher tiers shift distribution right.

    This allows:
    - Workhorses (>0.80) to appear at ANY quality tier (just rarer at Poor)
    - Lemons (<0.30) to appear at ANY quality tier (just rarer at Excellent)
    - "Diamond in the rough" scenario: finding workhorse at Poor (~10% chance)
    - Meaningful Excellent advantage without guaranteed safety (~20% workhorse)

    Expected outcomes (triangular base + modifier):
    | Tier      | Modifier | Center | Workhorse (>0.80) | Lemon (<0.30) |
    |-----------|----------|--------|-------------------|---------------|
    | Poor      | +0.02    | 0.52   | ~10%              | ~16%          |
    | Any       | +0.04    | 0.54   | ~12%              | ~14%          |
    | Fair      | +0.06    | 0.56   | ~14%              | ~12%          |
    | Good      | +0.09    | 0.59   | ~17%              | ~9%           |
    | Excellent | +0.12    | 0.62   | ~20%              | ~7%           |

    Order: 1=Any, 2=Poor, 3=Fair, 4=Good, 5=Excellent
    Must match UsedSearchDialog.QUALITY_TIERS order!
]]
UsedPlusMaintenance.DNA_TIER_MODIFIERS = {
    [1] = 0.04,   -- Any:       center 0.54, ~12% workhorse, ~14% lemon
    [2] = 0.02,   -- Poor:      center 0.52, ~10% workhorse, ~16% lemon
    [3] = 0.06,   -- Fair:      center 0.56, ~14% workhorse, ~12% lemon
    [4] = 0.09,   -- Good:      center 0.59, ~17% workhorse, ~9% lemon
    [5] = 0.12,   -- Excellent: center 0.62, ~20% workhorse, ~7% lemon
}

-- DEPRECATED: Legacy ranges kept for reference only (v1.4.0 - v2.7.x)
-- Use DNA_TIER_MODIFIERS instead for actual DNA generation
UsedPlusMaintenance.QUALITY_DNA_RANGES = {
    [1] = { min = 0.00, max = 0.85, avg = 0.40 },  -- Any (deprecated)
    [2] = { min = 0.00, max = 0.70, avg = 0.30 },  -- Poor (deprecated)
    [3] = { min = 0.15, max = 0.85, avg = 0.50 },  -- Fair (deprecated)
    [4] = { min = 0.30, max = 0.95, avg = 0.60 },  -- Good (deprecated)
    [5] = { min = 0.50, max = 1.00, avg = 0.75 },  -- Excellent (deprecated)
}

--[[
    v2.7.0: Calculate inspection cost for a specific tier
    @param tierIndex - 1 = Quick Glance, 2 = Standard, 3 = Comprehensive
    @param vehiclePrice - The vehicle's listing price
    @return cost, tierConfig - Cost in dollars and the tier configuration
]]
function UsedPlusMaintenance.calculateInspectionCostForTier(tierIndex, vehiclePrice)
    local tier = UsedPlusMaintenance.CONFIG.inspectionTiers[tierIndex]
    if tier == nil then
        tier = UsedPlusMaintenance.CONFIG.inspectionTiers[2]  -- Default to Standard
    end

    local baseCost = tier.baseCost or 2000
    local percentCost = (vehiclePrice or 0) * (tier.percentCost or 0.03)
    local totalCost = baseCost + percentCost
    local cappedCost = math.min(totalCost, tier.maxCost or 5000)

    return math.floor(cappedCost), tier
end

--[[
    v2.7.0: Get inspection tier configuration by index
    @param tierIndex - 1, 2, or 3
    @return tier configuration table
]]
function UsedPlusMaintenance.getInspectionTier(tierIndex)
    return UsedPlusMaintenance.CONFIG.inspectionTiers[tierIndex]
end

--[[
    v2.7.0: Get all inspection tier names and costs for display
    @param vehiclePrice - The vehicle's listing price
    @return array of {name, cost, hours, revealLevel} tables
]]
function UsedPlusMaintenance.getInspectionTierOptions(vehiclePrice)
    local options = {}
    for i, tier in ipairs(UsedPlusMaintenance.CONFIG.inspectionTiers) do
        local cost = UsedPlusMaintenance.calculateInspectionCostForTier(i, vehiclePrice)
        table.insert(options, {
            index = i,
            name = tier.name,
            cost = cost,
            durationHours = tier.durationHours,
            revealLevel = tier.revealLevel
        })
    end
    return options
end

--[[
    Get inspector quote based on workhorse/lemon scale
    Returns localized quote text from the appropriate tier
    @param workhorseLemonScale - The vehicle's hidden quality score (0.0-1.0)
    @return string - Localized quote text
]]
function UsedPlusMaintenance.getInspectorQuote(workhorseLemonScale)
    local quotes = UsedPlusMaintenance.INSPECTOR_QUOTES

    -- Determine tier based on scale (10 tiers, 0.1 each)
    local tier
    if workhorseLemonScale < 0.10 then
        tier = "catastrophic"
    elseif workhorseLemonScale < 0.20 then
        tier = "terrible"
    elseif workhorseLemonScale < 0.30 then
        tier = "poor"
    elseif workhorseLemonScale < 0.40 then
        tier = "belowAverage"
    elseif workhorseLemonScale < 0.50 then
        tier = "slightlyBelow"
    elseif workhorseLemonScale < 0.60 then
        tier = "average"
    elseif workhorseLemonScale < 0.70 then
        tier = "aboveAverage"
    elseif workhorseLemonScale < 0.80 then
        tier = "good"
    elseif workhorseLemonScale < 0.90 then
        tier = "excellent"
    else
        tier = "legendary"
    end

    -- Select random quote from tier
    local tierQuotes = quotes[tier]
    local quoteKey = tierQuotes[math.random(#tierQuotes)]

    -- Return localized text (with fallback)
    local text = g_i18n:getText(quoteKey)
    if text == quoteKey then
        -- Translation not found, return a generic message
        return "Vehicle condition assessed."
    end
    return text
end

--[[
    v1.9.4: Get comprehensive fluid inspector comment
    Generates detailed observations about oil, hydraulic fluid, and leaks
    @param usedPlusData - The full reliability data including fluid levels and leak status
    @return string - Detailed fluid assessment comment
]]
function UsedPlusMaintenance.getFluidInspectorComment(usedPlusData)
    if usedPlusData == nil then
        return nil
    end

    local comments = {}

    -- Oil assessment
    local oilLevel = usedPlusData.oilLevel or 1.0
    local hasOilLeak = usedPlusData.hasOilLeak or false
    local oilLeakSeverity = usedPlusData.oilLeakSeverity or 0

    if hasOilLeak then
        if oilLeakSeverity >= 2.0 then
            table.insert(comments, g_i18n:getText("usedplus_fluid_oilLeakSevere") or "Significant oil leak detected - needs immediate attention.")
        else
            table.insert(comments, g_i18n:getText("usedplus_fluid_oilLeakMinor") or "Minor oil leak present - may worsen over time.")
        end
    elseif oilLevel < 0.3 then
        table.insert(comments, g_i18n:getText("usedplus_fluid_oilCritical") or "Oil level critically low - top up before operation.")
    elseif oilLevel < 0.5 then
        table.insert(comments, g_i18n:getText("usedplus_fluid_oilLow") or "Oil level below recommended - needs topping up.")
    elseif oilLevel < 0.7 then
        table.insert(comments, g_i18n:getText("usedplus_fluid_oilAdequate") or "Oil level adequate but monitor regularly.")
    else
        table.insert(comments, g_i18n:getText("usedplus_fluid_oilGood") or "Oil level looks good.")
    end

    -- Hydraulic fluid assessment
    local hydraulicLevel = usedPlusData.hydraulicFluidLevel or 1.0
    local hasHydraulicLeak = usedPlusData.hasHydraulicLeak or false
    local hydraulicLeakSeverity = usedPlusData.hydraulicLeakSeverity or 0

    if hasHydraulicLeak then
        if hydraulicLeakSeverity >= 2.0 then
            table.insert(comments, g_i18n:getText("usedplus_fluid_hydLeakSevere") or "Major hydraulic leak found - repair urgently needed.")
        else
            table.insert(comments, g_i18n:getText("usedplus_fluid_hydLeakMinor") or "Small hydraulic leak detected - keep an eye on it.")
        end
    elseif hydraulicLevel < 0.4 then
        table.insert(comments, g_i18n:getText("usedplus_fluid_hydCritical") or "Hydraulic fluid dangerously low - implements may not function properly.")
    elseif hydraulicLevel < 0.6 then
        table.insert(comments, g_i18n:getText("usedplus_fluid_hydLow") or "Hydraulic fluid running low - recommend refill.")
    elseif hydraulicLevel >= 0.8 then
        table.insert(comments, g_i18n:getText("usedplus_fluid_hydGood") or "Hydraulic system looks healthy.")
    end

    -- Fuel leak (serious issue)
    local hasFuelLeak = usedPlusData.hasFuelLeak or false
    if hasFuelLeak then
        table.insert(comments, g_i18n:getText("usedplus_fluid_fuelLeak") or "CAUTION: Fuel leak detected - fire hazard, needs repair.")
    end

    -- Return combined comments or nil if nothing notable
    if #comments > 0 then
        return table.concat(comments, " ")
    else
        return g_i18n:getText("usedplus_fluid_allClear") or "All fluid systems appear normal."
    end
end

UsedPlus.logDebug("MaintenanceConfig module loaded")
