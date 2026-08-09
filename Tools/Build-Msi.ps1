[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Join-Path $PSScriptRoot '..') 'dist\JDownloader2UltimateManager.msi')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $repoRoot 'JDownloader 2 Ultimate Manager.ps1'
$versionPattern = '\$script:AppVersion\s*=\s*[''\"](?<version>[^''\"]+)[''\"]'
$versionMatch = Select-String -LiteralPath $scriptPath -Pattern $versionPattern | Select-Object -First 1
if (-not $versionMatch) { throw 'Could not determine the application version from the main script.' }
$appVersion = $versionMatch.Matches[0].Groups['version'].Value
$msiVersion = if ($appVersion -match '^\d+\.\d+\.\d+\.\d+$') { $appVersion } else { "$appVersion.0" }

$wix = Get-Command wix -CommandType Application -ErrorAction Stop
$ps2exe = Get-Command Invoke-ps2exe -CommandType Function,Cmdlet -ErrorAction Stop
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $outputFullPath
$stageRoot = Join-Path $env:TEMP ('JD2-UM-msi-' + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    if (Test-Path -LiteralPath $outputFullPath) { Remove-Item -LiteralPath $outputFullPath -Force }

    $stageExe = Join-Path $stageRoot 'JDownloader2UltimateManager.exe'
    & $ps2exe -InputFile $scriptPath -OutputFile $stageExe -NoConsole -RequireAdmin -Title 'JDownloader 2 Ultimate Manager' -Version $appVersion
    if (-not (Test-Path -LiteralPath $stageExe)) { throw 'PS2EXE did not produce the staged executable.' }

    foreach ($relativePath in @('icon.ico', 'icon.png')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $relativePath) -Destination (Join-Path $stageRoot $relativePath) -Force
    }
    foreach ($directory in @('Tools', 'Translations', 'Sounds')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $directory) -Destination (Join-Path $stageRoot $directory) -Recurse -Force
    }

    $wxsPath = Join-Path $repoRoot 'Installer\JD2UltimateManager.wxs'
    $intermediatePath = Join-Path $stageRoot 'obj'
    New-Item -ItemType Directory -Path $intermediatePath -Force | Out-Null
    & $wix.Source build $wxsPath -arch x64 -ext WixToolset.Util.wixext -d "SourceDir=$stageRoot" -d "AppVersion=$msiVersion" -intermediatefolder $intermediatePath -out $outputFullPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputFullPath)) { throw 'WiX did not produce the MSI artifact.' }

    Get-Item -LiteralPath $outputFullPath | Select-Object FullName, Length, LastWriteTime
}
finally {
    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
