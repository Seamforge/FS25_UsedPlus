--[[
    FS25_UsedPlus - Admin Control Panel

    Comprehensive admin/testing panel for mod development and QA
    Accessible via upAdminCP console command (admin only)

    Features:
    - 5 tabs: Malfunctions, Spawning, Finance, Dialogs, State
    - One-click access to all test functions
    - Status bar feedback
    - Vehicle context awareness

    v2.9.5: Initial implementation
]]

AdminControlPanel = {}
local AdminControlPanel_mt = Class(AdminControlPanel, MessageDialog)

-- Tab indices
AdminControlPanel.TAB = {
    MALFUNCTIONS = 1,
    SPAWNING = 2,
    FINANCE = 3,
    DIALOGS = 4,
    STATE = 5
}

-- Tab colors
AdminControlPanel.COLORS = {
    TAB_INACTIVE = {0.1, 0.1, 0.15, 0.9},
    TAB_ACTIVE = {0.2, 0.3, 0.5, 1},
    TEXT_INACTIVE = {0.7, 0.7, 0.7, 1},
    TEXT_ACTIVE = {1, 0.9, 0.3, 1}
}

--[[
    Constructor
]]
function AdminControlPanel.new(target, custom_mt, i18n)
    local self = MessageDialog.new(target, custom_mt or AdminControlPanel_mt)

    self.i18n = i18n or g_i18n
    self.currentTab = AdminControlPanel.TAB.MALFUNCTIONS
    self.vehicle = nil
    self.statusClearTimer = 0

    return self
end

--[[
    Called when GUI elements are ready
]]
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
end

--[[
    Set the vehicle context for testing
    Called before showing the dialog
    @param vehicle - The controlled vehicle
]]
function AdminControlPanel:setVehicle(vehicle)
    self.vehicle = vehicle

    -- Update vehicle info display
    if vehicle then
        local name = vehicle:getName() or "Unknown Vehicle"
        if self.vehicleInfoText1 then
            self.vehicleInfoText1:setText(string.format("Current: %s", name))
        end
    end
end

--[[
    Dialog opened - update UI
]]
function AdminControlPanel:onOpen()
    AdminControlPanel:superClass().onOpen(self)

    -- Show the first tab
    self:switchToTab(AdminControlPanel.TAB.MALFUNCTIONS)

    -- Update finance info
    self:updateFinanceInfo()

    -- Update debug button text
    self:updateDebugButtonText()

    -- Set initial status
    self:setStatus(g_i18n:getText("usedplus_admin_status_ready"))
end

--[[
    Update per frame (for status clear timer)
]]
function AdminControlPanel:update(dt)
    AdminControlPanel:superClass().update(self, dt)

    -- Clear status after timeout
    if self.statusClearTimer > 0 then
        self.statusClearTimer = self.statusClearTimer - dt
        if self.statusClearTimer <= 0 then
            self:setStatus(g_i18n:getText("usedplus_admin_status_ready"))
        end
    end
end

--[[
    Switch to a specific tab
    @param tabIndex - The tab to show (1-5)
]]
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

--[[
    Update the finance info display (Tab 3)
]]
function AdminControlPanel:updateFinanceInfo()
    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)

    if self.balanceText and farm then
        self.balanceText:setText(g_i18n:formatMoney(farm.money, 0, true, true))
    end

    if self.creditText and CreditScore then
        local score = CreditScore.calculate(farmId)
        local rating = CreditScore.getRating(score)
        self.creditText:setText(string.format("%d (%s)", score, rating))
    end
end

--[[
    Update debug button text based on current state
]]
function AdminControlPanel:updateDebugButtonText()
    if self.btnDebugText then
        local debugState = UsedPlus.DEBUG and "ON" or "OFF"
        self.btnDebugText:setText(string.format("Debug: %s", debugState))
    end
end

--[[
    Set the status bar text
    @param message - Status message to display
    @param duration - How long to show (ms), default 5000
]]
function AdminControlPanel:setStatus(message, duration)
    if self.statusText then
        self.statusText:setText(message or "")
    end
    self.statusClearTimer = duration or 5000
end

--[[
    Check if we have a valid vehicle for malfunction commands
    @return boolean
]]
function AdminControlPanel:requireVehicle()
    if not self.vehicle then
        self:setStatus("Error: No vehicle context")
        return false
    end

    local spec = self.vehicle.spec_usedPlusMaintenance
    if not spec then
        self:setStatus("Error: Vehicle has no maintenance data")
        return false
    end

    return true
end

--[[
    Close dialog
]]
function AdminControlPanel:onCancel()
    -- Clear any armed DNA overrides (principle of least surprise)
    UsedPlus.forcedDNA = nil
    self:close()
end

-- ========== TAB CLICK HANDLERS ==========

function AdminControlPanel:onTab1Click()
    self:switchToTab(AdminControlPanel.TAB.MALFUNCTIONS)
end

function AdminControlPanel:onTab2Click()
    self:switchToTab(AdminControlPanel.TAB.SPAWNING)
end

function AdminControlPanel:onTab3Click()
    self:switchToTab(AdminControlPanel.TAB.FINANCE)
    self:updateFinanceInfo()
end

function AdminControlPanel:onTab4Click()
    self:switchToTab(AdminControlPanel.TAB.DIALOGS)
end

function AdminControlPanel:onTab5Click()
    self:switchToTab(AdminControlPanel.TAB.STATE)
    self:updateDebugButtonText()
end

-- ========== TAB 1: MALFUNCTION HANDLERS ==========

function AdminControlPanel:onStallClick()
    if not self:requireVehicle() then return end

    if UsedPlusMaintenance and UsedPlusMaintenance.triggerEngineStall then
        UsedPlusMaintenance.triggerEngineStall(self.vehicle)
        self:setStatus(string.format("Triggered stall on %s", self.vehicle:getName() or "vehicle"))
    else
        self:setStatus("Error: triggerEngineStall not found")
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
        self:setStatus("Error: seizeComponent not found")
    end
end

function AdminControlPanel:onCutoutClick()
    if not self:requireVehicle() then return end

    if UsedPlusMaintenance and UsedPlusMaintenance.triggerImplementCutout then
        UsedPlusMaintenance.triggerImplementCutout(self.vehicle)
        self:setStatus(string.format("Triggered cutout on %s", self.vehicle:getName() or "vehicle"))
    else
        self:setStatus("Error: triggerImplementCutout not found")
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

function AdminControlPanel:onResetCooldownClick()
    if not self:requireVehicle() then return end

    local spec = self.vehicle.spec_usedPlusMaintenance
    spec.lastMalfunctionTime = 0

    self:setStatus(string.format("Reset malfunction cooldown on %s", self.vehicle:getName() or "vehicle"))
end

function AdminControlPanel:onMalfInfoClick()
    if not self:requireVehicle() then return end

    -- Trigger the console command output
    if UsedPlus and UsedPlus.consoleCommandMalfInfo then
        UsedPlus:consoleCommandMalfInfo()
        self:setStatus("Malfunction info printed to console (F8)")
    else
        self:setStatus("Error: consoleCommandMalfInfo not found")
    end
end

function AdminControlPanel:onFixAllClick()
    if not self:requireVehicle() then return end

    -- Call comprehensive reset helper
    if UsedPlusMaintenance and UsedPlusMaintenance.resetAllMalfunctions then
        UsedPlusMaintenance.resetAllMalfunctions(self.vehicle)
        self:setStatus(string.format("Reset all active malfunctions on %s (reliability, temperature, seizures, warnings)", self.vehicle:getName() or "vehicle"))
    else
        self:setStatus("Error: resetAllMalfunctions not found")
    end
end

-- ========== TAB 2: SPAWNING HANDLERS ==========

function AdminControlPanel:onSpawnObdClick()
    -- Spawn Field Service Kit at player position
    local player = g_localPlayer
    if not player then
        self:setStatus("Error: No local player")
        return
    end

    -- Use shop system to buy item
    local xmlFile = UsedPlus.MOD_DIR .. "vehicles/fieldServiceKit/fieldServiceKit.xml"
    local storeItem = g_storeManager:getItemByXMLFilename(xmlFile)

    if not storeItem then
        self:setStatus("Error: Field Service Kit not found in store")
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
        self:setStatus("Error: No local player")
        return
    end

    local xmlFile = UsedPlus.MOD_DIR .. "vehicles/serviceTruck/serviceTruck.xml"
    local storeItem = g_storeManager:getItemByXMLFilename(xmlFile)

    if not storeItem then
        self:setStatus("Error: Service Truck not found in store")
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
        self:setStatus("Error: No local player")
        return
    end

    local xmlFile = UsedPlus.MOD_DIR .. "vehicles/sparePartsPallet/sparePartsPallet.xml"
    local storeItem = g_storeManager:getItemByXMLFilename(xmlFile)

    if not storeItem then
        self:setStatus("Error: Spare Parts Pallet not found in store")
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
        self:setStatus("Error: ServiceTruckDiscovery not loaded")
    end
end

function AdminControlPanel:onResetDiscoveryClick()
    local farmId = g_currentMission:getFarmId()

    if ServiceTruckDiscovery then
        ServiceTruckDiscovery.resetDiscovery(farmId)
        self:setStatus(string.format("Reset discovery state for farm %d", farmId))
    else
        self:setStatus("Error: ServiceTruckDiscovery not loaded")
    end
end

function AdminControlPanel:onDiscoveryStatusClick()
    if UsedPlus and UsedPlus.consoleCommandServiceTruckStatus then
        UsedPlus:consoleCommandServiceTruckStatus()
        self:setStatus("Discovery status printed to console (F8)")
    else
        self:setStatus("Error: consoleCommandServiceTruckStatus not found")
    end
end

function AdminControlPanel:onSpawnLemonClick()
    self:setStatus("Spawn Lemon: Not yet implemented")
    -- TODO: Implement spawning vehicle with low reliability ceiling
end

function AdminControlPanel:onSpawnWorkhorseClick()
    self:setStatus("Spawn Workhorse: Not yet implemented")
    -- TODO: Implement spawning vehicle with high reliability
end

function AdminControlPanel:onSpawnDamagedClick()
    self:setStatus("Spawn Damaged: Not yet implemented")
    -- TODO: Implement spawning vehicle with existing damage
end

function AdminControlPanel:onPaintPristineClick()
    if not self:requireVehicle() then return end

    if self.vehicle.setDamage then
        self.vehicle:setDamage(0)
    end
    if self.vehicle.setWearAmount then
        self.vehicle:setWearAmount(0)
    end

    local spec = self.vehicle.spec_usedPlusMaintenance
    if spec then
        spec.engineReliability = 1.0
        spec.hydraulicReliability = 1.0
        spec.electricalReliability = 1.0
    end

    self:setStatus(string.format("Painted %s to pristine condition", self.vehicle:getName() or "vehicle"))
end

function AdminControlPanel:onPaintWornClick()
    if not self:requireVehicle() then return end

    if self.vehicle.setDamage then
        self.vehicle:setDamage(0.1)
    end
    if self.vehicle.setWearAmount then
        self.vehicle:setWearAmount(0.3)
    end

    local spec = self.vehicle.spec_usedPlusMaintenance
    if spec then
        spec.engineReliability = 0.75
        spec.hydraulicReliability = 0.8
        spec.electricalReliability = 0.75
    end

    self:setStatus(string.format("Painted %s to worn condition", self.vehicle:getName() or "vehicle"))
end

function AdminControlPanel:onPaintBeatenClick()
    if not self:requireVehicle() then return end

    if self.vehicle.setDamage then
        self.vehicle:setDamage(0.6)
    end
    if self.vehicle.setWearAmount then
        self.vehicle:setWearAmount(0.5)
    end

    local spec = self.vehicle.spec_usedPlusMaintenance
    if spec then
        spec.engineReliability = 0.45
        spec.hydraulicReliability = 0.5
        spec.electricalReliability = 0.4
    end

    self:setStatus(string.format("Painted %s to beaten condition", self.vehicle:getName() or "vehicle"))
end

function AdminControlPanel:onPaintDestroyedClick()
    if not self:requireVehicle() then return end

    if self.vehicle.setDamage then
        self.vehicle:setDamage(0.95)
    end
    if self.vehicle.setWearAmount then
        self.vehicle:setWearAmount(0.8)
    end

    local spec = self.vehicle.spec_usedPlusMaintenance
    if spec then
        spec.engineReliability = 0.2
        spec.hydraulicReliability = 0.3
        spec.electricalReliability = 0.25
    end

    self:setStatus(string.format("Painted %s to destroyed condition", self.vehicle:getName() or "vehicle"))
end

-- ========== TAB 3: FINANCE HANDLERS ==========

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

    if CreditHistory then
        -- TODO: This is a STUB implementation. Credit score is primarily calculated
        -- from PaymentTracker statistics (on-time payments, streaks). Adding
        -- CreditHistory events only provides small score adjustments (+2 to -5).
        -- To properly manipulate credit scores, we need to modify PaymentTracker
        -- data directly. For now, this approximates score changes but won't
        -- reliably reach exact targets, especially high scores (750+).

        -- Get current score
        local currentScore = CreditScore.calculate(farmId)
        local diff = targetScore - currentScore

        -- Add/remove history events to reach target
        if diff > 0 then
            -- Need to increase score - add positive events
            local eventsNeeded = math.ceil(diff / 10)
            for i = 1, eventsNeeded do
                CreditHistory.recordEvent(farmId, "LOAN_PAID", targetScore)
            end
        else
            -- Need to decrease score - add negative events
            local eventsNeeded = math.ceil(-diff / 5)
            for i = 1, eventsNeeded do
                CreditHistory.recordEvent(farmId, "LOAN_TAKEN", targetScore)
            end
        end

        local rating = CreditScore.getRating(targetScore)
        self:setStatus(string.format("Adjusted credit toward %d (%s)", targetScore, rating))
        self:updateFinanceInfo()
    else
        self:setStatus("Error: CreditHistory not available")
    end
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

function AdminControlPanel:onListDealsClick()
    if UsedPlus and UsedPlus.consoleCommandListDeals then
        UsedPlus:consoleCommandListDeals()
        self:setStatus("Deal list printed to console (F8)")
    else
        self:setStatus("Use upListDeals in console")
    end
end

function AdminControlPanel:onPayoffAllClick()
    if UsedPlus and UsedPlus.consoleCommandPayoffAll then
        local result = UsedPlus:consoleCommandPayoffAll()
        self:setStatus(result or "Paid off all deals")
        self:updateFinanceInfo()
    else
        self:setStatus("Error: consoleCommandPayoffAll not found")
    end
end

function AdminControlPanel:onCreateLoanClick()
    -- Create a test loan
    if g_financeManager then
        local farmId = g_currentMission:getFarmId()
        local farm = g_farmManager:getFarmById(farmId)

        -- Simple $50k test loan
        TakeLoanEvent.sendToServer(farmId, 50000, 5, 0.08, 1013.75, {})
        self:setStatus("Created $50,000 test loan")
        self:updateFinanceInfo()
    else
        self:setStatus("Error: FinanceManager not available")
    end
end

function AdminControlPanel:onCreateLeaseClick()
    self:setStatus("Create Test Lease: Not yet implemented")
    -- TODO: Create a test lease on current vehicle
end

function AdminControlPanel:onMissedPaymentClick()
    -- Force a missed payment
    if g_financeManager then
        local farmId = g_currentMission:getFarmId()
        CreditHistory.recordEvent(farmId, "PAYMENT_MISSED", 0)
        self:updateFinanceInfo()
        self:setStatus("Recorded missed payment (credit impact)")
    else
        self:setStatus("Error: Cannot record missed payment")
    end
end

-- ========== TAB 4: DIALOG HANDLERS ==========

function AdminControlPanel:onDlgLoanClick()
    self:close()
    local farmId = g_currentMission:getFarmId()
    DialogLoader.show("TakeLoanDialog", "setFarmId", farmId)
    -- Status set via closing
end

function AdminControlPanel:onDlgApprovedClick()
    self:close()
    -- Show with mock data
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
    if LoanApprovedDialog then
        LoanApprovedDialog.show(mockDetails)
    end
end

function AdminControlPanel:onDlgCreditClick()
    self:close()
    DialogLoader.show("CreditReportDialog")
end

function AdminControlPanel:onDlgHistoryClick()
    self:close()
    -- Need an active deal for this
    if g_financeManager then
        local farmId = g_currentMission:getFarmId()
        local deals = g_financeManager:getDealsForFarm(farmId)
        if deals and #deals > 0 then
            DialogLoader.show("PaymentHistoryDialog", "setDeal", deals[1])
        else
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, "No active deals to show history for")
        end
    end
end

function AdminControlPanel:onDlgRepoClick()
    self:close()
    -- Show with mock data
    DialogLoader.show("RepossessionDialog", "setData", "Test Vehicle", 50000, 3)
end

function AdminControlPanel:onDlgSearchClick()
    self:close()
    -- Need a store item for the search dialog
    local storeItems = g_storeManager:getItems()
    if storeItems and #storeItems > 0 then
        -- Find a vehicle
        for _, item in ipairs(storeItems) do
            if item.categoryName and string.find(item.categoryName, "TRACTOR") then
                DialogLoader.show("UsedSearchDialog", "setData", item)
                return
            end
        end
    end
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, "No store items found")
end

function AdminControlPanel:onDlgPurchaseClick()
    self:close()
    if not self.vehicle then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, "Need to be in a vehicle")
        return
    end

    -- Get store item for current vehicle
    local xmlFilename = self.vehicle.configFileName
    local storeItem = g_storeManager:getItemByXMLFilename(xmlFilename)

    if storeItem then
        -- Use static show() method with mock sale data
        local price = storeItem.price or 100000
        local saleItem = {
            price = price,
            storeItem = storeItem,
            vehicle = self.vehicle
        }

        if UnifiedPurchaseDialog.show then
            UnifiedPurchaseDialog.show(storeItem, price, saleItem, "cash")
        else
            DialogLoader.show("UnifiedPurchaseDialog", "setVehicleData", storeItem, price, saleItem, nil)
        end
    else
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, "Could not find store item for current vehicle")
    end
end

function AdminControlPanel:onDlgNegotiateClick()
    self:close()
    -- Would need mock listing data
    self:setStatus("Negotiate Dialog: Requires active search result")
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, "Negotiate Dialog requires an active search with found vehicles")
end

function AdminControlPanel:onDlgSellerClick()
    self:close()
    -- Would need mock response data
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, "Seller Response Dialog requires negotiation context")
end

function AdminControlPanel:onDlgObdClick()
    self:close()
    if self.vehicle then
        DialogLoader.show("FieldServiceKitDialog", "setData", self.vehicle, nil, "master")
    else
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, "Need to be in a vehicle")
    end
end

function AdminControlPanel:onDlgServiceClick()
    self:close()
    -- Service truck dialog needs service truck context
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, "Service Truck Dialog requires Service Truck context")
end

function AdminControlPanel:onDlgInspectClick()
    self:close()
    if not self.vehicle then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, "Need to be in a vehicle")
        return
    end

    -- InspectionReportDialog requires listing data, not just vehicle
    -- For testing purposes, create minimal mock listing
    if InspectionReportDialog and InspectionReportDialog.show then
        -- Try direct show() method
        InspectionReportDialog.show(self.vehicle)
    else
        -- Show placeholder message for now
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, "Inspect Dialog requires inspection listing data. Use the used vehicle search system.")
    end
end

function AdminControlPanel:onDlgLeaseEndClick()
    self:close()
    -- Need active lease
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, "Lease End Dialog requires an active lease")
end

function AdminControlPanel:onDlgLeaseRenewClick()
    self:close()
    -- Need active lease
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, "Lease Renewal Dialog requires an active lease")
end

-- ========== TAB 5: STATE HANDLERS ==========

function AdminControlPanel:onToggleDebugClick()
    UsedPlus.DEBUG = not UsedPlus.DEBUG
    self:updateDebugButtonText()
    self:setStatus(string.format("Debug mode: %s", UsedPlus.DEBUG and "ON" or "OFF"))
end

function AdminControlPanel:onRel100Click()
    if not self:requireVehicle() then return end

    local spec = self.vehicle.spec_usedPlusMaintenance
    spec.engineReliability = 1.0
    spec.hydraulicReliability = 1.0
    spec.electricalReliability = 1.0

    self:setStatus("Set reliability to 100%")
end

function AdminControlPanel:onRel50Click()
    if not self:requireVehicle() then return end

    local spec = self.vehicle.spec_usedPlusMaintenance
    spec.engineReliability = 0.5
    spec.hydraulicReliability = 0.5
    spec.electricalReliability = 0.5

    self:setStatus("Set reliability to 50%")
end

function AdminControlPanel:onRel10Click()
    if not self:requireVehicle() then return end

    local spec = self.vehicle.spec_usedPlusMaintenance
    spec.engineReliability = 0.1
    spec.hydraulicReliability = 0.1
    spec.electricalReliability = 0.1

    self:setStatus("Set reliability to 10% - malfunctions likely!")
end

function AdminControlPanel:onResetHoursClick()
    if not self:requireVehicle() then return end

    if self.vehicle.setOperatingTime then
        self.vehicle:setOperatingTime(0)
        self:setStatus("Reset operating hours to 0")
    else
        self:setStatus("Error: Cannot reset operating hours")
    end
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
        self:setStatus("Error: Cannot modify operating hours")
    end
end

-- ========== TAB 5: STATE - DNA FORCING (FIXED) ==========

function AdminControlPanel:onDnaLemonClick()
    UsedPlus.forcedDNA = 0.1  -- Force lemon DNA (low reliability)
    self:setStatus("Next vehicle generation will use DNA 0.1 (LEMON)")
end

function AdminControlPanel:onDnaAverageClick()
    UsedPlus.forcedDNA = 0.5  -- Force average DNA (mid reliability)
    self:setStatus("Next vehicle generation will use DNA 0.5 (AVERAGE)")
end

function AdminControlPanel:onDnaWorkhorseClick()
    UsedPlus.forcedDNA = 0.9  -- Force workhorse DNA (high reliability)
    self:setStatus("Next vehicle generation will use DNA 0.9 (WORKHORSE)")
end

function AdminControlPanel:onNextVehicleClick()
    -- Get list of owned vehicles
    local farmId = g_currentMission:getFarmId()
    local vehicles = {}

    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if vehicle.ownerFarmId == farmId and vehicle.getIsEnterable and vehicle:getIsEnterable() then
            table.insert(vehicles, vehicle)
        end
    end

    if #vehicles == 0 then
        self:setStatus("No enterable vehicles found")
        return
    end

    -- Find current vehicle index
    local currentIndex = 1
    for i, v in ipairs(vehicles) do
        if v == self.vehicle then
            currentIndex = i
            break
        end
    end

    -- Get next vehicle
    local nextIndex = currentIndex % #vehicles + 1
    local nextVehicle = vehicles[nextIndex]

    -- Enter the vehicle
    self:close()
    if nextVehicle.enterVehicle then
        g_localPlayer:enterVehicle(nextVehicle)
        self.vehicle = nextVehicle
    end
end

function AdminControlPanel:onPrevVehicleClick()
    -- Get list of owned vehicles
    local farmId = g_currentMission:getFarmId()
    local vehicles = {}

    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if vehicle.ownerFarmId == farmId and vehicle.getIsEnterable and vehicle:getIsEnterable() then
            table.insert(vehicles, vehicle)
        end
    end

    if #vehicles == 0 then
        self:setStatus("No enterable vehicles found")
        return
    end

    -- Find current vehicle index
    local currentIndex = 1
    for i, v in ipairs(vehicles) do
        if v == self.vehicle then
            currentIndex = i
            break
        end
    end

    -- Get previous vehicle
    local prevIndex = ((currentIndex - 2) % #vehicles) + 1
    local prevVehicle = vehicles[prevIndex]

    -- Enter the vehicle
    self:close()
    if prevVehicle.enterVehicle then
        g_localPlayer:enterVehicle(prevVehicle)
        self.vehicle = prevVehicle
    end
end

UsedPlus.logInfo("AdminControlPanel loaded")
