# BLUE MODE — Diagnostic Triage Protocol

Like a hospital "Code Blue," this protocol launches a full diagnostic sweep across the mod's loading, runtime, dialogs, events, GUI, hooks, save/load, and translations — all in parallel, all read-only.

**RULE**: Launch **6 parallel investigation tracks** as subagents. Every track is **strictly read-only**. Synthesize results into a diagnostic report with verdict and actionable next steps.

**Activation Triggers**: "blue mode" / "diagnose" / "run diagnostics" / "something's broken" / "Lua error"

---

## The 6 Parallel Investigation Tracks

Launch all 6 as subagents in parallel. **All read-only.** No track depends on another — cross-track correlations are resolved during synthesis (see Synthesis & Deduplication below).

---

### Track 1: LOG & LOADING — Does the Mod Load and Run?

*Reads `log.txt` once and `modDesc.xml` once. Categorizes findings by phase.*

**Load-Phase Checks:**
- `modDesc.xml` is valid XML
- All `<sourceFile>` entries point to existing `.lua` files
- All `<l10n>` entries point to existing translation files
- All `<gui>` entries point to existing `.xml` files
- Specializations registered correctly (no "Failed to register" errors)
- No `Error` or `Warning` lines referencing `UsedPlus` during load phase
- No "Failed to open" messages in log

**Runtime-Phase Checks:**
- `log.txt` for `Error` / `Warning` / `LUA call stack` referencing UsedPlus files
- Nil reference errors (`attempt to index` / `attempt to call` nil values)
- Stack traces pointing to `src/` files
- Repeated warnings on timer/update cycles (performance regression signals)
- `pcall` / error handling around dangerous operations

**Red Flags:** Missing source files · Invalid XML · Specialization registration errors · Stack traces · Nil reference errors · Repeated warnings on timer/update cycles

**Files:** `modDesc.xml`, `log.txt`, `src/**/*.lua` (existence check only)

---

### Track 2: GUI INTEGRITY — Are Dialogs Structurally and Semantically Correct?

*Reads each `gui/*.xml` + matching `src/gui/*.lua` pair once. Applies both structural validation AND semantic checks in a single pass per pair.*

**Structural Validation:**
- All `gui/*.xml` files are well-formed XML
- Profile `extends` references exist in base game or mod profiles
- Element `id` attributes are unique within each dialog
- `imageSliceId`, `imageFilename` references are valid
- Dialog structure follows `TakeLoanDialog.xml` pattern (GuiElement -> dialogBg -> content -> buttonBox)

**Semantic Checks:**
- Dialog coordinate system correct (Y negative going down from content container)
- `anchorTopCenter` used for dialog content elements
- Vehicle images use all 4 required attributes (`baseReference`, 180x180, `noSlice`, position `-185px 75px`)
- Custom images loaded via `setImageFilename()` in Lua (not XML `filename` attribute)
- `DialogLoader.show()` pattern used (not custom `getInstance()`)
- No `onClose`/`onOpen` callback name conflicts (system lifecycle names — causes stack overflow)
- Button profiles use `buttonActivate` / `buttonOK` (not `fs25_buttonSmall` which doesn't exist)
- XML root element is `<GUI>` (not `<MessageDialog>` or other)

**Red Flags:** Malformed XML · Dangling profile references · Duplicate IDs · Missing required dialog structure · Upside-down layouts · Missing vehicle images · Blank/corrupted textures · Stack overflow from lifecycle callback conflicts

**Files:** `gui/*.xml`, `src/gui/*.lua` (matched pairs)

---

### Track 3: NETWORK EVENTS — Is Multiplayer Working?

**Check:** All events in `src/events/` have matching registration in source files · Events check `g_server ~= nil` for server-side logic · `writeStream` / `readStream` field counts match (field-by-field comparison) · `Event.sendToServer()` used (not direct execution on client) · Static `execute()` pattern followed for business logic · Event class names match filenames · `emptyNew()` returns correct class instance

**Red Flags:** Missing event registration · Client-side execution of server logic · Stream read/write mismatch · "must run on server" errors in log · `execute()` doing client-side state mutation

**Files:** `src/events/*.lua`, registration sites in `src/main.lua` and manager files

---

### Track 4: HOOK CHAIN & COMPATIBILITY — Are Hooks Registered and Ordered Correctly?

*Validates all `appendedFunction`, `prependedFunction`, `overwrittenFunction` registrations, hook ordering, and mod compatibility detection.*

**Hook Registration Checks:**
- Every `appendedFunction` / `prependedFunction` / `overwrittenFunction` call targets an existing base-game or mod function
- Hook targets are not misspelled or referencing removed/renamed functions
- `overwrittenFunction` calls store and invoke the original function (no silent drops)
- No duplicate hook registrations for the same target

**Hook Ordering & Chain Checks:**
- RVB hook chain integrity: `YesNoDialog.show()` (static) -> `g_gui.showYesNoDialog()` (instance) -> `g_gui.showDialog()` (instance) — all three hooks present and ordered
- Farmland Market (FM) hook chain: `FarmlandManagerExtension` hooks present and conditional on FM detection
- `pendingRepairCallback` pre-stored before hook chain executes (RVB repair flow)

**Mod Compatibility Checks:**
- `ModCompatibility.lua` detection logic covers all supported mods (RVB, FM, etc.)
- Conditional hooks only register when target mod is detected
- No hard dependencies on optional mods (graceful degradation if absent)
- `ModCompatibility.isModPresent()` / `isModActive()` calls match actual mod names

**Red Flags:** Orphaned hooks targeting removed functions · Missing original function call in `overwrittenFunction` · Broken RVB/FM hook chains · Hard dependency on optional mod · Hook registered unconditionally for optional mod feature

**Files:** `src/extensions/*.lua`, `src/extensions/rvb/*.lua`, `src/utils/ModCompatibility.lua`, `src/main.lua`

---

### Track 5: SAVE/LOAD INTEGRITY — Does Data Survive Round-Trips?

*Validates `saveSavegame` / `loadSavegame` implementations for data consistency and migration safety.*

**Round-Trip Checks:**
- Every field written in `saveSavegame` has a matching read in `loadSavegame`
- Every field read in `loadSavegame` has a matching write in `saveSavegame`
- No fields silently dropped during save (data loss risk)
- Default values provided for missing fields in `loadSavegame` (handles first-load and migration)
- XML key names consistent between save and load (`xmlFile:getValue` / `xmlFile:setValue` key paths match)

**Schema Consistency Checks:**
- Data types match between save and load (string vs number vs boolean)
- Numeric fields use consistent formatting (`%.2f` save matches parse on load)
- Table/array iteration order is deterministic (no `pairs()` for ordered data)
- Nested XML paths are consistent (no mismatched depth)

**Migration Safety Checks:**
- Savegame loads cleanly with NO prior UsedPlus data (fresh install on existing save)
- Removed/renamed fields don't cause nil errors on load (backward compatibility)
- Version-gated migration logic (if any) handles all prior versions

**Red Flags:** Asymmetric save/load fields (data loss) · Missing defaults for new fields · Type mismatch between save format and load parse · `pairs()` used for ordered data serialization · Fresh-install nil errors

**Files:** `src/managers/*.lua`, `src/data/*.lua`, `src/settings/UsedPlusSettings.lua`, `src/extensions/FarmExtension.lua`, `src/specializations/UsedPlusMaintenance.lua`

---

### Track 6: TRANSLATIONS — Are All Languages Complete and Correct?

*Runs CLI tools AND performs manual spot-checks.*

**CLI Checks:**
- Run `node translations/rosetta.js status` — all 25 languages at expected entry count
- Run `node translations/rosetta.js validate` — format specifiers match English source (`%s`, `%d`, `%.1f`, `%.2f`)
- Run `node translations/rosetta.js audit` — check for grade D or F languages

**Spot-Checks (beyond CLI):**
- Sample 5-10 entries from 3+ languages for obvious machine-translation artifacts
- Verify CJK languages (ct, jp, kr) contain actual CJK characters (not romanized text)
- Check that high-visibility strings (menu titles, button labels, error messages) are translated in all languages
- Verify no placeholder entries remaining (`TODO`, `TRANSLATE`, `XXX`, or English text in non-English files)
- Check that `$l10n_` references in `gui/*.xml` and `src/**/*.lua` have matching keys in translation files

**Red Flags:** Languages below 100% · Mismatched format specifiers (crash risk) · Grade D/F languages · Missing translation files · `$l10n_` references with no matching key · CJK files containing only ASCII

**Files:** `translations/*.xml`, `gui/*.xml` (l10n refs), `src/**/*.lua` (l10n refs)

---

## Structured Finding Format

Every finding from every track MUST use this structure:

```
{
  severity:        CRITICAL | HIGH | WARNING | OK
  track:           1-6 (track number)
  track_name:      "LOG & LOADING" | "GUI INTEGRITY" | "NETWORK EVENTS" | "HOOK CHAIN & COMPATIBILITY" | "SAVE/LOAD INTEGRITY" | "TRANSLATIONS"
  file:            "path/to/file.lua"
  line:            123 (or null if not line-specific)
  description:     "Brief description of the issue"
  evidence:        "The actual code/log line that demonstrates the issue"
  related_tracks:  [2, 4] (other tracks likely to surface the same root cause)
}
```

Tracks return findings as a list in this format. The main agent uses `related_tracks` during synthesis to identify and deduplicate cross-track correlations.

---

## Severity Guide

| Severity | Meaning |
|----------|---------|
| CRITICAL | Mod won't load, game crashes, or save corruption (XML invalid, missing source files, stream mismatch, asymmetric save/load) |
| HIGH | Degraded — mod loads but key features broken (events failing, dialogs not opening, nil errors on use, broken hook chains) |
| WARNING | Unusual — monitor (incomplete translations, minor log warnings, edge case nil checks, style drift) |
| OK | Healthy — all checks pass |

---

## Synthesis & Deduplication

After all 6 tracks complete, the main agent performs synthesis:

1. **Collect** all findings from all tracks into a single list.
2. **Deduplicate** — when multiple tracks report findings with the same root cause (identified via `related_tracks` or same `file:line`), keep the finding from the track with the deepest analysis and annotate which other tracks corroborated it. Do NOT report the same root cause multiple times with different descriptions.
3. **Cross-correlate** — look for causal chains across tracks. Example: a missing source file in Track 1 explains a nil runtime error in Track 1 AND a broken hook in Track 4. Report as one finding with the root cause, noting downstream effects.
4. **Rank** — sort by severity (CRITICAL > HIGH > WARNING), then by impact breadth (number of corroborating tracks).

---

## Diagnostic Report Format

The final report contains:

1. **Verdict**: CRITICAL / DEGRADED / HEALTHY (see below)
2. **All CRITICAL and HIGH findings** (after deduplication) — every one listed with full structured detail
3. **Top 3 WARNING findings** — selected by impact breadth and user-facing visibility
4. **Track Summary Table**: track number, track name, status (CRITICAL/HIGH/WARNING/OK), one-line summary
5. **Recommended Actions**: specific `file:line` references and proposed fixes, ordered by severity
6. **Plain-English Summary**: 2-3 sentences a non-developer could understand

**Verdict Rules:**
- **CRITICAL** = any CRITICAL-severity finding exists
- **DEGRADED** = any HIGH-severity finding exists, no CRITICAL
- **HEALTHY** = all findings are WARNING or OK

---

## Blue Mode Checklist

1. All 6 tracks launched in parallel (no ordering dependency between tracks)
2. Each track uses structured finding format for all results
3. Red flags evaluated against severity guide
4. Synthesis performed: deduplicate, cross-correlate, rank
5. Report includes ALL CRITICAL+HIGH findings and top 3 WARNINGs
6. Actions reference specific files and line numbers
7. Verdict determined from severity rules
8. Plain-English summary written
9. AMBER consideration: if Track 6 (TRANSLATIONS) found issues, flag for AMBER MODE follow-up
