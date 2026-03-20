# INDIGO MODE — Issue Deep-Fix Protocol

End-to-end resolution pipeline for a **specific GitHub issue**: research, plan, skeptical review, implement, code review, RED+GOLD verify. Indigo drives an issue to closure with adversarial plan validation and post-implementation code review ensuring the fix is robust.

**RULE**: After implementation, **code review agents run on actual changes**, then **RED + GOLD auto-trigger in parallel**.

**Activation Triggers**: "indigo mode" / "deep fix" / "fix issue #N"

---

## CRITICAL: No Phase May Be Skipped

**Every phase is mandatory.** The temptation to skip Phase 4.5 (code review) or Phase 5 (verify) "because the fix is simple" has historically led to shipping incomplete or broken fixes. The protocol exists because each phase catches different classes of errors:

- **Phase 1** catches misdiagnosis (fixing the wrong thing)
- **Phase 2** catches incomplete plans (missing edge cases)
- **Phase 3** catches flawed approaches (the fix won't work)
- **Phase 4** is execution (no skipping possible)
- **Phase 4.5** catches implementation bugs (typos, logic errors, side effects)
- **Phase 5** catches quality regressions (build breaks, security holes, translation drift)

**If you feel a phase is unnecessary for a "simple" fix, that is the exact moment it is most needed.** Simple fixes have the highest rate of unreviewed regressions because confidence breeds shortcuts.

**The only exception**: MICRO-tier fixes (1 file, <100 lines) may use a single comprehensive reviewer for Phase 4.5 instead of 3 separate agents. All other phases remain mandatory.

---

## The 6 Phases

### Phase 1 — RECON

**Goal**: Understand the issue deeply before proposing any fix.

1. Fetch the GitHub issue (`gh issue view N --json title,body,labels,comments,state`)
2. Analyze any attached logs for root cause (grep for mod errors, stack traces, hook failures)
3. Read the relevant source code — do NOT propose a fix until you understand the current behavior
4. Check `.issues/` for prior analysis on this issue
5. Update or create `.issues/issue-0XX.md` with findings
6. Determine fix complexity tier (MICRO/SMALL/MEDIUM/LARGE)

**Output**: Root cause identified, affected files listed, complexity tier determined.

**GATE**: Do not proceed to Phase 2 until root cause is understood. If uncertain, spin up research subagents.

### Phase 2 — PLAN

**Goal**: Formulate a concrete fix plan that can be reviewed by skeptical agents.

Plan MUST include all three:
- **Primary fix**: The exact code changes that should resolve the issue, with file:line targets
- **Fallback diagnostic logging**: If the fix ships and the bug persists, what targeted log output would round 2 need? (appropriate level — don't flood)
- **Implementation scope**: List every file to be changed, grouped by zone if 4+ files

**Present the plan to Samantha for approval before proceeding.** The plan should be specific enough that a reviewer can evaluate it without reading the code themselves.

**GATE**: Do not proceed to Phase 3 until the plan is written and presented.

### Phase 3 — SKEPTICAL CONVERGENCE (max 3 loops)

**Goal**: Validate the plan through adversarial review before writing any code.

Launch 2 subagent reviewers **in parallel** on the PLAN:

| Agent | Role |
|-------|------|
| **CONSTRUCTIVE** | Reviews for correctness, completeness, multiplayer safety. "Will this fix work?" Attaches confidence score. |
| **SKEPTIC** | **Adversarial** — assumes the fix WON'T work, demands fallback diagnostic logging, identifies code paths not covered. Must explicitly sign off. Attaches confidence score. |

**SKEPTIC mandate**: The SKEPTIC must answer: *If this fix ships and the bug persists, what log lines would you need to diagnose it?* Those log lines MUST be in the plan.

**Convergence loop**: Revise plan based on feedback, re-launch both reviewers, repeat until **both CONSTRUCTIVE and SKEPTIC agree**. If no consensus after 3 loops, HALT and present disagreements to user.

**GATE**: Do not proceed to Phase 4 until both agents have signed off with confidence scores. Record scores for final report.

### Phase 4 — IMPLEMENT

**Goal**: Execute the agreed plan exactly. No improvising.

If the plan needs changes mid-implementation, **pause and re-enter Phase 3**. Do not silently deviate from the reviewed plan — that defeats the purpose of skeptical convergence.

**Conditional dispatch:**
- **3 or fewer files**: Implement directly (no zone partitioning, no parallel workers).
- **4+ files across multiple zones**: Dispatch parallel subagent workers, zone-partitioned per Gold Mode (no two workers edit the same file).

**After implementation**: Run `node tools/build.js` to verify the build passes. If it fails, fix before proceeding.

**GATE**: Do not proceed to Phase 4.5 until the build passes.

### Phase 4.5 — CODE REVIEW (Mandatory — Do Not Skip)

**Goal**: Verify the actual code changes match the plan and introduce no regressions.

**This phase reviews the ACTUAL CODE CHANGES (git diff), not the plan.** This is critical because implementation often deviates from plans in subtle ways.

Launch review agents **in parallel** on the actual changes:

| Agent | Role | Confidence Score |
|-------|------|-----------------|
| **CORRECTNESS** | Does the implemented code match the plan? Are there deviations, typos, or logic errors? | 0-100% |
| **SIDE-EFFECTS** | Did the changes break anything in adjacent code? Are callers, hooks, and data flows intact? | 0-100% |
| **MULTIPLAYER** | Are events, streams, and server checks correct? Do `writeStream`/`readStream` field counts match? Is `Event.sendToServer()` used where needed? | 0-100% |

**Tier-based scaling** (see Agent Scaling section):
- MICRO: 1 comprehensive reviewer (all 3 roles combined)
- SMALL: 2 reviewers (CORRECTNESS + SIDE-EFFECTS)
- MEDIUM/LARGE: All 3 reviewers

**All reviewers must pass.** If any agent raises a blocking concern, fix the code and re-run the failing reviewer(s). Do not commit until all reviewers sign off.

**GATE**: Do not proceed to Phase 5 until all code review agents have passed with confidence scores. Record scores for final report.

### Phase 5 — VERIFY

**Goal**: Run quality verification protocols on changed files.

1. **Build check**: `node tools/build.js` must pass (already done in Phase 4, but verify again after any Phase 4.5 fixes)
2. **Rosetta validate**: `node translations/rosetta.js validate` — format specifiers must match
3. **AMBER check**: If any `$l10n_` translation keys were added or modified, or if new user-facing strings were hardcoded in Lua, flag for AMBER MODE follow-up

**Conditional quality protocols:**
- **Single-file fixes**: Run GOLD only on the changed zone
- **Multi-file fixes**: Launch **RED + GOLD in parallel**. RED audits security. GOLD checks quality. Both must pass.

**GATE**: Do not commit/push until Phase 5 passes.

---

## Post-Fix Actions (All Mandatory)

After Phase 5 passes, in order:

1. **Commit** with descriptive message referencing `#N` (do NOT use `Closes #N` or `Fixes #N`)
2. **Push** to remote
3. **Compile confidence report** (see Report Format below)
4. **Update `.issues/issue-0XX.md`** with fix details, commit reference, confidence score, and verdict
5. **Comment on GitHub issue** following the Issue Workflow rules in CLAUDE.md (reporter's language, humble certainty, version numbers not commit hashes)
6. **Post auto-close countdown** comment
7. **AMBER consideration**: Flag if translation keys were added/modified

---

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

Present this report after Phase 5 completes. This is the final output of INDIGO mode.

```
Verdict: RESOLVED | Confidence: 85% (GREEN)

Phase 3 (Plan Review):
  CONSTRUCTIVE:  92%  -- plan addresses root cause directly
  SKEPTIC:       85%  -- fallback logging covers the gap if wrong

Phase 4.5 (Code Review):
  CORRECTNESS:   95%  -- implementation matches plan exactly
  SIDE-EFFECTS:  88%  -- no adjacent code affected
  MULTIPLAYER:   90%  -- events and streams verified

Composite: 85% (minimum of all scores)
```

---

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

---

## Verdict Scale

| Verdict | Meaning |
|---------|---------|
| RESOLVED | Fix implemented, code review passed, verification passed, confidence GREEN/YELLOW |
| PARTIAL | Fix implemented but confidence RED or skeptic concerns unresolved — diagnostic logging added for round 2 |
| BLOCKED | Skeptical convergence failed — fundamental disagreement on approach |

---

## Common Shortcuts That Lead to Regressions

These patterns have historically caused issues. Watch for them:

1. **Skipping Phase 4.5 "because the fix is obvious"** — Implementation bugs are never obvious until a reviewer finds them. The wrong vehicle sold (#39) was caused by an "obvious" ID storage choice.

2. **Skipping Phase 5 "because it's just one file"** — Even single-file changes can break the build, introduce security holes, or drift translations.

3. **Implementing before Phase 3 completes** — Writing code before skeptical review means the review is biased toward the existing implementation rather than evaluating the approach objectively.

4. **Ad-hoc skeptical review instead of structured agents** — Asking "does this look right?" is not the same as launching a SKEPTIC agent with a specific mandate. Structured agents find more issues because they have explicit checklists.

5. **Committing before code review** — Once code is committed, there's pressure to ship rather than fix issues found in review. Always review before commit.

6. **Skipping `.issues/` updates** — Issue tracking files are how future sessions understand past decisions. Without them, the same issues get re-investigated from scratch.

---

## Indigo Checklist

Before declaring an issue complete, verify ALL items:

- [ ] 1. GitHub issue researched, latest log analyzed, `.issues/` updated
- [ ] 2. Fix complexity tier determined (MICRO/SMALL/MEDIUM/LARGE)
- [ ] 3. Plan includes primary fix + fallback diagnostic logging + implementation scope
- [ ] 4. Skeptical convergence achieved (CONSTRUCTIVE + SKEPTIC signed off with scores)
- [ ] 5. Implementation complete (direct for <=3 files, zone-partitioned workers for 4+)
- [ ] 6. Build passes (`node tools/build.js`)
- [ ] 7. Code review passed (tier-appropriate reviewer count on actual changes, all with scores)
- [ ] 8. Confidence report compiled (composite score calculated from all reviewers)
- [ ] 9. Verification passed (GOLD-only for single-file, RED+GOLD for multi-file)
- [ ] 10. Rosetta validate passes (`node translations/rosetta.js validate`)
- [ ] 11. `.issues/` file updated with fix details, commit reference, and confidence score
- [ ] 12. Git commit with `#N` reference (NOT `Closes #N`)
- [ ] 13. GitHub issue commented (reporter's language, version numbers, humble certainty)
- [ ] 14. Auto-close countdown posted
- [ ] 15. AMBER consideration: flag if translation keys added/modified
