<p align="center">
  <img src="../icon.png" alt="UsedPlus Logo" width="128" height="128">
</p>

<h1 align="center">UsedPlus — Live Analytics</h1>

<p align="center">
  <strong>Real-time traffic, downloads, and engagement metrics</strong><br>
  <em>Auto-updated every 6 hours by <a href="https://github.com/XelaNull/FS25_UsedPlus/blob/master/.github/workflows/traffic-stats.yml">GitHub Actions</a></em>
</p>

<p align="center">
  <img src="https://img.shields.io/github/downloads/XelaNull/FS25_UsedPlus/total?label=downloads&color=brightgreen" alt="Downloads">
  <img src="https://img.shields.io/github/stars/XelaNull/FS25_UsedPlus?style=flat&color=yellow" alt="Stars">
  <img src="https://img.shields.io/github/forks/XelaNull/FS25_UsedPlus?style=flat&color=blue" alt="Forks">
  <img src="https://img.shields.io/github/watchers/XelaNull/FS25_UsedPlus?style=flat&color=green" alt="Watchers">
  <img src="https://img.shields.io/badge/AI--authored-Claude-purple" alt="AI Authored">
</p>

<p align="center">
  <a href="https://github.com/XelaNull/FS25_UsedPlus">🏠 Main Repo</a> •
  <a href="https://github.com/XelaNull/FS25_UsedPlus/releases">📥 Releases</a> •
  <a href="https://github.com/XelaNull/FS25_UsedPlus/blob/traffic-stats/.github/traffic/SUMMARY.md">📋 Raw Data</a> •
  <a href="https://github.com/XelaNull/FS25_UsedPlus/tree/traffic-stats/.github/traffic">📂 Data Files</a>
</p>

---

> **How this works:** A [GitHub Action](https://github.com/XelaNull/FS25_UsedPlus/blob/master/.github/workflows/traffic-stats.yml) runs hourly to capture download counts and every 6 hours to collect full traffic data. Charts are generated with matplotlib and stored on the [`traffic-stats`](https://github.com/XelaNull/FS25_UsedPlus/tree/traffic-stats) branch. The images below reference that branch directly — **they update automatically**.
>
> Want this for your repo? See the [Analytics Kit setup guide](github-repo-analytics-kit/SETUP_GUIDE.md).

---

## Traffic Overview — Views & Clones

<p align="center">
  <img src="https://raw.githubusercontent.com/XelaNull/FS25_UsedPlus/traffic-stats/.github/traffic/charts/views_clones.png" alt="Views and Clones" width="100%">
</p>

GitHub's traffic API provides a rolling 14-day window of page views and git clones. Our archival system preserves this data permanently — even after GitHub's 14-day window expires, the historical data lives on in [`daily.json`](https://github.com/XelaNull/FS25_UsedPlus/blob/traffic-stats/.github/traffic/daily.json).

---

## Release Acquisition — Downloads + Clones per Release

<p align="center">
  <img src="https://raw.githubusercontent.com/XelaNull/FS25_UsedPlus/traffic-stats/.github/traffic/charts/downloads.png" alt="Release Acquisition" width="100%">
</p>

Every release gets its own "era." Git clones that occur while a release is current are attributed to that release. Zip downloads are tracked per-release via the GitHub Releases API. Together, they show **total acquisition** — how many people got the mod during each release cycle.

---

## Download Activity — Hourly Rate + Daily This Month

<p align="center">
  <img src="https://raw.githubusercontent.com/XelaNull/FS25_UsedPlus/traffic-stats/.github/traffic/charts/download_activity.png" alt="Download Activity" width="100%">
</p>

**Top panel:** Hourly download rate for the most recent day with activity. See exactly when downloads spike — release announcements, Reddit posts, ModHub features all show up as distinct peaks. **Bottom panel:** Daily downloads within the current month, with a cumulative trend line showing how the month is tracking.

---

## Visitor Engagement — Are People Exploring?

<p align="center">
  <img src="https://raw.githubusercontent.com/XelaNull/FS25_UsedPlus/traffic-stats/.github/traffic/charts/engagement.png" alt="Visitor Engagement" width="100%">
</p>

Engagement measures how deeply visitors explore. A ratio of 1.0 means every visitor saw only one page (bounce). Higher numbers mean people are reading the wiki, checking issues, browsing screenshots. **3.0+ indicates deeply engaged visitors** who are seriously evaluating the mod.

---

## Conversion Funnel — Visitors Who Download

<p align="center">
  <img src="https://raw.githubusercontent.com/XelaNull/FS25_UsedPlus/traffic-stats/.github/traffic/charts/conversion.png" alt="Conversion Funnel" width="100%">
</p>

The ultimate question: **what percentage of visitors actually download the mod?** This chart compares unique visitors against unique cloners plus zip downloads. A high conversion rate means the README, screenshots, and wiki are doing their job convincing people to try UsedPlus.

---

## Traffic Referrers — Where Visitors Come From

<p align="center">
  <img src="https://raw.githubusercontent.com/XelaNull/FS25_UsedPlus/traffic-stats/.github/traffic/charts/referrers.png" alt="Traffic Referrers" width="100%">
</p>

Which websites and search engines send traffic to this repo. Direct GitHub traffic (searches, explore page, profile visits) appears as `github.com`. External sources like search engines and mod sites appear individually.

---

## Repository Growth — Stars, Forks & Watchers Over Time

<p align="center">
  <img src="https://raw.githubusercontent.com/XelaNull/FS25_UsedPlus/traffic-stats/.github/traffic/charts/growth.png" alt="Repository Growth" width="100%">
</p>

Long-term growth trajectory. Stars indicate community interest, forks indicate developers studying or adapting the code, and watchers indicate people actively following development.

---

## Data Transparency

All raw data is publicly available on the [`traffic-stats` branch](https://github.com/XelaNull/FS25_UsedPlus/tree/traffic-stats/.github/traffic):

| File | What It Contains | Granularity |
|------|-----------------|-------------|
| [`daily.json`](https://github.com/XelaNull/FS25_UsedPlus/blob/traffic-stats/.github/traffic/daily.json) | Views & clones per day (preserved beyond GitHub's 14-day limit) | Daily |
| [`downloads.json`](https://github.com/XelaNull/FS25_UsedPlus/blob/traffic-stats/.github/traffic/downloads.json) | Release download snapshots with per-release breakdown | Hourly |
| [`referrers.json`](https://github.com/XelaNull/FS25_UsedPlus/blob/traffic-stats/.github/traffic/referrers.json) | Traffic referrer snapshots | Daily |
| [`metadata.json`](https://github.com/XelaNull/FS25_UsedPlus/blob/traffic-stats/.github/traffic/metadata.json) | Stars, forks, watchers, open issues | Daily |
| [`releases_timeline.json`](https://github.com/XelaNull/FS25_UsedPlus/blob/traffic-stats/.github/traffic/releases_timeline.json) | Release publish dates + peak download counts | Per-release |

---

## Set Up Your Own Analytics

Like what you see? This entire system is open source and reusable.

**[Analytics Kit Setup Guide](github-repo-analytics-kit/SETUP_GUIDE.md)** — Step-by-step instructions to add live traffic analytics to any GitHub repository in under 5 minutes. Includes a ready-to-use workflow template.

---

<p align="center">
  <sub>Charts auto-generated every 6 hours by <a href="https://github.com/XelaNull/FS25_UsedPlus/blob/master/.github/workflows/traffic-stats.yml">traffic-stats.yml</a> | Data stored on <a href="https://github.com/XelaNull/FS25_UsedPlus/tree/traffic-stats">traffic-stats branch</a></sub>
</p>
