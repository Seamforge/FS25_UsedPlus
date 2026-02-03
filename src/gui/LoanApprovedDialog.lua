--[[
    FS25_UsedPlus - Loan Approved Confirmation Dialog

    Styled dialog showing loan terms after approval.
    Replaces the plain InfoDialog with a proper formatted display.
]]

LoanApprovedDialog = {}
local LoanApprovedDialog_mt = Class(LoanApprovedDialog, MessageDialog)

-- Singleton instance
LoanApprovedDialog.instance = nil

--[[
    Constructor
]]
function LoanApprovedDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or LoanApprovedDialog_mt)

    self.loanDetails = nil

    return self
end

--[[
    Get or create the singleton instance
]]
function LoanApprovedDialog.getInstance()
    if LoanApprovedDialog.instance == nil then
        -- Load the dialog XML - use UsedPlus.MOD_DIR which persists after mod load
        local xmlPath = UsedPlus.MOD_DIR .. "gui/LoanApprovedDialog.xml"

        LoanApprovedDialog.instance = LoanApprovedDialog.new()
        g_gui:loadGui(xmlPath, "LoanApprovedDialog", LoanApprovedDialog.instance, true)

        UsedPlus.logDebug("LoanApprovedDialog loaded from: " .. xmlPath)
    end

    return LoanApprovedDialog.instance
end

--[[
    Show the dialog with loan details
    @param details - Table with loan details
]]
function LoanApprovedDialog.show(details)
    DialogLoader.show("LoanApprovedDialog", "setLoanDetails", details)
end

--[[
    Called when dialog is created - binds XML element IDs
]]
function LoanApprovedDialog:onCreate()
    LoanApprovedDialog:superClass().onCreate(self)

    -- Store icon directory for later use
    self.iconDir = UsedPlus.MOD_DIR .. "gui/icons/"
end

--[[
    Setup header icon - must be called after elements are bound
]]
function LoanApprovedDialog:setupHeaderIcon()
    -- Get the header icon element
    local headerIcon = self.dialogElement:getDescendantById("headerIcon")
    if headerIcon ~= nil then
        headerIcon:setImageFilename(self.iconDir .. "status_good.png")
    end
end

--[[
    Set the loan details to display
]]
function LoanApprovedDialog:setLoanDetails(details)
    self.loanDetails = details
end

--[[
    Called when dialog opens
]]
function LoanApprovedDialog:onOpen()
    LoanApprovedDialog:superClass().onOpen(self)

    -- Setup header icon (green checkmark for success)
    self:setupHeaderIcon()

    UsedPlus.logDebug("LoanApprovedDialog:onOpen called, loanDetails=" .. tostring(self.loanDetails ~= nil))

    if self.loanDetails then
        self:updateDisplay()
    else
        UsedPlus.logDebug("LoanApprovedDialog:onOpen - NO loan details to display!")
    end
end

--[[
    Update all display elements with loan details
]]
function LoanApprovedDialog:updateDisplay()
    local d = self.loanDetails
    if not d then return end

    UsedPlus.logDebug("LoanApprovedDialog:updateDisplay - amount=" .. tostring(d.amount))
    UsedPlus.logDebug("  Elements: amountText=" .. tostring(self.amountText ~= nil) ..
                      ", termText=" .. tostring(self.termText ~= nil) ..
                      ", rateText=" .. tostring(self.rateText ~= nil))

    -- Amount deposited
    if self.amountText then
        self.amountText:setText(g_i18n:formatMoney(d.amount, 0, true, true))
    end

    -- Loan terms
    if self.termText then
        self.termText:setText(string.format("%d years", d.termYears))
    end

    if self.rateText then
        self.rateText:setText(string.format("%.2f%%", d.interestRate * 100))
    end

    -- Payment schedule
    if self.monthlyText then
        self.monthlyText:setText(g_i18n:formatMoney(d.monthlyPayment, 0, true, true))
    end

    if self.yearlyText then
        self.yearlyText:setText(g_i18n:formatMoney(d.yearlyPayment, 0, true, true))
    end

    if self.interestText then
        self.interestText:setText(g_i18n:formatMoney(d.totalInterest, 0, true, true))
    end

    -- Credit impact
    if self.prevScoreText then
        self.prevScoreText:setText(string.format("%d (%s)", d.previousScore, d.previousRating))
    end

    if self.newScoreText then
        local scoreText = string.format("%d (%s)", d.newScore, d.newRating)
        self.newScoreText:setText(scoreText)

        -- Color based on change
        if d.newScore < d.previousScore then
            self.newScoreText:setTextColor(1, 0.5, 0.4, 1)  -- Red for decrease
        elseif d.newScore > d.previousScore then
            self.newScoreText:setTextColor(0.4, 1, 0.5, 1)  -- Green for increase
        else
            self.newScoreText:setTextColor(0.5, 0.8, 1, 1)  -- Blue for no change
        end
    end

    -- Collateral warning
    if self.collateralText then
        if d.collateralCount and d.collateralCount > 0 then
            self.collateralText:setText(string.format(
                "%d asset(s) pledged as collateral. Miss 3 payments = repossession!",
                d.collateralCount
            ))
            self.collateralText:setVisible(true)
        else
            self.collateralText:setVisible(false)
        end
    end
end

--[[
    OK button clicked
]]
function LoanApprovedDialog:onClickOk()
    self:close()
end

--[[
    Clean up on close
]]
function LoanApprovedDialog:onClose()
    LoanApprovedDialog:superClass().onClose(self)
    self.loanDetails = nil
end

UsedPlus.logInfo("LoanApprovedDialog loaded")
