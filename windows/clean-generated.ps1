$ErrorActionPreference = 'Stop'
$appRoot = Split-Path $PSScriptRoot -Parent
Push-Location $appRoot
try {
    $translations = @(Get-ChildItem lib/i18n -Filter 'translations*.g.dart' | ForEach-Object FullName)
    if ($translations.Count) {
        & dart run windows/clean_dart_comments.dart @translations
        if ($LASTEXITCODE -ne 0) { throw 'Generated Dart cleanup failed' }
        & dart format @translations
        if ($LASTEXITCODE -ne 0) { throw 'Generated Dart formatting failed' }
    }
    foreach ($path in @('pubspec.lock', 'windows/flutter/generated_plugin_registrant.cc', 'windows/flutter/generated_plugin_registrant.h', 'windows/flutter/generated_plugins.cmake')) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $source = Get-Content -LiteralPath $path -Raw
        $pattern = if ($path.EndsWith('.lock') -or $path.EndsWith('.cmake')) { '(?m)^[\t ]*#[^\r\n]*\r?\n' } else { '(?m)^[\t ]*//[^\r\n]*\r?\n' }
        $cleaned = [regex]::Replace($source, $pattern, '')
        $cleaned = [regex]::Replace($cleaned, '(?m)(#endif)[\t ]+//[^\r\n]*', '$1')
        $cleaned = $cleaned.TrimStart()
        if ($cleaned -cne $source) { [IO.File]::WriteAllText((Join-Path $appRoot $path), $cleaned, [Text.UTF8Encoding]::new($false)) }
    }
} finally { Pop-Location }
