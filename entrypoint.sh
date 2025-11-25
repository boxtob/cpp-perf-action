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

# ---- Runtime args -------------------------------------------------------
RUN_ARGS=()
if [[ -n "${INPUT_RUN_ARGS:-}" ]]; then
  RUN_ARGS=($INPUT_RUN_ARGS)
  echo "Runtime args: ${RUN_ARGS[*]}"
else
  echo "Runtime args: none"
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
    if [[ ${#RUN_ARGS[@]} -gt 0 ]]; then
      valgrind --tool=memcheck \
        --leak-check=full \
        --show-leak-kinds=all \
        --track-origins=yes \
        --read-var-info=yes \
        --keep-debuginfo=yes \
        "./$bin_name" "${RUN_ARGS[@]}" \
        > "${bin_name}_valgrind_memcheck.out" 2>&1 || true
    else
      valgrind --tool=memcheck \
        --leak-check=full \
        --show-leak-kinds=all \
        --track-origins=yes \
        --read-var-info=yes \
        --keep-debuginfo=yes \
        "./$bin_name" \
        > "${bin_name}_valgrind_memcheck.out" 2>&1 || true
    fi
  fi

  # Valgrind callgrind
  if [[ "${INPUT_VALGRIND_CALLGRIND:-false}" == "true" ]]; then
    if [[ ${#RUN_ARGS[@]} -gt 0 ]]; then
      valgrind --tool=callgrind "./$bin_name" "${RUN_ARGS[@]}" \
        > "${bin_name}_valgrind_callgrind.out" 2>&1 || true
    else
      valgrind --tool=callgrind "./$bin_name" \
        > "${bin_name}_valgrind_callgrind.out" 2>&1 || true
    fi
  fi

  # Cachegrind (pure cache simulation)
  if [[ "${INPUT_VALGRIND_CACHEGRIND:-false}" == "true" ]]; then
    echo "Running Valgrind Cachegrind (L1/LL cache simulation)..."

    cachegrind_file="${bin_name}_cachegrind.out.%p"

    valgrind --tool=cachegrind \
      --cachegrind-out-file="$cachegrind_file" \
      "./$bin_name" "${RUN_ARGS[@]}" \
      > "${bin_name}_cachegrind.log" 2>&1 || true

    # Generate human-readable summary with cg_annotate
    if command -v cg_annotate &>/dev/null; then
      echo "Generating cg_annotate summary..."
      for cg_file in ${bin_name}_cachegrind.out.*; do
        [[ -f "$cg_file" ]] || continue
        cg_annotate "$cg_file" "./$bin_name" \
          > "$(basename "$cg_file" .out.*)_cachegrind_summary.txt" 2>&1 || true
      done
    else
      echo "::warning::cg_annotate not found — skipping summary"
    fi
  fi

  # gperftools
  if [[ "${INPUT_GPERFTOOLS:-false}" == "true" ]]; then
    echo "Running gperftools with args: ${RUN_ARGS[*]:-none}"
    export CPUPROFILE_FREQUENCY=100
    export CPUPROFILE="${bin_name}_profile.out"

  # Run binary with args
    if [[ ${#RUN_ARGS[@]} -gt 0 ]]; then
      "./$bin_name" "${RUN_ARGS[@]}" || true
    else
      "./$bin_name" || true
    fi

    if [[ -f "$CPUPROFILE" ]]; then
      profile_size=$(stat -c%s "$CPUPROFILE" 2>/dev/null || echo 0)
      echo "Profile size: $profile_size bytes"

      if [[ $profile_size -lt 500 ]]; then
        echo "::warning::Profile too small — no meaningful samples"
        continue
      fi

      # Generate text report
      pprof --text "./$bin_name" "$CPUPROFILE" > "${bin_name}_pprof.out" 2>&1 || true

      # Generate flamegraph: pprof --dot → dot -Tpng
      echo "Generating flamegraph..."
      dot_file="${bin_name}_flamegraph.dot"
      png_file="${bin_name}_flamegraph.png"

      if pprof --dot "./$bin_name" "$CPUPROFILE" > "$dot_file" 2> pprof_dot_error.log; then
        if dot -Tpng "$dot_file" -o "$png_file" 2> dot_error.log; then
          png_size=$(stat -c%s "$png_file" 2>/dev/null || echo 0)
          echo "Flamegraph created: $png_size bytes"
        else
          echo "::warning::dot failed:"
          cat dot_error.log
        fi
      else
        echo "::warning::pprof --dot failed:"
        cat pprof_dot_error.log
      fi
    else
      echo "::warning::No profile data generated"
    fi
  fi

  # Parse
  /app/venv/bin/python /app/parse_profile.py \
    "${bin_name}_valgrind_memcheck.out" \
    "${bin_name}_valgrind_callgrind.out" \
    "${bin_name}_cachegrind_summary.txt" \
    "${bin_name}_pprof.out" \
    "$bin_name"
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
mkdir -vp "$ARTIFACT_DIR"

# Copy from container's current dir to ARTIFACT_DIR
cp -vf *.out *.png *.dot "*_cachegrind.out.*" "*_cachegrind.log" "*_cachegrind_summary.txt" "$ARTIFACT_DIR"/ 2>/dev/null || true

echo "Artifacts ready at $ARTIFACT_DIR:"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "artifacts=$ARTIFACT_DIR" >> "$GITHUB_OUTPUT"
else
  echo "Artifacts in $ARTIFACT_DIR:"
  ls -la "$ARTIFACT_DIR"
  fi-la "$ARTIFACT_DIR"
fi