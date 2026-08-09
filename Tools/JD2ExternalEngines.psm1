Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-JD2ExternalCommand {
    param([Parameter(Mandatory)][string]$Name, [string]$CommandPath)
    if (-not [string]::IsNullOrWhiteSpace($CommandPath)) {
        if (-not (Test-Path -LiteralPath $CommandPath -PathType Leaf)) { throw "External engine executable was not found: $CommandPath" }
        return (Resolve-Path -LiteralPath $CommandPath).Path
    }
    $command = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue
    if (-not $command) { return $null }
    return $command.Source
}

function Get-JD2ExternalEngineStatus {
    param([string]$FlareSolverrEndpoint = 'http://127.0.0.1:8191/v1')
    [pscustomobject]@{
        YtDlpPath = Resolve-JD2ExternalCommand -Name 'yt-dlp'
        Aria2Path = Resolve-JD2ExternalCommand -Name 'aria2c'
        FlareSolverrEndpoint = $FlareSolverrEndpoint
    }
}

function ConvertTo-JD2ProcessArgument {
    param([Parameter(Mandatory)][string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function New-JD2ExternalDownloadStartInfo {
    param(
        [Parameter(Mandatory)][ValidateSet('yt-dlp', 'aria2c')][string]$Engine,
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [string]$CommandPath
    )
    $uri = $null
    if (-not [Uri]::TryCreate($Url.Trim(), [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http', 'https', 'ftp', 'magnet')) { throw 'External fallback URL must be an absolute HTTP(S), FTP, or magnet URL.' }
    $commandName = if ($Engine -eq 'yt-dlp') { 'yt-dlp' } else { 'aria2c' }
    $executable = Resolve-JD2ExternalCommand -Name $commandName -CommandPath $CommandPath
    if (-not $executable) { throw "$commandName was not found on PATH. Install it or select its executable path." }
    $output = [IO.Path]::GetFullPath($OutputDirectory)
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $executable
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    if ($Engine -eq 'yt-dlp') {
        $template = Join-Path $output '%(title)s.%(ext)s'
        $psi.Arguments = '--no-progress --no-warnings --newline -o ' + (ConvertTo-JD2ProcessArgument -Value $template) + ' ' + (ConvertTo-JD2ProcessArgument -Value $Url.Trim())
    } else {
        $psi.Arguments = '--continue=true --max-connection-per-server=16 --split=16 --file-allocation=none --dir=' + (ConvertTo-JD2ProcessArgument -Value $output) + ' ' + (ConvertTo-JD2ProcessArgument -Value $Url.Trim())
    }
    return $psi
}

function Start-JD2ExternalDownload {
    param(
        [Parameter(Mandatory)][ValidateSet('yt-dlp', 'aria2c')][string]$Engine,
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [string]$CommandPath
    )
    $psi = New-JD2ExternalDownloadStartInfo -Engine $Engine -Url $Url -OutputDirectory $OutputDirectory -CommandPath $CommandPath
    return [Diagnostics.Process]::Start($psi)
}

function Invoke-JD2FlareSolverr {
    param(
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)][string]$Url,
        [int]$MaxTimeout = 120000,
        [scriptblock]$RequestHandler
    )
    $endpointUri = $null
    if (-not [Uri]::TryCreate($Endpoint.Trim(), [UriKind]::Absolute, [ref]$endpointUri) -or $endpointUri.Scheme -notin @('http', 'https')) { throw 'FlareSolverr endpoint must be an absolute HTTP(S) URL.' }
    $targetUri = $null
    if (-not [Uri]::TryCreate($Url.Trim(), [UriKind]::Absolute, [ref]$targetUri) -or $targetUri.Scheme -notin @('http', 'https')) { throw 'FlareSolverr target must be an absolute HTTP(S) URL.' }
    $payload = @{ cmd = 'request.get'; url = $targetUri.AbsoluteUri; maxTimeout = [math]::Max(1000, $MaxTimeout) } | ConvertTo-Json -Compress
    $response = if ($RequestHandler) { & $RequestHandler $endpointUri.AbsoluteUri $payload } else { Invoke-RestMethod -Uri $endpointUri.AbsoluteUri -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -ContentType 'application/json' -TimeoutSec ([math]::Max(5, [math]::Ceiling($MaxTimeout / 1000))) -ErrorAction Stop }
    if (-not $response -or [string]$response.status -ne 'ok') { throw "FlareSolverr did not solve the request: $([string]$response.message)" }
    $solution = $response.solution
    [pscustomobject]@{
        Status = [string]$response.status
        Request = if ($solution) { [string]$solution.request } else { '' }
        UserAgent = if ($solution) { [string]$solution.userAgent } else { '' }
        Cookies = if ($solution) { @($solution.cookies) } else { @() }
        Response = $response
    }
}

Export-ModuleMember -Function Get-JD2ExternalEngineStatus, New-JD2ExternalDownloadStartInfo, Start-JD2ExternalDownload, Invoke-JD2FlareSolverr
