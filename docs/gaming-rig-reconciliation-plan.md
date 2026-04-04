# Gaming Rig Reconciliation Plan
**Created:** 2026-04-04  
**Status:** READY TO EXECUTE  
**Branch preserved:** `gaming-rig-wip` (commit `44ece0b`)  
**Master now at:** `47431a8` (origin/master, v2.15.4.97)

---

## Context

Developer broke leg 2026-02-22, worked exclusively on laptop for 6 weeks.
The gaming rig had 67 uncommitted files from pre-injury work. Those changes were
committed to `gaming-rig-wip` for preservation, then master was fast-forwarded
to origin/master (45 commits ahead).

Five parallel agents reviewed every file with a consistent verdict schema.
This document is the synthesized output.

---

## Executive Summary

**The overwhelming verdict: master is already better.**

The gaming-rig-wip work was pre-injury development that the laptop then superseded —
often with better architecture, more robust error handling, and proper i18n.

**Two categories of real action:**
1. **119 translation keys** — referenced in master's code, exist only in gaming-rig-wip, missing from master's translation files. These MUST be added via rosetta.js.
2. **2 files need human verification** — NegotiationDialog.lua and SellerResponseDialog.lua have a setImageColor API signature change that needs confirming before closing the book.

Everything else: master's version wins. Keep it.

---

## Verdict Reference

### Schema Used Across All Agents
- **CHERRY-PICK** — Unique local change, applies cleanly to master
- **PORT** — Good idea but old API; master already re-implemented it better
- **DISCARD** — Regression, or master already has a superior version
- **TRANSLATE-ONLY** — Only i18n diffs; master's version is correct
- **NEEDS-HUMAN** — Genuinely ambiguous; presented below with both sides

---

## File-by-File Verdicts

### Managers

| File | Verdict | Reason |
|------|---------|--------|
| `src/managers/BankInterestManager.lua` | **DISCARD** | `delete()` method intentionally removed from master (not needed — superseded by global cleanup) |
| `src/managers/DifficultyScalingManager.lua` | **DISCARD** | Same pattern — `delete()` method explicitly removed from master |
| `src/events/BulkSyncHandler.lua` | **DISCARD** | Master already has the settings sync step; rig was simply behind |
| `src/managers/UsedVehicleManager.lua` | **DISCARD** | `ServiceTruckDiscovery.checkExpiredOpportunities()` call was intentionally removed; module handles its own lifecycle |
| `src/managers/usedvehicle/VehicleSearchSystem.lua` | **DISCARD** | Master modernized API (tier→searchLevel, storeItemPrice→basePrice); rig used old field names |
| `src/managers/usedvehicle/VehicleSpawning.lua` | **DISCARD** | Master already has rig's changes plus more; rig was simply behind |

---

### GUI — Stubs & Test Infrastructure

| File | Verdict | Reason |
|------|---------|--------|
| `src/gui/AdminControlPanel.lua` | **DISCARD** | Master already has `onCreateTestLeaseClick()` + `onExpireLeaseClick()` plus better i18n |
| `gui/AdminControlPanel.xml` | **DISCARD** | Master already has Lease Testing buttons wired correctly |
| `src/gui/financepanels/FinancesPanel.lua` | **DISCARD** | Master already has `onFinanceRowClick9()` + `onFinanceRowClick10()` |
| `src/gui/unifiedpurchase/DisplayUpdater.lua` | **DISCARD** | Abandoned stub (all function bodies are TODOs); master deliberately removed it from modDesc.xml |
| `src/gui/UnifiedPurchaseDialog.lua` | **DISCARD** | No `_OLD` functions actually exist; diffs are pure i18n — master's version is correct |

---

### RVB & Vehicle Frame Extensions

| File | Verdict | Reason |
|------|---------|--------|
| `src/extensions/rvb/RVBButtonInjection.lua` | **DISCARD** | Rig removed `isElementStillInParent()` safety validator and used incorrect pricing config; master has both fixed |
| `src/extensions/rvb/RVBWorkshopIntegration.lua` | **DISCARD** | Rig removed pcall safety wrappers; master is strictly more robust |
| `src/extensions/rvb/RVBServiceHooks.lua` | **DISCARD** | **Confirmed regression**: rig used `vehicle` object as table key (breaks on save/load); master correctly uses `vehicle.id` integers + has `isSaving` guards |
| `src/extensions/InGameMenuVehiclesFrameExtension.lua` | **DISCARD** | Rig's `retryFrameHook()` 5-sec timer is fragile; master hooks actual `onFrameOpen` instance — more reliable |

---

### Extensions — Regressions & i18n

| File | Verdict | Reason |
|------|---------|--------|
| `src/extensions/ShopConfigScreenExtension.lua` | **DISCARD** | Rig removed saleItem tracking (Issue #30 regression) and reverted to hardcoded English; master is correct |
| `src/extensions/FinanceMenuExtension.lua` | **DISCARD** | Rig removed the borrow-redirect notification hook; master's version provides better UX |
| `src/extensions/BuyVehicleDataExtension.lua` | **DISCARD** | Rig used verbose nested if-blocks; master's flat early-return pattern is cleaner |
| `src/gui/UsedPlusSettingsMenuExtension.lua` | **DISCARD** | Rig missing FM integration toggle + preset sync event; master has both |
| `src/gui/DealDetailsDialog.lua` | **DISCARD** | Rig has hardcoded English; master has comprehensive i18n |
| `src/gui/FaultTracerDialog.lua` | **DISCARD** | Rig uses old i18n key names (ft_error_*); master uses correct (ft_*) keys |
| `src/gui/InspectionReportDialog.lua` | **DISCARD** | Inspector notes generation phased out in master; master has correct i18n |
| `src/gui/MaintenanceReportDialog.lua` | **DISCARD** | Rig uses acp_*/mrd_* key names; master uses unified condition_* scheme |
| `src/gui/FinanceDetailFrame.lua` | **DISCARD** | Rig uses `.sendToServer` (wrong); master uses `:sendToServer` (correct colon syntax) |
| `src/gui/ServiceTruckDiscoveryDialog.lua` | **DISCARD** | Rig uses old function name `onClickBuy`; master uses `onClickBuyNow` matching XML binding |
| `src/gui/SaleListingDetailsDialog.lua` | **DISCARD** | Master has i18n upgrades; *verify* hours format change is intentional (see Needs-Human) |

---

### Needs-Human: Two Files Require Verification

#### 1. `src/gui/NegotiationDialog.lua`

**Issue:** master calls `setImageColor(nil, r, g, b, a)` (5 args) while rig calls `setImageColor(r, g, b, a)` (4 args).

**What to verify:** Is the leading `nil` correct for the current GIANTS engine?  
Check in any other dialog that uses `setImageColor` on a Bitmap element.  
- If 5-arg `nil`-prefixed form is confirmed valid → master is correct, no action.  
- If 5-arg form is wrong → this is a master bug; file a fix.

**Check command:**
```bash
grep -r "setImageColor" src/gui/ --include="*.lua" | grep "nil," | head -10
```

---

#### 2. `src/gui/SellerResponseDialog.lua`

**Same issue as above.** Same verification step.

---

#### 3. `src/gui/SaleListingDetailsDialog.lua` *(low priority)*

**Issue:** master removed `DepreciationCalculations.formatOperatingHours()` wrapper, now uses raw `tostring()`.  
Verify in-game that operating hours display looks correct (e.g., "1,234 hrs" not "1234").

---

## Translation Keys: The Real Action Item

This is the only substantive work remaining. Five key prefix groups were analyzed.
Of the 252 keys that exist only in gaming-rig-wip:

| Prefix Group | Keys in WIP | Keys Referenced in Master Code | Action |
|---|---|---|---|
| `usedplus_ft_*` | 70 | **65** | ADD to master translations |
| `usedplus_confirm_*` | 23 | **22** | ADD to master translations |
| `usedplus_acp_*` | 166 | **20** | ADD to master translations |
| `usedplus_fp_*` | 54 | **12** | ADD to master translations |
| `usedplus_mrd_*` | 14 | **0** | DISCARD — orphaned |
| **Total** | **327** | **119** | **119 keys needed** |

**Diagnosis:** Master's code references 119 translation keys that are present in
gaming-rig-wip but absent from master's translation files. In-game, these currently
show as blank strings or fallback text. They were being built in the gaming rig era
and never made it into master.

### Specific Keys to Add (run on master)

#### usedplus_ft_* (65 keys) — FaultTracerDialog + ServiceTruck
```
usedplus_ft_action, usedplus_ft_beginRepair, usedplus_ft_ceilingRestored,
usedplus_ft_cellLabel, usedplus_ft_cellRef, usedplus_ft_componentTitle,
usedplus_ft_correct, usedplus_ft_corroded, usedplus_ft_corrodedDesc,
usedplus_ft_cracked, usedplus_ft_crackedDesc, usedplus_ft_diagnoseFaultType,
usedplus_ft_diagnosisAccuracy, usedplus_ft_electrical, usedplus_ft_engine,
usedplus_ft_engineFaultTracer, usedplus_ft_faultCounter,
usedplus_ft_faultCounterFormat, usedplus_ft_faultIndicator, usedplus_ft_flag,
usedplus_ft_flagAllFirst, usedplus_ft_gaugeAmber, usedplus_ft_gaugeFault,
usedplus_ft_gaugeGreen, usedplus_ft_gaugeRed, usedplus_ft_healthy,
usedplus_ft_hintAmberCracked, usedplus_ft_hintGreenCorroded,
usedplus_ft_hintNoProbes, usedplus_ft_hintRedSeized, usedplus_ft_howToPlay,
usedplus_ft_howToPlayLine1, usedplus_ft_howToPlayLine2, usedplus_ft_howToPlayLine3,
usedplus_ft_howToPlayLine4, usedplus_ft_howToPlayLine5, usedplus_ft_hydraulic,
usedplus_ft_hydraulicColon, usedplus_ft_incorrect, usedplus_ft_incorrectCount,
usedplus_ft_maxPotential, usedplus_ft_modeLabel, usedplus_ft_needsService,
usedplus_ft_noFaults, usedplus_ft_noOil, usedplus_ft_oilColon,
usedplus_ft_oilConsumed, usedplus_ft_oilUsed, usedplus_ft_perfectDiagnosis,
usedplus_ft_probe, usedplus_ft_probeHit, usedplus_ft_quickScan,
usedplus_ft_quickScanCap, usedplus_ft_reliabilityGain, usedplus_ft_repairResults,
usedplus_ft_resources, usedplus_ft_resultLine, usedplus_ft_seized,
usedplus_ft_seizedDesc, usedplus_ft_selectComponent, usedplus_ft_selectHint,
usedplus_ft_targetVehicle, usedplus_ft_title, usedplus_ft_truckUnavailable,
usedplus_ft_vehicleUnavailable
```

#### usedplus_confirm_* (22 keys) — UnifiedPurchaseDialog
```
usedplus_confirm_amountFinancedFormat, usedplus_confirm_buyoutFormat,
usedplus_confirm_capReductionFormat, usedplus_confirm_cashBackFormat,
usedplus_confirm_downPaymentFormat, usedplus_confirm_dueTodayDownFormat,
usedplus_confirm_dueTodayFormat, usedplus_confirm_interestRateFormat,
usedplus_confirm_leaseTermFormat, usedplus_confirm_monthlyPaymentFormat,
usedplus_confirm_priceFormat, usedplus_confirm_refundFormat,
usedplus_confirm_securityDepositFormat, usedplus_confirm_termFormat,
usedplus_confirm_title, usedplus_confirm_totalDueFormat,
usedplus_confirm_totalInterestFormat, usedplus_confirm_tradeInFormat,
usedplus_confirm_typeCash, usedplus_confirm_typeFinance,
usedplus_confirm_typeLease, usedplus_confirm_vehicleFormat
```

#### usedplus_acp_* (20 keys) — AdminControlPanel
```
usedplus_acp_activeDeals, usedplus_acp_balance, usedplus_acp_creditScore,
usedplus_acp_drainHyd, usedplus_acp_drainOil, usedplus_acp_elec10,
usedplus_acp_elec100, usedplus_acp_elec50, usedplus_acp_emptyHyd,
usedplus_acp_emptyOil, usedplus_acp_eng10, usedplus_acp_eng100,
usedplus_acp_eng50, usedplus_acp_hyd10, usedplus_acp_hyd100,
usedplus_acp_hyd50, usedplus_acp_resetCooldowns,
usedplus_acp_serviceTruckTanks, usedplus_acp_setZero, usedplus_acp_totalDebt
```

#### usedplus_fp_* (12 keys) — FluidPurchaseDialog + FinancesPanel
```
usedplus_fp_amount, usedplus_fp_contains, usedplus_fp_containsLabel,
usedplus_fp_cost, usedplus_fp_creditType, usedplus_fp_currentLevel,
usedplus_fp_empty, usedplus_fp_fluidType, usedplus_fp_open,
usedplus_fp_purchase, usedplus_fp_revolving, usedplus_fp_tankStatus
```

---

## Execution Checklist

### Phase 1 — Verify (do first, before touching translations)
- [ ] **NegotiationDialog:** Run `grep -r "setImageColor" src/gui/ --include="*.lua" | grep "nil,"` — confirm 5-arg form is valid in master
- [ ] **SellerResponseDialog:** Same check
- [ ] **SaleListingDetailsDialog:** Boot game and verify operating hours display format looks correct

### Phase 2 — Add Missing Translation Keys to Master
- [ ] Extract the 119 English source values from gaming-rig-wip:
  ```bash
  git show gaming-rig-wip:translations/translation_en.xml | grep -E 'name="usedplus_(ft|confirm|acp|fp)_' > /tmp/keys_to_port.txt
  ```
- [ ] Use `node translations/rosetta.js deposit` to add English values to master translation_en.xml
- [ ] Run `node translations/rosetta.js status` — new keys will appear as Untranslated
- [ ] Delegate translation of 119 new keys to Haiku subagent (25 languages × 119 keys)
- [ ] Run `node translations/rosetta.js validate` — confirm no format specifier errors

### Phase 3 — Close Out
- [ ] Confirm `gaming-rig-wip` branch is NOT pushed to origin (it's local archive only)
- [ ] Build and deploy: `node tools/build.js --deploy`
- [ ] Boot game, test FaultTracer, confirm dialog, and admin panel show correct strings
- [ ] If Phase 1 verification finds the `setImageColor` 5-arg bug in master, file a fix commit

### Phase 4 — Archive
- [ ] This document can be deleted or moved to `.claude/` after Phase 3 is complete
- [ ] `gaming-rig-wip` branch can be deleted once translations are verified: `git branch -d gaming-rig-wip`

---

## What We Are NOT Doing (and Why)

| Temptation | Why We're Skipping It |
|---|---|
| Cherry-picking `delete()` methods from BankInterestManager/DifficultyScalingManager | Master explicitly removed them — the cleanup mechanism changed architecture |
| Re-applying retryFrameHook() | Master's onFrameOpen instance hook is more reliable |
| Keeping any RVB gaming-rig changes | All are confirmed regressions vs master |
| Importing usedplus_mrd_* keys | Zero references in master code — orphaned |
| Merging modDesc.xml from gaming-rig-wip | Would load deleted files; master's version is authoritative |

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| setImageColor 5-arg is a master bug | Low | Medium | Phase 1 verification |
| rosetta.js deposit corrupts translation file | Very Low | High | Check `git diff` before committing |
| Some ft_*/confirm_* keys already exist in master under different names | Medium | Low | `node rosetta.js status` will show duplicates |
| gaming-rig-wip accidentally pushed to origin | Low | Low | It's local-only; don't `git push` it |

---

*Document authored by Claude + Samantha via 9-agent parallel review session, 2026-04-04*
