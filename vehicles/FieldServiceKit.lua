--[[
    FS25_UsedPlus - OBD Scanner Vehicle Specialization

    A consumable hand tool that allows emergency field repairs on disabled vehicles.
    Player carries the scanner to a broken vehicle, activates it, and plays a diagnosis
    minigame to attempt repairs. Scanner is consumed after single use.

    Based on: FS25_MobileServiceKit by w33zl (with acknowledgment)

    v1.8.0 - Field Service Kit System
    v2.0.0 - Full RVB/UYT cross-mod integration
    v2.0.1 - Fixed activation prompt, changed keybind to O
    v2.0.2 - Used addExtraPrintText + getDigitalInputAxis (worked but wrong UX)
    v2.0.3 - Attempted PlayerInputComponent (double keybind bug)
    v2.0.4 - Direct input polling - CONFIRMED WORKING
    v2.0.5 - FAILED: CutOpenBale pattern still causes double keybind
    v2.0.6 - Back to v2.0.4: Direct polling only, NO registerActionEvent
    v2.0.7 - RVB Pattern: Uses beginActionEventsModification/endActionEventsModification
            - This is the EXACT pattern RVB uses for jumper cables (which works!)
            - Key difference: modification context wrapper around registration
            - Game renders [O] automatically, we only provide text
]]

FieldServiceKit = {}
FieldServiceKit.MOD_NAME = g_currentModName or "FS25_UsedPlus"

-- Global tracking for proximity-based activation
FieldServiceKit.instances = {}           -- All active OBD scanner instances
FieldServiceKit.nearestScanner = nil     -- Currently nearest scanner to player
FieldServiceKit.actionEventId = nil      -- v2.0.7: Action event ID (RVB pattern)

local SPEC_NAME = "spec_fieldServiceKit"

function FieldServiceKit.prerequisitesPresent(specializations)
    return true
end

function FieldServiceKit.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "findNearbyVehicles", FieldServiceKit.findNearbyVehicles)
    SpecializationUtil.registerFunction(vehicleType, "getTargetVehicle", FieldServiceKit.getTargetVehicle)
    SpecializationUtil.registerFunction(vehicleType, "activateFieldService", FieldServiceKit.activateFieldService)
    SpecializationUtil.registerFunction(vehicleType, "consumeKit", FieldServiceKit.consumeKit)
    SpecializationUtil.registerFunction(vehicleType, "getActivatePromptText", FieldServiceKit.getActivatePromptText)
end

function FieldServiceKit.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", FieldServiceKit)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", FieldServiceKit)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", FieldServiceKit)
end

function FieldServiceKit.initSpecialization()
    local schema = Vehicle.xmlSchema
    schema:setXMLSpecializationType("FieldServiceKit")

    schema:register(XMLValueType.STRING, "vehicle.fieldServiceKit#kitTier", "Kit tier: basic, professional, or master", "basic")
    schema:register(XMLValueType.FLOAT, "vehicle.fieldServiceKit#detectionRadius", "Radius to detect nearby vehicles", 5.0)
    schema:register(XMLValueType.NODE_INDEX, "vehicle.fieldServiceKit#playerTriggerNode", "Trigger node for player activation")
    schema:register(XMLValueType.NODE_INDEX, "vehicle.fieldServiceKit#vehicleTriggerNode", "Trigger node for vehicle detection")

    schema:setXMLSpecializationType()
end

function FieldServiceKit:onLoad(savegame)
    self[SPEC_NAME] = {}
    local spec = self[SPEC_NAME]

    -- Load configuration from XML
    spec.kitTier = self.xmlFile:getValue("vehicle.fieldServiceKit#kitTier", "basic")
    spec.detectionRadius = self.xmlFile:getValue("vehicle.fieldServiceKit#detectionRadius", 5.0)

    -- State tracking
    spec.nearbyVehicles = {}
    spec.targetVehicle = nil
    spec.isActivated = false
    spec.isConsumed = false
    spec.playerNearby = false

    -- v2.0.1: Removed activatable system - using custom input instead to avoid R key conflict
    -- The activatable system forces use of ACTIVATE action (R key) which conflicts with
    -- Realistic Breakdowns jumper cable. Now using custom USEDPLUS_ACTIVATE_OBD action (O key).

    -- Load trigger nodes
    local playerTriggerNode = self.xmlFile:getValue("vehicle.fieldServiceKit#playerTriggerNode", nil, self.components, self.i3dMappings)
    local vehicleTriggerNode = self.xmlFile:getValue("vehicle.fieldServiceKit#vehicleTriggerNode", nil, self.components, self.i3dMappings)

    -- Set up player trigger if node exists
    if playerTriggerNode ~= nil then
        spec.playerTriggerNode = playerTriggerNode
        addTrigger(playerTriggerNode, "playerTriggerCallback", self)
    end

    -- Set up vehicle detection trigger if node exists
    if vehicleTriggerNode ~= nil then
        spec.vehicleTriggerNode = vehicleTriggerNode
        addTrigger(vehicleTriggerNode, "vehicleTriggerCallback", self)
    end

    -- v2.0.3: Register this scanner instance globally for proximity detection
    table.insert(FieldServiceKit.instances, self)

    -- Request updates - critical for objects on the ground to receive onUpdate calls
    -- Pattern from: OilServicePoint.lua
    self:raiseActive()

    UsedPlus.logInfo("FieldServiceKit loaded - tier: " .. spec.kitTier)
end

function FieldServiceKit:onDelete()
    local spec = self[SPEC_NAME]

    if spec.playerTriggerNode ~= nil then
        removeTrigger(spec.playerTriggerNode)
    end

    if spec.vehicleTriggerNode ~= nil then
        removeTrigger(spec.vehicleTriggerNode)
    end

    -- v2.0.3: Unregister this scanner instance from global tracking
    for i, instance in ipairs(FieldServiceKit.instances) do
        if instance == self then
            table.remove(FieldServiceKit.instances, i)
            break
        end
    end

    -- Clear nearest scanner if it was this one
    if FieldServiceKit.nearestScanner == self then
        FieldServiceKit.nearestScanner = nil
    end
end

function FieldServiceKit:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self[SPEC_NAME]

    -- Keep requesting updates (critical for objects on the ground)
    -- Pattern from: OilServicePoint.lua which works correctly
    self:raiseActive()

    -- Handle consumed kit - hide immediately, store player position for movement detection
    if spec.pendingDeletion then
        -- Clear flag first to prevent multiple processing
        spec.pendingDeletion = false
        spec.awaitingDeletion = true

        -- Store player position when consumed (they're in a menu)
        if g_localPlayer ~= nil then
            if g_localPlayer.getPosition ~= nil then
                spec.consumedPlayerX, spec.consumedPlayerY, spec.consumedPlayerZ = g_localPlayer:getPosition()
            elseif g_localPlayer.rootNode ~= nil then
                spec.consumedPlayerX, spec.consumedPlayerY, spec.consumedPlayerZ = getWorldTranslation(g_localPlayer.rootNode)
            end
        end

        -- If this was the nearest scanner, clear it
        if FieldServiceKit.nearestScanner == self then
            FieldServiceKit.nearestScanner = nil
        end

        -- Hide the kit visually immediately
        if self.rootNode ~= nil then
            setVisibility(self.rootNode, false)
        end

        UsedPlus.logInfo("FieldServiceKit: Kit consumed and hidden, waiting for player movement to delete")
        return
    end

    -- Check if player has moved at all since consumption (confirms they exited the menu)
    if spec.awaitingDeletion then
        -- Initialize deletion timer on first check
        if spec.deletionTimer == nil then
            spec.deletionTimer = 5000  -- 5 second delay before deletion
        end

        -- Count down the timer
        spec.deletionTimer = spec.deletionTimer - dt

        -- Only delete after timer expires (gives time for UI to fully close)
        if spec.deletionTimer <= 0 and not spec.deletionStarted then
            spec.deletionStarted = true  -- Prevent multiple deletion attempts
            UsedPlus.logInfo("FieldServiceKit: Deletion timer expired, scheduling removal")

            -- Remove from global instances list first
            for i = #FieldServiceKit.instances, 1, -1 do
                if FieldServiceKit.instances[i] == self then
                    table.remove(FieldServiceKit.instances, i)
                    break
                end
            end

            -- Use addUpdateable for safe delayed deletion
            -- This ensures we're not deleting during an active update cycle
            if g_currentMission ~= nil then
                g_currentMission:addUpdateable({
                    timeRemaining = 100,  -- Small extra delay
                    vehicle = self,
                    update = function(obj, dt)
                        obj.timeRemaining = obj.timeRemaining - dt
                        if obj.timeRemaining <= 0 then
                            UsedPlus.logInfo("FieldServiceKit: Executing safe removal")
                            local vehicle = obj.vehicle

                            -- Try multiple removal methods
                            pcall(function()
                                -- First remove from mission's vehicle list
                                if g_currentMission.removeVehicle then
                                    g_currentMission:removeVehicle(vehicle)
                                    UsedPlus.logInfo("FieldServiceKit: removeVehicle called")
                                end
                            end)

                            pcall(function()
                                -- Then call delete on the vehicle itself
                                if vehicle.delete then
                                    vehicle:delete()
                                    UsedPlus.logInfo("FieldServiceKit: delete() called")
                                end
                            end)

                            g_currentMission:removeUpdateable(obj)
                        end
                    end
                })
            end

            return
        end

        return  -- Don't process anything else while awaiting deletion
    end

    if spec.isConsumed then
        -- If this was the nearest scanner, clear it
        if FieldServiceKit.nearestScanner == self then
            FieldServiceKit.nearestScanner = nil
        end
        return
    end

    -- Update nearby vehicle detection (finds ANY vehicle, not just broken ones)
    self:findNearbyVehicles()

    -- v2.0.4: Check player proximity for direct input polling
    local playerNearby = false
    local playerDistance = 999999
    local activationRadius = 2.5  -- meters
    local isOnFoot = false

    if self.rootNode ~= nil and g_localPlayer ~= nil then
        -- Check if player is on foot (not in a vehicle)
        isOnFoot = true
        if g_localPlayer.getIsInVehicle ~= nil then
            isOnFoot = not g_localPlayer:getIsInVehicle()
        end
        if g_currentMission.controlledVehicle ~= nil then
            isOnFoot = false
        end

        if isOnFoot then
            local kx, ky, kz = getWorldTranslation(self.rootNode)
            local px, py, pz
            if g_localPlayer.getPosition ~= nil then
                px, py, pz = g_localPlayer:getPosition()
            elseif g_localPlayer.rootNode ~= nil then
                px, py, pz = getWorldTranslation(g_localPlayer.rootNode)
            end

            if px ~= nil then
                playerDistance = MathUtil.vector2Length(kx - px, kz - pz)
                playerNearby = playerDistance <= activationRadius
            end
        end
    end

    spec.playerNearby = playerNearby
    spec.playerDistance = playerDistance

    -- v2.0.4: Track nearest scanner for multiple scanner support
    if playerNearby and not spec.isConsumed then
        local currentNearest = FieldServiceKit.nearestScanner
        local shouldBeNearest = false

        if currentNearest == nil then
            shouldBeNearest = true
        elseif currentNearest == self then
            shouldBeNearest = true
        else
            -- Check if we're closer than the current nearest
            local currentSpec = currentNearest[SPEC_NAME]
            if currentSpec == nil or currentSpec.playerDistance == nil or playerDistance < currentSpec.playerDistance then
                shouldBeNearest = true
            end
        end

        if shouldBeNearest then
            FieldServiceKit.nearestScanner = self
        end
    else
        -- Player not nearby this scanner - clear if we were the nearest
        if FieldServiceKit.nearestScanner == self then
            FieldServiceKit.nearestScanner = nil
        end
    end

    -- v2.0.7: RVB Pattern - Use setActionEventText/Active/TextVisibility
    -- The callback handles activation, we just control display here
    if FieldServiceKit.actionEventId ~= nil and g_inputBinding ~= nil then
        local shouldShow = playerNearby and isOnFoot and FieldServiceKit.nearestScanner == self

        if shouldShow then
            -- Build prompt text WITHOUT [O] - game renders keybind automatically
            local promptText = self:getActivatePromptText()

            -- Set text and make visible (RVB pattern)
            g_inputBinding:setActionEventTextPriority(FieldServiceKit.actionEventId, GS_PRIO_VERY_HIGH)
            g_inputBinding:setActionEventTextVisibility(FieldServiceKit.actionEventId, true)
            g_inputBinding:setActionEventActive(FieldServiceKit.actionEventId, true)
            g_inputBinding:setActionEventText(FieldServiceKit.actionEventId, promptText)
        else
            -- Hide when not nearby
            g_inputBinding:setActionEventTextVisibility(FieldServiceKit.actionEventId, false)
            g_inputBinding:setActionEventActive(FieldServiceKit.actionEventId, false)
        end
    end
end

--[[
    Get the prompt text to display when player is near the kit
    v2.0.7: Returns text WITHOUT [KEY] prefix - game renders keybind via setActionEventText
]]
function FieldServiceKit:getActivatePromptText()
    local spec = self[SPEC_NAME]

    -- Base text (NO key prefix - game renders that automatically)
    local baseText = "OBD Scanner"

    -- Add vehicle info if we have a target
    if spec.targetVehicle ~= nil then
        local vehicleName = spec.targetVehicle.vehicle:getName() or "Vehicle"
        local target = spec.targetVehicle

        if target.isDisabled then
            baseText = string.format("OBD Scanner: %s (DISABLED)", vehicleName)
        elseif target.needsService then
            local warnings = {}
            if target.hasRVBIssue then table.insert(warnings, "RVB") end
            if target.hasUYTIssue then table.insert(warnings, "Tires") end
            if target.hasMaintenance then
                local maintSpec = target.vehicle.spec_usedPlusMaintenance
                if maintSpec then
                    if maintSpec.engineReliability < 0.5 then table.insert(warnings, "Engine") end
                    if maintSpec.electricalReliability < 0.5 then table.insert(warnings, "Electrical") end
                    if maintSpec.hydraulicReliability < 0.5 then table.insert(warnings, "Hydraulic") end
                end
            end
            if #warnings > 0 then
                baseText = string.format("OBD Scanner: %s (%s)", vehicleName, table.concat(warnings, ", "))
            else
                baseText = string.format("OBD Scanner: %s", vehicleName)
            end
        else
            baseText = string.format("OBD Scanner: %s", vehicleName)
        end
    end

    -- Return text only - game adds [KEY] prefix automatically via action event system
    return baseText
end

--[[
    Find vehicles within detection radius
    v1.9.9: Find ANY vehicle for OBD scanning, not just broken ones
    v2.0.0: Uses ModCompatibility for RVB/UYT cross-mod detection
    The scanner can diagnose any vehicle's health status
]]
function FieldServiceKit:findNearbyVehicles()
    local spec = self[SPEC_NAME]
    spec.nearbyVehicles = {}
    spec.targetVehicle = nil

    if self.rootNode == nil then
        UsedPlus.logInfo("FieldServiceKit:findNearbyVehicles - rootNode is nil!")
        return
    end

    local x, y, z = getWorldTranslation(self.rootNode)
    -- v2.0.3: Increased detection radius to 15m for better usability
    local radius = spec.detectionRadius or 15.0
    local radiusSq = radius * radius

    -- DEBUG: Removed verbose logging - was flooding logs

    -- Check all vehicles in mission
    -- v2.0.3: Use g_currentMission.vehicleSystem.vehicles (FS25 standard pattern)
    if g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles ~= nil then
        for _, vehicle in ipairs(g_currentMission.vehicleSystem.vehicles) do
            if vehicle ~= self and vehicle.rootNode ~= nil then
                local vx, vy, vz = getWorldTranslation(vehicle.rootNode)
                local distSq = (x - vx)^2 + (y - vy)^2 + (z - vz)^2
                local dist = math.sqrt(distSq)

                if distSq <= radiusSq then
                    -- v2.0.0: Use ModCompatibility for cross-mod health detection
                    local maintSpec = vehicle.spec_usedPlusMaintenance
                    local isDisabled = maintSpec and maintSpec.isDisabled or false
                    local needsService = false
                    local hasRVBIssue = false
                    local hasUYTIssue = false

                    -- Check UsedPlus maintenance if available
                    if maintSpec then
                        needsService = isDisabled or
                                      maintSpec.engineReliability < 0.5 or
                                      maintSpec.electricalReliability < 0.5 or
                                      maintSpec.hydraulicReliability < 0.5
                    end

                    -- v2.0.0: Check RVB part failures via ModCompatibility
                    if ModCompatibility and ModCompatibility.rvbInstalled then
                        -- Check engine parts
                        if ModCompatibility.isRVBPartFailed(vehicle, "ENGINE") or
                           ModCompatibility.isRVBPartFailed(vehicle, "THERMOSTAT") or
                           ModCompatibility.isRVBPartPrefault(vehicle, "ENGINE") or
                           ModCompatibility.isRVBPartPrefault(vehicle, "THERMOSTAT") then
                            hasRVBIssue = true
                        end

                        -- Check electrical parts
                        if ModCompatibility.isRVBPartFailed(vehicle, "GENERATOR") or
                           ModCompatibility.isRVBPartFailed(vehicle, "BATTERY") or
                           ModCompatibility.isRVBPartFailed(vehicle, "SELFSTARTER") or
                           ModCompatibility.isRVBPartPrefault(vehicle, "GENERATOR") or
                           ModCompatibility.isRVBPartPrefault(vehicle, "BATTERY") then
                            hasRVBIssue = true
                        end

                        -- Check for low part life (<30%)
                        local engineLife = ModCompatibility.getRVBPartLife(vehicle, "ENGINE")
                        local genLife = ModCompatibility.getRVBPartLife(vehicle, "GENERATOR")
                        local batLife = ModCompatibility.getRVBPartLife(vehicle, "BATTERY")
                        if engineLife < 0.3 or genLife < 0.3 or batLife < 0.3 then
                            hasRVBIssue = true
                        end
                    end

                    -- v2.0.0: Check UYT tire wear via ModCompatibility
                    if ModCompatibility and ModCompatibility.uytInstalled then
                        local maxWear = ModCompatibility.getUYTMaxTireWear(vehicle)
                        if maxWear > 0.8 then  -- >80% worn
                            hasUYTIssue = true
                        end
                    end

                    -- Combine all sources for needsService indicator
                    needsService = needsService or hasRVBIssue or hasUYTIssue

                    -- Add ANY vehicle within range (OBD scanner can diagnose any vehicle)
                    table.insert(spec.nearbyVehicles, {
                        vehicle = vehicle,
                        distance = math.sqrt(distSq),
                        isDisabled = isDisabled,
                        needsService = needsService,
                        hasRVBIssue = hasRVBIssue,
                        hasUYTIssue = hasUYTIssue,
                        hasMaintenance = maintSpec ~= nil,
                        failedSystem = maintSpec and maintSpec.lastFailedSystem or nil
                    })
                end
            end
        end
    end

    -- Sort by distance and pick closest
    table.sort(spec.nearbyVehicles, function(a, b) return a.distance < b.distance end)

    if #spec.nearbyVehicles > 0 then
        spec.targetVehicle = spec.nearbyVehicles[1]
    end
end

--[[
    Get the current target vehicle (closest serviceable vehicle)
]]
function FieldServiceKit:getTargetVehicle()
    local spec = self[SPEC_NAME]
    return spec.targetVehicle
end

--[[
    Activate field service - opens the diagnosis dialog
    v1.9.9: Shows message if no vehicle nearby, otherwise opens OBD Scanner
]]
function FieldServiceKit:activateFieldService()
    local spec = self[SPEC_NAME]
    if spec == nil or spec.isConsumed then
        return false
    end

    -- Re-scan for vehicles at activation time
    self:findNearbyVehicles()

    if spec.targetVehicle == nil then
        -- No vehicle nearby - show info message
        local infoText = g_i18n:getText("usedplus_fsk_noVehicle") or "No vehicle detected within range. Move the scanner closer to a vehicle."
        if InfoDialog ~= nil and InfoDialog.show ~= nil then
            InfoDialog.show(infoText)
        else
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, infoText)
        end
        return false
    end

    -- Ensure dialog is registered before showing
    if FieldServiceKitDialog ~= nil and FieldServiceKitDialog.register ~= nil then
        FieldServiceKitDialog.register()
    else
        UsedPlus.logError("FieldServiceKit: FieldServiceKitDialog class not found!")
        return false
    end

    -- Open the field service dialog
    local dialog = g_gui:showDialog("FieldServiceKitDialog")
    if dialog == nil then
        UsedPlus.logError("FieldServiceKit: Dialog failed to open")
        return false
    end

    if dialog.target ~= nil then
        dialog.target:setData(spec.targetVehicle.vehicle, self, spec.kitTier)
    end

    return true
end

--[[
    Consume the kit after use - schedules deletion
]]
function FieldServiceKit:consumeKit()
    local spec = self[SPEC_NAME]

    if spec.isConsumed then
        return
    end

    spec.isConsumed = true
    UsedPlus.logInfo("FieldServiceKit consumed - scheduling deletion")

    -- v2.0.7: Clear nearestScanner and hide action event immediately
    if FieldServiceKit.nearestScanner == self then
        FieldServiceKit.nearestScanner = nil
    end

    -- Hide the action event so it doesn't show for a consumed scanner
    if FieldServiceKit.actionEventId ~= nil and g_inputBinding ~= nil then
        g_inputBinding:setActionEventTextVisibility(FieldServiceKit.actionEventId, false)
        g_inputBinding:setActionEventActive(FieldServiceKit.actionEventId, false)
        UsedPlus.logInfo("FieldServiceKit: Action event hidden after consumption")
    end

    -- Mark for deletion on next update cycle
    -- We use a flag instead of immediate deletion to avoid issues during event handling
    spec.pendingDeletion = true
    UsedPlus.logInfo("FieldServiceKit: Kit marked for deletion")
end

--[[
    Player trigger callback - when player enters/exits trigger zone
]]
function FieldServiceKit:playerTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay)
    if not onEnter and not onLeave then
        return
    end

    local spec = self[SPEC_NAME]

    -- Check if it's the player
    if g_currentMission.player ~= nil and g_currentMission.player.rootNode == otherId then
        if onEnter then
            spec.playerInTrigger = true
        elseif onLeave then
            spec.playerInTrigger = false
        end
    end
end

--[[
    Vehicle trigger callback - when vehicles enter/exit detection zone
]]
function FieldServiceKit:vehicleTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay)
    -- Vehicle detection is handled in onUpdate via findNearbyVehicles()
    -- This callback could be used for more precise collision-based detection
end

--[[
    v2.0.7: RVB Pattern - Action Event Registration

    The EXACT pattern from Real Vehicle Breakdowns (jumper cables):
    1. Hook into PlayerInputComponent.registerActionEvents (not registerGlobalPlayerActionEvents)
    2. Wrap registration in beginActionEventsModification/endActionEventsModification
    3. Check inputComponent.player.isOwner before registering
    4. Use setActionEventText/Active/TextVisibility in onUpdate to control display
    5. Game renders [KEY] automatically - we only provide text

    Key difference from our previous attempts: The modification context wrapper.
]]

-- Callback function when action is triggered (RVB pattern)
function FieldServiceKit.actionEventCallback(self, actionName, inputValue, callbackState, isAnalog)
    -- Only trigger on key press (inputValue > 0), not release
    if inputValue <= 0 then
        return
    end

    -- Find and activate the nearest scanner
    local scanner = FieldServiceKit.nearestScanner
    if scanner ~= nil then
        local spec = scanner[SPEC_NAME]
        if spec ~= nil and not spec.isConsumed then
            UsedPlus.logInfo("OBD Scanner: Action callback triggered, activating scanner")
            scanner:activateFieldService()
        end
    end
end

-- RVB Pattern: Hook into PlayerInputComponent.registerActionEvents
-- Uses custom appendedFunction like RVB does
FieldServiceKit.originalRegisterActionEvents = nil

function FieldServiceKit.hookPlayerInputComponent()
    if FieldServiceKit.originalRegisterActionEvents ~= nil then
        return -- Already hooked
    end

    if PlayerInputComponent == nil or PlayerInputComponent.registerActionEvents == nil then
        UsedPlus.logWarn("OBD Scanner: PlayerInputComponent.registerActionEvents not available")
        return
    end

    -- Store original function
    FieldServiceKit.originalRegisterActionEvents = PlayerInputComponent.registerActionEvents

    -- Replace with our version that calls original then adds our action
    PlayerInputComponent.registerActionEvents = function(inputComponent, ...)
        -- Call original first
        FieldServiceKit.originalRegisterActionEvents(inputComponent, ...)

        -- Now add our action (RVB pattern)
        if inputComponent.player ~= nil and inputComponent.player.isOwner then
            -- Check if action exists
            local actionId = InputAction.USEDPLUS_ACTIVATE_OBD
            if actionId == nil then
                UsedPlus.logWarn("OBD Scanner: InputAction.USEDPLUS_ACTIVATE_OBD not found")
                return
            end

            -- RVB uses beginActionEventsModification/endActionEventsModification
            g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)

            local success, eventId = g_inputBinding:registerActionEvent(
                actionId,                               -- Action from modDesc.xml
                FieldServiceKit,                        -- Target object
                FieldServiceKit.actionEventCallback,    -- Callback function
                false,                                  -- triggerUp
                true,                                   -- triggerDown
                false,                                  -- triggerAlways
                false,                                  -- startActive (RVB uses false)
                nil,                                    -- callbackState
                true                                    -- disableConflictingBindings (RVB uses true)
            )

            g_inputBinding:endActionEventsModification()

            if success and eventId ~= nil then
                FieldServiceKit.actionEventId = eventId
                UsedPlus.logInfo("OBD Scanner: Action event registered (RVB pattern), eventId=" .. tostring(eventId))
            else
                UsedPlus.logWarn("OBD Scanner: Failed to register action event")
            end
        end
    end

    UsedPlus.logInfo("OBD Scanner: PlayerInputComponent.registerActionEvents hooked (v2.0.7 RVB pattern)")
end

-- Install hook when this file loads
FieldServiceKit.hookPlayerInputComponent()
