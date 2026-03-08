-- FS25_UsedPlus - Admin Control Panel
-- 5-tab debug/QA panel: State, Malfunctions, Spawning, Finance, Dialogs
-- v2.9.5: Initial | v2.15.0: Split layout | v2.15.1: Hover effects, status colors

AdminControlPanel = {}
local AdminControlPanel_mt = Class(AdminControlPanel, MessageDialog)

-- Tab indices (State first — shown on open for immediate vehicle diagnostics)
AdminControlPanel.TAB = {
    STATE = 1,
    MALFUNCTIONS = 2,
    SPAWNING = 3,
    FINANCE = 4,
    DIALOGS = 5
}

-- Tab colors
AdminControlPanel.COLORS = {
    TAB_INACTIVE = {0.1, 0.1, 0.15, 0.9},
    TAB_ACTIVE = {0.2, 0.3, 0.5, 1},
    TEXT_INACTIVE = {0.7, 0.7, 0.7, 1},
    TEXT_ACTIVE = {1, 0.9, 0.3, 1}
}

-- Diagnostic value colors (for State tab)
AdminControlPanel.DIAG = {
    GOOD     = {0.3, 1.0, 0.4, 1},    -- Green (>=75%)
    WARN     = {1.0, 0.9, 0.3, 1},    -- Yellow (50-74%)
    DANGER   = {1.0, 0.5, 0.2, 1},    -- Orange (25-49%)
    CRITICAL = {1.0, 0.2, 0.2, 1},    -- Red (<25%)
    INFO     = {0.6, 0.8, 1.0, 1},    -- Cyan (informational)
    SECTION  = {0.4, 0.6, 0.8, 1},    -- Blue-gray (section headers)
    LABEL    = {0.65, 0.65, 0.65, 1}, -- Gray (labels)
    ACTIVE   = {1.0, 0.3, 0.3, 1},    -- Red (active malfunction)
    INACTIVE = {0.5, 0.7, 0.5, 1},    -- Muted green (no malfunction)
    MAX_ROWS = 25                       -- Number of diagnostic rows in XML
}

-- Button hover colors (v2.15.1)
AdminControlPanel.COLORS.BTN_NORMAL = {0.12, 0.15, 0.2, 0.95}
AdminControlPanel.COLORS.BTN_HOVER  = {0.22, 0.28, 0.38, 1.0}
AdminControlPanel.COLORS.TAB_HOVER_INACTIVE = {0.16, 0.18, 0.26, 0.95}
AdminControlPanel.COLORS.TAB_HOVER_ACTIVE   = {0.25, 0.35, 0.55, 1}

-- Status bar severity colors (v2.15.1)
AdminControlPanel.COLORS.STATUS_OK    = {0.5, 0.9, 0.5, 1}
AdminControlPanel.COLORS.STATUS_WARN  = {1.0, 0.85, 0.3, 1}
AdminControlPanel.COLORS.STATUS_ERROR = {1.0, 0.35, 0.3, 1}

function AdminControlPanel.new(target, custom_mt, i18n)
    local self = MessageDialog.new(target, custom_mt or AdminControlPanel_mt)

    self.i18n = i18n or g_i18n
    self.currentTab = AdminControlPanel.TAB.STATE
    self.vehicle = nil
    self.statusClearTimer = 0

    return self
end

function AdminControlPanel:onGuiSetupFinished()
    AdminControlPanel:superClass().onGuiSetupFinished(self)

    -- Store tab element references
    self.tabBgs = {
        self.tabBg1, self.tabBg2, self.tabBg3, self.tabBg4, self.tabBg5
    }
    self.tabTexts = {
        self.tabText1, self.tabText2, self.tabText3, self.tabText4, self.tabText5
    }
    self.tabContents = {
        self.tabContent1, self.tabContent2, self.tabContent3, self.tabContent4, self.tabContent5
    }

    -- Store diagnostic row element references (State tab, left panel)
    self.diagLabels = {}
    self.diagValues = {}
    for i = 1, AdminControlPanel.DIAG.MAX_ROWS do
        self.diagLabels[i] = self["diagLabel" .. i]
        self.diagValues[i] = self["diagValue" .. i]
    end
end

-- ========== HOVER EFFECT HANDLERS (v2.15.1) ==========
-- Convention: btnXxx → bgXxx (strip "btn" prefix, add "bg")

function AdminControlPanel:onBtnHighlight(element)
    if element and element.id then
        local bgId = "bg" .. string.sub(element.id, 4)
        local bg = self[bgId]
        if bg and bg.setImageColor then
            bg:setImageColor(nil, unpack(AdminControlPanel.COLORS.BTN_HOVER))
        end
    end
end

function AdminControlPanel:onBtnUnhighlight(element)
    if element and element.id then
        local bgId = "bg" .. string.sub(element.id, 4)
        local bg = self[bgId]
        if bg and bg.setImageColor then
            bg:setImageColor(nil, unpack(AdminControlPanel.COLORS.BTN_NORMAL))
        end
    end
end

-- Tab hover: tabBtn1 → index 1 → self.tabBgs[1]
function AdminControlPanel:onTabHighlight(element)
    if element and element.id then
        local tabIndex = tonumber(string.sub(element.id, 7))
        if tabIndex and self.tabBgs[tabIndex] then
            local bg = self.tabBgs[tabIndex]
            if bg and bg.setImageColor then
                local color = (tabIndex == self.currentTab)
                    and AdminControlPanel.COLORS.TAB_HOVER_ACTIVE
                    or AdminControlPanel.COLORS.TAB_HOVER_INACTIVE
                bg:setImageColor(nil, color[1], color[2], color[3], color[4])
            end
        end
    end
end

function AdminControlPanel:onTabUnhighlight(element)
    if element and element.id then
        local tabIndex = tonumber(string.sub(element.id, 7))
        if tabIndex and self.tabBgs[tabIndex] then
            local bg = self.tabBgs[tabIndex]
            if bg and bg.setImageColor then
                local color = (tabIndex == self.currentTab)
                    and AdminControlPanel.COLORS.TAB_ACTIVE
                    or AdminControlPanel.COLORS.TAB_INACTIVE
                bg:setImageColor(nil, color[1], color[2], color[3], color[4])
            end
        end
    end
end

function AdminControlPanel:setVehicle(vehicle)
    self.vehicle = vehicle

    -- Vehicle context stored for diagnostics and action handlers
end

function AdminControlPanel:onOpen()
    AdminControlPanel:superClass().onOpen(self)

    -- Show the State tab first (vehicle diagnostics)
    self:switchToTab(AdminControlPanel.TAB.STATE)

    -- Load vehicle preview image
    self:updateVehicleImage()

    -- Update all tab-specific displays
    self:updateDiagnostics()
    self:updateFinanceInfo()

    -- Set initial status
    self:setStatus(g_i18n:getText("usedplus_admin_status_ready"))
end

function AdminControlPanel:updateVehicleImage()
    if self.vehicleImage == nil then return end

    if self.vehicle ~= nil then
        local storeItem = g_storeManager:getItemByXMLFilename(self.vehicle.configFileName)
        if storeItem ~= nil and storeItem.imageFilename ~= nil then
            self.vehicleImage:setImageFilename(storeItem.imageFilename)
            self.vehicleImage:setVisible(true)
            return
        end
    end

    self.vehicleImage:setVisible(false)
end

function AdminControlPanel:update(dt)
    AdminControlPanel:superClass().update(self, dt)

    -- Clear status after timeout
    if self.statusClearTimer > 0 then
        self.statusClearTimer = self.statusClearTimer - dt
        if self.statusClearTimer <= 0 then
            self:setStatus(g_i18n:getText("usedplus_admin_status_ready"))
        end
    end

    -- Delayed diagnostics refresh for async vehicle operations (damage, wear, hours)
    if self.pendingDiagRefresh and self.pendingDiagRefresh > 0 then
        self.pendingDiagRefresh = self.pendingDiagRefresh - dt
        if self.pendingDiagRefresh <= 0 then
            self.pendingDiagRefresh = nil
            self:updateDiagnostics()
        end
    end
end

function AdminControlPanel:switchToTab(tabIndex)
    self.currentTab = tabIndex

    -- Update tab backgrounds
    for i, bg in ipairs(self.tabBgs) do
        if bg and bg.setImageColor then
            if i == tabIndex then
                bg:setImageColor(nil, AdminControlPanel.COLORS.TAB_ACTIVE[1],
                    AdminControlPanel.COLORS.TAB_ACTIVE[2],
                    AdminControlPanel.COLORS.TAB_ACTIVE[3],
                    AdminControlPanel.COLORS.TAB_ACTIVE[4])
            else
                bg:setImageColor(nil, AdminControlPanel.COLORS.TAB_INACTIVE[1],
                    AdminControlPanel.COLORS.TAB_INACTIVE[2],
                    AdminControlPanel.COLORS.TAB_INACTIVE[3],
                    AdminControlPanel.COLORS.TAB_INACTIVE[4])
            end
        end
    end

    -- Update tab text colors
    for i, text in ipairs(self.tabTexts) do
        if text then
            if i == tabIndex then
                text:setTextColor(AdminControlPanel.COLORS.TEXT_ACTIVE[1],
                    AdminControlPanel.COLORS.TEXT_ACTIVE[2],
                    AdminControlPanel.COLORS.TEXT_ACTIVE[3],
                    AdminControlPanel.COLORS.TEXT_ACTIVE[4])
            else
                text:setTextColor(AdminControlPanel.COLORS.TEXT_INACTIVE[1],
                    AdminControlPanel.COLORS.TEXT_INACTIVE[2],
                    AdminControlPanel.COLORS.TEXT_INACTIVE[3],
                    AdminControlPanel.COLORS.TEXT_INACTIVE[4])
            end
        end
    end

    -- Show/hide tab content
    for i, content in ipairs(self.tabContents) do
        if content then
            content:setVisible(i == tabIndex)
        end
    end
end

function AdminControlPanel:updateFinanceInfo()
    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)

    -- Row 1: Balance
    if self.finLabel1 then
        self.finLabel1:setText(g_i18n:getText("usedplus_acp_balance"))
        self.finLabel1:setTextColor(0.65, 0.65, 0.65, 1)
    end
    if self.finValue1 and farm then
        self.finValue1:setText(g_i18n:formatMoney(farm.money, 0, true, true))
        local balColor = farm.money >= 0 and AdminControlPanel.DIAG.GOOD or AdminControlPanel.DIAG.CRITICAL
        self.finValue1:setTextColor(balColor[1], balColor[2], balColor[3], balColor[4])
    end

    -- Row 2: Credit Score
    if self.finLabel2 then
        self.finLabel2:setText(g_i18n:getText("usedplus_acp_creditScore"))
        self.finLabel2:setTextColor(0.65, 0.65, 0.65, 1)
    end
    if self.finValue2 and CreditScore then
        local score = CreditScore.calculate(farmId)
        local rating = CreditScore.getRating(score)
        self.finValue2:setText(string.format("%d (%s)", score, rating))
        local scoreColor = self:getPercentColor(score / 8.5)  -- 850 max → 100%
        self.finValue2:setTextColor(scoreColor[1], scoreColor[2], scoreColor[3], scoreColor[4])
    end

    -- Row 3: Active Deals
    if self.finLabel3 then
        self.finLabel3:setText(g_i18n:getText("usedplus_acp_activeDeals"))
        self.finLabel3:setTextColor(0.65, 0.65, 0.65, 1)
    end
    if self.finValue3 and g_financeManager then
        local deals = g_financeManager:getDealsForFarm(farmId)
        local count = deals and #deals or 0
        self.finValue3:setText(tostring(count))
        self.finValue3:setTextColor(AdminControlPanel.DIAG.INFO[1], AdminControlPanel.DIAG.INFO[2],
            AdminControlPanel.DIAG.INFO[3], AdminControlPanel.DIAG.INFO[4])
    end

    -- Row 4: Total Debt
    if self.finLabel4 then
        self.finLabel4:setText(g_i18n:getText("usedplus_acp_totalDebt"))
        self.finLabel4:setTextColor(0.65, 0.65, 0.65, 1)
    end
    if self.finValue4 and g_financeManager then
        local deals = g_financeManager:getDealsForFarm(farmId)
        local totalDebt = 0
        if deals then
            for _, deal in ipairs(deals) do
                totalDebt = totalDebt + (deal.remainingBalance or 0)
            end
        end
        self.finValue4:setText(g_i18n:formatMoney(totalDebt, 0, true, true))
        local debtColor = totalDebt > 0 and AdminControlPanel.DIAG.WARN or AdminControlPanel.DIAG.GOOD
        self.finValue4:setTextColor(debtColor[1], debtColor[2], debtColor[3], debtColor[4])
    end

    -- Row 5: clear (reserved)
    if self.finLabel5 then self.finLabel5:setText("") end
    if self.finValue5 then self.finValue5:setText("") end
end


function AdminControlPanel:setStatus(message, duration, severity)
    if self.statusText then
        self.statusText:setText(message or "")
        local colorKey = "STATUS_" .. string.upper(severity or "ok")
        local color = AdminControlPanel.COLORS[colorKey] or AdminControlPanel.COLORS.STATUS_OK
        self.statusText:setTextColor(color[1], color[2], color[3], color[4])
    end
    self.statusClearTimer = duration or 5000
end

function AdminControlPanel:requireVehicle()
    if not self.vehicle then
        self:setStatus("Error: No vehicle context", nil, "error")
        return false
    end

    local spec = self.vehicle.spec_usedPlusMaintenance
    if not spec then
        self:setStatus("Error: Vehicle has no maintenance data", nil, "error")
        return false
    end

    return true
end

function AdminControlPanel:onCancel()
    -- Clear any armed DNA overrides (principle of least surprise)
    UsedPlus.forcedDNA = nil
    self:close()
end

-- ========== TAB CLICK HANDLERS ==========

function AdminControlPanel:onTab1Click()
    self:switchToTab(AdminControlPanel.TAB.STATE)
    self:updateDiagnostics()
end

function AdminControlPanel:onTab2Click()
    self:switchToTab(AdminControlPanel.TAB.MALFUNCTIONS)
end

function AdminControlPanel:onTab3Click()
    self:switchToTab(AdminControlPanel.TAB.SPAWNING)
end

function AdminControlPanel:onTab4Click()
    self:switchToTab(AdminControlPanel.TAB.FINANCE)
    self:updateFinanceInfo()
end

function AdminControlPanel:onTab5Click()
    self:switchToTab(AdminControlPanel.TAB.DIALOGS)
end

-- ========== TAB 2: MALFUNCTION HANDLERS ==========

function AdminControlPanel:onStallClick()
    if not self:requireVehicle() then return end

    if UsedPlusMaintenance and UsedPlusMaintenance.triggerEngineStall then
        UsedPlusMaintenance.triggerEngineStall(self.vehicle)
        self:setStatus(string.format("Triggered stall on %s", self.vehicle:getName() or "vehicle"))
    else
        self:setStatus("Error: triggerEngineStall not found", nil, "error")
    end
end

function AdminControlPanel:onMisfireClick()
    if not self:requireVehicle() then return end

    local spec = self.vehicle.spec_usedPlusMaintenance
    local config = UsedPlusMaintenance.CONFIG
    spec.misfireActive = true
    spec.misfireEndTime = (g_currentMission.time or 0) + math.random(config.misfireDurationMin, config.misfireDurationMax)
    UsedPlusMaintenance.recordMalfunctionTime(self.vehicle)

    self:setStatus(string.format("Triggered misfire on %s", self.vehicle:getName() or "vehicle"))
end

function AdminControlPanel:onOverheatClick()
    if not self:requireVehicle() then return end

    local spec = self.vehicle.spec_usedPlusMaintenance
    spec.engineTemperature = 0.95  -- Critical overheat threshold

    -- Trigger actual overheat stall
    if self.vehicle.stopMotor then
        self.vehicle:stopMotor()
    end
    spec.isOverheated = true
    spec.overheatCooldownEndTime = (g_currentMission.time or 0) + (UsedPlusMaintenance.CONFIG.overheatCooldownMs or 120000)
    spec.failureCount = (spec.failureCount or 0) + 1
    spec.hasShownOverheatWarning = false
    spec.hasShownOverheatCritical = false

    UsedPlusMaintenance.recordMalfunctionTime(self.vehicle)

    -- Apply breakdown degradation
    if UsedPlusMaintenance.applyBreakdownDegradation then
        UsedPlusMaintenance.applyBreakdownDegradation(self.vehicle, "Engine")
    end

    self:setStatus(string.format("CRITICAL: Triggered overheat stall at 95%% on %s", self.vehicle:getName() or "vehicle"))
end

function AdminControlPanel:onRunawayClick()
    if not self:requireVehicle() then return end

    local spec = self.vehicle.spec_usedPlusMaintenance
    spec.runawayActive = true
    spec.runawayStartTime = g_currentMission.time or 0
    spec.runawayPreviousSpeed = self.vehicle.getLastSpeed and self.vehicle:getLastSpeed() or 0
    spec.runawayPreviousDamage = self.vehicle:getVehicleDamage() or 0
    UsedPlusMaintenance.recordMalfunctionTime(self.vehicle)

    UsedPlusMaintenance.showWarning(self.vehicle,
        g_i18n:getText("usedplus_warning_runaway") or "ENGINE RUNAWAY!",
        5000, "runaway")

    self:setStatus(string.format("Triggered runaway on %s", self.vehicle:getName() or "vehicle"))
end

function AdminControlPanel:onSeizureClick()
    if not self:requireVehicle() then return end

    if UsedPlusMaintenance and UsedPlusMaintenance.seizeComponent then
        UsedPlusMaintenance.seizeComponent(self.vehicle, "engine")
        self:setStatus(string.format("PERMANENT: Engine seized on %s", self.vehicle:getName() or "vehicle"))
    else
        self:setStatus("Error: seizeComponent not found", nil, "error")
    end
end

function AdminControlPanel:onCutoutClick()
    if not self:requireVehicle() then return end

    if UsedPlusMaintenance and UsedPlusMaintenance.triggerImplementCutout then
        UsedPlusMaintenance.triggerImplementCutout(self.vehicle)
        self:setStatus(string.format("Triggered cutout on %s", self.vehicle:getName() or "vehicle"))
    else
        self:setStatus("Error: triggerImplementCutout not found", nil, "error")
    end
end

function AdminControlPanel:onSurgeLClick()
    if not self:requireVehicle() then return end

    local spec = self.vehicle.spec_usedPlusMaintenance
    local config = UsedPlusMaintenance.CONFIG
    local currentTime = g_currentMission.time or 0

    spec.hydraulicSurgeActive = true
    spec.hydraulicSurgeEndTime = currentTime + math.random(config.hydraulicSurgeDurationMin, config.hydraulicSurgeDurationMax)
    spec.hydraulicSurgeFadeStartTime = spec.hydraulicSurgeEndTime - config.hydraulicSurgeFadeTime
    spec.hydraulicSurgeDirection = -1  -- Left
    UsedPlusMaintenance.recordMalfunctionTime(self.vehicle)

    self:setStatus(string.format("Triggered hydraulic surge (LEFT) on %s", self.vehicle:getName() or "vehicle"))
end

function AdminControlPanel:onSurgeRClick()
    if not self:requireVehicle() then return end

    local spec = self.vehicle.spec_usedPlusMaintenance
    local config = UsedPlusMaintenance.CONFIG
    local currentTime = g_currentMission.time or 0

    spec.hydraulicSurgeActive = true
    spec.hydraulicSurgeEndTime = currentTime + math.random(config.hydraulicSurgeDurationMin, config.hydraulicSurgeDurationMax)
    spec.hydraulicSurgeFadeStartTime = spec.hydraulicSurgeEndTime - config.hydraulicSurgeFadeTime
    spec.hydraulicSurgeDirection = 1  -- Right
    UsedPlusMaintenance.recordMalfunctionTime(self.vehicle)

    self:setStatus(string.format("Triggered hydraulic surge (RIGHT) on %s", self.vehicle:getName() or "vehicle"))
end

function AdminControlPanel:onFlatLClick()
    if not self:requireVehicle() then return end

    local spec = self.vehicle.spec_usedPlusMaintenance
    spec.hasFlatTire = true
    spec.flatTireSide = -1  -- Left
    spec.hasShownFlatTireWarning = false  -- Changed to false - allows warning to show
    spec.failureCount = (spec.failureCount or 0) + 1
    UsedPlusMaintenance.recordMalfunctionTime(self.vehicle)

    -- Manually show warning now
    if UsedPlusMaintenance.showWarning then
        UsedPlusMaintenance.showWarning(self.vehicle,
            g_i18n:getText("usedplus_warning_flattire") or "FLAT TIRE!",
            5000, "flattire")
    end

    self:setStatus(string.format("Triggered flat tire (LEFT) on %s", self.vehicle:getName() or "vehicle"))
end

function AdminControlPanel:onFlatRClick()
    if not self:requireVehicle() then return end

    local spec = self.vehicle.spec_usedPlusMaintenance
    spec.hasFlatTire = true
    spec.flatTireSide = 1  -- Right
    spec.hasShownFlatTireWarning = false  -- Changed to false - allows warning to show
    spec.failureCount = (spec.failureCount or 0) + 1
    UsedPlusMaintenance.recordMalfunctionTime(self.vehicle)

    -- Manually show warning now
    if UsedPlusMaintenance.showWarning then
        UsedPlusMaintenance.showWarning(self.vehicle,
            g_i18n:getText("usedplus_warning_flattire") or "FLAT TIRE!",
            5000, "flattire")
    end

    self:setStatus(string.format("Triggered flat tire (RIGHT) on %s", self.vehicle:getName() or "vehicle"))
end

-- ========== TAB 3: SPAWNING HANDLERS ==========

function AdminControlPanel:onSpawnObdClick()
    -- Spawn Field Service Kit at player position
    local player = g_localPlayer
    if not player then
        self:setStatus("Error: No local player", nil, "error")
        return
    end

    -- Use shop system to buy item
    local xmlFile = UsedPlus.MOD_DIR .. "vehicles/fieldServiceKit/fieldServiceKit.xml"
    local storeItem = g_storeManager:getItemByXMLFilename(xmlFile)

    if not storeItem then
        self:setStatus("Error: Field Service Kit not found in store", nil, "error")
        return
    end

    -- Create BuyVehicleData - proper FS25 API (position handled automatically)
    local buyData = BuyVehicleData.new()
    buyData:setOwnerFarmId(g_currentMission:getFarmId())
    buyData:setPrice(0)  -- Admin spawn - no cost
    buyData:setStoreItem(storeItem)
    buyData:setConfigurations({})

    if buyData.setConfigurationData then
        buyData:setConfigurationData({})
    end
    if buyData.setLicensePlateData then
        buyData:setLicensePlateData(nil)
    end

    self:setStatus("Spawning OBD Scanner at player location...")
    g_client:getServerConnection():sendEvent(BuyVehicleEvent.new(buyData))
end

function AdminControlPanel:onSpawnTruckClick()
    -- Spawn Service Truck (bypasses discovery)
    local player = g_localPlayer
    if not player then
        self:setStatus("Error: No local player", nil, "error")
        return
    end

    local xmlFile = UsedPlus.MOD_DIR .. "vehicles/serviceTruck/serviceTruck.xml"
    local storeItem = g_storeManager:getItemByXMLFilename(xmlFile)

    if not storeItem then
        self:setStatus("Error: Service Truck not found in store", nil, "error")
        return
    end

    -- Create BuyVehicleData - proper FS25 API (position handled automatically)
    local buyData = BuyVehicleData.new()
    buyData:setOwnerFarmId(g_currentMission:getFarmId())
    buyData:setPrice(0)  -- Admin spawn - no cost
    buyData:setStoreItem(storeItem)
    buyData:setConfigurations({})

    if buyData.setConfigurationData then
        buyData:setConfigurationData({})
    end
    if buyData.setLicensePlateData then
        buyData:setLicensePlateData(nil)
    end

    self:setStatus("Spawning Service Truck...")
    g_client:getServerConnection():sendEvent(BuyVehicleEvent.new(buyData))
end

function AdminControlPanel:onSpawnPartsClick()
    local player = g_localPlayer
    if not player then
        self:setStatus("Error: No local player", nil, "error")
        return
    end

    local xmlFile = UsedPlus.MOD_DIR .. "vehicles/sparePartsPallet/sparePartsPallet.xml"
    local storeItem = g_storeManager:getItemByXMLFilename(xmlFile)

    if not storeItem then
        self:setStatus("Error: Spare Parts Pallet not found in store", nil, "error")
        return
    end

    -- Create BuyVehicleData - proper FS25 API (position handled automatically)
    local buyData = BuyVehicleData.new()
    buyData:setOwnerFarmId(g_currentMission:getFarmId())
    buyData:setPrice(0)  -- Admin spawn - no cost
    buyData:setStoreItem(storeItem)
    buyData:setConfigurations({})

    if buyData.setConfigurationData then
        buyData:setConfigurationData({})
    end
    if buyData.setLicensePlateData then
        buyData:setLicensePlateData(nil)
    end

    self:setStatus("Spawning Spare Parts Pallet...")
    g_client:getServerConnection():sendEvent(BuyVehicleEvent.new(buyData))
end

function AdminControlPanel:onTriggerDiscoveryClick()
    local farmId = g_currentMission:getFarmId()

    if ServiceTruckDiscovery then
        ServiceTruckDiscovery.triggerDiscovery(farmId, "admin_panel")
        self:setStatus(string.format("Triggered Service Truck discovery for farm %d", farmId))
    else
        self:setStatus("Error: ServiceTruckDiscovery not loaded", nil, "error")
    end
end

function AdminControlPanel:onResetDiscoveryClick()
    local farmId = g_currentMission:getFarmId()

    if ServiceTruckDiscovery then
        ServiceTruckDiscovery.resetDiscovery(farmId)
        self:setStatus(string.format("Reset discovery state for farm %d", farmId))
    else
        self:setStatus("Error: ServiceTruckDiscovery not loaded", nil, "error")
    end
end

function AdminControlPanel:onDiscoveryStatusClick()
    if not UsedPlus.DEBUG then
        self:setStatus("Enable Debug mode first (State tab > Debug toggle)", nil, "warn")
        return
    end

    if UsedPlus and UsedPlus.consoleCommandServiceTruckStatus then
        UsedPlus:consoleCommandServiceTruckStatus()
        self:setStatus("Discovery status printed to console (F8)")
    else
        self:setStatus("Error: consoleCommandServiceTruckStatus not found", nil, "error")
    end
end

function AdminControlPanel:spawnRandomTractor(dna, label)
    UsedPlus.forcedDNA = dna

    local tractors = {}
    local storeItems = g_storeManager:getItems()
    if storeItems then
        for _, item in ipairs(storeItems) do
            if item.categoryName and string.find(item.categoryName, "TRACTOR") then
                table.insert(tractors, item)
            end
        end
    end

    if #tractors == 0 then
        UsedPlus.forcedDNA = nil
        self:setStatus("Error: No tractors found in store", nil, "error")
        return
    end

    local storeItem = tractors[math.random(#tractors)]

    local buyData = BuyVehicleData.new()
    buyData:setOwnerFarmId(g_currentMission:getFarmId())
    buyData:setPrice(0)
    buyData:setStoreItem(storeItem)
    buyData:setConfigurations({})

    if buyData.setConfigurationData then
        buyData:setConfigurationData({})
    end
    if buyData.setLicensePlateData then
        buyData:setLicensePlateData(nil)
    end

    self:setStatus(string.format("Spawning %s (DNA %.1f): %s...", label, dna, storeItem.name or "tractor"))
    g_client:getServerConnection():sendEvent(BuyVehicleEvent.new(buyData))
end

function AdminControlPanel:onSpawnLemonClick()
    self:spawnRandomTractor(0.1, "Lemon")
end

function AdminControlPanel:onSpawnWorkhorseClick()
    self:spawnRandomTractor(0.9, "Workhorse")
end

function AdminControlPanel:onSpawnDamagedClick()
    self:spawnRandomTractor(math.random() * 0.4 + 0.1, "Damaged")
end

-- Apply damage/wear using addDamageAmount/addWearAmount (the proven server-safe pattern)
-- setDamage()/setWearAmount() are async network ops that don't apply reliably from UI context
function AdminControlPanel:applyDamageWear(targetDamage, targetWear)
    local currentDamage = (self.vehicle.getDamageAmount and self.vehicle:getDamageAmount()) or 0
    local damageDelta = targetDamage - currentDamage
    if self.vehicle.addDamageAmount and math.abs(damageDelta) > 0.001 then
        self.vehicle:addDamageAmount(damageDelta, true)
    end

    local currentWear = 0
    if self.vehicle.getWearTotalAmount then
        currentWear = self.vehicle:getWearTotalAmount() or 0
    end
    local wearDelta = targetWear - currentWear
    if self.vehicle.addWearAmount and math.abs(wearDelta) > 0.001 then
        self.vehicle:addWearAmount(wearDelta, true)
    end
end

function AdminControlPanel:onPaintPristineClick()
    if not self:requireVehicle() then return end
    self:applyDamageWear(0, 0)

    local spec = self.vehicle.spec_usedPlusMaintenance
    if spec then
        spec.engineReliability = 1.0
        spec.hydraulicReliability = 1.0
        spec.electricalReliability = 1.0
    end

    self:setStatus(string.format("Painted %s to pristine condition", self.vehicle:getName() or "vehicle"))
    self:updateDiagnostics()
    self.pendingDiagRefresh = 500
end

function AdminControlPanel:onPaintWornClick()
    if not self:requireVehicle() then return end
    self:applyDamageWear(0.1, 0.3)

    local spec = self.vehicle.spec_usedPlusMaintenance
    if spec then
        spec.engineReliability = 0.75
        spec.hydraulicReliability = 0.8
        spec.electricalReliability = 0.75
    end

    self:setStatus(string.format("Painted %s to worn condition", self.vehicle:getName() or "vehicle"))
    self:updateDiagnostics()
    self.pendingDiagRefresh = 500
end

function AdminControlPanel:onPaintBeatenClick()
    if not self:requireVehicle() then return end
    self:applyDamageWear(0.6, 0.5)

    local spec = self.vehicle.spec_usedPlusMaintenance
    if spec then
        spec.engineReliability = 0.45
        spec.hydraulicReliability = 0.5
        spec.electricalReliability = 0.4
    end

    self:setStatus(string.format("Painted %s to beaten condition", self.vehicle:getName() or "vehicle"))
    self:updateDiagnostics()
    self.pendingDiagRefresh = 500
end

function AdminControlPanel:onPaintDestroyedClick()
    if not self:requireVehicle() then return end
    self:applyDamageWear(0.95, 0.8)

    local spec = self.vehicle.spec_usedPlusMaintenance
    if spec then
        spec.engineReliability = 0.2
        spec.hydraulicReliability = 0.3
        spec.electricalReliability = 0.25
    end

    self:setStatus(string.format("Painted %s to destroyed condition", self.vehicle:getName() or "vehicle"))
    self:updateDiagnostics()
    self.pendingDiagRefresh = 500
end

-- ========== TAB 4: FINANCE HANDLERS ==========

function AdminControlPanel:addMoney(amount)
    local farm = g_farmManager:getFarmById(g_currentMission:getFarmId())
    if farm then
        farm:changeBalance(amount, MoneyType.OTHER)
        self:updateFinanceInfo()
        self:setStatus(string.format("Added %s to farm", g_i18n:formatMoney(amount, 0, true, true)))
    end
end

function AdminControlPanel:onAdd10kClick()
    self:addMoney(10000)
end

function AdminControlPanel:onAdd100kClick()
    self:addMoney(100000)
end

function AdminControlPanel:onAdd1mClick()
    self:addMoney(1000000)
end

function AdminControlPanel:onSetZeroClick()
    local farm = g_farmManager:getFarmById(g_currentMission:getFarmId())
    if farm then
        local diff = -farm.money
        farm:changeBalance(diff, MoneyType.OTHER)
        self:updateFinanceInfo()
        self:setStatus("Set farm balance to $0")
    end
end

function AdminControlPanel:setCredit(targetScore)
    local farmId = g_currentMission:getFarmId()

    if not PaymentTracker then
        self:setStatus("Error: PaymentTracker not available", nil, "error")
        return
    end

    local data = PaymentTracker.getFarmData(farmId)

    -- Reset penalties for clean slate
    data.stats.missedPayments = 0
    data.stats.latePayments = 0
    data.stats.lastMissedIndex = 0

    -- Binary search for the right number of on-time payments to reach target
    -- CreditScore = base(500) + historyScore(0-250) + assetScore + cashScore
    -- We only control historyScore via PaymentTracker stats
    local lo, hi = 0, 125
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        data.stats.totalPayments = mid
        data.stats.onTimePayments = mid
        data.stats.currentStreak = mid
        data.stats.longestStreak = mid
        local score = CreditScore.calculate(farmId)
        if score < targetScore then
            lo = mid + 1
        else
            hi = mid
        end
    end

    data.stats.totalPayments = lo
    data.stats.onTimePayments = lo
    data.stats.currentStreak = lo
    data.stats.longestStreak = lo

    local score = CreditScore.calculate(farmId)
    local rating = CreditScore.getRating(score)
    self:setStatus(string.format("Credit set to %d (%s)", score, rating))
    self:updateFinanceInfo()
end

function AdminControlPanel:onCredit850Click()
    self:setCredit(850)
end

function AdminControlPanel:onCredit700Click()
    self:setCredit(700)
end

function AdminControlPanel:onCredit550Click()
    self:setCredit(550)
end

function AdminControlPanel:onCredit400Click()
    self:setCredit(400)
end

function AdminControlPanel:onCredit300Click()
    self:setCredit(300)
end

function AdminControlPanel:onPayoffAllClick()
    if UsedPlus and UsedPlus.consoleCommandPayoffAll then
        local result = UsedPlus:consoleCommandPayoffAll()
        self:setStatus(result or "Paid off all deals")
        self:updateFinanceInfo()
    else
        self:setStatus("Error: consoleCommandPayoffAll not found", nil, "error")
    end
end

function AdminControlPanel:onCreditUpClick()
    local farmId = g_currentMission:getFarmId()
    if not PaymentTracker then
        self:setStatus("Error: PaymentTracker not available", nil, "error")
        return
    end

    -- Add 25 on-time payments to stats (~50 base points)
    local data = PaymentTracker.getFarmData(farmId)
    data.stats.totalPayments = data.stats.totalPayments + 25
    data.stats.onTimePayments = data.stats.onTimePayments + 25
    data.stats.currentStreak = data.stats.currentStreak + 25
    if data.stats.currentStreak > data.stats.longestStreak then
        data.stats.longestStreak = data.stats.currentStreak
    end

    local score = CreditScore.calculate(farmId)
    local rating = CreditScore.getRating(score)
    self:setStatus(string.format("Credit nudged up → %d (%s)", score, rating))
    self:updateFinanceInfo()
end

function AdminControlPanel:onCreditDownClick()
    local farmId = g_currentMission:getFarmId()
    if not PaymentTracker then
        self:setStatus("Error: PaymentTracker not available", nil, "error")
        return
    end

    -- Remove 25 on-time payments from stats (~50 base points)
    local data = PaymentTracker.getFarmData(farmId)
    data.stats.onTimePayments = math.max(0, data.stats.onTimePayments - 25)
    data.stats.currentStreak = math.max(0, data.stats.currentStreak - 25)

    local score = CreditScore.calculate(farmId)
    local rating = CreditScore.getRating(score)
    self:setStatus(string.format("Credit nudged down → %d (%s)", score, rating))
    self:updateFinanceInfo()
end

-- ========== TAB 5: DIALOG HANDLERS ==========

-- Dialog handlers: dialogs open ON TOP of AdminCP (no self:close()).
-- When the target dialog closes, the user returns to AdminCP automatically.

function AdminControlPanel:onDlgLoanClick()
    local farmId = g_currentMission:getFarmId()
    DialogLoader.show("TakeLoanDialog", "setFarmId", farmId)
    self:setStatus("Opened Take Loan dialog")
end

function AdminControlPanel:onDlgApprovedClick()
    local mockDetails = {
        amount = 100000,
        termYears = 5,
        interestRate = 0.08,
        monthlyPayment = 2028,
        yearlyPayment = 24336,
        totalPayment = 121680,
        totalInterest = 21680,
        collateralCount = 2,
        previousScore = 700,
        previousRating = "Good",
        creditImpact = -5,
        newScore = 695,
        newRating = "Fair"
    }
    if LoanApprovedDialog and LoanApprovedDialog.show then
        LoanApprovedDialog.show(mockDetails)
        self:setStatus("Opened Loan Approved dialog (mock data)")
    else
        self:setStatus("Error: LoanApprovedDialog not available", nil, "error")
    end
end

function AdminControlPanel:onDlgCreditClick()
    DialogLoader.show("CreditReportDialog")
    self:setStatus("Opened Credit Report dialog")
end

function AdminControlPanel:onDlgHistoryClick()
    if g_financeManager then
        local farmId = g_currentMission:getFarmId()
        local deals = g_financeManager:getDealsForFarm(farmId)
        if deals and #deals > 0 then
            DialogLoader.show("PaymentHistoryDialog", "setDeal", deals[1])
            self:setStatus("Opened Payment History dialog")
        else
            self:setStatus("No active deals to show history for", nil, "warn")
        end
    else
        self:setStatus("Error: FinanceManager not available", nil, "error")
    end
end

function AdminControlPanel:onDlgRepoClick()
    -- RepossessionDialog:setData expects a data table
    local mockData = {
        vehicleName = "Test Vehicle",
        remainingBalance = 50000,
        missedPayments = 3
    }
    DialogLoader.show("RepossessionDialog", "setData", mockData)
    self:setStatus("Opened Repossession dialog (mock data)")
end

function AdminControlPanel:onDlgSearchClick()
    local storeItems = g_storeManager:getItems()
    if storeItems and #storeItems > 0 then
        for _, item in ipairs(storeItems) do
            if item.categoryName and string.find(item.categoryName, "TRACTOR") then
                DialogLoader.show("UsedSearchDialog", "setData", item, item.xmlFilename, g_currentMission:getFarmId())
                self:setStatus("Opened Used Search dialog")
                return
            end
        end
    end
    self:setStatus("No tractor store items found for search dialog", nil, "warn")
end

function AdminControlPanel:onDlgPurchaseClick()
    if not self.vehicle then
        self:setStatus("Need to be in a vehicle", nil, "warn")
        return
    end

    local xmlFilename = self.vehicle.configFileName
    local storeItem = g_storeManager:getItemByXMLFilename(xmlFilename)

    if storeItem then
        local price = storeItem.price or 100000
        local saleItem = {
            price = price,
            storeItem = storeItem,
            vehicle = self.vehicle
        }

        if UnifiedPurchaseDialog and UnifiedPurchaseDialog.show then
            UnifiedPurchaseDialog.show(storeItem, price, saleItem, "cash")
            self:setStatus("Opened Purchase dialog")
        else
            DialogLoader.show("UnifiedPurchaseDialog", "setVehicleData", storeItem, price, saleItem, nil)
            self:setStatus("Opened Purchase dialog via loader")
        end
    else
        self:setStatus("Could not find store item for current vehicle", nil, "error")
    end
end

function AdminControlPanel:onDlgNegotiateClick()
    self:setStatus("Negotiate Dialog: Requires active search result", nil, "warn")
end

function AdminControlPanel:onDlgSellerClick()
    self:setStatus("Seller Response Dialog: Requires negotiation context", nil, "warn")
end

function AdminControlPanel:onDlgObdClick()
    if self.vehicle then
        DialogLoader.show("FieldServiceKitDialog", "setData", self.vehicle, nil, "master")
        self:setStatus("Opened OBD Scanner dialog")
    else
        self:setStatus("Need to be in a vehicle", nil, "warn")
    end
end

function AdminControlPanel:onDlgServiceClick()
    self:setStatus("Service Truck Dialog: Requires Service Truck context", nil, "warn")
end

function AdminControlPanel:onDlgInspectClick()
    if not self.vehicle then
        self:setStatus("Need to be in a vehicle", nil, "warn")
        return
    end

    if InspectionReportDialog and InspectionReportDialog.show then
        InspectionReportDialog.show(self.vehicle)
        self:setStatus("Opened Inspection Report dialog")
    else
        self:setStatus("Inspect Dialog: Requires inspection listing data", nil, "warn")
    end
end

function AdminControlPanel:onDlgLeaseEndClick()
    self:setStatus("Lease End Dialog: Requires an active lease", nil, "warn")
end

function AdminControlPanel:onDlgLeaseRenewClick()
    self:setStatus("Lease Renewal Dialog: Requires an active lease", nil, "warn")
end

function AdminControlPanel:onDlgFaultTracerClick()
    if self.vehicle then
        DialogLoader.show("FaultTracerDialog", "setData", self.vehicle, nil)
        self:setStatus("Opened Fault Tracer dialog")
    else
        self:setStatus("Need to be in a vehicle", nil, "warn")
    end
end

function AdminControlPanel:onDlgPortfolioClick()
    if VehiclePortfolioDialog and VehiclePortfolioDialog.getInstance then
        local dialog = VehiclePortfolioDialog.getInstance()
        if dialog then
            dialog:show()
            self:setStatus("Opened Vehicle Portfolio dialog")
        else
            self:setStatus("Error: VehiclePortfolioDialog instance unavailable", nil, "error")
        end
    else
        self:setStatus("Error: VehiclePortfolioDialog not available", nil, "error")
    end
end

-- ========== TAB 1: STATE - RELIABILITY (per-system) ==========

function AdminControlPanel:setReliability(system, value)
    if not self:requireVehicle() then return end
    local spec = self.vehicle.spec_usedPlusMaintenance
    spec[system] = value
    self:setStatus(string.format("Set %s to %.0f%%", system, value * 100))
    self:updateDiagnostics()
end

function AdminControlPanel:onEngRel100Click() self:setReliability("engineReliability", 1.0) end
function AdminControlPanel:onEngRel50Click()  self:setReliability("engineReliability", 0.5) end
function AdminControlPanel:onEngRel10Click()  self:setReliability("engineReliability", 0.1) end
function AdminControlPanel:onHydRel100Click() self:setReliability("hydraulicReliability", 1.0) end
function AdminControlPanel:onHydRel50Click()  self:setReliability("hydraulicReliability", 0.5) end
function AdminControlPanel:onHydRel10Click()  self:setReliability("hydraulicReliability", 0.1) end
function AdminControlPanel:onElecRel100Click() self:setReliability("electricalReliability", 1.0) end
function AdminControlPanel:onElecRel50Click()  self:setReliability("electricalReliability", 0.5) end
function AdminControlPanel:onElecRel10Click()  self:setReliability("electricalReliability", 0.1) end

-- ========== TAB 1: STATE - CONDITION ==========

function AdminControlPanel:onRepairDamageClick()
    if not self:requireVehicle() then return end
    local currentDamage = (self.vehicle.getDamageAmount and self.vehicle:getDamageAmount()) or 0
    if currentDamage > 0 and self.vehicle.addDamageAmount then
        self.vehicle:addDamageAmount(-currentDamage, true)
        self:setStatus(string.format("Repaired all damage on %s", self.vehicle:getName() or "vehicle"))
    elseif currentDamage <= 0 then
        self:setStatus("Vehicle already at 0% damage")
    else
        self:setStatus("Error: Cannot repair damage on this vehicle", nil, "error")
    end
    self:updateDiagnostics()
    self.pendingDiagRefresh = 500
end

function AdminControlPanel:onPaintWearClick()
    if not self:requireVehicle() then return end
    local currentWear = 0
    if self.vehicle.getWearTotalAmount then
        currentWear = self.vehicle:getWearTotalAmount() or 0
    end
    if currentWear > 0 and self.vehicle.addWearAmount then
        self.vehicle:addWearAmount(-currentWear, true)
        self:setStatus(string.format("Repainted %s (wear removed)", self.vehicle:getName() or "vehicle"))
    elseif currentWear <= 0 then
        self:setStatus("Vehicle already at 0% wear")
    else
        self:setStatus("Error: Cannot remove wear on this vehicle", nil, "error")
    end
    self:updateDiagnostics()
    self.pendingDiagRefresh = 500
end

function AdminControlPanel:onResetHoursClick()
    if not self:requireVehicle() then return end

    if self.vehicle.setOperatingTime then
        self.vehicle:setOperatingTime(0)
        self:setStatus("Reset operating hours to 0")
    else
        self:setStatus("Error: Cannot reset operating hours", nil, "error")
    end
    self:updateDiagnostics()
    self.pendingDiagRefresh = 500
end

function AdminControlPanel:onAddHoursClick()
    if not self:requireVehicle() then return end

    if self.vehicle.setOperatingTime then
        local currentHours = self.vehicle:getOperatingTime() or 0
        local HOURS_TO_ADD = 1000
        local MS_PER_HOUR = 3600000  -- 60 min × 60 sec × 1000 ms
        local newHours = currentHours + (HOURS_TO_ADD * MS_PER_HOUR)
        self.vehicle:setOperatingTime(newHours)
        self:setStatus("Added 1000 operating hours")
    else
        self:setStatus("Error: Cannot modify operating hours", nil, "error")
    end
    self:updateDiagnostics()
    self.pendingDiagRefresh = 500
end

-- ========== TAB 1: STATE - DNA FORCING ==========

function AdminControlPanel:onDnaLemonClick()
    if not self:requireVehicle() then return end
    local spec = self.vehicle.spec_usedPlusMaintenance
    spec.workhorseLemonScale = 0.1
    self:setStatus(string.format("Set DNA to 0.1 (LEMON) on %s", self.vehicle:getName() or "vehicle"))
    self:updateDiagnostics()
end

function AdminControlPanel:onDnaAverageClick()
    if not self:requireVehicle() then return end
    local spec = self.vehicle.spec_usedPlusMaintenance
    spec.workhorseLemonScale = 0.5
    self:setStatus(string.format("Set DNA to 0.5 (AVERAGE) on %s", self.vehicle:getName() or "vehicle"))
    self:updateDiagnostics()
end

function AdminControlPanel:onDnaWorkhorseClick()
    if not self:requireVehicle() then return end
    local spec = self.vehicle.spec_usedPlusMaintenance
    spec.workhorseLemonScale = 0.9
    self:setStatus(string.format("Set DNA to 0.9 (WORKHORSE) on %s", self.vehicle:getName() or "vehicle"))
    self:updateDiagnostics()
end

-- ========== TAB 1: STATE - MAINTENANCE ACTIONS ==========

function AdminControlPanel:onRefillOilClick()
    if not self:requireVehicle() then return end

    local spec = self.vehicle.spec_usedPlusMaintenance
    spec.oilLevel = 1.0
    spec.hasOilLeak = false
    spec.oilLeakSeverity = 0

    self:setStatus(string.format("Refilled oil & cleared leaks on %s", self.vehicle:getName() or "vehicle"))
    self:updateDiagnostics()
end

function AdminControlPanel:onRefillHydClick()
    if not self:requireVehicle() then return end

    local spec = self.vehicle.spec_usedPlusMaintenance
    spec.hydraulicFluidLevel = 1.0
    spec.hasHydraulicLeak = false
    spec.hydraulicLeakSeverity = 0

    self:setStatus(string.format("Refilled hydraulic fluid & cleared leaks on %s", self.vehicle:getName() or "vehicle"))
    self:updateDiagnostics()
end

function AdminControlPanel:onEmptyOilClick()
    if not self:requireVehicle() then return end
    local spec = self.vehicle.spec_usedPlusMaintenance
    spec.oilLevel = 0
    self:setStatus(string.format("Emptied oil on %s", self.vehicle:getName() or "vehicle"))
    self:updateDiagnostics()
end

function AdminControlPanel:onEmptyHydClick()
    if not self:requireVehicle() then return end
    local spec = self.vehicle.spec_usedPlusMaintenance
    spec.hydraulicFluidLevel = 0
    self:setStatus(string.format("Emptied hydraulic fluid on %s", self.vehicle:getName() or "vehicle"))
    self:updateDiagnostics()
end

function AdminControlPanel:onFixTiresClick()
    if not self:requireVehicle() then return end

    local spec = self.vehicle.spec_usedPlusMaintenance
    spec.hasFlatTire = false
    spec.flatTireSide = 0
    spec.hasShownFlatTireWarning = false

    self:setStatus(string.format("Fixed all flat tires on %s", self.vehicle:getName() or "vehicle"))
    self:updateDiagnostics()
end

function AdminControlPanel:onFixLeaksClick()
    if not self:requireVehicle() then return end

    local spec = self.vehicle.spec_usedPlusMaintenance
    spec.hasOilLeak = false
    spec.oilLeakSeverity = 0
    spec.hasHydraulicLeak = false
    spec.hydraulicLeakSeverity = 0
    spec.hasFuelLeak = false

    self:setStatus(string.format("Fixed all leaks on %s", self.vehicle:getName() or "vehicle"))
    self:updateDiagnostics()
end

function AdminControlPanel:onFixAllMalfClick()
    if not self:requireVehicle() then return end

    if UsedPlusMaintenance and UsedPlusMaintenance.resetAllMalfunctions then
        UsedPlusMaintenance.resetAllMalfunctions(self.vehicle)
        self:setStatus(string.format("Reset ALL malfunctions on %s", self.vehicle:getName() or "vehicle"))
    else
        self:setStatus("Error: resetAllMalfunctions not found", nil, "error")
    end
    self:updateDiagnostics()
end

function AdminControlPanel:findServiceTrucks()
    local trucks = {}
    local seen = {}

    -- 1. Check current vehicle first (most likely — user is sitting in it)
    if self.vehicle and self.vehicle.configFileName then
        local lower = string.lower(self.vehicle.configFileName)
        if string.find(lower, "servicetruck") then
            table.insert(trucks, self.vehicle)
            seen[self.vehicle] = true
        end
    end

    -- 2. Search all vehicles in the world as fallback
    local allVehicles = g_currentMission.vehicles
        or (g_currentMission.vehicleSystem and g_currentMission.vehicleSystem.vehicles)
    if allVehicles then
        for _, vehicle in ipairs(allVehicles) do
            if not seen[vehicle] and vehicle.configFileName then
                local lower = string.lower(vehicle.configFileName)
                if string.find(lower, "servicetruck") then
                    table.insert(trucks, vehicle)
                end
            end
        end
    end

    return trucks
end

function AdminControlPanel:drainServiceTruckFillUnit(fillUnitIndex, label)
    local trucks = self:findServiceTrucks()

    if #trucks == 0 then
        self:setStatus("No Service Truck found in game world", nil, "error")
        return
    end

    local drained = 0
    for _, truck in ipairs(trucks) do
        local fillSpec = truck.spec_fillUnit
        if fillSpec and fillSpec.fillUnits and fillSpec.fillUnits[fillUnitIndex] then
            local fu = fillSpec.fillUnits[fillUnitIndex]
            local currentLevel = fu.fillLevel or 0
            if currentLevel > 0 then
                truck:addFillUnitFillLevel(truck:getOwnerFarmId(), fillUnitIndex, -currentLevel, fu.fillType, ToolType.UNDEFINED)
                drained = drained + 1
            end
        end
    end

    if drained > 0 then
        self:setStatus(string.format("Drained %s from %d Service Truck(s)", label, drained))
    else
        self:setStatus(string.format("Service Truck %s already empty", label), nil, "warn")
    end
end

function AdminControlPanel:onDrainSTOilClick()
    self:drainServiceTruckFillUnit(3, "oil tank")
end

function AdminControlPanel:onDrainSTHydClick()
    self:drainServiceTruckFillUnit(4, "hydraulic tank")
end

function AdminControlPanel:onResetCooldownsClick()
    if not self:requireVehicle() then return end

    local spec = self.vehicle.spec_usedPlusMaintenance
    if spec then
        spec.restorationCooldowns = {}
        self:setStatus(string.format("Cleared restoration cooldowns on %s", self.vehicle:getName() or "vehicle"))
    else
        self:setStatus("Error: No maintenance data", nil, "error")
    end
end

-- ========== DIAGNOSTICS SYSTEM (State tab, left panel) ==========

function AdminControlPanel:getPercentColor(pct)
    if pct >= 75 then return AdminControlPanel.DIAG.GOOD end
    if pct >= 50 then return AdminControlPanel.DIAG.WARN end
    if pct >= 25 then return AdminControlPanel.DIAG.DANGER end
    return AdminControlPanel.DIAG.CRITICAL
end

function AdminControlPanel:boolText(val, activeText, inactiveText)
    return val and (activeText or "ACTIVE") or (inactiveText or "No")
end

function AdminControlPanel:boolColor(val)
    return val and AdminControlPanel.DIAG.ACTIVE or AdminControlPanel.DIAG.INACTIVE
end

function AdminControlPanel:setDiagSection(row, text)
    if row > AdminControlPanel.DIAG.MAX_ROWS then return end
    local label = self.diagLabels[row]
    local value = self.diagValues[row]
    if label then
        label:setText(text)
        label:setTextColor(AdminControlPanel.DIAG.SECTION[1], AdminControlPanel.DIAG.SECTION[2],
            AdminControlPanel.DIAG.SECTION[3], AdminControlPanel.DIAG.SECTION[4])
    end
    if value then value:setText("") end
end

function AdminControlPanel:setDiagRow(row, labelText, valueText, color)
    if row > AdminControlPanel.DIAG.MAX_ROWS then return end
    local label = self.diagLabels[row]
    local value = self.diagValues[row]
    if label then
        label:setText(labelText or "")
        label:setTextColor(AdminControlPanel.DIAG.LABEL[1], AdminControlPanel.DIAG.LABEL[2],
            AdminControlPanel.DIAG.LABEL[3], AdminControlPanel.DIAG.LABEL[4])
    end
    if value then
        value:setText(valueText or "")
        if color then
            value:setTextColor(color[1], color[2], color[3], color[4])
        end
    end
end

function AdminControlPanel:updateDiagnostics()
    -- Clear all rows first
    for i = 1, AdminControlPanel.DIAG.MAX_ROWS do
        local label = self.diagLabels[i]
        local value = self.diagValues[i]
        if label then label:setText("") end
        if value then value:setText("") end
    end

    if not self.vehicle then
        self:setDiagRow(1, "", "No vehicle selected", AdminControlPanel.DIAG.WARN)
        return
    end

    local row = 1

    -- ===== IDENTITY =====
    self:setDiagSection(row, "VEHICLE IDENTITY")
    row = row + 1

    local vehName = self.vehicle:getName() or g_i18n:getText("usedplus_common_unknown")
    self:setDiagRow(row, "Vehicle:", vehName, AdminControlPanel.DIAG.INFO)
    row = row + 1

    local hours = math.floor((self.vehicle:getOperatingTime() or 0) / 3600000)
    self:setDiagRow(row, "Hours:", string.format("%s h", g_i18n:formatNumber(hours)), AdminControlPanel.DIAG.INFO)
    row = row + 1

    local spec = self.vehicle.spec_usedPlusMaintenance
    if not spec then
        self:setDiagRow(row, "", "No maintenance data", AdminControlPanel.DIAG.WARN)
        return
    end

    -- Age in days
    local age = spec.purchaseAge or 0
    if age > 0 then
        self:setDiagRow(row, "Age:", string.format("%d days", age), AdminControlPanel.DIAG.INFO)
        row = row + 1
    end

    -- ===== CONDITION =====
    self:setDiagSection(row, "CONDITION")
    row = row + 1

    local damage = ((self.vehicle.getDamageAmount and self.vehicle:getDamageAmount()) or 0) * 100
    self:setDiagRow(row, "Damage:", string.format("%.0f%%", damage), self:getPercentColor(100 - damage))
    row = row + 1

    local wear = 0
    if self.vehicle.getWearTotalAmount then
        wear = (self.vehicle:getWearTotalAmount() or 0) * 100
    end
    self:setDiagRow(row, "Wear:", string.format("%.0f%%", wear), self:getPercentColor(100 - wear))
    row = row + 1

    -- ===== RELIABILITY =====
    self:setDiagSection(row, "RELIABILITY")
    row = row + 1

    local engRel = (spec.engineReliability or 1) * 100
    local engCeil = (spec.engineReliabilityCeiling or spec.maxEngineDurability or 1) * 100
    self:setDiagRow(row, "Engine:", string.format("%.0f%% (ceil %.0f%%)", engRel, engCeil), self:getPercentColor(engRel))
    row = row + 1

    local hydRel = (spec.hydraulicReliability or 1) * 100
    local hydCeil = (spec.hydraulicReliabilityCeiling or spec.maxHydraulicDurability or 1) * 100
    self:setDiagRow(row, "Hydraulic:", string.format("%.0f%% (ceil %.0f%%)", hydRel, hydCeil), self:getPercentColor(hydRel))
    row = row + 1

    local elecRel = (spec.electricalReliability or 1) * 100
    local elecCeil = (spec.maxElectricalDurability or 1) * 100
    self:setDiagRow(row, "Electrical:", string.format("%.0f%% (ceil %.0f%%)", elecRel, elecCeil), self:getPercentColor(elecRel))
    row = row + 1

    local dna = spec.workhorseLemonScale or 0.5
    local dnaLabel = dna >= 0.7 and "Workhorse" or (dna <= 0.3 and "Lemon" or "Average")
    self:setDiagRow(row, "DNA:", string.format("%.2f (%s)", dna, dnaLabel), self:getPercentColor(dna * 100))
    row = row + 1

    -- ===== FLUIDS =====
    self:setDiagSection(row, "FLUIDS")
    row = row + 1

    local oilLevel = (spec.oilLevel or 1) * 100
    local oilLeak = spec.hasOilLeak and string.format("Leak (%d)", spec.oilLeakSeverity or 0) or "No Leak"
    self:setDiagRow(row, "Oil:", string.format("%.0f%% | %s", oilLevel, oilLeak),
        spec.hasOilLeak and AdminControlPanel.DIAG.DANGER or self:getPercentColor(oilLevel))
    row = row + 1

    local hydFluid = (spec.hydraulicFluidLevel or 1) * 100
    local hydLeak = spec.hasHydraulicLeak and string.format("Leak (%d)", spec.hydraulicLeakSeverity or 0) or "No Leak"
    self:setDiagRow(row, "Hydraulic Fluid:", string.format("%.0f%% | %s", hydFluid, hydLeak),
        spec.hasHydraulicLeak and AdminControlPanel.DIAG.DANGER or self:getPercentColor(hydFluid))
    row = row + 1

    self:setDiagRow(row, "Fuel Leak:", self:boolText(spec.hasFuelLeak, "YES", "No"), self:boolColor(spec.hasFuelLeak))
    row = row + 1

    -- ===== ACTIVE MALFUNCTIONS =====
    self:setDiagSection(row, "MALFUNCTIONS")
    row = row + 1

    -- Compact: two states per row where sensible
    self:setDiagRow(row, "Stalled / Seized:",
        string.format("%s / %s", self:boolText(spec.isStalled), self:boolText(spec.engineSeized, "SEIZED", "OK")),
        (spec.isStalled or spec.engineSeized) and AdminControlPanel.DIAG.ACTIVE or AdminControlPanel.DIAG.INACTIVE)
    row = row + 1

    self:setDiagRow(row, "Overheat / Runaway:",
        string.format("%s / %s", self:boolText(spec.isOverheated or (spec.engineTemperature and spec.engineTemperature > 0.6)),
            self:boolText(spec.runawayActive)),
        (spec.runawayActive or spec.isOverheated) and AdminControlPanel.DIAG.ACTIVE or AdminControlPanel.DIAG.INACTIVE)
    row = row + 1

    self:setDiagRow(row, "Flat Tire / Misfire:",
        string.format("%s / %s", self:boolText(spec.hasFlatTire), self:boolText(spec.misfireActive)),
        (spec.hasFlatTire or spec.misfireActive) and AdminControlPanel.DIAG.ACTIVE or AdminControlPanel.DIAG.INACTIVE)
    row = row + 1

    -- ===== HISTORY =====
    self:setDiagSection(row, "HISTORY")
    row = row + 1

    local failures = spec.failureCount or 0
    local repairs = spec.repairCount or 0
    self:setDiagRow(row, "Failures / Repairs:", string.format("%d / %d", failures, repairs), AdminControlPanel.DIAG.INFO)
    row = row + 1

    local repairCost = spec.totalRepairCost or 0
    if repairCost > 0 then
        self:setDiagRow(row, "Repair Cost:", g_i18n:formatMoney(repairCost, 0, true, true), AdminControlPanel.DIAG.INFO)
        row = row + 1
    end

    -- ===== RVB DATA (conditional) =====
    if ModCompatibility and ModCompatibility.rvbInstalled and self.vehicle.spec_faultData then
        local rvb = self.vehicle.spec_faultData
        if rvb and rvb.parts and row <= AdminControlPanel.DIAG.MAX_ROWS then
            self:setDiagSection(row, "RVB PARTS")
            row = row + 1

            -- Show key RVB parts with life percentage
            local rvbParts = {
                {"Engine", "ENGINE"},
                {"Battery", "BATTERY"},
                {"Generator", "GENERATOR"},
                {"Thermostat", "THERMOSTAT"},
                {"Starter", "SELFSTARTER"},
                {"Glow Plug", "GLOWPLUG"},
            }

            for _, partInfo in ipairs(rvbParts) do
                if row > AdminControlPanel.DIAG.MAX_ROWS then break end
                local label, key = partInfo[1], partInfo[2]
                if rvb.parts[key] then
                    local life = ModCompatibility.getRVBPartLife(self.vehicle, key) * 100
                    self:setDiagRow(row, label .. ":", string.format("%.0f%%", life), self:getPercentColor(life))
                    row = row + 1
                end
            end
        end
    end
end

UsedPlus.logInfo("AdminControlPanel loaded")
