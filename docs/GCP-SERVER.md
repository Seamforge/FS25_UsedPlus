# GCP Dedicated Server (FS25 Testing)

## Infrastructure Summary

| Resource | Value |
|----------|-------|
| **GCP Project** | `fs25-dedicated` |
| **Billing Account** | `017B40-04F445-C6229C` |
| **VM** | `fs25-server` (e2-medium, 2 vCPU, 4GB RAM) |
| **Zone** | `us-east1-b` |
| **OS** | Debian 12 (bookworm) |
| **Disk** | 150GB standard persistent |
| **Static IP** | `35.229.101.149` |
| **Docker Image** | `toetje585/arch-fs25server:latest` (Wine-based FS25 container) |
| **VM Username** | `shouden` |
| **Monthly Cost** | ~$35 |
| **FS25 Version** | 1.16.0.3 (GIANTS license, NOT Steam) |
| **Status** | Fully operational (as of 2026-02-22) |

## Access Points

| Service | URL / Command |
|---------|---------------|
| **Game Server** | `35.229.101.149:10823` (connect with FS25 game client) |
| **SSH (direct)** | `ssh -i ~/.ssh/google_compute_engine shouden@35.229.101.149` |
| **SSH (gcloud)** | `gcloud compute ssh fs25-server --zone=us-east1-b --project=fs25-dedicated` |
| **VNC** | `http://35.229.101.149:6080/vnc.html` (password: `UsedPlusDev2026`) — for manual setup/debugging only |

## Firewall Rules

| Rule | Ports | Source |
|------|-------|--------|
| `fs25-game-port` | TCP/UDP 10823 | `0.0.0.0/0` (public) |
| `fs25-web-admin` | TCP 7999, 8443 | Your IP only |
| `fs25-vnc-setup` | TCP 5900, 6080, 7999 | Your IP only |
| `fs25-iap-ssh` | TCP 22 | `35.235.240.0/20` (Google IAP) |
| `fs25-ssh-whitelist` | TCP 22 | Your IP only |

Only game port (10823) is public. If your IP changes:
```bash
for RULE in fs25-ssh-whitelist fs25-vnc-setup fs25-web-admin; do
  "C:/Users/mrath/AppData/Local/Google/Cloud SDK/google-cloud-sdk/bin/gcloud.cmd" compute firewall-rules update $RULE --source-ranges=NEW_IP/32 --project=fs25-dedicated
done
```

## GIANTS License (NOT Steam)

The server uses a **GIANTS-purchased license** (not Steam). Steam's DRM prevents dedicated server use.

- **Key format:** `DSR23-XXXXX-XXXXX-XXXXX` (purchased from `eshop.giants-software.com`)
- **License files:** `config/FarmingSimulator2025/AHC_63805.dat` + `AHT_63805.dat`
- **Activation:** Run `FarmingSimulator2025.exe` via VNC → GIANTS launcher prompts for key
- **Product ID:** B7094197 (base game)
- **Steam App ID:** 2300320 (for reference only — NOT usable for dedicated server without Steam client)

**If re-activation is needed:** Open VNC, run the GIANTS launcher, enter the key.

## Server Architecture

```
~/fs25-server/                           (on GCP VM)
├── docker-compose.yml                   (AUTOSTART_SERVER=true)
├── config/ → /opt/fs25/config           (server config, savegames, mods, logs)
│   └── FarmingSimulator2025/
│       ├── mods/FS25_UsedPlus.zip       (deployed mod)
│       ├── AHC_63805.dat, AHT_63805.dat (GIANTS license)
│       └── log_YYYY-MM-DD_HH-MM-SS.txt (game logs — timestamped, NOT log.txt)
├── game/ → /opt/fs25/game               (FS25 game files, ~55GB)
│   └── Farming Simulator 2025/
│       ├── FarmingSimulator2025.exe      (GIANTS launcher, 9.6MB)
│       ├── x64/FarmingSimulator2025Game.exe (game engine, 19MB)
│       └── dedicatedServer.exe          (web admin → launches game engine)
├── dlc/ → /opt/fs25/dlc
└── installer/ → /opt/fs25/installer
```

**How the container works:** Creates fresh Wine prefix on each start → symlinks game/config directories → runs `dedicatedServer.exe` via Wine → web admin on port 7999 → auto-starts game engine with `-server` flag.

## gcloud CLI Quoting (CRITICAL)

The gcloud path has spaces: `"C:/Users/mrath/AppData/Local/Google/Cloud SDK/google-cloud-sdk/bin/gcloud.cmd"`. Double-quoted flag values conflict with the outer path quotes.

**Solution:** Use direct SSH for commands with spaces:
```bash
ssh -i ~/.ssh/google_compute_engine shouden@35.229.101.149 "any command with spaces"
```

For gcloud commands, use single-quoted or `=`-joined flag values (no spaces).

## Server Management

```bash
# Docker management (via SSH)
ssh -i ~/.ssh/google_compute_engine shouden@35.229.101.149 "cd ~/fs25-server && docker compose restart"
ssh -i ~/.ssh/google_compute_engine shouden@35.229.101.149 "cd ~/fs25-server && docker compose down"
ssh -i ~/.ssh/google_compute_engine shouden@35.229.101.149 "cd ~/fs25-server && docker compose up -d"
ssh -i ~/.ssh/google_compute_engine shouden@35.229.101.149 "docker logs arch-fs25server --tail=50"
```

## Uploading Mods

Mods go in `config/FarmingSimulator2025/mods/` (NOT top-level `mods/`).
```bash
scp -i ~/.ssh/google_compute_engine "C:/path/to/mod.zip" shouden@35.229.101.149:~/fs25-server/config/FarmingSimulator2025/mods/
```

## Shutting Down (Save Money)

```bash
# Stop VM (disk still charges ~$6/mo for 150GB)
"C:/Users/mrath/AppData/Local/Google/Cloud SDK/google-cloud-sdk/bin/gcloud.cmd" compute instances stop fs25-server --zone=us-east1-b --project=fs25-dedicated

# Start VM back up
"C:/Users/mrath/AppData/Local/Google/Cloud SDK/google-cloud-sdk/bin/gcloud.cmd" compute instances start fs25-server --zone=us-east1-b --project=fs25-dedicated
```

## Local Reference Server

A working FS25 dedicated server also exists on the local network at `interstitch.shouden.us` (192.168.88.150), RHEL/CentOS 9, same Docker container. SSH: `ssh mrathbone@192.168.88.150`. Game files were originally rsync'd from here to GCP.

---

## Dev Iteration Workflow

### One-Command Build + Deploy

```bash
# Build mod, deploy locally, upload to GCP, restart server — all in one:
node tools/build.js --gcp

# Combine with version bump:
node tools/build.js --patch --gcp
```

### Individual Deploy Commands

```bash
# Upload latest mod zip + restart server (uses local mods folder build)
node tools/deploy-gcp.js

# Just restart the server (no re-upload — useful after config changes)
node tools/deploy-gcp.js --restart

# Tail the server log in real-time (Ctrl+C to stop)
node tools/deploy-gcp.js --log

# Check server status (process, container, disk, mod info)
node tools/deploy-gcp.js --status

# Clear the server log (fresh start for next test session)
node tools/deploy-gcp.js --log-clear
```

### Typical Dev Session

1. Edit code locally
2. `node tools/build.js --gcp` (builds + deploys + restarts)
3. Connect with game client to `35.229.101.149:10823`
4. `node tools/deploy-gcp.js --log` in a second terminal (monitor logs)
5. Test, find issues, `Ctrl+C` the log tail
6. Edit code, repeat from step 2

### Troubleshooting

| Issue | Fix |
|-------|-----|
| "Cannot connect" | VM may be stopped — start it with gcloud |
| "SSH key not found" | Run `gcloud compute ssh fs25-server ...` once to generate keys |
| Server won't start | Check `--log` for Wine/crash errors |
| Mod not loading | Check `--status` to verify mod zip was uploaded |
| Stale log | Run `--log-clear` before testing for clean output |
