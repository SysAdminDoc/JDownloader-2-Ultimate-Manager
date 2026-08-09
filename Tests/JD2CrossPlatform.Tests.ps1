BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\Tools\JD2CrossPlatform.psm1"
    Import-Module -Name $modulePath -Force
}

Describe "JD2 cross-platform configuration engine" {
    It "detects an install and atomically updates cfg JSON with a snapshot" {
        $root = Join-Path $TestDrive "JDownloader"
        $cfg = Join-Path $root "cfg"
        New-Item -ItemType Directory -Path $cfg -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root "JDownloader2") -Value "launcher" -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $cfg "org.jdownloader.settings.GeneralSettings.json") -Value '{"maxsimultanedownloads":3}' -Encoding UTF8

        $resolved = Resolve-JD2ConfigRoot -InstallPath $root
        $resolved.ConfigPath | Should -Be ([IO.Path]::GetFullPath($cfg))
        $updated = Set-JD2ConfigJson -Resolved $resolved -FileName "org.jdownloader.settings.GeneralSettings.json" -Values @{ maxsimultanedownloads = 5 }
        Test-Path -LiteralPath $updated | Should -BeTrue
        (Read-JD2ConfigJson -Resolved $resolved -FileName "org.jdownloader.settings.GeneralSettings.json").maxsimultanedownloads | Should -Be 5
        Test-Path -LiteralPath (Join-Path $root "cfg-backup") | Should -BeTrue
    }

    It "resolves an AppImage data cfg directory" {
        $root = Join-Path $TestDrive "AppImage"
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $appImage = Join-Path $root "JDownloader.AppImage"
        Set-Content -LiteralPath $appImage -Value "appimage" -Encoding UTF8
        New-Item -ItemType Directory -Path (Join-Path $root "JDownloader-data/cfg") -Force | Out-Null

        $resolved = Resolve-JD2ConfigRoot -InstallPath $appImage
        $resolved.IsAppImage | Should -BeTrue
        $resolved.ConfigPath | Should -Match "JDownloader-data"
    }

    It "rejects config paths that escape cfg" {
        $root = Join-Path $TestDrive "Safe"
        New-Item -ItemType Directory -Path (Join-Path $root "cfg") -Force | Out-Null
        $resolved = Resolve-JD2ConfigRoot -InstallPath $root
        { Read-JD2ConfigJson -Resolved $resolved -FileName "..\outside.json" } | Should -Throw
    }
}
