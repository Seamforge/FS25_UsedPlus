--[[
    FS25_UsedPlus - Used Vehicle Preview Dialog
    v2.7.0: Tiered delayed inspection system

    Shows used vehicle details with option to inspect or buy as-is.
    This is the entry point for the inspection system.
    Pattern from: ScreenElement (NOT MessageDialog - that causes conflicts)

    Flow:
    1. Player views used vehicle listing
    2. This dialog shows visible stats + warning about hidden condition
    3. Player can:
       a) Buy As-Is - Purchase without knowing reliability
       b) Request Inspection - Choose tier (Quick/Standard/Comprehensive)
       c) View Report - If inspection is complete
       d) Cancel - Return to previous screen

    v2.7.0 Changes:
    - Inspections are no longer instant - they take game time
    - Three tiers with different costs, times, and data revealed
    - Shows progress when inspection is in progress
]]

UsedVehiclePreviewDialog = {}
local UsedVehiclePreviewDialog_mt = Class(UsedVehiclePreviewDialog, ScreenElement)

-- Dialog instance
UsedVehiclePreviewDialog.INSTANCE = nil

-- Month name abbreviations for expiration display
UsedVehiclePreviewDialog.MONTH_NAMES = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
}

--[[
    Constructor - extends ScreenElement, NOT MessageDialog
]]
function UsedVehiclePreviewDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or UsedVehiclePreviewDialog_mt)

    self.listing = nil
    self.search = nil  -- v2.7.0: Need search reference for inspection request
    self.farmId = nil
    self.onPurchaseCallback = nil
    self.callbackTarget = nil
    self.isBackAllowed = true

    -- v2.7.0: Tier costs calculated on show
    self.tierCosts = {}

    return self
end

--[[
    Get singleton instance, creating if needed
]]
function UsedVehiclePreviewDialog.getInstance()
    if UsedVehiclePreviewDialog.INSTANCE == nil then
        UsedVehiclePreviewDialog.INSTANCE = UsedVehiclePreviewDialog.new()

        -- Load XML - use UsedPlus.MOD_DIR which persists after mod load
        local xmlPath = UsedPlus.MOD_DIR .. "gui/UsedVehiclePreviewDialog.xml"
        g_gui:loadGui(xmlPath, "UsedVehiclePreviewDialog", UsedVehiclePreviewDialog.INSTANCE)

        UsedPlus.logDebug("UsedVehiclePreviewDialog created and loaded from: " .. xmlPath)
    end
    return UsedVehiclePreviewDialog.INSTANCE
end

--[[
    Show dialog for a used vehicle listing
    @param listing - The used vehicle listing data
    @param farmId - Farm ID of the buyer
    @param onPurchaseCallback - Function(confirmed, listing) called when dialog closes
    @param callbackTarget - Target object for callback
    @param search - (Optional) The search object containing this listing
]]
function UsedVehiclePreviewDialog:show(listing, farmId, onPurchaseCallback, callbackTarget, search)
    self.listing = listing
    self.farmId = farmId
    self.onPurchaseCallback = onPurchaseCallback
    self.callbackTarget = callbackTarget
    self.search = search

    -- v2.9.6: Check if this is a powered vehicle (has engine) vs implement
    local storeItem = g_storeManager:getItemByXMLFilename(listing.storeItemIndex)
    self.isPoweredVehicle = true  -- Default to powered
    if storeItem then
        -- Implements in category "TOOLS" don't have engines to inspect
        local category = storeItem.category or ""
        if category == "TOOLS" or category == "PLACEABLES" then
            self.isPoweredVehicle = false
            UsedPlus.logDebug(string.format("Non-powered implement detected: %s (category: %s) - inspections disabled",
                tostring(listing.storeItemName), category))
        end
    end

    -- v2.7.0: Calculate tier costs
    self.tierCosts = UsedPlusMaintenance.getInspectionTierOptions(listing.price or 0)

    g_gui:showDialog("UsedVehiclePreviewDialog")
end

--[[
    Called when dialog opens
]]
function UsedVehiclePreviewDialog:onOpen()
    UsedVehiclePreviewDialog:superClass().onOpen(self)

    if self.listing then
        self:updateDisplay()
    end
end

--[[
    Called when dialog closes
]]
function UsedVehiclePreviewDialog:onClose()
    UsedVehiclePreviewDialog:superClass().onClose(self)
end

--[[
    v2.7.0: Get current inspection state
    @return "none", "pending", or "complete"
]]
function UsedVehiclePreviewDialog:getInspectionState()
    local listing = self.listing
    if listing == nil then return "none" end

    if listing.inspectionState == "pending" then
        return "pending"
    end
    if listing.inspectionState == "complete" then
        return "complete"
    end

    return "none"
end

--[[
    Update all display elements
]]
function UsedVehiclePreviewDialog:updateDisplay()
    local listing = self.listing
    if listing == nil then return end

    -- Get store item for image
    local storeItem = g_storeManager:getItemByXMLFilename(listing.storeItemIndex)

    -- Title
    if self.titleText then
        self.titleText:setText(g_i18n:getText("usedplus_preview_title"))
    end

    -- Vehicle name
    if self.vehicleNameText then
        self.vehicleNameText:setText(listing.storeItemName or g_i18n:getText("usedplus_common_unknownVehicle"))
    end

    -- Price
    if self.priceText then
        self.priceText:setText(g_i18n:formatMoney(listing.price or 0, 0, true, true))
    end

    -- v2.10.0: Expiration info
    if self.expirationText and self.search then
        local foundMonth = listing.foundMonth or 0
        local expirationMonths = listing.expirationMonths or 3
        local currentMonth = self.search.monthsElapsed or 0
        local age = currentMonth - foundMonth
        local remaining = expirationMonths - age
        local expireMonth = foundMonth + expirationMonths

        if remaining > 0 then
            -- Convert month number to month name (wrap to 1-12 range)
            local monthIndex = ((expireMonth - 1) % 12) + 1
            local monthName = UsedVehiclePreviewDialog.MONTH_NAMES[monthIndex] or "Jan"

            self.expirationText:setText(string.format(g_i18n:getText("usedplus_uvp_expiresFormat"),
                remaining, remaining == 1 and "" or "s", monthName))
        else
            self.expirationText:setText(g_i18n:getText("usedplus_uvp_expired"))
        end
    end

    -- Vehicle image - use UIHelper pattern if available
    if self.vehicleImage and storeItem then
        if UIHelper and UIHelper.Image and UIHelper.Image.setStoreItemImage then
            UIHelper.Image.setStoreItemImage(self.vehicleImage, storeItem)
        else
            -- Fallback: set image directly
            local imagePath = storeItem.imageFilename
            if imagePath then
                self.vehicleImage:setImageFilename(imagePath)
            end
        end
    end

    -- Visible condition stats (values only - labels are in XML)
    if self.ageText then
        self.ageText:setText(string.format(g_i18n:getText("usedplus_preview_ageYears"), listing.age or 0))
    end

    if self.hoursText then
        local hours = listing.operatingHours or 0
        self.hoursText:setText(g_i18n:formatNumber(hours))
    end

    -- Show descriptive condition instead of exact percentages (as if visually inspected)
    if self.damageText then
        local damageDesc = self:getConditionDescription(listing.damage or 0, "mechanical")
        self.damageText:setText(damageDesc)
    end

    if self.wearText then
        local wearDesc = self:getConditionDescription(listing.wear or 0, "cosmetic")
        self.wearText:setText(wearDesc)
    end

    -- v2.7.0: Update based on inspection state
    local inspectionState = self:getInspectionState()

    -- Update section visibility based on state
    self:updateInspectionSections(inspectionState)

    -- Update buttons based on state
    self:updateButtons(inspectionState)
end

--[[
    v2.7.0: Update inspection section visibility
    v2.9.6: Hide ALL inspection UI for non-powered implements
]]
function UsedVehiclePreviewDialog:updateInspectionSections(inspectionState)
    local listing = self.listing

    -- v2.9.6: For non-powered implements, hide ALL inspection UI
    if not self.isPoweredVehicle then
        -- Hide warning section
        if self.warningBg then self.warningBg:setVisible(false) end
        if self.warningIcon then self.warningIcon:setVisible(false) end
        if self.warningText then self.warningText:setVisible(false) end
        if self.inspectPrompt then self.inspectPrompt:setVisible(false) end
        self:hideTierButtons()

        -- Hide progress section
        if self.progressSection then self.progressSection:setVisible(false) end

        -- Hide inspected section
        if self.inspectedSection then self.inspectedSection:setVisible(false) end

        -- Show informational message instead
        if self.warningText then
            self.warningText:setVisible(true)
            self.warningText:setText(g_i18n:getText("usedplus_preview_implementNoInspection") or
                "Inspections not available for non-powered implements. Buy as-is only.")
        end
        return
    end

    -- Normal flow for powered vehicles
    -- Warning section (not inspected)
    local showWarning = (inspectionState == "none")
    if self.warningBg then self.warningBg:setVisible(showWarning) end
    if self.warningIcon then self.warningIcon:setVisible(showWarning) end
    if self.warningText then self.warningText:setVisible(showWarning) end
    if self.inspectPrompt then self.inspectPrompt:setVisible(showWarning) end

    -- v2.7.0: Update tier button text with costs and times
    if showWarning then
        self:updateTierButtons()
    else
        -- Hide all tier button elements when not in "none" state (3-layer pattern)
        self:hideTierButtons()
    end

    -- Progress section (inspection pending)
    local showProgress = (inspectionState == "pending")
    if self.progressSection then
        self.progressSection:setVisible(showProgress)
    end
    if showProgress and self.progressText then
        local hoursRemaining = 0
        if g_usedVehicleManager then
            hoursRemaining = g_usedVehicleManager:getInspectionHoursRemaining(listing)
        end
        local tierName = "Standard"
        if listing.inspectionTier and UsedPlusMaintenance.CONFIG.inspectionTiers[listing.inspectionTier] then
            tierName = UsedPlusMaintenance.CONFIG.inspectionTiers[listing.inspectionTier].name
        end
        local progressMsg = string.format(
            g_i18n:getText("usedplus_preview_inspectionProgress") or "%s inspection in progress... ~%d hrs remaining",
            tierName, hoursRemaining
        )
        self.progressText:setText(progressMsg)
    end

    -- Inspected section (complete)
    local showInspected = (inspectionState == "complete")
    if self.inspectedSection then
        self.inspectedSection:setVisible(showInspected)
    end
end

--[[
    v2.7.0: Update tier button text with costs and duration
    Uses 3-layer pattern: Bitmap (bg) + Button (hit) + Text (label)
]]
function UsedVehiclePreviewDialog:updateTierButtons()
    -- 3-layer elements for each tier
    local tierButtons = {
        { bg = self.tierQuickBg, button = self.tierQuickButton, text = self.tierQuickText, index = 1 },
        { bg = self.tierStandardBg, button = self.tierStandardButton, text = self.tierStandardText, index = 2 },
        { bg = self.tierComprehensiveBg, button = self.tierComprehensiveButton, text = self.tierComprehensiveText, index = 3 }
    }

    for _, tierData in ipairs(tierButtons) do
        local tierInfo = self.tierCosts[tierData.index]

        if tierInfo then
            -- Format: "Quick $1,234 (~2h)"
            local buttonText = string.format("%s %s (~%dh)",
                tierInfo.name,
                g_i18n:formatMoney(tierInfo.cost, 0, true, true),
                tierInfo.durationHours
            )

            -- Set text on the Text element (NOT the Button!)
            if tierData.text then
                tierData.text:setText(buttonText)
                tierData.text:setVisible(true)
            end

            -- Show background and button hit area
            if tierData.bg then tierData.bg:setVisible(true) end
            if tierData.button then tierData.button:setVisible(true) end
        else
            -- Hide all 3 elements
            if tierData.bg then tierData.bg:setVisible(false) end
            if tierData.button then tierData.button:setVisible(false) end
            if tierData.text then tierData.text:setVisible(false) end
        end
    end
end

--[[
    v2.7.0: Hide all tier button elements (3-layer pattern)
]]
function UsedVehiclePreviewDialog:hideTierButtons()
    -- Hide all 9 elements (3 tiers × 3 elements each)
    if self.tierQuickBg then self.tierQuickBg:setVisible(false) end
    if self.tierQuickButton then self.tierQuickButton:setVisible(false) end
    if self.tierQuickText then self.tierQuickText:setVisible(false) end

    if self.tierStandardBg then self.tierStandardBg:setVisible(false) end
    if self.tierStandardButton then self.tierStandardButton:setVisible(false) end
    if self.tierStandardText then self.tierStandardText:setVisible(false) end

    if self.tierComprehensiveBg then self.tierComprehensiveBg:setVisible(false) end
    if self.tierComprehensiveButton then self.tierComprehensiveButton:setVisible(false) end
    if self.tierComprehensiveText then self.tierComprehensiveText:setVisible(false) end
end

--[[
    v2.7.0: Tier button hover handler - highlight background
]]
function UsedVehiclePreviewDialog:onTierBtnHighlight(element)
    -- Get the corresponding background element by ID
    local bgElement = nil
    if element == self.tierQuickButton then
        bgElement = self.tierQuickBg
    elseif element == self.tierStandardButton then
        bgElement = self.tierStandardBg
    elseif element == self.tierComprehensiveButton then
        bgElement = self.tierComprehensiveBg
    end

    -- Lighten the background color on hover
    if bgElement then
        bgElement:setImageColor(nil, 0.20, 0.25, 0.20, 1)
    end
end

--[[
    v2.7.0: Tier button unhighlight handler - restore background
]]
function UsedVehiclePreviewDialog:onTierBtnUnhighlight(element)
    -- Get the corresponding background element by ID
    local bgElement = nil
    if element == self.tierQuickButton then
        bgElement = self.tierQuickBg
    elseif element == self.tierStandardButton then
        bgElement = self.tierStandardBg
    elseif element == self.tierComprehensiveButton then
        bgElement = self.tierComprehensiveBg
    end

    -- Restore the original background color
    if bgElement then
        bgElement:setImageColor(nil, 0.12, 0.15, 0.12, 1)
    end
end

--[[
    v2.7.0: Update button states based on inspection state
    v2.7.3: Cancel button changes to "Close" when inspection is in progress/complete
]]
function UsedVehiclePreviewDialog:updateButtons(inspectionState)
    -- Update inspect button text based on state
    if self.inspectButton then
        if inspectionState == "complete" then
            -- Show "View Report" button
            self.inspectButton:setText(g_i18n:getText("usedplus_preview_viewReport") or "View Report")
            self.inspectButton:setDisabled(false)
            self.inspectButton:setVisible(true)
        elseif inspectionState == "pending" then
            -- Show disabled "In Progress" button
            self.inspectButton:setText(g_i18n:getText("usedplus_preview_inProgress") or "In Progress...")
            self.inspectButton:setDisabled(true)
            self.inspectButton:setVisible(true)
        else
            -- Hide button when "none" state - tier buttons are shown instead
            self.inspectButton:setVisible(false)
        end
    end

    -- v2.7.3: Update cancel button text - "Close" when inspection started, "Cancel" otherwise
    if self.cancelButton then
        if inspectionState == "pending" or inspectionState == "complete" then
            -- Inspection started - user is just closing, not canceling
            self.cancelButton:setText(g_i18n:getText("button_close") or "Close")
        else
            -- No inspection yet - this is truly a cancel
            self.cancelButton:setText(g_i18n:getText("button_cancel") or "Cancel")
        end
    end
end

--[[
    Close this dialog
]]
function UsedVehiclePreviewDialog:close()
    g_gui:closeDialogByName("UsedVehiclePreviewDialog")
end

--[[
    Button handler: Buy without inspection
]]
function UsedVehiclePreviewDialog:onClickBuyAsIs()
    self:close()

    -- Trigger purchase - callback is a CLOSURE, don't pass target!
    if self.onPurchaseCallback then
        UsedPlus.logDebug("onClickBuyAsIs: Triggering purchase callback")
        self.onPurchaseCallback(true, self.listing)
    end
end

--[[
    Button handler: Inspect button clicked
    v2.7.0: Only shown when inspection is complete (to view report)
    Tier buttons handle the initial tier selection
]]
function UsedVehiclePreviewDialog:onClickInspect()
    local listing = self.listing
    local inspectionState = self:getInspectionState()

    if inspectionState == "complete" then
        -- Already inspected - show the report
        self:close()
        -- v2.7.3: Use DialogLoader.show() for consistency (fixes instance mismatch bug)
        -- Note: InspectionReportDialog:show() signature:
        -- (listing, farmId, onPurchaseCallback, callbackTarget, originalPurchaseCallback, originalCallbackTarget)
        DialogLoader.show("InspectionReportDialog", "show",
            listing, self.farmId,
            self.onInspectionComplete, self,
            self.onPurchaseCallback, self.callbackTarget)
    elseif inspectionState == "pending" then
        -- In progress - do nothing (button should be disabled)
        g_currentMission:showBlinkingWarning(
            g_i18n:getText("usedplus_inspection_alreadyPending") or "Inspection already in progress!",
            3000
        )
    end
    -- "none" state is handled by tier buttons directly
end

--[[
    v2.7.0: Show tier selection dialog
    Uses InfoDialog with options to select inspection tier
]]
function UsedVehiclePreviewDialog:showTierSelectionDialog()
    local listing = self.listing

    -- Build options text
    local options = {}
    for i, tier in ipairs(self.tierCosts) do
        local tierConfig = UsedPlusMaintenance.CONFIG.inspectionTiers[i]
        local optionText = string.format("%s - %s (~%d hrs)",
            tier.name,
            g_i18n:formatMoney(tier.cost, 0, true, true),
            tier.durationHours
        )
        table.insert(options, { text = optionText, tier = i })
    end

    -- Show selection dialog using YesNoDialog pattern
    -- For now, we'll use a simpler approach: show 3 buttons on the dialog
    -- or use InfoDialog with callback

    -- Build description for each tier
    local tierDescriptions = {
        g_i18n:getText("usedplus_tier_quick_desc") or "Overall rating only",
        g_i18n:getText("usedplus_tier_standard_desc") or "Full reliability + parts condition",
        g_i18n:getText("usedplus_tier_comprehensive_desc") or "Full details + DNA hint + repair estimate"
    }

    local messageText = g_i18n:getText("usedplus_selectInspectionTier") or "Select Inspection Type:\n\n"
    for i, tier in ipairs(self.tierCosts) do
        messageText = messageText .. string.format("[%d] %s - %s (~%d hrs)\n    %s\n\n",
            i, tier.name,
            g_i18n:formatMoney(tier.cost, 0, true, true),
            tier.durationHours,
            tierDescriptions[i] or ""
        )
    end

    -- Use TextInputDialog approach or just cycle through with button clicks
    -- For MVP: Use InfoDialog and have 3 separate buttons call tier-specific handlers

    -- Show a yes/no dialog for the recommended (Standard) tier
    local standardTier = self.tierCosts[2]
    local confirmText = string.format(
        g_i18n:getText("usedplus_confirmInspection") or "Request %s inspection for %s?\n\nReady in ~%d hours.",
        standardTier.name,
        g_i18n:formatMoney(standardTier.cost, 0, true, true),
        standardTier.durationHours
    )

    -- Use the correct YesNoDialog.show(callback, target, text) pattern
    YesNoDialog.show(
        function(target, yes)
            if yes then
                self:requestInspectionTier(2)  -- Standard tier
            end
        end,
        self,
        confirmText
    )
end

--[[
    v2.7.0: Request inspection at specified tier
    @param tierIndex - 1=Quick, 2=Standard, 3=Comprehensive
]]
function UsedVehiclePreviewDialog:requestInspectionTier(tierIndex)
    local listing = self.listing

    if g_usedVehicleManager == nil then
        g_currentMission:showBlinkingWarning(g_i18n:getText("usedplus_error_systemUnavailable"), 3000)
        return
    end

    -- Request the inspection
    local success, errorMsg = g_usedVehicleManager:requestInspection(
        listing,
        self.search,
        tierIndex,
        self.farmId
    )

    if success then
        -- Refresh display to show pending state
        self:updateDisplay()
    else
        g_currentMission:showBlinkingWarning(
            string.format(g_i18n:getText("usedplus_inspection_failed") or "Inspection failed: %s", errorMsg or g_i18n:getText("usedplus_common_unknownError")),
            3000
        )
    end
end

--[[
    v2.7.0: Tier button handlers - show confirmation before requesting
]]
function UsedVehiclePreviewDialog:onClickTierQuick()
    self:confirmTierSelection(1)
end

function UsedVehiclePreviewDialog:onClickTierStandard()
    self:confirmTierSelection(2)
end

function UsedVehiclePreviewDialog:onClickTierComprehensive()
    self:confirmTierSelection(3)
end

--[[
    v2.7.0: Show confirmation dialog before requesting inspection
]]
function UsedVehiclePreviewDialog:confirmTierSelection(tierIndex)
    local tierInfo = self.tierCosts[tierIndex]
    if tierInfo == nil then
        UsedPlus.logError("Invalid tier index: " .. tostring(tierIndex))
        return
    end

    -- Build confirmation text with proper line breaks
    -- Note: XML translations use literal \n which must be converted to actual newlines
    local template = g_i18n:getText("usedplus_confirmInspection") or "Request %s inspection for %s?\n\nReady in ~%d hours."
    local confirmText = string.format(template,
        tierInfo.name,
        g_i18n:formatMoney(tierInfo.cost, 0, true, true),
        tierInfo.durationHours
    )
    -- Convert literal \n to actual newlines (XML doesn't interpret \n as escape sequence)
    confirmText = confirmText:gsub("\\n", "\n")

    YesNoDialog.show(
        function(target, yes)
            if yes then
                self:requestInspectionTier(tierIndex)
            end
        end,
        self,
        confirmText
    )
end

--[[
    Callback from inspection report dialog
]]
function UsedVehiclePreviewDialog:onInspectionComplete(confirmed, listing)
    UsedPlus.logDebug(string.format("UsedVehiclePreviewDialog:onInspectionComplete - confirmed=%s, listing=%s",
        tostring(confirmed), tostring(listing and listing.storeItemName)))

    if confirmed then
        -- Player wants to buy after seeing inspection
        UsedPlus.logDebug("onInspectionComplete: Player confirmed purchase")
        UsedPlus.logDebug(string.format("onInspectionComplete: self.onPurchaseCallback type = %s", type(self.onPurchaseCallback)))
        if self.onPurchaseCallback then
            -- IMPORTANT: The original callback from UsedVehicleManager is a CLOSURE
            -- that expects (confirmed, listing) - NOT a target parameter!
            -- Do NOT pass callbackTarget - it will shift the arguments!
            UsedPlus.logDebug("onInspectionComplete: Calling original callback (confirmed, listing)")
            local success, err = pcall(function()
                self.onPurchaseCallback(true, listing)
            end)
            if not success then
                UsedPlus.logError(string.format("onInspectionComplete: Callback failed with error: %s", tostring(err)))
            else
                UsedPlus.logDebug("onInspectionComplete: Callback completed successfully")
            end
        else
            UsedPlus.logWarn("onInspectionComplete: No onPurchaseCallback set!")
        end
    else
        -- Player declined - just log it, don't re-show (Decline means done)
        UsedPlus.logDebug("onInspectionComplete: Player declined purchase")
    end
end

--[[
    Button handler: Cancel
]]
function UsedVehiclePreviewDialog:onClickCancel()
    self:close()

    -- Callback is a CLOSURE, don't pass target!
    if self.onPurchaseCallback then
        self.onPurchaseCallback(false, self.listing)
    end
end

--[[
    Handle ESC key - same as cancel
]]
function UsedVehiclePreviewDialog:onClickBack()
    self:onClickCancel()
end

--[[
    Get descriptive condition text based on damage/wear value
    Simulates what a person would say looking at the vehicle visually (without exact measurements)
    @param value - 0-1 damage or wear value (0 = perfect, 1 = destroyed)
    @param conditionType - "mechanical" or "cosmetic"
    @return Descriptive string
]]
function UsedVehiclePreviewDialog:getConditionDescription(value, conditionType)
    local isMechanical = (conditionType == "mechanical")

    if value <= 0.05 then
        -- Nearly perfect
        return isMechanical and g_i18n:getText("usedplus_cond_excellent") or g_i18n:getText("usedplus_cond_likeNew")
    elseif value <= 0.15 then
        -- Very good
        return isMechanical and g_i18n:getText("usedplus_cond_veryGood") or g_i18n:getText("usedplus_cond_minorScratches")
    elseif value <= 0.30 then
        -- Good
        return isMechanical and g_i18n:getText("usedplus_cond_goodCondition") or g_i18n:getText("usedplus_cond_someWearVisible")
    elseif value <= 0.50 then
        -- Fair
        return isMechanical and g_i18n:getText("usedplus_cond_fairShowsUse") or g_i18n:getText("usedplus_cond_fadedNeedsTouchup")
    elseif value <= 0.70 then
        -- Worn
        return isMechanical and g_i18n:getText("usedplus_cond_wornNeedsWork") or g_i18n:getText("usedplus_cond_weatheredRepaintAdvised")
    else
        -- Poor
        return isMechanical and g_i18n:getText("usedplus_cond_poorMajorRepairs") or g_i18n:getText("usedplus_cond_poorSignificantFading")
    end
end

UsedPlus.logInfo("UsedVehiclePreviewDialog loaded")
