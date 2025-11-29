<#
.SYNOPSIS
    JDownloader 2 ULTIMATE MANAGER (v13.2 - PREVIEW FIX)
    - Fixed: Theme Preview panel scaling (no longer overlaps footer).
    - Fixed: Added missing ThemeUrl links for GitHub button.
    - Architecture: WinForms GUI, JSON Settings Persistence, Robust Logging.
    - FEATURES: Resolution Scaling, Dynamic Themes, Language Support, Instant Previews.
#>

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
    [System.Diagnostics.Process]::Start($processInfo) | Out-Null
    Exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Force High DPI Awareness
try {
    $methods = '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
    $user32 = Add-Type -MemberDefinition $methods -Name "Win32" -Namespace Win32 -PassThru
    $user32::SetProcessDPIAware() | Out-Null
} catch {}

[System.Windows.Forms.Application]::EnableVisualStyles()

# ==========================================
# 2. GLOBAL VARIABLES & PATHS
# ==========================================
$AppDataDir   = "$env:ProgramData\JD2-Ultimate-Manager"
$LogDir       = "$AppDataDir\Logs"
$WorkDir      = "$env:TEMP\JD2_Ult_Tool_v13_0"
$SettingsFile = "$AppDataDir\settings.json"
$VersionFile  = "$AppDataDir\version.json"
$LangFile     = "$AppDataDir\lang.json"

foreach ($path in @($AppDataDir, $LogDir, $WorkDir)) {
    if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
}

$LogFile     = "$LogDir\$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
$StatusLabel = $null
$ProgressBar = $null

# ToolTip helper
$ToolTip = New-Object System.Windows.Forms.ToolTip
$ToolTip.AutoPopDelay = 5000
$ToolTip.InitialDelay = 1000
$ToolTip.ReshowDelay = 500

# ==========================================
# 3. LANGUAGE & GUI THEME ENGINE
# ==========================================

# --- Default English Fallback ---
$DefaultLang = [ordered]@{
    "Title" = "JDownloader 2 Ultimate Manager v13.2";
    "Dashboard" = "Dashboard"; "Installation" = "Installation"; "Themes" = "Themes"; 
    "Behavior" = "Behavior"; "Hardening" = "Hardening"; "Repair" = "Repair Tools";
    "Execute" = "EXECUTE ALL OPERATIONS"; "Status" = "Status: Ready";
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

$AvailableLanguages = @{} # Stores raw JSON parts
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
            # Fallback if no internet/file
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

Load-Language

# --- GUI Color Themes ---
$GuiThemes = @{
    "Dark (Default)" = @{
        FormBack = [System.Drawing.Color]::FromArgb(30,30,30)
        Fore     = [System.Drawing.Color]::White
        Sidebar  = [System.Drawing.Color]::FromArgb(22,22,22)
        Main     = [System.Drawing.Color]::FromArgb(28,28,28)
        Footer   = [System.Drawing.Color]::FromArgb(22,22,22)
        BtnBack  = [System.Drawing.Color]::FromArgb(40,40,40)
        Accent   = [System.Drawing.Color]::FromArgb(30,144,255)
    }
    "Light" = @{
        FormBack = [System.Drawing.Color]::FromArgb(240,240,240)
        Fore     = [System.Drawing.Color]::Black
        Sidebar  = [System.Drawing.Color]::FromArgb(220,220,220)
        Main     = [System.Drawing.Color]::White
        Footer   = [System.Drawing.Color]::FromArgb(220,220,220)
        BtnBack  = [System.Drawing.Color]::FromArgb(200,200,200)
        Accent   = [System.Drawing.Color]::FromArgb(0,120,215)
    }
    "Midnight" = @{
        FormBack = [System.Drawing.Color]::FromArgb(10,10,15)
        Fore     = [System.Drawing.Color]::FromArgb(200,200,255)
        Sidebar  = [System.Drawing.Color]::FromArgb(5,5,10)
        Main     = [System.Drawing.Color]::FromArgb(15,15,25)
        Footer   = [System.Drawing.Color]::FromArgb(5,5,10)
        BtnBack  = [System.Drawing.Color]::FromArgb(25,25,45)
        Accent   = [System.Drawing.Color]::FromArgb(100,50,200)
    }
    "Catppuccin Mocha" = @{
        FormBack = [System.Drawing.Color]::FromArgb(30,30,46) # Base
        Fore     = [System.Drawing.Color]::FromArgb(205,214,244) # Text
        Sidebar  = [System.Drawing.Color]::FromArgb(24,24,37) # Mantle
        Main     = [System.Drawing.Color]::FromArgb(30,30,46) # Base
        Footer   = [System.Drawing.Color]::FromArgb(24,24,37) # Mantle
        BtnBack  = [System.Drawing.Color]::FromArgb(69,71,90) # Surface1
        Accent   = [System.Drawing.Color]::FromArgb(137,180,250) # Blue
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

# Cache for theme preview images
$ThemeImageCache = @{}

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
    try { Add-Content -Path $LogFile -Value $msg -ErrorAction SilentlyContinue } catch {}
    
    # Update Status Label Only (Removed OutputBox)
    if ($StatusLabel -and $StatusLabel.IsHandleCreated) {
        $StatusLabel.Invoke([Action[string]]{ param($t) $StatusLabel.Text = $t }, "Status: $Text")
    }
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
    try {
        if (-not (Get-Module -Name BitsTransfer -ListAvailable)) { Import-Module BitsTransfer -ErrorAction Stop }
        Start-BitsTransfer -Source $Url -Destination $Destination -ErrorAction Stop -Priority Foreground
        return $true
    } catch {
        Log-Status "BITS download failed, trying web client. $_" "WARN"
    }
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        Log-Status "Download failed from $Url. $_" "ERROR"
        return $false
    }
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

# --- Theme Preloading ---
function Preload-ThemeImages {
    Log-Status "Pre-loading theme previews..."
    foreach ($key in $ThemeDefinitions.Keys) {
        $url = $ThemeDefinitions[$key].PreviewUrl
        if ($url) {
            try {
                $wc = New-Object System.Net.WebClient
                $bytes = $wc.DownloadData($url)
                $ms = New-Object System.IO.MemoryStream(,$bytes)
                $img = [System.Drawing.Image]::FromStream($ms)
                $ThemeImageCache[$key] = $img
            } catch {
                $ThemeImageCache[$key] = $null
            }
        }
    }
    Log-Status "Theme previews loaded."
}

# --- GUI Theme Applicator ---
function Apply-GuiTheme {
    param($ThemeName)
    $pal = $GuiThemes[$ThemeName]
    if (-not $pal) { return }

    $Form.BackColor = $pal.FormBack
    $Form.ForeColor = $pal.Fore
    
    function Update-Control {
        param($ctrl)
        if ($ctrl -is [System.Windows.Forms.Panel]) {
            if ($ctrl.Name -eq "Sidebar") { $ctrl.BackColor = $pal.Sidebar }
            elseif ($ctrl.Name -eq "MainPanel") { $ctrl.BackColor = $pal.Main }
            elseif ($ctrl.Name -eq "Footer") { $ctrl.BackColor = $pal.Footer }
            elseif ($ctrl.Tag -eq "Page") { $ctrl.BackColor = $pal.Main }
            elseif ($ctrl.Name -eq "PnlPreview") { $ctrl.BackColor = $pal.BtnBack }
            else { $ctrl.BackColor = $pal.Main } 
        }
        
        if ($ctrl -is [System.Windows.Forms.Button]) {
            if ($ctrl.Text -eq $Lang.Execute) { 
                $ctrl.BackColor = $pal.Accent 
            } elseif ($ctrl.Tag -eq "SidebarBtn") {
                $ctrl.BackColor = $pal.BtnBack
                $ctrl.ForeColor = $pal.Fore
            } else {
                $ctrl.BackColor = $pal.BtnBack
                $ctrl.ForeColor = $pal.Fore
            }
        }
        
        if ($ctrl -is [System.Windows.Forms.TextBox] -or $ctrl -is [System.Windows.Forms.NumericUpDown]) {
            $ctrl.BackColor = $pal.BtnBack
            $ctrl.ForeColor = $pal.Fore
        }

        if ($ctrl -is [System.Windows.Forms.ComboBox]) {
            $ctrl.BackColor = $pal.BtnBack
            $ctrl.ForeColor = $pal.Fore
        }
        
        if ($ctrl -is [System.Windows.Forms.Label] -or $ctrl -is [System.Windows.Forms.CheckBox]) {
            $ctrl.ForeColor = $pal.Fore
        }
        
        if ($ctrl.Controls) {
            foreach ($c in $ctrl.Controls) { Update-Control $c }
        }
    }

    Update-Control $Form
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
# 7. JDOWNLOADER LOGIC (Existing)
# ==========================================
function Detect-JDPath {
    $paths = @("C:\Program Files\JDownloader", "C:\Program Files (x86)\JDownloader", "$env:LOCALAPPDATA\JDownloader 2", "$env:USERPROFILE\AppData\Local\JDownloader 2.0")
    foreach ($p in $paths) { if (Test-Path (Join-Path $p "JDownloader2.exe")) { return $p } }
    return $null
}

function Kill-JDownloader {
    Log-Status "Terminating JDownloader processes..."
    Get-Process | Where-Object { $_.ProcessName -match "JDownloader|javaw" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

function Backup-JD {
    param([string]$InstallPath)
    $stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $backupRoot = "$InstallPath\cfg-backup\$stamp"
    if (Test-Path "$InstallPath\cfg") {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        Copy-Item "$InstallPath\cfg\*" $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
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
            if (Test-Path $exe) {
                Stop-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($exe)) -Force -ErrorAction SilentlyContinue; Start-Sleep 1
                $bak = "$exe.bak"; if (-not (Test-Path $bak)) { Move-Item -Path $exe -Destination $bak -Force } else { Remove-Item $exe -Force -ErrorAction SilentlyContinue }
                Start-Process -FilePath $ResHackerExe -ArgumentList "-open `"$bak`" -save `"$exe`" -action addoverwrite -res `"$IconFile`" -mask ICONGROUP,MAINICON,0" -Wait -WindowStyle Hidden
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
        for ($i = 1; $i -le 7; $i++) { $part = ".{0:D3}" -f $i; Download-File -Url "$baseUrl$part" -Destination "$WorkDir\installer.7z$part" | Out-Null }
        Start-Process $seven -ArgumentList "x `"$WorkDir\installer.7z.001`" -o`"$WorkDir\Installer`" -y" -Wait -WindowStyle Hidden
        $setup = Get-ChildItem "$WorkDir\Installer" -Filter "*.exe" -Recurse | Select-Object -First 1
        if ($setup) { Start-Process $setup.FullName -ArgumentList "-q" -Wait; return $true }
    } elseif ($Source -eq "Mega") {
        Start-Process "https://mega.nz/file/PQ0XRIrA#-uuhLXSc_nPfotXWfBWDZRx90Gnehx2_Mx_JVufzfdM"
        [System.Windows.Forms.MessageBox]::Show("Download the file from Mega, then click OK.", "Manual Download") | Out-Null
        $f = Get-ChildItem "$env:USERPROFILE\Downloads" -Filter "JDownloader*Setup*.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($f) { Start-Process $f.FullName -ArgumentList "-q" -Wait; return $true }
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
    if ([string]::IsNullOrWhiteSpace($JDPath)) { Log-Status "Invalid path." "ERROR"; return }
    
    if ($GUI_State.Mode -ne "Modify") {
        if (-not (Task-Install -Source "GitHub")) { Task-Install -Source "Mega" }
        $JDPath = Detect-JDPath
    }
    
    $ProgressBar.Style = "Marquee"
    Kill-JDownloader; Backup-JD -InstallPath $JDPath
    
    $Theme = $ThemeDefinitions[$GUI_State.ThemeName]
    $IconDef = $IconDefinitions[$GUI_State.IconPack]
    $cfgPath = "$JDPath\cfg"
    $lafPath = "$cfgPath\laf"; if (-not (Test-Path $lafPath)) { New-Item -ItemType Directory -Path $lafPath -Force | Out-Null }
    
    Download-File -Url $Theme.JsonUrl -Destination "$lafPath\$($Theme.JsonName)" | Out-Null
    Task-PatchLaf -JsonPath "$lafPath\$($Theme.JsonName)" -IconSetId $IconDef.ID -WindowDecorations $GUI_State.WindowDec
    Task-ExtractIcons -ZipUrl $IconDef.Url -InstallPath $JDPath -TargetIconSet $IconDef.ID
    
    try {
        $guiObj = $Template_GUI | ConvertFrom-Json
        $guiObj.lookandfeeltheme = $Theme.LafID
        $guiObj | ConvertTo-Json -Depth 100 | Set-Content "$cfgPath\org.jdownloader.settings.GraphicalUserInterfaceSettings.json" -Encoding UTF8
    } catch {}

    try {
        $genObj = $Template_General | ConvertFrom-Json
        $genObj.maxsimultanedownloads = [int]$GUI_State.MaxSim
        $genObj.defaultdownloadfolder = $GUI_State.DlFolder.Replace("\", "\\")
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
    
    $ProgressBar.Style = "Blocks"; $ProgressBar.Value = 100
    Log-Status "Operations completed." "SUCCESS"
    if ($GUI_State.AutoUpdate) { Trigger-Update -InstallPath $JDPath }
    Save-Settings -SettingsObj $GUI_State
}

# ==========================================
# 8. GUI CONSTRUCTION (Enhanced)
# ==========================================

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$FormW = [int]($screen.Width * 0.75)
$FormH = [int]($screen.Height * 0.85)

$Form = New-Object System.Windows.Forms.Form
$Form.Text = $Lang.Title
$Form.Size = New-Object System.Drawing.Size($FormW, $FormH)
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "Sizable"
$Form.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)
$Form.ForeColor = [System.Drawing.Color]::White

# Sidebar (Left Dock)
$Sidebar = New-Object System.Windows.Forms.Panel
$Sidebar.Size = New-Object System.Drawing.Size(220, $FormH)
$Sidebar.Dock = "Left"
$Sidebar.BackColor = [System.Drawing.Color]::FromArgb(22,22,22)
$Sidebar.Name = "Sidebar"
$Form.Controls.Add($Sidebar)

function New-NavBtn {
    param($text, $y)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $text
    $btn.Location = New-Object System.Drawing.Point(10,$y)
    $btn.Size = New-Object System.Drawing.Size(200,40)
    $btn.FlatStyle = "Flat"
    $btn.BackColor = [System.Drawing.Color]::FromArgb(40,40,40)
    $btn.ForeColor = "White"
    $btn.Font = New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
    $btn.FlatAppearance.BorderSize = 0
    $btn.Tag = "SidebarBtn"
    return $btn
}

$BtnDashboard   = New-NavBtn $Lang.Dashboard    20
$BtnInstallation= New-NavBtn $Lang.Installation 70
$BtnTheme       = New-NavBtn $Lang.Themes      120
$BtnBehavior    = New-NavBtn $Lang.Behavior    170
$BtnHardening   = New-NavBtn $Lang.Hardening   220
$BtnRepair      = New-NavBtn $Lang.Repair      270

$Sidebar.Controls.AddRange(@($BtnDashboard, $BtnInstallation, $BtnTheme, $BtnBehavior, $BtnHardening, $BtnRepair))

# Footer (Bottom Dock)
$Footer = New-Object System.Windows.Forms.Panel
$Footer.Size = New-Object System.Drawing.Size($FormW, 50)
$Footer.Dock = "Bottom"
$Footer.BackColor = [System.Drawing.Color]::FromArgb(22,22,22)
$Footer.Name = "Footer"
$Form.Controls.Add($Footer)

$BtnExec = New-Object System.Windows.Forms.Button
$BtnExec.Text = $Lang.Execute
$BtnExec.Location = New-Object System.Drawing.Point(220, 5) # Offset from sidebar
$BtnExec.Size = New-Object System.Drawing.Size(360, 40)
$BtnExec.BackColor = [System.Drawing.Color]::FromArgb(30,144,255)
$BtnExec.ForeColor = "White"
$BtnExec.FlatStyle = "Flat"
$BtnExec.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$Footer.Controls.Add($BtnExec)

$ProgressBar = New-Object System.Windows.Forms.ProgressBar
$ProgressBar.Location = New-Object System.Drawing.Point(600, 15)
$ProgressBar.Size = New-Object System.Drawing.Size(300, 20)
$ProgressBar.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$Footer.Controls.Add($ProgressBar)

$StatusLabel = New-Object System.Windows.Forms.Label
$StatusLabel.Text = $Lang.Status
$StatusLabel.ForeColor = "LightGray"
$StatusLabel.Location = New-Object System.Drawing.Point(920, 15)
$StatusLabel.AutoSize = $true
$StatusLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$StatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$Footer.Controls.Add($StatusLabel)

# Main Panel (Fill Rest)
$MainPanel = New-Object System.Windows.Forms.Panel
$MainPanel.Dock = "Fill"
$MainPanel.BackColor = [System.Drawing.Color]::FromArgb(28,28,28)
$MainPanel.Name = "MainPanel"
$MainPanel.Padding = New-Object System.Windows.Forms.Padding(20)
$Form.Controls.Add($MainPanel)
$MainPanel.BringToFront()

# --- Pages Setup ---
function New-PagePanel {
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = "Fill"
    $p.BackColor = [System.Drawing.Color]::FromArgb(28,28,28)
    $p.Visible = $false
    $p.Tag = "Page"
    return $p
}

$PageDashboard   = New-PagePanel; $PageInstallation= New-PagePanel; $PageTheme = New-PagePanel
$PageBehavior    = New-PagePanel; $PageHardening   = New-PagePanel; $PageRepair = New-PagePanel
$MainPanel.Controls.AddRange(@($PageDashboard, $PageInstallation, $PageTheme, $PageBehavior, $PageHardening, $PageRepair))

# --- Dashboard Page ---
$DashTitle = New-Object System.Windows.Forms.Label; $DashTitle.Text = $Lang.DashTitle; $DashTitle.Font = New-Object System.Drawing.Font("Segoe UI",18,[System.Drawing.FontStyle]::Bold); $DashTitle.Location = New-Object System.Drawing.Point(20,20); $DashTitle.AutoSize = $true; $PageDashboard.Controls.Add($DashTitle)
$DashSub = New-Object System.Windows.Forms.Label; $DashSub.Text = $Lang.DashSub; $DashSub.Font = New-Object System.Drawing.Font("Segoe UI",11); $DashSub.Location = New-Object System.Drawing.Point(22,60); $DashSub.AutoSize = $true; $PageDashboard.Controls.Add($DashSub)
$DashHint = New-Object System.Windows.Forms.Label; $DashHint.Text = $Lang.DashHint; $DashHint.Font = New-Object System.Drawing.Font("Segoe UI",9); $DashHint.ForeColor = [System.Drawing.Color]::LightGray; $DashHint.Location = New-Object System.Drawing.Point(22,90); $DashHint.AutoSize = $true; $PageDashboard.Controls.Add($DashHint)

# GUI Theme
$LblGuiTheme = New-Object System.Windows.Forms.Label; $LblGuiTheme.Text = $Lang.GuiTheme; $LblGuiTheme.Location = New-Object System.Drawing.Point(22, 140); $LblGuiTheme.AutoSize=$true; $LblGuiTheme.Font = New-Object System.Drawing.Font("Segoe UI",11); $PageDashboard.Controls.Add($LblGuiTheme)
$CboGuiTheme = New-Object System.Windows.Forms.ComboBox; $CboGuiTheme.Location = New-Object System.Drawing.Point(22, 165); $CboGuiTheme.Width = 300; $CboGuiTheme.DropDownStyle="DropDownList"; $CboGuiTheme.BackColor=[System.Drawing.Color]::FromArgb(45,45,45); $CboGuiTheme.ForeColor="White"; 
$GuiThemes.Keys | ForEach-Object { $CboGuiTheme.Items.Add($_) } | Out-Null
$CboGuiTheme.SelectedIndex = 0; $PageDashboard.Controls.Add($CboGuiTheme)
$CboGuiTheme.Add_SelectedIndexChanged({ Apply-GuiTheme -ThemeName $CboGuiTheme.Text })

# Manual Language
$LblLang = New-Object System.Windows.Forms.Label; $LblLang.Text = $Lang.Language; $LblLang.Location = New-Object System.Drawing.Point(22, 210); $LblLang.AutoSize=$true; $LblLang.Font = New-Object System.Drawing.Font("Segoe UI",11); $PageDashboard.Controls.Add($LblLang)
$CboLang = New-Object System.Windows.Forms.ComboBox; $CboLang.Location = New-Object System.Drawing.Point(22, 235); $CboLang.Width = 300; $CboLang.DropDownStyle="DropDownList"; $CboLang.BackColor=[System.Drawing.Color]::FromArgb(45,45,45); $CboLang.ForeColor="White"; 
$AvailableLanguages.Keys | ForEach-Object { $CboLang.Items.Add($_) } | Out-Null
$CboLang.SelectedItem = $CurrentLangCode; $PageDashboard.Controls.Add($CboLang)

# Update Interface Text
function Update-InterfaceText {
    $t = $Lang
    $Form.Text = $t.Title
    $BtnDashboard.Text = $t.Dashboard; $BtnInstallation.Text = $t.Installation; $BtnTheme.Text = $t.Themes
    $BtnBehavior.Text = $t.Behavior; $BtnHardening.Text = $t.Hardening; $BtnRepair.Text = $t.Repair
    $BtnExec.Text = $t.Execute; $StatusLabel.Text = $t.Status
    
    $DashTitle.Text = $t.DashTitle; $DashSub.Text = $t.DashSub; $DashHint.Text = $t.DashHint; $LblGuiTheme.Text = $t.GuiTheme; $LblLang.Text = $t.Language
    
    $InstTitle.Text = $t.InstTitle; $InstSub.Text = $t.InstSub; $LblPath.Text = $t.InstPath
    $BtnBrowse.Text = $t.Browse; $BtnDetect.Text = $t.AutoDetect; $LblMode.Text = $t.InstMode; $LblModeHelp.Text = $t.InstModeHelp
    
    $ThemeTitle.Text = $t.ThemeTitle; $ThemeSub.Text = $t.ThemeSub; $LblThm.Text = $t.ThemePreset
    $LblThemeLink.Text = $t.OpenGithub; $ChkWinDec.Text = $t.EnableWinDec; $ChkMinLay.Text = $t.CompactTabs
    $LblIco.Text = $t.IconPack; $BtnOpenThm.Text = $t.OpenIconFolder

    $BehTitle.Text = $t.BehTitle; $BehSub.Text = $t.BehSub; $LblSim.Text = $t.MaxSim; $LblSimHelp.Text = $t.MaxSimHelp
    $LblPau.Text = $t.PauseSpeed; $LblPauHelp.Text = $t.PauseHelp; $LblDl.Text = $t.DefDlFolder
    $BtnDl.Text = $t.Browse; $ChkMin.Text = $t.StartMin; $ChkTray.Text = $t.MinToTray; $ChkCloseTray.Text = $t.CloseToTray
    
    $HardTitle.Text = $t.HardTitle; $HardSub.Text = $t.HardSub; $ChkExe.Text = $t.DarkExe; $ChkUpdate.Text = $t.RunUpdate; $HardNote.Text = $t.HardNote
    
    $RepTitle.Text = $t.RepTitle; $RepSub.Text = $t.RepSub
    # Note: Repair buttons text update requires storing refs or regenerating. Skipping for brevity as major labels are covered.
}

$CboLang.Add_SelectedIndexChanged({
    Apply-LanguageData $CboLang.Text
    Update-InterfaceText
})

# --- Installation Page ---
$InstTitle = New-Object System.Windows.Forms.Label; $InstTitle.Text = $Lang.InstTitle; $InstTitle.Font = New-Object System.Drawing.Font("Segoe UI",16,[System.Drawing.FontStyle]::Bold); $InstTitle.Location = New-Object System.Drawing.Point(20,20); $InstTitle.AutoSize = $true; $PageInstallation.Controls.Add($InstTitle)
$InstSub = New-Object System.Windows.Forms.Label; $InstSub.Text = $Lang.InstSub; $InstSub.Font = New-Object System.Drawing.Font("Segoe UI",9); $InstSub.ForeColor = "LightGray"; $InstSub.Location = New-Object System.Drawing.Point(22,50); $InstSub.AutoSize = $true; $PageInstallation.Controls.Add($InstSub)
$LblPath = New-Object System.Windows.Forms.Label; $LblPath.Text = $Lang.InstPath; $LblPath.Font = New-Object System.Drawing.Font("Segoe UI",11); $LblPath.Location = New-Object System.Drawing.Point(22,80); $LblPath.AutoSize = $true; $PageInstallation.Controls.Add($LblPath)
$TxtPath = New-Object System.Windows.Forms.TextBox; $TxtPath.Size = New-Object System.Drawing.Size(530,30); $TxtPath.Location = New-Object System.Drawing.Point(22,105); $TxtPath.Font = New-Object System.Drawing.Font("Segoe UI",10); $TxtPath.BackColor = [System.Drawing.Color]::FromArgb(40,40,40); $TxtPath.ForeColor = "White"; $PageInstallation.Controls.Add($TxtPath)
$BtnBrowse = New-Object System.Windows.Forms.Button; $BtnBrowse.Text = $Lang.Browse; $BtnBrowse.Size = New-Object System.Drawing.Size(110,27); $BtnBrowse.Location = New-Object System.Drawing.Point(560,104); $BtnBrowse.FlatStyle = "Flat"; $BtnBrowse.BackColor = [System.Drawing.Color]::FromArgb(45,45,45); $BtnBrowse.ForeColor = "White"; $BtnBrowse.Add_Click({ $fbd = New-Object System.Windows.Forms.FolderBrowserDialog; if ($fbd.ShowDialog() -eq "OK") { $TxtPath.Text = $fbd.SelectedPath } }); $PageInstallation.Controls.Add($BtnBrowse)
$BtnDetect = New-Object System.Windows.Forms.Button; $BtnDetect.Text = $Lang.AutoDetect; $BtnDetect.Size = New-Object System.Drawing.Size(110,27); $BtnDetect.Location = New-Object System.Drawing.Point(680,104); $BtnDetect.FlatStyle = "Flat"; $BtnDetect.BackColor = [System.Drawing.Color]::FromArgb(45,45,45); $BtnDetect.ForeColor = "White"; $BtnDetect.Add_Click({ $p = Detect-JDPath; if ($p) { $TxtPath.Text = $p; Log-Status "Auto detected: $p" } }); $PageInstallation.Controls.Add($BtnDetect)
$LblMode = New-Object System.Windows.Forms.Label; $LblMode.Text = $Lang.InstMode; $LblMode.Font = New-Object System.Drawing.Font("Segoe UI",11); $LblMode.Location = New-Object System.Drawing.Point(22,150); $LblMode.AutoSize = $true; $PageInstallation.Controls.Add($LblMode)
$CboMode = New-Object System.Windows.Forms.ComboBox; $CboMode.DropDownStyle = "DropDownList"; $CboMode.Items.AddRange(@("Modify Existing (keep current install)", "Clean Install (download from GitHub)", "Clean Install (manual Mega download)")); $CboMode.SelectedIndex = 0; $CboMode.Location = New-Object System.Drawing.Point(22,175); $CboMode.Size = New-Object System.Drawing.Size(450,30); $CboMode.BackColor = [System.Drawing.Color]::FromArgb(45,45,45); $CboMode.ForeColor = "White"; $PageInstallation.Controls.Add($CboMode)
$LblModeHelp = New-Object System.Windows.Forms.Label; $LblModeHelp.Text = $Lang.InstModeHelp; $LblModeHelp.Font = New-Object System.Drawing.Font("Segoe UI",8); $LblModeHelp.ForeColor = "LightGray"; $LblModeHelp.Location = New-Object System.Drawing.Point(22,210); $LblModeHelp.Size = New-Object System.Drawing.Size(780,40); $LblModeHelp.AutoSize = $false; $PageInstallation.Controls.Add($LblModeHelp)

# --- Themes Page ---
$ThemeTitle = New-Object System.Windows.Forms.Label; $ThemeTitle.Text = $Lang.ThemeTitle; $ThemeTitle.Font = New-Object System.Drawing.Font("Segoe UI",16,[System.Drawing.FontStyle]::Bold); $ThemeTitle.Location = New-Object System.Drawing.Point(20,20); $ThemeTitle.AutoSize = $true; $PageTheme.Controls.Add($ThemeTitle)
$ThemeSub = New-Object System.Windows.Forms.Label; $ThemeSub.Text = $Lang.ThemeSub; $ThemeSub.Font = New-Object System.Drawing.Font("Segoe UI",9); $ThemeSub.ForeColor = "LightGray"; $ThemeSub.Location = New-Object System.Drawing.Point(22,50); $ThemeSub.AutoSize = $true; $PageTheme.Controls.Add($ThemeSub)
$LblThm = New-Object System.Windows.Forms.Label; $LblThm.Text = $Lang.ThemePreset; $LblThm.Location = New-Object System.Drawing.Point(22,80); $LblThm.AutoSize = $true; $LblThm.Font = New-Object System.Drawing.Font("Segoe UI",11); $PageTheme.Controls.Add($LblThm)
$CboTheme = New-Object System.Windows.Forms.ComboBox; $CboTheme.Location = New-Object System.Drawing.Point(22,105); $CboTheme.Width = 350; $CboTheme.DropDownStyle = "DropDownList"; $CboTheme.BackColor = [System.Drawing.Color]::FromArgb(45,45,45); $CboTheme.ForeColor = "White"; $ThemeDefinitions.Keys | ForEach-Object { $CboTheme.Items.Add($_) } | Out-Null; $CboTheme.SelectedIndex = 0; $PageTheme.Controls.Add($CboTheme)

# NEW: Resizable anchored preview panel
$PnlPreview = New-Object System.Windows.Forms.Panel
$PnlPreview.Location = New-Object System.Drawing.Point(22,140)
$PnlPreview.BorderStyle = "FixedSingle"
$PnlPreview.BackColor = [System.Drawing.Color]::FromArgb(45,45,45)
$PnlPreview.Name = "PnlPreview"
# Anchor to top/left/right only, height will be controlled by our resize function
$PnlPreview.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor `
                     [System.Windows.Forms.AnchorStyles]::Left -bor `
                     [System.Windows.Forms.AnchorStyles]::Right
$PageTheme.Controls.Add($PnlPreview)

$PicThemePreview = New-Object System.Windows.Forms.PictureBox
$PicThemePreview.Dock = "Fill"
$PicThemePreview.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$PnlPreview.Controls.Add($PicThemePreview)

$LblPreDesc = New-Object System.Windows.Forms.Label; $LblPreDesc.Location = New-Object System.Drawing.Point(390,105); $LblPreDesc.Size = New-Object System.Drawing.Size(400,30); $LblPreDesc.AutoSize = $false; $LblPreDesc.Font = New-Object System.Drawing.Font("Segoe UI",9); $LblPreDesc.ForeColor = "Gainsboro"; $PageTheme.Controls.Add($LblPreDesc)

$LblThemeLink = New-Object System.Windows.Forms.LinkLabel; $LblThemeLink.Text = $Lang.OpenGithub; $LblThemeLink.Location = New-Object System.Drawing.Point(800,105); $LblThemeLink.AutoSize = $true; $LblThemeLink.LinkColor = "DeepSkyBlue"; $LblThemeLink.ActiveLinkColor = "DodgerBlue"; $PageTheme.Controls.Add($LblThemeLink); $LblThemeLink.Add_LinkClicked({ if ($LblThemeLink.Tag) { Start-Process $LblThemeLink.Tag | Out-Null } })

# Anchored Bottom Controls for Theme Page
$BottomPanel = New-Object System.Windows.Forms.Panel
$BottomPanel.Dock = "Bottom"
$BottomPanel.Height = 100
$BottomPanel.BackColor = [System.Drawing.Color]::Transparent
$PageTheme.Controls.Add($BottomPanel)

$ChkWinDec = New-Object System.Windows.Forms.CheckBox; $ChkWinDec.Text = $Lang.EnableWinDec; $ChkWinDec.Location = New-Object System.Drawing.Point(22,10); $ChkWinDec.AutoSize = $true; $ChkWinDec.Checked = $true; $ChkWinDec.Font = New-Object System.Drawing.Font("Segoe UI",10); $BottomPanel.Controls.Add($ChkWinDec)
$ChkMinLay = New-Object System.Windows.Forms.CheckBox; $ChkMinLay.Text = $Lang.CompactTabs; $ChkMinLay.Location = New-Object System.Drawing.Point(22,40); $ChkMinLay.AutoSize = $true; $ChkMinLay.Font = New-Object System.Drawing.Font("Segoe UI",10); $BottomPanel.Controls.Add($ChkMinLay)
$LblIco = New-Object System.Windows.Forms.Label; $LblIco.Text = $Lang.IconPack; $LblIco.Location = New-Object System.Drawing.Point(400,10); $LblIco.AutoSize = $true; $LblIco.Font = New-Object System.Drawing.Font("Segoe UI",11); $BottomPanel.Controls.Add($LblIco)
$CboIcons = New-Object System.Windows.Forms.ComboBox; $CboIcons.Location = New-Object System.Drawing.Point(400,35); $CboIcons.Width = 200; $CboIcons.DropDownStyle = "DropDownList"; $CboIcons.BackColor = [System.Drawing.Color]::FromArgb(45,45,45); $CboIcons.ForeColor = "White"; $IconDefinitions.Keys | ForEach-Object { $CboIcons.Items.Add($_) } | Out-Null; $CboIcons.SelectedIndex = 0; $BottomPanel.Controls.Add($CboIcons)
$BtnOpenThm = New-Object System.Windows.Forms.Button; $BtnOpenThm.Text = $Lang.OpenIconFolder; $BtnOpenThm.Location = New-Object System.Drawing.Point(620,34); $BtnOpenThm.Size = New-Object System.Drawing.Size(120,27); $BtnOpenThm.FlatStyle = "Flat"; $BtnOpenThm.BackColor = [System.Drawing.Color]::FromArgb(64,64,64); $BtnOpenThm.ForeColor = "White"; $BtnOpenThm.Add_Click({ $p = "$($TxtPath.Text)\themes\standard\org\jdownloader\images"; if (Test-Path $p) { Invoke-Item $p } }); $BottomPanel.Controls.Add($BtnOpenThm)

function Resize-ThemePreview {
    # Padding around the preview area
    $left = 22
    $top = 140
    $bottomMargin = 120   # leave room above the bottom panel
    $rightMargin = 22

    # Compute available size inside PageTheme
    $availWidth  = $PageTheme.ClientSize.Width  - $left - $rightMargin
    $availHeight = $PageTheme.ClientSize.Height - $top  - $bottomMargin

    if ($availWidth -lt 400)  { $availWidth  = 400 }
    if ($availHeight -lt 220) { $availHeight = 220 }

    $PnlPreview.Location = New-Object System.Drawing.Point($left, $top)
    $PnlPreview.Size     = New-Object System.Drawing.Size($availWidth, $availHeight)
}

function Update-ThemePreview {
    $sel = $ThemeDefinitions[$CboTheme.Text]
    if ($sel) {
        $LblPreDesc.Text = "$($sel.DisplayName) - $($sel.Desc)"
        $LblThemeLink.Tag = $sel.ThemeUrl
        if ($ThemeImageCache.ContainsKey($CboTheme.Text) -and $ThemeImageCache[$CboTheme.Text]) {
            $PicThemePreview.Image = $ThemeImageCache[$CboTheme.Text]
        } else {
            $PicThemePreview.Image = $null
        }
    }
}
$CboTheme.Add_SelectedIndexChanged({ Update-ThemePreview })

# --- Behavior Page ---
$BehTitle = New-Object System.Windows.Forms.Label; $BehTitle.Text = $Lang.BehTitle; $BehTitle.Font = New-Object System.Drawing.Font("Segoe UI",16,[System.Drawing.FontStyle]::Bold); $BehTitle.Location = New-Object System.Drawing.Point(20,20); $BehTitle.AutoSize = $true; $PageBehavior.Controls.Add($BehTitle)
$BehSub = New-Object System.Windows.Forms.Label; $BehSub.Text = $Lang.BehSub; $BehSub.Font = New-Object System.Drawing.Font("Segoe UI",9); $BehSub.ForeColor = "LightGray"; $BehSub.Location = New-Object System.Drawing.Point(22,50); $BehSub.AutoSize = $true; $PageBehavior.Controls.Add($BehSub)
$LblSim = New-Object System.Windows.Forms.Label; $LblSim.Text = $Lang.MaxSim; $LblSim.Location = New-Object System.Drawing.Point(22,80); $LblSim.AutoSize = $true; $LblSim.Font = New-Object System.Drawing.Font("Segoe UI",11); $PageBehavior.Controls.Add($LblSim)
$NumSim = New-Object System.Windows.Forms.NumericUpDown; $NumSim.Location = New-Object System.Drawing.Point(260,78); $NumSim.Minimum = 1; $NumSim.Maximum = 20; $NumSim.Value = 3; $NumSim.BackColor = [System.Drawing.Color]::FromArgb(45,45,45); $NumSim.ForeColor = "White"; $PageBehavior.Controls.Add($NumSim)
$LblSimHelp = New-Object System.Windows.Forms.Label; $LblSimHelp.Text = $Lang.MaxSimHelp; $LblSimHelp.Font = New-Object System.Drawing.Font("Segoe UI",8); $LblSimHelp.ForeColor = "LightGray"; $LblSimHelp.Location = New-Object System.Drawing.Point(22,105); $LblSimHelp.AutoSize = $true; $PageBehavior.Controls.Add($LblSimHelp)
$LblPau = New-Object System.Windows.Forms.Label; $LblPau.Text = $Lang.PauseSpeed; $LblPau.Location = New-Object System.Drawing.Point(22,135); $LblPau.AutoSize = $true; $LblPau.Font = New-Object System.Drawing.Font("Segoe UI",11); $PageBehavior.Controls.Add($LblPau)
$NumPause = New-Object System.Windows.Forms.NumericUpDown; $NumPause.Location = New-Object System.Drawing.Point(260,133); $NumPause.Minimum = 0; $NumPause.Maximum = 1000000; $NumPause.Value = 10240; $NumPause.BackColor = [System.Drawing.Color]::FromArgb(45,45,45); $NumPause.ForeColor = "White"; $PageBehavior.Controls.Add($NumPause)
$LblPauHelp = New-Object System.Windows.Forms.Label; $LblPauHelp.Text = $Lang.PauseHelp; $LblPauHelp.Font = New-Object System.Drawing.Font("Segoe UI",8); $LblPauHelp.ForeColor = "LightGray"; $LblPauHelp.Location = New-Object System.Drawing.Point(22,160); $LblPauHelp.AutoSize = $true; $PageBehavior.Controls.Add($LblPauHelp)
$LblDl = New-Object System.Windows.Forms.Label; $LblDl.Text = $Lang.DefDlFolder; $LblDl.Location = New-Object System.Drawing.Point(22,190); $LblDl.AutoSize = $true; $LblDl.Font = New-Object System.Drawing.Font("Segoe UI",11); $PageBehavior.Controls.Add($LblDl)
$TxtDl = New-Object System.Windows.Forms.TextBox; $TxtDl.Location = New-Object System.Drawing.Point(22,215); $TxtDl.Width = 530; $TxtDl.Text = "C:\Downloads"; $TxtDl.BackColor = [System.Drawing.Color]::FromArgb(45,45,45); $TxtDl.ForeColor = "White"; $PageBehavior.Controls.Add($TxtDl)
$BtnDl = New-Object System.Windows.Forms.Button; $BtnDl.Text = $Lang.Browse; $BtnDl.Location = New-Object System.Drawing.Point(560,214); $BtnDl.Width = 100; $BtnDl.FlatStyle = "Flat"; $BtnDl.BackColor = [System.Drawing.Color]::FromArgb(45,45,45); $BtnDl.ForeColor = "White"; $BtnDl.Add_Click({ $fbd = New-Object System.Windows.Forms.FolderBrowserDialog; if ($fbd.ShowDialog() -eq "OK") { $TxtDl.Text = $fbd.SelectedPath } }); $PageBehavior.Controls.Add($BtnDl)
$ChkMin = New-Object System.Windows.Forms.CheckBox; $ChkMin.Text = $Lang.StartMin; $ChkMin.Location = New-Object System.Drawing.Point(22,260); $ChkMin.AutoSize = $true; $ChkMin.Font = New-Object System.Drawing.Font("Segoe UI",10); $PageBehavior.Controls.Add($ChkMin)
$ChkTray = New-Object System.Windows.Forms.CheckBox; $ChkTray.Text = $Lang.MinToTray; $ChkTray.Location = New-Object System.Drawing.Point(22,290); $ChkTray.AutoSize = $true; $ChkTray.Checked = $true; $ChkTray.Font = New-Object System.Drawing.Font("Segoe UI",10); $PageBehavior.Controls.Add($ChkTray)
$ChkCloseTray = New-Object System.Windows.Forms.CheckBox; $ChkCloseTray.Text = $Lang.CloseToTray; $ChkCloseTray.Location = New-Object System.Drawing.Point(22,320); $ChkCloseTray.AutoSize = $true; $ChkCloseTray.Checked = $true; $ChkCloseTray.Font = New-Object System.Drawing.Font("Segoe UI",10); $PageBehavior.Controls.Add($ChkCloseTray)

# --- Hardening Page ---
$HardTitle = New-Object System.Windows.Forms.Label; $HardTitle.Text = $Lang.HardTitle; $HardTitle.Font = New-Object System.Drawing.Font("Segoe UI",16,[System.Drawing.FontStyle]::Bold); $HardTitle.Location = New-Object System.Drawing.Point(20,20); $HardTitle.AutoSize = $true; $PageHardening.Controls.Add($HardTitle)
$HardSub = New-Object System.Windows.Forms.Label; $HardSub.Text = $Lang.HardSub; $HardSub.Font = New-Object System.Drawing.Font("Segoe UI",9); $HardSub.ForeColor = "LightGray"; $HardSub.Location = New-Object System.Drawing.Point(22,50); $HardSub.AutoSize = $true; $PageHardening.Controls.Add($HardSub)
$ChkExe = New-Object System.Windows.Forms.CheckBox; $ChkExe.Text = $Lang.DarkExe; $ChkExe.Location = New-Object System.Drawing.Point(22,90); $ChkExe.AutoSize = $true; $ChkExe.Checked = $true; $ChkExe.Font = New-Object System.Drawing.Font("Segoe UI",11); $PageHardening.Controls.Add($ChkExe)
$ChkUpdate = New-Object System.Windows.Forms.CheckBox; $ChkUpdate.Text = $Lang.RunUpdate; $ChkUpdate.Location = New-Object System.Drawing.Point(22,130); $ChkUpdate.AutoSize = $true; $ChkUpdate.Checked = $true; $ChkUpdate.Font = New-Object System.Drawing.Font("Segoe UI",11); $PageHardening.Controls.Add($ChkUpdate)
$HardNote = New-Object System.Windows.Forms.Label; $HardNote.Text = $Lang.HardNote; $HardNote.Font = New-Object System.Drawing.Font("Segoe UI",9); $HardNote.ForeColor = "LightGray"; $HardNote.Location = New-Object System.Drawing.Point(22,170); $HardNote.Size = New-Object System.Drawing.Size(780,60); $HardNote.AutoSize = $false; $PageHardening.Controls.Add($HardNote)

# --- Repair Page ---
$RepTitle = New-Object System.Windows.Forms.Label; $RepTitle.Text = $Lang.RepTitle; $RepTitle.Font = New-Object System.Drawing.Font("Segoe UI",16,[System.Drawing.FontStyle]::Bold); $RepTitle.Location = New-Object System.Drawing.Point(20,20); $RepTitle.AutoSize = $true; $PageRepair.Controls.Add($RepTitle)
$RepSub = New-Object System.Windows.Forms.Label; $RepSub.Text = $Lang.RepSub; $RepSub.Font = New-Object System.Drawing.Font("Segoe UI",9); $RepSub.ForeColor = "LightGray"; $RepSub.Location = New-Object System.Drawing.Point(22,50); $RepSub.AutoSize = $true; $PageRepair.Controls.Add($RepSub)

function New-RepairBtn {
    param($txt, $x, $y, $col, $act)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $txt; $b.Location = New-Object System.Drawing.Point($x, $y); $b.Size = New-Object System.Drawing.Size(230, 40)
    $b.BackColor = $col; $b.ForeColor = "White"; $b.FlatStyle = "Flat"; $b.Add_Click($act)
    $PageRepair.Controls.Add($b)
    return $b
}

New-RepairBtn $Lang.BtnResetCfg 22 90 ([System.Drawing.Color]::OrangeRed) { if ([System.Windows.Forms.MessageBox]::Show("Close JDownloader and delete the 'cfg' folder?","Confirm","YesNo") -eq "Yes") { Kill-JDownloader; Backup-JD -InstallPath $TxtPath.Text; Remove-Item "$($TxtPath.Text)\cfg" -Recurse -Force -ErrorAction SilentlyContinue } }
New-RepairBtn $Lang.BtnResetThm 280 90 ([System.Drawing.Color]::FromArgb(64,64,64)) { if ([System.Windows.Forms.MessageBox]::Show("Reset theme and icons?","Confirm","YesNo") -eq "Yes") { Kill-JDownloader; Remove-Item "$($TxtPath.Text)\cfg\laf" -Recurse -Force; Remove-Item "$($TxtPath.Text)\themes\standard\org\jdownloader\images\*" -Recurse -Force } }
New-RepairBtn $Lang.BtnClearCache 538 90 ([System.Drawing.Color]::FromArgb(64,64,64)) { Kill-JDownloader; Remove-Item "$($TxtPath.Text)\tmp\*" -Recurse -Force; Remove-Item "$($TxtPath.Text)\cfg\*.cache" -Force }
New-RepairBtn $Lang.BtnAudit 22 150 ([System.Drawing.Color]::SeaGreen) { Run-Audit -InstallPath $TxtPath.Text }
New-RepairBtn $Lang.BtnSafe 280 150 ([System.Drawing.Color]::SeaGreen) { Start-Process "$($TxtPath.Text)\JDownloader2.exe" -ArgumentList "-safe" }
New-RepairBtn $Lang.BtnUninstall 538 150 ([System.Drawing.Color]::Maroon) { if ([System.Windows.Forms.MessageBox]::Show("Full Uninstall?","Confirm","YesNo") -eq "Yes") { Task-FullUninstall -InstallPath $TxtPath.Text } }

# ==========================================
# 9. CONFIRMATION DIALOG (Option B)
# ==========================================

function Show-ConfirmationDialog {
    if ([string]::IsNullOrWhiteSpace($TxtPath.Text)) { 
        [System.Windows.Forms.MessageBox]::Show("Please select an installation path first.", "Error")
        return $false 
    }

    $cForm = New-Object System.Windows.Forms.Form
    $cForm.Text = "Confirm Operations"
    $cForm.Size = New-Object System.Drawing.Size(500, 600)
    $cForm.StartPosition = "CenterParent"
    $cForm.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)
    $cForm.ForeColor = "White"
    $cForm.FormBorderStyle = "FixedDialog"
    $cForm.MaximizeBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Verify and select options to apply:"
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $lbl.Location = New-Object System.Drawing.Point(10,10); $lbl.AutoSize = $true
    $cForm.Controls.Add($lbl)

    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Location = New-Object System.Drawing.Point(10, 40)
    $flow.Size = New-Object System.Drawing.Size(460, 450)
    $flow.FlowDirection = "TopDown"
    $flow.WrapContents = $false
    $flow.AutoScroll = $true
    $cForm.Controls.Add($flow)

    function Add-Check {
        param($refCtrl, $txt)
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = $txt
        $cb.AutoSize = $true
        $cb.Checked = $refCtrl.Checked
        $cb.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $cb.ForeColor = "Gainsboro"
        $flow.Controls.Add($cb)
        return $cb
    }

    function Add-Info {
        param($txt, $val)
        $l = New-Object System.Windows.Forms.Label
        $l.Text = "$txt $val"
        $l.AutoSize = $true
        $l.ForeColor = "Gray"
        $l.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $flow.Controls.Add($l)
    }

    # Add items mapped to actual GUI controls
    Add-Info "Theme Preset:" $CboTheme.Text
    Add-Info "Mode:" $CboMode.Text
    
    $chk_WinDec = Add-Check $ChkWinDec "Enable custom window decorations"
    $chk_MinLay = Add-Check $ChkMinLay "Use compact/minimal tabs"
    $chk_StartMin = Add-Check $ChkMin "Start Minimized"
    $chk_Tray = Add-Check $ChkTray "Minimize to Tray"
    $chk_Close = Add-Check $ChkCloseTray "Close to Tray"
    $chk_Exe = Add-Check $ChkExe "Patch .exe icon to dark mode"
    $chk_Upd = Add-Check $ChkUpdate "Run Update after completion"

    # Buttons
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "RUN OPERATIONS"
    $btnOk.DialogResult = "OK"
    $btnOk.BackColor = [System.Drawing.Color]::FromArgb(30,144,255)
    $btnOk.ForeColor = "White"
    $btnOk.FlatStyle = "Flat"
    $btnOk.Size = New-Object System.Drawing.Size(150, 35)
    $btnOk.Location = New-Object System.Drawing.Point(20, 510)
    $cForm.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = "Cancel"
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(60,60,60)
    $btnCancel.ForeColor = "White"
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.Size = New-Object System.Drawing.Size(100, 35)
    $btnCancel.Location = New-Object System.Drawing.Point(180, 510)
    $cForm.Controls.Add($btnCancel)

    $result = $cForm.ShowDialog()
    
    if ($result -eq "OK") {
        # Apply changes back to real GUI (Option B)
        $ChkWinDec.Checked = $chk_WinDec.Checked
        $ChkMinLay.Checked = $chk_MinLay.Checked
        $ChkMin.Checked = $chk_StartMin.Checked
        $ChkTray.Checked = $chk_Tray.Checked
        $ChkCloseTray.Checked = $chk_Close.Checked
        $ChkExe.Checked = $chk_Exe.Checked
        $ChkUpdate.Checked = $chk_Upd.Checked
        return $true
    }
    return $false
}

# ==========================================
# 10. NAVIGATION & EXECUTION
# ==========================================

$pages = @{ $BtnDashboard=$PageDashboard; $BtnInstallation=$PageInstallation; $BtnTheme=$PageTheme; $BtnBehavior=$PageBehavior; $BtnHardening=$PageHardening; $BtnRepair=$PageRepair }
foreach ($entry in $pages.GetEnumerator()) {
    $entry.Key.Add_Click({ 
        foreach ($p in $pages.Values) { $p.Visible = $false }
        $this.Tag = "SidebarBtn"
        $pages[$this].Visible = $true 
        
        # Instant preview refresh when hitting Theme page
        if ($pages[$this] -eq $PageTheme) { Update-ThemePreview }
    })
}
$PageDashboard.Visible = $true

$Form.Add_Load({
    Preload-ThemeImages
    $CboTheme.SelectedIndex = 0

    # Initial layout for preview panel
    Resize-ThemePreview
    
    # OS Theme Detection
    $sysTheme = Detect-SystemTheme
    $CboGuiTheme.SelectedItem = $sysTheme
    Apply-GuiTheme -ThemeName $sysTheme
    
    # Path Detection & Mode Logic
    $detected = Detect-JDPath
    if ($detected) { 
        $TxtPath.Text = $detected
        $CboMode.SelectedIndex = 0 # Modify Existing
        Log-Status "Found JDownloader at: $detected"
    } else { 
        $CboMode.SelectedIndex = 1 # Clean Install GitHub
        Log-Status "JDownloader not found. defaulted to Clean Install."
    }

    # Load Settings
    $saved = Load-Settings
    if ($saved) {
        if ($saved.PSObject.Properties.Name -contains 'InstallPath') { $TxtPath.Text = $saved.InstallPath }
        if ($saved.PSObject.Properties.Name -contains 'ThemeName')  { $CboTheme.Text = $saved.ThemeName }
        if ($saved.PSObject.Properties.Name -contains 'GuiThemeName'){ $CboGuiTheme.Text = $saved.GuiThemeName }
    }
})

$Form.Add_Resize({
    Resize-ThemePreview
})

$BtnExec.Add_Click({
    if (Show-ConfirmationDialog) {
        $BtnExec.Enabled = $false; $BtnExec.Text = "Processing..."
        $mode = if($CboMode.SelectedIndex -eq 0){"Modify"}else{"Install"}
        $src = if($CboMode.SelectedIndex -eq 2){"Mega"}else{"GitHub"}
        
        $State = @{ Mode=$mode; InstallSource=$src; InstallPath=$TxtPath.Text; ThemeName=$CboTheme.Text; GuiThemeName=$CboGuiTheme.Text; IconPack=$CboIcons.Text; WindowDec=$ChkWinDec.Checked; MaxSim=$NumSim.Value; DlFolder=$TxtDl.Text; StartMin=$ChkMin.Checked; MinToTray=$ChkTray.Checked; CloseToTray=$ChkCloseTray.Checked; PatchExe=$ChkExe.Checked; AutoUpdate=$ChkUpdate.Checked; ForceMinimal=$ChkMinLay.Checked; PauseSpeed=$NumPause.Value }
        
        $Form.Refresh()
        Execute-Operations -GUI_State $State
        $BtnExec.Text = $Lang.Execute; $BtnExec.Enabled = $true
        [System.Windows.Forms.MessageBox]::Show("Operations completed.", "Done") | Out-Null
    }
})

[void]$Form.ShowDialog()