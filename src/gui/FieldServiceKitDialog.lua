--[[
    FS25_UsedPlus - Field Service Kit Dialog (OBD Scanner)

    Multi-step diagnosis minigame dialog for emergency field repairs.
    Steps:
    1. System Selection - Player guesses which system failed
    2. Diagnosis - Player sees symptoms and picks likely cause
    3. Results - Shows repair outcome and applies to vehicle

    v1.8.0 - Field Service Kit System
    v2.0.0 - Full RVB/UYT cross-mod integration
            - Shows individual RVB part statuses (Engine, Thermostat, Generator, etc.)
            - Shows UYT tire wear breakdown per wheel
            - Color-coded health indicators with fault/prefault warnings
    v2.3.0 - Fixed button styling to use triple-element pattern (Bitmap + invisible Button + Text)
            - Matches mod's perfected custom button style
            - All dialogs now use consistent button pattern
            - Added hover effect for diagnosis buttons
            - Removed [A] [B] [C] [D] prefixes from options
            - Redesigned results screen with prominent success/failure display
]]

FieldServiceKitDialog = {}
local FieldServiceKitDialog_mt = Class(FieldServiceKitDialog, MessageDialog)

-- Registration pattern (same as other dialogs)
FieldServiceKitDialog.instance = nil
FieldServiceKitDialog.xmlPath = nil

--[[
    Register the dialog with g_gui
    Must be called before the dialog can be shown
]]
function FieldServiceKitDialog.register()
    if FieldServiceKitDialog.instance == nil then
        UsedPlus.logInfo("FieldServiceKitDialog: Registering dialog")

        -- Set XML path - use UsedPlus.MOD_DIR which persists after mod load
        if FieldServiceKitDialog.xmlPath == nil then
            FieldServiceKitDialog.xmlPath = UsedPlus.MOD_DIR .. "gui/FieldServiceKitDialog.xml"
        end

        UsedPlus.logInfo("FieldServiceKitDialog: Loading XML from: " .. tostring(FieldServiceKitDialog.xmlPath))

        -- Create instance and load GUI
        FieldServiceKitDialog.instance = FieldServiceKitDialog.new()
        g_gui:loadGui(FieldServiceKitDialog.xmlPath, "FieldServiceKitDialog", FieldServiceKitDialog.instance)

        UsedPlus.logInfo("FieldServiceKitDialog: Registration complete")
    end
end

-- v2.7.0: Added mode selection as first step
FieldServiceKitDialog.STEP_MODE_SELECT = 0       -- Choose what to do (new!)
FieldServiceKitDialog.STEP_SYSTEM_SELECT = 1     -- Component diagnosis (original)
FieldServiceKitDialog.STEP_DIAGNOSIS = 2         -- Pick diagnosis for component
FieldServiceKitDialog.STEP_RESULTS = 3           -- Show repair results
FieldServiceKitDialog.STEP_TIRE_REPAIR = 4       -- Tire patch/plug options
FieldServiceKitDialog.STEP_MALFUNCTIONS = 5      -- Show active malfunctions (new!)
FieldServiceKitDialog.STEP_RVB_ANALYSIS = 6      -- RVB component repair (new!)

function FieldServiceKitDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or FieldServiceKitDialog_mt)

    self.vehicle = nil
    self.kit = nil
    self.kitTier = "basic"
    self.currentStep = FieldServiceKitDialog.STEP_MODE_SELECT  -- v2.7.0: Start at mode selection
    self.selectedSystem = nil
    self.actualFailedSystem = nil
    self.currentScenario = nil
    self.selectedDiagnosis = nil
    self.repairResult = nil
    self.hasFlatTire = false
    self.hasFuelLeak = false  -- v2.7.0: Track fuel leak state

    return self
end

function FieldServiceKitDialog:onOpen()
    FieldServiceKitDialog:superClass().onOpen(self)
    self:updateDisplay()
end

function FieldServiceKitDialog:onCreate()
    FieldServiceKitDialog:superClass().onCreate(self)

    -- v2.8.1: Set mode icons via Lua (only method that works for mod images in ZIP)
    local iconDir = UsedPlus.MOD_DIR .. "gui/icons/"

    if self.modeRepairIcon ~= nil then
        self.modeRepairIcon:setImageFilename(iconDir .. "fsk_repair.png")
    end
    if self.modeWarningIcon ~= nil then
        self.modeWarningIcon:setImageFilename(iconDir .. "fsk_warning.png")
    end
    if self.modeTireIcon ~= nil then
        self.modeTireIcon:setImageFilename(iconDir .. "fsk_tire.png")
    end
    if self.modeDiagnosticsIcon ~= nil then
        self.modeDiagnosticsIcon:setImageFilename(iconDir .. "fsk_diagnostics.png")
    end
end

--[[
    Set data for the dialog
    @param vehicle - The vehicle to repair
    @param kit - The field service kit being used
    @param kitTier - "basic", "professional", or "master"
]]
function FieldServiceKitDialog:setData(vehicle, kit, kitTier)
    self.vehicle = vehicle
    self.kit = kit
    self.kitTier = kitTier or "basic"
    self.currentStep = FieldServiceKitDialog.STEP_MODE_SELECT  -- v2.7.0: Start at mode selection
    self.selectedSystem = nil
    self.selectedDiagnosis = nil
    self.repairResult = nil

    -- Determine actual failed system from vehicle maintenance spec
    -- Uses lastFailedSystem if a real failure was recorded, otherwise falls back to lowest reliability
    -- Player must use scanner hints to deduce the correct system (not just pick lowest %)
    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec ~= nil then
        self.actualFailedSystem = maintSpec.lastFailedSystem or self:determineFailedSystem(maintSpec)
        self.hasFlatTire = self:checkForFlatTire(vehicle)
        self.hasFuelLeak = maintSpec.hasFuelLeak or false  -- v2.7.0
    else
        self.hasFlatTire = false
        self.hasFuelLeak = false
    end

    self:updateDisplay()
end

--[[
    Determine which system most likely failed based on reliability values
]]
function FieldServiceKitDialog:determineFailedSystem(maintSpec)
    local engine = maintSpec.engineReliability or 1.0
    local electrical = maintSpec.electricalReliability or 1.0
    local hydraulic = maintSpec.hydraulicReliability or 1.0

    -- Return the system with lowest reliability
    if engine <= electrical and engine <= hydraulic then
        return DiagnosisData.SYSTEM_ENGINE
    elseif electrical <= engine and electrical <= hydraulic then
        return DiagnosisData.SYSTEM_ELECTRICAL
    else
        return DiagnosisData.SYSTEM_HYDRAULIC
    end
end

--[[
    Check if vehicle has a flat tire
]]
function FieldServiceKitDialog:checkForFlatTire(vehicle)
    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec ~= nil and maintSpec.tireConditions ~= nil then
        for _, condition in pairs(maintSpec.tireConditions) do
            if condition <= 0.01 then
                return true
            end
        end
    end
    return false
end

--[[
    Update the dialog display based on current step
]]
function FieldServiceKitDialog:updateDisplay()
    if self.vehicle == nil then
        return
    end

    local vehicleName = self.vehicle:getName() or "Vehicle"
    local maintSpec = self.vehicle.spec_usedPlusMaintenance

    if self.currentStep == FieldServiceKitDialog.STEP_MODE_SELECT then
        self:displayModeSelection(vehicleName, maintSpec)
    elseif self.currentStep == FieldServiceKitDialog.STEP_SYSTEM_SELECT then
        self:displaySystemSelection(vehicleName, maintSpec)
    elseif self.currentStep == FieldServiceKitDialog.STEP_DIAGNOSIS then
        self:displayDiagnosis()
    elseif self.currentStep == FieldServiceKitDialog.STEP_RESULTS then
        self:displayResults()
    elseif self.currentStep == FieldServiceKitDialog.STEP_TIRE_REPAIR then
        self:displayTireRepair()
    elseif self.currentStep == FieldServiceKitDialog.STEP_MALFUNCTIONS then
        self:displayMalfunctions()
    elseif self.currentStep == FieldServiceKitDialog.STEP_RVB_ANALYSIS then
        self:displayRVBAnalysis()
    end
end

--[[
    v2.7.0: Display Mode Selection (new first step)
    Player chooses what to do with the Field Service Kit
]]
function FieldServiceKitDialog:displayModeSelection(vehicleName, maintSpec)
    -- Update vehicle name
    if self.vehicleNameText ~= nil then
        self.vehicleNameText:setText(vehicleName)
    end

    -- Count active malfunctions for the button label
    local malfunctionCount = 0
    local seized = self:getSeizedComponents()
    if seized.engine then malfunctionCount = malfunctionCount + 1 end
    if seized.hydraulic then malfunctionCount = malfunctionCount + 1 end
    if seized.electrical then malfunctionCount = malfunctionCount + 1 end
    if self.hasFuelLeak then malfunctionCount = malfunctionCount + 1 end
    if self.hasFlatTire then malfunctionCount = malfunctionCount + 1 end

    -- Update mode button labels based on current state
    -- v2.7.1: Use Text labels instead of Button elements to avoid duplicate text
    if self.modeDiagnoseLabel ~= nil then
        self.modeDiagnoseLabel:setText(g_i18n:getText("usedplus_fsk_mode_diagnose") or "Diagnose Component")
    end

    if self.modeMalfunctionsLabel ~= nil then
        local malfText = g_i18n:getText("usedplus_fsk_mode_malfunctions") or "Locate Malfunctions"
        if malfunctionCount > 0 then
            malfText = malfText .. string.format(" (%d)", malfunctionCount)
        end
        self.modeMalfunctionsLabel:setText(malfText)
    end

    if self.modeTireServiceLabel ~= nil then
        local tireText = g_i18n:getText("usedplus_fsk_mode_tire") or "Tire Service"
        if self.hasFlatTire then
            tireText = tireText .. " (!)"
        end
        self.modeTireServiceLabel:setText(tireText)
        -- Disable if no flat tire (optional - could allow tire inspection even without flat)
        -- For now, keep enabled to allow future "inspect tires" feature
    end

    -- v2.7.0: Only show RVB button if RVB mod is actually installed
    -- Don't tease players with features they can't use
    local hasRVB = ModCompatibility.rvbInstalled or false
    if self.modeRVBBox ~= nil then
        self.modeRVBBox:setVisible(hasRVB)
    end
    if self.modeRVBButton ~= nil then
        self.modeRVBButton:setVisible(hasRVB)
    end

    -- Show mode selection container, hide others
    self:setStepVisibility(FieldServiceKitDialog.STEP_MODE_SELECT)
end

--[[
    Display Step 1: System Selection
    v1.8.0: Uses ModCompatibility to show RVB part details when available
    v2.0.0: Shows detailed RVB part status and UYT tire wear in dedicated sections
]]
function FieldServiceKitDialog:displaySystemSelection(vehicleName, maintSpec)
    -- v1.8.0: Get diagnostic data from ModCompatibility (includes RVB data if available)
    local diagData = ModCompatibility.getOBDDiagnosticData(self.vehicle)

    -- Get reliability values (uses RVB-derived values if RVB is installed)
    local engineRel = math.floor(diagData.engine.reliability * 100)
    local elecRel = math.floor(diagData.electrical.reliability * 100)
    local hydRel = math.floor(diagData.hydraulic.reliability * 100)

    local isDisabled = maintSpec and maintSpec.isDisabled or false
    local statusText = isDisabled and g_i18n:getText("usedplus_fsk_status_disabled") or g_i18n:getText("usedplus_fsk_status_needs_service")

    -- v1.8.0: Store diagnostic data for later steps (RVB repair integration)
    self.diagnosticData = diagData

    -- Update UI elements
    if self.vehicleNameText ~= nil then
        self.vehicleNameText:setText(vehicleName)
    end

    if self.statusText ~= nil then
        self.statusText:setText(statusText)
        if isDisabled then
            self.statusText:setTextColor(1, 0.2, 0.2, 1)  -- Red
        else
            self.statusText:setTextColor(1, 0.7, 0, 1)  -- Orange
        end
    end

    -- v2.7.0: Get seized component status
    local seized = self:getSeizedComponents()

    -- Update reliability displays (with seizure indicators)
    if self.engineRelText ~= nil then
        if seized.engine then
            self.engineRelText:setText(g_i18n:getText("usedplus_fsk_seized"))
            self.engineRelText:setTextColor(1, 0.1, 0.1, 1)  -- Bright red
        else
            self.engineRelText:setText(string.format("%d%%", engineRel))
            self:setReliabilityColor(self.engineRelText, engineRel)
        end
    end

    if self.electricalRelText ~= nil then
        if seized.electrical then
            self.electricalRelText:setText(g_i18n:getText("usedplus_fsk_seized"))
            self.electricalRelText:setTextColor(1, 0.1, 0.1, 1)  -- Bright red
        else
            self.electricalRelText:setText(string.format("%d%%", elecRel))
            self:setReliabilityColor(self.electricalRelText, elecRel)
        end
    end

    if self.hydraulicRelText ~= nil then
        if seized.hydraulic then
            self.hydraulicRelText:setText(g_i18n:getText("usedplus_fsk_seized"))
            self.hydraulicRelText:setTextColor(1, 0.1, 0.1, 1)  -- Bright red
        else
            self.hydraulicRelText:setText(string.format("%d%%", hydRel))
            self:setReliabilityColor(self.hydraulicRelText, hydRel)
        end
    end

    -- v2.1.0: Display scanner readout hints for the actual failed system
    -- These help the player deduce which system to select
    self:displayScannerHints()

    -- v2.0.0: Display RVB part details if RVB is installed
    self:displayRVBDetails(diagData)

    -- v2.0.0: Display UYT tire details if UYT is installed
    self:displayUYTDetails(diagData)

    -- Show/hide step containers
    self:setStepVisibility(FieldServiceKitDialog.STEP_SYSTEM_SELECT)

    -- Show tire button if flat tire detected
    if self.tireButton ~= nil then
        self.tireButton:setVisible(self.hasFlatTire)
    end
end

--[[
    v2.1.0: Display scanner readout hints
    Shows 2 diagnostic hints based on the actual failed system
    Player uses these to deduce which system to select
]]
function FieldServiceKitDialog:displayScannerHints()
    if self.actualFailedSystem == nil then
        -- No failure detected, show generic message
        if self.scannerHint1Text ~= nil then
            self.scannerHint1Text:setText(g_i18n:getText("usedplus_fsk_hint_no_faults") or "No critical faults detected")
        end
        if self.scannerHint2Text ~= nil then
            self.scannerHint2Text:setText(g_i18n:getText("usedplus_fsk_hint_preventive") or "Preventive maintenance recommended")
        end
        return
    end

    -- Get 2 random hints for the actual failed system
    local hints = DiagnosisData.getSystemHints(self.actualFailedSystem, 2)

    -- Display hint 1
    if self.scannerHint1Text ~= nil then
        if hints[1] ~= nil then
            local hintText = g_i18n:getText(hints[1])
            self.scannerHint1Text:setText(">> " .. (hintText or hints[1]))
        else
            self.scannerHint1Text:setText("")
        end
    end

    -- Display hint 2
    if self.scannerHint2Text ~= nil then
        if hints[2] ~= nil then
            local hintText = g_i18n:getText(hints[2])
            self.scannerHint2Text:setText(">> " .. (hintText or hints[2]))
        else
            self.scannerHint2Text:setText("")
        end
    end

    UsedPlus.logInfo(string.format("Scanner hints displayed for system: %s", self.actualFailedSystem))
end

--[[
    v2.0.0: Display RVB part details in dedicated section
    Shows individual part life percentages and fault indicators
]]
function FieldServiceKitDialog:displayRVBDetails(diagData)
    -- Show/hide RVB container based on whether RVB data is available
    if self.rvbDetailContainer ~= nil then
        self.rvbDetailContainer:setVisible(diagData.hasRVBData)
    end

    if not diagData.hasRVBData then
        return
    end

    local faultCount = 0

    -- Display engine parts
    for _, part in ipairs(diagData.engine.rvbParts or {}) do
        local elementId = "rvb" .. part.name:gsub(" ", "") .. "Text"
        local element = self[elementId]
        if element ~= nil then
            local lifePercent = math.floor(part.life * 100)
            local statusStr = string.format("%d%%", lifePercent)

            -- Add fault/prefault indicator
            if part.fault then
                statusStr = statusStr .. " FAULT"
                faultCount = faultCount + 1
            elseif part.prefault then
                statusStr = statusStr .. " !"
            end

            element:setText(statusStr)
            self:setRVBPartColor(element, part.life, part.fault, part.prefault)
        end
    end

    -- Display electrical parts
    for _, part in ipairs(diagData.electrical.rvbParts or {}) do
        local elementId = "rvb" .. part.name:gsub(" ", "") .. "Text"
        local element = self[elementId]
        if element ~= nil then
            local lifePercent = math.floor(part.life * 100)
            local statusStr = string.format("%d%%", lifePercent)

            if part.fault then
                statusStr = statusStr .. " FAULT"
                faultCount = faultCount + 1
            elseif part.prefault then
                statusStr = statusStr .. " !"
            end

            element:setText(statusStr)
            self:setRVBPartColor(element, part.life, part.fault, part.prefault)
        end
    end

    -- Display fault count
    if self.rvbFaultCountText ~= nil then
        if faultCount > 0 then
            self.rvbFaultCountText:setText(tostring(faultCount))
            self.rvbFaultCountText:setTextColor(1, 0.3, 0.3, 1)  -- Red
        else
            self.rvbFaultCountText:setText("None")
            self.rvbFaultCountText:setTextColor(0.4, 0.8, 0.4, 1)  -- Green
        end
    end
end

--[[
    v2.0.0: Display UYT tire wear details in dedicated section
]]
function FieldServiceKitDialog:displayUYTDetails(diagData)
    -- Show/hide UYT container based on whether UYT data is available
    if self.uytTireContainer ~= nil then
        self.uytTireContainer:setVisible(diagData.hasUYTData)
    end

    if not diagData.hasUYTData then
        return
    end

    local worstWear = 0
    local tirePositions = {"FL", "FR", "RL", "RR"}

    for i, tire in ipairs(diagData.tires or {}) do
        local position = tirePositions[i] or tostring(i)
        local elementId = "uytTire" .. position .. "Text"
        local element = self[elementId]

        if element ~= nil then
            local wearPercent = math.floor(tire.wear * 100)
            local conditionPercent = math.floor(tire.condition * 100)
            element:setText(string.format("%d%%", conditionPercent))
            self:setTireConditionColor(element, tire.condition)

            if tire.wear > worstWear then
                worstWear = tire.wear
            end
        end
    end

    -- Display worst tire status
    if self.uytWorstTireText ~= nil then
        local worstCondition = 1 - worstWear
        local worstPercent = math.floor(worstCondition * 100)
        self.uytWorstTireText:setText(string.format("%d%%", worstPercent))
        self:setTireConditionColor(self.uytWorstTireText, worstCondition)
    end
end

--[[
    v2.0.0: Set color for RVB part status based on life and fault state
]]
function FieldServiceKitDialog:setRVBPartColor(element, life, hasFault, hasPrefault)
    if element == nil then return end

    if hasFault then
        element:setTextColor(1, 0.2, 0.2, 1)  -- Red for fault
    elseif hasPrefault then
        element:setTextColor(1, 0.6, 0, 1)  -- Orange for prefault
    elseif life >= 0.7 then
        element:setTextColor(0.4, 0.8, 0.4, 1)  -- Green
    elseif life >= 0.4 then
        element:setTextColor(1, 0.8, 0.2, 1)  -- Yellow
    elseif life >= 0.2 then
        element:setTextColor(1, 0.5, 0, 1)  -- Orange
    else
        element:setTextColor(1, 0.3, 0.3, 1)  -- Red
    end
end

--[[
    v2.0.0: Set color for tire condition
]]
function FieldServiceKitDialog:setTireConditionColor(element, condition)
    if element == nil then return end

    if condition >= 0.7 then
        element:setTextColor(0.4, 0.8, 0.4, 1)  -- Green
    elseif condition >= 0.4 then
        element:setTextColor(1, 0.8, 0.2, 1)  -- Yellow
    elseif condition >= 0.2 then
        element:setTextColor(1, 0.5, 0, 1)  -- Orange
    else
        element:setTextColor(1, 0.3, 0.3, 1)  -- Red
    end
end

--[[
    Display Step 2: Diagnosis (symptoms and diagnosis options)
]]
function FieldServiceKitDialog:displayDiagnosis()
    if self.selectedSystem == nil then
        return
    end

    -- Get scenario for selected system
    self.currentScenario = DiagnosisData.getRandomScenario(self.selectedSystem)

    if self.currentScenario == nil then
        UsedPlus.logDebug("FieldServiceKitDialog: No scenario found for system: " .. tostring(self.selectedSystem))
        return
    end

    -- Display system name
    local systemName = g_i18n:getText("usedplus_fsk_system_" .. self.selectedSystem) or self.selectedSystem
    if self.systemNameText ~= nil then
        self.systemNameText:setText(string.format("%s %s", systemName, g_i18n:getText("usedplus_fsk_diagnosis") or "DIAGNOSIS"))
    end

    -- Display symptoms
    if self.symptom1Text ~= nil and self.currentScenario.symptoms[1] then
        self.symptom1Text:setText("* " .. g_i18n:getText(self.currentScenario.symptoms[1]))
    end
    if self.symptom2Text ~= nil and self.currentScenario.symptoms[2] then
        self.symptom2Text:setText("* " .. g_i18n:getText(self.currentScenario.symptoms[2]))
    end
    if self.symptom3Text ~= nil and self.currentScenario.symptoms[3] then
        self.symptom3Text:setText("* " .. g_i18n:getText(self.currentScenario.symptoms[3]))
    end

    -- Display diagnosis options (no letter prefix - hover effect shows selection)
    if self.diagButton1 ~= nil and self.currentScenario.diagnoses[1] then
        self.diagButton1:setText(g_i18n:getText(self.currentScenario.diagnoses[1]))
    end
    if self.diagButton2 ~= nil and self.currentScenario.diagnoses[2] then
        self.diagButton2:setText(g_i18n:getText(self.currentScenario.diagnoses[2]))
    end
    if self.diagButton3 ~= nil and self.currentScenario.diagnoses[3] then
        self.diagButton3:setText(g_i18n:getText(self.currentScenario.diagnoses[3]))
    end
    if self.diagButton4 ~= nil and self.currentScenario.diagnoses[4] then
        self.diagButton4:setText(g_i18n:getText(self.currentScenario.diagnoses[4]))
    end

    self:setStepVisibility(FieldServiceKitDialog.STEP_DIAGNOSIS)
end

--[[
    Display Step 3: Results (Redesigned v2.3.0)
    Prominent success/failure display with diagnosis details
]]
function FieldServiceKitDialog:displayResults()
    if self.repairResult == nil then
        return
    end

    local maintSpec = self.vehicle.spec_usedPlusMaintenance
    local isCorrect = self.repairResult.wasCorrectSystem and self.repairResult.wasCorrectDiagnosis
    local isPartial = self.repairResult.wasCorrectSystem and not self.repairResult.wasCorrectDiagnosis
    -- v2.13.2: Fix Issue #9 - Add 4th state: wrong system but correct diagnosis
    -- Previously this fell through to "WRONG DIAGNOSIS" which confused players
    -- because the "Correct answer" shown matched their answer exactly
    local isWrongSystem = not self.repairResult.wasCorrectSystem and self.repairResult.wasCorrectDiagnosis
    local isWrongBoth = not self.repairResult.wasCorrectSystem and not self.repairResult.wasCorrectDiagnosis

    -- ========== OUTCOME HEADER ==========
    -- Set icon and background color based on outcome
    -- v2.13.2: Use ASCII-safe characters — FS25 font lacks Unicode ✓ (U+2713) and ✗ (U+2717)
    -- Game log: "Character '10007' not found in texture font"
    if self.outcomeIcon ~= nil then
        if isCorrect then
            self.outcomeIcon:setText("OK")
            self.outcomeIcon:setTextColor(0.3, 1, 0.4, 1)
        elseif isPartial then
            self.outcomeIcon:setText("~")
            self.outcomeIcon:setTextColor(1, 0.7, 0.2, 1)
        elseif isWrongSystem then
            self.outcomeIcon:setText("~")
            self.outcomeIcon:setTextColor(1, 0.6, 0.2, 1)
        else
            self.outcomeIcon:setText("X")
            self.outcomeIcon:setTextColor(1, 0.4, 0.4, 1)
        end
    end

    if self.outcomeBg ~= nil then
        if isCorrect then
            -- Green success background
            self.outcomeBg:setImageColor(nil, 0.08, 0.22, 0.08, 0.95)
        elseif isPartial or isWrongSystem then
            -- Orange partial background (wrong system with right diagnosis is partial success)
            self.outcomeBg:setImageColor(nil, 0.22, 0.16, 0.06, 0.95)
        else
            -- Red failure background
            self.outcomeBg:setImageColor(nil, 0.22, 0.08, 0.08, 0.95)
        end
    end

    -- Outcome title (v2.13.2: use i18n instead of hardcoded English)
    if self.resultTitleText ~= nil then
        if isCorrect then
            self.resultTitleText:setText(g_i18n:getText("usedplus_fsk_result_title_perfect"))
            self.resultTitleText:setTextColor(0.4, 1, 0.5, 1)
        elseif isPartial then
            self.resultTitleText:setText(g_i18n:getText("usedplus_fsk_result_title_good"))
            self.resultTitleText:setTextColor(1, 0.8, 0.3, 1)
        elseif isWrongSystem then
            -- v2.13.2: New state - player got diagnosis right but picked wrong system
            self.resultTitleText:setText(g_i18n:getText("usedplus_fsk_result_title_wrong_system"))
            self.resultTitleText:setTextColor(1, 0.7, 0.3, 1)
        else
            self.resultTitleText:setText(g_i18n:getText("usedplus_fsk_result_title_poor"))
            self.resultTitleText:setTextColor(1, 0.5, 0.5, 1)
        end
    end

    -- Outcome subtitle (v2.13.2: use i18n instead of hardcoded English)
    if self.resultMessageText ~= nil then
        if isCorrect then
            self.resultMessageText:setText(g_i18n:getText("usedplus_fsk_result_perfect"))
        elseif isPartial then
            self.resultMessageText:setText(g_i18n:getText("usedplus_fsk_result_good"))
        elseif isWrongSystem then
            -- v2.13.2: Tell player their diagnosis was correct but system was wrong
            local actualSystemName = g_i18n:getText("usedplus_fsk_system_" .. (self.actualFailedSystem or "")) or self.actualFailedSystem or "Unknown"
            self.resultMessageText:setText(string.format(g_i18n:getText("usedplus_fsk_result_wrong_system"), actualSystemName))
        else
            self.resultMessageText:setText(g_i18n:getText("usedplus_fsk_result_wrong_both"))
        end
    end

    -- ========== DIAGNOSIS DETAILS ==========
    -- Show what the player diagnosed
    if self.playerDiagnosisText ~= nil and self.currentScenario ~= nil then
        local playerDiag = self.currentScenario.diagnoses[self.selectedDiagnosis]
        if playerDiag ~= nil then
            self.playerDiagnosisText:setText(g_i18n:getText(playerDiag) or "Unknown")
        end
    end

    -- Show correct answer (only when diagnosis was wrong AND system was right)
    -- v2.13.2: Don't show "Correct answer" when it matches player's answer (wrong system case)
    -- That was the core Issue #9 bug - "Correct answer: Faulty Seals" shown when player picked "Faulty Seals"
    local showCorrectAnswer = not isCorrect and not isWrongSystem
    if self.correctDiagLabel ~= nil then
        self.correctDiagLabel:setVisible(showCorrectAnswer)
    end
    if self.correctDiagnosisText ~= nil then
        self.correctDiagnosisText:setVisible(showCorrectAnswer)
        if showCorrectAnswer and self.currentScenario ~= nil then
            local correctDiag = self.currentScenario.diagnoses[self.currentScenario.correctDiagnosis]
            if correctDiag ~= nil then
                self.correctDiagnosisText:setText(g_i18n:getText(correctDiag) or "Unknown")
            end
        end
    end

    -- ========== RELIABILITY SECTION ==========
    -- Update header based on outcome (v2.13.2: use i18n)
    if self.reliabilityHeader ~= nil then
        if isCorrect then
            self.reliabilityHeader:setText(g_i18n:getText("usedplus_fsk_reliability_restored"))
            self.reliabilityHeader:setTextColor(0.3, 1, 0.4, 1)
        elseif isPartial or isWrongSystem then
            self.reliabilityHeader:setText(g_i18n:getText("usedplus_fsk_reliability_partial"))
            self.reliabilityHeader:setTextColor(1, 0.8, 0.3, 1)
        else
            self.reliabilityHeader:setText(g_i18n:getText("usedplus_fsk_reliability_minimal"))
            self.reliabilityHeader:setTextColor(1, 0.5, 0.5, 1)
        end
    end

    -- Calculate before/after values
    local systemKey = self.selectedSystem or self.actualFailedSystem
    local beforeRel = 0
    local afterRel = 0

    if maintSpec ~= nil then
        if systemKey == DiagnosisData.SYSTEM_ENGINE then
            afterRel = math.floor(maintSpec.engineReliability * 100)
            beforeRel = afterRel - math.floor(self.repairResult.reliabilityBoost * 100)
        elseif systemKey == DiagnosisData.SYSTEM_ELECTRICAL then
            afterRel = math.floor(maintSpec.electricalReliability * 100)
            beforeRel = afterRel - math.floor(self.repairResult.reliabilityBoost * 100)
        elseif systemKey == DiagnosisData.SYSTEM_HYDRAULIC then
            afterRel = math.floor(maintSpec.hydraulicReliability * 100)
            beforeRel = afterRel - math.floor(self.repairResult.reliabilityBoost * 100)
        end
    end

    if self.beforeRelText ~= nil then
        self.beforeRelText:setText(string.format("%d%%", math.max(0, beforeRel)))
    end
    if self.afterRelText ~= nil then
        self.afterRelText:setText(string.format("%d%%", afterRel))
    end
    if self.boostText ~= nil then
        local boostPercent = math.floor(self.repairResult.reliabilityBoost * 100)
        self.boostText:setText(string.format("+%d%%", boostPercent))
        -- Color based on boost amount
        if boostPercent >= 30 then
            self.boostText:setTextColor(0.3, 1, 0.4, 1)  -- Green for big boost
        elseif boostPercent >= 15 then
            self.boostText:setTextColor(1, 0.8, 0.3, 1)  -- Yellow for medium
        else
            self.boostText:setTextColor(1, 0.5, 0.5, 1)  -- Red-ish for small
        end
    end

    self:setStepVisibility(FieldServiceKitDialog.STEP_RESULTS)
end

--[[
    Display tire repair options
    v2.7.1: Shows tire status with percentages, only enables repair if flat tire exists
]]
function FieldServiceKitDialog:displayTireRepair()
    self:setStepVisibility(FieldServiceKitDialog.STEP_TIRE_REPAIR)

    -- Get tire conditions from vehicle
    local maintSpec = self.vehicle.spec_usedPlusMaintenance
    local tireConditions = {1.0, 1.0, 1.0, 1.0}  -- Default to 100%
    local hasFlatTire = false

    if maintSpec ~= nil and maintSpec.tireConditions ~= nil then
        for i = 1, 4 do
            tireConditions[i] = maintSpec.tireConditions[i] or 1.0
            if tireConditions[i] <= 0.01 then
                hasFlatTire = true
            end
        end
    end

    -- Update tire slot displays (FL, FR, RL, RR)
    local tireSlots = {
        { text = self.tireFLText, bg = self.tireFLBg, condition = tireConditions[1] },
        { text = self.tireFRText, bg = self.tireFRBg, condition = tireConditions[2] },
        { text = self.tireRLText, bg = self.tireRLBg, condition = tireConditions[3] },
        { text = self.tireRRText, bg = self.tireRRBg, condition = tireConditions[4] }
    }

    for _, slot in ipairs(tireSlots) do
        if slot.text ~= nil then
            local pct = math.floor(slot.condition * 100)
            if pct <= 1 then
                slot.text:setText(g_i18n:getText("usedplus_fsk_flat"))
                slot.text:setTextColor(1, 0.2, 0.2, 1)  -- Red
            elseif pct <= 25 then
                slot.text:setText(pct .. "%")
                slot.text:setTextColor(1, 0.5, 0.2, 1)  -- Orange
            elseif pct <= 50 then
                slot.text:setText(pct .. "%")
                slot.text:setTextColor(1, 0.8, 0.2, 1)  -- Yellow
            else
                slot.text:setText(pct .. "%")
                slot.text:setTextColor(0.4, 1, 0.5, 1)  -- Green
            end
        end

        -- Color the background based on condition
        if slot.bg ~= nil then
            if slot.condition <= 0.01 then
                slot.bg:setImageColor(nil, 0.3, 0.1, 0.1, 0.95)  -- Dark red
            elseif slot.condition <= 0.25 then
                slot.bg:setImageColor(nil, 0.25, 0.15, 0.1, 0.95)  -- Dark orange
            elseif slot.condition <= 0.5 then
                slot.bg:setImageColor(nil, 0.25, 0.2, 0.1, 0.95)  -- Dark yellow
            else
                slot.bg:setImageColor(nil, 0.15, 0.15, 0.18, 0.9)  -- Normal dark
            end
        end
    end

    -- Set vehicle image if available
    if self.tireVehicleImage ~= nil and self.vehicle ~= nil then
        local storeItem = g_storeManager:getItemByXMLFilename(self.vehicle.configFileName)
        if storeItem ~= nil and storeItem.imageFilename ~= nil then
            self.tireVehicleImage:setImageFilename(storeItem.imageFilename)
        end
    end

    -- Show/hide repair options based on flat tire status
    local showRepairOptions = hasFlatTire
    local showStatusMsg = not hasFlatTire

    -- Patch button elements
    if self.patchBtnBg ~= nil then self.patchBtnBg:setVisible(showRepairOptions) end
    if self.patchButton ~= nil then
        self.patchButton:setVisible(showRepairOptions)
        self.patchButton:setDisabled(not hasFlatTire)
    end
    if self.patchTitle ~= nil then self.patchTitle:setVisible(showRepairOptions) end
    if self.patchDesc ~= nil then self.patchDesc:setVisible(showRepairOptions) end
    if self.patchResult ~= nil then self.patchResult:setVisible(showRepairOptions) end

    -- Plug button elements
    if self.plugBtnBg ~= nil then self.plugBtnBg:setVisible(showRepairOptions) end
    if self.plugButton ~= nil then
        self.plugButton:setVisible(showRepairOptions)
        self.plugButton:setDisabled(not hasFlatTire)
    end
    if self.plugTitle ~= nil then self.plugTitle:setVisible(showRepairOptions) end
    if self.plugDesc ~= nil then self.plugDesc:setVisible(showRepairOptions) end
    if self.plugResult ~= nil then self.plugResult:setVisible(showRepairOptions) end

    -- Instruction text (only shown when flat tire exists)
    if self.tireInstructionText ~= nil then
        self.tireInstructionText:setVisible(showRepairOptions)
    end

    -- Status message (shown when no flat tire)
    if self.tireStatusMsg ~= nil then
        self.tireStatusMsg:setVisible(showStatusMsg)
        if showStatusMsg then
            self.tireStatusMsg:setText(g_i18n:getText("usedplus_fsk_tires_ok") or "All tires OK - No repair needed")
        end
    end
end

--[[
    Set visibility of step containers
]]
function FieldServiceKitDialog:setStepVisibility(activeStep)
    -- v2.7.0: Mode selection container
    if self.modeSelectContainer ~= nil then
        self.modeSelectContainer:setVisible(activeStep == FieldServiceKitDialog.STEP_MODE_SELECT)
    end
    if self.systemSelectContainer ~= nil then
        self.systemSelectContainer:setVisible(activeStep == FieldServiceKitDialog.STEP_SYSTEM_SELECT)
    end
    if self.diagnosisContainer ~= nil then
        self.diagnosisContainer:setVisible(activeStep == FieldServiceKitDialog.STEP_DIAGNOSIS)
    end
    if self.resultsContainer ~= nil then
        self.resultsContainer:setVisible(activeStep == FieldServiceKitDialog.STEP_RESULTS)
    end
    if self.tireRepairContainer ~= nil then
        self.tireRepairContainer:setVisible(activeStep == FieldServiceKitDialog.STEP_TIRE_REPAIR)
    end
    -- v2.7.0: New containers for malfunctions and RVB
    if self.malfunctionsContainer ~= nil then
        self.malfunctionsContainer:setVisible(activeStep == FieldServiceKitDialog.STEP_MALFUNCTIONS)
    end
    if self.rvbAnalysisContainer ~= nil then
        self.rvbAnalysisContainer:setVisible(activeStep == FieldServiceKitDialog.STEP_RVB_ANALYSIS)
    end

    -- Update button visibility based on step
    if self.okButton ~= nil then
        local showOk = (activeStep == FieldServiceKitDialog.STEP_RESULTS) or
                       (activeStep == FieldServiceKitDialog.STEP_MALFUNCTIONS) or
                       (activeStep == FieldServiceKitDialog.STEP_RVB_ANALYSIS)
        self.okButton:setText(g_i18n:getText("button_ok") or "OK")
        self.okButton:setVisible(showOk)
    end

    -- v2.7.0: Back button for navigating back to mode selection
    if self.backButton ~= nil then
        local showBack = (activeStep ~= FieldServiceKitDialog.STEP_MODE_SELECT) and
                         (activeStep ~= FieldServiceKitDialog.STEP_RESULTS)
        self.backButton:setVisible(showBack)
    end

    if self.cancelButton ~= nil then
        self.cancelButton:setVisible(activeStep ~= FieldServiceKitDialog.STEP_RESULTS)
    end
end

--[[
    Set text color based on reliability value
]]
function FieldServiceKitDialog:setReliabilityColor(element, value)
    if element == nil then return end

    if value >= 70 then
        element:setTextColor(0.2, 0.8, 0.2, 1)  -- Green
    elseif value >= 40 then
        element:setTextColor(1, 0.7, 0, 1)  -- Orange
    else
        element:setTextColor(1, 0.2, 0.2, 1)  -- Red
    end
end

-- v2.2.1: Removed custom hover effect code - buttonActivate profile provides built-in hover styling

-- ===========================================================================
-- v2.7.0: MODE SELECTION BUTTON HANDLERS
-- ===========================================================================

--[[
    Mode: Diagnose Component - goes to original system selection flow
]]
function FieldServiceKitDialog:onModeDiagnoseClick()
    self.currentStep = FieldServiceKitDialog.STEP_SYSTEM_SELECT
    self:updateDisplay()
end

--[[
    Mode: Locate Malfunctions - shows active issues
]]
function FieldServiceKitDialog:onModeMalfunctionsClick()
    self.currentStep = FieldServiceKitDialog.STEP_MALFUNCTIONS
    self:updateDisplay()
end

--[[
    Mode: Tire Service - goes to tire repair flow
]]
function FieldServiceKitDialog:onModeTireServiceClick()
    if self.hasFlatTire then
        self.currentStep = FieldServiceKitDialog.STEP_TIRE_REPAIR
    else
        -- No flat tire - could show tire inspection in future
        -- For now just go to tire repair which will show "no flat tire" message
        self.currentStep = FieldServiceKitDialog.STEP_TIRE_REPAIR
    end
    self:updateDisplay()
end

--[[
    Mode: RVB System Analysis - shows RVB component repair options
]]
function FieldServiceKitDialog:onModeRVBClick()
    if not ModCompatibility.rvbInstalled then
        g_currentMission:showBlinkingWarning(
            g_i18n:getText("usedplus_fsk_rvb_not_installed") or "RVB mod not installed",
            3000
        )
        return
    end
    self.currentStep = FieldServiceKitDialog.STEP_RVB_ANALYSIS
    self:updateDisplay()
end

--[[
    Back button - returns to mode selection
]]
function FieldServiceKitDialog:onBackClick()
    self.currentStep = FieldServiceKitDialog.STEP_MODE_SELECT
    self:updateDisplay()
end

-- ===========================================================================
-- v2.7.0: MALFUNCTIONS VIEW
-- Shows all active issues: seizures, fuel leak, flat tire
-- ===========================================================================

--[[
    Display active malfunctions list
]]
function FieldServiceKitDialog:displayMalfunctions()
    local maintSpec = self.vehicle.spec_usedPlusMaintenance
    local vehicleName = self.vehicle:getName() or "Vehicle"

    -- Update vehicle name
    if self.malfVehicleNameText ~= nil then
        self.malfVehicleNameText:setText(vehicleName)
    end

    -- Gather all active malfunctions
    local malfunctions = {}

    -- Check for seized components
    local seized = self:getSeizedComponents()
    if seized.engine then
        table.insert(malfunctions, {
            name = g_i18n:getText("usedplus_component_engine") or "Engine",
            issue = g_i18n:getText("usedplus_malfunction_seized") or "SEIZED",
            severity = "critical",
            repairable = true,
            repairAction = "engine_seizure"
        })
    end
    if seized.hydraulic then
        table.insert(malfunctions, {
            name = g_i18n:getText("usedplus_component_hydraulic") or "Hydraulics",
            issue = g_i18n:getText("usedplus_malfunction_seized") or "SEIZED",
            severity = "critical",
            repairable = true,
            repairAction = "hydraulic_seizure"
        })
    end
    if seized.electrical then
        table.insert(malfunctions, {
            name = g_i18n:getText("usedplus_component_electrical") or "Electrical",
            issue = g_i18n:getText("usedplus_malfunction_seized") or "SEIZED",
            severity = "critical",
            repairable = true,
            repairAction = "electrical_seizure"
        })
    end

    -- Check for fuel leak
    if self.hasFuelLeak then
        table.insert(malfunctions, {
            name = g_i18n:getText("usedplus_component_fuel_system") or "Fuel System",
            issue = g_i18n:getText("usedplus_malfunction_leak") or "LEAKING",
            severity = "warning",
            repairable = true,
            repairAction = "fuel_leak"
        })
    end

    -- Check for flat tire
    if self.hasFlatTire then
        table.insert(malfunctions, {
            name = g_i18n:getText("usedplus_component_tires") or "Tires",
            issue = g_i18n:getText("usedplus_malfunction_flat") or "FLAT",
            severity = "warning",
            repairable = true,
            repairAction = "flat_tire"
        })
    end

    -- Store malfunctions for repair actions
    self.currentMalfunctions = malfunctions

    -- Update malfunction count
    if self.malfCountText ~= nil then
        if #malfunctions > 0 then
            self.malfCountText:setText(string.format("%d %s", #malfunctions,
                #malfunctions == 1 and "issue found" or "issues found"))
            self.malfCountText:setTextColor(1, 0.5, 0.2, 1)  -- Orange
        else
            self.malfCountText:setText(g_i18n:getText("usedplus_fsk_no_malfunctions") or "No active malfunctions")
            self.malfCountText:setTextColor(0.4, 0.8, 0.4, 1)  -- Green
        end
    end

    -- Display up to 4 malfunctions in the list
    for i = 1, 4 do
        local nameElement = self["malf" .. i .. "NameText"]
        local issueElement = self["malf" .. i .. "IssueText"]
        local rowElement = self["malf" .. i .. "Row"]

        if malfunctions[i] then
            local malf = malfunctions[i]
            if nameElement then nameElement:setText(malf.name) end
            if issueElement then
                issueElement:setText(malf.issue)
                if malf.severity == "critical" then
                    issueElement:setTextColor(1, 0.2, 0.2, 1)  -- Red
                else
                    issueElement:setTextColor(1, 0.6, 0.2, 1)  -- Orange
                end
            end
            if rowElement then rowElement:setVisible(true) end
        else
            if nameElement then nameElement:setText("") end
            if issueElement then issueElement:setText("") end
            if rowElement then rowElement:setVisible(false) end
        end
    end

    self:setStepVisibility(FieldServiceKitDialog.STEP_MALFUNCTIONS)
end

-- ===========================================================================
-- v2.7.0: RVB ANALYSIS VIEW
-- Shows RVB component breakdown and allows incremental repair
-- ===========================================================================

--[[
    Display RVB system analysis
    Shows individual RVB component life percentages and repair options
]]
function FieldServiceKitDialog:displayRVBAnalysis()
    if not ModCompatibility.rvbInstalled then
        self:onBackClick()
        return
    end

    local vehicleName = self.vehicle:getName() or "Vehicle"

    -- Update vehicle name
    if self.rvbVehicleNameText ~= nil then
        self.rvbVehicleNameText:setText(vehicleName)
    end

    -- Get RVB diagnostic data
    local diagData = ModCompatibility.getOBDDiagnosticData(self.vehicle)

    if not diagData.hasRVBData then
        if self.rvbNoDataText ~= nil then
            self.rvbNoDataText:setText(g_i18n:getText("usedplus_fsk_rvb_no_data") or "No RVB data available for this vehicle")
            self.rvbNoDataText:setVisible(true)
        end
        self:setStepVisibility(FieldServiceKitDialog.STEP_RVB_ANALYSIS)
        return
    end

    if self.rvbNoDataText ~= nil then
        self.rvbNoDataText:setVisible(false)
    end

    -- Collect all RVB parts from all systems
    local allParts = {}

    -- Engine parts
    for _, part in ipairs(diagData.engine.rvbParts or {}) do
        table.insert(allParts, {
            name = part.name,
            life = part.life,
            fault = part.fault,
            prefault = part.prefault,
            system = "engine"
        })
    end

    -- Electrical parts
    for _, part in ipairs(diagData.electrical.rvbParts or {}) do
        table.insert(allParts, {
            name = part.name,
            life = part.life,
            fault = part.fault,
            prefault = part.prefault,
            system = "electrical"
        })
    end

    -- Store for repair actions
    self.rvbParts = allParts

    -- Display parts (up to 6 visible at once)
    for i = 1, 6 do
        local nameElement = self["rvbPart" .. i .. "NameText"]
        local lifeElement = self["rvbPart" .. i .. "LifeText"]
        local rowElement = self["rvbPart" .. i .. "Row"]

        if allParts[i] then
            local part = allParts[i]
            if nameElement then nameElement:setText(part.name) end
            if lifeElement then
                local lifePercent = math.floor(part.life * 100)
                local statusStr = string.format("%d%%", lifePercent)
                if part.fault then
                    statusStr = statusStr .. " FAULT"
                    lifeElement:setTextColor(1, 0.2, 0.2, 1)
                elseif part.prefault then
                    statusStr = statusStr .. " !"
                    lifeElement:setTextColor(1, 0.6, 0.2, 1)
                elseif lifePercent >= 70 then
                    lifeElement:setTextColor(0.4, 0.8, 0.4, 1)
                elseif lifePercent >= 40 then
                    lifeElement:setTextColor(1, 0.8, 0.2, 1)
                else
                    lifeElement:setTextColor(1, 0.5, 0.2, 1)
                end
                lifeElement:setText(statusStr)
            end
            if rowElement then rowElement:setVisible(true) end
        else
            if nameElement then nameElement:setText("") end
            if lifeElement then lifeElement:setText("") end
            if rowElement then rowElement:setVisible(false) end
        end
    end

    -- Show summary
    if self.rvbSummaryText ~= nil then
        local faultCount = 0
        local avgLife = 0
        for _, part in ipairs(allParts) do
            if part.fault then faultCount = faultCount + 1 end
            avgLife = avgLife + part.life
        end
        if #allParts > 0 then
            avgLife = avgLife / #allParts
        end

        local summary = string.format("Average Part Life: %d%% | Faults: %d",
            math.floor(avgLife * 100), faultCount)
        self.rvbSummaryText:setText(summary)
    end

    self:setStepVisibility(FieldServiceKitDialog.STEP_RVB_ANALYSIS)
end

--[[
    v2.8.0: Check if OBD diagnosis is available for a component
    Each system can only be diagnosed ONCE for a reliability boost (prevents spam exploit)
    Seizure repair is separate and always allowed
    @param component - "engine", "electrical", or "hydraulic"
    @return boolean - True if diagnosis is available, false if already used
]]
function FieldServiceKitDialog:isOBDDiagnosisAvailable(component)
    if self.vehicle == nil then return false end

    local maintSpec = self.vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return true end  -- No tracking = allow

    local obdUsed = maintSpec.obdDiagnosesUsed
    if obdUsed == nil then return true end  -- No tracking = allow

    if component == "engine" then
        return not obdUsed.engine
    elseif component == "electrical" then
        return not obdUsed.electrical
    elseif component == "hydraulic" then
        return not obdUsed.hydraulic
    end

    return true
end

--[[
    v2.8.0: Mark OBD diagnosis as used for a component
    @param component - "engine", "electrical", or "hydraulic"
]]
function FieldServiceKitDialog:markOBDDiagnosisUsed(component)
    if self.vehicle == nil then return end

    local maintSpec = self.vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return end

    maintSpec.obdDiagnosesUsed = maintSpec.obdDiagnosesUsed or {}

    if component == "engine" then
        maintSpec.obdDiagnosesUsed.engine = true
    elseif component == "electrical" then
        maintSpec.obdDiagnosesUsed.electrical = true
    elseif component == "hydraulic" then
        maintSpec.obdDiagnosesUsed.hydraulic = true
    end

    UsedPlus.logInfo(string.format("OBD diagnosis marked as used: %s", component))
end

--[[
    System selection button handlers
    v2.7.0: Modified to check for seizures first - offers repair instead of diagnosis if seized
    v2.8.0: Added check for one-time diagnosis limit
]]
function FieldServiceKitDialog:onEngineClick()
    -- v2.7.0: Check for engine seizure first (seizure repair is always allowed)
    if self:checkAndOfferSeizureRepair("engine") then
        return  -- Seizure repair dialog shown
    end

    -- v2.8.0: Check if diagnosis boost already used (one-time per system)
    if not self:isOBDDiagnosisAvailable("engine") then
        g_currentMission:showBlinkingWarning(
            g_i18n:getText("usedplus_fsk_diagnosis_exhausted") or
            "Engine already diagnosed - OBD boost exhausted. Shop repair available.",
            4000
        )
        return
    end

    self.selectedSystem = DiagnosisData.SYSTEM_ENGINE
    self.currentStep = FieldServiceKitDialog.STEP_DIAGNOSIS
    self:updateDisplay()
end

function FieldServiceKitDialog:onElectricalClick()
    -- v2.7.0: Check for electrical seizure first (seizure repair is always allowed)
    if self:checkAndOfferSeizureRepair("electrical") then
        return  -- Seizure repair dialog shown
    end

    -- v2.8.0: Check if diagnosis boost already used (one-time per system)
    if not self:isOBDDiagnosisAvailable("electrical") then
        g_currentMission:showBlinkingWarning(
            g_i18n:getText("usedplus_fsk_diagnosis_exhausted") or
            "Electrical already diagnosed - OBD boost exhausted. Shop repair available.",
            4000
        )
        return
    end

    self.selectedSystem = DiagnosisData.SYSTEM_ELECTRICAL
    self.currentStep = FieldServiceKitDialog.STEP_DIAGNOSIS
    self:updateDisplay()
end

function FieldServiceKitDialog:onHydraulicClick()
    -- v2.7.0: Check for hydraulic seizure first (seizure repair is always allowed)
    if self:checkAndOfferSeizureRepair("hydraulic") then
        return  -- Seizure repair dialog shown
    end

    -- v2.8.0: Check if diagnosis boost already used (one-time per system)
    if not self:isOBDDiagnosisAvailable("hydraulic") then
        g_currentMission:showBlinkingWarning(
            g_i18n:getText("usedplus_fsk_diagnosis_exhausted") or
            "Hydraulics already diagnosed - OBD boost exhausted. Shop repair available.",
            4000
        )
        return
    end

    self.selectedSystem = DiagnosisData.SYSTEM_HYDRAULIC
    self.currentStep = FieldServiceKitDialog.STEP_DIAGNOSIS
    self:updateDisplay()
end

function FieldServiceKitDialog:onTireClick()
    self.currentStep = FieldServiceKitDialog.STEP_TIRE_REPAIR
    self:updateDisplay()
end

--[[
    Diagnosis selection handlers
]]
function FieldServiceKitDialog:onDiagnosis1Click()
    self:applyRepair(1)
end

function FieldServiceKitDialog:onDiagnosis2Click()
    self:applyRepair(2)
end

function FieldServiceKitDialog:onDiagnosis3Click()
    self:applyRepair(3)
end

function FieldServiceKitDialog:onDiagnosis4Click()
    self:applyRepair(4)
end

--[[
    Hover effect handlers for diagnosis buttons
    Changes background color when mouse hovers over button
]]
function FieldServiceKitDialog:onDiagBtnHighlight(element)
    -- Derive background ID from button ID (diagBtn1 -> diagBtn1Bg)
    if element ~= nil and element.id ~= nil then
        local bgId = element.id .. "Bg"
        local bg = self[bgId]
        if bg ~= nil then
            -- Highlight color: lighter blue-ish
            bg:setImageColor(nil, 0.22, 0.28, 0.38, 1)
        end
    end
end

function FieldServiceKitDialog:onDiagBtnUnhighlight(element)
    -- Restore normal background color
    if element ~= nil and element.id ~= nil then
        local bgId = element.id .. "Bg"
        local bg = self[bgId]
        if bg ~= nil then
            -- Normal color (matches fskDiagBtnBg profile)
            bg:setImageColor(nil, 0.12, 0.12, 0.16, 1)
        end
    end
end

--[[
    v2.7.1: Hover effect handlers for mode selection buttons
    Changes background color when mouse hovers over button
]]
function FieldServiceKitDialog:onModeBtnHighlight(element)
    if element ~= nil and element.id ~= nil then
        -- Map button ID to background ID
        local bgMapping = {
            modeDiagnoseButton = "modeDiagnoseBg",
            modeMalfunctionsButton = "modeMalfunctionsBg",
            modeTireServiceButton = "modeTireServiceBg",
            modeRVBButton = "modeRVBBg"
        }
        local bgId = bgMapping[element.id]
        local bg = self[bgId]
        if bg ~= nil then
            -- Highlight color: lighter version of each box type
            if element.id == "modeMalfunctionsButton" then
                bg:setImageColor(nil, 0.28, 0.22, 0.12, 0.95)  -- Lighter warning orange
            elseif element.id == "modeRVBButton" then
                bg:setImageColor(nil, 0.16, 0.20, 0.28, 0.95)  -- Lighter tech blue
            else
                bg:setImageColor(nil, 0.20, 0.28, 0.20, 0.95)  -- Lighter green
            end
        end
    end
end

function FieldServiceKitDialog:onModeBtnUnhighlight(element)
    if element ~= nil and element.id ~= nil then
        -- Map button ID to background ID
        local bgMapping = {
            modeDiagnoseButton = "modeDiagnoseBg",
            modeMalfunctionsButton = "modeMalfunctionsBg",
            modeTireServiceButton = "modeTireServiceBg",
            modeRVBButton = "modeRVBBg"
        }
        local bgId = bgMapping[element.id]
        local bg = self[bgId]
        if bg ~= nil then
            -- Restore normal colors matching XML profiles
            if element.id == "modeMalfunctionsButton" then
                bg:setImageColor(nil, 0.18, 0.14, 0.08, 0.9)  -- fskModeBoxBgWarning
            elseif element.id == "modeRVBButton" then
                bg:setImageColor(nil, 0.10, 0.12, 0.16, 0.9)  -- fskModeBoxBgTech
            else
                bg:setImageColor(nil, 0.12, 0.15, 0.12, 0.9)  -- fskModeBoxBg
            end
        end
    end
end

--[[
    v2.7.1: Hover effect handlers for tire repair buttons
]]
function FieldServiceKitDialog:onTireBtnHighlight(element)
    if element ~= nil and element.id ~= nil then
        local bgMapping = {
            patchButton = "patchBtnBg",
            plugButton = "plugBtnBg"
        }
        local bgId = bgMapping[element.id]
        local bg = self[bgId]
        if bg ~= nil then
            -- Highlight color: lighter blue
            bg:setImageColor(nil, 0.22, 0.28, 0.38, 1)
        end
    end
end

function FieldServiceKitDialog:onTireBtnUnhighlight(element)
    if element ~= nil and element.id ~= nil then
        local bgMapping = {
            patchButton = "patchBtnBg",
            plugButton = "plugBtnBg"
        }
        local bgId = bgMapping[element.id]
        local bg = self[bgId]
        if bg ~= nil then
            -- Restore normal color (matches fskTireBtnBg profile)
            bg:setImageColor(nil, 0.12, 0.12, 0.16, 1)
        end
    end
end

--[[
    Apply the repair based on diagnosis choice
    v1.8.0: Also applies repairs to RVB parts when RVB is installed
    v2.8.0: Fixed exploit - now respects maxReliabilityCeiling and has OBD-specific cap
            OBD = field repair, can restore up to 80% (shop repair needed for higher)
]]
function FieldServiceKitDialog:applyRepair(diagnosisIndex)
    self.selectedDiagnosis = diagnosisIndex

    -- Calculate outcome
    self.repairResult = DiagnosisData.calculateOutcome(
        self.actualFailedSystem,
        self.selectedSystem,
        self.currentScenario,
        diagnosisIndex,
        self.kitTier
    )

    -- Apply repair to vehicle
    local maintSpec = self.vehicle.spec_usedPlusMaintenance
    if maintSpec ~= nil then
        -- v2.8.0: OBD Scanner is field repair - cannot restore to 100%
        -- Cap at 80% OR the vehicle's maxReliabilityCeiling, whichever is lower
        -- This prevents exploit of buying multiple kits to restore to 100%
        local OBD_MAX_RESTORE = 0.80  -- Field repair can only restore to 80%
        local vehicleCeiling = maintSpec.maxReliabilityCeiling or 1.0
        local effectiveCap = math.min(OBD_MAX_RESTORE, vehicleCeiling)

        -- Apply reliability boost to the ACTUAL failed system (not player's guess)
        if self.actualFailedSystem == DiagnosisData.SYSTEM_ENGINE then
            maintSpec.engineReliability = math.min(effectiveCap, maintSpec.engineReliability + self.repairResult.reliabilityBoost)

            -- v2.7.0: Engine repair can also fix fuel leaks (good/perfect outcome only)
            if maintSpec.hasFuelLeak and self.repairResult.outcome ~= DiagnosisData.OUTCOME_FAILED then
                if UsedPlusMaintenance and UsedPlusMaintenance.repairFuelLeak then
                    UsedPlusMaintenance.repairFuelLeak(self.vehicle)
                    UsedPlus.logInfo("OBD Scanner: Fuel leak repaired during engine diagnosis")
                end
            end
        elseif self.actualFailedSystem == DiagnosisData.SYSTEM_ELECTRICAL then
            maintSpec.electricalReliability = math.min(effectiveCap, maintSpec.electricalReliability + self.repairResult.reliabilityBoost)
        elseif self.actualFailedSystem == DiagnosisData.SYSTEM_HYDRAULIC then
            maintSpec.hydraulicReliability = math.min(effectiveCap, maintSpec.hydraulicReliability + self.repairResult.reliabilityBoost)
        end

        UsedPlus.logDebug(string.format("OBD repair cap: %.0f%% (vehicle ceiling: %.0f%%, OBD max: %.0f%%)",
            effectiveCap * 100, vehicleCeiling * 100, OBD_MAX_RESTORE * 100))

        -- If vehicle was disabled, restore to functional (barely)
        if maintSpec.isDisabled then
            maintSpec.isDisabled = false
            -- Set function level based on repair outcome
            -- This would require additional tracking in the maintenance spec
        end

        -- v1.8.0: Apply repairs to RVB parts if RVB is installed
        -- This is the key integration - successful OBD diagnosis reduces RVB operating hours
        if ModCompatibility.rvbInstalled then
            -- Calculate hours reduction based on repair quality
            -- Perfect diagnosis = 50 hours, Good = 25 hours, Partial = 10 hours
            local hoursReduction = 10
            local clearFaults = false

            if self.repairResult.outcome == DiagnosisData.OUTCOME_PERFECT then
                hoursReduction = 50
                clearFaults = true  -- Perfect diagnosis clears fault codes
            elseif self.repairResult.outcome == DiagnosisData.OUTCOME_GOOD then
                hoursReduction = 25
                clearFaults = true
            end

            -- Apply to RVB based on which system was diagnosed
            ModCompatibility.applyOBDRepairToRVB(
                self.vehicle,
                self.selectedSystem,  -- Use player's selected system (they chose to work on it)
                hoursReduction,
                clearFaults
            )

            UsedPlus.logInfo(string.format("RVB repair applied: %s hours reduced by %d, faults cleared: %s",
                self.selectedSystem, hoursReduction, tostring(clearFaults)))
        end

        UsedPlus.logInfo(string.format("Field repair applied: %s reliability +%.1f%%, outcome: %s",
            self.actualFailedSystem,
            self.repairResult.reliabilityBoost * 100,
            self.repairResult.outcome))

        -- v2.8.0: Mark diagnosis as used (one-time per system)
        -- Uses selectedSystem (what player chose to work on), not actualFailedSystem
        local componentMap = {
            [DiagnosisData.SYSTEM_ENGINE] = "engine",
            [DiagnosisData.SYSTEM_ELECTRICAL] = "electrical",
            [DiagnosisData.SYSTEM_HYDRAULIC] = "hydraulic"
        }
        local component = componentMap[self.selectedSystem]
        if component then
            self:markOBDDiagnosisUsed(component)
        end
    end

    -- Move to results step
    self.currentStep = FieldServiceKitDialog.STEP_RESULTS
    self:updateDisplay()
end

--[[
    Tire repair handlers
]]
function FieldServiceKitDialog:onTirePatchClick()
    self:applyTireRepair("patch")
end

function FieldServiceKitDialog:onTirePlugClick()
    self:applyTireRepair("plug")
end

function FieldServiceKitDialog:applyTireRepair(repairType)
    local result = DiagnosisData.calculateTireOutcome(repairType, self.kitTier)

    local maintSpec = self.vehicle.spec_usedPlusMaintenance
    if maintSpec ~= nil and maintSpec.tireConditions ~= nil then
        -- Find and repair the flat tire(s)
        for i, condition in pairs(maintSpec.tireConditions) do
            if condition <= 0.01 then
                maintSpec.tireConditions[i] = result.conditionRestore
                UsedPlus.logInfo(string.format("Tire %d repaired with %s: %.0f%% condition",
                    i, repairType, result.conditionRestore * 100))
            end
        end
    end

    -- v2.7.0: Clear the flat tire state after field repair
    if self.hasFlatTire and UsedPlusMaintenance and UsedPlusMaintenance.repairFlatTire then
        UsedPlusMaintenance.repairFlatTire(self.vehicle)
        UsedPlus.logInfo(string.format("Flat tire state cleared via %s repair", repairType))
    end

    -- Consume kit and close
    self:consumeAndClose()
end

--[[
    OK button - close and consume kit
    Note: Button callback from XML onClick="onOkClick"
]]
function FieldServiceKitDialog:onOkClick()
    UsedPlus.logInfo("FieldServiceKitDialog: OK button clicked")
    self:consumeAndClose()
end

--[[
    Cancel button - close dialog
    Note: Kit is only consumed when repair is actually completed via OK button
]]
function FieldServiceKitDialog:onCancelClick()
    UsedPlus.logInfo("FieldServiceKitDialog: Cancel clicked, currentStep=" .. tostring(self.currentStep))
    self:close()
end

--[[
    Consume the kit and close dialog
]]
function FieldServiceKitDialog:consumeAndClose()
    UsedPlus.logInfo("FieldServiceKitDialog: consumeAndClose called")

    -- Tell kit to consume itself
    if self.kit ~= nil then
        UsedPlus.logInfo("FieldServiceKitDialog: Consuming kit")
        self.kit:consumeKit()
    else
        UsedPlus.logInfo("FieldServiceKitDialog: No kit reference to consume")
    end

    self:close()
end

function FieldServiceKitDialog:close()
    UsedPlus.logInfo("FieldServiceKitDialog: Closing dialog")
    g_gui:closeDialogByName("FieldServiceKitDialog")
end

-- ===========================================================================
-- v2.7.0: SEIZURE REPAIR SYSTEM
-- OBD Scanner can detect and repair seized components
-- ===========================================================================

--[[
    Check if vehicle has any seized components
    @return table - {engine=bool, hydraulic=bool, electrical=bool}
]]
function FieldServiceKitDialog:getSeizedComponents()
    local result = {engine = false, hydraulic = false, electrical = false}

    if self.vehicle == nil then return result end

    local maintSpec = self.vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return result end

    result.engine = maintSpec.engineSeized or false
    result.hydraulic = maintSpec.hydraulicsSeized or false
    result.electrical = maintSpec.electricalSeized or false

    return result
end

--[[
    Check if vehicle has ANY seized component
    @return boolean
]]
function FieldServiceKitDialog:hasAnySeizure()
    local seized = self:getSeizedComponents()
    return seized.engine or seized.hydraulic or seized.electrical
end

--[[
    Calculate repair cost for a seized component
    @param component - "engine", "hydraulic", or "electrical"
    @return number - Cost in currency
]]
function FieldServiceKitDialog:getSeizureRepairCost(component)
    if self.vehicle == nil then return 0 end

    -- Get vehicle price
    local storeItem = g_storeManager:getItemByXMLFilename(self.vehicle.configFileName)
    local vehiclePrice = 50000  -- Default fallback
    if storeItem ~= nil then
        vehiclePrice = storeItem.price or 50000
    end

    -- Cost = 5% of vehicle price per component (configurable)
    local costMult = UsedPlusMaintenance.CONFIG.seizureRepairCostMult or 0.05
    return math.floor(vehiclePrice * costMult)
end

--[[
    Repair a seized component
    @param component - "engine", "hydraulic", or "electrical"
    @return boolean - True if repair succeeded
]]
function FieldServiceKitDialog:repairSeizedComponent(component)
    if self.vehicle == nil then return false end

    local maintSpec = self.vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return false end

    -- Check player has enough money
    local cost = self:getSeizureRepairCost(component)
    local farm = g_farmManager:getFarmById(g_currentMission:getFarmId())
    if farm == nil then return false end

    if farm.money < cost then
        -- Not enough money (client-side validation for immediate user feedback)
        g_currentMission:showBlinkingWarning(
            g_i18n:getText("usedplus_repair_no_money") or "Not enough money for repair!",
            3000
        )
        return false
    end

    -- v2.8.0: Use network event for multiplayer synchronization
    -- Event handles: money deduction, seizure clearing, reliability restoration, and syncs to all clients
    FieldRepairEvent.sendToServer(
        g_currentMission:getFarmId(),
        self.vehicle.id,
        component,
        cost
    )

    -- Show success message (event handles the actual repair on server)
    local componentName = g_i18n:getText("usedplus_component_" .. component) or component
    local minReliability = UsedPlusMaintenance.CONFIG.seizureRepairMinReliability or 0.30
    local message = string.format(
        g_i18n:getText("usedplus_seizure_repaired") or "%s repaired! Reliability restored to %d%%",
        componentName,
        math.floor(minReliability * 100)
    )
    g_currentMission:showBlinkingWarning(message, 3000)

    UsedPlus.logInfo(string.format("Seizure repair requested: %s for $%d (sent to server)",
        component, cost))

    return true
end

--[[
    Modified system click handler that checks for seizure first
    If component is seized, offers repair instead of diagnosis
    @param component - "engine", "hydraulic", or "electrical"
    @return boolean - True if seized (repair offered), false to proceed with normal diagnosis
]]
function FieldServiceKitDialog:checkAndOfferSeizureRepair(component)
    local seized = self:getSeizedComponents()

    local isSeized = false
    if component == "engine" then
        isSeized = seized.engine
    elseif component == "hydraulic" then
        isSeized = seized.hydraulic
    elseif component == "electrical" then
        isSeized = seized.electrical
    end

    if not isSeized then
        return false  -- Not seized, proceed with normal diagnosis
    end

    -- Component is seized - offer repair
    local cost = self:getSeizureRepairCost(component)
    local componentName = g_i18n:getText("usedplus_component_" .. component) or component

    -- Show confirmation dialog
    local title = g_i18n:getText("usedplus_seizure_detected") or "COMPONENT SEIZED"
    local text = string.format(
        g_i18n:getText("usedplus_seizure_repair_confirm") or
        "%s is seized and requires emergency repair.\n\nRepair cost: %s\n\nProceed with repair?",
        componentName,
        g_i18n:formatMoney(cost, 0, true, true)
    )

    -- Store component for callback
    self.pendingSeizureRepair = component

    -- Set bypass flag so VehicleSellingPointExtension doesn't intercept this dialog
    if VehicleSellingPointExtension then
        VehicleSellingPointExtension.bypassInterception = true
    end

    -- Show confirmation dialog using proper FS25 pattern (g_gui:showDialog, not showYesNoDialog)
    local dialog = g_gui:showDialog("YesNoDialog")
    if dialog and dialog.target then
        dialog.target:setTitle(title)
        dialog.target:setText(text)
        dialog.target:setCallback(self.onSeizureRepairConfirm, self)
    end

    return true  -- Seizure repair offered
end

--[[
    Callback for seizure repair confirmation dialog
]]
function FieldServiceKitDialog:onSeizureRepairConfirm(yes)
    if yes and self.pendingSeizureRepair ~= nil then
        local success = self:repairSeizedComponent(self.pendingSeizureRepair)
        if success then
            -- Consume kit and close dialog
            self:consumeAndClose()
        end
    end
    self.pendingSeizureRepair = nil
end
