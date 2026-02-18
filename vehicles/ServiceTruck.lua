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
    v2.12.0 - Fault Tracer on-foot detection (RVB pattern)
]]

ServiceTruck = {}
ServiceTruck.MOD_NAME = g_currentModName or "FS25_UsedPlus"

local SPEC_NAME = "spec_serviceTruck"

-- Global tracking for action events
ServiceTruck.instances = {}
ServiceTruck.actionEventId = nil
ServiceTruck.nearestTruck = nil
ServiceTruck.faultTracerActionEventId = nil  -- v2.12.0: On-foot Fault Tracer

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
    SpecializationUtil.registerFunction(vehicleType, "updateActionEventText", ServiceTruck.updateActionEventText)
    SpecializationUtil.registerFunction(vehicleType, "completeRestoration", ServiceTruck.completeRestoration)
    SpecializationUtil.registerFunction(vehicleType, "damageTarget", ServiceTruck.damageTarget)
    SpecializationUtil.registerFunction(vehicleType, "openFaultTracerDialog", ServiceTruck.openFaultTracerDialog)
    SpecializationUtil.registerFunction(vehicleType, "loadDieselTankVisual", ServiceTruck.loadDieselTankVisual)
    SpecializationUtil.registerFunction(vehicleType, "loadViseVisual", ServiceTruck.loadViseVisual)
    SpecializationUtil.registerFunction(vehicleType, "loadToolboxVisual", ServiceTruck.loadToolboxVisual)
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

    -- Action events
    spec.actionEvents = {}

    -- State tracking
    spec.nearbyVehicles = {}
    spec.targetVehicle = nil
    spec.faultTracerTarget = nil  -- v2.12.0: Any vehicle with maintenance spec (for Fault Tracer)
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

    -- Load diesel tank visual on truck bed (battery is in i3d directly)
    self:loadDieselTankVisual()
    -- Load cast iron vise on truck bed
    self:loadViseVisual()
    -- Load Superduty toolbox on truck bed
    self:loadToolboxVisual()

    UsedPlus.logInfo("ServiceTruck loaded - Long-term vehicle restoration ready")
end

--[[
    Load the diesel transfer tank 3D model and attach it to the truck bed.
    Uses the SmallFuelTank model (FS25_Small_fuel_tank), scaled and positioned
    on the right rear of the service bed.
]]
function ServiceTruck:loadDieselTankVisual()
    local spec = self[SPEC_NAME]

    local tankPath = Utils.getFilename("vehicles/serviceTruck/dieselTank/Smallfueltank.i3d", self.baseDirectory)
    local tankScene = g_i3DManager:loadSharedI3DFile(tankPath, false, false, false)

    if tankScene == nil or tankScene == 0 then
        UsedPlus.logError("ServiceTruck: Failed to load diesel tank model from: " .. tostring(tankPath))
        return
    end

    -- Navigate to visual mesh: root > "Small fuel tank" > visuals (index 7) > fuelTank (index 0)
    local tankRoot = getChildAt(tankScene, 0)
    local visualsNode = getChildAt(tankRoot, 7)

    if visualsNode == nil then
        UsedPlus.logError("ServiceTruck: Could not find visuals node in diesel tank i3d")
        delete(tankScene)
        return
    end

    local tankMesh = getChildAt(visualsNode, 0)
    if tankMesh == nil then
        UsedPlus.logError("ServiceTruck: Could not find fuelTank mesh in diesel tank i3d")
        delete(tankScene)
        return
    end

    -- Clone the visual mesh so we can delete the source scene
    local clonedTank = clone(tankMesh, true)

    -- Find the serviceVehicle (truck bed) node: 0>0|19
    local bedNode = I3DUtil.indexToObject(self.components, "0>0|19")
    if bedNode == nil then
        UsedPlus.logError("ServiceTruck: Could not find truck bed node (0>0|19)")
        delete(clonedTank)
        delete(tankScene)
        return
    end

    -- Link tank to truck bed
    link(bedNode, clonedTank)

    -- Position on center-rear of bed, sitting on the bed floor
    -- Bed floor Y ≈ 1.08 (matches oilTank, hydraulicTank, deco items)
    -- Bed extends roughly Z=-0.8 to Z=-4.2, center around Z=-2.5
    setTranslation(clonedTank, -0.24, 0.52, -3.5)

    -- Rotate 90° clockwise (viewed from above) to sit lengthwise on the bed
    setRotation(clonedTank, 0, -math.pi / 2, 0)

    -- Scale down to fit truck bed (original model is ~1.4m wide × 2.2m tall × 1.4m deep)
    -- At 0.45 scale: ~0.65m wide × 1.0m tall × 0.62m deep
    setScale(clonedTank, 0.648, 0.81, 0.648)

    -- Store reference for cleanup
    spec.dieselTankVisualNode = clonedTank

    -- Hide the battery charger deco (makes room for the diesel tank)
    -- deco_batteryCharger is child index 5 of serviceVehicle (0>0|19|5)
    local batteryChargerNode = I3DUtil.indexToObject(self.components, "0>0|19|5")
    if batteryChargerNode ~= nil then
        setVisibility(batteryChargerNode, false)
        UsedPlus.logDebug("ServiceTruck: Hid battery charger deco to make room for diesel tank")
    end

    -- Clean up loaded scene (cloned nodes survive)
    delete(tankScene)

    UsedPlus.logInfo("ServiceTruck: Diesel transfer tank loaded on truck bed")
end

--[[
    Load the cast iron bench vise from base game assets and attach it to the truck bed.
    Uses $data/maps/mapUS/textures/props/vintageTools/castIronVise.i3d
]]
function ServiceTruck:loadViseVisual()
    local spec = self[SPEC_NAME]

    -- Load the entire bootGross i3d which contains the castIronVise with textures
    -- The vise uses $data/ textures so no extra files needed beyond the i3d+shapes
    local visePath = Utils.getFilename("vehicles/serviceTruck/vise/id_bootGross.i3d", self.baseDirectory)
    local viseScene = g_i3DManager:loadSharedI3DFile(visePath, false, false, false)
    if viseScene == nil or viseScene == 0 then
        UsedPlus.logError("ServiceTruck: Failed to load vise model from: " .. tostring(visePath))
        return
    end

    -- Navigate to castIronVise LOD0 by index path:
    -- root(0) > id_bootGross > visuals(5) > LOD0(0) > Gamerstube(0) >
    -- sailingMotorBoatOnTheTable(0) > workBench_PREFAB(4) > castIronVise(1) > LOD0(0)
    local root = getChildAt(viseScene, 0)           -- id_bootGross
    local visuals = getChildAt(root, 5)             -- visuals
    local lod0Group = getChildAt(visuals, 0)        -- LOD0
    local gamerstube = getChildAt(lod0Group, 0)     -- Gamerstube_8/5
    local prefab = getChildAt(gamerstube, 0)        -- sailingMotorBoatOnTheTable_PREFAB
    local workBenchPrefab = getChildAt(prefab, 4)   -- workBench_PREFAB
    local viseNode = getChildAt(workBenchPrefab, 1) -- castIronVise
    local viseLod0 = getChildAt(viseNode, 0)        -- LOD0 shape

    if viseLod0 == nil then
        UsedPlus.logError("ServiceTruck: Could not navigate to castIronVise LOD0 in bootGross i3d")
        delete(viseScene)
        return
    end

    local clonedVise = clone(viseLod0, true)

    local bedNode = I3DUtil.indexToObject(self.components, "0>0|19")
    if bedNode == nil then
        UsedPlus.logError("ServiceTruck: Could not find truck bed node for vise")
        delete(clonedVise)
        delete(viseScene)
        return
    end

    link(bedNode, clonedVise)

    -- Position on rear of bed, near the tailgate area
    -- Negative X = right side (away from sidewall tools), negative Z = toward rear
    setTranslation(clonedVise, -1.25, 1.02, -3.725)
    setRotation(clonedVise, 0, math.pi, 0)
    setScale(clonedVise, 0.5, 1.0, 1.0)

    spec.viseVisualNode = clonedVise

    delete(viseScene)
    UsedPlus.logInfo("ServiceTruck: Cast iron vise loaded on truck bed")
end

--[[
    Load the portable toolbox from MobileServiceKit and attach to truck bed.
    Uses toolboxWorkshop.i3d — all textures are $data/ (base game), no local files needed.
]]
function ServiceTruck:loadToolboxVisual()
    local spec = self[SPEC_NAME]

    local tbPath = Utils.getFilename("vehicles/serviceTruck/toolbox/toolboxWorkshop.i3d", self.baseDirectory)
    local tbScene = g_i3DManager:loadSharedI3DFile(tbPath, false, false, false)
    if tbScene == nil or tbScene == 0 then
        UsedPlus.logError("ServiceTruck: Failed to load toolbox model from: " .. tostring(tbPath))
        return
    end

    -- Navigate to toolbox_viz by index path:
    -- root(0) > toolBoxWorkshopMainComponent > visible(3) > toolbox_viz(0)
    local root = getChildAt(tbScene, 0)       -- toolBoxWorkshopMainComponent
    local visible = getChildAt(root, 3)       -- visible TransformGroup
    local toolboxViz = getChildAt(visible, 0) -- toolbox_viz Shape

    if toolboxViz == nil then
        UsedPlus.logError("ServiceTruck: Could not navigate to toolbox_viz in toolboxWorkshop i3d")
        delete(tbScene)
        return
    end

    local clonedToolbox = clone(toolboxViz, true)

    local bedNode = I3DUtil.indexToObject(self.components, "0>0|19")
    if bedNode == nil then
        UsedPlus.logError("ServiceTruck: Could not find truck bed node for toolbox")
        delete(clonedToolbox)
        delete(tbScene)
        return
    end

    link(bedNode, clonedToolbox)

    -- Position on rear of bed near diesel tank and battery area
    setTranslation(clonedToolbox, -1.0, 1.08, -3.0)
    setRotation(clonedToolbox, 0, math.pi / 2, 0)
    setScale(clonedToolbox, 1.0, 1.0, 1.0)
    setVisibility(clonedToolbox, true)

    spec.toolboxVisualNode = clonedToolbox

    delete(tbScene)
    UsedPlus.logInfo("ServiceTruck: Portable toolbox loaded on truck bed")
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

    -- Clean up diesel tank visual
    if spec.dieselTankVisualNode ~= nil then
        delete(spec.dieselTankVisualNode)
        spec.dieselTankVisualNode = nil
    end

    -- Clean up vise visual
    if spec.viseVisualNode ~= nil then
        delete(spec.viseVisualNode)
        spec.viseVisualNode = nil
    end

    -- Clean up toolbox visual
    if spec.toolboxVisualNode ~= nil then
        delete(spec.toolboxVisualNode)
        spec.toolboxVisualNode = nil
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
    local active = true

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
            -- No target vehicle and no restoration — hide the action event
            -- so it doesn't block Oil Service Point or other activatables
            text = ""
            active = false
        end
    end

    g_inputBinding:setActionEventText(spec.actionEventId, text)
    g_inputBinding:setActionEventActive(spec.actionEventId, active)
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
        end
    end

    self:updateActionEventText()
end

function ServiceTruck:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self[SPEC_NAME]

    -- v2.12.0: Keep updating for on-foot detection (same pattern as FieldServiceKit)
    self:raiseActive()

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

    -- Update action text (in-vehicle R key)
    if isActiveForInputIgnoreSelection then
        self:updateActionEventText()
    end

    -- v2.12.0: On-foot player proximity detection for Fault Tracer
    local playerNearby = false
    local playerDistance = 999999
    local activationRadius = 3.0  -- meters (slightly larger than OBD Scanner's 2.5m)
    local isOnFoot = false

    if self.rootNode ~= nil and g_localPlayer ~= nil then
        isOnFoot = true
        if g_localPlayer.getIsInVehicle ~= nil then
            isOnFoot = not g_localPlayer:getIsInVehicle()
        end
        if g_currentMission.controlledVehicle ~= nil then
            isOnFoot = false
        end

        if isOnFoot then
            local tx, ty, tz = getWorldTranslation(self.rootNode)
            local px, py, pz
            if g_localPlayer.getPosition ~= nil then
                px, py, pz = g_localPlayer:getPosition()
            elseif g_localPlayer.rootNode ~= nil then
                px, py, pz = getWorldTranslation(g_localPlayer.rootNode)
            end

            if px ~= nil then
                playerDistance = MathUtil.vector2Length(tx - px, tz - pz)
                playerNearby = playerDistance <= activationRadius
            end
        end
    end

    -- Track nearest truck for Fault Tracer action event
    if playerNearby then
        local currentNearest = ServiceTruck.nearestTruck
        if currentNearest == nil or currentNearest == self then
            ServiceTruck.nearestTruck = self
        else
            -- Check if we're closer
            local currentSpec = currentNearest[SPEC_NAME]
            if currentSpec == nil or playerDistance < (currentSpec.playerDistance or 999999) then
                ServiceTruck.nearestTruck = self
            end
        end
    else
        if ServiceTruck.nearestTruck == self then
            ServiceTruck.nearestTruck = nil
        end
    end
    spec.playerDistance = playerDistance

    -- Update Fault Tracer action event visibility
    -- Uses faultTracerTarget (any vehicle with maintenance spec), not targetVehicle (needs restoration)
    -- Only shows when sidebar doors are open (door_service animation > 50%)
    if ServiceTruck.faultTracerActionEventId ~= nil and g_inputBinding ~= nil then
        local hasTarget = (spec.faultTracerTarget ~= nil)
        local doorsOpen = false
        if self.getAnimationTime ~= nil then
            doorsOpen = self:getAnimationTime("door_service") > 0.5
        end
        local shouldShow = playerNearby and isOnFoot and hasTarget and doorsOpen and ServiceTruck.nearestTruck == self

        if shouldShow then
            local vehicleName = spec.faultTracerTarget.vehicle:getName() or "Vehicle"
            local promptText = string.format(g_i18n:getText("usedplus_ft_action") or "Fault Tracer: %s", vehicleName)

            g_inputBinding:setActionEventTextPriority(ServiceTruck.faultTracerActionEventId, GS_PRIO_VERY_HIGH)
            g_inputBinding:setActionEventTextVisibility(ServiceTruck.faultTracerActionEventId, true)
            g_inputBinding:setActionEventActive(ServiceTruck.faultTracerActionEventId, true)
            g_inputBinding:setActionEventText(ServiceTruck.faultTracerActionEventId, promptText)
        else
            g_inputBinding:setActionEventTextVisibility(ServiceTruck.faultTracerActionEventId, false)
            g_inputBinding:setActionEventActive(ServiceTruck.faultTracerActionEventId, false)
        end
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
    spec.faultTracerTarget = nil

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

    -- v2.12.0: Track closest diagnosable vehicle for Fault Tracer (any with maintenance spec)
    -- The Fault Tracer can diagnose any vehicle, not just ones needing restoration.
    -- The dialog handles showing "system healthy" for components >=90%.
    if #spec.nearbyVehicles > 0 then
        spec.faultTracerTarget = spec.nearbyVehicles[1]
    else
        spec.faultTracerTarget = nil
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

-- ============================================================
-- v2.12.0: Fault Tracer - On-Foot Activation (RVB Pattern)
-- ============================================================

--[[
    Open the Fault Tracer dialog for a target vehicle.
    Called from the on-foot action event callback.
]]
function ServiceTruck:openFaultTracerDialog()
    local spec = self[SPEC_NAME]
    if spec.faultTracerTarget == nil then return end

    -- Check fluid levels before opening
    local oilLevel = self:getFillUnitFillLevel(spec.oilFillUnit) or 0
    local hydLevel = self:getFillUnitFillLevel(spec.hydraulicFillUnit) or 0

    if oilLevel < 1.0 and hydLevel < 1.0 then
        InfoDialog.show("Cannot start Fault Tracer: Service Truck has no oil or hydraulic fluid. Refill both tanks before diagnosing.")
        return
    elseif oilLevel < 1.0 then
        InfoDialog.show("Cannot start Fault Tracer: Service Truck oil tank is empty. Refill oil before diagnosing.")
        return
    elseif hydLevel < 1.0 then
        InfoDialog.show("Cannot start Fault Tracer: Service Truck hydraulic fluid tank is empty. Refill hydraulic fluid before diagnosing.")
        return
    end

    local targetVehicle = spec.faultTracerTarget.vehicle
    DialogLoader.show("FaultTracerDialog", "setData", targetVehicle, self)
end

--[[
    Callback when Fault Tracer action key is pressed (RVB pattern).
]]
function ServiceTruck.faultTracerCallback(self, actionName, inputValue, callbackState, isAnalog)
    if inputValue <= 0 then return end

    local truck = ServiceTruck.nearestTruck
    if truck ~= nil then
        local spec = truck[SPEC_NAME]
        if spec ~= nil and spec.faultTracerTarget ~= nil then
            UsedPlus.logInfo("ServiceTruck: Fault Tracer activated for " .. (spec.faultTracerTarget.vehicle:getName() or "Vehicle"))
            truck:openFaultTracerDialog()
        end
    end
end

--[[
    Hook PlayerInputComponent.registerActionEvents for on-foot Fault Tracer.
    Follows exact RVB pattern from FieldServiceKit v2.0.7.
]]
ServiceTruck.originalRegisterActionEventsForFT = nil

function ServiceTruck.hookPlayerInputComponentForFaultTracer()
    if ServiceTruck.originalRegisterActionEventsForFT ~= nil then
        return  -- Already hooked
    end

    if PlayerInputComponent == nil or PlayerInputComponent.registerActionEvents == nil then
        UsedPlus.logWarn("ServiceTruck: PlayerInputComponent.registerActionEvents not available for Fault Tracer")
        return
    end

    -- Store current function (may already be hooked by FieldServiceKit)
    ServiceTruck.originalRegisterActionEventsForFT = PlayerInputComponent.registerActionEvents

    -- Replace with our version
    PlayerInputComponent.registerActionEvents = function(inputComponent, ...)
        -- Call previous (chains with FieldServiceKit hook)
        ServiceTruck.originalRegisterActionEventsForFT(inputComponent, ...)

        -- Add Fault Tracer action (RVB pattern)
        if inputComponent.player ~= nil and inputComponent.player.isOwner then
            local actionId = InputAction.USEDPLUS_FAULT_TRACER
            if actionId == nil then
                UsedPlus.logWarn("ServiceTruck: InputAction.USEDPLUS_FAULT_TRACER not found")
                return
            end

            g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)

            local success, eventId = g_inputBinding:registerActionEvent(
                actionId,
                ServiceTruck,
                ServiceTruck.faultTracerCallback,
                false,   -- triggerUp
                true,    -- triggerDown
                false,   -- triggerAlways
                false,   -- startActive
                nil,     -- callbackState
                true     -- disableConflictingBindings
            )

            g_inputBinding:endActionEventsModification()

            if success and eventId ~= nil then
                ServiceTruck.faultTracerActionEventId = eventId
                UsedPlus.logInfo("ServiceTruck: Fault Tracer action event registered (RVB pattern)")
            else
                UsedPlus.logWarn("ServiceTruck: Failed to register Fault Tracer action event")
            end
        end
    end

    UsedPlus.logInfo("ServiceTruck: PlayerInputComponent hooked for Fault Tracer (v2.12.0)")
end

-- Install hook when this file loads
ServiceTruck.hookPlayerInputComponentForFaultTracer()
