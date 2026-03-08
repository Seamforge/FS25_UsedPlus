--[[
    FS25_UsedPlus - Seller Response Dialog
    v2.6.0: Shows seller's response to player's negotiation offer

    Three response modes:
    - ACCEPT: Seller accepts player's offer
    - COUNTER: Seller makes a counter offer
    - REJECT: Seller rejects offer outright

    Stand Firm mechanic (on counter):
    - 30% chance seller accepts original offer
    - 50% chance seller holds at counter
    - 20% chance seller walks away (listing locked for 1 hour)
]]

SellerResponseDialog = {}
local SellerResponseDialog_mt = Class(SellerResponseDialog, ScreenElement)

-- Response types
SellerResponseDialog.RESPONSE_ACCEPT = "accept"
SellerResponseDialog.RESPONSE_COUNTER = "counter"
SellerResponseDialog.RESPONSE_REJECT = "reject"

-- Stand Firm outcomes
SellerResponseDialog.STAND_FIRM_ACCEPT = 0.30    -- 30% accept original
SellerResponseDialog.STAND_FIRM_HOLD = 0.50      -- 50% hold at counter
SellerResponseDialog.STAND_FIRM_WALKAWAY = 0.20  -- 20% walk away

--[[
    Constructor
]]
function SellerResponseDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or SellerResponseDialog_mt)

    self.listing = nil
    self.search = nil
    self.responseType = nil
    self.playerOffer = 0
    self.responseAmount = 0
    self.askingPrice = 0
    self.onCompleteCallback = nil
    self.callbackTarget = nil
    self.isClosing = false  -- Flag to prevent double-close issues
    self.purchaseCompleted = false  -- v2.9.1: Flag to track if purchase was completed

    -- v2.9.5: Icon directory for dynamic icons
    self.iconDir = UsedPlus.MOD_DIR .. "gui/icons/"

    return self
end

--[[
    Set dialog data (called via DialogLoader.show)
    @param listing - The vehicle listing
    @param search - The search this listing came from
    @param responseType - "accept", "counter", or "reject"
    @param playerOffer - Amount player offered
    @param responseAmount - Counter amount (for counter), or asking price (for reject)
    @param askingPrice - Original asking price
    @param onCompleteCallback - Called when negotiation completes
    @param callbackTarget - Callback target
]]
function SellerResponseDialog:setData(listing, search, responseType, playerOffer, responseAmount, askingPrice, onCompleteCallback, callbackTarget)
    self.listing = listing
    self.search = search
    self.responseType = responseType
    self.playerOffer = playerOffer
    self.responseAmount = responseAmount
    self.askingPrice = askingPrice
    self.onCompleteCallback = onCompleteCallback
    self.callbackTarget = callbackTarget
    self.purchaseCompleted = false  -- v2.9.1: Reset for new negotiation
    self.isClosing = false

    UsedPlus.logDebug(string.format("SellerResponseDialog:setData - type=%s, offer=$%d, response=$%d, asking=$%d",
        responseType, playerOffer or 0, responseAmount or 0, askingPrice or 0))
end

--[[
    Called when dialog opens
]]
function SellerResponseDialog:onOpen()
    SellerResponseDialog:superClass().onOpen(self)

    self:updateDisplay()
end

--[[
    Called when dialog closes
    v2.9.1: Apply cooldown on close if reject response wasn't handled
]]
function SellerResponseDialog:onClose()
    SellerResponseDialog:superClass().onClose(self)

    -- v2.9.1: If closing a REJECT response dialog without accepting,
    -- apply the cooldown (handles Esc key and other close paths)
    if self.responseType == SellerResponseDialog.RESPONSE_REJECT and self.listing and not self.purchaseCompleted then
        if not self.listing.negotiationLocked then
            self.listing.negotiationLocked = true
            local currentTime = 0
            if g_currentMission and g_currentMission.environment then
                currentTime = g_currentMission.environment.dayTime or 0
            end
            self.listing.negotiationLockExpires = currentTime + 1800000  -- 30 minutes in ms
            UsedPlus.logDebug("Dialog closed (Esc/other): Applied 30-minute cooldown for REJECT")
        end
    end

    -- Reset closing flag when dialog is fully closed
    self.isClosing = false
    self.purchaseCompleted = false
end

--[[
    Update display based on response type
]]
function SellerResponseDialog:updateDisplay()
    if self.responseType == SellerResponseDialog.RESPONSE_ACCEPT then
        self:displayAccept()
    elseif self.responseType == SellerResponseDialog.RESPONSE_COUNTER then
        self:displayCounter()
    else
        self:displayReject()
    end
end

--[[
    Display ACCEPT response
]]
function SellerResponseDialog:displayAccept()
    -- Title
    if self.titleText then
        self.titleText:setText(g_i18n:getText("usedplus_sr_titleAccept") or "OFFER ACCEPTED!")
        self.titleText:setTextColor(0.2, 0.8, 0.2, 1)
    end

    -- Background color (green tint)
    if self.responseBg then
        self.responseBg:setImageColor(nil, 0.06, 0.14, 0.08, 0.95)
    end

    -- Icon - v2.9.5: Use image icon instead of text
    if self.responseIconImage then
        self.responseIconImage:setImageFilename(self.iconDir .. "status_good.dds")
    end

    -- Response text
    local vehicleName = self.listing and self.listing.storeItemName or "vehicle"
    if self.responseText then
        local text = g_i18n:getText("usedplus_response_accepted") or "Deal! You've got yourself a %s."
        self.responseText:setText(string.format(text, vehicleName))
    end

    -- Price details
    if self.priceLabel1 then
        self.priceLabel1:setText(g_i18n:getText("usedplus_sr_yourOffer") or "Your Offer:")
    end
    if self.priceValue1 then
        self.priceValue1:setText(g_i18n:formatMoney(self.playerOffer, 0, true, true))
        self.priceValue1:setTextColor(0.2, 0.8, 0.2, 1)
    end

    -- Hide second price row
    if self.priceLabel2 then self.priceLabel2:setText("") end
    if self.priceValue2 then self.priceValue2:setText("") end

    -- Savings display
    local savings = self.askingPrice - self.playerOffer
    if self.savingsText then
        if savings > 0 then
            self.savingsText:setText(string.format(g_i18n:getText("usedplus_sr_youSaved"), g_i18n:formatMoney(savings, 0, true, true)))
        else
            self.savingsText:setText("")
        end
    end

    -- Buttons: [Complete Purchase] only - deal is done, no cancel option
    if self.primaryButton then
        self.primaryButton:setText(g_i18n:getText("usedplus_sr_completePurchase") or "Complete Purchase")
    end
    if self.separator1 then
        self.separator1:setVisible(false)
    end
    if self.secondaryButton then
        self.secondaryButton:setVisible(false)
    end
    if self.separator2 then
        self.separator2:setVisible(false)
    end
    if self.tertiaryButton then
        self.tertiaryButton:setVisible(false)
    end
end

--[[
    Display COUNTER response
]]
function SellerResponseDialog:displayCounter()
    -- Title
    if self.titleText then
        self.titleText:setText(g_i18n:getText("usedplus_sr_titleCounter") or "COUNTER OFFER")
        self.titleText:setTextColor(1, 0.6, 0.2, 1)
    end

    -- Background color (orange tint)
    if self.responseBg then
        self.responseBg:setImageColor(nil, 0.14, 0.10, 0.06, 0.95)
    end

    -- Icon - v2.9.5: Use image icon instead of text
    if self.responseIconImage then
        self.responseIconImage:setImageFilename(self.iconDir .. "handshake.dds")
    end

    -- Response text
    if self.responseText then
        local text = g_i18n:getText("usedplus_response_counter") or "I can't go that low, but I'll meet you partway. How about %s?"
        self.responseText:setText(string.format(text, g_i18n:formatMoney(self.responseAmount, 0, true, true)))
    end

    -- Price details
    local offerPercent = math.floor((self.playerOffer / self.askingPrice) * 100)
    local counterPercent = math.floor((self.responseAmount / self.askingPrice) * 100)

    if self.priceLabel1 then
        self.priceLabel1:setText(g_i18n:getText("usedplus_sr_yourOffer") or "Your Offer:")
    end
    if self.priceValue1 then
        self.priceValue1:setText(string.format("%s (%d%%)", g_i18n:formatMoney(self.playerOffer, 0, true, true), offerPercent))
    end

    if self.priceLabel2 then
        self.priceLabel2:setText(g_i18n:getText("usedplus_sr_counterOffer") or "Counter Offer:")
    end
    if self.priceValue2 then
        self.priceValue2:setText(string.format("%s (%d%%)", g_i18n:formatMoney(self.responseAmount, 0, true, true), counterPercent))
        self.priceValue2:setTextColor(1, 0.6, 0.2, 1)
    end

    -- Hide savings
    if self.savingsText then self.savingsText:setText("") end

    -- Buttons: [Accept Counter] [Stand Firm] [Walk Away]
    if self.primaryButton then
        self.primaryButton:setText(g_i18n:getText("usedplus_sr_acceptCounter") or "Accept Counter")
    end
    if self.separator1 then
        self.separator1:setVisible(true)
    end
    if self.secondaryButton then
        self.secondaryButton:setVisible(true)
        self.secondaryButton:setText(g_i18n:getText("usedplus_sr_standFirm") or "Stand Firm")
    end
    if self.separator2 then
        self.separator2:setVisible(true)
    end
    if self.tertiaryButton then
        self.tertiaryButton:setVisible(true)
        self.tertiaryButton:setText(g_i18n:getText("usedplus_sr_walkAway") or "Walk Away")
    end
end

--[[
    Display REJECT response
]]
function SellerResponseDialog:displayReject()
    -- Title
    if self.titleText then
        self.titleText:setText(g_i18n:getText("usedplus_sr_titleReject") or "OFFER REJECTED")
        self.titleText:setTextColor(0.9, 0.2, 0.2, 1)
    end

    -- Background color (red tint)
    if self.responseBg then
        self.responseBg:setImageColor(nil, 0.14, 0.06, 0.06, 0.95)
    end

    -- Icon - v2.9.5: Use image icon instead of text
    if self.responseIconImage then
        self.responseIconImage:setImageFilename(self.iconDir .. "status_bad.dds")
    end

    -- Response text
    if self.responseText then
        local text = g_i18n:getText("usedplus_response_rejected") or "Sorry, but I can't accept that. My price is firm at %s."
        self.responseText:setText(string.format(text, g_i18n:formatMoney(self.askingPrice, 0, true, true)))
    end

    -- Price details
    if self.priceLabel1 then
        self.priceLabel1:setText(g_i18n:getText("usedplus_sr_yourOffer") or "Your Offer:")
    end
    if self.priceValue1 then
        self.priceValue1:setText(g_i18n:formatMoney(self.playerOffer, 0, true, true))
    end

    if self.priceLabel2 then
        self.priceLabel2:setText(g_i18n:getText("usedplus_sr_sellerPrice") or "Seller's Price:")
    end
    if self.priceValue2 then
        self.priceValue2:setText(g_i18n:formatMoney(self.askingPrice, 0, true, true))
        self.priceValue2:setTextColor(0.9, 0.2, 0.2, 1)
    end

    -- Hide savings
    if self.savingsText then self.savingsText:setText("") end

    -- Buttons: [Pay Full Price] [Walk Away]
    if self.primaryButton then
        self.primaryButton:setText(g_i18n:getText("usedplus_sr_payFullPrice") or "Pay Full Price")
    end
    if self.separator1 then
        self.separator1:setVisible(true)
    end
    if self.secondaryButton then
        self.secondaryButton:setVisible(false)
    end
    if self.separator2 then
        self.separator2:setVisible(false)
    end
    if self.tertiaryButton then
        self.tertiaryButton:setVisible(true)
        self.tertiaryButton:setText(g_i18n:getText("usedplus_sr_walkAway") or "Walk Away")
    end
end

--[[
    Check if player can afford an amount (cash only)
    @param amount - The amount to check
    @return boolean, string - canAfford, errorMessage
]]
function SellerResponseDialog:canAffordAmount(amount)
    local farmId = g_currentMission and g_currentMission.player and g_currentMission.player.farmId or 1
    local farm = g_farmManager:getFarmById(farmId)

    if not farm then
        return false, "Could not find farm"
    end

    local currentMoney = farm.money or 0
    if currentMoney >= amount then
        return true, nil
    else
        local shortfall = amount - currentMoney
        return false, string.format("You need %s more to complete this purchase.\nCurrent balance: %s",
            g_i18n:formatMoney(shortfall, 0, true, true),
            g_i18n:formatMoney(currentMoney, 0, true, true))
    end
end

--[[
    Primary button click
    - Accept: Complete purchase at offered price
    - Counter: Accept counter offer
    - Reject: Pay full price
]]
function SellerResponseDialog:onClickPrimary()
    local finalPrice = self.playerOffer
    local farmId = g_currentMission and g_currentMission.player and g_currentMission.player.farmId or 1

    -- Determine what price we're paying
    if self.responseType == SellerResponseDialog.RESPONSE_COUNTER then
        finalPrice = self.responseAmount
    elseif self.responseType == SellerResponseDialog.RESPONSE_REJECT then
        finalPrice = self.askingPrice
    end

    -- Validate player can afford the final price (used vehicles are cash only!)
    local canAfford, errorMsg = self:canAffordAmount(finalPrice)
    if not canAfford then
        InfoDialog.show(errorMsg or "You cannot afford this purchase.")
        return
    end

    -- Now proceed with the purchase - reset finalPrice for tracking logic
    finalPrice = self.playerOffer

    if self.responseType == SellerResponseDialog.RESPONSE_COUNTER then
        finalPrice = self.responseAmount
        -- Track counter acceptance
        if FinanceManager and FinanceManager.getInstance then
            local fm = FinanceManager.getInstance()
            if fm then
                fm:incrementStatistic(farmId, "negotiationsCountered", 1)
            end
        end
    elseif self.responseType == SellerResponseDialog.RESPONSE_REJECT then
        finalPrice = self.askingPrice
        -- Track rejection -> full price
        if FinanceManager and FinanceManager.getInstance then
            local fm = FinanceManager.getInstance()
            if fm then
                fm:incrementStatistic(farmId, "negotiationsRejected", 1)
            end
        end
    else
        -- Accept - track savings
        if FinanceManager and FinanceManager.getInstance then
            local fm = FinanceManager.getInstance()
            if fm then
                fm:incrementStatistic(farmId, "negotiationsWon", 1)
                local savings = self.askingPrice - finalPrice
                fm:incrementStatistic(farmId, "totalNegotiationSavings", savings)
            end
        end
    end

    UsedPlus.logDebug(string.format("Negotiation complete: purchase at $%d (asked $%d)", finalPrice, self.askingPrice))

    -- Cache values before closing (dialog state may be cleared)
    local listing = self.listing
    local callback = self.onCompleteCallback
    local callbackTarget = self.callbackTarget
    local purchasePrice = finalPrice

    -- v2.9.1: Mark purchase as completed so onClose doesn't apply cooldown
    self.purchaseCompleted = true

    -- Close dialog first
    self:close()

    -- Defer the purchase callback to next frame to ensure dialog is fully closed
    -- This prevents dialog stacking issues when the callback shows notifications
    g_currentMission:addUpdateable({
        update = function(self, dt)
            g_currentMission:removeUpdateable(self)
            if callback and callbackTarget then
                callback(callbackTarget, listing, purchasePrice)
            elseif callback then
                callback(listing, purchasePrice)
            end
        end
    })
end

--[[
    Secondary button click (Stand Firm - counter mode only)
]]
function SellerResponseDialog:onClickSecondary()
    if self.responseType ~= SellerResponseDialog.RESPONSE_COUNTER then
        return
    end

    -- Roll for Stand Firm outcome
    math.random()  -- Dry run
    local roll = math.random()

    UsedPlus.logDebug(string.format("Stand Firm roll: %.2f", roll))

    if roll <= SellerResponseDialog.STAND_FIRM_ACCEPT then
        -- Seller caves! Accepts original offer
        self:handleStandFirmAccept()
    elseif roll <= (SellerResponseDialog.STAND_FIRM_ACCEPT + SellerResponseDialog.STAND_FIRM_HOLD) then
        -- Seller holds at counter
        self:handleStandFirmHold()
    else
        -- Seller walks away
        self:handleStandFirmWalkaway()
    end
end

--[[
    Handle Stand Firm -> Accept outcome
]]
function SellerResponseDialog:handleStandFirmAccept()
    UsedPlus.logDebug("Stand Firm: Seller accepted original offer!")

    -- Update display to acceptance mode
    self.responseType = SellerResponseDialog.RESPONSE_ACCEPT

    -- Update response text
    if self.responseText then
        local text = g_i18n:getText("usedplus_standfirm_success") or "Alright, alright... you drive a hard bargain. I'll take it."
        self.responseText:setText(text)
    end

    -- Track as won negotiation
    local farmId = g_currentMission and g_currentMission.player and g_currentMission.player.farmId or 1
    if FinanceManager and FinanceManager.getInstance then
        local fm = FinanceManager.getInstance()
        if fm then
            fm:incrementStatistic(farmId, "negotiationsWon", 1)
            local savings = self.askingPrice - self.playerOffer
            fm:incrementStatistic(farmId, "totalNegotiationSavings", savings)
        end
    end

    -- Update display
    self:displayAccept()
end

--[[
    Handle Stand Firm -> Hold outcome
]]
function SellerResponseDialog:handleStandFirmHold()
    UsedPlus.logDebug("Stand Firm: Seller holding at counter")

    -- Update response text
    if self.responseText then
        local text = g_i18n:getText("usedplus_standfirm_hold") or "Look, %s is as low as I can go. Take it or leave it."
        self.responseText:setText(string.format(text, g_i18n:formatMoney(self.responseAmount, 0, true, true)))
    end

    -- Hide Stand Firm button (can't try again)
    if self.secondaryButton then
        self.secondaryButton:setVisible(false)
    end
    if self.separator2 then
        self.separator2:setVisible(false)
    end
end

--[[
    Handle Stand Firm -> Walk Away outcome
]]
function SellerResponseDialog:handleStandFirmWalkaway()
    UsedPlus.logDebug("Stand Firm: Seller walked away!")

    -- Lock the listing for 1 hour
    if self.listing then
        self.listing.negotiationLocked = true
        -- Lock expires in 1 game hour (using mission time)
        local currentTime = 0
        if g_currentMission and g_currentMission.environment then
            currentTime = g_currentMission.environment.dayTime or 0
        end
        self.listing.negotiationLockExpires = currentTime + 3600000  -- 1 hour in ms
    end

    -- Show walkaway message
    self:close()

    -- Track rejection
    local farmId = g_currentMission and g_currentMission.player and g_currentMission.player.farmId or 1
    if FinanceManager and FinanceManager.getInstance then
        local fm = FinanceManager.getInstance()
        if fm then
            fm:incrementStatistic(farmId, "negotiationsRejected", 1)
        end
    end

    -- Show info dialog
    InfoDialog.show(g_i18n:getText("usedplus_standfirm_walkaway") or "I don't think we're going to agree. Maybe another time.")
end

--[[
    Tertiary button click (Walk Away / Cancel)
    v2.9.1: Now applies a cooldown when walking away from a reject response
]]
function SellerResponseDialog:onClickTertiary()
    UsedPlus.logDebug("Walk Away clicked - initiating deferred close")

    -- Prevent double-clicks
    if self.isClosing then
        UsedPlus.logDebug("Walk Away - already closing, ignoring")
        return
    end
    self.isClosing = true

    -- v2.9.1: Apply cooldown when walking away from REJECT response
    -- This prevents the exploit of immediately re-negotiating with a higher offer
    if self.responseType == SellerResponseDialog.RESPONSE_REJECT and self.listing then
        self.listing.negotiationLocked = true
        -- Lock for 30 minutes of game time (1800000 ms) - enough to discourage exploit
        local currentTime = 0
        if g_currentMission and g_currentMission.environment then
            currentTime = g_currentMission.environment.dayTime or 0
        end
        self.listing.negotiationLockExpires = currentTime + 1800000  -- 30 minutes in ms
        UsedPlus.logDebug("Walk Away from REJECT: Applied 30-minute cooldown to listing")
    end

    -- Use DEFERRED close (same pattern that fixed Complete Purchase)
    -- This ensures the dialog closes cleanly after the button event is fully processed
    g_currentMission:addUpdateable({
        update = function(updatable, dt)
            g_currentMission:removeUpdateable(updatable)

            UsedPlus.logDebug("Walk Away - executing deferred close")

            -- Try to close the dialog
            if g_gui then
                local currentDialog = g_gui.currentDialog
                if currentDialog then
                    UsedPlus.logDebug("Walk Away - closing currentDialog: " .. tostring(currentDialog.name or "unknown"))
                    g_gui:closeDialog(currentDialog)
                else
                    UsedPlus.logDebug("Walk Away - no currentDialog, trying changeScreen")
                    g_gui:changeScreen(nil)
                end
            end
        end
    })

    UsedPlus.logDebug("Negotiation cancelled by player")
end

--[[
    Complete the purchase at the negotiated price
]]
function SellerResponseDialog:completePurchase(finalPrice)
    if self.onCompleteCallback and self.callbackTarget then
        -- Call the original purchase callback with the negotiated price
        self.onCompleteCallback(self.callbackTarget, self.listing, finalPrice)
    elseif self.onCompleteCallback then
        self.onCompleteCallback(self.listing, finalPrice)
    end
end

--[[
    Close the dialog
]]
function SellerResponseDialog:close()
    UsedPlus.logDebug("SellerResponseDialog:close() called")
    -- Try to close via g_gui
    if g_gui then
        if g_gui.currentDialog == self then
            g_gui:closeDialog(self)
        else
            -- Dialog might not be the current dialog, try by name
            g_gui:closeDialogByName("SellerResponseDialog")
        end
    end
end

UsedPlus.logInfo("SellerResponseDialog loaded")
