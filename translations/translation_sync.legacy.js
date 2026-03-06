#!/usr/bin/env node
/**
 * ══════════════════════════════════════════════════════════════════════════════
 * UNIVERSAL TRANSLATION SYNC TOOL v3.2.1
 * For Farming Simulator 25 Mods
 * ══════════════════════════════════════════════════════════════════════════════
 *
 * WHAT IS THIS?
 *   A portable tool that keeps your mod's translation files in sync.
 *   Drop this file into your translations folder and run it - that's it!
 *
 * THE PROBLEM IT SOLVES:
 *   When you add or CHANGE a text key in your English file, you need to know
 *   which translations need updating. This tool:
 *   - Adds missing keys to all language files automatically
 *   - Detects when English text changed but translation wasn't updated (STALE)
 *   - Uses embedded hashes for self-documenting XML files
 *   - Validates translations for data quality issues
 *
 * QUICK START:
 *   cd translations/
 *   node translation_sync.js sync      # Sync all languages
 *   node translation_sync.js status    # Quick overview
 *   node translation_sync.js report    # Detailed breakdown
 *   node translation_sync.js help      # Full documentation
 *
 * HOW HASH-BASED SYNC WORKS:
 *   Every entry has an embedded hash (eh) of its English source text:
 *
 *   English:  <e k="greeting" v="Hello World" eh="a1b2c3d4"/>
 *   German:   <e k="greeting" v="Hallo Welt" eh="a1b2c3d4"/>   <- Same hash = OK
 *   French:   <e k="greeting" v="Bonjour" eh="99999999"/>     <- Different = STALE!
 *
 *   When you change English text:
 *   1. Run sync - English hash auto-updates
 *   2. Target hashes stay the same (they reflect what was translated FROM)
 *   3. Hash mismatch = translation is STALE (needs re-translation)
 *
 * COMMANDS:
 *   sync           - Add missing keys, update hashes, show what changed
 *   status         - Quick table: translated/stale/missing per language
 *   report         - Detailed lists of problem keys by language
 *   check          - Report issues, exit code 1 if MISSING keys exist
 *   validate       - CI-friendly: minimal output, exit codes only
 *   help           - Show full help with all options
 *
 * CODEBASE VALIDATION (v4.0.0):
 *   All commands now gate on codebase usage first. English keys that aren't
 *   referenced in any Lua/XML file are flagged as UNUSED and excluded from
 *   translation counts. This prevents translating dead keys.
 *
 * WHAT IT DETECTS:
 *   ✓ Missing keys     - Key in English but not in target language
 *   ~ Stale entries    - Hash mismatch (English changed since translation)
 *   ? Untranslated     - Has "[EN] " prefix or exact match (excluding cognates)
 *   !! Duplicates      - Same key appears twice in file (data corruption!)
 *   x Orphaned         - Key in target but NOT in English (safe to delete)
 *   💥 Format errors   - Wrong format specifiers (%s, %d, %.1f) - WILL CRASH GAME!
 *   ⚠ Empty values    - Translation is empty string
 *   ⚠ Whitespace      - Leading/trailing spaces in translation
 *
 *   NOTE: Cognates and international terms (Type, Status, Generator, OK, etc.)
 *         are automatically recognized and NOT flagged as untranslated.
 *
 * SUPPORTED XML FORMATS (auto-detected):
 *   <e k="key" v="value" eh="hash"/>   (elements pattern - used by UsedPlus)
 *   <text name="key" text="value"/>     (texts pattern - no hash support)
 *
 * VERSION HISTORY:
 *   v4.0.0 - Codebase validation: scan src/gui/modDesc for actual key usage,
 *            'unused' command lists dead keys, 'prune' command removes keys from all files
 *   v3.2.2 - Added cognate detection (no false positives for international terms)
 *   v3.2.1 - Fixed format specifier regex (no false positives on "40% success")
 *   v3.2.0 - Added format specifier validation, empty/whitespace detection
 *   v3.1.0 - Added duplicate and orphan detection
 *   v3.0.0 - Hash-based sync system
 *
 * Author: FS25_UsedPlus Team
 * License: MIT - Free to use, modify, and distribute in any mod
 * ══════════════════════════════════════════════════════════════════════════════
 */

const VERSION = '4.0.0';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// ══════════════════════════════════════════════════════════════════════════════
// CONFIGURATION
// ══════════════════════════════════════════════════════════════════════════════

const CONFIG = {
    // Source language (the "master" file all others sync from)
    sourceLanguage: 'en',

    // Prefix added to untranslated entries (so translators know what needs work)
    untranslatedPrefix: '[EN] ',

    // File naming pattern: 'auto', 'translation', or 'l10n'
    filePrefix: 'auto',

    // XML format: 'auto', 'texts', or 'elements'
    xmlFormat: 'auto',
};

// ══════════════════════════════════════════════════════════════════════════════
// LANGUAGE NAME MAPPINGS
// ══════════════════════════════════════════════════════════════════════════════

const LANGUAGE_NAMES = {
    en: 'English',
    de: 'German',
    fr: 'French',
    es: 'Spanish',
    it: 'Italian',
    pl: 'Polish',
    ru: 'Russian',
    br: 'Portuguese (BR)',
    pt: 'Portuguese (PT)',
    cz: 'Czech',
    cs: 'Czech (deprecated)',
    uk: 'Ukrainian',
    nl: 'Dutch',
    da: 'Danish',
    sv: 'Swedish',
    no: 'Norwegian',
    fi: 'Finnish',
    hu: 'Hungarian',
    ro: 'Romanian',
    tr: 'Turkish',
    ja: 'Japanese',
    jp: 'Japanese',
    ko: 'Korean',
    kr: 'Korean',
    zh: 'Chinese (Simplified)',
    tw: 'Chinese (Traditional)',
    ct: 'Chinese (Traditional)',
    ea: 'Spanish (Latin America)',
    fc: 'French (Canadian)',
    id: 'Indonesian',
    vi: 'Vietnamese',
};

// ══════════════════════════════════════════════════════════════════════════════
// END OF CONFIGURATION
// ══════════════════════════════════════════════════════════════════════════════

// Change to script directory
process.chdir(__dirname);

// ──────────────────────────────────────────────────────────────────────────────
// Utility Functions
// ──────────────────────────────────────────────────────────────────────────────

function getHash(text) {
    // 8-character MD5 hash - short but sufficient for change detection
    return crypto.createHash('md5').update(text, 'utf8').digest('hex').substring(0, 8);
}

function escapeRegex(str) {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function escapeXml(str) {
    return str
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

// ──────────────────────────────────────────────────────────────────────────────
// Validation Functions (v3.2.0)
// ──────────────────────────────────────────────────────────────────────────────

/**
 * Extract format specifiers from a string
 * Matches: %s, %d, %i, %f, %.1f, %.2f, %ld, etc.
 * Returns sorted array for comparison
 *
 * NOTE: Excludes space flag to avoid false positives like "40% success"
 * where "% s" looks like a specifier but is just a percentage followed by text.
 * Real format specifiers don't have space between % and the type letter.
 */
function extractFormatSpecifiers(str) {
    // Pattern breakdown:
    // %         - literal percent sign
    // [-+0#]*   - optional flags (NO space - that causes false positives)
    // (\d+)?    - optional width
    // (\.\d+)?  - optional precision
    // (hh?|ll?|L|z|j|t)?  - optional length modifier
    // [diouxXeEfFgGaAcspn]  - type specifier (NOTE: excludes % - that's an escape, not a specifier)
    //
    // IMPORTANT: %% is an escape sequence that produces a literal %, NOT a format specifier.
    // We don't include % in the final character class because %% doesn't need to match
    // between source and target - both "50%" and "50%%" display the same thing.
    const pattern = /%[-+0#]*(\d+)?(\.\d+)?(hh?|ll?|L|z|j|t)?[diouxXeEfFgGaAcspn]/g;
    const matches = str.match(pattern) || [];
    return matches.sort();
}

/**
 * Compare format specifiers between source and target
 * Returns null if OK, or error object if mismatch
 */
function checkFormatSpecifiers(sourceValue, targetValue, key) {
    const sourceSpecs = extractFormatSpecifiers(sourceValue);
    const targetSpecs = extractFormatSpecifiers(targetValue);

    // Quick check: same count?
    if (sourceSpecs.length !== targetSpecs.length) {
        return {
            key,
            type: 'count',
            source: sourceSpecs,
            target: targetSpecs,
            message: `Expected ${sourceSpecs.length} format specifier(s), found ${targetSpecs.length}`
        };
    }

    // Detailed check: same specifiers?
    for (let i = 0; i < sourceSpecs.length; i++) {
        if (sourceSpecs[i] !== targetSpecs[i]) {
            return {
                key,
                type: 'mismatch',
                source: sourceSpecs,
                target: targetSpecs,
                message: `Format specifier mismatch: expected "${sourceSpecs[i]}", found "${targetSpecs[i]}"`
            };
        }
    }

    return null; // OK
}

/**
 * Check if a string is "format-only" (no translatable text content)
 * These are strings like "%s %%", "%d km", "%s:%s" that are identical in all languages
 */
function isFormatOnlyString(value) {
    if (!value) return false;
    // Remove all format specifiers: %s, %d, %02d, %.1f, %%, etc.
    // Remove common units that are international: km, m, %, etc.
    // Remove punctuation and whitespace
    const stripped = value
        .replace(/%[-+0-9]*\.?[0-9]*[sdfeEgGoxXuc%]/g, '') // format specifiers
        .replace(/\b(km|m|kg|l|h|s|ms|px|pcs)\b/gi, '')    // common units
        .replace(/[:\s.,\-\/()[\]{}]+/g, '');               // punctuation & whitespace

    // If nothing remains, it's format-only
    return stripped.length === 0;
}

/**
 * Check for empty value
 */
function isEmptyValue(value) {
    return value === '' || value === null || value === undefined;
}

/**
 * Check for whitespace issues (leading/trailing)
 */
function hasWhitespaceIssues(value) {
    if (!value) return false;
    return value !== value.trim();
}

/**
 * Check if a value is likely a cognate or international term
 * These are values that are legitimately the same in multiple languages:
 * - Proper names (Jim, Pete, Chuck, Joe)
 * - Technical terms (Generator, Starter, OBD, ECU, CAN)
 * - Common cognates (Type, Total, Status, Agent, Normal, OK)
 * - Universal symbols (#, $, @)
 * - Single-letter or very short terms
 * - Gaming terms (Hardcore, Mode, Info, Debug)
 */
function isCognateOrInternationalTerm(value) {
    // Empty strings are intentional placeholders, not untranslated
    if (value === '') return true;
    if (!value) return false;

    // If it's too long, it's probably not a cognate (arbitrary threshold: 50 chars)
    // Long identical sentences are suspicious
    if (value.length > 50) return false;

    // Check if value matches common patterns of cognates/international terms

    // 1. Very short (1-3 characters) - likely symbols or abbreviations
    if (value.length <= 3) return true;

    // 2. Contains only symbols, numbers, and punctuation
    if (/^[#$@%&*()[\]{}\-+:,.\/\d\s]+$/.test(value)) return true;

    // 3. Proper names (starts with "- " for mechanic names, or single capitalized word)
    if (/^-\s+[A-Z][a-z]+$/.test(value)) return true;  // "- Jim", "- Pete"

    // 4. Common single-word cognates and technical terms (case-insensitive)
    const commonCognates = [
        'type', 'total', 'status', 'agent', 'normal', 'ok', 'info', 'mode',
        'generator', 'starter', 'min', 'max', 'per', 'vs', 'hardcore',
        'obd', 'ecu', 'can', 'dtc', 'debug', 'regional', 'national',
        'original', 'score', 'principal', 'ha', 'pcs', 'elite', 'premium',
        'standard', 'budget', 'basic', 'advanced', 'pro', 'master',
        'leasing', 'spawning', 'repo', 'state', 'misfire', 'overheat',
        'runaway', 'cutout', 'workhorse', 'integration', 'vanilla',
        'item', 'land', 'thermostat',
        // French-English cognates (valid in both languages)
        'description', 'confirmation', 'actions', 'excellent', 'finance', 'finances',
        'acceptable', 'stable', 'ratio'
    ];
    const lowerValue = value.toLowerCase().trim();
    if (commonCognates.includes(lowerValue)) return true;

    // 5. Common multi-word international phrases and technical terms
    const commonPhrases = [
        'regional agent', 'national agent', 'local agent',
        'no', 'yes', 'si', 'ja',  // yes/no in various languages
        'obd scanner', 'service truck', 'spawn lemon', 'toggle debug',
        'reset cd'
    ];
    if (commonPhrases.includes(lowerValue)) return true;

    // 6. Phrases with "vs" (comparisons)
    if (/^vs\s+/i.test(value)) return true;

    // 7. All caps labels (STATUS, INFO, TOTAL, etc.)
    if (/^[A-Z\s:]+$/.test(value) && value.replace(/[:\s]/g, '').length >= 2) return true;

    // 8. Single word ending in colon (labels like "Status:", "Type:", "Agent:")
    if (/^[A-Za-z]+:\s*$/.test(value)) return true;

    // 9. Money symbols with amounts ($10,000, +$100,000, etc.) or admin labels with $
    if (/^[+\-]?\$[\d,]+$/.test(value) || /^Set \$\d+$/.test(value)) return true;

    // 10. Admin labels with percentages or abbreviations (Rel: 100%, Surge (L), etc.)
    if (/^(Rel|Surge|Flat):/i.test(value) || /\(L\)$|\(R\)$/.test(value)) return true;

    // 11. Mod integration names (RVB Integration, UYT Integration, etc.)
    if (/^[A-Z]{2,5}\s+Integration$/i.test(value)) return true;

    // 12. Vehicle model names with alphanumerics (GMC C7000, Ford F-150, etc.)
    if (/^[A-Z]+\s+[A-Z0-9\-]+/i.test(value) && value.split(' ').length <= 4) return true;

    return false;
}

// ──────────────────────────────────────────────────────────────────────────────
// Codebase Scanning (v4.0.0)
// ──────────────────────────────────────────────────────────────────────────────

/**
 * Recursively get all files matching extensions under a directory
 */
function getFilesRecursive(dir, extensions) {
    const results = [];
    if (!fs.existsSync(dir)) return results;

    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            results.push(...getFilesRecursive(fullPath, extensions));
        } else if (extensions.some(ext => entry.name.endsWith(ext))) {
            results.push(fullPath);
        }
    }
    return results;
}

/**
 * Resolve the mod root directory (parent of translations/)
 */
function getModDir() {
    return path.resolve(__dirname, '..');
}

// Cache for codebase scan results (only scan once per run)
let _codebaseScanCache = null;

/**
 * Gate function: scan the codebase and partition English keys into used/unused.
 * Called once at the start of every command. Results are cached.
 *
 * Returns: { usedKeys: Set, unusedKeys: string[], dynamicPrefixes: Set, activeKeyCount: number }
 */
function gateCodebaseValidation(sourceEntries) {
    if (_codebaseScanCache) return _codebaseScanCache;

    const modDir = getModDir();
    const allKeys = [...sourceEntries.keys()];
    const { usedKeys, dynamicPrefixes } = scanCodebaseForUsedKeys(modDir, allKeys);

    const unusedKeys = allKeys.filter(k => !usedKeys.has(k));

    _codebaseScanCache = {
        usedKeys,
        unusedKeys,
        dynamicPrefixes,
        activeKeyCount: allKeys.length - unusedKeys.length
    };

    return _codebaseScanCache;
}

/**
 * Print the codebase gate summary (shown at start of every command)
 */
function printGateSummary(gate, totalKeys) {
    const used = gate.activeKeyCount;
    const unused = gate.unusedKeys.length;
    console.log(`Codebase gate: ${used} keys in use, ${unused} unused (of ${totalKeys} total in English)`);
    if (gate.dynamicPrefixes.size > 0) {
        console.log(`  Dynamic prefixes detected: ${[...gate.dynamicPrefixes].join(', ')}`);
    }
    if (unused > 0 && unused <= 10) {
        console.log(`  Unused keys: ${gate.unusedKeys.join(', ')}`);
    } else if (unused > 10) {
        console.log(`  Unused keys: ${gate.unusedKeys.slice(0, 5).join(', ')} ... +${unused - 5} more`);
        console.log(`  Run with 'unused' command to see full list`);
    }
    console.log();
}

/**
 * Scan the codebase (src/, gui/, modDesc.xml) to find which translation keys
 * are actually referenced. Returns a Set of used key names.
 *
 * Detection methods:
 *   1. Direct getText("key") calls in Lua
 *   2. All "usedplus_*" / "usedPlus_*" string literals in Lua (catches config tables)
 *   3. $l10n_key references in XML files
 *   4. Dynamic prefix detection ("usedplus_component_" .. var) — whitelists all matching keys
 *   5. Game-engine auto-mapped keys (input_*, fillType_*, configuration_*, unit_*)
 */
function scanCodebaseForUsedKeys(modDir, allEnglishKeys) {
    const usedKeys = new Set();
    const dynamicPrefixes = new Set();

    const srcDir = path.join(modDir, 'src');
    const guiDir = path.join(modDir, 'gui');
    const modDescPath = path.join(modDir, 'modDesc.xml');

    // --- 1 & 2: Scan Lua files for getText() calls and string literals ---
    const luaFiles = getFilesRecursive(srcDir, ['.lua']);
    for (const luaFile of luaFiles) {
        const content = fs.readFileSync(luaFile, 'utf8');

        // Direct getText("key") calls
        const getTextPattern = /getText\("([^"]+)"\)/g;
        let match;
        while ((match = getTextPattern.exec(content)) !== null) {
            usedKeys.add(match[1]);
        }

        // All "usedplus_*" or "usedPlus_*" string literals (catches config tables, nameKey, etc.)
        const stringPattern = /"(usedplus_[a-zA-Z0-9_]+|usedPlus_[a-zA-Z0-9_]+)"/g;
        while ((match = stringPattern.exec(content)) !== null) {
            usedKeys.add(match[1]);
        }

        // Dynamic prefix detection: "usedplus_something_" .. variable
        const dynamicPattern = /"(usedplus_[a-z_]+_|usedPlus_[a-z_]+_)"\s*\.\./g;
        while ((match = dynamicPattern.exec(content)) !== null) {
            dynamicPrefixes.add(match[1]);
        }
    }

    // --- 3: Scan XML files for $l10n_ references ---
    const xmlFiles = getFilesRecursive(guiDir, ['.xml']);
    for (const xmlFile of xmlFiles) {
        const content = fs.readFileSync(xmlFile, 'utf8');
        const l10nPattern = /\$l10n_([a-zA-Z0-9_]+)/g;
        let match;
        while ((match = l10nPattern.exec(content)) !== null) {
            usedKeys.add(match[1]);
        }
    }

    // --- 4: Scan modDesc.xml ---
    if (fs.existsSync(modDescPath)) {
        const content = fs.readFileSync(modDescPath, 'utf8');
        const l10nPattern = /\$l10n_([a-zA-Z0-9_]+)/g;
        let match;
        while ((match = l10nPattern.exec(content)) !== null) {
            usedKeys.add(match[1]);
        }
    }

    // --- 5: Whitelist dynamic prefix keys ---
    // If code has "usedplus_component_" .. var, then all keys starting with
    // "usedplus_component_" are considered used
    for (const prefix of dynamicPrefixes) {
        for (const key of allEnglishKeys) {
            if (key.startsWith(prefix)) {
                usedKeys.add(key);
            }
        }
    }

    // --- 6: Game-engine auto-mapped keys ---
    // FS25 automatically maps input actions, fill types, etc. to $l10n_ keys
    const gameEnginePrefixes = ['input_', 'fillType_', 'configuration_', 'unit_'];
    for (const key of allEnglishKeys) {
        if (gameEnginePrefixes.some(p => key.startsWith(p))) {
            usedKeys.add(key);
        }
    }

    return { usedKeys, dynamicPrefixes };
}

/**
 * Validate a translation entry against its source
 * Returns array of issues found
 */
function validateEntry(key, sourceValue, targetValue, skipUntranslated = true) {
    const issues = [];

    // Skip entries that are still untranslated (have [EN] prefix)
    if (skipUntranslated && targetValue.startsWith(CONFIG.untranslatedPrefix)) {
        return issues;
    }

    // Check for empty value
    if (isEmptyValue(targetValue)) {
        issues.push({ key, type: 'empty', message: 'Empty translation value' });
    }

    // Check for whitespace issues
    if (hasWhitespaceIssues(targetValue)) {
        issues.push({
            key,
            type: 'whitespace',
            message: `Whitespace issue: "${targetValue.substring(0, 20)}..."`,
            value: targetValue
        });
    }

    // Check format specifiers (most critical!)
    const formatIssue = checkFormatSpecifiers(sourceValue, targetValue, key);
    if (formatIssue) {
        issues.push(formatIssue);
    }

    return issues;
}

function getEnabledLanguages() {
    const filePrefix = autoDetectFilePrefix();
    if (!filePrefix) return [];

    const files = fs.readdirSync('.');
    const pattern = new RegExp(`^${filePrefix}_([a-z]{2})\\.xml$`, 'i');
    const languages = [];

    for (const file of files) {
        const match = file.match(pattern);
        if (match) {
            const code = match[1].toLowerCase();
            if (code !== CONFIG.sourceLanguage) {
                languages.push({
                    code,
                    name: LANGUAGE_NAMES[code] || code.toUpperCase()
                });
            }
        }
    }

    return languages.sort((a, b) => a.code.localeCompare(b.code));
}

// ──────────────────────────────────────────────────────────────────────────────
// Auto-Detection Functions
// ──────────────────────────────────────────────────────────────────────────────

function autoDetectFilePrefix() {
    if (CONFIG.filePrefix !== 'auto') return CONFIG.filePrefix;

    if (fs.existsSync(`translation_${CONFIG.sourceLanguage}.xml`)) return 'translation';
    if (fs.existsSync(`l10n_${CONFIG.sourceLanguage}.xml`)) return 'l10n';

    const files = fs.readdirSync('.');
    for (const file of files) {
        if (file.match(/^translation_[a-z]{2}\.xml$/i)) return 'translation';
        if (file.match(/^l10n_[a-z]{2}\.xml$/i)) return 'l10n';
    }

    return null;
}

function autoDetectXmlFormat(content) {
    if (CONFIG.xmlFormat !== 'auto') return CONFIG.xmlFormat;

    if (content.includes('<e k="')) return 'elements';
    if (content.includes('<text name="')) return 'texts';

    return null;
}

function getSourceFilePath(filePrefix) {
    return `${filePrefix}_${CONFIG.sourceLanguage}.xml`;
}

function getLangFilePath(filePrefix, langCode) {
    return `${filePrefix}_${langCode}.xml`;
}

// ──────────────────────────────────────────────────────────────────────────────
// XML Parsing
// ──────────────────────────────────────────────────────────────────────────────

function parseTranslationFile(filepath, format) {
    const content = fs.readFileSync(filepath, 'utf8');
    const entries = new Map();
    const orderedKeys = [];
    const duplicates = [];

    let pattern;
    if (format === 'elements') {
        // <e k="key" v="value" [eh="hash"] [tag="format"] /> - handles any attribute order
        pattern = /<e k="([^"]+)" v="([^"]*)"([^>]*)\s*\/>/g;
    } else {
        // <text name="key" text="value"/>
        pattern = /<text name="([^"]+)" text="([^"]*)"\s*\/>/g;
    }

    let match;
    while ((match = pattern.exec(content)) !== null) {
        const key = match[1];
        const value = match[2];
        // Extract hash from remaining attributes (handles tag="format" eh="hash" in any order)
        const attrs = match[3] || '';
        const hashMatch = attrs.match(/eh="([^"]*)"/);
        const hash = hashMatch ? hashMatch[1] : null;

        // Track duplicates
        if (entries.has(key)) {
            duplicates.push(key);
        }

        entries.set(key, { value, hash });
        orderedKeys.push(key);
    }

    return { entries, orderedKeys, duplicates, rawContent: content };
}

function formatEntry(key, value, hash, format) {
    const escapedValue = escapeXml(value);
    if (format === 'elements') {
        return `<e k="${key}" v="${escapedValue}" eh="${hash}" />`;
    } else {
        return `<text name="${key}" text="${escapedValue}"/>`;
    }
}

function findInsertPosition(content, key, enOrderedKeys, langKeys, format) {
    const enIndex = enOrderedKeys.indexOf(key);

    // Look for the nearest preceding key that exists in this language
    for (let i = enIndex - 1; i >= 0; i--) {
        const prevKey = enOrderedKeys[i];
        if (langKeys.has(prevKey)) {
            let pattern;
            if (format === 'elements') {
                pattern = new RegExp(`<e k="${escapeRegex(prevKey)}" v="[^"]*"(?:\\s+eh="[^"]*")?\\s*/>`, 'g');
            } else {
                pattern = new RegExp(`<text name="${escapeRegex(prevKey)}" text="[^"]*"\\s*/>`, 'g');
            }
            const match = pattern.exec(content);
            if (match) {
                return match.index + match[0].length;
            }
        }
    }

    // Fallback: insert before closing container tag
    const containerTag = format === 'elements' ? 'elements' : 'texts';
    const closeTagIndex = content.indexOf(`</${containerTag}>`);
    if (closeTagIndex !== -1) {
        return closeTagIndex;
    }

    return -1;
}

// ──────────────────────────────────────────────────────────────────────────────
// Update English Source File with Hashes
// ──────────────────────────────────────────────────────────────────────────────

function updateSourceHashes(sourceFile, format) {
    let content = fs.readFileSync(sourceFile, 'utf8');
    const { entries } = parseTranslationFile(sourceFile, format);

    let updated = 0;

    for (const [key, data] of entries) {
        const correctHash = getHash(data.value);

        if (data.hash !== correctHash) {
            // Need to update or add the hash
            // Match entry with any combination of eh= and tag= attributes
            const oldPattern = new RegExp(
                `<e k="${escapeRegex(key)}" v="([^"]*)"([^>]*)\\s*/>`,
                'g'
            );

            content = content.replace(oldPattern, (match, value, attrs) => {
                // Remove any existing eh= attribute
                const cleanAttrs = attrs.replace(/\s*eh="[^"]*"/g, '');
                // Preserve tag="format" if present
                const hasTag = cleanAttrs.includes('tag="format"');
                if (hasTag) {
                    return `<e k="${key}" v="${value}" eh="${correctHash}" tag="format"/>`;
                } else {
                    return `<e k="${key}" v="${value}" eh="${correctHash}" />`;
                }
            });

            updated++;
        }
    }

    if (updated > 0) {
        fs.writeFileSync(sourceFile, content, 'utf8');
    }

    return updated;
}

// ──────────────────────────────────────────────────────────────────────────────
// SYNC Command
// ──────────────────────────────────────────────────────────────────────────────

function syncTranslations() {
    console.log("══════════════════════════════════════════════════════════════════════");
    console.log(`TRANSLATION SYNC v${VERSION} - Hash-Based Synchronization`);
    console.log("══════════════════════════════════════════════════════════════════════");
    console.log();

    const filePrefix = autoDetectFilePrefix();
    if (!filePrefix) {
        console.error("ERROR: Could not find source translation file.");
        console.error(`Looking for: translation_${CONFIG.sourceLanguage}.xml or l10n_${CONFIG.sourceLanguage}.xml`);
        process.exit(1);
    }

    const sourceFile = getSourceFilePath(filePrefix);
    if (!fs.existsSync(sourceFile)) {
        console.error(`ERROR: Source file not found: ${sourceFile}`);
        process.exit(1);
    }

    const sourceContent = fs.readFileSync(sourceFile, 'utf8');
    const format = autoDetectXmlFormat(sourceContent);

    if (!format) {
        console.error("ERROR: Could not detect XML format from source file.");
        process.exit(1);
    }

    // Step 1: Update hashes in the English source file
    console.log(`[1/4] Updating hashes in source file...`);

    if (format === 'elements') {
        const hashesUpdated = updateSourceHashes(sourceFile, format);
        if (hashesUpdated > 0) {
            console.log(`      Updated ${hashesUpdated} hash(es) in ${sourceFile}`);
        } else {
            console.log(`      All hashes current in ${sourceFile}`);
        }
    } else {
        console.log(`      Skipped (hash embedding only supported for 'elements' format)`);
    }

    // Re-parse source after hash update
    const { entries: sourceEntries, orderedKeys: sourceOrderedKeys } = parseTranslationFile(sourceFile, format);

    // GATE: Codebase validation — determine which keys are actually used
    const gate = gateCodebaseValidation(sourceEntries);

    // Compute hashes for comparison
    const sourceHashes = new Map();
    for (const [key, data] of sourceEntries) {
        sourceHashes.set(key, getHash(data.value));
    }

    console.log();
    console.log(`[2/4] Source: ${sourceFile} (${sourceEntries.size} keys)`);
    console.log(`      Format: ${format}`);
    console.log();

    // Step 2: Codebase gate
    console.log(`[3/4] Codebase validation...`);
    printGateSummary(gate, sourceEntries.size);

    // Step 3: Sync to all target languages (only active keys)
    console.log(`[4/4] Syncing to target languages (${gate.activeKeyCount} active keys)...`);
    console.log();

    const enabledLangs = getEnabledLanguages();
    const results = [];

    for (const { code: langCode, name: langName } of enabledLangs) {
        const langFile = getLangFilePath(filePrefix, langCode);

        if (!fs.existsSync(langFile)) {
            console.log(`  ${langName.padEnd(18)}: FILE NOT FOUND - skipping`);
            results.push({ lang: langName, missing: -1, stale: 0, added: 0 });
            continue;
        }

        let { entries: langEntries, orderedKeys: langKeys, duplicates: langDuplicates, rawContent: content } = parseTranslationFile(langFile, format);
        const langKeySet = new Set(langKeys);

        const missing = [];
        const stale = [];
        const duplicates = langDuplicates || [];
        const orphaned = [];
        const formatErrors = [];   // v3.2.0: Format specifier mismatches (CRITICAL)
        const emptyValues = [];    // v3.2.0: Empty translation values
        const whitespaceIssues = []; // v3.2.0: Leading/trailing whitespace
        let added = 0;

        // Find missing and stale keys (source → target)
        for (const sourceKey of sourceOrderedKeys) {
            const sourceHash = sourceHashes.get(sourceKey);

            if (!langEntries.has(sourceKey)) {
                missing.push(sourceKey);
            } else if (format === 'elements') {
                const langData = langEntries.get(sourceKey);
                // Stale = hash doesn't match AND not already marked as untranslated
                if (langData.hash !== sourceHash && !langData.value.startsWith(CONFIG.untranslatedPrefix)) {
                    stale.push(sourceKey);
                }
            }
        }

        // Find orphaned keys (in target but NOT in source)
        for (const langKey of langKeys) {
            if (!sourceEntries.has(langKey)) {
                orphaned.push(langKey);
            }
        }

        // v3.2.0: Validate translations for format specifiers, empty values, whitespace
        for (const [key, sourceData] of sourceEntries) {
            if (langEntries.has(key)) {
                const langData = langEntries.get(key);
                const validationIssues = validateEntry(key, sourceData.value, langData.value);

                for (const issue of validationIssues) {
                    if (issue.type === 'count' || issue.type === 'mismatch') {
                        formatErrors.push(issue);
                    } else if (issue.type === 'empty') {
                        emptyValues.push(issue);
                    } else if (issue.type === 'whitespace') {
                        whitespaceIssues.push(issue);
                    }
                }
            }
        }

        // Add missing keys
        for (const key of missing) {
            const sourceData = sourceEntries.get(key);
            const sourceHash = sourceHashes.get(key);
            const placeholderValue = CONFIG.untranslatedPrefix + sourceData.value;
            const newEntry = `\n        ${formatEntry(key, placeholderValue, sourceHash, format)}`;

            const insertPos = findInsertPosition(content, key, sourceOrderedKeys, langKeySet, format);

            if (insertPos !== -1) {
                content = content.substring(0, insertPos) + newEntry + content.substring(insertPos);
                langKeySet.add(key);
                added++;
            }
        }

        // Update hashes for existing entries to match source (elements format only)
        if (format === 'elements') {
            for (const [key, sourceData] of sourceEntries) {
                if (langEntries.has(key) && !missing.includes(key)) {
                    const sourceHash = sourceHashes.get(key);
                    const langData = langEntries.get(key);

                    // Add hash to entry if:
                    // 1. Translation is current (not stale) - normal case
                    // 2. OR entry has no hash yet AND is not marked as untranslated (first-time adoption)
                    //    This handles the chicken-and-egg problem when first adding hashes to a repo
                    const hasNoHash = !langData.hash;
                    const isUntranslated = langData.value.startsWith(CONFIG.untranslatedPrefix);
                    const shouldAddHash = !stale.includes(key) || (hasNoHash && !isUntranslated);

                    if (shouldAddHash) {
                        // Match entry with any combination of eh= and tag= attributes
                        // Captures: value, optional existing attributes (eh, tag, etc.)
                        const pattern = new RegExp(
                            `<e k="${escapeRegex(key)}" v="([^"]*)"([^>]*)\\s*/>`,
                            'g'
                        );
                        content = content.replace(pattern, (match, v, attrs) => {
                            // Remove any existing eh= attribute
                            const cleanAttrs = attrs.replace(/\s*eh="[^"]*"/g, '');
                            // Preserve tag="format" if present
                            const hasTag = cleanAttrs.includes('tag="format"');
                            if (hasTag) {
                                return `<e k="${key}" v="${v}" eh="${sourceHash}" tag="format"/>`;
                            } else {
                                return `<e k="${key}" v="${v}" eh="${sourceHash}" />`;
                            }
                        });
                    }
                }
            }
        }

        fs.writeFileSync(langFile, content, 'utf8');

        // Report
        const issues = [];
        if (added > 0) issues.push(`+${added} added`);
        if (stale.length > 0) issues.push(`${stale.length} stale`);
        if (duplicates.length > 0) issues.push(`${duplicates.length} duplicates`);
        if (orphaned.length > 0) issues.push(`${orphaned.length} orphaned`);
        // v3.2.0: Add validation issues to report
        if (formatErrors.length > 0) issues.push(`${formatErrors.length} FORMAT ERRORS`);
        if (emptyValues.length > 0) issues.push(`${emptyValues.length} empty`);
        if (whitespaceIssues.length > 0) issues.push(`${whitespaceIssues.length} whitespace`);

        if (issues.length === 0) {
            console.log(`  ${langName.padEnd(18)}: ✓ OK`);
        } else {
            console.log(`  ${langName.padEnd(18)}: ${issues.join(', ')}`);

            // v3.2.0: Show format errors FIRST (most critical!)
            if (formatErrors.length > 0) {
                console.log(`    🔴 FORMAT SPECIFIER ERRORS (will crash game!):`);
                for (const err of formatErrors.slice(0, 5)) {
                    console.log(`    💥 ${err.key}: ${err.message}`);
                }
                if (formatErrors.length > 5) {
                    console.log(`    ... and ${formatErrors.length - 5} more format errors`);
                }
            }

            if (added > 0) {
                for (const key of missing.slice(0, 3)) {
                    console.log(`    + ${key}`);
                }
                if (missing.length > 3) {
                    console.log(`    ... and ${missing.length - 3} more`);
                }
            }

            if (stale.length > 0 && stale.length <= 5) {
                console.log(`    Stale (English changed):`);
                for (const key of stale) {
                    console.log(`    ~ ${key}`);
                }
            } else if (stale.length > 5) {
                console.log(`    Stale: ${stale.slice(0, 3).join(', ')} ... +${stale.length - 3} more`);
            }

            if (duplicates.length > 0 && duplicates.length <= 5) {
                console.log(`    Duplicates (same key appears twice - remove one!):`);
                for (const key of duplicates) {
                    console.log(`    !! ${key}`);
                }
            } else if (duplicates.length > 5) {
                console.log(`    Duplicates: ${duplicates.slice(0, 3).join(', ')} ... +${duplicates.length - 3} more`);
            }

            if (orphaned.length > 0 && orphaned.length <= 5) {
                console.log(`    Orphaned (not in English - can delete):`);
                for (const key of orphaned) {
                    console.log(`    x ${key}`);
                }
            } else if (orphaned.length > 5) {
                console.log(`    Orphaned: ${orphaned.slice(0, 3).join(', ')} ... +${orphaned.length - 3} more`);
            }

            // v3.2.0: Show empty and whitespace issues
            if (emptyValues.length > 0) {
                console.log(`    Empty values: ${emptyValues.slice(0, 3).map(e => e.key).join(', ')}${emptyValues.length > 3 ? ` ... +${emptyValues.length - 3} more` : ''}`);
            }
            if (whitespaceIssues.length > 0) {
                console.log(`    Whitespace issues: ${whitespaceIssues.slice(0, 3).map(e => e.key).join(', ')}${whitespaceIssues.length > 3 ? ` ... +${whitespaceIssues.length - 3} more` : ''}`);
            }
        }

        results.push({
            lang: langName,
            missing: missing.length,
            stale: stale.length,
            duplicates: duplicates.length,
            orphaned: orphaned.length,
            formatErrors: formatErrors.length,
            emptyValues: emptyValues.length,
            whitespaceIssues: whitespaceIssues.length,
            added
        });
    }

    console.log();
    console.log("══════════════════════════════════════════════════════════════════════");
    console.log("SYNC COMPLETE");
    console.log();
    console.log("Hash-based tracking is now embedded in your XML files:");
    console.log("  - English entries have eh=\"hash\" showing current text hash");
    console.log("  - Target entries have eh=\"hash\" showing what they were translated from");
    console.log("  - When hashes don't match = translation is STALE (needs update)");
    console.log();
    console.log(`New entries have "${CONFIG.untranslatedPrefix}" prefix - they need translation!`);
    console.log("When translator updates an entry, update its eh= to match English.");
    console.log("══════════════════════════════════════════════════════════════════════");
}

// ──────────────────────────────────────────────────────────────────────────────
// CHECK Command
// ──────────────────────────────────────────────────────────────────────────────

function checkSync() {
    console.log("══════════════════════════════════════════════════════════════════════");
    console.log(`TRANSLATION CHECK v${VERSION}`);
    console.log("══════════════════════════════════════════════════════════════════════");
    console.log();

    const filePrefix = autoDetectFilePrefix();
    if (!filePrefix) {
        console.error("ERROR: Could not find source translation file.");
        process.exit(1);
    }

    const sourceFile = getSourceFilePath(filePrefix);
    if (!fs.existsSync(sourceFile)) {
        console.error(`ERROR: Source file not found: ${sourceFile}`);
        process.exit(1);
    }

    const sourceContent = fs.readFileSync(sourceFile, 'utf8');
    const format = autoDetectXmlFormat(sourceContent);
    const { entries: sourceEntries } = parseTranslationFile(sourceFile, format);

    // Compute current hashes
    const sourceHashes = new Map();
    for (const [key, data] of sourceEntries) {
        sourceHashes.set(key, getHash(data.value));
    }

    // GATE: Codebase validation
    const gate = gateCodebaseValidation(sourceEntries);

    console.log(`Source: ${sourceFile} (${sourceEntries.size} keys, ${gate.activeKeyCount} active)\n`);
    printGateSummary(gate, sourceEntries.size);

    let hasProblems = false;
    const summary = [];
    const enabledLangs = getEnabledLanguages();

    for (const { code: langCode, name: langName } of enabledLangs) {
        const langFile = getLangFilePath(filePrefix, langCode);

        if (!fs.existsSync(langFile)) {
            console.log(`  ${langName.padEnd(18)}: FILE NOT FOUND`);
            hasProblems = true;
            summary.push({ name: langName, total: 0, missing: -1, stale: 0, untranslated: 0 });
            continue;
        }

        const { entries: langEntries, orderedKeys: langKeys, duplicates: langDuplicates } = parseTranslationFile(langFile, format);

        const missing = [];
        const stale = [];
        const untranslated = [];
        const duplicates = langDuplicates || [];
        const orphaned = [];

        for (const [key, sourceData] of sourceEntries) {
            const sourceHash = sourceHashes.get(key);

            if (!langEntries.has(key)) {
                missing.push(key);
            } else {
                const langData = langEntries.get(key);

                if (langData.value.startsWith(CONFIG.untranslatedPrefix)) {
                    untranslated.push(key);
                } else if (langData.value === sourceData.value && !isFormatOnlyString(sourceData.value) && !isCognateOrInternationalTerm(sourceData.value)) {
                    // Exact match = untranslated, UNLESS it's a format-only string or cognate/international term
                    untranslated.push(key);
                } else if (format === 'elements' && langData.hash && langData.hash !== sourceHash) {
                    stale.push(key);
                }
            }
        }

        // Find orphaned keys (in target but NOT in source)
        for (const langKey of langKeys) {
            if (!sourceEntries.has(langKey)) {
                orphaned.push(langKey);
            }
        }

        const issues = [];
        if (missing.length > 0) issues.push(`${missing.length} MISSING`);
        if (stale.length > 0) issues.push(`${stale.length} stale`);
        if (untranslated.length > 0) issues.push(`${untranslated.length} untranslated`);
        if (duplicates.length > 0) issues.push(`${duplicates.length} duplicates`);
        if (orphaned.length > 0) issues.push(`${orphaned.length} orphaned`);

        if (issues.length === 0) {
            console.log(`  ${langName.padEnd(18)}: ✓ OK (${langEntries.size} keys)`);
        } else {
            if (missing.length > 0 || duplicates.length > 0 || orphaned.length > 0) hasProblems = true;
            console.log(`  ${langName.padEnd(18)}: ${issues.join(', ')}`);
        }

        summary.push({
            name: langName,
            total: langEntries.size,
            missing: missing.length,
            stale: stale.length,
            untranslated: untranslated.length,
            duplicates: duplicates.length,
            orphaned: orphaned.length
        });
    }

    console.log();
    console.log("──────────────────────────────────────────────────────────────────────────────────────────────────");
    console.log("SUMMARY:");
    console.log("──────────────────────────────────────────────────────────────────────────────────────────────────");
    console.log("Language            | Total  | Missing | Stale | Untranslated | Duplicates | Orphaned");
    console.log("──────────────────────────────────────────────────────────────────────────────────────────────────");

    for (const s of summary) {
        const status = (s.missing > 0 || s.duplicates > 0 || s.orphaned > 0) ? '!!' : '  ';
        const totalStr = s.missing === -1 ? '  N/A' : String(s.total).padStart(6);
        const missingStr = s.missing === -1 ? '  N/A' : String(s.missing).padStart(7);
        const dupsStr = s.duplicates !== undefined ? String(s.duplicates).padStart(10) : '       N/A';
        const orphStr = s.orphaned !== undefined ? String(s.orphaned).padStart(8) : '     N/A';
        console.log(`${status}${s.name.padEnd(18)} | ${totalStr} | ${missingStr} | ${String(s.stale).padStart(5)} | ${String(s.untranslated).padStart(12)} | ${dupsStr} | ${orphStr}`);
    }

    console.log("──────────────────────────────────────────────────────────────────────────────────────────────────");

    if (hasProblems) {
        console.log();
        const totalMissing = summary.reduce((sum, s) => sum + (s.missing > 0 ? s.missing : 0), 0);
        const totalDuplicates = summary.reduce((sum, s) => sum + (s.duplicates || 0), 0);
        const totalOrphaned = summary.reduce((sum, s) => sum + (s.orphaned || 0), 0);
        if (totalMissing > 0) {
            console.log("CRITICAL: Missing keys detected! Run 'node translation_sync.js sync' to fix.");
        }
        if (totalDuplicates > 0) {
            console.log(`CRITICAL: ${totalDuplicates} duplicate keys found! Manually remove duplicate entries from XML files.`);
        }
        if (totalOrphaned > 0) {
            console.log(`WARNING: ${totalOrphaned} orphaned keys found (in target but not in English). Safe to delete.`);
        }
        process.exit(1);
    } else {
        console.log();
        const totalStale = summary.reduce((sum, s) => sum + s.stale, 0);
        const totalUntranslated = summary.reduce((sum, s) => sum + s.untranslated, 0);

        if (totalStale > 0) {
            console.log(`Note: ${totalStale} stale entries need re-translation (English text changed).`);
        }
        if (totalUntranslated > 0) {
            console.log(`Note: ${totalUntranslated} entries have "${CONFIG.untranslatedPrefix}" prefix and need translation.`);
        }
        if (totalStale === 0 && totalUntranslated === 0) {
            console.log("All translations are complete and up to date!");
        }
        process.exit(0);
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// STATUS Command
// ──────────────────────────────────────────────────────────────────────────────

function showStatus() {
    console.log();
    console.log("══════════════════════════════════════════════════════════════════════");
    console.log(`TRANSLATION STATUS v${VERSION}`);
    console.log("══════════════════════════════════════════════════════════════════════");
    console.log();

    const filePrefix = autoDetectFilePrefix();
    if (!filePrefix) {
        console.error("ERROR: Could not find translation files.");
        process.exit(1);
    }

    const sourceFile = getSourceFilePath(filePrefix);
    const sourceContent = fs.readFileSync(sourceFile, 'utf8');
    const format = autoDetectXmlFormat(sourceContent);
    const { entries: sourceEntries } = parseTranslationFile(sourceFile, format);

    const sourceHashes = new Map();
    for (const [key, data] of sourceEntries) {
        sourceHashes.set(key, getHash(data.value));
    }

    // GATE: Codebase validation
    const gate = gateCodebaseValidation(sourceEntries);

    console.log(`Source: ${sourceFile} (${sourceEntries.size} keys, ${gate.activeKeyCount} active)`);
    console.log(`Format: ${format}${format === 'elements' ? ' (hash-enabled)' : ''}`);
    console.log();
    printGateSummary(gate, sourceEntries.size);

    console.log("Language            | Translated |  Stale  | Untranslated | Missing | Dups | Orphaned");
    console.log("──────────────────────────────────────────────────────────────────────────────────────────");

    const enabledLangs = getEnabledLanguages();

    for (const { code: langCode, name: langName } of enabledLangs) {
        const langFile = getLangFilePath(filePrefix, langCode);

        if (!fs.existsSync(langFile)) {
            console.log(`${langName.padEnd(20)}|    N/A     |   N/A   |     N/A      |   N/A   |  N/A |    N/A`);
            continue;
        }

        const { entries: langEntries, orderedKeys: langKeys, duplicates: langDuplicates } = parseTranslationFile(langFile, format);

        let translated = 0, stale = 0, untranslated = 0, missing = 0, orphaned = 0, formatErrs = 0;
        const duplicates = langDuplicates ? langDuplicates.length : 0;

        for (const [key, sourceData] of sourceEntries) {
            const sourceHash = sourceHashes.get(key);

            if (!langEntries.has(key)) {
                missing++;
            } else {
                const langData = langEntries.get(key);

                if (langData.value.startsWith(CONFIG.untranslatedPrefix)) {
                    untranslated++;
                } else if (langData.value === sourceData.value && !isFormatOnlyString(sourceData.value) && !isCognateOrInternationalTerm(sourceData.value)) {
                    untranslated++;
                } else if (format === 'elements' && langData.hash && langData.hash !== sourceHash) {
                    stale++;
                } else {
                    translated++;
                }

                // v3.2.0: Check format specifiers
                const formatIssue = checkFormatSpecifiers(sourceData.value, langData.value, key);
                if (formatIssue && !langData.value.startsWith(CONFIG.untranslatedPrefix)) {
                    formatErrs++;
                }
            }
        }

        // Count orphaned keys
        for (const langKey of langKeys) {
            if (!sourceEntries.has(langKey)) {
                orphaned++;
            }
        }

        // v3.2.0: Show format errors prominently
        const fmtStr = formatErrs > 0 ? ` 🔴${formatErrs}` : '';
        console.log(`${langName.padEnd(20)}| ${String(translated).padStart(10)} | ${String(stale).padStart(7)} | ${String(untranslated).padStart(12)} | ${String(missing).padStart(7)} | ${String(duplicates).padStart(4)} | ${String(orphaned).padStart(8)}${fmtStr}`);
    }

    console.log("──────────────────────────────────────────────────────────────────────────────────────────");
    console.log("🔴 = Format specifier errors (CRITICAL - will crash game!)");
}

// ──────────────────────────────────────────────────────────────────────────────
// REPORT Command
// ──────────────────────────────────────────────────────────────────────────────

function generateReport() {
    console.log("══════════════════════════════════════════════════════════════════════");
    console.log(`TRANSLATION DETAILED REPORT v${VERSION}`);
    console.log("══════════════════════════════════════════════════════════════════════");
    console.log();

    const filePrefix = autoDetectFilePrefix();
    if (!filePrefix) {
        console.error("ERROR: Could not find source translation file.");
        process.exit(1);
    }

    const sourceFile = getSourceFilePath(filePrefix);
    const sourceContent = fs.readFileSync(sourceFile, 'utf8');
    const format = autoDetectXmlFormat(sourceContent);
    const { entries: sourceEntries } = parseTranslationFile(sourceFile, format);

    const sourceHashes = new Map();
    for (const [key, data] of sourceEntries) {
        sourceHashes.set(key, getHash(data.value));
    }

    // GATE: Codebase validation
    const gate = gateCodebaseValidation(sourceEntries);

    console.log(`Source: ${sourceFile} (${sourceEntries.size} keys, ${gate.activeKeyCount} active)\n`);
    printGateSummary(gate, sourceEntries.size);

    const enabledLangs = getEnabledLanguages();

    for (const { code: langCode, name: langName } of enabledLangs) {
        const langFile = getLangFilePath(filePrefix, langCode);

        if (!fs.existsSync(langFile)) {
            console.log(`${langName} (${langCode.toUpperCase()}): FILE NOT FOUND\n`);
            continue;
        }

        const { entries: langEntries, orderedKeys: langKeys, duplicates: langDuplicates } = parseTranslationFile(langFile, format);

        const translated = [];
        const missing = [];
        const stale = [];
        const untranslated = [];
        const duplicates = langDuplicates || [];
        const orphaned = [];

        for (const [key, sourceData] of sourceEntries) {
            const sourceHash = sourceHashes.get(key);

            if (!langEntries.has(key)) {
                missing.push({ key, enValue: sourceData.value });
            } else {
                const langData = langEntries.get(key);

                if (langData.value.startsWith(CONFIG.untranslatedPrefix)) {
                    untranslated.push({ key, reason: 'has [EN] prefix' });
                } else if (langData.value === sourceData.value && !isFormatOnlyString(sourceData.value) && !isCognateOrInternationalTerm(sourceData.value)) {
                    untranslated.push({ key, reason: 'exact match (not cognate)' });
                } else if (format === 'elements' && langData.hash && langData.hash !== sourceHash) {
                    stale.push({
                        key,
                        oldHash: langData.hash,
                        newHash: sourceHash,
                        enValue: sourceData.value
                    });
                } else {
                    translated.push(key);
                }
            }
        }

        // Find orphaned keys
        for (const langKey of langKeys) {
            if (!sourceEntries.has(langKey)) {
                orphaned.push(langKey);
            }
        }

        console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
        console.log(`${langName} (${langCode.toUpperCase()})`);
        console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
        console.log(`  Translated:    ${translated.length}`);
        console.log(`  Missing:       ${missing.length}`);
        console.log(`  Stale:         ${stale.length}`);
        console.log(`  Untranslated:  ${untranslated.length}`);
        console.log(`  Duplicates:    ${duplicates.length}`);
        console.log(`  Orphaned:      ${orphaned.length}`);

        if (missing.length > 0) {
            console.log(`\n  ── MISSING KEYS ──`);
            for (const { key } of missing.slice(0, 10)) {
                console.log(`    - ${key}`);
            }
            if (missing.length > 10) {
                console.log(`    ... and ${missing.length - 10} more`);
            }
        }

        if (stale.length > 0) {
            console.log(`\n  ── STALE (English changed since translation) ──`);
            for (const { key, oldHash, newHash } of stale.slice(0, 10)) {
                console.log(`    ~ ${key}  (${oldHash} → ${newHash})`);
            }
            if (stale.length > 10) {
                console.log(`    ... and ${stale.length - 10} more`);
            }
        }

        if (untranslated.length > 0 && untranslated.length <= 10) {
            console.log(`\n  ── UNTRANSLATED ──`);
            for (const { key, reason } of untranslated) {
                console.log(`    ? ${key}  (${reason})`);
            }
        } else if (untranslated.length > 10) {
            console.log(`\n  ── UNTRANSLATED (showing first 10) ──`);
            for (const { key, reason } of untranslated.slice(0, 10)) {
                console.log(`    ? ${key}  (${reason})`);
            }
            console.log(`    ... and ${untranslated.length - 10} more`);
        }

        if (duplicates.length > 0 && duplicates.length <= 10) {
            console.log(`\n  ── DUPLICATES (same key appears twice - remove one!) ──`);
            for (const key of duplicates) {
                console.log(`    !! ${key}`);
            }
        } else if (duplicates.length > 10) {
            console.log(`\n  ── DUPLICATES (showing first 10) ──`);
            for (const key of duplicates.slice(0, 10)) {
                console.log(`    !! ${key}`);
            }
            console.log(`    ... and ${duplicates.length - 10} more`);
        }

        if (orphaned.length > 0 && orphaned.length <= 10) {
            console.log(`\n  ── ORPHANED (not in English - safe to delete) ──`);
            for (const key of orphaned) {
                console.log(`    x ${key}`);
            }
        } else if (orphaned.length > 10) {
            console.log(`\n  ── ORPHANED (showing first 10) ──`);
            for (const key of orphaned.slice(0, 10)) {
                console.log(`    x ${key}`);
            }
            console.log(`    ... and ${orphaned.length - 10} more`);
        }

        console.log();
    }

    // UNUSED section (global, not per-language)
    if (gate.unusedKeys.length > 0) {
        console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
        console.log(`UNUSED KEYS (${gate.unusedKeys.length} keys not referenced in codebase)`);
        console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
        for (const key of gate.unusedKeys.slice(0, 20)) {
            console.log(`    - ${key}`);
        }
        if (gate.unusedKeys.length > 20) {
            console.log(`    ... and ${gate.unusedKeys.length - 20} more (run 'unused' command for full list)`);
        }
        console.log();
    }

    console.log("══════════════════════════════════════════════════════════════════════");
}

// ──────────────────────────────────────────────────────────────────────────────
// VALIDATE Command (CI-friendly)
// ──────────────────────────────────────────────────────────────────────────────

function validateSync() {
    const filePrefix = autoDetectFilePrefix();
    if (!filePrefix) {
        console.log("FAIL: No translation files found");
        process.exit(1);
    }

    const sourceFile = getSourceFilePath(filePrefix);
    if (!fs.existsSync(sourceFile)) {
        console.log("FAIL: Source file not found");
        process.exit(1);
    }

    const sourceContent = fs.readFileSync(sourceFile, 'utf8');
    const format = autoDetectXmlFormat(sourceContent);
    const { entries: sourceEntries } = parseTranslationFile(sourceFile, format);

    // GATE: Codebase validation
    const gate = gateCodebaseValidation(sourceEntries);

    let hasProblems = false;
    const enabledLangs = getEnabledLanguages();

    for (const { code: langCode } of enabledLangs) {
        const langFile = getLangFilePath(filePrefix, langCode);
        if (!fs.existsSync(langFile)) {
            hasProblems = true;
            break;
        }

        const { entries: langEntries } = parseTranslationFile(langFile, format);

        for (const [key] of sourceEntries) {
            if (!langEntries.has(key)) {
                hasProblems = true;
                break;
            }
        }

        if (hasProblems) break;
    }

    if (hasProblems) {
        console.log("FAIL: Translation files out of sync");
        process.exit(1);
    } else {
        console.log("OK: All translation files have required keys");
        process.exit(0);
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// UNUSED Command
// ──────────────────────────────────────────────────────────────────────────────

function showUnused() {
    console.log("══════════════════════════════════════════════════════════════════════");
    console.log(`UNUSED TRANSLATION KEYS v${VERSION}`);
    console.log("══════════════════════════════════════════════════════════════════════");
    console.log();

    const filePrefix = autoDetectFilePrefix();
    if (!filePrefix) {
        console.error("ERROR: Could not find source translation file.");
        process.exit(1);
    }

    const sourceFile = getSourceFilePath(filePrefix);
    const sourceContent = fs.readFileSync(sourceFile, 'utf8');
    const format = autoDetectXmlFormat(sourceContent);
    const { entries: sourceEntries } = parseTranslationFile(sourceFile, format);

    const gate = gateCodebaseValidation(sourceEntries);
    printGateSummary(gate, sourceEntries.size);

    if (gate.unusedKeys.length === 0) {
        console.log("All keys are referenced in the codebase. Nothing to clean up!");
        return;
    }

    // Group unused keys by prefix
    const groups = new Map();
    for (const key of gate.unusedKeys) {
        // Extract prefix: everything up to and including the second underscore
        const parts = key.split('_');
        const prefix = parts.length >= 2 ? parts.slice(0, 2).join('_') + '_' : key;
        if (!groups.has(prefix)) groups.set(prefix, []);
        groups.get(prefix).push(key);
    }

    // Sort groups by size (largest first)
    const sortedGroups = [...groups.entries()].sort((a, b) => b[1].length - a[1].length);

    console.log(`${gate.unusedKeys.length} unused keys grouped by prefix:\n`);

    for (const [prefix, keys] of sortedGroups) {
        console.log(`  ${prefix}* (${keys.length} keys):`);
        for (const key of keys) {
            console.log(`    - ${key}`);
        }
        console.log();
    }

    console.log("══════════════════════════════════════════════════════════════════════");
    console.log("To remove these keys, run:");
    console.log("  node translation_sync.js prune --all-unused");
    console.log("Or remove specific keys:");
    console.log("  node translation_sync.js prune key1 key2 key3");
    console.log("══════════════════════════════════════════════════════════════════════");
}

// ──────────────────────────────────────────────────────────────────────────────
// PRUNE Command
// ──────────────────────────────────────────────────────────────────────────────

/**
 * Remove specified keys from English + all language translation files.
 *
 * Usage:
 *   node translation_sync.js prune key1 key2 key3     # Remove specific keys
 *   node translation_sync.js prune --all-unused        # Remove all codebase-unused keys
 */
function pruneKeys() {
    console.log("══════════════════════════════════════════════════════════════════════");
    console.log(`TRANSLATION PRUNE v${VERSION}`);
    console.log("══════════════════════════════════════════════════════════════════════");
    console.log();

    const filePrefix = autoDetectFilePrefix();
    if (!filePrefix) {
        console.error("ERROR: Could not find source translation file.");
        process.exit(1);
    }

    const sourceFile = getSourceFilePath(filePrefix);
    const sourceContent = fs.readFileSync(sourceFile, 'utf8');
    const format = autoDetectXmlFormat(sourceContent);
    const { entries: sourceEntries } = parseTranslationFile(sourceFile, format);

    // Determine which keys to prune
    const args = process.argv.slice(3);
    let keysToPrune = [];

    if (args.includes('--all-unused')) {
        const gate = gateCodebaseValidation(sourceEntries);
        printGateSummary(gate, sourceEntries.size);
        keysToPrune = gate.unusedKeys;
    } else if (args.length > 0) {
        keysToPrune = args.filter(a => !a.startsWith('--'));
    } else {
        console.error("ERROR: Specify keys to prune, or use --all-unused");
        console.error("");
        console.error("  node translation_sync.js prune key1 key2 key3");
        console.error("  node translation_sync.js prune --all-unused");
        process.exit(1);
    }

    if (keysToPrune.length === 0) {
        console.log("No keys to prune.");
        return;
    }

    // Validate that specified keys actually exist in English
    const validKeys = [];
    const invalidKeys = [];
    for (const key of keysToPrune) {
        if (sourceEntries.has(key)) {
            validKeys.push(key);
        } else {
            invalidKeys.push(key);
        }
    }

    if (invalidKeys.length > 0) {
        console.log(`WARNING: ${invalidKeys.length} key(s) not found in English source (skipping):`);
        for (const key of invalidKeys.slice(0, 10)) {
            console.log(`  ? ${key}`);
        }
        if (invalidKeys.length > 10) {
            console.log(`  ... and ${invalidKeys.length - 10} more`);
        }
        console.log();
    }

    if (validKeys.length === 0) {
        console.log("No valid keys to prune.");
        return;
    }

    console.log(`Pruning ${validKeys.length} key(s) from all translation files...\n`);

    // Build the set for fast lookup
    const pruneSet = new Set(validKeys);

    // Process English source + all language files
    const allFiles = [sourceFile];
    const enabledLangs = getEnabledLanguages();
    for (const { code } of enabledLangs) {
        const langFile = getLangFilePath(filePrefix, code);
        if (fs.existsSync(langFile)) {
            allFiles.push(langFile);
        }
    }

    let totalRemoved = 0;

    for (const filePath of allFiles) {
        let content = fs.readFileSync(filePath, 'utf8');
        let removedFromFile = 0;

        for (const key of pruneSet) {
            // Match the full XML line for this key (handles both formats)
            let pattern;
            if (format === 'elements') {
                // Match: optional whitespace + <e k="key" ... /> + optional newline
                pattern = new RegExp(`\\s*<e k="${escapeRegex(key)}" v="[^"]*"[^>]*/>\\s*\\n?`, 'g');
            } else {
                pattern = new RegExp(`\\s*<text name="${escapeRegex(key)}" text="[^"]*"\\s*/>\\s*\\n?`, 'g');
            }

            const before = content;
            content = content.replace(pattern, '\n');
            if (content !== before) {
                removedFromFile++;
            }
        }

        if (removedFromFile > 0) {
            // Clean up any double-blank-lines left behind
            content = content.replace(/\n{3,}/g, '\n\n');
            fs.writeFileSync(filePath, content, 'utf8');
        }

        const fileName = path.basename(filePath);
        if (removedFromFile > 0) {
            console.log(`  ${fileName.padEnd(25)}: removed ${removedFromFile} key(s)`);
            totalRemoved += removedFromFile;
        } else {
            console.log(`  ${fileName.padEnd(25)}: no matches`);
        }
    }

    console.log();
    console.log("══════════════════════════════════════════════════════════════════════");
    console.log(`PRUNE COMPLETE: Removed ${totalRemoved} entries across ${allFiles.length} files`);
    console.log("══════════════════════════════════════════════════════════════════════");
}

// ──────────────────────────────────────────────────────────────────────────────
// Help
// ──────────────────────────────────────────────────────────────────────────────

function showHelp() {
    console.log(`
══════════════════════════════════════════════════════════════════════════════
UNIVERSAL TRANSLATION SYNC TOOL v${VERSION}
══════════════════════════════════════════════════════════════════════════════

A hash-based translation synchronization tool for Farming Simulator 25 mods.

HOW HASH-BASED SYNC WORKS:
  Every entry embeds a hash of its English source text:

  English:  <e k="greeting" v="Hello World" eh="a1b2c3d4"/>
  German:   <e k="greeting" v="Hallo Welt" eh="a1b2c3d4"/>

  When English changes, its hash changes. Target entries keep their old hash
  until the translator updates them. Hash mismatch = STALE translation.

COMMANDS:
  sync      - Add missing keys, update source hashes, report stale entries
  check     - Report all issues, exit code 1 if MISSING keys exist
  status    - Quick overview: translated/stale/missing per language
  report    - Detailed breakdown by language with lists of problem keys
  validate  - CI-friendly: minimal output, exit codes only
  unused    - List all dead keys not referenced in codebase (grouped by prefix)
  prune     - Remove keys from English + all language files
  help      - Show this help

CODEBASE VALIDATION (v4.0.0):
  All commands show a codebase gate summary identifying which English keys
  are actually referenced in src/*.lua, gui/*.xml, or modDesc.xml. Keys not
  found in the codebase are flagged as UNUSED — use 'prune' to remove them.

USAGE:
  node translation_sync.js sync     # Sync all languages, update hashes
  node translation_sync.js check    # Verify sync status
  node translation_sync.js report   # See detailed stale/missing lists
  node translation_sync.js unused   # List dead keys for cleanup
  node translation_sync.js prune key1 key2   # Remove specific keys from all files
  node translation_sync.js prune --all-unused # Remove all dead keys at once

WORKFLOW:
  1. Add/change text in translation_${CONFIG.sourceLanguage}.xml
  2. Run: node translation_sync.js sync
  3. Script updates English hashes, adds missing keys to other languages
  4. Report shows which entries are STALE (English changed, needs re-translation)
  5. Translator updates entry and sets eh= to match English

STATUS MEANINGS:
  ✓ Translated   - Entry exists and hash matches (up to date)
  ~ Stale        - Hash mismatch (English changed since translation)
  ? Untranslated - Has "[EN] " prefix or exact match to English
  - Missing      - Key doesn't exist in target file
  !! Duplicate   - Same key appears more than once (data quality issue!)
  x Orphaned     - Key in target file but NOT in English (safe to delete)

VALIDATION (v3.2.0):
  💥 Format Error  - Missing/wrong format specifiers (%s, %.1f, etc.) - WILL CRASH!
  ⚠ Empty Value   - Translation is empty string
  ⚠ Whitespace    - Leading/trailing spaces in translation

══════════════════════════════════════════════════════════════════════════════
`);
}

// ──────────────────────────────────────────────────────────────────────────────
// Main
// ──────────────────────────────────────────────────────────────────────────────

const command = process.argv[2]?.toLowerCase();

switch (command) {
    case 'sync':
        syncTranslations();
        break;
    case 'check':
        checkSync();
        break;
    case 'status':
        showStatus();
        break;
    case 'report':
        generateReport();
        break;
    case 'validate':
        validateSync();
        break;
    case 'unused':
        showUnused();
        break;
    case 'prune':
        pruneKeys();
        break;
    case 'help':
    case '--help':
    case '-h':
        showHelp();
        break;
    default:
        showHelp();
}
