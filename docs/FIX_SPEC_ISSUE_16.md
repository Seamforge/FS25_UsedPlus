# Fix Specification: Issue #16 — Defensive Hardening of Global Hooks

**Issue:** [#16 — Buying vehicles bug](https://github.com/XelaNull/FS25_UsedPlus/issues/16)
**Priority:** High
**Type:** Bug Fix / Defensive Hardening
**Affects:** `VehicleSellingPointExtension.lua`, `InGameMenuMapFrameExtension.lua`

---

## Problem Summary

A user reports that "sometimes when I go to buy a vehicle I click on the thing I wanna buy and nothing happens" — the shop customization screen fails to open. The issue is intermittent and only appeared after installing UsedPlus.

Log analysis showed:
- **No UsedPlus LUA errors** in the log
- **3/3 shop purchases succeeded** in the captured session
- **9 occurrences** of `Error: Running LUA method 'mouseEvent'. dataS/scripts/FSBaseMission.lua:2472: attempt to index nil with 'id'` — all related to map interactions
- User has `FS25_FarmlandOverview` installed, which likely hooks the same map frame system

Our code review identified **three defensive issues** that could cause or contribute to these symptoms.

---

## Fix 1: Add Double-Call Guard to `hookShowYesNoDialog()`

### File
`src/extensions/VehicleSellingPointExtension.lua`

### Problem
`hookShowYesNoDialog()` (line 323) has **no guard** against being called twice. It unconditionally saves `g_gui.showYesNoDialog` to `originalShowYesNoDialog` and replaces it with our wrapper.

If called twice:
1. First call: `originalShowYesNoDialog` = vanilla `showYesNoDialog`. Wrapper installed.
2. Second call: `originalShowYesNoDialog` = **our wrapper** (from call 1). New wrapper installed that calls the old wrapper.
3. Result: **Infinite recursion** or double-interception when any yes/no dialog opens.

The function is currently called from `VehicleSellingPointExtension.init()` (line 516). While `init()` is only called once today, there is no protection if the call chain changes or if another code path triggers it.

### Current Code (lines 323-330)
```lua
function VehicleSellingPointExtension.hookShowYesNoDialog()
    if g_gui == nil then
        UsedPlus.logDebug("g_gui not available, skipping showYesNoDialog hook")
        return
    end

    -- Save original function
    VehicleSellingPointExtension.originalShowYesNoDialog = g_gui.showYesNoDialog
```

### Fix
Add a guard identical to the one in `hookAllDialogs()` (lines 533-536):

```lua
function VehicleSellingPointExtension.hookShowYesNoDialog()
    if g_gui == nil then
        UsedPlus.logDebug("g_gui not available, skipping showYesNoDialog hook")
        return
    end

    -- Only hook showYesNoDialog once
    if VehicleSellingPointExtension.originalShowYesNoDialog ~= nil then
        UsedPlus.logTrace("showYesNoDialog already hooked")
        return
    end

    -- Save original function
    VehicleSellingPointExtension.originalShowYesNoDialog = g_gui.showYesNoDialog
```

### Verification
- Search for all call sites of `hookShowYesNoDialog()` (currently only line 516)
- Confirm the guard fires on hypothetical second call
- Test that yes/no dialogs (sell vehicle, repair confirm) still work correctly

---

## Fix 2: Add Re-Entrancy Guard to Action ID Shifting

### File
`src/extensions/InGameMenuMapFrameExtension.lua`

### Problem
`onLoadMapFinished()` (line 24) shifts **all** action IDs in the class-level table `InGameMenuMapFrame.ACTIONS` up by 2 to make room for FINANCE_LAND and LEASE_LAND. The individual action registrations (REPAIR_VEHICLE, FINANCE_LAND, LEASE_LAND) have guards (`if ACTIONS.X == nil`), but the **ID shifting code itself has NO guard**.

If `onLoadMapFinished` is called twice (e.g., map reload, mod conflict):
1. First call: IDs correctly shifted. FINANCE_LAND registered at `BUY+1`, LEASE_LAND at `BUY+2`.
2. Second call: IDs shifted **again** (+2 more). Registration guards fire (actions already exist), so no new actions added. But now all other action IDs are **+4 from original** while FINANCE_LAND/LEASE_LAND are still at their original positions.
3. Result: `contextActions` table has **gaps** and **mismatched IDs**. When the game iterates context actions by ID, it hits `nil` entries → `attempt to index nil with 'id'` → the exact error in the user's log.

Additionally, if another mod (like `FS25_FarmlandOverview`) also adds entries to `InGameMenuMapFrame.ACTIONS`, our shifting corrupts their registrations because we shift ALL IDs > BUY, including theirs.

### Current Code (lines 56-85)
```lua
-- Insert FINANCE_LAND and LEASE_LAND right after BUY
-- We need to shift all actions with ID > BUY up by 2 to make room
local buyId = InGameMenuMapFrame.ACTIONS.BUY
local financeId = buyId + 1
local leaseId = buyId + 2

-- Collect all actions that need to be shifted (ID > buyId)
local actionsToShift = {}
for actionName, actionId in pairs(InGameMenuMapFrame.ACTIONS) do
    if type(actionId) == "number" and actionId > buyId then
        table.insert(actionsToShift, {name = actionName, oldId = actionId})
    end
end

-- Sort by ID descending so we shift highest first (avoid collisions)
table.sort(actionsToShift, function(a, b) return a.oldId > b.oldId end)

-- Shift each action's ID up by 2
for _, action in ipairs(actionsToShift) do
    local newId = action.oldId + 2
    InGameMenuMapFrame.ACTIONS[action.name] = newId

    -- Also move the contextAction entry
    if self.contextActions[action.oldId] then
        self.contextActions[newId] = self.contextActions[action.oldId]
        self.contextActions[action.oldId] = nil
    end

    UsedPlus.logDebug("Shifted action " .. action.name .. " from ID " .. action.oldId .. " to " .. newId)
end
```

### Fix
**Option A (Recommended): Guard the shifting with a module-level flag**

Add a module-level tracking variable and wrap the shifting code:

```lua
-- At top of file (after InGameMenuMapFrameExtension = {}):
InGameMenuMapFrameExtension.actionsShifted = false
```

Then in `onLoadMapFinished`, wrap the shifting block:

```lua
-- Only shift IDs once (critical: prevents double-shift corrupting action table)
if not InGameMenuMapFrameExtension.actionsShifted then
    InGameMenuMapFrameExtension.actionsShifted = true

    -- Insert FINANCE_LAND and LEASE_LAND right after BUY
    local buyId = InGameMenuMapFrame.ACTIONS.BUY
    local financeId = buyId + 1
    local leaseId = buyId + 2

    -- Collect all actions that need to be shifted (ID > buyId)
    local actionsToShift = {}
    for actionName, actionId in pairs(InGameMenuMapFrame.ACTIONS) do
        if type(actionId) == "number" and actionId > buyId then
            table.insert(actionsToShift, {name = actionName, oldId = actionId})
        end
    end

    -- Sort by ID descending so we shift highest first (avoid collisions)
    table.sort(actionsToShift, function(a, b) return a.oldId > b.oldId end)

    -- Shift each action's ID up by 2
    for _, action in ipairs(actionsToShift) do
        local newId = action.oldId + 2
        InGameMenuMapFrame.ACTIONS[action.name] = newId

        -- Also move the contextAction entry
        if self.contextActions[action.oldId] then
            self.contextActions[newId] = self.contextActions[action.oldId]
            self.contextActions[action.oldId] = nil
        end

        UsedPlus.logDebug("Shifted action " .. action.name .. " from ID " .. action.oldId .. " to " .. newId)
    end
else
    UsedPlus.logDebug("Action IDs already shifted - skipping (re-entrancy guard)")
end
```

**Important:** The existing individual registration guards (`if ACTIONS.FINANCE_LAND == nil`) should remain as-is — they're a second layer of defense. However, FINANCE_LAND and LEASE_LAND also need to read their IDs from `InGameMenuMapFrame.ACTIONS.BUY` consistently, not from the local variables computed inside the shift block. Since the guard wraps the block where `financeId`/`leaseId` are computed, adjust the registration to reference `ACTIONS.BUY + 1` and `ACTIONS.BUY + 2` directly:

```lua
-- Register FINANCE_LAND (uses BUY+1 whether we just shifted or previously shifted)
local financeId = InGameMenuMapFrame.ACTIONS.BUY + 1
if InGameMenuMapFrame.ACTIONS.FINANCE_LAND == nil then
    InGameMenuMapFrame.ACTIONS["FINANCE_LAND"] = financeId
    -- ... registration code ...
end

local leaseId = InGameMenuMapFrame.ACTIONS.BUY + 2
if InGameMenuMapFrame.ACTIONS.LEASE_LAND == nil then
    InGameMenuMapFrame.ACTIONS["LEASE_LAND"] = leaseId
    -- ... registration code ...
end
```

### Also: Guard the BUY Callback Override (lines 48-53)

The BUY callback override stores `originalBuyCallback` every call. If called twice, it stores **our own callback** as the "original", creating infinite recursion:

```lua
-- Current (line 51):
InGameMenuMapFrameExtension.originalBuyCallback = self.contextActions[InGameMenuMapFrame.ACTIONS.BUY].callback
```

**Fix:** Add a guard:
```lua
if InGameMenuMapFrameExtension.originalBuyCallback == nil then
    InGameMenuMapFrameExtension.originalBuyCallback = self.contextActions[InGameMenuMapFrame.ACTIONS.BUY].callback
    self.contextActions[InGameMenuMapFrame.ACTIONS.BUY].callback = InGameMenuMapFrameExtension.onBuyFarmland
end
```

### Verification
- Test entering the map screen, clicking farmland, and verifying Finance Land / Lease Land / Buy all appear
- Test with a map reload (if possible) to confirm no double-shift
- Verify no `mouseEvent` errors in log after fix
- Test that the action IDs in the log match expected values

---

## Fix 3: Add pcall Protection to Global Dialog Wrappers

### File
`src/extensions/VehicleSellingPointExtension.lua`

### Problem
The `g_gui.showDialog` wrapper (line 539) intercepts **every dialog open in the entire game**. If our interception logic throws an error for an unexpected dialog type, the dialog silently fails to open. The shop customization screen uses dialogs internally — if our wrapper errors on one of those, the shop "does nothing."

Currently, there's some error handling inside the wrapper, but not a comprehensive pcall around the entire interception logic with fallback to the original function.

### Current Flow (simplified, lines 539-940)
```lua
g_gui.showDialog = function(guiSelf, name, ...)
    UsedPlus.logDebug("=== showDialog called: name='" .. tostring(name) .. "' ===")

    if VehicleSellingPointExtension.DEBUG_PASSTHROUGH_ALL then
        return VehicleSellingPointExtension.originalShowDialog(guiSelf, name, ...)
    end

    -- ~400 lines of interception logic for SellItemDialog
    -- If any of this errors, the dialog call is lost

    -- Eventually calls originalShowDialog for non-intercepted dialogs
    return VehicleSellingPointExtension.originalShowDialog(guiSelf, name, ...)
end
```

### Fix
Wrap the entire interception logic in a pcall, with fallback to the original function on any error:

```lua
g_gui.showDialog = function(guiSelf, name, ...)
    UsedPlus.logDebug(string.format("=== showDialog called: name='%s' ===", tostring(name)))

    if VehicleSellingPointExtension.DEBUG_PASSTHROUGH_ALL then
        return VehicleSellingPointExtension.originalShowDialog(guiSelf, name, ...)
    end

    -- Protect all interception logic - if anything fails, fall through to original
    local args = {...}
    local success, result = pcall(function()
        -- [existing interception logic here - only for "SellItemDialog"]
        -- ... (existing code unchanged) ...
    end)

    if not success then
        UsedPlus.logError("showDialog wrapper error: " .. tostring(result) .. " — passing through to original")
        return VehicleSellingPointExtension.originalShowDialog(guiSelf, name, unpack(args))
    end

    -- If interception didn't handle it, pass through
    if result == nil then
        return VehicleSellingPointExtension.originalShowDialog(guiSelf, name, unpack(args))
    end

    return result
end
```

**Apply the same pattern to `showYesNoDialog` wrapper** (lines 333-465):

```lua
g_gui.showYesNoDialog = function(guiSelf, args)
    if VehicleSellingPointExtension.bypassInterception then
        VehicleSellingPointExtension.bypassInterception = false
        return VehicleSellingPointExtension.originalShowYesNoDialog(guiSelf, args)
    end

    local success, result = pcall(function()
        -- [existing interception logic]
    end)

    if not success then
        UsedPlus.logError("showYesNoDialog wrapper error: " .. tostring(result) .. " — passing through to original")
        return VehicleSellingPointExtension.originalShowYesNoDialog(guiSelf, args)
    end

    return result
end
```

### Key Principle
**If our wrapper fails for ANY reason, the original game function MUST still be called.** The user should never experience "nothing happens" because our interception logic errored.

### Verification
- Test selling a vehicle (our interception should still work)
- Test repair/repaint confirmation dialogs
- Test opening shop, browsing items, entering customization screen
- Test buying a vehicle via cash, finance, and lease
- Intentionally trigger an error in the wrapper (temporarily) to verify fallback works
- Check log for any "wrapper error" messages

---

## Fix 4: Reset `actionsShifted` Flag on Mission Delete

### File
`src/extensions/InGameMenuMapFrameExtension.lua`

### Problem
If the player exits to main menu and loads a new save, `InGameMenuMapFrameExtension.actionsShifted` would still be `true` from the previous session, preventing action registration in the new session. The class-level `InGameMenuMapFrame.ACTIONS` table gets reset by the game on new mission load, but our flag wouldn't.

### Fix
Add a cleanup function and hook it to mission delete:

```lua
function InGameMenuMapFrameExtension.onMissionDelete()
    InGameMenuMapFrameExtension.actionsShifted = false
    InGameMenuMapFrameExtension.originalBuyCallback = nil
    UsedPlus.logDebug("InGameMenuMapFrameExtension: Reset state for new mission")
end
```

Then in `src/main.lua`, wherever `Mission00.delete` is hooked (search for `Mission00.delete`), add:

```lua
InGameMenuMapFrameExtension.onMissionDelete()
```

### Verification
- Start a game, verify map actions work
- Exit to main menu, load a different save
- Verify map actions still work in the new session

---

## Testing Checklist

After implementing all fixes:

1. [ ] **Shop browsing** — Browse vehicles, click to enter customization screen (the reported issue)
2. [ ] **Shop purchase (cash)** — Buy a vehicle with cash
3. [ ] **Shop purchase (finance)** — Buy a vehicle with financing
4. [ ] **Shop purchase (lease)** — Buy a vehicle with leasing
5. [ ] **Map farmland** — Click farmland, verify Buy/Finance Land/Lease Land all appear
6. [ ] **Sell vehicle** — From workshop, sell a vehicle (our dialog interception)
7. [ ] **Repair vehicle** — From map, repair a vehicle
8. [ ] **No mouseEvent errors** — Check log for `mouseEvent` errors
9. [ ] **No wrapper errors** — Check log for "wrapper error" messages
10. [ ] **Session reload** — Exit to menu, load new save, repeat tests 1-8
11. [ ] **Log review** — Verify no new warnings or errors from our code

---

## Files Modified

| File | Changes |
|------|---------|
| `src/extensions/VehicleSellingPointExtension.lua` | Fix 1 (guard), Fix 3 (pcall wrappers) |
| `src/extensions/InGameMenuMapFrameExtension.lua` | Fix 2 (shift guard + callback guard), Fix 4 (reset flag) |
| `src/main.lua` | Fix 4 (call reset on mission delete) |
