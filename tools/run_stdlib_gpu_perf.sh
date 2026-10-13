#!/usr/bin/env bash
# Run one paired case at a time: RESULT_DIR CASE {synthetic|entry} ARGS...
# RESULT_DIR contains identical baseline/current benchmark binaries and separate
# baseline-shaders/current-shaders directories. The compiler loads shaders from
# disk even in release builds; switching that directory isolates shader changes.
set -euo pipefail

result_dir=$(realpath "$1")
case_name=$2
kind=$3
shift 3
artifact_root=${LANIUS_PERF_SHADER_ROOT:-"$result_dir/../build/laniusc-shader-artifacts/release/shaders"}
if [[ ! -L "$artifact_root" ]]; then
  printf 'shader artifact root must be the prepared benchmark symlink\n' >&2
  exit 2
fi
trap 'ln -sfn "$result_dir/current-shaders" "$artifact_root"' EXIT
case "$case_name" in
  *[!a-zA-Z0-9_-]*|'') printf 'invalid case name\n' >&2; exit 2 ;;
esac
case "$kind" in
  synthetic) binary_suffix=gpu-compile-bench ;;
  entry) binary_suffix=stdlib-gpu-perf ;;
  *) printf 'expected synthetic or entry\n' >&2; exit 2 ;;
esac

# Four pairs, with opposite order in alternating pairs.
# Do not run multiple cases concurrently on the same GPU.
for pair in 0 1 2 3; do
  if (( pair % 2 == 0 )); then
    revisions=(baseline current)
  else
    revisions=(current baseline)
  fi
  for revision in "${revisions[@]}"; do
    ln -sfn "$result_dir/$revision-shaders" "$artifact_root"
    log="$result_dir/$case_name-$revision-$pair.log"
    printf 'case=%s revision=%s pair=%s\n' "$case_name" "$revision" "$pair"
    if [[ "$kind" == synthetic ]]; then
      timeout 105s "$result_dir/$revision-$binary_suffix" \
        --emit x86_64-elf --warmups 3 --iters 10 --run-x86-output "$@" >"$log" 2>&1
      rg '^phase=x86 ' "$log"
    else
      timeout 105s "$result_dir/$revision-$binary_suffix" "$@" 3 10 >"$log" 2>&1
      rg '^entry=' "$log"
    fi
  done
done
