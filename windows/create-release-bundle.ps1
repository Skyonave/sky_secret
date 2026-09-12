param(
    [string]$Tag = '',
    [string]$BuildDirectory = 'build/windows/x64/runner/Release',
    [string]$OutputDirectory = 'build/release-bundle',
    [string]$PackerPath,
    [string]$CrtDirectory
)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7 or newer is required' }
. (Join-Path $PSScriptRoot 'release-metadata.ps1')
$appRoot = Split-Path $PSScriptRoot -Parent
Push-Location $appRoot
try {
    & (Join-Path $PSScriptRoot 'clean-generated.ps1')
    $version = Get-ReleaseVersion (Get-Content pubspec.yaml -Raw) $Tag
    $commit = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify source commit' }
    $sourceDirty = @(git status --porcelain --untracked-files=normal).Count -gt 0
    if ($LASTEXITCODE -ne 0) { throw 'Cannot check source status' }
    if ($env:GITHUB_ACTIONS -eq 'true' -and $sourceDirty) { throw 'CI source tree changed during the build' }
    if ($Tag -and $env:GITHUB_REF -cne "refs/tags/$Tag") { throw 'Release build must run from its tag' }
    $source = (Resolve-Path -LiteralPath $BuildDirectory).Path
    $buildRoot = [IO.Path]::GetFullPath((Join-Path $appRoot 'build')) + [IO.Path]::DirectorySeparatorChar
    if (-not ($source + [IO.Path]::DirectorySeparatorChar).StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'BuildDirectory must be inside application/build'
    }
    $output = [IO.Path]::GetFullPath((Join-Path $appRoot $OutputDirectory))
    if (-not $output.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'OutputDirectory must be inside application/build' }
    if (Test-Path -LiteralPath $output) { throw 'Release bundle already exists; use a fresh build workspace' }
    if (-not $PackerPath) { $PackerPath = & (Join-Path $PSScriptRoot 'prepare-release-tools.ps1') }
    $pins = Get-Content windows/release-tools.json -Raw | ConvertFrom-Json
    if ((Get-FileHash -LiteralPath $PackerPath).Hash -ne $pins.enigma.executableSha256) { throw 'Packer hash mismatch' }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $visualStudio) { throw 'Visual Studio C++ tools not found' }
    if (-not $CrtDirectory) {
        $redistRoot = Join-Path $visualStudio[0].installationPath 'VC/Redist/MSVC'
        $redist = Get-ChildItem -LiteralPath $redistRoot -Directory |
            Where-Object Name -match '^\d+\.\d+\.\d+$' | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
        $crt = @(Get-ChildItem -Path (Join-Path $redist.FullName 'x64/Microsoft.VC*.CRT') -Directory)
        if ($crt.Count -ne 1) { throw 'Cannot identify one x64 VC runtime directory' }
        $CrtDirectory = $crt[0].FullName
    }
    $staging = Join-Path $appRoot ('build/release-input-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $staging, $output | Out-Null

    foreach ($item in Get-ReleaseInputFiles $source 'build/windows/x64/install_manifest.txt') {
        $relative = [IO.Path]::GetRelativePath($source, $item.FullName)
        $target = Join-Path $staging $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        Copy-Item -LiteralPath $item.FullName -Destination $target
    }
    foreach ($dll in Get-ChildItem -LiteralPath $CrtDirectory -Filter '*.dll') {
        $target = Join-Path $staging $dll.Name
        if ((Test-Path -LiteralPath $target) -and (Get-FileHash $target).Hash -ne (Get-FileHash $dll.FullName).Hash) {
            throw 'Conflicting VC runtime in build'
        }
        Copy-Item -LiteralPath $dll.FullName -Destination $target
    }

    $stem = "SkySecret-$version-windows-x64"

    $packedName = "SkySecret-$version-ci-$([guid]::NewGuid().ToString('N'))-windows-x64.exe"
    & (Join-Path $PSScriptRoot 'package-portable.ps1') -BuildDirectory $staging -PackerPath $PackerPath -CrtDirectory $CrtDirectory -OutputName $packedName | Out-Host
    Copy-Item -LiteralPath (Join-Path $appRoot "build/portable/$packedName") -Destination (Join-Path $output "$stem.exe")
    $metadata = Join-Path $appRoot ('build/verification-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $metadata | Out-Null
    $inventory = @(Get-ChildItem -LiteralPath $staging -Recurse -File | Sort-Object FullName | ForEach-Object {
        [ordered]@{ path = [IO.Path]::GetRelativePath($staging, $_.FullName).Replace('\', '/'); bytes = $_.Length; sha256 = (Get-FileHash $_.FullName).Hash.ToLowerInvariant() }
    })
    $flutter = & flutter --version --machine | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'Cannot record Flutter version' }
    $dependencies = & flutter pub deps --json
    if ($LASTEXITCODE -ne 0) { throw 'Cannot record dependency inventory' }
    $dependencies | Set-Content -LiteralPath (Join-Path $metadata 'dependencies.json') -Encoding utf8NoBOM
    Copy-Item -LiteralPath pubspec.lock -Destination $metadata
    $runUrl = if ($env:GITHUB_RUN_ID) { "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID" } else { $null }
    $manifest = [ordered]@{
        version = $version; sourceCommit = $commit; sourceDirty = $sourceDirty; sourceTag = $Tag; workflowRun = $runUrl
        runAttempt = $env:GITHUB_RUN_ATTEMPT; runnerImage = $env:ImageOS; runnerImageVersion = $env:ImageVersion
        flutter = $flutter; visualStudio = @($visualStudio | Select-Object installationVersion, catalog)
        cmakeConfiguration = @(Get-Content build/windows/x64/CMakeCache.txt | Where-Object { $_ -match '^(CMAKE_(CXX_COMPILER|VS_WINDOWS_TARGET_PLATFORM_VERSION)|CMAKE_GENERATOR|CMAKE_VS_PLATFORM_TOOLSET)' })
        pubspecLockSha256 = (Get-FileHash pubspec.lock).Hash.ToLowerInvariant(); packagingTools = $pins
        unpackedFiles = $inventory
        guarantees = 'Build information and file hashes; not a signature, security audit or claim of bit-for-bit reproducibility or runtime acceptance.'
    }
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $metadata 'build-manifest.json') -Encoding utf8NoBOM
    New-VerificationArchive -Executable (Join-Path $output "$stem.exe") -MetadataDirectory $metadata -Destination (Join-Path $output 'verification.zip')
    Write-Output "Release bundle: $output"
} finally { Pop-Location }
