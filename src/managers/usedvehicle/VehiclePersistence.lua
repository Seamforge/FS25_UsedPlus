--[[
    FS25_UsedPlus - Vehicle Persistence Module

    v2.7.2 REFACTORED: Extracted from UsedVehicleManager.lua

    Handles save/load for used vehicle searches and listings:
    - saveToXMLFile: Save all searches and listings to savegame
    - saveListingToXMLFile: Save individual listing to XML
    - loadFromXMLFile: Load all searches and listings from savegame
    - loadListingFromXMLFile: Load individual listing from XML
]]

-- Ensure UsedVehicleManager table exists
UsedVehicleManager = UsedVehicleManager or {}

--[[
    Save all searches and listings to savegame
    Pattern from: BuyUsedEquipment nested XML serialization
]]
function UsedVehicleManager:saveToXMLFile(missionInfo)
    local savegameDirectory = missionInfo.savegameDirectory
    if savegameDirectory == nil then return end

    local filePath = savegameDirectory .. "/usedPlusVehicles.xml"
    local xmlFile = XMLFile.create("usedPlusVehiclesXML", filePath, "usedPlusVehicles")

    if xmlFile ~= nil then
        -- Save next ID counter
        xmlFile:setInt("usedPlusVehicles#nextSearchId", self.nextSearchId)

        -- v2.7.0: Save total game hours for inspection timing
        xmlFile:setInt("usedPlusVehicles#totalGameHours", self.totalGameHours or 0)

        -- v2.7.0: Save last processed day for time jump detection
        xmlFile:setInt("usedPlusVehicles#lastProcessedDay", self.lastProcessedDay or 0)

        -- Save searches and listings grouped by farm
        -- Note: pairs() key may not equal farm.farmId, so use farm.farmId consistently
        local farmIndex = 0
        for _, farm in pairs(g_farmManager:getFarms()) do
            local farmId = farm.farmId
            local hasSaveData = false

            -- Check if farm has searches or listings
            if (farm.usedVehicleSearches and #farm.usedVehicleSearches > 0) or
               (farm.usedVehicleListings and #farm.usedVehicleListings > 0) then
                hasSaveData = true
            end

            if hasSaveData then
                local farmKey = string.format("usedPlusVehicles.farms.farm(%d)", farmIndex)
                xmlFile:setInt(farmKey .. "#farmId", farmId)

                -- Save active searches
                if farm.usedVehicleSearches then
                    local searchIndex = 0
                    for _, search in ipairs(farm.usedVehicleSearches) do
                        local searchKey = string.format(farmKey .. ".search(%d)", searchIndex)
                        search:saveToXMLFile(xmlFile, searchKey)
                        searchIndex = searchIndex + 1
                    end
                end

                -- Save available listings
                if farm.usedVehicleListings then
                    local listingIndex = 0
                    for _, listing in ipairs(farm.usedVehicleListings) do
                        local listingKey = string.format(farmKey .. ".listing(%d)", listingIndex)
                        self:saveListingToXMLFile(xmlFile, listingKey, listing)
                        listingIndex = listingIndex + 1
                    end
                end

                farmIndex = farmIndex + 1
            end
        end

        xmlFile:save()
        xmlFile:delete()

        UsedPlus.logInfo(string.format("VehiclePersistence: Saved %d searches across %d farms to %s",
            self:getTotalSearchCount(), farmIndex, filePath))
    end
end

--[[
    Save listing to XML
    Listings are tables, not objects, so manual serialization
]]
function UsedVehicleManager:saveListingToXMLFile(xmlFile, key, listing)
    xmlFile:setString(key .. "#id", listing.id)
    xmlFile:setInt(key .. "#farmId", listing.farmId)
    xmlFile:setString(key .. "#searchId", listing.searchId or "")
    -- storeItemIndex is actually the xmlFilename (string), NOT an integer!
    xmlFile:setString(key .. "#storeItemXmlFilename", listing.storeItemIndex)
    xmlFile:setString(key .. "#storeItemName", listing.storeItemName)

    -- Configuration (if present)
    if listing.configuration then
        xmlFile:setString(key .. "#configId", listing.configuration.id or "default")
        xmlFile:setString(key .. "#configName", listing.configuration.name or "Default")
    end

    -- Used vehicle stats
    xmlFile:setInt(key .. "#age", listing.age)
    xmlFile:setInt(key .. "#operatingHours", listing.operatingHours)
    xmlFile:setFloat(key .. "#damage", listing.damage)
    xmlFile:setFloat(key .. "#wear", listing.wear)
    xmlFile:setFloat(key .. "#price", listing.price)

    -- Metadata
    xmlFile:setString(key .. "#generationName", listing.generationName)
    xmlFile:setInt(key .. "#listingDate", listing.listingDate)
    xmlFile:setInt(key .. "#expirationTTL", listing.expirationTTL or 72)
    xmlFile:setString(key .. "#status", listing.status)

    -- Hidden maintenance data (Phase 3)
    if listing.usedPlusData then
        xmlFile:setFloat(key .. "#engineReliability", listing.usedPlusData.engineReliability or 1.0)
        xmlFile:setFloat(key .. "#hydraulicReliability", listing.usedPlusData.hydraulicReliability or 1.0)
        xmlFile:setFloat(key .. "#electricalReliability", listing.usedPlusData.electricalReliability or 1.0)
        xmlFile:setBool(key .. "#wasInspected", listing.usedPlusData.wasInspected or false)
    end
end

--[[
    Load all searches and listings from savegame
    Reconstructs search and listing objects from XML data
]]
function UsedVehicleManager:loadFromXMLFile(missionInfo)
    local savegameDirectory = missionInfo.savegameDirectory
    if savegameDirectory == nil then
        UsedPlus.logWarn("loadFromXMLFile: No savegame directory")
        return
    end

    local filePath = savegameDirectory .. "/usedPlusVehicles.xml"
    UsedPlus.logInfo(string.format("Loading used vehicle data from: %s", filePath))

    local xmlFile = XMLFile.loadIfExists("usedPlusVehiclesXML", filePath, "usedPlusVehicles")

    if xmlFile ~= nil then
        -- Load next ID counter
        self.nextSearchId = xmlFile:getInt("usedPlusVehicles#nextSearchId", 1)

        -- v2.7.0: Load total game hours for inspection timing
        self.totalGameHours = xmlFile:getInt("usedPlusVehicles#totalGameHours", 0)

        -- v2.7.0: Load last processed day for time jump detection
        self.lastProcessedDay = xmlFile:getInt("usedPlusVehicles#lastProcessedDay", 0)

        UsedPlus.logDebug(string.format("  nextSearchId=%d, totalGameHours=%d, lastProcessedDay=%d",
            self.nextSearchId, self.totalGameHours, self.lastProcessedDay))

        -- Count farms in XML for debugging
        local farmCount = 0
        local searchCount = 0
        local listingCount = 0

        -- Load searches and listings
        xmlFile:iterate("usedPlusVehicles.farms.farm", function(_, farmKey)
            local farmId = xmlFile:getInt(farmKey .. "#farmId")
            local farm = g_farmManager:getFarmById(farmId)
            farmCount = farmCount + 1

            UsedPlus.logDebug(string.format("  Processing farm %d from XML (found: %s)",
                farmId, tostring(farm ~= nil)))

            if farm then
                -- Ensure farm has data structures initialized
                if farm.usedVehicleSearches == nil then
                    farm.usedVehicleSearches = {}
                    UsedPlus.logDebug(string.format("    Initialized usedVehicleSearches for farm %d", farmId))
                end
                if farm.usedVehicleListings == nil then
                    farm.usedVehicleListings = {}
                    UsedPlus.logDebug(string.format("    Initialized usedVehicleListings for farm %d", farmId))
                end

                -- Load searches
                xmlFile:iterate(farmKey .. ".search", function(_, searchKey)
                    local search = UsedVehicleSearch.new()
                    if search:loadFromXMLFile(xmlFile, searchKey) then
                        self:registerSearch(search)
                        searchCount = searchCount + 1
                        UsedPlus.logInfo(string.format("    Loaded search: %s (%s)",
                            search.id, search.storeItemName or "Unknown"))
                    else
                        UsedPlus.logWarn(string.format("    Failed to load search from %s", searchKey))
                    end
                end)

                -- Load listings
                xmlFile:iterate(farmKey .. ".listing", function(_, listingKey)
                    local listing = self:loadListingFromXMLFile(xmlFile, listingKey)
                    if listing then
                        table.insert(farm.usedVehicleListings, listing)
                        listingCount = listingCount + 1
                        UsedPlus.logInfo(string.format("    Loaded listing: %s (%s)",
                            listing.id, listing.storeItemName or "Unknown"))
                    else
                        UsedPlus.logWarn(string.format("    Failed to load listing from %s", listingKey))
                    end
                end)
            else
                UsedPlus.logError(string.format("  FARM %d NOT FOUND - searches/listings will be lost!", farmId))
            end
        end)

        xmlFile:delete()

        UsedPlus.logInfo(string.format("VehiclePersistence: Loaded %d searches, %d listings from %d farms",
            searchCount, listingCount, farmCount))

        -- Verify what's in memory after load
        local verifyCount = 0
        for _, search in pairs(self.activeSearches) do
            verifyCount = verifyCount + 1
        end
        UsedPlus.logDebug(string.format("  Verification: %d searches in activeSearches table", verifyCount))
    else
        UsedPlus.logInfo(string.format("VehiclePersistence: No file found at %s (new game or first run)", filePath))
    end
end

--[[
    Load listing from XML
    Manual reconstruction of listing table
]]
function UsedVehicleManager:loadListingFromXMLFile(xmlFile, key)
    local listing = {}

    listing.id = xmlFile:getString(key .. "#id")
    listing.farmId = xmlFile:getInt(key .. "#farmId")
    listing.searchId = xmlFile:getString(key .. "#searchId")
    -- storeItemIndex is actually the xmlFilename (string), NOT an integer!
    -- Try new attribute name first, fall back to old for save compatibility
    listing.storeItemIndex = xmlFile:getString(key .. "#storeItemXmlFilename")
    if listing.storeItemIndex == nil or listing.storeItemIndex == "" then
        -- Old saves might have it as storeItemIndex (incorrectly as int, would be nil)
        listing.storeItemIndex = xmlFile:getString(key .. "#storeItemIndex")
    end
    listing.storeItemName = xmlFile:getString(key .. "#storeItemName")

    -- Configuration
    local configId = xmlFile:getString(key .. "#configId")
    if configId then
        listing.configuration = {
            id = configId,
            name = xmlFile:getString(key .. "#configName", "Default")
        }
    end

    -- Used vehicle stats
    listing.age = xmlFile:getInt(key .. "#age", 0)
    listing.operatingHours = xmlFile:getInt(key .. "#operatingHours", 0)
    listing.damage = xmlFile:getFloat(key .. "#damage", 0)
    listing.wear = xmlFile:getFloat(key .. "#wear", 0)
    listing.price = xmlFile:getFloat(key .. "#price", 0)

    -- Metadata
    listing.generationName = xmlFile:getString(key .. "#generationName", "Unknown")
    listing.listingDate = xmlFile:getInt(key .. "#listingDate", 0)
    listing.expirationTTL = xmlFile:getInt(key .. "#expirationTTL", 72)
    listing.status = xmlFile:getString(key .. "#status", "available")

    -- Hidden maintenance data (Phase 3)
    local engineReliability = xmlFile:getFloat(key .. "#engineReliability", nil)
    if engineReliability ~= nil then
        listing.usedPlusData = {
            engineReliability = engineReliability,
            hydraulicReliability = xmlFile:getFloat(key .. "#hydraulicReliability", 1.0),
            electricalReliability = xmlFile:getFloat(key .. "#electricalReliability", 1.0),
            wasInspected = xmlFile:getBool(key .. "#wasInspected", false)
        }
    end

    -- Validate required fields
    if listing.id == nil or listing.storeItemIndex == nil then
        UsedPlus.logWarn(string.format("Invalid listing data at %s", key))
        return nil
    end

    return listing
end

UsedPlus.logDebug("VehiclePersistence module loaded")
