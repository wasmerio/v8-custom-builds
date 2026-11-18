<div align="center">
  <a href="https://wasmer.io" target="_blank" rel="noopener noreferrer">
    <img width="300" src="https://raw.githubusercontent.com/wasmerio/wasmer/master/assets/logo.png" alt="Wasmer logo">
  </a>
  
  <h1>wee8 Custom Builds</h1>
  
  <p>
    <a href="https://github.com/xdoardo/wee8-custom-builds/actions?query=workflow%3A%22Build%22">
      <img src="https://github.com/wasmerio/llvm-custom-builds/workflows/Build/badge.svg" alt="Build Status">
    </a>
    <a href="https://github.com/xdoardo/wee8-custom-builds/blob/master/LICENSE">
      <img src="https://img.shields.io/github/license/wasmerio/llvm-custom-builds.svg" alt="License">
    </a>
  </p>

  <h3>
    <a href="https://wasmer.io/">Website</a>
    <span> • </span>
    <a href="https://docs.wasmer.io">Docs</a>
    <span> • </span>
    <a href="https://slack.wasmer.io/">Slack Channel</a>
  </h3>

</div>

<hr/>

> Go along your path, this is a dangerous place.

## Linux AArch64

Build in an AArch64 Linux environment with native Clang, LLVM tools,
compiler-rt, LLD, and a C++20-capable GCC installation for libstdc++.
Run the build from the repository root.

```sh
./build.sh arm64 linux
```

The script also accepts `aarch64` and detects the target when run without
arguments on AArch64 Linux. Set `CLANG_BASE_PATH` to select a different LLVM
installation prefix. The packaged headers and archive are written to
`v8/out/dist`.

CI builds `v8-linux-arm64.tar.xz` on an ARM64 runner in a pinned manylinux
2.28 container using GCC 12's libstdc++ headers for Ubuntu 22.04 compatibility.
It links the archive into a shared library with libstdc++ and runs a
WebAssembly module through the packaged C API before uploading it.
