--[[
    FS25_UsedPlus - Settings Menu Extension

    Adds UsedPlus settings to ESC > Settings > Game Settings page.
    Pattern from: EnhancedLoanSystem ELS_settingsMenuExtension

    Hooks InGameMenuSettingsFrame.onFrameOpen to add elements dynamically.
    Settings are added to gameSettingsLayout using standard FS25 profiles.

    v1.4.0: Full settings implementation
    - 1 preset selector
    - 9 system toggles
    - 15 economic parameters
]]

UsedPlusSettingsMenuExtension = {}

-- v2.0.0: Expanded preset options (6 presets)
UsedPlusSettingsMenuExtension.presetOptions = {"Easy", "Balanced", "Challenging", "Hardcore", "Streamlined", "Immersive"}
UsedPlusSettingsMenuExtension.presetKeys = {"easy", "balanced", "challenging", "hardcore", "streamlined", "immersive"}

-- Economic parameter value ranges (for dropdowns)
-- v2.0.0: Expanded ranges for more flexible presets
UsedPlusSettingsMenuExtension.ranges = {
    -- Interest Rate: 4-12%
    interestRate = {"4%", "5%", "6%", "7%", "8%", "9%", "10%", "11%", "12%"},
    interestRateValues = {0.04, 0.05, 0.06, 0.07, 0.08, 0.09, 0.10, 0.11, 0.12},

    -- v2.0.0: Trade-In expanded to 40-80% for easy mode
    tradeInPercent = {"40%", "45%", "50%", "55%", "60%", "65%", "70%", "75%", "80%"},
    tradeInPercentValues = {40, 45, 50, 55, 60, 65, 70, 75, 80},

    -- v2.0.0: Repair multiplier now starts at 0.25x
    repairMultiplier = {"0.25x", "0.5x", "0.75x", "1.0x", "1.25x", "1.5x", "1.75x", "2.0x"},
    repairMultiplierValues = {0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0},

    -- v2.0.0: NEW - Paint multiplier (separate from repair)
    paintMultiplier = {"0.25x", "0.5x", "0.75x", "1.0x", "1.25x", "1.5x", "1.75x", "2.0x"},
    paintMultiplierValues = {0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0},

    leaseMarkup = {"5%", "10%", "15%", "20%", "25%"},
    leaseMarkupValues = {5, 10, 15, 20, 25},

    -- v2.0.0: Missed payments extended to 10 for easy mode
    missedPayments = {"1", "2", "3", "4", "5", "6", "8", "10"},
    missedPaymentsValues = {1, 2, 3, 4, 5, 6, 8, 10},

    downPayment = {"0%", "5%", "10%", "15%", "20%", "25%", "30%"},
    downPaymentValues = {0, 5, 10, 15, 20, 25, 30},

    startingCredit = {"500", "550", "600", "650", "700", "750"},
    startingCreditValues = {500, 550, 600, 650, 700, 750},

    -- v2.0.0: Late penalty now includes 0 and 2 for easy mode
    latePenalty = {"0", "2", "5", "10", "15", "20", "25", "30"},
    latePenaltyValues = {0, 2, 5, 10, 15, 20, 25, 30},

    -- v2.0.0: Search success with full range for all presets (35-95%)
    searchSuccess = {"35%", "40%", "45%", "50%", "55%", "60%", "65%", "70%", "75%", "80%", "85%", "90%", "95%"},
    searchSuccessValues = {35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95},

    -- v2.0.0: REMOVED from UI - maxListings kept internal only

    offerExpiry = {"24h", "48h", "72h", "96h", "120h", "168h"},
    offerExpiryValues = {24, 48, 72, 96, 120, 168},

    commission = {"4%", "6%", "8%", "10%", "12%", "15%"},
    commissionValues = {4, 6, 8, 10, 12, 15},

    conditionMin = {"20%", "30%", "40%", "50%", "60%"},
    conditionMinValues = {20, 30, 40, 50, 60},

    conditionMax = {"80%", "85%", "90%", "95%", "100%"},
    conditionMaxValues = {80, 85, 90, 95, 100},

    conditionMultiplier = {"0.5x", "0.75x", "1.0x", "1.25x", "1.5x"},
    conditionMultiplierValues = {0.5, 0.75, 1.0, 1.25, 1.5},

    brandBonus = {"0%", "2%", "5%", "7%", "10%"},
    brandBonusValues = {0, 2, 5, 7, 10},

    -- v2.0.0: Bank Interest Rate (APY)
    bankInterestRate = {"0%", "0.5%", "1%", "1.5%", "2%", "2.5%", "3%", "3.5%", "4%", "5%"},
    bankInterestRateValues = {0, 0.005, 0.01, 0.015, 0.02, 0.025, 0.03, 0.035, 0.04, 0.05},

    -- v2.8.0: Malfunction Frequency multiplier
    malfunctionFrequency = {"25%", "50%", "75%", "100%", "125%", "150%", "175%", "200%"},
    malfunctionFrequencyValues = {0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0},

    -- v2.15.1: Fluid Drain Rate multiplier
    fluidDrainRate = {"25%", "50%", "75%", "100%", "125%", "150%", "175%", "200%"},
    fluidDrainRateValues = {0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0},
}

--[[
    Called when InGameMenuSettingsFrame opens
    Adds our settings section to the gameSettingsLayout
]]
function UsedPlusSettingsMenuExtension:onFrameOpen()
    if self.usedplus_initDone then
        return
    end

    UsedPlus.logDebug("[Settings] onFrameOpen: Adding settings elements...")

    -- Match ELS pattern exactly - direct calls, no pcall wrapper
    UsedPlusSettingsMenuExtension:addSettingsElements(self)

    -- Refresh layout
    self.gameSettingsLayout:invalidateLayout()
    self:updateAlternatingElements(self.gameSettingsLayout)
    self:updateGeneralSettings(self.gameSettingsLayout)

    self.usedplus_initDone = true

    -- Update UI to reflect current settings
    UsedPlusSettingsMenuExtension:updateSettingsUI(self)

    UsedPlus.logDebug("[Settings] onFrameOpen: Settings menu setup complete")
end

--[[
    Add all settings elements (separated for pcall wrapping)
]]
function UsedPlusSettingsMenuExtension:addSettingsElements(frame)
    local ranges = UsedPlusSettingsMenuExtension.ranges

    UsedPlus.logDebug("[Settings] addSettingsElements: Starting...")
    UsedPlus.logDebug("[Settings] addSettingsElements: frame = " .. tostring(frame))
    UsedPlus.logDebug("[Settings] addSettingsElements: gameSettingsLayout = " .. tostring(frame.gameSettingsLayout))

    -- Single section header (like ELS pattern)
    UsedPlusSettingsMenuExtension:addSectionHeader(frame, g_i18n:getText("usedplus_settings_header") or "UsedPlus Settings")
    UsedPlus.logDebug("[Settings] addSettingsElements: Section header added")

    -- Preset selector
    frame.usedplus_presetOption = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onPresetChanged", UsedPlusSettingsMenuExtension.presetOptions,
        g_i18n:getText("usedplus_setting_preset") or "Quick Preset",
        g_i18n:getText("usedplus_setting_preset_desc") or "Apply a preset configuration"
    )
    UsedPlus.logDebug("[Settings] addSettingsElements: Preset option added = " .. tostring(frame.usedplus_presetOption))

    -- System toggles
    UsedPlus.logDebug("[Settings] addSettingsElements: About to add finance toggle...")
    frame.usedplus_financeToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
        frame, "onFinanceToggleChanged",
        g_i18n:getText("usedplus_setting_finance") or "Vehicle/Land Financing",
        g_i18n:getText("usedplus_setting_finance_desc") or "Enable financing for purchases"
    )
    UsedPlus.logDebug("[Settings] addSettingsElements: Finance toggle added = " .. tostring(frame.usedplus_financeToggle))

    frame.usedplus_leaseToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
        frame, "onLeaseToggleChanged",
        g_i18n:getText("usedplus_setting_lease") or "Leasing",
        g_i18n:getText("usedplus_setting_lease_desc") or "Enable vehicle and land leasing"
    )

    frame.usedplus_searchToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
        frame, "onSearchToggleChanged",
        g_i18n:getText("usedplus_setting_search") or "Used Vehicle Search",
        g_i18n:getText("usedplus_setting_search_desc") or "Enable searching for used equipment"
    )

    frame.usedplus_saleToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
        frame, "onSaleToggleChanged",
        g_i18n:getText("usedplus_setting_sale") or "Vehicle Sales",
        g_i18n:getText("usedplus_setting_sale_desc") or "Enable agent-based vehicle sales"
    )

    frame.usedplus_repairToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
        frame, "onRepairToggleChanged",
        g_i18n:getText("usedplus_setting_repair") or "Repair System",
        g_i18n:getText("usedplus_setting_repair_desc") or "Enable partial repair and repaint"
    )

    frame.usedplus_tradeinToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
        frame, "onTradeinToggleChanged",
        g_i18n:getText("usedplus_setting_tradein") or "Trade-In System",
        g_i18n:getText("usedplus_setting_tradein_desc") or "Enable trade-in during purchases"
    )

    frame.usedplus_creditToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
        frame, "onCreditToggleChanged",
        g_i18n:getText("usedplus_setting_credit") or "Credit Scoring",
        g_i18n:getText("usedplus_setting_credit_desc") or "Enable dynamic credit-based interest rates"
    )

    frame.usedplus_tirewearToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
        frame, "onTirewearToggleChanged",
        g_i18n:getText("usedplus_setting_tirewear") or "Tire Wear",
        g_i18n:getText("usedplus_setting_tirewear_desc") or "Enable realistic tire degradation"
    )

    frame.usedplus_malfunctionsToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
        frame, "onMalfunctionsToggleChanged",
        g_i18n:getText("usedplus_setting_malfunctions") or "Malfunctions",
        g_i18n:getText("usedplus_setting_malfunctions_desc") or "Enable random breakdowns and failures"
    )

    -- v2.8.0: Malfunction Frequency slider (only shown when malfunctions are enabled)
    frame.usedplus_malfunctionFrequency = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onMalfunctionFrequencyChanged", ranges.malfunctionFrequency,
        g_i18n:getText("usedplus_setting_malfunctionFrequency") or "Malfunction Frequency",
        g_i18n:getText("usedplus_setting_malfunctionFrequency_desc") or "How often malfunctions occur. 100% = normal, 50% = half as often, 200% = twice as often"
    )

    -- v2.15.1: Fluid Drain Rate slider
    frame.usedplus_fluidDrainRate = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onFluidDrainRateChanged", ranges.fluidDrainRate,
        g_i18n:getText("usedplus_setting_fluidDrainRate") or "Fluid Drain Rate",
        g_i18n:getText("usedplus_setting_fluidDrainRate_desc") or "How fast oil and hydraulic fluid deplete. 100% = normal, 50% = half speed, 200% = double speed"
    )

    -- v2.0.0: NEW - Partial Repair toggle
    frame.usedplus_partialRepairToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
        frame, "onPartialRepairToggleChanged",
        g_i18n:getText("usedplus_setting_partialRepair") or "Partial Repair",
        g_i18n:getText("usedplus_setting_partialRepair_desc") or "Enable partial repairs in vehicle shop"
    )

    -- v2.0.0: NEW - Partial Repaint toggle
    frame.usedplus_partialRepaintToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
        frame, "onPartialRepaintToggleChanged",
        g_i18n:getText("usedplus_setting_partialRepaint") or "Partial Repaint",
        g_i18n:getText("usedplus_setting_partialRepaint_desc") or "Enable partial repaints in vehicle shop"
    )

    -- v2.0.0: NEW - Farmland Difficulty Scaling toggle
    frame.usedplus_farmlandDifficultyToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
        frame, "onFarmlandDifficultyToggleChanged",
        g_i18n:getText("usedplus_setting_farmlandDifficulty") or "Farmland Difficulty Scaling",
        g_i18n:getText("usedplus_setting_farmlandDifficulty_desc") or "Scale land prices with game difficulty (Easy: 60%, Normal: 100%, Hard: 140%)"
    )

    -- v2.0.0: NEW - Bank Interest toggle
    frame.usedplus_bankInterestToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
        frame, "onBankInterestToggleChanged",
        g_i18n:getText("usedplus_setting_bankInterest") or "Bank Interest",
        g_i18n:getText("usedplus_setting_bankInterest_desc") or "Earn monthly interest on positive cash balances"
    )

    -- v2.6.2: NEW - Mod Compatibility section
    UsedPlusSettingsMenuExtension:addSectionHeader(frame, g_i18n:getText("usedplus_settings_compatibility") or "Mod Compatibility")

    -- RVB Integration toggle (only show if RVB detected)
    if ModCompatibility and ModCompatibility.rvbDetected then
        frame.usedplus_rvbIntegrationToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
            frame, "onRVBIntegrationToggleChanged",
            g_i18n:getText("usedplus_setting_rvbIntegration") or "RVB Integration",
            g_i18n:getText("usedplus_setting_rvbIntegration_desc") or "Enable Real Vehicle Breakdowns integration (symptom sharing, deferred failures)"
        )
    end

    -- UYT Integration toggle (only show if UYT detected)
    if ModCompatibility and ModCompatibility.uytDetected then
        frame.usedplus_uytIntegrationToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
            frame, "onUYTIntegrationToggleChanged",
            g_i18n:getText("usedplus_setting_uytIntegration") or "UYT Integration",
            g_i18n:getText("usedplus_setting_uytIntegration_desc") or "Enable Use Your Tyres integration (tire wear sync)"
        )
    end

    -- AM Integration toggle (only show if AM detected)
    if ModCompatibility and ModCompatibility.amDetected then
        frame.usedplus_amIntegrationToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
            frame, "onAMIntegrationToggleChanged",
            g_i18n:getText("usedplus_setting_amIntegration") or "AM Integration",
            g_i18n:getText("usedplus_setting_amIntegration_desc") or "Enable AdvancedMaintenance integration (chains engine damage checks)"
        )
    end

    -- HP Integration toggle (only show if HP detected)
    if ModCompatibility and ModCompatibility.hpDetected then
        frame.usedplus_hpIntegrationToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
            frame, "onHPIntegrationToggleChanged",
            g_i18n:getText("usedplus_setting_hpIntegration") or "HP Integration",
            g_i18n:getText("usedplus_setting_hpIntegration_desc") or "Enable HirePurchasing integration (hides Finance button, HP handles financing)"
        )
    end

    -- BUE Integration toggle (only show if BUE detected)
    if ModCompatibility and ModCompatibility.bueDetected then
        frame.usedplus_bueIntegrationToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
            frame, "onBUEIntegrationToggleChanged",
            g_i18n:getText("usedplus_setting_bueIntegration") or "BUE Integration",
            g_i18n:getText("usedplus_setting_bueIntegration_desc") or "Enable BuyUsedEquipment integration (hides Search button, BUE handles used search)"
        )
    end

    -- ELS Integration toggle (only show if ELS detected)
    if ModCompatibility and ModCompatibility.elsDetected then
        frame.usedplus_elsIntegrationToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
            frame, "onELSIntegrationToggleChanged",
            g_i18n:getText("usedplus_setting_elsIntegration") or "ELS Integration",
            g_i18n:getText("usedplus_setting_elsIntegration_desc") or "Enable EnhancedLoanSystem integration (disables loans, ELS handles them)"
        )
    end

    -- v2.15.2: BC Integration toggle (only show if BC detected)
    if ModCompatibility and ModCompatibility.bcDetected then
        frame.usedplus_bcIntegrationToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
            frame, "onBCIntegrationToggleChanged",
            g_i18n:getText("usedplus_setting_bcIntegration") or "Better Contracts",
            g_i18n:getText("usedplus_setting_bcIntegration_desc") or "Enable Better Contracts integration. Applies earned farmland discounts from completed contracts."
        )
    end

    -- v2.7.0: Shop Buy/Lease override toggle (always shown)
    frame.usedplus_overrideShopBuyLeaseToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
        frame, "onOverrideShopBuyLeaseToggleChanged",
        g_i18n:getText("usedplus_setting_overrideShopBuyLease") or "Override Shop Buy/Lease",
        g_i18n:getText("usedplus_setting_overrideShopBuyLease_desc") or "When ON, Buy/Lease buttons open UsedPlus dialog. When OFF, use Finance button for UsedPlus features. Disable if you have conflicts with other shop mods."
    )

    -- v2.7.0: RVB Repair override toggle (only shown when RVB is installed)
    if ModCompatibility and ModCompatibility.rvbInstalled then
        frame.usedplus_overrideRVBRepairToggle = UsedPlusSettingsMenuExtension:addBinaryOption(
            frame, "onOverrideRVBRepairToggleChanged",
            g_i18n:getText("usedplus_setting_overrideRVBRepair") or "Override RVB Repair",
            g_i18n:getText("usedplus_setting_overrideRVBRepair_desc") or "When ON, RVB's Repair button opens UsedPlus partial repair. When OFF, use Map > Repair Vehicle for UsedPlus features."
        )
    end

    -- Economic parameters
    -- v2.0.0: Updated tooltip to clarify what interest rate applies to
    frame.usedplus_interestRate = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onInterestRateChanged", ranges.interestRate,
        g_i18n:getText("usedplus_setting_interestRate") or "Financing Interest Rate",
        g_i18n:getText("usedplus_setting_interestRate_desc") or "Base rate for all financing (vehicles, land, loans). Credit score modifies this."
    )

    frame.usedplus_tradeInPercent = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onTradeInPercentChanged", ranges.tradeInPercent,
        g_i18n:getText("usedplus_setting_tradeInValue") or "Trade-In Value %",
        g_i18n:getText("usedplus_setting_tradeInValue_desc") or "Base percentage of sell price for trade-ins (±7.5% variance)"
    )

    frame.usedplus_repairMultiplier = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onRepairMultiplierChanged", ranges.repairMultiplier,
        g_i18n:getText("usedplus_setting_repairCost") or "Repair Cost Multiplier",
        g_i18n:getText("usedplus_setting_repairCost_desc") or "Multiplier applied to repair costs"
    )

    -- v2.0.0: NEW - Paint Cost Multiplier (separate from repair)
    frame.usedplus_paintMultiplier = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onPaintMultiplierChanged", ranges.paintMultiplier,
        g_i18n:getText("usedplus_setting_paintCost") or "Paint Cost Multiplier",
        g_i18n:getText("usedplus_setting_paintCost_desc") or "Multiplier applied to repaint costs"
    )

    frame.usedplus_leaseMarkup = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onLeaseMarkupChanged", ranges.leaseMarkup,
        g_i18n:getText("usedplus_setting_leaseMarkup") or "Lease Markup %",
        g_i18n:getText("usedplus_setting_leaseMarkup_desc") or "Lease rate markup (÷10 for percentage points, e.g., 15 = +1.5pp)"
    )

    frame.usedplus_missedPayments = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onMissedPaymentsChanged", ranges.missedPayments,
        g_i18n:getText("usedplus_setting_missedPayments") or "Missed Payments to Default",
        g_i18n:getText("usedplus_setting_missedPayments_desc") or "Number of missed payments before repossession"
    )

    frame.usedplus_downPayment = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onDownPaymentChanged", ranges.downPayment,
        g_i18n:getText("usedplus_setting_downPayment") or "Min Down Payment %",
        g_i18n:getText("usedplus_setting_downPayment_desc") or "Minimum required down payment percentage"
    )

    frame.usedplus_startingCredit = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onStartingCreditChanged", ranges.startingCredit,
        g_i18n:getText("usedplus_setting_startingCredit") or "Starting Credit Score",
        g_i18n:getText("usedplus_setting_startingCredit_desc") or "Credit score for new games"
    )

    frame.usedplus_latePenalty = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onLatePenaltyChanged", ranges.latePenalty,
        g_i18n:getText("usedplus_setting_latePenalty") or "Late Payment Penalty",
        g_i18n:getText("usedplus_setting_latePenalty_desc") or "Credit score penalty for late payments"
    )

    -- v2.0.0: Renamed to clarify tiers add bonuses
    frame.usedplus_searchSuccess = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onSearchSuccessChanged", ranges.searchSuccess,
        g_i18n:getText("usedplus_setting_searchSuccess") or "Base Search Success %",
        g_i18n:getText("usedplus_setting_searchSuccess_desc") or "Base chance to find used vehicles. Tiers add bonuses: Economy +0%, Standard +10%, Premium +20%, Elite +30%"
    )

    -- v2.0.0: REMOVED - maxListings (kept internal, not user-configurable)

    frame.usedplus_offerExpiry = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onOfferExpiryChanged", ranges.offerExpiry,
        g_i18n:getText("usedplus_setting_offerExpiry") or "Offer Expiration",
        g_i18n:getText("usedplus_setting_offerExpiry_desc") or "Hours until sale offers expire"
    )

    frame.usedplus_commission = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onCommissionChanged", ranges.commission,
        g_i18n:getText("usedplus_setting_commission") or "Agent Commission %",
        g_i18n:getText("usedplus_setting_commission_desc") or "Percentage taken by sale agents"
    )

    frame.usedplus_conditionMin = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onConditionMinChanged", ranges.conditionMin,
        g_i18n:getText("usedplus_setting_conditionMin") or "Used Condition Min",
        g_i18n:getText("usedplus_setting_conditionMin_desc") or "Minimum condition for used vehicles"
    )

    frame.usedplus_conditionMax = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onConditionMaxChanged", ranges.conditionMax,
        g_i18n:getText("usedplus_setting_conditionMax") or "Used Condition Max",
        g_i18n:getText("usedplus_setting_conditionMax_desc") or "Maximum condition for used vehicles"
    )

    frame.usedplus_conditionMultiplier = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onConditionMultiplierChanged", ranges.conditionMultiplier,
        g_i18n:getText("usedplus_setting_conditionMult") or "Condition Price Impact",
        g_i18n:getText("usedplus_setting_conditionMult_desc") or "How much condition affects price"
    )

    frame.usedplus_brandBonus = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onBrandBonusChanged", ranges.brandBonus,
        g_i18n:getText("usedplus_setting_brandBonus") or "Brand Loyalty Bonus",
        g_i18n:getText("usedplus_setting_brandBonus_desc") or "Extra trade-in value for same brand"
    )

    -- v2.0.0: NEW - Bank Interest Rate dropdown
    frame.usedplus_bankInterestRate = UsedPlusSettingsMenuExtension:addMultiTextOption(
        frame, "onBankInterestRateChanged", ranges.bankInterestRate,
        g_i18n:getText("usedplus_setting_bankInterestRate") or "Interest Rate (APY)",
        g_i18n:getText("usedplus_setting_bankInterestRate_desc") or "Annual interest rate on positive cash balances"
    )

    UsedPlus.logDebug("[Settings] addSettingsElements: ALL ELEMENTS ADDED SUCCESSFULLY!")
end

--[[
    Add a section header to the settings layout
]]
function UsedPlusSettingsMenuExtension:addSectionHeader(frame, text)
    local textElement = TextElement.new()
    local textElementProfile = g_gui:getProfile("fs25_settingsSectionHeader")
    textElement.name = "sectionHeader"
    textElement:loadProfile(textElementProfile, true)
    textElement:setText(text)
    frame.gameSettingsLayout:addElement(textElement)
    textElement:onGuiSetupFinished()
end

--[[
    Add a multi-text option (dropdown) to the settings layout
]]
function UsedPlusSettingsMenuExtension:addMultiTextOption(frame, callbackName, texts, title, tooltip)
    local bitMap = BitmapElement.new()
    local bitMapProfile = g_gui:getProfile("fs25_multiTextOptionContainer")
    bitMap:loadProfile(bitMapProfile, true)

    local multiTextOption = MultiTextOptionElement.new()
    local multiTextOptionProfile = g_gui:getProfile("fs25_settingsMultiTextOption")
    multiTextOption:loadProfile(multiTextOptionProfile, true)
    multiTextOption.target = UsedPlusSettingsMenuExtension
    multiTextOption:setCallback("onClickCallback", callbackName)
    multiTextOption:setTexts(texts)

    local titleElement = TextElement.new()
    local titleProfile = g_gui:getProfile("fs25_settingsMultiTextOptionTitle")
    titleElement:loadProfile(titleProfile, true)
    titleElement:setText(title)

    local tooltipElement = TextElement.new()
    local tooltipProfile = g_gui:getProfile("fs25_multiTextOptionTooltip")
    tooltipElement.name = "ignore"
    tooltipElement:loadProfile(tooltipProfile, true)
    tooltipElement:setText(tooltip)

    multiTextOption:addElement(tooltipElement)
    bitMap:addElement(multiTextOption)
    bitMap:addElement(titleElement)

    multiTextOption:onGuiSetupFinished()
    titleElement:onGuiSetupFinished()
    tooltipElement:onGuiSetupFinished()

    frame.gameSettingsLayout:addElement(bitMap)
    bitMap:onGuiSetupFinished()

    return multiTextOption
end

--[[
    Add a binary option (Yes/No toggle) to the settings layout
]]
function UsedPlusSettingsMenuExtension:addBinaryOption(frame, callbackName, title, tooltip)
    UsedPlus.logDebug("[Settings] addBinaryOption: Creating for '" .. tostring(title) .. "'")

    local bitMap = BitmapElement.new()
    UsedPlus.logDebug("[Settings] addBinaryOption: BitmapElement created")

    local bitMapProfile = g_gui:getProfile("fs25_multiTextOptionContainer")
    UsedPlus.logDebug("[Settings] addBinaryOption: Container profile = " .. tostring(bitMapProfile))
    bitMap:loadProfile(bitMapProfile, true)
    UsedPlus.logDebug("[Settings] addBinaryOption: Container profile loaded")

    local binaryOption = BinaryOptionElement.new()
    UsedPlus.logDebug("[Settings] addBinaryOption: BinaryOptionElement created")
    binaryOption.useYesNoTexts = true
    local binaryOptionProfile = g_gui:getProfile("fs25_settingsBinaryOption")
    UsedPlus.logDebug("[Settings] addBinaryOption: Binary profile = " .. tostring(binaryOptionProfile))
    binaryOption:loadProfile(binaryOptionProfile, true)
    UsedPlus.logDebug("[Settings] addBinaryOption: Binary profile loaded")
    binaryOption.target = UsedPlusSettingsMenuExtension
    binaryOption:setCallback("onClickCallback", callbackName)
    UsedPlus.logDebug("[Settings] addBinaryOption: Callback set")

    local titleElement = TextElement.new()
    local titleProfile = g_gui:getProfile("fs25_settingsMultiTextOptionTitle")
    titleElement:loadProfile(titleProfile, true)
    titleElement:setText(title)

    local tooltipElement = TextElement.new()
    local tooltipProfile = g_gui:getProfile("fs25_multiTextOptionTooltip")
    tooltipElement.name = "ignore"
    tooltipElement:loadProfile(tooltipProfile, true)
    tooltipElement:setText(tooltip)

    binaryOption:addElement(tooltipElement)
    bitMap:addElement(binaryOption)
    bitMap:addElement(titleElement)

    binaryOption:onGuiSetupFinished()
    titleElement:onGuiSetupFinished()
    tooltipElement:onGuiSetupFinished()
    UsedPlus.logDebug("[Settings] addBinaryOption: Elements setup finished")

    frame.gameSettingsLayout:addElement(bitMap)
    UsedPlus.logDebug("[Settings] addBinaryOption: Added to layout")
    bitMap:onGuiSetupFinished()
    UsedPlus.logDebug("[Settings] addBinaryOption: Complete for '" .. tostring(title) .. "'")

    return binaryOption
end

--[[
    Helper to find index in values array
]]
function UsedPlusSettingsMenuExtension:findValueIndex(values, target)
    for i, v in ipairs(values) do
        if v == target then
            return i
        end
    end
    return 1  -- Default to first
end

--[[
    Update the settings UI to reflect current values from UsedPlusSettings
]]
function UsedPlusSettingsMenuExtension:updateSettingsUI(frame)
    if not frame.usedplus_initDone then
        return
    end

    if not UsedPlusSettings then
        return
    end

    local ranges = UsedPlusSettingsMenuExtension.ranges

    -- Helper to set toggle state
    local function setChecked(toggle, key)
        if toggle then
            local value = UsedPlusSettings:get(key)
            toggle:setIsChecked(value == true, false, false)
        end
    end

    -- Helper to set dropdown state
    local function setState(dropdown, values, key)
        if dropdown then
            local value = UsedPlusSettings:get(key)
            local index = UsedPlusSettingsMenuExtension:findValueIndex(values, value)
            dropdown:setState(index)
        end
    end

    -- Update toggles
    setChecked(frame.usedplus_financeToggle, "enableFinanceSystem")
    setChecked(frame.usedplus_leaseToggle, "enableLeaseSystem")
    setChecked(frame.usedplus_searchToggle, "enableUsedVehicleSearch")
    setChecked(frame.usedplus_saleToggle, "enableVehicleSaleSystem")
    setChecked(frame.usedplus_repairToggle, "enableRepairSystem")
    setChecked(frame.usedplus_tradeinToggle, "enableTradeInSystem")
    setChecked(frame.usedplus_creditToggle, "enableCreditSystem")
    setChecked(frame.usedplus_tirewearToggle, "enableTireWearSystem")
    setChecked(frame.usedplus_malfunctionsToggle, "enableMalfunctionsSystem")
    setChecked(frame.usedplus_partialRepairToggle, "enablePartialRepair")   -- v2.0.0
    setChecked(frame.usedplus_partialRepaintToggle, "enablePartialRepaint") -- v2.0.0
    setChecked(frame.usedplus_farmlandDifficultyToggle, "enableFarmlandDifficultyScaling") -- v2.0.0
    setChecked(frame.usedplus_bankInterestToggle, "enableBankInterest") -- v2.0.0
    setChecked(frame.usedplus_rvbIntegrationToggle, "enableRVBIntegration") -- v2.6.2
    setChecked(frame.usedplus_uytIntegrationToggle, "enableUYTIntegration") -- v2.6.2
    setChecked(frame.usedplus_amIntegrationToggle, "enableAMIntegration") -- v2.6.2
    setChecked(frame.usedplus_hpIntegrationToggle, "enableHPIntegration") -- v2.6.2
    setChecked(frame.usedplus_bueIntegrationToggle, "enableBUEIntegration") -- v2.6.2
    setChecked(frame.usedplus_elsIntegrationToggle, "enableELSIntegration") -- v2.6.2
    setChecked(frame.usedplus_bcIntegrationToggle, "enableBCIntegration") -- v2.15.2
    setChecked(frame.usedplus_overrideShopBuyLeaseToggle, "overrideShopBuyLease") -- v2.7.0
    setChecked(frame.usedplus_overrideRVBRepairToggle, "overrideRVBRepair") -- v2.7.0

    -- Update economic parameters
    setState(frame.usedplus_interestRate, ranges.interestRateValues, "baseInterestRate")
    setState(frame.usedplus_tradeInPercent, ranges.tradeInPercentValues, "baseTradeInPercent")
    setState(frame.usedplus_repairMultiplier, ranges.repairMultiplierValues, "repairCostMultiplier")
    setState(frame.usedplus_paintMultiplier, ranges.paintMultiplierValues, "paintCostMultiplier")  -- v2.0.0
    setState(frame.usedplus_leaseMarkup, ranges.leaseMarkupValues, "leaseMarkupPercent")
    setState(frame.usedplus_missedPayments, ranges.missedPaymentsValues, "missedPaymentsToDefault")
    setState(frame.usedplus_downPayment, ranges.downPaymentValues, "minDownPaymentPercent")
    setState(frame.usedplus_startingCredit, ranges.startingCreditValues, "startingCreditScore")
    setState(frame.usedplus_latePenalty, ranges.latePenaltyValues, "latePaymentPenalty")
    setState(frame.usedplus_searchSuccess, ranges.searchSuccessValues, "baseSearchSuccessPercent")  -- v2.0.0: renamed
    -- v2.0.0: maxListings removed from UI
    setState(frame.usedplus_offerExpiry, ranges.offerExpiryValues, "offerExpirationHours")
    setState(frame.usedplus_commission, ranges.commissionValues, "agentCommissionPercent")
    setState(frame.usedplus_conditionMin, ranges.conditionMinValues, "usedConditionMin")
    setState(frame.usedplus_conditionMax, ranges.conditionMaxValues, "usedConditionMax")
    setState(frame.usedplus_conditionMultiplier, ranges.conditionMultiplierValues, "conditionPriceMultiplier")
    setState(frame.usedplus_brandBonus, ranges.brandBonusValues, "brandLoyaltyBonus")
    setState(frame.usedplus_bankInterestRate, ranges.bankInterestRateValues, "bankInterestRate") -- v2.0.0
    setState(frame.usedplus_malfunctionFrequency, ranges.malfunctionFrequencyValues, "malfunctionFrequencyMultiplier") -- v2.8.0
    setState(frame.usedplus_fluidDrainRate, ranges.fluidDrainRateValues, "fluidDrainRateMultiplier") -- v2.15.1

    -- Preset selector defaults to first option
    if frame.usedplus_presetOption then
        frame.usedplus_presetOption:setState(1)
    end
end

--[[
    Called when updateGameSettings is triggered (refreshes UI)
]]
function UsedPlusSettingsMenuExtension:updateGameSettings()
    UsedPlusSettingsMenuExtension:updateSettingsUI(self)
end

--[[
    Callback handlers for toggle changes
]]
function UsedPlusSettingsMenuExtension:onPresetChanged(state)
    local presetKey = UsedPlusSettingsMenuExtension.presetKeys[state]
    if presetKey and UsedPlusSettings then
        UsedPlusSettings:applyPreset(presetKey)
        local currentPage = g_gui.currentGui and g_gui.currentGui.target and g_gui.currentGui.target.currentPage
        if currentPage then
            UsedPlusSettingsMenuExtension:updateSettingsUI(currentPage)
        end
    end
end

function UsedPlusSettingsMenuExtension:onFinanceToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enableFinanceSystem", state == BinaryOptionElement.STATE_RIGHT)
    end
end

function UsedPlusSettingsMenuExtension:onLeaseToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enableLeaseSystem", state == BinaryOptionElement.STATE_RIGHT)
    end
end

function UsedPlusSettingsMenuExtension:onSearchToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enableUsedVehicleSearch", state == BinaryOptionElement.STATE_RIGHT)
    end
end

function UsedPlusSettingsMenuExtension:onSaleToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enableVehicleSaleSystem", state == BinaryOptionElement.STATE_RIGHT)
    end
end

function UsedPlusSettingsMenuExtension:onRepairToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enableRepairSystem", state == BinaryOptionElement.STATE_RIGHT)
    end
end

function UsedPlusSettingsMenuExtension:onTradeinToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enableTradeInSystem", state == BinaryOptionElement.STATE_RIGHT)
    end
end

function UsedPlusSettingsMenuExtension:onCreditToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enableCreditSystem", state == BinaryOptionElement.STATE_RIGHT)
    end
end

function UsedPlusSettingsMenuExtension:onTirewearToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enableTireWearSystem", state == BinaryOptionElement.STATE_RIGHT)
    end
end

function UsedPlusSettingsMenuExtension:onMalfunctionsToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enableMalfunctionsSystem", state == BinaryOptionElement.STATE_RIGHT)
    end
end

-- v2.8.0: Malfunction Frequency slider
function UsedPlusSettingsMenuExtension:onMalfunctionFrequencyChanged(state)
    if UsedPlusSettings then
        local values = UsedPlusSettingsMenuExtension.ranges.malfunctionFrequencyValues
        local value = values[state] or 1.0
        UsedPlusSettings:set("malfunctionFrequencyMultiplier", value)
    end
end

-- v2.15.1: Fluid Drain Rate slider
function UsedPlusSettingsMenuExtension:onFluidDrainRateChanged(state)
    if UsedPlusSettings then
        local value = UsedPlusSettingsMenuExtension.ranges.fluidDrainRateValues[state]
        UsedPlusSettings:set("fluidDrainRateMultiplier", value)
    end
end

-- v2.0.0: NEW - Partial Repair toggle
function UsedPlusSettingsMenuExtension:onPartialRepairToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enablePartialRepair", state == BinaryOptionElement.STATE_RIGHT)
    end
end

-- v2.0.0: NEW - Partial Repaint toggle
function UsedPlusSettingsMenuExtension:onPartialRepaintToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enablePartialRepaint", state == BinaryOptionElement.STATE_RIGHT)
    end
end

-- v2.0.0: NEW - Farmland Difficulty Scaling toggle
function UsedPlusSettingsMenuExtension:onFarmlandDifficultyToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enableFarmlandDifficultyScaling", state == BinaryOptionElement.STATE_RIGHT)
    end
end

-- v2.0.0: NEW - Bank Interest toggle
function UsedPlusSettingsMenuExtension:onBankInterestToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enableBankInterest", state == BinaryOptionElement.STATE_RIGHT)
    end
end

-- v2.6.2: NEW - RVB Integration toggle
function UsedPlusSettingsMenuExtension:onRVBIntegrationToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enableRVBIntegration", state == BinaryOptionElement.STATE_RIGHT)
        -- Refresh ModCompatibility flags
        if ModCompatibility and ModCompatibility.refreshIntegrationSettings then
            ModCompatibility.refreshIntegrationSettings()
        end
    end
end

-- v2.6.2: NEW - UYT Integration toggle
function UsedPlusSettingsMenuExtension:onUYTIntegrationToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enableUYTIntegration", state == BinaryOptionElement.STATE_RIGHT)
        -- Refresh ModCompatibility flags
        if ModCompatibility and ModCompatibility.refreshIntegrationSettings then
            ModCompatibility.refreshIntegrationSettings()
        end
    end
end

-- v2.6.2: NEW - AM Integration toggle
function UsedPlusSettingsMenuExtension:onAMIntegrationToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enableAMIntegration", state == BinaryOptionElement.STATE_RIGHT)
        -- Refresh ModCompatibility flags
        if ModCompatibility and ModCompatibility.refreshIntegrationSettings then
            ModCompatibility.refreshIntegrationSettings()
        end
    end
end

-- v2.6.2: NEW - HP Integration toggle
function UsedPlusSettingsMenuExtension:onHPIntegrationToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enableHPIntegration", state == BinaryOptionElement.STATE_RIGHT)
        -- Refresh ModCompatibility flags
        if ModCompatibility and ModCompatibility.refreshIntegrationSettings then
            ModCompatibility.refreshIntegrationSettings()
        end
    end
end

-- v2.6.2: NEW - BUE Integration toggle
function UsedPlusSettingsMenuExtension:onBUEIntegrationToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enableBUEIntegration", state == BinaryOptionElement.STATE_RIGHT)
        -- Refresh ModCompatibility flags
        if ModCompatibility and ModCompatibility.refreshIntegrationSettings then
            ModCompatibility.refreshIntegrationSettings()
        end
    end
end

-- v2.6.2: NEW - ELS Integration toggle
function UsedPlusSettingsMenuExtension:onELSIntegrationToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enableELSIntegration", state == BinaryOptionElement.STATE_RIGHT)
        -- Refresh ModCompatibility flags
        if ModCompatibility and ModCompatibility.refreshIntegrationSettings then
            ModCompatibility.refreshIntegrationSettings()
        end
    end
end

-- v2.15.2: NEW - Better Contracts Integration toggle
function UsedPlusSettingsMenuExtension:onBCIntegrationToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("enableBCIntegration", state == BinaryOptionElement.STATE_RIGHT)
        -- Refresh ModCompatibility flags
        if ModCompatibility and ModCompatibility.refreshIntegrationSettings then
            ModCompatibility.refreshIntegrationSettings()
        end
    end
end

-- v2.7.0: NEW - Shop Buy/Lease override toggle
function UsedPlusSettingsMenuExtension:onOverrideShopBuyLeaseToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("overrideShopBuyLease", state == BinaryOptionElement.STATE_RIGHT)
        UsedPlus.logInfo("Shop Buy/Lease override " .. (state == BinaryOptionElement.STATE_RIGHT and "enabled" or "disabled"))
    end
end

-- v2.7.0: RVB Repair override toggle
function UsedPlusSettingsMenuExtension:onOverrideRVBRepairToggleChanged(state)
    if UsedPlusSettings then
        UsedPlusSettings:set("overrideRVBRepair", state == BinaryOptionElement.STATE_RIGHT)
        UsedPlus.logInfo("RVB Repair override " .. (state == BinaryOptionElement.STATE_RIGHT and "enabled" or "disabled"))
    end
end

--[[
    Callback handlers for economic parameter changes
]]
function UsedPlusSettingsMenuExtension:onInterestRateChanged(state)
    if UsedPlusSettings then
        local value = UsedPlusSettingsMenuExtension.ranges.interestRateValues[state]
        UsedPlusSettings:set("baseInterestRate", value)
    end
end

function UsedPlusSettingsMenuExtension:onTradeInPercentChanged(state)
    if UsedPlusSettings then
        local value = UsedPlusSettingsMenuExtension.ranges.tradeInPercentValues[state]
        UsedPlusSettings:set("baseTradeInPercent", value)
    end
end

function UsedPlusSettingsMenuExtension:onRepairMultiplierChanged(state)
    if UsedPlusSettings then
        local value = UsedPlusSettingsMenuExtension.ranges.repairMultiplierValues[state]
        UsedPlusSettings:set("repairCostMultiplier", value)
    end
end

-- v2.0.0: NEW - Paint Cost Multiplier
function UsedPlusSettingsMenuExtension:onPaintMultiplierChanged(state)
    if UsedPlusSettings then
        local value = UsedPlusSettingsMenuExtension.ranges.paintMultiplierValues[state]
        UsedPlusSettings:set("paintCostMultiplier", value)
    end
end

function UsedPlusSettingsMenuExtension:onLeaseMarkupChanged(state)
    if UsedPlusSettings then
        local value = UsedPlusSettingsMenuExtension.ranges.leaseMarkupValues[state]
        UsedPlusSettings:set("leaseMarkupPercent", value)
    end
end

function UsedPlusSettingsMenuExtension:onMissedPaymentsChanged(state)
    if UsedPlusSettings then
        local value = UsedPlusSettingsMenuExtension.ranges.missedPaymentsValues[state]
        UsedPlusSettings:set("missedPaymentsToDefault", value)
    end
end

function UsedPlusSettingsMenuExtension:onDownPaymentChanged(state)
    if UsedPlusSettings then
        local value = UsedPlusSettingsMenuExtension.ranges.downPaymentValues[state]
        UsedPlusSettings:set("minDownPaymentPercent", value)
    end
end

function UsedPlusSettingsMenuExtension:onStartingCreditChanged(state)
    if UsedPlusSettings then
        local value = UsedPlusSettingsMenuExtension.ranges.startingCreditValues[state]
        UsedPlusSettings:set("startingCreditScore", value)
    end
end

function UsedPlusSettingsMenuExtension:onLatePenaltyChanged(state)
    if UsedPlusSettings then
        local value = UsedPlusSettingsMenuExtension.ranges.latePenaltyValues[state]
        UsedPlusSettings:set("latePaymentPenalty", value)
    end
end

-- v2.0.0: Updated to use renamed setting key
function UsedPlusSettingsMenuExtension:onSearchSuccessChanged(state)
    if UsedPlusSettings then
        local value = UsedPlusSettingsMenuExtension.ranges.searchSuccessValues[state]
        UsedPlusSettings:set("baseSearchSuccessPercent", value)
    end
end

-- v2.0.0: REMOVED - maxListings handler (setting removed from UI)

function UsedPlusSettingsMenuExtension:onOfferExpiryChanged(state)
    if UsedPlusSettings then
        local value = UsedPlusSettingsMenuExtension.ranges.offerExpiryValues[state]
        UsedPlusSettings:set("offerExpirationHours", value)
    end
end

function UsedPlusSettingsMenuExtension:onCommissionChanged(state)
    if UsedPlusSettings then
        local value = UsedPlusSettingsMenuExtension.ranges.commissionValues[state]
        UsedPlusSettings:set("agentCommissionPercent", value)
    end
end

function UsedPlusSettingsMenuExtension:onConditionMinChanged(state)
    if UsedPlusSettings then
        local value = UsedPlusSettingsMenuExtension.ranges.conditionMinValues[state]
        UsedPlusSettings:set("usedConditionMin", value)
    end
end

function UsedPlusSettingsMenuExtension:onConditionMaxChanged(state)
    if UsedPlusSettings then
        local value = UsedPlusSettingsMenuExtension.ranges.conditionMaxValues[state]
        UsedPlusSettings:set("usedConditionMax", value)
    end
end

function UsedPlusSettingsMenuExtension:onConditionMultiplierChanged(state)
    if UsedPlusSettings then
        local value = UsedPlusSettingsMenuExtension.ranges.conditionMultiplierValues[state]
        UsedPlusSettings:set("conditionPriceMultiplier", value)
    end
end

function UsedPlusSettingsMenuExtension:onBrandBonusChanged(state)
    if UsedPlusSettings then
        local value = UsedPlusSettingsMenuExtension.ranges.brandBonusValues[state]
        UsedPlusSettings:set("brandLoyaltyBonus", value)
    end
end

-- v2.0.0: NEW - Bank Interest Rate
function UsedPlusSettingsMenuExtension:onBankInterestRateChanged(state)
    if UsedPlusSettings then
        local value = UsedPlusSettingsMenuExtension.ranges.bankInterestRateValues[state]
        UsedPlusSettings:set("bankInterestRate", value)
    end
end

--[[
    Initialize hooks
    Called at file load time
]]
local function init()
    -- Hook into settings frame open to add our elements
    InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(
        InGameMenuSettingsFrame.onFrameOpen,
        UsedPlusSettingsMenuExtension.onFrameOpen
    )

    -- Hook into updateGameSettings to refresh our values
    InGameMenuSettingsFrame.updateGameSettings = Utils.appendedFunction(
        InGameMenuSettingsFrame.updateGameSettings,
        UsedPlusSettingsMenuExtension.updateGameSettings
    )

    UsedPlus.logInfo("UsedPlusSettingsMenuExtension hooks installed")
end

init()

UsedPlus.logInfo("UsedPlusSettingsMenuExtension loaded")
