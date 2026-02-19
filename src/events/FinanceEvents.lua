--[[
    FS25_UsedPlus - Finance Events (Consolidated)

    Network events for financing operations:
    - FinanceVehicleEvent: Finance a vehicle/land/placeable
    - FinancePaymentEvent: Make additional payment on a deal
    - TakeLoanEvent: Take out a general cash loan

    Pattern from: EnhancedLoanSystem, HirePurchasing network events
]]

--============================================================================
-- FINANCE VEHICLE EVENT
-- Network event for financing a vehicle/land
--============================================================================

FinanceVehicleEvent = {}
local FinanceVehicleEvent_mt = Class(FinanceVehicleEvent, Event)

InitEventClass(FinanceVehicleEvent, "FinanceVehicleEvent")

function FinanceVehicleEvent.emptyNew()
    local self = Event.new(FinanceVehicleEvent_mt)
    return self
end

function FinanceVehicleEvent.new(farmId, itemType, itemId, itemName, basePrice, downPayment, termYears, cashBack, configurations, configurationData, licensePlateData)
    local self = FinanceVehicleEvent.emptyNew()
    self.farmId = farmId
    self.itemType = itemType
    self.itemId = itemId
    self.itemName = itemName
    self.basePrice = basePrice
    self.downPayment = downPayment
    self.termYears = termYears
    self.cashBack = cashBack or 0
    self.configurations = configurations or {}
    -- v2.13.2: Custom color RGB data + license plate (Issue #6)
    self.configurationData = configurationData
    self.licensePlateData = licensePlateData
    return self
end

function FinanceVehicleEvent.sendToServer(farmId, itemType, itemId, itemName, basePrice, downPayment, termYears, cashBack, configurations, configurationData, licensePlateData)
    if g_server ~= nil then
        -- Single-player: pass configurationData directly (no serialization needed)
        FinanceVehicleEvent.execute(farmId, itemType, itemId, itemName, basePrice, downPayment, termYears, cashBack, configurations, configurationData, licensePlateData)
    else
        g_client:getServerConnection():sendEvent(
            FinanceVehicleEvent.new(farmId, itemType, itemId, itemName, basePrice, downPayment, termYears, cashBack, configurations, configurationData, licensePlateData)
        )
    end
end

function FinanceVehicleEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObjectId(streamId, self.farmId)
    streamWriteString(streamId, self.itemType)

    if self.itemType == "land" then
        streamWriteInt32(streamId, self.itemId)
    else
        streamWriteString(streamId, tostring(self.itemId))
    end

    streamWriteString(streamId, self.itemName)
    streamWriteFloat32(streamId, self.basePrice)
    streamWriteFloat32(streamId, self.downPayment)
    streamWriteInt32(streamId, self.termYears)
    streamWriteFloat32(streamId, self.cashBack)

    local configCount = 0
    for _ in pairs(self.configurations) do
        configCount = configCount + 1
    end

    streamWriteInt32(streamId, configCount)
    for configKey, configValue in pairs(self.configurations) do
        streamWriteString(streamId, tostring(configKey))
        streamWriteInt32(streamId, configValue)
    end

    -- v2.13.2: Serialize configurationData (custom color RGB values) for multiplayer (Issue #6)
    -- Format: count, then for each entry: key(string), hasColor(bool), r/g/b/a(float32), material(int32)
    local configDataCount = 0
    if self.configurationData then
        for _ in pairs(self.configurationData) do
            configDataCount = configDataCount + 1
        end
    end
    streamWriteInt32(streamId, configDataCount)

    if self.configurationData then
        for cdKey, cdValue in pairs(self.configurationData) do
            streamWriteString(streamId, tostring(cdKey))

            -- Color data: {color = {r, g, b, a}, material = n}
            local hasColor = (type(cdValue) == "table" and cdValue.color ~= nil)
            streamWriteBool(streamId, hasColor)

            if hasColor then
                local c = cdValue.color
                streamWriteFloat32(streamId, c[1] or 0)
                streamWriteFloat32(streamId, c[2] or 0)
                streamWriteFloat32(streamId, c[3] or 0)
                streamWriteFloat32(streamId, c[4] or 1)
                streamWriteInt32(streamId, cdValue.material or 1)
            end
        end
    end

    -- v2.13.2: Serialize licensePlateData
    local hasLicensePlate = (self.licensePlateData ~= nil)
    streamWriteBool(streamId, hasLicensePlate)
    if hasLicensePlate then
        streamWriteString(streamId, self.licensePlateData.characters or "")
        streamWriteInt32(streamId, self.licensePlateData.colorIndex or 1)
        streamWriteInt32(streamId, self.licensePlateData.variation or 1)
        streamWriteInt32(streamId, self.licensePlateData.placementIndex or 1)
    end
end

function FinanceVehicleEvent:readStream(streamId, connection)
    self.farmId = NetworkUtil.readNodeObjectId(streamId)
    self.itemType = streamReadString(streamId)

    if self.itemType == "land" then
        self.itemId = streamReadInt32(streamId)
    else
        self.itemId = streamReadString(streamId)
    end

    self.itemName = streamReadString(streamId)
    self.basePrice = streamReadFloat32(streamId)
    self.downPayment = streamReadFloat32(streamId)
    self.termYears = streamReadInt32(streamId)
    self.cashBack = streamReadFloat32(streamId)

    self.configurations = {}
    local configCount = streamReadInt32(streamId)

    -- v2.7.2 SECURITY: Prevent unbounded loop DoS attack
    -- CRITICAL: We must ALWAYS consume the stream data, even if count is invalid
    -- Otherwise the stream pointer gets out of sync and causes packet corruption
    local MAX_CONFIGS = 100
    local isValidCount = (configCount >= 0 and configCount <= MAX_CONFIGS)
    if not isValidCount then
        UsedPlus.logWarn(string.format("[SECURITY] Invalid configCount rejected: %d (max %d) - draining stream", configCount, MAX_CONFIGS))
    end

    -- Always read the exact number of items declared in the stream
    -- Only store them if the count was valid
    local safeCount = math.max(0, math.min(configCount, MAX_CONFIGS * 2))  -- Cap at 2x max to prevent extreme DoS
    for i = 1, safeCount do
        local configKey = streamReadString(streamId)
        local configValue = streamReadInt32(streamId)
        -- v2.7.2 SECURITY: Only store if count was valid and key is safe
        if isValidCount and configKey and not configKey:match("^__") and configKey ~= "" then
            self.configurations[configKey] = configValue
        end
    end

    -- v2.13.2: Deserialize configurationData (custom color RGB values) (Issue #6)
    self.configurationData = nil
    local configDataCount = streamReadInt32(streamId)
    local safeDataCount = math.max(0, math.min(configDataCount, MAX_CONFIGS))

    if safeDataCount > 0 then
        self.configurationData = {}
        for i = 1, safeDataCount do
            local cdKey = streamReadString(streamId)
            local hasColor = streamReadBool(streamId)

            if hasColor then
                local r = streamReadFloat32(streamId)
                local g = streamReadFloat32(streamId)
                local b = streamReadFloat32(streamId)
                local a = streamReadFloat32(streamId)
                local material = streamReadInt32(streamId)

                if cdKey and cdKey ~= "" then
                    self.configurationData[cdKey] = {
                        color = {r, g, b, a},
                        material = material
                    }
                end
            else
                -- Non-color configurationData entry — skip (read key but store nothing)
                if cdKey and cdKey ~= "" then
                    self.configurationData[cdKey] = {}
                end
            end
        end
    end

    -- v2.13.2: Deserialize licensePlateData
    self.licensePlateData = nil
    local hasLicensePlate = streamReadBool(streamId)
    if hasLicensePlate then
        self.licensePlateData = {
            characters = streamReadString(streamId),
            colorIndex = streamReadInt32(streamId),
            variation = streamReadInt32(streamId),
            placementIndex = streamReadInt32(streamId),
        }
    end

    self:run(connection)
end

function FinanceVehicleEvent.execute(farmId, itemType, itemId, itemName, basePrice, downPayment, termYears, cashBack, configurations, configurationData, licensePlateData)
    -- v2.6.2: Validate finance system is enabled
    if UsedPlusSettings and UsedPlusSettings:get("enableFinanceSystem") == false then
        UsedPlus.logWarn("FinanceVehicleEvent rejected: Finance system disabled in settings")
        return false, "usedplus_mp_error_disabled"
    end

    if g_financeManager == nil then
        UsedPlus.logError("FinanceManager not initialized")
        return false, "usedplus_mp_error_manager"
    end

    -- v2.7.2 SECURITY: Validate all financial parameters
    -- Check for NaN, Infinity, and invalid values
    -- Note: value ~= value catches NaN, math.abs check catches infinity
    local function isInvalidNumber(v)
        return v == nil or v ~= v or v == math.huge or v == -math.huge
    end

    if isInvalidNumber(basePrice) or basePrice <= 0 or basePrice > 100000000 then
        UsedPlus.logError(string.format("[SECURITY] Invalid basePrice: %s", tostring(basePrice)))
        return false, "usedplus_mp_error_invalid_params"
    end
    if isInvalidNumber(downPayment) or downPayment < 0 or downPayment > basePrice then
        UsedPlus.logError(string.format("[SECURITY] Invalid downPayment: %s", tostring(downPayment)))
        return false, "usedplus_mp_error_invalid_params"
    end
    if termYears == nil or termYears < 1 or termYears > 30 then
        UsedPlus.logError(string.format("[SECURITY] Invalid termYears: %s (must be 1-30)", tostring(termYears)))
        return false, "usedplus_mp_error_invalid_params"
    end
    if isInvalidNumber(cashBack) or cashBack < 0 then
        UsedPlus.logError(string.format("[SECURITY] Invalid cashBack: %s", tostring(cashBack)))
        return false, "usedplus_mp_error_invalid_params"
    end

    -- v2.7.2 SECURITY: Validate cashBack doesn't exceed maximum allowed
    -- v2.9.1: Fixed - use CreditScore.calculate() not nonexistent getScore()
    local creditScore = CreditScore.calculate(farmId)
    local maxCashBack = 0
    if CreditScore.getMaxCashBack then
        maxCashBack = CreditScore.getMaxCashBack(basePrice, downPayment, creditScore)
    end
    if cashBack > maxCashBack then
        UsedPlus.logError(string.format("[SECURITY] CashBack $%.0f exceeds maximum allowed $%.0f", cashBack, maxCashBack))
        return false, "usedplus_mp_error_invalid_params"
    end

    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then
        UsedPlus.logError(string.format("Farm %d not found", farmId))
        return false, "usedplus_mp_error_invalid_params"
    end

    local netCost = downPayment - cashBack
    if farm.money < netCost then
        UsedPlus.logError(string.format("Insufficient funds for down payment ($%.2f required, $%.2f available)",
            netCost, farm.money))
        return false, "usedplus_mp_error_insufficient_funds"
    end

    local deal = g_financeManager:createFinanceDeal(
        farmId, itemType, itemId, itemName, basePrice, downPayment, termYears, cashBack, configurations or {},
        configurationData, licensePlateData
    )

    if deal then
        UsedPlus.logDebug(string.format("Finance deal created successfully: %s (ID: %s)", itemName, deal.id))
        return true, "usedplus_mp_success_financed"
    else
        UsedPlus.logError(string.format("Failed to create finance deal for %s", itemName))
        return false, "usedplus_mp_error_failed"
    end
end

function FinanceVehicleEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- v2.7.2: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, self.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("FINANCE_REJECTED",
            string.format("Unauthorized finance attempt for farmId %d: %s", self.farmId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    -- v2.8.0: Capture result and send response to client
    local success, msgKey = FinanceVehicleEvent.execute(
        self.farmId, self.itemType, self.itemId, self.itemName,
        self.basePrice, self.downPayment, self.termYears, self.cashBack, self.configurations,
        self.configurationData, self.licensePlateData
    )
    TransactionResponseEvent.sendToClient(connection, self.farmId, success, msgKey)

    -- v2.15.0: Broadcast deal sync to all clients
    if success then
        SyncFinanceDealsEvent.broadcastAddForFarm(self.farmId)
    end
end

--============================================================================
-- FINANCE PAYMENT EVENT
-- Network event for making additional payment on finance/lease deal
--============================================================================

FinancePaymentEvent = {}
local FinancePaymentEvent_mt = Class(FinancePaymentEvent, Event)

InitEventClass(FinancePaymentEvent, "FinancePaymentEvent")

function FinancePaymentEvent.emptyNew()
    local self = Event.new(FinancePaymentEvent_mt)
    return self
end

function FinancePaymentEvent.new(dealId, paymentAmount, farmId)
    local self = FinancePaymentEvent.emptyNew()
    self.dealId = dealId
    self.paymentAmount = paymentAmount
    self.farmId = farmId
    return self
end

function FinancePaymentEvent:sendToServer(dealId, paymentAmount, farmId)
    if g_server ~= nil then
        self:run(nil)  -- v2.9.1: Server doesn't need connection
    else
        g_client:getServerConnection():sendEvent(
            FinancePaymentEvent.new(dealId, paymentAmount, farmId)
        )
    end
end

function FinancePaymentEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.dealId)
    streamWriteFloat32(streamId, self.paymentAmount)
    NetworkUtil.writeNodeObjectId(streamId, self.farmId)
end

function FinancePaymentEvent:readStream(streamId, connection)
    self.dealId = streamReadString(streamId)
    self.paymentAmount = streamReadFloat32(streamId)
    self.farmId = NetworkUtil.readNodeObjectId(streamId)
    self:run(connection)
end

function FinancePaymentEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- v2.7.2: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, self.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("PAYMENT_REJECTED",
            string.format("Unauthorized payment attempt for farmId %d: %s", self.farmId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    if g_financeManager == nil then
        UsedPlus.logError("FinanceManager not initialized")
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_manager")
        return
    end

    local deal = g_financeManager:getDealById(self.dealId)
    if deal == nil then
        UsedPlus.logError(string.format("Deal %s not found", self.dealId))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_deal_not_found")
        return
    end

    if deal.farmId ~= self.farmId then
        UsedPlus.logError(string.format("Farm %d does not own deal %s", self.farmId, self.dealId))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    local farm = g_farmManager:getFarmById(self.farmId)
    if farm == nil then
        UsedPlus.logError(string.format("Farm %d not found", self.farmId))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_invalid_params")
        return
    end

    if farm.money < self.paymentAmount then
        UsedPlus.logError(string.format("Insufficient funds for payment ($%.2f required, $%.2f available)",
            self.paymentAmount, farm.money))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_insufficient_funds")
        return
    end

    if self.paymentAmount <= 0 then
        UsedPlus.logError(string.format("Invalid payment amount: $%.2f", self.paymentAmount))
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_invalid_params")
        return
    end

    local payoffAmount = deal.currentBalance

    if self.paymentAmount >= payoffAmount then
        -- Full payoff
        -- v2.9.1: Fix method name and handle deals without prepayment penalties (leases)
        local penalty = 0
        if deal.getPrepaymentPenalty then
            penalty = deal:getPrepaymentPenalty()
        end
        local totalCost = payoffAmount + penalty

        if farm.money < totalCost then
            UsedPlus.logError(string.format("Insufficient funds for payoff with penalty ($%.2f required)", totalCost))
            TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_insufficient_funds")
            return
        end

        g_currentMission:addMoneyChange(-totalCost, self.farmId, MoneyType.OTHER, true)

        deal.status = "completed"
        deal.currentBalance = 0

        g_financeManager.deals[deal.id] = nil
        local farmDeals = g_financeManager.dealsByFarm[deal.farmId]
        if farmDeals then
            for i, d in ipairs(farmDeals) do
                if d.id == deal.id then
                    table.remove(farmDeals, i)
                    break
                end
            end
        end

        UsedPlus.logDebug(string.format("Deal %s paid off: $%.2f (penalty: $%.2f)", deal.id, payoffAmount, penalty))

        -- v2.8.0: Send response to multiplayer client
        TransactionResponseEvent.sendToClient(connection, self.farmId, true, "usedplus_mp_success_payment")

        -- v2.15.0: Broadcast deal removal to all clients
        SyncFinanceDealsEvent.broadcastAddForFarm(self.farmId)

        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notification_dealPaidOff"), deal.itemName)
        )
    else
        -- Partial payment
        local interestPortion = (deal.interestRate / 12) * deal.currentBalance
        local principalPortion = self.paymentAmount - interestPortion

        g_currentMission:addMoneyChange(-self.paymentAmount, self.farmId, MoneyType.OTHER, true)

        deal.currentBalance = deal.currentBalance - principalPortion
        deal.totalInterestPaid = deal.totalInterestPaid + interestPortion

        UsedPlus.logDebug(string.format("Payment processed for %s: $%.2f (principal: $%.2f, interest: $%.2f)",
            deal.id, self.paymentAmount, principalPortion, interestPortion))

        -- v2.8.0: Send response to multiplayer client
        TransactionResponseEvent.sendToClient(connection, self.farmId, true, "usedplus_mp_success_payment")

        -- v2.15.0: Broadcast deal update to all clients
        SyncFinanceDealsEvent.broadcastUpdateDeal(self.farmId, self.dealId)

        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format(g_i18n:getText("usedplus_notification_paymentProcessed"), g_i18n:formatMoney(self.paymentAmount), deal.itemName)
        )
    end
end

--============================================================================
-- TAKE LOAN EVENT
-- Network event for taking out a general cash loan
--============================================================================

TakeLoanEvent = {}
local TakeLoanEvent_mt = Class(TakeLoanEvent, Event)

InitEventClass(TakeLoanEvent, "TakeLoanEvent")

function TakeLoanEvent.emptyNew()
    local self = Event.new(TakeLoanEvent_mt)
    return self
end

function TakeLoanEvent.new(farmId, loanAmount, termYears, interestRate, monthlyPayment, collateralItems)
    local self = TakeLoanEvent.emptyNew()
    self.farmId = farmId
    self.loanAmount = loanAmount
    self.termYears = termYears
    self.interestRate = interestRate
    self.monthlyPayment = monthlyPayment
    self.collateralItems = collateralItems or {}
    return self
end

function TakeLoanEvent.sendToServer(farmId, loanAmount, termYears, interestRate, monthlyPayment, collateralItems)
    if g_server ~= nil then
        TakeLoanEvent.execute(farmId, loanAmount, termYears, interestRate, monthlyPayment, collateralItems)
    else
        g_client:getServerConnection():sendEvent(
            TakeLoanEvent.new(farmId, loanAmount, termYears, interestRate, monthlyPayment, collateralItems)
        )
    end
end

function TakeLoanEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteFloat32(streamId, self.loanAmount)
    streamWriteInt32(streamId, self.termYears)
    streamWriteFloat32(streamId, self.interestRate)
    streamWriteFloat32(streamId, self.monthlyPayment)

    -- Serialize collateral items array
    local collateralCount = #self.collateralItems
    streamWriteInt32(streamId, collateralCount)

    for _, item in ipairs(self.collateralItems) do
        streamWriteString(streamId, item.vehicleId or "")
        streamWriteInt32(streamId, item.objectId or 0)
        streamWriteString(streamId, item.configFile or "")
        streamWriteString(streamId, item.name or "")
        streamWriteFloat32(streamId, item.value or 0)
    end
end

function TakeLoanEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.loanAmount = streamReadFloat32(streamId)
    self.termYears = streamReadInt32(streamId)
    self.interestRate = streamReadFloat32(streamId)
    self.monthlyPayment = streamReadFloat32(streamId)

    -- Deserialize collateral items array
    self.collateralItems = {}
    local collateralCount = streamReadInt32(streamId)

    -- v2.7.2 SECURITY: Prevent unbounded loop DoS and memory exhaustion
    -- CRITICAL: We must ALWAYS consume the stream data, even if count is invalid
    local MAX_COLLATERAL = 50
    local isValidCount = (collateralCount >= 0 and collateralCount <= MAX_COLLATERAL)
    if not isValidCount then
        UsedPlus.logWarn(string.format("[SECURITY] Invalid collateralCount rejected: %d (max %d) - draining stream", collateralCount, MAX_COLLATERAL))
    end

    -- Always read the exact number of items declared in the stream
    local safeCount = math.max(0, math.min(collateralCount, MAX_COLLATERAL * 2))
    for i = 1, safeCount do
        local item = {
            vehicleId = streamReadString(streamId),
            objectId = streamReadInt32(streamId),
            configFile = streamReadString(streamId),
            name = streamReadString(streamId),
            value = streamReadFloat32(streamId),
            farmId = self.farmId  -- Use event's farmId
        }
        -- v2.7.2 SECURITY: Only store if count was valid and value is reasonable
        if isValidCount and item.value and item.value > 0 and item.value < 100000000 then
            table.insert(self.collateralItems, item)
        end
    end

    self:run(connection)
end

function TakeLoanEvent.execute(farmId, loanAmount, termYears, interestRate, monthlyPayment, collateralItems)
    -- v2.6.2: Validate finance system is enabled (loans are part of finance)
    if UsedPlusSettings and UsedPlusSettings:get("enableFinanceSystem") == false then
        UsedPlus.logWarn("TakeLoanEvent rejected: Finance system disabled in settings")
        return false
    end

    collateralItems = collateralItems or {}

    UsedPlus.logDebug(string.format("TakeLoanEvent.execute: farmId=%d, amount=$%.0f, term=%d years, collateral=%d items",
        farmId, loanAmount, termYears, #collateralItems))

    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then
        UsedPlus.logError(string.format("TakeLoanEvent - Farm %d not found", farmId))
        return false
    end

    -- v2.7.2 SECURITY: Comprehensive loan parameter validation
    -- Helper to check for NaN and Infinity values
    local function isInvalidNumber(v)
        return v == nil or v ~= v or v == math.huge or v == -math.huge
    end

    if isInvalidNumber(loanAmount) or loanAmount <= 0 or loanAmount > 50000000 then
        UsedPlus.logError(string.format("[SECURITY] Invalid loan amount: %s", tostring(loanAmount)))
        return false
    end

    if termYears < 1 or termYears > 30 then
        UsedPlus.logError(string.format("[SECURITY] Invalid term: %d years (must be 1-30)", termYears))
        return false
    end

    -- v2.7.2 SECURITY: Validate interest rate is reasonable (0% to 50%)
    if isInvalidNumber(interestRate) or interestRate < 0 or interestRate > 0.50 then
        UsedPlus.logError(string.format("[SECURITY] Invalid interest rate: %s (must be 0-50%%)", tostring(interestRate)))
        return false
    end

    -- v2.7.2 SECURITY: Validate monthly payment is positive and bounded
    if isInvalidNumber(monthlyPayment) or monthlyPayment <= 0 or monthlyPayment > 10000000 then
        UsedPlus.logError(string.format("[SECURITY] Invalid monthly payment: %s", tostring(monthlyPayment)))
        return false
    end

    -- v2.7.2 SECURITY: Validate loan doesn't exceed collateral value (if collateral required)
    if collateralItems and #collateralItems > 0 then
        local collateralValue = 0
        for _, item in ipairs(collateralItems) do
            collateralValue = collateralValue + (item.value or 0)
        end
        if loanAmount > collateralValue * 1.5 then
            UsedPlus.logError(string.format("[SECURITY] Loan $%.0f exceeds 150%% of collateral value $%.0f", loanAmount, collateralValue))
            return false
        end
    end

    local timeComponent = 0
    if g_currentMission and g_currentMission.time then
        timeComponent = math.floor(g_currentMission.time)
    else
        timeComponent = math.random(100000, 999999)
    end
    local loanId = string.format("LOAN_%d_%d", farmId, timeComponent)

    if g_financeManager then
        local termMonths = termYears * 12
        local interestRatePercent = interestRate * 100

        local deal = FinanceDeal.new(
            farmId, "loan", loanId, "Cash Loan", loanAmount, 0,
            termMonths, interestRatePercent, 0
        )

        if deal then
            deal.monthlyPayment = monthlyPayment
            deal.currentBalance = loanAmount
            deal.amountFinanced = loanAmount

            -- Store collateral items for this loan
            deal.collateralItems = collateralItems
            if #collateralItems > 0 then
                local collateralValue = 0
                for _, item in ipairs(collateralItems) do
                    collateralValue = collateralValue + (item.value or 0)
                end
                UsedPlus.logDebug(string.format("Collateral pledged: %d vehicles worth $%d",
                    #collateralItems, collateralValue))
            end

            g_financeManager:registerDeal(deal)
            g_currentMission:addMoney(loanAmount, farmId, MoneyType.OTHER, true, true)

            -- Sync to vanilla farm.loan so it appears on vanilla Finances page
            -- Note: This may cause vanilla to charge additional interest, but ensures visibility
            farm.loan = (farm.loan or 0) + loanAmount
            UsedPlus.logDebug(string.format("Updated farm.loan to $%.0f (added $%.0f)", farm.loan, loanAmount))

            UsedPlus.logDebug(string.format("Loan created: $%d at %.2f%% for %d years (ID: %s)",
                loanAmount, interestRate * 100, termYears, deal.id))

            return true
        else
            UsedPlus.logError("Failed to create loan deal")
            return false
        end
    else
        UsedPlus.logError("FinanceManager not available")
        return false
    end
end

function TakeLoanEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- v2.7.2: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, self.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("LOAN_REJECTED",
            string.format("Unauthorized loan attempt for farmId %d ($%.0f): %s",
                self.farmId, self.loanAmount, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    -- v2.8.0: Capture result and send response to client
    local success = TakeLoanEvent.execute(self.farmId, self.loanAmount, self.termYears, self.interestRate, self.monthlyPayment, self.collateralItems)
    if success then
        TransactionResponseEvent.sendToClient(connection, self.farmId, true, "usedplus_mp_success_loan")

        -- v2.15.0: Broadcast deal sync to all clients
        SyncFinanceDealsEvent.broadcastAddForFarm(self.farmId)
    else
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_failed")
    end
end

--============================================================================
-- VANILLA LOAN PAYMENT EVENT
-- Network event for paying down vanilla farm.loan (Credit Line)
--============================================================================

VanillaLoanPaymentEvent = {}
local VanillaLoanPaymentEvent_mt = Class(VanillaLoanPaymentEvent, Event)

InitEventClass(VanillaLoanPaymentEvent, "VanillaLoanPaymentEvent")

function VanillaLoanPaymentEvent.emptyNew()
    local self = Event.new(VanillaLoanPaymentEvent_mt)
    return self
end

function VanillaLoanPaymentEvent.new(farmId, paymentAmount)
    local self = VanillaLoanPaymentEvent.emptyNew()
    self.farmId = farmId
    self.paymentAmount = paymentAmount
    return self
end

function VanillaLoanPaymentEvent.sendToServer(farmId, paymentAmount)
    if g_server ~= nil then
        -- Single-player or server: execute directly
        VanillaLoanPaymentEvent.execute(farmId, paymentAmount)
    else
        -- Multiplayer client: send to server
        g_client:getServerConnection():sendEvent(
            VanillaLoanPaymentEvent.new(farmId, paymentAmount)
        )
    end
end

function VanillaLoanPaymentEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteFloat32(streamId, self.paymentAmount)
end

function VanillaLoanPaymentEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.paymentAmount = streamReadFloat32(streamId)
    self:run(connection)
end

function VanillaLoanPaymentEvent.execute(farmId, paymentAmount)
    -- Get the farm
    local farm = g_farmManager:getFarmById(farmId)
    if not farm then
        UsedPlus.logError(string.format("VanillaLoanPaymentEvent - Farm %d not found", farmId))
        return false, "usedplus_mp_error_farm_not_found"
    end

    -- Validate loan exists
    local currentLoan = farm.loan or 0
    if currentLoan <= 0 then
        UsedPlus.logDebug("VanillaLoanPaymentEvent - No vanilla loan balance to pay")
        return false, "usedplus_mp_error_no_loan"
    end

    -- Validate payment amount
    if paymentAmount <= 0 then
        UsedPlus.logError(string.format("VanillaLoanPaymentEvent - Invalid payment amount: %.2f", paymentAmount))
        return false, "usedplus_mp_error_invalid_params"
    end

    -- Validate sufficient funds
    if farm.money < paymentAmount then
        UsedPlus.logError(string.format("VanillaLoanPaymentEvent - Insufficient funds: need $%.2f, have $%.2f",
            paymentAmount, farm.money))
        return false, "usedplus_mp_error_insufficient_funds"
    end

    -- Calculate actual payment (in case loan changed since client request)
    local actualPayment = math.min(paymentAmount, currentLoan)

    -- Process the payment
    g_currentMission:addMoney(-actualPayment, farmId, MoneyType.OTHER, true, true)
    farm.loan = currentLoan - actualPayment

    UsedPlus.logDebug(string.format("Vanilla loan payment: $%.0f, remaining balance: $%.0f", actualPayment, farm.loan))

    -- Show notification (this will only display on server/single-player)
    local paidStr = g_i18n:formatMoney(actualPayment, 0, true, true)
    if farm.loan <= 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format("Loan paid off! Total paid: %s", paidStr)
        )
    else
        local newBalanceStr = g_i18n:formatMoney(farm.loan, 0, true, true)
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format("Payment processed: %s. Remaining balance: %s", paidStr, newBalanceStr)
        )
    end

    return true, "usedplus_mp_success_payment"
end

function VanillaLoanPaymentEvent:run(connection)
    -- Only execute on server
    if connection ~= nil and connection:getIsServer() then
        return
    end

    -- v2.8.0: Validate farm ownership to prevent multiplayer exploits
    local isAuthorized, errorMsg = NetworkSecurity.validateFarmOwnership(connection, self.farmId)
    if not isAuthorized then
        NetworkSecurity.logSecurityEvent("VANILLA_LOAN_PAYMENT_REJECTED",
            string.format("Unauthorized vanilla loan payment attempt for farmId %d: %s",
                self.farmId, errorMsg or "unknown"),
            connection)
        TransactionResponseEvent.sendToClient(connection, self.farmId, false, "usedplus_mp_error_unauthorized")
        return
    end

    -- Execute the payment and send response to client
    local success, msgKey = VanillaLoanPaymentEvent.execute(self.farmId, self.paymentAmount)
    TransactionResponseEvent.sendToClient(connection, self.farmId, success, msgKey)
end

--============================================================================

UsedPlus.logInfo("FinanceEvents loaded (FinanceVehicleEvent, FinancePaymentEvent, TakeLoanEvent, VanillaLoanPaymentEvent)")
