#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [string]$InstallPath,
    [switch]$Detect,
    [string]$ConfigFile,
    [string]$SetKey,
    [string]$SetValue,
    [switch]$Snapshot,
    [switch]$Cleanup,
    [ValidateRange(1, 3650)][int]$RetentionDays = 30
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'JD2CrossPlatform.psm1'
Import-Module -Name $modulePath -Force
$resolved = Resolve-JD2ConfigRoot -InstallPath $InstallPath -CreateConfig:$false
if (-not $resolved) { throw 'No JDownloader installation or AppImage cfg directory was found. Pass -InstallPath explicitly.' }

if ($Detect -or (-not $ConfigFile -and -not $Snapshot -and -not $Cleanup)) {
    Get-JD2CrossPlatformHealth -InstallPath $resolved.InstallPath | ConvertTo-Json -Depth 6
    exit 0
}
if ($Snapshot) {
    [pscustomobject]@{ SnapshotPath = (New-JD2ConfigSnapshot -Resolved $resolved); ConfigPath = $resolved.ConfigPath } | ConvertTo-Json -Depth 4
}
if ($Cleanup) {
    [pscustomobject]@{ Removed = (Invoke-JD2CrossPlatformCleanup -Resolved $resolved -RetentionDays $RetentionDays); ConfigPath = $resolved.ConfigPath } | ConvertTo-Json -Depth 4
}
if ($ConfigFile) {
    if ($SetKey) {
        if ($null -eq $SetValue) { throw '-SetValue is required with -SetKey.' }
        $value = $SetValue
        if ($SetValue -match '^(true|false)$') { $value = [bool]::Parse($SetValue) }
        elseif ($SetValue -match '^-?\d+$') { $value = [int64]$SetValue }
        [pscustomobject]@{ Updated = (Set-JD2ConfigJson -Resolved $resolved -FileName $ConfigFile -Values @{ $SetKey = $value }); ConfigPath = $resolved.ConfigPath } | ConvertTo-Json -Depth 4
    } else {
        Read-JD2ConfigJson -Resolved $resolved -FileName $ConfigFile | ConvertTo-Json -Depth 20
    }
}
