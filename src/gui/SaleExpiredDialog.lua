--[[
    FS25_UsedPlus - Sale Expired Dialog

    Popup shown when a vehicle sale listing expires without finding a buyer.
    Offers player the option to relist the vehicle or dismiss.

    Pattern from: SearchExpiredDialog
]]

SaleExpiredDialog = {}
local SaleExpiredDialog_mt = Class(SaleExpiredDialog, MessageDialog)

SaleExpiredDialog.CONTROLS = {
    "vehicleNameText",
    "agentTierText",
    "priceTierText",
    "durationText",
    "offersReceivedText",
    "feePaidText",
    "relistButton",
    "closeButton"
}

--[[
    Constructor
]]
function SaleExpiredDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or SaleExpiredDialog_mt)
    self.isLoaded = false

    -- Listing data
    self.listing = nil
    self.callback = nil

    return self
end

--[[
    Get singleton instance (lazy load)
]]
function SaleExpiredDialog.getInstance()
    if g_saleExpiredDialog == nil then
        g_saleExpiredDialog = SaleExpiredDialog.new()

        -- Load XML
        local xmlPath = Utils.getFilename("gui/SaleExpiredDialog.xml", UsedPlus.MOD_DIR)
        g_gui:loadGui(xmlPath, "SaleExpiredDialog", g_saleExpiredDialog, true)

        UsedPlus.logDebug("SaleExpiredDialog instance created")
    end

    return g_saleExpiredDialog
end

--[[
    onOpen callback
]]
function SaleExpiredDialog:onOpen()
    SaleExpiredDialog:superClass().onOpen(self)

    -- Assign controls
    self:assignControls()
end

--[[
    Assign control elements from XML
]]
function SaleExpiredDialog:assignControls()
    for _, name in pairs(SaleExpiredDialog.CONTROLS) do
        if self[name] == nil then
            self[name] = self.target and self.target[name]
        end
    end
end

--[[
    Show dialog with listing data
    @param listing - The expired VehicleSaleListing
    @param callback - Function(relistChoice) called on close, true if relisting
]]
function SaleExpiredDialog:show(listing, callback)
    self.listing = listing
    self.callback = callback

    -- Update display
    self:updateDisplay()

    -- Show dialog
    g_gui:showDialog("SaleExpiredDialog")
end

--[[
    Static show method
    @param listing - The expired VehicleSaleListing
    @param callback - Function(relistChoice) called on close
]]
function SaleExpiredDialog.showWithListing(listing, callback)
    DialogLoader.show("SaleExpiredDialog", "show", listing, callback)
end

--[[
    Update display with current data
]]
function SaleExpiredDialog:updateDisplay()
    if self.listing == nil then
        return
    end

    local listing = self.listing

    -- Vehicle name
    if self.vehicleNameText then
        self.vehicleNameText:setText(listing.vehicleName or g_i18n:getText("usedplus_common_unknownVehicle"))
    end

    -- Agent tier
    if self.agentTierText then
        local agentConfig = listing:getAgentTierConfig()
        self.agentTierText:setText(agentConfig.name or g_i18n:getText("usedplus_common_unknown"))
    end

    -- Price tier
    if self.priceTierText then
        local priceConfig = listing:getPriceTierConfig()
        self.priceTierText:setText(priceConfig.name or g_i18n:getText("usedplus_common_unknown"))
    end

    -- Duration listed
    if self.durationText then
        local hoursElapsed = listing.hoursElapsed or 0
        self.durationText:setText(UIHelper.Text.formatHours(hoursElapsed))
    end

    -- Offers received
    if self.offersReceivedText then
        local offers = listing.offersReceived or 0
        local declined = listing.offersDeclined or 0
        if offers > 0 then
            self.offersReceivedText:setText(string.format(g_i18n:getText("usedplus_se_offersDeclined"), offers, declined))
            self.offersReceivedText:setTextColor(1, 0.85, 0.2, 1)  -- Gold
        else
            self.offersReceivedText:setText(g_i18n:getText("usedplus_se_noOffers"))
            self.offersReceivedText:setTextColor(0.6, 0.6, 0.6, 1)  -- Gray
        end
    end

    -- Fee paid (non-refundable)
    if self.feePaidText then
        local fee = listing.agentFee or 0
        if fee > 0 then
            self.feePaidText:setText(UIHelper.Text.formatMoney(fee) .. g_i18n:getText("usedplus_se_nonRefundable"))
            self.feePaidText:setTextColor(1, 0.4, 0.4, 1)  -- Red
        else
            self.feePaidText:setText(g_i18n:getText("usedplus_se_noFeePrivate"))
            self.feePaidText:setTextColor(0.3, 1, 0.4, 1)  -- Green
        end
    end
end

--[[
    Relist button clicked
]]
function SaleExpiredDialog:onClickRelist()
    -- Close dialog
    self:close()

    -- Callback with relist choice
    if self.callback then
        self.callback(true)
    end
end

--[[
    Close/Dismiss button clicked
]]
function SaleExpiredDialog:onClickClose()
    self:close()

    -- Callback with no relist
    if self.callback then
        self.callback(false)
    end
end

--[[
    Close the dialog
]]
function SaleExpiredDialog:close()
    g_gui:closeDialogByName("SaleExpiredDialog")
end

UsedPlus.logInfo("SaleExpiredDialog loaded")
