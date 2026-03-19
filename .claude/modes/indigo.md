# INDIGO MODE — Issue Deep-Fix Protocol

End-to-end resolution pipeline for a **specific GitHub issue**: research, plan, skeptical review, implement, code review, RED+GOLD verify. Indigo drives an issue to closure with adversarial plan validation and post-implementation code review ensuring the fix is robust.

**RULE**: After implementation, **code review agents run on actual changes**, then **RED + GOLD auto-trigger in parallel**.

**Activation Triggers**: "indigo mode" / "deep fix" / "fix issue #N"

## The 6 Phases

### Phase 1 — RECON
Fetch latest game log from GitHub issue (`gh api` + `curl`). Analyze log for root cause (grep for mod errors, stack traces, hook failures). Update `.issues/issue-0XX.md` and `OVERVIEW.md` with findings.

### Phase 2 — PLAN
Formulate fix with file:line targets. Plan MUST include:
- **Primary fix**: The code change that should resolve the issue
- **Fallback diagnostic logging**: If the fix ships and the bug persists, what targeted log output would round 2 need? (appropriate level — don't flood)
- **Implementation scope**: List every file to be changed, grouped by zone if 4+ files

### Phase 3 — SKEPTICAL CONVERGENCE (max 3 loops)
Launch 2 subagent reviewers in parallel on the PLAN:

| Agent | Role |
|-------|------|
| **CONSTRUCTIVE** | Reviews for correctness, completeness, multiplayer safety. "Will this fix work?" |
| **SKEPTIC** | **Adversarial** — assumes the fix WON'T work, demands fallback diagnostic logging, identifies code paths not covered. Must explicitly sign off. |

**SKEPTIC mandate**: The SKEPTIC must answer: *If this fix ships and the bug persists, what log lines would you need to diagnose it?* Those log lines MUST be in the plan.

Loop: revise plan, re-launch both reviewers, repeat until **both CONSTRUCTIVE and SKEPTIC agree**. If no consensus after 3 loops, HALT and present disagreements to user.

### Phase 4 — IMPLEMENT
Execute the agreed plan. No improvising. If the plan needs changes mid-implementation, pause and re-enter Phase 3.

**Conditional dispatch:**
- **3 or fewer files**: Implement directly (no zone partitioning, no parallel workers).
- **4+ files across multiple zones**: Dispatch parallel subagent workers, zone-partitioned per Gold Mode (no two workers edit the same file).

### Phase 4.5 — CODE REVIEW
After implementation, launch 3 review agents in parallel on the **actual code changes** (not the plan):

| Agent | Role |
|-------|------|
| **CORRECTNESS** | Does the implemented code match the plan? Are there deviations, typos, or logic errors? |
| **SIDE-EFFECTS** | Did the changes break anything in adjacent code? Are callers, hooks, and data flows intact? |
| **MULTIPLAYER** | Are events, streams, and server checks correct? Do `writeStream`/`readStream` field counts match? Is `Event.sendToServer()` used where needed? |

All 3 must pass. If any agent raises a blocking concern, fix the code and re-run the failing reviewer(s).

### Phase 5 — VERIFY
Launch verification on changed files. Build + log check + rosetta validate.

**Conditional scope:**
- **Single-file fixes**: Run GOLD only on the changed zone (RED is overkill for a single file).
- **Multi-file fixes**: Launch **RED + GOLD in parallel**. RED audits security. GOLD checks quality. Both must pass.

## Confidence Scoring

Each review agent reports a **confidence score (0-100%)**: "How confident are you this fix resolves the reported issue without introducing regressions?"

### Who Scores

| Phase | Agents |
|-------|--------|
| Phase 3 (Plan Review) | CONSTRUCTIVE, SKEPTIC |
| Phase 4.5 (Code Review) | CORRECTNESS, SIDE-EFFECTS, MULTIPLAYER |

Implementation agents (Phase 4) do NOT score — they execute, not evaluate.

### Aggregation & Thresholds

**Composite score = minimum across all scoring agents.** The weakest reviewer's confidence IS the fix's confidence.

| Zone | Score | Action |
|------|-------|--------|
| GREEN | >= 80% | Ship. All reviewers confident. |
| YELLOW | 50-79% | Ship with diagnostic logging active. Uncertainty warrants observability. |
| RED | < 50% | Hold. Do not ship — reviewers unconvinced. Re-enter Phase 2 or escalate to user. |

- **RESOLVED** requires GREEN or YELLOW composite. RED composite forces PARTIAL.
- **PARTIAL** can be any composite — diagnostic logging already required.
- **BLOCKED** has no composite score (no fix implemented).

### Report Format

```
Verdict: RESOLVED | Confidence: 85% (GREEN)

  CONSTRUCTIVE:  92%  — plan addresses root cause directly
  SKEPTIC:       85%  — fallback logging covers the gap if wrong
  CORRECTNESS:   95%  — implementation matches plan exactly
  SIDE-EFFECTS:  88%  — no adjacent code affected
  MULTIPLAYER:   90%  — events and streams verified
```

## Agent Scaling by Fix Complexity

Scale agent count to the fix's blast radius. Determined by Phase 1 RECON output.

| Tier | Criteria | Phase 3 | Phase 4.5 | Total Agents |
|------|----------|---------|-----------|-------------|
| **MICRO** | 1 file, <100 lines | 2 (CONSTRUCTIVE + SKEPTIC), 1 loop. REVISE-MINOR = no Loop 2 | 1 comprehensive reviewer | 3 |
| **SMALL** | 2-3 files, same subsystem | 2, up to 2 loops | 2 (CORRECTNESS + SIDE-EFFECTS) | 4-5 |
| **MEDIUM** | 4-6 files, 2+ subsystems | 2, up to 2 loops | 3 (full suite) | 7-10 |
| **LARGE** | 7+ files, cross-subsystem | 2, up to 3 loops | 3-5 (per-subsystem) | 10-17 |

**Bump-up rule**: Any change to `readStream`/`writeStream`, save/load, or event classes bumps up 1 tier.

**REVISE severity**: REVISE-MINOR (add nil check, tweak log) = main agent applies, no Loop 2. REVISE-MAJOR (wrong approach, missing code path) = full re-review loop. SKEPTIC-only re-review in Loop 2+ (CONSTRUCTIVE already validated the approach).

## Verdict Scale

| Verdict | Meaning |
|---------|---------|
| RESOLVED | Fix implemented, code review passed, verification passed, confidence GREEN/YELLOW |
| PARTIAL | Fix implemented but confidence RED or skeptic concerns unresolved — diagnostic logging added for round 2 |
| BLOCKED | Skeptical convergence failed — fundamental disagreement on approach |

## AMBER Consideration

At the conclusion of INDIGO, if the fix added or modified any `$l10n_` translation keys, or if new user-facing strings were hardcoded in Lua, flag for AMBER MODE follow-up. Translation quality should not drift as a side effect of bug fixes.

## Indigo Checklist

1. GitHub issue researched, latest log analyzed, `.issues/` updated
2. Fix complexity tier determined (MICRO/SMALL/MEDIUM/LARGE)
3. Plan includes primary fix + fallback diagnostic logging + implementation scope
4. Skeptical convergence achieved (SKEPTIC signed off, tier-appropriate loop count)
5. Implementation complete (direct for <=3 files, zone-partitioned workers for 4+)
6. Code review passed (tier-appropriate reviewer count on actual changes)
7. Confidence scores collected from all reviewers, composite calculated
8. Verification passed (GOLD-only for single-file, RED+GOLD for multi-file)
9. `.issues/` file updated with fix details, commit reference, and confidence score
10. AMBER consideration: flag if translation keys added/modified
