--[[
    ModCompatibility.lua - Cross-Mod Integration Utility
    v2.6.2 - All integrations now have settings toggles for failsafe

    ============================================================================
    INTEGRATION LEVELS - What each mod integration actually does:
    ============================================================================

    INTEGRATED MODS (Enhanced cooperation - deep data sharing):
    ----------------------------------------------------------------------------

    1. REAL VEHICLE BREAKDOWNS (RVB) by MathiasHun
       Integration Level: DEEP
       Setting: enableRVBIntegration (default: true)

       What UsedPlus does WITH RVB:
       - Reads RVB part health (ENGINE, THERMOSTAT, GENERATOR, BATTERY, etc.)
       - Syncs UsedPlus reliability values FROM RVB part data
       - Defers catastrophic failures TO RVB (UsedPlus only does symptoms)
       - OBD Scanner shows RVB part status with fault indicators
       - Used vehicle listings pre-generate RVB part conditions
       - Vehicle DNA affects RVB part lifetimes (workhorses last longer)

       What UsedPlus does WITHOUT RVB:
       - Uses native UsedPlus reliability tracking
       - Handles its own symptom + failure triggers
       - OBD Scanner shows UsedPlus reliability percentages only

       Functions that check rvbInstalled:
       - getEngineReliability(), getElectricalReliability()
       - shouldDeferEngineFailure(), shouldDeferElectricalFailure()
       - getRVBPartLife(), isRVBPartFailed(), isRVBPartPrefault()
       - getOBDDiagnosticData(), initializeRVBPartsFromListing()
       - applyDNAToRVBLifetimes(), applyRVBRepairDegradation()

    2. USE YOUR TYRES (UYT) by 50keda
       Integration Level: DEEP
       Setting: enableUYTIntegration (default: true)

       What UsedPlus does WITH UYT:
       - Reads UYT tire wear per wheel
       - Syncs UsedPlus tire condition FROM UYT wear data
       - Defers flat tire events TO UYT/RVB
       - Syncs tire replacement TO UYT (resets wear tracking)
       - Quality tires get UYT life bonus, retreads start with wear
       - OBD Scanner shows UYT tire condition per wheel

       What UsedPlus does WITHOUT UYT:
       - Uses native UsedPlus tire tracking
       - Handles its own flat tire triggers
       - OBD Scanner shows UsedPlus tire data only

       Functions that check uytInstalled:
       - getUYTTireWear(), getUYTTireCondition(), getUYTMaxTireWear()
       - shouldDeferTireFailure(), hasUYTTires()
       - syncTireConditionFromUYT(), syncTireReplacementWithUYT()
       - applyInitialUYTWear(), getWorstUYTTireWear()

    COMPATIBLE MODS (Feature deferral - avoids conflicts):
    ----------------------------------------------------------------------------

    3. ADVANCEDMAINTENANCE (AM)
       Integration Level: CHAIN
       Setting: enableAMIntegration (default: true)

       What UsedPlus does WITH AM:
       - Chains to AM's engine damage check in canEngineRun()
       - If AM says engine can't run (damage too high), UsedPlus respects that
       - Both maintenance systems work together without conflicts

       What UsedPlus does WITHOUT AM:
       - Uses only UsedPlus reliability checks for engine operation

       Functions that check advancedMaintenanceInstalled:
       - getAdvancedMaintenanceChain() - returns AM's damage check function

       Used in:
       - UsedPlusMaintenance.lua:839 (canEngineRun chains to AM)

    4. HIREPURCHASING (HP)
       Integration Level: UI HIDE
       Setting: enableHPIntegration (default: true)

       What UsedPlus does WITH HP:
       - HIDES UsedPlus Finance button in shop (HP handles financing)
       - Displays HP lease data in Finance Manager for unified view
       - Can read HP lease terms and settlement costs
       - UsedPlus retains: marketplace, maintenance, leasing, used search

       What UsedPlus does WITHOUT HP:
       - Shows UsedPlus Finance button in shop
       - Full UsedPlus financing system active

       Functions that check hirePurchasingInstalled:
       - shouldShowFinanceButton() - returns false when HP installed
       - getHPLeases() - reads HP lease data for display

    5. BUYUSEDEQUIPMENT (BUE)
       Integration Level: UI HIDE
       Setting: enableBUEIntegration (default: true)

       What UsedPlus does WITH BUE:
       - HIDES UsedPlus Search button in shop (BUE handles used search)
       - Does NOT initialize UsedVehicleManager (avoids duplicate listings)
       - UsedPlus retains: financing, maintenance, agent sales

       What UsedPlus does WITHOUT BUE:
       - Shows UsedPlus Search button in shop
       - Full UsedPlus used vehicle marketplace active

       Functions that check buyUsedEquipmentInstalled:
       - shouldShowSearchButton() - returns false when BUE installed
       - shouldInitUsedVehicleManager() - returns false when BUE installed

    6. ENHANCEDLOANSYSTEM (ELS)
       Integration Level: FEATURE DISABLE
       Setting: enableELSIntegration (default: true)

       What UsedPlus does WITH ELS:
       - DISABLES UsedPlus loan creation (Take Loan button hidden)
       - Displays ELS loan data in Finance Manager for unified view
       - Can make payments on ELS loans through our UI
       - UsedPlus retains: marketplace, maintenance, leasing

       What UsedPlus does WITHOUT ELS:
       - Shows Take Loan button in Finance Manager
       - Full UsedPlus loan system active

       Functions that check enhancedLoanSystemInstalled:
       - shouldEnableLoanSystem() - returns false when ELS installed
       - shouldShowTakeLoanOption() - returns false when ELS installed
       - getELSLoans() - reads ELS loan data for display
       - payELSLoan() - makes payments on ELS loans

    ============================================================================
    SETTINGS FAILSAFE (v2.6.2)
    ============================================================================

    All integrations can be disabled via Settings > Game Settings > Mod Compatibility.
    Settings only appear if the corresponding mod is detected.

    Disabling an integration means:
    - ModCompatibility.xxxInstalled = false (even though mod is loaded)
    - UsedPlus behaves as if the mod isn't present
    - Useful if integration causes issues or player prefers standalone behavior

    ============================================================================
]]

ModCompatibility = {}

-- Detection flags (set during init)
-- Integrated mods (enhanced cooperation)
ModCompatibility.rvbInstalled = false
ModCompatibility.uytInstalled = false
ModCompatibility.uytGlobal = nil  -- Reference to actual UYT global (UseYourTyres or useYourTyres)

-- Formerly conflicting mods (now compatible)
ModCompatibility.advancedMaintenanceInstalled = false
ModCompatibility.hirePurchasingInstalled = false
ModCompatibility.buyUsedEquipmentInstalled = false
ModCompatibility.enhancedLoanSystemInstalled = false
ModCompatibility.betterContractsInstalled = false  -- v2.15.2: BC farmland discounts

-- v2.6.2: Raw detection flags (for UI display - shows toggle even when disabled)
ModCompatibility.rvbDetected = false
ModCompatibility.uytDetected = false
ModCompatibility.amDetected = false
ModCompatibility.hpDetected = false
ModCompatibility.bueDetected = false
ModCompatibility.elsDetected = false
ModCompatibility.bcDetected = false  -- v2.15.2: Better Contracts

ModCompatibility.initialized = false

-- RVB part key constants (must match RVB's definitions)
ModCompatibility.RVB_PARTS = {
    THERMOSTAT = "THERMOSTAT",
    LIGHTINGS = "LIGHTINGS",
    GLOWPLUG = "GLOWPLUG",
    WIPERS = "WIPERS",
    GENERATOR = "GENERATOR",
    ENGINE = "ENGINE",
    SELFSTARTER = "SELFSTARTER",
    BATTERY = "BATTERY",
    TIREFL = "TIREFL",
    TIREFR = "TIREFR",
    TIRERL = "TIRERL",
    TIRERR = "TIRERR",
}

--[[
    Initialize compatibility detection
    Called during mod load after other mods have registered
]]
function ModCompatibility.init()
    if ModCompatibility.initialized then return end

    -- ========================================================================
    -- INTEGRATED MODS (Enhanced cooperation)
    -- ========================================================================

    -- Detect Real Vehicle Breakdowns (check multiple possible globals)
    -- v2.7.2: Fixed detection - RVB uses g_rvbMenu, g_vehicleBreakdownsDirectory, etc.
    -- not just g_currentMission.vehicleBreakdowns
    local rvbDetected = false

    -- Method 1: Check g_currentMission.vehicleBreakdowns (original check)
    if g_currentMission ~= nil and g_currentMission.vehicleBreakdowns ~= nil then
        rvbDetected = true
        UsedPlus.logDebug("RVB detected via g_currentMission.vehicleBreakdowns")
    end

    -- Method 2: Check g_rvbMenu global (RVB settings menu instance)
    if not rvbDetected and g_rvbMenu ~= nil then
        rvbDetected = true
        UsedPlus.logDebug("RVB detected via g_rvbMenu")
    end

    -- Method 3: Check g_vehicleBreakdownsDirectory global
    if not rvbDetected and g_vehicleBreakdownsDirectory ~= nil then
        rvbDetected = true
        UsedPlus.logDebug("RVB detected via g_vehicleBreakdownsDirectory")
    end

    -- Method 4: Check g_rvbPlayer global
    if not rvbDetected and g_rvbPlayer ~= nil then
        rvbDetected = true
        UsedPlus.logDebug("RVB detected via g_rvbPlayer")
    end

    -- Method 5: Check specialization manager for "vehicleBreakdowns"
    if not rvbDetected and g_specializationManager ~= nil then
        local rvbSpec = g_specializationManager:getSpecializationByName("vehicleBreakdowns")
        if rvbSpec ~= nil then
            rvbDetected = true
            UsedPlus.logDebug("RVB detected via specialization manager")
        end
    end

    -- Detect Use Your Tyres (check multiple possible global names)
    -- Store reference to whichever global exists
    if UseYourTyres ~= nil then
        ModCompatibility.uytGlobal = UseYourTyres
    elseif useYourTyres ~= nil then
        ModCompatibility.uytGlobal = useYourTyres
    end
    local uytDetected = ModCompatibility.uytGlobal ~= nil or
        (g_specializationManager ~= nil and g_specializationManager:getSpecializationByName("useYourTyres") ~= nil)

    -- v2.6.2: Check integration settings (failsafe switches)
    -- If setting is OFF, treat as not installed even if mod is detected
    local rvbSettingEnabled = not UsedPlusSettings or UsedPlusSettings:get("enableRVBIntegration") ~= false
    local uytSettingEnabled = not UsedPlusSettings or UsedPlusSettings:get("enableUYTIntegration") ~= false

    -- Combine detection with setting
    ModCompatibility.rvbInstalled = rvbDetected and rvbSettingEnabled
    ModCompatibility.uytInstalled = uytDetected and uytSettingEnabled

    -- Store raw detection for UI display
    ModCompatibility.rvbDetected = rvbDetected
    ModCompatibility.uytDetected = uytDetected

    -- ========================================================================
    -- COMPATIBLE MODS (Feature deferral for coexistence)
    -- ========================================================================

    -- Detect AdvancedMaintenance - checks specialization registry
    local amDetected = ModCompatibility.checkAdvancedMaintenanceInstalled()

    -- Detect HirePurchasing - checks for HP-specific leaseDeals table
    -- Note: vanilla may have LeasingOptions but not leaseDeals
    local hpDetected = g_currentMission ~= nil and
                       g_currentMission.LeasingOptions ~= nil and
                       g_currentMission.LeasingOptions.leaseDeals ~= nil

    -- Detect BuyUsedEquipment - checks for global namespace
    local bueDetected = BuyUsedEquipment ~= nil

    -- Detect EnhancedLoanSystem - checks for loan manager
    -- v2.8.0: Enhanced detection - check multiple ELS globals
    local elsDetected = false

    -- Method 1: Check g_els_loanManager (main global created at file load)
    if g_els_loanManager ~= nil then
        elsDetected = true
        UsedPlus.logDebug("ELS detected via g_els_loanManager")
    end

    -- Method 2: Check ELS_loanManager class exists (created before instance)
    if not elsDetected and ELS_loanManager ~= nil then
        elsDetected = true
        UsedPlus.logDebug("ELS detected via ELS_loanManager class")
    end

    -- Method 3: Check ELS_loan class exists
    if not elsDetected and ELS_loan ~= nil then
        elsDetected = true
        UsedPlus.logDebug("ELS detected via ELS_loan class")
    end

    -- Detect Better Contracts via g_modIsLoaded (mod sandbox prevents direct global access)
    -- BC uses RoyalMod framework which creates BetterContracts in its sandboxed environment
    -- Data access uses getmetatable(_G).__index to reach across the sandbox boundary
    local bcDetected = false
    if g_modIsLoaded and g_modIsLoaded["FS25_BetterContracts"] then
        bcDetected = true
        UsedPlus.logWarn("BC: Better Contracts DETECTED via g_modIsLoaded")
    else
        UsedPlus.logWarn("BC: Better Contracts not found in g_modIsLoaded")
    end

    -- v2.6.2: Check integration settings for compatible mods
    local amSettingEnabled = not UsedPlusSettings or UsedPlusSettings:get("enableAMIntegration") ~= false
    local hpSettingEnabled = not UsedPlusSettings or UsedPlusSettings:get("enableHPIntegration") ~= false
    local bueSettingEnabled = not UsedPlusSettings or UsedPlusSettings:get("enableBUEIntegration") ~= false
    local elsSettingEnabled = not UsedPlusSettings or UsedPlusSettings:get("enableELSIntegration") ~= false
    local bcSettingEnabled = not UsedPlusSettings or UsedPlusSettings:get("enableBCIntegration") ~= false

    -- Combine detection with settings
    ModCompatibility.advancedMaintenanceInstalled = amDetected and amSettingEnabled
    ModCompatibility.hirePurchasingInstalled = hpDetected and hpSettingEnabled
    ModCompatibility.buyUsedEquipmentInstalled = bueDetected and bueSettingEnabled
    ModCompatibility.enhancedLoanSystemInstalled = elsDetected and elsSettingEnabled
    ModCompatibility.betterContractsInstalled = bcDetected and bcSettingEnabled

    -- Store raw detection for UI display
    ModCompatibility.amDetected = amDetected
    ModCompatibility.hpDetected = hpDetected
    ModCompatibility.bueDetected = bueDetected
    ModCompatibility.elsDetected = elsDetected
    ModCompatibility.bcDetected = bcDetected

    -- ========================================================================
    -- LOG DETECTION RESULTS
    -- ========================================================================

    UsedPlus.logInfo("=== ModCompatibility Detection Results ===")

    -- Integrated mods (full cooperation)
    if ModCompatibility.rvbDetected then
        if ModCompatibility.rvbInstalled then
            UsedPlus.logInfo("  [INTEGRATED] Real Vehicle Breakdowns DETECTED")
            UsedPlus.logInfo("    -> UsedPlus provides 'symptoms before failure'")
            UsedPlus.logInfo("    -> Final failure triggers deferred to RVB")
        else
            UsedPlus.logInfo("  [DISABLED] Real Vehicle Breakdowns detected but INTEGRATION DISABLED in settings")
        end
    end

    if ModCompatibility.uytDetected then
        if ModCompatibility.uytInstalled then
            UsedPlus.logInfo("  [INTEGRATED] Use Up Your Tyres DETECTED")
            UsedPlus.logInfo("    -> Tire condition synced from UYT wear data")
            UsedPlus.logInfo("    -> Flat tire triggers deferred to UYT/RVB")
        else
            UsedPlus.logInfo("  [DISABLED] Use Up Your Tyres detected but INTEGRATION DISABLED in settings")
        end
    end

    -- Compatible mods (feature deferral)
    if ModCompatibility.amDetected then
        if ModCompatibility.advancedMaintenanceInstalled then
            UsedPlus.logInfo("  [COMPATIBLE] AdvancedMaintenance DETECTED")
            UsedPlus.logInfo("    -> UsedPlus will chain to AM's engine damage checks")
            UsedPlus.logInfo("    -> Both maintenance systems work together")
        else
            UsedPlus.logInfo("  [DISABLED] AdvancedMaintenance detected but INTEGRATION DISABLED in settings")
        end
    end

    if ModCompatibility.hpDetected then
        if ModCompatibility.hirePurchasingInstalled then
            UsedPlus.logInfo("  [COMPATIBLE] HirePurchasing DETECTED")
            UsedPlus.logInfo("    -> UsedPlus Finance button HIDDEN (HP handles financing)")
            UsedPlus.logInfo("    -> UsedPlus retains: marketplace, maintenance, leasing")
        else
            UsedPlus.logInfo("  [DISABLED] HirePurchasing detected but INTEGRATION DISABLED in settings")
        end
    end

    if ModCompatibility.bueDetected then
        if ModCompatibility.buyUsedEquipmentInstalled then
            UsedPlus.logInfo("  [COMPATIBLE] BuyUsedEquipment DETECTED")
            UsedPlus.logInfo("    -> UsedPlus Search button HIDDEN (BUE handles used search)")
            UsedPlus.logInfo("    -> UsedPlus retains: financing, maintenance, agent sales")
        else
            UsedPlus.logInfo("  [DISABLED] BuyUsedEquipment detected but INTEGRATION DISABLED in settings")
        end
    end

    if ModCompatibility.elsDetected then
        if ModCompatibility.enhancedLoanSystemInstalled then
            UsedPlus.logInfo("  [COMPATIBLE] EnhancedLoanSystem DETECTED")
            UsedPlus.logInfo("    -> UsedPlus loan features DISABLED (ELS handles loans)")
            UsedPlus.logInfo("    -> UsedPlus retains: marketplace, maintenance, leasing")
        else
            UsedPlus.logInfo("  [DISABLED] EnhancedLoanSystem detected but INTEGRATION DISABLED in settings")
        end
    end

    if ModCompatibility.bcDetected then
        if ModCompatibility.betterContractsInstalled then
            UsedPlus.logInfo("  [COMPATIBLE] Better Contracts DETECTED")
            UsedPlus.logInfo("    -> Farmland discounts from completed contracts applied")
        else
            UsedPlus.logInfo("  [DISABLED] Better Contracts detected but INTEGRATION DISABLED in settings")
        end
    end

    -- Special combined modes
    if ModCompatibility.rvbInstalled and ModCompatibility.uytInstalled then
        UsedPlus.logInfo("  [FULL STACK] RVB + UYT + UsedPlus = Best experience!")
    end

    -- No external mods
    local anyDetected = ModCompatibility.rvbInstalled or ModCompatibility.uytInstalled or
                        ModCompatibility.advancedMaintenanceInstalled or
                        ModCompatibility.hirePurchasingInstalled or
                        ModCompatibility.buyUsedEquipmentInstalled or
                        ModCompatibility.enhancedLoanSystemInstalled or
                        ModCompatibility.betterContractsInstalled

    if not anyDetected then
        UsedPlus.logInfo("  No compatible mods detected - standalone mode")
    end

    UsedPlus.logInfo("==========================================")

    ModCompatibility.initialized = true
end

--[[
    Refresh integration settings (call when settings change)
    v2.6.2: Allows runtime toggling of all mod integrations
]]
function ModCompatibility.refreshIntegrationSettings()
    if not ModCompatibility.initialized then return end

    -- Get current settings
    local rvbSettingEnabled = not UsedPlusSettings or UsedPlusSettings:get("enableRVBIntegration") ~= false
    local uytSettingEnabled = not UsedPlusSettings or UsedPlusSettings:get("enableUYTIntegration") ~= false
    local amSettingEnabled = not UsedPlusSettings or UsedPlusSettings:get("enableAMIntegration") ~= false
    local hpSettingEnabled = not UsedPlusSettings or UsedPlusSettings:get("enableHPIntegration") ~= false
    local bueSettingEnabled = not UsedPlusSettings or UsedPlusSettings:get("enableBUEIntegration") ~= false
    local elsSettingEnabled = not UsedPlusSettings or UsedPlusSettings:get("enableELSIntegration") ~= false
    local bcSettingEnabled = not UsedPlusSettings or UsedPlusSettings:get("enableBCIntegration") ~= false

    -- Store old values
    local oldRVB = ModCompatibility.rvbInstalled
    local oldUYT = ModCompatibility.uytInstalled
    local oldAM = ModCompatibility.advancedMaintenanceInstalled
    local oldHP = ModCompatibility.hirePurchasingInstalled
    local oldBUE = ModCompatibility.buyUsedEquipmentInstalled
    local oldELS = ModCompatibility.enhancedLoanSystemInstalled
    local oldBC = ModCompatibility.betterContractsInstalled

    -- Update installed flags (detection AND setting)
    ModCompatibility.rvbInstalled = ModCompatibility.rvbDetected and rvbSettingEnabled
    ModCompatibility.uytInstalled = ModCompatibility.uytDetected and uytSettingEnabled
    ModCompatibility.advancedMaintenanceInstalled = ModCompatibility.amDetected and amSettingEnabled
    ModCompatibility.hirePurchasingInstalled = ModCompatibility.hpDetected and hpSettingEnabled
    ModCompatibility.buyUsedEquipmentInstalled = ModCompatibility.bueDetected and bueSettingEnabled
    ModCompatibility.enhancedLoanSystemInstalled = ModCompatibility.elsDetected and elsSettingEnabled
    ModCompatibility.betterContractsInstalled = ModCompatibility.bcDetected and bcSettingEnabled

    -- Log changes
    if oldRVB ~= ModCompatibility.rvbInstalled then
        UsedPlus.logInfo(ModCompatibility.rvbInstalled and "RVB Integration ENABLED" or "RVB Integration DISABLED")
    end
    if oldUYT ~= ModCompatibility.uytInstalled then
        UsedPlus.logInfo(ModCompatibility.uytInstalled and "UYT Integration ENABLED" or "UYT Integration DISABLED")
    end
    if oldAM ~= ModCompatibility.advancedMaintenanceInstalled then
        UsedPlus.logInfo(ModCompatibility.advancedMaintenanceInstalled and "AM Integration ENABLED" or "AM Integration DISABLED")
    end
    if oldHP ~= ModCompatibility.hirePurchasingInstalled then
        UsedPlus.logInfo(ModCompatibility.hirePurchasingInstalled and "HP Integration ENABLED" or "HP Integration DISABLED")
    end
    if oldBUE ~= ModCompatibility.buyUsedEquipmentInstalled then
        UsedPlus.logInfo(ModCompatibility.buyUsedEquipmentInstalled and "BUE Integration ENABLED" or "BUE Integration DISABLED")
    end
    if oldELS ~= ModCompatibility.enhancedLoanSystemInstalled then
        UsedPlus.logInfo(ModCompatibility.enhancedLoanSystemInstalled and "ELS Integration ENABLED" or "ELS Integration DISABLED")
    end
    if oldBC ~= ModCompatibility.betterContractsInstalled then
        UsedPlus.logInfo(ModCompatibility.betterContractsInstalled and "BC Integration ENABLED" or "BC Integration DISABLED")
    end
end

--[[
    Check if AdvancedMaintenance is installed
    Uses specialization registry lookup since AM uses custom specialization
]]
function ModCompatibility.checkAdvancedMaintenanceInstalled()
    -- AdvancedMaintenance adds a specialization to vehicles
    -- We check if the specialization exists in the registry
    if g_specializationManager then
        local amSpec = g_specializationManager:getSpecializationByName("advancedMaintenance")
        if amSpec then
            return true
        end
    end

    -- Also check for the global AdvancedMaintenance table
    if AdvancedMaintenance ~= nil then
        return true
    end

    return false
end

--============================================================================
-- RVB INTEGRATION FUNCTIONS
--============================================================================

--[[
    Get RVB part remaining life as a 0-1 percentage
    @param vehicle - The vehicle to check
    @param partKey - RVB part key (e.g., "ENGINE", "BATTERY")
    @return number - 0.0 (exhausted) to 1.0 (new)
]]
function ModCompatibility.getRVBPartLife(vehicle, partKey)
    if not ModCompatibility.rvbInstalled then return 1.0 end
    if vehicle == nil then return 1.0 end

    local rvb = vehicle.spec_faultData
    if not rvb or not rvb.parts or not rvb.parts[partKey] then
        return 1.0  -- Default to healthy if no data
    end

    local part = rvb.parts[partKey]
    if not part.tmp_lifetime or part.tmp_lifetime <= 0 then
        return 1.0
    end

    -- operatingHours / lifetime = used percentage
    -- 1 - usedPercent = remaining life
    local usedPercent = (part.operatingHours or 0) / part.tmp_lifetime
    return math.max(0, math.min(1, 1 - usedPercent))
end

--[[
    Check if an RVB part is in fault state
    @param vehicle - The vehicle to check
    @param partKey - RVB part key
    @return boolean - true if part has failed

    v2.7.2: Enhanced detection - checks multiple fault indicators:
    - part.fault (string: nil/"empty" = no fault, other string = fault)
    - part.damaged (boolean: true = damaged)
    - part.isFailed (boolean: some RVB versions use this)
]]
function ModCompatibility.isRVBPartFailed(vehicle, partKey)
    if not ModCompatibility.rvbInstalled then return false end
    if vehicle == nil then return false end

    local rvb = vehicle.spec_faultData
    if not rvb or not rvb.parts or not rvb.parts[partKey] then
        return false
    end

    local part = rvb.parts[partKey]

    -- Check string fault state (RVB uses "empty" or nil for no fault)
    if part.fault ~= nil and part.fault ~= "empty" and part.fault ~= "" then
        return true
    end

    -- Check boolean damaged state
    if part.damaged == true then
        return true
    end

    -- Check alternative isFailed boolean (some RVB versions)
    if part.isFailed == true then
        return true
    end

    return false
end

--[[
    Check if an RVB part is in prefault state (warning state before failure)
    @param vehicle - The vehicle to check
    @param partKey - RVB part key
    @return boolean - true if part is in prefault

    v2.7.2: Enhanced detection - checks multiple prefault indicators:
    - part.prefault (string: nil/"empty" = no prefault, other string = warning)
    - part.isWarning (boolean: some RVB versions use this)
]]
function ModCompatibility.isRVBPartPrefault(vehicle, partKey)
    if not ModCompatibility.rvbInstalled then return false end
    if vehicle == nil then return false end

    local rvb = vehicle.spec_faultData
    if not rvb or not rvb.parts or not rvb.parts[partKey] then
        return false
    end

    local part = rvb.parts[partKey]

    -- Check string prefault state (RVB uses "empty" or nil for no warning)
    if part.prefault ~= nil and part.prefault ~= "empty" and part.prefault ~= "" then
        return true
    end

    -- Check alternative isWarning boolean (some RVB versions)
    if part.isWarning == true then
        return true
    end

    return false
end

--[[
    Get engine reliability - uses RVB if available, otherwise native UsedPlus
    Combines ENGINE + THERMOSTAT health from RVB

    @param vehicle - The vehicle to check
    @return number - 0.0 (dead) to 1.0 (perfect)
]]
function ModCompatibility.getEngineReliability(vehicle)
    if ModCompatibility.rvbInstalled and vehicle.spec_faultData then
        -- Derive from RVB parts
        local engineLife = ModCompatibility.getRVBPartLife(vehicle, ModCompatibility.RVB_PARTS.ENGINE)
        local thermoLife = ModCompatibility.getRVBPartLife(vehicle, ModCompatibility.RVB_PARTS.THERMOSTAT)
        return (engineLife + thermoLife) / 2
    end

    -- Fall back to native UsedPlus reliability
    local spec = vehicle.spec_usedPlusMaintenance
    if spec then
        return spec.engineReliability or 1.0
    end

    return 1.0
end

--[[
    Get electrical reliability - uses RVB if available, otherwise native UsedPlus
    Combines GENERATOR + BATTERY + SELFSTARTER + GLOWPLUG health from RVB

    @param vehicle - The vehicle to check
    @return number - 0.0 (dead) to 1.0 (perfect)
]]
function ModCompatibility.getElectricalReliability(vehicle)
    if ModCompatibility.rvbInstalled and vehicle.spec_faultData then
        -- Derive from RVB parts
        local genLife = ModCompatibility.getRVBPartLife(vehicle, ModCompatibility.RVB_PARTS.GENERATOR)
        local batLife = ModCompatibility.getRVBPartLife(vehicle, ModCompatibility.RVB_PARTS.BATTERY)
        local startLife = ModCompatibility.getRVBPartLife(vehicle, ModCompatibility.RVB_PARTS.SELFSTARTER)
        local glowLife = ModCompatibility.getRVBPartLife(vehicle, ModCompatibility.RVB_PARTS.GLOWPLUG)
        return (genLife + batLife + startLife + glowLife) / 4
    end

    -- Fall back to native UsedPlus reliability
    local spec = vehicle.spec_usedPlusMaintenance
    if spec then
        return spec.electricalReliability or 1.0
    end

    return 1.0
end

--[[
    Get hydraulic reliability - ALWAYS uses native UsedPlus
    RVB doesn't track hydraulic systems, this is unique to UsedPlus!

    @param vehicle - The vehicle to check
    @return number - 0.0 (dead) to 1.0 (perfect)
]]
function ModCompatibility.getHydraulicReliability(vehicle)
    -- Always native - RVB doesn't have hydraulics
    local spec = vehicle.spec_usedPlusMaintenance
    if spec then
        return spec.hydraulicReliability or 1.0
    end

    return 1.0
end

--[[
    Get combined overall reliability for resale value calculations
    Uses weighted average of all systems

    @param vehicle - The vehicle to check
    @return number - 0.0 to 1.0
]]
function ModCompatibility.getOverallReliability(vehicle)
    local engine = ModCompatibility.getEngineReliability(vehicle)
    local electrical = ModCompatibility.getElectricalReliability(vehicle)
    local hydraulic = ModCompatibility.getHydraulicReliability(vehicle)

    -- Weighted: engine most important, then hydraulic, then electrical
    return (engine * 0.4) + (hydraulic * 0.35) + (electrical * 0.25)
end

--[[
    Check if engine failure triggers should be deferred to RVB
    @return boolean - true if RVB should handle engine failures
]]
function ModCompatibility.shouldDeferEngineFailure()
    return ModCompatibility.rvbInstalled
end

--[[
    Check if electrical failure triggers should be deferred to RVB
    @return boolean - true if RVB should handle electrical failures
]]
function ModCompatibility.shouldDeferElectricalFailure()
    return ModCompatibility.rvbInstalled
end

--[[
    Check if flat tire triggers should be deferred to RVB/UYT
    @return boolean - true if other mods should handle tire failures
]]
function ModCompatibility.shouldDeferTireFailure()
    return ModCompatibility.rvbInstalled or ModCompatibility.uytInstalled
end

--============================================================================
-- UYT INTEGRATION FUNCTIONS
--============================================================================

--[[
    Get tire wear from UYT for a specific wheel
    @param vehicle - The vehicle to check
    @param wheelIndex - 1-based wheel index
    @return number - 0.0 (new) to 1.0 (worn out)
]]
function ModCompatibility.getUYTTireWear(vehicle, wheelIndex)
    if not ModCompatibility.uytInstalled then return 0 end
    local uyt = ModCompatibility.uytGlobal
    if not uyt then return 0 end
    if vehicle == nil or not vehicle.spec_wheels then return 0 end

    local wheel = vehicle.spec_wheels.wheels[wheelIndex]
    if wheel and uyt.getWearAmount then
        return uyt.getWearAmount(wheel) or 0
    end

    return 0
end

--[[
    Get tire condition from UYT (inverted from wear)
    @param vehicle - The vehicle to check
    @param wheelIndex - 1-based wheel index
    @return number - 0.0 (worn out) to 1.0 (new)
]]
function ModCompatibility.getUYTTireCondition(vehicle, wheelIndex)
    local wear = ModCompatibility.getUYTTireWear(vehicle, wheelIndex)
    return 1.0 - wear
end

--[[
    Get maximum tire wear across all wheels
    @param vehicle - The vehicle to check
    @return number - 0.0 to 1.0 (worst tire)
]]
function ModCompatibility.getUYTMaxTireWear(vehicle)
    if not ModCompatibility.uytInstalled then return 0 end
    if vehicle == nil or not vehicle.spec_wheels then return 0 end

    local maxWear = 0
    for i, _ in ipairs(vehicle.spec_wheels.wheels) do
        local wear = ModCompatibility.getUYTTireWear(vehicle, i)
        maxWear = math.max(maxWear, wear)
    end

    return maxWear
end

--[[
    Get UYT tire replacement cost for vehicle
    @param vehicle - The vehicle to check
    @return number - Cost in dollars, or 0 if UYT not installed
]]
function ModCompatibility.getUYTReplacementCost(vehicle)
    if not ModCompatibility.uytInstalled then return 0 end
    local uyt = ModCompatibility.uytGlobal
    if not uyt or not uyt.getTyresPrice then return 0 end

    return uyt.getTyresPrice(vehicle) or 0
end

--[[
    Check if vehicle has UYT-compatible tires
    @param vehicle - The vehicle to check
    @return boolean
]]
function ModCompatibility.hasUYTTires(vehicle)
    if not ModCompatibility.uytInstalled then return false end
    return vehicle.uytHasTyres == true
end

--[[
    v2.8.0: Get unified tire condition with UYT → Native fallback
    This ensures ALL vehicles have tire wear displayed, regardless of UYT support status.

    Priority:
    1. UYT per-wheel data (if UYT is tracking this vehicle)
    2. UsedPlus native per-wheel tracking (ALWAYS available)

    Returns: {
        condition = 0-1 (worst tire, for display),
        source = "UYT" | "Native",
        perWheel = { [1]=cond, [2]=cond, ... } or nil
    }

    @param vehicle - The vehicle to check
    @return table - Unified tire condition data
]]
function ModCompatibility.getUnifiedTireCondition(vehicle)
    local result = { condition = 1.0, source = "Native", perWheel = nil }

    if vehicle == nil then return result end

    -- Priority 1: UYT per-wheel data (if UYT is installed AND tracking this vehicle)
    -- Key insight: UYT sets uytHasTyres=false for "unsupported" vehicles
    -- and then stops tracking distance. We detect this by checking uytTravelledDist
    if ModCompatibility.uytInstalled and vehicle.uytHasTyres == true then
        local uyt = ModCompatibility.uytGlobal
        if uyt and uyt.getWearAmount and vehicle.spec_wheels and vehicle.spec_wheels.wheels then
            local worstWear = 0
            local perWheel = {}
            local hasData = false

            for i, wheel in ipairs(vehicle.spec_wheels.wheels) do
                -- UYT only tracks if vehicle is "supported" and has traveled
                if wheel.uytTravelledDist and wheel.uytTravelledDist > 0 then
                    local wear = uyt.getWearAmount(wheel) or 0
                    worstWear = math.max(worstWear, wear)
                    perWheel[i] = 1.0 - wear  -- Convert WEAR to CONDITION
                    hasData = true
                end
            end

            if hasData then
                result.condition = 1.0 - worstWear  -- Convert WEAR to CONDITION
                result.source = "UYT"
                result.perWheel = perWheel
                return result
            end
        end
    end

    -- Priority 2: UsedPlus native per-wheel tracking (ALWAYS available)
    -- This is the "no free passes" fallback - every vehicle gets tracked
    local spec = vehicle.spec_usedPlusMaintenance
    if spec then
        if spec.wheelConditions and #spec.wheelConditions > 0 then
            -- Use per-wheel data
            result.perWheel = {}
            local worst = 1.0
            for i, cond in ipairs(spec.wheelConditions) do
                result.perWheel[i] = cond
                worst = math.min(worst, cond)
            end
            result.condition = worst
        elseif spec.tireCondition then
            -- Fallback to aggregate value
            result.condition = spec.tireCondition
        end
        result.source = "Native"
    end

    return result
end

--============================================================================
-- SYNC FUNCTIONS - Update UsedPlus data from external sources
--============================================================================

--[[
    Sync UsedPlus tire condition from UYT wear data
    Called periodically to keep our tire condition in sync with UYT

    @param vehicle - The vehicle to sync
]]
function ModCompatibility.syncTireConditionFromUYT(vehicle)
    if not ModCompatibility.uytInstalled then return end
    if not ModCompatibility.hasUYTTires(vehicle) then return end

    local spec = vehicle.spec_usedPlusMaintenance
    if not spec or not spec.tires then return end

    local wheelCount = 0
    if vehicle.spec_wheels and vehicle.spec_wheels.wheels then
        wheelCount = #vehicle.spec_wheels.wheels
    end

    -- Sync each tire's condition from UYT wear
    for i = 1, math.min(wheelCount, #spec.tires) do
        local uytCondition = ModCompatibility.getUYTTireCondition(vehicle, i)
        -- Only update if UYT has valid data
        if uytCondition < 1.0 or spec.tires[i].condition > uytCondition then
            spec.tires[i].condition = uytCondition
        end
    end
end

--[[
    Sync UsedPlus reliability from RVB part health
    Called periodically to update our reliability values

    @param vehicle - The vehicle to sync
]]
function ModCompatibility.syncReliabilityFromRVB(vehicle)
    if not ModCompatibility.rvbInstalled then return end

    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return end

    -- Update engine reliability from RVB
    spec.engineReliability = ModCompatibility.getEngineReliability(vehicle)

    -- Update electrical reliability from RVB
    spec.electricalReliability = ModCompatibility.getElectricalReliability(vehicle)

    -- Note: hydraulicReliability stays native - RVB doesn't track it
end

--[[
    v2.3.0: Sync tire replacement to UYT
    When UsedPlus replaces tires, reset UYT's tire wear tracking
    Retreads start with pre-existing wear (they're reconditioned casings)

    @param vehicle - The vehicle that had tires replaced
    @param tireQuality - 1=Retread, 2=Normal, 3=Quality (optional, defaults to 2)
    @return boolean - true if sync successful
]]
function ModCompatibility.syncTireReplacementWithUYT(vehicle, tireQuality)
    if not ModCompatibility.uytInstalled then return false end
    if not UseYourTyres then return false end
    if not vehicle then return false end

    local tireQuality = tireQuality or 2  -- Default to Normal

    -- Check if vehicle has UYT-compatible tires
    if not vehicle.uytHasTyres then
        UsedPlus.logDebug("syncTireReplacementWithUYT: Vehicle has no UYT tires")
        return false
    end

    -- Get UYT replacement price and trigger their reset event
    local uyt = ModCompatibility.uytGlobal
    local price = uyt and uyt.getTyresPrice and uyt.getTyresPrice(vehicle, false) or 0

    -- Try to send UYT's replacement event first (this resets to 0)
    local resetSuccessful = false
    if UytReplaceEvent and UytReplaceEvent.new then
        -- UYT's event resets all wheel distances
        local event = UytReplaceEvent.new(vehicle, price)
        if event and event.sendToServer then
            event:sendToServer()
            resetSuccessful = true
            UsedPlus.logInfo(string.format("Synced tire replacement to UYT for %s", vehicle:getName()))
        end
    end

    -- Fallback: Directly reset wheel distances (server-side only)
    if not resetSuccessful and vehicle.isServer and vehicle.spec_wheels and vehicle.spec_wheels.wheels then
        for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
            if wheel.uytTravelledDist ~= nil then
                wheel.uytTravelledDist = 0
            end
        end
        resetSuccessful = true
        UsedPlus.logInfo(string.format("Direct reset of UYT tire distances for %s", vehicle:getName()))
    end

    -- v2.3.0: Apply initial wear for retreads (reconditioned casings start with wear)
    if resetSuccessful and tireQuality == 1 and vehicle.isServer then
        local initialWear = UsedPlusMaintenance.CONFIG.tireRetreadInitialWear or 0.35
        ModCompatibility.applyInitialUYTWear(vehicle, initialWear)
    end

    -- v2.3.0: Apply life bonus for Quality tires (premium tires have extended life)
    -- This sets negative wear (distance offset) giving them extra life beyond 100%
    if resetSuccessful and tireQuality == 3 and vehicle.isServer then
        local lifeBonus = UsedPlusMaintenance.CONFIG.tireQualityLifeBonus or 0.15
        ModCompatibility.applyInitialUYTWear(vehicle, -lifeBonus)
    end

    return resetSuccessful
end

--[[
    v2.3.0: Apply initial wear to UYT tires
    Used for retreads (positive wear) and Quality tires (negative wear = bonus life)

    @param vehicle - The vehicle
    @param wearAmount - Wear to apply: positive for retreads, negative for Quality bonus
                        e.g., 0.35 = 35% pre-worn, -0.15 = 15% bonus life
]]
function ModCompatibility.applyInitialUYTWear(vehicle, wearAmount)
    if not ModCompatibility.uytInstalled then return end
    if not vehicle or not vehicle.spec_wheels then return end
    if wearAmount == 0 then return end

    -- Calculate distance to add/subtract based on UYT's wear formula
    -- UYT wear = (distance / perimeter) / maxRevolutions
    -- So distance = wear * perimeter * maxRevolutions
    -- Base maxRevolutions for 2m tire = 240000m / (2 * pi) ≈ 38197 revolutions
    -- We'll estimate based on typical tire size

    for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
        if wheel.uytTravelledDist ~= nil then
            -- Get wheel perimeter (radius * 2 * pi)
            local radius = wheel.radius or 0.5
            local perimeter = radius * 2 * math.pi

            -- UYT base distance for full wear is ~240000m for 2m diameter tire
            -- Scale by actual diameter
            local diameter = radius * 2
            local baseDistance = 240000 * (diameter / 2.0)

            -- Calculate distance for desired wear (can be negative for bonus life)
            local distanceToSet = wearAmount * baseDistance

            -- Clamp to valid range (can't have negative distance traveled)
            -- But negative wearAmount creates negative distance = bonus life
            wheel.uytTravelledDist = math.max(-baseDistance * 0.20, distanceToSet)  -- Cap bonus at 20%

            UsedPlus.logDebug(string.format("Applied %.0f%% initial UYT wear to wheel (dist=%.0fm)",
                wearAmount * 100, wheel.uytTravelledDist))
        end
    end

    local description = wearAmount > 0 and "retreads" or "Quality bonus"
    UsedPlus.logInfo(string.format("Applied %.0f%% initial wear to UYT tires for %s (%s)",
        wearAmount * 100, vehicle:getName(), description))
end

--[[
    v2.3.0: Get worst tire wear from UYT for flat tire probability
    Returns the highest wear value across all wheels

    @param vehicle - The vehicle to check
    @return number - 0.0 (all new) to 1.0 (worst tire fully worn)
]]
function ModCompatibility.getWorstUYTTireWear(vehicle)
    if not ModCompatibility.uytInstalled then return 0 end
    if not vehicle or not vehicle.spec_wheels then return 0 end

    local worstWear = 0
    for i, wheel in ipairs(vehicle.spec_wheels.wheels) do
        local wear = ModCompatibility.getUYTTireWear(vehicle, i)
        worstWear = math.max(worstWear, wear)
    end

    return worstWear
end

--============================================================================
-- OBD FIELD SERVICE KIT INTEGRATION
--============================================================================

--[[
    Get diagnostic data for OBD Field Service Kit
    Returns combined data from RVB (if available) and UsedPlus

    @param vehicle - The vehicle to diagnose
    @return table - Diagnostic data for display
]]
function ModCompatibility.getOBDDiagnosticData(vehicle)
    local data = {
        hasRVBData = ModCompatibility.rvbInstalled and vehicle.spec_faultData ~= nil,
        hasUYTData = ModCompatibility.uytInstalled and ModCompatibility.hasUYTTires(vehicle),

        -- Engine system
        engine = {
            reliability = ModCompatibility.getEngineReliability(vehicle),
            source = ModCompatibility.rvbInstalled and "RVB" or "UsedPlus",
            rvbParts = {},
        },

        -- Electrical system
        electrical = {
            reliability = ModCompatibility.getElectricalReliability(vehicle),
            source = ModCompatibility.rvbInstalled and "RVB" or "UsedPlus",
            rvbParts = {},
        },

        -- Hydraulic system (always UsedPlus)
        hydraulic = {
            reliability = ModCompatibility.getHydraulicReliability(vehicle),
            source = "UsedPlus",
        },

        -- Tire data
        tires = {},
    }

    -- Add RVB part details if available
    if data.hasRVBData then
        -- Engine parts
        data.engine.rvbParts = {
            { name = "Engine", life = ModCompatibility.getRVBPartLife(vehicle, "ENGINE"),
              prefault = ModCompatibility.isRVBPartPrefault(vehicle, "ENGINE"),
              fault = ModCompatibility.isRVBPartFailed(vehicle, "ENGINE") },
            { name = "Thermostat", life = ModCompatibility.getRVBPartLife(vehicle, "THERMOSTAT"),
              prefault = ModCompatibility.isRVBPartPrefault(vehicle, "THERMOSTAT"),
              fault = ModCompatibility.isRVBPartFailed(vehicle, "THERMOSTAT") },
        }

        -- Electrical parts
        data.electrical.rvbParts = {
            { name = "Generator", life = ModCompatibility.getRVBPartLife(vehicle, "GENERATOR"),
              prefault = ModCompatibility.isRVBPartPrefault(vehicle, "GENERATOR"),
              fault = ModCompatibility.isRVBPartFailed(vehicle, "GENERATOR") },
            { name = "Battery", life = ModCompatibility.getRVBPartLife(vehicle, "BATTERY"),
              prefault = ModCompatibility.isRVBPartPrefault(vehicle, "BATTERY"),
              fault = ModCompatibility.isRVBPartFailed(vehicle, "BATTERY") },
            { name = "Starter", life = ModCompatibility.getRVBPartLife(vehicle, "SELFSTARTER"),
              prefault = ModCompatibility.isRVBPartPrefault(vehicle, "SELFSTARTER"),
              fault = ModCompatibility.isRVBPartFailed(vehicle, "SELFSTARTER") },
            { name = "Glow Plug", life = ModCompatibility.getRVBPartLife(vehicle, "GLOWPLUG"),
              prefault = ModCompatibility.isRVBPartPrefault(vehicle, "GLOWPLUG"),
              fault = ModCompatibility.isRVBPartFailed(vehicle, "GLOWPLUG") },
        }
    end

    -- Add tire data
    if data.hasUYTData then
        local wheelCount = vehicle.spec_wheels and #vehicle.spec_wheels.wheels or 0
        for i = 1, wheelCount do
            table.insert(data.tires, {
                index = i,
                wear = ModCompatibility.getUYTTireWear(vehicle, i),
                condition = ModCompatibility.getUYTTireCondition(vehicle, i),
                source = "UYT",
            })
        end
    else
        -- Use UsedPlus native tire data
        local spec = vehicle.spec_usedPlusMaintenance
        if spec and spec.tires then
            for i, tire in ipairs(spec.tires) do
                table.insert(data.tires, {
                    index = i,
                    wear = 1 - (tire.condition or 1),
                    condition = tire.condition or 1,
                    tier = tire.tier or "Economy",
                    source = "UsedPlus",
                })
            end
        end
    end

    return data
end

--[[
    Apply OBD repair to RVB parts
    Called when Field Service Kit successfully diagnoses and repairs

    @param vehicle - The vehicle to repair
    @param system - "engine" or "electrical"
    @param hoursReduction - How many operating hours to reduce
    @param clearFaults - Whether to clear fault states
]]
function ModCompatibility.applyOBDRepairToRVB(vehicle, system, hoursReduction, clearFaults)
    if not ModCompatibility.rvbInstalled then return end

    local rvb = vehicle.spec_faultData
    if not rvb or not rvb.parts then return end

    local partsToFix = {}
    if system == "engine" then
        partsToFix = { "ENGINE", "THERMOSTAT" }
    elseif system == "electrical" then
        partsToFix = { "GENERATOR", "BATTERY", "SELFSTARTER", "GLOWPLUG" }
    end

    for _, partKey in ipairs(partsToFix) do
        local part = rvb.parts[partKey]
        if part then
            -- Reduce operating hours (making the part "younger")
            part.operatingHours = math.max(0, (part.operatingHours or 0) - hoursReduction)

            -- Clear fault states if requested (perfect diagnosis)
            if clearFaults then
                part.prefault = "empty"
                part.fault = "empty"
                part.damaged = false
            end

            UsedPlus.logDebug(string.format(
                "OBD repair applied to RVB %s: hours reduced by %d, faults cleared: %s",
                partKey, hoursReduction, tostring(clearFaults)))
        end
    end
end

--============================================================================
-- BETTER CONTRACTS INTEGRATION
--============================================================================

--[[
    Read Better Contracts config from savegame XML file
    Bypasses mod sandbox entirely - reads directly from BC's saved config

    BC saves to: {savegameDir}/FS25_BetterContracts.xml
    XML format:
      <BetterContracts discount="true">
        <discount perJob="0.05" maxJobs="5" />
      </BetterContracts>

    @return table {discountMode, discPerJob, discMaxJobs} or nil
]]
function ModCompatibility.readBCConfig()
    -- Get savegame directory
    local savegameDir = nil
    if g_currentMission and g_currentMission.missionInfo then
        savegameDir = g_currentMission.missionInfo.savegameDirectory
    end
    if savegameDir == nil then
        UsedPlus.logWarn("BC config: Cannot determine savegame directory")
        return nil
    end

    local xmlPath = savegameDir .. "/FS25_BetterContracts.xml"

    -- Load BC config XML (old-style API for maximum compatibility)
    local xmlId = loadXMLFile("BCConfig", xmlPath)
    if xmlId == nil or xmlId == 0 then
        UsedPlus.logWarn("BC config: No config file at " .. xmlPath .. " (BC using defaults, discountMode=false)")
        return { discountMode = false, discPerJob = 0.05, discMaxJobs = 5 }
    end

    local config = {}
    config.discountMode = Utils.getNoNil(getXMLBool(xmlId, "BetterContracts#discount"), false)
    if config.discountMode then
        config.discPerJob = Utils.getNoNil(getXMLFloat(xmlId, "BetterContracts.discount#perJob"), 0.05)
        config.discMaxJobs = Utils.getNoNil(getXMLInt(xmlId, "BetterContracts.discount#maxJobs"), 5)
    else
        config.discPerJob = 0.05
        config.discMaxJobs = 5
    end

    delete(xmlId)

    UsedPlus.logWarn(string.format("BC config loaded: discountMode=%s, perJob=%.2f, maxJobs=%d",
        tostring(config.discountMode), config.discPerJob, config.discMaxJobs))

    return config
end

--[[
    Get farmland discount from Better Contracts based on completed NPC jobs
    Reads BC config from savegame XML (bypasses mod sandbox)
    Reads job counts from farm.stats.npcJobs (shared game object, populated by BC)

    BC stores job counts on farm.stats.npcJobs[npcIndex] (integer)
    Each farmland has farmland.npcIndex identifying the NPC seller
    Discount = min(jobCount, maxJobs, floor(0.5/discPerJob)) * discPerJob * farmlandPrice

    @param farmland - The farmland object (from g_farmlandManager)
    @param farmId - The farm ID of the buyer
    @return discountAmount, discountPercent, jobCount, maxJobs
            Returns 0,0,0,0 if BC not installed, not enabled, or no discount
]]
function ModCompatibility.getBCFarmlandDiscount(farmland, farmId)
    if not ModCompatibility.betterContractsInstalled then
        return 0, 0, 0, 0
    end

    -- Validate inputs
    if farmland == nil or farmId == nil then
        return 0, 0, 0, 0
    end

    -- Read BC config from savegame XML (no sandbox issues)
    local bcConfig = ModCompatibility.readBCConfig()
    if bcConfig == nil or not bcConfig.discountMode then
        return 0, 0, 0, 0
    end

    local discPerJob = bcConfig.discPerJob
    local discMaxJobs = bcConfig.discMaxJobs

    -- Get farm and NPC job counts (shared game object, populated by BC)
    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil or farm.stats == nil then
        return 0, 0, 0, 0
    end

    -- Get NPC index for this farmland
    local npcIndex = farmland.npcIndex
    if npcIndex == nil then
        return 0, 0, 0, 0
    end

    -- Read job count from BC's data on farm stats
    -- BC appends to FarmStats:loadFromXMLFile() to populate npcJobs on the shared farm object
    local jobs = farm.stats.npcJobs or {}
    local jobCount = jobs[npcIndex] or 0

    -- Calculate discount (matches BC's formula exactly)
    -- Safety cap: floor(0.5/discPerJob) ensures discount can never exceed 50%
    local discountAmount = 0
    local discountPercent = 0
    if jobCount > 0 then
        local effectiveJobs = math.min(jobCount, discMaxJobs, math.floor(0.5 / discPerJob))
        discountPercent = math.floor(effectiveJobs * 100 * discPerJob)
        discountAmount = farmland.price * effectiveJobs * discPerJob
    end

    UsedPlus.logWarn(string.format(
        "BC farmland discount: NPC=%d, jobs=%d/%d, discount=%d%% ($%d)",
        npcIndex, jobCount, discMaxJobs, discountPercent, discountAmount))

    -- Always return maxJobs when BC discountMode is active (signals integration is live)
    return discountAmount, discountPercent, jobCount, discMaxJobs
end

--============================================================================
-- FEATURE AVAILABILITY QUERIES
-- Used by UI and managers to determine which features to enable/show
--============================================================================

--[[
    Should UsedPlus show the Finance button in shop?
    @return boolean - false if HirePurchasing handles financing
]]
function ModCompatibility.shouldShowFinanceButton()
    return not ModCompatibility.hirePurchasingInstalled
end

--[[
    Should UsedPlus show the Used Search button in shop?
    @return boolean - false if BuyUsedEquipment handles used search
]]
function ModCompatibility.shouldShowSearchButton()
    return not ModCompatibility.buyUsedEquipmentInstalled
end

--[[
    Should UsedPlus enable its loan/financing system?
    @return boolean - false if EnhancedLoanSystem handles loans
]]
function ModCompatibility.shouldEnableLoanSystem()
    return not ModCompatibility.enhancedLoanSystemInstalled
end

--[[
    Should UsedPlus show the "Take Loan" option in Finance Manager?
    @return boolean - false if ELS handles loans
]]
function ModCompatibility.shouldShowTakeLoanOption()
    return not ModCompatibility.enhancedLoanSystemInstalled
end

--[[
    Should UsedPlus initialize UsedVehicleManager?
    @return boolean - false if BuyUsedEquipment handles used search
]]
function ModCompatibility.shouldInitUsedVehicleManager()
    return not ModCompatibility.buyUsedEquipmentInstalled
end

--[[
    Should UsedPlus initialize FinanceManager?
    @return boolean - false if EnhancedLoanSystem handles loans
    Note: We still initialize for lease tracking even with ELS
]]
function ModCompatibility.shouldInitFinanceManager()
    -- Always initialize - we use it for leases and sales too
    -- But loan creation will be blocked
    return true
end

--[[
    Should UsedPlus chain to AdvancedMaintenance's damage check?
    @param vehicle - The vehicle to check
    @return boolean, function - Whether to chain, and the function to call
]]
function ModCompatibility.getAdvancedMaintenanceChain(vehicle)
    if not ModCompatibility.advancedMaintenanceInstalled then
        return false, nil
    end

    -- Try to get AM's damage check function
    if vehicle and vehicle.advancedMaintenanceCheckDamage then
        return true, vehicle.advancedMaintenanceCheckDamage
    end

    -- Alternative: check for the AM specialization
    if vehicle and vehicle.spec_advancedMaintenance then
        local spec = vehicle.spec_advancedMaintenance
        if spec and AdvancedMaintenance and AdvancedMaintenance.CheckDamage then
            return true, function()
                return AdvancedMaintenance.CheckDamage(vehicle)
            end
        end
    end

    return false, nil
end

--[[
    Get status string including all detected mods
]]
function ModCompatibility.getStatusString()
    local parts = {}

    -- Integrated mods
    if ModCompatibility.rvbInstalled then
        table.insert(parts, "RVB")
    end
    if ModCompatibility.uytInstalled then
        table.insert(parts, "UYT")
    end

    -- Compatible mods
    if ModCompatibility.advancedMaintenanceInstalled then
        table.insert(parts, "AM")
    end
    if ModCompatibility.hirePurchasingInstalled then
        table.insert(parts, "HP")
    end
    if ModCompatibility.buyUsedEquipmentInstalled then
        table.insert(parts, "BUE")
    end
    if ModCompatibility.enhancedLoanSystemInstalled then
        table.insert(parts, "ELS")
    end
    if ModCompatibility.betterContractsInstalled then
        table.insert(parts, "BC")
    end

    if #parts == 0 then
        return "Standalone mode (no compatible mods)"
    else
        return "Compatible mods: " .. table.concat(parts, " + ")
    end
end

--[[
    Get detailed feature status for debugging/display
    @return table with feature availability
]]
function ModCompatibility.getFeatureStatus()
    return {
        financeButton = ModCompatibility.shouldShowFinanceButton(),
        searchButton = ModCompatibility.shouldShowSearchButton(),
        loanSystem = ModCompatibility.shouldEnableLoanSystem(),
        takeLoanOption = ModCompatibility.shouldShowTakeLoanOption(),
        usedVehicleManager = ModCompatibility.shouldInitUsedVehicleManager(),
        financeManager = ModCompatibility.shouldInitFinanceManager(),
        -- Integrated features (always active with source attribution)
        engineSymptoms = true,  -- Always enabled, sources from RVB if available
        tireTracking = true,    -- Always enabled, syncs from UYT if available
        hydraulicDrift = true,  -- Unique to UsedPlus
        steeringPull = true,    -- Unique to UsedPlus
    }
end

--============================================================================
-- EXTERNAL MOD DATA ACCESS
-- Read loan/lease data from other mods for unified Finance Manager display
--============================================================================

--[[
    Get all active ELS loans for a farm
    @param farmId - Farm ID to get loans for
    @return array of pseudo-deal objects for Finance Manager display
]]
function ModCompatibility.getELSLoans(farmId)
    local loans = {}

    -- v2.8.0: Late-binding check for ELS - handles case where detection ran too early
    -- ELS creates g_els_loanManager at file load, but loans are converted in onStartMission
    if g_els_loanManager ~= nil then
        -- Update detection flag if we missed it earlier
        if not ModCompatibility.enhancedLoanSystemInstalled then
            UsedPlus.logDebug("ELS detected late (getELSLoans) - updating flag")
            ModCompatibility.enhancedLoanSystemInstalled = true
        end
    end

    if not ModCompatibility.enhancedLoanSystemInstalled then
        return loans
    end

    -- Access ELS loan manager
    if g_els_loanManager == nil then
        UsedPlus.logDebug("getELSLoans: g_els_loanManager is nil")
        return loans
    end

    -- v2.8.0: Check if currentLoans method exists using type() instead of field lookup
    if type(g_els_loanManager.currentLoans) ~= "function" then
        UsedPlus.logDebug("getELSLoans: currentLoans method not found (type=" ..
            tostring(type(g_els_loanManager.currentLoans)) .. ")")
        return loans
    end

    -- Get ELS loans for this farm
    local success, elsLoans = pcall(function()
        return g_els_loanManager:currentLoans(farmId)
    end)

    if not success then
        UsedPlus.logDebug("getELSLoans: Error calling currentLoans - " .. tostring(elsLoans))
        return loans
    end

    if elsLoans == nil or #elsLoans == 0 then
        UsedPlus.logDebug(string.format("getELSLoans: No loans found for farm %d", farmId or 0))
        return loans
    end

    UsedPlus.logDebug(string.format("getELSLoans: Found %d ELS loans for farm %d", #elsLoans, farmId or 0))

    for i, loan in ipairs(elsLoans) do
        -- Create pseudo-deal object matching UsedPlus structure
        local monthlyPayment = 0
        if type(loan.calculateAnnuity) == "function" then
            local ok, result = pcall(function() return loan:calculateAnnuity() end)
            if ok then monthlyPayment = result end
        end

        local totalAmount = 0
        if type(loan.calculateTotalAmount) == "function" then
            local ok, result = pcall(function() return loan:calculateTotalAmount() end)
            if ok then totalAmount = result end
        end

        -- v2.8.0: Better loan naming - show original amount
        local loanAmount = loan.amount or 0
        local loanName = string.format("ELS Loan ($%s)", g_i18n:formatMoney(loanAmount, 0, true, false) or tostring(loanAmount))

        local pseudoDeal = {
            id = "ELS_LOAN_" .. tostring(i),
            dealType = 100,  -- Special type for ELS loans
            itemName = loanName,
            currentBalance = loan.restAmount or loan.amount or 0,
            originalAmount = loan.amount or 0,
            monthlyPayment = monthlyPayment,
            interestRate = (loan.interest or 0) / 100,  -- v2.8.0: ELS stores as %, convert to decimal
            termMonths = (loan.duration or 1) * 12,
            monthsPaid = ((loan.duration or 1) * 12) - (loan.restDuration or 0),
            remainingMonths = loan.restDuration or 0,
            totalAmount = totalAmount,
            status = "active",
            isELSLoan = true,
            elsLoanRef = loan,  -- Store reference for payoff
            farmId = farmId,
        }

        UsedPlus.logDebug(string.format("  ELS Loan #%d: $%d balance, $%d/mo, %d mo remaining",
            i, pseudoDeal.currentBalance, math.floor(monthlyPayment), loan.restDuration or 0))

        table.insert(loans, pseudoDeal)
    end

    return loans
end

--[[
    Get all active HirePurchasing leases for a farm
    @param farmId - Farm ID to get leases for
    @return array of pseudo-deal objects for Finance Manager display
]]
function ModCompatibility.getHPLeases(farmId)
    local leases = {}

    if not ModCompatibility.hirePurchasingInstalled then
        return leases
    end

    -- Access HirePurchasing lease options
    if g_currentMission and g_currentMission.LeasingOptions and g_currentMission.LeasingOptions.leaseDeals then
        for i, deal in pairs(g_currentMission.LeasingOptions.leaseDeals) do
            if deal.farmId == farmId then
                -- Calculate monthly payment
                local monthlyPayment = 0
                if deal.getMonthlyPayment then
                    monthlyPayment = deal:getMonthlyPayment()
                end

                -- Calculate settlement cost
                local settlementCost = 0
                if deal.getSettlementCost then
                    settlementCost = deal:getSettlementCost()
                end

                -- Get vehicle name
                local vehicleName = "HP Lease"
                local vehicle = nil
                if deal.getVehicle then
                    vehicle = deal:getVehicle()
                    if vehicle and vehicle.getName then
                        vehicleName = vehicle:getName()
                    end
                end

                local remainingMonths = (deal.durationMonths or 0) - (deal.monthsPaid or 0)
                local remainingBalance = monthlyPayment * remainingMonths + (deal.finalFee or 0)

                local pseudoDeal = {
                    id = "HP_LEASE_" .. tostring(deal.id or i),
                    dealType = 101,  -- Special type for HP leases
                    itemName = vehicleName,
                    currentBalance = remainingBalance,
                    baseCost = deal.baseCost or 0,
                    deposit = deal.deposit or 0,
                    monthlyPayment = monthlyPayment,
                    termMonths = deal.durationMonths or 0,
                    monthsPaid = deal.monthsPaid or 0,
                    remainingMonths = remainingMonths,
                    finalFee = deal.finalFee or 0,
                    settlementCost = settlementCost,
                    status = "active",
                    isHPLease = true,
                    hpDealRef = deal,  -- Store reference for payoff
                    hpVehicle = vehicle,
                    farmId = farmId,
                }

                table.insert(leases, pseudoDeal)
            end
        end
    end

    return leases
end

--[[
    Make an early payment on an ELS loan
    @param pseudoDeal - The pseudo-deal object containing elsLoanRef
    @param amount - Amount to pay
    @return boolean - true if payment successful
]]
function ModCompatibility.payELSLoan(pseudoDeal, amount)
    if not pseudoDeal or not pseudoDeal.isELSLoan or not pseudoDeal.elsLoanRef then
        return false
    end

    local loan = pseudoDeal.elsLoanRef

    -- ELS uses specialRedemptionPayment for extra payments
    if g_els_loanManager and g_els_loanManager.specialRedemptionPayment then
        local success = g_els_loanManager:specialRedemptionPayment(loan, amount)
        if success then
            UsedPlus.logInfo(string.format("ELS loan payment: $%d applied", amount))
            return true
        end
    end

    return false
end

--[[
    Make a payment on an HP lease
    @param pseudoDeal - The pseudo-deal object containing hpDealRef
    @param amount - Amount to pay
    @return boolean - true if payment successful
]]
function ModCompatibility.payHPLease(pseudoDeal, amount)
    if not pseudoDeal or not pseudoDeal.isHPLease or not pseudoDeal.hpDealRef then
        return false
    end

    local deal = pseudoDeal.hpDealRef

    -- Check if player can afford
    local farm = g_farmManager:getFarmById(pseudoDeal.farmId)
    if not farm or farm.money < amount then
        return false
    end

    -- Try to use HP's payment processing if available
    -- HP processes payments automatically on HOUR_CHANGED, but we can
    -- try to trigger a manual payment if the API is exposed
    if deal.processPayment then
        local success = deal:processPayment(amount)
        if success then
            UsedPlus.logInfo(string.format("HP lease payment processed: $%d", amount))
            return true
        end
    end

    -- Alternative: Check if LeasingOptions has a payment method
    if g_currentMission.LeasingOptions and g_currentMission.LeasingOptions.makePayment then
        local success = g_currentMission.LeasingOptions:makePayment(deal, amount)
        if success then
            UsedPlus.logInfo(string.format("HP lease payment via LeasingOptions: $%d", amount))
            return true
        end
    end

    -- HP doesn't expose a direct payment API
    -- Payments are handled automatically by HP on hour change
    UsedPlus.logInfo("HP lease payments are managed automatically by HirePurchasing mod")
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_INFO,
        "HP lease payments are automatic - managed by HirePurchasing"
    )

    return false
end

--[[
    Settle (pay off) an HP lease early
    @param pseudoDeal - The pseudo-deal object containing hpDealRef
    @return boolean - true if settlement successful
]]
function ModCompatibility.settleHPLease(pseudoDeal)
    if not pseudoDeal or not pseudoDeal.isHPLease or not pseudoDeal.hpDealRef then
        return false
    end

    local deal = pseudoDeal.hpDealRef
    local settlementCost = pseudoDeal.settlementCost or 0

    -- Check if player can afford
    local farm = g_farmManager:getFarmById(pseudoDeal.farmId)
    if not farm or farm.money < settlementCost then
        return false
    end

    -- HP doesn't have a direct settlement API, but we can try:
    -- 1. Process remaining months rapidly
    -- 2. Or call any settlement function if available

    -- For now, we'll just display the settlement cost
    -- Full HP settlement would require HP mod to expose an API
    UsedPlus.logInfo(string.format("HP lease settlement would cost: $%d", settlementCost))

    -- Return false since we can't actually settle without HP API
    -- This is informational only until HP exposes settlement function
    return false
end

--[[
    Get total monthly obligations from external mods
    @param farmId - Farm ID
    @return number - Total monthly payment from ELS + HP
]]
function ModCompatibility.getExternalMonthlyObligations(farmId)
    local total = 0

    -- ELS loans
    local elsLoans = ModCompatibility.getELSLoans(farmId)
    for _, loan in ipairs(elsLoans) do
        total = total + (loan.monthlyPayment or 0)
    end

    -- HP leases
    local hpLeases = ModCompatibility.getHPLeases(farmId)
    for _, lease in ipairs(hpLeases) do
        total = total + (lease.monthlyPayment or 0)
    end

    return total
end

--[[
    Get total debt from external mods
    @param farmId - Farm ID
    @return number - Total debt from ELS + HP
]]
function ModCompatibility.getExternalTotalDebt(farmId)
    local total = 0

    -- ELS loans
    local elsLoans = ModCompatibility.getELSLoans(farmId)
    for _, loan in ipairs(elsLoans) do
        total = total + (loan.currentBalance or 0)
    end

    -- HP leases
    local hpLeases = ModCompatibility.getHPLeases(farmId)
    for _, lease in ipairs(hpLeases) do
        total = total + (lease.currentBalance or 0)
    end

    return total
end

--============================================================================
-- EMPLOYMENT SYSTEM INTEGRATION
--============================================================================

--[[
    Get total monthly employment wages
    @param playerId - Player user ID (not farm ID)
    @return number - Total monthly wages, 0 if Employment not installed
]]
function ModCompatibility.getEmploymentMonthlyCost(playerId)
    if not g_currentMission or not g_currentMission.employmentSystem then
        return 0
    end

    local employmentSystem = g_currentMission.employmentSystem
    if employmentSystem.getTotalWagesCost then
        return employmentSystem:getTotalWagesCost(playerId) or 0
    end

    return 0
end

--[[
    Get employee count
    @param playerId - Player user ID
    @return number - Total employees, 0 if Employment not installed
]]
function ModCompatibility.getEmployeeCount(playerId)
    if not g_currentMission or not g_currentMission.employmentSystem then
        return 0
    end

    local employmentSystem = g_currentMission.employmentSystem
    if employmentSystem.getEmployeeCount then
        return employmentSystem:getEmployeeCount(playerId) or 0
    end

    return 0
end

--============================================================================
-- FARMLAND ASSETS INTEGRATION
--============================================================================

--[[
    Get total farmland value owned by a farm
    @param farmId - Farm ID
    @return number - Total farmland value
]]
function ModCompatibility.getFarmlandValue(farmId)
    if not g_farmlandManager then
        return 0
    end

    local totalValue = 0

    for _, farmland in pairs(g_farmlandManager.farmlands or {}) do
        if g_farmlandManager:getFarmlandOwner(farmland.id) == farmId then
            totalValue = totalValue + (farmland.price or 0)
        end
    end

    return totalValue
end

--[[
    Get farmland count owned by a farm
    @param farmId - Farm ID
    @return number - Number of farmland parcels owned
]]
function ModCompatibility.getFarmlandCount(farmId)
    if not g_farmlandManager then
        return 0
    end

    local count = 0

    for _, farmland in pairs(g_farmlandManager.farmlands or {}) do
        if g_farmlandManager:getFarmlandOwner(farmland.id) == farmId then
            count = count + 1
        end
    end

    return count
end

--============================================================================
-- USED VEHICLE SPAWN INITIALIZATION
-- Apply pre-generated RVB/UYT data to newly spawned used vehicles
--============================================================================

--[[
    Initialize RVB parts data on a spawned used vehicle
    Called after vehicle purchase to apply the inspection-revealed part conditions

    @param vehicle - The spawned vehicle
    @param rvbPartsData - Table with part data from listing.rvbPartsData
    @return boolean - true if initialization successful
]]
function ModCompatibility.initializeRVBPartsFromListing(vehicle, rvbPartsData)
    if not ModCompatibility.rvbInstalled then
        UsedPlus.logDebug("initializeRVBPartsFromListing: RVB not installed, skipping")
        return false
    end

    if vehicle == nil or rvbPartsData == nil then
        UsedPlus.logWarn("initializeRVBPartsFromListing: Invalid vehicle or data")
        return false
    end

    local rvb = vehicle.spec_faultData
    if not rvb or not rvb.parts then
        UsedPlus.logDebug("initializeRVBPartsFromListing: Vehicle has no RVB spec_faultData")
        return false
    end

    -- Apply each part's operating hours from the listing data
    -- RVB calculates life from: 1 - (operatingHours / tmp_lifetime)
    local partsApplied = 0

    for partKey, partData in pairs(rvbPartsData) do
        local rvbPart = rvb.parts[partKey]
        if rvbPart then
            -- Set the operating hours to match the pre-generated life
            -- If RVB's lifetime differs from ours, recalculate hours
            local rvbLifetime = rvbPart.tmp_lifetime or partData.lifetime or 1000
            local targetLife = partData.life or 1.0

            -- hours = (1 - life) * lifetime
            local targetHours = math.floor((1 - targetLife) * rvbLifetime)
            rvbPart.operatingHours = targetHours

            UsedPlus.logDebug(string.format("  RVB %s: Set hours to %d (life %.0f%%)",
                partKey, targetHours, targetLife * 100))

            partsApplied = partsApplied + 1
        end
    end

    UsedPlus.logInfo(string.format("initializeRVBPartsFromListing: Applied %d RVB parts to vehicle",
        partsApplied))

    return partsApplied > 0
end

--[[
    Initialize UYT tire conditions on a spawned used vehicle
    Called after vehicle purchase to apply the inspection-revealed tire conditions

    @param vehicle - The spawned vehicle
    @param tireConditions - Table with conditions from listing.tireConditions (FL, FR, RL, RR)
    @return boolean - true if initialization successful
]]
function ModCompatibility.initializeTiresFromListing(vehicle, tireConditions)
    if vehicle == nil or tireConditions == nil then
        UsedPlus.logWarn("initializeTiresFromListing: Invalid vehicle or data")
        return false
    end

    -- Apply to UsedPlus native tire tracking
    local spec = vehicle.spec_usedPlusMaintenance
    if spec and spec.tires then
        local tireMapping = { "FL", "FR", "RL", "RR" }
        for i, tireKey in ipairs(tireMapping) do
            if spec.tires[i] and tireConditions[tireKey] then
                spec.tires[i].condition = tireConditions[tireKey]
                UsedPlus.logDebug(string.format("  Tire %d (%s): Set condition to %.0f%%",
                    i, tireKey, tireConditions[tireKey] * 100))
            end
        end
    end

    -- If UYT is installed, try to set tire wear there too
    local uyt = ModCompatibility.uytGlobal
    if ModCompatibility.uytInstalled and uyt then
        -- UYT stores wear (inverse of condition) per wheel
        if vehicle.spec_wheels and vehicle.spec_wheels.wheels then
            local wheelCount = #vehicle.spec_wheels.wheels
            local tireKeys = { "FL", "FR", "RL", "RR" }

            for i = 1, math.min(wheelCount, 4) do
                local wheel = vehicle.spec_wheels.wheels[i]
                local condition = tireConditions[tireKeys[i]] or 1.0
                local wear = 1.0 - condition

                -- Try to set UYT wear if the API is available
                if wheel and uyt.setWearAmount then
                    uyt.setWearAmount(wheel, wear)
                    UsedPlus.logDebug(string.format("  UYT wheel %d: Set wear to %.0f%%",
                        i, wear * 100))
                end
            end
        end
    end

    UsedPlus.logInfo("initializeTiresFromListing: Applied tire conditions to vehicle")
    return true
end

--[[
    Apply all listing data to a spawned used vehicle
    Master function that applies RVB parts, tires, and UsedPlus maintenance data

    @param vehicle - The spawned vehicle
    @param listing - The listing data with rvbPartsData, tireConditions, usedPlusData
]]
function ModCompatibility.applyListingDataToVehicle(vehicle, listing)
    if vehicle == nil or listing == nil then
        UsedPlus.logWarn("applyListingDataToVehicle: Invalid vehicle or listing")
        return
    end

    UsedPlus.logInfo(string.format("Applying listing data to spawned vehicle: %s",
        listing.storeItemName or "Unknown"))

    -- v2.1.0: ALWAYS store the data on the vehicle for persistence and deferred sync
    -- This ensures the data survives saves and can be synced when RVB/UYT is installed later
    local spec = vehicle.spec_usedPlusMaintenance
    if spec and (listing.rvbPartsData or listing.tireConditions) then
        if vehicle.storeListingData then
            vehicle:storeListingData(listing.rvbPartsData, listing.tireConditions)
        else
            -- Fallback: directly store on spec
            if listing.rvbPartsData then
                spec.storedRvbPartsData = listing.rvbPartsData
                spec.rvbDataSynced = ModCompatibility.rvbInstalled
            end
            if listing.tireConditions then
                spec.storedTireConditions = listing.tireConditions
                spec.tireDataSynced = ModCompatibility.uytInstalled
            end
        end
        UsedPlus.logDebug("  Stored RVB/tire data on vehicle for persistence")
    end

    -- Apply RVB parts data if present (only if RVB installed)
    if listing.rvbPartsData then
        ModCompatibility.initializeRVBPartsFromListing(vehicle, listing.rvbPartsData)
    end

    -- Apply tire conditions if present
    if listing.tireConditions then
        ModCompatibility.initializeTiresFromListing(vehicle, listing.tireConditions)
    end

    -- Apply UsedPlus maintenance data if present
    if listing.usedPlusData then
        local spec = vehicle.spec_usedPlusMaintenance
        if spec then
            spec.engineReliability = listing.usedPlusData.engineReliability or spec.engineReliability
            spec.hydraulicReliability = listing.usedPlusData.hydraulicReliability or spec.hydraulicReliability
            spec.electricalReliability = listing.usedPlusData.electricalReliability or spec.electricalReliability
            spec.workhorseLemonScale = listing.usedPlusData.workhorseLemonScale or spec.workhorseLemonScale

            UsedPlus.logDebug(string.format("  UsedPlus maintenance: Engine=%.0f%%, Hydraulic=%.0f%%, Electrical=%.0f%%",
                spec.engineReliability * 100,
                spec.hydraulicReliability * 100,
                spec.electricalReliability * 100))
        end
    end

    -- Apply basic wear/damage from listing
    if listing.damage and listing.damage > 0 then
        if vehicle.setDamageAmount then
            vehicle:setDamageAmount(listing.damage)
            UsedPlus.logDebug(string.format("  Damage: Set to %.0f%%", listing.damage * 100))
        end
    end

    if listing.wear and listing.wear > 0 then
        if vehicle.setWearAmount then
            vehicle:setWearAmount(listing.wear)
            UsedPlus.logDebug(string.format("  Wear: Set to %.0f%%", listing.wear * 100))
        end
    end

    if listing.operatingHours and listing.operatingHours > 0 then
        if vehicle.setOperatingTime then
            -- FS25 uses milliseconds for operating time
            vehicle:setOperatingTime(listing.operatingHours * 3600 * 1000)
            UsedPlus.logDebug(string.format("  Operating hours: Set to %d", listing.operatingHours))
        end
    end

    UsedPlus.logInfo("applyListingDataToVehicle: Complete")

    -- v2.2.0: Apply DNA-based lifetime multiplier to RVB parts
    ModCompatibility.applyDNAToRVBLifetimes(vehicle)
end

--[[
    v2.2.0: Apply initial DNA-based lifetime multiplier to all RVB parts
    Called at vehicle purchase to set starting lifetimes based on workhorse/lemon DNA

    DNA 0.0 (lemon):     0.6x lifetime = starts weaker, breaks down faster
    DNA 0.5 (average):   1.0x lifetime = normal
    DNA 1.0 (workhorse): 1.4x lifetime = starts stronger, lasts longer

    @param vehicle - The vehicle to apply multiplier to
    @return boolean - True if applied successfully
]]
function ModCompatibility.applyDNAToRVBLifetimes(vehicle)
    if not vehicle then return false end
    if not vehicle.isServer then return false end
    if not ModCompatibility.rvbInstalled then return false end

    local spec = vehicle.spec_usedPlusMaintenance
    local rvb = vehicle.spec_faultData
    if not spec or not rvb or not rvb.parts then return false end

    local dna = spec.workhorseLemonScale or 0.5
    local multiplier = 0.6 + (dna * 0.8)  -- Range: 0.6 to 1.4

    spec.rvbLifetimeMultiplier = multiplier
    spec.rvbLifetimesApplied = true

    for partKey, part in pairs(rvb.parts) do
        if part.tmp_lifetime then
            part.tmp_lifetime = part.tmp_lifetime * multiplier
        end
    end

    UsedPlus.logDebug(string.format("Applied DNA %.2f -> RVB lifetime multiplier %.2fx to %s",
        dna, multiplier, vehicle:getName()))
    return true
end

--[[
    v2.2.0: Apply repair degradation to RVB parts
    Called when RVB repair/service completes
    Lemons lose more lifetime per repair, workhorses lose little/none

    Legendary workhorses (DNA >= 0.90) are IMMUNE to repair degradation

    @param vehicle - The vehicle being repaired
]]
function ModCompatibility.applyRVBRepairDegradation(vehicle)
    if not vehicle then return end
    if not vehicle.isServer then return end
    if not ModCompatibility.rvbInstalled then return end

    local spec = vehicle.spec_usedPlusMaintenance
    local rvb = vehicle.spec_faultData
    if not spec or not rvb or not rvb.parts then return end

    local dna = spec.workhorseLemonScale or 0.5

    -- Legendary workhorses (DNA >= 0.90) are immune to repair degradation
    if dna >= 0.90 then
        UsedPlus.logDebug(string.format("Legendary workhorse - no repair degradation for %s (DNA %.2f)",
            vehicle:getName(), dna))
        return
    end

    -- Degradation formula: 0-2% per repair based on DNA
    local degradation = (1 - dna) * 0.02

    for partKey, part in pairs(rvb.parts) do
        if part.tmp_lifetime then
            part.tmp_lifetime = part.tmp_lifetime * (1 - degradation)
        end
    end

    -- Track cumulative degradation
    spec.rvbTotalDegradation = (spec.rvbTotalDegradation or 0) + degradation
    spec.rvbRepairCount = (spec.rvbRepairCount or 0) + 1

    UsedPlus.logDebug(string.format("RVB repair degradation %.1f%% applied to %s (DNA %.2f, total %.1f%%)",
        degradation * 100, vehicle:getName(), dna, spec.rvbTotalDegradation * 100))
end

--[[
    v2.2.0: Apply breakdown degradation to RVB parts
    Called when RVB fault/breakdown occurs
    Everyone loses lifetime on breakdown, but lemons lose MORE

    Legendary workhorses (DNA >= 0.95) take only 30% breakdown damage

    @param vehicle - The vehicle with the breakdown
    @param partKey - The RVB part that broke (ENGINE, BATTERY, etc.)
]]
function ModCompatibility.applyRVBBreakdownDegradation(vehicle, partKey)
    if not vehicle then return end
    if not vehicle.isServer then return end
    if not ModCompatibility.rvbInstalled then return end

    local spec = vehicle.spec_usedPlusMaintenance
    local rvb = vehicle.spec_faultData
    if not spec or not rvb or not rvb.parts then return end

    local dna = spec.workhorseLemonScale or 0.5

    -- Base degradation: 3% for everyone
    -- Lemon bonus: 0-5% extra based on DNA
    local baseDegradation = 0.03
    local lemonBonus = (1 - dna) * 0.05
    local totalDegradation = baseDegradation + lemonBonus

    -- Legendary workhorses (DNA >= 0.95) take only 30% breakdown damage
    if dna >= 0.95 then
        totalDegradation = totalDegradation * 0.3
    end

    -- Apply to the specific RVB part that broke down
    local part = rvb.parts[partKey]
    if part and part.tmp_lifetime then
        part.tmp_lifetime = part.tmp_lifetime * (1 - totalDegradation)
    end

    -- Track cumulative degradation
    spec.rvbTotalDegradation = (spec.rvbTotalDegradation or 0) + totalDegradation
    spec.rvbBreakdownCount = (spec.rvbBreakdownCount or 0) + 1

    UsedPlus.logDebug(string.format("RVB breakdown degradation %.1f%% on %s for %s (DNA %.2f)",
        totalDegradation * 100, partKey or "unknown", vehicle:getName(), dna))
end

UsedPlus.logInfo("ModCompatibility loaded")
