<#
.SYNOPSIS
    JDownloader 2 ULTIMATE MANAGER (v13.8.0)
    - Premium workspace UI with surface-based layout, hero sections, and card tiles.
    - Enhanced 18-token theme palette with semantic colors across all four themes.
    - Workspace state tracking with change detection and restore capability.
    - Architecture: WinForms GUI, JSON Settings Persistence, Robust Logging.
#>

param(
    [string]$ResumeStateFile,
    [switch]$ResumeApply,
    [switch]$Portable,
    [switch]$Silent,
    [string]$Preset,
    [string]$ExportPreset
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

# Script identity - single source of truth for versioning
$script:AppVersion = '13.8.0'
$script:AppName    = 'JDownloader 2 Ultimate Manager'
$script:AppTitle   = "$script:AppName v$script:AppVersion"

# ==========================================
# 0. PRE-FLIGHT CHECKS & HARDENING
# ==========================================
# Enforce TLS 1.2 for all web requests immediately
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==========================================
# 1. INITIALIZATION & ELEVATION
# ==========================================
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$script:IsElevated = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$script:ResumeStateFile = if ([string]::IsNullOrWhiteSpace($ResumeStateFile)) { $null } else { $ResumeStateFile }
$script:ResumeApplyRequested = [bool]$ResumeApply
$script:PortableMode = [bool]$Portable
$script:SilentMode = [bool]$Silent
$script:PresetPath = if ([string]::IsNullOrWhiteSpace($Preset)) { $null } else { $Preset }
$script:ExportPresetPath = if ([string]::IsNullOrWhiteSpace($ExportPreset)) { $null } else { $ExportPreset }
$script:ApiModulePath = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'Tools\JD2Api.psm1' } else { $null }
$script:ApiModuleLoaded = $false
if ($script:ApiModulePath -and (Test-Path -LiteralPath $script:ApiModulePath)) {
    try {
        Import-Module -Name $script:ApiModulePath -Force -ErrorAction Stop
        $script:ApiModuleLoaded = $true
    } catch {
        $script:ApiModuleLoadError = $_.Exception.Message
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class NativeGuiApi {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, string lParam);
}
'@ -ErrorAction Stop
} catch {}

# Force High DPI Awareness correctly
try {
    $methods = '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
    $user32 = Add-Type -MemberDefinition $methods -Name "Win32" -Namespace Win32 -PassThru
    $user32::SetProcessDPIAware() | Out-Null
} catch {
    # Fail silently on older OS
}

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# ==========================================
# 2. GLOBAL VARIABLES & PATHS
# ==========================================
# Guard against unusual environments where LOCALAPPDATA / TEMP are unset.
$LocalAppDataRoot = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { Join-Path $env:USERPROFILE 'AppData\Local' } else { $env:LOCALAPPDATA }
$ProgramDataRoot  = if ([string]::IsNullOrWhiteSpace($env:ProgramData))  { Join-Path $env:SystemDrive 'ProgramData' } else { $env:ProgramData }
$TempRoot         = if ([string]::IsNullOrWhiteSpace($env:TEMP))         { Join-Path $LocalAppDataRoot 'Temp' }         else { $env:TEMP }

$PortableRoot = if ($script:PortableMode) {
    $base = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($base) -and $MyInvocation.MyCommand -and -not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) {
        $base = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    if ([string]::IsNullOrWhiteSpace($base)) { $base = (Get-Location).Path }
    Join-Path $base 'JD2-UM'
} else { $null }
$LegacyAppDataDir = Join-Path $ProgramDataRoot  'JD2-Ultimate-Manager'
$AppDataDir       = if ($script:PortableMode) { $PortableRoot } else { Join-Path $LocalAppDataRoot 'JD2-Ultimate-Manager' }
$LogDir           = Join-Path $AppDataDir       'Logs'
$WorkDir          = Join-Path $TempRoot         'JD2_Ult_Tool_v13_0'
$SettingsFile     = Join-Path $AppDataDir       'settings.json'
$LegacySettingsFile = Join-Path $LegacyAppDataDir 'settings.json'
$LangFile         = Join-Path $AppDataDir       'lang.json'
# Note: $VersionFile was never read; removed to eliminate dead state.

# Ensure directories exist with error handling
foreach ($path in @($AppDataDir, $LogDir, $WorkDir)) {
    if ([string]::IsNullOrWhiteSpace($path)) { continue }
    if (-not (Test-Path $path)) {
        try { New-Item -ItemType Directory -Path $path -Force | Out-Null } catch {}
    }
}

# Best-effort log-retention: keep the 20 most recent log files so logs/ never grows unbounded.
try {
    if (Test-Path $LogDir) {
        Get-ChildItem -Path $LogDir -Filter "*.log" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip 20 |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
} catch {}

$LogFile     = "$LogDir\$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
$StatusLabel = $null
$ProgressBar = $null

# Best-effort WorkDir hygiene: remove items older than 7 days so TEMP never accumulates
# gigabytes of unpacked installers/icons across many runs. Skip anything in active use via
# -ErrorAction SilentlyContinue so a locked file never blocks startup.
try {
    if (Test-Path $WorkDir) {
        $cutoff = (Get-Date).AddDays(-7)
        Get-ChildItem -Path $WorkDir -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
} catch {}

# ToolTip helper
$ToolTip = New-Object System.Windows.Forms.ToolTip
$ToolTip.AutoPopDelay = 5000
$ToolTip.InitialDelay = 1000
$ToolTip.ReshowDelay = 500

# Language Registry for live updates. Using a List avoids the O(n) copy that `+=` causes
# across hundreds of registrations during GUI construction.
$LanguageRegistry = New-Object System.Collections.Generic.List[hashtable]

# Global tracking for cleanup. A List avoids rebind-per-append ($arr += x) and makes
# ownership clear when we dispose on FormClosing.
$GlobalJobs   = @{}
$GlobalTimers = New-Object System.Collections.Generic.List[object]
$ThemeImageCache = @{}
$script:CurrentGuiTheme = "Dark (Default)"
$script:LastStatusText = "Ready"
$script:LastStatusType = "INFO"
$script:InitialWorkspaceState = $null
$script:SavedWorkspaceState = $null
$script:IsBootstrapping = $true
$script:ApplyInFlight = $false
$script:LiveApiClient = $null
$script:LiveApiEndpoint = "http://127.0.0.1:3128"
$script:LiveApiBusy = $false
$script:LiveApiPollTimer = $null
$script:LiveCaptchaJob = $null
$script:LiveCaptchaBitmap = $null

# ==========================================
# 3. LANGUAGE & GUI THEME ENGINE
# ==========================================

# --- Default English Fallback ---
$DefaultLang = [ordered]@{
    "Title" = $script:AppTitle;
    "Dashboard" = "Dashboard"; "LiveControl" = "Live Control"; "Installation" = "Installation"; "Themes" = "Themes";
    "Behavior" = "Behavior"; "Hardening" = "Hardening"; "Repair" = "Repair Tools";
    "Execute" = "Apply Workspace"; "Status" = "Status: Ready";
    "Running" = "Applying workspace...";
    "FooterSummary" = "Review each page first. Administrative approval is requested only when the run begins.";
    "RunFinishedTitle" = "Run finished";
    "RunFinishedBody" = "Selected operations completed. Review the status area for the final result.";
    "PathRequiredTitle" = "Path required";
    "PathRequiredBody" = "Choose a JDownloader folder first.";
    "InstallRequiredTitle" = "Installation required";
    "InstallRequiredBody" = "Point the tool at a valid JDownloader installation first.";
    "Cancel" = "Cancel";
    "Back" = "Back";
    "ApplySelected" = "Apply selected changes";
    "DashTitle" = "JDownloader 2 Ultimate Manager";
    "DashSub" = "Configure install, appearance, behavior, hardening, and recovery from one guided workspace.";
    "DashHint" = "Review the workspace freely. Windows asks for approval only when changes are ready to start.";
    "InstTitle" = "Installation Options";
    "InstSub" = "Confirm the path, choose the install source, and make the next step obvious before files change.";
    "InstPath" = "JDownloader installation folder:";
    "Browse" = "Browse..."; "AutoDetect" = "Auto-Detect";
    "InstMode" = "Installation mode:";
    "InstModeHelp" = "If no installation is found, the tool will automatically perform a clean install from GitHub.";
    "ThemeTitle" = "Theme and Appearance";
    "ThemeSub" = "Compare supported looks, preview the result, and layer icon packs without leaving the manager.";
    "ThemePreset" = "Theme preset:";
    "OpenGithub" = "Open theme on GitHub";
    "EnableWinDec" = "Enable custom window decorations";
    "CompactTabs" = "Compact main tabs (minimal layout)";
    "IconPack" = "Icon pack:"; "OpenIconFolder" = "Open icon folder";
    "BehTitle" = "Behavior Settings";
    "BehSub" = "Set sane defaults for speed, folders, and tray behavior before the next launch.";
    "MaxSim" = "Max simultaneous downloads:";
    "MaxSimHelp" = "Higher values use more bandwidth and connections. 3 to 5 is usually a good balance.";
    "PauseSpeed" = "Pause speed (bytes per second):";
    "PauseHelp" = "10240 bytes per second is a near stop.";
    "DefDlFolder" = "Default download folder:";
    "StartMin" = "Start minimized";
    "MinToTray" = "Minimize to tray instead of taskbar";
    "CloseToTray" = "Close button sends JDownloader to tray";
    "HardTitle" = "Hardening and Security";
    "HardSub" = "Quiet promotional UI, align the shell with your desktop, and keep only the finishing touches you actually want.";
    "DarkExe" = "Darken JDownloader executables with a custom icon";
    "RunUpdate" = "Run JDownloader update after operations";
    "HardNote" = "Contribute prompts, premium ads, news popups, MyJD promos, and banner clutter are disabled every time this workspace runs.";
    "RepTitle" = "Repair and Maintenance";
    "RepSub" = "Use these safety-first tools when JDownloader feels unstable, cluttered, or ready for a clean reset.";
    "BtnResetCfg" = "Reset full configuration";
    "BtnResetThm" = "Reset theme and icons only";
    "BtnClearCache" = "Clear temporary cache files";
    "BtnAudit" = "Run health audit";
    "BtnSafe" = "Launch in safe mode";
    "BtnUninstall" = "Full uninstall JDownloader";
    "GuiTheme" = "GUI Theme:";
    "Language" = "Language:";
}

# --- Language Loader ---
$Lang = [ordered]@{}
foreach ($key in $DefaultLang.Keys) {
    $Lang[$key] = $DefaultLang[$key]
}

$AvailableLanguages = @{}
$CurrentLangCode = "en"

# Friendly names for the language dropdown (ASCII-only to remain byte-stable under PS 5.1 no-BOM).
# Codes not listed here fall back to the raw ISO code.
$script:LanguageDisplayNames = @{
    'en' = 'English'
    'es' = 'Spanish'
    'de' = 'German'
    'fr' = 'French'
    'it' = 'Italian'
    'pt' = 'Portuguese'
    'nl' = 'Dutch'
    'pl' = 'Polish'
    'ru' = 'Russian'
    'ja' = 'Japanese'
    'ko' = 'Korean'
    'zh' = 'Chinese'
    'ar' = 'Arabic'
    'tr' = 'Turkish'
    'cs' = 'Czech'
    'sv' = 'Swedish'
    'da' = 'Danish'
    'no' = 'Norwegian'
    'fi' = 'Finnish'
    'hu' = 'Hungarian'
    'ro' = 'Romanian'
    'uk' = 'Ukrainian'
    'el' = 'Greek'
    'he' = 'Hebrew'
    'th' = 'Thai'
    'vi' = 'Vietnamese'
    'id' = 'Indonesian'
    'sk' = 'Slovak'
    'bg' = 'Bulgarian'
    'hr' = 'Croatian'
    'sr' = 'Serbian'
}

function Get-LanguageDisplayName {
    param([string]$Code)
    if ([string]::IsNullOrWhiteSpace($Code)) { return $Code }
    if ($script:LanguageDisplayNames.ContainsKey($Code)) {
        return ("{0}  [{1}]" -f $script:LanguageDisplayNames[$Code], $Code)
    }
    return $Code
}

function Load-Language {
    $langUrl = "https://raw.githubusercontent.com/SysAdminDoc/JDownloader-2-Ultimate-Manager/refs/heads/main/Translations/lang.json"
    $userLang = try { (Get-Culture).TwoLetterISOLanguageName } catch { "en" }
    if ([string]::IsNullOrWhiteSpace($userLang)) { $userLang = "en" }
    $tempLangFile = "$LangFile.download"

    function Select-LangFallback {
        param($UserCode)
        if ($AvailableLanguages.ContainsKey($UserCode)) {
            $script:CurrentLangCode = $UserCode
            Apply-LanguageData $UserCode
        } elseif ($AvailableLanguages.ContainsKey("en")) {
            $script:CurrentLangCode = "en"
            Apply-LanguageData "en"
        }
    }

    try {
        # Prefer a modest timeout with a retry to tolerate slow connections.
        $webOk = $false
        for ($attempt = 1; $attempt -le 2 -and -not $webOk; $attempt++) {
            try {
                Invoke-WebRequest -Uri $langUrl -OutFile $tempLangFile -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
                $webOk = $true
            } catch {
                if ($attempt -ge 2) { throw }
                Start-Sleep -Milliseconds 500
            }
        }

        if ((Test-Path $tempLangFile) -and (Get-Item $tempLangFile).Length -gt 100) {
            $raw = Get-Content $tempLangFile -Raw -Encoding UTF8
            $json = $raw | ConvertFrom-Json -ErrorAction Stop
            try { Move-Item $tempLangFile $LangFile -Force -ErrorAction Stop } catch { Remove-Item $tempLangFile -Force -ErrorAction SilentlyContinue }

            $json.PSObject.Properties | ForEach-Object {
                $AvailableLanguages[$_.Name] = $_.Value
            }
            Select-LangFallback $userLang
            return
        }
        Remove-Item $tempLangFile -Force -ErrorAction SilentlyContinue
        throw "Downloaded language file was empty or invalid."
    } catch {
        Remove-Item $tempLangFile -Force -ErrorAction SilentlyContinue
        if (Test-Path $LangFile) {
            try {
                $json = Get-Content $LangFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
                $json.PSObject.Properties | ForEach-Object { $AvailableLanguages[$_.Name] = $_.Value }
                Select-LangFallback $userLang
                return
            } catch {}
        }
    }

    # Final defensive fallback: ensure at least English-with-default-keys is selectable.
    if (-not $AvailableLanguages.ContainsKey("en")) {
        $enPayload = New-Object PSCustomObject
        foreach ($key in $DefaultLang.Keys) {
            $enPayload | Add-Member -MemberType NoteProperty -Name $key -Value $DefaultLang[$key] -Force
        }
        $AvailableLanguages["en"] = $enPayload
    }
    $script:CurrentLangCode = "en"
}

$script:LangKeyAliases = @{
    "RepairTools" = "Repair"; "ExecuteOperations" = "Execute"; "Detect" = "AutoDetect"
    "InstallPath" = "InstPath"; "InstallMode" = "InstMode"; "ThemeSelection" = "ThemePreset"
    "WindowDecorations" = "EnableWinDec"; "MinimalLayout" = "CompactTabs"
    "MaxSimDownloads" = "MaxSim"; "DownloadFolder" = "DefDlFolder"
    "StartMinimized" = "StartMin"; "MinimizeToTray" = "MinToTray"
    "PatchExeIcon" = "DarkExe"; "AutoUpdate" = "RunUpdate"
}

function Apply-LanguageData {
    param($Code)
    if (-not $AvailableLanguages.ContainsKey($Code)) { return }
    $dict = $AvailableLanguages[$Code]
    if (-not $dict) { return }

    # Support PSCustomObject (from ConvertFrom-Json), Hashtable, and OrderedDictionary.
    $keys = @()
    $getter = $null
    if ($dict -is [System.Collections.IDictionary]) {
        $keys = @($dict.Keys)
        $getter = { param($k) $dict[$k] }
    } elseif ($dict -is [psobject]) {
        $keys = @($dict.PSObject.Properties.Name)
        $getter = { param($k) $dict.$k }
    } else {
        return
    }

    foreach ($key in $keys) {
        $value = & $getter $key
        if ($null -eq $value) { continue }
        $Lang[$key] = $value
        if ($script:LangKeyAliases.ContainsKey($key)) {
            $Lang[$script:LangKeyAliases[$key]] = $value
        }
    }
}

function Get-LangValue {
    param([string]$Key, [string]$Fallback = "")
    if ($Lang -and $Lang.Contains($Key)) {
        $value = [string]$Lang[$Key]
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    return $Fallback
}

function Register-LangControl {
    param($Control, $Key)
    if (-not $Control -or [string]::IsNullOrWhiteSpace($Key)) { return }
    # Guard against accidental double-registration (happens if a control is rebuilt and
    # Register-LangControl is re-called against it). Duplicate entries would cause redundant
    # writes during Update-InterfaceText but do no real harm; still, keep the registry clean.
    foreach ($entry in $script:LanguageRegistry) {
        if ($entry.Control -eq $Control -and $entry.Key -eq $Key) { return }
    }
    [void]$script:LanguageRegistry.Add(@{ Control = $Control; Key = $Key })
    if ($Lang.Contains($Key)) {
        try { $Control.Text = [string]$Lang[$Key] } catch {}
    }
}

Load-Language

# --- GUI Color Themes ---
$GuiThemes = @{
    "Dark (Default)" = @{
        FormBack   = [System.Drawing.Color]::FromArgb(13,18,28)
        Fore       = [System.Drawing.Color]::FromArgb(244,247,252)
        Sidebar    = [System.Drawing.Color]::FromArgb(10,14,22)
        SidebarAlt = [System.Drawing.Color]::FromArgb(18,24,36)
        Main       = [System.Drawing.Color]::FromArgb(17,22,34)
        Surface    = [System.Drawing.Color]::FromArgb(22,29,43)
        SurfaceAlt = [System.Drawing.Color]::FromArgb(27,35,51)
        Footer     = [System.Drawing.Color]::FromArgb(10,14,22)
        BtnBack    = [System.Drawing.Color]::FromArgb(32,40,56)
        InputBack  = [System.Drawing.Color]::FromArgb(15,20,30)
        Border     = [System.Drawing.Color]::FromArgb(45,58,81)
        Accent     = [System.Drawing.Color]::FromArgb(96,165,250)
        AccentSoft = [System.Drawing.Color]::FromArgb(34,58,94)
        Muted      = [System.Drawing.Color]::FromArgb(154,167,191)
        MutedStrong= [System.Drawing.Color]::FromArgb(191,203,224)
        Success    = [System.Drawing.Color]::FromArgb(74,222,128)
        Warning    = [System.Drawing.Color]::FromArgb(250,204,21)
        Danger     = [System.Drawing.Color]::FromArgb(248,113,113)
    }
    "Light" = @{
        FormBack   = [System.Drawing.Color]::FromArgb(245,247,251)
        Fore       = [System.Drawing.Color]::FromArgb(24,31,45)
        Sidebar    = [System.Drawing.Color]::FromArgb(234,239,246)
        SidebarAlt = [System.Drawing.Color]::FromArgb(248,250,253)
        Main       = [System.Drawing.Color]::FromArgb(245,247,251)
        Surface    = [System.Drawing.Color]::FromArgb(255,255,255)
        SurfaceAlt = [System.Drawing.Color]::FromArgb(240,244,250)
        Footer     = [System.Drawing.Color]::FromArgb(234,239,246)
        BtnBack    = [System.Drawing.Color]::FromArgb(232,237,244)
        InputBack  = [System.Drawing.Color]::FromArgb(255,255,255)
        Border     = [System.Drawing.Color]::FromArgb(206,215,228)
        Accent     = [System.Drawing.Color]::FromArgb(37,99,235)
        AccentSoft = [System.Drawing.Color]::FromArgb(219,234,254)
        Muted      = [System.Drawing.Color]::FromArgb(79,92,115)
        MutedStrong= [System.Drawing.Color]::FromArgb(52,64,86)
        Success    = [System.Drawing.Color]::FromArgb(22,163,74)
        Warning    = [System.Drawing.Color]::FromArgb(202,138,4)
        Danger     = [System.Drawing.Color]::FromArgb(220,38,38)
    }
    "Midnight" = @{
        FormBack   = [System.Drawing.Color]::FromArgb(8,11,20)
        Fore       = [System.Drawing.Color]::FromArgb(228,236,255)
        Sidebar    = [System.Drawing.Color]::FromArgb(6,8,15)
        SidebarAlt = [System.Drawing.Color]::FromArgb(16,21,38)
        Main       = [System.Drawing.Color]::FromArgb(11,15,28)
        Surface    = [System.Drawing.Color]::FromArgb(17,23,40)
        SurfaceAlt = [System.Drawing.Color]::FromArgb(24,31,54)
        Footer     = [System.Drawing.Color]::FromArgb(6,8,15)
        BtnBack    = [System.Drawing.Color]::FromArgb(28,36,60)
        InputBack  = [System.Drawing.Color]::FromArgb(12,16,29)
        Border     = [System.Drawing.Color]::FromArgb(47,61,95)
        Accent     = [System.Drawing.Color]::FromArgb(129,140,248)
        AccentSoft = [System.Drawing.Color]::FromArgb(38,46,84)
        Muted      = [System.Drawing.Color]::FromArgb(157,171,210)
        MutedStrong= [System.Drawing.Color]::FromArgb(207,218,245)
        Success    = [System.Drawing.Color]::FromArgb(74,222,128)
        Warning    = [System.Drawing.Color]::FromArgb(251,191,36)
        Danger     = [System.Drawing.Color]::FromArgb(248,113,113)
    }
    "Catppuccin Mocha" = @{
        FormBack   = [System.Drawing.Color]::FromArgb(30,30,46)
        Fore       = [System.Drawing.Color]::FromArgb(205,214,244)
        Sidebar    = [System.Drawing.Color]::FromArgb(24,24,37)
        SidebarAlt = [System.Drawing.Color]::FromArgb(49,50,68)
        Main       = [System.Drawing.Color]::FromArgb(30,30,46)
        Surface    = [System.Drawing.Color]::FromArgb(49,50,68)
        SurfaceAlt = [System.Drawing.Color]::FromArgb(69,71,90)
        Footer     = [System.Drawing.Color]::FromArgb(24,24,37)
        BtnBack    = [System.Drawing.Color]::FromArgb(88,91,112)
        InputBack  = [System.Drawing.Color]::FromArgb(36,39,58)
        Border     = [System.Drawing.Color]::FromArgb(108,112,134)
        Accent     = [System.Drawing.Color]::FromArgb(137,180,250)
        AccentSoft = [System.Drawing.Color]::FromArgb(53,68,100)
        Muted      = [System.Drawing.Color]::FromArgb(166,173,200)
        MutedStrong= [System.Drawing.Color]::FromArgb(198,208,245)
        Success    = [System.Drawing.Color]::FromArgb(166,227,161)
        Warning    = [System.Drawing.Color]::FromArgb(249,226,175)
        Danger     = [System.Drawing.Color]::FromArgb(243,139,168)
    }
}

# ==========================================
# 4. DATA DEFINITIONS (THEMES & ICONS)
# ==========================================

$IconDefinitions = [ordered]@{
    "Standard (Default)" = @{ "ID" = "standard"; "Url" = "https://raw.githubusercontent.com/SysAdminDoc/JDownloader-2-Ultimate-Manager/refs/heads/main/Themes/standard.7z" }
    "Material Darker"    = @{ "ID" = "standard"; "Url" = "https://raw.githubusercontent.com/SysAdminDoc/JDownloader-2-Ultimate-Manager/refs/heads/main/Themes/material-darker.7z" }
    "Dark / Minimal"     = @{ "ID" = "minimal"; "Url" = "https://raw.githubusercontent.com/SysAdminDoc/JDownloader-2-Ultimate-Manager/refs/heads/main/Themes/dark.7z" }
}

$ThemeDefinitions = [ordered]@{
    "Synthetica Black Eye" = @{
        "DisplayName" = "Synthetica Black Eye"
        "Desc"        = "High contrast gray and orange theme. Strong separation between panels and controls."
        "LafID"       = "BLACK_EYE"
        "JsonName"    = "SyntheticaBlackEyeLookAndFeel.json"
        "JsonUrl"     = "https://raw.githubusercontent.com/Vinylwalk3r/JDownloader-2-Dark-Theme/refs/heads/master/config/cfg/laf/SyntheticaBlackEyeLookAndFeel.json"
        "PreviewUrl"  = "https://raw.githubusercontent.com/Vinylwalk3r/Jdownloader-2-Dark-Theme/refs/heads/master/images/Download.JPG"
        "ThemeUrl"    = "https://github.com/Vinylwalk3r/JDownloader-2-Dark-Theme"
    }
    "Dracula" = @{
        "DisplayName" = "Dracula"
        "Desc"        = "Purple and teal dark theme with high legibility. Good for low light environments and OLED panels."
        "LafID"       = "FLATLAF_DRACULA"
        "JsonName"    = "FlatDarculaLaf.json"
        "JsonUrl"     = "https://raw.githubusercontent.com/dracula/jdownloader2/refs/heads/master/FlatDarculaLaf.json"
        "PreviewUrl"  = "https://raw.githubusercontent.com/dracula/jdownloader2/master/screenshot.png"
        "ThemeUrl"    = "https://github.com/dracula/jdownloader2"
    }
    "Flat Dark" = @{
        "DisplayName" = "Flat Dark (Mica style)"
        "Desc"        = "Flat dark fluent style with soft contrast. Modern Windows 10 and 11 friendly look."
        "LafID"       = "FLATLAF_DARK"
        "JsonName"    = "FlatDarkLaf.json"
        "JsonUrl"     = "https://raw.githubusercontent.com/ikoshura/JDownloader-Fluent-Theme/refs/heads/main/FlatMacDarkLaf.json"
        "PreviewUrl"  = "https://raw.githubusercontent.com/ikoshura/JDownloader-Fluent-Theme/main/Assets/MicaUpdate.png"
        "ThemeUrl"    = "https://github.com/ikoshura/JDownloader-Fluent-Theme"
    }
}

# ==========================================
# 5. EMBEDDED CONFIGS (TEMPLATES)
# ==========================================
$Template_GUI = @'
{ "overviewpaneldownloadlinksfailedcountvisible": false, "downloadview": "ALL", "linkpropertiespaneldownloadpasswordvisible": true, "speedmetervisible": true, "overviewpaneldownloadpackagecountvisible": true, "linkpropertiespanelfilenamevisible": true, "titlepattern": "|#TITLE|| - #SPEED/s|| - #UPDATENOTIFY|", "overviewpaneltotalinfovisible": true, "linkpropertiespanelchecksumvisible": true, "downloadspropertiespanelsavetovisible": true, "packagesbackgroundhighlightenabled": false, "overviewpaneldownloadlinkcountvisible": true, "downloadspropertiespanelpackagenamevisible": true, "overviewpaneldownloadlinksfinishedcountvisible": false, "overviewpanelsmartinfovisible": true, "availablecolumntextvisible": false, "overviewpaneldownloadbytesremainingvisible": true, "bannerenabled": false, "showfullhostname": false, "overviewpanellinkgrabberstatusonlinevisible": true, "linkpropertiespanelcommentvisible": true, "clipboardmonitored": true, "donatebuttonstate": "ALWAYS_HIDDEN", "donatebuttonlatestautochange": 1764274189351, "filecountinsizecolumnvisible": true, "clipboardskipmode": "ON_STARTUP", "premiumexpirewarningenabled": false, "downloadstablerefreshinterval": 1000, "overviewpaneldownloadpanelincludedisabledlinks": true, "tablewraparoundenabled": true, "specialdealoboomdialogvisibleonstartup": false, "tooltipenabled": true, "statusbaraddpremiumbuttonvisible": false, "captchadialogborderaroundimageenabled": true, "tablemouseoverhighlightenabled": true, "linkpropertiespanelsavetovisible": true, "overviewpanellinkgrabberlinkscountvisible": true, "clipboardmonitorprocesshtmlflavor": true, "overviewpanelselectedinfovisible": true, "linkpropertiespaneldownloadfromvisible": false, "sortcolumnhighlightenabled": true, "colorediconsfordisabledhostercolumnenabled": true, "premiumalertspeedcolumnenabled": false, "premiumalertetacolumnenabled": false, "premiumalerttaskcolumnenabled": false, "premiumdisabledwarningflashenabled": false, "downloadspropertiespanelcommentvisible": true, "overviewpaneldownloadtotalbytesvisible": true, "overviewpanellinkgrabberpackagecountvisible": true, "windowswindowmanagerforegroundlocktimeout": 2147483647, "linkgrabbertabpropertiespanelvisible": true, "configviewvisible": true, "downloadstabpropertiespanelvisible": true, "selecteddownloadsearchcategory": "FILENAME", "overviewpaneldownloadetavisible": true, "savedownloadviewcrosssessionenabled": false, "overviewpanellinkgrabberstatusunknownvisible": true, "myjdownloaderviewvisible": false, "downloadspropertiespanelchecksumvisible": true, "downloadspropertiespanelfilenamevisible": false, "speedmetertimeframe": 30000, "mainwindowalwaysontop": false, "overviewpaneldownloadconnectionsvisible": true, "helpdialogsenabled": false, "lookandfeeltheme": "FLATLAF_DARK", "linkpropertiespanelarchivepasswordvisible": true, "horizontalscrollbarsinlinkgrabbertableenabled": false, "downloadspropertiespaneldownloadfromvisible": false, "overviewpanellinkgrabberstatusofflinevisible": true, "balloonnotificationenabled": true, "activeconfigpanel": "jd.gui.swing.jdgui.views.settings.panels.advanced.AdvancedSettings", "donationnotifyid": null, "speedmeterframespersecond": 4, "linkpropertiespanelpackagenamevisible": true, "passwordprotectionenabled": false, "specialdealsenabled": false, "overviewpaneldownloadspeedvisible": true, "premiumstatusbardisplay": "GROUP_BY_ACCOUNT_TYPE", "maxsizeunit": "TiB", "downloadpaneloverviewsettingsvisible": false, "tooltipdelay": 2000, "overviewpaneldownloadbytesloadedvisible": true, "speedinwindowtitle": "WHEN_WINDOW_IS_MINIMIZED", "overviewpanellinkgrabbertotalbytesvisible": true, "selectedlinkgrabbersearchcategory": "FILENAME", "downloadtaboverviewvisible": true, "rlywarnlevel": "NORMAL", "overviewpanellinkgrabberhostercountvisible": true, "downloadspropertiespaneldownloadpasswordvisible": true, "dialogdefaulttimeoutinms": 20000, "overviewpanellinkgrabberincludedisabledlinks": true, "hidesinglechildpackages": false, "linkgrabberbottombarposition": "SOUTH", "linkgrabbertaboverviewvisible": true, "overviewpaneldownloadlinksskippedcountvisible": false, "windowswindowmanageraltkeyworkaroundenabled": true, "updatebuttonflashingenabled": false, "overviewpanelvisibleonlyinfovisible": true, "linkgrabbersidebarvisible": true, "downloadspropertiespanelarchivepasswordvisible": true, "captchaexchangeenabled": false, "hatecaptchastextincaptchadialogvisible": false, "taskbarflashenabled": false, "clipboarddisabledwarningflashenabled": false, "windowstaskbarprogressdisplay": "TOTAL_PROGRESS" }
'@
$Template_General = '{"maxsimultanedownloadsperhost":1,"delaywritemode":"AUTO","iffileexistsaction":"ASK_FOR_EACH_FILE","dupemanagerenabled":true,"forcemirrordetectioncaseinsensitive":true,"autoopencontainerafterdownload":true,"preferbouncycastlefortls":false,"autostartdownloadoption":"ONLY_IF_EXIT_WITH_RUNNING_DOWNLOADS","maxsimultanedownloads":3,"pausespeed":10240,"defaultdownloadfolder":"C:\\Downloads","windowsjnaidledetectorenabled":true,"downloadspeedlimitrememberedenabled":true,"closedwithrunningdownloads":false,"autostartcountdownseconds":10,"maxdownloadsperhostenabled":false,"maxchunksperfile":1,"sambaprefetchenabled":true,"showcountdownonautostartdownloads":true,"savelinkgrabberlistenabled":true,"onskipduetoalreadyexistsaction":"SKIP_FILE","hashretryenabled":false,"sharedmemorystateenabled":false,"convertrelativepathsjdroot":true,"keepxoldlists":5,"useavailableaccounts":true,"cleanupafterdownloadaction":"REMOVE_FINISHED_AND_DELETE_EXTRACTED","hashcheckenabled":true,"downloadspeedlimitenabled":false,"downloadspeedlimit":51200,"hidesinglechildpackages":true,"maxpluginretries":3,"forcedfreespaceondisk":512,"freespacecheckenabled":true,"useoriginallastmodified":false,"maxbuffersize":500,"flushbuffertimeout":120000,"flushbufferlevel":80,"deleteemptysubfoldersafterdeletingdownloadedfilesenabled":true,"cleanupfilenames":false,"waittimeonconnectionloss":300000,"downloadtempunavailableretrywaittime":1800000,"downloadhostunavailableretrywaittime":3600000}'
$Template_Tray = '{"freshinstall":false,"onminimizeaction":"TO_TASKBAR","tooltipenabled":true,"trayiconclipboardindicatorenabled":false,"oncloseaction":"ASK","tooglewindowstatuswithsingleclickenabled":false,"greyiconenabled":false,"gnometrayicontransparentenabled":true,"enabled":true,"startminimizedenabled":false,"trayonlyvisibleifwindowishiddenenabled":false}'
$Template_Update = '{"autoupdatecheckenabled":true,"installUpdatesSilentlyIfPossibleEnabled":true,"doAskMeBeforeInstallingAnUpdateEnabled":false,"installUpdatesOnExitEnabled":true,"jarDiffEnabled":true}'
$Template_BubbleNotify = '{"bubblenotifyenabledstate":"NEVER"}'

# ==========================================
# 6. CORE UTILITIES & LOGGING
# ==========================================

function Log-Status {
    param([string]$Text, [string]$Type = "INFO")
    $timestamp = (Get-Date).ToString('HH:mm:ss')
    $msg = "[$timestamp] [$Type] $Text"
    # Try/Catch wrap for logging
    try { Add-Content -Path $LogFile -Value $msg -ErrorAction SilentlyContinue } catch {}

    $script:LastStatusText = $Text
    $script:LastStatusType = $Type

    try { Update-StatusVisual -Text $Text -Type $Type } catch {}
}

function Save-Settings {
    param($SettingsObj)
    if (-not $SettingsObj) { return }
    try {
        $json = $SettingsObj | ConvertTo-Json -Depth 10
        $tmp = "$SettingsFile.tmp"
        Set-Content -Path $tmp -Value $json -Encoding UTF8 -ErrorAction Stop
        # Atomic replace: move temp into place so a crash mid-write never corrupts settings.
        Move-Item -Path $tmp -Destination $SettingsFile -Force -ErrorAction Stop
    } catch {
        Log-Status "Failed to save settings: $_" "ERROR"
        try { Remove-Item "$SettingsFile.tmp" -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Get-SettingsSourcePath {
    if (Test-Path $SettingsFile) { return $SettingsFile }
    if (Test-Path $LegacySettingsFile) {
        # Migrate legacy settings, then park the old copy alongside as a one-time breadcrumb
        # so we don't keep re-migrating on every launch.
        try {
            Copy-Item $LegacySettingsFile $SettingsFile -Force -ErrorAction Stop
            try { Rename-Item -Path $LegacySettingsFile -NewName 'settings.migrated.json' -Force -ErrorAction SilentlyContinue } catch {}
            Log-Status "Migrated legacy settings from ProgramData to LocalAppData." "INFO"
        } catch {
            Log-Status "Failed to migrate legacy settings: $_" "WARN"
        }
        return $SettingsFile
    }
    return $SettingsFile
}

function Load-Settings {
    $sourcePath = Get-SettingsSourcePath
    if (-not (Test-Path $sourcePath)) { return $null }
    try {
        $raw = Get-Content $sourcePath -Raw -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        # Corrupt settings file - quarantine it so the next run isn't stuck in a bad state.
        try {
            $bad = "$sourcePath.bad-$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Move-Item -Path $sourcePath -Destination $bad -Force -ErrorAction SilentlyContinue
            Log-Status "Settings file was unreadable and was quarantined: $bad" "WARN"
        } catch {}
        return $null
    }
}

function Save-ResumeState {
    param($State)
    if (-not $State) { return $null }
    if (-not (Test-Path $WorkDir)) {
        try { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null } catch {}
    }
    # Unique filename avoids collisions if the user launches two copies back-to-back.
    $resumeFile = Join-Path $WorkDir ("resume-state-{0}-{1:N}.json" -f $PID, [guid]::NewGuid())
    try {
        $tmp = "$resumeFile.tmp"
        $State | ConvertTo-Json -Depth 10 | Set-Content $tmp -Encoding UTF8 -ErrorAction Stop
        Move-Item -Path $tmp -Destination $resumeFile -Force -ErrorAction Stop
        return $resumeFile
    } catch {
        Log-Status "Failed to preserve the current workspace before requesting admin approval." "ERROR"
        try { Remove-Item "$resumeFile.tmp" -Force -ErrorAction SilentlyContinue } catch {}
        return $null
    }
}

function Load-ResumeState {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) { return $null }
    # Resume files are read from TEMP which is per-user but still untrusted if the file is stale.
    # Defensive: size cap (1 MB) and always remove after reading, regardless of parse outcome.
    try {
        $file = Get-Item -Path $Path -ErrorAction Stop
        if ($file.Length -gt 1MB) {
            Log-Status "Resume state file is unexpectedly large; refusing to load." "WARN"
            return $null
        }
        return Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Log-Status "The saved workspace handoff could not be restored. Start the apply flow again." "WARN"
        return $null
    } finally {
        try { Remove-Item $Path -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Request-ElevatedApply {
    param($State)
    $normalizedState = Get-NormalizedStateObject -State $State
    $resumeFile = Save-ResumeState -State $normalizedState
    if (-not $resumeFile) { return $false }

    # When launched via `irm | iex`, $PSCommandPath is null. Prefer MyInvocation,
    # then fall back to the compiled EXE in the install folder if present.
    $scriptPath = $null
    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        $scriptPath = $PSCommandPath
    } elseif ($MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
        $scriptPath = $MyInvocation.MyCommand.Path
    }

    Write-Host "Requesting administrative privileges. Accept the Windows prompt to continue this run." -ForegroundColor Yellow
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    if ($scriptPath -and (Test-Path $scriptPath)) {
        $processInfo.FileName = "powershell.exe"
        $portableArg = if ($script:PortableMode) { " -Portable" } else { "" }
        $processInfo.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$scriptPath`" -ResumeApply -ResumeStateFile `"$resumeFile`"$portableArg"
    } else {
        # No resolvable script on disk (web-launched via iex). Re-fetch the canonical script,
        # save it locally, and relaunch elevated with the resume handoff.
        $webScript = Join-Path $AppDataDir "JDownloader 2 Ultimate Manager.ps1"
        try {
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/SysAdminDoc/JDownloader-2-Ultimate-Manager/refs/heads/main/JDownloader%202%20Ultimate%20Manager.ps1" `
                -OutFile $webScript -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        } catch {
            Log-Status "Could not stage the script for elevation (web fetch failed). No changes were written." "ERROR"
            return $false
        }
        $processInfo.FileName = "powershell.exe"
        $portableArg = if ($script:PortableMode) { " -Portable" } else { "" }
        $processInfo.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$webScript`" -ResumeApply -ResumeStateFile `"$resumeFile`"$portableArg"
    }
    $processInfo.Verb = "RunAs"
    try {
        [System.Diagnostics.Process]::Start($processInfo) | Out-Null
        return $true
    } catch {
        Log-Status "Administrative approval was canceled. No changes were written." "WARN"
        return $false
    }
}

function Test-LooksLikeHtmlErrorPage {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    try {
        $fs = [System.IO.File]::OpenRead($Path)
        try {
            $buf = New-Object byte[] 512
            $read = $fs.Read($buf, 0, $buf.Length)
            if ($read -le 0) { return $false }
            $head = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read).ToLowerInvariant().TrimStart()
            return ($head.StartsWith('<!doctype html') -or $head.StartsWith('<html') -or $head.StartsWith('<?xml'))
        } finally { $fs.Dispose() }
    } catch { return $false }
}

function Download-File {
    param(
        [string]$Url,
        [string]$Destination,
        [int]$MinBytes = 1024,
        [switch]$AllowSmall
    )
    if ([string]::IsNullOrWhiteSpace($Url) -or [string]::IsNullOrWhiteSpace($Destination)) {
        Log-Status "Download-File called with empty URL or destination." "ERROR"
        return $false
    }
    if ($AllowSmall) { $MinBytes = 1 }

    # Remove any prior stale file so a failed download never appears as success.
    if (Test-Path $Destination) {
        try { Remove-Item $Destination -Force -ErrorAction Stop } catch {}
    }

    Log-Status "Downloading: $(Split-Path $Destination -Leaf)"

    $maxRetries = 3
    $attempt = 0
    $success = $false
    while ($attempt -lt $maxRetries -and -not $success) {
        $attempt++
        try {
            if (-not (Get-Module -Name BitsTransfer)) { Import-Module BitsTransfer -ErrorAction Stop }
            Start-BitsTransfer -Source $Url -Destination $Destination -ErrorAction Stop -Priority Foreground
            $success = $true
        } catch {
            Log-Status "BITS attempt $attempt failed: $_" "WARN"
            try {
                Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
                $success = $true
            } catch {
                Log-Status "HTTP attempt $attempt failed from $Url. $_" "WARN"
            }
        }
        if (-not $success -and $attempt -lt $maxRetries) {
            Start-Sleep -Milliseconds ($attempt * 1500)
        }
    }

    if ($success -and (Test-Path $Destination)) {
        $size = (Get-Item $Destination).Length
        if ($size -lt $MinBytes) {
            Log-Status "Downloaded file is suspiciously small ($size bytes) for $Url. Marking failed." "ERROR"
            try { Remove-Item $Destination -Force -ErrorAction SilentlyContinue } catch {}
            return $false
        }
        # Reject content that is clearly an HTML error page served with HTTP 200 (GitHub 404, captive portals, etc.).
        if (-not $AllowSmall -and (Test-LooksLikeHtmlErrorPage -Path $Destination)) {
            Log-Status "Download returned an HTML page instead of the expected payload: $Url" "ERROR"
            try { Remove-Item $Destination -Force -ErrorAction SilentlyContinue } catch {}
            return $false
        }
    }

    if (-not $success) { Log-Status "Download definitively failed: $Url" "ERROR" }
    return $success
}

function Get-7Zip {
    $seven = "$AppDataDir\7zr.exe"
    if (-not (Test-Path $seven)) {
        if (-not (Download-File -Url "https://www.7-zip.org/a/7zr.exe" -Destination $seven)) {
            Log-Status "Unable to download 7zr.exe." "ERROR"
            return $null
        }
    }
    return $seven
}

# Enhanced Async Job Manager
function Start-ThemeImagePreload {
    param($Definitions)
    if (-not $Definitions) { return }
    Log-Status "Starting background theme fetch..."

    # Instance-unique job name so two copies of the app can't stomp on each other.
    $jobName = "JD2UM_ThemeFetcher_$PID"

    # Clean any prior job this process owns.
    if ($GlobalJobs.ContainsKey($jobName) -and $GlobalJobs[$jobName]) {
        try { Stop-Job -Job $GlobalJobs[$jobName] -ErrorAction SilentlyContinue } catch {}
        try { Remove-Job -Job $GlobalJobs[$jobName] -Force -ErrorAction SilentlyContinue } catch {}
    }

    $jobScript = {
        param($defs)
        $results = @{}
        $web = New-Object System.Net.WebClient
        try {
            # Enforce TLS 1.2 in the child runspace as well.
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            foreach ($key in $defs.Keys) {
                $url = $defs[$key].PreviewUrl
                if ($url) {
                    try { $results[$key] = $web.DownloadData($url) }
                    catch { $results[$key] = $null }
                }
            }
        } finally { $web.Dispose() }
        return $results
    }

    $j = Start-Job -ScriptBlock $jobScript -ArgumentList $Definitions -Name $jobName
    $GlobalJobs[$jobName] = $j

    # Capture metadata the Tick closure needs - reduces surface for cross-scope bugs.
    $script:ThemeFetchStart = Get-Date
    $script:ThemeFetchTimeoutSeconds = 60

    $checkTimer = New-Object System.Windows.Forms.Timer
    $checkTimer.Interval = 500
    $checkTimer.Tag = $jobName
    $checkTimer.Add_Tick({
        param($src, $evt)
        $name = [string]$src.Tag
        $jb = Get-Job -Name $name -ErrorAction SilentlyContinue

        # Timeout safety so the timer doesn't poll forever if the job is stuck.
        $elapsed = ((Get-Date) - $script:ThemeFetchStart).TotalSeconds
        if ($elapsed -gt $script:ThemeFetchTimeoutSeconds) {
            try { $src.Stop(); $src.Dispose() } catch {}
            if ($jb) {
                try { Stop-Job -Job $jb -ErrorAction SilentlyContinue } catch {}
                try { Remove-Job -Job $jb -Force -ErrorAction SilentlyContinue } catch {}
            }
            Log-Status "Theme preview fetch timed out; previews may show as loading." "WARN"
            return
        }

        if (-not $jb) {
            try { $src.Stop(); $src.Dispose() } catch {}
            return
        }

        if ($jb.State -eq "Completed") {
            try { $src.Stop(); $src.Dispose() } catch {}
            try {
                $res = Receive-Job -Job $jb -ErrorAction SilentlyContinue
                Remove-Job -Job $jb -Force -ErrorAction SilentlyContinue

                if ($res) {
                    foreach ($k in $res.Keys) {
                        $bytes = $res[$k]
                        if (-not $bytes) { continue }
                        $ms = New-Object System.IO.MemoryStream(,$bytes)
                        $img = $null; $cacheImg = $null
                        try {
                            $img = [System.Drawing.Image]::FromStream($ms)
                            $cacheImg = New-Object System.Drawing.Bitmap($img)
                            if ($script:ThemeImageCache.ContainsKey($k)) {
                                try { $script:ThemeImageCache[$k].Dispose() } catch {}
                            }
                            $script:ThemeImageCache[$k] = $cacheImg
                        } catch {
                            # Bad image payload - ignore and keep whatever was there before.
                        } finally {
                            if ($img) { try { $img.Dispose() } catch {} }
                            try { $ms.Dispose() } catch {}
                        }
                    }
                }
                Log-Status "Theme previews loaded." "SUCCESS"
                if ($CboTheme -and $CboTheme.IsHandleCreated) {
                    try { $CboTheme.Invoke([Action]{ Update-ThemePreview }) } catch {}
                }
            } catch {
                Log-Status "Error processing theme images: $_" "ERROR"
            }
        } elseif ($jb.State -eq "Failed" -or $jb.State -eq "Stopped") {
            try { $src.Stop(); $src.Dispose() } catch {}
            try { Remove-Job -Job $jb -Force -ErrorAction SilentlyContinue } catch {}
            Log-Status "Theme preview fetch failed; previews remain unavailable." "WARN"
        }
    })
    [void]$GlobalTimers.Add($checkTimer)
    $checkTimer.Start()
}

# Cleanup Helper
function Cleanup-Resources {
    Log-Status "Cleaning up resources..."
    foreach ($t in $GlobalTimers) {
        if ($t) {
            try { $t.Stop() } catch {}
            try { $t.Dispose() } catch {}
        }
    }
    foreach ($j in $GlobalJobs.Values) {
        if ($j) {
            try { Stop-Job $j -ErrorAction SilentlyContinue } catch {}
            try { Remove-Job $j -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    foreach ($img in $ThemeImageCache.Values) {
        if ($img) { try { $img.Dispose() } catch {} }
    }
    if ($LiveCaptchaImage -and $LiveCaptchaImage.Image) {
        try { $LiveCaptchaImage.Image.Dispose() } catch {}
        try { $LiveCaptchaImage.Image = $null } catch {}
    }
    $ThemeImageCache.Clear()
    $GlobalTimers.Clear()
    $GlobalJobs.Clear()
}

function Enable-DoubleBuffer {
    param($Control)
    if (-not $Control) { return }
    try {
        $prop = $Control.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]("NonPublic,Instance"))
        if ($prop) { $prop.SetValue($Control, $true, $null) }
    } catch {}
}

function Get-ActivePalette {
    if ($GuiThemes.ContainsKey($script:CurrentGuiTheme)) {
        return $GuiThemes[$script:CurrentGuiTheme]
    }
    return $GuiThemes["Dark (Default)"]
}

function Set-CueBanner {
    param($Control, [string]$Text)
    if (-not $Control -or [string]::IsNullOrWhiteSpace($Text)) { return }
    try {
        $null = $Control.Handle
        [NativeGuiApi]::SendMessage($Control.Handle, 0x1501, [IntPtr]1, $Text) | Out-Null
    } catch {}
}

function Set-ControlMetadata {
    param($Control, [string]$Name, [string]$Description, [int]$TabIndex = -1)
    if (-not $Control) { return }
    if ($Name) { $Control.AccessibleName = $Name }
    if ($Description) { $Control.AccessibleDescription = $Description }
    if ($TabIndex -ge 0) { $Control.TabIndex = $TabIndex }
}

function Update-StatusVisual {
    param([string]$Text, [string]$Type = "INFO")

    $script:LastStatusText = $Text
    $script:LastStatusType = $Type

    if (-not $StatusLabel) { return }

    $palette = Get-ActivePalette
    $statusColor = switch ($Type.ToUpperInvariant()) {
        "SUCCESS" { $palette.Success; break }
        "WARN"    { $palette.Warning; break }
        "ERROR"   { $palette.Danger; break }
        "FATAL"   { $palette.Danger; break }
        "DEBUG"   { $palette.Muted; break }
        default   { $palette.MutedStrong; break }
    }

    $prefix = switch ($Type.ToUpperInvariant()) {
        "SUCCESS" { "Done" }
        "WARN"    { "Attention" }
        "ERROR"   { "Error" }
        "FATAL"   { "Critical" }
        "DEBUG"   { "Debug" }
        default   { "Status" }
    }

    if ($StatusLabel.IsHandleCreated) {
        # Only marshal onto the UI thread when necessary - avoids a useless cross-thread hop
        # (and its exception risk) when Update-StatusVisual is already running on that thread.
        if ($StatusLabel.InvokeRequired) {
            try {
                $StatusLabel.Invoke([Action[string, object, string]]{
                    param($t, $c, $pfx)
                    $StatusLabel.Text = "${pfx}: $t"
                    $StatusLabel.ForeColor = $c
                }, $Text, $statusColor, $prefix)
            } catch {}
        } else {
            $StatusLabel.Text = "${prefix}: $Text"
            $StatusLabel.ForeColor = $statusColor
        }
    } else {
        $StatusLabel.Text = "${prefix}: $Text"
        $StatusLabel.ForeColor = $statusColor
    }
}

# Enhanced Theme Engine
function Apply-GuiTheme {
    param($ThemeName, $Root = $Form)
    $pal = $GuiThemes[$ThemeName]
    if (-not $pal) {
        $ThemeName = "Dark (Default)"
        $pal = $GuiThemes[$ThemeName]
    }

    $script:CurrentGuiTheme = $ThemeName
    $isLightPalette = $pal.FormBack.GetBrightness() -gt 0.6

    if ($Root) {
        $Root.BackColor = $pal.FormBack
        $Root.ForeColor = $pal.Fore
    }
    
    function Update-Control {
        param($ctrl)
        if (-not $ctrl) { return }
        # A disposed control throws on property access; skip it rather than crash a re-theme
        # (important during form teardown or if we re-theme stale refs).
        try { if ($ctrl.IsDisposed) { return } } catch { return }

        $styled = $false
        if ($ctrl.Tag -is [string]) {
            switch ($ctrl.Tag) {
                "Sidebar" { $ctrl.BackColor = $pal.Sidebar; $styled=$true }
                "SidebarAlt" { $ctrl.BackColor = $pal.SidebarAlt; $styled=$true }
                "MainPanel" { $ctrl.BackColor = $pal.Main; $styled=$true }
                "Footer" { $ctrl.BackColor = $pal.Footer; $styled=$true }
                "Page" { $ctrl.BackColor = $pal.Main; $styled=$true }
                "Canvas" { $ctrl.BackColor = $pal.Main; $styled=$true }
                "Surface" { $ctrl.BackColor = $pal.Surface; $styled=$true }
                "SurfaceAlt" { $ctrl.BackColor = $pal.SurfaceAlt; $styled=$true }
                "Callout" { $ctrl.BackColor = $pal.AccentSoft; $styled=$true }
                "PreviewPanel" { $ctrl.BackColor = $pal.SurfaceAlt; $styled=$true }
                "PrimaryButton" { $ctrl.BackColor = $pal.Accent; $ctrl.ForeColor = [System.Drawing.Color]::White; $styled=$true }
                "DangerButton" { $ctrl.BackColor = $pal.Danger; $ctrl.ForeColor = [System.Drawing.Color]::White; $styled=$true }
                "SuccessButton" { $ctrl.BackColor = $pal.Success; $ctrl.ForeColor = [System.Drawing.Color]::Black; $styled=$true }
                "NavButton" { $ctrl.BackColor = $pal.Sidebar; $ctrl.ForeColor = $pal.MutedStrong; $styled=$true }
                "NavButtonActive" { $ctrl.BackColor = $pal.SidebarAlt; $ctrl.ForeColor = $pal.Fore; $styled=$true }
                "SecondaryButton" { $ctrl.BackColor = $pal.BtnBack; $ctrl.ForeColor = $pal.Fore; $styled=$true }
                "Input" { $ctrl.BackColor = $pal.InputBack; $ctrl.ForeColor = $pal.Fore; $styled=$true }
                "SectionHeader" { $ctrl.ForeColor = $pal.Fore; $styled=$true }
                "SubHeader" { $ctrl.ForeColor = $pal.MutedStrong; $styled=$true }
                "BodyMuted" { $ctrl.ForeColor = $pal.Muted; $styled=$true }
                "MutedStrong" { $ctrl.ForeColor = $pal.MutedStrong; $styled=$true }
                "BadgeNeutral" { $ctrl.BackColor = if ($isLightPalette) { $pal.SurfaceAlt } else { $pal.SidebarAlt }; $ctrl.ForeColor = $pal.MutedStrong; $styled=$true }
                "BadgeAccent" { $ctrl.BackColor = if ($isLightPalette) { [System.Windows.Forms.ControlPaint]::Light($pal.Accent, 0.86) } else { $pal.AccentSoft }; $ctrl.ForeColor = if ($isLightPalette) { [System.Windows.Forms.ControlPaint]::Dark($pal.Accent, 0.1) } else { [System.Windows.Forms.ControlPaint]::Light($pal.Accent, 0.18) }; $styled=$true }
                "BadgeSuccess" { $ctrl.BackColor = if ($isLightPalette) { [System.Windows.Forms.ControlPaint]::Light($pal.Success, 0.84) } else { [System.Windows.Forms.ControlPaint]::Dark($pal.Success, 0.76) }; $ctrl.ForeColor = if ($isLightPalette) { [System.Windows.Forms.ControlPaint]::Dark($pal.Success, 0.4) } else { [System.Windows.Forms.ControlPaint]::Light($pal.Success, 0.1) }; $styled=$true }
                "BadgeWarning" { $ctrl.BackColor = if ($isLightPalette) { [System.Windows.Forms.ControlPaint]::Light($pal.Warning, 0.84) } else { [System.Windows.Forms.ControlPaint]::Dark($pal.Warning, 0.76) }; $ctrl.ForeColor = if ($isLightPalette) { [System.Windows.Forms.ControlPaint]::Dark($pal.Warning, 0.45) } else { [System.Windows.Forms.ControlPaint]::Light($pal.Warning, 0.1) }; $styled=$true }
                "BadgeDanger" { $ctrl.BackColor = if ($isLightPalette) { [System.Windows.Forms.ControlPaint]::Light($pal.Danger, 0.85) } else { [System.Windows.Forms.ControlPaint]::Dark($pal.Danger, 0.76) }; $ctrl.ForeColor = if ($isLightPalette) { [System.Windows.Forms.ControlPaint]::Dark($pal.Danger, 0.4) } else { [System.Windows.Forms.ControlPaint]::Light($pal.Danger, 0.1) }; $styled=$true }
                "NavIndicator" { $ctrl.BackColor = $pal.Accent; $styled=$true }
                "QueueGrid" {
                    $ctrl.BackgroundColor = $pal.InputBack
                    $ctrl.GridColor = $pal.Border
                    $ctrl.ForeColor = $pal.Fore
                    $ctrl.ColumnHeadersDefaultCellStyle.BackColor = $pal.SurfaceAlt
                    $ctrl.ColumnHeadersDefaultCellStyle.ForeColor = $pal.Fore
                    $ctrl.DefaultCellStyle.BackColor = $pal.InputBack
                    $ctrl.DefaultCellStyle.ForeColor = $pal.Fore
                    $ctrl.DefaultCellStyle.SelectionBackColor = $pal.AccentSoft
                    $ctrl.DefaultCellStyle.SelectionForeColor = $pal.Fore
                    $styled=$true
                }
            }
        }

        # Fallback styles
        if (-not $styled) {
            if ($ctrl -is [System.Windows.Forms.Panel]) {
                if ($ctrl.Name -eq "Sidebar") { $ctrl.BackColor = $pal.Sidebar }
                elseif ($ctrl.Name -eq "MainPanel") { $ctrl.BackColor = $pal.Main }
                elseif ($ctrl.Name -eq "Footer") { $ctrl.BackColor = $pal.Footer }
                else { $ctrl.BackColor = $pal.Main }
            }
            if ($ctrl -is [System.Windows.Forms.Button]) {
                if ($ctrl.Tag -eq "SidebarBtn") {
                    $ctrl.BackColor = $pal.Sidebar
                    $ctrl.ForeColor = $pal.MutedStrong
                } else {
                    $ctrl.BackColor = $pal.BtnBack
                    $ctrl.ForeColor = $pal.Fore
                }
            }
            if ($ctrl -is [System.Windows.Forms.TextBox] -or $ctrl -is [System.Windows.Forms.NumericUpDown] -or $ctrl -is [System.Windows.Forms.ComboBox]) {
                $ctrl.BackColor = $pal.InputBack
                $ctrl.ForeColor = $pal.Fore
                if ($ctrl -is [System.Windows.Forms.TextBox]) { $ctrl.BorderStyle = "FixedSingle" }
            }
            if ($ctrl -is [System.Windows.Forms.Label] -or $ctrl -is [System.Windows.Forms.CheckBox]) {
                $ctrl.ForeColor = $pal.Fore
            }
        }

        if ($ctrl -is [System.Windows.Forms.Button]) {
            $ctrl.FlatAppearance.BorderSize = if ($ctrl.Tag -eq "SidebarBtn") { 0 } else { 1 }
            $ctrl.FlatAppearance.BorderColor = if ($ctrl.Tag -eq "PrimaryButton") { [System.Windows.Forms.ControlPaint]::Dark($pal.Accent, 0.2) } elseif ($ctrl.Tag -eq "DangerButton") { [System.Windows.Forms.ControlPaint]::Dark($pal.Danger, 0.2) } elseif ($ctrl.Tag -eq "SuccessButton") { [System.Windows.Forms.ControlPaint]::Dark($pal.Success, 0.25) } else { $pal.Border }
            $ctrl.FlatAppearance.MouseOverBackColor = [System.Windows.Forms.ControlPaint]::Light($ctrl.BackColor, 0.08)
            $ctrl.FlatAppearance.MouseDownBackColor = [System.Windows.Forms.ControlPaint]::Dark($ctrl.BackColor, 0.05)
            $ctrl.Cursor = [System.Windows.Forms.Cursors]::Hand
        }

        if ($ctrl -is [System.Windows.Forms.TextBox] -or $ctrl -is [System.Windows.Forms.NumericUpDown] -or $ctrl -is [System.Windows.Forms.ComboBox]) {
            $ctrl.BackColor = $pal.InputBack
            $ctrl.ForeColor = $pal.Fore
        }

        if ($ctrl -is [System.Windows.Forms.LinkLabel]) {
            $ctrl.LinkColor = $pal.Accent
            $ctrl.ActiveLinkColor = [System.Windows.Forms.ControlPaint]::Light($pal.Accent, 0.15)
            $ctrl.VisitedLinkColor = $pal.Accent
            $ctrl.ForeColor = $pal.MutedStrong
        }
        
        # Recurse into children. Guarded because accessing .Controls on a partially-disposed
        # container can throw, and we don't want a half-torn form to wedge a theme-change.
        try {
            if ($ctrl.Controls -and $ctrl.Controls.Count -gt 0) {
                foreach ($c in $ctrl.Controls) { Update-Control $c }
            }
        } catch {}
    }

    Update-Control $Root
    if ($Root -eq $Form) {
        try { Update-NavigationState } catch {}
        try { Update-StatusVisual -Text $script:LastStatusText -Type $script:LastStatusType } catch {}
    }
}

function Detect-SystemTheme {
    Log-Status "Detecting system theme..."
    try {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        $val = Get-ItemProperty -Path $key -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue
        if ($val -and $val.AppsUseLightTheme -eq 1) {
            return "Light"
        } else {
            return "Catppuccin Mocha"
        }
    } catch {
        return "Dark (Default)"
    }
}

# ==========================================
# 7. JDOWNLOADER LOGIC
# ==========================================
function Detect-JDPath {
    # Build candidate list from environment-derived roots (avoids hardcoded C:/D: assumptions).
    $candidates = New-Object System.Collections.Generic.List[string]
    $roots = @(
        $env:ProgramFiles
        ${env:ProgramFiles(x86)}
        $env:LOCALAPPDATA
        $env:APPDATA
        $env:USERPROFILE
        $env:ProgramData
    )
    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        foreach ($leaf in 'JDownloader 2','JDownloader 2.0','JDownloader') {
            $candidates.Add((Join-Path $root $leaf))
        }
    }
    # Common alternate drives - only probe drives that actually exist.
    foreach ($drive in 'D:','E:','F:') {
        $driveRoot = "$drive\"
        if (Test-Path -LiteralPath $driveRoot) {
            $candidates.Add(($drive + '\JDownloader 2'))
            $candidates.Add(($drive + '\JDownloader'))
        }
    }

    foreach ($p in ($candidates | Select-Object -Unique)) {
        try { if (Test-Path (Join-Path $p 'JDownloader2.exe')) { return $p } } catch {}
    }

    # Registry fallback for non-standard install locations.
    try {
        $regPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        foreach ($rp in $regPaths) {
            $entries = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match 'JDownloader' -and $_.InstallLocation }
            foreach ($e in $entries) {
                $loc = ([string]$e.InstallLocation).TrimEnd('\')
                if (-not [string]::IsNullOrWhiteSpace($loc) -and (Test-Path (Join-Path $loc 'JDownloader2.exe'))) { return $loc }
            }
        }
    } catch {}
    return $null
}

# Safer path-based kill logic
function Kill-JDownloader {
    Log-Status "Terminating JDownloader processes..."
    $procs = Get-Process -Name "javaw", "JDownloader2" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        try {
            # Only kill javaw instances that belong to a JDownloader install (MainModule may be blocked
            # for 64-bit processes when running non-elevated - fall back to process name check).
            $path = $null
            try { $path = $p.MainModule.FileName } catch { $path = $null }
            $shouldKill = $false
            if ($path -and $path -match 'JDownloader') {
                $shouldKill = $true
            } elseif ($p.ProcessName -eq 'JDownloader2') {
                $shouldKill = $true
            }
            if ($shouldKill) {
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    Start-Sleep -Seconds 1
}

function Backup-JD {
    param([string]$InstallPath, [int]$KeepCount = 10)
    if ([string]::IsNullOrWhiteSpace($InstallPath)) { return }
    $cfgDir = Join-Path $InstallPath 'cfg'
    if (-not (Test-Path $cfgDir)) { return }
    $stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $backupParent = Join-Path $InstallPath 'cfg-backup'
    $backupRoot   = Join-Path $backupParent $stamp
    try {
        New-Item -ItemType Directory -Path $backupRoot -Force -ErrorAction Stop | Out-Null
        Get-ChildItem $cfgDir -Exclude "tmp","logs","*.part","*.tmp","linkcollector" -ErrorAction SilentlyContinue |
            Copy-Item -Destination $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Log-Status "Config backup skipped: $_" "WARN"
        return
    }

    # Retention: keep only the N most recent backup folders.
    try {
        Get-ChildItem $backupParent -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip $KeepCount |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    } catch {}
}

function Task-ExtractIcons {
    param($ZipUrl, $InstallPath, $TargetIconSet)
    if ([string]::IsNullOrWhiteSpace($ZipUrl) -or [string]::IsNullOrWhiteSpace($InstallPath) -or [string]::IsNullOrWhiteSpace($TargetIconSet)) {
        Log-Status "Task-ExtractIcons: missing required argument." "WARN"
        return
    }
    $localZip    = Join-Path $WorkDir 'icons.7z'
    $extractPath = Join-Path $WorkDir 'IconsTemp'
    if (-not (Download-File -Url $ZipUrl -Destination $localZip)) { return }
    $seven = Get-7Zip
    if (-not $seven) { Log-Status "Cannot extract icons without 7zr.exe." "ERROR"; return }
    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue }

    $proc = Start-Process -FilePath $seven -ArgumentList @('x', "`"$localZip`"", "-o`"$extractPath`"", '-y') -Wait -WindowStyle Hidden -PassThru
    if (-not $proc -or ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 1)) {
        $code = if ($proc) { $proc.ExitCode } else { 'n/a' }
        Log-Status "Icon archive extraction failed (7zr exit=$code). Skipping icon copy." "ERROR"
        return
    }

    $foundImages = Get-ChildItem -Path $extractPath -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'images' } | Select-Object -First 1
    if (-not $foundImages) {
        Log-Status "Icon archive did not contain an 'images' folder. Skipping icon copy." "WARN"
        return
    }
    $targetImages = Join-Path $InstallPath "themes\$TargetIconSet\org\jdownloader\images"
    if (-not (Test-Path $targetImages)) {
        try { New-Item -ItemType Directory -Path $targetImages -Force | Out-Null } catch { Log-Status "Could not create icon folder $targetImages." "WARN"; return }
    }
    try {
        Copy-Item "$($foundImages.FullName)\*" $targetImages -Recurse -Force -ErrorAction Stop
    } catch {
        Log-Status ("Failed to copy icon files into {0}: {1}" -f $targetImages, $_) "WARN"
    } finally {
        # Remove the unpacked 7z staging folder so TEMP doesn't accumulate gigabytes of icon sets.
        if (Test-Path $extractPath) {
            try { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
}

function Task-PatchLaf {
    param($JsonPath, $IconSetId, $WindowDecorations)
    if ([string]::IsNullOrWhiteSpace($JsonPath) -or -not (Test-Path $JsonPath)) {
        Log-Status "Task-PatchLaf: theme JSON not found at $JsonPath" "WARN"; return
    }
    try {
        $content = Get-Content -Path $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if (-not $content.PSObject.Properties["iconsetid"]) { $content | Add-Member -MemberType NoteProperty -Name "iconsetid" -Value $IconSetId }
        else { $content.iconsetid = $IconSetId }
        if (-not $content.PSObject.Properties["windowdecorationenabled"]) { $content | Add-Member -MemberType NoteProperty -Name "windowdecorationenabled" -Value $WindowDecorations }
        else { $content.windowdecorationenabled = $WindowDecorations }
        [void](Write-JsonAtomic -Path $JsonPath -Payload $content)
    } catch { Log-Status "Failed to patch LAF config: $_" "WARN" }
}

function Task-NukeBanners {
    param($InstallPath)
    Add-Type -AssemblyName System.Drawing
    $themeDir = "$InstallPath\themes"
    if (Test-Path $themeDir) {
        Get-ChildItem -Path $themeDir -Recurse -Filter "*.png" | Where-Object { $_.Directory.Name -eq "banner" } | ForEach-Object {
            $img = $null; $bmp = $null
            try {
                $img = [System.Drawing.Image]::FromFile($_.FullName)
                $w = $img.Width; $h = $img.Height
                $img.Dispose(); $img = $null
                $bmp = New-Object System.Drawing.Bitmap($w, $h)
                $bmp.Save($_.FullName, [System.Drawing.Imaging.ImageFormat]::Png)
            } catch { Log-Status "Failed to replace banner image $($_.Name): $_" "WARN" } finally {
                if ($img) { $img.Dispose() }
                if ($bmp) { $bmp.Dispose() }
            }
        }
    }
}

function Task-PatchExeIcon {
    param($InstallPath)
    if ([string]::IsNullOrWhiteSpace($InstallPath) -or -not (Test-Path $InstallPath)) {
        Log-Status "Cannot apply icon: install path missing." "WARN"; return
    }
    Log-Status "Applying dark icon..."
    $ResHackerZip = Join-Path $WorkDir 'resource_hacker.zip'
    $ResHackerDir = Join-Path $WorkDir 'ResourceHacker'
    $IconFile     = Join-Path $WorkDir 'jd_dark.ico'
    if (-not (Download-File -Url "https://www.angusj.com/resourcehacker/resource_hacker.zip" -Destination $ResHackerZip)) { return }
    if (-not (Download-File -Url "https://raw.githubusercontent.com/SysAdminDoc/JDownloaderDarkMode/refs/heads/main/Icons/icon.ico" -Destination $IconFile)) { return }
    if (-not (Test-Path $ResHackerDir)) {
        try { Expand-Archive -Path $ResHackerZip -DestinationPath $ResHackerDir -Force -ErrorAction Stop }
        catch { Log-Status "Failed to unpack Resource Hacker: $_" "ERROR"; return }
    }
    $ResHackerExe = Join-Path $ResHackerDir 'ResourceHacker.exe'
    if (-not (Test-Path $ResHackerExe)) { Log-Status "Resource Hacker executable not found after extract." "ERROR"; return }

    $targets = @(
        (Join-Path $InstallPath 'JDownloader2.exe')
        (Join-Path $InstallPath 'Uninstall JDownloader.exe')
    )
    foreach ($exe in $targets) {
        if (-not (Test-Path $exe)) { continue }
        $bak = "$exe.bak"
        try {
            Stop-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($exe)) -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1

            # Preserve the original exactly once, then always operate from the pristine backup.
            if (-not (Test-Path $bak)) {
                Move-Item -Path $exe -Destination $bak -Force -ErrorAction Stop
            } elseif (Test-Path $exe) {
                # Keep the currently-installed exe around in case the patch fails mid-flight.
                $currentSave = "$exe.prepatch"
                try { Move-Item -Path $exe -Destination $currentSave -Force -ErrorAction Stop } catch { Remove-Item $exe -Force -ErrorAction SilentlyContinue }
            }

            $rhArgs = @('-open', "`"$bak`"", '-save', "`"$exe`"", '-action', 'addoverwrite', '-res', "`"$IconFile`"", '-mask', 'ICONGROUP,MAINICON,0')
            $proc = Start-Process -FilePath $ResHackerExe -ArgumentList $rhArgs -Wait -WindowStyle Hidden -PassThru
            $patched = ($proc -and $proc.ExitCode -eq 0 -and (Test-Path $exe) -and ((Get-Item $exe).Length -gt 0))

            if (-not $patched) {
                Log-Status "Icon patch failed for $exe (exit=$($proc.ExitCode)). Rolling back." "WARN"
                try { if (Test-Path $exe) { Remove-Item $exe -Force -ErrorAction SilentlyContinue } } catch {}
                try {
                    if (Test-Path "$exe.prepatch") {
                        Move-Item -Path "$exe.prepatch" -Destination $exe -Force -ErrorAction SilentlyContinue
                    } elseif (Test-Path $bak) {
                        Copy-Item -Path $bak -Destination $exe -Force -ErrorAction SilentlyContinue
                    }
                } catch {}
            } else {
                try { if (Test-Path "$exe.prepatch") { Remove-Item "$exe.prepatch" -Force -ErrorAction SilentlyContinue } } catch {}
            }
        } catch {
            Log-Status ("Failed to patch {0}: {1}" -f $exe, $_) "WARN"
            # Final safety net: if we lost the exe completely, restore from .bak.
            if (-not (Test-Path $exe) -and (Test-Path $bak)) {
                try { Copy-Item -Path $bak -Destination $exe -Force -ErrorAction SilentlyContinue } catch {}
            }
        }
    }
    try { Start-Process "ie4uinit.exe" -ArgumentList "-show" -WindowStyle Hidden -ErrorAction SilentlyContinue } catch {}
}

function Write-JsonAtomic {
    # Atomic JSON write: serialize, write to .tmp, then move into place. Never leaves a
    # half-written config if we're interrupted mid-write.
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Payload,
        [int]$Depth = 100
    )
    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path $parent)) {
        try { New-Item -ItemType Directory -Path $parent -Force | Out-Null } catch {}
    }
    $tmp = "$Path.tmp"
    try {
        $json = $Payload | ConvertTo-Json -Depth $Depth
        Set-Content -Path $tmp -Value $json -Encoding UTF8 -ErrorAction Stop
        Move-Item -Path $tmp -Destination $Path -Force -ErrorAction Stop
        return $true
    } catch {
        try { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } catch {}
        Log-Status ("Failed to write {0}: {1}" -f $Path, $_) "WARN"
        return $false
    }
}

function Set-JsonConfig {
    # Merge caller-supplied keys INTO the existing config (when one exists) instead of
    # overwriting the whole file. This preserves unrelated user customizations that
    # JDownloader persists into the same JSON, and still writes a fresh file on first use.
    param($Path, $DataHash)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not $DataHash) { return }

    $merged = [ordered]@{}
    if (Test-Path $Path) {
        try {
            $existing = Get-Content -Path $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($existing -is [psobject]) {
                foreach ($prop in $existing.PSObject.Properties) {
                    $merged[$prop.Name] = $prop.Value
                }
            }
        } catch {
            # Existing file is unreadable; back it up and rewrite fresh so the app recovers.
            try {
                $bad = "$Path.bad-$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                Move-Item -Path $Path -Destination $bad -Force -ErrorAction SilentlyContinue
                Log-Status ("Config {0} was unreadable and was quarantined: {1}" -f (Split-Path $Path -Leaf), $bad) "WARN"
            } catch {}
        }
    }

    if ($DataHash -is [System.Collections.IDictionary]) {
        foreach ($k in $DataHash.Keys) { $merged[$k] = $DataHash[$k] }
    } elseif ($DataHash -is [psobject]) {
        foreach ($p in $DataHash.PSObject.Properties) { $merged[$p.Name] = $p.Value }
    }

    [void](Write-JsonAtomic -Path $Path -Payload $merged)
}

function Task-DeepHardening {
    param($cfgPath, $HardenState)
    Log-Status "Applying hardening passes..."

    # Always-on: remove contribute panels
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.settings.AdvancedConfig.json" -DataHash @{"org.jdownloader.gui.jdgui.settings.AboutConfigPanel.contributepanelvisible"=$false}
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.controlling.WidgetStateManager.json" -DataHash @{"contributepanelvisible"=$false}
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.gui.jdgui.views.jdgui.GUILayout.json" -DataHash @{"contributepanel_visible"=$false}
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.settings.advanced.AdvancedSettings.json" -DataHash @{"contributepanel_enabled"=$false}

    # Always-on: disable bubble notifications (noise)
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.gui.notify.gui.BubbleNotifyConfig.json" -DataHash ($Template_BubbleNotify | ConvertFrom-Json | ForEach-Object {
        $h = @{}; $_.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }; $h
    })

    # Privacy: disable local API remote access by default
    if ($HardenState -and $HardenState.DisableLocalAPI) {
        Set-JsonConfig -Path "$cfgPath\org.jdownloader.api.RemoteAPIConfig.json" -DataHash @{
            "deprecatedapienabled" = $false
            "deprecatedapilocalhostonly" = $true
            "externinterfaceenabled" = $true
            "externinterfacelocalhostonly" = $true
            "localapiserverheaderxframeoptions" = "DENY"
            "localapiserverheaderxxssprotection" = "1; mode=block"
        }
    }

    # Privacy: disable clipboard monitoring if requested
    if ($HardenState -and $HardenState.DisableClipboard) {
        Set-JsonConfig -Path (Join-Path $cfgPath 'org.jdownloader.settings.GraphicalUserInterfaceSettings.json') -DataHash @{ "clipboardmonitored" = $false }
    }

    # Silent mode config
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.settings.SilentModeSettings.json" -DataHash @{
        "manualenabled" = $false
        "autoresetonstartupenabled" = $true
        "autotrigger" = "NEVER"
        "oncaptchaduringsilentmodeaction" = "WAIT_IN_BACKGROUND_UNTIL_WINDOW_GETS_FOCUS_OR_TIMEOUT"
    }

    # JVM tuning: write vmoptions file if it does not already exist
    if ($HardenState -and $HardenState.WriteVmOptions) {
        $jdRoot = Split-Path $cfgPath -Parent
        $vmFile = "$jdRoot\JDownloader2.vmoptions"
        if (-not (Test-Path $vmFile)) {
            try {
                $vmContent = @(
                    "-XX:-UsePerfData"
                    "-Djava.net.preferIPv4Stack=true"
                ) -join "`r`n"
                Set-Content -Path $vmFile -Value $vmContent -Encoding UTF8
                Log-Status "JVM options file written for performance tuning." "SUCCESS"
            } catch { Log-Status "Failed to write JDownloader2.vmoptions: $_" "WARN" }
        } else {
            Log-Status "JDownloader2.vmoptions already exists, skipping." "INFO"
        }
    }
}

function Task-Install {
    param($Source)
    if ($Source -eq "GitHub") {
        $seven = Get-7Zip
        if (-not $seven) { Log-Status "Cannot extract installer without 7zr.exe." "ERROR"; return $false }

        # Wipe any stale installer parts / extract folder from a previous (possibly failed) run.
        try {
            Get-ChildItem -Path $WorkDir -Filter 'installer.7z.*' -File -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
        } catch {}
        $installerExtract = Join-Path $WorkDir 'Installer'
        if (Test-Path $installerExtract) {
            try { Remove-Item $installerExtract -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        }

        # Prefer the locally-bundled installer (70 MB of .7z parts shipped alongside the script)
        # when present. This makes the clean-install flow work fully offline and avoids the
        # network hop for users who cloned/downloaded the repo whole.
        $usedLocal = $false
        if ($PSScriptRoot) {
            $localInstallerDir = Join-Path $PSScriptRoot 'Installer'
            if (Test-Path $localInstallerDir) {
                $localParts = 1..7 | ForEach-Object { Join-Path $localInstallerDir ("installer.7z.{0:D3}" -f $_) }
                $allLocalPresent = $true
                foreach ($lp in $localParts) { if (-not (Test-Path $lp)) { $allLocalPresent = $false; break } }
                if ($allLocalPresent) {
                    Log-Status "Using bundled installer from the script folder." "INFO"
                    foreach ($lp in $localParts) {
                        $target = Join-Path $WorkDir (Split-Path $lp -Leaf)
                        try { Copy-Item -Path $lp -Destination $target -Force -ErrorAction Stop } catch {
                            Log-Status ("Failed to stage bundled installer part: {0}" -f $_) "WARN"
                            $allLocalPresent = $false
                            break
                        }
                    }
                    if ($allLocalPresent) { $usedLocal = $true }
                }
            }
        }

        if (-not $usedLocal) {
            $baseUrl = "https://github.com/SysAdminDoc/JDownloaderDarkMode/raw/main/Installer/installer.7z"
            for ($i = 1; $i -le 7; $i++) {
                $part = ".{0:D3}" -f $i
                $destPart = Join-Path $WorkDir "installer.7z$part"
                if (-not (Download-File -Url "$baseUrl$part" -Destination $destPart)) {
                    Log-Status "Installer download failed on part $part." "ERROR"
                    return $false
                }
            }
        }

        # Verify all 7 parts landed on disk before asking 7-Zip to extract.
        $missing = 1..7 | Where-Object { -not (Test-Path (Join-Path $WorkDir ("installer.7z.{0:D3}" -f $_))) }
        if ($missing) {
            Log-Status ("Installer is missing part(s): {0}" -f ($missing -join ', ')) "ERROR"
            return $false
        }

        $firstPart = Join-Path $WorkDir 'installer.7z.001'
        $proc = Start-Process -FilePath $seven -ArgumentList @('x', "`"$firstPart`"", "-o`"$installerExtract`"", '-y') -Wait -WindowStyle Hidden -PassThru
        if (-not $proc -or ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 1)) {
            $code = if ($proc) { $proc.ExitCode } else { 'n/a' }
            Log-Status "Installer extraction failed (7zr exit=$code)." "ERROR"
            return $false
        }

        $setup = Get-ChildItem $installerExtract -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue |
            Sort-Object Length -Descending | Select-Object -First 1
        if (-not $setup) {
            Log-Status "Installer extraction completed, but no setup executable was found." "ERROR"
            return $false
        }

        $setupProc = Start-Process -FilePath $setup.FullName -ArgumentList "-q" -Wait -PassThru
        # Post-condition: detect a resulting install. Don't trust installer exit codes alone.
        $detected = Detect-JDPath
        if (-not $detected) {
            $exit = if ($setupProc) { $setupProc.ExitCode } else { 'n/a' }
            Log-Status "Setup finished (exit=$exit) but no JDownloader installation was detected afterwards." "WARN"
            return $false
        }
        return $true
    } elseif ($Source -eq "Mega") {
        Start-Process "https://mega.nz/file/PQ0XRIrA#-uuhLXSc_nPfotXWfBWDZRx90Gnehx2_Mx_JVufzfdM"
        [System.Windows.Forms.MessageBox]::Show("Download the file from Mega, then click OK.", "Manual Download") | Out-Null

        # Accept the user's Downloads folder as configured in the Shell; fall back to USERPROFILE\Downloads.
        $dl = try { [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile) } catch { $env:USERPROFILE }
        $downloadsFolder = Join-Path $dl 'Downloads'
        if (-not (Test-Path $downloadsFolder)) {
            Log-Status "Downloads folder not found - cannot auto-pick the Mega installer." "ERROR"
            return $false
        }
        # Only consider files created in the last hour to avoid launching an old/unrelated installer.
        $cutoff = (Get-Date).AddHours(-1)
        $f = Get-ChildItem $downloadsFolder -Filter "JDownloader*Setup*.exe" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $cutoff } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $f) {
            Log-Status "Mega installer was not found in Downloads after the manual step." "ERROR"
            return $false
        }
        Start-Process $f.FullName -ArgumentList "-q" -Wait
        if (-not (Detect-JDPath)) {
            Log-Status "Mega setup finished but JDownloader was not detected afterwards." "WARN"
            return $false
        }
        return $true
    }
    return $false
}

function Test-IsSafeInstallRoot {
    # Reject paths that are clearly not a JDownloader install folder before recursive deletion.
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try { $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path } catch { return $false }
    if ([string]::IsNullOrWhiteSpace($resolved)) { return $false }
    # Refuse drive roots, Windows system paths, and user-profile roots.
    $forbidden = @(
        $env:SystemRoot
        $env:ProgramFiles
        ${env:ProgramFiles(x86)}
        $env:USERPROFILE
        $env:LOCALAPPDATA
        $env:APPDATA
        $env:ProgramData
    ) | Where-Object { $_ }
    foreach ($f in $forbidden) {
        if ($resolved.TrimEnd('\').Equals($f.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    if ($resolved -match '^[A-Za-z]:\\?$') { return $false }          # drive root like C:\
    if ($resolved.Length -lt 6) { return $false }                     # too short to be safe
    # Require a file that identifies this as a JDownloader install (or an uninstaller stub).
    $jdMarker = Join-Path $resolved 'JDownloader2.exe'
    $uninstallMarker = Join-Path $resolved 'Uninstall JDownloader.exe'
    return ((Test-Path $jdMarker) -or (Test-Path $uninstallMarker))
}

function Task-FullUninstall {
    param($InstallPath)
    if (-not (Test-IsSafeInstallRoot -Path $InstallPath)) {
        Log-Status "Refused to uninstall: '$InstallPath' does not look like a JDownloader folder." "ERROR"
        return
    }
    Kill-JDownloader
    $uninstaller = Join-Path $InstallPath 'Uninstall JDownloader.exe'
    if (Test-Path $uninstaller) {
        try { Start-Process -FilePath $uninstaller -ArgumentList "-q" -Wait -ErrorAction Stop } catch { Log-Status "Uninstaller exited abnormally: $_" "WARN" }
    }
    Start-Sleep 2
    try {
        Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction Stop
    } catch {
        Log-Status "Some files could not be removed (locked or in use). Residual folder may remain: $_" "WARN"
    }
}

function Trigger-Update {
    param($InstallPath)
    $exe = Join-Path $InstallPath 'JDownloader2.exe'
    if (-not (Test-Path $exe)) {
        Log-Status "Skipping post-run update: JDownloader2.exe not found." "WARN"
        return
    }
    try {
        Start-Process -FilePath $exe -ArgumentList '-update' -ErrorAction Stop
        Log-Status "JDownloader update launched." "INFO"
    } catch {
        Log-Status ("Failed to launch JDownloader update: {0}" -f $_) "WARN"
    }
}

function Run-Audit {
    param($InstallPath)
    if ([string]::IsNullOrWhiteSpace($InstallPath) -or -not (Test-Path $InstallPath)) {
        Log-Status "Audit aborted: install path is invalid." "ERROR"
        return
    }

    $issues = 0
    $warnings = @()
    $notes = @()

    if (-not (Test-Path (Join-Path $InstallPath 'JDownloader2.exe'))) { $issues++; $warnings += "JDownloader2.exe missing" }
    if (-not (Test-Path (Join-Path $InstallPath 'JDownloader.jar'))) { $issues++; $warnings += "JDownloader.jar missing (core engine)" }

    # Bundled JRE is preferred; otherwise surface a note about system Java.
    $bundledJava = Join-Path $InstallPath 'jre\bin\java.exe'
    $bundledJavaw = Join-Path $InstallPath 'jre\bin\javaw.exe'
    if ((Test-Path $bundledJava) -or (Test-Path $bundledJavaw)) {
        $notes += "Bundled JRE detected."
    } else {
        $hasSystemJava = $false
        try {
            $cmd = Get-Command -Name 'javaw' -ErrorAction SilentlyContinue
            if ($cmd) { $hasSystemJava = $true }
            if (-not $hasSystemJava -and $env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\javaw.exe'))) {
                $hasSystemJava = $true
            }
        } catch {}
        if (-not $hasSystemJava) {
            $warnings += "No bundled JRE and no system Java found (JDownloader may fail to launch)."
        } else {
            $notes += "Using system Java."
        }
    }

    $cfgPath = Join-Path $InstallPath 'cfg'
    if (-not (Test-Path $cfgPath)) { $issues++; $warnings += "cfg/ directory missing entirely" }
    else {
        $criticalConfigs = @(
            "org.jdownloader.settings.GeneralSettings.json"
            "org.jdownloader.settings.GraphicalUserInterfaceSettings.json"
            "org.jdownloader.gui.jdtrayicon.TrayExtension.json"
        )
        foreach ($cfg in $criticalConfigs) {
            $cfgFile = Join-Path $cfgPath $cfg
            if (-not (Test-Path $cfgFile)) { $issues++; $warnings += "Missing: $cfg" }
            else {
                try { $null = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop } catch { $issues++; $warnings += "Corrupt JSON: $cfg" }
            }
        }

        $tmpFiles = Get-ChildItem $cfgPath -Filter "*.tmp" -ErrorAction SilentlyContinue
        if ($tmpFiles -and $tmpFiles.Count -gt 0) { $warnings += "$($tmpFiles.Count) stale .tmp files in cfg/" }

        $lafPath = Join-Path $cfgPath 'laf'
        if (Test-Path $lafPath) {
            $lafFiles = Get-ChildItem $lafPath -Filter "*.json" -ErrorAction SilentlyContinue
            if (-not $lafFiles -or $lafFiles.Count -eq 0) { $warnings += "laf/ directory exists but contains no theme files" }
        }
    }

    # Disk free-space sanity check: JDownloader defaults to requiring 512 MiB free.
    try {
        $drive = Split-Path $InstallPath -Qualifier
        if ($drive) {
            $psDrive = Get-PSDrive -Name $drive.TrimEnd(':') -ErrorAction SilentlyContinue
            if ($psDrive -and $psDrive.Free -lt 1GB) {
                $warnings += ("Low free space on {0} ({1:N1} MB) - JDownloader may pause downloads." -f $drive, ($psDrive.Free / 1MB))
            }
        }
    } catch {}

    # Update artifact
    $revFile = Join-Path $InstallPath 'update\versioninfo\JD\rev'
    if (Test-Path $revFile) {
        $rev = try { (Get-Content $revFile -ErrorAction SilentlyContinue).Trim() } catch { $null }
        if ($rev) { $notes += "Core revision: $rev" }
    }

    # Report - include notes even on success so the log is informative.
    $summarySuffix = if ($notes.Count -gt 0) { " Notes: $($notes -join '; ')" } else { '' }
    if ($issues -gt 0) {
        Log-Status ("Audit found {0} issue(s): {1}.{2}" -f $issues, ($warnings -join '; '), $summarySuffix) "WARN"
    } elseif ($warnings.Count -gt 0) {
        Log-Status ("Audit passed with notes: {0}.{1}" -f ($warnings -join '; '), $summarySuffix) "INFO"
    } else {
        Log-Status ("Audit passed. All critical files and configs are intact.{0}" -f $summarySuffix) "SUCCESS"
    }
}

function Execute-Operations {
    param($GUI_State)
    $JDPath = $GUI_State.InstallPath
    if ($GUI_State.Mode -eq "Modify") {
        if ([string]::IsNullOrWhiteSpace($JDPath)) {
            Log-Status "Select an existing JDownloader folder before running modify mode." "ERROR"
            return $false
        }
        # Refuse to act on a path that doesn't actually look like a JDownloader install.
        # Without this, a typo could cause us to drop cfg/ into an arbitrary folder.
        if (-not (Test-Path (Join-Path $JDPath 'JDownloader2.exe'))) {
            Log-Status "Modify mode refused: '$JDPath' does not contain JDownloader2.exe." "ERROR"
            return $false
        }
    }

    # Pre-flight: validate the download-folder selection so we fail before touching any config.
    if (-not [string]::IsNullOrWhiteSpace($GUI_State.DlFolder)) {
        $dl = [string]$GUI_State.DlFolder
        $dlParent = Split-Path $dl -Parent
        if (-not (Test-Path $dl) -and (-not [string]::IsNullOrWhiteSpace($dlParent)) -and (-not (Test-Path $dlParent))) {
            Log-Status "Download folder parent does not exist: $dlParent" "ERROR"
            return $false
        }
    }

    # Catch-all error trap
    try {
        if ($GUI_State.Mode -ne "Modify") {
            $selectedSource = if ($GUI_State.InstallSource) { $GUI_State.InstallSource } else { "GitHub" }
            $installSucceeded = Task-Install -Source $selectedSource

            if (-not $installSucceeded -and $selectedSource -eq "GitHub" -and -not $script:SilentMode) {
                $fallback = [System.Windows.Forms.MessageBox]::Show(
                    "GitHub install did not complete successfully. Do you want to try the manual Mega flow instead?",
                    "Try alternate install source",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question
                )
                if ($fallback -eq [System.Windows.Forms.DialogResult]::Yes) {
                    $installSucceeded = Task-Install -Source "Mega"
                }
            }

            if (-not $installSucceeded) {
                Log-Status "Install step did not complete." "ERROR"
                return $false
            }

            $JDPath = Detect-JDPath
            if (-not $JDPath) {
                Log-Status "Install completed, but JDownloader could not be detected automatically." "WARN"
                return $false
            }
        }

        $cfgPath = "$JDPath\cfg"
        if (-not (Test-Path $cfgPath)) { New-Item -ItemType Directory -Path $cfgPath -Force | Out-Null }
        
        $ProgressBar.Value = 15
        $ProgressBar.Style = "Marquee"
        $ProgressBar.MarqueeAnimationSpeed = 28
        Kill-JDownloader; Backup-JD -InstallPath $JDPath
        
        # [Fix] Use .Contains instead of .ContainsKey for OrderedDictionary
        if ($ThemeDefinitions.Contains($GUI_State.ThemeName)) {
            $Theme = $ThemeDefinitions[$GUI_State.ThemeName]
            $lafPath = "$cfgPath\laf"; if (-not (Test-Path $lafPath)) { New-Item -ItemType Directory -Path $lafPath -Force | Out-Null }
            
            Download-File -Url $Theme.JsonUrl -Destination "$lafPath\$($Theme.JsonName)" | Out-Null
            
            if ($IconDefinitions.Contains($GUI_State.IconPack)) {
                $IconDef = $IconDefinitions[$GUI_State.IconPack]
                Task-PatchLaf -JsonPath "$lafPath\$($Theme.JsonName)" -IconSetId $IconDef.ID -WindowDecorations $GUI_State.WindowDec
                Task-ExtractIcons -ZipUrl $IconDef.Url -InstallPath $JDPath -TargetIconSet $IconDef.ID
            }
            
            try {
                $guiObj = $Template_GUI | ConvertFrom-Json
                $guiObj.lookandfeeltheme = $Theme.LafID
                if ($GUI_State.Contains("ClipboardMonitor")) { $guiObj.clipboardmonitored = [bool]$GUI_State.ClipboardMonitor }
                [void](Write-JsonAtomic -Path (Join-Path $cfgPath 'org.jdownloader.settings.GraphicalUserInterfaceSettings.json') -Payload $guiObj)
            } catch { Log-Status "Failed to write GUI settings: $_" "WARN" }
        }

        try {
            $genObj = $Template_General | ConvertFrom-Json
            $genObj.maxsimultanedownloads = [int]$GUI_State.MaxSim
            if ([string]::IsNullOrWhiteSpace($GUI_State.DlFolder)) {
                $null = $genObj.PSObject.Properties.Remove("defaultdownloadfolder")
            } else {
                $genObj.defaultdownloadfolder = $GUI_State.DlFolder
            }
            $genObj.pausespeed = [int]$GUI_State.PauseSpeed
            if ($GUI_State.Contains("MaxChunks")) { $genObj.maxchunksperfile = [int]$GUI_State.MaxChunks }
            if ($GUI_State.Contains("MaxPerHost")) { $genObj.maxsimultanedownloadsperhost = [int]$GUI_State.MaxPerHost }
            if ($GUI_State.Contains("MaxPerHostEnabled")) { $genObj.maxdownloadsperhostenabled = [bool]$GUI_State.MaxPerHostEnabled }
            if ($GUI_State.Contains("FileExistsAction")) { $genObj.iffileexistsaction = [string]$GUI_State.FileExistsAction }
            if ($GUI_State.Contains("SpeedLimitEnabled")) {
                $genObj.downloadspeedlimitenabled = [bool]$GUI_State.SpeedLimitEnabled
                if ($GUI_State.Contains("SpeedLimit")) { $genObj.downloadspeedlimit = [int]$GUI_State.SpeedLimit }
            }
            if ($GUI_State.Contains("HashCheck")) { $genObj.hashcheckenabled = [bool]$GUI_State.HashCheck }
            if ($GUI_State.Contains("PreserveFileDate")) { $genObj.useoriginallastmodified = [bool]$GUI_State.PreserveFileDate }
            [void](Write-JsonAtomic -Path (Join-Path $cfgPath 'org.jdownloader.settings.GeneralSettings.json') -Payload $genObj)
        } catch { Log-Status "Failed to write general settings: $_" "WARN" }

        try {
            $trayObj = $Template_Tray | ConvertFrom-Json
            $trayObj.startminimizedenabled = $GUI_State.StartMin
            $trayObj.onminimizeaction = if ($GUI_State.MinToTray) { "TO_TASKBAR_IF_ALLOWED" } else { "TO_TASKBAR" }
            if ($GUI_State.Contains("CloseToTray")) { $trayObj.oncloseaction = if ($GUI_State.CloseToTray) { "TO_TASKBAR" } else { "ASK" } }
            [void](Write-JsonAtomic -Path (Join-Path $cfgPath 'org.jdownloader.gui.jdtrayicon.TrayExtension.json') -Payload $trayObj)
        } catch { Log-Status "Failed to write tray settings: $_" "WARN" }

        # Write update settings
        try {
            $updateObj = $Template_Update | ConvertFrom-Json
            [void](Write-JsonAtomic -Path (Join-Path $cfgPath 'org.jdownloader.updatev2.UpdateSettings.json') -Payload $updateObj)
        } catch { Log-Status "Failed to write update settings: $_" "WARN" }

        $hardenState = @{
            DisableLocalAPI  = if ($GUI_State.Contains("DisableLocalAPI")) { [bool]$GUI_State.DisableLocalAPI } else { $true }
            DisableClipboard = if ($GUI_State.Contains("ClipboardMonitor")) { -not [bool]$GUI_State.ClipboardMonitor } else { $false }
            WriteVmOptions   = if ($GUI_State.Contains("WriteVmOptions")) { [bool]$GUI_State.WriteVmOptions } else { $false }
        }
        Task-DeepHardening -cfgPath $cfgPath -HardenState $hardenState
        if ($GUI_State.ForceMinimal) { Set-JsonConfig -Path (Join-Path $cfgPath 'org.jdownloader.gui.jdgui.settings.MainTabLayout.json') -DataHash @{compactmodetabs=$true; hidemyjdtab=$true} }
        Task-NukeBanners -InstallPath $JDPath
        if ($GUI_State.PatchExe) { Task-PatchExeIcon -InstallPath $JDPath }

        # Defensive cleanup: remove any lingering *.tmp siblings we (or a previous crashed run) may
        # have left in cfg/. Write-JsonAtomic removes its own tmp on success, but a crash between
        # write and move-item could leave one behind.
        try {
            Get-ChildItem -Path $cfgPath -Filter '*.json.tmp' -File -Recurse -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
        } catch {}

        $ProgressBar.Style = "Continuous"; $ProgressBar.MarqueeAnimationSpeed = 0; $ProgressBar.Value = 100
        Log-Status "Operations completed." "SUCCESS"
        if ($GUI_State.AutoUpdate) { Trigger-Update -InstallPath $JDPath }
        Save-Settings -SettingsObj $GUI_State
        return $true
    } catch {
        $ProgressBar.Style = "Continuous"; $ProgressBar.MarqueeAnimationSpeed = 0; $ProgressBar.Value = 0
        Log-Status "CRITICAL ERROR: $_" "FATAL"
        Log-Status "Stack trace: $($_.ScriptStackTrace)" "DEBUG"
        if (-not $script:SilentMode) {
            [System.Windows.Forms.MessageBox]::Show("An error occurred during execution. Check the log file for details.`n`nError: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
        return $false
    }
}

# ==========================================
# 8. GUI CONSTRUCTION (Premium Workspace)
# ==========================================

function New-Panel {
    param($Name, $Parent, $Dock, $Size, $Location, $BackColor, $Tag, $Padding, $Anchor)
    $p = New-Object System.Windows.Forms.Panel
    if ($Name) { $p.Name = $Name }
    if ($Dock) { $p.Dock = $Dock }
    if ($Size) { $p.Size = $Size }
    if ($Location) { $p.Location = $Location }
    if ($BackColor) { $p.BackColor = $BackColor }
    if ($Tag) { $p.Tag = $Tag }
    if ($Padding) { $p.Padding = $Padding }
    if ($Anchor) { $p.Anchor = $Anchor }
    if ($Parent) { [void]$Parent.Controls.Add($p) }
    Enable-DoubleBuffer $p
    return $p
}

function New-Surface {
    param($Name, $Parent, $Location, $Size, $Tag = "Surface")
    $surface = New-Panel -Name $Name -Parent $Parent -Location $Location -Size $Size -Tag $Tag
    $surface.Padding = New-Object System.Windows.Forms.Padding(24)
    return $surface
}

function New-Button {
    param($Name, $Parent, $Text, $LangKey, $Location, $Size, $Tag, $Click, $Anchor)
    $b = New-Object System.Windows.Forms.Button
    if ($Name) { $b.Name = $Name }
    if ($Location) { $b.Location = $Location }
    if ($Size) { $b.Size = $Size }
    if ($Tag) { $b.Tag = $Tag }
    if ($Anchor) { $b.Anchor = $Anchor }
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 0
    $b.AutoSize = $false
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

    if ($LangKey) {
        Register-LangControl -Control $b -Key $LangKey
    } elseif ($Text) {
        $b.Text = $Text
    }

    if ($Tag -eq "SidebarBtn") {
        $b.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
        $b.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $b.Padding = New-Object System.Windows.Forms.Padding(18, 0, 0, 0)
    } elseif ($Tag -match "Primary|Danger|Success") {
        $b.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    } else {
        $b.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    }

    if ($Click) { $b.Add_Click($Click) }
    if ($Parent) { [void]$Parent.Controls.Add($b) }
    return $b
}

function New-Label {
    param($Name, $Parent, $Text, $LangKey, $Location, $Font, $AutoSize = $true, $Tag, $Size, $Anchor)
    $l = New-Object System.Windows.Forms.Label
    if ($Name) { $l.Name = $Name }
    if ($Location) { $l.Location = $Location }
    $l.AutoSize = $AutoSize
    if ($Size) { $l.Size = $Size }
    if ($Tag) { $l.Tag = $Tag }
    if ($Anchor) { $l.Anchor = $Anchor }

    if ($Font) { $l.Font = $Font }
    elseif ($Tag -eq "SectionHeader") { $l.Font = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold) }
    elseif ($Tag -eq "SubHeader") { $l.Font = New-Object System.Drawing.Font("Segoe UI", 12) }
    elseif ($Tag -eq "BodyMuted") { $l.Font = New-Object System.Drawing.Font("Segoe UI", 10) }
    else { $l.Font = New-Object System.Drawing.Font("Segoe UI", 11) }

    if ($LangKey) {
        Register-LangControl -Control $l -Key $LangKey
    } elseif ($Text) {
        $l.Text = $Text
    }

    if ($Parent) { [void]$Parent.Controls.Add($l) }
    return $l
}

function New-Badge {
    param($Name, $Parent, $Text, $Location, $Size, $Tag = "BadgeNeutral", $Anchor)
    $badge = New-Object System.Windows.Forms.Label
    if ($Name) { $badge.Name = $Name }
    if ($Location) { $badge.Location = $Location }
    if ($Size) { $badge.Size = $Size } else { $badge.Size = New-Object System.Drawing.Size(132, 28) }
    if ($Tag) { $badge.Tag = $Tag }
    if ($Anchor) { $badge.Anchor = $Anchor }
    $badge.AutoSize = $false
    $badge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $badge.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    if ($Text) { $badge.Text = $Text }
    if ($Parent) { [void]$Parent.Controls.Add($badge) }
    return $badge
}

function Set-BadgeState {
    param(
        $Badge,
        [string]$Text,
        [ValidateSet("Neutral", "Accent", "Success", "Warning", "Danger")]
        [string]$State = "Neutral"
    )
    if (-not $Badge) { return }
    if ($Text) { $Badge.Text = $Text }
    $Badge.Tag = "Badge{0}" -f $State
    try { Apply-GuiTheme -ThemeName $script:CurrentGuiTheme -Root $Badge } catch {}
}

function New-TextBox {
    param($Name, $Parent, $Location, $Size, $Text, $Tag, $ReadOnly = $false, $Anchor)
    $t = New-Object System.Windows.Forms.TextBox
    if ($Name) { $t.Name = $Name }
    if ($Location) { $t.Location = $Location }
    if ($Size) { $t.Size = $Size }
    if ($Text) { $t.Text = $Text }
    if ($Tag) { $t.Tag = $Tag }
    if ($Anchor) { $t.Anchor = $Anchor }
    $t.ReadOnly = $ReadOnly
    $t.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $t.BorderStyle = "FixedSingle"
    if ($Parent) { [void]$Parent.Controls.Add($t) }
    return $t
}

function New-ComboBox {
    param($Name, $Parent, $Location, $Size, $Tag, $Items, $SelectedIndex = -1, $Anchor)
    $c = New-Object System.Windows.Forms.ComboBox
    if ($Name) { $c.Name = $Name }
    if ($Location) { $c.Location = $Location }
    if ($Size) { $c.Size = $Size }
    if ($Tag) { $c.Tag = $Tag }
    if ($Anchor) { $c.Anchor = $Anchor }
    $c.DropDownStyle = "DropDownList"
    $c.FlatStyle = "Flat"
    $c.IntegralHeight = $false
    $c.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    if ($Items) { foreach ($item in $Items) { [void]$c.Items.Add($item) } }
    if ($SelectedIndex -ge 0 -and $c.Items.Count -gt $SelectedIndex) { $c.SelectedIndex = $SelectedIndex }
    if ($Parent) { [void]$Parent.Controls.Add($c) }
    return $c
}

function New-CheckBox {
    param($Name, $Parent, $Text, $LangKey, $Location, $Tag, $Checked = $false, $Anchor)
    $c = New-Object System.Windows.Forms.CheckBox
    if ($Name) { $c.Name = $Name }
    if ($Location) { $c.Location = $Location }
    if ($Tag) { $c.Tag = $Tag }
    if ($Anchor) { $c.Anchor = $Anchor }
    $c.AutoSize = $true
    $c.Checked = $Checked
    $c.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    if ($LangKey) {
        Register-LangControl -Control $c -Key $LangKey
    } elseif ($Text) {
        $c.Text = $Text
    }
    if ($Parent) { [void]$Parent.Controls.Add($c) }
    return $c
}

function New-NumericUpDown {
    param($Name, $Parent, $Location, $Tag, $Min, $Max, $Value, $Anchor)
    $n = New-Object System.Windows.Forms.NumericUpDown
    if ($Name) { $n.Name = $Name }
    if ($Location) { $n.Location = $Location }
    if ($Tag) { $n.Tag = $Tag }
    if ($Anchor) { $n.Anchor = $Anchor }
    $n.Minimum = $Min
    $n.Maximum = $Max
    $n.Value = $Value
    $n.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $n.BorderStyle = "FixedSingle"
    $n.Size = New-Object System.Drawing.Size(160, 36)
    if ($Parent) { [void]$Parent.Controls.Add($n) }
    return $n
}

$script:PageRegistry = New-Object System.Collections.Generic.List[object]

function New-PagePanel {
    param([int]$CanvasHeight = 900)
    $p = New-Panel -Dock "Fill" -Tag "Page"
    $p.Visible = $false
    $p.AutoScroll = $true
    $canvas = New-Panel -Name "Canvas" -Parent $p -Location (New-Object System.Drawing.Point(24, 18)) -Size (New-Object System.Drawing.Size(1040, $CanvasHeight)) -Tag "Canvas"
    $p.AutoScrollMinSize = New-Object System.Drawing.Size(1064, [Math]::Max(0, $CanvasHeight + 36))
    [void]$script:PageRegistry.Add($p)
    return $p
}

function Get-PageCanvas {
    param($Page)
    return $Page.Controls | Where-Object { $_.Name -eq "Canvas" } | Select-Object -First 1
}

function Center-PageCanvas {
    param($Page)
    $canvas = Get-PageCanvas $Page
    if ($canvas) {
        try { $Page.AutoScrollPosition = New-Object System.Drawing.Point(0, 0) } catch {}
        $extraWidth = $Page.ClientSize.Width - $canvas.Width
        if ($extraWidth -gt 220) {
            $canvas.Left = 72
        } else {
            $canvas.Left = [Math]::Max(24, [int]($extraWidth / 2))
        }
        $canvas.Top = 18
    }
}

function Sync-PageCanvases {
    Layout-Dashboard
    foreach ($page in $script:PageRegistry) {
        if ($page -and -not $page.IsDisposed) { Center-PageCanvas $page }
    }
}

function New-ActionTile {
    param($Parent, $Location, $Title, $Description, $ButtonText, $ButtonTag, $Action, $BadgeText, $BadgeState = "Neutral")
    $tile = New-Surface -Parent $Parent -Location $Location -Size (New-Object System.Drawing.Size(332, 164))
    $titleSize = if ($BadgeText) { New-Object System.Drawing.Size(184, 24) } else { $null }
    [void](New-Label -Parent $tile -Text $Title -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)) -AutoSize ($null -eq $titleSize) -Size $titleSize)
    if ($BadgeText) {
        $badge = New-Badge -Parent $tile -Text $BadgeText -Location (New-Object System.Drawing.Point(208, 20)) -Size (New-Object System.Drawing.Size(100, 28))
        Set-BadgeState -Badge $badge -Text $BadgeText -State $BadgeState
    }
    [void](New-Label -Parent $tile -Text $Description -Location (New-Object System.Drawing.Point(24, 56)) -Size (New-Object System.Drawing.Size(284, 48)) -AutoSize $false -Tag "BodyMuted")
    $btn = New-Button -Parent $tile -Text $ButtonText -Location (New-Object System.Drawing.Point(24, 110)) -Size (New-Object System.Drawing.Size(184, 34)) -Tag $ButtonTag -Click $Action
    return @{ Panel = $tile; Button = $btn }
}

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$FormW = [Math]::Min(1440, [Math]::Max(1320, [int]($screen.Width * 0.88)))
$FormH = [Math]::Min(940, [Math]::Max(840, [int]($screen.Height * 0.88)))

$Form = New-Object System.Windows.Forms.Form
$brandingIconPath = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'icon.ico' } else { $null }
if ($brandingIconPath -and (Test-Path $brandingIconPath)) {
    # Stream-based load so the .ico file handle is released immediately.
    try {
        $iconBytes = [System.IO.File]::ReadAllBytes($brandingIconPath)
        $iconMs = New-Object System.IO.MemoryStream(,$iconBytes)
        try { $Form.Icon = New-Object System.Drawing.Icon($iconMs) } finally { $iconMs.Dispose() }
    } catch {}
}
$Form.Text = Get-LangValue -Key "Title" -Fallback $script:AppTitle
$Form.Size = New-Object System.Drawing.Size($FormW, $FormH)
$Form.MinimumSize = New-Object System.Drawing.Size(1320, 840)
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "Sizable"
$Form.BackColor = [System.Drawing.Color]::FromArgb(13, 18, 28)
$Form.ForeColor = [System.Drawing.Color]::White
$Form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$Form.AutoScaleMode = "Dpi"
Enable-DoubleBuffer $Form

$Sidebar = New-Panel -Name "Sidebar" -Parent $Form -Dock "Left" -Size (New-Object System.Drawing.Size(252, $FormH)) -Tag "Sidebar"
$Footer = New-Panel -Name "Footer" -Parent $Form -Dock "Bottom" -Size (New-Object System.Drawing.Size($FormW, 88)) -Tag "Footer"
$MainPanel = New-Panel -Name "MainPanel" -Parent $Form -Dock "Fill" -Tag "MainPanel"

$SidebarBrand = New-Surface -Parent $Sidebar -Location (New-Object System.Drawing.Point(16, 18)) -Size (New-Object System.Drawing.Size(220, 148)) -Tag "SidebarAlt"
$LogoBox = New-Object System.Windows.Forms.PictureBox
$LogoBox.Location = New-Object System.Drawing.Point(24, 24)
$LogoBox.Size = New-Object System.Drawing.Size(42, 42)
$LogoBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$brandPngPath = if ($PSScriptRoot) { Join-Path $PSScriptRoot "icon.png" } else { $null }
if ($brandPngPath -and (Test-Path $brandPngPath)) {
    # Load via byte array + MemoryStream clone so the file handle is released immediately.
    # FromFile() holds the handle open for the life of the Image, which blocks icon updates
    # from any external tooling while the app is running.
    try {
        $bytes = [System.IO.File]::ReadAllBytes($brandPngPath)
        $ms = New-Object System.IO.MemoryStream(,$bytes)
        try {
            $src = [System.Drawing.Image]::FromStream($ms)
            try { $LogoBox.Image = New-Object System.Drawing.Bitmap($src) } finally { $src.Dispose() }
        } finally { $ms.Dispose() }
    } catch {}
}
[void]$SidebarBrand.Controls.Add($LogoBox)
[void](New-Label -Parent $SidebarBrand -Text "Workspace manager" -Location (New-Object System.Drawing.Point(78, 26)) -Font (New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)) -Size (New-Object System.Drawing.Size(118, 16)) -AutoSize $false -Tag "BodyMuted")
[void](New-Label -Parent $SidebarBrand -Text "JDownloader 2" -Location (New-Object System.Drawing.Point(24, 74)) -Font (New-Object System.Drawing.Font("Segoe UI", 13.5, [System.Drawing.FontStyle]::Bold)) -Size (New-Object System.Drawing.Size(172, 24)) -AutoSize $false)
[void](New-Label -Parent $SidebarBrand -Text "Ultimate Manager" -Location (New-Object System.Drawing.Point(24, 98)) -Font (New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Regular)) -Size (New-Object System.Drawing.Size(172, 20)) -AutoSize $false -Tag "MutedStrong")
[void](New-Label -Parent $SidebarBrand -Text "Install, refine, harden, and repair in one calm workspace." -Location (New-Object System.Drawing.Point(24, 120)) -Size (New-Object System.Drawing.Size(172, 38)) -AutoSize $false -Tag "BodyMuted")

$SidebarFooter = New-Panel -Parent $Sidebar -Dock "Bottom" -Size (New-Object System.Drawing.Size(252, 164)) -Tag "Sidebar"
$SidebarNote = New-Surface -Parent $SidebarFooter -Location (New-Object System.Drawing.Point(16, 10)) -Size (New-Object System.Drawing.Size(220, 140)) -Tag "SidebarAlt"
[void](New-Label -Parent $SidebarNote -Text "Before you run" -Location (New-Object System.Drawing.Point(24, 18)) -Font (New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $SidebarNote -Text "Review everything first. Windows asks for approval only when the run is ready to begin." -Location (New-Object System.Drawing.Point(24, 44)) -Size (New-Object System.Drawing.Size(176, 52)) -AutoSize $false -Tag "BodyMuted")
[void](New-Label -Parent $SidebarNote -Text "Current configs are backed up before file writes begin." -Location (New-Object System.Drawing.Point(24, 100)) -Size (New-Object System.Drawing.Size(176, 30)) -AutoSize $false -Tag "BodyMuted")

[int]$sbY = 184
[int]$sbH = 44
[int]$sbGap = 8
$BtnDashboard    = New-Button -Parent $Sidebar -LangKey "Dashboard"    -Location (New-Object System.Drawing.Point(16, $sbY)) -Size (New-Object System.Drawing.Size(220, $sbH)) -Tag "SidebarBtn"
$sbY += $sbH + $sbGap
$BtnLiveControl  = New-Button -Parent $Sidebar -LangKey "LiveControl"  -Location (New-Object System.Drawing.Point(16, $sbY)) -Size (New-Object System.Drawing.Size(220, $sbH)) -Tag "SidebarBtn"
$sbY += $sbH + $sbGap
$BtnInstallation = New-Button -Parent $Sidebar -LangKey "Installation" -Location (New-Object System.Drawing.Point(16, $sbY)) -Size (New-Object System.Drawing.Size(220, $sbH)) -Tag "SidebarBtn"
$sbY += $sbH + $sbGap
$BtnTheme        = New-Button -Parent $Sidebar -LangKey "Themes"       -Location (New-Object System.Drawing.Point(16, $sbY)) -Size (New-Object System.Drawing.Size(220, $sbH)) -Tag "SidebarBtn"
$sbY += $sbH + $sbGap
$BtnBehavior     = New-Button -Parent $Sidebar -LangKey "Behavior"     -Location (New-Object System.Drawing.Point(16, $sbY)) -Size (New-Object System.Drawing.Size(220, $sbH)) -Tag "SidebarBtn"
$sbY += $sbH + $sbGap
$BtnHardening    = New-Button -Parent $Sidebar -LangKey "Hardening"    -Location (New-Object System.Drawing.Point(16, $sbY)) -Size (New-Object System.Drawing.Size(220, $sbH)) -Tag "SidebarBtn"
$sbY += $sbH + $sbGap
$BtnRepair       = New-Button -Parent $Sidebar -LangKey "Repair"       -Location (New-Object System.Drawing.Point(16, $sbY)) -Size (New-Object System.Drawing.Size(220, $sbH)) -Tag "SidebarBtn"

$script:NavIndicators = @{
    $BtnDashboard    = New-Panel -Parent $Sidebar -Location (New-Object System.Drawing.Point(20, $($BtnDashboard.Top + 9))) -Size (New-Object System.Drawing.Size(4, 26)) -Tag "NavIndicator"
    $BtnLiveControl  = New-Panel -Parent $Sidebar -Location (New-Object System.Drawing.Point(20, $($BtnLiveControl.Top + 9))) -Size (New-Object System.Drawing.Size(4, 26)) -Tag "NavIndicator"
    $BtnInstallation = New-Panel -Parent $Sidebar -Location (New-Object System.Drawing.Point(20, $($BtnInstallation.Top + 9))) -Size (New-Object System.Drawing.Size(4, 26)) -Tag "NavIndicator"
    $BtnTheme        = New-Panel -Parent $Sidebar -Location (New-Object System.Drawing.Point(20, $($BtnTheme.Top + 9))) -Size (New-Object System.Drawing.Size(4, 26)) -Tag "NavIndicator"
    $BtnBehavior     = New-Panel -Parent $Sidebar -Location (New-Object System.Drawing.Point(20, $($BtnBehavior.Top + 9))) -Size (New-Object System.Drawing.Size(4, 26)) -Tag "NavIndicator"
    $BtnHardening    = New-Panel -Parent $Sidebar -Location (New-Object System.Drawing.Point(20, $($BtnHardening.Top + 9))) -Size (New-Object System.Drawing.Size(4, 26)) -Tag "NavIndicator"
    $BtnRepair       = New-Panel -Parent $Sidebar -Location (New-Object System.Drawing.Point(20, $($BtnRepair.Top + 9))) -Size (New-Object System.Drawing.Size(4, 26)) -Tag "NavIndicator"
}
foreach ($indicator in $script:NavIndicators.Values) {
    $indicator.Visible = $false
    $indicator.Enabled = $false
}

$BtnExec = New-Button -Parent $Footer -LangKey "Execute" -Location (New-Object System.Drawing.Point(24, 20)) -Size (New-Object System.Drawing.Size(248, 46)) -Tag "PrimaryButton"
$FooterStateBadge = New-Badge -Parent $Footer -Text "Checking workspace" -Location (New-Object System.Drawing.Point(296, 14)) -Size (New-Object System.Drawing.Size(140, 28)) -Tag "BadgeAccent"
$FooterSummary = New-Label -Parent $Footer -LangKey "FooterSummary" -Location (New-Object System.Drawing.Point(448, 18)) -Size (New-Object System.Drawing.Size(300, 18)) -AutoSize $false -Tag "BodyMuted"
$FooterSummary.AutoEllipsis = $true
$ProgressBar = New-Object System.Windows.Forms.ProgressBar
$ProgressBar.Location = New-Object System.Drawing.Point(448, 46)
$ProgressBar.Size = New-Object System.Drawing.Size(300, 10)
$ProgressBar.Style = "Continuous"
$ProgressBar.Value = 0
$ProgressBar.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
[void]$Footer.Controls.Add($ProgressBar)
$StatusLabel = New-Label -Parent $Footer -Text "Status: Ready" -Location (New-Object System.Drawing.Point(772, 29)) -Size (New-Object System.Drawing.Size(560, 22)) -AutoSize $false -Tag "MutedStrong"
$StatusLabel.AutoEllipsis = $true
$StatusLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$PageDashboard    = New-PagePanel -CanvasHeight 682; [void]$MainPanel.Controls.Add($PageDashboard)
$PageDashboard.AutoScroll = $false
$PageDashboard.AutoScrollMinSize = New-Object System.Drawing.Size(0, 0)
$PageLiveControl  = New-PagePanel -CanvasHeight 1030; [void]$MainPanel.Controls.Add($PageLiveControl)
$PageInstallation = New-PagePanel -CanvasHeight 610; [void]$MainPanel.Controls.Add($PageInstallation)
$PageTheme        = New-PagePanel -CanvasHeight 690; [void]$MainPanel.Controls.Add($PageTheme)
$PageBehavior     = New-PagePanel -CanvasHeight 740; [void]$MainPanel.Controls.Add($PageBehavior)
$PageHardening    = New-PagePanel -CanvasHeight 780; [void]$MainPanel.Controls.Add($PageHardening)
$PageRepair       = New-PagePanel -CanvasHeight 572; [void]$MainPanel.Controls.Add($PageRepair)

$DashboardCanvas = Get-PageCanvas $PageDashboard
$LiveControlCanvas = Get-PageCanvas $PageLiveControl
$InstallationCanvas = Get-PageCanvas $PageInstallation
$ThemeCanvas = Get-PageCanvas $PageTheme
$BehaviorCanvas = Get-PageCanvas $PageBehavior
$HardeningCanvas = Get-PageCanvas $PageHardening
$RepairCanvas = Get-PageCanvas $PageRepair

# --- Dashboard Page ---
$DashHero = New-Surface -Parent $DashboardCanvas -Location (New-Object System.Drawing.Point(0, 0)) -Size (New-Object System.Drawing.Size(1040, 216))
$DashEyebrow = New-Label -Parent $DashHero -Text "WORKSPACE OVERVIEW" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted"
$DashTitle = New-Label -Parent $DashHero -LangKey "DashTitle" -Location (New-Object System.Drawing.Point(24, 44)) -Font (New-Object System.Drawing.Font("Segoe UI", 24, [System.Drawing.FontStyle]::Bold)) -Size (New-Object System.Drawing.Size(560, 52)) -AutoSize $false
$DashSub = New-Label -Parent $DashHero -LangKey "DashSub" -Location (New-Object System.Drawing.Point(24, 96)) -Size (New-Object System.Drawing.Size(548, 50)) -AutoSize $false -Tag "SubHeader"
$DashHint = New-Label -Parent $DashHero -LangKey "DashHint" -Location (New-Object System.Drawing.Point(24, 154)) -Size (New-Object System.Drawing.Size(556, 38)) -AutoSize $false -Tag "BodyMuted"
$DashOverview = New-Surface -Parent $DashHero -Location (New-Object System.Drawing.Point(698, 18)) -Size (New-Object System.Drawing.Size(318, 192)) -Tag "SurfaceAlt"
$DashOverviewHeader = New-Label -Parent $DashOverview -Text "Session overview" -Location (New-Object System.Drawing.Point(24, 20)) -Font (New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold))
$DashInstallStatus = New-Label -Parent $DashOverview -Text "Not detected yet" -Location (New-Object System.Drawing.Point(24, 52)) -Font (New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold))
$DashInstallDetail = New-Label -Parent $DashOverview -Text "Choose an existing install or switch to clean install mode." -Location (New-Object System.Drawing.Point(24, 84)) -Size (New-Object System.Drawing.Size(260, 34)) -AutoSize $false -Tag "BodyMuted"
$DashRunModeLabel = New-Label -Parent $DashOverview -Text "Current run mode" -Location (New-Object System.Drawing.Point(24, 118)) -Font (New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted"
$DashModeDetail = New-Label -Parent $DashOverview -Text "Modify current installation" -Location (New-Object System.Drawing.Point(24, 138)) -Size (New-Object System.Drawing.Size(260, 18)) -AutoSize $false -Tag "MutedStrong"
$DashLastAppliedLabel = New-Label -Parent $DashOverview -Text "Last successful run" -Location (New-Object System.Drawing.Point(24, 160)) -Font (New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted"
$DashLastAppliedValue = New-Label -Parent $DashOverview -Text "Last applied: Not yet" -Location (New-Object System.Drawing.Point(24, 178)) -Size (New-Object System.Drawing.Size(260, 16)) -AutoSize $false -Tag "MutedStrong"

$DashCardInstall = New-Surface -Parent $DashboardCanvas -Location (New-Object System.Drawing.Point(0, 238)) -Size (New-Object System.Drawing.Size(332, 152))
$DashInstallStepBadge = New-Badge -Parent $DashCardInstall -Text "Step 1" -Location (New-Object System.Drawing.Point(236, 20)) -Size (New-Object System.Drawing.Size(72, 28)) -Tag "BadgeAccent"
$DashCardInstallTitle = New-Label -Parent $DashCardInstall -Text "Confirm install flow" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold))
$DashCardInstallBody = New-Label -Parent $DashCardInstall -Text "Choose modify or clean install, then validate the folder before anything changes." -Location (New-Object System.Drawing.Point(24, 54)) -Size (New-Object System.Drawing.Size(284, 40)) -AutoSize $false -Tag "BodyMuted"
$BtnDashInstallJump = New-Button -Parent $DashCardInstall -Text "Open install" -Location (New-Object System.Drawing.Point(24, 106)) -Size (New-Object System.Drawing.Size(132, 34)) -Tag "SecondaryButton" -Click { Show-Page -Button $BtnInstallation; $TxtPath.Select(); $null = $TxtPath.Focus() }
$DashCardTheme = New-Surface -Parent $DashboardCanvas -Location (New-Object System.Drawing.Point(354, 238)) -Size (New-Object System.Drawing.Size(332, 152))
$DashThemeStepBadge = New-Badge -Parent $DashCardTheme -Text "Step 2" -Location (New-Object System.Drawing.Point(236, 20)) -Size (New-Object System.Drawing.Size(72, 28)) -Tag "BadgeAccent"
$DashCardThemeTitle = New-Label -Parent $DashCardTheme -Text "Preview the final look" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold))
$DashCardThemeBody = New-Label -Parent $DashCardTheme -Text "Compare supported themes, layer icon packs, and tighten layout defaults before you apply." -Location (New-Object System.Drawing.Point(24, 54)) -Size (New-Object System.Drawing.Size(284, 40)) -AutoSize $false -Tag "BodyMuted"
$BtnDashThemeJump = New-Button -Parent $DashCardTheme -Text "Review themes" -Location (New-Object System.Drawing.Point(24, 106)) -Size (New-Object System.Drawing.Size(132, 34)) -Tag "SecondaryButton" -Click { Show-Page -Button $BtnTheme }
$DashCardSafety = New-Surface -Parent $DashboardCanvas -Location (New-Object System.Drawing.Point(708, 238)) -Size (New-Object System.Drawing.Size(332, 152))
$DashSafetyStepBadge = New-Badge -Parent $DashCardSafety -Text "Step 3" -Location (New-Object System.Drawing.Point(236, 20)) -Size (New-Object System.Drawing.Size(72, 28)) -Tag "BadgeAccent"
$DashCardSafetyTitle = New-Label -Parent $DashCardSafety -Text "Keep recovery close" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold))
$DashCardSafetyBody = New-Label -Parent $DashCardSafety -Text "Reset, audit, safe mode, and uninstall tools are ready if this install needs a fast rollback or repair." -Location (New-Object System.Drawing.Point(24, 54)) -Size (New-Object System.Drawing.Size(284, 40)) -AutoSize $false -Tag "BodyMuted"
$BtnDashRepairJump = New-Button -Parent $DashCardSafety -Text "Repair tools" -Location (New-Object System.Drawing.Point(24, 106)) -Size (New-Object System.Drawing.Size(132, 34)) -Tag "SecondaryButton" -Click { Show-Page -Button $BtnRepair }

$DashPrefs = New-Surface -Parent $DashboardCanvas -Location (New-Object System.Drawing.Point(0, 414)) -Size (New-Object System.Drawing.Size(1040, 238))
$DashPrefsHeading = New-Label -Parent $DashPrefs -Text "Workspace preferences" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold))
$DashPrefsIntro = New-Label -Parent $DashPrefs -Text "Set the app chrome once, then the tool remembers the workspace on the next launch." -Location (New-Object System.Drawing.Point(24, 52)) -Size (New-Object System.Drawing.Size(620, 24)) -AutoSize $false -Tag "BodyMuted"
$LblGuiTheme = New-Label -Parent $DashPrefs -LangKey "GuiTheme" -Location (New-Object System.Drawing.Point(24, 96))
$CboGuiTheme = New-ComboBox -Parent $DashPrefs -Location (New-Object System.Drawing.Point(24, 124)) -Size (New-Object System.Drawing.Size(290, 36)) -Tag "Input" -Items $GuiThemes.Keys
$LblLang = New-Label -Parent $DashPrefs -LangKey "Language" -Location (New-Object System.Drawing.Point(348, 96))
$CboLang = New-ComboBox -Parent $DashPrefs -Location (New-Object System.Drawing.Point(348, 124)) -Size (New-Object System.Drawing.Size(290, 36)) -Tag "Input" -Items ($AvailableLanguages.Keys | Sort-Object)
$CboLang.FormattingEnabled = $true
$CboLang.Add_Format({
    param($src, $evt)
    $code = [string]$evt.ListItem
    if ([string]::IsNullOrWhiteSpace($code)) { return }
    $evt.Value = Get-LanguageDisplayName $code
})
$BtnImportPreset = New-Button -Parent $DashPrefs -Text "Import preset" -Location (New-Object System.Drawing.Point(24, 178)) -Size (New-Object System.Drawing.Size(140, 34)) -Tag "SecondaryButton"
$BtnExportPreset = New-Button -Parent $DashPrefs -Text "Export preset" -Location (New-Object System.Drawing.Point(178, 178)) -Size (New-Object System.Drawing.Size(140, 34)) -Tag "SecondaryButton"
$DashPrefsNote = New-Surface -Parent $DashPrefs -Location (New-Object System.Drawing.Point(668, 80)) -Size (New-Object System.Drawing.Size(348, 144)) -Tag "Callout"
$DashPrefsNoteHeading = New-Label -Parent $DashPrefsNote -Text "Workspace status" -Location (New-Object System.Drawing.Point(18, 16)) -Font (New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold))
$DashPrefsStateValue = New-Label -Parent $DashPrefsNote -Text "No saved workspace yet" -Location (New-Object System.Drawing.Point(18, 40)) -Font (New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)) -Size (New-Object System.Drawing.Size(310, 24)) -AutoSize $false
$DashPrefsStateDetail = New-Label -Parent $DashPrefsNote -Text "Your selected path, theme, language, and run options will be remembered after the first successful run." -Location (New-Object System.Drawing.Point(18, 66)) -Size (New-Object System.Drawing.Size(310, 44)) -AutoSize $false -Tag "BodyMuted"
$BtnRestoreWorkspace = New-Button -Parent $DashPrefsNote -Text "Restore last run" -Location (New-Object System.Drawing.Point(18, 112)) -Size (New-Object System.Drawing.Size(170, 28)) -Tag "SecondaryButton"

function Layout-Dashboard {
    if (-not $PageDashboard -or -not $DashboardCanvas -or -not $DashHero -or -not $DashOverview -or -not $DashPrefs) { return }

    $DashboardCanvas.Size = New-Object System.Drawing.Size(1040, 682)
    $PageDashboard.AutoScrollMinSize = New-Object System.Drawing.Size(1064, 718)

    $DashHero.Size = New-Object System.Drawing.Size(1040, 216)
    $DashTitle.Size = New-Object System.Drawing.Size(590, 52)
    $DashSub.Size = New-Object System.Drawing.Size(566, 50)
    $DashHint.Size = New-Object System.Drawing.Size(590, 44)
    $DashOverview.Location = New-Object System.Drawing.Point(698, 18)
    $DashOverview.Size = New-Object System.Drawing.Size(318, 192)
    $DashInstallStatus.Size = New-Object System.Drawing.Size(260, 42)
    $DashInstallDetail.Size = New-Object System.Drawing.Size(260, 34)
    $DashModeDetail.Size = New-Object System.Drawing.Size(260, 18)
    $DashLastAppliedValue.Size = New-Object System.Drawing.Size(260, 16)

    $DashCardInstall.Location = New-Object System.Drawing.Point(0, 238)
    $DashCardInstall.Size = New-Object System.Drawing.Size(332, 152)
    $DashInstallStepBadge.Location = New-Object System.Drawing.Point(236, 20)
    $DashCardInstallTitle.Size = New-Object System.Drawing.Size(184, 24)
    $DashCardInstallBody.Size = New-Object System.Drawing.Size(284, 40)

    $DashCardTheme.Location = New-Object System.Drawing.Point(354, 238)
    $DashCardTheme.Size = New-Object System.Drawing.Size(332, 152)
    $DashThemeStepBadge.Location = New-Object System.Drawing.Point(236, 20)
    $DashCardThemeTitle.Size = New-Object System.Drawing.Size(184, 24)
    $DashCardThemeBody.Size = New-Object System.Drawing.Size(284, 40)

    $DashCardSafety.Location = New-Object System.Drawing.Point(708, 238)
    $DashCardSafety.Size = New-Object System.Drawing.Size(332, 152)
    $DashSafetyStepBadge.Location = New-Object System.Drawing.Point(236, 20)
    $DashCardSafetyTitle.Size = New-Object System.Drawing.Size(184, 24)
    $DashCardSafetyBody.Size = New-Object System.Drawing.Size(284, 40)

    $DashPrefs.Location = New-Object System.Drawing.Point(0, 414)
    $DashPrefs.Size = New-Object System.Drawing.Size(1040, 238)
    $DashPrefsIntro.Size = New-Object System.Drawing.Size(620, 24)
    $LblGuiTheme.Location = New-Object System.Drawing.Point(24, 96)
    $CboGuiTheme.Location = New-Object System.Drawing.Point(24, 124)
    $CboGuiTheme.Size = New-Object System.Drawing.Size(290, 36)
    $LblLang.Location = New-Object System.Drawing.Point(348, 96)
    $CboLang.Location = New-Object System.Drawing.Point(348, 124)
    $CboLang.Size = New-Object System.Drawing.Size(290, 36)
    $BtnImportPreset.Location = New-Object System.Drawing.Point(24, 178)
    $BtnImportPreset.Size = New-Object System.Drawing.Size(140, 34)
    $BtnExportPreset.Location = New-Object System.Drawing.Point(178, 178)
    $BtnExportPreset.Size = New-Object System.Drawing.Size(140, 34)
    $DashPrefsNote.Location = New-Object System.Drawing.Point(668, 80)
    $DashPrefsNote.Size = New-Object System.Drawing.Size(348, 144)
    $DashPrefsStateValue.Size = New-Object System.Drawing.Size(310, 24)
    $DashPrefsStateDetail.Size = New-Object System.Drawing.Size(310, 44)
    $BtnRestoreWorkspace.Location = New-Object System.Drawing.Point(18, 112)
    $BtnRestoreWorkspace.Size = New-Object System.Drawing.Size(170, 28)
}

# --- Live Control Page ---
$LiveHero = New-Surface -Parent $LiveControlCanvas -Location (New-Object System.Drawing.Point(0, 0)) -Size (New-Object System.Drawing.Size(1040, 136))
[void](New-Label -Parent $LiveHero -Text "LIVE CONTROL" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
[void](New-Label -Parent $LiveHero -Text "Control JDownloader from one queue view" -Location (New-Object System.Drawing.Point(24, 44)) -Font (New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)) -Size (New-Object System.Drawing.Size(640, 38)) -AutoSize $false)
[void](New-Label -Parent $LiveHero -Text "Connect to the local JSON API, inspect active downloads, start or pause the controller, and send links to LinkGrabber." -Location (New-Object System.Drawing.Point(24, 88)) -Size (New-Object System.Drawing.Size(670, 28)) -AutoSize $false -Tag "SubHeader")
$LiveHeroBadge = New-Badge -Parent $LiveHero -Text "Not connected" -Location (New-Object System.Drawing.Point(812, 26)) -Size (New-Object System.Drawing.Size(164, 30)) -Tag "BadgeNeutral"
[void](New-Label -Parent $LiveHero -Text "The endpoint stays local by default." -Location (New-Object System.Drawing.Point(782, 68)) -Size (New-Object System.Drawing.Size(210, 38)) -AutoSize $false -Tag "BodyMuted")

$LiveConnectionSurface = New-Surface -Parent $LiveControlCanvas -Location (New-Object System.Drawing.Point(0, 154)) -Size (New-Object System.Drawing.Size(1040, 122)) -Tag "SurfaceAlt"
[void](New-Label -Parent $LiveConnectionSurface -Text "JDownloader API connection" -Location (New-Object System.Drawing.Point(24, 18)) -Font (New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $LiveConnectionSurface -Text "Enable JDownloader's deprecated local API in Advanced Settings before connecting." -Location (New-Object System.Drawing.Point(24, 44)) -Size (New-Object System.Drawing.Size(560, 18)) -AutoSize $false -Tag "BodyMuted")
$TxtLiveEndpoint = New-TextBox -Parent $LiveConnectionSurface -Location (New-Object System.Drawing.Point(24, 70)) -Size (New-Object System.Drawing.Size(500, 34)) -Text $script:LiveApiEndpoint -Tag "Input"
$BtnLiveConnect = New-Button -Parent $LiveConnectionSurface -Text "Connect" -Location (New-Object System.Drawing.Point(540, 70)) -Size (New-Object System.Drawing.Size(108, 34)) -Tag "PrimaryButton"
$BtnLiveRefresh = New-Button -Parent $LiveConnectionSurface -Text "Refresh queue" -Location (New-Object System.Drawing.Point(660, 70)) -Size (New-Object System.Drawing.Size(132, 34)) -Tag "SecondaryButton"
$LiveConnectionBadge = New-Badge -Parent $LiveConnectionSurface -Text "Offline" -Location (New-Object System.Drawing.Point(812, 72)) -Size (New-Object System.Drawing.Size(112, 28)) -Tag "BadgeNeutral"
$LiveConnectionDetail = New-Label -Parent $LiveConnectionSurface -Text "No request made yet." -Location (New-Object System.Drawing.Point(812, 100)) -Size (New-Object System.Drawing.Size(194, 18)) -AutoSize $false -Tag "BodyMuted"

$LiveActionSurface = New-Surface -Parent $LiveControlCanvas -Location (New-Object System.Drawing.Point(0, 294)) -Size (New-Object System.Drawing.Size(1040, 166))
[void](New-Label -Parent $LiveActionSurface -Text "Controller actions and LinkGrabber" -Location (New-Object System.Drawing.Point(24, 18)) -Font (New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)))
$BtnLiveStart = New-Button -Parent $LiveActionSurface -Text "Start downloads" -Location (New-Object System.Drawing.Point(24, 52)) -Size (New-Object System.Drawing.Size(142, 34)) -Tag "SuccessButton"
$BtnLivePause = New-Button -Parent $LiveActionSurface -Text "Pause downloads" -Location (New-Object System.Drawing.Point(178, 52)) -Size (New-Object System.Drawing.Size(142, 34)) -Tag "SecondaryButton"
$BtnLiveStop = New-Button -Parent $LiveActionSurface -Text "Stop downloads" -Location (New-Object System.Drawing.Point(332, 52)) -Size (New-Object System.Drawing.Size(142, 34)) -Tag "DangerButton"
$BtnLiveGrabberRefresh = New-Button -Parent $LiveActionSurface -Text "Refresh LinkGrabber" -Location (New-Object System.Drawing.Point(488, 52)) -Size (New-Object System.Drawing.Size(166, 34)) -Tag "SecondaryButton"
$LiveLinkGrabberSummary = New-Label -Parent $LiveActionSurface -Text "LinkGrabber: not queried" -Location (New-Object System.Drawing.Point(680, 58)) -Size (New-Object System.Drawing.Size(326, 22)) -AutoSize $false -Tag "MutedStrong"
[void](New-Label -Parent $LiveActionSurface -Text "Paste one or more URLs below. They are forwarded to JDownloader's LinkGrabber instead of using the clipboard." -Location (New-Object System.Drawing.Point(24, 100)) -Size (New-Object System.Drawing.Size(680, 20)) -AutoSize $false -Tag "BodyMuted")
$TxtLiveLinks = New-TextBox -Parent $LiveActionSurface -Location (New-Object System.Drawing.Point(24, 124)) -Size (New-Object System.Drawing.Size(700, 30)) -Tag "Input"
$TxtLiveLinks.Multiline = $true
$TxtLiveLinks.ScrollBars = "Vertical"
$TxtLiveLinks.AcceptsReturn = $true
[void](New-Label -Parent $LiveActionSurface -Text "Package name" -Location (New-Object System.Drawing.Point(748, 100)) -Size (New-Object System.Drawing.Size(120, 20)) -AutoSize $false -Tag "BodyMuted")
$TxtLivePackage = New-TextBox -Parent $LiveActionSurface -Location (New-Object System.Drawing.Point(748, 124)) -Size (New-Object System.Drawing.Size(152, 30)) -Tag "Input"
$BtnLiveAddLinks = New-Button -Parent $LiveActionSurface -Text "Send to LinkGrabber" -Location (New-Object System.Drawing.Point(912, 124)) -Size (New-Object System.Drawing.Size(104, 30)) -Tag "PrimaryButton"

$LiveQueueSurface = New-Surface -Parent $LiveControlCanvas -Location (New-Object System.Drawing.Point(0, 478)) -Size (New-Object System.Drawing.Size(1040, 282)) -Tag "Surface"
[void](New-Label -Parent $LiveQueueSurface -Text "Download queue" -Location (New-Object System.Drawing.Point(24, 18)) -Font (New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)))
$LiveQueueSummary = New-Label -Parent $LiveQueueSurface -Text "Connect to load the current queue." -Location (New-Object System.Drawing.Point(180, 22)) -Size (New-Object System.Drawing.Size(820, 20)) -AutoSize $false -Tag "MutedStrong"
$LiveQueueGrid = New-Object System.Windows.Forms.DataGridView
$LiveQueueGrid.Location = New-Object System.Drawing.Point(24, 52)
$LiveQueueGrid.Size = New-Object System.Drawing.Size(992, 208)
$LiveQueueGrid.Tag = "QueueGrid"
$LiveQueueGrid.ReadOnly = $true
$LiveQueueGrid.AllowUserToAddRows = $false
$LiveQueueGrid.AllowUserToDeleteRows = $false
$LiveQueueGrid.AllowUserToResizeRows = $false
$LiveQueueGrid.AutoGenerateColumns = $false
$LiveQueueGrid.RowHeadersVisible = $false
$LiveQueueGrid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$LiveQueueGrid.MultiSelect = $false
$LiveQueueGrid.AutoSizeRowsMode = [System.Windows.Forms.DataGridViewAutoSizeRowsMode]::None
$LiveQueueGrid.RowTemplate.Height = 28
[void]$LiveQueueGrid.Columns.Add("Name", "Name"); $LiveQueueGrid.Columns["Name"].Width = 330
[void]$LiveQueueGrid.Columns.Add("Host", "Host"); $LiveQueueGrid.Columns["Host"].Width = 150
[void]$LiveQueueGrid.Columns.Add("Status", "Status"); $LiveQueueGrid.Columns["Status"].Width = 168
[void]$LiveQueueGrid.Columns.Add("Progress", "Progress"); $LiveQueueGrid.Columns["Progress"].Width = 112
[void]$LiveQueueGrid.Columns.Add("Speed", "Speed"); $LiveQueueGrid.Columns["Speed"].Width = 112
[void]$LiveQueueGrid.Columns.Add("ETA", "ETA"); $LiveQueueGrid.Columns["ETA"].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
[void]$LiveQueueSurface.Controls.Add($LiveQueueGrid)

$LiveCaptchaSurface = New-Surface -Parent $LiveControlCanvas -Location (New-Object System.Drawing.Point(0, 778)) -Size (New-Object System.Drawing.Size(1040, 220)) -Tag "Callout"
[void](New-Label -Parent $LiveCaptchaSurface -Text "Captcha attention" -Location (New-Object System.Drawing.Point(24, 18)) -Font (New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)))
$LiveCaptchaBadge = New-Badge -Parent $LiveCaptchaSurface -Text "No pending captcha" -Location (New-Object System.Drawing.Point(780, 18)) -Size (New-Object System.Drawing.Size(196, 28)) -Tag "BadgeSuccess"
$LiveCaptchaDetail = New-Label -Parent $LiveCaptchaSurface -Text "Captcha prompts from JDownloader appear here while the app stays in the tray." -Location (New-Object System.Drawing.Point(24, 50)) -Size (New-Object System.Drawing.Size(690, 22)) -AutoSize $false -Tag "BodyMuted"
$LiveCaptchaImage = New-Object System.Windows.Forms.PictureBox
$LiveCaptchaImage.Location = New-Object System.Drawing.Point(24, 82)
$LiveCaptchaImage.Size = New-Object System.Drawing.Size(180, 118)
$LiveCaptchaImage.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$LiveCaptchaImage.BackColor = [System.Drawing.Color]::Transparent
[void]$LiveCaptchaSurface.Controls.Add($LiveCaptchaImage)
$LiveCaptchaHost = New-Label -Parent $LiveCaptchaSurface -Text "No captcha job is waiting." -Location (New-Object System.Drawing.Point(228, 84)) -Size (New-Object System.Drawing.Size(330, 22)) -AutoSize $false -Tag "MutedStrong"
$LiveCaptchaExplanation = New-Label -Parent $LiveCaptchaSurface -Text "" -Location (New-Object System.Drawing.Point(228, 112)) -Size (New-Object System.Drawing.Size(330, 42)) -AutoSize $false -Tag "BodyMuted"
$TxtLiveCaptchaAnswer = New-TextBox -Parent $LiveCaptchaSurface -Location (New-Object System.Drawing.Point(580, 84)) -Size (New-Object System.Drawing.Size(174, 34)) -Tag "Input"
$BtnLiveCaptchaSolve = New-Button -Parent $LiveCaptchaSurface -Text "Submit answer" -Location (New-Object System.Drawing.Point(580, 128)) -Size (New-Object System.Drawing.Size(128, 32)) -Tag "PrimaryButton"
$BtnLiveCaptchaSkip = New-Button -Parent $LiveCaptchaSurface -Text "Skip" -Location (New-Object System.Drawing.Point(718, 128)) -Size (New-Object System.Drawing.Size(82, 32)) -Tag "SecondaryButton"
$BtnLiveCaptchaRefresh = New-Button -Parent $LiveCaptchaSurface -Text "Refresh" -Location (New-Object System.Drawing.Point(810, 128)) -Size (New-Object System.Drawing.Size(94, 32)) -Tag "SecondaryButton"

function Clear-LiveCaptchaImage {
    if (-not $LiveCaptchaImage) { return }
    $oldImage = $LiveCaptchaImage.Image
    $LiveCaptchaImage.Image = $null
    if ($oldImage) { try { $oldImage.Dispose() } catch {} }
    $script:LiveCaptchaBitmap = $null
}

function ConvertFrom-LiveCaptchaData {
    param([string]$DataUrl)
    if ([string]::IsNullOrWhiteSpace($DataUrl)) { return $null }
    try {
        $encoded = $DataUrl
        if ($encoded -match ",") { $encoded = $encoded.Substring($encoded.IndexOf(",") + 1) }
        $bytes = [Convert]::FromBase64String($encoded)
        $stream = New-Object System.IO.MemoryStream(,$bytes)
        $source = $null
        try {
            $source = [System.Drawing.Image]::FromStream($stream)
            return New-Object System.Drawing.Bitmap($source)
        } finally {
            if ($source) { try { $source.Dispose() } catch {} }
            try { $stream.Dispose() } catch {}
        }
    } catch {
        return $null
    }
}

function Set-LiveCaptchaEmptyState {
    Clear-LiveCaptchaImage
    $script:LiveCaptchaJob = $null
    $LiveCaptchaBadge.Text = "No pending captcha"
    $LiveCaptchaBadge.Tag = "BadgeSuccess"
    $LiveCaptchaHost.Text = "No captcha job is waiting."
    $LiveCaptchaExplanation.Text = "Captcha prompts from JDownloader will appear here."
    $LiveCaptchaDetail.Text = "Captcha prompts from JDownloader appear here while the app stays in the tray."
    $TxtLiveCaptchaAnswer.Clear()
    Apply-GuiTheme -ThemeName $script:CurrentGuiTheme -Root $LiveCaptchaBadge
}

function Refresh-LiveCaptcha {
    if (-not $script:LiveApiClient -or $script:LiveApiBusy) { return }
    try {
        $jobs = @(Get-JD2CaptchaJobs -Client $script:LiveApiClient | Where-Object { $_ })
        if ($jobs.Count -eq 0) {
            Set-LiveCaptchaEmptyState
            return
        }

        $job = $jobs[0]
        $jobId = 0L
        try { $jobId = [int64]$job.id } catch {}
        if ($jobId -le 0) { throw "Captcha response did not include a valid job id." }
        $script:LiveCaptchaJob = $job
        $LiveCaptchaBadge.Text = "Needs attention"
        $LiveCaptchaBadge.Tag = "BadgeWarning"
        $LiveCaptchaHost.Text = "{0} captcha from {1}" -f ([string](Get-LiveLinkProperty -Link $job -Name "type" -Default "Unknown")), ([string](Get-LiveLinkProperty -Link $job -Name "hoster" -Default "JDownloader"))
        $LiveCaptchaExplanation.Text = [string](Get-LiveLinkProperty -Link $job -Name "explain" -Default "Enter the characters shown in the image.")
        $LiveCaptchaDetail.Text = "Captcha job {0} is waiting. Answer it here to resume the download." -f $jobId
        $imageData = Get-JD2CaptchaImage -Client $script:LiveApiClient -Id $jobId
        $image = ConvertFrom-LiveCaptchaData -DataUrl ([string]$imageData)
        if ($image) {
            Clear-LiveCaptchaImage
            $LiveCaptchaImage.Image = $image
            $script:LiveCaptchaBitmap = $image
        }
        Apply-GuiTheme -ThemeName $script:CurrentGuiTheme -Root $LiveCaptchaBadge
    } catch {
        $LiveCaptchaBadge.Text = "Captcha unavailable"
        $LiveCaptchaBadge.Tag = "BadgeNeutral"
        Apply-GuiTheme -ThemeName $script:CurrentGuiTheme -Root $LiveCaptchaBadge
        Log-Status "Captcha polling failed: $($_.Exception.Message)" "WARN"
    }
}

function Submit-LiveCaptchaAnswer {
    if (-not $script:LiveApiClient -or -not $script:LiveCaptchaJob) { Refresh-LiveCaptcha; return }
    $answer = $TxtLiveCaptchaAnswer.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($answer)) {
        Log-Status "Enter the captcha answer before submitting." "WARN"
        return
    }
    try {
        $jobId = [int64]$script:LiveCaptchaJob.id
        Submit-JD2Captcha -Client $script:LiveApiClient -Id $jobId -Result $answer | Out-Null
        Log-Status "Captcha answer submitted." "SUCCESS"
        Set-LiveCaptchaEmptyState
        Refresh-LiveCaptcha
    } catch {
        Log-Status "Captcha answer failed: $($_.Exception.Message)" "WARN"
    }
}

function Skip-LiveCaptchaJob {
    if (-not $script:LiveApiClient -or -not $script:LiveCaptchaJob) { Refresh-LiveCaptcha; return }
    try {
        $jobId = [int64]$script:LiveCaptchaJob.id
        Skip-JD2Captcha -Client $script:LiveApiClient -Id $jobId | Out-Null
        Log-Status "Captcha job skipped." "INFO"
        Set-LiveCaptchaEmptyState
        Refresh-LiveCaptcha
    } catch {
        Log-Status "Captcha skip failed: $($_.Exception.Message)" "WARN"
    }
}

function Get-LiveLinkProperty {
    param($Link, [string]$Name, $Default = "")
    if (-not $Link -or [string]::IsNullOrWhiteSpace($Name)) { return $Default }
    try {
        if ($Link.PSObject.Properties.Name -contains $Name) { return $Link.$Name }
    } catch {}
    return $Default
}

function Format-LiveBytes {
    param($Bytes)
    $value = 0.0
    try { $value = [double]$Bytes } catch {}
    if ($value -ge 1TB) { return "{0:N1} TB" -f ($value / 1TB) }
    if ($value -ge 1GB) { return "{0:N1} GB" -f ($value / 1GB) }
    if ($value -ge 1MB) { return "{0:N1} MB" -f ($value / 1MB) }
    if ($value -ge 1KB) { return "{0:N1} KB" -f ($value / 1KB) }
    return "{0:N0} B" -f $value
}

function Update-LiveQueueGrid {
    param($Queue)
    if (-not $LiveQueueGrid -or -not $Queue) { return }
    try { $LiveQueueGrid.Rows.Clear() } catch { return }
    foreach ($link in @($Queue.Links)) {
        $loaded = Get-LiveLinkProperty -Link $link -Name "bytesLoaded" -Default 0
        $total = Get-LiveLinkProperty -Link $link -Name "bytesTotal" -Default 0
        $percent = if ([double]$total -gt 0) { "{0:N0}%" -f (([double]$loaded / [double]$total) * 100) } else { "-" }
        $status = [string](Get-LiveLinkProperty -Link $link -Name "status" -Default "")
        if ([string]::IsNullOrWhiteSpace($status)) {
            if (ConvertTo-SafeBool (Get-LiveLinkProperty -Link $link -Name "finished" -Default $false)) { $status = "Finished" }
            elseif (ConvertTo-SafeBool (Get-LiveLinkProperty -Link $link -Name "running" -Default $false)) { $status = "Downloading" }
            else { $status = "Queued" }
        }
        $rowIndex = $LiveQueueGrid.Rows.Add()
        $row = $LiveQueueGrid.Rows[$rowIndex]
        $row.Cells["Name"].Value = [string](Get-LiveLinkProperty -Link $link -Name "name" -Default "Unnamed link")
        $row.Cells["Host"].Value = [string](Get-LiveLinkProperty -Link $link -Name "host" -Default "")
        $row.Cells["Status"].Value = $status
        $row.Cells["Progress"].Value = "{0} / {1}" -f $percent, (Format-LiveBytes $total)
        $row.Cells["Speed"].Value = "{0}/s" -f (Format-LiveBytes (Get-LiveLinkProperty -Link $link -Name "speed" -Default 0))
        $eta = Get-LiveLinkProperty -Link $link -Name "eta" -Default -1
        $row.Cells["ETA"].Value = if ([int64]$eta -gt 0) { "{0:N0}s" -f ([double]$eta / 1000) } else { "-" }
    }
    $LiveQueueSummary.Text = "{0} link(s), {1} active, {2} finished, {3}/s" -f $Queue.TotalLinks, $Queue.ActiveLinks, $Queue.FinishedLinks, (Format-LiveBytes $Queue.SpeedBps)
}

function New-LiveApiClientFromControls {
    if (-not $script:ApiModuleLoaded) {
        throw "The JD2 API module could not be loaded."
    }
    $endpoint = $TxtLiveEndpoint.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($endpoint)) { throw "Enter a JDownloader API endpoint first." }
    if ($endpoint -notmatch "^(?i)https?://") { throw "The JDownloader API endpoint must start with http:// or https://." }
    $script:LiveApiEndpoint = $endpoint.TrimEnd("/")
    return New-JD2ApiClient -BaseUrl $script:LiveApiEndpoint -Mode "Local" -TimeoutSec 5
}

function Refresh-LiveLinkGrabber {
    if (-not $script:LiveApiClient -or $script:LiveApiBusy) { return }
    try {
        $grabber = Get-JD2LinkGrabberQueue -Client $script:LiveApiClient
        $LiveLinkGrabberSummary.Text = "LinkGrabber: {0} package(s), {1} link(s)" -f $grabber.TotalPackages, $grabber.TotalLinks
    } catch {
        $LiveLinkGrabberSummary.Text = "LinkGrabber: unavailable"
    }
}

function Refresh-LiveApiQueue {
    if ($script:LiveApiBusy) { return }
    $script:LiveApiBusy = $true
    try {
        if (-not $script:LiveApiClient -or $TxtLiveEndpoint.Text.TrimEnd("/") -ne $script:LiveApiEndpoint) {
            $script:LiveApiClient = New-LiveApiClientFromControls
        }
        $queue = Get-JD2Queue -Client $script:LiveApiClient
        Update-LiveQueueGrid -Queue $queue
        $LiveHeroBadge.Text = "Connected"
        $LiveHeroBadge.Tag = "BadgeSuccess"
        $LiveConnectionBadge.Text = "Online"
        $LiveConnectionBadge.Tag = "BadgeSuccess"
        $LiveConnectionDetail.Text = "Updated {0}" -f (Get-Date).ToString("HH:mm:ss")
        Apply-GuiTheme -ThemeName $script:CurrentGuiTheme -Root $LiveHeroBadge
        Apply-GuiTheme -ThemeName $script:CurrentGuiTheme -Root $LiveConnectionBadge
        Log-Status "Live queue refreshed." "SUCCESS"
    } catch {
        $LiveHeroBadge.Text = "Not connected"
        $LiveHeroBadge.Tag = "BadgeNeutral"
        $LiveConnectionBadge.Text = "Offline"
        $LiveConnectionBadge.Tag = "BadgeDanger"
        $LiveConnectionDetail.Text = "Connection failed."
        Apply-GuiTheme -ThemeName $script:CurrentGuiTheme -Root $LiveHeroBadge
        Apply-GuiTheme -ThemeName $script:CurrentGuiTheme -Root $LiveConnectionBadge
        Log-Status "Live API request failed: $($_.Exception.Message)" "WARN"
    } finally {
        $script:LiveApiBusy = $false
    }
}

function Invoke-LiveApiAction {
    param([ValidateSet("Start", "Pause", "Stop")][string]$Action)
    if (-not $script:LiveApiClient) { Refresh-LiveApiQueue }
    if (-not $script:LiveApiClient) { return }
    try {
        switch ($Action) {
            "Start" { Start-JD2Downloads -Client $script:LiveApiClient | Out-Null; Log-Status "JDownloader downloads started." "SUCCESS" }
            "Pause" { Set-JD2DownloadsPaused -Client $script:LiveApiClient -Paused $true | Out-Null; Log-Status "JDownloader downloads paused." "SUCCESS" }
            "Stop"  { Stop-JD2Downloads -Client $script:LiveApiClient | Out-Null; Log-Status "JDownloader download controller stopped." "SUCCESS" }
        }
        Refresh-LiveApiQueue
    } catch {
        Log-Status "Live API action failed: $($_.Exception.Message)" "WARN"
    }
}

function Send-LiveLinksToGrabber {
    if (-not $script:LiveApiClient) { Refresh-LiveApiQueue }
    if (-not $script:LiveApiClient) { return }
    try {
        Add-JD2Links -Client $script:LiveApiClient -Links @($TxtLiveLinks.Text) -PackageName $TxtLivePackage.Text | Out-Null
        $TxtLiveLinks.Clear()
        Log-Status "Links sent to JDownloader LinkGrabber." "SUCCESS"
        Refresh-LiveLinkGrabber
    } catch {
        Log-Status "LinkGrabber request failed: $($_.Exception.Message)" "WARN"
    }
}

$script:LiveApiPollTimer = New-Object System.Windows.Forms.Timer
$script:LiveApiPollTimer.Interval = 5000
$script:LiveApiPollTimer.Add_Tick({
    if ($PageLiveControl.Visible -and $script:LiveApiClient -and -not $script:LiveApiBusy) {
        Refresh-LiveApiQueue
        Refresh-LiveCaptcha
    }
})
[void]$GlobalTimers.Add($script:LiveApiPollTimer)

# --- Installation Page ---
$InstallHero = New-Surface -Parent $InstallationCanvas -Location (New-Object System.Drawing.Point(0, 0)) -Size (New-Object System.Drawing.Size(1040, 160))
$InstTitle = New-Label -Parent $InstallHero -LangKey "InstTitle" -Location (New-Object System.Drawing.Point(24, 24)) -Tag "SectionHeader"
$InstSub = New-Label -Parent $InstallHero -LangKey "InstSub" -Location (New-Object System.Drawing.Point(24, 62)) -Size (New-Object System.Drawing.Size(690, 44)) -AutoSize $false -Tag "SubHeader"
[void](New-Label -Parent $InstallHero -Text "Readiness" -Location (New-Object System.Drawing.Point(808, 24)) -Font (New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
$InstallBadge = New-Badge -Parent $InstallHero -Text "Detection pending" -Location (New-Object System.Drawing.Point(808, 48)) -Size (New-Object System.Drawing.Size(168, 30)) -Tag "BadgeAccent"
[void](New-Label -Parent $InstallHero -Text "The tool can work against an existing install or prepare a fresh one for you." -Location (New-Object System.Drawing.Point(804, 68)) -Size (New-Object System.Drawing.Size(190, 50)) -AutoSize $false -Tag "BodyMuted")

$PathSurface = New-Surface -Parent $InstallationCanvas -Location (New-Object System.Drawing.Point(0, 184)) -Size (New-Object System.Drawing.Size(640, 246))
[void](New-Label -Parent $PathSurface -Text "Where JDownloader lives" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $PathSurface -Text "Use this when modifying an existing install. Clean install mode can start with a blank path." -Location (New-Object System.Drawing.Point(24, 50)) -Size (New-Object System.Drawing.Size(566, 34)) -AutoSize $false -Tag "BodyMuted")
$LblPath = New-Label -Parent $PathSurface -LangKey "InstPath" -Location (New-Object System.Drawing.Point(24, 94))
$TxtPath = New-TextBox -Parent $PathSurface -Location (New-Object System.Drawing.Point(24, 122)) -Size (New-Object System.Drawing.Size(592, 36)) -Tag "Input"
$LblPathState = New-Label -Parent $PathSurface -Text "Choose an existing JDownloader folder, or keep clean install mode selected." -Location (New-Object System.Drawing.Point(24, 164)) -Size (New-Object System.Drawing.Size(592, 34)) -AutoSize $false -Tag "BodyMuted"
$BtnBrowse = New-Button -Parent $PathSurface -LangKey "Browse" -Location (New-Object System.Drawing.Point(24, 202)) -Size (New-Object System.Drawing.Size(132, 34)) -Tag "SecondaryButton"
$BtnDetect = New-Button -Parent $PathSurface -LangKey "AutoDetect" -Location (New-Object System.Drawing.Point(168, 202)) -Size (New-Object System.Drawing.Size(148, 34)) -Tag "SecondaryButton"

$ModeSurface = New-Surface -Parent $InstallationCanvas -Location (New-Object System.Drawing.Point(662, 184)) -Size (New-Object System.Drawing.Size(378, 246)) -Tag "SurfaceAlt"
[void](New-Label -Parent $ModeSurface -Text "Install mode" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $ModeSurface -Text "Pick how the tool should approach this machine." -Location (New-Object System.Drawing.Point(24, 50)) -Size (New-Object System.Drawing.Size(320, 18)) -AutoSize $false -Tag "BodyMuted")
$LblMode = New-Label -Parent $ModeSurface -LangKey "InstMode" -Location (New-Object System.Drawing.Point(24, 92))
$CboMode = New-ComboBox -Parent $ModeSurface -Location (New-Object System.Drawing.Point(24, 120)) -Size (New-Object System.Drawing.Size(330, 36)) -Tag "Input" -Items @("Modify Existing (keep current install)", "Clean Install (download from GitHub)", "Clean Install (manual Mega download)")
$InstallModeSummaryTitle = New-Label -Parent $ModeSurface -Text "Modify an existing install" -Location (New-Object System.Drawing.Point(24, 172)) -Font (New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold))
$LblModeHelp = New-Label -Parent $ModeSurface -Text "Use this when JDownloader is already present and you want to refine its configuration in place." -Location (New-Object System.Drawing.Point(24, 196)) -Size (New-Object System.Drawing.Size(330, 36)) -AutoSize $false -Tag "BodyMuted"

$InstallNotes = New-Surface -Parent $InstallationCanvas -Location (New-Object System.Drawing.Point(0, 454)) -Size (New-Object System.Drawing.Size(1040, 122))
[void](New-Label -Parent $InstallNotes -Text "What this protects" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $InstallNotes -Text "Backups are created before modify-mode changes." -Location (New-Object System.Drawing.Point(24, 60)) -Tag "BodyMuted")
[void](New-Label -Parent $InstallNotes -Text "Theme, icon, and behavior changes apply after install completes." -Location (New-Object System.Drawing.Point(360, 60)) -Tag "BodyMuted")
[void](New-Label -Parent $InstallNotes -Text "If GitHub install fails, the app can fall back to the manual Mega flow." -Location (New-Object System.Drawing.Point(700, 60)) -Size (New-Object System.Drawing.Size(280, 36)) -AutoSize $false -Tag "BodyMuted")

function Update-InterfaceText {
    $Form.Text = Get-LangValue -Key "Title" -Fallback $script:AppTitle
    foreach ($entry in $script:LanguageRegistry) {
        $ctrl = $entry.Control
        if (-not $ctrl -or $ctrl.IsDisposed) { continue }
        $originalFallback = $null
        if ($DefaultLang.Contains($entry.Key)) { $originalFallback = [string]$DefaultLang[$entry.Key] }
        $resolved = Get-LangValue -Key $entry.Key -Fallback $originalFallback
        if (-not [string]::IsNullOrWhiteSpace($resolved)) {
            try { $ctrl.Text = $resolved } catch {}
        }
    }
    try { Update-ModeSummary } catch {}
    try { Update-ThemePreview } catch {}
    try { Update-BehaviorProfile } catch {}
    try { Update-HardeningProfile } catch {}
    try { Layout-Footer } catch {}
    try { Update-WorkspaceState } catch {}
}

function Layout-Footer {
    if (-not $Footer -or -not $BtnExec -or -not $FooterSummary -or -not $ProgressBar -or -not $StatusLabel -or -not $FooterStateBadge) { return }
    $contentLeft = $BtnExec.Right + 24
    $badgeWidth = 140
    $FooterStateBadge.Location = New-Object System.Drawing.Point($contentLeft, 14)
    $FooterStateBadge.Size = New-Object System.Drawing.Size($badgeWidth, 28)
    $summaryLeft = $FooterStateBadge.Right + 12
    $availableWidth = [Math]::Max(420, $Footer.ClientSize.Width - $summaryLeft - 24)
    $progressWidth = [Math]::Max(240, [Math]::Min(420, [int]($availableWidth * 0.42)))
    $FooterSummary.Location = New-Object System.Drawing.Point($summaryLeft, 14)
    $FooterSummary.Size = New-Object System.Drawing.Size($progressWidth, 34)
    $ProgressBar.Location = New-Object System.Drawing.Point($summaryLeft, 56)
    $ProgressBar.Size = New-Object System.Drawing.Size($progressWidth, 10)
    $statusLeft = $ProgressBar.Right + 28
    $statusWidth = [Math]::Max(220, $Footer.ClientSize.Width - $statusLeft - 24)
    $StatusLabel.Location = New-Object System.Drawing.Point($statusLeft, 29)
    $StatusLabel.Size = New-Object System.Drawing.Size($statusWidth, 22)
}

function Set-WorkspaceBusyState {
    param([bool]$IsBusy)
    if ($Sidebar) { $Sidebar.Enabled = -not $IsBusy }
    if ($MainPanel) { $MainPanel.Enabled = -not $IsBusy }
    if ($BtnExec) {
        $BtnExec.Enabled = -not $IsBusy
        $BtnExec.Text = if ($IsBusy) { Get-LangValue -Key "Running" -Fallback "Applying workspace..." } else { $Lang.Execute }
    }
    if ($FooterStateBadge -and $IsBusy) {
        Set-BadgeState -Badge $FooterStateBadge -Text "Applying" -State "Accent"
        $FooterSummary.Text = "Working through the selected installation, theme, behavior, hardening, and repair steps."
    }
    if ($Form) { $Form.UseWaitCursor = $IsBusy }
    Layout-Footer
    if (-not $IsBusy -and -not $script:IsBootstrapping) { Update-WorkspaceState }
}

function Configure-DirectoryInput {
    param($TextBox, [string]$CueText)
    if (-not $TextBox) { return }
    $TextBox.AutoCompleteMode = "SuggestAppend"
    $TextBox.AutoCompleteSource = "FileSystemDirectories"
    Set-CueBanner -Control $TextBox -Text $CueText
}

function Focus-InstallPath {
    if ($BtnInstallation -and $TxtPath) {
        Show-Page -Button $BtnInstallation
        $TxtPath.Select()
        $null = $TxtPath.Focus()
    }
}

function Test-StateHas {
    param($State, [string]$Name)
    if (-not $State) { return $false }
    try { return ($State.PSObject.Properties.Name -contains $Name) } catch { return $false }
}

function ConvertTo-SafeBool {
    # PowerShell's [bool] cast treats any non-empty string as $true, so a hand-edited
    # settings.json containing "false" or "0" (strings, not literals) would silently enable
    # the flag. Inspect the raw value with parse semantics that match how users think.
    param($Value, [bool]$Default = $false)
    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return $Value }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return ($Value -ne 0)
    }
    $s = ([string]$Value).Trim()
    if ([string]::IsNullOrEmpty($s)) { return $Default }
    switch -Regex ($s) {
        '^(?i)(true|yes|on|1|enabled)$'    { return $true }
        '^(?i)(false|no|off|0|disabled)$'  { return $false }
    }
    return $Default
}

function Set-NumericSafe {
    param($Control, $Value)
    if (-not $Control) { return }
    try {
        $d = [decimal]$Value
        if ($d -lt $Control.Minimum) { $d = $Control.Minimum }
        if ($d -gt $Control.Maximum) { $d = $Control.Maximum }
        $Control.Value = $d
    } catch {}
}

function Apply-StateToControls {
    param($State)
    if (-not $State) { return }

    $previousBootstrapping = $script:IsBootstrapping
    $script:IsBootstrapping = $true
    try {
        if (Test-StateHas $State "InstallPath") { $TxtPath.Text = [string]$State.InstallPath }
        if (Test-StateHas $State "ThemeName")   {
            $val = [string]$State.ThemeName
            if ($CboTheme.Items.Contains($val)) { $CboTheme.SelectedItem = $val } else { $CboTheme.Text = $val }
        }
        if ((Test-StateHas $State "GuiThemeName") -and $CboGuiTheme.Items.Contains($State.GuiThemeName)) { $CboGuiTheme.SelectedItem = [string]$State.GuiThemeName }
        if ((Test-StateHas $State "LanguageCode") -and $CboLang.Items.Contains($State.LanguageCode)) { $CboLang.SelectedItem = [string]$State.LanguageCode }
        if (Test-StateHas $State "IconPack") {
            $val = [string]$State.IconPack
            if ($CboIcons.Items.Contains($val)) { $CboIcons.SelectedItem = $val } else { $CboIcons.Text = $val }
        }
        if (Test-StateHas $State "WindowDec")    { $ChkWinDec.Checked     = ConvertTo-SafeBool $State.WindowDec     $true }
        if (Test-StateHas $State "ForceMinimal") { $ChkMinLay.Checked     = ConvertTo-SafeBool $State.ForceMinimal  $false }
        if (Test-StateHas $State "MaxSim")       { Set-NumericSafe -Control $NumSim    -Value $State.MaxSim }
        if (Test-StateHas $State "PauseSpeed")   { Set-NumericSafe -Control $NumPause  -Value $State.PauseSpeed }
        if (Test-StateHas $State "DlFolder")     { $TxtDl.Text = [string]$State.DlFolder }
        if (Test-StateHas $State "StartMin")     { $ChkMin.Checked        = ConvertTo-SafeBool $State.StartMin      $false }
        if (Test-StateHas $State "MinToTray")    { $ChkTray.Checked       = ConvertTo-SafeBool $State.MinToTray     $true }
        if (Test-StateHas $State "CloseToTray")  { $ChkCloseTray.Checked  = ConvertTo-SafeBool $State.CloseToTray   $true }
        if (Test-StateHas $State "PatchExe")     { $ChkExe.Checked        = ConvertTo-SafeBool $State.PatchExe      $true }
        if (Test-StateHas $State "AutoUpdate")   { $ChkUpdate.Checked     = ConvertTo-SafeBool $State.AutoUpdate    $true }
        if (Test-StateHas $State "MaxChunks")    { Set-NumericSafe -Control $NumChunks  -Value $State.MaxChunks }
        if (Test-StateHas $State "MaxPerHost")   { Set-NumericSafe -Control $NumPerHost -Value $State.MaxPerHost }
        if (Test-StateHas $State "HashCheck")       { $ChkHashCheck.Checked    = ConvertTo-SafeBool $State.HashCheck        $true }
        if (Test-StateHas $State "PreserveFileDate"){ $ChkPreserveDate.Checked = ConvertTo-SafeBool $State.PreserveFileDate $false }
        if (Test-StateHas $State "ClipboardMonitor"){ $ChkClipboard.Checked    = ConvertTo-SafeBool $State.ClipboardMonitor $true }
        if (Test-StateHas $State "DisableLocalAPI") { $ChkDisableAPI.Checked   = ConvertTo-SafeBool $State.DisableLocalAPI  $true }
        if (Test-StateHas $State "WriteVmOptions")  { $ChkVmOptions.Checked    = ConvertTo-SafeBool $State.WriteVmOptions   $false }
        if (Test-StateHas $State "Mode") {
            if ($State.Mode -eq "Modify") { $CboMode.SelectedIndex = 0 }
            elseif ((Test-StateHas $State "InstallSource") -and $State.InstallSource -eq "Mega") { $CboMode.SelectedIndex = 2 }
            else { $CboMode.SelectedIndex = 1 }
        }
    } finally {
        $script:IsBootstrapping = $previousBootstrapping
    }

    Apply-GuiTheme -ThemeName $CboGuiTheme.Text
    Update-ModeSummary
    Update-PathState
    Update-DownloadFolderState
    Update-ThemePreview
    Update-BehaviorProfile
    Update-HardeningProfile
    Update-WorkspaceState
}

function Get-CurrentGuiState {
    if (-not $CboMode -or -not $CboTheme -or -not $CboGuiTheme -or -not $CboIcons) { return $null }
    $mode = "Modify"
    $src = $null
    if ($CboMode.SelectedIndex -eq 1) {
        $mode = "Install"
        $src = "GitHub"
    } elseif ($CboMode.SelectedIndex -eq 2) {
        $mode = "Install"
        $src = "Mega"
    }

    return [ordered]@{
        Mode            = $mode
        InstallSource   = $src
        InstallPath     = $TxtPath.Text.Trim()
        ThemeName       = $CboTheme.Text
        GuiThemeName    = $CboGuiTheme.Text
        LanguageCode    = $CboLang.Text
        IconPack        = $CboIcons.Text
        WindowDec       = [bool]$ChkWinDec.Checked
        MaxSim          = [int]$NumSim.Value
        DlFolder        = $TxtDl.Text.Trim()
        StartMin        = [bool]$ChkMin.Checked
        MinToTray       = [bool]$ChkTray.Checked
        CloseToTray     = [bool]$ChkCloseTray.Checked
        PatchExe        = [bool]$ChkExe.Checked
        AutoUpdate      = [bool]$ChkUpdate.Checked
        ForceMinimal    = [bool]$ChkMinLay.Checked
        PauseSpeed      = [int]$NumPause.Value
        MaxChunks       = [int]$NumChunks.Value
        MaxPerHost      = [int]$NumPerHost.Value
        HashCheck       = [bool]$ChkHashCheck.Checked
        PreserveFileDate= [bool]$ChkPreserveDate.Checked
        ClipboardMonitor= [bool]$ChkClipboard.Checked
        DisableLocalAPI = [bool]$ChkDisableAPI.Checked
        WriteVmOptions  = [bool]$ChkVmOptions.Checked
    }
}

function Get-NormalizedStateObject {
    param($State)
    if (-not $State) { return $null }

    $mode = if ([string]$State.Mode -eq "Install") { "Install" } else { "Modify" }
    $installSource = ""
    if ($mode -eq "Install") {
        $installSource = if ([string]$State.InstallSource -eq "Mega") { "Mega" } else { "GitHub" }
    }

    $languageCode = [string]$State.LanguageCode
    if ([string]::IsNullOrWhiteSpace($languageCode)) { $languageCode = $CurrentLangCode }

    # Parse numerics safely - a hand-edited JSON with "MaxSim": "three" should not throw here.
    $toInt = {
        param($v, [int]$default = 0)
        if ($null -eq $v) { return $default }
        $parsed = 0
        if ([int]::TryParse(([string]$v).Trim(), [ref]$parsed)) { return $parsed } else { return $default }
    }

    return [ordered]@{
        Mode            = $mode
        InstallSource   = $installSource
        InstallPath     = ([string]$State.InstallPath).Trim()
        ThemeName       = [string]$State.ThemeName
        GuiThemeName    = [string]$State.GuiThemeName
        LanguageCode    = $languageCode
        IconPack        = [string]$State.IconPack
        WindowDec       = ConvertTo-SafeBool $State.WindowDec    $true
        MaxSim          = & $toInt $State.MaxSim 3
        DlFolder        = ([string]$State.DlFolder).Trim()
        StartMin        = ConvertTo-SafeBool $State.StartMin     $false
        MinToTray       = ConvertTo-SafeBool $State.MinToTray    $true
        CloseToTray     = ConvertTo-SafeBool $State.CloseToTray  $true
        PatchExe        = ConvertTo-SafeBool $State.PatchExe     $true
        AutoUpdate      = ConvertTo-SafeBool $State.AutoUpdate   $true
        ForceMinimal    = ConvertTo-SafeBool $State.ForceMinimal $false
        PauseSpeed      = & $toInt $State.PauseSpeed 10240
        MaxChunks       = if (Test-StateHas $State "MaxChunks")       { & $toInt $State.MaxChunks 1 }       else { 1 }
        MaxPerHost      = if (Test-StateHas $State "MaxPerHost")      { & $toInt $State.MaxPerHost 1 }      else { 1 }
        HashCheck       = if (Test-StateHas $State "HashCheck")        { ConvertTo-SafeBool $State.HashCheck        $true }  else { $true }
        PreserveFileDate= if (Test-StateHas $State "PreserveFileDate") { ConvertTo-SafeBool $State.PreserveFileDate $false } else { $false }
        ClipboardMonitor= if (Test-StateHas $State "ClipboardMonitor") { ConvertTo-SafeBool $State.ClipboardMonitor $true }  else { $true }
        DisableLocalAPI = if (Test-StateHas $State "DisableLocalAPI")  { ConvertTo-SafeBool $State.DisableLocalAPI  $true }  else { $true }
        WriteVmOptions  = if (Test-StateHas $State "WriteVmOptions")   { ConvertTo-SafeBool $State.WriteVmOptions   $false } else { $false }
    }
}

function Get-DefaultWorkspaceState {
    $detected = Detect-JDPath
    $mode = if ($detected) { "Modify" } else { "Install" }
    return [ordered]@{
        Mode            = $mode
        InstallSource   = if ($mode -eq "Install") { "GitHub" } else { "" }
        InstallPath     = if ($detected) { $detected } else { "" }
        ThemeName       = "Flat Dark"
        GuiThemeName    = "Dark (Default)"
        LanguageCode    = $CurrentLangCode
        IconPack        = "Default"
        WindowDec       = $true
        MaxSim          = 3
        DlFolder        = ""
        StartMin        = $false
        MinToTray       = $true
        CloseToTray     = $true
        PatchExe        = $true
        AutoUpdate      = $true
        ForceMinimal    = $false
        PauseSpeed      = 10240
        MaxChunks       = 1
        MaxPerHost      = 1
        HashCheck       = $true
        PreserveFileDate= $false
        ClipboardMonitor= $true
        DisableLocalAPI = $true
        WriteVmOptions  = $false
    }
}

function Read-PresetFile {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path)) {
        Log-Status "Preset file not found: $Path" "ERROR"
        return $null
    }
    try {
        $file = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($file.Length -gt 1MB) {
            Log-Status "Preset file is too large; refusing to load: $Path" "ERROR"
            return $null
        }
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Log-Status "Preset file is empty: $Path" "ERROR"
            return $null
        }
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
        return Get-NormalizedStateObject -State $data
    } catch {
        Log-Status "Preset file could not be loaded: $_" "ERROR"
        return $null
    }
}

function Save-PresetFile {
    param($State, [string]$Path)
    if (-not $State -or [string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        $normalized = Get-NormalizedStateObject -State $State
        $targetDir = Split-Path -Parent $Path
        if (-not [string]::IsNullOrWhiteSpace($targetDir) -and -not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        $payload = [ordered]@{
            AppName   = $script:AppName
            Version   = $script:AppVersion
            Exported  = (Get-Date).ToString("o")
            Workspace = $normalized
        }
        $tmp = "$Path.tmp"
        $payload.Workspace | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmp -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $tmp -Destination $Path -Force -ErrorAction Stop
        Log-Status "Preset exported to $Path." "SUCCESS"
        return $true
    } catch {
        Log-Status "Preset export failed: $_" "ERROR"
        try { Remove-Item -LiteralPath "$Path.tmp" -Force -ErrorAction SilentlyContinue } catch {}
        return $false
    }
}

function Start-SilentWorkspace {
    $state = $null
    if ($script:PresetPath) {
        $state = Read-PresetFile -Path $script:PresetPath
        if (-not $state) { return 3 }
    }
    if (-not $state) { $state = Load-Settings }
    if (-not $state) { $state = Get-DefaultWorkspaceState }
    $state = Get-NormalizedStateObject -State $state

    if ($script:ExportPresetPath) {
        if (Save-PresetFile -State $state -Path $script:ExportPresetPath) { return 0 }
        return 4
    }

    if (-not $script:IsElevated) {
        Log-Status "Silent mode requires an elevated PowerShell session. No changes were written." "ERROR"
        return 5
    }

    $script:SilentMode = $true
    $script:ApplyInFlight = $true
    $script:InitialWorkspaceState = $state
    $script:SavedWorkspaceState = $state
    $script:ProgressShim = [pscustomobject]@{
        Value = 0
        Style = "Continuous"
        MarqueeAnimationSpeed = 0
    }
    Set-Variable -Name ProgressBar -Value $script:ProgressShim -Scope Script
    if (Execute-Operations -GUI_State $state) { return 0 }
    return 1
}

if ($script:SilentMode -or $script:ExportPresetPath) {
    $exitCode = Start-SilentWorkspace
    [Environment]::Exit($exitCode)
}

function Get-LastAppliedDisplayText {
    $sourcePath = Get-SettingsSourcePath
    if (Test-Path $sourcePath) {
        return "Last applied: {0}" -f ((Get-Item $sourcePath).LastWriteTime.ToString("MMM d, yyyy h:mm tt"))
    }
    return "Last applied: Not yet"
}

function Join-ReadableList {
    param([string[]]$Items)
    if (-not $Items -or $Items.Count -eq 0) { return "" }
    if ($Items.Count -eq 1) { return $Items[0] }
    if ($Items.Count -eq 2) { return "$($Items[0]) and $($Items[1])" }
    return "{0}, and {1}" -f (($Items[0..($Items.Count - 2)] -join ", ")), $Items[-1]
}

function Get-ChangedWorkspaceAreas {
    param($SavedState, $CurrentState)
    if (-not $SavedState -or -not $CurrentState) { return @() }

    $areaMap = [ordered]@{
        "installation setup"   = @("Mode", "InstallSource", "InstallPath")
        "appearance"           = @("ThemeName", "IconPack", "WindowDec", "ForceMinimal")
        "download behavior"    = @("MaxSim", "DlFolder", "PauseSpeed", "StartMin", "MinToTray", "CloseToTray", "MaxChunks", "MaxPerHost", "HashCheck", "PreserveFileDate", "ClipboardMonitor")
        "hardening"            = @("PatchExe", "AutoUpdate", "DisableLocalAPI", "WriteVmOptions")
        "workspace preferences"= @("GuiThemeName", "LanguageCode")
    }

    $changedAreas = New-Object System.Collections.Generic.List[string]
    foreach ($area in $areaMap.Keys) {
        foreach ($key in $areaMap[$area]) {
            if ($SavedState[$key] -ne $CurrentState[$key]) {
                $changedAreas.Add($area)
                break
            }
        }
    }

    return $changedAreas.ToArray()
}

function Get-WorkspaceComparisonBaseline {
    if ($script:SavedWorkspaceState) { return $script:SavedWorkspaceState }
    return $script:InitialWorkspaceState
}

function Update-WorkspaceState {
    if ($script:IsBootstrapping) { return }
    if (-not $FooterSummary -or -not $FooterStateBadge -or -not $DashPrefsStateValue -or -not $DashPrefsStateDetail -or -not $DashLastAppliedValue -or -not $BtnRestoreWorkspace) { return }

    $palette = Get-ActivePalette
    $currentState = Get-NormalizedStateObject -State (Get-CurrentGuiState)
    $lastAppliedText = Get-LastAppliedDisplayText
    $DashLastAppliedValue.Text = $lastAppliedText
    $baselineState = Get-WorkspaceComparisonBaseline

    if (-not $script:SavedWorkspaceState) {
        $BtnRestoreWorkspace.Enabled = $false
        $BtnRestoreWorkspace.Text = "Available after first run"
        $changedAreas = @(Get-ChangedWorkspaceAreas -SavedState $baselineState -CurrentState $currentState)
        if ($changedAreas.Count -eq 0) {
            $FooterSummary.Text = "First run ready. Review the pages, then apply once to save this workspace."
            Set-BadgeState -Badge $FooterStateBadge -Text "First run" -State "Accent"
            $DashPrefsStateValue.Text = "No saved workspace yet"
            $DashPrefsStateValue.ForeColor = $palette.Accent
            $DashPrefsStateDetail.Text = "Your selected path, theme, language, and run options will be remembered after the first successful run."
        } else {
            $suffix = if ($changedAreas.Count -eq 1) { "" } else { "s" }
            $FooterSummary.Text = "First run configured in {0} area{1}. Apply once to save this workspace." -f $changedAreas.Count, $suffix
            Set-BadgeState -Badge $FooterStateBadge -Text "Pending setup" -State "Warning"
            $DashPrefsStateValue.Text = "Ready to save first run"
            $DashPrefsStateValue.ForeColor = $palette.Warning
            $DashPrefsStateDetail.Text = "Adjusted since launch: {0}. Apply once to make this workspace the new default." -f (Join-ReadableList -Items $changedAreas)
        }
        Layout-Footer
        return
    }

    $changedAreas = @(Get-ChangedWorkspaceAreas -SavedState $baselineState -CurrentState $currentState)
    if ($changedAreas.Count -eq 0) {
        $BtnRestoreWorkspace.Enabled = $false
        $BtnRestoreWorkspace.Text = "Already current"
        $FooterSummary.Text = "Workspace matches the last successful run."
        Set-BadgeState -Badge $FooterStateBadge -Text "Ready" -State "Success"
        $DashPrefsStateValue.Text = "Everything is in sync"
        $DashPrefsStateValue.ForeColor = $palette.Success
        $DashPrefsStateDetail.Text = "The current workspace already matches the last applied run."
        Layout-Footer
        return
    }

    $BtnRestoreWorkspace.Enabled = $true
    $BtnRestoreWorkspace.Text = "Restore last run"
    $suffix = if ($changedAreas.Count -eq 1) { "" } else { "s" }
    $FooterSummary.Text = "Changes pending in {0} area{1}. Apply when you're ready." -f $changedAreas.Count, $suffix
    Set-BadgeState -Badge $FooterStateBadge -Text "Pending changes" -State "Warning"
    $DashPrefsStateValue.Text = "Changes pending"
    $DashPrefsStateValue.ForeColor = $palette.Warning
    $DashPrefsStateDetail.Text = "Updated since the last successful run: {0}." -f (Join-ReadableList -Items $changedAreas)
    Layout-Footer
}

function Test-WorkspaceHasPendingChanges {
    $baselineState = Get-WorkspaceComparisonBaseline
    if (-not $baselineState) { return $false }
    $currentState = Get-NormalizedStateObject -State (Get-CurrentGuiState)
    return (@(Get-ChangedWorkspaceAreas -SavedState $baselineState -CurrentState $currentState).Count -gt 0)
}

function Apply-AccessibilityMetadata {
    Set-ControlMetadata -Control $BtnDashboard    -Name "Dashboard navigation"    -Description "Open the dashboard overview page." -TabIndex 0
    Set-ControlMetadata -Control $BtnLiveControl  -Name "Live control navigation"  -Description "Open the live JDownloader queue and LinkGrabber controls." -TabIndex 1
    Set-ControlMetadata -Control $BtnInstallation -Name "Installation navigation" -Description "Open installation mode and path settings." -TabIndex 1
    Set-ControlMetadata -Control $BtnTheme        -Name "Themes navigation"       -Description "Open theme and icon customization options." -TabIndex 2
    Set-ControlMetadata -Control $BtnBehavior     -Name "Behavior navigation"     -Description "Open download and window behavior settings." -TabIndex 3
    Set-ControlMetadata -Control $BtnHardening    -Name "Hardening navigation"    -Description "Open the debloat and hardening options page." -TabIndex 4
    Set-ControlMetadata -Control $BtnRepair       -Name "Repair navigation"       -Description "Open maintenance and recovery tools." -TabIndex 5

    Set-ControlMetadata -Control $CboGuiTheme -Name "Workspace theme" -Description "Choose the visual theme for this manager window." -TabIndex 0
    Set-ControlMetadata -Control $CboLang     -Name "Workspace language" -Description "Choose the language used inside this manager window." -TabIndex 1
    Set-ControlMetadata -Control $BtnImportPreset -Name "Import preset" -Description "Load workspace selections from a JSON preset file." -TabIndex 2
    Set-ControlMetadata -Control $BtnExportPreset -Name "Export preset" -Description "Save current workspace selections to a JSON preset file." -TabIndex 3
    Set-ControlMetadata -Control $BtnDashInstallJump -Name "Open installation from dashboard" -Description "Jump directly to installation path and mode settings." -TabIndex 4
    Set-ControlMetadata -Control $BtnDashThemeJump   -Name "Open themes from dashboard" -Description "Jump directly to theme previews and icon options." -TabIndex 5
    Set-ControlMetadata -Control $BtnDashRepairJump  -Name "Open repair tools from dashboard" -Description "Jump directly to maintenance and recovery tools." -TabIndex 6
    Set-ControlMetadata -Control $TxtPath     -Name "JDownloader installation folder" -Description "Enter the folder for the JDownloader installation you want to modify, or leave it blank in clean install mode." -TabIndex 0
    Set-ControlMetadata -Control $BtnBrowse   -Name "Browse for installation folder" -Description "Open a folder picker for the JDownloader installation folder." -TabIndex 1
    Set-ControlMetadata -Control $BtnDetect   -Name "Auto-detect installation folder" -Description "Try to locate the current JDownloader installation automatically." -TabIndex 2
    Set-ControlMetadata -Control $CboMode     -Name "Installation mode" -Description "Choose whether to modify an existing install or run a clean install flow." -TabIndex 0

    Set-ControlMetadata -Control $CboTheme     -Name "Theme preset" -Description "Choose the theme preset that will be applied to JDownloader." -TabIndex 0
    Set-ControlMetadata -Control $LblThemeLink -Name "Open theme project" -Description "Open the selected theme's GitHub page in your browser." -TabIndex 1
    Set-ControlMetadata -Control $CboIcons     -Name "Icon pack" -Description "Choose the icon pack that should be layered onto the selected theme." -TabIndex 0
    Set-ControlMetadata -Control $ChkWinDec    -Name "Custom window decorations" -Description "Enable custom window decorations when the theme supports them." -TabIndex 1
    Set-ControlMetadata -Control $ChkMinLay    -Name "Compact main tabs" -Description "Use a tighter main tab layout inside JDownloader." -TabIndex 2
    Set-ControlMetadata -Control $BtnOpenThm   -Name "Open icon folder" -Description "Open the active JDownloader icon folder on disk." -TabIndex 3

    Set-ControlMetadata -Control $NumSim       -Name "Max simultaneous downloads" -Description "Choose the number of downloads that can run at the same time." -TabIndex 0
    Set-ControlMetadata -Control $NumPause     -Name "Pause speed" -Description "Choose the speed threshold used for the pause behavior." -TabIndex 1
    Set-ControlMetadata -Control $TxtDl        -Name "Default download folder" -Description "Enter a download folder or leave it blank to reset to JDownloader's default folder." -TabIndex 2
    Set-ControlMetadata -Control $BtnDl        -Name "Browse for download folder" -Description "Open a folder picker for the default download location." -TabIndex 3
    Set-ControlMetadata -Control $ChkMin       -Name "Start minimized" -Description "Launch JDownloader in a minimized state." -TabIndex 0
    Set-ControlMetadata -Control $ChkTray      -Name "Minimize to tray" -Description "Send JDownloader to the system tray when minimized." -TabIndex 1
    Set-ControlMetadata -Control $ChkCloseTray -Name "Close to tray" -Description "Send JDownloader to the system tray when the close button is used." -TabIndex 2

    Set-ControlMetadata -Control $NumChunks     -Name "Chunks per file" -Description "Number of parallel segments per download. Increase for premium hosts." -TabIndex 3
    Set-ControlMetadata -Control $NumPerHost    -Name "Per-host download limit" -Description "Max simultaneous downloads from any single host." -TabIndex 4
    Set-ControlMetadata -Control $ChkHashCheck  -Name "Hash check" -Description "Verify file integrity after download completes." -TabIndex 5
    Set-ControlMetadata -Control $ChkPreserveDate -Name "Preserve file dates" -Description "Keep the original file modification timestamp from the server." -TabIndex 6
    Set-ControlMetadata -Control $ChkClipboard  -Name "Clipboard monitoring" -Description "Automatically detect download links copied to clipboard." -TabIndex 7
    Set-ControlMetadata -Control $ChkExe       -Name "Apply dark executable icon" -Description "Replace the executable icon with the darker icon variant." -TabIndex 0
    Set-ControlMetadata -Control $ChkUpdate    -Name "Run update after completion" -Description "Launch JDownloader's update routine after the selected work finishes." -TabIndex 1
    Set-ControlMetadata -Control $ChkDisableAPI -Name "Disable deprecated local API" -Description "Block the legacy unauthenticated REST API on port 3128." -TabIndex 2
    Set-ControlMetadata -Control $ChkVmOptions  -Name "Write JVM options file" -Description "Create JDownloader2.vmoptions with performance flags." -TabIndex 3

    Set-ControlMetadata -Control $RepairResetCfg.Button   -Name "Reset configuration" -Description "Back up and remove the full configuration folder." -TabIndex 0
    Set-ControlMetadata -Control $RepairResetTheme.Button -Name "Reset theme assets" -Description "Remove the current theme override files and icon assets." -TabIndex 0
    Set-ControlMetadata -Control $RepairClearCache.Button -Name "Clear cache" -Description "Delete temporary cache files and leftover logs." -TabIndex 0
    Set-ControlMetadata -Control $RepairAudit.Button      -Name "Run health audit" -Description "Check the installation for missing or damaged configuration files." -TabIndex 0
    Set-ControlMetadata -Control $RepairSafe.Button       -Name "Launch safe mode" -Description "Start JDownloader in safe mode for troubleshooting." -TabIndex 0
    Set-ControlMetadata -Control $RepairUninstall.Button  -Name "Full uninstall" -Description "Remove JDownloader from the selected install folder." -TabIndex 0

    Set-ControlMetadata -Control $BtnExec      -Name "Apply selected changes" -Description "Run the selected installation, theme, behavior, hardening, and repair operations." -TabIndex 0
    Set-ControlMetadata -Control $BtnRestoreWorkspace -Name "Restore last run" -Description "Restore the last successful workspace selections and discard pending edits." -TabIndex 2
    Set-ControlMetadata -Control $FooterStateBadge -Name "Workspace readiness" -Description "Shows whether the current workspace is ready, pending, or actively applying changes."
    Set-ControlMetadata -Control $ProgressBar  -Name "Operation progress" -Description "Shows progress while selected changes are being applied."
    Set-ControlMetadata -Control $StatusLabel  -Name "Status updates" -Description "Shows the latest status and completion messages."
    Set-ControlMetadata -Control $DashLastAppliedValue -Name "Last successful run" -Description "Shows when the last successful apply run completed."
    Set-ControlMetadata -Control $DashPrefsStateValue -Name "Workspace status" -Description "Shows whether the current selections match the last successful run."
    Set-ControlMetadata -Control $ThemePreviewBadge -Name "Theme preview status" -Description "Shows whether the selected theme preview is ready, loading, or unavailable."
    Set-ControlMetadata -Control $BehProfileBadge -Name "Behavior profile summary" -Description "Summarizes the current download and window behavior profile."
    Set-ControlMetadata -Control $InstallBadge -Name "Installation readiness" -Description "Shows whether the selected installation path and mode are ready."
    Set-ControlMetadata -Control $TxtLiveEndpoint -Name "JDownloader API endpoint" -Description "Enter the local or remote HTTP endpoint for JDownloader's JSON API." -TabIndex 0
    Set-ControlMetadata -Control $BtnLiveConnect -Name "Connect to JDownloader" -Description "Connect to the configured JDownloader API endpoint." -TabIndex 1
    Set-ControlMetadata -Control $BtnLiveRefresh -Name "Refresh live queue" -Description "Reload the current JDownloader download queue." -TabIndex 2
    Set-ControlMetadata -Control $BtnLiveStart -Name "Start downloads" -Description "Start JDownloader's download controller." -TabIndex 3
    Set-ControlMetadata -Control $BtnLivePause -Name "Pause downloads" -Description "Pause JDownloader downloads." -TabIndex 4
    Set-ControlMetadata -Control $BtnLiveStop -Name "Stop downloads" -Description "Stop JDownloader's download controller." -TabIndex 5
    Set-ControlMetadata -Control $BtnLiveGrabberRefresh -Name "Refresh LinkGrabber" -Description "Reload the current LinkGrabber package and link counts." -TabIndex 6
    Set-ControlMetadata -Control $TxtLiveLinks -Name "Links for LinkGrabber" -Description "Paste one or more URLs to send to JDownloader LinkGrabber." -TabIndex 7
    Set-ControlMetadata -Control $TxtLivePackage -Name "LinkGrabber package name" -Description "Optional package name for the links sent to LinkGrabber." -TabIndex 8
    Set-ControlMetadata -Control $BtnLiveAddLinks -Name "Send links to LinkGrabber" -Description "Forward the pasted URLs to JDownloader LinkGrabber." -TabIndex 9
    Set-ControlMetadata -Control $LiveQueueGrid -Name "JDownloader download queue" -Description "Shows current links, status, progress, speed, and estimated time." -TabIndex 10
    Set-ControlMetadata -Control $TxtLiveCaptchaAnswer -Name "Captcha answer" -Description "Enter the answer for the pending JDownloader captcha prompt." -TabIndex 11
    Set-ControlMetadata -Control $BtnLiveCaptchaSolve -Name "Submit captcha answer" -Description "Submit the captcha answer to JDownloader." -TabIndex 12
    Set-ControlMetadata -Control $BtnLiveCaptchaSkip -Name "Skip captcha" -Description "Skip the current JDownloader captcha prompt." -TabIndex 13
    Set-ControlMetadata -Control $BtnLiveCaptchaRefresh -Name "Refresh captcha prompts" -Description "Refresh the pending JDownloader captcha prompt." -TabIndex 14
}

# --- Themes Page ---
$ThemeHeader = New-Surface -Parent $ThemeCanvas -Location (New-Object System.Drawing.Point(0, 0)) -Size (New-Object System.Drawing.Size(1040, 148))
$ThemeTitle = New-Label -Parent $ThemeHeader -LangKey "ThemeTitle" -Location (New-Object System.Drawing.Point(24, 22)) -Tag "SectionHeader"
$ThemeSub = New-Label -Parent $ThemeHeader -LangKey "ThemeSub" -Location (New-Object System.Drawing.Point(24, 58)) -Size (New-Object System.Drawing.Size(600, 44)) -AutoSize $false -Tag "SubHeader"
$LblThm = New-Label -Parent $ThemeHeader -LangKey "ThemePreset" -Location (New-Object System.Drawing.Point(24, 112))
$CboTheme = New-ComboBox -Parent $ThemeHeader -Location (New-Object System.Drawing.Point(148, 108)) -Size (New-Object System.Drawing.Size(280, 36)) -Tag "Input" -Items $ThemeDefinitions.Keys
$LblPreDesc = New-Label -Parent $ThemeHeader -Text "" -Location (New-Object System.Drawing.Point(454, 110)) -Size (New-Object System.Drawing.Size(380, 34)) -AutoSize $false -Tag "BodyMuted"
$LblThemeLink = New-Object System.Windows.Forms.LinkLabel
$LblThemeLink.Location = New-Object System.Drawing.Point(856, 114)
$LblThemeLink.AutoSize = $true
$LblThemeLink.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Underline)
[void]$ThemeHeader.Controls.Add($LblThemeLink)
Register-LangControl -Control $LblThemeLink -Key "OpenGithub"

$PnlPreview = New-Surface -Name "PnlPreview" -Parent $ThemeCanvas -Location (New-Object System.Drawing.Point(0, 172)) -Size (New-Object System.Drawing.Size(658, 488)) -Tag "PreviewPanel"
$ThemePreviewBadge = New-Badge -Parent $PnlPreview -Text "Loading preview" -Location (New-Object System.Drawing.Point(490, 24)) -Size (New-Object System.Drawing.Size(120, 28)) -Tag "BadgeAccent"
$PicThemePreview = New-Object System.Windows.Forms.PictureBox
$PicThemePreview.Location = New-Object System.Drawing.Point(24, 24)
$PicThemePreview.Size = New-Object System.Drawing.Size(610, 440)
$PicThemePreview.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
[void]$PnlPreview.Controls.Add($PicThemePreview)
$LblPreviewState = New-Label -Parent $PnlPreview -Text "Preview is loading in the background." -Location (New-Object System.Drawing.Point(48, 214)) -Size (New-Object System.Drawing.Size(562, 42)) -AutoSize $false -Tag "BodyMuted"
$LblPreviewState.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$ThemePreviewBadge.BringToFront()

$ThemeOptions = New-Surface -Parent $ThemeCanvas -Location (New-Object System.Drawing.Point(680, 172)) -Size (New-Object System.Drawing.Size(360, 488)) -Tag "SurfaceAlt"
[void](New-Label -Parent $ThemeOptions -Text "Appearance options" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $ThemeOptions -Text "Choose the supporting icon pack and decide how minimal you want the final JDownloader shell to feel." -Location (New-Object System.Drawing.Point(24, 52)) -Size (New-Object System.Drawing.Size(312, 52)) -AutoSize $false -Tag "BodyMuted")
$LblIco = New-Label -Parent $ThemeOptions -LangKey "IconPack" -Location (New-Object System.Drawing.Point(24, 126))
$CboIcons = New-ComboBox -Parent $ThemeOptions -Location (New-Object System.Drawing.Point(24, 154)) -Size (New-Object System.Drawing.Size(312, 36)) -Tag "Input" -Items $IconDefinitions.Keys
$ChkWinDec = New-CheckBox -Parent $ThemeOptions -LangKey "EnableWinDec" -Location (New-Object System.Drawing.Point(24, 220)) -Checked $true
$ChkMinLay = New-CheckBox -Parent $ThemeOptions -LangKey "CompactTabs" -Location (New-Object System.Drawing.Point(24, 258))
[void](New-Label -Parent $ThemeOptions -Text "Theme previews can keep loading while you continue configuring the rest of the tool." -Location (New-Object System.Drawing.Point(24, 298)) -Size (New-Object System.Drawing.Size(312, 36)) -AutoSize $false -Tag "BodyMuted")
$BtnOpenThm = New-Button -Parent $ThemeOptions -LangKey "OpenIconFolder" -Location (New-Object System.Drawing.Point(24, 352)) -Size (New-Object System.Drawing.Size(220, 36)) -Tag "SecondaryButton"
$ThemeSelectionCallout = New-Surface -Parent $ThemeOptions -Location (New-Object System.Drawing.Point(24, 388)) -Size (New-Object System.Drawing.Size(312, 88)) -Tag "Callout"
[void](New-Label -Parent $ThemeSelectionCallout -Text "Current preset" -Location (New-Object System.Drawing.Point(18, 12)) -Font (New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
$ThemeSelectionValue = New-Label -Parent $ThemeSelectionCallout -Text "Choose a theme preset" -Location (New-Object System.Drawing.Point(18, 30)) -Size (New-Object System.Drawing.Size(276, 20)) -AutoSize $false -Tag "MutedStrong"
$ThemeSelectionDetail = New-Label -Parent $ThemeSelectionCallout -Text "Icon pack, window decorations, and compact tabs update live." -Location (New-Object System.Drawing.Point(18, 54)) -Size (New-Object System.Drawing.Size(276, 22)) -AutoSize $false -Tag "BodyMuted"

function Resize-ThemePreview {
    if (-not $PnlPreview) { return }
    $PicThemePreview.Size = New-Object System.Drawing.Size([Math]::Max(120, $PnlPreview.Width - 48), [Math]::Max(120, $PnlPreview.Height - 48))
    $LblPreviewState.Location = New-Object System.Drawing.Point(36, [Math]::Max(80, [int](($PnlPreview.Height - $LblPreviewState.Height) / 2)))
    $LblPreviewState.Size = New-Object System.Drawing.Size([Math]::Max(160, $PnlPreview.Width - 72), 42)
    if ($ThemePreviewBadge) {
        $ThemePreviewBadge.Location = New-Object System.Drawing.Point([Math]::Max(24, $PnlPreview.Width - $ThemePreviewBadge.Width - 24), 24)
        $ThemePreviewBadge.BringToFront()
    }
}

function Update-ThemeSelectionSummary {
    if (-not $ThemeSelectionDetail -or -not $CboIcons -or -not $ChkWinDec -or -not $ChkMinLay) { return }

    $iconNote = if ([string]::IsNullOrWhiteSpace($CboIcons.Text) -or $CboIcons.Text -eq "None") {
        "No icon pack layered."
    } else {
        "Icons: {0}." -f $CboIcons.Text
    }
    $windowNote = if ($ChkWinDec.Checked) { "Window decorations on." } else { "Window decorations off." }
    $densityNote = if ($ChkMinLay.Checked) { "Compact tabs on." } else { "Standard tabs on." }
    $ThemeSelectionDetail.Text = "{0} {1} {2}" -f $iconNote, $windowNote, $densityNote
}

function Update-ThemePreview {
    $selection = $ThemeDefinitions[$CboTheme.Text]
    if (-not $selection) { return }
    $LblPreDesc.Text = $selection.Desc
    $LblThemeLink.Tag = $selection.ThemeUrl
    if ($ThemeSelectionValue) { $ThemeSelectionValue.Text = $selection.DisplayName }
    Update-ThemeSelectionSummary
    if ($ThemeImageCache.ContainsKey($CboTheme.Text) -and $ThemeImageCache[$CboTheme.Text]) {
        $PicThemePreview.Image = $ThemeImageCache[$CboTheme.Text]
        $LblPreviewState.Visible = $false
        Set-BadgeState -Badge $ThemePreviewBadge -Text "Preview ready" -State "Success"
    } else {
        $PicThemePreview.Image = $null
        if ($selection.PreviewUrl) {
            $LblPreviewState.Text = "Preview is still loading. You can keep configuring icons and layout options in the meantime."
            Set-BadgeState -Badge $ThemePreviewBadge -Text "Loading preview" -State "Accent"
        } else {
            $LblPreviewState.Text = "No preview is available for this theme yet."
            Set-BadgeState -Badge $ThemePreviewBadge -Text "Preview unavailable" -State "Neutral"
        }
        $LblPreviewState.Visible = $true
    }
    if ($ThemePreviewBadge) { $ThemePreviewBadge.BringToFront() }
}

function Update-BehaviorProfile {
    if (-not $BehProfileBadge -or -not $BehProfileDetail -or -not $NumSim -or -not $NumPause -or -not $TxtDl -or -not $ChkMin -or -not $ChkTray -or -not $ChkCloseTray) { return }

    $simultaneous = [int]$NumSim.Value
    $pauseSpeed = [int]$NumPause.Value
    if ($simultaneous -le 2) {
        $profileName = "Conservative profile"
        $profileState = "Neutral"
        $throughputNote = "Lower concurrency keeps bandwidth predictable."
    } elseif ($simultaneous -le 5) {
        $profileName = "Balanced profile"
        $profileState = "Success"
        $throughputNote = "Good default for most setups."
    } else {
        $profileName = "High-throughput profile"
        $profileState = "Warning"
        $throughputNote = "High concurrency favors bursts over calmness."
    }

    $pauseNote = if ($pauseSpeed -eq 0) {
        "Pause speed is disabled."
    } elseif ($pauseSpeed -le 10240) {
        "Pause speed acts like a near stop."
    } else {
        "Pause speed still allows some residual traffic."
    }

    $folderValue = $TxtDl.Text.Trim()
    $folderNote = if ([string]::IsNullOrWhiteSpace($folderValue)) {
        "Downloads stay on JDownloader's default folder."
    } elseif (Test-Path $folderValue) {
        "Custom download folder is ready."
    } else {
        "Custom download folder will be created when needed."
    }

    $windowNote = if ($ChkCloseTray.Checked -and $ChkTray.Checked) {
        "Close still routes to the tray."
    } elseif ($ChkTray.Checked) {
        "Minimize still routes to the tray."
    } elseif ($ChkMin.Checked) {
        "Starts minimized without tray routing."
    } else {
        "Window behavior stays explicit."
    }

    Set-BadgeState -Badge $BehProfileBadge -Text $profileName -State $profileState
    $BehProfileDetail.Text = "{0} {1} {2} {3}" -f $throughputNote, $pauseNote, $folderNote, $windowNote
}

# --- Behavior Page ---
$BehHero = New-Surface -Parent $BehaviorCanvas -Location (New-Object System.Drawing.Point(0, 0)) -Size (New-Object System.Drawing.Size(1040, 156))
$BehTitle = New-Label -Parent $BehHero -LangKey "BehTitle" -Location (New-Object System.Drawing.Point(24, 24)) -Tag "SectionHeader"
$BehSub = New-Label -Parent $BehHero -LangKey "BehSub" -Location (New-Object System.Drawing.Point(24, 60)) -Size (New-Object System.Drawing.Size(690, 40)) -AutoSize $false -Tag "SubHeader"
$BehProfileBadge = New-Badge -Parent $BehHero -Text "Balanced profile" -Location (New-Object System.Drawing.Point(780, 28)) -Size (New-Object System.Drawing.Size(174, 28)) -Tag "BadgeSuccess"
$BehProfileDetail = New-Label -Parent $BehHero -Text "Good default for most setups. Speed, pause, folder, and tray behavior still update live." -Location (New-Object System.Drawing.Point(780, 64)) -Size (New-Object System.Drawing.Size(214, 78)) -AutoSize $false -Tag "BodyMuted"

$BehMain = New-Surface -Parent $BehaviorCanvas -Location (New-Object System.Drawing.Point(0, 180)) -Size (New-Object System.Drawing.Size(640, 344))
[void](New-Label -Parent $BehMain -Text "Download defaults" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)))
$LblSim = New-Label -Parent $BehMain -LangKey "MaxSim" -Location (New-Object System.Drawing.Point(24, 74))
$NumSim = New-NumericUpDown -Parent $BehMain -Location (New-Object System.Drawing.Point(412, 70)) -Min 1 -Max 20 -Value 3 -Tag "Input"
$LblSimHelp = New-Label -Parent $BehMain -LangKey "MaxSimHelp" -Location (New-Object System.Drawing.Point(24, 100)) -Size (New-Object System.Drawing.Size(520, 34)) -AutoSize $false -Tag "BodyMuted"
$LblPau = New-Label -Parent $BehMain -LangKey "PauseSpeed" -Location (New-Object System.Drawing.Point(24, 150))
$NumPause = New-NumericUpDown -Parent $BehMain -Location (New-Object System.Drawing.Point(412, 146)) -Min 0 -Max 1000000 -Value 10240 -Tag "Input"
$LblPauHelp = New-Label -Parent $BehMain -LangKey "PauseHelp" -Location (New-Object System.Drawing.Point(24, 176)) -Size (New-Object System.Drawing.Size(520, 34)) -AutoSize $false -Tag "BodyMuted"
$LblDl = New-Label -Parent $BehMain -LangKey "DefDlFolder" -Location (New-Object System.Drawing.Point(24, 228))
$TxtDl = New-TextBox -Parent $BehMain -Location (New-Object System.Drawing.Point(24, 256)) -Size (New-Object System.Drawing.Size(476, 36)) -Tag "Input"
$BtnDl = New-Button -Parent $BehMain -LangKey "Browse" -Location (New-Object System.Drawing.Point(512, 256)) -Size (New-Object System.Drawing.Size(104, 34)) -Tag "SecondaryButton"
$LblDownloadState = New-Label -Parent $BehMain -Text "This folder becomes the new default location for downloads." -Location (New-Object System.Drawing.Point(24, 298)) -Size (New-Object System.Drawing.Size(592, 24)) -AutoSize $false -Tag "BodyMuted"

$BehTray = New-Surface -Parent $BehaviorCanvas -Location (New-Object System.Drawing.Point(662, 180)) -Size (New-Object System.Drawing.Size(378, 344)) -Tag "SurfaceAlt"
[void](New-Label -Parent $BehTray -Text "Window behavior" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $BehTray -Text "Keep the app available without interrupting your desktop workflow." -Location (New-Object System.Drawing.Point(24, 50)) -Size (New-Object System.Drawing.Size(320, 34)) -AutoSize $false -Tag "BodyMuted")
$ChkMin = New-CheckBox -Parent $BehTray -LangKey "StartMin" -Location (New-Object System.Drawing.Point(24, 106))
$ChkTray = New-CheckBox -Parent $BehTray -LangKey "MinToTray" -Location (New-Object System.Drawing.Point(24, 144)) -Checked $true
$ChkCloseTray = New-CheckBox -Parent $BehTray -LangKey "CloseToTray" -Location (New-Object System.Drawing.Point(24, 182)) -Checked $true
[void](New-Label -Parent $BehTray -Text "Recommended: keep tray behavior enabled if JDownloader runs in the background most of the time." -Location (New-Object System.Drawing.Point(24, 232)) -Size (New-Object System.Drawing.Size(320, 50)) -AutoSize $false -Tag "BodyMuted")

# --- Advanced download tuning ---
$BehAdvanced = New-Surface -Parent $BehaviorCanvas -Location (New-Object System.Drawing.Point(0, 548)) -Size (New-Object System.Drawing.Size(640, 168))
[void](New-Label -Parent $BehAdvanced -Text "Advanced download tuning" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $BehAdvanced -Text "Chunks per file" -Location (New-Object System.Drawing.Point(24, 68)))
$NumChunks = New-NumericUpDown -Parent $BehAdvanced -Location (New-Object System.Drawing.Point(412, 64)) -Min 1 -Max 20 -Value 1 -Tag "Input"
[void](New-Label -Parent $BehAdvanced -Text "Split downloads into segments. Higher values can improve speed on premium hosts." -Location (New-Object System.Drawing.Point(24, 94)) -Size (New-Object System.Drawing.Size(520, 24)) -AutoSize $false -Tag "BodyMuted")
[void](New-Label -Parent $BehAdvanced -Text "Per-host limit" -Location (New-Object System.Drawing.Point(24, 128)))
$NumPerHost = New-NumericUpDown -Parent $BehAdvanced -Location (New-Object System.Drawing.Point(412, 124)) -Min 1 -Max 20 -Value 1 -Tag "Input"
[void](New-Label -Parent $BehAdvanced -Text "Max simultaneous downloads from any single host. Increase for premium accounts." -Location (New-Object System.Drawing.Point(24, 150)) -Size (New-Object System.Drawing.Size(520, 18)) -AutoSize $false -Tag "BodyMuted")

$BehFileOpts = New-Surface -Parent $BehaviorCanvas -Location (New-Object System.Drawing.Point(662, 548)) -Size (New-Object System.Drawing.Size(378, 168)) -Tag "SurfaceAlt"
[void](New-Label -Parent $BehFileOpts -Text "File handling" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)))
$ChkHashCheck = New-CheckBox -Parent $BehFileOpts -Text "Verify file integrity (hash check)" -Location (New-Object System.Drawing.Point(24, 68)) -Checked $true
$ChkPreserveDate = New-CheckBox -Parent $BehFileOpts -Text "Preserve original file dates" -Location (New-Object System.Drawing.Point(24, 100))
$ChkClipboard = New-CheckBox -Parent $BehFileOpts -Text "Monitor clipboard for download links" -Location (New-Object System.Drawing.Point(24, 132)) -Checked $true

# --- Hardening Page ---
$HardHero = New-Surface -Parent $HardeningCanvas -Location (New-Object System.Drawing.Point(0, 0)) -Size (New-Object System.Drawing.Size(1040, 156))
$HardTitle = New-Label -Parent $HardHero -LangKey "HardTitle" -Location (New-Object System.Drawing.Point(24, 24)) -Tag "SectionHeader"
$HardSub = New-Label -Parent $HardHero -LangKey "HardSub" -Location (New-Object System.Drawing.Point(24, 60)) -Size (New-Object System.Drawing.Size(690, 40)) -AutoSize $false -Tag "SubHeader"
$HardResultBadge = New-Badge -Parent $HardHero -Text "Cleaner shell by default" -Location (New-Object System.Drawing.Point(780, 28)) -Size (New-Object System.Drawing.Size(188, 28)) -Tag "BadgeAccent"
$HardResultDetail = New-Label -Parent $HardHero -Text "This pass removes promotional noise first, then lets you opt into the finishing touches that fit your desktop." -Location (New-Object System.Drawing.Point(780, 64)) -Size (New-Object System.Drawing.Size(214, 68)) -AutoSize $false -Tag "BodyMuted"

$HardControls = New-Surface -Parent $HardeningCanvas -Location (New-Object System.Drawing.Point(0, 180)) -Size (New-Object System.Drawing.Size(640, 228))
[void](New-Label -Parent $HardControls -Text "Optional finishing passes" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $HardControls -Text "These are off by default if you want a lighter-touch run. Enable whichever touches fit your setup." -Location (New-Object System.Drawing.Point(24, 52)) -Size (New-Object System.Drawing.Size(568, 24)) -AutoSize $false -Tag "BodyMuted")
$ChkExe = New-CheckBox -Parent $HardControls -LangKey "DarkExe" -Location (New-Object System.Drawing.Point(24, 84)) -Checked $true
[void](New-Label -Parent $HardControls -Text "Replaces the executable icon so the shell looks more at home with darker setups." -Location (New-Object System.Drawing.Point(48, 110)) -Size (New-Object System.Drawing.Size(544, 32)) -AutoSize $false -Tag "BodyMuted")
$ChkUpdate = New-CheckBox -Parent $HardControls -LangKey "RunUpdate" -Location (New-Object System.Drawing.Point(24, 156)) -Checked $true
[void](New-Label -Parent $HardControls -Text "Launches JDownloader's update routine once configuration work finishes." -Location (New-Object System.Drawing.Point(48, 182)) -Size (New-Object System.Drawing.Size(544, 24)) -AutoSize $false -Tag "BodyMuted")

$HardAlways = New-Surface -Parent $HardeningCanvas -Location (New-Object System.Drawing.Point(662, 180)) -Size (New-Object System.Drawing.Size(378, 228)) -Tag "SurfaceAlt"
[void](New-Label -Parent $HardAlways -Text "Always applied cleanup" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $HardAlways -Text "Contribute panel" -Location (New-Object System.Drawing.Point(24, 74)) -Font (New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
[void](New-Label -Parent $HardAlways -Text "Promotional banners" -Location (New-Object System.Drawing.Point(24, 106)) -Font (New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
[void](New-Label -Parent $HardAlways -Text "Premium upsell columns + alerts" -Location (New-Object System.Drawing.Point(24, 138)) -Font (New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
[void](New-Label -Parent $HardAlways -Text "Special deals, donate button, captcha ads" -Location (New-Object System.Drawing.Point(24, 170)) -Font (New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
[void](New-Label -Parent $HardAlways -Text "Bubble notifications disabled" -Location (New-Object System.Drawing.Point(24, 202)) -Font (New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")

# --- Privacy & Security ---
$HardPrivacy = New-Surface -Parent $HardeningCanvas -Location (New-Object System.Drawing.Point(0, 432)) -Size (New-Object System.Drawing.Size(640, 200))
[void](New-Label -Parent $HardPrivacy -Text "Privacy and security" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $HardPrivacy -Text "Control network exposure, local APIs, and JVM performance flags." -Location (New-Object System.Drawing.Point(24, 52)) -Size (New-Object System.Drawing.Size(568, 24)) -AutoSize $false -Tag "BodyMuted")
$ChkDisableAPI = New-CheckBox -Parent $HardPrivacy -Text "Disable deprecated local API (port 3128)" -Location (New-Object System.Drawing.Point(24, 84)) -Checked $true
[void](New-Label -Parent $HardPrivacy -Text "Blocks the legacy unauthenticated REST API that listens on localhost." -Location (New-Object System.Drawing.Point(48, 110)) -Size (New-Object System.Drawing.Size(544, 24)) -AutoSize $false -Tag "BodyMuted")
$ChkVmOptions = New-CheckBox -Parent $HardPrivacy -Text "Write JVM performance options file" -Location (New-Object System.Drawing.Point(24, 144))
[void](New-Label -Parent $HardPrivacy -Text "Creates JDownloader2.vmoptions with tuned flags. Skipped if the file already exists." -Location (New-Object System.Drawing.Point(48, 170)) -Size (New-Object System.Drawing.Size(544, 24)) -AutoSize $false -Tag "BodyMuted")

$HardNoteSurface = New-Surface -Parent $HardeningCanvas -Location (New-Object System.Drawing.Point(662, 432)) -Size (New-Object System.Drawing.Size(378, 200)) -Tag "SurfaceAlt"
[void](New-Label -Parent $HardNoteSurface -Text "What gets removed" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)))
$HardNote = New-Label -Parent $HardNoteSurface -LangKey "HardNote" -Location (New-Object System.Drawing.Point(24, 56)) -Size (New-Object System.Drawing.Size(330, 120)) -AutoSize $false -Tag "BodyMuted"

$HardResultSurface = New-Surface -Parent $HardeningCanvas -Location (New-Object System.Drawing.Point(0, 656)) -Size (New-Object System.Drawing.Size(1040, 100))
[void](New-Label -Parent $HardResultSurface -Text "This pass writes debloat flags across 8 config files, replaces banner images with blank PNGs, and optionally hardens the local API and JVM settings." -Location (New-Object System.Drawing.Point(24, 22)) -Size (New-Object System.Drawing.Size(992, 56)) -AutoSize $false -Tag "BodyMuted")

function Update-HardeningProfile {
    if (-not $HardResultBadge -or -not $HardResultDetail -or -not $ChkExe -or -not $ChkUpdate) { return }

    if ($ChkExe.Checked -and $ChkUpdate.Checked) {
        $badgeText = "Full finishing pass"
        $badgeState = "Success"
        $detailText = "Promotional UI is removed, the darker shell icon stays enabled, and JDownloader refreshes after the run."
    } elseif ($ChkExe.Checked) {
        $badgeText = "Cleanup + shell polish"
        $badgeState = "Accent"
        $detailText = "Promotional UI is removed and the darker shell icon stays enabled. Updates stay manual."
    } elseif ($ChkUpdate.Checked) {
        $badgeText = "Cleanup + refresh"
        $badgeState = "Accent"
        $detailText = "Promotional UI is removed and JDownloader refreshes after the run. The stock executable icon stays in place."
    } else {
        $badgeText = "Cleanup only"
        $badgeState = "Neutral"
        $detailText = "Promotional UI is removed, while icon patching and post-run updates stay off for a lighter-touch pass."
    }

    Set-BadgeState -Badge $HardResultBadge -Text $badgeText -State $badgeState
    $HardResultDetail.Text = $detailText
}

# --- Repair Page ---
$RepairHero = New-Surface -Parent $RepairCanvas -Location (New-Object System.Drawing.Point(0, 0)) -Size (New-Object System.Drawing.Size(1040, 160))
$RepTitle = New-Label -Parent $RepairHero -LangKey "RepTitle" -Location (New-Object System.Drawing.Point(24, 24)) -Tag "SectionHeader"
$RepSub = New-Label -Parent $RepairHero -LangKey "RepSub" -Location (New-Object System.Drawing.Point(24, 60)) -Size (New-Object System.Drawing.Size(690, 40)) -AutoSize $false -Tag "SubHeader"
[void](New-Badge -Parent $RepairHero -Text "Confirmation required" -Location (New-Object System.Drawing.Point(780, 28)) -Size (New-Object System.Drawing.Size(196, 28)) -Tag "BadgeWarning")
[void](New-Label -Parent $RepairHero -Text "Most actions below stop JDownloader first. Destructive actions ask for confirmation before they continue." -Location (New-Object System.Drawing.Point(780, 64)) -Size (New-Object System.Drawing.Size(220, 68)) -AutoSize $false -Tag "BodyMuted")

function Show-ActionPrompt {
    param([string]$Title, [string]$Message, [string]$ConfirmText = "Continue", [string]$ConfirmTag = "PrimaryButton")
    $pal = Get-ActivePalette
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $Title
    $dlg.Size = New-Object System.Drawing.Size(520, 296)
    $dlg.MinimumSize = $dlg.Size
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.ShowInTaskbar = $false
    $dlg.BackColor = $pal.FormBack
    $dlg.ForeColor = $pal.Fore
    $dlg.AutoScaleMode = "Dpi"
    $body = New-Surface -Parent $dlg -Location (New-Object System.Drawing.Point(16, 16)) -Size (New-Object System.Drawing.Size(472, 174))
    [void](New-Label -Parent $body -Text $Title -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)))
    [void](New-Label -Parent $body -Text $Message -Location (New-Object System.Drawing.Point(24, 58)) -Size (New-Object System.Drawing.Size(424, 82)) -AutoSize $false -Tag "BodyMuted")
    $btnConfirm = New-Button -Parent $dlg -Text $ConfirmText -Location (New-Object System.Drawing.Point(16, 206)) -Size (New-Object System.Drawing.Size(188, 36)) -Tag $ConfirmTag
    $btnConfirm.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnCancel = New-Button -Parent $dlg -Text (Get-LangValue -Key "Cancel" -Fallback "Cancel") -Location (New-Object System.Drawing.Point(218, 206)) -Size (New-Object System.Drawing.Size(120, 36)) -Tag "SecondaryButton"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.AcceptButton = $btnConfirm
    $dlg.CancelButton = $btnCancel
    Apply-GuiTheme -ThemeName $script:CurrentGuiTheme -Root $dlg
    try {
        return ($dlg.ShowDialog($Form) -eq [System.Windows.Forms.DialogResult]::OK)
    } finally { $dlg.Dispose() }
}

function Ensure-InstallPathSelected {
    param([switch]$RequireExecutable)
    if ([string]::IsNullOrWhiteSpace($TxtPath.Text)) {
        Focus-InstallPath
        Log-Status "Select a JDownloader folder before using repair tools." "WARN"
        [System.Windows.Forms.MessageBox]::Show((Get-LangValue -Key "PathRequiredBody" -Fallback "Choose a JDownloader folder first."), (Get-LangValue -Key "PathRequiredTitle" -Fallback "Path required"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return $false
    }
    if ($RequireExecutable -and -not (Test-Path "$($TxtPath.Text)\JDownloader2.exe")) {
        Focus-InstallPath
        Log-Status "Point the tool at a valid JDownloader installation before continuing." "WARN"
        [System.Windows.Forms.MessageBox]::Show((Get-LangValue -Key "InstallRequiredBody" -Fallback "Point the tool at a valid JDownloader installation first."), (Get-LangValue -Key "InstallRequiredTitle" -Fallback "Installation required"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return $false
    }
    return $true
}

$RepairResetCfg = New-ActionTile -Parent $RepairCanvas -Location (New-Object System.Drawing.Point(0, 184)) -Title "Factory reset" -Description "Back up and remove the full cfg folder to return JDownloader to a clean starting point." -ButtonText "Reset configuration" -ButtonTag "DangerButton" -BadgeText "Destructive" -BadgeState "Danger" -Action {
    if (-not (Ensure-InstallPathSelected)) { return }
    if (-not (Show-ActionPrompt -Title "Reset configuration" -Message "This closes JDownloader, backs up the current configuration, and removes the cfg folder. Downloads remain on disk." -ConfirmText "Reset configuration" -ConfirmTag "DangerButton")) { return }
    Kill-JDownloader
    Backup-JD -InstallPath $TxtPath.Text
    $cfg = Join-Path $TxtPath.Text 'cfg'
    if (Test-Path $cfg) { try { Remove-Item $cfg -Recurse -Force -ErrorAction Stop } catch { Log-Status "Reset failed: $_" "ERROR"; return } }
    Log-Status "Configuration reset completed." "SUCCESS"
}
$RepairResetTheme = New-ActionTile -Parent $RepairCanvas -Location (New-Object System.Drawing.Point(354, 184)) -Title "Theme reset" -Description "Strip theme overrides and custom icons without touching the rest of the installation." -ButtonText "Reset theme only" -ButtonTag "SecondaryButton" -BadgeText "Reversible" -BadgeState "Accent" -Action {
    if (-not (Ensure-InstallPathSelected)) { return }
    if (-not (Show-ActionPrompt -Title "Reset theme assets" -Message "This removes the custom look-and-feel files and current icon overrides so you can start fresh." -ConfirmText "Reset theme assets" -ConfirmTag "PrimaryButton")) { return }
    Kill-JDownloader
    $laf    = Join-Path $TxtPath.Text 'cfg\laf'
    $icons  = Join-Path $TxtPath.Text 'themes\standard\org\jdownloader\images'
    if (Test-Path $laf)   { try { Remove-Item $laf -Recurse -Force -ErrorAction SilentlyContinue } catch {} }
    if (Test-Path $icons) { try { Remove-Item (Join-Path $icons '*') -Recurse -Force -ErrorAction SilentlyContinue } catch {} }
    Log-Status "Theme and icon overrides were cleared." "SUCCESS"
}
$RepairClearCache = New-ActionTile -Parent $RepairCanvas -Location (New-Object System.Drawing.Point(708, 184)) -Title "Cache cleanup" -Description "Delete temporary files, logs, and cache fragments that commonly linger after broken runs." -ButtonText "Clear cache" -ButtonTag "SecondaryButton" -BadgeText "Safe" -BadgeState "Success" -Action {
    if (-not (Ensure-InstallPathSelected)) { return }
    Kill-JDownloader
    $root = $TxtPath.Text.Trim()
    $removed = 0
    $targets = @(
        (Join-Path $root 'tmp\*')
        (Join-Path $root 'logs\*')
        (Join-Path $root 'cfg\*.cache')
        (Join-Path $root 'cfg\tmp\*')
        (Join-Path $root 'update\*.tmp')
    )
    foreach ($glob in $targets) {
        try {
            $items = Get-ChildItem -Path $glob -Recurse -Force -ErrorAction SilentlyContinue
            if ($items) {
                $items | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                $removed += $items.Count
            }
        } catch {}
    }
    Log-Status ("Cache cleanup removed {0} item(s)." -f $removed) "SUCCESS"
}
$RepairAudit = New-ActionTile -Parent $RepairCanvas -Location (New-Object System.Drawing.Point(0, 372)) -Title "Health audit" -Description "Check for missing or corrupted configuration files before you commit to a larger repair step." -ButtonText "Run health audit" -ButtonTag "SuccessButton" -BadgeText "Read-only" -BadgeState "Accent" -Action { if (Ensure-InstallPathSelected) { Run-Audit -InstallPath $TxtPath.Text } }
$RepairSafe = New-ActionTile -Parent $RepairCanvas -Location (New-Object System.Drawing.Point(354, 372)) -Title "Safe mode launch" -Description "Start JDownloader with a reduced profile for troubleshooting unstable themes or config changes." -ButtonText "Launch safe mode" -ButtonTag "SuccessButton" -BadgeText "Safe" -BadgeState "Success" -Action {
    if (-not (Ensure-InstallPathSelected -RequireExecutable)) { return }
    $exe = Join-Path $TxtPath.Text 'JDownloader2.exe'
    try {
        Start-Process -FilePath $exe -ArgumentList '-safe' -ErrorAction Stop
        Log-Status "JDownloader launched in safe mode." "SUCCESS"
    } catch { Log-Status "Failed to launch safe mode: $_" "ERROR" }
}
$RepairUninstall = New-ActionTile -Parent $RepairCanvas -Location (New-Object System.Drawing.Point(708, 372)) -Title "Full uninstall" -Description "Remove the application entirely when you need to start over from a clean machine state." -ButtonText "Full uninstall" -ButtonTag "DangerButton" -BadgeText "Destructive" -BadgeState "Danger" -Action {
    if (-not (Ensure-InstallPathSelected)) { return }
    if (-not (Show-ActionPrompt -Title "Full uninstall" -Message "This removes JDownloader from the selected folder. Use it only when you want to wipe the install completely." -ConfirmText "Uninstall JDownloader" -ConfirmTag "DangerButton")) { return }
    Task-FullUninstall -InstallPath $TxtPath.Text
    Log-Status "Full uninstall finished." "SUCCESS"
}

function Update-ModeSummary {
    switch ($CboMode.SelectedIndex) {
        1 { $InstallModeSummaryTitle.Text = "Clean install from GitHub"; $LblModeHelp.Text = "Downloads the GitHub installer automatically, then applies the options you selected in this workspace."; $DashModeDetail.Text = "Clean install using GitHub assets" }
        2 { $InstallModeSummaryTitle.Text = "Manual Mega fallback"; $LblModeHelp.Text = "Opens the Mega page for manual download, then continues once the installer is available locally."; $DashModeDetail.Text = "Clean install using manual Mega download" }
        default { $InstallModeSummaryTitle.Text = "Modify an existing install"; $LblModeHelp.Text = "Use this when JDownloader is already present and you want to refine its configuration in place."; $DashModeDetail.Text = "Modify current installation" }
    }
}

function Update-PathState {
    $palette = Get-ActivePalette
    $path = $TxtPath.Text.Trim()
    $pathExists = -not [string]::IsNullOrWhiteSpace($path) -and (Test-Path $path)
    $hasExe = $pathExists -and (Test-Path (Join-Path $path "JDownloader2.exe"))
    if ($CboMode.SelectedIndex -eq 0) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            $LblPathState.Text = "Modify mode needs an existing JDownloader folder."
            $LblPathState.ForeColor = $palette.Warning
            $DashInstallStatus.Text = "Path needed"
            $DashInstallDetail.Text = "Select the existing installation you want to refine."
            Set-BadgeState -Badge $InstallBadge -Text "Path needed" -State "Warning"
            $TxtPath.BackColor = $palette.InputBack
        }
        elseif ($hasExe) {
            $LblPathState.Text = "Ready. JDownloader was found at this location."
            $LblPathState.ForeColor = $palette.Success
            $DashInstallStatus.Text = "Install detected"
            $DashInstallDetail.Text = $path
            Set-BadgeState -Badge $InstallBadge -Text "Installed" -State "Success"
            $TxtPath.BackColor = [System.Windows.Forms.ControlPaint]::Light($palette.Success, 0.85)
        }
        elseif ($pathExists) {
            $LblPathState.Text = "The folder exists, but JDownloader2.exe was not found there."
            $LblPathState.ForeColor = $palette.Warning
            $DashInstallStatus.Text = "Folder found"
            $DashInstallDetail.Text = "Switch to clean install mode or point to the correct install."
            Set-BadgeState -Badge $InstallBadge -Text "Check folder" -State "Warning"
            $TxtPath.BackColor = [System.Windows.Forms.ControlPaint]::Light($palette.Warning, 0.82)
        }
        else {
            $LblPathState.Text = "That folder does not exist yet."
            $LblPathState.ForeColor = $palette.Danger
            $DashInstallStatus.Text = "Path not found"
            $DashInstallDetail.Text = "Use Browse or Auto-Detect to pick a valid installation."
            Set-BadgeState -Badge $InstallBadge -Text "Invalid path" -State "Danger"
            $TxtPath.BackColor = [System.Windows.Forms.ControlPaint]::Light($palette.Danger, 0.82)
        }
    } else {
        if ([string]::IsNullOrWhiteSpace($path)) {
            $LblPathState.Text = "Clean install can start without a path. The app will detect JDownloader after install completes."
            $LblPathState.ForeColor = $palette.MutedStrong
            $DashInstallStatus.Text = "Clean install ready"
            $DashInstallDetail.Text = "No existing path is required for this flow."
            Set-BadgeState -Badge $InstallBadge -Text "Fresh install" -State "Accent"
            $TxtPath.BackColor = $palette.InputBack
        }
        elseif ($hasExe) {
            $LblPathState.Text = "An existing JDownloader install is already present here. You can still continue with clean install if you want to replace it."
            $LblPathState.ForeColor = $palette.Warning
            $DashInstallStatus.Text = "Existing install present"
            $DashInstallDetail.Text = $path
            Set-BadgeState -Badge $InstallBadge -Text "Install present" -State "Warning"
            $TxtPath.BackColor = [System.Windows.Forms.ControlPaint]::Light($palette.Warning, 0.82)
        }
        elseif ($pathExists) {
            $LblPathState.Text = "Folder exists and can be used as a reference point while the installer finishes."
            $LblPathState.ForeColor = $palette.MutedStrong
            $DashInstallStatus.Text = "Folder selected"
            $DashInstallDetail.Text = "JDownloader will be detected after the install phase."
            Set-BadgeState -Badge $InstallBadge -Text "Folder selected" -State "Accent"
            $TxtPath.BackColor = $palette.InputBack
        }
        else {
            $LblPathState.Text = "This folder does not exist yet, but clean install mode can still continue."
            $LblPathState.ForeColor = $palette.MutedStrong
            $DashInstallStatus.Text = "Clean install ready"
            $DashInstallDetail.Text = "The installer will decide the final install location."
            Set-BadgeState -Badge $InstallBadge -Text "Fresh install" -State "Accent"
            $TxtPath.BackColor = $palette.InputBack
        }
    }
    $TxtPath.ForeColor = $palette.Fore
}

function Update-DownloadFolderState {
    $palette = Get-ActivePalette
    $folder = $TxtDl.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($folder)) {
        $LblDownloadState.Text = "Leave this blank to reset the download folder back to JDownloader's default."
        $LblDownloadState.ForeColor = $palette.MutedStrong
        $TxtDl.BackColor = $palette.InputBack
        $TxtDl.ForeColor = $palette.Fore
        return
    }
    if (Test-Path $folder) {
        $LblDownloadState.Text = "Ready. Files will download here by default."
        $LblDownloadState.ForeColor = $palette.Success
        $TxtDl.BackColor = [System.Windows.Forms.ControlPaint]::Light($palette.Success, 0.85)
        $TxtDl.ForeColor = $palette.Fore
        return
    }
    $parent = Split-Path $folder -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and (Test-Path $parent)) {
        $LblDownloadState.Text = "This folder will be created the first time JDownloader writes to it."
        $LblDownloadState.ForeColor = $palette.MutedStrong
        $TxtDl.BackColor = $palette.InputBack
    }
    else {
        $LblDownloadState.Text = "The parent folder does not exist yet. Double-check the path before you apply changes."
        $LblDownloadState.ForeColor = $palette.Warning
        $TxtDl.BackColor = [System.Windows.Forms.ControlPaint]::Light($palette.Warning, 0.82)
    }
    $TxtDl.ForeColor = $palette.Fore
}

# ==========================================
# 9. CONFIRMATION DIALOG (Enhanced)
# ==========================================

function Show-ConfirmationDialog {
    param($CurrentState)
    if ($CurrentState.Mode -eq "Modify" -and [string]::IsNullOrWhiteSpace($CurrentState.InstallPath)) {
        Focus-InstallPath
        Log-Status "Modify mode needs an existing JDownloader folder." "WARN"
        [System.Windows.Forms.MessageBox]::Show("Select an existing JDownloader folder before running modify mode.", (Get-LangValue -Key "PathRequiredTitle" -Fallback "Path required"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return $false
    }

    $pal = Get-ActivePalette
    $normalizedState = Get-NormalizedStateObject -State $CurrentState
    $baselineState = Get-WorkspaceComparisonBaseline
    $changedAreas = @(Get-ChangedWorkspaceAreas -SavedState $baselineState -CurrentState $normalizedState)
    $runModeDisplay = if ($CurrentState.Mode -eq "Install") { "Clean install" } else { "Modify existing install" }
    $sourceDisplay = if ($CurrentState.Mode -eq "Install") {
        if ($CurrentState.InstallSource -eq "Mega") { "Manual Mega download" } else { "GitHub download" }
    } else {
        "Existing install"
    }
    $downloadDisplay = if ([string]::IsNullOrWhiteSpace($CurrentState.DlFolder)) { "JDownloader default" } else { $CurrentState.DlFolder }
    $languageDisplay = if ([string]::IsNullOrWhiteSpace($CurrentState.LanguageCode)) { $CurrentLangCode } else { $CurrentState.LanguageCode }
    $changeScopeText = if (-not $script:SavedWorkspaceState) {
        if ($changedAreas.Count -gt 0) {
            "First run setup. This will save the current workspace and apply updates to {0}." -f (Join-ReadableList -Items $changedAreas)
        } else {
            "First run setup. Current defaults will become the saved workspace for future launches."
        }
    } elseif ($changedAreas.Count -gt 0) {
        "Compared with the last successful run, this will update {0}." -f (Join-ReadableList -Items $changedAreas)
    } else {
        "This re-applies the same workspace that was saved on the last successful run."
    }
    if (-not $script:SavedWorkspaceState) {
        $summaryBadgeText = "First run"
        $summaryBadgeState = "Accent"
    } elseif ($changedAreas.Count -gt 0) {
        $summaryBadgeText = "{0} area{1}" -f $changedAreas.Count, (if ($changedAreas.Count -eq 1) { "" } else { "s" })
        $summaryBadgeState = "Warning"
    } else {
        $summaryBadgeText = "Saved workspace"
        $summaryBadgeState = "Success"
    }
    $pathPreview = if ([string]::IsNullOrWhiteSpace($CurrentState.InstallPath)) { "Auto-detect after install" } else { $CurrentState.InstallPath }
    $guardrailText = if ($CurrentState.Mode -eq "Modify") {
        "Modify mode backs up the current configuration before file changes are applied."
    } else {
        "Clean install runs the installer first, then detects the resulting JDownloader folder before applying your selected options."
    }
    $cForm = New-Object System.Windows.Forms.Form
    $cForm.Text = "Confirm changes"
    $cForm.Size = New-Object System.Drawing.Size(700, 688)
    $cForm.MinimumSize = $cForm.Size
    $cForm.StartPosition = "CenterParent"
    $cForm.FormBorderStyle = "FixedDialog"
    $cForm.MaximizeBox = $false
    $cForm.MinimizeBox = $false
    $cForm.ShowInTaskbar = $false
    $cForm.BackColor = $pal.FormBack
    $cForm.ForeColor = $pal.Fore
    $cForm.AutoScaleMode = "Dpi"

    $summary = New-Surface -Parent $cForm -Location (New-Object System.Drawing.Point(16, 16)) -Size (New-Object System.Drawing.Size(652, 218))
    $summaryBadge = New-Badge -Parent $summary -Text $summaryBadgeText -Location (New-Object System.Drawing.Point(488, 22)) -Size (New-Object System.Drawing.Size(140, 28))
    Set-BadgeState -Badge $summaryBadge -Text $summaryBadgeText -State $summaryBadgeState
    [void](New-Label -Parent $summary -Text "Review the run" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)))
    [void](New-Label -Parent $summary -Text "Use the checklist below to confirm the most important options before the tool starts writing files." -Location (New-Object System.Drawing.Point(24, 54)) -Size (New-Object System.Drawing.Size(604, 34)) -AutoSize $false -Tag "BodyMuted")
    [void](New-Label -Parent $summary -Text "Run type" -Location (New-Object System.Drawing.Point(24, 104)) -Font (New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
    [void](New-Label -Parent $summary -Text $runModeDisplay -Location (New-Object System.Drawing.Point(24, 124)) -Font (New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)))
    [void](New-Label -Parent $summary -Text "Install source" -Location (New-Object System.Drawing.Point(236, 104)) -Font (New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
    [void](New-Label -Parent $summary -Text $sourceDisplay -Location (New-Object System.Drawing.Point(236, 124)) -Size (New-Object System.Drawing.Size(184, 32)) -AutoSize $false -Tag "MutedStrong")
    [void](New-Label -Parent $summary -Text "Theme preset" -Location (New-Object System.Drawing.Point(436, 104)) -Font (New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
    [void](New-Label -Parent $summary -Text $CurrentState.ThemeName -Location (New-Object System.Drawing.Point(436, 124)) -Size (New-Object System.Drawing.Size(190, 32)) -AutoSize $false -Tag "MutedStrong")
    [void](New-Label -Parent $summary -Text "Icon pack" -Location (New-Object System.Drawing.Point(24, 156)) -Font (New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
    [void](New-Label -Parent $summary -Text $CurrentState.IconPack -Location (New-Object System.Drawing.Point(24, 176)) -Size (New-Object System.Drawing.Size(184, 20)) -AutoSize $false -Tag "MutedStrong")
    [void](New-Label -Parent $summary -Text "Manager language" -Location (New-Object System.Drawing.Point(236, 156)) -Font (New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
    [void](New-Label -Parent $summary -Text $languageDisplay -Location (New-Object System.Drawing.Point(236, 176)) -Size (New-Object System.Drawing.Size(184, 20)) -AutoSize $false -Tag "MutedStrong")
    [void](New-Label -Parent $summary -Text "Download folder" -Location (New-Object System.Drawing.Point(436, 156)) -Font (New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
    [void](New-Label -Parent $summary -Text $downloadDisplay -Location (New-Object System.Drawing.Point(436, 176)) -Size (New-Object System.Drawing.Size(190, 32)) -AutoSize $false -Tag "MutedStrong")

    $optionsPanel = New-Surface -Parent $cForm -Location (New-Object System.Drawing.Point(16, 250)) -Size (New-Object System.Drawing.Size(652, 336)) -Tag "SurfaceAlt"
    [void](New-Label -Parent $optionsPanel -Text "Confirm optional switches" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)))
    [void](New-Label -Parent $optionsPanel -Text $changeScopeText -Location (New-Object System.Drawing.Point(24, 52)) -Size (New-Object System.Drawing.Size(604, 38)) -AutoSize $false -Tag "BodyMuted")

    $KeyMap = [ordered]@{
        "WindowDec"      = "Enable custom window decorations"
        "ForceMinimal"   = "Use compact tab layout"
        "StartMin"       = "Start minimized"
        "MinToTray"      = "Minimize to tray"
        "CloseToTray"    = "Close button sends JDownloader to tray"
        "HashCheck"      = "Verify file integrity after download"
        "PreserveFileDate"= "Preserve original file dates"
        "ClipboardMonitor"= "Monitor clipboard for download links"
        "PatchExe"       = "Apply dark executable icon"
        "AutoUpdate"     = "Run update after completion"
        "DisableLocalAPI"= "Disable legacy local API (port 3128)"
        "WriteVmOptions" = "Write JVM performance options file"
    }
    $ResultRefs = @{}
    [int]$optY = 104
    foreach ($key in $KeyMap.Keys) {
        if ($CurrentState.Contains($key)) {
            $cb = New-CheckBox -Parent $optionsPanel -Text $KeyMap[$key] -Location (New-Object System.Drawing.Point(24, $optY)) -Checked $CurrentState[$key]
            $ResultRefs[$key] = $cb
            $optY += 34
        }
    }
    [void](New-Label -Parent $optionsPanel -Text "Install path" -Location (New-Object System.Drawing.Point(24, 262)) -Font (New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
    [void](New-Label -Parent $optionsPanel -Text $pathPreview -Location (New-Object System.Drawing.Point(24, 282)) -Size (New-Object System.Drawing.Size(604, 24)) -AutoSize $false -Tag "MutedStrong")
    [void](New-Label -Parent $optionsPanel -Text $guardrailText -Location (New-Object System.Drawing.Point(24, 306)) -Size (New-Object System.Drawing.Size(604, 24)) -AutoSize $false -Tag "BodyMuted")

    $btnOk = New-Button -Parent $cForm -Text (Get-LangValue -Key "ApplySelected" -Fallback "Apply selected changes") -Location (New-Object System.Drawing.Point(16, 600)) -Size (New-Object System.Drawing.Size(214, 38)) -Tag "PrimaryButton"
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnCancel = New-Button -Parent $cForm -Text (Get-LangValue -Key "Back" -Fallback "Back") -Location (New-Object System.Drawing.Point(244, 600)) -Size (New-Object System.Drawing.Size(110, 38)) -Tag "SecondaryButton"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cForm.AcceptButton = $btnOk
    $cForm.CancelButton = $btnCancel

    Apply-GuiTheme -ThemeName $script:CurrentGuiTheme -Root $cForm
    try {
    $result = $cForm.ShowDialog($Form)
    } finally { $cForm.Dispose() }

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        foreach ($k in $ResultRefs.Keys) {
             $CurrentState[$k] = $ResultRefs[$k].Checked
        }
        
        # Sync changes back to main GUI
        if($ResultRefs["WindowDec"]) { $ChkWinDec.Checked = $ResultRefs["WindowDec"].Checked }
        if($ResultRefs["ForceMinimal"]) { $ChkMinLay.Checked = $ResultRefs["ForceMinimal"].Checked }
        if($ResultRefs["StartMin"]) { $ChkMin.Checked = $ResultRefs["StartMin"].Checked }
        if($ResultRefs["MinToTray"]) { $ChkTray.Checked = $ResultRefs["MinToTray"].Checked }
        if($ResultRefs["CloseToTray"]) { $ChkCloseTray.Checked = $ResultRefs["CloseToTray"].Checked }
        if($ResultRefs["PatchExe"]) { $ChkExe.Checked = $ResultRefs["PatchExe"].Checked }
        if($ResultRefs["AutoUpdate"]) { $ChkUpdate.Checked = $ResultRefs["AutoUpdate"].Checked }
        if($ResultRefs["HashCheck"]) { $ChkHashCheck.Checked = $ResultRefs["HashCheck"].Checked }
        if($ResultRefs["PreserveFileDate"]) { $ChkPreserveDate.Checked = $ResultRefs["PreserveFileDate"].Checked }
        if($ResultRefs["ClipboardMonitor"]) { $ChkClipboard.Checked = $ResultRefs["ClipboardMonitor"].Checked }
        if($ResultRefs["DisableLocalAPI"]) { $ChkDisableAPI.Checked = $ResultRefs["DisableLocalAPI"].Checked }
        if($ResultRefs["WriteVmOptions"]) { $ChkVmOptions.Checked = $ResultRefs["WriteVmOptions"].Checked }
        
        return $true
    }
    return $false
}

# ==========================================
# 10. NAVIGATION & EXECUTION
# ==========================================

$pages = @{ $BtnDashboard = $PageDashboard; $BtnLiveControl = $PageLiveControl; $BtnInstallation = $PageInstallation; $BtnTheme = $PageTheme; $BtnBehavior = $PageBehavior; $BtnHardening = $PageHardening; $BtnRepair = $PageRepair }
$script:ActiveNavButton = $BtnDashboard

function Update-NavigationState {
    $pal = Get-ActivePalette
    foreach ($button in $pages.Keys) {
        if ($button -eq $script:ActiveNavButton) {
            $button.BackColor = $pal.SidebarAlt
            $button.ForeColor = $pal.Fore
        } else {
            $button.BackColor = $pal.Sidebar
            $button.ForeColor = $pal.MutedStrong
        }
        if ($script:NavIndicators.ContainsKey($button)) {
            $script:NavIndicators[$button].Visible = ($button -eq $script:ActiveNavButton)
            if ($button -eq $script:ActiveNavButton) { $script:NavIndicators[$button].BringToFront() }
        }
    }
}

function Show-Page {
    param($Button)
    if (-not $Button -or -not $pages.ContainsKey($Button)) { return }
    $target = $pages[$Button]
    if (-not $target -or $target.IsDisposed) { return }

    foreach ($page in $pages.Values) {
        if ($page -and -not $page.IsDisposed) { $page.Visible = $false }
    }
    $target.Visible = $true
    Center-PageCanvas $target
    $script:ActiveNavButton = $Button
    Update-NavigationState
    if ($target -eq $PageTheme) {
        Resize-ThemePreview
        Update-ThemePreview
    }
    if ($target -eq $PageLiveControl -and $script:LiveApiClient) {
        Refresh-LiveApiQueue
        Refresh-LiveCaptcha
    }
}

function Start-WorkspaceApply {
    # Re-entrancy guard: prevent double-invocation from rapid double-click on Apply before
    # Set-WorkspaceBusyState has had a chance to disable the button.
    if ($script:ApplyInFlight) {
        Log-Status "Apply already in progress." "DEBUG"
        return $false
    }
    $script:ApplyInFlight = $true
    if ($BtnExec) { $BtnExec.Enabled = $false }

    try {
        $State = Get-CurrentGuiState
        if ($State.Mode -eq "Modify" -and [string]::IsNullOrWhiteSpace($State.InstallPath)) {
            Focus-InstallPath
            Log-Status "Modify mode needs an existing JDownloader folder." "WARN"
            return $false
        }

        if (-not $script:IsElevated) {
            if (Request-ElevatedApply -State $State) {
                Log-Status "Administrative approval requested. The elevated workspace will continue this run." "INFO"
                if ($Form) { $Form.Close() }
                return $true
            }
            return $false
        }

        if (-not (Show-ConfirmationDialog -CurrentState $State)) {
            Log-Status "Apply was canceled before changes were written." "INFO"
            return $false
        }

        Set-WorkspaceBusyState -IsBusy $true
        $ProgressBar.Value = 15
        Log-Status "Applying selected changes..." "INFO"
        try { $Form.Refresh() } catch {}
        $completed = $false
        try {
            $completed = Execute-Operations -GUI_State $State
        } finally {
            Set-WorkspaceBusyState -IsBusy $false
        }

        if ($completed) {
            $script:SavedWorkspaceState = Get-NormalizedStateObject -State $State
            $script:InitialWorkspaceState = $script:SavedWorkspaceState
            Update-WorkspaceState
            Log-Status (Get-LangValue -Key "RunFinishedBody" -Fallback "Selected operations completed. Review the status area for the final result.") "SUCCESS"
            return $true
        }

        $ProgressBar.Style = "Continuous"
        $ProgressBar.MarqueeAnimationSpeed = 0
        $ProgressBar.Value = 0
        return $false
    } finally {
        $script:ApplyInFlight = $false
        if ($BtnExec -and -not $Form.UseWaitCursor) { $BtnExec.Enabled = $true }
    }
}

function Show-FolderPicker {
    param([string]$Description, [string]$SelectedPath)
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    try {
        if ($Description) { $fbd.Description = $Description }
        if (-not [string]::IsNullOrWhiteSpace($SelectedPath) -and (Test-Path $SelectedPath)) { $fbd.SelectedPath = $SelectedPath }
        if ($fbd.ShowDialog($Form) -eq [System.Windows.Forms.DialogResult]::OK) { return $fbd.SelectedPath }
    } finally { $fbd.Dispose() }
    return $null
}

$BtnBrowse.Add_Click({
    $picked = Show-FolderPicker -Description "Select the JDownloader installation folder" -SelectedPath $TxtPath.Text
    if ($picked) { $TxtPath.Text = $picked }
})
$BtnDetect.Add_Click({
    $p = Detect-JDPath
    if ($p) { $TxtPath.Text = $p; Log-Status "Detected JDownloader at $p." "SUCCESS" }
    else    { Log-Status "JDownloader was not detected automatically on this machine." "WARN" }
})
$BtnDl.Add_Click({
    $picked = Show-FolderPicker -Description "Select the default download folder" -SelectedPath $TxtDl.Text
    if ($picked) { $TxtDl.Text = $picked }
})
$BtnOpenThm.Add_Click({
    if ([string]::IsNullOrWhiteSpace($TxtPath.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Set the JDownloader install folder first.", "Folder not found", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $path = Join-Path $TxtPath.Text 'themes\standard\org\jdownloader\images'
    if (Test-Path $path) {
        try { Invoke-Item $path } catch { Log-Status "Could not open $path : $_" "WARN" }
    } else {
        [System.Windows.Forms.MessageBox]::Show("No icon folder was found yet. Apply a theme first or point the app at an existing install.", "Folder not found", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
})
$LblThemeLink.Add_LinkClicked({
    $target = [string]$LblThemeLink.Tag
    if ([string]::IsNullOrWhiteSpace($target)) { return }
    # Only permit known URL schemes so a malformed Tag can't launch an arbitrary local file.
    if ($target -match '^https?://') {
        try { Start-Process $target | Out-Null } catch { Log-Status "Could not open link: $_" "WARN" }
    } else {
        Log-Status "Refused to open unsafe link target." "WARN"
    }
})
$CboGuiTheme.Add_SelectedIndexChanged({ Apply-GuiTheme -ThemeName $CboGuiTheme.Text; Update-WorkspaceState })
$CboLang.Add_SelectedIndexChanged({ Apply-LanguageData $CboLang.Text; Update-InterfaceText; Update-WorkspaceState })
$CboTheme.Add_SelectedIndexChanged({ Update-ThemePreview; Update-WorkspaceState })
$CboIcons.Add_SelectedIndexChanged({ Update-ThemeSelectionSummary; Update-WorkspaceState })
$CboMode.Add_SelectedIndexChanged({ Update-ModeSummary; Update-PathState; Update-WorkspaceState })
$TxtPath.Add_TextChanged({ Update-PathState; Update-WorkspaceState })
$TxtDl.Add_TextChanged({ Update-DownloadFolderState; Update-BehaviorProfile; Update-WorkspaceState })
$NumSim.Add_ValueChanged({ Update-BehaviorProfile; Update-WorkspaceState })
$NumPause.Add_ValueChanged({ Update-BehaviorProfile; Update-WorkspaceState })
$ChkWinDec.Add_CheckedChanged({ Update-ThemeSelectionSummary; Update-WorkspaceState })
$ChkMinLay.Add_CheckedChanged({ Update-ThemeSelectionSummary; Update-WorkspaceState })
$ChkMin.Add_CheckedChanged({ Update-BehaviorProfile; Update-WorkspaceState })
$ChkTray.Add_CheckedChanged({ Update-BehaviorProfile; Update-WorkspaceState })
$ChkCloseTray.Add_CheckedChanged({ Update-BehaviorProfile; Update-WorkspaceState })
$ChkExe.Add_CheckedChanged({ Update-HardeningProfile; Update-WorkspaceState })
$ChkUpdate.Add_CheckedChanged({ Update-HardeningProfile; Update-WorkspaceState })
$NumChunks.Add_ValueChanged({ Update-BehaviorProfile; Update-WorkspaceState })
$NumPerHost.Add_ValueChanged({ Update-BehaviorProfile; Update-WorkspaceState })
$ChkHashCheck.Add_CheckedChanged({ Update-BehaviorProfile; Update-WorkspaceState })
$ChkPreserveDate.Add_CheckedChanged({ Update-BehaviorProfile; Update-WorkspaceState })
$ChkClipboard.Add_CheckedChanged({ Update-BehaviorProfile; Update-WorkspaceState })
$ChkDisableAPI.Add_CheckedChanged({ Update-HardeningProfile; Update-WorkspaceState })
$ChkVmOptions.Add_CheckedChanged({ Update-HardeningProfile; Update-WorkspaceState })
$BtnLiveConnect.Add_Click({ Refresh-LiveApiQueue; Refresh-LiveCaptcha })
$BtnLiveRefresh.Add_Click({ Refresh-LiveApiQueue; Refresh-LiveCaptcha })
$BtnLiveStart.Add_Click({ Invoke-LiveApiAction -Action "Start" })
$BtnLivePause.Add_Click({ Invoke-LiveApiAction -Action "Pause" })
$BtnLiveStop.Add_Click({ Invoke-LiveApiAction -Action "Stop" })
$BtnLiveGrabberRefresh.Add_Click({
    if (-not $script:LiveApiClient) { Refresh-LiveApiQueue }
    if ($script:LiveApiClient) { Refresh-LiveLinkGrabber }
})
$BtnLiveAddLinks.Add_Click({ Send-LiveLinksToGrabber })
$BtnLiveCaptchaSolve.Add_Click({ Submit-LiveCaptchaAnswer })
$BtnLiveCaptchaSkip.Add_Click({ Skip-LiveCaptchaJob })
$BtnLiveCaptchaRefresh.Add_Click({ Refresh-LiveCaptcha })
$BtnRestoreWorkspace.Add_Click({
    if (-not $script:SavedWorkspaceState) { return }
    $shouldRestore = Show-ActionPrompt -Title "Restore last successful run" -Message "This replaces the current selections with the workspace that was last applied successfully." -ConfirmText "Restore selections" -ConfirmTag "PrimaryButton"
    if ($shouldRestore) {
        Apply-StateToControls -State $script:SavedWorkspaceState
        Log-Status "Workspace selections were restored from the last successful run." "SUCCESS"
    }
})
$BtnImportPreset.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    try {
        $dlg.Title = "Import workspace preset"
        $dlg.Filter = "JSON preset (*.json)|*.json|All files (*.*)|*.*"
        $dlg.CheckFileExists = $true
        if ($dlg.ShowDialog($Form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $presetState = Read-PresetFile -Path $dlg.FileName
            if ($presetState) {
                Apply-StateToControls -State $presetState
                Log-Status "Preset imported. Review the workspace before applying." "SUCCESS"
            }
        }
    } finally {
        $dlg.Dispose()
    }
})
$BtnExportPreset.Add_Click({
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    try {
        $dlg.Title = "Export workspace preset"
        $dlg.Filter = "JSON preset (*.json)|*.json|All files (*.*)|*.*"
        $dlg.DefaultExt = "json"
        $dlg.FileName = "jd2-ultimate-manager-preset.json"
        if ($dlg.ShowDialog($Form) -eq [System.Windows.Forms.DialogResult]::OK) {
            [void](Save-PresetFile -State (Get-CurrentGuiState) -Path $dlg.FileName)
        }
    } finally {
        $dlg.Dispose()
    }
})

foreach ($entry in $pages.GetEnumerator()) {
    $entry.Key.Add_Click({ Show-Page -Button $this })
}

$ToolTip.SetToolTip($BtnDashboard, "Open the dashboard overview page.")
$ToolTip.SetToolTip($BtnLiveControl, "Open live JDownloader queue and LinkGrabber controls.")
$ToolTip.SetToolTip($BtnInstallation, "Open installation path and mode options.")
$ToolTip.SetToolTip($BtnTheme, "Open themes, previews, and icon settings.")
$ToolTip.SetToolTip($BtnBehavior, "Open download and tray behavior settings.")
$ToolTip.SetToolTip($BtnHardening, "Open debloat and hardening options.")
$ToolTip.SetToolTip($BtnRepair, "Open repair and recovery tools.")
$ToolTip.SetToolTip($BtnDashInstallJump, "Jump straight to installation path and mode settings.")
$ToolTip.SetToolTip($BtnDashThemeJump, "Jump straight to theme previews and icon options.")
$ToolTip.SetToolTip($BtnDashRepairJump, "Jump straight to repair and recovery actions.")
$ToolTip.SetToolTip($BtnExec, "Apply the selected installation, theme, behavior, hardening, and repair settings in one run.")
$ToolTip.SetToolTip($CboMode, "Choose whether the tool should refine an existing install or run a fresh deployment flow.")
$ToolTip.SetToolTip($TxtPath, "Required for modify mode. Optional for clean install mode.")
$ToolTip.SetToolTip($TxtDl, "Leave blank to reset the download folder to JDownloader's default.")
$ToolTip.SetToolTip($CboGuiTheme, "Change the visual theme of this manager window.")
$ToolTip.SetToolTip($CboLang, "Change the language used by this manager window.")
$ToolTip.SetToolTip($BtnImportPreset, "Load workspace selections from a JSON preset.")
$ToolTip.SetToolTip($BtnExportPreset, "Save the current workspace selections as a JSON preset.")
$ToolTip.SetToolTip($BtnRestoreWorkspace, "Restore the last successful workspace selections and discard pending edits.")
$ToolTip.SetToolTip($CboTheme, "Pick the JDownloader look and feel that should be installed.")
$ToolTip.SetToolTip($CboIcons, "Icon packs can be changed independently from the theme preset.")
$ToolTip.SetToolTip($ChkWinDec, "Turns on custom window decorations when the theme supports them.")
$ToolTip.SetToolTip($ChkMinLay, "Tightens the main JDownloader tabs for a cleaner, lower-noise shell.")
$ToolTip.SetToolTip($NumChunks, "Split downloads into parallel segments. Higher values help on premium hosts. Default: 1.")
$ToolTip.SetToolTip($NumPerHost, "Max concurrent downloads from any single host. Useful with premium accounts.")
$ToolTip.SetToolTip($ChkHashCheck, "Verify downloaded file integrity using checksums when available.")
$ToolTip.SetToolTip($ChkPreserveDate, "Keep the original last-modified date from the server instead of the download date.")
$ToolTip.SetToolTip($ChkClipboard, "Automatically detect and queue download links copied to the clipboard.")
$ToolTip.SetToolTip($ChkExe, "Replaces the executable icon for a more cohesive dark desktop setup.")
$ToolTip.SetToolTip($ChkDisableAPI, "Disables the legacy local REST API (port 3128) that requires no authentication.")
$ToolTip.SetToolTip($ChkVmOptions, "Creates a JDownloader2.vmoptions file with JVM performance flags. Skipped if the file already exists.")
$ToolTip.SetToolTip($TxtLiveEndpoint, "Local default: http://127.0.0.1:3128. Enable JDownloader's deprecated local API first.")
$ToolTip.SetToolTip($BtnLiveConnect, "Connect to the configured JDownloader API endpoint.")
$ToolTip.SetToolTip($BtnLiveRefresh, "Refresh the download queue and connection status.")
$ToolTip.SetToolTip($BtnLiveStart, "Start all eligible JDownloader downloads.")
$ToolTip.SetToolTip($BtnLivePause, "Pause the JDownloader download controller.")
$ToolTip.SetToolTip($BtnLiveStop, "Stop the JDownloader download controller.")
$ToolTip.SetToolTip($TxtLiveLinks, "Paste one or more HTTP, HTTPS, FTP, magnet, file, or jdlist links.")
$ToolTip.SetToolTip($BtnLiveAddLinks, "Send pasted URLs to LinkGrabber.")
$ToolTip.SetToolTip($LiveCaptchaImage, "Captcha image supplied by JDownloader.")
$ToolTip.SetToolTip($TxtLiveCaptchaAnswer, "Enter the captcha answer shown by JDownloader.")
$ToolTip.SetToolTip($BtnLiveCaptchaSolve, "Submit the captcha answer to JDownloader.")
$ToolTip.SetToolTip($BtnLiveCaptchaSkip, "Skip the current captcha job.")
$ToolTip.SetToolTip($BtnLiveCaptchaRefresh, "Refresh pending captcha prompts.")


$Form.Add_Load({
    Sync-PageCanvases
    Resize-ThemePreview
    Layout-Footer

    $CboGuiTheme.SelectedIndex = 0
    if ($CboLang.Items.Count -gt 0) { $CboLang.SelectedItem = $CurrentLangCode }
    if ($CboIcons.Items.Count -gt 0) { $CboIcons.SelectedIndex = 0 }
    if ($CboTheme.Items.Count -gt 0) { $CboTheme.SelectedIndex = 0 }
    $CboMode.SelectedIndex = 0

    $sysTheme = Detect-SystemTheme
    if ($CboGuiTheme.Items.Contains($sysTheme)) { $CboGuiTheme.SelectedItem = $sysTheme }

    $saved = Load-Settings
    $resumeState = Load-ResumeState -Path $script:ResumeStateFile
    $detected = Detect-JDPath
    if ($resumeState) {
        Apply-StateToControls -State $resumeState
    } elseif ($saved) {
        Apply-StateToControls -State $saved
        if ([string]::IsNullOrWhiteSpace($TxtPath.Text) -and $detected) { $TxtPath.Text = $detected }
    } elseif ($detected) {
        $TxtPath.Text = $detected
        $CboMode.SelectedIndex = 0
    } else {
        $CboMode.SelectedIndex = 1
    }

    if ($resumeState) {
        Log-Status "Workspace restored after administrative approval." "INFO"
    } elseif ($detected) {
        Log-Status "JDownloader was detected successfully." "SUCCESS"
    } else {
        Log-Status "JDownloader was not detected. Clean install mode is ready." "INFO"
    }

    Configure-DirectoryInput -TextBox $TxtPath -CueText "Required for modify mode. Optional for clean install mode."
    Configure-DirectoryInput -TextBox $TxtDl -CueText "Leave blank to reset to JDownloader's default download folder."
    Apply-AccessibilityMetadata
    Apply-GuiTheme -ThemeName $CboGuiTheme.Text
    Update-ModeSummary
    Update-PathState
    Update-DownloadFolderState
    Update-BehaviorProfile
    Update-ThemePreview
    Update-HardeningProfile
    Show-Page -Button $BtnDashboard
    $script:InitialWorkspaceState = Get-NormalizedStateObject -State (Get-CurrentGuiState)
    if ($saved) { $script:SavedWorkspaceState = Get-NormalizedStateObject -State $saved } else { $script:SavedWorkspaceState = $null }
    $script:IsBootstrapping = $false
    Update-WorkspaceState
    Start-ThemeImagePreload -Definitions $ThemeDefinitions
    if ($script:LiveApiPollTimer) { $script:LiveApiPollTimer.Start() }
})

# Debounce the resize handler: Form fires Resize per drag-pixel, which was causing the full
# page-canvas + theme preview + footer layout to run 100+ times during a single drag. A 60ms
# throttle batches the bursts and runs the heavy layout once the user pauses.
$script:ResizeDebounceTimer = New-Object System.Windows.Forms.Timer
$script:ResizeDebounceTimer.Interval = 60
$script:ResizeDebounceTimer.Add_Tick({
    param($src, $evt)
    try { $src.Stop() } catch {}
    try { Sync-PageCanvases } catch {}
    try { Resize-ThemePreview } catch {}
    try { Layout-Footer } catch {}
})
[void]$GlobalTimers.Add($script:ResizeDebounceTimer)
$Form.Add_Resize({
    if ($script:ResizeDebounceTimer) {
        $script:ResizeDebounceTimer.Stop()
        $script:ResizeDebounceTimer.Start()
    }
})
$Form.Add_Shown({
    if ($script:ResumeApplyRequested) {
        $script:ResumeApplyRequested = $false
        Log-Status "Administrative approval granted. Review the confirmation dialog to continue." "INFO"
        Start-WorkspaceApply | Out-Null
    }
})
$Form.Add_FormClosing({
    param($src, $evt)
    if ($Form.UseWaitCursor) {
        $evt.Cancel = $true
        return
    }
    if ($LogoBox -and $LogoBox.Image) { try { $LogoBox.Image.Dispose() } catch {} }
    Cleanup-Resources
})

$BtnExec.Add_Click({ Start-WorkspaceApply | Out-Null })

[void]$Form.ShowDialog()
