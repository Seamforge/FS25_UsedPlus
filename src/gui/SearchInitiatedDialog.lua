--[[
    FS25_UsedPlus - Search Initiated Confirmation Dialog

    Styled dialog showing search details after agent is hired.
    Matches styling of LoanApprovedDialog.
    v1.5.0: Multi-find agent model
]]

SearchInitiatedDialog = {}
local SearchInitiatedDialog_mt = Class(SearchInitiatedDialog, ScreenElement)

-- Static instance
SearchInitiatedDialog.instance = nil
SearchInitiatedDialog.xmlPath = nil

--[[
    Get or create dialog instance
]]
function SearchInitiatedDialog.getInstance()
    if SearchInitiatedDialog.instance == nil then
        if SearchInitiatedDialog.xmlPath == nil then
            SearchInitiatedDialog.xmlPath = UsedPlus.MOD_DIR .. "gui/SearchInitiatedDialog.xml"
        end

        SearchInitiatedDialog.instance = SearchInitiatedDialog.new()
        g_gui:loadGui(SearchInitiatedDialog.xmlPath, "SearchInitiatedDialog", SearchInitiatedDialog.instance)

        UsedPlus.logDebug("SearchInitiatedDialog created and loaded")
    end

    return SearchInitiatedDialog.instance
end

--[[
    Constructor
]]
function SearchInitiatedDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or SearchInitiatedDialog_mt)
    self.isBackAllowed = true
    return self
end

--[[
    Called when dialog is created
]]
function SearchInitiatedDialog:onCreate()
    -- Store icon directory for later use
    self.iconDir = UsedPlus.MOD_DIR .. "gui/icons/"
end

--[[
    Setup header icon - must be called after elements are bound
    Small confirmation dialogs use header icon only (no section icons)
]]
function SearchInitiatedDialog:setupSectionIcons()
    -- Header icon (search icon)
    local headerIcon = self.dialogElement:getDescendantById("headerIcon")
    if headerIcon ~= nil then
        headerIcon:setImageFilename(self.iconDir .. "search.dds")
    end
end

--[[
    Show dialog with search details
    @param details - Table with search details:
        vehicleName, tierName, duration, maxListings,
        qualityName, retainerFee, commissionPercent,
        estimatedBasePrice, estimatedCommission, estimatedAskingPrice
]]
function SearchInitiatedDialog:show(details)
    if details == nil then
        UsedPlus.logError("SearchInitiatedDialog:show called with nil details")
        return
    end

    -- Populate fields
    self:updateDisplay(details)

    -- Show the dialog
    g_gui:showDialog("SearchInitiatedDialog")
end

--[[
    Static convenience method to show dialog
    Can be called without getting instance first
]]
function SearchInitiatedDialog.showWithDetails(details)
    local dialog = SearchInitiatedDialog.getInstance()
    if dialog then
        dialog:show(details)
    end
end

--[[
    Update all display fields
]]
function SearchInitiatedDialog:updateDisplay(details)
    -- Vehicle name
    if self.vehicleNameText then
        self.vehicleNameText:setText(details.vehicleName or g_i18n:getText("usedplus_common_unknownVehicle"))
    end

    -- Search tier
    if self.tierText then
        self.tierText:setText(details.tierName or g_i18n:getText("usedplus_si_defaultTier"))
    end

    -- Duration
    if self.durationText then
        self.durationText:setText(details.duration or g_i18n:getText("usedplus_si_defaultDuration"))
    end

    -- Quality target
    if self.qualityText then
        self.qualityText:setText(details.qualityName or g_i18n:getText("usedplus_si_defaultQuality"))
    end

    -- Max finds
    if self.maxFindsText then
        local maxListings = details.maxListings or 6
        self.maxFindsText:setText(string.format(g_i18n:getText("usedplus_si_maxFinds"), maxListings))
    end

    -- Retainer fee (already formatted or raw number)
    if self.retainerText then
        local retainer = details.retainerFee
        if type(retainer) == "number" then
            retainer = g_i18n:formatMoney(retainer, 0, true, true)
        end
        self.retainerText:setText(retainer or "$0")
    end

    -- Commission rate
    if self.commissionText then
        local commPct = details.commissionPercent or 8
        if type(commPct) == "number" and commPct < 1 then
            commPct = math.floor(commPct * 100)
        end
        self.commissionText:setText(string.format("%d%%", commPct))
    end

    -- Estimated base price
    if self.basePriceText then
        local basePrice = details.estimatedBasePrice
        if type(basePrice) == "number" then
            basePrice = g_i18n:formatMoney(basePrice, 0, true, true)
        end
        self.basePriceText:setText(basePrice or "$0")
    end

    -- Estimated commission amount
    if self.commissionAmtText then
        local commAmt = details.estimatedCommission
        if type(commAmt) == "number" then
            commAmt = "+" .. g_i18n:formatMoney(commAmt, 0, true, true)
        end
        self.commissionAmtText:setText(commAmt or "+$0")
    end

    -- Estimated asking price
    if self.askingPriceText then
        local askingPrice = details.estimatedAskingPrice
        if type(askingPrice) == "number" then
            askingPrice = g_i18n:formatMoney(askingPrice, 0, true, true)
        end
        self.askingPriceText:setText(askingPrice or "$0")
    end
end

--[[
    Handle OK button click
]]
function SearchInitiatedDialog:onClickOk()
    g_gui:changeScreen(nil)
end

--[[
    Handle ESC key / back button
]]
function SearchInitiatedDialog:onClickBack()
    g_gui:changeScreen(nil)
    return true
end

--[[
    Called when dialog opens
]]
function SearchInitiatedDialog:onOpen()
    SearchInitiatedDialog:superClass().onOpen(self)

    -- Setup section icons
    self:setupSectionIcons()
end

--[[
    Called when dialog closes
]]
function SearchInitiatedDialog:onClose()
    SearchInitiatedDialog:superClass().onClose(self)
end

UsedPlus.logInfo("SearchInitiatedDialog loaded")
