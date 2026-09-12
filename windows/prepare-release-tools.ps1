
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release-download.ps1')
$pins = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release-tools.json') -Raw | ConvertFrom-Json
$toolsRoot = Join-Path (Split-Path $PSScriptRoot -Parent) ('build/release-tools/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $toolsRoot | Out-Null
function Get-PinnedFile($Pin, [string]$Name) {
    $path = Join-Path $toolsRoot $Name
    return Get-PinnedToolDownload -Pin $Pin -Destination $path
}
$installer = Get-PinnedFile $pins.enigma 'enigmavb.exe'
$archive = Get-PinnedFile $pins.innoextract 'innoextract.zip'
$extractorRoot = Join-Path $toolsRoot 'innoextract'
Expand-Archive -LiteralPath $archive -DestinationPath $extractorRoot
$extractors = @(Get-ChildItem -LiteralPath $extractorRoot -Recurse -Filter innoextract.exe)
if ($extractors.Count -ne 1 -or (Get-FileHash $extractors[0].FullName).Hash -ne $pins.innoextract.executableSha256) {
    throw 'Unexpected innoextract executable'
}
$enigmaRoot = Join-Path $toolsRoot 'enigma'
& $extractors[0].FullName --quiet --extract --output-dir $enigmaRoot $installer | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Enigma extraction failed' }
$packer = Join-Path $enigmaRoot 'app/enigmavbconsole.exe'
if ((Get-FileHash -LiteralPath $packer).Hash -ne $pins.enigma.executableSha256) {
    throw 'Unexpected Enigma console executable'
}
return $packer
