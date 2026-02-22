--[[
    SearchDetailsDialog.lua
    Dialog showing details about an active used vehicle search

    v1.5.0: Multi-find agent model
    Displays:
    - Vehicle being searched for
    - Monthly progress (Month X of Y)
    - Retainer paid + commission rate
    - Number of vehicles found in portfolio
    - Expected pricing and savings
    - Quality selection impact

    Note: Full portfolio browser is available in VehiclePortfolioDialog.lua
]]

SearchDetailsDialog = {}
-- Use ScreenElement, NOT MessageDialog (MessageDialog lacks registerControls)
local SearchDetailsDialog_mt = Class(SearchDetailsDialog, ScreenElement)

-- Static instance
SearchDetailsDialog.instance = nil
SearchDetailsDialog.xmlPath = nil

-- v1.5.0: Search tier definitions (must match UsedVehicleSearch.SEARCH_TIERS)
SearchDetailsDialog.SEARCH_TIERS = {
    {
        name = "Local Search",
        retainerFlat = 500,
        retainerPercent = 0,
        commissionPercent = 0.06,
        monthlySuccessChance = 0.30,
        maxMonths = 1,
        maxListings = 3
    },
    {
        name = "Regional Search",
        retainerFlat = 1000,
        retainerPercent = 0.005,
        commissionPercent = 0.08,
        monthlySuccessChance = 0.55,
        maxMonths = 3,
        maxListings = 6
    },
    {
        name = "National Search",
        retainerFlat = 2000,
        retainerPercent = 0.008,
        commissionPercent = 0.10,
        monthlySuccessChance = 0.85,
        maxMonths = 6,
        maxListings = 10,
        guaranteedMinimum = 1
    }
}

--[[
    Get or create dialog instance
]]
function SearchDetailsDialog.getInstance()
    if SearchDetailsDialog.instance == nil then
        if SearchDetailsDialog.xmlPath == nil then
            SearchDetailsDialog.xmlPath = UsedPlus.MOD_DIR .. "gui/SearchDetailsDialog.xml"
        end

        SearchDetailsDialog.instance = SearchDetailsDialog.new()
        g_gui:loadGui(SearchDetailsDialog.xmlPath, "SearchDetailsDialog", SearchDetailsDialog.instance)
    end

    return SearchDetailsDialog.instance
end

--[[
    Constructor
]]
function SearchDetailsDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or SearchDetailsDialog_mt)

    self.search = nil
    self.isBackAllowed = true

    return self
end

--[[
    Called when dialog is created
]]
function SearchDetailsDialog:onCreate()
    -- No superclass call needed for ScreenElement
end

--[[
    Show dialog with search information
    @param search - UsedVehicleSearch object
]]
function SearchDetailsDialog:show(search)
    if search == nil then
        UsedPlus.logError("SearchDetailsDialog:show called with nil search")
        return
    end

    self.search = search

    -- Populate all fields
    self:updateDisplay()

    -- Show the dialog
    g_gui:showDialog("SearchDetailsDialog")
end

--[[
    Update all display fields with search data
    v1.5.0: Updated for monthly model with portfolio display
]]
function SearchDetailsDialog:updateDisplay()
    if self.search == nil then return end

    local search = self.search

    -- Vehicle Info
    if self.vehicleNameText then
        self.vehicleNameText:setText(search.storeItemName or "Unknown Vehicle")
    end

    -- Search Tier
    local searchTier = SearchDetailsDialog.SEARCH_TIERS[search.searchLevel] or SearchDetailsDialog.SEARCH_TIERS[2]
    if self.searchTierText then
        self.searchTierText:setText(searchTier.name)
    end

    -- v1.5.0: Show retainer fee (already paid) + commission rate
    if self.agentFeeText then
        local retainerFee = search.retainerFee or 0
        local commissionPercent = (search.commissionPercent or searchTier.commissionPercent or 0.08) * 100
        self.agentFeeText:setText(string.format(g_i18n:getText("usedplus_sd_agentFeeFormat"),
            g_i18n:formatMoney(retainerFee, 0, true, true),
            commissionPercent))
    end

    -- v1.5.0: Show monthly success chance
    if self.baseSuccessText then
        local monthlyChance = (search.monthlySuccessChance or searchTier.monthlySuccessChance or 0.5) * 100
        self.baseSuccessText:setText(string.format("%.0f%%/mo", monthlyChance))
    end

    -- Quality Tier
    local qualityTier = UsedVehicleSearch.QUALITY_TIERS[search.qualityLevel] or UsedVehicleSearch.QUALITY_TIERS[1]
    if self.qualityTierText then
        self.qualityTierText:setText(qualityTier.name)
    end

    if self.successModText then
        local successMod = (qualityTier.successModifier or 0) * 100
        local modText = string.format("%+.0f%%", successMod)
        self.successModText:setText(modText)

        if successMod > 0 then
            self.successModText:setTextColor(0.3, 1, 0.3, 1)  -- Green - easier
        elseif successMod < 0 then
            self.successModText:setTextColor(1, 0.4, 0.4, 1)  -- Red - harder
        else
            self.successModText:setTextColor(0.7, 0.7, 0.7, 1)  -- Gray
        end
    end

    -- v1.5.0: Combined success chance (with quality modifier applied)
    if self.combinedChanceText then
        local baseChance = search.monthlySuccessChance or searchTier.monthlySuccessChance or 0.5
        local combinedChance = baseChance + (qualityTier.successModifier or 0)
        combinedChance = math.max(0.05, math.min(0.95, combinedChance))
        self.combinedChanceText:setText(string.format("%.0f%%/mo", combinedChance * 100))

        -- Color based on chance
        if combinedChance >= 0.70 then
            self.combinedChanceText:setTextColor(0.3, 1, 0.3, 1)  -- Green
        elseif combinedChance >= 0.40 then
            self.combinedChanceText:setTextColor(1, 0.8, 0.3, 1)  -- Yellow
        else
            self.combinedChanceText:setTextColor(1, 0.4, 0.4, 1)  -- Red
        end
    end

    -- Pricing
    local basePrice = search.basePrice or 0
    if self.newPriceText then
        self.newPriceText:setText(g_i18n:formatMoney(basePrice, 0, true, true))
    end

    -- Expected price (based on quality tier range)
    local priceRangeMin = qualityTier.priceRangeMin or 0.30
    local priceRangeMax = qualityTier.priceRangeMax or 0.50
    local avgPriceMultiplier = (priceRangeMin + priceRangeMax) / 2
    local expectedBasePrice = math.floor(basePrice * avgPriceMultiplier)
    -- v1.5.0: Add commission to expected price
    local commissionPercent = search.commissionPercent or searchTier.commissionPercent or 0.08
    local expectedCommission = math.floor(expectedBasePrice * commissionPercent)
    local expectedAskingPrice = expectedBasePrice + expectedCommission

    if self.expectedPriceText then
        self.expectedPriceText:setText(g_i18n:formatMoney(expectedAskingPrice, 0, true, true))
    end

    -- Savings percentage (range)
    if self.savingsText then
        local maxDiscount = math.floor((1 - priceRangeMin) * 100)
        local minDiscount = math.floor((1 - priceRangeMax) * 100)
        self.savingsText:setText(string.format("%d-%d%% off", minDiscount, maxDiscount))
    end

    -- Condition range (show as condition percent)
    if self.conditionRangeText then
        local damageRange = qualityTier.damageRange or { 0.30, 0.60 }
        -- Condition = 100% - damage%
        local maxCondition = math.floor((1 - damageRange[1]) * 100)
        local minCondition = math.floor((1 - damageRange[2]) * 100)
        self.conditionRangeText:setText(string.format("%d%% - %d%%", minCondition, maxCondition))
    end

    -- Price range (v1.5.0: includes commission)
    if self.priceRangeText then
        local minBasePrice = math.floor(basePrice * priceRangeMin)
        local maxBasePrice = math.floor(basePrice * priceRangeMax)
        local minAsking = minBasePrice + math.floor(minBasePrice * commissionPercent)
        local maxAsking = maxBasePrice + math.floor(maxBasePrice * commissionPercent)
        self.priceRangeText:setText(string.format("%s - %s",
            g_i18n:formatMoney(minAsking, 0, true, true),
            g_i18n:formatMoney(maxAsking, 0, true, true)))
    end

    -- v1.5.0: Status with portfolio count
    if self.statusText then
        local statusText = g_i18n:getText("usedplus_sd_statusSearching")
        local statusColor = {0.7, 0.7, 0.7, 1}

        local foundCount = #(search.foundListings or {})
        local maxListings = search.maxListings or searchTier.maxListings or 10

        if search.status == "active" then
            if foundCount > 0 then
                statusText = string.format(g_i18n:getText("usedplus_sd_vehiclesFound"), foundCount)
                statusColor = {0.3, 1, 0.3, 1}  -- Green
            else
                statusText = g_i18n:getText("usedplus_sd_statusSearching")
                statusColor = {0.8, 0.8, 0.3, 1}  -- Yellow
            end
        elseif search.status == "completed" then
            statusText = string.format(g_i18n:getText("usedplus_sd_statusComplete"), foundCount)
            statusColor = foundCount > 0 and {0.3, 1, 0.3, 1} or {0.6, 0.6, 0.6, 1}
        elseif search.status == "cancelled" then
            statusText = g_i18n:getText("usedplus_sd_statusCancelled")
            statusColor = {0.6, 0.6, 0.6, 1}  -- Gray
        end

        self.statusText:setText(statusText)
        self.statusText:setTextColor(unpack(statusColor))
    end

    -- v1.5.0: Monthly progress instead of time remaining
    if self.timeRemainingText then
        local monthsElapsed = search.monthsElapsed or 0
        local maxMonths = search.maxMonths or searchTier.maxMonths or 1
        local monthsRemaining = maxMonths - monthsElapsed

        if monthsRemaining > 0 then
            self.timeRemainingText:setText(string.format(g_i18n:getText("usedplus_sd_monthsLeft"), monthsRemaining))
        else
            self.timeRemainingText:setText(g_i18n:getText("usedplus_sd_finalMonth"))
        end
    end

    -- v1.5.0: Show month progress
    if self.startedText then
        local monthsElapsed = search.monthsElapsed or 0
        local maxMonths = search.maxMonths or searchTier.maxMonths or 1
        self.startedText:setText(string.format(g_i18n:getText("usedplus_sd_monthProgress"), monthsElapsed + 1, maxMonths))
    end

    -- v1.5.0: Show portfolio count
    if self.elapsedText then
        local foundCount = #(search.foundListings or {})
        local maxListings = search.maxListings or searchTier.maxListings or 10
        self.elapsedText:setText(string.format(g_i18n:getText("usedplus_sd_foundCount"), foundCount, maxListings))
    end

    -- Info text - tips based on search tier and portfolio
    if self.infoText then
        local foundCount = #(search.foundListings or {})
        local tipText = g_i18n:getText("usedplus_sd_tipRegional")

        if foundCount > 0 then
            tipText = g_i18n:getText("usedplus_sd_tipDefault")
        elseif search.searchLevel == 1 then
            tipText = g_i18n:getText("usedplus_sd_tipLocal")
        elseif search.searchLevel == 3 then
            tipText = g_i18n:getText("usedplus_sd_tipNational")
        end

        if search.qualityLevel >= 4 and foundCount == 0 then
            tipText = g_i18n:getText("usedplus_sd_tipQuality")
        end

        self.infoText:setText(tipText)
    end
end

--[[
    Handle close button click
    Note: ScreenElement doesn't have close() - use changeScreen to return
]]
function SearchDetailsDialog:onCloseDialog()
    -- Close dialog by changing back to previous screen
    g_gui:changeScreen(nil)
end

--[[
    Handle View Portfolio button click
    Opens VehiclePortfolioDialog to browse found vehicles
]]
function SearchDetailsDialog:onViewPortfolio()
    if self.search == nil then
        UsedPlus.logError("No search to view portfolio for")
        return
    end

    local foundCount = #(self.search.foundListings or {})
    if foundCount == 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_notification_noVehiclesYet")
        )
        return
    end

    -- IMPORTANT: Save search reference BEFORE closing dialog
    -- onClose() sets self.search = nil, so we need to capture it first
    local searchToView = self.search

    -- Close this dialog first
    g_gui:changeScreen(nil)

    -- Open the portfolio dialog with saved reference
    DialogLoader.show("VehiclePortfolioDialog", "show", searchToView)
end

--[[
    Update View Portfolio button visibility
    Called after updateDisplay() or when search changes
]]
function SearchDetailsDialog:updatePortfolioButton()
    if self.viewPortfolioButton == nil then
        return
    end

    local foundCount = 0
    if self.search and self.search.foundListings then
        foundCount = #self.search.foundListings
    end

    -- Show/hide button based on whether there are found vehicles
    if foundCount > 0 then
        self.viewPortfolioButton:setVisible(true)
        self.viewPortfolioButton:setText(string.format(g_i18n:getText("usedplus_sd_viewPortfolio"),
            foundCount, foundCount > 1 and "s" or ""))
    else
        self.viewPortfolioButton:setVisible(false)
    end
end

--[[
    Handle ESC key / back button
]]
function SearchDetailsDialog:onClickBack()
    g_gui:changeScreen(nil)
    return true  -- Handled
end

--[[
    Called when dialog opens
]]
function SearchDetailsDialog:onOpen()
    SearchDetailsDialog:superClass().onOpen(self)
    -- Update portfolio button visibility when dialog opens
    self:updatePortfolioButton()
end

--[[
    Called when dialog closes
]]
function SearchDetailsDialog:onClose()
    SearchDetailsDialog:superClass().onClose(self)
    self.search = nil
end

UsedPlus.logInfo("SearchDetailsDialog loaded")
