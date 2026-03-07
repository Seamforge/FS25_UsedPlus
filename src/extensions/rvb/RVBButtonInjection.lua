--[[
    RVBButtonInjection.lua
    Inject Repaint and Tires buttons into RVB's Workshop dialog

    Extracted from RVBWorkshopIntegration.lua for modularity
]]

-- Ensure RVBWorkshopIntegration table exists (modules load before coordinator)
RVBWorkshopIntegration = RVBWorkshopIntegration or {}

--[[
    Validate that an element reference is still in a parent's elements list
    Returns true if the element is live in the parent DOM, false if stale
]]
local function isElementStillInParent(element, parent)
    if element == nil or parent == nil or parent.elements == nil then
        return false
    end
    for _, child in ipairs(parent.elements) do
        if child == element then
            return true
        end
    end
    return false
end

--[[
    Inject a Repaint button into RVB's Workshop dialog
    Clones the Repair button and places it after Repair, before Back
]]
function RVBWorkshopIntegration:injectRepaintButton(dialog)
    UsedPlus.logDebug("RVBWorkshopIntegration:injectRepaintButton called")

    -- v2.6.2: Don't inject repaint button if repair system is disabled
    if UsedPlusSettings and UsedPlusSettings:get("enableRepairSystem") == false then
        UsedPlus.logDebug("RVBWorkshopIntegration: Repair system disabled, not adding repaint button")
        return
    end

    if dialog == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: dialog is nil")
        return
    end

    -- Check if button reference exists
    if dialog.usedPlusRepaintButton then
        -- Validate button is still in the DOM (not stale from dialog close/reopen)
        if isElementStillInParent(dialog.usedPlusRepaintButton, dialog.buttonsBox) then
            self:updateRepaintButtonState(dialog)
            return
        end
        -- Stale reference — clear and fall through to re-inject
        UsedPlus.logDebug("RVBWorkshopIntegration: Repaint button reference is stale, re-injecting")
        dialog.usedPlusRepaintButton = nil
        dialog.usedPlusRepaintSeparator = nil
    end

    local buttonsBox = dialog.buttonsBox
    if buttonsBox == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: buttonsBox not found, listing dialog properties:")
        for k, v in pairs(dialog) do
            if type(v) == "table" then
                UsedPlus.logDebug(string.format("  dialog.%s = table", tostring(k)))
            end
        end
        return
    end

    UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Found buttonsBox with %d elements",
        buttonsBox.elements and #buttonsBox.elements or 0))

    -- Find the repair button to clone
    local repairButton = dialog.repairButton
    if repairButton == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: dialog.repairButton not found, searching buttonsBox.elements...")
        -- Try to find by iterating elements
        for i, element in ipairs(buttonsBox.elements or {}) do
            local elemId = element.id or element.name or "unknown"
            UsedPlus.logDebug(string.format("  buttonsBox.elements[%d]: id=%s, name=%s",
                i, tostring(element.id), tostring(element.name)))
            if element.id == "repairButton" or element.name == "repairButton" then
                repairButton = element
                UsedPlus.logDebug("RVBWorkshopIntegration: Found repairButton in elements!")
                break
            end
        end
    end

    if repairButton == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Could not find repair button to clone")
        return
    end

    UsedPlus.logDebug("RVBWorkshopIntegration: Found repairButton, attempting to clone...")

    -- Clone the repair button
    local success, repaintButton = pcall(function()
        return repairButton:clone(buttonsBox)
    end)

    if not success then
        UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Clone failed with error: %s", tostring(repaintButton)))
        return
    end

    if repaintButton == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Clone returned nil")
        return
    end

    UsedPlus.logDebug("RVBWorkshopIntegration: Successfully cloned button!")

    -- Configure the repaint button
    repaintButton.id = "usedPlusRepaintButton"
    repaintButton.name = "usedPlusRepaintButton"
    repaintButton:setText(g_i18n:getText("usedplus_button_repaint") or "Repaint")

    -- Set click callback
    repaintButton.onClickCallback = function()
        RVBWorkshopIntegration:onRepaintButtonClick(dialog)
    end

    -- Also try setting via target pattern (RVB uses this)
    repaintButton.target = RVBWorkshopIntegration
    repaintButton.onClickCallbackFunction = "onRepaintButtonClick"

    -- Store reference
    dialog.usedPlusRepaintButton = repaintButton

    -- Add a separator before the repaint button (for visual consistency)
    -- Find separator template from buttonsBox
    local separatorTemplate = nil
    for _, element in ipairs(buttonsBox.elements or {}) do
        if element.profile and string.find(element.profile, "Separator") then
            separatorTemplate = element
            break
        end
    end

    if separatorTemplate then
        local separator = separatorTemplate:clone(buttonsBox)
        if separator then
            dialog.usedPlusRepaintSeparator = separator
        end
    end

    -- Note: Final button reordering is done in injectTiresButton after all buttons added
    -- Order will be: ..., Repair, Repaint, Tires, Back

    -- Update button state based on vehicle
    self:updateRepaintButtonState(dialog)

    -- Refresh the layout
    if buttonsBox.invalidateLayout then
        buttonsBox:invalidateLayout()
    end

    UsedPlus.logInfo("RVBWorkshopIntegration: Added Repaint button to RVB Workshop dialog")
end

--[[
    Update the Repaint button state based on vehicle condition
]]
function RVBWorkshopIntegration:updateRepaintButtonState(dialog)
    local repaintButton = dialog.usedPlusRepaintButton
    if repaintButton == nil then
        return
    end

    local vehicle = dialog.vehicle
    if vehicle == nil then
        if repaintButton.setDisabled then
            repaintButton:setDisabled(true)
        end
        return
    end

    -- Get wear amount
    local wear = 0
    if vehicle.getWearTotalAmount then
        wear = vehicle:getWearTotalAmount() or 0
    end

    -- Calculate repaint cost (similar to RepairDialog logic)
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    -- Use empty config table to get base store price (not depreciated vehicle price)
    local basePrice = storeItem and (StoreItemUtil.getDefaultPrice(storeItem, {}) or storeItem.price or 10000) or 10000

    local repaintCost = 0
    if Wearable and Wearable.calculateRepaintPrice then
        repaintCost = Wearable.calculateRepaintPrice(basePrice, wear) or 0
    else
        repaintCost = math.floor(basePrice * wear * 0.15)
    end

    -- Apply settings multiplier
    local paintMultiplier = UsedPlusSettings and UsedPlusSettings:get("paintCostMultiplier") or 1.0
    repaintCost = math.floor(repaintCost * paintMultiplier)

    -- Update button text with cost
    local buttonText = g_i18n:getText("usedplus_button_repaint") or "Repaint"
    if repaintCost > 0 then
        buttonText = string.format("%s (%s)", buttonText, g_i18n:formatMoney(repaintCost, 0, true, true))
    end
    repaintButton:setText(buttonText)

    -- Disable if no wear to fix
    local hasWear = wear > 0.01
    if repaintButton.setDisabled then
        repaintButton:setDisabled(not hasWear)
    end
end

--[[
    Handle Repaint button click
    Shows our RepairDialog in MODE_REPAINT
]]
function RVBWorkshopIntegration:onRepaintButtonClick(dialog)
    -- v2.6.2: Check master repair system toggle
    if UsedPlusSettings and UsedPlusSettings:get("enableRepairSystem") == false then
        UsedPlus.logDebug("RVBWorkshopIntegration: Repair system disabled, repaint button should not be shown")
        return
    end

    local vehicle = dialog and dialog.vehicle
    if vehicle == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: No vehicle for repaint")
        return
    end

    UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Repaint clicked for %s", vehicle:getName()))

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

    -- Show our RepairDialog in REPAINT mode
    local farmId = g_currentMission:getFarmId()

    -- Use DialogLoader for centralized lazy loading
    if DialogLoader and DialogLoader.show then
        DialogLoader.show("RepairDialog", "setVehicle", vehicle, farmId, RepairDialog.MODE_REPAINT)
    else
        -- Fallback: direct dialog creation
        if VehicleSellingPointExtension and VehicleSellingPointExtension.showRepairDialog then
            VehicleSellingPointExtension.showRepairDialog(vehicle, RepairDialog.MODE_REPAINT)
        end
    end
end

--[[
    Inject a Tires button into RVB's Workshop dialog
    Clones the Repair button and places it after Repaint
]]
function RVBWorkshopIntegration:injectTiresButton(dialog)
    UsedPlus.logDebug("RVBWorkshopIntegration:injectTiresButton called")

    if dialog == nil then
        return
    end

    -- Check if button reference exists
    if dialog.usedPlusTiresButton then
        -- Validate button is still in the DOM
        if isElementStillInParent(dialog.usedPlusTiresButton, dialog.buttonsBox) then
            self:updateTiresButtonState(dialog)
            return
        end
        -- Stale reference — clear and fall through to re-inject
        UsedPlus.logDebug("RVBWorkshopIntegration: Tires button reference is stale, re-injecting")
        dialog.usedPlusTiresButton = nil
    end

    local buttonsBox = dialog.buttonsBox
    if buttonsBox == nil then
        return
    end

    -- Find the repair button to clone (or use repaint if it exists)
    local sourceButton = dialog.usedPlusRepaintButton or dialog.repairButton
    if sourceButton == nil then
        -- Try to find by iterating elements
        for _, element in ipairs(buttonsBox.elements or {}) do
            if element.id == "repairButton" or element.name == "repairButton" then
                sourceButton = element
                break
            end
        end
    end

    if sourceButton == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Could not find button to clone for Tires")
        return
    end

    -- Clone the button
    local success, tiresButton = pcall(function()
        return sourceButton:clone(buttonsBox)
    end)

    if not success or tiresButton == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Failed to clone button for Tires")
        return
    end

    -- Configure the tires button
    tiresButton.id = "usedPlusTiresButton"
    tiresButton.name = "usedPlusTiresButton"
    tiresButton:setText(g_i18n:getText("usedplus_button_tires") or "Tires")

    -- Set keybind (T key)
    tiresButton.inputActionName = "USEDPLUS_TIRES"

    -- Set click callback
    tiresButton.onClickCallback = function()
        RVBWorkshopIntegration:onTiresButtonClick(dialog)
    end

    -- Store reference
    dialog.usedPlusTiresButton = tiresButton

    -- Update button state based on vehicle
    self:updateTiresButtonState(dialog)

    -- Reorder buttons to achieve: ..., Repair, Back, Tires, Repaint
    -- User wants Back FIRST, then Tires, then Repaint
    self:reorderUsedPlusButtons(dialog)

    -- Refresh the layout
    if buttonsBox.invalidateLayout then
        buttonsBox:invalidateLayout()
    end

    UsedPlus.logInfo("RVBWorkshopIntegration: Added Tires button to RVB Workshop dialog")
end

--[[
    Reorder UsedPlus buttons to achieve order: ..., Repair, Repaint, Tires, Back
    Called after both Repaint and Tires buttons are added
]]
function RVBWorkshopIntegration:reorderUsedPlusButtons(dialog)
    local buttonsBox = dialog.buttonsBox
    if buttonsBox == nil or buttonsBox.elements == nil then
        return
    end

    local tiresButton = dialog.usedPlusTiresButton
    local repaintButton = dialog.usedPlusRepaintButton
    local backButton = dialog.okButton  -- Back button has id="okButton" in RVB

    -- Find Back button if not found via dialog.okButton
    if backButton == nil then
        for _, element in ipairs(buttonsBox.elements) do
            if element.id == "okButton" or
               (element.getText and element:getText() == g_i18n:getText("button_back")) then
                backButton = element
                break
            end
        end
    end

    if backButton == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Could not find Back button for reordering")
        return
    end

    -- Remove our buttons and Back from the list (we'll re-add in correct order)
    local elementsToRemove = {tiresButton, repaintButton, backButton}
    for _, btn in ipairs(elementsToRemove) do
        if btn then
            for i = #buttonsBox.elements, 1, -1 do
                if buttonsBox.elements[i] == btn then
                    table.remove(buttonsBox.elements, i)
                    break
                end
            end
        end
    end

    -- Re-add in desired order: Repaint, Tires, Back (Back stays at end)
    if repaintButton then
        table.insert(buttonsBox.elements, repaintButton)
    end
    if tiresButton then
        table.insert(buttonsBox.elements, tiresButton)
    end
    if backButton then
        table.insert(buttonsBox.elements, backButton)
    end

    UsedPlus.logDebug("RVBWorkshopIntegration: Reordered buttons to Repaint, Tires, Back")
end

--[[
    Update the Tires button state based on vehicle tire condition
]]
function RVBWorkshopIntegration:updateTiresButtonState(dialog)
    local tiresButton = dialog.usedPlusTiresButton
    if tiresButton == nil then
        return
    end

    local vehicle = dialog.vehicle
    if vehicle == nil then
        if tiresButton.setDisabled then
            tiresButton:setDisabled(true)
        end
        return
    end

    -- Check if vehicle has tires that can be serviced
    local hasTires = vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels ~= nil
    if tiresButton.setDisabled then
        tiresButton:setDisabled(not hasTires)
    end
end

--[[
    Handle Tires button click
    Shows our TiresDialog
]]
function RVBWorkshopIntegration:onTiresButtonClick(dialog)
    local vehicle = dialog and dialog.vehicle
    if vehicle == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: No vehicle for tires service")
        return
    end

    UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Tires clicked for %s", vehicle:getName()))

    -- Play click sound (safely)
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

    -- Show our TiresDialog
    local farmId = g_currentMission:getFarmId()

    if DialogLoader and DialogLoader.show then
        DialogLoader.show("TiresDialog", "setVehicle", vehicle, farmId)
    end
end
