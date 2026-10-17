$ErrorActionPreference = 'Stop'
$webDirectory = Join-Path $PSScriptRoot '../web'
# Keep this release aligned with drift in pubspec.lock. Files are bundled locally.
$release = 'https://github.com/simolus3/drift/releases/download/drift-2.35.2'
foreach ($file in @('sqlite3.wasm', 'drift_worker.js')) {
  & curl.exe -fLsS --retry 2 --max-time 120 "$release/$file" --output (Join-Path $webDirectory $file)
  if ($LASTEXITCODE -ne 0) { throw "Database asset download failed: $file" }
}
$expectedHashes = @{
  'sqlite3.wasm' = 'fbcd2e8214f9231ea961e1b7706a22dd1194cfbfe6f26f13841b5aa7a0be1a1f'
  'drift_worker.js' = '191fc9db018d2bbecb1723e81118fcf2c5c094df8644c2fcba2ed51df061e90a'
}
foreach ($file in $expectedHashes.Keys) {
  $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $webDirectory $file)).Hash
  if ($actual.ToLowerInvariant() -ne $expectedHashes[$file]) { throw "Checksum mismatch: $file" }
}
