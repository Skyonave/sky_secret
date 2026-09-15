$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'windows/release-antivirus.ps1')
$target = 'C:\synthetic\SkySecret.exe'
$clean = "Scan starting...`nScan finished.`nScanning $target found no threats."
if ((Get-AntivirusVerdict 0 $clean $target) -ne 'passed') { throw 'Clean scan rejected' }
foreach ($case in @(
    @{code=2; text=$clean},
    @{code=0; text=''},
    @{code=0; text='Scan finished.'},
    @{code=0; text='Threat detected and remediated'},
    @{code=0; text="Threat detected`n$clean"},
    @{code=0; text='Scanning C:\different.exe found no threats.'},
    @{code=2; text='Trojan:Win32/Wacatac.B!ml'},
    @{code=-2147024891; text='Access denied'}
)) {
    if ((Get-AntivirusVerdict $case.code $case.text $target) -ne 'failed') { throw 'Unsafe scan accepted' }
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('sky-antivirus-unit-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$sample = Join-Path $fixture 'sample.txt'
try {
    $emptyRejected = $false
    try { Get-AntivirusInventory $fixture | Out-Null } catch { $emptyRejected = $true }
    if (-not $emptyRejected) { throw 'Empty directory accepted' }
    [IO.File]::WriteAllText($sample, 'Synthetic sample, no executable content')
    $before = @(Get-AntivirusInventory $fixture)
    if ($before.Count -ne 1 -or $before[0].path -ne 'sample.txt') { throw 'Incorrect inventory' }
    [IO.File]::WriteAllText($sample, 'Modified synthetic sample')
    $after = @(Get-AntivirusInventory $fixture)
    if ($before[0].sha256 -eq $after[0].sha256) { throw 'Mutation not detected' }
    $nestedRejected = $false
    try { Invoke-ReleaseAntivirus @($fixture) (Join-Path $fixture 'reports') $false } catch { $nestedRejected = $true }
    if (-not $nestedRejected) { throw 'Report inside scan target accepted' }

    & {
        $state = @{mode='clean'; calls=0}
        function Get-DefenderScanner { return 'Synthetic scanner, never executed' }
        function Get-MpComputerStatus {
            [pscustomobject]@{
                AMServiceEnabled = $state.mode -ne 'unavailable'; AntivirusEnabled = $true
                AntivirusSignatureLastUpdated = if ($state.mode -eq 'stale') { [DateTime]::UtcNow.AddDays(-3) } else { [DateTime]::UtcNow }
            }
        }
        function Get-MpPreference { [pscustomobject]@{SubmitSamplesConsent=2} }
        function Invoke-DefenderCommand {
            param($Scanner, $Arguments, $TimeoutSeconds)
            $state.calls++
            $scanTarget = $Arguments[4]
            if ($Arguments[-1] -ne '-DisableRemediation') { throw 'Exclusion-independent scan required' }
            if ($state.mode -eq 'timeout') { throw 'Synthetic timeout' }
            if ($state.mode -eq 'mutated') { [IO.File]::AppendAllText($scanTarget, 'changed') }
            if ($state.mode -eq 'detected') { return [pscustomobject]@{exitCode=2; output='Threat : Trojan:Win32/Wacatac.B!ml'} }
            [pscustomobject]@{exitCode=0; output="Scanning $scanTarget found no threats."}
        }
        foreach ($mode in @('clean', 'detected', 'timeout', 'mutated', 'unavailable', 'stale')) {
            $state.mode = $mode
            $state.calls = 0
            $destination = Join-Path $fixture $mode
            $rejected = $false
            try { Invoke-ReleaseAntivirus @($sample) $destination $false } catch { $rejected = $true }
            $report = Get-Content (Join-Path $destination 'report.json') -Raw | ConvertFrom-Json
            if ($mode -eq 'clean') {
                if ($rejected -or $report.status -ne 'passed' -or $report.results.Count -ne 1) { throw 'Clean scan failed' }
            } elseif (-not $rejected -or $report.status -ne 'failed') { throw "Unsafe result accepted: $mode" }
            if ($mode -in @('unavailable', 'stale') -and $state.calls -ne 0) { throw 'Scan started with unavailable protection' }
            foreach ($file in Get-ChildItem -LiteralPath $destination -File) { Remove-Item -LiteralPath $file.FullName }
            [IO.Directory]::Delete($destination)
        }
    }
} finally {
    if (Test-Path -LiteralPath $sample) { Remove-Item -LiteralPath $sample }
    [IO.Directory]::Delete($fixture)
}
Write-Output 'Release antivirus unit checks passed.'
