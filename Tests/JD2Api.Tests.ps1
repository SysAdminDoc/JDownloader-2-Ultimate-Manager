BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\Tools\JD2Api.psm1"
    Import-Module -Name $modulePath -Force
}

function global:ConvertTo-TestJdHex {
    param([byte[]]$Bytes)
    return (($Bytes | ForEach-Object { $_.ToString("x2") }) -join "")
}

function global:ConvertFrom-TestJdHex {
    param([string]$Hex)
    $bytes = New-Object byte[] ($Hex.Length / 2)
    for ($index = 0; $index -lt $bytes.Length; $index++) {
        $bytes[$index] = [Convert]::ToByte($Hex.Substring($index * 2, 2), 16)
    }
    return $bytes
}

function global:Get-TestJdSha256 {
    param([byte[]]$Bytes)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return $hash.ComputeHash($Bytes) }
    finally { $hash.Dispose() }
}

function global:Join-TestJdBytes {
    param([byte[]]$Left, [byte[]]$Right)
    $joined = New-Object byte[] ($Left.Length + $Right.Length)
    [Buffer]::BlockCopy($Left, 0, $joined, 0, $Left.Length)
    [Buffer]::BlockCopy($Right, 0, $joined, $Left.Length, $Right.Length)
    return $joined
}

function global:Protect-TestJdPayload {
    param([byte[]]$Token, [string]$PlainText)
    $aes = [Security.Cryptography.Aes]::Create()
    try {
        $key = New-Object byte[] 16
        $iv = New-Object byte[] 16
        [Buffer]::BlockCopy($Token, 16, $key, 0, 16)
        [Buffer]::BlockCopy($Token, 0, $iv, 0, 16)
        $aes.Mode = [Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $key
        $aes.IV = $iv
        $bytes = [Text.Encoding]::UTF8.GetBytes($PlainText)
        return [Convert]::ToBase64String($aes.CreateEncryptor().TransformFinalBlock($bytes, 0, $bytes.Length))
    } finally { $aes.Dispose() }
}

function global:Unprotect-TestJdPayload {
    param([byte[]]$Token, [string]$CipherText)
    $aes = [Security.Cryptography.Aes]::Create()
    try {
        $key = New-Object byte[] 16
        $iv = New-Object byte[] 16
        [Buffer]::BlockCopy($Token, 16, $key, 0, 16)
        [Buffer]::BlockCopy($Token, 0, $iv, 0, 16)
        $aes.Mode = [Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $key
        $aes.IV = $iv
        $cipher = [Convert]::FromBase64String($CipherText)
        $plain = $aes.CreateDecryptor().TransformFinalBlock($cipher, 0, $cipher.Length)
        return [Text.Encoding]::UTF8.GetString($plain)
    } finally { $aes.Dispose() }
}

Describe "JD2 API transport" {
    It "builds escaped positional JSON parameters" {
        $client = New-JD2ApiClient -BaseUrl "http://127.0.0.1:3128"
        $uri = New-JD2ApiRequestUri -Client $client -Namespace "downloadsV2" -Method "queryLinks" -Parameters @([ordered]@{})

        $uri | Should -Be "http://127.0.0.1:3128/downloadsV2/queryLinks?%7B%7D"
    }

    It "returns queue data and derived counters" {
        $seen = New-Object System.Collections.Generic.List[string]
        $invoker = {
            param($uri)
            [void]$seen.Add($uri)
            if ($uri -match "/queryLinks\\?") {
                return '{"data":[{"name":"one.zip","bytesLoaded":50,"bytesTotal":100,"speed":25,"running":true,"finished":false}]}'
            }
            return '{"data":[{"name":"Package","bytesLoaded":50,"bytesTotal":100,"childCount":1}]}'
        }.GetNewClosure()
        $client = New-JD2ApiClient -BaseUrl "http://127.0.0.1:3128" -RequestInvoker $invoker

        $queue = Get-JD2Queue -Client $client

        $queue.TotalLinks | Should -Be 1
        $queue.TotalPackages | Should -Be 1
        $queue.ActiveLinks | Should -Be 1
        $queue.BytesLoaded | Should -Be 50
        $queue.SpeedBps | Should -Be 25
        $seen.Count | Should -Be 2
    }

    It "maps controller actions to documented endpoints" {
        $seen = New-Object System.Collections.Generic.List[string]
        $invoker = {
            param($uri)
            [void]$seen.Add($uri)
            return '{"data":true}'
        }.GetNewClosure()
        $client = New-JD2ApiClient -RequestInvoker $invoker

        Start-JD2Downloads -Client $client | Should -BeTrue
        Set-JD2DownloadsPaused -Client $client -Paused $true | Should -BeTrue
        Stop-JD2Downloads -Client $client | Should -BeTrue

        ($seen -join "`n") | Should -Match "downloadcontroller/start"
        ($seen -join "`n") | Should -Match "downloadcontroller/pause"
        ($seen -join "`n") | Should -Match "downloadcontroller/stop"
    }

    It "normalizes link input and sends one linkgrabber query" {
        $seen = New-Object System.Collections.Generic.List[string]
        $invoker = {
            param($uri)
            [void]$seen.Add($uri)
            return '{"data":{"id":123}}'
        }.GetNewClosure()
        $client = New-JD2ApiClient -RequestInvoker $invoker

        $result = Add-JD2Links -Client $client -Links @("https://example.test/a`nhttps://example.test/a", "magnet:?xt=urn:btih:abc") -PackageName "Test package"
        $result.id | Should -Be 123
        $seen.Count | Should -Be 1
        ([System.Uri]::UnescapeDataString(($seen[0] -split "\\?", 2)[1])) | Should -Match '"links":"https://example.test/a'
    }

    It "rejects empty and unsupported links before making a request" {
        $invoker = { param($uri) throw "The request should not run." }
        $client = New-JD2ApiClient -RequestInvoker $invoker

        { Add-JD2Links -Client $client -Links @(" ") } | Should -Throw "At least one download link is required."
        { Add-JD2Links -Client $client -Links @("not-a-url") } | Should -Throw "Unsupported link format: not-a-url"
    }

    It "supports captcha polling, image retrieval, solving, and skipping" {
        $seen = New-Object System.Collections.Generic.List[string]
        $invoker = {
            param($uri)
            [void]$seen.Add($uri)
            if ($uri -match "/captcha/list") { return '{"data":[{"id":42,"hoster":"example","type":"text"}]}' }
            if ($uri -match "/captcha/get") { return '{"data":"data:image/png;base64,AAAA"}' }
            return '{"data":true}'
        }.GetNewClosure()
        $client = New-JD2ApiClient -RequestInvoker $invoker

        $jobs = @(Get-JD2CaptchaJobs -Client $client)
        $jobs.Count | Should -Be 1
        $jobs[0].id | Should -Be 42
        Get-JD2CaptchaImage -Client $client -Id 42 | Should -Be "data:image/png;base64,AAAA"
        Submit-JD2Captcha -Client $client -Id 42 -Result "answer" | Should -BeTrue
        Skip-JD2Captcha -Client $client -Id 42 | Should -BeTrue
        ($seen -join "`n") | Should -Match "captcha/solve"
        ($seen -join "`n") | Should -Match "captcha/skip"
    }

    It "queries and updates global bandwidth settings through the config API" {
        $seen = New-Object System.Collections.Generic.List[string]
        $invoker = {
            param($uri)
            [void]$seen.Add($uri)
            if ($uri -match "config/query") {
                return '{"data":[{"interfaceName":"org.jdownloader.settings.GeneralSettings","storage":"cfg","key":"downloadspeedlimitenabled"},{"interfaceName":"org.jdownloader.settings.GeneralSettings","storage":"cfg","key":"downloadspeedlimit"}]}'
            }
            return '{"data":true}'
        }.GetNewClosure()
        $client = New-JD2ApiClient -RequestInvoker $invoker

        Set-JD2DownloadBandwidth -Client $client -Enabled $true -LimitBytesPerSecond 2097152 | Should -BeTrue
        $seen.Count | Should -Be 3
        ($seen -join "`n") | Should -Match "config/query"
        ($seen -join "`n") | Should -Match "config/set"
    }

    It "queries and updates per-host bandwidth settings through the config API" {
        $seen = New-Object System.Collections.Generic.List[string]
        $invoker = {
            param($uri)
            [void]$seen.Add($uri)
            if ($uri -match "config/query") {
                return '{"data":[{"interfaceName":"org.jdownloader.settings.GeneralSettings","storage":"cfg","key":"maxdownloadsperhostenabled"},{"interfaceName":"org.jdownloader.settings.GeneralSettings","storage":"cfg","key":"maxsimultanedownloadsperhost"}]}'
            }
            return '{"data":true}'
        }.GetNewClosure()
        $client = New-JD2ApiClient -RequestInvoker $invoker

        Set-JD2PerHostBandwidth -Client $client -Enabled $true -MaxDownloadsPerHost 4 | Should -BeTrue
        $seen.Count | Should -Be 3
        ($seen -join "`n") | Should -Match "config/query"
        ($seen -join "`n") | Should -Match "maxdownloadsperhostenabled"
        ($seen -join "`n") | Should -Match "maxsimultanedownloadsperhost"
    }

    It "lists accounts and maps account mutations" {
        $seen = New-Object System.Collections.Generic.List[string]
        $invoker = {
            param($uri)
            [void]$seen.Add($uri)
            if ($uri -match "accountsV2/listAccounts") { return '{"data":[{"uuid":7,"hostname":"example","username":"user","valid":true}]}' }
            return '{"data":true}'
        }.GetNewClosure()
        $client = New-JD2ApiClient -RequestInvoker $invoker

        $accounts = @(Get-JD2Accounts -Client $client)
        $accounts.Count | Should -Be 1
        $accounts[0].uuid | Should -Be 7
        Add-JD2Account -Client $client -PremiumHoster "example" -AccountUser "user" -AccountSecret "secret" | Should -BeTrue
        Set-JD2AccountEnabled -Client $client -Ids ([long[]](7)) -Enabled $false | Should -BeTrue
        Remove-JD2Accounts -Client $client -Ids ([long[]](7)) -Confirm:$false | Should -BeTrue
        ($seen -join "`n") | Should -Match "accountsV2/addAccount"
        ($seen -join "`n") | Should -Match "accountsV2/setEnabledState"
        ($seen -join "`n") | Should -Match "accountsV2/removeAccounts"
    }

    It "connects to MyJDownloader and routes encrypted device calls" {
        $email = "User@Example.test"
        $passwordText = "test-password"
        $password = ConvertTo-SecureString $passwordText -AsPlainText -Force
        $sessionToken = "0123456789abcdef0123456789abcdef"
        $loginSecret = Get-TestJdSha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($email.ToLowerInvariant() + $passwordText + "server"))
        $deviceSecret = Get-TestJdSha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($email.ToLowerInvariant() + $passwordText + "device"))
        $sessionBytes = ConvertFrom-TestJdHex -Hex $sessionToken
        $serverToken = Get-TestJdSha256 -Bytes (Join-TestJdBytes -Left $loginSecret -Right $sessionBytes)
        $deviceToken = Get-TestJdSha256 -Bytes (Join-TestJdBytes -Left $deviceSecret -Right $sessionBytes)
        $remoteUris = New-Object System.Collections.Generic.List[string]
        $remotePaths = New-Object System.Collections.Generic.List[string]
        $invoker = {
            param($request)
            [void]$remoteUris.Add([string]$request.Uri)
            $uri = [string]$request.Uri
            $ridMatch = [regex]::Match($uri, "(?:^|&)rid=(\d+)")
            $rid = if ($ridMatch.Success) { [long]$ridMatch.Groups[1].Value } else { 0 }
            if ($request.Method -eq "POST") {
                $payload = (Unprotect-TestJdPayload -Token $deviceToken -CipherText $request.Body) | ConvertFrom-Json
                [void]$remotePaths.Add([string]$payload.url)
                $rid = [long]$payload.rid
                if ([string]$payload.url -eq "/downloadsV2/queryLinks") {
                    $result = [ordered]@{ data = @([ordered]@{ name = "remote.zip"; bytesLoaded = 50; bytesTotal = 100; speed = 25; running = $true; finished = $false }); rid = $rid }
                } elseif ([string]$payload.url -eq "/downloadsV2/queryPackages") {
                    $result = [ordered]@{ data = @([ordered]@{ name = "Remote"; childCount = 1; bytesLoaded = 50; bytesTotal = 100 }); rid = $rid }
                } else {
                    $result = [ordered]@{ data = $true; rid = $rid }
                }
                return Protect-TestJdPayload -Token $deviceToken -PlainText ($result | ConvertTo-Json -Depth 20 -Compress)
            }
            if ($uri -match "/my/connect") {
                $result = [ordered]@{ sessiontoken = $sessionToken; regaintoken = "regain-token"; rid = $rid }
                return Protect-TestJdPayload -Token $loginSecret -PlainText ($result | ConvertTo-Json -Depth 20 -Compress)
            }
            if ($uri -match "/my/listdevices") {
                $result = [ordered]@{ list = @([ordered]@{ id = "device-1"; name = "Office" }); rid = $rid }
                return Protect-TestJdPayload -Token $serverToken -PlainText ($result | ConvertTo-Json -Depth 20 -Compress)
            }
            $result = [ordered]@{ data = $true; rid = $rid }
            return Protect-TestJdPayload -Token $serverToken -PlainText ($result | ConvertTo-Json -Depth 20 -Compress)
        }.GetNewClosure()
        $client = New-JD2ApiClient -Mode MyJDownloader -RequestInvoker $invoker

        $devices = @(Connect-JD2MyJDownloader -Client $client -Email $email -Password $password -DeviceName "Office")

        $devices.Count | Should -Be 1
        $client.Connected | Should -BeTrue
        $client.DeviceId | Should -Be "device-1"
        $remoteUris[0] | Should -Match "signature="
        $remoteUris[0] | Should -Not -Match [regex]::Escape($passwordText)
        $queue = Get-JD2Queue -Client $client
        $queue.TotalLinks | Should -Be 1
        $queue.BytesLoaded | Should -Be 50
        $queue.SpeedBps | Should -Be 25
        Start-JD2Downloads -Client $client | Should -BeTrue
        ($remotePaths -join "`n") | Should -Match "/downloadsV2/queryLinks"
        ($remotePaths -join "`n") | Should -Match "/downloadsV2/queryPackages"
        Disconnect-JD2MyJDownloader -Client $client | Should -BeTrue
        $client.Connected | Should -BeFalse
    }
}
