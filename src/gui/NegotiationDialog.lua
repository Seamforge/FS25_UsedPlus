--[[
    FS25_UsedPlus - Negotiation Dialog
    v2.6.0: Used vehicle offer negotiation system

    Shows mechanic's whisper intel about seller and allows player to make offers.
    Pattern from: ScreenElement (NOT MessageDialog)

    Flow:
    1. Player clicks "Make Offer" on InspectionReportDialog
    2. NegotiationDialog opens showing:
       - Vehicle info and asking price
       - Mechanic's whisper (seller intel)
       - Offer percentage selection (70-100%)
    3. Player selects offer and clicks "Send Offer"
    4. SellerResponseDialog shows accept/counter/reject result
]]

NegotiationDialog = {}
local NegotiationDialog_mt = Class(NegotiationDialog, ScreenElement)

-- Offer percentages available
NegotiationDialog.OFFER_PERCENTAGES = {70, 80, 85, 90, 95, 100}

-- Weather modifiers for negotiation
NegotiationDialog.WEATHER_MODIFIERS = {
    -- Weather types are integers in FS25
    [0] = 0,        -- SUN (baseline)
    [1] = 0.02,     -- CLOUDY
    [2] = 0.05,     -- RAIN
    [3] = 0.08,     -- STORM/THUNDER
    [4] = 0.12,     -- HAIL
    [5] = 0.05,     -- SNOW
    [6] = 0.03,     -- FOG
}

--[[
    Constructor - extends ScreenElement
]]
function NegotiationDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or NegotiationDialog_mt)

    self.listing = nil
    self.search = nil
    self.onOfferCallback = nil
    self.callbackTarget = nil

    -- Current offer state
    self.selectedPercent = 100
    self.offerAmount = 0
    self.askingPrice = 0

    -- v2.9.5: Icon directory for dynamic icons
    self.iconDir = UsedPlus.MOD_DIR .. "gui/icons/"

    -- v2.11.0: Debouncing flag for cancel button
    self.isClosing = false

    return self
end

--[[
    Set dialog data (called via DialogLoader.show)
    @param listing - The used vehicle listing
    @param search - The search this listing came from
    @param onOfferCallback - Function to call with offer result
    @param callbackTarget - Target object for callback
]]
function NegotiationDialog:setData(listing, search, onOfferCallback, callbackTarget)
    -- Store on instance
    self.listing = listing
    self.search = search
    self.onOfferCallback = onOfferCallback
    self.callbackTarget = callbackTarget

    -- Debug: Log what price fields exist in the listing
    UsedPlus.logDebug(string.format("NegotiationDialog:setData - listing.askingPrice=%s, listing.price=%s, listing.basePrice=%s",
        tostring(listing.askingPrice), tostring(listing.price), tostring(listing.basePrice)))

    -- Initialize offer state
    self.askingPrice = listing.askingPrice or listing.price or 0
    self.selectedPercent = 100
    self.offerAmount = self.askingPrice

    UsedPlus.logDebug(string.format("NegotiationDialog:setData - %s, final askingPrice=$%d, personality: %s",
        listing.storeItemName or "Unknown", self.askingPrice, listing.sellerPersonality or "unknown"))
end

--[[
    Called when dialog opens
]]
function NegotiationDialog:onOpen()
    NegotiationDialog:superClass().onOpen(self)

    -- v2.11.0: Reset debounce flag for dialog reuse
    self.isClosing = false

    -- v2.9.5: Setup section icons
    self:setupSectionIcons()

    UsedPlus.logDebug(string.format("NegotiationDialog:onOpen - self.listing=%s, self.askingPrice=%s",
        tostring(self.listing ~= nil), tostring(self.askingPrice)))

    if self.listing then
        self:updateDisplay()
    else
        UsedPlus.logWarn("NegotiationDialog:onOpen - self.listing is nil! Dialog data not set properly.")
    end
end

--[[
    v2.9.5: Setup section icons
]]
function NegotiationDialog:setupSectionIcons()
    -- Vehicle section icon
    local vehicleSectionIcon = self.dialogElement:getDescendantById("vehicleSectionIcon")
    if vehicleSectionIcon ~= nil then
        vehicleSectionIcon:setImageFilename(self.iconDir .. "vehicle.png")
    end

    -- Whisper section icon (lightbulb)
    local whisperSectionIcon = self.dialogElement:getDescendantById("whisperSectionIcon")
    if whisperSectionIcon ~= nil then
        whisperSectionIcon:setImageFilename(self.iconDir .. "lightbulb.png")
    end

    -- Whisper inline icon (also lightbulb for the quote area)
    local whisperIcon = self.dialogElement:getDescendantById("whisperIcon")
    if whisperIcon ~= nil then
        whisperIcon:setImageFilename(self.iconDir .. "lightbulb.png")
    end

    -- Offer section icon
    local offerSectionIcon = self.dialogElement:getDescendantById("offerSectionIcon")
    if offerSectionIcon ~= nil then
        offerSectionIcon:setImageFilename(self.iconDir .. "offer.png")
    end
end

--[[
    Called when dialog closes
]]
function NegotiationDialog:onClose()
    NegotiationDialog:superClass().onClose(self)
end

--[[
    Update all display elements
]]
function NegotiationDialog:updateDisplay()
    local listing = self.listing
    if listing == nil then return end

    -- Get store item for image
    local storeItem = g_storeManager:getItemByXMLFilename(listing.storeItemIndex)

    -- Vehicle name
    if self.vehicleNameText then
        self.vehicleNameText:setText(listing.storeItemName or "Unknown Vehicle")
    end

    -- Asking price
    if self.askingPriceText then
        self.askingPriceText:setText(g_i18n:formatMoney(self.askingPrice, 0, true, true))
    end

    -- Vehicle image
    if self.vehicleImage and storeItem then
        local imagePath = storeItem.imageFilename
        if imagePath then
            self.vehicleImage:setImageFilename(imagePath)
        end
    end

    -- Mechanic's whisper (seller intel)
    self:updateWhisperDisplay()

    -- Offer amount display
    self:updateOfferDisplay()
end

--[[
    Update mechanic's whisper display
    Shows seller intel + weather intel if applicable
]]
function NegotiationDialog:updateWhisperDisplay()
    local listing = self.listing
    if listing == nil then return end

    -- Get seller whisper text
    local whisperType = listing.whisperType or "standard"
    local whisperKey = "usedplus_whisper_" .. whisperType
    local whisperText = g_i18n:getText(whisperKey)

    -- Fallback if translation missing
    if whisperText == whisperKey then
        whisperText = "Between you and me... seems like a straightforward seller."
    end

    if self.whisperText1 then
        self.whisperText1:setText(whisperText)
    end

    -- Weather whisper (second line if weather is significant)
    local weatherModifier = self:getWeatherModifier()
    local weatherWhisper = ""

    if weatherModifier >= 0.05 then
        -- Good negotiating weather
        weatherWhisper = self:getWeatherWhisperText(true)
    elseif weatherModifier <= -0.03 then
        -- Bad negotiating weather
        weatherWhisper = self:getWeatherWhisperText(false)
    end

    if self.whisperText2 then
        self.whisperText2:setText(weatherWhisper)
    end
end

--[[
    Get weather modifier for current conditions
]]
function NegotiationDialog:getWeatherModifier()
    if not g_currentMission or not g_currentMission.environment then
        return 0
    end

    local environment = g_currentMission.environment
    if not environment.weather then
        return 0
    end

    -- Try to get weather type (v2.6.0: Fixed - use getCurrentWeatherType, not getWeatherTypeAtTime)
    local weatherType = 0
    if environment.weather.getCurrentWeatherType then
        weatherType = environment.weather:getCurrentWeatherType()
    elseif environment.weather.currentWeatherType then
        weatherType = environment.weather.currentWeatherType
    end

    return NegotiationDialog.WEATHER_MODIFIERS[weatherType] or 0
end

--[[
    Get weather whisper text
    @param favorable - true if good negotiating weather, false if bad
]]
function NegotiationDialog:getWeatherWhisperText(favorable)
    if favorable then
        -- Pick based on current weather
        local environment = g_currentMission.environment
        local weatherType = 0
        if environment and environment.weather then
            if environment.weather.getCurrentWeatherType then
                weatherType = environment.weather:getCurrentWeatherType()
            elseif environment.weather.currentWeatherType then
                weatherType = environment.weather.currentWeatherType
            end
        end

        -- Map weather type to whisper key
        local whisperKeys = {
            [2] = "usedplus_whisper_weather_rain",
            [3] = "usedplus_whisper_weather_storm",
            [4] = "usedplus_whisper_weather_hail",
            [5] = "usedplus_whisper_weather_snow",
        }
        local key = whisperKeys[weatherType] or "usedplus_whisper_weather_storm"
        local text = g_i18n:getText(key)
        if text == key then
            text = "Plus, with this weather, they might want to close quick."
        end
        return text
    else
        local text = g_i18n:getText("usedplus_whisper_weather_perfect")
        if text == "usedplus_whisper_weather_perfect" then
            text = "Beautiful day like this though... don't expect any favors."
        end
        return text
    end
end

--[[
    Update offer display based on selected percentage
]]
function NegotiationDialog:updateOfferDisplay()
    UsedPlus.logDebug(string.format("updateOfferDisplay: askingPrice=%s, selectedPercent=%s",
        tostring(self.askingPrice), tostring(self.selectedPercent)))

    -- v2.9.1: At 100%, use exact asking price (no rounding) to avoid false "savings"
    if self.selectedPercent >= 100 then
        self.offerAmount = self.askingPrice
    else
        self.offerAmount = math.floor(self.askingPrice * (self.selectedPercent / 100))
        -- Round to nearest $100 only for discounted offers
        self.offerAmount = math.floor(self.offerAmount / 100) * 100
    end

    UsedPlus.logDebug(string.format("updateOfferDisplay: calculated offerAmount=%s, offerAmountText=%s",
        tostring(self.offerAmount), tostring(self.offerAmountText ~= nil)))

    if self.offerAmountText then
        self.offerAmountText:setText(g_i18n:formatMoney(self.offerAmount, 0, true, true))
    else
        UsedPlus.logWarn("updateOfferDisplay: offerAmountText element is nil!")
    end

    -- Savings display
    -- Note: At 100%, always show "Full price" regardless of rounding effects
    if self.savingsText then
        if self.selectedPercent >= 100 then
            self.savingsText:setText("Full price")
        else
            local savings = self.askingPrice - self.offerAmount
            local savingsPercent = 100 - self.selectedPercent
            self.savingsText:setText(string.format("%s (%d%% off)",
                g_i18n:formatMoney(savings, 0, true, true), savingsPercent))
        end
    end

    -- Update button highlights
    self:updateButtonHighlights()
end

--[[
    Update button visual states to show selected percentage
    Uses background color change pattern (3-layer buttons)
]]
function NegotiationDialog:updateButtonHighlights()
    local buttons = {
        {bg = self.btn70Bg, text = self.btn70Text, percent = 70},
        {bg = self.btn80Bg, text = self.btn80Text, percent = 80},
        {bg = self.btn85Bg, text = self.btn85Text, percent = 85},
        {bg = self.btn90Bg, text = self.btn90Text, percent = 90},
        {bg = self.btn95Bg, text = self.btn95Text, percent = 95},
        {bg = self.btn100Bg, text = self.btn100Text, percent = 100},
    }

    -- Colors for button states
    local selectedColor = {0.15, 0.35, 0.20, 1}  -- Green highlight
    local normalColor = {0.15, 0.15, 0.18, 1}    -- Dark gray
    local fullPriceColor = {0.18, 0.15, 0.12, 1} -- Slightly warm gray for 100%

    for _, btn in ipairs(buttons) do
        if btn.bg then
            local isSelected = (btn.percent == self.selectedPercent)

            if isSelected then
                -- Selected state - green highlight
                btn.bg:setImageColor(selectedColor[1], selectedColor[2], selectedColor[3], selectedColor[4])
            elseif btn.percent == 100 then
                -- 100% has special color
                btn.bg:setImageColor(fullPriceColor[1], fullPriceColor[2], fullPriceColor[3], fullPriceColor[4])
            else
                -- Normal state
                btn.bg:setImageColor(normalColor[1], normalColor[2], normalColor[3], normalColor[4])
            end

            -- Update text color (brighter when selected)
            if btn.text then
                if isSelected then
                    btn.text:setTextColor(0.4, 1, 0.6, 1)  -- Bright green text
                else
                    btn.text:setTextColor(1, 1, 1, 1)  -- White text
                end
            end
        end
    end
end

--[[
    Offer button click handlers
]]
function NegotiationDialog:onClickOffer70()
    self.selectedPercent = 70
    self:updateOfferDisplay()
end

function NegotiationDialog:onClickOffer80()
    self.selectedPercent = 80
    self:updateOfferDisplay()
end

function NegotiationDialog:onClickOffer85()
    self.selectedPercent = 85
    self:updateOfferDisplay()
end

function NegotiationDialog:onClickOffer90()
    self.selectedPercent = 90
    self:updateOfferDisplay()
end

function NegotiationDialog:onClickOffer95()
    self.selectedPercent = 95
    self:updateOfferDisplay()
end

function NegotiationDialog:onClickOffer100()
    self.selectedPercent = 100
    self:updateOfferDisplay()
end

--[[
    Calculate seller response to offer
    v2.6.1: Graduated rejection risk - lowballing now has real consequences!

    Response logic based on gap below threshold:
    - 0-5% gap: Always counter (safe negotiation)
    - 5-10% gap: Usually counter, 0-30% reject chance (low risk)
    - 10-15% gap: 50/50 counter vs reject (medium risk)
    - 15-20% gap: Usually reject, 0-30% counter chance (high risk)
    - >20% gap: Always reject - seller is insulted! (extreme risk)

    Personality toleranceBonus adjusts the perceived gap:
    Personalities (v2.6.2 DNA-DRIVEN):
    - Desperate (DNA 0.00-0.20): +15% tolerance, 5% walk-away chance
    - Motivated (DNA 0.20-0.40): +8% tolerance, 15% walk-away chance
    - Reasonable (DNA 0.40-0.60): 0% tolerance, 35% walk-away chance
    - Firm (DNA 0.60-0.80): -5% tolerance, 60% walk-away chance
    - Immovable (DNA 0.80-1.00): -15% tolerance, 90% walk-away chance, WON'T NEGOTIATE

    Weather still modifies seller willingness (rainy day = seller more eager to close deal)

    @return "accept", "counter", "reject", or "walkaway" plus amount
    "walkaway" = permanent loss of listing (seller insulted)
]]
function NegotiationDialog:calculateSellerResponse()
    local listing = self.listing
    if listing == nil then
        return "accept", self.offerAmount
    end

    -- Get seller personality config (NOW DNA-DRIVEN)
    local personality = UsedVehicleSearch.getSellerPersonalityConfig(listing.sellerPersonality)
    local baseThreshold = personality.acceptThreshold
    local toleranceBonus = personality.toleranceBonus or 0
    local walkAwayChance = personality.walkAwayChance or 0.35

    -- IMMOVABLE SELLERS (workhorses): Special handling
    -- They KNOW they have gold and won't budge
    local isImmovable = listing.sellerPersonality == "immovable"
    if isImmovable then
        local offerPercent = self.selectedPercent / 100
        -- Immovable sellers only accept offers at 98%+ of asking
        if offerPercent >= 0.98 then
            UsedPlus.logDebug("Immovable seller: ACCEPT at 98%+")
            return "accept", self.offerAmount
        else
            -- Any lowball on a workhorse = high risk of permanent walk-away
            math.random()
            local roll = math.random()
            local gap = 0.98 - offerPercent

            UsedPlus.logDebug(string.format(
                "Immovable seller: offer=%.0f%%, gap=%.2f, walkAwayChance=%.2f, roll=%.2f",
                offerPercent * 100, gap, walkAwayChance, roll))

            -- Even tiny lowballs (96-98%) have high walk-away chance
            if roll < walkAwayChance then
                UsedPlus.logDebug("Immovable seller: WALKAWAY - insulted, listing permanently lost")
                return "walkaway", self.askingPrice
            else
                -- They don't counter - they just reject and hold firm
                UsedPlus.logDebug("Immovable seller: REJECT (but willing to wait for full price)")
                return "reject", self.askingPrice
            end
        end
    end

    -- Apply situation modifiers (make seller more willing to deal)
    local modifier = 0

    -- Days on market modifier (+0.3% per day, max +10%)
    local daysOnMarket = listing.daysOnMarket or 0
    modifier = modifier + math.min(daysOnMarket * 0.003, 0.10)

    -- Damage modifier (+5% if damage > 20%)
    if (listing.damage or 0) > 0.20 then
        modifier = modifier + 0.05
    end

    -- Hours modifier (+3% if hours > 5000)
    if (listing.operatingHours or 0) > 5000 then
        modifier = modifier + 0.03
    end

    -- Premium vehicle modifier (-5% if expensive)
    if (listing.basePrice or 0) > 200000 then
        modifier = modifier - 0.05
    end

    -- Weather modifier (preserved from v2.6.0 design)
    local weatherMod = self:getWeatherModifier()
    modifier = modifier + weatherMod

    -- Effective threshold (lower = easier to negotiate)
    local effectiveThreshold = baseThreshold - modifier
    local offerPercent = self.selectedPercent / 100

    -- Calculate raw gap (how far below threshold is the offer)
    local rawGap = effectiveThreshold - offerPercent

    -- Apply personality tolerance (adjusts perceived insult level)
    local adjustedGap = rawGap - toleranceBonus

    UsedPlus.logDebug(string.format(
        "Negotiation calc: personality=%s, base=%.2f, weatherMod=%.2f, mod=%.2f, effective=%.2f",
        listing.sellerPersonality, baseThreshold, weatherMod, modifier, effectiveThreshold))
    UsedPlus.logDebug(string.format(
        "  offer=%.2f, rawGap=%.2f, tolerance=%.2f, adjustedGap=%.2f, walkAwayChance=%.2f",
        offerPercent, rawGap, toleranceBonus, adjustedGap, walkAwayChance))

    -- Calculate counter offer amount (used if we counter)
    local counterPercent = personality.counterThreshold
    local counterAmount = math.floor(self.askingPrice * counterPercent)
    counterAmount = math.floor(counterAmount / 100) * 100

    -- DECISION LOGIC: Graduated rejection risk with permanent walk-away
    math.random()  -- Dry run for better randomness
    local roll = math.random()

    -- Offer meets or exceeds threshold - ACCEPT
    if adjustedGap <= 0 then
        UsedPlus.logDebug("Response: ACCEPT (offer meets threshold)")
        return "accept", self.offerAmount
    end

    -- Close offer (within 5%) - always counter, this is reasonable negotiation
    if adjustedGap <= 0.05 then
        UsedPlus.logDebug("Response: COUNTER (close offer, within 5%)")
        return "counter", counterAmount
    end

    -- Moderate lowball (5-10% below) - counter or reject
    if adjustedGap <= 0.10 then
        local rejectChance = (adjustedGap - 0.05) * 6  -- 0% at 5%, 30% at 10%
        UsedPlus.logDebug(string.format("Moderate lowball: rejectChance=%.2f, roll=%.2f", rejectChance, roll))
        if roll < rejectChance then
            UsedPlus.logDebug("Response: REJECT (moderate lowball)")
            return "reject", self.askingPrice
        end
        UsedPlus.logDebug("Response: COUNTER (moderate lowball)")
        return "counter", counterAmount
    end

    -- Significant lowball (10-15% below) - 50/50 chance, small walk-away risk
    if adjustedGap <= 0.15 then
        local walkChance = walkAwayChance * 0.3  -- 30% of base walk-away chance
        UsedPlus.logDebug(string.format("Significant lowball: 50/50, walkChance=%.2f, roll=%.2f", walkChance, roll))

        if roll < walkChance then
            UsedPlus.logDebug("Response: WALKAWAY (significant lowball, seller insulted)")
            return "walkaway", self.askingPrice
        elseif roll < 0.50 then
            UsedPlus.logDebug("Response: REJECT (significant lowball)")
            return "reject", self.askingPrice
        end
        UsedPlus.logDebug("Response: COUNTER (significant lowball, seller gave benefit of doubt)")
        return "counter", counterAmount
    end

    -- Aggressive lowball (15-20% below) - usually reject, risk of walk-away
    if adjustedGap <= 0.20 then
        local walkChance = walkAwayChance * 0.6  -- 60% of base walk-away chance
        local counterChance = (0.20 - adjustedGap) * 6  -- 30% at 15%, 0% at 20%
        UsedPlus.logDebug(string.format("Aggressive lowball: walkChance=%.2f, counterChance=%.2f, roll=%.2f",
            walkChance, counterChance, roll))

        if roll < walkChance then
            UsedPlus.logDebug("Response: WALKAWAY (aggressive lowball, seller insulted)")
            return "walkaway", self.askingPrice
        elseif roll < walkChance + counterChance then
            UsedPlus.logDebug("Response: COUNTER (aggressive lowball, seller very desperate)")
            return "counter", counterAmount
        end
        UsedPlus.logDebug("Response: REJECT (aggressive lowball)")
        return "reject", self.askingPrice
    end

    -- Insulting offer (>20% below threshold) - high walk-away risk
    local walkChance = walkAwayChance  -- Full walk-away chance
    UsedPlus.logDebug(string.format("Insulting offer (gap=%.2f): walkChance=%.2f, roll=%.2f", adjustedGap, walkChance, roll))

    if roll < walkChance then
        UsedPlus.logDebug("Response: WALKAWAY (insulting offer, seller walked away permanently)")
        return "walkaway", self.askingPrice
    end

    UsedPlus.logDebug("Response: REJECT (insulting offer, but seller patient)")
    return "reject", self.askingPrice
end

--[[
    Check if player can afford an amount (cash only)
    @param amount - The amount to check
    @return boolean, string - canAfford, errorMessage
]]
function NegotiationDialog:canAffordAmount(amount)
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
        return false, string.format("You need %s more to afford this offer.\nCurrent balance: %s",
            g_i18n:formatMoney(shortfall, 0, true, true),
            g_i18n:formatMoney(currentMoney, 0, true, true))
    end
end

--[[
    Send Offer button click
]]
function NegotiationDialog:onClickSendOffer()
    UsedPlus.logDebug("NegotiationDialog:onClickSendOffer() CALLED")

    -- Validate player can afford their offer (used vehicles are cash only!)
    local canAfford, errorMsg = self:canAffordAmount(self.offerAmount)
    if not canAfford then
        InfoDialog.show(errorMsg or "You cannot afford this offer.")
        return
    end

    -- Track statistics
    local farmId = g_currentMission and g_currentMission.player and g_currentMission.player.farmId or 1
    if FinanceManager and FinanceManager.getInstance then
        local fm = FinanceManager.getInstance()
        if fm then
            fm:incrementStatistic(farmId, "negotiationsAttempted", 1)
        end
    end

    -- Calculate seller response
    local response, responseAmount = self:calculateSellerResponse()

    UsedPlus.logDebug(string.format("Offer sent: $%d (%d%%) - Response: %s ($%d)",
        self.offerAmount, self.selectedPercent, response, responseAmount))

    -- v2.6.2: Handle WALKAWAY - permanent loss of listing
    -- v2.8.0: Fixed - notify parent dialog to close/refresh, preventing double-offer exploit
    if response == "walkaway" then
        UsedPlus.logDebug("SELLER WALKAWAY - removing listing permanently")

        -- v2.9.1: Cache ALL values BEFORE any operations that might clear them
        local callback = self.onOfferCallback
        local callbackTarget = self.callbackTarget
        local listing = self.listing
        local search = self.search

        -- Remove listing from search (permanent loss) - pass cached values
        self:removeListingPermanentlyWithData(listing, search)

        -- Track walkaway statistic
        if FinanceManager and FinanceManager.getInstance then
            local fm = FinanceManager.getInstance()
            if fm then
                fm:incrementStatistic(farmId, "negotiationsWalkaway", 1)
            end
        end

        -- v2.8.0: Close ALL related dialogs to prevent any offer attempts
        -- Close in reverse order of opening: NegotiationDialog -> any parent dialogs
        g_gui:closeDialogByName("NegotiationDialog")
        g_gui:closeDialogByName("InspectionReportDialog")
        g_gui:closeDialogByName("UsedVehiclePreviewDialog")
        g_gui:closeDialogByName("VehiclePortfolioDialog")

        UsedPlus.logDebug("Walkaway: Closed all related dialogs")

        -- v2.8.0: Notify parent dialog with "walkaway" result so it closes/disables Make Offer
        -- This prevents the exploit where player could make another offer from the parent dialog
        if callback then
            local success, err = pcall(function()
                if callbackTarget then
                    callback(callbackTarget, "walkaway", listing)
                else
                    callback("walkaway", listing)
                end
            end)
            if not success then
                UsedPlus.logDebug("Walkaway callback error (non-critical): " .. tostring(err))
            end
        end

        -- Show special walkaway dialog
        InfoDialog.show(
            g_i18n:getText("usedplus_walkaway_message") or "Your offer insulted the seller. They've refused to do business with you and this vehicle is no longer available."
        )
        return
    end

    -- Cache values before closing (dialog state may be cleared)
    local listing = self.listing
    local search = self.search
    local offerAmount = self.offerAmount
    local askingPrice = self.askingPrice
    local onOfferCallback = self.onOfferCallback
    local callbackTarget = self.callbackTarget

    -- Close this dialog
    self:close()

    -- v2.11.0: Defer SellerResponseDialog open to next frame to ensure NegotiationDialog closes first
    -- This prevents dialog stacking where both dialogs are visible at once
    g_currentMission:addUpdateable({
        update = function(self, dt)
            g_currentMission:removeUpdateable(self)
            DialogLoader.show("SellerResponseDialog", "setData",
                listing,
                search,
                response,
                offerAmount,
                responseAmount,
                askingPrice,
                onOfferCallback,
                callbackTarget
            )
        end
    })
end

--[[
    v2.6.2: Remove listing permanently from search
    Called when seller walks away insulted
    v2.9.1: Now takes explicit parameters to avoid nil reference issues
]]
function NegotiationDialog:removeListingPermanently()
    -- Delegate to parameterized version
    self:removeListingPermanentlyWithData(self.listing, self.search)
end

--[[
    v2.9.1: Remove listing permanently with explicit data parameters
    This version takes the listing and search as parameters to avoid nil reference issues
    when dialog state is cleared during close operations
]]
function NegotiationDialog:removeListingPermanentlyWithData(listing, search)
    if not listing or not search then
        UsedPlus.logWarn("removeListingPermanentlyWithData: missing listing or search")
        return
    end

    local listingId = listing.id
    local searchId = search.id

    UsedPlus.logDebug(string.format("Permanently removing listing %s from search %s", listingId, searchId))

    -- Method 1: Try to remove via search object
    if search.removeFoundListing then
        local removed = search:removeFoundListing(listingId)
        if removed then
            UsedPlus.logDebug("Listing removed via search:removeFoundListing()")
            return
        end
    end

    -- Method 2: Try to remove via manager
    if UsedVehicleManager and UsedVehicleManager.getInstance then
        local uvm = UsedVehicleManager.getInstance()
        if uvm then
            -- Find the search in manager and remove the listing
            local managerSearch = uvm:getSearchById(searchId)
            if managerSearch and managerSearch.removeFoundListing then
                local removed = managerSearch:removeFoundListing(listingId)
                if removed then
                    UsedPlus.logDebug("Listing removed via UsedVehicleManager search")
                    return
                end
            end

            -- Also try direct listing removal if manager supports it
            if uvm.removeListing then
                uvm:removeListing(listingId)
                UsedPlus.logDebug("Listing removed via UsedVehicleManager:removeListing()")
                return
            end
        end
    end

    -- Method 3: Mark listing as unavailable (fallback)
    listing.status = "seller_walked_away"
    listing.negotiationLocked = true
    listing.negotiationLockExpires = math.huge  -- Never expires
    UsedPlus.logDebug("Listing marked as seller_walked_away (fallback)")
end

--[[
    Cancel button click
    v2.11.0: Added debouncing to prevent multi-fire
]]
function NegotiationDialog:onClickCancel()
    UsedPlus.logDebug("NegotiationDialog:onClickCancel() CALLED")

    -- Prevent double-clicks
    if self.isClosing then
        UsedPlus.logDebug("NegotiationDialog:onClickCancel() - already closing, ignoring")
        return
    end
    self.isClosing = true

    self:close()
end

--[[
    Close the dialog
]]
function NegotiationDialog:close()
    g_gui:closeDialog(self)
end

UsedPlus.logInfo("NegotiationDialog loaded (v2.9.5)")
