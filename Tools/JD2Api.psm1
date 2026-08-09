Set-StrictMode -Version 2.0

$script:JD2ApiRequestCounter = [long]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())

function New-JD2ApiClient {
    [CmdletBinding()]
    param(
        [string]$BaseUrl = "http://127.0.0.1:3128",
        [ValidateSet("Local", "MyJDownloader")]
        [string]$Mode = "Local",
        [ValidateRange(1, 120)]
        [int]$TimeoutSec = 8,
        [System.Collections.IDictionary]$Headers,
        [scriptblock]$RequestInvoker
    )

    if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
        throw "JDownloader API endpoint cannot be empty."
    }

    try {
        $uri = New-Object System.Uri($BaseUrl)
    } catch {
        throw "JDownloader API endpoint is not a valid URL: $BaseUrl"
    }

    if ($uri.Scheme -notin @("http", "https")) {
        throw "JDownloader API endpoint must use http or https."
    }

    $headerTable = @{}
    if ($Headers) {
        foreach ($key in $Headers.Keys) {
            if (-not [string]::IsNullOrWhiteSpace([string]$key)) {
                $headerTable[[string]$key] = [string]$Headers[$key]
            }
        }
    }

    return [pscustomobject]@{
        PSTypeName      = "JD2.ApiClient"
        BaseUrl         = $BaseUrl.TrimEnd("/")
        Mode            = $Mode
        TimeoutSec      = $TimeoutSec
        Headers         = $headerTable
        RequestInvoker  = $RequestInvoker
        RequestId       = [long]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
    }
}

function Get-JD2ApiRequestId {
    return [System.Threading.Interlocked]::Increment([ref]$script:JD2ApiRequestCounter)
}

function ConvertTo-JD2ApiParameter {
    param($Value)

    if ($null -eq $Value) {
        return "null"
    }

    try {
        return ($Value | ConvertTo-Json -Depth 100 -Compress)
    } catch {
        throw "Could not serialize a JDownloader API parameter: $($_.Exception.Message)"
    }
}

function New-JD2ApiRequestUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][string]$Namespace,
        [Parameter(Mandatory)][string]$Method,
        [object[]]$Parameters
    )

    if (-not $Client -or [string]::IsNullOrWhiteSpace([string]$Client.BaseUrl)) {
        throw "A valid JDownloader API client is required."
    }
    if ($Namespace -notmatch "^[A-Za-z][A-Za-z0-9_-]*$") {
        throw "Invalid JDownloader API namespace: $Namespace"
    }
    if ($Method -notmatch "^[A-Za-z][A-Za-z0-9_-]*$") {
        throw "Invalid JDownloader API method: $Method"
    }

    $endpoint = "{0}/{1}/{2}" -f ([string]$Client.BaseUrl).TrimEnd("/"), $Namespace, $Method
    if ($null -eq $Parameters -or $Parameters.Count -eq 0) {
        return $endpoint
    }

    $encoded = New-Object System.Collections.Generic.List[string]
    foreach ($parameter in $Parameters) {
        $json = ConvertTo-JD2ApiParameter -Value $parameter
        [void]$encoded.Add([System.Uri]::EscapeDataString($json))
    }
    return "{0}?{1}" -f $endpoint, ($encoded -join "&")
}

function Get-JD2ApiResponseContent {
    param($Response)

    if ($null -eq $Response) {
        throw "JDownloader API returned an empty response."
    }
    if ($Response -is [string]) {
        return [string]$Response
    }
    if ($Response.PSObject.Properties.Name -contains "Content") {
        return [string]$Response.Content
    }
    return ($Response | ConvertTo-Json -Depth 100 -Compress)
}

function ConvertFrom-JD2ApiResponse {
    param([string]$Content)

    if ([string]::IsNullOrWhiteSpace($Content)) {
        throw "JDownloader API returned an empty response."
    }

    try {
        $payload = $Content | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "JDownloader API returned invalid JSON: $($_.Exception.Message)"
    }

    $properties = @($payload.PSObject.Properties.Name)
    if (($properties -contains "error") -and $null -ne $payload.error) {
        $errorText = if ($payload.error -is [string]) { [string]$payload.error } else { $payload.error | ConvertTo-Json -Compress }
        throw "JDownloader API error: $errorText"
    }
    if (($properties -contains "type") -and ($properties -contains "src") -and $payload.type) {
        throw "JDownloader API error from $($payload.src): $($payload.type)"
    }
    if ($properties -contains "data") {
        return $payload.data
    }
    return $payload
}

function Invoke-JD2ApiMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][string]$Namespace,
        [Parameter(Mandatory)][string]$Method,
        [object[]]$Parameters
    )

    $requestUri = New-JD2ApiRequestUri -Client $Client -Namespace $Namespace -Method $Method -Parameters $Parameters
    $requestId = Get-JD2ApiRequestId
    $Client.RequestId = $requestId

    try {
        if ($Client.RequestInvoker) {
            $response = & $Client.RequestInvoker $requestUri
        } else {
            $headers = @{}
            if ($Client.Headers) {
                foreach ($key in $Client.Headers.Keys) { $headers[$key] = $Client.Headers[$key] }
            }
            $response = Invoke-WebRequest -Uri $requestUri -Method Get -Headers $headers -UseBasicParsing -TimeoutSec $Client.TimeoutSec -ErrorAction Stop
        }

        return ConvertFrom-JD2ApiResponse -Content (Get-JD2ApiResponseContent -Response $response)
    } catch {
        if ($_.Exception.Message -like "JDownloader API*") { throw }
        throw "JDownloader API request failed ($Namespace/$Method): $($_.Exception.Message)"
    }
}

function Get-JD2Queue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [ValidateRange(1, 5000)][int]$MaxLinks = 500,
        [ValidateRange(1, 1000)][int]$MaxPackages = 200
    )

    $linkQuery = [ordered]@{
        startAt     = 0
        maxResults  = $MaxLinks
        bytesLoaded = $true
        bytesTotal  = $true
        eta         = $true
        finished    = $true
        host        = $true
        name        = $true
        packageUUID = $true
        running     = $true
        skipped     = $true
        speed       = $true
        status      = $true
        url         = $true
    }
    # JDownloader expects packageUUIDs only when filtering; packageUUID is a returned field.
    $linkQuery.Remove("packageUUID")
    $packageQuery = [ordered]@{
        startAt     = 0
        maxResults  = $MaxPackages
        bytesLoaded = $true
        bytesTotal  = $true
        childCount  = $true
        finished    = $true
        hosts       = $true
        name        = $true
        running     = $true
        saveTo      = $true
        speed       = $true
        status      = $true
    }

    $links = @(Invoke-JD2ApiMethod -Client $Client -Namespace "downloadsV2" -Method "queryLinks" -Parameters @($linkQuery))
    $packages = @(Invoke-JD2ApiMethod -Client $Client -Namespace "downloadsV2" -Method "queryPackages" -Parameters @($packageQuery))

    $loaded = [int64]0
    $total = [int64]0
    $speed = [int64]0
    $active = 0
    $finishedCount = 0
    foreach ($link in $links) {
        try { $loaded += [int64]$link.bytesLoaded } catch {}
        try { $total += [int64]$link.bytesTotal } catch {}
        try { $speed += [int64]$link.speed } catch {}
        try { if ([bool]$link.running) { $active++ } } catch {}
        try { if ([bool]$link.finished) { $finishedCount++ } } catch {}
    }

    return [pscustomobject]@{
        Links         = $links
        Packages      = $packages
        TotalLinks    = $links.Count
        TotalPackages = $packages.Count
        ActiveLinks   = $active
        FinishedLinks = $finishedCount
        BytesLoaded   = $loaded
        BytesTotal    = $total
        SpeedBps      = $speed
        RefreshedAt   = Get-Date
    }
}

function Get-JD2LinkGrabberQueue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [ValidateRange(1, 5000)][int]$MaxLinks = 500,
        [ValidateRange(1, 1000)][int]$MaxPackages = 200
    )

    $linkQuery = [ordered]@{
        startAt     = 0
        maxResults  = $MaxLinks
        availability = $true
        bytesTotal  = $true
        enabled     = $true
        host        = $true
        name        = $true
        packageUUID = $true
        status      = $true
        url         = $true
    }
    $linkQuery.Remove("packageUUID")
    $packageQuery = [ordered]@{
        startAt        = 0
        maxResults     = $MaxPackages
        availableOnlineCount = $true
        availableOfflineCount = $true
        bytesTotal     = $true
        childCount     = $true
        enabled        = $true
        hosts          = $true
        name           = $true
        saveTo         = $true
        status         = $true
    }

    $links = @(Invoke-JD2ApiMethod -Client $Client -Namespace "linkgrabberv2" -Method "queryLinks" -Parameters @($linkQuery))
    $packages = @(Invoke-JD2ApiMethod -Client $Client -Namespace "linkgrabberv2" -Method "queryPackages" -Parameters @($packageQuery))
    return [pscustomobject]@{
        Links         = $links
        Packages      = $packages
        TotalLinks    = $links.Count
        TotalPackages = $packages.Count
        RefreshedAt   = Get-Date
    }
}

function Start-JD2Downloads {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Client)
    return Invoke-JD2ApiMethod -Client $Client -Namespace "downloadcontroller" -Method "start"
}

function Stop-JD2Downloads {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Client)
    return Invoke-JD2ApiMethod -Client $Client -Namespace "downloadcontroller" -Method "stop"
}

function Set-JD2DownloadsPaused {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][bool]$Paused
    )
    return Invoke-JD2ApiMethod -Client $Client -Namespace "downloadcontroller" -Method "pause" -Parameters @($Paused)
}

function Add-JD2Links {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][string[]]$Links,
        [string]$PackageName,
        [string]$DestinationFolder,
        [bool]$AutoStart = $false,
        [bool]$DeepDecrypt = $true
    )

    $normalized = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $Links) {
        if ($null -eq $entry) { continue }
        foreach ($line in ([string]$entry -split "`r?`n")) {
            $value = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($value)) { continue }
            if ($value -notmatch "^(?i)(https?|ftp|ftps|magnet|file|jdlist|data):") {
                throw "Unsupported link format: $value"
            }
            if (-not $normalized.Contains($value)) { [void]$normalized.Add($value) }
        }
    }

    if ($normalized.Count -eq 0) {
        throw "At least one download link is required."
    }

    $query = [ordered]@{
        assignJobID  = $true
        autostart    = $AutoStart
        deepDecrypt  = $DeepDecrypt
        links        = ($normalized -join "`r`n")
    }
    if (-not [string]::IsNullOrWhiteSpace($PackageName)) { $query.packageName = $PackageName.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($DestinationFolder)) { $query.destinationFolder = $DestinationFolder.Trim() }

    return Invoke-JD2ApiMethod -Client $Client -Namespace "linkgrabberv2" -Method "addLinks" -Parameters @($query)
}

function Test-JD2ApiConnection {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Client)

    try {
        $null = Invoke-JD2ApiMethod -Client $Client -Namespace "downloadsV2" -Method "packageCount"
        return $true
    } catch {
        return $false
    }
}

function Get-JD2CaptchaJobs {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Client)
    return @(Invoke-JD2ApiMethod -Client $Client -Namespace "captcha" -Method "list")
}

function Get-JD2CaptchaImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][long]$Id
    )
    return Invoke-JD2ApiMethod -Client $Client -Namespace "captcha" -Method "get" -Parameters @($Id)
}

function Submit-JD2Captcha {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][long]$Id,
        [Parameter(Mandatory)][string]$Result,
        [string]$ResultFormat = "text"
    )
    if ([string]::IsNullOrWhiteSpace($Result)) {
        throw "Captcha answer cannot be empty."
    }
    return Invoke-JD2ApiMethod -Client $Client -Namespace "captcha" -Method "solve" -Parameters @($Id, $Result, $ResultFormat)
}

function Skip-JD2Captcha {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][long]$Id,
        [ValidateSet("SINGLE", "BLOCK_HOSTER", "BLOCK_ALL_CAPTCHAS", "BLOCK_PACKAGE", "REFRESH", "STOP_CURRENT_ACTION", "TIMEOUT")]
        [string]$Type = "SINGLE"
    )
    return Invoke-JD2ApiMethod -Client $Client -Namespace "captcha" -Method "skip" -Parameters @($Id, $Type)
}

function Get-JD2Accounts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [ValidateRange(1, 1000)][int]$MaxResults = 200
    )
    $query = [ordered]@{
        startAt     = 0
        maxResults  = $MaxResults
        enabled     = $true
        error       = $true
        trafficLeft = $true
        trafficMax  = $true
        userName    = $true
        valid       = $true
        validUntil  = $true
    }
    return @(Invoke-JD2ApiMethod -Client $Client -Namespace "accountsV2" -Method "listAccounts" -Parameters @($query))
}

function Add-JD2Account {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][string]$PremiumHoster,
        [Parameter(Mandatory)][string]$AccountUser,
        [Parameter(Mandatory)][string]$AccountSecret
    )
    if ([string]::IsNullOrWhiteSpace($PremiumHoster)) { throw "Premium hoster cannot be empty." }
    if ([string]::IsNullOrWhiteSpace($AccountUser)) { throw "Account username cannot be empty." }
    if ([string]::IsNullOrWhiteSpace($AccountSecret)) { throw "Account password cannot be empty." }
    return Invoke-JD2ApiMethod -Client $Client -Namespace "accountsV2" -Method "addAccount" -Parameters @($PremiumHoster.Trim(), $AccountUser.Trim(), $AccountSecret)
}

function Set-JD2AccountEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][long[]]$Ids,
        [Parameter(Mandatory)][bool]$Enabled
    )
    if (-not $Ids -or $Ids.Count -eq 0) { throw "At least one account id is required." }
    return Invoke-JD2ApiMethod -Client $Client -Namespace "accountsV2" -Method "setEnabledState" -Parameters @($Enabled, $Ids)
}

function Remove-JD2Accounts {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][long[]]$Ids
    )
    if (-not $Ids -or $Ids.Count -eq 0) { throw "At least one account id is required." }
    if ($PSCmdlet.ShouldProcess(($Ids -join ","), "Remove JDownloader accounts")) {
        return Invoke-JD2ApiMethod -Client $Client -Namespace "accountsV2" -Method "removeAccounts" -Parameters @($Ids)
    }
    return $false
}

Export-ModuleMember -Function @(
    "New-JD2ApiClient",
    "New-JD2ApiRequestUri",
    "Invoke-JD2ApiMethod",
    "Get-JD2Queue",
    "Get-JD2LinkGrabberQueue",
    "Start-JD2Downloads",
    "Stop-JD2Downloads",
    "Set-JD2DownloadsPaused",
    "Add-JD2Links",
    "Get-JD2CaptchaJobs",
    "Get-JD2CaptchaImage",
    "Submit-JD2Captcha",
    "Skip-JD2Captcha",
    "Get-JD2Accounts",
    "Add-JD2Account",
    "Set-JD2AccountEnabled",
    "Remove-JD2Accounts",
    "Test-JD2ApiConnection"
)
