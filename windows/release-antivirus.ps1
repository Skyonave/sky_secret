param(
    [string[]]$Paths = @(),
    [string]$ReportDirectory = 'build/antivirus',
    [switch]$UpdateSignatures
)

$ErrorActionPreference = 'Stop'

function Get-AntivirusVerdict([int]$ExitCode, [string]$Output, [string]$Target) {
    $confirmation = "Scanning $Target found no threats."
    if ($Output -match '(?im)^\s*(Threat\b|Error\b|CmdTool: Failed)') { return 'failed' }
    if ($ExitCode -eq 0 -and ($Output -split '\r?\n').Trim() -ccontains $confirmation) { return 'passed' }
    return 'failed'
}

function Get-DefenderScanner {
    $platform = Join-Path $env:ProgramData 'Microsoft/Windows Defender/Platform'
    $scanner = @(Get-ChildItem -LiteralPath $platform -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'MpCmdRun.exe' } |
        Where-Object { Test-Path -LiteralPath $_ }) | Select-Object -First 1
    if (-not $scanner) { $scanner = Join-Path $env:ProgramFiles 'Windows Defender/MpCmdRun.exe' }
    return (Resolve-Path -LiteralPath $scanner).Path
}

function Get-AntivirusInventory([string]$Path) {
    $root = Get-Item -LiteralPath $Path -Force
    if ($root.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Cannot scan a reparse point' }
    $items = if ($root.PSIsContainer) { @(Get-ChildItem -LiteralPath $root.FullName -Recurse -Force) } else { @($root) }
    if (@($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) {
        throw 'Cannot scan a directory containing reparse points'
    }
    $files = @($items | Where-Object { -not $_.PSIsContainer } | Sort-Object FullName)
    if ($files.Count -eq 0) { throw 'Cannot accept an empty scan target' }
    foreach ($file in $files) {
        [ordered]@{
            path = if ($root.PSIsContainer) { [IO.Path]::GetRelativePath($root.FullName, $file.FullName) } else { $file.Name }
            bytes = $file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
}

function Invoke-DefenderCommand([string]$Scanner, [string[]]$Arguments, [int]$TimeoutSeconds = 300) {
    $start = [Diagnostics.ProcessStartInfo]::new($Scanner)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'Defender process did not start' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw "Defender command exceeded $TimeoutSeconds seconds"
        }
        [pscustomobject]@{ exitCode = $process.ExitCode; output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult() }
    } finally { $process.Dispose() }
}

function Invoke-ReleaseAntivirus([string[]]$Targets, [string]$Destination, [bool]$Refresh) {
    $destinationPath = [IO.Path]::GetFullPath($Destination)
    foreach ($target in $Targets) {
        $absolute = [IO.Path]::GetFullPath($target).TrimEnd('\')
        if ($destinationPath -eq $absolute -or $destinationPath.StartsWith($absolute + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Scan reports must be outside the scan targets'
        }
    }
    New-Item -ItemType Directory -Force -Path $destinationPath | Out-Null
    $reportPath = Join-Path $destinationPath 'report.json'
    if (Test-Path -LiteralPath $reportPath) { throw 'Use a new report directory for each scan' }
    $report = [ordered]@{
        schema = 1; startedUtc = [DateTime]::UtcNow.ToString('o'); status = 'failed'
        sourceCommit = $env:GITHUB_SHA; runId = $env:GITHUB_RUN_ID; runAttempt = $env:GITHUB_RUN_ATTEMPT
        scope = 'Custom static scan, exclusions ignored; no application execution. Not a browser download or runtime verdict.'
        scanner = $null; defender = $null; preferences = $null; results = @(); error = $null
    }
    try {
        if ($Targets.Count -eq 0) { throw 'At least one explicit scan target is required' }
        $scanner = Get-DefenderScanner
        $report.scanner = $scanner
        if ($Refresh) {
            $update = Invoke-DefenderCommand $scanner @('-SignatureUpdate')
            $update.output | Set-Content -LiteralPath (Join-Path $destinationPath 'signature-update.log') -Encoding utf8NoBOM
            if ($update.exitCode -ne 0) { throw 'Defender signature update failed' }
        }
        $status = Get-MpComputerStatus -ErrorAction Stop
        $report.defender = $status | Select-Object AMProductVersion, AMEngineVersion, AMServiceEnabled, AMRunningMode,
            AntivirusEnabled, AntivirusSignatureVersion, AntivirusSignatureLastUpdated, RealTimeProtectionEnabled
        $report.preferences = Get-MpPreference -ErrorAction Stop | Select-Object DisableArchiveScanning,
            DisableRealtimeMonitoring, DisableIOAVProtection, MAPSReporting, SubmitSamplesConsent
        if (-not $status.AMServiceEnabled -or -not $status.AntivirusEnabled) { throw 'Defender antivirus is unavailable' }
        if (-not $status.AntivirusSignatureLastUpdated -or
            $status.AntivirusSignatureLastUpdated.ToUniversalTime() -lt [DateTime]::UtcNow.AddDays(-2)) {
            throw 'Defender signatures are missing or older than two days'
        }
        $index = 0
        foreach ($target in $Targets) {
            $index++
            $result = [ordered]@{ target = $target; status = 'failed'; exitCode = $null; before = @(); after = @(); error = $null }
            try {
                $resolved = (Resolve-Path -LiteralPath $target).Path
                $result.target = $resolved
                $result.before = @(Get-AntivirusInventory $resolved)
                $scan = Invoke-DefenderCommand $scanner @('-Scan', '-ScanType', '3', '-File', $resolved, '-DisableRemediation')
                $result.exitCode = $scan.exitCode
                $scan.output | Set-Content -LiteralPath (Join-Path $destinationPath "scan-$index.log") -Encoding utf8NoBOM
                Write-Host $scan.output
                $result.after = @(Get-AntivirusInventory $resolved)
                if (($result.before | ConvertTo-Json -Depth 5 -Compress) -cne ($result.after | ConvertTo-Json -Depth 5 -Compress)) {
                    throw 'Scan target changed or lost files during scanning'
                }
                $result.status = Get-AntivirusVerdict $scan.exitCode $scan.output $resolved
            } catch { $result.error = $_.Exception.Message }
            $report.results += $result
        }
        if (@($report.results | Where-Object status -ne 'passed').Count -gt 0) {
            throw 'Antivirus gate failed: detection, scan error or missing clean confirmation. See scan logs.'
        }
        $report.status = 'passed'
    } catch {
        $report.error = $_.Exception.Message
        throw
    } finally {
        $report['finishedUtc'] = [DateTime]::UtcNow.ToString('o')
        $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-ReleaseAntivirus $Paths $ReportDirectory $UpdateSignatures.IsPresent
}
