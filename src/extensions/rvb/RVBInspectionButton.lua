--[[
    RVBInspectionButton.lua
    Enhanced inspection & service confirmation dialogs for RVB Workshop

    Replaces RVB's basic "Are you sure?" YesNoDialog with enriched versions
    that show cost, estimated completion time, and total duration.

    Resolves: MathiasHun/FS25_Real_Vehicle_Breakdowns_Beta#152
]]

-- Ensure RVBWorkshopIntegration table exists (modules load before coordinator)
RVBWorkshopIntegration = RVBWorkshopIntegration or {}

--[[
    Hook RVB's Inspection button to show enhanced confirmation dialog.
    Hooks the dialog METHOD onClickInspection (called by XML onClick).
]]
function RVBWorkshopIntegration:hookInspectionButton(dialog)
    if dialog == nil then return end
    if dialog.usedPlusInspectionHooked then return end

    -- Find original onClickInspection (same metatable walk as RVBRepairButton)
    local origOnClickInspection = dialog.onClickInspection
    if origOnClickInspection == nil then
        local mt = getmetatable(dialog)
        while mt do
            local idx = mt.__index
            if type(idx) == "table" and idx.onClickInspection then
                origOnClickInspection = idx.onClickInspection
                break
            elseif type(idx) == "function" then
                break
            end
            mt = getmetatable(idx)
        end
    end

    if origOnClickInspection == nil then
        UsedPlus.logDebug("RVBInspectionButton: Could not find onClickInspection to hook")
        return
    end

    dialog.usedPlusOriginalOnClickInspection = origOnClickInspection

    -- Set method hook (may not fire due to raiseCallback caching — see RVBRepairButton)
    dialog.onClickInspection = function(self, ...)
        RVBWorkshopIntegration:onEnhancedInspectionClick(self)
    end

    -- CRITICAL: Also hook the button element's onClickCallback directly.
    -- FS25's raiseCallback("onClickCallback") caches at button creation time,
    -- so the method hook above won't fire. Same pattern as RVBRepairButton.
    if dialog.inspectionButton then
        dialog.inspectionButton.onClickCallback = function(target, element, ...)
            RVBWorkshopIntegration:onEnhancedInspectionClick(dialog)
        end
        UsedPlus.logInfo("RVBWorkshopIntegration: Replaced inspectionButton.onClickCallback")
    else
        UsedPlus.logWarn("RVBInspectionButton: inspectionButton element not found on dialog")
    end

    -- Also hook onClickService for enhanced service dialog
    local origOnClickService = dialog.onClickService
    if origOnClickService == nil then
        local mt = getmetatable(dialog)
        while mt do
            local idx = mt.__index
            if type(idx) == "table" and idx.onClickService then
                origOnClickService = idx.onClickService
                break
            elseif type(idx) == "function" then
                break
            end
            mt = getmetatable(idx)
        end
    end

    if origOnClickService then
        dialog.usedPlusOriginalOnClickService = origOnClickService

        dialog.onClickService = function(self, ...)
            RVBWorkshopIntegration:onEnhancedServiceClick(self)
        end

        if dialog.serviceButton then
            dialog.serviceButton.onClickCallback = function(target, element, ...)
                RVBWorkshopIntegration:onEnhancedServiceClick(dialog)
            end
            UsedPlus.logInfo("RVBWorkshopIntegration: Replaced serviceButton.onClickCallback")
        else
            UsedPlus.logWarn("RVBInspectionButton: serviceButton element not found on dialog")
        end

        UsedPlus.logInfo("RVBWorkshopIntegration: Hooked onClickService for enhanced dialog")
    end

    dialog.usedPlusInspectionHooked = true
    UsedPlus.logInfo("RVBWorkshopIntegration: Hooked onClickInspection for enhanced dialog")
end

--[[
    Format duration from total seconds into localized string
]]
function RVBWorkshopIntegration:formatDuration(totalSeconds)
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)

    if hours > 0 and minutes > 0 then
        return string.format(g_i18n:getText("usedplus_rvb_durationHM") or "%d hr, %d min", hours, minutes)
    elseif hours > 0 then
        return string.format(g_i18n:getText("usedplus_rvb_durationH") or "%d hr", hours)
    else
        return string.format(g_i18n:getText("usedplus_rvb_durationM") or "%d min", minutes)
    end
end

--[[
    Calculate finish time — delegates to RVB's vehicle method with fallback
]]
function RVBWorkshopIntegration:calculateFinishTime(vehicle, addHour, addMinute)
    if vehicle and vehicle.CalculateFinishTime then
        return vehicle:CalculateFinishTime(addHour, addMinute)
    end

    -- Fallback: simple time addition (no workshop hours logic)
    local env = g_currentMission.environment
    local totalMinutes = env.currentHour * 60 + env.currentMinute + addHour * 60 + addMinute
    local finishDay = env.currentDay + math.floor(totalMinutes / 1440)
    totalMinutes = totalMinutes % 1440
    return finishDay, math.floor(totalMinutes / 60), totalMinutes % 60
end

--[[
    Enhanced Inspection button click handler.
    Replicates RVB's onClickInspection logic but shows richer confirmation text.
]]
function RVBWorkshopIntegration:onEnhancedInspectionClick(dialog)
    local vehicle = dialog.vehicle
    if not (vehicle and vehicle.spec_faultData) then return end

    -- Workshop capacity guard (same as RVB)
    local RVB = g_currentMission.vehicleBreakdowns
    if RVB == nil then
        if dialog.usedPlusOriginalOnClickInspection then
            dialog.usedPlusOriginalOnClickInspection(dialog)
        end
        return
    end

    local GPSET = RVB.gameplaySettings
    if GPSET and RVB.workshopCount >= (GPSET.workshopCountMax or 1) then
        if InfoDialog then
            InfoDialog.show(string.format(
                g_i18n:getText("RVB_repairErrorMechanics") or "Workshop full (%d max)",
                GPSET.workshopCountMax))
        end
        return
    end

    -- Calculate inspection time (replicate RVB's logic from rvbConfig + dialog)
    -- INSPECTION is RVB's global config table
    local inspectionTime = (INSPECTION and INSPECTION.TIME) or 3600

    -- Own workshop adds random 10-30 min (same as RVB's onClickInspection)
    if g_rvbMain and g_rvbMain.isAlwaysOpenWorkshop and g_rvbMain:isAlwaysOpenWorkshop() then
        inspectionTime = inspectionTime + math.random(10 * 60, 30 * 60)
    end

    -- Mutate RVB's global so server-side WorkshopInspection.start() uses same value
    if INSPECTION then
        INSPECTION.TIME = inspectionTime
    end

    -- Calculate finish time
    local addHour = math.floor(inspectionTime / 3600)
    local addMinute = math.floor(((inspectionTime / 3600) - addHour) * 60)
    local finishDay, finishHour, finishMinute = self:calculateFinishTime(vehicle, addHour, addMinute)

    -- Get cost and format all values
    local env = g_currentMission.environment
    local cost = vehicle.getInspectionPrice and vehicle:getInspectionPrice() or 0
    local costText = g_i18n:formatMoney(cost, 0, true, true)
    local currentTimeText = string.format("%02d:%02d", env.currentHour, env.currentMinute)
    local finishTimeText = string.format("%02d:%02d", finishHour, finishMinute)
    local durationText = self:formatDuration(inspectionTime)

    -- Build enhanced confirmation text with all 4 details
    local lines = {}
    table.insert(lines, string.format(
        g_i18n:getText("usedplus_rvb_inspectQuestion") or "Inspect this vehicle for %s?", costText))
    table.insert(lines, "")
    table.insert(lines, string.format(
        g_i18n:getText("usedplus_rvb_currentTime") or "Current time: %s", currentTimeText))

    if finishDay > env.currentDay then
        table.insert(lines, string.format(
            g_i18n:getText("usedplus_rvb_completesTomorrow") or "Completed tomorrow at %s", finishTimeText))
    else
        table.insert(lines, string.format(
            g_i18n:getText("usedplus_rvb_completesAt") or "Estimated completion: %s", finishTimeText))
    end

    table.insert(lines, string.format(
        g_i18n:getText("usedplus_rvb_totalDuration") or "Total duration: %s", durationText))

    local text = table.concat(lines, "\n")

    -- Wrap RVB's original callback to add confirmation notification
    local origCallback = dialog.onYesNoInspectionDialog
    if origCallback == nil then
        UsedPlus.logWarn("RVBInspectionButton: onYesNoInspectionDialog is NIL — inspection will not work")
    end
    local wrappedCallback = function(target, yes)
        UsedPlus.logInfo(string.format("RVBInspectionButton: Callback fired — yes=%s, origCallback=%s",
            tostring(yes), tostring(origCallback ~= nil)))
        if origCallback then
            local ok, err = pcall(origCallback, target, yes)
            if not ok then
                UsedPlus.logWarn("RVBInspectionButton: origCallback CRASHED: " .. tostring(err))
            end
        end
        if yes and g_currentMission and g_currentMission.hud then
            local msg = string.format(
                g_i18n:getText("usedplus_rvb_inspectionStarted") or "Inspection started — %s charged on completion",
                costText)
            g_currentMission.hud:addSideNotification(
                FSBaseMission.INGAME_NOTIFICATION_OK, msg, 5000)
        end
    end

    local yesSound = GuiSoundPlayer and GuiSoundPlayer.SOUND_SAMPLES
        and GuiSoundPlayer.SOUND_SAMPLES.CONFIG_SPRAY
    YesNoDialog.show(wrappedCallback, dialog, text, nil, nil, nil, nil, yesSound)

    UsedPlus.logDebug(string.format(
        "RVBInspectionButton: Enhanced inspection dialog — cost=%s, finish=%s, duration=%s",
        costText, finishTimeText, durationText))
end

--[[
    Enhanced Service button click handler.
    Replicates RVB's onClickService logic but shows richer confirmation text.
]]
function RVBWorkshopIntegration:onEnhancedServiceClick(dialog)
    local vehicle = dialog.vehicle
    if not (vehicle and vehicle.spec_faultData) then return end

    local RVB = g_currentMission.vehicleBreakdowns
    if RVB == nil then
        if dialog.usedPlusOriginalOnClickService then
            dialog.usedPlusOriginalOnClickService(dialog)
        end
        return
    end

    local GPSET = RVB.gameplaySettings
    if GPSET and RVB.workshopCount >= (GPSET.workshopCountMax or 1) then
        if InfoDialog then
            InfoDialog.show(string.format(
                g_i18n:getText("RVB_repairErrorMechanics") or "Workshop full (%d max)",
                GPSET.workshopCountMax))
        end
        return
    end

    local specRVB = vehicle.spec_faultData

    -- Calculate service time (replicate RVB's logic)
    -- SERVICE is RVB's global config table
    local baseTime = (SERVICE and SERVICE.BASE_TIME) or 10800
    local perHourTime = (SERVICE and SERVICE.TIME) or 600

    -- Own workshop adds random 20-40 min (same as RVB's onClickService)
    if g_rvbMain and g_rvbMain.isAlwaysOpenWorkshop and g_rvbMain:isAlwaysOpenWorkshop() then
        baseTime = baseTime + math.random(20 * 60, 40 * 60)
    end

    -- Mutate RVB's global so server-side WorkshopService.start() uses same value
    if SERVICE then
        SERVICE.BASE_TIME = baseTime
    end

    -- Calculate overdue hours
    local periodicService = 50  -- Default fallback
    if RVB.getPeriodicService then
        periodicService = RVB:getPeriodicService()
    end
    local hoursOverdue = math.max(0, math.floor(specRVB.operatingHours or 0) - periodicService)
    local additionalTime = hoursOverdue * perHourTime
    local totalServiceTime = baseTime + additionalTime

    -- Calculate finish time
    local addHour = math.floor(totalServiceTime / 3600)
    local addMinute = math.floor(((totalServiceTime / 3600) - addHour) * 60)
    local finishDay, finishHour, finishMinute = self:calculateFinishTime(vehicle, addHour, addMinute)

    -- Get cost and format all values
    local env = g_currentMission.environment
    local cost = vehicle.getServicePrice and vehicle:getServicePrice() or 0
    local costText = g_i18n:formatMoney(cost, 0, true, true)
    local currentTimeText = string.format("%02d:%02d", env.currentHour, env.currentMinute)
    local finishTimeText = string.format("%02d:%02d", finishHour, finishMinute)
    local durationText = self:formatDuration(totalServiceTime)

    -- Build enhanced confirmation text with all 4 details
    local lines = {}
    table.insert(lines, string.format(
        g_i18n:getText("usedplus_rvb_serviceQuestion") or "Service this vehicle for %s?", costText))
    table.insert(lines, "")
    table.insert(lines, string.format(
        g_i18n:getText("usedplus_rvb_currentTime") or "Current time: %s", currentTimeText))

    if finishDay > env.currentDay then
        table.insert(lines, string.format(
            g_i18n:getText("usedplus_rvb_completesTomorrow") or "Completed tomorrow at %s", finishTimeText))
    else
        table.insert(lines, string.format(
            g_i18n:getText("usedplus_rvb_completesAt") or "Estimated completion: %s", finishTimeText))
    end

    table.insert(lines, string.format(
        g_i18n:getText("usedplus_rvb_totalDuration") or "Total duration: %s", durationText))

    -- Add overdue info if relevant
    if hoursOverdue > 0 then
        table.insert(lines, string.format(
            g_i18n:getText("usedplus_rvb_serviceOverdue") or "(%d hours overdue — extended service)",
            hoursOverdue))
    end

    local text = table.concat(lines, "\n")

    -- Wrap RVB's original callback to add confirmation notification
    local origCallback = dialog.onYesNoServiceDialog
    if origCallback == nil then
        UsedPlus.logWarn("RVBInspectionButton: onYesNoServiceDialog is NIL — service will not work")
    end
    local wrappedCallback = function(target, yes)
        UsedPlus.logInfo(string.format("RVBInspectionButton: Service callback fired — yes=%s, origCallback=%s",
            tostring(yes), tostring(origCallback ~= nil)))
        if origCallback then
            local ok, err = pcall(origCallback, target, yes)
            if not ok then
                UsedPlus.logWarn("RVBInspectionButton: origServiceCallback CRASHED: " .. tostring(err))
            end
        end
        if yes and g_currentMission and g_currentMission.hud then
            local msg = string.format(
                g_i18n:getText("usedplus_rvb_serviceStarted") or "Service started — %s charged on completion",
                costText)
            g_currentMission.hud:addSideNotification(
                FSBaseMission.INGAME_NOTIFICATION_OK, msg, 5000)
        end
    end

    local yesSound = GuiSoundPlayer and GuiSoundPlayer.SOUND_SAMPLES
        and GuiSoundPlayer.SOUND_SAMPLES.CONFIG_SPRAY
    YesNoDialog.show(wrappedCallback, dialog, text, nil, nil, nil, nil, yesSound)

    UsedPlus.logDebug(string.format(
        "RVBInspectionButton: Enhanced service dialog — cost=%s, finish=%s, duration=%s, overdue=%d",
        costText, finishTimeText, durationText, hoursOverdue))
end
