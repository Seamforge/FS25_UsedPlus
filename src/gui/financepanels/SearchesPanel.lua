--[[
    FS25_UsedPlus - Searches Panel Module

    v2.7.2 REFACTORED: Extracted from FinanceManagerFrame.lua

    Handles the Searches section of the Finance Manager:
    - updateSearchesSection: Display active searches and ready listings
    - onInfoSearchClick: Show search/listing details
    - onCancelSearchClick: Cancel an active search
    - Row click/hover handlers
]]

-- Ensure FinanceManagerFrame table exists
FinanceManagerFrame = FinanceManagerFrame or {}

--[[
    Update Searches section with row-based table display
    Shows both active searches AND available listings (results ready for purchase)
]]
function FinanceManagerFrame:updateSearchesSection(farmId)
    -- Check if used vehicle search system is enabled
    local searchEnabled = true
    if UsedPlusSettings and UsedPlusSettings.get then
        searchEnabled = UsedPlusSettings:get("enableUsedVehicleSearch") ~= false
    end

    local maxSearches = FinanceManagerFrame.MAX_SEARCH_ROWS

    -- Hide all rows first
    for i = 0, FinanceManagerFrame.MAX_SEARCH_ROWS - 1 do
        if self.searchRows[i] and self.searchRows[i].row then
            self.searchRows[i].row:setVisible(false)
        end
    end

    -- If system disabled, show message and return
    if not searchEnabled then
        if self.searchEmptyText then
            self.searchEmptyText:setText(g_i18n:getText("usedplus_fmf_searchDisabled") or "Used vehicle search disabled in settings")
            self.searchEmptyText:setVisible(true)
        end
        return
    end

    local searchCount = 0
    local totalCost = 0

    -- Show empty state initially
    if self.searchEmptyText then
        self.searchEmptyText:setVisible(true)
        self.searchEmptyText:setText(string.format(g_i18n:getText("usedplus_srp_noSearches"), maxSearches))
    end

    -- Store ordered list for button handlers
    self.activeSearchList = {}

    if g_usedVehicleManager then
        local displayItems = {}

        -- Collect active searches
        local searches = g_usedVehicleManager:getSearchesForFarm(farmId) or {}
        for _, search in ipairs(searches) do
            if search.status == "active" then
                table.insert(displayItems, {
                    type = "search",
                    data = search,
                    sortTime = search.startTime or 0,
                    isReady = false
                })
            end
        end

        -- Collect available listings (completed search results)
        local listings = g_usedVehicleManager:getListingsForFarm(farmId) or {}
        for _, listing in ipairs(listings) do
            table.insert(displayItems, {
                type = "listing",
                data = listing,
                sortTime = listing.createdTime or (g_currentMission and g_currentMission.time or 0),
                isReady = true
            })
        end

        -- Sort by time descending (newest first)
        table.sort(displayItems, function(a, b)
            return (a.sortTime or 0) > (b.sortTime or 0)
        end)

        local rowIndex = 0
        for _, item in ipairs(displayItems) do
            if rowIndex >= FinanceManagerFrame.MAX_SEARCH_ROWS then
                break
            end

            -- Store for button handlers
            self.activeSearchList[rowIndex] = item

            local isReady = item.isReady
            local itemName, searchLevel, ttl, basePrice
            local search = nil

            if item.type == "search" then
                search = item.data
                itemName = search.storeItemName or g_i18n:getText("usedplus_common_unknown")
                searchLevel = search.searchLevel or 1
                ttl = search.ttl or 0
                basePrice = search.basePrice or 0
                totalCost = totalCost + (search.searchCost or 0)
            else
                local listing = item.data
                itemName = listing.storeItemName or g_i18n:getText("usedplus_common_unknown")
                searchLevel = listing.searchLevel or 1
                ttl = 0
                basePrice = listing.price or 0
            end

            -- Truncate item name if too long
            if #itemName > 18 then
                itemName = string.sub(itemName, 1, 16) .. ".."
            end

            searchCount = searchCount + 1

            -- Tier info
            local tierNames = {"Local", "Regional", "National"}
            local successRates = {40, 70, 85}
            local tierName = tierNames[searchLevel] or "Local"

            -- Time display
            local timeStr
            if isReady then
                timeStr = "Ready!"
            else
                local monthsLeft = math.ceil(ttl / 24)
                local hoursLeft = ttl % 24
                if monthsLeft > 0 then
                    timeStr = string.format("%dmo", monthsLeft)
                elseif hoursLeft > 0 then
                    timeStr = string.format("%dhr", hoursLeft)
                else
                    timeStr = "Soon"
                end
            end

            -- Format values
            local priceStr = g_i18n:formatMoney(basePrice, 0, true, true)

            -- Get quality name
            local qualityStr = "Any"
            if not isReady and search then
                if search.getQualityName then
                    local fullName = search:getQualityName() or "Any Condition"
                    qualityStr = string.gsub(fullName, " Condition", "")
                elseif search.qualityLevel then
                    local qualityNames = {"Any", "Poor", "Fair", "Good", "Excellent"}
                    qualityStr = qualityNames[search.qualityLevel] or "Any"
                end
            elseif isReady and item.data then
                local fullName = item.data.qualityName or "Any Condition"
                qualityStr = string.gsub(fullName, " Condition", "")
            end

            -- Update row elements
            local row = self.searchRows[rowIndex]
            if row then
                if row.row then row.row:setVisible(true) end
                if row.item then row.item:setText(itemName) end
                if row.price then row.price:setText(priceStr) end
                if row.tier then row.tier:setText(tierName) end
                if row.chance then row.chance:setText(qualityStr) end
                if row.time then
                    row.time:setText(timeStr)
                    if isReady then
                        row.time:setTextColor(0.4, 1, 0.5, 1)
                    else
                        row.time:setTextColor(0.7, 0.7, 0.7, 1)
                    end
                end

                -- Row background
                if row.bg then
                    if isReady then
                        row.bg:setImageColor(nil, 0.1, 0.15, 0.1, 1)
                    else
                        local bgColor = (rowIndex % 2 == 0) and 0.1 or 0.12
                        row.bg:setImageColor(nil, bgColor, bgColor, bgColor, 1)
                    end
                end

                -- Info button
                if row.infoBtn then row.infoBtn:setVisible(true) end
                if row.infoBtnBg then
                    row.infoBtnBg:setVisible(true)
                    if isReady then
                        row.infoBtnBg:setImageColor(nil, 0.15, 0.25, 0.15, 1)
                    else
                        row.infoBtnBg:setImageColor(nil, 0.18, 0.18, 0.18, 1)
                    end
                end
                if row.infoBtnText then
                    row.infoBtnText:setVisible(true)
                    if isReady then
                        row.infoBtnText:setText("!")
                        row.infoBtnText:setTextColor(0.4, 1, 0.5, 1)
                    else
                        row.infoBtnText:setText("?")
                        row.infoBtnText:setTextColor(1, 1, 1, 1)
                    end
                end

                -- Cancel button - only for active searches
                local showCancel = not isReady
                if row.cancelBtn then row.cancelBtn:setVisible(showCancel) end
                if row.cancelBtnBg then row.cancelBtnBg:setVisible(showCancel) end
                if row.cancelBtnText then row.cancelBtnText:setVisible(showCancel) end
            end

            rowIndex = rowIndex + 1
        end

        -- Hide empty text if we have items
        if rowIndex > 0 and self.searchEmptyText then
            self.searchEmptyText:setVisible(false)
        end
    end

    -- Update summary bar
    if self.searchesCountText then
        self.searchesCountText:setText(string.format("%d/%d", searchCount, maxSearches))
    end
    if self.searchesTotalCostText then
        self.searchesTotalCostText:setText(g_i18n:formatMoney(totalCost, 0, true, true))
    end

    if self.searchesSuccessCountText then
        self.searchesSuccessCountText:setText("0")
    end
    if self.searchesFailedCountText then
        self.searchesFailedCountText:setText("0")
    end
end

--[[
    Cancel Search button handlers (per-row)
]]
function FinanceManagerFrame:onCancelSearch0() self:onCancelSearchClick(0) end
function FinanceManagerFrame:onCancelSearch1() self:onCancelSearchClick(1) end
function FinanceManagerFrame:onCancelSearch2() self:onCancelSearchClick(2) end
function FinanceManagerFrame:onCancelSearch3() self:onCancelSearchClick(3) end
function FinanceManagerFrame:onCancelSearch4() self:onCancelSearchClick(4) end

--[[
    Info Search button handlers (per-row)
]]
function FinanceManagerFrame:onInfoSearch0() self:onInfoSearchClick(0) end
function FinanceManagerFrame:onInfoSearch1() self:onInfoSearchClick(1) end
function FinanceManagerFrame:onInfoSearch2() self:onInfoSearchClick(2) end
function FinanceManagerFrame:onInfoSearch3() self:onInfoSearchClick(3) end
function FinanceManagerFrame:onInfoSearch4() self:onInfoSearchClick(4) end

-- Search row click handlers
function FinanceManagerFrame:onSearchRowClick0() self:onInfoSearchClick(0) end
function FinanceManagerFrame:onSearchRowClick1() self:onInfoSearchClick(1) end
function FinanceManagerFrame:onSearchRowClick2() self:onInfoSearchClick(2) end
function FinanceManagerFrame:onSearchRowClick3() self:onInfoSearchClick(3) end
function FinanceManagerFrame:onSearchRowClick4() self:onInfoSearchClick(4) end

-- Search row hover handlers
function FinanceManagerFrame:onSearchRowHighlight(element)
    for i = 0, FinanceManagerFrame.MAX_SEARCH_ROWS - 1 do
        local rowData = self.searchRows[i]
        if rowData and rowData.hit == element and rowData.bg then
            local baseColor = (i % 2 == 0) and 0.1 or 0.12
            rowData.bg:setImageColor(nil, baseColor + 0.08, baseColor + 0.08, baseColor + 0.10, 1)
            break
        end
    end
end

function FinanceManagerFrame:onSearchRowUnhighlight(element)
    for i = 0, FinanceManagerFrame.MAX_SEARCH_ROWS - 1 do
        local rowData = self.searchRows[i]
        if rowData and rowData.hit == element and rowData.bg then
            local baseColor = (i % 2 == 0) and 0.1 or 0.12
            rowData.bg:setImageColor(nil, baseColor, baseColor, baseColor, 1)
            break
        end
    end
end

--[[
    Handle Info button click for a specific search row
]]
function FinanceManagerFrame:onInfoSearchClick(rowIndex)
    local item = self.activeSearchList and self.activeSearchList[rowIndex]
    if not item then
        UsedPlus.logDebug(string.format("onInfoSearchClick: No item at row %d", rowIndex))
        return
    end

    local farmId = g_currentMission:getFarmId()

    if item.type == "listing" then
        -- Ready listing - show the purchase preview dialog
        local listing = item.data
        UsedPlus.logDebug(string.format("onInfoSearchClick: Showing purchase dialog for listing %s",
            listing.storeItemName or "Unknown"))

        if g_usedVehicleManager and g_usedVehicleManager.showSearchResultDialog then
            g_usedVehicleManager:showSearchResultDialog(listing, farmId)
        end
    else
        -- Active search - show search details dialog
        local search = item.data
        UsedPlus.logDebug(string.format("onInfoSearchClick: Showing details for search %s",
            search.storeItemName or "Unknown"))

        -- Use DialogLoader for consistent dialog management
        if DialogLoader and DialogLoader.show then
            DialogLoader.show("SearchDetailsDialog", "show", search)
        elseif SearchDetailsDialog then
            -- Fallback to old pattern if DialogLoader not available
            local dialog = SearchDetailsDialog.getInstance()
            dialog:show(search)
        end
    end
end

--[[
    Handle Cancel button click for a specific search row
]]
function FinanceManagerFrame:onCancelSearchClick(rowIndex)
    local item = self.activeSearchList and self.activeSearchList[rowIndex]
    if not item then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_noSearchInRow")
        )
        return
    end

    -- Only cancel active searches, not ready listings
    if item.type ~= "search" then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_cannotCancelReady")
        )
        return
    end

    local search = item.data
    if not search then
        return
    end

    if search.status ~= "active" then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            g_i18n:getText("usedplus_error_searchNotActive")
        )
        return
    end

    -- Show confirmation dialog
    local itemName = search.storeItemName or g_i18n:getText("usedplus_common_unknown")
    local searchFee = search.searchCost or 0
    local message = string.format(
        "Cancel search for %s?\n\n" ..
        "WARNING: The agent fee of %s will NOT be refunded.\n\n" ..
        "The search will be terminated immediately.",
        itemName,
        g_i18n:formatMoney(searchFee, 0, true, true)
    )

    YesNoDialog.show(
        function(yes)
            if yes then
                if CancelSearchEvent then
                    CancelSearchEvent.sendToServer(search.id)
                else
                    g_currentMission:addIngameNotification(
                        FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                        g_i18n:getText("usedplus_error_cancelSearchUnavailable")
                    )
                end
                self:updateDisplay()
            end
        end,
        nil,
        message,
        "Cancel Search"
    )
end

UsedPlus.logDebug("SearchesPanel module loaded")
