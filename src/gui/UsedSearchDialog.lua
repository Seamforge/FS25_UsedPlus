--[[
    FS25_UsedPlus - Used Search Dialog

     GUI class for used equipment search tier selection
     Pattern from: Game's mission dialogs with option selection
     Reference: FS25_ADVANCED_PATTERNS.md - GUI Dialog Pattern

    Responsibilities:
    - Display store item being searched
    - Show 3 search tier options (Local/National/International)
    - Display tier comparison (cost, duration, success%, match%)
    - Allow single tier selection via checkbox/radio buttons
    - Send RequestUsedItemEvent on "Start Search"

    Search Tiers (REBALANCED to fix Local loophole):
    - Local: 4% cost, 0-1 months, 25% success, 25% match (quick but low odds)
    - Regional: 6% cost, 1-2 months, 55% success, 50% match (best value)
    - National: 10% cost, 2-4 months, 80% success, 70% match (high certainty)
]]

UsedSearchDialog = {}
local UsedSearchDialog_mt = Class(UsedSearchDialog, MessageDialog)

--[[
     Constructor
]]
function UsedSearchDialog.new(target, customMt, i18n)
    local self = MessageDialog.new(target, customMt or UsedSearchDialog_mt)

    -- Controls are automatically mapped by g_gui:loadGui() based on XML id attributes
    -- Available controls after loadGui:
    --   self.itemImage, self.itemNameText, self.itemPriceText
    --   self.localCheckbox, self.localCostText, self.localDurationText, self.localSuccessText, self.localMatchText
    --   self.regionalCheckbox, self.regionalCostText, self.regionalDurationText, self.regionalSuccessText, self.regionalMatchText
    --   self.nationalCheckbox, self.nationalCostText, self.nationalDurationText, self.nationalSuccessText, self.nationalMatchText

    self.storeItem = nil
    self.storeItemIndex = nil
    self.basePrice = 0
    self.farmId = nil
    self.selectedTier = 1  -- Default: Local (1=Local, 2=Regional, 3=National)
    self.selectedQuality = 1  -- Default: Any Condition (1=Any, 2=Poor, 3=Fair, 4=Good, 5=Excellent)
    self.i18n = i18n

    return self
end

--[[
     Called when dialog is created (required by GUI system)
     v2.9.5: Sets up section header icons
]]
function UsedSearchDialog:onCreate()
    UsedSearchDialog:superClass().onCreate(self)

    -- Store icon directory
    self.iconDir = UsedPlus.MOD_DIR .. "gui/icons/"
end

--[[
     Called after GUI element binding is complete (required by GUI system)
     Button onClick handlers are only wired after this callback
]]
function UsedSearchDialog:onGuiSetupFinished()
    UsedSearchDialog:superClass().onGuiSetupFinished(self)

    -- v2.9.5: Setup icons (element refs only valid after setup finished)
    self:setupSectionIcons()

    -- Diagnostic: confirm setup ran and check button state
    UsedPlus.logDebug(string.format("UsedSearchDialog:onGuiSetupFinished - startSearchButton=%s, cancelButton=%s",
        tostring(self.startSearchButton ~= nil),
        tostring(self.cancelButton ~= nil)))

    -- Belt-and-suspenders: manually wire button callbacks via onClickCallback
    -- XML onClick should handle this, but if it doesn't, this catches it
    if self.startSearchButton then
        local dialogSelf = self  -- capture ref for closure
        self.startSearchButton.onClickCallback = function()
            UsedPlus.logDebug("startSearchButton.onClickCallback fired (manual wiring)")
            UsedPlus.logDebug(string.format("  self type=%s, storeItem=%s, selectedTier=%s",
                tostring(type(dialogSelf)), tostring(dialogSelf.storeItem ~= nil), tostring(dialogSelf.selectedTier)))
            local ok, err = pcall(function()
                dialogSelf:onStartSearch()
            end)
            if not ok then
                UsedPlus.logError("onStartSearch CRASHED: " .. tostring(err))
            else
                UsedPlus.logDebug("onStartSearch completed without error")
            end
        end
    end
    if self.cancelButton then
        self.cancelButton.onClickCallback = function()
            UsedPlus.logDebug("cancelButton.onClickCallback fired (manual wiring)")
            self:onCancel()
        end
    end

    -- Also try binding via dialogElement:getDescendantByName if self refs are nil
    if not self.startSearchButton and self.dialogElement then
        local btn = self.dialogElement:getDescendantByName("startSearchButton")
        if btn then
            UsedPlus.logDebug("Found startSearchButton via getDescendantByName")
            self.startSearchButton = btn
            btn.onClickCallback = function()
                UsedPlus.logDebug("startSearchButton.onClickCallback fired (descendant wiring)")
                self:onStartSearch()
            end
        else
            UsedPlus.logWarn("startSearchButton NOT found via getDescendantByName either!")
        end
    end
end

--[[
    Setup section header icons
    Icons are set via Lua because XML paths don't work from ZIP mods
    Large input dialogs use section icons only (no header icon)
]]
function UsedSearchDialog:setupSectionIcons()
    if self.iconDir == nil then
        return
    end

    -- Vehicle section - vehicle icon
    if self.vehicleSectionIcon ~= nil then
        self.vehicleSectionIcon:setImageFilename(self.iconDir .. "vehicle.dds")
    end

    -- Tier section - agent icon
    if self.tierSectionIcon ~= nil then
        self.tierSectionIcon:setImageFilename(self.iconDir .. "agent.dds")
    end

    -- Quality section - quality star icon
    if self.qualitySectionIcon ~= nil then
        self.qualitySectionIcon:setImageFilename(self.iconDir .. "quality_star.dds")
    end
end

--[[
    Quality tier definitions with RANGES (v1.4.0 - ECONOMICS.md compliance)
    Lower quality = lower price, but needs repairs
    Array order: 1=Any, 2=Poor, 3=Fair, 4=Good, 5=Excellent
    Display order (leftmost to rightmost): Any, Poor, Fair, Good, Excellent
    successModifier affects the base success rate from search tier

    Must match DepreciationCalculations.QUALITY_TIERS!
]]
UsedSearchDialog.QUALITY_TIERS = {
    {  -- Any Condition: Catch-all with widest variance
        name = "Any Condition",
        nameKey = "usedplus_quality_any",
        priceRangeMin = 0.30,            -- 30% of new (70% off)
        priceRangeMax = 0.50,            -- 50% of new (50% off)
        damageRange = { 0.35, 0.60 },    -- 35-60% damage
        wearRange = { 0.40, 0.65 },      -- 40-65% wear
        successModifier = 0.08,          -- +8% easier to find rough equipment
        description = "Wildcard - high variance in quality and price",
        descriptionKey = "usedplus_quality_anyDesc"
    },
    {  -- Poor Condition: Fixer-upper - highest repair costs
        name = "Poor Condition",
        nameKey = "usedplus_quality_poor",
        priceRangeMin = 0.22,            -- 22% of new (78% off)
        priceRangeMax = 0.38,            -- 38% of new (62% off)
        damageRange = { 0.55, 0.80 },    -- 55-80% damage
        wearRange = { 0.60, 0.85 },      -- 60-85% wear
        successModifier = 0.15,          -- +15% easier to find junk
        description = "Bargain bin - extensive repairs needed",
        descriptionKey = "usedplus_quality_poorDesc"
    },
    {  -- Fair Condition: Middle ground
        name = "Fair Condition",
        nameKey = "usedplus_quality_fair",
        priceRangeMin = 0.50,            -- 50% of new (50% off)
        priceRangeMax = 0.68,            -- 68% of new (32% off)
        damageRange = { 0.18, 0.35 },    -- 18-35% damage
        wearRange = { 0.22, 0.40 },      -- 22-40% wear
        successModifier = 0.00,          -- Baseline (no modifier)
        description = "Moderate wear - some repairs likely",
        descriptionKey = "usedplus_quality_fairDesc"
    },
    {  -- Good Condition: Well maintained
        name = "Good Condition",
        nameKey = "usedplus_quality_good",
        priceRangeMin = 0.68,            -- 68% of new (32% off)
        priceRangeMax = 0.80,            -- 80% of new (20% off)
        damageRange = { 0.06, 0.18 },    -- 6-18% damage
        wearRange = { 0.08, 0.22 },      -- 8-22% wear
        successModifier = -0.08,         -- -8% harder to find well-maintained
        description = "Well maintained - minimal repairs",
        descriptionKey = "usedplus_quality_goodDesc"
    },
    {  -- Excellent Condition: Like new
        name = "Excellent Condition",
        nameKey = "usedplus_quality_excellent",
        priceRangeMin = 0.80,            -- 80% of new (20% off)
        priceRangeMax = 0.94,            -- 94% of new (6% off)
        damageRange = { 0.00, 0.06 },    -- 0-6% damage
        wearRange = { 0.00, 0.08 },      -- 0-8% wear
        successModifier = -0.15,         -- -15% harder to find pristine
        description = "Like new - ready to work immediately",
        descriptionKey = "usedplus_quality_excellentDesc"
    }
}

--[[
     Credit score modifiers for agent fees
     Better credit = cheaper agent services (they trust you more)
]]
UsedSearchDialog.CREDIT_FEE_MODIFIERS = {
    {minScore = 750, modifier = -0.15, name = "Excellent", nameKey = "usedplus_creditRating_excellent"},  -- 15% discount
    {minScore = 700, modifier = -0.08, name = "Good",      nameKey = "usedplus_creditRating_good"},       -- 8% discount
    {minScore = 650, modifier = 0.00,  name = "Fair",      nameKey = "usedplus_creditRating_fair"},       -- No change
    {minScore = 600, modifier = 0.10,  name = "Poor",      nameKey = "usedplus_creditRating_poor"},       -- 10% surcharge
    {minScore = 300, modifier = 0.20,  name = "Very Poor", nameKey = "usedplus_creditRating_veryPoor"}   -- 20% surcharge
}

--[[
     Get credit score fee modifier based on player's credit
     @return modifier (negative = discount, positive = surcharge)
]]
function UsedSearchDialog:getCreditFeeModifier()
    -- Check if credit system is enabled
    if UsedPlusSettings and UsedPlusSettings.get then
        if UsedPlusSettings:get("enableCreditSystem") == false then
            return 0  -- No modifier when credit system disabled
        end
    end

    local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
    if not farm or not CreditScore then
        return 0
    end

    local score = CreditScore.calculate(farm.farmId)
    for _, tier in ipairs(UsedSearchDialog.CREDIT_FEE_MODIFIERS) do
        if score >= tier.minScore then
            return tier.modifier
        end
    end
    return 0.20  -- Default to worst tier
end

--[[
     Calculate adjusted success rate based on tier and quality
     @param tierSuccessRate - Base success rate from search tier (0.0-1.0)
     @param qualityIndex - Selected quality tier index (1-5)
     @return adjusted success rate (clamped to 0.05-0.95)
]]
function UsedSearchDialog:getAdjustedSuccessRate(tierSuccessRate, qualityIndex)
    local quality = UsedSearchDialog.QUALITY_TIERS[qualityIndex]
    if not quality then
        return tierSuccessRate
    end

    local adjusted = tierSuccessRate + (quality.successModifier or 0)
    -- Clamp to reasonable bounds (5% minimum, 95% maximum)
    return math.max(0.05, math.min(0.95, adjusted))
end

--[[
     Called when dialog opens (required by GUI system)
]]
function UsedSearchDialog:onOpen()
    UsedSearchDialog:superClass().onOpen(self)

    -- Set default selections
    self:selectTier(1)
    self:selectQuality(1)  -- Default to "Any Condition" (index 1, Poor is index 2)
end

--[[
     Initialize dialog with item data
]]
function UsedSearchDialog:setData(storeItem, storeItemIndex, farmId)
    self.storeItem = storeItem
    self.storeItemIndex = storeItemIndex
    self.farmId = farmId

    self.basePrice = StoreItemUtil.getDefaultPrice(storeItem, {})

    -- Get vehicle name using consolidated utility
    self.vehicleName = UIHelper.Vehicle.getFullName(storeItem)

    -- Populate item details
    if self.itemNameText then
        self.itemNameText:setText(self.vehicleName)
    end

    if self.itemPriceText then
        self.itemPriceText:setText(string.format("%s %s", g_i18n:getText("usedplus_search_newPrice"), UIHelper.Text.formatMoney(self.basePrice)))
    end

    -- Set category text (human-readable) - category only, no brand (brand is in name now)
    if self.itemCategoryText then
        local categoryText = ""

        -- Use categoryName (not category - that's nil!)
        local categoryKey = storeItem.categoryName or storeItem.category
        UsedPlus.logTrace(string.format("Category key: %s", tostring(categoryKey)))

        -- Get human-readable category name
        if categoryKey then
            local category = g_storeManager:getCategoryByName(categoryKey)
            if category then
                UsedPlus.logTrace("  Category object found")
                if category.title then
                    -- category.title might be plain text or l10n key
                    if type(category.title) == "string" and category.title:sub(1, 1) == "$" then
                        -- It's a translation key, translate it
                        categoryText = g_i18n:getText(category.title:sub(2))
                    else
                        -- It's already translated text, use as-is
                        categoryText = category.title
                    end
                    UsedPlus.logTrace(string.format("  Category title: %s", categoryText))
                else
                    categoryText = categoryKey
                end
            else
                UsedPlus.logTrace("  Category object NOT found, using raw key")
                categoryText = categoryKey
            end
        end

        UsedPlus.logTrace(string.format("Final category text: '%s'", categoryText))
        self.itemCategoryText:setText(categoryText)
        self.itemCategoryText:setVisible(true)
    else
        UsedPlus.logWarn("itemCategoryText element not found!")
    end

    -- Set item image - XML profile handles aspect ratio via imageSliceId="noSlice"
    if self.itemImage then
        UIHelper.Image.set(self.itemImage, storeItem)
    end

    -- Define search tier data (matches UsedVehicleSearch.SEARCH_TIERS)
    -- v1.5.0: Multi-find agent model with retainer + commission
    -- Store as instance variable so we can recalculate on quality change
    self.SEARCH_TIERS = {
        {  -- Local Search: Quick, cheap, low odds
            name = "Local Search",
            nameKey = "usedplus_searchTier_local",
            retainerFlat = 500,           -- $500 flat retainer
            retainerPercent = 0,          -- No percentage
            commissionPercent = 0.06,     -- 6% added to vehicle price
            maxMonths = 1,                -- 1 month only
            monthlySuccessChance = 0.30,  -- 30% each month
            matchChance = 0.25,           -- 25% per configuration
            maxListings = 3               -- Cap at 3 finds
        },
        {  -- Regional Search: Balanced, best value
            name = "Regional Search",
            nameKey = "usedplus_searchTier_regional",
            retainerFlat = 1000,          -- $1000 base
            retainerPercent = 0.005,      -- Plus 0.5% of vehicle price
            commissionPercent = 0.08,     -- 8% commission
            maxMonths = 3,                -- Up to 3 months
            monthlySuccessChance = 0.55,  -- 55% each month
            matchChance = 0.50,           -- 50% per configuration
            maxListings = 6               -- Cap at 6 finds
        },
        {  -- National Search: Premium, high certainty
            name = "National Search",
            nameKey = "usedplus_searchTier_national",
            retainerFlat = 2000,          -- $2000 base
            retainerPercent = 0.008,      -- Plus 0.8% of vehicle price
            commissionPercent = 0.10,     -- 10% commission
            maxMonths = 6,                -- Up to 6 months
            monthlySuccessChance = 0.85,  -- 85% each month
            matchChance = 0.70,           -- 70% per configuration
            maxListings = 10,             -- Cap at 10 finds
            guaranteedMinimum = 1         -- At least 1 find guaranteed
        }
    }

    -- Get credit fee modifier (better credit = cheaper agents)
    local creditFeeModifier = self:getCreditFeeModifier()
    self.creditFeeModifier = creditFeeModifier  -- Store for later use

    -- v1.5.0: Multi-find agent model
    -- Populate tier displays using UIHelper (with credit-adjusted retainer fees)
    for i, tier in ipairs(self.SEARCH_TIERS) do
        -- Calculate retainer fee: flat + percentage of vehicle price
        local baseRetainer = tier.retainerFlat + math.floor(self.basePrice * tier.retainerPercent)
        -- Apply credit modifier to retainer (better credit = cheaper agents)
        local adjustedRetainer = math.floor(baseRetainer * (1 + creditFeeModifier))

        -- Duration text (just maxMonths now, no minMonths)
        local durationText
        if tier.maxMonths == 1 then
            durationText = g_i18n:getText("usedplus_time_1month")
        else
            durationText = string.format(g_i18n:getText("usedplus_time_months"), tier.maxMonths)
        end

        -- Show monthly success chance (will be modified by quality selection)
        local successText = UIHelper.Text.formatPercent(tier.monthlySuccessChance, true, 0) .. "/mo"
        local matchText = UIHelper.Text.formatPercent(tier.matchChance, true, 0)

        local prefix = ({"local", "regional", "national"})[i]

        -- Cost now shows retainer + commission info
        -- Format: "$1,500 + 8%"  (retainer + commission)
        local costText = string.format("%s + %d%%",
            UIHelper.Text.formatMoney(adjustedRetainer),
            math.floor(tier.commissionPercent * 100))
        UIHelper.Element.setText(self[prefix .. "CostText"], costText)
        UIHelper.Element.setText(self[prefix .. "DurationText"], durationText)
        UIHelper.Element.setText(self[prefix .. "SuccessText"], successText)
        UIHelper.Element.setText(self[prefix .. "MatchText"], matchText)

        -- Show credit discount/surcharge indicator if not neutral
        if creditFeeModifier ~= 0 then
            local discountText = creditFeeModifier < 0
                and string.format(" (-%d%% credit)", math.abs(creditFeeModifier * 100))
                or string.format(" (+%d%% credit)", creditFeeModifier * 100)
            -- Note: Could add a credit indicator element here if desired
        end
    end

    -- Populate quality tier displays using UIHelper
    -- Order matches QUALITY_TIERS: 1=Any, 2=Poor, 3=Fair, 4=Good, 5=Excellent
    -- Show discount RANGES instead of single values (v1.4.0 - embraces variance)
    local qualityPrefixes = {"anyCondition", "poorCondition", "fairCondition", "goodCondition", "excellentCondition"}
    for i, quality in ipairs(UsedSearchDialog.QUALITY_TIERS) do
        -- Calculate discount range (1 - price range = discount range)
        -- Note: max discount = 1 - min price, min discount = 1 - max price
        local maxDiscount = math.floor((1 - (quality.priceRangeMin or 0.30)) * 100)
        local minDiscount = math.floor((1 - (quality.priceRangeMax or 0.50)) * 100)

        -- Display discount range (e.g., "50-70% off")
        local discountText = string.format("%d-%d%% off", minDiscount, maxDiscount)
        UIHelper.Element.setText(self[qualityPrefixes[i] .. "PriceText"], discountText)
    end

    -- Default selection set in onOpen()
    -- Initial rate update will happen after selectTier and selectQuality
end

--[[
     Update displayed success rates based on current tier and quality selection
     Called when either tier or quality selection changes
     v1.5.0: Now shows monthly success chance with "/mo" suffix
]]
function UsedSearchDialog:updateDisplayedRates()
    if not self.SEARCH_TIERS then
        return
    end

    local selectedQuality = self.selectedQuality or 1  -- Default to Any (index 1)

    -- Update each tier's success rate display with quality modifier applied
    local prefixes = {"local", "regional", "national"}
    for i, tier in ipairs(self.SEARCH_TIERS) do
        -- v1.5.0: Use monthlySuccessChance instead of successChance
        local adjustedSuccess = self:getAdjustedSuccessRate(tier.monthlySuccessChance, selectedQuality)
        local successText = UIHelper.Text.formatPercent(adjustedSuccess, true, 0) .. "/mo"
        -- v2.7.3: Removed modifier indicator (e.g., "+8%") - total % is already shown, modifier was confusing

        UIHelper.Element.setText(self[prefixes[i] .. "SuccessText"], successText)
    end
end

--[[
     Select a search tier (radio button behavior)
     Only one tier can be selected at a time
]]
function UsedSearchDialog:selectTier(tier)
    self.selectedTier = tier

    -- Colors for selected vs unselected (using FS25 standard orange/gold)
    local selectedTextColor = {1, 0.8, 0, 1}         -- Gold text (matches section titles)
    local unselectedTextColor = {0.7, 0.7, 0.7, 1}   -- Gray text
    local selectedBgColor = {1, 0.5, 0, 0.4}         -- FS25 orange highlight (semi-transparent)
    local unselectedBgColor = {0, 0, 0, 0}           -- Transparent background

    -- Update background colors (solid color highlighting)
    if self.localBg then
        self.localBg:setImageColor(nil, unpack(tier == 1 and selectedBgColor or unselectedBgColor))
    end
    if self.regionalBg then
        self.regionalBg:setImageColor(nil, unpack(tier == 2 and selectedBgColor or unselectedBgColor))
    end
    if self.nationalBg then
        self.nationalBg:setImageColor(nil, unpack(tier == 3 and selectedBgColor or unselectedBgColor))
    end

    -- Change name color when selected
    if self.localName then
        self.localName:setTextColor(unpack(tier == 1 and selectedTextColor or unselectedTextColor))
    end
    if self.regionalName then
        self.regionalName:setTextColor(unpack(tier == 2 and selectedTextColor or unselectedTextColor))
    end
    if self.nationalName then
        self.nationalName:setTextColor(unpack(tier == 3 and selectedTextColor or unselectedTextColor))
    end
end

--[[
     Checkbox callbacks (exclusive selection)
]]
function UsedSearchDialog:onLocalSelected()
    self:selectTier(1)
end

function UsedSearchDialog:onRegionalSelected()
    self:selectTier(2)
end

function UsedSearchDialog:onNationalSelected()
    self:selectTier(3)
end

--[[
     Select a quality tier (radio button behavior)
     Only one quality can be selected at a time
     Quality indices: 1=Poor, 2=Any, 3=Fair, 4=Good, 5=Excellent
]]
function UsedSearchDialog:selectQuality(quality)
    self.selectedQuality = quality

    -- Colors for selected vs unselected (using FS25 standard orange/gold)
    local selectedTextColor = {1, 0.8, 0, 1}         -- Gold text (matches section titles)
    local unselectedTextColor = {0.7, 0.7, 0.7, 1}   -- Gray text
    local selectedBgColor = {1, 0.5, 0, 0.4}         -- FS25 orange highlight (semi-transparent)
    local unselectedBgColor = {0, 0, 0, 0}           -- Transparent background

    -- Update background colors (solid color highlighting)
    -- Indices match QUALITY_TIERS: 1=Any, 2=Poor, 3=Fair, 4=Good, 5=Excellent
    if self.anyBg then
        self.anyBg:setImageColor(nil, unpack(quality == 1 and selectedBgColor or unselectedBgColor))
    end
    if self.poorBg then
        self.poorBg:setImageColor(nil, unpack(quality == 2 and selectedBgColor or unselectedBgColor))
    end
    if self.fairBg then
        self.fairBg:setImageColor(nil, unpack(quality == 3 and selectedBgColor or unselectedBgColor))
    end
    if self.goodBg then
        self.goodBg:setImageColor(nil, unpack(quality == 4 and selectedBgColor or unselectedBgColor))
    end
    if self.excellentBg then
        self.excellentBg:setImageColor(nil, unpack(quality == 5 and selectedBgColor or unselectedBgColor))
    end

    -- Change name color when selected
    -- Indices match QUALITY_TIERS: 1=Any, 2=Poor, 3=Fair, 4=Good, 5=Excellent
    if self.anyName then
        self.anyName:setTextColor(unpack(quality == 1 and selectedTextColor or unselectedTextColor))
    end
    if self.poorName then
        self.poorName:setTextColor(unpack(quality == 2 and selectedTextColor or unselectedTextColor))
    end
    if self.fairName then
        self.fairName:setTextColor(unpack(quality == 3 and selectedTextColor or unselectedTextColor))
    end
    if self.goodName then
        self.goodName:setTextColor(unpack(quality == 4 and selectedTextColor or unselectedTextColor))
    end
    if self.excellentName then
        self.excellentName:setTextColor(unpack(quality == 5 and selectedTextColor or unselectedTextColor))
    end

    -- Update displayed success rates to reflect quality modifier
    self:updateDisplayedRates()
end

--[[
     Quality checkbox callbacks (exclusive selection)
     Indices match QUALITY_TIERS array: 1=Any, 2=Poor, 3=Fair, 4=Good, 5=Excellent
]]
function UsedSearchDialog:onAnyConditionSelected()
    self:selectQuality(1)
end

function UsedSearchDialog:onPoorConditionSelected()
    self:selectQuality(2)
end

function UsedSearchDialog:onFairConditionSelected()
    self:selectQuality(3)
end

function UsedSearchDialog:onGoodConditionSelected()
    self:selectQuality(4)
end

function UsedSearchDialog:onExcellentConditionSelected()
    self:selectQuality(5)
end

--[[
     Start Search button callback
     v1.5.0: Multi-find agent model - retainer fee upfront, commission on purchase
]]
function UsedSearchDialog:onStartSearch()
    if self.storeItem == nil then
        UsedPlus.logError("No item selected for search")
        return
    end

    -- v1.5.0: Multi-find agent model tier data
    -- Must match self.SEARCH_TIERS and UsedVehicleSearch.SEARCH_TIERS
    local SEARCH_TIERS = {
        {
            name = "Local",
            nameKey = "usedplus_searchTier_local",
            retainerFlat = 500,
            retainerPercent = 0,
            commissionPercent = 0.06,
            maxMonths = 1,
            monthlySuccessChance = 0.30,
            maxListings = 3
        },
        {
            name = "Regional",
            nameKey = "usedplus_searchTier_regional",
            retainerFlat = 1000,
            retainerPercent = 0.005,
            commissionPercent = 0.08,
            maxMonths = 3,
            monthlySuccessChance = 0.55,
            maxListings = 6
        },
        {
            name = "National",
            nameKey = "usedplus_searchTier_national",
            retainerFlat = 2000,
            retainerPercent = 0.008,
            commissionPercent = 0.10,
            maxMonths = 6,
            monthlySuccessChance = 0.85,
            maxListings = 10,
            guaranteedMinimum = 1
        }
    }

    local tier = SEARCH_TIERS[self.selectedTier]

    -- v1.5.0: Calculate retainer fee (flat + percentage of vehicle price)
    local baseRetainer = tier.retainerFlat + math.floor(self.basePrice * tier.retainerPercent)

    -- Apply credit score modifier to retainer (better credit = cheaper agents)
    local creditFeeModifier = self:getCreditFeeModifier()
    local retainerFee = math.floor(baseRetainer * (1 + creditFeeModifier))

    -- Get quality tier info (v1.4.0: uses price range, show midpoint for estimate)
    local qualityTier = UsedSearchDialog.QUALITY_TIERS[self.selectedQuality]
    local priceRangeMin = qualityTier.priceRangeMin or 0.30
    local priceRangeMax = qualityTier.priceRangeMax or 0.50
    local avgPriceMultiplier = (priceRangeMin + priceRangeMax) / 2
    local estimatedBasePrice = math.floor(self.basePrice * avgPriceMultiplier)
    -- Commission added on top of base price
    local estimatedCommission = math.floor(estimatedBasePrice * tier.commissionPercent)
    local estimatedAskingPrice = estimatedBasePrice + estimatedCommission

    -- Validate funds (only need retainer upfront now!)
    local farm = g_farmManager:getFarmById(self.farmId)
    if farm == nil then
        UsedPlus.logError("Farm not found")
        return
    end

    if farm.money < retainerFee then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_insufficientFunds"), UIHelper.Text.formatMoney(retainerFee))
        )
        return
    end

    -- Store data for use after dialog closes
    local itemName = self.vehicleName or self.storeItem.name
    local storeItemIndex = self.storeItemIndex
    local basePrice = self.basePrice
    local farmId = self.farmId
    local selectedTier = self.selectedTier
    local selectedQuality = self.selectedQuality

    -- Log before closing (close() may clear data)
    UsedPlus.logDebug(string.format("Search request sent: %s (Tier %d, Quality %d, Retainer: $%d)",
        itemName, selectedTier, selectedQuality, retainerFee))

    -- Send search request to server with quality level
    RequestUsedItemEvent.sendToServer(
        farmId,
        storeItemIndex,
        itemName,
        basePrice,
        selectedTier,
        selectedQuality  -- Pass quality level instead of configId
    )

    -- Close dialog first
    self:close()

    -- v1.5.0: Show styled SearchInitiatedDialog with all details
    local tierName = tier.nameKey and g_i18n:getText(tier.nameKey) or tier.name
    local qualityName = qualityTier.nameKey and g_i18n:getText(qualityTier.nameKey) or qualityTier.name
    local durationText = tier.maxMonths == 1 and g_i18n:getText("usedplus_time_1month") or string.format(g_i18n:getText("usedplus_time_months"), tier.maxMonths)

    DialogLoader.show("SearchInitiatedDialog", "show", {
        vehicleName = itemName,
        tierName = tierName,
        duration = durationText,
        maxListings = tier.maxListings,
        qualityName = qualityName,
        retainerFee = retainerFee,
        commissionPercent = tier.commissionPercent,
        estimatedBasePrice = estimatedBasePrice,
        estimatedCommission = estimatedCommission,
        estimatedAskingPrice = estimatedAskingPrice
    })

    -- Also add corner notification for when they exit menus
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format(g_i18n:getText("usedplus_notification_searchInitiated"), itemName, tierName, durationText)
    )
end

--[[
     Cancel button callback
]]
function UsedSearchDialog:onCancel()
    self:close()
end

--[[
     Cleanup
]]
function UsedSearchDialog:onClose()
    self.storeItem = nil
    self.storeItemIndex = nil
    self.vehicleName = nil
    self.basePrice = 0
    self.farmId = nil
    self.selectedTier = 1
    self.selectedQuality = 1  -- Reset quality selection

    UsedSearchDialog:superClass().onClose(self)
end

UsedPlus.logInfo("UsedSearchDialog loaded")
