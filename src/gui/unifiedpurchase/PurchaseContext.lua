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

    -- Mode constants (reference from dialog)
    self.MODE_CASH = 1
    self.MODE_FINANCE = 2
    self.MODE_LEASE = 3

    -- Current mode
    self.currentMode = self.MODE_CASH

    -- Trade-in state
    self.tradeInEnabled = false
    self.tradeInVehicle = nil
    self.tradeInValue = 0
    self.eligibleTradeIns = {}

    -- Item data
    self.itemType = "vehicle"  -- "vehicle" or "placeable"
    self.storeItem = nil
    self.vehiclePrice = 0
    self.vehicleName = ""
    self.vehicleCategory = ""
    self.isUsedVehicle = false
    self.usedCondition = 100
    self.saleItem = nil  -- For used vehicle purchases
    self.shopScreen = nil  -- Reference to shop screen for vanilla buy flow

    -- Finance parameters
    self.financeTermIndex = 5  -- Default 5 years
    self.financeDownIndex = 3  -- Default 10%
    self.financeCashBackIndex = 1  -- Default $0

    -- Lease parameters (LEASE_TERMS is in months: index 6 = 36 months = 3 years)
    self.leaseTermIndex = 6  -- Default 3 years (36 months) in {3,6,9,12,24,36,48,60}
    self.leaseDownIndex = 3  -- Default 10%

    -- Credit data
    self.creditScore = 650
    self.creditRating = "Fair"
    self.interestRate = 0.08
    self.canFinance = true
    self.financeMinScore = 550
    self.canLease = true
    self.leaseMinScore = 600

    -- Available options (filtered by credit, set by CreditCalculations)
    self.availableFinanceTerms = {}
    self.availableFinanceDownOptions = {}
    self.availableLeaseDownOptions = {}

    return self
end

--[[
    Reset transient state between dialog opens
    Call this when dialog is closed or needs fresh state
]]
function PurchaseContext:reset()
    self.currentMode = self.MODE_CASH
    self.tradeInEnabled = false
    self.tradeInVehicle = nil
    self.tradeInValue = 0
    self.eligibleTradeIns = {}

    self.itemType = "vehicle"
    self.storeItem = nil
    self.vehiclePrice = 0
    self.vehicleName = ""
    self.vehicleCategory = ""
    self.isUsedVehicle = false
    self.usedCondition = 100
    self.saleItem = nil
    self.shopScreen = nil

    -- Reset to defaults
    self.financeTermIndex = 5
    self.financeDownIndex = 3
    self.financeCashBackIndex = 1
    self.leaseTermIndex = 6
    self.leaseDownIndex = 3

    -- Keep credit data (persists across opens)
    -- Don't reset: creditScore, creditRating, interestRate, canFinance, canLease
end

--[[
    Validate state integrity
    @return isValid, errorMessage
]]
function PurchaseContext:validate()
    -- Check required fields
    if self.storeItem == nil then
        return false, "No store item set"
    end

    if self.vehiclePrice <= 0 then
        return false, "Invalid vehicle price"
    end

    -- Check mode-specific requirements
    if self.currentMode == self.MODE_FINANCE then
        if not self.canFinance then
            return false, string.format("Cannot finance (credit score %d, need %d)",
                self.creditScore, self.financeMinScore)
        end
    elseif self.currentMode == self.MODE_LEASE then
        if not self.canLease then
            return false, string.format("Cannot lease (credit score %d, need %d)",
                self.creditScore, self.leaseMinScore)
        end
        if self.itemType == "placeable" then
            return false, "Placeables cannot be leased"
        end
    end

    return true, nil
end
