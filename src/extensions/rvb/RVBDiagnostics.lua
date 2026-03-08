--[[
    RVBDiagnostics.lua
    Inject UsedPlus data and hydraulic diagnostics into RVB's Workshop dialog

    Extracted from RVBWorkshopIntegration.lua for modularity
    v2.5.2: Hydraulic injection via data source wrapper or clone approach
]]

-- Ensure RVBWorkshopIntegration table exists (modules load before coordinator)
RVBWorkshopIntegration = RVBWorkshopIntegration or {}

--[[
    Inject UsedPlus data into RVB's settingsBox
    Called after RVB populates their vehicle info
]]
function RVBWorkshopIntegration:injectUsedPlusData(dialog)
    if dialog == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration:injectUsedPlusData - dialog is nil")
        return
    end

    local vehicle = dialog.vehicle
    if vehicle == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration:injectUsedPlusData - vehicle is nil")
        return
    end

    local settingsBox = dialog.settingsBox
    local templateRow = dialog.templateVehicleInfo

    if settingsBox == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Missing settingsBox")
        return
    end

    if templateRow == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Missing templateVehicleInfo")
        return
    end

    -- Check if our rows are still in settingsBox (RVB rebuilds it each updateScreen)
    if dialog.usedPlusDividerRow then
        for _, el in ipairs(settingsBox.elements or {}) do
            if el == dialog.usedPlusDividerRow then
                return  -- Our rows persist, no need to re-inject
            end
        end
        dialog.usedPlusDividerRow = nil
    end

    -- Get UsedPlus maintenance data
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Vehicle has no UsedPlusMaintenance spec")
        return
    end

    -- v2.5.2: Inject Hydraulic System into diagnostics panel (right side)
    -- This displays it like an RVB part with status bar
    local hydraulicOnRightSide = self:injectHydraulicDiagnosticV2(dialog, vehicle, spec)

    -- Prepare our data rows (left side - maintenance grade, history, etc.)
    -- If hydraulic injection to right side failed, include it on left side as fallback
    local usedPlusData = self:collectUsedPlusData(vehicle, spec, not hydraulicOnRightSide)

    if #usedPlusData == 0 then
        UsedPlus.logDebug("RVBWorkshopIntegration: No UsedPlus data to inject")
        return
    end

    -- Get alternating color state from existing rows
    local rowCount = #settingsBox.elements
    local alternating = (rowCount % 2 == 0)

    -- Check if AISettingsDialog color exists
    local colorTable = AISettingsDialog and AISettingsDialog.COLOR_ALTERNATING
    if colorTable == nil then
        -- Fallback colors if AISettingsDialog not available
        colorTable = {
            [true] = {0.03, 0.03, 0.03, 1},
            [false] = {0.05, 0.05, 0.05, 1}
        }
    end

    -- Add a subtle header/divider row
    local dividerRow = templateRow:clone(settingsBox)
    if dividerRow then
        dialog.usedPlusDividerRow = dividerRow
        dividerRow:setVisible(true)
        local divColor = colorTable[alternating]
        if divColor then
            dividerRow:setImageColor(nil, unpack(divColor))
        end
        local divLabel = dividerRow:getDescendantByName("label")
        local divValue = dividerRow:getDescendantByName("value")
        if divLabel then
            divLabel:setText(g_i18n:getText("usedplus_rvb_sectionHeader"))
            -- Make it slightly dimmer to look like a section header
            if divLabel.setTextColor then
                divLabel:setTextColor(0.6, 0.7, 0.8, 1)
            end
        end
        if divValue then
            divValue:setText("")
        end
        alternating = not alternating
    end

    -- Add our data rows
    for _, dataRow in ipairs(usedPlusData) do
        local element = templateRow:clone(settingsBox)
        if element then
            element:setVisible(true)
            local color = colorTable[alternating]
            if color then
                element:setImageColor(nil, unpack(color))
            end

            local label = element:getDescendantByName("label")
            local value = element:getDescendantByName("value")

            if label then
                label:setText(tostring(dataRow[1]))
            end
            if value then
                value:setText(tostring(dataRow[2]))
                -- Color code the value based on type
                if dataRow[3] and value.setTextColor then
                    value:setTextColor(unpack(dataRow[3]))
                end
            end

            alternating = not alternating
        end
    end

    -- Add Mechanic's Assessment as full-width centered section
    local assessmentRefs = self:injectMechanicAssessment(dialog, settingsBox, templateRow, colorTable, alternating)

    -- Refresh the layout
    if settingsBox.invalidateLayout then
        settingsBox:invalidateLayout()
    end

    -- Post-layout: expand assessment labels to full width
    -- MUST be after invalidateLayout() to prevent layout manager from overriding sizes
    if assessmentRefs then
        self:applyFullWidthSizing(assessmentRefs, settingsBox)
    end

    UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Injected %d UsedPlus rows for %s",
        #usedPlusData, vehicle:getName()))
end

--[[
    v2.5.2: Inject Hydraulic System into RVB's diagnostics panel (right side)

    APPROACH: Instead of cloning elements directly into SmoothList (which corrupts
    internal state), we inject our data into RVB's parts table BEFORE they populate
    the list. Then RVB creates our row with proper internal state management.

    This is called from our hooked updateScreen, but we need to inject BEFORE
    RVB builds the list. So we use a two-phase approach:
    1. Inject fake hydraulic part data into spec_faultData.parts
    2. Mark it for cleanup after RVB processes it
]]
function RVBWorkshopIntegration:injectHydraulicDiagnosticV2(dialog, vehicle, spec)
    -- Method hooks installed? Hydraulics will appear on right side.
    return dialog.usedPlusMethodsHooked == true
end

--[[
    Hook the dialog's own dataSource methods to add a hydraulic row.

    CRITICAL: RVB sets `self` (the dialog) as the dataSource. Previous approach
    wrapped with a new object, which replaced `self` in delegate methods — breaking
    `self.partBreakdowns`, `self.vehicle`, etc. and corrupting toggles.

    This approach modifies the dialog's OWN methods directly. `self` remains the
    dialog throughout, so all RVB internal state access works correctly.
    Hydraulic item is appended at the END so RVB part indices stay unchanged.
]]
function RVBWorkshopIntegration:hookDiagnosticsMethods(dialog)
    if dialog == nil then
        return
    end

    -- Only hook once per dialog instance
    if dialog.usedPlusMethodsHooked then
        return
    end

    -- Capture originals from metatable (class methods)
    local origGetCount = dialog.getNumberOfItemsInSection
    local origPopulate = dialog.populateCellForItemInSection

    if origGetCount == nil or origPopulate == nil then
        UsedPlus.logWarn("RVBWorkshopIntegration: Could not find dataSource methods to hook")
        return
    end

    -- Resolve DIAGNOSTICS mode value — try multiple sources since the global may be nil
    local DIAGNOSTICS_MODE = nil

    -- Method 1: rvbWorkshopDialog global (may be nil in our mod's scope)
    if rvbWorkshopDialog and rvbWorkshopDialog.MODE then
        DIAGNOSTICS_MODE = rvbWorkshopDialog.MODE.DIAGNOSTICS
    end

    -- Method 2: Instance's own MODE (resolved via metatable chain)
    if DIAGNOSTICS_MODE == nil and dialog.MODE then
        DIAGNOSTICS_MODE = dialog.MODE.DIAGNOSTICS
    end

    -- Method 3: Walk metatable chain manually
    if DIAGNOSTICS_MODE == nil then
        local mt = getmetatable(dialog)
        while mt do
            local idx = mt.__index
            if type(idx) == "table" then
                if idx.MODE and idx.MODE.DIAGNOSTICS then
                    DIAGNOSTICS_MODE = idx.MODE.DIAGNOSTICS
                    break
                end
                mt = getmetatable(idx)
            else
                break
            end
        end
    end

    -- Method 4: Infer from dialog's current selectedMode (RVB starts in DIAGNOSTICS)
    if DIAGNOSTICS_MODE == nil then
        if dialog.selectedMode ~= nil and dialog.selectedMode ~= 0 then
            DIAGNOSTICS_MODE = dialog.selectedMode
        end
    end

    -- Method 5: _G global lookup
    if DIAGNOSTICS_MODE == nil and _G and _G.rvbWorkshopDialog and _G.rvbWorkshopDialog.MODE then
        DIAGNOSTICS_MODE = _G.rvbWorkshopDialog.MODE.DIAGNOSTICS
    end

    if DIAGNOSTICS_MODE == nil then
        UsedPlus.logWarn("RVBWorkshopIntegration: Could not resolve DIAGNOSTICS mode value")
        return
    end

    -- Override getNumberOfItemsInSection: +1 for hydraulics in diagnostics mode
    -- Check if our entry is already in partBreakdowns (appended by updateScreen hook)
    dialog.getNumberOfItemsInSection = function(self, list, section)
        local count = origGetCount(self, list, section)
        if self.selectedMode == DIAGNOSTICS_MODE then
            -- Only add +1 if our entry isn't already in partBreakdowns
            local lastEntry = self.partBreakdowns and self.partBreakdowns[#self.partBreakdowns]
            if not lastEntry or lastEntry.name ~= "USEDPLUS_HYDRAULIC" then
                return count + 1
            end
        end
        return count
    end

    -- Override populateCellForItemInSection: handle our hydraulic item
    dialog.populateCellForItemInSection = function(self, list, section, index, cell)
        if self.selectedMode == DIAGNOSTICS_MODE then
            -- Check if this index is our hydraulic entry (by name or by overflow)
            local partEntry = self.partBreakdowns and self.partBreakdowns[index]
            local isOurs = (partEntry and partEntry.name == "USEDPLUS_HYDRAULIC")
                or (not partEntry)  -- index beyond partBreakdowns = our extra item
            if isOurs then
                -- Our hydraulic item — read live value from vehicle
                local hydraulicRel = 1.0
                if self.vehicle and self.vehicle.spec_usedPlusMaintenance then
                    hydraulicRel = self.vehicle.spec_usedPlusMaintenance.hydraulicReliability or 1.0
                end
                RVBWorkshopIntegration:populateHydraulicCell(cell, hydraulicRel, self)
                -- After populating (including on list reload after toggle), update price
                RVBWorkshopIntegration:adjustRepairButtonPrice(self)
                return
            end
        end
        -- All other items: call original (self IS the dialog, indices unchanged)
        origPopulate(self, list, section, index, cell)
    end

    -- Initialize toggle state
    RVBWorkshopIntegration.hydraulicRepairRequested = false

    dialog.usedPlusMethodsHooked = true
    UsedPlus.logInfo("RVBWorkshopIntegration: Diagnostics methods hooked successfully")
end

--[[
    Inject a fake "USEDPLUS_HYDRAULIC" entry into partBreakdowns.
    This allows RVB's native onClickPart to handle our toggle — no hooking needed.
    Called from the updateScreen hook after RVB rebuilds partBreakdowns.
]]
function RVBWorkshopIntegration:injectHydraulicPartEntry(dialog)
    if dialog == nil or dialog.partBreakdowns == nil then
        return
    end

    -- Check if already appended (RVB rebuilds partBreakdowns each updateScreen)
    local lastEntry = dialog.partBreakdowns[#dialog.partBreakdowns]
    if lastEntry and lastEntry.name == "USEDPLUS_HYDRAULIC" then
        return  -- Already appended
    end

    -- Append our entry — RVB's onClickPart will find it at this index
    table.insert(dialog.partBreakdowns, {name = "USEDPLUS_HYDRAULIC"})

    -- Ensure the vehicle has a fake part entry so setPartsRepairreq doesn't crash
    if dialog.vehicle and dialog.vehicle.spec_faultData and dialog.vehicle.spec_faultData.parts then
        local parts = dialog.vehicle.spec_faultData.parts
        if parts["USEDPLUS_HYDRAULIC"] == nil then
            parts["USEDPLUS_HYDRAULIC"] = {
                repairreq = RVBWorkshopIntegration.hydraulicRepairRequested or false,
                fault = "empty",
                condition = 100
            }
        end
    end
end

--[[
    Hook setPartsRepairreq on the vehicle to intercept our fake hydraulic part.
    When RVB's onClickPart calls vehicle:setPartsRepairreq("USEDPLUS_HYDRAULIC", state),
    we handle it ourselves instead of letting RVB process it (which would crash/send bad events).
]]
function RVBWorkshopIntegration:hookSetPartsRepairreq(dialog)
    if dialog == nil or dialog.vehicle == nil then
        return
    end

    local vehicle = dialog.vehicle
    if vehicle.usedPlusSetPartsHooked then
        return
    end

    local origSetParts = vehicle.setPartsRepairreq
    if origSetParts == nil then
        return
    end

    vehicle.setPartsRepairreq = function(self, part, state)
        if part == "USEDPLUS_HYDRAULIC" then
            -- Handle our fake part — update toggle state, skip RVB event
            RVBWorkshopIntegration.hydraulicRepairRequested = state
            UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Hydraulic toggle set to %s", tostring(state)))
            -- Update the fake part entry directly (no network event)
            if self.spec_faultData and self.spec_faultData.parts and self.spec_faultData.parts["USEDPLUS_HYDRAULIC"] then
                self.spec_faultData.parts["USEDPLUS_HYDRAULIC"].repairreq = state
            end
            return
        end
        -- All other parts: call original RVB handler
        origSetParts(self, part, state)
    end

    -- Also hook getRepairPrice_RVBClone to include hydraulic cost.
    -- RVB's onClickRepair bails if getRepairPrice_RVBClone(true) <= 100.
    -- Without this, the Repair button does nothing when only hydraulics need repair.
    local origGetRepairPrice = vehicle.getRepairPrice_RVBClone
    if origGetRepairPrice then
        vehicle.getRepairPrice_RVBClone = function(self, ...)
            local basePrice = origGetRepairPrice(self, ...)
            if RVBWorkshopIntegration.hydraulicRepairRequested then
                local hydCost = RVBWorkshopIntegration:calculateHydraulicRepairCost(self)
                return (basePrice or 0) + (hydCost or 0)
            end
            return basePrice
        end
    end

    vehicle.usedPlusSetPartsHooked = true
    UsedPlus.logDebug("RVBWorkshopIntegration: hookSetPartsRepairreq hooked on vehicle")
end

--[[
    Calculate the cost to repair hydraulics for a vehicle.
    Uses a formula compatible with RVB's pricing:
      vehiclePrice × costFraction × damageFraction + labor
]]
function RVBWorkshopIntegration:calculateHydraulicRepairCost(vehicle)
    if vehicle == nil then
        return 0
    end

    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then
        return 0
    end

    local hydraulicReliability = spec.hydraulicReliability or 1.0
    if hydraulicReliability >= 0.99 then
        return 0
    end

    local damage = 1.0 - hydraulicReliability

    -- Get vehicle base price
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local basePrice = storeItem and (StoreItemUtil.getDefaultPrice(storeItem, {}) or storeItem.price or 10000) or 10000

    -- Hydraulic systems are high-pressure precision components — pumps, cylinders,
    -- seals, hoses, and specialized fluid. Real-world cost runs 3-8% of vehicle value.
    -- Gamified at 3.5% parts + $800 labor (significant but not crippling).
    -- Examples at full damage: $50K tractor → ~$2,550 | $200K → ~$7,800 | $500K → ~$18,300
    local partCost = basePrice * 0.035 * damage
    local laborCost = 800 * damage
    local repairMultiplier = UsedPlusSettings and UsedPlusSettings:get("repairCostMultiplier") or 1.0

    return math.floor((partCost + laborCost) * repairMultiplier)
end

--[[
    Adjust the repair button price to include hydraulic repair cost.
    Called directly after updateButtons() runs — no hooking needed.
    Works from both our onClickPart handler and the updateScreen hook.
]]
function RVBWorkshopIntegration:adjustRepairButtonPrice(dialog)
    if dialog == nil or dialog.vehicle == nil or dialog.repairButton == nil then
        return
    end

    if self.hydraulicRepairRequested then
        local hydraulicCost = self:calculateHydraulicRepairCost(dialog.vehicle)
        if hydraulicCost > 0 then
            -- getRepairPrice_RVBClone is hooked to include hydraulic cost,
            -- so totalPrice already includes both RVB + hydraulic
            local totalPrice = 0
            if dialog.vehicle.getRepairPrice_RVBClone then
                totalPrice = dialog.vehicle:getRepairPrice_RVBClone() or 0
            end

            -- Update button text with combined price
            dialog.repairButton:setText(string.format("%s (%s)",
                g_i18n:getText("button_repair"),
                g_i18n:formatMoney(totalPrice, 0, true, true)))

            -- Enable the button — hydraulic repair is meaningful even if no RVB parts need repair
            local rvb = dialog.vehicle.spec_faultData
            local activeWork = false
            if rvb then
                activeWork = (rvb.repair and rvb.repair.state and rvb.repair.state ~= 0)
                    or (rvb.inspection and rvb.inspection.active)
                    or (rvb.service and rvb.service.active)
            end
            if not activeWork then
                dialog.repairButton:setDisabled(false)
            end

            -- Store the cost for the repair completion handler
            self.lastHydraulicRepairCost = hydraulicCost
        end
    else
        self.lastHydraulicRepairCost = 0
    end
end

--[[
    Populate a diagnostics row cell with hydraulic data
]]
function RVBWorkshopIntegration:populateHydraulicCell(cell, hydraulicReliability, dialog)
    -- Get effective ceiling (min of overall ceiling and component durability)
    local effectiveCeiling = 1.0
    if dialog and dialog.vehicle and dialog.vehicle.spec_usedPlusMaintenance then
        local spec = dialog.vehicle.spec_usedPlusMaintenance
        effectiveCeiling = math.min(spec.maxReliabilityCeiling or 1.0, spec.maxHydraulicDurability or 1.0)
    end

    -- Text percentage = fraction of ceiling (100% = fully repaired to current max)
    -- Bar fill = fraction of 1.0 (visual gap shows ceiling degradation)
    local ceilingPct = 0
    if effectiveCeiling > 0.001 then
        ceilingPct = math.min(100, math.floor((hydraulicReliability / effectiveCeiling) * 100))
    end
    local barFill = math.min(hydraulicReliability, 1.0)

    -- Determine condition text and color based on RAW reliability (not ceiling-relative)
    local rawPct = math.floor(hydraulicReliability * 100)
    local conditionText = "Unknown"
    local conditionColor = {1, 1, 1, 1}

    if rawPct >= 80 then
        conditionText = g_i18n:getText("usedplus_condition_good") or "Good"
        conditionColor = {0.3, 1.0, 0.4, 1}
    elseif rawPct >= 60 then
        conditionText = g_i18n:getText("usedplus_condition_fair") or "Fair"
        conditionColor = {1.0, 0.85, 0.2, 1}
    elseif rawPct >= 40 then
        conditionText = g_i18n:getText("usedplus_condition_poor") or "Poor"
        conditionColor = {1.0, 0.6, 0.2, 1}
    else
        conditionText = g_i18n:getText("usedplus_condition_critical") or "Critical"
        conditionColor = {1.0, 0.4, 0.4, 1}
    end

    cell:setVisible(true)

    -- Part name
    local partName = cell:getDescendantByName("partName")
    if partName then
        partName:setText(g_i18n:getText("usedplus_hydraulic_system") or "HYDRAULIC SYSTEM")
    end

    -- Percentage — shows fraction of ceiling (100% = at max possible)
    local partPercent = cell:getDescendantByName("partPercent")
    if partPercent then
        partPercent:setText(string.format("%d%%", ceilingPct))
        if partPercent.setTextColor then
            partPercent:setTextColor(unpack(conditionColor))
        end
    end

    -- Condition text
    local partCondition = cell:getDescendantByName("partCondition")
    if partCondition then
        partCondition:setText(conditionText)
        if partCondition.setTextColor then
            partCondition:setTextColor(unpack(conditionColor))
        end
    end

    -- Status bar — fills as fraction of 1.0 (visual gap = ceiling degradation)
    local partBar = cell:getDescendantByName("partBar")
    if partBar then
        if partBar.setSize and partBar.parent and partBar.parent.size then
            local fullWidth = partBar.parent.size[1] - (partBar.margin and partBar.margin[1] or 0) * 2
            local minSize = 0
            if partBar.startSize and partBar.endSize then
                minSize = partBar.startSize[1] + partBar.endSize[1]
            end
            local fillWidth = fullWidth * barFill
            partBar:setSize(math.max(minSize, fillWidth), nil)
        end
        if partBar.setImageColor then
            partBar:setImageColor(nil, unpack(conditionColor))
        end
    end

    -- Show toggle — enabled when hydraulic reliability is below ceiling
    local checkPart = cell:getDescendantByName("checkPart")
    if checkPart then
        checkPart:setVisible(true)
        local canToggle = hydraulicReliability < (effectiveCeiling - 0.01)
        checkPart:setDisabled(not canToggle)
        checkPart:setIsChecked(RVBWorkshopIntegration.hydraulicRepairRequested == true)
    end
end

--[[
    Collect UsedPlus data for display on LEFT SIDE (settingsBox)
    Returns array of {label, value, [color]} tuples

    NOTE: We tried moving Hydraulics to RVB's diagnosticsList (right side) but
    SmoothList's internal state gets corrupted, causing mouseEvent errors.
    Hydraulics stays on the left side with other UsedPlus data.
]]
function RVBWorkshopIntegration:collectUsedPlusData(vehicle, spec, includeHydraulic)
    local data = {}

    -- Color constants (R, G, B, A)
    local COLOR_GREEN = {0.3, 1.0, 0.4, 1}
    local COLOR_YELLOW = {1.0, 0.85, 0.2, 1}
    local COLOR_ORANGE = {1.0, 0.6, 0.2, 1}
    local COLOR_RED = {1.0, 0.4, 0.4, 1}

    -- Helper: get color based on percentage
    local function getConditionColor(pct)
        if pct >= 80 then return COLOR_GREEN
        elseif pct >= 60 then return COLOR_YELLOW
        elseif pct >= 40 then return COLOR_ORANGE
        else return COLOR_RED end
    end

    -- Get hydraulic reliability for grade calculation
    local hydraulicReliability = spec.hydraulicReliability or 1.0

    -- Hydraulic System - unique to UsedPlus, RVB doesn't track this
    if includeHydraulic then
        local hydraulicPct = math.floor(hydraulicReliability * 100)
        table.insert(data, {
            g_i18n:getText("usedplus_hydraulic_system") or "Hydraulic System",
            string.format("%d%%", hydraulicPct),
            getConditionColor(hydraulicPct)
        })
    end

    -- 1. Maintenance Grade (our overall assessment)
    local grade = "Unknown"
    local gradeColor = COLOR_YELLOW

    -- Calculate overall reliability
    local engineRel = spec.engineReliability or 1.0
    local elecRel = spec.electricalReliability or 1.0
    local avgReliability = (hydraulicReliability + engineRel + elecRel) / 3

    if avgReliability >= 0.9 then
        grade = g_i18n:getText("usedplus_grade_excellent") or "Excellent"
        gradeColor = COLOR_GREEN
    elseif avgReliability >= 0.75 then
        grade = g_i18n:getText("usedplus_grade_good") or "Good"
        gradeColor = COLOR_GREEN
    elseif avgReliability >= 0.5 then
        grade = g_i18n:getText("usedplus_grade_fair") or "Fair"
        gradeColor = COLOR_YELLOW
    elseif avgReliability >= 0.3 then
        grade = g_i18n:getText("usedplus_grade_poor") or "Poor"
        gradeColor = COLOR_ORANGE
    else
        grade = g_i18n:getText("usedplus_grade_critical") or "Critical"
        gradeColor = COLOR_RED
    end

    table.insert(data, {
        g_i18n:getText("usedplus_maintenance_grade") or "Maintenance",
        grade,
        gradeColor
    })

    -- 3. Service History (if there's notable history)
    local failureCount = spec.failureCount or 0
    local repairCount = spec.repairCount or 0

    if failureCount > 0 or repairCount > 0 then
        local historyText = string.format("%d repairs, %d breakdowns", repairCount, failureCount)
        local historyColor = COLOR_YELLOW
        if failureCount > 3 then
            historyColor = COLOR_ORANGE
        elseif failureCount == 0 and repairCount > 0 then
            historyColor = COLOR_GREEN
        end

        table.insert(data, {
            g_i18n:getText("usedplus_service_history") or "History",
            historyText,
            historyColor
        })
    end

    -- NOTE: Mechanic's Assessment is now handled separately in injectUsedPlusData()
    -- to allow for special centered display formatting

    return data
end

--[[
    Fallback quote generation if main quote system unavailable
    Uses workhorseLemonScale (the vehicle's hidden DNA)
]]
function RVBWorkshopIntegration:generateFallbackQuote(workhorseLemonScale)
    if workhorseLemonScale >= 0.9 then
        return "Exceptional build quality"
    elseif workhorseLemonScale >= 0.7 then
        return "Solid machine"
    elseif workhorseLemonScale >= 0.5 then
        return "Average, nothing special"
    elseif workhorseLemonScale >= 0.3 then
        return "Shows some quirks"
    else
        return "Keep your mechanic's number handy"
    end
end

--[[
    Convert a cloned label+value template row into a single full-width label.
    Removes the value element so the label can expand, then sizes the label
    using parent.size[1] (declared size — always available, unlike getSize()
    which returns 0 on freshly cloned elements that haven't been laid out).
]]
function RVBWorkshopIntegration:makeFullWidthRow(row, label, value)
    -- Remove the value element entirely (not just hide it)
    if value then
        if row.removeElement then
            row:removeElement(value)
        else
            -- Manual fallback: remove from elements array
            if row.elements then
                for i = #row.elements, 1, -1 do
                    if row.elements[i] == value then
                        table.remove(row.elements, i)
                        break
                    end
                end
            end
            value.parent = nil
        end
    end

    -- Expand label to full container width using parent's DECLARED size
    -- (parent = settingsBox ScrollingLayout, .size[1] = declared width from XML)
    if label then
        local containerWidth = 0
        if row.parent and row.parent.size then
            containerWidth = row.parent.size[1] or 0
        end

        if containerWidth > 0 and label.setSize then
            label:setSize(containerWidth * 0.95, nil)
        end

        if label.setPosition then
            label:setPosition(0, nil)
        end
        if label.setTextAlignment then
            label:setTextAlignment(RenderText.ALIGN_CENTER)
        end
        if label.setTextTruncated then
            label:setTextTruncated(false)
        end
        label.textTruncated = false
    end
end

--[[
    Re-apply full-width sizing and truncation disable after invalidateLayout().
    Layout passes may reset element sizes/properties, so we re-enforce them.
    Uses settingsBox.size[1] (declared size) which is always available.
]]
function RVBWorkshopIntegration:applyFullWidthSizing(refs, settingsBox)
    if not refs then
        return
    end

    local containerWidth = 0
    if settingsBox and settingsBox.size then
        containerWidth = settingsBox.size[1] or 0
    end

    for _, label in ipairs(refs) do
        if label then
            if containerWidth > 0 and label.setSize then
                label:setSize(containerWidth * 0.95, nil)
            end
            if label.setTextTruncated then
                label:setTextTruncated(false)
            end
            label.textTruncated = false
        end
    end
end

--[[
    Inject Mechanic's Assessment into the settingsBox as full-width centered rows.
    Uses makeFullWidthRow() to remove the value child so the label gets full width.
    Returns array of label refs for post-layout truncation reset, or nil if nothing injected.

    Renders as:
      ─────────────────────────────   (full-width separator)
      MECHANIC'S ASSESSMENT           (full-width gold header)
      "quote text here"               (full-width colored quote)
]]
function RVBWorkshopIntegration:injectMechanicAssessment(dialog, settingsBox, templateRow, colorTable, alternating)
    local vehicle = dialog.vehicle
    if vehicle == nil then
        return nil
    end

    -- Only show assessment after RVB inspection is completed
    local rvb = vehicle.spec_faultData
    if rvb and rvb.inspection and not rvb.inspection.completed then
        return nil
    end

    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then
        return nil
    end

    -- Get workhorse/lemon scale and quote
    local workhorseLemonScale = spec.workhorseLemonScale or 0.5
    local mechanicQuote = nil

    -- Get the proper inspector quote based on workhorse/lemon DNA
    if UsedPlusMaintenance and UsedPlusMaintenance.getInspectorQuote then
        mechanicQuote = UsedPlusMaintenance.getInspectorQuote(workhorseLemonScale)
    end

    -- Fallback if quote system not available
    if mechanicQuote == nil or mechanicQuote == "" then
        mechanicQuote = self:generateFallbackQuote(workhorseLemonScale)
    end

    if mechanicQuote == nil or mechanicQuote == "" then
        return nil
    end

    -- Determine quote color based on workhorse/lemon scale
    local quoteColor = {0.85, 0.85, 0.7, 1}  -- Default warm beige
    if workhorseLemonScale >= 0.7 then
        quoteColor = {0.6, 0.95, 0.65, 1}  -- Greenish for workhorses
    elseif workhorseLemonScale <= 0.3 then
        quoteColor = {0.95, 0.6, 0.55, 1}  -- Reddish for lemons
    end

    local assessmentLabels = {}

    -- Row 0: Separator — full-width dashes
    local separatorRow = templateRow:clone(settingsBox)
    if separatorRow then
        separatorRow:setVisible(true)
        local color = colorTable[alternating]
        if color then
            separatorRow:setImageColor(nil, unpack(color))
        end
        local sepLabel = separatorRow:getDescendantByName("label")
        local sepValue = separatorRow:getDescendantByName("value")
        self:makeFullWidthRow(separatorRow, sepLabel, sepValue)
        if sepLabel then
            sepLabel:setText("------------------------------")
            if sepLabel.setTextColor then
                sepLabel:setTextColor(0.5, 0.5, 0.5, 1)
            end
            table.insert(assessmentLabels, sepLabel)
        end
        alternating = not alternating
    end

    -- Row 1: Header — full-width gold bold text
    local headerRow = templateRow:clone(settingsBox)
    if headerRow then
        headerRow:setVisible(true)
        local color = colorTable[alternating]
        if color then
            headerRow:setImageColor(nil, unpack(color))
        end
        local hdrLabel = headerRow:getDescendantByName("label")
        local hdrValue = headerRow:getDescendantByName("value")
        self:makeFullWidthRow(headerRow, hdrLabel, hdrValue)
        if hdrLabel then
            hdrLabel:setText(g_i18n:getText("usedplus_mechanic_assessment") or "MECHANIC'S ASSESSMENT")
            if hdrLabel.setTextColor then
                hdrLabel:setTextColor(0.9, 0.8, 0.5, 1)  -- Gold
            end
            if hdrLabel.setTextBold then
                hdrLabel:setTextBold(true)
            end
            table.insert(assessmentLabels, hdrLabel)
        end
        alternating = not alternating
    end

    -- Row 2: Quote — full-width colored quote text
    local quoteRow = templateRow:clone(settingsBox)
    if quoteRow then
        quoteRow:setVisible(true)
        local color = colorTable[alternating]
        if color then
            quoteRow:setImageColor(nil, unpack(color))
        end
        local qLabel = quoteRow:getDescendantByName("label")
        local qValue = quoteRow:getDescendantByName("value")
        self:makeFullWidthRow(quoteRow, qLabel, qValue)
        if qLabel then
            qLabel:setText(string.format('"%s"', mechanicQuote))
            if qLabel.setTextColor then
                qLabel:setTextColor(unpack(quoteColor))
            end
            table.insert(assessmentLabels, qLabel)
        end
    end

    UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Added Mechanic's Assessment for %s (scale=%.2f)",
        vehicle:getName(), workhorseLemonScale))

    return assessmentLabels
end
