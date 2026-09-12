param(
    [Parameter(Mandatory = $true)][string]$BuildDirectory,
    [Parameter(Mandatory = $true)][string]$PackerPath,
    [Parameter(Mandatory = $true)][string]$CrtDirectory,
    [string]$OutputName = ''
)



$ErrorActionPreference = 'Stop'
$appRoot = Split-Path $PSScriptRoot -Parent
if (-not $OutputName) {
    . (Join-Path $PSScriptRoot 'release-metadata.ps1')
    $version = Get-ReleaseVersion (Get-Content (Join-Path $appRoot 'pubspec.yaml') -Raw)
    $OutputName = "SkySecret-$version-windows-x64.exe"
}
$buildRoot = [IO.Path]::GetFullPath((Join-Path $appRoot 'build')) + '\'
$source = (Resolve-Path -LiteralPath $BuildDirectory).Path
if (-not ($source + '\').StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'BuildDirectory must be inside application/build.'
}
if ($OutputName -notmatch '^SkySecret-[0-9A-Za-z.+-]+-windows-x64\.exe$') {
    throw 'Use an x64 release filename. Native ARM64 is not supported by this packer.'
}
$packer = (Resolve-Path -LiteralPath $PackerPath).Path
$crt = (Resolve-Path -LiteralPath $CrtDirectory).Path
$inputExe = Join-Path $source 'SkySecret.exe'
foreach ($required in @('SkySecret.exe', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets')) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $required))) { throw "Missing release component: $required" }
}
foreach ($required in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $crt $required))) { throw "Missing VC runtime: $required" }
}

function Assert-X64([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5a4d) { throw "Not a PE image: $Path" }
        $stream.Position = 0x3c
        $offset = $reader.ReadUInt32()
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) {
            throw "Expected an x64 PE image: $Path"
        }
    } finally { $reader.Dispose() }
}
function Escape-Xml([string]$Value) { [Security.SecurityElement]::Escape($Value) }
function File-Xml([IO.FileInfo]$Item) {
    if ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse points cannot be packaged.' }
    if ($Item.Extension -in @('.smv', '.dpapi', '.lock', '.pem', '.key') -or $Item.Name -like '.env*') {
        throw 'User data or credentials found in the release directory.'
    }
    if ($Item.Extension -in @('.dll', '.exe')) { Assert-X64 $Item.FullName }
    $script:packedCount++
    '<File><Type>2</Type><Name>' + (Escape-Xml $Item.Name) + '</Name><File>' +
        (Escape-Xml $Item.FullName) + '</File><ActiveX>false</ActiveX><ActiveXInstall>false</ActiveXInstall>' +
        '<Action>0</Action><OverwriteDateTime>false</OverwriteDateTime><OverwriteAttributes>false</OverwriteAttributes>' +
        '<PassCommandLine>false</PassCommandLine></File>'
}
function Directory-Xml([string]$Path) {
    $parts = foreach ($item in Get-ChildItem -LiteralPath $Path -Force | Sort-Object Name) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse points cannot be packaged.' }
        if ($item.PSIsContainer) {
            '<File><Type>3</Type><Name>' + (Escape-Xml $item.Name) + '</Name><Action>0</Action>' +
                '<OverwriteDateTime>false</OverwriteDateTime><OverwriteAttributes>false</OverwriteAttributes><Files>' +
                (Directory-Xml $item.FullName) + '</Files></File>'
        } elseif ($item.FullName -ne $inputExe -and $item.Extension -ne '.pdb') {
            File-Xml $item
        }
    }
    $parts -join "`r`n"
}

Assert-X64 $inputExe
$outputDir = Join-Path $appRoot 'build/portable'
$workDir = Join-Path $appRoot 'build/packaging'
New-Item -ItemType Directory -Force $outputDir, $workDir | Out-Null
$output = Join-Path $outputDir $OutputName
if (Test-Path -LiteralPath $output) { throw "Output already exists: $output" }
$runId = [Guid]::NewGuid().ToString('N')
$temporaryOutput = Join-Path $workDir "$runId.exe"
$projectFile = Join-Path $workDir "$runId.evb"
$script:packedCount = 0
$files = Directory-Xml $source
foreach ($item in Get-ChildItem -LiteralPath $crt -Filter '*.dll' | Sort-Object Name) {
    if (Test-Path -LiteralPath (Join-Path $source $item.Name)) {
        if ((Get-FileHash -LiteralPath (Join-Path $source $item.Name)).Hash -ne (Get-FileHash -LiteralPath $item.FullName).Hash) {
            throw "Conflicting runtime DLL: $($item.Name)"
        }
    } else { $files += File-Xml $item }
}
$project = @"
<?xml encoding="utf-16"?>
<>
<InputFile>$(Escape-Xml $inputExe)</InputFile>
<OutputFile>$(Escape-Xml $temporaryOutput)</OutputFile>
<Files><Enabled>true</Enabled><DeleteExtractedOnExit>false</DeleteExtractedOnExit><CompressFiles>true</CompressFiles>
<Files><File><Type>3</Type><Name>%DEFAULT FOLDER%</Name><Action>0</Action>
<OverwriteDateTime>false</OverwriteDateTime><OverwriteAttributes>false</OverwriteAttributes><Files>$files</Files></File></Files></Files>
<Registries><Enabled>false</Enabled></Registries><Packaging><Enabled>false</Enabled></Packaging>
<Options><ShareVirtualSystem>false</ShareVirtualSystem><MapExecutableWithTemporaryFile>false</MapExecutableWithTemporaryFile>
<AllowRunningOfVirtualExeFiles>false</AllowRunningOfVirtualExeFiles></Options>
</>
"@
[IO.File]::WriteAllText($projectFile, $project, [Text.Encoding]::Unicode)
& $packer $projectFile
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $temporaryOutput)) { throw 'Packing failed.' }
Assert-X64 $temporaryOutput

[IO.File]::Move($temporaryOutput, $output)
$hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output "Packed $script:packedCount files into $output"
Write-Output "SHA256: $hash"
Write-Output "Project: $projectFile"
Write-Output 'Runtime acceptance is pending. Packaging success alone does not verify Flutter compatibility.'
