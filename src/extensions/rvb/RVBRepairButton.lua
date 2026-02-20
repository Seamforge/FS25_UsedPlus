--[[
    RVBRepairButton.lua
    Hook RVB's native Repair button to redirect to UsedPlus RepairDialog

    Extracted from RVBWorkshopIntegration.lua for modularity
]]

-- Ensure RVBWorkshopIntegration table exists (modules load before coordinator)
RVBWorkshopIntegration = RVBWorkshopIntegration or {}

--[[
    Hook RVB's native Repair button to redirect to our partial repair dialog
    Uses RVB's calculated repair cost
]]
function RVBWorkshopIntegration:hookRepairButton(dialog)
    -- v2.6.2: Don't hook repair button if repair system is disabled
    if UsedPlusSettings and UsedPlusSettings:get("enableRepairSystem") == false then
        UsedPlus.logDebug("RVBWorkshopIntegration: Repair system disabled, not hooking repair button")
        return
    end

    -- v2.7.0: Don't hook if override is disabled - let RVB handle repair natively
    if UsedPlusSettings and UsedPlusSettings:get("overrideRVBRepair") == false then
        UsedPlus.logDebug("RVBWorkshopIntegration: RVB repair override disabled, not hooking repair button")
        return
    end

    if dialog == nil then
        return
    end

    -- Only hook once per dialog instance
    if dialog.usedPlusRepairHooked then
        return
    end

    -- Find RVB's repair button
    local repairButton = dialog.repairButton
    if repairButton == nil then
        -- Try to find by iterating elements
        local buttonsBox = dialog.buttonsBox
        if buttonsBox and buttonsBox.elements then
            for _, element in ipairs(buttonsBox.elements) do
                if element.id == "repairButton" or element.name == "repairButton" then
                    repairButton = element
                    break
                end
            end
        end
    end

    if repairButton == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Could not find repair button to hook")
        return
    end

    -- Store original callback for potential fallback
    dialog.usedPlusOriginalRepairCallback = repairButton.onClickCallback

    -- Replace with our callback
    repairButton.onClickCallback = function()
        RVBWorkshopIntegration:onRVBRepairButtonClick(dialog)
    end

    dialog.usedPlusRepairHooked = true
    UsedPlus.logDebug("RVBWorkshopIntegration: Hooked RVB repair button")
end

--[[
    v2.15.0: Update the Repair button enabled/disabled state based on vehicle damage
    RVB's own updateScreen may disable the button; we re-enable if there's mechanical damage to fix
]]
function RVBWorkshopIntegration:updateRepairButtonState(dialog)
    local repairButton = dialog.repairButton
    if repairButton == nil then
        -- Try to find by iterating elements (same pattern as hookRepairButton)
        local buttonsBox = dialog.buttonsBox
        if buttonsBox and buttonsBox.elements then
            for _, element in ipairs(buttonsBox.elements) do
                if element.id == "repairButton" or element.name == "repairButton" then
                    repairButton = element
                    break
                end
            end
        end
    end

    if repairButton == nil then
        return
    end

    local vehicle = dialog.vehicle
    if vehicle == nil then
        if repairButton.setDisabled then
            repairButton:setDisabled(true)
        end
        return
    end

    -- Check mechanical damage (base game damage amount)
    local damage = 0
    if vehicle.getDamageAmount then
        damage = vehicle:getDamageAmount() or 0
    end

    -- Also check UsedPlus reliability - if any component is below ceiling, repair is useful
    local hasUsedPlusDamage = false
    local spec = vehicle.spec_usedPlusMaintenance
    if spec then
        local ceiling = spec.maxReliabilityCeiling or 1.0
        if (spec.engineReliability or 1.0) < ceiling or
           (spec.hydraulicReliability or 1.0) < ceiling or
           (spec.electricalReliability or 1.0) < ceiling then
            hasUsedPlusDamage = true
        end
    end

    -- Enable if there's any damage to repair
    local hasDamage = damage > 0.01 or hasUsedPlusDamage
    if repairButton.setDisabled then
        repairButton:setDisabled(not hasDamage)
    end
end

--[[
    Handle RVB's Repair button click
    Shows our RepairDialog in MODE_REPAIR with RVB's calculated cost
]]
function RVBWorkshopIntegration:onRVBRepairButtonClick(dialog)
    -- v2.6.2: Check master repair system toggle
    -- v2.7.0: Also check override setting
    local repairDisabled = UsedPlusSettings and UsedPlusSettings:get("enableRepairSystem") == false
    local overrideDisabled = UsedPlusSettings and UsedPlusSettings:get("overrideRVBRepair") == false

    if repairDisabled or overrideDisabled then
        UsedPlus.logDebug("RVBWorkshopIntegration: Repair override disabled, calling original RVB callback")
        -- Call original RVB behavior
        if dialog.usedPlusOriginalRepairCallback then
            dialog.usedPlusOriginalRepairCallback()
        end
        return
    end

    local vehicle = dialog and dialog.vehicle
    if vehicle == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: No vehicle for repair")
        return
    end

    UsedPlus.logDebug(string.format("RVBWorkshopIntegration: RVB Repair clicked for %s", vehicle:getName()))

    -- Get RVB's calculated repair cost from the dialog if available
    local rvbRepairCost = nil
    if dialog.repairCost then
        rvbRepairCost = dialog.repairCost
        UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Using RVB repair cost: %d", rvbRepairCost))
    end

    -- Play click sound (use pcall for safety - API varies between versions)
    pcall(function()
        if g_gui and g_gui.playSample then
            g_gui:playSample(GuiSoundPlayer.SOUND_SAMPLES.CLICK)
        end
    end)

    -- Close RVB dialog first
    if dialog.close then
        dialog:close()
    elseif g_gui.closeDialog then
        g_gui:closeDialog()
    end

    -- Show our RepairDialog in REPAIR mode
    local farmId = g_currentMission:getFarmId()

    -- Use DialogLoader for centralized lazy loading
    if DialogLoader and DialogLoader.show then
        -- Pass RVB cost as optional 4th parameter
        DialogLoader.show("RepairDialog", "setVehicle", vehicle, farmId, RepairDialog.MODE_REPAIR, rvbRepairCost)
    else
        -- Fallback: direct dialog creation
        if VehicleSellingPointExtension and VehicleSellingPointExtension.showRepairDialog then
            VehicleSellingPointExtension.showRepairDialog(vehicle, RepairDialog.MODE_REPAIR)
        end
    end
end
