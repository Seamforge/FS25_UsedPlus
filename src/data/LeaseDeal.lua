--[[
    FS25_UsedPlus - Lease Deal Data Class

    LeaseDeal is a specialized finance deal for leasing
    Pattern from: HirePurchasing "Balloon Payment Lease System"
    Reference: FS25_ADVANCED_PATTERNS.md - Lease/Rental patterns

    Key differences from FinanceDeal:
    - Vehicles only (not land or equipment)
    - Lower down payment max (20% vs 50%)
    - Residual value (balloon payment at end)
    - Vehicle must be returned at lease end
    - Cannot sell leased vehicle
    - Damage penalties on return
    - Early termination fee

    Lease Payment Formula:
    M = (P - FV/(1+r)^n) * [r(1+r)^n] / [(1+r)^n - 1]
    Where FV = Future Value (residual/balloon)
]]

LeaseDeal = {}
local LeaseDeal_mt = Class(LeaseDeal)

--[[
    Constructor for new lease deal
    Creates lease with balloon payment calculation
]]
function LeaseDeal.new(farmId, vehicleConfig, vehicleName, price, downPayment, termMonths, residualValue, interestRate)
    local self = setmetatable({}, LeaseDeal_mt)

    -- Identity and classification (using DealUtils constants)
    self.dealType = DealUtils.TYPE.LEASE
    self.id = DealUtils.generateId(self.dealType, farmId)
    self.farmId = farmId

    -- Vehicle information (leases are vehicles only)
    self.vehicleConfig = vehicleConfig  -- XML config filename
    self.vehicleName = vehicleName      -- Display name
    self.vehicleId = nil                -- Runtime vehicle ID
    self.objectId = nil                 -- Network object ID

    -- Lease financial terms (v2.9.1: nil guards for savegame load)
    self.baseCost = price or 0
    self.downPayment = downPayment or 0
    self.residualValue = residualValue or 0  -- Balloon payment at end

    self.termMonths = termMonths or 12
    self.monthsPaid = 0
    self.interestRate = (interestRate or 5) / 100  -- Convert percentage to decimal
    self.monthlyPayment = 0  -- Calculated below

    -- Vehicle condition tracking (for damage penalties)
    self.startDamage = 0    -- Paint damage at lease start
    self.startWear = 0      -- Wear at lease start

    -- Status tracking
    self.status = "active"  -- active, completed, terminated, defaulted
    self.createdDate = g_currentMission.environment.currentDay
    self.createdMonth = g_currentMission.environment.currentMonth
    self.createdYear = g_currentMission.environment.currentYear
    self.missedPayments = 0  -- Track consecutive missed payments

    -- UI compatibility fields (for FinanceManagerFrame)
    -- Leases don't have a traditional "balance" but we show remaining obligation
    self.totalInterestPaid = 0  -- Interest portion of payments made
    self.itemName = vehicleName  -- Alias for consistency with FinanceDeal

    -- Calculate monthly payment using balloon formula
    self:calculatePayment()

    -- Calculate "current balance" as remaining obligation for UI
    self.currentBalance = self:calculateRemainingObligation()

    return self
end

--[[
    Calculate remaining lease obligation for UI display
    Shows remaining payments + residual value (total you'd owe)
]]
function LeaseDeal:calculateRemainingObligation()
    local remainingMonths = self.termMonths - self.monthsPaid
    local remainingPayments = self.monthlyPayment * remainingMonths
    return remainingPayments + self.residualValue
end

--[[
    Calculate lease payment with residual value (balloon)
    Formula: M = (P - FV/(1+r)^n) * [r(1+r)^n] / [(1+r)^n - 1]
    This is different from standard amortization due to FV
]]
function LeaseDeal:calculatePayment()
    local P = self.baseCost - self.downPayment  -- Amount to finance
    local FV = self.residualValue                -- Future value (balloon)
    local r = self.interestRate / 12             -- Monthly rate
    local n = self.termMonths

    -- Handle zero interest edge case
    if r == 0 or r < 0.0001 then
        self.monthlyPayment = (P - FV) / n
    else
        -- Balloon payment formula (from HirePurchasing)
        local discountedFV = FV / math.pow(1 + r, n)
        local numerator = r * math.pow(1 + r, n)
        local denominator = math.pow(1 + r, n) - 1
        self.monthlyPayment = (P - discountedFV) * (numerator / denominator)
    end
end

--[[
    Process monthly lease payment
    Different from finance - no principal reduction concept
    At lease end, vehicle is removed (returned to dealer)
]]
function LeaseDeal:processMonthlyPayment()
    local farm = g_farmManager:getFarmById(self.farmId)

    -- Check if farm can afford payment
    if farm.money < self.monthlyPayment then
        self:handleMissedPayment()
        return false
    end

    -- Deduct payment (use changeBalance — the actual Farm money API)
    if g_server then
        farm:changeBalance(-self.monthlyPayment, MoneyType.LEASING_COSTS)
    end

    -- Increment months paid and reset missed counter
    self.monthsPaid = self.monthsPaid + 1
    self.missedPayments = 0

    -- Record on-time payment to PaymentTracker (builds credit score!)
    if PaymentTracker then
        PaymentTracker.recordPayment(
            self.farmId,
            self.id or "unknown",
            PaymentTracker.STATUS_ON_TIME,
            self.monthlyPayment,
            "lease"
        )
    end

    -- Update remaining obligation for UI
    self.currentBalance = self:calculateRemainingObligation()

    -- Check if lease term complete
    if self.monthsPaid >= self.termMonths then
        self:completeLease()
        return true  -- Lease completed
    end

    return false  -- Still active
end

--[[
    Handle missed lease payment
    3 strikes = vehicle repossession (consistent with finance deals)
]]
function LeaseDeal:handleMissedPayment()
    self.missedPayments = self.missedPayments + 1

    -- Record credit impact
    if CreditHistory then
        CreditHistory.recordEvent(self.farmId, "LEASE_PAYMENT_MISSED", self.itemName)
    end

    if self.missedPayments == 1 then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format(g_i18n:getText("usedplus_notification_missedLeasePayment1st"), self.itemName))
    elseif self.missedPayments == 2 then
        local warningMsg = string.format(g_i18n:getText("usedplus_notification_missedLeasePaymentFinal"), self.itemName)
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, warningMsg)

        -- Show popup dialog to ensure player sees this critical warning
        InfoDialog.show(warningMsg .. "\n\n" .. g_i18n:getText("usedplus_notification_missedLeasePaymentFinalPopup"))
    elseif self.missedPayments >= 3 then
        self:repossessVehicle()
    end
end

--[[
    Repossess leased vehicle after 3 missed payments
    Remove vehicle from world, mark deal as defaulted
]]
function LeaseDeal:repossessVehicle()
    if not g_server then return end

    -- Find and remove the vehicle (v2.15.4: Clear lease flags — Issue #34)
    local vehicle = self:findVehicle()
    if vehicle then
        UsedPlus.logDebug(string.format("Repossessing leased vehicle: %s (deal %s)", self.itemName, self.id))
        vehicle.isLeased = false
        vehicle.leaseDealId = nil
        g_currentMission:removeVehicle(vehicle)
    end

    -- Mark lease as defaulted (no refund of any payments)
    self.status = "defaulted"

    -- Record credit impact (severe)
    if CreditHistory then
        CreditHistory.recordEvent(self.farmId, "LEASED_VEHICLE_REPOSSESSED", self.itemName)
    end

    -- Calculate remaining lease obligation for display
    local remainingObligation = self:calculateRemainingObligation() or 0

    -- Show RepossessionDialog instead of just a banner
    if RepossessionDialog and RepossessionDialog.showVehicleRepossession then
        RepossessionDialog.showVehicleRepossession(
            self.itemName .. " (Leased)",  -- Mark as lease in name
            self.baseCost,                  -- Original vehicle value
            self.missedPayments,
            remainingObligation             -- Remaining lease obligation
        )
    else
        -- Fallback to notification if dialog not available
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_notification_leaseVehicleRepossessed"), self.itemName))
    end
end

--[[
    Complete lease at end of term
    v2.8.0: No longer shows dialog here - FinanceManager handles that with LeaseRenewalDialog
    which has all 3 options (Return, Buyout, Renew)

    This method is kept for potential direct calls but dialog is handled by FinanceManager
]]
function LeaseDeal:completeLease()
    if not g_server then return end

    -- v2.8.0: Dialog is now shown by FinanceManager:showLeaseRenewalDialog()
    -- which provides 3 options (Return, Buyout, Renew) instead of just 2
    -- Just log the completion here
    UsedPlus.logDebug(string.format("LeaseDeal:completeLease() called for %s - dialog handled by FinanceManager", self.itemName or "unknown"))
end

--[[
    Show the lease end dialog
    Refactored to use DialogLoader for centralized loading
]]
function LeaseDeal:showLeaseEndDialog(vehicle, penalty)
    -- Create callback for action handling
    local dealId = self.id
    local callback = function(action, amount)
        if action == "return" then
            LeaseEndEvent.sendToServer(dealId, LeaseEndEvent.ACTION_RETURN, amount)
        elseif action == "buyout" then
            LeaseEndEvent.sendToServer(dealId, LeaseEndEvent.ACTION_BUYOUT, amount)
        end
    end

    -- Use DialogLoader for centralized lazy loading
    DialogLoader.show("LeaseEndDialog", "setData", self, vehicle, callback)

    -- Send notification that lease has ended
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_INFO,
        string.format(g_i18n:getText("usedplus_notification_leaseEnded"), self.itemName)
    )
end

--[[
    Calculate damage penalty on lease return
    Allowed: 10% paint damage, 15% wear
    Penalty: 30% of base cost for excess damage/wear
]]
function LeaseDeal:calculateDamagePenalty(vehicle)
    -- Get current vehicle condition
    local currentDamage = 0
    local currentWear = 0

    if vehicle.spec_wearable then
        currentDamage = vehicle.spec_wearable.damage or 0
        currentWear = vehicle.spec_wearable.wear or 0
    end

    -- Calculate excess beyond allowed thresholds
    local allowedDamage = 0.10  -- 10% paint damage allowed
    local allowedWear = 0.15    -- 15% wear allowed

    local excessDamage = math.max(0, currentDamage - self.startDamage - allowedDamage)
    local excessWear = math.max(0, currentWear - self.startWear - allowedWear)

    -- Penalty is 30% of base cost per excess point
    local penalty = (excessDamage + excessWear) * self.baseCost * 0.30

    return math.floor(penalty)
end

--[[
    Terminate lease early (player-initiated)
    Charge termination fee (50% of remaining obligations)
    Remove vehicle, close lease
]]
function LeaseDeal:terminateEarly()
    if not g_server then return end

    -- Calculate early termination fee
    local terminationFee = self:calculateTerminationFee()

    -- Charge termination fee
    local farm = g_farmManager:getFarmById(self.farmId)
    if farm.money < terminationFee then
        -- Cannot afford termination
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_ERROR,
            g_i18n:getText("usedplus_error_cannotAffordTermination"))
        return false
    end

    -- Deduct fee (use changeBalance — the actual Farm money API)
    farm:changeBalance(-terminationFee, MoneyType.LEASING_COSTS)

    -- Find and remove vehicle (v2.15.4: Clear lease flags — Issue #34)
    local vehicle = self:findVehicle()
    if vehicle ~= nil then
        vehicle.isLeased = false
        vehicle.leaseDealId = nil
        g_currentMission:removeVehicle(vehicle)
    end

    -- Mark lease as terminated
    self.status = "terminated"

    -- Send notification
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format(g_i18n:getText("usedplus_notification_leaseTerminated"),
            self.vehicleName, g_i18n:formatMoney(terminationFee)))

    return true
end

--[[
    Calculate early termination fee
    Fee is 50% of (remaining payments + residual value)
]]
function LeaseDeal:calculateTerminationFee()
    local remainingMonths = self.termMonths - self.monthsPaid
    local remainingPayments = self.monthlyPayment * remainingMonths
    local remainingValue = remainingPayments + self.residualValue

    -- Fee is 50% of total remaining obligations
    local fee = remainingValue * 0.50

    return math.floor(fee)
end

--[[
    Find the leased vehicle in game world
    Uses objectId if available, otherwise searches by config
]]
function LeaseDeal:findVehicle()
    if self.objectId ~= nil then
        -- Find by network object ID (fastest, most reliable)
        return NetworkUtil.getObject(self.objectId)
    end

    -- Fallback: search all vehicles for matching config
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if vehicle.configFileName == self.vehicleConfig and
           vehicle.ownerFarmId == self.farmId then
            -- Found matching vehicle, cache objectId
            self.objectId = vehicle.id
            return vehicle
        end
    end

    return nil
end

--[[
    Save lease to XML savegame
    Similar to FinanceDeal but includes vehicle condition data
]]
function LeaseDeal:saveToXMLFile(xmlFile, key)
    xmlFile:setString(key .. "#id", self.id or "")
    xmlFile:setInt(key .. "#dealType", self.dealType)
    xmlFile:setInt(key .. "#farmId", self.farmId)
    xmlFile:setString(key .. "#vehicleConfig", self.vehicleConfig or "")
    xmlFile:setString(key .. "#vehicleName", self.vehicleName or "")
    xmlFile:setFloat(key .. "#baseCost", self.baseCost)
    xmlFile:setFloat(key .. "#downPayment", self.downPayment)
    xmlFile:setFloat(key .. "#residualValue", self.residualValue)
    xmlFile:setInt(key .. "#termMonths", self.termMonths)
    xmlFile:setInt(key .. "#monthsPaid", self.monthsPaid)
    xmlFile:setFloat(key .. "#interestRate", self.interestRate * 100)
    xmlFile:setFloat(key .. "#monthlyPayment", self.monthlyPayment)
    xmlFile:setFloat(key .. "#startDamage", self.startDamage)
    xmlFile:setFloat(key .. "#startWear", self.startWear)
    xmlFile:setString(key .. "#status", self.status or "active")
    xmlFile:setInt(key .. "#createdDate", self.createdDate)
    xmlFile:setInt(key .. "#createdMonth", self.createdMonth or 1)
    xmlFile:setInt(key .. "#createdYear", self.createdYear or 2025)
    xmlFile:setInt(key .. "#missedPayments", self.missedPayments or 0)

    if self.objectId ~= nil then
        xmlFile:setInt(key .. "#objectId", self.objectId)
    end
end

--[[
    Load lease from XML savegame
    Returns true if successful, false if corrupt
]]
function LeaseDeal:loadFromXMLFile(xmlFile, key)
    self.id = xmlFile:getString(key .. "#id")

    -- Validate required fields
    if self.id == nil or self.id == "" then
        UsedPlus.logWarn("Corrupt lease deal in savegame, skipping")
        return false
    end

    self.dealType = xmlFile:getInt(key .. "#dealType", 2)
    self.farmId = xmlFile:getInt(key .. "#farmId")
    self.vehicleConfig = xmlFile:getString(key .. "#vehicleConfig")
    self.vehicleName = xmlFile:getString(key .. "#vehicleName")
    self.baseCost = xmlFile:getFloat(key .. "#baseCost")
    self.downPayment = xmlFile:getFloat(key .. "#downPayment")
    self.residualValue = xmlFile:getFloat(key .. "#residualValue")
    self.termMonths = xmlFile:getInt(key .. "#termMonths")
    self.monthsPaid = xmlFile:getInt(key .. "#monthsPaid")
    self.interestRate = xmlFile:getFloat(key .. "#interestRate") / 100
    self.monthlyPayment = xmlFile:getFloat(key .. "#monthlyPayment")
    self.startDamage = xmlFile:getFloat(key .. "#startDamage", 0)
    self.startWear = xmlFile:getFloat(key .. "#startWear", 0)
    self.status = xmlFile:getString(key .. "#status", "active")
    self.createdDate = xmlFile:getInt(key .. "#createdDate")
    self.createdMonth = xmlFile:getInt(key .. "#createdMonth", 1)
    self.createdYear = xmlFile:getInt(key .. "#createdYear", 2025)
    self.missedPayments = xmlFile:getInt(key .. "#missedPayments", 0)
    self.objectId = xmlFile:getInt(key .. "#objectId")

    -- Set UI compatibility fields after loading
    self.itemName = self.vehicleName
    self.totalInterestPaid = 0  -- Will be recalculated if needed
    self.currentBalance = self:calculateRemainingObligation()

    return true
end

UsedPlus.logInfo("LeaseDeal class loaded")
