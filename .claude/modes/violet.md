# VIOLET MODE — Spec Compliance & Construction Protocol

Violet Mode is a **spec-driven audit + construction protocol** that compares the mod's design documents against the actual codebase, grades every section, and builds what's missing. Violet treats the spec documents as the source of truth.

**RULE**: Violet Mode is **explicit-only**. Uses subagents in two phases: audit (read-only), then build in dependency-ordered waves. Max 3 passes.

**Activation Triggers**: "violet mode" / "vision audit" / "spec compliance" / "align to spec"

## Spec Documents (Source of Truth)

| Document | What It Defines |
|----------|-----------------|
| `DESIGN.md` | System architecture, data models, multiplayer patterns, GUI framework |
| `CHANGELOG.md` | What was built, when, and why — the historical record |
| `FEATURES.md` | Complete feature list with current implementation status |
| `README.md` | What the mod does, how to install, how to use — the public contract |

## Section Classification

| # | Category | Class | Zone(s) |
|---|----------|-------|---------|
| 1 | Core Finance System | AUDIT | MANAGERS + DATA |
| 2 | Credit Score System | AUDIT | MANAGERS + DATA |
| 3 | Used Vehicle Marketplace | AUDIT | MANAGERS + EVENTS + GUI |
| 4 | Repair & Repaint System | AUDIT | EXTENSIONS + GUI |
| 5 | Lease System | AUDIT | MANAGERS + EVENTS |
| 6 | GUI Dialogs | AUDIT | GUI |
| 7 | Multiplayer Support | AUDIT | EVENTS |
| 8 | Translation Coverage | AUDIT | TRANSLATIONS |
| 9 | User Documentation | AUDIT | — (docs only) |
| 10 | Version & Release | INFO | — (historical record) |

**AUDIT** = graded against spec. **INFO** = context/reference only.

## Audit Grading

**4 Dimensions:** Coverage (0-100%) · Depth (STUB | SHALLOW | ADEQUATE | DEEP) · Fidelity (LOW | MED | HIGH) · Quality (LOW | MED | HIGH)

**Grades:** COMPLETE (3pts, Coverage >= 90% + Depth >= ADEQUATE + HIGH fidelity) · PARTIAL (2pts, Coverage 40-89% or SHALLOW depth) · SKELETAL (1pt, Coverage < 40% or STUB depth) · MISSING (0pts, Coverage < 10%) · N/A (excluded from scoring)

**Max total:** 9 auditable categories x 3 = **27 points**

### Structured Scorecard Format

Every audit agent MUST return its findings in this exact format:

```
Category: [name]
Coverage: [0-100%]
Depth: [STUB|SHALLOW|ADEQUATE|DEEP]
Fidelity: [LOW|MED|HIGH]
Quality: [LOW|MED|HIGH]
Grade: [COMPLETE|PARTIAL|SKELETAL|MISSING]
Points: [0-3]
Key Gaps: [list of specific missing implementations with file:line targets]
```

The main agent synthesizes all 9 scorecards into the audit report. Key Gaps must reference specific files and line numbers (e.g., `src/managers/FinanceManager.lua:142 — missing early-payoff penalty calculation`), not vague descriptions.

## Phase 1 — AUDIT

**RULE**: Launch **9 parallel read-only audit agents**, one per auditable category (categories 1-9 from Section Classification). Even where categories overlap zones (e.g., Core Finance and Credit Score both touch MANAGERS+DATA), each agent has a distinct spec-section focus. Overlap is safe since the audit phase is read-only.

Each agent:
1. Reads the relevant spec document sections (DESIGN.md, FEATURES.md, README.md, CHANGELOG.md)
2. Reads the source files in its zone(s)
3. Grades against the 4 dimensions
4. Returns a structured scorecard (see format above)

The main agent synthesizes all 9 scorecards into the audit report with total score, per-category breakdown, and prioritized gap list.

## Phase 2 — BUILD

**RULE — Samantha Gate (REQUIRED)**: Samantha reviews the complete audit report and approves the build scope before any construction begins. No code is written until Samantha gives explicit approval. She may narrow scope, reprioritize categories, or reject the build plan entirely.

### Dependency-Ordered Waves

Build proceeds in 5 sequential waves. **Within each wave, agents for different zones run in parallel. Between waves, execution is sequential.**

| Wave | Zone(s) | Depends On | Parallelism |
|------|---------|------------|-------------|
| 1 | DATA + MANAGERS | — (foundation) | DATA agent and MANAGERS agent run simultaneously |
| 2 | EVENTS | Wave 1 complete | Single zone |
| 3 | GUI | Waves 1-2 complete | Single zone |
| 4 | EXTENSIONS | Waves 1-3 complete | Single zone |
| 5 | TRANSLATIONS | Waves 1-4 complete (all UI text finalized) | Single zone |

**Example**: DATA agent and MANAGERS agent run simultaneously in Wave 1. Only after both complete does Wave 2 (EVENTS) begin. EVENTS must finish before Wave 3 (GUI) starts, and so on.

### Verification

After all 5 waves complete:
1. `node tools/build.js` — builds without errors
2. No new `Error` lines in `log.txt` after loading mod
3. `node translations/rosetta.js validate` — format specifiers intact
4. Files under 1500-line limit

### Re-Audit Optimization

**RULE**: Re-audit **ONLY** categories whose source files were modified in the build phase. Categories with zero file changes are carried forward from the previous audit score. This avoids redundant read-only sweeps of unchanged code and keeps convergence passes efficient.

## Convergence

Max 3 passes through the audit-build loop. Score must improve each pass, else HALT. Build priority order: MISSING -> SKELETAL -> PARTIAL.

## Verdict Scale

| Verdict | Criteria | Meaning |
|---------|----------|---------|
| ALIGNED | 27/27 (all COMPLETE) | Codebase fully implements all spec documents |
| CONVERGING | >= 21 AND improving each pass | Most categories COMPLETE or PARTIAL |
| DRIFTING | 12-20 OR any MISSING categories remain | Significant gaps between spec and code |
| MISALIGNED | < 12 OR score stalled/regressed | Major disconnect between spec and codebase |

## Violet Mode Checklist

1. User explicitly requested Violet Mode
2. All 4 spec documents read and section classification reviewed
3. 9 audit agents launched in parallel (read-only) + scorecards synthesized
4. Build scope approved by Samantha before any code is written (REQUIRED gate)
5. Build agents dispatched in dependency-ordered waves (parallel within, sequential between) + verification passed
6. Re-audit limited to categories with modified files; unchanged categories carry forward
7. Convergence tracked (score must improve each pass, max 3)
8. Final report with verdict
9. AMBER consideration: if Translation Coverage category scored below COMPLETE, or if build phase added new `$l10n_` keys, flag for AMBER MODE follow-up
