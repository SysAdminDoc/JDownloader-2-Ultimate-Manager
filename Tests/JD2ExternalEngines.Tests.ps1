BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\Tools\JD2ExternalEngines.psm1"
    Import-Module -Name $modulePath -Force
}

Describe "JD2 external engine lanes" {
    It "builds a hidden yt-dlp fallback command" {
        $fake = Join-Path $TestDrive "yt-dlp.exe"
        Set-Content -LiteralPath $fake -Value "stub" -Encoding UTF8
        $info = New-JD2ExternalDownloadStartInfo -Engine yt-dlp -CommandPath $fake -Url "https://example.test/video?id=1" -OutputDirectory (Join-Path $TestDrive "downloads")
        $info.FileName | Should -Be ([IO.Path]::GetFullPath($fake))
        $info.Arguments | Should -Match "--no-progress"
        $info.Arguments | Should -Match "video"
        $info.CreateNoWindow | Should -BeTrue
    }

    It "builds an aria2c split command" {
        $fake = Join-Path $TestDrive "aria2c.exe"
        Set-Content -LiteralPath $fake -Value "stub" -Encoding UTF8
        $info = New-JD2ExternalDownloadStartInfo -Engine aria2c -CommandPath $fake -Url "https://example.test/file.zip" -OutputDirectory (Join-Path $TestDrive "downloads")
        $info.Arguments | Should -Match "--split=16"
        $info.Arguments | Should -Match "--max-connection-per-server=16"
    }

    It "normalizes a FlareSolverr solve response through an injectable request" {
        $handler = {
            param($endpoint, $body)
            $body | Should -Match 'request.get'
            [pscustomobject]@{
                status = 'ok'
                solution = [pscustomobject]@{
                    request = 'https://example.test/solved'
                    userAgent = 'test-agent'
                    cookies = @([pscustomobject]@{ name = 'cf_clearance'; value = 'token' })
                }
            }
        }
        $result = Invoke-JD2FlareSolverr -Endpoint 'http://127.0.0.1:8191/v1' -Url 'https://example.test/challenge' -RequestHandler $handler
        $result.Status | Should -Be 'ok'
        $result.Request | Should -Be 'https://example.test/solved'
        $result.Cookies.Count | Should -Be 1
    }

    It "rejects non-web fallback targets" {
        { New-JD2ExternalDownloadStartInfo -Engine aria2c -CommandPath 'C:\missing.exe' -Url 'file:///secret' -OutputDirectory $TestDrive } | Should -Throw
    }
}
