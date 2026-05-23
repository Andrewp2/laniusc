#!/usr/bin/env bash
set -euo pipefail

run=0
tier=smoke
list_tests=0

usage() {
  cat <<'USAGE'
Usage: tools/compiler_acceptance.sh [--run] [--list-tests] [--tier smoke|generated|properties|pareas|all]

Default mode is dry-run: commands are printed but not executed.
Use --list-tests to print/list test inventories instead of acceptance runs.

Tiers:
  smoke       List generated gates and run the no-GPU capacity estimate gate.
  generated   Run parameterized generated compiler gates around 10k lines.
  properties  Run deterministic randomized/property-style compiler tests.
  pareas      Run the optional Pareas comparison gate.
  all         Run smoke, generated, properties, and pareas.

Relevant environment:
  LANIUS_GENERATED_LINES                         default 10000
  LANIUS_CAPACITY_STRESS_LINES                   default 20000
  LANIUS_CAPACITY_STRESS_SOURCE                  default expr-dense
  LANIUS_MAX_CAPACITY_STRESS_COMPILE_FLOOR_BYTES default 12 GiB
  LANIUS_ALLOW_LARGE_GENERATED_TESTS=1           opt into >20k generated gates
  PAREAS_BIN                                     path to Pareas compiler
  LANIUS_REQUIRE_PAREAS=1                        fail if Pareas is unavailable
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run)
      run=1
      shift
      ;;
    --list-tests)
      list_tests=1
      shift
      ;;
    --tier)
      if [[ $# -lt 2 ]]; then
        echo "--tier requires a value" >&2
        exit 2
      fi
      tier="$2"
      shift 2
      ;;
    --tier=*)
      tier="${1#--tier=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$tier" in
  smoke|generated|properties|pareas|all) ;;
  *)
    echo "unknown tier: $tier" >&2
    usage >&2
    exit 2
    ;;
esac

run_cmd() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  if [[ "$run" -eq 1 ]]; then
    "$@"
  fi
}

run_smoke() {
  run_cmd cargo test --test generated_10k_gates -- --list
  if [[ "$list_tests" -eq 1 ]]; then
    return
  fi
  run_cmd cargo test --test generated_10k_gates \
    generated_capacity_stress_x86_has_capacity_estimate_without_gpu_work \
    -- --ignored --nocapture
}

run_generated() {
  if [[ "$list_tests" -eq 1 ]]; then
    run_cmd cargo test --test generated_10k_gates -- --list
    return
  fi
  run_cmd cargo test --test generated_10k_gates \
    generated_frontend_suite_passes_supported_phases \
    -- --ignored --nocapture
  run_cmd cargo test --test generated_10k_gates \
    generated_reused_parse_matches_independent_varied \
    -- --ignored --nocapture
  run_cmd cargo test --test generated_10k_gates \
    generated_reused_x86_suite_validates \
    -- --ignored --nocapture
}

run_properties() {
  if [[ "$list_tests" -eq 1 ]]; then
    run_cmd cargo test --test codegen_x86_properties -- --list
    run_cmd cargo test --test type_checker_semantics -- --list
    return
  fi
  run_cmd cargo test --test codegen_x86_properties -- --test-threads=1 --nocapture
  run_cmd cargo test --test type_checker_semantics -- --test-threads=1 --nocapture
}

run_pareas() {
  if [[ "$list_tests" -eq 1 ]]; then
    run_cmd cargo test --test generated_10k_gates \
      generated_pareas_comparison_when_available \
      -- --list
    return
  fi
  run_cmd cargo test --test generated_10k_gates \
    generated_pareas_comparison_when_available \
    -- --ignored --nocapture
}

case "$tier" in
  smoke)
    run_smoke
    ;;
  generated)
    run_generated
    ;;
  properties)
    run_properties
    ;;
  pareas)
    run_pareas
    ;;
  all)
    if [[ "$list_tests" -eq 1 ]]; then
      run_smoke
      run_properties
    else
      run_smoke
      run_generated
      run_properties
      run_pareas
    fi
    ;;
esac
