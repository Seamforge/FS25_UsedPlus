--[[
    FS25_UsedPlus - Sales Panel Module

    v2.7.2 REFACTORED: Extracted from FinanceManagerFrame.lua

    Handles the Sale Listings section of the Finance Manager:
    - updateSaleListings: Display vehicle sale listings
    - onAcceptSaleClick: Accept a pending offer
    - onDeclineSaleClick: Decline a pending offer
    - onCancelSaleClick: Cancel an active listing
    - onInfoSaleClick: View listing details
    - onEditSaleClick: Edit asking price
]]

-- Ensure FinanceManagerFrame table exists
FinanceManagerFrame = FinanceManagerFrame or {}

--[[
    Update Sale Listings section
    Shows active vehicle sale listings with agent tier, status, and offer buttons
]]
function FinanceManagerFrame:updateSaleListings(farmId)
    -- Check if vehicle sale system is enabled
    local saleEnabled = true
    if UsedPlusSettings and UsedPlusSettings.get then
        saleEnabled = UsedPlusSettings:get("enableVehicleSaleSystem") ~= false
    end

    local maxSales = FinanceManagerFrame.MAX_SALE_ROWS

    -- Hide all rows first
    for i = 0, FinanceManagerFrame.MAX_SALE_ROWS - 1 do
        if self.saleRows[i] and self.saleRows[i].row then
            self.saleRows[i].row:setVisible(false)
        end
    end

    -- If system disabled, show message and return
    if not saleEnabled then
        if self.saleEmptyText then
            self.saleEmptyText:setText(g_i18n:getText("usedplus_fmf_saleDisabled") or "Vehicle sale system disabled in settings")
            self.saleEmptyText:setVisible(true)
        end
        return
    end

    local listingCount = 0
    local pendingOffers = 0

    -- Show empty state initially
    if self.saleEmptyText then
        self.saleEmptyText:setVisible(true)
        self.saleEmptyText:setText(string.format("No listings (0/%d). Sell from Garage menu.", maxSales))
    end

    -- Clear active listings for button handlers
    self.activeSaleListings = {}

    -- Get listings from VehicleSaleManager
    if g_vehicleSaleManager then
        local listings = g_vehicleSaleManager:getListingsForFarm(farmId)
        if listings and #listings > 0 then
            local rowIndex = 0

            for _, listing in ipairs(listings) do
                -- Only show active or pending offer listings
                local isActiveOrPending = (listing.status == "active" or
                                          listing.status == "pending" or
                                          listing.status == VehicleSaleListing.STATUS.ACTIVE or
                                          listing.status == VehicleSaleListing.STATUS.OFFER_PENDING)
                if isActiveOrPending and rowIndex < FinanceManagerFrame.MAX_SALE_ROWS then
                    -- Store listing reference for button handlers
                    table.insert(self.activeSaleListings, listing)

                    -- Get listing details
                    local itemName = listing.vehicleName or "Unknown Vehicle"
                    local tierConfig = VehicleSaleListing.SALE_TIERS[listing.agentTier] or VehicleSaleListing.SALE_TIERS[1]
                    local tierName = tierConfig.name or "Local"
                    local status = listing.status or "active"
                    local hasPendingOffer = (status == "pending" or
                                            status == VehicleSaleListing.STATUS.OFFER_PENDING)

                    -- Truncate item name if too long
                    if #itemName > 18 then
                        itemName = string.sub(itemName, 1, 16) .. ".."
                    end

                    -- Calculate time remaining
                    local ttl = listing.ttl or 0
                    local monthsLeft = math.ceil(ttl / 24)
                    local hoursLeft = ttl % 24
                    local timeStr
                    if monthsLeft > 0 then
                        timeStr = string.format("%dmo left", monthsLeft)
                    elseif hoursLeft > 0 then
                        timeStr = string.format("%dhr left", hoursLeft)
                    else
                        timeStr = "Expiring"
                    end

                    -- Status text
                    local statusText
                    if hasPendingOffer then
                        local offerAmount = listing.currentOffer or 0
                        statusText = string.format("OFFER: %s", g_i18n:formatMoney(offerAmount, 0, true, true))
                        pendingOffers = pendingOffers + 1
                    else
                        statusText = "Searching..."
                    end

                    listingCount = listingCount + 1

                    -- Update row elements
                    local row = self.saleRows[rowIndex]
                    if row then
                        if row.row then row.row:setVisible(true) end
                        if row.item then row.item:setText(itemName) end
                        if row.tier then row.tier:setText(tierName) end
                        if row.status then
                            row.status:setText(statusText)
                            if hasPendingOffer then
                                row.status:setTextColor(0.4, 1, 0.4, 1)
                            else
                                row.status:setTextColor(0.7, 0.7, 0.7, 1)
                            end
                        end
                        if row.time then row.time:setText(timeStr) end

                        -- Show offers received count
                        if row.offers then
                            local offersCount = listing.offersReceived or 0
                            row.offers:setText(tostring(offersCount))
                            if offersCount > 0 then
                                row.offers:setTextColor(0.9, 0.7, 0.4, 1)
                            else
                                row.offers:setTextColor(0.5, 0.5, 0.5, 1)
                            end
                        end

                        -- Info button (always visible)
                        if row.infoBtn then row.infoBtn:setVisible(true) end
                        if row.infoBtnBg then row.infoBtnBg:setVisible(true) end
                        if row.infoBtnText then row.infoBtnText:setVisible(true) end

                        -- Accept/Decline buttons (only for pending offers)
                        if row.acceptBtn then row.acceptBtn:setVisible(hasPendingOffer) end
                        if row.acceptBtnBg then row.acceptBtnBg:setVisible(hasPendingOffer) end
                        if row.acceptBtnText then row.acceptBtnText:setVisible(hasPendingOffer) end

                        if row.declineBtn then row.declineBtn:setVisible(hasPendingOffer) end
                        if row.declineBtnBg then row.declineBtnBg:setVisible(hasPendingOffer) end
                        if row.declineBtnText then row.declineBtnText:setVisible(hasPendingOffer) end

                        -- Cancel button (only for active listings without pending offer)
                        if row.cancelBtn then row.cancelBtn:setVisible(not hasPendingOffer) end
                        if row.cancelBtnBg then row.cancelBtnBg:setVisible(not hasPendingOffer) end
                        if row.cancelBtnText then row.cancelBtnText:setVisible(not hasPendingOffer) end

                        -- Highlight row background for pending offers
                        if row.bg then
                            if hasPendingOffer then
                                row.bg:setImageColor(nil, 0.15, 0.25, 0.15, 1)
                            else
                                row.bg:setImageColor(nil, 0.1, 0.12, 0.1, 1)
                            end
                        end
                    end

                    rowIndex = rowIndex + 1
                end
            end

            -- Hide empty text if we have listings
            if rowIndex > 0 and self.saleEmptyText then
                self.saleEmptyText:setVisible(false)
            end
        end
    end

    -- Update listings count text
    if self.saleListingsCountText then
        if pendingOffers > 0 then
            self.saleListingsCountText:setText(string.format("%d/%d (%d offers!)", listingCount, maxSales, pendingOffers))
            self.saleListingsCountText:setTextColor(0.4, 1, 0.4, 1)
        else
            self.saleListingsCountText:setText(string.format("%d/%d", listingCount, maxSales))
            self.saleListingsCountText:setTextColor(0.6, 0.6, 0.6, 1)
        end
    end
end

-- Accept Sale Offer button handlers
function FinanceManagerFrame:onAcceptSale0() self:onAcceptSaleClick(0) end
function FinanceManagerFrame:onAcceptSale1() self:onAcceptSaleClick(1) end
function FinanceManagerFrame:onAcceptSale2() self:onAcceptSaleClick(2) end

-- Decline Sale Offer button handlers
function FinanceManagerFrame:onDeclineSale0() self:onDeclineSaleClick(0) end
function FinanceManagerFrame:onDeclineSale1() self:onDeclineSaleClick(1) end
function FinanceManagerFrame:onDeclineSale2() self:onDeclineSaleClick(2) end

-- Cancel Sale Listing button handlers
function FinanceManagerFrame:onCancelSale0() self:onCancelSaleClick(0) end
function FinanceManagerFrame:onCancelSale1() self:onCancelSaleClick(1) end
function FinanceManagerFrame:onCancelSale2() self:onCancelSaleClick(2) end

-- Edit Sale Price button handlers
function FinanceManagerFrame:onEditSale0() self:onEditSaleClick(0) end
function FinanceManagerFrame:onEditSale1() self:onEditSaleClick(1) end
function FinanceManagerFrame:onEditSale2() self:onEditSaleClick(2) end

-- Info Sale Listing button handlers
function FinanceManagerFrame:onInfoSale0() self:onInfoSaleClick(0) end
function FinanceManagerFrame:onInfoSale1() self:onInfoSaleClick(1) end
function FinanceManagerFrame:onInfoSale2() self:onInfoSaleClick(2) end

--[[
    Handle Info button click for a sale row
]]
function FinanceManagerFrame:onInfoSaleClick(rowIndex)
    if not self.activeSaleListings or rowIndex >= #self.activeSaleListings then
        return
    end

    local listing = self.activeSaleListings[rowIndex + 1]
    if not listing then
        return
    end

    if SaleListingDetailsDialog then
        DialogLoader.show("SaleListingDetailsDialog", "show", listing)
    end
end

--[[
    Handle Accept button click for a sale listing row
]]
function FinanceManagerFrame:onAcceptSaleClick(rowIndex)
    if not self.activeSaleListings or rowIndex >= #self.activeSaleListings then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noSaleListingInRow")
        )
        return
    end

    local listing = self.activeSaleListings[rowIndex + 1]
    if not listing then
        return
    end

    -- Verify listing has pending offer
    local isPending = (listing.status == "pending" or
                      listing.status == VehicleSaleListing.STATUS.OFFER_PENDING)
    if not isPending then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noOfferPending")
        )
        return
    end

    local self_ref = self
    local listingId = listing.id
    local vehicleName = listing.vehicleName or "Unknown"
    local offerAmount = listing.currentOffer or 0

    -- Show full SaleOfferDialog for detailed review
    local callback = function(accepted)
        if accepted then
            if SaleListingActionEvent then
                SaleListingActionEvent.sendToServer(listingId, SaleListingActionEvent.ACTION_ACCEPT)
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_OK,
                    string.format(g_i18n:getText("usedplus_notify_vehicleSold"), vehicleName, g_i18n:formatMoney(offerAmount, 0, true, true))
                )
            elseif AcceptSaleOfferEvent then
                AcceptSaleOfferEvent.sendToServer(listingId)
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_OK,
                    string.format(g_i18n:getText("usedplus_notify_vehicleSold"), vehicleName, g_i18n:formatMoney(offerAmount, 0, true, true))
                )
            end
        end
        self_ref:updateDisplay()
    end

    SaleOfferDialog.showForListing(listing, callback)
end

--[[
    Handle Decline button click for a sale listing row
]]
function FinanceManagerFrame:onDeclineSaleClick(rowIndex)
    if not self.activeSaleListings or rowIndex >= #self.activeSaleListings then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noSaleListingInRow")
        )
        return
    end

    local listing = self.activeSaleListings[rowIndex + 1]
    if not listing then
        return
    end

    -- Verify listing has pending offer
    local isPending = (listing.status == "pending" or
                      listing.status == VehicleSaleListing.STATUS.OFFER_PENDING)
    if not isPending then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noOfferToDecline")
        )
        return
    end

    -- Show confirmation dialog
    local offerAmount = listing.currentOffer or 0
    local vehicleName = listing.vehicleName or "Unknown"
    local message = string.format(
        "Decline offer of %s for %s?\n\nThe agent will continue searching for other buyers.",
        g_i18n:formatMoney(offerAmount, 0, true, true),
        vehicleName
    )

    YesNoDialog.show(
        function(yes)
            if yes then
                if DeclineSaleOfferEvent then
                    DeclineSaleOfferEvent.sendToServer(listing.id)
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_INFO,
                        g_i18n:getText("usedplus_notify_offerDeclined")
                    )
                end
                self:updateDisplay()
            end
        end,
        nil,
        message,
        "Decline Sale Offer"
    )
end

--[[
    Handle Cancel button click for a sale listing row
]]
function FinanceManagerFrame:onCancelSaleClick(rowIndex)
    if not self.activeSaleListings or rowIndex >= #self.activeSaleListings then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noSaleListingInRow")
        )
        return
    end

    local listing = self.activeSaleListings[rowIndex + 1]
    if not listing then
        return
    end

    -- Verify listing does NOT have pending offer
    local isPending = (listing.status == "pending" or
                      listing.status == VehicleSaleListing.STATUS.OFFER_PENDING)
    if isPending then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_cannotCancelPendingOffer")
        )
        return
    end

    -- Show confirmation dialog
    local vehicleName = listing.vehicleName or "Unknown"
    local agentFee = listing.agentFee or 0
    local message = string.format(
        "Cancel sale listing for %s?\n\n" ..
        "WARNING: The agent fee of %s will NOT be refunded.\n\n" ..
        "The vehicle will remain in your possession.",
        vehicleName,
        g_i18n:formatMoney(agentFee, 0, true, true)
    )

    YesNoDialog.show(
        function(yes)
            if yes then
                if SaleListingActionEvent then
                    SaleListingActionEvent.cancelListing(listing.id)
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_INFO,
                        string.format(g_i18n:getText("usedplus_notify_listingCancelled"), vehicleName)
                    )
                end
                self:updateDisplay()
            end
        end,
        nil,
        message,
        "Cancel Sale Listing"
    )
end

--[[
    Handle Edit Price button click for a sale row
]]
function FinanceManagerFrame:onEditSaleClick(rowIndex)
    if not self.activeSaleListings or rowIndex >= #self.activeSaleListings then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noSaleListingInRow")
        )
        return
    end

    local listing = self.activeSaleListings[rowIndex + 1]
    if not listing then
        return
    end

    -- Verify listing is in searching status
    if listing.status ~= "searching" then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_cannotModifyPendingOffer")
        )
        return
    end

    -- Store listing reference for callback
    self.pendingEditListing = listing

    -- Use TextInputDialog to get new price
    local currentPrice = listing.askingPrice or 0
    local vehicleName = listing.vehicleName or "Unknown"

    g_gui:showTextInputDialog({
        callback = function(text, args)
            self:onEditPriceInputComplete(text)
        end,
        target = self,
        dialogPrompt = string.format("Enter new asking price for %s\n(Current: %s)",
            vehicleName, g_i18n:formatMoney(currentPrice, 0, true, true)),
        defaultText = tostring(math.floor(currentPrice)),
        maxCharacters = 10,
        confirmText = "Update Price"
    })
end

--[[
    Handle text input completion for price edit
]]
function FinanceManagerFrame:onEditPriceInputComplete(text)
    local listing = self.pendingEditListing
    self.pendingEditListing = nil

    if text == nil or text == "" or listing == nil then
        return
    end

    local newPrice = tonumber(text)
    if newPrice == nil or newPrice <= 0 then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_invalidPrice")
        )
        return
    end

    if ModifyListingPriceEvent then
        ModifyListingPriceEvent.sendToServer(listing.id, newPrice)
        self:updateDisplay()
    else
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            "Error: ModifyListingPriceEvent not available"
        )
    end
end

UsedPlus.logDebug("SalesPanel module loaded")
