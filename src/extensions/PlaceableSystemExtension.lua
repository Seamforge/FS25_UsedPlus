--[[
    FS25_UsedPlus - Placeable System Extension

    Hooks placeable placement/removal to handle financing:
    1. After placement: Detect financed placements, refund difference, create deal
    2. On removal: Early payoff for financed placeables

    v2.8.0: Created for construction financing feature
]]

PlaceableSystemExtension = {}

--[[
    Hook: Placeable finalization (called when player confirms placement position)
    This runs AFTER vanilla deducts full price, so we refund the financed amount

    Pattern: Utils.appendedFunction on Placeable.finalizePlacement
]]
function PlaceableSystemExtension.onPlaceableFinalized(placeable, ...)
    UsedPlus.logInfo("╔════════════════════════════════════════════════════════════════")
    UsedPlus.logInfo("║ PlaceableSystemExtension.onPlaceableFinalized() ENTRY")
    UsedPlus.logInfo("╠════════════════════════════════════════════════════════════════")
    UsedPlus.logDebug(string.format("  placeable.configFileName: %s",
        tostring(placeable and placeable.configFileName)))
    UsedPlus.logDebug(string.format("  isServer: %s", tostring(g_server ~= nil)))

    if not g_server then
        UsedPlus.logDebug("  Not server - skipping (server authority only)")
        UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")
        return
    end

    -- Check for pending finance deal
    local pending = UsedPlus.pendingPlaceableFinance
    UsedPlus.logDebug(string.format("  pendingPlaceableFinance exists: %s", tostring(pending ~= nil)))

    if not pending then
        UsedPlus.logDebug("  No pending finance - this was a CASH purchase, nothing to reconcile")

        -- Close the hidden dialog now that placement is complete
        if UsedPlus.pendingPlaceableDialog then
            UsedPlus.logDebug("  → Closing hidden dialog")
            UsedPlus.pendingPlaceableDialog:close()
            UsedPlus.pendingPlaceableDialog = nil
        end

        UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")
        return
    end

    -- v2.8.4: Check for PRE-BUY mode (dialog already handled, just create finance deal)
    local isPreBuyMode = pending.preBuyMode
    if isPreBuyMode then
        UsedPlus.logInfo("  ✅ PRE-BUY MODE - Dialog already handled, creating finance deal now")
    else
        UsedPlus.logWarn("  ⚠️  OLD MODE (not preBuyMode) - unexpected state!")
    end

    UsedPlus.logInfo("  → Found pending finance state - FINANCE purchase detected")

    -- Dump pending state for analysis
    UsedPlus.logDebug("  Pending state:")
    UsedPlus.logDebug(string.format("    - itemName: %s", tostring(pending.itemName)))
    UsedPlus.logDebug(string.format("    - price: %s", g_i18n:formatMoney(pending.price or 0)))
    UsedPlus.logDebug(string.format("    - downPayment: %s", g_i18n:formatMoney(pending.downPayment or 0)))
    UsedPlus.logDebug(string.format("    - tempMoneyInjected: %s", g_i18n:formatMoney(pending.tempMoneyInjected or 0)))
    UsedPlus.logDebug(string.format("    - placementActive: %s", tostring(pending.placementActive)))
    UsedPlus.logDebug(string.format("    - xmlFilename: %s", tostring(pending.xmlFilename)))

    -- Verify this is the right placeable (match by xmlFilename)
    local placeableXml = placeable.configFileName or placeable.xmlFilename
    UsedPlus.logDebug(string.format("  Placed placeable xmlFilename: %s", tostring(placeableXml)))
    UsedPlus.logDebug(string.format("  Expected xmlFilename: %s", tostring(pending.xmlFilename)))

    if placeableXml ~= pending.xmlFilename then
        UsedPlus.logWarn(string.format("  ✗ Placeable mismatch! Expected %s, got %s - ABORTING",
            tostring(pending.xmlFilename), tostring(placeableXml)))
        UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")
        return
    end

    UsedPlus.logInfo(string.format("  ✓ Placeable match verified: %s", pending.itemName))

    -- Get current balance to verify money flow
    local farmId = pending.farmId or g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)
    local balanceBeforeReconciliation = farm and farm.money or 0

    UsedPlus.logInfo("╔════════════════════════════════════════════════════════════════")
    UsedPlus.logInfo("║ FINALIZATION RECONCILIATION - MONEY FLOW")
    UsedPlus.logInfo("╠════════════════════════════════════════════════════════════════")
    UsedPlus.logDebug("  Money flow analysis:")
    UsedPlus.logDebug(string.format("    1. Player started with: ~%s (down payment)",
        g_i18n:formatMoney(pending.downPayment)))
    UsedPlus.logDebug(string.format("    2. We injected temp: +%s",
        g_i18n:formatMoney(pending.tempMoneyInjected)))
    UsedPlus.logDebug(string.format("    3. Balance became: ~%s (total price)",
        g_i18n:formatMoney(pending.price)))
    UsedPlus.logDebug(string.format("    4. Vanilla deducted: -%s (full price)",
        g_i18n:formatMoney(pending.price)))
    UsedPlus.logDebug(string.format("    5. Balance now: %s (should be ~$0)",
        g_i18n:formatMoney(balanceBeforeReconciliation)))

    -- Mark reconciled (prevent double-processing or cleanup in close())
    UsedPlus.logInfo("  → Marking placementActive = false (prevents double-cleanup)")
    pending.placementActive = false

    -- v2.8.1: NO REFUND - player already paid down payment via temp money system
    UsedPlus.logInfo("  → NO REFUND (temp money system - player paid down payment already)")
    UsedPlus.logDebug("     Net result: Player paid %s down, owes %s financed",
        g_i18n:formatMoney(pending.downPayment),
        g_i18n:formatMoney(pending.price - pending.downPayment))
    UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")

    -- Calculate monthly payment (reuse existing calculations)
    local termMonths = pending.termYears * 12
    local principalFinanced = pending.price - pending.downPayment

    UsedPlus.logInfo("╔════════════════════════════════════════════════════════════════")
    UsedPlus.logInfo("║ CREATING FINANCE DEAL")
    UsedPlus.logInfo("╠════════════════════════════════════════════════════════════════")
    UsedPlus.logDebug(string.format("  Principal financed: %s", g_i18n:formatMoney(principalFinanced)))
    UsedPlus.logDebug(string.format("  Interest rate: %.2f%%", pending.interestRate))
    UsedPlus.logDebug(string.format("  Term: %d months (%d years)", termMonths, pending.termYears))

    local monthlyPayment = FinanceCalculations.calculateMonthlyPayment(
        principalFinanced,
        pending.interestRate,
        termMonths
    )

    UsedPlus.logDebug(string.format("  Calculated monthly payment: %s", g_i18n:formatMoney(monthlyPayment)))

    -- Create finance deal
    -- Note: itemId is the placeable's unique ID, but it's not available until after finalizePlacement
    -- So we use xmlFilename as itemId for now, and will associate actual ID later if needed
    UsedPlus.logDebug("  Creating FinanceDeal object...")
    local deal = FinanceDeal.new(
        pending.farmId,
        "placeable",                    -- itemType
        placeableXml,                   -- itemId (xmlFilename for now)
        pending.itemName,               -- itemName
        pending.price,                  -- basePrice
        pending.downPayment,            -- downPayment
        termMonths,                     -- termMonths
        pending.interestRate,           -- interestRate
        0                               -- cashBack (not applicable to placeables)
    )

    UsedPlus.logDebug(string.format("  Deal created with ID: %s", tostring(deal.id)))

    -- Add deal to manager
    if g_financeManager then
        UsedPlus.logDebug("  Adding deal to FinanceManager...")
        g_financeManager:addDeal(deal)
        UsedPlus.logInfo(string.format("  ✓ Finance deal created: %s, monthly=%s for %d years",
            pending.itemName, g_i18n:formatMoney(monthlyPayment), pending.termYears))
    else
        UsedPlus.logError("  ✗ FinanceManager not available - CRITICAL: deal not created!")
        UsedPlus.logError("     Player has paid down payment but has no finance deal!")
    end
    UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")

    -- Note: FinanceManager:createDeal() already handles multiplayer sync via savegame
    -- No additional event needed for placeable finance deals

    -- Verify final balance
    local farm3 = g_farmManager:getFarmById(farmId)
    local finalBalance = farm3 and farm3.money or 0
    UsedPlus.logDebug(string.format("  Final balance after finalization: %s", g_i18n:formatMoney(finalBalance)))
    UsedPlus.logDebug(string.format("  Expected final balance: ~$0 (paid down payment of %s)",
        g_i18n:formatMoney(pending.downPayment)))

    -- Custom notification explaining the finance mechanics
    UsedPlus.logInfo("  → Showing user notification")
    local notifText = string.format(
        "%s FINANCED! Temp credit: %s (loan) | Full price: %s | Your cost today: %s down | Monthly: %s for %d years",
        pending.itemName,
        g_i18n:formatMoney(pending.tempMoneyInjected),
        g_i18n:formatMoney(pending.price),
        g_i18n:formatMoney(pending.downPayment),
        g_i18n:formatMoney(monthlyPayment),
        pending.termYears
    )
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        notifText
    )

    -- Clear pending state (safe to do now that deal is created)
    UsedPlus.logInfo("  → Clearing pendingPlaceableFinance (reconciliation complete)")
    UsedPlus.pendingPlaceableFinance = nil

    -- Close the hidden dialog now that placement and financing is complete
    if UsedPlus.pendingPlaceableDialog then
        UsedPlus.logDebug("  → Closing hidden dialog")
        UsedPlus.pendingPlaceableDialog:close()
        UsedPlus.pendingPlaceableDialog = nil
    end

    -- v2.8.4: Close Construction Screen immediately after finance deal created
    if isPreBuyMode then
        if g_gui and g_gui.showGui then
            UsedPlus.logInfo("  🏗️  Closing Construction Screen (finance complete)")
            g_gui:showGui("")  -- Close current GUI
        end
    end

    UsedPlus.logInfo("║ PlaceableSystemExtension.onPlaceableFinalized() EXIT - SUCCESS")
    UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")
end

--[[
    Hook: Placeable deletion (called when player sells/removes placeable)
    Deduct remaining loan balance from sale proceeds (early payoff)
]]
function PlaceableSystemExtension.onPlaceableDeleted(placeable, ...)
    if not g_server then return end  -- Server authority only

    -- Find active deal for this placeable
    if not g_financeManager then return end

    local placeableXml = placeable.configFileName or placeable.xmlFilename

    -- Find deal by looping through all deals (no findDealByItem method exists)
    local deal = nil
    for _, d in pairs(g_financeManager.deals) do
        if d.itemType == "placeable" and d.itemId == placeableXml and d.status == "active" then
            deal = d
            break
        end
    end

    if not deal then
        UsedPlus.logDebug("PlaceableSystemExtension: No finance deal for deleted placeable")
        return
    end

    -- Calculate payoff amount (remaining balance)
    local payoff = deal.currentBalance or 0

    if payoff > 0 then
        UsedPlus.logInfo(string.format("Placeable sold: %s, loan payoff=%s", deal.itemName, g_i18n:formatMoney(payoff)))

        -- Mark deal as paid off (remove from manager)
        deal.status = "paid_off"
        g_financeManager:removeDeal(deal.id)

        -- Notification (vanilla already deducted payoff from sale proceeds)
        local notifText = g_i18n:getText("usedplus_notify_placeableSoldPayoff") or "Building sold. Loan payoff: %s"
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format(notifText, g_i18n:formatMoney(payoff))
        )
    end
end

--[[
    Hook: Placement cancellation (called when player cancels placement or deletes during placement)
    This handles cleanup of temp money injection for financed placements

    v2.8.1: Critical for preventing money leakage when user ESC's during placement
]]
function PlaceableSystemExtension.onPlacementCancelled(placeable, ...)
    UsedPlus.logInfo("╔════════════════════════════════════════════════════════════════")
    UsedPlus.logInfo("║ PlaceableSystemExtension.onPlacementCancelled() ENTRY")
    UsedPlus.logInfo("╠════════════════════════════════════════════════════════════════")
    UsedPlus.logDebug(string.format("  placeable: %s", tostring(placeable and placeable.configFileName)))

    -- CRITICAL: Check bypass flag (prevents cancellation during dialog show)
    -- When showGui() closes ConstructionScreen, it triggers this hook
    -- But we're just showing a payment dialog, not actually cancelling placement
    if UsedPlus.bypassPlaceableCancellation then
        UsedPlus.logInfo("  ⏭️  BYPASSING cancellation (dialog showing, not real cancel)")
        UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")
        return
    end

    -- Check for pending finance deal
    local pending = UsedPlus.pendingPlaceableFinance
    UsedPlus.logDebug(string.format("  pendingPlaceableFinance exists: %s", tostring(pending ~= nil)))

    if not pending then
        UsedPlus.logDebug("  No pending finance - nothing to clean up")
        UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")
        return
    end

    UsedPlus.logInfo("  → Found pending finance state")

    -- Dump pending state
    UsedPlus.logDebug("  Pending state:")
    UsedPlus.logDebug(string.format("    - itemName: %s", tostring(pending.itemName)))
    UsedPlus.logDebug(string.format("    - price: %s", g_i18n:formatMoney(pending.price or 0)))
    UsedPlus.logDebug(string.format("    - downPayment: %s", g_i18n:formatMoney(pending.downPayment or 0)))
    UsedPlus.logDebug(string.format("    - tempMoneyInjected: %s", g_i18n:formatMoney(pending.tempMoneyInjected or 0)))
    UsedPlus.logDebug(string.format("    - placementActive: %s", tostring(pending.placementActive)))

    -- Check if already reconciled (finalization or close() already handled it)
    if not pending.placementActive then
        UsedPlus.logDebug("  placementActive = false - already reconciled by finalization or close()")
        UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")
        return
    end

    UsedPlus.logInfo("  → Placement was CANCELLED - initiating temp money reclaim")

    -- Get balance before reclaim
    local farmId = pending.farmId or g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)
    local balanceBeforeReclaim = farm and farm.money or 0

    UsedPlus.logInfo("╔════════════════════════════════════════════════════════════════")
    UsedPlus.logInfo("║ CANCELLATION RECONCILIATION - MONEY FLOW")
    UsedPlus.logInfo("╠════════════════════════════════════════════════════════════════")
    UsedPlus.logDebug("  Money flow on cancellation:")
    UsedPlus.logDebug(string.format("    1. Player started with: ~%s (down payment)",
        g_i18n:formatMoney(pending.downPayment)))
    UsedPlus.logDebug(string.format("    2. We injected temp: +%s",
        g_i18n:formatMoney(pending.tempMoneyInjected)))
    UsedPlus.logDebug(string.format("    3. Balance became: ~%s (total price)",
        g_i18n:formatMoney(pending.price)))
    UsedPlus.logDebug(string.format("    4. Vanilla deducted: -%s (full price)",
        g_i18n:formatMoney(pending.price)))
    UsedPlus.logDebug(string.format("    5. User pressed ESC"))
    UsedPlus.logDebug(string.format("    6. Vanilla refunded: +%s (full price)",
        g_i18n:formatMoney(pending.price)))
    UsedPlus.logDebug(string.format("    7. Balance before reclaim: %s",
        g_i18n:formatMoney(balanceBeforeReclaim)))
    UsedPlus.logDebug(string.format("    8. Expected: ~%s (original + full refund)",
        g_i18n:formatMoney(pending.price)))

    -- Mark reconciled
    UsedPlus.logDebug("  → Marking placementActive = false")
    pending.placementActive = false

    -- Vanilla already refunded full price (if placement started)
    -- We must reclaim the temp money we injected to restore original balance
    local tempMoney = pending.tempMoneyInjected or 0
    UsedPlus.logDebug(string.format("  Temp money to reclaim: %s", g_i18n:formatMoney(tempMoney)))

    if tempMoney > 0 then
        UsedPlus.logInfo(string.format("  → RECLAIMING TEMP MONEY: %s", g_i18n:formatMoney(tempMoney)))
        g_currentMission:addMoney(-tempMoney, pending.farmId, MoneyType.OTHER, true, false)

        -- Verify reclaim worked
        local farm2 = g_farmManager:getFarmById(pending.farmId)
        local balanceAfterReclaim = farm2 and farm2.money or 0
        UsedPlus.logDebug(string.format("  Balance AFTER reclaim: %s", g_i18n:formatMoney(balanceAfterReclaim)))
        UsedPlus.logDebug(string.format("  Expected after reclaim: %s (should match original down payment)",
            g_i18n:formatMoney(pending.downPayment)))

        local expectedBalance = balanceBeforeReclaim - tempMoney
        if math.abs(balanceAfterReclaim - expectedBalance) < 1 then
            UsedPlus.logInfo("  ✓ Temp money reclaim VERIFIED - balance restored")
        else
            UsedPlus.logWarn(string.format("  ✗ Balance mismatch! Expected %s, got %s",
                g_i18n:formatMoney(expectedBalance),
                g_i18n:formatMoney(balanceAfterReclaim)))
        end
    else
        UsedPlus.logWarn("  No temp money to reclaim (tempMoneyInjected = 0)")
    end

    UsedPlus.logDebug("  Net result: Player back to original balance (~%s)",
        g_i18n:formatMoney(pending.downPayment))
    UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")

    -- Clear pending
    UsedPlus.logInfo("  → Clearing pendingPlaceableFinance")
    UsedPlus.pendingPlaceableFinance = nil

    -- Notify user
    UsedPlus.logDebug("  → Showing cancellation notification")
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_INFO,
        "Placement cancelled"
    )

    UsedPlus.logInfo("║ PlaceableSystemExtension.onPlacementCancelled() EXIT - SUCCESS")
    UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")
end

--[[
    Deferred initialization - called from main.lua after mission loads
    Placeable class should be available at mission load time
]]
function PlaceableSystemExtension:init()
    UsedPlus.logInfo("PlaceableSystemExtension: Attempting deferred initialization...")

    if Placeable and Placeable.finalizePlacement then
        Placeable.finalizePlacement = Utils.appendedFunction(
            Placeable.finalizePlacement,
            PlaceableSystemExtension.onPlaceableFinalized
        )
        UsedPlus.logInfo("PlaceableSystemExtension: Successfully hooked finalizePlacement")
    else
        UsedPlus.logWarn("PlaceableSystemExtension: Placeable.finalizePlacement not available")
    end

    if Placeable and Placeable.delete then
        -- Hook delete for both cancellation AND sale payoff
        -- onPlacementCancelled checks pending state, onPlaceableDeleted checks active deals
        Placeable.delete = Utils.prependedFunction(
            Placeable.delete,
            function(placeable, ...)
                PlaceableSystemExtension.onPlacementCancelled(placeable, ...)
                PlaceableSystemExtension.onPlaceableDeleted(placeable, ...)
            end
        )
        UsedPlus.logInfo("PlaceableSystemExtension: Successfully hooked delete (cancellation + payoff)")
    else
        UsedPlus.logWarn("PlaceableSystemExtension: Placeable.delete not available")
    end
end

UsedPlus.logInfo("PlaceableSystemExtension loaded (awaiting init)")
