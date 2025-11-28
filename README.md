# JDownloader 2 Ultimate Admin Toolkit

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)
![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?logo=windows)
![License](https://img.shields.io/badge/License-MIT-green)

A comprehensive PowerShell automation script for managing **JDownloader 2**.

This tool is designed to deploy a clean, ad-free, and aesthetically consistent instance of JDownloader 2. It automates the complex process of syncing Look-and-Feel (LAF) files with internal configurations, patching executable icons, and stripping out adware/banners.

## 🚀 Features

### 📦 Automated Installation
- **GitHub Mirror:** Downloads and extracts the clean installer via 7-Zip split archives (silent install).
- **Mega.nz Support:** Scrapes and launches the official Mega installer for browser-based download handling.
- **Deep Uninstall:** Includes a "scorched earth" uninstaller that removes residual data in AppData and Program Files.

### 🛡️ System Hardening & Ad-Removal
- **Banner Nuker:** Recursively scans theme directories and replaces ad banners with transparent bitmaps.
- **Config Injection:** Injects a pre-hardened `GraphicalUserInterfaceSettings.json` that disables:
  - Donation buttons
  - Premium alerts
  - Oboom/Special Deal popups
  - Clipboard monitoring warnings
- **EXE Patcher:** Automatically downloads **Resource Hacker** to patch `JDownloader2.exe` with a modern `.ico` file, fixing the blurry/legacy taskbar icon.

### 🎨 Intelligent Theme Engine
JDownloader 2 often reverts themes if the configuration and LAF files aren't perfectly synced. This tool enforces specific **Theme + Icon** pairings to ensure stability:

| Theme | Icon Set Applied | Description |
| :--- | :--- | :--- |
| **Dracula** | **Standard** | The famous dark theme with default JDownloader icons. |
| **Flat Dark** | **Material** | A clean, flat dark interface paired with Material Design icons. |
| **Black Eye** | **Dark** | A high-contrast dark theme paired with a specialized Dark icon set. |
| **Black Eye** | **Standard** | The Black Eye theme but reverting to standard colored icons. |

## 🛠️ Usage

1. **Download** the `Install-JD2-Ultimate.ps1` script.
2. **Right-click** the file and select **Run with PowerShell**.
   * *Note: The script will auto-request Administrator privileges to modify Program Files.*
3. **Select your operation:**
   * **Installation:** Choose GitHub (Silent) or Mega.
   * **Theme:** Select your desired look. The script automatically handles the icon dependencies.
   * **Hardening:** Check "Recursively Nuke Banners" and "Patch EXE Icon".
4. Click **EXECUTE ALL OPERATIONS**.

## ⚙️ How It Works

1. **Process Killer:** Forcefully terminates all Java/JDownloader processes to release file locks.
2. **Dynamic Fetching:** Downloads the latest theme definitions (`.json`) directly from their respective GitHub repositories to ensure up-to-date colors.
3. **JSON Injection:** - Reads the target `org.jdownloader.settings.GraphicalUserInterfaceSettings.json`.
   - Injects the strict internal ID (e.g., `FLATLAF_DRACULA`).
   - Writes the corresponding LAF file to `\cfg\laf\`.
4. **Icon Extraction:** Downloads specific `.zip` packs (Dark, Material, Default), detects their internal structure (root folders vs. loose files), and places them precisely where the theme engine expects them.
5. **Watchdog:** Uses a detached background process to monitor the installer and ensure the update cycle completes.

## 🔗 Credits & Resources

This toolkit aggregates themes and icons from the community:

* **Themes:**
  * [Dracula Theme](https://github.com/dracula/jdownloader2)
  * [Fluent/Flat Dark](https://github.com/ikoshura/JDownloader-Fluent-Theme)
  * [Synthetica Black Eye](https://github.com/Vinylwalk3r/JDownloader-2-Dark-Theme)
* **Icons & Assets:**
  * Hosted by [SysAdminDoc/JDownloaderDarkMode](https://github.com/SysAdminDoc/JDownloaderDarkMode)

## ⚠️ Disclaimer

This script is an independent community tool. It is not affiliated with AppWork GmbH. Use at your own risk. Always back up your download lists (`downloadList*.zip`) before running a full uninstall.
