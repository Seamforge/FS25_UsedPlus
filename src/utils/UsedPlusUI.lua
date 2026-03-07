--[[
    FS25_UsedPlus - UsedPlusUI.lua

    High-level UI component system for consistent dialog layouts
    Provides reusable patterns for sections, tables, label-value pairs
    Works with UIHelper.lua for actual formatting

    Components:
    - UsedPlusUI.Section: Section headers with title and description
    - UsedPlusUI.LabelValue: Label-value pair displays
    - UsedPlusUI.Table: Table/list building helpers
    - UsedPlusUI.Columns: Multi-column layout helpers
    - UsedPlusUI.Comparison: Side-by-side comparison displays
    - UsedPlusUI.Dialog: Common dialog setup patterns
]]

UsedPlusUI = {}

-- ============================================================================
-- SECTION COMPONENT
-- Standardized section headers (50+ instances across dialogs)
-- ============================================================================

UsedPlusUI.Section = {}

--[[
    Display a section header with title and optional description
    @param titleElement - Text element for section title
    @param descElement - Text element for description (optional)
    @param title - Title text
    @param description - Description text (optional)
    @param titleColor - Color for title (default GOLD)
]]
function UsedPlusUI.Section.display(titleElement, descElement, title, description, titleColor)
    titleColor = titleColor or UIHelper.Colors.GOLD

    if titleElement then
        titleElement:setText(title or "")
        if titleElement.setTextColor then
            titleElement:setTextColor(unpack(titleColor))
        end
    end

    if descElement and description then
        descElement:setText(description)
        if descElement.setTextColor then
            descElement:setTextColor(unpack(UIHelper.Colors.GRAY))
        end
    end
end

--[[
    Show/hide an entire section (title, description, and content container)
    @param elements - Table of elements belonging to section
    @param visible - Boolean visibility
]]
function UsedPlusUI.Section.setVisible(elements, visible)
    for _, element in pairs(elements) do
        UIHelper.Element.setVisible(element, visible)
    end
end

--[[
    Standard section titles used across dialogs
    (For localization reference)
]]
UsedPlusUI.Section.Titles = {
    -- Credit/Finance sections
    YOUR_CREDIT = "YOUR CREDIT",
    COLLATERAL = "COLLATERAL",
    LOAN_CONFIGURATION = "LOAN CONFIGURATION",
    PAYMENT_PREVIEW = "PAYMENT PREVIEW",
    FINANCE_TERMS = "FINANCE TERMS",
    LEASE_TERMS = "LEASE TERMS",

    -- Vehicle sections
    ITEM_DETAILS = "ITEM DETAILS",
    VEHICLE = "VEHICLE",
    VEHICLE_TO_SELL = "VEHICLE TO SELL",
    VEHICLE_STATUS = "VEHICLE STATUS",

    -- Purchase sections
    PURCHASE_METHOD = "PURCHASE METHOD",
    TRADE_IN = "TRADE-IN",
    PAYMENT_SUMMARY = "PAYMENT SUMMARY",
    DUE_TODAY = "DUE TODAY",

    -- Search sections
    SEARCH_TIER = "SEARCH TIER SELECTION",
    DESIRED_QUALITY = "DESIRED QUALITY",

    -- Agent/Sale sections
    SELECT_AGENT = "SELECT SALES AGENT",
    AGENT_DETAILS = "AGENT DETAILS",
    VALUE_COMPARISON = "VALUE COMPARISON",
    OFFER_DETAILS = "OFFER DETAILS",
    COMPARISON = "COMPARISON",

    -- Dashboard sections
    CREDIT_SCORE = "CREDIT SCORE",
    DEBT_RATIO = "DEBT RATIO",
    MONTHLY_OBLIGATIONS = "MONTHLY OBLIGATIONS",
    UPCOMING_PAYMENTS = "UPCOMING PAYMENTS",
    LIFETIME_STATISTICS = "LIFETIME STATISTICS",

    -- Repair sections
    MECHANICAL_REPAIR = "MECHANICAL REPAIR",
    REPAINT = "REPAINT",
    PAYMENT = "PAYMENT",

    -- Land sections
    FIELD_DETAILS = "FIELD DETAILS",
    CONFIGURATION = "CONFIGURATION",
}

-- ============================================================================
-- LABEL-VALUE PAIR COMPONENT
-- Standardized label-value displays (140+ instances)
-- ============================================================================

UsedPlusUI.LabelValue = {}

--[[
    Display a label-value pair
    @param labelElement - Text element for label
    @param valueElement - Text element for value
    @param label - Label text
    @param value - Value text
    @param valueColor - Optional color for value
]]
function UsedPlusUI.LabelValue.display(labelElement, valueElement, label, value, valueColor)
    if labelElement then
        labelElement:setText(label or "")
        if labelElement.setTextColor then
            labelElement:setTextColor(unpack(UIHelper.Colors.GRAY))
        end
    end

    if valueElement then
        valueElement:setText(value or "")
        if valueColor and valueElement.setTextColor then
            valueElement:setTextColor(unpack(valueColor))
        end
    end
end

--[[
    Display a money label-value pair with appropriate coloring
    @param labelElement - Text element for label
    @param valueElement - Text element for value
    @param label - Label text
    @param amount - Money amount
    @param isPositive - True for green (asset), false for red (debt), nil for white
]]
function UsedPlusUI.LabelValue.displayMoney(labelElement, valueElement, label, amount, isPositive)
    local valueColor = UIHelper.Colors.WHITE
    if isPositive == true then
        valueColor = UIHelper.Colors.MONEY_GREEN
    elseif isPositive == false then
        valueColor = UIHelper.Colors.DEBT_RED
    end

    UsedPlusUI.LabelValue.display(
        labelElement,
        valueElement,
        label,
        UIHelper.Text.formatMoney(amount),
        valueColor
    )
end

--[[
    Display a percentage label-value pair
    @param labelElement - Text element for label
    @param valueElement - Text element for value
    @param label - Label text
    @param percent - Percentage value (0-100 or 0-1 if isDecimal)
    @param isDecimal - If true, multiply by 100
    @param valueColor - Optional color
]]
function UsedPlusUI.LabelValue.displayPercent(labelElement, valueElement, label, percent, isDecimal, valueColor)
    UsedPlusUI.LabelValue.display(
        labelElement,
        valueElement,
        label,
        UIHelper.Text.formatPercent(percent, isDecimal),
        valueColor or UIHelper.Colors.WHITE
    )
end

--[[
    Display an interest rate label-value pair (always orange)
    @param labelElement - Text element for label
    @param valueElement - Text element for value
    @param label - Label text (default "Interest Rate:")
    @param rate - Rate as decimal (0.08 = 8%)
]]
function UsedPlusUI.LabelValue.displayInterestRate(labelElement, valueElement, label, rate)
    UsedPlusUI.LabelValue.display(
        labelElement,
        valueElement,
        label or "Interest Rate:",
        UIHelper.Text.formatInterestRate(rate),
        UIHelper.Colors.COST_ORANGE
    )
end

--[[
    Display a term label-value pair
    @param labelElement - Text element for label
    @param valueElement - Text element for value
    @param label - Label text
    @param count - Number of units
    @param unit - Unit type ("year", "month", etc.)
]]
function UsedPlusUI.LabelValue.displayTerm(labelElement, valueElement, label, count, unit)
    UsedPlusUI.LabelValue.display(
        labelElement,
        valueElement,
        label,
        UIHelper.Text.formatTerm(count, unit),
        UIHelper.Colors.WHITE
    )
end

--[[
    Batch update multiple label-value pairs
    @param pairs - Array of {labelElement, valueElement, label, value, color}
]]
function UsedPlusUI.LabelValue.displayMultiple(pairs)
    for _, pair in ipairs(pairs) do
        UsedPlusUI.LabelValue.display(
            pair.labelElement or pair[1],
            pair.valueElement or pair[2],
            pair.label or pair[3],
            pair.value or pair[4],
            pair.color or pair[5]
        )
    end
end

-- ============================================================================
-- TABLE/LIST COMPONENT
-- Helpers for building and populating tables
-- ============================================================================

UsedPlusUI.Table = {}

--[[
    Populate a scrollable list with items
    @param listElement - SmoothList element
    @param items - Array of data items
    @param populateRow - Function(rowElement, item, index) to populate each row
]]
function UsedPlusUI.Table.populateList(listElement, items, populateRow)
    if not listElement then return end

    -- Clear existing items
    listElement:deleteListItems()

    -- Add new items
    for index, item in ipairs(items) do
        local row = listElement:createItem()
        if row and populateRow then
            populateRow(row, item, index)
        end
    end
end

--[[
    Set column header texts
    @param headers - Table mapping column name to {element, text}
]]
function UsedPlusUI.Table.setHeaders(headers)
    for _, header in pairs(headers) do
        if header.element and header.text then
            header.element:setText(header.text)
        end
    end
end

--[[
    Standard table row population for finance deals
    @param row - Row element
    @param deal - FinanceDeal or similar object
    @param columnIds - Table mapping column names to element IDs within row
]]
function UsedPlusUI.Table.populateFinanceDealRow(row, deal, columnIds)
    columnIds = columnIds or {
        name = "loanName",
        balance = "balance",
        mode = "mode",
        payment = "amount"
    }

    -- Get child elements by name
    local nameElement = row:getDescendantByName(columnIds.name)
    local balanceElement = row:getDescendantByName(columnIds.balance)
    local modeElement = row:getDescendantByName(columnIds.mode)
    local paymentElement = row:getDescendantByName(columnIds.payment)

    if nameElement then
        nameElement:setText(deal.itemName or g_i18n:getText("usedplus_common_unknown"))
    end

    if balanceElement then
        balanceElement:setText(UIHelper.Text.formatMoney(deal.remainingBalance or 0))
    end

    if modeElement then
        local modeText = "Standard"
        if deal.paymentMode and FinanceDeal and FinanceDeal.PAYMENT_MODE_NAMES then
            modeText = FinanceDeal.PAYMENT_MODE_NAMES[deal.paymentMode] or "Standard"
        end
        modeElement:setText(modeText)
    end

    if paymentElement then
        paymentElement:setText(UIHelper.Text.formatMoney(deal.monthlyPayment or 0))
    end
end

--[[
    Build array of row data for a fixed-row table display
    (For tables with pre-defined rows like FinancialDashboard upcoming payments)
    @param maxRows - Maximum number of rows in the display
    @param items - Array of items to display
    @param formatItem - Function(item) returning {text1, text2, ...} for columns
    @return Array of formatted row data
]]
function UsedPlusUI.Table.buildFixedRowData(maxRows, items, formatItem)
    local rows = {}
    for i = 1, maxRows do
        if items[i] then
            rows[i] = formatItem(items[i])
        else
            rows[i] = nil  -- Empty row
        end
    end
    return rows
end

--[[
    Display data in fixed pre-defined rows
    @param rowElements - Array of {col1Element, col2Element, ...} for each row
    @param rowData - Array from buildFixedRowData
]]
function UsedPlusUI.Table.displayFixedRows(rowElements, rowData)
    for i, elements in ipairs(rowElements) do
        local data = rowData[i]
        if data then
            for j, element in ipairs(elements) do
                if element then
                    element:setText(data[j] or "")
                    element:setVisible(true)
                end
            end
        else
            -- Hide empty rows
            for _, element in ipairs(elements) do
                if element then
                    element:setText("")
                    -- Optionally hide: element:setVisible(false)
                end
            end
        end
    end
end

-- ============================================================================
-- MULTI-COLUMN LAYOUT COMPONENT
-- Helpers for 2/3/4 column layouts (25+ instances)
-- ============================================================================

UsedPlusUI.Columns = {}

-- Standard column position offsets (centered layout)
UsedPlusUI.Columns.POSITIONS = {
    TWO_COL = {-150, 150},
    THREE_COL = {-280, 0, 280},
    THREE_COL_NARROW = {-200, 0, 200},
    FOUR_COL = {-300, -100, 100, 300},
}

--[[
    Display data across multiple columns
    @param columnElements - Array of column container elements
    @param columnData - Array of {element, text, color} for each column
]]
function UsedPlusUI.Columns.display(columnElements, columnData)
    for i, element in ipairs(columnElements) do
        local data = columnData[i]
        if element and data then
            if data.text then
                element:setText(data.text)
            end
            if data.color and element.setTextColor then
                element:setTextColor(unpack(data.color))
            end
        end
    end
end

--[[
    Display a row of label-value pairs across columns
    @param columns - Array of {labelElement, valueElement} for each column
    @param data - Array of {label, value, valueColor} for each column
]]
function UsedPlusUI.Columns.displayLabelValueRow(columns, data)
    for i, col in ipairs(columns) do
        local d = data[i]
        if col and d then
            UsedPlusUI.LabelValue.display(
                col.labelElement or col[1],
                col.valueElement or col[2],
                d.label or d[1],
                d.value or d[2],
                d.valueColor or d[3]
            )
        end
    end
end

-- ============================================================================
-- COMPARISON COMPONENT
-- Side-by-side value comparisons (5+ instances)
-- ============================================================================

UsedPlusUI.Comparison = {}

--[[
    Display a two-option comparison
    @param option1 - {labelElement, valueElement, label, value, color}
    @param option2 - {labelElement, valueElement, label, value, color}
]]
function UsedPlusUI.Comparison.displayTwoOptions(option1, option2)
    UsedPlusUI.LabelValue.display(
        option1.labelElement, option1.valueElement,
        option1.label, option1.value, option1.color
    )
    UsedPlusUI.LabelValue.display(
        option2.labelElement, option2.valueElement,
        option2.label, option2.value, option2.color
    )
end

--[[
    Display tier options (Local/Regional/National pattern)
    @param tiers - Array of tier elements with sub-elements
    @param tierData - Array of {name, cost, time, returnRange, selected}
    @param selectedTier - Index of selected tier (1-based)
]]
function UsedPlusUI.Comparison.displayTierOptions(tiers, tierData, selectedTier)
    for i, tier in ipairs(tiers) do
        local data = tierData[i]
        if tier and data then
            -- Set tier name
            if tier.nameElement then
                tier.nameElement:setText(data.name or "")
            end

            -- Set cost
            if tier.costElement then
                tier.costElement:setText(UIHelper.Text.formatMoney(data.cost or 0))
            end

            -- Set time
            if tier.timeElement then
                tier.timeElement:setText(data.time or "")
            end

            -- Set return range
            if tier.returnElement then
                tier.returnElement:setText(data.returnRange or "")
            end

            -- Highlight selected
            if tier.bgElement and tier.bgElement.setImageColor then
                if i == selectedTier then
                    tier.bgElement:setImageColor(0.3, 0.5, 0.3, 0.8)  -- Green highlight
                else
                    tier.bgElement:setImageColor(0.2, 0.2, 0.2, 0.5)  -- Normal
                end
            end
        end
    end
end

--[[
    Display price comparison (offer vs vanilla, etc.)
    @param elements - {vanillaLabel, vanillaValue, offerLabel, offerValue, differenceValue}
    @param vanilla - Vanilla/base price
    @param offer - Offer/comparison price
    @param showDifference - Show +/- difference (default true)
]]
function UsedPlusUI.Comparison.displayPriceComparison(elements, vanilla, offer, showDifference)
    showDifference = showDifference ~= false

    if elements.vanillaLabel then
        elements.vanillaLabel:setText(g_i18n:getText("usedplus_ui_vanillaSellPrice"))
    end
    if elements.vanillaValue then
        elements.vanillaValue:setText(UIHelper.Text.formatMoney(vanilla))
    end

    if elements.offerLabel then
        elements.offerLabel:setText(g_i18n:getText("usedplus_ui_thisOffer"))
    end
    if elements.offerValue then
        elements.offerValue:setText(UIHelper.Text.formatMoney(offer))
        -- Color based on comparison
        local color = offer >= vanilla and UIHelper.Colors.MONEY_GREEN or UIHelper.Colors.WARNING_RED
        if elements.offerValue.setTextColor then
            elements.offerValue:setTextColor(unpack(color))
        end
    end

    if showDifference and elements.differenceValue then
        local diff = offer - vanilla
        local diffText = (diff >= 0 and "+" or "") .. UIHelper.Text.formatMoney(diff)
        elements.differenceValue:setText(diffText)
        local color = diff >= 0 and UIHelper.Colors.MONEY_GREEN or UIHelper.Colors.WARNING_RED
        if elements.differenceValue.setTextColor then
            elements.differenceValue:setTextColor(unpack(color))
        end
    end
end

-- ============================================================================
-- DIALOG HELPERS
-- Common dialog setup and lifecycle patterns
-- ============================================================================

UsedPlusUI.Dialog = {}

--[[
    Standard dialog initialization
    Call this in onGuiSetupFinished to cache common elements
    @param dialog - Dialog instance
    @param elementIds - Array of element IDs to cache
    @return Table of cached elements
]]
function UsedPlusUI.Dialog.cacheElements(dialog, elementIds)
    local cached = {}
    for _, id in ipairs(elementIds) do
        cached[id] = dialog[id]
    end
    return cached
end

--[[
    Standard dialog data validation
    @param data - Table of required data
    @return boolean, string - isValid, errorMessage
]]
function UsedPlusUI.Dialog.validateData(data)
    for key, value in pairs(data) do
        if value == nil then
            return false, string.format("Missing required data: %s", key)
        end
    end
    return true, nil
end

--[[
    Safe dialog close
    @param dialog - Dialog instance
]]
function UsedPlusUI.Dialog.safeClose(dialog)
    if dialog and dialog.close then
        dialog:close()
    end
end

--[[
    Show error and close dialog
    @param dialog - Dialog instance
    @param message - Error message
]]
function UsedPlusUI.Dialog.showErrorAndClose(dialog, message)
    -- Show error message then close dialog
    InfoDialog.show(message or g_i18n:getText("usedplus_error_genericError"))
    UsedPlusUI.Dialog.safeClose(dialog)
end

-- ============================================================================
-- VEHICLE INFO CARD COMPONENT
-- Standard vehicle display card used by 5+ dialogs
-- ============================================================================

UsedPlusUI.VehicleCard = {}

--[[
    Display vehicle information in a standard card layout
    @param elements - Table of UI elements:
        - imageElement: Bitmap for vehicle image
        - nameElement: Text for vehicle name
        - priceElement: Text for price
        - categoryElement: Text for category (optional)
        - brandElement: Text for brand (optional)
        - conditionElement: Text for condition (optional)
        - usedBadgeElement: Text for USED badge (optional)
    @param storeItem - Store item data
    @param options - Additional options:
        - price: Override price to display
        - isUsed: Boolean for used badge
        - condition: Condition percentage for used vehicles
        - showCategory: Show category (default true)
]]
function UsedPlusUI.VehicleCard.display(elements, storeItem, options)
    options = options or {}

    if not storeItem then
        -- Hide all elements if no item
        for _, element in pairs(elements) do
            UIHelper.Element.setVisible(element, false)
        end
        return
    end

    -- Image
    if elements.imageElement then
        UIHelper.Image.setStoreItemImage(elements.imageElement, storeItem)
    end

    -- Name
    if elements.nameElement then
        elements.nameElement:setText(storeItem.name or g_i18n:getText("usedplus_common_unknown"))
        UIHelper.Element.setVisible(elements.nameElement, true)
    end

    -- Price
    if elements.priceElement then
        local price = options.price or storeItem.price or 0
        elements.priceElement:setText(UIHelper.Text.formatMoney(price))
        UIHelper.Element.setVisible(elements.priceElement, true)
    end

    -- Category
    if elements.categoryElement and options.showCategory ~= false then
        local category = storeItem.categoryName or storeItem.category or ""
        elements.categoryElement:setText(category)
        UIHelper.Element.setVisible(elements.categoryElement, true)
    end

    -- Brand
    if elements.brandElement then
        local brand = storeItem.brandName or storeItem.brand or ""
        elements.brandElement:setText(brand)
        UIHelper.Element.setVisible(elements.brandElement, true)
    end

    -- Condition (for used vehicles)
    if elements.conditionElement and options.condition then
        elements.conditionElement:setText(string.format(g_i18n:getText("usedplus_ui_conditionPercent"), options.condition))
        UIHelper.Element.setVisible(elements.conditionElement, true)
    end

    -- Used badge
    if elements.usedBadgeElement then
        UIHelper.Vehicle.displayUsedBadge(
            elements.usedBadgeElement,
            options.isUsed,
            options.condition
        )
    end
end

--[[
    Display vehicle card from vehicle object (instead of store item)
    @param elements - Same as above
    @param vehicle - Vehicle instance
    @param options - Same as above
]]
function UsedPlusUI.VehicleCard.displayFromVehicle(elements, vehicle, options)
    if not vehicle then
        UsedPlusUI.VehicleCard.display(elements, nil, options)
        return
    end

    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    options = options or {}

    -- Get condition from vehicle
    if vehicle.getDamageAmount then
        local damage = vehicle:getDamageAmount() or 0
        local wear = vehicle.getWearTotalAmount and vehicle:getWearTotalAmount() or 0
        local avgCondition = math.floor(((1 - damage) + (1 - wear)) / 2 * 100)
        options.condition = avgCondition
    end

    -- Get sell price
    if vehicle.getSellPrice and not options.price then
        options.price = vehicle:getSellPrice()
    end

    UsedPlusUI.VehicleCard.display(elements, storeItem, options)
end

-- ============================================================================
-- QUICK BUTTON COMPONENT
-- Parameterized quick selection buttons
-- ============================================================================

UsedPlusUI.QuickButtons = {}

--[[
    Create quick button click handler
    @param callback - Function to call with selected value
    @return Function that can be used as onClick handler
]]
function UsedPlusUI.QuickButtons.createHandler(callback)
    return function(value)
        return function()
            if callback then
                callback(value)
            end
        end
    end
end

--[[
    Standard percentage quick buttons (25, 50, 75, 100)
]]
UsedPlusUI.QuickButtons.PERCENTAGES = {25, 50, 75, 100}

--[[
    Standard term quick buttons (1, 3, 6, 12 months)
]]
UsedPlusUI.QuickButtons.TERM_MONTHS = {1, 3, 6, 12}

-- ============================================================================

UsedPlus.logInfo("UsedPlusUI loaded")
