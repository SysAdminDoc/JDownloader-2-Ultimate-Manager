<p align="center"><img src="icon.png" width="128" alt="JDownloader 2 Ultimate Manager"></p>

# JDownloader 2 Ultimate Manager  

<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/version-13.8.0-58A6FF?style=for-the-badge">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-4ade80?style=for-the-badge">
  <img alt="Platform" src="https://img.shields.io/badge/platform-PowerShell-58A6FF?style=for-the-badge">
</p>

<img width="1637" height="1216" alt="Preview" src="https://github.com/user-attachments/assets/0953927a-209c-476d-aa87-a17f2ab68f19" />

JDownloader 2 Ultimate Manager is a guided control workspace for installing, configuring, theming, hardening, and repairing JDownloader 2. It replaces scattered JSON edits and one-off cleanup steps with one calm, stateful interface that keeps the full setup visible from start to finish.

The tool supports both new deployments and existing installations, with live readiness feedback, theme previews, safer confirmation flows, and recovery tools that stay close when you need them.

---

## Quick Start

Run this command in **PowerShell** to launch instantly:

    irm https://tinyurl.com/jdowntest | iex

---

## Key Features

### 1. Installation & Deployment
- Auto-detects existing JDownloader 2 installations in standard directories  
- Supports clean installs from GitHub or Mega when no installation is found  
- Full mode selection: modify in-place or perform a clean fresh install  

### 2. Theming & Appearance
- Integrated theme engine with one-click installation of community themes (Dracula, Synthetica Black Eye, Flat Dark, Mica, etc.)  
- Icon pack system independent of theme selection  
- Dynamic live previews of themes before applying  
- Optional window decorations and compact tab layouts  

### 3. Hardening & Debloating
- Automatic removal of banners, premium ads, “Contribute” UI panels, and other clutter  
- Optional executable icon patching using Resource Hacker  
- Privacy enhancements to reduce unwanted promotional or telemetry-related components  

### 4. Configuration Management
- Direct editing of JD2's JSON configuration files without launching the application  
- Adjustable simultaneous downloads, pause speed, and networking behavior  
- Tray and taskbar behavior control (Minimize to Tray, Close to Tray)  
- Fully validated download directory selection  
- Portable settings mode, JSON workspace presets, and silent preset application for repeatable deployments  

### 5. Repair & Maintenance
- Full configuration reset to factory defaults while preserving downloads  
- Cache cleaning: removes tmp, logs, and cached metadata files  
- Health audit for missing or corrupted configuration files  
- Safe Mode launcher for troubleshooting  
- Full uninstall capability for complete removal of JDownloader 2  

### 6. Live Control & LinkGrabber
- Connects to JDownloader's local JSON API at `http://127.0.0.1:3128` (or a configured HTTP endpoint)
- Displays the live download queue with status, progress, speed, and ETA
- Starts, pauses, or stops the download controller without opening JDownloader's main window
- Sends one or more pasted URLs directly to LinkGrabber without clipboard polling

---

## System Requirements
- Windows 10 or Windows 11  
- PowerShell 5.1 or later  
- Administrative approval when you apply changes  
- Active internet connection for fetching installers, themes, and language files  

---

## Usage Guide

### Dashboard
- Review workspace status and the last successful run  
- Set the GUI theme (Dark, Light, Midnight, Catppuccin Mocha)  
- Select interface language and restore the last saved workspace  
- Review first without interruption; admin approval is requested only when the run begins  

### Installation
- Detect or specify the JDownloader directory  
- Choose between modify or clean install  

### Themes
- Select a Look-and-Feel theme  
- Choose and apply icon packs  
- Enable or disable window decorations and compact mode  

### Behavior
- Set maximum simultaneous downloads  
- Control minimize-to-tray and close-to-tray settings  
- Configure default download folder  

### Hardening
- Toggle executable icon patching  
- Enable automatic update after operations  
- Debloat settings (enabled by default)  

### Repair Tools
- Reset configuration files  
- Clear cache  
- Run a health audit  
- Launch Safe Mode  
- Perform full uninstall  

### Live Control
- Enable JDownloader's deprecated local API in Advanced Settings, then open **Live Control**
- Connect to the default `http://127.0.0.1:3128` endpoint or enter another HTTP endpoint
- Refresh the queue, use controller actions, and send newline-separated links to LinkGrabber

---

## Execution Workflow

After reviewing each page, click **Apply Workspace** in the footer.  
The manager opens a confirmation review first, then shows real-time progress for install, file patching, configuration writes, hardening steps, and recovery actions.

For repeatable deployments, export a preset from the dashboard or run:

    powershell -ExecutionPolicy Bypass -File "JDownloader 2 Ultimate Manager.ps1" -Portable -Silent -Preset ".\preset.json"

---

## Technical Details
- **Settings Persistence:** Stored in `%LOCALAPPDATA%\JD2-Ultimate-Manager\settings.json` with legacy `ProgramData` settings still recognized  
- **Portable Mode:** `-Portable` stores settings, logs, language cache, and presets beside the script in `.\JD2-UM\`  
- **Preset Automation:** `-ExportPreset <path>` writes the current/default workspace to JSON; `-Silent -Preset <path>` applies it without opening the GUI  
- **JSON Manipulation:** Edits JD2's config files directly, without requiring JD2 to be running
- **Live API:** `Tools\JD2Api.psm1` provides a tested, injectable client for queue queries, controller actions, and LinkGrabber submission
- **Dependencies:** Automatically downloads 7zr.exe and Resource Hacker when needed  
- **Security:** All outbound web requests enforce TLS 1.2  

---

## Disclaimer
This software is provided “as is” with no warranties. While the tool includes backup and recovery features, users assume responsibility for any data loss or instability arising from modifications to application files or system settings.
