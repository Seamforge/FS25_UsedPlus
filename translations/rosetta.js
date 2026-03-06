#!/usr/bin/env node
/**
 * ROSETTA.JS v1.0.0 — Translation Management Tool for FS25 Mods
 * Named after the Rosetta Stone that decoded multiple languages from a single artifact.
 * Replaces translation_sync.js with atomic key ops, JSON protocol, and health checks.
 * Run: node rosetta.js help
 * Author: FS25_UsedPlus Team | License: MIT
 */

const VERSION = '1.0.0';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// --- CONFIGURATION

const CONFIG = {
    sourceLanguage: 'en',
    untranslatedPrefix: '[EN] ',
    filePrefix: 'auto',
    xmlFormat: 'auto',
};

// --- LANGUAGE NAME MAPPINGS

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

// --- LOW-LEVEL UTILITIES

function getHash(text) {
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

/**
 * Extract format specifiers from a string.
 * Matches: %s, %d, %i, %f, %.1f, %.2f, %ld, etc.
 * Excludes space flag to avoid false positives like "40% success".
 */
function extractFormatSpecifiers(str) {
    const pattern = /%[-+0#]*(\d+)?(\.\d+)?(hh?|ll?|L|z|j|t)?[diouxXeEfFgGaAcspn]/g;
    const matches = str.match(pattern) || [];
    return matches.sort();
}

/**
 * Compare format specifiers between source and target.
 * Returns null if OK, or error object if mismatch.
 */
function checkFormatSpecifiers(sourceValue, targetValue, key) {
    const sourceSpecs = extractFormatSpecifiers(sourceValue);
    const targetSpecs = extractFormatSpecifiers(targetValue);

    if (sourceSpecs.length !== targetSpecs.length) {
        return {
            key,
            type: 'count',
            source: sourceSpecs,
            target: targetSpecs,
            message: `Expected ${sourceSpecs.length} format specifier(s), found ${targetSpecs.length}`
        };
    }

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

    return null;
}

// --- COGNATE DETECTION

/**
 * Check if a string is "format-only" (no translatable text content).
 * These are strings like "%s %%", "%d km", "%s:%s" that are identical in all languages.
 */
function isFormatOnlyString(value) {
    if (!value) return false;
    const stripped = value
        .replace(/%[-+0-9]*\.?[0-9]*[sdfeEgGoxXuc%]/g, '')
        .replace(/\b(km|m|kg|l|h|s|ms|px|pcs)\b/gi, '')
        .replace(/[:\s.,\-\/()[\]{}]+/g, '');
    return stripped.length === 0;
}

/**
 * Check if a value is likely a cognate or international term.
 * These are values legitimately the same in multiple languages.
 */
function isCognateOrInternationalTerm(value) {
    if (value === '') return true;
    if (!value) return false;
    if (value.length > 50) return false;
    if (value.length <= 3) return true;
    if (/^[#$@%&*()[\]{}\-+:,.\/\d\s]+$/.test(value)) return true;
    if (/^-\s+[A-Z][a-z]+$/.test(value)) return true;

    const commonCognates = [
        'type', 'total', 'status', 'agent', 'normal', 'ok', 'info', 'mode',
        'generator', 'starter', 'min', 'max', 'per', 'vs', 'hardcore',
        'obd', 'ecu', 'can', 'dtc', 'debug', 'regional', 'national',
        'original', 'score', 'principal', 'ha', 'pcs', 'elite', 'premium',
        'standard', 'budget', 'basic', 'advanced', 'pro', 'master',
        'leasing', 'spawning', 'repo', 'state', 'misfire', 'overheat',
        'runaway', 'cutout', 'workhorse', 'integration', 'vanilla',
        'item', 'land', 'thermostat',
        'description', 'confirmation', 'actions', 'excellent', 'finance', 'finances',
        'acceptable', 'stable', 'ratio'
    ];
    const lowerValue = value.toLowerCase().trim();
    if (commonCognates.includes(lowerValue)) return true;

    const commonPhrases = [
        'regional agent', 'national agent', 'local agent',
        'no', 'yes', 'si', 'ja',
        'obd scanner', 'service truck', 'spawn lemon', 'toggle debug',
        'reset cd'
    ];
    if (commonPhrases.includes(lowerValue)) return true;

    if (/^vs\s+/i.test(value)) return true;
    if (/^[A-Z\s:]+$/.test(value) && value.replace(/[:\s]/g, '').length >= 2) return true;
    if (/^[A-Za-z]+:\s*$/.test(value)) return true;
    if (/^[+\-]?\$[\d,]+$/.test(value) || /^Set \$\d+$/.test(value)) return true;
    if (/^(Rel|Surge|Flat):/i.test(value) || /\(L\)$|\(R\)$/.test(value)) return true;
    if (/^[A-Z]{2,5}\s+Integration$/i.test(value)) return true;
    if (/^[A-Z]+\s+[A-Z0-9\-]+/i.test(value) && value.split(' ').length <= 4) return true;

    return false;
}

// --- XML I/O

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

/**
 * Parse a translation XML file into a structured representation.
 * Returns { entries: Map, orderedKeys: [], duplicates: [], rawContent: string }
 */
function parseTranslationFile(filepath, format) {
    const content = fs.readFileSync(filepath, 'utf8');
    const entries = new Map();
    const orderedKeys = [];
    const duplicates = [];

    let pattern;
    if (format === 'elements') {
        pattern = /<e k="([^"]+)" v="([^"]*)"([^>]*)\s*\/>/g;
    } else {
        pattern = /<text name="([^"]+)" text="([^"]*)"\s*\/>/g;
    }

    let match;
    while ((match = pattern.exec(content)) !== null) {
        const key = match[1];
        const value = match[2];
        const attrs = match[3] || '';
        const hashMatch = attrs.match(/eh="([^"]*)"/);
        const hash = hashMatch ? hashMatch[1] : null;
        const tagMatch = attrs.match(/tag="([^"]*)"/);
        const tag = tagMatch ? tagMatch[1] : null;

        if (entries.has(key)) {
            duplicates.push(key);
        }

        entries.set(key, { value, hash, tag });
        orderedKeys.push(key);
    }

    return { entries, orderedKeys, duplicates, rawContent: content };
}

/**
 * Format a single XML entry line.
 */
function formatEntry(key, value, hash, format, tag) {
    const escapedValue = escapeXml(value);
    if (format === 'elements') {
        const tagAttr = tag ? ` tag="${tag}"` : '';
        return `<e k="${key}" v="${escapedValue}" eh="${hash}"${tagAttr} />`;
    } else {
        return `<text name="${key}" text="${escapedValue}"/>`;
    }
}

/**
 * Find the correct position to insert a new entry, maintaining English key order.
 */
function findInsertPosition(content, key, enOrderedKeys, langKeys, format) {
    const enIndex = enOrderedKeys.indexOf(key);

    for (let i = enIndex - 1; i >= 0; i--) {
        const prevKey = enOrderedKeys[i];
        if (langKeys.has(prevKey)) {
            let pattern;
            if (format === 'elements') {
                pattern = new RegExp(`<e k="${escapeRegex(prevKey)}" v="[^"]*"[^>]*\\s*/>`, 'g');
            } else {
                pattern = new RegExp(`<text name="${escapeRegex(prevKey)}" text="[^"]*"\\s*/>`, 'g');
            }
            const match = pattern.exec(content);
            if (match) {
                return match.index + match[0].length;
            }
        }
    }

    const containerTag = format === 'elements' ? 'elements' : 'texts';
    const closeTagIndex = content.indexOf(`</${containerTag}>`);
    if (closeTagIndex !== -1) {
        return closeTagIndex;
    }

    return -1;
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

// --- CLASSIFICATION ENGINE — Single classifier for all commands

/**
 * Classify all entries for a target language against the English source.
 *
 * Returns {
 *   translated: [{ key, value }],
 *   stale: [{ key, value, oldHash, newHash, enValue }],
 *   untranslated: [{ key, value, reason }],
 *   missing: [{ key, enValue }],
 *   orphaned: [key],
 *   duplicates: [key],
 *   formatErrors: [{ key, type, source, target, message }],
 *   emptyValues: [{ key }],
 *   whitespaceIssues: [{ key, value }]
 * }
 */
function classifyEntries(sourceEntries, sourceHashes, langEntries, langOrderedKeys, format) {
    const result = {
        translated: [],
        stale: [],
        untranslated: [],
        missing: [],
        orphaned: [],
        duplicates: [],
        formatErrors: [],
        emptyValues: [],
        whitespaceIssues: [],
    };

    for (const [key, sourceData] of sourceEntries) {
        const sourceHash = sourceHashes.get(key);

        if (!langEntries.has(key)) {
            result.missing.push({ key, enValue: sourceData.value });
        } else {
            const langData = langEntries.get(key);

            if (langData.value.startsWith(CONFIG.untranslatedPrefix)) {
                result.untranslated.push({ key, value: langData.value, reason: 'has [EN] prefix' });
            } else if (langData.value === sourceData.value && !isFormatOnlyString(sourceData.value) && !isCognateOrInternationalTerm(sourceData.value)) {
                result.untranslated.push({ key, value: langData.value, reason: 'exact match (not cognate)' });
            } else if (format === 'elements' && langData.hash && langData.hash !== sourceHash) {
                result.stale.push({ key, value: langData.value, oldHash: langData.hash, newHash: sourceHash, enValue: sourceData.value });
            } else {
                result.translated.push({ key, value: langData.value });
            }

            // Validation checks (skip untranslated [EN] prefix entries)
            if (!langData.value.startsWith(CONFIG.untranslatedPrefix)) {
                if (langData.value === '' || langData.value === null || langData.value === undefined) {
                    result.emptyValues.push({ key });
                }
                if (langData.value && langData.value !== langData.value.trim()) {
                    result.whitespaceIssues.push({ key, value: langData.value });
                }
                const formatIssue = checkFormatSpecifiers(sourceData.value, langData.value, key);
                if (formatIssue) {
                    result.formatErrors.push(formatIssue);
                }
            }
        }
    }

    // Orphaned keys (in target but NOT in source)
    for (const langKey of langOrderedKeys) {
        if (!sourceEntries.has(langKey)) {
            result.orphaned.push(langKey);
        }
    }

    return result;
}

// --- CODEBASE SCANNER

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

function getModDir() {
    return path.resolve(__dirname, '..');
}

let _codebaseScanCache = null;

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

function scanCodebaseForUsedKeys(modDir, allEnglishKeys) {
    const usedKeys = new Set();
    const dynamicPrefixes = new Set();

    const srcDir = path.join(modDir, 'src');
    const guiDir = path.join(modDir, 'gui');
    const modDescPath = path.join(modDir, 'modDesc.xml');
    const vehiclesDir = path.join(modDir, 'vehicles');

    // Scan Lua files
    const luaDirs = [srcDir, vehiclesDir];
    for (const dir of luaDirs) {
        const luaFiles = getFilesRecursive(dir, ['.lua']);
        for (const luaFile of luaFiles) {
            const content = fs.readFileSync(luaFile, 'utf8');

            const getTextPattern = /getText\("([^"]+)"\)/g;
            let match;
            while ((match = getTextPattern.exec(content)) !== null) {
                usedKeys.add(match[1]);
            }

            const stringPattern = /"(usedplus_[a-zA-Z0-9_]+|usedPlus_[a-zA-Z0-9_]+)"/g;
            while ((match = stringPattern.exec(content)) !== null) {
                usedKeys.add(match[1]);
            }

            const dynamicPattern = /"(usedplus_[a-z_]+_|usedPlus_[a-z_]+_)"\s*\.\./g;
            while ((match = dynamicPattern.exec(content)) !== null) {
                dynamicPrefixes.add(match[1]);
            }
        }
    }

    // Scan XML files
    const xmlFiles = getFilesRecursive(guiDir, ['.xml']);
    for (const xmlFile of xmlFiles) {
        const content = fs.readFileSync(xmlFile, 'utf8');
        const l10nPattern = /\$l10n_([a-zA-Z0-9_]+)/g;
        let match;
        while ((match = l10nPattern.exec(content)) !== null) {
            usedKeys.add(match[1]);
        }
    }

    // Scan modDesc.xml
    if (fs.existsSync(modDescPath)) {
        const content = fs.readFileSync(modDescPath, 'utf8');
        const l10nPattern = /\$l10n_([a-zA-Z0-9_]+)/g;
        let match;
        while ((match = l10nPattern.exec(content)) !== null) {
            usedKeys.add(match[1]);
        }
    }

    // Whitelist dynamic prefix keys
    for (const prefix of dynamicPrefixes) {
        for (const key of allEnglishKeys) {
            if (key.startsWith(prefix)) {
                usedKeys.add(key);
            }
        }
    }

    // Game-engine auto-mapped keys
    const gameEnginePrefixes = ['input_', 'fillType_', 'configuration_', 'unit_'];
    for (const key of allEnglishKeys) {
        if (gameEnginePrefixes.some(p => key.startsWith(p))) {
            usedKeys.add(key);
        }
    }

    return { usedKeys, dynamicPrefixes };
}

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

// --- STORE INIT — Single entry point for all commands

/**
 * Initialize the shared store used by all commands.
 * Returns { filePrefix, format, sourceFile, sourceEntries, sourceOrderedKeys,
 *           sourceHashes, gate, enabledLangs }
 */
function initStore() {
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

    const { entries: sourceEntries, orderedKeys: sourceOrderedKeys } = parseTranslationFile(sourceFile, format);

    const sourceHashes = new Map();
    for (const [key, data] of sourceEntries) {
        sourceHashes.set(key, getHash(data.value));
    }

    const gate = gateCodebaseValidation(sourceEntries);
    const enabledLangs = getEnabledLanguages();

    return { filePrefix, format, sourceFile, sourceEntries, sourceOrderedKeys, sourceHashes, gate, enabledLangs };
}

// --- MUTATION ENGINE — Atomic file operations

/**
 * Add an entry to a file's content at the correct position.
 * Returns the modified content string.
 */
function addEntryToContent(content, key, value, hash, format, enOrderedKeys, langKeySet, tag) {
    const newEntry = `\n        ${formatEntry(key, value, hash, format, tag)}`;
    const insertPos = findInsertPosition(content, key, enOrderedKeys, langKeySet, format);

    if (insertPos !== -1) {
        return content.substring(0, insertPos) + newEntry + content.substring(insertPos);
    }
    return content;
}

/**
 * Update an existing entry's value and/or hash in file content.
 * Returns the modified content string.
 */
function updateEntryInContent(content, key, newValue, newHash, format) {
    if (format === 'elements') {
        const pattern = new RegExp(
            `<e k="${escapeRegex(key)}" v="([^"]*)"([^>]*)\\s*/>`,
            'g'
        );
        return content.replace(pattern, (match, oldValue, attrs) => {
            const cleanAttrs = attrs.replace(/\s*eh="[^"]*"/g, '');
            const tagMatch = cleanAttrs.match(/tag="([^"]*)"/);
            const tagAttr = tagMatch ? ` tag="${tagMatch[1]}"` : '';
            const val = newValue !== null ? escapeXml(newValue) : oldValue;
            return `<e k="${key}" v="${val}" eh="${newHash}"${tagAttr} />`;
        });
    } else {
        const pattern = new RegExp(
            `<text name="${escapeRegex(key)}" text="([^"]*)"\\s*/>`,
            'g'
        );
        return content.replace(pattern, (match, oldValue) => {
            const val = newValue !== null ? escapeXml(newValue) : oldValue;
            return `<text name="${key}" text="${val}"/>`;
        });
    }
}

/**
 * Remove an entry from file content.
 * Returns the modified content string.
 */
function removeEntryFromContent(content, key, format) {
    let pattern;
    if (format === 'elements') {
        pattern = new RegExp(`\\s*<e k="${escapeRegex(key)}" v="[^"]*"[^>]*/>\\s*\\n?`, 'g');
    } else {
        pattern = new RegExp(`\\s*<text name="${escapeRegex(key)}" text="[^"]*"\\s*/>\\s*\\n?`, 'g');
    }
    return content.replace(pattern, '\n');
}

/**
 * Rename a key in file content (preserves value and hash).
 * Returns the modified content string.
 */
function renameKeyInContent(content, oldKey, newKey, format) {
    if (format === 'elements') {
        const pattern = new RegExp(
            `<e k="${escapeRegex(oldKey)}" v="([^"]*)"([^>]*)\\s*/>`,
            'g'
        );
        return content.replace(pattern, (match, value, attrs) => {
            return `<e k="${newKey}" v="${value}"${attrs} />`;
        });
    } else {
        const pattern = new RegExp(
            `<text name="${escapeRegex(oldKey)}" text="([^"]*)"\\s*/>`,
            'g'
        );
        return content.replace(pattern, (match, value) => {
            return `<text name="${newKey}" text="${value}"/>`;
        });
    }
}

/**
 * Atomic write: content → .tmp file → rename to real file.
 * Returns true on success.
 */
function atomicWrite(filePath, content) {
    const tmpPath = filePath + '.tmp';
    try {
        fs.writeFileSync(tmpPath, content, 'utf8');
        fs.renameSync(tmpPath, filePath);
        return true;
    } catch (err) {
        // Cleanup tmp on failure
        try { fs.unlinkSync(tmpPath); } catch (_) {}
        throw err;
    }
}

/**
 * Get all translation file paths (English + all languages).
 */
function getAllFilePaths(filePrefix, enabledLangs) {
    const paths = [getSourceFilePath(filePrefix)];
    for (const { code } of enabledLangs) {
        const langFile = getLangFilePath(filePrefix, code);
        if (fs.existsSync(langFile)) {
            paths.push(langFile);
        }
    }
    return paths;
}

// --- JSON TRANSLATION PROTOCOL

const SCHEMA_TRANSLATE = 'rosetta-translate-v1';
const SCHEMA_IMPORT = 'rosetta-import-v1';

function getKeySection(key) {
    const prefixes = [
        ['finance', 'Finance'], ['lease', 'Lease'], ['search', 'Search'], ['detail', 'Detail'],
        ['button', 'Buttons'], ['notify', 'Notifications'], ['notification', 'Notifications'],
        ['error', 'Errors'], ['settings', 'Settings'], ['credit', 'Credit'], ['marketplace', 'Marketplace'],
        ['repair', 'Repair'], ['workshop', 'Workshop'], ['fsk', 'Field Service Kit'], ['sp', 'Salesperson'],
        ['whisper', 'Whisper'], ['inGameMenu', 'Menu'], ['component', 'Components'],
        ['fluid', 'Fluids'], ['land', 'Land'], ['loan', 'Loans'],
    ];
    for (const [p, s] of prefixes) {
        if (key.startsWith('usedplus_' + p) || key.startsWith('usedPlus_' + p)) return s;
    }
    return 'General';
}

/**
 * Export entries for translation as JSON.
 * Includes context (nearby translated keys, format specifiers, section).
 */
function exportForTranslation(langCode, sourceEntries, sourceHashes, langEntries, langOrderedKeys, format, includeStale) {
    const langName = LANGUAGE_NAMES[langCode] || langCode.toUpperCase();
    const classification = classifyEntries(sourceEntries, sourceHashes, langEntries, langOrderedKeys, format);

    let entriesToExport = classification.untranslated.concat(classification.missing);
    if (includeStale) {
        entriesToExport = entriesToExport.concat(classification.stale);
    }

    if (entriesToExport.length === 0) {
        return null;
    }

    const sourceKeys = [...sourceEntries.keys()];
    const translatedSet = new Set(classification.translated.map(e => e.key));

    const entries = entriesToExport.map(entry => {
        const key = entry.key;
        const sourceData = sourceEntries.get(key);
        const sourceValue = sourceData ? sourceData.value : entry.enValue;
        const sourceHash = sourceHashes.get(key);
        const langData = langEntries ? langEntries.get(key) : null;
        const formatSpecs = extractFormatSpecifiers(sourceValue);
        const keyIndex = sourceKeys.indexOf(key);

        // Find up to 3 nearby translated keys for context
        const nearbyKeys = [];
        for (let i = Math.max(0, keyIndex - 5); i < Math.min(sourceKeys.length, keyIndex + 6) && nearbyKeys.length < 3; i++) {
            const nk = sourceKeys[i];
            if (nk !== key && translatedSet.has(nk) && langEntries && langEntries.has(nk)) {
                nearbyKeys.push({ key: nk, source: sourceEntries.get(nk).value, translated: langEntries.get(nk).value });
            }
        }

        const status = entry.reason ? 'untranslated' : (entry.enValue && !entry.value ? 'missing' : (entry.oldHash ? 'stale' : 'untranslated'));
        const ctx = { section: getKeySection(key) };
        if (formatSpecs.length > 0) ctx.formatSpecifiers = formatSpecs;
        if (nearbyKeys.length > 0) ctx.nearbyKeys = nearbyKeys;

        return { key, source: sourceValue, sourceHash, currentTranslation: langData ? langData.value : null, status, context: ctx };
    });

    return {
        $schema: SCHEMA_TRANSLATE,
        meta: {
            sourceLanguage: CONFIG.sourceLanguage,
            targetLanguage: langCode,
            targetName: langName,
            exportedAt: new Date().toISOString(),
            entryCount: entries.length,
        },
        instructions: {
            formatSpecifiers: "Preserve format specifiers EXACTLY as they appear in the source: %s, %d, %.1f, %.2f, etc. The count, type, and order must match. Lua format specifiers are positional.",
            tone: "Farming simulation context. Use natural, professional language appropriate for a game UI. Keep translations concise.",
            xmlEntities: "If the source contains &#10; (XML newline), preserve it as &#10; in the translation. Do NOT convert to \\n.",
        },
        entries,
    };
}

function validateAndImport(importData, sourceEntries, sourceHashes) {
    const result = { accepted: [], rejected: [], warnings: [] };
    const reject = (key, reason) => result.rejected.push({ key, reason });

    if (!importData?.$schema) { reject('*', 'Invalid JSON: missing $schema'); return result; }
    if (importData.$schema !== SCHEMA_IMPORT) { reject('*', `Unknown schema: ${importData.$schema}`); return result; }
    if (!importData.meta?.targetLanguage) { reject('*', 'Missing meta.targetLanguage'); return result; }
    if (!Array.isArray(importData.translations)) { reject('*', 'Missing translations array'); return result; }

    for (const entry of importData.translations) {
        const k = entry?.key;
        if (!k || typeof k !== 'string') { reject(k || '?', 'Invalid key'); continue; }
        if (!entry.translation || typeof entry.translation !== 'string' || !entry.translation.trim()) {
            reject(k, 'Empty or missing translation'); continue;
        }
        if (!sourceEntries.has(k)) { reject(k, 'Key not in English source'); continue; }

        const sourceHash = sourceHashes.get(k);
        const fmtIssue = checkFormatSpecifiers(sourceEntries.get(k).value, entry.translation, k);
        if (fmtIssue) { reject(k, `Format error: ${fmtIssue.message}`); continue; }

        if (entry.sourceHash && entry.sourceHash !== sourceHash) {
            result.warnings.push({ key: k, warning: 'English changed after export' });
        }
        if (entry.translation !== entry.translation.trim()) {
            result.warnings.push({ key: k, warning: 'Has leading/trailing whitespace' });
        }
        result.accepted.push({ key: k, translation: entry.translation, sourceHash });
    }
    return result;
}

// --- READ-ONLY COMMANDS: status, report, check, validate, unused

// --- Shared table formatter ---
function padRight(str, len) {
    return (str + '').length >= len ? (str + '') : (str + '').padEnd(len);
}

function padLeft(str, len) {
    return String(str).padStart(len);
}

function printCheckSummaryTable(summary) {
    console.log("Language            | Total  | Missing | Stale | Untranslated | Duplicates | Orphaned");
    console.log("-----------------------------------------------------------------------------------------------");
    for (const s of summary) {
        const flag = (s.missing > 0 || s.duplicates > 0 || s.orphaned > 0) ? '!!' : '  ';
        const tot = s.missing === -1 ? '  N/A' : padLeft(s.total, 6);
        const mis = s.missing === -1 ? '  N/A' : padLeft(s.missing, 7);
        console.log(`${flag}${padRight(s.name, 18)} | ${tot} | ${mis} | ${padLeft(s.stale, 5)} | ${padLeft(s.untranslated, 12)} | ${padLeft(s.duplicates, 10)} | ${padLeft(s.orphaned, 8)}`);
    }
    console.log("-----------------------------------------------------------------------------------------------");
}

// --- STATUS ---
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
        const cls = classifyEntries(store.sourceEntries, store.sourceHashes, langEntries, langKeys, store.format);

        const duplicates = langDuplicates ? langDuplicates.length : 0;
        const fmtStr = cls.formatErrors.length > 0 ? ` !${cls.formatErrors.length}` : '';

        console.log(`${padRight(langName, 20)}| ${padLeft(cls.translated.length, 10)} | ${padLeft(cls.stale.length, 7)} | ${padLeft(cls.untranslated.length, 12)} | ${padLeft(cls.missing.length, 7)} | ${padLeft(duplicates, 4)} | ${padLeft(cls.orphaned.length, 8)}${fmtStr}`);
    }

    console.log("-----------------------------------------------------------------------------------------------");
    console.log("! = Format specifier errors (CRITICAL - will crash game!)");
}

// --- REPORT ---
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
        const cls = classifyEntries(store.sourceEntries, store.sourceHashes, langEntries, langKeys, store.format);
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

        if (cls.formatErrors.length > 0) {
            console.log(`  Format Errors: ${cls.formatErrors.length} (CRITICAL)`);
        }

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

        console.log();
    }

    // UNUSED section (global)
    if (store.gate.unusedKeys.length > 0) {
        console.log(`======================================================================`);
        console.log(`UNUSED KEYS (${store.gate.unusedKeys.length} keys not referenced in codebase)`);
        console.log(`======================================================================`);
        for (const key of store.gate.unusedKeys.slice(0, 20)) {
            console.log(`    - ${key}`);
        }
        if (store.gate.unusedKeys.length > 20) {
            console.log(`    ... and ${store.gate.unusedKeys.length - 20} more (run 'unused' command for full list)`);
        }
        console.log();
    }
}

// --- CHECK ---
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
        const cls = classifyEntries(store.sourceEntries, store.sourceHashes, langEntries, langKeys, store.format);
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
            name: langName,
            total: langEntries.size,
            missing: cls.missing.length,
            stale: cls.stale.length,
            untranslated: cls.untranslated.length,
            duplicates,
            orphaned: cls.orphaned.length
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

// --- VALIDATE ---
function cmdValidate() {
    const store = initStore();

    let hasProblems = false;
    let formatErrorCount = 0;

    for (const { code: langCode } of store.enabledLangs) {
        const langFile = getLangFilePath(store.filePrefix, langCode);
        if (!fs.existsSync(langFile)) {
            hasProblems = true;
            break;
        }

        const { entries: langEntries, orderedKeys: langKeys } = parseTranslationFile(langFile, store.format);

        for (const [key] of store.sourceEntries) {
            if (!langEntries.has(key)) {
                hasProblems = true;
                break;
            }
        }

        // Also check format specifiers
        const cls = classifyEntries(store.sourceEntries, store.sourceHashes, langEntries, langKeys, store.format);
        formatErrorCount += cls.formatErrors.length;

        if (hasProblems) break;
    }

    if (formatErrorCount > 0) {
        console.log(`FAIL: ${formatErrorCount} format specifier error(s) detected`);
        process.exit(1);
    } else if (hasProblems) {
        console.log("FAIL: Translation files out of sync");
        process.exit(1);
    } else {
        console.log("OK: All translation files have required keys");
        process.exit(0);
    }
}

// --- UNUSED ---
function cmdUnused() {
    const store = initStore();

    console.log("======================================================================");
    console.log(`ROSETTA UNUSED KEYS v${VERSION}`);
    console.log("======================================================================");
    console.log();
    printGateSummary(store.gate, store.sourceEntries.size);

    if (store.gate.unusedKeys.length === 0) {
        console.log("All keys are referenced in the codebase. Nothing to clean up!");
        return;
    }

    // Group by prefix
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
        for (const key of keys) {
            console.log(`    - ${key}`);
        }
        console.log();
    }

    console.log("======================================================================");
    console.log("To remove these keys, run:");
    console.log("  node rosetta.js remove --all-unused");
    console.log("Or remove specific keys:");
    console.log("  node rosetta.js remove key1 key2 key3");
    console.log("======================================================================");
}

// --- MUTATING COMMANDS: sync, deposit, amend, rename, remove, import, doctor

// --- SYNC ---
function cmdSync() {
    const dryRun = process.argv.includes('--dry-run');

    console.log("======================================================================");
    console.log(`ROSETTA SYNC v${VERSION}${dryRun ? ' (DRY RUN)' : ''}`);
    console.log("======================================================================");
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
    if (!format) {
        console.error("ERROR: Could not detect XML format.");
        process.exit(1);
    }

    // Step 1: Update hashes in English source
    console.log(`[1/4] Updating hashes in source file...`);
    if (format === 'elements' && !dryRun) {
        const hashesUpdated = updateSourceHashes(sourceFile, format);
        if (hashesUpdated > 0) {
            console.log(`      Updated ${hashesUpdated} hash(es) in ${sourceFile}`);
        } else {
            console.log(`      All hashes current in ${sourceFile}`);
        }
    } else if (format === 'elements') {
        // Dry run: count how many would change
        const { entries } = parseTranslationFile(sourceFile, format);
        let wouldUpdate = 0;
        for (const [key, data] of entries) {
            if (data.hash !== getHash(data.value)) wouldUpdate++;
        }
        console.log(`      Would update ${wouldUpdate} hash(es) in ${sourceFile}`);
    } else {
        console.log(`      Skipped (hash embedding only for 'elements' format)`);
    }

    // Re-parse source after hash update
    const { entries: sourceEntries, orderedKeys: sourceOrderedKeys } = parseTranslationFile(sourceFile, format);

    const sourceHashes = new Map();
    for (const [key, data] of sourceEntries) {
        sourceHashes.set(key, getHash(data.value));
    }

    // Step 2: Codebase gate
    const gate = gateCodebaseValidation(sourceEntries);

    console.log();
    console.log(`[2/4] Source: ${sourceFile} (${sourceEntries.size} keys)`);
    console.log(`      Format: ${format}`);
    console.log();
    console.log(`[3/4] Codebase validation...`);
    printGateSummary(gate, sourceEntries.size);

    // Step 3: Sync to all target languages
    console.log(`[4/4] Syncing to target languages (${gate.activeKeyCount} active keys)...`);
    console.log();

    const enabledLangs = getEnabledLanguages();

    for (const { code: langCode, name: langName } of enabledLangs) {
        const langFile = getLangFilePath(filePrefix, langCode);

        if (!fs.existsSync(langFile)) {
            console.log(`  ${padRight(langName, 18)}: FILE NOT FOUND - skipping`);
            continue;
        }

        let { entries: langEntries, orderedKeys: langKeys, duplicates: langDuplicates, rawContent: content } = parseTranslationFile(langFile, format);
        const langKeySet = new Set(langKeys);
        const cls = classifyEntries(sourceEntries, sourceHashes, langEntries, langKeys, format);

        let added = 0;

        // Add missing keys
        for (const { key, enValue } of cls.missing) {
            const sourceHash = sourceHashes.get(key);
            const placeholderValue = CONFIG.untranslatedPrefix + enValue;
            content = addEntryToContent(content, key, placeholderValue, sourceHash, format, sourceOrderedKeys, langKeySet);
            langKeySet.add(key);
            added++;
        }

        // Update hashes for non-stale, existing entries
        if (format === 'elements') {
            const missingKeySet = new Set(cls.missing.map(m => m.key));
            const staleKeySet = new Set(cls.stale.map(s => s.key));

            for (const [key] of sourceEntries) {
                if (!langEntries.has(key) || missingKeySet.has(key)) continue;

                const sourceHash = sourceHashes.get(key);
                const langData = langEntries.get(key);
                const hasNoHash = !langData.hash;
                const isUntranslated = langData.value.startsWith(CONFIG.untranslatedPrefix);

                // Update stale [EN] placeholders to current English text
                if (isUntranslated && staleKeySet.has(key)) {
                    // This is an untranslated entry whose English source changed.
                    // The stale classification wouldn't have caught this since untranslated
                    // entries skip stale check, but we should still update the placeholder.
                    const sourceData = sourceEntries.get(key);
                    const newPlaceholder = CONFIG.untranslatedPrefix + sourceData.value;
                    content = updateEntryInContent(content, key, newPlaceholder, sourceHash, format);
                    continue;
                }

                const shouldAddHash = !staleKeySet.has(key) || (hasNoHash && !isUntranslated);

                if (shouldAddHash) {
                    content = updateEntryInContent(content, key, null, sourceHash, format);
                }
            }
        }

        if (!dryRun) {
            atomicWrite(langFile, content);
        }

        // Report
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
 * Update source hashes (ported from translation_sync.js).
 */
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

// --- DEPOSIT ---
function cmdDeposit() {
    const dryRun = process.argv.includes('--dry-run');
    const args = process.argv.slice(3).filter(a => !a.startsWith('--'));
    const fileFlag = process.argv.indexOf('--file');

    let keysToDeposit = []; // Array of { key, value }

    if (fileFlag !== -1 && process.argv[fileFlag + 1]) {
        // Bulk deposit from JSON file
        const jsonPath = process.argv[fileFlag + 1];
        if (!fs.existsSync(jsonPath)) {
            console.error(`ERROR: File not found: ${jsonPath}`);
            process.exit(1);
        }
        try {
            const data = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
            if (Array.isArray(data)) {
                keysToDeposit = data.map(item => ({ key: item.key, value: item.value }));
            } else if (typeof data === 'object') {
                keysToDeposit = Object.entries(data).map(([key, value]) => ({ key, value }));
            }
        } catch (err) {
            console.error(`ERROR: Failed to parse JSON file: ${err.message}`);
            process.exit(1);
        }
    } else if (args.length >= 2) {
        // Single key deposit: deposit KEY VALUE
        keysToDeposit = [{ key: args[0], value: args.slice(1).join(' ') }];
    } else {
        console.error("Usage: rosetta.js deposit KEY VALUE  OR  rosetta.js deposit --file keys.json");
        process.exit(1);
    }

    const store = initStore();

    console.log("======================================================================");
    console.log(`ROSETTA DEPOSIT v${VERSION}${dryRun ? ' (DRY RUN)' : ''}`);
    console.log("======================================================================");
    console.log();

    // Validate keys
    const valid = [];
    const skipped = [];

    for (const { key, value } of keysToDeposit) {
        if (!key || !value) {
            skipped.push({ key: key || '(empty)', reason: 'missing key or value' });
            continue;
        }
        if (store.sourceEntries.has(key)) {
            skipped.push({ key, reason: 'already exists in English source' });
            continue;
        }
        valid.push({ key, value });
    }

    if (skipped.length > 0) {
        console.log(`Skipped ${skipped.length} key(s):`);
        for (const { key, reason } of skipped) {
            console.log(`  ? ${key}: ${reason}`);
        }
        console.log();
    }

    if (valid.length === 0) {
        console.log("No new keys to deposit.");
        return;
    }

    console.log(`Depositing ${valid.length} key(s) across ${store.enabledLangs.length + 1} files...`);
    console.log();

    // Step 1: Add to English source
    let sourceContent = fs.readFileSync(store.sourceFile, 'utf8');
    const sourceKeySet = new Set(store.sourceOrderedKeys);

    for (const { key, value } of valid) {
        const hash = getHash(value);
        sourceContent = addEntryToContent(sourceContent, key, value, hash, store.format, store.sourceOrderedKeys, sourceKeySet);
        sourceKeySet.add(key);
        // Also add to ordered keys for subsequent insertions
        store.sourceOrderedKeys.push(key);
    }

    if (!dryRun) {
        atomicWrite(store.sourceFile, sourceContent);
    }
    console.log(`  ${padRight(path.basename(store.sourceFile), 25)}: +${valid.length} (English values)`);

    // Step 2: Add to all language files with [EN] prefix
    for (const { code: langCode, name: langName } of store.enabledLangs) {
        const langFile = getLangFilePath(store.filePrefix, langCode);
        if (!fs.existsSync(langFile)) continue;

        let content = fs.readFileSync(langFile, 'utf8');
        const { orderedKeys: langKeys } = parseTranslationFile(langFile, store.format);
        const langKeySet = new Set(langKeys);

        for (const { key, value } of valid) {
            const hash = getHash(value);
            const placeholderValue = CONFIG.untranslatedPrefix + value;
            content = addEntryToContent(content, key, placeholderValue, hash, store.format, store.sourceOrderedKeys, langKeySet);
            langKeySet.add(key);
        }

        if (!dryRun) {
            atomicWrite(langFile, content);
        }
        console.log(`  ${padRight(path.basename(langFile), 25)}: +${valid.length} ([EN] placeholders)`);
    }

    console.log();
    console.log("======================================================================");
    console.log(`DEPOSIT COMPLETE: ${valid.length} key(s) added across ${store.enabledLangs.length + 1} files`);
    console.log("======================================================================");
}

// --- AMEND ---
function cmdAmend() {
    const dryRun = process.argv.includes('--dry-run');
    const args = process.argv.slice(3).filter(a => !a.startsWith('--'));

    if (args.length < 2) {
        console.error("Usage: node rosetta.js amend KEY NEW_VALUE");
        process.exit(1);
    }

    const key = args[0];
    const newValue = args.slice(1).join(' ');
    const store = initStore();

    if (!store.sourceEntries.has(key)) {
        console.error(`ERROR: Key '${key}' not found in English source.`);
        process.exit(1);
    }

    const oldValue = store.sourceEntries.get(key).value;
    const newHash = getHash(newValue);

    console.log("======================================================================");
    console.log(`ROSETTA AMEND v${VERSION}${dryRun ? ' (DRY RUN)' : ''}`);
    console.log("======================================================================");
    console.log();
    console.log(`  Key:       ${key}`);
    console.log(`  Old value: ${oldValue}`);
    console.log(`  New value: ${newValue}`);
    console.log(`  New hash:  ${newHash}`);
    console.log();

    // Step 1: Update English source
    let sourceContent = fs.readFileSync(store.sourceFile, 'utf8');
    sourceContent = updateEntryInContent(sourceContent, key, newValue, newHash, store.format);

    if (!dryRun) {
        atomicWrite(store.sourceFile, sourceContent);
    }
    console.log(`  ${padRight(path.basename(store.sourceFile), 25)}: value + hash updated`);

    // Step 2: All language files keep their old hash (mismatch = stale)
    // Nothing to do — the old hash stays, creating a stale signal automatically.
    console.log(`  All ${store.enabledLangs.length} language files: hash mismatch will mark as stale`);

    console.log();
    console.log("======================================================================");
    console.log("AMEND COMPLETE");
    console.log("  Run 'rosetta.js status' to see stale entries.");
    console.log("  Run 'rosetta.js translate LANG --stale' to export for re-translation.");
    console.log("======================================================================");
}

// --- RENAME ---
function cmdRename() {
    const dryRun = process.argv.includes('--dry-run');
    const args = process.argv.slice(3).filter(a => !a.startsWith('--'));

    if (args.length !== 2) {
        console.error("Usage: node rosetta.js rename OLD_KEY NEW_KEY");
        process.exit(1);
    }

    const [oldKey, newKey] = args;
    const store = initStore();

    if (!store.sourceEntries.has(oldKey)) {
        console.error(`ERROR: Key '${oldKey}' not found in English source.`);
        process.exit(1);
    }

    if (store.sourceEntries.has(newKey)) {
        console.error(`ERROR: Key '${newKey}' already exists in English source.`);
        process.exit(1);
    }

    console.log("======================================================================");
    console.log(`ROSETTA RENAME v${VERSION}${dryRun ? ' (DRY RUN)' : ''}`);
    console.log("======================================================================");
    console.log();
    console.log(`  Renaming: ${oldKey} -> ${newKey}`);
    console.log();

    const allFiles = getAllFilePaths(store.filePrefix, store.enabledLangs);
    let filesModified = 0;

    for (const filePath of allFiles) {
        let content = fs.readFileSync(filePath, 'utf8');
        const newContent = renameKeyInContent(content, oldKey, newKey, store.format);

        if (newContent !== content) {
            if (!dryRun) {
                atomicWrite(filePath, newContent);
            }
            filesModified++;
            console.log(`  ${padRight(path.basename(filePath), 25)}: renamed`);
        } else {
            console.log(`  ${padRight(path.basename(filePath), 25)}: key not found`);
        }
    }

    console.log();
    console.log("======================================================================");
    console.log(`RENAME COMPLETE: ${filesModified} file(s) updated`);
    console.log("  Translations and hashes have been preserved.");
    console.log("======================================================================");
}

// --- REMOVE (replaces prune) ---
function cmdRemove() {
    const dryRun = process.argv.includes('--dry-run');
    const store = initStore();

    console.log("======================================================================");
    console.log(`ROSETTA REMOVE v${VERSION}${dryRun ? ' (DRY RUN)' : ''}`);
    console.log("======================================================================");
    console.log();

    // Determine which keys to remove
    const args = process.argv.slice(3).filter(a => !a.startsWith('--'));
    let keysToRemove = [];

    if (process.argv.includes('--all-unused')) {
        printGateSummary(store.gate, store.sourceEntries.size);
        keysToRemove = store.gate.unusedKeys;
    } else if (args.length > 0) {
        keysToRemove = args;
    } else {
        console.error("Usage:");
        console.error("  node rosetta.js remove KEY1 KEY2 KEY3");
        console.error("  node rosetta.js remove --all-unused");
        process.exit(1);
    }

    if (keysToRemove.length === 0) {
        console.log("No keys to remove.");
        return;
    }

    // Validate keys exist
    const validKeys = [];
    const invalidKeys = [];
    for (const key of keysToRemove) {
        if (store.sourceEntries.has(key)) {
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
        if (invalidKeys.length > 10) console.log(`  ... and ${invalidKeys.length - 10} more`);
        console.log();
    }

    if (validKeys.length === 0) {
        console.log("No valid keys to remove.");
        return;
    }

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
            if (!dryRun) {
                atomicWrite(filePath, content);
            }
        }

        const fileName = path.basename(filePath);
        if (removedFromFile > 0) {
            console.log(`  ${padRight(fileName, 25)}: removed ${removedFromFile} key(s)`);
            totalRemoved += removedFromFile;
        } else {
            console.log(`  ${padRight(fileName, 25)}: no matches`);
        }
    }

    console.log();
    console.log("======================================================================");
    console.log(`REMOVE COMPLETE: ${totalRemoved} entries across ${allFiles.length} files`);
    console.log("======================================================================");
}

// --- TRANSLATE (JSON export) ---
function cmdTranslate() {
    const args = process.argv.slice(3).filter(a => !a.startsWith('--'));
    const includeStale = process.argv.includes('--stale');

    if (args.length === 0) { console.error("Usage: rosetta.js translate LANG [--stale]"); process.exit(1); }

    const langCode = args[0].toLowerCase();
    const store = initStore();
    const langMatch = store.enabledLangs.find(l => l.code === langCode);
    if (!langMatch) { console.error(`Language '${langCode}' not found.`); process.exit(1); }

    const langFile = getLangFilePath(store.filePrefix, langCode);
    if (!fs.existsSync(langFile)) { console.error(`File not found: ${langFile}`); process.exit(1); }

    const { entries: langEntries, orderedKeys: langKeys } = parseTranslationFile(langFile, store.format);
    const exportData = exportForTranslation(langCode, store.sourceEntries, store.sourceHashes, langEntries, langKeys, store.format, includeStale);

    if (!exportData) { console.log(`Nothing to translate for ${langMatch.name}.`); return; }

    const outputFile = `${langCode}_translate.json`;
    fs.writeFileSync(outputFile, JSON.stringify(exportData, null, 2), 'utf8');
    console.log(`Exported ${exportData.entries.length} entries to ${outputFile} (${langMatch.name})`);
    console.log(`Import after translation: rosetta.js import ${langCode}_translated.json`);
}

// --- IMPORT (JSON import) ---
function cmdImport() {
    const dryRun = process.argv.includes('--dry-run');
    const args = process.argv.slice(3).filter(a => !a.startsWith('--'));
    if (args.length === 0) { console.error("Usage: rosetta.js import FILE.json [--dry-run]"); process.exit(1); }

    const jsonPath = args[0];
    if (!fs.existsSync(jsonPath)) { console.error(`File not found: ${jsonPath}`); process.exit(1); }

    let importData;
    try { importData = JSON.parse(fs.readFileSync(jsonPath, 'utf8')); }
    catch (err) { console.error(`Invalid JSON: ${err.message}`); process.exit(1); }

    const store = initStore();
    const v = validateAndImport(importData, store.sourceEntries, store.sourceHashes);

    console.log("======================================================================");
    console.log(`ROSETTA IMPORT v${VERSION}${dryRun ? ' (DRY RUN)' : ''}`);
    console.log("======================================================================");

    if (v.rejected.length > 0 && v.accepted.length === 0) {
        console.log(`ALL REJECTED (${v.rejected.length}):`);
        for (const { key, reason } of v.rejected.slice(0, 20)) console.log(`  X ${key}: ${reason}`);
        process.exit(1);
    }

    const langCode = importData.meta.targetLanguage;
    const langFile = getLangFilePath(store.filePrefix, langCode);
    if (!fs.existsSync(langFile)) { console.error(`Target file not found: ${langFile}`); process.exit(1); }

    const langName = LANGUAGE_NAMES[langCode] || langCode.toUpperCase();
    console.log(`\nImporting ${v.accepted.length} translations for ${langName}`);

    if (v.rejected.length > 0) {
        console.log(`\nRejected (${v.rejected.length}):`);
        for (const { key, reason } of v.rejected) console.log(`  X ${key}: ${reason}`);
    }
    if (v.warnings.length > 0) {
        console.log(`\nWarnings (${v.warnings.length}):`);
        for (const { key, warning } of v.warnings.slice(0, 10)) console.log(`  ~ ${key}: ${warning}`);
        if (v.warnings.length > 10) console.log(`  ... and ${v.warnings.length - 10} more`);
    }

    let content = fs.readFileSync(langFile, 'utf8');
    for (const { key, translation, sourceHash } of v.accepted) {
        content = updateEntryInContent(content, key, translation, sourceHash, store.format);
    }
    if (!dryRun && v.accepted.length > 0) atomicWrite(langFile, content);

    console.log(`\nApplied: ${v.accepted.length} | Rejected: ${v.rejected.length} | Warnings: ${v.warnings.length}`);
    console.log("======================================================================");
}

// --- DOCTOR ---
function cmdDoctor() {
    const doFix = process.argv.includes('--fix');
    const store = initStore();

    console.log("======================================================================");
    console.log(`ROSETTA DOCTOR v${VERSION}${doFix ? ' (AUTO-FIX MODE)' : ''}`);
    console.log("======================================================================");
    console.log();

    const issues = [];
    let totalFormatErrors = 0, totalEmpty = 0, totalOrphaned = 0, totalDuplicates = 0;

    // Single pass through all language files
    console.log("Scanning all language files...");
    for (const { code: langCode } of store.enabledLangs) {
        const langFile = getLangFilePath(store.filePrefix, langCode);
        if (!fs.existsSync(langFile)) continue;

        const { entries: langEntries, orderedKeys: langKeys, duplicates } = parseTranslationFile(langFile, store.format);
        const cls = classifyEntries(store.sourceEntries, store.sourceHashes, langEntries, langKeys, store.format);

        for (const err of cls.formatErrors) {
            issues.push({ severity: 'CRITICAL', category: 'format', lang: langCode, key: err.key, message: err.message });
        }
        totalFormatErrors += cls.formatErrors.length;

        for (const { key } of cls.emptyValues) {
            issues.push({ severity: 'WARNING', category: 'empty', lang: langCode, key, message: 'Empty translation value' });
        }
        totalEmpty += cls.emptyValues.length;

        for (const key of cls.orphaned) {
            issues.push({ severity: 'WARNING', category: 'orphan', lang: langCode, key, message: 'Key not in English source', fixable: true });
        }
        totalOrphaned += cls.orphaned.length;

        for (const key of duplicates) {
            issues.push({ severity: 'HIGH', category: 'duplicate', lang: langCode, key, message: 'Key appears multiple times' });
        }
        totalDuplicates += duplicates.length;
    }

    // English source duplicates
    const { duplicates: enDupes } = parseTranslationFile(store.sourceFile, store.format);
    for (const key of enDupes) {
        issues.push({ severity: 'CRITICAL', category: 'duplicate', lang: 'en', key, message: 'Duplicate in English source' });
        totalDuplicates++;
    }

    console.log(`  Format specifiers: ${totalFormatErrors === 0 ? 'OK' : `${totalFormatErrors} errors`}`);
    console.log(`  Empty values: ${totalEmpty === 0 ? 'OK' : `${totalEmpty} found`}`);
    console.log(`  Orphaned keys: ${totalOrphaned === 0 ? 'OK' : `${totalOrphaned} found`}`);
    console.log(`  Duplicate keys: ${totalDuplicates === 0 ? 'OK' : `${totalDuplicates} found`}`);

    // Reverse orphan detection
    console.log("Checking reverse orphans (code refs missing from English)...");
    const reverseOrphans = findReverseOrphans(getModDir(), store.sourceEntries);
    for (const { key, file } of reverseOrphans) {
        issues.push({ severity: 'HIGH', category: 'reverse-orphan', lang: '-', key, message: `Referenced in ${file} but missing from English` });
    }
    console.log(`  Reverse orphans: ${reverseOrphans.length === 0 ? 'OK' : `${reverseOrphans.length} found`}`);

    // Mixed prefix convention
    const mixedPrefix = [...store.sourceEntries.keys()].filter(k => k.startsWith('usedPlus_'));
    for (const key of mixedPrefix) {
        issues.push({ severity: 'LOW', category: 'convention', lang: 'en', key, message: 'Uses usedPlus_ instead of usedplus_' });
    }
    console.log(`  Naming convention: ${mixedPrefix.length === 0 ? 'OK' : `${mixedPrefix.length} mixed-case keys`}`);

    // XML structure integrity
    let structureIssues = 0;
    const allFiles = getAllFilePaths(store.filePrefix, store.enabledLangs);
    for (const filePath of allFiles) {
        const content = fs.readFileSync(filePath, 'utf8');
        if (!content.includes('<l10n>') || !content.includes('</l10n>')) {
            structureIssues++;
            issues.push({ severity: 'CRITICAL', category: 'structure', lang: path.basename(filePath), key: '-', message: 'Missing <l10n> root element' });
        }
        if (!content.includes('<elements>') || !content.includes('</elements>')) {
            structureIssues++;
            issues.push({ severity: 'CRITICAL', category: 'structure', lang: path.basename(filePath), key: '-', message: 'Missing <elements> container' });
        }
    }
    console.log(`  XML structure: ${structureIssues === 0 ? 'OK' : `${structureIssues} issues`}`);

    // Hash consistency
    let staleHashes = 0;
    for (const [key, data] of store.sourceEntries) {
        if (data.hash && data.hash !== getHash(data.value)) {
            staleHashes++;
            issues.push({ severity: 'WARNING', category: 'hash', lang: 'en', key, message: 'Hash does not match value (run sync)', fixable: true });
        }
    }
    console.log(`  Hash consistency: ${staleHashes === 0 ? 'OK' : `${staleHashes} stale hashes`}`);

    // Auto-fix
    if (doFix && issues.some(i => i.fixable)) {
        console.log("\nApplying auto-fixes...");
        let fixed = 0;

        if (staleHashes > 0) {
            const count = updateSourceHashes(store.sourceFile, store.format);
            console.log(`  Fixed ${count} stale English hashes`);
            fixed += count;
        }

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

    // Summary
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

        if (!doFix && issues.some(i => i.fixable)) {
            console.log("\n  Some issues are auto-fixable. Run: node rosetta.js doctor --fix");
        }
    }
    console.log("======================================================================");

    if (critical.length > 0) process.exit(1);
}

/**
 * Find translation keys referenced in code but missing from English XML.
 */
function findReverseOrphans(modDir, sourceEntries) {
    const reverseOrphans = [];
    const srcDir = path.join(modDir, 'src');
    const guiDir = path.join(modDir, 'gui');

    // Scan Lua for getText("usedplus_...") calls
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

    // Scan XML for $l10n_usedplus_ references
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

    // Deduplicate
    const seen = new Set();
    return reverseOrphans.filter(o => {
        const id = `${o.key}:${o.file}`;
        if (seen.has(id)) return false;
        seen.add(id);
        return true;
    });
}

// --- FORMAT COMMAND — Standardize all XML files

function cmdFormat() {
    const dryRun = process.argv.includes('--dry-run');
    const store = initStore();

    console.log("======================================================================");
    console.log(`ROSETTA FORMAT v${VERSION}${dryRun ? ' (DRY RUN)' : ''}`);
    console.log("======================================================================\n");

    const allFiles = [store.sourceFile, ...store.enabledLangs
        .map(l => getLangFilePath(store.filePrefix, l.code))
        .filter(f => fs.existsSync(f))];

    let totalReformatted = 0;

    for (const filePath of allFiles) {
        const parsed = parseTranslationFile(filePath, store.format);
        const content = fs.readFileSync(filePath, 'utf8');

        // Extract header: everything before <elements>
        const elementsStart = content.indexOf('<elements>');
        const elementsEnd = content.indexOf('</elements>');
        if (elementsStart === -1 || elementsEnd === -1) {
            console.log(`  ${padRight(path.basename(filePath), 25)}: SKIP (missing <elements>)`);
            continue;
        }

        const header = content.substring(0, elementsStart + '<elements>'.length);
        const footer = content.substring(elementsEnd);

        // Rebuild entries section with consistent 8-space indent, English key order
        const isSource = filePath === store.sourceFile;
        const referenceOrder = store.sourceOrderedKeys;
        const lines = [];

        // Format entry WITHOUT re-escaping (values from parser are already XML-encoded)
        const fmtRaw = (key, data) => {
            const hash = data.hash || getHash(data.value);
            const tagAttr = data.tag ? ` tag="${data.tag}"` : '';
            return store.format === 'elements'
                ? `        <e k="${key}" v="${data.value}" eh="${hash}"${tagAttr} />`
                : `        <text name="${key}" text="${data.value}"/>`;
        };

        // First: output entries in English key order
        const outputKeys = new Set();
        for (const key of referenceOrder) {
            if (parsed.entries.has(key)) {
                lines.push(fmtRaw(key, parsed.entries.get(key)));
                outputKeys.add(key);
            }
        }

        // Then: any remaining keys not in English order (orphans in target files)
        for (const key of parsed.orderedKeys) {
            if (!outputKeys.has(key)) {
                lines.push(fmtRaw(key, parsed.entries.get(key)));
            }
        }

        const newContent = header + '\n' + lines.join('\n') + '\n    ' + footer;
        const changed = newContent !== content;

        if (changed && !dryRun) {
            atomicWrite(filePath, newContent);
        }

        const label = changed ? 'reformatted' : 'already clean';
        console.log(`  ${padRight(path.basename(filePath), 25)}: ${label} (${parsed.entries.size} entries)`);
        if (changed) totalReformatted++;
    }

    console.log(`\nFORMAT COMPLETE: ${totalReformatted}/${allFiles.length} files ${dryRun ? 'would be ' : ''}reformatted`);
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
  deposit KEY VALUE       Add a key atomically across ALL files
  deposit --file F.json   Bulk add keys from JSON
  amend KEY NEW_VALUE     Change English text, mark translations stale
  rename OLD_KEY NEW_KEY  Rename across all files, preserve translations
  remove KEY [KEY...]     Delete key(s) from all files
  remove --all-unused     Delete all unused keys
  translate LANG [--stale]  Export JSON for AI translation
  import FILE.json        Import translated JSON with validation
  doctor [--fix]          Health check + auto-fix
  format                  Standardize XML indentation and key order
  prune                   Alias for 'remove' (deprecated)

FLAGS:  --dry-run  --help

JSON PROTOCOL:
  Export: rosetta.js translate de  ->  Import: rosetta.js import de_translated.json
  Format specifiers MUST match English (hard reject). Empty = rejected.

WORKFLOW:  deposit -> sync -> translate -> (AI/human) -> import -> status
`);
}

// --- Main CLI Router ---
const command = process.argv[2]?.toLowerCase();

// Change to script directory
process.chdir(__dirname);

const commands = {
    sync: cmdSync, status: cmdStatus, report: cmdReport, check: cmdCheck,
    validate: cmdValidate, unused: cmdUnused, deposit: cmdDeposit, amend: cmdAmend,
    rename: cmdRename, remove: cmdRemove, translate: cmdTranslate, import: cmdImport,
    doctor: cmdDoctor, format: cmdFormat, help: showHelp, '--help': showHelp, '-h': showHelp,
};
if (command === 'prune') { console.log("NOTE: 'prune' is deprecated. Use 'remove' instead.\n"); cmdRemove(); }
else if (commands[command]) { commands[command](); }
else { showHelp(); }
