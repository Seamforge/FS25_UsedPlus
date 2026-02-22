--[[
    FS25_UsedPlus - Vehicle Search System Module

    v2.7.2 REFACTORED: Extracted from UsedVehicleManager.lua

    Handles search processing, notifications, and listing generation:
    - processSearchesForFarm: Process monthly success rolls for a farm
    - notifyVehicleFound: Notify player when vehicle found
    - notifySearchComplete: Show search completion with renewal option
    - renewSearch: Renew an expired search
    - calculateSearchCost: Calculate search fee based on tier
    - generateUsedVehicleListingFromData: Create full listing from partial data
    - generateUsedVehicleListing: Legacy listing generation
]]

-- Ensure UsedVehicleManager table exists
UsedVehicleManager = UsedVehicleManager or {}

--[[
    Process searches for a single farm
    v1.5.0: Monthly success rolls - vehicles accumulate in portfolio
    Iterate backwards to safely remove completed searches
]]
function UsedVehicleManager:processSearchesForFarm(farmId, farm)
    -- Iterate backwards for safe removal
    for i = #farm.usedVehicleSearches, 1, -1 do
        local search = farm.usedVehicleSearches[i]

        -- Clean up expired listings even if search is completed
        -- Listings should expire 2-3 months after being found, regardless of search status
        if search.status == "completed" and search.foundListings and #search.foundListings > 0 then
            -- Increment monthsElapsed so listing age calculation works correctly
            search.monthsElapsed = search.monthsElapsed + 1
            search.lastCheckDay = g_currentMission.environment.currentDay

            -- Clean up expired listings
            local normalExpired, earlyExpired = search:cleanupExpiredListings()

            -- Show dialog for early expirations (seller backed out)
            if earlyExpired and #earlyExpired > 0 then
                for _, listing in ipairs(earlyExpired) do
                    self:showSellerBackedOutDialog(listing.name)
                end
            end

            -- Notify for normal expirations
            if normalExpired > 0 then
                UsedPlus.logDebug(string.format("Search %s (completed): Month %d, cleaned up %d expired listing(s)",
                    search.id, search.monthsElapsed, normalExpired))
                if g_currentMission and not g_currentMission.isLoading then
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_INFO,
                        string.format(g_i18n:getText("usedplus_notification_offersExpired"), normalExpired)
                    )
                end
            end
        end

        if search.status == "active" then
            -- Log before monthly check
            UsedPlus.logTrace(string.format("    Search %s: %s - Month %d/%d, Listings: %d/%d",
                search.id, search.storeItemName,
                search.monthsElapsed or 0, search.maxMonths or 1,
                #(search.foundListings or {}), search.maxListings or 10))

            -- v1.5.0: Process monthly success roll
            local listingData = search:processMonthlyCheck()

            -- If a vehicle was found this month, flesh out the listing
            if listingData then
                UsedPlus.logDebug(string.format("Search %s found vehicle this month: condition=%.1f%%",
                    search.id, (1 - (listingData.damage or 0)) * 100))

                -- Generate full listing with store item details, configurations, etc.
                local fullListing = self:generateUsedVehicleListingFromData(search, listingData)

                if fullListing then
                    -- Add to search's portfolio (foundListings is managed by the search object)
                    -- The listingData was already added by processMonthlyCheck, but we need to
                    -- update it with the full data
                    for j, existingListing in ipairs(search.foundListings) do
                        if existingListing.id == listingData.id then
                            -- Replace partial data with full listing
                            search.foundListings[j] = fullListing
                            break
                        end
                    end

                    -- Track statistic
                    if g_financeManager then
                        g_financeManager:incrementStatistic(farmId, "vehiclesFound", 1)
                    end

                    -- Notify player a vehicle was found
                    self:notifyVehicleFound(search, fullListing, farmId)
                end
            end

            -- Check for early expirations (seller backed out)
            if search.recentEarlyExpirations and #search.recentEarlyExpirations > 0 then
                for _, listing in ipairs(search.recentEarlyExpirations) do
                    self:showSellerBackedOutDialog(listing.name)
                end
                search.recentEarlyExpirations = {}  -- Clear after processing
            end

            -- Check if search has completed (expired or player bought a vehicle)
            if search.status == "completed" then
                UsedPlus.logDebug(string.format("Search %s completed: %s (%d vehicles found)",
                    search.id, search.storeItemName, #(search.foundListings or {})))

                -- Remove from active searches
                table.remove(farm.usedVehicleSearches, i)
                self.activeSearches[search.id] = nil

                -- Track completion statistic
                if g_financeManager then
                    local foundCount = #(search.foundListings or {})
                    if foundCount > 0 then
                        g_financeManager:incrementStatistic(farmId, "searchesSucceeded", 1)
                    else
                        g_financeManager:incrementStatistic(farmId, "searchesFailed", 1)
                    end
                end

                -- Notify player search is complete
                self:notifySearchComplete(search, farmId)
            end
            -- else: search still active, will continue next month
        end
    end
end

--[[
    v2.10.0: Show dialog when seller backs out early
    Happens randomly for uninspected vehicles
]]
function UsedVehicleManager:showSellerBackedOutDialog(vehicleName)
    if not g_currentMission or g_currentMission.isLoading then
        return
    end

    local message = string.format(
        g_i18n:getText("usedplus_notification_sellerBackedOut"),
        vehicleName or "vehicle"
    )

    -- v2.13.2: During sleep, only show notification to prevent freeze (Issue #7)
    if g_sleepManager ~= nil and g_sleepManager.isSleeping then
        UsedPlus.logDebug(string.format("showSellerBackedOutDialog: Using notification only - player is sleeping (%s)", vehicleName or "unknown"))
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            message
        )
        return
    end

    -- Use DialogLoader to show simple info dialog
    if DialogLoader and DialogLoader.showInfoDialog then
        DialogLoader.showInfoDialog(
            g_i18n:getText("usedplus_title_offerWithdrawn"),
            message,
            function() end  -- No callback needed
        )
    else
        -- Fallback: Just show notification
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            message
        )
    end

    UsedPlus.logDebug(string.format("Seller backed out dialog shown for: %s", vehicleName or "unknown"))
end

--[[
    Notify player that a vehicle was found
    v1.5.0: Shows notification AND opens UsedVehiclePreviewDialog
    Player can inspect/buy the found vehicle immediately
]]
function UsedVehicleManager:notifyVehicleFound(search, listing, farmId)
    -- Only show if game is running
    if g_currentMission == nil or g_currentMission.isLoading then
        return
    end

    local message = string.format(
        g_i18n:getText("usedplus_notify_vehicleFound") or "Your agent found a %s!",
        search.storeItemName or "vehicle"
    )

    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        message
    )

    UsedPlus.logDebug(string.format("Notified player: vehicle found for search %s", search.id))

    -- v1.5.0: Show the preview dialog so player can act on it immediately
    -- This is the same dialog as before - lets them Inspect or Buy As-Is
    -- v2.13.2: Skip dialog during sleep to prevent freeze (Issue #7)
    -- Notification above still shows, player can view from portfolio after waking
    if listing then
        if g_sleepManager ~= nil and g_sleepManager.isSleeping then
            UsedPlus.logDebug(string.format("notifyVehicleFound: Deferring preview dialog - player is sleeping (%s)", search.storeItemName or "vehicle"))
        else
            self:showSearchResultDialog(listing, farmId)
        end
    end
end

--[[
    Notify player that a search has completed
    v1.5.0: Shows summary of what was found
    v1.5.1: Shows SearchExpiredDialog with renewal option
]]
function UsedVehicleManager:notifySearchComplete(search, farmId)
    -- Only show if game is running
    if g_currentMission == nil or g_currentMission.isLoading then
        return
    end

    local foundCount = #(search.foundListings or {})

    -- Calculate renewal cost (same as original search)
    -- NOTE: search uses searchLevel (1-3), not tier, and basePrice not storeItemPrice
    local renewCost = self:calculateSearchCost(search.searchLevel, search.basePrice or 0, farmId)

    UsedPlus.logDebug(string.format("Search %s complete with %d vehicles, renewCost=$%d, showing expiration dialog",
        search.id, foundCount, renewCost))

    -- v2.13.2: Skip dialog during sleep to prevent freeze (Issue #7)
    -- Falls through to notification fallback below
    if g_sleepManager ~= nil and g_sleepManager.isSleeping then
        UsedPlus.logDebug(string.format("notifySearchComplete: Deferring dialog - player is sleeping (%s)", search.storeItemName or "vehicle"))
        g_currentMission:addIngameNotification(
            foundCount > 0 and FSBaseMission.INGAME_NOTIFICATION_OK or FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format(g_i18n:getText("usedplus_notify_searchComplete") or "Search complete: %d vehicle(s) found for %s",
                foundCount, search.storeItemName or "vehicle")
        )
        return
    end

    -- Show the SearchExpiredDialog with renewal option
    local dialogShown = false

    if SearchExpiredDialog and SearchExpiredDialog.showWithData then
        local self_ref = self
        local success, err = pcall(function()
            dialogShown = SearchExpiredDialog.showWithData(search, foundCount, renewCost, function(renewChoice)
                if renewChoice then
                    -- Player chose to renew - create a new search with same parameters
                    self_ref:renewSearch(search, farmId)
                else
                    -- Player declined - just log it
                    UsedPlus.logDebug(string.format("Player declined to renew search %s", search.id))
                end
            end)
        end)

        if not success then
            UsedPlus.logError(string.format("SearchExpiredDialog.showWithData failed: %s", tostring(err)))
            dialogShown = false
        end
    else
        UsedPlus.logWarn("SearchExpiredDialog or showWithData not available")
    end

    -- Fallback to notification if dialog failed to show
    if not dialogShown then
        UsedPlus.logDebug("Falling back to notification for search completion")
        local message = string.format(
            g_i18n:getText("usedplus_notify_searchComplete") or "Search complete: %d vehicle(s) found for %s",
            foundCount, search.storeItemName or "vehicle"
        )

        g_currentMission:addIngameNotification(
            foundCount > 0 and FSBaseMission.INGAME_NOTIFICATION_OK or FSBaseMission.INGAME_NOTIFICATION_INFO,
            message
        )
    end
end

--[[
    Renew a search with the same parameters
    @param oldSearch - The completed search to renew
    @param farmId - Farm ID
]]
function UsedVehicleManager:renewSearch(oldSearch, farmId)
    -- Calculate cost
    local cost = self:calculateSearchCost(oldSearch.tier, oldSearch.storeItemPrice or 0, farmId)

    -- Check if player can afford
    local farm = g_farmManager:getFarmById(farmId)
    if farm.money < cost then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_notification_insufficientFundsRenew")
        )
        return false
    end

    -- Create new search with same parameters
    local newSearch = UsedVehicleSearch.new(
        oldSearch.storeItemIndex,
        oldSearch.storeItemName,
        oldSearch.storeItemPrice or 0,
        oldSearch.tier,
        oldSearch.qualityTier,
        oldSearch.requestedConfigId
    )

    -- Charge the fee
    farm:changeBalance(-cost, MoneyType.OTHER)

    -- Add to active searches
    self.activeSearches[newSearch.id] = newSearch
    table.insert(farm.usedVehicleSearches, newSearch)

    -- Notify player
    g_currentMission:addIngameNotification(
        FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format(g_i18n:getText("usedplus_notification_searchRenewed"), oldSearch.storeItemName)
    )

    UsedPlus.logInfo(string.format("Renewed search for %s (Tier %d, Quality %d)",
        oldSearch.storeItemName, oldSearch.tier, oldSearch.qualityTier))

    return true
end

--[[
    Calculate search cost based on tier and vehicle price
    @param tier - Search tier (1-3)
    @param vehiclePrice - Base price of vehicle
    @param farmId - Farm ID for credit modifier
    @return cost - Total search cost
]]
function UsedVehicleManager:calculateSearchCost(tier, vehiclePrice, farmId)
    local tierInfo = UsedVehicleSearch.SEARCH_TIERS[tier]
    if not tierInfo then
        return 0
    end

    local baseCost = tierInfo.retainerFlat + (vehiclePrice * tierInfo.retainerPercent)

    -- Apply credit score modifier
    if farmId and CreditScore then
        local score = CreditScore.calculate(farmId)
        local modifier = UsedVehicleSearch.getCreditFeeModifier(score)
        baseCost = baseCost * (1 + modifier)
    end

    return math.floor(baseCost)
end

--[[
    Generate used vehicle listing from partial data returned by processMonthlyCheck
    v1.5.0: Takes basic condition data and adds store item details, configs, commission
    @param search - The UsedVehicleSearch object
    @param listingData - Partial data from processMonthlyCheck (id, damage, wear, age, operatingHours, basePrice)
]]
function UsedVehicleManager:generateUsedVehicleListingFromData(search, listingData)
    -- Get store item data
    local storeItem = g_storeManager:getItemByXMLFilename(search.storeItemIndex)
    if storeItem == nil then
        UsedPlus.logError(string.format("Store item not found for search %s (xmlFilename: %s)",
            search.id, tostring(search.storeItemIndex)))
        return nil
    end

    -- Apply configuration matching if specific config requested
    local selectedConfig = nil
    if search.requestedConfigId then
        local configMatch = self:findMatchingConfiguration(storeItem, search.requestedConfigId)
        if configMatch then
            selectedConfig = configMatch
        else
            selectedConfig = self:selectRandomConfiguration(storeItem)
        end
    else
        selectedConfig = self:selectRandomConfiguration(storeItem)
    end

    -- Generate hidden reliability scores based on damage, age, hours, and quality tier
    local usedPlusData = nil
    if UsedPlusMaintenance and UsedPlusMaintenance.generateReliabilityScores then
        usedPlusData = UsedPlusMaintenance.generateReliabilityScores(
            listingData.damage or 0,
            listingData.age or 1,
            listingData.operatingHours or 100,
            search.qualityLevel  -- DNA bias based on quality tier
        )
    end

    -- v2.1.2: When RVB parts data exists, DERIVE our reliability values from it
    -- This ensures consistency - our Engine/Electrical values match the RVB parts shown
    if listingData.rvbPartsData and usedPlusData then
        local rvbParts = listingData.rvbPartsData

        -- Engine reliability = average of ENGINE + THERMOSTAT (cooling affects engine life)
        local engineLife = (rvbParts.ENGINE and rvbParts.ENGINE.life) or usedPlusData.engineReliability
        local thermoLife = (rvbParts.THERMOSTAT and rvbParts.THERMOSTAT.life) or engineLife
        usedPlusData.engineReliability = (engineLife + thermoLife) / 2

        -- Electrical reliability = average of GENERATOR, BATTERY, SELFSTARTER, GLOWPLUG
        local genLife = (rvbParts.GENERATOR and rvbParts.GENERATOR.life) or 1.0
        local battLife = (rvbParts.BATTERY and rvbParts.BATTERY.life) or 1.0
        local startLife = (rvbParts.SELFSTARTER and rvbParts.SELFSTARTER.life) or 1.0
        local glowLife = (rvbParts.GLOWPLUG and rvbParts.GLOWPLUG.life) or 1.0
        usedPlusData.electricalReliability = (genLife + battLife + startLife + glowLife) / 4

        -- Hydraulic reliability stays as generated (RVB doesn't track hydraulics)

        UsedPlus.logDebug(string.format("Derived reliability from RVB parts: Engine=%.0f%%, Electrical=%.0f%%, Hydraulic=%.0f%%",
            usedPlusData.engineReliability * 100,
            usedPlusData.electricalReliability * 100,
            usedPlusData.hydraulicReliability * 100))
    end

    -- v1.5.0: Calculate commission and asking price
    local basePrice = listingData.basePrice or listingData.price or 0
    local commissionPercent = search.commissionPercent or 0.08
    local commissionAmount = math.floor(basePrice * commissionPercent)
    local askingPrice = basePrice + commissionAmount

    -- v2.6.2: DNA-DRIVEN SELLER PERSONALITY
    -- The seller KNOWS what they have! Lemons = desperate, Workhorses = immovable
    local sellerPersonality = listingData.sellerPersonality or "reasonable"
    if usedPlusData and usedPlusData.workhorseLemonScale then
        local dna = usedPlusData.workhorseLemonScale
        sellerPersonality = UsedVehicleSearch.generateSellerPersonalityFromDNA(dna)
        UsedPlus.logDebug(string.format("DNA %.2f -> Seller personality: %s (overriding %s)",
            dna, sellerPersonality, listingData.sellerPersonality or "none"))
    end

    -- Regenerate whisper based on new personality
    local whisperType = listingData.whisperType
    if sellerPersonality ~= listingData.sellerPersonality then
        -- Personality changed, update whisper hint
        local personalityConfig = UsedVehicleSearch.SELLER_PERSONALITIES[sellerPersonality]
        if personalityConfig then
            whisperType = personalityConfig.whisperHint or "standard"
        end
    end

    -- Create full listing object
    local fullListing = {
        id = listingData.id,
        farmId = search.farmId,
        searchId = search.id,
        storeItemIndex = search.storeItemIndex,
        storeItemName = search.storeItemName,
        configuration = selectedConfig,

        -- Used vehicle stats
        age = listingData.age or 1,
        operatingHours = math.floor(listingData.operatingHours or 100),
        damage = listingData.damage or 0,
        wear = listingData.wear or 0,

        -- v1.5.0: Pricing with commission
        basePrice = basePrice,
        commissionPercent = commissionPercent,
        commissionAmount = commissionAmount,
        askingPrice = askingPrice,
        price = askingPrice,  -- Legacy field for compatibility

        -- Hidden maintenance data
        usedPlusData = usedPlusData,

        -- v2.1.0: RVB/UYT holistic data from generation
        rvbPartsData = listingData.rvbPartsData,
        tireConditions = listingData.tireConditions,

        -- v2.6.0: Negotiation system fields
        sellerPersonality = sellerPersonality,
        daysOnMarket = listingData.daysOnMarket or 0,
        whisperType = whisperType or "standard",
        negotiationLocked = listingData.negotiationLocked or false,
        negotiationLockExpires = listingData.negotiationLockExpires or 0,
        foundMonth = listingData.foundMonth or 0,
        expirationMonths = listingData.expirationMonths or 3,

        -- Metadata
        generationName = listingData.generationName or "Unknown",
        qualityLevel = listingData.qualityLevel or search.qualityLevel,
        qualityName = listingData.qualityName or "Any",
        listingDate = g_currentMission.environment.currentDay,
        status = "available"
    }

    UsedPlus.logDebug(string.format("Generated full listing %s: %s (base $%d + $%d commission = $%d asking)",
        fullListing.id, fullListing.storeItemName,
        fullListing.basePrice, fullListing.commissionAmount, fullListing.askingPrice))
    UsedPlus.logDebug(string.format("  DNA: %.2f, Personality: %s, Whisper: %s",
        usedPlusData and usedPlusData.workhorseLemonScale or 0.5, sellerPersonality, whisperType))

    return fullListing
end

--[[
    Generate used vehicle listing from successful search (LEGACY - kept for compatibility)
    v1.5.0: Updated to include commission calculation
    Uses DepreciationCalculations to create realistic used vehicle
]]
function UsedVehicleManager:generateUsedVehicleListing(search)
    -- Get store item data
    local storeItem = g_storeManager:getItemByXMLFilename(search.storeItemIndex)
    if storeItem == nil then
        UsedPlus.logError(string.format("Store item not found for xmlFilename: %s", tostring(search.storeItemIndex)))
        return nil
    end

    -- Get tier info for quality bounds
    local tierInfo = search.tierInfo or {}

    -- Get quality tier multipliers
    local qualityTier = search.qualityLevel or 2
    local qualityMult = DepreciationCalculations.getQualityTierMultipliers(qualityTier)

    -- Generate random condition within tier bounds
    local minDamage = tierInfo.minDamage or 0
    local maxDamage = tierInfo.maxDamage or 0.5
    local damage = minDamage + math.random() * (maxDamage - minDamage)

    -- Apply quality tier modifier
    damage = damage * qualityMult.wearMult

    -- Generate age (years)
    local minAge = tierInfo.minAge or 1
    local maxAge = tierInfo.maxAge or 10
    local age = minAge + math.random() * (maxAge - minAge)

    -- Generate operating hours based on age
    local hoursPerYear = 200 + math.random() * 300  -- 200-500 hours/year typical farm use
    local operatingHours = math.floor(age * hoursPerYear * qualityMult.hoursMult)

    -- Generate wear (paint condition)
    local wear = damage * (0.8 + math.random() * 0.4)

    -- Calculate depreciated value
    local basePrice = storeItem.price or 0
    local depreciatedValue = DepreciationCalculations.calculateDepreciatedValue(basePrice, age, operatingHours, damage)

    -- Select random configuration
    local selectedConfig = self:selectRandomConfiguration(storeItem)

    -- Generate hidden reliability scores
    local usedPlusData = nil
    if UsedPlusMaintenance and UsedPlusMaintenance.generateReliabilityScores then
        usedPlusData = UsedPlusMaintenance.generateReliabilityScores(damage, age, operatingHours, qualityTier)
    end

    -- v1.5.0: Calculate commission and asking price
    local commissionPercent = search.commissionPercent or 0.08
    local commissionAmount = math.floor(depreciatedValue * commissionPercent)
    local askingPrice = depreciatedValue + commissionAmount

    local listing = {
        id = self:generateListingId(),
        farmId = search.farmId,
        searchId = search.id,
        storeItemIndex = search.storeItemIndex,
        storeItemName = search.storeItemName,
        configuration = selectedConfig,
        age = math.floor(age),
        operatingHours = operatingHours,
        damage = damage,
        wear = wear,
        basePrice = depreciatedValue,
        commissionPercent = commissionPercent,
        commissionAmount = commissionAmount,
        askingPrice = askingPrice,
        price = askingPrice,
        usedPlusData = usedPlusData,
        qualityLevel = qualityTier,
        listingDate = g_currentMission.environment.currentDay,
        status = "available"
    }

    UsedPlus.logDebug(string.format("Generated listing %s: %s (base $%.2f + $%.2f commission = $%.2f asking, %d hrs, %.1f%% damage)",
        listing.id, listing.storeItemName, listing.basePrice, listing.commissionAmount, listing.askingPrice,
        listing.operatingHours, listing.damage * 100))

    return listing
end

UsedPlus.logDebug("VehicleSearchSystem module loaded")
