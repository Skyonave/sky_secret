
function Get-PinnedToolDownload {
    param(
        [Parameter(Mandatory)]$Pin,
        [Parameter(Mandatory)][string]$Destination
    )
    $expected = [string]$Pin.sha256
    if ($expected -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid tool SHA-256 pin' }
    $urls = @([string]$Pin.url) + @($Pin.fallbackUrls)
    $urls = @($urls | Where-Object { $_ } | Select-Object -Unique)
    foreach ($url in $urls) {
        $uri = [uri]$url
        if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or $uri.UserInfo) {
            throw 'Tool download must use HTTPS without credentials'
        }
    }
    if ($urls.Count -eq 0) { throw 'Missing tool download URL' }

    $attempt = 0
    $limit = 2 * $urls.Count
    foreach ($round in 1..2) {
        foreach ($url in $urls) {
            $attempt++
            try {
                $response = Invoke-WebRequest -Uri $url -OutFile $Destination -PassThru -TimeoutSec 60 -ErrorAction Stop
                $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
                $length = (Get-Item -LiteralPath $Destination).Length
                if ($actual -eq $expected) { return $Destination }
                Write-Warning "Tool hash mismatch from $url (attempt $attempt/$limit): HTTP $($response.StatusCode), Content-Type $($response.Headers['Content-Type']), bytes $length; expected SHA256 $expected; received SHA256 $actual."
            } catch {

                Write-Warning "Tool download failed from $url (attempt $attempt/$limit): $($_.Exception.GetType().Name)."
            }
            if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force }
            if ($attempt -lt $limit) { Start-Sleep -Seconds 2 }
        }
    }
    throw "Unable to download pinned tool $([IO.Path]::GetFileName($Destination)) after $limit attempts. No downloaded file was accepted. Review the upstream response and release-tools.json; never replace the pin merely to bypass this check."
}
