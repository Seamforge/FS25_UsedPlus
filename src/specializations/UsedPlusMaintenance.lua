--[[
    FS25_UsedPlus - Maintenance System Vehicle Specialization (CORE)

    v2.7.2 REFACTORED: This is the core specialization file.
    Implementation functions have been extracted to maintenance/ modules:
    - MaintenanceConfig.lua     - CONFIG, quotes, tier functions
    - MaintenanceWarnings.lua   - Warning helpers, repair handlers
    - MaintenanceSpeed.lua      - Speed governor, limits
    - MaintenanceSteering.lua   - Steering pull, degradation, drift
    - MaintenanceTires.lua      - Tire wear, friction, flat tire
    - MaintenanceFluids.lua     - Oil, hydraulic fluid, fuel leak
    - MaintenanceReliability.lua - DNA, scoring, seizure system
    - MaintenanceEngine.lua     - Stall, misfire, overheat
    - MaintenanceHydraulics.lua - Hydraulic malfunctions, implements

    This file contains:
    - Module declaration and spec registration
    - Lifecycle functions (onLoad, onPostLoad, onUpdate, save/load, stream)
    - Override functions (getCanMotorRun, setSteeringInput)
]]

-- Use existing table if modules have loaded, otherwise create new
UsedPlusMaintenance = UsedPlusMaintenance or {}

UsedPlusMaintenance.MOD_NAME = g_currentModName
UsedPlusMaintenance.SPEC_NAME = UsedPlusMaintenance.MOD_NAME .. ".UsedPlusMaintenance"

-- NOTE: CONFIG, INSPECTOR_QUOTES, and QUALITY_DNA_RANGES are defined in MaintenanceConfig.lua
-- They are loaded before this file and attached to UsedPlusMaintenance namespace

--[[
    Prerequisites check
    Return true to allow spec to load
]]
function UsedPlusMaintenance.prerequisitesPresent(specializations)
    return true
end

--[[
    Initialize specialization - Register XML schema for save/load
    Pattern from: HeadlandManagement initSpecialization
]]
function UsedPlusMaintenance.initSpecialization()
    UsedPlus.logDebug("UsedPlusMaintenance.initSpecialization starting schema registration")

    local schemaSavegame = Vehicle.xmlSchemaSavegame
    local key = "vehicles.vehicle(?)." .. UsedPlusMaintenance.SPEC_NAME

    -- Purchase Information
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".purchasedUsed", "Was this vehicle bought used?", false)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".purchaseDate", "Game time when purchased", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".purchasePrice", "What player paid", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".purchaseDamage", "Damage at time of purchase", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".purchaseHours", "Operating hours at purchase", 0)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".wasInspected", "Did player pay for inspection?", false)

    -- Hidden Reliability Scores (0.0-1.0, lower = worse)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".engineReliability", "Engine reliability score", 1.0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".hydraulicReliability", "Hydraulic reliability score", 1.0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".electricalReliability", "Electrical reliability score", 1.0)

    -- Workhorse/Lemon Scale System (v1.4.0+)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".workhorseLemonScale", "Hidden quality DNA (0=lemon, 1=workhorse)", 0.5)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".maxReliabilityCeiling", "Current max achievable reliability", 1.0)

    -- v2.2.0: Component Durability System (progressive degradation)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".maxEngineDurability", "Max achievable engine durability (degrades over time)", 1.0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".maxHydraulicDurability", "Max achievable hydraulic durability (degrades over time)", 1.0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".maxElectricalDurability", "Max achievable electrical durability (degrades over time)", 1.0)

    -- v2.2.0: RVB Integration Tracking
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".rvbLifetimeMultiplier", "Initial DNA-based RVB lifetime multiplier", 1.0)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".rvbLifetimesApplied", "Whether RVB lifetimes have been modified by DNA", false)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".rvbTotalDegradation", "Cumulative RVB lifetime degradation", 0)
    schemaSavegame:register(XMLValueType.INT,   key .. ".rvbRepairCount", "Number of RVB repairs performed", 0)
    schemaSavegame:register(XMLValueType.INT,   key .. ".rvbBreakdownCount", "Number of RVB breakdowns suffered", 0)

    -- Maintenance History
    schemaSavegame:register(XMLValueType.INT,   key .. ".repairCount", "Times repaired at shop", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".totalRepairCost", "Lifetime repair spending", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".lastRepairDate", "Last shop visit game time", 0)
    schemaSavegame:register(XMLValueType.INT,   key .. ".failureCount", "Total breakdowns experienced", 0)

    -- Inspection Cache (for paid inspections on owned vehicles)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".hasInspectionCache", "Has a paid inspection been done?", false)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".inspectionCacheHours", "Operating hours at inspection", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".inspectionCacheDamage", "Damage level at inspection", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".inspectionCacheWear", "Wear/paint level at inspection", 0)

    -- v1.7.0: Tire System
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".tireCondition", "Tire tread condition (0-1)", 1.0)
    schemaSavegame:register(XMLValueType.INT,   key .. ".tireQuality", "Tire quality tier (1=Retread, 2=Normal, 3=Quality)", 2)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".distanceTraveled", "Distance traveled for tire wear", 0)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".hasFlatTire", "Does vehicle have a flat tire?", false)
    schemaSavegame:register(XMLValueType.INT,   key .. ".flatTireSide", "Which side has flat tire (-1=left, 0=none, 1=right)", 0)

    -- v2.8.0: Per-wheel distance tracking (unified tire tracking - no free passes)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".wheelDistances.w1", "Wheel 1 distance traveled (m)", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".wheelDistances.w2", "Wheel 2 distance traveled (m)", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".wheelDistances.w3", "Wheel 3 distance traveled (m)", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".wheelDistances.w4", "Wheel 4 distance traveled (m)", 0)

    -- v1.7.0: Oil System
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".oilLevel", "Engine oil level (0-1)", 1.0)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".wasLowOil", "Was low oil warning shown?", false)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".hasOilLeak", "Does engine have oil leak?", false)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".oilLeakSeverity", "Oil leak severity multiplier", 1.0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".engineReliabilityCeiling", "Max engine reliability due to oil damage", 1.0)

    -- v1.7.0: Hydraulic Fluid System
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".hydraulicFluidLevel", "Hydraulic fluid level (0-1)", 1.0)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".wasLowHydraulicFluid", "Was low hydraulic fluid warning shown?", false)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".hasHydraulicLeak", "Does hydraulic system have leak?", false)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".hydraulicLeakSeverity", "Hydraulic leak severity multiplier", 1.0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".hydraulicReliabilityCeiling", "Max hydraulic reliability due to fluid damage", 1.0)

    -- v1.7.0: Fuel Leak System
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".hasFuelLeak", "Does fuel tank have leak?", false)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".fuelLeakMultiplier", "Fuel leak rate multiplier", 1.0)

    -- v2.4.0: Hydraulic Surge Event (only cooldown matters for persistence)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".hydraulicSurgeCooldownEnd", "Cooldown timer end time", 0)

    -- v2.7.0: Seizure Escalation System (permanent component failures)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".engineSeized", "Engine seized (won't start)", false)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".hydraulicsSeized", "Hydraulics seized (implements frozen)", false)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".electricalSeized", "Electrical seized (systems dead)", false)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".engineSeizedTime", "When engine seizure occurred", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".hydraulicsSeizedTime", "When hydraulic seizure occurred", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".electricalSeizedTime", "When electrical seizure occurred", 0)

    -- v2.8.0: OBD Scanner diagnosis tracking (one-time boost per system)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".obdDiagnosedEngine", "OBD diagnosis used on engine", false)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".obdDiagnosedElectrical", "OBD diagnosis used on electrical", false)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".obdDiagnosedHydraulic", "OBD diagnosis used on hydraulic", false)

    -- v2.9.0: Service Truck Restoration System
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".isBeingRestored", "Is currently being restored by a service truck", false)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".restorationCooldowns.engine", "Cooldown end time for engine restoration", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".restorationCooldowns.electrical", "Cooldown end time for electrical restoration", 0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".restorationCooldowns.hydraulic", "Cooldown end time for hydraulic restoration", 0)

    -- v2.1.0: RVB/UYT Deferred Sync Flags (prevents schema validation errors)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".rvbDataSynced", "Whether RVB data has been synced to vehicle", false)
    schemaSavegame:register(XMLValueType.BOOL,  key .. ".tireDataSynced", "Whether UYT tire data has been synced to vehicle", false)

    -- v2.1.0: Stored RVB Parts Data (for deferred sync when RVB not installed at purchase)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".storedRvbData.ENGINE", "Stored RVB engine life", 1.0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".storedRvbData.BATTERY", "Stored RVB battery life", 1.0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".storedRvbData.THERMOSTAT", "Stored RVB thermostat life", 1.0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".storedRvbData.GENERATOR", "Stored RVB generator life", 1.0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".storedRvbData.SELFSTARTER", "Stored RVB selfstarter life", 1.0)

    -- v2.1.0: Stored Tire Conditions (for deferred sync when UYT not installed at purchase)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".storedTireConditions.FL", "Stored tire condition front-left", 1.0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".storedTireConditions.FR", "Stored tire condition front-right", 1.0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".storedTireConditions.RL", "Stored tire condition rear-left", 1.0)
    schemaSavegame:register(XMLValueType.FLOAT, key .. ".storedTireConditions.RR", "Stored tire condition rear-right", 1.0)

    UsedPlus.logDebug("UsedPlusMaintenance schema registration complete (v2.7.2 modular)")
end

--[[
    Register event listeners for this specialization
    Pattern from: HeadlandManagement registerEventListeners
]]
function UsedPlusMaintenance.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", UsedPlusMaintenance)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", UsedPlusMaintenance)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", UsedPlusMaintenance)
    SpecializationUtil.registerEventListener(vehicleType, "saveToXMLFile", UsedPlusMaintenance)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", UsedPlusMaintenance)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", UsedPlusMaintenance)
    SpecializationUtil.registerEventListener(vehicleType, "onReadUpdateStream", UsedPlusMaintenance)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteUpdateStream", UsedPlusMaintenance)
    -- v1.5.1: Listen for vehicle enter to trigger first-start stall check
    SpecializationUtil.registerEventListener(vehicleType, "onEnterVehicle", UsedPlusMaintenance)
end

--[[
    Register overwritten functions
    Pattern from: HeadlandManagement registerOverwrittenFunctions
]]
function UsedPlusMaintenance.registerOverwrittenFunctions(vehicleType)
    -- v1.5.1: Override getCanMotorRun for stall recovery period and speed governor
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanMotorRun", UsedPlusMaintenance.getCanMotorRun)

    -- v1.5.1: Override setSteeringInput for steering degradation (loose steering on worn hydraulics)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setSteeringInput", UsedPlusMaintenance.setSteeringInput)
end

--[[
    v1.5.1: Override getCanMotorRun to enforce:
    1. Stall recovery period (prevents instant restart after stall)
    2. Speed governor (cuts power when over reliability-based max speed)

    The speed governor acts like a rev limiter - when you exceed the max speed
    your engine can sustain, power cuts briefly until you drop back below.
    This is more realistic than applying brakes (no brake lights).
]]
function UsedPlusMaintenance:getCanMotorRun(superFunc)
    local spec = self.spec_usedPlusMaintenance
    if spec == nil then
        return superFunc(self)
    end

    -- v2.7.0: Seized engine cannot run at all (requires repair)
    if spec.engineSeized then
        return false
    end

    -- Check if in stall recovery period
    if spec.stallRecoveryEndTime and spec.stallRecoveryEndTime > 0 then
        local currentTime = g_currentMission.time or 0
        if currentTime < spec.stallRecoveryEndTime then
            -- Still in recovery - engine cannot run
            return false
        else
            -- Recovery complete - clear the timer
            spec.stallRecoveryEndTime = 0
        end
    end

    -- v1.6.0: Check for engine overheat - can't run until cooled
    if spec.isOverheated then
        return false
    end

    -- v1.6.0: Check for active misfire - brief power cut
    if spec.misfireActive then
        return false
    end

    -- v1.5.1: Speed governor - cut motor when significantly over reliability-based max speed
    local inStallRecovery = spec.stallRecoveryEndTime and spec.stallRecoveryEndTime > 0
    local config = UsedPlusMaintenance.CONFIG
    if not inStallRecovery and config and config.enableSpeedDegradation and spec.maxSpeedFactor and spec.maxSpeedFactor < 0.95 then
        local currentSpeed = 0
        if self.getLastSpeed then
            currentSpeed = self:getLastSpeed()  -- km/h
        end

        -- Calculate max speed based on vehicle's base max and our degradation factor
        local baseMaxSpeed = 50  -- Default fallback
        if self.spec_drivable and self.spec_drivable.cruiseControl then
            baseMaxSpeed = self.spec_drivable.cruiseControl.maxSpeed or 50
        end
        local degradedMaxSpeed = baseMaxSpeed * spec.maxSpeedFactor

        -- Allow 3 km/h grace before cutting (prevents constant flickering at the limit)
        local overspeedThreshold = degradedMaxSpeed + 3

        if currentSpeed > overspeedThreshold then
            -- Over speed - cut power (acts like hitting a governor/rev limiter)
            spec.governorPulseTimer = (spec.governorPulseTimer or 0) + 1
            if spec.governorPulseTimer % 3 ~= 0 then  -- Cut 2 out of every 3 frames
                if not spec.hasShownGovernorWarning and UsedPlusMaintenance.shouldShowWarning(self) then
                    if not g_dedicatedServer then
                        g_currentMission:showBlinkingWarning(
                            g_i18n:getText("usedPlus_speedGovernor") or "Engine struggling at this speed!",
                            2000
                        )
                    end
                    spec.hasShownGovernorWarning = true
                end
                return false
            end
        else
            spec.governorPulseTimer = 0
            spec.hasShownGovernorWarning = false
        end
    end

    -- v1.8.1: Chain to AdvancedMaintenance's damage check if installed
    if ModCompatibility.advancedMaintenanceInstalled then
        local shouldChain, chainFunc = ModCompatibility.getAdvancedMaintenanceChain(self)
        if shouldChain and chainFunc then
            local amResult = chainFunc()
            if amResult == false then
                return false
            end
        end
    end

    -- Normal check
    return superFunc(self)
end

--[[
    v1.5.1: Override setSteeringInput for steering degradation
    Poor hydraulic reliability causes "loose" steering - the vehicle doesn't hold straight
    v1.7.0: Added flat tire steering pull (stronger, more consistent)
    Pattern from: HeadlandManagement setSteeringInput
]]
function UsedPlusMaintenance:setSteeringInput(superFunc, inputValue, isAnalog, deviceCategory)
    local spec = self.spec_usedPlusMaintenance

    -- If no maintenance data, pass through
    if spec == nil then
        return superFunc(self, inputValue, isAnalog, deviceCategory)
    end

    local config = UsedPlusMaintenance.CONFIG
    local hydraulicReliability = ModCompatibility.getHydraulicReliability(self)

    -- Get current speed (used by multiple effects)
    local speed = 0
    if self.getLastSpeed then
        speed = self:getLastSpeed()
    end

    -- ========== v2.4.0: HYDRAULIC SURGE EVENT ==========
    if spec.hydraulicSurgeActive and config.enableHydraulicSurge then
        local currentTime = g_currentMission.time or 0

        if currentTime >= spec.hydraulicSurgeEndTime then
            spec.hydraulicSurgeActive = false
            spec.hydraulicSurgeCooldownEnd = currentTime + config.hydraulicSurgeCooldown
        else
            local surgeStrength = config.hydraulicSurgeStrength
            if currentTime >= spec.hydraulicSurgeFadeStartTime then
                local fadeProgress = (currentTime - spec.hydraulicSurgeFadeStartTime) / config.hydraulicSurgeFadeTime
                fadeProgress = math.min(fadeProgress, 1.0)
                surgeStrength = surgeStrength * (1 - fadeProgress)
            end

            local surgePull = surgeStrength * spec.hydraulicSurgeDirection
            inputValue = inputValue + surgePull
            inputValue = math.max(-1, math.min(1, inputValue))
        end
    end

    -- ========== v2.5.0: IMPLEMENT PULL ==========
    if spec.implementPullActive and config.enableImplementPull then
        local hasImplements = false
        if self.getAttachedImplements then
            local implements = self:getAttachedImplements()
            hasImplements = implements and #implements > 0
        end

        if hasImplements then
            local implPullSpeedFactor = 0
            if speed > 5 then
                implPullSpeedFactor = math.min((speed - 5) / 20, 1.0)
            end

            local implPullAmount = config.implementPullMaxStrength * implPullSpeedFactor * spec.implementPullDirection
            inputValue = inputValue + implPullAmount
            inputValue = math.max(-1, math.min(1, inputValue))
        else
            spec.implementPullActive = false
        end
    end

    -- ========== v1.7.0: FLAT TIRE STEERING PULL ==========
    -- v2.8.0: Also check malfunctions setting - if disabled, no flat tire effects
    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if spec.hasFlatTire and config.enableFlatTire and malfunctionsEnabled then
        local flatTirePullStrength = config.flatTirePullStrength
        local flatSpeedFactor = 0.3
        if speed > 3 then
            flatSpeedFactor = math.min(0.3 + (speed / 40) * 0.7, 1.0)
        end

        local flatPullAmount = flatTirePullStrength * flatSpeedFactor * spec.flatTireSide
        inputValue = inputValue + flatPullAmount
        inputValue = math.max(-1, math.min(1, inputValue))
    end

    -- ========== HYDRAULIC STEERING DEGRADATION ==========
    if not config.enableSteeringDegradation then
        return superFunc(self, inputValue, isAnalog, deviceCategory)
    end

    if hydraulicReliability >= config.steeringPullThreshold then
        spec.steeringPullDirection = 0
        spec.steeringPullInitialized = false
        spec.hasShownPullWarning = false
        return superFunc(self, inputValue, isAnalog, deviceCategory)
    end

    -- ========== v1.6.0: STEERING PULL ==========
    if not spec.steeringPullInitialized then
        spec.steeringPullDirection = math.random() < 0.5 and -1 or 1
        spec.steeringPullInitialized = true
        local surgeInterval = math.random(config.steeringPullSurgeIntervalMin, config.steeringPullSurgeIntervalMax)
        spec.steeringPullSurgeTimer = surgeInterval
    end

    local pullFactor = (config.steeringPullThreshold - hydraulicReliability) / config.steeringPullThreshold
    local basePullStrength = pullFactor * config.steeringPullMax

    local speedFactor = 0
    if speed > config.steeringPullSpeedMin then
        speedFactor = math.min((speed - config.steeringPullSpeedMin) / (config.steeringPullSpeedMax - config.steeringPullSpeedMin), 1.0)
    end

    local currentTime = g_currentMission.time or 0
    local surgeMultiplier = 1.0

    if spec.steeringPullSurgeActive then
        if currentTime >= spec.steeringPullSurgeEndTime then
            spec.steeringPullSurgeActive = false
            local surgeInterval = math.random(config.steeringPullSurgeIntervalMin, config.steeringPullSurgeIntervalMax)
            spec.steeringPullSurgeTimer = surgeInterval
        else
            surgeMultiplier = config.steeringPullSurgeMultiplier
        end
    end

    local pullAmount = basePullStrength * speedFactor * surgeMultiplier * spec.steeringPullDirection

    if speedFactor > 0 then
        inputValue = inputValue + pullAmount

        if not spec.hasShownPullWarning and UsedPlusMaintenance.shouldShowWarning(self) then
            local directionText = spec.steeringPullDirection < 0 and
                (g_i18n:getText("usedPlus_directionLeft") or "left") or
                (g_i18n:getText("usedPlus_directionRight") or "right")
            if not g_dedicatedServer then
                g_currentMission:showBlinkingWarning(
                    string.format(g_i18n:getText("usedPlus_steeringPull") or "Steering pulling to the %s!", directionText),
                    3000
                )
            end
            spec.hasShownPullWarning = true
        end
    end

    -- ========== STEERING WANDER ==========
    if speed > 3 then
        local slopFactor = (config.steeringPullThreshold - hydraulicReliability) / config.steeringPullThreshold
        slopFactor = math.min(slopFactor, 0.9)

        local wanderSpeedFactor = math.min(speed / 30, 1.0)
        local wanderIntensity = slopFactor * wanderSpeedFactor * 0.08

        spec.steeringWanderTarget = spec.steeringWanderTarget or 0
        spec.steeringWanderCurrent = spec.steeringWanderCurrent or 0

        if math.random() < 0.02 then
            spec.steeringWanderTarget = (math.random() - 0.5) * 2 * wanderIntensity
        end

        local approach = 0.05
        spec.steeringWanderCurrent = spec.steeringWanderCurrent + (spec.steeringWanderTarget - spec.steeringWanderCurrent) * approach

        local playerInputStrength = math.abs(inputValue)
        local wanderWeight = 1.0 - (playerInputStrength * 0.7)
        local finalWander = spec.steeringWanderCurrent * wanderWeight

        inputValue = inputValue + finalWander
        inputValue = math.max(-1, math.min(1, inputValue))

        if hydraulicReliability < 0.3 and math.random() < 0.001 then
            local slip = (math.random() - 0.5) * 0.15
            inputValue = math.max(-1, math.min(1, inputValue + slip))

            if not spec.hasShownSteeringWarning and UsedPlusMaintenance.shouldShowWarning(self) then
                if not g_dedicatedServer then
                    g_currentMission:showBlinkingWarning(
                        g_i18n:getText("usedPlus_steeringLoose") or "Steering feels loose!",
                        2000
                    )
                end
                spec.hasShownSteeringWarning = true
            end
        end
    else
        spec.steeringWanderCurrent = 0
        spec.steeringWanderTarget = 0
    end

    -- ========== v2.5.0: REDUCED TURNING ==========
    if spec.reducedTurningActive and config.enableReducedTurning then
        inputValue = inputValue * config.reducedTurningLimit
    end

    inputValue = math.max(-1, math.min(1, inputValue))

    return superFunc(self, inputValue, isAnalog, deviceCategory)
end

--[[
    Called when vehicle is loaded
    Initialize all spec data with defaults
    Pattern from: HeadlandManagement onLoad
]]
function UsedPlusMaintenance:onLoad(savegame)
    -- Make spec accessible via self.spec_usedPlusMaintenance
    self.spec_usedPlusMaintenance = self["spec_" .. UsedPlusMaintenance.SPEC_NAME]
    local spec = self.spec_usedPlusMaintenance

    if spec == nil then
        UsedPlus.logWarn("UsedPlusMaintenance spec not found for vehicle: " .. tostring(self:getName()))
        return
    end

    -- Create dirty flag for network sync
    spec.dirtyFlag = self:getNextDirtyFlag()

    -- Purchase Information
    spec.purchasedUsed = false
    spec.purchaseDate = 0
    spec.purchasePrice = 0
    spec.purchaseDamage = 0
    spec.purchaseHours = 0
    spec.wasInspected = false

    -- Hidden Reliability Scores (1.0 = perfect, 0.0 = broken)
    spec.engineReliability = 1.0
    spec.hydraulicReliability = 1.0
    spec.electricalReliability = 1.0

    -- Workhorse/Lemon Scale System (v1.4.0+)
    spec.workhorseLemonScale = 0.5
    spec.maxReliabilityCeiling = 1.0

    -- v2.2.0: Component Durability System
    spec.maxEngineDurability = 1.0
    spec.maxHydraulicDurability = 1.0
    spec.maxElectricalDurability = 1.0

    -- v2.2.0: RVB Integration Tracking
    spec.rvbLifetimeMultiplier = 1.0
    spec.rvbLifetimesApplied = false
    spec.rvbTotalDegradation = 0
    spec.rvbRepairCount = 0
    spec.rvbBreakdownCount = 0

    -- Maintenance History
    spec.repairCount = 0
    spec.totalRepairCost = 0
    spec.lastRepairDate = 0
    spec.failureCount = 0

    -- Inspection Cache (for paid inspections)
    spec.hasInspectionCache = false
    spec.inspectionCacheHours = 0
    spec.inspectionCacheDamage = 0
    spec.inspectionCacheWear = 0

    -- v2.1.0: RVB/UYT Deferred Sync System
    spec.storedRvbPartsData = nil
    spec.storedTireConditions = nil
    spec.rvbDataSynced = false
    spec.tireDataSynced = false

    -- Runtime State (not persisted)
    spec.updateTimer = 0
    spec.stallCooldown = 0
    spec.isStalled = false
    spec.currentMaxSpeed = nil

    -- Electrical cutout state
    spec.cutoutTimer = 0
    spec.isCutout = false
    spec.cutoutEndTime = 0

    -- Hydraulic drift state
    spec.isDrifting = false

    -- v1.5.1: Stall recovery state
    spec.stallRecoveryEndTime = 0

    -- v1.6.0: Startup grace period
    spec.startupGracePeriod = 2000
    spec.lastIsActiveForInput = false

    -- Warning notification state
    spec.hasShownSpeedWarning = false
    spec.speedWarningTimer = 0
    spec.speedWarningInterval = 300000
    spec.hasShownDriftWarning = false
    spec.hasShownDriftMidpointWarning = false

    -- v1.6.0: Steering pull state
    spec.steeringPullDirection = 0
    spec.steeringPullInitialized = false
    spec.steeringPullSurgeTimer = 0
    spec.steeringPullSurgeActive = false
    spec.steeringPullSurgeEndTime = 0
    spec.hasShownPullWarning = false

    -- v1.6.0: Engine misfiring state
    spec.misfireTimer = 0
    spec.misfireActive = false
    spec.misfireEndTime = 0
    spec.misfireBurstRemaining = 0
    spec.hasShownMisfireWarning = false

    -- v1.6.0: Engine overheating state
    spec.engineTemperature = 0
    spec.isOverheated = false
    spec.overheatCooldownEndTime = 0
    spec.hasShownOverheatWarning = false
    spec.hasShownOverheatCritical = false

    -- v1.6.0: Implement malfunction state
    spec.implementMalfunctionTimer = 0
    spec.hasShownSurgeWarning = false
    spec.hasShownDropWarning = false
    spec.hasShownPTOWarning = false
    spec.hasShownHitchWarning = false

    -- v1.7.0: Tire system state
    spec.tireCondition = 1.0
    spec.tireQuality = 2
    spec.tireMaxTraction = 1.0
    spec.tireFailureMultiplier = 1.0
    spec.distanceTraveled = 0
    spec.lastPosition = nil
    spec.hasFlatTire = false
    spec.flatTireSide = 0
    spec.hasShownTireWarnWarning = false
    spec.hasShownTireCriticalWarning = false
    spec.hasShownFlatTireWarning = false
    spec.hasShownLowTractionWarning = false

    -- v2.8.0: Per-wheel distance tracking (unified tire tracking)
    spec.wheelDistances = {0, 0, 0, 0}
    spec.wheelConditions = {1.0, 1.0, 1.0, 1.0}

    -- v1.7.0: Oil system state
    spec.oilLevel = 1.0
    spec.wasLowOil = false
    spec.hasOilLeak = false
    spec.oilLeakSeverity = 0
    spec.engineReliabilityCeiling = 1.0
    spec.hasShownOilWarnWarning = false
    spec.hasShownOilCriticalWarning = false
    spec.hasShownOilLeakWarning = false

    -- v1.7.0: Hydraulic fluid system state
    spec.hydraulicFluidLevel = 1.0
    spec.wasLowHydraulicFluid = false
    spec.hasHydraulicLeak = false
    spec.hydraulicLeakSeverity = 0
    spec.hydraulicReliabilityCeiling = 1.0
    spec.hasShownHydraulicWarnWarning = false
    spec.hasShownHydraulicCriticalWarning = false
    spec.hasShownHydraulicLeakWarning = false

    -- v1.7.0: Fuel leak state
    spec.hasFuelLeak = false
    spec.fuelLeakMultiplier = 1.0
    spec.hasShownFuelLeakWarning = false

    -- v2.4.0: Hydraulic surge event state
    spec.hydraulicSurgeActive = false
    spec.hydraulicSurgeEndTime = 0
    spec.hydraulicSurgeFadeStartTime = 0
    spec.hydraulicSurgeDirection = 0
    spec.hydraulicSurgeCooldownEnd = 0

    -- v2.5.0: RUNAWAY ENGINE state
    spec.runawayActive = false
    spec.runawayStartTime = 0
    spec.runawayPreviousSpeed = 0
    spec.runawayPreviousDamage = 0

    -- v2.5.0: Implement stuck down state
    spec.implementStuckDown = false
    spec.implementStuckDownEndTime = 0

    -- v2.5.0: Implement stuck up state
    spec.implementStuckUp = false
    spec.implementStuckUpEndTime = 0

    -- v2.5.0: Implement steering pull state
    spec.implementPullActive = false
    spec.implementPullEndTime = 0
    spec.implementPullDirection = 0

    -- v2.5.0: Implement speed drag state
    spec.implementDragActive = false
    spec.implementDragEndTime = 0

    -- v2.5.0: Reduced turning state
    spec.reducedTurningActive = false
    spec.reducedTurningEndTime = 0

    -- v2.7.0: Seizure Escalation System
    spec.engineSeized = false
    spec.hydraulicsSeized = false
    spec.electricalSeized = false
    spec.engineSeizedTime = 0
    spec.hydraulicsSeizedTime = 0
    spec.electricalSeizedTime = 0

    -- v2.8.0: Global malfunction cooldown (prevents cascade failures)
    spec.lastMalfunctionTime = 0

    -- v2.8.0: OBD Scanner diagnosis tracking (one-time boost per system)
    -- Prevents exploit of spamming OBD kits for unlimited reliability restoration
    spec.obdDiagnosesUsed = {
        engine = false,
        electrical = false,
        hydraulic = false
    }

    -- v2.9.0: Service Truck Restoration System
    -- isBeingRestored: prevents vehicle from being driven/started during restoration
    -- restorationCooldowns: time-based lockout after failed inspection
    spec.isBeingRestored = false
    spec.restorationCooldowns = {
        engine = 0,
        electrical = 0,
        hydraulic = 0
    }

    UsedPlus.logTrace("UsedPlusMaintenance onLoad complete for: " .. tostring(self:getName()))
end

--[[
    Called after vehicle is fully loaded
    Load saved data from savegame if available
    Pattern from: HeadlandManagement onPostLoad
]]
function UsedPlusMaintenance:onPostLoad(savegame)
    local spec = self.spec_usedPlusMaintenance
    if spec == nil then return end

    if savegame ~= nil then
        local xmlFile = savegame.xmlFile
        local key = savegame.key .. "." .. UsedPlusMaintenance.SPEC_NAME

        -- Load purchase information
        spec.purchasedUsed = xmlFile:getValue(key .. ".purchasedUsed", spec.purchasedUsed)
        spec.purchaseDate = xmlFile:getValue(key .. ".purchaseDate", spec.purchaseDate)
        spec.purchasePrice = xmlFile:getValue(key .. ".purchasePrice", spec.purchasePrice)
        spec.purchaseDamage = xmlFile:getValue(key .. ".purchaseDamage", spec.purchaseDamage)
        spec.purchaseHours = xmlFile:getValue(key .. ".purchaseHours", spec.purchaseHours)
        spec.wasInspected = xmlFile:getValue(key .. ".wasInspected", spec.wasInspected)

        -- Load hidden reliability scores
        spec.engineReliability = xmlFile:getValue(key .. ".engineReliability", spec.engineReliability)
        spec.hydraulicReliability = xmlFile:getValue(key .. ".hydraulicReliability", spec.hydraulicReliability)
        spec.electricalReliability = xmlFile:getValue(key .. ".electricalReliability", spec.electricalReliability)

        -- Load Workhorse/Lemon Scale (v1.4.0+)
        spec.workhorseLemonScale = xmlFile:getValue(key .. ".workhorseLemonScale", spec.workhorseLemonScale)
        spec.maxReliabilityCeiling = xmlFile:getValue(key .. ".maxReliabilityCeiling", spec.maxReliabilityCeiling)

        -- v2.2.0: Load Component Durability System
        spec.maxEngineDurability = xmlFile:getValue(key .. ".maxEngineDurability", spec.maxEngineDurability) or 1.0
        spec.maxHydraulicDurability = xmlFile:getValue(key .. ".maxHydraulicDurability", spec.maxHydraulicDurability) or 1.0
        spec.maxElectricalDurability = xmlFile:getValue(key .. ".maxElectricalDurability", spec.maxElectricalDurability) or 1.0

        -- v2.2.0: Load RVB Integration Tracking
        spec.rvbLifetimeMultiplier = xmlFile:getValue(key .. ".rvbLifetimeMultiplier", spec.rvbLifetimeMultiplier) or 1.0
        spec.rvbLifetimesApplied = xmlFile:getValue(key .. ".rvbLifetimesApplied", spec.rvbLifetimesApplied) or false
        spec.rvbTotalDegradation = xmlFile:getValue(key .. ".rvbTotalDegradation", spec.rvbTotalDegradation) or 0
        spec.rvbRepairCount = xmlFile:getValue(key .. ".rvbRepairCount", spec.rvbRepairCount) or 0
        spec.rvbBreakdownCount = xmlFile:getValue(key .. ".rvbBreakdownCount", spec.rvbBreakdownCount) or 0

        -- Load maintenance history
        spec.repairCount = xmlFile:getValue(key .. ".repairCount", spec.repairCount)
        spec.totalRepairCost = xmlFile:getValue(key .. ".totalRepairCost", spec.totalRepairCost)
        spec.lastRepairDate = xmlFile:getValue(key .. ".lastRepairDate", spec.lastRepairDate)
        spec.failureCount = xmlFile:getValue(key .. ".failureCount", spec.failureCount)

        -- Load inspection cache
        spec.hasInspectionCache = xmlFile:getValue(key .. ".hasInspectionCache", spec.hasInspectionCache)
        spec.inspectionCacheHours = xmlFile:getValue(key .. ".inspectionCacheHours", spec.inspectionCacheHours)
        spec.inspectionCacheDamage = xmlFile:getValue(key .. ".inspectionCacheDamage", spec.inspectionCacheDamage)
        spec.inspectionCacheWear = xmlFile:getValue(key .. ".inspectionCacheWear", spec.inspectionCacheWear)

        -- v1.7.0: Load tire system state
        spec.tireCondition = xmlFile:getValue(key .. ".tireCondition", spec.tireCondition) or 1.0
        spec.tireQuality = xmlFile:getValue(key .. ".tireQuality", spec.tireQuality) or 2
        spec.distanceTraveled = xmlFile:getValue(key .. ".distanceTraveled", spec.distanceTraveled) or 0
        spec.hasFlatTire = xmlFile:getValue(key .. ".hasFlatTire", spec.hasFlatTire) or false
        spec.flatTireSide = xmlFile:getValue(key .. ".flatTireSide", spec.flatTireSide) or 0

        -- v2.8.0: Load per-wheel distances and recalculate conditions
        spec.wheelDistances = spec.wheelDistances or {0, 0, 0, 0}
        spec.wheelConditions = spec.wheelConditions or {1.0, 1.0, 1.0, 1.0}
        spec.wheelDistances[1] = xmlFile:getValue(key .. ".wheelDistances.w1", spec.wheelDistances[1]) or 0
        spec.wheelDistances[2] = xmlFile:getValue(key .. ".wheelDistances.w2", spec.wheelDistances[2]) or 0
        spec.wheelDistances[3] = xmlFile:getValue(key .. ".wheelDistances.w3", spec.wheelDistances[3]) or 0
        spec.wheelDistances[4] = xmlFile:getValue(key .. ".wheelDistances.w4", spec.wheelDistances[4]) or 0

        -- Recalculate per-wheel conditions from loaded distances
        local config = UsedPlusMaintenance.CONFIG
        local baseDistance = (config and config.tireWearDistanceBase) or 240000
        for i = 1, 4 do
            local wheelWear = math.min(1.0, spec.wheelDistances[i] / baseDistance)
            spec.wheelConditions[i] = math.max(0, 1.0 - wheelWear)
        end

        -- Apply tire quality modifiers after loading
        if spec.tireQuality == 1 then
            spec.tireMaxTraction = UsedPlusMaintenance.CONFIG.tireRetreadTractionMult
            spec.tireFailureMultiplier = UsedPlusMaintenance.CONFIG.tireRetreadFailureMult
        elseif spec.tireQuality == 3 then
            spec.tireMaxTraction = UsedPlusMaintenance.CONFIG.tireQualityTractionMult
            spec.tireFailureMultiplier = UsedPlusMaintenance.CONFIG.tireQualityFailureMult
        else
            spec.tireMaxTraction = UsedPlusMaintenance.CONFIG.tireNormalTractionMult
            spec.tireFailureMultiplier = UsedPlusMaintenance.CONFIG.tireNormalFailureMult
        end

        -- v1.7.0: Load oil system state
        spec.oilLevel = xmlFile:getValue(key .. ".oilLevel", spec.oilLevel) or 1.0
        spec.wasLowOil = xmlFile:getValue(key .. ".wasLowOil", spec.wasLowOil) or false
        spec.hasOilLeak = xmlFile:getValue(key .. ".hasOilLeak", spec.hasOilLeak) or false
        spec.oilLeakSeverity = xmlFile:getValue(key .. ".oilLeakSeverity", spec.oilLeakSeverity) or 1.0
        spec.engineReliabilityCeiling = xmlFile:getValue(key .. ".engineReliabilityCeiling", spec.engineReliabilityCeiling) or 1.0

        -- v1.7.0: Load hydraulic fluid system state
        spec.hydraulicFluidLevel = xmlFile:getValue(key .. ".hydraulicFluidLevel", spec.hydraulicFluidLevel) or 1.0
        spec.wasLowHydraulicFluid = xmlFile:getValue(key .. ".wasLowHydraulicFluid", spec.wasLowHydraulicFluid) or false
        spec.hasHydraulicLeak = xmlFile:getValue(key .. ".hasHydraulicLeak", spec.hasHydraulicLeak) or false
        spec.hydraulicLeakSeverity = xmlFile:getValue(key .. ".hydraulicLeakSeverity", spec.hydraulicLeakSeverity) or 1.0
        spec.hydraulicReliabilityCeiling = xmlFile:getValue(key .. ".hydraulicReliabilityCeiling", spec.hydraulicReliabilityCeiling) or 1.0

        -- v1.7.0: Load fuel leak state
        spec.hasFuelLeak = xmlFile:getValue(key .. ".hasFuelLeak", spec.hasFuelLeak) or false
        spec.fuelLeakMultiplier = xmlFile:getValue(key .. ".fuelLeakMultiplier", spec.fuelLeakMultiplier) or 1.0

        -- v2.4.0: Load hydraulic surge cooldown
        spec.hydraulicSurgeCooldownEnd = xmlFile:getValue(key .. ".hydraulicSurgeCooldownEnd", spec.hydraulicSurgeCooldownEnd) or 0

        -- v2.7.0: Load seizure state
        spec.engineSeized = xmlFile:getValue(key .. ".engineSeized", spec.engineSeized) or false
        spec.hydraulicsSeized = xmlFile:getValue(key .. ".hydraulicsSeized", spec.hydraulicsSeized) or false
        spec.electricalSeized = xmlFile:getValue(key .. ".electricalSeized", spec.electricalSeized) or false
        spec.engineSeizedTime = xmlFile:getValue(key .. ".engineSeizedTime", spec.engineSeizedTime) or 0
        spec.hydraulicsSeizedTime = xmlFile:getValue(key .. ".hydraulicsSeizedTime", spec.hydraulicsSeizedTime) or 0
        spec.electricalSeizedTime = xmlFile:getValue(key .. ".electricalSeizedTime", spec.electricalSeizedTime) or 0

        -- v2.8.0: Load OBD diagnosis tracking (one-time boost per system)
        spec.obdDiagnosesUsed = spec.obdDiagnosesUsed or {}
        spec.obdDiagnosesUsed.engine = xmlFile:getValue(key .. ".obdDiagnosedEngine", false)
        spec.obdDiagnosesUsed.electrical = xmlFile:getValue(key .. ".obdDiagnosedElectrical", false)
        spec.obdDiagnosesUsed.hydraulic = xmlFile:getValue(key .. ".obdDiagnosedHydraulic", false)

        -- v2.9.0: Load Service Truck restoration cooldowns
        spec.isBeingRestored = xmlFile:getValue(key .. ".isBeingRestored", false)
        spec.restorationCooldowns = spec.restorationCooldowns or {}
        spec.restorationCooldowns.engine = xmlFile:getValue(key .. ".restorationCooldowns.engine", 0)
        spec.restorationCooldowns.electrical = xmlFile:getValue(key .. ".restorationCooldowns.electrical", 0)
        spec.restorationCooldowns.hydraulic = xmlFile:getValue(key .. ".restorationCooldowns.hydraulic", 0)

        -- v2.1.0: Load RVB/UYT deferred sync data
        spec.rvbDataSynced = xmlFile:getValue(key .. ".rvbDataSynced", spec.rvbDataSynced) or false
        spec.tireDataSynced = xmlFile:getValue(key .. ".tireDataSynced", spec.tireDataSynced) or false

        -- Load stored RVB parts data
        local rvbKey = key .. ".storedRvbParts"
        local rvbParts = { "ENGINE", "THERMOSTAT", "GENERATOR", "BATTERY", "SELFSTARTER", "GLOWPLUG" }
        for _, partName in ipairs(rvbParts) do
            local partKey = rvbKey .. "." .. partName
            if xmlFile:hasProperty(partKey .. "#life") then
                spec.storedRvbPartsData = spec.storedRvbPartsData or {}
                spec.storedRvbPartsData[partName] = {
                    life = xmlFile:getValue(partKey .. "#life", 1.0),
                    operatingHours = xmlFile:getValue(partKey .. "#operatingHours", 0),
                    lifetime = xmlFile:getValue(partKey .. "#lifetime", 1000)
                }
            end
        end

        -- Load stored tire conditions
        local tireKey = key .. ".storedTires"
        if xmlFile:hasProperty(tireKey .. "#FL") then
            spec.storedTireConditions = {
                FL = xmlFile:getValue(tireKey .. "#FL", 1.0),
                FR = xmlFile:getValue(tireKey .. "#FR", 1.0),
                RL = xmlFile:getValue(tireKey .. "#RL", 1.0),
                RR = xmlFile:getValue(tireKey .. "#RR", 1.0)
            }
        end

        UsedPlus.logTrace(string.format("UsedPlusMaintenance loaded for %s: used=%s, engine=%.2f, repairs=%d, tires=%.0f%%, oil=%.0f%%",
            self:getName(), tostring(spec.purchasedUsed), spec.engineReliability, spec.repairCount,
            spec.tireCondition * 100, spec.oilLevel * 100))

        -- v2.1.0: Check if we need to sync RVB/UYT data after load
        UsedPlusMaintenance.checkAndSyncCrossModData(self)
    end
end

--[[
    Save vehicle data to XML
    Pattern from: HeadlandManagement saveToXMLFile
]]
function UsedPlusMaintenance:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Save purchase information
    xmlFile:setValue(key .. ".purchasedUsed", spec.purchasedUsed)
    xmlFile:setValue(key .. ".purchaseDate", spec.purchaseDate)
    xmlFile:setValue(key .. ".purchasePrice", spec.purchasePrice)
    xmlFile:setValue(key .. ".purchaseDamage", spec.purchaseDamage)
    xmlFile:setValue(key .. ".purchaseHours", spec.purchaseHours)
    xmlFile:setValue(key .. ".wasInspected", spec.wasInspected)

    -- Save hidden reliability scores
    xmlFile:setValue(key .. ".engineReliability", spec.engineReliability)
    xmlFile:setValue(key .. ".hydraulicReliability", spec.hydraulicReliability)
    xmlFile:setValue(key .. ".electricalReliability", spec.electricalReliability)

    -- Save Workhorse/Lemon Scale (v1.4.0+)
    xmlFile:setValue(key .. ".workhorseLemonScale", spec.workhorseLemonScale)
    xmlFile:setValue(key .. ".maxReliabilityCeiling", spec.maxReliabilityCeiling)

    -- v2.2.0: Save Component Durability System
    xmlFile:setValue(key .. ".maxEngineDurability", spec.maxEngineDurability)
    xmlFile:setValue(key .. ".maxHydraulicDurability", spec.maxHydraulicDurability)
    xmlFile:setValue(key .. ".maxElectricalDurability", spec.maxElectricalDurability)

    -- v2.2.0: Save RVB Integration Tracking
    xmlFile:setValue(key .. ".rvbLifetimeMultiplier", spec.rvbLifetimeMultiplier)
    xmlFile:setValue(key .. ".rvbLifetimesApplied", spec.rvbLifetimesApplied)
    xmlFile:setValue(key .. ".rvbTotalDegradation", spec.rvbTotalDegradation)
    xmlFile:setValue(key .. ".rvbRepairCount", spec.rvbRepairCount)
    xmlFile:setValue(key .. ".rvbBreakdownCount", spec.rvbBreakdownCount)

    -- Save maintenance history
    xmlFile:setValue(key .. ".repairCount", spec.repairCount)
    xmlFile:setValue(key .. ".totalRepairCost", spec.totalRepairCost)
    xmlFile:setValue(key .. ".lastRepairDate", spec.lastRepairDate)
    xmlFile:setValue(key .. ".failureCount", spec.failureCount)

    -- Save inspection cache
    xmlFile:setValue(key .. ".hasInspectionCache", spec.hasInspectionCache)
    xmlFile:setValue(key .. ".inspectionCacheHours", spec.inspectionCacheHours)
    xmlFile:setValue(key .. ".inspectionCacheDamage", spec.inspectionCacheDamage)
    xmlFile:setValue(key .. ".inspectionCacheWear", spec.inspectionCacheWear)

    -- v1.7.0: Save tire system state
    xmlFile:setValue(key .. ".tireCondition", spec.tireCondition)
    xmlFile:setValue(key .. ".tireQuality", spec.tireQuality)
    xmlFile:setValue(key .. ".distanceTraveled", spec.distanceTraveled)
    xmlFile:setValue(key .. ".hasFlatTire", spec.hasFlatTire)
    xmlFile:setValue(key .. ".flatTireSide", spec.flatTireSide)

    -- v2.8.0: Save per-wheel distances
    if spec.wheelDistances then
        xmlFile:setValue(key .. ".wheelDistances.w1", spec.wheelDistances[1] or 0)
        xmlFile:setValue(key .. ".wheelDistances.w2", spec.wheelDistances[2] or 0)
        xmlFile:setValue(key .. ".wheelDistances.w3", spec.wheelDistances[3] or 0)
        xmlFile:setValue(key .. ".wheelDistances.w4", spec.wheelDistances[4] or 0)
    end

    -- v1.7.0: Save oil system state
    xmlFile:setValue(key .. ".oilLevel", spec.oilLevel)
    xmlFile:setValue(key .. ".wasLowOil", spec.wasLowOil)
    xmlFile:setValue(key .. ".hasOilLeak", spec.hasOilLeak)
    xmlFile:setValue(key .. ".oilLeakSeverity", spec.oilLeakSeverity)
    xmlFile:setValue(key .. ".engineReliabilityCeiling", spec.engineReliabilityCeiling)

    -- v1.7.0: Save hydraulic fluid system state
    xmlFile:setValue(key .. ".hydraulicFluidLevel", spec.hydraulicFluidLevel)
    xmlFile:setValue(key .. ".wasLowHydraulicFluid", spec.wasLowHydraulicFluid)
    xmlFile:setValue(key .. ".hasHydraulicLeak", spec.hasHydraulicLeak)
    xmlFile:setValue(key .. ".hydraulicLeakSeverity", spec.hydraulicLeakSeverity)
    xmlFile:setValue(key .. ".hydraulicReliabilityCeiling", spec.hydraulicReliabilityCeiling)

    -- v1.7.0: Save fuel leak state
    xmlFile:setValue(key .. ".hasFuelLeak", spec.hasFuelLeak)
    xmlFile:setValue(key .. ".fuelLeakMultiplier", spec.fuelLeakMultiplier)

    -- v2.4.0: Save hydraulic surge cooldown
    xmlFile:setValue(key .. ".hydraulicSurgeCooldownEnd", spec.hydraulicSurgeCooldownEnd or 0)

    -- v2.7.0: Save seizure state
    xmlFile:setValue(key .. ".engineSeized", spec.engineSeized or false)
    xmlFile:setValue(key .. ".hydraulicsSeized", spec.hydraulicsSeized or false)
    xmlFile:setValue(key .. ".electricalSeized", spec.electricalSeized or false)
    xmlFile:setValue(key .. ".engineSeizedTime", spec.engineSeizedTime or 0)
    xmlFile:setValue(key .. ".hydraulicsSeizedTime", spec.hydraulicsSeizedTime or 0)
    xmlFile:setValue(key .. ".electricalSeizedTime", spec.electricalSeizedTime or 0)

    -- v2.8.0: Save OBD diagnosis tracking (one-time boost per system)
    if spec.obdDiagnosesUsed then
        xmlFile:setValue(key .. ".obdDiagnosedEngine", spec.obdDiagnosesUsed.engine or false)
        xmlFile:setValue(key .. ".obdDiagnosedElectrical", spec.obdDiagnosesUsed.electrical or false)
        xmlFile:setValue(key .. ".obdDiagnosedHydraulic", spec.obdDiagnosesUsed.hydraulic or false)
    end

    -- v2.9.0: Save Service Truck restoration cooldowns
    xmlFile:setValue(key .. ".isBeingRestored", spec.isBeingRestored or false)
    if spec.restorationCooldowns then
        xmlFile:setValue(key .. ".restorationCooldowns.engine", spec.restorationCooldowns.engine or 0)
        xmlFile:setValue(key .. ".restorationCooldowns.electrical", spec.restorationCooldowns.electrical or 0)
        xmlFile:setValue(key .. ".restorationCooldowns.hydraulic", spec.restorationCooldowns.hydraulic or 0)
    end

    -- v2.1.0: Save RVB/UYT deferred sync data
    xmlFile:setValue(key .. ".rvbDataSynced", spec.rvbDataSynced)
    xmlFile:setValue(key .. ".tireDataSynced", spec.tireDataSynced)

    -- Save stored RVB parts data
    if spec.storedRvbPartsData then
        local rvbKey = key .. ".storedRvbParts"
        for partName, partData in pairs(spec.storedRvbPartsData) do
            xmlFile:setValue(rvbKey .. "." .. partName .. "#life", partData.life or 1.0)
            xmlFile:setValue(rvbKey .. "." .. partName .. "#operatingHours", partData.operatingHours or 0)
            xmlFile:setValue(rvbKey .. "." .. partName .. "#lifetime", partData.lifetime or 1000)
        end
    end

    -- Save stored tire conditions
    if spec.storedTireConditions then
        local tireKey = key .. ".storedTires"
        xmlFile:setValue(tireKey .. "#FL", spec.storedTireConditions.FL or 1.0)
        xmlFile:setValue(tireKey .. "#FR", spec.storedTireConditions.FR or 1.0)
        xmlFile:setValue(tireKey .. "#RL", spec.storedTireConditions.RL or 1.0)
        xmlFile:setValue(tireKey .. "#RR", spec.storedTireConditions.RR or 1.0)
    end

    UsedPlus.logTrace(string.format("UsedPlusMaintenance saved for %s", self:getName()))
end

--[[
    Helper: Read all maintenance data from a network stream
    Used by both onReadStream (initial join) and onReadUpdateStream (incremental sync)
]]
function UsedPlusMaintenance:readMaintenanceData(streamId)
    local spec = self.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Purchase info
    spec.purchasedUsed = streamReadBool(streamId)
    spec.purchaseDate = streamReadFloat32(streamId)
    spec.purchasePrice = streamReadFloat32(streamId)
    spec.purchaseDamage = streamReadFloat32(streamId)
    spec.purchaseHours = streamReadFloat32(streamId)
    spec.wasInspected = streamReadBool(streamId)

    -- Reliability scores
    spec.engineReliability = streamReadFloat32(streamId)
    spec.hydraulicReliability = streamReadFloat32(streamId)
    spec.electricalReliability = streamReadFloat32(streamId)

    -- Workhorse/Lemon Scale
    spec.workhorseLemonScale = streamReadFloat32(streamId)
    spec.maxReliabilityCeiling = streamReadFloat32(streamId)

    -- Component Durability System
    spec.maxEngineDurability = streamReadFloat32(streamId)
    spec.maxHydraulicDurability = streamReadFloat32(streamId)
    spec.maxElectricalDurability = streamReadFloat32(streamId)

    -- RVB Integration Tracking
    spec.rvbLifetimeMultiplier = streamReadFloat32(streamId)
    spec.rvbLifetimesApplied = streamReadBool(streamId)
    spec.rvbTotalDegradation = streamReadFloat32(streamId)
    spec.rvbRepairCount = streamReadInt32(streamId)
    spec.rvbBreakdownCount = streamReadInt32(streamId)

    -- Maintenance history
    spec.repairCount = streamReadInt32(streamId)
    spec.totalRepairCost = streamReadFloat32(streamId)
    spec.lastRepairDate = streamReadFloat32(streamId)
    spec.failureCount = streamReadInt32(streamId)

    -- Inspection cache
    spec.hasInspectionCache = streamReadBool(streamId)
    spec.inspectionCacheHours = streamReadFloat32(streamId)
    spec.inspectionCacheDamage = streamReadFloat32(streamId)
    spec.inspectionCacheWear = streamReadFloat32(streamId)

    -- Tire system
    spec.tireCondition = streamReadFloat32(streamId)
    spec.tireQuality = streamReadInt8(streamId)
    spec.distanceTraveled = streamReadFloat32(streamId)
    spec.hasFlatTire = streamReadBool(streamId)
    spec.flatTireSide = streamReadInt8(streamId)

    -- Per-wheel distances
    spec.wheelDistances = spec.wheelDistances or {0, 0, 0, 0}
    spec.wheelConditions = spec.wheelConditions or {1.0, 1.0, 1.0, 1.0}
    for i = 1, 4 do
        spec.wheelDistances[i] = streamReadFloat32(streamId)
    end
    -- Recalculate conditions from distances
    local config = UsedPlusMaintenance.CONFIG
    local baseDistance = (config and config.tireWearDistanceBase) or 240000
    for i = 1, 4 do
        local wheelWear = math.min(1.0, spec.wheelDistances[i] / baseDistance)
        spec.wheelConditions[i] = math.max(0, 1.0 - wheelWear)
    end

    -- Apply tire quality modifiers after reading
    if spec.tireQuality == 1 then
        spec.tireMaxTraction = (config and config.tireRetreadTractionMult) or 0.95
        spec.tireFailureMultiplier = (config and config.tireRetreadFailureMult) or 1.5
    elseif spec.tireQuality == 3 then
        spec.tireMaxTraction = (config and config.tireQualityTractionMult) or 1.05
        spec.tireFailureMultiplier = (config and config.tireQualityFailureMult) or 0.7
    else
        spec.tireMaxTraction = (config and config.tireNormalTractionMult) or 1.0
        spec.tireFailureMultiplier = (config and config.tireNormalFailureMult) or 1.0
    end

    -- Oil system
    spec.oilLevel = streamReadFloat32(streamId)
    spec.wasLowOil = streamReadBool(streamId)
    spec.hasOilLeak = streamReadBool(streamId)
    spec.oilLeakSeverity = streamReadInt8(streamId)
    spec.engineReliabilityCeiling = streamReadFloat32(streamId)

    -- Hydraulic fluid system
    spec.hydraulicFluidLevel = streamReadFloat32(streamId)
    spec.wasLowHydraulicFluid = streamReadBool(streamId)
    spec.hasHydraulicLeak = streamReadBool(streamId)
    spec.hydraulicLeakSeverity = streamReadInt8(streamId)
    spec.hydraulicReliabilityCeiling = streamReadFloat32(streamId)

    -- Fuel leak
    spec.hasFuelLeak = streamReadBool(streamId)
    spec.fuelLeakMultiplier = streamReadFloat32(streamId)

    -- Hydraulic surge event
    spec.hydraulicSurgeActive = streamReadBool(streamId)
    spec.hydraulicSurgeEndTime = streamReadFloat32(streamId)
    spec.hydraulicSurgeFadeStartTime = streamReadFloat32(streamId)
    spec.hydraulicSurgeDirection = streamReadInt8(streamId)
    spec.hydraulicSurgeCooldownEnd = streamReadFloat32(streamId)

    -- Comprehensive hydraulic malfunctions
    spec.runawayActive = streamReadBool(streamId)
    spec.runawayStartTime = streamReadFloat32(streamId)
    spec.implementStuckDown = streamReadBool(streamId)
    spec.implementStuckDownEndTime = streamReadFloat32(streamId)
    spec.implementStuckUp = streamReadBool(streamId)
    spec.implementStuckUpEndTime = streamReadFloat32(streamId)
    spec.implementPullActive = streamReadBool(streamId)
    spec.implementPullEndTime = streamReadFloat32(streamId)
    spec.implementPullDirection = streamReadInt8(streamId)
    spec.implementDragActive = streamReadBool(streamId)
    spec.implementDragEndTime = streamReadFloat32(streamId)
    spec.reducedTurningActive = streamReadBool(streamId)
    spec.reducedTurningEndTime = streamReadFloat32(streamId)

    -- Seizure escalation
    spec.engineSeized = streamReadBool(streamId)
    spec.hydraulicsSeized = streamReadBool(streamId)
    spec.electricalSeized = streamReadBool(streamId)

    -- Global malfunction cooldown
    spec.lastMalfunctionTime = streamReadFloat32(streamId)

    -- OBD diagnosis tracking (one-time boost per system)
    spec.obdDiagnosesUsed = spec.obdDiagnosesUsed or {}
    spec.obdDiagnosesUsed.engine = streamReadBool(streamId)
    spec.obdDiagnosesUsed.electrical = streamReadBool(streamId)
    spec.obdDiagnosesUsed.hydraulic = streamReadBool(streamId)
end

--[[
    Helper: Write all maintenance data to a network stream
    Used by both onWriteStream (initial join) and onWriteUpdateStream (incremental sync)
]]
function UsedPlusMaintenance:writeMaintenanceData(streamId)
    local spec = self.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Purchase info
    streamWriteBool(streamId, spec.purchasedUsed)
    streamWriteFloat32(streamId, spec.purchaseDate)
    streamWriteFloat32(streamId, spec.purchasePrice)
    streamWriteFloat32(streamId, spec.purchaseDamage)
    streamWriteFloat32(streamId, spec.purchaseHours)
    streamWriteBool(streamId, spec.wasInspected)

    -- Reliability scores
    streamWriteFloat32(streamId, spec.engineReliability)
    streamWriteFloat32(streamId, spec.hydraulicReliability)
    streamWriteFloat32(streamId, spec.electricalReliability)

    -- Workhorse/Lemon Scale
    streamWriteFloat32(streamId, spec.workhorseLemonScale)
    streamWriteFloat32(streamId, spec.maxReliabilityCeiling)

    -- Component Durability System
    streamWriteFloat32(streamId, spec.maxEngineDurability)
    streamWriteFloat32(streamId, spec.maxHydraulicDurability)
    streamWriteFloat32(streamId, spec.maxElectricalDurability)

    -- RVB Integration Tracking
    streamWriteFloat32(streamId, spec.rvbLifetimeMultiplier)
    streamWriteBool(streamId, spec.rvbLifetimesApplied)
    streamWriteFloat32(streamId, spec.rvbTotalDegradation)
    streamWriteInt32(streamId, spec.rvbRepairCount)
    streamWriteInt32(streamId, spec.rvbBreakdownCount)

    -- Maintenance history
    streamWriteInt32(streamId, spec.repairCount)
    streamWriteFloat32(streamId, spec.totalRepairCost)
    streamWriteFloat32(streamId, spec.lastRepairDate)
    streamWriteInt32(streamId, spec.failureCount)

    -- Inspection cache
    streamWriteBool(streamId, spec.hasInspectionCache)
    streamWriteFloat32(streamId, spec.inspectionCacheHours)
    streamWriteFloat32(streamId, spec.inspectionCacheDamage)
    streamWriteFloat32(streamId, spec.inspectionCacheWear)

    -- Tire system
    streamWriteFloat32(streamId, spec.tireCondition)
    streamWriteInt8(streamId, spec.tireQuality)
    streamWriteFloat32(streamId, spec.distanceTraveled)
    streamWriteBool(streamId, spec.hasFlatTire)
    streamWriteInt8(streamId, spec.flatTireSide)

    -- Per-wheel distances
    for i = 1, 4 do
        streamWriteFloat32(streamId, (spec.wheelDistances and spec.wheelDistances[i]) or 0)
    end

    -- Oil system
    streamWriteFloat32(streamId, spec.oilLevel)
    streamWriteBool(streamId, spec.wasLowOil)
    streamWriteBool(streamId, spec.hasOilLeak)
    streamWriteInt8(streamId, spec.oilLeakSeverity)
    streamWriteFloat32(streamId, spec.engineReliabilityCeiling)

    -- Hydraulic fluid system
    streamWriteFloat32(streamId, spec.hydraulicFluidLevel)
    streamWriteBool(streamId, spec.wasLowHydraulicFluid)
    streamWriteBool(streamId, spec.hasHydraulicLeak)
    streamWriteInt8(streamId, spec.hydraulicLeakSeverity)
    streamWriteFloat32(streamId, spec.hydraulicReliabilityCeiling)

    -- Fuel leak
    streamWriteBool(streamId, spec.hasFuelLeak)
    streamWriteFloat32(streamId, spec.fuelLeakMultiplier)

    -- Hydraulic surge event
    streamWriteBool(streamId, spec.hydraulicSurgeActive or false)
    streamWriteFloat32(streamId, spec.hydraulicSurgeEndTime or 0)
    streamWriteFloat32(streamId, spec.hydraulicSurgeFadeStartTime or 0)
    streamWriteInt8(streamId, spec.hydraulicSurgeDirection or 0)
    streamWriteFloat32(streamId, spec.hydraulicSurgeCooldownEnd or 0)

    -- Comprehensive hydraulic malfunctions
    streamWriteBool(streamId, spec.runawayActive or false)
    streamWriteFloat32(streamId, spec.runawayStartTime or 0)
    streamWriteBool(streamId, spec.implementStuckDown or false)
    streamWriteFloat32(streamId, spec.implementStuckDownEndTime or 0)
    streamWriteBool(streamId, spec.implementStuckUp or false)
    streamWriteFloat32(streamId, spec.implementStuckUpEndTime or 0)
    streamWriteBool(streamId, spec.implementPullActive or false)
    streamWriteFloat32(streamId, spec.implementPullEndTime or 0)
    streamWriteInt8(streamId, spec.implementPullDirection or 0)
    streamWriteBool(streamId, spec.implementDragActive or false)
    streamWriteFloat32(streamId, spec.implementDragEndTime or 0)
    streamWriteBool(streamId, spec.reducedTurningActive or false)
    streamWriteFloat32(streamId, spec.reducedTurningEndTime or 0)

    -- Seizure escalation
    streamWriteBool(streamId, spec.engineSeized or false)
    streamWriteBool(streamId, spec.hydraulicsSeized or false)
    streamWriteBool(streamId, spec.electricalSeized or false)

    -- Global malfunction cooldown
    streamWriteFloat32(streamId, spec.lastMalfunctionTime or 0)

    -- OBD diagnosis tracking (one-time boost per system)
    local obdUsed = spec.obdDiagnosesUsed or {}
    streamWriteBool(streamId, obdUsed.engine or false)
    streamWriteBool(streamId, obdUsed.electrical or false)
    streamWriteBool(streamId, obdUsed.hydraulic or false)
end

--[[
    Read data from network stream (multiplayer client join)
]]
function UsedPlusMaintenance:onReadStream(streamId, connection)
    self:readMaintenanceData(streamId)
    UsedPlus.logTrace("UsedPlusMaintenance onReadStream complete")
end

--[[
    Write data to network stream (multiplayer client join)
]]
function UsedPlusMaintenance:onWriteStream(streamId, connection)
    self:writeMaintenanceData(streamId)
    UsedPlus.logTrace("UsedPlusMaintenance onWriteStream complete")
end

--[[
    Read incremental update from server (multiplayer runtime sync)
    Called when server raises dirty flags via raiseDirtyFlags()
]]
function UsedPlusMaintenance:onReadUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() then
        if streamReadBool(streamId) then
            self:readMaintenanceData(streamId)
        end
    end
end

--[[
    Write incremental update to clients (multiplayer runtime sync)
    Triggered by raiseDirtyFlags(spec.dirtyFlag) on the server
]]
function UsedPlusMaintenance:onWriteUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer() then
        local spec = self.spec_usedPlusMaintenance
        if streamWriteBool(streamId, bitAND(dirtyMask, spec.dirtyFlag) ~= 0) then
            self:writeMaintenanceData(streamId)
        end
    end
end

--[[
    Check if vehicle is sleeping (inactive, can skip expensive updates)
    Pattern from: MoreRealistic_FS25 sleep/wake optimization

    A vehicle is "sleeping" if:
    - Not player-controlled
    - Not moving (speed < 0.1 km/h)
    - Not AI-active
    - Engine off

    @param vehicle - The vehicle to check
    @return isSleeping (boolean)
]]
function UsedPlusMaintenance.isSleeping(vehicle)
    -- Player-controlled vehicles are always awake
    if vehicle.isActiveForInput or vehicle.isActiveForInputIgnoreSelection then
        return false
    end

    -- Check AI activity
    if vehicle.spec_aiVehicle and vehicle.spec_aiVehicle.isActive then
        return false
    end

    -- Check movement (speed check BEFORE engine check - catches towed vehicles)
    local speed = vehicle:getLastSpeed() or 0
    if speed > 0.1 then  -- >0.1 km/h = moving
        return false
    end

    -- Check engine state
    if vehicle.spec_motorized then
        if vehicle.spec_motorized.isMotorStarted then
            return false
        end
    end

    -- Vehicle is idle - can sleep
    return true
end

--[[
    Called every frame when vehicle is active
    Dispatches to module update functions
    Pattern from: HeadlandManagement onUpdate
]]
function UsedPlusMaintenance:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self.spec_usedPlusMaintenance
    if spec == nil then return end

    -- v1.7.1: Track player control state
    spec.lastIsActiveForInput = isActiveForInput

    -- v1.7.1: Countdown startup grace period
    if isActiveForInput and spec.startupGracePeriod and spec.startupGracePeriod > 0 then
        spec.startupGracePeriod = spec.startupGracePeriod - dt
    end

    -- Only process failure simulation on server
    if not self.isServer then return end

    -- v2.8.0: Sleep/wake optimization - skip expensive checks for idle vehicles
    -- Pattern from: MoreRealistic_FS25 performance optimization
    if UsedPlusMaintenance.isSleeping(self) then
        -- Still update critical timers even when sleeping
        if spec.stallCooldown > 0 then
            spec.stallCooldown = spec.stallCooldown - dt
        end
        return  -- Skip all other maintenance checks
    end

    -- Vehicle is awake - process normal maintenance updates

    -- Update stall cooldown
    if spec.stallCooldown > 0 then
        spec.stallCooldown = spec.stallCooldown - dt
    end

    -- v1.5.1: Process first-start stall timer
    if spec.firstStartStallPending and spec.firstStartStallTimer then
        spec.firstStartStallTimer = spec.firstStartStallTimer - dt
        if spec.firstStartStallTimer <= 0 then
            spec.firstStartStallPending = false
            spec.firstStartStallTimer = nil
            UsedPlusMaintenance.triggerEngineStall(self, true)  -- true = isFirstStart
        end
    end

    -- ========== GRADUAL WORKSHOP REPAIR (RVB integration) ==========
    -- All systems (hydraulic, engine, fluids, base damage) repair gradually
    -- alongside RVB's time-based component repair over the same time window.
    if spec.pendingHydraulicRepair then
        -- Keep vehicle active so onUpdate keeps firing during repair
        self:raiseActive()

        local pending = spec.pendingHydraulicRepair
        local rvb = self.spec_faultData
        local env = g_currentMission.environment
        local nowMinutes = (env.currentDay * 24 * 60) + (env.currentHour * 60) + env.currentMinute
        local totalDuration = pending.finishMinutes - pending.startMinutes
        local elapsed = nowMinutes - pending.startMinutes
        local progress = math.min(1.0, math.max(0, elapsed / totalDuration))

        -- Check if repair is done.
        -- useTimeProgress: hydraulic-only repair (no RVB parts) — use elapsed time only.
        -- Otherwise sync with RVB's repair state (state == NONE == 0 means finished).
        local repairDone = false
        if pending.useTimeProgress then
            repairDone = (progress >= 1.0)
        elseif rvb and rvb.repair and rvb.repair.state then
            repairDone = (rvb.repair.state == 0)
        else
            repairDone = (progress >= 1.0)
        end
        if repairDone then progress = 1.0 end

        -- Lerp hydraulic reliability
        local hydRange = pending.targetHydraulic - pending.startHydraulic
        spec.hydraulicReliability = pending.startHydraulic + (hydRange * progress)

        -- Lerp engine reliability
        local engRange = pending.targetEngine - pending.startEngine
        spec.engineReliability = pending.startEngine + (engRange * progress)

        -- Lerp base vehicle damage (reduce toward 0)
        if pending.startDamage and pending.startDamage > 0.001 then
            local targetDamage = pending.startDamage * (1.0 - progress)
            if self.getDamageAmount and self.addDamageAmount then
                local currentDamage = self:getDamageAmount() or 0
                local desiredReduction = currentDamage - targetDamage
                if desiredReduction > 0.001 then
                    self:addDamageAmount(-desiredReduction, true)
                end
            end
        end

        -- Lerp fluid levels (only upward — don't reduce if already full)
        if pending.startHydFluid < 1.0 then
            spec.hydraulicFluidLevel = pending.startHydFluid + ((1.0 - pending.startHydFluid) * progress)
        end
        if pending.startOil < 1.0 then
            spec.oilLevel = pending.startOil + ((1.0 - pending.startOil) * progress)
        end

        -- Deduct cost at halfway point (RVB deducts at completion, we split the difference)
        if not pending.costDeducted and progress >= 0.5 then
            if pending.cost and pending.cost > 0 and pending.farmId then
                if g_currentMission:getMoney(pending.farmId) >= pending.cost then
                    g_currentMission:addMoney(-pending.cost, pending.farmId, MoneyType.VEHICLE_RUNNING_COSTS, true)
                    UsedPlus.logInfo(string.format("Hydraulic repair cost deducted: $%d", pending.cost))
                end
            end
            pending.costDeducted = true
        end

        -- Finalize when done
        if repairDone then
            -- Snap to exact targets
            spec.hydraulicReliability = pending.targetHydraulic
            spec.engineReliability = pending.targetEngine
            -- Snap base damage to 0 (fully repaired)
            if pending.startDamage and pending.startDamage > 0.001 then
                if self.getDamageAmount and self.addDamageAmount then
                    local remaining = self:getDamageAmount() or 0
                    if remaining > 0.001 then
                        self:addDamageAmount(-remaining, true)
                    end
                end
            end
            if pending.startHydFluid < 1.0 then
                spec.hydraulicFluidLevel = 1.0
                spec.hasHydraulicLeak = false
                spec.hydraulicLeakSeverity = 0
            end
            if pending.startOil < 1.0 then
                spec.oilLevel = 1.0
                spec.hasOilLeak = false
                spec.oilLeakSeverity = 0
            end
            -- Deduct if not yet done (e.g., very fast repair)
            if not pending.costDeducted and pending.cost and pending.cost > 0 and pending.farmId then
                if g_currentMission:getMoney(pending.farmId) >= pending.cost then
                    g_currentMission:addMoney(-pending.cost, pending.farmId, MoneyType.VEHICLE_RUNNING_COSTS, true)
                end
            end
            UsedPlus.logInfo(string.format(
                "Hydraulic repair completed — hydraulic %.0f%%, engine %.0f%%",
                spec.hydraulicReliability * 100, spec.engineReliability * 100))
            -- Add entry to RVB's service manual
            if RVBserviceManual_Event and RVBserviceManual_Event.sendEvent then
                local entry = {
                    entryType = 3,  -- REPAIR.SERVICE_MANUAL
                    entryTime = env.currentDay,
                    operatingHours = rvb and rvb.totaloperatingHours or 0,
                    odometer = 0,
                    resultKey = "RVB_WorkshopMessage_repairDone",
                    errorList = {"UsedPlus Hydraulic System"},
                    cost = pending.cost or 0
                }
                RVBserviceManual_Event.sendEvent(self, entry)
                UsedPlus.logDebug("Added hydraulic repair to RVB service manual")
            end
            spec.pendingHydraulicRepair = nil
        end
    end

    -- ========== PER-FRAME CHECKS ==========
    local config = UsedPlusMaintenance.CONFIG

    if config.enableSpeedDegradation then
        UsedPlusMaintenance.enforceSpeedLimit(self, dt)
    end

    if config.enableSteeringDegradation then
        UsedPlusMaintenance.applySteeringDegradation(self, dt)
    end

    UsedPlusMaintenance.applyDirectSteeringPull(self, dt)

    if config.enableMisfiring then
        UsedPlusMaintenance.updateMisfireState(self, dt)
    end

    if config.enableTireWear then
        UsedPlusMaintenance.trackDistanceTraveled(self, dt)
    end

    if config.enableRunaway then
        UsedPlusMaintenance.updateRunawayState(self, dt)
    end

    -- ========== PERIODIC CHECKS (throttled to every 1 second) ==========
    spec.updateTimer = (spec.updateTimer or 0) + dt
    if spec.updateTimer < config.updateIntervalMs then
        return
    end
    spec.updateTimer = 0

    if config.enableSpeedDegradation then
        UsedPlusMaintenance.calculateSpeedLimit(self)
    end

    if config.enableFailures then
        UsedPlusMaintenance.checkEngineStall(self)
    end

    if config.enableHydraulicDrift then
        UsedPlusMaintenance.checkHydraulicDrift(self, dt)
    end

    if config.enableElectricalCutout then
        UsedPlusMaintenance.checkImplementCutout(self, dt)
    end

    if config.enableSteeringDegradation then
        UsedPlusMaintenance.updateSteeringPullSurge(self)
    end

    local malfunctionsEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Malfunctions")
    if config.enableHydraulicSurge and malfunctionsEnabled then
        UsedPlusMaintenance.checkHydraulicSurge(self)
    end

    if config.enableMisfiring then
        UsedPlusMaintenance.checkEngineMisfire(self)
    end

    if config.enableOverheating then
        UsedPlusMaintenance.updateEngineTemperature(self)
    end

    if malfunctionsEnabled then
        UsedPlusMaintenance.checkImplementMalfunctions(self)
    end

    local tireWearEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("TireWear")
    if config.enableTireWear and tireWearEnabled then
        UsedPlusMaintenance.applyTireWear(self)
        if malfunctionsEnabled then
            UsedPlusMaintenance.checkTireMalfunctions(self)
        end
    end

    -- v2.2.0: RVB fault monitoring
    if ModCompatibility and ModCompatibility.rvbInstalled and self.spec_faultData then
        if RVBWorkshopIntegration and RVBWorkshopIntegration.checkForNewFaults then
            RVBWorkshopIntegration:checkForNewFaults(self)
        end
    end

    if config.enableOilSystem then
        UsedPlusMaintenance.updateOilSystem(self, dt)
    end

    if config.enableHydraulicFluidSystem then
        UsedPlusMaintenance.updateHydraulicFluidSystem(self, dt)
    end

    if malfunctionsEnabled then
        UsedPlusMaintenance.checkForNewLeaks(self)
    end

    if malfunctionsEnabled then
        UsedPlusMaintenance.updateMalfunctionTimers(self)

        if config.enableRunaway then
            UsedPlusMaintenance.checkRunawayCondition(self)
        end

        if config.enableImplementStuckDown then
            UsedPlusMaintenance.checkImplementStuckDown(self)
        end
        if config.enableImplementStuckUp then
            UsedPlusMaintenance.checkImplementStuckUp(self)
        end

        if config.enableImplementPull then
            UsedPlusMaintenance.checkImplementPull(self)
        end
        if config.enableImplementDrag then
            UsedPlusMaintenance.checkImplementDrag(self)
        end
        if config.enableReducedTurning then
            UsedPlusMaintenance.checkReducedTurning(self)
        end
    end

    UsedPlusMaintenance.processFuelLeak(self, dt)

    -- v1.8.0: Sync data from external mods
    ModCompatibility.syncTireConditionFromUYT(self)
    ModCompatibility.syncReliabilityFromRVB(self)
end

--[[
    v1.5.1: Called when player enters vehicle
    Checks for first-start stall on poor reliability vehicles
]]
function UsedPlusMaintenance:onEnterVehicle(isControlling)
    if not isControlling then return end
    if not self.isServer then return end

    local spec = self.spec_usedPlusMaintenance
    if spec == nil then return end

    local engineReliability = ModCompatibility.getEngineReliability(self)

    if engineReliability >= 0.5 then
        return
    end

    if spec.stallRecoveryEndTime and spec.stallRecoveryEndTime > 0 then
        return
    end

    local stallChance = (0.5 - engineReliability) * 2.0
    stallChance = math.max(0, math.min(stallChance, 1.0))

    if math.random() < stallChance then
        spec.firstStartStallPending = true
        spec.firstStartStallTimer = 500

        UsedPlus.logDebug(string.format("First-start stall scheduled for %s (reliability: %d%%)",
            self:getName(), math.floor(engineReliability * 100)))
    end
end

--[[
    Admin panel helper: Reset ALL malfunction states
    Comprehensive cleanup for testing purposes
    @param vehicle - The vehicle to reset
]]
function UsedPlusMaintenance.resetAllMalfunctions(vehicle)
    if not vehicle or not vehicle.spec_usedPlusMaintenance then
        return
    end

    local spec = vehicle.spec_usedPlusMaintenance

    -- Reset reliability
    spec.engineReliability = 1.0
    spec.hydraulicReliability = 1.0
    spec.electricalReliability = 1.0

    -- Reset engine malfunctions
    spec.isStalled = false
    spec.stallRecoveryEndTime = 0
    spec.stallCooldown = 0
    spec.misfireActive = false
    spec.misfireEndTime = 0
    spec.misfireBurstRemaining = 0
    spec.engineTemperature = 0.0  -- Fully cool (pristine reset)
    spec.isOverheated = false
    spec.overheatCooldownEndTime = 0
    spec.runawayActive = false
    spec.runawayStartTime = 0
    spec.runawayPreviousSpeed = 0
    spec.runawayPreviousDamage = 0

    -- Reset hydraulic malfunctions
    spec.hydraulicSurgeActive = false
    spec.hydraulicSurgeEndTime = 0
    spec.hydraulicSurgeFadeStartTime = 0
    spec.hydraulicSurgeDirection = 0
    spec.hydraulicSurgeCooldownEnd = 0
    spec.implementStuckDown = false
    spec.implementStuckDownEndTime = 0
    spec.implementStuckUp = false
    spec.implementStuckUpEndTime = 0
    spec.implementPullActive = false
    spec.implementPullEndTime = 0
    spec.implementDragActive = false
    spec.implementDragEndTime = 0
    spec.reducedTurningActive = false
    spec.reducedTurningEndTime = 0

    -- Reset electrical malfunctions
    spec.isCutout = false
    spec.cutoutEndTime = 0

    -- Reset tire malfunctions
    spec.hasFlatTire = false
    spec.flatTireSide = 0

    -- Reset seizure states
    spec.engineSeized = false
    spec.hydraulicsSeized = false
    spec.electricalSeized = false
    spec.engineSeizedTime = 0
    spec.hydraulicsSeizedTime = 0
    spec.electricalSeizedTime = 0

    -- Reset cooldowns
    spec.lastMalfunctionTime = 0

    -- Reset ALL warning flags (allows warnings to show again on next trigger)
    spec.hasShownSpeedWarning = false
    spec.hasShownDriftWarning = false
    spec.hasShownPullWarning = false
    spec.hasShownSteeringWarning = false
    spec.hasShownMisfireWarning = false
    spec.hasShownOverheatWarning = false
    spec.hasShownOverheatCritical = false
    spec.hasShownSurgeWarning = false
    spec.hasShownDropWarning = false
    spec.hasShownPTOWarning = false
    spec.hasShownHitchWarning = false
    spec.hasShownFlatTireWarning = false
    spec.hasShownLowTractionWarning = false
    spec.hasShownTireWarnWarning = false
    spec.hasShownTireCriticalWarning = false
    spec.hasShownGovernorWarning = false

    -- Reset vehicle damage
    if vehicle.setDamage then
        vehicle:setDamage(0)
    end

    -- Reset wear
    if vehicle.setWearAmount then
        vehicle:setWearAmount(0)
    end

    -- NOTE: We do NOT reset failureCount, repairCount, or totalRepairCost
    -- Those are historical metrics that testers may want to preserve

    UsedPlus.logInfo("Admin panel: Reset all active malfunctions on " .. (vehicle:getName() or "vehicle"))
end

UsedPlus.logDebug("UsedPlusMaintenance loaded")
