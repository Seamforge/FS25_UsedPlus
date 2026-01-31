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

--[[
    Calculate credit parameters for current purchase
    Updates context: creditScore, creditRating, interestRate, canFinance, canLease
    @param context - PurchaseContext instance
    @param farmId - Farm ID to calculate credit for
]]
function CreditCalculations.calculate(context, farmId)
    -- Will be implemented in Step 4
end

--[[
    Get available finance terms based on credit score
    @param context - PurchaseContext instance
    @return table of available term years
]]
function CreditCalculations.getAvailableTerms(context)
    -- Will be implemented in Step 4
    return {}
end

--[[
    Get available down payment options based on credit score
    @param context - PurchaseContext instance
    @return table of available down payment percentages
]]
function CreditCalculations.getAvailableDownPayments(context)
    -- Will be implemented in Step 4
    return {}
end

--[[
    Check if a purchase mode is available
    @param context - PurchaseContext instance
    @param mode - MODE_CASH, MODE_FINANCE, or MODE_LEASE
    @return isAvailable, reason
]]
function CreditCalculations.isModeAvailable(context, mode)
    -- Will be implemented in Step 4
    return true, nil
end

--[[
    Get trade-in value multiplier based on credit score
    Better credit = better trade-in offers
    @param context - PurchaseContext instance
    @return multiplier (0.75 to 1.0)
]]
function CreditCalculations.getTradeInMultiplier(context)
    -- Will be implemented in Step 4
    return 0.85
end
