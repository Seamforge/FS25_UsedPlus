--[[
    FS25_UsedPlus - Oil Service Point Placeable Specialization

    Dual-interaction oil service system using distance-based detection:
    1. Player on foot within range - Purchase oil to fill tank storage
    2. Vehicle within range - Refill engine oil / hydraulic fluid from storage

    Pattern from: Fuel tank placeables, activatable objects

    v1.9.3 - Custom dialog UX with MultiTextOption dropdown
]]

OilServicePoint = {}
OilServicePoint.MOD_NAME = g_currentModName or "FS25_UsedPlus"

-- Default values
OilServicePoint.DEFAULT_STORAGE_CAPACITY = 500  -- Liters
OilServicePoint.DEFAULT_OIL_PRICE_PER_LITER = 5  -- Cost to purchase oil
OilServicePoint.DEFAULT_LITERS_PER_OIL_CHANGE = 10  -- Liters consumed per vehicle refill
OilServicePoint.DEFAULT_OIL_COST_MULTIPLIER = 0.01  -- 1% of vehicle value for oil
OilServicePoint.DEFAULT_HYDRAULIC_COST_MULTIPLIER = 0.008  -- 0.8% of vehicle value for hydraulic
OilServicePoint.DEFAULT_PLAYER_RANGE = 3.0  -- meters for player interaction
OilServicePoint.DEFAULT_VEHICLE_RANGE = 5.0  -- meters for vehicle interaction

-- Specialization registration
function OilServicePoint.prerequisitesPresent(specializations)
    return true
end

function OilServicePoint.registerFunctions(placeableType)
    SpecializationUtil.registerFunction(placeableType, "isPlayerInRange", OilServicePoint.isPlayerInRange)
    SpecializationUtil.registerFunction(placeableType, "getVehicleInRange", OilServicePoint.getVehicleInRange)
    SpecializationUtil.registerFunction(placeableType, "canRefillOil", OilServicePoint.canRefillOil)
    SpecializationUtil.registerFunction(placeableType, "canRefillHydraulic", OilServicePoint.canRefillHydraulic)
    SpecializationUtil.registerFunction(placeableType, "getOilRefillCost", OilServicePoint.getOilRefillCost)
    SpecializationUtil.registerFunction(placeableType, "getHydraulicRefillCost", OilServicePoint.getHydraulicRefillCost)
    SpecializationUtil.registerFunction(placeableType, "refillOil", OilServicePoint.refillOil)
    SpecializationUtil.registerFunction(placeableType, "refillHydraulic", OilServicePoint.refillHydraulic)
    SpecializationUtil.registerFunction(placeableType, "purchaseFluid", OilServicePoint.purchaseFluid)
    SpecializationUtil.registerFunction(placeableType, "getStorageLevel", OilServicePoint.getStorageLevel)
    SpecializationUtil.registerFunction(placeableType, "getStorageCapacity", OilServicePoint.getStorageCapacity)
    SpecializationUtil.registerFunction(placeableType, "getFluidType", OilServicePoint.getFluidType)
    SpecializationUtil.registerFunction(placeableType, "getInteractionPosition", OilServicePoint.getInteractionPosition)
    SpecializationUtil.registerFunction(placeableType, "updatePlayerActions", OilServicePoint.updatePlayerActions)
    SpecializationUtil.registerFunction(placeableType, "updateVehicleActions", OilServicePoint.updateVehicleActions)
    SpecializationUtil.registerFunction(placeableType, "fillServiceTruckTank", OilServicePoint.fillServiceTruckTank)
    SpecializationUtil.registerFunction(placeableType, "getOilLitersNeeded", OilServicePoint.getOilLitersNeeded)
    SpecializationUtil.registerFunction(placeableType, "getHydraulicLitersNeeded", OilServicePoint.getHydraulicLitersNeeded)
end

function OilServicePoint.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onLoad", OilServicePoint)
    SpecializationUtil.registerEventListener(placeableType, "onDelete", OilServicePoint)
    SpecializationUtil.registerEventListener(placeableType, "onUpdate", OilServicePoint)
    SpecializationUtil.registerEventListener(placeableType, "saveToXMLFile", OilServicePoint)
    SpecializationUtil.registerEventListener(placeableType, "onReadStream", OilServicePoint)
    SpecializationUtil.registerEventListener(placeableType, "onWriteStream", OilServicePoint)
end

function OilServicePoint.registerXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("OilServicePoint")
    -- Interaction nodes (for position reference)
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".oilServicePoint#interactionNode", "Node for interaction position (player/vehicle)")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".oilServicePoint#playerTriggerNode", "Legacy: Player trigger node (used for position)")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".oilServicePoint#vehicleTriggerNode", "Legacy: Vehicle trigger node")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".oilServicePoint#triggerNode", "Legacy: Single trigger node")

    -- Range settings
    schema:register(XMLValueType.FLOAT, basePath .. ".oilServicePoint#playerRange", "Range for player interaction (meters)", OilServicePoint.DEFAULT_PLAYER_RANGE)
    schema:register(XMLValueType.FLOAT, basePath .. ".oilServicePoint#vehicleRange", "Range for vehicle interaction (meters)", OilServicePoint.DEFAULT_VEHICLE_RANGE)

    -- Storage settings
    schema:register(XMLValueType.FLOAT, basePath .. ".oilServicePoint#storageCapacity", "Storage capacity in liters", OilServicePoint.DEFAULT_STORAGE_CAPACITY)
    schema:register(XMLValueType.FLOAT, basePath .. ".oilServicePoint#oilPricePerLiter", "Cost per liter to purchase oil", OilServicePoint.DEFAULT_OIL_PRICE_PER_LITER)
    schema:register(XMLValueType.FLOAT, basePath .. ".oilServicePoint#litersPerOilChange", "Liters consumed per full oil change", OilServicePoint.DEFAULT_LITERS_PER_OIL_CHANGE)

    -- Cost multipliers
    schema:register(XMLValueType.FLOAT, basePath .. ".oilServicePoint#oilCostMultiplier", "Cost multiplier for oil refill", OilServicePoint.DEFAULT_OIL_COST_MULTIPLIER)
    schema:register(XMLValueType.FLOAT, basePath .. ".oilServicePoint#hydraulicCostMultiplier", "Cost multiplier for hydraulic fluid refill", OilServicePoint.DEFAULT_HYDRAULIC_COST_MULTIPLIER)

    -- Mode settings
    schema:register(XMLValueType.BOOL, basePath .. ".oilServicePoint#useFillableStorage", "If true, uses storage system. If false, infinite supply.", true)
    schema:setXMLSpecializationType()
end

-- v2.11.1: Removed registerSavegameXMLPaths - PlaceableEmployer pattern uses
-- setFloat/setString/getFloat/getString which bypass schema validation entirely.
-- Schema registration at module load time was unreliable (Placeable.xmlSchemaSavegame
-- may be nil) and caused "Path not registered" errors that blocked data persistence.

function OilServicePoint:onLoad(savegame)
    local spec = self.spec_oilServicePoint
    if spec == nil then
        self.spec_oilServicePoint = {}
        spec = self.spec_oilServicePoint
    end

    local xmlFile = self.xmlFile

    -- Get interaction node (try multiple options)
    spec.interactionNode = xmlFile:getValue("placeable.oilServicePoint#interactionNode", nil, self.components, self.i3dMappings)
    if spec.interactionNode == nil then
        spec.interactionNode = xmlFile:getValue("placeable.oilServicePoint#playerTriggerNode", nil, self.components, self.i3dMappings)
    end
    if spec.interactionNode == nil then
        spec.interactionNode = xmlFile:getValue("placeable.oilServicePoint#triggerNode", nil, self.components, self.i3dMappings)
    end
    if spec.interactionNode == nil and self.rootNode ~= nil then
        spec.interactionNode = self.rootNode
        UsedPlus.logDebug("OilServicePoint: Using rootNode as interaction point")
    end

    -- Range settings
    spec.playerRange = xmlFile:getValue("placeable.oilServicePoint#playerRange", OilServicePoint.DEFAULT_PLAYER_RANGE)
    spec.vehicleRange = xmlFile:getValue("placeable.oilServicePoint#vehicleRange", OilServicePoint.DEFAULT_VEHICLE_RANGE)

    -- Storage settings
    spec.storageCapacity = xmlFile:getValue("placeable.oilServicePoint#storageCapacity", OilServicePoint.DEFAULT_STORAGE_CAPACITY)
    spec.oilPricePerLiter = xmlFile:getValue("placeable.oilServicePoint#oilPricePerLiter", OilServicePoint.DEFAULT_OIL_PRICE_PER_LITER)
    spec.litersPerOilChange = xmlFile:getValue("placeable.oilServicePoint#litersPerOilChange", OilServicePoint.DEFAULT_LITERS_PER_OIL_CHANGE)

    -- Cost multipliers
    spec.oilCostMultiplier = xmlFile:getValue("placeable.oilServicePoint#oilCostMultiplier", OilServicePoint.DEFAULT_OIL_COST_MULTIPLIER)
    spec.hydraulicCostMultiplier = xmlFile:getValue("placeable.oilServicePoint#hydraulicCostMultiplier", OilServicePoint.DEFAULT_HYDRAULIC_COST_MULTIPLIER)

    -- Mode
    spec.useFillableStorage = xmlFile:getValue("placeable.oilServicePoint#useFillableStorage", true)

    -- Current storage - tracks fluid TYPE and amount
    -- fluidType: "oil", "hydraulic", or nil (empty)
    spec.currentFluidType = nil
    spec.currentFluidStorage = 0

    -- Update throttling
    spec.activationTimer = 0
    spec.updateInterval = 200 -- ms between updates

    -- Activatable tracking (to avoid duplicates)
    spec.playerPurchaseActivatable = nil  -- Single activatable for purchase dialog
    spec.vehicleRefillActivatable = nil

    -- Action text
    spec.purchaseFluidsText = g_i18n:getText("usedplus_fluid_purchaseAction") or "Purchase Fluids"
    spec.refillOilText = g_i18n:getText("usedplus_oil_refillAction") or "Refill Engine Oil"
    spec.refillHydraulicText = g_i18n:getText("usedplus_hydraulic_refillAction") or "Refill Hydraulic Fluid"

    -- Fluid type display names
    spec.fluidNames = {
        oil = g_i18n:getText("usedplus_fluid_oil") or "Engine Oil",
        hydraulic = g_i18n:getText("usedplus_fluid_hydraulic") or "Hydraulic Fluid"
    }

    -- Load from savegame (v2.11.1: use getFloat/getString like PlaceableEmployer pattern)
    -- savegame.key = "placeables.placeable(N)" (bare path)
    -- Must add MOD_NAME.SpecName to match the key used in saveToXMLFile
    if savegame ~= nil and savegame.xmlFile ~= nil then
        local key = savegame.key .. "." .. OilServicePoint.MOD_NAME .. ".OilServicePoint"
        spec.currentFluidStorage = savegame.xmlFile:getFloat(key .. "#currentFluidStorage", 0) or 0
        spec.currentFluidType = savegame.xmlFile:getString(key .. "#currentFluidType", nil)
        UsedPlus.logInfo(string.format("OilServicePoint: Savegame load key='%s', storage=%.1f, type=%s",
            key, spec.currentFluidStorage or 0, tostring(spec.currentFluidType)))
    end

    -- Log
    local nodeInfo = spec.interactionNode and tostring(spec.interactionNode) or "none"
    UsedPlus.logInfo(string.format("OilServicePoint loaded (Storage Mode - %.0fL capacity, $%.2f/L, node: %s, range: %.1fm player / %.1fm vehicle)",
        spec.storageCapacity, spec.oilPricePerLiter, nodeInfo, spec.playerRange, spec.vehicleRange))

    -- Request updates - placeables need this to receive onUpdate calls
    self:raiseActive()
end

function OilServicePoint:onDelete()
    local spec = self.spec_oilServicePoint
    if spec == nil then return end

    -- Clean up activatables
    if spec.playerPurchaseActivatable ~= nil then
        g_currentMission.activatableObjectsSystem:removeActivatable(spec.playerPurchaseActivatable)
        spec.playerPurchaseActivatable = nil
    end
    if spec.vehicleRefillActivatable ~= nil then
        g_currentMission.activatableObjectsSystem:removeActivatable(spec.vehicleRefillActivatable)
        spec.vehicleRefillActivatable = nil
    end
end

--[[
    Save storage state
    v2.11.1: Use setFloat/setString (PlaceableEmployer pattern) instead of setValue
    which requires schema registration. This bypasses schema validation entirely.
]]
function OilServicePoint:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_oilServicePoint
    if spec == nil then return end

    -- key already = "placeables.placeable(N).FS25_UsedPlus.OilServicePoint"
    -- Just append attributes directly (no extra .oilServicePoint!)
    xmlFile:setFloat(key .. "#currentFluidStorage", spec.currentFluidStorage or 0)
    if spec.currentFluidType then
        xmlFile:setString(key .. "#currentFluidType", spec.currentFluidType)
    end
    UsedPlus.logInfo(string.format("OilServicePoint: Saved %.1fL of %s (key=%s)",
        spec.currentFluidStorage or 0, tostring(spec.currentFluidType), key))
end

--[[
    Get the world position of the interaction point
]]
function OilServicePoint:getInteractionPosition()
    local spec = self.spec_oilServicePoint
    if spec == nil then return 0, 0, 0 end

    if spec.interactionNode ~= nil then
        return getWorldTranslation(spec.interactionNode)
    end

    -- Fallback to placeable position
    if self.rootNode ~= nil then
        return getWorldTranslation(self.rootNode)
    end

    return 0, 0, 0
end

--[[
    Check if player (on foot) is within range
    Uses g_localPlayer which is the standard FS25 way to access the local player
    Pattern from: FS25_gameplay_Real_Vehicle_Breakdowns/rvbPlaceableChargingStation.lua
]]
function OilServicePoint:isPlayerInRange()
    local spec = self.spec_oilServicePoint
    if spec == nil then return false end

    -- Use g_localPlayer - the standard FS25 player reference
    if g_localPlayer == nil then
        return false
    end

    -- KEY CHECK: Use getIsInVehicle() - the proper FS25 API to check if player is in a vehicle
    -- Pattern from: FS25_gameplay_Real_Vehicle_Breakdowns/rvbPlaceableChargingStation.lua line 81
    if g_localPlayer.getIsInVehicle ~= nil and g_localPlayer:getIsInVehicle() then
        -- Player is in a vehicle, not on foot
        return false
    end

    -- Fallback check using controlledVehicle in case getIsInVehicle doesn't exist
    local controlledVehicle = g_currentMission.controlledVehicle
    if controlledVehicle ~= nil then
        -- Player is controlling a vehicle - not on foot
        return false
    end

    -- Get placeable position
    local px, py, pz = self:getInteractionPosition()

    -- Get player position using g_localPlayer methods
    local playerX, playerY, playerZ
    if g_localPlayer.getPosition ~= nil then
        playerX, playerY, playerZ = g_localPlayer:getPosition()
    elseif g_localPlayer.rootNode ~= nil then
        playerX, playerY, playerZ = getWorldTranslation(g_localPlayer.rootNode)
    else
        return false
    end

    if playerX == nil then
        return false
    end

    -- Calculate distance (ignore Y for more forgiving detection)
    local dist = MathUtil.vector2Length(px - playerX, pz - playerZ)

    return dist <= spec.playerRange
end

--[[
    Get vehicle in range that needs service
    Pattern from: FS25_gameplay_Real_Vehicle_Breakdowns/rvbPlaceableChargingStation.lua line 82
]]
function OilServicePoint:getVehicleInRange()
    local spec = self.spec_oilServicePoint
    if spec == nil then return nil end

    -- Get controlled vehicle - try g_localPlayer:getCurrentVehicle() first (more reliable)
    local controlledVehicle = nil

    if g_localPlayer ~= nil then
        -- Check if player is in a vehicle
        if g_localPlayer.getIsInVehicle ~= nil and g_localPlayer:getIsInVehicle() then
            if g_localPlayer.getCurrentVehicle ~= nil then
                controlledVehicle = g_localPlayer:getCurrentVehicle()
            end
        end
    end

    -- Fallback to g_currentMission.controlledVehicle
    if controlledVehicle == nil then
        controlledVehicle = g_currentMission.controlledVehicle
    end

    if controlledVehicle == nil then
        return nil
    end

    -- Check if vehicle has our maintenance spec or is a Service Truck
    if controlledVehicle.spec_usedPlusMaintenance == nil and controlledVehicle.spec_serviceTruck == nil then
        return nil
    end

    -- Get positions
    local px, py, pz = self:getInteractionPosition()

    if controlledVehicle.rootNode == nil then
        return nil
    end

    local vx, vy, vz = getWorldTranslation(controlledVehicle.rootNode)

    -- Calculate distance
    local dist = MathUtil.vector2Length(px - vx, pz - vz)

    if dist <= spec.vehicleRange then
        return controlledVehicle
    end

    return nil
end

function OilServicePoint:onUpdate(dt)
    local spec = self.spec_oilServicePoint
    if spec == nil then return end

    -- v2.7.1: Safety check - ensure onLoad has completed initialization
    if spec.updateInterval == nil then
        return
    end

    -- Keep requesting updates
    self:raiseActive()

    -- Throttle updates
    spec.activationTimer = (spec.activationTimer or 0) + dt
    if spec.activationTimer < spec.updateInterval then
        return
    end
    spec.activationTimer = 0

    -- Trace-level debug: log every few seconds (only visible when DEBUG=true and log level includes TRACE)
    spec.debugTimer = (spec.debugTimer or 0) + spec.updateInterval
    if spec.debugTimer >= 3000 then
        spec.debugTimer = 0

        -- Get local player vehicle status using new API
        local isInVehicle = false
        local currentVehicle = nil
        local vehicleName = "none"

        if g_localPlayer ~= nil then
            if g_localPlayer.getIsInVehicle ~= nil then
                isInVehicle = g_localPlayer:getIsInVehicle()
            end
            if isInVehicle and g_localPlayer.getCurrentVehicle ~= nil then
                currentVehicle = g_localPlayer:getCurrentVehicle()
                if currentVehicle ~= nil then
                    vehicleName = currentVehicle:getName() or "unnamed"
                end
            end
        end

        -- Fallback check
        local missionVehicle = g_currentMission.controlledVehicle
        if currentVehicle == nil and missionVehicle ~= nil then
            currentVehicle = missionVehicle
            vehicleName = missionVehicle:getName() or "unnamed"
            isInVehicle = true
        end

        -- Check our detection functions
        local playerInRange = self:isPlayerInRange()
        local vehicleInRange = self:getVehicleInRange()

        -- Extra debug for vehicle maintenance
        local vehicleOilInfo = "N/A"
        if currentVehicle ~= nil then
            local maintSpec = currentVehicle.spec_usedPlusMaintenance
            if maintSpec then
                vehicleOilInfo = string.format("oil=%.0f%%, hasMaint=true", (maintSpec.oilLevel or 1.0) * 100)
            else
                vehicleOilInfo = "hasMaint=FALSE (no maintenance spec!)"
            end
        end

        -- Calculate distance to interaction point
        local px, py, pz = self:getInteractionPosition()
        local distInfo = "N/A"
        if currentVehicle ~= nil and currentVehicle.rootNode ~= nil then
            local vx, vy, vz = getWorldTranslation(currentVehicle.rootNode)
            local dist = MathUtil.vector2Length(px - vx, pz - vz)
            distInfo = string.format("%.1fm (range=%.1f)", dist, spec.vehicleRange)
        end

        -- Activatable status
        local hasPurchaseAct = spec.playerPurchaseActivatable ~= nil
        local hasVehicleAct = spec.vehicleRefillActivatable ~= nil

        -- Tank status
        local tankInfo = "empty"
        if spec.currentFluidStorage > 0 and spec.currentFluidType then
            tankInfo = string.format("%.0fL %s", spec.currentFluidStorage, spec.currentFluidType)
        end

        UsedPlus.logTrace(string.format("OilServicePoint: isInVehicle=%s (%s), playerInRange=%s, vehicleInRange=%s, dist=%s, tank=%s, %s, acts=[purchase=%s, veh=%s]",
            tostring(isInVehicle),
            vehicleName,
            tostring(playerInRange),
            vehicleInRange and "yes" or "no",
            distInfo,
            tankInfo,
            vehicleOilInfo,
            tostring(hasPurchaseAct),
            tostring(hasVehicleAct)))
    end

    -- Check for player on foot
    if self:isPlayerInRange() then
        self:updatePlayerActions()
    else
        -- Player left range - remove activatable
        if spec.playerPurchaseActivatable ~= nil then
            g_currentMission.activatableObjectsSystem:removeActivatable(spec.playerPurchaseActivatable)
            spec.playerPurchaseActivatable = nil
        end
    end

    -- Check for vehicle
    local vehicle = self:getVehicleInRange()
    if vehicle ~= nil then
        self:updateVehicleActions(vehicle)
    else
        -- Vehicle left range - remove activatable
        if spec.vehicleRefillActivatable ~= nil then
            g_currentMission.activatableObjectsSystem:removeActivatable(spec.vehicleRefillActivatable)
            spec.vehicleRefillActivatable = nil
        end
    end
end

--[[
    Update player actions (purchase fluids)
    Shows single "Purchase Fluids" activatable that opens a dialog
]]
function OilServicePoint:updatePlayerActions()
    local spec = self.spec_oilServicePoint
    if spec == nil then return end

    -- Calculate space available
    local spaceAvailable = spec.storageCapacity - spec.currentFluidStorage

    -- Build action text
    local actionText = spec.purchaseFluidsText or "Purchase Fluids"

    -- Show tank status in the action text
    if spec.currentFluidStorage > 0 and spec.currentFluidType then
        local fluidName = spec.fluidNames[spec.currentFluidType] or spec.currentFluidType
        actionText = string.format("%s [%s: %.0f/%.0fL]",
            actionText,
            fluidName,
            spec.currentFluidStorage,
            spec.storageCapacity)
    elseif spaceAvailable <= 0 then
        actionText = "Tank Full!"
    else
        actionText = string.format("%s [Empty - %.0fL capacity]",
            actionText,
            spec.storageCapacity)
    end

    -- Create or update the single activatable
    if spec.playerPurchaseActivatable == nil then
        spec.playerPurchaseActivatable = FluidPurchaseActivatable.new(self, actionText)
        g_currentMission.activatableObjectsSystem:addActivatable(spec.playerPurchaseActivatable)
    else
        spec.playerPurchaseActivatable.activateText = actionText
    end
end

--[[
    Update vehicle actions (refill from tank)
    Only shows refill action if tank has fluid AND vehicle needs that type
]]
function OilServicePoint:updateVehicleActions(vehicle)
    local spec = self.spec_oilServicePoint
    if spec == nil then return end

    -- Check what we can refill based on tank contents
    local canRefill = false
    local refillType = nil
    local actionText = nil
    local hasEnough = false

    if spec.currentFluidStorage > 0 and spec.currentFluidType then
        -- Tank has fluid - check if vehicle needs this type

        -- 1) PRIORITY: Check Service Truck fill unit tanks first (work-critical storage)
        -- These are large tanks (200L) used for restoration - always prioritize over
        -- small maintenance top-ups that would otherwise steal the action
        local truckSpec = vehicle.spec_serviceTruck
        if truckSpec ~= nil and vehicle.getFillUnitFillLevel ~= nil and vehicle.getFillUnitCapacity ~= nil then
            local fillUnit = nil
            local fillTypeName = nil
            local fluidLabel = nil

            if spec.currentFluidType == "oil" and truckSpec.oilFillUnit then
                fillUnit = truckSpec.oilFillUnit
                fillTypeName = "OIL"
                fluidLabel = spec.fluidNames["oil"] or "Engine Oil"
            elseif spec.currentFluidType == "hydraulic" and truckSpec.hydraulicFillUnit then
                fillUnit = truckSpec.hydraulicFillUnit
                fillTypeName = "HYDRAULICOIL"
                fluidLabel = spec.fluidNames["hydraulic"] or "Hydraulic Fluid"
            end

            if fillUnit then
                local currentLevel = vehicle:getFillUnitFillLevel(fillUnit) or 0
                local capacity = vehicle:getFillUnitCapacity(fillUnit) or 0
                local spaceInTruck = capacity - currentLevel

                if spaceInTruck > 0.5 then
                    canRefill = true
                    refillType = "serviceTruck"
                    local transferAmount = math.min(spaceInTruck, spec.currentFluidStorage)
                    hasEnough = true

                    actionText = string.format("Fill %s Tank (%.0f/%.0fL → +%.0fL)",
                        fluidLabel, currentLevel, capacity, transferAmount)
                end
            end
        end

        -- 2) Fallback: Check maintenance-level oil/hydraulic needs (regular vehicles or if truck tanks are full)
        if not canRefill then
            if spec.currentFluidType == "oil" and self:canRefillOil(vehicle) then
                canRefill = true
                refillType = "oil"
                local litersNeeded = self:getOilLitersNeeded(vehicle)
                hasEnough = spec.currentFluidStorage >= litersNeeded

                if hasEnough then
                    actionText = string.format("%s (%.1fL from tank)",
                        spec.refillOilText, litersNeeded)
                else
                    actionText = string.format("%s - Need %.1fL, tank has %.1fL",
                        spec.refillOilText, litersNeeded, spec.currentFluidStorage)
                end
            elseif spec.currentFluidType == "hydraulic" and self:canRefillHydraulic(vehicle) then
                canRefill = true
                refillType = "hydraulic"
                local litersNeeded = self:getHydraulicLitersNeeded(vehicle)
                hasEnough = spec.currentFluidStorage >= litersNeeded

                if hasEnough then
                    actionText = string.format("%s (%.1fL from tank)",
                        spec.refillHydraulicText, litersNeeded)
                else
                    actionText = string.format("%s - Need %.1fL, tank has %.1fL",
                        spec.refillHydraulicText, litersNeeded, spec.currentFluidStorage)
                end
            end
        end
    end

    -- If tank is empty or wrong fluid type, show info message
    if not canRefill then
        -- Check if vehicle needs anything (maintenance or Service Truck tanks)
        local needsOil = self:canRefillOil(vehicle)
        local needsHydraulic = self:canRefillHydraulic(vehicle)

        -- Also check Service Truck tanks
        local truckSpec = vehicle.spec_serviceTruck
        if truckSpec ~= nil and vehicle.getFillUnitFillLevel ~= nil and vehicle.getFillUnitCapacity ~= nil then
            if truckSpec.oilFillUnit then
                local lvl = vehicle:getFillUnitFillLevel(truckSpec.oilFillUnit) or 0
                local cap = vehicle:getFillUnitCapacity(truckSpec.oilFillUnit) or 0
                if cap - lvl > 0.5 then needsOil = true end
            end
            if truckSpec.hydraulicFillUnit then
                local lvl = vehicle:getFillUnitFillLevel(truckSpec.hydraulicFillUnit) or 0
                local cap = vehicle:getFillUnitCapacity(truckSpec.hydraulicFillUnit) or 0
                if cap - lvl > 0.5 then needsHydraulic = true end
            end
        end

        if needsOil or needsHydraulic then
            local neededType = needsOil and "oil" or "hydraulic"
            local neededName = spec.fluidNames[neededType] or neededType

            if spec.currentFluidStorage <= 0 then
                actionText = string.format("Tank Empty - Purchase %s first", neededName)
            elseif spec.currentFluidType ~= neededType then
                local tankFluid = spec.fluidNames[spec.currentFluidType] or spec.currentFluidType
                actionText = string.format("Tank has %s - Vehicle needs %s", tankFluid, neededName)
            end

            -- Show info activatable (not actionable)
            if actionText then
                if spec.vehicleRefillActivatable == nil then
                    spec.vehicleRefillActivatable = FluidRefillActivatable.new(self, vehicle, nil, actionText, false)
                    g_currentMission.activatableObjectsSystem:addActivatable(spec.vehicleRefillActivatable)
                else
                    spec.vehicleRefillActivatable.vehicle = vehicle
                    spec.vehicleRefillActivatable.fluidType = nil
                    spec.vehicleRefillActivatable.canActivate = false
                    spec.vehicleRefillActivatable.activateText = actionText
                end
                return
            end
        end

        -- No action needed - remove activatable
        if spec.vehicleRefillActivatable ~= nil then
            g_currentMission.activatableObjectsSystem:removeActivatable(spec.vehicleRefillActivatable)
            spec.vehicleRefillActivatable = nil
        end
        return
    end

    -- Can refill - create/update activatable
    if not hasEnough then
        if refillType == "oil" then
            hasEnough = spec.currentFluidStorage >= self:getOilLitersNeeded(vehicle)
        elseif refillType == "hydraulic" then
            hasEnough = spec.currentFluidStorage >= self:getHydraulicLitersNeeded(vehicle)
        end
    end

    if spec.vehicleRefillActivatable == nil then
        spec.vehicleRefillActivatable = FluidRefillActivatable.new(self, vehicle, refillType, actionText, hasEnough)
        g_currentMission.activatableObjectsSystem:addActivatable(spec.vehicleRefillActivatable)
    else
        spec.vehicleRefillActivatable.vehicle = vehicle
        spec.vehicleRefillActivatable.fluidType = refillType
        spec.vehicleRefillActivatable.canActivate = hasEnough
        spec.vehicleRefillActivatable.activateText = actionText
    end
end

--[[
    Check if vehicle needs oil refill
]]
function OilServicePoint:canRefillOil(vehicle)
    if vehicle == nil then return false end

    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return false end

    local oilLevel = maintSpec.oilLevel or 1.0
    return oilLevel < 0.99
end

--[[
    Check if vehicle needs hydraulic fluid refill
]]
function OilServicePoint:canRefillHydraulic(vehicle)
    if vehicle == nil then return false end

    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return false end

    local hydraulicLevel = maintSpec.hydraulicFluidLevel or 1.0
    return hydraulicLevel < 0.99
end

--[[
    Get liters of oil needed for vehicle
]]
function OilServicePoint:getOilLitersNeeded(vehicle)
    local spec = self.spec_oilServicePoint
    if spec == nil or vehicle == nil then return 0 end

    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return 0 end

    local oilNeeded = (1.0 - (maintSpec.oilLevel or 1.0)) * spec.litersPerOilChange
    return oilNeeded
end

--[[
    Get liters of hydraulic fluid needed for vehicle
]]
function OilServicePoint:getHydraulicLitersNeeded(vehicle)
    local spec = self.spec_oilServicePoint
    if spec == nil or vehicle == nil then return 0 end

    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return 0 end

    -- Use same liters as oil for now (could be configured separately)
    local hydraulicNeeded = (1.0 - (maintSpec.hydraulicFluidLevel or 1.0)) * spec.litersPerOilChange
    return hydraulicNeeded
end

--[[
    Calculate oil refill cost based on vehicle value
]]
function OilServicePoint:getOilRefillCost(vehicle)
    local spec = self.spec_oilServicePoint
    if spec == nil or vehicle == nil then return 0 end

    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return 0 end

    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local basePrice = 10000
    if storeItem then
        basePrice = StoreItemUtil.getDefaultPrice(storeItem, vehicle.configurations) or storeItem.price or 10000
    end

    local oilNeeded = 1.0 - (maintSpec.oilLevel or 1.0)
    local cost = basePrice * spec.oilCostMultiplier * oilNeeded

    return math.max(1, math.floor(cost))
end

--[[
    Calculate hydraulic fluid refill cost
]]
function OilServicePoint:getHydraulicRefillCost(vehicle)
    local spec = self.spec_oilServicePoint
    if spec == nil or vehicle == nil then return 0 end

    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return 0 end

    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local basePrice = 10000
    if storeItem then
        basePrice = StoreItemUtil.getDefaultPrice(storeItem, vehicle.configurations) or storeItem.price or 10000
    end

    local hydraulicNeeded = 1.0 - (maintSpec.hydraulicFluidLevel or 1.0)
    local cost = basePrice * spec.hydraulicCostMultiplier * hydraulicNeeded

    return math.max(1, math.floor(cost))
end

--[[
    Get current storage level
]]
function OilServicePoint:getStorageLevel()
    local spec = self.spec_oilServicePoint
    if spec == nil then return 0 end
    return spec.currentFluidStorage
end

--[[
    Get current fluid type
]]
function OilServicePoint:getFluidType()
    local spec = self.spec_oilServicePoint
    if spec == nil then return nil end
    return spec.currentFluidType
end

--[[
    Get storage capacity
]]
function OilServicePoint:getStorageCapacity()
    local spec = self.spec_oilServicePoint
    if spec == nil then return 0 end
    return spec.storageCapacity
end

--[[
    Purchase fluid (player action) - adds fluid to storage
    fluidType: "oil" or "hydraulic"
    amount: liters to purchase
]]
function OilServicePoint:purchaseFluid(fluidType, amount, noEventSend)
    UsedPlus.logDebug(string.format("OilServicePoint:purchaseFluid - START: type=%s, amount=%s", tostring(fluidType), tostring(amount)))

    local spec = self.spec_oilServicePoint
    if spec == nil then
        UsedPlus.logError("OilServicePoint:purchaseFluid - spec_oilServicePoint is nil!")
        return false
    end

    UsedPlus.logDebug(string.format("OilServicePoint:purchaseFluid - spec found: storage=%.0f/%.0f, type=%s",
        spec.currentFluidStorage or 0, spec.storageCapacity or 0, tostring(spec.currentFluidType)))

    -- Validate fluid type
    if fluidType ~= "oil" and fluidType ~= "hydraulic" then
        UsedPlus.logError("OilServicePoint:purchaseFluid - Invalid fluid type: " .. tostring(fluidType))
        return false
    end

    UsedPlus.logDebug("OilServicePoint:purchaseFluid - Fluid type valid, getting farmId...")

    local farmId = g_currentMission:getFarmId()
    UsedPlus.logDebug("OilServicePoint:purchaseFluid - farmId=" .. tostring(farmId))

    -- Check if tank has different fluid type
    if spec.currentFluidStorage > 0 and spec.currentFluidType ~= nil and spec.currentFluidType ~= fluidType then
        local currentFluidName = spec.fluidNames[spec.currentFluidType] or spec.currentFluidType
        local newFluidName = spec.fluidNames[fluidType] or fluidType
        g_currentMission:showBlinkingWarning(
            string.format("Tank contains %s! Empty it first to add %s.", currentFluidName, newFluidName),
            2000
        )
        return false
    end

    UsedPlus.logDebug("OilServicePoint:purchaseFluid - Fluid type check passed")

    -- Check space
    local spaceAvailable = spec.storageCapacity - spec.currentFluidStorage
    UsedPlus.logDebug("OilServicePoint:purchaseFluid - spaceAvailable=" .. tostring(spaceAvailable))

    if spaceAvailable <= 0 then
        g_currentMission:showBlinkingWarning(g_i18n:getText("usedplus_fluid_storageFull") or "Tank is full!", 2000)
        return false
    end

    -- Adjust amount to fit
    local actualAmount = math.min(amount, spaceAvailable)
    local cost = actualAmount * spec.oilPricePerLiter
    UsedPlus.logDebug(string.format("OilServicePoint:purchaseFluid - actualAmount=%.0f, cost=%.0f, pricePerLiter=%.2f",
        actualAmount, cost, spec.oilPricePerLiter or 0))

    -- Check money
    local currentMoney = g_currentMission:getMoney(farmId)
    UsedPlus.logDebug(string.format("OilServicePoint:purchaseFluid - currentMoney=%.0f, cost=%.0f", currentMoney or 0, cost))

    if currentMoney < cost then
        g_currentMission:showBlinkingWarning(g_i18n:getText("usedplus_warning_notEnoughMoney") or "Not enough money!", 2000)
        return false
    end

    UsedPlus.logDebug("OilServicePoint:purchaseFluid - Money check passed, deducting...")

    -- Deduct money (use OTHER since PURCHASE_MATERIALS doesn't exist in FS25)
    g_currentMission:addMoney(-cost, farmId, MoneyType.OTHER, true, true)
    UsedPlus.logDebug("OilServicePoint:purchaseFluid - Money deducted")

    -- Add to storage and set type
    spec.currentFluidStorage = spec.currentFluidStorage + actualAmount
    spec.currentFluidType = fluidType
    UsedPlus.logDebug(string.format("OilServicePoint:purchaseFluid - Storage updated: %.0f/%.0f, type=%s",
        spec.currentFluidStorage, spec.storageCapacity, spec.currentFluidType))

    -- Get display name
    local fluidName = spec.fluidNames[fluidType] or fluidType
    UsedPlus.logDebug("OilServicePoint:purchaseFluid - fluidName=" .. tostring(fluidName))

    -- Confirmation
    local msg = string.format(g_i18n:getText("usedplus_fluid_purchased") or "Purchased %.0fL of %s - %s (Tank: %.0f/%.0fL)",
        actualAmount,
        fluidName,
        g_i18n:formatMoney(cost, 0, true, true),
        spec.currentFluidStorage,
        spec.storageCapacity)
    UsedPlus.logDebug("OilServicePoint:purchaseFluid - Showing confirmation: " .. msg)

    g_currentMission:showBlinkingWarning(msg, 2000)

    UsedPlus.logInfo(string.format("OilServicePoint: Purchased %.0fL of %s for %s (%.0f/%.0fL)",
        actualAmount, fluidType, g_i18n:formatMoney(cost), spec.currentFluidStorage, spec.storageCapacity))

    UsedPlus.logDebug("OilServicePoint:purchaseFluid - SUCCESS, returning true")
    return true
end

--[[
    Refill oil (vehicle action) - uses fluid from storage tank
]]
function OilServicePoint:refillOil(vehicle, noEventSend)
    if vehicle == nil then return false end

    local spec = self.spec_oilServicePoint
    if spec == nil then return false end

    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return false end

    local vehicleName = vehicle:getName() or "Vehicle"

    -- STORAGE MODE - consume from tank
    local oilNeeded = self:getOilLitersNeeded(vehicle)

    -- Check if tank has oil
    if spec.currentFluidType ~= "oil" then
        local fluidName = spec.currentFluidType and spec.fluidNames[spec.currentFluidType] or "nothing"
        g_currentMission:showBlinkingWarning(
            string.format("Tank contains %s, not Engine Oil!", fluidName),
            2000
        )
        return false
    end

    if spec.currentFluidStorage < oilNeeded then
        g_currentMission:showBlinkingWarning(
            string.format(g_i18n:getText("usedplus_fluid_notEnoughStorage") or "Not enough fluid! Need %.1fL, have %.1fL",
                oilNeeded, spec.currentFluidStorage),
            2000
        )
        return false
    end

    -- Consume from storage
    spec.currentFluidStorage = spec.currentFluidStorage - oilNeeded

    -- Clear fluid type if empty
    if spec.currentFluidStorage <= 0 then
        spec.currentFluidStorage = 0
        spec.currentFluidType = nil
    end

    -- Set oil to 100%
    maintSpec.oilLevel = 1.0

    -- Clear leak
    if maintSpec.hasOilLeak then
        maintSpec.hasOilLeak = false
    end

    -- Confirmation
    g_currentMission:showBlinkingWarning(
        string.format(g_i18n:getText("usedplus_oil_refillCompleteStorage") or "Engine oil refilled - %.1fL used (%.1fL remaining)",
            oilNeeded, spec.currentFluidStorage),
        2000
    )

    UsedPlus.logInfo(string.format("OilServicePoint: Refilled oil for %s, used %.1fL (%.1fL left)",
        vehicleName, oilNeeded, spec.currentFluidStorage))

    return true
end

--[[
    Refill hydraulic fluid (vehicle action) - uses fluid from storage tank
]]
function OilServicePoint:refillHydraulic(vehicle, noEventSend)
    if vehicle == nil then return false end

    local spec = self.spec_oilServicePoint
    if spec == nil then return false end

    local maintSpec = vehicle.spec_usedPlusMaintenance
    if maintSpec == nil then return false end

    local vehicleName = vehicle:getName() or "Vehicle"

    -- STORAGE MODE - consume from tank
    local hydraulicNeeded = self:getHydraulicLitersNeeded(vehicle)

    -- Check if tank has hydraulic fluid
    if spec.currentFluidType ~= "hydraulic" then
        local fluidName = spec.currentFluidType and spec.fluidNames[spec.currentFluidType] or "nothing"
        g_currentMission:showBlinkingWarning(
            string.format("Tank contains %s, not Hydraulic Fluid!", fluidName),
            2000
        )
        return false
    end

    if spec.currentFluidStorage < hydraulicNeeded then
        g_currentMission:showBlinkingWarning(
            string.format(g_i18n:getText("usedplus_fluid_notEnoughStorage") or "Not enough fluid! Need %.1fL, have %.1fL",
                hydraulicNeeded, spec.currentFluidStorage),
            2000
        )
        return false
    end

    -- Consume from storage
    spec.currentFluidStorage = spec.currentFluidStorage - hydraulicNeeded

    -- Clear fluid type if empty
    if spec.currentFluidStorage <= 0 then
        spec.currentFluidStorage = 0
        spec.currentFluidType = nil
    end

    -- Set hydraulic to 100%
    maintSpec.hydraulicFluidLevel = 1.0

    -- Clear leak
    if maintSpec.hasHydraulicLeak then
        maintSpec.hasHydraulicLeak = false
    end

    -- Confirmation
    g_currentMission:showBlinkingWarning(
        string.format(g_i18n:getText("usedplus_hydraulic_refillCompleteStorage") or "Hydraulic fluid refilled - %.1fL used (%.1fL remaining)",
            hydraulicNeeded, spec.currentFluidStorage),
        2000
    )

    UsedPlus.logInfo(string.format("OilServicePoint: Refilled hydraulic for %s, used %.1fL (%.1fL left)",
        vehicleName, hydraulicNeeded, spec.currentFluidStorage))

    return true
end

--[[
    Fill a Service Truck's storage tank from the oil service point storage.
    Transfers fluid from the point's storage into the truck's fill unit.
]]
function OilServicePoint:fillServiceTruckTank(vehicle)
    if vehicle == nil then return false end

    local spec = self.spec_oilServicePoint
    if spec == nil then return false end

    local truckSpec = vehicle.spec_serviceTruck
    if truckSpec == nil then return false end

    local vehicleName = vehicle:getName() or "Service Truck"

    -- Determine which fill unit to target
    local fillUnit = nil
    local fillTypeName = nil
    local fluidLabel = nil

    if spec.currentFluidType == "oil" and truckSpec.oilFillUnit then
        fillUnit = truckSpec.oilFillUnit
        fillTypeName = "OIL"
        fluidLabel = spec.fluidNames["oil"] or "Engine Oil"
    elseif spec.currentFluidType == "hydraulic" and truckSpec.hydraulicFillUnit then
        fillUnit = truckSpec.hydraulicFillUnit
        fillTypeName = "HYDRAULICOIL"
        fluidLabel = spec.fluidNames["hydraulic"] or "Hydraulic Fluid"
    else
        g_currentMission:showBlinkingWarning("No matching fluid type for this tank!", 2000)
        return false
    end

    -- Calculate transfer amount
    local currentLevel = vehicle:getFillUnitFillLevel(fillUnit) or 0
    local capacity = vehicle:getFillUnitCapacity(fillUnit) or 0
    local spaceInTruck = capacity - currentLevel

    if spaceInTruck <= 0.5 then
        g_currentMission:showBlinkingWarning(
            string.format("%s tank is full! (%.0f/%.0fL)", fluidLabel, currentLevel, capacity), 2000)
        return false
    end

    local transferAmount = math.min(spaceInTruck, spec.currentFluidStorage)
    if transferAmount <= 0 then
        g_currentMission:showBlinkingWarning("Storage tank is empty!", 2000)
        return false
    end

    -- Transfer fluid into truck's fill unit
    local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
    UsedPlus.logInfo(string.format("OilServicePoint.fillServiceTruckTank: fillType=%s, fillTypeIndex=%s, fillUnit=%d, before=%.1f/%.1f, transfer=%.1f",
        fillTypeName, tostring(fillTypeIndex), fillUnit, currentLevel, capacity, transferAmount))

    if fillTypeIndex == nil then
        UsedPlus.logError(string.format("OilServicePoint: Fill type '%s' NOT FOUND in g_fillTypeManager!", fillTypeName))
        g_currentMission:showBlinkingWarning("Error: Fill type not registered!", 2000)
        return false
    end

    local actualAdded = vehicle:addFillUnitFillLevel(
        vehicle:getOwnerFarmId(), fillUnit, transferAmount,
        fillTypeIndex, ToolType.UNDEFINED, nil)
    actualAdded = actualAdded or 0

    local newLevel = vehicle:getFillUnitFillLevel(fillUnit) or 0
    UsedPlus.logInfo(string.format("OilServicePoint.fillServiceTruckTank: addFillUnitFillLevel returned=%.1f, newLevel=%.1f/%.1f",
        actualAdded, newLevel, capacity))

    -- Only consume from storage what was ACTUALLY added to the truck
    local consumed = math.abs(actualAdded)
    if consumed < 0.1 then
        -- Fill was rejected - don't consume storage
        UsedPlus.logError(string.format("OilServicePoint: addFillUnitFillLevel REJECTED! fillUnit=%d, fillType=%s(%d), amount=%.1f",
            fillUnit, fillTypeName, fillTypeIndex, transferAmount))
        g_currentMission:showBlinkingWarning(
            string.format("Fill failed! %s may not accept %s (fillUnit=%d)", vehicleName, fillTypeName, fillUnit), 3000)
        return false
    end

    spec.currentFluidStorage = spec.currentFluidStorage - consumed
    if spec.currentFluidStorage <= 0 then
        spec.currentFluidStorage = 0
        spec.currentFluidType = nil
    end

    -- Confirmation
    g_currentMission:showBlinkingWarning(
        string.format("%s tank filled - +%.0fL (now %.0f/%.0fL)",
            fluidLabel, consumed, newLevel, capacity), 2000)

    UsedPlus.logInfo(string.format("OilServicePoint: Filled %s %s tank +%.0fL (%.0f/%.0fL, storage: %.0fL left)",
        vehicleName, fluidLabel, consumed, newLevel, capacity, spec.currentFluidStorage))

    return true
end

-- Multiplayer sync
function OilServicePoint:onReadStream(streamId, connection)
    local spec = self.spec_oilServicePoint
    if spec == nil then return end

    spec.currentFluidStorage = streamReadFloat32(streamId)
    local hasFluidType = streamReadBool(streamId)
    if hasFluidType then
        spec.currentFluidType = streamReadString(streamId)
    else
        spec.currentFluidType = nil
    end
end

function OilServicePoint:onWriteStream(streamId, connection)
    local spec = self.spec_oilServicePoint
    if spec == nil then return end

    streamWriteFloat32(streamId, spec.currentFluidStorage)
    if spec.currentFluidType then
        streamWriteBool(streamId, true)
        streamWriteString(streamId, spec.currentFluidType)
    else
        streamWriteBool(streamId, false)
    end
end


--[[
    ============================================================================
    FluidPurchaseActivatable - Opens dialog for purchasing fluids
    ============================================================================
]]
FluidPurchaseActivatable = {}
local FluidPurchaseActivatable_mt = Class(FluidPurchaseActivatable)

function FluidPurchaseActivatable.new(servicePoint, actionText)
    local self = setmetatable({}, FluidPurchaseActivatable_mt)

    self.servicePoint = servicePoint
    self.activateText = actionText

    return self
end

function FluidPurchaseActivatable:getIsActivatable()
    if self.servicePoint == nil then
        return false
    end

    -- Check player still in range and on foot
    return self.servicePoint:isPlayerInRange()
end

function FluidPurchaseActivatable:run()
    -- Open the fluid purchase dialog
    if FluidPurchaseDialog and FluidPurchaseDialog.show then
        FluidPurchaseDialog.show(self.servicePoint)
    else
        UsedPlus.logError("FluidPurchaseActivatable: FluidPurchaseDialog not available!")
    end
end

function FluidPurchaseActivatable:getDistance(x, y, z)
    return 1
end


--[[
    ============================================================================
    FluidRefillActivatable - For vehicle fluid refill from tank
    ============================================================================
]]
FluidRefillActivatable = {}
local FluidRefillActivatable_mt = Class(FluidRefillActivatable)

function FluidRefillActivatable.new(servicePoint, vehicle, fluidType, actionText, canActivate)
    local self = setmetatable({}, FluidRefillActivatable_mt)

    self.servicePoint = servicePoint
    self.vehicle = vehicle
    self.fluidType = fluidType  -- "oil", "hydraulic", or nil (info only)
    self.canActivate = canActivate
    self.activateText = actionText

    return self
end

function FluidRefillActivatable:getIsActivatable()
    if self.vehicle == nil or self.servicePoint == nil then
        return false
    end

    -- Check vehicle still in range
    local vehicleInRange = self.servicePoint:getVehicleInRange()
    if vehicleInRange ~= self.vehicle then
        return false
    end

    -- v2.7.1: Always show prompt when vehicle is in range
    -- Even if we can't refill (info-only mode), show the status message
    return true
end

--[[
    v2.7.1: Get the text to display for this activatable
    Shows different text based on whether action is available
]]
function FluidRefillActivatable:getActivateText()
    return self.activateText or "Service Vehicle"
end

function FluidRefillActivatable:run()
    -- v2.7.1: Only perform action if canActivate is true
    if not self.canActivate then
        -- Info-only mode - show a message explaining why
        if self.activateText then
            g_currentMission:showBlinkingWarning(self.activateText, 2000)
        end
        return
    end

    if self.fluidType == "oil" then
        self.servicePoint:refillOil(self.vehicle)
    elseif self.fluidType == "hydraulic" then
        self.servicePoint:refillHydraulic(self.vehicle)
    elseif self.fluidType == "serviceTruck" then
        self.servicePoint:fillServiceTruckTank(self.vehicle)
    end
end

function FluidRefillActivatable:getDistance(x, y, z)
    return 1
end


UsedPlus.logInfo("OilServicePoint.lua loaded (v2.11.1 - PlaceableEmployer save pattern)")
