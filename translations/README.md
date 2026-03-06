# FS25_UsedPlus Translations

This folder contains all localization files for the UsedPlus mod.

## Quick Start

```bash
cd translations/
node rosetta.js status    # See current state
node rosetta.js sync      # Sync all languages
node rosetta.js report    # Detailed breakdown
node rosetta.js help      # Full documentation
```

## Files

| File | Language | Code |
|------|----------|------|
| `translation_en.xml` | English (source) | EN |
| `translation_de.xml` | German | DE |
| `translation_fr.xml` | French | FR |
| `translation_es.xml` | Spanish | ES |
| `translation_it.xml` | Italian | IT |
| `translation_pl.xml` | Polish | PL |
| `translation_ru.xml` | Russian | RU |
| `translation_br.xml` | Brazilian Portuguese | BR |
| `translation_cz.xml` | Czech | CZ |
| `translation_uk.xml` | Ukrainian | UK |

## Entry Format

Each translation entry uses this format:

```xml
<e k="usedplus_finance_title" v="Vehicle Financing" eh="6efef1bd" />
```

| Attribute | Description |
|-----------|-------------|
| `k` | Key - unique identifier referenced in Lua code |
| `v` | Value - the translated text |
| `eh` | English Hash - 8-character MD5 hash of the English source text |

## How Hash-Based Sync Works

The `eh` (English Hash) attribute tracks when translations become stale:

```
English:  <e k="greeting" v="Hello World" eh="a1b2c3d4"/>
German:   <e k="greeting" v="Hallo Welt" eh="a1b2c3d4"/>   <- Same hash = OK
French:   <e k="greeting" v="Bonjour" eh="99999999"/>     <- Different = STALE!
```

When you change English text:
1. Run `sync` - English hash auto-updates
2. Target hashes stay the same (they reflect what was translated FROM)
3. Hash mismatch = translation is STALE (needs re-translation)

## Rosetta.js — Translation Management Tool (v1.0.0)

`rosetta.js` manages translation synchronization, validation, and key lifecycle.

### Commands

```bash
node rosetta.js sync                    # Add missing keys, update hashes
node rosetta.js status                  # Quick table overview
node rosetta.js report [LANG]           # Detailed lists by language
node rosetta.js check                   # Exit code 1 if missing keys
node rosetta.js validate                # CI-friendly, minimal output
node rosetta.js unused                  # List dead keys not in codebase
node rosetta.js deposit KEY VALUE       # Add key atomically to ALL files
node rosetta.js amend KEY NEW_VALUE     # Change English, mark translations stale
node rosetta.js rename OLD_KEY NEW_KEY  # Rename across all files
node rosetta.js remove KEY [KEY...]     # Delete from all files
node rosetta.js translate LANG [--stale]  # Export JSON for AI translation
node rosetta.js import FILE.json        # Import translations with validation
node rosetta.js doctor [--fix]          # Health check + auto-fix
node rosetta.js help                    # Full documentation
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

### Example Output

**status command:**
```
Language            | Translated |  Stale  | Untranslated | Missing | Dups | Orphaned
-----------------------------------------------------------------------------------------------
German              |       1954 |       0 |            0 |       0 |    0 |        0
French              |       1954 |       0 |            0 |       0 |    0 |        0
```

## Workflow

### Adding New Keys (Recommended)

1. Run `node rosetta.js deposit usedplus_new_key "English text"`
2. Key is added atomically to English (real value) + all 25 languages (`[EN]` placeholder)
3. Use `node rosetta.js translate de` to export JSON for AI translation
4. Import results: `node rosetta.js import de_translated.json`

### Adding New Keys (Manual)

1. Add the new key to `translation_en.xml`
2. Run `node rosetta.js sync`
3. Script automatically adds key to all languages with `[EN]` prefix
4. Translators update values and remove prefix

### Updating English Text

1. Run `node rosetta.js amend usedplus_key "New English text"`
2. English value + hash updated, all translations marked stale automatically
3. Use `translate` command to export stale entries for re-translation

### Verifying Translations

```bash
node rosetta.js status    # Quick check
node rosetta.js report    # See exactly which keys need work
node rosetta.js doctor    # Comprehensive health check
```

## Translation Guidelines

### Placeholders (CRITICAL!)

Format specifiers MUST be preserved exactly - wrong specifiers crash the game:

| Specifier | Type | Example |
|-----------|------|---------|
| `%s` | String | `"Hello %s"` -> `"Hola %s"` |
| `%d` | Integer | `"Count: %d"` -> `"Anzahl: %d"` |
| `%.1f` | Decimal (1 place) | `"%.1f hours"` -> `"%.1f Stunden"` |
| `%.2f` | Decimal (2 places) | `"$%.2f"` -> `"%.2f EUR"` |

The sync tool validates these automatically and reports FORMAT ERRORS.

### Context Matters

| English | Context | Correct Translation Approach |
|---------|---------|------------------------------|
| Poor | Credit rating | "Bad" quality, not "impoverished" |
| Fair | Credit rating | "Acceptable/Passable", not "just/equitable" |
| Good | Credit rating | Adjective "good", not adverb "well" |

### Special Characters

XML requires escaping these characters:

| Character | Escape Sequence |
|-----------|-----------------|
| `<` | `&lt;` |
| `>` | `&gt;` |
| `&` | `&amp;` |
| `"` | `&quot;` |

Example: `<e k="key" v="Score &lt;600 is poor" />`

## Requirements

- Node.js (any recent version)
- No external dependencies (uses only Node.js standard library)
