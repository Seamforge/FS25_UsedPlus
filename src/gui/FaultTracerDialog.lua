--[[
    FS25_UsedPlus - Fault Tracer Dialog

    Minesweeper-inspired diagnostic minigame for the Service Truck.
    Players probe a grid to locate hidden faults, then diagnose each
    fault's type (Corroded/Cracked/Seized) for maximum repair quality.

    Screens:
    1. Component Selection - Pick engine/electrical/hydraulic
    2. Grid - Probe cells and flag faults
    3. Type Selection - Choose fault type (overlay)
    4. Results - Repair outcomes and reliability gains

    v2.12.0 - Fault Tracer Minigame
]]

FaultTracerDialog = {}
local FaultTracerDialog_mt = Class(FaultTracerDialog, MessageDialog)

-- Registration singleton
FaultTracerDialog.instance = nil
FaultTracerDialog.xmlPath = nil

-- Screens
FaultTracerDialog.SCREEN_COMPONENT = 1
FaultTracerDialog.SCREEN_GRID = 2
FaultTracerDialog.SCREEN_TYPE_SELECT = 3
FaultTracerDialog.SCREEN_RESULTS = 4

-- Modes
FaultTracerDialog.MODE_PROBE = "probe"
FaultTracerDialog.MODE_FLAG = "flag"

-- Colors for cell backgrounds
FaultTracerDialog.COLOR_HIDDEN = { 0.15, 0.15, 0.20, 1 }
FaultTracerDialog.COLOR_REVEALED_GREEN = { 0.08, 0.20, 0.08, 1 }
FaultTracerDialog.COLOR_REVEALED_AMBER = { 0.25, 0.20, 0.05, 1 }
FaultTracerDialog.COLOR_REVEALED_RED = { 0.30, 0.08, 0.08, 1 }
FaultTracerDialog.COLOR_REVEALED_ZERO = { 0.06, 0.12, 0.06, 1 }
FaultTracerDialog.COLOR_FAULT_HIT = { 0.40, 0.05, 0.05, 1 }
FaultTracerDialog.COLOR_FLAGGED = { 0.20, 0.10, 0.30, 1 }
FaultTracerDialog.COLOR_MODE_ACTIVE = { 0.15, 0.30, 0.15, 1 }
FaultTracerDialog.COLOR_MODE_INACTIVE = { 0.15, 0.15, 0.20, 1 }

-- Hover brighten amount (matches FinancesPanel +0.08 pattern)
FaultTracerDialog.HOVER_BRIGHTEN = 0.08


--[[
    Register the dialog with g_gui (lazy loading pattern).
]]
function FaultTracerDialog.register()
    if FaultTracerDialog.instance == nil then
        UsedPlus.logInfo("FaultTracerDialog: Registering dialog")

        if FaultTracerDialog.xmlPath == nil then
            FaultTracerDialog.xmlPath = UsedPlus.MOD_DIR .. "gui/FaultTracerDialog.xml"
        end

        FaultTracerDialog.instance = FaultTracerDialog.new()
        g_gui:loadGui(FaultTracerDialog.xmlPath, "FaultTracerDialog", FaultTracerDialog.instance)

        UsedPlus.logInfo("FaultTracerDialog: Registration complete")
    end
end

function FaultTracerDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or FaultTracerDialog_mt)

    self.vehicle = nil
    self.serviceTruck = nil
    self.currentScreen = FaultTracerDialog.SCREEN_COMPONENT
    self.selectedComponent = nil
    self.grid = nil
    self.mode = FaultTracerDialog.MODE_PROBE
    self.flaggingCell = nil  -- {row, col} of cell being flagged
    self.results = nil

    -- Cell element references (populated in onCreate)
    self.cellElements = {}

    return self
end

function FaultTracerDialog:onOpen()
    FaultTracerDialog:superClass().onOpen(self)
    self:updateDisplay()
end

function FaultTracerDialog:onCreate()
    FaultTracerDialog:superClass().onCreate(self)

    -- Pre-cache cell element references for all 20 possible cells
    for r = 0, 3 do
        self.cellElements[r] = {}
        for c = 0, 4 do
            local prefix = "ftCell"
            local suffix = r .. "_" .. c
            self.cellElements[r][c] = {
                bg = self.dialogElement:getDescendantById(prefix .. "Bg_" .. suffix),
                btn = self.dialogElement:getDescendantById(prefix .. "Btn_" .. suffix),
                num = self.dialogElement:getDescendantById(prefix .. "Num_" .. suffix),
                gauge = self.dialogElement:getDescendantById(prefix .. "Gauge_" .. suffix),
            }
        end
    end
end

--[[
    Set data for the dialog.
    @param vehicle - Target vehicle to diagnose
    @param serviceTruck - The Service Truck performing the work
]]
function FaultTracerDialog:setData(vehicle, serviceTruck)
    self.vehicle = vehicle
    self.serviceTruck = serviceTruck
    self.currentScreen = FaultTracerDialog.SCREEN_COMPONENT
    self.selectedComponent = nil
    self.grid = nil
    self.mode = FaultTracerDialog.MODE_PROBE
    self.flaggingCell = nil
    self.results = nil

    self:updateDisplay()
end

--[[
    Master display update - routes to correct screen.
]]
function FaultTracerDialog:updateDisplay()
    if self.vehicle == nil then return end

    -- Hide all screen containers
    if self.componentContainer then self.componentContainer:setVisible(false) end
    if self.gridContainer then self.gridContainer:setVisible(false) end
    if self.typeSelectContainer then self.typeSelectContainer:setVisible(false) end
    if self.resultsContainer then self.resultsContainer:setVisible(false) end

    if self.currentScreen == FaultTracerDialog.SCREEN_COMPONENT then
        self:displayComponentSelection()
    elseif self.currentScreen == FaultTracerDialog.SCREEN_GRID then
        self:displayGrid()
    elseif self.currentScreen == FaultTracerDialog.SCREEN_TYPE_SELECT then
        self:displayTypeSelection()
    elseif self.currentScreen == FaultTracerDialog.SCREEN_RESULTS then
        self:displayResults()
    end
end

-- ============================================================
-- SCREEN 1: Component Selection
-- ============================================================

function FaultTracerDialog:displayComponentSelection()
    if self.componentContainer then
        self.componentContainer:setVisible(true)
    end

    local vehicleName = self.vehicle:getName() or "Vehicle"
    if self.ftVehicleNameText then
        self.ftVehicleNameText:setText(vehicleName)
    end

    local maintSpec = self.vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return end

    -- Display ceiling
    local ceiling = (maintSpec.maxReliabilityCeiling or 1.0) * 100
    if self.ftCeilingText then
        self.ftCeilingText:setText(string.format(g_i18n:getText("usedplus_ft_maxPotential"), ceiling))
    end

    -- Engine
    local engineRel = (maintSpec.engineReliability or 1.0) * 100
    if self.ftEngineValue then
        self.ftEngineValue:setText(string.format("%.0f%%", engineRel))
        self:setReliabilityColor(self.ftEngineValue, engineRel)
    end
    if self.ftEngineStatus then
        self.ftEngineStatus:setText(engineRel >= 90 and g_i18n:getText("usedplus_ft_healthy") or g_i18n:getText("usedplus_ft_needsService"))
    end
    if self.ftEngineBg then
        self:setComponentBgColor(self.ftEngineBg, engineRel)
    end

    -- Electrical
    local elecRel = (maintSpec.electricalReliability or 1.0) * 100
    if self.ftElectricalValue then
        self.ftElectricalValue:setText(string.format("%.0f%%", elecRel))
        self:setReliabilityColor(self.ftElectricalValue, elecRel)
    end
    if self.ftElectricalStatus then
        self.ftElectricalStatus:setText(elecRel >= 90 and g_i18n:getText("usedplus_ft_healthy") or g_i18n:getText("usedplus_ft_needsService"))
    end
    if self.ftElectricalBg then
        self:setComponentBgColor(self.ftElectricalBg, elecRel)
    end

    -- Hydraulic
    local hydRel = (maintSpec.hydraulicReliability or 1.0) * 100
    if self.ftHydraulicValue then
        self.ftHydraulicValue:setText(string.format("%.0f%%", hydRel))
        self:setReliabilityColor(self.ftHydraulicValue, hydRel)
    end
    if self.ftHydraulicStatus then
        self.ftHydraulicStatus:setText(hydRel >= 90 and g_i18n:getText("usedplus_ft_healthy") or g_i18n:getText("usedplus_ft_needsService"))
    end
    if self.ftHydraulicBg then
        self:setComponentBgColor(self.ftHydraulicBg, hydRel)
    end

    -- Resource levels from service truck
    if self.serviceTruck ~= nil then
        local truckSpec = self.serviceTruck[ServiceTruck.specName or "spec_serviceTruck"]
        if truckSpec == nil then
            truckSpec = self.serviceTruck.spec_serviceTruck
        end
        if truckSpec ~= nil then
            local oilLevel = self.serviceTruck:getFillUnitFillLevel(truckSpec.oilFillUnit) or 0
            local hydLevel = self.serviceTruck:getFillUnitFillLevel(truckSpec.hydraulicFillUnit) or 0
            if self.ftOilLevel then
                self.ftOilLevel:setText(string.format("%.0fL", oilLevel))
            end
            if self.ftHydraulicLevel then
                self.ftHydraulicLevel:setText(string.format("%.0fL", hydLevel))
            end
        end
    end
end

function FaultTracerDialog:setReliabilityColor(element, percent)
    if percent >= 70 then
        element:setTextColor(0.3, 1.0, 0.3, 1)  -- Green
    elseif percent >= 50 then
        element:setTextColor(1.0, 0.8, 0.2, 1)  -- Amber
    else
        element:setTextColor(1.0, 0.3, 0.3, 1)  -- Red
    end
end

function FaultTracerDialog:setComponentBgColor(element, percent)
    if percent >= 90 then
        element:setImageColor(nil, 0.12, 0.12, 0.16, 1)  -- Normal
    elseif percent >= 70 then
        element:setImageColor(nil, 0.10, 0.15, 0.10, 1)  -- Slight green
    elseif percent >= 50 then
        element:setImageColor(nil, 0.18, 0.15, 0.08, 1)  -- Amber tint
    else
        element:setImageColor(nil, 0.20, 0.08, 0.08, 1)  -- Red tint
    end
end

-- Component click handlers
function FaultTracerDialog:onEngineClick()
    self:selectComponent("engine")
end

function FaultTracerDialog:onElectricalClick()
    self:selectComponent("electrical")
end

function FaultTracerDialog:onHydraulicClick()
    self:selectComponent("hydraulic")
end

function FaultTracerDialog:selectComponent(component)
    local maintSpec = self.vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return end

    local reliability = 1.0
    if component == "engine" then
        reliability = maintSpec.engineReliability or 1.0
    elseif component == "electrical" then
        reliability = maintSpec.electricalReliability or 1.0
    elseif component == "hydraulic" then
        reliability = maintSpec.hydraulicReliability or 1.0
    end

    -- Check if component needs service
    if reliability >= 0.9 then
        if self.ftSelectHint then
            self.ftSelectHint:setText(g_i18n:getText("usedplus_ft_noFaults") or "No faults remaining - system healthy!")
            self.ftSelectHint:setTextColor(0.3, 1.0, 0.3, 1)
        end
        return
    end

    -- Check if truck has oil
    local oilLevel = 0
    if self.serviceTruck ~= nil then
        local truckSpec = self.serviceTruck.spec_serviceTruck
        if truckSpec ~= nil and truckSpec.oilFillUnit ~= nil then
            oilLevel = self.serviceTruck:getFillUnitFillLevel(truckSpec.oilFillUnit) or 0
        end
    end

    if oilLevel < 1.0 then
        if self.ftSelectHint then
            self.ftSelectHint:setText(g_i18n:getText("usedplus_ft_noOil") or "Service Truck has no oil! Fill the oil tank before diagnosing.")
            self.ftSelectHint:setTextColor(1.0, 0.3, 0.3, 1)
        end
        return
    end

    self.selectedComponent = component
    self.grid = FaultTracerGrid.generate(component, reliability)
    self.mode = FaultTracerDialog.MODE_PROBE
    self.currentScreen = FaultTracerDialog.SCREEN_GRID

    UsedPlus.logInfo("FaultTracerDialog: Generated " .. self.grid.rows .. "x" .. self.grid.cols ..
        " grid for " .. component .. " (reliability=" .. string.format("%.1f%%", reliability * 100) ..
        ", faults=" .. self.grid.totalFaults .. ")")

    self:updateDisplay()
end

-- ============================================================
-- SCREEN 2: Grid Display
-- ============================================================

function FaultTracerDialog:displayGrid()
    if self.gridContainer then
        self.gridContainer:setVisible(true)
    end

    -- Update title
    local componentName = self.selectedComponent
    if componentName then
        componentName = componentName:sub(1, 1):upper() .. componentName:sub(2)
    end
    if self.ftGridTitle then
        self.ftGridTitle:setText(string.format(g_i18n:getText("usedplus_ft_componentTitle"), componentName))
    end

    -- Update fault counter
    if self.ftFaultCounter then
        local flagged = FaultTracerGrid.getFlaggedCount(self.grid)
        self.ftFaultCounter:setText(string.format(g_i18n:getText("usedplus_ft_faultCounterFormat"), flagged, self.grid.totalFaults))
    end

    -- Update oil counter (single source of truth from grid state)
    if self.ftOilUsedText then
        self.ftOilUsedText:setText(string.format("%.1fL", FaultTracerGrid.getOilUsed(self.grid)))
    end

    -- Update mode buttons
    self:updateModeButtons()

    -- Update repair button visibility
    local allFlagged = FaultTracerGrid.allFaultsFlagged(self.grid)
    if self.ftRepairBtnBg then
        self.ftRepairBtnBg:setImageColor(nil,
            allFlagged and 0.1 or 0.05,
            allFlagged and 0.3 or 0.1,
            allFlagged and 0.1 or 0.05, 1)
    end

    -- Update all grid cells
    self:updateGridCells()
end

function FaultTracerDialog:updateModeButtons()
    local isProbe = (self.mode == FaultTracerDialog.MODE_PROBE)

    if self.ftProbeBtnBg then
        local c = isProbe and FaultTracerDialog.COLOR_MODE_ACTIVE or FaultTracerDialog.COLOR_MODE_INACTIVE
        self.ftProbeBtnBg:setImageColor(nil, c[1], c[2], c[3], c[4])
    end
    if self.ftFlagBtnBg then
        local c = (not isProbe) and FaultTracerDialog.COLOR_MODE_ACTIVE or FaultTracerDialog.COLOR_MODE_INACTIVE
        self.ftFlagBtnBg:setImageColor(nil, c[1], c[2], c[3], c[4])
    end
end

function FaultTracerDialog:updateGridCells()
    if self.grid == nil then return end

    for r = 0, 3 do
        for c = 0, 4 do
            local elements = self.cellElements[r] and self.cellElements[r][c]
            if elements == nil then
                -- Skip if elements not cached
            else
                -- Grid uses 1-based indexing, elements use 0-based
                local gridRow = r + 1
                local gridCol = c + 1

                local isActive = (gridRow <= self.grid.rows and gridCol <= self.grid.cols)

                -- Show/hide cells outside current grid
                if elements.bg then elements.bg:setVisible(isActive) end
                if elements.btn then elements.btn:setVisible(isActive) end
                if elements.num then elements.num:setVisible(isActive) end
                if elements.gauge then elements.gauge:setVisible(isActive) end

                if isActive then
                    local cell = self.grid.cells[gridRow][gridCol]
                    self:renderCell(elements, cell, gridRow, gridCol)
                end
            end
        end
    end
end

function FaultTracerDialog:renderCell(elements, cell, row, col)
    if cell.state == FaultTracerGrid.STATE_HIDDEN then
        -- Hidden cell
        local clr = FaultTracerDialog.COLOR_HIDDEN
        if elements.bg then elements.bg:setImageColor(nil, clr[1], clr[2], clr[3], clr[4]) end
        if elements.num then elements.num:setText("?") end
        if elements.num then elements.num:setTextColor(0.4, 0.4, 0.5, 1) end
        if elements.gauge then elements.gauge:setText("") end

    elseif cell.state == FaultTracerGrid.STATE_REVEALED then
        if cell.isFault then
            -- Fault hit by probing
            local clr = FaultTracerDialog.COLOR_FAULT_HIT
            if elements.bg then elements.bg:setImageColor(nil, clr[1], clr[2], clr[3], clr[4]) end
            if elements.num then
                elements.num:setText("!")
                elements.num:setTextColor(1, 0.2, 0.2, 1)
            end
            if elements.gauge then
                elements.gauge:setText(g_i18n:getText("usedplus_ft_gaugeFault"))
                elements.gauge:setTextColor(1, 0.3, 0.3, 1)
            end
        else
            -- Safe revealed cell
            local clr
            if cell.number == 0 then
                clr = FaultTracerDialog.COLOR_REVEALED_ZERO
            elseif cell.gaugeColor == FaultTracerGrid.GAUGE_RED then
                clr = FaultTracerDialog.COLOR_REVEALED_RED
            elseif cell.gaugeColor == FaultTracerGrid.GAUGE_AMBER then
                clr = FaultTracerDialog.COLOR_REVEALED_AMBER
            else
                clr = FaultTracerDialog.COLOR_REVEALED_GREEN
            end
            if elements.bg then elements.bg:setImageColor(nil, clr[1], clr[2], clr[3], clr[4]) end

            -- Number
            if elements.num then
                if cell.number == 0 then
                    elements.num:setText("")
                else
                    elements.num:setText(tostring(cell.number))
                end
                elements.num:setTextColor(1, 1, 1, 1)
            end

            -- Gauge color label
            if elements.gauge then
                if cell.gaugeColor == FaultTracerGrid.GAUGE_RED then
                    elements.gauge:setText(g_i18n:getText("usedplus_ft_gaugeRed"))
                    elements.gauge:setTextColor(1, 0.3, 0.3, 1)
                elseif cell.gaugeColor == FaultTracerGrid.GAUGE_AMBER then
                    elements.gauge:setText(g_i18n:getText("usedplus_ft_gaugeAmber"))
                    elements.gauge:setTextColor(1, 0.8, 0.2, 1)
                else
                    elements.gauge:setText(g_i18n:getText("usedplus_ft_gaugeGreen"))
                    elements.gauge:setTextColor(0.3, 1, 0.3, 1)
                end
                -- Zero cells don't need gauge
                if cell.number == 0 then
                    elements.gauge:setText("")
                end
            end
        end

    elseif cell.state == FaultTracerGrid.STATE_FLAGGED then
        -- Flagged cell
        local clr = FaultTracerDialog.COLOR_FLAGGED
        if elements.bg then elements.bg:setImageColor(nil, clr[1], clr[2], clr[3], clr[4]) end
        if elements.num then
            elements.num:setText(g_i18n:getText("usedplus_ft_faultIndicator"))
            elements.num:setTextColor(0.8, 0.5, 1, 1)
        end
        if elements.gauge then
            local typeText = ""
            if cell.flaggedType == FaultTracerGrid.FAULT_CORRODED then
                typeText = "CORR"
                elements.gauge:setTextColor(1, 0.6, 0.2, 1)
            elseif cell.flaggedType == FaultTracerGrid.FAULT_CRACKED then
                typeText = "CRCK"
                elements.gauge:setTextColor(1, 0.8, 0.2, 1)
            elseif cell.flaggedType == FaultTracerGrid.FAULT_SEIZED then
                typeText = "SEIZD"
                elements.gauge:setTextColor(1, 0.3, 0.3, 1)
            end
            elements.gauge:setText(typeText)
        end
    end
end

-- Mode buttons
function FaultTracerDialog:onProbeModeClick()
    self.mode = FaultTracerDialog.MODE_PROBE
    self:updateModeButtons()
end

function FaultTracerDialog:onFlagModeClick()
    self.mode = FaultTracerDialog.MODE_FLAG
    self:updateModeButtons()
end

-- ============================================================
-- Cell Click Handlers (20 cells, 0-indexed)
-- ============================================================

function FaultTracerDialog:handleCellClick(row, col)
    if self.grid == nil then return end

    -- Convert 0-based element index to 1-based grid index
    local gridRow = row + 1
    local gridCol = col + 1

    if gridRow > self.grid.rows or gridCol > self.grid.cols then return end

    local cell = self.grid.cells[gridRow][gridCol]

    if self.mode == FaultTracerDialog.MODE_PROBE then
        self:handleProbe(gridRow, gridCol, cell)
    elseif self.mode == FaultTracerDialog.MODE_FLAG then
        self:handleFlag(gridRow, gridCol, cell)
    end
end

function FaultTracerDialog:handleProbe(row, col, cell)
    if cell.state ~= FaultTracerGrid.STATE_HIDDEN then
        return
    end

    local result = FaultTracerGrid.probeCell(self.grid, row, col)

    if not result.success then return end

    if result.isFault then
        -- Hit a fault - penalty (oil tracked via FaultTracerGrid.getOilUsed)
        if self.ftStatusMsg then
            self.ftStatusMsg:setText(g_i18n:getText("usedplus_ft_probeHit") or "FAULT HIT! Fluid leak - 3x cost")
        end
        -- Auto-switch to flag mode for convenience
        self.mode = FaultTracerDialog.MODE_FLAG
    else
        -- Safe probe (oil tracked via FaultTracerGrid.getOilUsed)
        if self.ftStatusMsg then
            self.ftStatusMsg:setText("")
        end
    end

    self:displayGrid()
end

function FaultTracerDialog:handleFlag(row, col, cell)
    if cell.state == FaultTracerGrid.STATE_FLAGGED then
        -- Unflag on second click
        FaultTracerGrid.unflagCell(self.grid, row, col)
        self:displayGrid()
        return
    end

    if cell.state == FaultTracerGrid.STATE_REVEALED and not cell.isFault then
        return  -- Can't flag a revealed safe cell
    end

    if cell.state ~= FaultTracerGrid.STATE_HIDDEN and cell.state ~= FaultTracerGrid.STATE_REVEALED then
        return
    end

    -- Open type selection overlay
    self.flaggingCell = { row = row, col = col }
    self.currentScreen = FaultTracerDialog.SCREEN_TYPE_SELECT
    self:updateDisplay()
end

-- Generate cell click callback functions
for r = 0, 3 do
    for c = 0, 4 do
        local funcName = "onCellClick_" .. r .. "_" .. c
        FaultTracerDialog[funcName] = function(self)
            self:handleCellClick(r, c)
        end
    end
end

-- ============================================================
-- SCREEN 3: Type Selection
-- ============================================================

function FaultTracerDialog:displayTypeSelection()
    if self.typeSelectContainer then
        self.typeSelectContainer:setVisible(true)
    end

    if self.ftTypeSelectCell and self.flaggingCell then
        local colLetter = string.char(64 + self.flaggingCell.col)  -- A, B, C, D, E
        self.ftTypeSelectCell:setText(string.format(g_i18n:getText("usedplus_ft_cellRef"), colLetter, self.flaggingCell.row))
    end

    -- Dynamic gauge hint: scan neighbors for gauge color clues
    if self.ftGaugeHint and self.flaggingCell and self.grid then
        local row = self.flaggingCell.row
        local col = self.flaggingCell.col
        local worstGauge = nil
        local hasProbed = false

        for dr = -1, 1 do
            for dc = -1, 1 do
                if dr ~= 0 or dc ~= 0 then
                    local nr = row + dr
                    local nc = col + dc
                    if nr >= 1 and nr <= self.grid.rows and nc >= 1 and nc <= self.grid.cols then
                        local neighbor = self.grid.cells[nr][nc]
                        if neighbor.state == FaultTracerGrid.STATE_REVEALED and not neighbor.isFault then
                            hasProbed = true
                            if neighbor.gaugeColor == FaultTracerGrid.GAUGE_RED then
                                worstGauge = FaultTracerGrid.GAUGE_RED
                            elseif neighbor.gaugeColor == FaultTracerGrid.GAUGE_AMBER then
                                if worstGauge ~= FaultTracerGrid.GAUGE_RED then
                                    worstGauge = FaultTracerGrid.GAUGE_AMBER
                                end
                            elseif neighbor.gaugeColor == FaultTracerGrid.GAUGE_GREEN then
                                if worstGauge == nil then
                                    worstGauge = FaultTracerGrid.GAUGE_GREEN
                                end
                            end
                        end
                    end
                end
            end
        end

        if not hasProbed then
            self.ftGaugeHint:setText(g_i18n:getText("usedplus_ft_hintNoProbes"))
            self.ftGaugeHint:setTextColor(0.5, 0.5, 0.6, 1)
        elseif worstGauge == FaultTracerGrid.GAUGE_RED then
            self.ftGaugeHint:setText(g_i18n:getText("usedplus_ft_hintRedSeized"))
            self.ftGaugeHint:setTextColor(1, 0.3, 0.3, 1)
        elseif worstGauge == FaultTracerGrid.GAUGE_AMBER then
            self.ftGaugeHint:setText(g_i18n:getText("usedplus_ft_hintAmberCracked"))
            self.ftGaugeHint:setTextColor(1, 0.8, 0.2, 1)
        else
            self.ftGaugeHint:setText(g_i18n:getText("usedplus_ft_hintGreenCorroded"))
            self.ftGaugeHint:setTextColor(0.3, 1, 0.3, 1)
        end
    end
end

function FaultTracerDialog:onCorrodedClick()
    self:applyFlag(FaultTracerGrid.FAULT_CORRODED)
end

function FaultTracerDialog:onCrackedClick()
    self:applyFlag(FaultTracerGrid.FAULT_CRACKED)
end

function FaultTracerDialog:onSeizedClick()
    self:applyFlag(FaultTracerGrid.FAULT_SEIZED)
end

function FaultTracerDialog:onTypeCancelClick()
    self.flaggingCell = nil
    self.currentScreen = FaultTracerDialog.SCREEN_GRID
    self:updateDisplay()
end

function FaultTracerDialog:applyFlag(faultType)
    if self.flaggingCell == nil then return end

    FaultTracerGrid.flagCell(self.grid, self.flaggingCell.row, self.flaggingCell.col, faultType)

    self.flaggingCell = nil
    self.currentScreen = FaultTracerDialog.SCREEN_GRID
    self:updateDisplay()
end

-- ============================================================
-- Action Buttons
-- ============================================================

function FaultTracerDialog:onQuickScanClick()
    if self.grid == nil then return end
    if self.grid.quickScanUsed then return end

    FaultTracerGrid.quickScan(self.grid)

    -- Oil tracked via FaultTracerGrid.getOilUsed (quickScanUsed flag set in grid engine)
    if self.ftStatusMsg then
        self.ftStatusMsg:setText(g_i18n:getText("usedplus_ft_quickScanCap") or "Quality capped at 60% (Quick Scan)")
    end

    self:displayGrid()
end

function FaultTracerDialog:onBeginRepairClick()
    if self.grid == nil then return end

    if not FaultTracerGrid.allFaultsFlagged(self.grid) then
        if self.ftStatusMsg then
            self.ftStatusMsg:setText(g_i18n:getText("usedplus_ft_flagAllFirst"))
        end
        return
    end

    -- Validate vehicle still exists
    if self.vehicle == nil or self.vehicle.isDeleted then
        InfoDialog.show(g_i18n:getText("usedplus_ft_vehicleUnavailable"))
        self:close()
        return
    end

    -- Validate truck still exists
    if self.serviceTruck == nil or self.serviceTruck.isDeleted then
        InfoDialog.show(g_i18n:getText("usedplus_ft_truckUnavailable"))
        self:close()
        return
    end

    -- Calculate results
    self.results = FaultTracerGrid.calculateResults(self.grid)

    -- Apply via network event (handles both SP and MP)
    self:applyResults()

    -- Show results screen
    self.currentScreen = FaultTracerDialog.SCREEN_RESULTS
    self:updateDisplay()
end

-- ============================================================
-- SCREEN 4: Results
-- ============================================================

function FaultTracerDialog:displayResults()
    if self.resultsContainer then
        self.resultsContainer:setVisible(true)
    end

    if self.results == nil then return end

    -- Display per-fault results
    for i = 0, 4 do
        local element = self["ftResult" .. i]
        if element then
            if i < #self.results.faultResults then
                local fr = self.results.faultResults[i + 1]
                local colLetter = string.char(64 + fr.col)
                local typeLabel = fr.actualType:sub(1, 1):upper() .. fr.actualType:sub(2)
                local status = fr.isCorrect and g_i18n:getText("usedplus_ft_correct") or g_i18n:getText("usedplus_ft_incorrect")
                local color = fr.isCorrect and {0.3, 1, 0.3} or {1, 0.3, 0.3}

                element:setText(string.format(g_i18n:getText("usedplus_ft_resultLine"), colLetter, fr.row, typeLabel, status, fr.oilCost))
                element:setTextColor(color[1], color[2], color[3], 1)
                element:setVisible(true)
            else
                element:setVisible(false)
            end
        end
    end

    -- Summary values
    if self.ftReliabilityGainText then
        self.ftReliabilityGainText:setText(string.format("+%.1f%%", self.results.reliabilityGain * 100))
    end
    if self.ftCeilingGainText then
        self.ftCeilingGainText:setText(string.format("+%.1f%%", self.results.ceilingGain * 100))
    end
    if self.ftAccuracyText then
        self.ftAccuracyText:setText(string.format("%.0f%%", self.results.diagnosisAccuracy * 100))
    end
    if self.ftOilConsumedText then
        self.ftOilConsumedText:setText(string.format("%.1fL", self.results.totalOilUsed))
    end

    -- v2.14.2: Result outcome icon based on accuracy
    local outcomeIcon = self.ftResultOutcomeIcon or self.dialogElement:getDescendantById("ftResultOutcomeIcon")
    if outcomeIcon ~= nil then
        local iconDir = UsedPlus.MOD_DIR .. "gui/icons/"
        if self.results.diagnosisAccuracy >= 1.0 then
            outcomeIcon:setImageFilename(iconDir .. "success.dds")
        elseif self.results.diagnosisAccuracy >= 0.5 then
            outcomeIcon:setImageFilename(iconDir .. "status_warning.dds")
        else
            outcomeIcon:setImageFilename(iconDir .. "failure.dds")
        end
    end

    -- Quality note
    if self.ftQualityNote then
        if self.grid.quickScanUsed then
            self.ftQualityNote:setText(g_i18n:getText("usedplus_ft_quickScanCap") or "Quality capped at 60% (Quick Scan)")
            self.ftQualityNote:setVisible(true)
        elseif self.results.incorrectCount > 0 then
            self.ftQualityNote:setText(string.format(g_i18n:getText("usedplus_ft_incorrectCount"), self.results.incorrectCount))
            self.ftQualityNote:setVisible(true)
        else
            self.ftQualityNote:setText(g_i18n:getText("usedplus_ft_perfectDiagnosis"))
            self.ftQualityNote:setTextColor(0.3, 1, 0.3, 1)
            self.ftQualityNote:setVisible(true)
        end
    end
end

--[[
    Apply repair results via network event (handles SP and MP).
    Server-side event validates and applies reliability/ceiling gains, consumes oil.
]]
function FaultTracerDialog:applyResults()
    if self.results == nil or self.vehicle == nil or self.serviceTruck == nil then return end

    FaultTracerResultEvent.sendToServer(
        self.vehicle.id,
        self.serviceTruck.id,
        self.selectedComponent,
        self.results.reliabilityGain,
        self.results.ceilingGain,
        self.results.totalOilUsed
    )
end

-- ============================================================
-- Hover Effects
-- ============================================================

function FaultTracerDialog.brightenColor(color)
    local b = FaultTracerDialog.HOVER_BRIGHTEN
    return { math.min(color[1] + b, 1.0), math.min(color[2] + b, 1.0), math.min(color[3] + b, 1.0), color[4] }
end

function FaultTracerDialog:getCellBaseColor(cell)
    if cell.state == FaultTracerGrid.STATE_HIDDEN then
        return FaultTracerDialog.COLOR_HIDDEN
    elseif cell.state == FaultTracerGrid.STATE_FLAGGED then
        return FaultTracerDialog.COLOR_FLAGGED
    elseif cell.state == FaultTracerGrid.STATE_REVEALED then
        if cell.isFault then
            return FaultTracerDialog.COLOR_FAULT_HIT
        elseif cell.number == 0 then
            return FaultTracerDialog.COLOR_REVEALED_ZERO
        elseif cell.gaugeColor == FaultTracerGrid.GAUGE_RED then
            return FaultTracerDialog.COLOR_REVEALED_RED
        elseif cell.gaugeColor == FaultTracerGrid.GAUGE_AMBER then
            return FaultTracerDialog.COLOR_REVEALED_AMBER
        else
            return FaultTracerDialog.COLOR_REVEALED_GREEN
        end
    end
    return FaultTracerDialog.COLOR_HIDDEN
end

-- Screen 1: Component buttons (ftEngineBtn → ftEngineBg)
function FaultTracerDialog:onComponentHighlight(element)
    if element == nil or element.id == nil then return end
    local bgId = element.id:gsub("Btn$", "Bg")
    local bg = self[bgId]
    if bg == nil or bg.setImageColor == nil then return end

    local maintSpec = self.vehicle and self.vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return end

    local percent = 100
    if element.id == "ftEngineBtn" then
        percent = (maintSpec.engineReliability or 1.0) * 100
    elseif element.id == "ftElectricalBtn" then
        percent = (maintSpec.electricalReliability or 1.0) * 100
    elseif element.id == "ftHydraulicBtn" then
        percent = (maintSpec.hydraulicReliability or 1.0) * 100
    end

    local base
    if percent >= 90 then
        base = { 0.12, 0.12, 0.16, 1 }
    elseif percent >= 70 then
        base = { 0.10, 0.15, 0.10, 1 }
    elseif percent >= 50 then
        base = { 0.18, 0.15, 0.08, 1 }
    else
        base = { 0.20, 0.08, 0.08, 1 }
    end
    local bright = FaultTracerDialog.brightenColor(base)
    bg:setImageColor(nil, bright[1], bright[2], bright[3], bright[4])
end

function FaultTracerDialog:onComponentUnhighlight(element)
    if element == nil or element.id == nil then return end
    local bgId = element.id:gsub("Btn$", "Bg")
    local bg = self[bgId]
    if bg == nil or bg.setImageColor == nil then return end

    local maintSpec = self.vehicle and self.vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return end

    local percent = 100
    if element.id == "ftEngineBtn" then
        percent = (maintSpec.engineReliability or 1.0) * 100
    elseif element.id == "ftElectricalBtn" then
        percent = (maintSpec.electricalReliability or 1.0) * 100
    elseif element.id == "ftHydraulicBtn" then
        percent = (maintSpec.hydraulicReliability or 1.0) * 100
    end
    self:setComponentBgColor(bg, percent)
end

-- Screen 2: Grid cell hover (ftCellBtn_R_C → ftCellBg_R_C)
function FaultTracerDialog:onCellHighlight(element)
    if element == nil or element.id == nil or self.grid == nil then return end
    local r, c = element.id:match("ftCellBtn_(%d+)_(%d+)")
    if r == nil then return end
    r, c = tonumber(r), tonumber(c)
    local elems = self.cellElements[r] and self.cellElements[r][c]
    if elems == nil or elems.bg == nil then return end

    local gridRow, gridCol = r + 1, c + 1
    if gridRow > self.grid.rows or gridCol > self.grid.cols then return end

    local cell = self.grid.cells[gridRow][gridCol]
    local base = self:getCellBaseColor(cell)
    local bright = FaultTracerDialog.brightenColor(base)
    elems.bg:setImageColor(nil, bright[1], bright[2], bright[3], bright[4])
end

function FaultTracerDialog:onCellUnhighlight(element)
    if element == nil or element.id == nil or self.grid == nil then return end
    local r, c = element.id:match("ftCellBtn_(%d+)_(%d+)")
    if r == nil then return end
    r, c = tonumber(r), tonumber(c)
    local elems = self.cellElements[r] and self.cellElements[r][c]
    if elems == nil then return end

    local gridRow, gridCol = r + 1, c + 1
    if gridRow > self.grid.rows or gridCol > self.grid.cols then return end

    local cell = self.grid.cells[gridRow][gridCol]
    self:renderCell(elems, cell, gridRow, gridCol)
end

-- Screen 2: Mode buttons (ftProbeBtn/ftFlagBtn → ftProbeBtnBg/ftFlagBtnBg)
function FaultTracerDialog:onModeHighlight(element)
    if element == nil or element.id == nil then return end
    local bg = self[element.id .. "Bg"]
    if bg == nil or bg.setImageColor == nil then return end

    local isActive = (element.id == "ftProbeBtn" and self.mode == FaultTracerDialog.MODE_PROBE) or
                     (element.id == "ftFlagBtn" and self.mode == FaultTracerDialog.MODE_FLAG)
    local base = isActive and FaultTracerDialog.COLOR_MODE_ACTIVE or FaultTracerDialog.COLOR_MODE_INACTIVE
    local bright = FaultTracerDialog.brightenColor(base)
    bg:setImageColor(nil, bright[1], bright[2], bright[3], bright[4])
end

function FaultTracerDialog:onModeUnhighlight(element)
    if element == nil or element.id == nil then return end
    self:updateModeButtons()
end

-- Screen 2: Action buttons (ftQuickScanBtn/ftRepairBtn → ftQuickScanBtnBg/ftRepairBtnBg)
function FaultTracerDialog:onActionHighlight(element)
    if element == nil or element.id == nil then return end
    local bg = self[element.id .. "Bg"]
    if bg == nil or bg.setImageColor == nil then return end

    local base
    if element.id == "ftQuickScanBtn" then
        base = { 0.12, 0.12, 0.18, 1 }
    elseif element.id == "ftRepairBtn" then
        local allFlagged = self.grid ~= nil and FaultTracerGrid.allFaultsFlagged(self.grid)
        base = { allFlagged and 0.1 or 0.05, allFlagged and 0.3 or 0.1, allFlagged and 0.1 or 0.05, 1 }
    else
        return
    end
    local bright = FaultTracerDialog.brightenColor(base)
    bg:setImageColor(nil, bright[1], bright[2], bright[3], bright[4])
end

function FaultTracerDialog:onActionUnhighlight(element)
    if element == nil or element.id == nil then return end
    local bg = self[element.id .. "Bg"]
    if bg == nil or bg.setImageColor == nil then return end

    if element.id == "ftQuickScanBtn" then
        bg:setImageColor(nil, 0.12, 0.12, 0.18, 1)
    elseif element.id == "ftRepairBtn" then
        local allFlagged = self.grid ~= nil and FaultTracerGrid.allFaultsFlagged(self.grid)
        bg:setImageColor(nil,
            allFlagged and 0.1 or 0.05,
            allFlagged and 0.3 or 0.1,
            allFlagged and 0.1 or 0.05, 1)
    end
end

-- Screen 3: Type selection buttons (ftCorrodedBtn → ftCorrodedBtnBg, ftCancelBtn → ftCancelBtnBg)
function FaultTracerDialog:onTypeHighlight(element)
    if element == nil or element.id == nil then return end
    local bg = self[element.id .. "Bg"]
    if bg == nil or bg.setImageColor == nil then return end

    local base
    if element.id == "ftCancelBtn" then
        base = { 0.3, 0.1, 0.1, 1 }
    else
        base = { 0.12, 0.12, 0.16, 1 }
    end
    local bright = FaultTracerDialog.brightenColor(base)
    bg:setImageColor(nil, bright[1], bright[2], bright[3], bright[4])
end

function FaultTracerDialog:onTypeUnhighlight(element)
    if element == nil or element.id == nil then return end
    local bg = self[element.id .. "Bg"]
    if bg == nil or bg.setImageColor == nil then return end

    if element.id == "ftCancelBtn" then
        bg:setImageColor(nil, 0.3, 0.1, 0.1, 1)
    else
        bg:setImageColor(nil, 0.12, 0.12, 0.16, 1)
    end
end

-- ============================================================
-- Navigation
-- ============================================================

function FaultTracerDialog:onClickBack()
    if self.currentScreen == FaultTracerDialog.SCREEN_GRID then
        -- Go back to component selection
        self.grid = nil
        self.selectedComponent = nil
        self.currentScreen = FaultTracerDialog.SCREEN_COMPONENT
        self:updateDisplay()
    elseif self.currentScreen == FaultTracerDialog.SCREEN_TYPE_SELECT then
        -- Cancel type selection
        self.flaggingCell = nil
        self.currentScreen = FaultTracerDialog.SCREEN_GRID
        self:updateDisplay()
    elseif self.currentScreen == FaultTracerDialog.SCREEN_RESULTS then
        -- Close from results
        self:close()
    else
        self:close()
    end
end

function FaultTracerDialog:onClickClose()
    self:close()
end

UsedPlus.logInfo("FaultTracerDialog loaded - Fault Tracer minigame dialog ready")
