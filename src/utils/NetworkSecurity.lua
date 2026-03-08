--[[
    FS25_UsedPlus - Network Security Utility

    v2.7.2: Added to prevent multiplayer exploits

    Provides validation functions for network events to ensure:
    - Players can only act on behalf of their own farm
    - Malicious clients cannot drain other farms' money
    - All financial operations are properly authorized

    CRITICAL: All events that accept farmId should call validateFarmOwnership()
]]

NetworkSecurity = {}

--[[
    Validate that a network connection is authorized to act on behalf of a farm

    @param connection - Network connection (nil for local/server)
    @param claimedFarmId - The farmId the client claims to act on behalf of
    @return boolean - true if authorized, false if not
    @return string - Error message if not authorized (nil if authorized)
]]
function NetworkSecurity.validateFarmOwnership(connection, claimedFarmId)
    -- Local/server connections are trusted
    if connection == nil then
        return true, nil
    end

    -- Single-player is always trusted
    if g_currentMission:getIsServer() and not g_currentMission.missionDynamicInfo.isMultiplayer then
        return true, nil
    end

    -- Get player from connection
    local player = g_currentMission:getPlayerByConnection(connection)
    if player == nil then
        -- Try alternative: userManager
        if g_currentMission.userManager then
            local user = g_currentMission.userManager:getUserByConnection(connection)
            if user then
                local userFarmId = user.getFarmId and user:getFarmId() or nil
                if userFarmId and userFarmId == claimedFarmId then
                    return true, nil
                end
            end
        end

        UsedPlus.logWarn(string.format(
            "[SECURITY] Farm ownership validation failed: Could not identify player from connection (claimed farmId: %s)",
            tostring(claimedFarmId)
        ))
        return false, "Could not identify player"
    end

    -- Check if player's farm matches claimed farm
    local playerFarmId = player.farmId
    if playerFarmId == nil then
        UsedPlus.logWarn(string.format(
            "[SECURITY] Farm ownership validation failed: Player has no farmId (claimed farmId: %s)",
            tostring(claimedFarmId)
        ))
        return false, "Player has no farm"
    end

    if playerFarmId ~= claimedFarmId then
        UsedPlus.logWarn(string.format(
            "[SECURITY] Farm ownership validation REJECTED: Player farmId %d does not match claimed farmId %d",
            playerFarmId, claimedFarmId
        ))
        return false, "Farm ownership mismatch"
    end

    return true, nil
end

--[[
    Validate that a connection has master rights (admin permissions)

    @param connection - Network connection
    @return boolean - true if has master rights
]]
--[[
    Log a security event for audit purposes

    @param eventType - Type of security event
    @param details - Details about the event
    @param connection - Network connection (optional)
]]
function NetworkSecurity.logSecurityEvent(eventType, details, connection)
    local connectionInfo = "local"
    if connection then
        local player = g_currentMission:getPlayerByConnection(connection)
        if player then
            connectionInfo = string.format("player=%s farmId=%s",
                tostring(player.nickname or "unknown"),
                tostring(player.farmId or "none"))
        else
            connectionInfo = "unknown_connection"
        end
    end

    UsedPlus.logWarn(string.format("[SECURITY] %s: %s (connection: %s)",
        eventType, details, connectionInfo))
end

UsedPlus.logInfo("NetworkSecurity utility loaded")
