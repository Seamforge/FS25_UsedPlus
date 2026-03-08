#!/usr/bin/env node
/**
 * ROSETTA.JS v1.1.0 — Translation Management CLI for FS25 Mods
 * Named after the Rosetta Stone that decoded multiple languages from a single artifact.
 * Library code in rosetta_lib.js. This file contains CLI commands and routing.
 * Run: node rosetta.js help
 * Author: FS25_UsedPlus Team | License: MIT
 */

const fs = require('fs');
const path = require('path');

const lib = require('./rosetta_lib');
const {
    VERSION, CONFIG, LANGUAGE_NAMES, CJK_LANGS, DIACRITIC_LANGS,
    VARIANT_PAIRS,
    getHash, escapeRegex,
    isFormatOnlyString, detectVariantDivergence,
    classifyEntries, parseTranslationFile,
    getSourceFilePath, getLangFilePath, getEnabledLanguages,
    autoDetectFilePrefix, autoDetectXmlFormat,
    addEntryToContent, updateEntryInContent, removeEntryFromContent, renameKeyInContent,
    atomicWrite, getAllFilePaths,
    initStore, printGateSummary, gateCodebaseValidation, findMissingKeys, findMissingKeysWithFallbacks,
    exportForTranslation, validateAndImport,
    padRight, padLeft, printCheckSummaryTable,
    getFilesRecursive, getModDir,
} = lib;

// --- TRANSLATOR AGENT AUTO-CREATION

const TRANSLATOR_AGENT_PATH = path.resolve(__dirname, '..', '.claude', 'agents', 'translator.md');

function ensureTranslatorAgent() {
    if (fs.existsSync(TRANSLATOR_AGENT_PATH)) {
        // Check if existing agent needs updating (version mismatch)
        const existing = fs.readFileSync(TRANSLATOR_AGENT_PATH, 'utf8');
        if (existing.includes(`rosetta ${VERSION}`)) return;
        // Version changed — regenerate
    }

    const agentDir = path.dirname(TRANSLATOR_AGENT_PATH);
    fs.mkdirSync(agentDir, { recursive: true });

    const content = `---
name: translator
description: Translates JSON content to target languages for the FS25_UsedPlus mod. Use for bulk translation tasks via rosetta.js JSON protocol.
tools: Read, Write, Bash
model: haiku
permissionMode: bypassPermissions
---

# FS25_UsedPlus Translator Agent (rosetta ${VERSION})

You are a professional translator for a farming simulation game mod (FS25_UsedPlus / Farming Simulator 25). You translate game UI text from English to other languages using the rosetta.js JSON protocol.

## Workflow

When given a language code (e.g., "nl") and/or a file path:

1. **Read** the input file specified in the prompt (or default: \`translations/{lang}_translate.json\`)
2. **Translate** ALL entries from English to the target language
3. **Verify** your output has the SAME number of entries as the input — count them
4. **Write** the import file using a unique name (see Naming Convention below)
5. **Import** by running: \`cd ${__dirname} && node rosetta.js import {output_filename} --cleanup\`
6. **Report** the Applied/Rejected counts from the import output
7. **Clean up** — delete any files YOU created (see Cleanup Rules below)

All file paths are relative to \`${__dirname}/\`.

## Cleanup Rules (MANDATORY)

You MUST leave the translations/ directory clean when you finish. This is non-negotiable.

**After a successful import:**
- The \`--cleanup\` flag on the import command auto-deletes the translated JSON file
- If you created ANY other files (scripts, temp files, notes, markdown), DELETE them before finishing
- Run \`ls ${__dirname}/*.json ${__dirname}/*.js ${__dirname}/*.py ${__dirname}/*.md 2>/dev/null | grep -v rosetta | grep -v README | grep -v package\` to verify no temp files remain

**Rules:**
- NEVER create helper scripts (.js, .py, .sh) — do all work inline in your Bash commands
- NEVER create documentation or status files (.md, .txt)
- The ONLY file you should create is the \`{lang}_translated_{HHMMSS}.json\` output file, and \`--cleanup\` deletes it after import
- If import fails and you need to retry, delete the failed output file before creating a new one

## File Naming Convention (Parallel-Safe)

Multiple agents may run for the same language simultaneously. To avoid file collisions:

- **Input files** are provided by the dispatcher — read whatever path you're given
- **Output files** MUST include a unique suffix: \`{lang}_translated_{HHMMSS}.json\`
  - Use the current time (hours/minutes/seconds) as the suffix
  - Get it via: \`date +%H%M%S\` in a Bash command
  - Example: \`fi_translated_143022.json\`
- **Import command** uses the unique output filename:
  \`node rosetta.js import fi_translated_143022.json --cleanup\`

## Output File Format (CRITICAL)

The output JSON MUST use this exact structure:

\`\`\`json
{
  "$schema": "rosetta-import-v1",
  "meta": { "targetLanguage": "XX" },
  "translations": [
    { "key": "usedplus_example_key", "translation": "Translated text here", "sourceHash": "abc12345" }
  ]
}
\`\`\`

**Non-negotiable rules:**
- \`$schema\` MUST be \`"rosetta-import-v1"\` — NOT \`"rosetta-translate-v1"\`
- The array MUST be named \`"translations"\` — NOT \`"entries"\`
- Each object MUST have: \`key\`, \`translation\`, \`sourceHash\`
- Copy \`sourceHash\` exactly from the input file's \`sourceHash\` field

## Format Specifier Rules (CRITICAL — game will crash if wrong)

Preserve ALL format specifiers EXACTLY as they appear in the English source. The count, type, and order MUST match.

| Specifier | Meaning | Example |
|-----------|---------|---------|
| \`%s\` | String | \`Payment for %s\` |
| \`%d\` | Integer | \`%d payments\` |
| \`%.0f\` | Float, 0 decimals | \`%.0f%%\` (shows "85%") |
| \`%.1f\` | Float, 1 decimal | \`$%.1f\` |
| \`%.2f\` | Float, 2 decimals | \`$%.2f\` |
| \`%+d\` | Signed integer | \`%+d pts\` (shows "+5 pts") |
| \`%%\` | Literal percent sign | \`90%%\` (shows "90%") |

**Common pattern:** \`%d component%s\` — the \`%s\` is a plural suffix ("" or "s"). Translate the word but keep \`%s\` for the suffix position. Example: \`%d composant%s\` (French).

## XML Entity Rules

- Preserve \`&#10;\` as \`&#10;\` — this is an XML newline. Do NOT convert to \`\\n\`
- Preserve \`&amp;\` as \`&amp;\` if present in source

## Translation Style

- **Context:** Farming simulation game (tractors, harvesters, fields, loans, leasing)
- **Tone:** Professional, concise, appropriate for game UI
- **Length:** Keep translations concise — UI buttons and labels have limited space
- **Numbers/percentages in parentheses:** Keep as-is. E.g., "Premium (115-130%)" — translate "Premium" if appropriate, keep "(115-130%)"

## Character Set & Diacritics (CRITICAL)

You MUST use the correct characters and diacritics for the target language. Translations that strip accents or use ASCII-only characters when the language requires diacritics are REJECTED as low quality.

**Examples of CORRECT usage:**
- Finnish: ä, ö, å (e.g., "käyttäjä" NOT "kayttaja")
- German: ä, ö, ü, ß (e.g., "Fahrzeugübersicht" NOT "Fahrzeugubersicht")
- French: à, â, ç, é, è, ê, ë, î, ï, ô, ù, û, ü, ÿ, æ, œ (e.g., "véhicule" NOT "vehicule")
- Spanish: á, é, í, ñ, ó, ú, ü, ¿, ¡ (e.g., "vehículo" NOT "vehiculo")
- Czech: á, č, ď, é, ě, í, ň, ó, ř, š, ť, ú, ů, ý, ž
- Polish: ą, ć, ę, ł, ń, ó, ś, ź, ż (e.g., "pojazd" with proper Polish chars)
- Romanian: ă, â, î, ș, ț (e.g., "vehicul" with proper Romanian chars)
- Turkish: ç, ğ, ı, ö, ş, ü, İ (note: dotless ı and dotted İ)
- Hungarian: á, é, í, ó, ö, ő, ú, ü, ű
- Norwegian/Danish: æ, ø, å
- Swedish: ä, ö, å
- Portuguese: à, á, â, ã, ç, é, ê, í, ó, ô, õ, ú
- Italian: à, è, é, ì, í, ò, ó, ù, ú
- Japanese: Use kanji (漢字), hiragana (ひらがな), katakana (カタカナ) — NOT romanized English
- Korean: Use Hangul (한글) — NOT romanized English
- Chinese Traditional: Use traditional characters (繁體中文) — NOT simplified or English

**NEVER** produce ASCII-only translations for languages that require non-ASCII characters. A 50+ character Finnish string with zero ä/ö/å is almost certainly wrong.

## What NOT To Do

- Do NOT translate brand names, mod names ("UsedPlus"), or URLs
- Do NOT translate technical codes (OBD, ECU, CAN, DTC)
- Do NOT add \`[XX]\` prefixes to translations (e.g., \`[FI]\`, \`[PL]\`) — provide actual translations
- Do NOT skip entries — translate ALL of them, even if there are 500+
- Do NOT run \`node tools/build.js\` — only run the rosetta import command
- Do NOT create helper scripts, temporary files, or documentation files
- The ONLY file you write is the translated JSON output file

## Handling Identical Translations

Some entries are legitimately the same in English and the target language:
- **Format-only strings** like \`%s: %s - %s +%.0f%%\` — keep identical
- **International terms** like "Premium", "Portfolio", "OBD Scanner" — keep or minimally adapt
- **Technical labels** like "Cell [A1]" — keep identical if the word is the same in target language

This is fine — rosetta.js handles these correctly.

## Language Codes Reference

| Code | Language | Code | Language |
|------|----------|------|----------|
| br | Portuguese (Brazil) | kr | Korean |
| ct | Chinese (Traditional) | nl | Dutch |
| cz | Czech | no | Norwegian (Bokmål) |
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

## Error Handling

- If the import reports rejected entries, check format specifier mismatches
- If the input file has 0 entries, report "nothing to translate" and stop
- If you encounter encoding issues, ensure the output file is UTF-8
`;

    fs.writeFileSync(TRANSLATOR_AGENT_PATH, content, 'utf8');
    console.log(`Created translator agent: ${path.relative(process.cwd(), TRANSLATOR_AGENT_PATH)}`);
}

// --- COMMAND HELPERS (used only by specific commands)

function updateSourceHashes(sourceFile, format) {
    let content = fs.readFileSync(sourceFile, 'utf8');
    const { entries } = parseTranslationFile(sourceFile, format);
    let updated = 0;

    for (const [key, data] of entries) {
        const correctHash = getHash(data.value);
        if (data.hash !== correctHash) {
            const oldPattern = new RegExp(
                `<e k="${escapeRegex(key)}" v="([^"]*)"([^>]*)\\s*/>`, 'g'
            );
            content = content.replace(oldPattern, (match, value, attrs) => {
                const cleanAttrs = attrs.replace(/\s*eh="[^"]*"/g, '');
                const tagMatch = cleanAttrs.match(/tag="([^"]*)"/);
                const tagAttr = tagMatch ? ` tag="${tagMatch[1]}"` : '';
                return `<e k="${key}" v="${value}" eh="${correctHash}"${tagAttr} />`;
            });
            updated++;
        }
    }

    if (updated > 0) {
        atomicWrite(sourceFile, content);
    }
    return updated;
}

function findReverseOrphans(modDir, sourceEntries) {
    const reverseOrphans = [];
    const srcDir = path.join(modDir, 'src');
    const guiDir = path.join(modDir, 'gui');

    const luaFiles = getFilesRecursive(srcDir, ['.lua']);
    for (const luaFile of luaFiles) {
        const content = fs.readFileSync(luaFile, 'utf8');
        const pattern = /getText\("(usedplus_[a-zA-Z0-9_]+|usedPlus_[a-zA-Z0-9_]+)"\)/g;
        let match;
        while ((match = pattern.exec(content)) !== null) {
            const key = match[1];
            if (!sourceEntries.has(key)) {
                reverseOrphans.push({ key, file: path.relative(modDir, luaFile) });
            }
        }
    }

    const xmlFiles = getFilesRecursive(guiDir, ['.xml']);
    for (const xmlFile of xmlFiles) {
        const content = fs.readFileSync(xmlFile, 'utf8');
        const pattern = /\$l10n_(usedplus_[a-zA-Z0-9_]+|usedPlus_[a-zA-Z0-9_]+)/g;
        let match;
        while ((match = pattern.exec(content)) !== null) {
            const key = match[1];
            if (!sourceEntries.has(key)) {
                reverseOrphans.push({ key, file: path.relative(modDir, xmlFile) });
            }
        }
    }

    const seen = new Set();
    return reverseOrphans.filter(o => {
        const id = `${o.key}:${o.file}`;
        if (seen.has(id)) return false;
        seen.add(id);
        return true;
    });
}

// --- READ-ONLY COMMANDS: status, report, check, validate, unused, audit

function cmdStatus() {
    const store = initStore();

    console.log();
    console.log("======================================================================");
    console.log(`ROSETTA STATUS v${VERSION}`);
    console.log("======================================================================");
    console.log();
    console.log(`Source: ${store.sourceFile} (${store.sourceEntries.size} keys, ${store.gate.activeKeyCount} active)`);
    console.log(`Format: ${store.format}${store.format === 'elements' ? ' (hash-enabled)' : ''}`);
    console.log();
    printGateSummary(store.gate, store.sourceEntries.size);

    console.log("Language            | Translated |  Stale  | Untranslated | Missing | Dups | Orphaned");
    console.log("-----------------------------------------------------------------------------------------------");

    for (const { code: langCode, name: langName } of store.enabledLangs) {
        const langFile = getLangFilePath(store.filePrefix, langCode);

        if (!fs.existsSync(langFile)) {
            console.log(`${padRight(langName, 20)}|    N/A     |   N/A   |     N/A      |   N/A   |  N/A |    N/A`);
            continue;
        }

        const { entries: langEntries, orderedKeys: langKeys, duplicates: langDuplicates } = parseTranslationFile(langFile, store.format);
        const cls = classifyEntries(store.sourceEntries, store.sourceHashes, langEntries, langKeys, store.format, langCode);

        const duplicates = langDuplicates ? langDuplicates.length : 0;
        const fmtStr = cls.formatErrors.length > 0 ? ` !${cls.formatErrors.length}` : '';
        const entityStr = cls.doubleEncodedEntities.length > 0 ? ` !!${cls.doubleEncodedEntities.length}` : '';
        const suspectStr = cls.suspectTranslations.length > 0 ? ` ?${cls.suspectTranslations.length}` : '';
        const orderStr = cls.formatOrderWarnings.length > 0 ? ` ~${cls.formatOrderWarnings.length}` : '';

        console.log(`${padRight(langName, 20)}| ${padLeft(cls.translated.length, 10)} | ${padLeft(cls.stale.length, 7)} | ${padLeft(cls.untranslated.length, 12)} | ${padLeft(cls.missing.length, 7)} | ${padLeft(duplicates, 4)} | ${padLeft(cls.orphaned.length, 8)}${fmtStr}${suspectStr}${orderStr}${entityStr}`);
    }

    console.log("-----------------------------------------------------------------------------------------------");
    console.log("!N = Format specifier errors (CRITICAL)  ?N = Suspect translations  ~N = Format order warnings");
    console.log("!!N = Double-encoded XML entities");
}

function cmdReport() {
    const store = initStore();
    const targetLang = process.argv[3]?.toLowerCase();

    console.log("======================================================================");
    console.log(`ROSETTA DETAILED REPORT v${VERSION}`);
    console.log("======================================================================");
    console.log();
    console.log(`Source: ${store.sourceFile} (${store.sourceEntries.size} keys, ${store.gate.activeKeyCount} active)\n`);
    printGateSummary(store.gate, store.sourceEntries.size);

    const langsToReport = targetLang
        ? store.enabledLangs.filter(l => l.code === targetLang)
        : store.enabledLangs;

    if (targetLang && langsToReport.length === 0) {
        console.error(`ERROR: Language '${targetLang}' not found. Available: ${store.enabledLangs.map(l => l.code).join(', ')}`);
        process.exit(1);
    }

    for (const { code: langCode, name: langName } of langsToReport) {
        const langFile = getLangFilePath(store.filePrefix, langCode);

        if (!fs.existsSync(langFile)) {
            console.log(`${langName} (${langCode.toUpperCase()}): FILE NOT FOUND\n`);
            continue;
        }

        const { entries: langEntries, orderedKeys: langKeys, duplicates: langDuplicates } = parseTranslationFile(langFile, store.format);
        const cls = classifyEntries(store.sourceEntries, store.sourceHashes, langEntries, langKeys, store.format, langCode);
        const duplicates = langDuplicates || [];

        console.log(`======================================================================`);
        console.log(`${langName} (${langCode.toUpperCase()})`);
        console.log(`======================================================================`);
        console.log(`  Translated:    ${cls.translated.length}`);
        console.log(`  Missing:       ${cls.missing.length}`);
        console.log(`  Stale:         ${cls.stale.length}`);
        console.log(`  Untranslated:  ${cls.untranslated.length}`);
        console.log(`  Duplicates:    ${duplicates.length}`);
        console.log(`  Orphaned:      ${cls.orphaned.length}`);

        if (cls.formatErrors.length > 0) console.log(`  Format Errors: ${cls.formatErrors.length} (CRITICAL)`);
        if (cls.suspectTranslations.length > 0) console.log(`  Suspect:       ${cls.suspectTranslations.length} (partially translated)`);
        if (cls.formatOrderWarnings.length > 0) console.log(`  Order Warns:   ${cls.formatOrderWarnings.length} (specifier order differs)`);
        if (cls.doubleEncodedEntities.length > 0) console.log(`  Dbl-Encoded:   ${cls.doubleEncodedEntities.length} (corrupted XML entities)`);
        if (cls.scriptIssues.length > 0) console.log(`  Script Issues: ${cls.scriptIssues.length} (garbling, spacing, zero-width chars)`);
        if (cls.cjkIssues.length > 0) console.log(`  CJK Issues:    ${cls.cjkIssues.length} (low CJK character ratio)`);
        if (cls.englishFunctionWordIssues.length > 0) console.log(`  Eng. Fn Words: ${cls.englishFunctionWordIssues.length} (untranslated English)`);
        if (cls.characterIssues.length > 0) console.log(`  Char Issues:   ${cls.characterIssues.length} (decimal sep, doubled accents, umlaut)`);
        if (cls.diacriticIssues.length > 0) console.log(`  Diacritics:    ${cls.diacriticIssues.length} (missing expected accents)`);
        if (cls.morphologyIssues.length > 0) console.log(`  Morphology:    ${cls.morphologyIssues.length} (English suffixes on foreign roots)`);
        if (cls.truncationIssues.length > 0) console.log(`  Truncated:     ${cls.truncationIssues.length} (information loss — translation too short)`);
        if (cls.inlineSuffixIssues.length > 0) console.log(`  Inline Suffix: ${cls.inlineSuffixIssues.length} (missing space/parens format)`);
        if (cls.colonMismatches.length > 0) console.log(`  Colon Mismatch: ${cls.colonMismatches.length} (source ends with : but translation does not)`);

        const showList = (items, label, fmt, limit = 10) => {
            if (items.length === 0) return;
            console.log(`\n  -- ${label}${items.length > limit ? ` (first ${limit})` : ''} --`);
            for (const item of items.slice(0, limit)) console.log(`    ${fmt(item)}`);
            if (items.length > limit) console.log(`    ... and ${items.length - limit} more`);
        };

        showList(cls.missing, 'MISSING', m => `- ${m.key}`);
        showList(cls.stale, 'STALE', s => `~ ${s.key}  (${s.oldHash} -> ${s.newHash})`);
        showList(cls.untranslated, 'UNTRANSLATED', u => `? ${u.key}  (${u.reason})`);
        showList(duplicates, 'DUPLICATES', d => `!! ${d}`);
        showList(cls.orphaned, 'ORPHANED', o => `x ${o}`);
        showList(cls.formatErrors, 'FORMAT ERRORS (will crash!)', e => `! ${e.key}: ${e.message}`);
        showList(cls.suspectTranslations, 'SUSPECT TRANSLATIONS (partial/gibberish)', s => `? ${s.key}: ${s.reason}`);
        showList(cls.formatOrderWarnings, 'FORMAT ORDER WARNINGS (positional mismatch)', w => `~ ${w.key}: ${w.message}`);
        showList(cls.doubleEncodedEntities, 'DOUBLE-ENCODED ENTITIES (display corruption)', e => `!! ${e.key}: ${e.matches.join(', ')}`);
        showList(cls.scriptIssues, 'SCRIPT ISSUES (garbling, spacing, zero-width)', e => `!! ${e.key}: ${e.issues.map(i => i.detail).join('; ')}`);
        showList(cls.cjkIssues, 'CJK QUALITY ISSUES (low CJK ratio)', e => `!! ${e.key}: ratio ${(e.ratio * 100).toFixed(0)}%`);
        showList(cls.englishFunctionWordIssues, 'ENGLISH FUNCTION WORDS (untranslated)', e => `!! ${e.key}: [${e.words.join(', ')}]`);
        showList(cls.characterIssues, 'CHARACTER ISSUES (decimal, doubled accents, umlaut)', e => `!! ${e.key}: ${e.issues.map(i => `${i.type}: ${i.detail}`).join('; ')}`);
        showList(cls.diacriticIssues, 'DIACRITIC ISSUES (missing accents)', e => `!! ${e.key}${e.words ? ': [' + e.words.join(', ') + ']' : ''}`);
        showList(cls.truncationIssues, 'TRUNCATED TRANSLATIONS (information loss)', e => `!! ${e.key}: ${e.pct}% of source (${e.targetLen}/${e.sourceLen} chars)`);
        showList(cls.morphologyIssues, 'ENGLISH MORPHOLOGY (foreign+English suffixes)', e => `!! ${e.key}: [${e.words.join(', ')}]`);
        showList(cls.inlineSuffixIssues, 'INLINE SUFFIX ISSUES (format preservation)', e => `!! ${e.key}: "${e.source}" -> "${e.value}"`);
        showList(cls.colonMismatches, 'COLON MISMATCHES (missing trailing colon)', e => `!! ${e.key}: "${e.value}"`);

        console.log();
    }

    if (store.gate.unusedKeys.length > 0) {
        console.log(`======================================================================`);
        console.log(`UNUSED KEYS (${store.gate.unusedKeys.length} keys not referenced in codebase)`);
        console.log(`======================================================================`);
        for (const key of store.gate.unusedKeys.slice(0, 20)) console.log(`    - ${key}`);
        if (store.gate.unusedKeys.length > 20) console.log(`    ... and ${store.gate.unusedKeys.length - 20} more (run 'unused' command for full list)`);
        console.log();
    }
}

function cmdCheck() {
    const store = initStore();

    console.log("======================================================================");
    console.log(`ROSETTA CHECK v${VERSION}`);
    console.log("======================================================================");
    console.log();
    console.log(`Source: ${store.sourceFile} (${store.sourceEntries.size} keys, ${store.gate.activeKeyCount} active)\n`);
    printGateSummary(store.gate, store.sourceEntries.size);

    let hasProblems = false;
    const summary = [];

    for (const { code: langCode, name: langName } of store.enabledLangs) {
        const langFile = getLangFilePath(store.filePrefix, langCode);

        if (!fs.existsSync(langFile)) {
            console.log(`  ${padRight(langName, 18)}: FILE NOT FOUND`);
            hasProblems = true;
            summary.push({ name: langName, total: 0, missing: -1, stale: 0, untranslated: 0, duplicates: 0, orphaned: 0 });
            continue;
        }

        const { entries: langEntries, orderedKeys: langKeys, duplicates: langDuplicates } = parseTranslationFile(langFile, store.format);
        const cls = classifyEntries(store.sourceEntries, store.sourceHashes, langEntries, langKeys, store.format, langCode);
        const duplicates = langDuplicates ? langDuplicates.length : 0;

        const issues = [];
        if (cls.missing.length > 0) issues.push(`${cls.missing.length} MISSING`);
        if (cls.stale.length > 0) issues.push(`${cls.stale.length} stale`);
        if (cls.untranslated.length > 0) issues.push(`${cls.untranslated.length} untranslated`);
        if (duplicates > 0) issues.push(`${duplicates} duplicates`);
        if (cls.orphaned.length > 0) issues.push(`${cls.orphaned.length} orphaned`);

        if (issues.length === 0) {
            console.log(`  ${padRight(langName, 18)}: OK (${langEntries.size} keys)`);
        } else {
            if (cls.missing.length > 0 || duplicates > 0 || cls.orphaned.length > 0) hasProblems = true;
            console.log(`  ${padRight(langName, 18)}: ${issues.join(', ')}`);
        }

        summary.push({
            name: langName, total: langEntries.size, missing: cls.missing.length,
            stale: cls.stale.length, untranslated: cls.untranslated.length, duplicates, orphaned: cls.orphaned.length
        });
    }

    console.log();
    printCheckSummaryTable(summary);

    if (hasProblems) {
        const totalMissing = summary.reduce((sum, s) => sum + (s.missing > 0 ? s.missing : 0), 0);
        const totalDuplicates = summary.reduce((sum, s) => sum + (s.duplicates || 0), 0);
        const totalOrphaned = summary.reduce((sum, s) => sum + (s.orphaned || 0), 0);
        if (totalMissing > 0) console.log("CRITICAL: Run 'rosetta.js sync' to fix missing keys.");
        if (totalDuplicates > 0) console.log(`CRITICAL: ${totalDuplicates} duplicate keys found!`);
        if (totalOrphaned > 0) console.log(`WARNING: ${totalOrphaned} orphaned keys.`);
        process.exit(1);
    } else {
        const totalStale = summary.reduce((sum, s) => sum + s.stale, 0);
        const totalUntranslated = summary.reduce((sum, s) => sum + s.untranslated, 0);
        if (totalStale > 0) console.log(`Note: ${totalStale} stale entries.`);
        if (totalUntranslated > 0) console.log(`Note: ${totalUntranslated} untranslated entries.`);
        if (totalStale === 0 && totalUntranslated === 0) console.log("All translations complete and up to date!");
        process.exit(0);
    }
}

function cmdValidate() {
    const store = initStore();

    let hasProblems = false;
    let formatErrorCount = 0;
    let doubleEncodedCount = 0;

    for (const { code: langCode } of store.enabledLangs) {
        const langFile = getLangFilePath(store.filePrefix, langCode);
        if (!fs.existsSync(langFile)) { hasProblems = true; break; }

        const { entries: langEntries, orderedKeys: langKeys } = parseTranslationFile(langFile, store.format);

        for (const [key] of store.sourceEntries) {
            if (!langEntries.has(key)) { hasProblems = true; break; }
        }

        const cls = classifyEntries(store.sourceEntries, store.sourceHashes, langEntries, langKeys, store.format, langCode);
        formatErrorCount += cls.formatErrors.length;
        const langName = LANGUAGE_NAMES[langCode] || langCode.toUpperCase();
        if (cls.suspectTranslations.length > 0) console.log(`  WARNING: ${langName} has ${cls.suspectTranslations.length} suspect (partially translated) entries`);
        if (cls.formatOrderWarnings.length > 0) console.log(`  WARNING: ${langName} has ${cls.formatOrderWarnings.length} format specifier order mismatch(es)`);
        if (cls.doubleEncodedEntities.length > 0) {
            console.log(`  ERROR: ${langName} has ${cls.doubleEncodedEntities.length} double-encoded XML entities`);
            doubleEncodedCount += cls.doubleEncodedEntities.length;
        }
        if (cls.cjkIssues.length > 0) console.log(`  WARNING: ${langName} has ${cls.cjkIssues.length} low CJK ratio entries`);
        if (cls.englishFunctionWordIssues.length > 0) console.log(`  WARNING: ${langName} has ${cls.englishFunctionWordIssues.length} entries with English function words`);
        if (cls.truncationIssues.length > 0) console.log(`  WARNING: ${langName} has ${cls.truncationIssues.length} truncated translations (information loss)`);

        if (hasProblems) break;
    }

    // Check for phantom keys (referenced in code but not in any translation file)
    const { missing: phantomKeys } = findMissingKeys(store.sourceEntries);

    if (formatErrorCount > 0) { console.log(`FAIL: ${formatErrorCount} format specifier error(s) detected`); process.exit(1); }
    else if (doubleEncodedCount > 0) { console.log(`FAIL: ${doubleEncodedCount} double-encoded XML entity(ies) detected`); process.exit(1); }
    else if (hasProblems) { console.log("FAIL: Translation files out of sync"); process.exit(1); }
    else if (phantomKeys.length > 0) {
        console.log(`WARN: ${phantomKeys.length} phantom key(s) — referenced in code but missing from translations`);
        for (const key of phantomKeys) console.log(`  - ${key}`);
        console.log("Run 'missing --deposit' to auto-add keys with fallback text");
        process.exit(0);
    }
    else { console.log("OK: All translation files have required keys"); process.exit(0); }
}

function cmdUnused() {
    const store = initStore();

    console.log("======================================================================");
    console.log(`ROSETTA UNUSED KEYS v${VERSION}`);
    console.log("======================================================================");
    console.log();
    printGateSummary(store.gate, store.sourceEntries.size);

    if (store.gate.unusedKeys.length === 0) { console.log("All keys are referenced in the codebase. Nothing to clean up!"); return; }

    const groups = new Map();
    for (const key of store.gate.unusedKeys) {
        const parts = key.split('_');
        const prefix = parts.length >= 2 ? parts.slice(0, 2).join('_') + '_' : key;
        if (!groups.has(prefix)) groups.set(prefix, []);
        groups.get(prefix).push(key);
    }

    const sortedGroups = [...groups.entries()].sort((a, b) => b[1].length - a[1].length);
    console.log(`${store.gate.unusedKeys.length} unused keys grouped by prefix:\n`);
    for (const [prefix, keys] of sortedGroups) {
        console.log(`  ${prefix}* (${keys.length} keys):`);
        for (const key of keys) console.log(`    - ${key}`);
        console.log();
    }

    console.log("======================================================================");
    console.log("To remove these keys, run:");
    console.log("  node rosetta.js remove --all-unused");
    console.log("======================================================================");
}

function cmdMissing() {
    const doDeposit = process.argv.includes('--deposit');
    const doExport = process.argv.includes('--export');
    const dryRun = process.argv.includes('--dry-run');
    const store = initStore();

    console.log("======================================================================");
    console.log(`ROSETTA MISSING KEYS v${VERSION}${doDeposit ? (dryRun ? ' (DEPOSIT DRY RUN)' : ' (DEPOSIT)') : doExport ? ' (EXPORT)' : ''}`);
    console.log("======================================================================");
    console.log();
    console.log("Scanning codebase for getText() and $l10n_ references...");

    const { allCodeKeys, missing, missingWithFallbacks, missingWithoutFallbacks, fallbackMap } = findMissingKeysWithFallbacks(store.sourceEntries);

    console.log(`Found ${allCodeKeys.length} unique usedplus_/usedPlus_ key references in source code.`);
    console.log(`English source has ${store.sourceEntries.size} keys.`);
    console.log();

    if (missing.length === 0) {
        console.log("All referenced keys exist in translation files. Nothing missing!");
        return;
    }

    console.log(`MISSING: ${missing.length} key(s) referenced in code but NOT in translation files`);
    console.log(`  With fallback text:    ${missingWithFallbacks.length} (auto-depositable)`);
    console.log(`  Without fallback text: ${missingWithoutFallbacks.length} (need manual English text)`);
    console.log();

    // --export mode: write JSON file compatible with `deposit --file`
    if (doExport) {
        const exportData = missingWithFallbacks.map(key => ({ key, value: fallbackMap.get(key) }));
        const outputFile = '_missing_deposit.json';
        fs.writeFileSync(outputFile, JSON.stringify(exportData, null, 2), 'utf8');
        console.log(`Exported ${exportData.length} key(s) with fallback text to ${outputFile}`);
        console.log(`Import: node rosetta.js deposit --file ${outputFile}`);

        if (missingWithoutFallbacks.length > 0) {
            console.log(`\n${missingWithoutFallbacks.length} key(s) without fallback text (add manually):`);
            for (const key of missingWithoutFallbacks) console.log(`  ${key}`);
        }
        console.log("======================================================================");
        return;
    }

    // --deposit mode: deposit all missing keys with fallback text in one pass
    if (doDeposit) {
        if (missingWithFallbacks.length === 0) {
            console.log("No missing keys have fallback text. Add English text manually:");
            console.log(`  node rosetta.js deposit KEY "English text"`);
            return;
        }

        const keysToDeposit = missingWithFallbacks.map(key => ({ key, value: fallbackMap.get(key) }));
        console.log(`Depositing ${keysToDeposit.length} key(s) across ${store.enabledLangs.length + 1} files...\n`);

        const deposited = depositKeysToFiles(store, keysToDeposit, dryRun);

        console.log();
        if (missingWithoutFallbacks.length > 0) {
            console.log(`${missingWithoutFallbacks.length} key(s) without fallback text (add manually):`);
            for (const key of missingWithoutFallbacks) console.log(`  ${key}`);
            console.log();
        }
        console.log("======================================================================");
        console.log(`DEPOSIT COMPLETE: ${deposited} key(s) added across ${store.enabledLangs.length + 1} files${dryRun ? ' (DRY RUN)' : ''}`);
        console.log("======================================================================");
        return;
    }

    // Default mode: list missing keys with file references and fallback hints
    const modDir = getModDir();
    const srcDir = path.join(modDir, 'src');
    const guiDir = path.join(modDir, 'gui');
    const vehiclesDir = path.join(modDir, 'vehicles');

    for (const key of missing) {
        const refs = [];
        for (const dir of [srcDir, guiDir, vehiclesDir]) {
            const files = getFilesRecursive(dir, ['.lua', '.xml']);
            for (const f of files) {
                const content = fs.readFileSync(f, 'utf8');
                if (content.includes(key)) {
                    refs.push(path.relative(modDir, f));
                }
            }
        }
        const fallback = fallbackMap.get(key);
        console.log(`  ${key}${fallback ? `  ← fallback: "${fallback}"` : ''}`);
        for (const ref of refs) console.log(`    → ${ref}`);
    }

    console.log();
    console.log("======================================================================");
    console.log("To deposit all keys with fallback text in one pass:");
    console.log("  node rosetta.js missing --deposit [--dry-run]");
    console.log("To export as JSON for review first:");
    console.log("  node rosetta.js missing --export");
    console.log("To add individual keys:");
    console.log(`  node rosetta.js deposit KEY "English text"`);
    console.log("======================================================================");
}

function cmdAudit() {
    const store = initStore();
    const targetLang = process.argv[3]?.toLowerCase();

    console.log("======================================================================");
    console.log(`ROSETTA AUDIT v${VERSION} — Translation Quality Intelligence`);
    console.log("======================================================================\n");

    const langsToAudit = targetLang
        ? store.enabledLangs.filter(l => l.code === targetLang)
        : store.enabledLangs;

    if (targetLang && langsToAudit.length === 0) {
        console.error(`ERROR: Language '${targetLang}' not found. Available: ${store.enabledLangs.map(l => l.code).join(', ')}`);
        process.exit(1);
    }

    const gradeThresholds = { A: 0.02, B: 0.05, C: 0.10, D: 0.20 };

    function getGrade(issueCount, totalEntries) {
        const ratio = totalEntries > 0 ? issueCount / totalEntries : 0;
        if (ratio <= gradeThresholds.A) return { grade: 'A', ratio };
        if (ratio <= gradeThresholds.B) return { grade: 'B', ratio };
        if (ratio <= gradeThresholds.C) return { grade: 'C', ratio };
        if (ratio <= gradeThresholds.D) return { grade: 'D', ratio };
        return { grade: 'F', ratio };
    }

    const auditCache = new Map(); // Cache results to avoid double-parsing in summary

    for (const { code: langCode, name: langName } of langsToAudit) {
        const langFile = getLangFilePath(store.filePrefix, langCode);
        if (!fs.existsSync(langFile)) { console.log(`${langName} (${langCode.toUpperCase()}): FILE NOT FOUND\n`); continue; }

        const { entries: langEntries, orderedKeys: langKeys } = parseTranslationFile(langFile, store.format);
        const cls = classifyEntries(store.sourceEntries, store.sourceHashes, langEntries, langKeys, store.format, langCode);

        const issueCount = cls.doubleEncodedEntities.length + cls.scriptIssues.length +
            cls.englishFunctionWordIssues.length + cls.characterIssues.length +
            cls.morphologyIssues.length + cls.suspectTranslations.length +
            cls.truncationIssues.length + cls.inlineSuffixIssues.length;
        const { grade: qualGrade, ratio } = getGrade(issueCount, langEntries.size);

        // Coverage grade: what percentage is actually translated (not untranslated/missing)
        const covRatio = langEntries.size > 0 ? (langEntries.size - cls.untranslated.length - cls.missing.length) / langEntries.size : 0;
        const covGrade = covRatio >= 0.98 ? 'A' : covRatio >= 0.95 ? 'B' : covRatio >= 0.90 ? 'C' : covRatio >= 0.80 ? 'D' : 'F';

        // Variant divergence (fc/ea/br only)
        let variantDiv = [];
        if (VARIANT_PAIRS[langCode]) {
            const pairFile = getLangFilePath(store.filePrefix, VARIANT_PAIRS[langCode]);
            if (fs.existsSync(pairFile)) {
                const { entries: pairEntries } = parseTranslationFile(pairFile, store.format);
                variantDiv = detectVariantDivergence(langCode, langEntries, pairEntries, store.sourceEntries);
            }
        }

        auditCache.set(langCode, { cls, entryCount: langEntries.size, issueCount, qualGrade, covGrade, variantCount: variantDiv.length });

        console.log(`======================================================================`);
        console.log(`${langName} (${langCode.toUpperCase()}) — Quality: ${qualGrade} | Coverage: ${covGrade} (${issueCount} issues / ${langEntries.size} entries = ${(ratio * 100).toFixed(1)}%)`);
        console.log(`======================================================================`);
        console.log(`  Translated:         ${cls.translated.length}`);
        console.log(`  Untranslated:       ${cls.untranslated.length}`);
        console.log(`  Format Errors:      ${cls.formatErrors.length}${cls.formatErrors.length > 0 ? ' (CRITICAL)' : ''}`);
        console.log(`  Double-Encoded:     ${cls.doubleEncodedEntities.length}${cls.doubleEncodedEntities.length > 0 ? ' (auto-fixable: rosetta.js fix --entities)' : ''}`);
        console.log(`  Script Issues:      ${cls.scriptIssues.length}${CJK_LANGS.includes(langCode) ? '' : cls.scriptIssues.length === 0 ? ' (n/a)' : ''}`);
        console.log(`  CJK Ratio Issues:   ${cls.cjkIssues.length}${CJK_LANGS.includes(langCode) ? '' : ' (n/a)'}`);
        console.log(`  English Fn Words:   ${cls.englishFunctionWordIssues.length}`);
        console.log(`  Character Issues:   ${cls.characterIssues.length}`);
        console.log(`  Diacritic Issues:   ${cls.diacriticIssues.length}${DIACRITIC_LANGS[langCode] ? '' : ' (n/a)'}`);
        console.log(`  Morphology Issues:  ${cls.morphologyIssues.length}`);
        console.log(`  Truncated:          ${cls.truncationIssues.length}${cls.truncationIssues.length > 0 ? ' (information loss)' : ''}`);
        console.log(`  Suspect (partial):  ${cls.suspectTranslations.length}`);
        console.log(`  Inline Suffix:      ${cls.inlineSuffixIssues.length}`);
        if (cls.colonMismatches.length > 0) console.log(`  Colon Mismatches:   ${cls.colonMismatches.length}`);
        if (variantDiv.length > 0) {
            console.log(`  Variant Divergence: ${variantDiv.length} (identical to EN but ${VARIANT_PAIRS[langCode].toUpperCase()} has translation)`);
        }

        const showSample = (items, label, fmt, limit = 5) => {
            if (items.length === 0) return;
            console.log(`\n  ${label} (${items.length} total, showing ${Math.min(items.length, limit)}):`);
            for (const item of items.slice(0, limit)) console.log(`    ${fmt(item)}`);
            if (items.length > limit) console.log(`    ... and ${items.length - limit} more`);
        };

        showSample(cls.doubleEncodedEntities, 'DOUBLE-ENCODED ENTITIES', e => `${e.key}: ${e.matches.join(', ')}`);
        showSample(cls.scriptIssues, 'SCRIPT ISSUES', e => `${e.key}: ${e.issues.map(i => i.detail).join('; ')}`);
        showSample(cls.cjkIssues, 'CJK RATIO FAILURES', e => `${e.key}: ${(e.ratio * 100).toFixed(0)}% CJK chars`);
        showSample(cls.englishFunctionWordIssues, 'ENGLISH FUNCTION WORDS', e => `${e.key}: [${e.words.join(', ')}] (${e.count} words)`);
        showSample(cls.characterIssues, 'CHARACTER ISSUES', e => `${e.key}: ${e.issues.map(i => `${i.type}: ${i.detail}`).join('; ')}`);
        showSample(cls.diacriticIssues, 'MISSING DIACRITICS', e => `${e.key}${e.words ? ': [' + e.words.join(', ') + ']' : ''}`);
        showSample(cls.morphologyIssues, 'ENGLISH MORPHOLOGY', e => `${e.key}: [${e.words.join(', ')}]`);
        showSample(cls.truncationIssues, 'TRUNCATED TRANSLATIONS', e => `${e.key}: ${e.pct}% of source (${e.targetLen}/${e.sourceLen} chars)`);
        showSample(cls.suspectTranslations, 'SUSPECT TRANSLATIONS', e => `${e.key}: ${e.reason}`);
        showSample(cls.colonMismatches, 'COLON MISMATCHES', e => `${e.key}: "${e.value}"`);
        showSample(cls.inlineSuffixIssues, 'INLINE SUFFIX ISSUES', e => `${e.key}: "${e.source}" -> "${e.value}"`);
        if (variantDiv.length > 0) {
            showSample(variantDiv, `VARIANT DIVERGENCE (vs ${VARIANT_PAIRS[langCode].toUpperCase()})`, e => `${e.key}: EN="${e.value.substring(0, 40)}..." ${VARIANT_PAIRS[langCode].toUpperCase()}="${e.pairValue.substring(0, 40)}..."`);
        }
        console.log();
    }

    if (!targetLang) {
        console.log("======================================================================");
        console.log("AUDIT SUMMARY");
        console.log("======================================================================");
        console.log(`${'Language'.padEnd(22)} | Qual | Cov | DblEnc | Script | EngFW | Chars | Morph | Trunc | Suspct | Total`);
        console.log("------------------------------------------------------------------------------------------------------------");

        for (const { code: langCode, name: langName } of langsToAudit) {
            const cached = auditCache.get(langCode);
            if (!cached) continue;

            const { cls, qualGrade, covGrade } = cached;
            const counts = {
                de: cls.doubleEncodedEntities.length, scr: cls.scriptIssues.length,
                efw: cls.englishFunctionWordIssues.length, chr: cls.characterIssues.length,
                mor: cls.morphologyIssues.length, tru: cls.truncationIssues.length,
                sus: cls.suspectTranslations.length,
            };
            const total = counts.de + counts.scr + counts.efw + counts.chr + counts.mor + counts.tru + counts.sus;

            console.log(`${padRight(langName, 22)} |  ${qualGrade}   |  ${covGrade}  | ${padLeft(counts.de, 6)} | ${padLeft(counts.scr, 6)} | ${padLeft(counts.efw, 5)} | ${padLeft(counts.chr, 5)} | ${padLeft(counts.mor, 5)} | ${padLeft(counts.tru, 5)} | ${padLeft(counts.sus, 6)} | ${padLeft(total, 5)}`);
        }
        console.log("------------------------------------------------------------------------------------------------------------");
        console.log("Qual = quality grade (issues/entries): A (<=2%) B (<=5%) C (<=10%) D (<=20%) F (>20%)");
        console.log("Cov  = coverage grade (translated/total): A (>=98%) B (>=95%) C (>=90%) D (>=80%) F (<80%)");
    }
}

// --- MUTATING COMMANDS: sync, deposit, amend, rename, remove, translate, import, fix-stale, fix, doctor, format

function cmdSync() {
    const dryRun = process.argv.includes('--dry-run');

    console.log("======================================================================");
    console.log(`ROSETTA SYNC v${VERSION}${dryRun ? ' (DRY RUN)' : ''}`);
    console.log("======================================================================\n");

    const filePrefix = autoDetectFilePrefix();
    if (!filePrefix) { console.error("ERROR: Could not find source translation file."); process.exit(1); }

    const sourceFile = getSourceFilePath(filePrefix);
    if (!fs.existsSync(sourceFile)) { console.error(`ERROR: Source file not found: ${sourceFile}`); process.exit(1); }

    const sourceContent = fs.readFileSync(sourceFile, 'utf8');
    const format = autoDetectXmlFormat(sourceContent);
    if (!format) { console.error("ERROR: Could not detect XML format."); process.exit(1); }

    console.log(`[1/4] Updating hashes in source file...`);
    if (format === 'elements' && !dryRun) {
        const hashesUpdated = updateSourceHashes(sourceFile, format);
        console.log(hashesUpdated > 0 ? `      Updated ${hashesUpdated} hash(es) in ${sourceFile}` : `      All hashes current in ${sourceFile}`);
    } else if (format === 'elements') {
        const { entries } = parseTranslationFile(sourceFile, format);
        let wouldUpdate = 0;
        for (const [, data] of entries) { if (data.hash !== getHash(data.value)) wouldUpdate++; }
        console.log(`      Would update ${wouldUpdate} hash(es) in ${sourceFile}`);
    } else {
        console.log(`      Skipped (hash embedding only for 'elements' format)`);
    }

    const { entries: sourceEntries, orderedKeys: sourceOrderedKeys } = parseTranslationFile(sourceFile, format);
    const sourceHashes = new Map();
    for (const [key, data] of sourceEntries) sourceHashes.set(key, getHash(data.value));

    const gate = gateCodebaseValidation(sourceEntries);

    console.log();
    console.log(`[2/4] Source: ${sourceFile} (${sourceEntries.size} keys)`);
    console.log(`      Format: ${format}`);
    console.log();
    console.log(`[3/4] Codebase validation...`);
    printGateSummary(gate, sourceEntries.size);
    console.log(`[4/4] Syncing to target languages (${gate.activeKeyCount} active keys)...\n`);

    const enabledLangs = getEnabledLanguages();

    for (const { code: langCode, name: langName } of enabledLangs) {
        const langFile = getLangFilePath(filePrefix, langCode);
        if (!fs.existsSync(langFile)) { console.log(`  ${padRight(langName, 18)}: FILE NOT FOUND - skipping`); continue; }

        let { entries: langEntries, orderedKeys: langKeys, duplicates: langDuplicates, rawContent: content } = parseTranslationFile(langFile, format);
        const langKeySet = new Set(langKeys);
        const cls = classifyEntries(sourceEntries, sourceHashes, langEntries, langKeys, format, langCode);

        let added = 0;
        for (const { key, enValue } of cls.missing) {
            const sourceHash = sourceHashes.get(key);
            content = addEntryToContent(content, key, CONFIG.untranslatedPrefix + enValue, sourceHash, format, sourceOrderedKeys, langKeySet);
            langKeySet.add(key);
            added++;
        }

        if (format === 'elements') {
            const missingKeySet = new Set(cls.missing.map(m => m.key));
            const staleKeySet = new Set(cls.stale.map(s => s.key));

            for (const [key] of sourceEntries) {
                if (!langEntries.has(key) || missingKeySet.has(key)) continue;
                const sourceHash = sourceHashes.get(key);
                const langData = langEntries.get(key);
                const isUntranslated = langData.value.startsWith(CONFIG.untranslatedPrefix);

                if (isUntranslated && staleKeySet.has(key)) {
                    const sourceData = sourceEntries.get(key);
                    content = updateEntryInContent(content, key, CONFIG.untranslatedPrefix + sourceData.value, sourceHash, format);
                    continue;
                }

                const shouldAddHash = !staleKeySet.has(key) || (!langData.hash && !isUntranslated);
                if (shouldAddHash) content = updateEntryInContent(content, key, null, sourceHash, format);
            }
        }

        if (!dryRun) atomicWrite(langFile, content);

        const parts = [];
        if (added > 0) parts.push(`+${added} added`);
        if (cls.stale.length > 0) parts.push(`${cls.stale.length} stale`);
        if (langDuplicates && langDuplicates.length > 0) parts.push(`${langDuplicates.length} duplicates`);
        if (cls.orphaned.length > 0) parts.push(`${cls.orphaned.length} orphaned`);
        if (cls.formatErrors.length > 0) parts.push(`${cls.formatErrors.length} FORMAT ERRORS`);
        if (cls.emptyValues.length > 0) parts.push(`${cls.emptyValues.length} empty`);
        if (cls.whitespaceIssues.length > 0) parts.push(`${cls.whitespaceIssues.length} whitespace`);

        console.log(`  ${padRight(langName, 18)}: ${parts.length === 0 ? 'OK' : parts.join(', ')}`);
    }

    console.log();
    console.log("======================================================================");
    console.log(`SYNC COMPLETE${dryRun ? ' (DRY RUN - no files modified)' : ''}`);
    console.log(`New entries have "${CONFIG.untranslatedPrefix}" prefix. Stale = hash mismatch.`);
    console.log("======================================================================");
}

/**
 * Shared helper: deposit an array of {key, value} pairs across all translation files.
 * Builds an enKeyIndex Map for O(1) insert-position lookups.
 * Returns count of keys actually deposited.
 */
function depositKeysToFiles(store, keysToDeposit, dryRun) {
    // Build O(1) key index from source ordered keys
    const enKeyIndex = new Map();
    for (let i = 0; i < store.sourceOrderedKeys.length; i++) {
        enKeyIndex.set(store.sourceOrderedKeys[i], i);
    }

    // Deposit to English source
    let sourceContent = fs.readFileSync(store.sourceFile, 'utf8');
    const sourceKeySet = new Set(store.sourceOrderedKeys);

    for (const { key, value } of keysToDeposit) {
        const hash = getHash(value);
        sourceContent = addEntryToContent(sourceContent, key, value, hash, store.format, store.sourceOrderedKeys, sourceKeySet, undefined, enKeyIndex);
        sourceKeySet.add(key);
        enKeyIndex.set(key, store.sourceOrderedKeys.length);
        store.sourceOrderedKeys.push(key);
    }

    if (!dryRun) atomicWrite(store.sourceFile, sourceContent);
    console.log(`  ${padRight(path.basename(store.sourceFile), 25)}: +${keysToDeposit.length} (English values)`);

    // Deposit to all target language files
    for (const { code: langCode, name: langName } of store.enabledLangs) {
        const langFile = getLangFilePath(store.filePrefix, langCode);
        if (!fs.existsSync(langFile)) continue;

        let content = fs.readFileSync(langFile, 'utf8');
        const { orderedKeys: langKeys } = parseTranslationFile(langFile, store.format);
        const langKeySet = new Set(langKeys);

        for (const { key, value } of keysToDeposit) {
            const hash = getHash(value);
            content = addEntryToContent(content, key, CONFIG.untranslatedPrefix + value, hash, store.format, store.sourceOrderedKeys, langKeySet, undefined, enKeyIndex);
            langKeySet.add(key);
        }

        if (!dryRun) atomicWrite(langFile, content);
        console.log(`  ${padRight(path.basename(langFile), 25)}: +${keysToDeposit.length} ([EN] placeholders)`);
    }

    return keysToDeposit.length;
}

function cmdDeposit() {
    const dryRun = process.argv.includes('--dry-run');
    const args = process.argv.slice(3).filter(a => !a.startsWith('--'));
    const fileFlag = process.argv.indexOf('--file');

    let keysToDeposit = [];

    if (fileFlag !== -1 && process.argv[fileFlag + 1]) {
        const jsonPath = process.argv[fileFlag + 1];
        if (!fs.existsSync(jsonPath)) { console.error(`ERROR: File not found: ${jsonPath}`); process.exit(1); }
        try {
            const data = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
            keysToDeposit = Array.isArray(data) ? data.map(item => ({ key: item.key, value: item.value })) : Object.entries(data).map(([key, value]) => ({ key, value }));
        } catch (err) { console.error(`ERROR: Failed to parse JSON file: ${err.message}`); process.exit(1); }
    } else if (args.length >= 2) {
        keysToDeposit = [{ key: args[0], value: args.slice(1).join(' ') }];
    } else {
        console.error("Usage: rosetta.js deposit KEY VALUE  OR  rosetta.js deposit --file keys.json"); process.exit(1);
    }

    const store = initStore();

    console.log("======================================================================");
    console.log(`ROSETTA DEPOSIT v${VERSION}${dryRun ? ' (DRY RUN)' : ''}`);
    console.log("======================================================================\n");

    const valid = [], skipped = [];
    for (const { key, value } of keysToDeposit) {
        if (!key || !value) { skipped.push({ key: key || '(empty)', reason: 'missing key or value' }); continue; }
        if (store.sourceEntries.has(key)) { skipped.push({ key, reason: 'already exists in English source' }); continue; }
        valid.push({ key, value });
    }

    if (skipped.length > 0) {
        console.log(`Skipped ${skipped.length} key(s):`);
        for (const { key, reason } of skipped) console.log(`  ? ${key}: ${reason}`);
        console.log();
    }
    if (valid.length === 0) { console.log("No new keys to deposit."); return; }

    console.log(`Depositing ${valid.length} key(s) across ${store.enabledLangs.length + 1} files...\n`);

    const deposited = depositKeysToFiles(store, valid, dryRun);

    console.log();
    console.log("======================================================================");
    console.log(`DEPOSIT COMPLETE: ${deposited} key(s) added across ${store.enabledLangs.length + 1} files`);
    console.log("======================================================================");
}

function cmdAmend() {
    const dryRun = process.argv.includes('--dry-run');
    const args = process.argv.slice(3).filter(a => !a.startsWith('--'));
    if (args.length < 2) { console.error("Usage: node rosetta.js amend KEY NEW_VALUE"); process.exit(1); }

    const key = args[0], newValue = args.slice(1).join(' ');
    const store = initStore();

    if (!store.sourceEntries.has(key)) { console.error(`ERROR: Key '${key}' not found in English source.`); process.exit(1); }

    const oldValue = store.sourceEntries.get(key).value;
    const newHash = getHash(newValue);

    console.log("======================================================================");
    console.log(`ROSETTA AMEND v${VERSION}${dryRun ? ' (DRY RUN)' : ''}`);
    console.log("======================================================================\n");
    console.log(`  Key:       ${key}`);
    console.log(`  Old value: ${oldValue}`);
    console.log(`  New value: ${newValue}`);
    console.log(`  New hash:  ${newHash}\n`);

    let sourceContent = fs.readFileSync(store.sourceFile, 'utf8');
    sourceContent = updateEntryInContent(sourceContent, key, newValue, newHash, store.format);
    if (!dryRun) atomicWrite(store.sourceFile, sourceContent);
    console.log(`  ${padRight(path.basename(store.sourceFile), 25)}: value + hash updated`);
    console.log(`  All ${store.enabledLangs.length} language files: hash mismatch will mark as stale\n`);
    console.log("======================================================================");
    console.log("AMEND COMPLETE");
    console.log("  Run 'rosetta.js status' to see stale entries.");
    console.log("  Run 'rosetta.js translate LANG --stale' to export for re-translation.");
    console.log("======================================================================");
}

function cmdRename() {
    const dryRun = process.argv.includes('--dry-run');
    const args = process.argv.slice(3).filter(a => !a.startsWith('--'));
    if (args.length !== 2) { console.error("Usage: node rosetta.js rename OLD_KEY NEW_KEY"); process.exit(1); }

    const [oldKey, newKey] = args;
    const store = initStore();

    if (!store.sourceEntries.has(oldKey)) { console.error(`ERROR: Key '${oldKey}' not found.`); process.exit(1); }
    if (store.sourceEntries.has(newKey)) { console.error(`ERROR: Key '${newKey}' already exists.`); process.exit(1); }

    console.log("======================================================================");
    console.log(`ROSETTA RENAME v${VERSION}${dryRun ? ' (DRY RUN)' : ''}`);
    console.log("======================================================================\n");
    console.log(`  Renaming: ${oldKey} -> ${newKey}\n`);

    const allFiles = getAllFilePaths(store.filePrefix, store.enabledLangs);
    let filesModified = 0;

    for (const filePath of allFiles) {
        let content = fs.readFileSync(filePath, 'utf8');
        const newContent = renameKeyInContent(content, oldKey, newKey, store.format);
        if (newContent !== content) {
            if (!dryRun) atomicWrite(filePath, newContent);
            filesModified++;
            console.log(`  ${padRight(path.basename(filePath), 25)}: renamed`);
        } else {
            console.log(`  ${padRight(path.basename(filePath), 25)}: key not found`);
        }
    }

    console.log();
    console.log("======================================================================");
    console.log(`RENAME COMPLETE: ${filesModified} file(s) updated`);
    console.log("======================================================================");
}

function cmdRemove() {
    const dryRun = process.argv.includes('--dry-run');
    const store = initStore();

    console.log("======================================================================");
    console.log(`ROSETTA REMOVE v${VERSION}${dryRun ? ' (DRY RUN)' : ''}`);
    console.log("======================================================================\n");

    const args = process.argv.slice(3).filter(a => !a.startsWith('--'));
    let keysToRemove = [];

    if (process.argv.includes('--all-unused')) {
        printGateSummary(store.gate, store.sourceEntries.size);
        keysToRemove = store.gate.unusedKeys;
    } else if (args.length > 0) {
        keysToRemove = args;
    } else {
        console.error("Usage:\n  node rosetta.js remove KEY1 KEY2 KEY3\n  node rosetta.js remove --all-unused"); process.exit(1);
    }

    if (keysToRemove.length === 0) { console.log("No keys to remove."); return; }

    const validKeys = [], invalidKeys = [];
    for (const key of keysToRemove) {
        if (store.sourceEntries.has(key)) validKeys.push(key); else invalidKeys.push(key);
    }

    if (invalidKeys.length > 0) {
        console.log(`WARNING: ${invalidKeys.length} key(s) not found (skipping):`);
        for (const key of invalidKeys.slice(0, 10)) console.log(`  ? ${key}`);
        if (invalidKeys.length > 10) console.log(`  ... and ${invalidKeys.length - 10} more`);
        console.log();
    }
    if (validKeys.length === 0) { console.log("No valid keys to remove."); return; }

    console.log(`Removing ${validKeys.length} key(s) from all translation files...\n`);

    const allFiles = getAllFilePaths(store.filePrefix, store.enabledLangs);
    let totalRemoved = 0;

    for (const filePath of allFiles) {
        let content = fs.readFileSync(filePath, 'utf8');
        let removedFromFile = 0;
        for (const key of validKeys) {
            const before = content;
            content = removeEntryFromContent(content, key, store.format);
            if (content !== before) removedFromFile++;
        }
        if (removedFromFile > 0) {
            content = content.replace(/\n{3,}/g, '\n\n');
            if (!dryRun) atomicWrite(filePath, content);
        }
        console.log(`  ${padRight(path.basename(filePath), 25)}: ${removedFromFile > 0 ? `removed ${removedFromFile} key(s)` : 'no matches'}`);
        totalRemoved += removedFromFile;
    }

    console.log();
    console.log("======================================================================");
    console.log(`REMOVE COMPLETE: ${totalRemoved} entries across ${allFiles.length} files`);
    console.log("======================================================================");
}

function exportQualityEntries(langCode, langMatch, store, langEntries, langKeys, filterType) {
    const BATCH_SIZE = 300;
    const cls = classifyEntries(store.sourceEntries, store.sourceHashes, langEntries, langKeys, store.format, langCode);
    const flaggedKeys = new Set();

    // Count entries identical to English (classified as translated but not actually)
    const identicalEntries = cls.translated.filter(e => {
        const src = store.sourceEntries.get(e.key);
        return src && e.value === src.value && !isFormatOnlyString(src.value);
    });

    // Map filter types to issue arrays
    const issueMap = {
        entities: cls.doubleEncodedEntities,
        script: cls.scriptIssues,
        cjk: cls.cjkIssues, // backward compat alias
        engfw: cls.englishFunctionWordIssues,
        chars: cls.characterIssues,
        diacritics: cls.diacriticIssues,
        morphology: cls.morphologyIssues,
        suspect: cls.suspectTranslations,
        reorder: cls.formatOrderWarnings,
        truncated: cls.truncationIssues,
        suffix: cls.inlineSuffixIssues,
        colons: cls.colonMismatches,
        identical: identicalEntries,
        untranslated: cls.untranslated,
        missing: cls.missing,
    };

    // Variant divergence requires loading the pair language file
    if (filterType === 'variant') {
        if (!VARIANT_PAIRS[langCode]) {
            console.error(`Variant filter only applies to: ${Object.keys(VARIANT_PAIRS).join(', ')}`);
            process.exit(1);
        }
        const pairFile = getLangFilePath(store.filePrefix, VARIANT_PAIRS[langCode]);
        if (fs.existsSync(pairFile)) {
            const { entries: pairEntries } = parseTranslationFile(pairFile, store.format);
            const variantDiv = detectVariantDivergence(langCode, langEntries, pairEntries, store.sourceEntries);
            for (const e of variantDiv) flaggedKeys.add(e.key);
        }
        if (flaggedKeys.size === 0) return [];
    } else if (filterType && !issueMap[filterType]) {
        console.error(`Unknown filter type '${filterType}'. Available: ${Object.keys(issueMap).join(', ')}, variant`);
        process.exit(1);
    }

    if (filterType && filterType !== 'variant') {
        for (const e of issueMap[filterType]) flaggedKeys.add(e.key);
    } else if (!filterType) {
        for (const arr of Object.values(issueMap)) {
            for (const e of arr) flaggedKeys.add(e.key);
        }
    }

    if (flaggedKeys.size === 0) return [];

    const allEntries = [...flaggedKeys].map(key => ({
        key, source: store.sourceEntries.get(key).value, sourceHash: store.sourceHashes.get(key),
    }));

    const meta = { sourceLanguage: CONFIG.sourceLanguage, targetLanguage: langCode, targetName: langMatch.name, exportedAt: new Date().toISOString() };
    const instructions = {
        formatSpecifiers: "Preserve format specifiers EXACTLY: %s, %d, %.1f, %.2f, etc. Count, type, and order must match. Lua is positional.",
        tone: "Farming simulation context. Natural, professional game UI language. Concise.",
        xmlEntities: "Preserve &#10; as &#10;. Do NOT convert to \\n.",
        quality: "These entries were flagged for quality issues. Provide HIGH QUALITY translations with proper diacritics/characters.",
    };

    // Split into batches if > BATCH_SIZE
    const files = [];
    if (allEntries.length <= BATCH_SIZE) {
        const outputFile = `${langCode}_quality_translate.json`;
        const exportData = { $schema: 'rosetta-translate-v1', meta: { ...meta, entryCount: allEntries.length }, instructions, entries: allEntries };
        fs.writeFileSync(outputFile, JSON.stringify(exportData, null, 2), 'utf8');
        files.push({ file: outputFile, count: allEntries.length });
    } else {
        const numBatches = Math.ceil(allEntries.length / BATCH_SIZE);
        for (let i = 0; i < numBatches; i++) {
            const batch = allEntries.slice(i * BATCH_SIZE, (i + 1) * BATCH_SIZE);
            const outputFile = `${langCode}_quality_translate_${i + 1}.json`;
            const exportData = { $schema: 'rosetta-translate-v1', meta: { ...meta, entryCount: batch.length, batch: i + 1, totalBatches: numBatches }, instructions, entries: batch };
            fs.writeFileSync(outputFile, JSON.stringify(exportData, null, 2), 'utf8');
            files.push({ file: outputFile, count: batch.length });
        }
    }
    return files;
}

function cmdTranslate() {
    const args = process.argv.slice(3).filter(a => !a.startsWith('--'));
    const includeStale = process.argv.includes('--stale');
    const includeQuality = process.argv.includes('--quality');
    const compact = process.argv.includes('--compact');
    const filterArg = process.argv.find(a => a.startsWith('--filter='));
    const filterType = filterArg ? filterArg.split('=')[1] : null;
    const translateAll = args[0]?.toLowerCase() === 'all';

    if (args.length === 0) { console.error("Usage: rosetta.js translate LANG|all [--stale] [--quality] [--compact] [--filter=TYPE]"); process.exit(1); }
    if (filterType && !includeQuality) { console.error("--filter requires --quality flag."); process.exit(1); }

    const store = initStore();

    // Handle --quality --all: export quality-flagged entries for all languages
    if (includeQuality && translateAll) {
        console.log("======================================================================");
        console.log(`ROSETTA QUALITY EXPORT v${VERSION} — All Languages`);
        console.log("======================================================================\n");
        let totalFiles = 0, totalEntries = 0;
        for (const lang of store.enabledLangs) {
            const langFile = getLangFilePath(store.filePrefix, lang.code);
            if (!fs.existsSync(langFile)) continue;
            const { entries: langEntries, orderedKeys: langKeys } = parseTranslationFile(langFile, store.format);
            const files = exportQualityEntries(lang.code, lang, store, langEntries, langKeys, filterType);
            if (files.length === 0) {
                console.log(`  ${padRight(lang.name, 22)}: Grade A — no issues`);
            } else {
                const count = files.reduce((s, f) => s + f.count, 0);
                const fileList = files.map(f => f.file).join(', ');
                console.log(`  ${padRight(lang.name, 22)}: ${count} entries -> ${fileList}`);
                totalFiles += files.length;
                totalEntries += count;
            }
        }
        console.log(`\nExported ${totalEntries} entries across ${totalFiles} file(s)`);
        console.log("======================================================================");
        return;
    }

    if (translateAll) { console.error("Usage: 'translate all' requires --quality flag. For a single language: rosetta.js translate LANG"); process.exit(1); }

    const langCode = args[0].toLowerCase();
    const langMatch = store.enabledLangs.find(l => l.code === langCode);
    if (!langMatch) { console.error(`Language '${langCode}' not found.`); process.exit(1); }

    const langFile = getLangFilePath(store.filePrefix, langCode);
    if (!fs.existsSync(langFile)) { console.error(`File not found: ${langFile}`); process.exit(1); }

    const { entries: langEntries, orderedKeys: langKeys } = parseTranslationFile(langFile, store.format);

    if (includeQuality) {
        const files = exportQualityEntries(langCode, langMatch, store, langEntries, langKeys, filterType);
        if (files.length === 0) { console.log(`No quality issues found for ${langMatch.name}${filterType ? ` (filter: ${filterType})` : ''}. Grade: A`); return; }
        const count = files.reduce((s, f) => s + f.count, 0);
        for (const f of files) console.log(`Exported ${f.count} quality-flagged entries to ${f.file} (${langMatch.name})`);
        if (files.length > 1) console.log(`Total: ${count} entries across ${files.length} batches (max 300 per batch for AI agent reliability)`);
        console.log(`Import after translation: rosetta.js import ${langCode}_translated.json --cleanup`);
        return;
    }

    const exportData = exportForTranslation(langCode, store.sourceEntries, store.sourceHashes, langEntries, langKeys, store.format, includeStale, compact);
    if (!exportData) { console.log(`Nothing to translate for ${langMatch.name}.`); return; }

    const outputFile = `${langCode}_translate.json`;
    fs.writeFileSync(outputFile, JSON.stringify(exportData, null, 2), 'utf8');
    console.log(`Exported ${exportData.entries.length} entries to ${outputFile} (${langMatch.name})`);
    console.log(`Import after translation: rosetta.js import ${langCode}_translated.json --cleanup`);
}

function importSingleFile(jsonPath, store, dryRun, doCleanup) {
    if (!fs.existsSync(jsonPath)) { console.error(`  File not found: ${jsonPath}`); return { applied: 0, rejected: 0 }; }

    let importData;
    try { importData = JSON.parse(fs.readFileSync(jsonPath, 'utf8')); }
    catch (err) { console.error(`  Invalid JSON in ${jsonPath}: ${err.message}`); return { applied: 0, rejected: 0 }; }

    const v = validateAndImport(importData, store.sourceEntries, store.sourceHashes);

    if (v.rejected.length > 0 && v.accepted.length === 0) {
        console.log(`  ${jsonPath}: ALL REJECTED (${v.rejected.length})`);
        for (const { key, reason } of v.rejected.slice(0, 5)) console.log(`    X ${key}: ${reason}`);
        return { applied: 0, rejected: v.rejected.length };
    }

    const langCode = importData.meta.targetLanguage;
    const langFile = getLangFilePath(store.filePrefix, langCode);
    if (!fs.existsSync(langFile)) { console.error(`  Target file not found: ${langFile}`); return { applied: 0, rejected: 0 }; }

    const langName = LANGUAGE_NAMES[langCode] || langCode.toUpperCase();

    if (v.rejected.length > 0) {
        for (const { key, reason } of v.rejected.slice(0, 5)) console.log(`    X ${key}: ${reason}`);
    }

    let content = fs.readFileSync(langFile, 'utf8');
    for (const { key, translation, sourceHash } of v.accepted) {
        content = updateEntryInContent(content, key, translation, sourceHash, store.format);
    }
    if (!dryRun && v.accepted.length > 0) atomicWrite(langFile, content);

    // Post-import audit
    let gradeStr = '';
    if (!dryRun && v.accepted.length > 0) {
        const { entries: newLangEntries, orderedKeys: newLangKeys } = parseTranslationFile(langFile, store.format);
        const cls = classifyEntries(store.sourceEntries, store.sourceHashes, newLangEntries, newLangKeys, store.format, langCode);
        const issues = cls.doubleEncodedEntities.length + cls.scriptIssues.length + cls.englishFunctionWordIssues.length +
            cls.characterIssues.length + cls.morphologyIssues.length + cls.truncationIssues.length + cls.suspectTranslations.length +
            cls.inlineSuffixIssues.length;
        const pct = (issues / store.sourceEntries.size) * 100;
        const grade = pct <= 2 ? 'A' : pct <= 5 ? 'B' : pct <= 10 ? 'C' : pct <= 20 ? 'D' : 'F';
        gradeStr = ` -> Grade ${grade} (${pct.toFixed(1)}%)`;
    }

    console.log(`  ${jsonPath}: ${langName} — Applied: ${v.accepted.length} | Rejected: ${v.rejected.length}${gradeStr}`);

    if (doCleanup && !dryRun && v.accepted.length > 0) {
        try { fs.unlinkSync(jsonPath); } catch (_e) { /* ignore */ }
    }

    return { applied: v.accepted.length, rejected: v.rejected.length };
}

function cmdImport() {
    const dryRun = process.argv.includes('--dry-run');
    const doCleanup = process.argv.includes('--cleanup');
    const args = process.argv.slice(3).filter(a => !a.startsWith('--'));
    if (args.length === 0) { console.error("Usage: rosetta.js import FILE.json [FILE2.json...] [--dry-run] [--cleanup]"); process.exit(1); }

    // Expand glob patterns (e.g., *_fix.json)
    const resolvedFiles = [];
    for (const arg of args) {
        if (arg.includes('*') || arg.includes('?')) {
            const escaped = arg.replace(/[.+^${}()|[\]\\]/g, '\\$&');
            const pattern = new RegExp('^' + escaped.replace(/\*/g, '.*').replace(/\?/g, '.') + '$');
            const matches = fs.readdirSync('.').filter(f => pattern.test(f) && f.endsWith('.json')).sort();
            if (matches.length === 0) { console.error(`No files matching: ${arg}`); process.exit(1); }
            resolvedFiles.push(...matches);
        } else {
            resolvedFiles.push(arg);
        }
    }

    const store = initStore();

    console.log("======================================================================");
    console.log(`ROSETTA IMPORT v${VERSION}${dryRun ? ' (DRY RUN)' : ''} — ${resolvedFiles.length} file(s)`);
    console.log("======================================================================\n");

    let totalApplied = 0, totalRejected = 0;
    for (const jsonPath of resolvedFiles) {
        const result = importSingleFile(jsonPath, store, dryRun, doCleanup);
        totalApplied += result.applied;
        totalRejected += result.rejected;
    }

    if (resolvedFiles.length > 1) {
        console.log(`\nTotal: Applied ${totalApplied} | Rejected ${totalRejected} across ${resolvedFiles.length} files`);
    }
    console.log("======================================================================");
}

function cmdFixStale() {
    const args = process.argv.slice(3).filter(a => !a.startsWith('--'));
    const dryRun = process.argv.includes('--dry-run');
    const store = initStore();

    const langsToFix = args.length > 0
        ? store.enabledLangs.filter(l => args.map(a => a.toLowerCase()).includes(l.code))
        : store.enabledLangs;

    if (langsToFix.length === 0) { console.error("No matching languages found."); process.exit(1); }

    console.log("======================================================================");
    console.log(`ROSETTA FIX-STALE v${VERSION}${dryRun ? ' (DRY RUN)' : ''}`);
    console.log("======================================================================\n");

    let totalFixed = 0;
    for (const { code: langCode, name: langName } of langsToFix) {
        const langFile = getLangFilePath(store.filePrefix, langCode);
        if (!fs.existsSync(langFile)) continue;

        const { entries: langEntries, orderedKeys: langKeys } = parseTranslationFile(langFile, store.format);
        const cls = classifyEntries(store.sourceEntries, store.sourceHashes, langEntries, langKeys, store.format, langCode);

        if (cls.stale.length === 0) continue;

        console.log(`${langName} (${langCode}): ${cls.stale.length} stale → accepting current translations`);
        if (!dryRun) {
            let content = fs.readFileSync(langFile, 'utf8');
            for (const entry of cls.stale) {
                content = updateEntryInContent(content, entry.key, entry.value, store.sourceHashes.get(entry.key), store.format);
            }
            atomicWrite(langFile, content);
        }
        totalFixed += cls.stale.length;
        for (const entry of cls.stale) console.log(`  ✓ ${entry.key}`);
    }

    console.log(`\nFixed: ${totalFixed} stale entries${dryRun ? ' (dry run)' : ''}`);
    console.log("======================================================================");
}

function cmdFix() {
    const dryRun = process.argv.includes('--dry-run');
    const fixEntities = process.argv.includes('--entities');
    const args = process.argv.slice(3).filter(a => !a.startsWith('--'));
    const targetLang = args[0]?.toLowerCase();

    if (!fixEntities) {
        console.error("Usage: node rosetta.js fix [LANG] --entities [--dry-run]");
        console.error("\nAvailable fixes:");
        console.error("  --entities    Fix double-encoded XML entities (&amp;# -> &#, etc.)");
        process.exit(1);
    }

    const store = initStore();

    console.log("======================================================================");
    console.log(`ROSETTA FIX v${VERSION}${dryRun ? ' (DRY RUN)' : ''}`);
    console.log("======================================================================\n");

    const langsToFix = targetLang ? store.enabledLangs.filter(l => l.code === targetLang) : store.enabledLangs;
    if (targetLang && langsToFix.length === 0) { console.error(`ERROR: Language '${targetLang}' not found.`); process.exit(1); }

    let totalFixed = 0;

    for (const { code: langCode, name: langName } of langsToFix) {
        const langFile = getLangFilePath(store.filePrefix, langCode);
        if (!fs.existsSync(langFile)) continue;

        let content = fs.readFileSync(langFile, 'utf8');
        let fixCount = 0;

        const replacements = [
            [/&amp;(#\d+;)/g, '&$1'], [/&amp;(#x[0-9a-fA-F]+;)/g, '&$1'],
            [/&amp;amp;/g, '&amp;'], [/&amp;lt;/g, '&lt;'], [/&amp;gt;/g, '&gt;'], [/&amp;quot;/g, '&quot;'],
        ];
        // Loop until convergence — multi-layer encoding needs multiple passes
        let changed = true;
        while (changed) {
            changed = false;
            for (const [pattern, replacement] of replacements) {
                const before = content;
                content = content.replace(pattern, replacement);
                if (content !== before) {
                    const matches = before.match(pattern);
                    fixCount += matches ? matches.length : 0;
                    changed = true;
                }
            }
        }

        if (fixCount > 0) {
            if (!dryRun) atomicWrite(langFile, content);
            console.log(`  ${padRight(langName, 22)}: fixed ${fixCount} double-encoded entities`);
            totalFixed += fixCount;
        } else {
            console.log(`  ${padRight(langName, 22)}: clean`);
        }
    }

    console.log(`\nFIX COMPLETE: ${totalFixed} entities fixed across ${langsToFix.length} files${dryRun ? ' (DRY RUN)' : ''}`);
    console.log("======================================================================");
}

function cmdDoctor() {
    const doFix = process.argv.includes('--fix');
    const store = initStore();

    console.log("======================================================================");
    console.log(`ROSETTA DOCTOR v${VERSION}${doFix ? ' (AUTO-FIX MODE)' : ''}`);
    console.log("======================================================================\n");

    const issues = [];
    let totalFormatErrors = 0, totalEmpty = 0, totalOrphaned = 0, totalDuplicates = 0;

    console.log("Scanning all language files...");
    for (const { code: langCode } of store.enabledLangs) {
        const langFile = getLangFilePath(store.filePrefix, langCode);
        if (!fs.existsSync(langFile)) continue;

        const { entries: langEntries, orderedKeys: langKeys, duplicates } = parseTranslationFile(langFile, store.format);
        const cls = classifyEntries(store.sourceEntries, store.sourceHashes, langEntries, langKeys, store.format, langCode);

        for (const err of cls.formatErrors) issues.push({ severity: 'CRITICAL', category: 'format', lang: langCode, key: err.key, message: err.message });
        totalFormatErrors += cls.formatErrors.length;
        for (const { key } of cls.emptyValues) issues.push({ severity: 'WARNING', category: 'empty', lang: langCode, key, message: 'Empty translation value' });
        totalEmpty += cls.emptyValues.length;
        for (const key of cls.orphaned) issues.push({ severity: 'WARNING', category: 'orphan', lang: langCode, key, message: 'Key not in English source', fixable: true });
        totalOrphaned += cls.orphaned.length;
        for (const key of duplicates) issues.push({ severity: 'HIGH', category: 'duplicate', lang: langCode, key, message: 'Key appears multiple times' });
        totalDuplicates += duplicates.length;
    }

    const { duplicates: enDupes } = parseTranslationFile(store.sourceFile, store.format);
    for (const key of enDupes) { issues.push({ severity: 'CRITICAL', category: 'duplicate', lang: 'en', key, message: 'Duplicate in English source' }); totalDuplicates++; }

    console.log(`  Format specifiers: ${totalFormatErrors === 0 ? 'OK' : `${totalFormatErrors} errors`}`);
    console.log(`  Empty values: ${totalEmpty === 0 ? 'OK' : `${totalEmpty} found`}`);
    console.log(`  Orphaned keys: ${totalOrphaned === 0 ? 'OK' : `${totalOrphaned} found`}`);
    console.log(`  Duplicate keys: ${totalDuplicates === 0 ? 'OK' : `${totalDuplicates} found`}`);

    console.log("Checking reverse orphans (code refs missing from English)...");
    const reverseOrphans = findReverseOrphans(getModDir(), store.sourceEntries);
    for (const { key, file } of reverseOrphans) issues.push({ severity: 'HIGH', category: 'reverse-orphan', lang: '-', key, message: `Referenced in ${file} but missing from English` });
    console.log(`  Reverse orphans: ${reverseOrphans.length === 0 ? 'OK' : `${reverseOrphans.length} found`}`);

    const mixedPrefix = [...store.sourceEntries.keys()].filter(k => k.startsWith('usedPlus_'));
    for (const key of mixedPrefix) issues.push({ severity: 'LOW', category: 'convention', lang: 'en', key, message: 'Uses usedPlus_ instead of usedplus_' });
    console.log(`  Naming convention: ${mixedPrefix.length === 0 ? 'OK' : `${mixedPrefix.length} mixed-case keys`}`);

    let structureIssues = 0;
    const allFiles = getAllFilePaths(store.filePrefix, store.enabledLangs);
    for (const filePath of allFiles) {
        const content = fs.readFileSync(filePath, 'utf8');
        if (!content.includes('<l10n>') || !content.includes('</l10n>')) { structureIssues++; issues.push({ severity: 'CRITICAL', category: 'structure', lang: path.basename(filePath), key: '-', message: 'Missing <l10n> root element' }); }
        if (!content.includes('<elements>') || !content.includes('</elements>')) { structureIssues++; issues.push({ severity: 'CRITICAL', category: 'structure', lang: path.basename(filePath), key: '-', message: 'Missing <elements> container' }); }
    }
    console.log(`  XML structure: ${structureIssues === 0 ? 'OK' : `${structureIssues} issues`}`);

    let staleHashes = 0;
    for (const [key, data] of store.sourceEntries) {
        if (data.hash && data.hash !== getHash(data.value)) {
            staleHashes++; issues.push({ severity: 'WARNING', category: 'hash', lang: 'en', key, message: 'Hash does not match value (run sync)', fixable: true });
        }
    }
    console.log(`  Hash consistency: ${staleHashes === 0 ? 'OK' : `${staleHashes} stale hashes`}`);

    if (doFix && issues.some(i => i.fixable)) {
        console.log("\nApplying auto-fixes...");
        let fixed = 0;
        if (staleHashes > 0) { const count = updateSourceHashes(store.sourceFile, store.format); console.log(`  Fixed ${count} stale English hashes`); fixed += count; }
        if (totalOrphaned > 0) {
            const orphansByFile = new Map();
            for (const issue of issues.filter(i => i.category === 'orphan')) {
                const langFile = getLangFilePath(store.filePrefix, issue.lang);
                if (!orphansByFile.has(langFile)) orphansByFile.set(langFile, []);
                orphansByFile.get(langFile).push(issue.key);
            }
            for (const [filePath, keys] of orphansByFile) {
                let content = fs.readFileSync(filePath, 'utf8');
                for (const key of keys) content = removeEntryFromContent(content, key, store.format);
                atomicWrite(filePath, content.replace(/\n{3,}/g, '\n\n'));
                console.log(`  Removed ${keys.length} orphaned key(s) from ${path.basename(filePath)}`);
                fixed += keys.length;
            }
        }
        console.log(`  Total fixes applied: ${fixed}`);
    }

    console.log();
    console.log("======================================================================");

    const critical = issues.filter(i => i.severity === 'CRITICAL');
    const high = issues.filter(i => i.severity === 'HIGH');
    const warning = issues.filter(i => i.severity === 'WARNING');
    const low = issues.filter(i => i.severity === 'LOW');

    if (issues.length === 0) {
        console.log("DIAGNOSIS: HEALTHY");
    } else {
        console.log(`DIAGNOSIS: ${critical.length > 0 ? 'CRITICAL' : high.length > 0 ? 'NEEDS ATTENTION' : 'MINOR ISSUES'}`);
        console.log(`  Critical: ${critical.length} | High: ${high.length} | Warning: ${warning.length} | Low: ${low.length}`);
        for (const [label, list] of [['CRITICAL', critical], ['HIGH', high]]) {
            if (list.length > 0) {
                console.log(`\n  ${label} issues:`);
                for (const i of list.slice(0, 10)) console.log(`    [${i.lang}] ${i.key}: ${i.message}`);
                if (list.length > 10) console.log(`    ... and ${list.length - 10} more`);
            }
        }
        if (!doFix && issues.some(i => i.fixable)) console.log("\n  Some issues are auto-fixable. Run: node rosetta.js doctor --fix");
    }
    console.log("======================================================================");

    if (critical.length > 0) process.exit(1);
}

function cmdFormat() {
    const dryRun = process.argv.includes('--dry-run');
    const store = initStore();

    console.log("======================================================================");
    console.log(`ROSETTA FORMAT v${VERSION}${dryRun ? ' (DRY RUN)' : ''}`);
    console.log("======================================================================\n");

    const allFiles = [store.sourceFile, ...store.enabledLangs.map(l => getLangFilePath(store.filePrefix, l.code)).filter(f => fs.existsSync(f))];
    let totalReformatted = 0;

    for (const filePath of allFiles) {
        const parsed = parseTranslationFile(filePath, store.format);
        const content = fs.readFileSync(filePath, 'utf8');

        const containerTag = store.format === 'elements' ? 'elements' : 'texts';
        const containerStart = content.indexOf(`<${containerTag}>`);
        const containerEnd = content.indexOf(`</${containerTag}>`);
        if (containerStart === -1 || containerEnd === -1) { console.log(`  ${padRight(path.basename(filePath), 25)}: SKIP (missing <${containerTag}>)`); continue; }

        const header = content.substring(0, containerStart + `<${containerTag}>`.length);
        const footer = content.substring(containerEnd);
        const referenceOrder = store.sourceOrderedKeys;
        const lines = [];

        const fmtRaw = (key, data) => {
            const hash = data.hash || getHash(data.value);
            const tagAttr = data.tag ? ` tag="${data.tag}"` : '';
            return store.format === 'elements'
                ? `        <e k="${key}" v="${data.value}" eh="${hash}"${tagAttr} />`
                : `        <text name="${key}" text="${data.value}"/>`;
        };

        const outputKeys = new Set();
        for (const key of referenceOrder) {
            if (parsed.entries.has(key)) { lines.push(fmtRaw(key, parsed.entries.get(key))); outputKeys.add(key); }
        }
        for (const key of parsed.orderedKeys) {
            if (!outputKeys.has(key)) lines.push(fmtRaw(key, parsed.entries.get(key)));
        }

        const newContent = header + '\n' + lines.join('\n') + '\n    ' + footer;
        const changed = newContent !== content;
        if (changed && !dryRun) atomicWrite(filePath, newContent);
        console.log(`  ${padRight(path.basename(filePath), 25)}: ${changed ? 'reformatted' : 'already clean'} (${parsed.entries.size} entries)`);
        if (changed) totalReformatted++;
    }

    console.log(`\nFORMAT COMPLETE: ${totalReformatted}/${allFiles.length} files ${dryRun ? 'would be ' : ''}reformatted`);
}

function cmdCleanup() {
    const dryRun = process.argv.includes('--dry-run');
    const force = process.argv.includes('--force');
    const STALE_MINUTES = 10;

    // Patterns for temp files that agents and rosetta workflows create
    const tempPatterns = [
        /^[a-z]{2}_translate\.json$/,
        /^[a-z]{2}_translated[_\w]*\.json$/,
        /^[a-z]{2}_quality_translate[_\w]*\.json$/,
        /^[a-z]{2}_retranslated[_\w]*\.json$/,
        /^[a-z]{2}_fix[_\w]*\.json$/,
        /^_missing_deposit\.json$/,
        /^(translate|retranslate|export|generate|ct_comprehensive)[_\w]*\.(js|py)$/,
        /^_extract_missing\.js$/,
        /^_batch_deposit\.sh$/,
        /^RETRANSLATION[_\w]*\.(md|txt)$/,
    ];

    const files = fs.readdirSync('.');
    const toDelete = files.filter(f => tempPatterns.some(p => p.test(f)));

    // Check for recently modified files — agents may still be running
    const now = Date.now();
    const recentFiles = toDelete.filter(f => {
        const mtime = fs.statSync(f).mtimeMs;
        return (now - mtime) < STALE_MINUTES * 60 * 1000;
    });

    console.log("======================================================================");
    console.log(`ROSETTA CLEANUP v${VERSION}${dryRun ? ' (DRY RUN)' : ''}`);
    console.log("======================================================================\n");

    if (toDelete.length === 0) {
        console.log("  No temporary files found. Directory is clean.");
    } else if (recentFiles.length > 0 && !force && !dryRun) {
        console.log(`  WARNING: ${recentFiles.length} file(s) modified in the last ${STALE_MINUTES} minutes.`);
        console.log("  Translator agents may still be running.\n");
        for (const f of recentFiles) {
            const age = Math.round((now - fs.statSync(f).mtimeMs) / 60000);
            console.log(`  ! ${f} (${age}m ago)`);
        }
        const staleFiles = toDelete.filter(f => !recentFiles.includes(f));
        if (staleFiles.length > 0) {
            console.log(`\n  ${staleFiles.length} older file(s) are safe to delete:`);
            for (const f of staleFiles) console.log(`    ${f}`);
        }
        console.log(`\n  To delete all: node rosetta.js cleanup --force`);
        console.log("  To preview:    node rosetta.js cleanup --dry-run");
    } else {
        for (const f of toDelete) {
            if (!dryRun) {
                try { fs.unlinkSync(f); } catch (e) { console.log(`  ERROR deleting ${f}: ${e.message}`); continue; }
            }
            console.log(`  ${dryRun ? 'Would delete' : 'Deleted'}: ${f}`);
        }
        console.log(`\n${dryRun ? 'Would delete' : 'Deleted'} ${toDelete.length} temporary file(s).`);
    }
    console.log("======================================================================");
}

// --- INSPECT COMMAND: View key(s) across all languages

function cmdInspect() {
    const args = process.argv.slice(3).filter(a => !a.startsWith('--'));
    if (args.length === 0) { console.error("Usage: rosetta.js inspect KEY [KEY...]"); process.exit(1); }

    const store = initStore();
    const allLangs = [{ code: 'en', name: 'English' }, ...store.enabledLangs];
    const langFiles = new Map();

    for (const { code } of allLangs) {
        const file = code === 'en' ? getSourceFilePath(store.filePrefix) : getLangFilePath(store.filePrefix, code);
        if (fs.existsSync(file)) {
            langFiles.set(code, parseTranslationFile(file, store.format).entries);
        }
    }

    for (const key of args) {
        console.log(`\n${'='.repeat(70)}`);
        console.log(`KEY: ${key}`);
        const srcEntry = store.sourceEntries.get(key);
        if (!srcEntry) { console.log(`  NOT FOUND in English source.`); continue; }
        const srcHash = store.sourceHashes.get(key);
        console.log(`  Source Hash: ${srcHash}`);
        console.log(`${'='.repeat(70)}`);

        const maxNameLen = Math.max(...allLangs.map(l => l.name.length));
        for (const { code, name } of allLangs) {
            const entries = langFiles.get(code);
            if (!entries) { console.log(`  ${padRight(name, maxNameLen)} [${code}]  -- FILE MISSING --`); continue; }
            const entry = entries.get(key);
            if (!entry) { console.log(`  ${padRight(name, maxNameLen)} [${code}]  -- KEY MISSING --`); continue; }
            const hashMatch = entry.hash === srcHash ? ' ' : '~';
            const val = entry.value.length > 100 ? entry.value.substring(0, 97) + '...' : entry.value;
            console.log(`  ${padRight(name, maxNameLen)} [${code}] ${hashMatch} ${val}`);
        }
    }
    console.log();
}

// --- CLI ROUTER, HELP, AND BACKWARD COMPATIBILITY

function showHelp() {
    console.log(`
ROSETTA.JS v${VERSION} — Translation Management Tool

COMMANDS:
  sync                    Sync all languages: add missing keys, update hashes
  status                  Quick overview table per language
  report [LANG]           Detailed breakdown with problem key lists
  check                   CI-friendly report with exit codes
  validate                Minimal CI output, exit codes only
  unused                  List dead keys not referenced in codebase
  missing                 Find keys referenced in code but not in translations
  missing --deposit       Deposit all missing keys with fallback text (one pass)
  missing --export        Export missing keys as JSON for review
  audit [LANG]            Deep translation quality audit with grades
  inspect KEY [KEY...]    View key value across all 26 languages
  deposit KEY VALUE       Add a key atomically across ALL files
  deposit --file F.json   Bulk add keys from JSON
  amend KEY NEW_VALUE     Change English text, mark translations stale
  rename OLD_KEY NEW_KEY  Rename across all files, preserve translations
  remove KEY [KEY...]     Delete key(s) from all files
  remove --all-unused     Delete all unused keys
  translate LANG [--stale] [--quality] [--filter=TYPE]  Export JSON for AI translation
  import FILE.json [...]  Import translated JSON (supports multiple files and globs)
  fix [LANG] --entities   Auto-fix double-encoded XML entities
  fix-stale [LANG]        Accept current translations, update hashes
  doctor [--fix]          Health check + auto-fix
  cleanup [--force]       Remove temporary translation files (JSON, scripts)
  format                  Standardize XML indentation and key order

FLAGS:  --dry-run  --help  --compact  --quality  --cleanup  --force  --filter=TYPE
FILTER TYPES: entities, script, cjk, engfw, chars, diacritics, morphology, suspect, reorder, truncated, suffix, identical, variant, untranslated, missing

QUALITY WORKFLOW:
  audit [LANG]                    Check translation quality grades (A-F)
  translate LANG --quality        Export quality-flagged entries (auto-batched at 300)
  translate all --quality         Export quality-flagged entries for ALL languages
  fix LANG --entities             Auto-fix double-encoded XML entities
  (dispatch translator agent)     Retranslate flagged entries
  import FILE.json --cleanup      Import translations + delete input file
  cleanup                         Remove all temp files from translations/

JSON PROTOCOL:
  Export: rosetta.js translate de  ->  Import: rosetta.js import de_translated.json --cleanup
  Format specifiers MUST match English (hard reject). Empty = rejected.
  Batches of 300 max for AI agent reliability.
`);
}

// --- Main CLI Router ---
const command = process.argv[2]?.toLowerCase();

// Change to script directory
process.chdir(__dirname);

// Ensure translator agent exists on first run
ensureTranslatorAgent();

const commands = {
    sync: cmdSync, status: cmdStatus, report: cmdReport, check: cmdCheck,
    validate: cmdValidate, unused: cmdUnused, missing: cmdMissing, audit: cmdAudit, inspect: cmdInspect, deposit: cmdDeposit, amend: cmdAmend,
    rename: cmdRename, remove: cmdRemove, translate: cmdTranslate, import: cmdImport,
    fix: cmdFix, 'fix-stale': cmdFixStale, doctor: cmdDoctor, cleanup: cmdCleanup, format: cmdFormat, help: showHelp, '--help': showHelp, '-h': showHelp,
};
if (command === 'prune') { console.log("NOTE: 'prune' is deprecated. Use 'remove' instead.\n"); cmdRemove(); }
else if (commands[command]) { commands[command](); }
else { showHelp(); }
