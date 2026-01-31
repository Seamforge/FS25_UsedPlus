--[[
    PurchaseContext - Centralized state container for UnifiedPurchaseDialog

    Purpose: Single source of truth for all purchase-related state.
    Holds mode, item data, finance/lease parameters, credit info, trade-in data,
    and calculated values. Modules operate on this context.

    Pattern: Context Object - stateless modules read/write this shared state
]]

PurchaseContext = {}
local PurchaseContext_mt = Class(PurchaseContext)

--[[
    Constructor - Initialize with default state
]]
function PurchaseContext.new()
    local self = setmetatable({}, PurchaseContext_mt)

    -- Will be populated in next step

    return self
end

--[[
    Reset transient state between dialog opens
]]
function PurchaseContext:reset()
    -- Will be implemented in next step
end

--[[
    Validate state integrity
    @return isValid, errorMessage
]]
function PurchaseContext:validate()
    -- Will be implemented in next step
    return true, nil
end
