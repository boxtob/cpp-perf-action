# C++ Performance Profiler GitHub Action

[![Experimental](https://img.shields.io/badge/status-experimental-red.svg?logo=github)](https://github.com/boxtob/cpp-perf-action/releases/tag/v0.2.0)

Automatically run **Valgrind memcheck**, **callgrind**, and **gperftools** on your C/C++ binaries in every PR.

![example badge](https://github.com/yourname/cpp-perf-action/workflows/C++%20Performance%20Profiling/badge.svg)

## Features

* Memory-leak detection with source-line annotations (`::error file=…`)
* CPU hotspot reporting (callgrind & gperftools)
* Configurable per-run (memcheck / callgrind / gperftools)
* Fail the job on leaks (optional)
* Uploads raw `.out` files as artifacts

## Quick start

```yaml
- uses: yourname/cpp-perf-action@v1
  with:
    binaries: mytest another_test
    valgrind-memcheck: true
    valgrind-callgrind: true
    gperftools: false
    fail-on-leak: true