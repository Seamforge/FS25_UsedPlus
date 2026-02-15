--[[
    FS25_UsedPlus - Vehicle Inspection Module

    v2.7.2 REFACTORED: Extracted from UsedVehicleManager.lua

    Handles the inspection system for used vehicles:
    - requestInspection: Start an inspection for a listing
    - processInspectionCompletions: Check and complete pending inspections
    - notifyInspectionComplete: Notify player inspection is done
    - onInspectionCompleteDialogCallback: Handle dialog response
    - getInspectionHoursRemaining: Get remaining time
    - cancelInspection: Cancel a pending inspection
]]

-- Ensure UsedVehicleManager table exists
UsedVehicleManager = UsedVehicleManager or {}

--[[
    v2.7.0: Request an inspection for a listing
    @param listing - The listing to inspect
    @param search - The search containing this listing
    @param tierIndex - 1=Quick, 2=Standard, 3=Comprehensive
    @param farmId - Farm requesting the inspection
    @return success boolean, error message string
]]
function UsedVehicleManager:requestInspection(listing, search, tierIndex, farmId)
    if listing == nil then
        return false, "No listing provided"
    end

    -- Check if already inspected or inspection in progress
    if listing.inspectionState == "pending" then
        return false, "Inspection already in progress"
    end
    if listing.inspectionState == "complete" then
        return false, "Already inspected"
    end

    -- Get tier configuration
    local tier = UsedPlusMaintenance.CONFIG.inspectionTiers[tierIndex]
    if tier == nil then
        return false, "Invalid inspection tier"
    end

    -- Calculate cost
    local cost = UsedPlusMaintenance.calculateInspectionCostForTier(tierIndex, listing.price or 0)

    -- Check if farm can afford
    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then
        return false, "Invalid farm"
    end
    if farm.money < cost then
        return false, "Insufficient funds"
    end

    -- Deduct money
    g_currentMission:addMoney(-cost, farmId, MoneyType.OTHER, true, true)

    -- Calculate completion time
    local currentHour = self.totalGameHours or 0
    local completionHour = currentHour + tier.durationHours

    -- Update listing with inspection data
    listing.inspectionState = "pending"
    listing.inspectionTier = tierIndex
    listing.inspectionRequestedAtHour = currentHour
    listing.inspectionCompletesAtHour = completionHour
    listing.inspectionFarmId = farmId
    listing.inspectionCostPaid = cost
    listing.listingOnHold = true  -- Prevent expiration during inspection

    -- Track statistics
    if g_financeManager then
        g_financeManager:incrementStatistic(farmId, "inspectionsPurchased", 1)
        g_financeManager:incrementStatistic(farmId, "totalInspectionFees", cost)
    end

    UsedPlus.logDebug(string.format("Inspection requested: %s tier %d (%s), cost $%d, completes at hour %d",
        listing.storeItemName or listing.id, tierIndex, tier.name, cost, completionHour))

    -- Send notification
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format(g_i18n:getText("usedplus_inspection_started") or "Inspection started! Ready in ~%d hours.",
            tier.durationHours)
    )

    return true, nil
end

--[[
    v2.7.0: Process inspection completions
    Called every game hour to check if any pending inspections are now complete
]]
function UsedVehicleManager:processInspectionCompletions()
    local currentHour = self.totalGameHours or 0
    local completedCount = 0

    -- Iterate through all farms and their searches
    for _, farm in pairs(g_farmManager:getFarms()) do
        if farm.usedVehicleSearches then
            for _, search in ipairs(farm.usedVehicleSearches) do
                if search.foundListings then
                    for _, listing in ipairs(search.foundListings) do
                        -- Check if this listing has a pending inspection that should complete
                        if listing.inspectionState == "pending" and
                           listing.inspectionCompletesAtHour and
                           currentHour >= listing.inspectionCompletesAtHour then
                            -- Mark inspection as complete
                            listing.inspectionState = "complete"
                            listing.listingOnHold = false  -- Allow expiration again

                            -- v2.10.1: Generate and save mechanic's assessment quote (prevent re-rolling exploit)
                            -- Only generate if comprehensive inspection (tier 3) and not already saved
                            if listing.inspectionTier >= 3 and not listing.mechanicQuote then
                                local usedPlusData = listing.usedPlusData
                                if usedPlusData and usedPlusData.workhorseLemonScale and UsedPlusMaintenance and UsedPlusMaintenance.getInspectorQuote then
                                    listing.mechanicQuote = UsedPlusMaintenance.getInspectorQuote(usedPlusData.workhorseLemonScale)
                                    UsedPlus.logDebug(string.format("Generated mechanic quote for %s: '%s'", listing.storeItemName or "vehicle", listing.mechanicQuote))
                                end
                            end

                            -- v2.10.1: Generate and save fluid assessment (prevent re-rolling exploit)
                            -- Only generate if standard+ inspection (tier 2+) and not already saved
                            if listing.inspectionTier >= 2 and not listing.fluidAssessment then
                                local usedPlusData = listing.usedPlusData
                                if usedPlusData and UsedPlusMaintenance and UsedPlusMaintenance.getFluidInspectorComment then
                                    listing.fluidAssessment = UsedPlusMaintenance.getFluidInspectorComment(usedPlusData)
                                    if listing.fluidAssessment then
                                        UsedPlus.logDebug(string.format("Generated fluid assessment for %s: '%s'", listing.storeItemName or "vehicle", listing.fluidAssessment))
                                    end
                                end
                            end

                            completedCount = completedCount + 1

                            UsedPlus.logDebug(string.format("Inspection complete: %s (tier %d)",
                                listing.storeItemName or listing.id, listing.inspectionTier or 0))

                            -- Notify the farm that requested it
                            if listing.inspectionFarmId == farm.farmId then
                                self:notifyInspectionComplete(listing, search, farm.farmId)
                            end
                        end
                    end
                end
            end
        end
    end

    if completedCount > 0 then
        UsedPlus.logDebug(string.format("Processed %d inspection completion(s) at hour %d",
            completedCount, currentHour))
    end
end

--[[
    v2.7.0: Notify player that an inspection is complete
    v2.7.1: Now shows a popup dialog with option to view report immediately
    @param listing - The listing that was inspected
    @param search - The search containing this listing
    @param farmId - Farm that paid for the inspection
]]
function UsedVehicleManager:notifyInspectionComplete(listing, search, farmId)
    -- Only notify if game is running
    if g_currentMission == nil or g_currentMission.isLoading then
        return
    end

    -- Only notify the local player's farm
    if g_currentMission.player and g_currentMission.player.farmId ~= farmId then
        return
    end

    local vehicleName = listing.storeItemName or search.storeItemName or "Vehicle"
    local tierName = "Standard"
    if listing.inspectionTier and UsedPlusMaintenance.CONFIG.inspectionTiers[listing.inspectionTier] then
        tierName = UsedPlusMaintenance.CONFIG.inspectionTiers[listing.inspectionTier].name
    end

    local message = string.format(
        g_i18n:getText("usedplus_inspection_complete") or "%s inspection complete for %s! View report now.",
        tierName, vehicleName
    )

    -- Also add in-game notification as backup (visible even if dialog is dismissed)
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        message
    )

    -- v2.13.2: Skip modal dialog during sleep to prevent freeze (Issue #7)
    -- Notification still shows above, player can view report from portfolio after waking
    if g_sleepManager ~= nil and g_sleepManager.isSleeping then
        UsedPlus.logDebug(string.format("notifyInspectionComplete: Deferring dialog - player is sleeping (%s)", vehicleName))
        return
    end

    -- Show popup dialog with option to view report immediately
    -- Store references for the callback
    self.pendingInspectionListing = listing
    self.pendingInspectionSearch = search
    self.pendingInspectionFarmId = farmId

    local viewReportText = g_i18n:getText("usedplus_preview_viewReport") or "View Report"
    local laterText = g_i18n:getText("usedplus_button_later") or "Later"

    YesNoDialog.show(
        self.onInspectionCompleteDialogCallback,
        self,
        message,
        nil,  -- title (uses default)
        viewReportText,
        laterText
    )

    UsedPlus.logDebug(string.format("Showing inspection complete popup for %s (tier: %s)", vehicleName, tierName))
end

--[[
    v2.7.1: Callback for inspection complete dialog
    v2.7.3: Added frame delay to ensure YesNoDialog is fully closed before opening preview
    @param yes - true if user clicked "View Report", false for "Later"
]]
function UsedVehicleManager:onInspectionCompleteDialogCallback(yes)
    if yes then
        -- User wants to view the report - open UsedVehiclePreviewDialog
        local listing = self.pendingInspectionListing
        local farmId = self.pendingInspectionFarmId
        local search = self.pendingInspectionSearch

        if listing then
            UsedPlus.logDebug(string.format("User chose to view inspection report (state: %s)",
                tostring(listing.inspectionState)))

            -- v2.7.3: Use a frame delay to ensure YesNoDialog is fully closed
            -- This prevents the preview dialog from opening while the previous dialog
            -- is still being processed, which can cause stale state to be displayed
            g_currentMission:addUpdateable({
                listing = listing,
                farmId = farmId,
                search = search,
                frameWait = 2,  -- Wait 2 frames to ensure clean state
                update = function(self, dt)
                    self.frameWait = self.frameWait - 1
                    if self.frameWait <= 0 then
                        g_currentMission:removeUpdateable(self)
                        UsedPlus.logDebug(string.format("Opening preview dialog after delay (state: %s)",
                            tostring(self.listing.inspectionState)))
                        DialogLoader.show("UsedVehiclePreviewDialog", "show",
                            self.listing, self.farmId, nil, nil, self.search)
                    end
                end
            })
        else
            UsedPlus.logWarn("No pending inspection listing to show")
        end
    else
        UsedPlus.logDebug("User chose to view inspection report later")
    end

    -- Clear the pending references
    self.pendingInspectionListing = nil
    self.pendingInspectionSearch = nil
    self.pendingInspectionFarmId = nil
end

--[[
    v2.7.0: Get remaining hours until inspection completes
    @param listing - The listing being inspected
    @return hours remaining, or 0 if complete/not started
]]
function UsedVehicleManager:getInspectionHoursRemaining(listing)
    if listing == nil or listing.inspectionState ~= "pending" then
        return 0
    end

    local currentHour = self.totalGameHours or 0
    local completionHour = listing.inspectionCompletesAtHour or currentHour

    return math.max(0, completionHour - currentHour)
end

--[[
    v2.7.0: Cancel a pending inspection (no refund - sunk cost)
    @param listing - The listing with pending inspection
    @return success boolean
]]
function UsedVehicleManager:cancelInspection(listing)
    if listing == nil or listing.inspectionState ~= "pending" then
        return false
    end

    listing.inspectionState = nil
    listing.inspectionTier = nil
    listing.inspectionRequestedAtHour = nil
    listing.inspectionCompletesAtHour = nil
    listing.inspectionFarmId = nil
    listing.inspectionCostPaid = nil
    listing.listingOnHold = false

    UsedPlus.logDebug(string.format("Inspection cancelled: %s (no refund)", listing.id or "unknown"))

    return true
end

UsedPlus.logDebug("VehicleInspection module loaded")
