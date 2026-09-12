$ErrorActionPreference = 'Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {

    $unitFiles = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*_test.dart' |
        Where-Object { -not (Select-String -LiteralPath $_.FullName -Pattern '\btestWidgets\s*\(' -Quiet) } |
        Sort-Object Name | ForEach-Object { 'test/' + $_.Name })
    if ($unitFiles.Count -eq 0) { throw 'No unit tests found' }
    & flutter test --no-pub --concurrency=1 --timeout=3m --fail-fast --reporter=expanded @unitFiles
    if ($LASTEXITCODE -ne 0) { throw 'Unit tests failed' }
} finally {
    Pop-Location
}
