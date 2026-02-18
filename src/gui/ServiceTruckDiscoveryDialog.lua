--[[
    FS25_UsedPlus - Service Truck Discovery Dialog

    Shown when the player discovers the Service Truck opportunity through
    National Agent transactions. Displays the agent's message about a
    retiring mechanic selling his custom service truck at a discount.

    Features:
    - Agent narrative message (builds immersion)
    - Service Truck details and $67,500 discounted price
    - Prominent "CASH ONLY" warning
    - Two buttons: "Buy Now" and "Not Now"
    - Cash validation with helpful error message
    - "Not Now" saves opportunity to Finance Manager

    v2.9.0 - Service Truck System
]]

ServiceTruckDiscoveryDialog = {}
local ServiceTruckDiscoveryDialog_mt = Class(ServiceTruckDiscoveryDialog, MessageDialog)

-- Registration pattern
ServiceTruckDiscoveryDialog.instance = nil
ServiceTruckDiscoveryDialog.xmlPath = nil

--[[
    Register the dialog with g_gui (called from DialogLoader.registerAll)
]]
function ServiceTruckDiscoveryDialog.register()
    if ServiceTruckDiscoveryDialog.instance == nil then
        UsedPlus.logInfo("ServiceTruckDiscoveryDialog: Registering dialog")

        if ServiceTruckDiscoveryDialog.xmlPath == nil then
            ServiceTruckDiscoveryDialog.xmlPath = UsedPlus.MOD_DIR .. "gui/ServiceTruckDiscoveryDialog.xml"
        end

        ServiceTruckDiscoveryDialog.instance = ServiceTruckDiscoveryDialog.new()
        g_gui:loadGui(ServiceTruckDiscoveryDialog.xmlPath, "ServiceTruckDiscoveryDialog", ServiceTruckDiscoveryDialog.instance)

        UsedPlus.logInfo("ServiceTruckDiscoveryDialog: Registration complete")
    end
end

--[[
    Constructor
]]
function ServiceTruckDiscoveryDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or ServiceTruckDiscoveryDialog_mt)

    self.price = 67500  -- Default discounted price
    self.basePrice = 75000
    self.discountPercent = 10

    return self
end

--[[
    Called when dialog is created - binds XML element IDs
]]
function ServiceTruckDiscoveryDialog:onCreate()
    ServiceTruckDiscoveryDialog:superClass().onCreate(self)

    -- v2.14.2: Set header icon dynamically (ZIP-safe pattern)
    local headerIcon = self.dialogElement:getDescendantById("headerIcon")
    if headerIcon ~= nil then
        headerIcon:setImageFilename(UsedPlus.MOD_DIR .. "gui/icons/service_truck.png")
    end
end

--[[
    Called when dialog opens
]]
function ServiceTruckDiscoveryDialog:onOpen()
    ServiceTruckDiscoveryDialog:superClass().onOpen(self)

    UsedPlus.logDebug("ServiceTruckDiscoveryDialog:onOpen - price=$%d", self.price)

    self:updateDisplay()
end

--[[
    Set discovery data for the dialog
    @param price - The discounted price for the service truck
]]
function ServiceTruckDiscoveryDialog:setDiscoveryData(price)
    self.price = price or ServiceTruckDiscovery.DISCOUNTED_PRICE or 67500
    self.basePrice = ServiceTruckDiscovery.BASE_PRICE or 75000
    self.discountPercent = ServiceTruckDiscovery.DISCOUNT_PERCENT and
        math.floor(ServiceTruckDiscovery.DISCOUNT_PERCENT * 100) or 10

    UsedPlus.logDebug("ServiceTruckDiscoveryDialog:setDiscoveryData - price=$%d, base=$%d, discount=%d%%",
        self.price, self.basePrice, self.discountPercent)
end

--[[
    Update all display elements
    Uses translation keys from translation_en.xml
]]
function ServiceTruckDiscoveryDialog:updateDisplay()
    -- Update title (uses existing key)
    if self.titleText then
        self.titleText:setText(g_i18n:getText("usedplus_serviceTruck_discoveryTitle"))
    end

    -- Update subtitle (uses existing key)
    if self.subtitleText then
        self.subtitleText:setText(g_i18n:getText("usedplus_serviceTruck_discoverySubtitle"))
    end

    -- Update agent message/mechanic quote (uses existing key)
    if self.agentMessageText then
        local message = g_i18n:getText("usedplus_serviceTruck_mechanicQuote")
        self.agentMessageText:setText(message)
    end

    -- Update truck name (uses existing key)
    if self.truckNameText then
        local truckName = g_i18n:getText("usedplus_serviceTruck_vehicleName")
        self.truckNameText:setText(truckName)
    end

    -- Update truck features
    if self.feature1Text then
        self.feature1Text:setText(g_i18n:getText("usedplus_serviceTruck_feature1"))
    end
    if self.feature2Text then
        self.feature2Text:setText(g_i18n:getText("usedplus_serviceTruck_feature2"))
    end
    if self.feature3Text then
        self.feature3Text:setText(g_i18n:getText("usedplus_serviceTruck_feature3"))
    end

    -- Update pricing - base price with strikethrough styling (uses existing key)
    if self.basePriceText then
        self.basePriceText:setText(g_i18n:getText("usedplus_serviceTruck_originalPrice"))
    end

    -- "YOUR PRICE" label (uses existing key)
    if self.yourPriceLabel then
        self.yourPriceLabel:setText(g_i18n:getText("usedplus_serviceTruck_yourPrice"))
    end

    -- Final discounted price - large and prominent
    if self.finalPriceText then
        self.finalPriceText:setText(g_i18n:formatMoney(self.price, 0, true, true))
    end

    -- Update CASH ONLY warning (uses existing key) - prominently styled
    if self.cashOnlyText then
        self.cashOnlyText:setText(g_i18n:getText("usedplus_serviceTruck_cashOnly"))
        self.cashOnlyText:setTextColor(1.0, 0.3, 0.3, 1)  -- Red for emphasis
    end

    -- Update player's current cash display
    if self.currentCashText then
        local farmId = g_currentMission:getFarmId()
        local farm = g_farmManager:getFarmById(farmId)
        local currentCash = farm and farm.money or 0
        self.currentCashText:setText(string.format("Your Cash: %s", g_i18n:formatMoney(currentCash, 0, true, true)))

        -- Color based on affordability
        if currentCash >= self.price then
            self.currentCashText:setTextColor(0.3, 0.9, 0.3, 1)  -- Green - can afford
        else
            self.currentCashText:setTextColor(1.0, 0.5, 0.3, 1)  -- Orange - insufficient
        end
    end

    -- Update expiry information (uses existing key)
    if self.expiryText then
        local farmId = g_currentMission:getFarmId()
        local remainingDays = ServiceTruckDiscovery.getOpportunityRemainingDays(farmId)
        if remainingDays > 0 then
            local expiryStr = string.format(
                g_i18n:getText("usedplus_serviceTruck_expiryNote"),
                remainingDays
            )
            self.expiryText:setText(expiryStr)
        else
            self.expiryText:setText("")
        end
    end
end

--[[
    "Buy Now" button clicked
    Validates cash and executes purchase
]]
function ServiceTruckDiscoveryDialog:onClickBuyNow()
    local farmId = g_currentMission:getFarmId()
    local farm = g_farmManager:getFarmById(farmId)

    if not farm then
        UsedPlus.logError("ServiceTruckDiscoveryDialog: Could not find farm for farmId %d", farmId)
        self:close()
        return
    end

    local currentCash = farm.money or 0

    -- Check if player has enough cash
    if currentCash < self.price then
        local shortfall = self.price - currentCash
        local errorMsg = string.format(
            g_i18n:getText("usedplus_serviceTruck_insufficientFunds") or
            "Insufficient funds! You need %s more cash.",
            g_i18n:formatMoney(shortfall, 0, true, true)
        )

        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_ERROR,
            errorMsg
        )

        UsedPlus.logDebug("ServiceTruckDiscoveryDialog: Insufficient funds - need $%d more", shortfall)
        return  -- Don't close dialog - let them see the price again
    end

    -- Close dialog before executing purchase (prevents UI issues)
    self:close()

    -- Execute purchase through ServiceTruckDiscovery
    local success, reason, extra = ServiceTruckDiscovery.acceptOpportunity(farmId)

    if not success then
        local errorMsg = "Purchase failed"
        if reason == "insufficient_funds" then
            errorMsg = string.format("Insufficient funds! You have %s", g_i18n:formatMoney(extra or 0, 0, true, true))
        elseif reason == "spawn_failed" then
            errorMsg = "Failed to deliver the truck. Contact support."
        elseif reason == "no_opportunity" then
            errorMsg = "This opportunity has expired."
        end

        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_ERROR,
            errorMsg
        )

        UsedPlus.logWarning("ServiceTruckDiscoveryDialog: Purchase failed - %s", reason)
    else
        UsedPlus.logInfo("ServiceTruckDiscoveryDialog: Purchase successful!")
        -- Success notification is shown by ServiceTruckDiscovery.acceptOpportunity
    end
end

--[[
    "Not Now" button clicked
    Saves opportunity to Finance Manager for later
]]
function ServiceTruckDiscoveryDialog:onClickNotNow()
    local farmId = g_currentMission:getFarmId()

    -- Record the decline (keeps opportunity active)
    ServiceTruckDiscovery.declineOpportunity(farmId)

    -- Close dialog
    self:close()

    -- Show helpful reminder (uses existing translation key)
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_INFO,
        g_i18n:getText("usedplus_serviceTruck_opportunitySaved")
    )

    UsedPlus.logDebug("ServiceTruckDiscoveryDialog: Opportunity declined - saved for later")
end

--[[
    Back button / ESC key handler
]]
function ServiceTruckDiscoveryDialog:onClickBack()
    -- Treat back as "Not Now"
    self:onClickNotNow()
    return true
end

--[[
    Close the dialog properly
]]
function ServiceTruckDiscoveryDialog:close()
    g_gui:closeDialogByName("ServiceTruckDiscoveryDialog")
end

--[[
    Called when dialog closes
]]
function ServiceTruckDiscoveryDialog:onClose()
    ServiceTruckDiscoveryDialog:superClass().onClose(self)
end

--[[
    Static convenience method to show dialog with data
    @param price - The discounted price (optional, defaults to ServiceTruckDiscovery constant)
]]
function ServiceTruckDiscoveryDialog.showWithPrice(price)
    -- Ensure dialog is registered
    ServiceTruckDiscoveryDialog.register()

    -- Get dialog instance
    local guiDialog = g_gui.guis["ServiceTruckDiscoveryDialog"]
    if guiDialog and guiDialog.target then
        guiDialog.target:setDiscoveryData(price)
    end

    -- Show dialog
    g_gui:showDialog("ServiceTruckDiscoveryDialog")

    UsedPlus.logDebug("ServiceTruckDiscoveryDialog.showWithPrice: Showing dialog with price $%d", price or 67500)
end

UsedPlus.logInfo("ServiceTruckDiscoveryDialog class loaded")
