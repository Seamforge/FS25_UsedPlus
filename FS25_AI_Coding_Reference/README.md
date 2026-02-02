# FS25 AI Coding Reference

```
 _____ ____  ____  ____     _    ___    ____          _
|  ___/ ___|___ \| ___|   / \  |_ _|  / ___|___   __| | ___
| |_  \___ \ __) |___ \  / _ \  | |  | |   / _ \ / _` |/ _ \
|  _|  ___) / __/ ___) |/ ___ \ | |  | |__| (_) | (_| |  __/
|_|   |____/_____|____/_/   \_\___|  \____\___/ \__,_|\___|
```

> **Battle-tested patterns for Farming Simulator 2025 mod development**

Built by the **UsedPlus** team with **Claude AI** assistance.
Validated against an in-development mod with **83 Lua files** and **30+ custom dialogs**.

---

## Table of Contents

- [Community Resources](#-community-resources)
- [Documentation Overview](#-documentation-overview)
- [Quick Navigation](#-quick-navigation)
- [Critical Quick Reference](#-critical-quick-reference)
- [Source Attribution](#-source-attribution)

---

## Community Resources

> **Three resources, three purposes** - use them together for best results

```
┌─────────────────────────────────────────────────────────────────────┐
│  YOUR QUESTION                           WHERE TO LOOK              │
├─────────────────────────────────────────────────────────────────────┤
│  "How do I build a dialog?"         →   THIS REFERENCE (patterns)   │
│  "What params does loadGui() take?" →   Community LUADOC (API)      │
│  "How does Giants implement X?"     →   FS25-lua-scripting (source) │
└─────────────────────────────────────────────────────────────────────┘
```

### [FS25 Community LUADOC](https://github.com/umbraprior/FS25-Community-LUADOC) ⭐ Highly Recommended

Maintained by [@umbraprior](https://github.com/umbraprior) — the most comprehensive API reference available.

| Metric | Value |
|--------|-------|
| Documentation Pages | **1,661** |
| Script Functions | **11,102** |
| Coverage | Engine, Foundation, Script APIs |

**Quick Links:**
[GUI](https://github.com/umbraprior/FS25-Community-LUADOC/tree/main/docs/script/GUI) ·
[Vehicles](https://github.com/umbraprior/FS25-Community-LUADOC/tree/main/docs/script/Vehicles) ·
[Specializations](https://github.com/umbraprior/FS25-Community-LUADOC/tree/main/docs/script/Specializations) ·
[Events](https://github.com/umbraprior/FS25-Community-LUADOC/tree/main/docs/script/Events) ·
[Economy](https://github.com/umbraprior/FS25-Community-LUADOC/tree/main/docs/script/Economy) ·
[Engine](https://github.com/umbraprior/FS25-Community-LUADOC/tree/main/docs/engine)

### [FS25-lua-scripting](https://github.com/Dukefarming/FS25-lua-scripting) 📂 Raw Source Archive

Created by [@Dukefarming](https://github.com/Dukefarming) — raw Lua source from the game's dataS folder.

- **267 Lua files** — Vehicle.lua, VehicleMotor.lua, dialogs, managers
- **Best for** — Understanding internal implementations
- **Status** — Archived (April 2025) but valuable reference

---

## Documentation Overview

```
╔════════════════════════════════════════════════════════════════════╗
║  28 FILES  ·  9,600+ LINES  ·  73+ PATTERNS  ·  17 PITFALLS       ║
║                    Analyzed from 164+ community mods               ║
╚════════════════════════════════════════════════════════════════════╝
```

### Validation Status

| Category | Files | Status |
|:---------|:-----:|:------:|
| `basics/` | 4 | ✅ 100% validated |
| `patterns/` | 14 | ✅ 100% validated |
| `advanced/` | 8 | ⚠️ 38% validated |
| `pitfalls/` | 1 | ✅ 100% battle-tested |

### Badge Legend

| Badge | Meaning |
|:-----:|---------|
| ✅ | **Validated** — Used in UsedPlus codebase |
| ⚠️ | **Partial** — Some aspects validated, use carefully |
| 📚 | **Reference** — Extracted from source mods, not validated |

---

## Quick Navigation

### Getting Started — `basics/`

| Document | Description |
|----------|-------------|
| [modDesc.md](basics/modDesc.md) | modDesc.xml structure and examples |
| [localization.md](basics/localization.md) | Translation (l10n) patterns |
| [input-bindings.md](basics/input-bindings.md) | Keyboard/controller bindings |
| [lua-patterns.md](basics/lua-patterns.md) | Core Lua patterns & best practices |

### Core Patterns — `patterns/`

| Document | Description | Use Case |
|----------|-------------|----------|
| [gui-dialogs.md](patterns/gui-dialogs.md) | MessageDialog pattern, XML | Custom dialogs |
| [events.md](patterns/events.md) | Network events | Multiplayer sync |
| [managers.md](patterns/managers.md) | Singleton managers | Global state |
| [data-classes.md](patterns/data-classes.md) | Data with business logic | Finance, deals |
| [save-load.md](patterns/save-load.md) | Savegame persistence | Saving data |
| [extensions.md](patterns/extensions.md) | Hooking game classes | Modify behavior |
| [placeable-purchase-hooks.md](patterns/placeable-purchase-hooks.md) | Custom placeable purchase dialogs | Finance/custom flows |
| [vehicle-info-box.md](patterns/vehicle-info-box.md) | Vehicle info display | Add custom HUD info |
| [shop-ui.md](patterns/shop-ui.md) | Shop customization | Shop buttons |
| [async-operations.md](patterns/async-operations.md) | TTL/TTS queues | Delayed ops |
| [message-center.md](patterns/message-center.md) | Event subscription | Time/economy |
| [financial-calculations.md](patterns/financial-calculations.md) | Loans, depreciation | Finance mods |
| [physics-override.md](patterns/physics-override.md) | Property modification | Balance mods |
| [mod-api.md](patterns/mod-api.md) | UsedPlus public API | Cross-mod |

### Advanced Topics — `advanced/`

| Document | Description | Status |
|----------|-------------|:------:|
| [placeables.md](advanced/placeables.md) | Production points, decorations | ⚠️ |
| [triggers.md](advanced/triggers.md) | Trigger zones with timers | ✅ |
| [vehicle-configs.md](advanced/vehicle-configs.md) | Equipment configurations | ✅ |
| [vehicles.md](advanced/vehicles.md) | Specializations, vehicle state | 📚 |
| [hud-framework.md](advanced/hud-framework.md) | Interactive HUD displays | 📚 |
| [animations.md](advanced/animations.md) | Multi-state animations | 📚 |
| [animals.md](advanced/animals.md) | Husbandry integration | 📚 |
| [production-patterns.md](advanced/production-patterns.md) | Multi-input production | 📚 |

### Pitfalls

| Document | Description |
|----------|-------------|
| [what-doesnt-work.md](pitfalls/what-doesnt-work.md) | 17 common mistakes and fixes |

---

## Critical Quick Reference

### GUI Coordinate System

```
FS25 uses BOTTOM-LEFT origin:
    ┌─────────────────────────┐
    │                         │  Y increases ↑
    │      Y = 600px (TOP)    │
    │                         │
    │      Y = 300px (MID)    │
    │                         │
    │      Y = 0px (BOTTOM)   │
    └─────────────────────────┘
         X = 0    X increases →
```

### Top 5 Pitfalls

| Don't Use | Use Instead | Why |
|:---------:|:-----------:|-----|
| `os.time()` | `g_currentMission.time` | Sandboxed Lua |
| `goto` / `::label::` | `if not then` | Lua 5.1 only |
| `Slider` widgets | `MultiTextOption` | Unreliable events |
| `DialogElement` | `MessageDialog` | Rendering issues |
| `g_gui:showYesNoDialog()` | `YesNoDialog.show()` | Doesn't exist |

### Key Globals

```lua
g_currentMission     -- Current game session
g_server             -- Server instance (nil on client)
g_client             -- Client instance
g_farmManager        -- Farm data access
g_storeManager       -- Shop/store items
g_vehicleTypeManager -- Vehicle type registry
g_gui                -- GUI system
g_i18n               -- Localization
g_messageCenter      -- Event pub/sub system
```

### Common MessageTypes

```lua
MessageType.HOUR_CHANGED    -- Every game hour
MessageType.DAY_CHANGED     -- Every game day
MessageType.PERIOD_CHANGED  -- Season change
MessageType.YEAR_CHANGED    -- New year
MessageType.MONEY_CHANGED   -- Farm money changes
```

---

## Source Attribution

This documentation was built by analyzing patterns from community mods:

**Primary References:**
- `FS25_EnhancedLoanSystem` — Loan/credit patterns
- `FS25_BuyUsedEquipment` — Used vehicle marketplace
- `FS25_SellVehicles` — Vehicle sales
- `FS25_TradeIn` — Trade-in mechanics

**Secondary References:**
- `FS25_AutomaticCarWash` — Trigger patterns
- `FS25_AnimalsDisplay` — HUD framework
- `FS25_LiquidFertilizer` — Production patterns
- `FS25_betterLights` — Animation patterns

---

## Contributing

Found a pattern? Discovered a pitfall the hard way?

1. Check if relevant doc file exists
2. Add pattern with validation status badge
3. Include source mod reference if not from UsedPlus
4. Always include: complete example + common pitfalls

---

## License

This documentation is provided freely to the FS25 modding community.
**Use it, share it, improve it.**

---

<div align="center">

Created with **Claude AI** (Anthropic) as part of **UsedPlus** mod development

*Last Updated: 2026-01-17 · UsedPlus v2.6.2*

</div>
