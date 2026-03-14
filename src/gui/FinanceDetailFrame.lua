--[[
    FS25_UsedPlus - Finance Detail Frame

     GUI class for detailed deal view and payment screen
     Pattern from: Game's vehicle/equipment detail screens
     Reference: FS25_ADVANCED_PATTERNS.md - GUI Frame Pattern

    Responsibilities:
    - Display full deal information (original terms, dates, etc.)
    - Show payment status (balance, progress, interest/principal breakdown)
    - Provide payment slider with quick-select buttons (1mo/6mo/1yr/payoff)
    - Calculate payment preview (principal vs interest split)
    - Send FinancePaymentEvent or TerminateLeaseEvent
    - Handle prepayment penalties

    Layout: 3-column (Deal Info | Payment Status | Payment Options)
]]

FinanceDetailFrame = {}
local FinanceDetailFrame_mt = Class(FinanceDetailFrame, TabbedMenuFrameElement)

FinanceDetailFrame.CONTROLS = {
    -- Left column: Deal Information
    "itemNameText",
    "dealTypeText",
    "originalPriceText",
    "downPaymentText",
    "amountFinancedText",
    "interestRateText",
    "termText",
    "startDateText",

    -- Center column: Payment Status
    "currentBalanceText",
    "principalPaidText",
    "interestPaidText",
    "remainingPrincipalText",
    "projectedInterestText",
    "progressBar",

    -- Right column: Payment Options
    "paymentSlider",
    "paymentAmountText",
    "paymentTotalText",
    "toPrincipalText",
    "toInterestText",
    "newBalanceText",
    "prepaymentPenaltyText",

    -- Buttons
    "makePaymentButton",
    "endLeaseButton",
    "button1Month",
    "button6Months",
    "button1Year",
    "buttonPayoff"
}

--[[
     Constructor
]]
function FinanceDetailFrame.new(target, customMt, messageCenter, i18n, inputManager)
    local self = TabbedMenuFrameElement.new(target, customMt or FinanceDetailFrame_mt)

    self:registerControls(FinanceDetailFrame.CONTROLS)

    self.messageCenter = messageCenter
    self.i18n = i18n
    self.inputManager = inputManager

    self.dealId = nil
    self.deal = nil
    self.farmId = nil

    return self
end

--[[
     Set deal to display
     Called from FinanceManagerFrame when opening
]]
function FinanceDetailFrame:setDealId(dealId)
    self.dealId = dealId

    -- Get deal from manager
    if g_financeManager then
        self.deal = g_financeManager:getDealById(dealId)
    end

    if self.deal == nil then
        UsedPlus.logError(string.format("Deal %s not found", dealId))
        self:close()
        return
    end

    self.farmId = self.deal.farmId

    -- Populate all sections
    self:updateDealInfo()
    self:updatePaymentStatus()
    self:updatePaymentOptions()
end

--[[
     Update deal information section (left column)
]]
function FinanceDetailFrame:updateDealInfo()
    if self.deal == nil then return end

    -- Item name
    if self.itemNameText then
        local itemName = self.deal.itemName or self.deal.vehicleName or g_i18n:getText("usedplus_common_unknown")
        self.itemNameText:setText(itemName)
    end

    -- Deal type
    if self.dealTypeText then
        local dealTypeKey = "usedplus_dealType_finance"
        if self.deal.dealType == 2 then  -- LeaseDeal
            dealTypeKey = "usedplus_dealType_lease"
        end
        self.dealTypeText:setText(g_i18n:getText(dealTypeKey))
    end

    -- Financial details
    if self.originalPriceText then
        local originalPrice = self.deal.baseCost or self.deal.basePrice or 0
        self.originalPriceText:setText(g_i18n:formatMoney(originalPrice))
    end

    if self.downPaymentText then
        self.downPaymentText:setText(g_i18n:formatMoney(self.deal.downPayment))
    end

    if self.amountFinancedText then
        self.amountFinancedText:setText(g_i18n:formatMoney(self.deal.amountFinanced))
    end

    if self.interestRateText then
        self.interestRateText:setText(string.format("%.2f%%", self.deal.interestRate))
    end

    if self.termText then
        local termYears = math.floor(self.deal.termMonths / 12)
        self.termText:setText(string.format(g_i18n:getText("usedplus_fdf_termFormat"), termYears, self.deal.termMonths))
    end

    if self.startDateText then
        -- Format start date (stored as game day number)
        if self.deal.startDate then
            self.startDateText:setText(string.format(g_i18n:getText("usedplus_fdf_dayFormat"), self.deal.startDate))
        end
    end
end

--[[
     Update payment status section (center column)
]]
function FinanceDetailFrame:updatePaymentStatus()
    if self.deal == nil then return end

    -- Current balance
    if self.currentBalanceText then
        self.currentBalanceText:setText(g_i18n:formatMoney(self.deal.currentBalance))
    end

    -- Principal paid (original amount - current balance)
    local principalPaid = self.deal.amountFinanced - self.deal.currentBalance
    if self.principalPaidText then
        self.principalPaidText:setText(g_i18n:formatMoney(principalPaid))
    end

    -- Interest paid
    if self.interestPaidText then
        self.interestPaidText:setText(g_i18n:formatMoney(self.deal.totalInterestPaid))
    end

    -- Remaining principal
    if self.remainingPrincipalText then
        self.remainingPrincipalText:setText(g_i18n:formatMoney(self.deal.currentBalance))
    end

    -- Projected interest (if no prepayment)
    local remainingMonths = self.deal.termMonths - self.deal.monthsPaid
    local projectedInterest = (self.deal.monthlyPayment * remainingMonths) - self.deal.currentBalance
    if self.projectedInterestText then
        self.projectedInterestText:setText(g_i18n:formatMoney(projectedInterest))
    end

    -- Progress bar
    if self.progressBar then
        local progressPercent = 0
        if self.deal.termMonths > 0 then
            progressPercent = (self.deal.monthsPaid / self.deal.termMonths)
        end
        self.progressBar:setValue(progressPercent)
    end
end

--[[
     Update payment options section (right column)
]]
function FinanceDetailFrame:updatePaymentOptions()
    if self.deal == nil then return end

    -- Initialize payment slider
    if self.paymentSlider then
        -- Min: 1 monthly payment, Max: full payoff
        self.paymentSlider:setMinValue(self.deal.monthlyPayment)
        self.paymentSlider:setMaxValue(self.deal.currentBalance)
        self.paymentSlider:setValue(self.deal.monthlyPayment)  -- Default: 1 payment
    end

    -- Update payment preview
    self:updatePaymentPreview()

    -- Show/hide End Lease button
    if self.endLeaseButton then
        local isLease = (self.deal.dealType == 2)
        self.endLeaseButton:setVisible(isLease)
    end
end

--[[
     Update payment preview when slider changes
]]
function FinanceDetailFrame:updatePaymentPreview()
    if self.deal == nil or self.paymentSlider == nil then return end

    local paymentAmount = self.paymentSlider:getValue()

    -- Calculate interest vs principal split
    local monthlyInterest = (self.deal.interestRate / 100 / 12) * self.deal.currentBalance
    local toPrincipal
    local toInterest

    if paymentAmount >= self.deal.currentBalance then
        -- Full payoff
        toPrincipal = self.deal.currentBalance
        toInterest = 0  -- No more interest accrues on payoff
    else
        -- Partial payment
        toInterest = monthlyInterest
        toPrincipal = paymentAmount - monthlyInterest
    end

    local newBalance = self.deal.currentBalance - toPrincipal

    -- Calculate prepayment penalty (if full payoff)
    local prepaymentPenalty = 0
    if paymentAmount >= self.deal.currentBalance then
        if self.deal.calculatePrepaymentPenalty then
            prepaymentPenalty = self.deal:calculatePrepaymentPenalty()
        end
    end

    -- Update displays
    if self.paymentAmountText then
        self.paymentAmountText:setText(g_i18n:formatMoney(paymentAmount))
    end

    if self.paymentTotalText then
        local totalCost = paymentAmount + prepaymentPenalty
        self.paymentTotalText:setText(g_i18n:formatMoney(totalCost))
    end

    if self.toPrincipalText then
        self.toPrincipalText:setText(g_i18n:formatMoney(toPrincipal))
    end

    if self.toInterestText then
        self.toInterestText:setText(g_i18n:formatMoney(toInterest))
    end

    if self.newBalanceText then
        self.newBalanceText:setText(g_i18n:formatMoney(newBalance))
    end

    if self.prepaymentPenaltyText then
        if prepaymentPenalty > 0 then
            self.prepaymentPenaltyText:setText(g_i18n:formatMoney(prepaymentPenalty))
            self.prepaymentPenaltyText:setVisible(true)
        else
            self.prepaymentPenaltyText:setVisible(false)
        end
    end
end

--[[
     Quick-select button callbacks
]]
function FinanceDetailFrame:onButton1Month()
    if self.paymentSlider then
        self.paymentSlider:setValue(self.deal.monthlyPayment)
        self:updatePaymentPreview()
    end
end

function FinanceDetailFrame:onButton6Months()
    if self.paymentSlider and self.deal then
        local amount = math.min(self.deal.monthlyPayment * 6, self.deal.currentBalance)
        self.paymentSlider:setValue(amount)
        self:updatePaymentPreview()
    end
end

function FinanceDetailFrame:onButton1Year()
    if self.paymentSlider and self.deal then
        local amount = math.min(self.deal.monthlyPayment * 12, self.deal.currentBalance)
        self.paymentSlider:setValue(amount)
        self:updatePaymentPreview()
    end
end

function FinanceDetailFrame:onButtonPayoff()
    if self.paymentSlider and self.deal then
        self.paymentSlider:setValue(self.deal.currentBalance)
        self:updatePaymentPreview()
    end
end

--[[
     Slider change callback
]]
function FinanceDetailFrame:onPaymentSliderChanged()
    self:updatePaymentPreview()
end

--[[
     Make Payment button callback (wired to onClick="onClickMakePayment" in XML)
]]
function FinanceDetailFrame:onClickMakePayment()
    if self.deal == nil then return end

    local paymentAmount = self.paymentSlider:getValue()

    -- Validate funds
    local farm = g_farmManager:getFarmById(self.farmId)
    if farm == nil then
        UsedPlus.logError("Farm not found")
        return
    end

    -- Include prepayment penalty in total cost
    local prepaymentPenalty = 0
    if paymentAmount >= self.deal.currentBalance then
        if self.deal.calculatePrepaymentPenalty then
            prepaymentPenalty = self.deal:calculatePrepaymentPenalty()
        end
    end

    local totalCost = paymentAmount + prepaymentPenalty

    if farm.money < totalCost then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_insufficientFunds"), g_i18n:formatMoney(totalCost))
        )
        return
    end

    -- Send payment event to server
    FinancePaymentEvent.sendToServer(self.dealId, paymentAmount, self.farmId)

    -- Close frame
    self:close()

    UsedPlus.logDebug(string.format("Payment submitted: $%.2f for deal %s", paymentAmount, self.dealId))
end

--[[
     End Lease Early button callback (wired to onClick="onClickEndLease" in XML)
]]
function FinanceDetailFrame:onClickEndLease()
    if self.deal == nil or self.deal.dealType ~= 2 then return end

    -- Show confirmation dialog (lease termination is serious)
    -- For now, send event directly
    TerminateLeaseEvent:sendToServer(self.dealId, self.farmId)

    self:close()

    UsedPlus.logDebug(string.format("Lease termination submitted: %s", self.dealId))
end

--[[
     Focus payment section (called from FinanceManagerFrame "Make Payment")
]]
function FinanceDetailFrame:focusPaymentSection()
    -- Scroll to payment section, focus slider
    if self.paymentSlider then
        FocusManager:setFocus(self.paymentSlider)
    end
end

--[[
     Cleanup
]]
function FinanceDetailFrame:onFrameClose()
    self.dealId = nil
    self.deal = nil
    self.farmId = nil

    FinanceDetailFrame:superClass().onFrameClose(self)
end

UsedPlus.logInfo("FinanceDetailFrame loaded")
