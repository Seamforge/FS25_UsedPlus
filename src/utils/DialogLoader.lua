--[[
    FS25_UsedPlus - Dialog Loader Utility

    Centralized dialog loading and management
    Eliminates 200+ lines of duplicated dialog loading patterns

    Features:
    - Central registry of all dialogs with their configurations
    - Lazy loading (dialogs only loaded when first used)
    - Unified show/hide API with data setting
    - Automatic fallback handling (dialog.target vs direct)
    - Error logging on failures

    Usage:
        -- Simple show (no data)
        DialogLoader.show("FinancialDashboard")

        -- Show with data method call
        DialogLoader.show("TakeLoanDialog", "setFarmId", farmId)

        -- Show with multiple data args
        DialogLoader.show("RepairDialog", "setVehicle", vehicle, farmId)

        -- Show with callback
        DialogLoader.show("SellVehicleDialog", "setVehicle", vehicle, farmId, callback)
]]

DialogLoader = {}

-- Central dialog registry
-- Each entry: { class = DialogClass, xml = "path/to/dialog.xml" }
DialogLoader.dialogs = {}

-- Track which dialogs have been loaded
DialogLoader.loaded = {}

--[[
    Register a dialog with the loader
    Call this at mod load time for each dialog class

    @param name - Dialog name (matches g_gui.guis key)
    @param dialogClass - The dialog class (e.g., TakeLoanDialog)
    @param xmlPath - Path relative to MOD_DIR (e.g., "gui/TakeLoanDialog.xml")
]]
function DialogLoader.register(name, dialogClass, xmlPath)
    UsedPlus.logDebug(string.format("╔═══ DialogLoader.register() ENTRY ═══"))
    UsedPlus.logDebug(string.format("  name: '%s'", tostring(name)))
    UsedPlus.logDebug(string.format("  dialogClass: %s", tostring(dialogClass)))
    UsedPlus.logDebug(string.format("  dialogClass type: %s", type(dialogClass)))
    UsedPlus.logDebug(string.format("  xmlPath: '%s'", tostring(xmlPath)))

    -- Check if already registered
    if DialogLoader.dialogs[name] then
        UsedPlus.logWarn(string.format("  ⚠ Dialog '%s' ALREADY registered - overwriting", name))
    end

    DialogLoader.dialogs[name] = {
        class = dialogClass,
        xml = xmlPath
    }
    DialogLoader.loaded[name] = false

    -- Verify registration
    local stored = DialogLoader.dialogs[name]
    if stored then
        UsedPlus.logDebug(string.format("  ✓ Stored in dialogs[%s]:", name))
        UsedPlus.logDebug(string.format("    - class: %s", tostring(stored.class)))
        UsedPlus.logDebug(string.format("    - xml: %s", tostring(stored.xml)))
    else
        UsedPlus.logError(string.format("  ✗ FAILED to store in dialogs[%s]!", name))
    end

    UsedPlus.logDebug(string.format("╚═══ DialogLoader.register() EXIT ═══"))
end

--[[
    Ensure a dialog is loaded (lazy loading)
    Returns true if dialog is ready to use

    @param name - Dialog name
    @return boolean - true if loaded successfully
]]
function DialogLoader.ensureLoaded(name)
    UsedPlus.logDebug(string.format("╔═══ DialogLoader.ensureLoaded() ENTRY ═══"))
    UsedPlus.logDebug(string.format("  name: '%s'", tostring(name)))

    -- Already loaded?
    UsedPlus.logDebug(string.format("  Checking if already loaded..."))
    UsedPlus.logDebug(string.format("    DialogLoader.loaded[%s] = %s", name, tostring(DialogLoader.loaded[name])))

    if DialogLoader.loaded[name] then
        UsedPlus.logDebug(string.format("  ✓ Already loaded, returning true"))
        UsedPlus.logDebug(string.format("╚═══ DialogLoader.ensureLoaded() EXIT (cached) ═══"))
        return true
    end

    -- Check if already loaded by another mechanism (getInstance(), etc.)
    UsedPlus.logDebug(string.format("  Checking g_gui.guis[%s]...", name))
    if g_gui and g_gui.guis and g_gui.guis[name] then
        UsedPlus.logDebug(string.format("  ✓ Already loaded in g_gui (skipping duplicate load)"))
        DialogLoader.loaded[name] = true
        UsedPlus.logDebug(string.format("╚═══ DialogLoader.ensureLoaded() EXIT (g_gui cached) ═══"))
        return true
    end

    -- Get registration
    UsedPlus.logDebug(string.format("  Looking up registration for '%s'...", name))
    UsedPlus.logDebug(string.format("    DialogLoader.dialogs exists: %s", tostring(DialogLoader.dialogs ~= nil)))
    UsedPlus.logDebug(string.format("    DialogLoader.dialogs type: %s", type(DialogLoader.dialogs)))

    -- DEBUG: List all registered dialogs
    UsedPlus.logDebug("  Currently registered dialogs:")
    local count = 0
    for dialogName, _ in pairs(DialogLoader.dialogs or {}) do
        count = count + 1
        UsedPlus.logDebug(string.format("    [%d] '%s'", count, dialogName))
    end
    if count == 0 then
        UsedPlus.logWarn("    ⚠ NO DIALOGS REGISTERED!")
    end

    local registration = DialogLoader.dialogs[name]
    UsedPlus.logDebug(string.format("  registration exists: %s", tostring(registration ~= nil)))

    if not registration then
        UsedPlus.logError(string.format("  ✗ Dialog '%s' not registered", name))
        UsedPlus.logError(string.format("╚═══ DialogLoader.ensureLoaded() EXIT (not registered) ═══"))
        return false
    end

    UsedPlus.logDebug(string.format("  ✓ Registration found:"))
    UsedPlus.logDebug(string.format("    - class: %s", tostring(registration.class)))
    UsedPlus.logDebug(string.format("    - xml: %s", tostring(registration.xml)))

    -- Load the dialog
    local dialogClass = registration.class
    local xmlPath = UsedPlus.MOD_DIR .. registration.xml

    UsedPlus.logDebug(string.format("  Full XML path: %s", xmlPath))

    if not dialogClass then
        UsedPlus.logError(string.format("  ✗ Dialog class for '%s' is nil", name))
        UsedPlus.logError(string.format("╚═══ DialogLoader.ensureLoaded() EXIT (nil class) ═══"))
        return false
    end

    UsedPlus.logDebug(string.format("  → Creating dialog instance..."))
    local dialog = dialogClass.new(nil, nil, g_i18n)
    UsedPlus.logDebug(string.format("  ✓ Dialog instance created: %s", tostring(dialog)))

    UsedPlus.logDebug(string.format("  → Loading GUI from XML..."))
    g_gui:loadGui(xmlPath, name, dialog)

    DialogLoader.loaded[name] = true
    UsedPlus.logInfo(string.format("  ✓ Loaded '%s' successfully", name))
    UsedPlus.logDebug(string.format("╚═══ DialogLoader.ensureLoaded() EXIT (success) ═══"))

    return true
end

--[[
    Get dialog instance (target or direct)
    Handles the target wrapper pattern used by g_gui

    @param name - Dialog name
    @return dialog instance or nil
]]
function DialogLoader.getDialog(name)
    local guiDialog = g_gui.guis[name]
    if guiDialog == nil then
        return nil
    end

    -- g_gui wraps dialogs - get the actual instance
    if guiDialog.target ~= nil then
        return guiDialog.target
    end

    -- Direct reference (some older patterns)
    return guiDialog
end

--[[
    Show a dialog with optional data setting
    This is the main API - replaces all the scattered patterns

    @param name - Dialog name
    @param dataMethod - Optional: method name to call for setting data (e.g., "setFarmId")
    @param ... - Optional: arguments to pass to dataMethod
    @return boolean - true if dialog was shown successfully
]]
function DialogLoader.show(name, dataMethod, ...)
    UsedPlus.logInfo(string.format("╔═══ DialogLoader.show() ENTRY ═══"))
    UsedPlus.logInfo(string.format("  name: '%s'", tostring(name)))
    UsedPlus.logInfo(string.format("  dataMethod: '%s'", tostring(dataMethod)))

    -- Ensure loaded
    UsedPlus.logInfo(string.format("  → Calling ensureLoaded('%s')...", name))
    if not DialogLoader.ensureLoaded(name) then
        UsedPlus.logError(string.format("  ✗ Failed to load '%s'", name))
        UsedPlus.logError(string.format("╚═══ DialogLoader.show() EXIT (load failed) ═══"))
        return false
    end

    UsedPlus.logInfo(string.format("  ✓ Dialog loaded"))

    -- Get dialog instance
    UsedPlus.logDebug(string.format("  → Getting dialog instance from g_gui.guis..."))
    local dialog = DialogLoader.getDialog(name)
    UsedPlus.logDebug(string.format("  dialog instance: %s", tostring(dialog)))

    if dialog == nil then
        UsedPlus.logError(string.format("  ✗ '%s' not found in g_gui.guis after loading", name))
        -- Reset loaded flag so we try again next time
        DialogLoader.loaded[name] = false
        UsedPlus.logError(string.format("╚═══ DialogLoader.show() EXIT (not in g_gui) ═══"))
        return false
    end

    UsedPlus.logDebug(string.format("  ✓ Dialog instance retrieved"))

    -- Call data method if provided
    if dataMethod then
        UsedPlus.logDebug(string.format("  → Calling %s:%s()...", name, dataMethod))
        local method = dialog[dataMethod]
        if method and type(method) == "function" then
            method(dialog, ...)
            UsedPlus.logDebug(string.format("  ✓ Method called successfully"))
        else
            UsedPlus.logWarn(string.format("  ⚠ Method '%s' not found on '%s'", dataMethod, name))
        end
    end

    -- Show the dialog using showDialog() for proper ESC/close handling
    -- Standard overlay mode (works for most dialogs)
    -- Placeable dialog uses showGui() directly in BuyPlaceableDataExtension
    UsedPlus.logInfo(string.format("  → Calling g_gui:showDialog('%s')...", name))
    g_gui:showDialog(name)
    UsedPlus.logInfo(string.format("  ✓ Showed '%s' successfully", name))
    UsedPlus.logInfo(string.format("╚═══ DialogLoader.show() EXIT (success) ═══"))

    return true
end

--[[
    Check if a dialog is currently visible
    @param name - Dialog name
    @return boolean
]]
function DialogLoader.isVisible(name)
    local currentDialog = g_gui:getIsDialogVisible()
    if currentDialog and currentDialog.name == name then
        return true
    end
    return false
end

--[[
    Close a specific dialog if it's open
    @param name - Dialog name
]]
function DialogLoader.close(name)
    local dialog = DialogLoader.getDialog(name)
    if dialog and dialog.close then
        dialog:close()
    end
end

--[[
    Completely unload a dialog (remove from GUI system and mark as unloaded)
    Use this when you need to force a fresh reload of a dialog
    @param name - Dialog name
    @return boolean - true if unloaded, false if not found
]]
function DialogLoader.unload(name)
    UsedPlus.logInfo(string.format("╔═══ DialogLoader.unload() - Destroying '%s' ═══", name))

    -- Close dialog if open
    local dialog = g_gui.guis[name]
    if dialog then
        if dialog.close then
            UsedPlus.logDebug("  → Closing dialog before unload...")
            dialog:close()
        end

        -- Remove from GUI system
        UsedPlus.logDebug("  → Removing from g_gui.guis...")
        g_gui.guis[name] = nil

        -- Delete the dialog object (let Lua GC handle it)
        UsedPlus.logDebug("  → Dialog instance removed")
    else
        UsedPlus.logDebug("  → Dialog not in g_gui.guis (already unloaded?)")
    end

    -- Mark as unloaded in DialogLoader
    if DialogLoader.loaded[name] ~= nil then
        DialogLoader.loaded[name] = false
        UsedPlus.logDebug("  → Marked as unloaded in DialogLoader")
    end

    UsedPlus.logInfo(string.format("  ✓ Dialog '%s' completely unloaded", name))
    UsedPlus.logInfo("╚═══════════════════════════════════════════════════")

    return true
end

--[[
    Register all UsedPlus dialogs
    Called from main.lua after all dialog classes are loaded
]]
function DialogLoader.registerAll()
    UsedPlus.logInfo("╔════════════════════════════════════════════════════════════════")
    UsedPlus.logInfo("║ DialogLoader.registerAll() - REGISTERING ALL DIALOGS")
    UsedPlus.logInfo("╠════════════════════════════════════════════════════════════════")

    -- Finance/Loan dialogs
    if TakeLoanDialog then
        UsedPlus.logDebug("  Registering TakeLoanDialog...")
        DialogLoader.register("TakeLoanDialog", TakeLoanDialog, "gui/TakeLoanDialog.xml")
    else
        UsedPlus.logWarn("  TakeLoanDialog class not available - skipping")
    end

    if FinancialDashboard then
        DialogLoader.register("FinancialDashboard", FinancialDashboard, "gui/FinancialDashboard.xml")
    end

    if CreditReportDialog then
        DialogLoader.register("CreditReportDialog", CreditReportDialog, "gui/CreditReportDialog.xml")
    end

    if PaymentHistoryDialog then
        DialogLoader.register("PaymentHistoryDialog", PaymentHistoryDialog, "gui/PaymentHistoryDialog.xml")
    end

    if SearchDetailsDialog then
        DialogLoader.register("SearchDetailsDialog", SearchDetailsDialog, "gui/SearchDetailsDialog.xml")
    end

    -- Land dialogs
    if UnifiedLandPurchaseDialog then
        DialogLoader.register("UnifiedLandPurchaseDialog", UnifiedLandPurchaseDialog, "gui/UnifiedLandPurchaseDialog.xml")
    end

    -- Vehicle dialogs
    if RepairDialog then
        DialogLoader.register("RepairDialog", RepairDialog, "gui/RepairDialog.xml")
    end

    if RepairFinanceDialog then
        DialogLoader.register("RepairFinanceDialog", RepairFinanceDialog, "gui/RepairFinanceDialog.xml")
    end

    if SellVehicleDialog then
        DialogLoader.register("SellVehicleDialog", SellVehicleDialog, "gui/SellVehicleDialog.xml")
    end

    if SaleOfferDialog then
        DialogLoader.register("SaleOfferDialog", SaleOfferDialog, "gui/SaleOfferDialog.xml")
    end

    -- Purchase dialogs
    UsedPlus.logDebug("  ═══ PURCHASE DIALOGS ═══")
    UsedPlus.logDebug(string.format("    UnifiedPurchaseDialog class exists: %s", tostring(UnifiedPurchaseDialog ~= nil)))
    UsedPlus.logDebug(string.format("    UnifiedPurchaseDialog type: %s", type(UnifiedPurchaseDialog)))

    if UnifiedPurchaseDialog then
        UsedPlus.logInfo("  → Registering UnifiedPurchaseDialog...")
        DialogLoader.register("UnifiedPurchaseDialog", UnifiedPurchaseDialog, "gui/UnifiedPurchaseDialog.xml")

        -- v2.8.1: Placeable-specific dialog (same class, different XML layout)
        UsedPlus.logDebug("  → Registering UnifiedPurchaseDialogPlaceable...")
        DialogLoader.register("UnifiedPurchaseDialogPlaceable", UnifiedPurchaseDialog, "gui/UnifiedPurchaseDialogPlaceable.xml")
    else
        UsedPlus.logWarn("  UnifiedPurchaseDialog class not available - skipping")
    end

    if UsedSearchDialog then
        DialogLoader.register("UsedSearchDialog", UsedSearchDialog, "gui/UsedSearchDialog.xml")
    end

    -- Lease end dialogs
    if LeaseEndDialog then
        DialogLoader.register("LeaseEndDialog", LeaseEndDialog, "gui/LeaseEndDialog.xml")
    end

    if LeaseRenewalDialog then
        DialogLoader.register("LeaseRenewalDialog", LeaseRenewalDialog, "gui/LeaseRenewalDialog.xml")
    end

    -- Maintenance/Inspection dialogs (Phase 4)
    if UsedVehiclePreviewDialog then
        DialogLoader.register("UsedVehiclePreviewDialog", UsedVehiclePreviewDialog, "gui/UsedVehiclePreviewDialog.xml")
    end

    if InspectionReportDialog then
        DialogLoader.register("InspectionReportDialog", InspectionReportDialog, "gui/InspectionReportDialog.xml")
    end

    if MaintenanceReportDialog then
        DialogLoader.register("MaintenanceReportDialog", MaintenanceReportDialog, "gui/MaintenanceReportDialog.xml")
    end

    -- Tire/Fluid service dialogs
    if TiresDialog then
        DialogLoader.register("TiresDialog", TiresDialog, "gui/TiresDialog.xml")
    end

    if FluidsDialog then
        DialogLoader.register("FluidsDialog", FluidsDialog, "gui/FluidsDialog.xml")
    end

    -- v1.5.1: Search expiration dialog with renewal option
    if SearchExpiredDialog then
        DialogLoader.register("SearchExpiredDialog", SearchExpiredDialog, "gui/SearchExpiredDialog.xml")
    end

    if SearchInitiatedDialog then
        DialogLoader.register("SearchInitiatedDialog", SearchInitiatedDialog, "gui/SearchInitiatedDialog.xml")
    end

    -- v1.9.8: Repossession notification dialog
    if RepossessionDialog then
        DialogLoader.register("RepossessionDialog", RepossessionDialog, "gui/RepossessionDialog.xml")
    end

    -- v2.6.0: Negotiation dialogs
    if NegotiationDialog then
        DialogLoader.register("NegotiationDialog", NegotiationDialog, "gui/NegotiationDialog.xml")
    end

    if SellerResponseDialog then
        DialogLoader.register("SellerResponseDialog", SellerResponseDialog, "gui/SellerResponseDialog.xml")
    end

    -- v2.9.0: Service Truck Discovery dialog
    if ServiceTruckDiscoveryDialog then
        DialogLoader.register("ServiceTruckDiscoveryDialog", ServiceTruckDiscoveryDialog, "gui/ServiceTruckDiscoveryDialog.xml")
    end

    -- v2.9.5: Admin Control Panel
    if AdminControlPanel then
        DialogLoader.register("AdminControlPanel", AdminControlPanel, "gui/AdminControlPanel.xml")
    end

    -- Count registered dialogs
    local count = 0
    for dialogName, _ in pairs(DialogLoader.dialogs or {}) do
        count = count + 1
    end

    UsedPlus.logInfo(string.format("║ DialogLoader.registerAll() COMPLETE"))
    UsedPlus.logInfo(string.format("║ Total dialogs registered: %d", count))
    UsedPlus.logInfo("╚════════════════════════════════════════════════════════════════")

    -- List all registered dialogs for verification
    UsedPlus.logDebug("  Registered dialog list:")
    for dialogName, reg in pairs(DialogLoader.dialogs or {}) do
        UsedPlus.logDebug(string.format("    - '%s' → %s", dialogName, reg.xml))
    end
end

--[[
    Reset all loaded flags (for testing/reload)
]]
function DialogLoader.resetAll()
    for name, _ in pairs(DialogLoader.loaded) do
        DialogLoader.loaded[name] = false
    end
end

UsedPlus.logInfo("DialogLoader loaded")
