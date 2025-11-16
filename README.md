# C++ Performance Profiler GitHub Action

[![Experimental](https://img.shields.io/badge/status-experimental-red.svg?logo=github)](https://github.com/boxtob/cpp-perf-action/releases/tag/v0.3.1)

Automatically run **Valgrind memcheck**, **callgrind**, and **gperftools** on your C/C++ binaries in every PR.

## Features

* Memory-leak detection with source-line annotations (`::error file=…`)
* CPU hotspot reporting (callgrind & gperftools)
* Configurable per-run (memcheck / callgrind / gperftools)
* Fail the job on leaks (optional)
* Uploads raw `.out` files as artifacts
* Uploads flamegraph `.png`files as artifacts

## Quick start

```yaml
- name: Run C++ Profiler (Experimental)
  uses: boxtob/cpp-perf-action@v0.4.1
  with:
    binaries: build/test
    apt-packages: libgl1-mesa-dev libglfw3-dev
    ld-library-path: /workspace/libs
    valgrind-memcheck: true
    gperftools: true
    fail-on-leak: true
    run-args: --verbose

- name: Upload Artifacts
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: profiling-results
    path: ${{ steps.profiler.outputs.artifacts }}