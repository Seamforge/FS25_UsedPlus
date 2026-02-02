# FS25_UsedPlus - Complete Feature List

A comprehensive finance, maintenance, and marketplace overhaul for Farming Simulator 25.

---

## CREDIT & FINANCE SYSTEM

### FICO-Style Credit Scoring
* Dynamic credit scores ranging from 300 to 850, modeled after real-world FICO scoring
* Starting score of 500 for new players
* Payment history is the primary factor (up to +250 points)
* Five credit tiers: Excellent (750+), Good (700-749), Fair (650-699), Poor (550-649), Very Poor (<550)
* Credit score directly impacts loan approval, interest rates, and available terms

### Credit Score Impact
* On-time payments gradually increase your credit score
* Missed payments cause rapid credit score drops
* Repossession events severely damage credit standing
* Full credit report available showing payment history and score breakdown

### Vehicle & Equipment Financing
* Finance any vehicle or equipment purchase (1-30 year terms)
* Interest rates based on credit score (lower score = higher rates)
* Monthly automatic payment processing
* Pay extra toward principal at any time
* Early payoff available with no prepayment penalty
* Full amortization schedule visible in deal details

### Building & Placeable Financing
* Finance sheds, silos, decorations, and all placeables (1-30 year terms)
* Requires minimum 750 credit score for building financing
* 20% down payment required on all placeable purchases
* Same credit-based interest rates as vehicle financing
* Seamless purchase flow: place building → choose Cash or Finance → confirm
* Transaction transparency with detailed notifications explaining finance flow
* Multiple buildings can be financed sequentially without issues

### Cash Loans with Collateral
* Take out general-purpose cash loans against your assets
* Use owned vehicles and equipment as collateral
* Loan amount limited by collateral value
* Collateral seizure if loan defaults after missed payments
* Multiple collateral items can secure a single loan

### Finance Repair & Repaint
* Finance the cost of repairs when short on cash
* Finance repaint costs with monthly payments
* Spread maintenance costs over time instead of paying upfront

---

## FARMLAND

### Land Leasing
* Lease farmland for 1, 3, 5, or 10-year terms
* Shorter terms have higher markup rates (20% for 1 year, 5% for 10 years)
* Monthly lease payments automatically deducted
* Expiration warnings at 3 months, 1 month, and 1 week before end
* Land reverts to NPC ownership upon lease expiration
* Lease renewal option available before expiration

### Land Financing
* Finance farmland purchases over extended terms
* Build equity while using the land
* Lower monthly payment compared to lease-to-own

### Lease Buyout
* Purchase leased land before term ends at discounted rate
* Longer lease terms earn bigger buyout discounts (up to 15% off)
* Credit toward purchase price based on payments already made

---

## VEHICLE MAINTENANCE SYSTEM

### Three-Component Reliability
* **Engine Health**: Affects power output, fuel efficiency, and starting reliability
* **Electrical Health**: Impacts lights, gauges, and electronic systems
* **Hydraulic Health**: Controls implement lift, steering assist, and attachments

### Hidden "DNA" Reliability Trait (Workhorse/Lemon Scale)
* Each vehicle has a hidden "DNA" score (0.0-1.0) assigned at spawn
* **Lemons (low DNA)**: Experience more frequent breakdowns, faster wear, and progressive degradation
* **Workhorses (high DNA)**: More reliable with slower degradation
* **Legendary Workhorses (DNA ≥ 0.90)**: IMMUNE to repair degradation - can last forever if maintained!
* Mechanic inspection hints at vehicle's reliability class via colorful quotes
* DNA affects initial RVB part lifetimes (0.6x-1.4x multiplier when RVB installed)

### Progressive Degradation System (v2.2.0)
* **Each repair permanently reduces max component durability** (lemons lose 0-2% per repair)
* **Each breakdown causes larger permanent damage** (3-8% depending on DNA)
* **Legendary workhorses are immune to repair degradation** - only breakdowns wear them down
* **Legendary workhorses (DNA ≥ 0.95) take only 30% breakdown damage**
* Creates a "death spiral" for lemons: more breakdowns → faster degradation → even more breakdowns
* Creates "immortality" for well-maintained workhorses: prevent breakdowns → zero degradation

### Tire System
* Three tire quality tiers with meaningful trade-offs:

| Tier | Cost | Traction | Failure Rate | Wear Rate | Initial State | Effective Life |
|------|------|----------|--------------|-----------|---------------|----------------|
| **Retread** | 40% | 85% | 3x | 2x faster | +35% worn | ~32% of Normal |
| **Normal** | 100% | 100% | 1x | 1x | Fresh (0%) | 100% baseline |
| **Quality** | 150% | 110% | 0.5x | 0.67x | -15% bonus | ~172% of Normal |

* **v2.3.0: Quality tiers create 5x life difference** between cheapest and best options
* **v2.3.0: DNA affects tire wear**: Lemons (1.4x) wear tires faster, Workhorses (0.6x) are gentler
* Tire tread wears over time based on usage and terrain
* Worn tires reduce traction and increase slip
* Flat tires cause steering pull toward the affected side
* Flat tires reduce maximum speed
* Low traction warnings in wet/icy conditions
* Tire service available to replace worn tires

### Fluid Systems
* **Engine Oil**: Depletes with use, low oil causes engine damage
* **Hydraulic Fluid**: Powers implements and steering, leaks cause system failures
* **Fuel**: Fuel leaks drain tank over time when detected
* Leak detection with dashboard warnings
* Fluid service dialog to refill oil and hydraulic fluid

### v2.5.2: Fluid-Malfunction Interaction
**Low fluid levels don't just cause damage - they make ALL related malfunctions worse!**

| Fluid | Affects | Effect at 20% Fluid |
|-------|---------|---------------------|
| **Oil** | Engine malfunctions | 2.6x more likely, 2.2x longer duration |
| **Hydraulic Fluid** | Hydraulic malfunctions | 2.6x more likely, 2.2x longer duration |

* Full fluid = no penalty (1.0x multiplier)
* 50% fluid = moderate penalty (~2.0x multiplier)
* 20% fluid = severe penalty (~2.6x multiplier)
* Empty fluid = maximum penalty (3.0x multiplier)

**Real-world basis:**
- Low oil makes engines run hotter, wear faster, and misfire more often
- Low hydraulic fluid causes cavitation, erratic pressure, and valve sticking
- A farmer who ignores "LOW FLUID" warnings will have a MUCH worse day!

### Mechanic Inspection
* Comprehensive inspection available at dealer or via agent
* Reveals component health percentages
* Shows tire condition and fluid levels
* Hints at hidden reliability trait
* Inspection history tracked per vehicle

### Repair & Maintenance
* Partial repairs available (fix just what you need)
* Partial repaints for cosmetic damage
* Repair history tracked as part of vehicle record
* Breakdown events logged for resale transparency

---

## VEHICLE MALFUNCTIONS

Real consequences for neglecting maintenance:

### Engine Malfunctions
* **Overheating**: Engine temperature rises, power reduces, eventual stall (v2.5.2: faster at low oil!)
* **Misfiring**: Random power fluctuations and rough running (v2.5.2: more frequent at low oil!)
* **Stalling**: Engine cuts out unexpectedly, restart required (v2.5.2: more likely at low oil!)
* **Hard Starting**: Difficulty starting in cold conditions with worn engine

All engine malfunctions are affected by oil level (v2.5.2)!

### Electrical Malfunctions
* **Electrical Cutout**: Temporary loss of electrical systems
* **Gauge Failures**: Instrument readings become unreliable
* **Light Flickering**: Headlights and work lights flicker or fail

### Hydraulic Malfunctions
* **Hydraulic Drift**: Implements slowly lower when raised (v2.5.2: faster at low fluid)
* **Hydraulic Surge**: Sudden steering loss for 5-15 seconds - requires active countersteering!
* **Implement Surge**: Sudden unexpected implement movements
* **PTO Toggle**: Power take-off randomly engages or disengages
* **Hitch Failure**: Attachments may unexpectedly disconnect

### v2.5.0: Advanced Hydraulic Malfunctions
* **Runaway Engine**: When BOTH oil AND hydraulic fluid drop below 10%, the speed governor fails! Vehicle accelerates uncontrollably up to 150% max speed. Brakes only 40% effective. Must turn off engine or crash to stop!
* **Implement Stuck Down**: Hydraulic lift failure - cannot raise lowered implement for 45+ seconds
* **Implement Stuck Up**: Hydraulic valve failure - cannot lower raised implement for 45+ seconds
* **Implement Pull**: Asymmetric drag causes steering to pull left or right
* **Implement Drag**: Hydraulic strain reduces max speed to 60% while working
* **Reduced Turning**: Power steering failure limits steering travel to 65%

All v2.5.0/v2.5.2 hydraulic malfunctions are affected by hydraulic fluid level!

### Tire Malfunctions
* **Flat Tire**: Sudden tire failure causing steering pull
* **Slow Leak**: Gradual pressure loss over time
* **Blowout**: High-speed tire failure

### Fuel System Malfunctions
* **Fuel Leak**: Tank slowly drains fuel when parked or running

---

## FIELD SERVICE KIT

Emergency repair system for disabled vehicles in the field. Designed as a **tactical tool** - use it wisely!

### OBD Diagnostic Scanner
* Portable diagnostic tool that connects to vehicle's OBD (On-Board Diagnostics) port
* Purchase from shop as a consumable hand tool ($5,000 for Basic kit)
* Carry to disabled vehicle and activate to begin diagnosis
* Scanner reads fault codes and sensor data from vehicle systems

### Diagnostic Minigame
* Choose which system to diagnose: Engine, Electrical, or Hydraulic
* Scanner displays 3 diagnostic readings (fault codes, sensor values, test results)
* Interpret readings to identify the root cause from 4 possible diagnoses
* Correct diagnosis = better repair outcome
* Tests your mechanical knowledge and deductive reasoning

### One-Time Diagnosis Limit (v2.8.0)
**Each system can only be diagnosed ONCE per vehicle:**
* Engine - one diagnostic boost available
* Electrical - one diagnostic boost available
* Hydraulic - one diagnostic boost available
* After use, message shows: "System already diagnosed - OBD boost exhausted"
* Prevents exploit of spam-buying kits for unlimited restoration
* **Seizure repair is separate** - fixing a seized component doesn't consume the diagnosis

### Reliability Caps (v2.8.0)
* **Field Repair Maximum**: 80% reliability (field repairs can't match workshop quality)
* **Vehicle Ceiling**: Also respects the vehicle's aging ceiling (`maxReliabilityCeiling`)
* **Effective Cap**: Uses whichever is lower - `min(80%, vehicleCeiling)`
* **Shop repair for more**: To exceed 80%, use workshop repair services

### Kit Tiers
* **Basic Kit** ($5,000): Standard OBD readings, 1.0x boost multiplier
* **Professional Kit** ($12,000): Enhanced diagnostics, 1.25x boost multiplier
* **Master Kit** ($25,000): Complete diagnostics, 1.5x boost multiplier

### Repair Outcomes
* **Perfect Diagnosis**: Correct system + correct cause = 8-15% boost (up to 22.5% with Master)
* **Good Diagnosis**: Correct system + wrong cause = 4-8% boost
* **Poor Diagnosis**: Wrong system entirely = 1-3% boost
* All boosts capped at 25% maximum, then subject to 80%/ceiling cap
* Vehicle is re-enabled regardless of outcome (you can limp home)

### Tire Repair Mode
* Emergency flat tire repair without needing a tow
* **Patch Repair** ($50): Moderate fix, 60% tread restored
* **Plug Repair** ($25): Quick fix, 40% tread restored

### Consumable Item
* Kit is consumed after one use, regardless of diagnosis accuracy
* Encourages players to learn vehicle systems for better outcomes
* Stock up on kits for long field work sessions
* **Strategic use**: Save your one-time diagnosis for when you really need it!

---

## USED VEHICLE MARKETPLACE

### Agent-Based Vehicle Searching
* Hire an agent to search for specific used vehicles
* **Local Agent**: 1-2 month search, lower fees, smaller selection
* **Regional Agent**: 2-4 month search, moderate fees, better selection
* **National Agent**: 4-6 month search, higher fees, best selection
* Small upfront retainer fee when search begins
* Agent commission built into vehicle price upon purchase

### Search Configuration
* Choose specific vehicle make and model
* Select desired quality level (affects price and condition)
* Agent continues monthly searches until contract ends
* Multiple vehicles accumulate in your portfolio as found
* Browse and purchase from found vehicles at any time

### Used Vehicle Condition
* Condition ranges from Poor to Excellent
* Lower condition = lower price but more repairs needed
* Component health (engine, electrical, hydraulic) varies by condition
* Tire wear and fluid levels reflect actual vehicle state
* Maintenance history available for review before purchase

### Used Vehicle Pricing
* Used prices significantly below new retail
* Price reflects actual condition and component health
* Trade-in available when purchasing (takes your old vehicle)
* Savings tracked in lifetime statistics

### Price Negotiation (v2.6.0, updated v2.6.1)
After inspecting a used vehicle, you can negotiate the price instead of paying full asking price!

**The Three Twists:**
1. **Mechanic's Assessment** - Inspection report shows vehicle condition
2. **Mechanic's Whisper** - Your mechanic shares intel about the SELLER's psychology
3. **Weather Window** - Bad weather makes sellers more willing to deal!

**Offer System:**
* Select your offer percentage (70%, 80%, 85%, 90%, 95%, or 100%)
* Lower offers save more money but risk rejection
* Seller may Accept, Counter, or Reject your offer
* **Cash only!** Used vehicle purchases require full payment upfront

**Seller Personalities (v2.6.2 - DNA-driven!):**
| Type | Accept At | Tolerance | Frequency | Behavior |
|------|-----------|-----------|-----------|----------|
| **Desperate** | 65% | +8% | 10% | Very forgiving of lowballs |
| **Motivated** | 75% | +4% | 25% | Somewhat tolerant |
| **Reasonable** | 85% | 0% | 40% | Standard expectations |
| **Firm** | 92% | -5% | 25% | Easily insulted by lowballs |
| **Immovable** | 98% | -10% | ~5% | Workhorse owners - they know what they have! |

**v2.6.2: DNA-Driven Seller Assignment**
Seller personality is no longer random - it's tied to the vehicle's hidden DNA!
* **Lemons (DNA < 0.30)**: 60% Desperate, 25% Motivated, 15% Reasonable
* **Average (DNA 0.30-0.69)**: 10% Desperate, 30% Motivated, 45% Reasonable, 15% Firm
* **Workhorses (DNA 0.70-0.89)**: 5% Motivated, 30% Reasonable, 50% Firm, 15% Immovable
* **Legendary (DNA ≥ 0.90)**: 20% Firm, 80% Immovable - owners KNOW they have gold!

This creates meaningful market dynamics:
* Great deals are more likely to be lemons (desperate sellers unloading problems)
* Stubborn sellers often have workhorses worth paying more for
* "Too good to be true" pricing? Probably a lemon!

**v2.6.1 Rejection Risk System - Lowballing Has Consequences!**

The further below the seller's threshold you offer, the higher your rejection risk:

| Gap Below Threshold | Risk Level | What Happens |
|---------------------|------------|--------------|
| 0-5% | Safe | Always counter - reasonable negotiation |
| 5-10% | Low Risk | Usually counter, 0-30% rejection chance |
| 10-15% | Medium Risk | 50/50 counter vs reject |
| 15-20% | High Risk | Usually reject, only 0-30% counter chance |
| >20% | Extreme Risk | **Always reject - seller is insulted!** |

**Example: Offering 70% to different sellers**
| Seller | Threshold | Raw Gap | Tolerance | Adjusted Gap | Result |
|--------|-----------|---------|-----------|--------------|--------|
| Desperate | 65% | -5% | +8% | -13% | **Accept!** |
| Motivated | 75% | 5% | +4% | 1% | Safe counter |
| Reasonable | 85% | 15% | 0% | 15% | High risk (mostly reject) |
| Firm | 92% | 22% | -5% | 27% | **Always reject!** |

**Factors That Improve Your Chances:**
* Days on market: +0.3% acceptance per day listed (max +10%)
* Vehicle damage > 20%: +5% acceptance
* Operating hours > 5000: +3% acceptance
* Bad weather (rain, storm, hail): +3% to +12% acceptance

**Weather Modifiers:**
| Weather | Modifier | Seller Psychology |
|---------|----------|-------------------|
| Hail | +12% | Fear of outdoor equipment damage |
| Storm | +8% | Urgency to close deal |
| Rain | +5% | Stuck inside, reflective mood |
| Snow | +5% | Off-season blues |
| Fog | +3% | Gloomy outlook |
| Cloudy | +2% | Slightly contemplative |
| Clear/Sunny | 0% to -3% | Optimistic, no rush |

**Counter Offers:**
* If your offer is close but not quite enough, seller will counter
* Accept the counter, Stand Firm (risky!), or Walk Away
* "Stand Firm" outcomes: 30% accept, 50% hold, 20% walk away

**Negotiation Lock & Permanent Walk-Away (v2.6.2):**
* **Temporary Cooldown (1 hour)**: Seller rejects but may return
* **Permanent Walk-Away**: Insulting offers (>20% below threshold) cause PERMANENT rejection!
  - The listing is locked forever - that vehicle is gone
  - Shows "The seller walked away permanently" warning
  - Strategic risk: push too hard and lose the vehicle entirely
* Immovable sellers (workhorse owners) are especially sensitive to lowball offers

**Strategic Tips:**
* Read the mechanic's whisper to identify seller personality!
* Wait for bad weather to improve your odds
* Don't lowball firm sellers - they won't budge
* Long-listed vehicles = more desperate sellers
* Damaged/high-hour vehicles = sellers want them gone

**Mechanic's Whisper Examples:**
* *"Between you and me... they seem pretty eager to sell. Might be in a tough spot."* (Desperate seller - lowball away!)
* *"Between you and me... I've seen this rig listed for a while now."* (Long listing - more flexible)
* *"Between you and me... they've priced it fair and know exactly what it's worth."* (Firm seller - stay above 90%!)
* *"Plus, with that storm rolling in, they might want to close quick."* (Weather bonus active)

---

## VEHICLE SELLING

### Agent-Based Vehicle Sales
* List owned vehicles for sale through agent network
* **Local Agent**: Fastest sales (1-2 months), lowest returns (60-75%)
* **Regional Agent**: Moderate timeline (2-4 months), better returns (75-90%)
* **National Agent**: Longest wait (3-6 months), best returns (90-100%)
* Agent actively markets your vehicle to potential buyers

### Private Sale Option
* No-cost listing similar to vanilla selling
* Instant sale at standard depreciated value
* No agent fees but no price negotiation

### Sale Offers
* Receive offers from interested buyers
* Accept or decline each offer
* Offer amounts based on vehicle condition and market demand
* Multiple offers may come in during listing period
* Offers expire if not responded to promptly

### Trade-In System
* Trade in old vehicle when purchasing new
* Instant disposal - lowest return option (50-65% of sell value)
* Condition impacts trade-in value (damage and wear reduce price)
* Brand loyalty bonus (5% extra for same manufacturer)
* Convenient when upgrading equipment

---

## USER INTERFACE

### Financial Dashboard
* Overview of all active loans and leases
* Payment schedule and upcoming due dates
* Credit score display with rating tier
* Total debt and monthly payment obligations
* Quick access to deal details and payment options

### 32 Custom Dialogs
* Comprehensive UI for all finance, maintenance, and marketplace features
* Consistent styling matching FS25 native interface
* Full keyboard and controller navigation support
* Informative displays with color-coded values

### Shop Integration
* "Finance" and "Lease" buttons in vehicle shop
* "Search Used" option to find pre-owned equipment
* Trade-in option when purchasing
* Condition display for used vehicles

### Map Integration
* "Buy", "Finance", and "Lease" options for farmland from map view
* Repair option when clicking owned vehicles on map

---

## CROSS-MOD INTEGRATION (v1.8.2+)

### Unified Financial Dashboard
* **EnhancedLoanSystem**: ELS loans display in Finance Manager with "ELS" type marker
* **HirePurchasing**: HP leases display in Finance Manager with "HP" type marker
* **Employment**: Worker wages included in monthly obligations total
* See ALL financial obligations from multiple mods in one unified view

### Pay Early Integration
* Make payments on ELS loans directly from UsedPlus Finance Manager
* Click "Pay Early" on ELS loans to make monthly or full payoff payments
* UsedPlus calls ELS payment API for seamless integration

### Maintenance Integration
* **Real Vehicle Breakdowns**: Deep integration with UsedPlus Workhorse/Lemon DNA system
  - DNA affects initial RVB part lifetimes (0.6x-1.4x multiplier)
  - Repair degradation applied when using RVB Workshop Service button
  - Breakdown degradation applied when RVB parts fail
  - OBD Scanner shows RVB part health: Engine, Thermostat, Generator, Battery, Starter, Glow Plug
  - Legendary workhorses immune to RVB repair degradation
  - **v2.7.0**: Override RVB Repair toggle - disable to let RVB handle repair natively (use Map > "Repair Vehicle" for UsedPlus features)
* **Use Up Your Tyres (v2.3.0 Deep Integration)**:
  - **Per-wheel display**: TiresDialog shows FL/FR/RL/RR wear when UYT installed
  - **Quality affects wear rate**: Retread tires wear 2x faster, Quality tires wear 33% slower
  - **DNA affects wear rate**: Lemons wear tires 40% faster, Workhorses wear 40% slower
  - **UYT wear influences flat tire probability**: Higher UYT wear = higher flat chance (1x-3x multiplier)
  - **Two-way sync**: Tire replacement in UsedPlus resets UYT wear tracking
  - OBD Scanner shows per-wheel UYT wear data
* **AdvancedMaintenance**: Both systems work together via function chaining

### Financial Visibility
* Monthly total shows loans + leases + employment wages (marked with * when wages included)
* Assets display shows farmland count: "Assets: $X (Y fields)"
* Complete picture of monthly cash requirements for accurate budgeting

### Compatibility Toggles (Settings)
UsedPlus provides escape hatches for mod conflicts:

| Setting | Default | Description |
|---------|---------|-------------|
| **Override Shop Buy/Lease** | ON | When ON, UsedPlus intercepts Buy/Lease buttons. When OFF, vanilla/other mods handle them. |
| **Override RVB Repair** (v2.7.0) | ON | When ON, RVB's Repair button opens UsedPlus partial repair. When OFF, RVB handles repair natively. Only shown when RVB is installed. |

Access via **ESC > Settings > UsedPlus**

### Compatible Mods
* **BuyUsedEquipment**: UsedPlus hides Search button, BUE handles used search
* **CrudeOilProduction**: Pure production mod, fully compatible
* **SpecialOffers**: Notification utility, works alongside

---

## MULTIPLAYER SUPPORT

* Full multiplayer compatibility with server-authoritative logic
* All transactions validated and processed on server
* Network events sync finance data across clients
* Per-farm credit scores and deal tracking
* Shared farm finances visible to farm members

---

## STATISTICS TRACKING

### Lifetime Statistics Per Farm
* Searches started, succeeded, failed, and cancelled
* Total agent fees paid
* Savings from buying used vs new
* Vehicles purchased through used marketplace
* Sales listed and completed
* Total sale proceeds
* Finance deals created and completed
* Total amount financed over time
* Total interest paid
* Negotiations attempted, won, countered, rejected (v2.6.0)
* Total savings from negotiation (v2.6.0)

---

## LOCALIZATION

Full localization support with 10 languages:

| Language | Status |
|----------|--------|
| English | ✓ Complete (source) |
| German | ✓ Complete |
| French | ✓ Complete |
| Spanish | ✓ Complete |
| Italian | ✓ Complete |
| Polish | ✓ Complete |
| Portuguese (BR) | ✓ Complete |
| Russian | ✓ Complete |
| Ukrainian | ✓ Complete |
| Czech | ✓ Complete |

All 1,654 translation keys available in every language.
