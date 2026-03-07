--[[
    RVBServiceHooks.lua
    Hook RVB's Service completion and fault tracking/degradation

    Extracted from RVBWorkshopIntegration.lua for modularity
    v2.2.0: Progressive degradation - DNA affects RVB part lifetimes
    v2.15.3: Fixed hook — hooks dialog:onYesNoServiceDialog() method directly
             instead of button.onClickCallback (XML onClick bypasses onClickCallback)
]]

-- Ensure RVBWorkshopIntegration table exists (modules load before coordinator)
RVBWorkshopIntegration = RVBWorkshopIntegration or {}

--[[
    Hook RVB's Service completion to apply degradation and top up UsedPlus fluids.
    Hooks onYesNoServiceDialog — the method called when the player confirms service.
]]
function RVBWorkshopIntegration:hookServiceButton(dialog)
    if dialog == nil then
        return
    end

    -- Only hook once per dialog instance
    if dialog.usedPlusServiceHooked then
        return
    end

    -- Hook the dialog's onYesNoServiceDialog METHOD
    local origOnYesNoService = dialog.onYesNoServiceDialog
    if origOnYesNoService == nil then
        local mt = getmetatable(dialog)
        while mt do
            local idx = mt.__index
            if type(idx) == "table" and idx.onYesNoServiceDialog then
                origOnYesNoService = idx.onYesNoServiceDialog
                break
            elseif type(idx) == "function" then
                break
            end
            mt = getmetatable(idx)
        end
    end

    if origOnYesNoService == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Could not find onYesNoServiceDialog to hook")
        return
    end

    dialog.onYesNoServiceDialog = function(self, yes)
        -- Call original first (this does the actual RVB service)
        origOnYesNoService(self, yes)

        -- If player confirmed service, apply UsedPlus effects
        if yes and self.vehicle then
            local vehicle = self.vehicle

            -- Apply degradation after service completes
            if ModCompatibility and ModCompatibility.applyRVBRepairDegradation then
                ModCompatibility.applyRVBRepairDegradation(vehicle)
                UsedPlus.logDebug("RVBWorkshopIntegration: Applied repair degradation after RVB service")
            end

            -- Top up UsedPlus fluids (oil + hydraulic)
            local spec = vehicle.spec_usedPlusMaintenance
            if spec then
                local fluidsToppedUp = false

                -- Top up oil
                if spec.oilLevel and spec.oilLevel < 1.0 then
                    spec.oilLevel = 1.0
                    spec.hasOilLeak = false
                    spec.oilLeakSeverity = 0
                    fluidsToppedUp = true
                    UsedPlus.logDebug("RVBWorkshopIntegration: Topped up engine oil")
                end

                -- Top up hydraulic fluid
                if spec.hydraulicFluidLevel and spec.hydraulicFluidLevel < 1.0 then
                    spec.hydraulicFluidLevel = 1.0
                    spec.hasHydraulicLeak = false
                    spec.hydraulicLeakSeverity = 0
                    fluidsToppedUp = true
                    UsedPlus.logDebug("RVBWorkshopIntegration: Topped up hydraulic fluid")
                end

                -- Small reliability boost from proper maintenance
                if fluidsToppedUp then
                    local serviceBoost = 0.03  -- 3% reliability improvement from service

                    local oldHydraulic = spec.hydraulicReliability or 1.0
                    local maxHydraulic = spec.maxHydraulicDurability or spec.maxReliabilityCeiling or 1.0
                    spec.hydraulicReliability = math.min(maxHydraulic, oldHydraulic + serviceBoost)

                    local oldEngine = spec.engineReliability or 1.0
                    local maxEngine = spec.maxEngineDurability or spec.maxReliabilityCeiling or 1.0
                    spec.engineReliability = math.min(maxEngine, oldEngine + (serviceBoost * 0.5))

                    UsedPlus.logDebug(string.format(
                        "RVBWorkshopIntegration: Service reliability boost - hydraulic %.1f%% -> %.1f%%, engine %.1f%% -> %.1f%%",
                        oldHydraulic * 100, spec.hydraulicReliability * 100,
                        oldEngine * 100, spec.engineReliability * 100))
                end
            end
        end
    end

    dialog.usedPlusServiceHooked = true
    UsedPlus.logInfo("RVBWorkshopIntegration: Hooked onYesNoServiceDialog for service effects")
end

--[[
    Initialize fault state tracking for a vehicle
    Called when dialog opens to establish baseline
]]
function RVBWorkshopIntegration:initializeFaultTracking(vehicle)
    if vehicle == nil then
        return
    end

    local rvb = vehicle.spec_faultData
    if not rvb or not rvb.parts then
        return
    end

    -- Initialize tracking table for this vehicle
    if self.previousFaultStates[vehicle] == nil then
        self.previousFaultStates[vehicle] = {}
    end

    -- Record current fault states as baseline
    for partKey, part in pairs(rvb.parts) do
        local currentState = part.fault or "empty"
        self.previousFaultStates[vehicle][partKey] = currentState
    end

    UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Initialized fault tracking for %s (%d parts)",
        vehicle:getName(), self:countParts(rvb.parts)))
end

--[[
    Check for new faults since last check
    Called periodically or when dialog updates
]]
function RVBWorkshopIntegration:checkForNewFaults(vehicle)
    if vehicle == nil then
        return
    end

    local rvb = vehicle.spec_faultData
    if not rvb or not rvb.parts then
        return
    end

    -- Initialize if not done yet
    if self.previousFaultStates[vehicle] == nil then
        self:initializeFaultTracking(vehicle)
        return  -- No comparison possible on first check
    end

    -- Check each part for new faults
    for partKey, part in pairs(rvb.parts) do
        local currentState = part.fault or "empty"
        local previousState = self.previousFaultStates[vehicle][partKey] or "empty"

        -- Detect transition TO "fault" state (breakdown occurred)
        if currentState == "fault" and previousState ~= "fault" then
            UsedPlus.logDebug(string.format(
                "RVBWorkshopIntegration: NEW FAULT detected! Part=%s, was=%s, now=%s",
                partKey, previousState, currentState))

            -- Apply breakdown degradation
            if ModCompatibility and ModCompatibility.applyRVBBreakdownDegradation then
                ModCompatibility.applyRVBBreakdownDegradation(vehicle, partKey)
            end
        end

        -- Update tracking
        self.previousFaultStates[vehicle][partKey] = currentState
    end
end

--[[
    Count parts in a table (utility)
]]
function RVBWorkshopIntegration:countParts(partsTable)
    local count = 0
    for _ in pairs(partsTable) do
        count = count + 1
    end
    return count
end

