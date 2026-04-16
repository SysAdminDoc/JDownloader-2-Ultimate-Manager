# Changelog

All notable changes to JDownloader-2-Ultimate-Manager will be documented in this file.

## [v13.6.0] - 2026-04-16

### Added
- **Behavior page: Advanced download tuning** surface with chunks per file (1-20) and per-host download limit (1-20) controls
- **Behavior page: File handling** surface with hash check toggle, preserve original file dates toggle, and clipboard monitoring toggle
- **Hardening page: Privacy and security** surface with deprecated local API lockdown (port 3128) and JVM performance options file writer
- **5 new config templates**: UpdateSettings, BubbleNotifyConfig, RemoteAPIConfig, SilentModeSettings — all written during apply flow
- **Expanded debloat flags** in GUI template: `premiumalertetacolumnenabled`, `premiumalerttaskcolumnenabled`, `premiumdisabledwarningflashenabled`, `hatecaptchastextincaptchadialogvisible`, `taskbarflashenabled`, `clipboarddisabledwarningflashenabled`, `windowstaskbarprogressdisplay`
- **Expanded GeneralSettings template** with 12 new keys: `maxpluginretries`, `forcedfreespaceondisk`, `freespacecheckenabled`, `useoriginallastmodified`, `maxbuffersize`, `flushbuffertimeout`, `flushbufferlevel`, `deleteemptysubfoldersafterdeletingdownloadedfilesenabled`, `cleanupfilenames`, `waittimeonconnectionloss`, `downloadtempunavailableretrywaittime`, `downloadhostunavailableretrywaittime`
- **Comprehensive health audit** (`Run-Audit`): checks JDownloader2.exe, JDownloader.jar, critical config JSON validity, stale .tmp files, LAF directory, and reports JD core revision
- **Registry-based install detection** fallback when filesystem paths don't match
- **8 additional install path candidates** including D: drive, %APPDATA%, %ProgramData% variations
- **JDownloader2.vmoptions writer**: creates JVM tuning file with `-XX:-UsePerfData` and `-Djava.net.preferIPv4Stack=true`
- **Deep hardening** now writes to 8+ config files: contribute panels, bubble notifications, silent mode, remote API security headers
- All 7 new controls include accessibility metadata, tooltips, workspace state tracking, and confirmation dialog sync

### Changed
- `donatebuttonstate` changed from `"CUSTOM_HIDDEN"` to `"ALWAYS_HIDDEN"` (more reliable suppression)
- `packagesbackgroundhighlightenabled` set to `false` for better dark theme readability (from community theme projects)
- `Task-DeepHardening` now accepts `$HardenState` parameter for conditional privacy/security passes
- Behavior page canvas height increased from 560 to 740 for new controls
- Hardening page canvas height increased from 610 to 780 for privacy/security section
- Hardening "Always applied" section now lists 5 categories instead of 3 (adds premium columns and bubble notifications)
- Workspace change detection area map expanded to track new controls

## [v13.5.1] - 2026-04-16

### Fixed
- Download folder double-escaping: `ConvertTo-Json` already handles backslash escaping, so manual `.Replace("\", "\\")` produced corrupted paths (`C:\\\\Downloads` instead of `C:\\Downloads`)
- Tray config silently failing: `OrderedDictionary.ContainsKey()` throws in PowerShell 5.1; replaced with `.Contains()` so tray settings (close-to-tray, minimize-to-tray) are actually written
- Language auto-detection broken: `$CurrentLangCode` inside `Load-Language` was local-scoped, never updating the script-level variable; fixed to `$script:CurrentLangCode`
- Translation keys mismatch: lang.json uses different keys than `$DefaultLang`; added `$script:LangKeyAliases` bridge so translations actually apply to controls
- BitsTransfer inverted check: first download attempt always failed on BITS before falling back to WebRequest; fixed module-loaded check
- Get-7Zip returning invalid path on download failure: now returns `$null` with null guards at all call sites
- Language file download corruption: downloads to temp file first, validates size > 100 bytes, moves to final path only on success; falls back to cached copy
- Explorer killed during icon patching: replaced `taskkill /f /im explorer.exe` with `ie4uinit.exe -show` for icon cache refresh
- GDI resource leak in banner nuking: added `try/finally` disposal pattern for Image and Bitmap objects
- WebClient leak in background theme image preloader: added `try/finally` disposal
- Confirmation dialog and action prompt forms not disposed after `ShowDialog()`
- Settings never migrating from legacy `%ProgramData%` path: added `Get-SettingsSourcePath` with auto-migration
- Form closable during operations: added `FormClosing` guard that blocks close while `UseWaitCursor` is active
- LAF patching failures silently swallowed: now logs warnings
- Banner nuke failures silently swallowed: now logs per-file warnings
- Legacy settings migration failure silently swallowed: now logs warning
- Multiple config write failures in `Execute-Operations` silently swallowed: now log warnings
- `Set-JsonConfig` failure silently swallowed: now logs warning with file path

## [v13.5.0] - 2026-04-15

### Added
- Premium workspace UI with surface-based layout, hero sections, and card tiles
- Enhanced theme palette: 18 semantic color tokens (Surface, Border, Accent, Muted, Success, Warning, Danger, etc.) across all four themes
- Sidebar branding panel with logo, tagline, and contextual notes
- Workspace state tracking: detects changes vs last successful run, shows pending areas
- Restore workspace button to revert to last applied state
- Session overview card on dashboard with install detection status and run mode
- Action tile components for repair tools with descriptions and path validation
- Accessibility metadata (AccessibleName/Description) on all interactive controls
- Double buffering on panels and form to reduce flicker
- Cue banners (placeholder text) on path and download folder inputs
- Directory autocomplete on path inputs
- Form taskbar icon from icon.ico
- Install fallback prompt when GitHub download fails (offers Mega alternative)
- Per-step error messages during install flow
- Download folder blank = reset to JDownloader default behavior
- Footer layout auto-adjusts to window width

### Changed
- Theme engine expanded from 7 to 18 color tokens per theme
- Dark (Default) theme deepened to navy-black palette
- GUI builder functions refactored with consistent parameter handling
- Pages now use scrollable canvas panels with centered content
- Repair tools moved from grid buttons to descriptive action tiles
- Form starts at 88% screen size (centered) instead of maximized
- Font sizes normalized across all control types
- Theme image cache now copies bitmaps and disposes streams (GDI leak fix)
- Execute button runs immediately without confirmation dialog
- Status bar uses semantic colors matching current theme

### Removed
- Keyboard shortcuts (Ctrl+1-6, F5, Ctrl+Enter, Ctrl+R) per project rules
- Pre-execute confirmation dialog gate
- Close confirmation dialog
- Hardcoded "C:\Downloads" default (now blank = JD default)
- Old flat button grid for repair tools

## [v13.4.4] - 2026-04-13

- Fixed: Constructor overload errors in System.Drawing.Size and Point
- Fixed: Arithmetic parsing issues causing argument count mismatches
- Fixed: Null reference exceptions on event handlers

## [v13.4.0] - Initial tracked release

- WinForms GUI with sidebar navigation
- Theme engine with 4 GUI themes and community JD2 themes
- Installation, behavior, hardening, and repair modules
- Language engine with JSON translation files
- Settings persistence to ProgramData
