#!/usr/bin/env node
/**
 * UsedPlus GCP Dev Server Deployment Tool
 * Manages mod deployment, server restart, and log monitoring on the GCP test server.
 *
 * Usage:
 *   node deploy-gcp.js              Upload latest mod zip + restart server
 *   node deploy-gcp.js --restart    Just restart server (no upload)
 *   node deploy-gcp.js --log        Tail the server log (Ctrl+C to stop)
 *   node deploy-gcp.js --status     Check server status, disk, mod info
 *   node deploy-gcp.js --log-clear  Clear server log for fresh test run
 */

const fs = require('fs');
const path = require('path');
const { execSync, spawn } = require('child_process');

// ── GCP Server Configuration ───────────────────────────────────────────────
const GCP_HOST = '35.229.101.149';
const GCP_USER = 'shouden';
const SSH_KEY = path.join(process.env.USERPROFILE || process.env.HOME, '.ssh', 'google_compute_engine');
const CONTAINER_NAME = 'arch-fs25server';

// Remote paths
const REMOTE_MODS_DIR = '~/fs25-server/config/FarmingSimulator2025/mods';
const REMOTE_LOG_FILE = '~/fs25-server/config/FarmingSimulator2025/dedicated_server/logs/server.log';
const REMOTE_MOD_ZIP = `${REMOTE_MODS_DIR}/FS25_UsedPlus.zip`;

// Local paths
const MOD_NAME = 'FS25_UsedPlus';
const LOCAL_MODS_FOLDER = path.join(
    process.env.USERPROFILE || process.env.HOME,
    'OneDrive', 'Documents', 'My Games', 'FarmingSimulator2025', 'mods'
);
const LOCAL_MOD_ZIP = path.join(LOCAL_MODS_FOLDER, `${MOD_NAME}.zip`);

// SSH/SCP common options
const SSH_OPTS = ['-i', SSH_KEY, '-o', 'StrictHostKeyChecking=no', '-o', 'ConnectTimeout=10'];

// ── Helpers ─────────────────────────────────────────────────────────────────

function ssh(command, options = {}) {
    const args = ['ssh', ...SSH_OPTS, `${GCP_USER}@${GCP_HOST}`, command];
    const cmd = args.join(' ');
    try {
        return execSync(cmd, {
            encoding: 'utf8',
            timeout: options.timeout || 30000,
            stdio: options.stdio || 'pipe'
        }).trim();
    } catch (err) {
        if (options.ignoreError) return '';
        throw err;
    }
}

function scp(localPath, remotePath) {
    const cmd = `scp ${SSH_OPTS.join(' ')} "${localPath}" ${GCP_USER}@${GCP_HOST}:${remotePath}`;
    execSync(cmd, { encoding: 'utf8', stdio: 'inherit', timeout: 120000 });
}

function preflight() {
    // Check SSH key exists
    if (!fs.existsSync(SSH_KEY)) {
        console.error(`ERROR: SSH key not found at ${SSH_KEY}`);
        console.error('  Run: gcloud compute ssh fs25-server --zone=us-east1-b --project=fs25-dedicated');
        console.error('  This will generate the SSH key pair automatically.');
        process.exit(1);
    }

    // Quick SSH connectivity check
    try {
        ssh('echo ok', { timeout: 15000 });
    } catch {
        console.error(`ERROR: Cannot connect to ${GCP_HOST}`);
        console.error('  Possible causes:');
        console.error('  - VM is stopped (start it: gcloud compute instances start fs25-server ...)');
        console.error('  - Your IP changed (update firewall rules)');
        console.error('  - SSH key issue');
        process.exit(1);
    }
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

// ── Commands ────────────────────────────────────────────────────────────────

async function deploy() {
    console.log('');
    console.log('============================================');
    console.log('  UsedPlus GCP Deploy');
    console.log('============================================');
    console.log('');

    // Verify local mod zip exists
    if (!fs.existsSync(LOCAL_MOD_ZIP)) {
        console.error(`ERROR: Mod zip not found at ${LOCAL_MOD_ZIP}`);
        console.error('  Run: node tools/build.js');
        process.exit(1);
    }

    const stats = fs.statSync(LOCAL_MOD_ZIP);
    const sizeMB = (stats.size / 1024 / 1024).toFixed(2);
    const modTime = stats.mtime.toLocaleString();
    console.log(`  Local mod:  ${LOCAL_MOD_ZIP}`);
    console.log(`  Size:       ${sizeMB} MB`);
    console.log(`  Modified:   ${modTime}`);
    console.log('');

    preflight();

    // Ensure remote mods directory exists
    console.log('Ensuring remote mods directory exists...');
    ssh(`mkdir -p ${REMOTE_MODS_DIR}`);

    // Upload mod zip
    console.log('Uploading mod zip to GCP server...');
    scp(LOCAL_MOD_ZIP, REMOTE_MOD_ZIP);
    console.log('  Upload complete.');
    console.log('');

    // Restart the server process
    await restartServer();
}

async function restartServer() {
    console.log('Restarting FS25 server process...');

    // Kill existing dedicatedServer.exe (if running)
    const killResult = ssh(
        `docker exec ${CONTAINER_NAME} pkill -f dedicatedServer.exe 2>/dev/null || true`,
        { ignoreError: true }
    );
    console.log('  Stopped dedicatedServer.exe');

    // Wait for cleanup
    console.log('  Waiting for cleanup (2s)...');
    await sleep(2000);

    // Relaunch via the container's startup script
    console.log('  Launching dedicatedServer.exe...');
    ssh(
        `docker exec -d ${CONTAINER_NAME} /usr/local/bin/start_fs25.sh`,
        { ignoreError: true }
    );

    // Poll for server to come up (check if process is running)
    console.log('  Waiting for server to start...');
    const maxWait = 30;
    let started = false;
    for (let i = 0; i < maxWait; i++) {
        await sleep(1000);
        const result = ssh(
            `docker exec ${CONTAINER_NAME} pgrep -f dedicatedServer.exe 2>/dev/null || true`,
            { ignoreError: true }
        );
        if (result && result.trim().length > 0) {
            started = true;
            console.log(`  Server process detected after ${i + 1}s`);
            break;
        }
        if ((i + 1) % 5 === 0) {
            console.log(`  Still waiting... (${i + 1}s)`);
        }
    }

    if (!started) {
        console.log('  WARNING: Server process not detected after 30s');
        console.log('  Check manually: node tools/deploy-gcp.js --status');
    }

    // Show last few lines of log
    console.log('');
    console.log('--- Server Log (last 10 lines) ---');
    const logTail = ssh(`tail -10 ${REMOTE_LOG_FILE} 2>/dev/null || echo "(no log file yet)"`, { ignoreError: true });
    console.log(logTail);
    console.log('----------------------------------');

    console.log('');
    console.log('============================================');
    console.log('  Deploy complete!');
    console.log('============================================');
    console.log('  Monitor logs:  node tools/deploy-gcp.js --log');
    console.log('  Check status:  node tools/deploy-gcp.js --status');
    console.log('============================================');
    console.log('');
}

function tailLog() {
    console.log(`Tailing server log on ${GCP_HOST} (Ctrl+C to stop)...`);
    console.log('');

    preflight();

    const child = spawn('ssh', [
        ...SSH_OPTS,
        `${GCP_USER}@${GCP_HOST}`,
        `tail -f ${REMOTE_LOG_FILE} 2>/dev/null || echo "Log file not found at ${REMOTE_LOG_FILE}"`
    ], {
        stdio: 'inherit'
    });

    // Handle clean Ctrl+C exit
    process.on('SIGINT', () => {
        child.kill('SIGTERM');
        console.log('\nLog tail stopped.');
        process.exit(0);
    });

    child.on('exit', (code) => {
        process.exit(code || 0);
    });
}

function status() {
    console.log('');
    console.log('============================================');
    console.log('  GCP Server Status');
    console.log('============================================');
    console.log('');

    preflight();

    // Check if dedicatedServer.exe is running
    console.log('Server Process:');
    const pgrep = ssh(
        `docker exec ${CONTAINER_NAME} pgrep -f dedicatedServer.exe 2>/dev/null || true`,
        { ignoreError: true }
    );
    if (pgrep && pgrep.trim().length > 0) {
        console.log('  dedicatedServer.exe: RUNNING (PID: ' + pgrep.trim() + ')');
    } else {
        console.log('  dedicatedServer.exe: NOT RUNNING');
    }
    console.log('');

    // Container status
    console.log('Container:');
    const containerInfo = ssh(
        `docker ps --filter name=${CONTAINER_NAME} --format "  Status: {{.Status}}\\n  Created: {{.CreatedAt}}" 2>/dev/null || echo "  Container not found"`,
        { ignoreError: true }
    );
    console.log(containerInfo.replace(/^"|"$/gm, ''));
    console.log('');

    // Disk usage
    console.log('Disk Usage:');
    const disk = ssh('df -h /home/shouden/fs25-server/ | tail -1', { ignoreError: true });
    if (disk) {
        const parts = disk.split(/\s+/);
        console.log(`  Total: ${parts[1] || '?'}  Used: ${parts[2] || '?'}  Avail: ${parts[3] || '?'}  Use%: ${parts[4] || '?'}`);
    }
    console.log('');

    // Mod file info
    console.log('Deployed Mod:');
    const modInfo = ssh(`ls -la ${REMOTE_MOD_ZIP} 2>/dev/null || echo "  No mod zip found"`, { ignoreError: true });
    if (modInfo.includes('No mod zip')) {
        console.log('  No mod zip found');
    } else {
        const parts = modInfo.split(/\s+/);
        const size = parts[4] ? (parseInt(parts[4]) / 1024 / 1024).toFixed(2) + ' MB' : '?';
        const date = parts.slice(5, 8).join(' ');
        console.log(`  Size: ${size}  Date: ${date}`);
    }
    console.log('');

    // Last 5 lines of server log
    console.log('Server Log (last 5 lines):');
    const logTail = ssh(`tail -5 ${REMOTE_LOG_FILE} 2>/dev/null || echo (no log file)`, { ignoreError: true });
    console.log('  ' + logTail.replace(/\n/g, '\n  '));

    console.log('');
    console.log('============================================');
    console.log('');
}

function clearLog() {
    preflight();

    console.log(`Clearing server log on ${GCP_HOST}...`);
    ssh(`truncate -s 0 ${REMOTE_LOG_FILE} 2>/dev/null || echo "Log file not found"`);
    console.log('  Log cleared.');
    console.log('');
}

// ── CLI Parsing ─────────────────────────────────────────────────────────────

function parseArgs() {
    const args = process.argv.slice(2);

    if (args.length === 0) return 'deploy';

    const arg = args[0].toLowerCase().replace(/^-+/, '');

    switch (arg) {
        case 'restart':
            return 'restart';
        case 'log':
            return 'log';
        case 'status':
            return 'status';
        case 'log-clear':
        case 'logclear':
        case 'clear-log':
        case 'clearlog':
            return 'log-clear';
        case 'help':
        case 'h':
            console.log(`
Usage: node deploy-gcp.js [command]

Commands:
  (none)       Upload latest mod zip + restart server (default)
  --restart    Just restart the server (no upload)
  --log        Tail the server log in real-time (Ctrl+C to stop)
  --status     Show server status, disk usage, mod info
  --log-clear  Clear the server log file

Configuration:
  Host:      ${GCP_HOST}
  User:      ${GCP_USER}
  SSH Key:   ${SSH_KEY}
  Container: ${CONTAINER_NAME}
  Local Mod: ${LOCAL_MOD_ZIP}
`);
            process.exit(0);
        default:
            console.error(`Unknown command: ${args[0]}`);
            console.error('Run with --help to see available commands.');
            process.exit(1);
    }
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
    const command = parseArgs();

    switch (command) {
        case 'deploy':
            await deploy();
            break;
        case 'restart':
            preflight();
            console.log('');
            console.log('============================================');
            console.log('  UsedPlus GCP Restart');
            console.log('============================================');
            console.log('');
            await restartServer();
            break;
        case 'log':
            tailLog();
            break;
        case 'status':
            status();
            break;
        case 'log-clear':
            clearLog();
            break;
    }
}

main().catch(err => {
    console.error('Deploy failed:', err.message || err);
    process.exit(1);
});
