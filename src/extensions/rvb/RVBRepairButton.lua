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

    -- Replace with our redirect (dialog method — may not fire due to raiseCallback caching)
    dialog.onClickRepair = function(self, ...)
        RVBWorkshopIntegration:onRVBRepairButtonClick(self)
    end

    -- CRITICAL: Also replace the button element's onClickCallback directly.
    -- FS25's raiseCallback("onClickCallback") resolves button["onClickCallback"] at click time.
    -- When only hydraulic needs repair, RVB's onClickRepair bails (no faultListText),
    -- so we need our own handler to show the repair dialog.
    if dialog.repairButton then
        local origBtnCallback = dialog.repairButton.onClickCallback
        dialog.repairButton.onClickCallback = function(target, element, ...)
            -- Check if only hydraulic needs repair (no RVB parts selected)
            local hasRVBParts = false
            local vehicle = dialog.vehicle
            if vehicle and vehicle.spec_faultData and vehicle.spec_faultData.parts then
                for _, key in ipairs(g_vehicleBreakdownsPartKeys or {}) do
                    local part = vehicle.spec_faultData.parts[key]
                    if part and part.repairreq then
                        hasRVBParts = true
                        break
                    end
                end
            end

            if not hasRVBParts then
                -- v2.15.4: No RVB parts need repair — check for UsedPlus hydraulic issues (Issue #43)
                -- Previously required hydraulicRepairRequested flag, creating chicken-and-egg:
                -- flag only set inside RepairDialog, but dialog couldn't open without the flag
                local spec = vehicle and vehicle.spec_usedPlusMaintenance
                local hasHydraulicIssue = spec and (spec.hydraulicReliability or 1.0) < 0.95
                if hasHydraulicIssue or RVBWorkshopIntegration.hydraulicRepairRequested then
                    UsedPlus.logInfo("RVBRepairButton: Hydraulic-only repair — bypassing RVB onClickRepair")
                    RVBWorkshopIntegration:showHydraulicOnlyRepair(dialog)
                    return
                end
            end

            -- Normal case: RVB parts need repair, call original (goes through RVB flow)
            if origBtnCallback then
                origBtnCallback(target, element, ...)
            end
        end
        UsedPlus.logInfo("RVBWorkshopIntegration: Replaced repairButton.onClickCallback")
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
        -- Call original first (this starts the RVB time-based repair and
        -- populates rvb.repair with correct finish times for the display).
        -- For 0-part repairs, RVB's state gets stuck at ACTIVE — our gradual
        -- handler's time-based failsafe + state cleanup handles this.
        origOnYesNoRepair(self, yes)

        -- Any workshop repair always includes hydraulic/engine/fluid restoration.
        -- Hydraulics degrade over time — a full workshop repair restores them to
        -- their current max ceiling (which itself degrades with vehicle history).
        -- The toggle only controls whether the player pays extra for hydraulic repair.
        if yes and self.vehicle then
            local spec = self.vehicle.spec_usedPlusMaintenance
            local rvb = self.vehicle.spec_faultData
            if spec and rvb then
                -- Only charge hydraulic cost if toggle was checked
                local hydraulicCost = 0
                if RVBWorkshopIntegration.hydraulicRepairRequested then
                    hydraulicCost = RVBWorkshopIntegration.lastHydraulicRepairCost or 0
                end
                local env = g_currentMission.environment

                -- Capture starting values for interpolation
                -- Effective cap = min of overall ceiling AND component durability
                local hydraulicCap = math.min(spec.maxReliabilityCeiling or 1.0, spec.maxHydraulicDurability or 1.0)
                local engineCap = math.min(spec.maxReliabilityCeiling or 1.0, spec.maxEngineDurability or 1.0)
                local repairFraction = (RVBWorkshopIntegration.lastRepairPercent or 100) / 100

                -- Convert start and finish times to total minutes for progress calc
                local startMinutes = (env.currentDay * 24 * 60) + (env.currentHour * 60) + env.currentMinute
                local finishMinutes = startMinutes + 60  -- fallback: 1 hour
                if rvb.repair and rvb.repair.finishDay then
                    finishMinutes = (rvb.repair.finishDay * 24 * 60)
                        + ((rvb.repair.finishHour or 0) * 60)
                        + (rvb.repair.finishMinute or 0)
                end
                -- Ensure at least 1 minute duration
                if finishMinutes <= startMinutes then
                    finishMinutes = startMinutes + 60
                end

                -- Capture starting base damage for gradual repair
                local startDamage = 0
                if self.vehicle.getDamageAmount then
                    startDamage = self.vehicle:getDamageAmount() or 0
                end

                -- Detect if RVB actually started a real repair (with parts).
                -- If not (hydraulic-only), use time-based progress instead of RVB state.
                -- Without this, WorkshopRepair finishes instantly (0 parts = 0 time)
                -- and our gradual handler would snap to targets on the next frame.
                local hasRVBRepair = rvb.repair and rvb.repair.state and rvb.repair.state ~= 0
                    and rvb.repair.finishDay and rvb.repair.finishDay > 0

                -- When financed, hydraulic cost is included in the finance deal —
                -- don't deduct it separately during the gradual repair handler
                local isFinanced = RVBWorkshopIntegration.isFinancedRepair or false

                local startH = spec.hydraulicReliability or 1.0
                local startE = spec.engineReliability or 1.0

                -- Target = start + (cap - start) * fraction, floored at start
                -- (repair must never decrease reliability)
                local targetH = math.max(startH, startH + (hydraulicCap - startH) * repairFraction)
                local targetE = math.max(startE, math.min(engineCap, startE + 0.05))

                spec.pendingHydraulicRepair = {
                    cost = isFinanced and 0 or hydraulicCost,
                    farmId = g_currentMission:getFarmId(),
                    startMinutes = startMinutes,
                    finishMinutes = finishMinutes,
                    startHydraulic = startH,
                    targetHydraulic = targetH,
                    startEngine = startE,
                    targetEngine = targetE,
                    startOil = spec.oilLevel or 1.0,
                    startHydFluid = spec.hydraulicFluidLevel or 1.0,
                    startDamage = startDamage,
                    costDeducted = isFinanced,  -- Already paid via finance deal
                    useTimeProgress = not hasRVBRepair
                }
                UsedPlus.logInfo(string.format(
                    "RVBWorkshopIntegration: Workshop repair queued — hydraulic %.0f%%→%.0f%% (%d%%), cost=$%d, duration=%d min",
                    startH * 100, spec.pendingHydraulicRepair.targetHydraulic * 100,
                    RVBWorkshopIntegration.lastRepairPercent or 100,
                    hydraulicCost, finishMinutes - startMinutes))

                -- Reset toggle state
                RVBWorkshopIntegration.hydraulicRepairRequested = false
                RVBWorkshopIntegration.lastHydraulicRepairCost = 0
                RVBWorkshopIntegration.lastRepairPercent = 100
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
    UsedPlus.logDebug("RVBRepairButton: onRVBRepairButtonClick called")
    if dialog.usedPlusOriginalOnClickRepair then
        -- Pre-store RVB's repair callback so VehicleSellingPointExtension's showDialog
        -- hook can pass it to our RepairDialog. The showDialog hook intercepts by dialog
        -- name and doesn't have access to YesNoDialog.show()'s callback argument.
        -- We know RVB's onClickRepair will call YesNoDialog.show(self.onYesNoRepairDialog, self, ...)
        if VehicleSellingPointExtension then
            VehicleSellingPointExtension.pendingRepairCallback = dialog.onYesNoRepairDialog
            VehicleSellingPointExtension.pendingRepairTarget = dialog
            UsedPlus.logDebug(string.format("RVBRepairButton: Pre-stored callback=%s, target=%s",
                tostring(dialog.onYesNoRepairDialog), tostring(dialog)))
        end
        dialog.usedPlusOriginalOnClickRepair(dialog)
    else
        UsedPlus.logWarn("RVBWorkshopIntegration: usedPlusOriginalOnClickRepair is nil")
    end
end

--[[
    Handle hydraulic-only repair (no RVB components need repair).
    Bypasses RVB's onClickRepair entirely and shows our RepairDialog directly.
    RVB's onClickRepair has two gates that block when only hydraulic is toggled:
      1. getRepairPrice_RVBClone(true) <= 100  (hooked, but not enough)
      2. #faultListText > 0  (only counts g_vehicleBreakdownsPartKeys, not our hydraulic)
]]
function RVBWorkshopIntegration:showHydraulicOnlyRepair(dialog)
    local vehicle = dialog.vehicle
    if vehicle == nil then
        return
    end

    local hydraulicCost = self:calculateHydraulicRepairCost(vehicle)
    if hydraulicCost <= 0 then
        return
    end

    -- Pre-store the callback and target for our RepairDialog's RVB path
    if VehicleSellingPointExtension then
        VehicleSellingPointExtension.pendingRepairCallback = dialog.onYesNoRepairDialog
        VehicleSellingPointExtension.pendingRepairTarget = dialog
    end

    -- Show our RepairDialog directly with hydraulic cost
    local mode = RepairDialog.MODE_REPAIR
    if VehicleSellingPointExtension and VehicleSellingPointExtension.showRepairDialog then
        local success = VehicleSellingPointExtension.showRepairDialog(vehicle, mode, hydraulicCost)
        if success then
            UsedPlus.logInfo(string.format("RVBRepairButton: Showed hydraulic-only RepairDialog (cost=$%d)", hydraulicCost))
        else
            UsedPlus.logWarn("RVBRepairButton: Failed to show RepairDialog for hydraulic-only repair")
        end
    end
end
