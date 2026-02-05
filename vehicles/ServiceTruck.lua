--[[
    FS25_UsedPlus - Service Truck Specialization

    A driveable vehicle that performs long-term restoration on other vehicles.
    Unlike OBD Scanner (instant, caps at 80%), the Service Truck:
    - Takes hours/days of game time
    - Can restore reliability to 100%
    - Can restore reliability CEILING (unique feature for lemons)
    - Consumes diesel, oil, hydraulic fluid, and spare parts
    - Immobilizes target vehicle during restoration

    Credits:
    - GMC C7000 model by Canada FS
    - ServiceVehicle pattern studied from GtX (Andy)

    v2.9.0 - Service Truck System
]]

ServiceTruck = {}
ServiceTruck.MOD_NAME = g_currentModName or "FS25_UsedPlus"

local SPEC_NAME = "spec_serviceTruck"

-- Global tracking for action events
ServiceTruck.instances = {}
ServiceTruck.actionEventId = nil
ServiceTruck.nearestTruck = nil

function ServiceTruck.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Motorized, specializations) and
           SpecializationUtil.hasSpecialization(FillUnit, specializations)
end

function ServiceTruck.initSpecialization()
    local schema = Vehicle.xmlSchema
    schema:setXMLSpecializationType("ServiceTruck")

    -- Configuration from vehicle XML
    schema:register(XMLValueType.FLOAT, "vehicle.serviceTruck.detectionRadius#value", "Radius to detect nearby vehicles", 15.0)
    schema:register(XMLValueType.FLOAT, "vehicle.serviceTruck.palletRadius#value", "Radius to detect spare parts pallets", 5.0)
    schema:register(XMLValueType.FLOAT, "vehicle.serviceTruck.consumption#diesel", "Diesel consumption per game hour", 5.0)
    schema:register(XMLValueType.FLOAT, "vehicle.serviceTruck.consumption#oil", "Oil consumption per game hour", 0.5)
    schema:register(XMLValueType.FLOAT, "vehicle.serviceTruck.consumption#hydraulic", "Hydraulic fluid consumption per game hour", 0.5)
    schema:register(XMLValueType.FLOAT, "vehicle.serviceTruck.consumption#parts", "Parts consumption per game hour", 2.0)
    schema:register(XMLValueType.FLOAT, "vehicle.serviceTruck.restoration#reliabilityPerHour", "Reliability restored per game hour", 0.01)
    schema:register(XMLValueType.FLOAT, "vehicle.serviceTruck.restoration#ceilingPerHour", "Ceiling restored per game hour", 0.0025)
    schema:register(XMLValueType.INT, "vehicle.serviceTruck.fillUnits#diesel", "Fill unit index for diesel", 2)
    schema:register(XMLValueType.INT, "vehicle.serviceTruck.fillUnits#oil", "Fill unit index for oil", 3)
    schema:register(XMLValueType.INT, "vehicle.serviceTruck.fillUnits#hydraulic", "Fill unit index for hydraulic", 4)

    -- Savegame schema
    local schemaSavegame = Vehicle.xmlSchemaSavegame
    schemaSavegame:register(XMLValueType.BOOL, "vehicles.vehicle(?).serviceTruck#isRestoring", "Is currently restoring a vehicle")
    schemaSavegame:register(XMLValueType.INT, "vehicles.vehicle(?).serviceTruck#targetVehicleId", "ID of vehicle being restored")
    schemaSavegame:register(XMLValueType.STRING, "vehicles.vehicle(?).serviceTruck#component", "Component being restored")
    schemaSavegame:register(XMLValueType.FLOAT, "vehicles.vehicle(?).serviceTruck#startReliability", "Reliability when started")
    schemaSavegame:register(XMLValueType.FLOAT, "vehicles.vehicle(?).serviceTruck#progress", "Current progress 0-1")

    schema:setXMLSpecializationType()
end

function ServiceTruck.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "findNearbyVehicles", ServiceTruck.findNearbyVehicles)
    SpecializationUtil.registerFunction(vehicleType, "findNearbyPallets", ServiceTruck.findNearbyPallets)
    SpecializationUtil.registerFunction(vehicleType, "getTargetVehicle", ServiceTruck.getTargetVehicle)
    SpecializationUtil.registerFunction(vehicleType, "startRestoration", ServiceTruck.startRestoration)
    SpecializationUtil.registerFunction(vehicleType, "stopRestoration", ServiceTruck.stopRestoration)
    SpecializationUtil.registerFunction(vehicleType, "pauseRestoration", ServiceTruck.pauseRestoration)
    SpecializationUtil.registerFunction(vehicleType, "progressRestoration", ServiceTruck.progressRestoration)
    SpecializationUtil.registerFunction(vehicleType, "consumeResources", ServiceTruck.consumeResources)
    SpecializationUtil.registerFunction(vehicleType, "consumePartsFromPallets", ServiceTruck.consumePartsFromPallets)
    SpecializationUtil.registerFunction(vehicleType, "immobilizeTarget", ServiceTruck.immobilizeTarget)
    SpecializationUtil.registerFunction(vehicleType, "releaseTarget", ServiceTruck.releaseTarget)
    SpecializationUtil.registerFunction(vehicleType, "openRestorationDialog", ServiceTruck.openRestorationDialog)
    SpecializationUtil.registerFunction(vehicleType, "getRestorationStatus", ServiceTruck.getRestorationStatus)
end

function ServiceTruck.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", ServiceTruck)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", ServiceTruck)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", ServiceTruck)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", ServiceTruck)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", ServiceTruck)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", ServiceTruck)
end

function ServiceTruck:onLoad(savegame)
    self[SPEC_NAME] = {}
    local spec = self[SPEC_NAME]

    -- Load configuration from XML
    spec.detectionRadius = self.xmlFile:getValue("vehicle.serviceTruck.detectionRadius#value", 15.0)
    spec.palletRadius = self.xmlFile:getValue("vehicle.serviceTruck.palletRadius#value", 5.0)

    -- Consumption rates per game hour
    spec.dieselRate = self.xmlFile:getValue("vehicle.serviceTruck.consumption#diesel", 5.0)
    spec.oilRate = self.xmlFile:getValue("vehicle.serviceTruck.consumption#oil", 0.5)
    spec.hydraulicRate = self.xmlFile:getValue("vehicle.serviceTruck.consumption#hydraulic", 0.5)
    spec.partsRate = self.xmlFile:getValue("vehicle.serviceTruck.consumption#parts", 2.0)

    -- Restoration rates
    spec.reliabilityPerHour = self.xmlFile:getValue("vehicle.serviceTruck.restoration#reliabilityPerHour", 0.01)
    spec.ceilingPerHour = self.xmlFile:getValue("vehicle.serviceTruck.restoration#ceilingPerHour", 0.0025)

    -- Fill unit indices
    spec.dieselFillUnit = self.xmlFile:getValue("vehicle.serviceTruck.fillUnits#diesel", 2)
    spec.oilFillUnit = self.xmlFile:getValue("vehicle.serviceTruck.fillUnits#oil", 3)
    spec.hydraulicFillUnit = self.xmlFile:getValue("vehicle.serviceTruck.fillUnits#hydraulic", 4)

    -- State tracking
    spec.nearbyVehicles = {}
    spec.targetVehicle = nil
    spec.nearbyPallets = {}

    -- Restoration state
    spec.isRestoring = false
    spec.isPaused = false
    spec.pauseReason = nil
    spec.restorationData = nil  -- {targetVehicle, component, startReliability, progress, startTime}

    -- Warning tracking
    spec.lowDieselWarned = false
    spec.lowOilWarned = false
    spec.lowHydraulicWarned = false
    spec.noPartsWarned = false

    -- Damage timer (for empty fluids)
    spec.emptyFluidTimer = 0
    spec.damageThreshold = 60 * 60 * 1000  -- 1 hour in ms = damage to target

    -- Register instance globally
    table.insert(ServiceTruck.instances, self)

    -- Load from savegame
    if savegame ~= nil and savegame.xmlFile ~= nil then
        local key = savegame.key .. ".serviceTruck"
        spec.isRestoring = savegame.xmlFile:getValue(key .. "#isRestoring", false)
        spec.savedTargetId = savegame.xmlFile:getValue(key .. "#targetVehicleId")
        spec.savedComponent = savegame.xmlFile:getValue(key .. "#component")
        spec.savedStartReliability = savegame.xmlFile:getValue(key .. "#startReliability")
        spec.savedProgress = savegame.xmlFile:getValue(key .. "#progress")
    end

    UsedPlus.logInfo("ServiceTruck loaded - Long-term vehicle restoration ready")
end

function ServiceTruck:onDelete()
    local spec = self[SPEC_NAME]
    if spec == nil then return end  -- v2.11.0: Guard against missing specialization

    -- Release any target vehicle
    if spec.restorationData ~= nil and spec.restorationData.targetVehicle ~= nil then
        self:releaseTarget(spec.restorationData.targetVehicle)
    end

    -- Remove from global instances
    for i, instance in ipairs(ServiceTruck.instances) do
        if instance == self then
            table.remove(ServiceTruck.instances, i)
            break
        end
    end

    if ServiceTruck.nearestTruck == self then
        ServiceTruck.nearestTruck = nil
    end
end

function ServiceTruck:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self[SPEC_NAME]

    xmlFile:setValue(key .. "#isRestoring", spec.isRestoring)

    if spec.restorationData ~= nil then
        local targetId = nil
        if spec.restorationData.targetVehicle ~= nil and spec.restorationData.targetVehicle.id ~= nil then
            targetId = spec.restorationData.targetVehicle.id
        end
        if targetId ~= nil then
            xmlFile:setValue(key .. "#targetVehicleId", targetId)
        end
        if spec.restorationData.component ~= nil then
            xmlFile:setValue(key .. "#component", spec.restorationData.component)
        end
        if spec.restorationData.startReliability ~= nil then
            xmlFile:setValue(key .. "#startReliability", spec.restorationData.startReliability)
        end
        if spec.restorationData.progress ~= nil then
            xmlFile:setValue(key .. "#progress", spec.restorationData.progress)
        end
    end
end

function ServiceTruck:onReadStream(streamId, connection)
    local spec = self[SPEC_NAME]
    if connection:getIsServer() then
        spec.isRestoring = streamReadBool(streamId)
        spec.isPaused = streamReadBool(streamId)
        if spec.isRestoring then
            local targetId = streamReadInt32(streamId)
            spec.savedTargetId = targetId
            spec.savedComponent = streamReadString(streamId)
            spec.savedProgress = streamReadFloat32(streamId)
        end
    end
end

function ServiceTruck:onWriteStream(streamId, connection)
    local spec = self[SPEC_NAME]
    if not connection:getIsServer() then
        streamWriteBool(streamId, spec.isRestoring)
        streamWriteBool(streamId, spec.isPaused)
        if spec.isRestoring and spec.restorationData ~= nil then
            local targetId = 0
            if spec.restorationData.targetVehicle ~= nil then
                targetId = spec.restorationData.targetVehicle.id or 0
            end
            streamWriteInt32(streamId, targetId)
            streamWriteString(streamId, spec.restorationData.component or "")
            streamWriteFloat32(streamId, spec.restorationData.progress or 0)
        end
    end
end

function ServiceTruck:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if self.isClient then
        local spec = self[SPEC_NAME]
        self:clearActionEventsTable(spec.actionEvents)

        if isActiveForInputIgnoreSelection then
            -- Use dedicated USEDPLUS_SERVICE_TRUCK action (R key) to avoid conflicts
            local _, actionEventId = self:addActionEvent(spec.actionEvents, InputAction.USEDPLUS_SERVICE_TRUCK, self, ServiceTruck.onActionActivate, false, true, false, true, nil)
            if actionEventId ~= nil then
                g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_HIGH)
                spec.actionEventId = actionEventId
                self:updateActionEventText()
            end
        end
    end
end

function ServiceTruck:updateActionEventText()
    local spec = self[SPEC_NAME]
    if spec.actionEventId == nil then return end

    local text
    if spec.isRestoring then
        if spec.isPaused then
            text = g_i18n:getText("usedplus_serviceTruck_resume") or "Resume Restoration"
        else
            text = g_i18n:getText("usedplus_serviceTruck_stop") or "Stop Restoration"
        end
    else
        if spec.targetVehicle ~= nil then
            local vehicleName = spec.targetVehicle.vehicle:getName() or "Vehicle"
            text = string.format(g_i18n:getText("usedplus_serviceTruck_inspect") or "Inspect %s", vehicleName)
        else
            text = g_i18n:getText("usedplus_serviceTruck_noTarget") or "No vehicle nearby"
        end
    end

    g_inputBinding:setActionEventText(spec.actionEventId, text)
    g_inputBinding:setActionEventActive(spec.actionEventId, true)
end

function ServiceTruck.onActionActivate(self, actionName, inputValue, callbackState, isAnalog)
    local spec = self[SPEC_NAME]

    if spec.isRestoring then
        -- Toggle pause/resume or stop
        if spec.isPaused then
            spec.isPaused = false
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO,
                g_i18n:getText("usedplus_serviceTruck_resumed") or "Restoration resumed")
        else
            self:stopRestoration(false)  -- false = don't release target, just pause
        end
    else
        -- Start inspection process
        if spec.targetVehicle ~= nil then
            self:openRestorationDialog()
        else
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO,
                g_i18n:getText("usedplus_serviceTruck_noVehicle") or "No vehicle nearby to restore")
        end
    end

    self:updateActionEventText()
end

function ServiceTruck:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self[SPEC_NAME]

    -- Reconnect saved target vehicle after load
    if spec.savedTargetId ~= nil and spec.isRestoring then
        for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles) do
            if vehicle.id == spec.savedTargetId then
                spec.restorationData = {
                    targetVehicle = vehicle,
                    component = spec.savedComponent,
                    startReliability = spec.savedStartReliability or 0,
                    progress = spec.savedProgress or 0,
                    startTime = g_currentMission.time
                }
                self:immobilizeTarget(vehicle)
                spec.savedTargetId = nil
                UsedPlus.logInfo("ServiceTruck: Reconnected to target vehicle after load")
                break
            end
        end
    end

    -- Update nearby vehicle detection
    self:findNearbyVehicles()

    -- Update nearby pallet detection
    self:findNearbyPallets()

    -- Update action text
    if isActiveForInputIgnoreSelection then
        self:updateActionEventText()
    end

    -- Process restoration if active
    if spec.isRestoring and not spec.isPaused and spec.restorationData ~= nil then
        -- Check if target vehicle still exists
        if spec.restorationData.targetVehicle == nil or spec.restorationData.targetVehicle.isDeleted then
            UsedPlus.logInfo("ServiceTruck: Target vehicle was deleted, stopping restoration")
            self:stopRestoration(true)
            return
        end

        -- Calculate time passed in game hours
        -- dt is in ms, game time scale affects actual passage
        local hoursPassed = dt / (60 * 60 * 1000)  -- Convert ms to hours

        -- Consume resources
        local hasResources = self:consumeResources(hoursPassed)

        if hasResources then
            -- Reset damage timer
            spec.emptyFluidTimer = 0

            -- Progress restoration
            self:progressRestoration(hoursPassed)
        else
            -- Resources depleted - pause and warn
            spec.emptyFluidTimer = spec.emptyFluidTimer + dt

            -- After 1 game hour of empty resources, damage target
            if spec.emptyFluidTimer >= spec.damageThreshold then
                self:damageTarget()
                spec.emptyFluidTimer = 0
            end
        end
    end
end

--[[
    Find vehicles within detection radius.
]]
function ServiceTruck:findNearbyVehicles()
    local spec = self[SPEC_NAME]
    spec.nearbyVehicles = {}
    spec.targetVehicle = nil

    if self.rootNode == nil then return end

    local x, y, z = getWorldTranslation(self.rootNode)
    local radius = spec.detectionRadius
    local radiusSq = radius * radius

    if g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil then
        for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles) do
            if vehicle ~= self and vehicle.rootNode ~= nil then
                -- Skip if vehicle doesn't have maintenance spec
                local maintSpec = vehicle.spec_usedPlusMaintenance
                if maintSpec ~= nil then
                    local vx, vy, vz = getWorldTranslation(vehicle.rootNode)
                    local distSq = (x - vx)^2 + (y - vy)^2 + (z - vz)^2

                    if distSq <= radiusSq then
                        -- Check if vehicle needs restoration
                        local needsRestoration = maintSpec.engineReliability < 0.9 or
                                                 maintSpec.electricalReliability < 0.9 or
                                                 maintSpec.hydraulicReliability < 0.9 or
                                                 (maintSpec.maxReliabilityCeiling or 1.0) < 1.0

                        -- Check if vehicle is already being restored
                        local isBeingRestored = maintSpec.isBeingRestored or false

                        table.insert(spec.nearbyVehicles, {
                            vehicle = vehicle,
                            distance = math.sqrt(distSq),
                            needsRestoration = needsRestoration,
                            isBeingRestored = isBeingRestored,
                            engineReliability = maintSpec.engineReliability or 1.0,
                            electricalReliability = maintSpec.electricalReliability or 1.0,
                            hydraulicReliability = maintSpec.hydraulicReliability or 1.0,
                            reliabilityCeiling = maintSpec.maxReliabilityCeiling or 1.0
                        })
                    end
                end
            end
        end
    end

    -- Sort by distance and pick closest that needs restoration
    table.sort(spec.nearbyVehicles, function(a, b) return a.distance < b.distance end)

    for _, entry in ipairs(spec.nearbyVehicles) do
        if entry.needsRestoration and not entry.isBeingRestored then
            spec.targetVehicle = entry
            break
        end
    end
end

--[[
    Find spare parts pallets within detection radius.
]]
function ServiceTruck:findNearbyPallets()
    local spec = self[SPEC_NAME]
    spec.nearbyPallets = {}
    spec.totalPartsAvailable = 0

    if self.rootNode == nil then return end

    local x, y, z = getWorldTranslation(self.rootNode)
    local radius = spec.palletRadius
    local radiusSq = radius * radius

    -- Check all objects in mission
    if g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil then
        for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles) do
            if vehicle ~= self and vehicle.rootNode ~= nil then
                local vx, vy, vz = getWorldTranslation(vehicle.rootNode)
                local distSq = (x - vx)^2 + (y - vy)^2 + (z - vz)^2

                if distSq <= radiusSq then
                    -- Check if this is a pallet with spare parts
                    if vehicle.getFillUnitFillLevel ~= nil and vehicle.getFillUnitFillType ~= nil then
                        local sparePartsFillType = g_fillTypeManager:getFillTypeIndexByName("USEDPLUS_SPAREPARTS")
                        if sparePartsFillType ~= nil then
                            -- Check all fill units
                            local fillUnitsSpec = vehicle.spec_fillUnit
                            if fillUnitsSpec ~= nil and fillUnitsSpec.fillUnits ~= nil then
                                for i, fillUnit in ipairs(fillUnitsSpec.fillUnits) do
                                    local level = vehicle:getFillUnitFillLevel(i)
                                    local fillType = vehicle:getFillUnitFillType(i)
                                    if fillType == sparePartsFillType and level > 0 then
                                        table.insert(spec.nearbyPallets, {
                                            vehicle = vehicle,
                                            fillUnitIndex = i,
                                            fillLevel = level,
                                            distance = math.sqrt(distSq)
                                        })
                                        spec.totalPartsAvailable = spec.totalPartsAvailable + level
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Sort by distance
    table.sort(spec.nearbyPallets, function(a, b) return a.distance < b.distance end)
end

function ServiceTruck:getTargetVehicle()
    local spec = self[SPEC_NAME]
    return spec.targetVehicle
end

--[[
    Open the restoration inspection dialog.
]]
function ServiceTruck:openRestorationDialog()
    local spec = self[SPEC_NAME]
    if spec.targetVehicle == nil then return end

    -- Ensure dialog is registered
    if ServiceTruckDialog ~= nil and ServiceTruckDialog.register ~= nil then
        ServiceTruckDialog.register()
    else
        UsedPlus.logError("ServiceTruck: ServiceTruckDialog class not found!")
        return
    end

    -- Show dialog
    local dialog = g_gui:showDialog("ServiceTruckDialog")
    if dialog ~= nil and dialog.target ~= nil then
        dialog.target:setData(spec.targetVehicle.vehicle, self)
    end
end

--[[
    Start restoration on a vehicle component.
    Called after successful inspection.
]]
function ServiceTruck:startRestoration(targetVehicle, component)
    local spec = self[SPEC_NAME]

    -- Check for spare parts
    if spec.totalPartsAvailable < spec.partsRate then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            g_i18n:getText("usedplus_serviceTruck_needParts") or "Need spare parts pallet nearby!")
        return false
    end

    -- Get current reliability for the component
    local maintSpec = targetVehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return false end

    local startReliability = 0
    if component == "engine" then
        startReliability = maintSpec.engineReliability or 0
    elseif component == "electrical" then
        startReliability = maintSpec.electricalReliability or 0
    elseif component == "hydraulic" then
        startReliability = maintSpec.hydraulicReliability or 0
    end

    -- Store restoration data
    spec.restorationData = {
        targetVehicle = targetVehicle,
        component = component,
        startReliability = startReliability,
        progress = 0,
        startTime = g_currentMission.time,
        startCeiling = maintSpec.maxReliabilityCeiling or 1.0
    }

    spec.isRestoring = true
    spec.isPaused = false

    -- Immobilize target
    self:immobilizeTarget(targetVehicle)

    -- Notification
    local vehicleName = targetVehicle:getName() or "Vehicle"
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO,
        string.format(g_i18n:getText("usedplus_serviceTruck_started") or "Started restoration of %s", vehicleName))

    UsedPlus.logInfo("ServiceTruck: Started restoration of " .. vehicleName .. " (" .. component .. ")")

    return true
end

--[[
    Stop restoration and optionally release target.
]]
function ServiceTruck:stopRestoration(releaseVehicle)
    local spec = self[SPEC_NAME]

    if spec.restorationData ~= nil then
        local targetVehicle = spec.restorationData.targetVehicle

        if releaseVehicle and targetVehicle ~= nil then
            self:releaseTarget(targetVehicle)
        end

        local vehicleName = "Vehicle"
        if targetVehicle ~= nil and targetVehicle.getName ~= nil then
            vehicleName = targetVehicle:getName()
        end

        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format(g_i18n:getText("usedplus_serviceTruck_stopped") or "Stopped restoration of %s", vehicleName))

        spec.restorationData = nil
    end

    spec.isRestoring = false
    spec.isPaused = false

    -- Reset warnings
    spec.lowDieselWarned = false
    spec.lowOilWarned = false
    spec.lowHydraulicWarned = false
    spec.noPartsWarned = false
end

--[[
    Pause restoration due to resource shortage.
]]
function ServiceTruck:pauseRestoration(reason)
    local spec = self[SPEC_NAME]
    spec.isPaused = true
    spec.pauseReason = reason

    local reasonText = g_i18n:getText("usedplus_serviceTruck_paused_" .. reason) or "Restoration paused"
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, reasonText)
end

--[[
    Consume resources during restoration.
    Returns true if all resources available, false if shortage.
]]
function ServiceTruck:consumeResources(hoursPassed)
    local spec = self[SPEC_NAME]

    -- Calculate consumption amounts
    local dieselNeeded = spec.dieselRate * hoursPassed
    local oilNeeded = spec.oilRate * hoursPassed
    local hydraulicNeeded = spec.hydraulicRate * hoursPassed
    local partsNeeded = spec.partsRate * hoursPassed

    -- Check diesel (from fill unit 2)
    local dieselLevel = self:getFillUnitFillLevel(spec.dieselFillUnit)
    if dieselLevel < dieselNeeded then
        if not spec.lowDieselWarned then
            self:pauseRestoration("diesel")
            spec.lowDieselWarned = true
        end
        return false
    end

    -- Check oil (from fill unit 3)
    local oilLevel = self:getFillUnitFillLevel(spec.oilFillUnit)
    if oilLevel < oilNeeded then
        if not spec.lowOilWarned then
            self:pauseRestoration("oil")
            spec.lowOilWarned = true
        end
        return false
    end

    -- Check hydraulic (from fill unit 4)
    local hydraulicLevel = self:getFillUnitFillLevel(spec.hydraulicFillUnit)
    if hydraulicLevel < hydraulicNeeded then
        if not spec.lowHydraulicWarned then
            self:pauseRestoration("hydraulic")
            spec.lowHydraulicWarned = true
        end
        return false
    end

    -- Check spare parts from nearby pallets
    if spec.totalPartsAvailable < partsNeeded then
        if not spec.noPartsWarned then
            self:pauseRestoration("parts")
            spec.noPartsWarned = true
        end
        return false
    end

    -- All resources available - consume them
    self:addFillUnitFillLevel(self:getOwnerFarmId(), spec.dieselFillUnit, -dieselNeeded, g_fillTypeManager:getFillTypeIndexByName("DIESEL"), ToolType.UNDEFINED, nil)
    self:addFillUnitFillLevel(self:getOwnerFarmId(), spec.oilFillUnit, -oilNeeded, g_fillTypeManager:getFillTypeIndexByName("OIL"), ToolType.UNDEFINED, nil)
    self:addFillUnitFillLevel(self:getOwnerFarmId(), spec.hydraulicFillUnit, -hydraulicNeeded, g_fillTypeManager:getFillTypeIndexByName("HYDRAULICOIL"), ToolType.UNDEFINED, nil)

    -- Consume parts from pallets
    self:consumePartsFromPallets(partsNeeded)

    -- Reset warnings
    spec.lowDieselWarned = false
    spec.lowOilWarned = false
    spec.lowHydraulicWarned = false
    spec.noPartsWarned = false

    return true
end

--[[
    Consume spare parts from nearby pallets.
]]
function ServiceTruck:consumePartsFromPallets(partsNeeded)
    local spec = self[SPEC_NAME]
    local remaining = partsNeeded

    local sparePartsFillType = g_fillTypeManager:getFillTypeIndexByName("USEDPLUS_SPAREPARTS")
    if sparePartsFillType == nil then return end

    for _, pallet in ipairs(spec.nearbyPallets) do
        if remaining <= 0 then break end

        local available = pallet.fillLevel
        local toConsume = math.min(available, remaining)

        if toConsume > 0 and pallet.vehicle.addFillUnitFillLevel ~= nil then
            pallet.vehicle:addFillUnitFillLevel(self:getOwnerFarmId(), pallet.fillUnitIndex, -toConsume, sparePartsFillType, ToolType.UNDEFINED, nil)
            remaining = remaining - toConsume
        end
    end
end

--[[
    Progress the restoration - increase reliability and ceiling.
]]
function ServiceTruck:progressRestoration(hoursPassed)
    local spec = self[SPEC_NAME]
    if spec.restorationData == nil then return end

    local targetVehicle = spec.restorationData.targetVehicle
    local component = spec.restorationData.component

    if targetVehicle == nil or targetVehicle.spec_usedPlusMaintenance == nil then return end

    local maintSpec = targetVehicle.spec_usedPlusMaintenance

    -- Calculate reliability gain
    local reliabilityGain = spec.reliabilityPerHour * hoursPassed
    local ceilingGain = spec.ceilingPerHour * hoursPassed

    -- Apply to the correct component
    if component == "engine" then
        maintSpec.engineReliability = math.min(1.0, maintSpec.engineReliability + reliabilityGain)
    elseif component == "electrical" then
        maintSpec.electricalReliability = math.min(1.0, maintSpec.electricalReliability + reliabilityGain)
    elseif component == "hydraulic" then
        maintSpec.hydraulicReliability = math.min(1.0, maintSpec.hydraulicReliability + reliabilityGain)
    end

    -- Restore ceiling (unique Service Truck feature!)
    maintSpec.maxReliabilityCeiling = math.min(1.0, (maintSpec.maxReliabilityCeiling or 1.0) + ceilingGain)

    -- Update progress
    local currentReliability = 0
    if component == "engine" then
        currentReliability = maintSpec.engineReliability
    elseif component == "electrical" then
        currentReliability = maintSpec.electricalReliability
    elseif component == "hydraulic" then
        currentReliability = maintSpec.hydraulicReliability
    end

    spec.restorationData.progress = (currentReliability - spec.restorationData.startReliability) /
                                     (1.0 - spec.restorationData.startReliability)

    -- Check for completion
    if currentReliability >= 0.99 and maintSpec.maxReliabilityCeiling >= 0.99 then
        self:completeRestoration()
    end
end

--[[
    Complete restoration successfully.
]]
function ServiceTruck:completeRestoration()
    local spec = self[SPEC_NAME]
    if spec.restorationData == nil then return end

    local targetVehicle = spec.restorationData.targetVehicle
    local vehicleName = "Vehicle"
    if targetVehicle ~= nil and targetVehicle.getName ~= nil then
        vehicleName = targetVehicle:getName()
    end

    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
        string.format(g_i18n:getText("usedplus_serviceTruck_complete") or "Restoration complete: %s", vehicleName))

    -- Release target
    if targetVehicle ~= nil then
        self:releaseTarget(targetVehicle)
    end

    spec.restorationData = nil
    spec.isRestoring = false
    spec.isPaused = false

    UsedPlus.logInfo("ServiceTruck: Completed restoration of " .. vehicleName)
end

--[[
    Damage target vehicle when resources run out for too long.
]]
function ServiceTruck:damageTarget()
    local spec = self[SPEC_NAME]
    if spec.restorationData == nil then return end

    local targetVehicle = spec.restorationData.targetVehicle
    if targetVehicle == nil or targetVehicle.spec_usedPlusMaintenance == nil then return end

    local maintSpec = targetVehicle.spec_usedPlusMaintenance
    local component = spec.restorationData.component

    -- Apply damage to component
    local damage = 0.05  -- 5% damage

    if component == "engine" then
        maintSpec.engineReliability = math.max(0, maintSpec.engineReliability - damage)
    elseif component == "electrical" then
        maintSpec.electricalReliability = math.max(0, maintSpec.electricalReliability - damage)
    elseif component == "hydraulic" then
        maintSpec.hydraulicReliability = math.max(0, maintSpec.hydraulicReliability - damage)
    end

    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
        g_i18n:getText("usedplus_serviceTruck_damage") or "Warning: Restoration damage due to empty resources!")

    UsedPlus.logInfo("ServiceTruck: Damaged target due to empty resources")
end

--[[
    Immobilize target vehicle during restoration.
]]
function ServiceTruck:immobilizeTarget(vehicle)
    if vehicle == nil then return end

    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec ~= nil then
        maintSpec.isBeingRestored = true
    end

    -- Disable engine start
    if vehicle.spec_motorized ~= nil then
        vehicle.spec_motorized.motorizedWasStarted = vehicle.spec_motorized.isMotorStarted or false
        -- Force motor stop
        if vehicle.stopMotor ~= nil then
            vehicle:stopMotor()
        end
    end

    -- TODO: Visual wheel removal could be added here if model supports it

    UsedPlus.logInfo("ServiceTruck: Immobilized target vehicle for restoration")
end

--[[
    Release target vehicle after restoration.
]]
function ServiceTruck:releaseTarget(vehicle)
    if vehicle == nil then return end

    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec ~= nil then
        maintSpec.isBeingRestored = false
    end

    -- TODO: Restore wheel visibility if changed

    UsedPlus.logInfo("ServiceTruck: Released target vehicle")
end

--[[
    Get current restoration status for UI display.
]]
function ServiceTruck:getRestorationStatus()
    local spec = self[SPEC_NAME]

    if not spec.isRestoring or spec.restorationData == nil then
        return nil
    end

    local targetVehicle = spec.restorationData.targetVehicle
    local vehicleName = "Unknown"
    if targetVehicle ~= nil and targetVehicle.getName ~= nil then
        vehicleName = targetVehicle:getName()
    end

    local maintSpec = targetVehicle and targetVehicle.spec_usedPlusMaintenance
    local currentReliability = 0
    if maintSpec ~= nil then
        local component = spec.restorationData.component
        if component == "engine" then
            currentReliability = maintSpec.engineReliability
        elseif component == "electrical" then
            currentReliability = maintSpec.electricalReliability
        elseif component == "hydraulic" then
            currentReliability = maintSpec.hydraulicReliability
        end
    end

    return {
        vehicleName = vehicleName,
        component = spec.restorationData.component,
        progress = spec.restorationData.progress,
        currentReliability = currentReliability,
        isPaused = spec.isPaused,
        pauseReason = spec.pauseReason,
        dieselLevel = self:getFillUnitFillLevel(spec.dieselFillUnit),
        oilLevel = self:getFillUnitFillLevel(spec.oilFillUnit),
        hydraulicLevel = self:getFillUnitFillLevel(spec.hydraulicFillUnit),
        partsAvailable = spec.totalPartsAvailable
    }
end
