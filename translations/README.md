# FS25_UsedPlus Translations

**Last Updated:** 2026-03-07 | **Parent:** [`CLAUDE.md`](../CLAUDE.md)

This directory contains all localization files for the UsedPlus mod and is the single source of truth for translation tooling, workflows, quality detection, and the AMBER mode protocol.

---

## Overview

FS25_UsedPlus supports **25 target languages** (+ English source) with **~2,567 translation entries** each. All translation management flows through `rosetta.js` in this directory.

**Architecture:** Rosetta v1.1.0 is split into two files:
- `rosetta.js` — CLI entry point, all cmd* functions, help text, CLI router
- `rosetta_lib.js` — shared library (CONFIG, utilities, XML I/O, classification, quality detection, JSON protocol, formatters)

**File limit:** `rosetta.js` exception is 2500 lines (per CLAUDE.md Code Quality Rules).

**Requirements:** Node.js (any recent version). No external dependencies.

---

## Entry Format

Each translation entry uses this format:

```xml
<e k="usedplus_finance_title" v="Vehicle Financing" eh="6efef1bd" />
```

| Attribute | Description |
|-----------|-------------|
| `k` | Key — unique identifier referenced in Lua code |
| `v` | Value — the translated text |
| `eh` | English Hash — 8-character MD5 hash of the English source text |

### How Hash-Based Sync Works

The `eh` (English Hash) attribute tracks when translations become stale:

```
English:  <e k="greeting" v="Hello World" eh="a1b2c3d4"/>
German:   <e k="greeting" v="Hallo Welt" eh="a1b2c3d4"/>   <- Same hash = OK
French:   <e k="greeting" v="Bonjour" eh="99999999"/>       <- Different = STALE!
```

When you change English text:
1. Run `sync` — English hash auto-updates
2. Target hashes stay the same (they reflect what was translated FROM)
3. Hash mismatch = translation is STALE (needs re-translation)

---

## Rosetta.js Commands

```bash
cd translations

# Status & Reporting
node rosetta.js status              # Quick overview table per language
node rosetta.js report [LANG]       # Detailed breakdown with key lists
node rosetta.js validate            # CI-friendly: exit codes only
node rosetta.js audit [LANG]        # Deep quality audit with grades (A-F)
node rosetta.js inspect KEY [KEY]   # View key value across all 26 languages

# Structural Operations
node rosetta.js sync                # Add missing keys, update hashes
node rosetta.js doctor [--fix]      # Health check + auto-fix
node rosetta.js deposit KEY "text"  # Add key to ALL 26 files
node rosetta.js amend KEY "text"    # Change English, mark stale
node rosetta.js rename OLD NEW      # Rename, preserve translations
node rosetta.js remove KEY1 KEY2    # Delete from ALL files

# Translation Export/Import
node rosetta.js translate LANG      # Export untranslated as JSON (add --compact for 70% smaller)
node rosetta.js translate LANG --quality                # Export all quality-flagged entries
node rosetta.js translate LANG --quality --filter=TYPE  # Export specific issue type only
node rosetta.js import FILE.json [FILE2.json...]        # Import with validation (supports globs)

# Maintenance
node rosetta.js fix [LANG] --entities  # Auto-fix double-encoded XML entities
node rosetta.js fix-stale [LANG]       # Accept current translations, update hashes
node rosetta.js cleanup [--force]      # Remove temporary translation files
node rosetta.js format                 # Reformat XML files
node rosetta.js unused                 # List unused translation keys
```

### What It Detects

| Symbol | Meaning | Action |
|--------|---------|--------|
| Translated | Up to date | No action needed |
| Stale | English changed | Needs re-translation |
| Untranslated | Has `[EN]` prefix or matches English | Needs translation |
| Missing | Key not in target file | Sync adds it |
| Duplicate | Same key twice in file | Remove one! |
| Orphaned | Key in target but not English | Safe to delete |
| Format Error | Wrong `%s`/`%d` specifiers | WILL CRASH GAME! |
| Empty/Whitespace | Empty value or leading/trailing spaces | Fix value |

### Quality Filter Types

Used with `--quality --filter=TYPE`:

| Type | What It Catches |
|------|-----------------|
| `truncated` | Translations <40% source length (15% for CJK) or sentence count drop |
| `diacritics` | Missing expected diacritics for the language (e.g., Finnish without a/o) |
| `cjk` | English words appearing in CJK translations |
| `engfw` | English function words remaining in non-English translations |
| `morphology` | Suspicious morphological patterns (skips Romance + Dutch) |
| `suspect` | Entries that look untranslated after stripping URLs/numbers/proper nouns |
| `entities` | Double-encoded XML entities (`&amp;amp;`) |
| `untranslated` | Entries identical to English (after entity normalization) |
| `missing` | Keys present in English but absent in target |
| `reorder` | Format specifier order mismatches |
| `colons` | Source ends with `:` but translation doesn't (or vice versa) |
| `suffix` | Inline suffix pattern mismatches |
| `identical` | Entries identical to English that aren't cognates/format-only |
| `variant` | Variant-specific issues |
| `chars` | Character/script issues |

---

## Workflows

### Adding New Keys

1. `node rosetta.js deposit usedplus_new_key "English text here"`
2. `node rosetta.js translate LANG` — export untranslated JSON
3. Dispatch translator agent (see Bulk Translation below)
4. `node rosetta.js status` — verify counts

### Updating English Text

1. `node rosetta.js amend usedplus_key "New English text"`
2. English value + hash updated, all translations marked stale automatically
3. Use `translate` command to export stale entries for re-translation

### Bulk Translation — Translator Agent (MANDATORY)

**RULE:** For bulk translation, ALWAYS use the custom Haiku translator agent at `.claude/agents/translator.md`. NEVER use Opus agents for translation — it wastes tokens.

```
Agent tool -> subagent_type: "translator"
Prompt: "Translate FS25_UsedPlus to Finnish (fi)."
```

The translator agent handles: JSON protocol (`rosetta-import-v1`), format specifier preservation, import schema, file naming (timestamp suffix for parallel safety), and the rosetta import command. All rules are baked into the agent definition — dispatch prompts only need the language code.

### Quality Retranslation

To fix quality issues in an existing language:
1. `node rosetta.js translate LANG --quality` — exports all flagged entries
2. `node rosetta.js translate LANG --quality --filter=TYPE` — exports specific issue type
3. Dispatch translator agent with the quality export file
4. `node rosetta.js audit LANG` — verify improvement

---

## Translation Guidelines

### Format Specifiers (CRITICAL — game will crash if wrong)

Format specifiers MUST be preserved exactly — wrong specifiers crash the game:

| Specifier | Type | Example |
|-----------|------|---------|
| `%s` | String | `"Hello %s"` -> `"Hola %s"` |
| `%d` | Integer | `"Count: %d"` -> `"Anzahl: %d"` |
| `%.1f` | Decimal (1 place) | `"%.1f hours"` -> `"%.1f Stunden"` |
| `%.2f` | Decimal (2 places) | `"$%.2f"` -> `"%.2f EUR"` |
| `%+d` | Signed integer | `"%+d pts"` (shows "+5 pts") |
| `%%` | Literal percent | `"90%%"` (shows "90%") |

### Context Matters

| English | Context | Correct Translation Approach |
|---------|---------|------------------------------|
| Poor | Credit rating | "Bad" quality, not "impoverished" |
| Fair | Credit rating | "Acceptable/Passable", not "just/equitable" |
| Good | Credit rating | Adjective "good", not adverb "well" |

### Special Characters (XML Escaping)

| Character | Escape Sequence |
|-----------|-----------------|
| `<` | `&lt;` |
| `>` | `&gt;` |
| `&` | `&amp;` |
| `"` | `&quot;` |

Preserve `&#10;` as `&#10;` (XML newline). Do NOT convert to `\n`.

---

## Quality Detection Reference (rosetta_lib.js)

### Key Functions & Constants

| Function / Constant | Purpose |
|---------------------|---------|
| `escapeXml()` | Entity-aware regex `&(?!(?:amp\|lt\|gt\|quot\|apos\|#\d+\|#x[0-9a-fA-F]+);)` — prevents double-encoding |
| `normalizeXmlEntities()` | Normalizes `&gt;`/`&lt;`/`&amp;`/`&quot;`/`&apos;` for untranslated comparison |
| `CJK_LANGS` | `['ct', 'jp', 'kr']` — EA is Spanish Latin America, NOT CJK |
| `DIACRITIC_LANGS` | Maps 16 lang codes to expected character regex patterns (including NL for trema) |
| `ENGLISH_FUNCTION_WORDS` | Set for detecting untranslated content |
| `ENGLISH_CONTENT_BLOCKLIST` | 44 common English words that should never appear untranslated |
| `STRIPPED_WORD_SENTINELS` | Per-language regex matching common words that always need diacritics |

### classifyEntries() Output

Returns quality arrays:
- `doubleEncodedEntities` — `&amp;amp;` style double-encoding
- `cjkIssues` — English words in CJK translations (strict 30-word blocklist)
- `diacriticIssues` — Missing expected diacritics (with triggering words)
- `morphologyIssues` — Suspicious patterns (skips Romance + Dutch)
- `englishFunctionWordIssues` — English function words remaining
- `truncationIssues` — Translations suspiciously shorter than source
- `suspectTranslations` — Entries that look untranslated
- `colonMismatches` — Colon consistency (source vs translation)
- `characterIssues` — Wrong character set for language
- `scriptIssues` — Wrong script (e.g., Latin in CJK)
- `inlineSuffixIssues` — Suffix pattern mismatches

### Detection Details

- **Diacritics**: Word extraction splits on whitespace/punctuation (NOT ASCII `\b`) to prevent fragments. Skips ALL-UPPERCASE words (Turkish dotless i valid in uppercase).
- **Truncation**: Non-CJK <40% of source length; CJK uses 15% threshold; also checks sentence count (3+ source sentences -> 1 target = truncated).
- **Suspect**: Strips URLs, numbers, proper nouns before word comparison. Content blocklist has `alreadySuspect` flag to avoid double-flagging.
- **CJK English**: Strict 30-word blocklist where common English words should never appear.
- **Colons**: Flags entries where source ends with `:` but translation doesn't.
- **NL trema**: Sentinels for `geinstalleerd` -> `geinstalleerd`, `beeindigd` -> `beeindigd`.

### Sentinel Tuning Lessons

These false positives have been resolved — do NOT re-introduce:
- Turkish `arac*` = false positive (consonant mutation c -> c)
- Polish `twoj\w*` -> `twoj\b` (declined forms like Twojej/Twoja are correct)
- Finnish `valitt*` removed (valittu is correct)
- IT/RO `necesit(t)a` removed (verb form correct without accent)

---

## Language Codes Reference

| Code | Language | Code | Language |
|------|----------|------|----------|
| br | Portuguese (Brazil) | kr | Korean |
| ct | Chinese (Traditional) | nl | Dutch |
| cz | Czech | no | Norwegian (Bokmal) |
| da | Danish | pl | Polish |
| de | German | pt | Portuguese (Portugal) |
| ea | Spanish (Latin America) | ro | Romanian |
| en | English (source) | ru | Russian |
| es | Spanish | sv | Swedish |
| fc | French (Canadian) | tr | Turkish |
| fi | Finnish | uk | Ukrainian |
| fr | French | vi | Vietnamese |
| hu | Hungarian | | |
| id | Indonesian | | |
| it | Italian | | |
| jp | Japanese | | |

---

## Key Counts

- 2567 translation keys across 25 target languages (+ English source)
- 588 unused, 1979 active (as of 2026-03-07)

---

## AMBER MODE — Translation Quality Convergence Protocol

### What Is Amber Mode?

Amber Mode is a **translation-focused quality convergence loop** that spot-checks all 25 languages, improves rosetta's detection when false positives/negatives are found, retranslates quality-flagged entries, and repeats until all languages pass clean. Unlike Gold Mode (code quality) or Blue Mode (diagnostics), Amber Mode exclusively targets translation quality across the full language matrix.

**RULE**: Amber Mode is **explicit-only** — never auto-triggered by the Color Gate. Uses **5 parallel spot-check workers** per pass, with rosetta improvement and retranslation between passes. Max 5 passes.

**Activation Triggers**: "amber mode" / "translation quality" / "translation sweep" / "translation convergence"

### The 5 Worker Slots (Language Families)

Each pass launches 5 parallel subagent workers. Each worker owns a batch of 5 languages grouped by linguistic family, ensuring language-specific expertise per worker.

| Worker | Languages | Family |
|--------|-----------|--------|
| W1 | de, fr, es, it, pt | Western European |
| W2 | pl, cz, hu, ro, tr | Central/Eastern European |
| W3 | nl, da, no, sv, fi | Nordic + Dutch |
| W4 | ru, uk, vi, id, br | Slavic + SEA + Brazil |
| W5 | ct, jp, kr, ea, fc | CJK + Regional Variants |

### Worker Task Protocol (Per Pass)

Each worker is a subagent that performs the following for each of its 5 assigned languages:

#### Step 1: Automated Audit
Run `node translations/rosetta.js audit LANG` and capture the grade (A-F) and issue counts.

#### Step 2: Spot-Check (Manual Review)
Read the translation XML file directly and manually review **10-15 random entries** per language, checking:
- **Naturalness**: Does the translation read like a native speaker wrote it? Or is it stiff/mechanical?
- **Accuracy**: Does the meaning match the English source? Are gaming terms correct?
- **Completeness**: Is the full meaning conveyed, or was content truncated/summarized?
- **Diacritics**: Are the correct characters used for the language?
- **Format specifiers**: Are `%s`, `%d`, `%.1f`, `%.2f`, `%%` preserved exactly?
- **Context**: Does the translation make sense in a farming simulation UI context?

#### Step 3: Evaluate Rosetta Detection
For each issue rosetta flagged:
- **True positive?** The detection correctly identified a real problem.
- **False positive?** The detection incorrectly flagged a correct translation. Document the pattern and why it's wrong.

For entries rosetta did NOT flag:
- **False negative?** A bad translation that rosetta's detection missed. Document what detection rule should catch it.

#### Step 4: Return Structured Report

```json
{
  "worker": "W1",
  "pass": 1,
  "languages": {
    "de": { "grade": "A", "issueCount": 2, "spotCheckIssues": 0 },
    "fr": { "grade": "B+", "issueCount": 8, "spotCheckIssues": 3 }
  },
  "rosettaBugs": [
    { "type": "false_positive", "detector": "diacritics", "lang": "fr", "key": "usedplus_example", "reason": "French word 'resume' is valid without accent in this context" },
    { "type": "false_negative", "lang": "de", "key": "usedplus_other", "reason": "Translation uses Austrian German instead of standard" }
  ],
  "qualityIssues": [
    { "lang": "fr", "key": "usedplus_loan_term", "issue": "Translates 'term' as 'terme' but should be 'duree' in financial context", "severity": "MED" }
  ],
  "summary": "4/5 languages clean. French needs quality retranslation for 8 entries."
}
```

### Main Agent Orchestration (Between Passes)

After collecting all 5 worker reports, the main agent:

#### Phase A: Rosetta Improvement
If ANY worker reported `rosettaBugs`:
1. Categorize bugs: false positives (detection too aggressive) vs false negatives (detection gaps)
2. Edit `translations/rosetta_lib.js` to fix detection logic
3. Run `node translations/rosetta.js audit` on affected languages to verify fix
4. Run `node translations/rosetta.js validate` to ensure no regressions

**RULE**: Rosetta improvements MUST be made before retranslation, so the next export reflects corrected detection.

#### Phase B: Quality Retranslation
If ANY worker reported `qualityIssues`:
1. For each affected language, export quality-flagged entries:
   `node translations/rosetta.js translate LANG --quality`
2. Dispatch translator agents (one per language, using `subagent_type: "translator"`)
3. After import, run `node translations/rosetta.js audit LANG` to verify improvement

#### Phase C: Completion Check
1. Run `node translations/rosetta.js status` — verify all 25 languages at 100% completion (2567/2567)
2. Run `node translations/rosetta.js validate` — verify format specifiers intact
3. If any language below 100%, export missing entries and dispatch translator agents

#### Phase D: Convergence Check
Track total issues across all workers:
- **Total issues decreased** -> proceed to next pass
- **Total issues = 0** -> CONVERGED, stop
- **Total issues stalled or increased** -> HALT (something is wrong)
- **Pass 5 reached** -> HALT regardless

### Convergence Rules

| Rule | Description |
|------|-------------|
| Max passes | 5 (hard limit) |
| Monotonic decrease | Total issues must decrease each pass, else HALT |
| Zero = done | 0 issues across all 5 workers = success |
| Stalled = halt | Same issue count on consecutive passes = HALT |
| Rosetta first | Always fix detection before retranslating |

### Verdict Scale

| Verdict | Criteria | Meaning |
|---------|----------|---------|
| PRISTINE | Pass 1: all 25 languages grade A, 0 issues, 0 spot-check problems | Translations are production-ready |
| POLISHED | Converged to 0 issues within passes 2-5 | Found and fixed all issues |
| ACCEPTABLE | Halted with <=5 LOW-severity issues remaining | Minor imperfections, safe to ship |
| NEEDS ATTENTION | Unresolved MED/HIGH issues, or did not converge | Manual review required |

### Pass Summary Table (Output After Each Pass)

```
| Pass | W1 Issues | W2 Issues | W3 Issues | W4 Issues | W5 Issues | Total | Rosetta Fixes | Retranslated |
|------|-----------|-----------|-----------|-----------|-----------|-------|---------------|--------------|
| 1    | 3         | 12        | 1         | 8         | 5         | 29    | 2             | 4 langs      |
| 2    | 0         | 3         | 0         | 2         | 1         | 6     | 1             | 2 langs      |
| 3    | 0         | 0         | 0         | 0         | 0         | 0     | 0             | 0            |
Verdict: POLISHED (converged in 3 passes)
```

### Amber Mode Checklist

1. User explicitly requested Amber Mode
2. Rosetta `status` run to establish baseline (completion counts + grades)
3. 5 workers launched in parallel (one per language family)
4. Each worker: audit + spot-check + rosetta evaluation + structured report
5. Main agent: rosetta fixes (Phase A) BEFORE retranslation (Phase B)
6. Completion verified at 100% for all 25 languages (Phase C)
7. Convergence tracked (monotonic decrease, max 5 passes)
8. Translator agents dispatched via `subagent_type: "translator"` (NEVER Opus)
9. Final verdict with pass summary table

### What Amber Mode Does NOT Do

- Does NOT modify Lua source code, GUI XML, or modDesc.xml
- Does NOT touch the English source translations (use `amend` command for that)
- Does NOT add or remove translation keys (use `deposit`/`remove` for that)
- Does NOT run `node tools/build.js` — only rosetta commands
- Does NOT bypass the translator agent rule — all retranslation goes through Haiku agents

---

## Rules Summary

| Rule | Description |
|------|-------------|
| Agent for translation | ALWAYS use `subagent_type: "translator"` (Haiku). NEVER Opus. |
| Rosetta location | `rosetta.js` + `rosetta_lib.js` in this directory. NOT in `tools/`. |
| JSON protocol | Export: `rosetta-translate-v1`. Import: `rosetta-import-v1`. |
| Parallel safety | Output files use timestamp suffix: `{lang}_translated_{HHMMSS}.json` |
| Auto-agent config | `ensureTranslatorAgent()` auto-creates `.claude/agents/translator.md` on every rosetta run |
| Codebase gate | Rosetta scans `placeables/` and `vehicles/` XML for `$l10n_` refs |
