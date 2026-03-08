--[[
    FS25_UsedPlus - Credit Report Dialog
    Official credit report styled dialog showing:
    - Credit score with factors breakdown
    - Account history (open and closed)
    - Payment performance metrics
    - Score trend over time

    Styled to look like an official credit bureau report
]]

CreditReportDialog = {}
local CreditReportDialog_mt = Class(CreditReportDialog, MessageDialog)

-- Month name abbreviations for date display
CreditReportDialog.MONTH_NAMES = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
}

--[[
     Constructor
]]
function CreditReportDialog.new(target, custom_mt, i18n)
    local self = MessageDialog.new(target, custom_mt or CreditReportDialog_mt)
    self.i18n = i18n or g_i18n
    return self
end

--[[
    Format date as "Mon YY" (e.g., "Jan 01")
    Uses currentPeriod (1-12) and currentYear
]]
function CreditReportDialog:formatDate()
    local env = g_currentMission.environment
    local period = env.currentPeriod or 1
    local year = env.currentYear or 1

    -- Clamp period to valid range
    period = math.max(1, math.min(12, period))

    local monthName = CreditReportDialog.MONTH_NAMES[period] or "Jan"
    local yearStr = string.format("%02d", year % 100)  -- Last 2 digits

    return monthName .. " " .. yearStr
end

--[[
    v2.0.0: Helper function to check if credit system is enabled
]]
function CreditReportDialog.isCreditSystemEnabled()
    if UsedPlusSettings and UsedPlusSettings.get then
        return UsedPlusSettings:get("enableCreditSystem") ~= false
    end
    return true  -- Default to enabled
end

--[[
    v2.9.5: Initialize icon paths on dialog creation
]]
function CreditReportDialog:onCreate()
    CreditReportDialog:superClass().onCreate(self)

    -- Store icon directory for icons
    self.iconDir = UsedPlus.MOD_DIR .. "gui/icons/"

    -- v2.8.0: Initialize smoothed credit score for jitter reduction
    self.smoothedCreditScore = nil
end

--[[
    v2.9.5: Setup section header icons
    Icons are set via Lua because XML paths don't work from ZIP mods
]]
function CreditReportDialog:setupSectionIcons()
    if self.iconDir == nil then
        return
    end

    -- Credit Score section - gold star
    if self.scoreHeaderIcon ~= nil then
        self.scoreHeaderIcon:setImageFilename(self.iconDir .. "credit_score.dds")
    end

    -- Factors section - percentage
    if self.factorsHeaderIcon ~= nil then
        self.factorsHeaderIcon:setImageFilename(self.iconDir .. "percentage.dds")
    end

    -- Tips section - lightbulb
    if self.tipsHeaderIcon ~= nil then
        self.tipsHeaderIcon:setImageFilename(self.iconDir .. "lightbulb.dds")
    end

    -- Account Summary section - finance
    if self.accountHeaderIcon ~= nil then
        self.accountHeaderIcon:setImageFilename(self.iconDir .. "finance.dds")
    end

    -- Payment History section - calendar
    if self.paymentHeaderIcon ~= nil then
        self.paymentHeaderIcon:setImageFilename(self.iconDir .. "calendar.dds")
    end
end

--[[
    Bind all GUI elements by ID
    Called once when dialog first opens to cache element references
]]
function CreditReportDialog:bindElements()
    if self.elementsBound then
        return  -- Already bound
    end

    -- Helper to safely get element by ID
    local function getElement(id)
        local element = self:getDescendantById(id)
        if not element then
            UsedPlus.logDebug("CreditReportDialog: Element not found: " .. id)
        end
        return element
    end

    -- Header elements
    self.farmNameText = getElement("farmNameText")
    self.reportDateText = getElement("reportDateText")

    -- v2.9.5: Trend icon element
    self.trendIcon = getElement("trendIcon")

    -- v2.9.5: Section header icons
    self.scoreHeaderIcon = getElement("scoreHeaderIcon")
    self.factorsHeaderIcon = getElement("factorsHeaderIcon")
    self.tipsHeaderIcon = getElement("tipsHeaderIcon")
    self.accountHeaderIcon = getElement("accountHeaderIcon")
    self.paymentHeaderIcon = getElement("paymentHeaderIcon")

    -- Containers for visibility toggle
    self.creditContentContainer = getElement("creditContentContainer")
    self.disabledMessageContainer = getElement("disabledMessageContainer")

    -- Credit Score section
    self.scoreValueText = getElement("scoreValueText")
    self.ratingText = getElement("ratingText")
    self.scoreRangeText = getElement("scoreRangeText")
    self.interestImpactText = getElement("interestImpactText")
    self.scoreTrendText = getElement("scoreTrendText")

    -- Factors section
    self.factorPaymentText = getElement("factorPaymentText")
    self.factorUtilizationText = getElement("factorUtilizationText")
    self.factorAgeText = getElement("factorAgeText")
    self.factorMixText = getElement("factorMixText")
    self.factorInquiriesText = getElement("factorInquiriesText")

    -- Account Summary section
    self.openAccountsText = getElement("openAccountsText")
    self.closedAccountsText = getElement("closedAccountsText")
    self.totalBalanceText = getElement("totalBalanceText")
    self.netWorthText = getElement("netWorthText")

    -- Active Accounts section
    self.accountLine1Text = getElement("accountLine1Text")
    self.accountLine2Text = getElement("accountLine2Text")
    self.accountLine3Text = getElement("accountLine3Text")

    -- Payment History section
    self.onTimePaymentsText = getElement("onTimePaymentsText")
    self.missedPaymentsText = getElement("missedPaymentsText")
    self.currentStreakText = getElement("currentStreakText")
    self.longestStreakText = getElement("longestStreakText")

    -- Histogram section
    self.histogramText = getElement("histogramText")
    self.histogramLegendText = getElement("histogramLegendText")

    -- Tips section
    self.tipText1 = getElement("tipText1")
    self.tipText2 = getElement("tipText2")
    self.tipText3 = getElement("tipText3")

    self.elementsBound = true
    UsedPlus.logDebug("CreditReportDialog: Elements bound successfully")
end

--[[
     Called when dialog opens
]]
function CreditReportDialog:onOpen()
    CreditReportDialog:superClass().onOpen(self)

    -- Bind elements on first open
    self:bindElements()

    -- v2.9.5: Setup section header icons (after elements are bound)
    self:setupSectionIcons()

    -- v2.0.0: Check if credit system is enabled
    local creditEnabled = CreditReportDialog.isCreditSystemEnabled()

    -- Toggle visibility between credit content and disabled message
    if self.creditContentContainer then
        self.creditContentContainer:setVisible(creditEnabled)
    end
    if self.disabledMessageContainer then
        self.disabledMessageContainer:setVisible(not creditEnabled)
    end

    -- If disabled, no need to update report content
    if not creditEnabled then
        return
    end

    -- Get current farm
    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if farm then
        self.farmId = farm.farmId
        self.farm = farm
    end

    self:updateReport()
end

--[[
     Update all report sections
]]
function CreditReportDialog:updateReport()
    if not self.farmId or not self.farm then
        return
    end

    self:updateHeader()
    self:updateScoreSection()
    self:updateFactorsSection()
    self:updateAccountsSection()
    self:updateActiveAccountsSection()
    self:updatePaymentHistorySection()
    self:updateTipsSection()
end

--[[
     Update report header with farm name and date
]]
function CreditReportDialog:updateHeader()
    -- Farm name
    if self.farmNameText then
        local farmName = self.farm.name or g_i18n:getText("usedplus_common_unknownFarm")
        self.farmNameText:setText(farmName)
    end

    -- Report date (current in-game date) - Format: "Report Date: Mon YY"
    if self.reportDateText then
        local dateStr = self:formatDate()
        self.reportDateText:setText(g_i18n:getText("usedplus_cr_reportDate") .. dateStr)
    end
end

--[[
     Update credit score section with large score display
]]
function CreditReportDialog:updateScoreSection()
    local score = 650
    local rating = "Fair"
    local interestAdj = 0

    if CreditScore then
        local rawScore = CreditScore.calculate(self.farmId)

        -- v2.8.0: Apply smoothing to reduce score jitter (EMA factor 0.15 = very smooth)
        self.smoothedCreditScore = Smoothing.emaInt(rawScore, self.smoothedCreditScore or rawScore, 0.15)
        score = self.smoothedCreditScore

        rating = CreditScore.getRating(score)
        interestAdj = CreditScore.getInterestAdjustment(score)
    end

    -- Large score display
    if self.scoreValueText then
        self.scoreValueText:setText(tostring(score))
        -- Color based on score
        local color = UIHelper.Credit.getScoreColor(score)
        self.scoreValueText:setTextColor(unpack(color))
    end

    -- Rating text
    if self.ratingText then
        self.ratingText:setText(rating)
    end

    -- Score range indicator (300-850)
    if self.scoreRangeText then
        self.scoreRangeText:setText(g_i18n:getText("usedplus_cr_scoreRange"))
    end

    -- Interest rate impact
    if self.interestImpactText then
        local impactStr
        if interestAdj < 0 then
            impactStr = string.format(g_i18n:getText("usedplus_cr_discountRates"), -interestAdj)
        elseif interestAdj > 0 then
            impactStr = string.format(g_i18n:getText("usedplus_cr_penaltyRates"), interestAdj)
        else
            impactStr = g_i18n:getText("usedplus_cr_standardRates")
        end
        self.interestImpactText:setText(impactStr)
    end

    -- Score trend
    self:updateScoreTrend()
end

--[[
     Update score trend based on PaymentTracker history
     v2.9.5: Uses icon-based trend indicators instead of Unicode arrows
]]
function CreditReportDialog:updateScoreTrend()
    if not self.scoreTrendText then
        return
    end

    local trendText = g_i18n:getText("usedplus_cr_noHistory")
    local trendColor = {0.6, 0.6, 0.6, 1}
    local trendIconFile = "trend_flat.dds"  -- Default icon

    if PaymentTracker then
        local stats = PaymentTracker.getStats(self.farmId)
        if stats and stats.totalPayments and stats.totalPayments > 0 then
            -- Calculate on-time rate from stats
            local onTimeRate = stats.onTimePayments / stats.totalPayments
            local streak = stats.currentStreak or 0

            if streak >= 6 and onTimeRate >= 0.95 then
                trendText = g_i18n:getText("usedplus_cr_trendExcellent")
                trendColor = {0.2, 0.9, 0.3, 1}
                trendIconFile = "trend_up.dds"
            elseif streak >= 3 and onTimeRate >= 0.85 then
                trendText = g_i18n:getText("usedplus_cr_trendGood")
                trendColor = {0.5, 0.9, 0.4, 1}
                trendIconFile = "trend_up.dds"
            elseif onTimeRate >= 0.70 then
                trendText = g_i18n:getText("usedplus_cr_trendStable")
                trendColor = {0.8, 0.8, 0.4, 1}
                trendIconFile = "trend_flat.dds"
            elseif onTimeRate >= 0.50 then
                trendText = g_i18n:getText("usedplus_cr_trendDeclining")
                trendColor = {1, 0.6, 0.3, 1}
                trendIconFile = "trend_down.dds"
            else
                trendText = g_i18n:getText("usedplus_cr_trendPoor")
                trendColor = {1, 0.3, 0.3, 1}
                trendIconFile = "trend_down.dds"
            end
        end
    end

    -- Update text
    self.scoreTrendText:setText(trendText)
    self.scoreTrendText:setTextColor(unpack(trendColor))

    -- v2.9.5: Update trend icon
    if self.trendIcon ~= nil and self.iconDir ~= nil then
        self.trendIcon:setImageFilename(self.iconDir .. trendIconFile)
        self.trendIcon:setVisible(true)
    end
end

--[[
     Update score factors section showing what affects the score
]]
function CreditReportDialog:updateFactorsSection()
    if not PaymentTracker then
        return
    end

    local stats = PaymentTracker.getStats(self.farmId)
    if not stats then
        return
    end

    -- Payment History factor (most important - 35%)
    if self.factorPaymentText then
        local paymentScore = g_i18n:getText("usedplus_cr_noPaymentHistory")
        local paymentColor = {0.6, 0.6, 0.6, 1}

        if stats.totalPayments and stats.totalPayments > 0 then
            local rate = stats.onTimePayments / stats.totalPayments
            local pct = math.floor(rate * 100)
            if rate >= 0.95 then
                paymentScore = string.format(g_i18n:getText("usedplus_cr_factorExcellent"), pct)
                paymentColor = {0.2, 0.9, 0.3, 1}
            elseif rate >= 0.85 then
                paymentScore = string.format(g_i18n:getText("usedplus_cr_factorGood"), pct)
                paymentColor = {0.5, 0.9, 0.4, 1}
            elseif rate >= 0.70 then
                paymentScore = string.format(g_i18n:getText("usedplus_cr_factorFair"), pct)
                paymentColor = {0.8, 0.8, 0.4, 1}
            else
                paymentScore = string.format(g_i18n:getText("usedplus_cr_factorPoor"), pct)
                paymentColor = {1, 0.4, 0.3, 1}
            end
        end

        self.factorPaymentText:setText(paymentScore)
        self.factorPaymentText:setTextColor(unpack(paymentColor))
    end

    -- Credit Utilization factor (30%)
    if self.factorUtilizationText and CreditScore then
        local assets = CreditScore.calculateAssets(self.farm)
        local debt = CreditScore.calculateDebt(self.farm)
        local ratio = assets > 0 and (debt / assets) or 0

        local utilScore = "N/A"
        local utilColor = {0.6, 0.6, 0.6, 1}

        if assets > 0 then
            if ratio <= 0.30 then
                utilScore = string.format(g_i18n:getText("usedplus_cr_utilExcellent"), ratio * 100)
                utilColor = {0.2, 0.9, 0.3, 1}
            elseif ratio <= 0.50 then
                utilScore = string.format(g_i18n:getText("usedplus_cr_utilGood"), ratio * 100)
                utilColor = {0.5, 0.9, 0.4, 1}
            elseif ratio <= 0.70 then
                utilScore = string.format(g_i18n:getText("usedplus_cr_utilFair"), ratio * 100)
                utilColor = {0.8, 0.8, 0.4, 1}
            else
                utilScore = string.format(g_i18n:getText("usedplus_cr_utilHigh"), ratio * 100)
                utilColor = {1, 0.4, 0.3, 1}
            end
        end

        self.factorUtilizationText:setText(utilScore)
        self.factorUtilizationText:setTextColor(unpack(utilColor))
    end

    -- Account Age factor (15%)
    if self.factorAgeText then
        local totalPayments = stats.totalPayments or 0
        local ageScore = g_i18n:getText("usedplus_cr_ageNew")
        local ageColor = {0.6, 0.6, 0.6, 1}

        if totalPayments >= 24 then
            ageScore = string.format(g_i18n:getText("usedplus_cr_ageEstablished"), totalPayments)
            ageColor = {0.2, 0.9, 0.3, 1}
        elseif totalPayments >= 12 then
            ageScore = string.format(g_i18n:getText("usedplus_cr_ageBuilding"), totalPayments)
            ageColor = {0.5, 0.9, 0.4, 1}
        elseif totalPayments >= 6 then
            ageScore = string.format(g_i18n:getText("usedplus_cr_ageGrowing"), totalPayments)
            ageColor = {0.8, 0.8, 0.4, 1}
        elseif totalPayments > 0 then
            ageScore = string.format(g_i18n:getText("usedplus_cr_ageNewCount"), totalPayments)
            ageColor = {0.7, 0.7, 0.7, 1}
        end

        self.factorAgeText:setText(ageScore)
        self.factorAgeText:setTextColor(unpack(ageColor))
    end
end

--[[
     Update accounts section showing open and closed accounts
     Includes UsedPlus deals + vanilla bank loan in outstanding balance
]]
function CreditReportDialog:updateAccountsSection()
    local openCount = 0
    local closedCount = 0
    local totalBalance = 0

    -- Include vanilla bank loan in total balance
    local vanillaLoan = self.farm.loan or 0
    if vanillaLoan > 0 then
        openCount = openCount + 1  -- Count vanilla loan as an open account
        totalBalance = totalBalance + vanillaLoan
    end

    -- Add UsedPlus finance deals
    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(self.farmId)
        if deals then
            for _, deal in ipairs(deals) do
                if deal.status == "active" then
                    openCount = openCount + 1
                    totalBalance = totalBalance + (deal.currentBalance or 0)
                elseif deal.status == "completed" or deal.status == "paid_off" then
                    closedCount = closedCount + 1
                end
            end
        end
    end

    -- Open accounts
    if self.openAccountsText then
        self.openAccountsText:setText(tostring(openCount))
    end

    -- Closed accounts (good standing)
    if self.closedAccountsText then
        self.closedAccountsText:setText(tostring(closedCount))
    end

    -- Total outstanding balance (includes vanilla loan)
    if self.totalBalanceText then
        self.totalBalanceText:setText(g_i18n:formatMoney(totalBalance, 0, true, true))
    end

    -- Net worth section (NEW)
    self:updateNetWorthSection()
end

--[[
    Update net worth section showing total assets
    Assets = farmland value + vehicle value
]]
function CreditReportDialog:updateNetWorthSection()
    local totalAssets = 0
    local farmlandValue = 0
    local vehicleValue = 0

    UsedPlus.logDebug("CreditReportDialog: Calculating net worth for farmId=" .. tostring(self.farmId))

    -- Calculate farmland value
    if g_farmlandManager then
        local farmlands = g_farmlandManager:getOwnedFarmlandIdsByFarmId(self.farmId)
        if farmlands then
            UsedPlus.logDebug("CreditReportDialog: Found " .. #farmlands .. " farmlands")
            for _, farmlandId in ipairs(farmlands) do
                local farmland = g_farmlandManager:getFarmlandById(farmlandId)
                if farmland then
                    farmlandValue = farmlandValue + (farmland.price or 0)
                end
            end
        else
            UsedPlus.logDebug("CreditReportDialog: No farmlands found")
        end
    end

    -- Calculate vehicle value
    if g_currentMission.vehicles then
        local vehicleCount = 0
        for _, vehicle in ipairs(g_currentMission.vehicles) do
            if vehicle.ownerFarmId == self.farmId then
                -- Use getSellPrice if available, otherwise estimate from storeItem
                local value = 0
                if vehicle.getSellPrice then
                    value = vehicle:getSellPrice()
                elseif vehicle.storeItem then
                    value = vehicle.storeItem.price or 0
                end
                vehicleValue = vehicleValue + value
                vehicleCount = vehicleCount + 1
            end
        end
        UsedPlus.logDebug("CreditReportDialog: Found " .. vehicleCount .. " vehicles worth " .. vehicleValue)
    end

    totalAssets = farmlandValue + vehicleValue
    UsedPlus.logDebug("CreditReportDialog: Net worth = " .. totalAssets .. " (land=" .. farmlandValue .. ", vehicles=" .. vehicleValue .. ")")

    -- Update net worth display
    if self.netWorthText then
        self.netWorthText:setText(g_i18n:formatMoney(totalAssets, 0, true, true))
        UsedPlus.logDebug("CreditReportDialog: Set netWorthText to " .. g_i18n:formatMoney(totalAssets, 0, true, true))
    else
        UsedPlus.logDebug("CreditReportDialog: WARNING - netWorthText element is nil!")
    end

    -- Update individual components if elements exist
    if self.farmlandValueText then
        self.farmlandValueText:setText(g_i18n:formatMoney(farmlandValue, 0, true, true))
    end
    if self.vehicleValueText then
        self.vehicleValueText:setText(g_i18n:formatMoney(vehicleValue, 0, true, true))
    end
end

--[[
     Update active accounts detail section
     Shows up to 3 most recent active accounts with start dates
     Includes vanilla bank loan if present
]]
function CreditReportDialog:updateActiveAccountsSection()
    local accounts = {}

    -- Include vanilla bank loan if it exists
    local vanillaLoan = self.farm.loan or 0
    if vanillaLoan > 0 then
        table.insert(accounts, {
            name = g_i18n:getText("usedplus_cr_bankCreditLine"),
            typeLabel = g_i18n:getText("usedplus_cr_bankLoan"),
            startDate = g_i18n:getText("usedplus_cr_statusActive"),
            balance = vanillaLoan,
            createdYear = 9999,  -- Sort to top as "most important"
            createdMonth = 1
        })
    end

    -- Collect all active accounts from finance manager
    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(self.farmId)
        if deals then
            for _, deal in ipairs(deals) do
                if deal.status == "active" then
                    -- Determine deal type label
                    local typeLabel = g_i18n:getText("usedplus_cr_typeLoan")
                    if deal.dealType == DealUtils.TYPE.LEASE then
                        typeLabel = g_i18n:getText("usedplus_cr_typeLease")
                    elseif deal.dealType == DealUtils.TYPE.FINANCE then
                        typeLabel = g_i18n:getText("usedplus_cr_typeFinance")
                    elseif deal.dealType == DealUtils.TYPE.LOAN then
                        typeLabel = g_i18n:getText("usedplus_cr_typeCashLoan")
                    end

                    -- Get item name (truncate if too long)
                    local itemName = deal.itemName or deal.vehicleName or g_i18n:getText("usedplus_common_unknown")
                    if #itemName > 18 then
                        itemName = itemName:sub(1, 15) .. "..."
                    end

                    -- Format start date using month names
                    local month = deal.createdMonth or 1
                    local year = deal.createdYear or 1
                    month = math.max(1, math.min(12, month))
                    local monthName = CreditReportDialog.MONTH_NAMES[month] or "Jan"
                    local startDate = string.format("%s %02d", monthName, year % 100)

                    -- Format balance
                    local balance = deal.currentBalance or 0

                    table.insert(accounts, {
                        name = itemName,
                        typeLabel = typeLabel,
                        startDate = startDate,
                        balance = balance,
                        createdYear = year,
                        createdMonth = month
                    })
                end
            end
        end
    end

    -- Sort by most recent first (newest first)
    table.sort(accounts, function(a, b)
        if a.createdYear ~= b.createdYear then
            return a.createdYear > b.createdYear
        end
        return a.createdMonth > b.createdMonth
    end)

    -- Populate account detail lines (up to 3)
    local accountLines = {self.accountLine1Text, self.accountLine2Text, self.accountLine3Text}

    for i, lineElement in ipairs(accountLines) do
        if lineElement then
            local account = accounts[i]
            if account then
                -- Format: "Item Name (Type) - MM/YYYY - $X"
                local lineText = string.format("%s (%s) - %s - %s",
                    account.name,
                    account.typeLabel,
                    account.startDate,
                    g_i18n:formatMoney(account.balance, 0, true, true))
                lineElement:setText(lineText)
                lineElement:setVisible(true)
            else
                lineElement:setText(g_i18n:getText("usedplus_cr_noActiveAccounts"))
                lineElement:setVisible(i == 1 and #accounts == 0)  -- Only show "No accounts" on first line
            end
        end
    end
end

--[[
     Update payment history section with stats
]]
function CreditReportDialog:updatePaymentHistorySection()
    UsedPlus.logDebug("CreditReportDialog: Updating payment history section")

    if not PaymentTracker then
        UsedPlus.logDebug("CreditReportDialog: PaymentTracker not available")
        return
    end

    local stats = PaymentTracker.getStats(self.farmId)
    UsedPlus.logDebug("CreditReportDialog: PaymentTracker stats = " .. tostring(stats ~= nil))

    if not stats then
        UsedPlus.logDebug("CreditReportDialog: No stats, setting defaults")
        -- No history yet
        if self.onTimePaymentsText then
            self.onTimePaymentsText:setText("0")
        else
            UsedPlus.logDebug("CreditReportDialog: WARNING - onTimePaymentsText is nil")
        end
        if self.missedPaymentsText then
            self.missedPaymentsText:setText("0")
        else
            UsedPlus.logDebug("CreditReportDialog: WARNING - missedPaymentsText is nil")
        end
        if self.currentStreakText then
            self.currentStreakText:setText(g_i18n:getText("usedplus_cr_notAvailable"))
        end
        if self.longestStreakText then
            self.longestStreakText:setText(g_i18n:getText("usedplus_cr_notAvailable"))
        end
        return
    end

    UsedPlus.logDebug("CreditReportDialog: Stats - onTime=" .. tostring(stats.onTimePayments) ..
        ", missed=" .. tostring(stats.missedPayments) ..
        ", total=" .. tostring(stats.totalPayments) ..
        ", streak=" .. tostring(stats.currentStreak))

    -- On-time payments
    if self.onTimePaymentsText then
        self.onTimePaymentsText:setText(tostring(stats.onTimePayments or 0))
        self.onTimePaymentsText:setTextColor(0.3, 0.9, 0.3, 1)
    else
        UsedPlus.logDebug("CreditReportDialog: WARNING - onTimePaymentsText is nil")
    end

    -- Missed payments
    if self.missedPaymentsText then
        local missed = stats.missedPayments or 0
        self.missedPaymentsText:setText(tostring(missed))
        if missed > 0 then
            self.missedPaymentsText:setTextColor(1, 0.4, 0.3, 1)
        else
            self.missedPaymentsText:setTextColor(0.3, 0.9, 0.3, 1)
        end
    end

    -- Current streak
    if self.currentStreakText then
        local streak = stats.currentStreak or 0
        local streakText = streak > 0 and (streak .. " months") or "N/A"
        self.currentStreakText:setText(streakText)
        if streak >= 6 then
            self.currentStreakText:setTextColor(0.3, 0.9, 0.3, 1)
        elseif streak >= 3 then
            self.currentStreakText:setTextColor(0.7, 0.9, 0.3, 1)
        else
            self.currentStreakText:setTextColor(0.7, 0.7, 0.7, 1)
        end
    end

    -- Longest streak
    if self.longestStreakText then
        local longest = stats.longestStreak or 0
        local longestText = longest > 0 and (longest .. " months") or "N/A"
        self.longestStreakText:setText(longestText)
    end

    -- Payment histogram (simplified - show last 12 months as text)
    self:updatePaymentHistogram(stats)
end

--[[
     Update payment histogram display
     Shows a visual representation of payment breakdown using ASCII bar chart
]]
function CreditReportDialog:updatePaymentHistogram(stats)
    UsedPlus.logDebug("CreditReportDialog: Updating payment histogram")

    if not self.histogramText then
        UsedPlus.logDebug("CreditReportDialog: WARNING - histogramText is nil!")
        return
    end

    local total = stats.totalPayments or 0
    local onTime = stats.onTimePayments or 0
    local missed = stats.missedPayments or 0
    local late = stats.latePayments or 0

    UsedPlus.logDebug("CreditReportDialog: Histogram data - total=" .. total .. ", onTime=" .. onTime .. ", missed=" .. missed .. ", late=" .. late)

    if total == 0 then
        self.histogramText:setText(g_i18n:getText("usedplus_cr_noPaymentHistory"))
        if self.histogramLegendText then
            self.histogramLegendText:setText(g_i18n:getText("usedplus_cr_makePayments"))
        end
        UsedPlus.logDebug("CreditReportDialog: No payment history to display")
        return
    end

    -- Calculate percentages
    local onTimePercent = math.floor((onTime / total) * 100 + 0.5)
    local missedPercent = math.floor((missed / total) * 100 + 0.5)
    local latePercent = 100 - onTimePercent - missedPercent

    -- Build ASCII progress bar (20 chars wide)
    local barLength = 20
    local onTimeChars = math.floor((onTime / total) * barLength + 0.5)
    local missedChars = math.floor((missed / total) * barLength + 0.5)
    local lateChars = barLength - onTimeChars - missedChars

    -- Ensure minimums for non-zero values
    if onTime > 0 and onTimeChars == 0 then onTimeChars = 1 end
    if missed > 0 and missedChars == 0 then missedChars = 1 end
    if late > 0 and lateChars == 0 then lateChars = 1 end

    -- Build bar using ASCII: + = on-time, - = late, X = missed
    local bar = "[" ..
        string.rep("+", onTimeChars) ..
        string.rep("-", lateChars) ..
        string.rep("X", missedChars) ..
    "]"

    -- Summary text with the bar
    local summaryText = string.format(g_i18n:getText("usedplus_cr_histogramFormat"), bar, onTimePercent)
    self.histogramText:setText(summaryText)
    UsedPlus.logDebug("CreditReportDialog: Histogram bar = '" .. summaryText .. "'")

    -- Legend showing counts
    if self.histogramLegendText then
        local legendParts = {}
        if onTime > 0 then
            table.insert(legendParts, string.format(g_i18n:getText("usedplus_cr_legendOnTime"), onTime))
        end
        if late > 0 then
            table.insert(legendParts, string.format(g_i18n:getText("usedplus_cr_legendLate"), late))
        end
        if missed > 0 then
            table.insert(legendParts, string.format(g_i18n:getText("usedplus_cr_legendMissed"), missed))
        end
        self.histogramLegendText:setText(table.concat(legendParts, "  "))
    end
end

--[[
    Update tips section with context-sensitive credit improvement advice
    Tips are prioritized based on what will most improve the player's score
]]
function CreditReportDialog:updateTipsSection()
    local tips = {}

    -- Gather current credit status
    local score = 650
    local rating = "Fair"
    local assets = 0
    local debt = 0
    local debtRatio = 0
    local paymentStats = nil
    local openAccounts = 0
    local missedPayments = 0

    if CreditScore then
        score = CreditScore.calculate(self.farmId)
        rating = CreditScore.getRating(score)
        assets = CreditScore.calculateAssets(self.farm)
        debt = CreditScore.calculateDebt(self.farm)
        if assets > 0 then
            debtRatio = debt / assets
        end
    end

    if PaymentTracker then
        paymentStats = PaymentTracker.getStats(self.farmId)
        if paymentStats then
            missedPayments = paymentStats.missedPayments or 0
        end
    end

    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(self.farmId)
        if deals then
            for _, deal in ipairs(deals) do
                if deal.status == "active" then
                    openAccounts = openAccounts + 1
                end
            end
        end
    end

    -- Priority 1: Address missed payments (biggest impact)
    if missedPayments > 0 then
        table.insert(tips, g_i18n:getText("usedplus_cr_tipMissedPayments"))
    end

    -- Priority 2: High debt utilization
    if debtRatio > 0.70 then
        table.insert(tips, g_i18n:getText("usedplus_cr_tipHighDebt"))
    elseif debtRatio > 0.50 then
        table.insert(tips, g_i18n:getText("usedplus_cr_tipDebtRatio"))
    end

    -- Based on score level
    if score < 600 then
        -- Very Poor score tips
        table.insert(tips, g_i18n:getText("usedplus_cr_tipStartSmall"))
        if missedPayments == 0 then
            table.insert(tips, g_i18n:getText("usedplus_cr_tipOnTime6Months"))
        end
    elseif score < 650 then
        -- Poor score tips
        table.insert(tips, g_i18n:getText("usedplus_cr_tipConsistency"))
        if openAccounts == 0 then
            table.insert(tips, g_i18n:getText("usedplus_cr_tipOpenDeal"))
        end
    elseif score < 700 then
        -- Fair score tips
        if paymentStats and paymentStats.currentStreak and paymentStats.currentStreak < 6 then
            table.insert(tips, g_i18n:getText("usedplus_cr_tipStreak"))
        end
        table.insert(tips, g_i18n:getText("usedplus_cr_tipMixAccounts"))
    elseif score < 750 then
        -- Good score tips
        table.insert(tips, g_i18n:getText("usedplus_cr_tipGoodProgress"))
        if debtRatio > 0.30 then
            table.insert(tips, g_i18n:getText("usedplus_cr_tipDebt30"))
        end
    else
        -- Excellent score tips
        table.insert(tips, g_i18n:getText("usedplus_cr_tipExcellent"))
        table.insert(tips, g_i18n:getText("usedplus_cr_tipRefinance"))
    end

    -- Account age tip for new players
    if paymentStats == nil or (paymentStats.totalPayments or 0) < 6 then
        table.insert(tips, g_i18n:getText("usedplus_cr_tipTimeBuilds"))
    end

    -- No accounts tip
    if openAccounts == 0 and debt == 0 then
        table.insert(tips, g_i18n:getText("usedplus_cr_tipNoHistory"))
    end

    -- Limit to 3 tips
    while #tips > 3 do
        table.remove(tips)
    end

    -- Pad with general tips if needed
    local generalTips = {
        g_i18n:getText("usedplus_cr_tipGeneral1"),
        g_i18n:getText("usedplus_cr_tipGeneral2"),
        g_i18n:getText("usedplus_cr_tipGeneral3"),
        g_i18n:getText("usedplus_cr_tipGeneral4"),
        g_i18n:getText("usedplus_cr_tipGeneral5")
    }

    local generalIndex = 1
    while #tips < 3 and generalIndex <= #generalTips do
        -- Don't add duplicates
        local isDuplicate = false
        for _, existingTip in ipairs(tips) do
            if existingTip == generalTips[generalIndex] then
                isDuplicate = true
                break
            end
        end
        if not isDuplicate then
            table.insert(tips, generalTips[generalIndex])
        end
        generalIndex = generalIndex + 1
    end

    -- Update UI elements
    if self.tipText1 then
        self.tipText1:setText(tips[1] or "")
    end
    if self.tipText2 then
        self.tipText2:setText(tips[2] or "")
    end
    if self.tipText3 then
        self.tipText3:setText(tips[3] or "")
    end
end

--[[
     Close button callback
]]
function CreditReportDialog:onClickBack()
    self:close()
end

UsedPlus.logInfo("CreditReportDialog loaded")
