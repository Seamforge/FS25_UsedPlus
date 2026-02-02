# Placeable Purchase Hooks - Custom Finance/Purchase Dialogs

**Last Updated:** 2026-02-01
**Project:** FS25_UsedPlus
**Difficulty:** Advanced
**Tested:** FS25 v1.4+

## Overview

This guide documents how to intercept placeable purchases to show custom dialogs (e.g., financing options) BEFORE the purchase completes. This pattern was developed after extensive debugging of GUI state machine issues.

## The Challenge

When hooking placeable purchases to show a custom dialog, you'll encounter two critical issues:

1. **GUI State Corruption**: Using `showGui()` closes ConstructionScreen, which triggers placement cancellation
2. **Dialog Reuse Issues**: Reusing dialog instances causes input routing failures on subsequent purchases

## The Solution: Three-Part Pattern

### 1. PRE-BUY Hook with Bypass Flag

Hook `BuyPlaceableData.buy()` BEFORE the purchase executes:

```lua
BuyPlaceableDataExtension = {}

function BuyPlaceableDataExtension.buyHook(self, superFunc, callback, callbackTarget, callbackArguments)
    local storeItem = self.storeItem

    if not storeItem then
        return superFunc(self, callback, callbackTarget, callbackArguments)
    end

    -- Check if this item should show custom dialog
    if not shouldShowCustomDialog(storeItem) then
        return superFunc(self, callback, callbackTarget, callbackArguments)
    end

    -- Store buy data for later execution
    UsedPlus.pendingPlaceableBuy = {
        buyData = self,
        superFunc = superFunc,
        callback = callback,
        callbackTarget = callbackTarget,
        callbackArguments = callbackArguments,
        storeItem = storeItem,
        price = storeItem.price
    }

    -- Show custom dialog (see Section 2)
    showCustomDialog(storeItem)

    -- DON'T call superFunc yet - dialog will call it when user confirms
end

-- Initialize hook
function BuyPlaceableDataExtension:init()
    if BuyPlaceableData and BuyPlaceableData.buy then
        BuyPlaceableData.buy = Utils.overwrittenFunction(
            BuyPlaceableData.buy,
            BuyPlaceableDataExtension.buyHook
        )
    end
end
```

### 2. Dialog Unload/Reload Pattern

**CRITICAL**: Never reuse dialog instances for placeable purchases. Always unload and reload fresh:

```lua
function showCustomDialog(storeItem)
    local dialog = DialogLoader.getDialog("MyCustomDialog")

    if dialog then
        -- Dialog exists from previous purchase - DESTROY IT
        DialogLoader.unload("MyCustomDialog")

        -- Wait 1 frame for cleanup
        g_currentMission:addUpdateable({
            update = function(updatable, dt)
                g_currentMission:removeUpdateable(updatable)

                -- Reload fresh from XML
                if not DialogLoader.ensureLoaded("MyCustomDialog") then
                    print("ERROR: Failed to reload dialog!")
                    return
                end

                local freshDialog = DialogLoader.getDialog("MyCustomDialog")
                freshDialog:setData(storeItem)

                -- Show with bypass flag (see Section 3)
                showDialogWithBypass(freshDialog)
            end
        })
        return
    end

    -- First time - load and show
    DialogLoader.ensureLoaded("MyCustomDialog")
    local freshDialog = DialogLoader.getDialog("MyCustomDialog")
    freshDialog:setData(storeItem)
    showDialogWithBypass(freshDialog)
end
```

**DialogLoader.unload() implementation:**

```lua
function DialogLoader.unload(name)
    local dialog = g_gui.guis[name]
    if dialog then
        if dialog.close then
            dialog:close()
        end
        g_gui.guis[name] = nil
    end

    if DialogLoader.loaded[name] ~= nil then
        DialogLoader.loaded[name] = false
    end

    return true
end
```

### 3. Bypass Flag to Prevent Placement Cancellation

**THE PROBLEM**: When `showGui()` closes ConstructionScreen, it triggers `Placeable.finalizePlacement` cancellation logic, deleting the ghost building.

**THE SOLUTION**: Set a bypass flag before showing the dialog:

```lua
function showDialogWithBypass(dialog)
    -- Set bypass flag BEFORE showGui
    UsedPlus.bypassPlaceableCancellation = true

    -- Show dialog (this closes ConstructionScreen)
    g_gui:showGui("MyCustomDialog")

    -- Flag will be cleared in dialog's onOpen() and close()
end
```

**Hook the cancellation to check the flag:**

```lua
-- In your PlaceableSystemExtension
function PlaceableSystemExtension.onPlacementCancelled(placeable, ...)
    -- Check bypass flag
    if UsedPlus.bypassPlaceableCancellation then
        print("BYPASSING cancellation (dialog showing)")
        return  -- Don't process cancellation
    end

    -- Normal cancellation logic...
end

-- Hook it
if Placeable and Placeable.finalizePlacement then
    Placeable.finalizePlacement = Utils.appendedFunction(
        Placeable.finalizePlacement,
        PlaceableSystemExtension.onPlacementCancelled
    )
end
```

**Clear the flag in your dialog:**

```lua
function MyCustomDialog:onOpen()
    MyCustomDialog:superClass().onOpen(self)

    -- Safety clear (defensive programming)
    if UsedPlus.bypassPlaceableCancellation then
        print("WARNING: Bypass flag still set! Clearing...")
        UsedPlus.bypassPlaceableCancellation = nil
    end
end

function MyCustomDialog:close()
    -- Clear bypass flag to re-enable normal cancellation
    if UsedPlus.bypassPlaceableCancellation then
        UsedPlus.bypassPlaceableCancellation = nil
    end

    -- Clean up pending data
    UsedPlus.pendingPlaceableBuy = nil

    MyCustomDialog:superClass().close(self)
end
```

## Purchase Execution

When user confirms in your dialog:

```lua
function MyCustomDialog:onConfirm()
    local pending = UsedPlus.pendingPlaceableBuy
    if not pending then
        print("ERROR: No pending buy data!")
        self:close()
        return
    end

    -- Hide dialog but keep it alive until purchase completes
    self:setVisible(false)

    -- Execute the vanilla buy
    pending.superFunc(pending.buyData, pending.callback, pending.callbackTarget, pending.callbackArguments)

    -- Close dialog and ConstructionScreen after buy completes
    g_currentMission:addUpdateable({
        update = function(updatable, dt)
            g_currentMission:removeUpdateable(updatable)

            -- Close dialog
            self:close()

            -- Close ConstructionScreen immediately (no delay needed)
            if g_gui and g_gui.showGui then
                g_gui:showGui("")
            end
        end
    })
end
```

## Finance Flow with Temp Money

If implementing financing, use the temp money pattern:

```lua
function executeFinancePurchase(storeItem, downPayment, financedAmount)
    local farmId = g_currentMission:getFarmId()

    -- Inject temp money for financed amount
    g_currentMission:addMoney(financedAmount, farmId, MoneyType.OTHER, true, true)

    -- Store finance state for reconciliation
    UsedPlus.pendingPlaceableFinance = {
        farmId = farmId,
        itemName = storeItem.name,
        price = storeItem.price,
        downPayment = downPayment,
        tempMoneyInjected = financedAmount,
        xmlFilename = storeItem.xmlFilename,
        placementActive = true,
        preBuyMode = true
    }

    -- Execute buy (will deduct full price)
    local pending = UsedPlus.pendingPlaceableBuy
    pending.superFunc(pending.buyData, pending.callback, pending.callbackTarget, pending.callbackArguments)

    -- Reconciliation happens in finalizePlacement hook
end
```

**Reconciliation in finalizePlacement:**

```lua
function PlaceableSystemExtension.onPlaceableFinalized(placeable, ...)
    local pending = UsedPlus.pendingPlaceableFinance
    if not pending then return end

    -- Verify placeable matches
    if placeable.configFileName ~= pending.xmlFilename then return end

    -- Create finance deal
    local deal = FinanceDeal.new(
        pending.farmId,
        "placeable",
        placeable.configFileName,
        pending.itemName,
        pending.price,
        pending.downPayment,
        termMonths,
        interestRate,
        0  -- cashBack
    )

    g_financeManager:addDeal(deal)

    -- Show notification explaining the transaction
    local notifText = string.format(
        "%s FINANCED! Temp credit: %s (loan) | Full price: %s | Your cost today: %s down | Monthly: %s for %d years",
        pending.itemName,
        g_i18n:formatMoney(pending.tempMoneyInjected),
        g_i18n:formatMoney(pending.price),
        g_i18n:formatMoney(pending.downPayment),
        g_i18n:formatMoney(monthlyPayment),
        termYears
    )
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, notifText)

    -- Clear state
    UsedPlus.pendingPlaceableFinance = nil

    -- Close ConstructionScreen
    if g_gui and g_gui.showGui then
        g_gui:showGui("")
    end
end
```

## Common Pitfalls

### ❌ DON'T: Reuse Dialog Instances

```lua
-- WRONG - Second purchase will freeze!
local dialog = DialogLoader.getDialog("MyDialog")
if dialog then
    dialog:setData(newData)
    g_gui:showGui("MyDialog")  -- Input routing broken!
end
```

### ✅ DO: Unload and Reload Fresh

```lua
-- CORRECT - Fresh instance every time
if DialogLoader.getDialog("MyDialog") then
    DialogLoader.unload("MyDialog")
    -- Wait 1 frame, then reload fresh
end
```

### ❌ DON'T: Forget Bypass Flag

```lua
-- WRONG - ConstructionScreen close triggers cancellation!
g_gui:showGui("MyDialog")  // Ghost building deleted!
```

### ✅ DO: Set Bypass Flag First

```lua
-- CORRECT - Prevents unwanted cancellation
UsedPlus.bypassPlaceableCancellation = true
g_gui:showGui("MyDialog")
```

### ❌ DON'T: Add Delays to "Fix" Issues

```lua
-- WRONG - Delays make UX feel sluggish
g_currentMission:addUpdateable({
    update = function(updatable, dt)
        timer = timer + dt
        if timer >= 2000 then  -- 2 second delay - BAD!
            closeDialog()
        end
    end
})
```

### ✅ DO: Close Immediately

```lua
-- CORRECT - Instant, responsive UX
g_currentMission:addUpdateable({
    update = function(updatable, dt)
        g_currentMission:removeUpdateable(updatable)  -- Next frame
        closeDialog()  // Instant!
    end
})
```

## Why This Pattern Works

1. **PRE-BUY Timing**: Intercepts before money is deducted, allowing cancellation without refunds
2. **Bypass Flag**: Prevents ConstructionScreen closure from triggering unwanted cancellation
3. **Unload/Reload**: Ensures fresh dialog instance with clean input handlers
4. **Temp Money**: Allows vanilla buy() to deduct full price while player only pays down payment

## Alternative Approaches (Not Recommended)

### ❌ POST-BUY Hook
- Money already deducted
- Requires complex refund logic
- Can't prevent purchase, only react

### ❌ Manual currentGui Override
- Breaks GUI state machine
- Causes input routing failures
- Leads to "frozen dialog" syndrome

### ❌ showDialog() Without Bypass Flag
- Dialog shows as overlay
- ConstructionScreen stays active but ghost gets deleted
- Purchase flow breaks

## Testing Checklist

- [ ] First purchase works (dialog shows, buttons respond, purchase completes)
- [ ] Second purchase works (dialog is interactive, not frozen)
- [ ] Third+ purchases work (no state corruption)
- [ ] ESC cancels purchase properly (no money deducted)
- [ ] Finance flow correct (temp money → full deduct → down payment net)
- [ ] Transaction log understandable (notification explains temp money)
- [ ] No delays in UX (instant dialog close, instant return to game)
- [ ] Other dialogs still work (regression test)

## Real-World Example

See `FS25_UsedPlus` implementation:
- `src/extensions/BuyPlaceableDataExtension.lua` - PRE-BUY hook with bypass flag
- `src/extensions/PlaceableSystemExtension.lua` - Cancellation bypass + finalization
- `src/utils/DialogLoader.lua` - Unload/reload pattern
- `src/gui/UnifiedPurchaseDialog.lua` - Dialog lifecycle management
- `src/gui/unifiedpurchase/PurchaseExecutorPlaceable.lua` - Purchase execution

## Credits

Pattern developed by FS25_UsedPlus team after debugging GUI state machine issues (2026-02-01).

Key discoveries:
- Bypass flag prevents unwanted cancellation (critical insight!)
- Dialog unload/reload prevents input routing failures
- Immediate closes create responsive UX
- Transparent notifications explain temp money system
