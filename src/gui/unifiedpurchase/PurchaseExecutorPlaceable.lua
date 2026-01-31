--[[
    PurchaseExecutorPlaceable - Execute placeable purchases with temp money injection

    Purpose: Handle placeable purchase execution logic.
    Stateless functions that operate on PurchaseContext.

    CRITICAL: executeFinance() contains temp money injection flow for placeables.
    This is the most delicate code in the refactor - must preserve exactly.

    Responsibilities:
    - Execute cash placeable purchases
    - Execute finance placeable purchases (TEMP MONEY FLOW)
    - Execute lease placeable purchases
    - Coordinate with PlaceableSystemExtension for reconciliation
]]

PurchaseExecutorPlaceable = {}

--[[
    Execute cash placeable purchase
    @param context - PurchaseContext instance
    @param farmId - Farm ID
    @return success
]]
function PurchaseExecutorPlaceable.executeCash(context, farmId)
    -- Will be implemented in Step 8
    return false
end

--[[
    Execute finance placeable purchase with temp money injection

    CRITICAL FLOW:
    1. Inject temp money (financed amount)
    2. Create pendingPlaceableFinance state
    3. Close dialog
    4. Defer call to placeableData:buy() (triggers placement mode)
    5. PlaceableSystemExtension.onPlaceableFinalized() reconciles after placement

    @param context - PurchaseContext instance
    @param farmId - Farm ID
    @return success
]]
function PurchaseExecutorPlaceable.executeFinance(context, farmId)
    -- Will be implemented in Step 8 - PRESERVE EXACT LOGIC FROM LINES 2078-2363
    return false
end

--[[
    Execute lease placeable purchase
    Note: Placeables cannot be leased - this should never be called
    @param context - PurchaseContext instance
    @param farmId - Farm ID
    @return success (always false)
]]
function PurchaseExecutorPlaceable.executeLease(context, farmId)
    -- Placeables cannot be leased
    UsedPlus.logWarn("Attempted to lease placeable - not supported")
    return false
end
