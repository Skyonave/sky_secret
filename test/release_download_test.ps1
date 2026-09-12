
$ErrorActionPreference = 'Stop'
& {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'windows/release-download.ps1')
    $fixture = Join-Path ([IO.Path]::GetTempPath()) ('sky-download-unit-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixture | Out-Null
    $destination = Join-Path $fixture 'tool.exe'
    $bytes = [Text.Encoding]::UTF8.GetBytes('synthetic pinned tool')
    $sha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    $pin = [pscustomobject]@{url='https://primary.invalid/tool'; fallbackUrls=@('https://fallback.invalid/tool'); sha256=$sha}
    $state = @{responses=@(); calls=@(); sleeps=0}
    function Invoke-WebRequest {
        param($Uri, $OutFile, [switch]$PassThru, $TimeoutSec, $ErrorAction)
        if (-not $PassThru -or $TimeoutSec -ne 60) { throw 'Expected bounded download with response metadata' }
        $state.calls += $Uri
        $reply = $state.responses[$state.calls.Count - 1]
        if ($reply -eq 'network') { throw [IO.IOException]::new('Synthetic network failure') }
        $content = if ($reply -eq 'valid') { $bytes } else { [Text.Encoding]::UTF8.GetBytes('<html>temporary error</html>') }
        [IO.File]::WriteAllBytes($OutFile, $content)
        return [pscustomobject]@{StatusCode=200; Headers=@{'Content-Type'='application/octet-stream'}}
    }
    function Start-Sleep { param($Seconds) $state.sleeps++ }
    function Assert-Rejected([scriptblock]$Action) {
        $failed = $false
        try { & $Action | Out-Null } catch { $failed = $true }
        if (-not $failed) { throw 'Expected rejection' }
    }
    try {
        $state.responses = @('valid')
        $result = Get-PinnedToolDownload $pin $destination
        if ($result -ne $destination -or $state.calls.Count -ne 1 -or $state.sleeps -ne 0) { throw 'Valid download should return immediately' }

        $state.calls = @(); $state.responses = @('html', 'valid')
        Get-PinnedToolDownload $pin $destination | Out-Null
        if ($state.calls.Count -ne 2 -or $state.calls[1] -ne $pin.fallbackUrls[0] -or (Get-FileHash $destination).Hash -ne $sha) { throw 'Fallback must verify the same pin' }

        $state.calls = @(); $state.responses = @('network', 'html', 'valid')
        Get-PinnedToolDownload $pin $destination | Out-Null
        if ($state.calls.Count -ne 3 -or $state.calls[2] -ne $pin.url) { throw 'Retry should revisit the primary source' }

        $state.calls = @(); $state.responses = @('html', 'html', 'html', 'html')
        Assert-Rejected { Get-PinnedToolDownload $pin $destination }
        if ($state.calls.Count -ne 4 -or (Test-Path $destination)) { throw 'Exhausted retries must leave no usable file' }

        $state.calls = @(); $state.responses = @('network', 'valid')
        $single = [pscustomobject]@{url=$pin.url; sha256=$sha}
        Get-PinnedToolDownload $single $destination | Out-Null
        if ($state.calls.Count -ne 2 -or $state.calls[1] -ne $pin.url) { throw 'Single-source pins must retry safely' }

        $state.calls = @()
        Assert-Rejected { Get-PinnedToolDownload ([pscustomobject]@{url='http://unsafe.invalid'; sha256=$sha}) $destination }
        Assert-Rejected { Get-PinnedToolDownload ([pscustomobject]@{url=$pin.url; sha256='invalid'}) $destination }
        if ($state.calls.Count) { throw 'Invalid pins must be rejected before networking' }
    } finally {
        if (Test-Path $destination) { Remove-Item -LiteralPath $destination }
        [IO.Directory]::Delete($fixture)
    }
}
Write-Output 'Pinned download unit checks passed.'
