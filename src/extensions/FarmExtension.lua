--[[
    FS25_UsedPlus - Farm Extension

    Extends Farm class for vanilla loan tracking and credit scoring
    Pattern from: BuyUsedEquipment FarmExtension.lua
    Reference: FS25_ADVANCED_PATTERNS.md - Extension Pattern

    Responsibilities:
    - Subscribe to PERIOD_CHANGED event (monthly)
    - Track vanilla bank loan payments for credit score (unique to FarmExtension)
    - Seed retroactive credit for existing saves
    - Handle land seizure for non-payment

    NOTE (v2.12.2): Deal payment processing moved to FinanceManager (Issue #7)
    FarmExtension previously duplicated FinanceManager's payment loop,
    causing double money deductions. FinanceManager is now the sole processor.
]]

FarmExtension = {}

-- Track if we've already subscribed to events
FarmExtension.initialized = false

-- v2.5.2: Track vanilla loan balances to detect payments
-- The vanilla bank loan (farm.loan) makes automatic payments each period
-- We need to track these to give proper credit score benefits
FarmExtension.lastVanillaLoanBalances = {}

-- v2.5.2: Track which farms have received retroactive credit seeding
-- This is PERSISTED to prevent gaming (take small new loan → get years of free credit)
-- Once seeded, a farm will never be seeded again
FarmExtension.retroactiveCreditSeeded = {}

--[[
    Initialize farm extension
    Subscribe to game events for payment processing
]]
function FarmExtension:init()
    if FarmExtension.initialized then return end

    -- Subscribe to period (month) change for finance payments
    if g_messageCenter then
        g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, FarmExtension.onPeriodChanged, FarmExtension)

        UsedPlus.logDebug("FarmExtension subscribed to PERIOD_CHANGED")
    end

    FarmExtension.initialized = true
end

--[[
    Called every in-game month
    Process automatic payments for all active finance deals
]]
function FarmExtension.onPeriodChanged()
    -- Only server processes payments
    if not g_server then return end

    UsedPlus.logDebug("FarmExtension: Processing vanilla loan tracking...")

    -- Get all farms and track vanilla loans
    -- NOTE: Deal payment processing removed in v2.12.2 (Issue #7)
    -- FarmExtension was duplicating FinanceManager's payment processing,
    -- causing double money deduction and double monthsPaid increments.
    -- FinanceManager.onPeriodChanged() is now the sole payment processor.
    local farms = g_farmManager:getFarms()
    for _, farm in pairs(farms) do
        if farm.farmId ~= FarmManager.SPECTATOR_FARM_ID then
            -- v2.5.2: Track vanilla loan payments (unique to FarmExtension)
            FarmExtension:trackVanillaLoanPayment(farm)
        end
    end
end

--[[
    v2.5.2: Track vanilla bank loan payments for credit score
    The game automatically deducts vanilla loan payments each period.
    We detect this by comparing the current balance to what we stored last period.
    If the balance decreased, that's a payment - record it for credit!

    NOTE: Vanilla loans can't be "missed" - they're automatic. So we only
    record on-time payments. This is fair because the player IS paying.

    COLD START HANDLING (v2.5.2+):
    When loading an existing save that has never had UsedPlus tracking:
    - If player has a loan and has played N periods, they've made ~N payments
    - We seed PaymentTracker with retroactive credit for past payments
    - This ensures players aren't penalized for playing before installing UsedPlus
]]
function FarmExtension:trackVanillaLoanPayment(farm)
    local farmId = farm.farmId
    local currentLoan = farm.loan or 0

    -- Get the previous balance we stored (may be from save file)
    local previousLoan = FarmExtension.lastVanillaLoanBalances[farmId]

    UsedPlus.logDebug(string.format("Farm %d: Vanilla loan check - previous=$%.0f, current=$%.0f",
        farmId, previousLoan or -1, currentLoan))

    -- Store current balance for next period
    FarmExtension.lastVanillaLoanBalances[farmId] = currentLoan

    -- If we don't have a previous balance, this is our first check (fresh install or data loss)
    if previousLoan == nil then
        UsedPlus.logDebug(string.format("Farm %d: Initialized vanilla loan tracking at $%.0f (no previous data)",
            farmId, currentLoan))

        -- COLD START: Seed retroactive credit if player has a loan and has played
        -- NOTE: seedRetroactiveVanillaLoanCredit checks the persisted flag to prevent gaming
        if currentLoan > 0 then
            FarmExtension:seedRetroactiveVanillaLoanCredit(farm, currentLoan)
        else
            -- No loan currently - but mark as "initialized" so future loans don't get retroactive credit
            -- This is CRITICAL: prevents gaming by taking a new loan after playing for months
            if not FarmExtension.retroactiveCreditSeeded[farmId] then
                FarmExtension.retroactiveCreditSeeded[farmId] = true
                UsedPlus.logDebug(string.format(
                    "Farm %d: Marked as initialized (no loan) - future loans won't get retroactive credit",
                    farmId))
            end
        end
        return
    end

    -- If there was no loan before and still no loan, nothing to track
    if previousLoan == 0 and currentLoan == 0 then
        return
    end

    -- Calculate the change in loan balance
    local balanceChange = previousLoan - currentLoan

    -- If balance DECREASED, a payment was made
    if balanceChange > 0 then
        -- Estimate the payment amount (this is principal reduction)
        -- The game also charges interest, so the actual payment is higher
        -- We'll use a rough estimate: payment ≈ principal + (balance * 10%/12)
        local estimatedInterest = previousLoan * (0.10 / 12)  -- ~10% annual rate
        local estimatedPayment = balanceChange + estimatedInterest

        -- Record as on-time payment in PaymentTracker
        if PaymentTracker then
            PaymentTracker.recordPayment(
                farmId,
                "VANILLA_BANK_LOAN",
                PaymentTracker.STATUS_ON_TIME,
                math.floor(estimatedPayment),
                "vanilla_loan"
            )
        end

        -- Record in CreditHistory for event tracking
        if CreditHistory then
            CreditHistory.recordEvent(farmId, "PAYMENT_ON_TIME",
                string.format("Bank Loan: $%d payment", math.floor(estimatedPayment)))
        end

        UsedPlus.logDebug(string.format("Farm %d: Vanilla loan payment detected - $%.0f (balance: $%.0f -> $%.0f)",
            farmId, estimatedPayment, previousLoan, currentLoan))

        -- Check if the loan was fully paid off
        if currentLoan <= 0 and previousLoan > 0 then
            if CreditHistory then
                CreditHistory.recordEvent(farmId, "DEAL_PAID_OFF", "Bank Credit Line paid in full!")
            end

            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_OK,
                "Congratulations! Your bank loan has been paid off!"
            )

            UsedPlus.logInfo(string.format("Farm %d: Vanilla bank loan paid off!", farmId))
        end
    elseif balanceChange < 0 then
        -- Balance INCREASED - player borrowed more money
        -- This is recorded elsewhere when they take out the loan
        UsedPlus.logDebug(string.format("Farm %d: Vanilla loan increased by $%.0f (new balance: $%.0f)",
            farmId, -balanceChange, currentLoan))
    end
end

--[[
    v2.5.2: Seed retroactive credit for vanilla loan payments
    Called when we first detect a loan on an existing save.

    We estimate past payments based on:
    - Total periods (months) elapsed in the game
    - Current loan balance (estimate typical payment size)

    This is intentionally conservative - we'd rather give slightly less
    credit than give too much for payments that may not have happened.
]]
function FarmExtension:seedRetroactiveVanillaLoanCredit(farm, currentLoan)
    local farmId = farm.farmId

    -- CRITICAL: Check if this farm has EVER been seeded before
    -- This flag is PERSISTED to prevent gaming (new loan → free years of credit)
    if FarmExtension.retroactiveCreditSeeded[farmId] then
        UsedPlus.logDebug(string.format(
            "Farm %d: Already seeded retroactive credit - skipping (anti-gaming)",
            farmId))
        return
    end

    -- Check if PaymentTracker is available
    if not PaymentTracker then
        UsedPlus.logDebug("PaymentTracker not available for retroactive credit")
        return
    end

    -- Additional safety: Check if we already have payment history for this farm's vanilla loan
    local existingPayments = PaymentTracker.getPaymentHistory(farmId) or {}

    for _, payment in ipairs(existingPayments) do
        if payment.dealType == "vanilla_loan" then
            UsedPlus.logDebug(string.format(
                "Farm %d: Already has vanilla loan payment history - skipping retroactive seed",
                farmId))
            -- Mark as seeded so we don't check again
            FarmExtension.retroactiveCreditSeeded[farmId] = true
            return
        end
    end

    -- Calculate periods elapsed
    local environment = g_currentMission.environment
    if not environment then
        UsedPlus.logDebug("Environment not available for retroactive credit calculation")
        return
    end

    local daysPerPeriod = environment.daysPerPeriod or 1
    local currentMonotonicDay = environment.currentMonotonicDay or 0

    -- Calculate how many periods (months) have passed
    local periodsElapsed = math.floor(currentMonotonicDay / daysPerPeriod)

    -- If less than 1 period, no retroactive credit needed (they just started)
    if periodsElapsed < 1 then
        UsedPlus.logDebug(string.format(
            "Farm %d: Less than 1 period elapsed - no retroactive credit",
            farmId))
        return
    end

    -- Cap retroactive payments at a reasonable maximum
    -- (We don't want to give 100+ payments for a very long game save)
    local maxRetroactivePayments = 24  -- 2 years of credit max
    local paymentsToCredit = math.min(periodsElapsed, maxRetroactivePayments)

    -- Estimate a typical payment amount
    -- Vanilla loan is ~10% annual, so monthly payment includes principal + interest
    -- We'll estimate payment as roughly (balance / remaining_term) + monthly_interest
    -- Since we don't know the original term, estimate conservatively
    local estimatedMonthlyPayment = currentLoan * (0.10 / 12) + (currentLoan / 36)
    estimatedMonthlyPayment = math.floor(estimatedMonthlyPayment)

    -- Seed the payments into PaymentTracker
    for i = 1, paymentsToCredit do
        PaymentTracker.recordPayment(
            farmId,
            "VANILLA_BANK_LOAN_RETRO",
            PaymentTracker.STATUS_ON_TIME,
            estimatedMonthlyPayment,
            "vanilla_loan"
        )
    end

    -- Also record a single CreditHistory event summarizing the retroactive credit
    if CreditHistory then
        CreditHistory.recordEvent(farmId, "PAYMENT_ON_TIME",
            string.format("Bank Loan: %d prior monthly payments credited", paymentsToCredit))
    end

    -- Mark this farm as seeded (CRITICAL - prevents gaming)
    FarmExtension.retroactiveCreditSeeded[farmId] = true

    -- Notify the player
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format("UsedPlus: Credited %d prior bank loan payments to your history!",
            paymentsToCredit)
    )

    UsedPlus.logInfo(string.format(
        "Farm %d: Seeded %d retroactive vanilla loan payments (est. $%d each) - marked as seeded",
        farmId, paymentsToCredit, estimatedMonthlyPayment))
end

-- v2.12.2: processMonthlyPaymentsForFarm, processPaymentForDeal, sendPaymentSummaryNotification,
-- checkCreditTierChange, getDealTypeName, handleMissedPayment, and seizeLand removed (Issue #7).
-- These were duplicating FinanceManager's payment processing, causing double deductions.
-- FinanceManager.processMonthlyPaymentsForFarm() is now the sole payment processor.
-- Land seizure is handled by FinanceDeal:seizeLand() directly.

--[[
    Save FarmExtension data to XML
    Called from FinanceManager save
]]
function FarmExtension.saveToXMLFile(xmlFile, key)
    -- Save retroactive credit seeding flags
    local farmIndex = 0
    for farmId, seeded in pairs(FarmExtension.retroactiveCreditSeeded) do
        if seeded then
            local farmKey = string.format("%s.retroactiveSeeded.farm(%d)", key, farmIndex)
            xmlFile:setInt(farmKey .. "#farmId", farmId)
            farmIndex = farmIndex + 1
        end
    end

    UsedPlus.logDebug(string.format("FarmExtension: Saved %d retroactive seeding flags", farmIndex))

    -- v2.5.2: Save vanilla loan balances for payment detection across sessions
    local balanceIndex = 0
    for farmId, balance in pairs(FarmExtension.lastVanillaLoanBalances) do
        local balanceKey = string.format("%s.vanillaLoanBalances.farm(%d)", key, balanceIndex)
        xmlFile:setInt(balanceKey .. "#farmId", farmId)
        xmlFile:setFloat(balanceKey .. "#balance", balance)
        balanceIndex = balanceIndex + 1
    end

    UsedPlus.logDebug(string.format("FarmExtension: Saved %d vanilla loan balances", balanceIndex))
end

--[[
    Load FarmExtension data from XML
    Called from FinanceManager load
]]
function FarmExtension.loadFromXMLFile(xmlFile, key)
    -- Reset state
    FarmExtension.retroactiveCreditSeeded = {}
    FarmExtension.lastVanillaLoanBalances = {}

    -- Load retroactive credit seeding flags
    local count = 0
    xmlFile:iterate(key .. ".retroactiveSeeded.farm", function(_, farmKey)
        local farmId = xmlFile:getInt(farmKey .. "#farmId")
        if farmId then
            FarmExtension.retroactiveCreditSeeded[farmId] = true
            count = count + 1
        end
    end)

    UsedPlus.logDebug(string.format("FarmExtension: Loaded %d retroactive seeding flags", count))

    -- v2.5.2: Load vanilla loan balances for payment detection
    local balanceCount = 0
    xmlFile:iterate(key .. ".vanillaLoanBalances.farm", function(_, balanceKey)
        local farmId = xmlFile:getInt(balanceKey .. "#farmId")
        local balance = xmlFile:getFloat(balanceKey .. "#balance")
        if farmId and balance then
            FarmExtension.lastVanillaLoanBalances[farmId] = balance
            balanceCount = balanceCount + 1
        end
    end)

    UsedPlus.logDebug(string.format("FarmExtension: Loaded %d vanilla loan balances", balanceCount))
end

--[[
    Cleanup on mission unload
    Unsubscribe from MessageCenter events to prevent memory leaks
]]
function FarmExtension:delete()
    if g_messageCenter then
        g_messageCenter:unsubscribe(MessageType.PERIOD_CHANGED, FarmExtension)
        UsedPlus.logDebug("FarmExtension unsubscribed from events")
    end

    -- Reset state
    FarmExtension.initialized = false
    FarmExtension.lastVanillaLoanBalances = {}
    FarmExtension.retroactiveCreditSeeded = {}

    UsedPlus.logInfo("FarmExtension cleaned up")
end

--[[
    Initialize on mission load
]]
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, function(mission, node)
    FarmExtension:init()
end)

--[[
    Cleanup on mission unload
]]
Mission00.delete = Utils.appendedFunction(Mission00.delete, function(mission)
    FarmExtension:delete()
end)

UsedPlus.logInfo("FarmExtension loaded")
