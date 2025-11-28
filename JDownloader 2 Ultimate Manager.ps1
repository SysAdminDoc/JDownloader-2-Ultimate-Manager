<#
.SYNOPSIS
    JDownloader 2 ULTIMATE MANAGER (v9.0)
    - Updated for new GitHub paths (Dark, Material, Default zips).
    - Features: Theme Sync, EXE Patching, Banner Nuking, Icon Replacement.
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
[System.Windows.Forms.Application]::EnableVisualStyles()

# ==========================================
# 2. THEME DEFINITIONS
# ==========================================

$ThemeDefinitions = [ordered]@{
    "Synthetica Black Eye (Dark Icons)" = @{
        "ID"       = "BLACK_EYE"
        "Url"      = "https://raw.githubusercontent.com/Vinylwalk3r/JDownloader-2-Dark-Theme/refs/heads/master/config/cfg/laf/SyntheticaBlackEyeLookAndFeel.json"
        "Local"    = "SyntheticaBlackEyeLookAndFeel.json"
        "IconZip"  = "https://raw.githubusercontent.com/SysAdminDoc/JDownloaderDarkMode/refs/heads/main/Themes/dark.zip"
        "IconSet"  = "minimal" # Config override
    }
    "Synthetica Black Eye (Standard)" = @{
        "ID"       = "BLACK_EYE"
        "Url"      = "https://raw.githubusercontent.com/Vinylwalk3r/JDownloader-2-Dark-Theme/refs/heads/master/config/cfg/laf/SyntheticaBlackEyeLookAndFeel.json"
        "Local"    = "SyntheticaBlackEyeLookAndFeel.json"
        "IconZip"  = "https://raw.githubusercontent.com/SysAdminDoc/JDownloaderDarkMode/refs/heads/main/Themes/default.zip"
        "IconSet"  = "standard"
    }
    "Flat Dark (Material)" = @{
        "ID"       = "FLATLAF_DARK"
        "Url"      = "https://raw.githubusercontent.com/ikoshura/JDownloader-Fluent-Theme/refs/heads/main/FlatMacDarkLaf.json"
        "Local"    = "FlatDarkLaf.json"
        "IconZip"  = "https://raw.githubusercontent.com/SysAdminDoc/JDownloaderDarkMode/refs/heads/main/Themes/material.zip"
        "IconSet"  = "standard"
    }
    "Dracula (Standard)" = @{
        "ID"       = "FLATLAF_DRACULA"
        "Url"      = "https://raw.githubusercontent.com/dracula/jdownloader2/refs/heads/master/FlatDarculaLaf.json"
        "Local"    = "FlatDarculaLaf.json"
        "IconZip"  = "https://raw.githubusercontent.com/SysAdminDoc/JDownloaderDarkMode/refs/heads/main/Themes/default.zip"
        "IconSet"  = "standard"
    }
}

# ==========================================
# 3. EMBEDDED CONFIGURATIONS
# ==========================================

# -- GUI Settings --
$Config_GUI = @'
{
  "overviewpaneldownloadlinksfailedcountvisible": false,
  "horizontalscrollbarsindownloadtableenabled": false,
  "overviewpaneldownloadrunningdownloadscountvisible": true,
  "downloadview": "ALL",
  "linkpropertiespaneldownloadpasswordvisible": true,
  "speedmetervisible": true,
  "overviewpaneldownloadpackagecountvisible": true,
  "datetimeformataccountmanagerexpiredatecolumn": null,
  "password": "",
  "linkpropertiespanelfilenamevisible": true,
  "titlepattern": "|#TITLE|| - #SPEED/s|| - #UPDATENOTIFY|",
  "filterhighlightenabled": true,
  "overviewpaneltotalinfovisible": true,
  "linkpropertiespanelchecksumvisible": true,
  "downloadspropertiespanelsavetovisible": true,
  "packagesbackgroundhighlightenabled": true,
  "overviewpaneldownloadlinkcountvisible": true,
  "downloadspropertiespanelpackagenamevisible": true,
  "overviewpaneldownloadlinksfinishedcountvisible": false,
  "datetimeformatdownloadlistaddeddatecolumn": null,
  "overviewpanelsmartinfovisible": true,
  "availablecolumntextvisible": false,
  "overviewpaneldownloadbytesremainingvisible": true,
  "bannerenabled": false,
  "showfullhostname": false,
  "overviewpanellinkgrabberstatusonlinevisible": true,
  "linkpropertiespanelcommentvisible": true,
  "clipboardmonitored": true,
  "donatebuttonstate": "CUSTOM_HIDDEN",
  "filecountinsizecolumnvisible": true,
  "clipboardskipmode": "ON_STARTUP",
  "premiumexpirewarningenabled": false,
  "downloadstablerefreshinterval": 1000,
  "overviewpaneldownloadpanelincludedisabledlinks": true,
  "datetimeformatdownloadlistmodifieddatecolumn": null,
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
  "datetimeformatdownloadlistfinisheddatecolumn": null,
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
  "updatebuttonflashingenabled": true,
  "customlookandfeelclass": null,
  "overviewpanelvisibleonlyinfovisible": true,
  "linkgrabbersidebarvisible": true,
  "donatebuttonlatestautochange": 1764364213119,
  "downloadspropertiespanelarchivepasswordvisible": true
}
'@

# -- General Settings --
$Config_General = @'
{"maxsimultanedownloadsperhost":1,"delaywritemode":"AUTO","iffileexistsaction":"ASK_FOR_EACH_FILE","dupemanagerenabled":true,"forcemirrordetectioncaseinsensitive":true,"autoopencontainerafterdownload":true,"preferbouncycastlefortls":false,"autostartdownloadoption":"ONLY_IF_EXIT_WITH_RUNNING_DOWNLOADS","maxsimultanedownloads":3,"pausespeed":10240,"defaultdownloadfolder":"C:\\Downloads","windowsjnaidledetectorenabled":true,"downloadspeedlimitrememberedenabled":true,"closedwithrunningdownloads":false,"autostartcountdownseconds":10,"maxdownloadsperhostenabled":false,"maxchunksperfile":1,"sambaprefetchenabled":true,"showcountdownonautostartdownloads":true,"savelinkgrabberlistenabled":true,"onskipduetoalreadyexistsaction":"SKIP_FILE","hashretryenabled":false,"sharedmemorystateenabled":false,"convertrelativepathsjdroot":true,"keepxoldlists":5,"useavailableaccounts":true,"cleanupafterdownloadaction":"NEVER","hashcheckenabled":true,"downloadspeedlimitenabled":false,"downloadspeedlimit":51200}
'@

# -- Tray Settings --
$Config_Tray = @'
{"freshinstall":false,"onminimizeaction":"TO_TASKBAR","tooltipenabled":true,"trayiconclipboardindicatorenabled":false,"oncloseaction":"ASK","tooglewindowstatuswithsingleclickenabled":false,"greyiconenabled":false,"gnometrayicontransparentenabled":true,"enabled":true,"startminimizedenabled":false,"trayonlyvisibleifwindowishiddenenabled":false}
'@

# ==========================================
# 4. UTILITY FUNCTIONS
# ==========================================
$WorkDir = "$env:TEMP\JD2_Full_Tool"
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
$OutputBox = $null; $StatusLabel = $null

function Log-Status {
    param([string]$Text)
    $msg = "[$((Get-Date).ToString('HH:mm:ss'))] $Text`r`n"
    if ($OutputBox -and $OutputBox.IsHandleCreated) {
        $OutputBox.Invoke([Action[string]]{ param($t) $OutputBox.AppendText($t); $OutputBox.ScrollToCaret() }, $msg)
    } else { Write-Host $Text }
    if ($StatusLabel) { $StatusLabel.Text = $Text }
}

function Download-File {
    param([string]$Url, [string]$Destination)
    Log-Status "Downloading: $(Split-Path $Destination -Leaf)"
    try {
        if (-not (Get-Module -Name BitsTransfer -ListAvailable)) { Import-Module BitsTransfer -ErrorAction Stop }
        Start-BitsTransfer -Source $Url -Destination $Destination -ErrorAction Stop -Priority Foreground
        return $true
    } catch {
        try { Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop; return $true }
        catch { Log-Status "Error: $_"; return $false }
    }
}

function Get-7Zip {
    $7z = "$WorkDir\7zr.exe"
    if (-not (Test-Path $7z)) { Download-File -Url "https://www.7-zip.org/a/7zr.exe" -Destination $7z | Out-Null }
    return $7z
}

# ==========================================
# 5. CORE TASKS & HARDENING
# ==========================================

function Kill-JDownloader {
    Log-Status "Stopping JDownloader processes..."
    Get-Process | Where-Object { $_.ProcessName -match "JDownloader|javaw" } | ForEach-Object {
        try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
    Start-Sleep -Seconds 2
}

function Start-Detached-Watchdog {
    Log-Status "Starting Independent Watchdog..."
    $watchdogScript = {
        $cnt = 0; $maxSeconds = 180
        while ($cnt -lt $maxSeconds) {
            $target = Get-Process | Where-Object { $_.ProcessName -like "*JDownloader*2*" }
            if ($target) {
                Start-Process "taskkill.exe" -ArgumentList "/F /IM JDownloader2.exe /T" -NoNewWindow -Wait
                Start-Process "taskkill.exe" -ArgumentList "/F /IM javaw.exe /T" -NoNewWindow -Wait
                break
            }
            Start-Sleep -Seconds 1; $cnt++
        }
    }
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($watchdogScript.ToString()))
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -WindowStyle Hidden -EncodedCommand $encodedCommand"
}

function Task-RefreshIconCache {
    Log-Status "Restarting Explorer (Icon Cache)..."
    try {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep 2
        $IconCachePath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
        Get-ChildItem -Path $IconCachePath -Filter "iconcache_*.db" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force
        Start-Process explorer.exe
    } catch { Log-Status "Error refreshing icon cache: $_" }
}

function Task-NukeBanners {
    param([string]$InstallPath)
    Log-Status "Scanning for Banner Ads..."
    Add-Type -AssemblyName System.Drawing
    $themeDir = "$InstallPath\themes"
    if (Test-Path $themeDir) {
        $bannerFolders = Get-ChildItem -Path $themeDir -Recurse -Directory | Where-Object { $_.Name -eq "banner" }
        foreach ($folder in $bannerFolders) {
            $pngs = Get-ChildItem -Path $folder.FullName -Filter *.png
            foreach ($img in $pngs) {
                try {
                    $original = [System.Drawing.Image]::FromFile($img.FullName)
                    $w = $original.Width; $h = $original.Height
                    $original.Dispose()
                    $bmp = New-Object System.Drawing.Bitmap($w, $h)
                    $bmp.Save($img.FullName, [System.Drawing.Imaging.ImageFormat]::Png)
                    $bmp.Dispose()
                } catch {}
            }
        }
        Log-Status " -> Banners Sanitized."
    }
}

function Task-PatchExeIcon {
    param([string]$InstallPath)
    Log-Status "Downloading Resource Hacker..."
    
    $ResHackerZip = "$WorkDir\resource_hacker.zip"
    $ResHackerDir = "$WorkDir\ResourceHacker"
    $IconFile = "$WorkDir\jd_dark.ico"
    
    Download-File -Url "https://www.angusj.com/resourcehacker/resource_hacker.zip" -Destination $ResHackerZip | Out-Null
    Download-File -Url "https://raw.githubusercontent.com/SysAdminDoc/JDownloaderDarkMode/refs/heads/main/Icons/icon.ico" -Destination $IconFile | Out-Null
    
    if (-not (Test-Path $ResHackerDir)) { Expand-Archive -Path $ResHackerZip -DestinationPath $ResHackerDir -Force }
    $ResHackerExe = "$ResHackerDir\ResourceHacker.exe"
    
    if (-not (Test-Path $ResHackerExe)) { Log-Status "ERROR: Resource Hacker missing."; return }

    $targets = @("$InstallPath\JDownloader2.exe", "$InstallPath\Uninstall JDownloader.exe")
    foreach ($exe in $targets) {
        if (Test-Path $exe) {
            Log-Status "Patching EXE: $(Split-Path $exe -Leaf)"
            $procName = [System.IO.Path]::GetFileNameWithoutExtension($exe)
            Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue
            Start-Sleep 1
            $bak = "$exe.bak"
            if (-not (Test-Path $bak)) { Move-Item -Path $exe -Destination $bak -Force }
            else { Remove-Item $exe -Force -ErrorAction SilentlyContinue }
            
            $args = "-open `"$bak`" -save `"$exe`" -action addoverwrite -res `"$IconFile`" -mask ICONGROUP,MAINICON,0"
            $p = Start-Process -FilePath $ResHackerExe -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
            if ($p.ExitCode -eq 0) { Log-Status " -> Success." } else { Copy-Item -Path $bak -Destination $exe -Force }
        }
    }
}

function Task-InstallAppIcons {
    param([string]$InstallPath)
    Log-Status "Installing Custom Internal App Icons..."
    $icons = @{
        "https://raw.githubusercontent.com/SysAdminDoc/JDownloaderDarkMode/refs/heads/main/Icons/icon.ico" = "icon.ico"
        "https://raw.githubusercontent.com/SysAdminDoc/JDownloaderDarkMode/refs/heads/main/Icons/installer.ico" = "installer.ico"
        "https://raw.githubusercontent.com/SysAdminDoc/JDownloaderDarkMode/refs/heads/main/Icons/i4j_extf_6_69g5ss_1kdboqw.ico" = "i4j_extf_6_69g5ss_1kdboqw.ico"
        "https://raw.githubusercontent.com/SysAdminDoc/JDownloaderDarkMode/refs/heads/main/Icons/i4j_extf.ico" = "i4j_extf.ico"
    }

    $themeIconPath = "$InstallPath\themes\standard\org\jdownloader\images\logo"
    # Fallback to minimal path if standard doesn't exist (depends on active theme)
    if (-not (Test-Path $themeIconPath)) { $themeIconPath = "$InstallPath\themes\minimal\org\jdownloader\images\logo" }
    
    $install4jPath = "$InstallPath\.install4j"
    
    if (-not (Test-Path $themeIconPath)) { New-Item -ItemType Directory -Path $themeIconPath -Force | Out-Null }
    if (-not (Test-Path $install4jPath)) { New-Item -ItemType Directory -Path $install4jPath -Force | Out-Null }

    foreach ($url in $icons.Keys) {
        $filename = $icons[$url]
        $dest = $null
        
        if ($filename -eq "icon.ico") { $dest = "$themeIconPath\icon.ico" } 
        elseif ($filename -eq "installer.ico") { $dest = "$install4jPath\installer.ico" } 
        elseif ($filename -like "i4j_extf*.ico") { $dest = "$install4jPath\$filename" }

        if ($dest) { Download-File -Url $url -Destination $dest | Out-Null }
    }
}

function Task-TriggerUpdate {
    param([string]$InstallPath)
    Log-Status "=== Triggering Updater ==="
    Start-Sleep 2
    $exe = "$InstallPath\JDownloader2.exe"
    if (Test-Path $exe) {
        $p = New-Object System.Diagnostics.ProcessStartInfo
        $p.FileName = $exe; $p.Arguments = "-update"; $p.WorkingDirectory = $InstallPath
        [System.Diagnostics.Process]::Start($p)
        [System.Windows.Forms.MessageBox]::Show("Success!`n`nJDownloader patched.", "Done", "OK", "Information")
    }
}

# ==========================================
# 6. CONFIGURATION ENGINE
# ==========================================

function Apply-Configuration {
    param($Options)
    
    # 1. Kill JD2
    Kill-JDownloader
    
    $paths = @("C:\Program Files\JDownloader", "$env:LOCALAPPDATA\JDownloader 2")
    $JDPath = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $JDPath) { Log-Status "Error: JDownloader not found."; return }
    Log-Status "Targeting: $JDPath"

    $cfgPath = "$JDPath\cfg"
    $lafPath = "$JDPath\cfg\laf"
    if (-not (Test-Path $lafPath)) { New-Item -ItemType Directory -Path $lafPath -Force | Out-Null }

    $ThemeDef = $ThemeDefinitions[$Options.ThemeName]
    $SelectedID = $ThemeDef.ID
    Log-Status "Theme Selected: $($Options.ThemeName)"

    # 2. Download Theme Definition (JSON)
    $lafDest = "$lafPath\$($ThemeDef.Local)"
    Log-Status " -> Fetching Theme definition..."
    if (-not (Download-File -Url $ThemeDef.Url -Destination $lafDest)) {
        Log-Status " -> ERROR: Download failed. Aborting."
        return
    }

    # 3. Patch JSON for IconSet (Minimal vs Standard)
    try {
        $jsonContent = Get-Content -Path $lafDest -Raw -Encoding UTF8 | ConvertFrom-Json
        $targetIconSet = $ThemeDef.IconSet
        
        if (-not $jsonContent.PSObject.Properties["iconsetid"]) {
            $jsonContent | Add-Member -MemberType NoteProperty -Name "iconsetid" -Value $targetIconSet
        } else {
            $jsonContent.iconsetid = $targetIconSet
        }
        $jsonContent | ConvertTo-Json -Depth 100 | Set-Content $lafDest -Encoding UTF8
        Log-Status " -> Configured Theme for '$targetIconSet' icons."
    } catch { Log-Status " -> Warning: Could not patch Theme JSON icon ID." }

    # 4. Handle Icon Zip Download & Extraction
    if ($ThemeDef.IconZip) {
        Log-Status " -> Downloading Icon Pack..."
        $zipUrl = $ThemeDef.IconZip
        $localZip = "$WorkDir\icons.7z"
        $extractPath = "$WorkDir\IconsExtracted"
        
        Download-File -Url $zipUrl -Destination $localZip
        
        # Extract via 7zip
        $7z = Get-7Zip
        if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
        Start-Process $7z -ArgumentList "x `"$localZip`" -o`"$extractPath`" -y" -Wait -WindowStyle Hidden
        
        # INSTALL LOGIC
        # We need to copy the extracted contents to JD/themes.
        # Structure varies (sometimes 'minimal' root, sometimes 'org' root).
        
        $destThemeDir = "$JDPath\themes"
        Log-Status " -> Installing Icons..."
        
        # Check extraction result
        if (Test-Path "$extractPath\minimal") {
             # e.g. dark.zip -> minimal folder
             Copy-Item "$extractPath\minimal" $destThemeDir -Recurse -Force
        } elseif (Test-Path "$extractPath\org") {
             # e.g. default.zip or material.zip might be just 'org'
             # If so, we usually assume it goes into 'standard' or 'minimal' depending on theme.
             # BUT 'Material' usually replaces 'standard'.
             # 'Dark' replaces 'minimal'.
             
             if ($ThemeDef.IconSet -eq "minimal") {
                 $target = "$destThemeDir\minimal"
                 if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
                 Copy-Item "$extractPath\*" $target -Recurse -Force
             } else {
                 # Standard
                 $target = "$destThemeDir\standard"
                 if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
                 Copy-Item "$extractPath\*" $target -Recurse -Force
             }
        } else {
             # Loose files? Dump into target based on IconSet
             if ($ThemeDef.IconSet -eq "minimal") { $target = "$destThemeDir\minimal" } 
             else { $target = "$destThemeDir\standard" }
             
             if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
             Copy-Item "$extractPath\*" $target -Recurse -Force
        }
    }

    # 5. Write Main GUI Config
    try {
        $guiObj = $Config_GUI | ConvertFrom-Json
        $guiObj.lookandfeeltheme = $SelectedID
        if ($Options.CleanConfig) { Log-Status " -> Enforcing Clean Config" }
        $guiObj | ConvertTo-Json -Depth 100 | Set-Content "$cfgPath\org.jdownloader.settings.GraphicalUserInterfaceSettings.json" -Encoding UTF8
    } catch { Log-Status "Error writing GUI config: $_" }

    # 6. Write Other Configs
    $genObj = $Config_General | ConvertFrom-Json
    $genObj.defaultdownloadfolder = "$env:USERPROFILE\Downloads".Replace("\", "\\")
    $genObj | ConvertTo-Json -Depth 100 | Set-Content "$cfgPath\org.jdownloader.settings.GeneralSettings.json" -Encoding UTF8
    $Config_Tray | Set-Content "$cfgPath\org.jdownloader.gui.jdtrayicon.TrayExtension.json" -Encoding UTF8

    # 7. Hardening
    if ($Options.RemoveBanners) { Task-NukeBanners -InstallPath $JDPath }
    if ($Options.PatchExe) { 
        Task-PatchExeIcon -InstallPath $JDPath 
        Task-RefreshIconCache
    }
    Task-InstallAppIcons -InstallPath $JDPath

    Log-Status "=== CONFIGURATION COMPLETE ==="
}

function Install-Mega {
    Log-Status "Installing from Mega..."
    try {
        $link = "https://mega.nz/file/PQ0XRIrA#-uuhLXSc_nPfotXWfBWDZRx90Gnehx2_Mx_JVufzfdM"
        Start-Process $link
        Log-Status "Waiting for installer in Downloads folder..."
        $dlDir = "$env:USERPROFILE\Downloads"
        $start = Get-Date
        while ((Get-Date) -lt $start.AddMinutes(5)) {
            $f = Get-ChildItem $dlDir -Filter "JDownloader*Setup*.exe" | Sort LastWriteTime -Desc | Select -First 1
            if ($f) {
                try { $s=[IO.File]::Open($f.FullName,"Open","Write","None"); $s.Close(); 
                    Start-Detached-Watchdog
                    Start-Process $f.FullName -ArgumentList "-q" -Wait
                    Log-Status "Installation Complete."
                    Task-TriggerUpdate -InstallPath "C:\Program Files\JDownloader"
                    return
                } catch {}
            }
            [System.Windows.Forms.Application]::DoEvents(); Start-Sleep 1
        }
    } catch { Log-Status "Error: $_" }
}

function Install-GitHub {
    Log-Status "Installing from GitHub..."
    $7z = Get-7Zip
    $baseUrl = "https://github.com/SysAdminDoc/JDownloaderDarkMode/raw/main/Installer/installer.7z"
    for ($i = 1; $i -le 7; $i++) {
        $part = ".{0:D3}" -f $i
        Download-File -Url "$baseUrl$part" -Destination "$WorkDir\installer.7z$part"
    }
    Start-Process $7z -ArgumentList "x `"$WorkDir\installer.7z.001`" -o`"$WorkDir\Installer`" -y" -Wait -WindowStyle Hidden
    $setup = Get-ChildItem "$WorkDir\Installer" -Filter "*.exe" -Recurse | Select -First 1
    if ($setup) {
        Start-Detached-Watchdog
        Start-Process $setup.FullName -ArgumentList "-q" -Wait
        Task-TriggerUpdate -InstallPath "C:\Program Files\JDownloader"
    }
}

function Uninstall-Full {
    $locations = @("$env:LOCALAPPDATA\JDownloader 2", "C:\Program Files\JDownloader")
    foreach ($path in $locations) {
        if (Test-Path $path) {
            Log-Status "Uninstalling: $path"
            Get-Process | Where-Object { $_.ProcessName -like "*JDownloader*" } | Stop-Process -Force -ErrorAction SilentlyContinue
            $uninst = "$path\Uninstall JDownloader.exe"
            if (Test-Path $uninst) { Start-Process -FilePath $uninst -ArgumentList "-q" -Wait }
            Start-Sleep 2
            if (Test-Path $path) { Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    Log-Status "Full Uninstall Complete."
}

# ==========================================
# 7. MAIN GUI
# ==========================================
$Form = New-Object System.Windows.Forms.Form
$Form.Text = "JDownloader 2 Ultimate Manager - Installation, Removal, Themes"
$Form.Size = New-Object System.Drawing.Size(700, 750)
$Form.StartPosition = "CenterScreen"
$Form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$Form.ForeColor = [System.Drawing.Color]::WhiteSmoke

$LblTitle = New-Object System.Windows.Forms.Label
$LblTitle.Text = "JDownloader 2 Ultimate Manager"
$LblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$LblTitle.Location = New-Object System.Drawing.Point(20, 20)
$LblTitle.AutoSize = $true
$Form.Controls.Add($LblTitle)

# Install Group
$GrpInst = New-Object System.Windows.Forms.GroupBox
$GrpInst.Text = "Installation"
$GrpInst.Location = New-Object System.Drawing.Point(20, 70)
$GrpInst.Size = New-Object System.Drawing.Size(300, 110)
$GrpInst.ForeColor = [System.Drawing.Color]::LightGray
$Form.Controls.Add($GrpInst)

$RadNone = New-Object System.Windows.Forms.RadioButton; $RadNone.Text = "Modify Existing (Skip Install)"; $RadNone.Location = New-Object System.Drawing.Point(20, 20); $RadNone.AutoSize = $true; $RadNone.Checked = $true; $GrpInst.Controls.Add($RadNone)
$RadGit = New-Object System.Windows.Forms.RadioButton; $RadGit.Text = "Install from GitHub"; $RadGit.Location = New-Object System.Drawing.Point(20, 45); $RadGit.AutoSize = $true; $GrpInst.Controls.Add($RadGit)
$RadMega = New-Object System.Windows.Forms.RadioButton; $RadMega.Text = "Install from JDownloader's Mega (Browser)"; $RadMega.Location = New-Object System.Drawing.Point(20, 70); $RadMega.AutoSize = $true; $GrpInst.Controls.Add($RadMega)

# Theme Group
$GrpTheme = New-Object System.Windows.Forms.GroupBox
$GrpTheme.Text = "Theme & Appearance"
$GrpTheme.Location = New-Object System.Drawing.Point(20, 200)
$GrpTheme.Size = New-Object System.Drawing.Size(300, 100)
$GrpTheme.ForeColor = [System.Drawing.Color]::LightGray
$Form.Controls.Add($GrpTheme)

$LblThm = New-Object System.Windows.Forms.Label; $LblThm.Text = "Select Theme:"; $LblThm.Location = New-Object System.Drawing.Point(20, 25); $LblThm.AutoSize=$true; $GrpTheme.Controls.Add($LblThm)
$CboTheme = New-Object System.Windows.Forms.ComboBox; $CboTheme.Location = New-Object System.Drawing.Point(20, 45); $CboTheme.Width=250; $CboTheme.DropDownStyle="DropDownList"
foreach ($k in $ThemeDefinitions.Keys) { $CboTheme.Items.Add($k) | Out-Null }; $CboTheme.SelectedIndex=0; $GrpTheme.Controls.Add($CboTheme)
$LblNote = New-Object System.Windows.Forms.Label; $LblNote.Text = "* Icons are auto-applied based on selection."; $LblNote.Location = New-Object System.Drawing.Point(20, 75); $LblNote.AutoSize=$true; $LblNote.ForeColor=[System.Drawing.Color]::Gray; $GrpTheme.Controls.Add($LblNote)

# Hardening Group
$GrpHard = New-Object System.Windows.Forms.GroupBox
$GrpHard.Text = "Additional Settings"
$GrpHard.Location = New-Object System.Drawing.Point(340, 70)
$GrpHard.Size = New-Object System.Drawing.Size(320, 230)
$GrpHard.ForeColor = [System.Drawing.Color]::LightGray
$Form.Controls.Add($GrpHard)

$ChkClean = New-Object System.Windows.Forms.CheckBox; $ChkClean.Text = "Remove Advertisements"; $ChkClean.Location = New-Object System.Drawing.Point(20, 30); $ChkClean.AutoSize=$true; $ChkClean.Checked=$true; $GrpHard.Controls.Add($ChkClean)
$ChkBan = New-Object System.Windows.Forms.CheckBox; $ChkBan.Text = "Remove Banners"; $ChkBan.Location = New-Object System.Drawing.Point(20, 60); $ChkBan.AutoSize=$true; $ChkBan.Checked=$true; $GrpHard.Controls.Add($ChkBan)
$ChkPatch = New-Object System.Windows.Forms.CheckBox; $ChkPatch.Text = "Darkmodify EXE Icon"; $ChkPatch.Location = New-Object System.Drawing.Point(20, 90); $ChkPatch.AutoSize=$true; $ChkPatch.Checked=$true; $GrpHard.Controls.Add($ChkPatch)

$BtnUninst = New-Object System.Windows.Forms.Button
$BtnUninst.Text = "FULL UNINSTALL (Deep Clean)"; $BtnUninst.Location = New-Object System.Drawing.Point(20, 170); $BtnUninst.Size = New-Object System.Drawing.Size(280, 40)
$BtnUninst.BackColor = [System.Drawing.Color]::FromArgb(192, 57, 43); $BtnUninst.ForeColor = [System.Drawing.Color]::White; $BtnUninst.FlatStyle="Flat"
$BtnUninst.Add_Click({ if([System.Windows.Forms.MessageBox]::Show("Delete Everything?","Confirm","YesNo")-eq"Yes"){Uninstall-Full} })
$GrpHard.Controls.Add($BtnUninst)

$BtnGo = New-Object System.Windows.Forms.Button
$BtnGo.Text = "EXECUTE ALL OPERATIONS"; $BtnGo.Location = New-Object System.Drawing.Point(20, 320); $BtnGo.Size = New-Object System.Drawing.Size(640, 50)
$BtnGo.BackColor = [System.Drawing.Color]::FromArgb(0, 122, 204); $BtnGo.ForeColor = [System.Drawing.Color]::White; $BtnGo.FlatStyle="Flat"
$BtnGo.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$Form.Controls.Add($BtnGo)

$OutputBox = New-Object System.Windows.Forms.TextBox
$OutputBox.Multiline = $true; $OutputBox.ScrollBars = "Vertical"; $OutputBox.Location = New-Object System.Drawing.Point(20, 390); $OutputBox.Size = New-Object System.Drawing.Size(640, 290)
$OutputBox.BackColor = [System.Drawing.Color]::Black; $OutputBox.ForeColor = [System.Drawing.Color]::LimeGreen; $OutputBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$Form.Controls.Add($OutputBox)

$BtnGo.Add_Click({
    $BtnGo.Enabled = $false; $BtnGo.Text = "Processing..."
    if ($RadGit.Checked) { Install-GitHub }
    if ($RadMega.Checked) { Install-Mega }
    
    $opts = @{
        ThemeName = $CboTheme.Text
        CleanConfig = $ChkClean.Checked
        RemoveBanners = $ChkBan.Checked
        PatchExe = $ChkPatch.Checked
    }
    Apply-Configuration -Options $opts
    $BtnGo.Text = "Operations Complete"; $BtnGo.Enabled = $true
})

$Form.Add_Shown({ $Form.Activate() })
[void]$Form.ShowDialog()