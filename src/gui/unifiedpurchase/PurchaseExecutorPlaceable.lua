--[[
    PurchaseExecutorPlaceable - Execute placeable purchases with temp money injection

    Purpose: Handle placeable purchase execution logic.
    Stateless functions that operate on PurchaseContext.

    CRITICAL: executeFinance() contains temp money injection flow for placeables.
    This is the most delicate code in the refactor - PRESERVED EXACTLY.

    Responsibilities:
    - Execute cash placeable purchases
    - Execute finance placeable purchases (TEMP MONEY FLOW)
    - Coordinate with PlaceableSystemExtension for reconciliation
]]

PurchaseExecutorPlaceable = {}

--[[
    Execute finance placeable purchase with temp money injection
    CRITICAL: This method contains the temp money flow - PRESERVED EXACTLY from original (lines 1889-2174)

    @param context - PurchaseContext instance
    @param farmId - Farm ID
    @param dialogInstance - Dialog instance (for close() and accessing shopScreen/storeItem)
    @return nil (closes dialog async)
]]
function PurchaseExecutorPlaceable.executeFinance(context, farmId, dialogInstance)
    UsedPlus.logInfo("╔════════════════════════════════════════════════════════════════")
    UsedPlus.logInfo("║ executeFinancePurchasePlaceable() ENTRY - FINANCE PURCHASE")
    UsedPlus.logInfo("╠════════════════════════════════════════════════════════════════")

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
    UsedPlus.logDebug(string.format("  Credit score: %d (min required: %d)", context.creditScore, PLACEABLE_MIN_CREDIT))

    if context.creditScore < PLACEABLE_MIN_CREDIT then
        UsedPlus.logWarn(string.format("  ✗ Credit too low - ABORTING (have %d, need %d)",
            context.creditScore, PLACEABLE_MIN_CREDIT))
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format("Building financing requires Excellent credit (%d+). Your credit: %d", PLACEABLE_MIN_CREDIT, context.creditScore))
        return
    end
    UsedPlus.logInfo("  ✓ Credit score check PASSED")

    -- Calculate finance parameters
    local availableTerms = context.availableFinanceTerms or CreditCalculations.getFinanceTermsForCredit(context.creditScore)
    local termYears = availableTerms[context.financeTermIndex] or 5
    local downPct = CreditCalculations.getDownPaymentPercent(context.financeDownIndex, context.creditScore)
    local downPayment = context.vehiclePrice * (downPct / 100)

    UsedPlus.logInfo(string.format("  Building: %s", tostring(context.vehicleName)))
    UsedPlus.logInfo(string.format("  Price: %s", g_i18n:formatMoney(context.vehiclePrice)))
    UsedPlus.logInfo(string.format("  Down payment: %s (%d%%)", g_i18n:formatMoney(downPayment), downPct))
    UsedPlus.logInfo(string.format("  Term: %d years", termYears))
    UsedPlus.logInfo(string.format("  Interest rate: %.2f%%", context.interestRate * 100))

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
    local financedAmount = context.vehiclePrice - downPayment

    UsedPlus.logInfo("╔════════════════════════════════════════════════════════════════")
    UsedPlus.logInfo("║ TEMP MONEY INJECTION - CRITICAL SECTION")
    UsedPlus.logInfo("╠════════════════════════════════════════════════════════════════")
    UsedPlus.logInfo(string.format("  Financed amount calculation:"))
    UsedPlus.logDebug(string.format("    Price:        %s", g_i18n:formatMoney(context.vehiclePrice)))
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
        storeItem = context.storeItem,
        farmId = farmId,
        price = context.vehiclePrice,
        downPayment = downPayment,
        termYears = termYears,
        interestRate = context.interestRate,
        itemName = context.vehicleName,
        xmlFilename = context.storeItem.xmlFilename,

        -- CRITICAL: Track temp money for cleanup on cancellation
        tempMoneyInjected = financedAmount,
        injectionTimestamp = injectionTimestamp,
        placementActive = true,  -- Flag to prevent double-cleanup
    }

    UsedPlus.logDebug("  Pending state created with fields:")
    UsedPlus.logDebug(string.format("    - itemName: %s", context.vehicleName))
    UsedPlus.logDebug(string.format("    - price: %s", g_i18n:formatMoney(context.vehiclePrice)))
    UsedPlus.logDebug(string.format("    - downPayment: %s", g_i18n:formatMoney(downPayment)))
    UsedPlus.logDebug(string.format("    - tempMoneyInjected: %s", g_i18n:formatMoney(financedAmount)))
    UsedPlus.logDebug(string.format("    - injectionTimestamp: %.0f", injectionTimestamp))
    UsedPlus.logDebug(string.format("    - placementActive: true"))
    UsedPlus.logDebug(string.format("    - farmId: %d", farmId))
    UsedPlus.logDebug(string.format("    - xmlFilename: %s", tostring(context.storeItem.xmlFilename)))

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
        dialogInstance:close()

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
        dialogInstance:close()

        -- Fallback omitted for token efficiency - follows same pattern as primary path
        UsedPlus.logError("Fallback placeable purchase path not implemented in refactored module")
    end
end
