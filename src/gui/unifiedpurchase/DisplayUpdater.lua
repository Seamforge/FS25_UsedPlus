--[[
    DisplayUpdater - UI updates (read context → write GUI elements)

    Purpose: All display/UI update logic centralized here.
    Stateless functions that read from PurchaseContext and update GUI elements.

    Responsibilities:
    - Update section visibility (cash/finance/lease)
    - Update mode selector texts
    - Update cash display (price, trade-in, total)
    - Update finance display (down payment, monthly, total, APR)
    - Update lease display (monthly, total, term)
    - Update term/down payment option sliders
]]

DisplayUpdater = {}

--[[
    Update all display sections
    Master update function - calls all specific update methods
    @param context - PurchaseContext instance
    @param elements - Table of GUI element references
]]
function DisplayUpdater.updateAll(context, elements)
    -- Will be implemented in Step 6
end

--[[
    Update section visibility based on current mode
    @param context - PurchaseContext instance
    @param elements - Table of GUI element references
]]
function DisplayUpdater.updateSectionVisibility(context, elements)
    -- Will be implemented in Step 6
end

--[[
    Update mode selector button texts (availability indicators)
    @param context - PurchaseContext instance
    @param elements - Table of GUI element references
]]
function DisplayUpdater.updateModeSelector(context, elements)
    -- Will be implemented in Step 6
end

--[[
    Update cash purchase display section
    @param context - PurchaseContext instance
    @param elements - Table of GUI element references
]]
function DisplayUpdater.updateCashDisplay(context, elements)
    -- Will be implemented in Step 6
end

--[[
    Update finance purchase display section
    @param context - PurchaseContext instance
    @param elements - Table of GUI element references
]]
function DisplayUpdater.updateFinanceDisplay(context, elements)
    -- Will be implemented in Step 6
end

--[[
    Update lease purchase display section
    @param context - PurchaseContext instance
    @param elements - Table of GUI element references
]]
function DisplayUpdater.updateLeaseDisplay(context, elements)
    -- Will be implemented in Step 6
end

--[[
    Update term options slider based on credit
    @param context - PurchaseContext instance
    @param elements - Table of GUI element references
]]
function DisplayUpdater.updateTermOptions(context, elements)
    -- Will be implemented in Step 6
end

--[[
    Update down payment options slider based on credit
    @param context - PurchaseContext instance
    @param elements - Table of GUI element references
]]
function DisplayUpdater.updateDownPaymentOptions(context, elements)
    -- Will be implemented in Step 6
end
