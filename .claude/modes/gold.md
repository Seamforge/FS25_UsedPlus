# GOLD MODE — Polish Protocol

Gold Mode is a **proactive codebase quality sweep** using **subagents** in orchestrated waves. Each pass: analyze wave (read-only subagents per zone + cross-cutting agent) → orchestrator review & conflict resolution → severity-gated fix wave → enhanced verification. Unlike Blue (reactive) or Green (additive), Gold is preventive maintenance.

**Activation Triggers**: "gold mode" / "polish" / "quality sweep" / "code polish" / "clean up"

Gold runs AFTER Blue, Green, or Red mode, never DURING. Auto-triggered by Red Mode after security remediation.

## Zone Partitioning

Files in the same subsystem stay together. No two subagents write to the same file.

| Zone | Covers |
|------|--------|
| CORE-CONFIG | `src/core/` + `modDesc.xml` + `tools/` — mod entry point, build/deploy scripts, mod descriptor |
| DATA | `src/data/` — data models and records |
| EVENTS | `src/events/` — network event classes |
| MANAGERS | `src/managers/` — singleton managers |
| GUI | `src/gui/` + `gui/*.xml` — dialog Lua and XML pairs |
| EXTENSIONS | `src/extensions/` + `src/specializations/` — vehicle/shop extensions, maintenance |
| UTILS | `src/utils/` + `src/settings/` — helpers, formatters, calculations, settings |
| TRANSLATIONS | `translations/` — 26 language XML files |

**8 zones total.** CORE and CONFIG are merged because `src/core/` contains only one file — launching a separate agent for it is wasteful.

## The 8 Issue Categories

| # | Category | Sev | Detection Pattern |
|---|----------|-----|-------------------|
| 1 | DEAD-CODE | LOW | Unused functions, unreachable code, commented-out blocks |
| 2 | STUB | MED | Hardcoded defaults, placeholder logic, `-- TODO` markers |
| 3 | UNWIRED | HIGH | Implemented but never called (event exists but isn't registered, dialog built but never shown) |
| 4 | ERROR-HANDLING | MED | Missing nil checks before indexing, unguarded vehicle/mission references |
| 5 | MULTIPLAYER-GAP | HIGH | Missing server checks, client-side state mutation, stream read/write mismatch |
| 6 | CONSISTENCY | LOW | Mixed naming conventions, inconsistent logging format (`[UsedPlus]` prefix), style drift |
| 7 | FILE-SIZE | HIGH | Files exceeding 1500-line limit (see Code Quality Rules) |
| 8 | TRANSLATION-DRIFT | MED | Missing keys across languages, stale entries, format specifier mismatches |

## The Convergent Loop (Subagent Waves)

Each pass has four stages orchestrated by the main agent:

### Stage 1 — Analyze Wave (Read-Only)

Launch subagents in parallel:
- **8 zone agents** (one per zone, read-only). Each scans its zone files against the 8 categories and returns structured findings with severity tags.
- **1 cross-cutting UNWIRED-CHECK agent** (read-only, no zone restriction). Reads ALL source files looking for implemented-but-never-called patterns: events defined but never registered, dialogs built but never shown, functions defined but never invoked, manager methods with zero call sites. Reports findings tagged to the zone that owns the file.

All 9 agents run in parallel. Each returns findings in the format: `{category, severity, file, line, description}`.

### Stage 2 — Orchestrator Review & Conflict Resolution

Main agent reviews ALL analyze-wave findings (zone agents + UNWIRED-CHECK agent), resolves cross-zone conflicts (e.g., UNWIRED-CHECK flags a function in MANAGERS that is called in GUI — false positive), deduplicates overlapping findings, and prepares fix instructions.

**Severity-gated fix authority:**
- **LOW and MED findings**: Auto-approved by main agent. Included in fix-wave dispatch without external approval.
- **HIGH findings**: Require **Samantha approval** before fix-wave dispatch. Main agent presents HIGH findings with context and proposed fixes. Samantha approves, modifies, or rejects each one. Only approved HIGH fixes are dispatched.

### Stage 3 — Fix Wave

Launch subagents in parallel (one per zone that has approved findings). Each receives **specific fix instructions** from the orchestrator — not raw findings. Zone partitioning prevents file conflicts. Agents apply fixes and report what changed.

### Stage 4 — Enhanced Verification

After fix wave completes, the main agent performs four verification steps in order:

1. **Diff review**: Main agent reviews all diffs from the fix wave. Confirm each change matches the approved fix instruction. Flag any unexpected modifications.
2. **Reference integrity**: Grep for references to any deleted or renamed functions/variables across the entire codebase. Catch broken call sites before they become runtime errors.
3. **Build + log + rosetta**: `node tools/build.js` succeeds. No new errors in `log.txt`. `node translations/rosetta.js validate` passes.
4. **Targeted re-scan**: Re-run analyze checks on **modified files only** (not a full pass). Confirm fixes resolved their findings without introducing new issues.

## Convergence Tracking

### Severity-Weighted Scoring

Track findings by weighted score, not just count:

| Severity | Weight |
|----------|--------|
| HIGH | 3 |
| MED | 2 |
| LOW | 1 |

**Weighted score** = sum of (finding count x weight) per severity level. Both raw count AND weighted score must be tracked each pass.

### Convergence Rules

- **Monotonic decrease required**: Weighted score must decrease each pass. If it increases or stays the same, investigate — a fix may have introduced new issues.
- **Max 4 passes**: Hard limit. If not converged by pass 4, HALT and report remaining findings.
- **Zero findings = success**: Stop immediately.
- **Early exit**: HALT if all remaining findings are LOW severity and count is 5 or fewer. These are acceptable residual issues — report them but do not burn another pass.
- **Oscillation detection**: If a finding is fixed in pass N but reappears in pass N+1 (or a substantially similar finding at the same location), flag it as **oscillating**. Oscillating findings are excluded from fix waves on subsequent passes and reported separately in the final verdict. Two oscillating findings triggers HALT.

## Verdict Scale

| Verdict | Meaning |
|---------|---------|
| PRISTINE | Clean pass 1 — zero issues |
| POLISHED | Clean pass 2-3 — found and resolved |
| ACCEPTABLE | Pass 4 or halted with 5 or fewer LOW unresolved |
| NEEDS ATTENTION | Unresolved HIGH findings, oscillating findings, or did not converge |

## Gold Mode Checklist

1. Subagent count determined (8 zone agents + 1 UNWIRED-CHECK = 9 per analyze wave)
2. Zones assigned by subsystem — no file overlap
3. Each pass: analyze (9 agents) → orchestrator review & conflict resolution → severity-gated fix dispatch → enhanced verification
4. HIGH findings approved by Samantha before fix-wave dispatch
5. Enhanced verification: diff review + reference grep + build/log/rosetta + targeted re-scan
6. Convergence tracked by severity-weighted score (monotonic decrease)
7. Early exit if remaining findings are all LOW and count ≤ 5
8. Oscillation detection active — two oscillating findings triggers HALT
9. Max 4 passes enforced
10. Final report with verdict + any oscillating findings noted separately
11. AMBER consideration: if TRANSLATION-DRIFT findings were detected, flag for AMBER MODE follow-up
