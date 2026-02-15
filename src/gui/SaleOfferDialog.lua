--[[
    FS25_UsedPlus - Sale Offer Dialog

    REDESIGNED v1.9.6: Player-focused framing
    - Removed "vanilla" terminology - players don't think that way
    - Added deal quality rating with stars (★★★★☆)
    - Shows expected range with visual bar positioning
    - "Keep Waiting" instead of "Decline" - implies hope

    v1.9.7: Simplified "Your Options" section
    - Removed "Sell Instantly" (no instant sell in UsedPlus)
    - Removed confusing "+X%" bonus display

    Features:
    - Shows offer amount prominently with deal quality
    - Visual range bar showing where offer falls
    - Simple accept/wait options
    - Expiration countdown
]]

SaleOfferDialog = {}
-- Use ScreenElement, NOT MessageDialog (MessageDialog lacks registerControls,
-- and setPosition() breaks element visibility — see UnifiedPurchaseDialog.lua:1076)
local SaleOfferDialog_mt = Class(SaleOfferDialog, ScreenElement)

-- Deal quality thresholds (position in range 0-1)
SaleOfferDialog.DEAL_RATINGS = {
    { threshold = 0.00, stars = "★★☆☆☆", text = "Fair Offer",     color = {0.8, 0.8, 0.3, 1} },
    { threshold = 0.25, stars = "★★★☆☆", text = "Good Deal",      color = {0.7, 0.9, 0.3, 1} },
    { threshold = 0.50, stars = "★★★★☆", text = "Great Deal",     color = {0.4, 1.0, 0.4, 1} },
    { threshold = 0.75, stars = "★★★★★", text = "Excellent Deal", color = {0.3, 1.0, 0.3, 1} },
}

--[[
    Constructor - extends ScreenElement (pattern from NegotiationDialog)
]]
function SaleOfferDialog.new(target, custom_mt, i18n)
    local self = ScreenElement.new(target, custom_mt or SaleOfferDialog_mt)

    self.i18n = i18n or g_i18n

    -- Data
    self.listing = nil
    self.callback = nil

    -- v2.9.5: Icon directory for dynamic icons
    self.iconDir = UsedPlus.MOD_DIR .. "gui/icons/"

    return self
end

--[[
    Set the listing with pending offer
    @param listing - VehicleSaleListing with pending offer
    @param callback - Function called with (accepted: boolean) on decision
]]
function SaleOfferDialog:setListing(listing, callback)
    self.listing = listing
    self.callback = callback

    UsedPlus.logDebug(string.format("SaleOfferDialog: Set listing %s with offer $%d",
        listing.id, listing.currentOffer or 0))
end

--[[
    Called when dialog opens
]]
function SaleOfferDialog:onOpen()
    SaleOfferDialog:superClass().onOpen(self)

    -- v2.9.5: Setup section icons
    self:setupSectionIcons()

    self:updateDisplay()
end

--[[
    v2.9.5: Setup section icons
]]
function SaleOfferDialog:setupSectionIcons()
    -- Quality star icon
    local qualityIcon = self.dialogElement:getDescendantById("qualityIcon")
    if qualityIcon ~= nil then
        qualityIcon:setImageFilename(self.iconDir .. "quality_star.png")
    end

    -- Timer icon
    local timerIcon = self.dialogElement:getDescendantById("timerIcon")
    if timerIcon ~= nil then
        timerIcon:setImageFilename(self.iconDir .. "timer.png")
    end

    -- Range arrow markers (11 positions: 0% to 100% in 10% steps)
    -- Load arrow PNG on all, then show/hide in updateDisplay
    local arrowPath = self.iconDir .. "range_marker.png"
    self.arrowMarkers = {}
    local arrowIds = {"arrow0", "arrow5", "arrow10", "arrow15", "arrow20", "arrow25", "arrow30", "arrow35", "arrow40", "arrow45", "arrow50", "arrow55", "arrow60", "arrow65", "arrow70", "arrow75", "arrow80", "arrow85", "arrow90", "arrow95", "arrow100"}
    for _, id in pairs(arrowIds) do
        local arrow = self.dialogElement:getDescendantById(id)
        if arrow ~= nil then
            arrow:setImageFilename(arrowPath)
            arrow:setVisible(false)  -- Start hidden, updateDisplay shows the right one
            table.insert(self.arrowMarkers, { element = arrow, id = id })
            UsedPlus.logDebug(string.format("SaleOfferDialog: Arrow '%s' loaded + hidden", id))
        else
            UsedPlus.logWarn(string.format("SaleOfferDialog: Arrow '%s' not found!", id))
        end
    end
    UsedPlus.logDebug(string.format("SaleOfferDialog: %d arrow markers loaded", #self.arrowMarkers))
end

--[[
    Calculate deal quality rating based on where offer falls in expected range
    @return rating table with stars, text, color, and position (0-1)
]]
function SaleOfferDialog:calculateDealRating()
    if self.listing == nil then
        return SaleOfferDialog.DEAL_RATINGS[1], 0
    end

    local offer = self.listing.currentOffer or 0
    local minPrice = self.listing.expectedMinPrice or offer
    local maxPrice = self.listing.expectedMaxPrice or offer

    -- Calculate position in range (0 = min, 1 = max)
    local range = maxPrice - minPrice
    local position = 0
    if range > 0 then
        position = math.max(0, math.min(1, (offer - minPrice) / range))
    elseif offer >= maxPrice then
        position = 1  -- At or above max
    end

    -- Find appropriate rating
    local rating = SaleOfferDialog.DEAL_RATINGS[1]
    for i = #SaleOfferDialog.DEAL_RATINGS, 1, -1 do
        if position >= SaleOfferDialog.DEAL_RATINGS[i].threshold then
            rating = SaleOfferDialog.DEAL_RATINGS[i]
            break
        end
    end

    return rating, position
end

--[[
    Update all display elements
    REDESIGNED v1.9.6: Complete overhaul for player-focused presentation
]]
function SaleOfferDialog:updateDisplay()
    if self.listing == nil then return end

    -- ================================================================
    -- SECTION 1: Vehicle Info
    -- ================================================================
    UIHelper.Element.setText(self.vehicleNameText, self.listing.vehicleName or "Unknown Vehicle")
    UIHelper.Image.setImagePath(self.vehicleImage, self.listing.vehicleImageFile)

    -- Agent info: "Standard Agent · Fair Market"
    local agentTier = self.listing:getAgentTierConfig()
    local priceTier = self.listing:getPriceTierConfig()
    local agentInfo = string.format("%s · %s", agentTier.name or "Agent", priceTier.name or "Standard")
    UIHelper.Element.setText(self.agentTierText, agentInfo)

    -- ================================================================
    -- SECTION 2: The Offer + Deal Rating
    -- ================================================================
    local offer = self.listing.currentOffer or 0
    UIHelper.Element.setText(self.offerAmountText, UIHelper.Text.formatMoney(offer))

    -- Calculate and display deal rating
    local rating, position = self:calculateDealRating()
    local ratingText = string.format("%s %s", rating.stars, rating.text)
    if self.dealRatingText then
        self.dealRatingText:setText(ratingText)
        self.dealRatingText:setTextColor(unpack(rating.color))
    end

    -- ================================================================
    -- SECTION 3: Expected Range
    -- ================================================================
    local minPrice = self.listing.expectedMinPrice or offer
    local maxPrice = self.listing.expectedMaxPrice or offer

    UIHelper.Element.setText(self.rangeMinText, UIHelper.Text.formatMoney(minPrice))
    UIHelper.Element.setText(self.rangeMaxText, UIHelper.Text.formatMoney(maxPrice))

    -- Show the arrow marker closest to the offer position
    -- Markers at 0%, 5%, 10%, ..., 100% — snap to nearest (±2.5% accuracy)
    local markerPositions = {0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100}
    local pctOfRange = math.floor(position * 100)
    local closestIdx = 1
    local closestDist = 999
    for i, pct in ipairs(markerPositions) do
        local dist = math.abs(pctOfRange - pct)
        if dist < closestDist then
            closestDist = dist
            closestIdx = i
        end
    end

    -- Show closest arrow, hide others
    if self.arrowMarkers then
        for i, marker in ipairs(self.arrowMarkers) do
            if marker.element then
                marker.element:setVisible(i == closestIdx)
            end
        end
        UsedPlus.logDebug(string.format("SaleOfferDialog: Showing arrow #%d for %d%%", closestIdx, pctOfRange))
    end

    -- Offer price display
    UIHelper.Element.setText(self.rangeOfferText, UIHelper.Text.formatMoney(offer))

    -- ================================================================
    -- SECTION 4: Your Options (simplified - just show offer amount)
    -- ================================================================
    UIHelper.Element.setText(self.thisOfferText, UIHelper.Text.formatMoney(offer))

    -- ================================================================
    -- SECTION 5: Expiration
    -- ================================================================
    local expiresIn = self.listing.offerExpiresIn or 0
    UIHelper.Element.setText(self.expirationText, UIHelper.Text.formatHours(expiresIn))
end

--[[
    Handle accept button click
    CRITICAL: Close dialog BEFORE callback - callback may delete the vehicle
    which causes errors if dialog is still referencing it
]]
function SaleOfferDialog:onClickAccept()
    if self.listing == nil then
        self:close()
        return
    end

    -- Cache values before closing (dialog will lose reference to listing)
    local vehicleName = self.listing.vehicleName
    local offerAmount = self.listing.currentOffer or 0
    local callback = self.callback

    -- Close dialog FIRST (before vehicle gets deleted)
    self:close()

    -- Log the acceptance
    UsedPlus.logDebug(string.format("Offer accepted for %s: $%d", vehicleName, offerAmount))

    -- Call callback AFTER close (this may delete the vehicle)
    if callback then
        callback(true)
    end
end

--[[
    Handle decline button click (now called "Keep Waiting")
    Close dialog before callback for consistency with accept pattern
]]
function SaleOfferDialog:onClickDecline()
    -- Cache values before closing
    local vehicleName = self.listing and self.listing.vehicleName or "Unknown"
    local callback = self.callback

    -- Close dialog first
    self:close()

    -- Log the decline
    UsedPlus.logDebug(string.format("Offer declined (keep waiting) for %s", vehicleName))

    -- Call callback after close
    if callback then
        callback(false)
    end
end

--[[
    Close this dialog properly
    v1.9.5: Use closeDialogByName pattern like other dialogs
]]
function SaleOfferDialog:close()
    g_gui:closeDialogByName("SaleOfferDialog")
end

--[[
    Show the offer dialog for a listing
    Static helper function
    @param listing - VehicleSaleListing with pending offer
    @param callback - Function called with (accepted: boolean)
]]
function SaleOfferDialog.showForListing(listing, callback)
    if listing == nil then
        UsedPlus.logError("Cannot show offer dialog - listing is nil")
        return false
    end

    if listing.currentOffer == nil or listing.currentOffer <= 0 then
        UsedPlus.logError("Cannot show offer dialog - no valid offer amount")
        return false
    end

    UsedPlus.logDebug(string.format("SaleOfferDialog.showForListing: listing=%s, offer=$%d",
        tostring(listing.id), listing.currentOffer or 0))

    -- Use DialogLoader for centralized lazy loading
    return DialogLoader.show("SaleOfferDialog", "setListing", listing, callback)
end

UsedPlus.logInfo("SaleOfferDialog loaded (v2.9.5)")
