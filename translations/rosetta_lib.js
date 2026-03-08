/**
 * ROSETTA_LIB.JS — Shared library for Rosetta Translation Management Tool
 * Contains: configuration, utilities, XML I/O, classification engine,
 * quality detection, codebase scanner, mutation engine, JSON protocol.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// --- CONFIGURATION

const VERSION = '1.1.0';

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
    if (!str) return str;
    return str
        .replace(/&(?!(?:amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);)/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

function extractFormatSpecifiers(str) {
    if (!str) return [];
    const pattern = /%[-+0#]*(\d+)?(\.\d+)?(hh?|ll?|L|z|j|t)?[diouxXeEfFgGaAcspn]/g;
    return str.match(pattern) || [];
}

function extractFormatSpecifiersSorted(str) {
    return extractFormatSpecifiers(str).sort();
}

function checkFormatSpecifiers(sourceValue, targetValue, key) {
    const sourceSpecs = extractFormatSpecifiersSorted(sourceValue);
    const targetSpecs = extractFormatSpecifiersSorted(targetValue);

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

// --- ENTITY NORMALIZATION (for untranslated detection)

function normalizeXmlEntities(s) {
    if (!s) return s;
    return s.replace(/&gt;/g, '>').replace(/&lt;/g, '<').replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&apos;/g, "'");
}

// --- COGNATE DETECTION

function isFormatOnlyString(value) {
    if (value === '') return true;
    if (!value) return false;
    const stripped = value
        .replace(/%[-+0-9]*\.?[0-9]*[sdfeEgGoxXuc%]/g, '')
        .replace(/\b(km|m|kg|l|h|s|ms|px|pcs|comm)\b/gi, '')
        .replace(/[:\s.,\-\/()[\]{}+]+/g, '');
    return stripped.length === 0;
}

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
        'original', 'score', 'principal', 'ha', 'pcs', 'elite', 'premium', 'portfolio', 'cell',
        'standard', 'budget', 'basic', 'advanced', 'pro', 'master',
        'leasing', 'spawning', 'repo', 'state', 'misfire', 'overheat',
        'runaway', 'cutout', 'workhorse', 'integration', 'vanilla',
        'item', 'land', 'thermostat',
        'description', 'confirmation', 'excellent', 'acceptable', 'finance', 'finances',
        'stable', 'ratio', 'actions', 'open', 'correct', 'incorrect',
        'option', 'admin', 'panel', 'diesel', 'trend',
    ];
    const lowerValue = value.toLowerCase().trim();
    if (commonCognates.includes(lowerValue)) return true;
    const words = lowerValue.split(/[^a-z]+/i).filter(w => w.length > 0);
    if (words.length > 0 && words.every(w => commonCognates.includes(w) || w.length <= 1)) return true;

    const commonPhrases = [
        'no', 'yes', 'si', 'ja',
        'obd scanner', 'service truck', 'spawn lemon', 'toggle debug',
        'reset cd', 'better contracts', 'admin panel', 'svc truck',
    ];
    if (commonPhrases.includes(lowerValue)) return true;

    if (/^vs\s+/i.test(value)) return true;
    // Short uppercase abbreviation combos like "OBD", "ECU STATUS", "DTC P0301" — NOT full phrases
    if (/^[A-Z]{2,6}(\s+[A-Z0-9]{1,6}){0,2}$/.test(value)) return true;
    if (/^[A-Za-z]+:\s*$/.test(value)) return true;
    if (/^[+\-]?\$[\d,]+$/.test(value) || /^Set \$\d+$/.test(value)) return true;
    if (/^(Rel|Surge|Flat):/i.test(value) || /\(L\)$|\(R\)$/.test(value)) return true;
    if (/^[A-Z]{2,5}\s+Integration$/i.test(value)) return true;
    // Abbreviation + percentage (Hyd 100%, Elec 50%, Oil 10%)
    if (/^[A-Za-z]{2,5}\s+\d+%$/.test(value)) return true;
    // Product/brand names (GMC C7000 Service Truck, UsedPlus Admin Panel)
    if (/UsedPlus/i.test(value)) return true;

    return false;
}

// --- TRANSLATION QUALITY DETECTION HELPERS

const CJK_LANGS = ['ct', 'jp', 'kr'];

const DIACRITIC_LANGS = {
    fi: /[äöåÄÖÅ]/,
    sv: /[äöåÅÄÖéÉ]/,
    da: /[æøåÆØÅ]/,
    de: /[äöüßÄÖÜ]/,
    fr: /[àâçéèêëîïôùûüÿæœÀÂÇÉÈÊËÎÏÔÙÛÜŸÆŒ]/,
    fc: /[àâçéèêëîïôùûüÿæœÀÂÇÉÈÊËÎÏÔÙÛÜŸÆŒ]/,
    hu: /[áéíóöőúüűÁÉÍÓÖŐÚÜŰ]/,
    cz: /[áčďéěíňóřšťúůýžÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ]/,
    ro: /[ăâîșțĂÂÎȘȚ]/,
    tr: /[çğıöşüÇĞİÖŞÜ]/,
    pl: /[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]/,
    nl: /[ëïéèöüËÏÉÈÖÜ]/,
    no: /[æøåÆØÅ]/,
    pt: /[àáâãçéêíóôõúÀÁÂÃÇÉÊÍÓÔÕÚ]/,
    br: /[àáâãçéêíóôõúÀÁÂÃÇÉÊÍÓÔÕÚ]/,
    it: /[àèéìíòóùúÀÈÉÌÍÒÓÙÚ]/,
    es: /[áéíñóúüÁÉÍÑÓÚÜ¿¡]/,
    ea: /[áéíñóúüÁÉÍÑÓÚÜ¿¡]/,
};

const ENGLISH_FUNCTION_WORDS = new Set([
    'the', 'is', 'are', 'was', 'were', 'has', 'have', 'been', 'will',
    'would', 'should', 'could', 'with', 'from', 'your', 'this', 'that',
    'which', 'when', 'into', 'also', 'their', 'they', 'than', 'then',
    'these', 'those', 'does', 'did', 'been', 'being', 'each', 'every',
]);

// English content words that should NEVER appear untranslated in target languages.
// Unlike function words (the, is, with), these are domain-specific verbs/adjectives/nouns
// that have no cognate excuse in any target language.
const ENGLISH_CONTENT_BLOCKLIST = new Set([
    'purchased', 'processed', 'successfully', 'restored', 'repaired',
    'insufficient', 'detected', 'expired', 'vehicles', 'financing',
    'payment', 'payments', 'found', 'needed', 'required', 'available',
    'selected', 'confirmed', 'completed', 'cancelled', 'approved',
    'rejected', 'submitted', 'updated', 'removed', 'added',
    'warning', 'buyer', 'seller', 'search', 'searches',
    'listed', 'unlisted', 'stopped', 'started',
    // Added from spotcheck v2 findings — words with no Romance cognate excuse
    'payoff', 'achieved', 'cheapest', 'impaired',
    'repossessed', 'searching', 'remaining', 'ensure',
    'choose', 'missed', 'working', 'pending', 'listing', 'listings',
    'received', 'sale', 'accounts',
    // Added from AMBER Pass 1 — ro/tr/id English contamination patterns
    // Only words with NO cognate excuse in any target language
    'ready', 'filled', 'above', 'declined',
    'tier', 'fill', 'make',
]);

function detectLiteralEscapes(value) {
    if (!value) return [];
    // Detect literal \n, \t, \r that should be &#10;, &#9;, &#13;
    const matches = [];
    if (/\\n/.test(value)) matches.push('\\n (should be &#10;)');
    if (/\\t/.test(value)) matches.push('\\t (should be &#9;)');
    if (/\\r/.test(value)) matches.push('\\r (should be &#13;)');
    return matches;
}

function detectDoubleEncodedEntities(value) {
    if (!value) return [];
    const patterns = [
        /&amp;#\d+;/g, /&amp;#x[0-9a-fA-F]+;/g,
        /&amp;amp;/g, /&amp;lt;/g, /&amp;gt;/g, /&amp;quot;/g,
    ];
    const matches = [];
    for (const pat of patterns) {
        let m;
        while ((m = pat.exec(value)) !== null) {
            matches.push(m[0]);
        }
    }
    return matches;
}

function detectEnglishFunctionWords(sourceValue, targetValue, langCode) {
    if (!targetValue || !sourceValue || langCode === 'en') return { count: 0, words: [] };
    if (targetValue === sourceValue) return { count: 0, words: [] };
    if (targetValue.length < 20) return { count: 0, words: [] };
    // Skip format-only strings
    if (isFormatOnlyString(targetValue)) return { count: 0, words: [] };

    const targetWords = targetValue.toLowerCase().split(/[\s,.:;!?()\[\]{}"'\/]+/).filter(w => w.length > 1);
    const found = targetWords.filter(w => ENGLISH_FUNCTION_WORDS.has(w));
    const unique = [...new Set(found)];
    // Require higher threshold (4+) for languages that commonly borrow English words
    const threshold = ['id', 'vi'].includes(langCode) ? 4 : 3;
    return { count: unique.length >= threshold ? unique.length : 0, words: unique.length >= threshold ? unique : [] };
}

function detectCJKRatio(value, langCode) {
    if (!value || value.length <= 10) return { ratio: 1.0, suspect: false };
    if (!CJK_LANGS.includes(langCode)) return { ratio: 1.0, suspect: false };

    // Strip URLs, format specifiers, digits, punctuation, whitespace for analysis
    const stripped = value.replace(/https?:\/\/\S+/g, '')
        .replace(/\S+\.\S+\/\S+/g, '') // URL-like paths (github.com/...)
        .replace(/%[-+0-9]*\.?[0-9]*[sdfeEgGoxXuc%]/g, '')
        .replace(/[\s\d.,;:!?()\[\]{}"'\/\-+=<>$@#&*^~|\\]+/g, '');
    // Also strip known brand names / proper nouns that stay in ASCII
    const cleaned = stripped.replace(/UsedPlus|EnhancedLoanSystem|BetterContracts|RealVehicleBreakdowns?|UseYourTyres|OBD|Scanner/gi, '');
    if (cleaned.length <= 5) return { ratio: 1.0, suspect: false };

    // Count CJK chars: CJK Unified, Extension A, Hiragana, Katakana, Hangul,
    // Katakana Ext, CJK Symbols, Fullwidth Forms, Halfwidth Katakana
    const cjkChars = cleaned.match(/[\u4E00-\u9FFF\u3400-\u4DBF\u3040-\u30FF\uAC00-\uD7AF\u31F0-\u31FF\u3000-\u303F\uFF00-\uFFEF\uFF65-\uFF9F]/g) || [];
    const ratio = cjkChars.length / cleaned.length;
    return { ratio, suspect: ratio < 0.3 };
}

// Per-language sentinel patterns: ASCII-only word stems that indicate stripped diacritics.
// Each regex matches common words that ALWAYS require diacritics when spelled correctly.
// Built from frequency analysis of actual translation corpus.
const STRIPPED_WORD_SENTINELS = {
    de: /\b(wahlen|uber\w*|konnen|mussen|verfugbar|qualitat(?!iv)|benotigt|kaufer|lauft|schlussel|naturlich|kreditwurdigkeit|fahig|gebuhr|ubersicht|uberprufen|erfullen|grundstuck|zuruckgeben)\b/i,
    fi: /\b(kaytt\w*|hyva\w*|riittamaton|enemman|jaljella|etta|nayt\w*|tama|tayta|sahko\w*|vahen\w*|myyda|paall\w*|myyntimaara|lisamaksu|loyty\w*|epaon\w*|riittamattom\w*|yhteensa|paatty\w*|paiva\w*|etsitaan|kaytetty|jaannos\w*|taysi|hylatty|todennakoisyys|loytaa)\b/i,
    pl: /\b(platnosc\w*|pozyczk\w*|sprzedaz\w*|pojazdow|miesiac\w*|wartosc\w*|ostrzezenie|twoj\b|rowniez|takze|mozliw\w*|wlasn\w*|prosze|zrodlo|scisle|jakosc\w*|powyzej|zuzyci\w*|wyblakni\w*|nieistniejac\w*|zawisniet\w*)\b/i,
    ro: /\b(dobanda|reparati[ie]\w*|imprumut\w*|finantare|conditie|vanzare|informatii|achizit\w*|masina|platit|insea?mna)\b/i,
    tr: /\b(odeme\w*|dusuk|satis\w*|islem\w*|ozellik\w*|guncelle\w*|donustur\w*)\b/i,
    fr: /\b(vehicule\w*|reparation\w*|interet\w*|systeme\w*|qualite|cout\w*|depense\w*|creancier|etre|depassement|securite)\b/i,
    fc: /\b(vehicule\w*|reparation\w*|interet\w*|systeme\w*|qualite|cout\w*|depense\w*|creancier|etre|depassement|securite)\b/i,
    da: /\b(koretoj\w*|sogning\w*|vaelg\w*|maned\w*|manedlig|kraever|utilstraekkelige|hydraulikvaeske|spaending|aendring)\b/i,
    no: /\b(kjoretoy\w*|kjop\w*|maned\w*|manedlig|hoyere|fullfort|darlig|hydraulikkvaeske|endring\w*|nokkelverd|sok\w*|prov\b|lan\b|pa\b|pakrevd|utkjops\w*|kontantlan)\b/i,
    nl: /\b(geinstalleerd|beeindigd\w*|beeindiging\w*|geinteresseerd|cooperat\w*|geinformeerd|geinspecteerd)\b/i,
    sv: /\b(valj\w*|ranta\w*|fran\b|behover|manad\w*|sokning\w*|otillrackliga|upptackt|hogre|forsakring|sok\w*|gor\b|kop\b|kopa\w*|forsaljning\w*|varde\w*|vardighet|restvarde\w*|godkan\w*|forvant\w*|lan\b|pa\b|for\b|aterbetalning\w*|aterstaende|laneperiod|spelmanad\w*)\b/i,
    hu: /\b(kereses\w*|torlesztes\w*|szukseges|koltseg\w*|fizetes\w*|osszes|honap\w*|fold\w*|jarmu\w*|szamla|kornyezet)\b/i,
    cz: /\b(pujck\w*|nabidka|mesicn[ie]\w*|mesic\b|vyssi|uzivatel\w*|pozadavek|uver\w*)\b/i,
    it: /\b(vehicule\w*|disponibilita|affidabilita|qualita|attivita|possibilita|responsabilita|pubblicita)\b/i,
    es: /\b(vehiculo\w*|informacion|reparacion|condicion|calificacion|financiacion|garantia|duracion|negociacion)\b/i,
    ea: /\b(vehiculo\w*|informacion|reparacion|condicion|calificacion|financiacion|garantia|duracion|negociacion)\b/i,
    pt: /\b(veiculo\w*|informacao|reparacao|condicao|qualificacao|classificacao)\b/i,
    br: /\b(veiculo\w*|informacao|reparacao|condicao|qualificacao|classificacao)\b/i,
};

function detectDiacriticStripping(sourceValue, targetValue, langCode) {
    if (!DIACRITIC_LANGS[langCode]) return false;
    if (!targetValue || targetValue === sourceValue) return false;
    // Skip format-only strings
    if (isFormatOnlyString(targetValue)) return false;
    // Word-level detection: check for specific stripped word patterns
    // Works even in mixed strings (some diacritics present, some stripped)
    const sentinels = STRIPPED_WORD_SENTINELS[langCode];
    if (!sentinels) return false;
    // Split on whitespace/punctuation to keep whole words intact (prevents
    // "Écoute" → "coute" fragment extraction from ASCII word-boundary regex)
    // Then keep only words that are entirely ASCII (genuinely stripped diacritics)
    // Skip ALL-UPPERCASE words (Turkish ı→I, headers/labels)
    const words = targetValue.split(/[\s,;:!?.()[\]{}\/"'<>=%+\-÷×&#+]+/).filter(w => w.length >= 3);
    const asciiOnly = words.filter(w => /^[a-zA-Z]+$/.test(w) && w !== w.toUpperCase());
    if (asciiOnly.length === 0) return false;
    const matched = asciiOnly.filter(w => sentinels.test(w));
    // Compound languages (fi, sv, no, da, de): sentinel stems may be embedded in compounds
    // e.g. "Aloituspaiva" contains stripped "paiva" but \b prevents sentinel match.
    // For long ASCII words, strip \b from sentinel regex and retest.
    // IMPORTANT: Filter out short stems (<4 chars) to prevent false positives —
    // e.g. "pa" matching inside "reparasjoner", "lan" inside "kontantlan" etc.
    const COMPOUND_LANGS = new Set(['fi', 'sv', 'no', 'da', 'de']);
    if (COMPOUND_LANGS.has(langCode)) {
        // Extract alternation branches from the sentinel source and keep only stems >= 4 chars
        const rawSource = sentinels.source.replace(/\\b/g, '');
        // Source is like "(stem1\w*|stem2|...)" — extract the inner alternation
        const inner = rawSource.replace(/^\(/, '').replace(/\)$/, '');
        const branches = inner.split('|').filter(b => {
            // Get the base stem (before any \w* or quantifier)
            const base = b.replace(/\\w\*$/, '').replace(/\\b$/, '');
            return base.length >= 5;  // 5+ chars to prevent FP: "etta"→"maksettava", "tama"→"odottamattomasti"
        });
        if (branches.length > 0) {
            const unbounded = new RegExp('(' + branches.join('|') + ')', sentinels.flags);
            // Require stem covers at least 40% of the word to avoid short-stem-in-long-word FPs
            const compoundMatched = asciiOnly.filter(w => {
                if (w.length < 8 || matched.includes(w)) return false;
                const m = w.match(unbounded);
                if (!m) return false;
                return m[0].length >= w.length * 0.4;
            });
            matched.push(...compoundMatched);
        }
    }
    if (matched.length === 0) return false;
    return { flagged: true, words: matched };
}

function detectEnglishMorphologySuffix(value, langCode) {
    if (!value || langCode === 'en' || value.length < 10) return { count: 0, words: [] };

    // Skip Romance languages and Dutch — consonant+s is their natural plural/adverb form
    // (e.g., FR "paiements", NL "maandelijks", ES "pagamentos", IT "documenti" aren't English artifacts)
    const consonantSLangs = ['fr', 'fc', 'es', 'ea', 'pt', 'br', 'it', 'nl', 'ro'];
    if (consonantSLangs.includes(langCode)) return { count: 0, words: [] };

    // Common words ending in consonant+s that are NOT English morphology issues
    const morphExclude = new Set([
        'plus', 'bonus', 'status', 'minus', 'campus', 'focus', 'radius',
        'nexus', 'bus', 'census', 'corpus', 'stimulus', 'apparatus',
        'thus', 'virus', 'versus', 'consensus', 'surplus', 'atlas',
    ]);

    const words = value.split(/[\s,.:;!?()\[\]{}"'\/]+/).filter(w => w.length > 4);
    const suspectWords = [];
    for (const word of words) {
        const lower = word.toLowerCase();
        if (morphExclude.has(lower)) continue;
        if (isCognateOrInternationalTerm(word)) continue;
        if (/[bcdfghjklmnpqrtvwxyz]s$/i.test(word) && !/ss$/i.test(word)) {
            suspectWords.push(word);
        }
    }
    return { count: suspectWords.length, words: suspectWords.slice(0, 5) };
}

function detectTruncation(sourceValue, targetValue, langCode) {
    if (!sourceValue || !targetValue) return false;
    // Strip format specifiers and XML entities for fair comparison
    const strip = s => s.replace(/%[-+0-9]*\.?[0-9]*[sdfeEgGoxXuc%]/g, '')
        .replace(/&amp;\w+;|&#\d+;|&#x[0-9a-fA-F]+;/g, '')
        .replace(/https?:\/\/\S+/g, '');
    // CJK languages encode more meaning per character — use stricter threshold
    if (CJK_LANGS.includes(langCode)) {
        // Catch single-char CJK for multi-word English sources (e.g. "氣" for "Electrical")
        // 2-char CJK is normal for single English words (e.g. "確認" for "Confirmation")
        // 1-char CJK is OK if source is mostly numbers with 1 word (e.g. "月" for "6 Months")
        const tgtCJK = targetValue.replace(/[\s\d.,;:!?()\[\]{}"'\/\-+=<>$@#&*^~|\\%]+/g, '');
        if (tgtCJK.length === 1 && sourceValue.length >= 8) {
            const srcWords = sourceValue.replace(/[\d%+\-.,]+/g, '').trim().split(/\s+/).filter(w => w.length >= 2);
            if (srcWords.length >= 2) return true;
        }
        if (sourceValue.length <= 50) return false;
        const srcLen = strip(sourceValue).length;
        const tgtLen = strip(targetValue).length;
        return srcLen > 30 && tgtLen < srcLen * 0.15;
    }
    // Only flag long source strings
    if (sourceValue.length <= 30) return false;
    const srcLen = strip(sourceValue).length;
    const tgtLen = strip(targetValue).length;
    if (srcLen <= 20) return false;
    // Character length check
    if (tgtLen < srcLen * 0.4) return true;
    // Sentence count check: if source has 2+ sentences and target drops most of them
    const srcSentences = sourceValue.split(/[.!?]+/).filter(s => s.trim().length > 5).length;
    const tgtSentences = targetValue.split(/[.!?。！？]+/).filter(s => s.trim().length > 3).length;
    if (srcSentences >= 3 && tgtSentences <= 1) return true;
    return false;
}

function detectTurkishUppercaseI(value, langCode) {
    if (langCode !== 'tr' || !value) return false;
    // Turkish: uppercase words should not contain lowercase ı (U+0131)
    // Mixed case like "KAPATıLMıŞ" is always wrong — should be "KAPATILMIŞ"
    return /[A-ZÇĞİÖŞÜ]+\u0131[A-ZÇĞİÖŞÜ]+/.test(value);
}

function detectCJKEnglishWords(value, langCode) {
    if (!CJK_LANGS.includes(langCode) || !value) return [];
    // Strip mod names and proper nouns that should remain in English
    const cleaned = value.replace(/Real Vehicle Breakdowns?|Use Your Tyres?|UsedPlus|EnhancedLoanSystem|AdvancedMaintenance|HirePurchasing|BuyUsedEquipment|GMC C7000/gi, '');
    // In CJK text, standalone common English words indicate partial translation.
    // Only flag words from a strict blocklist — CJK text legitimately contains
    // technical terms, brand names, abbreviations, and short loanwords (vs, or, etc.)
    const cjkBlocklist = new Set([
        'for', 'funds', 'the', 'with', 'from', 'your', 'this', 'that',
        'payment', 'payments', 'purchased', 'processed', 'available',
        'insufficient', 'required', 'needed', 'found', 'warning',
        'buyer', 'seller', 'expired', 'confirmed', 'completed',
        'working', 'handling', 'remaining', 'balance', 'monthly',
        'fill', 'tank', 'choose', 'vehicle', 'repair',
    ]);
    const words = cleaned.match(/\b[a-zA-Z]{3,}\b/g) || [];
    const leaked = words.filter(w => cjkBlocklist.has(w.toLowerCase()));
    // Also detect English words adjacent to CJK chars (e.g. "Go 返回", "債務-to-資產")
    // These are short words the blocklist might miss but are clearly untranslated
    const cjkChar = '[\u4E00-\u9FFF\u3400-\u4DBF\u3040-\u30FF\uAC00-\uD7AF]';
    const adjacentRe = new RegExp(`${cjkChar}[\\s\\-]*([a-zA-Z]{2,})[\\s\\-]*${cjkChar}`, 'g');
    const allowedAdjacent = new Set(['vs', 'or', 'km', 'kg', 'hp', 'rpm', 'obd', 'usb', 'gps',
        'api', 'rvb', 'pto', 'esc', 'can', 'mod', 'plus', 'els']);
    let m;
    while ((m = adjacentRe.exec(cleaned)) !== null) {
        const w = m[1];
        if (!allowedAdjacent.has(w.toLowerCase()) && !leaked.includes(w)) leaked.push(w);
    }
    return leaked;
}

// --- SCRIPT, CHARACTER, SUFFIX, AND VARIANT DETECTION

function detectScriptIssues(value, langCode) {
    const issues = [];
    // Zero-width characters (all languages)
    const zwc = value.match(/[\u200B\u200C\u200D\uFEFF]/g);
    if (zwc) issues.push({ type: 'zwc', detail: `${zwc.length} zero-width char(s)` });
    // CJK-only checks
    if (!CJK_LANGS.includes(langCode)) return issues;
    // Garbling: Latin-CJK interleaving (Latin-CJK-Latin, or CJK directly attached to lowercase Latin 2+)
    const garbled = value.match(/[a-zA-Z][\u4E00-\u9FFF\u3400-\u4DBF]+[a-zA-Z]|[\u4E00-\u9FFF\u3400-\u4DBF]+[a-z]{2,}/g);
    if (garbled) issues.push({ type: 'garbled', detail: `${garbled.length} garbled pattern(s): ${garbled.slice(0, 3).join(', ')}` });
    // Unnatural spacing (CT only — JP uses some spaces legitimately)
    if (langCode === 'ct') {
        const cjkSpaces = value.match(/[\u4E00-\u9FFF] [\u4E00-\u9FFF]/g);
        if (cjkSpaces && cjkSpaces.length >= 2) {
            issues.push({ type: 'cjk_spacing', detail: `${cjkSpaces.length} unnatural space(s)` });
        }
    }
    return issues;
}

// Locales that use comma as decimal separator
const COMMA_DECIMAL_LANGS = ['fi', 'sv', 'da', 'no', 'nl', 'de', 'fr', 'fc', 'es', 'ea', 'it', 'pt', 'br', 'ro', 'tr', 'pl', 'cz', 'hu'];

// German words commonly written with ASCII umlaut substitutions
const DE_UMLAUT_WORDS = /\b(fuer|Haendler|laeuft|Aenderung|waehlen|koennen|muessen|Verfuegbar|Gebuehr|moechten|groesser|zurueck|ueberpruef|Ueberblick|natuerlich|faehig|Grundstueck|Kaeufer|erhoehen|genuegend|Zuverlaessig\w*|Gehaeuse|Erhoeht|Benoetigt)\b/i;

function detectCharacterIssues(sourceValue, targetValue, langCode) {
    const issues = [];
    if (!targetValue || targetValue === sourceValue) return issues;
    // Decimal separator (comma-decimal locales)
    if (COMMA_DECIMAL_LANGS.includes(langCode)) {
        const decimalDots = targetValue.match(/\d\.\d+%/g);
        if (decimalDots) issues.push({ type: 'decimal_sep', detail: decimalDots.join(', ') });
    }
    // Doubled accents (almost never valid)
    const doubled = targetValue.match(/([àâçéèêëîïôùûüÿñáíóúăîșț])\1/gi);
    if (doubled) {
        // Exclude French feminine past participles (-ée, -éé valid: créée, agréée)
        const filtered = doubled.filter(d => !/ée|éé/i.test(d));
        if (filtered.length > 0) issues.push({ type: 'doubled_accent', detail: filtered.join(', ') });
    }
    // German umlaut encoding (ae->ä, oe->ö, ue->ü)
    if (langCode === 'de') {
        const words = targetValue.match(DE_UMLAUT_WORDS);
        if (words) issues.push({ type: 'umlaut_encoding', detail: words.slice(0, 3).join(', ') });
    }
    return issues;
}

function detectInlineSuffix(sourceValue, targetValue) {
    if (!sourceValue || !targetValue) return false;
    // Source starts with " (" and ends with ")" — inline suffix like " (worn)"
    if (sourceValue.startsWith(' (') && sourceValue.endsWith(')')) {
        return !targetValue.startsWith(' (') || !targetValue.endsWith(')');
    }
    return false;
}

const VARIANT_PAIRS = { fc: 'fr', ea: 'es', br: 'pt' };

function detectVariantDivergence(langCode, langEntries, pairEntries, sourceEntries) {
    if (!VARIANT_PAIRS[langCode]) return [];
    const results = [];
    for (const [key, sourceData] of sourceEntries) {
        const langData = langEntries.get(key);
        const pairData = pairEntries.get(key);
        if (!langData || !pairData) continue;
        // Entry identical to English in this lang, but properly translated in pair lang
        if (langData.value === sourceData.value && pairData.value !== sourceData.value
            && !isFormatOnlyString(sourceData.value)) {
            results.push({ key, value: langData.value, pairValue: pairData.value });
        }
    }
    return results;
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

function formatEntry(key, value, hash, format, tag) {
    const escapedValue = escapeXml(value);
    if (format === 'elements') {
        const tagAttr = tag ? ` tag="${tag}"` : '';
        return `<e k="${key}" v="${escapedValue}" eh="${hash}"${tagAttr} />`;
    } else {
        return `<text name="${key}" text="${escapedValue}"/>`;
    }
}

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

// --- CLASSIFICATION ENGINE

function classifyEntries(sourceEntries, sourceHashes, langEntries, langOrderedKeys, format, langCode) {
    const result = {
        translated: [], stale: [], untranslated: [], missing: [],
        orphaned: [], duplicates: [], formatErrors: [], formatOrderWarnings: [],
        suspectTranslations: [], emptyValues: [], whitespaceIssues: [],
        doubleEncodedEntities: [], cjkIssues: [], diacriticIssues: [],
        morphologyIssues: [], englishFunctionWordIssues: [], truncationIssues: [],
        scriptIssues: [], characterIssues: [], inlineSuffixIssues: [],
        colonMismatches: [],
    };

    for (const [key, sourceData] of sourceEntries) {
        const sourceHash = sourceHashes.get(key);

        if (!langEntries.has(key)) {
            result.missing.push({ key, enValue: sourceData.value });
        } else {
            const langData = langEntries.get(key);

            if (langData.value.startsWith(CONFIG.untranslatedPrefix)) {
                result.untranslated.push({ key, value: langData.value, reason: 'has [EN] prefix' });
            } else if (/^\[[^\]]{1,10}\]\s/.test(langData.value)) {
                const bracket = langData.value.match(/^\[[^\]]{1,10}\]/)[0];
                const bracketInner = bracket.slice(1, -1);
                // Skip if bracket content is format specifiers (e.g. [%s%d]) — these are output patterns, not language tags
                if (!/^[%sdfc.0-9+\-lfexXuoEgG]+$/.test(bracketInner)) {
                    result.untranslated.push({ key, value: langData.value, reason: `has ${bracket} prefix (not translated)` });
                } else {
                    // Format specifier group — classify normally
                    if ((langData.value === sourceData.value || normalizeXmlEntities(langData.value) === normalizeXmlEntities(sourceData.value)) && !isFormatOnlyString(sourceData.value)) {
                        result.untranslated.push({ key, value: langData.value, reason: 'exact match (not cognate)' });
                    } else {
                        result.translated.push({ key, value: langData.value });
                    }
                }
            } else if ((langData.value === sourceData.value || normalizeXmlEntities(langData.value) === normalizeXmlEntities(sourceData.value)) && !isFormatOnlyString(sourceData.value) && !isCognateOrInternationalTerm(sourceData.value)) {
                result.untranslated.push({ key, value: langData.value, reason: 'exact match (not cognate)' });
            } else if (format === 'elements' && langData.hash && langData.hash !== sourceHash) {
                result.stale.push({ key, value: langData.value, oldHash: langData.hash, newHash: sourceHash, enValue: sourceData.value });
            } else {
                result.translated.push({ key, value: langData.value });
            }

            if (!langData.value.startsWith(CONFIG.untranslatedPrefix)) {
                if (langData.value === '') {
                    result.emptyValues.push({ key });
                }
                if (langData.value && langData.value !== langData.value.trim()) {
                    result.whitespaceIssues.push({ key, value: langData.value });
                }
                const formatIssue = checkFormatSpecifiers(sourceData.value, langData.value, key);
                if (formatIssue) {
                    result.formatErrors.push(formatIssue);
                }
                const srcSpecs = extractFormatSpecifiers(sourceData.value);
                const tgtSpecs = extractFormatSpecifiers(langData.value);
                if (srcSpecs.length >= 2 && srcSpecs.length === tgtSpecs.length &&
                    [...srcSpecs].sort().join(',') === [...tgtSpecs].sort().join(',') &&
                    srcSpecs.join(',') !== tgtSpecs.join(',')) {
                    result.formatOrderWarnings.push({
                        key, source: srcSpecs, target: tgtSpecs,
                        message: `Specifier order differs: source [${srcSpecs.join(', ')}] vs target [${tgtSpecs.join(', ')}] (Lua is positional!)`
                    });
                }
                let alreadySuspect = false;
                if (langData.value !== sourceData.value && sourceData.value.length > 20) {
                    // Strip format specifiers, numbers/percentages, URLs, XML entities for word comparison
                    const stripNoise = s => s
                        .replace(/%[-+0-9]*\.?[0-9]*[sdfeEgGoxXuc%]/g, '')
                        .replace(/https?:\/\/\S+/g, '')
                        .replace(/\S+\.\S+\/\S+/g, '') // URL-like paths
                        .replace(/&amp;\w+;|&#\d+;|&#x[0-9a-fA-F]+;/g, '')
                        .replace(/\d+[%.,]?\d*/g, '');
                    const srcWords = stripNoise(sourceData.value).split(/\s+/).filter(w => w.length > 2 && !/^[A-Z][a-z]*$/.test(w));
                    const tgtWords = stripNoise(langData.value).split(/\s+/).filter(w => w.length > 2);
                    // Exclude words that are international terms/proper nouns shared across languages
                    const sharedTerms = new Set(['Premium', 'Standard', 'Elite', 'Economy', 'UsedPlus', 'github.com']);
                    if (srcWords.length >= 3 && tgtWords.length >= 3) {
                        const engInTarget = tgtWords.filter(w => srcWords.includes(w) && !sharedTerms.has(w) && !isCognateOrInternationalTerm(w)).length;
                        const ratio = engInTarget / tgtWords.length;
                        const minEngWords = tgtWords.length < 8 ? 2 : 3;
                        if (ratio >= 0.4 && ratio < 1.0 && engInTarget >= minEngWords) {
                            result.suspectTranslations.push({
                                key, value: langData.value,
                                reason: `Partially translated: ${engInTarget}/${tgtWords.length} words (${Math.round(ratio*100)}%) match English source`
                            });
                            alreadySuspect = true;
                        }
                    }
                }
                // English content word blocklist — runs on ALL entries (not gated by source length)
                if (!alreadySuspect && langData.value !== sourceData.value) {
                    const tgtLower = langData.value.toLowerCase().split(/[\s,.:;!?()\[\]{}"'\/]+/).filter(w => w.length > 3);
                    const leaked = tgtLower.filter(w => ENGLISH_CONTENT_BLOCKLIST.has(w));
                    if (leaked.length >= 1) {
                        result.suspectTranslations.push({
                            key, value: langData.value,
                            reason: `English content word leakage: ${[...new Set(leaked)].join(', ')}`
                        });
                    }
                }
                if (langCode) {
                    const deMatches = detectDoubleEncodedEntities(langData.value);
                    const escMatches = detectLiteralEscapes(langData.value);
                    const allEntityMatches = [...deMatches, ...escMatches];
                    if (allEntityMatches.length > 0) {
                        result.doubleEncodedEntities.push({ key, value: langData.value, matches: allEntityMatches });
                    }
                    if (CJK_LANGS.includes(langCode)) {
                        const cjk = detectCJKRatio(langData.value, langCode);
                        if (cjk.suspect) {
                            result.cjkIssues.push({ key, value: langData.value, ratio: cjk.ratio });
                        }
                    }
                    const efw = detectEnglishFunctionWords(sourceData.value, langData.value, langCode);
                    if (efw.count >= 3) {
                        result.englishFunctionWordIssues.push({ key, value: langData.value, count: efw.count, words: efw.words });
                    }
                    if (DIACRITIC_LANGS[langCode]) {
                        const diaResult = detectDiacriticStripping(sourceData.value, langData.value, langCode);
                        if (diaResult) {
                            result.diacriticIssues.push({ key, value: langData.value, words: diaResult.words });
                        }
                    }
                    const morph = detectEnglishMorphologySuffix(langData.value, langCode);
                    if (morph.count >= 3) {
                        result.morphologyIssues.push({ key, value: langData.value, count: morph.count, words: morph.words });
                    }
                    if (detectTruncation(sourceData.value, langData.value, langCode)) {
                        const pct = Math.round(langData.value.length * 100 / sourceData.value.length);
                        result.truncationIssues.push({ key, value: langData.value, sourceLen: sourceData.value.length, targetLen: langData.value.length, pct });
                    }
                    // Script issues (garbling, spacing, zero-width)
                    const scriptIss = detectScriptIssues(langData.value, langCode);
                    if (scriptIss.length > 0) {
                        result.scriptIssues.push({ key, value: langData.value, issues: scriptIss });
                    }
                    // Turkish uppercase ı detection
                    if (detectTurkishUppercaseI(langData.value, langCode)) {
                        result.characterIssues.push({ key, value: langData.value, issues: [{ type: 'turkish_i', detail: 'Uppercase word contains lowercase ı (U+0131)' }] });
                    }
                    // CJK English word leakage (stricter than general content blocklist)
                    if (CJK_LANGS.includes(langCode)) {
                        const cjkLeaked = detectCJKEnglishWords(langData.value, langCode);
                        if (cjkLeaked.length > 0) {
                            result.suspectTranslations.push({ key, value: langData.value, reason: `English words in CJK text: ${cjkLeaked.join(', ')}` });
                        }
                    }
                    // Character issues (decimal separator, doubled accents, umlaut encoding)
                    const charIss = detectCharacterIssues(sourceData.value, langData.value, langCode);
                    if (charIss.length > 0) {
                        result.characterIssues.push({ key, value: langData.value, issues: charIss });
                    }
                    // Inline suffix format
                    if (detectInlineSuffix(sourceData.value, langData.value)) {
                        result.inlineSuffixIssues.push({ key, source: sourceData.value, value: langData.value });
                    }
                    // Colon consistency: if source ends with ":" translation should too
                    // CJK languages use fullwidth colon ： (U+FF1A) which is equivalent
                    if (sourceData.value.trimEnd().endsWith(':') && !langData.value.trimEnd().endsWith(':') && !langData.value.trimEnd().endsWith('\uFF1A') && langData.value !== sourceData.value) {
                        result.colonMismatches.push({ key, value: langData.value });
                    }
                }
            }
        }
    }

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
        usedKeys, unusedKeys, dynamicPrefixes,
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

    const luaDirs = [srcDir, vehiclesDir];
    for (const dir of luaDirs) {
        const luaFiles = getFilesRecursive(dir, ['.lua']);
        for (const luaFile of luaFiles) {
            const content = fs.readFileSync(luaFile, 'utf8');
            let match;

            const getTextPattern = /getText\("([^"]+)"\)/g;
            while ((match = getTextPattern.exec(content)) !== null) usedKeys.add(match[1]);

            const stringPattern = /"(usedplus_[a-zA-Z0-9_]+|usedPlus_[a-zA-Z0-9_]+)"/g;
            while ((match = stringPattern.exec(content)) !== null) usedKeys.add(match[1]);

            const dynamicPattern = /"(usedplus_[a-z_]+_|usedPlus_[a-z_]+_)"\s*\.\./g;
            while ((match = dynamicPattern.exec(content)) !== null) dynamicPrefixes.add(match[1]);
        }
    }

    const placeablesDir = path.join(modDir, 'placeables');
    const xmlDirs = [guiDir, placeablesDir, vehiclesDir];
    for (const dir of xmlDirs) {
        const xmlFiles = getFilesRecursive(dir, ['.xml']);
        for (const xmlFile of xmlFiles) {
            const content = fs.readFileSync(xmlFile, 'utf8');
            const l10nPattern = /\$l10n_([a-zA-Z0-9_]+)/g;
            let match;
            while ((match = l10nPattern.exec(content)) !== null) usedKeys.add(match[1]);
        }
    }

    if (fs.existsSync(modDescPath)) {
        const content = fs.readFileSync(modDescPath, 'utf8');
        const l10nPattern = /\$l10n_([a-zA-Z0-9_]+)/g;
        let match;
        while ((match = l10nPattern.exec(content)) !== null) usedKeys.add(match[1]);
    }

    for (const prefix of dynamicPrefixes) {
        for (const key of allEnglishKeys) {
            if (key.startsWith(prefix)) usedKeys.add(key);
        }
    }

    const gameEnginePrefixes = ['input_', 'fillType_', 'configuration_', 'unit_'];
    for (const key of allEnglishKeys) {
        if (gameEnginePrefixes.some(p => key.startsWith(p))) usedKeys.add(key);
    }

    return { usedKeys, dynamicPrefixes };
}

// Scan codebase for ALL getText/l10n references and find keys missing from translation files
function findMissingKeys(sourceEntries) {
    const modDir = getModDir();
    const allCodeKeys = new Set();

    const srcDir = path.join(modDir, 'src');
    const guiDir = path.join(modDir, 'gui');
    const modDescPath = path.join(modDir, 'modDesc.xml');
    const vehiclesDir = path.join(modDir, 'vehicles');

    // Scan Lua files for getText("key") references
    for (const dir of [srcDir, vehiclesDir]) {
        const luaFiles = getFilesRecursive(dir, ['.lua']);
        for (const luaFile of luaFiles) {
            const content = fs.readFileSync(luaFile, 'utf8');
            let match;
            const getTextPattern = /getText\("([^"]+)"\)/g;
            while ((match = getTextPattern.exec(content)) !== null) allCodeKeys.add(match[1]);
        }
    }

    // Scan XML files for $l10n_ references
    const placeablesDir = path.join(modDir, 'placeables');
    for (const dir of [guiDir, placeablesDir, vehiclesDir]) {
        const xmlFiles = getFilesRecursive(dir, ['.xml']);
        for (const xmlFile of xmlFiles) {
            const content = fs.readFileSync(xmlFile, 'utf8');
            const l10nPattern = /\$l10n_([a-zA-Z0-9_]+)/g;
            let match;
            while ((match = l10nPattern.exec(content)) !== null) allCodeKeys.add(match[1]);
        }
    }

    if (fs.existsSync(modDescPath)) {
        const content = fs.readFileSync(modDescPath, 'utf8');
        const l10nPattern = /\$l10n_([a-zA-Z0-9_]+)/g;
        let match;
        while ((match = l10nPattern.exec(content)) !== null) allCodeKeys.add(match[1]);
    }

    // Filter to only usedplus_/usedPlus_ keys (ignore game engine keys like input_, fillType_)
    const modKeys = [...allCodeKeys].filter(k => /^usedplus_|^usedPlus_/i.test(k));

    // Find keys referenced in code but missing from English source
    const missing = modKeys.filter(k => !sourceEntries.has(k)).sort();

    return { allCodeKeys: modKeys, missing };
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

// --- STORE INIT

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

// --- MUTATION ENGINE

function addEntryToContent(content, key, value, hash, format, enOrderedKeys, langKeySet, tag) {
    const newEntry = `\n        ${formatEntry(key, value, hash, format, tag)}`;
    const insertPos = findInsertPosition(content, key, enOrderedKeys, langKeySet, format);

    if (insertPos !== -1) {
        return content.substring(0, insertPos) + newEntry + content.substring(insertPos);
    }
    return content;
}

function updateEntryInContent(content, key, newValue, newHash, format) {
    if (format === 'elements') {
        const pattern = new RegExp(
            `<e k="${escapeRegex(key)}" v="([^"]*)"([^>]*)\\s*/>`, 'g'
        );
        return content.replace(pattern, (_match, oldValue, attrs) => {
            const cleanAttrs = attrs.replace(/\s*eh="[^"]*"/g, '');
            const tagMatch = cleanAttrs.match(/tag="([^"]*)"/);
            const tagAttr = tagMatch ? ` tag="${tagMatch[1]}"` : '';
            const val = newValue !== null ? escapeXml(newValue) : oldValue;
            return `<e k="${key}" v="${val}" eh="${newHash}"${tagAttr} />`;
        });
    } else {
        const pattern = new RegExp(
            `<text name="${escapeRegex(key)}" text="([^"]*)"\\s*/>`, 'g'
        );
        return content.replace(pattern, (_match, oldValue) => {
            const val = newValue !== null ? escapeXml(newValue) : oldValue;
            return `<text name="${key}" text="${val}"/>`;
        });
    }
}

function removeEntryFromContent(content, key, format) {
    let pattern;
    if (format === 'elements') {
        pattern = new RegExp(`\\s*<e k="${escapeRegex(key)}" v="[^"]*"[^>]*/>\\s*\\n?`, 'g');
    } else {
        pattern = new RegExp(`\\s*<text name="${escapeRegex(key)}" text="[^"]*"\\s*/>\\s*\\n?`, 'g');
    }
    return content.replace(pattern, '\n');
}

function renameKeyInContent(content, oldKey, newKey, format) {
    if (format === 'elements') {
        const pattern = new RegExp(
            `<e k="${escapeRegex(oldKey)}" v="([^"]*)"([^>]*)\\s*/>`, 'g'
        );
        return content.replace(pattern, (_match, value, attrs) => {
            return `<e k="${newKey}" v="${value}"${attrs} />`;
        });
    } else {
        const pattern = new RegExp(
            `<text name="${escapeRegex(oldKey)}" text="([^"]*)"\\s*/>`, 'g'
        );
        return content.replace(pattern, (_match, value) => {
            return `<text name="${newKey}" text="${value}"/>`;
        });
    }
}

function atomicWrite(filePath, content) {
    const tmpPath = filePath + '.tmp';
    try {
        fs.writeFileSync(tmpPath, content, 'utf8');
        fs.renameSync(tmpPath, filePath);
        return true;
    } catch (err) {
        try { fs.unlinkSync(tmpPath); } catch (_) {}
        throw err;
    }
}

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

function exportForTranslation(langCode, sourceEntries, sourceHashes, langEntries, langOrderedKeys, format, includeStale, compact) {
    const langName = LANGUAGE_NAMES[langCode] || langCode.toUpperCase();
    const classification = classifyEntries(sourceEntries, sourceHashes, langEntries, langOrderedKeys, format, langCode);

    let entriesToExport = classification.untranslated.concat(classification.missing);
    if (includeStale) {
        entriesToExport = entriesToExport.concat(classification.stale);
    }

    if (entriesToExport.length === 0) return null;

    const sourceKeys = compact ? null : [...sourceEntries.keys()];
    const translatedSet = compact ? null : new Set(classification.translated.map(e => e.key));

    const entries = entriesToExport.map(entry => {
        const key = entry.key;
        const sourceData = sourceEntries.get(key);
        const sourceValue = sourceData ? sourceData.value : entry.enValue;
        const sourceHash = sourceHashes.get(key);

        if (compact) return { key, source: sourceValue, sourceHash };

        const langData = langEntries ? langEntries.get(key) : null;
        const formatSpecs = extractFormatSpecifiers(sourceValue);
        const keyIndex = sourceKeys.indexOf(key);

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
            sourceLanguage: CONFIG.sourceLanguage, targetLanguage: langCode,
            targetName: langName, exportedAt: new Date().toISOString(), entryCount: entries.length,
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

// --- TABLE FORMATTERS

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

// --- EXPORTS

module.exports = {
    VERSION, CONFIG, LANGUAGE_NAMES, CJK_LANGS, DIACRITIC_LANGS,
    COMMA_DECIMAL_LANGS, VARIANT_PAIRS,
    getHash, escapeRegex, escapeXml, extractFormatSpecifiers, checkFormatSpecifiers,
    isFormatOnlyString, isCognateOrInternationalTerm,
    detectDoubleEncodedEntities, detectEnglishFunctionWords, detectCJKRatio,
    detectDiacriticStripping, detectEnglishMorphologySuffix,
    detectScriptIssues, detectCharacterIssues, detectInlineSuffix, detectVariantDivergence,
    autoDetectFilePrefix, autoDetectXmlFormat, getSourceFilePath, getLangFilePath,
    parseTranslationFile, formatEntry, findInsertPosition, getEnabledLanguages,
    classifyEntries,
    getFilesRecursive, getModDir, gateCodebaseValidation, findMissingKeys, printGateSummary,
    initStore,
    addEntryToContent, updateEntryInContent, removeEntryFromContent, renameKeyInContent,
    atomicWrite, getAllFilePaths,
    exportForTranslation, validateAndImport,
    padRight, padLeft, printCheckSummaryTable,
};
