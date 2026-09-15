param([string]$BuildDirectory = '')

$ErrorActionPreference = 'Stop'
if (-not $BuildDirectory) { $BuildDirectory = Join-Path $PSScriptRoot '../build/windows/x64' }
$buildRoot = (Resolve-Path -LiteralPath $BuildDirectory).Path
$cache = Get-Content -LiteralPath (Join-Path $buildRoot 'CMakeCache.txt')
$command = @($cache | Where-Object { $_.StartsWith('CMAKE_COMMAND:INTERNAL=') })
if ($command.Count -ne 1) { throw 'Build Windows before running native unit tests' }
$cmake = $command[0].Substring('CMAKE_COMMAND:INTERNAL='.Length)
& $cmake --build $buildRoot --config Release --target desktop_window_focus_test desktop_window_focus_baseline window_layout_test window_layout_baseline companion_window_test
if ($LASTEXITCODE -ne 0) { throw 'Native unit build failed' }

$previousPath = $env:PATH
try {
    $runtime = Join-Path $buildRoot 'runner/Release'
    $env:PATH = "$runtime;$env:PATH"
    & (Join-Path $runtime 'companion_window_test.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Companion movement regression failed' }
    $baseline = Join-Path $buildRoot 'Release/desktop_window_focus_baseline.exe'
    & $baseline
    if ($LASTEXITCODE -ne 1) { throw 'Original hidden-window focus failure was not reproduced' }
    & $baseline --activation
    if ($LASTEXITCODE -ne 2) { throw 'Original inactive-window focus failure was not reproduced' }
    $fixed = Join-Path $buildRoot 'Release/desktop_window_focus_test.exe'
    & $fixed
    if ($LASTEXITCODE -ne 0) { throw 'Native focus regression failed' }
    & $fixed --activation
    if ($LASTEXITCODE -ne 0) { throw 'Native activation regression failed' }
    foreach ($mode in @('', '--frame')) {
        $layoutBaseline = Join-Path $buildRoot 'Release/window_layout_baseline.exe'
        & $layoutBaseline $mode
        if ($LASTEXITCODE -ne 1) { throw 'Original layout activation failure was not reproduced' }
        $layoutFixed = Join-Path $buildRoot 'Release/window_layout_test.exe'
        & $layoutFixed $mode
        if ($LASTEXITCODE -ne 0) { throw 'Window layout focus regression failed' }
    }
} finally {
    $env:PATH = $previousPath
}
