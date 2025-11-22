# C++ Performance Profiler GitHub Action

![Version](https://img.shields.io/github/v/release/boxtob/cpp-perf-action)

Automatically run **Valgrind memcheck**, **callgrind**, and **gperftools** on your C/C++ binaries in every PR.

## Features

* Memory-leak detection with source-line annotations (`::error file=…`)
* CPU hotspot reporting (callgrind & gperftools)
* High-precision tracing profiling (cachegrind)
* Configurable per-run (memcheck / callgrind / gperftools)
* Fail the job on leaks (optional)
* Uploads raw `.out` files as artifacts
* Uploads flamegraph `.png`files as artifacts

## Quick start

```yaml
- name: Run C++ Profiler (Experimental)
  uses: boxtob/cpp-perf-action@v1.1.0
  with:
    binaries: build/test
    apt-packages: libgl1-mesa-dev libglfw3-dev
    ld-library-path: /workspace/libs
    valgrind-memcheck: true
    valgrind-callgrind: true
    valgrind-cachegrind: true
    gperftools: true
    fail-on-leak: true
    run-args: --verbose

- name: Upload Artifacts
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: profiling-results
    path: ${{ steps.profiler.outputs.artifacts }}
```


## Binary Compatibility

This Action runs in an **Ubuntu 24.04** Docker container (glibc 2.39).

Your binary will work if built on:

- Ubuntu 20.04+
- Debian 11+
- Fedora 34+
- Arch Linux, Manjaro, openSUSE, etc.
- WSL2 (Ubuntu/Debian)
- Any cross-compile targeting `x86_64-linux-gnu` with glibc ≤ 2.39

Will **NOT** work:
- Alpine Linux (uses musl)
- macOS / Windows binaries
- ARM binaries
- Very old distros (e.g., CentOS 7)

**Best practice**: Build your binary **in the same GitHub Actions job** (`ubuntu-latest`) — guaranteed compatibility.