--[[
    FS25_UsedPlus - Vehicle Spawning Module

    v2.7.2 REFACTORED: Extracted from UsedVehicleManager.lua

    Handles vehicle purchase, spawning, and condition application:
    - showSearchResultDialog: Show preview dialog for found vehicle
    - purchaseUsedVehicle: Handle purchase transaction
    - spawnUsedVehicle: Spawn vehicle via BuyVehicleEvent
    - applyUsedConditionToVehicle: Apply damage, wear, hours to spawned vehicle
    - applyDirtBasedOnQuality: Apply visual dirt based on quality tier
    - applyDelayedDirt: Timer callback for delayed dirt application
    - applyDelayedUYTTireWear: Timer callback for delayed UYT tire wear
    - getVehicleSpawnPosition: Get spawn position near player
    - findMatchingConfiguration: Find matching config from storeItem
    - selectRandomConfiguration: Generate random configs for variety
]]

-- Ensure UsedVehicleManager table exists
UsedVehicleManager = UsedVehicleManager or {}

-- Static table for pending dirt applications (needs to survive timer callbacks)
UsedVehicleManager.pendingDirtApplications = UsedVehicleManager.pendingDirtApplications or {}
UsedVehicleManager.pendingUYTTireApplications = UsedVehicleManager.pendingUYTTireApplications or {}

--[[
    Show the UsedVehiclePreviewDialog for a completed search result
    Allows user to Buy As-Is, Inspect, or Cancel
    @param listing - The generated UsedVehicleListing
    @param farmId - Farm ID of the buyer
]]
function UsedVehicleManager:showSearchResultDialog(listing, farmId)
    -- Only show dialog if game is running and not in loading state
    if g_currentMission == nil or g_currentMission.isLoading then
        UsedPlus.logDebug("Skipping dialog - mission not ready")
        return
    end

    -- Use DialogLoader to show the preview dialog
    -- Capture self explicitly to avoid closure issues
    local manager = self
    local callback = function(confirmed, resultListing)
        UsedPlus.logDebug(string.format("UsedVehicleManager callback invoked: confirmed=%s, resultListing=%s",
            tostring(confirmed), tostring(resultListing and resultListing.storeItemName or "nil")))
        UsedPlus.logDebug(string.format("Callback closure check: manager=%s, farmId=%s",
            tostring(manager), tostring(farmId)))
        if confirmed and resultListing then
            -- User wants to buy - spawn the vehicle
            UsedPlus.logDebug(string.format("Calling purchaseUsedVehicle for %s", resultListing.storeItemName or "Unknown"))
            if manager and manager.purchaseUsedVehicle then
                UsedPlus.logDebug("manager.purchaseUsedVehicle exists, calling it...")
                local purchaseResult = nil
                local success, err = pcall(function()
                    purchaseResult = manager:purchaseUsedVehicle(resultListing, farmId)
                end)
                UsedPlus.logDebug(string.format("pcall returned: success=%s, err=%s, purchaseResult=%s",
                    tostring(success), tostring(err), tostring(purchaseResult)))
                if not success then
                    UsedPlus.logError(string.format("purchaseUsedVehicle FAILED: %s", tostring(err)))
                else
                    UsedPlus.logDebug("purchaseUsedVehicle completed")
                end
            else
                UsedPlus.logError(string.format("CANNOT CALL purchaseUsedVehicle: manager=%s, method=%s",
                    tostring(manager), tostring(manager and manager.purchaseUsedVehicle)))
            end
        else
            -- User cancelled - listing remains available for later
            UsedPlus.logDebug("User cancelled used vehicle purchase")
        end
    end

    -- Show the UsedVehiclePreviewDialog
    if DialogLoader and DialogLoader.show then
        DialogLoader.show("UsedVehiclePreviewDialog", "show", listing, farmId, callback, self)
        UsedPlus.logDebug(string.format("Showing UsedVehiclePreviewDialog for %s", listing.storeItemName or "Unknown"))
    else
        UsedPlus.logWarn("DialogLoader not available - cannot show preview dialog")
    end
end

--[[
    Purchase a used vehicle from a listing
    Called when user confirms purchase in UsedVehiclePreviewDialog
    @param listing - The UsedVehicleListing to purchase
    @param farmId - Farm ID of the buyer
]]
function UsedVehicleManager:purchaseUsedVehicle(listing, farmId)
    UsedPlus.logDebug("=== purchaseUsedVehicle FUNCTION ENTERED (v2025-12-01 BuyVehicleEvent) ===")
    UsedPlus.logDebug(string.format("purchaseUsedVehicle args: listing=%s, farmId=%s",
        tostring(listing and listing.storeItemName or "nil"), tostring(farmId)))
    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then
        UsedPlus.logError("Farm not found for purchase")
        return false
    end

    -- Check if player can afford
    if farm.money < listing.price then
        if not g_dedicatedServer then
            g_currentMission:showBlinkingWarning(
                string.format("Insufficient funds. Need %s", g_i18n:formatMoney(listing.price, 0, true, true)),
                3000
            )
        end
        return false
    end

    -- Deduct money
    g_currentMission:addMoney(-listing.price, farmId, MoneyType.SHOP_VEHICLE_BUY, true, true)

    -- Spawn the vehicle
    local success = self:spawnUsedVehicle(listing, farmId)

    if success then
        -- Remove listing from available listings
        self:removeListing(listing, farmId)

        -- v1.7.1: End the search when a vehicle is purchased - player found what they wanted
        if listing.searchId then
            self:endSearchAfterPurchase(listing.searchId, farmId)
        end

        -- Track statistics
        if g_financeManager then
            g_financeManager:incrementStatistic(farmId, "usedPurchases", 1)
            -- Calculate and track savings from buying used (vs new price)
            local savings = (listing.basePrice or 0) - (listing.price or 0)
            if savings > 0 then
                g_financeManager:incrementStatistic(farmId, "totalSavingsFromUsed", savings)
                UsedPlus.logDebug(string.format("Tracked used vehicle savings: $%.0f (base $%.0f - paid $%.0f)",
                    savings, listing.basePrice or 0, listing.price or 0))
            end
        end

        -- Use addGameNotification (pattern from BuyUsedEquipment)
        g_currentMission:addGameNotification(
            "Purchase Complete",
            "",
            string.format("Purchased %s for %s. Check near your position!",
                listing.storeItemName,
                g_i18n:formatMoney(listing.price, 0, true, true)),
            nil,
            10000
        )

        UsedPlus.logDebug(string.format("Used vehicle purchased: %s for $%.2f", listing.storeItemName, listing.price))
        return true
    else
        -- Refund if spawn failed
        g_currentMission:addMoney(listing.price, farmId, MoneyType.OTHER, true, true)
        if not g_dedicatedServer then
            g_currentMission:showBlinkingWarning(g_i18n:getText("usedplus_error_spawnFailed"), 5000)
        end
        return false
    end
end

--[[
    Spawn a used vehicle from listing
    Uses BuyVehicleData/BuyVehicleEvent - the proper FS25 vehicle purchase API
    @param listing - The UsedVehicleListing
    @param farmId - Owner farm ID
    @return boolean success
]]
function UsedVehicleManager:spawnUsedVehicle(listing, farmId)
    UsedPlus.logDebug("=== spawnUsedVehicle ENTERED (using BuyVehicleData API) ===")
    UsedPlus.logDebug(string.format("spawnUsedVehicle: storeItemIndex=%s", tostring(listing.storeItemIndex)))

    local storeItem = g_storeManager:getItemByXMLFilename(listing.storeItemIndex)
    if storeItem == nil then
        UsedPlus.logError("Could not find store item for spawning")
        return false
    end

    UsedPlus.logDebug(string.format("Store item: %s", tostring(storeItem.name)))

    -- Check if BuyVehicleData and BuyVehicleEvent are available
    if BuyVehicleData == nil then
        UsedPlus.logError("BuyVehicleData class not available")
        return false
    end
    if BuyVehicleEvent == nil then
        UsedPlus.logError("BuyVehicleEvent class not available")
        return false
    end

    -- Build configurations table from listing's random configuration
    local configTable = {}
    if listing.configuration then
        for configName, configValue in pairs(listing.configuration) do
            configTable[configName] = configValue
        end
    end

    -- Log the configurations being used
    local configCount = 0
    for k, v in pairs(configTable) do
        UsedPlus.logDebug(string.format("  Config: %s = %s", tostring(k), tostring(v)))
        configCount = configCount + 1
    end
    UsedPlus.logDebug(string.format("Total configurations: %d", configCount))

    UsedPlus.logDebug("Creating BuyVehicleData...")

    -- Create BuyVehicleData - the proper FS25 way to purchase vehicles
    local buyData = BuyVehicleData.new()
    buyData:setOwnerFarmId(farmId)
    buyData:setPrice(0)  -- Price already deducted in purchaseUsedVehicle
    buyData:setStoreItem(storeItem)
    buyData:setConfigurations(configTable)

    -- Set configuration data if available (for appearance like colors)
    if buyData.setConfigurationData then
        buyData:setConfigurationData({})
    end

    -- Set license plate data if method exists
    if buyData.setLicensePlateData then
        buyData:setLicensePlateData(nil)
    end

    -- Store pending purchase so we can apply used condition after spawn
    -- Key by xmlFilename + farmId to handle multiple purchases
    local pendingKey = storeItem.xmlFilename .. "_" .. tostring(farmId) .. "_" .. tostring(g_currentMission.time)
    self.pendingUsedPurchases[pendingKey] = {
        listing = listing,
        farmId = farmId,
        xmlFilename = storeItem.xmlFilename,
        timestamp = g_currentMission.time,
        storeItemName = listing.storeItemName or storeItem.name or "unknown",
        category = storeItem.category or "unknown",
    }
    UsedPlus.logDebug(string.format("Stored pending purchase: %s (item: %s, category: %s)",
        pendingKey, self.pendingUsedPurchases[pendingKey].storeItemName, self.pendingUsedPurchases[pendingKey].category))

    UsedPlus.logDebug("Sending BuyVehicleEvent...")

    -- Send the event - this triggers the proper vehicle spawning
    local success, err = pcall(function()
        g_client:getServerConnection():sendEvent(BuyVehicleEvent.new(buyData))
    end)

    if success then
        UsedPlus.logDebug("BuyVehicleEvent sent successfully - condition will be applied in onBought hook")
        return true
    else
        UsedPlus.logError(string.format("BuyVehicleEvent failed: %s", tostring(err)))
        -- Clean up pending purchase on failure
        self.pendingUsedPurchases[pendingKey] = nil
        return false
    end
end

--[[
    Apply used condition to a spawned vehicle
    Sets damage, wear, operating hours, and UsedPlus reliability data
    Uses FS25 Wearable spec methods (pattern from RealisticWeather, Courseplay)
    @param vehicle - The spawned vehicle
    @param listing - The UsedVehicleListing with condition data
]]
function UsedVehicleManager:applyUsedConditionToVehicle(vehicle, listing)
    if vehicle == nil then
        UsedPlus.logWarn("applyUsedConditionToVehicle: vehicle is nil")
        return
    end

    UsedPlus.logDebug(string.format("applyUsedConditionToVehicle: Applying to %s", tostring(vehicle.typeName or "unknown")))

    -- Apply damage and wear via spec_wearable (FS25 pattern)
    local wearable = vehicle.spec_wearable
    if wearable then
        -- Apply damage - use addDamageAmount since vehicle starts at 0
        if listing.damage and listing.damage > 0 then
            if wearable.addDamageAmount then
                wearable:addDamageAmount(listing.damage, true)
                UsedPlus.logDebug(string.format("  Added damage via spec_wearable: %.2f", listing.damage))
            elseif vehicle.addDamageAmount then
                vehicle:addDamageAmount(listing.damage, true)
                UsedPlus.logDebug(string.format("  Added damage via vehicle: %.2f", listing.damage))
            end
        end

        -- Apply wear - use addWearAmount since vehicle starts at 0
        if listing.wear and listing.wear > 0 then
            if wearable.addWearAmount then
                wearable:addWearAmount(listing.wear, true)
                UsedPlus.logDebug(string.format("  Added wear via spec_wearable: %.2f", listing.wear))
            elseif vehicle.addWearAmount then
                vehicle:addWearAmount(listing.wear, true)
                UsedPlus.logDebug(string.format("  Added wear via vehicle: %.2f", listing.wear))
            end
        end
    else
        UsedPlus.logDebug("  No spec_wearable found, trying vehicle methods directly")
        -- Fallback to vehicle-level methods
        if listing.damage and listing.damage > 0 and vehicle.addDamageAmount then
            vehicle:addDamageAmount(listing.damage, true)
        end
        if listing.wear and listing.wear > 0 and vehicle.addWearAmount then
            vehicle:addWearAmount(listing.wear, true)
        end
    end

    -- Apply operating hours via setOperatingTime (takes milliseconds)
    if listing.operatingHours and listing.operatingHours > 0 then
        local operatingTimeMs = listing.operatingHours * 60 * 60 * 1000
        if vehicle.setOperatingTime then
            vehicle:setOperatingTime(operatingTimeMs)
            UsedPlus.logDebug(string.format("  Set operating time: %d hours (%d ms)", listing.operatingHours, operatingTimeMs))
        else
            UsedPlus.logDebug("  setOperatingTime not available")
        end
    end

    -- v2.8.0: Apply vehicle age (FS25 stores age in months)
    -- listing.age is in YEARS, vehicle.age is in MONTHS
    if listing.age and listing.age > 0 then
        local ageInMonths = listing.age * 12
        vehicle.age = ageInMonths
        UsedPlus.logDebug(string.format("  Set vehicle age: %d years (%d months)", listing.age, ageInMonths))
    end

    -- Apply UsedPlus maintenance data (hidden reliability scores)
    if listing.usedPlusData then
        UsedPlusMaintenance.setUsedPurchaseData(vehicle, listing.usedPlusData)
        UsedPlus.logDebug(string.format("  Applied UsedPlus data: DNA=%.2f, Engine=%.2f, Hydraulic=%.2f",
            listing.usedPlusData.workhorseLemonScale or 0.5,
            listing.usedPlusData.engineReliability or 1,
            listing.usedPlusData.hydraulicReliability or 1))
    end

    -- After UsedPlus maintenance data applied, check for Service Truck discovery
    -- Only trigger for National Agent purchases (qualityLevel 3)
    if listing.qualityLevel == 3 then
        local farmId = vehicle:getOwnerFarmId()
        if ServiceTruckDiscovery and ServiceTruckDiscovery.onNationalAgentTransaction then
            ServiceTruckDiscovery.onNationalAgentTransaction(farmId, "purchase")
        end
    end

    -- v2.1.0: Apply RVB parts data if RVB is installed
    if listing.rvbPartsData and ModCompatibility and ModCompatibility.rvbInstalled then
        ModCompatibility.initializeRVBPartsFromListing(vehicle, listing.rvbPartsData)
        UsedPlus.logDebug("  Applied RVB parts data")
    end

    -- v2.1.0: Apply UYT tire conditions if UYT is installed
    if listing.tireConditions and ModCompatibility and ModCompatibility.uytInstalled then
        -- Defer tire application slightly to ensure UYT has initialized
        local uytKey = "uyt_" .. tostring(vehicle.id or "") .. "_" .. tostring(g_currentMission.time)
        UsedVehicleManager.pendingUYTTireApplications = UsedVehicleManager.pendingUYTTireApplications or {}
        UsedVehicleManager.pendingUYTTireApplications[uytKey] = {
            vehicle = vehicle,
            tireConditions = listing.tireConditions
        }
        addTimer(500, "applyDelayedUYTTireWear", uytKey, self)
        UsedPlus.logDebug("  Scheduled delayed UYT tire wear application")
    end

    -- v1.9.5: Apply dirt based on quality tier (delayed to ensure vehicle is fully loaded)
    local dirtKey = "dirt_" .. tostring(vehicle.id or "") .. "_" .. tostring(g_currentMission.time)
    UsedVehicleManager.pendingDirtApplications[dirtKey] = {
        vehicle = vehicle,
        listing = listing
    }
    addTimer(1000, "applyDelayedDirt", dirtKey, self)
    UsedPlus.logDebug("  Scheduled delayed dirt application")
end

--[[
    Apply dirt/grime based on quality tier
    Lower quality = more dirt to reflect lack of maintenance
    @param vehicle - The vehicle to dirty
    @param qualityLevel - 1=Economy, 2=Standard, 3=Premium, 4=Certified
    @param damage - Damage level (0-1) to influence dirt
]]
function UsedVehicleManager:applyDirtBasedOnQuality(vehicle, qualityLevel, damage)
    if vehicle == nil then
        UsedPlus.logDebug("applyDirtBasedOnQuality: vehicle is nil")
        return
    end

    -- Calculate dirt amount based on quality tier
    -- Economy (1) = 60-80% dirty, Standard (2) = 30-50%, Premium (3) = 10-20%, Certified (4) = 0-5%
    local baseDirt = 0.5
    if qualityLevel == 1 then
        baseDirt = 0.6 + math.random() * 0.2  -- 60-80%
    elseif qualityLevel == 2 then
        baseDirt = 0.3 + math.random() * 0.2  -- 30-50%
    elseif qualityLevel == 3 then
        baseDirt = 0.1 + math.random() * 0.1  -- 10-20%
    elseif qualityLevel == 4 then
        baseDirt = math.random() * 0.05       -- 0-5%
    end

    -- Damage also adds dirt (damaged vehicles are usually dirtier)
    local damageDirt = (damage or 0) * 0.3
    local finalDirt = math.min(baseDirt + damageDirt, 1.0)

    UsedPlus.logDebug(string.format("applyDirtBasedOnQuality: quality=%d, baseDirt=%.2f, damageDirt=%.2f, final=%.2f",
        qualityLevel or 0, baseDirt, damageDirt, finalDirt))

    -- Apply dirt via spec_washable if available
    local washable = vehicle.spec_washable
    if washable == nil then
        UsedPlus.logDebug("  No spec_washable found")
        return
    end

    -- Method 1: Use setDirtAmount if available (preferred)
    if washable.setDirtAmount then
        washable:setDirtAmount(finalDirt, true)
        UsedPlus.logDebug(string.format("  Applied dirt via setDirtAmount: %.2f", finalDirt))
        return
    end

    -- Method 2: Use addDirtAmount if available
    if washable.addDirtAmount then
        washable:addDirtAmount(finalDirt, true)
        UsedPlus.logDebug(string.format("  Applied dirt via addDirtAmount: %.2f", finalDirt))
        return
    end

    -- Method 3: Directly set dirt node values via shader parameters
    if washable.washableNodes then
        local nodesApplied = 0
        for _, nodeData in ipairs(washable.washableNodes) do
            if nodeData.node and entityExists(nodeData.node) then
                -- FS25 dirt is typically controlled via shader parameter
                local success = pcall(function()
                    setShaderParameter(nodeData.node, "RDT", finalDirt, 0, 0, 0, false)
                end)
                if success then
                    nodesApplied = nodesApplied + 1
                end
            end
        end
        UsedPlus.logDebug(string.format("  Applied dirt via shaders to %d nodes, finalDirt=%.2f", nodesApplied, finalDirt))
    end

    -- Raise dirty flags for network sync if on server
    if washable.dirtyFlag and vehicle.raiseDirtyFlags then
        vehicle:raiseDirtyFlags(washable.dirtyFlag)
    end
end

--[[
    Timer callback for delayed dirt application
    Called by addTimer after vehicle has fully spawned
    @param dirtKey - Key to look up pending dirt application data
]]
function UsedVehicleManager:applyDelayedDirt(dirtKey)
    UsedPlus.logDebug(string.format("applyDelayedDirt called with key: %s", tostring(dirtKey)))

    if UsedVehicleManager.pendingDirtApplications == nil then
        UsedPlus.logDebug("No pending dirt applications table")
        return
    end

    local data = UsedVehicleManager.pendingDirtApplications[dirtKey]
    if data == nil then
        UsedPlus.logDebug(string.format("No pending dirt data for key: %s", tostring(dirtKey)))
        return
    end

    local vehicle = data.vehicle
    local listing = data.listing

    -- Clean up
    UsedVehicleManager.pendingDirtApplications[dirtKey] = nil

    -- Apply dirt if vehicle still exists
    if vehicle ~= nil and not vehicle.isDeleted then
        UsedPlus.logDebug(string.format("Applying delayed dirt to %s, qualityLevel=%s",
            tostring(vehicle:getName()), tostring(listing.qualityLevel)))
        self:applyDirtBasedOnQuality(vehicle, listing.qualityLevel, listing.damage)
    else
        UsedPlus.logDebug("Vehicle was deleted before dirt could be applied")
    end
end

--[[
    Apply delayed UYT tire wear after vehicle is fully loaded
    This ensures UYT's wheel data structures are ready before we set wear

    @param uytKey - Key to look up pending tire data
]]
function UsedVehicleManager:applyDelayedUYTTireWear(uytKey)
    UsedPlus.logDebug(string.format("applyDelayedUYTTireWear called with key: %s", tostring(uytKey)))

    if UsedVehicleManager.pendingUYTTireApplications == nil then
        UsedPlus.logDebug("No pending UYT tire applications table")
        return
    end

    local data = UsedVehicleManager.pendingUYTTireApplications[uytKey]
    if data == nil then
        UsedPlus.logDebug(string.format("No pending UYT tire data for key: %s", tostring(uytKey)))
        return
    end

    local vehicle = data.vehicle
    local tireConditions = data.tireConditions

    -- Clean up
    UsedVehicleManager.pendingUYTTireApplications[uytKey] = nil

    -- Apply UYT tire wear if vehicle still exists and UYT is available
    if vehicle ~= nil and not vehicle.isDeleted then
        local uyt = ModCompatibility and ModCompatibility.uytGlobal
        if ModCompatibility and ModCompatibility.uytInstalled and uyt then
            if vehicle.spec_wheels and vehicle.spec_wheels.wheels then
                local wheelCount = #vehicle.spec_wheels.wheels
                local tireKeys = { "FL", "FR", "RL", "RR" }

                UsedPlus.logDebug(string.format("Applying delayed UYT tire wear to %s (%d wheels)",
                    tostring(vehicle:getName()), wheelCount))

                for i = 1, math.min(wheelCount, 4) do
                    local wheel = vehicle.spec_wheels.wheels[i]
                    local condition = tireConditions[tireKeys[i]] or 1.0
                    local wear = 1.0 - condition

                    -- Try to set UYT wear if the API is available
                    if wheel and uyt.setWearAmount then
                        uyt.setWearAmount(wheel, wear)
                        UsedPlus.logDebug(string.format("  Delayed UYT wheel %d: Set wear to %.0f%%",
                            i, wear * 100))
                    elseif wheel then
                        UsedPlus.logDebug(string.format("  Wheel %d exists but uyt.setWearAmount not available", i))
                    end
                end
            else
                UsedPlus.logDebug("Vehicle has no spec_wheels or wheels table")
            end
        else
            UsedPlus.logDebug("UYT not installed or ModCompatibility not available")
        end
    else
        UsedPlus.logDebug("Vehicle was deleted before UYT tire wear could be applied")
    end
end

--[[
    Get spawn position near player
]]
function UsedVehicleManager:getVehicleSpawnPosition()
    if g_currentMission.player and g_currentMission.player.rootNode then
        local playerX, playerY, playerZ = getWorldTranslation(g_currentMission.player.rootNode)
        local dirX, _, dirZ = localDirectionToWorld(g_currentMission.player.rootNode, 0, 0, 1)
        return playerX + dirX * 5, playerY, playerZ + dirZ * 5
    end
    -- Fallback to map center
    local mapSize = g_currentMission.terrainSize / 2
    return mapSize, 0, mapSize
end

--[[
    Find configuration matching requested ID
    Compares configuration IDs from shop system
]]
function UsedVehicleManager:findMatchingConfiguration(storeItem, requestedConfigId)
    if storeItem.configurations == nil then
        return nil
    end

    -- Search through available configurations
    for _, config in ipairs(storeItem.configurations) do
        if config.id == requestedConfigId then
            return config
        end
    end

    return nil
end

--[[
    Generate random configurations for ALL available configuration types
    This makes used vehicles feel unique with random wheels, colors, designs, etc.
    Returns table like { wheel = 3, design = 2, color = 5, ... }
]]
function UsedVehicleManager:selectRandomConfiguration(storeItem)
    local randomConfigs = {}

    -- Get the vehicle's XML to find all available configurations
    local xmlFilename = storeItem.xmlFilename
    if xmlFilename == nil then
        UsedPlus.logDebug("selectRandomConfiguration: No xmlFilename, using empty config")
        return randomConfigs
    end

    -- Try to get configurations from ConfigurationUtil
    local configSets = nil

    -- Method 1: Try to get from g_configurationManager if available
    if g_configurationManager and g_configurationManager.configurations then
        configSets = g_configurationManager.configurations[xmlFilename]
    end

    -- Method 2: Use storeItem.configurations directly
    if configSets == nil and storeItem.configurations then
        -- v1.9.5: SKIP wheel-related configurations entirely to avoid physics issues
        local skipConfigs = {
            wheel = true,
            wheels = true,
            tire = true,
            tireRear = true,
            tireFront = true,
            wheelBrand = true
        }

        for configName, configData in pairs(storeItem.configurations) do
            -- Skip wheel-related configs to avoid physics issues
            if skipConfigs[configName] then
                UsedPlus.logTrace(string.format("  Skipping config: %s (wheel-related, using default)", configName))
            elseif type(configData) == "table" then
                -- configData is an array of options - pick random index
                local numOptions = #configData
                if numOptions > 0 then
                    randomConfigs[configName] = math.random(1, numOptions)
                    UsedPlus.logTrace(string.format("  Random config: %s = %d (of %d options)",
                        configName, randomConfigs[configName], numOptions))
                end
            elseif type(configData) == "number" then
                -- configData is the number of options - pick random
                if configData > 0 then
                    randomConfigs[configName] = math.random(1, configData)
                end
            end
        end
    end

    -- Method 3: Use StoreItemUtil to get configuration items if available
    if next(randomConfigs) == nil and StoreItemUtil and StoreItemUtil.getConfigurationsFromXML then
        UsedPlus.logDebug("selectRandomConfiguration: Trying StoreItemUtil method")
    end

    -- Method 4: If vehicle type has known common configuration types, randomize those
    if next(randomConfigs) == nil then
        local skipConfigs = {
            wheel = true,
            wheels = true,
            tire = true,
            tireRear = true,
            tireFront = true,
            wheelBrand = true
        }

        -- Check if storeItem has configurationSets (preset combinations)
        if storeItem.configurationSets and #storeItem.configurationSets > 0 then
            -- Pick a random preset as our base
            local randomPreset = storeItem.configurationSets[math.random(1, #storeItem.configurationSets)]
            if randomPreset and randomPreset.configurations then
                for k, v in pairs(randomPreset.configurations) do
                    -- Skip wheel-related configs to avoid physics issues
                    if not skipConfigs[k] then
                        randomConfigs[k] = v
                    else
                        UsedPlus.logTrace(string.format("  Skipping preset config: %s (wheel-related)", k))
                    end
                end
                local presetCount = 0
                for _ in pairs(randomConfigs) do presetCount = presetCount + 1 end
                UsedPlus.logDebug(string.format("selectRandomConfiguration: Using random preset with %d configs (wheel configs excluded)", presetCount))
            end
        end
    end

    -- Count configurations
    local configCount = 0
    for _ in pairs(randomConfigs) do configCount = configCount + 1 end
    UsedPlus.logDebug(string.format("selectRandomConfiguration: Generated %d random configurations", configCount))

    return randomConfigs
end

UsedPlus.logDebug("VehicleSpawning module loaded")
