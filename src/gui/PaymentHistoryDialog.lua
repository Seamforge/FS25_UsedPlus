--[[
    PaymentHistoryDialog.lua
    Dialog showing full amortization schedule for a finance deal

    Generates payment-by-payment breakdown showing:
    - Payment number
    - Payment amount
    - Principal portion
    - Interest portion
    - Remaining balance
    - Paid/Unpaid status

    Uses standard amortization formula to calculate schedule
]]

PaymentHistoryDialog = {}
-- Use ScreenElement, NOT MessageDialog (MessageDialog lacks registerControls)
local PaymentHistoryDialog_mt = Class(PaymentHistoryDialog, ScreenElement)

PaymentHistoryDialog.MAX_ROWS = 10  -- Rows per page

-- Static instance
PaymentHistoryDialog.instance = nil
PaymentHistoryDialog.xmlPath = nil

--[[
    Get or create dialog instance
]]
function PaymentHistoryDialog.getInstance()
    if PaymentHistoryDialog.instance == nil then
        if PaymentHistoryDialog.xmlPath == nil then
            PaymentHistoryDialog.xmlPath = UsedPlus.MOD_DIR .. "gui/PaymentHistoryDialog.xml"
        end

        PaymentHistoryDialog.instance = PaymentHistoryDialog.new()
        g_gui:loadGui(PaymentHistoryDialog.xmlPath, "PaymentHistoryDialog", PaymentHistoryDialog.instance)
    end

    return PaymentHistoryDialog.instance
end

--[[
    Constructor
]]
function PaymentHistoryDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or PaymentHistoryDialog_mt)

    self.deal = nil
    self.schedule = {}  -- Calculated amortization schedule
    self.currentPage = 1
    self.totalPages = 1
    self.paymentRows = {}
    self.isBackAllowed = true

    return self
end

--[[
    Called when dialog is created
]]
function PaymentHistoryDialog:onCreate()
    UsedPlus.logInfo("PaymentHistoryDialog:onCreate called")

    -- Cache icon paths for status indicators
    self.iconDir = UsedPlus.MOD_DIR .. "gui/icons/"

    -- Cache row elements
    for i = 0, PaymentHistoryDialog.MAX_ROWS - 1 do
        local rowId = "paymentRow" .. i
        self.paymentRows[i] = {
            row = self[rowId],
            bg = self[rowId .. "Bg"],
            num = self[rowId .. "Num"],
            payment = self[rowId .. "Payment"],
            principal = self[rowId .. "Principal"],
            interest = self[rowId .. "Interest"],
            balance = self[rowId .. "Balance"],
            icon = self[rowId .. "Icon"],
            status = self[rowId .. "Status"]
        }

        -- Debug: Check if elements were found
        if self[rowId] == nil then
            UsedPlus.logInfo(string.format("PaymentHistoryDialog:onCreate - row %d NOT FOUND", i))
        end
    end

    UsedPlus.logInfo(string.format("PaymentHistoryDialog:onCreate - cached %d rows", PaymentHistoryDialog.MAX_ROWS))
end

--[[
    Show dialog with deal payment history
    @param deal - FinanceDeal or LeaseDeal object
]]
function PaymentHistoryDialog:show(deal)
    if deal == nil then
        UsedPlus.logError("PaymentHistoryDialog:show called with nil deal")
        return
    end

    self.deal = deal
    self.currentPage = 1

    -- Calculate full amortization schedule
    self:calculateSchedule()

    -- Update display
    self:updateDisplay()

    -- Show dialog
    g_gui:showDialog("PaymentHistoryDialog")
end

--[[
    Calculate full amortization schedule from deal parameters
]]
function PaymentHistoryDialog:calculateSchedule()
    self.schedule = {}

    local deal = self.deal
    if deal == nil then return end

    local principal = deal.amountFinanced or 0
    local monthlyRate = (deal.interestRate or 0) / 12
    local termMonths = deal.termMonths or 0
    local monthlyPayment = deal.monthlyPayment or 0
    local monthsPaid = deal.monthsPaid or 0

    -- Debug: Log the monthsPaid value to understand discrepancy
    UsedPlus.logInfo(string.format("PaymentHistoryDialog:calculateSchedule - monthsPaid=%d, termMonths=%d", monthsPaid, termMonths))

    -- Handle zero interest edge case
    if monthlyRate < 0.0001 then
        monthlyRate = 0
    end

    local balance = principal

    for month = 1, termMonths do
        -- Calculate interest portion
        local interestPortion = balance * monthlyRate

        -- Calculate principal portion
        local principalPortion = monthlyPayment - interestPortion

        -- For final payment, adjust for rounding
        if month == termMonths then
            principalPortion = balance
            -- Recalculate payment for final month
            monthlyPayment = principalPortion + interestPortion
        end

        -- Update balance
        local newBalance = balance - principalPortion
        if newBalance < 0.01 then
            newBalance = 0
        end

        -- Determine status
        local status = "PENDING"
        if month <= monthsPaid then
            status = "PAID"
        elseif month == monthsPaid + 1 then
            status = "DUE"
        end

        -- Add to schedule
        table.insert(self.schedule, {
            month = month,
            payment = monthlyPayment,
            principal = principalPortion,
            interest = interestPortion,
            balance = newBalance,
            status = status
        })

        balance = newBalance
    end

    -- Calculate total pages
    self.totalPages = math.ceil(#self.schedule / PaymentHistoryDialog.MAX_ROWS)
    if self.totalPages < 1 then
        self.totalPages = 1
    end
end

--[[
    Update all display elements
]]
function PaymentHistoryDialog:updateDisplay()
    if self.deal == nil then return end

    local deal = self.deal

    -- Update summary section
    if self.itemNameText then
        self.itemNameText:setText(deal.itemName or g_i18n:getText("usedplus_common_unknown"))
    end

    if self.originalAmountText then
        self.originalAmountText:setText(g_i18n:formatMoney(deal.amountFinanced or 0, 0, true, true))
    end

    if self.interestRateText then
        local rate = (deal.interestRate or 0) * 100
        self.interestRateText:setText(string.format("%.2f%%", rate))
    end

    if self.monthlyPaymentText then
        self.monthlyPaymentText:setText(g_i18n:formatMoney(deal.monthlyPayment or 0, 0, true, true))
    end

    -- Progress
    local monthsPaid = deal.monthsPaid or 0
    local termMonths = deal.termMonths or 0
    local percentComplete = 0
    if termMonths > 0 then
        percentComplete = math.floor((monthsPaid / termMonths) * 100)
    end

    if self.progressText then
        self.progressText:setText(string.format(g_i18n:getText("usedplus_ph_progressFormat"), monthsPaid, termMonths, percentComplete))
    end

    if self.balanceText then
        self.balanceText:setText(g_i18n:formatMoney(deal.currentBalance or 0, 0, true, true))
    end

    -- Update payment rows for current page
    self:updatePaymentRows()

    -- Update pagination
    self:updatePagination()
end

--[[
    Update payment rows for current page
]]
function PaymentHistoryDialog:updatePaymentRows()
    local startIndex = (self.currentPage - 1) * PaymentHistoryDialog.MAX_ROWS + 1
    local endIndex = startIndex + PaymentHistoryDialog.MAX_ROWS - 1

    -- Debug: Check if paymentRows were cached
    local rowCount = 0
    for _ in pairs(self.paymentRows) do rowCount = rowCount + 1 end
    UsedPlus.logInfo(string.format("PaymentHistoryDialog:updatePaymentRows - cached rows: %d", rowCount))

    for i = 0, PaymentHistoryDialog.MAX_ROWS - 1 do
        local scheduleIndex = startIndex + i
        local row = self.paymentRows[i]

        if row and row.row then
            if scheduleIndex <= #self.schedule then
                local entry = self.schedule[scheduleIndex]

                row.row:setVisible(true)

                if row.num then
                    row.num:setText(tostring(entry.month))
                end
                if row.payment then
                    row.payment:setText(g_i18n:formatMoney(entry.payment, 0, true, true))
                end
                if row.principal then
                    row.principal:setText(g_i18n:formatMoney(entry.principal, 0, true, true))
                end
                if row.interest then
                    row.interest:setText(g_i18n:formatMoney(entry.interest, 0, true, true))
                    -- Color interest in orange
                    row.interest:setTextColor(1, 0.6, 0.3, 1)
                end
                if row.balance then
                    row.balance:setText(g_i18n:formatMoney(entry.balance, 0, true, true))
                end
                -- Get status element - try cached first, then direct access
                local statusEl = row.status or self["paymentRow" .. i .. "Status"]
                if statusEl then
                    statusEl:setText(entry.status)
                    -- Debug: Log first few rows' status
                    if i < 3 then
                        UsedPlus.logInfo(string.format("PaymentHistoryDialog - Row %d: month=%d status=%s", i, entry.month, entry.status))
                    end
                    -- Color based on status
                    if entry.status == "PAID" then
                        statusEl:setTextColor(0.3, 1, 0.3, 1)  -- Green
                    elseif entry.status == "DUE" then
                        statusEl:setTextColor(1, 0.9, 0.3, 1)  -- Yellow
                    else
                        statusEl:setTextColor(0.5, 0.5, 0.5, 1)  -- Gray
                    end
                else
                    UsedPlus.logInfo(string.format("PaymentHistoryDialog - Row %d: status element NOT FOUND", i))
                end

                -- Set status icon based on payment status (v2.8.0)
                local iconEl = row.icon or self["paymentRow" .. i .. "Icon"]
                if iconEl and self.iconDir then
                    if entry.status == "PAID" then
                        iconEl:setImageFilename(self.iconDir .. "status_good.dds")
                    elseif entry.status == "DUE" then
                        iconEl:setImageFilename(self.iconDir .. "calendar.dds")
                    else
                        iconEl:setImageFilename(self.iconDir .. "status_pending.dds")
                    end
                end

                -- Highlight current/due payment row
                if row.bg then
                    if entry.status == "DUE" then
                        row.bg:setImageColor(nil, 0.2, 0.2, 0.1, 1)  -- Yellow tint
                    elseif entry.status == "PAID" then
                        row.bg:setImageColor(nil, 0.1, 0.15, 0.1, 1)  -- Slight green tint
                    else
                        -- Alternate gray shades
                        if i % 2 == 0 then
                            row.bg:setImageColor(nil, 0.1, 0.1, 0.1, 1)
                        else
                            row.bg:setImageColor(nil, 0.12, 0.12, 0.12, 1)
                        end
                    end
                end
            else
                row.row:setVisible(false)
            end
        end
    end
end

--[[
    Update pagination controls
]]
function PaymentHistoryDialog:updatePagination()
    local startIndex = (self.currentPage - 1) * PaymentHistoryDialog.MAX_ROWS + 1
    local endIndex = math.min(startIndex + PaymentHistoryDialog.MAX_ROWS - 1, #self.schedule)

    if self.pageInfoText then
        self.pageInfoText:setText(string.format(g_i18n:getText("usedplus_ph_pageInfo"), startIndex, endIndex, #self.schedule))
    end

    if self.prevButton then
        self.prevButton:setDisabled(self.currentPage <= 1)
    end

    if self.nextButton then
        self.nextButton:setDisabled(self.currentPage >= self.totalPages)
    end
end

--[[
    Handle previous page button
]]
function PaymentHistoryDialog:onPrevPage()
    if self.currentPage > 1 then
        self.currentPage = self.currentPage - 1
        self:updatePaymentRows()
        self:updatePagination()
    end
end

--[[
    Handle next page button
]]
function PaymentHistoryDialog:onNextPage()
    if self.currentPage < self.totalPages then
        self.currentPage = self.currentPage + 1
        self:updatePaymentRows()
        self:updatePagination()
    end
end

--[[
    Handle close button
]]
function PaymentHistoryDialog:onCloseDialog()
    g_gui:closeDialogByName("PaymentHistoryDialog")
end

--[[
    Handle ESC key / back button
]]
function PaymentHistoryDialog:onClickBack()
    g_gui:closeDialogByName("PaymentHistoryDialog")
end

--[[
    Handle input events (ESC key for ScreenElement)
]]
function PaymentHistoryDialog:inputEvent(action, value, eventUsed)
    eventUsed = PaymentHistoryDialog:superClass().inputEvent(self, action, value, eventUsed)

    if not eventUsed and action == InputAction.MENU_BACK and value > 0 then
        g_gui:closeDialogByName("PaymentHistoryDialog")
        eventUsed = true
    end

    return eventUsed
end

--[[
    Called when dialog closes
]]
function PaymentHistoryDialog:onClose()
    PaymentHistoryDialog:superClass().onClose(self)

    -- Refresh DealDetailsDialog if it's open (to sync display after time passage)
    if DealDetailsDialog and DealDetailsDialog.instance then
        local dealDialog = DealDetailsDialog.instance
        if dealDialog.deal then
            dealDialog:updateDisplay()
            UsedPlus.logInfo("PaymentHistoryDialog:onClose - refreshed DealDetailsDialog display")
        end
    end

    self.deal = nil
    self.schedule = {}
    self.currentPage = 1
end
