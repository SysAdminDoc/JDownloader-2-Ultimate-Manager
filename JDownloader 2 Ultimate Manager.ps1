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

# ==========================================
# 3. LANGUAGE & GUI THEME ENGINE
# ==========================================

# --- Default English Fallback ---
$DefaultLang = [ordered]@{
    "Title" = "JDownloader 2 Ultimate Manager v13.4";
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
                        # Cache raw stream or image - keep stream open or use FromStream validation
                        $img = [System.Drawing.Image]::FromStream($ms)
                        if ($script:ThemeImageCache.ContainsKey($k)) { $script:ThemeImageCache[$k].Dispose() }
                        $script:ThemeImageCache[$k] = $img
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

# Enhanced Theme Engine
function Apply-GuiTheme {
    param($ThemeName)
    $pal = $GuiThemes[$ThemeName]
    if (-not $pal) { return }

    $Form.BackColor = $pal.FormBack
    $Form.ForeColor = $pal.Fore
    
    function Update-Control {
        param($ctrl)
        
        $styled = $false
        if ($ctrl.Tag -is [string]) {
            switch ($ctrl.Tag) {
                "Sidebar" { $ctrl.BackColor = $pal.Sidebar; $styled=$true }
                "MainPanel" { $ctrl.BackColor = $pal.Main; $styled=$true }
                "Footer" { $ctrl.BackColor = $pal.Footer; $styled=$true }
                "Page" { $ctrl.BackColor = $pal.Main; $styled=$true }
                "PreviewPanel" { $ctrl.BackColor = $pal.BtnBack; $styled=$true }
                "PrimaryButton" { $ctrl.BackColor = $pal.Accent; $ctrl.ForeColor = "White"; $styled=$true }
                "DangerButton" { $ctrl.BackColor = [System.Drawing.Color]::Maroon; $ctrl.ForeColor = "White"; $styled=$true }
                "SuccessButton" { $ctrl.BackColor = [System.Drawing.Color]::SeaGreen; $ctrl.ForeColor = "White"; $styled=$true }
                "NavButton" { $ctrl.BackColor = $pal.BtnBack; $ctrl.ForeColor = $pal.Fore; $styled=$true }
                "Input" { $ctrl.BackColor = $pal.BtnBack; $ctrl.ForeColor = $pal.Fore; $styled=$true }
                "SectionHeader" { $ctrl.ForeColor = $pal.Fore; $styled=$true }
                "SubHeader" { $ctrl.ForeColor = "LightGray"; $styled=$true }
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
            if ($ctrl -is [System.Windows.Forms.Button] -and $ctrl.Tag -ne "SidebarBtn") {
                 $ctrl.BackColor = $pal.BtnBack
                 $ctrl.ForeColor = $pal.Fore
            }
             if ($ctrl -is [System.Windows.Forms.TextBox] -or $ctrl -is [System.Windows.Forms.NumericUpDown] -or $ctrl -is [System.Windows.Forms.ComboBox]) {
                $ctrl.BackColor = $pal.BtnBack
                $ctrl.ForeColor = $pal.Fore
                if ($ctrl -is [System.Windows.Forms.TextBox]) { $ctrl.BorderStyle = "FixedSingle" }
            }
            if ($ctrl -is [System.Windows.Forms.Label] -or $ctrl -is [System.Windows.Forms.CheckBox]) {
                $ctrl.ForeColor = $pal.Fore
            }
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
    
    # Catch-all error trap
    try {
        if ($GUI_State.Mode -ne "Modify") {
            if (-not (Task-Install -Source "GitHub")) { Task-Install -Source "Mega" }
            $JDPath = Detect-JDPath
        }
        
        $ProgressBar.Style = "Marquee"
        Kill-JDownloader; Backup-JD -InstallPath $JDPath
        
        # [Fix] Use .Contains instead of .ContainsKey for OrderedDictionary
        if ($ThemeDefinitions.Contains($GUI_State.ThemeName)) {
            $Theme = $ThemeDefinitions[$GUI_State.ThemeName]
            $cfgPath = "$JDPath\cfg"
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
    } catch {
        Log-Status "CRITICAL ERROR: $_" "FATAL"
        Log-Status $($_.ScriptStackTrace) "DEBUG"
        [System.Windows.Forms.MessageBox]::Show("An error occurred during execution. check logs. `nError: $_", "Error")
    }
}

# ==========================================
# 8. GUI CONSTRUCTION (Refined Layout)
# ==========================================

# UI Builder Functions with proper Anchors and DPI sizing

function New-Panel {
    param($Name, $Parent, $Dock, $Size, $Location, $BackColor, $Tag, $Padding, $Anchor)
    $p = New-Object System.Windows.Forms.Panel
    if($Name){$p.Name=$Name}
    if($Dock){$p.Dock=$Dock}
    if($Size){$p.Size=$Size}
    if($Location){$p.Location=$Location}
    if($BackColor){$p.BackColor=$BackColor}
    if($Tag){$p.Tag=$Tag}
    if($Padding){$p.Padding=$Padding}
    if($Anchor){$p.Anchor=$Anchor}
    if($Parent){ [void]$Parent.Controls.Add($p) }
    return $p
}

function New-Button {
    param($Name, $Parent, $Text, $LangKey, $Location, $Size, $Tag, $Click, $Anchor)
    $b = New-Object System.Windows.Forms.Button
    if($Name){$b.Name=$Name}
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 0
    if($Location){$b.Location=$Location}
    if($Size){$b.Size=$Size}
    if($Tag){$b.Tag=$Tag}
    if($Anchor){$b.Anchor=$Anchor}
    if($Click){$b.Add_Click($Click)}
    
    if($LangKey) {
        Register-LangControl -Control $b -Key $LangKey
    } elseif ($Text) {
        $b.Text = $Text
    }
    
    # Defaults + Hover Effect
    # UPDATED FONT SIZE: 14pt (was 12)
    $b.Font = New-Object System.Drawing.Font("Segoe UI",14)
    $b.AutoSize = $false
    
    if ($Tag -eq "SidebarBtn") { 
        # UPDATED FONT SIZE: 14pt Bold (was 12)
        $b.Font = New-Object System.Drawing.Font("Segoe UI",14,[System.Drawing.FontStyle]::Bold) 
    } elseif ($Tag -match "Primary|Danger|Success") {
        # UPDATED FONT SIZE: 14pt Bold (was 12)
        $b.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
        # Add hover effect with local storage
        $b.Add_MouseEnter({ 
            $this | Add-Member -MemberType NoteProperty -Name "LastColor" -Value $this.BackColor -Force -ErrorAction SilentlyContinue
            $this.BackColor = [System.Windows.Forms.ControlPaint]::Light($this.BackColor, 0.2) 
        })
        $b.Add_MouseLeave({ 
            if ($this.LastColor) { $this.BackColor = $this.LastColor } 
        })
    }

    if($Parent){ [void]$Parent.Controls.Add($b) }
    return $b
}

function New-Label {
    param($Name, $Parent, $Text, $LangKey, $Location, $Font, $AutoSize=$true, $Tag, $Size, $Anchor)
    $l = New-Object System.Windows.Forms.Label
    if($Name){$l.Name=$Name}
    if($Location){$l.Location=$Location}
    $l.AutoSize=$AutoSize
    if($Size){$l.Size=$Size}
    if($Tag){$l.Tag=$Tag}
    if($Anchor){$l.Anchor=$Anchor}
    
    # UPDATED FONT SIZES
    if ($Font) { $l.Font = $Font } 
    elseif ($Tag -eq "SectionHeader") { $l.Font = New-Object System.Drawing.Font("Segoe UI",20,[System.Drawing.FontStyle]::Bold) } 
    elseif ($Tag -eq "SubHeader") { $l.Font = New-Object System.Drawing.Font("Segoe UI",14) } 
    else { $l.Font = New-Object System.Drawing.Font("Segoe UI",13) } 

    if($LangKey) {
        Register-LangControl -Control $l -Key $LangKey
    } elseif ($Text) {
        $l.Text = $Text
    }
    
    if($Parent){ [void]$Parent.Controls.Add($l) }
    return $l
}

function New-TextBox {
    param($Name, $Parent, $Location, $Size, $Text, $Tag, $ReadOnly=$false, $Anchor)
    $t = New-Object System.Windows.Forms.TextBox
    if($Name){$t.Name=$Name}
    if($Location){$t.Location=$Location}
    if($Size){$t.Size=$Size}
    if($Text){$t.Text=$Text}
    if($Tag){$t.Tag=$Tag}
    if($Anchor){$t.Anchor=$Anchor}
    $t.ReadOnly=$ReadOnly
    # UPDATED FONT SIZE: 12pt (was 10)
    $t.Font = New-Object System.Drawing.Font("Segoe UI",12)
    $t.BorderStyle = "FixedSingle"
    
    if($Parent){ [void]$Parent.Controls.Add($t) }
    return $t
}

function New-ComboBox {
    param($Name, $Parent, $Location, $Size, $Tag, $Items, $SelectedIndex=0, $Anchor)
    $c = New-Object System.Windows.Forms.ComboBox
    if($Name){$c.Name=$Name}
    if($Location){$c.Location=$Location}
    if($Size){$c.Size=$Size}
    if($Tag){$c.Tag=$Tag}
    if($Anchor){$c.Anchor=$Anchor}
    $c.DropDownStyle="DropDownList"
    $c.IntegralHeight = $false # prevents resizing weirdly
    # UPDATED FONT SIZE: 12pt (was default)
    $c.Font = New-Object System.Drawing.Font("Segoe UI",12)
    # Ensure Add() output is suppressed
    if($Items){ foreach($i in $Items){ [void]$c.Items.Add($i) } }
    if($SelectedIndex -ge 0 -and $c.Items.Count -gt 0){$c.SelectedIndex=$SelectedIndex}
    
    if($Parent){ [void]$Parent.Controls.Add($c) }
    return $c
}

function New-CheckBox {
    param($Name, $Parent, $Text, $LangKey, $Location, $Tag, $Checked=$false, $Anchor)
    $c = New-Object System.Windows.Forms.CheckBox
    if($Name){$c.Name=$Name}
    if($Location){$c.Location=$Location}
    if($Tag){$c.Tag=$Tag}
    if($Anchor){$c.Anchor=$Anchor}
    $c.AutoSize = $true
    $c.Checked = $Checked
    # UPDATED FONT SIZE: 12pt (was 10)
    $c.Font = New-Object System.Drawing.Font("Segoe UI",12)

    if($LangKey) {
        Register-LangControl -Control $c -Key $LangKey
    } elseif ($Text) {
        $c.Text = $Text
    }

    if($Parent){ [void]$Parent.Controls.Add($c) }
    return $c
}

function New-NumericUpDown {
    param($Name, $Parent, $Location, $Tag, $Min, $Max, $Value, $Anchor)
    $n = New-Object System.Windows.Forms.NumericUpDown
    if($Name){$n.Name=$Name}
    if($Location){$n.Location=$Location}
    if($Tag){$n.Tag=$Tag}
    if($Anchor){$n.Anchor=$Anchor}
    if($Min){$n.Minimum=$Min}
    if($Max){$n.Maximum=$Max}
    if($Value){$n.Value=$Value}
    # UPDATED FONT SIZE: 12pt
    $n.Font = New-Object System.Drawing.Font("Segoe UI",12)
    $n.Size = New-Object System.Drawing.Size(120, 30) # Increased height
    
    if($Parent){ [void]$Parent.Controls.Add($n) }
    return $n
}

# --- Main Form ---
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
$Form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$Form.AutoScaleMode = "Dpi"
$Form.WindowState = 'Maximized'


# Sidebar (Left Dock) - Increased Width to 260 for larger fonts
$Sidebar = New-Panel -Name "Sidebar" -Parent $Form -Dock "Left" -Size (New-Object System.Drawing.Size(260, $FormH)) -Tag "Sidebar"

# Dynamic Sidebar Layout Calculation
[int]$sbY = 20
[int]$sbH = 50 # Increased Button Height
[int]$sbGap = 10
$BtnDashboard    = New-Button -Parent $Sidebar -LangKey "Dashboard"    -Location (New-Object System.Drawing.Point(10,$sbY))  -Size (New-Object System.Drawing.Size(240,$sbH)) -Tag "SidebarBtn"
$sbY += $sbH + $sbGap
$BtnInstallation = New-Button -Parent $Sidebar -LangKey "Installation" -Location (New-Object System.Drawing.Point(10,$sbY))  -Size (New-Object System.Drawing.Size(240,$sbH)) -Tag "SidebarBtn"
$sbY += $sbH + $sbGap
$BtnTheme        = New-Button -Parent $Sidebar -LangKey "Themes"       -Location (New-Object System.Drawing.Point(10,$sbY)) -Size (New-Object System.Drawing.Size(240,$sbH)) -Tag "SidebarBtn"
$sbY += $sbH + $sbGap
$BtnBehavior     = New-Button -Parent $Sidebar -LangKey "Behavior"     -Location (New-Object System.Drawing.Point(10,$sbY)) -Size (New-Object System.Drawing.Size(240,$sbH)) -Tag "SidebarBtn"
$sbY += $sbH + $sbGap
$BtnHardening    = New-Button -Parent $Sidebar -LangKey "Hardening"    -Location (New-Object System.Drawing.Point(10,$sbY)) -Size (New-Object System.Drawing.Size(240,$sbH)) -Tag "SidebarBtn"
$sbY += $sbH + $sbGap
$BtnRepair       = New-Button -Parent $Sidebar -LangKey "Repair"       -Location (New-Object System.Drawing.Point(10,$sbY)) -Size (New-Object System.Drawing.Size(240,$sbH)) -Tag "SidebarBtn"

# Footer (Bottom Dock)
$Footer = New-Panel -Name "Footer" -Parent $Form -Dock "Bottom" -Size (New-Object System.Drawing.Size($FormW, 60)) -Tag "Footer"

$BtnExec = New-Button -Parent $Footer -LangKey "Execute" -Location (New-Object System.Drawing.Point(280, 8)) -Size (New-Object System.Drawing.Size(360, 44)) -Tag "PrimaryButton" -Anchor ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left)

$ProgressBar = New-Object System.Windows.Forms.ProgressBar
$ProgressBar.Location = New-Object System.Drawing.Point(660, 20)
$ProgressBar.Size = New-Object System.Drawing.Size(280, 25)
$ProgressBar.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
[void]$Footer.Controls.Add($ProgressBar)

$StatusLabel = New-Label -Parent $Footer -LangKey "Status" -Location (New-Object System.Drawing.Point(960, 20)) -Font (New-Object System.Drawing.Font("Segoe UI", 14)) -Anchor ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)

# Main Panel (Fill Rest) - Increased Padding to 30
$MainPanel = New-Panel -Name "MainPanel" -Parent $Form -Dock "Fill" -Tag "MainPanel" -Padding (New-Object System.Windows.Forms.Padding(30))
[void]$MainPanel.BringToFront()

# --- Pages Setup ---
function New-PagePanel {
    $p = New-Panel -Dock "Fill" -Tag "Page" -BackColor ([System.Drawing.Color]::FromArgb(28,28,28))
    $p.Visible = $false
    return $p
}

$PageDashboard   = New-PagePanel; [void]$MainPanel.Controls.Add($PageDashboard)
$PageInstallation= New-PagePanel; [void]$MainPanel.Controls.Add($PageInstallation)
$PageTheme       = New-PagePanel; [void]$MainPanel.Controls.Add($PageTheme)
$PageBehavior    = New-PagePanel; [void]$MainPanel.Controls.Add($PageBehavior)
$PageHardening   = New-PagePanel; [void]$MainPanel.Controls.Add($PageHardening)
$PageRepair      = New-PagePanel; [void]$MainPanel.Controls.Add($PageRepair)

# Layout constants for Dynamic Positioning
[int]$padX = 30
[int]$padY = 30
[int]$gapSmall = 15
[int]$gapMed = 30
[int]$gapLarge = 40
[int]$inputH = 35

# --- Dashboard Page ---
[int]$curY = $padY
$DashTitle = New-Label -Parent $PageDashboard -LangKey "DashTitle" -Location (New-Object System.Drawing.Point($padX,$curY)) -Tag "SectionHeader"
$curY += $DashTitle.Height + $gapSmall
$DashSub = New-Label -Parent $PageDashboard -LangKey "DashSub" -Location (New-Object System.Drawing.Point($padX,$curY)) -Tag "SubHeader"
$curY += $DashSub.Height + $gapSmall
$DashHint = New-Label -Parent $PageDashboard -LangKey "DashHint" -Location (New-Object System.Drawing.Point($padX,$curY)) -Font (New-Object System.Drawing.Font("Segoe UI",14)) -Tag "SubHeader"

$curY += $DashHint.Height + 50 # Spacer

# GUI Theme
$LblGuiTheme = New-Label -Parent $PageDashboard -LangKey "GuiTheme" -Location (New-Object System.Drawing.Point($padX, $curY))
$curY += $LblGuiTheme.Height + 5
$CboGuiTheme = New-ComboBox -Parent $PageDashboard -Location (New-Object System.Drawing.Point($padX, $curY)) -Size (New-Object System.Drawing.Size(350, $inputH)) -Tag "Input" -Items $GuiThemes.Keys
$CboGuiTheme.SelectedIndex = 0
$CboGuiTheme.Add_SelectedIndexChanged({ Apply-GuiTheme -ThemeName $CboGuiTheme.Text })

$curY += $inputH + $gapMed

# Manual Language
$LblLang = New-Label -Parent $PageDashboard -LangKey "Language" -Location (New-Object System.Drawing.Point($padX, $curY))
$curY += $LblLang.Height + 5
$CboLang = New-ComboBox -Parent $PageDashboard -Location (New-Object System.Drawing.Point($padX, $curY)) -Size (New-Object System.Drawing.Size(350, $inputH)) -Tag "Input" -Items $AvailableLanguages.Keys
$CboLang.SelectedItem = $CurrentLangCode

# Logic Update Interface
function Update-InterfaceText {
    $Form.Text = $Lang.Title
    # Iterate registry to update text
    foreach ($entry in $script:LanguageRegistry) {
        if ($entry.Control -and $entry.Control.IsDisposed -eq $false) {
            $entry.Control.Text = $Lang[$entry.Key]
            # Enforce auto-size checks for labels
            if ($entry.Control -is [System.Windows.Forms.Label]) {
                 # Force refresh of bounds if needed
            }
        }
    }
}

$CboLang.Add_SelectedIndexChanged({
    Apply-LanguageData $CboLang.Text
    Update-InterfaceText
})

# --- Installation Page ---
$curY = $padY
$InstTitle = New-Label -Parent $PageInstallation -LangKey "InstTitle" -Location (New-Object System.Drawing.Point($padX,$curY)) -Tag "SectionHeader"
$curY += $InstTitle.Height + $gapSmall
$InstSub = New-Label -Parent $PageInstallation -LangKey "InstSub" -Location (New-Object System.Drawing.Point($padX,$curY)) -Tag "SubHeader"
$curY += $InstSub.Height + $gapLarge

$LblPath = New-Label -Parent $PageInstallation -LangKey "InstPath" -Location (New-Object System.Drawing.Point($padX,$curY))
$curY += $LblPath.Height + 5
$TxtPath = New-TextBox -Parent $PageInstallation -Location (New-Object System.Drawing.Point($padX,$curY)) -Size (New-Object System.Drawing.Size(600,$inputH)) -Tag "Input" -Anchor ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)

# Inline Validation
$TxtPath.Add_TextChanged({
    if ($TxtPath.Text.Length -gt 0 -and (-not (Test-Path $TxtPath.Text))) {
        $TxtPath.BackColor = [System.Drawing.Color]::FromArgb(60,20,20) # Red-ish
    } else {
        $TxtPath.BackColor = [System.Drawing.Color]::FromArgb(40,40,40)
    }
})

$BtnBrowse = New-Button -Parent $PageInstallation -LangKey "Browse" -Location (New-Object System.Drawing.Point(640,[int]($curY-1))) -Size (New-Object System.Drawing.Size(120,[int]($inputH+2))) -Tag "NavButton" -Anchor ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
$BtnBrowse.Add_Click({ $fbd = New-Object System.Windows.Forms.FolderBrowserDialog; if ($fbd.ShowDialog() -eq "OK") { $TxtPath.Text = $fbd.SelectedPath } })

$BtnDetect = New-Button -Parent $PageInstallation -LangKey "AutoDetect" -Location (New-Object System.Drawing.Point(770,[int]($curY-1))) -Size (New-Object System.Drawing.Size(140,[int]($inputH+2))) -Tag "NavButton" -Anchor ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
$BtnDetect.Add_Click({ $p = Detect-JDPath; if ($p) { $TxtPath.Text = $p; Log-Status "Auto detected: $p" } })

$curY += $inputH + $gapMed

$LblMode = New-Label -Parent $PageInstallation -LangKey "InstMode" -Location (New-Object System.Drawing.Point($padX,$curY))
$curY += $LblMode.Height + 5
$CboMode = New-ComboBox -Parent $PageInstallation -Location (New-Object System.Drawing.Point($padX,$curY)) -Size (New-Object System.Drawing.Size(500,$inputH)) -Tag "Input" -Items @("Modify Existing (keep current install)", "Clean Install (download from GitHub)", "Clean Install (manual Mega download)")
$curY += $inputH + $gapSmall
$LblModeHelp = New-Label -Parent $PageInstallation -LangKey "InstModeHelp" -Location (New-Object System.Drawing.Point($padX,$curY)) -Size (New-Object System.Drawing.Size(800,60)) -Font (New-Object System.Drawing.Font("Segoe UI",14)) -Tag "SubHeader"

# --- Themes Page ---
$curY = $padY
$ThemeTitle = New-Label -Parent $PageTheme -LangKey "ThemeTitle" -Location (New-Object System.Drawing.Point($padX,$curY)) -Tag "SectionHeader"
$curY += $ThemeTitle.Height + $gapSmall
$ThemeSub = New-Label -Parent $PageTheme -LangKey "ThemeSub" -Location (New-Object System.Drawing.Point($padX,$curY)) -Tag "SubHeader"
$curY += $ThemeSub.Height + $gapMed

$LblThm = New-Label -Parent $PageTheme -LangKey "ThemePreset" -Location (New-Object System.Drawing.Point($padX,$curY))
$curY += $LblThm.Height + 5
$CboTheme = New-ComboBox -Parent $PageTheme -Location (New-Object System.Drawing.Point($padX,$curY)) -Size (New-Object System.Drawing.Size(400, $inputH)) -Tag "Input" -Items $ThemeDefinitions.Keys

$LblPreDesc = New-Label -Parent $PageTheme -Location (New-Object System.Drawing.Point([int]($padX + 420),$curY)) -Size (New-Object System.Drawing.Size(450,40)) -Font (New-Object System.Drawing.Font("Segoe UI",14)) -Tag "SubHeader" -Anchor ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)

$LblThemeLink = New-Object System.Windows.Forms.LinkLabel; 
$LblThemeLink.Text = $Lang.OpenGithub; 
$LblThemeLink.Location = New-Object System.Drawing.Point(880,[int]($curY+5)); 
$LblThemeLink.AutoSize = $true; 
$LblThemeLink.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$LblThemeLink.LinkColor = "DeepSkyBlue"; 
$LblThemeLink.ActiveLinkColor = "DodgerBlue";
$LblThemeLink.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
[void]$PageTheme.Controls.Add($LblThemeLink); 
$LblThemeLink.Add_LinkClicked({ if ($LblThemeLink.Tag) { Start-Process $LblThemeLink.Tag | Out-Null } })

$curY += $inputH + $gapMed

# Resizable anchored preview panel - Moved further down for breathing room
$PnlPreview = New-Panel -Name "PnlPreview" -Parent $PageTheme -Tag "PreviewPanel" -Location (New-Object System.Drawing.Point($padX,$curY))
$PnlPreview.BorderStyle = "FixedSingle"
$PnlPreview.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom

$PicThemePreview = New-Object System.Windows.Forms.PictureBox
$PicThemePreview.Dock = "Fill"
$PicThemePreview.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
[void]$PnlPreview.Controls.Add($PicThemePreview)

# Anchored Bottom Controls for Theme Page - Taller to fit large controls
[int]$BottomPanelH = 140
$BottomPanel = New-Panel -Parent $PageTheme -Dock "Bottom" -Size (New-Object System.Drawing.Size(100, $BottomPanelH)) -BackColor ([System.Drawing.Color]::Transparent)

$ChkWinDec = New-CheckBox -Parent $BottomPanel -LangKey "EnableWinDec" -Location (New-Object System.Drawing.Point($padX,20)) -Checked $true
$ChkMinLay = New-CheckBox -Parent $BottomPanel -LangKey "CompactTabs" -Location (New-Object System.Drawing.Point($padX,60))
$LblIco = New-Label -Parent $BottomPanel -LangKey "IconPack" -Location (New-Object System.Drawing.Point([int]($padX + 400),20))
$CboIcons = New-ComboBox -Parent $BottomPanel -Location (New-Object System.Drawing.Point([int]($padX + 400),55)) -Size (New-Object System.Drawing.Size(220, $inputH)) -Tag "Input" -Items $IconDefinitions.Keys

$BtnOpenThm = New-Button -Parent $BottomPanel -LangKey "OpenIconFolder" -Location (New-Object System.Drawing.Point([int]($padX + 640),54)) -Size (New-Object System.Drawing.Size(180,[int]($inputH+2))) -Tag "NavButton"
$BtnOpenThm.Add_Click({ $p = "$($TxtPath.Text)\themes\standard\org\jdownloader\images"; if (Test-Path $p) { Invoke-Item $p } })

function Resize-ThemePreview {
    # Logic to prevent overlapping and stretching
    if ($Form.WindowState -eq "Minimized") { return }
    $topMargin = $PnlPreview.Location.Y # Dynamic top
    $botMargin = $BottomPanel.Height # Dynamic bottom reference
    $availH = $PageTheme.ClientSize.Height - $topMargin - $botMargin - 30
    
    if ($availH -lt 150) { $availH = 150 }
    
    $PnlPreview.Height = $availH
}

function Update-ThemePreview {
    $sel = $ThemeDefinitions[$CboTheme.Text]
    if ($sel) {
        $LblPreDesc.Text = "$($sel.DisplayName) - $($sel.Desc)"
        $LblThemeLink.Tag = $sel.ThemeUrl
        if ($ThemeImageCache.ContainsKey($CboTheme.Text) -and $ThemeImageCache[$CboTheme.Text]) {
            if ($PicThemePreview.IsHandleCreated) {
                 $PicThemePreview.Invoke([Action]{
                    $PicThemePreview.Image = $ThemeImageCache[$CboTheme.Text]
                    $PicThemePreview.Refresh()
                })
            } else {
                 $PicThemePreview.Image = $ThemeImageCache[$CboTheme.Text]
            }
        } else {
            $PicThemePreview.Image = $null
        }
    }
}
$CboTheme.Add_SelectedIndexChanged({ Update-ThemePreview })

# --- Behavior Page ---
$curY = $padY
$BehTitle = New-Label -Parent $PageBehavior -LangKey "BehTitle" -Location (New-Object System.Drawing.Point($padX,$curY)) -Tag "SectionHeader"
$curY += $BehTitle.Height + $gapSmall
$BehSub = New-Label -Parent $PageBehavior -LangKey "BehSub" -Location (New-Object System.Drawing.Point($padX,$curY)) -Tag "SubHeader"
$curY += $BehSub.Height + $gapLarge

$LblSim = New-Label -Parent $PageBehavior -LangKey "MaxSim" -Location (New-Object System.Drawing.Point($padX,$curY))
$NumSim = New-NumericUpDown -Parent $PageBehavior -Location (New-Object System.Drawing.Point([int]($padX + 300),[int]($curY-2))) -Min 1 -Max 20 -Value 3 -Tag "Input"
$curY += $inputH
$LblSimHelp = New-Label -Parent $PageBehavior -LangKey "MaxSimHelp" -Location (New-Object System.Drawing.Point($padX,$curY)) -Font (New-Object System.Drawing.Font("Segoe UI",14)) -Tag "SubHeader"
$curY += $LblSimHelp.Height + $gapMed

$LblPau = New-Label -Parent $PageBehavior -LangKey "PauseSpeed" -Location (New-Object System.Drawing.Point($padX,$curY))
$NumPause = New-NumericUpDown -Parent $PageBehavior -Location (New-Object System.Drawing.Point([int]($padX + 300),[int]($curY-2))) -Min 0 -Max 1000000 -Value 10240 -Tag "Input"
$curY += $inputH
$LblPauHelp = New-Label -Parent $PageBehavior -LangKey "PauseHelp" -Location (New-Object System.Drawing.Point($padX,$curY)) -Font (New-Object System.Drawing.Font("Segoe UI",14)) -Tag "SubHeader"
$curY += $LblPauHelp.Height + $gapMed

$LblDl = New-Label -Parent $PageBehavior -LangKey "DefDlFolder" -Location (New-Object System.Drawing.Point($padX,$curY))
$curY += $LblDl.Height + 5
$TxtDl = New-TextBox -Parent $PageBehavior -Location (New-Object System.Drawing.Point($padX,$curY)) -Size (New-Object System.Drawing.Size(600,$inputH)) -Tag "Input" -Text "C:\Downloads" -Anchor ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
$BtnDl = New-Button -Parent $PageBehavior -LangKey "Browse" -Location (New-Object System.Drawing.Point(640,[int]($curY-1))) -Size (New-Object System.Drawing.Size(120,[int]($inputH+2))) -Tag "NavButton" -Anchor ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
$BtnDl.Add_Click({ $fbd = New-Object System.Windows.Forms.FolderBrowserDialog; if ($fbd.ShowDialog() -eq "OK") { $TxtDl.Text = $fbd.SelectedPath } })

$curY += $inputH + $gapLarge

$ChkMin = New-CheckBox -Parent $PageBehavior -LangKey "StartMin" -Location (New-Object System.Drawing.Point($padX,$curY))
$curY += 30 + $gapSmall
$ChkTray = New-CheckBox -Parent $PageBehavior -LangKey "MinToTray" -Location (New-Object System.Drawing.Point($padX,$curY)) -Checked $true
$curY += 30 + $gapSmall
$ChkCloseTray = New-CheckBox -Parent $PageBehavior -LangKey "CloseToTray" -Location (New-Object System.Drawing.Point($padX,$curY)) -Checked $true

# --- Hardening Page ---
$curY = $padY
$HardTitle = New-Label -Parent $PageHardening -LangKey "HardTitle" -Location (New-Object System.Drawing.Point($padX,$curY)) -Tag "SectionHeader"
$curY += $HardTitle.Height + $gapSmall
$HardSub = New-Label -Parent $PageHardening -LangKey "HardSub" -Location (New-Object System.Drawing.Point($padX,$curY)) -Tag "SubHeader"
$curY += $HardSub.Height + $gapLarge

$ChkExe = New-CheckBox -Parent $PageHardening -LangKey "DarkExe" -Location (New-Object System.Drawing.Point($padX,$curY)) -Checked $true
$curY += 30 + $gapMed

$ChkUpdate = New-CheckBox -Parent $PageHardening -LangKey "RunUpdate" -Location (New-Object System.Drawing.Point($padX,$curY)) -Checked $true
$curY += 30 + $gapLarge

$HardNote = New-Label -Parent $PageHardening -LangKey "HardNote" -Location (New-Object System.Drawing.Point($padX,$curY)) -Size (New-Object System.Drawing.Size(800,80)) -Font (New-Object System.Drawing.Font("Segoe UI",14)) -Tag "SubHeader"

# --- Repair Page ---
$curY = $padY
$RepTitle = New-Label -Parent $PageRepair -LangKey "RepTitle" -Location (New-Object System.Drawing.Point($padX,$curY)) -Tag "SectionHeader"
$curY += $RepTitle.Height + $gapSmall
$RepSub = New-Label -Parent $PageRepair -LangKey "RepSub" -Location (New-Object System.Drawing.Point($padX,$curY)) -Tag "SubHeader"
$curY += $RepSub.Height + $gapLarge

# Repair Grid Logic
[int]$gridX1 = $padX
[int]$gridX2 = $padX + 280
[int]$gridX3 = $padX + 560
[int]$gridRow1 = $curY
[int]$gridRow2 = $curY + 70 # Button Height + Gap

function New-RepairBtn {
    param($LangKey, $x, $y, $Tag, $act)
    return New-Button -Parent $PageRepair -LangKey $LangKey -Location (New-Object System.Drawing.Point([int]$x, [int]$y)) -Size (New-Object System.Drawing.Size(260, 55)) -Tag $Tag -Click $act
}

New-RepairBtn "BtnResetCfg" $gridX1 $gridRow1 "DangerButton" { if ([System.Windows.Forms.MessageBox]::Show("Close JDownloader and delete the 'cfg' folder?","Confirm","YesNo") -eq "Yes") { Kill-JDownloader; Backup-JD -InstallPath $TxtPath.Text; Remove-Item "$($TxtPath.Text)\cfg" -Recurse -Force -ErrorAction SilentlyContinue } } | Out-Null
New-RepairBtn "BtnResetThm" $gridX2 $gridRow1 "NavButton" { if ([System.Windows.Forms.MessageBox]::Show("Reset theme and icons?","Confirm","YesNo") -eq "Yes") { Kill-JDownloader; Remove-Item "$($TxtPath.Text)\cfg\laf" -Recurse -Force; Remove-Item "$($TxtPath.Text)\themes\standard\org\jdownloader\images\*" -Recurse -Force } } | Out-Null
New-RepairBtn "BtnClearCache" $gridX3 $gridRow1 "NavButton" { Kill-JDownloader; Remove-Item "$($TxtPath.Text)\tmp\*" -Recurse -Force; Remove-Item "$($TxtPath.Text)\cfg\*.cache" -Force } | Out-Null

New-RepairBtn "BtnAudit" $gridX1 $gridRow2 "SuccessButton" { Run-Audit -InstallPath $TxtPath.Text } | Out-Null
New-RepairBtn "BtnSafe" $gridX2 $gridRow2 "SuccessButton" { Start-Process "$($TxtPath.Text)\JDownloader2.exe" -ArgumentList "-safe" } | Out-Null
New-RepairBtn "BtnUninstall" $gridX3 $gridRow2 "DangerButton" { if ([System.Windows.Forms.MessageBox]::Show("Full Uninstall?","Confirm","YesNo") -eq "Yes") { Task-FullUninstall -InstallPath $TxtPath.Text } } | Out-Null

# ==========================================
# 9. CONFIRMATION DIALOG (Enhanced)
# ==========================================

function Show-ConfirmationDialog {
    param($CurrentState)
    if ([string]::IsNullOrWhiteSpace($TxtPath.Text)) { 
        [System.Windows.Forms.MessageBox]::Show("Please select an installation path first.", "Error")
        return $false 
    }

    $cForm = New-Object System.Windows.Forms.Form
    $cForm.Text = "Confirm Operations"
    $cForm.Size = New-Object System.Drawing.Size(600, 750)
    $cForm.StartPosition = "CenterParent"
    $cForm.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)
    $cForm.ForeColor = "White"
    $cForm.FormBorderStyle = "Sizable"
    $cForm.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
    $cForm.AutoScaleMode = "Dpi"

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Verify and select options to apply:"
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
    $lbl.Location = New-Object System.Drawing.Point(20,20); $lbl.AutoSize = $true
    [void]$cForm.Controls.Add($lbl)

    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Location = New-Object System.Drawing.Point(20, 70)
    $flow.Size = New-Object System.Drawing.Size(540, 560)
    $flow.FlowDirection = "TopDown"
    $flow.WrapContents = $false
    $flow.AutoScroll = $true
    # Padding for scrollbar
    $flow.Padding = New-Object System.Windows.Forms.Padding(0,0,20,0)
    $flow.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
    [void]$cForm.Controls.Add($flow)

    function Add-Info {
        param($txt, $val)
        $l = New-Object System.Windows.Forms.Label
        $l.Text = "$txt $val"
        $l.AutoSize = $true
        # Constrain width for wrapping
        $l.MaximumSize = New-Object System.Drawing.Size(500, 0) 
        $l.ForeColor = "Gray"
        $l.Font = New-Object System.Drawing.Font("Segoe UI", 14)
        [void]$flow.Controls.Add($l)
    }

    Add-Info "Theme Preset:" $CurrentState.ThemeName
    Add-Info "Mode:" $CurrentState.Mode
    Add-Info "Downloads:" $CurrentState.MaxSim
    Add-Info "Path:" $CurrentState.InstallPath

    # Auto-generate Confirmation Checkboxes
    $KeyMap = @{
        "WindowDec"="Enable custom window decorations";
        "ForceMinimal"="Use compact/minimal tabs";
        "StartMin"="Start Minimized";
        "MinToTray"="Minimize to Tray";
        "CloseToTray"="Close to Tray";
        "PatchExe"="Patch .exe icon to dark mode";
        "AutoUpdate"="Run Update after completion"
    }

    $ResultRefs = @{}

    foreach ($key in $KeyMap.Keys) {
        if ($CurrentState.ContainsKey($key)) {
            $cb = New-Object System.Windows.Forms.CheckBox
            $cb.Text = $KeyMap[$key]
            $cb.AutoSize = $true
            # Constrain width for wrapping
            $cb.MaximumSize = New-Object System.Drawing.Size(500, 0)
            $cb.Checked = $CurrentState[$key]
            $cb.Font = New-Object System.Drawing.Font("Segoe UI", 14)
            $cb.ForeColor = "Gainsboro"
            $cb.Padding = New-Object System.Windows.Forms.Padding(0, 10, 0, 10) # Added Padding
            [void]$flow.Controls.Add($cb)
            $ResultRefs[$key] = $cb
        }
    }

    # Buttons
    $btnPanel = New-Object System.Windows.Forms.Panel
    $btnPanel.Height = 70
    $btnPanel.Dock = "Bottom"
    [void]$cForm.Controls.Add($btnPanel)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "RUN OPERATIONS"
    $btnOk.DialogResult = "OK"
    $btnOk.BackColor = [System.Drawing.Color]::FromArgb(30,144,255)
    $btnOk.ForeColor = "White"
    $btnOk.FlatStyle = "Flat"
    $btnOk.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $btnOk.Size = New-Object System.Drawing.Size(220, 50)
    $btnOk.Location = New-Object System.Drawing.Point(20, 10)
    [void]$btnPanel.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.DialogResult = "Cancel"
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(60,60,60)
    $btnCancel.ForeColor = "White"
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.Font = New-Object System.Drawing.Font("Segoe UI", 14)
    $btnCancel.Size = New-Object System.Drawing.Size(140, 50)
    $btnCancel.Location = New-Object System.Drawing.Point(260, 10)
    [void]$btnPanel.Controls.Add($btnCancel)

    $result = $cForm.ShowDialog()
    
    if ($result -eq "OK") {
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

$pages = @{ $BtnDashboard=$PageDashboard; $BtnInstallation=$PageInstallation; $BtnTheme=$PageTheme; $BtnBehavior=$PageBehavior; $BtnHardening=$PageHardening; $BtnRepair=$PageRepair }
foreach ($entry in $pages.GetEnumerator()) {
    $entry.Key.Add_Click({ 
        # Visual Reset for Sidebar logic
        foreach ($k in $pages.Keys) {
            # Reset color based on Theme palette manually or let Theme Engine handle it next time.
            # Simple approach: Reset to Sidebar background (approximate)
            $k.BackColor = $Sidebar.BackColor
        }
        # Highlight Active
        $this.BackColor = [System.Windows.Forms.ControlPaint]::Light($this.BackColor, 0.5)

        foreach ($p in $pages.Values) { $p.Visible = $false }
        # Do NOT overwrite Tag
        $pages[$this].Visible = $true 
        
        if ($pages[$this] -eq $PageTheme) { 
             Resize-ThemePreview
             Update-ThemePreview 
        }
    })
}
$PageDashboard.Visible = $true

$Form.Add_Load({
    Start-ThemeImagePreload -Definitions $ThemeDefinitions

    $CboTheme.SelectedIndex = 0
    Resize-ThemePreview
    
    $sysTheme = Detect-SystemTheme
    $CboGuiTheme.SelectedItem = $sysTheme
    Apply-GuiTheme -ThemeName $sysTheme
    
    $detected = Detect-JDPath
    if ($detected) { 
        $TxtPath.Text = $detected
        $CboMode.SelectedIndex = 0
        Log-Status "Found JDownloader at: $detected"
    } else { 
        $CboMode.SelectedIndex = 1
        Log-Status "JDownloader not found. defaulted to Clean Install."
    }

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

# Dispose all resources on close
$Form.Add_FormClosing({
    Cleanup-Resources
})

$BtnExec.Add_Click({
    # Explicit mapping logic
    $mode = "Modify"
    $src = $null

    if ($CboMode.SelectedIndex -eq 0) {
        $mode = "Modify"
    } elseif ($CboMode.SelectedIndex -eq 1) {
        $mode = "Install"
        $src = "GitHub"
    } elseif ($CboMode.SelectedIndex -eq 2) {
        $mode = "Install"
        $src = "Mega"
    }
    
    $State = @{ 
        Mode=$mode; 
        InstallSource=$src; 
        InstallPath=$TxtPath.Text; 
        ThemeName=$CboTheme.Text; 
        GuiThemeName=$CboGuiTheme.Text; 
        IconPack=$CboIcons.Text; 
        WindowDec=$ChkWinDec.Checked; 
        MaxSim=$NumSim.Value; 
        DlFolder=$TxtDl.Text; 
        StartMin=$ChkMin.Checked; 
        MinToTray=$ChkTray.Checked; 
        CloseToTray=$ChkCloseTray.Checked; 
        PatchExe=$ChkExe.Checked; 
        AutoUpdate=$ChkUpdate.Checked; 
        ForceMinimal=$ChkMinLay.Checked; 
        PauseSpeed=$NumPause.Value 
    }

    if (Show-ConfirmationDialog -CurrentState $State) {
        $BtnExec.Enabled = $false; $BtnExec.Text = "Processing..."
        $Form.Refresh()
        Execute-Operations -GUI_State $State
        $BtnExec.Text = $Lang.Execute; $BtnExec.Enabled = $true
        [System.Windows.Forms.MessageBox]::Show("Operations completed.", "Done") | Out-Null
    }
})

[void]$Form.ShowDialog()
