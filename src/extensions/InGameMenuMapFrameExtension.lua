--[[
    FS25_UsedPlus - InGameMenuMapFrame Extension

    Adds "Finance Land" option to farmland context menu
    Pattern from: FS25_FieldLeasing mod (working reference)

    This adds a "Finance Land" option alongside "Visit", "Buy", "Tag Place"
    when clicking on unowned farmland in the map.

    Key hooks:
    - onLoadMapFinished: Register new action in InGameMenuMapFrame.ACTIONS
    - setMapInputContext: Control when action is visible (when Buy is available)
]]

InGameMenuMapFrameExtension = {}
InGameMenuMapFrameExtension.actionsShifted = false

-- Dialog loading now handled by DialogLoader utility

--[[
    Hook onLoadMapFinished to register new actions
    Register REPAIR_VEHICLE, FINANCE_LAND, and LEASE_LAND actions
    Also intercept BUY to open our unified dialog
]]
function InGameMenuMapFrameExtension.onLoadMapFinished(self, superFunc)
    -- Call original function FIRST so base game contextActions are set up
    superFunc(self)

    -- Count existing actions to get next ID for vehicle-related actions
    local count = 0
    for _ in pairs(InGameMenuMapFrame.ACTIONS) do
        count = count + 1
    end

    -- Register REPAIR_VEHICLE action if not already added (at end, for vehicles)
    if InGameMenuMapFrame.ACTIONS.REPAIR_VEHICLE == nil then
        InGameMenuMapFrame.ACTIONS["REPAIR_VEHICLE"] = count + 1
        count = count + 1

        self.contextActions[InGameMenuMapFrame.ACTIONS.REPAIR_VEHICLE] = {
            ["title"] = g_i18n:getText("usedplus_button_repairVehicle"),
            ["callback"] = InGameMenuMapFrameExtension.onRepairVehicle,
            ["isActive"] = false
        }

        UsedPlus.logDebug("Registered REPAIR_VEHICLE action in InGameMenuMapFrame (ID=" .. tostring(InGameMenuMapFrame.ACTIONS.REPAIR_VEHICLE) .. ")")
    end

    -- Override the BUY action callback to open our dialog for farmland
    if InGameMenuMapFrame.ACTIONS.BUY and self.contextActions[InGameMenuMapFrame.ACTIONS.BUY] then
        -- Store original callback (only on first call to prevent infinite recursion)
        if InGameMenuMapFrameExtension.originalBuyCallback == nil then
            InGameMenuMapFrameExtension.originalBuyCallback = self.contextActions[InGameMenuMapFrame.ACTIONS.BUY].callback
        end
        -- Replace with our callback
        self.contextActions[InGameMenuMapFrame.ACTIONS.BUY].callback = InGameMenuMapFrameExtension.onBuyFarmland
        UsedPlus.logDebug("Intercepted BUY action callback (ID=" .. tostring(InGameMenuMapFrame.ACTIONS.BUY) .. ")")

        -- Insert FINANCE_LAND and LEASE_LAND right after BUY
        -- We need to shift all actions with ID > BUY up by 2 to make room
        local buyId = InGameMenuMapFrame.ACTIONS.BUY
        local financeId = buyId + 1
        local leaseId = buyId + 2

        -- Only shift actions once (re-entrancy guard to prevent double-shifting IDs)
        if not InGameMenuMapFrameExtension.actionsShifted then
            InGameMenuMapFrameExtension.actionsShifted = true

            -- Collect all actions that need to be shifted (ID > buyId)
            local actionsToShift = {}
            for actionName, actionId in pairs(InGameMenuMapFrame.ACTIONS) do
                if type(actionId) == "number" and actionId > buyId then
                    table.insert(actionsToShift, {name = actionName, oldId = actionId})
                end
            end

            -- Sort by ID descending so we shift highest first (avoid collisions)
            table.sort(actionsToShift, function(a, b) return a.oldId > b.oldId end)

            -- Shift each action's ID up by 2
            for _, action in ipairs(actionsToShift) do
                local newId = action.oldId + 2
                InGameMenuMapFrame.ACTIONS[action.name] = newId

                -- Also move the contextAction entry
                if self.contextActions[action.oldId] then
                    self.contextActions[newId] = self.contextActions[action.oldId]
                    self.contextActions[action.oldId] = nil
                end

                UsedPlus.logDebug("Shifted action " .. action.name .. " from ID " .. action.oldId .. " to " .. newId)
            end
        end

        -- Now register our actions in the gap we created
        if InGameMenuMapFrame.ACTIONS.FINANCE_LAND == nil then
            InGameMenuMapFrame.ACTIONS["FINANCE_LAND"] = financeId

            self.contextActions[financeId] = {
                ["title"] = g_i18n:getText("usedplus_action_financeLand") or "Finance",
                ["callback"] = InGameMenuMapFrameExtension.onFinanceLand,
                ["isActive"] = false
            }

            UsedPlus.logDebug("Registered FINANCE_LAND action (ID=" .. tostring(financeId) .. ")")
        end

        if InGameMenuMapFrame.ACTIONS.LEASE_LAND == nil then
            InGameMenuMapFrame.ACTIONS["LEASE_LAND"] = leaseId

            self.contextActions[leaseId] = {
                ["title"] = g_i18n:getText("usedplus_action_leaseLand") or "Lease",
                ["callback"] = InGameMenuMapFrameExtension.onLeaseLand,
                ["isActive"] = false
            }

            UsedPlus.logDebug("Registered LEASE_LAND action (ID=" .. tostring(leaseId) .. ")")
        end
    else
        UsedPlus.logWarn("Could not intercept BUY action")
    end
end

--[[
    Hook setMapInputContext to show Repair, Finance Land, and Lease Land options
    v1.4.0: Check settings system for feature toggles
    v2.15.5: Call superFunc FIRST so FM and other mods can modify BUY state,
             then observe the result to control Finance/Lease visibility.
             This avoids FS25 mod sandbox issues — we observe effects, not data.
]]
function InGameMenuMapFrameExtension.setMapInputContext(self, superFunc, enterVehicleActive, resetVehicleActive, sellVehicleActive, visitPlaceActive, setMarkerActive, removeMarkerActive, buyFarmlandActive, sellFarmlandActive, manageActive)

    -- Call original function chain FIRST so FM and other mods can modify buy state
    superFunc(self, enterVehicleActive, resetVehicleActive, sellVehicleActive, visitPlaceActive, setMarkerActive, removeMarkerActive, buyFarmlandActive, sellFarmlandActive, manageActive)

    -- v1.4.0: Check settings for each feature
    local repairEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Repair")
    local financeEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Finance")
    local leaseEnabled = not UsedPlusSettings or UsedPlusSettings:isSystemEnabled("Lease")

    -- Show "Repair Vehicle" when "Sell Vehicle" is available (owned vehicle selected) AND repair is enabled
    if sellVehicleActive and repairEnabled and self.contextActions[InGameMenuMapFrame.ACTIONS.REPAIR_VEHICLE] then
        self.contextActions[InGameMenuMapFrame.ACTIONS.REPAIR_VEHICLE].isActive = true
    elseif self.contextActions[InGameMenuMapFrame.ACTIONS.REPAIR_VEHICLE] then
        self.contextActions[InGameMenuMapFrame.ACTIONS.REPAIR_VEHICLE].isActive = false
    end

    -- v2.15.5: Check if buy is available after the full hook chain has run.
    -- FM sets BUY.isActive=false for blocked fields (not for sale, no negotiation).
    -- We show Finance/Lease whenever BUY is active — this covers both vanilla buy
    -- and FM's "Make Offer" mode (where the purchase goes through FM's server validation).
    local buyAction = self.contextActions[InGameMenuMapFrame.ACTIONS.BUY]
    local isBuyAvailable = buyAction and buyAction.isActive

    -- v2.15.4: Hide Finance/Lease for free ($0) farmlands — nothing to finance or lease
    local isFreeField = false
    if isBuyAvailable and self.selectedFarmland then
        isFreeField = (self.selectedFarmland.price == nil or self.selectedFarmland.price <= 0)
    end

    -- Show "Finance Land" when vanilla buy is available AND finance enabled AND not free
    if isBuyAvailable and financeEnabled and not isFreeField and self.contextActions[InGameMenuMapFrame.ACTIONS.FINANCE_LAND] then
        self.contextActions[InGameMenuMapFrame.ACTIONS.FINANCE_LAND].isActive = true
    elseif self.contextActions[InGameMenuMapFrame.ACTIONS.FINANCE_LAND] then
        self.contextActions[InGameMenuMapFrame.ACTIONS.FINANCE_LAND].isActive = false
    end

    -- Show "Lease Land" when vanilla buy is available AND lease enabled AND not free
    if isBuyAvailable and leaseEnabled and not isFreeField and self.contextActions[InGameMenuMapFrame.ACTIONS.LEASE_LAND] then
        self.contextActions[InGameMenuMapFrame.ACTIONS.LEASE_LAND].isActive = true
    elseif self.contextActions[InGameMenuMapFrame.ACTIONS.LEASE_LAND] then
        self.contextActions[InGameMenuMapFrame.ACTIONS.LEASE_LAND].isActive = false
    end
end

--[[
    Install hooks at load time with safety check
    InGameMenuMapFrame should exist when mods load
]]
if InGameMenuMapFrame ~= nil then
    -- Hook into onLoadMapFinished
    if InGameMenuMapFrame.onLoadMapFinished ~= nil then
        InGameMenuMapFrame.onLoadMapFinished = Utils.overwrittenFunction(
            InGameMenuMapFrame.onLoadMapFinished,
            InGameMenuMapFrameExtension.onLoadMapFinished
        )
        UsedPlus.logDebug("InGameMenuMapFrame.onLoadMapFinished hook installed")
    end

    -- Hook into setMapInputContext
    if InGameMenuMapFrame.setMapInputContext ~= nil then
        InGameMenuMapFrame.setMapInputContext = Utils.overwrittenFunction(
            InGameMenuMapFrame.setMapInputContext,
            InGameMenuMapFrameExtension.setMapInputContext
        )
        UsedPlus.logDebug("InGameMenuMapFrame.setMapInputContext hook installed")
    end
else
    UsedPlus.logDebug("InGameMenuMapFrame not available at load time")
end

--[[
    Callback when "Finance Land" is clicked
    Opens UnifiedLandPurchaseDialog in Finance mode
]]
function InGameMenuMapFrameExtension.onFinanceLand(inGameMenuMapFrame, element)
    UsedPlus.logDebug("onFinanceLand called")
    if inGameMenuMapFrame.selectedFarmland == nil then
        UsedPlus.logWarn("onFinanceLand: No farmland selected")
        return true
    end

    local selectedFarmland = inGameMenuMapFrame.selectedFarmland
    UsedPlus.logDebug("onFinanceLand: Farmland ID=" .. tostring(selectedFarmland.id) .. ", Price=" .. tostring(selectedFarmland.price))

    -- v2.15.4: Free farmlands ($0) — can't finance free land, use vanilla buy
    if selectedFarmland.price == nil or selectedFarmland.price <= 0 then
        UsedPlus.logDebug("onFinanceLand: Free farmland, using vanilla purchase")
        if InGameMenuMapFrameExtension.originalBuyCallback then
            return InGameMenuMapFrameExtension.originalBuyCallback(inGameMenuMapFrame, element)
        end
        return true
    end

    -- Check if there's a mission running on this farmland
    if g_missionManager:getIsMissionRunningOnFarmland(selectedFarmland) then
        InfoDialog.show(g_i18n:getText(InGameMenuMapFrame.L10N_SYMBOL.DIALOG_BUY_FARMLAND_ACTIVE_MISSION))
        return false
    end

    -- Load dialog if needed and set data
    if not DialogLoader.ensureLoaded("UnifiedLandPurchaseDialog") then
        UsedPlus.logError("onFinanceLand: Failed to load UnifiedLandPurchaseDialog")
        return true
    end

    local dialog = DialogLoader.getDialog("UnifiedLandPurchaseDialog")
    if dialog then
        dialog:setLandData(selectedFarmland.id, selectedFarmland, selectedFarmland.price)
        dialog:setInitialMode(UnifiedLandPurchaseDialog.MODE_FINANCE)
        g_gui:showDialog("UnifiedLandPurchaseDialog")

        -- Hide context boxes after opening dialog
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBox)
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBoxPlayer)
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBoxFarmland)
        UsedPlus.logDebug("onFinanceLand: Dialog shown")
    else
        UsedPlus.logError("onFinanceLand: Dialog not found")
    end

    return true
end

--[[
    Callback when "Lease Land" is clicked
    Opens UnifiedLandPurchaseDialog in Lease mode
]]
function InGameMenuMapFrameExtension.onLeaseLand(inGameMenuMapFrame, element)
    UsedPlus.logDebug("onLeaseLand called")
    if inGameMenuMapFrame.selectedFarmland == nil then
        UsedPlus.logWarn("onLeaseLand: No farmland selected")
        return true
    end

    local selectedFarmland = inGameMenuMapFrame.selectedFarmland
    UsedPlus.logDebug("onLeaseLand: Farmland ID=" .. tostring(selectedFarmland.id) .. ", Price=" .. tostring(selectedFarmland.price))

    -- v2.15.4: Free farmlands ($0) — can't lease free land, use vanilla buy
    if selectedFarmland.price == nil or selectedFarmland.price <= 0 then
        UsedPlus.logDebug("onLeaseLand: Free farmland, using vanilla purchase")
        if InGameMenuMapFrameExtension.originalBuyCallback then
            return InGameMenuMapFrameExtension.originalBuyCallback(inGameMenuMapFrame, element)
        end
        return true
    end

    -- Check if there's a mission running on this farmland
    if g_missionManager:getIsMissionRunningOnFarmland(selectedFarmland) then
        InfoDialog.show(g_i18n:getText(InGameMenuMapFrame.L10N_SYMBOL.DIALOG_BUY_FARMLAND_ACTIVE_MISSION))
        return false
    end

    -- Load dialog if needed and set data
    if not DialogLoader.ensureLoaded("UnifiedLandPurchaseDialog") then
        UsedPlus.logError("onLeaseLand: Failed to load UnifiedLandPurchaseDialog")
        return true
    end

    local dialog = DialogLoader.getDialog("UnifiedLandPurchaseDialog")
    if dialog then
        dialog:setLandData(selectedFarmland.id, selectedFarmland, selectedFarmland.price)
        dialog:setInitialMode(UnifiedLandPurchaseDialog.MODE_LEASE)
        g_gui:showDialog("UnifiedLandPurchaseDialog")

        -- Hide context boxes after opening dialog
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBox)
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBoxPlayer)
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBoxFarmland)
        UsedPlus.logDebug("onLeaseLand: Dialog shown")
    else
        UsedPlus.logError("onLeaseLand: Dialog not found")
    end

    return true
end

--[[
    Callback when "Repair Vehicle" is clicked
    Refactored to use DialogLoader for centralized loading
]]
function InGameMenuMapFrameExtension.onRepairVehicle(inGameMenuMapFrame, element)
    -- Get the selected vehicle from the current hotspot
    local vehicle = nil

    if inGameMenuMapFrame.currentHotspot ~= nil then
        -- Try to get vehicle from hotspot
        if InGameMenuMapUtil and InGameMenuMapUtil.getHotspotVehicle then
            vehicle = InGameMenuMapUtil.getHotspotVehicle(inGameMenuMapFrame.currentHotspot)
        end

        -- Fallback: try direct vehicle reference
        if vehicle == nil and inGameMenuMapFrame.currentHotspot.vehicle then
            vehicle = inGameMenuMapFrame.currentHotspot.vehicle
        end
    end

    if vehicle == nil then
        UsedPlus.logError("No vehicle selected for repair")
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_noVehicleSelected")
        )
        return true
    end

    local farmId = g_currentMission:getFarmId()

    -- Check if player owns the vehicle
    if vehicle.ownerFarmId ~= farmId then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_error_notYourVehicle")
        )
        return true
    end

    -- v2.15.4: Pass RVB's repair cost if RVB is installed
    local rvbRepairCost = nil
    if ModCompatibility and ModCompatibility.rvbInstalled and vehicle.getRepairPrice_RVBClone then
        rvbRepairCost = vehicle:getRepairPrice_RVBClone() or 0
    end

    -- Use DialogLoader for centralized lazy loading
    local shown = DialogLoader.show("RepairDialog", "setVehicle", vehicle, farmId, RepairDialog.MODE_REPAIR, rvbRepairCost)

    if shown then
        -- Hide context boxes after opening dialog
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBox)
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBoxPlayer)
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBoxFarmland)
    end

    return true
end

--[[
    Callback when "Buy" farmland is clicked
    Opens UnifiedLandPurchaseDialog in Cash mode (default)
]]
function InGameMenuMapFrameExtension.onBuyFarmland(inGameMenuMapFrame, element)
    UsedPlus.logDebug("onBuyFarmland called - intercepted Buy action")

    -- v2.7.0: Check if override is enabled - if not, use vanilla callback
    local overrideEnabled = not UsedPlusSettings or UsedPlusSettings:get("overrideShopBuyLease") ~= false
    if not overrideEnabled then
        UsedPlus.logDebug("onBuyFarmland: Override disabled, using vanilla callback")
        if InGameMenuMapFrameExtension.originalBuyCallback then
            return InGameMenuMapFrameExtension.originalBuyCallback(inGameMenuMapFrame, element)
        end
        return true
    end

    if inGameMenuMapFrame.selectedFarmland == nil then
        UsedPlus.logWarn("onBuyFarmland: No farmland selected")
        return true
    end

    local selectedFarmland = inGameMenuMapFrame.selectedFarmland
    UsedPlus.logDebug("onBuyFarmland: Farmland ID=" .. tostring(selectedFarmland.id) .. ", Price=" .. tostring(selectedFarmland.price))

    -- v2.15.4: Free farmlands ($0) — use vanilla purchase (nothing to finance)
    if selectedFarmland.price == nil or selectedFarmland.price <= 0 then
        UsedPlus.logDebug("onBuyFarmland: Free farmland, using vanilla purchase")
        if InGameMenuMapFrameExtension.originalBuyCallback then
            return InGameMenuMapFrameExtension.originalBuyCallback(inGameMenuMapFrame, element)
        end
        return true
    end

    -- Check if there's a mission running on this farmland
    if g_missionManager:getIsMissionRunningOnFarmland(selectedFarmland) then
        InfoDialog.show(g_i18n:getText(InGameMenuMapFrame.L10N_SYMBOL.DIALOG_BUY_FARMLAND_ACTIVE_MISSION))
        return false
    end

    -- Load dialog if needed and set data
    if not DialogLoader.ensureLoaded("UnifiedLandPurchaseDialog") then
        UsedPlus.logError("onBuyFarmland: Failed to load UnifiedLandPurchaseDialog")
        return true
    end

    local dialog = DialogLoader.getDialog("UnifiedLandPurchaseDialog")
    if dialog then
        dialog:setLandData(selectedFarmland.id, selectedFarmland, selectedFarmland.price)
        dialog:setInitialMode(UnifiedLandPurchaseDialog.MODE_CASH)  -- Default to cash mode
        g_gui:showDialog("UnifiedLandPurchaseDialog")

        -- Hide context boxes after opening dialog
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBox)
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBoxPlayer)
        InGameMenuMapUtil.hideContextBox(inGameMenuMapFrame.contextBoxFarmland)
        UsedPlus.logDebug("onBuyFarmland: Dialog shown")
    else
        UsedPlus.logError("onBuyFarmland: Dialog not found")
    end

    return true
end

--[[
    Reset state on mission delete to prevent stale data in new sessions
]]
function InGameMenuMapFrameExtension.onMissionDelete()
    InGameMenuMapFrameExtension.actionsShifted = false
    InGameMenuMapFrameExtension.originalBuyCallback = nil
    UsedPlus.logDebug("InGameMenuMapFrameExtension: Reset state for new mission")
end

UsedPlus.logInfo("InGameMenuMapFrameExtension loaded")
