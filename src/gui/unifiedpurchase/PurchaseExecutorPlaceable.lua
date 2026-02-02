--[[
    PurchaseExecutorPlaceable - Execute placeable purchases (PRE-BUY approach)

    Purpose: Handle placeable purchase execution with PRE-BUY dialog.

    Flow:
    1. User positions building → Confirms
    2. BuyPlaceableDataExtension intercepts buy()
    3. Dialog shows (before buy executes)
    4. User chooses payment
    5. [WE ARE HERE] Execute cash or finance
    6. Call vanilla buy() → Complete normally
    7. finalizePlacement() reconciles finance

    v2.8.4: Rewritten for PRE-BUY approach (clean vanilla flow)
]]

PurchaseExecutorPlaceable = {}

--[[
    Execute CASH placeable purchase (PRE-BUY)

    User chose cash payment. Simply call vanilla buy() with no temp money.
]]
function PurchaseExecutorPlaceable.executePreBuyCash(farmId, dialogInstance)
    UsedPlus.logInfo("═══════════════════════════════════════════════════════════")
    UsedPlus.logInfo("💵 PRE-BUY CASH PURCHASE")
    UsedPlus.logInfo("═══════════════════════════════════════════════════════════")

    local pending = UsedPlus.pendingPlaceableBuy

    if not pending then
        UsedPlus.logError("❌ No pendingPlaceableBuy - cannot execute!")
        dialogInstance:close()
        return
    end

    UsedPlus.logInfo(string.format("📦 Item: %s", pending.storeItem.name))
    UsedPlus.logInfo(string.format("💰 Price: %s (full cash payment)", g_i18n:formatMoney(pending.price)))

    -- Clear pending state
    UsedPlus.pendingPlaceableBuy = nil

    -- Hide dialog (don't close yet - wait for buy() to complete)
    dialogInstance:setVisible(false)
    UsedPlus.logDebug("   Dialog hidden (will close after placement)")

    -- Call vanilla buy() - it will deduct full price and place building
    UsedPlus.logInfo("🚀 Calling vanilla buy() for cash purchase...")
    pending.superFunc(pending.buyData, pending.callback, pending.callbackTarget, pending.callbackArguments)

    UsedPlus.logInfo("✅ Cash purchase initiated - vanilla will handle completion")

    -- Wait for buy() to complete, then close everything immediately
    g_currentMission:addUpdateable({
        update = function(updatable, dt)
            g_currentMission:removeUpdateable(updatable)

            -- Close dialog
            UsedPlus.logDebug("  Closing dialog after cash purchase")
            dialogInstance:close()

            -- Close Construction Screen immediately (no delay needed)
            if g_gui and g_gui.showGui then
                UsedPlus.logInfo("  🏗️  Closing Construction Screen (cash purchase complete)")
                g_gui:showGui("")
            end
        end
    })

    UsedPlus.logInfo("═══════════════════════════════════════════════════════════")
end

--[[
    Execute FINANCE placeable purchase (PRE-BUY)

    User chose financing. Inject temp money, call vanilla buy(), create finance deal.
]]
function PurchaseExecutorPlaceable.executePreBuyFinance(context, farmId, dialogInstance)
    UsedPlus.logInfo("═══════════════════════════════════════════════════════════")
    UsedPlus.logInfo("🏦 PRE-BUY FINANCE PURCHASE")
    UsedPlus.logInfo("═══════════════════════════════════════════════════════════")

    local pending = UsedPlus.pendingPlaceableBuy

    if not pending then
        UsedPlus.logError("❌ No pendingPlaceableBuy - cannot execute!")
        dialogInstance:close()
        return
    end

    UsedPlus.logInfo(string.format("📦 Item: %s", pending.storeItem.name))
    UsedPlus.logInfo(string.format("💰 Price: %s", g_i18n:formatMoney(pending.price)))

    -- Get finance parameters from context (including user's down payment selection!)
    local termYears = 10  -- Default
    local interestRate = 5.0  -- Default
    local downPct = 20  -- Default

    if context then
        local availableTerms = context.availableFinanceTerms or CreditCalculations.getFinanceTermsForCredit(context.creditScore)
        termYears = availableTerms[context.financeTermIndex] or termYears
        interestRate = context.interestRate or interestRate

        -- v2.8.4: Get down payment percentage from user's selection in dialog
        -- For placeables, use same dynamic system as vehicles
        if context.itemType == "placeable" then
            downPct = 20  -- Default for placeables if not specified
        end
        -- Get actual percentage from dialog's down payment slider
        downPct = UnifiedPurchaseDialog.getDownPaymentPercent(context.financeDownIndex, context.creditScore)
    end

    -- Calculate down payment based on user's selection (not hardcoded!)
    local downPayment = math.floor(pending.price * (downPct / 100))
    local financedAmount = pending.price - downPayment

    UsedPlus.logInfo(string.format("💵 Down payment: %s (%d%%)", g_i18n:formatMoney(downPayment), downPct))

    UsedPlus.logInfo(string.format("📊 Finance: %s @ %.2f%% for %d years",
        g_i18n:formatMoney(financedAmount), interestRate, termYears))

    -- Inject temp money for financed amount
    UsedPlus.logInfo(string.format("💸 Injecting temp money: %s", g_i18n:formatMoney(financedAmount)))
    g_currentMission:addMoney(financedAmount, farmId, MoneyType.OTHER, true, true)

    local balanceAfterInjection = g_farmManager:getFarmById(farmId).money
    UsedPlus.logDebug(string.format("   Balance after injection: %s", g_i18n:formatMoney(balanceAfterInjection)))

    -- Store finance state for finalizePlacement() reconciliation
    UsedPlus.pendingPlaceableFinance = {
        farmId = farmId,
        itemName = pending.storeItem.name,
        price = pending.price,
        downPayment = downPayment,  -- Use calculated down payment from user's selection!
        financedAmount = financedAmount,
        tempMoneyInjected = financedAmount,
        xmlFilename = pending.storeItem.xmlFilename,
        interestRate = interestRate,
        termYears = termYears,
        placementActive = true,

        -- v2.8.4: PRE-BUY mode (NOT post-placement)
        preBuyMode = true
    }

    UsedPlus.logDebug("💾 Created pendingPlaceableFinance for finalizePlacement() reconciliation")

    -- Clear buy state
    UsedPlus.pendingPlaceableBuy = nil

    -- DON'T close dialog yet - wait for buy() to complete
    -- (If we close now, dialog's cleanup will reclaim temp money!)
    UsedPlus.logDebug("⏸️  Keeping dialog open until buy() completes")

    -- Store dialog reference for cleanup after finalization
    UsedPlus.pendingPlaceableDialog = dialogInstance

    -- Hide dialog (but don't close)
    dialogInstance:setVisible(false)
    UsedPlus.logDebug("   Dialog hidden (will close after finalization)")

    -- Call vanilla buy() - it will deduct full price (down payment + temp) and place building
    UsedPlus.logInfo("🚀 Calling vanilla buy() with temp money injected...")
    pending.superFunc(pending.buyData, pending.callback, pending.callbackTarget, pending.callbackArguments)

    UsedPlus.logInfo("✅ Finance purchase initiated")
    UsedPlus.logInfo("   Vanilla will deduct: down payment (real) + financed amount (temp)")
    UsedPlus.logInfo("   finalizePlacement() will create finance deal")
    UsedPlus.logInfo("═══════════════════════════════════════════════════════════")
end

--[[
    OLD FUNCTION - Kept for reference, not used in PRE-BUY mode
]]
function PurchaseExecutorPlaceable.executeFinance(context, farmId, dialogInstance)
    UsedPlus.logError("❌ OLD executeFinance() called - this should not happen in PRE-BUY mode!")
    UsedPlus.logError("   If you see this, the dialog routing is wrong.")
    dialogInstance:close()
end
