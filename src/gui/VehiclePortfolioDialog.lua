--[[
    FS25_UsedPlus - Vehicle Portfolio Dialog
    Carousel-style browser for vehicles found by agent search

    v1.5.0: Part of multi-find agent model
    Displays one vehicle at a time with Prev/Next navigation.
    Actions: View Details (inspect/buy), Decline (remove from portfolio), Close

    Pattern: ScreenElement (NOT MessageDialog)
]]

VehiclePortfolioDialog = {}
local VehiclePortfolioDialog_mt = Class(VehiclePortfolioDialog, ScreenElement)

-- Static instance
VehiclePortfolioDialog.instance = nil
VehiclePortfolioDialog.xmlPath = nil

--[[
    Get or create dialog instance
]]
function VehiclePortfolioDialog.getInstance()
    if VehiclePortfolioDialog.instance == nil then
        if VehiclePortfolioDialog.xmlPath == nil then
            VehiclePortfolioDialog.xmlPath = UsedPlus.MOD_DIR .. "gui/VehiclePortfolioDialog.xml"
        end

        VehiclePortfolioDialog.instance = VehiclePortfolioDialog.new()
        g_gui:loadGui(VehiclePortfolioDialog.xmlPath, "VehiclePortfolioDialog", VehiclePortfolioDialog.instance)

        UsedPlus.logDebug("VehiclePortfolioDialog created and loaded from: " .. VehiclePortfolioDialog.xmlPath)
    end

    return VehiclePortfolioDialog.instance
end

--[[
    Constructor
]]
function VehiclePortfolioDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or VehiclePortfolioDialog_mt)

    self.search = nil
    self.currentIndex = 1
    self.isBackAllowed = true

    return self
end

--[[
    Called when dialog is created
]]
function VehiclePortfolioDialog:onCreate()
    -- No superclass call needed for ScreenElement
end

--[[
    Show dialog with search's found vehicles
    @param search - UsedVehicleSearch object with foundListings
]]
function VehiclePortfolioDialog:show(search)
    if search == nil then
        UsedPlus.logError("VehiclePortfolioDialog:show called with nil search")
        return
    end

    self.search = search
    self.currentIndex = 1

    local foundCount = #(search.foundListings or {})
    if foundCount == 0 then
        UsedPlus.logWarn("VehiclePortfolioDialog:show called but no listings found")
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            "No vehicles in portfolio. Check back next month!"
        )
        return
    end

    -- Populate all fields
    self:updateDisplay()

    -- Show the dialog
    g_gui:showDialog("VehiclePortfolioDialog")
end

--[[
    Update all display fields for current vehicle
]]
function VehiclePortfolioDialog:updateDisplay()
    if self.search == nil then return end

    local listings = self.search.foundListings or {}
    local foundCount = #listings

    if foundCount == 0 then
        -- No vehicles left - close dialog
        self:closeDialog()
        return
    end

    -- Clamp index to valid range
    if self.currentIndex < 1 then
        self.currentIndex = 1
    elseif self.currentIndex > foundCount then
        self.currentIndex = foundCount
    end

    local listing = listings[self.currentIndex]
    if listing == nil then
        UsedPlus.logError("VehiclePortfolioDialog: listing is nil at index " .. tostring(self.currentIndex))
        return
    end

    -- Title
    if self.titleText then
        self.titleText:setText("Found Vehicles")
    end

    -- Navigation counter
    if self.navCounterText then
        self.navCounterText:setText(string.format("%d of %d", self.currentIndex, foundCount))
    end

    -- Update nav button states
    if self.prevButton then
        self.prevButton:setDisabled(self.currentIndex <= 1)
    end
    if self.nextButton then
        self.nextButton:setDisabled(self.currentIndex >= foundCount)
    end

    -- Vehicle name
    if self.vehicleNameText then
        self.vehicleNameText:setText(self.search.storeItemName or "Unknown Vehicle")
    end

    -- Vehicle image
    if self.vehicleImage then
        local storeItem = g_storeManager:getItemByXMLFilename(self.search.storeItemIndex)
        if storeItem then
            if UIHelper and UIHelper.Image and UIHelper.Image.setStoreItemImage then
                UIHelper.Image.setStoreItemImage(self.vehicleImage, storeItem)
            else
                local imagePath = storeItem.imageFilename
                if imagePath then
                    self.vehicleImage:setImageFilename(imagePath)
                end
            end
        end
    end

    -- Quality tier
    if self.qualityText then
        self.qualityText:setText(listing.qualityName or "Standard")
    end

    -- Condition (from damage value)
    if self.conditionText then
        local condition = math.floor((1 - (listing.damage or 0)) * 100)
        self.conditionText:setText(string.format("%d%%", condition))

        -- Color based on condition
        if condition >= 85 then
            self.conditionText:setTextColor(0.3, 1, 0.4, 1)  -- Green
        elseif condition >= 60 then
            self.conditionText:setTextColor(1, 0.9, 0.3, 1)  -- Yellow
        else
            self.conditionText:setTextColor(1, 0.5, 0.3, 1)  -- Orange
        end
    end

    -- Inspected status
    local isInspected = listing.wasInspected or false
    if self.inspectedText then
        if isInspected then
            self.inspectedText:setText(g_i18n:getText("usedplus_common_yes") or "Yes")
            self.inspectedText:setTextColor(0.3, 1, 0.4, 1)  -- Green
        else
            self.inspectedText:setText(g_i18n:getText("usedplus_common_no") or "No")
            self.inspectedText:setTextColor(0.7, 0.7, 0.7, 1)  -- Gray
        end
    end

    -- Update View Details button text based on inspection status
    if self.viewDetailsButton then
        if isInspected then
            -- Already inspected - show "Buy Now" instead
            self.viewDetailsButton:setText(g_i18n:getText("usedplus_button_buyNow") or "Buy Now")
        else
            -- Not inspected - show "View Details" (which includes inspect option)
            self.viewDetailsButton:setText(g_i18n:getText("usedplus_button_viewDetail") or "View Details")
        end
    end

    -- Pricing
    if self.basePriceText then
        self.basePriceText:setText(g_i18n:formatMoney(listing.basePrice or 0, 0, true, true))
    end

    if self.commissionText then
        local commission = listing.commissionAmount or 0
        self.commissionText:setText(string.format("+%s", g_i18n:formatMoney(commission, 0, true, true)))
    end

    if self.askingPriceText then
        self.askingPriceText:setText(g_i18n:formatMoney(listing.askingPrice or 0, 0, true, true))
    end

    -- Expiration warning
    if self.expirationText then
        local monthsRemaining = self.search:getListingMonthsRemaining(listing)

        if monthsRemaining <= 1 then
            self.expirationText:setText("Offer expires NEXT MONTH!")
            self.expirationText:setTextColor(1, 0.4, 0.3, 1)  -- Red - urgent
        elseif monthsRemaining == 2 then
            self.expirationText:setText("Offer expires in 2 months")
            self.expirationText:setTextColor(1, 0.7, 0.3, 1)  -- Orange - warning
        else
            self.expirationText:setText(string.format("Offer valid for %d months", monthsRemaining))
            self.expirationText:setTextColor(1, 0.85, 0.4, 1)  -- Yellow - normal
        end
    end

    -- Info text with tip
    if self.infoText then
        if foundCount > 1 then
            self.infoText:setText("Use Prev/Next to browse. View Details to inspect or buy.")
        else
            self.infoText:setText("View Details to inspect condition or purchase this vehicle.")
        end
    end
end

--[[
    Navigate to previous vehicle
]]
function VehiclePortfolioDialog:onClickPrev()
    if self.currentIndex > 1 then
        self.currentIndex = self.currentIndex - 1
        self:updateDisplay()
    end
end

--[[
    Navigate to next vehicle
]]
function VehiclePortfolioDialog:onClickNext()
    local foundCount = #(self.search.foundListings or {})
    if self.currentIndex < foundCount then
        self.currentIndex = self.currentIndex + 1
        self:updateDisplay()
    end
end

--[[
    Open UsedVehiclePreviewDialog for current vehicle
]]
function VehiclePortfolioDialog:onClickViewDetails()
    local listing = self:getCurrentListing()
    if listing == nil then
        UsedPlus.logError("No current listing to view")
        return
    end

    -- Build a listing object compatible with UsedVehiclePreviewDialog
    local previewListing = self:buildPreviewListing(listing)

    -- Close this dialog
    self:closeDialog()

    -- Open preview dialog with purchase callback
    local farmId = g_currentMission:getFarmId()
    DialogLoader.show("UsedVehiclePreviewDialog", "show",
        previewListing,
        farmId,
        function(confirmed, purchasedListing)
            self:onPreviewResult(confirmed, purchasedListing, listing)
        end,
        self)
end

--[[
    Build a listing object for UsedVehiclePreviewDialog
    Converts our portfolio listing format to the format expected by preview dialog
]]
function VehiclePortfolioDialog:buildPreviewListing(listing)
    return {
        storeItemIndex = self.search.storeItemIndex,
        storeItemName = self.search.storeItemName,
        price = listing.askingPrice or 0,
        damage = listing.damage or 0,
        wear = listing.wear or 0,
        age = 0,  -- Not tracked per-listing
        operatingHours = 0,  -- Not tracked per-listing
        usedPlusData = {
            wasInspected = listing.wasInspected or false,
            -- Additional data for purchase handling
            searchId = self.search.id,
            listingId = listing.id,
            basePrice = listing.basePrice,
            commissionAmount = listing.commissionAmount
        }
    }
end

--[[
    Handle result from preview dialog
    @param confirmed - Whether purchase was confirmed
    @param purchasedListing - The listing data
    @param originalListing - Our portfolio listing reference
]]
function VehiclePortfolioDialog:onPreviewResult(confirmed, purchasedListing, originalListing)
    if confirmed then
        -- Player bought the vehicle - search should end
        UsedPlus.logInfo("Vehicle purchased from portfolio - completing search")

        -- Mark search as completed (client-side UI state)
        if self.search then
            self.search.status = "completed"

            -- Use network event for multiplayer synchronization
            -- Event handles: validation, finding search/listing, calling manager, response to client
            PurchaseUsedVehicleEvent.sendToServer(
                g_currentMission:getFarmId(),
                self.search.id,
                originalListing.id
            )
        end
    else
        -- Player cancelled - mark as inspected if they paid for inspection
        if purchasedListing and purchasedListing.usedPlusData and purchasedListing.usedPlusData.wasInspected then
            originalListing.wasInspected = true
        end

        -- Re-open portfolio dialog so they can continue browsing
        self:show(self.search)
    end
end

--[[
    Decline current vehicle offer (remove from portfolio)
    v1.5.0: Uses DeclineListingEvent for multiplayer sync
]]
function VehiclePortfolioDialog:onClickDecline()
    local listing = self:getCurrentListing()
    if listing == nil then
        UsedPlus.logError("No current listing to decline")
        return
    end

    if self.search == nil or self.search.id == nil then
        UsedPlus.logError("No search ID for decline")
        return
    end

    -- Send decline event (handles both single-player and multiplayer)
    DeclineListingEvent.sendToServer(self.search.id, listing.id)

    -- Notify player
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_INFO,
        "Offer declined. Seller has been notified."
    )

    -- Update display (will close if no listings left)
    -- Note: foundListings was updated by the event execution
    local remainingCount = #(self.search.foundListings or {})
    if remainingCount == 0 then
        self:closeDialog()
    else
        -- Adjust index if we removed the last item
        if self.currentIndex > remainingCount then
            self.currentIndex = remainingCount
        end
        self:updateDisplay()
    end
end

--[[
    Get the current listing
]]
function VehiclePortfolioDialog:getCurrentListing()
    if self.search == nil then return nil end
    local listings = self.search.foundListings or {}
    return listings[self.currentIndex]
end

--[[
    Close the dialog
]]
function VehiclePortfolioDialog:closeDialog()
    g_gui:changeScreen(nil)
end

--[[
    Handle close button click
]]
function VehiclePortfolioDialog:onClickClose()
    self:closeDialog()
end

--[[
    Handle ESC key / back button
]]
function VehiclePortfolioDialog:onClickBack()
    self:closeDialog()
    return true  -- Handled
end

--[[
    Called when dialog opens
]]
function VehiclePortfolioDialog:onOpen()
    VehiclePortfolioDialog:superClass().onOpen(self)
end

--[[
    Called when dialog closes
]]
function VehiclePortfolioDialog:onClose()
    VehiclePortfolioDialog:superClass().onClose(self)
end

UsedPlus.logInfo("VehiclePortfolioDialog loaded")
