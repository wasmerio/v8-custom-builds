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

Cross-compile on an x86-64 Linux host using V8/Chromium's bundled Clang:

```sh
./build.sh arm64 linux
```

The script installs Chromium's pinned ARM64 and host Debian sysroots and sets
`target_cpu="arm64"`, `v8_target_cpu="arm64"`, and `use_sysroot=true`.
It uses Chromium's bundled libc++ for both target code and host tools because
Bullseye's libstdc++ headers do not provide the C++20 features required by V8.
No native ARM64 runner, QEMU, or system cross-compiler is required.

## Typed JSPI example

[The C11 sum example](examples/jspi-sum.c) imports a suspending callback with
`wasm_func_new_suspending`, instantiates the module with `wasm_instance_new`,
and wraps its `run` export with `wasm_func_promising`. When the host work
completes, `wasm_pending_call_resume` supplies its result to the suspended guest.
The program prints `42`.

On Linux, build the example against the unpacked distribution with:

```sh
cc -std=c11 -I"$WEE8_DIR/include/wasm-c-api" -c examples/jspi-sum.c -o jspi-sum.o
c++ jspi-sum.o "$WEE8_DIR/lib/libv8.a" -ldl -pthread -o jspi-sum
./jspi-sum
```
