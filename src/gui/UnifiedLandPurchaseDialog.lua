--[[
    FS25_UsedPlus - Unified Land Purchase Dialog

     Single dialog for all farmland purchase modes (Cash, Finance, Lease)
    No trade-in support for land purchases.

    Features:
    - Mode selector: Buy with Cash, Finance, Lease
    - Dynamic section visibility based on mode
    - Unified calculations and purchase flow for farmland
]]

UnifiedLandPurchaseDialog = {}
local UnifiedLandPurchaseDialog_mt = Class(UnifiedLandPurchaseDialog, MessageDialog)

-- Purchase modes
UnifiedLandPurchaseDialog.MODE_CASH = 1
UnifiedLandPurchaseDialog.MODE_FINANCE = 2
UnifiedLandPurchaseDialog.MODE_LEASE = 3

-- MODE_TEXTS built dynamically in onGuiSetupFinished using g_i18n

-- Term options for land
UnifiedLandPurchaseDialog.FINANCE_TERMS = {5, 10, 15, 20}  -- Years (max 20)
-- Lease terms in MONTHS: 3, 6, 9 months (sub-year), then 1-5 years
UnifiedLandPurchaseDialog.LEASE_TERMS = {3, 6, 9, 12, 24, 36, 48, 60}
UnifiedLandPurchaseDialog.DOWN_PAYMENT_OPTIONS = {0, 5, 10, 15, 20, 25, 30, 40, 50}  -- Percent (for finance)

--[[
    Get available down payment options based on settings minimum AND credit score
    v2.7.1: Now uses UnifiedPurchaseDialog's credit-based filtering
    @param creditScore - Player's credit score (optional)
    @return filtered table of down payment percentages
]]
function UnifiedLandPurchaseDialog.getDownPaymentOptions(creditScore)
    -- Delegate to UnifiedPurchaseDialog's credit-aware function
    if UnifiedPurchaseDialog and UnifiedPurchaseDialog.getDownPaymentOptions then
        return UnifiedPurchaseDialog.getDownPaymentOptions(creditScore)
    end

    -- Fallback if UnifiedPurchaseDialog not loaded
    local minPercent = UsedPlusSettings and UsedPlusSettings:get("minDownPaymentPercent") or 0
    local options = {}
    for _, pct in ipairs(UnifiedLandPurchaseDialog.DOWN_PAYMENT_OPTIONS) do
        if pct >= minPercent then
            table.insert(options, pct)
        end
    end
    if #options == 0 then
        options = {minPercent}
    end
    return options
end

--[[
    Get the actual down payment percentage for a given dropdown index
    v2.7.1: Now supports credit-based filtering
    @param index - Dropdown index (1-based)
    @param creditScore - Player's credit score (optional)
    @return percentage value
]]
function UnifiedLandPurchaseDialog.getDownPaymentPercent(index, creditScore)
    local options = UnifiedLandPurchaseDialog.getDownPaymentOptions(creditScore)
    return options[index] or options[1] or 0
end

-- Lease pricing constants
-- Base rate should make leasing ~25-35% of expected crop revenue for balance
-- 7 acres wheat @ $12k/year revenue → lease should be ~$3-4k/year
-- 7 acres = 2.83 ha → $1,000-1,400/ha base rate
UnifiedLandPurchaseDialog.LEASE_BASE_RATE_PER_HA = 1000  -- Base $/ha/year for average soil

-- Soil quality multipliers for lease payment
UnifiedLandPurchaseDialog.SOIL_LEASE_MULTIPLIERS = {
    excellent = 1.50,  -- Premium soil = 50% higher lease
    good = 1.25,       -- Good soil = 25% higher lease
    average = 1.00,    -- Baseline
    poor = 0.75,       -- Poor soil = 25% lower lease
}

-- Credit risk multipliers for lease payment (poor credit = landlord charges more)
UnifiedLandPurchaseDialog.CREDIT_LEASE_MULTIPLIERS = {
    [1] = 0.90,  -- Excellent credit: 10% discount (reliable tenant)
    [2] = 0.95,  -- Good credit: 5% discount
    [3] = 1.00,  -- Fair credit: baseline
    [4] = 1.10,  -- Poor credit: 10% premium (risk)
    [5] = 1.25,  -- Very Poor credit: 25% premium (high risk)
}

-- Signing bonus: Estimated crop value based on grain
-- Conservative estimate: assume 60% of arable land has harvestable crops
UnifiedLandPurchaseDialog.CROP_COVERAGE_PERCENT = 0.60
UnifiedLandPurchaseDialog.GRAIN_YIELD_PER_HA = 7.0      -- tons/ha (typical wheat/barley)
UnifiedLandPurchaseDialog.GRAIN_PRICE_PER_TON = 320     -- $/ton (average grain price)

--[[
    Constructor
]]
function UnifiedLandPurchaseDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or UnifiedLandPurchaseDialog_mt)

    -- Current state
    self.currentMode = UnifiedLandPurchaseDialog.MODE_CASH

    -- Land data
    self.farmlandId = nil
    self.farmland = nil
    self.baseLandPrice = 0      -- Original price before credit adjustment
    self.landPrice = 0          -- Adjusted price after credit modifier
    self.creditAdjustment = 0   -- Dollar amount of adjustment (negative = discount)
    self.creditModifierPct = 0  -- Percentage adjustment (-5, 0, +10, etc.)
    self.landName = ""
    self.landSize = 0
    self.pricePerHa = 0

    -- Finance parameters
    self.financeTermIndex = 3  -- Default 15 years for land
    self.financeDownIndex = 5  -- Default 20%

    -- Lease parameters
    self.leaseTermIndex = 4  -- Default 1 year (12 months) - index 4 in LEASE_TERMS {3,6,9,12,...}

    -- Credit data
    self.creditScore = 650
    self.creditRating = "Fair"
    self.interestRate = 0.06  -- Land loans typically have lower rates

    -- v2.15.2: Better Contracts farmland discount
    self.bcDiscountAmount = 0
    self.bcDiscountPercent = 0
    self.bcJobCount = 0
    self.bcMaxJobs = 0
    self.bcDiscountedPrice = 0

    return self
end

--[[
    Called when GUI elements are ready
]]
function UnifiedLandPurchaseDialog:onGuiSetupFinished()
    UnifiedLandPurchaseDialog:superClass().onGuiSetupFinished(self)

    -- Setup mode selector with localized texts
    -- v2.6.2: Check settings for Finance/Lease toggles and show disabled status
    if self.modeSelector then
        local financeSystemEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Finance")
        local leaseSystemEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Lease")

        local modeTexts = {
            g_i18n:getText("usedplus_land_modeCash"),
            financeSystemEnabled and g_i18n:getText("usedplus_land_modeFinance") or (g_i18n:getText("usedplus_land_modeFinance_disabled") or "Finance (Disabled)"),
            leaseSystemEnabled and g_i18n:getText("usedplus_land_modeLease") or (g_i18n:getText("usedplus_land_modeLease_disabled") or "Lease (Disabled)")
        }
        self.modeSelector:setTexts(modeTexts)
        self.modeSelector:setState(1)  -- Default to Cash
    end

    -- Setup finance term slider with localized texts
    if self.financeTermSlider then
        local texts = {}
        for _, years in ipairs(UnifiedLandPurchaseDialog.FINANCE_TERMS) do
            if years == 1 then
                table.insert(texts, g_i18n:getText("usedplus_land_termYear"))
            else
                table.insert(texts, string.format(g_i18n:getText("usedplus_land_termYears"), years))
            end
        end
        self.financeTermSlider:setTexts(texts)
        self.financeTermSlider:setState(self.financeTermIndex)
    end

    -- Setup finance down payment slider (uses filtered options from settings)
    if self.financeDownSlider then
        local options = UnifiedLandPurchaseDialog.getDownPaymentOptions()
        local texts = {}
        for _, pct in ipairs(options) do
            table.insert(texts, pct .. "%")
        end
        self.financeDownSlider:setTexts(texts)
        -- Adjust default index to stay within available options
        self.financeDownIndex = math.min(self.financeDownIndex, #options)
        self.financeDownSlider:setState(self.financeDownIndex)
    end

    -- Setup lease term slider with localized texts (LEASE_TERMS stores months)
    if self.leaseTermSlider then
        local texts = {}
        for _, months in ipairs(UnifiedLandPurchaseDialog.LEASE_TERMS) do
            if months == 1 then
                table.insert(texts, g_i18n:getText("usedplus_land_termMonth"))
            elseif months < 12 then
                table.insert(texts, string.format(g_i18n:getText("usedplus_land_termMonths"), months))
            elseif months == 12 then
                table.insert(texts, g_i18n:getText("usedplus_land_termYear"))
            else
                local years = months / 12
                table.insert(texts, string.format(g_i18n:getText("usedplus_land_termYears"), years))
            end
        end
        self.leaseTermSlider:setTexts(texts)
        self.leaseTermSlider:setState(self.leaseTermIndex)
    end
    -- Note: Security deposit is now credit-based (automatic, no slider needed)
end

--[[
    Set land data for purchase
]]
function UnifiedLandPurchaseDialog:setLandData(farmlandId, farmland, price)
    self.farmlandId = farmlandId
    self.farmland = farmland
    self.baseLandPrice = price or 0  -- Store original price

    -- Verbose debug logging
    UsedPlus.logDebug(string.format("setLandData: farmlandId=%s, basePrice=%s", tostring(farmlandId), tostring(price)))
    if farmland then
        UsedPlus.logTrace("Farmland properties:")
        for key, value in pairs(farmland) do
            if type(value) ~= "table" and type(value) ~= "function" then
                UsedPlus.logTrace(string.format("  %s = %s", tostring(key), tostring(value)))
            end
        end
    end

    if farmland then
        -- Get land name (Field X or custom name)
        self.landName = farmland.name or string.format("Field %d", farmlandId)

        -- Get land size in hectares (farmland.areaInHa is the correct property)
        self.landSize = farmland.areaInHa or 0

        -- Get soil quality if available
        self.soilQuality = "Standard"
        if farmland.soilQuality then
            if farmland.soilQuality >= 0.8 then
                self.soilQuality = "Excellent"
            elseif farmland.soilQuality >= 0.6 then
                self.soilQuality = "Good"
            elseif farmland.soilQuality >= 0.4 then
                self.soilQuality = "Average"
            else
                self.soilQuality = "Poor"
            end
        end
    else
        self.landName = string.format(g_i18n:getText("usedplus_land_farmlandFormat"), farmlandId or 0)
        self.landSize = 0
        self.soilQuality = "Unknown"
    end

    -- v2.15.2: Check for Better Contracts farmland discount
    self.bcDiscountAmount, self.bcDiscountPercent, self.bcJobCount, self.bcMaxJobs = 0, 0, 0, 0
    if ModCompatibility and ModCompatibility.betterContractsInstalled and self.farmland then
        self.bcDiscountAmount, self.bcDiscountPercent, self.bcJobCount, self.bcMaxJobs =
            ModCompatibility.getBCFarmlandDiscount(self.farmland, g_currentMission:getFarmId())
    end

    -- Apply BC discount to base price BEFORE credit adjustment
    -- BC discount = vendor loyalty discount, credit = bank risk assessment
    self.bcDiscountedPrice = self.baseLandPrice - self.bcDiscountAmount

    -- Calculate credit parameters (this also calculates adjusted price)
    self:calculateCreditParameters()

    -- Calculate per-unit prices based on adjusted price
    if self.landSize > 0 then
        self.pricePerHa = self.landPrice / self.landSize
        self.landSizeAcres = self.landSize * 2.47105
        self.pricePerAcre = self.landPrice / self.landSizeAcres
    else
        self.pricePerHa = 0
        self.landSizeAcres = 0
        self.pricePerAcre = 0
    end
end

--[[
    Set initial mode (called from farmland extension)
]]
function UnifiedLandPurchaseDialog:setInitialMode(mode)
    self.currentMode = mode or UnifiedLandPurchaseDialog.MODE_CASH

    if self.modeSelector then
        self.modeSelector:setState(self.currentMode)
    end
end

--[[
    v2.0.0: Helper function to check if credit system is enabled
]]
function UnifiedLandPurchaseDialog.isCreditSystemEnabled()
    if UsedPlusSettings and UsedPlusSettings.get then
        return UsedPlusSettings:get("enableCreditSystem") ~= false
    end
    return true  -- Default to enabled
end

--[[
    Calculate credit parameters and adjusted land price
    v2.0.0: Respects enableCreditSystem setting
]]
function UnifiedLandPurchaseDialog:calculateCreditParameters()
    local farmId = g_currentMission:getFarmId()
    local creditEnabled = UnifiedLandPurchaseDialog.isCreditSystemEnabled()

    if creditEnabled and CreditScore then
        self.creditScore = CreditScore.calculate(farmId)
        self.creditRating = CreditScore.getRating(self.creditScore)

        -- Calculate interest rate based on credit (land loans are typically lower)
        local baseRate = 0.06
        local adjustment = CreditScore.getInterestAdjustment(self.creditScore) or 0
        self.interestRate = math.max(0.025, math.min(0.12, baseRate + adjustment))
    else
        -- Credit system disabled - use defaults
        self.creditScore = 650
        self.creditRating = "Fair"
        self.interestRate = 0.06
    end

    -- Calculate credit-adjusted land price (only if credit enabled)
    -- v2.15.2: Use BC-discounted price as input (vendor discount applied first, then bank risk)
    local priceForCredit = self.bcDiscountedPrice or self.baseLandPrice
    if creditEnabled and FinanceCalculations and priceForCredit > 0 then
        self.landPrice, self.creditAdjustment, self.creditModifierPct, _ =
            FinanceCalculations.calculateAdjustedLandPrice(priceForCredit, self.creditScore)

        UsedPlus.logDebug(string.format(
            "Credit price adjustment: Base=$%d, BC=$%d, Adjusted=$%d, Modifier=%d%%, Score=%d (%s)",
            self.baseLandPrice, priceForCredit, self.landPrice, self.creditModifierPct,
            self.creditScore, self.creditRating))
    else
        -- No credit adjustment
        self.landPrice = priceForCredit
        self.creditAdjustment = 0
        self.creditModifierPct = 0
    end

    -- v2.7.1: Update down payment options based on credit score
    self:updateDownPaymentOptionsForCredit()
end

--[[
    Update down payment slider options based on credit score
    v2.7.1: Lower down payments require better credit
]]
function UnifiedLandPurchaseDialog:updateDownPaymentOptionsForCredit()
    if not self.financeDownSlider then
        return
    end

    local availableOptions = UnifiedLandPurchaseDialog.getDownPaymentOptions(self.creditScore)

    -- Store available options for later lookup
    self.availableFinanceDownOptions = availableOptions

    -- Build texts for available options
    local texts = {}
    for _, pct in ipairs(availableOptions) do
        table.insert(texts, pct .. "%")
    end

    self.financeDownSlider:setTexts(texts)

    -- Ensure current selection is valid
    if self.financeDownIndex > #availableOptions then
        self.financeDownIndex = 1  -- Reset to minimum
    end
    self.financeDownSlider:setState(self.financeDownIndex)
end

--[[
    Called when dialog opens
]]
function UnifiedLandPurchaseDialog:onOpen()
    UnifiedLandPurchaseDialog:superClass().onOpen(self)

    -- Update display
    self:updateDisplay()
    self:updateSectionVisibility()
end

--[[
    Mode selector changed
    v2.6.2: Validates mode against settings
]]
function UnifiedLandPurchaseDialog:onModeChanged()
    if self.modeSelector then
        local newMode = self.modeSelector:getState()

        -- v2.6.2: Check settings for Finance/Lease toggles
        local financeSystemEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Finance")
        local leaseSystemEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Lease")

        -- v2.6.2: Check if Finance mode is allowed
        if newMode == UnifiedLandPurchaseDialog.MODE_FINANCE then
            if not financeSystemEnabled then
                InfoDialog.show(g_i18n:getText("usedplus_land_finance_disabled_msg") or "Land financing is disabled in UsedPlus settings.")
                self.modeSelector:setState(self.currentMode)
                return
            end
        end

        -- v2.6.2: Check if Lease mode is allowed
        if newMode == UnifiedLandPurchaseDialog.MODE_LEASE then
            if not leaseSystemEnabled then
                InfoDialog.show(g_i18n:getText("usedplus_land_lease_disabled_msg") or "Land leasing is disabled in UsedPlus settings.")
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
    Finance term changed
]]
function UnifiedLandPurchaseDialog:onFinanceTermChanged()
    if self.financeTermSlider then
        self.financeTermIndex = self.financeTermSlider:getState()
    end
    self:updateDisplay()
end

--[[
    Finance down payment changed
]]
function UnifiedLandPurchaseDialog:onFinanceDownChanged()
    if self.financeDownSlider then
        self.financeDownIndex = self.financeDownSlider:getState()
    end
    self:updateDisplay()
end

--[[
    Lease term changed
]]
function UnifiedLandPurchaseDialog:onLeaseTermChanged()
    if self.leaseTermSlider then
        self.leaseTermIndex = self.leaseTermSlider:getState()
    end
    self:updateDisplay()
end

-- Note: Security deposit is now credit-based (no user selection needed)

--[[
    Update section visibility based on current mode
]]
function UnifiedLandPurchaseDialog:updateSectionVisibility()
    local isCash = (self.currentMode == UnifiedLandPurchaseDialog.MODE_CASH)
    local isFinance = (self.currentMode == UnifiedLandPurchaseDialog.MODE_FINANCE)
    local isLease = (self.currentMode == UnifiedLandPurchaseDialog.MODE_LEASE)

    if self.cashSection then
        self.cashSection:setVisible(isCash)
    end

    if self.financeSection then
        self.financeSection:setVisible(isFinance)
    end

    if self.leaseSection then
        self.leaseSection:setVisible(isLease)
    end
end

--[[
    Update all display elements
    Refactored to use UIHelper
]]
function UnifiedLandPurchaseDialog:updateDisplay()
    -- Land info using UIHelper
    UIHelper.Element.setText(self.landNameText, self.landName)
    UIHelper.Element.setText(self.landSizeText, string.format("%.2f ha (%.1f acres)", self.landSize, self.landSizeAcres or 0))

    -- Show adjusted price as main price (this is what they'll pay)
    UIHelper.Element.setText(self.landPriceText, UIHelper.Text.formatMoney(self.landPrice))
    UIHelper.Element.setText(self.landPricePerHaText, UIHelper.Text.formatMoney(self.pricePerHa) .. "/ha")
    UIHelper.Element.setText(self.landPricePerAcreText, UIHelper.Text.formatMoney(self.pricePerAcre or 0) .. "/acre")
    local soilI18nMap = {
        Excellent = "usedplus_soil_excellent", Good = "usedplus_soil_good",
        Average = "usedplus_soil_average", Standard = "usedplus_soil_standard",
        Poor = "usedplus_soil_poor", Unknown = "usedplus_condition_unknown"
    }
    local soilKey = soilI18nMap[self.soilQuality] or "usedplus_soil_standard"
    UIHelper.Element.setText(self.landSoilText, g_i18n:getText(soilKey))

    -- Update credit adjustment display elements (if they exist in XML)
    if self.basePriceText then
        UIHelper.Element.setText(self.basePriceText, UIHelper.Text.formatMoney(self.baseLandPrice))
    end

    -- v2.15.2: Better Contracts discount row + dynamic layout
    -- Show row whenever BC discountMode is active (bcMaxJobs > 0), even with 0 jobs
    local bcVisible = self.bcMaxJobs > 0
    if self.bcDiscountText then
        if bcVisible then
            local discText
            local discColor
            if self.bcDiscountAmount > 0 then
                -- Earned discount: green text with amount
                discText = string.format("-%s (%d%% - %d/%d jobs)",
                    UIHelper.Text.formatMoney(self.bcDiscountAmount),
                    self.bcDiscountPercent, self.bcJobCount, self.bcMaxJobs)
                discColor = UIHelper.Colors.MONEY_GREEN
            else
                -- No discount yet: neutral text showing progress
                discText = string.format("0%% (0/%d jobs)", self.bcMaxJobs)
                discColor = UIHelper.Colors.GRAY
            end
            UIHelper.Element.setTextWithColor(self.bcDiscountText, discText, discColor)
            UIHelper.Element.setVisible(self.bcDiscountText, true)
            UIHelper.Element.setVisible(self.bcDiscountLabel, true)
        else
            UIHelper.Element.setVisible(self.bcDiscountText, false)
            UIHelper.Element.setVisible(self.bcDiscountLabel, false)
        end
    end

    -- Shift credit/price group down when BC row is visible (fills gap when hidden)
    if self.creditPriceGroup then
        self.creditPriceGroup:setPosition(0, bcVisible and -80 or -55)
    end

    if self.creditAdjustmentText then
        if self.creditAdjustment ~= 0 then
            local adjText = ""
            local adjColor = nil
            if self.creditAdjustment < 0 then
                -- Discount (good credit)
                adjText = "-" .. UIHelper.Text.formatMoney(math.abs(self.creditAdjustment)) ..
                    " (" .. self.creditModifierPct .. "% " .. self.creditRating .. ")"
                adjColor = UIHelper.Colors.MONEY_GREEN
            else
                -- Premium (bad credit)
                adjText = "+" .. UIHelper.Text.formatMoney(self.creditAdjustment) ..
                    " (+" .. self.creditModifierPct .. "% " .. self.creditRating .. ")"
                adjColor = UIHelper.Colors.DEBT_RED
            end
            UIHelper.Element.setTextWithColor(self.creditAdjustmentText, adjText, adjColor)
            UIHelper.Element.setVisible(self.creditAdjustmentText, true)
        else
            UIHelper.Element.setText(self.creditAdjustmentText, g_i18n:getText("usedplus_land_noAdjustment"))
            UIHelper.Element.setVisible(self.creditAdjustmentText, true)
        end
    end

    if self.adjustedPriceText then
        UIHelper.Element.setText(self.adjustedPriceText, UIHelper.Text.formatMoney(self.landPrice))
    end

    -- Update mode-specific displays
    if self.currentMode == UnifiedLandPurchaseDialog.MODE_CASH then
        self:updateCashDisplay()
    elseif self.currentMode == UnifiedLandPurchaseDialog.MODE_FINANCE then
        self:updateFinanceDisplay()
    elseif self.currentMode == UnifiedLandPurchaseDialog.MODE_LEASE then
        self:updateLeaseDisplay()
    end
end

--[[
    Update cash mode display
    Refactored to use UIHelper
]]
function UnifiedLandPurchaseDialog:updateCashDisplay()
    UIHelper.Element.setText(self.cashPriceText, UIHelper.Text.formatMoney(self.landPrice))
    UIHelper.Element.setText(self.cashTaxText, UIHelper.Text.formatMoney(0))  -- No transfer tax in FS
    UIHelper.Element.setText(self.cashTotalText, UIHelper.Text.formatMoney(self.landPrice))
end

--[[
    Update finance mode display
    Refactored to use UIHelper
]]
function UnifiedLandPurchaseDialog:updateFinanceDisplay()
    local termYears = UnifiedLandPurchaseDialog.FINANCE_TERMS[self.financeTermIndex] or 15
    local downPct = UnifiedLandPurchaseDialog.getDownPaymentPercent(self.financeDownIndex, self.creditScore)

    local downPayment = self.landPrice * (downPct / 100)
    local amountFinanced = self.landPrice - downPayment

    -- Use centralized calculation function
    local termMonths = termYears * 12
    local monthlyPayment, totalInterest = FinanceCalculations.calculateMonthlyPayment(
        amountFinanced,
        self.interestRate,
        termMonths
    )

    -- Update UI using UIHelper
    UIHelper.Element.setText(self.financeAmountText, UIHelper.Text.formatMoney(amountFinanced))
    UIHelper.Element.setText(self.financeRateText, UIHelper.Text.formatInterestRateWithRating(self.interestRate, self.creditRating))
    UIHelper.Finance.displayMonthlyPayment(self.financeMonthlyText, monthlyPayment)
    UIHelper.Element.setTextWithColor(self.financeTotalInterestText,
        UIHelper.Text.formatMoney(math.max(0, totalInterest)), UIHelper.Colors.COST_ORANGE)
    UIHelper.Element.setText(self.financeDueTodayText, UIHelper.Text.formatMoney(downPayment))

    -- v2.0.0: Only show credit score if credit system enabled
    if UnifiedLandPurchaseDialog.isCreditSystemEnabled() then
        UIHelper.Element.setText(self.financeCreditText, UIHelper.Text.formatCreditScore(self.creditScore, self.creditRating))
        UIHelper.Element.setVisible(self.financeCreditText, true)
    else
        UIHelper.Element.setVisible(self.financeCreditText, false)
    end
end

--[[
    Get soil quality key for multiplier lookup
    Maps self.soilQuality string to multiplier table key
]]
function UnifiedLandPurchaseDialog:getSoilMultiplierKey()
    local qualityMap = {
        ["Excellent"] = "excellent",
        ["Good"] = "good",
        ["Average"] = "average",
        ["Standard"] = "average",  -- Default fallback
        ["Poor"] = "poor",
        ["Unknown"] = "average"
    }
    return qualityMap[self.soilQuality] or "average"
end

--[[
    Get credit level for lease multiplier lookup
    Uses CreditScore system if available
]]
function UnifiedLandPurchaseDialog:getCreditLevel()
    if CreditScore and CreditScore.getRating then
        local rating, level = CreditScore.getRating(self.creditScore)
        return level or 3  -- Default to Fair (level 3)
    end
    return 3  -- Fair baseline
end

--[[
    Calculate annual lease payment based on acreage, soil quality, and credit
    Formula: Annual Payment = Base Rate × Hectares × Soil Multiplier × Credit Multiplier
]]
function UnifiedLandPurchaseDialog:calculateAnnualLeasePayment()
    local baseRate = UnifiedLandPurchaseDialog.LEASE_BASE_RATE_PER_HA  -- $1000/ha/year
    local hectares = self.landSize or 0

    -- Get multipliers
    local soilKey = self:getSoilMultiplierKey()
    local soilMult = UnifiedLandPurchaseDialog.SOIL_LEASE_MULTIPLIERS[soilKey] or 1.0

    local creditLevel = self:getCreditLevel()
    local creditMult = UnifiedLandPurchaseDialog.CREDIT_LEASE_MULTIPLIERS[creditLevel] or 1.0

    local annualPayment = baseRate * hectares * soilMult * creditMult

    return math.ceil(annualPayment), soilMult, creditMult
end

--[[
    Estimate value of standing crops on the farmland
    For leases 12+ months, tenant gets the crop as "signing bonus"

    Simple estimation based on grain (wheat/barley):
    - Assume 60% of land has harvestable crops
    - Use typical grain yield (~7 tons/ha) and price (~$320/ton)
    - Results in ~$1,344/ha estimated crop value
]]
function UnifiedLandPurchaseDialog:estimateCropValue()
    local hectares = self.landSize or 0
    if hectares <= 0 then
        return 0, nil
    end

    -- Calculate estimated crop value based on grain
    local arableHa = hectares * UnifiedLandPurchaseDialog.CROP_COVERAGE_PERCENT
    local yieldTons = arableHa * UnifiedLandPurchaseDialog.GRAIN_YIELD_PER_HA
    local cropValue = yieldTons * UnifiedLandPurchaseDialog.GRAIN_PRICE_PER_TON

    -- Adjust for soil quality (better soil = more crops)
    local soilKey = self:getSoilMultiplierKey()
    local soilMult = UnifiedLandPurchaseDialog.SOIL_LEASE_MULTIPLIERS[soilKey] or 1.0
    cropValue = cropValue * soilMult

    return math.floor(cropValue), "grain"
end

--[[
    Update lease mode display
    Lease payment based on acreage × soil × credit, NOT property value
    Security deposit = credit-based months of payment (automatic, not selectable)
]]
function UnifiedLandPurchaseDialog:updateLeaseDisplay()
    -- Get term in months
    local termMonths = UnifiedLandPurchaseDialog.LEASE_TERMS[self.leaseTermIndex] or 12

    -- Calculate lease payment using formula
    local annualPayment, soilMult, creditMult = self:calculateAnnualLeasePayment()
    local monthlyPayment = math.ceil(annualPayment / 12)

    -- Security deposit = credit-based months of lease payment (automatic)
    local securityDeposit, depositMonths, depositTierName = FinanceCalculations.calculateSecurityDeposit(
        monthlyPayment, self.creditScore)

    -- Total lease cost over full term
    local totalPayments = monthlyPayment * termMonths
    local totalLeaseCost = totalPayments + securityDeposit

    -- Buyout price (can purchase land at any time)
    local buyoutPrice = self.landPrice

    -- Check for signing bonus (crop value for 12+ month leases)
    local cropValue, cropName = self:estimateCropValue()
    local hasSigningBonus = (termMonths >= 12 and cropValue > 0)

    -- Store for executeLeasePurchase
    self.calculatedMonthlyPayment = monthlyPayment
    self.calculatedAnnualPayment = annualPayment
    self.calculatedSecurityDeposit = securityDeposit
    self.calculatedCropBonus = hasSigningBonus and cropValue or 0
    self.calculatedCropName = cropName

    -- Update UI using UIHelper
    UIHelper.Finance.displayMonthlyPayment(self.leaseMonthlyText, monthlyPayment)

    -- Show rate breakdown
    if self.leaseRateText then
        local rateInfo = string.format("%s/ha × %.0f%% soil × %.0f%% credit",
            UIHelper.Text.formatMoney(UnifiedLandPurchaseDialog.LEASE_BASE_RATE_PER_HA),
            soilMult * 100,
            creditMult * 100)
        UIHelper.Element.setText(self.leaseRateText, rateInfo)
    end

    -- Annual payment display
    if self.leaseAnnualText then
        UIHelper.Element.setText(self.leaseAnnualText, UIHelper.Text.formatMoney(annualPayment) .. "/year")
    end

    -- Security deposit (credit-based, not selectable)
    if self.leaseDepositText then
        local depositText
        if depositMonths == 0 then
            depositText = string.format(g_i18n:getText("usedplus_land_noDeposit"), depositTierName)
        else
            depositText = string.format(g_i18n:getText("usedplus_land_depositInfo"),
                UIHelper.Text.formatMoney(securityDeposit), depositMonths, depositTierName)
        end
        UIHelper.Element.setText(self.leaseDepositText, depositText)
    end

    -- Due today = security deposit only
    UIHelper.Element.setText(self.leaseDueTodayText, UIHelper.Text.formatMoney(securityDeposit))

    -- Total over lease term
    UIHelper.Element.setText(self.leaseTotalText, UIHelper.Text.formatMoney(totalLeaseCost))

    -- Buyout price to own the land (formatted as full sentence)
    UIHelper.Element.setText(self.leaseBuyoutText, string.format(g_i18n:getText("usedplus_land_buyoutAnytime"), UIHelper.Text.formatMoney(buyoutPrice)))

    -- v2.0.0: Only show credit score if credit system enabled
    if UnifiedLandPurchaseDialog.isCreditSystemEnabled() then
        UIHelper.Element.setText(self.leaseCreditText, UIHelper.Text.formatCreditScore(self.creditScore, self.creditRating))
        UIHelper.Element.setVisible(self.leaseCreditText, true)
    else
        UIHelper.Element.setVisible(self.leaseCreditText, false)
    end

    -- Signing bonus display (for 12+ month leases with standing crops)
    if self.signingBonusSection then
        UIHelper.Element.setVisible(self.signingBonusSection, hasSigningBonus)
        if hasSigningBonus and self.signingBonusText then
            local bonusText = string.format(g_i18n:getText("usedplus_land_signingBonus"),
                cropName or "crops",
                UIHelper.Text.formatMoney(cropValue))
            UIHelper.Element.setText(self.signingBonusText, bonusText)
        end
    end
end

--[[
    Confirm purchase button clicked
]]
function UnifiedLandPurchaseDialog:onConfirmPurchase()
    if self.currentMode == UnifiedLandPurchaseDialog.MODE_CASH then
        self:executeCashPurchase()
    elseif self.currentMode == UnifiedLandPurchaseDialog.MODE_FINANCE then
        self:executeFinancePurchase()
    elseif self.currentMode == UnifiedLandPurchaseDialog.MODE_LEASE then
        self:executeLeasePurchase()
    end
end

--[[
    Execute cash purchase
    v2.8.0: Uses PurchaseLandCashEvent for proper multiplayer support
]]
function UnifiedLandPurchaseDialog:executeCashPurchase()
    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)

    if not farm then
        UsedPlus.logError("Farm not found for cash purchase")
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_farmNotFound"))
        return
    end

    -- Client-side validation (server will re-validate)
    if self.landPrice > farm.money then
        local shortfall = self.landPrice - farm.money
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_insufficientFundsLand"),
                UIHelper.Text.formatMoney(shortfall)))
        return
    end

    -- Validate farmland ID exists
    if not self.farmlandId then
        UsedPlus.logError("farmlandId is nil")
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_couldNotCompletePurchase"))
        return
    end

    -- Send purchase request to server via network event
    -- Server handles: ownership transfer, money deduction, notifications
    -- Pass baseLandPrice for credit discount tracking
    PurchaseLandCashEvent.sendToServer(farmId, self.farmlandId, self.landPrice, self.landName, self.baseLandPrice)

    self:close()
end

--[[
    Execute finance purchase
    v2.8.0: Uses FinanceVehicleEvent for proper multiplayer support
    The FinanceManager:createFinanceDeal() handles ownership transfer for land
]]
function UnifiedLandPurchaseDialog:executeFinancePurchase()
    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)

    if not farm then
        UsedPlus.logError("Farm not found for finance purchase")
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_farmNotFound"))
        return
    end

    -- Calculate finance parameters (using filtered options from settings)
    local termYears = UnifiedLandPurchaseDialog.FINANCE_TERMS[self.financeTermIndex] or 15
    local downPct = UnifiedLandPurchaseDialog.getDownPaymentPercent(self.financeDownIndex, self.creditScore)
    local downPayment = self.landPrice * (downPct / 100)

    -- Client-side validation (server will re-validate)
    if downPayment > farm.money then
        local shortfall = downPayment - farm.money
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_insufficientFundsDownPayment"),
                UIHelper.Text.formatMoney(shortfall)))
        return
    end

    -- Validate farmland ID exists
    if not self.farmlandId then
        UsedPlus.logError("farmlandId is nil for finance purchase")
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_couldNotCompletePurchase"))
        return
    end

    -- Send finance request to server via network event
    -- FinanceVehicleEvent.execute() -> FinanceManager:createFinanceDeal() handles:
    -- - Down payment deduction
    -- - Land ownership transfer (for itemType="land")
    -- - Finance deal creation
    -- - Cash back (not applicable for land, so pass 0)
    FinanceVehicleEvent.sendToServer(
        farmId,
        "land",                 -- itemType
        self.farmlandId,        -- itemId (serialized as Int32 for land)
        self.landName,          -- itemName
        self.landPrice,         -- basePrice
        downPayment,            -- downPayment
        termYears,              -- termYears
        0,                      -- cashBack (land doesn't have cash back)
        {}                      -- configurations (empty for land)
    )

    self:close()
end

--[[
    Execute lease purchase
    v2.8.0: Uses LandLeaseEvent for proper multiplayer support
    NEW SYSTEM: Lease based on acreage, security deposit based on credit score
]]
function UnifiedLandPurchaseDialog:executeLeasePurchase()
    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)

    if not farm then
        UsedPlus.logError("Farm not found for lease purchase")
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_farmNotFound"))
        return
    end

    -- Get calculated values from updateLeaseDisplay (already computed)
    local termMonths = UnifiedLandPurchaseDialog.LEASE_TERMS[self.leaseTermIndex] or 12
    local monthlyPayment = self.calculatedMonthlyPayment or 0
    local securityDeposit = self.calculatedSecurityDeposit or 0

    -- Recalculate if needed (safety check)
    if monthlyPayment == 0 then
        local annualPayment = self:calculateAnnualLeasePayment()
        monthlyPayment = math.ceil(annualPayment / 12)
        -- Security deposit is credit-based (automatic)
        securityDeposit = FinanceCalculations.calculateSecurityDeposit(monthlyPayment, self.creditScore)
    end

    -- Client-side validation (server will re-validate)
    if securityDeposit > farm.money then
        local shortfall = securityDeposit - farm.money
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_insufficientFundsDeposit"),
                UIHelper.Text.formatMoney(shortfall)))
        return
    end

    -- Validate farmland ID exists
    if not self.farmlandId then
        UsedPlus.logError("farmlandId is nil for lease purchase")
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_couldNotCompletePurchase"))
        return
    end

    -- Send lease request to server via network event
    -- LandLeaseEvent handles:
    -- - Security deposit deduction
    -- - Land ownership transfer
    -- - LandLeaseDeal creation
    -- - Notifications
    LandLeaseEvent.sendToServer(
        farmId,
        self.farmlandId,
        self.landName,
        self.landPrice,
        termMonths,
        securityDeposit,
        monthlyPayment
    )

    self:close()
end

--[[
    Cancel button clicked
]]
function UnifiedLandPurchaseDialog:onCancel()
    self:close()
end

--[[
    Static show method
]]
function UnifiedLandPurchaseDialog.show(farmlandId, farmland, price, initialMode)
    local dialog = g_gui.guis.UnifiedLandPurchaseDialog
    if dialog and dialog.target then
        dialog.target:setLandData(farmlandId, farmland, price)
        dialog.target:setInitialMode(initialMode or UnifiedLandPurchaseDialog.MODE_CASH)
        g_gui:showDialog("UnifiedLandPurchaseDialog")
    else
        UsedPlus.logError("UnifiedLandPurchaseDialog not registered")
    end
end

UsedPlus.logInfo("UnifiedLandPurchaseDialog loaded")
