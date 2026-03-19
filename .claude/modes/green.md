# GREEN MODE — Feature Gap Resolution Protocol

Green Mode resolves **feature gaps** — capabilities that should exist but don't. Unlike Blue Mode (diagnostics), Green Mode designs and builds new functionality through a 6-stage process.

**RULE**: Follow all 6 stages in order. Do NOT skip stages.

**Activation Triggers**: Color Gate routes GREEN · "green mode" / "feature gap" · Additive functionality requests

## Zone Reference

Green Mode uses Gold Mode Zone Partitioning for all dispatch decisions:

| Zone | Covers |
|------|--------|
| CORE | `src/core/` |
| DATA | `src/data/` |
| EVENTS | `src/events/` |
| MANAGERS | `src/managers/` |
| GUI | `src/gui/` + `gui/*.xml` |
| EXTENSIONS | `src/extensions/` + `src/specializations/` |
| UTILS | `src/utils/` + `src/settings/` |
| TRANSLATIONS | `translations/` |
| CONFIG | `modDesc.xml`, `tools/` |

## The 6 Stages

### Stage 1: GAP ANALYSIS — Define What's Missing

Articulate what exists vs what's needed. Output a 3-part gap statement:
- **Current behavior**: [What happens now]
- **Expected behavior**: [What should happen]
- **Constraints**: [What must NOT change — especially multiplayer sync, existing save data, other features]

### Stage 2: CODEBASE EXPLORATION — Understand the System

Read-only exploration. Identify affected files, read source, note patterns/conventions.

**Agent dispatch rule**: If the gap affects **3+ subsystems**, dispatch parallel read-only exploration agents scoped to those subsystems. For **1-2 subsystems**, explore serially.

Each exploration agent reads only files within its assigned subsystem and returns: relevant files, current code paths, existing patterns to follow, and impact assessment.

Output: Relevant files · Current code path · Existing patterns to follow · Impact assessment · Affected zones (mapped to Gold Mode Zone Partitioning)

### Stage 3: DESIGN — Architecture & Edge Cases (Approval Required)

Design before coding. Consider:
- Architecture and data flow
- Multiplayer implications (what needs events? server-authoritative?)
- GUI layout (coordinate system, profile inheritance)
- Edge cases (nil vehicles, missing data, mid-save state)
- Impact on existing features

**Checkpoint (REQUIRED)**: Samantha approves before any code is written. Checks: fits existing patterns? Multiplayer safe? Simplest solution? File size under 1500 lines?

### Stage 4: PLAN — Implementation Steps

Turn design into numbered checklist via `EnterPlanMode`. Cover: dependency-ordered changes, file size checks, translation keys needed, verification steps.

**Interface contracts (REQUIRED when plan triggers agent dispatch)**: Before any agents launch, the plan must define explicit interface contracts:
- **Function signatures**: Name, parameters, return values for all cross-zone calls
- **Event parameters**: `writeStream` / `readStream` field order and types for all new events
- **Data model fields**: Field names, types, and defaults for all new/modified data structures

These contracts are the source of truth that agents code against. Each agent receives the full contract set so cross-zone boundaries stay consistent.

**Implementation partitioning**: Use Violet's dependency-wave pattern for new features. Waves execute in order — within each wave, agents for different zones run in parallel:

| Wave | Zones | Rationale |
|------|-------|-----------|
| 1 | DATA + MANAGERS | Core data models and manager singletons must exist first |
| 2 | EVENTS | Network events depend on data models |
| 3 | GUI + EXTENSIONS | Dialogs and vehicle extensions depend on managers and events |
| 4 | TRANSLATIONS + CONFIG | Translation keys and modDesc registration depend on all code being finalized |

### Stage 5: IMPLEMENT — Execute the Plan

Follow approved plan. No improvising. If plan needs changes, return to Stage 4.

**Rules during implementation:**
- Follow existing patterns (MessageDialog, DialogLoader, Event.sendToServer)
- Respect 1500-line file limit — refactor if exceeded
- Add translation keys to all 25 languages
- Register new source files in `modDesc.xml`
- No `goto`, no `os.time()`, no sliders (see "What DOESN'T Work")

**Agent dispatch rule**: If the plan modifies files in **3+ distinct zones** (per Gold Mode Zone Partitioning), dispatch one agent per affected zone. Within a single zone, implement directly regardless of file count. Agents within the same dependency wave run in parallel; waves execute sequentially.

**Samantha partitioning review (REQUIRED gate)**: If the plan triggers agent dispatch, Samantha reviews the partitioning strategy and interface contracts before agents launch. Checks: zone boundaries clean? Interface contracts complete and unambiguous? Wave ordering correct? Any hidden cross-zone dependencies?

**Failure and rollback protocol**: If dispatched agents produce incompatible code (mismatched interfaces, conflicting assumptions, integration errors), the main agent manually resolves integration conflicts. If the conflict reveals a plan flaw, return to Stage 4 — redefine interface contracts, get Samantha's re-approval, and re-dispatch.

### Stage 6: VERIFY — Confirm Gap Closed

**Parallel verification** — launch three checks simultaneously:
1. `node tools/build.js` — builds without errors
2. `node translations/rosetta.js validate` — format specifiers intact
3. `log.txt` scan — no new `Error` lines referencing UsedPlus after loading mod

**Sequential verification** — main agent checks after parallel results return:
4. Multiplayer events have matching read/write streams (field count, order, types)
5. Regression risk — all existing features still work (no broken code paths)
6. Files under 1500-line limit
7. New feature works as specified in gap statement

ALL checks must pass. If any fail, fix and re-verify.

## Green Mode Checklist

1. Color Gate routed GREEN
2. Gap statement defined and approved
3. Codebase explored — parallel exploration agents if 3+ subsystems, serial if 1-2
4. Design explicitly approved by Samantha
5. Plan formalized via EnterPlanMode with interface contracts (if multi-zone)
6. Samantha approved partitioning strategy and contracts (if agent dispatch triggered)
7. Implementation follows plan — agents per zone if 3+ zones affected, direct if 1-2 zones
8. Agent conflicts resolved; returned to Stage 4 if plan needed changes
9. Verification passed — parallel checks (build, rosetta, log) then sequential checks (streams, regression, file size, gap satisfaction)
10. AMBER consideration: if new `$l10n_` keys were added or user-facing strings introduced, flag for AMBER MODE follow-up
