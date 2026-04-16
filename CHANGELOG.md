# Changelog

All notable changes to JDownloader-2-Ultimate-Manager will be documented in this file.

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
