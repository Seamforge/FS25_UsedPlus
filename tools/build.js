#!/usr/bin/env node
/**
 * UsedPlus ModHub Build Script
 * Creates a clean .zip file ready for ModHub submission
 *
 * Version format: major.minor.patch.build (e.g., 2.12.1.0)
 *   - build number auto-increments on every build (no args needed)
 *   - --patch/--minor/--major bump that component and reset build to 0
 *
 * Usage:
 *   node build.js              Auto-increment build number (2.12.0.3 → 2.12.0.4)
 *   node build.js --patch      Bump patch (2.12.0.3 → 2.12.1.0) then build
 *   node build.js --minor      Bump minor (2.12.0.3 → 2.13.0.0) then build
 *   node build.js --major      Bump major (2.12.0.3 → 3.0.0.0) then build
 *   node build.js --deploy     (Default behavior - always copies to mods folder)
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const MOD_NAME = 'FS25_UsedPlus';
const SCRIPT_DIR = __dirname;
const MOD_DIR = path.dirname(SCRIPT_DIR);
const OUTPUT_DIR = path.join(MOD_DIR, 'dist');
const MODS_FOLDER = path.join(
    process.env.USERPROFILE || process.env.HOME,
    'OneDrive', 'Documents', 'My Games', 'FarmingSimulator2025', 'mods'
);

// Patterns to exclude (relative paths)
const EXCLUDE_PATTERNS = [
    /^(?!gui\/icons\/).*\.png$/i,  // Exclude PNGs EXCEPT in gui/icons/
    /\.psd$/i,
    /\.xcf$/i,
    /\.bak$/i,
    /\.log$/i,
    /\.md$/i,
    /\.py$/i,
    /^\.git/,
    /^\.vscode/,
    /^\.idea/,
    /^node_modules/,
    /^dist\//,
    /^\.build_temp/,
    /^tools\//,
    /^FS25_AI_Coding_Reference/,
    /^docs\//,
    /package\.json$/,
    /package-lock\.json$/,
    /\.translation-sync\.json$/,
    /icon_old\.dds\.bak$/,
];

function shouldExclude(relativePath) {
    const normalized = relativePath.replace(/\\/g, '/');
    return EXCLUDE_PATTERNS.some(pattern => pattern.test(normalized));
}

function getAllFiles(dir, baseDir = dir) {
    const files = [];
    const entries = fs.readdirSync(dir, { withFileTypes: true });

    for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        const relativePath = path.relative(baseDir, fullPath);

        if (shouldExclude(relativePath)) continue;

        if (entry.isDirectory()) {
            files.push(...getAllFiles(fullPath, baseDir));
        } else {
            files.push({ fullPath, relativePath });
        }
    }
    return files;
}

function getVersion() {
    const modDescPath = path.join(MOD_DIR, 'modDesc.xml');
    const content = fs.readFileSync(modDescPath, 'utf8');
    const match = content.match(/<version>([^<]+)<\/version>/);
    return match ? match[1] : 'unknown';
}

function getTimestamp() {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const hours = String(now.getHours()).padStart(2, '0');
    const minutes = String(now.getMinutes()).padStart(2, '0');
    const seconds = String(now.getSeconds()).padStart(2, '0');
    return `${year}${month}${day}_${hours}${minutes}${seconds}`;
}

function parseArgs() {
    const args = process.argv.slice(2);
    const options = {
        bumpType: null // 'major', 'minor', 'patch', or null (auto-increment build)
    };

    for (const arg of args) {
        const normalized = arg.toLowerCase().replace(/^-+/, '');
        if (normalized === 'major') {
            options.bumpType = 'major';
        } else if (normalized === 'minor') {
            options.bumpType = 'minor';
        } else if (normalized === 'patch') {
            options.bumpType = 'patch';
        } else if (normalized === 'deploy') {
            // Always deploys — flag accepted for compatibility
        } else if (normalized === 'help' || normalized === 'h') {
            console.log(`
Usage: node build.js [options]

Version format: major.minor.patch.build (e.g., 2.12.1.0)

Options:
  --patch    Bump patch version (2.12.0.3 → 2.12.1.0) then build
  --minor    Bump minor version (2.12.0.3 → 2.13.0.0) then build
  --major    Bump major version (2.12.0.3 → 3.0.0.0) then build
  --deploy   Copy to mods folder (default behavior, always on)
  --help     Show this help message

If no version option is provided, auto-increments the build number.
`);
            process.exit(0);
        }
    }

    return options;
}

function bumpVersion(bumpType) {
    const modDescPath = path.join(MOD_DIR, 'modDesc.xml');
    let content = fs.readFileSync(modDescPath, 'utf8');

    const match = content.match(/<version>([^<]+)<\/version>/);
    if (!match) {
        throw new Error('Could not find version in modDesc.xml');
    }

    const currentVersion = match[1];
    const parts = currentVersion.split('.').map(Number);

    // Ensure we have exactly 4 parts (major.minor.patch.build)
    while (parts.length < 4) {
        parts.push(0);
    }

    let [major, minor, patch, build] = parts;
    const oldVersion = `${major}.${minor}.${patch}.${build}`;

    switch (bumpType) {
        case 'major':
            major++;
            minor = 0;
            patch = 0;
            build = 0;
            break;
        case 'minor':
            minor++;
            patch = 0;
            build = 0;
            break;
        case 'patch':
            patch++;
            build = 0;
            break;
        default:
            // No explicit bump — auto-increment build number
            build++;
            break;
    }

    const newVersion = `${major}.${minor}.${patch}.${build}`;

    // Update modDesc.xml
    content = content.replace(
        /<version>[^<]+<\/version>/,
        `<version>${newVersion}</version>`
    );
    fs.writeFileSync(modDescPath, content, 'utf8');

    // Update README.md version badge (show major.minor.patch for display)
    updateReadmeVersion(`${major}.${minor}.${patch}`);

    // Update UsedPlusAPI.MOD_VERSION so in-game display shows full build version
    updateApiVersion(newVersion);

    return { oldVersion, newVersion };
}

function updateReadmeVersion(newVersion) {
    const readmePath = path.join(MOD_DIR, 'README.md');

    if (!fs.existsSync(readmePath)) {
        console.log('  Warning: README.md not found, skipping version update');
        return;
    }

    let content = fs.readFileSync(readmePath, 'utf8');

    // Match the version badge line: **v1.2.3** | FS25 | ...
    const versionBadgeRegex = /^\*\*v[\d.]+\*\*(\s*\|.*)$/m;

    if (versionBadgeRegex.test(content)) {
        content = content.replace(versionBadgeRegex, `**v${newVersion}**$1`);
        fs.writeFileSync(readmePath, content, 'utf8');
        console.log(`  README:    v${newVersion} (updated)`);
    } else {
        console.log('  Warning: Could not find version badge in README.md');
    }
}

function updateApiVersion(newVersion) {
    const apiPath = path.join(MOD_DIR, 'src', 'utils', 'UsedPlusAPI.lua');

    if (!fs.existsSync(apiPath)) {
        console.log('  Warning: UsedPlusAPI.lua not found, skipping version update');
        return;
    }

    let content = fs.readFileSync(apiPath, 'utf8');

    // Match: UsedPlusAPI.MOD_VERSION = "x.y.z" or "x.y.z.b"
    const versionRegex = /^(UsedPlusAPI\.MOD_VERSION\s*=\s*")[\d.]+(")$/m;

    if (versionRegex.test(content)) {
        content = content.replace(versionRegex, `$1${newVersion}$2`);
        fs.writeFileSync(apiPath, content, 'utf8');
        console.log(`  API:       v${newVersion} (updated)`);
    } else {
        console.log('  Warning: Could not find MOD_VERSION in UsedPlusAPI.lua');
    }
}

function createZipWithArchiver(files, outputPath) {
    return new Promise((resolve, reject) => {
        const archiver = require('archiver');

        // Remove existing file if present
        if (fs.existsSync(outputPath)) {
            fs.unlinkSync(outputPath);
        }

        const output = fs.createWriteStream(outputPath);
        const archive = archiver('zip', {
            zlib: { level: 9 } // Maximum compression
        });

        output.on('close', () => {
            resolve(archive.pointer());
        });

        archive.on('error', (err) => {
            reject(err);
        });

        archive.pipe(output);

        // Add files with forward slashes (Unix-style paths for FS25 compatibility)
        for (const file of files) {
            const zipPath = file.relativePath.replace(/\\/g, '/');
            archive.file(file.fullPath, { name: zipPath });
        }

        archive.finalize();
    });
}

async function main() {
    const options = parseArgs();

    console.log('');
    console.log('============================================');
    console.log('  UsedPlus ModHub Build Script');
    console.log('============================================');

    // Always bump version — auto-increment build number if no explicit bump type
    const versionBumped = bumpVersion(options.bumpType);
    if (options.bumpType) {
        console.log(`  Bumping:   ${options.bumpType} (${versionBumped.oldVersion} → ${versionBumped.newVersion})`);
    } else {
        console.log(`  Build:     ${versionBumped.oldVersion} → ${versionBumped.newVersion}`);
    }

    const version = getVersion();
    const timestamp = getTimestamp();
    const zipName = `${MOD_NAME}_v${version}_${timestamp}.zip`;
    const outputPath = path.join(OUTPUT_DIR, zipName);

    console.log(`  Version:   ${version}`);
    console.log(`  Timestamp: ${timestamp}`);
    console.log(`  Output:    ${zipName}`);
    console.log('============================================');
    console.log('');

    // Create output directory
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });

    // Collect files
    console.log('Collecting files...');
    const files = getAllFiles(MOD_DIR);
    console.log(`  Found ${files.length} files to include`);
    console.log('');

    // Create zip with archiver (uses forward slashes for FS25 compatibility)
    console.log('Creating zip file...');
    const size = await createZipWithArchiver(files, outputPath);
    const sizeKB = (size / 1024).toFixed(2);
    const sizeMB = (size / 1024 / 1024).toFixed(2);

    // Copy to FS25 mods folder
    const modsDestPath = path.join(MODS_FOLDER, `${MOD_NAME}.zip`);
    let copiedToMods = false;

    if (fs.existsSync(MODS_FOLDER)) {
        console.log('');
        console.log(`Copying to mods folder...`);
        fs.copyFileSync(outputPath, modsDestPath);
        copiedToMods = true;
        console.log(`  Copied to: ${modsDestPath}`);
    } else {
        console.log('');
        console.log(`Warning: Mods folder not found at ${MODS_FOLDER}`);
        console.log('  Skipping auto-copy to mods folder');
    }

    console.log('');
    console.log('============================================');
    console.log('  Build Complete!');
    console.log('============================================');
    console.log(`  Output: ${outputPath}`);
    console.log(`  Size:   ${sizeKB} KB (${sizeMB} MB)`);
    console.log(`  Files:  ${files.length}`);
    if (copiedToMods) {
        console.log(`  Mods:   ${modsDestPath}`);
    }
    console.log('============================================');
    console.log('');
    console.log('To test with GIANTS TestRunner:');
    console.log(`  TestRunner_public.exe "${outputPath}"`);
    console.log('');

    // Remind about CHANGELOG if an explicit version bump was requested
    if (options.bumpType) {
        console.log('--------------------------------------------');
        console.log('  REMINDER: Update CHANGELOG.md');
        console.log('--------------------------------------------');
        console.log(`  Add entry for [${versionBumped.newVersion}] with:`);
        console.log('  - What changed');
        console.log('  - What was fixed');
        console.log('  - What was added');
        console.log('');
    }
}

main().catch(err => {
    console.error('Build failed:', err);
    process.exit(1);
});
