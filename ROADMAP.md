# JDownloader 2 Ultimate Manager Roadmap

PowerShell WPF workspace for installing, theming, hardening, configuring, and repairing JDownloader 2. v13.7.0 covers install + theme + debloat + config + repair. Roadmap targets automation, remote control, and deeper JD2 integration.

## Planned Features

### JDownloader Integration
- **Live JD2 control via JSON-RPC / MyJDownloader API** — start/stop/pause downloads, query queue, add links from the Ultimate Manager UI
- **Link grabber integration** — paste URLs into UM → forward to JD2's link grabber via internal API, not clipboard polling
- **Captcha solver pipeline** — surface captcha prompts in UM's own notification area so JD2 can stay in tray
- **Account manager** — front-end for JD2's premium hoster accounts, including OAuth flows (rapidgator, ddownload, etc.)
- **Per-host throttling** — UI for JD2's bandwidth rules (max per-host, global cap, scheduled off-peak)

### Deployment & Packaging
- **Portable profile** — `--portable` flag writes all settings to `./JD2-UM/` next to the script instead of `%LOCALAPPDATA%`
- **Silent mode** — `-Silent -Preset <name>` applies a saved preset with zero UI, for fleet deployment
- **Preset JSON** — dump/load full workspace state to JSON for version-control / share between machines
- **MSI installer** — ship as signed MSI (MSBuild WiX) with uninstall cleanup
- **Winget manifest** — publish to winget-pkgs for `winget install SysAdminDoc.JD2-Ultimate-Manager`
- **MyJDownloader/remote mode** — control JD2 installs on other machines from one UM instance

### Theming
- **Theme builder** — visual editor for custom Synthetica/FlatLaf themes with live preview, export as `.theme` bundle
- **Icon pack manager** — browse/install/preview community icon packs, validate against JD2's icon keys
- **Catppuccin/OLED/Nord theme packs** — build these natively so users don't have to hunt third-party JARs

### Hardening & Maintenance
- **Scheduled cleanup** — nightly cache purge via Task Scheduler with rotation retention
- **Update broker** — detect new JD2 core version, download, apply safely with automatic rollback if JD2 fails to start
- **Health dashboard** — readiness indicators for Java runtime, JD2 core, theme engine, hosts file, firewall, disk space
- **Safe-Mode diff** — when Safe Mode is triggered, produce a diff of what was changed since the last known-good state
- **Backup/restore** — snapshot `cfg/` folder before any destructive action, one-click restore

### UX
- **Dark WPF ComboBox parity** — full ControlTemplate audit so every dropdown matches Catppuccin
- **Toast notifications** — replace any dialogs with WPF toasts for non-blocking feedback
- **Drag-drop presets** — drop a `.json` preset onto the dashboard to import

## Competitive Research
- **Raw JDownloader 2** — upstream; full-featured but config is scattered across JSON files and menus. UM's value prop is unifying that.
- **MyJDownloader** — official remote control (web + mobile); great for remote but no install/theme/debloat story. Complement, don't replace.
- **pyLoad / FlareSolverr** — OSS download managers; smaller ecosystem than JD2. Not direct competitors but good reference for API design.
- **Chocolatey / winget JD2 package** — install-only, no theming or config. UM is the higher layer on top.

## Nice-to-Haves
- Linux port (PowerShell Core) for JDownloader on Ubuntu/Debian
- AppImage-aware mode on Linux (detect JD2 AppImage install, still edit `cfg/`)
- Discord/Slack webhook on download completion / failure
- Plugin API for custom post-download actions (auto-extract, virus scan, move to Plex library)
- Dry-run diff viewer that shows exactly which files/settings will change before Apply Workspace
- Encrypted settings store via DPAPI so saved premium account tokens aren't plaintext

## Open-Source Research (Round 2)

### Related OSS Projects
- JDownloader2 community repos — https://github.com/johna23-lab/jdownloader2 and https://github.com/pmoscode-helm/jdownloader2 — code mirrors / Docker images; useful for packaging reference
- giantpinkrobots/varia — https://github.com/giantpinkrobots/varia — modern aria2 + yt-dlp unified GUI (Linux/Windows); possible long-term migration target
- yt-dlp/yt-dlp — https://github.com/yt-dlp/yt-dlp — reference extractor catalog; can be paired with JDownloader for sites JD doesn't cover
- aria2/aria2 — https://github.com/aria2/aria2 — JSON-RPC lightweight downloader; complementary to JD for non-hoster direct links
- my.jdownloader API (MyJD) — https://github.com/mmzsource/myjdapi and https://github.com/rix1337/MyJDownloader-Scripts — Python clients for the JDownloader remote API
- 9seconds/ahttp / jdown_manager — community PowerShell/Python glue scripts
- FlareSolverr — https://github.com/FlareSolverr/FlareSolverr — Cloudflare bypass proxy; JD users chain it for protected hosters
- JDownloader Telegram/Switch bots (topic: jdownloader-2) — upload pipelines worth studying for auto-post-process hooks

### Features to Borrow
- **MyJDownloader remote API integration** (rix1337/MyJDownloader-Scripts) — the app already manages a local JD instance; adding remote queue visibility + pause/resume would cover tablet/phone use
- **yt-dlp fallback lane** (Varia) — when JD's hoster plugin fails, offer "retry with yt-dlp" button; same URL bar, different engine
- **aria2c direct-link lane** — for plain HTTPS files, aria2c with `-x16 -s16` is often faster than JD's single-connection default
- **FlareSolverr integration** — optional proxy for CF-protected hosters; auto-detect CF challenge → route through FlareSolverr → retry
- **Post-download action hooks** — like the JD bots: on complete, run script (unrar, rename, move to NAS share, emit webhook)
- **Queue persistence across JD restarts** — many community scripts re-enqueue items on JD crash; formalize this
- **Bandwidth schedule** (cron-like) — limit to 2 MB/s 9-5, unlimited overnight; common PS wrapper feature
- **Link-grabber paste from clipboard monitor** — similar to JD's browser extension but native in this manager
- **Host rotation / premium-account pool** — round-robin between multiple premium configs to max hourly quota

### Patterns & Architectures Worth Studying
- MyJD API client **auth/session refresh** — PBKDF2 device-key + session token with silent reconnect on expiry; tricky to get right
- Varia's **aria2 JSON-RPC + yt-dlp subprocess** duo — shows how to present two very different backends under one UI model
- JDownloader's **FlashGot-style link grabber** intake — regex-match of clipboard against hundreds of hoster patterns; worth mirroring for the app's paste-URL bar
- yt-dlp's **external-downloader protocol** (`--downloader aria2c --downloader-args "..."`) — mirror this: one unified download command, pick engine per-URL based on heuristics
- **PowerShell ThreadJob over Start-Job** — lower overhead for keeping multiple backend queries alive concurrently in the GUI
