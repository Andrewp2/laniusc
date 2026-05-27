#!/usr/bin/env bash
set -euo pipefail

run=0
tier=focused
list_tests=0
allow_scale=0

usage() {
  cat <<'USAGE'
Usage: tools/compiler_acceptance.sh [--run] [--list-tests] [--allow-scale] [--tier focused|smoke|generated|properties|pareas|all]

Default mode is dry-run: commands are printed but not executed.
Use --list-tests to print/list test inventories instead of acceptance runs.
Use --allow-scale to execute generated, Pareas, or all-tier scale lanes.

Tiers:
  focused     Run the small CPU-only compile/model and shader-loop checkpoint.
  smoke       List generated gates and run the no-GPU capacity estimate gate.
  generated   Run parameterized generated compiler gates around 5k lines by default.
  properties  Run named deterministic randomized/property-style compiler tests.
  pareas      Run the optional Pareas comparison gate.
  all         Run focused, smoke, generated, properties, and pareas.

Relevant environment:
  LANIUS_GENERATED_LINES                         default 5000
  LANIUS_CAPACITY_STRESS_LINES                   default 5000
  LANIUS_CAPACITY_STRESS_SOURCE                  default expr-dense
  LANIUS_MAX_CAPACITY_STRESS_COMPILE_FLOOR_BYTES default 12 GiB
  LANIUS_ALLOW_LARGE_GENERATED_TESTS=1           opt into >20k generated gates
  LANIUS_GENERATED_GATE_COMMAND_TIMEOUT_MS        default 120000
  LANIUS_X86_READBACK_TIMEOUT_MS                  default 60000 inside generated gates
  LANIUS_PAREAS_COMPARE_ITERS                    default 1; >3 requires large-test opt-in
  LANIUS_ACCEPTANCE_ALLOW_SCALE=1                 allow generated/Pareas/all tiers to execute
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
    --allow-scale)
      allow_scale=1
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
  focused|smoke|generated|properties|pareas|all) ;;
  *)
    echo "unknown tier: $tier" >&2
    usage >&2
    exit 2
    ;;
esac

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

scale_allowed() {
  [[ "$allow_scale" -eq 1 ]] || is_truthy "${LANIUS_ACCEPTANCE_ALLOW_SCALE:-}"
}

require_scale_opt_in() {
  if [[ "$run" -eq 0 || "$list_tests" -eq 1 ]]; then
    return
  fi

  case "$tier" in
    generated|pareas|all)
      if ! scale_allowed; then
        echo "tier '$tier' is a scale/performance lane and requires --allow-scale or LANIUS_ACCEPTANCE_ALLOW_SCALE=1 with --run" >&2
        exit 2
      fi
      ;;
  esac
}

run_cmd() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  if [[ "$run" -eq 1 ]]; then
    "$@"
  fi
}

run_cargo_test() {
  local test_target="$1"
  local test_name="${2:-}"
  shift 2 || true
  if [[ -n "$test_name" ]]; then
    run_cmd cargo test -j1 --test "$test_target" "$test_name" -- --test-threads=1 "$@"
  else
    run_cmd cargo test -j1 --test "$test_target" -- --test-threads=1 "$@"
  fi
}

run_cargo_lib_test() {
  local test_name="$1"
  run_cmd cargo test -p laniusc -j1 --lib "$test_name" -- --test-threads=1
}

describe_tier() {
  case "$tier" in
    focused)
      echo "# testing-strategy tier=focused lane=CPU/model contract='library compiles, shader loop budgets stay bounded, work-queue model still matches reference transitions'"
      ;;
    smoke)
      echo "# testing-strategy tier=smoke lane=capacity-estimate contract='generated gates are discoverable and x86 stress sizing is computed without GPU submission'"
      ;;
    generated)
      echo "# testing-strategy tier=generated lane=fixed-seed-generated contract='supported generated frontend/backend cases still compile and validate at the explicitly requested size'"
      ;;
    properties)
      echo "# testing-strategy tier=properties lane=targeted-property contract='name, shape, and HIR-record invariants hold on focused randomized cases'"
      ;;
    pareas)
      echo "# testing-strategy tier=pareas lane=external-comparison contract='optional Pareas comparison is bounded, replayable, and explicitly requested'"
      ;;
    all)
      echo "# testing-strategy tier=all lane=escalated-checkpoint contract='focused, smoke, generated, properties, and Pareas lanes were intentionally requested together'"
      ;;
  esac
  if [[ "$run" -eq 0 ]]; then
    echo "# testing-strategy mode=dry-run; pass --run to execute these commands"
  fi
}

run_focused() {
  if [[ "$list_tests" -eq 1 ]]; then
    run_cmd cargo test --test shader_loop_budgets -j1 -- --list
    run_cmd cargo test -p laniusc source_pack_work_queue_progress_page_transitions_match_reference_model -j1 --lib -- --list
    return
  fi
  run_cmd cargo check --lib -j1
  run_cargo_test shader_loop_budgets shader_tree_loop_budget_does_not_grow
  run_cargo_test shader_loop_budgets type_checker_shader_loop_budget_does_not_grow
  run_cargo_lib_test source_pack_work_queue_progress_page_transitions_match_reference_model
}

run_smoke() {
  run_cmd cargo test --test generated_10k_gates -j1 -- --list
  if [[ "$list_tests" -eq 1 ]]; then
    return
  fi
  run_cargo_test generated_10k_gates \
    generated_capacity_stress_x86_has_capacity_estimate_without_gpu_work \
    --ignored
}

run_generated() {
  if [[ "$list_tests" -eq 1 ]]; then
    run_cmd cargo test --test generated_10k_gates -j1 -- --list
    return
  fi
  run_cargo_test generated_10k_gates \
    generated_frontend_suite_passes_supported_phases \
    --ignored
  run_cargo_test generated_10k_gates \
    generated_reused_parse_matches_independent_varied \
    --ignored
  run_cargo_test generated_10k_gates \
    generated_reused_x86_suite_validates \
    --ignored
}

run_properties() {
  if [[ "$list_tests" -eq 1 ]]; then
    run_cmd cargo test --test codegen_x86_properties -j1 -- --list
    run_cmd cargo test --test type_checker_semantics -j1 -- --list
    return
  fi
  run_cargo_test codegen_x86_properties \
    x86_codegen_does_not_restore_whole_function_shape_recognizers
  run_cargo_test codegen_x86_properties \
    generated_x86_programs_are_name_and_shape_independent
  run_cargo_test type_checker_semantics \
    type_checker_accepts_generated_let_chain_from_hir_records
  run_cargo_test type_checker_semantics \
    type_checker_accepts_generated_call_argument_shapes_from_hir_records
}

run_pareas() {
  if [[ "$list_tests" -eq 1 ]]; then
    run_cmd cargo test --test generated_10k_gates -j1 \
      generated_pareas_comparison_when_available \
      -- --list
    return
  fi
  run_cargo_test generated_10k_gates \
    generated_pareas_comparison_when_available \
    --ignored
}

require_scale_opt_in
describe_tier

case "$tier" in
  focused)
    run_focused
    ;;
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
    run_focused
    run_smoke
    run_generated
    run_properties
    run_pareas
    ;;
esac
