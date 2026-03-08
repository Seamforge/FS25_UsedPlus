--[[
    FS25_UsedPlus - Inspection Report Dialog
    v2.6.0: Integrated with negotiation system

    Shows detailed inspection report for used vehicles before purchase.
    Reveals hidden reliability scores that player paid to inspect.
    Pattern from: ScreenElement (NOT MessageDialog - that causes conflicts)

    Responsibilities:
    - Display vehicle info and price
    - Show reliability ratings (engine, hydraulic, electrical)
    - v2.1.0: Show RVB parts breakdown when data available
    - v2.1.0: Show UYT tire conditions when data available
    - Display inspector notes based on condition
    - v2.6.0: "Make Offer" button opens NegotiationDialog instead of direct purchase
]]

InspectionReportDialog = {}
local InspectionReportDialog_mt = Class(InspectionReportDialog, ScreenElement)

-- Dialog instance
InspectionReportDialog.INSTANCE = nil

--[[
    Constructor - extends ScreenElement, NOT MessageDialog
]]
function InspectionReportDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or InspectionReportDialog_mt)

    self.listing = nil
    self.search = nil  -- v2.6.0: For negotiation flow
    self.onPurchaseCallback = nil
    self.callbackTarget = nil
    self.isBackAllowed = true

    return self
end

--[[
    Get singleton instance, creating if needed
]]
function InspectionReportDialog.getInstance()
    if InspectionReportDialog.INSTANCE == nil then
        InspectionReportDialog.INSTANCE = InspectionReportDialog.new()

        -- Load XML - use UsedPlus.MOD_DIR which persists after mod load
        local xmlPath = UsedPlus.MOD_DIR .. "gui/InspectionReportDialog.xml"
        g_gui:loadGui(xmlPath, "InspectionReportDialog", InspectionReportDialog.INSTANCE)
        -- Note: setupSystemIcons() is called in onCreate() for DialogLoader compatibility

        UsedPlus.logDebug("InspectionReportDialog created and loaded from: " .. xmlPath)
    end
    return InspectionReportDialog.INSTANCE
end

--[[
    Set up system icons for mechanical assessment section
    Icons must be set via Lua - XML paths don't work from ZIP mods
    Large input dialogs use section icons only (no header icon)
]]
function InspectionReportDialog:setupSystemIcons()
    local iconDir = UsedPlus.MOD_DIR .. "gui/icons/"

    -- Section header icons
    if self.vehicleSectionIcon ~= nil then
        self.vehicleSectionIcon:setImageFilename(iconDir .. "vehicle.dds")
    end
    if self.mechanicalSectionIcon ~= nil then
        self.mechanicalSectionIcon:setImageFilename(iconDir .. "sys_engine.dds")
    end
    if self.tireSectionIcon ~= nil then
        self.tireSectionIcon:setImageFilename(iconDir .. "fsk_tire.dds")
    end
    if self.mechanicSectionIcon ~= nil then
        self.mechanicSectionIcon:setImageFilename(iconDir .. "agent.dds")
    end
    if self.recommendSectionIcon ~= nil then
        self.recommendSectionIcon:setImageFilename(iconDir .. "lightbulb.dds")
    end

    -- Engine system icon
    if self.engineSystemIcon ~= nil then
        self.engineSystemIcon:setImageFilename(iconDir .. "sys_engine.dds")
    end

    -- Hydraulic system icon
    if self.hydraulicSystemIcon ~= nil then
        self.hydraulicSystemIcon:setImageFilename(iconDir .. "sys_hydraulic.dds")
    end

    -- Electrical system icon
    if self.electricalSystemIcon ~= nil then
        self.electricalSystemIcon:setImageFilename(iconDir .. "sys_electrical.dds")
    end

    UsedPlus.logDebug("InspectionReportDialog: System icons initialized")
end

--[[
    Show dialog with inspection data
    @param listing - The used vehicle listing with usedPlusData
    @param farmId - Farm ID for purchase and Go Back
    @param onPurchaseCallback - Function to call if player clicks Buy (from preview dialog)
    @param callbackTarget - Target object for callback (preview dialog instance)
    @param originalPurchaseCallback - Original callback from UsedVehicleManager
    @param originalCallbackTarget - Original target from UsedVehicleManager
]]
function InspectionReportDialog:show(listing, farmId, onPurchaseCallback, callbackTarget, originalPurchaseCallback, originalCallbackTarget)
    -- v2.7.0: Guard against incomplete inspections
    if listing == nil then
        UsedPlus.logWarn("InspectionReportDialog:show - No listing provided")
        return
    end

    -- Check if inspection is still pending
    if listing.inspectionState == "pending" then
        UsedPlus.logWarn("InspectionReportDialog:show - Inspection still in progress, cannot view report yet")
        g_currentMission:showBlinkingWarning(
            g_i18n:getText("usedplus_inspection_notReady") or "Inspection not yet complete!",
            3000
        )
        return
    end

    -- Check if inspection was actually done
    if listing.inspectionState ~= "complete" then
        UsedPlus.logWarn("InspectionReportDialog:show - Vehicle has not been inspected")
        g_currentMission:showBlinkingWarning(
            g_i18n:getText("usedplus_inspection_notDone") or "Vehicle has not been inspected!",
            3000
        )
        return
    end

    self.listing = listing
    self.farmId = farmId
    self.onPurchaseCallback = onPurchaseCallback
    self.callbackTarget = callbackTarget
    -- Store original callbacks for Go Back functionality
    self.originalPurchaseCallback = originalPurchaseCallback
    self.originalCallbackTarget = originalCallbackTarget

    UsedPlus.logDebug(string.format("InspectionReportDialog:show - listing=%s, farmId=%s",
        tostring(listing and listing.storeItemName), tostring(farmId)))

    g_gui:showDialog("InspectionReportDialog")
end

--[[
    Called when dialog is created by GUI system
    v2.8.0: Set up icons here instead of getInstance() for DialogLoader compatibility
    NOTE: ScreenElement doesn't have onCreate() in superclass - no super call needed
]]
function InspectionReportDialog:onCreate()
    -- Set up system icons (must be done via Lua, not XML paths)
    self:setupSystemIcons()
end

--[[
    Called when dialog opens
    NOTE: ScreenElement doesn't have onOpen() in superclass - no super call needed
]]
function InspectionReportDialog:onOpen()
    -- Update display with listing data
    if self.listing then
        self:updateDisplay()
    end
end

--[[
    Called when dialog closes
    NOTE: ScreenElement doesn't have onClose() in superclass - no super call needed
]]
function InspectionReportDialog:onClose()
    -- No superclass cleanup needed for ScreenElement
end

--[[
    Update all display elements with inspection data
    v2.9.1: Added tier-based reveal level filtering
]]
function InspectionReportDialog:updateDisplay()
    local listing = self.listing
    if listing == nil then return end

    -- v2.9.1: Get reveal level from inspection tier
    -- revealLevel 1 = Quick (overall only)
    -- revealLevel 2 = Standard (+ component details + RVB/tires)
    -- revealLevel 3 = Comprehensive (+ DNA hint + repair estimate)
    local revealLevel = 3  -- Default to full reveal for backwards compatibility
    if listing.inspectionTier and UsedPlusMaintenance and UsedPlusMaintenance.CONFIG then
        local tierConfig = UsedPlusMaintenance.CONFIG.inspectionTiers[listing.inspectionTier]
        if tierConfig and tierConfig.revealLevel then
            revealLevel = tierConfig.revealLevel
        end
    end
    UsedPlus.logDebug(string.format("InspectionReportDialog: tier=%s, revealLevel=%d",
        tostring(listing.inspectionTier), revealLevel))

    -- Get store item for image
    local storeItem = g_storeManager:getItemByXMLFilename(listing.storeItemIndex)

    -- Vehicle name
    if self.vehicleNameText then
        self.vehicleNameText:setText(listing.storeItemName or g_i18n:getText("usedplus_common_unknownVehicle"))
    end

    -- Vehicle details
    if self.vehicleDetailsText then
        local hours = listing.operatingHours or 0
        local age = listing.age or 0
        local damage = math.floor((listing.damage or 0) * 100)
        self.vehicleDetailsText:setText(string.format(g_i18n:getText("usedplus_ir_vehicleDetailsFormat"),
            hours, age, damage))
    end

    -- Listed Price (seller's asking price)
    local listedPrice = listing.price or 0
    if self.priceText then
        self.priceText:setText(g_i18n:formatMoney(listedPrice, 0, true, true))
    end

    -- Vehicle image
    if self.vehicleImage and storeItem then
        local imagePath = storeItem.imageFilename
        if imagePath then
            self.vehicleImage:setImageFilename(imagePath)
        end
    end

    -- Update reliability displays
    local usedPlusData = listing.usedPlusData
    local engineRel = 0.5
    local hydraulicRel = 0.5
    local electricalRel = 0.5

    if usedPlusData then
        engineRel = usedPlusData.engineReliability or 1.0
        hydraulicRel = usedPlusData.hydraulicReliability or 1.0
        electricalRel = usedPlusData.electricalReliability or 1.0

        -- v2.9.1: Component reliability only shown for Standard+ (revealLevel >= 2)
        if revealLevel >= 2 then
            self:updateReliabilityRating("engine", engineRel)
            self:updateReliabilityRating("hydraulic", hydraulicRel)
            self:updateReliabilityRating("electrical", electricalRel)
            -- Show component containers
            self:setComponentsVisible(true)
        else
            -- Quick inspection - hide individual components
            self:setComponentsVisible(false)
        end

        -- v2.9.1: Mechanic quote/DNA hint only for Comprehensive (revealLevel >= 3)
        if self.mechanicQuoteText then
            if revealLevel >= 3 then
                -- v2.10.1: Use saved quote if available (prevents re-rolling exploit)
                local quote = listing.mechanicQuote
                if not quote then
                    -- Fallback: generate if not saved (shouldn't happen after inspection completes)
                    quote = "Vehicle condition assessed."
                    if usedPlusData.workhorseLemonScale and UsedPlusMaintenance and UsedPlusMaintenance.getInspectorQuote then
                        quote = UsedPlusMaintenance.getInspectorQuote(usedPlusData.workhorseLemonScale)
                        listing.mechanicQuote = quote  -- Save for next time
                        UsedPlus.logDebug("Generated mechanic quote on-the-fly (should have been saved at inspection completion)")
                    end
                end
                self.mechanicQuoteText:setText('"' .. quote .. '"')
                self.mechanicQuoteText:setVisible(true)
            else
                -- Hide mechanic quote for Quick/Standard
                self.mechanicQuoteText:setVisible(false)
            end
        end

        -- v2.9.1: Fluid assessment only for Standard+ (revealLevel >= 2)
        if self.fluidAssessmentText then
            if revealLevel >= 2 then
                -- v2.10.1: Use saved fluid assessment if available (prevents re-rolling exploit)
                local fluidComment = listing.fluidAssessment
                if not fluidComment then
                    -- Fallback: generate if not saved (shouldn't happen after inspection completes)
                    if UsedPlusMaintenance and UsedPlusMaintenance.getFluidInspectorComment then
                        fluidComment = UsedPlusMaintenance.getFluidInspectorComment(usedPlusData)
                        listing.fluidAssessment = fluidComment  -- Save for next time
                        if fluidComment then
                            UsedPlus.logDebug("Generated fluid assessment on-the-fly (should have been saved at inspection completion)")
                        end
                    end
                end
                if fluidComment then
                    self.fluidAssessmentText:setText(fluidComment)
                    -- Color based on severity
                    if usedPlusData.hasOilLeak or usedPlusData.hasHydraulicLeak or usedPlusData.hasFuelLeak then
                        self.fluidAssessmentText:setTextColor(1, 0.4, 0.4, 1)  -- Red
                    elseif (usedPlusData.oilLevel or 1) < 0.5 or (usedPlusData.hydraulicFluidLevel or 1) < 0.5 then
                        self.fluidAssessmentText:setTextColor(1, 0.7, 0.3, 1)  -- Orange
                    else
                        self.fluidAssessmentText:setTextColor(0.7, 0.9, 0.7, 1)  -- Green
                    end
                    self.fluidAssessmentText:setVisible(true)
                end
            else
                self.fluidAssessmentText:setVisible(false)
            end
        end

        -- Legacy notes elements (keep for compatibility, may be removed later)
        if self.notesText then
            self.notesText:setText("")
        end
        if self.notesText2 then
            self.notesText2:setText("")
        end
    else
        -- No inspection data - show defaults
        if revealLevel >= 2 then
            self:updateReliabilityRating("engine", 0.5)
            self:updateReliabilityRating("hydraulic", 0.5)
            self:updateReliabilityRating("electrical", 0.5)
            self:setComponentsVisible(true)
        else
            self:setComponentsVisible(false)
        end

        if self.mechanicQuoteText then
            if revealLevel >= 3 then
                self.mechanicQuoteText:setText('"' .. g_i18n:getText("usedplus_inspection_noData") .. '"')
                self.mechanicQuoteText:setVisible(true)
            else
                self.mechanicQuoteText:setVisible(false)
            end
        end
    end

    -- v2.9.1: RVB parts and tire conditions only for Standard+ (revealLevel >= 2)
    if revealLevel >= 2 then
        -- v2.1.2: Integrate RVB parts INTO mechanical assessment
        self:displayIntegratedRVBData(listing)
        -- v2.1.0: Display tire conditions if data exists
        self:displayTireConditions(listing)
    else
        -- Hide RVB/tire sections for Quick inspection
        self:hideRVBAndTireSections()
    end

    -- Calculate overall condition and costs
    local avgReliability = (engineRel + hydraulicRel + electricalRel) / 3
    local overallPercent = math.floor(avgReliability * 100)

    -- Overall rating
    if self.overallRatingText then
        self.overallRatingText:setText(string.format("%d%%", overallPercent))
        if avgReliability >= 0.7 then
            self.overallRatingText:setTextColor(0.3, 1, 0.4, 1)  -- Green
        elseif avgReliability >= 0.5 then
            self.overallRatingText:setTextColor(1, 0.85, 0.2, 1)  -- Gold
        else
            self.overallRatingText:setTextColor(1, 0.4, 0.4, 1)  -- Red
        end
    end

    -- v2.9.1: Repair cost and post-repair value only for Comprehensive (revealLevel >= 3)
    if revealLevel >= 3 then
        local repairDeficit = 1.0 - avgReliability
        local basePrice = storeItem and storeItem.price or listedPrice * 1.5
        local estimatedRepairCost = math.floor(basePrice * repairDeficit * 0.15)

        if self.repairCostText then
            self.repairCostText:setText(g_i18n:formatMoney(estimatedRepairCost, 0, true, true))
            self.repairCostText:setVisible(true)
        end
        if self.repairCostLabel then
            self.repairCostLabel:setVisible(true)
        end

        local postRepairValue = math.floor(listedPrice + (estimatedRepairCost * 0.5))
        if self.postRepairValueText then
            self.postRepairValueText:setText(g_i18n:formatMoney(postRepairValue, 0, true, true))
            self.postRepairValueText:setVisible(true)
        end
        if self.postRepairValueLabel then
            self.postRepairValueLabel:setVisible(true)
        end
    else
        -- Hide repair estimates for Quick/Standard
        if self.repairCostText then self.repairCostText:setVisible(false) end
        if self.repairCostLabel then self.repairCostLabel:setVisible(false) end
        if self.postRepairValueText then self.postRepairValueText:setVisible(false) end
        if self.postRepairValueLabel then self.postRepairValueLabel:setVisible(false) end
    end

    -- Generate recommendation based on overall condition (shown for ALL tiers)
    if self.recommendationText then
        if avgReliability >= 0.75 then
            self.recommendationText:setText(g_i18n:getText("usedplus_inspection_rec_excellent"))
            self.recommendationText:setTextColor(0.4, 1, 0.5, 1)
        elseif avgReliability >= 0.6 then
            self.recommendationText:setText(g_i18n:getText("usedplus_inspection_rec_good"))
            self.recommendationText:setTextColor(0.8, 1, 0.7, 1)
        elseif avgReliability >= 0.45 then
            self.recommendationText:setText(g_i18n:getText("usedplus_inspection_rec_fair"))
            self.recommendationText:setTextColor(1, 0.85, 0.4, 1)
        else
            self.recommendationText:setText(g_i18n:getText("usedplus_inspection_rec_poor"))
            self.recommendationText:setTextColor(1, 0.5, 0.4, 1)
        end
    end
end

--[[
    Update a single reliability rating display
    @param componentType - "engine", "hydraulic", or "electrical"
    @param reliability - 0.0 to 1.0
]]
function InspectionReportDialog:updateReliabilityRating(componentType, reliability)
    local percentage = math.floor(reliability * 100)

    -- Get rating text (safely handle if function doesn't exist)
    local ratingText = g_i18n:getText("usedplus_condition_unknown") or "?"
    if UsedPlusMaintenance and UsedPlusMaintenance.getRatingText then
        ratingText = UsedPlusMaintenance.getRatingText(reliability)
    elseif reliability >= 0.75 then
        ratingText = g_i18n:getText("usedplus_condition_excellent")
    elseif reliability >= 0.6 then
        ratingText = g_i18n:getText("usedplus_condition_good")
    elseif reliability >= 0.45 then
        ratingText = g_i18n:getText("usedplus_condition_fair")
    elseif reliability >= 0.3 then
        ratingText = g_i18n:getText("usedplus_condition_poor")
    else
        ratingText = g_i18n:getText("usedplus_condition_critical")
    end

    -- Determine color based on rating
    local r, g, b = 1, 1, 1
    if reliability >= 0.7 then
        r, g, b = 0.3, 1, 0.4  -- Green
    elseif reliability >= 0.5 then
        r, g, b = 1, 0.85, 0.2  -- Gold
    elseif reliability >= 0.35 then
        r, g, b = 1, 0.6, 0.3  -- Orange
    else
        r, g, b = 1, 0.4, 0.4  -- Red
    end

    -- Update percentage text
    local percentElement = self[componentType .. "RatingText"]
    if percentElement then
        percentElement:setText(string.format("%d%%", percentage))
        percentElement:setTextColor(r, g, b, 1)
    end

    -- Update status text (separate element)
    local statusElement = self[componentType .. "StatusText"]
    if statusElement then
        statusElement:setText(ratingText)
        statusElement:setTextColor(r, g, b, 1)
    end
end

--[[
    v2.9.1: Show/hide component reliability sections
    Used for tier-based reveal levels
]]
function InspectionReportDialog:setComponentsVisible(visible)
    -- Engine section
    if self.engineSection then self.engineSection:setVisible(visible) end
    if self.engineRatingText then self.engineRatingText:setVisible(visible) end
    if self.engineStatusText then self.engineStatusText:setVisible(visible) end
    if self.engineLabel then self.engineLabel:setVisible(visible) end

    -- Hydraulic section
    if self.hydraulicSection then self.hydraulicSection:setVisible(visible) end
    if self.hydraulicRatingText then self.hydraulicRatingText:setVisible(visible) end
    if self.hydraulicStatusText then self.hydraulicStatusText:setVisible(visible) end
    if self.hydraulicLabel then self.hydraulicLabel:setVisible(visible) end

    -- Electrical section
    if self.electricalSection then self.electricalSection:setVisible(visible) end
    if self.electricalRatingText then self.electricalRatingText:setVisible(visible) end
    if self.electricalStatusText then self.electricalStatusText:setVisible(visible) end
    if self.electricalLabel then self.electricalLabel:setVisible(visible) end

    -- Component containers (if they exist as grouping elements)
    if self.componentsContainer then self.componentsContainer:setVisible(visible) end
    if self.mechanicalAssessmentSection then self.mechanicalAssessmentSection:setVisible(visible) end
end

--[[
    v2.9.1: Hide RVB parts and tire condition sections
    Used for Quick inspection tier
]]
function InspectionReportDialog:hideRVBAndTireSections()
    -- RVB sub-components
    if self.engineSubComponentsContainer then self.engineSubComponentsContainer:setVisible(false) end
    if self.electricalSubComponentsContainer then self.electricalSubComponentsContainer:setVisible(false) end

    -- Individual RVB elements
    local rvbElements = {"engineCoreText", "thermostatText", "generatorText", "batteryText", "starterText", "glowPlugText"}
    for _, elemName in ipairs(rvbElements) do
        if self[elemName] then self[elemName]:setVisible(false) end
    end

    -- Tire section
    if self.tireSectionContainer then self.tireSectionContainer:setVisible(false) end
    if self.tireConditionsContainer then self.tireConditionsContainer:setVisible(false) end
end

--[[
    Calculate inspection cost
    Base $200 + 1% of vehicle price, capped at $2000
]]
function InspectionReportDialog.calculateInspectionCost(vehiclePrice)
    local baseCost = UsedPlusMaintenance.CONFIG.inspectionCostBase or 200
    local percentCost = (vehiclePrice or 0) * (UsedPlusMaintenance.CONFIG.inspectionCostPercent or 0.01)
    local totalCost = baseCost + percentCost
    return math.min(totalCost, 2000)
end

--[[
    Close this dialog
]]
function InspectionReportDialog:close()
    g_gui:closeDialogByName("InspectionReportDialog")
end

--[[
    Button handler: Make Offer - opens negotiation dialog
    v2.6.0: Changed from direct purchase to negotiation flow
]]
function InspectionReportDialog:onClickBuy()
    UsedPlus.logDebug("InspectionReportDialog: onClickBuy (Make Offer) called")

    local listing = self.listing
    if listing == nil then
        UsedPlus.logWarn("InspectionReportDialog: No listing available!")
        return
    end

    -- Check if negotiation is locked (seller walked away)
    if listing.negotiationLocked then
        local currentTime = 0
        if g_currentMission and g_currentMission.environment then
            currentTime = g_currentMission.environment.dayTime or 0
        end

        if currentTime < (listing.negotiationLockExpires or 0) then
            -- Still locked - show message
            local remainingMs = (listing.negotiationLockExpires or 0) - currentTime
            local remainingMins = math.ceil(remainingMs / 60000)
            InfoDialog.show(string.format(g_i18n:getText("usedplus_negotiation_locked") or "Seller is unavailable. Try again in %d minutes.", remainingMins))
            return
        else
            -- Lock expired
            listing.negotiationLocked = false
            listing.negotiationLockExpires = 0
        end
    end

    -- Store current state for callback
    -- CRITICAL FIX: Use originalPurchaseCallback (the REAL callback from UsedVehicleManager)
    -- NOT self.onPurchaseCallback (which is the intermediate onInspectionComplete callback)
    local callback = self.originalPurchaseCallback  -- FIXED: was self.onPurchaseCallback
    local target = self.originalCallbackTarget      -- FIXED: was self.callbackTarget
    local search = self.search

    -- Close this dialog
    self:close()

    -- Create callback function for negotiation completion
    local negotiationCallback = function(negotiationTarget, completedListing, finalPrice)
        -- This callback is called when negotiation completes with purchase
        UsedPlus.logDebug(string.format("Negotiation callback: finalPrice=$%d", finalPrice or 0))

        if finalPrice and completedListing then
            -- Update listing price to the negotiated amount
            completedListing.price = finalPrice

            -- Call original callback to complete purchase
            -- v2.11.0 FIX: VehicleSpawning callback expects (confirmed, listing), not (target, confirmed, listing)
            -- The callback signature is: function(confirmed, resultListing)
            if callback then
                callback(true, completedListing)
            end
        end
    end

    -- Open NegotiationDialog via DialogLoader
    DialogLoader.show("NegotiationDialog", "setData",
        listing,
        search,
        negotiationCallback,
        self
    )
end

--[[
    Button handler: Decline - reject the offer entirely
]]
function InspectionReportDialog:onClickDecline()
    UsedPlus.logDebug("InspectionReportDialog: onClickDecline called")
    self:close()

    if self.onPurchaseCallback then
        if self.callbackTarget then
            self.onPurchaseCallback(self.callbackTarget, false, self.listing)
        else
            self.onPurchaseCallback(false, self.listing)
        end
    end
end

--[[
    Button handler: Go Back - return to UsedVehiclePreviewDialog
]]
function InspectionReportDialog:onClickGoBack()
    UsedPlus.logDebug("InspectionReportDialog: onClickGoBack called")

    local listing = self.listing
    local farmId = self.farmId
    local callback = self.originalPurchaseCallback
    local target = self.originalCallbackTarget

    self:close()

    -- v2.7.3: Use DialogLoader.show() for consistency (fixes instance mismatch bug)
    DialogLoader.show("UsedVehiclePreviewDialog", "show",
        listing, farmId, callback, target)
end

--[[
    Handle ESC key - same as Go Back
]]
function InspectionReportDialog:onClickBack()
    self:onClickGoBack()
end

--[[
    Legacy handler for old XML
]]
function InspectionReportDialog:onClickCancel()
    self:onClickDecline()
end

--[[
    v2.1.2: Display INTEGRATED RVB data within Mechanical Assessment
    Instead of a separate section, shows RVB parts as sub-components under Engine/Electrical

    Layout when RVB data exists:
    - Engine section shows: Engine Core, Thermostat
    - Electrical section shows: Generator, Battery, Starter, Glow Plug
    - Hydraulic remains as-is (RVB doesn't track it)

    The main Engine/Hydraulic/Electrical percentages are now DERIVED from RVB parts
    (see UsedVehicleManager.generateUsedVehicleListingFromData)
]]
function InspectionReportDialog:displayIntegratedRVBData(listing)
    local rvbData = listing.rvbPartsData

    -- v2.8.0: Check if RVB integration is enabled in settings
    -- v2.9.1: Also require RVB mod to actually be installed - don't show synthetic data without RVB
    local rvbSettingEnabled = not UsedPlusSettings or UsedPlusSettings:get("enableRVBIntegration") ~= false
    local rvbModInstalled = ModCompatibility and ModCompatibility.rvbInstalled or false
    local hasRvbData = rvbSettingEnabled and rvbModInstalled and rvbData ~= nil and next(rvbData) ~= nil

    -- Debug logging to diagnose blank RVB section
    UsedPlus.logDebug(string.format("displayIntegratedRVBData: hasRvbData=%s, rvbInstalled=%s, rvbData=%s",
        tostring(hasRvbData), tostring(rvbModInstalled), tostring(rvbData ~= nil and "exists" or "nil")))
    UsedPlus.logDebug(string.format("  engineSubComponentsContainer=%s, electricalSubComponentsContainer=%s",
        tostring(self.engineSubComponentsContainer ~= nil),
        tostring(self.electricalSubComponentsContainer ~= nil)))

    -- Hide the old separate RVB section (if it exists in XML)
    if self.rvbSectionContainer then
        self.rvbSectionContainer:setVisible(false)
    end

    -- Show/hide the integrated sub-component elements
    if self.engineSubComponentsContainer then
        self.engineSubComponentsContainer:setVisible(hasRvbData)
        UsedPlus.logDebug("  Set engineSubComponentsContainer visible=" .. tostring(hasRvbData))
    end
    if self.electricalSubComponentsContainer then
        self.electricalSubComponentsContainer:setVisible(hasRvbData)
        UsedPlus.logDebug("  Set electricalSubComponentsContainer visible=" .. tostring(hasRvbData))
    end

    if not hasRvbData then
        UsedPlus.logDebug("  No RVB data - returning early")
        return
    end

    -- Display Engine sub-components (Engine Core + Thermostat)
    local engineParts = {
        { key = "ENGINE", element = "engineCoreText", label = "engineCoreLabel" },
        { key = "THERMOSTAT", element = "thermostatText", label = "thermostatLabel" }
    }
    for _, part in ipairs(engineParts) do
        local element = self[part.element]
        if element then
            local partData = rvbData[part.key]
            if partData then
                local life = partData.life or 1.0
                local lifePercent = math.floor(life * 100)
                local r, g, b = self:getConditionColor(life)
                element:setText(string.format("%d%%", lifePercent))
                element:setTextColor(r, g, b, 1)
            else
                element:setText("--")
                element:setTextColor(0.5, 0.5, 0.5, 1)
            end
        end
    end

    -- Display Electrical sub-components (Generator, Battery, Starter, Glow Plug)
    local electricalParts = {
        { key = "GENERATOR", element = "generatorText" },
        { key = "BATTERY", element = "batteryText" },
        { key = "SELFSTARTER", element = "starterText" },
        { key = "GLOWPLUG", element = "glowPlugText" }
    }
    for _, part in ipairs(electricalParts) do
        local element = self[part.element]
        if element then
            local partData = rvbData[part.key]
            if partData then
                local life = partData.life or 1.0
                local lifePercent = math.floor(life * 100)
                local r, g, b = self:getConditionColor(life)
                element:setText(string.format("%d%%", lifePercent))
                element:setTextColor(r, g, b, 1)
            else
                element:setText("--")
                element:setTextColor(0.5, 0.5, 0.5, 1)
            end
        end
    end

    UsedPlus.logDebug("InspectionReportDialog: Displayed integrated RVB component data")
end

--[[
    DEPRECATED: Old separate RVB section display
    Kept for backwards compatibility but now hidden - use displayIntegratedRVBData instead
]]
function InspectionReportDialog:displayRVBPartsData(listing)
    -- Redirect to integrated display
    self:displayIntegratedRVBData(listing)
end

--[[
    v2.1.0: Display tire conditions
    Shows per-wheel conditions when tireConditions exists in listing
]]
function InspectionReportDialog:displayTireConditions(listing)
    -- Check if listing has tire data
    local tireData = listing.tireConditions
    local hasTireData = tireData ~= nil and (tireData.FL or tireData.FR or tireData.RL or tireData.RR)

    -- Toggle visibility of tire section
    if self.tireSectionContainer then
        self.tireSectionContainer:setVisible(hasTireData)
    end

    if not hasTireData then
        return
    end

    -- Display each tire
    local tireElements = {
        { key = "FL", element = "tireFLText" },
        { key = "FR", element = "tireFRText" },
        { key = "RL", element = "tireRLText" },
        { key = "RR", element = "tireRRText" }
    }

    local worstCondition = 1.0
    local worstTire = nil

    for _, tireInfo in ipairs(tireElements) do
        local element = self[tireInfo.element]
        if element then
            local condition = tireData[tireInfo.key] or 1.0
            local conditionPercent = math.floor(condition * 100)
            local r, g, b = self:getConditionColor(condition)

            element:setText(string.format("%d%%", conditionPercent))
            element:setTextColor(r, g, b, 1)

            if condition < worstCondition then
                worstCondition = condition
                worstTire = tireInfo.key
            end
        end
    end

    -- Display worst tire indicator
    if self.tireWorstText and worstTire then
        local worstPercent = math.floor(worstCondition * 100)
        local r, g, b = self:getConditionColor(worstCondition)
        self.tireWorstText:setText(string.format("%s: %d%%", worstTire, worstPercent))
        self.tireWorstText:setTextColor(r, g, b, 1)
    end

    UsedPlus.logDebug("InspectionReportDialog: Displayed tire conditions")
end

--[[
    Helper: Get color based on condition value
    Green (good) -> Yellow -> Orange -> Red (critical)
]]
function InspectionReportDialog:getConditionColor(condition)
    if condition >= 0.75 then
        return 0.3, 1, 0.4  -- Green
    elseif condition >= 0.50 then
        return 1, 0.85, 0.2  -- Gold/Yellow
    elseif condition >= 0.30 then
        return 1, 0.6, 0.3  -- Orange
    else
        return 1, 0.4, 0.4  -- Red
    end
end

UsedPlus.logInfo("InspectionReportDialog loaded")
