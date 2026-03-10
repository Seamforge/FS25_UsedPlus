# Hook Architecture Audit — FS25_UsedPlus

**Date:** 2026-03-09
**Context:** Issue #21 analysis revealed systemic risk from the mod's function hooking strategy. This document catalogs every hook, classifies risk, and outlines mitigation options.

---

## Executive Summary

FS25_UsedPlus installs **~60 function hooks/overrides** across **20 files** to intercept game behavior for financing, marketplace, repair, and RVB integration. Most hooks (~55) are **chain-safe** (they store and call the original function), but the sheer volume creates collision risk at high mod counts. The RVB integration layer alone accounts for 14 hooks across 5 files, with a 3-level deep hook chain on `g_gui.showDialog`.

**Key risk:** With 1400+ mods loaded (as reported in Issue #21), hook ordering becomes non-deterministic. Direct function replacement hooks follow a "last writer wins" pattern — if another mod hooks the same function after UsedPlus, UsedPlus's hook is orphaned. If UsedPlus hooks after another mod, that mod's hook is orphaned.

---

## Hook Patterns Used

| Pattern | Count | Mechanism | Chain Safety |
|---------|-------|-----------|-------------|
| Direct replacement (`X.fn = function(...)`) | ~25 | Stores original in local/field, replaces function | Depends on implementation |
| `Utils.overwrittenFunction` | ~11 | FS25 official override — passes `superFunc` | YES (by design) |
| `Utils.appendedFunction` | ~22 | FS25 official append — original runs first | YES (by design) |
| `Utils.prependedFunction` | ~2 | FS25 official prepend — hook runs first | YES (by design) |
| **Total** | **~60** | | **~55 chain-safe** |

**The `Utils.*` hooks are safe by design** — FS25's framework manages the chain. The risk concentrates in the **~25 direct replacement hooks**, which bypass the framework and manage their own chains.

---

## Hooks by File

### Core System (7 hooks)

**src/main.lua** — 7 hooks
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 147 | `Mission00.loadMission00Finished` | appended | YES | Initialize UsedPlus on mission load |
| 225 | `Mission00.onStartMission` | appended | YES | Load savegame data after mission starts |
| 526 | `FSCareerMissionInfo.saveToXMLFile` | appended | YES | Save finance data to savegame |
| 574 | `Farm.new` | direct (stored) | YES | Add finance data structures to Farm |
| 591 | `Farm.loadFromXMLFile` | direct (stored) | YES | Load finance data from savegame |
| 594 | `Farm.saveToXMLFile` | appended | YES | Persist farm-specific data |
| 675 | `Mission00.delete` | prepended | YES | Cleanup before mission unload |

### Vehicle System (5 hooks)

**src/extensions/VehicleExtension.lua** — 2 hooks
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 32 | `Vehicle.getSellPrice` | overwritten | YES | Deduct finance balance from sell price |
| 38 | `Vehicle.sell` | overwritten | YES | Block selling leased/financed vehicles |

**src/extensions/VehicleInfoExtension.lua** — 1 hook
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 182 | `Vehicle.showInfo` | appended | YES | Show finance/lease info in tooltip |

**src/extensions/BuyVehicleDataExtension.lua** — 2 hooks
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 120 | `FSBaseMission.onVehicleBought` | appended | YES | Track purchased vehicles |
| 129 | `Vehicle.onLoadFinished` | appended | YES | Track newly loaded vehicles |

### Shop & Purchase (8 hooks)

**src/extensions/ShopConfigScreenExtension.lua** — 6 hooks
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 217 | `ShopConfigScreen.setStoreItem` | overwritten | YES | Show/hide UsedPlus buttons |
| 298 | `buyButton.onClickCallback` | direct (swap) | N/A | Finance new vehicle purchases |
| 350 | `leaseButton.onClickCallback` | direct (swap) | N/A | Lease new vehicles |
| 375 | `financeButton.onClickCallback` | direct | N/A | Custom button — no original |
| 404 | `tiresButton.onClickCallback` | direct | N/A | Custom button — no original |
| 435 | `searchButton.onClickCallback` | direct | N/A | Custom button — no original |

**src/extensions/BuyPlaceableDataExtension.lua** — 1 hook
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 279 | `BuyPlaceableData.buy` | overwritten | YES | Finance placeable purchases |

**src/extensions/PlaceableSystemExtension.lua** — 2 hooks (1 appended, 1 prepended — rare pattern)
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 392 | `Placeable.finalizePlacement` | appended | YES | Track placeable for finance |
| 404 | `Placeable.delete` | prepended | YES | Cancel finance before deletion |

### Farmland (3 hooks)

**src/extensions/FarmlandManagerExtension.lua** — 3 hooks
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 30 | `FarmlandScreen.onClickBuyLand` | overwritten | YES | Show land purchase dialog |
| 37 | `FarmlandManager.buyFarmland` | overwritten | YES | Handle financed land purchase |
| 42 | `FarmlandManager.sellFarmland` | overwritten | YES | Check finance deals on sale |

### Menu System (14 hooks)

**src/extensions/InGameMenuVehiclesFrameExtension.lua** — 9 hooks
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 98 | `YesNoDialog.show` | direct (stored) | YES | Intercept sell confirmations |
| 243 | `InGameMenuVehiclesFrame.onFrameOpen` | appended | YES | Hook vehicle frame open |
| 257 | `InGameMenuVehiclesFrame.updateMenuButtons` | appended | YES | Update menu buttons |
| 268 | `InGameMenuVehiclesFrame.onListSelectionChanged` | appended | YES | Track selected vehicle |
| 400 | `Vehicle.getName` | direct (stored) | YES | Add lease/finance indicators |
| 461 | `InGameMenuVehiclesFrame.onClickSell` | direct (stored) | YES | Custom sell dialog |
| 472 | `InGameMenuVehiclesFrame.onButtonSell` | direct (stored) | YES | Alternative sell handler |
| 487 | `InGameMenuVehiclesFrame.inputEvent` | direct (stored) | YES | Intercept sell keybind |
| 1216 | `InGameMenu.onOpen` | overwritten | YES | Main menu integration |

**src/extensions/InGameMenuMapFrameExtension.lua** — 2 hooks
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 173 | `InGameMenuMapFrame.onLoadMapFinished` | overwritten | YES | Handle map loading |
| 182 | `InGameMenuMapFrame.setMapInputContext` | overwritten | YES | Map input context |

**src/extensions/FinanceMenuExtension.lua** — 1 hook
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 50 | `InGameMenuStatisticsFrame.hasPlayerLoanPermission` | overwritten | YES | Disable vanilla borrowing |

**src/gui/UsedPlusSettingsMenuExtension.lua** — 2 hooks
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 984 | `InGameMenuSettingsFrame.onFrameOpen` | appended | YES | Add settings UI |
| 990 | `InGameMenuSettingsFrame.updateGameSettings` | appended | YES | Update settings display |

### Workshop & Selling (5 hooks)

**src/extensions/WorkshopScreenExtension.lua** — 3 hooks
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 71 | `WorkshopScreen.onOpen` | appended | YES | Add inspect/sell buttons |
| 80 | `WorkshopScreen.setVehicle` | appended | YES | Update buttons on vehicle change |
| 155 | `sellButton.onClickCallback` | direct (stored) | YES | Custom sell dialog |

**src/extensions/VehicleSellingPointExtension.lua** — 6 hooks
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 336 | `g_gui.showYesNoDialog` | direct (stored) | YES | Intercept repair/repaint dialogs |
| 502 | `WorkshopScreen.onOpen` | appended | YES | Store workshop reference |
| 521 | `WorkshopScreen.onClose` | appended | YES | Clear workshop reference |
| 563 | **`g_gui.showDialog`** | direct (stored) | YES | **Intercept SellItemDialog** |
| 1118 | `Mission00.onStartMission` | appended | YES | Install sale hooks |

### RVB Integration (14 hooks across 5 files) — HIGHEST RISK ZONE

**src/extensions/RVBWorkshopIntegration.lua** — 2 hooks
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 83 | **`g_gui.showDialog`** | direct (stored) | YES | Detect RVB workshop dialog open |
| 163 | `dialogClass.updateScreen` | direct (stored) | YES | Inject UsedPlus data into RVB |

**src/extensions/rvb/RVBRepairButton.lua** — 3 hooks
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 46 | `dialog.onClickRepair` | direct (metatable walk) | **NO** | Redirect to hydraulic repair |
| 80 | `dialog.repairButton.onClickCallback` | direct (stored) | YES | Hydraulic repair bypass |
| 129 | `dialog.onYesNoRepairDialog` | direct (metatable walk) | YES | Boost reliability after repair |

**src/extensions/rvb/RVBInspectionButton.lua** — 4 hooks
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 23 | `dialog.onClickInspection` | direct (metatable walk) | **NO** | Redirect to enhanced inspection |
| 54 | `dialog.inspectionButton.onClickCallback` | direct | YES | Button click handler |
| 63 | `dialog.onClickService` | direct (metatable walk) | **NO** | Redirect to enhanced service |
| 86 | `dialog.serviceButton.onClickCallback` | direct | YES | Button click handler |

**src/extensions/rvb/RVBDiagnostics.lua** — 4 hooks
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 251 | `dialog.getNumberOfItemsInSection` | direct (stored) | YES | +1 count for hydraulic item |
| 264 | `dialog.populateCellForItemInSection` | direct (stored) | YES | Populate hydraulic cell |
| 340 | `vehicle.setPartsRepairreq` | direct (stored) | YES | Intercept repair state toggle |
| 363 | `vehicle.getRepairPrice_RVBClone` | direct (stored) | YES | Include hydraulic cost |

**src/extensions/rvb/RVBServiceHooks.lua** — 1 hook
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 29 | `dialog.onYesNoServiceDialog` | direct (stored) | YES | Handle service confirmation |

### Misc (2 hooks)

**src/extensions/FarmExtension.lua** — 2 hooks
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 381 | `Mission00.loadMission00Finished` | appended | YES | Initialize farm extension |
| 388 | `Mission00.delete` | appended | YES | Cleanup on unload |

**src/managers/DifficultyScalingManager.lua** — 2 hooks
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 66 | `FSBaseMission.setEconomicDifficulty` | appended | YES | Recalculate on difficulty change |
| 111 | `FarmlandManager.getPricePerHa` | overwritten | **NO** | Replace farmland pricing (ignores superFunc) |

**src/managers/UsedVehicleManager.lua** — 1 hook
| Line | Target | Pattern | Chain-Safe | Purpose |
|------|--------|---------|-----------|---------|
| 572 | `BuyVehicleData.onBought` | appended | YES | Track used vehicle purchases |

---

## Risk Analysis

### High-Risk Hooks (Collision-Prone)

These hooks target **global game functions** that other mods are also likely to hook:

| Hook Target | File(s) | Why It's Risky |
|-------------|---------|---------------|
| **`g_gui.showDialog`** | VehicleSellingPointExtension (line 563), RVBWorkshopIntegration (line 83) | Hooked TWICE by this mod alone. Intercepts ALL dialog opens. Any mod that also hooks this creates a chain conflict. |
| **`g_gui.showYesNoDialog`** | VehicleSellingPointExtension (line 336) | Common hook target for mods that modify confirmation dialogs. |
| **`YesNoDialog.show`** | InGameMenuVehiclesFrameExtension (line 98) | Static function — direct replacement, last writer wins. |
| **`Vehicle.getName`** | InGameMenuVehiclesFrameExtension (line 400) | Extremely common hook target — any mod adding vehicle name decorations will conflict. |
| **`Vehicle.sell`** | VehicleExtension (line 38) | Other finance/economy mods likely hook this too. |
| **`Vehicle.getSellPrice`** | VehicleExtension (line 32) | Same concern as `Vehicle.sell`. |

### Chain-Unsafe Hooks (Don't Call Original)

These hooks **replace behavior entirely** rather than extending it:

| Hook | File:Line | Impact |
|------|-----------|--------|
| `dialog.onClickRepair` | RVBRepairButton.lua:46 | RVB's repair click is fully replaced — if RVB updates its internal logic, this won't adapt |
| `dialog.onClickInspection` | RVBInspectionButton.lua:23 | Same — full replacement |
| `dialog.onClickService` | RVBInspectionButton.lua:63 | Same — full replacement |
| `FarmlandManager.getPricePerHa` | DifficultyScalingManager.lua:111 | Ignores `superFunc` — any other mod's pricing changes are lost |

### The `g_gui.showDialog` Chain Problem

This is the most dangerous hook in the mod. It's hooked twice:

```
Game's original g_gui.showDialog
    └─ VehicleSellingPointExtension hooks it (line 563), stores original
        └─ RVBWorkshopIntegration hooks it (line 83), stores VSE's version as "original"
```

When RVBWorkshopIntegration calls its stored "original," it actually calls VehicleSellingPointExtension's hook, which calls the real original. This works **as long as no other mod inserts into the chain.** With 1400 mods, any mod that hooks `g_gui.showDialog` after UsedPlus loads will overwrite RVBWorkshopIntegration's hook, breaking the chain.

---

## Issue #21 Connection

The infinite save loop reported in Issue #21 traces back to this hook architecture:

1. RVB integration hooks fire during vehicle state operations
2. `RVBWorkshopIntegration.previousFaultStates` stores unbounded vehicle references
3. During save serialization, these hooks/state can re-trigger operations
4. The reporter confirmed: **disabling RVB compatibility option eliminates the save loop**

The v2.15.1.18 fix addressed ServiceTruck schema issues (real but unrelated bugs). The actual save loop was caused by the RVB hook layer's interaction with the save system.

---

## Mitigation Options

### Short-Term (Issue #21 Fix)
- **Re-entry guard on RVB hooks during save** — set a flag before save begins, skip RVB hook logic while saving
- **Clear `previousFaultStates` before save** — prevent stale vehicle references from causing re-triggers

### Medium-Term (Reduce Risk)
- **Consolidate `g_gui.showDialog` hooks** — merge VehicleSellingPointExtension and RVBWorkshopIntegration into a single hook point with a dispatch table
- **Move from direct replacement to `Utils.overwrittenFunction`** where possible — the framework handles chain management
- **Add hook installation logging** — log when each hook installs and what "original" it captured, so chain breaks are diagnosable

### Long-Term (Architecture)
- **Reduce total hook count** — some hooks may be consolidatable (e.g., the 3 `WorkshopScreen` hooks could be a single extension class)
- **Event-based patterns** — where FS25 provides events/callbacks, prefer those over function replacement
- **Hook health check on load** — after all mods load, verify that critical hooks are still pointing to UsedPlus's functions (detect if another mod overwrote them)
