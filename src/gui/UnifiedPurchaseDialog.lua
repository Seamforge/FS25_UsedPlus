--[[
    FS25_UsedPlus - Unified Purchase Dialog

     Single dialog for all purchase modes (Cash, Finance, Lease)
    with integrated Trade-In support. Replaces separate dialogs for cleaner UX.

    Features:
    - Mode selector: Buy with Cash, Finance, Lease
    - Trade-in support for all modes
    - Dynamic section visibility based on mode
    - Unified calculations and purchase flow
]]

UnifiedPurchaseDialog = {}
local UnifiedPurchaseDialog_mt = Class(UnifiedPurchaseDialog, MessageDialog)

-- Purchase modes
UnifiedPurchaseDialog.MODE_CASH = 1
UnifiedPurchaseDialog.MODE_FINANCE = 2
UnifiedPurchaseDialog.MODE_LEASE = 3

UnifiedPurchaseDialog.MODE_TEXTS = {"Buy with Cash", "Finance", "Lease"}

-- Term options (v2.7.0: reduced from 20 to 15 years max, credit-gated)
-- Longer terms require better credit to prevent over-leveraging
UnifiedPurchaseDialog.FINANCE_TERMS = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}  -- Years (max 15)
-- Credit requirements for term lengths:
-- 1-5 years: Any credit (300+)
-- 6-10 years: Fair credit (650+)
-- 11-15 years: Good credit (700+)
UnifiedPurchaseDialog.TERM_CREDIT_REQUIREMENTS = {
    {maxYears = 5, minCredit = 300},   -- Anyone can get short-term
    {maxYears = 10, minCredit = 650},  -- Fair credit for medium-term
    {maxYears = 15, minCredit = 700},  -- Good credit for long-term
}

-- v2.7.1: Credit requirements for down payment options
-- Better credit = access to lower down payment options
-- This prevents new players with no credit history from getting 0% down
UnifiedPurchaseDialog.DOWN_PAYMENT_CREDIT_REQUIREMENTS = {
    {minDown = 25, minCredit = 300},   -- Very poor credit: 25%+ down required
    {minDown = 20, minCredit = 600},   -- Poor credit: 20%+ down required
    {minDown = 10, minCredit = 650},   -- Fair credit: 10%+ down required
    {minDown = 5, minCredit = 700},    -- Good credit: 5%+ down required
    {minDown = 0, minCredit = 750},    -- Excellent credit: 0% down available
}

-- Lease terms in months: 3, 6, 9 months (short-term), then 1-5 years
-- Vehicle leases beyond 5 years don't make financial sense - just buy it!
UnifiedPurchaseDialog.LEASE_TERMS = {3, 6, 9, 12, 24, 36, 48, 60}
UnifiedPurchaseDialog.DOWN_PAYMENT_OPTIONS = {0, 5, 10, 15, 20, 25, 30, 40, 50}  -- Percent
UnifiedPurchaseDialog.CASH_BACK_OPTIONS = {0, 500, 1000, 2500, 5000, 10000}

--[[
    v2.7.1: Get minimum required down payment based on credit score
    Better credit = lower minimum down payment
    @param creditScore - Player's current credit score (300-850)
    @return minPercent - Minimum down payment percentage required
]]
-- REFACTORED: Delegate to CreditCalculations module (backward compatibility wrappers)
function UnifiedPurchaseDialog.getMinDownPaymentForCredit(creditScore)
    return CreditCalculations.getMinDownPaymentForCredit(creditScore)
end

function UnifiedPurchaseDialog.getDownPaymentOptions(creditScore)
    return CreditCalculations.getDownPaymentOptions(creditScore)
end

function UnifiedPurchaseDialog.getDownPaymentPercent(index, creditScore)
    return CreditCalculations.getDownPaymentPercent(index, creditScore)
end

function UnifiedPurchaseDialog.getMaxTermForCredit(creditScore)
    return CreditCalculations.getMaxTermForCredit(creditScore)
end

function UnifiedPurchaseDialog.getFinanceTermsForCredit(creditScore)
    return CreditCalculations.getFinanceTermsForCredit(creditScore)
end

--[[
    Constructor
]]
function UnifiedPurchaseDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or UnifiedPurchaseDialog_mt)

    -- Initialize context - centralized state container
    self.context = PurchaseContext.new()

    -- TEMPORARY: Keep direct fields for backward compatibility during migration
    -- These will be removed in Step 9 (cleanup) once all code uses context
    self.currentMode = self.context.currentMode
    self.tradeInEnabled = self.context.tradeInEnabled
    self.tradeInVehicle = self.context.tradeInVehicle
    self.tradeInValue = self.context.tradeInValue

    self.storeItem = self.context.storeItem
    self.vehiclePrice = self.context.vehiclePrice
    self.vehicleName = self.context.vehicleName
    self.vehicleCategory = self.context.vehicleCategory
    self.isUsedVehicle = self.context.isUsedVehicle
    self.usedCondition = self.context.usedCondition
    self.saleItem = self.context.saleItem

    self.financeTermIndex = self.context.financeTermIndex
    self.financeDownIndex = self.context.financeDownIndex
    self.financeCashBackIndex = self.context.financeCashBackIndex

    self.leaseTermIndex = self.context.leaseTermIndex
    self.leaseDownIndex = self.context.leaseDownIndex

    self.creditScore = self.context.creditScore
    self.creditRating = self.context.creditRating
    self.interestRate = self.context.interestRate

    self.eligibleTradeIns = self.context.eligibleTradeIns

    return self
end

--[[
    Called when GUI elements are ready
]]
function UnifiedPurchaseDialog:onGuiSetupFinished()
    UnifiedPurchaseDialog:superClass().onGuiSetupFinished(self)

    -- Setup mode selector
    if self.modeSelector then
        self.modeSelector:setTexts(UnifiedPurchaseDialog.MODE_TEXTS)
        self.modeSelector:setState(1)  -- Default to Cash
    end

    -- Setup finance term slider
    if self.financeTermSlider then
        local texts = {}
        for _, years in ipairs(UnifiedPurchaseDialog.FINANCE_TERMS) do
            table.insert(texts, years .. (years == 1 and " Year" or " Years"))
        end
        self.financeTermSlider:setTexts(texts)
        self.financeTermSlider:setState(self.financeTermIndex)
    end

    -- Setup finance down payment slider (uses filtered options from settings)
    if self.financeDownSlider then
        local options = UnifiedPurchaseDialog.getDownPaymentOptions()
        local texts = {}
        for _, pct in ipairs(options) do
            table.insert(texts, pct .. "%")
        end
        self.financeDownSlider:setTexts(texts)
        -- Adjust default index to stay within available options
        self.financeDownIndex = math.min(self.financeDownIndex, #options)
        self.financeDownSlider:setState(self.financeDownIndex)
    end

    -- Setup finance cash back slider
    if self.financeCashBackSlider then
        local texts = {}
        for _, amount in ipairs(UnifiedPurchaseDialog.CASH_BACK_OPTIONS) do
            table.insert(texts, g_i18n:formatMoney(amount, 0, true, true))
        end
        self.financeCashBackSlider:setTexts(texts)
        self.financeCashBackSlider:setState(self.financeCashBackIndex)
    end

    -- Setup lease term slider (terms are in months)
    if self.leaseTermSlider then
        local texts = {}
        for _, months in ipairs(UnifiedPurchaseDialog.LEASE_TERMS) do
            if months < 12 then
                table.insert(texts, months .. (months == 1 and " Month" or " Months"))
            elseif months == 12 then
                table.insert(texts, "1 Year")
            else
                local years = months / 12
                table.insert(texts, years .. " Years")
            end
        end
        self.leaseTermSlider:setTexts(texts)
        self.leaseTermSlider:setState(self.leaseTermIndex)
    end

    -- Setup lease down payment slider (uses filtered options from settings)
    if self.leaseDownSlider then
        local options = UnifiedPurchaseDialog.getDownPaymentOptions()
        local texts = {}
        for _, pct in ipairs(options) do
            table.insert(texts, pct .. "%")
        end
        self.leaseDownSlider:setTexts(texts)
        -- Adjust default index to stay within available options
        self.leaseDownIndex = math.min(self.leaseDownIndex, #options)
        self.leaseDownSlider:setState(self.leaseDownIndex)
    end

    -- v2.9.5: Setup section header icons
    self.iconDir = UsedPlus.MOD_DIR .. "gui/icons/"
    self:setupSectionIcons()
end

--[[
    Setup section header icons
    Icons are set via Lua because XML paths don't work from ZIP mods
    Large input dialogs use section icons only (no header icon)
]]
function UnifiedPurchaseDialog:setupSectionIcons()
    if self.iconDir == nil then
        return
    end

    -- Vehicle section - vehicle icon
    if self.vehicleSectionIcon ~= nil then
        self.vehicleSectionIcon:setImageFilename(self.iconDir .. "vehicle.png")
    end

    -- Method section - percentage icon
    if self.methodSectionIcon ~= nil then
        self.methodSectionIcon:setImageFilename(self.iconDir .. "percentage.png")
    end

    -- Trade-In section - trade_in icon
    if self.tradeInSectionIcon ~= nil then
        self.tradeInSectionIcon:setImageFilename(self.iconDir .. "trade_in.png")
    end

    -- Cash section - cash icon
    if self.cashSectionIcon ~= nil then
        self.cashSectionIcon:setImageFilename(self.iconDir .. "cash.png")
    end

    -- Finance section - loan_doc icon
    if self.financeSectionIcon ~= nil then
        self.financeSectionIcon:setImageFilename(self.iconDir .. "loan_doc.png")
    end

    -- Lease section - lease icon
    if self.leaseSectionIcon ~= nil then
        self.leaseSectionIcon:setImageFilename(self.iconDir .. "lease.png")
    end
end

--[[
    Set vehicle data for purchase
    @param storeItem - The store item being purchased
    @param price - The configured price
    @param saleItem - Used vehicle listing (optional)
    @param shopScreen - Reference to shop screen for vanilla buy flow (optional)
]]
function UnifiedPurchaseDialog:setVehicleData(storeItem, price, saleItem, shopScreen)
    self.storeItem = storeItem
    self.vehiclePrice = price or 0
    self.saleItem = saleItem
    self.shopScreen = shopScreen  -- Store for vanilla buy flow

    -- Detect item type: vehicle or placeable
    -- Species 2 = PLACEABLE (covers all categories: SILOS, SHEDS, ANIMALS, etc.)
    -- v2.8.0: Uses separate XML dialogs for vehicles (820px) and placeables (650px)
    if storeItem and storeItem.species == 2 then
        self.context.itemType = "placeable"
        self.itemType = self.context.itemType  -- Shadow field sync
        UsedPlus.logDebug(string.format("Dialog detected placeable: %s (category=%s)",
            tostring(storeItem.name), tostring(storeItem.categoryName)))
        -- Placeables cannot be "used" - always new
        self.context.isUsedVehicle = false
        self.context.usedCondition = 100
        self.isUsedVehicle = false  -- Shadow field sync
        self.usedCondition = 100  -- Shadow field sync
    else
        self.context.itemType = "vehicle"
        self.itemType = self.context.itemType  -- Shadow field sync
        UsedPlus.logDebug(string.format("Dialog detected vehicle: %s (species=%s)",
            tostring(storeItem.name), tostring(storeItem.species)))
        -- Check if this is a used vehicle
        if saleItem then
            self.isUsedVehicle = true
            self.usedCondition = saleItem.condition or 100
        else
            self.isUsedVehicle = false
            self.usedCondition = 100
        end
    end

    -- Use consolidated utility functions for vehicle name and category
    self.vehicleName = UIHelper.Vehicle.getFullName(storeItem)
    self.vehicleCategory = storeItem and UIHelper.Vehicle.getCategoryName(storeItem) or ""

    -- Set item image - XML profile handles aspect ratio via imageSliceId="noSlice"
    if self.itemImage then
        UIHelper.Image.set(self.itemImage, storeItem)
    end

    -- Calculate credit parameters (handles both vehicles and placeables)
    self:calculateCreditParameters()

    -- Load eligible trade-in vehicles (vehicles only)
    if self.itemType == "vehicle" then
        self:loadEligibleTradeIns()
    end
end

--[[
    Set initial mode (called from shop extension)
]]
function UnifiedPurchaseDialog:setInitialMode(mode)
    self.currentMode = mode or UnifiedPurchaseDialog.MODE_CASH

    UsedPlus.logDebug(string.format("  setInitialMode: Setting mode to %d", self.currentMode))
    UsedPlus.logDebug(string.format("    modeSelector exists: %s", tostring(self.modeSelector ~= nil)))

    if self.modeSelector then
        self.modeSelector:setState(self.currentMode)
        UsedPlus.logDebug(string.format("    modeSelector state set to %d", self.currentMode))
    else
        UsedPlus.logWarn("    WARNING: modeSelector is nil! Cannot set initial mode!")
    end
end

--[[
    v2.0.0: Helper function to check if credit system is enabled
    REFACTORED: Delegate to CreditCalculations module (backward compatibility wrapper)
]]
function UnifiedPurchaseDialog.isCreditSystemEnabled()
    return CreditCalculations.isCreditSystemEnabled()
end

--[[
    Calculate credit parameters
    v2.0.0: Respects enableCreditSystem setting
    v2.7.0: Updates available term options based on credit
    v2.8.0: Handles placeable financing (requires 750+ credit - Excellent tier)
]]
function UnifiedPurchaseDialog:calculateCreditParameters()
    local farmId = g_currentMission:getFarmId()

    -- Delegate to CreditCalculations module
    CreditCalculations.calculate(self.context, farmId)

    -- Sync shadow fields (will be removed in Step 9)
    self.creditScore = self.context.creditScore
    self.creditRating = self.context.creditRating
    self.interestRate = self.context.interestRate
    self.canFinance = self.context.canFinance
    self.financeMinScore = self.context.financeMinScore
    self.canLease = self.context.canLease
    self.leaseMinScore = self.context.leaseMinScore

    -- v2.7.0: Update term options based on credit score
    self:updateTermOptionsForCredit()

    -- v2.7.1: Update down payment options based on credit score
    self:updateDownPaymentOptionsForCredit()
end

--[[
    Update finance term slider options based on credit score
    v2.7.0: Longer terms require better credit
    - 1-5 years: Any credit (300+)
    - 6-10 years: Fair credit (650+)
    - 11-15 years: Good credit (700+)
]]
function UnifiedPurchaseDialog:updateTermOptionsForCredit()
    if not self.financeTermSlider then
        return
    end

    -- Delegate to CreditCalculations module
    local availableTerms = CreditCalculations.getAvailableTerms(self.context)
    local maxYears = CreditCalculations.getMaxTermForCredit(self.context.creditScore)

    -- Sync shadow field (will be removed in Step 9)
    self.availableFinanceTerms = self.context.availableFinanceTerms

    -- Build texts for available terms
    local texts = {}
    for _, years in ipairs(availableTerms) do
        table.insert(texts, years .. (years == 1 and " Year" or " Years"))
    end

    -- If better credit would unlock more terms, show hint
    if maxYears < 15 then
        local nextTier = nil
        for _, tier in ipairs(CreditCalculations.TERM_CREDIT_REQUIREMENTS) do
            if tier.maxYears > maxYears then
                nextTier = tier
                break
            end
        end
        if nextTier then
            UsedPlus.logDebug(string.format("Credit %d allows up to %d year terms. Score %d+ unlocks %d years.",
                self.context.creditScore, maxYears, nextTier.minCredit, nextTier.maxYears))
        end
    end

    self.financeTermSlider:setTexts(texts)

    -- Ensure current selection is valid
    if self.context.financeTermIndex > #availableTerms then
        self.context.financeTermIndex = #availableTerms
    end
    self.financeTermSlider:setState(self.context.financeTermIndex)

    -- Sync shadow field
    self.financeTermIndex = self.context.financeTermIndex
end

--[[
    Update down payment slider options based on credit score
    v2.7.1: Lower down payments require better credit
    - Very Poor (<600): 25%+ down required
    - Poor (600-649): 20%+ down required
    - Fair (650-699): 10%+ down required
    - Good (700-749): 5%+ down required
    - Excellent (750+): 0% down available
]]
function UnifiedPurchaseDialog:updateDownPaymentOptionsForCredit()
    -- Delegate to CreditCalculations module
    local availableOptions = CreditCalculations.getAvailableDownPayments(self.context)
    local minDown = CreditCalculations.getMinDownPaymentForCredit(self.context.creditScore)

    -- Sync shadow fields (will be removed in Step 9)
    self.availableFinanceDownOptions = self.context.availableFinanceDownOptions
    self.availableLeaseDownOptions = self.context.availableLeaseDownOptions

    -- Build texts for available options
    local texts = {}
    for _, pct in ipairs(availableOptions) do
        table.insert(texts, pct .. "%")
    end

    -- Log what's available
    if minDown > 0 then
        UsedPlus.logDebug(string.format("Credit %d requires minimum %d%% down payment. Available options: %s",
            self.context.creditScore, minDown, table.concat(texts, ", ")))
    end

    -- Update finance down payment slider
    if self.financeDownSlider then
        self.financeDownSlider:setTexts(texts)

        -- Ensure current selection is valid
        if self.context.financeDownIndex > #availableOptions then
            self.context.financeDownIndex = 1  -- Reset to minimum (first option)
        end
        self.financeDownSlider:setState(self.context.financeDownIndex)

        -- Sync shadow field
        self.financeDownIndex = self.context.financeDownIndex
    end

    -- Update lease down payment slider (same logic)
    if self.leaseDownSlider then
        self.leaseDownSlider:setTexts(texts)

        -- Ensure current selection is valid
        if self.context.leaseDownIndex > #availableOptions then
            self.context.leaseDownIndex = 1  -- Reset to minimum
        end
        self.leaseDownSlider:setState(self.context.leaseDownIndex)

        -- Sync shadow field
        self.leaseDownIndex = self.context.leaseDownIndex
    end
end

--[[
    Get selected finance term in years (from credit-filtered options)
    @return years
]]
function UnifiedPurchaseDialog:getSelectedTermYears()
    local terms = self.availableFinanceTerms or UnifiedPurchaseDialog.getFinanceTermsForCredit(self.creditScore)
    return terms[self.financeTermIndex] or 5
end

--[[
    Check if current mode is available based on credit score and minimum amounts
    @return isAvailable (boolean), message (string or nil)
]]
function UnifiedPurchaseDialog:isModeAvailable()
    -- Delegate to CreditCalculations module
    return CreditCalculations.isModeAvailable(self.context, self.context.currentMode)
end

--[[
    Calculate credit score modifier for trade-in values
    Better credit = higher trade-in offer (dealers trust you more for financing)

    Trade-in value hierarchy (must be LESS than agent sales!):
    - Trade-In: baseTradeInPercent to baseTradeInPercent+15% (instant, convenient)
    - Local Agent: 60-75% (1-2 months wait)
    - Regional Agent: 75-90% (2-4 months wait)
    - National Agent: 90-100% (3-6 months wait)

    v2.6.2: Now uses baseTradeInPercent setting (default 55%)
    Credit adds bonus on top (up to +15% for excellent credit):
    - 800-850: Exceptional -> base + 15%
    - 740-799: Very Good   -> base + 11%
    - 670-739: Good        -> base + 7%
    - 580-669: Fair        -> base + 3%
    - 300-579: Poor        -> base + 0%

    Condition (damage + wear) further reduces value by up to 30%
]]
function UnifiedPurchaseDialog:getCreditTradeInMultiplier()
    -- Delegate to CreditCalculations module
    return CreditCalculations.getTradeInMultiplier(self.context)
end

--[[
    Load vehicles eligible for trade-in
    Trade-in values are adjusted based on:
    1. Credit score (determines base percentage 50-65%)
    2. Vehicle condition (damage + wear reduce value further)
    Always less than agent sale values (convenience tradeoff)
]]
function UnifiedPurchaseDialog:loadEligibleTradeIns()
    local farmId = g_currentMission:getFarmId()

    -- Delegate to TradeInHandler module
    TradeInHandler.loadEligible(self.context, farmId)

    -- Sync shadow field (will be removed in Step 9)
    self.eligibleTradeIns = self.context.eligibleTradeIns

    -- Update trade-in selector
    self:updateTradeInSelector()
end

--[[
    Update trade-in vehicle selector dropdown
]]
function UnifiedPurchaseDialog:updateTradeInSelector()
    if self.tradeInVehicleSelector then
        local texts = {"None"}  -- First option is always "None"

        for _, item in ipairs(self.eligibleTradeIns) do
            local shortName = item.name
            if #shortName > 30 then
                shortName = string.sub(shortName, 1, 28) .. ".."
            end
            -- Don't show price here - it's displayed separately below the selector
            table.insert(texts, shortName)
        end

        self.tradeInVehicleSelector:setTexts(texts)
        self.tradeInVehicleSelector:setState(1)  -- Default to "None"
    end
end

--[[
    Called when dialog opens
]]
function UnifiedPurchaseDialog:onOpen()
    -- SAFETY: Clear bypass flag if it's somehow still set
    -- Defensive programming - flag should already be cleared, but just in case
    if UsedPlus.bypassPlaceableCancellation then
        UsedPlus.logWarn("  ⚠️  bypassPlaceableCancellation still set on onOpen! Clearing...")
        UsedPlus.bypassPlaceableCancellation = nil
    end

    UnifiedPurchaseDialog:superClass().onOpen(self)

    -- IMPORTANT FIX 2.1: Reset context to clear stale state from previous purchase
    -- This prevents mode/term/down payment from persisting between purchases
    if self.context and self.context.reset then
        self.context:reset()
        UsedPlus.logDebug("UnifiedPurchaseDialog: Context reset (cleared stale state)")
    end

    -- Reset trade-in state in context
    TradeInHandler.setTradeIn(self.context, nil)

    -- Sync shadow fields (will be removed in Step 9)
    self.tradeInEnabled = false
    self.tradeInVehicle = nil
    self.tradeInValue = 0

    -- Reset selector to "None"
    if self.tradeInVehicleSelector then
        self.tradeInVehicleSelector:setState(1)
    end

    -- Hide trade-in details container (no vehicle selected initially)
    if self.tradeInDetailsContainer then
        self.tradeInDetailsContainer:setVisible(false)
    end

    -- Reset cash back to $0 and update options (no equity = no cash back allowed)
    self.financeCashBackIndex = 1
    self:updateCashBackOptions()

    -- Update display
    self:updateDisplay()
    self:updateSectionVisibility()
end

--[[
    Override close to clean up pending placeable state
    Critical for preventing free buildings when user ESC's from confirmation
]]
function UnifiedPurchaseDialog:close()
    UsedPlus.logInfo("╔════════════════════════════════════════════════════════════════")
    UsedPlus.logInfo("║ UnifiedPurchaseDialog:close() ENTRY")
    UsedPlus.logInfo("╠════════════════════════════════════════════════════════════════")

    -- CRITICAL: Clear bypass flag to re-enable placement cancellation handling
    -- This flag was set when showGui() was called to prevent ghost deletion
    -- Now that dialog is closing, normal cancellation behavior should resume
    if UsedPlus.bypassPlaceableCancellation then
        UsedPlus.logInfo("  → Clearing bypassPlaceableCancellation flag")
        UsedPlus.bypassPlaceableCancellation = nil
    end

    -- Capture current state for debugging
    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)
    local currentBalance = farm and farm.money or 0

    UsedPlus.logDebug(string.format("  Current balance: %s (Farm %d)",
        g_i18n:formatMoney(currentBalance), farmId))
    UsedPlus.logDebug(string.format("  pendingPlaceableData exists: %s",
        tostring(UsedPlus.pendingPlaceableData ~= nil)))
    UsedPlus.logDebug(string.format("  bypassPlaceableHook: %s",
        tostring(UsedPlus.bypassPlaceableHook)))
    UsedPlus.logDebug(string.format("  pendingPlaceableFinance exists: %s",
        tostring(UsedPlus.pendingPlaceableFinance ~= nil)))

    -- Clean up pending placeable data to prevent accidental free placement
    if UsedPlus.pendingPlaceableData then
        UsedPlus.logInfo("  → Clearing pendingPlaceableData to prevent free placement")
        UsedPlus.pendingPlaceableData = nil
    end

    if UsedPlus.bypassPlaceableHook then
        UsedPlus.logDebug("  → Clearing bypassPlaceableHook flag")
        UsedPlus.bypassPlaceableHook = nil
    end

    -- Clean up pending finance state (critical for temp money cleanup on ESC)
    if UsedPlus.pendingPlaceableFinance then
        local pending = UsedPlus.pendingPlaceableFinance

        UsedPlus.logInfo("  → Found pendingPlaceableFinance, analyzing...")
        UsedPlus.logDebug(string.format("     - itemName: %s", tostring(pending.itemName)))
        UsedPlus.logDebug(string.format("     - price: %s", g_i18n:formatMoney(pending.price or 0)))
        UsedPlus.logDebug(string.format("     - downPayment: %s", g_i18n:formatMoney(pending.downPayment or 0)))
        UsedPlus.logDebug(string.format("     - tempMoneyInjected: %s", g_i18n:formatMoney(pending.tempMoneyInjected or 0)))
        UsedPlus.logDebug(string.format("     - placementActive: %s", tostring(pending.placementActive)))
        UsedPlus.logDebug(string.format("     - farmId: %d", pending.farmId or 0))

        -- If temp money was injected but placement never started, reclaim it
        if pending.tempMoneyInjected and pending.tempMoneyInjected > 0 and pending.placementActive then
            UsedPlus.logInfo(string.format("  → RECLAIMING TEMP MONEY: %s (ESC during pending state)",
                g_i18n:formatMoney(pending.tempMoneyInjected)))
            UsedPlus.logDebug(string.format("     Balance BEFORE reclaim: %s",
                g_i18n:formatMoney(currentBalance)))

            g_currentMission:addMoney(-pending.tempMoneyInjected, pending.farmId, MoneyType.OTHER, true, false)

            -- Verify reclaim worked
            local farm2 = g_farmManager:getFarmById(pending.farmId)
            local newBalance = farm2 and farm2.money or 0
            UsedPlus.logDebug(string.format("     Balance AFTER reclaim: %s",
                g_i18n:formatMoney(newBalance)))
            UsedPlus.logDebug(string.format("     Expected balance: %s",
                g_i18n:formatMoney(currentBalance - pending.tempMoneyInjected)))

            if math.abs(newBalance - (currentBalance - pending.tempMoneyInjected)) < 1 then
                UsedPlus.logInfo("     ✓ Temp money reclaim VERIFIED")
            else
                UsedPlus.logWarn(string.format("     ✗ Temp money reclaim MISMATCH! Expected %s, got %s",
                    g_i18n:formatMoney(currentBalance - pending.tempMoneyInjected),
                    g_i18n:formatMoney(newBalance)))
            end
        else
            UsedPlus.logDebug("     No temp money to reclaim (already reconciled or none injected)")
        end

        UsedPlus.logInfo("  → Clearing pendingPlaceableFinance")
        UsedPlus.pendingPlaceableFinance = nil
    end

    UsedPlus.logInfo("║ UnifiedPurchaseDialog:close() EXIT - Calling superclass")
    UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")

    -- Call parent close
    UnifiedPurchaseDialog:superClass().close(self)
end

--[[
    Mode selector changed
    v2.6.2: Validates mode against settings and credit score
]]
function UnifiedPurchaseDialog:onModeChanged()
    UsedPlus.logInfo("═══════════════════════════════════════════════════════════")
    UsedPlus.logInfo("UnifiedPurchaseDialog:onModeChanged() - MODE SELECTOR CLICKED")
    UsedPlus.logInfo("═══════════════════════════════════════════════════════════")

    if self.modeSelector then
        local newMode = self.modeSelector:getState()
        UsedPlus.logInfo(string.format("  Current mode: %d | New mode: %d", self.currentMode or 0, newMode))
        UsedPlus.logInfo(string.format("  itemType: %s", tostring(self.itemType)))
        UsedPlus.logInfo(string.format("  canFinance: %s", tostring(self.canFinance)))
        UsedPlus.logInfo(string.format("  creditScore: %d", self.creditScore or 0))

        -- v2.6.2: Check if Finance mode is allowed
        if newMode == UnifiedPurchaseDialog.MODE_FINANCE then
            if not self.financeSystemEnabled then
                -- Finance system disabled in settings
                InfoDialog.show(g_i18n:getText("usedplus_finance_disabled_msg") or "Vehicle financing is disabled in UsedPlus settings.")
                self.modeSelector:setState(self.currentMode)  -- Revert to previous mode
                return
            elseif not self.canFinance then
                -- v2.8.0: Placeable-specific message (Excellent credit required)
                if self.itemType == "placeable" then
                    local msgTemplate = g_i18n:getText("usedplus_credit_tooLowForPlaceable") or
                        "Building financing requires Excellent credit (%d+).\nYour credit: %d (%s)"
                    InfoDialog.show(string.format(
                        msgTemplate,
                        self.financeMinScore or 750,
                        self.creditScore or 0,
                        self.creditRating or "Unknown"
                    ))
                else
                    -- Credit score too low for vehicles
                    InfoDialog.show(string.format(g_i18n:getText("usedplus_finance_credit_msg") or "Financing requires a credit score of %d or higher.", self.financeMinScore or 550))
                end
                self.modeSelector:setState(self.currentMode)
                return
            end
        end

        -- v2.6.2: Check if Lease mode is allowed (vehicles only)
        -- v2.8.0: Placeables don't show lease option, so this only applies to vehicles
        if newMode == UnifiedPurchaseDialog.MODE_LEASE then
            if not self.leaseSystemEnabled then
                -- Lease system disabled in settings
                InfoDialog.show(g_i18n:getText("usedplus_lease_disabled_msg") or "Vehicle leasing is disabled in UsedPlus settings.")
                self.modeSelector:setState(self.currentMode)
                return
            elseif not self.canLease then
                -- Credit score too low
                InfoDialog.show(string.format(g_i18n:getText("usedplus_lease_credit_msg") or "Leasing requires a credit score of %d or higher.", self.leaseMinScore or 600))
                self.modeSelector:setState(self.currentMode)
                return
            end
        end

        self.currentMode = newMode
    end

    self:updateSectionVisibility()
    self:updateDisplay()
end

--[[
    Trade-in vehicle selection changed
    Index 1 = "None", Index 2+ = vehicles from eligibleTradeIns
]]
function UnifiedPurchaseDialog:onTradeInVehicleChanged()
    local index = 1
    if self.tradeInVehicleSelector then
        index = self.tradeInVehicleSelector:getState()
    end

    UsedPlus.logInfo("UnifiedPurchaseDialog:onTradeInVehicleChanged() called - index=" .. tostring(index))

    -- Index 1 = "None" selected
    if index == 1 then
        -- Clear trade-in in context
        TradeInHandler.setTradeIn(self.context, nil)

        -- Sync shadow fields (will be removed in Step 9)
        self.tradeInEnabled = false
        self.tradeInVehicle = nil
        self.tradeInValue = 0

        -- Hide entire trade-in details container
        if self.tradeInDetailsContainer then
            self.tradeInDetailsContainer:setVisible(false)
        end
    else
        -- Index 2+ = vehicle selected (subtract 1 for eligibleTradeIns array)
        local vehicleIndex = index - 1
        local item = TradeInHandler.getItemByIndex(self.context, vehicleIndex)

        UsedPlus.logInfo("  vehicleIndex=" .. tostring(vehicleIndex) .. ", item=" .. tostring(item ~= nil))

        if item then
            UsedPlus.logInfo("  item.name=" .. tostring(item.name) .. ", item.value=" .. tostring(item.value))
            UsedPlus.logInfo("  Elements bound: tradeInDetailsContainer=" .. tostring(self.tradeInDetailsContainer ~= nil) ..
                ", tradeInNameText=" .. tostring(self.tradeInNameText ~= nil) ..
                ", tradeInImage=" .. tostring(self.tradeInImage ~= nil))

            -- Set trade-in in context
            TradeInHandler.setTradeIn(self.context, item.vehicle)

            -- Sync shadow fields (will be removed in Step 9)
            self.tradeInEnabled = true
            self.tradeInVehicle = item.vehicle
            self.tradeInValue = item.value

            -- Show trade-in details container
            if self.tradeInDetailsContainer then
                self.tradeInDetailsContainer:setVisible(true)
            end

            -- Update trade-in name
            if self.tradeInNameText then
                self.tradeInNameText:setText(item.name or "")
            end

            -- Update trade-in image
            if self.tradeInImage then
                local storeItem = g_storeManager:getItemByXMLFilename(item.vehicle.configFileName)
                UIHelper.Image.setStoreItemImage(self.tradeInImage, storeItem)
            end

            -- Update condition display - Line 1: Repair status
            if self.tradeInConditionText then
                local repairText = string.format("Repair: %d%%", item.repairPercent or 100)
                if (item.repairPercent or 100) < 70 then
                    repairText = repairText .. " (damaged)"
                end
                self.tradeInConditionText:setText(repairText)
            end

            -- Update condition display - Line 2: Paint status
            if self.tradeInCondition2Text then
                local paintText = string.format("Paint: %d%%", item.paintPercent or 100)
                if (item.paintPercent or 100) < 70 then
                    paintText = paintText .. " (worn)"
                end
                self.tradeInCondition2Text:setText(paintText)
            end

            -- Update hours display
            if self.tradeInHoursText then
                local hours = math.floor((item.operatingHours or 0) / 3600000)  -- ms to hours
                self.tradeInHoursText:setText(string.format("Hours: %d", hours))
            end

            -- Update value percentage (what % of sell price this represents)
            if self.tradeInPercentText then
                local sellPrice = item.sellPrice or 0
                local percentOfSell = 0
                if sellPrice > 0 then
                    percentOfSell = math.floor((item.value / sellPrice) * 100)
                end
                self.tradeInPercentText:setText(string.format("(%d%% of sell value)", percentOfSell))
            end

            -- Update credit impact display
            if self.tradeInCreditText then
                -- v2.6.2: Use baseTradeInPercent as fallback instead of hardcoded 50%
                local baseFallback = (UsedPlusSettings and UsedPlusSettings:get("baseTradeInPercent") or 55) / 100
                local creditPct = math.floor((item.creditMultiplier or baseFallback) * 100)
                local condPct = math.floor((item.conditionMultiplier or 1.0) * 100)
                self.tradeInCreditText:setText(string.format("Credit: %d%% | Cond: %d%%", creditPct, condPct))
            end
        else
            -- Invalid index - clear trade-in
            TradeInHandler.setTradeIn(self.context, nil)

            -- Sync shadow fields
            self.tradeInEnabled = false
            self.tradeInVehicle = nil
            self.tradeInValue = 0

            -- Hide trade-in details container
            if self.tradeInDetailsContainer then
                self.tradeInDetailsContainer:setVisible(false)
            end
        end
    end

    -- Update cash back options (max is 50% of down payment + trade-in)
    self:updateCashBackOptions()
    self:updateDisplay()
end

--[[
    Finance term changed
]]
function UnifiedPurchaseDialog:onFinanceTermChanged()
    if self.financeTermSlider then
        self.financeTermIndex = self.financeTermSlider:getState()
    end
    self:updateDisplay()
end

--[[
    Finance down payment changed
]]
function UnifiedPurchaseDialog:onFinanceDownChanged()
    if self.financeDownSlider then
        self.financeDownIndex = self.financeDownSlider:getState()
    end
    -- Update cash back options (max is 50% of down payment + trade-in)
    self:updateCashBackOptions()
    self:updateDisplay()
end

--[[
    Finance cash back changed
]]
function UnifiedPurchaseDialog:onFinanceCashBackChanged()
    if self.financeCashBackSlider then
        self.financeCashBackIndex = self.financeCashBackSlider:getState()
    end
    self:updateDisplay()
end

--[[
    Update cash back options based on down payment + trade-in value
    Rule: Cash back cannot exceed 50% of (down payment amount + trade-in value)
    If no down payment and no trade-in, cash back must be $0
]]
function UnifiedPurchaseDialog:updateCashBackOptions()
    if not self.financeCashBackSlider then
        return
    end

    -- Calculate down payment amount (percentage of vehicle price, using filtered options)
    local downPct = UnifiedPurchaseDialog.getDownPaymentPercent(self.financeDownIndex, self.creditScore)
    local downPaymentAmount = self.vehiclePrice * (downPct / 100)

    -- Calculate max allowed cash back: 50% of (down payment + trade-in)
    local totalEquity = downPaymentAmount + (self.tradeInValue or 0)
    local maxCashBack = math.floor(totalEquity * 0.50)

    -- Build filtered options list (only values <= maxCashBack)
    local validOptions = {}
    local validIndices = {}
    for i, amount in ipairs(UnifiedPurchaseDialog.CASH_BACK_OPTIONS) do
        if amount <= maxCashBack then
            table.insert(validOptions, amount)
            table.insert(validIndices, i)
        end
    end

    -- Always ensure at least $0 option exists
    if #validOptions == 0 then
        validOptions = {0}
        validIndices = {1}
    end

    -- Build text labels for dropdown
    local texts = {}
    for _, amount in ipairs(validOptions) do
        table.insert(texts, g_i18n:formatMoney(amount, 0, true, true))
    end

    -- Store valid options for lookup when confirming purchase
    self.validCashBackOptions = validOptions

    -- Update dropdown
    self.financeCashBackSlider:setTexts(texts)

    -- Adjust current selection if it's now out of bounds
    if self.financeCashBackIndex > #validOptions then
        self.financeCashBackIndex = #validOptions  -- Select highest valid option
    end
    self.financeCashBackSlider:setState(self.financeCashBackIndex)

    -- Debug log
    UsedPlus.logDebug(string.format("CashBack updated: downPmt=$%d + tradeIn=$%d = equity $%d, maxCashBack=$%d, options=%d",
        math.floor(downPaymentAmount), math.floor(self.tradeInValue or 0), math.floor(totalEquity), maxCashBack, #validOptions))
end

--[[
    Update down payment dropdown to show both percentage AND dollar amount
    This helps users understand "10% = 4,250 $" at a glance

    @param slider - The MultiTextOption element to update
    @param currentIndex - Current selected index to preserve
]]
function UnifiedPurchaseDialog:updateDownPaymentOptions(slider, currentIndex)
    if not slider then
        return
    end

    -- v2.9.1: Use credit-filtered options to match calculation logic
    -- Previously called getDownPaymentOptions() without creditScore, causing mismatch
    local options = UnifiedPurchaseDialog.getDownPaymentOptions(self.creditScore)
    local texts = {}
    for _, pct in ipairs(options) do
        local dollarAmount = self.vehiclePrice * (pct / 100)
        -- Format: "10% (4,250 $)" - using game's locale formatting
        local formatted = string.format("%d%% (%s)", pct, g_i18n:formatMoney(dollarAmount, 0, true, true))
        table.insert(texts, formatted)
    end

    slider:setTexts(texts)
    -- Ensure index is within bounds
    local safeIndex = math.min(currentIndex or 1, #options)
    slider:setState(safeIndex)
end

--[[
    Lease term changed
]]
function UnifiedPurchaseDialog:onLeaseTermChanged()
    if self.leaseTermSlider then
        self.leaseTermIndex = self.leaseTermSlider:getState()
    end
    self:updateDisplay()
end

--[[
    Lease down payment changed
]]
function UnifiedPurchaseDialog:onLeaseDownChanged()
    if self.leaseDownSlider then
        self.leaseDownIndex = self.leaseDownSlider:getState()
    end
    self:updateDisplay()
end

--[[
    Update section visibility based on current mode
    v2.8.0: Hides trade-in section for placeables (not applicable)
]]
function UnifiedPurchaseDialog:updateSectionVisibility()
    local isCash = (self.currentMode == UnifiedPurchaseDialog.MODE_CASH)
    local isFinance = (self.currentMode == UnifiedPurchaseDialog.MODE_FINANCE)
    local isLease = (self.currentMode == UnifiedPurchaseDialog.MODE_LEASE)

    if self.cashSection then
        self.cashSection:setVisible(isCash)
    end

    if self.financeSection then
        self.financeSection:setVisible(isFinance)
    end

    if self.leaseSection then
        self.leaseSection:setVisible(isLease)
    end

    -- Hide trade-in section for placeables (only applicable to vehicles)
    -- When hidden, move payment sections up to eliminate gap
    local showTradeIn = (self.itemType == "vehicle")
    if self.tradeInSection then
        self.tradeInSection:setVisible(showTradeIn)
    end
    if self.tradeInVehicleSelector then
        self.tradeInVehicleSelector:setVisible(showTradeIn)
        self.tradeInVehicleSelector:setDisabled(not showTradeIn)
    end
    if self.tradeInDetailsContainer then
        self.tradeInDetailsContainer:setVisible(showTradeIn and self.tradeInEnabled)
    end

    -- Payment sections remain at XML default position (-510px) for both vehicles and placeables
    -- setPosition() breaks visibility, so we accept the empty space for placeables
    -- This is a reasonable UX tradeoff for code simplicity and maintainability

    -- Note: Dynamic dialog resizing not supported in FS25
    -- Dialog will remain at 820px tall, leaving some empty space for placeables
    -- This is acceptable - better than crashing or not showing payment sections
end

--[[
    Update all display elements
    Refactored to use UIHelper for consistent formatting
]]
function UnifiedPurchaseDialog:updateDisplay()
    -- Update dialog title based on item type
    if self.dialogTitleElement then
        local titleText = (self.itemType == "placeable")
            and (g_i18n:getText("usedplus_up_title_placeable") or "Purchase Building")
            or (g_i18n:getText("usedplus_up_title") or "Purchase Vehicle")
        self.dialogTitleElement:setText(titleText)
    end

    -- Item info
    UIHelper.Element.setText(self.itemNameText, self.vehicleName)
    UIHelper.Element.setText(self.itemPriceText, UIHelper.Text.formatMoney(self.vehiclePrice))
    UIHelper.Element.setText(self.itemCategoryText, self.vehicleCategory)

    -- Used badge
    UIHelper.Vehicle.displayUsedBadge(self.usedBadgeText, self.isUsedVehicle, self.usedCondition)

    -- Trade-in value (green - credit toward purchase)
    UIHelper.Finance.displayAssetValue(self.tradeInValueText, self.tradeInValue)

    -- Check if current mode is available (credit qualification)
    local modeAvailable, creditWarning = self:isModeAvailable()

    -- Show/hide credit warning
    if self.creditWarningText then
        if creditWarning then
            self.creditWarningText:setText(creditWarning)
            self.creditWarningText:setVisible(true)
            -- Red color for warning
            self.creditWarningText:setTextColor(1, 0.3, 0.3, 1)
        else
            self.creditWarningText:setVisible(false)
        end
    end

    -- Show/hide credit warning container (background)
    if self.creditWarningContainer then
        self.creditWarningContainer:setVisible(creditWarning ~= nil)
    end

    -- Enable/disable confirm button based on mode availability
    if self.confirmButton then
        self.confirmButton:setDisabled(not modeAvailable)
    end

    -- Update mode selector to show unavailable options with indicators
    self:updateModeSelectorTexts()

    -- Update mode-specific displays
    if self.currentMode == UnifiedPurchaseDialog.MODE_CASH then
        self:updateCashDisplay()
    elseif self.currentMode == UnifiedPurchaseDialog.MODE_FINANCE then
        self:updateFinanceDisplay()
    elseif self.currentMode == UnifiedPurchaseDialog.MODE_LEASE then
        self:updateLeaseDisplay()
    end
end

--[[
    Update mode selector texts to show which options are unavailable
    Adds visual indicators for credit-locked options
    v2.6.2: Now checks settings system for Finance/Lease toggles
    v2.8.0: Handles placeable-specific text (Excellent credit requirement, no lease)
]]
function UnifiedPurchaseDialog:updateModeSelectorTexts()
    if not self.modeSelector then return end

    -- v2.1.2: Preserve current state - setTexts() resets state to 1
    local currentState = self.currentMode or 1

    -- v2.6.2: Check settings for Finance/Lease system toggles
    local financeSystemEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Finance")
    local leaseSystemEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Lease")

    -- Store for mode validation
    self.financeSystemEnabled = financeSystemEnabled
    self.leaseSystemEnabled = leaseSystemEnabled

    local texts = {}
    local isPlaceable = (self.itemType == "placeable")

    -- Cash is always available
    table.insert(texts, g_i18n:getText("usedplus_mode_cash"))

    -- Finance - check system enabled first, then credit score
    if not financeSystemEnabled then
        table.insert(texts, g_i18n:getText("usedplus_mode_finance_disabled") or "Finance (Disabled)")
    elseif self.canFinance then
        table.insert(texts, g_i18n:getText("usedplus_mode_finance"))
    else
        -- v2.8.0: Placeables show "Excellent (750+)" requirement
        if isPlaceable then
            table.insert(texts, string.format("Finance (Excellent %d+)", self.financeMinScore or 750))
        else
            local template = g_i18n:getText("usedplus_mode_financeCredit")
            table.insert(texts, string.format(template, self.financeMinScore or 550))
        end
    end

    -- Lease - placeables cannot be leased (don't show option at all)
    -- v2.8.0: Placeable dialog only shows Cash and Finance
    if not isPlaceable then
        -- Only add lease option for vehicles
        if not leaseSystemEnabled then
            table.insert(texts, g_i18n:getText("usedplus_mode_lease_disabled") or "Lease (Disabled)")
        elseif self.canLease then
            table.insert(texts, g_i18n:getText("usedplus_mode_lease"))
        else
            local template = g_i18n:getText("usedplus_mode_leaseCredit")
            table.insert(texts, string.format(template, self.leaseMinScore or 600))
        end
    end

    self.modeSelector:setTexts(texts)

    -- v2.1.2: Restore state after setTexts() resets it
    -- v2.6.2: But redirect to Cash if current mode is disabled
    if currentState == UnifiedPurchaseDialog.MODE_FINANCE and not financeSystemEnabled then
        currentState = UnifiedPurchaseDialog.MODE_CASH
    elseif currentState == UnifiedPurchaseDialog.MODE_LEASE and not leaseSystemEnabled then
        currentState = UnifiedPurchaseDialog.MODE_CASH
    end

    self.currentMode = currentState
    self.modeSelector:setState(currentState)
end

--[[
    Update cash mode display
    Refactored to use UIHelper formatting
]]
function UnifiedPurchaseDialog:updateCashDisplay()
    local totalDue = self.vehiclePrice - self.tradeInValue

    UIHelper.Element.setText(self.cashPriceText, UIHelper.Text.formatMoney(self.vehiclePrice))

    -- Trade-in credit (shown as negative)
    if self.tradeInEnabled and self.tradeInValue > 0 then
        UIHelper.Element.setTextWithColor(self.cashTradeInText,
            "-" .. UIHelper.Text.formatMoney(self.tradeInValue), UIHelper.Colors.MONEY_GREEN)
    else
        UIHelper.Element.setText(self.cashTradeInText, "-" .. UIHelper.Text.formatMoney(0))
    end

    -- Total due (or refund if negative)
    if totalDue < 0 then
        UIHelper.Element.setTextWithColor(self.cashTotalText,
            "+" .. UIHelper.Text.formatMoney(math.abs(totalDue)) .. " REFUND", UIHelper.Colors.MONEY_GREEN)
    else
        UIHelper.Element.setText(self.cashTotalText, UIHelper.Text.formatMoney(totalDue))
    end
end

--[[
    Update finance mode display
    Refactored to use UIHelper formatting
]]
function UnifiedPurchaseDialog:updateFinanceDisplay()
    local termYears = self:getSelectedTermYears()
    local downPct = UnifiedPurchaseDialog.getDownPaymentPercent(self.financeDownIndex, self.creditScore)
    -- Use filtered cash back options (limited by down payment + trade-in)
    local cashBack = (self.validCashBackOptions and self.validCashBackOptions[self.financeCashBackIndex]) or 0

    -- Down payment is cash paid today (percentage of vehicle price)
    local downPayment = self.vehiclePrice * (downPct / 100)

    -- Amount financed calculation:
    -- Start with vehicle price
    -- Subtract trade-in (reduces what you need to finance)
    -- Subtract down payment (cash you're putting down)
    -- Add cash back (increases loan amount)
    local amountFinanced = self.vehiclePrice - self.tradeInValue - downPayment + cashBack
    amountFinanced = math.max(0, amountFinanced)

    -- Due today = down payment MINUS cash back (cash out of pocket)
    -- Trade-in does NOT reduce due today - it reduces amount financed
    -- Cash back DOES reduce due today - the extra loan covers part of your down payment
    -- v2.9.1: Fixed - cashback should reduce the amount due today
    local dueTodayAmount = math.max(0, downPayment - cashBack)

    -- Use centralized calculation function
    local termMonths = termYears * 12
    local monthlyPayment, totalInterest = FinanceCalculations.calculateMonthlyPayment(
        math.max(0, amountFinanced),
        self.interestRate,
        termMonths
    )

    -- Update UI with UIHelper
    UIHelper.Element.setText(self.financeAmountText, UIHelper.Text.formatMoney(math.max(0, amountFinanced)))
    UIHelper.Element.setText(self.financeRateText, UIHelper.Text.formatInterestRateWithRating(self.interestRate, self.creditRating))
    UIHelper.Finance.displayMonthlyPayment(self.financeMonthlyText, monthlyPayment)

    -- Update down payment dropdown to show dollar amounts (e.g., "10% (4,250 $)")
    self:updateDownPaymentOptions(self.financeDownSlider, self.financeDownIndex)

    UIHelper.Element.setTextWithColor(self.financeTotalInterestText,
        UIHelper.Text.formatMoney(math.max(0, totalInterest)), UIHelper.Colors.COST_ORANGE)
    UIHelper.Element.setText(self.financeDueTodayText, UIHelper.Text.formatMoney(dueTodayAmount))

    -- v2.0.0: Only show credit score if credit system enabled
    if UnifiedPurchaseDialog.isCreditSystemEnabled() then
        UIHelper.Element.setText(self.financeCreditText, UIHelper.Text.formatCreditScore(self.creditScore, self.creditRating))
        UIHelper.Element.setVisible(self.financeCreditText, true)
    else
        UIHelper.Element.setVisible(self.financeCreditText, false)
    end
end

--[[
    Update lease mode display
    Refactored to use UIHelper formatting

    LEASE ECONOMICS:
    - You pay for DEPRECIATION during the lease term, not the full vehicle value
    - Cap reduction (down payment) is a percentage of DEPRECIATION, not vehicle price
    - This makes leasing more affordable and economically sensible
    - At end of lease: return vehicle OR pay residual (buyout) to keep it
    - Lease payments build equity toward the buyout
    - Security deposit is credit-based (automatic, not selectable)

    IMPORTANT: Capitalized cost must never go below residual value, or we get
    negative depreciation (impossible scenario). If trade-in + cap reduction
    would push capitalized cost below residual, we cap it at residual.
]]
function UnifiedPurchaseDialog:updateLeaseDisplay()
    -- LEASE_TERMS now stores months directly
    local termMonths = UnifiedPurchaseDialog.LEASE_TERMS[self.leaseTermIndex] or 12
    local termYears = termMonths / 12  -- For residual value calculation
    local capReductionPct = UnifiedPurchaseDialog.getDownPaymentPercent(self.leaseDownIndex, self.creditScore)

    -- Calculate residual value first (what vehicle is worth at end of lease)
    local residualValue = FinanceCalculations.calculateResidualValue(self.vehiclePrice, termYears)

    -- Depreciation = what you're "using up" during the lease
    local depreciation = self.vehiclePrice - residualValue

    -- Cap reduction is a percentage of VEHICLE PRICE (like a down payment)
    -- This keeps the upfront cost consistent regardless of lease term
    -- Longer terms = lower monthly but same upfront if same % selected
    local capReduction = self.vehiclePrice * (capReductionPct / 100)

    -- Capitalized cost = vehicle price - trade-in - cap reduction
    -- CRITICAL: Capitalized cost must be >= residual value to avoid negative depreciation
    -- If trade-in is very large, we cap the benefit to prevent impossible scenarios
    local rawCapitalizedCost = self.vehiclePrice - self.tradeInValue - capReduction
    local capitalizedCost = math.max(residualValue, rawCapitalizedCost)

    -- Track if trade-in exceeds what can be applied (would go to refund/equity)
    local tradeInExcess = math.max(0, residualValue - rawCapitalizedCost)

    -- Monthly payment calculation (will always be non-negative now)
    local monthlyPayment = FinanceCalculations.calculateLeasePayment(
        capitalizedCost,
        residualValue,
        self.interestRate,
        termMonths
    )

    -- Extra safety: ensure monthly payment is never negative
    monthlyPayment = math.max(0, monthlyPayment)

    -- Security deposit = credit-based months of lease payment (automatic)
    local securityDeposit, depositMonths, depositTierName = FinanceCalculations.calculateSecurityDeposit(
        monthlyPayment, self.creditScore)

    -- Total lease cost = all monthly payments + cap reduction + security deposit
    local totalLeaseCost = monthlyPayment * termMonths + capReduction + securityDeposit

    -- Due today = cap reduction + security deposit (cash out of pocket)
    -- Trade-in does NOT reduce due today - it reduces capitalized cost
    local dueTodayAmount = capReduction + securityDeposit

    -- Store for executeLeasePurchase
    self.calculatedSecurityDeposit = securityDeposit
    self.calculatedDepositMonths = depositMonths

    -- Update UI with UIHelper
    UIHelper.Finance.displayMonthlyPayment(self.leaseMonthlyText, monthlyPayment)
    UIHelper.Element.setText(self.leaseRateText, UIHelper.Text.formatInterestRateWithRating(self.interestRate, self.creditRating))
    UIHelper.Element.setText(self.leaseTotalText, UIHelper.Text.formatMoney(totalLeaseCost))
    UIHelper.Element.setText(self.leaseBuyoutText, UIHelper.Text.formatMoney(residualValue))

    -- v2.0.0: Only show credit score if credit system enabled
    if UnifiedPurchaseDialog.isCreditSystemEnabled() then
        UIHelper.Element.setText(self.leaseCreditText, UIHelper.Text.formatCreditScore(self.creditScore, self.creditRating))
        UIHelper.Element.setVisible(self.leaseCreditText, true)
    else
        UIHelper.Element.setVisible(self.leaseCreditText, false)
    end

    -- Update down payment dropdown to show dollar amounts (e.g., "10% (4,250 $)")
    self:updateDownPaymentOptions(self.leaseDownSlider, self.leaseDownIndex)

    -- Security deposit display (credit-based, not selectable)
    if self.leaseDepositText then
        local depositText
        if depositMonths == 0 then
            depositText = "No Deposit (" .. depositTierName .. " credit)"
        else
            depositText = string.format("%s (%d mo, %s)",
                UIHelper.Text.formatMoney(securityDeposit), depositMonths, depositTierName)
        end
        UIHelper.Element.setText(self.leaseDepositText, depositText)
    end

    -- Due today display (cap reduction + security deposit)
    local dueTodayText = UIHelper.Text.formatMoney(dueTodayAmount)

    -- v2.11.0: Show trade-in excess warning when residual value limits trade-in benefit
    -- This helps players understand why their trade-in didn't reduce monthly payment
    if tradeInExcess > 100 then
        dueTodayText = dueTodayText .. string.format(
            "\n💡 Trade-in excess: %s → Lease-end equity",
            UIHelper.Text.formatMoney(math.floor(tradeInExcess))
        )
    end

    UIHelper.Element.setText(self.leaseDueTodayText, dueTodayText)

    -- Debug log
    UsedPlus.logDebug(string.format("Lease: price=$%d, depreciation=$%d, capRed=%d%% ($%d), deposit=$%d (%d mo), residual=$%d, monthly=$%d, tradeInExcess=$%d",
        self.vehiclePrice, math.floor(depreciation), capReductionPct, math.floor(capReduction),
        math.floor(securityDeposit), depositMonths, math.floor(residualValue), math.floor(monthlyPayment), math.floor(tradeInExcess)))
end

--[[
    Confirm purchase button clicked
    Shows confirmation dialog with transaction details before executing
]]
function UnifiedPurchaseDialog:onConfirmPurchase()
    -- Build confirmation message based on current mode
    local confirmMessage = self:buildConfirmationMessage()

    -- Show YesNo confirmation dialog
    -- Signature: YesNoDialog.show(callback, target, text, ...)
    YesNoDialog.show(
        function(yes)
            if yes then
                self:executeConfirmedPurchase()
            else
                -- User cancelled - clean up pending placeable state
                UsedPlus.logInfo("Purchase cancelled by user - cleaning up pending state")
                if UsedPlus.pendingPlaceableData then
                    UsedPlus.pendingPlaceableData = nil
                    UsedPlus.logDebug("Cleared pendingPlaceableData")
                end
                if UsedPlus.bypassPlaceableHook then
                    UsedPlus.bypassPlaceableHook = nil
                    UsedPlus.logDebug("Cleared bypassPlaceableHook")
                end
            end
        end,
        self,
        confirmMessage
    )
end

--[[
    Build confirmation message based on current mode
]]
function UnifiedPurchaseDialog:buildConfirmationMessage()
    local lines = {}

    table.insert(lines, "CONFIRM PURCHASE")
    table.insert(lines, "")
    table.insert(lines, string.format("Vehicle: %s", self.vehicleName))
    table.insert(lines, string.format("Price: %s", g_i18n:formatMoney(self.vehiclePrice)))
    table.insert(lines, "")

    if self.currentMode == UnifiedPurchaseDialog.MODE_CASH then
        -- Cash purchase
        local totalDue = self.vehiclePrice - self.tradeInValue
        table.insert(lines, "PURCHASE TYPE: Cash")
        if self.tradeInEnabled and self.tradeInValue > 0 then
            table.insert(lines, string.format("Trade-In Credit: -%s", g_i18n:formatMoney(self.tradeInValue)))
        end
        table.insert(lines, "")
        if totalDue < 0 then
            table.insert(lines, string.format("REFUND: +%s", g_i18n:formatMoney(math.abs(totalDue))))
        else
            table.insert(lines, string.format("TOTAL DUE NOW: %s", g_i18n:formatMoney(totalDue)))
        end

    elseif self.currentMode == UnifiedPurchaseDialog.MODE_FINANCE then
        -- Finance purchase
        local termYears = self:getSelectedTermYears()
        local downPct = UnifiedPurchaseDialog.getDownPaymentPercent(self.financeDownIndex, self.creditScore)
        local cashBack = (self.validCashBackOptions and self.validCashBackOptions[self.financeCashBackIndex]) or 0
        local downPayment = self.vehiclePrice * (downPct / 100)
        local amountFinanced = self.vehiclePrice - self.tradeInValue - downPayment + cashBack
        amountFinanced = math.max(0, amountFinanced)

        local termMonths = termYears * 12
        local monthlyPayment, totalInterest = FinanceCalculations.calculateMonthlyPayment(
            amountFinanced, self.interestRate, termMonths)

        table.insert(lines, "PURCHASE TYPE: Finance")
        table.insert(lines, string.format("Term: %d years (%d months)", termYears, termMonths))
        table.insert(lines, string.format("Interest Rate: %.2f%%", self.interestRate * 100))
        table.insert(lines, string.format("Amount Financed: %s", g_i18n:formatMoney(amountFinanced)))
        table.insert(lines, "")
        table.insert(lines, string.format("Monthly Payment: %s", g_i18n:formatMoney(monthlyPayment)))
        table.insert(lines, string.format("Total Interest: %s", g_i18n:formatMoney(totalInterest)))
        table.insert(lines, "")
        -- v2.9.1: Show cashback breakdown if applicable, and net due today
        local netDueToday = math.max(0, downPayment - cashBack)
        if cashBack > 0 then
            table.insert(lines, string.format("Down Payment: %s", g_i18n:formatMoney(downPayment)))
            table.insert(lines, string.format("Cash Back: -%s", g_i18n:formatMoney(cashBack)))
            table.insert(lines, string.format("DUE TODAY: %s", g_i18n:formatMoney(netDueToday)))
        else
            table.insert(lines, string.format("DUE TODAY: %s (down payment)", g_i18n:formatMoney(netDueToday)))
        end

    elseif self.currentMode == UnifiedPurchaseDialog.MODE_LEASE then
        -- Lease
        local termMonths = UnifiedPurchaseDialog.LEASE_TERMS[self.leaseTermIndex] or 36
        local termYears = termMonths / 12
        local capReductionPct = UnifiedPurchaseDialog.getDownPaymentPercent(self.leaseDownIndex, self.creditScore)
        local residualValue = FinanceCalculations.calculateResidualValue(self.vehiclePrice, termYears)
        local capReduction = self.vehiclePrice * (capReductionPct / 100)
        local capitalizedCost = math.max(residualValue, self.vehiclePrice - self.tradeInValue - capReduction)
        local monthlyPayment = FinanceCalculations.calculateLeasePayment(
            capitalizedCost, residualValue, self.interestRate, termMonths)
        monthlyPayment = math.max(0, monthlyPayment)
        local securityDeposit = self.calculatedSecurityDeposit or 0
        local totalDueToday = capReduction + securityDeposit

        table.insert(lines, "PURCHASE TYPE: Lease")
        table.insert(lines, string.format("Term: %d months", termMonths))
        table.insert(lines, string.format("Monthly Payment: %s", g_i18n:formatMoney(monthlyPayment)))
        table.insert(lines, string.format("Buyout at End: %s", g_i18n:formatMoney(residualValue)))
        table.insert(lines, "")
        if capReduction > 0 then
            table.insert(lines, string.format("Cap Reduction: %s", g_i18n:formatMoney(capReduction)))
        end
        if securityDeposit > 0 then
            table.insert(lines, string.format("Security Deposit: %s", g_i18n:formatMoney(securityDeposit)))
        end
        table.insert(lines, string.format("DUE TODAY: %s", g_i18n:formatMoney(totalDueToday)))
    end

    table.insert(lines, "")
    table.insert(lines, "Proceed with this transaction?")

    return table.concat(lines, "\n")
end

--[[
    Execute the confirmed purchase based on current mode
]]
function UnifiedPurchaseDialog:executeConfirmedPurchase()
    if self.currentMode == UnifiedPurchaseDialog.MODE_CASH then
        self:executeCashPurchase()
    elseif self.currentMode == UnifiedPurchaseDialog.MODE_FINANCE then
        self:executeFinancePurchase()
    elseif self.currentMode == UnifiedPurchaseDialog.MODE_LEASE then
        self:executeLeasePurchase()
    else
        UsedPlus.logError(string.format("Unknown purchase mode: %s", tostring(self.currentMode)))
    end
end

--[[
    Execute cash purchase

    Uses BuyVehicleData/BuyVehicleEvent for vehicles
    Uses BuyPlaceableData for placeables
    v2.8.0: Added placeable support
]]
function UnifiedPurchaseDialog:executeCashPurchase()
    -- Delegate to item-type-specific function
    if self.itemType == "placeable" then
        self:executeCashPurchasePlaceable()
    else
        self:executeCashPurchaseVehicle()
    end
end

--[[
    Execute cash purchase for vehicles
    Pattern from HirePurchasing mod (working reference).
]]
function UnifiedPurchaseDialog:executeCashPurchaseVehicle()
    -- Delegate to PurchaseExecutorVehicle module
    local success = PurchaseExecutorVehicle.executeCash(self.context, g_currentMission:getFarmId(), self.shopScreen)
    if success then
        self:close()
    end
end

function UnifiedPurchaseDialog:executeCashPurchaseVehicle_OLD()
    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)

    if not farm then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, g_i18n:getText("usedplus_error_farmNotFound"))
        return
    end

    local totalDue = self.vehiclePrice - self.tradeInValue

    -- Check if player can afford
    if totalDue > 0 and farm.money < totalDue then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_insufficientFundsGeneric"), g_i18n:formatMoney(totalDue, 0, true, true)))
        return
    end

    -- Handle trade-in first (adds money to player's account)
    if self.tradeInEnabled and self.tradeInVehicle then
        self:executeTradeIn()
    end

    -- Get configurations from shop screen
    local configurations = {}
    local configurationData = nil
    local licensePlateData = nil

    if self.shopScreen then
        configurations = self.shopScreen.configurations or {}
        configurationData = self.shopScreen.configurationData
        licensePlateData = self.shopScreen.licensePlateData
    elseif g_shopConfigScreen then
        configurations = g_shopConfigScreen.configurations or {}
        configurationData = g_shopConfigScreen.configurationData
        licensePlateData = g_shopConfigScreen.licensePlateData
    end

    -- Use BuyVehicleData/BuyVehicleEvent pattern (from HirePurchasing)
    if BuyVehicleData and BuyVehicleEvent and g_client then
        local event = BuyVehicleData.new()
        event:setOwnerFarmId(farmId)
        event:setPrice(totalDue)
        event:setStoreItem(self.storeItem)
        event:setConfigurations(configurations)

        if configurationData then
            event:setConfigurationData(configurationData)
        end
        if licensePlateData then
            event:setLicensePlateData(licensePlateData)
        end
        if self.saleItem then
            event:setSaleItem(self.saleItem)
        end

        g_client:getServerConnection():sendEvent(BuyVehicleEvent.new(event))

        UsedPlus.logDebug("Cash purchase: Sent BuyVehicleEvent for " .. tostring(self.vehicleName))
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notify_vehiclePurchased") or "Purchased %s for %s",
                self.vehicleName, g_i18n:formatMoney(math.max(0, totalDue))))
    else
        UsedPlus.logError("BuyVehicleData/BuyVehicleEvent not available - cannot complete cash purchase")
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_purchaseFailed") or "Purchase failed - game API not available")
    end

    self:close()
end

--[[
    Execute cash purchase for placeables
    v2.8.0: Uses stored BuyPlaceableData instance to trigger placement mode
]]
function UnifiedPurchaseDialog:executeCashPurchasePlaceable()
    UsedPlus.logInfo("╔════════════════════════════════════════════════════════════════")
    UsedPlus.logInfo("║ executeCashPurchasePlaceable() ENTRY - CASH PURCHASE")
    UsedPlus.logInfo("╠════════════════════════════════════════════════════════════════")

    -- v2.8.4: Check for PRE-BUY mode (user positioned, dialog shown before buy())
    if UsedPlus.pendingPlaceableBuy then
        UsedPlus.logInfo("✅ PRE-BUY MODE DETECTED - Delegating to PRE-BUY cash handler")
        PurchaseExecutorPlaceable.executePreBuyCash(g_currentMission:getFarmId(), self)
        return
    end

    UsedPlus.logWarn("⚠️  No pendingPlaceableBuy - falling back to OLD flow (shouldn't happen!)")

    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)

    UsedPlus.logDebug(string.format("  farmId: %d", farmId))
    UsedPlus.logDebug(string.format("  farm exists: %s", tostring(farm ~= nil)))

    if not farm then
        UsedPlus.logWarn("  ✗ Farm not found - ABORTING")
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, "Farm not found")
        return
    end

    local totalDue = self.vehiclePrice  -- No trade-in for placeables

    UsedPlus.logInfo(string.format("  Building: %s", tostring(self.vehicleName)))
    UsedPlus.logInfo(string.format("  Price: %s", g_i18n:formatMoney(totalDue)))
    UsedPlus.logInfo(string.format("  Current balance: %s", g_i18n:formatMoney(farm.money)))
    UsedPlus.logDebug(string.format("  Can afford: %s", tostring(farm.money >= totalDue)))

    -- Check if player can afford
    if totalDue > 0 and farm.money < totalDue then
        UsedPlus.logWarn(string.format("  ✗ Insufficient funds - ABORTING (need %s, have %s)",
            g_i18n:formatMoney(totalDue), g_i18n:formatMoney(farm.money)))
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format("Insufficient funds. Required: %s", g_i18n:formatMoney(totalDue, 0, true, true)))
        return
    end

    UsedPlus.logInfo("  ✓ Affordability check PASSED")

    -- Use the pending BuyPlaceableData instance stored by BuyPlaceableDataExtension
    UsedPlus.logDebug(string.format("  pendingPlaceableData exists: %s",
        tostring(UsedPlus.pendingPlaceableData ~= nil)))

    if UsedPlus.pendingPlaceableData then
        UsedPlus.logInfo("  → Using stored BuyPlaceableData instance")

        -- Get the stored instance
        local placeableData = UsedPlus.pendingPlaceableData
        UsedPlus.logDebug(string.format("     placeableData type: %s", type(placeableData)))
        UsedPlus.pendingPlaceableData = nil
        UsedPlus.logDebug("     Cleared pendingPlaceableData")

        -- CRITICAL: Hide dialog (don't close) to keep state alive during placement
        -- We'll close it after placement completes in PlaceableSystemExtension
        UsedPlus.logInfo("  → HIDING dialog (not closing) - will close after placement")
        self:setVisible(false)

        -- Store dialog reference for cleanup after placement
        UsedPlus.pendingPlaceableDialog = self

        UsedPlus.logInfo("  → Registering deferred buy() updateable")
        local deferredStartTime = g_currentMission.time

        -- Defer buy() to next frame using updateable (ensures clean GUI state)
        g_currentMission:addUpdateable({
            update = function(updatable, dt)
                local deferredElapsed = g_currentMission.time - deferredStartTime
                UsedPlus.logInfo("╔════════════════════════════════════════════════════════════════")
                UsedPlus.logInfo("║ DEFERRED CALLBACK - CASH PURCHASE")
                UsedPlus.logInfo("╠════════════════════════════════════════════════════════════════")
                UsedPlus.logDebug(string.format("  Deferred callback fired after: %.0fms", deferredElapsed))
                UsedPlus.logDebug(string.format("  dt: %.2fms", dt))

                g_currentMission:removeUpdateable(updatable)
                UsedPlus.logDebug("  Removed self from updateables")

                -- Verify state before proceeding
                local currentFarm = g_farmManager:getFarmById(farmId)
                if currentFarm then
                    UsedPlus.logDebug(string.format("  Current balance: %s", g_i18n:formatMoney(currentFarm.money)))
                end

                -- Set bypass flag so our hook doesn't intercept again
                UsedPlus.bypassPlaceableHook = true
                UsedPlus.logInfo("  → Set bypassPlaceableHook = true")

                -- Trigger placement mode - calls the hooked buy() which will see bypass flag
                -- and call the original vanilla function
                UsedPlus.logInfo("  → Calling placeableData:buy() - PLACEMENT MODE SHOULD START")
                placeableData:buy()

                UsedPlus.logInfo("  ✓ buy() call completed - placement mode active")
                UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")
            end
        })

        UsedPlus.logInfo("  ✓ Deferred updateable registered - returning control")
        UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")
    else
        UsedPlus.logWarn("  ✗ No pending BuyPlaceableData - using FALLBACK path (shouldn't happen)")

        -- Close dialog first
        UsedPlus.logInfo("  → Closing dialog")
        self:close()

        -- Fallback: create new instance (shouldn't happen normally)
        if BuyPlaceableData and g_client then
            UsedPlus.logDebug("  → Registering fallback deferred updateable")
            local deferredStartTime = g_currentMission.time

            g_currentMission:addUpdateable({
                update = function(updatable, dt)
                    local deferredElapsed = g_currentMission.time - deferredStartTime
                    UsedPlus.logInfo("╔════════════════════════════════════════════════════════════════")
                    UsedPlus.logInfo("║ DEFERRED CALLBACK - CASH FALLBACK")
                    UsedPlus.logInfo("╠════════════════════════════════════════════════════════════════")
                    UsedPlus.logDebug(string.format("  Deferred callback fired after: %.0fms", deferredElapsed))

                    g_currentMission:removeUpdateable(updatable)

                    UsedPlus.logDebug("  Creating new BuyPlaceableData event")
                    local event = BuyPlaceableData.new()
                    event:setOwnerFarmId(farmId)
                    event:setPrice(totalDue)
                    event:setStoreItem(self.storeItem)

                    -- Get configurations from shop screen
                    local configurations = {}
                    if self.shopScreen then
                        configurations = self.shopScreen.configurations or {}
                    elseif g_shopConfigScreen then
                        configurations = g_shopConfigScreen.configurations or {}
                    end
                    event:setConfigurations(configurations)
                    UsedPlus.logDebug("  Configurations set")

                    UsedPlus.bypassPlaceableHook = true
                    UsedPlus.logInfo("  → Calling event:buy()")
                    event:buy()
                    UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")
                end
            })
        else
            UsedPlus.logError("  ✗ BuyPlaceableData not available - CRITICAL FAILURE")
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                "Purchase failed - game API not available")
        end

        UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")
    end
end

--[[
    Spawn a vehicle using the game's shop system
    @param farmId - Owner farm
    @param price - Price to pay (0 for financed/leased)
    @return boolean - True if spawn succeeded
]]
function UnifiedPurchaseDialog:spawnVehicle(farmId, price)
    if not self.storeItem then
        UsedPlus.logError("No storeItem for vehicle spawn")
        return false
    end

    -- Try using the shop controller's buy method
    if g_currentMission.shopController and g_currentMission.shopController.buy then
        local success = pcall(function()
            g_currentMission.shopController:buy(self.storeItem, {}, farmId, price or 0)
        end)
        if success then
            UsedPlus.logDebug("Vehicle spawned via shopController:buy()")
            return true
        end
    end

    -- Fallback: Try direct VehicleLoadingUtil
    if VehicleLoadingUtil and VehicleLoadingUtil.loadVehicle then
        local x, y, z = self:getVehicleSpawnPosition()
        local success = pcall(function()
            VehicleLoadingUtil.loadVehicle(
                self.storeItem.xmlFilename,
                {x = x, y = y, z = z},
                true,   -- addPhysics
                0,      -- yRotation
                farmId,
                {},     -- configurations
                nil,    -- callback
                nil,    -- callbackTarget
                {}      -- callbackArguments
            )
        end)
        if success then
            UsedPlus.logDebug("Vehicle spawned via VehicleLoadingUtil")
            return true
        end
    end

    UsedPlus.logWarn("Could not spawn vehicle - no suitable spawn method found")
    return false
end

--[[
    Get a spawn position for the vehicle (near shop/player)
]]
function UnifiedPurchaseDialog:getVehicleSpawnPosition()
    -- Try to get a position near the player
    local player = g_currentMission.player
    if player and player.rootNode then
        local x, y, z = getWorldTranslation(player.rootNode)
        -- Offset slightly so vehicle doesn't spawn on player
        return x + 5, y, z + 5
    end

    -- Fallback to a default spawn point
    return 0, 0, 0
end

--[[
    Execute finance purchase
    v2.8.0: Delegates to item-type-specific functions
]]
function UnifiedPurchaseDialog:executeFinancePurchase()
    if self.itemType == "placeable" then
        self:executeFinancePurchasePlaceable()
    else
        self:executeFinancePurchaseVehicle()
    end
end

--[[
    Execute finance purchase for vehicles

    NOTE: FinanceVehicleEvent handles:
    1. Creating the finance deal
    2. Spawning the vehicle
    3. Deducting down payment

    Trade-in and cash back are handled here before sending the event.
]]
function UnifiedPurchaseDialog:executeFinancePurchaseVehicle()
    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)

    if not farm then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, g_i18n:getText("usedplus_error_farmNotFound"))
        return
    end

    -- Credit score check - must meet minimum for vehicle financing
    if CreditScore and CreditScore.canFinance then
        local canFinance, minRequired, currentScore, message = CreditScore.canFinance(farmId, "VEHICLE_FINANCE")
        if not canFinance then
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, message)
            UsedPlus.logInfo(string.format("Finance rejected: credit %d < %d required", currentScore, minRequired))
            return
        end
    end

    -- Calculate finance parameters
    local termYears = self:getSelectedTermYears()
    local downPct = UnifiedPurchaseDialog.getDownPaymentPercent(self.financeDownIndex, self.creditScore)
    -- Use filtered cash back options (limited by down payment + trade-in)
    local cashBack = (self.validCashBackOptions and self.validCashBackOptions[self.financeCashBackIndex]) or 0

    -- Down payment is cash paid today (regardless of trade-in)
    local downPayment = self.vehiclePrice * (downPct / 100)

    -- v2.9.1: Net cost = down payment minus cashback (the actual out-of-pocket amount)
    local netDueToday = math.max(0, downPayment - cashBack)

    -- Check if player can afford net due today (down payment minus cashback)
    if netDueToday > farm.money then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_insufficientFundsDownPayment"), g_i18n:formatMoney(netDueToday, 0, true, true)))
        return
    end

    -- Handle trade-in first (removes the vehicle)
    if self.tradeInEnabled and self.tradeInVehicle then
        self:executeTradeIn()
    end

    -- Get vehicle config filename
    local vehicleConfig = self.storeItem and self.storeItem.xmlFilename or "unknown"

    -- Calculate effective price after trade-in (for the finance deal)
    -- Trade-in reduces the amount that needs to be financed
    local effectivePrice = self.vehiclePrice - self.tradeInValue

    -- Send finance event to server (creates the deal and handles money)
    FinanceVehicleEvent.sendToServer(
        farmId,
        "vehicle",           -- itemType
        vehicleConfig,       -- itemId (xmlFilename)
        self.vehicleName,    -- itemName
        effectivePrice,      -- basePrice (after trade-in reduction)
        downPayment,         -- downPayment
        termYears,           -- termYears
        cashBack,            -- cashBack
        {}                   -- configurations
    )

    -- Spawn the vehicle (FinanceVehicleEvent only creates the deal, not the vehicle)
    local spawnSuccess = self:spawnVehicle(farmId, 0)  -- Price 0 since it's financed

    if spawnSuccess then
        -- v2.9.1: Show net due today (down payment minus cashback) not just down payment
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notify_vehicleFinanced"), self.vehicleName, g_i18n:formatMoney(netDueToday)))
    else
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notify_vehicleFinancedShop"), self.vehicleName))
    end

    -- Close dialog
    self:close()
end

--[[
    Execute finance purchase for placeables
    v2.8.0: Refund pattern - create deal, trigger placement, refund after confirmation

    FLOW:
    1. Create finance deal and deduct down payment
    2. Store pending placeable data
    3. Trigger placement mode (player positions building)
    4. Vanilla deducts full price on placement confirm
    5. PlaceableSystemExtension detects completion, refunds financed amount
]]
function UnifiedPurchaseDialog:executeFinancePurchasePlaceable()
    UsedPlus.logInfo("╔════════════════════════════════════════════════════════════════")
    UsedPlus.logInfo("║ executeFinancePurchasePlaceable() ENTRY - FINANCE PURCHASE")
    UsedPlus.logInfo("╠════════════════════════════════════════════════════════════════")

    -- v2.8.4: Check for PRE-BUY mode (user positioned, dialog shown before buy())
    if UsedPlus.pendingPlaceableBuy then
        UsedPlus.logInfo("✅ PRE-BUY MODE DETECTED - Delegating to PRE-BUY finance handler")
        PurchaseExecutorPlaceable.executePreBuyFinance(self.context, g_currentMission:getFarmId(), self)
        return
    end

    UsedPlus.logWarn("⚠️  No pendingPlaceableBuy - falling back to OLD flow (shouldn't happen!)")

    -- Fallback to old executor (should not be reached)
    PurchaseExecutorPlaceable.executeFinance(self.context, g_currentMission:getFarmId(), self)
end

function UnifiedPurchaseDialog:executeFinancePurchasePlaceable_OLD()
    UsedPlus.logInfo("╔════════════════════════════════════════════════════════════════")
    UsedPlus.logInfo("║ executeFinancePurchasePlaceable() ENTRY - FINANCE PURCHASE")
    UsedPlus.logInfo("╠════════════════════════════════════════════════════════════════")

    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)

    UsedPlus.logDebug(string.format("  farmId: %d", farmId))
    UsedPlus.logDebug(string.format("  farm exists: %s", tostring(farm ~= nil)))

    if not farm then
        UsedPlus.logWarn("  ✗ Farm not found - ABORTING")
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, "Farm not found")
        return
    end

    local initialBalance = farm.money
    UsedPlus.logInfo(string.format("  Initial balance: %s", g_i18n:formatMoney(initialBalance)))

    -- Credit score check - placeables require Excellent credit (750+)
    local PLACEABLE_MIN_CREDIT = 750
    UsedPlus.logDebug(string.format("  Credit score: %d (min required: %d)", self.creditScore, PLACEABLE_MIN_CREDIT))

    if self.creditScore < PLACEABLE_MIN_CREDIT then
        UsedPlus.logWarn(string.format("  ✗ Credit too low - ABORTING (have %d, need %d)",
            self.creditScore, PLACEABLE_MIN_CREDIT))
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format("Building financing requires Excellent credit (%d+). Your credit: %d", PLACEABLE_MIN_CREDIT, self.creditScore))
        return
    end
    UsedPlus.logInfo("  ✓ Credit score check PASSED")

    -- Calculate finance parameters
    local termYears = self:getSelectedTermYears()
    local downPct = UnifiedPurchaseDialog.getDownPaymentPercent(self.financeDownIndex, self.creditScore)
    local downPayment = self.vehiclePrice * (downPct / 100)

    UsedPlus.logInfo(string.format("  Building: %s", tostring(self.vehicleName)))
    UsedPlus.logInfo(string.format("  Price: %s", g_i18n:formatMoney(self.vehiclePrice)))
    UsedPlus.logInfo(string.format("  Down payment: %s (%d%%)", g_i18n:formatMoney(downPayment), downPct))
    UsedPlus.logInfo(string.format("  Term: %d years", termYears))
    UsedPlus.logInfo(string.format("  Interest rate: %.2f%%", self.interestRate))

    -- Check if player can afford down payment
    UsedPlus.logDebug(string.format("  Can afford down payment: %s (have %s, need %s)",
        tostring(farm.money >= downPayment),
        g_i18n:formatMoney(farm.money),
        g_i18n:formatMoney(downPayment)))

    if downPayment > farm.money then
        UsedPlus.logWarn(string.format("  ✗ Insufficient funds for down payment - ABORTING (need %s, have %s)",
            g_i18n:formatMoney(downPayment), g_i18n:formatMoney(farm.money)))
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format("Insufficient funds for down payment. Required: %s", g_i18n:formatMoney(downPayment, 0, true, true)))
        return
    end
    UsedPlus.logInfo("  ✓ Down payment affordability check PASSED")

    -- Calculate temp money needed (financed amount = price - down payment)
    local financedAmount = self.vehiclePrice - downPayment

    UsedPlus.logInfo("╔════════════════════════════════════════════════════════════════")
    UsedPlus.logInfo("║ TEMP MONEY INJECTION - CRITICAL SECTION")
    UsedPlus.logInfo("╠════════════════════════════════════════════════════════════════")
    UsedPlus.logInfo(string.format("  Financed amount calculation:"))
    UsedPlus.logDebug(string.format("    Price:        %s", g_i18n:formatMoney(self.vehiclePrice)))
    UsedPlus.logDebug(string.format("    Down payment: %s", g_i18n:formatMoney(downPayment)))
    UsedPlus.logDebug(string.format("    Financed:     %s (this will be injected)", g_i18n:formatMoney(financedAmount)))

    local balanceBeforeInjection = farm.money
    UsedPlus.logDebug(string.format("  Balance BEFORE injection: %s", g_i18n:formatMoney(balanceBeforeInjection)))

    -- Inject temp money so player can afford vanilla affordability check
    -- This will be reconciled after placement (refund removed, finance deal created)
    UsedPlus.logInfo(string.format("  → INJECTING TEMP MONEY: %s", g_i18n:formatMoney(financedAmount)))
    g_currentMission:addMoney(financedAmount, farmId, MoneyType.OTHER, true, false)

    -- Verify injection worked
    local farm2 = g_farmManager:getFarmById(farmId)
    local balanceAfterInjection = farm2 and farm2.money or 0
    UsedPlus.logDebug(string.format("  Balance AFTER injection: %s", g_i18n:formatMoney(balanceAfterInjection)))
    UsedPlus.logDebug(string.format("  Expected after injection: %s",
        g_i18n:formatMoney(balanceBeforeInjection + financedAmount)))

    if math.abs(balanceAfterInjection - (balanceBeforeInjection + financedAmount)) < 1 then
        UsedPlus.logInfo("  ✓ Temp money injection VERIFIED")
    else
        UsedPlus.logWarn(string.format("  ✗ Temp money injection MISMATCH! Expected %s, got %s",
            g_i18n:formatMoney(balanceBeforeInjection + financedAmount),
            g_i18n:formatMoney(balanceAfterInjection)))
    end

    -- Store pending placeable finance data (picked up by PlaceableSystemExtension after placement)
    local injectionTimestamp = g_currentMission.time
    UsedPlus.logInfo("  → Creating pendingPlaceableFinance state")

    UsedPlus.pendingPlaceableFinance = {
        storeItem = self.storeItem,
        farmId = farmId,
        price = self.vehiclePrice,
        downPayment = downPayment,
        termYears = termYears,
        interestRate = self.interestRate,
        itemName = self.vehicleName,
        xmlFilename = self.storeItem.xmlFilename,

        -- CRITICAL: Track temp money for cleanup on cancellation
        tempMoneyInjected = financedAmount,
        injectionTimestamp = injectionTimestamp,
        placementActive = true,  -- Flag to prevent double-cleanup
    }

    UsedPlus.logDebug("  Pending state created with fields:")
    UsedPlus.logDebug(string.format("    - itemName: %s", self.vehicleName))
    UsedPlus.logDebug(string.format("    - price: %s", g_i18n:formatMoney(self.vehiclePrice)))
    UsedPlus.logDebug(string.format("    - downPayment: %s", g_i18n:formatMoney(downPayment)))
    UsedPlus.logDebug(string.format("    - tempMoneyInjected: %s", g_i18n:formatMoney(financedAmount)))
    UsedPlus.logDebug(string.format("    - injectionTimestamp: %.0f", injectionTimestamp))
    UsedPlus.logDebug(string.format("    - placementActive: true"))
    UsedPlus.logDebug(string.format("    - farmId: %d", farmId))
    UsedPlus.logDebug(string.format("    - xmlFilename: %s", tostring(self.storeItem.xmlFilename)))

    UsedPlus.logInfo(string.format("  ✓ Pending finance state ready for reconciliation"))
    UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")

    -- Use the pending BuyPlaceableData instance stored by BuyPlaceableDataExtension
    -- CRITICAL: Reuse existing instance instead of creating new one (prevents auto-completion)
    UsedPlus.logDebug(string.format("  pendingPlaceableData exists: %s",
        tostring(UsedPlus.pendingPlaceableData ~= nil)))

    if UsedPlus.pendingPlaceableData then
        UsedPlus.logInfo("  → Using stored BuyPlaceableData instance")

        -- Get the stored instance
        local placeableData = UsedPlus.pendingPlaceableData
        UsedPlus.logDebug(string.format("     placeableData type: %s", type(placeableData)))
        UsedPlus.pendingPlaceableData = nil
        UsedPlus.logDebug("     Cleared pendingPlaceableData")

        -- CRITICAL: Close dialog FIRST to clear GUI modal stack
        UsedPlus.logInfo("  → Closing dialog BEFORE buy() (deferred execution pattern)")
        self:close()

        UsedPlus.logInfo("  → Registering deferred buy() updateable")
        local deferredStartTime = g_currentMission.time

        -- Defer buy() to next frame (ensures clean GUI state for placement mode)
        g_currentMission:addUpdateable({
            update = function(updatable, dt)
                local deferredElapsed = g_currentMission.time - deferredStartTime
                UsedPlus.logInfo("╔════════════════════════════════════════════════════════════════")
                UsedPlus.logInfo("║ DEFERRED CALLBACK - FINANCE PURCHASE")
                UsedPlus.logInfo("╠════════════════════════════════════════════════════════════════")
                UsedPlus.logDebug(string.format("  Deferred callback fired after: %.0fms", deferredElapsed))
                UsedPlus.logDebug(string.format("  dt: %.2fms", dt))

                g_currentMission:removeUpdateable(updatable)
                UsedPlus.logDebug("  Removed self from updateables")

                -- Guard: Check if pending state still exists (ESC race condition)
                UsedPlus.logDebug(string.format("  Checking pendingPlaceableFinance exists: %s",
                    tostring(UsedPlus.pendingPlaceableFinance ~= nil)))

                if not UsedPlus.pendingPlaceableFinance then
                    UsedPlus.logWarn("  ✗ Pending state cleared (user pressed ESC) - ABORTING deferred buy()")
                    UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")
                    return
                end

                UsedPlus.logInfo("  ✓ Pending state intact - proceeding with buy()")

                -- Verify current balance state
                local currentFarm = g_farmManager:getFarmById(farmId)
                if currentFarm then
                    local currentBalance = currentFarm.money
                    local pending = UsedPlus.pendingPlaceableFinance
                    local expectedBalance = pending.tempMoneyInjected + (initialBalance or 0)
                    UsedPlus.logDebug(string.format("  Current balance: %s", g_i18n:formatMoney(currentBalance)))
                    UsedPlus.logDebug(string.format("  Expected balance: %s (initial %s + temp %s)",
                        g_i18n:formatMoney(expectedBalance),
                        g_i18n:formatMoney(initialBalance or 0),
                        g_i18n:formatMoney(pending.tempMoneyInjected)))

                    if math.abs(currentBalance - expectedBalance) < 1 then
                        UsedPlus.logInfo("  ✓ Balance state verified before buy()")
                    else
                        UsedPlus.logWarn(string.format("  ⚠ Balance mismatch! Expected %s, got %s",
                            g_i18n:formatMoney(expectedBalance),
                            g_i18n:formatMoney(currentBalance)))
                    end
                end

                -- Set bypass flag so our hook doesn't intercept again
                UsedPlus.bypassPlaceableHook = true
                UsedPlus.logInfo("  → Set bypassPlaceableHook = true")

                -- Trigger placement mode
                UsedPlus.logInfo("  → Calling placeableData:buy() - PLACEMENT MODE SHOULD START")
                UsedPlus.logDebug("     Vanilla will deduct full price, then finalization hook will reconcile")
                placeableData:buy()

                UsedPlus.logInfo("  ✓ buy() call completed - placement mode active")
                UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")
            end
        })

        UsedPlus.logInfo("  ✓ Deferred updateable registered - returning control")
        UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")
    else
        UsedPlus.logWarn("  ✗ No pending BuyPlaceableData - using FALLBACK path (shouldn't happen)")

        -- Close dialog first
        UsedPlus.logInfo("  → Closing dialog")
        self:close()

        -- Fallback: create new instance (shouldn't happen normally)
        if BuyPlaceableData and g_client then
            UsedPlus.logDebug("  → Registering fallback deferred updateable")
            local deferredStartTime = g_currentMission.time

            g_currentMission:addUpdateable({
                update = function(updatable, dt)
                    local deferredElapsed = g_currentMission.time - deferredStartTime
                    UsedPlus.logInfo("╔════════════════════════════════════════════════════════════════")
                    UsedPlus.logInfo("║ DEFERRED CALLBACK - FINANCE FALLBACK")
                    UsedPlus.logInfo("╠════════════════════════════════════════════════════════════════")
                    UsedPlus.logDebug(string.format("  Deferred callback fired after: %.0fms", deferredElapsed))

                    g_currentMission:removeUpdateable(updatable)

                    -- Guard: Check if pending state still exists
                    UsedPlus.logDebug(string.format("  Checking pendingPlaceableFinance exists: %s",
                        tostring(UsedPlus.pendingPlaceableFinance ~= nil)))

                    if not UsedPlus.pendingPlaceableFinance then
                        UsedPlus.logWarn("  ✗ Pending state cleared (user cancelled) - ABORTING")
                        UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")
                        return
                    end

                    UsedPlus.logDebug("  Creating new BuyPlaceableData event")
                    local event = BuyPlaceableData.new()
                    event:setOwnerFarmId(farmId)
                    event:setPrice(self.vehiclePrice)
                    event:setStoreItem(self.storeItem)

                    -- Get configurations
                    local configurations = {}
                    if self.shopScreen then
                        configurations = self.shopScreen.configurations or {}
                    elseif g_shopConfigScreen then
                        configurations = g_shopConfigScreen.configurations or {}
                    end
                    event:setConfigurations(configurations)
                    UsedPlus.logDebug("  Configurations set")

                    UsedPlus.bypassPlaceableHook = true
                    UsedPlus.logInfo("  → Calling event:buy()")
                    event:buy()
                    UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")
                end
            })
        else
            UsedPlus.logError("  ✗ BuyPlaceableData not available - CRITICAL FAILURE")
            UsedPlus.logError("     Temp money was injected but cannot proceed!")
            UsedPlus.logError("     Attempting to reclaim temp money...")

            -- Emergency cleanup - reclaim temp money
            if UsedPlus.pendingPlaceableFinance then
                local pending = UsedPlus.pendingPlaceableFinance
                if pending.tempMoneyInjected and pending.tempMoneyInjected > 0 then
                    g_currentMission:addMoney(-pending.tempMoneyInjected, pending.farmId, MoneyType.OTHER, true, false)
                    UsedPlus.logError(string.format("     Emergency reclaim: %s",
                        g_i18n:formatMoney(pending.tempMoneyInjected)))
                end
                UsedPlus.pendingPlaceableFinance = nil
            end

            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                "Purchase failed - game API not available")
        end

        UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")
    end
end

--[[
    Execute lease purchase

    LEASE ECONOMICS:
    - Cap reduction is based on vehicle price percentage
    - Security deposit is credit-based (automatic)
    - LeaseVehicleEvent handles deal creation AND vehicle spawning

    NOTE: We send the event to server which handles:
    1. Creating the lease deal
    2. Spawning the vehicle with LEASED property state
    3. Deducting money (down payment)
]]
function UnifiedPurchaseDialog:executeLeasePurchase()
    UsedPlus.logWarn("executeLeasePurchase: ENTERED")

    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)

    UsedPlus.logWarn(string.format("executeLeasePurchase: farmId=%s, farm=%s", tostring(farmId), tostring(farm ~= nil)))

    if not farm then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, g_i18n:getText("usedplus_error_farmNotFound"))
        return
    end

    -- Credit score check - leasing requires HIGHER credit score than financing
    if CreditScore and CreditScore.canFinance then
        local canLease, minRequired, currentScore, message = CreditScore.canFinance(farmId, "VEHICLE_LEASE")
        if not canLease then
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, message)
            UsedPlus.logInfo(string.format("Lease rejected: credit %d < %d required", currentScore, minRequired))
            return
        end
    end

    -- Calculate lease parameters (LEASE_TERMS stores months directly)
    local termMonths = UnifiedPurchaseDialog.LEASE_TERMS[self.leaseTermIndex] or 36
    local termYears = termMonths / 12
    local capReductionPct = UnifiedPurchaseDialog.getDownPaymentPercent(self.leaseDownIndex, self.creditScore)

    -- Cap reduction as percentage of vehicle price
    local capReduction = self.vehiclePrice * (capReductionPct / 100)

    -- Get security deposit
    local securityDeposit = self.calculatedSecurityDeposit or 0

    -- Total due today = cap reduction + security deposit
    local totalDueToday = capReduction + securityDeposit

    -- Check if player can afford total due today
    if totalDueToday > farm.money then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            "Insufficient funds! Need " .. g_i18n:formatMoney(totalDueToday, 0, true, true))
        return
    end

    -- Handle trade-in first (removes the vehicle)
    if self.tradeInEnabled and self.tradeInVehicle then
        self:executeTradeIn()
    end

    -- Get vehicle config filename
    local vehicleConfig = self.storeItem and self.storeItem.xmlFilename or "unknown"

    -- Get configurations from shop screen (same pattern as cash/finance purchase)
    local configurations = {}
    if self.shopScreen then
        configurations = self.shopScreen.configurations or {}
    elseif g_shopConfigScreen then
        configurations = g_shopConfigScreen.configurations or {}
    end

    -- Send lease event to server
    -- LeaseVehicleEvent handles: deal creation, money deduction, vehicle spawning
    LeaseVehicleEvent.sendToServer(
        farmId,
        vehicleConfig,
        self.vehicleName,
        self.vehiclePrice,
        totalDueToday,  -- downPayment = cap reduction + security deposit
        termYears,      -- LeaseVehicleEvent expects years
        configurations  -- User-selected configurations from shop screen
    )

    -- Close dialog
    self:close()

    -- Note: Success notification is shown by LeaseVehicleEvent after spawn
end

--[[
    Execute trade-in (sell the trade-in vehicle)
]]
function UnifiedPurchaseDialog:executeTradeIn()
    local farmId = g_currentMission:getFarmId()

    -- Delegate to TradeInHandler module
    TradeInHandler.execute(self.context, farmId)
end

--[[
    Cancel button clicked
]]
function UnifiedPurchaseDialog:onCancel()
    self:close()
end

--[[
    Static show method
    v2.8.0: Chooses correct dialog based on item type (vehicle vs placeable)
]]
function UnifiedPurchaseDialog.show(storeItem, price, saleItem, initialMode)
    -- Choose dialog based on item type (species 2 = placeable)
    local dialogName = (storeItem and storeItem.species == 2) and "UnifiedPurchaseDialogPlaceable" or "UnifiedPurchaseDialog"

    local dialog = g_gui.guis[dialogName]
    if dialog and dialog.target then
        dialog.target:setVehicleData(storeItem, price, saleItem)
        dialog.target:setInitialMode(initialMode or UnifiedPurchaseDialog.MODE_CASH)
        g_gui:showDialog(dialogName)
    else
        UsedPlus.logError(dialogName .. " not registered")
    end
end

UsedPlus.logInfo("UnifiedPurchaseDialog loaded")
