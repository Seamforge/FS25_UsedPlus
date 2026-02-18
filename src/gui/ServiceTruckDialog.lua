--[[
    FS25_UsedPlus - Service Truck Dialog

    Inspection minigame dialog for starting long-term vehicle restoration.
    Unlike OBD Scanner (instant repairs), this dialog determines if restoration
    can BEGIN - the actual restoration takes hours/days of game time.

    Steps:
    1. Component Selection - Pick which system to restore
    2. Inspection - View symptoms and diagnose the issue
    3. Results - Success allows restoration, failure applies 48hr cooldown

    v2.9.0 - Service Truck System
]]

ServiceTruckDialog = {}
local ServiceTruckDialog_mt = Class(ServiceTruckDialog, MessageDialog)

-- Registration pattern
ServiceTruckDialog.instance = nil
ServiceTruckDialog.xmlPath = nil

-- Dialog steps
ServiceTruckDialog.STEP_COMPONENT = 1
ServiceTruckDialog.STEP_INSPECTION = 2
ServiceTruckDialog.STEP_RESULTS = 3

--[[
    Register the dialog with g_gui
]]
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

    -- v2.14.2: Set header icon dynamically (ZIP-safe pattern)
    local headerIcon = self.dialogElement:getDescendantById("headerIcon")
    if headerIcon ~= nil then
        headerIcon:setImageFilename(UsedPlus.MOD_DIR .. "gui/icons/service_truck.png")
    end
end

--[[
    Set data for the dialog
    @param vehicle - The target vehicle to restore
    @param serviceTruck - The service truck performing the restoration
]]
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

--[[
    Update the dialog display based on current step
]]
function ServiceTruckDialog:updateDisplay()
    if self.vehicle == nil then return end

    -- Hide all step containers
    if self.componentContainer then self.componentContainer:setVisible(false) end
    if self.inspectionContainer then self.inspectionContainer:setVisible(false) end
    if self.resultsContainer then self.resultsContainer:setVisible(false) end

    local vehicleName = self.vehicle:getName() or "Vehicle"

    if self.currentStep == ServiceTruckDialog.STEP_COMPONENT then
        self:displayComponentSelection(vehicleName)
    elseif self.currentStep == ServiceTruckDialog.STEP_INSPECTION then
        self:displayInspection()
    elseif self.currentStep == ServiceTruckDialog.STEP_RESULTS then
        self:displayResults()
    end
end

--[[
    Display component selection screen
]]
function ServiceTruckDialog:displayComponentSelection(vehicleName)
    if self.componentContainer then
        self.componentContainer:setVisible(true)
    end

    -- Update vehicle name
    if self.vehicleNameText then
        self.vehicleNameText:setText(vehicleName)
    end

    local maintSpec = self.vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return end

    -- Update reliability displays
    local engineRel = math.floor((maintSpec.engineReliability or 1.0) * 100)
    local electricalRel = math.floor((maintSpec.electricalReliability or 1.0) * 100)
    local hydraulicRel = math.floor((maintSpec.hydraulicReliability or 1.0) * 100)
    local ceiling = math.floor((maintSpec.maxReliabilityCeiling or 1.0) * 100)

    if self.engineReliabilityText then
        self.engineReliabilityText:setText(tostring(engineRel) .. "%")
        self:setReliabilityColor(self.engineReliabilityText, engineRel)
    end
    if self.electricalReliabilityText then
        self.electricalReliabilityText:setText(tostring(electricalRel) .. "%")
        self:setReliabilityColor(self.electricalReliabilityText, electricalRel)
    end
    if self.hydraulicReliabilityText then
        self.hydraulicReliabilityText:setText(tostring(hydraulicRel) .. "%")
        self:setReliabilityColor(self.hydraulicReliabilityText, hydraulicRel)
    end
    if self.ceilingText then
        self.ceilingText:setText(string.format(g_i18n:getText("usedplus_serviceTruck_ceiling") or "Max Potential: %d%%", ceiling))
    end

    -- Check for cooldowns and disable buttons
    self:updateButtonStates(maintSpec)

    -- Update resource display
    self:updateResourceDisplay()
end

--[[
    Set reliability text color based on value
]]
function ServiceTruckDialog:setReliabilityColor(textElement, reliability)
    if textElement == nil then return end

    if reliability >= 75 then
        textElement:setTextColor(0.2, 0.8, 0.2, 1)  -- Green
    elseif reliability >= 50 then
        textElement:setTextColor(1.0, 0.8, 0.0, 1)  -- Yellow
    elseif reliability >= 25 then
        textElement:setTextColor(1.0, 0.5, 0.0, 1)  -- Orange
    else
        textElement:setTextColor(1.0, 0.2, 0.2, 1)  -- Red
    end
end

--[[
    Update button states based on cooldowns and current reliability
]]
function ServiceTruckDialog:updateButtonStates(maintSpec)
    local function checkComponent(button, label, systemType, reliability)
        if button == nil then return end

        local onCooldown, timeRemaining = RestorationData.isOnCooldown(self.vehicle, systemType)
        local needsRestoration = reliability < 0.9

        if onCooldown then
            -- Show cooldown timer
            local hoursRemaining = math.ceil(timeRemaining / (60 * 1000))
            button:setDisabled(true)
            if label then
                label:setText(string.format(g_i18n:getText("usedplus_serviceTruck_cooldown") or "Cooldown: %dh", hoursRemaining))
            end
        elseif not needsRestoration then
            button:setDisabled(true)
            if label then
                label:setText(g_i18n:getText("usedplus_serviceTruck_healthy") or "System Healthy")
            end
        else
            button:setDisabled(false)
        end
    end

    checkComponent(self.engineButton, self.engineStatusText, RestorationData.SYSTEM_ENGINE, maintSpec.engineReliability or 1.0)
    checkComponent(self.electricalButton, self.electricalStatusText, RestorationData.SYSTEM_ELECTRICAL, maintSpec.electricalReliability or 1.0)
    checkComponent(self.hydraulicButton, self.hydraulicStatusText, RestorationData.SYSTEM_HYDRAULIC, maintSpec.hydraulicReliability or 1.0)
end

--[[
    Update resource availability display
]]
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
            self.partsLevelText:setTextColor(1.0, 0.2, 0.2, 1)  -- Red warning
        else
            self.partsLevelText:setTextColor(0.9, 0.9, 0.9, 1)  -- Normal
        end
    end
end

--[[
    Display inspection screen with symptoms and diagnosis options
]]
function ServiceTruckDialog:displayInspection()
    if self.inspectionContainer then
        self.inspectionContainer:setVisible(true)
    end

    -- Get scenario for selected component
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

    -- Display component being inspected
    if self.inspectingText then
        local componentName = g_i18n:getText("usedplus_component_" .. self.selectedComponent) or self.selectedComponent
        self.inspectingText:setText(string.format(g_i18n:getText("usedplus_serviceTruck_inspecting") or "Inspecting: %s", componentName))
    end

    -- Display symptoms
    for i = 1, 3 do
        local symptomText = self["symptom" .. i .. "Text"]
        if symptomText then
            local symptomKey = self.currentScenario.symptoms[i]
            local symptom = symptomKey and g_i18n:getText(symptomKey) or ""
            symptomText:setText("• " .. symptom)
        end
    end

    -- Display diagnosis hints
    local hints = RestorationData.getSystemHints(self.selectedComponent, 2)
    for i = 1, 2 do
        local hintText = self["hint" .. i .. "Text"]
        if hintText then
            local hint = hints[i] and g_i18n:getText(hints[i]) or ""
            hintText:setText(hint)
        end
    end

    -- Display diagnosis options
    for i = 1, 4 do
        local diagButton = self["diagnosisButton" .. i]
        local diagText = self["diagnosisText" .. i]
        if diagButton and diagText then
            local diagKey = self.currentScenario.diagnoses[i]
            local diagLabel = diagKey and g_i18n:getText(diagKey) or ("Option " .. i)
            diagText:setText(diagLabel)
        end
    end

    -- Update estimated time
    if self.estimatedTimeText then
        local hours = self.currentScenario.restorationHours or 48
        self.estimatedTimeText:setText(string.format(g_i18n:getText("usedplus_serviceTruck_estimatedTime") or "Estimated time: %d hours", hours))
    end
end

--[[
    Display results screen
]]
function ServiceTruckDialog:displayResults()
    if self.resultsContainer then
        self.resultsContainer:setVisible(true)
    end

    if self.inspectionResult == nil then return end

    local isSuccess = self.inspectionResult.outcome == RestorationData.OUTCOME_SUCCESS

    -- Update result header
    if self.resultHeaderText then
        if isSuccess then
            self.resultHeaderText:setText(g_i18n:getText("usedplus_serviceTruck_inspectionPassed") or "INSPECTION PASSED")
            self.resultHeaderText:setTextColor(0.2, 0.8, 0.2, 1)  -- Green
        else
            self.resultHeaderText:setText(g_i18n:getText("usedplus_serviceTruck_inspectionFailed") or "INSPECTION FAILED")
            self.resultHeaderText:setTextColor(1.0, 0.2, 0.2, 1)  -- Red
        end
    end

    -- Update result message
    if self.resultMessageText then
        if isSuccess then
            local hours = self.inspectionResult.estimatedHours or 48
            self.resultMessageText:setText(string.format(
                g_i18n:getText("usedplus_serviceTruck_canStartRestoration") or "Restoration can begin. Estimated: %d hours",
                hours
            ))
        else
            self.resultMessageText:setText(g_i18n:getText("usedplus_serviceTruck_wrongDiagnosis") or
                "Incorrect diagnosis. You must wait before retrying this component.")
        end
    end

    -- Update cooldown display
    if self.cooldownText then
        if not isSuccess then
            local cooldownHours = RestorationData.FAILED_DIAGNOSIS_COOLDOWN / (60 * 1000)
            self.cooldownText:setText(string.format(g_i18n:getText("usedplus_serviceTruck_cooldownApplied") or "Cooldown: %d hours", cooldownHours))
            self.cooldownText:setVisible(true)
        else
            self.cooldownText:setVisible(false)
        end
    end

    -- Show/hide start button based on result
    if self.startRestorationButton then
        self.startRestorationButton:setVisible(isSuccess)
    end
end

--[[
    Component button callbacks
]]
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

--[[
    Diagnosis button callbacks
]]
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

--[[
    Process player's diagnosis choice
]]
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

--[[
    Start restoration button callback
]]
function ServiceTruckDialog:onStartRestorationClick()
    if self.serviceTruck ~= nil and self.vehicle ~= nil and self.selectedComponent ~= nil then
        local success = self.serviceTruck:startRestoration(self.vehicle, self.selectedComponent)

        if success then
            self:onClickBack()  -- Close dialog
        end
    end
end

--[[
    Back button callback
]]
function ServiceTruckDialog:onClickBack()
    if self.currentStep == ServiceTruckDialog.STEP_INSPECTION then
        self.currentStep = ServiceTruckDialog.STEP_COMPONENT
        self.currentScenario = nil
        self:updateDisplay()
    elseif self.currentStep == ServiceTruckDialog.STEP_RESULTS then
        -- Close dialog
        g_gui:closeDialog(self)
    else
        -- Close dialog
        g_gui:closeDialog(self)
    end
end

--[[
    Close button callback
]]
function ServiceTruckDialog:onClickOk()
    g_gui:closeDialog(self)
end

UsedPlus.logInfo("ServiceTruckDialog class loaded")
