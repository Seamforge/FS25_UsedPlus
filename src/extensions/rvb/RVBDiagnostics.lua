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
        dividerRow:setVisible(true)
        local divColor = colorTable[alternating]
        if divColor then
            dividerRow:setImageColor(nil, unpack(divColor))
        end
        local divLabel = dividerRow:getDescendantByName("label")
        local divValue = dividerRow:getDescendantByName("value")
        if divLabel then
            divLabel:setText("— UsedPlus —")
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

    -- Add Mechanic's Assessment as special centered section
    self:injectMechanicAssessment(dialog, settingsBox, templateRow, colorTable, alternating)

    -- Refresh the layout
    if settingsBox.invalidateLayout then
        settingsBox:invalidateLayout()
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
    if dialog == nil or vehicle == nil or spec == nil then
        return false
    end

    -- Only inject once per dialog update
    if dialog.usedPlusHydraulicInjected then
        return true
    end

    -- Get hydraulic data
    local hydraulicReliability = spec.hydraulicReliability or 1.0
    local hydraulicPct = math.floor(hydraulicReliability * 100)

    -- Try to find RVB's diagnosticsList and understand its structure
    local diagnosticsList = dialog.diagnosticsList
    if diagnosticsList == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: diagnosticsList not found")
        return false
    end

    -- Log list properties to understand structure
    UsedPlus.logDebug("RVBWorkshopIntegration: Analyzing diagnosticsList structure...")
    local numericProps = {}
    local functionProps = {}
    for k, v in pairs(diagnosticsList) do
        if type(v) == "number" then
            numericProps[k] = v
        elseif type(v) == "function" then
            table.insert(functionProps, k)
        end
    end

    -- Log numeric properties (likely include item counts)
    for k, v in pairs(numericProps) do
        UsedPlus.logDebug(string.format("  [number] %s = %d", k, v))
    end

    -- Log function names (looking for add/update methods)
    UsedPlus.logDebug("  [functions] " .. table.concat(functionProps, ", "))

    -- Check if list has a dataSource
    if diagnosticsList.dataSource then
        UsedPlus.logDebug("RVBWorkshopIntegration: List has dataSource - trying wrapper approach")
        return self:injectViaDataSource(dialog, diagnosticsList, hydraulicReliability)
    end

    -- Check if list has elements we can clone from
    if diagnosticsList.elements and #diagnosticsList.elements > 0 then
        UsedPlus.logDebug(string.format("RVBWorkshopIntegration: List has %d elements", #diagnosticsList.elements))
        return self:injectViaCloneWithStateUpdate(dialog, diagnosticsList, hydraulicReliability)
    end

    UsedPlus.logDebug("RVBWorkshopIntegration: No viable injection method found")
    return false
end

--[[
    Approach 1: Wrap the data source to include our hydraulic item
]]
function RVBWorkshopIntegration:injectViaDataSource(dialog, diagnosticsList, hydraulicReliability)
    local originalDataSource = diagnosticsList.dataSource

    -- Create wrapper that adds our item
    local wrapper = {}
    setmetatable(wrapper, {__index = originalDataSource})

    -- Override getNumberOfItemsInSection
    if originalDataSource.getNumberOfItemsInSection then
        wrapper.getNumberOfItemsInSection = function(self, list, section)
            local count = originalDataSource:getNumberOfItemsInSection(list, section)
            return count + 1
        end
    end

    -- Override populateCellForItemInSection
    if originalDataSource.populateCellForItemInSection then
        wrapper.populateCellForItemInSection = function(self, list, section, index, cell)
            local originalCount = originalDataSource:getNumberOfItemsInSection(list, section)

            if index > originalCount then
                -- This is our hydraulic item
                RVBWorkshopIntegration:populateHydraulicCell(cell, hydraulicReliability)
            else
                -- Original item
                originalDataSource:populateCellForItemInSection(list, section, index, cell)
            end
        end
    end

    -- Set wrapper and reload
    diagnosticsList:setDataSource(wrapper)
    if diagnosticsList.reloadData then
        diagnosticsList:reloadData()
    end

    dialog.usedPlusHydraulicInjected = true
    UsedPlus.logInfo("RVBWorkshopIntegration: Injected hydraulic via data source wrapper")
    return true
end

--[[
    Approach 2: Clone element and update internal state
]]
function RVBWorkshopIntegration:injectViaCloneWithStateUpdate(dialog, diagnosticsList, hydraulicReliability)
    local templateRow = diagnosticsList.elements[1]

    -- Remember state before
    local elementsBefore = #diagnosticsList.elements

    -- Clone the row
    local success, hydraulicRow = pcall(function()
        return templateRow:clone(diagnosticsList)
    end)

    if not success or hydraulicRow == nil then
        UsedPlus.logDebug("RVBWorkshopIntegration: Clone failed")
        return false
    end

    -- Populate the row
    self:populateHydraulicCell(hydraulicRow, hydraulicReliability)

    -- Update internal state - try multiple property names
    local stateUpdated = false
    local propsToUpdate = {
        "numItems", "itemCount", "totalItemCount", "numberOfItems",
        "listItemCount", "numSections", "totalDataCount"
    }

    for _, prop in ipairs(propsToUpdate) do
        if diagnosticsList[prop] ~= nil and type(diagnosticsList[prop]) == "number" then
            local oldVal = diagnosticsList[prop]
            diagnosticsList[prop] = oldVal + 1
            UsedPlus.logDebug(string.format("Updated %s: %d -> %d", prop, oldVal, oldVal + 1))
            stateUpdated = true
        end
    end

    -- Try calling update/refresh methods
    local methodsToTry = {
        "updateItemPositions", "buildItemList", "updateContentSize",
        "invalidateLayout", "updateAbsolutePosition", "layoutItems"
    }

    for _, method in ipairs(methodsToTry) do
        if diagnosticsList[method] and type(diagnosticsList[method]) == "function" then
            pcall(function()
                diagnosticsList[method](diagnosticsList)
                UsedPlus.logDebug(string.format("Called %s()", method))
            end)
        end
    end

    dialog.usedPlusHydraulicInjected = true

    local elementsAfter = #diagnosticsList.elements
    UsedPlus.logInfo(string.format(
        "RVBWorkshopIntegration: Injected hydraulic via clone (elements: %d -> %d, state updated: %s)",
        elementsBefore, elementsAfter, tostring(stateUpdated)))

    return true
end

--[[
    Populate a diagnostics row cell with hydraulic data
]]
function RVBWorkshopIntegration:populateHydraulicCell(cell, hydraulicReliability)
    local hydraulicPct = math.floor(hydraulicReliability * 100)

    -- Determine condition text and color
    local conditionText = "Unknown"
    local conditionColor = {1, 1, 1, 1}

    if hydraulicPct >= 80 then
        conditionText = g_i18n:getText("usedplus_condition_good") or "Good"
        conditionColor = {0.3, 1.0, 0.4, 1}
    elseif hydraulicPct >= 60 then
        conditionText = g_i18n:getText("usedplus_condition_fair") or "Fair"
        conditionColor = {1.0, 0.85, 0.2, 1}
    elseif hydraulicPct >= 40 then
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

    -- Percentage
    local partPercent = cell:getDescendantByName("partPercent")
    if partPercent then
        partPercent:setText(string.format("%d%%", hydraulicPct))
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

    -- Status bar
    local partBar = cell:getDescendantByName("partBar")
    if partBar then
        if partBar.setSize then
            local bgWidth = 176  -- From RVB profile
            local fillWidth = math.floor(bgWidth * hydraulicReliability)
            partBar:setSize(fillWidth, nil)
        end
        if partBar.setImageColor then
            partBar:setImageColor(nil, unpack(conditionColor))
        end
    end

    -- Hide repair toggle (we handle this separately)
    local checkPart = cell:getDescendantByName("checkPart")
    if checkPart then
        checkPart:setVisible(false)
    end

    -- Hide action row
    for _, child in ipairs(cell.elements or {}) do
        if child.profile and string.find(tostring(child.profile), "actionRow") then
            child:setVisible(false)
            break
        end
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
    Inject Mechanic's Assessment as a centered display section
    Creates a visually distinct area with header + quote
    Includes horizontal rule separator above
]]
function RVBWorkshopIntegration:injectMechanicAssessment(dialog, settingsBox, templateRow, colorTable, alternating)
    local vehicle = dialog.vehicle
    if vehicle == nil then
        return
    end

    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then
        return
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
        return
    end

    -- Determine quote color based on workhorse/lemon scale
    local quoteColor = {0.85, 0.85, 0.7, 1}  -- Default warm beige
    if workhorseLemonScale >= 0.7 then
        quoteColor = {0.6, 0.95, 0.65, 1}  -- Greenish for workhorses
    elseif workhorseLemonScale <= 0.3 then
        quoteColor = {0.95, 0.6, 0.55, 1}  -- Reddish for lemons
    end

    -- Row 0: Horizontal rule separator (centered, full width)
    local separatorRow = templateRow:clone(settingsBox)
    if separatorRow then
        separatorRow:setVisible(true)
        local color = colorTable[alternating]
        if color then
            separatorRow:setImageColor(nil, unpack(color))
        end

        local label = separatorRow:getDescendantByName("label")
        local value = separatorRow:getDescendantByName("value")

        if label then
            -- Expand label to full row width and center
            -- v2.8.0: Fix for cloned elements that may not have getSize method
            if separatorRow.getSize then
                local rowWidth, rowHeight = separatorRow:getSize()
                if rowWidth and rowWidth > 0 then
                    label:setSize(rowWidth * 0.95, nil)
                end
            end
            if label.setTextAlignment then
                label:setTextAlignment(RenderText.ALIGN_CENTER)
            end
            -- Create centered horizontal rule using ASCII dashes
            label:setText("─────────────────────────────")
            if label.setTextColor then
                label:setTextColor(0.5, 0.5, 0.5, 1)  -- Gray color for rule
            end
        end
        if value then
            value:setText("")
            value:setVisible(false)
        end

        alternating = not alternating
    end

    -- Row 1: Header "MECHANIC'S ASSESSMENT" - centered, full width
    local headerRow = templateRow:clone(settingsBox)
    if headerRow then
        headerRow:setVisible(true)
        local color = colorTable[alternating]
        if color then
            headerRow:setImageColor(nil, unpack(color))
        end

        local label = headerRow:getDescendantByName("label")
        local value = headerRow:getDescendantByName("value")

        if label then
            -- Expand label to full row width and center text
            -- v2.8.0: Fix for cloned elements that may not have getSize method
            if headerRow.getSize then
                local rowWidth, rowHeight = headerRow:getSize()
                if rowWidth and rowWidth > 0 then
                    label:setSize(rowWidth * 0.95, nil)  -- 95% of row width
                end
            end
            if label.setTextAlignment then
                label:setTextAlignment(RenderText.ALIGN_CENTER)
            end
            -- Disable text truncation (ellipsis)
            if label.setHandleFocus then
                label:setHandleFocus(false)
            end
            if label.setTextTruncated then
                label:setTextTruncated(false)
            end

            label:setText(g_i18n:getText("usedplus_mechanic_assessment") or "MECHANIC'S ASSESSMENT")
            -- Style as centered header
            if label.setTextColor then
                label:setTextColor(0.9, 0.8, 0.5, 1)  -- Gold header color
            end
            if label.setTextBold then
                label:setTextBold(true)
            end
        end
        if value then
            value:setText("")  -- Empty value column
            value:setVisible(false)  -- Hide value column entirely
        end

        alternating = not alternating
    end

    -- Row 2: The quote itself - centered, full width
    local quoteRow = templateRow:clone(settingsBox)
    if quoteRow then
        quoteRow:setVisible(true)
        local color = colorTable[alternating]
        if color then
            quoteRow:setImageColor(nil, unpack(color))
        end

        local label = quoteRow:getDescendantByName("label")
        local value = quoteRow:getDescendantByName("value")

        if label then
            -- Expand label to full row width and center text
            -- v2.8.0: Fix for cloned elements that may not have getSize method
            if quoteRow.getSize then
                local rowWidth, rowHeight = quoteRow:getSize()
                if rowWidth and rowWidth > 0 then
                    label:setSize(rowWidth * 0.95, nil)  -- 95% of row width
                end
            end
            if label.setTextAlignment then
                label:setTextAlignment(RenderText.ALIGN_CENTER)
            end
            -- Disable text truncation (ellipsis)
            if label.setHandleFocus then
                label:setHandleFocus(false)
            end
            if label.setTextTruncated then
                label:setTextTruncated(false)
            end

            -- Format as quote with quotation marks
            label:setText(string.format('"%s"', mechanicQuote))
            if label.setTextColor then
                label:setTextColor(unpack(quoteColor))
            end
        end
        if value then
            value:setText("")  -- Empty value column
            value:setVisible(false)  -- Hide value column entirely
        end
    end

    UsedPlus.logDebug(string.format("RVBWorkshopIntegration: Added Mechanic's Assessment for %s (scale=%.2f)",
        vehicle:getName(), workhorseLemonScale))
end
