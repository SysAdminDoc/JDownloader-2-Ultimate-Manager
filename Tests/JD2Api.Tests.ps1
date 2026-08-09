BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\Tools\JD2Api.psm1"
    Import-Module -Name $modulePath -Force
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
}
