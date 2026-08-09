# Changelog

All notable changes to JDownloader-2-Ultimate-Manager will be documented in this file.

## [Unreleased]

### Added
- **Live Control page** with a headless-tested JDownloader API client for queue inspection, start/pause/stop actions, and direct LinkGrabber submission.
- **Local API transport module** in `Tools\JD2Api.psm1`, with injectable request handling and Pester coverage for JSON parameter encoding, queue counters, controller actions, and link validation.
- **Captcha attention panel** with five-second polling, in-app image display, answer submission, and skip handling that keeps prompts visible while JDownloader stays in the tray.
- **Account Manager page** with account listing, add, enable, disable, and remove actions backed by JDownloader's local accounts API; credentials are not persisted by the manager.
- **Bandwidth controls** with per-host concurrency enforcement, a global download cap, and daily off-peak Task Scheduler profiles that use the local API when available and atomic config-file fallback otherwise.

## [v13.8.0] - 2026-06-27

### Added
- **Portable mode**: `-Portable` stores settings, logs, language cache, and temp handoff state under `.\JD2-UM\` beside the script instead of `%LOCALAPPDATA%`.
- **Workspace preset import/export**: dashboard buttons load or save the current workspace as JSON with validation and status feedback.
- **CLI preset automation**: `-ExportPreset <path>` writes the current/default workspace to JSON, and `-Silent -Preset <path>` applies a preset without opening the GUI.

### Changed
- Admin elevation handoff preserves `-Portable` so a UAC relaunch keeps using the portable data root.
- Silent install fallback no longer opens an alternate-source confirmation dialog; failures return a non-zero exit code for automation.
- Install detection now probes alternate drive roots without throwing when `E:` or `F:` are absent.

## [v13.7.0] - 2026-04-16

### Fixed (round 6 - bundled assets + repo hygiene)
- **Bundled installer is now actually used.** The repo ships 70 MB of `Installer/installer.7z.*` parts that the script was never touching - `Task-Install` always downloaded from a separate GitHub repo. Now checks `$PSScriptRoot\Installer\` first, stages the bundled parts into `$WorkDir` if all 7 are present, and only falls back to the network download if the bundled copy is missing/incomplete. Makes the clean-install flow work fully offline when run from a cloned/downloaded repo.
- **`.gitignore` hardened**: adds `*.bad-*` (corrupt-config quarantine files), `.vscode/`, and per-user runtime artifacts (`settings.json`, `settings.migrated.json`, `resume-state-*.json`, `Logs/`) so they can't be accidentally committed from a developer's working tree.

### Fixed (round 5 - type coercion + theme resilience)
- **Boolean coercion bug in state restore**: `[bool]"false"` returns `$true` in PowerShell (any non-empty string is truthy), so a hand-edited `settings.json` containing `"StartMin": "false"` would silently *enable* the flag on load. New `ConvertTo-SafeBool` helper parses string/int/bool uniformly (`true/yes/on/1/enabled` = true; `false/no/off/0/disabled` = false; anything else returns the caller-supplied default). All 18 boolean restores in `Apply-StateToControls` and `Get-NormalizedStateObject` now go through it. Verified with a 13-case self-test covering null, bool, int, and mixed-case string inputs.
- **Numeric parse safety in `Get-NormalizedStateObject`**: integer fields now use `[int]::TryParse` with per-field defaults, so `"MaxSim": "three"` no longer throws at comparison time.
- **`Apply-GuiTheme` guards against disposed controls**: `Update-Control` checks `IsDisposed` before reading any property, and the recursive `foreach ($c in $ctrl.Controls)` step is wrapped in try/catch. A partially-torn form during teardown (or a stale reference) can no longer wedge a theme change.

### Fixed (round 4 - UI responsiveness + thread safety)
- **Form.Add_Resize debounced** via a 60ms throttling timer. The Form fires `Resize` per drag-pixel, which was running the full `Sync-PageCanvases` + `Resize-ThemePreview` + `Layout-Footer` 100+ times during a single window drag. The batched layout now runs once the user pauses.
- **`Update-StatusVisual` checks `InvokeRequired`** before marshaling onto the UI thread. Previously every status update took the cross-thread hop path even when already on the UI thread - wasted work plus a failure surface if the marshal threw.
- **Status-update cross-thread exceptions are swallowed** (with try/catch around the Invoke call) so a status write during form teardown can't propagate an uncaught exception.

### Fixed (round 3 - deeper edge cases)
- **Fixed my own bug from round 1**: `if (Test-Path $bundledJava -or Test-Path $bundledJavaw)` was parsed as `Test-Path` receiving `-or` as an argument (always truthy), so the audit would never correctly report "no JRE". Added required parens.
- **`Execute-Operations` hardened for Modify mode**: refuses to proceed if the selected install path does not contain `JDownloader2.exe`. Previously a typo could cause cfg/ to be created in an unrelated folder. Also validates the download-folder parent exists before any writes.
- **Apply button re-entrancy**: a rapid double-click on Apply could fire the flow twice before `Set-WorkspaceBusyState` disabled the button. New `$script:ApplyInFlight` latch plus an immediate `BtnExec.Enabled = $false` on entry blocks this.
- **Icon file locks released**: both `$Form.Icon` and the sidebar `$LogoBox.Image` used `FromFile`, which holds an OS-level file handle for the life of the Image. Switched to in-memory byte array + `MemoryStream` + `Bitmap` copy so the file is released immediately (lets the user update `icon.ico`/`icon.png` while the app is running).
- **`Show-Page` guards** against unknown/disposed buttons and disposed target pages before toggling `Visible`.
- **`Register-LangControl` dedupes** accidental double-registrations of the same control+key pair.
- **Stale `.json.tmp` sweep**: at the end of a successful apply, any `*.json.tmp` siblings in `cfg/` (ours from a prior crash, or left over from an external tool) are removed. `Write-JsonAtomic` cleans its own on success, but a hard crash between write and move could leave one behind.
- **Startup WorkDir hygiene**: items older than 7 days in `$env:TEMP\JD2_Ult_Tool_v13_0` are removed on launch so TEMP doesn't accumulate gigabytes of unpacked installers/icons over many runs.
- **`$Form.Text`** at construction uses `Get-LangValue` with the `$script:AppTitle` fallback so an already-started language load can pre-populate the title and we never show a null.
- **`$PSScriptRoot`-null safety** for icon paths when launched via `iex` mode (where `$PSScriptRoot` is empty).

### Fixed (round 2 - deeper hardening)
- **`Set-JsonConfig` no longer overwrites existing config files.** It now reads the existing JSON, merges the caller's keys on top, and writes atomically. This preserves unrelated JDownloader-managed keys that the tool doesn't know about (previously a `Set-JsonConfig` of a single flag wiped the rest of the file).
- **All config writes are now atomic** via a new `Write-JsonAtomic` helper (write to `.tmp`, then `Move-Item` into place). The three raw `Set-Content` calls in `Execute-Operations` (GUI, General, Tray, Update settings) were converted.
- **Corrupt config files are quarantined** (`*.bad-<timestamp>`) instead of being treated as empty - the rewritten file is fresh and recoverable.
- **Stale `$sender` reference** in the theme-preloader timer tick (leftover from an earlier rename) would have thrown on any "job not found" branch. Removed.
- **Theme-preloader robustness**: instance-unique job name (`JD2UM_ThemeFetcher_<PID>`) eliminates cross-instance collisions; 60-second timeout hard-stops the polling timer if the job hangs; `Failed`/`Stopped` job states now clean up properly instead of spinning forever; TLS 1.2 is re-enforced inside the child runspace.
- **Installer-safety guard on uninstall**: `Task-FullUninstall` refuses to `Remove-Item -Recurse` a drive root, Windows system folder, user profile, `ProgramData`, or any path that doesn't contain a JDownloader/uninstaller marker. Prevents catastrophic deletions if the install-path field is edited incorrectly.
- **`Detect-JDPath` uses environment variables**, not hardcoded `C:\`/`D:\`. Probes `D:`/`E:`/`F:` only if those drives actually exist. Registry fallback unchanged.
- **Legacy settings migration** no longer re-migrates on every launch - the old ProgramData copy is renamed to `settings.migrated.json` after a successful copy.
- **Resume-state files are unique per launch** (`resume-state-<pid>-<guid>.json`), atomic on write, and size-capped at 1 MB on read (defense against bloated/crafted handoffs).
- **`Trigger-Update` checks for the exe first**, logs on failure, and surfaces `-update` launch errors (previously silently no-op'd).
- **Repair > Reset config / Reset theme / Clear cache** rewritten from one-liners: proper `Join-Path` composition, prompt cancellation short-circuits cleanly, and Clear Cache now also removes `logs\`, `cfg\tmp\`, and `update\*.tmp` (previously ignored the biggest sources of bloat). Clear Cache reports the count of items removed.
- **Safe Mode launch** surfaces `Start-Process` errors instead of silently pretending to launch.
- **`Task-ExtractIcons`** removes its `$WorkDir\IconsTemp` staging folder after the copy, so TEMP no longer accumulates unpacked icon archives.
- **`Task-PatchLaf`** uses `Write-JsonAtomic` (was non-atomic `Set-Content`), and guards against a missing theme JSON.

### Changed (round 2)
- `$GlobalTimers`, `$LanguageRegistry`, and `$PageRegistry` switched from `@()` + `+=` to `System.Collections.Generic.List` to eliminate O(n) rebind-per-append during GUI construction (hundreds of calls per launch).

### Fixed (correctness / reliability)
- **Icon patch now rolls back on failure.** `Task-PatchExeIcon` used to leave the install in a broken state if Resource Hacker failed mid-flight. It now preserves the pre-patch binary, checks the exit code, and restores the original exe if the patched output is missing or empty.
- **Installer pipeline no longer reuses stale parts.** `Task-Install` deletes any leftover `installer.7z.*` parts and the previous extract folder before downloading, verifies all 7 parts are present on disk, checks 7-Zip's exit code, and requires a post-install detection before reporting success.
- **Download-File now rejects HTML error pages.** A status-200 response that serves an HTML login/404 page no longer passes the size check; the payload is sniffed for HTML/XML markers and the file is deleted on mismatch.
- **Download-File removes stale destination first**, so a later failure cannot appear successful because a leftover file is still present.
- **Kill-JDownloader safer.** The javaw/JDownloader2 kill path wraps `MainModule.FileName` access (which throws under access-denied) and only terminates processes that are clearly JDownloader.
- **Task-ExtractIcons checks 7z exit code** and verifies an `images` directory exists before copying.
- **Save-Settings is now atomic.** Writes go to `settings.json.tmp` first and move into place, so a crash during write can never corrupt settings.
- **Load-Settings quarantines corrupt JSON** (renames to `.bad-<timestamp>`) so the next run starts from a clean default instead of refusing to load.
- **Atomic language-file replace.** `Load-Language` now retries, uses a longer timeout, tolerates an OrderedDictionary fallback (the previous `$dict.PSObject.Properties` iteration produced garbage keys on that code path), and keeps a known-good default-English payload when nothing else is available.
- **Update-InterfaceText no longer nulls labels** when a translation JSON omits a key — it now falls back through `Lang → DefaultLang`.
- **Elevation flow works under `iex`.** `Request-ElevatedApply` previously wrote `-File ""` when `$PSCommandPath` was null (web-launch mode); it now resolves via `$MyInvocation`, and if neither is available it re-stages the canonical script from GitHub before relaunching elevated.
- **Settings paths are robust when `LOCALAPPDATA`/`TEMP`/`ProgramData` are unset**; fallbacks compute a sane per-user location.
- **NumericUpDown state restore clamps to Min/Max** so a stale/out-of-range saved value never throws at load.
- **FolderBrowserDialog is now disposed** (memory/handle leak) and is scoped to the main form so it centers correctly over the app.
- **LinkLabel click validates URL scheme**; only `https?://` targets are launched so a malformed Tag can't Start-Process an arbitrary local command.
- **Removed the two dead config templates** (`Template_RemoteAPI`, `Template_SilentMode`) that were unused and carried malformed quote escaping the PowerShell parser flagged as errors.
- **Auto-elevation no longer assigns to the reserved `$sender` automatic variable** in timer/FormClosing handlers.

### Added
- **Log retention**: keeps the 20 most recent log files in `Logs/` and prunes older ones.
- **Config backup retention**: `Backup-JD` keeps only the 10 most recent backup folders in `cfg-backup/`.
- **Run-Audit** now additionally checks for a bundled JRE, falls back to looking up system `javaw`/`JAVA_HOME`, and warns when free space on the install drive is below 1 GB.
- **Language dropdown** displays friendly localized names (e.g., "English [en]", "Español [es]", "日本語 [ja]") instead of bare ISO codes — SelectedItem still carries the code, so the rest of the app is unaffected.
- **Utility helpers**: `Set-NumericSafe`, `Test-StateHas`, `Show-FolderPicker`, `Get-LanguageDisplayName`, `Test-LooksLikeHtmlErrorPage`.

### Changed
- Version bumped to 13.7.0 and centralized in a single `$script:AppVersion` constant. `$DefaultLang.Title` derives from this constant instead of being hard-coded (previously read "v13.5.0" while the script was 13.6.0).
- Title string in the window and default-language dictionary always match the actual script version.
- `"Available later"` button label for the restore action changed to `"Available after first run"` (the prior label implied a time-delay rather than a precondition).

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
