--[[
    FS25_UsedPlus - Lease End Dialog

     Dialog shown when a lease term completes
     Pattern from: MessageDialog (simple yes/no with info display)

    Options:
    1. Return Vehicle - Pay damage penalties, vehicle is removed
    2. Buyout Vehicle - Pay residual value, keep vehicle as owned

    Displays:
    - Vehicle name and image
    - Lease summary (term, payments made)
    - Current condition (damage/wear)
    - Damage penalties (if any)
    - Buyout price (residual value)
]]

LeaseEndDialog = {}
local LeaseEndDialog_mt = Class(LeaseEndDialog, MessageDialog)

--[[
     Constructor
]]
function LeaseEndDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or LeaseEndDialog_mt)

    self.leaseDeal = nil
    self.vehicle = nil
    self.damagePenalty = 0
    self.buyoutPrice = 0
    self.callback = nil

    -- v2.9.5: Icon directory for dynamic icons
    self.iconDir = UsedPlus.MOD_DIR .. "gui/icons/"

    return self
end

--[[
     Called when dialog is created
]]
function LeaseEndDialog:onCreate()
    LeaseEndDialog:superClass().onCreate(self)
end

--[[
     Called when dialog opens
]]
function LeaseEndDialog:onOpen()
    LeaseEndDialog:superClass().onOpen(self)

    -- v2.9.5: Setup option icons
    self:setupOptionIcons()

    self:updateDisplay()
end

--[[
    v2.9.5: Setup option icons
]]
function LeaseEndDialog:setupOptionIcons()
    -- Return icon (arrow_left)
    local returnIcon = self.dialogElement:getDescendantById("returnIcon")
    if returnIcon ~= nil then
        returnIcon:setImageFilename(self.iconDir .. "arrow_left.dds")
    end

    -- Buyout icon (cash)
    local buyoutIcon = self.dialogElement:getDescendantById("buyoutIcon")
    if buyoutIcon ~= nil then
        buyoutIcon:setImageFilename(self.iconDir .. "cash.dds")
    end
end

--[[
     Set lease deal data
    @param leaseDeal - The LeaseDeal that has ended
    @param vehicle - The leased vehicle (may be nil if not found)
    @param callback - Function to call with result ("return" or "buyout")
]]
function LeaseEndDialog:setData(leaseDeal, vehicle, callback)
    self.leaseDeal = leaseDeal
    self.vehicle = vehicle
    self.callback = callback

    -- Calculate damage penalty
    if vehicle and leaseDeal.calculateDamagePenalty then
        self.damagePenalty = leaseDeal:calculateDamagePenalty(vehicle)
    else
        self.damagePenalty = 0
    end

    -- Get buyout price (residual value)
    self.buyoutPrice = leaseDeal.residualValue or 0
end

--[[
     Update display with lease data
     Refactored to use UIHelper for consistent formatting
]]
function LeaseEndDialog:updateDisplay()
    if self.leaseDeal == nil then return end

    local deal = self.leaseDeal

    -- Vehicle name
    UIHelper.Element.setText(self.vehicleNameText, deal.itemName or deal.vehicleName or "Unknown Vehicle")

    -- Lease summary
    local termYears = math.floor(deal.termMonths / 12)
    local totalPaid = deal.monthlyPayment * deal.monthsPaid
    UIHelper.Element.setText(self.leaseSummaryText,
        string.format("%d year lease completed. Total payments: %s",
            termYears, UIHelper.Text.formatMoney(totalPaid)))

    -- Vehicle condition
    if self.vehicle then
        local damage = 0
        local wear = 0
        if self.vehicle.spec_wearable then
            damage = self.vehicle.spec_wearable.damage or 0
            wear = self.vehicle.spec_wearable.wear or 0
        end
        UIHelper.Element.setText(self.conditionText,
            string.format("Damage: %s | Wear: %s",
                UIHelper.Text.formatPercent(damage, true, 0),
                UIHelper.Text.formatPercent(wear, true, 0)))
    else
        UIHelper.Element.setText(self.conditionText, "Vehicle condition: Unknown")
    end

    -- Damage penalty (red if any, green if none)
    if self.damagePenalty > 0 then
        UIHelper.Element.setTextWithColor(self.penaltyText,
            UIHelper.Text.formatMoneyWithLabel("Damage Penalty", self.damagePenalty),
            UIHelper.Colors.DEBT_RED)
    else
        UIHelper.Element.setTextWithColor(self.penaltyText,
            "No damage penalty - vehicle in good condition!",
            UIHelper.Colors.MONEY_GREEN)
    end
    UIHelper.Element.setVisible(self.penaltyText, true)

    -- Buyout price
    UIHelper.Element.setText(self.buyoutPriceText,
        UIHelper.Text.formatMoneyWithLabel("Buyout Price", self.buyoutPrice))

    -- Return cost (just penalty - show as red if non-zero)
    if self.damagePenalty > 0 then
        UIHelper.Element.setTextWithColor(self.returnCostText,
            UIHelper.Text.formatMoneyWithLabel("Return Cost", self.damagePenalty),
            UIHelper.Colors.DEBT_RED)
    else
        UIHelper.Element.setTextWithColor(self.returnCostText,
            UIHelper.Text.formatMoneyWithLabel("Return Cost", 0),
            UIHelper.Colors.MONEY_GREEN)
    end
end

--[[
     Return vehicle button clicked
]]
function LeaseEndDialog:onReturnVehicle()
    if self.callback then
        self.callback("return", self.damagePenalty)
    end
    self:close()
end

--[[
     Buyout vehicle button clicked
]]
function LeaseEndDialog:onBuyoutVehicle()
    -- Check if farm can afford buyout
    local farmId = self.leaseDeal.farmId
    local farm = g_farmManager:getFarmById(farmId)

    if farm and farm.money < self.buyoutPrice then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_ERROR,
            string.format(g_i18n:getText("usedplus_notification_insufficientBuyout"),
                UIHelper.Text.formatMoney(self.buyoutPrice))
        )
        return
    end

    if self.callback then
        self.callback("buyout", self.buyoutPrice)
    end
    self:close()
end

--[[
     Cancel - defer choice to next month (Issue #5)
     Player can dismiss the dialog; it will reappear next period.
     No extra charges are applied while deferred (see FinanceManager guard).
]]
function LeaseEndDialog:onCancel()
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_INFO,
        g_i18n:getText("usedplus_lr_deferNotice")
    )
    self:close()
end

--[[
     Cleanup
]]
function LeaseEndDialog:onClose()
    self.leaseDeal = nil
    self.vehicle = nil
    self.callback = nil

    LeaseEndDialog:superClass().onClose(self)
end

UsedPlus.logInfo("LeaseEndDialog loaded")
