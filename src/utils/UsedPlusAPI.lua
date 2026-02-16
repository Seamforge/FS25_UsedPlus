--[[
    UsedPlusAPI.lua - Public API for External Mod Integration

    This module provides a stable, documented interface for other mods to:
    - Query credit scores and financial status
    - Read vehicle DNA (workhorse/lemon scale)
    - Access maintenance states (fluids, malfunctions, reliability)
    - Get finance deal information
    - Subscribe to UsedPlus events

    USAGE BY EXTERNAL MODS:
    ```lua
    -- Check if UsedPlus is installed and get API
    if UsedPlusAPI then
        local creditScore = UsedPlusAPI.getCreditScore(farmId)
        local dna = UsedPlusAPI.getVehicleDNA(vehicle)
    end
    ```

    VERSION: 1.0.0 (v2.13.3)
    STABILITY: Stable - breaking changes will be versioned

    All functions return nil/false gracefully if UsedPlus subsystems unavailable.
]]

UsedPlusAPI = {}

-- API Version for compatibility checking
UsedPlusAPI.VERSION = "1.0.0"
UsedPlusAPI.MOD_VERSION = "2.13.3.1"

--============================================================================
-- VERSION & AVAILABILITY
--============================================================================

--[[
    Get API version for compatibility checking
    @return string - API version (e.g., "1.0.0")
]]
function UsedPlusAPI.getVersion()
    return UsedPlusAPI.VERSION
end

--[[
    Get UsedPlus mod version
    @return string - Mod version (e.g., "2.5.2")
]]
function UsedPlusAPI.getModVersion()
    return UsedPlusAPI.MOD_VERSION
end

--[[
    Check if UsedPlus is fully initialized and ready
    @return boolean
]]
function UsedPlusAPI.isReady()
    return UsedPlus ~= nil and
           g_financeManager ~= nil and
           ModCompatibility ~= nil and
           ModCompatibility.initialized
end

--============================================================================
-- CREDIT SYSTEM API
-- Query credit scores, ratings, and financial status
--============================================================================

--[[
    Get credit score for a farm
    @param farmId - Farm ID (number)
    @return number - Credit score (300-850), or nil if unavailable
]]
function UsedPlusAPI.getCreditScore(farmId)
    if not CreditScore then return nil end
    return CreditScore.calculate(farmId)
end

--[[
    Get credit rating tier for a farm
    @param farmId - Farm ID
    @return rating (string), level (number 1-5), or nil
    Tiers: "Excellent" (1), "Good" (2), "Fair" (3), "Poor" (4), "Very Poor" (5)
]]
function UsedPlusAPI.getCreditRating(farmId)
    if not CreditScore then return nil, nil end
    local score = CreditScore.calculate(farmId)
    return CreditScore.getRating(score)
end

--[[
    Get interest rate adjustment based on credit score
    @param farmId - Farm ID
    @return number - Percentage points to add to base rate (-1.5 to +3.0)
]]
function UsedPlusAPI.getInterestAdjustment(farmId)
    if not CreditScore then return 0 end
    local score = CreditScore.calculate(farmId)
    return CreditScore.getInterestAdjustment(score)
end

--[[
    Check if a farm can qualify for a specific type of financing
    @param farmId - Farm ID
    @param financeType - "REPAIR", "VEHICLE_FINANCE", "VEHICLE_LEASE", "LAND_FINANCE", "CASH_LOAN"
    @return canFinance (boolean), minRequired (number), currentScore (number)
]]
function UsedPlusAPI.canFinance(farmId, financeType)
    if not CreditScore then return false, 0, 0 end
    local can, minReq, score = CreditScore.canFinance(farmId, financeType)
    return can, minReq, score
end

--[[
    Get payment history statistics for a farm
    @param farmId - Farm ID
    @return table with: totalPayments, onTimePayments, latePayments, missedPayments, currentStreak, longestStreak
            or nil if unavailable
]]
function UsedPlusAPI.getPaymentStats(farmId)
    if not PaymentTracker then return nil end
    return PaymentTracker.getStats(farmId)
end

--[[
    Get on-time payment rate as percentage
    @param farmId - Farm ID
    @return number - 0-100 percentage, or nil
]]
function UsedPlusAPI.getOnTimePaymentRate(farmId)
    if not PaymentTracker then return nil end
    return PaymentTracker.getOnTimeRate(farmId)
end

--[[
    Get credit history events for a farm
    @param farmId - Farm ID
    @param limit - Optional max entries to return (default all)
    @return array of history entries (newest first), or empty array
]]
function UsedPlusAPI.getCreditHistory(farmId, limit)
    if not CreditHistory then return {} end
    return CreditHistory.getHistory(farmId, limit)
end

--============================================================================
-- VEHICLE DNA API
-- Query workhorse/lemon scale and related mechanics
--============================================================================

--[[
    Get vehicle DNA (workhorse/lemon scale)
    @param vehicle - Vehicle object
    @return number - 0.0 (pure lemon) to 1.0 (pure workhorse), or nil
]]
function UsedPlusAPI.getVehicleDNA(vehicle)
    if not vehicle then return nil end
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return nil end
    return spec.workhorseLemonScale
end

--[[
    Check if vehicle is a workhorse (DNA >= 0.65)
    @param vehicle - Vehicle object
    @return boolean
]]
function UsedPlusAPI.isWorkhorse(vehicle)
    local dna = UsedPlusAPI.getVehicleDNA(vehicle)
    return dna ~= nil and dna >= 0.65
end

--[[
    Check if vehicle is a legendary workhorse (DNA >= 0.90, immune to repair degradation)
    @param vehicle - Vehicle object
    @return boolean
]]
function UsedPlusAPI.isLegendaryWorkhorse(vehicle)
    local dna = UsedPlusAPI.getVehicleDNA(vehicle)
    return dna ~= nil and dna >= 0.90
end

--[[
    Check if vehicle is a lemon (DNA <= 0.35)
    @param vehicle - Vehicle object
    @return boolean
]]
function UsedPlusAPI.isLemon(vehicle)
    local dna = UsedPlusAPI.getVehicleDNA(vehicle)
    return dna ~= nil and dna <= 0.35
end

--[[
    Get DNA classification as string
    @param vehicle - Vehicle object
    @return string - "Legendary Workhorse", "Workhorse", "Average", "Lemon", or nil
]]
function UsedPlusAPI.getDNAClassification(vehicle)
    local dna = UsedPlusAPI.getVehicleDNA(vehicle)
    if dna == nil then return nil end

    if dna >= 0.90 then
        return "Legendary Workhorse"
    elseif dna >= 0.65 then
        return "Workhorse"
    elseif dna <= 0.35 then
        return "Lemon"
    else
        return "Average"
    end
end

--[[
    Get DNA-based lifetime multiplier for RVB parts
    @param vehicle - Vehicle object
    @return number - 0.6 to 1.4 (affects RVB part lifetimes), or 1.0
]]
function UsedPlusAPI.getDNALifetimeMultiplier(vehicle)
    local dna = UsedPlusAPI.getVehicleDNA(vehicle)
    if dna == nil then return 1.0 end
    return 0.6 + (dna * 0.8)  -- Range: 0.6 to 1.4
end

--============================================================================
-- MAINTENANCE STATE API
-- Query fluid levels, reliability, and malfunction states
--============================================================================

--[[
    Get fluid levels for a vehicle
    @param vehicle - Vehicle object
    @return table with: oilLevel, hydraulicFluidLevel (0.0-1.0), or nil
]]
function UsedPlusAPI.getFluidLevels(vehicle)
    if not vehicle then return nil end
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return nil end

    return {
        oilLevel = spec.oilLevel or 1.0,
        hydraulicFluidLevel = spec.hydraulicFluidLevel or 1.0,
    }
end

--[[
    Get reliability values for a vehicle
    @param vehicle - Vehicle object
    @return table with: engine, electrical, hydraulic (0.0-1.0), overall, or nil
]]
function UsedPlusAPI.getReliability(vehicle)
    if not vehicle then return nil end

    local engine = ModCompatibility.getEngineReliability(vehicle)
    local electrical = ModCompatibility.getElectricalReliability(vehicle)
    local hydraulic = ModCompatibility.getHydraulicReliability(vehicle)
    local overall = ModCompatibility.getOverallReliability(vehicle)

    return {
        engine = engine,
        electrical = electrical,
        hydraulic = hydraulic,
        overall = overall,
    }
end

--[[
    Get active malfunctions for a vehicle
    @param vehicle - Vehicle object
    @return table with active malfunction states, or nil
]]
function UsedPlusAPI.getActiveMalfunctions(vehicle)
    if not vehicle then return nil end
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return nil end

    local malfunctions = {}

    -- Runaway state
    if spec.runawayActive then
        malfunctions.runaway = {
            active = true,
            startTime = spec.runawayStartTime,
        }
    end

    -- Hydraulic malfunctions
    if spec.hydraulicSurgeActive then
        malfunctions.hydraulicSurge = {
            active = true,
            endTime = spec.hydraulicSurgeEndTime,
        }
    end

    if spec.implementStuckDown then
        malfunctions.implementStuckDown = {
            active = true,
            endTime = spec.implementStuckDownEndTime,
        }
    end

    if spec.implementStuckUp then
        malfunctions.implementStuckUp = {
            active = true,
            endTime = spec.implementStuckUpEndTime,
        }
    end

    if spec.implementPullActive then
        malfunctions.implementPull = {
            active = true,
            direction = spec.implementPullDirection,
        }
    end

    if spec.implementDragActive then
        malfunctions.implementDrag = { active = true }
    end

    -- Engine/Electrical malfunctions
    if spec.electricalCutoutActive then
        malfunctions.electricalCutout = {
            active = true,
            endTime = spec.electricalCutoutEndTime,
        }
    end

    -- Steering pull (from flat tire or hydraulic issues)
    if spec.steeringPullActive then
        malfunctions.steeringPull = {
            active = true,
            strength = spec.steeringPullStrength,
            direction = spec.steeringPullDirection,
        }
    end

    return malfunctions
end

--[[
    Check if vehicle has any active malfunction
    @param vehicle - Vehicle object
    @return boolean
]]
function UsedPlusAPI.hasActiveMalfunction(vehicle)
    local malfunctions = UsedPlusAPI.getActiveMalfunctions(vehicle)
    if not malfunctions then return false end

    for _, _ in pairs(malfunctions) do
        return true
    end
    return false
end

--[[
    Get progressive degradation info for a vehicle
    @param vehicle - Vehicle object
    @return table with: maxReliability (current caps), repairCount, breakdownCount, totalDegradation
]]
function UsedPlusAPI.getProgressiveDegradation(vehicle)
    if not vehicle then return nil end
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec then return nil end

    return {
        maxEngineReliability = spec.maxEngineReliability or 1.0,
        maxElectricalReliability = spec.maxElectricalReliability or 1.0,
        maxHydraulicReliability = spec.maxHydraulicReliability or 1.0,
        repairCount = spec.repairCount or 0,
        breakdownCount = spec.breakdownCount or 0,
        rvbTotalDegradation = spec.rvbTotalDegradation or 0,
        rvbRepairCount = spec.rvbRepairCount or 0,
        rvbBreakdownCount = spec.rvbBreakdownCount or 0,
    }
end

--[[
    Get tire information for a vehicle
    @param vehicle - Vehicle object
    @return array of tire data: {condition, tier, isFlat}, or nil
]]
function UsedPlusAPI.getTireInfo(vehicle)
    if not vehicle then return nil end
    local spec = vehicle.spec_usedPlusMaintenance
    if not spec or not spec.tires then return nil end

    local tires = {}
    for i, tire in ipairs(spec.tires) do
        table.insert(tires, {
            index = i,
            condition = tire.condition or 1.0,
            tier = tire.tier or 2,  -- 1=Retread, 2=Normal, 3=Quality
            isFlat = tire.isFlat or false,
        })
    end

    -- Add UYT data if available
    if ModCompatibility.uytInstalled then
        for i, tire in ipairs(tires) do
            tire.uytWear = ModCompatibility.getUYTTireWear(vehicle, i)
        end
    end

    return tires
end

--============================================================================
-- FINANCE DEALS API
-- Query active loans, leases, and financial obligations
--============================================================================

--[[
    Get all active finance deals for a farm
    @param farmId - Farm ID
    @return array of deal objects, or empty array
]]
function UsedPlusAPI.getActiveDeals(farmId)
    if not g_financeManager then return {} end

    local deals = g_financeManager:getDealsForFarm(farmId) or {}
    local activeDeals = {}

    for _, deal in pairs(deals) do
        if deal.status == "active" then
            table.insert(activeDeals, {
                id = deal.id,
                dealType = deal.dealType,
                itemName = deal.itemName,
                originalAmount = deal.originalAmount or deal.purchasePrice,
                currentBalance = deal.currentBalance,
                monthlyPayment = deal.monthlyPayment,
                interestRate = deal.interestRate,
                termMonths = deal.termMonths,
                monthsPaid = deal.monthsPaid,
                remainingMonths = deal.termMonths - deal.monthsPaid,
                missedPayments = deal.missedPayments or 0,
            })
        end
    end

    return activeDeals
end

--[[
    Get total debt for a farm (all active deal balances + vanilla loan)
    @param farmId - Farm ID
    @return number - Total debt amount
]]
function UsedPlusAPI.getTotalDebt(farmId)
    if not CreditScore then return 0 end
    local farm = g_farmManager:getFarmById(farmId)
    if not farm then return 0 end
    return CreditScore.calculateDebt(farm)
end

--[[
    Get monthly payment obligations for a farm
    @param farmId - Farm ID
    @return table with: usedPlusTotal, externalTotal (ELS+HP), grandTotal
]]
function UsedPlusAPI.getMonthlyObligations(farmId)
    local usedPlusTotal = 0
    local externalTotal = 0

    -- UsedPlus deals
    if g_financeManager then
        local deals = g_financeManager:getDealsForFarm(farmId) or {}
        for _, deal in pairs(deals) do
            if deal.status == "active" then
                usedPlusTotal = usedPlusTotal + (deal.monthlyPayment or 0)
            end
        end
    end

    -- External mods (ELS + HP)
    if ModCompatibility then
        externalTotal = ModCompatibility.getExternalMonthlyObligations(farmId)
    end

    return {
        usedPlusTotal = usedPlusTotal,
        externalTotal = externalTotal,
        grandTotal = usedPlusTotal + externalTotal,
    }
end

--[[
    Get total assets for a farm (cash + owned land + owned vehicles)
    @param farmId - Farm ID
    @return number - Total asset value
]]
function UsedPlusAPI.getTotalAssets(farmId)
    if not CreditScore then return 0 end
    local farm = g_farmManager:getFarmById(farmId)
    if not farm then return 0 end
    return CreditScore.calculateAssets(farm)
end

--[[
    Get statistics for a farm
    @param farmId - Farm ID
    @return table with lifetime statistics, or nil
]]
function UsedPlusAPI.getStatistics(farmId)
    if not g_financeManager then return nil end
    return g_financeManager:getStatistics(farmId)
end

--============================================================================
-- CREDIT BUREAU API
-- Allow external mods to register deals and report payments
-- This enables other finance mods to affect UsedPlus credit scores
--============================================================================

-- Storage for externally registered deals
UsedPlusAPI.externalDeals = {}

--[[
    Register an external deal with UsedPlus credit bureau
    Other mods call this when they create a loan/lease to track it

    @param modName - Unique identifier for the calling mod (e.g., "EnhancedLoanSystem")
    @param dealId - Unique deal ID within that mod
    @param farmId - Farm ID the deal belongs to
    @param dealData - Table with deal information:
        - dealType: "loan", "lease", "finance", "credit" (required)
        - itemName: Description of the deal (required)
        - originalAmount: Starting balance (required)
        - currentBalance: Current balance (optional, defaults to originalAmount)
        - monthlyPayment: Expected monthly payment (required for credit impact)
        - interestRate: Interest rate as decimal (optional)
        - termMonths: Total term in months (optional)
    @return externalDealId - Unique ID for this registration, or nil on failure
]]
function UsedPlusAPI.registerExternalDeal(modName, dealId, farmId, dealData)
    if not modName or not dealId or not farmId or not dealData then
        UsedPlus.logWarn("UsedPlusAPI.registerExternalDeal: Missing required parameters")
        return nil
    end

    if not dealData.dealType or not dealData.itemName or not dealData.originalAmount then
        UsedPlus.logWarn("UsedPlusAPI.registerExternalDeal: dealData missing required fields")
        return nil
    end

    -- Create unique external deal ID
    local externalDealId = string.format("%s_%s", modName, tostring(dealId))

    -- Check for duplicate
    if UsedPlusAPI.externalDeals[externalDealId] then
        UsedPlus.logWarn("UsedPlusAPI.registerExternalDeal: Deal already registered: " .. externalDealId)
        return externalDealId  -- Return existing ID
    end

    -- Register the deal
    local deal = {
        externalDealId = externalDealId,
        modName = modName,
        originalDealId = dealId,
        farmId = farmId,
        dealType = dealData.dealType,
        itemName = dealData.itemName,
        originalAmount = dealData.originalAmount,
        currentBalance = dealData.currentBalance or dealData.originalAmount,
        monthlyPayment = dealData.monthlyPayment or 0,
        interestRate = dealData.interestRate or 0,
        termMonths = dealData.termMonths or 0,
        monthsPaid = 0,
        missedPayments = 0,
        status = "active",
        registeredAt = g_currentMission.time or 0,
    }

    UsedPlusAPI.externalDeals[externalDealId] = deal

    -- Initialize farm data if needed
    if not UsedPlusAPI.externalDeals.byFarm then
        UsedPlusAPI.externalDeals.byFarm = {}
    end
    if not UsedPlusAPI.externalDeals.byFarm[farmId] then
        UsedPlusAPI.externalDeals.byFarm[farmId] = {}
    end
    table.insert(UsedPlusAPI.externalDeals.byFarm[farmId], externalDealId)

    UsedPlus.logInfo(string.format("External deal registered: %s from %s (farm %d, $%d)",
        externalDealId, modName, farmId, deal.originalAmount))

    -- Fire event for deal creation
    UsedPlusAPI.fireEvent("onDealCreated", farmId, deal)

    -- Record credit event for new debt
    if CreditHistory then
        CreditHistory.recordEvent(farmId, "NEW_DEBT_TAKEN",
            string.format("External: %s - %s", modName, dealData.itemName))
    end

    return externalDealId
end

--[[
    Report an on-time payment from an external deal
    Call this when the player makes a payment on an externally-registered deal

    @param externalDealId - The ID returned from registerExternalDeal
    @param amount - Payment amount
    @return boolean - true if recorded successfully
]]
function UsedPlusAPI.reportExternalPayment(externalDealId, amount)
    local deal = UsedPlusAPI.externalDeals[externalDealId]
    if not deal then
        UsedPlus.logWarn("UsedPlusAPI.reportExternalPayment: Unknown deal: " .. tostring(externalDealId))
        return false
    end

    if deal.status ~= "active" then
        UsedPlus.logWarn("UsedPlusAPI.reportExternalPayment: Deal not active: " .. externalDealId)
        return false
    end

    -- Update deal state
    deal.currentBalance = math.max(0, deal.currentBalance - amount)
    deal.monthsPaid = deal.monthsPaid + 1

    -- Record payment in PaymentTracker (affects credit score!)
    if PaymentTracker then
        PaymentTracker.recordPayment(
            deal.farmId,
            externalDealId,
            PaymentTracker.STATUS_ON_TIME,
            amount,
            deal.dealType
        )
    end

    -- Record credit event
    if CreditHistory then
        CreditHistory.recordEvent(deal.farmId, "PAYMENT_ON_TIME",
            string.format("External: %s payment $%d", deal.modName, amount))
    end

    UsedPlus.logDebug(string.format("External payment recorded: %s - $%d (balance: $%d)",
        externalDealId, amount, deal.currentBalance))

    -- Check if deal is paid off
    if deal.currentBalance <= 0 then
        UsedPlusAPI.closeExternalDeal(externalDealId, "paid_off")
    end

    return true
end

--[[
    Report a missed/late payment from an external deal
    Call this when the player misses a payment on an externally-registered deal

    @param externalDealId - The ID returned from registerExternalDeal
    @param isLate - true if payment was made late, false if missed entirely
    @return boolean - true if recorded successfully
]]
function UsedPlusAPI.reportExternalDefault(externalDealId, isLate)
    local deal = UsedPlusAPI.externalDeals[externalDealId]
    if not deal then
        UsedPlus.logWarn("UsedPlusAPI.reportExternalDefault: Unknown deal: " .. tostring(externalDealId))
        return false
    end

    if deal.status ~= "active" then
        return false
    end

    -- Update deal state
    deal.missedPayments = deal.missedPayments + 1

    -- Record in PaymentTracker (affects credit score!)
    if PaymentTracker then
        local status = isLate and PaymentTracker.STATUS_LATE or PaymentTracker.STATUS_MISSED
        PaymentTracker.recordPayment(
            deal.farmId,
            externalDealId,
            status,
            0,
            deal.dealType
        )
    end

    -- Record credit event
    if CreditHistory then
        local eventType = isLate and "PAYMENT_PARTIAL" or "PAYMENT_MISSED"
        CreditHistory.recordEvent(deal.farmId, eventType,
            string.format("External: %s - %s", deal.modName, deal.itemName))
    end

    UsedPlus.logDebug(string.format("External %s recorded: %s (total missed: %d)",
        isLate and "late payment" or "missed payment",
        externalDealId, deal.missedPayments))

    return true
end

--[[
    Update the current balance of an external deal
    Call this when the balance changes (e.g., interest accrual, extra payment)

    @param externalDealId - The ID returned from registerExternalDeal
    @param newBalance - New current balance
    @return boolean - true if updated successfully
]]
function UsedPlusAPI.updateExternalDealBalance(externalDealId, newBalance)
    local deal = UsedPlusAPI.externalDeals[externalDealId]
    if not deal then
        return false
    end

    deal.currentBalance = math.max(0, newBalance)

    if deal.currentBalance <= 0 and deal.status == "active" then
        UsedPlusAPI.closeExternalDeal(externalDealId, "paid_off")
    end

    return true
end

--[[
    Close an external deal (paid off, cancelled, or defaulted)

    @param externalDealId - The ID returned from registerExternalDeal
    @param reason - "paid_off", "cancelled", "defaulted", "transferred"
    @return boolean - true if closed successfully
]]
function UsedPlusAPI.closeExternalDeal(externalDealId, reason)
    local deal = UsedPlusAPI.externalDeals[externalDealId]
    if not deal then
        return false
    end

    if deal.status ~= "active" then
        return false  -- Already closed
    end

    deal.status = reason or "closed"
    deal.closedAt = g_currentMission.time or 0

    -- Record appropriate credit event
    if CreditHistory then
        if reason == "paid_off" then
            CreditHistory.recordEvent(deal.farmId, "DEAL_PAID_OFF",
                string.format("External: %s - %s paid in full", deal.modName, deal.itemName))
        elseif reason == "defaulted" then
            CreditHistory.recordEvent(deal.farmId, "LEASE_TERMINATED_EARLY",
                string.format("External: %s - %s defaulted", deal.modName, deal.itemName))
        end
    end

    -- Fire event
    UsedPlusAPI.fireEvent("onDealCompleted", deal.farmId, deal)

    UsedPlus.logInfo(string.format("External deal closed: %s (%s)", externalDealId, reason))

    return true
end

--[[
    Get all external deals for a farm
    @param farmId - Farm ID
    @return array of external deal objects
]]
function UsedPlusAPI.getExternalDeals(farmId)
    local result = {}

    if not UsedPlusAPI.externalDeals.byFarm or not UsedPlusAPI.externalDeals.byFarm[farmId] then
        return result
    end

    for _, externalDealId in ipairs(UsedPlusAPI.externalDeals.byFarm[farmId]) do
        local deal = UsedPlusAPI.externalDeals[externalDealId]
        if deal and deal.status == "active" then
            table.insert(result, {
                externalDealId = deal.externalDealId,
                modName = deal.modName,
                dealType = deal.dealType,
                itemName = deal.itemName,
                originalAmount = deal.originalAmount,
                currentBalance = deal.currentBalance,
                monthlyPayment = deal.monthlyPayment,
                monthsPaid = deal.monthsPaid,
                missedPayments = deal.missedPayments,
            })
        end
    end

    return result
end

--[[
    Get total debt from external deals for a farm
    @param farmId - Farm ID
    @return number - Total external debt
]]
function UsedPlusAPI.getExternalDebt(farmId)
    local total = 0

    local deals = UsedPlusAPI.getExternalDeals(farmId)
    for _, deal in ipairs(deals) do
        total = total + (deal.currentBalance or 0)
    end

    return total
end

--[[
    Get total monthly obligations from external deals for a farm
    @param farmId - Farm ID
    @return number - Total external monthly payments
]]
function UsedPlusAPI.getExternalMonthlyPayments(farmId)
    local total = 0

    local deals = UsedPlusAPI.getExternalDeals(farmId)
    for _, deal in ipairs(deals) do
        total = total + (deal.monthlyPayment or 0)
    end

    return total
end

--============================================================================
-- RESALE VALUE API
-- Calculate vehicle values with condition factors
--============================================================================

--[[
    Get adjusted resale value for a vehicle considering condition
    @param vehicle - Vehicle object
    @return number - Adjusted sale value, or 0
]]
function UsedPlusAPI.getResaleValue(vehicle)
    if not vehicle then return 0 end

    -- Base sell price from game
    local baseSellPrice = vehicle:getSellPrice() or 0

    -- Get reliability factor
    local reliability = ModCompatibility.getOverallReliability(vehicle)
    local dna = UsedPlusAPI.getVehicleDNA(vehicle)

    -- Apply reliability modifier (70-100% of base)
    local reliabilityMod = 0.7 + (reliability * 0.3)

    -- DNA bonus for workhorses, penalty for lemons
    local dnaMod = 1.0
    if dna then
        if dna >= 0.90 then
            dnaMod = 1.05  -- 5% bonus for legendary
        elseif dna >= 0.65 then
            dnaMod = 1.02  -- 2% bonus for workhorse
        elseif dna <= 0.35 then
            dnaMod = 0.95  -- 5% penalty for lemon
        end
    end

    return math.floor(baseSellPrice * reliabilityMod * dnaMod)
end

--============================================================================
-- EVENT SUBSCRIPTION API
-- Subscribe to UsedPlus events
--============================================================================

-- Event subscribers
UsedPlusAPI.subscribers = {
    onCreditScoreChanged = {},
    onPaymentMade = {},
    onPaymentMissed = {},
    onDealCreated = {},
    onDealCompleted = {},
    onMalfunctionTriggered = {},
    onMalfunctionEnded = {},
    onVehicleRepaired = {},
}

--[[
    Subscribe to a UsedPlus event
    @param eventName - One of: "onCreditScoreChanged", "onPaymentMade", "onPaymentMissed",
                       "onDealCreated", "onDealCompleted", "onMalfunctionTriggered",
                       "onMalfunctionEnded", "onVehicleRepaired"
    @param callback - Function to call when event fires
    @param context - Optional 'self' context for callback
    @return boolean - true if subscribed successfully
]]
function UsedPlusAPI.subscribe(eventName, callback, context)
    if not UsedPlusAPI.subscribers[eventName] then
        UsedPlus.logWarn("UsedPlusAPI: Unknown event " .. tostring(eventName))
        return false
    end

    table.insert(UsedPlusAPI.subscribers[eventName], {
        callback = callback,
        context = context,
    })

    UsedPlus.logDebug("UsedPlusAPI: Subscribed to " .. eventName)
    return true
end

--[[
    Unsubscribe from a UsedPlus event
    @param eventName - Event name
    @param callback - The callback to remove
    @return boolean - true if unsubscribed
]]
function UsedPlusAPI.unsubscribe(eventName, callback)
    local subs = UsedPlusAPI.subscribers[eventName]
    if not subs then return false end

    for i = #subs, 1, -1 do
        if subs[i].callback == callback then
            table.remove(subs, i)
            return true
        end
    end
    return false
end

--[[
    Fire an event to all subscribers (internal use)
    @param eventName - Event to fire
    @param ... - Arguments to pass to callbacks
]]
function UsedPlusAPI.fireEvent(eventName, ...)
    local subs = UsedPlusAPI.subscribers[eventName]
    if not subs then return end

    -- Capture varargs into a table (Lua 5.1 doesn't allow ... in nested functions)
    local args = {...}

    for _, sub in ipairs(subs) do
        local success, err = pcall(function()
            if sub.context then
                sub.callback(sub.context, unpack(args))
            else
                sub.callback(unpack(args))
            end
        end)

        if not success then
            UsedPlus.logWarn("UsedPlusAPI: Event handler error in " .. eventName .. ": " .. tostring(err))
        end
    end
end

--============================================================================
-- CROSS-MOD COMPATIBILITY INFO
--============================================================================

--[[
    Get detected compatible mods status
    @return table with mod detection flags
]]
function UsedPlusAPI.getCompatibleMods()
    if not ModCompatibility then return {} end

    return {
        rvbInstalled = ModCompatibility.rvbInstalled,
        uytInstalled = ModCompatibility.uytInstalled,
        advancedMaintenanceInstalled = ModCompatibility.advancedMaintenanceInstalled,
        hirePurchasingInstalled = ModCompatibility.hirePurchasingInstalled,
        buyUsedEquipmentInstalled = ModCompatibility.buyUsedEquipmentInstalled,
        enhancedLoanSystemInstalled = ModCompatibility.enhancedLoanSystemInstalled,
    }
end

--[[
    Get feature availability based on detected mods
    @return table with feature flags
]]
function UsedPlusAPI.getFeatureAvailability()
    if not ModCompatibility then
        return {
            financeEnabled = true,
            searchEnabled = true,
            loanEnabled = true,
            maintenanceEnabled = true,
        }
    end

    return {
        financeEnabled = ModCompatibility.shouldShowFinanceButton(),
        searchEnabled = ModCompatibility.shouldShowSearchButton(),
        loanEnabled = ModCompatibility.shouldEnableLoanSystem(),
        maintenanceEnabled = true,  -- Always enabled
    }
end

--============================================================================
-- INITIALIZATION
--============================================================================

UsedPlus.logInfo("UsedPlusAPI v" .. UsedPlusAPI.VERSION .. " loaded - Public API ready for external mods")
