#!/bin/bash
set -euo pipefail

echo "Container started"
echo "Working directory: $(pwd)"
echo "Input binaries: $@"
echo "GITHUB_WORKSPACE: $GITHUB_WORKSPACE"

# ---- Debug: local mode -----------------------------------------------------------------------------------------------
[[ -z "${GITHUB_ACTIONS:-}" ]] && echo "Running in local mode"

# ---- Print INPUT_* (only in CI) -----------------------------------------
[[ -n "${GITHUB_ACTIONS:-}" ]] && {
  echo "::group::INPUT variables"
  env | grep '^INPUT_' | sort | while IFS='=' read -r k v; do
    printf "  %s = %s\n" "$k" "$v"
  done
  echo "::endgroup::"
}

# ---- Runtime apt install (system libraries) ----------------------------
if [[ -n "${INPUT_APT_PACKAGES:-}" ]]; then
  echo "Installing apt packages: $INPUT_APT_PACKAGES"
  apt-get update && apt-get install -y $INPUT_APT_PACKAGES && rm -rf /var/lib/apt/lists/*
fi

# ---- LD_LIBRARY_PATH (user .so files) ----------------------------------
if [[ -n "${INPUT_LD_LIBRARY_PATH:-}" ]]; then
  export LD_LIBRARY_PATH="$INPUT_LD_LIBRARY_PATH:$LD_LIBRARY_PATH"
  echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
fi

# ---- Binaries -----------------------------------------------------------
BINARIES=("${@:-}")
[[ ${#BINARIES[@]} -eq 0 ]] && {
  echo "::error::No binaries specified. Use 'binaries: your_binary' in workflow."
  exit 1
}

for bin in "${BINARIES[@]}"; do
  full_path=$(realpath "$bin" 2>/dev/null || echo "$bin")
  [[ ! -x "$full_path" ]] && { echo "::error::Binary '$bin' not found"; exit 1; }

  bin_name=$(basename "$full_path")
  bin_dir=$(dirname "$full_path")

  echo "=== Profiling $bin ($full_path) ==="
  pushd "$bin_dir" > /dev/null

  # Valgrind memcheck
  if [[ "${INPUT_VALGRIND_MEMCHECK:-true}" == "true" ]]; then
    valgrind --tool=memcheck \
      --leak-check=full \
      --show-leak-kinds=all \
      --track-origins=yes \
      --read-var-info=yes \
      --keep-debuginfo=yes \
      "./$bin_name" \
      > "${bin_name}_valgrind_memcheck.out" 2>&1 || true
  fi

  # Valgrind callgrind
  if [[ "${INPUT_VALGRIND_CALLGRIND:-false}" == "true" ]]; then
    valgrind --tool=callgrind "./$bin_name" \
      > "${bin_name}_valgrind_callgrind.out" 2>&1 || true
  fi

  # gperftools
  if [[ "${INPUT_GPERFTOOLS:-false}" == "true" ]]; then
    echo "Running gperftools (100 Hz sampling)..."
    export CPUPROFILE_FREQUENCY=100
    export CPUPROFILE="${bin_name}_profile.out"
    "./$bin_name" || true
    if [[ -f "$CPUPROFILE" ]]; then
      pprof --text "./$bin_name" "$CPUPROFILE" > "${bin_name}_pprof.out" 2>&1 || true
      
      echo "Generating flamegraph..."
      if pprof --png "./$bin_name" "$CPUPROFILE" > "${bin_name}_flamegraph.png" 2> pprof_png_error.log; then
        echo "Flamegraph created: ${bin_name}_flamegraph.png"
      else
        echo "::warning::Failed to generate PNG:"
        cat pprof_png_error.log
      fi      
    fi
  fi

  # Parse
  /app/venv/bin/python /app/parse_profile.py \
    "${bin}_valgrind_memcheck.out" \
    "${bin}_valgrind_callgrind.out" \
    "${bin}_pprof.out" \
    "$bin"
done

# ---- Fail on leak -------------------------------------------------------
if [[ "${INPUT_FAIL_ON_LEAK:-false}" == "true" ]]; then
  if grep -q "::error::" *.out 2>/dev/null; then
    echo "::error::Memory leak detected — failing job"
    exit 1
  fi
fi

# ---- Artifacts ----------------------------------------------------------
ARTIFACT_DIR="artifacts"
mkdir -p "$ARTIFACT_DIR"

# Copy from container's current dir to ARTIFACT_DIR
cp -f *.out "$ARTIFACT_DIR"/ 2>/dev/null || true

echo "Artifacts ready at $ARTIFACT_DIR:"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "artifacts=$ARTIFACT_DIR" >> "$GITHUB_OUTPUT"
else
  echo "Artifacts in $ARTIFACT_DIR:"
  ls -la "$ARTIFACT_DIR"
  fi-la "$ARTIFACT_DIR"
fi