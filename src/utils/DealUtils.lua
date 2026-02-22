--[[
    FS25_UsedPlus - Deal Utilities

    Shared utility functions for all Deal types
    Pattern: Utility module instead of abstract base class

    Provides:
    - Common ID generation
    - Standardized deal summary for UI
    - Type checking helpers
    - Progress calculation

    Deal Interface Contract:
    All Deal classes (FinanceDeal, LeaseDeal, LandLeaseDeal) must have:
    - id (string) - Unique identifier
    - dealType (number) - 1=finance, 2=lease, 3=land_lease
    - farmId (number) - Owning farm
    - itemName (string) - Display name
    - monthlyPayment (number) - Payment amount
    - monthsPaid (number) - Payments completed
    - status (string) - "active", "paid_off", "terminated", etc.
    - createdDate (number) - Game day created
    - currentBalance (number) - Remaining obligation
    - processMonthlyPayment() - Process payment, returns bool
    - saveToXMLFile(xmlFile, key) - Persistence
    - loadFromXMLFile(xmlFile, key) - Persistence, returns bool
]]

DealUtils = {}

-- Deal type constants (single source of truth)
DealUtils.TYPE = {
    FINANCE = 1,
    LEASE = 2,
    LAND_LEASE = 3,
}

DealUtils.TYPE_NAMES = {
    [1] = "Finance",
    [2] = "Lease",
    [3] = "Land Lease",
}

DealUtils.STATUS = {
    ACTIVE = "active",
    PAID_OFF = "paid_off",
    COMPLETED = "completed",
    TERMINATED = "terminated",
    EXPIRED = "expired",
    DEFAULTED = "defaulted",
}

--[[
    Generate unique deal ID
    Format: {type}_{farmId}_{timestamp}_{random}
]]
function DealUtils.generateId(dealType, farmId)
    local typePrefix = DealUtils.TYPE_NAMES[dealType] or "deal"
    typePrefix = typePrefix:lower():gsub(" ", "_")
    local timestamp = g_currentMission.environment.currentDay or 0
    local random = math.random(1000, 9999)
    -- v2.9.1: Guard against nil farmId during savegame load
    local safeFarmId = farmId or 0
    return string.format("%s_%d_%d_%d", typePrefix, safeFarmId, timestamp, random)
end

--[[
    Get standardized summary for UI display
    Works with any deal type
    @param deal - Any deal object (FinanceDeal, LeaseDeal, LandLeaseDeal)
    @return table with standardized fields for UI
]]
function DealUtils.getSummary(deal)
    if deal == nil then return nil end

    return {
        id = deal.id,
        type = deal.dealType,
        typeName = DealUtils.TYPE_NAMES[deal.dealType] or "Unknown",
        farmId = deal.farmId,
        itemName = deal.itemName or deal.vehicleName or deal.landName or "Unknown",
        monthlyPayment = deal.monthlyPayment or 0,
        monthsPaid = deal.monthsPaid or 0,
        totalMonths = deal.termMonths or 0,
        remainingMonths = (deal.termMonths or 0) - (deal.monthsPaid or 0),
        currentBalance = deal.currentBalance or 0,
        status = deal.status or "unknown",
        isActive = (deal.status == DealUtils.STATUS.ACTIVE),
        progress = DealUtils.calculateProgress(deal),
    }
end

--[[
    Calculate progress percentage (0-100)
]]
function DealUtils.calculateProgress(deal)
    if deal == nil or deal.termMonths == nil or deal.termMonths == 0 then
        return 0
    end
    local progress = ((deal.monthsPaid or 0) / deal.termMonths) * 100
    return math.min(100, math.max(0, progress))
end

--[[
    Check if deal is active
]]
function DealUtils.isActive(deal)
    return deal ~= nil and deal.status == DealUtils.STATUS.ACTIVE
end

--[[
    Check if deal is for a vehicle (finance or lease, not land)
]]
function DealUtils.isVehicleDeal(deal)
    if deal == nil then return false end
    if deal.dealType == DealUtils.TYPE.LEASE then return true end
    if deal.dealType == DealUtils.TYPE.FINANCE then
        return deal.itemType == "vehicle" or deal.itemType == "equipment"
    end
    return false
end

--[[
    Check if deal is for land
]]
function DealUtils.isLandDeal(deal)
    if deal == nil then return false end
    if deal.dealType == DealUtils.TYPE.LAND_LEASE then return true end
    if deal.dealType == DealUtils.TYPE.FINANCE then
        return deal.itemType == "land"
    end
    return false
end

--[[
    Get monthly payment for display (handles nil safely)
]]
function DealUtils.getMonthlyPayment(deal)
    if deal == nil then return 0 end
    -- For leases with configurable payments
    if deal.getConfiguredPayment then
        return deal:getConfiguredPayment()
    end
    return deal.monthlyPayment or 0
end

--[[
    Get status display text with color hint
    @return text, colorKey
]]
function DealUtils.getStatusDisplay(deal)
    if deal == nil then return "Unknown", "neutral" end

    local status = deal.status or "unknown"

    if status == DealUtils.STATUS.ACTIVE then
        return g_i18n:getText("usedplus_status_active"), "neutral"
    elseif status == DealUtils.STATUS.PAID_OFF then
        return g_i18n:getText("usedplus_status_paidOff"), "success"
    elseif status == DealUtils.STATUS.COMPLETED then
        return g_i18n:getText("usedplus_status_completed"), "success"
    elseif status == DealUtils.STATUS.TERMINATED then
        return g_i18n:getText("usedplus_status_terminated"), "warning"
    elseif status == DealUtils.STATUS.EXPIRED then
        return g_i18n:getText("usedplus_status_expired"), "warning"
    elseif status == DealUtils.STATUS.DEFAULTED then
        return g_i18n:getText("usedplus_status_defaulted"), "error"
    else
        return status, "neutral"
    end
end

--[[
    Calculate total remaining obligation
    Different calculation per deal type
]]
function DealUtils.getRemainingObligation(deal)
    if deal == nil then return 0 end

    if deal.dealType == DealUtils.TYPE.FINANCE then
        -- Finance: current balance + any accrued interest
        return (deal.currentBalance or 0) + (deal.accruedInterest or 0)

    elseif deal.dealType == DealUtils.TYPE.LEASE then
        -- Lease: remaining payments + residual value
        local remaining = (deal.termMonths or 0) - (deal.monthsPaid or 0)
        return (deal.monthlyPayment or 0) * remaining + (deal.residualValue or 0)

    elseif deal.dealType == DealUtils.TYPE.LAND_LEASE then
        -- Land lease: remaining payments
        local remaining = (deal.termMonths or 0) - (deal.monthsPaid or 0)
        return (deal.monthlyPayment or 0) * remaining
    end

    return deal.currentBalance or 0
end

--[[
    Validate deal has required fields
    @return isValid, missingFields
]]
function DealUtils.validate(deal)
    local required = {"id", "dealType", "farmId", "monthlyPayment", "status"}
    local missing = {}

    for _, field in ipairs(required) do
        if deal[field] == nil then
            table.insert(missing, field)
        end
    end

    return #missing == 0, missing
end

UsedPlus.logInfo("DealUtils utility loaded")
