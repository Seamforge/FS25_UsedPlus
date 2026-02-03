--[[
    FS25_UsedPlus - Restoration Data for Service Truck

    Contains symptom-to-diagnosis mappings for the restoration inspection minigame.
    Unlike OBD Scanner (instant field repairs), Service Truck restoration is a
    long-term process that can restore reliability AND reliability ceiling.

    The inspection minigame determines if restoration can BEGIN, not the boost amount.
    - Correct diagnosis: Restoration can start immediately
    - Wrong diagnosis: 48 game hour cooldown before retry

    v2.9.0 - Service Truck System
]]

RestorationData = {}

-- System types (same as DiagnosisData for compatibility)
RestorationData.SYSTEM_ENGINE = "engine"
RestorationData.SYSTEM_ELECTRICAL = "electrical"
RestorationData.SYSTEM_HYDRAULIC = "hydraulic"

-- Restoration outcomes
RestorationData.OUTCOME_SUCCESS = "success"      -- Correct diagnosis, can start restoration
RestorationData.OUTCOME_FAILED = "failed"        -- Wrong diagnosis, cooldown applied

-- Cooldown period after failed diagnosis (in game milliseconds)
-- 48 game hours = 48 * 60 * 1000 = 2,880,000 ms at 1x speed
RestorationData.FAILED_DIAGNOSIS_COOLDOWN = 48 * 60 * 1000

-- Restoration parameters
RestorationData.PARAMS = {
    -- Reliability restoration per game hour (1% = 0.01)
    reliabilityPerHour = 0.01,
    -- Ceiling restoration per game hour (0.25% = 0.0025)
    -- Ceiling restores 4x slower than reliability
    ceilingPerHour = 0.0025,
    -- Maximum reliability that can be achieved (100%)
    maxReliability = 1.0,
    -- Maximum ceiling that can be restored to (100%)
    maxCeiling = 1.0,
    -- Diesel consumption per game hour (liters)
    dieselPerHour = 5.0,
    -- Oil consumption per game hour (liters)
    oilPerHour = 0.5,
    -- Hydraulic fluid consumption per game hour (liters)
    hydraulicPerHour = 0.5,
    -- Spare parts consumption per game hour (units)
    partsPerHour = 2.0,
    -- Detection radius for target vehicles (meters)
    vehicleDetectionRadius = 15.0,
    -- Detection radius for spare parts pallets (meters)
    palletDetectionRadius = 5.0
}

--[[
    ENGINE RESTORATION SCENARIOS
    These are different from OBD Scanner scenarios - focused on deep mechanical issues
    that require workshop-level restoration, not field repairs.
]]
RestorationData.ENGINE_SCENARIOS = {
    {
        id = "engine_worn_bearings",
        symptoms = {
            "usedplus_resto_symptom_engine_knocking_load",
            "usedplus_resto_symptom_engine_low_oil_pressure",
            "usedplus_resto_symptom_engine_excessive_vibration"
        },
        correctDiagnosis = 2,
        diagnoses = {
            "usedplus_resto_diag_cylinder_wear",
            "usedplus_resto_diag_main_bearings",      -- CORRECT
            "usedplus_resto_diag_piston_rings",
            "usedplus_resto_diag_camshaft_wear"
        },
        restorationHours = 48,
        description = "usedplus_resto_desc_bearings"
    },
    {
        id = "engine_cylinder_wear",
        symptoms = {
            "usedplus_resto_symptom_engine_blue_smoke",
            "usedplus_resto_symptom_engine_oil_consumption",
            "usedplus_resto_symptom_engine_compression_loss"
        },
        correctDiagnosis = 1,
        diagnoses = {
            "usedplus_resto_diag_cylinder_wear",      -- CORRECT
            "usedplus_resto_diag_main_bearings",
            "usedplus_resto_diag_piston_rings",
            "usedplus_resto_diag_camshaft_wear"
        },
        restorationHours = 72,
        description = "usedplus_resto_desc_cylinder"
    },
    {
        id = "engine_piston_rings",
        symptoms = {
            "usedplus_resto_symptom_engine_blowby",
            "usedplus_resto_symptom_engine_power_loss",
            "usedplus_resto_symptom_engine_crankcase_pressure"
        },
        correctDiagnosis = 3,
        diagnoses = {
            "usedplus_resto_diag_cylinder_wear",
            "usedplus_resto_diag_main_bearings",
            "usedplus_resto_diag_piston_rings",       -- CORRECT
            "usedplus_resto_diag_camshaft_wear"
        },
        restorationHours = 60,
        description = "usedplus_resto_desc_rings"
    },
    {
        id = "engine_camshaft",
        symptoms = {
            "usedplus_resto_symptom_engine_ticking",
            "usedplus_resto_symptom_engine_rough_idle",
            "usedplus_resto_symptom_engine_valve_noise"
        },
        correctDiagnosis = 4,
        diagnoses = {
            "usedplus_resto_diag_cylinder_wear",
            "usedplus_resto_diag_main_bearings",
            "usedplus_resto_diag_piston_rings",
            "usedplus_resto_diag_camshaft_wear"       -- CORRECT
        },
        restorationHours = 36,
        description = "usedplus_resto_desc_camshaft"
    }
}

--[[
    ELECTRICAL RESTORATION SCENARIOS
    Deep electrical system issues requiring complete overhaul.
]]
RestorationData.ELECTRICAL_SCENARIOS = {
    {
        id = "electrical_harness",
        symptoms = {
            "usedplus_resto_symptom_elec_intermittent_systems",
            "usedplus_resto_symptom_elec_corrosion_visible",
            "usedplus_resto_symptom_elec_multiple_faults"
        },
        correctDiagnosis = 1,
        diagnoses = {
            "usedplus_resto_diag_harness_degradation", -- CORRECT
            "usedplus_resto_diag_ecu_failure",
            "usedplus_resto_diag_sensor_array",
            "usedplus_resto_diag_ground_points"
        },
        restorationHours = 24,
        description = "usedplus_resto_desc_harness"
    },
    {
        id = "electrical_ecu",
        symptoms = {
            "usedplus_resto_symptom_elec_erratic_behavior",
            "usedplus_resto_symptom_elec_no_communication",
            "usedplus_resto_symptom_elec_stored_codes"
        },
        correctDiagnosis = 2,
        diagnoses = {
            "usedplus_resto_diag_harness_degradation",
            "usedplus_resto_diag_ecu_failure",         -- CORRECT
            "usedplus_resto_diag_sensor_array",
            "usedplus_resto_diag_ground_points"
        },
        restorationHours = 18,
        description = "usedplus_resto_desc_ecu"
    },
    {
        id = "electrical_sensors",
        symptoms = {
            "usedplus_resto_symptom_elec_wrong_readings",
            "usedplus_resto_symptom_elec_limp_mode",
            "usedplus_resto_symptom_elec_poor_response"
        },
        correctDiagnosis = 3,
        diagnoses = {
            "usedplus_resto_diag_harness_degradation",
            "usedplus_resto_diag_ecu_failure",
            "usedplus_resto_diag_sensor_array",        -- CORRECT
            "usedplus_resto_diag_ground_points"
        },
        restorationHours = 30,
        description = "usedplus_resto_desc_sensors"
    },
    {
        id = "electrical_grounds",
        symptoms = {
            "usedplus_resto_symptom_elec_voltage_drops",
            "usedplus_resto_symptom_elec_dim_lights",
            "usedplus_resto_symptom_elec_starter_slow"
        },
        correctDiagnosis = 4,
        diagnoses = {
            "usedplus_resto_diag_harness_degradation",
            "usedplus_resto_diag_ecu_failure",
            "usedplus_resto_diag_sensor_array",
            "usedplus_resto_diag_ground_points"        -- CORRECT
        },
        restorationHours = 12,
        description = "usedplus_resto_desc_grounds"
    }
}

--[[
    HYDRAULIC RESTORATION SCENARIOS
    Complete hydraulic system overhaul for worn components.
]]
RestorationData.HYDRAULIC_SCENARIOS = {
    {
        id = "hydraulic_pump_worn",
        symptoms = {
            "usedplus_resto_symptom_hyd_slow_operation",
            "usedplus_resto_symptom_hyd_cavitation_noise",
            "usedplus_resto_symptom_hyd_low_pressure"
        },
        correctDiagnosis = 1,
        diagnoses = {
            "usedplus_resto_diag_pump_wear",           -- CORRECT
            "usedplus_resto_diag_valve_wear",
            "usedplus_resto_diag_cylinder_seals",
            "usedplus_resto_diag_hose_degradation"
        },
        restorationHours = 36,
        description = "usedplus_resto_desc_pump"
    },
    {
        id = "hydraulic_valves",
        symptoms = {
            "usedplus_resto_symptom_hyd_drift",
            "usedplus_resto_symptom_hyd_uneven_response",
            "usedplus_resto_symptom_hyd_internal_leak"
        },
        correctDiagnosis = 2,
        diagnoses = {
            "usedplus_resto_diag_pump_wear",
            "usedplus_resto_diag_valve_wear",          -- CORRECT
            "usedplus_resto_diag_cylinder_seals",
            "usedplus_resto_diag_hose_degradation"
        },
        restorationHours = 24,
        description = "usedplus_resto_desc_valves"
    },
    {
        id = "hydraulic_cylinders",
        symptoms = {
            "usedplus_resto_symptom_hyd_external_leak",
            "usedplus_resto_symptom_hyd_rod_scoring",
            "usedplus_resto_symptom_hyd_position_creep"
        },
        correctDiagnosis = 3,
        diagnoses = {
            "usedplus_resto_diag_pump_wear",
            "usedplus_resto_diag_valve_wear",
            "usedplus_resto_diag_cylinder_seals",      -- CORRECT
            "usedplus_resto_diag_hose_degradation"
        },
        restorationHours = 48,
        description = "usedplus_resto_desc_cylinders"
    },
    {
        id = "hydraulic_hoses",
        symptoms = {
            "usedplus_resto_symptom_hyd_visible_cracks",
            "usedplus_resto_symptom_hyd_bulging",
            "usedplus_resto_symptom_hyd_seepage"
        },
        correctDiagnosis = 4,
        diagnoses = {
            "usedplus_resto_diag_pump_wear",
            "usedplus_resto_diag_valve_wear",
            "usedplus_resto_diag_cylinder_seals",
            "usedplus_resto_diag_hose_degradation"     -- CORRECT
        },
        restorationHours = 18,
        description = "usedplus_resto_desc_hoses"
    }
}

--[[
    SCANNER HINTS
    Technical readouts displayed during inspection to help player deduce the issue.
    More detailed than OBD hints - these are workshop-level diagnostics.
]]
RestorationData.SYSTEM_HINTS = {
    [RestorationData.SYSTEM_ENGINE] = {
        "usedplus_resto_hint_engine_compression",
        "usedplus_resto_hint_engine_oil_analysis",
        "usedplus_resto_hint_engine_vibration",
        "usedplus_resto_hint_engine_blowby",
        "usedplus_resto_hint_engine_wear_metals"
    },
    [RestorationData.SYSTEM_ELECTRICAL] = {
        "usedplus_resto_hint_elec_resistance",
        "usedplus_resto_hint_elec_insulation",
        "usedplus_resto_hint_elec_continuity",
        "usedplus_resto_hint_elec_voltage_drop",
        "usedplus_resto_hint_elec_current_draw"
    },
    [RestorationData.SYSTEM_HYDRAULIC] = {
        "usedplus_resto_hint_hyd_pressure_test",
        "usedplus_resto_hint_hyd_flow_rate",
        "usedplus_resto_hint_hyd_fluid_analysis",
        "usedplus_resto_hint_hyd_temp_rise",
        "usedplus_resto_hint_hyd_case_drain"
    }
}

--[[
    Get a random scenario for a given system.
    @param systemType string - SYSTEM_ENGINE, SYSTEM_ELECTRICAL, or SYSTEM_HYDRAULIC
    @return table - The scenario data
]]
function RestorationData.getRandomScenario(systemType)
    local scenarios
    if systemType == RestorationData.SYSTEM_ENGINE then
        scenarios = RestorationData.ENGINE_SCENARIOS
    elseif systemType == RestorationData.SYSTEM_ELECTRICAL then
        scenarios = RestorationData.ELECTRICAL_SCENARIOS
    elseif systemType == RestorationData.SYSTEM_HYDRAULIC then
        scenarios = RestorationData.HYDRAULIC_SCENARIOS
    else
        return nil
    end

    local index = math.random(1, #scenarios)
    return scenarios[index]
end

--[[
    Get scenario based on reliability level.
    Lower reliability = more severe scenarios with longer restoration times.
    @param systemType string - The system type
    @param reliability number - Current reliability 0-1
    @return table - The scenario data
]]
function RestorationData.getScenarioForReliability(systemType, reliability)
    local scenarios
    if systemType == RestorationData.SYSTEM_ENGINE then
        scenarios = RestorationData.ENGINE_SCENARIOS
    elseif systemType == RestorationData.SYSTEM_ELECTRICAL then
        scenarios = RestorationData.ELECTRICAL_SCENARIOS
    elseif systemType == RestorationData.SYSTEM_HYDRAULIC then
        scenarios = RestorationData.HYDRAULIC_SCENARIOS
    else
        return nil
    end

    -- Sort scenarios by restoration hours (severity)
    local sorted = {}
    for i, s in ipairs(scenarios) do
        sorted[i] = s
    end
    table.sort(sorted, function(a, b) return a.restorationHours > b.restorationHours end)

    -- Lower reliability = higher chance of severe scenario
    local severityWeight = 1 - reliability  -- 0 = healthy, 1 = destroyed

    -- Weight towards more severe scenarios for lower reliability
    local weightedIndex = math.floor(severityWeight * (#sorted - 1)) + 1
    weightedIndex = math.min(weightedIndex, #sorted)

    -- Add some randomness
    local variation = math.random(-1, 1)
    weightedIndex = math.max(1, math.min(#sorted, weightedIndex + variation))

    return sorted[weightedIndex]
end

--[[
    Calculate inspection outcome.
    Unlike OBD, this only determines if restoration can BEGIN.
    @param scenario table - The scenario being used
    @param chosenDiagnosis number - The diagnosis index player chose (1-4)
    @return table - {outcome, canStartRestoration, cooldownEnd, message}
]]
function RestorationData.calculateInspectionOutcome(scenario, chosenDiagnosis)
    local isCorrect = (chosenDiagnosis == scenario.correctDiagnosis)

    if isCorrect then
        return {
            outcome = RestorationData.OUTCOME_SUCCESS,
            canStartRestoration = true,
            cooldownEnd = 0,
            messageKey = "usedplus_resto_inspection_success",
            estimatedHours = scenario.restorationHours
        }
    else
        -- Wrong diagnosis - apply 48 hour cooldown
        local cooldownEnd = g_currentMission.time + RestorationData.FAILED_DIAGNOSIS_COOLDOWN
        return {
            outcome = RestorationData.OUTCOME_FAILED,
            canStartRestoration = false,
            cooldownEnd = cooldownEnd,
            messageKey = "usedplus_resto_inspection_failed",
            estimatedHours = 0
        }
    end
end

--[[
    Get random hints for a system to display in inspection readout.
    @param systemType string - SYSTEM_ENGINE, SYSTEM_ELECTRICAL, or SYSTEM_HYDRAULIC
    @param count number - How many hints to return (default 2)
    @return table - Array of hint translation keys
]]
function RestorationData.getSystemHints(systemType, count)
    local count = count or 2
    local hints = RestorationData.SYSTEM_HINTS[systemType]

    if hints == nil then
        return {}
    end

    -- Create a shuffled copy
    local available = {}
    for i, hint in ipairs(hints) do
        available[i] = hint
    end

    -- Fisher-Yates shuffle
    for i = #available, 2, -1 do
        local j = math.random(1, i)
        available[i], available[j] = available[j], available[i]
    end

    -- Return first 'count' hints
    local result = {}
    for i = 1, math.min(count, #available) do
        result[i] = available[i]
    end

    return result
end

--[[
    Check if a component is on cooldown from a failed inspection.
    @param vehicle table - The vehicle to check
    @param systemType string - The system type
    @return boolean, number - Is on cooldown, time remaining in ms
]]
function RestorationData.isOnCooldown(vehicle, systemType)
    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then
        return false, 0
    end

    local cooldowns = maintSpec.restorationCooldowns or {}
    local cooldownEnd = cooldowns[systemType] or 0

    if g_currentMission.time < cooldownEnd then
        return true, cooldownEnd - g_currentMission.time
    end

    return false, 0
end

--[[
    Set cooldown for a component after failed inspection.
    @param vehicle table - The vehicle
    @param systemType string - The system type
    @param cooldownEnd number - Game time when cooldown ends
]]
function RestorationData.setCooldown(vehicle, systemType, cooldownEnd)
    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then
        return
    end

    if maintSpec.restorationCooldowns == nil then
        maintSpec.restorationCooldowns = {}
    end

    maintSpec.restorationCooldowns[systemType] = cooldownEnd
end

--[[
    Calculate estimated restoration time based on current vs target reliability.
    @param currentReliability number - Current reliability 0-1
    @param targetReliability number - Target reliability 0-1
    @return number - Estimated game hours to complete
]]
function RestorationData.estimateRestorationTime(currentReliability, targetReliability)
    local difference = targetReliability - currentReliability
    if difference <= 0 then
        return 0
    end

    -- At 1% per hour, time = difference * 100
    return math.ceil(difference / RestorationData.PARAMS.reliabilityPerHour)
end

--[[
    Calculate resources needed for restoration.
    @param hours number - Estimated restoration hours
    @return table - {diesel, oil, hydraulic, parts}
]]
function RestorationData.calculateResourcesNeeded(hours)
    return {
        diesel = hours * RestorationData.PARAMS.dieselPerHour,
        oil = hours * RestorationData.PARAMS.oilPerHour,
        hydraulic = hours * RestorationData.PARAMS.hydraulicPerHour,
        parts = hours * RestorationData.PARAMS.partsPerHour
    }
end

UsedPlus.logInfo("RestorationData loaded - Service Truck restoration system ready")
