--[[
    FS25_UsedPlus - Service Truck Dialog ("The Workshop Order")

    Full redesign v2.15.0 - Warm amber mechanic aesthetic.
    Inspection minigame dialog for starting long-term vehicle restoration.

    Steps:
    1. Component Selection - Pick which system to restore (with DDS icons, hover effects)
    2. Inspection - View symptoms in terminal readout, choose diagnosis from 2x2 grid
    3. Results - Success shows detail + Start Restoration; Failure shows cooldown
]]

ServiceTruckDialog = {}
local ServiceTruckDialog_mt = Class(ServiceTruckDialog, MessageDialog)

-- Registration
ServiceTruckDialog.instance = nil
ServiceTruckDialog.xmlPath = nil

-- Dialog steps
ServiceTruckDialog.STEP_COMPONENT = 1
ServiceTruckDialog.STEP_INSPECTION = 2
ServiceTruckDialog.STEP_RESULTS = 3

-- Color palette
ServiceTruckDialog.COLOR_COMPONENT_BASE = { 0.08, 0.08, 0.10, 0.9 }
ServiceTruckDialog.COLOR_DIAG_BASE = { 0.12, 0.12, 0.16, 1 }
ServiceTruckDialog.COLOR_START_BASE = { 0.12, 0.30, 0.12, 0.95 }
ServiceTruckDialog.COLOR_SUCCESS_BG = { 0.08, 0.20, 0.08, 0.95 }
ServiceTruckDialog.COLOR_FAILURE_BG = { 0.25, 0.06, 0.06, 0.95 }
ServiceTruckDialog.HOVER_BRIGHTEN = 0.08

-- Icon filenames
ServiceTruckDialog.COMPONENT_ICONS = {
    engine = "sys_engine.dds",
    electrical = "sys_electrical.dds",
    hydraulic = "sys_hydraulic.dds"
}

function ServiceTruckDialog.brightenColor(color)
    local b = ServiceTruckDialog.HOVER_BRIGHTEN
    return {
        math.min(color[1] + b, 1.0),
        math.min(color[2] + b, 1.0),
        math.min(color[3] + b, 1.0),
        color[4]
    }
end

-- ============================================================
--- Registration
-- ============================================================

function ServiceTruckDialog.register()
    if ServiceTruckDialog.instance == nil then
        UsedPlus.logInfo("ServiceTruckDialog: Registering dialog")

        if ServiceTruckDialog.xmlPath == nil then
            ServiceTruckDialog.xmlPath = UsedPlus.MOD_DIR .. "gui/ServiceTruckDialog.xml"
        end

        ServiceTruckDialog.instance = ServiceTruckDialog.new()
        g_gui:loadGui(ServiceTruckDialog.xmlPath, "ServiceTruckDialog", ServiceTruckDialog.instance)

        UsedPlus.logInfo("ServiceTruckDialog: Registration complete")
    end
end

function ServiceTruckDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or ServiceTruckDialog_mt)

    self.vehicle = nil
    self.serviceTruck = nil
    self.currentStep = ServiceTruckDialog.STEP_COMPONENT
    self.selectedComponent = nil
    self.currentScenario = nil
    self.selectedDiagnosis = nil
    self.inspectionResult = nil

    return self
end

function ServiceTruckDialog:onOpen()
    ServiceTruckDialog:superClass().onOpen(self)
    self:updateDisplay()
end

function ServiceTruckDialog:onCreate()
    ServiceTruckDialog:superClass().onCreate(self)

    local iconDir = UsedPlus.MOD_DIR .. "gui/icons/"

    -- Header icon
    if self.headerIcon ~= nil then
        self.headerIcon:setImageFilename(iconDir .. "service_truck.dds")
    end

    -- Component icons (Step 1)
    if self.engineIcon ~= nil then
        self.engineIcon:setImageFilename(iconDir .. "sys_engine.dds")
    end
    if self.electricalIcon ~= nil then
        self.electricalIcon:setImageFilename(iconDir .. "sys_electrical.dds")
    end
    if self.hydraulicIcon ~= nil then
        self.hydraulicIcon:setImageFilename(iconDir .. "sys_hydraulic.dds")
    end
end

-- ============================================================
--- Data & Display
-- ============================================================

function ServiceTruckDialog:setData(vehicle, serviceTruck)
    self.vehicle = vehicle
    self.serviceTruck = serviceTruck
    self.currentStep = ServiceTruckDialog.STEP_COMPONENT
    self.selectedComponent = nil
    self.currentScenario = nil
    self.selectedDiagnosis = nil
    self.inspectionResult = nil

    self:updateDisplay()
end

function ServiceTruckDialog:updateDisplay()
    if self.vehicle == nil then return end

    -- Hide all step containers
    if self.componentContainer then self.componentContainer:setVisible(false) end
    if self.inspectionContainer then self.inspectionContainer:setVisible(false) end
    if self.resultsContainer then self.resultsContainer:setVisible(false) end

    -- Single buttonBack (ESC keybind): text changes per step
    if self.okButton then
        if self.currentStep == ServiceTruckDialog.STEP_INSPECTION then
            self.okButton:setText(g_i18n:getText("button_back") or "Back")
        else
            self.okButton:setText(g_i18n:getText("button_close") or "Close")
        end
    end

    local vehicleName = self.vehicle:getName() or "Vehicle"

    if self.currentStep == ServiceTruckDialog.STEP_COMPONENT then
        self:displayComponentSelection(vehicleName)
    elseif self.currentStep == ServiceTruckDialog.STEP_INSPECTION then
        self:displayInspection()
    elseif self.currentStep == ServiceTruckDialog.STEP_RESULTS then
        self:displayResults()
    end
end

-- ============================================================
--- Step 1: Component Selection
-- ============================================================

function ServiceTruckDialog:displayComponentSelection(vehicleName)
    if self.componentContainer then
        self.componentContainer:setVisible(true)
    end

    -- Vehicle name
    if self.vehicleNameText then
        self.vehicleNameText:setText(vehicleName)
    end

    local maintSpec = self.vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return end

    -- Reliability values
    local engineRel = math.floor((maintSpec.engineReliability or 1.0) * 100)
    local electricalRel = math.floor((maintSpec.electricalReliability or 1.0) * 100)
    local hydraulicRel = math.floor((maintSpec.hydraulicReliability or 1.0) * 100)
    local ceiling = math.floor((maintSpec.maxReliabilityCeiling or 1.0) * 100)

    -- Ceiling text
    if self.ceilingText then
        self.ceilingText:setText(string.format(g_i18n:getText("usedplus_serviceTruck_ceiling") or "Max Potential: %d%%", ceiling))
    end

    -- Count degraded components
    local degradedCount = 0
    if engineRel < 90 then degradedCount = degradedCount + 1 end
    if electricalRel < 90 then degradedCount = degradedCount + 1 end
    if hydraulicRel < 90 then degradedCount = degradedCount + 1 end
    if self.degradedCountText then
        self.degradedCountText:setText(string.format(g_i18n:getText("usedplus_st_degradedCount"), degradedCount, degradedCount == 1 and "" or "s"))
    end

    -- Update component displays
    self:updateComponentBox("engine", engineRel, maintSpec.engineReliability or 1.0, RestorationData.SYSTEM_ENGINE)
    self:updateComponentBox("electrical", electricalRel, maintSpec.electricalReliability or 1.0, RestorationData.SYSTEM_ELECTRICAL)
    self:updateComponentBox("hydraulic", hydraulicRel, maintSpec.hydraulicReliability or 1.0, RestorationData.SYSTEM_HYDRAULIC)

    -- Update resources
    self:updateResourceDisplay()
end

function ServiceTruckDialog:updateComponentBox(name, percent, rawReliability, systemType)
    local valueText = self[name .. "ReliabilityText"]
    local statusText = self[name .. "StatusText"]
    local button = self[name .. "Btn"]
    local bg = self[name .. "Bg"]

    -- Set reliability value with color
    if valueText then
        valueText:setText(tostring(percent) .. "%")
        self:setReliabilityColor(valueText, percent)
    end

    -- Set status text
    if statusText then
        local onCooldown, timeRemaining = RestorationData.isOnCooldown(self.vehicle, systemType)
        if onCooldown then
            local hoursRemaining = math.ceil(timeRemaining / (60 * 1000))
            statusText:setText(string.format(g_i18n:getText("usedplus_serviceTruck_cooldown") or "Cooldown: %dh", hoursRemaining))
            statusText:setTextColor(0.9, 0.6, 0.15, 1)
            if button then button:setDisabled(true) end
        elseif percent >= 90 then
            statusText:setText(g_i18n:getText("usedplus_serviceTruck_healthy") or "Healthy")
            statusText:setTextColor(0.5, 0.5, 0.5, 1)
            if button then button:setDisabled(true) end
        else
            local statusLabel = self:getStatusLabel(percent)
            statusText:setText(statusLabel)
            statusText:setTextColor(0.6, 0.6, 0.6, 1)
            if button then button:setDisabled(false) end
        end
    end

    -- Set background tint based on reliability
    if bg then
        self:setComponentBgColor(bg, percent)
    end
end

function ServiceTruckDialog:getStatusLabel(percent)
    if percent >= 75 then
        return g_i18n:getText("usedplus_st_statusGood")
    elseif percent >= 50 then
        return g_i18n:getText("usedplus_st_statusDegraded")
    elseif percent >= 25 then
        return g_i18n:getText("usedplus_st_statusPoor")
    else
        return g_i18n:getText("usedplus_st_statusCritical")
    end
end

function ServiceTruckDialog:setReliabilityColor(textElement, percent)
    if textElement == nil then return end
    if percent >= 75 then
        textElement:setTextColor(0.3, 1.0, 0.3, 1)  -- Healthy green
    elseif percent >= 50 then
        textElement:setTextColor(1.0, 0.8, 0.2, 1)  -- Degraded amber
    else
        textElement:setTextColor(1.0, 0.3, 0.3, 1)  -- Critical red
    end
end

function ServiceTruckDialog:setComponentBgColor(bg, percent)
    if bg == nil then return end
    if percent >= 90 then
        bg:setImageColor(nil, 0.08, 0.08, 0.10, 0.9)    -- Neutral
    elseif percent >= 75 then
        bg:setImageColor(nil, 0.08, 0.12, 0.08, 0.9)    -- Slight green tint
    elseif percent >= 50 then
        bg:setImageColor(nil, 0.14, 0.12, 0.06, 0.9)    -- Amber tint
    else
        bg:setImageColor(nil, 0.16, 0.06, 0.06, 0.9)    -- Red tint
    end
end

function ServiceTruckDialog:updateResourceDisplay()
    if self.serviceTruck == nil then return end

    local spec = self.serviceTruck.spec_serviceTruck
    if spec == nil then return end

    local dieselLevel = self.serviceTruck:getFillUnitFillLevel(spec.dieselFillUnit) or 0
    local oilLevel = self.serviceTruck:getFillUnitFillLevel(spec.oilFillUnit) or 0
    local hydraulicLevel = self.serviceTruck:getFillUnitFillLevel(spec.hydraulicFillUnit) or 0
    local partsAvailable = spec.totalPartsAvailable or 0

    if self.dieselLevelText then
        self.dieselLevelText:setText(string.format("%.0fL", dieselLevel))
    end
    if self.oilLevelText then
        self.oilLevelText:setText(string.format("%.0fL", oilLevel))
    end
    if self.hydraulicLevelText then
        self.hydraulicLevelText:setText(string.format("%.0fL", hydraulicLevel))
    end
    if self.partsLevelText then
        self.partsLevelText:setText(string.format("%.0f", partsAvailable))
        if partsAvailable < 10 then
            self.partsLevelText:setTextColor(1.0, 0.3, 0.3, 1)  -- Red warning
        else
            self.partsLevelText:setTextColor(1, 1, 1, 1)
        end
    end
end

-- ============================================================
--- Step 2: Inspection
-- ============================================================

function ServiceTruckDialog:displayInspection()
    if self.inspectionContainer then
        self.inspectionContainer:setVisible(true)
    end

    -- Set inspection header icon based on selected component
    local iconDir = UsedPlus.MOD_DIR .. "gui/icons/"
    if self.inspectComponentIcon then
        local iconFile = ServiceTruckDialog.COMPONENT_ICONS[self.selectedComponent] or "sys_engine.dds"
        self.inspectComponentIcon:setImageFilename(iconDir .. iconFile)
    end

    -- Get scenario
    local maintSpec = self.vehicle.spec_usedPlusMaintenance
    local reliability = 1.0
    if self.selectedComponent == RestorationData.SYSTEM_ENGINE then
        reliability = maintSpec.engineReliability or 1.0
    elseif self.selectedComponent == RestorationData.SYSTEM_ELECTRICAL then
        reliability = maintSpec.electricalReliability or 1.0
    elseif self.selectedComponent == RestorationData.SYSTEM_HYDRAULIC then
        reliability = maintSpec.hydraulicReliability or 1.0
    end

    self.currentScenario = RestorationData.getScenarioForReliability(self.selectedComponent, reliability)

    if self.currentScenario == nil then
        UsedPlus.logError("ServiceTruckDialog: No scenario found for " .. tostring(self.selectedComponent))
        return
    end

    -- Display component name
    if self.inspectingText then
        local componentName = g_i18n:getText("usedplus_component_" .. self.selectedComponent) or self.selectedComponent
        self.inspectingText:setText(string.format(g_i18n:getText("usedplus_serviceTruck_inspecting") or "Inspecting: %s", componentName))
    end

    -- Estimated time
    if self.estimatedTimeText then
        local hours = self.currentScenario.restorationHours or 48
        self.estimatedTimeText:setText(string.format(g_i18n:getText("usedplus_serviceTruck_estimatedTime") or "Estimated restoration: %d hours", hours))
    end

    -- Display symptoms with > prefix (not bullet — doesn't render in FS25 font)
    for i = 1, 3 do
        local symptomText = self["symptom" .. i .. "Text"]
        if symptomText then
            local symptomKey = self.currentScenario.symptoms[i]
            local symptom = symptomKey and g_i18n:getText(symptomKey) or ""
            if symptom ~= "" then
                symptomText:setText("> " .. symptom)
            else
                symptomText:setText("")
            end
        end
    end

    -- Display hints
    local hints = RestorationData.getSystemHints(self.selectedComponent, 2)
    for i = 1, 2 do
        local hintText = self["hint" .. i .. "Text"]
        if hintText then
            local hint = hints[i] and g_i18n:getText(hints[i]) or ""
            if hint ~= "" then
                hintText:setText(g_i18n:getText("usedplus_st_hintPrefix") .. hint)
            else
                hintText:setText("")
            end
        end
    end

    -- Display diagnosis options
    for i = 1, 4 do
        local diagText = self["diagnosisText" .. i]
        if diagText then
            local diagKey = self.currentScenario.diagnoses[i]
            local diagLabel = diagKey and g_i18n:getText(diagKey) or ("Option " .. i)
            diagText:setText(diagLabel)
        end
    end
end

-- ============================================================
--- Step 3: Results
-- ============================================================

function ServiceTruckDialog:displayResults()
    if self.resultsContainer then
        self.resultsContainer:setVisible(true)
    end

    if self.inspectionResult == nil then return end

    local isSuccess = self.inspectionResult.outcome == RestorationData.OUTCOME_SUCCESS

    -- Result banner background color
    if self.resultBannerBg then
        if isSuccess then
            local c = ServiceTruckDialog.COLOR_SUCCESS_BG
            self.resultBannerBg:setImageColor(nil, c[1], c[2], c[3], c[4])
        else
            local c = ServiceTruckDialog.COLOR_FAILURE_BG
            self.resultBannerBg:setImageColor(nil, c[1], c[2], c[3], c[4])
        end
    end

    -- Result icon (checkmark or X)
    if self.resultIconText then
        if isSuccess then
            self.resultIconText:setText(g_i18n:getText("usedplus_st_diagnosisCorrect"))
            self.resultIconText:setTextColor(0.3, 1.0, 0.3, 1)
        else
            self.resultIconText:setText(g_i18n:getText("usedplus_st_diagnosisIncorrect"))
            self.resultIconText:setTextColor(1.0, 0.3, 0.3, 1)
        end
    end

    -- Result title
    if self.resultHeaderText then
        if isSuccess then
            self.resultHeaderText:setText(g_i18n:getText("usedplus_st_restorationCanBegin"))
        else
            self.resultHeaderText:setText(g_i18n:getText("usedplus_st_symptomsMismatch"))
        end
    end

    -- Result message
    if self.resultMessageText then
        if isSuccess then
            local hours = self.inspectionResult.estimatedHours or 48
            self.resultMessageText:setText(string.format(g_i18n:getText("usedplus_st_estimatedTimeResult"), hours))
        else
            self.resultMessageText:setText(g_i18n:getText("usedplus_st_cooldownApplied"))
        end
    end

    -- Success-only sections
    if self.detailSection then self.detailSection:setVisible(isSuccess) end
    if self.requirementsSection then self.requirementsSection:setVisible(isSuccess) end
    if self.startRestorationBox then self.startRestorationBox:setVisible(isSuccess) end

    -- Failure-only sections
    if self.cooldownSection then self.cooldownSection:setVisible(not isSuccess) end

    if isSuccess then
        self:displaySuccessDetails()
    else
        self:displayFailureDetails()
    end
end

function ServiceTruckDialog:displaySuccessDetails()
    -- Set detail icon
    local iconDir = UsedPlus.MOD_DIR .. "gui/icons/"
    if self.detailComponentIcon then
        local iconFile = ServiceTruckDialog.COMPONENT_ICONS[self.selectedComponent] or "sys_engine.dds"
        self.detailComponentIcon:setImageFilename(iconDir .. iconFile)
    end

    -- Component name
    if self.detailComponentName then
        local componentName = g_i18n:getText("usedplus_component_" .. self.selectedComponent) or self.selectedComponent
        self.detailComponentName:setText(string.upper(componentName))
    end

    -- Current → Target
    if self.detailCurrentText then
        local maintSpec = self.vehicle.spec_usedPlusMaintenance
        local reliability = 1.0
        if self.selectedComponent == RestorationData.SYSTEM_ENGINE then
            reliability = maintSpec.engineReliability or 1.0
        elseif self.selectedComponent == RestorationData.SYSTEM_ELECTRICAL then
            reliability = maintSpec.electricalReliability or 1.0
        elseif self.selectedComponent == RestorationData.SYSTEM_HYDRAULIC then
            reliability = maintSpec.hydraulicReliability or 1.0
        end
        local currentPct = math.floor(reliability * 100)
        self.detailCurrentText:setText(string.format(g_i18n:getText("usedplus_st_currentTarget"), currentPct))
    end

    -- Vehicle name
    if self.detailVehicleText then
        self.detailVehicleText:setText(string.format(g_i18n:getText("usedplus_st_vehicleLabel"), self.vehicle:getName() or g_i18n:getText("usedplus_common_unknown")))
    end

    -- Requirements
    if self.reqPartsText then
        local spec = self.serviceTruck and self.serviceTruck.spec_serviceTruck
        local partsAvailable = spec and spec.totalPartsAvailable or 0
        local hasParts = partsAvailable >= 10
        self.reqPartsText:setText(string.format(g_i18n:getText("usedplus_st_sparePartsAvailable"), partsAvailable, hasParts and "" or g_i18n:getText("usedplus_st_low")))
        if not hasParts then
            self.reqPartsText:setTextColor(1.0, 0.3, 0.3, 1)
        else
            self.reqPartsText:setTextColor(0.8, 0.8, 0.8, 1)
        end
    end
    if self.reqFluidsText then
        self.reqFluidsText:setText(g_i18n:getText("usedplus_st_fluidsConsumed"))
    end

    -- Disable start button if insufficient resources
    if self.startBtn then
        local spec = self.serviceTruck and self.serviceTruck.spec_serviceTruck
        local partsAvailable = spec and spec.totalPartsAvailable or 0
        self.startBtn:setDisabled(partsAvailable < 10)
    end
end

function ServiceTruckDialog:displayFailureDetails()
    if self.cooldownText then
        local cooldownHours = RestorationData.FAILED_DIAGNOSIS_COOLDOWN / (60 * 1000)
        self.cooldownText:setText(string.format(g_i18n:getText("usedplus_st_cooldownMessage"), cooldownHours))
    end
end

-- ============================================================
--- Component Click Handlers
-- ============================================================

function ServiceTruckDialog:onEngineClick()
    self.selectedComponent = RestorationData.SYSTEM_ENGINE
    self.currentStep = ServiceTruckDialog.STEP_INSPECTION
    self:updateDisplay()
end

function ServiceTruckDialog:onElectricalClick()
    self.selectedComponent = RestorationData.SYSTEM_ELECTRICAL
    self.currentStep = ServiceTruckDialog.STEP_INSPECTION
    self:updateDisplay()
end

function ServiceTruckDialog:onHydraulicClick()
    self.selectedComponent = RestorationData.SYSTEM_HYDRAULIC
    self.currentStep = ServiceTruckDialog.STEP_INSPECTION
    self:updateDisplay()
end

-- ============================================================
--- Diagnosis Click Handlers
-- ============================================================

function ServiceTruckDialog:onDiagnosis1Click()
    self:processDiagnosis(1)
end

function ServiceTruckDialog:onDiagnosis2Click()
    self:processDiagnosis(2)
end

function ServiceTruckDialog:onDiagnosis3Click()
    self:processDiagnosis(3)
end

function ServiceTruckDialog:onDiagnosis4Click()
    self:processDiagnosis(4)
end

function ServiceTruckDialog:processDiagnosis(choice)
    self.selectedDiagnosis = choice

    -- Calculate outcome
    self.inspectionResult = RestorationData.calculateInspectionOutcome(self.currentScenario, choice)

    -- Apply cooldown if failed
    if self.inspectionResult.outcome == RestorationData.OUTCOME_FAILED then
        RestorationData.setCooldown(self.vehicle, self.selectedComponent, self.inspectionResult.cooldownEnd)
    end

    self.currentStep = ServiceTruckDialog.STEP_RESULTS
    self:updateDisplay()
end

-- ============================================================
--- Start Restoration
-- ============================================================

function ServiceTruckDialog:onStartRestorationClick()
    if self.serviceTruck ~= nil and self.vehicle ~= nil and self.selectedComponent ~= nil then
        local success = self.serviceTruck:startRestoration(self.vehicle, self.selectedComponent)

        if success then
            self:close()
        end
    end
end

-- ============================================================
--- Hover Effects
-- ============================================================

function ServiceTruckDialog:onComponentHighlight(element)
    if element == nil or element.id == nil then return end
    local bgId = element.id:gsub("Btn$", "Bg")
    local bg = self[bgId]
    if bg == nil or bg.setImageColor == nil then return end

    -- Get reliability percent for this component to determine base color
    local maintSpec = self.vehicle and self.vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return end

    local percent = 100
    if element.id == "engineBtn" then
        percent = (maintSpec.engineReliability or 1.0) * 100
    elseif element.id == "electricalBtn" then
        percent = (maintSpec.electricalReliability or 1.0) * 100
    elseif element.id == "hydraulicBtn" then
        percent = (maintSpec.hydraulicReliability or 1.0) * 100
    end

    local base
    if percent >= 90 then
        base = { 0.08, 0.08, 0.10, 0.9 }
    elseif percent >= 75 then
        base = { 0.08, 0.12, 0.08, 0.9 }
    elseif percent >= 50 then
        base = { 0.14, 0.12, 0.06, 0.9 }
    else
        base = { 0.16, 0.06, 0.06, 0.9 }
    end
    local bright = ServiceTruckDialog.brightenColor(base)
    bg:setImageColor(nil, bright[1], bright[2], bright[3], bright[4])
end

function ServiceTruckDialog:onComponentUnhighlight(element)
    if element == nil or element.id == nil then return end
    local bgId = element.id:gsub("Btn$", "Bg")
    local bg = self[bgId]
    if bg == nil or bg.setImageColor == nil then return end

    local maintSpec = self.vehicle and self.vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return end

    local percent = 100
    if element.id == "engineBtn" then
        percent = (maintSpec.engineReliability or 1.0) * 100
    elseif element.id == "electricalBtn" then
        percent = (maintSpec.electricalReliability or 1.0) * 100
    elseif element.id == "hydraulicBtn" then
        percent = (maintSpec.hydraulicReliability or 1.0) * 100
    end
    self:setComponentBgColor(bg, percent)
end

function ServiceTruckDialog:onDiagHighlight(element)
    if element == nil or element.id == nil then return end
    local bgId = element.id:gsub("Btn$", "Bg")
    local bg = self[bgId]
    if bg == nil or bg.setImageColor == nil then return end

    local base = ServiceTruckDialog.COLOR_DIAG_BASE
    local bright = ServiceTruckDialog.brightenColor(base)
    bg:setImageColor(nil, bright[1], bright[2], bright[3], bright[4])
end

function ServiceTruckDialog:onDiagUnhighlight(element)
    if element == nil or element.id == nil then return end
    local bgId = element.id:gsub("Btn$", "Bg")
    local bg = self[bgId]
    if bg == nil or bg.setImageColor == nil then return end

    local base = ServiceTruckDialog.COLOR_DIAG_BASE
    bg:setImageColor(nil, base[1], base[2], base[3], base[4])
end

function ServiceTruckDialog:onStartHighlight(element)
    if self.startBtnBg == nil or self.startBtnBg.setImageColor == nil then return end
    local base = ServiceTruckDialog.COLOR_START_BASE
    local bright = ServiceTruckDialog.brightenColor(base)
    self.startBtnBg:setImageColor(nil, bright[1], bright[2], bright[3], bright[4])
end

function ServiceTruckDialog:onStartUnhighlight(element)
    if self.startBtnBg == nil or self.startBtnBg.setImageColor == nil then return end
    local base = ServiceTruckDialog.COLOR_START_BASE
    self.startBtnBg:setImageColor(nil, base[1], base[2], base[3], base[4])
end

-- ============================================================
--- Navigation
-- ============================================================

function ServiceTruckDialog:onClickOk()
    if self.currentStep == ServiceTruckDialog.STEP_INSPECTION then
        -- Go back to component selection
        self.currentStep = ServiceTruckDialog.STEP_COMPONENT
        self.currentScenario = nil
        self:updateDisplay()
    else
        self:close()
    end
end

UsedPlus.logInfo("ServiceTruckDialog class loaded")
