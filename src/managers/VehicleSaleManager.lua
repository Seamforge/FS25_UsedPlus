--[[
    FS25_UsedPlus - Vehicle Sale Manager

    VehicleSaleManager handles agent-based vehicle sales queue
    Pattern mirrors UsedVehicleManager but for SELLING instead of BUYING
    Replaces vanilla instant-sell with time-based agent system

    Responsibilities:
    - Track all active sale listings across all farms
    - Process sale queue hourly (subscribe to HOUR_CHANGED)
    - Update TTL/TTS counters for each listing
    - Generate sale offers when TTS reached
    - Handle accept/decline of offers
    - Send notifications for offers, sales, expirations
    - Save/load sale listings to savegame
    - Remove vehicle from farm when sold

    v1.9.7: Queue-based offer presentation
    - Added offerShownToUser flag to prevent race conditions
    - showNextPendingOffer() ensures offers are shown one at a time
    - After each dialog closes, checks for more pending offers
    - Handles case where multiple offers arrive in same tick

    This is a global singleton: g_vehicleSaleManager
]]

VehicleSaleManager = {}
local VehicleSaleManager_mt = Class(VehicleSaleManager)

-- Maximum concurrent sale listings per farm (default, overridden by settings)
VehicleSaleManager.MAX_LISTINGS_PER_FARM = 3

--[[
    Get maximum allowed sale listings per farm from settings
    @return number - max listings allowed
]]
function VehicleSaleManager.getMaxListingsPerFarm()
    return UsedPlusSettings and UsedPlusSettings:get("maxListingsPerFarm") or VehicleSaleManager.MAX_LISTINGS_PER_FARM
end

--[[
    Constructor
    Creates manager instance with empty data structures
]]
function VehicleSaleManager.new()
    local self = setmetatable({}, VehicleSaleManager_mt)

    -- Data structures
    self.activeListings = {}  -- All listings indexed by ID
    self.nextListingId = 1

    -- Event subscriptions
    self.isServer = false
    self.isClient = false

    -- v1.9.7: Flag to check for pending offers on first hour tick after load
    self.checkPendingOnFirstTick = false

    -- v2.7.0: Track total processed hours for time jump detection
    self.totalProcessedHours = 0

    return self
end

--[[
    Initialize manager after mission loads
    Subscribe to hourly events for queue processing
]]
function VehicleSaleManager:loadMapFinished()
    -- Set server/client status
    if g_currentMission then
        self.isServer = g_currentMission:getIsServer()
        self.isClient = g_currentMission:getIsClient()
    end

    if self.isServer then
        -- Subscribe to hourly game time for TTL/TTS countdown
        g_messageCenter:subscribe(MessageType.HOUR_CHANGED, self.onHourChanged, self)
        -- v2.12.2: Subscribe to sleep state changes to show deferred sale offers on wake (Issue #7)
        g_messageCenter:subscribe(MessageType.SLEEPING, self.onSleepingStateChanged, self)
        UsedPlus.logDebug("VehicleSaleManager subscribed to HOUR_CHANGED, SLEEPING")
    end

    -- v1.9.7: Check for any pending offers that weren't shown before save
    -- Subscribe to HOUR_CHANGED on client to check for pending offers after first hour tick
    -- This ensures UI is ready before showing dialogs
    if self.isClient and not self.isServer then
        self.checkPendingOnFirstTick = true
    elseif self.isClient then
        -- In single-player (both server and client), check on first hour tick
        self.checkPendingOnFirstTick = true
    end
end

--[[
    Hourly queue processing
    Called automatically when in-game hour changes
    Updates all listings, generates offers, handles expirations
    v2.7.0: Handles time jumps (sleep, fast-forward, save/load) by processing multiple iterations
]]
function VehicleSaleManager:onHourChanged()
    if not self.isServer then return end

    -- Check if vehicle sale system is enabled
    local saleEnabled = not UsedPlusSettings or UsedPlusSettings:get("enableVehicleSaleSystem") ~= false
    if not saleEnabled then
        UsedPlus.logDebug("VehicleSaleManager: Sale system disabled, skipping HOUR_CHANGED processing")
        return
    end

    -- v1.9.7: Check for pending offers from previous session on first tick
    if self.checkPendingOnFirstTick then
        self.checkPendingOnFirstTick = false
        local shown = self:showNextPendingOffer()
        if shown then
            UsedPlus.logDebug("onHourChanged: Showed pending offer from previous session")
        end
    end

    -- v2.7.0: Calculate hours to process (handles time jumps)
    local lastHour = self.totalProcessedHours or 0
    self.totalProcessedHours = lastHour + 1
    local hoursToProcess = 1  -- Default: just this hour

    -- On first tick after load, we may need to catch up
    -- Compare against environment time if we have a significant gap
    local currentGameHour = (g_currentMission.environment.currentDay - 1) * 24 + g_currentMission.environment.currentHour
    if lastHour > 0 and currentGameHour > lastHour then
        hoursToProcess = currentGameHour - lastHour
        -- Cap to prevent excessive processing (720 hours = 30 days)
        local maxHoursToProcess = 720
        if hoursToProcess > maxHoursToProcess then
            UsedPlus.logDebug(string.format("TIME_JUMP: %d hours jumped for sales, capping to %d", hoursToProcess, maxHoursToProcess))
            hoursToProcess = maxHoursToProcess
        end
        self.totalProcessedHours = currentGameHour
    end

    local totalListings = self:getTotalListingCount()

    if hoursToProcess > 1 then
        UsedPlus.logDebug(string.format("TIME_JUMP: Processing %d hours of sale listings (total active: %d)",
            hoursToProcess, totalListings))
    else
        UsedPlus.logTrace(string.format("HOUR_CHANGED - Processing sale queue (total active: %d)", totalListings))
    end

    -- v2.7.0: Process each jumped hour to ensure proper TTL/TTS countdown
    -- v2.15.0: Track which farms had changes for sync
    local farmsWithChanges = {}

    for hourIteration = 1, hoursToProcess do
        -- Process all active listings for this hour
        for _, farm in pairs(g_farmManager:getFarms()) do
            local farmId = farm.farmId
            if farm.vehicleSaleListings and #farm.vehicleSaleListings > 0 then
                if hoursToProcess > 1 and hourIteration == 1 then
                    UsedPlus.logTrace(string.format("  Processing %d hours for Farm %d (%d sale listings)",
                        hoursToProcess, farmId, #farm.vehicleSaleListings))
                end
                self:processListingsForFarm(farmId, farm)
                farmsWithChanges[farmId] = true
            end
        end
    end

    -- v2.15.0: Broadcast updated listing state to all clients
    if g_server ~= nil then
        for farmId, _ in pairs(farmsWithChanges) do
            SyncSaleListingsEvent.broadcastFullForFarm(farmId)
        end
    end
end

--[[
    v2.12.2: Handle sleep state changes (Issue #7)
    When player wakes up, show any sale offers that were deferred during sleep
]]
function VehicleSaleManager:onSleepingStateChanged(isSleeping)
    if not isSleeping then
        -- Player woke up - show any pending offers that were deferred during sleep
        UsedPlus.logDebug("VehicleSaleManager: Player woke up, checking for deferred sale offers")
        self:showNextPendingOffer()
    end
end

--[[
    Process listings for a single farm
    Iterate backwards to safely remove completed listings
]]
function VehicleSaleManager:processListingsForFarm(farmId, farm)
    -- Iterate backwards for safe removal
    for i = #farm.vehicleSaleListings, 1, -1 do
        local listing = farm.vehicleSaleListings[i]

        if listing:isActive() or listing.status == VehicleSaleListing.STATUS.OFFER_PENDING then
            -- Log before update
            UsedPlus.logTrace(string.format("    Listing %s: %s - TTL=%d, TTS=%d, Status=%s",
                listing.id, listing.vehicleName, listing.ttl, listing.tts, listing.status))

            -- Update listing (decrements TTL/TTS, checks offer expiration)
            local event = listing:update()

            -- Handle events
            if event == "offer" then
                -- New offer generated
                self:onOfferReceived(farmId, listing)

            elseif event == "offer_expired" then
                -- Player didn't respond in time
                self:onOfferExpired(farmId, listing)

            elseif event == "expired" then
                -- Listing expired without accepted offer
                self:onListingExpired(farmId, listing, i)
            end

            -- Check if listing is complete (sold or expired)
            if listing:isComplete() then
                -- Remove from active listings (keep in history for UI)
                self.activeListings[listing.id] = nil
            end
        end
    end
end

--[[
    Handle new offer received
    v1.9.7: Refactored to use queue-based presentation pattern
    - Sends notification to alert player
    - Calls showNextPendingOffer() which checks offerShownToUser flag
    - This prevents race conditions when multiple offers arrive in same tick
]]
function VehicleSaleManager:onOfferReceived(farmId, listing)
    UsedPlus.logDebug(string.format("onOfferReceived ENTERED for %s: $%d",
        listing.vehicleName, listing.currentOffer))

    -- Check if game is ready
    if g_currentMission == nil or g_currentMission.isLoading then
        UsedPlus.logDebug("onOfferReceived: Skipping - mission not ready or loading")
        return
    end

    -- Step 1: Show notification to alert the player (always)
    local notifyMessage = string.format(
        g_i18n:getText("usedplus_notify_saleOffer") or "Buyer found for %s! Offering %s",
        listing.vehicleName,
        g_i18n:formatMoney(listing.currentOffer, 0, true, true)
    )
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        notifyMessage
    )

    -- Step 2: Determine if we should show dialog for this farm
    local playerFarmId = nil
    if g_currentMission.player and g_currentMission.player.farmId then
        playerFarmId = g_currentMission.player.farmId
    elseif g_currentMission.playerUserId then
        local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
        if farm then
            playerFarmId = farm.farmId
        end
    end
    if playerFarmId == nil and g_currentMission:getIsServer() then
        playerFarmId = 1  -- Default farm in single-player
    end

    local isLocalFarm = (playerFarmId ~= nil and playerFarmId == farmId)
    local isSinglePlayer = g_currentMission:getIsServer() and not g_currentMission.missionDynamicInfo.isMultiplayer
    local shouldShowDialog = isSinglePlayer or isLocalFarm

    UsedPlus.logDebug(string.format("onOfferReceived: farmId=%s, playerFarmId=%s, shouldShow=%s",
        tostring(farmId), tostring(playerFarmId), tostring(shouldShowDialog)))

    -- Step 3: Use queue-based presentation - showNextPendingOffer checks offerShownToUser flag
    -- This ensures if another dialog is open, this offer waits its turn
    -- v2.12.2: Also skip dialog during sleep (Issue #7) - offers stay queued
    if shouldShowDialog then
        if g_sleepManager ~= nil and g_sleepManager.isSleeping then
            UsedPlus.logDebug("onOfferReceived: Deferring dialog - player is sleeping")
        else
            self:showNextPendingOffer(farmId)
        end
    end
end

--[[
    Handle offer that expired without response
    Listing may continue if time remains
]]
function VehicleSaleManager:onOfferExpired(farmId, listing)
    UsedPlus.logDebug(string.format("Offer expired for %s", listing.vehicleName))

    -- Send notification
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_INFO,
        string.format(g_i18n:getText("usedplus_notification_saleOfferExpired"), listing.vehicleName)
    )
end

--[[
    Show the next pending offer that hasn't been shown to user yet
    Called after dialog closes to ensure all offers are eventually presented
    v1.9.7: Added to fix race condition when multiple offers arrive in same tick
    @param farmId - Optional farm ID to filter by, nil = check all farms
    @return true if a dialog was shown
]]
function VehicleSaleManager:showNextPendingOffer(farmId)
    -- Check if game is ready
    if g_currentMission == nil or g_currentMission.isLoading then
        UsedPlus.logTrace("showNextPendingOffer: Skipping - mission not ready")
        return false
    end

    -- v2.12.2: Skip during sleep to prevent modal dialog freeze (Issue #7)
    -- Offers stay queued (offerShownToUser = false) and show when player wakes up
    if g_sleepManager ~= nil and g_sleepManager.isSleeping then
        UsedPlus.logTrace("showNextPendingOffer: Skipping - player is sleeping")
        return false
    end

    -- Determine which farm to check
    local targetFarmId = farmId

    -- If no farm specified, get player's farm
    if targetFarmId == nil then
        if g_currentMission.player and g_currentMission.player.farmId then
            targetFarmId = g_currentMission.player.farmId
        elseif g_currentMission.playerUserId then
            local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
            if farm then
                targetFarmId = farm.farmId
            end
        end
        -- In single-player, assume farm 1 if still nil
        if targetFarmId == nil and g_currentMission:getIsServer() then
            targetFarmId = 1
        end
    end

    if targetFarmId == nil then
        UsedPlus.logTrace("showNextPendingOffer: Could not determine farm ID")
        return false
    end

    -- Find listings with pending offers that haven't been shown
    local farm = g_farmManager:getFarmById(targetFarmId)
    if farm == nil or farm.vehicleSaleListings == nil then
        return false
    end

    for _, listing in ipairs(farm.vehicleSaleListings) do
        if listing:hasPendingOffer() and not listing.offerShownToUser then
            -- v2.13.2: Verify the vehicle still exists before showing the offer
            -- If another listing already sold and deleted this vehicle, auto-cancel
            local vehicleStillExists = false
            if listing.vehicleId and g_currentMission and g_currentMission.vehicleSystem then
                for _, v in pairs(g_currentMission.vehicleSystem.vehicles) do
                    if tostring(v.id) == tostring(listing.vehicleId) then
                        vehicleStillExists = true
                        break
                    end
                end
            end

            if not vehicleStillExists then
                UsedPlus.logInfo(string.format("v2.13.2: Vehicle gone for listing %s (%s) - auto-cancelling",
                    listing.id, listing.vehicleName))
                listing:cancel()
                self.activeListings[listing.id] = nil
                -- Continue to next listing (don't show dialog for a ghost vehicle)
            else
            -- Found an unshown offer - show it now
            UsedPlus.logDebug(string.format("showNextPendingOffer: Showing offer for %s ($%d)",
                listing.vehicleName, listing.currentOffer))

            -- Mark as shown BEFORE opening dialog to prevent re-entry
            listing.offerShownToUser = true

            -- Create callback
            local listingId = listing.id
            local self_ref = self  -- Capture self for callback closure
            local callback = function(accepted)
                UsedPlus.logDebug(string.format("SaleOfferDialog callback: accepted=%s, listingId=%s",
                    tostring(accepted), tostring(listingId)))
                if accepted then
                    -- v2.13.2: Call accept directly (no outer deferral needed)
                    -- Vehicle deletion is already safely deferred inside acceptOffer()
                    -- Removing the outer deferral eliminates the race condition where the listing
                    -- stays OFFER_PENDING for one frame, allowing potential re-accept
                    SaleListingActionEvent.sendToServer(listingId, SaleListingActionEvent.ACTION_ACCEPT)
                else
                    SaleListingActionEvent.sendToServer(listingId, SaleListingActionEvent.ACTION_DECLINE)
                end

                -- v2.13.2: Refresh Finance page so stale buttons disappear
                if FinanceManagerFrame and FinanceManagerFrame.refresh then
                    FinanceManagerFrame.refresh()
                end

                -- After handling this offer, check for more pending offers
                if self_ref then
                    self_ref:showNextPendingOffer(targetFarmId)
                end
            end

            -- Show the dialog
            if DialogLoader and DialogLoader.show then
                DialogLoader.show("SaleOfferDialog", "setListing", listing, callback)
                return true
            end
            end -- end of else (vehicle still exists)
        end
    end

    UsedPlus.logTrace("showNextPendingOffer: No unshown pending offers found")
    return false
end

--[[
    Handle listing expiration
    Vehicle is returned to player (stays in inventory), fee lost
]]
function VehicleSaleManager:onListingExpired(farmId, listing, listingIndex)
    UsedPlus.logDebug(string.format("Listing expired for %s", listing.vehicleName))

    -- v2.13.2: During sleep, only show notification to prevent freeze (Issue #7)
    if g_sleepManager ~= nil and g_sleepManager.isSleeping then
        UsedPlus.logDebug(string.format("onListingExpired: Deferring dialog - player is sleeping (%s)", listing.vehicleName))
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format(g_i18n:getText("usedplus_notification_noBuyerFound"),
                listing.vehicleName, listing.agentFee)
        )
        return
    end

    -- Show popup dialog instead of notification
    if SaleExpiredDialog then
        local callback = function(relistChoice)
            if relistChoice then
                -- Player wants to relist - show SellVehicleDialog
                local vehicle = listing.vehicle
                if vehicle and DialogLoader then
                    local sellCallback = function(agentTier, priceTier)
                        if agentTier ~= nil then
                            -- Create new listing
                            local newListing = g_vehicleSaleManager:createSaleListing(farmId, vehicle, agentTier, priceTier or 2)
                            if newListing then
                                UsedPlus.logInfo(string.format("Relisted %s with agent tier %d, price tier %d",
                                    newListing.vehicleName, agentTier, priceTier))
                            end
                        end
                    end
                    DialogLoader.show("SellVehicleDialog", "setVehicle", vehicle, farmId, sellCallback)
                else
                    -- Vehicle not available, just show notification
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_INFO,
                        g_i18n:getText("usedplus_notification_vehicleNotAvailableRelist")
                    )
                end
            end
            -- If not relisting, nothing more to do - vehicle stays in inventory
        end

        SaleExpiredDialog.showWithListing(listing, callback)
    else
        -- Fallback to notification if dialog not loaded
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format(g_i18n:getText("usedplus_notification_noBuyerFound"),
                listing.vehicleName, listing.agentFee)
        )
    end

    -- Note: We don't remove from farm.vehicleSaleListings here
    -- It stays with "expired" status for history/UI purposes
    -- Clean up old expired listings periodically
end

--[[
    Create new sale listing
    Called from SellVehicleDialog when player selects agent tier
    @param farmId - Farm that owns the vehicle
    @param vehicle - The vehicle object to sell
    @param agentTier - Agent tier (0=Private, 1=Local, 2=Regional, 3=National)
    @param priceTier - Price tier (1=Quick, 2=Market, 3=Premium) - optional, defaults to 2
    @return listing or nil on failure
]]
function VehicleSaleManager:createSaleListing(farmId, vehicle, agentTier, priceTier)
    if not self.isServer then
        UsedPlus.logError("createSaleListing must be called on server")
        return nil
    end

    -- Default priceTier for legacy compatibility
    priceTier = priceTier or 2

    -- Validate vehicle
    if vehicle == nil then
        UsedPlus.logError("Cannot create listing for nil vehicle")
        return nil
    end

    -- Validate agent tier (0=Private, 1-3=Professional agents)
    if agentTier < 0 or agentTier > 3 then
        UsedPlus.logError(string.format("Invalid agent tier %d", agentTier))
        return nil
    end

    -- Validate price tier (1=Quick, 2=Market, 3=Premium)
    if priceTier < 1 or priceTier > 3 then
        UsedPlus.logError(string.format("Invalid price tier %d", priceTier))
        return nil
    end

    -- Check vehicle is owned and not already listed
    if vehicle.ownerFarmId ~= farmId then
        UsedPlus.logError("Vehicle not owned by this farm")
        return nil
    end

    if self:isVehicleListed(vehicle) then
        UsedPlus.logError("Vehicle is already listed for sale")
        return nil
    end

    -- Check listing limit (UI only supports 3 rows)
    local canCreate, currentCount, maxAllowed = self:canCreateListing(farmId)
    if not canCreate then
        UsedPlus.logError(string.format("Farm %d already has maximum sale listings (%d/%d)", farmId, currentCount, maxAllowed))
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("usedplus_error_maxSaleListings") or "Maximum %d vehicles can be listed for sale at once.", maxAllowed)
        )
        return nil
    end

    -- Check vehicle is not leased (cannot sell leased vehicles at all)
    if g_financeManager and g_financeManager:hasActiveLease(vehicle) then
        UsedPlus.logError("Cannot sell leased vehicle")
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_ERROR,
            g_i18n:getText("usedplus_error_cannotSellLeasedVehicle")
        )
        return nil
    end

    -- Check vehicle is not financed (v2.11.0: Added user-facing error message)
    if TradeInCalculations and TradeInCalculations.isVehicleFinanced then
        if TradeInCalculations.isVehicleFinanced(vehicle, farmId) then
            UsedPlus.logError("Cannot sell financed vehicle")
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_ERROR,
                g_i18n:getText("usedplus_sell_cantSellFinanced") or "Cannot sell financed vehicles. Pay off balance first."
            )
            return nil
        end
    end

    -- Create listing using factory method
    local listing = VehicleSaleListing.createFromVehicle(farmId, vehicle, agentTier, priceTier)
    if listing == nil then
        UsedPlus.logError("Failed to create listing from vehicle")
        return nil
    end

    -- Assign unique ID
    listing.id = self:generateListingId()

    -- Register listing
    self:registerListing(listing)

    -- Deduct agent fee
    g_currentMission:addMoney(-listing.agentFee, farmId, MoneyType.OTHER, true, true)

    -- Track statistics
    if g_financeManager then
        g_financeManager:incrementStatistic(farmId, "salesListed", 1)
    end

    UsedPlus.logDebug(string.format("Created sale listing %s: %s ($%d fee, %d hrs TTL, Agent: %s, Price: %s)",
        listing.id, listing.vehicleName, listing.agentFee, listing.ttl,
        listing:getAgentTierName(), listing:getPriceTierName()))

    -- Note: Confirmation notification now handled by SaleListingInitiatedDialog
    -- No inline notification here to avoid duplicate feedback

    return listing
end

--[[
    Register listing in manager and farm
]]
function VehicleSaleManager:registerListing(listing)
    -- Add to global listings table
    self.activeListings[listing.id] = listing

    -- Add to farm-specific listings table
    local farm = g_farmManager:getFarmById(listing.farmId)
    if farm then
        if farm.vehicleSaleListings == nil then
            farm.vehicleSaleListings = {}
        end
        table.insert(farm.vehicleSaleListings, listing)

        UsedPlus.logDebug(string.format("REGISTERED Listing %s for farm %d - TTL=%d, TTS=%d",
            listing.id, listing.farmId, listing.ttl, listing.tts))
        UsedPlus.logTrace(string.format("  Farm now has %d active sale listings", #farm.vehicleSaleListings))
    else
        UsedPlus.logError(string.format("Could not find farm %d to register listing", listing.farmId))
    end
end

--[[
    Accept current offer on a listing
    Deletes vehicle and credits money to farm
    @param listingId - The listing ID
    @return true on success
]]
function VehicleSaleManager:acceptOffer(listingId)
    if not self.isServer then
        UsedPlus.logError("acceptOffer must be called on server")
        return false
    end

    local listing = self.activeListings[listingId]
    if listing == nil then
        UsedPlus.logError(string.format("acceptOffer: Listing %s not found in activeListings (already completed?)", listingId))
        return false
    end

    -- v2.13.2: Contract lifecycle gate — block if contract is already complete
    if listing:isComplete() then
        UsedPlus.logInfo(string.format("acceptOffer: Blocked — listing %s is already %s (contract complete)",
            listingId, listing.status))
        return false
    end

    if not listing:hasPendingOffer() then
        UsedPlus.logError(string.format("acceptOffer: Listing %s has no pending offer (status: %s)",
            listingId, listing.status))
        return false
    end

    -- Get sale price before accepting
    local grossSalePrice = listing.currentOffer
    local farmId = listing.farmId
    local vehicleName = listing.vehicleName
    local vehicleId = listing.vehicleId

    -- Calculate agent commission from settings (default 8%)
    local commissionPercent = UsedPlusSettings and UsedPlusSettings:get("agentCommissionPercent") or 8
    local agentCommission = math.floor(grossSalePrice * (commissionPercent / 100))
    local netSalePrice = grossSalePrice - agentCommission

    -- v2.8.0: Close workshop screen if it's showing the vehicle being sold
    -- This prevents the "ghost vehicle" issue where workshop still displays sold vehicle
    self:closeWorkshopIfShowingVehicle(vehicleId)

    -- Accept the offer (updates listing status)
    listing:acceptOffer()

    -- v2.13.2: Cancel any OTHER active/pending listings for the same vehicle
    -- This prevents the duplicate listing bug where a vehicle gets listed twice
    -- (e.g., from save/load edge cases) and accepting one leaves the other active
    local farm = g_farmManager:getFarmById(farmId)
    if farm and farm.vehicleSaleListings then
        for _, otherListing in ipairs(farm.vehicleSaleListings) do
            if otherListing.id ~= listingId
               and otherListing.vehicleId and tostring(otherListing.vehicleId) == tostring(vehicleId)
               and (otherListing:isActive() or otherListing.status == VehicleSaleListing.STATUS.OFFER_PENDING) then
                UsedPlus.logInfo(string.format("v2.13.2: Auto-cancelling sibling listing %s for sold vehicle %s",
                    otherListing.id, vehicleName))
                otherListing:cancel()
                self.activeListings[otherListing.id] = nil
            end
        end
    end

    -- v2.11.0: Defer vehicle deletion to next frame to prevent GUI event queue conflicts
    -- Issue: If vehicle is deleted immediately, pending mouse events may still reference it
    -- causing FSBaseMission.lua:2472 "attempt to index nil with 'id'" crash
    -- Solution: Schedule deletion for next frame after GUI events are processed
    local vehicleIdToDelete = vehicleId
    local listingIdForLog = listingId

    g_currentMission:addUpdateable({
        update = function(self, dt)
            -- Delete the vehicle on next frame
            local vehicleDeleted = g_vehicleSaleManager:deleteVehicleById(vehicleIdToDelete)
            if not vehicleDeleted then
                UsedPlus.logWarn(string.format("Could not find vehicle to delete for listing %s", listingIdForLog))
            end
            -- Remove this updateable after one execution
            g_currentMission:removeUpdateable(self)
        end
    })

    -- Credit NET sale price to farm (after agent commission)
    g_currentMission:addMoney(netSalePrice, farmId, MoneyType.VEHICLE_SELL, true, true)

    -- Track statistics (record gross sale for reporting)
    if g_financeManager then
        g_financeManager:incrementStatistic(farmId, "salesCompleted", 1)
        g_financeManager:incrementStatistic(farmId, "totalSaleProceeds", grossSalePrice)
        g_financeManager:incrementStatistic(farmId, "totalAgentCommissions", agentCommission)
    end

    -- Remove from active listings
    self.activeListings[listingId] = nil

    -- Send notification showing gross, commission, and net
    local notificationMsg = string.format("SOLD: %s\nGross: %s | Commission: %s (%d%%)\nNet: %s",
        vehicleName,
        g_i18n:formatMoney(grossSalePrice, 0, true, true),
        g_i18n:formatMoney(agentCommission, 0, true, true),
        commissionPercent,
        g_i18n:formatMoney(netSalePrice, 0, true, true))
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, notificationMsg)

    UsedPlus.logDebug(string.format("Sale completed: %s sold for $%d (net $%d after %d%% commission)",
        vehicleName, grossSalePrice, netSalePrice, commissionPercent))

    -- v2.13.2: Force Finance page refresh so stale "Accept" buttons disappear immediately
    if FinanceManagerFrame and FinanceManagerFrame.refresh then
        FinanceManagerFrame.refresh()
    end

    -- Check for Service Truck discovery after National Agent sale
    -- agentTier 3 = National
    if listing.agentTier == 3 then
        if ServiceTruckDiscovery and ServiceTruckDiscovery.onNationalAgentTransaction then
            ServiceTruckDiscovery.onNationalAgentTransaction(listing.farmId, "sale")
        end
    end

    return true
end

--[[
    Decline current offer on a listing
    Listing continues, may receive more offers if time remains
    @param listingId - The listing ID
    @return true on success
]]
function VehicleSaleManager:declineOffer(listingId)
    if not self.isServer then
        UsedPlus.logError("declineOffer must be called on server")
        return false
    end

    local listing = self.activeListings[listingId]
    if listing == nil then
        UsedPlus.logError(string.format("Listing %s not found", listingId))
        return false
    end

    if not listing:hasPendingOffer() then
        UsedPlus.logError(string.format("Listing %s has no pending offer to decline", listingId))
        return false
    end

    -- Decline the offer
    local declinedAmount = listing.currentOffer
    listing:declineOffer()

    -- Send notification
    if listing:isActive() then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format(g_i18n:getText("usedplus_notification_offerDeclinedContinue"),
                g_i18n:formatMoney(declinedAmount, 0, true, true), listing.vehicleName)
        )
    else
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format(g_i18n:getText("usedplus_notification_offerDeclinedExpired"), listing.vehicleName)
        )
    end

    UsedPlus.logDebug(string.format("Offer declined for %s. Status: %s, TTL: %d",
        listing.vehicleName, listing.status, listing.ttl))

    return true
end

--[[
    Cancel a sale listing
    Vehicle stays in inventory, agent fee is NOT refunded
    @param listingId - The listing ID
    @return true on success
]]
function VehicleSaleManager:cancelListing(listingId)
    if not self.isServer then
        UsedPlus.logError("cancelListing must be called on server")
        return false
    end

    local listing = self.activeListings[listingId]
    if listing == nil then
        UsedPlus.logError(string.format("Listing %s not found", listingId))
        return false
    end

    if listing:isComplete() then
        UsedPlus.logError(string.format("Listing %s is already complete", listingId))
        return false
    end

    -- Cancel the listing
    listing:cancel()

    -- Track statistics
    if g_financeManager then
        g_financeManager:incrementStatistic(listing.farmId, "salesCancelled", 1)
    end

    -- Remove from active listings
    self.activeListings[listingId] = nil

    -- Send notification
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_INFO,
        string.format(g_i18n:getText("usedplus_notification_saleListingCancelled"),
            listing.vehicleName, listing.agentFee)
    )

    UsedPlus.logDebug(string.format("Listing cancelled: %s", listing.vehicleName))

    return true
end

--[[
    Modify the asking price of an active listing
    Only allowed when listing is in "searching" status (no active offer)
    @param listingId - The listing ID
    @param newPrice - The new asking price
    @return true on success
]]
function VehicleSaleManager:modifyAskingPrice(listingId, newPrice)
    if not self.isServer then
        UsedPlus.logError("modifyAskingPrice must be called on server")
        return false
    end

    local listing = self.activeListings[listingId]
    if listing == nil then
        UsedPlus.logError(string.format("Listing %s not found", listingId))
        return false
    end

    -- Can only modify if in searching status (no pending offer)
    if listing.status ~= "searching" then
        UsedPlus.logError(string.format("Listing %s cannot be modified - status is %s", listingId, listing.status))
        return false
    end

    -- Validate new price (must be positive and reasonable)
    if newPrice == nil or newPrice <= 0 then
        UsedPlus.logError("Invalid price: must be greater than 0")
        return false
    end

    -- Store old price for logging
    local oldPrice = listing.askingPrice

    -- Update the asking price
    listing.askingPrice = newPrice

    -- Recalculate price tier based on new price vs fair market value
    if listing.fairMarketValue and listing.fairMarketValue > 0 then
        local priceRatio = newPrice / listing.fairMarketValue
        if priceRatio <= 0.85 then
            listing.priceTier = 1  -- Quick Sale
        elseif priceRatio <= 1.05 then
            listing.priceTier = 2  -- Market Price
        else
            listing.priceTier = 3  -- Premium
        end
    end

    -- Send notification
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format(g_i18n:getText("usedplus_notification_askingPriceUpdated"),
            listing.vehicleName,
            g_i18n:formatMoney(oldPrice, 0, true, true),
            g_i18n:formatMoney(newPrice, 0, true, true))
    )

    UsedPlus.logDebug(string.format("Listing %s price modified: $%.0f -> $%.0f", listingId, oldPrice, newPrice))

    return true
end

--[[
    Delete vehicle by ID
    Finds vehicle in mission and removes it
    @param vehicleId - The vehicle ID (from vehicle.id)
    @return true if vehicle was found and deleted
]]
function VehicleSaleManager:deleteVehicleById(vehicleId)
    if vehicleId == nil or vehicleId == "" then
        return false
    end

    -- Search through all vehicles
    if g_currentMission and g_currentMission.vehicleSystem then
        for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
            if tostring(vehicle.id) == tostring(vehicleId) then
                if vehicle.delete then
                    vehicle:delete()
                    UsedPlus.logTrace(string.format("Deleted vehicle ID: %s", tostring(vehicleId)))
                    return true
                end
            end
        end
    end

    return false
end

--[[
    Check if a vehicle is already listed for sale
    @param vehicle - The vehicle object
    @return true if vehicle has an active listing
]]
function VehicleSaleManager:isVehicleListed(vehicle)
    if vehicle == nil then return false end

    local vehicleId = tostring(vehicle.id)

    -- v2.13.2: Check BOTH activeListings hash AND farm.vehicleSaleListings array
    -- Previously only checked activeListings, which is cleared on accept,
    -- allowing duplicate listings for the same vehicle after sale
    for _, listing in pairs(self.activeListings) do
        if listing.vehicleId and tostring(listing.vehicleId) == vehicleId then
            if listing:isActive() or listing.status == VehicleSaleListing.STATUS.OFFER_PENDING then
                return true
            end
        end
    end

    -- Also check farm's listing array (includes sold/completed listings)
    local farm = g_farmManager:getFarmById(vehicle.ownerFarmId)
    if farm and farm.vehicleSaleListings then
        for _, listing in ipairs(farm.vehicleSaleListings) do
            if listing.vehicleId and tostring(listing.vehicleId) == vehicleId then
                if listing:isActive() or listing.status == VehicleSaleListing.STATUS.OFFER_PENDING then
                    return true
                end
            end
        end
    end

    return false
end

--[[
    Generate unique listing ID
    Format: "SALE_NNNNNNNN" (8-digit counter)
]]
function VehicleSaleManager:generateListingId()
    local id = string.format("SALE_%08d", self.nextListingId)
    self.nextListingId = self.nextListingId + 1
    return id
end

--[[
    Get all listings for a specific farm
    @param farmId - The farm ID
    @param activeOnly - If true, only return active/pending listings
    @return Array of listings
]]
function VehicleSaleManager:getListingsForFarm(farmId, activeOnly)
    local farm = g_farmManager:getFarmById(farmId)
    if farm and farm.vehicleSaleListings then
        if activeOnly then
            local active = {}
            for _, listing in ipairs(farm.vehicleSaleListings) do
                if listing:isActive() or listing.status == VehicleSaleListing.STATUS.OFFER_PENDING then
                    table.insert(active, listing)
                end
            end
            return active
        else
            return farm.vehicleSaleListings
        end
    end
    return {}
end

--[[
    Check if farm can create more sale listings
    @param farmId - The farm ID
    @return canCreate (bool), currentCount, maxAllowed
]]
function VehicleSaleManager:canCreateListing(farmId)
    local activeListings = self:getListingsForFarm(farmId, true)  -- true = active only
    local currentCount = #activeListings
    local maxAllowed = VehicleSaleManager.getMaxListingsPerFarm()
    return currentCount < maxAllowed, currentCount, maxAllowed
end

--[[
    Get listing by ID
    @return listing or nil
]]
function VehicleSaleManager:getListingById(listingId)
    return self.activeListings[listingId]
end

--[[
    Get count of listings with pending offers for a farm
    @return count of pending offers
]]
function VehicleSaleManager:getPendingOfferCount(farmId)
    local count = 0
    local farm = g_farmManager:getFarmById(farmId)
    if farm and farm.vehicleSaleListings then
        for _, listing in ipairs(farm.vehicleSaleListings) do
            if listing.status == VehicleSaleListing.STATUS.OFFER_PENDING then
                count = count + 1
            end
        end
    end
    return count
end

--[[
    Get total count of all active listings
]]
function VehicleSaleManager:getTotalListingCount()
    local count = 0
    for _ in pairs(self.activeListings) do
        count = count + 1
    end
    return count
end

--[[
    Save all listings to savegame
]]
function VehicleSaleManager:saveToXMLFile(missionInfo)
    local savegameDirectory = missionInfo.savegameDirectory
    if savegameDirectory == nil then return end

    local filePath = savegameDirectory .. "/usedPlusSales.xml"
    local xmlFile = XMLFile.create("usedPlusSalesXML", filePath, "usedPlusSales")

    if xmlFile ~= nil then
        -- Save next ID counter
        xmlFile:setInt("usedPlusSales#nextListingId", self.nextListingId)

        -- v2.7.0: Save total processed hours for time jump detection
        xmlFile:setInt("usedPlusSales#totalProcessedHours", self.totalProcessedHours or 0)

        -- Save listings grouped by farm
        -- Note: pairs() key may not equal farm.farmId, so use farm.farmId consistently
        local farmIndex = 0
        for _, farm in pairs(g_farmManager:getFarms()) do
            local farmId = farm.farmId
            if farm.vehicleSaleListings and #farm.vehicleSaleListings > 0 then
                local farmKey = string.format("usedPlusSales.farms.farm(%d)", farmIndex)
                xmlFile:setInt(farmKey .. "#farmId", farmId)

                -- Save all listings (including completed for history)
                local listingIndex = 0
                for _, listing in ipairs(farm.vehicleSaleListings) do
                    local listingKey = string.format(farmKey .. ".listing(%d)", listingIndex)
                    listing:saveToXMLFile(xmlFile, listingKey)
                    listingIndex = listingIndex + 1
                end

                farmIndex = farmIndex + 1
            end
        end

        xmlFile:save()
        xmlFile:delete()

        UsedPlus.logDebug(string.format("Saved %d sale listings across %d farms",
            self:getTotalListingCount(), farmIndex))
    end
end

--[[
    Load all listings from savegame
]]
function VehicleSaleManager:loadFromXMLFile(missionInfo)
    local savegameDirectory = missionInfo.savegameDirectory
    if savegameDirectory == nil then
        UsedPlus.logWarn("VehicleSaleManager.loadFromXMLFile: No savegame directory")
        return
    end

    local filePath = savegameDirectory .. "/usedPlusSales.xml"
    UsedPlus.logInfo(string.format("Loading sale data from: %s", filePath))

    local xmlFile = XMLFile.loadIfExists("usedPlusSalesXML", filePath, "usedPlusSales")

    if xmlFile ~= nil then
        -- Load next ID counter
        self.nextListingId = xmlFile:getInt("usedPlusSales#nextListingId", 1)

        -- v2.7.0: Load total processed hours for time jump detection
        self.totalProcessedHours = xmlFile:getInt("usedPlusSales#totalProcessedHours", 0)

        UsedPlus.logDebug(string.format("  nextListingId=%d, totalProcessedHours=%d",
            self.nextListingId, self.totalProcessedHours))

        local farmCount = 0
        local listingCount = 0

        -- Load listings
        xmlFile:iterate("usedPlusSales.farms.farm", function(_, farmKey)
            local farmId = xmlFile:getInt(farmKey .. "#farmId")
            local farm = g_farmManager:getFarmById(farmId)
            farmCount = farmCount + 1

            UsedPlus.logDebug(string.format("  Processing farm %d from XML (found: %s)",
                farmId, tostring(farm ~= nil)))

            if farm then
                if farm.vehicleSaleListings == nil then
                    farm.vehicleSaleListings = {}
                    UsedPlus.logDebug(string.format("    Initialized vehicleSaleListings for farm %d", farmId))
                end

                -- Load listings
                xmlFile:iterate(farmKey .. ".listing", function(_, listingKey)
                    local listing = setmetatable({}, {__index = VehicleSaleListing})
                    if listing:loadFromXMLFile(xmlFile, listingKey) then
                        table.insert(farm.vehicleSaleListings, listing)
                        listingCount = listingCount + 1

                        -- Re-register active listings
                        if listing:isActive() or listing.status == VehicleSaleListing.STATUS.OFFER_PENDING then
                            self.activeListings[listing.id] = listing
                        end

                        UsedPlus.logInfo(string.format("    Loaded sale listing: %s (%s) status=%s",
                            listing.id, listing.vehicleName or "Unknown", listing.status or "unknown"))
                    else
                        UsedPlus.logWarn(string.format("    Failed to load sale listing from %s", listingKey))
                    end
                end)
            else
                UsedPlus.logError(string.format("  FARM %d NOT FOUND - sale listings will be lost!", farmId))
            end
        end)

        xmlFile:delete()

        UsedPlus.logInfo(string.format("VehicleSaleManager: Loaded %d sale listings from %d farms",
            listingCount, farmCount))
    else
        UsedPlus.logInfo("No saved sale data found (new game or first run)")
    end
end

--[[
    v2.8.0: Close workshop/shop config screen if it's showing a specific vehicle
    Called before deleting a sold vehicle to prevent "ghost vehicle" in UI
    @param vehicleId - The ID of the vehicle being sold
]]
function VehicleSaleManager:closeWorkshopIfShowingVehicle(vehicleId)
    if vehicleId == nil then return end

    -- Check if shop config screen is open and showing this vehicle
    if g_shopConfigScreen and g_shopConfigScreen.vehicle then
        local screenVehicleId = tostring(g_shopConfigScreen.vehicle.id or "")
        if screenVehicleId == tostring(vehicleId) then
            UsedPlus.logInfo("Closing workshop - vehicle being sold")
            -- Close the screen by changing to nil
            if g_gui and g_gui.changeScreen then
                g_gui:changeScreen(nil)
            end
            return
        end
    end

    -- Also check workshop screen if different from shop config
    if g_workshopScreen and g_workshopScreen.vehicle then
        local screenVehicleId = tostring(g_workshopScreen.vehicle.id or "")
        if screenVehicleId == tostring(vehicleId) then
            UsedPlus.logInfo("Closing workshop screen - vehicle being sold")
            if g_gui and g_gui.changeScreen then
                g_gui:changeScreen(nil)
            end
            return
        end
    end

    -- Check InGameMenu vehicles frame
    if g_currentMission and g_currentMission.inGameMenu then
        local inGameMenu = g_currentMission.inGameMenu
        if inGameMenu.pageVehicles and inGameMenu.pageVehicles.currentVehicle then
            local menuVehicleId = tostring(inGameMenu.pageVehicles.currentVehicle.id or "")
            if menuVehicleId == tostring(vehicleId) then
                UsedPlus.logInfo("Closing in-game menu - vehicle being sold")
                -- Close the in-game menu
                if inGameMenu.close then
                    inGameMenu:close()
                end
                return
            end
        end
    end
end

--[[
    Cleanup on mission unload
]]
function VehicleSaleManager:delete()
    -- Unsubscribe from events
    if self.isServer then
        g_messageCenter:unsubscribe(MessageType.HOUR_CHANGED, self)
        g_messageCenter:unsubscribe(MessageType.SLEEPING, self)
    end

    -- Clear data
    self.activeListings = {}

    UsedPlus.logDebug("VehicleSaleManager cleaned up")
end

UsedPlus.logInfo("VehicleSaleManager loaded")
