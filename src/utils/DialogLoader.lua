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
    DialogLoader.dialogs[name] = {
        class = dialogClass,
        xml = xmlPath
    }
    DialogLoader.loaded[name] = false
end

--[[
    Ensure a dialog is loaded (lazy loading)
    Returns true if dialog is ready to use

    @param name - Dialog name
    @return boolean - true if loaded successfully
]]
function DialogLoader.ensureLoaded(name)
    -- Already loaded?
    if DialogLoader.loaded[name] then
        return true
    end

    -- Check if already loaded by another mechanism (getInstance(), etc.)
    if g_gui and g_gui.guis and g_gui.guis[name] then
        DialogLoader.loaded[name] = true
        return true
    end

    -- Get registration
    local registration = DialogLoader.dialogs[name]

    if not registration then
        UsedPlus.logError(string.format("Dialog '%s' not registered", name))
        return false
    end

    -- Load the dialog
    local dialogClass = registration.class
    local xmlPath = UsedPlus.MOD_DIR .. registration.xml

    if not dialogClass then
        UsedPlus.logError(string.format("Dialog class for '%s' is nil", name))
        return false
    end

    local dialog = dialogClass.new(nil, nil, g_i18n)
    g_gui:loadGui(xmlPath, name, dialog)

    -- Verify the load actually succeeded (g_gui:loadGui silently fails)
    if g_gui.guis[name] ~= nil then
        DialogLoader.loaded[name] = true
        UsedPlus.logInfo(string.format("Loaded dialog '%s'", name))
        return true
    else
        UsedPlus.logError(string.format("g_gui:loadGui() failed for '%s' - XML file may be inaccessible", name))
        DialogLoader.loaded[name] = false
        return false
    end
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
    -- Ensure loaded
    if not DialogLoader.ensureLoaded(name) then
        UsedPlus.logError(string.format("Failed to load dialog '%s'", name))
        return false
    end

    -- Get dialog instance
    local dialog = DialogLoader.getDialog(name)

    if dialog == nil then
        UsedPlus.logError(string.format("'%s' not found in g_gui.guis after loading", name))
        -- Reset loaded flag so we try again next time
        DialogLoader.loaded[name] = false
        return false
    end

    -- Call data method if provided
    if dataMethod then
        local method = dialog[dataMethod]
        if method and type(method) == "function" then
            method(dialog, ...)
        else
            UsedPlus.logWarn(string.format("Method '%s' not found on '%s'", dataMethod, name))
        end
    end

    -- Show the dialog using showDialog() for proper ESC/close handling
    g_gui:showDialog(name)

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
        DialogLoader.register("TakeLoanDialog", TakeLoanDialog, "gui/TakeLoanDialog.xml")
    end

    if LoanApprovedDialog then
        DialogLoader.register("LoanApprovedDialog", LoanApprovedDialog, "gui/LoanApprovedDialog.xml")
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

    if DealDetailsDialog then
        DialogLoader.register("DealDetailsDialog", DealDetailsDialog, "gui/DealDetailsDialog.xml")
    end

    if SearchDetailsDialog then
        DialogLoader.register("SearchDetailsDialog", SearchDetailsDialog, "gui/SearchDetailsDialog.xml")
    end

    if SaleListingDetailsDialog then
        DialogLoader.register("SaleListingDetailsDialog", SaleListingDetailsDialog, "gui/SaleListingDetailsDialog.xml")
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
    if UnifiedPurchaseDialog then
        DialogLoader.register("UnifiedPurchaseDialog", UnifiedPurchaseDialog, "gui/UnifiedPurchaseDialog.xml")
        -- v2.8.1: Placeable-specific dialog (same class, different XML layout)
        DialogLoader.register("UnifiedPurchaseDialogPlaceable", UnifiedPurchaseDialog, "gui/UnifiedPurchaseDialogPlaceable.xml")
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

    if VehiclePortfolioDialog then
        DialogLoader.register("VehiclePortfolioDialog", VehiclePortfolioDialog, "gui/VehiclePortfolioDialog.xml")
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

    if SaleExpiredDialog then
        DialogLoader.register("SaleExpiredDialog", SaleExpiredDialog, "gui/SaleExpiredDialog.xml")
    end

    if SearchInitiatedDialog then
        DialogLoader.register("SearchInitiatedDialog", SearchInitiatedDialog, "gui/SearchInitiatedDialog.xml")
    end

    if SaleListingInitiatedDialog then
        DialogLoader.register("SaleListingInitiatedDialog", SaleListingInitiatedDialog, "gui/SaleListingInitiatedDialog.xml")
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

    -- v2.11.1: Fault Tracer minigame dialog
    if FaultTracerDialog then
        DialogLoader.register("FaultTracerDialog", FaultTracerDialog, "gui/FaultTracerDialog.xml")
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

    -- Eagerly load all dialogs now while the zip file handle is valid
    -- This prevents failures when dialogs are first used later (e.g., if the
    -- zip is replaced by a rebuild or modified by OneDrive sync during gameplay)
    UsedPlus.logInfo("╔═══ DialogLoader: Eagerly loading all dialogs ═══")
    local loaded = 0
    local failed = 0
    for dialogName, _ in pairs(DialogLoader.dialogs) do
        if not DialogLoader.loaded[dialogName] then
            if DialogLoader.ensureLoaded(dialogName) then
                loaded = loaded + 1
            else
                failed = failed + 1
            end
        else
            loaded = loaded + 1
        end
    end
    UsedPlus.logInfo(string.format("║ Eager load complete: %d loaded, %d failed", loaded, failed))
    UsedPlus.logInfo("╚═════════════════════════════════════════════════")
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
