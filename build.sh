#!/bin/bash

# Display all commands before executing them.
set -o errexit
set -o errtrace
set -x

DEPOT_TOOLS_REPO="https://chromium.googlesource.com/chromium/tools/depot_tools.git"
DEPOT_TOOLS_DIR="/tmp/depot_tools"

V8_TAG=${V8_TAG:-"15.0.1"}

if [ -z "$1" ]; then 
  case $(uname -m) in
	"x86_64")
	  ARCH="x64"
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


if [ ! -d "$DEPOT_TOOLS_DIR" ]
then 
  git clone "$DEPOT_TOOLS_REPO" "$DEPOT_TOOLS_DIR"
fi

export PATH="$PATH:$DEPOT_TOOLS_DIR"

# Set up google's client and fetch v8
if [ ! -d v8 ]
then 
  fetch v8
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
git checkout $V8_TAG
# Sync deps without hooks to avoid downloading unnecessary test data
# (wasm-spec-tests, wasm-js) which can fail on musl/Alpine due to gsutil issues.
gclient sync --with_branch_heads --with_tags --nohooks
# Run only the hooks required for building
python3 build/util/lastchange.py -o build/util/LASTCHANGE

for patch in ../patches/*.patch; do
  git apply "$patch"
done

# V8 14+ headers require clang (use __has_warning and friends GCC can't parse).
# glibc: chromium's bundled prebuilt. musl: glibc-linked prebuilt won't run,
# so use system clang via apk and chromium's unbundle:default toolchain
# (honours $CC/$CXX/$AR/$NM, sidesteps the bundled-clang/lld assumptions).
if [ "$OS" == "linux" ]; then
  if [ -f /etc/alpine-release ]; then
    export CC=clang
    export CXX=clang++
    export AR=llvm-ar
    export NM=llvm-nm
    # Chromium's bundled rust_wrapper still emits -Z flags even with
    # rustc_nightly_capability=false; bootstrap lets stable rustc accept them.
    export RUSTC_BOOTSTRAP=1
    # Force libc++ into musl mode (__config_site is force-included, overrides -D).
    sed -i 's|#define _LIBCPP_HAS_MUSL_LIBC 0|#define _LIBCPP_HAS_MUSL_LIBC 1|' buildtools/third_party/libc++/__config_site
    # Strip clang-23-only flags that clang 20 rejects.
    sed -i 's|"-fdiagnostics-show-inlining-chain",\?||g' build/config/compiler/BUILD.gn
    sed -i 's|"-fno-lifetime-dse",\?||g' build/config/compiler/BUILD.gn
    sed -i 's|"-fsanitize-ignore-for-ubsan-feature=${invoker.sanitizer}",\?||g' build/config/sanitizers/sanitizers.gni
    # Replace chromium's hardcoded x86_64-unknown-linux-gnu triple with alpine's
    # native one — clang's default is correct; rustlib only ships the alpine path.
    grep -rl '"--target=x86_64-unknown-linux-gnu"' build/config/ | xargs -r sed -i '/"--target=x86_64-unknown-linux-gnu"/d'
    grep -rl 'rust_abi_target = "x86_64-unknown-linux-gnu"' build/config/ | xargs -r sed -i 's|rust_abi_target = "x86_64-unknown-linux-gnu"|rust_abi_target = "x86_64-alpine-linux-musl"|'
    grep -qxF 'x86_64-alpine-linux-musl' build/rust/known-target-triples.txt || echo 'x86_64-alpine-linux-musl' >> build/rust/known-target-triples.txt
    # rustc_nightly_capability is computed (not a declare_args), so override
    # the source. Alpine ships stable rustc only.
    grep -rl 'rustc_nightly_capability = use_chromium_rust_toolchain || build_with_chromium' build/config/ | xargs -r sed -i 's#rustc_nightly_capability = use_chromium_rust_toolchain || build_with_chromium#rustc_nightly_capability = false#'
    CLANG_ARGS="custom_toolchain=\"//build/toolchain/linux/unbundle:default\" host_toolchain=\"//build/toolchain/linux/unbundle:default\" is_clang=true clang_use_chrome_plugins=false use_custom_libcxx=true use_custom_libcxx_for_host=true enable_rust=true rust_sysroot_absolute=\"/usr\" rust_bindgen_root=\"/usr\" rust_force_head_revision=true rustc_version=\"$(rustc --version | cut -d' ' -f2)\" use_partition_alloc_as_malloc=false use_allocator_shim=false"
  else
    python3 tools/clang/scripts/update.py
    CLANG_ARGS="is_clang=true use_custom_libcxx=false use_custom_libcxx_for_host=false"
  fi
elif [ "$OS" == "mac" ]; then
  # V8 14+ uses std::atomic_ref (libc++ ≥ LLVM 19); Apple's libc++ in
  # Xcode 16 lacks it. Build against chromium's bundled libc++ instead.
  python3 tools/clang/scripts/update.py
  CLANG_ARGS="is_clang=true use_custom_libcxx=true use_custom_libcxx_for_host=true"
else
  CLANG_ARGS="is_clang=false use_custom_libcxx=false use_custom_libcxx_for_host=false"
fi

if [ "$OS" == "ios" ]
then
gn gen out/release --args="is_debug=false \
  v8_symbol_level=0 \
  symbol_level = 0 \
  is_component_build=false \
  is_official_build=false \
  use_sysroot=false \
  use_glib=false \
  $CLANG_ARGS \
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
  use_siso = false \
  v8_enable_short_builtin_calls = true \
  v8_monolithic = true \
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
  use_sysroot=false \
  use_glib=false \
  $CLANG_ARGS \
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
  use_siso = false \
  target_cpu=\"$ARCH\" \
  v8_target_cpu=\"$ARCH\" \
  target_os=\"$OS\" \
  "
fi

# Showtime!
if [ "$OS" == "ios" ]; then
  ninja -C out/release v8_monolith
else
  ninja -C out/release wee8
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
