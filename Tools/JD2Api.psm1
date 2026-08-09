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
        [scriptblock]$RequestInvoker,
        [string]$AppKey = "https://github.com/SysAdminDoc/JDownloader-2-Ultimate-Manager",
        [string]$DeviceId,
        [string]$DeviceName
    )

    if ($Mode -eq "MyJDownloader" -and ([string]::IsNullOrWhiteSpace($BaseUrl) -or $BaseUrl -eq "http://127.0.0.1:3128")) {
        $BaseUrl = "https://api.jdownloader.org"
    }

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
        AppKey          = $AppKey
        Email           = $null
        DeviceId        = $DeviceId
        DeviceName      = $DeviceName
        Devices         = @()
        LoginSecret     = $null
        DeviceSecret    = $null
        ServerEncryptionToken = $null
        DeviceEncryptionToken = $null
        SessionToken    = $null
        RegainToken     = $null
        Connected       = $false
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

function Get-JD2SecureStringText {
    param([System.Security.SecureString]$Value)
    if (-not $Value) { return "" }
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Get-JD2Sha256Bytes {
    param([byte[]]$Bytes)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return $hash.ComputeHash($Bytes) }
    finally { $hash.Dispose() }
}

function ConvertTo-JD2Hex {
    param([byte[]]$Bytes)
    return (($Bytes | ForEach-Object { $_.ToString("x2") }) -join "")
}

function ConvertFrom-JD2Hex {
    param([string]$Hex)
    if ([string]::IsNullOrWhiteSpace($Hex) -or ($Hex.Length % 2) -ne 0 -or $Hex -notmatch "^[0-9a-fA-F]+$") {
        throw "JDownloader returned an invalid hexadecimal token."
    }
    $bytes = New-Object byte[] ($Hex.Length / 2)
    for ($index = 0; $index -lt $bytes.Length; $index++) {
        $bytes[$index] = [Convert]::ToByte($Hex.Substring($index * 2, 2), 16)
    }
    return $bytes
}

function Join-JD2Bytes {
    param([byte[]]$Left, [byte[]]$Right)
    $joined = New-Object byte[] ($Left.Length + $Right.Length)
    [Buffer]::BlockCopy($Left, 0, $joined, 0, $Left.Length)
    [Buffer]::BlockCopy($Right, 0, $joined, $Left.Length, $Right.Length)
    return $joined
}

function New-JD2MyJdSecret {
    param(
        [Parameter(Mandatory)][string]$Email,
        [Parameter(Mandatory)][System.Security.SecureString]$Password,
        [Parameter(Mandatory)][string]$Domain
    )
    $passwordText = Get-JD2SecureStringText -Value $Password
    try {
        $material = [Text.Encoding]::UTF8.GetBytes($Email.Trim().ToLowerInvariant() + $passwordText + $Domain.ToLowerInvariant())
        return Get-JD2Sha256Bytes -Bytes $material
    } finally {
        $passwordText = $null
    }
}

function Get-JD2HmacHex {
    param([Parameter(Mandatory)][byte[]]$Key, [Parameter(Mandatory)][string]$Text)
    $hmac = New-Object Security.Cryptography.HMACSHA256(,$Key)
    try { return ConvertTo-JD2Hex -Bytes ($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))) }
    finally { $hmac.Dispose() }
}

function Protect-JD2MyJdPayload {
    param([Parameter(Mandatory)][byte[]]$Token, [Parameter(Mandatory)][string]$PlainText)
    if ($Token.Length -ne 32) { throw "JDownloader encryption token must be 32 bytes." }
    $aes = [Security.Cryptography.Aes]::Create()
    try {
        $aes.Mode = [Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
        $aes.KeySize = 128
        $aes.BlockSize = 128
        $aes.Key = $Token[16..31]
        $aes.IV = $Token[0..15]
        $bytes = [Text.Encoding]::UTF8.GetBytes($PlainText)
        $cipher = $aes.CreateEncryptor().TransformFinalBlock($bytes, 0, $bytes.Length)
        return [Convert]::ToBase64String($cipher)
    } finally { $aes.Dispose() }
}

function Unprotect-JD2MyJdPayload {
    param([Parameter(Mandatory)][byte[]]$Token, [Parameter(Mandatory)][string]$CipherText)
    if ($Token.Length -ne 32) { throw "JDownloader encryption token must be 32 bytes." }
    try { $cipher = [Convert]::FromBase64String($CipherText) } catch { throw "JDownloader returned an invalid encrypted response." }
    $aes = [Security.Cryptography.Aes]::Create()
    try {
        $aes.Mode = [Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
        $aes.KeySize = 128
        $aes.BlockSize = 128
        $aes.Key = $Token[16..31]
        $aes.IV = $Token[0..15]
        $plain = $aes.CreateDecryptor().TransformFinalBlock($cipher, 0, $cipher.Length)
        return [Text.Encoding]::UTF8.GetString($plain)
    } catch { throw "JDownloader returned an undecryptable response: $($_.Exception.Message)" }
    finally { $aes.Dispose() }
}

function Invoke-JD2MyJdTransport {
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][string]$Uri,
        [ValidateSet("GET", "POST")][string]$Method = "GET",
        [string]$Body,
        [string]$ContentType
    )
    $headers = @{}
    if ($Client.Headers) {
        foreach ($key in $Client.Headers.Keys) { $headers[[string]$key] = [string]$Client.Headers[$key] }
    }
    try {
        if ($Client.RequestInvoker) {
            return & $Client.RequestInvoker ([pscustomobject]@{
                Uri         = $Uri
                Method      = $Method
                Headers     = $headers
                Body        = $Body
                ContentType = $ContentType
            })
        }
        if ($Method -eq "POST") {
            return Invoke-WebRequest -Uri $Uri -Method Post -Headers $headers -Body $Body -ContentType $ContentType -UseBasicParsing -TimeoutSec $Client.TimeoutSec -ErrorAction Stop
        }
        return Invoke-WebRequest -Uri $Uri -Method Get -Headers $headers -UseBasicParsing -TimeoutSec $Client.TimeoutSec -ErrorAction Stop
    } catch {
        throw "JDownloader MyJDownloader transport failed: $($_.Exception.Message)"
    }
}

function Get-JD2MyJdRequestId {
    param([Parameter(Mandatory)]$Client)
    $requestId = Get-JD2ApiRequestId
    if ($requestId -le [long]$Client.RequestId) { $requestId = [long]$Client.RequestId + 1 }
    $Client.RequestId = $requestId
    return $requestId
}

function Invoke-JD2MyJdRequest {
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][string]$Path,
        [System.Collections.IDictionary]$QueryParameters,
        [object[]]$Parameters,
        [switch]$DeviceRequest
    )
    $requestId = Get-JD2MyJdRequestId -Client $Client
    $requestUri = $null
    $responseToken = $null
    $method = "GET"
    $body = $null
    $contentType = $null

    if ($DeviceRequest) {
        if (-not $Client.Connected -or [string]::IsNullOrWhiteSpace([string]$Client.SessionToken)) {
            throw "MyJDownloader is not connected."
        }
        if ([string]::IsNullOrWhiteSpace([string]$Client.DeviceId)) {
            throw "Select a MyJDownloader device before making a request."
        }
        $serializedParameters = @()
        foreach ($parameter in @($Parameters)) { $serializedParameters += ConvertTo-JD2ApiParameter -Value $parameter }
        $requestPayload = [ordered]@{
            apiVer = 1
            url    = $Path
            params = $serializedParameters
            rid    = $requestId
        }
        $body = Protect-JD2MyJdPayload -Token $Client.DeviceEncryptionToken -PlainText ($requestPayload | ConvertTo-Json -Depth 100 -Compress)
        $requestUri = "{0}/t_{1}_{2}{3}" -f $Client.BaseUrl.TrimEnd("/"), $Client.SessionToken, $Client.DeviceId, $Path
        $responseToken = $Client.DeviceEncryptionToken
        $method = "POST"
        $contentType = "application/aesjson-jd; charset=utf-8"
    } else {
        $parts = New-Object System.Collections.Generic.List[string]
        if ($QueryParameters) {
            foreach ($key in $QueryParameters.Keys) {
                $queryPart = "{0}={1}" -f ([string]$key), ([Uri]::EscapeDataString([string]$QueryParameters[$key]))
                [void]$parts.Add($queryPart)
            }
        }
        [void]$parts.Add("rid={0}" -f $requestId)
        $unsigned = "{0}?{1}" -f $Path, ($parts -join "&")
        $signatureKey = if ($Client.ServerEncryptionToken) { $Client.ServerEncryptionToken } else { $Client.LoginSecret }
        if (-not $signatureKey) { throw "MyJDownloader authentication has not been initialized." }
        $requestUri = "{0}{1}&signature={2}" -f $Client.BaseUrl.TrimEnd("/"), $unsigned, (Get-JD2HmacHex -Key $signatureKey -Text $unsigned)
        $responseToken = if ($Client.ServerEncryptionToken) { $Client.ServerEncryptionToken } else { $Client.LoginSecret }
    }

    $response = Invoke-JD2MyJdTransport -Client $Client -Uri $requestUri -Method $method -Body $body -ContentType $contentType
    $statusCode = 200
    if ($response -and $response.PSObject.Properties.Name -contains "StatusCode") { $statusCode = [int]$response.StatusCode }
    $content = Get-JD2ApiResponseContent -Response $response
    if ($statusCode -ne 200) { throw ("JDownloader MyJDownloader API returned HTTP {0}: {1}" -f $statusCode, $content) }
    $plainText = Unprotect-JD2MyJdPayload -Token $responseToken -CipherText $content
    try { $payload = $plainText | ConvertFrom-Json -ErrorAction Stop } catch { throw "JDownloader returned invalid MyJDownloader JSON: $($_.Exception.Message)" }
    if ($payload.PSObject.Properties.Name -contains "rid" -and [long]$payload.rid -ne $requestId) {
        throw "JDownloader returned a mismatched MyJDownloader request id."
    }
    return $payload
}

function Connect-JD2MyJDownloader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][string]$Email,
        [Parameter(Mandatory)][System.Security.SecureString]$Password,
        [string]$DeviceId,
        [string]$DeviceName
    )
    if ($Client.Mode -ne "MyJDownloader") { throw "The API client is not configured for MyJDownloader." }
    if ([string]::IsNullOrWhiteSpace($Email)) { throw "MyJDownloader email cannot be empty." }
    if (-not $Password) { throw "MyJDownloader password cannot be empty." }
    $Client.Email = $Email.Trim().ToLowerInvariant()
    $Client.DeviceId = if ([string]::IsNullOrWhiteSpace($DeviceId)) { $Client.DeviceId } else { $DeviceId.Trim() }
    $Client.DeviceName = if ([string]::IsNullOrWhiteSpace($DeviceName)) { $Client.DeviceName } else { $DeviceName.Trim() }
    $Client.LoginSecret = New-JD2MyJdSecret -Email $Client.Email -Password $Password -Domain "server"
    $Client.DeviceSecret = New-JD2MyJdSecret -Email $Client.Email -Password $Password -Domain "device"
    $Client.ServerEncryptionToken = $null
    $Client.DeviceEncryptionToken = $null
    $Client.Connected = $false

    $connectResponse = Invoke-JD2MyJdRequest -Client $Client -Path "/my/connect" -QueryParameters ([ordered]@{ email = $Client.Email; appkey = $Client.AppKey })
    if (-not $connectResponse.sessiontoken -or -not $connectResponse.regaintoken) { throw "MyJDownloader did not return a session token." }
    $Client.SessionToken = [string]$connectResponse.sessiontoken
    $Client.RegainToken = [string]$connectResponse.regaintoken
    $sessionBytes = ConvertFrom-JD2Hex -Hex $Client.SessionToken
    $Client.ServerEncryptionToken = Get-JD2Sha256Bytes -Bytes (Join-JD2Bytes -Left $Client.LoginSecret -Right $sessionBytes)
    $Client.DeviceEncryptionToken = Get-JD2Sha256Bytes -Bytes (Join-JD2Bytes -Left $Client.DeviceSecret -Right $sessionBytes)
    $Client.Connected = $true
    $devices = @(Get-JD2MyJDownloaderDevices -Client $Client)
    $Client.Devices = $devices

    $selected = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$Client.DeviceId)) { $selected = $devices | Where-Object { [string]$_.id -eq [string]$Client.DeviceId } | Select-Object -First 1 }
    if (-not $selected -and -not [string]::IsNullOrWhiteSpace([string]$Client.DeviceName)) { $selected = $devices | Where-Object { [string]$_.name -eq [string]$Client.DeviceName } | Select-Object -First 1 }
    if (-not $selected -and $devices.Count -eq 1) { $selected = $devices[0] }
    if ($selected) {
        $Client.DeviceId = [string]$selected.id
        $Client.DeviceName = [string]$selected.name
    } else {
        $Client.DeviceId = $null
    }
    return $devices
}

function Get-JD2MyJDownloaderDevices {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Client)
    if (-not $Client.Connected) { throw "MyJDownloader is not connected." }
    $response = Invoke-JD2MyJdRequest -Client $Client -Path "/my/listdevices" -QueryParameters ([ordered]@{ sessiontoken = $Client.SessionToken })
    if ($response.PSObject.Properties.Name -contains "list") { return @($response.list) }
    if ($response.PSObject.Properties.Name -contains "data") { return @($response.data) }
    return @()
}

function Set-JD2MyJDownloaderDevice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [string]$DeviceId,
        [string]$DeviceName
    )
    if (-not $Client.Connected) { throw "MyJDownloader is not connected." }
    $devices = @(if ($Client.Devices) { $Client.Devices } else { Get-JD2MyJDownloaderDevices -Client $Client })
    $selected = if (-not [string]::IsNullOrWhiteSpace($DeviceId)) {
        $devices | Where-Object { [string]$_.id -eq $DeviceId } | Select-Object -First 1
    } else {
        $devices | Where-Object { [string]$_.name -eq $DeviceName } | Select-Object -First 1
    }
    if (-not $selected) { throw "MyJDownloader device was not found." }
    $Client.DeviceId = [string]$selected.id
    $Client.DeviceName = [string]$selected.name
    return $selected
}

function Disconnect-JD2MyJDownloader {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Client)
    if ($Client.Mode -eq "MyJDownloader" -and $Client.Connected -and $Client.SessionToken) {
        try { [void](Invoke-JD2MyJdRequest -Client $Client -Path "/my/disconnect" -QueryParameters ([ordered]@{ sessiontoken = $Client.SessionToken })) } catch {}
    }
    $Client.Email = $null
    $Client.DeviceId = $null
    $Client.DeviceName = $null
    $Client.Devices = @()
    $Client.LoginSecret = $null
    $Client.DeviceSecret = $null
    $Client.ServerEncryptionToken = $null
    $Client.DeviceEncryptionToken = $null
    $Client.SessionToken = $null
    $Client.RegainToken = $null
    $Client.Connected = $false
    return $true
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

    if ($Client.Mode -eq "MyJDownloader") {
        try {
            if ($Namespace -notmatch "^[A-Za-z][A-Za-z0-9_-]*$") {
                throw "Invalid JDownloader API namespace: $Namespace"
            }
            if ($Method -notmatch "^[A-Za-z][A-Za-z0-9_-]*$") {
                throw "Invalid JDownloader API method: $Method"
            }
            $remotePayload = Invoke-JD2MyJdRequest -Client $Client -Path ("/{0}/{1}" -f $Namespace, $Method) -Parameters $Parameters -DeviceRequest
            return ConvertFrom-JD2ApiResponse -Content ($remotePayload | ConvertTo-Json -Depth 100 -Compress)
        } catch {
            if ($_.Exception.Message -like "JDownloader API*") { throw }
            throw "JDownloader API request failed ($Namespace/$Method): $($_.Exception.Message)"
        }
    }

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

function Get-JD2ConfigEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [string]$ConfigInterface = "org.jdownloader.settings.GeneralSettings",
        [string]$Pattern = "downloadspeedlimit"
    )
    $query = [ordered]@{
        configInterface   = $ConfigInterface
        defaultValues     = $false
        description       = $false
        enumInfo          = $false
        includeExtensions = $false
        pattern           = $Pattern
        values            = $true
    }
    return @(Invoke-JD2ApiMethod -Client $Client -Namespace "config" -Method "query" -Parameters @($query))
}

function Set-JD2ConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][string]$InterfaceName,
        [Parameter(Mandatory)][string]$Storage,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)]$Value
    )
    if ([string]::IsNullOrWhiteSpace($InterfaceName)) { throw "JDownloader config interface cannot be empty." }
    if ([string]::IsNullOrWhiteSpace($Storage)) { throw "JDownloader config storage cannot be empty." }
    if ([string]::IsNullOrWhiteSpace($Key)) { throw "JDownloader config key cannot be empty." }
    return Invoke-JD2ApiMethod -Client $Client -Namespace "config" -Method "set" -Parameters @($InterfaceName, $Storage, $Key, $Value)
}

function Set-JD2DownloadBandwidth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][bool]$Enabled,
        [ValidateRange(1, 2147483647)][int]$LimitBytesPerSecond = 51200
    )
    $entries = @(Get-JD2ConfigEntries -Client $Client -ConfigInterface "org.jdownloader.settings.GeneralSettings" -Pattern "downloadspeedlimit")
    $enabledEntry = $entries | Where-Object { [string]$_.key -eq "downloadspeedlimitenabled" } | Select-Object -First 1
    $limitEntry = $entries | Where-Object { [string]$_.key -eq "downloadspeedlimit" } | Select-Object -First 1
    if (-not $enabledEntry -or -not $limitEntry) {
        throw "JDownloader did not expose both global bandwidth settings through its API."
    }

    [void](Set-JD2ConfigValue -Client $Client -InterfaceName ([string]$enabledEntry.interfaceName) -Storage ([string]$enabledEntry.storage) -Key ([string]$enabledEntry.key) -Value $Enabled)
    return Set-JD2ConfigValue -Client $Client -InterfaceName ([string]$limitEntry.interfaceName) -Storage ([string]$limitEntry.storage) -Key ([string]$limitEntry.key) -Value $LimitBytesPerSecond
}

function Set-JD2PerHostBandwidth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][bool]$Enabled,
        [ValidateRange(1, 2147483647)][int]$MaxDownloadsPerHost = 1
    )
    $entries = @(Get-JD2ConfigEntries -Client $Client -ConfigInterface "org.jdownloader.settings.GeneralSettings" -Pattern "perhost")
    $enabledEntry = $entries | Where-Object { [string]$_.key -eq "maxdownloadsperhostenabled" } | Select-Object -First 1
    $limitEntry = $entries | Where-Object { [string]$_.key -eq "maxsimultanedownloadsperhost" } | Select-Object -First 1
    if (-not $enabledEntry -or -not $limitEntry) {
        throw "JDownloader did not expose both per-host bandwidth settings through its API."
    }

    [void](Set-JD2ConfigValue -Client $Client -InterfaceName ([string]$enabledEntry.interfaceName) -Storage ([string]$enabledEntry.storage) -Key ([string]$enabledEntry.key) -Value $Enabled)
    return Set-JD2ConfigValue -Client $Client -InterfaceName ([string]$limitEntry.interfaceName) -Storage ([string]$limitEntry.storage) -Key ([string]$limitEntry.key) -Value $MaxDownloadsPerHost
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

function Set-JD2AccountRotation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][long[]]$Ids,
        [ValidateRange(0, 2147483647)][int]$Index = 0
    )
    $uniqueIds = @($Ids | Select-Object -Unique)
    if ($uniqueIds.Count -lt 2) { throw "At least two account ids are required for rotation." }
    $activeId = [long]$uniqueIds[$Index % $uniqueIds.Count]
    [void](Set-JD2AccountEnabled -Client $Client -Ids $uniqueIds -Enabled $false)
    [void](Set-JD2AccountEnabled -Client $Client -Ids ([long[]]@($activeId)) -Enabled $true)
    return [pscustomobject]@{ ActiveId = $activeId; Index = ($Index % $uniqueIds.Count); Count = $uniqueIds.Count }
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
    "Connect-JD2MyJDownloader",
    "Get-JD2MyJDownloaderDevices",
    "Set-JD2MyJDownloaderDevice",
    "Disconnect-JD2MyJDownloader",
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
    "Get-JD2ConfigEntries",
    "Set-JD2ConfigValue",
    "Set-JD2DownloadBandwidth",
    "Set-JD2PerHostBandwidth",
    "Get-JD2Accounts",
    "Add-JD2Account",
    "Set-JD2AccountEnabled",
    "Set-JD2AccountRotation",
    "Remove-JD2Accounts",
    "Test-JD2ApiConnection"
)
