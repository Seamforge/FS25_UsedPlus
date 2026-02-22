--[[
    FS25_UsedPlus - Finance Manager Frame (ESC Menu Page)

    v2.7.2 REFACTORED: Core frame with panel modules

    Three-column layout showing Finances, Searches, and Stats simultaneously
    Uses row-based table display with proper column alignment

    Panel Modules (loaded before this file):
    - FinancesPanel.lua: Finance section, payment dialogs
    - SearchesPanel.lua: Search section, info/cancel handlers
    - SalesPanel.lua: Sale listings, offer handlers
]]

-- Use existing table if modules have loaded, otherwise create new
FinanceManagerFrame = FinanceManagerFrame or {}
FinanceManagerFrame._mt = Class(FinanceManagerFrame, TabbedMenuFrameElement)

-- Static instance reference for external refresh calls
FinanceManagerFrame.instance = nil

-- Constants
FinanceManagerFrame.MAX_FINANCE_ROWS = 9
FinanceManagerFrame.MAX_SEARCH_ROWS = 5
FinanceManagerFrame.MAX_SALE_ROWS = 3

--[[
    Helper function to check if credit system is enabled
]]
function FinanceManagerFrame.isCreditSystemEnabled()
    if UsedPlusSettings and UsedPlusSettings.get then
        return UsedPlusSettings:get("enableCreditSystem") ~= false
    end
    return true
end

function FinanceManagerFrame.new()
    local self = FinanceManagerFrame:superClass().new(nil, FinanceManagerFrame._mt)

    self.name = "financeManagerFrame"

    -- Store row element references
    self.financeRows = {}
    self.searchRows = {}
    self.saleRows = {}

    -- Track active data
    self.activeSaleListings = {}
    self.selectedDealId = nil

    -- Menu buttons
    self.btnBack = {
        inputAction = InputAction.MENU_BACK
    }

    self.btnPreviousPage = {
        text = g_i18n:getText("usedplus_button_prevPage"),
        inputAction = InputAction.MENU_PAGE_PREV
    }

    self.btnNextPage = {
        text = g_i18n:getText("usedplus_button_nextPage"),
        inputAction = InputAction.MENU_PAGE_NEXT
    }

    self.btnDashboard = {
        text = g_i18n:getText("usedplus_fmf_btnCreditReport"),
        inputAction = InputAction.MENU_ACTIVATE,
        callback = function()
            self:onCreditReportClick()
        end
    }

    self.btnTakeLoan = {
        text = g_i18n:getText("usedplus_fmf_btnTakeLoan"),
        inputAction = InputAction.MENU_EXTRA_1,
        callback = function()
            self:onTakeLoanClick()
        end
    }

    -- Build button list conditionally
    local buttons = {
        self.btnBack,
        self.btnNextPage,
        self.btnPreviousPage
    }

    if FinanceManagerFrame.isCreditSystemEnabled() then
        table.insert(buttons, self.btnDashboard)
    else
        UsedPlus.logDebug("Credit Report button hidden - Credit System disabled")
    end

    if ModCompatibility.shouldShowTakeLoanOption() then
        table.insert(buttons, self.btnTakeLoan)
    else
        UsedPlus.logDebug("Take Loan button hidden - EnhancedLoanSystem detected")
    end

    self:setMenuButtonInfo(buttons)

    return self
end

function FinanceManagerFrame:onGuiSetupFinished()
    FinanceManagerFrame:superClass().onGuiSetupFinished(self)

    -- Set up section header icons
    self:setupSectionIcons()

    -- Cache references to finance row elements
    for i = 0, FinanceManagerFrame.MAX_FINANCE_ROWS - 1 do
        local rowId = "financeRow" .. i
        self.financeRows[i] = {
            row = self[rowId],
            bg = self[rowId .. "Bg"],
            hit = self[rowId .. "Hit"],
            type = self[rowId .. "Type"],
            item = self[rowId .. "Item"],
            balance = self[rowId .. "Balance"],
            monthly = self[rowId .. "Monthly"],
            progress = self[rowId .. "Progress"],
            remaining = self[rowId .. "Remaining"]
        }
    end

    -- Track selected finance row index
    self.selectedFinanceRowIndex = -1

    -- Cache reference to finance table container
    self.financeTableContainer = self.financeTableContainer

    -- Row Y positions for click detection
    self.financeRowPositions = {
        [0] = 324, [1] = 288, [2] = 252, [3] = 216,
        [4] = 180, [5] = 144, [6] = 108, [7] = 72, [8] = 36
    }
    self.financeRowHeight = 36

    -- Cache references to search row elements
    for i = 0, FinanceManagerFrame.MAX_SEARCH_ROWS - 1 do
        local rowId = "searchRow" .. i
        self.searchRows[i] = {
            row = self[rowId],
            bg = self[rowId .. "Bg"],
            hit = self[rowId .. "Hit"],
            item = self[rowId .. "Item"],
            price = self[rowId .. "Price"],
            tier = self[rowId .. "Tier"],
            chance = self[rowId .. "Chance"],
            time = self[rowId .. "Time"],
            infoBtn = self[rowId .. "InfoBtn"],
            infoBtnBg = self[rowId .. "InfoBtnBg"],
            infoBtnText = self[rowId .. "InfoBtnText"],
            cancelBtn = self[rowId .. "CancelBtn"],
            cancelBtnBg = self[rowId .. "CancelBtnBg"],
            cancelBtnText = self[rowId .. "CancelBtnText"]
        }
    end

    -- Cache references to sale listing row elements
    for i = 0, FinanceManagerFrame.MAX_SALE_ROWS - 1 do
        local rowId = "saleRow" .. i
        self.saleRows[i] = {
            row = self[rowId],
            bg = self[rowId .. "Bg"],
            item = self[rowId .. "Item"],
            tier = self[rowId .. "Tier"],
            status = self[rowId .. "Status"],
            time = self[rowId .. "Time"],
            offers = self[rowId .. "Offers"],
            infoBtn = self[rowId .. "InfoBtn"],
            infoBtnBg = self[rowId .. "InfoBtnBg"],
            infoBtnText = self[rowId .. "InfoBtnText"],
            acceptBtn = self[rowId .. "AcceptBtn"],
            acceptBtnBg = self[rowId .. "AcceptBtnBg"],
            acceptBtnText = self[rowId .. "AcceptBtnText"],
            declineBtn = self[rowId .. "DeclineBtn"],
            declineBtnBg = self[rowId .. "DeclineBtnBg"],
            declineBtnText = self[rowId .. "DeclineBtnText"],
            cancelBtn = self[rowId .. "CancelBtn"],
            cancelBtnBg = self[rowId .. "CancelBtnBg"],
            cancelBtnText = self[rowId .. "CancelBtnText"]
        }
    end

    -- Cache references to action button elements
    self.actionButtons = {
        pay = {
            btn = self.paySelectedBtn,
            bg = self.payBtnBg,
            text = self.payBtnText,
            enabledBgColor = {0.2, 0.4, 0.2, 1},
            disabledBgColor = {0.15, 0.15, 0.15, 1},
            focusBgColor = {0.3, 0.5, 0.3, 1},
            enabledTextColor = {1, 1, 1, 1},
            disabledTextColor = {0.4, 0.4, 0.4, 1}
        },
        info = {
            btn = self.infoSelectedBtn,
            bg = self.infoBtnBg,
            text = self.infoBtnText,
            enabledBgColor = {0.2, 0.3, 0.4, 1},
            disabledBgColor = {0.15, 0.15, 0.15, 1},
            focusBgColor = {0.3, 0.4, 0.5, 1},
            enabledTextColor = {1, 1, 1, 1},
            disabledTextColor = {0.4, 0.4, 0.4, 1}
        },
        payAll = {
            btn = self.payAllBtn,
            bg = self.payAllBtnBg,
            text = self.payAllBtnText,
            enabledBgColor = {0.2, 0.35, 0.2, 1},
            disabledBgColor = {0.15, 0.15, 0.15, 1},
            focusBgColor = {0.3, 0.45, 0.3, 1},
            enabledTextColor = {1, 1, 1, 1},
            disabledTextColor = {0.4, 0.4, 0.4, 1}
        }
    }

    self:setupActionButtonFocusHandlers()
end

--[[
    Set up focus handlers for action buttons
]]
function FinanceManagerFrame:setupActionButtonFocusHandlers()
    for name, btnData in pairs(self.actionButtons) do
        if btnData.btn then
            local frame = self
            local buttonName = name

            btnData.btn.onFocusEnter = function(element)
                frame:onActionButtonFocusEnter(buttonName)
            end

            btnData.btn.onFocusLeave = function(element)
                frame:onActionButtonFocusLeave(buttonName)
            end
        end
    end
end

function FinanceManagerFrame:onActionButtonFocusEnter(buttonName)
    local btnData = self.actionButtons[buttonName]
    if not btnData or not btnData.bg then return end

    if btnData.btn and not btnData.btn:getIsDisabled() then
        btnData.bg:setImageColor(nil, unpack(btnData.focusBgColor))
    end
end

function FinanceManagerFrame:onActionButtonFocusLeave(buttonName)
    local btnData = self.actionButtons[buttonName]
    if not btnData or not btnData.bg then return end

    if btnData.btn and btnData.btn:getIsDisabled() then
        btnData.bg:setImageColor(nil, unpack(btnData.disabledBgColor))
    else
        btnData.bg:setImageColor(nil, unpack(btnData.enabledBgColor))
    end
end

--[[
    Set up section header icons (v2.8.0)
    Icons must be set via Lua - XML paths don't work from ZIP mods
]]
function FinanceManagerFrame:setupSectionIcons()
    local iconDir = UsedPlus.MOD_DIR .. "gui/icons/"

    -- Finance section (left column) - dollar sign
    if self.financeSectionIcon ~= nil then
        self.financeSectionIcon:setImageFilename(iconDir .. "finance.dds")
    end

    -- Marketplace section (center column) - search magnifying glass
    if self.marketplaceSectionIcon ~= nil then
        self.marketplaceSectionIcon:setImageFilename(iconDir .. "search.dds")
    end

    -- Credit/Stats section (right column) - credit score star
    if self.creditSectionIcon ~= nil then
        self.creditSectionIcon:setImageFilename(iconDir .. "credit_score.dds")
    end

    -- Vehicles For Sale subsection - sale tag
    if self.saleSectionIcon ~= nil then
        self.saleSectionIcon:setImageFilename(iconDir .. "sale.dds")
    end

    -- Used Vehicle Searches subsection - inspect/eye icon
    if self.searchSectionIcon ~= nil then
        self.searchSectionIcon:setImageFilename(iconDir .. "inspect.dds")
    end
end

function FinanceManagerFrame:onFrameOpen()
    FinanceManagerFrame:superClass().onFrameOpen(self)
    FinanceManagerFrame.instance = self

    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    self.currentFarmId = farm and farm.farmId or nil

    if g_messageCenter then
        g_messageCenter:subscribe(MessageType.MONEY_CHANGED, self.onMoneyChanged, self)
    end

    self:setMenuButtonInfoDirty()
    self:updateDisplay()
end

function FinanceManagerFrame:onFrameClose()
    FinanceManagerFrame:superClass().onFrameClose(self)

    if g_messageCenter then
        g_messageCenter:unsubscribe(MessageType.MONEY_CHANGED, self)
    end
    self.currentFarmId = nil
end

function FinanceManagerFrame:onMoneyChanged(farmId, newBalance)
    if farmId == self.currentFarmId then
        self:updateDisplay()
    end
end

--[[
    Static method to refresh the frame from external code
]]
function FinanceManagerFrame.refresh()
    if FinanceManagerFrame.instance then
        FinanceManagerFrame.instance:updateDisplay()
        UsedPlus.logTrace("FinanceManagerFrame refreshed")
    end
end

--[[
    Update all three sections (calls into panel modules)
]]
function FinanceManagerFrame:updateDisplay()
    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if not farm then
        return
    end
    local farmId = farm.farmId

    -- These functions are provided by panel modules
    self:updateFinancesSection(farmId, farm)
    self:updateSearchesSection(farmId)
    self:updateSaleListings(farmId)
    self:updateStatsSection(farmId, farm)

    -- v2.13.1: Version & source footer
    if self.versionFooterText then
        local version = UsedPlus.VERSION
        self.versionFooterText:setText(string.format(
            g_i18n:getText("usedplus_fmf_versionFooter"),
            version))
    end

    -- Check for ELS data loss (ELS loans exist but mod not installed)
    self:checkForELSDataLoss(farmId, farm)
end

--[[
    Check for ELS data loss warning
    Show warning if ELS loans exist but EnhancedLoanSystem mod is not installed
]]
function FinanceManagerFrame:checkForELSDataLoss(farmId, farm)
    -- Skip if already warned this session
    if self.hasShownELSWarning then
        return
    end

    -- Skip if ELS is integrated (mod is installed and active)
    if ModCompatibility and ModCompatibility.enhancedLoanSystemInstalled then
        return
    end

    -- Check if any deals are marked as ELS loans
    local hasELSLoans = false
    if g_financeManager and g_financeManager.deals then
        for _, deal in pairs(g_financeManager.deals) do
            if deal.farmId == farmId and deal.isELSLoan and deal.currentBalance and deal.currentBalance > 0 then
                hasELSLoans = true
                break
            end
        end
    end

    -- Show warning if ELS loans exist but mod not available
    if hasELSLoans then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_WARNING,
            g_i18n:getText("usedplus_warning_elsDataLoss") or
            "Some loans require EnhancedLoanSystem mod to manage. Data preserved but inaccessible."
        )
        self.hasShownELSWarning = true
        UsedPlus.logInfo("ELS data loss warning shown - ELS loans exist but mod not installed")
    end
end

--[[
    Handle mouse events for row selection
]]
function FinanceManagerFrame:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    if FinanceManagerFrame:superClass().mouseEvent ~= nil then
        eventUsed = FinanceManagerFrame:superClass().mouseEvent(self, posX, posY, isDown, isUp, button, eventUsed)
    end

    if not isUp or button ~= Input.MOUSE_BUTTON_LEFT then
        return eventUsed
    end

    if not self.financeTableContainer or not self.financeTableContainer:getIsVisible() then
        return eventUsed
    end

    local containerX = self.financeTableContainer.absPosition[1]
    local containerY = self.financeTableContainer.absPosition[2]
    local containerW = self.financeTableContainer.absSize[1]
    local containerH = self.financeTableContainer.absSize[2]

    if posX >= containerX and posX <= containerX + containerW and
       posY >= containerY and posY <= containerY + containerH then

        local relativeY = posY - containerY
        local containerHeightPx = 360
        local pixelY = (relativeY / containerH) * containerHeightPx

        local clickedRow = -1
        for rowIndex = 0, 8 do
            local rowY = self.financeRowPositions[rowIndex]
            if pixelY >= rowY and pixelY < rowY + self.financeRowHeight then
                clickedRow = rowIndex
                break
            end
        end

        if clickedRow >= 0 and self.activeDeals and self.activeDeals[clickedRow + 1] then
            self:selectFinanceRow(clickedRow)
            return true
        end
    end

    return eventUsed
end

--[[
    Update Stats section (right column)
]]
function FinanceManagerFrame:updateStatsSection(farmId, farm)
    local creditEnabled = FinanceManagerFrame.isCreditSystemEnabled()

    if self.statsSectionHeaderText then
        if creditEnabled then
            self.statsSectionHeaderText:setText(g_i18n:getText("usedplus_fmf_sectionCredit") or "Credit & Statistics")
        else
            self.statsSectionHeaderText:setText(g_i18n:getText("usedplus_fmf_sectionStatistics") or "Statistics")
        end
    end

    if self.creditScoreBox then
        self.creditScoreBox:setVisible(creditEnabled)
    end

    local score = 650
    local rating = "fair"
    local interestAdj = 1.0
    local assets = 0
    local debt = 0

    if creditEnabled and CreditScore then
        score = CreditScore.calculate(farmId)
        rating = CreditScore.getRating(score)
        interestAdj = CreditScore.getInterestAdjustment(score)
        assets = CreditScore.calculateAssets(farm)
        debt = CreditScore.calculateDebt(farm)

        local ratingText = rating or "Unknown"
        local adjText = interestAdj >= 0 and string.format("+%.1f%% interest", interestAdj) or string.format("%.1f%% interest", interestAdj)

        if self.creditScoreValueText then
            self.creditScoreValueText:setText(tostring(score))
        end
        if self.creditRatingText then
            self.creditRatingText:setText(ratingText)
        end
        if self.interestAdjustText then
            self.interestAdjustText:setText(adjText)
        end
        if self.assetsText then
            local farmlandCount = ModCompatibility.getFarmlandCount(farmId)
            local assetsStr = g_i18n:formatMoney(assets, 0, true, true)
            if farmlandCount > 0 then
                self.assetsText:setText(string.format(g_i18n:getText("usedplus_fmf_assetsWithFields"), assetsStr, farmlandCount))
            else
                self.assetsText:setText(string.format(g_i18n:getText("usedplus_manager_assetsLabel"), assetsStr))
            end
        end
        if self.debtText then
            self.debtText:setText(string.format(g_i18n:getText("usedplus_manager_debtLabel"), g_i18n:formatMoney(debt, 0, true, true)))
        end

        self:highlightCreditTier(score)
    end

    -- Calculate lifetime statistics
    local lifetimeFinanced = 0
    local lifetimeInterest = 0
    local lifetimePayments = 0
    local activeDeals = 0

    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(farmId)
        if deals then
            for _, deal in ipairs(deals) do
                lifetimeFinanced = lifetimeFinanced + (deal.amountFinanced or 0)
                lifetimeInterest = lifetimeInterest + (deal.totalInterestPaid or 0)
                lifetimePayments = lifetimePayments + (deal.monthsPaid or 0)
                if deal.status == "active" then
                    activeDeals = activeDeals + 1
                end
            end
        end
    end

    if self.lifetimeDealsText then
        self.lifetimeDealsText:setText(tostring(activeDeals))
    end
    if self.lifetimeFinancedText then
        self.lifetimeFinancedText:setText(g_i18n:formatMoney(lifetimeFinanced, 0, true, true))
    end
    if self.lifetimeInterestText then
        self.lifetimeInterestText:setText(g_i18n:formatMoney(lifetimeInterest, 0, true, true))
    end
    if self.lifetimePaymentsText then
        self.lifetimePaymentsText:setText(tostring(lifetimePayments))
    end

    -- Search statistics
    local stats = g_financeManager:getStatistics(farmId)
    if self.lifetimeSearchesText then
        self.lifetimeSearchesText:setText(tostring(stats.searchesStarted or 0))
    end
    if self.lifetimeFoundText then
        self.lifetimeFoundText:setText(tostring(stats.searchesSucceeded or 0))
    end
    if self.lifetimeFeesText then
        self.lifetimeFeesText:setText(g_i18n:formatMoney(stats.totalSearchFees or 0, 0, true, true))
    end
    if self.lifetimeSuccessRateText then
        local totalSearches = stats.searchesStarted or 0
        local found = stats.searchesSucceeded or 0
        if totalSearches > 0 then
            local rate = math.floor((found / totalSearches) * 100)
            self.lifetimeSuccessRateText:setText(string.format("%d%%", rate))
        else
            self.lifetimeSuccessRateText:setText(g_i18n:getText("usedplus_fm_notAvailable"))
        end
    end

    -- Credit history summary
    if creditEnabled and CreditHistory then
        local summary = CreditHistory.getSummary(farmId)

        if self.paymentsOnTimeText then
            self.paymentsOnTimeText:setText(tostring(summary.paymentsOnTime or 0))
        end
        if self.paymentsMissedText then
            self.paymentsMissedText:setText(tostring(summary.paymentsMissed or 0))
            if summary.paymentsMissed > 0 then
                self.paymentsMissedText:setTextColor(0.8, 0.2, 0.2, 1)
            else
                self.paymentsMissedText:setTextColor(0.2, 0.8, 0.2, 1)
            end
        end
        if self.dealsCompletedText then
            self.dealsCompletedText:setText(tostring(summary.dealsCompleted or 0))
        end
        if self.creditTrendText then
            local netChange = summary.netChange or 0
            local trendText = ""
            if netChange > 20 then
                trendText = "Trending Up"
                self.creditTrendText:setTextColor(0.2, 0.8, 0.2, 1)
            elseif netChange > 0 then
                trendText = "Slightly Up"
                self.creditTrendText:setTextColor(0.4, 0.7, 0.2, 1)
            elseif netChange < -20 then
                trendText = "Trending Down"
                self.creditTrendText:setTextColor(0.8, 0.2, 0.2, 1)
            elseif netChange < 0 then
                trendText = "Slightly Down"
                self.creditTrendText:setTextColor(0.8, 0.6, 0.2, 1)
            else
                trendText = "Stable"
                self.creditTrendText:setTextColor(0.7, 0.7, 0.7, 1)
            end
            self.creditTrendText:setText(trendText)
        end
        if self.historyAdjustmentText then
            local adjustment = CreditHistory.getScoreAdjustment(farmId)
            self.historyAdjustmentText:setText(string.format(g_i18n:getText("usedplus_fmf_historyPoints"), adjustment))
        end
    end
end

--[[
    Highlight the current credit tier
]]
function FinanceManagerFrame:highlightCreditTier(score)
    local tiers = {
        {name = "Excellent", minScore = 750, bgId = "tierExcellentBg"},
        {name = "Good",      minScore = 700, bgId = "tierGoodBg"},
        {name = "Fair",      minScore = 650, bgId = "tierFairBg"},
        {name = "Poor",      minScore = 600, bgId = "tierPoorBg"},
        {name = "VeryPoor",  minScore = 300, bgId = "tierVeryPoorBg"}
    }

    local highlightColor = {0.8, 0.5, 0.1, 0.6}
    local noHighlightColor = {0, 0, 0, 0}

    local currentTier = nil
    for _, tier in ipairs(tiers) do
        if score >= tier.minScore then
            currentTier = tier.name
            break
        end
    end

    for _, tier in ipairs(tiers) do
        local bgElement = self[tier.bgId]
        if bgElement then
            if tier.name == currentTier then
                bgElement:setImageColor(nil, unpack(highlightColor))
            else
                bgElement:setImageColor(nil, unpack(noHighlightColor))
            end
        end
    end
end

--[[
    Take Loan button clicked
]]
function FinanceManagerFrame:onTakeLoanClick()
    if not ModCompatibility.shouldShowTakeLoanOption() then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_notification_loansManByELS")
        )
        return
    end

    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if not farm then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_farmNotFound")
        )
        return
    end

    DialogLoader.show("TakeLoanDialog", "setFarmId", farm.farmId)
end

--[[
    Credit Report button clicked
]]
function FinanceManagerFrame:onCreditReportClick()
    DialogLoader.show("CreditReportDialog")
end

-- ========== ADMIN PANEL BUTTON (v2.15.1) ==========

function FinanceManagerFrame:onAdminPanelClick()
    -- Multi-method vehicle detection (ESC menu may clear controlledVehicle)
    local vehicle = nil

    -- Method 1: HUD controlled vehicle
    if g_currentMission.hud and g_currentMission.hud.controlledVehicle then
        vehicle = g_currentMission.hud.controlledVehicle
    end

    -- Method 2: Standard controlledVehicle
    if vehicle == nil and g_currentMission.controlledVehicle then
        vehicle = g_currentMission.controlledVehicle
    end

    -- Method 3: Find entered vehicle (most reliable in ESC menu context)
    if vehicle == nil and g_currentMission.vehicles then
        for _, v in pairs(g_currentMission.vehicles) do
            if v.getIsEntered and v:getIsEntered() then
                vehicle = v
                break
            end
        end
    end

    if vehicle == nil then
        InfoDialog.show(g_i18n:getText("usedplus_admin_no_vehicle_warning"))
        return
    end

    DialogLoader.show("AdminControlPanel", "setVehicle", vehicle)
end

function FinanceManagerFrame:onAdminBtnHighlight()
    if self.adminPanelBtnBg then
        self.adminPanelBtnBg:setImageColor(nil, 0.28, 0.35, 0.55, 1)
    end
    if self.adminPanelBtnText then
        self.adminPanelBtnText:setTextColor(1, 1, 1, 1)
    end
end

function FinanceManagerFrame:onAdminBtnUnhighlight()
    if self.adminPanelBtnBg then
        self.adminPanelBtnBg:setImageColor(nil, 0.18, 0.22, 0.35, 1)
    end
    if self.adminPanelBtnText then
        self.adminPanelBtnText:setTextColor(0.6, 0.8, 1, 1)
    end
end

UsedPlus.logInfo("FinanceManagerFrame loaded")
