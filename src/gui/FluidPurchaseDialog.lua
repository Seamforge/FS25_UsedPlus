--[[
    FS25_UsedPlus - Fluid Purchase Dialog

    Custom dialog for purchasing fluids (Engine Oil or Hydraulic Fluid)
    for the Oil Service Tank placeable.

    Pattern from: FluidsDialog, TiresDialog (singleton pattern)

    v1.9.3 - Custom popup dialog with MultiTextOption
]]

FluidPurchaseDialog = {}
local FluidPurchaseDialog_mt = Class(FluidPurchaseDialog, MessageDialog)

-- Singleton instance
FluidPurchaseDialog.INSTANCE = nil

-- Fluid type definitions
FluidPurchaseDialog.FLUID_TYPES = {"oil", "hydraulic"}

-- v2.11.1: Selectable purchase amounts (50L increments up to 500L)
FluidPurchaseDialog.PURCHASE_AMOUNTS = {50, 100, 150, 200, 250, 300, 350, 400, 450, 500}

--[[
    Constructor
]]
function FluidPurchaseDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or FluidPurchaseDialog_mt)

    -- Reference to the service point
    self.servicePoint = nil

    -- Current selection
    self.selectedFluidType = "oil"
    self.fluidTypeIndex = 1

    -- Tank data (populated on open)
    self.tankLevel = 0
    self.tankCapacity = 500
    self.tankFluidType = nil
    self.pricePerLiter = 5

    -- v2.11.1: Amount selection (50L-500L)
    self.selectedAmount = 50
    self.amountIndex = 1
    self.availableAmounts = {}

    return self
end

--[[
    Ensure dialog is loaded (called once)
]]
function FluidPurchaseDialog.ensureLoaded()
    if g_gui.guis["FluidPurchaseDialog"] == nil then
        local xmlPath = UsedPlus.MOD_DIR .. "gui/FluidPurchaseDialog.xml"
        g_gui:loadGui(xmlPath, "FluidPurchaseDialog", FluidPurchaseDialog.new())
        UsedPlus.logDebug("FluidPurchaseDialog loaded from: " .. xmlPath)
    end
end

--[[
    Called when GUI elements are ready
]]
function FluidPurchaseDialog:onGuiSetupFinished()
    FluidPurchaseDialog:superClass().onGuiSetupFinished(self)

    -- v2.8.0: Callback is now bound via XML onClick attribute (not setCallback)
    -- See FluidPurchaseDialog.xml: <MultiTextOption ... onClick="onFluidTypeChanged"/>
end

--[[
    Set the service point reference
    @param servicePoint - The OilServicePoint placeable
]]
function FluidPurchaseDialog:setServicePoint(servicePoint)
    self.servicePoint = servicePoint

    if servicePoint == nil then
        UsedPlus.logError("FluidPurchaseDialog:setServicePoint - No service point provided")
        return
    end

    -- Get current tank status
    local spec = servicePoint.spec_oilServicePoint
    if spec then
        self.tankLevel = spec.currentFluidStorage or 0
        self.tankCapacity = spec.storageCapacity or 500
        self.tankFluidType = spec.currentFluidType
        self.pricePerLiter = spec.oilPricePerLiter or 5
    end

    -- Default selection based on tank contents
    if self.tankFluidType == "hydraulic" then
        self.selectedFluidType = "hydraulic"
        self.fluidTypeIndex = 2
    else
        self.selectedFluidType = "oil"
        self.fluidTypeIndex = 1
    end

    UsedPlus.logDebug(string.format("FluidPurchaseDialog:setServicePoint - tank=%.0f/%.0f, type=%s",
        self.tankLevel, self.tankCapacity, tostring(self.tankFluidType)))
end

--[[
    Called when dialog opens
]]
function FluidPurchaseDialog:onOpen()
    FluidPurchaseDialog:superClass().onOpen(self)

    -- Populate dropdowns
    self:populateFluidTypeOptions()
    self:populateAmountOptions()

    -- Update display
    self:updateDisplay()
end

--[[
    Populate the fluid type MultiTextOption dropdown
]]
function FluidPurchaseDialog:populateFluidTypeOptions()
    if self.fluidTypeOption == nil then
        return
    end

    local oilName = g_i18n:getText("usedplus_fluid_oil") or "Engine Oil"
    local hydraulicName = g_i18n:getText("usedplus_fluid_hydraulic") or "Hydraulic Fluid"

    self.fluidTypeOption:setTexts({oilName, hydraulicName})
    self.fluidTypeOption:setState(self.fluidTypeIndex)
end

--[[
    v2.11.1: Populate amount selection (50L increments, capped at available space)
]]
function FluidPurchaseDialog:populateAmountOptions()
    if self.amountOption == nil then
        return
    end

    local spaceAvailable = self.tankCapacity - self.tankLevel
    self.availableAmounts = {}
    local texts = {}

    for _, amount in ipairs(FluidPurchaseDialog.PURCHASE_AMOUNTS) do
        if amount <= spaceAvailable then
            table.insert(self.availableAmounts, amount)
            table.insert(texts, string.format("%d L", amount))
        end
    end

    -- If space is less than 50L but > 0, offer what's left
    if #self.availableAmounts == 0 and spaceAvailable > 0 then
        local remaining = math.floor(spaceAvailable)
        table.insert(self.availableAmounts, remaining)
        table.insert(texts, string.format("%d L", remaining))
    end

    if #texts > 0 then
        self.amountOption:setTexts(texts)
        -- Default to the largest amount
        self.amountIndex = #self.availableAmounts
        self.amountOption:setState(self.amountIndex)
        self.selectedAmount = self.availableAmounts[self.amountIndex]
    else
        self.amountOption:setTexts({"Tank Full"})
        self.amountOption:setState(1)
        self.selectedAmount = 0
    end
end

--[[
    v2.11.1: Amount dropdown changed
]]
function FluidPurchaseDialog:onAmountChanged()
    if self.amountOption == nil then
        return
    end

    local state = self.amountOption:getState()
    if state >= 1 and state <= #self.availableAmounts then
        self.amountIndex = state
        self.selectedAmount = self.availableAmounts[state]
    end

    self:updateDisplay()
end

--[[
    Update all display elements
]]
function FluidPurchaseDialog:updateDisplay()
    -- Tank level
    if self.tankLevelText then
        self.tankLevelText:setText(string.format("%.0f / %.0f L", self.tankLevel, self.tankCapacity))
    end

    -- Tank contents
    if self.tankContentsText then
        if self.tankFluidType and self.tankLevel > 0 then
            local fluidName = g_i18n:getText("usedplus_fluid_" .. self.tankFluidType) or self.tankFluidType
            self.tankContentsText:setText(fluidName)
            if self.tankFluidType == "oil" then
                self.tankContentsText:setTextColor(1, 0.8, 0.2, 1)
            else
                self.tankContentsText:setTextColor(0.4, 0.85, 1, 1)
            end
        else
            self.tankContentsText:setText("Empty")
            self.tankContentsText:setTextColor(0.5, 0.5, 0.5, 1)
        end
    end

    -- v2.11.1: Calculate purchase details using selected amount
    local spaceAvailable = self.tankCapacity - self.tankLevel
    local purchaseAmount = self.selectedAmount or 0
    local cost = purchaseAmount * self.pricePerLiter

    -- Cost text
    if self.costText then
        if spaceAvailable <= 0 or purchaseAmount <= 0 then
            self.costText:setText("-")
            self.costText:setTextColor(0.5, 0.5, 0.5, 1)
        else
            self.costText:setText(g_i18n:formatMoney(cost, 0, true, true))
            self.costText:setTextColor(0.3, 1, 0.4, 1)
        end
    end

    -- Check if we can purchase the selected fluid type
    local canPurchase = spaceAvailable > 0 and purchaseAmount > 0

    -- Can't mix fluids
    if self.tankFluidType and self.tankLevel > 0 and self.tankFluidType ~= self.selectedFluidType then
        canPurchase = false
        if self.costText then
            local currentFluidName = g_i18n:getText("usedplus_fluid_" .. self.tankFluidType) or self.tankFluidType
            self.costText:setText("Contains " .. currentFluidName)
            self.costText:setTextColor(1, 0.5, 0.2, 1)
        end
    end

    -- Update purchase button
    if self.purchaseButton then
        self.purchaseButton:setDisabled(not canPurchase)
    end
end

--[[
    Fluid type dropdown changed
]]
function FluidPurchaseDialog:onFluidTypeChanged()
    if self.fluidTypeOption == nil then
        return
    end

    local state = self.fluidTypeOption:getState()
    if state == 1 then
        self.selectedFluidType = "oil"
        self.fluidTypeIndex = 1
    elseif state == 2 then
        self.selectedFluidType = "hydraulic"
        self.fluidTypeIndex = 2
    end

    -- v2.11.1: Re-populate amounts (available space may change if mixing is blocked)
    self:populateAmountOptions()
    self:updateDisplay()
end

--[[
    Purchase button clicked
]]
function FluidPurchaseDialog:onClickPurchase()
    UsedPlus.logDebug("FluidPurchaseDialog:onClickPurchase - START")

    if self.servicePoint == nil then
        UsedPlus.logError("FluidPurchaseDialog:onClickPurchase - servicePoint is nil!")
        self:close()
        return
    end

    UsedPlus.logDebug(string.format("FluidPurchaseDialog:onClickPurchase - servicePoint exists, tankLevel=%.0f, tankCapacity=%.0f",
        self.tankLevel, self.tankCapacity))

    -- v2.11.1: Use selected amount from dropdown
    local spaceAvailable = self.tankCapacity - self.tankLevel
    local purchaseAmount = math.min(self.selectedAmount or 50, spaceAvailable)

    UsedPlus.logDebug(string.format("FluidPurchaseDialog:onClickPurchase - spaceAvailable=%.0f, purchaseAmount=%.0f",
        spaceAvailable, purchaseAmount))

    if purchaseAmount <= 0 then
        UsedPlus.logDebug("FluidPurchaseDialog:onClickPurchase - No space, closing")
        self:close()
        return
    end

    -- Store values before closing
    local servicePoint = self.servicePoint
    local fluidType = self.selectedFluidType

    UsedPlus.logDebug(string.format("FluidPurchaseDialog:onClickPurchase - Calling purchaseFluid with type=%s, amount=%.0f",
        tostring(fluidType), purchaseAmount))

    -- Close dialog
    self:close()

    -- Attempt purchase (after dialog is closed)
    local success = servicePoint:purchaseFluid(fluidType, purchaseAmount)
    UsedPlus.logDebug("FluidPurchaseDialog:onClickPurchase - purchaseFluid returned: " .. tostring(success))
end

--[[
    Cancel button clicked
]]
function FluidPurchaseDialog:onClickCancel()
    self:close()
end

--[[
    Called when dialog closes
]]
function FluidPurchaseDialog:onClose()
    FluidPurchaseDialog:superClass().onClose(self)
end

--[[
    Static method to show the dialog
    @param servicePoint - The OilServicePoint placeable
]]
function FluidPurchaseDialog.show(servicePoint)
    -- Ensure dialog is loaded first
    FluidPurchaseDialog.ensureLoaded()

    -- Get the controller instance from the GUI system
    local guiEntry = g_gui.guis["FluidPurchaseDialog"]
    if guiEntry == nil or guiEntry.target == nil then
        UsedPlus.logError("FluidPurchaseDialog.show - Failed to get dialog instance")
        return
    end

    -- Set service point and show
    guiEntry.target:setServicePoint(servicePoint)
    g_gui:showDialog("FluidPurchaseDialog")
end

UsedPlus.logInfo("FluidPurchaseDialog.lua loaded")
