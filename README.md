# C++ Performance Profiler GitHub Action

![Version](https://img.shields.io/github/v/release/boxtob/cpp-perf-action)
![ARM64 Ready](https://img.shields.io/badge/ARM64-native-green)

Automatically run **Valgrind memcheck**, **callgrind**, and **gperftools** on your C/C++ binaries in every PR.

## Features

- Memory leak detection with `::error file=...` annotations
- CPU hotspot reporting (callgrind + gperftools)
- Full L1/LL **cache simulation** (cachegrind)
- Flamegraph PNG uploaded as artifact
- Runtime `apt-get install` for missing system libraries
- Custom `LD_LIBRARY_PATH` for your `.so` files
- Pass any runtime args (`--config`, `--verbose`, etc.)
- Fail CI on leaks or excessive hotspots
- Works on **Linux x86_64 and ARM64**

## Quick start

### x86_64 (standard runners)

```yaml
- name: Run C++ Profiler (x86_64)
  uses: boxtob/cpp-perf-action@v1.2.3
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

### ARM64 (native – Graviton, Raspberry Pi)

```yaml
jobs:
  profile-arm64:
    runs-on: ubuntu-24.04-arm
    steps:
      - uses: actions/checkout@v4

      - name: Run C++ Profiler (ARM64)
        uses: boxtob/cpp-perf-action@v1.2.3
        with:
          binaries: test-arm64
          run-args: --verbose
          valgrind-memcheck: true
          gperftools: true
```

### Platform Support Table

| Architecture   | Runner                          | Speed     | Recommended?
|----------------|---------------------------------|-----------|---------------
| Linux x86_64   | `ubuntu-latest`                 | Fastest   | Yes (default)
| Linux ARM64    | `ubuntu-24.04-arm`              | Native    | Yes (best)
| Linux ARM64    | `ubuntu-22.04-arm`              | Native    | Yes (best)

## Native ARM64 Support

This Action runs **natively** on GitHub's official ARM64 runners:

```yaml
runs-on: ubuntu-24.04-arm
````

No QEMU. No cross-compilation. Full Valgrind + gperftools performance.
Perfect for:
* AWS Graviton
* Raspberry Pi
* Any modern ARM server

Just use `ubuntu-24.04-arm` — the correct image is pulled automatically.

## Binary Compatibility

This Action runs in an **Ubuntu 24.04** Docker container (glibc 2.39).

Your binary will work if built on:

- Ubuntu 20.04+
- Debian 11+
- Fedora 34+
- Arch Linux, Manjaro, openSUSE, etc.
- WSL2 (Ubuntu/Debian)
- Graviton
- Raspberry Pi

Will **NOT** work:
- Alpine Linux (uses musl)
- macOS / Windows binaries
- Very old distros (e.g., CentOS 7)

**Best practice**: Build your binary **in the same GitHub Actions job** (`ubuntu-latest` or `ubuntu-22.04-arm` or `ubuntu-24.04-arm`) — guaranteed compatibility.