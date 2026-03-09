--[[
    FS25_UsedPlus - Finances Panel Module

    v2.7.2 REFACTORED: Extracted from FinanceManagerFrame.lua

    Handles the Finances section (left column) of the Finance Manager:
    - updateFinancesSection: Display finance deals
    - updateFinanceActionButtons: Enable/disable action buttons
    - selectFinanceRow: Row selection handling
    - showPaymentOptionsDialog: Payment options for deals
    - processPayment/processPayoff: Payment processing
    - ELS/HP/Vanilla loan dialogs: External mod integration
]]

-- Ensure FinanceManagerFrame table exists
FinanceManagerFrame = FinanceManagerFrame or {}

--[[
    Update Finances section (left column) with row-based table display
]]
function FinanceManagerFrame:updateFinancesSection(farmId, farm)
    -- Check if finance system is enabled
    local financeEnabled = true
    if UsedPlusSettings and UsedPlusSettings.get then
        financeEnabled = UsedPlusSettings:get("enableFinanceSystem") ~= false
    end

    -- Hide all rows first
    for i = 0, FinanceManagerFrame.MAX_FINANCE_ROWS - 1 do
        if self.financeRows[i] and self.financeRows[i].row then
            self.financeRows[i].row:setVisible(false)
        end
    end

    -- If system disabled, show message and return
    if not financeEnabled then
        if self.financeEmptyText then
            self.financeEmptyText:setText(g_i18n:getText("usedplus_fmf_financeDisabled") or "Finance system disabled in settings")
            self.financeEmptyText:setVisible(true)
        end
        -- Disable action buttons
        if self.actionButtons then
            for _, btnData in pairs(self.actionButtons) do
                if btnData.btn then
                    btnData.btn:setDisabled(true)
                end
                if btnData.bg then
                    btnData.bg:setImageColor(nil, unpack(btnData.disabledBgColor or {0.15, 0.15, 0.15, 1}))
                end
                if btnData.text then
                    btnData.text:setTextColor(unpack(btnData.disabledTextColor or {0.4, 0.4, 0.4, 1}))
                end
            end
        end
        return
    end

    local totalFinanced = 0
    local totalMonthly = 0
    local totalInterestPaid = 0
    local dealCount = 0

    -- Show empty state initially
    if self.financeEmptyText then
        self.financeEmptyText:setText(g_i18n:getText("usedplus_fmf_noActiveDeals") or "No active deals")
        self.financeEmptyText:setVisible(true)
    end

    -- Store active deals for payment selection
    self.activeDeals = {}

    -- v1.7.3: Calculate UsedPlus loan balances to subtract from farm.loan
    local usedPlusLoanTotal = 0
    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(farmId)
        if deals then
            for _, deal in ipairs(deals) do
                if deal.status == "active" and deal.currentBalance then
                    usedPlusLoanTotal = usedPlusLoanTotal + deal.currentBalance
                end
            end
        end
    end

    -- v1.7.3: Check for vanilla bank loan (farm.loan minus UsedPlus loans)
    local rowIndex = 0
    local vanillaLoanAmount = 0
    if farm and farm.loan then
        vanillaLoanAmount = math.max(0, farm.loan - usedPlusLoanTotal)
    end

    if vanillaLoanAmount > 0 then
        -- Vanilla loan is a REVOLVING CREDIT LINE
        local vanillaInterestRate = 0.04
        local monthlyInterestCost = math.floor(vanillaLoanAmount * vanillaInterestRate / 12)

        -- Get stored payment multiplier for this farm's vanilla loan
        local storedMultiplier = 1.0
        if g_financeManager then
            storedMultiplier = g_financeManager:getVanillaLoanMultiplier(farmId)
        end

        -- Create a pseudo-deal for the credit line display
        local vanillaLoanDeal = {
            id = "VANILLA_LOAN",
            dealType = 0,
            itemName = g_i18n:getText("usedplus_vanillaLoan") or "Bank Credit Line",
            currentBalance = vanillaLoanAmount,
            monthlyPayment = monthlyInterestCost,
            interestRate = vanillaInterestRate,
            termMonths = 0,
            monthsPaid = 0,
            totalInterestPaid = 0,
            status = "active",
            isVanillaLoan = true,
            isCreditLine = true,
            farmId = farmId,
            paymentMultiplier = storedMultiplier,
        }
        table.insert(self.activeDeals, vanillaLoanDeal)

        -- Update row for credit line
        local row = self.financeRows[rowIndex]
        if row then
            if row.row then row.row:setVisible(true) end
            if row.type then row.type:setText(g_i18n:getText("usedplus_fp_creditType")) end
            if row.item then row.item:setText(vanillaLoanDeal.itemName) end
            if row.balance then row.balance:setText(g_i18n:formatMoney(vanillaLoanAmount, 0, true, true)) end
            if row.monthly then
                row.monthly:setText("~" .. g_i18n:formatMoney(monthlyInterestCost, 0, true, true))
                row.monthly:setTextColor(1, 0.6, 0.3, 1)
            end
            if row.progress then row.progress:setText(g_i18n:getText("usedplus_fp_revolving")) end
            if row.remaining then row.remaining:setText(g_i18n:getText("usedplus_fp_open")) end
        end

        totalFinanced = totalFinanced + vanillaLoanAmount
        dealCount = dealCount + 1
        rowIndex = rowIndex + 1
    end

    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(farmId)
        if deals and #deals > 0 then
            for _, deal in ipairs(deals) do
                if deal.status == "active" and rowIndex < FinanceManagerFrame.MAX_FINANCE_ROWS then
                    table.insert(self.activeDeals, deal)

                    -- v2.9.1: Clearer type indicators to distinguish leases from financing
                    local dealType
                    if deal.dealType == DealUtils.TYPE.LEASE then
                        dealType = "V.LEASE"  -- Vehicle Lease
                    elseif deal.dealType == DealUtils.TYPE.LAND_LEASE then
                        dealType = "L.LEASE"  -- Land Lease
                    elseif deal.dealType == 4 then
                        dealType = "LOAN"     -- Cash Loan
                    else
                        dealType = "FINANCE"  -- Vehicle/Equipment/Land Finance
                    end
                    local itemName = deal.itemName or g_i18n:getText("usedplus_common_unknown")

                    if #itemName > 20 then
                        itemName = string.sub(itemName, 1, 18) .. ".."
                    end

                    local currentBalance = deal.currentBalance or 0
                    local monthlyPayment = deal.getConfiguredPayment and deal:getConfiguredPayment() or deal.monthlyPayment or 0
                    local termMonths = deal.termMonths or 0
                    local monthsPaid = deal.monthsPaid or 0
                    local interestPaid = deal.totalInterestPaid or 0

                    totalFinanced = totalFinanced + currentBalance
                    totalMonthly = totalMonthly + monthlyPayment
                    totalInterestPaid = totalInterestPaid + interestPaid
                    dealCount = dealCount + 1

                    local balanceStr = g_i18n:formatMoney(currentBalance, 0, true, true)
                    local monthlyStr = g_i18n:formatMoney(monthlyPayment, 0, true, true)
                    local progressStr = string.format("%d/%d", monthsPaid, termMonths)
                    local remainingMonths = termMonths - monthsPaid
                    local remainingStr = string.format("%dmo", remainingMonths)

                    local row = self.financeRows[rowIndex]
                    if row then
                        if row.row then row.row:setVisible(true) end
                        if row.type then row.type:setText(dealType) end
                        if row.item then row.item:setText(itemName) end
                        if row.balance then row.balance:setText(balanceStr) end
                        if row.monthly then row.monthly:setText(monthlyStr) end
                        if row.progress then row.progress:setText(progressStr) end
                        if row.remaining then row.remaining:setText(remainingStr) end
                    end

                    rowIndex = rowIndex + 1
                end
            end
        end
    end

    -- v1.8.1: Add ELS loans if EnhancedLoanSystem is installed
    -- v2.8.0: Always try to get ELS loans - getELSLoans() handles late-binding detection
    --         This fixes case where ELS loads before our init() but we miss it
    if ModCompatibility.enhancedLoanSystemInstalled or g_els_loanManager ~= nil then
        local elsLoans = ModCompatibility.getELSLoans(farmId)
        UsedPlus.logDebug(string.format("FinancesPanel: ELS check - installed=%s, g_els_loanManager=%s, loans found=%d",
            tostring(ModCompatibility.enhancedLoanSystemInstalled),
            tostring(g_els_loanManager ~= nil),
            #elsLoans))
        for _, pseudoDeal in ipairs(elsLoans) do
            if rowIndex < FinanceManagerFrame.MAX_FINANCE_ROWS then
                table.insert(self.activeDeals, pseudoDeal)

                local dealType = "ELS"
                local itemName = pseudoDeal.itemName or "ELS Loan"
                if #itemName > 20 then
                    itemName = string.sub(itemName, 1, 18) .. ".."
                end

                local currentBalance = pseudoDeal.currentBalance or 0
                local monthlyPayment = pseudoDeal.monthlyPayment or 0
                local termMonths = pseudoDeal.termMonths or 0
                local monthsPaid = pseudoDeal.monthsPaid or 0

                totalFinanced = totalFinanced + currentBalance
                totalMonthly = totalMonthly + monthlyPayment
                dealCount = dealCount + 1

                local balanceStr = g_i18n:formatMoney(currentBalance, 0, true, true)
                local monthlyStr = g_i18n:formatMoney(monthlyPayment, 0, true, true)
                local progressStr = string.format("%d/%d", monthsPaid, termMonths)
                local remainingMonths = math.max(0, termMonths - monthsPaid)
                local remainingStr = string.format("%dmo", remainingMonths)

                local row = self.financeRows[rowIndex]
                if row then
                    if row.row then row.row:setVisible(true) end
                    if row.type then row.type:setText(dealType) end
                    if row.item then row.item:setText(itemName) end
                    if row.balance then row.balance:setText(balanceStr) end
                    if row.monthly then row.monthly:setText(monthlyStr) end
                    if row.progress then row.progress:setText(progressStr) end
                    if row.remaining then row.remaining:setText(remainingStr) end
                end

                rowIndex = rowIndex + 1
            end
        end
    end

    -- v1.8.1: Add HP leases if HirePurchasing is installed
    if ModCompatibility.hirePurchasingInstalled then
        local hpLeases = ModCompatibility.getHPLeases(farmId)
        for _, pseudoDeal in ipairs(hpLeases) do
            if rowIndex < FinanceManagerFrame.MAX_FINANCE_ROWS then
                table.insert(self.activeDeals, pseudoDeal)

                local dealType = "HP"
                local itemName = pseudoDeal.itemName or "HP Lease"
                if #itemName > 20 then
                    itemName = string.sub(itemName, 1, 18) .. ".."
                end

                local currentBalance = pseudoDeal.currentBalance or 0
                local monthlyPayment = pseudoDeal.monthlyPayment or 0
                local termMonths = pseudoDeal.termMonths or 0
                local monthsPaid = pseudoDeal.monthsPaid or 0

                totalFinanced = totalFinanced + currentBalance
                totalMonthly = totalMonthly + monthlyPayment
                dealCount = dealCount + 1

                local balanceStr = g_i18n:formatMoney(currentBalance, 0, true, true)
                local monthlyStr = g_i18n:formatMoney(monthlyPayment, 0, true, true)
                local progressStr = string.format("%d/%d", monthsPaid, termMonths)
                local remainingMonths = math.max(0, termMonths - monthsPaid)
                local remainingStr = string.format("%dmo", remainingMonths)

                local row = self.financeRows[rowIndex]
                if row then
                    if row.row then row.row:setVisible(true) end
                    if row.type then row.type:setText(dealType) end
                    if row.item then row.item:setText(itemName) end
                    if row.balance then row.balance:setText(balanceStr) end
                    if row.monthly then row.monthly:setText(monthlyStr) end
                    if row.progress then row.progress:setText(progressStr) end
                    if row.remaining then row.remaining:setText(remainingStr) end
                end

                rowIndex = rowIndex + 1
            end
        end
    end

    -- Hide empty text if we have ANY rows
    if rowIndex > 0 and self.financeEmptyText then
        self.financeEmptyText:setVisible(false)
    end

    -- v1.8.1: Add Employment wages to monthly obligations
    local employmentWages = ModCompatibility.getEmploymentMonthlyCost(g_currentMission.playerUserId)
    local hasEmployment = employmentWages > 0

    -- Update summary bar
    if self.totalFinancedText then
        self.totalFinancedText:setText(g_i18n:formatMoney(totalFinanced, 0, true, true))
    end
    if self.monthlyTotalText then
        local displayMonthly = totalMonthly + employmentWages
        local monthlyStr = g_i18n:formatMoney(displayMonthly, 0, true, true) .. "/mo"
        if hasEmployment then
            monthlyStr = monthlyStr .. "*"
        end
        self.monthlyTotalText:setText(monthlyStr)
    end
    if self.totalInterestText then
        self.totalInterestText:setText(g_i18n:formatMoney(totalInterestPaid, 0, true, true))
    end
    if self.dealsCountText then
        self.dealsCountText:setText(tostring(dealCount))
    end

    -- Update PAY ALL button state
    if self.payAllBtn then
        local canPayAll = dealCount > 0 and totalMonthly > 0
        self.payAllBtn:setDisabled(not canPayAll)
    end

    -- Reset selection when data changes
    self.selectedFinanceRowIndex = -1
    self.selectedDealId = nil

    -- Update action buttons
    self:updateFinanceActionButtons()
end

--[[
    Update the action buttons based on current selection
]]
function FinanceManagerFrame:updateFinanceActionButtons()
    local hasSelection = self.selectedFinanceRowIndex >= 0 and self.activeDeals and self.activeDeals[self.selectedFinanceRowIndex + 1]
    local hasAnyDeals = self.activeDeals and #self.activeDeals > 0

    self:setActionButtonEnabled("pay", hasSelection)
    self:setActionButtonEnabled("info", hasSelection)
    self:setActionButtonEnabled("payAll", hasAnyDeals)

    if self.selectedDealText then
        if hasSelection then
            local deal = self.activeDeals[self.selectedFinanceRowIndex + 1]
            local itemName = deal.itemName or g_i18n:getText("usedplus_common_unknown")
            if #itemName > 20 then
                itemName = string.sub(itemName, 1, 18) .. ".."
            end
            self.selectedDealText:setText(itemName)
            self.selectedDealText:setVisible(true)
        else
            self.selectedDealText:setText(g_i18n:getText("usedplus_manager_clickToSelect"))
            self.selectedDealText:setVisible(true)
        end
    end
end

--[[
    Set an action button's enabled/disabled state
]]
function FinanceManagerFrame:setActionButtonEnabled(buttonName, enabled)
    local btnData = self.actionButtons and self.actionButtons[buttonName]
    if not btnData then return end

    if btnData.btn then
        btnData.btn:setDisabled(not enabled)
    end

    if btnData.bg then
        if enabled then
            btnData.bg:setImageColor(nil, unpack(btnData.enabledBgColor))
        else
            btnData.bg:setImageColor(nil, unpack(btnData.disabledBgColor))
        end
    end

    if btnData.text then
        if enabled then
            btnData.text:setTextColor(unpack(btnData.enabledTextColor))
        else
            btnData.text:setTextColor(unpack(btnData.disabledTextColor))
        end
    end
end

--[[
    Select a finance row by index and highlight it
]]
function FinanceManagerFrame:selectFinanceRow(rowIndex)
    -- Deselect previous row
    if self.selectedFinanceRowIndex >= 0 then
        local prevRow = self.financeRows[self.selectedFinanceRowIndex]
        if prevRow and prevRow.bg then
            local bgColor = (self.selectedFinanceRowIndex % 2 == 0) and {0.1, 0.1, 0.1, 1} or {0.12, 0.12, 0.12, 1}
            prevRow.bg:setImageColor(nil, unpack(bgColor))
        end
    end

    self.selectedFinanceRowIndex = rowIndex

    if rowIndex >= 0 then
        local newRow = self.financeRows[rowIndex]
        if newRow and newRow.bg then
            newRow.bg:setImageColor(nil, 0.3, 0.25, 0.1, 1)
        end

        if self.activeDeals and self.activeDeals[rowIndex + 1] then
            self.selectedDealId = self.activeDeals[rowIndex + 1].id
        end
    else
        self.selectedDealId = nil
    end

    self:updateFinanceActionButtons()
end

--[[
    PAY button clicked for selected row
]]
function FinanceManagerFrame:onPaySelected()
    if self.selectedFinanceRowIndex < 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_selectDealFirst")
        )
        return
    end

    self:onPayRowClick(self.selectedFinanceRowIndex)
end

--[[
    INFO button clicked for selected row
]]
function FinanceManagerFrame:onInfoSelected()
    if self.selectedFinanceRowIndex < 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_selectDealFirst")
        )
        return
    end

    self:onInfoRowClick(self.selectedFinanceRowIndex)
end

-- Finance row click handlers
function FinanceManagerFrame:onFinanceRowClick0() self:selectFinanceRow(0) end
function FinanceManagerFrame:onFinanceRowClick1() self:selectFinanceRow(1) end
function FinanceManagerFrame:onFinanceRowClick2() self:selectFinanceRow(2) end
function FinanceManagerFrame:onFinanceRowClick3() self:selectFinanceRow(3) end
function FinanceManagerFrame:onFinanceRowClick4() self:selectFinanceRow(4) end
function FinanceManagerFrame:onFinanceRowClick5() self:selectFinanceRow(5) end
function FinanceManagerFrame:onFinanceRowClick6() self:selectFinanceRow(6) end
function FinanceManagerFrame:onFinanceRowClick7() self:selectFinanceRow(7) end
function FinanceManagerFrame:onFinanceRowClick8() self:selectFinanceRow(8) end

-- Finance row hover handlers
function FinanceManagerFrame:onFinanceRowHighlight(element)
    for i = 0, FinanceManagerFrame.MAX_FINANCE_ROWS - 1 do
        local rowData = self.financeRows[i]
        if rowData and rowData.hit == element and rowData.bg then
            local baseColor = (i % 2 == 0) and 0.1 or 0.12
            rowData.bg:setImageColor(nil, baseColor + 0.08, baseColor + 0.08, baseColor + 0.10, 1)
            break
        end
    end
end

function FinanceManagerFrame:onFinanceRowUnhighlight(element)
    for i = 0, FinanceManagerFrame.MAX_FINANCE_ROWS - 1 do
        local rowData = self.financeRows[i]
        if rowData and rowData.hit == element and rowData.bg then
            local baseColor = (i % 2 == 0) and 0.1 or 0.12
            if self.selectedFinanceRowIndex == i then
                rowData.bg:setImageColor(nil, 0.2, 0.3, 0.4, 1)
            else
                rowData.bg:setImageColor(nil, baseColor, baseColor, baseColor, 1)
            end
            break
        end
    end
end

-- Per-row PAY button handlers
function FinanceManagerFrame:onPayRow0() self:onPayRowClick(0) end
function FinanceManagerFrame:onPayRow1() self:onPayRowClick(1) end
function FinanceManagerFrame:onPayRow2() self:onPayRowClick(2) end
function FinanceManagerFrame:onPayRow3() self:onPayRowClick(3) end
function FinanceManagerFrame:onPayRow4() self:onPayRowClick(4) end
function FinanceManagerFrame:onPayRow5() self:onPayRowClick(5) end
function FinanceManagerFrame:onPayRow6() self:onPayRowClick(6) end
function FinanceManagerFrame:onPayRow7() self:onPayRowClick(7) end
function FinanceManagerFrame:onPayRow8() self:onPayRowClick(8) end
function FinanceManagerFrame:onPayRow9() self:onPayRowClick(9) end

-- Per-row INFO button handlers
function FinanceManagerFrame:onInfoRow0() self:onInfoRowClick(0) end
function FinanceManagerFrame:onInfoRow1() self:onInfoRowClick(1) end
function FinanceManagerFrame:onInfoRow2() self:onInfoRowClick(2) end
function FinanceManagerFrame:onInfoRow3() self:onInfoRowClick(3) end
function FinanceManagerFrame:onInfoRow4() self:onInfoRowClick(4) end
function FinanceManagerFrame:onInfoRow5() self:onInfoRowClick(5) end
function FinanceManagerFrame:onInfoRow6() self:onInfoRowClick(6) end
function FinanceManagerFrame:onInfoRow7() self:onInfoRowClick(7) end
function FinanceManagerFrame:onInfoRow8() self:onInfoRowClick(8) end

--[[
    Handle INFO button click for a specific row
]]
function FinanceManagerFrame:onInfoRowClick(rowIndex)
    if not self.activeDeals or rowIndex >= #self.activeDeals then
        return
    end

    local deal = self.activeDeals[rowIndex + 1]
    if not deal then
        return
    end

    if DealDetailsDialog then
        DialogLoader.show("DealDetailsDialog", "show", deal, function()
            self:updateDisplay()
        end)
    end
end

--[[
    Handle PAY button click for a specific row
]]
function FinanceManagerFrame:onPayRowClick(rowIndex)
    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if not farm then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_farmNotFound")
        )
        return
    end

    if not self.activeDeals or rowIndex >= #self.activeDeals then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noDealInRow")
        )
        return
    end

    local deal = self.activeDeals[rowIndex + 1]
    if not deal then
        return
    end

    self:showPaymentOptionsDialog(deal, farm)
end

--[[
    Show payment options dialog
]]
function FinanceManagerFrame:showPaymentOptionsDialog(deal, farm)
    local currentBalance = deal.currentBalance or 0
    local monthlyPayment = deal.monthlyPayment or 0
    local itemName = deal.itemName or g_i18n:getText("usedplus_common_unknown")
    local farmMoney = farm.money or 0

    -- v1.8.1: Handle ELS loans
    if deal.isELSLoan then
        self:showELSPaymentDialog(deal, farm)
        return
    end

    -- v1.8.1: Handle HP leases
    if deal.isHPLease then
        self:showHPPaymentDialog(deal, farm)
        return
    end

    -- v2.1.1: Handle vanilla bank loans
    if deal.isVanillaLoan then
        self:showVanillaLoanPaymentDialog(deal, farm)
        return
    end

    local isVehicleLease = (deal.dealType == 2)
    local isLandLease = (deal.dealType == 3)

    local payoffPenalty = currentBalance * 0.05
    local totalPayoff = currentBalance + payoffPenalty

    local terminationFee = 0
    if isVehicleLease and deal.calculateTerminationFee then
        terminationFee = deal:calculateTerminationFee()
    elseif isVehicleLease then
        local remainingMonths = (deal.termMonths or 0) - (deal.monthsPaid or 0)
        local remainingPayments = monthlyPayment * remainingMonths
        local residualValue = deal.residualValue or 0
        terminationFee = (remainingPayments + residualValue) * 0.50
    end

    local buyoutPrice = 0
    if isLandLease and deal.calculateBuyoutPrice then
        buyoutPrice = deal:calculateBuyoutPrice()
    elseif isLandLease then
        buyoutPrice = deal.baseBuyoutPrice or deal.landPrice or 0
    end

    local balanceStr = g_i18n:formatMoney(currentBalance, 0, true, true)
    local monthlyStr = g_i18n:formatMoney(monthlyPayment, 0, true, true)
    local moneyStr = g_i18n:formatMoney(farmMoney, 0, true, true)

    local canPayMonthly = farmMoney >= monthlyPayment
    local canPayFull = farmMoney >= totalPayoff

    -- Store deal reference for callback
    self.pendingPaymentDeal = deal
    self.pendingPayoffAmount = totalPayoff
    self.pendingMonthlyAmount = monthlyPayment
    self.pendingTerminationFee = terminationFee
    self.pendingBuyoutPrice = buyoutPrice

    local message
    if isVehicleLease then
        -- Vehicle lease buyout calculation
        local baseCost = deal.baseCost or 0
        local residualValue = deal.residualValue or 0
        local totalDepreciation = baseCost - residualValue
        local monthsPaid = deal.monthsPaid or 0
        local termMonths = deal.termMonths or 12

        local equityAccumulated = 0
        if FinanceCalculations and FinanceCalculations.calculateLeaseEquity then
            equityAccumulated = FinanceCalculations.calculateLeaseEquity(monthlyPayment, monthsPaid, totalDepreciation, termMonths)
        else
            local progressPercent = monthsPaid / termMonths
            equityAccumulated = totalDepreciation * progressPercent
        end

        local vehicleBuyoutPrice = math.max(0, residualValue - equityAccumulated)
        local securityDeposit = deal.securityDeposit or 0
        local netBuyoutCost = vehicleBuyoutPrice - securityDeposit

        self.pendingVehicleBuyoutPrice = vehicleBuyoutPrice
        self.pendingVehicleEquity = equityAccumulated
        self.pendingVehicleDepositRefund = securityDeposit

        local equityStr = g_i18n:formatMoney(equityAccumulated, 0, true, true)
        local vehicleBuyoutStr = g_i18n:formatMoney(vehicleBuyoutPrice, 0, true, true)

        message = string.format(
            "%s (LEASE)\n\nRemaining: %s\nMonthly: %s\nEquity: %s\nBuyout: %s\nYour Money: %s",
            itemName, balanceStr, monthlyStr, equityStr, vehicleBuyoutStr, moneyStr
        )

        if canPayMonthly then
            YesNoDialog.show(
                function(yes)
                    if yes then
                        self:onPayMonthlyConfirm()
                    end
                end,
                nil,
                message .. "\n\nMake monthly lease payment?",
                "Lease Payment"
            )
        end
    elseif isLandLease then
        local remainingMonths = (deal.termMonths or 0) - (deal.monthsPaid or 0)
        local buyoutStr = g_i18n:formatMoney(buyoutPrice, 0, true, true)
        message = string.format(
            "%s (LAND LEASE)\n\nRemaining: %d months\nMonthly: %s\nBuyout: %s\nYour Money: %s",
            itemName, remainingMonths, monthlyStr, buyoutStr, moneyStr
        )

        if canPayMonthly then
            YesNoDialog.show(
                function(yes)
                    if yes then
                        self:onPayMonthlyConfirm()
                    end
                end,
                nil,
                message .. "\n\nMake monthly land lease payment?",
                "Land Lease Payment"
            )
        else
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_INFO,
                g_i18n:getText("usedplus_error_noPaymentOptions")
            )
        end
    else
        -- Finance deal
        message = string.format(
            "%s\n\nBalance: %s\nMonthly: %s\nYour Money: %s",
            itemName, balanceStr, monthlyStr, moneyStr
        )

        if canPayMonthly then
            YesNoDialog.show(
                function(yes)
                    if yes then
                        self:processPayment(deal, monthlyPayment)
                    end
                end,
                nil,
                message .. "\n\nMake early monthly payment?",
                "Early Payment"
            )
        else
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_INFO,
                string.format(g_i18n:getText("usedplus_error_insufficientFundsPayment"), monthlyStr)
            )
        end
    end
end

-- Payment callbacks
function FinanceManagerFrame:onPayMonthlyConfirm()
    if self.pendingPaymentDeal and self.pendingMonthlyAmount then
        self:processPayment(self.pendingPaymentDeal, self.pendingMonthlyAmount)
    end
    self.pendingPaymentDeal = nil
    self.pendingPayoffAmount = nil
    self.pendingMonthlyAmount = nil
end

function FinanceManagerFrame:onPayoffConfirm()
    if self.pendingPaymentDeal and self.pendingPayoffAmount then
        self:processPayoff(self.pendingPaymentDeal, self.pendingPayoffAmount)
    end
    self.pendingPaymentDeal = nil
    self.pendingPayoffAmount = nil
    self.pendingMonthlyAmount = nil
    self.pendingTerminationFee = nil
end

function FinanceManagerFrame:onTerminateLeaseConfirm()
    if self.pendingPaymentDeal then
        local deal = self.pendingPaymentDeal
        local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)

        if not farm then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                g_i18n:getText("usedplus_error_farmNotFound")
            )
            return
        end

        local terminationFee = self.pendingTerminationFee or 0
        local itemName = deal.itemName or g_i18n:getText("usedplus_common_unknown")

        YesNoDialog.show(
            function(yes)
                if yes then
                    if TerminateLeaseEvent then
                        TerminateLeaseEvent.sendToServer(deal.id, farm.farmId)
                    end
                    self:updateDisplay()
                end
            end,
            nil,
            string.format(
                "Are you sure you want to terminate the lease for %s?\n\n" ..
                "Termination Fee: %s\n\n" ..
                "The vehicle will be returned to the dealer.",
                itemName, g_i18n:formatMoney(terminationFee, 0, true, true)
            ),
            "Confirm Lease Termination"
        )
    end

    self.pendingPaymentDeal = nil
    self.pendingPayoffAmount = nil
    self.pendingMonthlyAmount = nil
    self.pendingTerminationFee = nil
end

function FinanceManagerFrame:onVehicleLeaseBuyoutConfirm()
    if self.pendingPaymentDeal then
        local deal = self.pendingPaymentDeal
        local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)

        if not farm then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                g_i18n:getText("usedplus_error_farmNotFound")
            )
            return
        end

        local buyoutPrice = self.pendingVehicleBuyoutPrice or 0
        local equityApplied = self.pendingVehicleEquity or 0
        local depositRefund = self.pendingVehicleDepositRefund or 0
        local vehicleName = deal.vehicleName or deal.itemName or g_i18n:getText("usedplus_common_unknownVehicle")
        local netCost = buyoutPrice - depositRefund

        local confirmMessage = string.format(
            "Buy out your lease for %s?\n\n" ..
            "Buyout Price: %s\n" ..
            "Equity Applied: -%s\n" ..
            "Net Cost: %s\n\n" ..
            "The vehicle will become fully yours.",
            vehicleName,
            g_i18n:formatMoney(deal.residualValue or 0, 0, true, true),
            g_i18n:formatMoney(equityApplied, 0, true, true),
            g_i18n:formatMoney(netCost, 0, true, true)
        )

        YesNoDialog.show(
            function(yes)
                if yes then
                    if LeaseRenewalEvent then
                        LeaseRenewalEvent.sendToServer(deal.id, LeaseRenewalEvent.ACTION_BUYOUT, {
                            buyoutPrice = buyoutPrice,
                            equityApplied = equityApplied,
                            depositRefund = depositRefund
                        })
                        g_currentMission:addIngameNotification(
                            FSBaseMission.INGAME_NOTIFICATION_OK,
                            string.format(g_i18n:getText("usedplus_notify_vehicleNowYours"), vehicleName)
                        )
                    end
                    self:updateDisplay()
                end
            end,
            nil,
            confirmMessage,
            "Confirm Vehicle Buyout"
        )
    end

    self.pendingPaymentDeal = nil
    self.pendingPayoffAmount = nil
    self.pendingMonthlyAmount = nil
    self.pendingTerminationFee = nil
    self.pendingVehicleBuyoutPrice = nil
    self.pendingVehicleEquity = nil
    self.pendingVehicleDepositRefund = nil
end

function FinanceManagerFrame:onLandLeaseBuyoutConfirm()
    if self.pendingPaymentDeal then
        local deal = self.pendingPaymentDeal
        local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)

        if not farm then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                g_i18n:getText("usedplus_error_farmNotFound")
            )
            return
        end

        local buyoutPrice = self.pendingBuyoutPrice or 0
        if buyoutPrice <= 0 and deal.calculateBuyoutPrice then
            buyoutPrice = deal:calculateBuyoutPrice()
        end
        local landName = deal.landName or deal.itemName or g_i18n:getText("usedplus_common_unknownLand")

        YesNoDialog.show(
            function(yes)
                if yes then
                    if LandLeaseBuyoutEvent then
                        LandLeaseBuyoutEvent.sendToServer(deal.id)
                    end
                    self:updateDisplay()
                end
            end,
            nil,
            string.format(
                "Are you sure you want to buy out the lease for %s?\n\n" ..
                "Buyout Price: %s",
                landName, g_i18n:formatMoney(buyoutPrice, 0, true, true)
            ),
            "Confirm Land Buyout"
        )
    end

    self.pendingPaymentDeal = nil
    self.pendingPayoffAmount = nil
    self.pendingMonthlyAmount = nil
    self.pendingTerminationFee = nil
    self.pendingBuyoutPrice = nil
end

function FinanceManagerFrame:onLandLeaseTerminateConfirm()
    if self.pendingPaymentDeal then
        local deal = self.pendingPaymentDeal
        local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)

        if not farm then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                g_i18n:getText("usedplus_error_farmNotFound")
            )
            return
        end

        local landName = deal.landName or deal.itemName or g_i18n:getText("usedplus_common_unknownLand")
        local monthsPaid = deal.monthsPaid or 0
        local monthlyPayment = deal.monthlyPayment or 0
        local totalPaid = monthsPaid * monthlyPayment

        YesNoDialog.show(
            function(yes)
                if yes then
                    if TerminateLeaseEvent then
                        TerminateLeaseEvent.sendToServer(deal.id, farm.farmId)
                        g_currentMission:addIngameNotification(
                            FSBaseMission.INGAME_NOTIFICATION_INFO,
                            string.format(g_i18n:getText("usedplus_notify_landLeaseTerminated"), landName)
                        )
                    end
                    self:updateDisplay()
                end
            end,
            nil,
            string.format(
                "WARNING: Terminate lease for %s?\n\n" ..
                "- Land will revert to NPC ownership\n" ..
                "- All %d payments (%s) will be lost\n\n" ..
                "Are you sure?",
                landName, monthsPaid, g_i18n:formatMoney(totalPaid, 0, true, true)
            ),
            "Terminate Land Lease"
        )
    end

    self.pendingPaymentDeal = nil
    self.pendingPayoffAmount = nil
    self.pendingMonthlyAmount = nil
    self.pendingTerminationFee = nil
    self.pendingBuyoutPrice = nil
end

--[[
    Process a full payoff
]]
function FinanceManagerFrame:processPayoff(deal, amount)
    if not deal or not amount or amount <= 0 then
        return
    end

    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if not farm then
        return
    end

    if farm.money < amount then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_insufficientFundsPayoff")
        )
        return
    end

    if FinancePaymentEvent and FinancePaymentEvent.sendPayoffToServer then
        FinancePaymentEvent.sendPayoffToServer(deal.id, amount, farm.farmId)
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notify_loanPaidOff"), g_i18n:formatMoney(amount, 0, true, true))
        )
    elseif FinancePaymentEvent then
        local event = FinancePaymentEvent.new(deal.id, amount, farm.farmId, true)
        event:sendToServer(deal.id, amount, farm.farmId, true)
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notify_loanPaidOff"), g_i18n:formatMoney(amount, 0, true, true))
        )
    else
        if g_financeManager then
            if g_financeManager.payoffDeal then
                local success = g_financeManager:payoffDeal(deal.id, amount, farm.farmId)
                if success then
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_OK,
                        string.format(g_i18n:getText("usedplus_notify_loanPaidOff"), g_i18n:formatMoney(amount, 0, true, true))
                    )
                end
            elseif g_financeManager.makePayment then
                local success = g_financeManager:makePayment(deal.id, amount, farm.farmId)
                if success then
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_OK,
                        string.format(g_i18n:getText("usedplus_notify_loanPaidOff"), g_i18n:formatMoney(amount, 0, true, true))
                    )
                end
            end
        end
    end

    self:updateDisplay()
end

--[[
    Process an early payment
]]
function FinanceManagerFrame:processPayment(deal, amount)
    if not deal or not amount or amount <= 0 then
        return
    end

    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if not farm then
        return
    end

    if farm.money < amount then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_insufficientFundsForPayment")
        )
        return
    end

    if FinancePaymentEvent then
        local event = FinancePaymentEvent.new(deal.id, amount, farm.farmId)
        event:sendToServer(deal.id, amount, farm.farmId)

        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notify_paymentProcessed"), g_i18n:formatMoney(amount, 0, true, true))
        )
    else
        if g_financeManager and g_financeManager.makePayment then
            local success = g_financeManager:makePayment(deal.id, amount, farm.farmId)
            if success then
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_OK,
                    string.format(g_i18n:getText("usedplus_notify_paymentProcessed"), g_i18n:formatMoney(amount, 0, true, true))
                )
            end
        end
    end

    self:updateDisplay()
end

--[[
    ELS Payment Dialog
]]
function FinanceManagerFrame:showELSPaymentDialog(pseudoDeal, farm)
    local currentBalance = pseudoDeal.currentBalance or 0
    local monthlyPayment = pseudoDeal.monthlyPayment or 0
    local itemName = pseudoDeal.itemName or "ELS Loan"
    local farmMoney = farm.money or 0
    local interestRate = (pseudoDeal.interestRate or 0) * 100

    local balanceStr = g_i18n:formatMoney(currentBalance, 0, true, true)
    local monthlyStr = g_i18n:formatMoney(monthlyPayment, 0, true, true)
    local moneyStr = g_i18n:formatMoney(farmMoney, 0, true, true)
    local rateStr = string.format("%.2f%%", interestRate)

    local canPayMonthly = farmMoney >= monthlyPayment and monthlyPayment > 0

    local message = string.format(
        "%s\n\nBalance: %s\nMonthly: %s\nInterest Rate: %s\nYour Money: %s\n\n(Managed by EnhancedLoanSystem)",
        itemName, balanceStr, monthlyStr, rateStr, moneyStr
    )

    self.pendingELSDeal = pseudoDeal
    self.pendingELSMonthlyAmount = monthlyPayment

    if canPayMonthly then
        YesNoDialog.show(
            function(yes)
                if yes then
                    self:onELSPaymentConfirm()
                end
            end,
            nil,
            message .. "\n\nMake monthly payment of " .. monthlyStr .. "?",
            "ELS Loan Payment"
        )
    else
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_insufficientFundsELS")
        )
    end
end

function FinanceManagerFrame:onELSPaymentConfirm()
    if self.pendingELSDeal and self.pendingELSMonthlyAmount then
        local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
        if farm and farm.money >= self.pendingELSMonthlyAmount then
            local success = ModCompatibility.payELSLoan(self.pendingELSDeal, self.pendingELSMonthlyAmount)
            if success then
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_OK,
                    string.format(g_i18n:getText("usedplus_notification_elsPaymentProcessed"), g_i18n:formatMoney(self.pendingELSMonthlyAmount, 0, true, true))
                )
            end
        end
    end
    self.pendingELSDeal = nil
    self.pendingELSMonthlyAmount = nil
    self:updateDisplay()
end

function FinanceManagerFrame:onELSPayoffConfirm()
    if self.pendingELSDeal then
        local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
        local amount = self.pendingELSDeal.currentBalance or 0
        if farm and farm.money >= amount then
            local success = ModCompatibility.payELSLoan(self.pendingELSDeal, amount)
            if success then
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_OK,
                    string.format(g_i18n:getText("usedplus_notification_elsPaidOff"), g_i18n:formatMoney(amount, 0, true, true))
                )
            end
        end
    end
    self.pendingELSDeal = nil
    self.pendingELSMonthlyAmount = nil
    self:updateDisplay()
end

--[[
    HP Payment Dialog
]]
function FinanceManagerFrame:showHPPaymentDialog(pseudoDeal, farm)
    local currentBalance = pseudoDeal.currentBalance or 0
    local monthlyPayment = pseudoDeal.monthlyPayment or 0
    local itemName = pseudoDeal.itemName or "HP Lease"
    local farmMoney = farm.money or 0
    local termMonths = pseudoDeal.termMonths or 0
    local monthsPaid = pseudoDeal.monthsPaid or 0
    local remainingMonths = math.max(0, termMonths - monthsPaid)

    local balanceStr = g_i18n:formatMoney(currentBalance, 0, true, true)
    local monthlyStr = g_i18n:formatMoney(monthlyPayment, 0, true, true)
    local moneyStr = g_i18n:formatMoney(farmMoney, 0, true, true)

    local message = string.format(
        "%s\n\nRemaining Balance: %s\nMonthly Payment: %s\nRemaining: %d months\nYour Money: %s\n\n(Managed by HirePurchasing)",
        itemName, balanceStr, monthlyStr, remainingMonths, moneyStr
    )

    self.pendingHPDeal = pseudoDeal
    self.pendingHPMonthlyAmount = monthlyPayment

    InfoDialog.show(
        message .. "\n\nNote: HirePurchasing manages payments automatically each hour.",
        "HP Lease Info"
    )
end

function FinanceManagerFrame:onHPPaymentConfirm()
    if self.pendingHPDeal and self.pendingHPMonthlyAmount then
        local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
        if farm and farm.money >= self.pendingHPMonthlyAmount then
            local success = ModCompatibility.payHPLease(self.pendingHPDeal, self.pendingHPMonthlyAmount)
            if success then
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_OK,
                    string.format(g_i18n:getText("usedplus_notification_hpPaymentProcessed"), g_i18n:formatMoney(self.pendingHPMonthlyAmount, 0, true, true))
                )
            end
        end
    end
    self.pendingHPDeal = nil
    self.pendingHPMonthlyAmount = nil
    self:updateDisplay()
end

function FinanceManagerFrame:onHPSettleConfirm()
    if self.pendingHPDeal then
        local success = ModCompatibility.settleHPLease(self.pendingHPDeal)
        if success then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_OK,
                g_i18n:getText("usedplus_notification_hpSettled")
            )
        end
    end
    self.pendingHPDeal = nil
    self.pendingHPMonthlyAmount = nil
    self:updateDisplay()
end

--[[
    Vanilla Loan Payment Dialog
]]
function FinanceManagerFrame:showVanillaLoanPaymentDialog(deal, farm)
    local currentBalance = deal.currentBalance or 0
    local farmMoney = farm.money or 0
    local itemName = deal.itemName or "Bank Credit Line"

    local balanceStr = g_i18n:formatMoney(currentBalance, 0, true, true)
    local moneyStr = g_i18n:formatMoney(farmMoney, 0, true, true)

    local monthlyInterest = math.floor(currentBalance * 0.10 / 12)
    local interestStr = g_i18n:formatMoney(monthlyInterest, 0, true, true)

    local paymentOptions = {}
    local optionAmounts = {10000, 25000, 50000, 100000, 250000}

    for _, amount in ipairs(optionAmounts) do
        if amount <= farmMoney and amount <= currentBalance then
            table.insert(paymentOptions, amount)
        end
    end

    local canPayFull = farmMoney >= currentBalance

    local message = string.format(
        "%s\n\nBalance Owed: %s\nMonthly Interest: ~%s\nYour Money: %s\n\nHow much to pay down?",
        itemName, balanceStr, interestStr, moneyStr
    )

    self.pendingVanillaLoan = deal
    self.pendingVanillaFarm = farm

    if #paymentOptions == 0 and not canPayFull then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format(g_i18n:getText("usedplus_error_insufficientFundsMinPayment"),
                g_i18n:formatMoney(math.min(10000, currentBalance), 0, true, true),
                moneyStr)
        )
        return
    end

    local optionLabels = {}
    local optionValues = {}

    for _, amount in ipairs(paymentOptions) do
        local amountStr = g_i18n:formatMoney(amount, 0, true, true)
        local newBalance = currentBalance - amount
        local newBalanceStr = g_i18n:formatMoney(newBalance, 0, true, true)
        table.insert(optionLabels, string.format("Pay %s (Balance: %s)", amountStr, newBalanceStr))
        table.insert(optionValues, amount)
    end

    if canPayFull then
        local alreadyHasFullPayoff = false
        for _, amount in ipairs(paymentOptions) do
            if amount >= currentBalance then
                alreadyHasFullPayoff = true
                break
            end
        end
        if not alreadyHasFullPayoff then
            local payoffStr = g_i18n:formatMoney(currentBalance, 0, true, true)
            table.insert(optionLabels, string.format("Clear Full Balance (%s)", payoffStr))
            table.insert(optionValues, currentBalance)
        end
    end

    self.pendingVanillaPaymentOptions = optionValues

    if #optionLabels > 0 then
        OptionDialog.show(
            function(selectedIndex)
                if selectedIndex > 0 and selectedIndex <= #self.pendingVanillaPaymentOptions then
                    local selectedAmount = self.pendingVanillaPaymentOptions[selectedIndex]
                    self:processVanillaLoanPayment(selectedAmount)
                end
                self.pendingVanillaPaymentOptions = nil
            end,
            message,
            "Credit Line Payment",
            optionLabels
        )
    else
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noPaymentOptions")
        )
    end
end

function FinanceManagerFrame:processVanillaLoanPayment(amount)
    if not amount or amount <= 0 then
        return
    end

    local farm = self.pendingVanillaFarm or g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if not farm then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_farmNotFound")
        )
        return
    end

    -- Client-side validation for immediate feedback
    if farm.money < amount then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_insufficientFundsForPayment")
        )
        return
    end

    local currentLoan = farm.loan or 0
    if currentLoan <= 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noVanillaLoanBalance")
        )
        return
    end

    local actualPayment = math.min(amount, currentLoan)

    -- v2.8.0: Use network event for multiplayer synchronization
    -- The server will validate funds, process payment, update farm.loan, and show notification
    VanillaLoanPaymentEvent.sendToServer(farm.farmId, actualPayment)

    -- Clear pending state
    self.pendingVanillaLoan = nil
    self.pendingVanillaFarm = nil
    self.pendingVanillaPaymentAmount = nil
    self.pendingVanillaPaymentOptions = nil

    -- Update display (values will sync from server in multiplayer)
    self:updateDisplay()
end

--[[
    PAY ALL functionality
]]
function FinanceManagerFrame:onPayAll()
    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if not farm then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_farmNotFound")
        )
        return
    end

    if not self.activeDeals or #self.activeDeals == 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noDealsToPayAll")
        )
        return
    end

    local totalPayment = 0
    local payableDeals = {}

    for _, deal in ipairs(self.activeDeals) do
        if deal.status == "active" then
            local monthlyPayment = deal.getConfiguredPayment and deal:getConfiguredPayment() or deal.monthlyPayment or 0
            if monthlyPayment > 0 then
                totalPayment = totalPayment + monthlyPayment
                table.insert(payableDeals, {deal = deal, amount = monthlyPayment})
            end
        end
    end

    if totalPayment <= 0 or #payableDeals == 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noPaymentsDue")
        )
        return
    end

    local farmMoney = farm.money or 0
    if totalPayment > farmMoney then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_insufficientFundsNeedHave"),
                g_i18n:formatMoney(totalPayment, 0, true, true),
                g_i18n:formatMoney(farmMoney, 0, true, true))
        )
        return
    end

    self.bulkPaymentData = {
        deals = payableDeals,
        totalAmount = totalPayment,
        farm = farm
    }

    local message = string.format(
        "Pay all %d finance deals?\n\nTotal: %s\nBalance after: %s",
        #payableDeals,
        g_i18n:formatMoney(totalPayment, 0, true, true),
        g_i18n:formatMoney(farmMoney - totalPayment, 0, true, true)
    )

    YesNoDialog.show(
        function(yes)
            self:onBulkPaymentConfirm(yes)
        end,
        nil,
        message,
        "Bulk Payment"
    )
end

function FinanceManagerFrame:onBulkPaymentConfirm(yes)
    if not yes or not self.bulkPaymentData then
        self.bulkPaymentData = nil
        return
    end

    local data = self.bulkPaymentData
    local successCount = 0
    local failCount = 0

    for _, paymentInfo in ipairs(data.deals) do
        local deal = paymentInfo.deal
        local amount = paymentInfo.amount

        if FinancePaymentEvent then
            local event = FinancePaymentEvent.new(deal.id, amount, data.farm.farmId)
            event:sendToServer(deal.id, amount, data.farm.farmId)
            successCount = successCount + 1
        else
            failCount = failCount + 1
        end
    end

    if failCount == 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notify_paidDealsTotal"),
                successCount,
                g_i18n:formatMoney(data.totalAmount, 0, true, true))
        )
    else
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_notify_paidDealsSomeFailed"), successCount, failCount)
        )
    end

    self.bulkPaymentData = nil
    self:updateDisplay()
end

UsedPlus.logDebug("FinancesPanel module loaded")
