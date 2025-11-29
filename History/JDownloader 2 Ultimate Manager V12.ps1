<#
.SYNOPSIS
    JDownloader 2 ULTIMATE MANAGER (v12.0 - HIGH PERFORMANCE)
    - Architecture: WinForms GUI, JSON Settings Persistence, Robust Logging.
    - NEW CORE: High DPI Awareness (Sharp Text), BITS Transfer Engine.
    - FIXES: Donate button timestamp validation, persistent debloat.
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

# --- EARLY ASSEMBLY LOADING & DPI FIX ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Force High DPI Awareness (Fixes blurry text on Windows 10/11)
try {
    $methods = '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
    $user32 = Add-Type -MemberDefinition $methods -Name "Win32" -Namespace Win32 -PassThru
    $user32::SetProcessDPIAware() | Out-Null
} catch {
    # Silently fail on older OS versions
}

[System.Windows.Forms.Application]::EnableVisualStyles()

# ==========================================
# 2. GLOBAL VARIABLES & PATHS
# ==========================================

$AppDataDir = "$env:ProgramData\JD2-Ultimate-Manager"
$LogDir     = "$AppDataDir\Logs"
$WorkDir    = "$env:TEMP\JD2_Ult_Tool_v12_0"
$SettingsFile = "$AppDataDir\settings.json"
$VersionFile  = "$AppDataDir\version.json"

# Ensure directories exist
foreach ($path in @($AppDataDir, $LogDir, $WorkDir)) {
    if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
}

$LogFile = "$LogDir\$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
$OutputBox = $null # GUI Reference
$StatusLabel = $null # GUI Reference
$ProgressBar = $null # GUI Reference

# ==========================================
# 3. DATA DEFINITIONS (THEMES & ICONS)
# ==========================================

# Icon Packs (Fixed URLs)
$IconDefinitions = [ordered]@{
    "Standard (Default)" = @{
        "ID"  = "standard"
        "Url" = "https://raw.githubusercontent.com/SysAdminDoc/JDownloader-2-Ultimate-Manager/refs/heads/main/Themes/standard.7z"
    }
    "Material Darker" = @{
        "ID"  = "standard" # Material usually replaces standard slots
        "Url" = "https://raw.githubusercontent.com/SysAdminDoc/JDownloader-2-Ultimate-Manager/refs/heads/main/Themes/material-darker.7z"
    }
    "Dark / Minimal" = @{
        "ID"  = "minimal"
        "Url" = "https://raw.githubusercontent.com/SysAdminDoc/JDownloader-2-Ultimate-Manager/refs/heads/main/Themes/dark.7z"
    }
}

# Theme Definitions
$ThemeDefinitions = [ordered]@{
    "Synthetica Black Eye" = @{
        "DisplayName" = "Synthetica Black Eye"
        "Desc"        = "High contrast gray/orange dark theme."
        "LafID"       = "BLACK_EYE"
        "JsonName"    = "SyntheticaBlackEyeLookAndFeel.json"
        "JsonUrl"     = "https://raw.githubusercontent.com/Vinylwalk3r/JDownloader-2-Dark-Theme/refs/heads/master/config/cfg/laf/SyntheticaBlackEyeLookAndFeel.json"
        "DefaultIcon" = "Standard (Default)"
    }
    "Dracula" = @{
        "DisplayName" = "Dracula"
        "Desc"        = "Dracula-style purple/teal dark theme."
        "LafID"       = "FLATLAF_DRACULA"
        "JsonName"    = "FlatDarculaLaf.json"
        "JsonUrl"     = "https://raw.githubusercontent.com/dracula/jdownloader2/refs/heads/master/FlatDarculaLaf.json"
        "DefaultIcon" = "Standard (Default)"
    }
    "Flat Dark" = @{
        "DisplayName" = "Flat Dark"
        "Desc"        = "Flat dark minimal theme."
        "LafID"       = "FLATLAF_DARK"
        "JsonName"    = "FlatDarkLaf.json"
        "JsonUrl"     = "https://raw.githubusercontent.com/ikoshura/JDownloader-Fluent-Theme/refs/heads/main/FlatMacDarkLaf.json"
        "DefaultIcon" = "Standard (Default)"
    }
}

# ==========================================
# 4. EMBEDDED CONFIGURATIONS (TEMPLATES)
# ==========================================

# ENFORCED DEBLOAT: donatebuttonstate set to CUSTOM_HIDDEN, plus future timestamp
$Template_GUI = @'
{
  "overviewpaneldownloadlinksfailedcountvisible": false,
  "downloadview": "ALL",
  "linkpropertiespaneldownloadpasswordvisible": true,
  "speedmetervisible": true,
  "overviewpaneldownloadpackagecountvisible": true,
  "linkpropertiespanelfilenamevisible": true,
  "titlepattern": "|#TITLE|| - #SPEED/s|| - #UPDATENOTIFY|",
  "overviewpaneltotalinfovisible": true,
  "linkpropertiespanelchecksumvisible": true,
  "downloadspropertiespanelsavetovisible": true,
  "packagesbackgroundhighlightenabled": true,
  "overviewpaneldownloadlinkcountvisible": true,
  "downloadspropertiespanelpackagenamevisible": true,
  "overviewpaneldownloadlinksfinishedcountvisible": false,
  "overviewpanelsmartinfovisible": true,
  "availablecolumntextvisible": false,
  "overviewpaneldownloadbytesremainingvisible": true,
  "bannerenabled": false,
  "showfullhostname": false,
  "overviewpanellinkgrabberstatusonlinevisible": true,
  "linkpropertiespanelcommentvisible": true,
  "clipboardmonitored": true,
  "donatebuttonstate": "CUSTOM_HIDDEN",
  "donatebuttonlatestautochange": 1764274189351,
  "filecountinsizecolumnvisible": true,
  "clipboardskipmode": "ON_STARTUP",
  "premiumexpirewarningenabled": false,
  "downloadstablerefreshinterval": 1000,
  "overviewpaneldownloadpanelincludedisabledlinks": true,
  "tablewraparoundenabled": true,
  "specialdealoboomdialogvisibleonstartup": false,
  "tooltipenabled": true,
  "statusbaraddpremiumbuttonvisible": false,
  "captchadialogborderaroundimageenabled": true,
  "tablemouseoverhighlightenabled": true,
  "linkpropertiespanelsavetovisible": true,
  "overviewpanellinkgrabberlinkscountvisible": true,
  "clipboardmonitorprocesshtmlflavor": true,
  "overviewpanelselectedinfovisible": true,
  "linkpropertiespaneldownloadfromvisible": false,
  "sortcolumnhighlightenabled": true,
  "colorediconsfordisabledhostercolumnenabled": true,
  "premiumalertspeedcolumnenabled": false,
  "downloadspropertiespanelcommentvisible": true,
  "overviewpaneldownloadtotalbytesvisible": true,
  "overviewpanellinkgrabberpackagecountvisible": true,
  "windowswindowmanagerforegroundlocktimeout": 2147483647,
  "linkgrabbertabpropertiespanelvisible": true,
  "configviewvisible": true,
  "downloadstabpropertiespanelvisible": true,
  "selecteddownloadsearchcategory": "FILENAME",
  "overviewpaneldownloadetavisible": true,
  "savedownloadviewcrosssessionenabled": false,
  "overviewpanellinkgrabberstatusunknownvisible": true,
  "myjdownloaderviewvisible": false,
  "downloadspropertiespanelchecksumvisible": true,
  "downloadspropertiespanelfilenamevisible": false,
  "speedmetertimeframe": 30000,
  "mainwindowalwaysontop": false,
  "overviewpaneldownloadconnectionsvisible": true,
  "helpdialogsenabled": false,
  "lookandfeeltheme": "FLATLAF_DARK",
  "linkpropertiespanelarchivepasswordvisible": true,
  "horizontalscrollbarsinlinkgrabbertableenabled": false,
  "downloadspropertiespaneldownloadfromvisible": false,
  "overviewpanellinkgrabberstatusofflinevisible": true,
  "balloonnotificationenabled": true,
  "activeconfigpanel": "jd.gui.swing.jdgui.views.settings.panels.advanced.AdvancedSettings",
  "donationnotifyid": null,
  "speedmeterframespersecond": 4,
  "linkpropertiespanelpackagenamevisible": true,
  "passwordprotectionenabled": false,
  "specialdealsenabled": false,
  "overviewpaneldownloadspeedvisible": true,
  "premiumstatusbardisplay": "GROUP_BY_ACCOUNT_TYPE",
  "maxsizeunit": "TiB",
  "downloadpaneloverviewsettingsvisible": false,
  "tooltipdelay": 2000,
  "overviewpaneldownloadbytesloadedvisible": true,
  "speedinwindowtitle": "WHEN_WINDOW_IS_MINIMIZED",
  "overviewpanellinkgrabbertotalbytesvisible": true,
  "selectedlinkgrabbersearchcategory": "FILENAME",
  "downloadtaboverviewvisible": true,
  "rlywarnlevel": "NORMAL",
  "overviewpanellinkgrabberhostercountvisible": true,
  "downloadspropertiespaneldownloadpasswordvisible": true,
  "dialogdefaulttimeoutinms": 20000,
  "overviewpanellinkgrabberincludedisabledlinks": true,
  "hidesinglechildpackages": false,
  "linkgrabberbottombarposition": "SOUTH",
  "linkgrabbertaboverviewvisible": true,
  "overviewpaneldownloadlinksskippedcountvisible": false,
  "windowswindowmanageraltkeyworkaroundenabled": true,
  "updatebuttonflashingenabled": false,
  "overviewpanelvisibleonlyinfovisible": true,
  "linkgrabbersidebarvisible": true,
  "downloadspropertiespanelarchivepasswordvisible": true,
  "captchaexchangeenabled": false
}
'@

$Template_General = @'
{"maxsimultanedownloadsperhost":1,"delaywritemode":"AUTO","iffileexistsaction":"ASK_FOR_EACH_FILE","dupemanagerenabled":true,"forcemirrordetectioncaseinsensitive":true,"autoopencontainerafterdownload":true,"preferbouncycastlefortls":false,"autostartdownloadoption":"ONLY_IF_EXIT_WITH_RUNNING_DOWNLOADS","maxsimultanedownloads":3,"pausespeed":10240,"defaultdownloadfolder":"C:\\Downloads","windowsjnaidledetectorenabled":true,"downloadspeedlimitrememberedenabled":true,"closedwithrunningdownloads":false,"autostartcountdownseconds":10,"maxdownloadsperhostenabled":false,"maxchunksperfile":1,"sambaprefetchenabled":true,"showcountdownonautostartdownloads":true,"savelinkgrabberlistenabled":true,"onskipduetoalreadyexistsaction":"SKIP_FILE","hashretryenabled":false,"sharedmemorystateenabled":false,"convertrelativepathsjdroot":true,"keepxoldlists":5,"useavailableaccounts":true,"cleanupafterdownloadaction":"REMOVE_FINISHED_AND_DELETE_EXTRACTED","hashcheckenabled":true,"downloadspeedlimitenabled":false,"downloadspeedlimit":51200,"hidesinglechildpackages":true}
'@

$Template_Tray = @'
{"freshinstall":false,"onminimizeaction":"TO_TASKBAR","tooltipenabled":true,"trayiconclipboardindicatorenabled":false,"oncloseaction":"ASK","tooglewindowstatuswithsingleclickenabled":false,"greyiconenabled":false,"gnometrayicontransparentenabled":true,"enabled":true,"startminimizedenabled":false,"trayonlyvisibleifwindowishiddenenabled":false}
'@

# ==========================================
# 5. CORE UTILITIES & LOGGING
# ==========================================

function Log-Status {
    param([string]$Text, [string]$Type = "INFO")
    $timestamp = (Get-Date).ToString('HH:mm:ss')
    $msg = "[$timestamp] [$Type] $Text"
    
    # 1. File Log
    try { Add-Content -Path $LogFile -Value $msg -ErrorAction SilentlyContinue } catch {}

    # 2. GUI Log
    if ($OutputBox -and $OutputBox.IsHandleCreated) {
        $OutputBox.Invoke([Action[string]]{ param($t) $OutputBox.AppendText("$t`r`n"); $OutputBox.ScrollToCaret() }, $msg)
    } else { Write-Host $msg }

    # 3. Status Label
    if ($StatusLabel -and $StatusLabel.IsHandleCreated) {
        $StatusLabel.Invoke([Action[string]]{ param($t) $StatusLabel.Text = $t }, "Status: $Text")
    }
}

function Save-Settings {
    param($SettingsObj)
    try {
        $SettingsObj | ConvertTo-Json -Depth 5 | Set-Content $SettingsFile -Encoding UTF8
    } catch { Log-Status "Failed to save settings: $_" "ERROR" }
}

function Load-Settings {
    if (Test-Path $SettingsFile) {
        try { return Get-Content $SettingsFile -Raw | ConvertFrom-Json } catch { return $null }
    }
    return $null
}

# --- UPDATED DOWNLOAD ENGINE (BITS + FAILOVER) ---
function Download-File {
    param([string]$Url, [string]$Destination)
    Log-Status "Downloading: $(Split-Path $Destination -Leaf)"
    
    # Method 1: BITS (Robust)
    try {
        if (-not (Get-Module -Name BitsTransfer -ListAvailable)) { Import-Module BitsTransfer -ErrorAction Stop }
        Start-BitsTransfer -Source $Url -Destination $Destination -ErrorAction Stop -Priority Foreground
        return $true
    } catch {
        Log-Status "BITS Failed ($($_)). Trying Failover..." "WARN"
    }

    # Method 2: WebClient (Failover)
    try { 
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop
        return $true 
    }
    catch { 
        Log-Status "Download completely failed: $_" "ERROR"
        return $false 
    }
}

function Get-7Zip {
    $7z = "$AppDataDir\7zr.exe"
    if (-not (Test-Path $7z)) { Download-File -Url "https://www.7-zip.org/a/7zr.exe" -Destination $7z | Out-Null }
    return $7z
}

# ==========================================
# 6. JDOWNLOADER LOGIC
# ==========================================

function Detect-JDPath {
    $paths = @(
        "C:\Program Files\JDownloader",
        "C:\Program Files (x86)\JDownloader",
        "$env:LOCALAPPDATA\JDownloader 2"
    )
    foreach ($p in $paths) {
        if (Test-Path "$p\JDownloader2.exe") { return $p }
    }
    return $null
}

function Kill-JDownloader {
    Log-Status "Terminating JDownloader processes..."
    # Robust kill with wait loop to prevent race conditions
    $limit = 0
    while ($limit -lt 15) {
        $procs = Get-Process | Where-Object { $_.ProcessName -match "JDownloader|javaw" }
        if (-not $procs) { break }
        
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        $limit++
    }
    if ($limit -ge 15) { Log-Status "Warning: Could not terminate all JD processes." "WARN" }
    Start-Sleep -Seconds 1
}

function Backup-JD {
    param([string]$InstallPath)
    $stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $backupRoot = "$InstallPath\cfg-backup\$stamp"
    $themeBackup = "$InstallPath\themes-backup\$stamp"
    
    Log-Status "Creating Backup at: $stamp"
    try {
        if (Test-Path "$InstallPath\cfg") {
            New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
            Copy-Item "$InstallPath\cfg\*" $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path "$InstallPath\themes") {
            New-Item -ItemType Directory -Path $themeBackup -Force | Out-Null
            Copy-Item "$InstallPath\themes\*" $themeBackup -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch { Log-Status "Backup warning: $_" "WARN" }
}

function Task-ExtractIcons {
    param(
        [string]$ZipUrl,
        [string]$InstallPath,
        [string]$TargetIconSet # 'standard' or 'minimal'
    )
    
    $localZip = "$WorkDir\icons.7z"
    $extractPath = "$WorkDir\IconsTemp"
    
    Log-Status "Downloading Icon Pack..."
    if (-not (Download-File -Url $ZipUrl -Destination $localZip)) { return }
    
    $7z = Get-7Zip
    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
    Start-Process $7z -ArgumentList "x `"$localZip`" -o`"$extractPath`" -y" -Wait -WindowStyle Hidden
    
    Log-Status "Locating icon data within archive..."
    
    # Recursive search for 'images' folder
    $foundImages = Get-ChildItem -Path $extractPath -Recurse -Directory | Where-Object { $_.Name -eq "images" } | Select-Object -First 1
    
    if (-not $foundImages) {
        Log-Status "ERROR: Could not find 'images' folder in icon pack!" "ERROR"
        return
    }

    # Construct correct target path: <JD>\themes\<set>\org\jdownloader\images
    $targetImages = "$InstallPath\themes\$TargetIconSet\org\jdownloader\images"
    
    Log-Status "Installing icons to: $targetImages"
    if (-not (Test-Path $targetImages)) { New-Item -ItemType Directory -Path $targetImages -Force | Out-Null }
    
    # Copy CONTENTS only
    Copy-Item "$($foundImages.FullName)\*" $targetImages -Recurse -Force

    # Cleanup incorrect folders from previous broken runs
    $baseJdPath = "$InstallPath\themes\$TargetIconSet\org\jdownloader"
    $badFolders = @("dark", "material-darker", "material", "minimal", "standard")
    
    foreach ($bad in $badFolders) {
        $badPath = "$baseJdPath\$bad"
        if (Test-Path $badPath) {
            Log-Status "Cleaning up incorrect folder: $badPath" "INFO"
            Remove-Item $badPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Task-PatchLaf {
    param(
        [string]$JsonPath,
        [string]$IconSetId,
        [bool]$WindowDecorations
    )
    Log-Status "Patching LAF: $(Split-Path $JsonPath -Leaf)"
    try {
        $content = Get-Content -Path $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        
        # Patch properties
        if (-not $content.PSObject.Properties["iconsetid"]) {
            $content | Add-Member -MemberType NoteProperty -Name "iconsetid" -Value $IconSetId
        } else { $content.iconsetid = $IconSetId }

        if (-not $content.PSObject.Properties["windowdecorationenabled"]) {
            $content | Add-Member -MemberType NoteProperty -Name "windowdecorationenabled" -Value $WindowDecorations
        } else { $content.windowdecorationenabled = $WindowDecorations }

        $content | ConvertTo-Json -Depth 100 | Set-Content $JsonPath -Encoding UTF8
    } catch { Log-Status "Error patching LAF: $_" "ERROR" }
}

function Task-NukeBanners {
    param([string]$InstallPath)
    Log-Status "Nuking Banner Ads (Filesystem)..."
    Add-Type -AssemblyName System.Drawing
    $themeDir = "$InstallPath\themes"
    if (Test-Path $themeDir) {
        Get-ChildItem -Path $themeDir -Recurse -Filter "*.png" | Where-Object { $_.Directory.Name -eq "banner" } | ForEach-Object {
            try {
                $img = [System.Drawing.Image]::FromFile($_.FullName)
                $w = $img.Width; $h = $img.Height; $img.Dispose()
                $bmp = New-Object System.Drawing.Bitmap($w, $h)
                $bmp.Save($_.FullName, [System.Drawing.Imaging.ImageFormat]::Png)
                $bmp.Dispose()
            } catch {}
        }
    }
}

function Task-PatchExeIcon {
    param([string]$InstallPath)
    Log-Status "Patching EXE Icon..."
    
    $ResHackerZip = "$WorkDir\resource_hacker.zip"
    $ResHackerDir = "$WorkDir\ResourceHacker"
    $IconFile = "$WorkDir\jd_dark.ico"
    
    Download-File -Url "https://www.angusj.com/resourcehacker/resource_hacker.zip" -Destination $ResHackerZip | Out-Null
    Download-File -Url "https://raw.githubusercontent.com/SysAdminDoc/JDownloaderDarkMode/refs/heads/main/Icons/icon.ico" -Destination $IconFile | Out-Null
    
    if (-not (Test-Path $ResHackerDir)) { Expand-Archive -Path $ResHackerZip -DestinationPath $ResHackerDir -Force }
    $ResHackerExe = "$ResHackerDir\ResourceHacker.exe"
    
    $targets = @("$InstallPath\JDownloader2.exe", "$InstallPath\Uninstall JDownloader.exe")
    foreach ($exe in $targets) {
        if (Test-Path $exe) {
            Stop-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($exe)) -Force -ErrorAction SilentlyContinue
            Start-Sleep 1
            $bak = "$exe.bak"
            if (-not (Test-Path $bak)) { Move-Item -Path $exe -Destination $bak -Force }
            else { Remove-Item $exe -Force -ErrorAction SilentlyContinue }
            
            $args = "-open `"$bak`" -save `"$exe`" -action addoverwrite -res `"$IconFile`" -mask ICONGROUP,MAINICON,0"
            Start-Process -FilePath $ResHackerExe -ArgumentList $args -Wait -WindowStyle Hidden
        }
    }
    
    # Clear Icon Cache
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep 1
    Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Filter "iconcache_*.db" -Recurse | Remove-Item -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}

function Set-JsonConfig {
    param($Path, $DataHash)
    try {
        $DataHash | ConvertTo-Json -Depth 100 | Set-Content $Path -Encoding UTF8
        Log-Status "Patched: $(Split-Path $Path -Leaf)"
    } catch { Log-Status "Error writing $Path" "ERROR" }
}

function Task-DeepHardening {
    param([string]$cfgPath)
    Log-Status "Applying Deep Cache Hardening (Contribute Panel)..."

    # 1. AdvancedConfig.json
    $advConfig = @{
        "org.jdownloader.gui.jdgui.settings.AboutConfigPanel.contributepanelvisible" = $false
        "org.jdownloader.gui.jdgui.settings.AboutConfigPanel.contributepanelshown"   = $false
        "org.jdownloader.gui.jdgui.settings.AboutConfigPanel.contributepanelallowed" = $false
    }
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.settings.AdvancedConfig.json" -DataHash $advConfig

    # 2. WidgetStateManager.json
    $widgetState = @{
        "contributepanelvisible" = $false
        "contributepanelallowed" = $false
        "aboutpanelvisible"      = $false
    }
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.controlling.WidgetStateManager.json" -DataHash $widgetState

    # 3. GUILayout.json
    $guiLayout = @{
        "contributepanel_visible" = $false
    }
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.gui.jdgui.views.jdgui.GUILayout.json" -DataHash $guiLayout

    # 4. AdvancedSettings.json
    $advSettings = @{
        "contributepanel_enabled" = $false
        "contributepanel_visible" = $false
    }
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.settings.advanced.AdvancedSettings.json" -DataHash $advSettings
}

function Task-Install {
    param([string]$Source)
    Log-Status "Starting Installation ($Source)..."
    
    if ($Source -eq "GitHub") {
        $7z = Get-7Zip
        $baseUrl = "https://github.com/SysAdminDoc/JDownloaderDarkMode/raw/main/Installer/installer.7z"
        for ($i = 1; $i -le 7; $i++) {
            $part = ".{0:D3}" -f $i
            Download-File -Url "$baseUrl$part" -Destination "$WorkDir\installer.7z$part" | Out-Null
        }
        Start-Process $7z -ArgumentList "x `"$WorkDir\installer.7z.001`" -o`"$WorkDir\Installer`" -y" -Wait -WindowStyle Hidden
        $setup = Get-ChildItem "$WorkDir\Installer" -Filter "*.exe" -Recurse | Select-Object -First 1
        if ($setup) { Start-Process $setup.FullName -ArgumentList "-q" -Wait }
    } elseif ($Source -eq "Mega") {
        Start-Process "https://mega.nz/file/PQ0XRIrA#-uuhLXSc_nPfotXWfBWDZRx90Gnehx2_Mx_JVufzfdM"
        [System.Windows.Forms.MessageBox]::Show("Please download the installer from the browser, then click OK once the download is finished.", "Action Required")
        $dlDir = "$env:USERPROFILE\Downloads"
        $f = Get-ChildItem $dlDir -Filter "JDownloader*Setup*.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($f) { Start-Process $f.FullName -ArgumentList "-q" -Wait }
    }
}

function Task-FullUninstall {
    param([string]$InstallPath)
    if (-not (Test-Path $InstallPath)) { Log-Status "Path not found."; return }
    Kill-JDownloader
    Log-Status "Running Uninstaller..."
    $uninst = "$InstallPath\Uninstall JDownloader.exe"
    if (Test-Path $uninst) { Start-Process -FilePath $uninst -ArgumentList "-q" -Wait }
    Start-Sleep 2
    if (Test-Path $InstallPath) { 
        Log-Status "Removing remaining files..."
        Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction SilentlyContinue 
    }
    Log-Status "Uninstall Complete."
}

function Trigger-Update {
    param([string]$InstallPath)
    Log-Status "Triggering JDownloader Update..."
    $exe = "$InstallPath\JDownloader2.exe"
    if (Test-Path $exe) {
        Start-Process -FilePath $exe -ArgumentList "-update"
    }
}

function Run-Audit {
    param([string]$InstallPath)
    Log-Status "=== STARTING SYSTEM AUDIT ==="
    
    if (-not (Test-Path $InstallPath)) {
        Log-Status "AUDIT FAILED: Install path not found." "ERROR"; return
    }
    
    $issues = 0
    $cfg = "$InstallPath\cfg"
    $laf = "$cfg\laf"
    
    # Check Critical Configs
    $checkFiles = @("org.jdownloader.settings.GraphicalUserInterfaceSettings.json", "org.jdownloader.settings.GeneralSettings.json")
    foreach ($f in $checkFiles) {
        if (-not (Test-Path "$cfg\$f")) { Log-Status "MISSING CONFIG: $f" "WARN"; $issues++ }
    }
    
    # Check Theme folder structure
    if (-not (Test-Path "$InstallPath\themes\standard\org\jdownloader\images")) {
        Log-Status "MISSING ICONS: Standard theme folder incorrect." "WARN"; $issues++
    }
    
    # Check Debloat Files (Mandatory now)
    $debloatFiles = @(
        "org.jdownloader.gui.jdgui.settings.AboutConfigPanel.json",
        "org.jdownloader.settings.AboutSettings.json",
        "org.jdownloader.gui.jdgui.settings.MainToolBar.json",
        "org.jdownloader.settings.PremiumSettings.json",
        "org.jdownloader.settings.NewsSettings.json"
    )
    foreach ($f in $debloatFiles) {
        if (-not (Test-Path "$cfg\$f")) { Log-Status "MISSING DEBLOAT: $f (Run Execute to fix)" "WARN"; $issues++ }
    }
    
    if ($issues -gt 0) {
        Log-Status "AUDIT: FAILED - $issues Issues Found" "WARN"
        [System.Windows.Forms.MessageBox]::Show("Audit found $issues potential issues.`nCheck log for details.", "Audit Failed", "OK", "Warning")
    } else {
        Log-Status "AUDIT: PASSED - No Critical Issues Detected" "SUCCESS"
        [System.Windows.Forms.MessageBox]::Show("Audit Passed! System looks good.", "Audit Passed", "OK", "Information")
    }
}

# ==========================================
# 7. MAIN LOGIC ORCHESTRATOR
# ==========================================

function Execute-Operations {
    param($GUI_State)
    
    $JDPath = $GUI_State.InstallPath
    
    # Sanity Checks
    if ([string]::IsNullOrWhiteSpace($JDPath)) { Log-Status "Path cannot be empty." "ERROR"; return }
    if ($JDPath.Contains("(") -or $JDPath.Contains(")")) { Log-Status "Warning: Path contains parentheses. Ensure proper escaping if manual intervention needed." "WARN" }
    
    if (-not (Test-Path $JDPath) -and $GUI_State.Mode -eq "Modify") {
        Log-Status "Invalid JDownloader Path!" "ERROR"; return
    }
    
    $ProgressBar.Style = "Marquee"
    
    # 1. Install Phase
    if ($GUI_State.Mode -ne "Modify") {
        Task-Install -Source $GUI_State.InstallSource
        # Re-detect path after install
        $JDPath = Detect-JDPath
        if (-not $JDPath) { $JDPath = "C:\Program Files\JDownloader" }
    }
    
    Kill-JDownloader
    Backup-JD -InstallPath $JDPath
    
    # 2. Theme & Icons Phase
    $Theme = $ThemeDefinitions[$GUI_State.ThemeName]
    $IconSetKey = $GUI_State.IconPack
    $IconDef = $IconDefinitions[$IconSetKey]
    
    # Ensure folders exist
    $cfgPath = "$JDPath\cfg"
    $lafPath = "$cfgPath\laf"
    if (-not (Test-Path $lafPath)) { New-Item -ItemType Directory -Path $lafPath -Force | Out-Null }
    
    # Download & Patch LAF
    $lafFile = "$lafPath\$($Theme.JsonName)"
    Download-File -Url $Theme.JsonUrl -Destination $lafFile | Out-Null
    
    # Determine Icon ID for JSON (standard vs minimal)
    $jsonIconId = $IconDef.ID
    Task-PatchLaf -JsonPath $lafFile -IconSetId $jsonIconId -WindowDecorations $GUI_State.WindowDec
    
    # Extract Icons
    Task-ExtractIcons -ZipUrl $IconDef.Url -InstallPath $JDPath -TargetIconSet $jsonIconId
    
    # 3. Config Phase
    # GUI Settings (ENFORCED HARDENING)
    try {
        $guiObj = $Template_GUI | ConvertFrom-Json
        $guiObj.lookandfeeltheme = $Theme.LafID
        
        # --- FIXED: MANDATORY DONATE BLOCK (Directly in GUI settings) ---
        if (-not $guiObj.PSObject.Properties["donatebuttonstate"]) {
             $guiObj | Add-Member -MemberType NoteProperty -Name "donatebuttonstate" -Value "CUSTOM_HIDDEN"
        } else { $guiObj.donatebuttonstate = "CUSTOM_HIDDEN" }

        # --- FIXED: TIMESTAMP VALIDATION (Prevents reversion) ---
        if (-not $guiObj.PSObject.Properties["donatebuttonlatestautochange"]) {
             $guiObj | Add-Member -MemberType NoteProperty -Name "donatebuttonlatestautochange" -Value 1764274189351
        } else { $guiObj.donatebuttonlatestautochange = 1764274189351 }
        
        # Other Mandatory Flags
        $guiObj.bannerenabled = $false
        $guiObj.specialdealsenabled = $false
        $guiObj.statusbaraddpremiumbuttonvisible = $false
        $guiObj.specialdealoboomdialogvisibleonstartup = $false

        $guiObj | ConvertTo-Json -Depth 100 | Set-Content "$cfgPath\org.jdownloader.settings.GraphicalUserInterfaceSettings.json" -Encoding UTF8
    } catch { Log-Status "Config Write Error (GUI): $_" "ERROR" }
    
    # General Settings (Includes Cleanup Logic)
    try {
        $genObj = $Template_General | ConvertFrom-Json
        $genObj.maxsimultanedownloads = [int]$GUI_State.MaxSim
        $genObj.defaultdownloadfolder = $GUI_State.DlFolder.Replace("\", "\\")
        $genObj.pausespeed = [int]$GUI_State.PauseSpeed
        $genObj | ConvertTo-Json -Depth 100 | Set-Content "$cfgPath\org.jdownloader.settings.GeneralSettings.json" -Encoding UTF8
    } catch { Log-Status "Config Write Error (General): $_" "ERROR" }

    # Tray Settings
    try {
        $trayObj = $Template_Tray | ConvertFrom-Json
        $trayObj.startminimizedenabled = $GUI_State.StartMin
        $trayObj.onminimizeaction = if ($GUI_State.MinToTray) { "TO_TASKBAR_IF_ALLOWED" } else { "TO_TASKBAR" }
        $trayObj | ConvertTo-Json -Depth 100 | Set-Content "$cfgPath\org.jdownloader.gui.jdtrayicon.TrayExtension.json" -Encoding UTF8
    } catch { Log-Status "Config Write Error (Tray): $_" "ERROR" }

    # 4. Advanced Debloat & Layout (MANDATORY EXECUTION)
    Log-Status "Applying Mandatory Debloat Policies..."
    
    # Contribute Tab (3-File Lockout)
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.gui.jdgui.settings.AboutConfigPanel.json" -DataHash @{contributepanelshown=$false; contributepanelallowed=$false; contributepanelvisible=$false}
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.settings.AboutSettings.json" -DataHash @{contributepanelenabled=$false; contributepanelvisible=$false}
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.gui.jdgui.settings.MainToolBar.json" -DataHash @{contributepanelvisible=$false}
    
    # Deep Cache Nuke (Contribute Panel Caches Only)
    Task-DeepHardening -cfgPath $cfgPath

    # Premium Ads
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.settings.PremiumSettings.json" -DataHash @{advertisingmarketenabled=$false; premiumalertspeedcolumnenabled=$false}
    
    # News Panel
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.settings.NewsSettings.json" -DataHash @{newsenabled=$false; newspopupsenabled=$false}
    
    # MyJD Promotions
    Set-JsonConfig -Path "$cfgPath\org.jdownloader.settings.MyJDownloaderSettings.json" -DataHash @{myjdremotetasksenabled=$false; myjdrunsilentupdates=$false}

    # Minimal Layout Fix (Optional)
    if ($GUI_State.ForceMinimal) {
        Set-JsonConfig -Path "$cfgPath\org.jdownloader.gui.jdgui.settings.MainTabLayout.json" -DataHash @{compactmodetabs=$true; hidemyjdtab=$true}
    }

    # 5. Hardening (MANDATORY NUKE)
    Task-NukeBanners -InstallPath $JDPath
    
    if ($GUI_State.PatchExe) { Task-PatchExeIcon -InstallPath $JDPath }
    
    Log-Status "=== Operations Complete ===" "SUCCESS"
    $ProgressBar.Style = "Blocks"; $ProgressBar.Value = 100
    
    if ($GUI_State.AutoUpdate) { Trigger-Update -InstallPath $JDPath }
    
    # Save Settings
    Save-Settings -SettingsObj $GUI_State
}

# ==========================================
# 8. GUI CONSTRUCTION
# ==========================================

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "JDownloader 2 Ultimate Manager v12.0"
$Form.Size = New-Object System.Drawing.Size(720, 830)
$Form.StartPosition = "CenterScreen"
$Form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$Form.ForeColor = [System.Drawing.Color]::WhiteSmoke
$Form.FormBorderStyle = "FixedDialog"
$Form.MaximizeBox = $false

# -- Header --
$LblHeader = New-Object System.Windows.Forms.Label
$LblHeader.Text = "JDownloader 2 Ultimate Manager"
$LblHeader.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$LblHeader.Location = New-Object System.Drawing.Point(15, 10); $LblHeader.AutoSize=$true
$Form.Controls.Add($LblHeader)

# -- Path Selection (Top) --
$GrpPath = New-Object System.Windows.Forms.GroupBox
$GrpPath.Text = "JDownloader Location"
$GrpPath.Location = New-Object System.Drawing.Point(15, 50); $GrpPath.Size = New-Object System.Drawing.Size(675, 70); $GrpPath.ForeColor = "LightGray"
$Form.Controls.Add($GrpPath)

$TxtPath = New-Object System.Windows.Forms.TextBox
$TxtPath.Location = New-Object System.Drawing.Point(15, 30); $TxtPath.Size = New-Object System.Drawing.Size(430, 23); $TxtPath.BackColor="DimGray"; $TxtPath.ForeColor="White"
$GrpPath.Controls.Add($TxtPath)

$BtnDetect = New-Object System.Windows.Forms.Button
$BtnDetect.Text = "Auto-Detect"; $BtnDetect.Location = New-Object System.Drawing.Point(455, 29); $BtnDetect.Size = New-Object System.Drawing.Size(100, 25); $BtnDetect.FlatStyle="Flat"
$BtnDetect.BackColor = [System.Drawing.Color]::FromArgb(64,64,64)
$BtnDetect.Add_Click({ 
    $p = Detect-JDPath; if($p){$TxtPath.Text=$p;Log-Status "Detected: $p"}else{Log-Status "Not found." "WARN"} 
})
$GrpPath.Controls.Add($BtnDetect)

$BtnBrowse = New-Object System.Windows.Forms.Button
$BtnBrowse.Text = "Browse..."; $BtnBrowse.Location = New-Object System.Drawing.Point(565, 29); $BtnBrowse.Size = New-Object System.Drawing.Size(90, 25); $BtnBrowse.FlatStyle="Flat"
$BtnBrowse.BackColor = [System.Drawing.Color]::FromArgb(64,64,64)
$BtnBrowse.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($fbd.ShowDialog() -eq "OK") { $TxtPath.Text = $fbd.SelectedPath }
})
$GrpPath.Controls.Add($BtnBrowse)

# -- Installation (Left Column) --
$GrpInst = New-Object System.Windows.Forms.GroupBox
$GrpInst.Text = "Installation Mode"; $GrpInst.Location = New-Object System.Drawing.Point(15, 130); $GrpInst.Size = New-Object System.Drawing.Size(320, 100); $GrpInst.ForeColor="LightGray"
$Form.Controls.Add($GrpInst)

$RadModeMod = New-Object System.Windows.Forms.RadioButton; $RadModeMod.Text = "Modify Existing (Skip Install)"; $RadModeMod.Location = New-Object System.Drawing.Point(15, 25); $RadModeMod.AutoSize=$true; $RadModeMod.Checked=$true; $GrpInst.Controls.Add($RadModeMod)
$RadModeGit = New-Object System.Windows.Forms.RadioButton; $RadModeGit.Text = "Clean Install (GitHub)"; $RadModeGit.Location = New-Object System.Drawing.Point(15, 50); $RadModeGit.AutoSize=$true; $GrpInst.Controls.Add($RadModeGit)
$RadModeMega = New-Object System.Windows.Forms.RadioButton; $RadModeMega.Text = "Clean Install (Mega)"; $RadModeMega.Location = New-Object System.Drawing.Point(15, 75); $RadModeMega.AutoSize=$true; $GrpInst.Controls.Add($RadModeMega)

# -- Theme & Appearance (Right Column) --
$GrpTheme = New-Object System.Windows.Forms.GroupBox
$GrpTheme.Text = "Theme & Appearance"; $GrpTheme.Location = New-Object System.Drawing.Point(350, 130); $GrpTheme.Size = New-Object System.Drawing.Size(340, 210); $GrpTheme.ForeColor="LightGray"
$Form.Controls.Add($GrpTheme)

$LblThm = New-Object System.Windows.Forms.Label; $LblThm.Text = "Theme:"; $LblThm.Location = New-Object System.Drawing.Point(15, 25); $LblThm.AutoSize=$true; $GrpTheme.Controls.Add($LblThm)
$CboTheme = New-Object System.Windows.Forms.ComboBox; $CboTheme.Location = New-Object System.Drawing.Point(15, 45); $CboTheme.Width=310; $CboTheme.DropDownStyle="DropDownList"; $CboTheme.BackColor="DimGray"; $CboTheme.ForeColor="White"
$ThemeDefinitions.Keys | ForEach-Object { $CboTheme.Items.Add($_) } | Out-Null; $CboTheme.SelectedIndex=0; $GrpTheme.Controls.Add($CboTheme)

# Preview Panel
$PnlPreview = New-Object System.Windows.Forms.Panel; $PnlPreview.Location = New-Object System.Drawing.Point(15, 75); $PnlPreview.Size = New-Object System.Drawing.Size(310, 50); $PnlPreview.BorderStyle="FixedSingle"
$PnlPreview.BackColor = [System.Drawing.Color]::FromArgb(45,45,45)
$GrpTheme.Controls.Add($PnlPreview)
$LblPreDesc = New-Object System.Windows.Forms.Label; $LblPreDesc.Location=New-Object System.Drawing.Point(5,5); $LblPreDesc.AutoSize=$true; $LblPreDesc.Text="Description..."; $PnlPreview.Controls.Add($LblPreDesc)

$ChkWinDec = New-Object System.Windows.Forms.CheckBox; $ChkWinDec.Text = "Enable Window Decorations (Custom Titlebar)"; $ChkWinDec.Location = New-Object System.Drawing.Point(15, 130); $ChkWinDec.AutoSize=$true; $ChkWinDec.Checked=$true; $GrpTheme.Controls.Add($ChkWinDec)
$ChkMinLay = New-Object System.Windows.Forms.CheckBox; $ChkMinLay.Text = "Compact Tabs"; $ChkMinLay.Location = New-Object System.Drawing.Point(15, 150); $ChkMinLay.AutoSize=$true; $GrpTheme.Controls.Add($ChkMinLay)

$LblIco = New-Object System.Windows.Forms.Label; $LblIco.Text = "Icon Pack:"; $LblIco.Location = New-Object System.Drawing.Point(15, 180); $LblIco.AutoSize=$true; $GrpTheme.Controls.Add($LblIco)
$CboIcons = New-Object System.Windows.Forms.ComboBox; $CboIcons.Location = New-Object System.Drawing.Point(85, 177); $CboIcons.Width=140; $CboIcons.DropDownStyle="DropDownList"; $CboIcons.BackColor="DimGray"; $CboIcons.ForeColor="White"
$IconDefinitions.Keys | ForEach-Object { $CboIcons.Items.Add($_) } | Out-Null; $CboIcons.SelectedIndex=0; $GrpTheme.Controls.Add($CboIcons)

# Open Folder Button
$BtnOpenThm = New-Object System.Windows.Forms.Button; $BtnOpenThm.Text="Open Folder"; $BtnOpenThm.Location=New-Object System.Drawing.Point(235, 176); $BtnOpenThm.Size=New-Object System.Drawing.Size(90,23); $BtnOpenThm.FlatStyle="Flat"; $BtnOpenThm.BackColor=[System.Drawing.Color]::FromArgb(64,64,64)
$BtnOpenThm.Add_Click({ 
    $iconP = if($CboIcons.Text.Contains("Dark") -or $CboIcons.Text.Contains("Minimal")){"minimal"}else{"standard"}
    $p = "$($TxtPath.Text)\themes\$iconP\org\jdownloader\images"
    if(Test-Path $p){Invoke-Item $p}else{Log-Status "Icon folder not found (not installed yet?)" "WARN"}
})
$GrpTheme.Controls.Add($BtnOpenThm)


# Event Handler for Theme Change
$CboTheme.Add_SelectedIndexChanged({
    $sel = $ThemeDefinitions[$CboTheme.Text]
    $LblPreDesc.Text = "$($sel.Desc)`nLAF ID: $($sel.LafID)"
})

# -- Configuration (Bottom Left) --
$GrpCfg = New-Object System.Windows.Forms.GroupBox
$GrpCfg.Text = "Behavior Settings"; $GrpCfg.Location = New-Object System.Drawing.Point(15, 240); $GrpCfg.Size = New-Object System.Drawing.Size(320, 200); $GrpCfg.ForeColor="LightGray"
$Form.Controls.Add($GrpCfg)

$LblSim = New-Object System.Windows.Forms.Label; $LblSim.Text = "Max Downloads:"; $LblSim.Location = New-Object System.Drawing.Point(15, 25); $LblSim.AutoSize=$true; $GrpCfg.Controls.Add($LblSim)
$NumSim = New-Object System.Windows.Forms.NumericUpDown; $NumSim.Location = New-Object System.Drawing.Point(150, 23); $NumSim.Minimum=1; $NumSim.Maximum=20; $NumSim.Value=3; $GrpCfg.Controls.Add($NumSim)

$LblDl = New-Object System.Windows.Forms.Label; $LblDl.Text = "Download Folder:"; $LblDl.Location = New-Object System.Drawing.Point(15, 55); $LblDl.AutoSize=$true; $GrpCfg.Controls.Add($LblDl)
$TxtDl = New-Object System.Windows.Forms.TextBox; $TxtDl.Location = New-Object System.Drawing.Point(15, 75); $TxtDl.Width=200; $TxtDl.Text="C:\Downloads"; $GrpCfg.Controls.Add($TxtDl)
$BtnDl = New-Object System.Windows.Forms.Button; $BtnDl.Text="Browse"; $BtnDl.Location=New-Object System.Drawing.Point(220,74); $BtnDl.Width=80; $BtnDl.FlatStyle="Flat"; $BtnDl.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog; if($fbd.ShowDialog()-eq"OK"){$TxtDl.Text=$fbd.SelectedPath}
}); $GrpCfg.Controls.Add($BtnDl)

$ChkMin = New-Object System.Windows.Forms.CheckBox; $ChkMin.Text="Start Minimized"; $ChkMin.Location=New-Object System.Drawing.Point(15,110); $ChkMin.AutoSize=$true; $GrpCfg.Controls.Add($ChkMin)
$ChkTray = New-Object System.Windows.Forms.CheckBox; $ChkTray.Text="Minimize to Tray"; $ChkTray.Location=New-Object System.Drawing.Point(15,135); $ChkTray.AutoSize=$true; $ChkTray.Checked=$true; $GrpCfg.Controls.Add($ChkTray)

# -- Advanced / Actions (Bottom Right) --
$GrpAdv = New-Object System.Windows.Forms.GroupBox
$GrpAdv.Text = "Hardening & Actions"; $GrpAdv.Location = New-Object System.Drawing.Point(350, 350); $GrpAdv.Size = New-Object System.Drawing.Size(340, 90); $GrpAdv.ForeColor="LightGray"
$Form.Controls.Add($GrpAdv)

# Banner Checkbox REMOVED - Mandatory now.

$ChkExe = New-Object System.Windows.Forms.CheckBox; $ChkExe.Text="Darken EXE Icon"; $ChkExe.Location=New-Object System.Drawing.Point(15,25); $ChkExe.AutoSize=$true; $ChkExe.Checked=$true; $GrpAdv.Controls.Add($ChkExe)
$ChkUpdate = New-Object System.Windows.Forms.CheckBox; $ChkUpdate.Text="Trigger Update"; $ChkUpdate.Location=New-Object System.Drawing.Point(180,25); $ChkUpdate.AutoSize=$true; $ChkUpdate.Checked=$true; $GrpAdv.Controls.Add($ChkUpdate)

# -- QoL / Repair Buttons --
$BtnRepair = New-Object System.Windows.Forms.Button
$BtnRepair.Text = "Reset Config"; $BtnRepair.Location = New-Object System.Drawing.Point(15, 450); $BtnRepair.Size = New-Object System.Drawing.Size(100, 30); $BtnRepair.BackColor="OrangeRed"; $BtnRepair.FlatStyle="Flat"
$BtnRepair.Add_Click({
    if ([System.Windows.Forms.MessageBox]::Show("Close JD2 and delete 'cfg' folder?","Confirm","YesNo") -eq "Yes") {
        Kill-JDownloader; Backup-JD -InstallPath $TxtPath.Text
        Remove-Item "$($TxtPath.Text)\cfg" -Recurse -Force -ErrorAction SilentlyContinue
        Log-Status "Config reset."
    }
})
$Form.Controls.Add($BtnRepair)

$BtnResetThm = New-Object System.Windows.Forms.Button
$BtnResetThm.Text = "Reset Theme"; $BtnResetThm.Location = New-Object System.Drawing.Point(120, 450); $BtnResetThm.Size = New-Object System.Drawing.Size(100, 30); $BtnResetThm.FlatStyle="Flat"
$BtnResetThm.BackColor=[System.Drawing.Color]::FromArgb(64,64,64)
$BtnResetThm.Add_Click({
    if ([System.Windows.Forms.MessageBox]::Show("Reset only appearance settings?","Confirm","YesNo") -eq "Yes") {
        Kill-JDownloader
        Remove-Item "$($TxtPath.Text)\cfg\laf" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$($TxtPath.Text)\themes\standard\org\jdownloader\images\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$($TxtPath.Text)\themes\minimal\org\jdownloader\images\*" -Recurse -Force -ErrorAction SilentlyContinue
        Log-Status "Theme reset."
    }
})
$Form.Controls.Add($BtnResetThm)

$BtnClearCache = New-Object System.Windows.Forms.Button
$BtnClearCache.Text = "Clear Cache"; $BtnClearCache.Location = New-Object System.Drawing.Point(225, 450); $BtnClearCache.Size = New-Object System.Drawing.Size(100, 30); $BtnClearCache.FlatStyle="Flat"
$BtnClearCache.BackColor=[System.Drawing.Color]::FromArgb(64,64,64)
$BtnClearCache.Add_Click({
    Kill-JDownloader
    Remove-Item "$($TxtPath.Text)\tmp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$($TxtPath.Text)\cfg\*.cache" -Force -ErrorAction SilentlyContinue
    Log-Status "Cache cleared."
})
$Form.Controls.Add($BtnClearCache)

$BtnAudit = New-Object System.Windows.Forms.Button
$BtnAudit.Text = "Run Audit"; $BtnAudit.Location = New-Object System.Drawing.Point(330, 450); $BtnAudit.Size = New-Object System.Drawing.Size(100, 30); $BtnAudit.BackColor="SeaGreen"; $BtnAudit.FlatStyle="Flat"
$BtnAudit.Add_Click({ Run-Audit -InstallPath $TxtPath.Text })
$Form.Controls.Add($BtnAudit)

$BtnSafe = New-Object System.Windows.Forms.Button
$BtnSafe.Text = "Launch Safe Mode"; $BtnSafe.Location = New-Object System.Drawing.Point(15, 485); $BtnSafe.Size = New-Object System.Drawing.Size(150, 30); $BtnSafe.BackColor="SeaGreen"; $BtnSafe.FlatStyle="Flat"
$BtnSafe.Add_Click({
    $exe = "$($TxtPath.Text)\JDownloader2.exe"
    if(Test-Path $exe){ Start-Process $exe -ArgumentList "-safe" }
})
$Form.Controls.Add($BtnSafe)

$BtnUninstall = New-Object System.Windows.Forms.Button
$BtnUninstall.Text = "Full Uninstall"; $BtnUninstall.Location = New-Object System.Drawing.Point(175, 485); $BtnUninstall.Size = New-Object System.Drawing.Size(150, 30); $BtnUninstall.BackColor="Maroon"; $BtnUninstall.FlatStyle="Flat"
$BtnUninstall.Add_Click({
    if ([System.Windows.Forms.MessageBox]::Show("Completely remove JDownloader?","Confirm","YesNo") -eq "Yes") {
        Task-FullUninstall -InstallPath $TxtPath.Text
    }
})
$Form.Controls.Add($BtnUninstall)

$BtnExec = New-Object System.Windows.Forms.Button
$BtnExec.Text = "EXECUTE ALL OPERATIONS"; $BtnExec.Location = New-Object System.Drawing.Point(350, 450); $BtnExec.Size = New-Object System.Drawing.Size(340, 65); $BtnExec.BackColor="DodgerBlue"; $BtnExec.FlatStyle="Flat"; $BtnExec.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$Form.Controls.Add($BtnExec)

# -- Footer: Progress & Log --
$ProgressBar = New-Object System.Windows.Forms.ProgressBar
$ProgressBar.Location = New-Object System.Drawing.Point(15, 530); $ProgressBar.Size = New-Object System.Drawing.Size(675, 10)
$Form.Controls.Add($ProgressBar)

$OutputBox = New-Object System.Windows.Forms.TextBox
$OutputBox.Multiline = $true; $OutputBox.ScrollBars = "Vertical"; $OutputBox.Location = New-Object System.Drawing.Point(15, 550); $OutputBox.Size = New-Object System.Drawing.Size(675, 200)
$OutputBox.BackColor = "Black"; $OutputBox.ForeColor = "LimeGreen"; $OutputBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$Form.Controls.Add($OutputBox)

# -- Startup Logic --
$Form.Add_Load({
    $p = Detect-JDPath
    if ($p) { $TxtPath.Text = $p; Log-Status "JDownloader detected at: $p" }
    
    # Load Settings
    $saved = Load-Settings
    if ($saved) {
        if ($saved.InstallPath -and (Test-Path $saved.InstallPath)) { $TxtPath.Text = $saved.InstallPath }
        if ($saved.ThemeName) { $CboTheme.Text = $saved.ThemeName }
        if ($saved.IconPack) { $CboIcons.Text = $saved.IconPack }
        if ($saved.DlFolder) { $TxtDl.Text = $saved.DlFolder }
    }
})

# -- Execution Handler --
$BtnExec.Add_Click({
    $BtnExec.Enabled = $false; $BtnExec.Text = "Processing..."
    
    $State = @{
        Mode = if ($RadModeMod.Checked) {"Modify"} else {"Install"}
        InstallSource = if ($RadModeGit.Checked) {"GitHub"} else {"Mega"}
        InstallPath = $TxtPath.Text
        ThemeName = $CboTheme.Text
        IconPack = $CboIcons.Text
        WindowDec = $ChkWinDec.Checked
        MaxSim = $NumSim.Value
        DlFolder = $TxtDl.Text
        StartMin = $ChkMin.Checked
        MinToTray = $ChkTray.Checked
        PatchExe = $ChkExe.Checked
        AutoUpdate = $ChkUpdate.Checked
        ForceMinimal = $ChkMinLay.Checked
        PauseSpeed = 10240
    }
    
    # Run async to not freeze GUI completely
    $Form.Refresh()
    Execute-Operations -GUI_State $State
    
    $BtnExec.Text = "EXECUTE ALL OPERATIONS"; $BtnExec.Enabled = $true
    [System.Windows.Forms.MessageBox]::Show("Operations Completed Successfully.", "Done")
})

$Form.Add_Shown({ $Form.Activate() })
[void]$Form.ShowDialog()
