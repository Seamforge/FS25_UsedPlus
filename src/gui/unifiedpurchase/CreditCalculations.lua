--[[
    CreditCalculations - Credit scoring, qualification, term/down filtering

    Purpose: All credit-related calculations and business logic.
    Stateless functions that read from and update PurchaseContext.

    Responsibilities:
    - Calculate credit score and interest rate
    - Filter available terms based on credit
    - Filter available down payment options based on credit
    - Check mode qualification (can finance/lease?)
    - Calculate trade-in multiplier based on credit
]]

CreditCalculations = {}

-- Constants (copied from UnifiedPurchaseDialog for module independence)
CreditCalculations.FINANCE_TERMS = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}
CreditCalculations.TERM_CREDIT_REQUIREMENTS = {
    {maxYears = 5, minCredit = 300},
    {maxYears = 10, minCredit = 650},
    {maxYears = 15, minCredit = 700},
}
CreditCalculations.DOWN_PAYMENT_OPTIONS = {0, 5, 10, 15, 20, 25, 30, 40, 50}
CreditCalculations.DOWN_PAYMENT_CREDIT_REQUIREMENTS = {
    {minDown = 25, minCredit = 300},
    {minDown = 20, minCredit = 600},
    {minDown = 10, minCredit = 650},
    {minDown = 5, minCredit = 700},
    {minDown = 0, minCredit = 750},
}

--[[
    Check if credit system is enabled
    @return boolean
]]
function CreditCalculations.isCreditSystemEnabled()
    if UsedPlusSettings and UsedPlusSettings.get then
        return UsedPlusSettings:get("enableCreditSystem") ~= false
    end
    return true  -- Default to enabled
end

--[[
    Calculate credit parameters for current purchase
    Updates context: creditScore, creditRating, interestRate, canFinance, canLease, financeMinScore, leaseMinScore
    @param context - PurchaseContext instance
    @param farmId - Farm ID to calculate credit for
]]
function CreditCalculations.calculate(context, farmId)
    local creditEnabled = CreditCalculations.isCreditSystemEnabled()

    if creditEnabled and CreditScore then
        context.creditScore = CreditScore.calculate(farmId)
        context.creditRating = CreditScore.getRating(context.creditScore)

        -- Calculate interest rate based on credit
        local baseRate = 0.08
        local adjustment = CreditScore.getInterestAdjustment(context.creditScore) or 0
        context.interestRate = math.max(0.03, math.min(0.15, baseRate + adjustment))

        -- Check qualification based on item type
        if context.itemType == "placeable" then
            -- Placeables require Excellent credit (750+) - endgame unlock
            local PLACEABLE_MIN_CREDIT = 750
            context.canFinance = context.creditScore >= PLACEABLE_MIN_CREDIT
            context.financeMinScore = PLACEABLE_MIN_CREDIT
            -- Placeables cannot be leased (only financed or bought)
            context.canLease = false
            context.leaseMinScore = 999  -- Never available
        else
            -- Vehicles use standard credit checks
            context.canFinance, context.financeMinScore = CreditScore.canFinance(farmId, "VEHICLE_FINANCE")
            context.canLease, context.leaseMinScore = CreditScore.canFinance(farmId, "VEHICLE_LEASE")
        end
    else
        -- Credit system disabled - use defaults (always qualified)
        context.creditScore = 650
        context.creditRating = "Fair"
        context.interestRate = 0.08
        context.canFinance = true
        context.canLease = (context.itemType == "vehicle")  -- Placeables can't be leased even with credit disabled
        context.financeMinScore = 550
        context.leaseMinScore = 600
    end
end

--[[
    Get minimum required down payment based on credit score
    @param creditScore - Player's current credit score (300-850)
    @return minPercent - Minimum down payment percentage required
]]
function CreditCalculations.getMinDownPaymentForCredit(creditScore)
    local minDown = 25  -- Default: worst credit requires 25% down
    for _, tier in ipairs(CreditCalculations.DOWN_PAYMENT_CREDIT_REQUIREMENTS) do
        if creditScore >= tier.minCredit then
            minDown = tier.minDown
        end
    end
    return minDown
end

--[[
    Get available down payment options based on settings minimum AND credit score
    @param creditScore - Player's current credit score (300-850), optional
    @return filtered table of down payment percentages
]]
function CreditCalculations.getDownPaymentOptions(creditScore)
    -- Get the absolute minimum from settings
    local settingsMin = UsedPlusSettings and UsedPlusSettings:get("minDownPaymentPercent") or 0

    -- Get the credit-based minimum (if credit score provided)
    local creditMin = 0
    if creditScore then
        creditMin = CreditCalculations.getMinDownPaymentForCredit(creditScore)
    end

    -- Use the higher of the two minimums
    local minPercent = math.max(settingsMin, creditMin)

    local options = {}
    for _, pct in ipairs(CreditCalculations.DOWN_PAYMENT_OPTIONS) do
        if pct >= minPercent then
            table.insert(options, pct)
        end
    end
    -- Ensure at least one option exists
    if #options == 0 then
        options = {minPercent}
    end
    return options
end

--[[
    Get the actual down payment percentage for a given dropdown index
    @param index - Dropdown index (1-based)
    @param creditScore - Optional credit score for filtering
    @return percentage value
]]
function CreditCalculations.getDownPaymentPercent(index, creditScore)
    local options = CreditCalculations.getDownPaymentOptions(creditScore)
    return options[index] or options[1] or 0
end

--[[
    Get maximum allowed finance term based on credit score
    @param creditScore - Player's current credit score (300-850)
    @return maxYears - Maximum allowed term in years
]]
function CreditCalculations.getMaxTermForCredit(creditScore)
    local maxYears = 5  -- Default: anyone can get 5 years
    for _, tier in ipairs(CreditCalculations.TERM_CREDIT_REQUIREMENTS) do
        if creditScore >= tier.minCredit then
            maxYears = tier.maxYears
        end
    end
    return maxYears
end

--[[
    Get available finance terms based on credit score
    @param creditScore - Player's current credit score (300-850)
    @return filtered table of term years
]]
function CreditCalculations.getFinanceTermsForCredit(creditScore)
    local maxYears = CreditCalculations.getMaxTermForCredit(creditScore)
    local terms = {}
    for _, years in ipairs(CreditCalculations.FINANCE_TERMS) do
        if years <= maxYears then
            table.insert(terms, years)
        end
    end
    return terms
end

--[[
    Get available finance terms based on context credit score
    Updates context.availableFinanceTerms
    @param context - PurchaseContext instance
    @return table of available term years
]]
function CreditCalculations.getAvailableTerms(context)
    local availableTerms = CreditCalculations.getFinanceTermsForCredit(context.creditScore)
    context.availableFinanceTerms = availableTerms
    return availableTerms
end

--[[
    Get available down payment options based on context credit score
    Updates context.availableFinanceDownOptions and context.availableLeaseDownOptions
    @param context - PurchaseContext instance
    @return table of available down payment percentages
]]
function CreditCalculations.getAvailableDownPayments(context)
    local availableOptions = CreditCalculations.getDownPaymentOptions(context.creditScore)
    context.availableFinanceDownOptions = availableOptions
    context.availableLeaseDownOptions = availableOptions
    return availableOptions
end

--[[
    Check if a purchase mode is available
    @param context - PurchaseContext instance
    @param mode - MODE_CASH, MODE_FINANCE, or MODE_LEASE
    @return isAvailable, reason
]]
function CreditCalculations.isModeAvailable(context, mode)
    if mode == context.MODE_CASH then
        return true, nil  -- Cash is always available
    elseif mode == context.MODE_FINANCE then
        -- Check minimum financing amount first
        if FinanceCalculations and FinanceCalculations.meetsMinimumAmount then
            local meetsMinimum, minRequired = FinanceCalculations.meetsMinimumAmount(context.vehiclePrice, "VEHICLE_FINANCE")
            if not meetsMinimum then
                local msg = string.format(g_i18n:getText("usedplus_finance_amountTooSmall") or "Amount too small for financing. Minimum: %s",
                    g_i18n:formatMoney(minRequired, 0, true, true))
                return false, msg
            end
        end
        -- Then check credit score
        if not context.canFinance then
            local msgTemplate = g_i18n:getText("usedplus_credit_tooLowForFinancing")
            return false, string.format(msgTemplate, context.creditScore, context.financeMinScore or 550)
        end
        return true, nil
    elseif mode == context.MODE_LEASE then
        -- Check minimum lease amount first
        if FinanceCalculations and FinanceCalculations.meetsMinimumAmount then
            local meetsMinimum, minRequired = FinanceCalculations.meetsMinimumAmount(context.vehiclePrice, "VEHICLE_LEASE")
            if not meetsMinimum then
                local msg = string.format(g_i18n:getText("usedplus_lease_amountTooSmall") or "Amount too small for leasing. Minimum: %s",
                    g_i18n:formatMoney(minRequired, 0, true, true))
                return false, msg
            end
        end
        -- Then check credit score
        if not context.canLease then
            local msgTemplate = g_i18n:getText("usedplus_credit_tooLowForLeasing")
            return false, string.format(msgTemplate, context.creditScore, context.leaseMinScore or 600)
        end
        return true, nil
    end
    return true, nil
end

--[[
    Get trade-in value multiplier based on credit score
    Better credit = better trade-in offers (dealers trust you more for financing)

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

    @param context - PurchaseContext instance
    @return multiplier (e.g., 0.55 to 0.70)
]]
function CreditCalculations.getTradeInMultiplier(context)
    local score = context.creditScore or 650

    -- v2.6.2: Use baseTradeInPercent setting instead of hardcoded 50%
    -- Credit bonus adds 0-15% on top based on credit score
    local basePercent = (UsedPlusSettings and UsedPlusSettings:get("baseTradeInPercent") or 55) / 100
    local maxBonus = 0.15  -- Excellent credit adds up to 15%

    -- Calculate credit bonus: poor credit = 0, excellent credit = maxBonus
    local creditBonus = 0
    if score >= 800 then
        creditBonus = maxBonus           -- Exceptional: full 15% bonus
    elseif score >= 740 then
        creditBonus = maxBonus * 0.73    -- Very good: 11% bonus
    elseif score >= 670 then
        creditBonus = maxBonus * 0.47    -- Good: 7% bonus
    elseif score >= 580 then
        creditBonus = maxBonus * 0.20    -- Fair: 3% bonus
    else
        creditBonus = 0                  -- Poor: no bonus
    end

    return basePercent + creditBonus
end
