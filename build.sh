#!/bin/bash

# Display all commands before executing them.
set -o errexit
set -o errtrace
set -x

DEPOT_TOOLS_REPO="https://chromium.googlesource.com/chromium/tools/depot_tools.git"
DEPOT_TOOLS_DIR="/tmp/depot_tools"

V8_TAG=${V8_TAG:-"15.9.111"}

if [ -z "$1" ]; then 
  case $(uname -m) in
	"x86_64")
	  ARCH="x64"
      ;;
	"aarch64"|"arm64")
	  ARCH="arm64"
      ;;
  
	*)
	  ARCH=$(uname -m)
      ;;
  esac
else 
  ARCH=$1
fi

if [ -z "$2" ]; then 
  case $(uname -s) in
	"Darwin")
	  OS="mac"
	  ;;
	"Linux")
	  OS="linux"
	  ;;
	*)
	  OS=$(uname -s)
  esac
else 
  OS=$2
fi

USE_SYSROOT=false
USE_CUSTOM_LIBCXX=false
IS_CLANG=false
if [ "$OS" = "linux" ] || [ "$OS" = "mac" ]; then
  IS_CLANG=true
fi
if [ "$OS" = "linux" ] && [ "$ARCH" = "arm64" ]; then
  # Use Chromium's bundled Clang cross-compiler and Debian sysroots rather
  # than a native ARM64 system compiler. Bullseye's libstdc++ lacks the
  # C++20 headers V8 needs, so use bundled libc++ for target and host tools.
  USE_SYSROOT=true
  USE_CUSTOM_LIBCXX=true
fi

if [ ! -d "$DEPOT_TOOLS_DIR" ]
then 
  git clone "$DEPOT_TOOLS_REPO" "$DEPOT_TOOLS_DIR"
fi

export PATH="$PATH:$DEPOT_TOOLS_DIR"
"$DEPOT_TOOLS_DIR/ensure_bootstrap"

# Set up Google's client, including when reusing a standalone V8 checkout.
if [ ! -d v8 ] || [ ! -f .gclient ]
then
  if [ ! -d v8 ]; then
    fetch v8
  else
    gclient config --name v8 --unmanaged https://chromium.googlesource.com/v8/v8.git
  fi
  if [ "$OS" == "android" ] 
  then
	echo "target_os = [\"android\"];" >> .gclient
	gclient sync
  fi
  if [ "$OS" == "ios" ] 
  then
	echo "target_os = [\"ios\"];" >> .gclient
	gclient sync
  fi
fi

cd v8
git reset --hard
gclient recurse --scm=git -- git reset --hard
git checkout "$V8_TAG"
# Sync deps without hooks to avoid downloading unnecessary test data
# (wasm-spec-tests, wasm-js).
gclient sync --with_branch_heads --with_tags --nohooks
# Run only the hooks required for building
python3 build/util/lastchange.py -o build/util/LASTCHANGE

if [ "$OS" = "linux" ] && [ "$ARCH" = "arm64" ]; then
  # Hooks are disabled above, so install target and host sysroots explicitly.
  # The host sysroot is needed for build-time tools such as mksnapshot.
  python3 build/linux/sysroot_scripts/install-sysroot.py --arch=arm64
  if [ "$(uname -m)" = "x86_64" ]; then
    python3 build/linux/sysroot_scripts/install-sysroot.py --arch=amd64
  fi
fi

for patch in ../patches/*.patch; do 
  git apply "$patch"
done

# Keep both Rust-backed integrations disabled. Intl still uses bundled ICU.
if [ "$OS" == "ios" ]
then
gn gen out/release --args="is_debug=false \
  v8_symbol_level=0 \
  symbol_level = 0 \
  is_component_build=false \
  is_official_build=false \
  use_custom_libcxx=false \
  use_custom_libcxx_for_host=false \
  use_sysroot=false \
  use_glib=false \
  is_clang=$IS_CLANG \
  v8_expose_symbols=true \
  v8_optimized_debug=false \
  v8_enable_sandbox=false \
  v8_enable_i18n_support=true \
  icu_use_data_file=false \
  v8_enable_gdbjit=false \
  v8_use_external_startup_data=false \
  treat_warnings_as_errors=false \
  v8_enable_fast_mksnapshot = true \
  v8_enable_handle_zapping = false \
  v8_enable_pointer_compression = true \
  v8_enable_short_builtin_calls = true \
  v8_monolithic = true \
  v8_deprecation_warnings = false \
  v8_enable_temporal_support = false \
  v8_enable_ecma402_icu4x = false \
  ios_enable_code_signing = false \
  target_cpu=\"$ARCH\" \
  v8_target_cpu=\"$ARCH\" \
  target_os=\"$OS\" \
  target_environment=\"device\" \
  "
else
gn gen out/release --args="is_debug=false \
  v8_symbol_level=0 \
  symbol_level = 0 \
  is_component_build=false \
  is_official_build=false \
  use_custom_libcxx=$USE_CUSTOM_LIBCXX \
  use_custom_libcxx_for_host=$USE_CUSTOM_LIBCXX \
  use_sysroot=$USE_SYSROOT \
  use_glib=false \
  is_clang=$IS_CLANG \
  v8_expose_symbols=true \
  v8_optimized_debug=false \
  v8_enable_sandbox=false \
  v8_enable_i18n_support=true \
  icu_use_data_file=false \
  v8_enable_gdbjit=false \
  v8_use_external_startup_data=false \
  treat_warnings_as_errors=false \
  v8_enable_fast_mksnapshot = true \
  v8_enable_handle_zapping = false \
  v8_enable_pointer_compression = true \
  v8_deprecation_warnings = false \
  v8_enable_temporal_support = false \
  v8_enable_ecma402_icu4x = false \
  target_cpu=\"$ARCH\" \
  v8_target_cpu=\"$ARCH\" \
  target_os=\"$OS\" \
  "
fi

# Chromium's Rust rules use multi-output depslog support that upstream Ninja
# lacks. Always use the DEPS-pinned Chromium Ninja downloaded by gclient sync.
NINJA=./third_party/ninja/ninja

# Showtime!
NINJA_ARGS=()
if [ -n "${NINJA_JOBS:-}" ]; then
  NINJA_ARGS=(-j "$NINJA_JOBS")
fi

if [ "$OS" == "ios" ]; then
  "$NINJA" "${NINJA_ARGS[@]}" -C out/release v8_monolith
else
  "$NINJA" "${NINJA_ARGS[@]}" -C out/release wee8
fi

ls -laR out/release/obj

# Package the output into a proper directory structure:
#   include/         - V8 public headers
#   include/wasm-c-api/wasm.h - Wasm C API header (patched)
#   lib/libv8.a      - The built library
DIST_DIR="out/dist"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/include"
mkdir -p "$DIST_DIR/include/wasm-c-api"
mkdir -p "$DIST_DIR/lib"

# Copy V8 public headers (preserving subdirectory structure)
cp -R include/* "$DIST_DIR/include/"
# Remove non-header files
find "$DIST_DIR/include" -type f ! -name "*.h" -delete

# Copy the patched wasm C API header
cp third_party/wasm-api/wasm.h "$DIST_DIR/include/wasm-c-api/wasm.h"

# Copy the library (renamed to libv8.a)
if [ "$OS" == "ios" ]; then
  cp out/release/obj/libv8_monolith.a "$DIST_DIR/lib/libv8.a"
else
  cp out/release/obj/libwee8.a "$DIST_DIR/lib/libv8.a"
fi

echo "=== Distribution layout ==="
find "$DIST_DIR" -type f | sort

if [ "$OS" = "linux" ] && command -v readelf >/dev/null 2>&1; then
  if readelf -rW "$DIST_DIR/lib/libv8.a" | grep -Eq 'R_X86_64_TPOFF32|R_AARCH64_TLSLE'; then
    echo "The V8 archive still contains local-exec TLS relocations" >&2
    exit 1
  fi

  if nm -u "$DIST_DIR/lib/libv8.a" | grep -q '__isoc23_'; then
    echo "The V8 archive requires glibc 2.38 C23 symbols" >&2
    nm -u "$DIST_DIR/lib/libv8.a" | grep '__isoc23_' | sort -u >&2
    exit 1
  fi
fi
