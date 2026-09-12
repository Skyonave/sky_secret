
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'windows/release-metadata.ps1')
function Assert-Throws([scriptblock]$Action) {
    $thrown = $false
    try { & $Action | Out-Null } catch { $thrown = $true }
    if (-not $thrown) { throw 'Expected invalid release metadata to be rejected' }
}
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('sky-verification-unit-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$metadata = Join-Path $fixture 'metadata'
$release = Join-Path $fixture 'release'
New-Item -ItemType Directory -Path $metadata, $release | Out-Null
try {
    $exe = Join-Path $release 'SkySecret-1.2.3-windows-x64.exe'
    [IO.File]::WriteAllText($exe, 'Synthetic executable; never launched')
    [IO.File]::WriteAllText((Join-Path $metadata 'build-manifest.json'), '{"version":"1.2.3"}')
    [IO.File]::WriteAllText((Join-Path $metadata 'pubspec.lock'), 'synthetic')
    $destination = Join-Path $release 'verification.zip'
    New-VerificationArchive $exe $metadata $destination
    $files = @(Get-ChildItem -LiteralPath $release -File)
    if (@(Compare-Object ($files.Name | Sort-Object) @('SkySecret-1.2.3-windows-x64.exe', 'verification.zip')).Count) { throw 'Expected exactly two public downloads' }
    $archive = [IO.Compression.ZipFile]::OpenRead($destination)
    try {
        $names = @($archive.Entries.FullName | Sort-Object)
        if (@(Compare-Object $names @('build-manifest.json', 'pubspec.lock', 'SHA256SUMS.txt')).Count) { throw 'Unexpected verification contents' }
        $reader = [IO.StreamReader]::new($archive.GetEntry('SHA256SUMS.txt').Open())
        try { $checksums = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $expectedHash = (Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($exe)
        if (($checksums -split '\r?\n') -cnotcontains $expectedHash) { throw 'EXE checksum is missing or incorrect' }
    } finally { $archive.Dispose() }
    $archiveHash = (Get-FileHash -LiteralPath $destination).Hash
    Assert-Throws { New-VerificationArchive $exe $metadata $destination }
    if ((Get-FileHash -LiteralPath $destination).Hash -ne $archiveHash) { throw 'Existing archive was changed' }
} finally {
    foreach ($directory in @($metadata, $release)) {
        Get-ChildItem -LiteralPath $directory -File | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
        [IO.Directory]::Delete($directory)
    }
    [IO.Directory]::Delete($fixture)
}
if ((Get-ReleaseVersion "name: demo`nversion: 1.2.3+4`n" 'v1.2.3') -cne '1.2.3') { throw 'Version mismatch' }
if ((Get-ReleaseVersion 'version: 1.2.3-rc.1+4' 'v1.2.3-rc.1') -cne '1.2.3-rc.1') { throw 'Prerelease mismatch' }
Assert-Throws { Get-ReleaseVersion 'version: 1.2.3+4' 'v1.2.4' }
Assert-Throws { Get-ReleaseVersion 'version: 1.2.3+4' '../../unsafe' }
Assert-Throws { Get-ReleaseVersion 'version: unknown' }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('sky-release-unit-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    [IO.File]::WriteAllText((Join-Path $temporary 'sample.txt'), 'synthetic')
    Write-ReleaseChecksums $temporary
    $checksum = Get-Content -LiteralPath (Join-Path $temporary 'SHA256SUMS.txt')
    $expected = (Get-FileHash (Join-Path $temporary 'sample.txt')).Hash.ToLowerInvariant() + '  sample.txt'
    if ($checksum -cne $expected) { throw 'Checksum mismatch' }
    Write-ReleaseChecksums $temporary
    if (@(Get-Content (Join-Path $temporary 'SHA256SUMS.txt')).Count -ne 1) { throw 'Checksums must not include themselves' }
    $source = Join-Path $temporary 'input'
    New-Item -ItemType Directory $source | Out-Null
    foreach ($name in @('SkySecret.exe', 'current.dll', 'stale.exe')) { [IO.File]::WriteAllText((Join-Path $source $name), 'synthetic') }
    $manifest = Join-Path $temporary 'install_manifest.txt'
    [IO.File]::WriteAllText($manifest, (Join-Path $source 'current.dll'))
    $inputs = @(Get-ReleaseInputFiles $source $manifest)
    if ($inputs.Count -ne 2 -or $inputs.Name -contains 'stale.exe') { throw 'Stale build files must be excluded' }
    [IO.File]::WriteAllText($manifest, (Join-Path $temporary 'sample.txt'))
    Assert-Throws { Get-ReleaseInputFiles $source $manifest }
    [IO.File]::WriteAllText($manifest, (Join-Path $source 'stale.exe'))
    Assert-Throws { Get-ReleaseInputFiles $source $manifest }
} finally {
    foreach ($name in @('SkySecret.exe', 'current.dll', 'stale.exe')) {
        Remove-Item -LiteralPath (Join-Path $temporary "input/$name") -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath (Join-Path $temporary 'input')) { [IO.Directory]::Delete((Join-Path $temporary 'input')) }
    Remove-Item -LiteralPath (Join-Path $temporary 'install_manifest.txt') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $temporary 'sample.txt'), (Join-Path $temporary 'SHA256SUMS.txt') -Force -ErrorAction SilentlyContinue
    [IO.Directory]::Delete($temporary)
}
