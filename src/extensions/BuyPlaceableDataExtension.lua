--[[
    FS25_UsedPlus - Buy Placeable Data Extension

    Hooks BuyPlaceableData.buy() to show financing dialog BEFORE purchase executes.

    Flow (PRE-BUY Dialog):
    1. User clicks building → Ghost appears (vanilla)
    2. User positions ghost → Left-clicks to confirm
    3. buy() called → **WE INTERCEPT HERE**
    4. Show dialog: "How do you want to pay?"
    5. User chooses → Inject temp money if finance
    6. Call vanilla buy() → Runs completely
    7. Finalize finance deal
    8. Done - no freeze, no state issues

    v2.8.4: Rewritten for PRE-BUY dialog (sweet spot approach)
]]

BuyPlaceableDataExtension = {}

--[[
    Hook: BuyPlaceableData.buy()

    Intercepts BEFORE buy() executes (after user confirms position).
    Shows financing dialog, then lets buy() run normally.
]]
function BuyPlaceableDataExtension.buyHook(self, superFunc, callback, callbackTarget, callbackArguments)
    UsedPlus.logInfo("═══════════════════════════════════════════════════════════")
    UsedPlus.logInfo("BuyPlaceableDataExtension.buyHook() - PRE-BUY INTERCEPTION")
    UsedPlus.logInfo("═══════════════════════════════════════════════════════════")

    -- v2.15.5: Check if finance system is enabled (#42)
    -- Must pass through to vanilla when disabled — vanilla buy() handles
    -- fence/meadow customization that our interception would skip.
    local financeEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Finance")
    if not financeEnabled then
        return superFunc(self, callback, callbackTarget, callbackArguments)
    end

    -- Get the store item
    local storeItem = self.storeItem

    if not storeItem then
        UsedPlus.logWarn("No storeItem - falling back to vanilla")
        return superFunc(self, callback, callbackTarget, callbackArguments)
    end

    UsedPlus.logInfo(string.format("📦 Placeable: %s", tostring(storeItem.name)))
    UsedPlus.logInfo(string.format("💰 Price: %s", g_i18n:formatMoney(storeItem.price or 0)))

    -- Check if financeable
    local canFinance = ShopConfigScreenExtension and ShopConfigScreenExtension.canFinanceItem
        and ShopConfigScreenExtension.canFinanceItem(storeItem)

    if not canFinance then
        UsedPlus.logInfo("❌ Not financeable - vanilla cash purchase")
        return superFunc(self, callback, callbackTarget, callbackArguments)
    end

    -- Check credit score (750+ for placeables)
    local farmId = g_currentMission:getFarmId()
    local creditScore = 650
    if CreditScore and CreditScore.calculate then
        creditScore = CreditScore.calculate(farmId)
    end

    local PLACEABLE_MIN_CREDIT = 750
    if creditScore < PLACEABLE_MIN_CREDIT then
        UsedPlus.logInfo(string.format("❌ Credit too low (%d < %d) - vanilla cash only", creditScore, PLACEABLE_MIN_CREDIT))

        -- Notify user why financing isn't available
        local notifText = string.format(
            g_i18n:getText("usedplus_notification_buildingFinanceCreditLow"),
            creditScore
        )
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            notifText
        )

        return superFunc(self, callback, callbackTarget, callbackArguments)
    end

    UsedPlus.logInfo(string.format("✅ Financeable | Credit: %d", creditScore))

    -- Calculate down payment (20% for placeables)
    local price = storeItem.price or 0
    local downPayment = math.floor(price * 0.20)

    -- Check affordability for down payment
    local farm = g_farmManager:getFarmById(farmId)
    if not farm or farm.money < downPayment then
        UsedPlus.logInfo(string.format("❌ Can't afford down payment (%s) - vanilla cash only",
            g_i18n:formatMoney(downPayment)))
        return superFunc(self, callback, callbackTarget, callbackArguments)
    end

    UsedPlus.logInfo("✅ Down payment affordable - showing finance dialog")

    -- CRITICAL FIX 1.2: Store buy data FIRST (before any dialog checks)
    -- This ensures forced-close path has data to work with
    UsedPlus.pendingPlaceableBuy = {
        buyData = self,
        superFunc = superFunc,
        callback = callback,
        callbackTarget = callbackTarget,
        callbackArguments = callbackArguments,
        storeItem = storeItem,
        farmId = farmId,
        price = price,
        downPayment = downPayment
    }
    UsedPlus.logDebug("  ✓ Stored pendingPlaceableBuy data")

    -- Show dialog using standard DialogLoader (handles dialog reuse properly)
    UsedPlus.logInfo("📋 Showing UnifiedPurchaseDialogPlaceable via DialogLoader...")

    -- DIAGNOSTIC: Check current dialog state before showing
    local currentGui = g_gui.currentGui
    UsedPlus.logInfo(string.format("  Current GUI: %s", currentGui and currentGui.name or "none"))

    -- DEFENSIVE CLEANUP: Clear stale global state from previous purchases
    if UsedPlus.pendingPlaceableFinance and not UsedPlus.pendingPlaceableFinance.placementActive then
        UsedPlus.logDebug("  🧹 Clearing stale pendingPlaceableFinance from previous purchase")
        UsedPlus.pendingPlaceableFinance = nil
    end

    if UsedPlus.pendingPlaceableDialog then
        UsedPlus.logDebug("  🧹 Clearing stale pendingPlaceableDialog reference")
        UsedPlus.pendingPlaceableDialog = nil
    end

    local dialog = DialogLoader.getDialog("UnifiedPurchaseDialogPlaceable")
    if dialog then
        UsedPlus.logInfo(string.format("  Dialog exists: true"))
        UsedPlus.logInfo(string.format("  Dialog visible: %s", tostring(dialog.isVisible)))
        UsedPlus.logInfo(string.format("  Dialog isOpen: %s", tostring(dialog.isOpen)))

        -- CRITICAL FIX: Completely UNLOAD existing dialog to force fresh reload
        -- Reusing a dialog instance causes input routing issues on second use
        -- Solution: Destroy it completely and reload from XML
        UsedPlus.logDebug("  ⚠️  DIALOG EXISTS - Destroying and reloading fresh!")
        UsedPlus.logDebug(string.format("    - visible=%s, currentGui=%s, isOpen=%s",
            tostring(dialog.isVisible),
            currentGui and currentGui.name or "none",
            tostring(dialog.isOpen)))

        -- Completely unload the dialog (closes, removes from g_gui, marks unloaded)
        DialogLoader.unload("UnifiedPurchaseDialogPlaceable")

        -- Wait 1 frame for unload to complete
        local frameDelay = 0
        g_currentMission:addUpdateable({
            update = function(updatable, dt)
                frameDelay = frameDelay + 1
                if frameDelay >= 1 then
                    g_currentMission:removeUpdateable(updatable)

                    UsedPlus.logInfo("  → Reloading dialog fresh after unload...")

                    -- Reload dialog fresh from XML (like first-time load)
                    if not DialogLoader.ensureLoaded("UnifiedPurchaseDialogPlaceable") then
                        UsedPlus.logError("  ✗ Failed to reload dialog!")
                        return
                    end

                    -- Get the fresh dialog instance
                    local dialog2 = DialogLoader.getDialog("UnifiedPurchaseDialogPlaceable")
                    if not dialog2 then
                        UsedPlus.logError("  ✗ Dialog not found after reload!")
                        return
                    end

                    UsedPlus.logInfo("  ✓ Dialog reloaded fresh from XML")

                    -- Set data first (updates member variables only)
                    -- onOpen() will refresh UI from these variables when dialog shows
                    if dialog2.setVehicleData then
                        dialog2:setVehicleData(storeItem, price, nil, nil)
                        UsedPlus.logDebug("  ✓ setVehicleData called")
                    end

                    -- Show as active GUI (NOT showDialog!)
                    -- This properly handles ConstructionScreen → Dialog transition
                    -- CRITICAL: Set bypass flag to prevent placement cancellation
                    -- When showGui() closes ConstructionScreen, it triggers onPlacementCancelled
                    -- We need to block that cancellation since we're just showing a payment dialog
                    UsedPlus.bypassPlaceableCancellation = true
                    UsedPlus.logInfo("  → Set bypassPlaceableCancellation flag (prevent ghost deletion)")
                    UsedPlus.logInfo("  → Calling g_gui:showGui('UnifiedPurchaseDialogPlaceable')...")
                    g_gui:showGui("UnifiedPurchaseDialogPlaceable")

                    -- Verify currentGui
                    local afterGui = g_gui.currentGui
                    UsedPlus.logInfo(string.format("  Current GUI after show: %s",
                        afterGui and afterGui.name or "none"))

                    if afterGui and afterGui.name ~= "UnifiedPurchaseDialogPlaceable" then
                        UsedPlus.logError(string.format("  ✗ INPUT ROUTING FAILED! currentGui=%s",
                            afterGui.name))
                    end

                    -- Reset mode to Cash
                    if dialog2.setInitialMode then
                        dialog2:setInitialMode(UnifiedPurchaseDialog.MODE_CASH)
                        UsedPlus.logDebug("  ✓ Reset dialog mode to Cash")
                    end
                end
            end
        })
        return  -- Don't call superFunc yet (buy data already stored)
    end

    -- Don't close ConstructionScreen manually - showGui() will handle transition
    UsedPlus.logInfo("  → Showing placeable dialog (first time)...")

    -- Wait 1 frame for ConstructionScreen to stabilize
    local frameDelay = 0
    g_currentMission:addUpdateable({
        update = function(updatable, dt)
            frameDelay = frameDelay + 1
            if frameDelay >= 1 then
                g_currentMission:removeUpdateable(updatable)

                UsedPlus.logInfo("  → Dialog ready to show...")

                -- Ensure loaded
                if not DialogLoader.ensureLoaded("UnifiedPurchaseDialogPlaceable") then
                    UsedPlus.logError("  ✗ Failed to load dialog!")
                    return
                end

                -- Get dialog instance
                local dialog = DialogLoader.getDialog("UnifiedPurchaseDialogPlaceable")
                if not dialog then
                    UsedPlus.logError("  ✗ Dialog not found!")
                    return
                end

                -- Set data first (updates member variables only)
                -- onOpen() will refresh UI from these variables when dialog shows
                if dialog.setVehicleData then
                    dialog:setVehicleData(storeItem, price, nil, nil)
                    UsedPlus.logDebug("  ✓ setVehicleData called")
                end

                -- Show as active GUI
                -- CRITICAL: Set bypass flag to prevent placement cancellation
                -- When showGui() closes ConstructionScreen, it triggers onPlacementCancelled
                -- We need to block that cancellation since we're just showing a payment dialog
                UsedPlus.bypassPlaceableCancellation = true
                UsedPlus.logInfo("  → Set bypassPlaceableCancellation flag (prevent ghost deletion)")
                UsedPlus.logInfo("  → Calling g_gui:showGui('UnifiedPurchaseDialogPlaceable')...")
                g_gui:showGui("UnifiedPurchaseDialogPlaceable")

                -- Verify currentGui
                local afterGui = g_gui.currentGui
                UsedPlus.logInfo(string.format("  Current GUI after show: %s",
                    afterGui and afterGui.name or "none"))

                if afterGui and afterGui.name ~= "UnifiedPurchaseDialogPlaceable" then
                    UsedPlus.logError(string.format("  ✗ INPUT ROUTING FAILED! currentGui=%s",
                        afterGui.name))
                end

                -- Reset mode to Cash
                if dialog.setInitialMode then
                    dialog:setInitialMode(UnifiedPurchaseDialog.MODE_CASH)
                    UsedPlus.logDebug("  ✓ Reset dialog mode to Cash")
                end
            end
        end
    })

    -- DON'T call superFunc yet - dialog will trigger it
    UsedPlus.logInfo("⏸️  Paused buy() - waiting for dialog response")
    UsedPlus.logInfo("═══════════════════════════════════════════════════════════")
end

--[[
    Initialize hook (called from main.lua after game loads)
]]
function BuyPlaceableDataExtension:init()
    UsedPlus.logInfo("BuyPlaceableDataExtension: Initializing PRE-BUY dialog hook...")

    if BuyPlaceableData and BuyPlaceableData.buy then
        BuyPlaceableData.buy = Utils.overwrittenFunction(
            BuyPlaceableData.buy,
            BuyPlaceableDataExtension.buyHook
        )
        UsedPlus.logInfo("✅ BuyPlaceableData.buy() hooked successfully (PRE-BUY mode)")
    else
        UsedPlus.logWarn("⚠️  BuyPlaceableData class not available")
    end
end

UsedPlus.logInfo("BuyPlaceableDataExtension loaded (PRE-BUY mode)")
