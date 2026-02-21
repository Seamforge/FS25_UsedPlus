# FS25_UsedPlus - Cross-Mod Compatibility Guide

**Last Updated:** 2026-02-21
**Version:** 2.15.2

This document analyzes compatibility between UsedPlus and popular FS25 mods that players commonly run together.

---

## Quick Reference

| Mod | Status | Summary |
|-----|--------|---------|
| **CrudeOilProduction** | COMPATIBLE | Pure production mod, no conflicts |
| **SpecialOffers** | COMPATIBLE | Notification utility, no conflicts |
| **Real Vehicle Breakdowns** | DEEPLY INTEGRATED | DNA affects part lifetimes, workshop injection, OBD display |
| **Use Up Your Tyres** | DEEPLY INTEGRATED | Quality/DNA affects wear rate, two-way sync, per-wheel display |
| **EnhancedLoanSystem** | INTEGRATED | ELS loans display in Finance Manager with Pay Early support |
| **Better Contracts** | INTEGRATED | BC farmland discounts applied in purchase dialog |
| **BuyUsedEquipment** | COMPATIBLE | UsedPlus hides search button when BUE detected |
| **HirePurchasing** | INTEGRATED | HP leases display in Finance Manager |
| **AdvancedMaintenance** | NOT RECOMMENDED | Conflicts with UsedPlus maintenance systems |
| **Employment** | INTEGRATED | Worker wages included in monthly obligations |

---

## Fully Compatible Mods

### CrudeOilProduction

**Status:** FULLY COMPATIBLE

**What it does:** Adds crude oil extraction and refining production chain (oil wells, refineries, selling stations). Pure XML-defined placeable mod with no Lua scripts.

**Why it works:**
- No game hooks or function overrides
- Adds new placeables that can be financed through UsedPlus
- New vehicles integrate with UsedPlus used market naturally
- Different systems - no overlap

**Synergies:**
- Finance oil infrastructure with UsedPlus loans
- Oil equipment creates income to pay off loans
- Higher upkeep costs create financial pressure (realistic gameplay)

---

### SpecialOffers

**Status:** FULLY COMPATIBLE

**What it does:** Notification utility that alerts players when new vehicles appear in the shop sale system.

**Why it works:**
- Read-only access to shop data
- No function hooks or overrides
- Only subscribes to `HOUR_CHANGED` event (safe - multiple subscribers allowed)
- Creates only its own `SpecialOffers.*` namespace

**Synergies:**
- Get notified when new used vehicles appear
- Then finance them through UsedPlus

---

## Deeply Integrated Mods

### Real Vehicle Breakdowns (RVB)
**Author:** MathiasHun

**Status:** DEEPLY INTEGRATED (v2.1.0+)

**What it does:** Comprehensive vehicle breakdown simulation tracking 10+ parts with operating hours and failure states.

**How UsedPlus integrates:**

#### DNA System Integration (v2.6.0+)
- **Legendary Immunity** - Vehicles with DNA 0.90+ are IMMUNE to RVB repair degradation
- **Workhorse Bonus** - DNA 0.70-0.89 vehicles experience reduced part wear
- **Lemon Penalty** - DNA 0.00-0.29 vehicles degrade faster through RVB

#### Symptoms Before Failure Philosophy
- **UsedPlus = Journey** - Gradual symptoms warn players BEFORE catastrophic failure
- **RVB = Destination** - Final catastrophic failure when parts exhausted
- **Reliability Derivation** - UsedPlus reads RVB part health to calculate symptom severity

#### Workshop Dialog Integration (v2.1.0+)
- **Unified Workshop Experience** - When RVB is installed, UsedPlus hides its own Inspect button (RVB replaces it with their Workshop button)
- **Data Injection** - UsedPlus injects its unique data into RVB's Workshop Dialog left pane:
  - "— UsedPlus —" section divider
  - Hydraulic System: XX% (unique - RVB doesn't track hydraulics)
  - Maintenance Grade: Excellent/Good/Fair/Poor/Critical
  - Service History: X repairs, Y breakdowns (if notable)
- **Visual Consistency** - Uses RVB's row templates for matching fonts and colors

#### OBD Scanner Enhancement (v2.0.0+)
- **Activation Prompt** - Shows "Use OBD Scanner - Tractor (RVB)" when RVB issues detected
- **Part Status Display** - Shows individual RVB part statuses:
  - Engine, Thermostat (engine system)
  - Generator, Battery, Starter, Glow Plug (electrical system)
- **Fault Indicators** - Parts showing "FAULT" (red) or "!" prefault warning (orange)
- **Fault Counter** - Total number of active faults across all RVB parts

#### OBD Scanner Multi-Mode (v2.7.0+)
- **RVB System Analysis Mode** - Dedicated mode for detailed RVB part inspection
- **Only visible when RVB installed** - Mode button hidden entirely without RVB

#### Holistic Used Vehicle Inspection (v2.1.0+)
- **Pre-Generated Part Data** - When agent finds used vehicle, RVB-compatible parts are generated:
  - Engine, Thermostat, Generator, Battery, Starter, Glow Plug
  - Each part has "life" percentage based on vehicle condition with realistic variance
- **Inspection Report Display** - Shows "COMPONENT STATUS" section with 6 parts in 3 columns
- **Purchase Initialization** - When player buys, RVB operating hours match inspection data
- **Deferred Sync** - If player buys without RVB then later installs it, data auto-syncs

#### Service Button Integration (v2.5.1+)
When player uses RVB's "Service" button:
- RVB's original service runs (resets RVB part wear)
- **UsedPlus fluids topped up** - Oil and hydraulic fluid restored to 100%
- **Minor leaks fixed** - Oil/hydraulic leak states cleared
- **Small reliability boost** - +3% hydraulic, +1.5% engine reliability

**Feature Responsibility Table:**
| Feature | Who Handles It |
|---------|---------------|
| Progressive speed limiting | UsedPlus (uses RVB engine health) |
| First-start stalling | UsedPlus (uses RVB engine health) |
| Hydraulic drift | UsedPlus only (unique feature) |
| Steering pull | UsedPlus only (unique feature) |
| Runaway Engine | UsedPlus (requires low oil + hydraulic) |
| Implement Stuck/Pull/Drag | UsedPlus |
| Final engine failure | RVB (7 km/h cap when part exhausted) |
| Final electrical failure | RVB (lights/starter fail) |
| Flat tire trigger | RVB (via UYT integration) |
| Workshop Inspect button | RVB (UsedPlus hides its button) |
| RVB Service button | RVB + UsedPlus fluids |
| RVB Repair button | Opens UsedPlus RepairDialog |
| RVB Workshop vehicle info | UsedPlus injects |
| OBD Part Detail Display | UsedPlus |
| OBD RVB Analysis Mode | UsedPlus (v2.7.0+) |

---

### Use Up Your Tyres (UYT)
**Author:** 50keda

**Status:** DEEPLY INTEGRATED (v2.3.0+)

**What it does:** Distance-based tire wear system with visual progression and friction reduction.

#### Two-Way Sync (v2.3.0+)
- **UsedPlus → UYT** - TiresDialog replacement resets UYT's distance tracking
- **UYT → UsedPlus** - UsedPlus reads UYT wear data for condition displays

#### Quality Affects UYT Wear Rate
| Tier | Cost | Traction | Wear Rate | Initial State | Effective Life |
|------|------|----------|-----------|---------------|----------------|
| Retread | 40% | 85% | 2x faster | +35% worn | ~32% of Normal |
| Normal | 100% | 100% | 1x | Fresh | 100% baseline |
| Quality | 150% | 110% | 0.67x | -15% bonus | ~172% of Normal |

*5x life difference between cheapest and best options!*

#### DNA Affects UYT Wear Rate
- Lemons (low DNA): 1.4x wear rate (harder on tires)
- Workhorses (high DNA): 0.6x wear rate (gentler driving)

#### UYT Wear Influences Flat Probability
- 0% UYT wear: 1x flat chance (baseline)
- 100% UYT wear: 3x flat chance (worn tires more likely to fail)
- Note: UYT itself has no flat tires - UsedPlus adds this as a complementary feature

#### Per-Wheel Display
When UYT installed, TiresDialog shows:
- FL/FR/RL/RR individual conditions
- "Worst" tire indicator
- Condition label changes to "Tire Wear (UYT):"

#### OBD Scanner Enhancement (v2.0.0+)
- **Activation Prompt** - Shows "Use OBD Scanner - Tractor (Tires)" when >80% tire wear
- **Tire Wear Display** - Shows FL, FR, RL, RR conditions
- **Worst Indicator** - Highlights the most worn tire

#### OBD Scanner Tire Service Mode (v2.7.0+)
- **Dedicated mode** for tire inspection and service
- Per-wheel condition display with service options

#### Holistic Used Vehicle Inspection (v2.1.0+)
- **Pre-Generated Tire Data** - FL, FR, RL, RR conditions generated for used vehicles
- **Front Tire Bias** - Front tires generated with higher wear (simulates steering wear)
- **Purchase Initialization** - UYT wheel wear matches inspection data after purchase
- **Deferred Sync** - Auto-syncs if UYT installed later

**Feature Responsibility Table:**
| Feature | Who Handles It |
|---------|---------------|
| Tire wear calculation | Both: UYT (distance) + UsedPlus (quality/DNA multipliers) |
| Visual tire degradation | UYT (shader-based) |
| Tire condition display | UsedPlus (synced from UYT) |
| Flat tire trigger | UsedPlus (UYT doesn't have flats) |
| Low traction warning | UsedPlus |
| Tire replacement (shop) | UYT (workshop button) |
| Tire replacement (UsedPlus) | UsedPlus (syncs to UYT) |
| TiresDialog per-wheel display | UsedPlus |
| Quality wear multiplier | UsedPlus |
| DNA wear multiplier | UsedPlus |
| OBD Tire Detail Display | UsedPlus |
| OBD Tire Service Mode | UsedPlus (v2.7.0+) |

---

## Integrated Mods (Feature Deferral)

These mods are fully compatible with UsedPlus automatically deferring specific features to avoid conflicts.

### EnhancedLoanSystem (ELS)

**Status:** INTEGRATED (v1.8.2+)

**What it does:** Replaces vanilla loan system with annuity-based loans featuring collateral requirements, variable interest rates, and monthly payments.

**How UsedPlus integrates:**
- **Detection:** `g_els_loanManager ~= nil`
- **Finance Manager Display** - ELS loans appear with "ELS" type marker
- **Pay Early Button** - Make payments on ELS loans directly from UsedPlus
- **Monthly Totals** - ELS loan payments included in monthly obligations
- **Debt Totals** - ELS loan balances included in total debt
- **Take Loan button** - Hidden (ELS handles loan creation)

**Feature Responsibility:**
| Feature | Who Handles It |
|---------|---------------|
| Cash loans (creation) | ELS |
| Loan display in Finance Manager | UsedPlus (reads ELS data) |
| Loan payments via Pay Early | UsedPlus (calls ELS API) |
| Vehicle financing | UsedPlus |
| Vehicle leasing | UsedPlus |
| Used vehicle search | UsedPlus |
| Agent-based sales | UsedPlus |
| Credit scoring | Both (independent) |

---

### Better Contracts (BC)
**Author:** Mmtrx

**Status:** INTEGRATED (v2.15.2+)

**What it does:** Enhanced contract management with farmland purchase discounts. Players who complete contracts for NPCs earn cumulative discounts on that NPC's farmland (default: 5% per job, up to 25% max).

**How UsedPlus integrates:**
- **Detection:** `BetterContracts ~= nil`
- **Farmland Discounts** - Reads BC's earned discount data (`farm.stats.npcJobs[npcIndex]`)
- **Purchase Dialog** - Shows "Contract Discount" row with amount, percentage, and jobs completed
- **Price Flow** - BC discount applied FIRST (vendor loyalty), then credit adjustment (bank risk)
- **Respects BC Config** - Uses BC's `discountMode`, `discPerJob`, and `discMaxJobs` settings

**Feature Responsibility:**
| Feature | Who Handles It |
|---------|---------------|
| Contract management | BC |
| NPC job tracking | BC (persists on `farm.stats.npcJobs`) |
| Farmland discount calculation | BC (config) + UsedPlus (applies in dialog) |
| Land purchase dialog | UsedPlus |
| Land financing/leasing | UsedPlus |
| Credit score adjustment | UsedPlus |

**Note:** When UsedPlus's shop override is disabled (`overrideShopBuyLease=false`), BC's own discount logic handles the vanilla buy button directly. The integration only matters when UsedPlus intercepts the farmland buy flow.

---

### BuyUsedEquipment (BUE)

**Status:** COMPATIBLE (v1.8.1+)

**What it does:** Broker-based used equipment search where players pay a fee, wait for success rolls, and find vehicles in the vanilla shop's Sales tab.

**How UsedPlus handles compatibility:**
- **Detection:** `BuyUsedEquipment ~= nil`
- **Search Used button** - Hidden from shop when BUE detected
- **UsedVehicleManager** - Still initializes (for agent-based selling)
- **Financing** - Still works for all purchases including BUE finds

**Feature Responsibility:**
| Feature | Who Handles It |
|---------|---------------|
| Used vehicle search | BUE |
| Search button in shop | BUE |
| Vehicle financing | UsedPlus |
| Vehicle leasing | UsedPlus |
| Agent-based sales | UsedPlus |
| Maintenance & symptoms | UsedPlus |

---

### HirePurchasing (HP)

**Status:** INTEGRATED (v1.8.2+)

**What it does:** Hire purchase financing with deposit requirements, 1-10 year terms, and optional balloon payments.

**How UsedPlus integrates:**
- **Detection:** `g_currentMission.LeasingOptions ~= nil`
- **Finance Manager Display** - HP leases appear with "HP" type marker
- **Info Dialog** - Click Pay Early on HP leases to see details
- **Monthly Totals** - HP lease payments included in monthly obligations
- **Debt Totals** - HP lease balances included in total debt
- **Finance button** - Hidden from shop (HP handles financing)

**Note:** HP manages lease payments automatically each hour. UsedPlus displays HP leases for visibility but doesn't process HP payments directly.

---

### Employment

**Status:** INTEGRATED (v1.8.2+)

**What it does:** Adds worker hiring system with wages and productivity bonuses.

**How UsedPlus integrates:**
- **Detection:** `g_currentMission.employmentSystem ~= nil`
- **Monthly Totals** - Worker wages automatically included in monthly obligations
- **Visual Indicator** - Asterisk (*) shown when wages are included
- **Budget Planning** - See true monthly costs including labor

**Financial Clarity:**
When Employment mod is installed, monthly obligations include:
- Loan payments (UsedPlus + ELS)
- Lease payments (UsedPlus + HP)
- Worker wages (Employment)

---

## Not Recommended

### AdvancedMaintenance (AM)

**Status:** NOT RECOMMENDED

**What it does:** Prevents engine start at 0% damage and causes random shutdowns when damage exceeds 28%.

**Why it's not recommended:**
- Both mods track vehicle condition independently
- Can cause inconsistent behavior where UsedPlus shows one state, AM shows another
- Maintenance features overlap significantly
- **Recommendation:** Use one or the other, not both

---

## Technical Details

### Detection Methods

```lua
-- Deeply integrated mods
ModCompatibility.rvbInstalled = g_currentMission.vehicleBreakdowns ~= nil
ModCompatibility.uytInstalled = UseYourTyres ~= nil

-- Integrated mods (feature deferral)
ModCompatibility.hirePurchasingInstalled = g_currentMission.LeasingOptions ~= nil
ModCompatibility.buyUsedEquipmentInstalled = BuyUsedEquipment ~= nil
ModCompatibility.enhancedLoanSystemInstalled = g_els_loanManager ~= nil
ModCompatibility.betterContractsInstalled = BetterContracts ~= nil
ModCompatibility.employmentInstalled = g_currentMission.employmentSystem ~= nil
```

### Feature Availability Queries

```lua
ModCompatibility.shouldShowFinanceButton()    -- false if HP detected
ModCompatibility.shouldShowSearchButton()     -- false if BUE detected
ModCompatibility.shouldShowTakeLoanOption()   -- false if ELS detected
ModCompatibility.shouldEnableLoanSystem()     -- false if ELS detected
```

### Data Access Functions

```lua
-- ELS Integration
ModCompatibility.getELSLoans(farmId)
ModCompatibility.payELSLoan(pseudoDeal, amt)

-- HP Integration
ModCompatibility.getHPLeases(farmId)
ModCompatibility.settleHPLease(pseudoDeal)

-- BC Integration (v2.15.2)
ModCompatibility.getBCFarmlandDiscount(farmland, farmId)

-- Employment Integration
ModCompatibility.getEmploymentMonthlyCost(playerId)

-- Farmland Integration
ModCompatibility.getFarmlandValue(farmId)
ModCompatibility.getFarmlandCount(farmId)

-- Aggregate Functions
ModCompatibility.getExternalMonthlyObligations(farmId)
ModCompatibility.getExternalTotalDebt(farmId)
```

---

## Recommended Mod Setups

### Best Experience
- **UsedPlus** (financial system, maintenance, marketplace)
- **Real Vehicle Breakdowns** (catastrophic failures - integrates with DNA)
- **Use Up Your Tyres** (visual tire wear - integrates with quality tiers)
- **Employment** (worker management with wages in Finance Manager)

### Full Financial Suite
- **UsedPlus** + **EnhancedLoanSystem** + **HirePurchasing** + **Better Contracts** + **Employment**
- Unified Financial Dashboard showing all obligations
- BC farmland discounts applied in UsedPlus purchase dialog
- Each mod handles its specialty, UsedPlus provides the unified view

### Production Focus
- **UsedPlus** (financing for expensive equipment)
- **CrudeOilProduction** (production chain)
- **SpecialOffers** (shop notifications)

---

## Settings

All mod integrations can be individually toggled in:
**ESC > Settings > UsedPlus > Mod Compatibility**

---

## Version History

**2026-02-21 (v2.15.2)** - Better Contracts Integration
- Added Better Contracts (BC) farmland discount integration
- BC discounts applied in land purchase dialog before credit adjustment
- Shows discount amount, percentage, and jobs completed in dialog
- Integration toggle in Settings > Mod Compatibility
- Respects BC's discountMode, discPerJob, and discMaxJobs config

**2026-01-17 (v2.6.3)** - Documentation Update
- Updated OBD Scanner multi-mode integration details
- Added DNA system integration with RVB
- Updated AdvancedMaintenance status to "NOT RECOMMENDED"
- Reorganized document structure for clarity

**2026-01-11 (v2.5.1)** - RVB Service Button Integration
- RVB Service button now tops up UsedPlus fluids
- Minor leaks fixed during RVB service

**2026-01-11 (v2.3.0)** - UYT Deep Integration
- Two-way sync for tire replacement
- Quality tiers affect UYT wear rate
- DNA affects tire wear rate
- Per-wheel display in TiresDialog

**2026-01-10 (v2.1.0)** - RVB Workshop & Holistic Inspection
- UsedPlus data injected into RVB Workshop Dialog
- Pre-generated part data for used vehicles
- InspectionReportDialog shows component/tire status

**2026-01-05 (v2.0.0)** - OBD Scanner Enhancement
- RVB part status in OBD Scanner
- UYT tire wear in OBD Scanner
- Per-wheel breakdown display

**2025-12-28 (v1.8.2)** - Deep Integration
- ELS/HP loans display in Finance Manager
- Pay Early works with ELS API
- Employment wages in monthly totals
