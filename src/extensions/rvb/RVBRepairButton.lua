--[[
    RVBRepairButton.lua
    Hook RVB's native Repair button to redirect to UsedPlus RepairDialog

    Extracted from RVBWorkshopIntegration.lua for modularity

    v2.15.3: Fixed hook mechanism — hooks dialog:onClickRepair() method directly
             instead of button.onClickCallback (which doesn't intercept XML onClick).
             Also hooks onYesNoRepairDialog to repair hydraulics when RVB repair completes.
]]

-- Ensure RVBWorkshopIntegration table exists (modules load before coordinator)
RVBWorkshopIntegration = RVBWorkshopIntegration or {}

--[[
    Hook RVB's native Repair button to redirect to our partial repair dialog.
    Hooks the dialog METHOD onClickRepair (not button.onClickCallback),
    because RVB uses XML onClick="onClickRepair" which bypasses onClickCallback.
]]
function RVBWorkshopIntegration:hookRepairButton(dialog)
    -- v2.6.2: Don't hook repair button if repair system is disabled
    if UsedPlusSettings and UsedPlusSettings:get("enableRepairSystem") == false then
        UsedPlus.logDebug("RVBWorkshopIntegration: Repair system disabled, not hooking repair button")
        return
    end

    -- v2.7.0: Don't hook if override is disabled - let RVB handle repair natively
    if UsedPlusSettings and UsedPlusSettings:get("overrideRVBRepair") == false then
        UsedPlus.logDebug("RVBWorkshopIntegration: RVB repair override disabled, not hooking")
        -- Even if not overriding, still hook the completion to repair hydraulics
        self:hookRepairCompletion(dialog)
        return
    end

    if dialog == nil then
        return
    end

    -- Only hook once per dialog instance
    if dialog.usedPlusRepairHooked then
        return
    end

    -- Hook the dialog's onClickRepair METHOD directly (not button callback)
    -- This is what RVB's XML onClick="onClickRepair" calls
    local origOnClickRepair = dialog.onClickRepair
    if origOnClickRepair == nil then
        -- Try metatable
        local mt = getmetatable(dialog)
        while mt do
            local idx = mt.__index
            if type(idx) == "table" and idx.onClickRepair then
                origOnClickRepair = idx.onClickRepair
                break
            elseif type(idx) == "function" then
                break
            end
            mt = getmetatable(idx)
        end
    end

    if origOnClickRepair == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Could not find onClickRepair to hook")
        return
    end

    -- Store original for fallback
    dialog.usedPlusOriginalOnClickRepair = origOnClickRepair

    -- Replace with our redirect
    dialog.onClickRepair = function(self, ...)
        RVBWorkshopIntegration:onRVBRepairButtonClick(self)
    end

    dialog.usedPlusRepairHooked = true
    UsedPlus.logInfo("RVBWorkshopIntegration: Hooked onClickRepair method for repair redirect")

    -- Also hook repair completion for hydraulic repair
    self:hookRepairCompletion(dialog)
end

--[[
    Hook RVB's repair completion to also repair hydraulic reliability.
    When RVB finishes a repair (player confirms YesNo dialog), we boost hydraulics.
    This ensures hydraulic system benefits from RVB repairs even if our override is disabled.
]]
function RVBWorkshopIntegration:hookRepairCompletion(dialog)
    if dialog == nil or dialog.usedPlusRepairCompletionHooked then
        return
    end

    -- Hook onYesNoRepairDialog — called when player confirms RVB's repair
    local origOnYesNoRepair = dialog.onYesNoRepairDialog
    if origOnYesNoRepair == nil then
        local mt = getmetatable(dialog)
        while mt do
            local idx = mt.__index
            if type(idx) == "table" and idx.onYesNoRepairDialog then
                origOnYesNoRepair = idx.onYesNoRepairDialog
                break
            elseif type(idx) == "function" then
                break
            end
            mt = getmetatable(idx)
        end
    end

    if origOnYesNoRepair == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Could not find onYesNoRepairDialog to hook")
        return
    end

    dialog.onYesNoRepairDialog = function(self, yes)
        -- Call original first (this does the actual RVB repair)
        origOnYesNoRepair(self, yes)

        -- If player confirmed repair and hydraulic toggle was on, repair hydraulics
        if yes and self.vehicle and RVBWorkshopIntegration.hydraulicRepairRequested then
            local spec = self.vehicle.spec_usedPlusMaintenance
            if spec then
                -- Deduct hydraulic repair cost from farm
                local hydraulicCost = RVBWorkshopIntegration.lastHydraulicRepairCost or 0
                if hydraulicCost > 0 then
                    local farmId = g_currentMission:getFarmId()
                    if g_currentMission:getMoney(farmId) >= hydraulicCost then
                        g_currentMission:addMoney(-hydraulicCost, farmId, MoneyType.VEHICLE_RUNNING_COSTS, true)
                        UsedPlus.logInfo(string.format(
                            "RVBWorkshopIntegration: Deducted $%d for hydraulic repair", hydraulicCost))
                    end
                end

                -- Full hydraulic repair — restore to max ceiling
                local oldHydraulic = spec.hydraulicReliability or 1.0
                local maxHydraulic = spec.maxHydraulicDurability or spec.maxReliabilityCeiling or 1.0
                spec.hydraulicReliability = maxHydraulic

                -- Engine gets a small boost from the work
                local oldEngine = spec.engineReliability or 1.0
                local maxEngine = spec.maxEngineDurability or spec.maxReliabilityCeiling or 1.0
                spec.engineReliability = math.min(maxEngine, oldEngine + 0.05)

                -- Top up fluids as part of repair
                if spec.hydraulicFluidLevel and spec.hydraulicFluidLevel < 1.0 then
                    spec.hydraulicFluidLevel = 1.0
                    spec.hasHydraulicLeak = false
                    spec.hydraulicLeakSeverity = 0
                end
                if spec.oilLevel and spec.oilLevel < 1.0 then
                    spec.oilLevel = 1.0
                    spec.hasOilLeak = false
                    spec.oilLeakSeverity = 0
                end

                UsedPlus.logInfo(string.format(
                    "RVBWorkshopIntegration: Repair completed — hydraulic %.0f%% -> %.0f%%, engine %.0f%% -> %.0f%%",
                    oldHydraulic * 100, spec.hydraulicReliability * 100,
                    oldEngine * 100, spec.engineReliability * 100))

                -- Reset toggle state after repair
                RVBWorkshopIntegration.hydraulicRepairRequested = false
                RVBWorkshopIntegration.lastHydraulicRepairCost = 0
            end
        end
    end

    dialog.usedPlusRepairCompletionHooked = true
    UsedPlus.logInfo("RVBWorkshopIntegration: Hooked onYesNoRepairDialog for hydraulic repair")
end

--[[
    Handle RVB's Repair button click
    Shows our RepairDialog in MODE_REPAIR with RVB's calculated cost
]]
function RVBWorkshopIntegration:onRVBRepairButtonClick(dialog)
    -- Let RVB handle repair natively — its component-based system shows proper
    -- part breakdowns, costs, and repair times. Our RepairDialog is designed for
    -- vanilla FS25 damage/wear, not RVB components.
    -- hookRepairCompletion handles hydraulic repair when RVB's repair completes.
    if dialog.usedPlusOriginalOnClickRepair then
        dialog.usedPlusOriginalOnClickRepair(dialog)
    else
        UsedPlus.logWarn("RVBWorkshopIntegration: usedPlusOriginalOnClickRepair is nil")
    end
end
