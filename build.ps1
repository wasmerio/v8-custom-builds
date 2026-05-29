$ErrorActionPreference = "Stop"
# Make native command failures (non-zero exit code) throw terminating errors
$PSNativeCommandUseErrorActionPreference = $true

$DEPOT_TOOLS_REPO="https://chromium.googlesource.com/chromium/tools/depot_tools.git"
$V8_TAG="13.6.233.17"

# Clone depot-tools
if (-not (Test-Path -Path "depot_tools" -PathType Container)) {
  git clone --single-branch --depth=1 "$DEPOT_TOOLS_REPO" "C:\tmp\depot_tools"
}

echo "C:\tmp\depot_tools" | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
$env:Path = "C:\tmp\depot_tools;" + $env:Path

# Ensure consistent line endings so patches apply cleanly
git config --global core.autocrlf false

# Set up google's client and fetch v8
if (-not (Test-Path -Path "v8" -PathType Container)) {
  gclient
  fetch v8
}

Set-Location v8

git reset --hard
git checkout $V8_TAG
# Sync deps without hooks to avoid downloading unnecessary test data
gclient sync --with_branch_heads --with_tags --nohooks
# Run only the hooks required for building
python3 build/util/lastchange.py -o build/util/LASTCHANGE

# Apply patches (--ignore-whitespace handles CRLF differences on Windows)
$files = Get-ChildItem "../patches" -Filter *.patch
foreach ($f in $files){
  git apply --ignore-whitespace $f
}

# Write args.gn directly to avoid PowerShell quote-stripping issues
New-Item -ItemType Directory -Force -Path "out\release" | Out-Null
@'
is_debug = false
v8_symbol_level = 2
is_component_build = false
is_official_build = false
use_custom_libcxx = false
use_custom_libcxx_for_host = true
use_glib = false
v8_expose_symbols = true
v8_optimized_debug = false
v8_enable_sandbox = false
v8_enable_i18n_support = true
icu_use_data_file = false
v8_enable_gdbjit = false
v8_use_external_startup_data = false
v8_enable_pointer_compression = true
v8_enable_short_builtin_calls = true
v8_monolithic = true
treat_warnings_as_errors = false
target_cpu = "x64"
v8_target_cpu = "x64"
'@ | Set-Content -Path "out\release\args.gn" -Encoding utf8
gn gen out/release

# Showtime! (wee8 has dllimport/dllexport issues on Windows, use v8_monolith instead)
ninja -C out/release v8_monolith

Get-ChildItem -Recurse out/release/obj

# Package the output into a proper directory structure
$DIST_DIR = "out\dist"
if (Test-Path $DIST_DIR) { Remove-Item -Recurse -Force $DIST_DIR }
New-Item -ItemType Directory -Force -Path "$DIST_DIR\include"
New-Item -ItemType Directory -Force -Path "$DIST_DIR\include\wasm-c-api"
New-Item -ItemType Directory -Force -Path "$DIST_DIR\lib"

# Copy V8 public headers (preserving subdirectory structure)
Copy-Item -Recurse -Path "include\*" -Destination "$DIST_DIR\include\" -Include "*.h"
# Copy subdirectories with headers
Get-ChildItem -Path "include" -Directory | ForEach-Object {
    $dest = "$DIST_DIR\include\$($_.Name)"
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Force -Path $dest }
    Copy-Item -Recurse -Path "$($_.FullName)\*" -Destination $dest -Filter "*.h"
}

# Copy the patched wasm C API header
Copy-Item -Path "third_party\wasm-api\wasm.h" -Destination "$DIST_DIR\include\wasm-c-api\wasm.h"

# Copy the library (renamed from v8_monolith.lib to v8.lib)
Copy-Item -Path "out\release\obj\v8_monolith.lib" -Destination "$DIST_DIR\lib\v8.lib"

Write-Host "=== Distribution layout ==="
Get-ChildItem -Recurse -File $DIST_DIR | ForEach-Object { Write-Host $_.FullName }
