<#
.SYNOPSIS
    JDownloader 2 ULTIMATE MANAGER (v13.4.4 - STABLE REPAIR)
    - FIXED: Constructor overload errors in System.Drawing.Size and Point.
    - FIXED: Arithmetic parsing issues causing argument count mismatches.
    - FIXED: Null reference exceptions on event handlers.
    - Architecture: WinForms GUI, JSON Settings Persistence, Robust Logging.
#>

# ==========================================
# 0. PRE-FLIGHT CHECKS & HARDENING
# ==========================================
# Enforce TLS 1.2 for all web requests immediately
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ==========================================
# 1. INITIALIZATION & ELEVATION
# ==========================================
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrative Privileges..." -ForegroundColor Yellow
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = "powershell.exe"
    $processInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $processInfo.Verb = "RunAs"
    try {
        [System.Diagnostics.Process]::Start($processInfo) | Out-Null
    } catch {
        Write-Error "Failed to elevate privileges. $_"
    }
    Exit
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
$AppDataDir   = "$env:ProgramData\JD2-Ultimate-Manager"
$LogDir       = "$AppDataDir\Logs"
$WorkDir      = "$env:TEMP\JD2_Ult_Tool_v13_0"
$SettingsFile = "$AppDataDir\settings.json"
$VersionFile  = "$AppDataDir\version.json"
$LangFile     = "$AppDataDir\lang.json"

# Ensure directories exist with error handling
foreach ($path in @($AppDataDir, $LogDir, $WorkDir)) {
    if (-not (Test-Path $path)) { 
        try { New-Item -ItemType Directory -Path $path -Force | Out-Null } catch {} 
    }
}

$LogFile     = "$LogDir\$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
$StatusLabel = $null
$ProgressBar = $null

# ToolTip helper
$ToolTip = New-Object System.Windows.Forms.ToolTip
$ToolTip.AutoPopDelay = 5000
$ToolTip.InitialDelay = 1000
$ToolTip.ReshowDelay = 500

# Language Registry for live updates
$LanguageRegistry = @()

# Global tracking for cleanup
$GlobalJobs = @{}
$GlobalTimers = @()
$ThemeImageCache = @{}
$script:CurrentGuiTheme = "Dark (Default)"
$script:LastStatusText = "Ready"
$script:LastStatusType = "INFO"
$script:InitialWorkspaceState = $null
$script:SavedWorkspaceState = $null
$script:IsBootstrapping = $true

# ==========================================
# 3. LANGUAGE & GUI THEME ENGINE
# ==========================================

# --- Default English Fallback ---
$DefaultLang = [ordered]@{
    "Title" = "JDownloader 2 Ultimate Manager v13.4";
    "Dashboard" = "Dashboard"; "Installation" = "Installation"; "Themes" = "Themes"; 
    "Behavior" = "Behavior"; "Hardening" = "Hardening"; "Repair" = "Repair Tools";
    "Execute" = "EXECUTE ALL OPERATIONS"; "Status" = "Status: Ready";
    "Running" = "Applying changes...";
    "FooterSummary" = "Apply every selected change in a single, predictable run.";
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
    "DashSub" = "One panel to install, theme, debloat, harden and repair JDownloader 2.";
    "DashHint" = "Tip: Select options from the sidebar, then click 'Execute All Operations' below.";
    "InstTitle" = "Installation Options";
    "InstSub" = "Choose how this tool interacts with JDownloader 2 on this machine.";
    "InstPath" = "JDownloader installation folder:";
    "Browse" = "Browse..."; "AutoDetect" = "Auto-Detect";
    "InstMode" = "Installation mode:";
    "InstModeHelp" = "If no installation is found, the tool will automatically perform a clean install from GitHub.";
    "ThemeTitle" = "Theme and Appearance";
    "ThemeSub" = "Pick how JDownloader looks. Preview thumbnails and open the theme project on GitHub.";
    "ThemePreset" = "Theme preset:";
    "OpenGithub" = "Open theme on GitHub";
    "EnableWinDec" = "Enable custom window decorations";
    "CompactTabs" = "Compact main tabs (minimal layout)";
    "IconPack" = "Icon pack:"; "OpenIconFolder" = "Open icon folder";
    "BehTitle" = "Behavior Settings";
    "BehSub" = "Tune how JDownloader downloads, pauses, and minimizes.";
    "MaxSim" = "Max simultaneous downloads:";
    "MaxSimHelp" = "Higher values use more bandwidth and connections. 3 to 5 is usually a good balance.";
    "PauseSpeed" = "Pause speed (bytes per second):";
    "PauseHelp" = "10240 bytes per second is a near stop.";
    "DefDlFolder" = "Default download folder:";
    "StartMin" = "Start minimized";
    "MinToTray" = "Minimize to tray instead of taskbar";
    "CloseToTray" = "Close button sends JDownloader to tray";
    "HardTitle" = "Hardening and Security";
    "HardSub" = "These options refine the shell experience. Debloating and ad removal are always on.";
    "DarkExe" = "Darken JDownloader executables with a custom icon";
    "RunUpdate" = "Run JDownloader update after operations";
    "HardNote" = "Note: Contribute panel, premium ads, news popups, MyJD promos and banners are always turned off.";
    "RepTitle" = "Repair and Maintenance";
    "RepSub" = "Use these tools if JDownloader is acting strange, corrupted, or you need a clean start.";
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

function Load-Language {
    $langUrl = "https://raw.githubusercontent.com/SysAdminDoc/JDownloader-2-Ultimate-Manager/refs/heads/main/Translations/lang.json"
    $userLang = (Get-Culture).TwoLetterISOLanguageName 
    
    try {
        Invoke-WebRequest -Uri $langUrl -OutFile $LangFile -UseBasicParsing -ErrorAction SilentlyContinue
        if (Test-Path $LangFile) {
            $json = Get-Content $LangFile -Raw -Encoding UTF8 | ConvertFrom-Json
            
            # Store all available languages for dropdown
            $json.PSObject.Properties | ForEach-Object {
                $AvailableLanguages[$_.Name] = $_.Value
            }

            # Auto-detect logic
            if ($AvailableLanguages.ContainsKey($userLang)) {
                $CurrentLangCode = $userLang
                Apply-LanguageData $userLang
            } elseif ($AvailableLanguages.ContainsKey("en")) {
                $CurrentLangCode = "en"
                Apply-LanguageData "en"
            }
        } else {
            $AvailableLanguages["en"] = $DefaultLang
        }
    } catch {
        $AvailableLanguages["en"] = $DefaultLang
    }
}

function Apply-LanguageData {
    param($Code)
    if ($AvailableLanguages.ContainsKey($Code)) {
        $dict = $AvailableLanguages[$Code]
        foreach ($key in $dict.PSObject.Properties.Name) {
            $Lang[$key] = $dict.$key
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
    if (-not $Key) { return }
    $script:LanguageRegistry += @{ Control = $Control; Key = $Key }
    # Set initial text
    if ($Lang.Contains($Key)) {
        $Control.Text = $Lang[$Key]
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
{ "overviewpaneldownloadlinksfailedcountvisible": false, "downloadview": "ALL", "linkpropertiespaneldownloadpasswordvisible": true, "speedmetervisible": true, "overviewpaneldownloadpackagecountvisible": true, "linkpropertiespanelfilenamevisible": true, "titlepattern": "|#TITLE|| - #SPEED/s|| - #UPDATENOTIFY|", "overviewpaneltotalinfovisible": true, "linkpropertiespanelchecksumvisible": true, "downloadspropertiespanelsavetovisible": true, "packagesbackgroundhighlightenabled": true, "overviewpaneldownloadlinkcountvisible": true, "downloadspropertiespanelpackagenamevisible": true, "overviewpaneldownloadlinksfinishedcountvisible": false, "overviewpanelsmartinfovisible": true, "availablecolumntextvisible": false, "overviewpaneldownloadbytesremainingvisible": true, "bannerenabled": false, "showfullhostname": false, "overviewpanellinkgrabberstatusonlinevisible": true, "linkpropertiespanelcommentvisible": true, "clipboardmonitored": true, "donatebuttonstate": "CUSTOM_HIDDEN", "donatebuttonlatestautochange": 1764274189351, "filecountinsizecolumnvisible": true, "clipboardskipmode": "ON_STARTUP", "premiumexpirewarningenabled": false, "downloadstablerefreshinterval": 1000, "overviewpaneldownloadpanelincludedisabledlinks": true, "tablewraparoundenabled": true, "specialdealoboomdialogvisibleonstartup": false, "tooltipenabled": true, "statusbaraddpremiumbuttonvisible": false, "captchadialogborderaroundimageenabled": true, "tablemouseoverhighlightenabled": true, "linkpropertiespanelsavetovisible": true, "overviewpanellinkgrabberlinkscountvisible": true, "clipboardmonitorprocesshtmlflavor": true, "overviewpanelselectedinfovisible": true, "linkpropertiespaneldownloadfromvisible": false, "sortcolumnhighlightenabled": true, "colorediconsfordisabledhostercolumnenabled": true, "premiumalertspeedcolumnenabled": false, "downloadspropertiespanelcommentvisible": true, "overviewpaneldownloadtotalbytesvisible": true, "overviewpanellinkgrabberpackagecountvisible": true, "windowswindowmanagerforegroundlocktimeout": 2147483647, "linkgrabbertabpropertiespanelvisible": true, "configviewvisible": true, "downloadstabpropertiespanelvisible": true, "selecteddownloadsearchcategory": "FILENAME", "overviewpaneldownloadetavisible": true, "savedownloadviewcrosssessionenabled": false, "overviewpanellinkgrabberstatusunknownvisible": true, "myjdownloaderviewvisible": false, "downloadspropertiespanelchecksumvisible": true, "downloadspropertiespanelfilenamevisible": false, "speedmetertimeframe": 30000, "mainwindowalwaysontop": false, "overviewpaneldownloadconnectionsvisible": true, "helpdialogsenabled": false, "lookandfeeltheme": "FLATLAF_DARK", "linkpropertiespanelarchivepasswordvisible": true, "horizontalscrollbarsinlinkgrabbertableenabled": false, "downloadspropertiespaneldownloadfromvisible": false, "overviewpanellinkgrabberstatusofflinevisible": true, "balloonnotificationenabled": true, "activeconfigpanel": "jd.gui.swing.jdgui.views.settings.panels.advanced.AdvancedSettings", "donationnotifyid": null, "speedmeterframespersecond": 4, "linkpropertiespanelpackagenamevisible": true, "passwordprotectionenabled": false, "specialdealsenabled": false, "overviewpaneldownloadspeedvisible": true, "premiumstatusbardisplay": "GROUP_BY_ACCOUNT_TYPE", "maxsizeunit": "TiB", "downloadpaneloverviewsettingsvisible": false, "tooltipdelay": 2000, "overviewpaneldownloadbytesloadedvisible": true, "speedinwindowtitle": "WHEN_WINDOW_IS_MINIMIZED", "overviewpanellinkgrabbertotalbytesvisible": true, "selectedlinkgrabbersearchcategory": "FILENAME", "downloadtaboverviewvisible": true, "rlywarnlevel": "NORMAL", "overviewpanellinkgrabberhostercountvisible": true, "downloadspropertiespaneldownloadpasswordvisible": true, "dialogdefaulttimeoutinms": 20000, "overviewpanellinkgrabberincludedisabledlinks": true, "hidesinglechildpackages": false, "linkgrabberbottombarposition": "SOUTH", "linkgrabbertaboverviewvisible": true, "overviewpaneldownloadlinksskippedcountvisible": false, "windowswindowmanageraltkeyworkaroundenabled": true, "updatebuttonflashingenabled": false, "overviewpanelvisibleonlyinfovisible": true, "linkgrabbersidebarvisible": true, "downloadspropertiespanelarchivepasswordvisible": true, "captchaexchangeenabled": false }
'@
$Template_General = '{"maxsimultanedownloadsperhost":1,"delaywritemode":"AUTO","iffileexistsaction":"ASK_FOR_EACH_FILE","dupemanagerenabled":true,"forcemirrordetectioncaseinsensitive":true,"autoopencontainerafterdownload":true,"preferbouncycastlefortls":false,"autostartdownloadoption":"ONLY_IF_EXIT_WITH_RUNNING_DOWNLOADS","maxsimultanedownloads":3,"pausespeed":10240,"defaultdownloadfolder":"C:\\Downloads","windowsjnaidledetectorenabled":true,"downloadspeedlimitrememberedenabled":true,"closedwithrunningdownloads":false,"autostartcountdownseconds":10,"maxdownloadsperhostenabled":false,"maxchunksperfile":1,"sambaprefetchenabled":true,"showcountdownonautostartdownloads":true,"savelinkgrabberlistenabled":true,"onskipduetoalreadyexistsaction":"SKIP_FILE","hashretryenabled":false,"sharedmemorystateenabled":false,"convertrelativepathsjdroot":true,"keepxoldlists":5,"useavailableaccounts":true,"cleanupafterdownloadaction":"REMOVE_FINISHED_AND_DELETE_EXTRACTED","hashcheckenabled":true,"downloadspeedlimitenabled":false,"downloadspeedlimit":51200,"hidesinglechildpackages":true}'
$Template_Tray = '{"freshinstall":false,"onminimizeaction":"TO_TASKBAR","tooltipenabled":true,"trayiconclipboardindicatorenabled":false,"oncloseaction":"ASK","tooglewindowstatuswithsingleclickenabled":false,"greyiconenabled":false,"gnometrayicontransparentenabled":true,"enabled":true,"startminimizedenabled":false,"trayonlyvisibleifwindowishiddenenabled":false}'

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
    try { $SettingsObj | ConvertTo-Json -Depth 5 | Set-Content $SettingsFile -Encoding UTF8 } catch { Log-Status "Failed to save settings: $_" "ERROR" }
}

function Load-Settings {
    if (Test-Path $SettingsFile) { try { return Get-Content $SettingsFile -Raw | ConvertFrom-Json } catch { return $null } }
    return $null
}

function Download-File {
    param([string]$Url, [string]$Destination)
    Log-Status "Downloading: $(Split-Path $Destination -Leaf)"
    
    $maxRetries = 3
    $attempt = 0
    $success = $false

    while ($attempt -lt $maxRetries -and -not $success) {
        $attempt++
        try {
            if (-not (Get-Module -Name BitsTransfer -ListAvailable)) { Import-Module BitsTransfer -ErrorAction Stop }
            Start-BitsTransfer -Source $Url -Destination $Destination -ErrorAction Stop -Priority Foreground
            $success = $true
        } catch {
            Log-Status "BITS attempt $attempt failed: $_" "WARN"
            try {
                Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop
                $success = $true
            } catch {
                Log-Status "WebClient attempt $attempt failed from $Url. $_" "WARN"
            }
        }
        
        if (-not $success -and $attempt -lt $maxRetries) {
            $delay = $attempt * 1500
            Start-Sleep -Milliseconds $delay
        }
    }
    
    # Added file size/integrity check (basic)
    if ($success -and (Test-Path $Destination)) {
        $size = (Get-Item $Destination).Length
        if ($size -lt 1024) { 
            Log-Status "Downloaded file is suspiciously small ($size bytes). marking failed." "ERROR"
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
        }
    }
    return $seven
}

# Enhanced Async Job Manager
function Start-ThemeImagePreload {
    param($Definitions)
    Log-Status "Starting background theme fetch..."
    
    # Clean old job if exists
    if ($GlobalJobs["ThemeFetcher"]) { Remove-Job -Job $GlobalJobs["ThemeFetcher"] -Force -ErrorAction SilentlyContinue }
    
    $jobScript = {
        param($defs)
        $results = @{}
        $web = New-Object System.Net.WebClient
        foreach ($key in $defs.Keys) {
            $url = $defs[$key].PreviewUrl
            if ($url) {
                try {
                    $bytes = $web.DownloadData($url)
                    $results[$key] = $bytes
                } catch { $results[$key] = $null }
            }
        }
        return $results
    }

    $j = Start-Job -ScriptBlock $jobScript -ArgumentList $Definitions -Name "ThemeFetcher"
    $GlobalJobs["ThemeFetcher"] = $j
    
    $checkTimer = New-Object System.Windows.Forms.Timer
    $checkTimer.Interval = 500
    # Use closure to ensure variable safety or explicit ref
    $checkTimer.Add_Tick({
        param($sender, $e)
        $j = Get-Job -Name "ThemeFetcher" -ErrorAction SilentlyContinue
        if ($j -and $j.State -eq "Completed") {
            $sender.Stop()
            $sender.Dispose()
            try {
                $res = Receive-Job -Job $j
                Remove-Job -Job $j
                
                # Process images
                foreach ($k in $res.Keys) {
                    if ($res[$k]) {
                        $ms = New-Object System.IO.MemoryStream(,$res[$k])
                        $img = $null
                        $cacheImg = $null
                        try {
                            $img = [System.Drawing.Image]::FromStream($ms)
                            $cacheImg = New-Object System.Drawing.Bitmap($img)
                            if ($script:ThemeImageCache.ContainsKey($k)) { $script:ThemeImageCache[$k].Dispose() }
                            $script:ThemeImageCache[$k] = $cacheImg
                        } finally {
                            if ($img) { $img.Dispose() }
                            $ms.Dispose()
                        }
                    }
                }
                Log-Status "Theme previews loaded." "SUCCESS"
                if ($CboTheme -and $CboTheme.IsHandleCreated) {
                    $CboTheme.Invoke([Action]{ Update-ThemePreview }) 
                }
            } catch {
                Log-Status "Error processing theme images: $_" "ERROR"
            }
        } elseif (-not $j) {
            $sender.Stop()
        }
    })
    $GlobalTimers += $checkTimer
    $checkTimer.Start()
}

# Cleanup Helper
function Cleanup-Resources {
    Log-Status "Cleaning up resources..."
    foreach ($t in $GlobalTimers) { if($t){$t.Stop(); $t.Dispose()} }
    foreach ($j in $GlobalJobs.Values) { if($j){Stop-Job $j -ErrorAction SilentlyContinue; Remove-Job $j -ErrorAction SilentlyContinue} }
    foreach ($img in $ThemeImageCache.Values) { if($img){$img.Dispose()} }
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
        $StatusLabel.Invoke([Action[string, object, string]]{
            param($t, $c, $pfx)
            $StatusLabel.Text = "${pfx}: $t"
            $StatusLabel.ForeColor = $c
        }, $Text, $statusColor, $prefix)
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

    if ($Root) {
        $Root.BackColor = $pal.FormBack
        $Root.ForeColor = $pal.Fore
    }
    
    function Update-Control {
        param($ctrl)
        
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
            $ctrl.FlatAppearance.BorderSize = 0
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
        
        if ($ctrl.Controls) {
            foreach ($c in $ctrl.Controls) { Update-Control $c }
        }
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
    $paths = @("C:\Program Files\JDownloader", "C:\Program Files (x86)\JDownloader", "$env:LOCALAPPDATA\JDownloader 2", "$env:USERPROFILE\AppData\Local\JDownloader 2.0")
    foreach ($p in $paths) { if (Test-Path (Join-Path $p "JDownloader2.exe")) { return $p } }
    return $null
}

# Safer path-based kill logic
function Kill-JDownloader {
    Log-Status "Terminating JDownloader processes..."
    $procs = Get-Process -Name "javaw", "JDownloader2" -ErrorAction SilentlyContinue
    
    foreach ($p in $procs) {
        try {
            $path = $p.MainModule.FileName
            if ($path -match "JDownloader") {
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {
             if ($p.ProcessName -eq "JDownloader2") { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
        }
    }
    Start-Sleep -Seconds 1
}

# Exclude more temp folders
function Backup-JD {
    param([string]$InstallPath)
    $stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $backupRoot = "$InstallPath\cfg-backup\$stamp"
    if (Test-Path "$InstallPath\cfg") {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        Get-ChildItem "$InstallPath\cfg" -Exclude "tmp","logs","*.part","*.tmp","linkcollector" | Copy-Item -Destination $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Task-ExtractIcons {
    param($ZipUrl, $InstallPath, $TargetIconSet)
    $localZip = "$WorkDir\icons.7z"
    $extractPath = "$WorkDir\IconsTemp"
    if (-not (Download-File -Url $ZipUrl -Destination $localZip)) { return }
    $seven = Get-7Zip
    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue }
    Start-Process $seven -ArgumentList "x `"$localZip`" -o`"$extractPath`" -y" -Wait -WindowStyle Hidden
    $foundImages = Get-ChildItem -Path $extractPath -Recurse -Directory | Where-Object { $_.Name -eq "images" } | Select-Object -First 1
    if ($foundImages) {
        $targetImages = "$InstallPath\themes\$TargetIconSet\org\jdownloader\images"
        if (-not (Test-Path $targetImages)) { New-Item -ItemType Directory -Path $targetImages -Force | Out-Null }
        Copy-Item "$($foundImages.FullName)\*" $targetImages -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Task-PatchLaf {
    param($JsonPath, $IconSetId, $WindowDecorations)
    try {
        $content = Get-Content -Path $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $content.PSObject.Properties["iconsetid"]) { $content | Add-Member -MemberType NoteProperty -Name "iconsetid" -Value $IconSetId } else { $content.iconsetid = $IconSetId }
        if (-not $content.PSObject.Properties["windowdecorationenabled"]) { $content | Add-Member -MemberType NoteProperty -Name "windowdecorationenabled" -Value $WindowDecorations } else { $content.windowdecorationenabled = $WindowDecorations }
        $content | ConvertTo-Json -Depth 100 | Set-Content $JsonPath -Encoding UTF8
    } catch {}
}

function Task-NukeBanners {
    param($InstallPath)
    Add-Type -AssemblyName System.Drawing
    $themeDir = "$InstallPath\themes"
    if (Test-Path $themeDir) {
        Get-ChildItem -Path $themeDir -Recurse -Filter "*.png" | Where-Object { $_.Directory.Name -eq "banner" } | ForEach-Object {
            try {
                $img = [System.Drawing.Image]::FromFile($_.FullName); $w = $img.Width; $h = $img.Height; $img.Dispose()
                $bmp = New-Object System.Drawing.Bitmap($w, $h)
                $bmp.Save($_.FullName, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
            } catch {}
        }
    }
}

function Task-PatchExeIcon {
    param($InstallPath)
    Log-Status "Applying dark icon..."
    $ResHackerZip = "$WorkDir\resource_hacker.zip"; $ResHackerDir = "$WorkDir\ResourceHacker"; $IconFile = "$WorkDir\jd_dark.ico"
    if (-not (Download-File -Url "https://www.angusj.com/resourcehacker/resource_hacker.zip" -Destination $ResHackerZip)) { return }
    if (-not (Download-File -Url "https://raw.githubusercontent.com/SysAdminDoc/JDownloaderDarkMode/refs/heads/main/Icons/icon.ico" -Destination $IconFile)) { return }
    if (-not (Test-Path $ResHackerDir)) { Expand-Archive -Path $ResHackerZip -DestinationPath $ResHackerDir -Force }
    $ResHackerExe = "$ResHackerDir\ResourceHacker.exe"
    if (Test-Path $ResHackerExe) {
        $targets = @("$InstallPath\JDownloader2.exe", "$InstallPath\Uninstall JDownloader.exe")
        foreach ($exe in $targets) {
            # Check write permission/existence first
            if (Test-Path $exe) {
                try {
                    Stop-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($exe)) -Force -ErrorAction SilentlyContinue; Start-Sleep 1
                    $bak = "$exe.bak"; if (-not (Test-Path $bak)) { Move-Item -Path $exe -Destination $bak -Force } else { Remove-Item $exe -Force -ErrorAction SilentlyContinue }
                    Start-Process -FilePath $ResHackerExe -ArgumentList "-open `"$bak`" -save `"$exe`" -action addoverwrite -res `"$IconFile`" -mask ICONGROUP,MAINICON,0" -Wait -WindowStyle Hidden
                } catch { Log-Status "Failed to patch $exe - Access Denied?" "WARN" }
            }
        }
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue; Start-Sleep 1; Start-Process explorer.exe
    }
}

function Set-JsonConfig {
    param($Path, $DataHash)
    try { $DataHash | ConvertTo-Json -Depth 100 | Set-Content $Path -Encoding UTF8 } catch {}
}

function Task-DeepHardening {
    param($cfgPath)
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.settings.AdvancedConfig.json" -DataHash @{"org.jdownloader.gui.jdgui.settings.AboutConfigPanel.contributepanelvisible"=$false}
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.controlling.WidgetStateManager.json" -DataHash @{"contributepanelvisible"=$false}
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.gui.jdgui.views.jdgui.GUILayout.json" -DataHash @{"contributepanel_visible"=$false}
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.settings.advanced.AdvancedSettings.json" -DataHash @{"contributepanel_enabled"=$false}
}

function Task-Install {
    param($Source)
    if ($Source -eq "GitHub") {
        $seven = Get-7Zip
        $baseUrl = "https://github.com/SysAdminDoc/JDownloaderDarkMode/raw/main/Installer/installer.7z"
        for ($i = 1; $i -le 7; $i++) {
            $part = ".{0:D3}" -f $i
            if (-not (Download-File -Url "$baseUrl$part" -Destination "$WorkDir\installer.7z$part")) {
                Log-Status "Installer download failed on part $part." "ERROR"
                return $false
            }
        }
        Start-Process $seven -ArgumentList "x `"$WorkDir\installer.7z.001`" -o`"$WorkDir\Installer`" -y" -Wait -WindowStyle Hidden
        $setup = Get-ChildItem "$WorkDir\Installer" -Filter "*.exe" -Recurse | Select-Object -First 1
        if ($setup) {
            Start-Process $setup.FullName -ArgumentList "-q" -Wait
            return $true
        }
        Log-Status "Installer extraction completed, but no setup executable was found." "ERROR"
    } elseif ($Source -eq "Mega") {
        Start-Process "https://mega.nz/file/PQ0XRIrA#-uuhLXSc_nPfotXWfBWDZRx90Gnehx2_Mx_JVufzfdM"
        [System.Windows.Forms.MessageBox]::Show("Download the file from Mega, then click OK.", "Manual Download") | Out-Null
        $f = Get-ChildItem "$env:USERPROFILE\Downloads" -Filter "JDownloader*Setup*.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($f) {
            Start-Process $f.FullName -ArgumentList "-q" -Wait
            return $true
        }
        Log-Status "Mega installer was not found in Downloads after the manual step." "ERROR"
    }
    return $false
}

function Task-FullUninstall {
    param($InstallPath)
    Kill-JDownloader
    if (Test-Path "$InstallPath\Uninstall JDownloader.exe") { Start-Process -FilePath "$InstallPath\Uninstall JDownloader.exe" -ArgumentList "-q" -Wait }
    Start-Sleep 2; Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
}

function Trigger-Update {
    param($InstallPath)
    if (Test-Path "$InstallPath\JDownloader2.exe") { Start-Process -FilePath "$InstallPath\JDownloader2.exe" -ArgumentList "-update" }
}

function Run-Audit {
    param($InstallPath)
    $issues = 0
    if (-not (Test-Path "$InstallPath\cfg\org.jdownloader.settings.GeneralSettings.json")) { $issues++ }
    if ($issues -gt 0) { Log-Status "Audit found $issues issues." "WARN" } else { Log-Status "Audit passed." "SUCCESS" }
}

function Execute-Operations {
    param($GUI_State)
    $JDPath = $GUI_State.InstallPath
    if ($GUI_State.Mode -eq "Modify" -and [string]::IsNullOrWhiteSpace($JDPath)) {
        Log-Status "Select an existing JDownloader folder before running modify mode." "ERROR"
        return $false
    }
    
    # Catch-all error trap
    try {
        if ($GUI_State.Mode -ne "Modify") {
            $selectedSource = if ($GUI_State.InstallSource) { $GUI_State.InstallSource } else { "GitHub" }
            $installSucceeded = Task-Install -Source $selectedSource

            if (-not $installSucceeded -and $selectedSource -eq "GitHub") {
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
                $guiObj | ConvertTo-Json -Depth 100 | Set-Content "$cfgPath\org.jdownloader.settings.GraphicalUserInterfaceSettings.json" -Encoding UTF8
            } catch {}
        }

        try {
            $genObj = $Template_General | ConvertFrom-Json
            $genObj.maxsimultanedownloads = [int]$GUI_State.MaxSim
            if ([string]::IsNullOrWhiteSpace($GUI_State.DlFolder)) {
                $null = $genObj.PSObject.Properties.Remove("defaultdownloadfolder")
            } else {
                $genObj.defaultdownloadfolder = $GUI_State.DlFolder.Replace("\", "\\")
            }
            $genObj.pausespeed = [int]$GUI_State.PauseSpeed
            $genObj | ConvertTo-Json -Depth 100 | Set-Content "$cfgPath\org.jdownloader.settings.GeneralSettings.json" -Encoding UTF8
        } catch {}

        try {
            $trayObj = $Template_Tray | ConvertFrom-Json
            $trayObj.startminimizedenabled = $GUI_State.StartMin
            $trayObj.onminimizeaction = if ($GUI_State.MinToTray) { "TO_TASKBAR_IF_ALLOWED" } else { "TO_TASKBAR" }
            if ($GUI_State.ContainsKey("CloseToTray")) { $trayObj.oncloseaction = if ($GUI_State.CloseToTray) { "TO_TASKBAR" } else { "ASK" } }
            $trayObj | ConvertTo-Json -Depth 100 | Set-Content "$cfgPath\org.jdownloader.gui.jdtrayicon.TrayExtension.json" -Encoding UTF8
        } catch {}

        Task-DeepHardening -cfgPath $cfgPath
        if ($GUI_State.ForceMinimal) { Set-JsonConfig -Path "$cfgPath\org.jdownloader.gui.jdgui.settings.MainTabLayout.json" -DataHash @{compactmodetabs=$true; hidemyjdtab=$true} }
        Task-NukeBanners -InstallPath $JDPath
        if ($GUI_State.PatchExe) { Task-PatchExeIcon -InstallPath $JDPath }
        
        $ProgressBar.Style = "Continuous"; $ProgressBar.MarqueeAnimationSpeed = 0; $ProgressBar.Value = 100
        Log-Status "Operations completed." "SUCCESS"
        if ($GUI_State.AutoUpdate) { Trigger-Update -InstallPath $JDPath }
        Save-Settings -SettingsObj $GUI_State
        return $true
    } catch {
        $ProgressBar.Style = "Continuous"; $ProgressBar.MarqueeAnimationSpeed = 0; $ProgressBar.Value = 0
        Log-Status "CRITICAL ERROR: $_" "FATAL"
        Log-Status $($_.ScriptStackTrace) "DEBUG"
        [System.Windows.Forms.MessageBox]::Show("An error occurred during execution. check logs. `nError: $_", "Error")
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

$script:PageRegistry = @()

function New-PagePanel {
    param([int]$CanvasHeight = 900)
    $p = New-Panel -Dock "Fill" -Tag "Page"
    $p.Visible = $false
    $p.AutoScroll = $true
    $canvas = New-Panel -Name "Canvas" -Parent $p -Location (New-Object System.Drawing.Point(24, 18)) -Size (New-Object System.Drawing.Size(1040, $CanvasHeight)) -Tag "Canvas"
    $p.AutoScrollMinSize = New-Object System.Drawing.Size(1064, [Math]::Max(0, $CanvasHeight + 36))
    $script:PageRegistry += $p
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
        $canvas.Left = [Math]::Max(18, [int](($Page.ClientSize.Width - $canvas.Width) / 2))
        $canvas.Top = 18
    }
}

function Sync-PageCanvases {
    foreach ($page in $script:PageRegistry) {
        if ($page -and -not $page.IsDisposed) { Center-PageCanvas $page }
    }
}

function New-ActionTile {
    param($Parent, $Location, $Title, $Description, $ButtonText, $ButtonTag, $Action)
    $tile = New-Surface -Parent $Parent -Location $Location -Size (New-Object System.Drawing.Size(332, 164))
    [void](New-Label -Parent $tile -Text $Title -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)))
    [void](New-Label -Parent $tile -Text $Description -Location (New-Object System.Drawing.Point(24, 56)) -Size (New-Object System.Drawing.Size(284, 48)) -AutoSize $false -Tag "BodyMuted")
    $btn = New-Button -Parent $tile -Text $ButtonText -Location (New-Object System.Drawing.Point(24, 110)) -Size (New-Object System.Drawing.Size(184, 34)) -Tag $ButtonTag -Click $Action
    return @{ Panel = $tile; Button = $btn }
}

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$FormW = [Math]::Min(1440, [Math]::Max(1320, [int]($screen.Width * 0.88)))
$FormH = [Math]::Min(940, [Math]::Max(840, [int]($screen.Height * 0.88)))

$Form = New-Object System.Windows.Forms.Form
# codex-branding:start
$brandingIconPath = Join-Path $PSScriptRoot 'icon.ico'
if (Test-Path $brandingIconPath) {
    try {
        $Form.Icon = New-Object System.Drawing.Icon($brandingIconPath)
    } catch {}
}
# codex-branding:end
$Form.Text = $Lang.Title
$Form.Size = New-Object System.Drawing.Size($FormW, $FormH)
$Form.MinimumSize = New-Object System.Drawing.Size(1320, 840)
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "Sizable"
$Form.BackColor = [System.Drawing.Color]::FromArgb(13, 18, 28)
$Form.ForeColor = [System.Drawing.Color]::White
$Form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$Form.AutoScaleMode = "Dpi"
$Form.KeyPreview = $true
Enable-DoubleBuffer $Form

$Sidebar = New-Panel -Name "Sidebar" -Parent $Form -Dock "Left" -Size (New-Object System.Drawing.Size(252, $FormH)) -Tag "Sidebar"
$Footer = New-Panel -Name "Footer" -Parent $Form -Dock "Bottom" -Size (New-Object System.Drawing.Size($FormW, 88)) -Tag "Footer"
$MainPanel = New-Panel -Name "MainPanel" -Parent $Form -Dock "Fill" -Tag "MainPanel"

$SidebarBrand = New-Surface -Parent $Sidebar -Location (New-Object System.Drawing.Point(16, 18)) -Size (New-Object System.Drawing.Size(220, 132)) -Tag "SidebarAlt"
$LogoBox = New-Object System.Windows.Forms.PictureBox
$LogoBox.Location = New-Object System.Drawing.Point(24, 26)
$LogoBox.Size = New-Object System.Drawing.Size(52, 52)
$LogoBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$brandPngPath = Join-Path $PSScriptRoot "icon.png"
if (Test-Path $brandPngPath) {
    try { $LogoBox.Image = [System.Drawing.Image]::FromFile($brandPngPath) } catch {}
}
[void]$SidebarBrand.Controls.Add($LogoBox)
[void](New-Label -Parent $SidebarBrand -Text "JDownloader 2" -Location (New-Object System.Drawing.Point(88, 28)) -Font (New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $SidebarBrand -Text "Ultimate Manager" -Location (New-Object System.Drawing.Point(88, 54)) -Font (New-Object System.Drawing.Font("Segoe UI", 12)) -Tag "MutedStrong")
[void](New-Label -Parent $SidebarBrand -Text "Install, refine, harden, and repair from one calm workspace." -Location (New-Object System.Drawing.Point(24, 88)) -Size (New-Object System.Drawing.Size(172, 34)) -AutoSize $false -Tag "BodyMuted")

$SidebarFooter = New-Panel -Parent $Sidebar -Dock "Bottom" -Size (New-Object System.Drawing.Size(252, 150)) -Tag "Sidebar"
$SidebarNote = New-Surface -Parent $SidebarFooter -Location (New-Object System.Drawing.Point(16, 10)) -Size (New-Object System.Drawing.Size(220, 124)) -Tag "SidebarAlt"
[void](New-Label -Parent $SidebarNote -Text "Before you run" -Location (New-Object System.Drawing.Point(24, 20)) -Font (New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $SidebarNote -Text "Admin rights are required. Existing configs are backed up before changes are applied." -Location (New-Object System.Drawing.Point(24, 46)) -Size (New-Object System.Drawing.Size(172, 52)) -AutoSize $false -Tag "BodyMuted")
[void](New-Label -Parent $SidebarNote -Text "Best flow: review every page, then apply once." -Location (New-Object System.Drawing.Point(24, 98)) -Size (New-Object System.Drawing.Size(172, 18)) -AutoSize $false -Tag "BodyMuted")

[int]$sbY = 168
[int]$sbH = 44
[int]$sbGap = 8
$BtnDashboard    = New-Button -Parent $Sidebar -LangKey "Dashboard"    -Location (New-Object System.Drawing.Point(16, $sbY)) -Size (New-Object System.Drawing.Size(220, $sbH)) -Tag "SidebarBtn"
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

$BtnExec = New-Button -Parent $Footer -LangKey "Execute" -Location (New-Object System.Drawing.Point(24, 20)) -Size (New-Object System.Drawing.Size(248, 46)) -Tag "PrimaryButton"
$FooterSummary = New-Label -Parent $Footer -LangKey "FooterSummary" -Location (New-Object System.Drawing.Point(296, 18)) -Size (New-Object System.Drawing.Size(300, 18)) -AutoSize $false -Tag "BodyMuted"
$ProgressBar = New-Object System.Windows.Forms.ProgressBar
$ProgressBar.Location = New-Object System.Drawing.Point(296, 46)
$ProgressBar.Size = New-Object System.Drawing.Size(300, 10)
$ProgressBar.Style = "Continuous"
$ProgressBar.Value = 0
$ProgressBar.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
[void]$Footer.Controls.Add($ProgressBar)
$StatusLabel = New-Label -Parent $Footer -Text "Status: Ready" -Location (New-Object System.Drawing.Point(624, 29)) -Size (New-Object System.Drawing.Size(560, 22)) -AutoSize $false -Tag "MutedStrong"
$StatusLabel.AutoEllipsis = $true
$StatusLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$Form.AcceptButton = $BtnExec

$PageDashboard    = New-PagePanel -CanvasHeight 666; [void]$MainPanel.Controls.Add($PageDashboard)
$PageInstallation = New-PagePanel -CanvasHeight 610; [void]$MainPanel.Controls.Add($PageInstallation)
$PageTheme        = New-PagePanel -CanvasHeight 690; [void]$MainPanel.Controls.Add($PageTheme)
$PageBehavior     = New-PagePanel -CanvasHeight 560; [void]$MainPanel.Controls.Add($PageBehavior)
$PageHardening    = New-PagePanel -CanvasHeight 610; [void]$MainPanel.Controls.Add($PageHardening)
$PageRepair       = New-PagePanel -CanvasHeight 740; [void]$MainPanel.Controls.Add($PageRepair)

$DashboardCanvas = Get-PageCanvas $PageDashboard
$InstallationCanvas = Get-PageCanvas $PageInstallation
$ThemeCanvas = Get-PageCanvas $PageTheme
$BehaviorCanvas = Get-PageCanvas $PageBehavior
$HardeningCanvas = Get-PageCanvas $PageHardening
$RepairCanvas = Get-PageCanvas $PageRepair

# --- Dashboard Page ---
$DashHero = New-Surface -Parent $DashboardCanvas -Location (New-Object System.Drawing.Point(0, 0)) -Size (New-Object System.Drawing.Size(1040, 216))
[void](New-Label -Parent $DashHero -Text "DESKTOP CONTROL CENTER" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
$DashTitle = New-Label -Parent $DashHero -LangKey "DashTitle" -Location (New-Object System.Drawing.Point(24, 46)) -Font (New-Object System.Drawing.Font("Segoe UI", 28, [System.Drawing.FontStyle]::Bold))
$DashSub = New-Label -Parent $DashHero -LangKey "DashSub" -Location (New-Object System.Drawing.Point(24, 96)) -Size (New-Object System.Drawing.Size(602, 50)) -AutoSize $false -Tag "SubHeader"
$DashHint = New-Label -Parent $DashHero -LangKey "DashHint" -Location (New-Object System.Drawing.Point(24, 154)) -Size (New-Object System.Drawing.Size(622, 38)) -AutoSize $false -Tag "BodyMuted"
$DashOverview = New-Surface -Parent $DashHero -Location (New-Object System.Drawing.Point(698, 18)) -Size (New-Object System.Drawing.Size(318, 192)) -Tag "SurfaceAlt"
[void](New-Label -Parent $DashOverview -Text "Session overview" -Location (New-Object System.Drawing.Point(24, 20)) -Font (New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)))
$DashInstallStatus = New-Label -Parent $DashOverview -Text "Not detected yet" -Location (New-Object System.Drawing.Point(24, 52)) -Font (New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold))
$DashInstallDetail = New-Label -Parent $DashOverview -Text "Choose an existing install or switch to clean install mode." -Location (New-Object System.Drawing.Point(24, 84)) -Size (New-Object System.Drawing.Size(260, 34)) -AutoSize $false -Tag "BodyMuted"
[void](New-Label -Parent $DashOverview -Text "Current run mode" -Location (New-Object System.Drawing.Point(24, 118)) -Font (New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
$DashModeDetail = New-Label -Parent $DashOverview -Text "Modify current installation" -Location (New-Object System.Drawing.Point(24, 138)) -Size (New-Object System.Drawing.Size(260, 18)) -AutoSize $false -Tag "MutedStrong"
[void](New-Label -Parent $DashOverview -Text "Last successful run" -Location (New-Object System.Drawing.Point(24, 160)) -Font (New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
$DashLastAppliedValue = New-Label -Parent $DashOverview -Text "Last applied: Not yet" -Location (New-Object System.Drawing.Point(24, 178)) -Size (New-Object System.Drawing.Size(260, 16)) -AutoSize $false -Tag "MutedStrong"

$DashCardInstall = New-Surface -Parent $DashboardCanvas -Location (New-Object System.Drawing.Point(0, 238)) -Size (New-Object System.Drawing.Size(332, 124))
[void](New-Label -Parent $DashCardInstall -Text "Installation coverage" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $DashCardInstall -Text "Modify an existing setup or shift into a clean-install flow without leaving the tool." -Location (New-Object System.Drawing.Point(24, 52)) -Size (New-Object System.Drawing.Size(284, 48)) -AutoSize $false -Tag "BodyMuted")
$DashCardTheme = New-Surface -Parent $DashboardCanvas -Location (New-Object System.Drawing.Point(354, 238)) -Size (New-Object System.Drawing.Size(332, 124))
[void](New-Label -Parent $DashCardTheme -Text "Theme refinement" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $DashCardTheme -Text "Preview community looks, layer icon packs, and keep the interface clean with tighter defaults." -Location (New-Object System.Drawing.Point(24, 52)) -Size (New-Object System.Drawing.Size(284, 48)) -AutoSize $false -Tag "BodyMuted")
$DashCardSafety = New-Surface -Parent $DashboardCanvas -Location (New-Object System.Drawing.Point(708, 238)) -Size (New-Object System.Drawing.Size(332, 124))
[void](New-Label -Parent $DashCardSafety -Text "Confidence and recovery" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $DashCardSafety -Text "Backups, audits, safe mode, cache cleanup, and uninstall tools all stay close at hand." -Location (New-Object System.Drawing.Point(24, 52)) -Size (New-Object System.Drawing.Size(284, 48)) -AutoSize $false -Tag "BodyMuted")

$DashPrefs = New-Surface -Parent $DashboardCanvas -Location (New-Object System.Drawing.Point(0, 386)) -Size (New-Object System.Drawing.Size(1040, 224))
[void](New-Label -Parent $DashPrefs -Text "Workspace preferences" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $DashPrefs -Text "Set the app chrome once, then the tool remembers the workspace on the next launch." -Location (New-Object System.Drawing.Point(24, 52)) -Size (New-Object System.Drawing.Size(620, 24)) -AutoSize $false -Tag "BodyMuted")
$LblGuiTheme = New-Label -Parent $DashPrefs -LangKey "GuiTheme" -Location (New-Object System.Drawing.Point(24, 96))
$CboGuiTheme = New-ComboBox -Parent $DashPrefs -Location (New-Object System.Drawing.Point(24, 124)) -Size (New-Object System.Drawing.Size(290, 36)) -Tag "Input" -Items $GuiThemes.Keys
$LblLang = New-Label -Parent $DashPrefs -LangKey "Language" -Location (New-Object System.Drawing.Point(348, 96))
$CboLang = New-ComboBox -Parent $DashPrefs -Location (New-Object System.Drawing.Point(348, 124)) -Size (New-Object System.Drawing.Size(290, 36)) -Tag "Input" -Items $AvailableLanguages.Keys
$DashPrefsNote = New-Surface -Parent $DashPrefs -Location (New-Object System.Drawing.Point(684, 80)) -Size (New-Object System.Drawing.Size(332, 128)) -Tag "Callout"
[void](New-Label -Parent $DashPrefsNote -Text "Workspace status" -Location (New-Object System.Drawing.Point(18, 16)) -Font (New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)))
$DashPrefsStateValue = New-Label -Parent $DashPrefsNote -Text "No saved workspace yet" -Location (New-Object System.Drawing.Point(18, 40)) -Font (New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold))
$DashPrefsStateDetail = New-Label -Parent $DashPrefsNote -Text "Your selected path, theme, language, and run options will be remembered after the first successful run." -Location (New-Object System.Drawing.Point(18, 68)) -Size (New-Object System.Drawing.Size(286, 28)) -AutoSize $false -Tag "BodyMuted"
$BtnRestoreWorkspace = New-Button -Parent $DashPrefsNote -Text "Restore last run" -Location (New-Object System.Drawing.Point(18, 96)) -Size (New-Object System.Drawing.Size(138, 28)) -Tag "SecondaryButton"

# --- Installation Page ---
$InstallHero = New-Surface -Parent $InstallationCanvas -Location (New-Object System.Drawing.Point(0, 0)) -Size (New-Object System.Drawing.Size(1040, 160))
$InstTitle = New-Label -Parent $InstallHero -LangKey "InstTitle" -Location (New-Object System.Drawing.Point(24, 24)) -Tag "SectionHeader"
$InstSub = New-Label -Parent $InstallHero -LangKey "InstSub" -Location (New-Object System.Drawing.Point(24, 62)) -Size (New-Object System.Drawing.Size(690, 44)) -AutoSize $false -Tag "SubHeader"
$InstallBadge = New-Label -Parent $InstallHero -Text "Detection pending" -Location (New-Object System.Drawing.Point(804, 34)) -Font (New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold))
[void](New-Label -Parent $InstallHero -Text "The tool can work against an existing install or prepare a fresh one for you." -Location (New-Object System.Drawing.Point(804, 68)) -Size (New-Object System.Drawing.Size(190, 38)) -AutoSize $false -Tag "BodyMuted")

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
    $Form.Text = $Lang.Title
    foreach ($entry in $script:LanguageRegistry) {
        if ($entry.Control -and -not $entry.Control.IsDisposed) {
            $entry.Control.Text = $Lang[$entry.Key]
        }
    }
    Update-ModeSummary
    Update-ThemePreview
    Layout-Footer
    Update-WorkspaceState
}

function Layout-Footer {
    if (-not $Footer -or -not $BtnExec -or -not $FooterSummary -or -not $ProgressBar -or -not $StatusLabel) { return }
    $contentLeft = $BtnExec.Right + 24
    $availableWidth = [Math]::Max(520, $Footer.ClientSize.Width - $contentLeft - 24)
    $progressWidth = [Math]::Max(240, [Math]::Min(420, [int]($availableWidth * 0.42)))
    $FooterSummary.Location = New-Object System.Drawing.Point($contentLeft, 18)
    $FooterSummary.Size = New-Object System.Drawing.Size($progressWidth, 18)
    $ProgressBar.Location = New-Object System.Drawing.Point($contentLeft, 46)
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
        $BtnExec.Text = if ($IsBusy) { Get-LangValue -Key "Running" -Fallback "Applying changes..." } else { $Lang.Execute }
    }
    if ($Form) { $Form.UseWaitCursor = $IsBusy }
    Layout-Footer
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

function Apply-StateToControls {
    param($State)
    if (-not $State) { return }

    $previousBootstrapping = $script:IsBootstrapping
    $script:IsBootstrapping = $true
    try {
        if ($State.PSObject.Properties.Name -contains "InstallPath") { $TxtPath.Text = [string]$State.InstallPath }
        if ($State.PSObject.Properties.Name -contains "ThemeName") { $CboTheme.Text = [string]$State.ThemeName }
        if ($State.PSObject.Properties.Name -contains "GuiThemeName" -and $CboGuiTheme.Items.Contains($State.GuiThemeName)) { $CboGuiTheme.Text = [string]$State.GuiThemeName }
        if ($State.PSObject.Properties.Name -contains "LanguageCode" -and $CboLang.Items.Contains($State.LanguageCode)) { $CboLang.SelectedItem = [string]$State.LanguageCode }
        if ($State.PSObject.Properties.Name -contains "IconPack") { $CboIcons.Text = [string]$State.IconPack }
        if ($State.PSObject.Properties.Name -contains "WindowDec") { $ChkWinDec.Checked = [bool]$State.WindowDec }
        if ($State.PSObject.Properties.Name -contains "ForceMinimal") { $ChkMinLay.Checked = [bool]$State.ForceMinimal }
        if ($State.PSObject.Properties.Name -contains "MaxSim") { $NumSim.Value = [decimal]$State.MaxSim }
        if ($State.PSObject.Properties.Name -contains "PauseSpeed") { $NumPause.Value = [decimal]$State.PauseSpeed }
        if ($State.PSObject.Properties.Name -contains "DlFolder") { $TxtDl.Text = [string]$State.DlFolder }
        if ($State.PSObject.Properties.Name -contains "StartMin") { $ChkMin.Checked = [bool]$State.StartMin }
        if ($State.PSObject.Properties.Name -contains "MinToTray") { $ChkTray.Checked = [bool]$State.MinToTray }
        if ($State.PSObject.Properties.Name -contains "CloseToTray") { $ChkCloseTray.Checked = [bool]$State.CloseToTray }
        if ($State.PSObject.Properties.Name -contains "PatchExe") { $ChkExe.Checked = [bool]$State.PatchExe }
        if ($State.PSObject.Properties.Name -contains "AutoUpdate") { $ChkUpdate.Checked = [bool]$State.AutoUpdate }
        if ($State.PSObject.Properties.Name -contains "Mode") {
            if ($State.Mode -eq "Modify") { $CboMode.SelectedIndex = 0 }
            elseif ($State.PSObject.Properties.Name -contains "InstallSource" -and $State.InstallSource -eq "Mega") { $CboMode.SelectedIndex = 2 }
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
        Mode         = $mode
        InstallSource= $src
        InstallPath  = $TxtPath.Text.Trim()
        ThemeName    = $CboTheme.Text
        GuiThemeName = $CboGuiTheme.Text
        LanguageCode = $CboLang.Text
        IconPack     = $CboIcons.Text
        WindowDec    = [bool]$ChkWinDec.Checked
        MaxSim       = [int]$NumSim.Value
        DlFolder     = $TxtDl.Text.Trim()
        StartMin     = [bool]$ChkMin.Checked
        MinToTray    = [bool]$ChkTray.Checked
        CloseToTray  = [bool]$ChkCloseTray.Checked
        PatchExe     = [bool]$ChkExe.Checked
        AutoUpdate   = [bool]$ChkUpdate.Checked
        ForceMinimal = [bool]$ChkMinLay.Checked
        PauseSpeed   = [int]$NumPause.Value
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

    return [ordered]@{
        Mode         = $mode
        InstallSource= $installSource
        InstallPath  = ([string]$State.InstallPath).Trim()
        ThemeName    = [string]$State.ThemeName
        GuiThemeName = [string]$State.GuiThemeName
        LanguageCode = $languageCode
        IconPack     = [string]$State.IconPack
        WindowDec    = [bool]$State.WindowDec
        MaxSim       = [int]$State.MaxSim
        DlFolder     = ([string]$State.DlFolder).Trim()
        StartMin     = [bool]$State.StartMin
        MinToTray    = [bool]$State.MinToTray
        CloseToTray  = [bool]$State.CloseToTray
        PatchExe     = [bool]$State.PatchExe
        AutoUpdate   = [bool]$State.AutoUpdate
        ForceMinimal = [bool]$State.ForceMinimal
        PauseSpeed   = [int]$State.PauseSpeed
    }
}

function Get-LastAppliedDisplayText {
    if (Test-Path $SettingsFile) {
        return "Last applied: {0}" -f ((Get-Item $SettingsFile).LastWriteTime.ToString("MMM d, yyyy h:mm tt"))
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
        "download behavior"    = @("MaxSim", "DlFolder", "PauseSpeed", "StartMin", "MinToTray", "CloseToTray")
        "hardening"            = @("PatchExe", "AutoUpdate")
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
    if (-not $FooterSummary -or -not $DashPrefsStateValue -or -not $DashPrefsStateDetail -or -not $DashLastAppliedValue -or -not $BtnRestoreWorkspace) { return }

    $palette = Get-ActivePalette
    $currentState = Get-NormalizedStateObject -State (Get-CurrentGuiState)
    $lastAppliedText = Get-LastAppliedDisplayText
    $DashLastAppliedValue.Text = $lastAppliedText
    $baselineState = Get-WorkspaceComparisonBaseline

    if (-not $script:SavedWorkspaceState) {
        $BtnRestoreWorkspace.Enabled = $false
        $BtnRestoreWorkspace.Text = "Available later"
        $changedAreas = @(Get-ChangedWorkspaceAreas -SavedState $baselineState -CurrentState $currentState)
        if ($changedAreas.Count -eq 0) {
            $FooterSummary.Text = "First run ready. Review the pages, then apply once to save this workspace."
            $DashPrefsStateValue.Text = "No saved workspace yet"
            $DashPrefsStateValue.ForeColor = $palette.Accent
            $DashPrefsStateDetail.Text = "Your selected path, theme, language, and run options will be remembered after the first successful run."
        } else {
            $suffix = if ($changedAreas.Count -eq 1) { "" } else { "s" }
            $FooterSummary.Text = "First run configured in {0} area{1}. Apply once to save this workspace." -f $changedAreas.Count, $suffix
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
    Set-ControlMetadata -Control $BtnInstallation -Name "Installation navigation" -Description "Open installation mode and path settings." -TabIndex 1
    Set-ControlMetadata -Control $BtnTheme        -Name "Themes navigation"       -Description "Open theme and icon customization options." -TabIndex 2
    Set-ControlMetadata -Control $BtnBehavior     -Name "Behavior navigation"     -Description "Open download and window behavior settings." -TabIndex 3
    Set-ControlMetadata -Control $BtnHardening    -Name "Hardening navigation"    -Description "Open the debloat and hardening options page." -TabIndex 4
    Set-ControlMetadata -Control $BtnRepair       -Name "Repair navigation"       -Description "Open maintenance and recovery tools." -TabIndex 5

    Set-ControlMetadata -Control $CboGuiTheme -Name "Workspace theme" -Description "Choose the visual theme for this manager window." -TabIndex 0
    Set-ControlMetadata -Control $CboLang     -Name "Workspace language" -Description "Choose the language used inside this manager window." -TabIndex 1
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

    Set-ControlMetadata -Control $ChkExe       -Name "Apply dark executable icon" -Description "Replace the executable icon with the darker icon variant." -TabIndex 0
    Set-ControlMetadata -Control $ChkUpdate    -Name "Run update after completion" -Description "Launch JDownloader's update routine after the selected work finishes." -TabIndex 1

    Set-ControlMetadata -Control $RepairResetCfg.Button   -Name "Reset configuration" -Description "Back up and remove the full configuration folder." -TabIndex 0
    Set-ControlMetadata -Control $RepairResetTheme.Button -Name "Reset theme assets" -Description "Remove the current theme override files and icon assets." -TabIndex 0
    Set-ControlMetadata -Control $RepairClearCache.Button -Name "Clear cache" -Description "Delete temporary cache files and leftover logs." -TabIndex 0
    Set-ControlMetadata -Control $RepairAudit.Button      -Name "Run health audit" -Description "Check the installation for missing or damaged configuration files." -TabIndex 0
    Set-ControlMetadata -Control $RepairSafe.Button       -Name "Launch safe mode" -Description "Start JDownloader in safe mode for troubleshooting." -TabIndex 0
    Set-ControlMetadata -Control $RepairUninstall.Button  -Name "Full uninstall" -Description "Remove JDownloader from the selected install folder." -TabIndex 0

    Set-ControlMetadata -Control $BtnExec      -Name "Apply selected changes" -Description "Run the selected installation, theme, behavior, hardening, and repair operations." -TabIndex 0
    Set-ControlMetadata -Control $BtnRestoreWorkspace -Name "Restore last run" -Description "Restore the last successful workspace selections and discard pending edits." -TabIndex 2
    Set-ControlMetadata -Control $ProgressBar  -Name "Operation progress" -Description "Shows progress while selected changes are being applied."
    Set-ControlMetadata -Control $StatusLabel  -Name "Status updates" -Description "Shows the latest status and completion messages."
    Set-ControlMetadata -Control $DashLastAppliedValue -Name "Last successful run" -Description "Shows when the last successful apply run completed."
    Set-ControlMetadata -Control $DashPrefsStateValue -Name "Workspace status" -Description "Shows whether the current selections match the last successful run."
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
$PicThemePreview = New-Object System.Windows.Forms.PictureBox
$PicThemePreview.Location = New-Object System.Drawing.Point(24, 24)
$PicThemePreview.Size = New-Object System.Drawing.Size(610, 440)
$PicThemePreview.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
[void]$PnlPreview.Controls.Add($PicThemePreview)
$LblPreviewState = New-Label -Parent $PnlPreview -Text "Preview is loading in the background." -Location (New-Object System.Drawing.Point(48, 214)) -Size (New-Object System.Drawing.Size(562, 42)) -AutoSize $false -Tag "BodyMuted"
$LblPreviewState.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

$ThemeOptions = New-Surface -Parent $ThemeCanvas -Location (New-Object System.Drawing.Point(680, 172)) -Size (New-Object System.Drawing.Size(360, 488)) -Tag "SurfaceAlt"
[void](New-Label -Parent $ThemeOptions -Text "Appearance options" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $ThemeOptions -Text "Choose the supporting icon pack and decide how minimal you want the final JDownloader shell to feel." -Location (New-Object System.Drawing.Point(24, 52)) -Size (New-Object System.Drawing.Size(312, 52)) -AutoSize $false -Tag "BodyMuted")
$LblIco = New-Label -Parent $ThemeOptions -LangKey "IconPack" -Location (New-Object System.Drawing.Point(24, 126))
$CboIcons = New-ComboBox -Parent $ThemeOptions -Location (New-Object System.Drawing.Point(24, 154)) -Size (New-Object System.Drawing.Size(312, 36)) -Tag "Input" -Items $IconDefinitions.Keys
$ChkWinDec = New-CheckBox -Parent $ThemeOptions -LangKey "EnableWinDec" -Location (New-Object System.Drawing.Point(24, 220)) -Checked $true
$ChkMinLay = New-CheckBox -Parent $ThemeOptions -LangKey "CompactTabs" -Location (New-Object System.Drawing.Point(24, 258))
[void](New-Label -Parent $ThemeOptions -Text "Theme previews can keep loading while you continue configuring the rest of the tool." -Location (New-Object System.Drawing.Point(24, 298)) -Size (New-Object System.Drawing.Size(312, 36)) -AutoSize $false -Tag "BodyMuted")
$BtnOpenThm = New-Button -Parent $ThemeOptions -LangKey "OpenIconFolder" -Location (New-Object System.Drawing.Point(24, 352)) -Size (New-Object System.Drawing.Size(220, 36)) -Tag "SecondaryButton"

function Resize-ThemePreview {
    if (-not $PnlPreview) { return }
    $PicThemePreview.Size = New-Object System.Drawing.Size([Math]::Max(120, $PnlPreview.Width - 48), [Math]::Max(120, $PnlPreview.Height - 48))
    $LblPreviewState.Location = New-Object System.Drawing.Point(36, [Math]::Max(80, [int](($PnlPreview.Height - $LblPreviewState.Height) / 2)))
    $LblPreviewState.Size = New-Object System.Drawing.Size([Math]::Max(160, $PnlPreview.Width - 72), 42)
}

function Update-ThemePreview {
    $selection = $ThemeDefinitions[$CboTheme.Text]
    if (-not $selection) { return }
    $LblPreDesc.Text = $selection.Desc
    $LblThemeLink.Tag = $selection.ThemeUrl
    if ($ThemeImageCache.ContainsKey($CboTheme.Text) -and $ThemeImageCache[$CboTheme.Text]) {
        $PicThemePreview.Image = $ThemeImageCache[$CboTheme.Text]
        $LblPreviewState.Visible = $false
    } else {
        $PicThemePreview.Image = $null
        $LblPreviewState.Text = if ($selection.PreviewUrl) { "Preview is still loading. You can keep configuring icons and layout options in the meantime." } else { "No preview is available for this theme yet." }
        $LblPreviewState.Visible = $true
    }
}

# --- Behavior Page ---
$BehHero = New-Surface -Parent $BehaviorCanvas -Location (New-Object System.Drawing.Point(0, 0)) -Size (New-Object System.Drawing.Size(1040, 156))
$BehTitle = New-Label -Parent $BehHero -LangKey "BehTitle" -Location (New-Object System.Drawing.Point(24, 24)) -Tag "SectionHeader"
$BehSub = New-Label -Parent $BehHero -LangKey "BehSub" -Location (New-Object System.Drawing.Point(24, 60)) -Size (New-Object System.Drawing.Size(690, 40)) -AutoSize $false -Tag "SubHeader"
[void](New-Label -Parent $BehHero -Text "These settings become part of the final JDownloader profile the moment you apply operations." -Location (New-Object System.Drawing.Point(780, 34)) -Size (New-Object System.Drawing.Size(214, 52)) -AutoSize $false -Tag "BodyMuted")

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

# --- Hardening Page ---
$HardHero = New-Surface -Parent $HardeningCanvas -Location (New-Object System.Drawing.Point(0, 0)) -Size (New-Object System.Drawing.Size(1040, 156))
$HardTitle = New-Label -Parent $HardHero -LangKey "HardTitle" -Location (New-Object System.Drawing.Point(24, 24)) -Tag "SectionHeader"
$HardSub = New-Label -Parent $HardHero -LangKey "HardSub" -Location (New-Object System.Drawing.Point(24, 60)) -Size (New-Object System.Drawing.Size(650, 40)) -AutoSize $false -Tag "SubHeader"
[void](New-Label -Parent $HardHero -Text "The goal here is a quieter, less promotional, more trustworthy default JDownloader shell." -Location (New-Object System.Drawing.Point(780, 34)) -Size (New-Object System.Drawing.Size(214, 52)) -AutoSize $false -Tag "BodyMuted")

$HardControls = New-Surface -Parent $HardeningCanvas -Location (New-Object System.Drawing.Point(0, 180)) -Size (New-Object System.Drawing.Size(640, 228))
[void](New-Label -Parent $HardControls -Text "Optional finishing passes" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)))
$ChkExe = New-CheckBox -Parent $HardControls -LangKey "DarkExe" -Location (New-Object System.Drawing.Point(24, 84)) -Checked $true
[void](New-Label -Parent $HardControls -Text "Replaces the executable icon so the shell looks more at home with darker setups." -Location (New-Object System.Drawing.Point(48, 110)) -Size (New-Object System.Drawing.Size(544, 32)) -AutoSize $false -Tag "BodyMuted")
$ChkUpdate = New-CheckBox -Parent $HardControls -LangKey "RunUpdate" -Location (New-Object System.Drawing.Point(24, 156)) -Checked $true
[void](New-Label -Parent $HardControls -Text "Launches JDownloader's update routine once configuration work finishes." -Location (New-Object System.Drawing.Point(48, 182)) -Size (New-Object System.Drawing.Size(544, 24)) -AutoSize $false -Tag "BodyMuted")

$HardAlways = New-Surface -Parent $HardeningCanvas -Location (New-Object System.Drawing.Point(662, 180)) -Size (New-Object System.Drawing.Size(378, 228)) -Tag "SurfaceAlt"
[void](New-Label -Parent $HardAlways -Text "Always applied cleanup" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)))
[void](New-Label -Parent $HardAlways -Text "Contribute panel" -Location (New-Object System.Drawing.Point(24, 74)) -Font (New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
[void](New-Label -Parent $HardAlways -Text "Promotional banners" -Location (New-Object System.Drawing.Point(24, 106)) -Font (New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
[void](New-Label -Parent $HardAlways -Text "Premium and MyJD prompts" -Location (New-Object System.Drawing.Point(24, 138)) -Font (New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)) -Tag "BodyMuted")
[void](New-Label -Parent $HardAlways -Text "These are disabled by default so the final interface feels calmer and less cluttered." -Location (New-Object System.Drawing.Point(24, 174)) -Size (New-Object System.Drawing.Size(320, 32)) -AutoSize $false -Tag "BodyMuted")

$HardNoteSurface = New-Surface -Parent $HardeningCanvas -Location (New-Object System.Drawing.Point(0, 432)) -Size (New-Object System.Drawing.Size(1040, 144))
[void](New-Label -Parent $HardNoteSurface -Text "Result" -Location (New-Object System.Drawing.Point(24, 22)) -Font (New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)))
$HardNote = New-Label -Parent $HardNoteSurface -LangKey "HardNote" -Location (New-Object System.Drawing.Point(24, 56)) -Size (New-Object System.Drawing.Size(972, 56)) -AutoSize $false -Tag "BodyMuted"

# --- Repair Page ---
$RepairHero = New-Surface -Parent $RepairCanvas -Location (New-Object System.Drawing.Point(0, 0)) -Size (New-Object System.Drawing.Size(1040, 160))
$RepTitle = New-Label -Parent $RepairHero -LangKey "RepTitle" -Location (New-Object System.Drawing.Point(24, 24)) -Tag "SectionHeader"
$RepSub = New-Label -Parent $RepairHero -LangKey "RepSub" -Location (New-Object System.Drawing.Point(24, 60)) -Size (New-Object System.Drawing.Size(650, 40)) -AutoSize $false -Tag "SubHeader"
[void](New-Label -Parent $RepairHero -Text "Most actions below stop JDownloader first. Destructive actions ask for confirmation before they continue." -Location (New-Object System.Drawing.Point(760, 34)) -Size (New-Object System.Drawing.Size(236, 52)) -AutoSize $false -Tag "BodyMuted")

function Show-ActionPrompt {
    param([string]$Title, [string]$Message, [string]$ConfirmText = "Continue", [string]$ConfirmTag = "PrimaryButton")
    $pal = Get-ActivePalette
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $Title
    $dlg.Size = New-Object System.Drawing.Size(520, 280)
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
    return ($dlg.ShowDialog($Form) -eq [System.Windows.Forms.DialogResult]::OK)
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

$RepairResetCfg = New-ActionTile -Parent $RepairCanvas -Location (New-Object System.Drawing.Point(0, 184)) -Title "Factory reset" -Description "Back up and remove the full cfg folder to return JDownloader to a clean starting point." -ButtonText "Reset configuration" -ButtonTag "DangerButton" -Action { if ((Ensure-InstallPathSelected) -and (Show-ActionPrompt -Title "Reset configuration" -Message "This closes JDownloader, backs up the current configuration, and removes the cfg folder. Downloads remain on disk." -ConfirmText "Reset configuration" -ConfirmTag "DangerButton")) { Kill-JDownloader; Backup-JD -InstallPath $TxtPath.Text; Remove-Item "$($TxtPath.Text)\cfg" -Recurse -Force -ErrorAction SilentlyContinue; Log-Status "Configuration reset completed." "SUCCESS" } }
$RepairResetTheme = New-ActionTile -Parent $RepairCanvas -Location (New-Object System.Drawing.Point(354, 184)) -Title "Theme reset" -Description "Strip theme overrides and custom icons without touching the rest of the installation." -ButtonText "Reset theme only" -ButtonTag "SecondaryButton" -Action { if ((Ensure-InstallPathSelected) -and (Show-ActionPrompt -Title "Reset theme assets" -Message "This removes the custom look-and-feel files and current icon overrides so you can start fresh." -ConfirmText "Reset theme assets" -ConfirmTag "PrimaryButton")) { Kill-JDownloader; Remove-Item "$($TxtPath.Text)\cfg\laf" -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item "$($TxtPath.Text)\themes\standard\org\jdownloader\images\*" -Recurse -Force -ErrorAction SilentlyContinue; Log-Status "Theme and icon overrides were cleared." "SUCCESS" } }
$RepairClearCache = New-ActionTile -Parent $RepairCanvas -Location (New-Object System.Drawing.Point(708, 184)) -Title "Cache cleanup" -Description "Delete temporary files, logs, and cache fragments that commonly linger after broken runs." -ButtonText "Clear cache" -ButtonTag "SecondaryButton" -Action { if (Ensure-InstallPathSelected) { Kill-JDownloader; Remove-Item "$($TxtPath.Text)\tmp\*" -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item "$($TxtPath.Text)\cfg\*.cache" -Force -ErrorAction SilentlyContinue; Log-Status "Temporary cache files were cleared." "SUCCESS" } }
$RepairAudit = New-ActionTile -Parent $RepairCanvas -Location (New-Object System.Drawing.Point(0, 372)) -Title "Health audit" -Description "Check for missing or corrupted configuration files before you commit to a larger repair step." -ButtonText "Run health audit" -ButtonTag "SuccessButton" -Action { if (Ensure-InstallPathSelected) { Run-Audit -InstallPath $TxtPath.Text } }
$RepairSafe = New-ActionTile -Parent $RepairCanvas -Location (New-Object System.Drawing.Point(354, 372)) -Title "Safe mode launch" -Description "Start JDownloader with a reduced profile for troubleshooting unstable themes or config changes." -ButtonText "Launch safe mode" -ButtonTag "SuccessButton" -Action { if (Ensure-InstallPathSelected -RequireExecutable) { Start-Process "$($TxtPath.Text)\JDownloader2.exe" -ArgumentList "-safe"; Log-Status "JDownloader launched in safe mode." "SUCCESS" } }
$RepairUninstall = New-ActionTile -Parent $RepairCanvas -Location (New-Object System.Drawing.Point(708, 372)) -Title "Full uninstall" -Description "Remove the application entirely when you need to start over from a clean machine state." -ButtonText "Full uninstall" -ButtonTag "DangerButton" -Action { if ((Ensure-InstallPathSelected) -and (Show-ActionPrompt -Title "Full uninstall" -Message "This removes JDownloader from the selected folder. Use it only when you want to wipe the install completely." -ConfirmText "Uninstall JDownloader" -ConfirmTag "DangerButton")) { Task-FullUninstall -InstallPath $TxtPath.Text; Log-Status "Full uninstall finished." "SUCCESS" } }

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
        if ([string]::IsNullOrWhiteSpace($path)) { $LblPathState.Text = "Modify mode needs an existing JDownloader folder."; $LblPathState.ForeColor = $palette.Warning; $DashInstallStatus.Text = "Path needed"; $DashInstallDetail.Text = "Select the existing installation you want to refine."; $InstallBadge.Text = "Modify mode"; $InstallBadge.ForeColor = $palette.Warning; $TxtPath.BackColor = $palette.InputBack }
        elseif ($hasExe) { $LblPathState.Text = "Ready. JDownloader was found at this location."; $LblPathState.ForeColor = $palette.Success; $DashInstallStatus.Text = "Install detected"; $DashInstallDetail.Text = $path; $InstallBadge.Text = "Existing install found"; $InstallBadge.ForeColor = $palette.Success; $TxtPath.BackColor = [System.Windows.Forms.ControlPaint]::Light($palette.Success, 0.85) }
        elseif ($pathExists) { $LblPathState.Text = "The folder exists, but JDownloader2.exe was not found there."; $LblPathState.ForeColor = $palette.Warning; $DashInstallStatus.Text = "Folder found"; $DashInstallDetail.Text = "Switch to clean install mode or point to the correct install."; $InstallBadge.Text = "Check folder"; $InstallBadge.ForeColor = $palette.Warning; $TxtPath.BackColor = [System.Windows.Forms.ControlPaint]::Light($palette.Warning, 0.82) }
        else { $LblPathState.Text = "That folder does not exist yet."; $LblPathState.ForeColor = $palette.Danger; $DashInstallStatus.Text = "Path not found"; $DashInstallDetail.Text = "Use Browse or Auto-Detect to pick a valid installation."; $InstallBadge.Text = "Invalid path"; $InstallBadge.ForeColor = $palette.Danger; $TxtPath.BackColor = [System.Windows.Forms.ControlPaint]::Light($palette.Danger, 0.82) }
    } else {
        if ([string]::IsNullOrWhiteSpace($path)) { $LblPathState.Text = "Clean install can start without a path. The app will detect JDownloader after install completes."; $LblPathState.ForeColor = $palette.MutedStrong; $DashInstallStatus.Text = "Clean install ready"; $DashInstallDetail.Text = "No existing path is required for this flow."; $InstallBadge.Text = "Fresh install"; $InstallBadge.ForeColor = $palette.Accent; $TxtPath.BackColor = $palette.InputBack }
        elseif ($hasExe) { $LblPathState.Text = "An existing JDownloader install is already present here. You can still continue with clean install if you want to replace it."; $LblPathState.ForeColor = $palette.Warning; $DashInstallStatus.Text = "Existing install present"; $DashInstallDetail.Text = $path; $InstallBadge.Text = "Install already present"; $InstallBadge.ForeColor = $palette.Warning; $TxtPath.BackColor = [System.Windows.Forms.ControlPaint]::Light($palette.Warning, 0.82) }
        elseif ($pathExists) { $LblPathState.Text = "Folder exists and can be used as a reference point while the installer finishes."; $LblPathState.ForeColor = $palette.MutedStrong; $DashInstallStatus.Text = "Folder selected"; $DashInstallDetail.Text = "JDownloader will be detected after the install phase."; $InstallBadge.Text = "Clean install"; $InstallBadge.ForeColor = $palette.Accent; $TxtPath.BackColor = $palette.InputBack }
        else { $LblPathState.Text = "This folder does not exist yet, but clean install mode can still continue."; $LblPathState.ForeColor = $palette.MutedStrong; $DashInstallStatus.Text = "Clean install ready"; $DashInstallDetail.Text = "The installer will decide the final install location."; $InstallBadge.Text = "Fresh install"; $InstallBadge.ForeColor = $palette.Accent; $TxtPath.BackColor = $palette.InputBack }
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
    $pathPreview = if ([string]::IsNullOrWhiteSpace($CurrentState.InstallPath)) { "Auto-detect after install" } else { $CurrentState.InstallPath }
    $guardrailText = if ($CurrentState.Mode -eq "Modify") {
        "Modify mode backs up the current configuration before file changes are applied."
    } else {
        "Clean install runs the installer first, then detects the resulting JDownloader folder before applying your selected options."
    }
    $cForm = New-Object System.Windows.Forms.Form
    $cForm.Text = "Confirm changes"
    $cForm.Size = New-Object System.Drawing.Size(700, 664)
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
        "WindowDec"    = "Enable custom window decorations"
        "ForceMinimal" = "Use compact tab layout"
        "StartMin"     = "Start minimized"
        "MinToTray"    = "Minimize to tray"
        "CloseToTray"  = "Close button sends JDownloader to tray"
        "PatchExe"     = "Apply dark executable icon"
        "AutoUpdate"   = "Run update after completion"
    }
    $ResultRefs = @{}
    [int]$optY = 104
    foreach ($key in $KeyMap.Keys) {
        if ($CurrentState.ContainsKey($key)) {
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
    $result = $cForm.ShowDialog($Form)
    
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
        
        return $true
    }
    return $false
}

# ==========================================
# 10. NAVIGATION & EXECUTION
# ==========================================

$pages = @{ $BtnDashboard = $PageDashboard; $BtnInstallation = $PageInstallation; $BtnTheme = $PageTheme; $BtnBehavior = $PageBehavior; $BtnHardening = $PageHardening; $BtnRepair = $PageRepair }
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
    }
}

function Show-Page {
    param($Button)
    foreach ($page in $pages.Values) { $page.Visible = $false }
    $pages[$Button].Visible = $true
    $script:ActiveNavButton = $Button
    Update-NavigationState
    if ($pages[$Button] -eq $PageTheme) {
        Resize-ThemePreview
        Update-ThemePreview
    }
}

$BtnBrowse.Add_Click({ $fbd = New-Object System.Windows.Forms.FolderBrowserDialog; if ($fbd.ShowDialog() -eq "OK") { $TxtPath.Text = $fbd.SelectedPath } })
$BtnDetect.Add_Click({ $p = Detect-JDPath; if ($p) { $TxtPath.Text = $p; Log-Status "Detected JDownloader at $p." "SUCCESS" } else { Log-Status "JDownloader was not detected automatically on this machine." "WARN" } })
$BtnDl.Add_Click({ $fbd = New-Object System.Windows.Forms.FolderBrowserDialog; if ($fbd.ShowDialog() -eq "OK") { $TxtDl.Text = $fbd.SelectedPath } })
$BtnOpenThm.Add_Click({ $path = "$($TxtPath.Text)\themes\standard\org\jdownloader\images"; if (Test-Path $path) { Invoke-Item $path } else { [System.Windows.Forms.MessageBox]::Show("No icon folder was found yet. Apply a theme first or point the app at an existing install.", "Folder not found", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null } })
$LblThemeLink.Add_LinkClicked({ if ($LblThemeLink.Tag) { Start-Process $LblThemeLink.Tag | Out-Null } })
$CboGuiTheme.Add_SelectedIndexChanged({ Apply-GuiTheme -ThemeName $CboGuiTheme.Text; Update-WorkspaceState })
$CboLang.Add_SelectedIndexChanged({ Apply-LanguageData $CboLang.Text; Update-InterfaceText; Update-WorkspaceState })
$CboTheme.Add_SelectedIndexChanged({ Update-ThemePreview; Update-WorkspaceState })
$CboIcons.Add_SelectedIndexChanged({ Update-WorkspaceState })
$CboMode.Add_SelectedIndexChanged({ Update-ModeSummary; Update-PathState; Update-WorkspaceState })
$TxtPath.Add_TextChanged({ Update-PathState; Update-WorkspaceState })
$TxtDl.Add_TextChanged({ Update-DownloadFolderState; Update-WorkspaceState })
$NumSim.Add_ValueChanged({ Update-WorkspaceState })
$NumPause.Add_ValueChanged({ Update-WorkspaceState })
$ChkWinDec.Add_CheckedChanged({ Update-WorkspaceState })
$ChkMinLay.Add_CheckedChanged({ Update-WorkspaceState })
$ChkMin.Add_CheckedChanged({ Update-WorkspaceState })
$ChkTray.Add_CheckedChanged({ Update-WorkspaceState })
$ChkCloseTray.Add_CheckedChanged({ Update-WorkspaceState })
$ChkExe.Add_CheckedChanged({ Update-WorkspaceState })
$ChkUpdate.Add_CheckedChanged({ Update-WorkspaceState })
$BtnRestoreWorkspace.Add_Click({
    if (-not $script:SavedWorkspaceState) { return }
    $shouldRestore = Show-ActionPrompt -Title "Restore last successful run" -Message "This replaces the current selections with the workspace that was last applied successfully." -ConfirmText "Restore selections" -ConfirmTag "PrimaryButton"
    if ($shouldRestore) {
        Apply-StateToControls -State $script:SavedWorkspaceState
        Log-Status "Workspace selections were restored from the last successful run." "SUCCESS"
    }
})

foreach ($entry in $pages.GetEnumerator()) {
    $entry.Key.Add_Click({ Show-Page -Button $this })
}

$ToolTip.SetToolTip($BtnDashboard, "Open the dashboard overview page (Ctrl+1).")
$ToolTip.SetToolTip($BtnInstallation, "Open installation path and mode options (Ctrl+2).")
$ToolTip.SetToolTip($BtnTheme, "Open themes, previews, and icon settings (Ctrl+3).")
$ToolTip.SetToolTip($BtnBehavior, "Open download and tray behavior settings (Ctrl+4).")
$ToolTip.SetToolTip($BtnHardening, "Open debloat and hardening options (Ctrl+5).")
$ToolTip.SetToolTip($BtnRepair, "Open repair and recovery tools (Ctrl+6).")
$ToolTip.SetToolTip($BtnExec, "Apply the selected installation, theme, behavior, hardening, and repair settings in one run.")
$ToolTip.SetToolTip($CboMode, "Choose whether the tool should refine an existing install or run a fresh deployment flow.")
$ToolTip.SetToolTip($TxtPath, "Required for modify mode. Optional for clean install mode.")
$ToolTip.SetToolTip($TxtDl, "Leave blank to reset the download folder to JDownloader's default.")
$ToolTip.SetToolTip($CboGuiTheme, "Change the visual theme of this manager window.")
$ToolTip.SetToolTip($CboLang, "Change the language used by this manager window.")
$ToolTip.SetToolTip($BtnRestoreWorkspace, "Restore the last successful workspace selections and discard pending edits.")
$ToolTip.SetToolTip($CboTheme, "Pick the JDownloader look and feel that should be installed.")
$ToolTip.SetToolTip($CboIcons, "Icon packs can be changed independently from the theme preset.")
$ToolTip.SetToolTip($ChkWinDec, "Turns on custom window decorations when the theme supports them.")
$ToolTip.SetToolTip($ChkMinLay, "Tightens the main JDownloader tabs for a cleaner, lower-noise shell.")
$ToolTip.SetToolTip($ChkExe, "Replaces the executable icon for a more cohesive dark desktop setup.")

$Form.Add_KeyDown({
    param($sender, $e)
    if ($e.Control) {
        switch ($e.KeyCode) {
            ([System.Windows.Forms.Keys]::D1) { Show-Page -Button $BtnDashboard; $e.SuppressKeyPress = $true; return }
            ([System.Windows.Forms.Keys]::D2) { Show-Page -Button $BtnInstallation; $e.SuppressKeyPress = $true; return }
            ([System.Windows.Forms.Keys]::D3) { Show-Page -Button $BtnTheme; $e.SuppressKeyPress = $true; return }
            ([System.Windows.Forms.Keys]::D4) { Show-Page -Button $BtnBehavior; $e.SuppressKeyPress = $true; return }
            ([System.Windows.Forms.Keys]::D5) { Show-Page -Button $BtnHardening; $e.SuppressKeyPress = $true; return }
            ([System.Windows.Forms.Keys]::D6) { Show-Page -Button $BtnRepair; $e.SuppressKeyPress = $true; return }
            ([System.Windows.Forms.Keys]::Enter) {
                if ($BtnExec.Enabled) { $BtnExec.PerformClick() }
                $e.SuppressKeyPress = $true
                return
            }
            ([System.Windows.Forms.Keys]::R) {
                if ($BtnRestoreWorkspace.Enabled) { $BtnRestoreWorkspace.PerformClick() }
                $e.SuppressKeyPress = $true
                return
            }
        }
    }
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F5 -and $BtnExec.Enabled) {
        $BtnExec.PerformClick()
        $e.SuppressKeyPress = $true
    }
})

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
    $detected = Detect-JDPath
    if ($saved) {
        Apply-StateToControls -State $saved
        if ([string]::IsNullOrWhiteSpace($TxtPath.Text) -and $detected) { $TxtPath.Text = $detected }
    } elseif ($detected) {
        $TxtPath.Text = $detected
        $CboMode.SelectedIndex = 0
    } else {
        $CboMode.SelectedIndex = 1
    }

    if ($detected) { Log-Status "JDownloader was detected successfully." "SUCCESS" } else { Log-Status "JDownloader was not detected. Clean install mode is ready." "INFO" }

    Configure-DirectoryInput -TextBox $TxtPath -CueText "Required for modify mode. Optional for clean install mode."
    Configure-DirectoryInput -TextBox $TxtDl -CueText "Leave blank to reset to JDownloader's default download folder."
    Apply-AccessibilityMetadata
    Apply-GuiTheme -ThemeName $CboGuiTheme.Text
    Update-ModeSummary
    Update-PathState
    Update-DownloadFolderState
    Update-ThemePreview
    Show-Page -Button $BtnDashboard
    $script:InitialWorkspaceState = Get-NormalizedStateObject -State (Get-CurrentGuiState)
    if ($saved) { $script:SavedWorkspaceState = Get-NormalizedStateObject -State (Get-CurrentGuiState) } else { $script:SavedWorkspaceState = $null }
    $script:IsBootstrapping = $false
    Update-WorkspaceState
    Start-ThemeImagePreload -Definitions $ThemeDefinitions
})

$Form.Add_Resize({ Sync-PageCanvases; Resize-ThemePreview; Layout-Footer })
$Form.Add_FormClosing({
    param($sender, $e)
    if (-not $script:IsBootstrapping -and $BtnExec -and $BtnExec.Enabled -and (Test-WorkspaceHasPendingChanges)) {
        $discard = Show-ActionPrompt -Title "Discard pending changes" -Message "This workspace has unapplied changes. Close the manager without saving them?" -ConfirmText "Discard changes" -ConfirmTag "DangerButton"
        if (-not $discard) {
            $e.Cancel = $true
            return
        }
    }

    if ($LogoBox.Image) { $LogoBox.Image.Dispose() }
    Cleanup-Resources
})

$BtnExec.Add_Click({
    $State = Get-CurrentGuiState
    if (Show-ConfirmationDialog -CurrentState $State) {
        Set-WorkspaceBusyState -IsBusy $true
        $ProgressBar.Value = 15
        Log-Status "Applying selected changes..." "INFO"
        $Form.Refresh()
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
            [System.Windows.Forms.MessageBox]::Show((Get-LangValue -Key "RunFinishedBody" -Fallback "Selected operations completed. Review the status area for the final result."), (Get-LangValue -Key "RunFinishedTitle" -Fallback "Run finished"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } else {
            $ProgressBar.Style = "Continuous"
            $ProgressBar.MarqueeAnimationSpeed = 0
            $ProgressBar.Value = 0
        }
    }
})

[void]$Form.ShowDialog()
