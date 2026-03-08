--[[
    FS25_UsedPlus - Lease Renewal Dialog

    Unified dialog for lease expiration handling (both vehicles and land)
    Shows when a lease term completes with options:
    - Return: Give back asset, receive security deposit refund
    - Buyout: Purchase asset at residual value minus equity
    - Renew: Extend lease with equity rollover

    Works for both vehicle and land leases with appropriate UI adjustments.
]]

LeaseRenewalDialog = {}
local LeaseRenewalDialog_mt = Class(LeaseRenewalDialog, MessageDialog)

-- Action constants
LeaseRenewalDialog.ACTION_RETURN = 1
LeaseRenewalDialog.ACTION_BUYOUT = 2
LeaseRenewalDialog.ACTION_RENEW = 3

--[[
    Constructor
]]
function LeaseRenewalDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or LeaseRenewalDialog_mt)

    -- Deal data
    self.deal = nil
    self.isLandLease = false
    self.vehicle = nil  -- For vehicle leases

    -- Calculated values
    self.equityAccumulated = 0
    self.depositRefund = 0
    self.deductions = {}
    self.buyoutPrice = 0
    self.damagePenalty = 0

    -- Callback
    self.callback = nil

    -- v2.9.5: Icon directory for dynamic icons
    self.iconDir = UsedPlus.MOD_DIR .. "gui/icons/"

    return self
end

--[[
    Called when GUI is created - set up icons via Lua (only method that works for mod images in ZIP)
]]
function LeaseRenewalDialog:onCreate()
    LeaseRenewalDialog:superClass().onCreate(self)

    local iconDir = self.iconDir

    if self.returnIcon ~= nil then
        self.returnIcon:setImageFilename(iconDir .. "arrow_left.dds")
    end
    if self.buyoutIcon ~= nil then
        self.buyoutIcon:setImageFilename(iconDir .. "cash.dds")
    end
    if self.renewIcon ~= nil then
        self.renewIcon:setImageFilename(iconDir .. "lease.dds")
    end
end

--[[
    Set lease deal data
    @param deal - The FinanceDeal that has expired
    @param callback - Function to call with action result
]]
function LeaseRenewalDialog:setDeal(deal, callback)
    self.deal = deal
    self.callback = callback

    -- Determine lease type
    self.isLandLease = (deal.itemType == "land") or
                       (deal.itemId and string.find(deal.itemId, "farmland"))

    -- Find vehicle if vehicle lease
    if not self.isLandLease then
        self.vehicle = self:findVehicle()
    end

    -- Calculate all values
    self:calculateValues()
end

--[[
    Find the leased vehicle
]]
function LeaseRenewalDialog:findVehicle()
    if self.deal == nil then return nil end

    -- Try by objectId first
    if self.deal.objectId then
        local vehicle = NetworkUtil.getObject(self.deal.objectId)
        if vehicle then return vehicle end
    end

    -- Search by config filename
    local configFile = self.deal.itemId or self.deal.vehicleConfig
    if configFile then
        for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
            if vehicle.configFileName == configFile and
               vehicle.ownerFarmId == self.deal.farmId then
                return vehicle
            end
        end
    end

    return nil
end

--[[
    Calculate all values for display
]]
function LeaseRenewalDialog:calculateValues()
    local deal = self.deal
    if deal == nil then return end

    -- Calculate depreciation and equity
    local depreciation = (deal.originalPrice or deal.baseCost or 0) - (deal.residualValue or 0)
    self.equityAccumulated = FinanceCalculations.calculateLeaseEquity(
        deal.monthlyPayment,
        deal.monthsPaid,
        depreciation,
        deal.termMonths
    )

    -- Calculate damage penalty for vehicles
    self.damagePenalty = 0
    if not self.isLandLease and self.vehicle then
        self.damagePenalty = self:calculateDamagePenalty()
    end

    -- Calculate security deposit refund
    local securityDeposit = deal.securityDeposit or 0
    self.depositRefund, self.deductions = FinanceCalculations.calculateSecurityDepositRefund(
        securityDeposit,
        self.damagePenalty,
        deal.missedPayments or 0,
        self.isLandLease
    )

    -- Calculate buyout price with equity applied
    local residualValue = deal.residualValue or deal.landPrice or deal.originalPrice or 0
    self.buyoutPrice = FinanceCalculations.calculateLeaseBuyout(residualValue, self.equityAccumulated)

    UsedPlus.logDebug(string.format("LeaseRenewalDialog calc: equity=$%d, deposit=$%d, refund=$%d, buyout=$%d",
        self.equityAccumulated, securityDeposit, self.depositRefund, self.buyoutPrice))
end

--[[
    Calculate damage penalty for vehicle
]]
function LeaseRenewalDialog:calculateDamagePenalty()
    if self.vehicle == nil then return 0 end

    local currentDamage = 0
    local currentWear = 0

    if self.vehicle.spec_wearable then
        currentDamage = self.vehicle.spec_wearable.damage or 0
        currentWear = self.vehicle.spec_wearable.wear or 0
    end

    -- Allowed: 10% paint damage, 15% wear
    local allowedDamage = 0.10
    local allowedWear = 0.15

    local startDamage = self.deal.startDamage or 0
    local startWear = self.deal.startWear or 0

    local excessDamage = math.max(0, currentDamage - startDamage - allowedDamage)
    local excessWear = math.max(0, currentWear - startWear - allowedWear)

    -- Penalty is 30% of base cost per excess point
    local baseCost = self.deal.originalPrice or self.deal.baseCost or 0
    local penalty = (excessDamage + excessWear) * baseCost * 0.30

    return math.floor(penalty)
end

--[[
    Called when dialog opens
]]
function LeaseRenewalDialog:onOpen()
    LeaseRenewalDialog:superClass().onOpen(self)
    self:updateDisplay()
end

--[[
    Update all display elements
]]
function LeaseRenewalDialog:updateDisplay()
    local deal = self.deal
    if deal == nil then return end

    -- Title
    local title = self.isLandLease and g_i18n:getText("usedplus_lr_landLeaseComplete") or g_i18n:getText("usedplus_lr_vehicleLeaseComplete")
    UIHelper.Element.setText(self.titleText, title)

    -- Asset name
    local assetName = deal.itemName or deal.vehicleName or deal.landName or g_i18n:getText("usedplus_common_unknown")
    UIHelper.Element.setText(self.assetNameText, assetName)

    -- Lease summary
    local termYears = deal.termMonths / 12
    local termText = termYears >= 1 and string.format(g_i18n:getText("usedplus_lr_termYears"), termYears) or string.format(g_i18n:getText("usedplus_lr_termMonths"), deal.termMonths)
    UIHelper.Element.setText(self.termText, termText)
    UIHelper.Element.setText(self.paymentsMadeText, string.format("%d of %d", deal.monthsPaid, deal.termMonths))

    local totalPaid = deal.monthlyPayment * deal.monthsPaid
    UIHelper.Element.setText(self.totalPaidText, UIHelper.Text.formatMoney(totalPaid))
    UIHelper.Element.setText(self.equityText, UIHelper.Text.formatMoney(self.equityAccumulated))

    -- Deposit status
    local securityDeposit = deal.securityDeposit or 0
    UIHelper.Element.setText(self.depositText, UIHelper.Text.formatMoney(securityDeposit))

    local totalDeductions = securityDeposit - self.depositRefund
    if totalDeductions > 0 then
        UIHelper.Element.setTextWithColor(self.deductionsText,
            "-" .. UIHelper.Text.formatMoney(totalDeductions), UIHelper.Colors.DEBT_RED)
    else
        UIHelper.Element.setText(self.deductionsText, UIHelper.Text.formatMoney(0))
    end
    UIHelper.Element.setText(self.refundText, UIHelper.Text.formatMoney(self.depositRefund))

    -- Vehicle condition (hide for land)
    if self.conditionLabel then
        UIHelper.Element.setVisible(self.conditionLabel, not self.isLandLease)
    end
    if self.conditionText then
        UIHelper.Element.setVisible(self.conditionText, not self.isLandLease)
        if not self.isLandLease and self.vehicle then
            local condition = self:getConditionText()
            UIHelper.Element.setText(self.conditionText, condition)
        end
    end

    -- Return option
    if self.depositRefund > 0 then
        UIHelper.Element.setText(self.returnRefundText, string.format(g_i18n:getText("usedplus_lr_depositRefundFormat"), UIHelper.Text.formatMoney(self.depositRefund)))
    else
        UIHelper.Element.setText(self.returnRefundText, g_i18n:getText("usedplus_lr_noRefund"))
    end

    -- Buyout option
    UIHelper.Element.setText(self.buyoutPriceText, UIHelper.Text.formatMoney(self.buyoutPrice))

    -- Check if farm can afford buyout
    local farm = g_farmManager:getFarmById(deal.farmId)
    local canAffordBuyout = farm and farm.money >= self.buyoutPrice
    if self.buyoutButton then
        self.buyoutButton:setDisabled(not canAffordBuyout)
    end
    -- Dim buyout card when unaffordable (three-layer button visual feedback)
    if self.buyoutBg then
        if canAffordBuyout then
            self.buyoutBg:setImageColor(nil, 0.10, 0.10, 0.14, 0.9)  -- Normal
        else
            self.buyoutBg:setImageColor(nil, 0.06, 0.06, 0.08, 0.5)  -- Dimmed
        end
    end

    -- Renew option
    UIHelper.Element.setText(self.renewEquityText, string.format(g_i18n:getText("usedplus_lr_equityAppliedFormat"), UIHelper.Text.formatMoney(self.equityAccumulated)))

    -- Help text (use i18n key from XML, supports all languages)
    UIHelper.Element.setText(self.helpText, g_i18n:getText("usedplus_lr_helpText"))
end

--[[
    Get condition description text for vehicle
]]
function LeaseRenewalDialog:getConditionText()
    if self.vehicle == nil then return "Unknown" end

    local damage = 0
    local wear = 0
    if self.vehicle.spec_wearable then
        damage = self.vehicle.spec_wearable.damage or 0
        wear = self.vehicle.spec_wearable.wear or 0
    end

    if damage < 0.05 and wear < 0.10 then
        return g_i18n:getText("usedplus_condition_excellent")
    elseif damage < 0.15 and wear < 0.25 then
        return g_i18n:getText("usedplus_condition_good")
    elseif damage < 0.30 and wear < 0.40 then
        return g_i18n:getText("usedplus_condition_fair")
    else
        return g_i18n:getText("usedplus_condition_poor")
    end
end

--[[
    Return button clicked - give back asset, get deposit refund
]]
function LeaseRenewalDialog:onReturn()
    if self.callback then
        self.callback(LeaseRenewalDialog.ACTION_RETURN, {
            depositRefund = self.depositRefund,
            damagePenalty = self.damagePenalty
        })
    end
    self:close()
end

--[[
    Buyout button clicked - purchase asset at residual minus equity
]]
function LeaseRenewalDialog:onBuyout()
    -- Verify funds
    local farm = g_farmManager:getFarmById(self.deal.farmId)
    if not farm or farm.money < self.buyoutPrice then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_ERROR,
            string.format(g_i18n:getText("usedplus_notification_insufficientBuyout"),
                UIHelper.Text.formatMoney(self.buyoutPrice))
        )
        return
    end

    if self.callback then
        self.callback(LeaseRenewalDialog.ACTION_BUYOUT, {
            buyoutPrice = self.buyoutPrice,
            equityApplied = self.equityAccumulated,
            depositRefund = self.depositRefund
        })
    end
    self:close()
end

--[[
    Renew button clicked - extend lease with equity rollover
]]
function LeaseRenewalDialog:onRenew()
    if self.callback then
        self.callback(LeaseRenewalDialog.ACTION_RENEW, {
            equityRollover = self.equityAccumulated,
            newResidualValue = self.buyoutPrice  -- Residual is reduced by equity
        })
    end
    self:close()
end

--[[
    Cancel button - defer choice to next month (Issue #5)
    Player can dismiss the dialog; it will reappear next period.
    No extra charges are applied while deferred (see FinanceManager guard).
]]
function LeaseRenewalDialog:onCancel()
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_INFO,
        g_i18n:getText("usedplus_lr_deferNotice")
    )
    self:close()
end

--[[
    Hover effect handler for option card buttons (three-layer pattern)
    Changes background color when mouse hovers over card
]]
function LeaseRenewalDialog:onOptionHighlight(element)
    if element ~= nil and element.id ~= nil then
        -- Don't highlight disabled buttons (e.g. unaffordable buyout)
        if element.getIsDisabled and element:getIsDisabled() then return end

        local bgMapping = {
            returnButton = "returnBg",
            buyoutButton = "buyoutBg",
            renewButton = "renewBg"
        }
        local bgId = bgMapping[element.id]
        local bg = self[bgId]
        if bg ~= nil then
            bg:setImageColor(nil, 0.18, 0.22, 0.30, 0.95)
        end
    end
end

function LeaseRenewalDialog:onOptionUnhighlight(element)
    if element ~= nil and element.id ~= nil then
        local bgMapping = {
            returnButton = "returnBg",
            buyoutButton = "buyoutBg",
            renewButton = "renewBg"
        }
        local bgId = bgMapping[element.id]
        local bg = self[bgId]
        if bg ~= nil then
            -- Keep dimmed state for disabled buyout card
            if element.id == "buyoutButton" and element.getIsDisabled and element:getIsDisabled() then
                bg:setImageColor(nil, 0.06, 0.06, 0.08, 0.5)  -- Stay dimmed
            else
                -- Restore normal color (matches lrOptionCardBg profile)
                bg:setImageColor(nil, 0.10, 0.10, 0.14, 0.9)
            end
        end
    end
end

--[[
    Cleanup on close
]]
function LeaseRenewalDialog:onClose()
    self.deal = nil
    self.vehicle = nil
    self.callback = nil
    LeaseRenewalDialog:superClass().onClose(self)
end

--[[
    Static show method for external use
]]
function LeaseRenewalDialog.show(deal, callback)
    DialogLoader.show("LeaseRenewalDialog", "setDeal", deal, callback)
end

UsedPlus.logInfo("LeaseRenewalDialog loaded")
