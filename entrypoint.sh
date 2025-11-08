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

# ---- Binaries -----------------------------------------------------------
BINARIES=("${@:-}")
[[ ${#BINARIES[@]} -eq 0 ]] && {
  echo "::error::No binaries specified. Use 'binaries: your_binary' in workflow."
  exit 1
}

for bin in "${BINARIES[@]}"; do
  [[ ! -x "$bin" ]] && {
    echo "::error::Binary '$bin' not found or not executable. Provide pre-built binary."
    exit 1
  }

  echo "=== Profiling $bin ==="

  # Valgrind memcheck
  if [[ "${INPUT_VALGRIND_MEMCHECK:-true}" == "true" ]]; then
    valgrind --tool=memcheck \
      --leak-check=full \
      --show-leak-kinds=all \
      --track-origins=yes \
      --read-var-info=yes \
      --keep-debuginfo=yes \
      "./$bin" \
      > "${bin}_valgrind_memcheck.out" 2>&1 || true
  fi

  # Valgrind callgrind
  if [[ "${INPUT_VALGRIND_CALLGRIND:-false}" == "true" ]]; then
    valgrind --tool=callgrind "./$bin" \
      > "${bin}_valgrind_callgrind.out" 2>&1 || true
  fi

  # gperftools
  if [[ "${INPUT_GPERFTOOLS:-false}" == "true" ]]; then
    echo "Running gperftools (100 Hz sampling)..."
    export CPUPROFILE_FREQUENCY=100
    export CPUPROFILE="${bin}_profile.out"
    "./$bin" || true
    if [[ -f "${bin}_profile.out" ]]; then
      pprof --text "/workspace/$bin" "${bin}_profile.out" > "${bin}_pprof.out" 2>&1 || true
      pprof --png  "/workspace/$bin" "${bin}_profile.out" > "${bin}_flamegraph.png" 2>&1 || true
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

# Copy from container's /tmp to host's $GITHUB_WORKSPACE
cp -f *.out "$ARTIFACT_DIR"/ 2>/dev/null || true

echo "Artifacts ready at $ARTIFACT_DIR:"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "artifacts=$ARTIFACT_DIR" >> "$GITHUB_OUTPUT"
else
  echo "Artifacts in $ARTIFACT_DIR:"
  ls -la "$ARTIFACT_DIR"
  fi-la "$ARTIFACT_DIR"
fi