--[[
    FS25_UsedPlus - Repair Dialog

     Custom repair dialog with fine-grained percentage control
     Pattern from: FinanceDialog (working reference)
     Reference: FS25_ADVANCED_PATTERNS.md - Shop UI Customization

    Features:
    - Slider control (1-100%) for repair percentage
    - Separate modes for repair-only and repaint-only
    - Real-time cost preview as slider moves
    - Payment options: Cash or Finance
    - Vehicle current status display

    Modes:
    - "repair" - Mechanical repair only
    - "repaint" - Cosmetic repaint only
    - "both" - Combined (legacy, not used for workshop intercept)
]]

RepairDialog = {}
local RepairDialog_mt = Class(RepairDialog, MessageDialog)

-- Mode constants
RepairDialog.MODE_REPAIR = "repair"
RepairDialog.MODE_REPAINT = "repaint"
RepairDialog.MODE_BOTH = "both"

--[[
     Constructor
]]
function RepairDialog.new(target, custom_mt, i18n)
    local self = MessageDialog.new(target, custom_mt or RepairDialog_mt)

    self.i18n = i18n or g_i18n

    -- Vehicle data
    self.vehicle = nil
    self.vehicleName = ""
    self.basePrice = 0
    self.farmId = 0

    -- Dialog mode (repair, repaint, or both)
    self.mode = RepairDialog.MODE_BOTH

    -- Current condition (0-1 scale)
    self.currentDamage = 0      -- 0 = perfect, 1 = destroyed
    self.currentWear = 0        -- 0 = perfect, 1 = needs full repaint

    -- Slider values (0-100 percentage)
    self.repairPercent = 50     -- Default 50% repair
    self.repaintPercent = 50    -- Default 50% repaint

    -- Calculated costs
    self.repairCost = 0
    self.repaintCost = 0
    self.totalCost = 0

    -- Full repair costs (for reference)
    self.fullRepairCost = 0
    self.fullRepaintCost = 0

    -- v2.7.0: Additional repair costs (fuel leak, flat tire)
    self.hasFuelLeak = false
    self.hasFlatTire = false
    self.fuelLeakRepairCost = 0
    self.flatTireRepairCost = 0

    return self
end

--[[
     Called when GUI elements are ready
     Element references auto-populated by g_gui based on XML id attributes
     No manual caching needed - removed redundant self.x = self.x patterns
]]
function RepairDialog:onGuiSetupFinished()
    RepairDialog:superClass().onGuiSetupFinished(self)
    -- UI elements automatically available via XML id attributes:
    -- vehicleNameText, vehicleImageElement
    -- currentConditionText, currentConditionBar, currentPaintText, currentPaintBar
    -- repairSlider, repairPercentText, repairCostText, repairAfterText
    -- repaintSlider, repaintPercentText, repaintCostText, repaintAfterText
    -- workSlider, workPercentText, workCostText, workAfterText, workSectionTitle, workSliderLabel
    -- totalCostText, playerMoneyText
    -- payCashButton, financeButton, cancelButton
end

--[[
     Set vehicle data for repair
    @param vehicle - The vehicle object to repair
    @param farmId - Farm ID that owns the vehicle
    @param mode - Optional mode: "repair", "repaint", or "both" (default: "both")
    @param rvbRepairCost - Optional: RVB's calculated repair cost (used when called from RVB Workshop)
]]
function RepairDialog:setVehicle(vehicle, farmId, mode, rvbRepairCost)
    -- v2.6.2: Check master repair system toggle
    if UsedPlusSettings and UsedPlusSettings:get("enableRepairSystem") == false then
        UsedPlus.logDebug("RepairDialog: Repair system disabled in settings, canceling")
        self:close()
        return
    end

    self.vehicle = vehicle
    self.farmId = farmId
    self.mode = mode or RepairDialog.MODE_BOTH
    self.rvbRepairCost = rvbRepairCost  -- Store RVB cost for later use

    if vehicle == nil then
        UsedPlus.logError("RepairDialog:setVehicle - No vehicle provided")
        return
    end

    UsedPlus.logDebug(string.format("RepairDialog:setVehicle mode=%s", self.mode))

    -- Get store item and vehicle name using consolidated utility
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    self.storeItem = storeItem
    self.vehicleName = UIHelper.Vehicle.getFullName(storeItem)
    -- Use empty config table to get base store price (not depreciated vehicle price)
    self.basePrice = storeItem and (StoreItemUtil.getDefaultPrice(storeItem, {}) or storeItem.price or 10000) or 10000

    -- Get current damage and wear (0-1 scale, 0 = perfect)
    if vehicle.getDamageAmount then
        self.currentDamage = vehicle:getDamageAmount() or 0
    else
        self.currentDamage = 0
    end

    if vehicle.getWearTotalAmount then
        self.currentWear = vehicle:getWearTotalAmount() or 0
    else
        self.currentWear = 0
    end

    -- Get cost multipliers from settings (v2.0.0: separate paint multiplier)
    local repairMultiplier = UsedPlusSettings and UsedPlusSettings:get("repairCostMultiplier") or 1.0
    local paintMultiplier = UsedPlusSettings and UsedPlusSettings:get("paintCostMultiplier") or 1.0

    -- Calculate full repair cost
    -- v2.1.2: Use RVB's calculated repair cost if provided (from RVB Workshop integration)
    if self.rvbRepairCost and self.rvbRepairCost > 0 then
        self.fullRepairCost = self.rvbRepairCost
        UsedPlus.logDebug(string.format("RepairDialog: Using RVB repair cost: $%d", self.fullRepairCost))
    elseif Wearable and Wearable.calculateRepairPrice then
        self.fullRepairCost = Wearable.calculateRepairPrice(self.basePrice, self.currentDamage) or 0
        -- Apply settings multiplier (only when not using RVB cost)
        self.fullRepairCost = math.floor(self.fullRepairCost * repairMultiplier)
    else
        -- Fallback calculation: damage% * 25% of base price
        self.fullRepairCost = math.floor(self.basePrice * self.currentDamage * 0.25)
        -- Apply settings multiplier
        self.fullRepairCost = math.floor(self.fullRepairCost * repairMultiplier)
    end

    if Wearable and Wearable.calculateRepaintPrice then
        self.fullRepaintCost = Wearable.calculateRepaintPrice(self.basePrice, self.currentWear) or 0
    else
        -- Fallback calculation: wear% * 15% of base price
        self.fullRepaintCost = math.floor(self.basePrice * self.currentWear * 0.15)
    end
    -- Apply settings multiplier to repaint (v2.0.0: uses separate paintCostMultiplier)
    self.fullRepaintCost = math.floor(self.fullRepaintCost * paintMultiplier)

    -- Reset sliders to sensible defaults
    if self.rvbRepairCost and self.rvbRepairCost > 0 then
        -- v2.15.4: RVB mode — default to 50% for expensive repairs, 100% for cheap
        self.repairPercent = (self.rvbRepairCost > 10000) and 50 or 100
        -- Collect RVB parts data for display
        self.rvbParts = {}
        if vehicle.spec_faultData and vehicle.spec_faultData.parts then
            for partKey, part in pairs(vehicle.spec_faultData.parts) do
                if partKey ~= "USEDPLUS_HYDRAULIC" then
                    table.insert(self.rvbParts, {
                        key = partKey,
                        condition = part.condition or 100,
                        repairreq = part.repairreq or false,
                        fault = part.fault or "empty"
                    })
                end
            end
            -- Sort: parts needing repair first, then by condition (worst first)
            table.sort(self.rvbParts, function(a, b)
                if a.repairreq ~= b.repairreq then
                    return a.repairreq  -- repairreq=true sorts first
                end
                return (a.condition or 100) < (b.condition or 100)
            end)
        end
    elseif self.currentDamage < 0.2 then
        self.repairPercent = 100
    else
        self.repairPercent = 50
    end

    if self.currentWear < 0.2 then
        self.repaintPercent = 100
    else
        self.repaintPercent = 50
    end

    -- v2.7.0: Detect fuel leak and flat tire status (only relevant for mechanical repair)
    self.hasFuelLeak = false
    self.hasFlatTire = false
    self.fuelLeakRepairCost = 0
    self.flatTireRepairCost = 0

    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec ~= nil then
        self.hasFuelLeak = maintSpec.hasFuelLeak or false
        self.hasFlatTire = maintSpec.hasFlatTire or false

        -- Calculate additional repair costs based on vehicle price
        local config = UsedPlusMaintenance.CONFIG or {}

        if self.hasFuelLeak then
            local fuelLeakMult = config.workshopFuelLeakRepairCostMult or 0.02
            self.fuelLeakRepairCost = math.floor(self.basePrice * fuelLeakMult)
            UsedPlus.logDebug(string.format("RepairDialog: Fuel leak detected, repair cost: $%d", self.fuelLeakRepairCost))
        end

        if self.hasFlatTire then
            local flatTireMult = config.workshopFlatTireRepairCostMult or 0.01
            self.flatTireRepairCost = math.floor(self.basePrice * flatTireMult)
            UsedPlus.logDebug(string.format("RepairDialog: Flat tire detected, repair cost: $%d", self.flatTireRepairCost))
        end
    end

    -- Calculate initial costs
    self:calculateCosts()

    -- Update UI
    self:updateDisplay()

    UsedPlus.logDebug(string.format("RepairDialog loaded for: %s", self.vehicleName))
    UsedPlus.logTrace(string.format("  Base price: $%d", self.basePrice))
    UsedPlus.logTrace(string.format("  Current damage: %.1f%%", self.currentDamage * 100))
    UsedPlus.logTrace(string.format("  Current wear: %.1f%%", self.currentWear * 100))
    UsedPlus.logTrace(string.format("  Full repair cost: $%d", self.fullRepairCost))
    UsedPlus.logTrace(string.format("  Full repaint cost: $%d", self.fullRepaintCost))
end

--[[
     Calculate repair and repaint costs based on slider percentages and mode
]]
function RepairDialog:calculateCosts()
    -- Reset costs
    self.repairCost = 0
    self.repaintCost = 0

    -- Calculate based on mode
    if self.mode == RepairDialog.MODE_REPAIR or self.mode == RepairDialog.MODE_BOTH then
        -- Repair cost is proportional to percentage selected
        self.repairCost = math.floor(self.fullRepairCost * (self.repairPercent / 100))
    end

    if self.mode == RepairDialog.MODE_REPAINT or self.mode == RepairDialog.MODE_BOTH then
        -- Repaint cost is proportional to percentage selected
        self.repaintCost = math.floor(self.fullRepaintCost * (self.repaintPercent / 100))
    end

    -- v2.7.0: Add additional repair costs for mechanical repair mode only
    -- Fuel leak and flat tire repairs are only included when doing mechanical repair
    local additionalCosts = 0
    if self.mode == RepairDialog.MODE_REPAIR or self.mode == RepairDialog.MODE_BOTH then
        if self.hasFuelLeak then
            additionalCosts = additionalCosts + self.fuelLeakRepairCost
        end
        if self.hasFlatTire then
            additionalCosts = additionalCosts + self.flatTireRepairCost
        end
    end

    -- Total cost (only active modes + additional repairs)
    self.totalCost = self.repairCost + self.repaintCost + additionalCosts
end

--[[
     Calculate condition after repair
    @return newCondition (0-1 where 1 = 100% healthy)
]]
function RepairDialog:getConditionAfterRepair()
    -- Current condition as percentage (1 - damage)
    local currentCondition = 1 - self.currentDamage

    -- Damage that will be removed
    local damageToRemove = self.currentDamage * (self.repairPercent / 100)

    -- New condition
    local newCondition = currentCondition + damageToRemove

    return math.min(1, newCondition)
end

--[[
     Calculate paint condition after repaint
    @return newPaintCondition (0-1 where 1 = 100% fresh paint)
]]
function RepairDialog:getPaintAfterRepaint()
    -- Current paint condition (1 - wear)
    local currentPaint = 1 - self.currentWear

    -- Wear that will be removed
    local wearToRemove = self.currentWear * (self.repaintPercent / 100)

    -- New paint condition
    local newPaint = currentPaint + wearToRemove

    return math.min(1, newPaint)
end

--[[
     Update all UI elements based on mode
     Refactored to use UIHelper for consistent formatting
    Uses unified work section that adapts to repair or repaint mode
]]
function RepairDialog:updateDisplay()
    -- Determine which mode we're in
    local isRepairMode = (self.mode == RepairDialog.MODE_REPAIR)
    local isRepaintMode = (self.mode == RepairDialog.MODE_REPAINT)

    -- Set vehicle image
    if self.vehicleImageElement and self.storeItem then
        UIHelper.Image.setStoreItemImage(self.vehicleImageElement, self.storeItem)
    end

    -- Update button highlights based on current selection
    self:updateButtonHighlights()

    -- Update dialog title based on mode
    local title = "Vehicle Service"
    local isRVBRepair = (self.rvbRepairCost and self.rvbRepairCost > 0)
    if isRVBRepair then
        title = g_i18n:getText("usedplus_repair_title_workshop") or "Workshop Repair"
    elseif isRepairMode then
        title = g_i18n:getText("usedplus_repair_title_mechanical") or "Mechanical Repair"
    elseif isRepaintMode then
        title = g_i18n:getText("usedplus_repair_title_repaint") or "Repaint Vehicle"
    else
        title = g_i18n:getText("usedplus_repair_title") or "Vehicle Service"
    end
    UIHelper.Element.setText(self.dialogTitleElement, title)

    -- Vehicle name
    UIHelper.Element.setText(self.vehicleNameText, self.vehicleName)

    -- Hide/show status sections based on mode
    UIHelper.Element.setVisible(self.repairStatusSection, isRepairMode)
    UIHelper.Element.setVisible(self.repaintStatusSection, isRepaintMode)

    -- Update work section title and labels based on mode
    local sectionTitle
    if isRVBRepair then
        sectionTitle = g_i18n:getText("usedplus_repair_title_workshop") or "WORKSHOP REPAIR"
    elseif isRepairMode then
        sectionTitle = g_i18n:getText("usedplus_repair_mechanical") or "MECHANICAL REPAIR"
    else
        sectionTitle = g_i18n:getText("usedplus_repair_cosmetic") or "PAINT & COSMETICS"
    end
    UIHelper.Element.setText(self.workSectionTitle, sectionTitle)
    local sliderLabel
    if isRVBRepair then
        sliderLabel = g_i18n:getText("usedplus_rp_label_components") or "Components:"
    elseif isRepairMode then
        sliderLabel = g_i18n:getText("usedplus_rp_label_repair") or "Repair:"
    else
        sliderLabel = g_i18n:getText("usedplus_rp_label_repaint") or "Repaint:"
    end
    UIHelper.Element.setText(self.workSliderLabel, sliderLabel)

    -- Populate component grid (unified: UsedPlus maintenance + RVB components)
    self:updateComponentGrid(isRepairMode)

    -- Current condition displays
    if isRVBRepair then
        -- v2.15.4: RVB mode — use wide status line, hide vanilla elements
        local partsNeedRepair = 0
        local totalParts = 0
        if self.vehicle and self.vehicle.spec_faultData and self.vehicle.spec_faultData.parts then
            for partKey, part in pairs(self.vehicle.spec_faultData.parts) do
                if partKey ~= "USEDPLUS_HYDRAULIC" then
                    totalParts = totalParts + 1
                    if part.repairreq then
                        partsNeedRepair = partsNeedRepair + 1
                    end
                end
            end
        end
        -- Hide vanilla elements (label, bar, value)
        UIHelper.Element.setVisible(self.repairStatusLabel, false)
        UIHelper.Element.setVisible(self.currentConditionBar, false)
        UIHelper.Element.setVisible(self.currentConditionText, false)
        -- Show wide RVB status line
        UIHelper.Element.setVisible(self.rvbStatusText, true)
        local statusFormat = g_i18n:getText("usedplus_rvb_parts_status") or "Components: %d / %d need repair"
        UIHelper.Element.setText(self.rvbStatusText, string.format(statusFormat, partsNeedRepair, totalParts))
    else
        -- Restore vanilla elements, hide RVB status
        UIHelper.Element.setVisible(self.repairStatusLabel, true)
        UIHelper.Element.setVisible(self.currentConditionBar, true)
        UIHelper.Element.setVisible(self.currentConditionText, true)
        UIHelper.Element.setVisible(self.rvbStatusText, false)
        -- Vanilla condition display
        UIHelper.Vehicle.displayCondition(
            self.currentConditionText,
            self.currentPaintText,
            self.currentConditionBar,
            self.currentPaintBar,
            self.currentDamage,
            self.currentWear
        )
    end

    -- Work section values (unified slider/buttons)
    local workPercent, workCost, workAfter
    if isRVBRepair then
        -- RVB: slider controls repair percentage, cost scales proportionally
        workPercent = self.repairPercent
        workCost = self.repairCost
        workAfter = workPercent  -- percentage of components repaired
    elseif isRepairMode then
        workPercent = self.repairPercent
        workCost = self.repairCost
        workAfter = math.floor(self:getConditionAfterRepair() * 100)
    else
        workPercent = self.repaintPercent
        workCost = self.repaintCost
        workAfter = math.floor(self:getPaintAfterRepaint() * 100)
    end

    -- Update work slider
    if self.workSlider then
        self.workSlider:setValue(workPercent / 100)
        if isRVBRepair then
            -- RVB: slider always enabled (partial repair scales cost)
            self.workSlider:setDisabled(false)
        else
            local needsWork = isRepairMode and (self.currentDamage >= 0.01) or (self.currentWear >= 0.01)
            self.workSlider:setDisabled(not needsWork)
        end
    end

    -- Work section text displays
    UIHelper.Element.setText(self.workPercentText, UIHelper.Text.formatPercent(workPercent, false))
    UIHelper.Element.setText(self.workCostText, UIHelper.Text.formatMoney(workCost))
    UIHelper.Element.setText(self.workAfterText, UIHelper.Text.formatPercent(workAfter, false))

    -- v2.7.0: Display additional repair costs (fuel leak, flat tire) if any
    local hasAdditionalRepairs = isRepairMode and (self.hasFuelLeak or self.hasFlatTire)
    if self.additionalRepairsText then
        if hasAdditionalRepairs then
            local parts = {}
            if self.hasFuelLeak then
                table.insert(parts, string.format(g_i18n:getText("usedplus_rp_fuelLeakLabel"), UIHelper.Text.formatMoney(self.fuelLeakRepairCost)))
            end
            if self.hasFlatTire then
                table.insert(parts, string.format(g_i18n:getText("usedplus_rp_flatTireLabel"), UIHelper.Text.formatMoney(self.flatTireRepairCost)))
            end
            local additionalText = g_i18n:getText("usedplus_rp_includesLabel") .. table.concat(parts, ", ")
            self.additionalRepairsText:setText(additionalText)
            self.additionalRepairsText:setTextColor(1, 0.8, 0.2, 1)  -- Yellow/gold for info
            self.additionalRepairsText:setVisible(true)
        else
            self.additionalRepairsText:setVisible(false)
        end
    end

    -- Total cost (orange for expense)
    UIHelper.Element.setTextWithColor(self.totalCostText,
        UIHelper.Text.formatMoney(self.totalCost), UIHelper.Colors.COST_ORANGE)

    -- Result in payment section (shows what condition will be after work)
    UIHelper.Element.setText(self.paymentResultText, string.format("→ %d%%", workAfter))

    -- Enable/disable pay cash button based on funds (game UI shows player money)
    if self.payCashButton then
        local playerMoney = 0
        local farm = g_farmManager:getFarmById(self.farmId)
        if farm then
            playerMoney = farm.money or 0
        end
        local canAfford = playerMoney >= self.totalCost and self.totalCost > 0
        self.payCashButton:setDisabled(not canAfford)
    end

    -- Finance button - enabled if there's a cost AND player qualifies for financing
    if self.financeButton then
        local canFinanceRepair = true
        local financeDisabledReason = nil

        -- Check credit qualification
        if CreditScore and CreditScore.canFinance then
            local canFinance, minRequired, currentScore = CreditScore.canFinance(self.farmId, "REPAIR")
            if not canFinance then
                canFinanceRepair = false
                local template = g_i18n:getText("usedplus_credit_needScore")
                financeDisabledReason = string.format(template, currentScore, minRequired)
            end
        end

        -- Disable if no cost or can't qualify
        local shouldDisable = (self.totalCost <= 0) or (not canFinanceRepair)
        self.financeButton:setDisabled(shouldDisable)

        -- Show tooltip/reason if disabled due to credit
        if self.financeDisabledText then
            if financeDisabledReason then
                self.financeDisabledText:setText(financeDisabledReason)
                self.financeDisabledText:setVisible(true)
            else
                self.financeDisabledText:setVisible(false)
            end
        end
    end
end

--[[
     Unified work slider changed callback
    Note: FS25 slider callbacks can pass (value) or (slider, value) depending on context
]]
function RepairDialog:onWorkSliderChanged(sliderOrValue, value)
    -- Handle both callback signatures: (value) and (slider, value)
    local actualValue = value
    if actualValue == nil then
        -- First argument is the value, not the slider
        if type(sliderOrValue) == "number" then
            actualValue = sliderOrValue
        elseif type(sliderOrValue) == "table" and sliderOrValue.sliderValue then
            actualValue = sliderOrValue.sliderValue
        elseif self.workSlider then
            actualValue = self.workSlider.sliderValue or 0.5
        else
            actualValue = 0.5
        end
    end

    -- Ensure actualValue is a number
    if type(actualValue) ~= "number" then
        actualValue = 0.5
    end

    -- Convert 0-1 to 0-100 percentage, round to nearest 5%
    local percent = math.floor((actualValue * 100) / 5 + 0.5) * 5
    percent = math.max(0, math.min(100, percent))

    -- Update the appropriate percent based on mode
    if self.mode == RepairDialog.MODE_REPAIR then
        self.repairPercent = percent
    else
        self.repaintPercent = percent
    end

    self:calculateCosts()
    self:updateDisplay()
end

--[[
    Populate the unified component grid with UsedPlus maintenance + RVB components.
    Shows all vehicle subsystem conditions in a 2-column layout.
]]
function RepairDialog:updateComponentGrid(isRepairMode)
    local NUM_SLOTS = 16
    local components = {}

    -- Collect repairable components only (no fluid levels — those aren't repair items)
    local hasRVB = self.vehicle and self.vehicle.spec_faultData and self.vehicle.spec_faultData.parts
    local maintSpec = self.vehicle and self.vehicle.spec_usedPlusMaintenance

    -- UsedPlus maintenance components (only actual repairable items, not fluid levels)
    if maintSpec and isRepairMode and not hasRVB then
        -- Only show these in non-RVB mode; RVB handles its own component list
        local tirePct = math.floor((maintSpec.tireCondition or 1) * 100)
        table.insert(components, { name = g_i18n:getText("usedplus_comp_tires") or "Tires", condition = tirePct, bad = maintSpec.hasFlatTire or tirePct < 30 })
        if maintSpec.hasFuelLeak then
            table.insert(components, { name = g_i18n:getText("usedplus_comp_fuelSystem") or "Fuel System", condition = 0, bad = true })
        end
    end

    -- RVB components: only parts toggled for repair, skip tires and our fake hydraulic
    -- Use vehicle:getPartsPercentage() for accurate condition (not part.condition which doesn't exist)
    local TIRE_PARTS = { TIREFL = true, TIREFR = true, TIRERL = true, TIRERR = true }
    if hasRVB and isRepairMode then
        for partKey, part in pairs(self.vehicle.spec_faultData.parts) do
            if part.repairreq and partKey ~= "USEDPLUS_HYDRAULIC" and not TIRE_PARTS[partKey] then
                -- Get condition from RVB's actual percentage calculation
                local conditionPct = 100
                if self.vehicle.getPartsPercentage then
                    local ok, pct = pcall(self.vehicle.getPartsPercentage, self.vehicle, partKey)
                    if ok and pct then
                        -- RVB returns wear% (0=new, 100=worn); convert to condition% (100=new, 0=worn)
                        conditionPct = math.max(0, math.floor(100 - pct))
                    end
                end
                -- Display name: try RVB's i18n, fallback to our own readable names
                local RVB_PART_NAMES = {
                    ENGINE = "Engine", THERMOSTAT = "Thermostat", GENERATOR = "Generator",
                    BATTERY = "Battery", SELFSTARTER = "Starter", GLOWPLUG = "Glow Plug",
                    LIGHTINGS = "Lighting", WIPERS = "Wipers"
                }
                local rvbName = g_i18n:getText("RVB_faultText_" .. partKey)
                local name = RVB_PART_NAMES[partKey] or partKey
                if rvbName and not rvbName:find("Missing") and rvbName ~= ("RVB_faultText_" .. partKey) then
                    name = rvbName
                end
                table.insert(components, { name = name, condition = conditionPct, bad = true })
            end
        end

        -- Include UsedPlus Hydraulic System if toggled for repair
        if RVBWorkshopIntegration and RVBWorkshopIntegration.hydraulicRepairRequested and maintSpec then
            local hydRelPct = math.floor((maintSpec.hydraulicReliability or 1) * 100)
            table.insert(components, {
                name = g_i18n:getText("usedplus_hydraulic_system") or "Hydraulic System",
                condition = hydRelPct, bad = true
            })
        end
    end

    -- Collect vanilla damage info (when not in RVB mode and no maintenance spec)
    if #components == 0 and isRepairMode then
        local dmgPct = math.floor((1 - (self.currentDamage or 0)) * 100)
        table.insert(components, { name = g_i18n:getText("usedplus_rp_mechanical") or "Mechanical", condition = dmgPct, bad = dmgPct < 50 })
    end
    if not isRepairMode then
        local paintPct = math.floor((1 - (self.currentWear or 0)) * 100)
        table.insert(components, { name = g_i18n:getText("usedplus_rp_paint") or "Paint", condition = paintPct, bad = paintPct < 50 })
    end

    -- Sort: bad components first, then by condition ascending
    table.sort(components, function(a, b)
        if a.bad ~= b.bad then return a.bad end
        return a.condition < b.condition
    end)

    -- Populate grid slots (fill left column first, then right)
    for i = 1, NUM_SLOTS do
        local slot = self["compSlot" .. i]
        if slot then
            local comp = components[i]
            if comp then
                -- No prefix indicator — color alone communicates state (red/yellow/green)
                slot:setText(string.format("%s  %d%%", comp.name, comp.condition))
                if comp.bad then
                    slot:setTextColor(1, 0.4, 0.3, 1)        -- Red for needs repair
                elseif comp.condition < 50 then
                    slot:setTextColor(1, 0.8, 0.2, 1)        -- Yellow for worn
                else
                    slot:setTextColor(0.4, 0.9, 0.4, 1)      -- Green for good
                end
                slot:setVisible(true)
            else
                slot:setText("")
                slot:setVisible(false)
            end
        end
    end
end

--[[
     Pay cash button clicked - shows confirmation dialog first
]]
function RepairDialog:onPayCash()
    if self.totalCost <= 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noRepairsSelected")
        )
        return
    end

    -- Check funds
    local farm = g_farmManager:getFarmById(self.farmId)
    if not farm or farm.money < self.totalCost then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_insufficientFundsRepair"), UIHelper.Text.formatMoney(self.totalCost))
        )
        return
    end

    -- Build confirmation message
    local serviceType
    if self.rvbRepairCost and self.rvbRepairCost > 0 then
        serviceType = g_i18n:getText("usedplus_rp_service_workshop") or "Workshop Repair"
    elseif self.mode == RepairDialog.MODE_REPAIR then
        serviceType = g_i18n:getText("usedplus_rp_service_mechanical") or "Mechanical Repair"
    else
        serviceType = g_i18n:getText("usedplus_rp_service_repaint") or "Repaint"
    end
    local workPercent = (self.mode == RepairDialog.MODE_REPAIR) and self.repairPercent or self.repaintPercent

    local confirmMessage = string.format(
        g_i18n:getText("usedplus_rp_confirmMessageFormat"),
        serviceType,
        self.vehicleName,
        workPercent,
        serviceType,
        g_i18n:formatMoney(self.totalCost, 0, true, true)
    )

    -- Set bypass flag so VehicleSellingPointExtension doesn't intercept this dialog
    -- and create an infinite loop of RepairDialog → YesNoDialog → RepairDialog
    if VehicleSellingPointExtension then
        VehicleSellingPointExtension.bypassInterception = true
    end

    -- Show confirmation dialog using FS25's YesNoDialog.show()
    -- Signature: YesNoDialog.show(callback, target, text, title, yesText, noText)
    YesNoDialog.show(
        self.onPayCashConfirmed,
        self,
        confirmMessage,
        g_i18n:getText("usedplus_rp_confirm_title") or "Confirm Payment"
    )
end

--[[
    Callback when user confirms Pay Cash
    @param yes - true if user clicked Yes
]]
function RepairDialog:onPayCashConfirmed(yes)
    -- Reset bypass flag (whether confirmed or cancelled)
    if VehicleSellingPointExtension then
        VehicleSellingPointExtension.bypassInterception = false
    end

    if not yes then
        return  -- User cancelled
    end

    -- v2.15.4: When RVB cost was used, trigger RVB's native repair callback
    -- This repairs RVB components and deducts money through RVB's own mechanism.
    -- hookRepairCompletion handles hydraulic repair when RVB's callback fires.
    if self.rvbRepairCost and self.rvbRepairCost > 0 and VehicleSellingPointExtension then
        local callback = VehicleSellingPointExtension.pendingRepairCallback
        local target = VehicleSellingPointExtension.pendingRepairTarget

        UsedPlus.logDebug(string.format("RepairDialog: RVB path — callback=%s, target=%s, rvbCost=%s",
            tostring(callback), tostring(target), tostring(self.rvbRepairCost)))

        if callback then
            -- Trigger RVB's repair (deducts money + repairs components)
            local ok, err = pcall(callback, target, true)
            if ok then
                UsedPlus.logDebug("RepairDialog: Triggered RVB repair callback successfully")
            else
                UsedPlus.logError("RepairDialog: RVB repair callback FAILED: " .. tostring(err))
            end
        else
            UsedPlus.logWarn("RepairDialog: pendingRepairCallback is NIL — RVB component repair will NOT fire!")
        end

        -- Trigger side effects (seizures, fluids, steering pull) with epsilon repair
        -- Epsilon (0.001) triggers all side-effect guards (> 0) but does negligible
        -- base damage repair. Real base damage repair is handled gradually by
        -- UsedPlusMaintenance.onUpdate alongside hydraulic interpolation.
        RepairVehicleEvent.sendToServer(
            self.vehicle,
            self.farmId,
            0.001,  -- Epsilon: triggers side effects, negligible base damage change
            0,      -- No repaint
            0,      -- $0 cost (RVB already deducted)
            false
        )

        -- Clear stored callback
        VehicleSellingPointExtension.pendingRepairCallback = nil
        VehicleSellingPointExtension.pendingRepairTarget = nil
    else
        -- Vanilla repair path
        local sendRepairPercent = 0
        local sendRepaintPercent = 0

        if self.mode == RepairDialog.MODE_REPAIR or self.mode == RepairDialog.MODE_BOTH then
            sendRepairPercent = self.repairPercent / 100
        end
        if self.mode == RepairDialog.MODE_REPAINT or self.mode == RepairDialog.MODE_BOTH then
            sendRepaintPercent = self.repaintPercent / 100
        end

        RepairVehicleEvent.sendToServer(
            self.vehicle,
            self.farmId,
            sendRepairPercent,
            sendRepaintPercent,
            self.totalCost,
            false  -- Not financed
        )
    end

    -- Close dialog
    self:close()

    -- Show success notification
    local repairInfo = ""
    if self.rvbRepairCost and self.rvbRepairCost > 0 then
        repairInfo = g_i18n:getText("usedplus_rp_notification_workshop") or "full workshop repair"
    elseif self.repairPercent > 0 and self.currentDamage > 0.01 then
        repairInfo = string.format("%d%% mechanical repair", self.repairPercent)
    end
    if self.repaintPercent > 0 and self.currentWear > 0.01 then
        if repairInfo ~= "" then
            repairInfo = repairInfo .. ", "
        end
        repairInfo = repairInfo .. string.format("%d%% repaint", self.repaintPercent)
    end

    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format(g_i18n:getText("usedplus_notification_repairComplete"),
            repairInfo,
            UIHelper.Text.formatMoney(self.totalCost))
    )

    -- Refresh the WorkshopScreen to show updated values
    RepairDialog.refreshWorkshopScreen()
end

--[[
     Refresh the WorkshopScreen to show updated damage/wear values
    Called after repair is applied
     This function explores various methods to refresh the workshop UI
]]
function RepairDialog.refreshWorkshopScreen()
    UsedPlus.logTrace("refreshWorkshopScreen called")

    -- The WorkshopScreen GUI is accessed via g_gui.guis.WorkshopScreen
    local workshopGui = g_gui and g_gui.guis and g_gui.guis.WorkshopScreen
    if not workshopGui then
        UsedPlus.logTrace("WorkshopScreen GUI not found")
        return
    end

    local workshopScreen = workshopGui.target or workshopGui

    -- Get vehicle to read updated values
    local vehicle = workshopScreen.vehicle or (g_workshopScreen and g_workshopScreen.vehicle)
    if not vehicle then
        UsedPlus.logTrace("No vehicle found for refresh")
        return
    end

    -- Get current wear/damage from vehicle
    local currentWear = vehicle.getWearTotalAmount and vehicle:getWearTotalAmount() or 0
    local currentDamage = vehicle.getDamageAmount and vehicle:getDamageAmount() or 0

    UsedPlus.logTrace(string.format("Vehicle state - wear: %.1f%%, damage: %.1f%%",
        currentWear * 100, currentDamage * 100))

    -- Try to find and update condition/wear display elements
    local elementsToTry = {
        "conditionBar", "wearBar", "damageBar", "paintBar",
        "conditionValue", "wearValue", "damageValue", "paintValue",
        "vehicleCondition", "vehicleWear", "vehicleDamage", "vehiclePaint"
    }

    for _, elemName in ipairs(elementsToTry) do
        local elem = workshopScreen[elemName]
        if elem then
            if elem.setValue then
                if string.find(elemName:lower(), "wear") or string.find(elemName:lower(), "paint") then
                    elem:setValue(1 - currentWear)
                elseif string.find(elemName:lower(), "damage") or string.find(elemName:lower(), "condition") then
                    elem:setValue(1 - currentDamage)
                end
            end
            if elem.setText then
                if string.find(elemName:lower(), "wear") or string.find(elemName:lower(), "paint") then
                    elem:setText(string.format("%.0f%%", (1 - currentWear) * 100))
                elseif string.find(elemName:lower(), "damage") or string.find(elemName:lower(), "condition") then
                    elem:setText(string.format("%.0f%%", (1 - currentDamage) * 100))
                end
            end
        end
    end

    -- Try various refresh methods
    if workshopScreen.updateVehicleInfo then workshopScreen:updateVehicleInfo() end
    if workshopScreen.updateDisplay then workshopScreen:updateDisplay() end

    -- Try to refresh the vehicle list
    if workshopScreen.list then
        local list = workshopScreen.list
        if list.reloadData then list:reloadData() end
        if list.updateItemPositions then list:updateItemPositions() end
        if list.updateContents then list:updateContents() end

        if list.getSelectedElementIndex and list.setSelectedIndex then
            local idx = list:getSelectedElementIndex()
            if idx then list:setSelectedIndex(idx) end
        end
    end

    -- Try to trigger vehicle update
    if workshopScreen.onVehicleChanged then workshopScreen:onVehicleChanged(vehicle) end
    if workshopScreen.setVehicle then workshopScreen:setVehicle(vehicle) end
    if workshopScreen.updateButtons then workshopScreen:updateButtons() end
    if workshopScreen.updateMenuButtons then workshopScreen:updateMenuButtons() end
    if workshopScreen.onMenuUpdate then workshopScreen:onMenuUpdate() end

    -- Try to trigger list selection refresh
    if workshopScreen.onListSelectionChanged then
        local selectedIdx = 1
        if workshopScreen.list and workshopScreen.list.getSelectedElementIndex then
            selectedIdx = workshopScreen.list:getSelectedElementIndex() or 1
        end
        workshopScreen:onListSelectionChanged(selectedIdx)
    end

    -- Force vehicle dirty flags
    if vehicle.setDirty then vehicle:setDirty() end
    if vehicle.raiseActive then vehicle:raiseActive() end

    UsedPlus.logTrace("refreshWorkshopScreen complete")
end

--[[
     Finance button clicked - open full RepairFinanceDialog
    Allows user to select term, down payment, and see full payment details
]]
function RepairDialog:onFinanceRepair()
    if self.totalCost <= 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noRepairsSelected")
        )
        return
    end

    -- Capture data before closing (only send values for active mode)
    local capturedVehicle = self.vehicle
    local capturedFarmId = self.farmId
    local capturedTotalCost = self.totalCost
    local capturedMode = self.mode

    -- Only send percent for the active mode
    local capturedRepairPercent = 0
    local capturedRepaintPercent = 0
    if self.mode == RepairDialog.MODE_REPAIR or self.mode == RepairDialog.MODE_BOTH then
        capturedRepairPercent = self.repairPercent
    end
    if self.mode == RepairDialog.MODE_REPAINT or self.mode == RepairDialog.MODE_BOTH then
        capturedRepaintPercent = self.repaintPercent
    end

    -- Close this dialog
    self:close()

    -- Use DialogLoader for centralized lazy loading
    DialogLoader.show("RepairFinanceDialog", "setData",
        capturedVehicle,
        capturedFarmId,
        capturedTotalCost,
        capturedRepairPercent,
        capturedRepaintPercent,
        capturedMode,
        self.rvbRepairCost  -- Pass RVB context so finance path can trigger RVB repair
    )
end

--[[
     Cancel button clicked
]]
function RepairDialog:onCancel()
    self:close()
end

--[[
     Update button background highlights to show current selection
]]
function RepairDialog:updateButtonHighlights()
    local currentPercent = (self.mode == RepairDialog.MODE_REPAIR) and self.repairPercent or self.repaintPercent

    -- Define colors for normal, selected, and 100% states
    local normalColor = {0.15, 0.15, 0.18, 1}      -- Dark gray
    local selectedColor = {0.2, 0.4, 0.6, 1}       -- Blue highlight
    local fullNormalColor = {0.15, 0.25, 0.15, 1}  -- Green tint for 100%
    local fullSelectedColor = {0.2, 0.5, 0.25, 1}  -- Bright green when selected

    -- Helper to set button background color
    local function setButtonColor(element, color)
        if element and element.setImageColor then
            element:setImageColor(nil, color[1], color[2], color[3], color[4])
        end
    end

    -- Update each button's background
    setButtonColor(self.btn25Bg, currentPercent == 25 and selectedColor or normalColor)
    setButtonColor(self.btn50Bg, currentPercent == 50 and selectedColor or normalColor)
    setButtonColor(self.btn75Bg, currentPercent == 75 and selectedColor or normalColor)
    setButtonColor(self.btn100Bg, currentPercent == 100 and fullSelectedColor or fullNormalColor)
end

--[[
     Quick buttons (preset percentages) - unified for both modes
]]
function RepairDialog:onQuickButton25()
    if self.mode == RepairDialog.MODE_REPAIR then
        self.repairPercent = 25
    else
        self.repaintPercent = 25
    end
    self:calculateCosts()
    self:updateDisplay()
end

function RepairDialog:onQuickButton50()
    if self.mode == RepairDialog.MODE_REPAIR then
        self.repairPercent = 50
    else
        self.repaintPercent = 50
    end
    self:calculateCosts()
    self:updateDisplay()
end

function RepairDialog:onQuickButton75()
    if self.mode == RepairDialog.MODE_REPAIR then
        self.repairPercent = 75
    else
        self.repaintPercent = 75
    end
    self:calculateCosts()
    self:updateDisplay()
end

function RepairDialog:onQuickButton100()
    if self.mode == RepairDialog.MODE_REPAIR then
        self.repairPercent = 100
    else
        self.repaintPercent = 100
    end
    self:calculateCosts()
    self:updateDisplay()
end

UsedPlus.logInfo("RepairDialog loaded")
