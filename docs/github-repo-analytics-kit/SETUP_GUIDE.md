# GitHub Repository Analytics Kit

**Add live traffic dashboards, download tracking, and engagement metrics to any GitHub repository.**

No third-party services. No external dependencies. Just GitHub Actions + matplotlib.

---

## What You Get

| Chart | What It Shows |
|-------|---------------|
| **Views & Clones** | Daily page views and git clones (preserved beyond GitHub's 14-day limit) |
| **Release Acquisition** | Zip downloads + git clones per release era |
| **Visitor Engagement** | Pages per visitor (are people exploring or bouncing?) |
| **Conversion Funnel** | What % of visitors actually download your project |
| **Traffic Referrers** | Which websites and search engines send you traffic |
| **Repository Growth** | Stars, forks, and watchers over time |

Charts are generated with dark GitHub-themed styling and stored on an orphan branch. Reference them from your README or a docs page — they auto-update.

---

## Setup (Under 5 Minutes)

### Step 1: Create a Personal Access Token

The GitHub Traffic API requires a token with elevated permissions (the default `GITHUB_TOKEN` doesn't have traffic access).

1. Go to **GitHub Settings** → **Developer settings** → **[Personal access tokens (classic)](https://github.com/settings/tokens)**
2. Click **Generate new token (classic)**
3. Set:
   - **Note:** `repo-analytics` (or whatever you like)
   - **Expiration:** No expiration (or set a reminder to rotate)
   - **Scopes:** Check `repo` (full control of private repositories)
4. Click **Generate token** and **copy it immediately**

### Step 2: Add the Token as a Repository Secret

1. Go to your repository → **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Set:
   - **Name:** `TRAFFIC_TOKEN`
   - **Secret:** Paste your token from Step 1
4. Click **Add secret**

### Step 3: Add the Workflow

Copy the template workflow file into your repository:

```
.github/workflows/traffic-stats.yml
```

You can use the [`traffic-stats-template.yml`](traffic-stats-template.yml) file included in this kit. The only thing you need to change is the secret name if you used something other than `TRAFFIC_TOKEN`.

```bash
# From your repo root:
mkdir -p .github/workflows
cp path/to/traffic-stats-template.yml .github/workflows/traffic-stats.yml
git add .github/workflows/traffic-stats.yml
git commit -m "feat: Add traffic analytics dashboard"
git push
```

### Step 4: Run It

Trigger the workflow manually to create the initial data:

```bash
gh workflow run traffic-stats.yml
```

Or wait for the next hourly cron. The first **full collection** (with charts) happens at 00:00, 06:00, 12:00, or 18:00 UTC — or on any manual trigger.

### Step 5: View Your Dashboard

After the first full run completes:

- **Raw dashboard:** `https://github.com/YOUR_USER/YOUR_REPO/blob/traffic-stats/.github/traffic/SUMMARY.md`
- **Chart images:** `https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/traffic-stats/.github/traffic/charts/CHART_NAME.png`

---

## Embed Charts in Your README

Reference the chart images from your main branch using raw GitHub URLs:

```markdown
## Live Traffic

![Views & Clones](https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/traffic-stats/.github/traffic/charts/views_clones.png)

![Downloads](https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/traffic-stats/.github/traffic/charts/downloads.png)
```

Available chart filenames:
- `views_clones.png` — Page views and git clones over time
- `downloads.png` — Release acquisition (downloads + clones per release era)
- `engagement.png` — Pages per visitor engagement metric
- `conversion.png` — Visitor-to-download conversion funnel
- `referrers.png` — Traffic referrer breakdown
- `growth.png` — Stars, forks, watchers growth

**Pro tip:** Create a dedicated `docs/TRAFFIC_DASHBOARD.md` page (like [we did](https://github.com/XelaNull/FS25_UsedPlus/blob/master/docs/TRAFFIC_DASHBOARD.md)) and link to it from your README. Keeps your main page clean while giving interested visitors the full picture.

---

## How It Works

### Architecture

```
main branch                    traffic-stats branch (orphan)
├── .github/workflows/         ├── .github/traffic/
│   └── traffic-stats.yml      │   ├── charts/
│       (the workflow)          │   │   ├── views_clones.png
│                               │   │   ├── downloads.png
│                               │   │   ├── engagement.png
│                               │   │   ├── conversion.png
│                               │   │   ├── referrers.png
│                               │   │   └── growth.png
│                               │   ├── daily.json
│                               │   ├── downloads.json
│                               │   ├── referrers.json
│                               │   ├── metadata.json
│                               │   ├── releases_timeline.json
│                               │   ├── stats.json
│                               │   └── SUMMARY.md
│                               └── README.md
```

### Schedule

| Frequency | What Runs | Cost |
|-----------|-----------|------|
| **Every hour** | Download snapshot only (skip if unchanged) | ~5 seconds |
| **Every 6 hours** (00/06/12/18 UTC) | Full collection + chart generation + dashboard | ~25 seconds |
| **Manual trigger** | Full collection | ~25 seconds |

### Data Preservation

GitHub only provides **14 days** of traffic data. This system captures and archives it permanently:

- **Daily views/clones:** Saved per-day in `daily.json`, merged (never overwritten)
- **Download counts:** Cumulative snapshots with smart deduplication (skip if count unchanged)
- **Referrers:** Daily snapshots with date keys
- **Repo metadata:** Stars/forks/watchers daily snapshots

### Release Era Tracking

When you publish a new release, the system automatically:
1. Records the publish date in `releases_timeline.json`
2. Attributes subsequent git clones to the new release's "era"
3. Tracks per-release download counts from the Releases API
4. Generates stacked bar charts showing total acquisition per release
5. Preserves `peak_downloads` per release (survives release deletion)

---

## Customization

### Change the Secret Name

If your token is stored under a different secret name, update this line in the workflow:

```yaml
env:
  GH_TOKEN: ${{ secrets.YOUR_SECRET_NAME }}
```

### Change Chart Colors

The dark theme colors are defined in the Python section. Look for `plt.rcParams.update`:

```python
plt.rcParams.update({
    'figure.facecolor': '#0d1117',   # Background
    'axes.facecolor': '#161b22',     # Chart area
    'text.color': '#c9d1d9',         # Text
    # ... etc
})
```

### Add or Remove Charts

Each chart is an independent section in the "Generate charts" step. Delete any section you don't want, or add new ones following the same pattern.

### Change Collection Frequency

The cron schedule is in the `on.schedule` section:

```yaml
on:
  schedule:
    - cron: '0 * * * *'    # Every hour
```

Full collection hours are in the "Determine collection mode" step:

```yaml
if [ "$HOUR" = "00" ] || [ "$HOUR" = "06" ] || ...
```

---

## Costs & Limits

| Resource | Usage | Limit |
|----------|-------|-------|
| **Actions minutes** | ~0.5 min/day avg | Unlimited for public repos |
| **Storage** | ~2 MB/month (charts + JSON) | 500 MB soft limit per repo |
| **API calls** | ~30/day | 5,000/hour per token |

**Important:** GitHub auto-disables scheduled workflows after 60 days of repo inactivity. Any push, issue, or PR resets the timer.

---

## Troubleshooting

**Workflow fails with "Resource not accessible by integration"**
- Your token needs `repo` scope. Regenerate with correct permissions.

**Charts show "Jan 01" dates**
- This was a matplotlib auto-locator bug with few data points. The template includes the fix (`ax.set_xticks(dates)`).

**Downloads show 0 even though releases have downloads**
- The template reads from `downloads.json` (regular `jq`) instead of using `gh api --jq` which has a Go implementation that handles nested arrays differently.

**Charts show broken images in SUMMARY.md**
- Wait for the first full collection cycle (manual trigger or 6-hour mark).

**"traffic-stats branch is X commits behind main"**
- This is expected! It's an orphan branch — it shares no history with main. The "behind" count is meaningless.

---

## Credits

This analytics system was created for [FS25_UsedPlus](https://github.com/XelaNull/FS25_UsedPlus) by Claude (AI Developer) and Samantha (Co-Creator) through Anthropic's Claude Code.

**License:** Use freely. No attribution required, but appreciated.
