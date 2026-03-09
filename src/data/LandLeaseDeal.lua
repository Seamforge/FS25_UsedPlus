--[[
    FS25_UsedPlus - Land Lease Deal Data Class

    LandLeaseDeal is a specialized deal for land leasing
    Pattern from: FinanceDeal and LeaseDeal
    Reference: FS25_ADVANCED_PATTERNS.md - Lease Management section

    Key differences from vehicle leases:
    - Land only (farmlandId instead of vehicleConfig)
    - Longer terms (1-10 years)
    - No damage/wear penalties
    - Buyout discount based on term progress
    - Expiration warnings (3mo, 1mo, 1wk before end)
    - Land reverts to NPC on expiration (no forced buyout)

    Monthly Payment Formula (simple, no residual):
    M = TotalCost / TermMonths
    Where TotalCost = LandValue * (1 + MarkupRate)
]]

LandLeaseDeal = {}
local LandLeaseDeal_mt = Class(LandLeaseDeal)

-- Land lease term configurations
LandLeaseDeal.TERMS = {
    {years = 1, markupRate = 0.20, buyoutDiscount = 0.00},  -- 20% markup, no buyout discount
    {years = 3, markupRate = 0.15, buyoutDiscount = 0.05},  -- 15% markup, 5% buyout discount
    {years = 5, markupRate = 0.10, buyoutDiscount = 0.10},  -- 10% markup, 10% buyout discount
    {years = 10, markupRate = 0.05, buyoutDiscount = 0.15}, -- 5% markup, 15% buyout discount
}

--[[
    Constructor for new land lease deal
    Creates lease with monthly payment calculation
]]
function LandLeaseDeal.new(farmId, farmlandId, landName, landPrice, termYears)
    local self = setmetatable({}, LandLeaseDeal_mt)

    -- Identity and classification (using DealUtils constants)
    self.dealType = DealUtils.TYPE.LAND_LEASE
    self.id = DealUtils.generateId(self.dealType, farmId)
    self.farmId = farmId

    -- Land information
    self.farmlandId = farmlandId  -- Farmland ID from farmland manager
    self.landName = landName      -- Display name (e.g., "Field 5")
    self.itemName = landName      -- Alias for UI compatibility

    -- Lease financial terms (v2.9.1: nil guards for savegame load)
    self.landPrice = landPrice or 0
    self.termYears = termYears or 1
    self.termMonths = (termYears or 1) * 12

    -- Get term configuration (use self.termYears which has nil guard)
    local termConfig = LandLeaseDeal.getTermConfig(self.termYears)
    self.markupRate = termConfig.markupRate
    self.buyoutDiscount = termConfig.buyoutDiscount

    -- Calculate total lease cost with markup (use self.landPrice which has nil guard)
    self.totalLeaseCost = self.landPrice * (1 + self.markupRate)
    self.monthlyPayment = self.totalLeaseCost / self.termMonths

    -- Calculate buyout price (land price minus discount for progress)
    self.baseBuyoutPrice = self.landPrice * (1 - self.buyoutDiscount)

    -- Payment tracking
    self.monthsPaid = 0
    self.totalPaid = 0
    self.status = "active"  -- active, completed, terminated, expired

    -- Tracking
    self.createdDate = g_currentMission.environment.currentDay
    self.missedPayments = 0

    -- Expiration warnings tracking
    self.warned3Months = false
    self.warned1Month = false
    self.warned1Week = false

    -- UI compatibility fields
    self.currentBalance = self:calculateRemainingCost()

    return self
end

--[[
    Get term configuration for a given year count
]]
function LandLeaseDeal.getTermConfig(termYears)
    for _, config in ipairs(LandLeaseDeal.TERMS) do
        if config.years == termYears then
            return config
        end
    end
    -- Default to 1-year terms if not found
    return LandLeaseDeal.TERMS[1]
end

--[[
    Calculate remaining lease cost for UI display
]]
function LandLeaseDeal:calculateRemainingCost()
    local remainingMonths = self.termMonths - self.monthsPaid
    return self.monthlyPayment * remainingMonths
end

--[[
    Calculate current buyout price
    Price decreases as more payments are made
    Formula: BaseBuyout - (BaseBuyout * ProgressPercent * 0.5)
    At 50% through term, buyout is 75% of base price
]]
function LandLeaseDeal:calculateBuyoutPrice()
    local progressPercent = self.monthsPaid / self.termMonths
    local progressDiscount = progressPercent * 0.5  -- Up to 50% off at end of term
    return self.baseBuyoutPrice * (1 - progressDiscount)
end

--[[
    Process monthly lease payment
    Returns: true if lease expired, false if still active
]]
function LandLeaseDeal:processMonthlyPayment()
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

    -- Update tracking
    self.monthsPaid = self.monthsPaid + 1
    self.totalPaid = self.totalPaid + self.monthlyPayment
    self.missedPayments = 0  -- Reset missed payment counter

    -- Record on-time payment to PaymentTracker (builds credit score!)
    if PaymentTracker then
        PaymentTracker.recordPayment(
            self.farmId,
            self.id or "unknown",
            PaymentTracker.STATUS_ON_TIME,
            self.monthlyPayment,
            "land_lease"
        )
    end

    -- Update remaining cost for UI
    self.currentBalance = self:calculateRemainingCost()

    -- Check for expiration warnings
    self:checkExpirationWarnings()

    -- Check if lease term complete
    if self.monthsPaid >= self.termMonths then
        self:expireLease()
        return true  -- Lease expired
    end

    return false  -- Still active
end

--[[
    Check and send expiration warnings
]]
function LandLeaseDeal:checkExpirationWarnings()
    local remainingMonths = self.termMonths - self.monthsPaid

    -- 3 months warning
    if remainingMonths <= 3 and not self.warned3Months then
        self.warned3Months = true
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format(g_i18n:getText("usedplus_notification_landLeaseExpires3Mo"),
                self.landName, g_i18n:formatMoney(self:calculateBuyoutPrice(), 0, true, true))
        )
    end

    -- 1 month warning
    if remainingMonths <= 1 and not self.warned1Month then
        self.warned1Month = true
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_notification_landLeaseExpires1Mo"),
                self.landName)
        )
    end

    -- 1 week warning (approximately - triggered at start of final month)
    if remainingMonths == 0 and not self.warned1Week then
        self.warned1Week = true
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_notification_landLeaseExpiresFinal"),
                self.landName)
        )
    end
end

--[[
    Handle missed payment
    Less strict than vehicle leases - just track and warn
]]
function LandLeaseDeal:handleMissedPayment()
    self.missedPayments = self.missedPayments + 1

    -- Record in credit history
    if CreditHistory then
        CreditHistory.recordEvent(self.farmId, "LAND_LEASE_MISSED_PAYMENT", self.landName)
    end

    if self.missedPayments == 1 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format(g_i18n:getText("usedplus_notification_missedLandLease1st"),
                self.landName)
        )
    elseif self.missedPayments == 2 then
        local warningMsg = string.format(g_i18n:getText("usedplus_notification_missedLandLeaseFinal"), self.landName)
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, warningMsg)

        -- Show popup dialog to ensure player sees this critical warning
        InfoDialog.show(warningMsg .. "\n\n" .. g_i18n:getText("usedplus_notification_missedLandLeaseEnsureFunds"))
    elseif self.missedPayments >= 3 then
        -- 3 missed payments = immediate expiration
        local remainingBalance = self:calculateRemainingCost() or 0
        self:expireLease()

        -- Show RepossessionDialog instead of just a banner
        if RepossessionDialog and RepossessionDialog.showLandSeizure then
            RepossessionDialog.showLandSeizure(
                self.landName .. " " .. g_i18n:getText("usedplus_label_landLease"),
                self.landPrice,
                self.missedPayments,
                remainingBalance
            )
        else
            -- Fallback to notification if dialog not available
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                string.format(g_i18n:getText("usedplus_notification_landLeaseTerminated"),
                    self.landName)
            )
        end
    end
end

--[[
    Expire the lease (term ended or forced due to non-payment)
    Reverts land ownership to NPC
]]
function LandLeaseDeal:expireLease()
    if not g_server then return end

    -- Revert land ownership to unowned (0 = NPC)
    g_farmlandManager:setLandOwnership(self.farmlandId, 0)

    -- Mark lease as expired
    self.status = "expired"

    -- Send notification
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_INFO,
        string.format(g_i18n:getText("usedplus_notification_landLeaseExpired"),
            self.landName)
    )

    -- Record in credit history (neutral if expired normally)
    if self.missedPayments < 3 and CreditHistory then
        CreditHistory.recordEvent(self.farmId, "LAND_LEASE_EXPIRED", self.landName)
    end

    UsedPlus.logDebug(string.format("Land lease expired: %s (farmlandId: %d)", self.landName, self.farmlandId))
end

--[[
    Terminate lease early (player-initiated)
    Returns land immediately, no penalty
]]
function LandLeaseDeal:terminateEarly()
    if not g_server then return end

    -- Revert land ownership
    g_farmlandManager:setLandOwnership(self.farmlandId, 0)

    -- Mark lease as terminated
    self.status = "terminated"

    -- Record in credit history (neutral)
    if CreditHistory then
        CreditHistory.recordEvent(self.farmId, "LAND_LEASE_TERMINATED", self.landName)
    end

    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format(g_i18n:getText("usedplus_notification_landLeaseReturnedToMarket"),
            self.landName)
    )

    UsedPlus.logDebug(string.format("Land lease terminated early: %s", self.landName))
end

--[[
    Save land lease to XML savegame
]]
function LandLeaseDeal:saveToXMLFile(xmlFile, key)
    xmlFile:setString(key .. "#id", self.id or "")
    xmlFile:setInt(key .. "#dealType", self.dealType)
    xmlFile:setInt(key .. "#farmId", self.farmId)
    xmlFile:setInt(key .. "#farmlandId", self.farmlandId)
    xmlFile:setString(key .. "#landName", self.landName or "")
    xmlFile:setFloat(key .. "#landPrice", self.landPrice)
    xmlFile:setInt(key .. "#termYears", self.termYears)
    xmlFile:setInt(key .. "#termMonths", self.termMonths)
    xmlFile:setFloat(key .. "#markupRate", self.markupRate)
    xmlFile:setFloat(key .. "#buyoutDiscount", self.buyoutDiscount)
    xmlFile:setFloat(key .. "#totalLeaseCost", self.totalLeaseCost)
    xmlFile:setFloat(key .. "#monthlyPayment", self.monthlyPayment)
    xmlFile:setFloat(key .. "#baseBuyoutPrice", self.baseBuyoutPrice)
    xmlFile:setInt(key .. "#monthsPaid", self.monthsPaid)
    xmlFile:setFloat(key .. "#totalPaid", self.totalPaid)
    xmlFile:setString(key .. "#status", self.status or "active")
    xmlFile:setInt(key .. "#createdDate", self.createdDate)
    xmlFile:setInt(key .. "#missedPayments", self.missedPayments)
    xmlFile:setBool(key .. "#warned3Months", self.warned3Months)
    xmlFile:setBool(key .. "#warned1Month", self.warned1Month)
    xmlFile:setBool(key .. "#warned1Week", self.warned1Week)
end

--[[
    Load land lease from XML savegame
    Returns true if successful, false if corrupt
]]
function LandLeaseDeal:loadFromXMLFile(xmlFile, key)
    self.id = xmlFile:getString(key .. "#id")

    -- Validate required fields
    if self.id == nil or self.id == "" then
        UsedPlus.logWarn("Corrupt land lease deal in savegame, skipping")
        return false
    end

    self.dealType = xmlFile:getInt(key .. "#dealType", 3)
    self.farmId = xmlFile:getInt(key .. "#farmId")
    self.farmlandId = xmlFile:getInt(key .. "#farmlandId")
    self.landName = xmlFile:getString(key .. "#landName")
    self.itemName = self.landName  -- UI compatibility
    self.landPrice = xmlFile:getFloat(key .. "#landPrice")
    self.termYears = xmlFile:getInt(key .. "#termYears")
    self.termMonths = xmlFile:getInt(key .. "#termMonths")
    self.markupRate = xmlFile:getFloat(key .. "#markupRate")
    self.buyoutDiscount = xmlFile:getFloat(key .. "#buyoutDiscount")
    self.totalLeaseCost = xmlFile:getFloat(key .. "#totalLeaseCost")
    self.monthlyPayment = xmlFile:getFloat(key .. "#monthlyPayment")
    self.baseBuyoutPrice = xmlFile:getFloat(key .. "#baseBuyoutPrice")
    self.monthsPaid = xmlFile:getInt(key .. "#monthsPaid")
    self.totalPaid = xmlFile:getFloat(key .. "#totalPaid")
    self.status = xmlFile:getString(key .. "#status", "active")
    self.createdDate = xmlFile:getInt(key .. "#createdDate")
    self.missedPayments = xmlFile:getInt(key .. "#missedPayments", 0)
    self.warned3Months = xmlFile:getBool(key .. "#warned3Months", false)
    self.warned1Month = xmlFile:getBool(key .. "#warned1Month", false)
    self.warned1Week = xmlFile:getBool(key .. "#warned1Week", false)

    -- Recalculate UI fields
    self.currentBalance = self:calculateRemainingCost()

    return true
end

--[[
    Serialize for network stream (multiplayer)
]]
function LandLeaseDeal:writeStream(streamId)
    streamWriteString(streamId, self.id or "")
    streamWriteInt32(streamId, self.dealType)
    streamWriteInt32(streamId, self.farmId)
    streamWriteInt32(streamId, self.farmlandId)
    streamWriteString(streamId, self.landName or "")
    streamWriteFloat32(streamId, self.landPrice)
    streamWriteInt32(streamId, self.termYears)
    streamWriteInt32(streamId, self.termMonths)
    streamWriteFloat32(streamId, self.markupRate)
    streamWriteFloat32(streamId, self.buyoutDiscount)
    streamWriteFloat32(streamId, self.totalLeaseCost)
    streamWriteFloat32(streamId, self.monthlyPayment)
    streamWriteFloat32(streamId, self.baseBuyoutPrice)
    streamWriteInt32(streamId, self.monthsPaid)
    streamWriteFloat32(streamId, self.totalPaid)
    streamWriteString(streamId, self.status or "active")
    streamWriteInt32(streamId, self.createdDate or 0)
    streamWriteInt32(streamId, self.missedPayments)
end

--[[
    Deserialize from network stream (multiplayer)
]]
function LandLeaseDeal:readStream(streamId)
    self.id = streamReadString(streamId)
    self.dealType = streamReadInt32(streamId)
    self.farmId = streamReadInt32(streamId)
    self.farmlandId = streamReadInt32(streamId)
    self.landName = streamReadString(streamId)
    self.itemName = self.landName
    self.landPrice = streamReadFloat32(streamId)
    self.termYears = streamReadInt32(streamId)
    self.termMonths = streamReadInt32(streamId)
    self.markupRate = streamReadFloat32(streamId)
    self.buyoutDiscount = streamReadFloat32(streamId)
    self.totalLeaseCost = streamReadFloat32(streamId)
    self.monthlyPayment = streamReadFloat32(streamId)
    self.baseBuyoutPrice = streamReadFloat32(streamId)
    self.monthsPaid = streamReadInt32(streamId)
    self.totalPaid = streamReadFloat32(streamId)
    self.status = streamReadString(streamId)
    self.createdDate = streamReadInt32(streamId)
    self.missedPayments = streamReadInt32(streamId)

    -- Recalculate derived fields
    self.currentBalance = self:calculateRemainingCost()
end

UsedPlus.logInfo("LandLeaseDeal class loaded")
