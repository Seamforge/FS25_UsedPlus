# Network Events Pattern

**How to synchronize data between client and server in multiplayer**

Based on patterns from: UsedPlus, BuyUsedEquipment, HirePurchasing, EnhancedLoanSystem

---

## Related API Documentation

> 📖 For complete function signatures and source code, see the [FS25 Community LUADOC](https://github.com/umbraprior/FS25-Community-LUADOC)

| Class | API Reference | Description |
|-------|---------------|-------------|
| Events (folder) | [Events/](https://github.com/umbraprior/FS25-Community-LUADOC/tree/main/docs/script/Events) | 200+ event class examples |
| Network Engine | [Network/](https://github.com/umbraprior/FS25-Community-LUADOC/tree/main/docs/engine/Network) | Low-level network functions |
| StreamRead | [streamRead functions](https://github.com/umbraprior/FS25-Community-LUADOC/tree/main/docs/engine/Network) | `streamReadInt32()`, `streamReadString()`, etc. |
| StreamWrite | [streamWrite functions](https://github.com/umbraprior/FS25-Community-LUADOC/tree/main/docs/engine/Network) | `streamWriteInt32()`, `streamWriteString()`, etc. |

**Example Events (Reference):**
- [VehicleSellEvent.md](https://github.com/umbraprior/FS25-Community-LUADOC/blob/main/docs/script/Events/VehicleSellEvent.md) - Vehicle sale pattern
- [MoneyChangeEvent.md](https://github.com/umbraprior/FS25-Community-LUADOC/blob/main/docs/script/Events/MoneyChangeEvent.md) - Money transactions
- [SetFarmlandStateEvent.md](https://github.com/umbraprior/FS25-Community-LUADOC/blob/main/docs/script/Events/SetFarmlandStateEvent.md) - Land state changes

---

## Validation Status Legend

| Badge | Meaning |
|-------|---------|
| ✅ **VALIDATED** | Actively used in FS25_UsedPlus - includes file:line reference |
| ⚠️ **PARTIAL** | Pattern exists but with variations from documented example |
| 📚 **REFERENCE** | From source mod only - not validated in UsedPlus codebase |

---

## Overview

> ✅ **VALIDATED** - 19 events across 8 files in UsedPlus
> - All events implement documented patterns with 100% compliance
> - Files: `FS25_UsedPlus/src/events/` - FinanceEvents, LeaseEvents, LandEvents, SaleEvents, UsedMarketEvents, RepairVehicleEvent, SetPaymentConfigEvent, UsedPlusSettingsEvent

Network events are required for **any action that modifies game state** in multiplayer:
- Creating/modifying deals, loans, listings
- Spending/adding money
- Modifying vehicles or farm data
- Any persistent change

**Rule:** Client requests action → Server validates and executes → Server broadcasts result

---

## Basic Event Structure

> ✅ **VALIDATED** - All UsedPlus events follow this exact structure
> - Example: `FS25_UsedPlus/src/events/FinanceEvents.lua:17-152` - FinanceVehicleEvent
> - Example: `FS25_UsedPlus/src/events/SaleEvents.lua:16-101` - CreateSaleListingEvent

### Event Class Template
```lua
--[[
    MyActionEvent - Network event for [description]

    Flow:
    1. Client calls MyActionEvent.sendToServer(params)
    2. Server receives, validates, executes
    3. State change is automatically synced
]]

MyActionEvent = {}
local MyActionEvent_mt = Class(MyActionEvent, Event)

-- Register event class with game
InitEventClass(MyActionEvent, "MyActionEvent")

--[[
    Empty constructor for receiving events
]]
function MyActionEvent.emptyNew()
    local self = Event.new(MyActionEvent_mt)
    return self
end

--[[
    Constructor with data for sending events
]]
function MyActionEvent.new(param1, param2)
    local self = MyActionEvent.emptyNew()
    self.param1 = param1
    self.param2 = param2
    return self
end

--[[
    Static helper - call this from UI/client code
]]
function MyActionEvent.sendToServer(param1, param2)
    if g_server ~= nil then
        -- Single-player or server: execute directly
        MyActionEvent.execute(param1, param2)
    else
        -- Multiplayer client: send to server
        g_client:getServerConnection():sendEvent(
            MyActionEvent.new(param1, param2)
        )
    end
end

--[[
    Serialize data to network stream
]]
function MyActionEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.param1)
    streamWriteString(streamId, self.param2)
end

--[[
    Deserialize data from network stream
]]
function MyActionEvent:readStream(streamId, connection)
    self.param1 = streamReadInt32(streamId)
    self.param2 = streamReadString(streamId)
    self:run(connection)
end

--[[
    Execute business logic (server-side)
]]
function MyActionEvent.execute(param1, param2)
    -- Validate parameters
    if param1 == nil or param2 == nil then
        print("Error: [MyMod] MyActionEvent - Invalid parameters")
        return false
    end

    -- Execute the actual logic
    -- ... your code here ...

    return true
end

--[[
    Called when event is received on server
]]
function MyActionEvent:run(connection)
    -- Reject if received on a client (connection:getIsServer() == true means
    -- the other end is the server, so WE are a client - don't execute here)
    if connection ~= nil and connection:getIsServer() then
        return
    end

    MyActionEvent.execute(self.param1, self.param2)
end

print("MyMod: MyActionEvent loaded")
```

---

## Stream Read/Write Functions

> ✅ **VALIDATED** - All stream types used correctly in UsedPlus events
> - Example: `FS25_UsedPlus/src/events/FinanceEvents.lua:51-77` (writeStream)
> - Example: `FS25_UsedPlus/src/events/UsedMarketEvents.lua:47-64` (various types)

### Available Types
```lua
-- Integers
streamWriteInt8(streamId, value)      -- -128 to 127
streamWriteUInt8(streamId, value)     -- 0 to 255
streamWriteInt16(streamId, value)     -- -32768 to 32767
streamWriteUInt16(streamId, value)    -- 0 to 65535
streamWriteInt32(streamId, value)     -- Standard integer
streamWriteUIntN(streamId, value, n)  -- N-bit unsigned

-- Floating point
streamWriteFloat32(streamId, value)   -- Standard float

-- Boolean
streamWriteBool(streamId, value)

-- String
streamWriteString(streamId, value)

-- Reading (same names, replace Write with Read)
local value = streamReadInt32(streamId)
local str = streamReadString(streamId)
local flag = streamReadBool(streamId)
```

### Best Practices
```lua
-- Always write in same order as read
function MyEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteString(streamId, self.listingId)
    streamWriteFloat32(streamId, self.amount)
    streamWriteBool(streamId, self.isActive)
end

function MyEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.listingId = streamReadString(streamId)
    self.amount = streamReadFloat32(streamId)
    self.isActive = streamReadBool(streamId)
    self:run(connection)
end
```

---

## Real-World Examples

### Create Sale Listing Event
```lua
CreateSaleListingEvent = {}
local CreateSaleListingEvent_mt = Class(CreateSaleListingEvent, Event)

InitEventClass(CreateSaleListingEvent, "CreateSaleListingEvent")

function CreateSaleListingEvent.emptyNew()
    local self = Event.new(CreateSaleListingEvent_mt)
    return self
end

function CreateSaleListingEvent.new(farmId, vehicleId, agentTier)
    local self = CreateSaleListingEvent.emptyNew()
    self.farmId = farmId
    self.vehicleId = vehicleId
    self.agentTier = agentTier
    return self
end

function CreateSaleListingEvent.sendToServer(farmId, vehicleId, agentTier)
    if g_server ~= nil then
        CreateSaleListingEvent.execute(farmId, vehicleId, agentTier)
    else
        g_client:getServerConnection():sendEvent(
            CreateSaleListingEvent.new(farmId, vehicleId, agentTier)
        )
    end
end

function CreateSaleListingEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.farmId)
    streamWriteInt32(streamId, self.vehicleId)
    streamWriteInt8(streamId, self.agentTier)  -- 1-3, so Int8 is fine
end

function CreateSaleListingEvent:readStream(streamId, connection)
    self.farmId = streamReadInt32(streamId)
    self.vehicleId = streamReadInt32(streamId)
    self.agentTier = streamReadInt8(streamId)
    self:run(connection)
end

function CreateSaleListingEvent.execute(farmId, vehicleId, agentTier)
    if g_vehicleSaleManager == nil then
        return false
    end

    local vehicle = g_currentMission:getVehicleById(vehicleId)
    if vehicle == nil then
        return false
    end

    local success = g_vehicleSaleManager:createListing(farmId, vehicle, agentTier)
    return success
end

function CreateSaleListingEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return
    end
    CreateSaleListingEvent.execute(self.farmId, self.vehicleId, self.agentTier)
end
```

### Accept Offer Event (Simple)
```lua
AcceptSaleOfferEvent = {}
local AcceptSaleOfferEvent_mt = Class(AcceptSaleOfferEvent, Event)

InitEventClass(AcceptSaleOfferEvent, "AcceptSaleOfferEvent")

function AcceptSaleOfferEvent.emptyNew()
    return Event.new(AcceptSaleOfferEvent_mt)
end

function AcceptSaleOfferEvent.new(listingId)
    local self = AcceptSaleOfferEvent.emptyNew()
    self.listingId = listingId
    return self
end

function AcceptSaleOfferEvent.sendToServer(listingId)
    if g_server ~= nil then
        AcceptSaleOfferEvent.execute(listingId)
    else
        g_client:getServerConnection():sendEvent(
            AcceptSaleOfferEvent.new(listingId)
        )
    end
end

function AcceptSaleOfferEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.listingId)
end

function AcceptSaleOfferEvent:readStream(streamId, connection)
    self.listingId = streamReadString(streamId)
    self:run(connection)
end

function AcceptSaleOfferEvent.execute(listingId)
    if g_vehicleSaleManager then
        return g_vehicleSaleManager:acceptOffer(listingId)
    end
    return false
end

function AcceptSaleOfferEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then return end
    AcceptSaleOfferEvent.execute(self.listingId)
end
```

---

## Registration in modDesc.xml

Events are registered via `<extraSourceFiles>`:
```xml
<extraSourceFiles>
    <!-- Events must load BEFORE managers that use them -->
    <sourceFile filename="src/events/CreateSaleListingEvent.lua"/>
    <sourceFile filename="src/events/AcceptSaleOfferEvent.lua"/>
    <sourceFile filename="src/events/DeclineSaleOfferEvent.lua"/>

    <!-- Managers load after events -->
    <sourceFile filename="src/managers/VehicleSaleManager.lua"/>
</extraSourceFiles>
```

---

## Common Pitfalls

> ✅ **VALIDATED** - All 4 pitfalls properly avoided in UsedPlus codebase
> - All 19 events use `InitEventClass()` correctly
> - All events have matching write/read order
> - All events check `g_server ~= nil` and `connection:getIsServer()`

### 1. Event Not Received
- Verify `InitEventClass()` is called
- Check event class name matches in `InitEventClass`
- Ensure event file is in modDesc.xml

### 2. Data Corruption
- Write and read in EXACT same order
- Use correct stream types for data ranges
- Don't forget to call `self:run(connection)` in readStream

### 3. Server-Only Execution
- Always check `g_server ~= nil` in sendToServer
- In `run()`, guard with `if connection ~= nil and connection:getIsServer() then return end`
  - `connection:getIsServer() == true` means the other end IS a server → we are a client → don't execute
  - `connection:getIsServer() == false` means the other end is a client → we are the server → execute
- Business logic should be in static `execute()` method

### 4. Nil Reference Errors
- Validate all parameters in `execute()`
- Check managers exist before using them
- Handle missing vehicles/farms gracefully

---

## Advanced Patterns (Validated in UsedPlus)

### Consolidated Multi-Action Events

> ✅ **VALIDATED** - `FS25_UsedPlus/src/events/SaleEvents.lua:108-204`

Instead of separate events for Accept/Decline/Cancel, use action constants:

```lua
SaleListingActionEvent.ACTION_ACCEPT = 1
SaleListingActionEvent.ACTION_DECLINE = 2
SaleListingActionEvent.ACTION_CANCEL = 3

-- Convenience methods
function SaleListingActionEvent.acceptOffer(listingId)
    SaleListingActionEvent.sendToServer(listingId, SaleListingActionEvent.ACTION_ACCEPT)
end
```

### Server→Client Broadcast

> ✅ **VALIDATED** - `FS25_UsedPlus/src/events/UsedMarketEvents.lua:197-228`

For notifications FROM server TO clients:

```lua
function UsedItemFoundEvent:sendToClients(...)
    if g_server ~= nil then
        g_server:broadcastEvent(UsedItemFoundEvent.new(...))
    end
end

-- Or to specific farm
function UsedItemFoundEvent:sendToFarm(farmId, ...)
    local connection = g_server:getClientConnection(farmId)
    if connection then
        connection:sendEvent(UsedItemFoundEvent.new(...))
    end
end
```

**Note:** These advanced patterns evolved from the basic template and are used extensively in UsedPlus.
