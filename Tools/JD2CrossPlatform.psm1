Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Expand-JD2Path {
    param([Parameter(Mandatory)][string]$Path)
    $expanded = $Path
    if ($expanded.StartsWith('~')) {
        $homePath = if ($HOME) { $HOME } else { [Environment]::GetFolderPath('UserProfile') }
        $expanded = Join-Path $homePath $expanded.Substring(1).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    }
    return [IO.Path]::GetFullPath($expanded)
}

function Test-JD2PathWithin {
    param([Parameter(Mandatory)][string]$Child, [Parameter(Mandatory)][string]$Parent)
    $childPath = (Expand-JD2Path -Path $Child).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $parentPath = (Expand-JD2Path -Path $Parent).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    return $childPath.Equals($parentPath, [StringComparison]::OrdinalIgnoreCase) -or $childPath.StartsWith($parentPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Get-JD2CrossPlatformCandidates {
    param([string]$InstallPath)
    if (-not [string]::IsNullOrWhiteSpace($InstallPath)) { return @((Expand-JD2Path -Path $InstallPath)) }
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($value in @($env:JDOWNLOADER_HOME, $env:JD2_HOME)) {
        if (-not [string]::IsNullOrWhiteSpace($value)) { $candidates.Add((Expand-JD2Path -Path $value)) }
    }
    $homePath = if ($HOME) { $HOME } else { [Environment]::GetFolderPath('UserProfile') }
    foreach ($value in @(
        (Join-Path $homePath '.jd'),
        (Join-Path $homePath '.config/jdownloader'),
        (Join-Path $homePath 'JDownloader'),
        '/opt/JDownloader',
        '/usr/local/JDownloader'
    )) { $candidates.Add((Expand-JD2Path -Path $value)) }
    return @($candidates | Select-Object -Unique)
}

function Resolve-JD2ConfigRoot {
    param(
        [string]$InstallPath,
        [switch]$CreateConfig
    )
    foreach ($candidate in @(Get-JD2CrossPlatformCandidates -InstallPath $InstallPath)) {
        $isAppImage = (Test-Path -LiteralPath $candidate -PathType Leaf) -and ([IO.Path]::GetExtension($candidate) -ieq '.AppImage')
        $basePath = if ($isAppImage) { Split-Path -Parent $candidate } else { $candidate }
        $appImageName = if ($isAppImage) { [IO.Path]::GetFileNameWithoutExtension($candidate) } else { '' }
        $configCandidates = New-Object System.Collections.Generic.List[string]
        if ($isAppImage) {
            $configCandidates.Add((Join-Path $basePath "$appImageName-data/cfg"))
            $configCandidates.Add((Join-Path $basePath 'cfg'))
        } else {
            $configCandidates.Add((Join-Path $candidate 'cfg'))
            $configCandidates.Add((Join-Path $candidate 'config/cfg'))
        }
        foreach ($configPath in @($configCandidates | Select-Object -Unique)) {
            if (Test-Path -LiteralPath $configPath -PathType Container) {
                return [pscustomobject]@{ InstallPath = $candidate; ConfigPath = (Expand-JD2Path -Path $configPath); IsAppImage = $isAppImage; AppImagePath = if ($isAppImage) { $candidate } else { $null } }
            }
        }
        if ($CreateConfig -and -not $isAppImage -and (Test-Path -LiteralPath $candidate -PathType Container)) {
            $configPath = Join-Path $candidate 'cfg'
            New-Item -ItemType Directory -Path $configPath -Force | Out-Null
            return [pscustomobject]@{ InstallPath = $candidate; ConfigPath = (Expand-JD2Path -Path $configPath); IsAppImage = $false; AppImagePath = $null }
        }
    }
    return $null
}

function Get-JD2CrossPlatformHealth {
    param([string]$InstallPath)
    $resolved = Resolve-JD2ConfigRoot -InstallPath $InstallPath
    if (-not $resolved) { return [pscustomobject]@{ Ready = $false; Detail = 'No JDownloader cfg directory was found.'; InstallPath = $InstallPath; ConfigPath = $null; IsAppImage = $false } }
    $coreNames = if ($resolved.IsAppImage) { @($resolved.AppImagePath) } else { @('JDownloader2', 'JDownloader2.jar', 'JDownloader2.exe') | ForEach-Object { Join-Path $resolved.InstallPath $_ } }
    $hasCore = @($coreNames | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count -gt 0
    [pscustomobject]@{ Ready = ($hasCore -or (Get-ChildItem -LiteralPath $resolved.ConfigPath -Force -ErrorAction SilentlyContinue | Select-Object -First 1)); Detail = if ($hasCore) { 'JDownloader core and cfg were found.' } else { 'cfg was found; core launcher was not detected.' }; InstallPath = $resolved.InstallPath; ConfigPath = $resolved.ConfigPath; IsAppImage = $resolved.IsAppImage; AppImagePath = $resolved.AppImagePath }
}

function Get-JD2ConfigFilePath {
    param([Parameter(Mandatory)]$Resolved, [Parameter(Mandatory)][string]$FileName)
    if ([IO.Path]::IsPathRooted($FileName) -or $FileName -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::GetExtension($FileName) -ine '.json') { throw 'ConfigFile must be a relative .json filename inside cfg.' }
    $path = Expand-JD2Path -Path (Join-Path $Resolved.ConfigPath $FileName)
    if (-not (Test-JD2PathWithin -Child $path -Parent $Resolved.ConfigPath)) { throw 'ConfigFile resolves outside cfg.' }
    return $path
}

function Read-JD2ConfigJson {
    param([Parameter(Mandatory)]$Resolved, [Parameter(Mandatory)][string]$FileName)
    $path = Get-JD2ConfigFilePath -Resolved $Resolved -FileName $FileName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $file = Get-Item -LiteralPath $path
    if ($file.Length -gt 4MB) { throw 'Config file is larger than 4 MB; refusing to load it.' }
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]@{} }
    return $raw | ConvertFrom-Json -ErrorAction Stop
}

function New-JD2ConfigSnapshot {
    param([Parameter(Mandatory)]$Resolved)
    $parent = Join-Path $Resolved.InstallPath 'cfg-backup'
    $destination = Join-Path $parent (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $Resolved.ConfigPath -Force -ErrorAction SilentlyContinue)) {
        if ($item.Name -in @('tmp', 'logs', 'linkcollector')) { continue }
        Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse -Force
    }
    return $destination
}

function Set-JD2ConfigJson {
    param(
        [Parameter(Mandatory)]$Resolved,
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][hashtable]$Values,
        [switch]$NoSnapshot
    )
    if (-not $NoSnapshot) { [void](New-JD2ConfigSnapshot -Resolved $Resolved) }
    New-Item -ItemType Directory -Path $Resolved.ConfigPath -Force | Out-Null
    $path = Get-JD2ConfigFilePath -Resolved $Resolved -FileName $FileName
    $object = Read-JD2ConfigJson -Resolved $Resolved -FileName $FileName
    if (-not $object) { $object = [pscustomobject]@{} }
    foreach ($key in $Values.Keys) {
        if ($object.PSObject.Properties.Name -contains [string]$key) { $object.PSObject.Properties[[string]$key].Value = $Values[$key] }
        else { $object | Add-Member -MemberType NoteProperty -Name ([string]$key) -Value $Values[$key] }
    }
    $temp = "$path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $json = $object | ConvertTo-Json -Depth 20
        [IO.File]::WriteAllText($temp, $json, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temp -Destination $path -Force
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
    return $path
}

function Invoke-JD2CrossPlatformCleanup {
    param([Parameter(Mandatory)]$Resolved, [ValidateRange(1, 3650)][int]$RetentionDays = 30)
    $cutoff = (Get-Date).AddDays(-1 * $RetentionDays)
    $removed = 0
    $targets = @((Join-Path $Resolved.InstallPath 'tmp'), (Join-Path $Resolved.ConfigPath 'tmp'), (Join-Path $Resolved.InstallPath 'logs'))
    foreach ($target in $targets) {
        if (-not (Test-Path -LiteralPath $target -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $target -File -Recurse -Force -ErrorAction SilentlyContinue | Where-Object LastWriteTime -lt $cutoff)) {
            if (Test-JD2PathWithin -Child $file.FullName -Parent $target) { Remove-Item -LiteralPath $file.FullName -Force; $removed++ }
        }
    }
    return $removed
}

Export-ModuleMember -Function Get-JD2CrossPlatformCandidates, Resolve-JD2ConfigRoot, Get-JD2CrossPlatformHealth, Read-JD2ConfigJson, New-JD2ConfigSnapshot, Set-JD2ConfigJson, Invoke-JD2CrossPlatformCleanup
