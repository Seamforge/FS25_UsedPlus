--[[
    FS25_UsedPlus - Tires Service Dialog

    Allows player to replace tires with quality selection:
    - Retread (1): Cheap, reduced traction (85%), higher failure risk (3x)
    - Normal (2): Standard tires, baseline performance
    - Quality (3): Premium tires, better traction (110%), lower failure risk (0.5x)

    v2.3.0: UYT Deep Integration
    - Shows per-wheel wear when UYT installed (FL/FR/RL/RR)
    - Quality tiers affect UYT wear rate (retread 2x faster, quality 33% slower)
    - Tire replacement syncs to UYT (resets their wear tracking)

    Pattern from: RepairDialog, MessageDialog

    v1.7.0 - Tire and Fluid System
]]

TiresDialog = {}
local TiresDialog_mt = Class(TiresDialog, MessageDialog)

-- Quality tier constants
TiresDialog.QUALITY_RETREAD = 1
TiresDialog.QUALITY_NORMAL = 2
TiresDialog.QUALITY_QUALITY = 3

-- Singleton instance
TiresDialog.INSTANCE = nil

--[[
    Constructor
]]
function TiresDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or TiresDialog_mt)

    -- Vehicle data
    self.vehicle = nil
    self.vehicleName = ""
    self.storeItem = nil
    self.basePrice = 0
    self.farmId = 0

    -- Current tire state
    self.currentQuality = 2  -- 1=Retread, 2=Normal, 3=Quality
    self.currentCondition = 1.0  -- 0-1
    self.hasFlatTire = false

    -- v2.3.0: UYT per-wheel tracking
    self.hasUYT = false
    self.perWheelConditions = nil  -- { FL=0.85, FR=0.82, RL=0.90, RR=0.88 }
    self.worstWheel = nil          -- "FR"
    self.worstCondition = 1.0

    -- Selected quality
    self.selectedQuality = nil

    -- Calculated costs
    self.retreadCost = 0
    self.normalCost = 0
    self.qualityCost = 0

    return self
end

--[[
    Get singleton instance, creating if needed
]]
function TiresDialog.getInstance()
    if TiresDialog.INSTANCE == nil then
        TiresDialog.INSTANCE = TiresDialog.new()

        local xmlPath = UsedPlus.MOD_DIR .. "gui/TiresDialog.xml"
        g_gui:loadGui(xmlPath, "TiresDialog", TiresDialog.INSTANCE)

        UsedPlus.logDebug("TiresDialog created and loaded from: " .. xmlPath)
    end
    return TiresDialog.INSTANCE
end

--[[
    Called when GUI elements are ready
]]
function TiresDialog:onGuiSetupFinished()
    TiresDialog:superClass().onGuiSetupFinished(self)
    -- UI elements auto-populated from XML id attributes
end

--[[
    Set vehicle data for tire replacement
    @param vehicle - The vehicle object
    @param farmId - Farm ID that owns the vehicle
]]
function TiresDialog:setVehicle(vehicle, farmId)
    self.vehicle = vehicle
    self.farmId = farmId

    if vehicle == nil then
        UsedPlus.logError("TiresDialog:setVehicle - No vehicle provided")
        return
    end

    -- Get store item and vehicle name
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    self.storeItem = storeItem
    self.vehicleName = storeItem and storeItem.name or vehicle:getName() or g_i18n:getText("usedplus_common_unknownVehicle")
    -- Use empty config table to get base store price (not depreciated vehicle price)
    self.basePrice = storeItem and (StoreItemUtil.getDefaultPrice(storeItem, {}) or storeItem.price or 10000) or 10000

    -- Get current tire state from UsedPlusMaintenance
    local spec = vehicle.spec_usedPlusMaintenance
    if spec then
        self.currentQuality = spec.tireQuality or 2
        self.currentCondition = spec.tireCondition or 1.0
        self.hasFlatTire = spec.hasFlatTire or false
    else
        self.currentQuality = 2
        self.currentCondition = 1.0
        self.hasFlatTire = false
    end

    -- v2.3.0: Get UYT per-wheel data if available
    self.hasUYT = ModCompatibility and ModCompatibility.uytInstalled and ModCompatibility.hasUYTTires(vehicle)
    self.perWheelConditions = nil
    self.worstWheel = nil
    self.worstCondition = 1.0

    if self.hasUYT then
        local wheelLabels = { "FL", "FR", "RL", "RR" }
        self.perWheelConditions = {}
        local worstWear = 0

        for i = 1, 4 do
            local wear = ModCompatibility.getUYTTireWear(vehicle, i)
            local condition = 1.0 - wear
            self.perWheelConditions[wheelLabels[i]] = condition

            if wear > worstWear then
                worstWear = wear
                self.worstWheel = wheelLabels[i]
                self.worstCondition = condition
            end
        end

        UsedPlus.logDebug(string.format("TiresDialog: UYT data - FL=%.0f%% FR=%.0f%% RL=%.0f%% RR=%.0f%%, worst=%s",
            (self.perWheelConditions.FL or 1) * 100,
            (self.perWheelConditions.FR or 1) * 100,
            (self.perWheelConditions.RL or 1) * 100,
            (self.perWheelConditions.RR or 1) * 100,
            self.worstWheel or "none"))
    end

    -- Reset selection
    self.selectedQuality = nil

    -- Calculate tire replacement costs
    self:calculateCosts()

    UsedPlus.logDebug(string.format("TiresDialog:setVehicle %s - quality=%d, condition=%.0f%%, flat=%s, UYT=%s",
        self.vehicleName, self.currentQuality, self.currentCondition * 100, tostring(self.hasFlatTire), tostring(self.hasUYT)))
end

--[[
    Calculate tire costs based on vehicle base price
    Pattern: Tires cost ~5% of vehicle base price for normal, scaled by quality multiplier
]]
function TiresDialog:calculateCosts()
    local config = UsedPlusMaintenance.CONFIG
    local baseTireCost = self.basePrice * 0.05  -- 5% of vehicle price for baseline tires

    self.retreadCost = math.floor(baseTireCost * config.tireRetreadCostMult)
    self.normalCost = math.floor(baseTireCost * config.tireNormalCostMult)
    self.qualityCost = math.floor(baseTireCost * config.tireQualityCostMult)

    UsedPlus.logDebug(string.format("TiresDialog costs: Retread=$%d, Normal=$%d, Quality=$%d",
        self.retreadCost, self.normalCost, self.qualityCost))
end

--[[
    Called when dialog opens
]]
function TiresDialog:onOpen()
    TiresDialog:superClass().onOpen(self)
    self:updateDisplay()
end

--[[
    Update all display elements
]]
function TiresDialog:updateDisplay()
    -- Vehicle name
    if self.vehicleNameText then
        self.vehicleNameText:setText(self.vehicleName)
    end

    -- Vehicle image
    if self.vehicleImageElement and self.storeItem then
        local imagePath = self.storeItem.imageFilename
        if imagePath then
            self.vehicleImageElement:setImageFilename(imagePath)
        end
    end

    -- Current quality text
    if self.currentQualityText then
        local qualityName = self:getQualityName(self.currentQuality)
        self.currentQualityText:setText(qualityName)
    end

    -- Current condition
    -- v2.3.0: Show per-wheel conditions when UYT is installed
    if self.hasUYT and self.perWheelConditions then
        -- Show per-wheel display
        if self.currentConditionText then
            local fl = math.floor((self.perWheelConditions.FL or 1) * 100)
            local fr = math.floor((self.perWheelConditions.FR or 1) * 100)
            local rl = math.floor((self.perWheelConditions.RL or 1) * 100)
            local rr = math.floor((self.perWheelConditions.RR or 1) * 100)

            -- Format: "FL:85% FR:82% RL:90% RR:88%"
            self.currentConditionText:setText(string.format("FL:%d%% FR:%d%% RL:%d%% RR:%d%%", fl, fr, rl, rr))

            -- Color based on worst tire
            if self.worstCondition >= 0.7 then
                self.currentConditionText:setTextColor(0.3, 1, 0.4, 1)  -- Green
            elseif self.worstCondition >= 0.4 then
                self.currentConditionText:setTextColor(1, 0.85, 0.2, 1)  -- Yellow
            else
                self.currentConditionText:setTextColor(1, 0.4, 0.4, 1)  -- Red
            end
        end

        -- Show worst tire indicator in a separate element if available
        if self.worstTireText then
            if self.worstWheel then
                self.worstTireText:setText(string.format(g_i18n:getText("usedplus_tires_worstFormat"), self.worstWheel, self.worstCondition * 100))
                self.worstTireText:setVisible(true)
            else
                self.worstTireText:setVisible(false)
            end
        end

        -- Update condition label to indicate UYT source
        if self.conditionLabel then
            self.conditionLabel:setText(g_i18n:getText("usedplus_tires_conditionUYT") or "Tire Wear (UYT):")
        end
    else
        -- Standard single condition display
        if self.currentConditionText then
            local conditionPercent = math.floor(self.currentCondition * 100)
            self.currentConditionText:setText(string.format("%d%%", conditionPercent))

            -- Color based on condition
            if self.currentCondition >= 0.7 then
                self.currentConditionText:setTextColor(0.3, 1, 0.4, 1)  -- Green
            elseif self.currentCondition >= 0.4 then
                self.currentConditionText:setTextColor(1, 0.85, 0.2, 1)  -- Yellow
            else
                self.currentConditionText:setTextColor(1, 0.4, 0.4, 1)  -- Red
            end
        end

        -- Hide worst tire indicator when UYT not available
        if self.worstTireText then
            self.worstTireText:setVisible(false)
        end
    end

    -- Flat tire warning
    if self.flatTireWarningText then
        if self.hasFlatTire then
            self.flatTireWarningText:setText(g_i18n:getText("usedplus_tires_flatWarning") or "FLAT TIRE - Replacement Required!")
            self.flatTireWarningText:setVisible(true)
        else
            self.flatTireWarningText:setVisible(false)
        end
    end

    -- Button costs
    if self.btnRetreadCost then
        self.btnRetreadCost:setText(g_i18n:formatMoney(self.retreadCost, 0, true, true))
    end
    if self.btnNormalCost then
        self.btnNormalCost:setText(g_i18n:formatMoney(self.normalCost, 0, true, true))
    end
    if self.btnQualityCost then
        self.btnQualityCost:setText(g_i18n:formatMoney(self.qualityCost, 0, true, true))
    end

    -- Update payment summary
    self:updatePaymentSummary()
end

--[[
    Update payment summary section based on selection
]]
function TiresDialog:updatePaymentSummary()
    if self.selectedQuality then
        local qualityName = self:getQualityName(self.selectedQuality)
        local cost = self:getCostForQuality(self.selectedQuality)

        if self.selectedTireText then
            self.selectedTireText:setText(qualityName)
        end
        if self.totalCostText then
            self.totalCostText:setText(g_i18n:formatMoney(cost, 0, true, true))
        end
    else
        if self.selectedTireText then
            self.selectedTireText:setText(g_i18n:getText("usedplus_tires_selectAbove") or "Select above")
        end
        if self.totalCostText then
            self.totalCostText:setText(g_i18n:formatMoney(0, 0, true, true))
        end
    end
end

--[[
    Get quality name for display
]]
function TiresDialog:getQualityName(quality)
    if quality == TiresDialog.QUALITY_RETREAD then
        return g_i18n:getText("usedplus_tires_retread") or "Retread"
    elseif quality == TiresDialog.QUALITY_NORMAL then
        return g_i18n:getText("usedplus_tires_normal") or "Normal"
    elseif quality == TiresDialog.QUALITY_QUALITY then
        return g_i18n:getText("usedplus_tires_quality") or "Quality"
    end
    return "Unknown"
end

--[[
    Get cost for a quality tier
]]
function TiresDialog:getCostForQuality(quality)
    if quality == TiresDialog.QUALITY_RETREAD then
        return self.retreadCost
    elseif quality == TiresDialog.QUALITY_NORMAL then
        return self.normalCost
    elseif quality == TiresDialog.QUALITY_QUALITY then
        return self.qualityCost
    end
    return 0
end

--[[
    Highlight the selected button
]]
function TiresDialog:highlightButton(quality)
    -- Reset all button backgrounds
    local defaultColors = {
        [TiresDialog.QUALITY_RETREAD] = {0.2, 0.15, 0.1, 1},   -- Orange tint
        [TiresDialog.QUALITY_NORMAL] = {0.1, 0.15, 0.2, 1},    -- Blue tint
        [TiresDialog.QUALITY_QUALITY] = {0.1, 0.2, 0.15, 1}    -- Green tint
    }

    local selectedColor = {0.3, 0.5, 0.3, 1}  -- Bright green for selection

    -- Update backgrounds
    if self.btnRetreadBg then
        if quality == TiresDialog.QUALITY_RETREAD then
            self.btnRetreadBg:setImageColor(nil, unpack(selectedColor))
        else
            self.btnRetreadBg:setImageColor(nil, unpack(defaultColors[TiresDialog.QUALITY_RETREAD]))
        end
    end

    if self.btnNormalBg then
        if quality == TiresDialog.QUALITY_NORMAL then
            self.btnNormalBg:setImageColor(nil, unpack(selectedColor))
        else
            self.btnNormalBg:setImageColor(nil, unpack(defaultColors[TiresDialog.QUALITY_NORMAL]))
        end
    end

    if self.btnQualityBg then
        if quality == TiresDialog.QUALITY_QUALITY then
            self.btnQualityBg:setImageColor(nil, unpack(selectedColor))
        else
            self.btnQualityBg:setImageColor(nil, unpack(defaultColors[TiresDialog.QUALITY_QUALITY]))
        end
    end
end

--[[
    Button callbacks
]]
function TiresDialog:onClickRetread()
    self.selectedQuality = TiresDialog.QUALITY_RETREAD
    self:highlightButton(TiresDialog.QUALITY_RETREAD)
    self:updatePaymentSummary()
    UsedPlus.logDebug("TiresDialog: Selected Retread")
end

function TiresDialog:onClickNormal()
    self.selectedQuality = TiresDialog.QUALITY_NORMAL
    self:highlightButton(TiresDialog.QUALITY_NORMAL)
    self:updatePaymentSummary()
    UsedPlus.logDebug("TiresDialog: Selected Normal")
end

function TiresDialog:onClickQuality()
    self.selectedQuality = TiresDialog.QUALITY_QUALITY
    self:highlightButton(TiresDialog.QUALITY_QUALITY)
    self:updatePaymentSummary()
    UsedPlus.logDebug("TiresDialog: Selected Quality")
end

--[[
    Confirm button - process tire replacement
]]
function TiresDialog:onConfirm()
    if self.selectedQuality == nil then
        InfoDialog.show(g_i18n:getText("usedplus_tires_selectFirst") or "Please select a tire quality first.")
        return
    end

    local cost = self:getCostForQuality(self.selectedQuality)

    -- Client-side validation for immediate feedback
    if g_currentMission:getMoney(self.farmId) < cost then
        InfoDialog.show(g_i18n:getText("usedplus_error_insufficientFunds") or "Insufficient funds!")
        return
    end

    if not self.vehicle then
        UsedPlus.logError("TiresDialog:onConfirm - No vehicle set")
        return
    end

    -- v2.8.0: Use network event for multiplayer synchronization
    -- Event handles: money deduction, setTireQuality, and flat tire repair
    ReplaceTiresEvent.sendToServer(
        self.farmId,
        self.vehicle.id,
        self.selectedQuality,  -- Quality tier: 1=Retread, 2=Normal, 3=Quality
        cost
    )

    -- Log request sent (server will log actual execution)
    UsedPlus.logDebug(string.format("TiresDialog: Sent tire replacement request - %s: %s for %s%s",
        self.vehicleName, self:getQualityName(self.selectedQuality),
        g_i18n:formatMoney(cost, 0, true, true),
        self.hasFlatTire and " (includes flat repair)" or ""))

    -- Close dialog
    self:close()

    -- Show confirmation
    InfoDialog.show(
        string.format(g_i18n:getText("usedplus_tires_replaced") or "Tires replaced: %s",
            self:getQualityName(self.selectedQuality))
    )
end

--[[
    Cancel button
]]
function TiresDialog:onCancel()
    self:close()
end

function TiresDialog:onClose()
    TiresDialog:superClass().onClose(self)
end

UsedPlus.logInfo("TiresDialog loaded")
