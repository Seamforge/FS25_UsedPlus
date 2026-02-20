--[[
    RVBServiceHooks.lua
    Hook RVB's Service button and fault tracking/degradation

    Extracted from RVBWorkshopIntegration.lua for modularity
    v2.2.0: Progressive degradation - DNA affects RVB part lifetimes
]]

-- Ensure RVBWorkshopIntegration table exists (modules load before coordinator)
RVBWorkshopIntegration = RVBWorkshopIntegration or {}

--[[
    Hook RVB's Service button to apply degradation after service completes
    This catches repairs that don't go through our RepairDialog
]]
function RVBWorkshopIntegration:hookServiceButton(dialog)
    if dialog == nil then
        return
    end

    -- Only hook once per dialog instance
    if dialog.usedPlusServiceHooked then
        return
    end

    -- Find RVB's service button
    local serviceButton = dialog.serviceButton
    if serviceButton == nil then
        -- Try to find by iterating elements
        local buttonsBox = dialog.buttonsBox
        if buttonsBox and buttonsBox.elements then
            for _, element in ipairs(buttonsBox.elements) do
                if element.id == "serviceButton" or element.name == "serviceButton" then
                    serviceButton = element
                    break
                end
            end
        end
    end

    if serviceButton == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Could not find service button to hook")
        return
    end

    -- Store original callback (may be nil if RVB hasn't assigned it yet)
    local originalCallback = serviceButton.onClickCallback

    -- Wrap with our degradation logic AND fluid top-up
    serviceButton.onClickCallback = function()
        local vehicle = dialog.vehicle
        UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Service button clicked for %s",
            vehicle and vehicle:getName() or "nil"))

        -- v2.15.0: Call original service with robust fallback
        -- originalCallback may be nil (RVB hadn't assigned it at hook time) or may need dialog context
        local serviceCallOk = false
        if originalCallback then
            -- Try closure-style first (most common)
            local ok = pcall(originalCallback)
            if ok then
                serviceCallOk = true
            else
                -- Try method-style with dialog as self
                ok = pcall(originalCallback, dialog)
                if ok then serviceCallOk = true end
            end
        end
        -- Fallback: try well-known RVB method names on the dialog
        if not serviceCallOk then
            local fallbackNames = {"onServiceButtonClick", "onService", "serviceVehicle"}
            for _, name in ipairs(fallbackNames) do
                if dialog[name] and type(dialog[name]) == "function" then
                    local ok = pcall(dialog[name], dialog)
                    if ok then
                        serviceCallOk = true
                        UsedPlus.logDebug("RVBWorkshopIntegration: Service called via fallback: " .. name)
                        break
                    end
                end
            end
        end
        if not serviceCallOk then
            UsedPlus.logDebug("RVBWorkshopIntegration: Could not invoke RVB native service — applying UsedPlus service only")
        end

        -- Apply degradation after service completes
        -- Note: Service in RVB typically resets wear/fixes minor issues
        if vehicle and ModCompatibility and ModCompatibility.applyRVBRepairDegradation then
            ModCompatibility.applyRVBRepairDegradation(vehicle)
            UsedPlus.logDebug("RVBWorkshopIntegration: Applied repair degradation after RVB service")
        end

        -- v2.5.1: Service also tops up UsedPlus fluids (oil + hydraulic)
        -- This creates cohesive experience - RVB service includes our fluids
        local spec = vehicle and vehicle.spec_usedPlusMaintenance
        if spec then
            local fluidsToppedUp = false

            -- Top up oil
            if spec.oilLevel and spec.oilLevel < 1.0 then
                spec.oilLevel = 1.0
                spec.hasOilLeak = false  -- Service fixes minor leaks
                spec.oilLeakSeverity = 0
                fluidsToppedUp = true
                UsedPlus.logDebug("RVBWorkshopIntegration: Topped up engine oil")
            end

            -- Top up hydraulic fluid
            if spec.hydraulicFluidLevel and spec.hydraulicFluidLevel < 1.0 then
                spec.hydraulicFluidLevel = 1.0
                spec.hasHydraulicLeak = false  -- Service fixes minor leaks
                spec.hydraulicLeakSeverity = 0
                fluidsToppedUp = true
                UsedPlus.logDebug("RVBWorkshopIntegration: Topped up hydraulic fluid")
            end

            -- Small reliability boost from proper maintenance (max 5% boost, caps at ceiling)
            if fluidsToppedUp then
                local serviceBoost = 0.03  -- 3% reliability improvement from service

                -- Hydraulic boost (primary benefit for v2.5.0 malfunctions)
                local oldHydraulic = spec.hydraulicReliability or 1.0
                local maxHydraulic = spec.maxHydraulicDurability or spec.maxReliabilityCeiling or 1.0
                spec.hydraulicReliability = math.min(maxHydraulic, oldHydraulic + serviceBoost)

                -- Engine boost (minor)
                local oldEngine = spec.engineReliability or 1.0
                local maxEngine = spec.maxEngineDurability or spec.maxReliabilityCeiling or 1.0
                spec.engineReliability = math.min(maxEngine, oldEngine + (serviceBoost * 0.5))

                UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Service reliability boost - hydraulic %.1f%% -> %.1f%%, engine %.1f%% -> %.1f%%",
                    oldHydraulic * 100, spec.hydraulicReliability * 100,
                    oldEngine * 100, spec.engineReliability * 100))
            end
        end
    end

    dialog.usedPlusServiceHooked = true
    UsedPlus.logDebug("RVBWorkshopIntegration: Hooked RVB service button for degradation")
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

--[[
    Clean up fault tracking when vehicle is sold/removed
]]
function RVBWorkshopIntegration:cleanupFaultTracking(vehicle)
    if vehicle and self.previousFaultStates[vehicle] then
        self.previousFaultStates[vehicle] = nil
        UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Cleaned up fault tracking for %s",
            vehicle:getName()))
    end
end

--[[
    Periodic fault check for all vehicles with RVB data
    Called from UsedPlusMaintenance:onUpdate or message center subscription
]]
function RVBWorkshopIntegration:updateFaultMonitoring()
    if not ModCompatibility or not ModCompatibility.rvbInstalled then
        return
    end

    -- Check all vehicles with UsedPlus maintenance spec
    if g_currentMission and g_currentMission.vehicles then
        for _, vehicle in ipairs(g_currentMission.vehicles) do
            if vehicle.spec_usedPlusMaintenance and vehicle.spec_faultData then
                self:checkForNewFaults(vehicle)
            end
        end
    end
end
