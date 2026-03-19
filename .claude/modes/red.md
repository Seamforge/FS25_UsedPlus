# RED MODE — Security Audit Protocol

OWASP-informed security audit with **overlapping full-codebase coverage** (not zone-partitioned). RED is a **security-focused BLUE -> GOLD** pipeline: diagnose security issues first, then auto-trigger GOLD scoped to security remediations.

**Activation Triggers**: "red mode" / "security audit" / "security sweep"

---

## The 4 Review Agents

Three primary agents (INJECTION, TRUST-BOUNDARY, EXPOSURE) launch in parallel during Phase 1a. The ADVERSARY launches in Phase 1b after receiving all primary findings.

Every agent has **full codebase access** (`src/`, `gui/`, `modDesc.xml`, `tools/`), but the protocol directs attention via priority files.

| Agent | Focus | Priority Files |
|-------|-------|---------------|
| **INJECTION** | Lua injection (`loadstring`/`dofile`/string concat), XML injection in save/load, unsanitized input | `src/core/`, `src/managers/` |
| **TRUST-BOUNDARY** | Authentication ("who can do this?" -- missing `g_server` checks, event spoofing, privilege escalation) AND validation ("what values are acceptable?" -- bounds checking, save/load XML tampering, integer overflow in financial math, race conditions) | `src/events/`, `src/managers/` |
| **EXPOSURE** | Sensitive data in logs, debug code in production, hardcoded values, information leakage | `src/`, `tools/` |
| **ADVERSARY** | Devil's advocate -- performs independent review of full codebase AND challenges agents 1-3, identifies false positives, catches missed issues, escalates underrated findings | Full codebase (receives Phase 1a findings) |

---

## FS25 Mod Threat Model

| Threat | Relevance | Why |
|--------|-----------|-----|
| Lua code injection | HIGH | `loadstring()`, `dofile()`, string-concatenated Lua expressions |
| Multiplayer event spoofing | HIGH | Crafted network events can manipulate server state |
| Save data tampering | MEDIUM | Players edit XML saves; mod must validate on load |
| Financial calculation abuse | MEDIUM | Integer overflow/underflow in loan amounts, credit scores |
| Information disclosure | LOW | Log output visible to local player only |
| Denial of service | LOW | Infinite loops or excessive memory in mod code |

---

## Audit Process

### Phase 1a -- PRIMARY REVIEW (read-only, parallel)

Launch agents 1-3 (INJECTION, TRUST-BOUNDARY, EXPOSURE) in parallel. Each examines the full codebase with attention directed to their priority files. Each returns structured findings:

- Finding ID (e.g., `INJ-001`, `TRUST-003`, `EXP-002`)
- File:line reference
- Severity: CRITICAL / HIGH / MEDIUM / LOW
- Category (from threat model)
- Description
- Proof-of-concept (how to exploit)
- Recommended fix

### Phase 1b -- ADVERSARIAL REVIEW (read-only, sequential)

ADVERSARY launches **after Phase 1a completes** and receives all findings from agents 1-3. ADVERSARY performs two tasks:

1. **Independent review**: Full codebase scan for issues the primary agents missed
2. **Challenge of existing findings**: Mark each Phase 1a finding as:
   - **CONFIRMED** -- finding is valid as stated
   - **DOWNGRADED** -- finding is valid but severity is too high (provide rationale)
   - **DISPUTED** -- finding is invalid or unexploitable (provide rationale)
   - **ESCALATED** -- finding is valid but severity is too low (provide rationale)

### Phase 2 -- DISPUTE RESOLUTION (main agent)

The **main agent** adjudicates all DISPUTED, DOWNGRADED, and ESCALATED findings. For each:

1. ADVERSARY provides dispute rationale
2. Main agent evaluates **exploitability against the FS25 threat model** (see table above)
3. Main agent rules:
   - **SUSTAINED** -- ADVERSARY's position adopted (finding dismissed, severity changed, etc.)
   - **OVERRULED** -- original finding stands as-is
   - **RECLASSIFIED** -- finding valid but assigned a different severity than either party proposed

Adjudication considers: Is this exploitable in a real FS25 multiplayer session? What is the actual blast radius? Does the threat model support the claimed severity?

### Phase 3 -- REMEDIATION

Fix all surviving findings (CONFIRMED + OVERRULED + RECLASSIFIED + ADVERSARY's independent findings) in severity order: CRITICAL -> HIGH -> MEDIUM -> LOW.

### Phase 4 -- VERIFY + PIPELINE

1. `node tools/build.js` -- builds without errors
2. `log.txt` check -- no new errors after loading mod
3. Re-run agents on changed files only -- confirm fixes don't introduce new issues
4. **GOLD MODE auto-launches** (see Pipeline Integration below)

---

## Pipeline Integration: RED -> GOLD

RED MODE is the security-focused front half of a two-stage pipeline. After RED remediation:

1. **GOLD MODE auto-launches**, scoped to security remediations (files changed during Phase 3)
2. GOLD checks whether security fixes introduced code quality regressions (dead code, consistency, file size, etc.)
3. If GOLD finds issues **in RED-changed files**, those are RED's responsibility -- fix them before declaring the RED pass complete
4. **Excluded from auto-triggered GOLD**: The `MULTIPLAYER-GAP` and `ERROR-HANDLING` categories are already covered by RED's TRUST-BOUNDARY agent and do not need redundant GOLD coverage

This ensures security patches meet the same quality bar as the rest of the codebase without duplicating RED's own coverage areas.

---

## Severity Guide

| Severity | Meaning |
|----------|---------|
| CRITICAL | Exploitable in default config, affects save integrity or server state -- fix immediately |
| HIGH | Exploitable with moderate effort, multiplayer impact -- fix in this pass |
| MEDIUM | Requires specific conditions, limited blast radius -- fix if straightforward |
| LOW | Theoretical concern, defense-in-depth -- fix at discretion |

---

## Verdict Scale

| Verdict | Meaning |
|---------|---------|
| HARDENED | 0 findings after adversarial review |
| SECURED | All CRITICAL/HIGH resolved, <=3 MEDIUM remaining |
| IMPROVED | CRITICAL resolved, some HIGH/MEDIUM remain |
| EXPOSED | Unresolved CRITICAL findings |

---

## Red Mode Checklist

1. User explicitly requested Red Mode
2. Phase 1a: INJECTION, TRUST-BOUNDARY, EXPOSURE launched in parallel with full codebase access
3. Phase 1b: ADVERSARY launched after 1a completes, receives all findings, performs independent review + challenge
4. Phase 2: Main agent adjudicates all disputes (SUSTAINED / OVERRULED / RECLASSIFIED)
5. Phase 3: Fixes applied in severity order (CRITICAL -> HIGH -> MEDIUM -> LOW)
6. Phase 4: Verification passed
7. GOLD MODE auto-triggered scoped to RED-changed files (excludes MULTIPLAYER-GAP and ERROR-HANDLING)
8. Final report with verdict
9. AMBER consideration: if security remediations added user-facing error messages or modified `$l10n_` keys, flag for AMBER MODE follow-up
