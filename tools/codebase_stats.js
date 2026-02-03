#!/usr/bin/env node
/**
 * FS25_UsedPlus Codebase Statistics Generator
 *
 * Generates comprehensive statistics about the codebase:
 * - File counts by type (Lua, XML, etc.)
 * - Lines of code metrics
 * - Directory breakdown
 * - Translation coverage
 *
 * Usage:
 *   node codebase_stats.js
 *
 * Author: Claude & Samantha
 * Version: 1.0.0
 */

const fs = require('fs');
const path = require('path');

const MOD_ROOT = path.dirname(__dirname);

// Colors for terminal output
const colors = {
    cyan: '\x1b[96m',
    green: '\x1b[92m',
    yellow: '\x1b[93m',
    reset: '\x1b[0m',
    bold: '\x1b[1m'
};

/**
 * Recursively get all files in a directory
 */
function getAllFiles(dir, fileList = []) {
    const files = fs.readdirSync(dir);

    for (const file of files) {
        const filePath = path.join(dir, file);
        const stat = fs.statSync(filePath);

        if (stat.isDirectory()) {
            // Skip certain directories
            if (file === 'node_modules' || file === '.git' || file === 'dist' || file === '.build_temp') {
                continue;
            }
            getAllFiles(filePath, fileList);
        } else {
            fileList.push(filePath);
        }
    }

    return fileList;
}

/**
 * Count lines in a file (excluding blank lines)
 */
function countLines(filePath) {
    try {
        const content = fs.readFileSync(filePath, 'utf8');
        const lines = content.split('\n');
        const totalLines = lines.length;
        const codeLines = lines.filter(line => line.trim().length > 0).length;
        const blankLines = totalLines - codeLines;

        return { total: totalLines, code: codeLines, blank: blankLines };
    } catch (err) {
        return { total: 0, code: 0, blank: 0 };
    }
}

/**
 * Get file extension
 */
function getExtension(filePath) {
    const ext = path.extname(filePath).toLowerCase();
    return ext || 'no-extension';
}

/**
 * Generate statistics
 */
function generateStats() {
    console.log();
    console.log(colors.cyan + '═══════════════════════════════════════════════════════════════════════');
    console.log('FS25_UsedPlus - Codebase Statistics');
    console.log('═══════════════════════════════════════════════════════════════════════' + colors.reset);
    console.log();

    // Get all files
    const allFiles = getAllFiles(MOD_ROOT);

    // Statistics by file type
    const filesByType = {};
    const linesByType = {};
    const directoryCounts = {};

    for (const filePath of allFiles) {
        const ext = getExtension(filePath);
        const relativePath = path.relative(MOD_ROOT, filePath);
        const dir = path.dirname(relativePath).split(path.sep)[0];

        // Count by type
        if (!filesByType[ext]) {
            filesByType[ext] = [];
            linesByType[ext] = { total: 0, code: 0, blank: 0 };
        }
        filesByType[ext].push(relativePath);

        // Count lines for code files
        if (['.lua', '.js', '.xml', '.md', '.json'].includes(ext)) {
            const lines = countLines(filePath);
            linesByType[ext].total += lines.total;
            linesByType[ext].code += lines.code;
            linesByType[ext].blank += lines.blank;
        }

        // Count by directory
        directoryCounts[dir] = (directoryCounts[dir] || 0) + 1;
    }

    // Summary
    console.log(colors.bold + 'Overall Summary:' + colors.reset);
    console.log(`  Total Files:     ${allFiles.length}`);
    console.log(`  Total Size:      ${formatBytes(getTotalSize(allFiles))}`);
    console.log();

    // Files by type
    console.log(colors.bold + 'Files by Type:' + colors.reset);
    console.log('  Type       | Count |   Lines (Total / Code / Blank)');
    console.log('  ─────────────────────────────────────────────────────────');

    const sortedTypes = Object.keys(filesByType).sort((a, b) => {
        return filesByType[b].length - filesByType[a].length;
    });

    for (const ext of sortedTypes) {
        const count = filesByType[ext].length;
        const lines = linesByType[ext];
        const typeName = ext === 'no-extension' ? '(none)' : ext;

        if (lines.total > 0) {
            console.log(`  ${typeName.padEnd(10)} | ${String(count).padStart(5)} | ${String(lines.total).padStart(7)} / ${String(lines.code).padStart(6)} / ${String(lines.blank).padStart(6)}`);
        } else {
            console.log(`  ${typeName.padEnd(10)} | ${String(count).padStart(5)} |       -`);
        }
    }
    console.log();

    // Code-only summary
    const luaLines = linesByType['.lua'] || { total: 0, code: 0, blank: 0 };
    const xmlLines = linesByType['.xml'] || { total: 0, code: 0, blank: 0 };
    const jsLines = linesByType['.js'] || { total: 0, code: 0, blank: 0 };

    console.log(colors.bold + 'Code Metrics:' + colors.reset);
    console.log(`  Lua Code:        ${luaLines.code.toLocaleString()} lines (${filesByType['.lua']?.length || 0} files)`);
    console.log(`  XML:             ${xmlLines.code.toLocaleString()} lines (${filesByType['.xml']?.length || 0} files)`);
    console.log(`  JavaScript:      ${jsLines.code.toLocaleString()} lines (${filesByType['.js']?.length || 0} files)`);
    console.log(`  ${colors.green}Total Code:      ${(luaLines.code + xmlLines.code + jsLines.code).toLocaleString()} lines${colors.reset}`);
    console.log();

    // Directory breakdown
    console.log(colors.bold + 'Files by Directory:' + colors.reset);
    const sortedDirs = Object.keys(directoryCounts).sort((a, b) => {
        return directoryCounts[b] - directoryCounts[a];
    });

    for (const dir of sortedDirs.slice(0, 15)) {
        const count = directoryCounts[dir];
        console.log(`  ${dir.padEnd(25)} ${String(count).padStart(4)} files`);
    }

    if (sortedDirs.length > 15) {
        console.log(`  ... and ${sortedDirs.length - 15} more directories`);
    }
    console.log();

    // Special counts
    console.log(colors.bold + 'Feature Counts:' + colors.reset);

    // Count dialogs (normalize path separators)
    const dialogXmlFiles = filesByType['.xml']?.filter(f => {
        const normalized = f.replace(/\\/g, '/');
        return normalized.includes('gui/') && !normalized.includes('Frame.xml');
    }) || [];
    const dialogLuaFiles = filesByType['.lua']?.filter(f => {
        const normalized = f.replace(/\\/g, '/');
        return normalized.includes('src/gui/') && normalized.includes('Dialog.lua');
    }) || [];
    console.log(`  GUI Dialogs:     ${dialogXmlFiles.length} XML + ${dialogLuaFiles.length} Lua`);

    // Count managers
    const managerFiles = filesByType['.lua']?.filter(f => {
        const normalized = f.replace(/\\/g, '/');
        return normalized.includes('managers/') && normalized.endsWith('Manager.lua');
    }) || [];
    console.log(`  Manager Classes: ${managerFiles.length}`);

    // Count events
    const eventFiles = filesByType['.lua']?.filter(f => {
        const normalized = f.replace(/\\/g, '/');
        return normalized.includes('events/') && normalized.includes('Event.lua');
    }) || [];
    console.log(`  Network Events:  ${eventFiles.length}`);

    // Count specializations
    const specFiles = filesByType['.lua']?.filter(f => {
        const normalized = f.replace(/\\/g, '/');
        return normalized.includes('specializations/');
    }) || [];
    console.log(`  Specializations: ${specFiles.length}`);

    // Translation files
    const translationFiles = filesByType['.xml']?.filter(f => {
        const normalized = f.replace(/\\/g, '/');
        return normalized.includes('translations/translation_');
    }) || [];
    console.log(`  Translations:    ${translationFiles.length} languages`);

    // Get translation key count from English file
    const enTransFile = path.join(MOD_ROOT, 'translations', 'translation_en.xml');
    if (fs.existsSync(enTransFile)) {
        const content = fs.readFileSync(enTransFile, 'utf8');
        const keyMatches = content.match(/<e k="/g);
        const keyCount = keyMatches ? keyMatches.length : 0;
        console.log(`  Translation Keys: ${keyCount}`);
    }

    console.log();
    console.log(colors.cyan + '═══════════════════════════════════════════════════════════════════════' + colors.reset);
    console.log();
}

/**
 * Get total size of files
 */
function getTotalSize(files) {
    let total = 0;
    for (const file of files) {
        try {
            const stat = fs.statSync(file);
            total += stat.size;
        } catch (err) {
            // Skip
        }
    }
    return total;
}

/**
 * Format bytes to human readable
 */
function formatBytes(bytes) {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    if (bytes < 1024 * 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + ' MB';
    return (bytes / 1024 / 1024 / 1024).toFixed(1) + ' GB';
}

// Run
generateStats();
