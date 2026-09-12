
function New-VerificationArchive([string]$Executable, [string]$MetadataDirectory, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) { throw 'Verification archive already exists' }
    $files = @(Get-ChildItem -LiteralPath $MetadataDirectory -Force)
    if ($files.Count -eq 0) { throw 'No build information to archive' }
    foreach ($file in $files) {
        if ($file.PSIsContainer -or $file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Unexpected verification input' }
        if ($file.Name -ceq 'SHA256SUMS.txt' -or $file.Extension -notin @('.json', '.lock')) { throw 'Unexpected verification file' }
    }
    $exe = Get-Item -LiteralPath $Executable
    if ($exe.Extension -ne '.exe' -or $exe.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Expected a regular EXE' }
    $checksums = @(@($exe) + $files | Sort-Object Name | ForEach-Object {
        (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $_.Name
    })
    [IO.File]::WriteAllLines((Join-Path $MetadataDirectory 'SHA256SUMS.txt'), $checksums, [Text.UTF8Encoding]::new($false))
    $archive = [IO.Compression.ZipFile]::Open($Destination, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in Get-ChildItem -LiteralPath $MetadataDirectory -File | Sort-Object Name) {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $file.Name, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally { $archive.Dispose() }
}

function Get-ReleaseInputFiles([string]$Source, [string]$InstallManifest) {
    $root = [IO.Path]::GetFullPath($Source).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    $paths = @((Join-Path $root 'SkySecret.exe')) + @(Get-Content -LiteralPath $InstallManifest | Where-Object { $_.Trim() })
    foreach ($path in ($paths | Sort-Object -Unique)) {
        $absolute = [IO.Path]::GetFullPath($path)
        if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Install manifest points outside the selected build' }
        $item = Get-Item -LiteralPath $absolute -Force
        if ($item.PSIsContainer -or $item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Invalid installed file' }
        $parent = $item.Directory
        while ($parent.FullName.Length -ge $root.Length) {
            if ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse point in installed file path' }
            $parent = $parent.Parent
        }
        if ($item.Extension -eq '.exe' -and $item.Name -cne 'SkySecret.exe') { throw 'Unexpected executable in install manifest' }
        if ($item.Extension -ne '.pdb') { $item }
    }
}

function Get-ReleaseVersion([string]$Pubspec, [string]$Tag = '') {
    $match = [regex]::Match($Pubspec, '(?m)^version:\s*(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)(?:\+(\d+))?\s*$')
    if (-not $match.Success) { throw 'Unsupported pubspec version' }
    $version = $match.Groups[1].Value
    if ($Tag -and $Tag -cne "v$version") { throw 'Release tag must match pubspec.yaml version' }
    return $version
}

function Write-ReleaseChecksums([string]$Directory) {
    $lines = @(Get-ChildItem -LiteralPath $Directory -File | Where-Object Name -ne 'SHA256SUMS.txt' |
        Sort-Object Name | ForEach-Object {
            (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $_.Name
        })
    if (-not $lines.Count) { throw 'No release assets to hash' }
    [IO.File]::WriteAllLines((Join-Path $Directory 'SHA256SUMS.txt'), $lines, [Text.UTF8Encoding]::new($false))
}
