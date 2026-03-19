# AMBER MODE — Translation Quality Convergence Protocol

Amber Mode is a **translation-focused quality convergence loop** that spot-checks all 25 languages, improves rosetta's detection when needed, retranslates quality-flagged entries, and repeats until all languages pass clean.

**RULE**: Amber Mode is **explicit-only**. Full protocol details in [`translations/README.md`](../../translations/README.md). Max 5 passes (pre-flight + up to 5 convergence passes).

**Activation Triggers**: "amber mode" / "translation quality" / "translation sweep"

---

## Pre-Flight: Rosetta Validation

**Before launching Pass 1**, run a pre-flight check to ensure rosetta's detectors are calibrated:

1. Run `rosetta audit` on all 25 languages — capture grades and issue counts
2. Run `rosetta validate` — verify format specifiers and structural integrity
3. Review aggregate false-positive rates per detector category (diacritics, truncation, suspect, CJK, morphology, etc.)
4. If any detector shows obviously high false-positive rates (>30% of flags appear incorrect on manual sampling), fix `rosetta_lib.js` BEFORE dispatching workers
5. Re-run `rosetta audit` on affected languages to confirm detection improved

**Purpose**: Prevents wasting an entire pass on bad detection. Turns the loop into "calibrate once, then converge" rather than "discover detection bugs through workers, fix, repeat."

---

## The 5 Worker Slots (Linguistic Families)

Each pass launches **5 parallel spot-check workers** grouped by linguistic similarity. This ensures each worker has domain expertise for its language family and enables cross-checking within families.

| Worker | Languages | Family | Rationale |
|--------|-----------|--------|-----------|
| W1 | de, nl, da, no, sv | Germanic (5) | Shared compound-word patterns, similar diacritic systems, cognate overlap |
| W2 | fr, fc, es, ea, it, pt, br, ro | Romance + variants (8) | Heavy detection overlap; variants (fc/fr, ea/es, br/pt) cross-checked against parents within same worker |
| W3 | pl, cz, hu, tr, fi | Complex morphology (5) | Finno-Ugric, Slavic with heavy diacritics, agglutinative — all share rich inflection and diacritic requirements |
| W4 | ru, uk, vi, id | Cyrillic + SEA (4) | Cyrillic script pair (ru/uk) + tonal/isolating languages with distinct detection needs |
| W5 | ct, jp, kr | CJK (3) | Only 3 languages but heavy per-language workload with 6 dedicated detection mechanisms (CJK ratio, English word detection, character validation, truncation thresholds, script mixing, fullwidth) |

**Note**: W2 has 8 languages but detection issues overlap heavily across Romance languages, and variant pairs (fc vs fr, ea vs es, br vs pt) benefit from being in the same worker for direct divergence comparison. W5 has only 3 but each requires intensive CJK-specific analysis.

---

## Worker Task Protocol (Per Pass)

Each worker is a subagent that performs the following for each assigned language:

### Step 1: Automated Audit + Validation
Run both commands and capture results:
- `node translations/rosetta.js audit LANG` — grade (A-F), issue counts by category
- `node translations/rosetta.js validate` — format specifier integrity for the language

### Step 2: Spot-Check (Manual Review)

Spot-check count scales by pass and grade:

| Condition | Spot-Check Count |
|-----------|-----------------|
| Pass 1 (any grade) | 10-15 random entries (baseline sampling) |
| Pass 2+ (grade A-C) | All entries retranslated in previous pass + 5 random entries |
| Any pass, grade D or F | 25-30 entries (expanded sampling for troubled languages) |

For each spot-checked entry, evaluate:
- **Naturalness**: Does the translation read like a native speaker wrote it?
- **Accuracy**: Does the meaning match the English source? Are gaming/financial terms correct?
- **Completeness**: Is the full meaning conveyed, or was content truncated/summarized?
- **Diacritics**: Are the correct characters used for the language?
- **Format specifiers**: Are `%s`, `%d`, `%.1f`, `%.2f`, `%%` preserved exactly?
- **Context**: Does the translation make sense in a farming simulation UI context?

### Step 3: Evaluate Rosetta Detection
For each issue rosetta flagged:
- **True positive?** The detection correctly identified a real problem.
- **False positive?** The detection incorrectly flagged a correct translation. Document the pattern and why it's wrong.

For entries rosetta did NOT flag:
- **False negative?** A bad translation that rosetta's detection missed. Document what detection rule should catch it.

### Step 4: Return Structured Report

```json
{
  "worker": "W2",
  "pass": 2,
  "languages": {
    "fr": {
      "grade": "B",
      "issueCount": 8,
      "breakdown": { "diacritics": 3, "truncation": 2, "suspect": 3 },
      "retranslatedDelta": { "improved": 5, "unchanged": 1, "regressed": 0 },
      "spotCheckIssues": 1
    },
    "es": {
      "grade": "A",
      "issueCount": 0,
      "breakdown": {},
      "retranslatedDelta": { "improved": 3, "unchanged": 0, "regressed": 0 },
      "spotCheckIssues": 0
    }
  },
  "rosettaBugs": [
    { "type": "false_positive", "detector": "diacritics", "lang": "fr", "key": "usedplus_example", "reason": "French word 'resume' is valid without accent in this context" },
    { "type": "false_negative", "lang": "it", "key": "usedplus_other", "reason": "Translation truncated but below rosetta's length threshold" }
  ],
  "qualityIssues": [
    { "lang": "fr", "key": "usedplus_loan_term", "issue": "Translates 'term' as 'terme' but should be 'duree' in financial context", "severity": "MED" }
  ],
  "summary": "7/8 languages clean. French needs quality retranslation for 3 remaining entries."
}
```

**Report field definitions:**
- `breakdown`: Issue count per rosetta detection category (diacritics, truncation, suspect, cjk, morphology, engfw, entities, colons, suffix, chars, identical, etc.)
- `retranslatedDelta`: Only present on pass 2+. Tracks how entries retranslated in the previous pass fared: `improved` (issue resolved), `unchanged` (same issue persists), `regressed` (new issue introduced by retranslation)
- `spotCheckIssues`: Number of problems found during manual review that rosetta did NOT flag

---

## Main Agent Orchestration (Between Passes)

After collecting all 5 worker reports, the main agent runs three phases:

### Phase A: Rosetta Improvement

If ANY worker reported `rosettaBugs`:
1. Categorize bugs: false positives (detection too aggressive) vs false negatives (detection gaps)
2. Edit `translations/rosetta_lib.js` to fix detection logic
3. Run `node translations/rosetta.js audit` on affected languages to verify fix
4. Run `node translations/rosetta.js validate` to ensure no regressions

**RULE**: Rosetta improvements MUST be made before retranslation, so the next export reflects corrected detection. This is a hard dependency — skipping it causes oscillation (fix in pass N, re-flag in pass N+1).

### Phase A.5: Cross-Language Synthesis

After rosetta fixes, before retranslation, the main agent performs cross-language analysis using worker report data:

1. **Translation length outlier detection**: For each key, compare translation lengths across all 25 languages. Flag entries where one language's translation is >2x or <0.5x the median length — likely truncation or over-elaboration.

2. **Variant divergence check**: Compare variant languages against their parent:
   - `fc` (French Canadian) vs `fr` (French) — flag entries where fc diverges significantly in length or structure
   - `ea` (Latin American Spanish) vs `es` (Spanish) — same
   - `br` (Brazilian Portuguese) vs `pt` (Portuguese) — same

   Minor lexical differences are expected; structural divergence (missing sentences, vastly different length) indicates a problem. W2 has all variant pairs in the same worker, so this data is available within the worker report. For cross-worker comparisons, the main agent synthesizes.

3. **Cognate/identical entry auditing**: Across all non-English languages, flag entries where the translation is identical to English source (after normalizing XML entities). Entries that are legitimately identical across many languages (proper nouns, abbreviations, technical terms) are expected — flag entries identical in only 1-3 languages as likely untranslated.

Findings from synthesis feed into Phase B as additional retranslation targets.

### Phase B: Quality Retranslation

If ANY worker reported `qualityIssues`, or Phase A.5 identified issues:
1. For each affected language, export quality-flagged entries:
   `node translations/rosetta.js translate LANG --quality`
   (optionally with `--filter=TYPE` for targeted categories)
2. Dispatch **Haiku translator agents** via `subagent_type: "translator"` (NEVER Opus)
3. Import results via `rosetta import`
4. Run `node translations/rosetta.js audit LANG` on affected languages to verify improvement

### Phase C: Verification & Convergence

Combined completion and convergence check:

1. **Completion**: Run `rosetta status` — verify all 25 languages at 100%. Run `rosetta validate` — verify format specifiers intact. If any language below 100% or validation fails, export and fix before proceeding.

2. **Convergence**: Compare total issue counts to previous pass:
   - **Total issues decreased** → proceed to next pass
   - **Total issues = 0** → CONVERGED, stop
   - **Total issues stalled or increased** → HALT (something is wrong — detection oscillation or retranslation regression)
   - **Pass 5 reached** → HALT regardless

3. **Retranslation delta review**: Check `retranslatedDelta` across all workers. If `regressed > 0` for any language, investigate before next pass — retranslation should never make things worse.

---

## Convergence Rules

| Rule | Description |
|------|-------------|
| Pre-flight first | Calibrate rosetta detectors before Pass 1 |
| Max passes | 5 (hard limit), not counting pre-flight |
| Monotonic decrease | Total issues must decrease each pass, else HALT |
| Zero = done | 0 issues across all 5 workers = success |
| Stalled = halt | Same issue count on consecutive passes = HALT |
| Rosetta first | Always fix detection BEFORE retranslating (hard dependency) |
| No regression | Retranslation must not introduce new issues (`regressed` = 0) |

**Why 5 passes (not 3 like Gold)?** Amber has a dimension Gold lacks: mutable detection rules. Each pass can fix rosetta AND retranslate, meaning pass N's detection may classify entries differently than pass N-1. This extra degree of freedom justifies the higher pass limit while the rosetta-first hard dependency prevents oscillation.

---

## Verdict Scale

| Verdict | Criteria | Meaning |
|---------|----------|---------|
| PRISTINE | Pass 1: all 25 languages grade A, 0 issues, 0 spot-check problems | Translations are production-ready |
| POLISHED | Converged to 0 issues within passes 2-5 | Found and fixed all issues |
| ACCEPTABLE | Halted with <=5 LOW-severity issues remaining | Minor imperfections, safe to ship |
| NEEDS ATTENTION | Unresolved MED/HIGH issues, or did not converge | Manual review required |

---

## Pass Summary Table (Output After Each Pass)

```
| Pass | W1 Issues | W2 Issues | W3 Issues | W4 Issues | W5 Issues | Total | Rosetta Fixes | Retranslated | Regressed |
|------|-----------|-----------|-----------|-----------|-----------|-------|---------------|--------------|-----------|
| PF   | —         | —         | —         | —         | —         | —     | 3             | 0            | —         |
| 1    | 4         | 11        | 7         | 3         | 5         | 30    | 2             | 4 langs      | 0         |
| 2    | 1         | 3         | 0         | 1         | 1         | 6     | 1             | 3 langs      | 0         |
| 3    | 0         | 0         | 0         | 0         | 0         | 0     | 0             | 0            | 0         |
Verdict: POLISHED (converged in 3 passes after pre-flight)
```

---

## Amber Checklist

1. User explicitly requested Amber Mode
2. Pre-flight: `rosetta audit` + `rosetta validate` on all 25 languages; fix high false-positive detectors
3. 5 workers launched in parallel (one per linguistic family)
4. Each worker: audit + validate + scaled spot-check + rosetta evaluation + structured report with breakdown and delta
5. Main agent Phase A: rosetta fixes BEFORE retranslation (hard dependency)
6. Main agent Phase A.5: cross-language synthesis (length outliers, variant divergence, cognate audit)
7. Main agent Phase B: quality retranslation via Haiku agents (NEVER Opus)
8. Main agent Phase C: completion verified at 100%, convergence tracked, regression delta reviewed
9. Max 5 passes enforced (not counting pre-flight)
10. Final verdict with pass summary table

---

## What Amber Mode Does NOT Do

- Does NOT modify Lua source code, GUI XML, or modDesc.xml
- Does NOT touch the English source translations (use `amend` command for that)
- Does NOT add or remove translation keys (use `deposit`/`remove` for that)
- Does NOT run `node tools/build.js` — only rosetta commands
- Does NOT bypass the translator agent rule — all retranslation goes through Haiku agents
