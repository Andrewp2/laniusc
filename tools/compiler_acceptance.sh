#!/usr/bin/env bash
set -euo pipefail

run=0
tier=focused
list_tests=0
allow_scale=0
check_plan=0
check_env=0
measurement_plan=0
measurement_plan_path=
plan_checked_tests=0
plan_invalid_tests=0
plan_missing_tests=0
plan_checked_commands=0
plan_missing_commands=0
env_errors=0
evidence_inventory_errors=0
language_slice_errors=0
test_discipline_errors=0
current_plan_lane=unclassified
plan_focused_evidence=0
plan_smoke_evidence=0
plan_generated_evidence=0
plan_properties_evidence=0
plan_property_boundary_evidence=0
plan_property_record_evidence=0
plan_property_execution_evidence=0
plan_property_semantic_evidence=0
plan_pareas_evidence=0
language_slice_public_boundary_evidence=0
language_slice_artifact_contract_evidence=0
language_slice_record_invariant_evidence=0
language_slice_semantic_contract_evidence=0
language_slice_execution_contract_evidence=0
language_slice_fail_closed_evidence=0
language_slice_measurement_scaffold_evidence=0
language_slice_parser_type_relation_evidence=0
language_slice_pass_order_evidence=0
language_slice_planned_pass_order_gaps=0
language_slice_performance_claim_guards=0
language_slice_array_lit_context_evidence=0
language_slice_struct_lit_context_evidence=0
language_slice_call_context_evidence=0
language_slice_expr_result_root_evidence=0
language_slice_trait_or_inherent_method_owner_evidence=0
language_slice_trait_impl_method_owner_evidence=0
language_slice_method_owner_evidence=0
language_slice_method_signature_status_hook=0
language_slice_method_signature_status_evidence=0
language_slice_nearest_stmt_context_evidence=0
language_slice_nearest_block_control_context_evidence=0
language_slice_rows=0
language_slice_external_tooling_gate_evidence=0
language_slice_stable_code_registry_gate=0
language_slice_diagnostic_registry_json_gate=0
language_slice_diagnostic_registry_cli_gate=0
language_slice_diagnostic_categories_cli_gate=0
language_slice_diagnostic_explain_cli_gate=0
language_slice_diagnostic_explain_unknown_cli_gate=0
language_slice_diagnostic_formats_cli_gate=0
language_slice_formatter_library_gate=0
language_slice_formatter_cli_check_gate=0
language_slice_lsp_capabilities_gate=0
language_slice_lsp_stdio_gate=0
language_slice_lsp_document_diagnostics_gate=0
language_slice_package_manifest_cli_gate=0
language_slice_package_lockfile_cli_gate=0
language_slice_package_lock_command_gate=0
language_slice_package_metadata_diagnostic_gate=0
test_discipline_checked_files=0

usage() {
  cat <<'USAGE'
Usage: tools/compiler_acceptance.sh [--run] [--list-tests] [--check-plan] [--check-env] [--measurement-plan] [--write-measurement-plan PATH] [--allow-scale] [--tier focused|smoke|generated|properties|readiness|pareas|all]

Default mode is dry-run: commands are printed but not executed.
Use --list-tests to print/list test inventories instead of acceptance runs.
Use --check-plan to validate the planned command inventory without compiling or executing tests.
Use --check-env to validate command and environment prerequisites without compiling or executing tests.
Use --measurement-plan to print a no-run 5k/10k/20k performance/VRAM/readback measurement plan.
Use --write-measurement-plan PATH to write that no-run plan to PATH.
Use --allow-scale to execute generated, Pareas, or all-tier scale lanes.

Tiers:
  focused     Run the small CPU-only compile/model and behavior checkpoint.
  smoke       List generated gates and run the no-GPU capacity estimate gate.
  generated   Run parameterized generated compiler gates around 5k lines by default.
  properties  Run named deterministic randomized/property-style compiler tests.
  readiness   No-run inventory for the current production-readiness contracts.
  pareas      Run the optional Pareas comparison gate.
  all         Run focused, smoke, generated, properties, and pareas.

Relevant environment:
  LANIUS_GENERATED_LINES                         default 5000
  LANIUS_CAPACITY_STRESS_LINES                   default 5000
  LANIUS_CAPACITY_STRESS_SOURCE                  default expr-dense
  LANIUS_MAX_CAPACITY_STRESS_COMPILE_FLOOR_BYTES default 12 GiB
  LANIUS_ALLOW_LARGE_GENERATED_TESTS=1           opt into >20k generated gates
  LANIUS_GENERATED_GATE_COMMAND_TIMEOUT_MS        default 120000
  LANIUS_X86_READBACK_TIMEOUT_MS                  default 60000 inside generated/perf x86 gates
  LANIUS_PERF_CHECKPOINT_LINES                    default 5000,10000,20000; comma-separated checkpoints
  LANIUS_PERF_LINES                               default 5000 for future VRAM/perf plans
  LANIUS_PERF_SEED                                default 3235798765, matching gpu_compile_bench
  LANIUS_PERF_ITERS                               default 1; >3 requires large-test opt-in
  LANIUS_PERF_COMMAND_TIMEOUT_MS                  default 120000
  LANIUS_VRAM_SAMPLE_INTERVAL_MS                  default 250
  LANIUS_RESPONSIVENESS_PROBE_TIMEOUT_MS          default 2000
  LANIUS_PERF_OUTPUT_PATH                         default target/lanius-measurements/<source>-<phase>-<lines>l-<iters>i.stdout.txt
  LANIUS_PERFETTO_TRACE                           default target/lanius-measurements/<source>-<phase>-<lines>l-<iters>i.perfetto.json
  LANIUS_READBACK_SUMMARY_OUTPUT_PATH             default target/lanius-measurements/<source>-<phase>-<lines>l-<iters>i.readback.txt
  LANIUS_VRAM_OUTPUT_PATH                         default target/lanius-measurements/<source>-<phase>-<lines>l-<iters>i.vram.csv
  LANIUS_SOURCE_REPLAY_OUTPUT_PATH                default target/lanius-measurements/<source>-<phase>-<lines>l-<iters>i-s<seed>.source.lani
  LANIUS_SOURCE_SHA256_OUTPUT_PATH                default target/lanius-measurements/<source>-<phase>-<lines>l-<iters>i-s<seed>.source.sha256.txt
  LANIUS_BENCH_SHA256_OUTPUT_PATH                 default target/lanius-measurements/<source>-<phase>-<lines>l-<iters>i.bench.sha256.txt
  LANIUS_HARDWARE_OUTPUT_PATH                     default target/lanius-measurements/<source>-<phase>-<lines>l-<iters>i.hardware.txt
  LANIUS_COMMAND_ENV_OUTPUT_PATH                  default target/lanius-measurements/<source>-<phase>-<lines>l-<iters>i.command-env.txt
  LANIUS_COMMAND_STATUS_OUTPUT_PATH               default target/lanius-measurements/<source>-<phase>-<lines>l-<iters>i.status.txt
  LANIUS_RESPONSIVENESS_OUTPUT_PATH               default target/lanius-measurements/<source>-<phase>-<lines>l-<iters>i.responsiveness.txt
  LANIUS_RESOURCE_USAGE_OUTPUT_PATH               default target/lanius-measurements/<source>-<phase>-<lines>l-<iters>i.resource-usage.txt
  LANIUS_MEASUREMENT_SUMMARY_OUTPUT_PATH          default target/lanius-measurements/<source>-<phase>-<lines>l-<iters>i.summary.tsv
  LANIUS_PAREAS_SOURCE_PATH                       default target/lanius-measurements/pareas-<lines>l.par
  LANIUS_PAREAS_SOURCE_SHA256_OUTPUT_PATH         default target/lanius-measurements/pareas-<lines>l.source.sha256.txt
  LANIUS_PAREAS_BINARY_SHA256_OUTPUT_PATH         default target/lanius-measurements/pareas-<lines>l.compiler.sha256.txt
  LANIUS_PAREAS_OUTPUT_PATH                       default target/lanius-measurements/pareas-<lines>l.out
  LANIUS_PAREAS_STDOUT_PATH                       default target/lanius-measurements/pareas-<lines>l.stdout.txt
  NVIDIA_SMI                                     path to nvidia-smi
  LANIUS_REQUIRE_NVIDIA_SMI=1                    fail if nvidia-smi is unavailable
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
    --check-plan)
      check_plan=1
      shift
      ;;
    --check-env)
      check_env=1
      shift
      ;;
    --measurement-plan)
      measurement_plan=1
      shift
      ;;
    --write-measurement-plan)
      if [[ $# -lt 2 ]]; then
        echo "--write-measurement-plan requires a path" >&2
        exit 2
      fi
      measurement_plan=1
      measurement_plan_path="$2"
      shift 2
      ;;
    --write-measurement-plan=*)
      measurement_plan=1
      measurement_plan_path="${1#--write-measurement-plan=}"
      if [[ -z "$measurement_plan_path" ]]; then
        echo "--write-measurement-plan requires a non-empty path" >&2
        exit 2
      fi
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
  focused|smoke|generated|properties|readiness|pareas|all) ;;
  *)
    echo "unknown tier: $tier" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ "$check_plan" -eq 1 && "$run" -eq 1 ]]; then
  echo "--check-plan is a no-run verification mode and cannot be combined with --run" >&2
  exit 2
fi

if [[ "$check_plan" -eq 1 && "$list_tests" -eq 1 ]]; then
  echo "--check-plan verifies acceptance commands; use it without --list-tests" >&2
  exit 2
fi

if [[ "$check_env" -eq 1 && "$run" -eq 1 ]]; then
  echo "--check-env is a no-run verification mode and cannot be combined with --run" >&2
  exit 2
fi

if [[ "$check_env" -eq 1 && "$list_tests" -eq 1 ]]; then
  echo "--check-env validates the environment; use it without --list-tests" >&2
  exit 2
fi

if [[ "$measurement_plan" -eq 1 && "$run" -eq 1 ]]; then
  echo "--measurement-plan is a no-run report mode and cannot be combined with --run" >&2
  exit 2
fi

if [[ "$measurement_plan" -eq 1 && "$list_tests" -eq 1 ]]; then
  echo "--measurement-plan writes a measurement report; use it without --list-tests" >&2
  exit 2
fi

if [[ "$measurement_plan" -eq 1 && "$check_plan" -eq 1 ]]; then
  echo "--measurement-plan is separate from --check-plan" >&2
  exit 2
fi

if [[ "$measurement_plan" -eq 1 && "$check_env" -eq 1 ]]; then
  echo "--measurement-plan is separate from --check-env" >&2
  exit 2
fi

if [[ "$tier" == "readiness" && "$run" -eq 1 ]]; then
  echo "tier 'readiness' is a no-run tracking inventory; use focused, properties, smoke, generated, or pareas with --run for execution" >&2
  exit 2
fi

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

validate_test_name() {
  local fn_name="${1##*::}"
  if [[ ! "$fn_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "unsupported test name in acceptance plan: $1" >&2
    return 1
  fi
}

test_reference_filter_exists() {
  local test_name="$1"
  shift
  local fn_pattern="^[[:space:]]*(pub[[:space:]]+)?(async[[:space:]]+)?fn[[:space:]]+$test_name[[:space:]]*\\("
  local target_path
  for target_path in "$@"; do
    if [[ -f "$target_path" ]]; then
      if grep -qE "$fn_pattern" "$target_path"; then
        return 0
      fi
      if [[ "$target_path" == tests/*.rs ]]; then
        local sibling_dir="${target_path%.rs}"
        if [[ -d "$sibling_dir" ]] && grep -R -qE --include='*.rs' "$fn_pattern" "$sibling_dir"; then
          return 0
        fi
      fi
    elif [[ -d "$target_path" ]]; then
      if grep -R -qE --include='*.rs' "$fn_pattern" "$target_path"; then
        return 0
      fi
    fi
  done
  return 1
}

env_error() {
  echo "acceptance env error: $*" >&2
  env_errors=$((env_errors + 1))
}

env_note() {
  echo "# acceptance-env: $*"
}

check_required_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    env_note "$command_name=$(command -v "$command_name")"
  else
    env_error "required command '$command_name' was not found on PATH"
  fi
}

check_slangc() {
  if [[ -n "${SLANGC:-}" ]]; then
    if [[ -x "$SLANGC" ]]; then
      env_note "SLANGC=$SLANGC"
    else
      env_error "SLANGC is set to '$SLANGC', but that path is not executable"
    fi
  elif command -v slangc >/dev/null 2>&1; then
    env_note "slangc=$(command -v slangc)"
  else
    env_error "slangc was not found; set SLANGC to the Slang compiler used by the build"
  fi
}

positive_integer_env_value() {
  local -n output_ref="$1"
  local name="$2"
  local default_value="$3"
  local raw_value="${!name:-$default_value}"

  if [[ ! "$raw_value" =~ ^[0-9]+$ ]]; then
    env_error "$name must be a positive integer, got '$raw_value'"
    return 1
  fi
  if (( 10#$raw_value == 0 )); then
    env_error "$name must be greater than zero"
    return 1
  fi

  output_ref="$raw_value"
}

unsigned_integer_env_value() {
  local -n output_ref="$1"
  local name="$2"
  local default_value="$3"
  local raw_value="${!name:-$default_value}"

  if [[ ! "$raw_value" =~ ^[0-9]+$ ]]; then
    env_error "$name must be an unsigned integer, got '$raw_value'"
    return 1
  fi

  output_ref="$raw_value"
}

check_unsigned_integer_env() {
  local name="$1"
  local default_value="$2"
  local value

  unsigned_integer_env_value value "$name" "$default_value" || return
  env_note "$name=$value"
}

check_positive_integer_env() {
  local name="$1"
  local default_value="$2"
  local value

  positive_integer_env_value value "$name" "$default_value" || return
  env_note "$name=$value"
}

check_bounded_positive_integer_env() {
  local name="$1"
  local default_value="$2"
  local max_without_opt_in="$3"
  local value

  positive_integer_env_value value "$name" "$default_value" || return
  if (( 10#$value > max_without_opt_in )) && ! is_truthy "${LANIUS_ALLOW_LARGE_GENERATED_TESTS:-}"; then
    env_error "$name=$value exceeds the default guardrail $max_without_opt_in; set LANIUS_ALLOW_LARGE_GENERATED_TESTS=1 for an intentional larger generated gate"
    return
  fi

  env_note "$name=$value"
}

bounded_positive_integer_env_value() {
  local -n output_ref="$1"
  local name="$2"
  local default_value="$3"
  local max_without_opt_in="$4"
  local opt_in_name="$5"
  local guardrail_description="$6"
  local value

  positive_integer_env_value value "$name" "$default_value" || return 1
  if (( 10#$value > max_without_opt_in )) && ! is_truthy "${!opt_in_name:-}"; then
    env_error "$name=$value exceeds the default guardrail $max_without_opt_in for $guardrail_description; set $opt_in_name=1 for an intentional larger measurement"
    return 1
  fi

  output_ref="$value"
}

check_label_env() {
  local name="$1"
  local default_value="$2"
  local value="${!name:-$default_value}"

  if [[ -z "$value" ]]; then
    env_error "$name must not be empty"
    return
  fi

  if [[ ! "$value" =~ ^[A-Za-z0-9_.:-]+$ ]]; then
    env_error "$name contains unsupported characters: '$value'"
    return
  fi

  env_note "$name=$value"
}

label_env_value() {
  local -n output_ref="$1"
  local name="$2"
  local default_value="$3"
  local value="${!name:-$default_value}"

  if [[ -z "$value" ]]; then
    env_error "$name must not be empty"
    return 1
  fi

  if [[ ! "$value" =~ ^[A-Za-z0-9_.:-]+$ ]]; then
    env_error "$name contains unsupported characters: '$value'"
    return 1
  fi

  output_ref="$value"
}

path_env_value() {
  local -n output_ref="$1"
  local name="$2"
  local default_value="$3"
  local value="${!name:-$default_value}"

  if [[ -z "$value" ]]; then
    env_error "$name must not be empty"
    return 1
  fi

  case "$value" in
    *$'\n'*|*$'\r'*)
      env_error "$name must be a single path, got a value with a newline"
      return 1
      ;;
  esac

  output_ref="$value"
}

tier_uses_generated_env() {
  case "$tier" in
    smoke|generated|readiness|pareas|all) return 0 ;;
    *) return 1 ;;
  esac
}

tier_uses_pareas_env() {
  case "$tier" in
    generated|readiness|pareas|all) return 0 ;;
    *) return 1 ;;
  esac
}

find_pareas_bin() {
  if [[ -n "${PAREAS_BIN:-}" ]]; then
    if [[ -x "$PAREAS_BIN" ]]; then
      printf '%s\n' "$PAREAS_BIN"
    fi
    return
  fi

  if [[ -z "${HOME:-}" ]]; then
    return
  fi

  local candidate
  for candidate in \
    "$HOME/code/pareas/build-laniusc-cuda-futhark025/pareas" \
    "$HOME/code/pareas/build-laniusc-cuda/pareas" \
    "$HOME/code/pareas/build-laniusc-c/pareas" \
    "$HOME/code/pareas/build/pareas" \
    "$HOME/code/pareas/build/src/pareas" \
    "$HOME/code/pareas/builddir/pareas" \
    "$HOME/code/pareas/builddir/src/pareas"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
}

find_nvidia_smi() {
  if [[ -n "${NVIDIA_SMI:-}" ]]; then
    if [[ -x "$NVIDIA_SMI" ]]; then
      printf '%s\n' "$NVIDIA_SMI"
    fi
    return
  fi

  command -v nvidia-smi 2>/dev/null || true
}

check_nvidia_smi_environment() {
  local nvidia_smi

  nvidia_smi="$(find_nvidia_smi || true)"
  if [[ -n "$nvidia_smi" ]]; then
    env_note "nvidia-smi=$nvidia_smi"
  elif [[ -n "${NVIDIA_SMI:-}" ]]; then
    env_error "NVIDIA_SMI is set to '$NVIDIA_SMI', but that path is not executable"
  elif is_truthy "${LANIUS_REQUIRE_NVIDIA_SMI:-}"; then
    env_error "LANIUS_REQUIRE_NVIDIA_SMI=1 but nvidia-smi was not found; set NVIDIA_SMI or put nvidia-smi on PATH"
  else
    env_note "nvidia-smi optional: set NVIDIA_SMI or LANIUS_REQUIRE_NVIDIA_SMI=1 to require VRAM sampling"
  fi
}

perf_lines=
perf_checkpoint_lines=()
perf_seed=
perf_iters=
perf_timeout_ms=
perf_timeout_seconds=
perf_readback_timeout_ms=
perf_vram_sample_interval_ms=
perf_responsiveness_timeout_ms=
perf_responsiveness_timeout_seconds=
perf_source=
perf_phase=
perf_output_path=
perf_trace_path=
perf_readback_summary_path=
perf_vram_output_path=
perf_source_replay_output_path=
perf_source_sha256_output_path=
perf_bench_sha256_output_path=
perf_hardware_output_path=
perf_command_env_output_path=
perf_command_status_output_path=
perf_responsiveness_output_path=
perf_resource_usage_output_path=
perf_measurement_summary_output_path=
perf_pareas_source_path=
perf_pareas_source_sha256_output_path=
perf_pareas_binary_sha256_output_path=
perf_pareas_output_path=
perf_pareas_stdout_path=

ceil_ms_to_seconds() {
  local milliseconds="$1"
  printf '%s\n' $(((10#$milliseconds + 999) / 1000))
}

join_by_comma() {
  local IFS=,
  printf '%s\n' "$*"
}

parse_perf_checkpoint_lines_env() {
  local raw="${LANIUS_PERF_CHECKPOINT_LINES:-5000,10000,20000}"
  local checkpoint
  local canonical_checkpoint
  local previous_checkpoint=0
  local seen=","
  local -a parsed=()

  if [[ -z "$raw" ]]; then
    env_error "LANIUS_PERF_CHECKPOINT_LINES must not be empty"
    return 1
  fi

  IFS=',' read -r -a parsed <<<"$raw"
  perf_checkpoint_lines=()
  for checkpoint in "${parsed[@]}"; do
    if [[ ! "$checkpoint" =~ ^[0-9]+$ ]]; then
      env_error "LANIUS_PERF_CHECKPOINT_LINES contains non-integer checkpoint '$checkpoint'"
      continue
    fi
    canonical_checkpoint=$((10#$checkpoint))
    if (( canonical_checkpoint == 0 )); then
      env_error "LANIUS_PERF_CHECKPOINT_LINES contains zero; checkpoints must be greater than zero"
      continue
    fi
    if (( canonical_checkpoint > 20000 )) && ! is_truthy "${LANIUS_ALLOW_LARGE_GENERATED_TESTS:-}"; then
      env_error "LANIUS_PERF_CHECKPOINT_LINES checkpoint $canonical_checkpoint exceeds the default guardrail 20000; set LANIUS_ALLOW_LARGE_GENERATED_TESTS=1 for an intentional larger measurement"
      continue
    fi
    if [[ "$seen" == *",$canonical_checkpoint,"* ]]; then
      env_error "LANIUS_PERF_CHECKPOINT_LINES repeats checkpoint $canonical_checkpoint"
      continue
    fi
    if (( canonical_checkpoint <= previous_checkpoint )); then
      env_error "LANIUS_PERF_CHECKPOINT_LINES must be strictly ascending; checkpoint $canonical_checkpoint follows $previous_checkpoint"
      continue
    fi

    seen="${seen}${canonical_checkpoint},"
    perf_checkpoint_lines+=("$canonical_checkpoint")
    previous_checkpoint=$canonical_checkpoint
  done

  if [[ "${#perf_checkpoint_lines[@]}" -eq 0 ]]; then
    env_error "LANIUS_PERF_CHECKPOINT_LINES did not contain any usable checkpoints"
    return 1
  fi
}

perf_checkpoint_lines_include_primary_line() {
  local checkpoint

  for checkpoint in "${perf_checkpoint_lines[@]}"; do
    if (( 10#$checkpoint == 10#$perf_lines )); then
      return 0
    fi
  done

  return 1
}

prepare_perf_measurement_plan_values() {
  local errors_before="$env_errors"

  bounded_positive_integer_env_value \
    perf_lines \
    LANIUS_PERF_LINES \
    5000 \
    20000 \
    LANIUS_ALLOW_LARGE_GENERATED_TESTS \
    "performance/VRAM line count" || true
  bounded_positive_integer_env_value \
    perf_iters \
    LANIUS_PERF_ITERS \
    1 \
    3 \
    LANIUS_ALLOW_LARGE_GENERATED_TESTS \
    "performance/VRAM iteration count" || true
  unsigned_integer_env_value perf_seed LANIUS_PERF_SEED 3235798765 || true
  positive_integer_env_value perf_timeout_ms LANIUS_PERF_COMMAND_TIMEOUT_MS 120000 || true
  positive_integer_env_value perf_readback_timeout_ms LANIUS_X86_READBACK_TIMEOUT_MS 60000 || true
  positive_integer_env_value perf_vram_sample_interval_ms LANIUS_VRAM_SAMPLE_INTERVAL_MS 250 || true
  positive_integer_env_value perf_responsiveness_timeout_ms LANIUS_RESPONSIVENESS_PROBE_TIMEOUT_MS 2000 || true
  parse_perf_checkpoint_lines_env || true
  if [[ "${#perf_checkpoint_lines[@]}" -gt 0 ]] && [[ -n "$perf_lines" ]] && ! perf_checkpoint_lines_include_primary_line; then
    env_error "LANIUS_PERF_LINES=$perf_lines is not included in LANIUS_PERF_CHECKPOINT_LINES=$(join_by_comma "${perf_checkpoint_lines[@]}"); add it or set LANIUS_PERF_LINES to one planned checkpoint"
  fi
  label_env_value perf_source LANIUS_PERF_SOURCE call-graph || true
  label_env_value perf_phase LANIUS_PERF_PHASE x86 || true

  if [[ "$env_errors" -gt "$errors_before" ]]; then
    return 1
  fi

  local stem="${perf_source}-${perf_phase}-${perf_lines}l-${perf_iters}i"
  path_env_value \
    perf_output_path \
    LANIUS_PERF_OUTPUT_PATH \
    "target/lanius-measurements/${stem}.stdout.txt" || true
  path_env_value \
    perf_trace_path \
    LANIUS_PERFETTO_TRACE \
    "target/lanius-measurements/${stem}.perfetto.json" || true
  path_env_value \
    perf_readback_summary_path \
    LANIUS_READBACK_SUMMARY_OUTPUT_PATH \
    "target/lanius-measurements/${stem}.readback.txt" || true
  path_env_value \
    perf_vram_output_path \
    LANIUS_VRAM_OUTPUT_PATH \
    "target/lanius-measurements/${stem}.vram.csv" || true
  path_env_value \
    perf_source_replay_output_path \
    LANIUS_SOURCE_REPLAY_OUTPUT_PATH \
    "target/lanius-measurements/${stem}-s${perf_seed}.source.lani" || true
  path_env_value \
    perf_source_sha256_output_path \
    LANIUS_SOURCE_SHA256_OUTPUT_PATH \
    "target/lanius-measurements/${stem}-s${perf_seed}.source.sha256.txt" || true
  path_env_value \
    perf_bench_sha256_output_path \
    LANIUS_BENCH_SHA256_OUTPUT_PATH \
    "target/lanius-measurements/${stem}.bench.sha256.txt" || true
  path_env_value \
    perf_hardware_output_path \
    LANIUS_HARDWARE_OUTPUT_PATH \
    "target/lanius-measurements/${stem}.hardware.txt" || true
  path_env_value \
    perf_command_env_output_path \
    LANIUS_COMMAND_ENV_OUTPUT_PATH \
    "target/lanius-measurements/${stem}.command-env.txt" || true
  path_env_value \
    perf_command_status_output_path \
    LANIUS_COMMAND_STATUS_OUTPUT_PATH \
    "target/lanius-measurements/${stem}.status.txt" || true
  path_env_value \
    perf_responsiveness_output_path \
    LANIUS_RESPONSIVENESS_OUTPUT_PATH \
    "target/lanius-measurements/${stem}.responsiveness.txt" || true
  path_env_value \
    perf_resource_usage_output_path \
    LANIUS_RESOURCE_USAGE_OUTPUT_PATH \
    "target/lanius-measurements/${stem}.resource-usage.txt" || true
  path_env_value \
    perf_measurement_summary_output_path \
    LANIUS_MEASUREMENT_SUMMARY_OUTPUT_PATH \
    "target/lanius-measurements/${stem}.summary.tsv" || true
  path_env_value \
    perf_pareas_source_path \
    LANIUS_PAREAS_SOURCE_PATH \
    "target/lanius-measurements/pareas-${perf_lines}l.par" || true
  path_env_value \
    perf_pareas_source_sha256_output_path \
    LANIUS_PAREAS_SOURCE_SHA256_OUTPUT_PATH \
    "target/lanius-measurements/pareas-${perf_lines}l.source.sha256.txt" || true
  path_env_value \
    perf_pareas_binary_sha256_output_path \
    LANIUS_PAREAS_BINARY_SHA256_OUTPUT_PATH \
    "target/lanius-measurements/pareas-${perf_lines}l.compiler.sha256.txt" || true
  path_env_value \
    perf_pareas_output_path \
    LANIUS_PAREAS_OUTPUT_PATH \
    "target/lanius-measurements/pareas-${perf_lines}l.out" || true
  path_env_value \
    perf_pareas_stdout_path \
    LANIUS_PAREAS_STDOUT_PATH \
    "target/lanius-measurements/pareas-${perf_lines}l.stdout.txt" || true

  if [[ "$env_errors" -gt "$errors_before" ]]; then
    return 1
  fi

  perf_timeout_seconds="$(ceil_ms_to_seconds "$perf_timeout_ms")"
  perf_responsiveness_timeout_seconds="$(ceil_ms_to_seconds "$perf_responsiveness_timeout_ms")"
}

print_report_command() {
  local label="$1"
  shift
  printf '%s =' "$label"
  printf ' %q' "$@"
  printf '\n'
}

measurement_stem_for_line() {
  local line_count="$1"
  printf '%s-%s-%sl-%si' "$perf_source" "$perf_phase" "$line_count" "$perf_iters"
}

measurement_stdout_path_for_line() {
  local line_count="$1"
  if [[ "$line_count" == "$perf_lines" ]]; then
    printf '%s\n' "$perf_output_path"
  else
    printf 'target/lanius-measurements/%s.stdout.txt\n' "$(measurement_stem_for_line "$line_count")"
  fi
}

measurement_trace_path_for_line() {
  local line_count="$1"
  if [[ "$line_count" == "$perf_lines" ]]; then
    printf '%s\n' "$perf_trace_path"
  else
    printf 'target/lanius-measurements/%s.perfetto.json\n' "$(measurement_stem_for_line "$line_count")"
  fi
}

measurement_readback_summary_path_for_line() {
  local line_count="$1"
  if [[ "$line_count" == "$perf_lines" ]]; then
    printf '%s\n' "$perf_readback_summary_path"
  else
    printf 'target/lanius-measurements/%s.readback.txt\n' "$(measurement_stem_for_line "$line_count")"
  fi
}

measurement_vram_path_for_line() {
  local line_count="$1"
  if [[ "$line_count" == "$perf_lines" ]]; then
    printf '%s\n' "$perf_vram_output_path"
  else
    printf 'target/lanius-measurements/%s.vram.csv\n' "$(measurement_stem_for_line "$line_count")"
  fi
}

measurement_source_replay_path_for_line() {
  local line_count="$1"
  if [[ "$line_count" == "$perf_lines" ]]; then
    printf '%s\n' "$perf_source_replay_output_path"
  else
    printf 'target/lanius-measurements/%s-s%s.source.lani\n' "$(measurement_stem_for_line "$line_count")" "$perf_seed"
  fi
}

measurement_source_sha256_path_for_line() {
  local line_count="$1"
  if [[ "$line_count" == "$perf_lines" ]]; then
    printf '%s\n' "$perf_source_sha256_output_path"
  else
    printf 'target/lanius-measurements/%s-s%s.source.sha256.txt\n' "$(measurement_stem_for_line "$line_count")" "$perf_seed"
  fi
}

measurement_bench_sha256_path_for_line() {
  local line_count="$1"
  if [[ "$line_count" == "$perf_lines" ]]; then
    printf '%s\n' "$perf_bench_sha256_output_path"
  else
    printf 'target/lanius-measurements/%s.bench.sha256.txt\n' "$(measurement_stem_for_line "$line_count")"
  fi
}

measurement_hardware_path_for_line() {
  local line_count="$1"
  if [[ "$line_count" == "$perf_lines" ]]; then
    printf '%s\n' "$perf_hardware_output_path"
  else
    printf 'target/lanius-measurements/%s.hardware.txt\n' "$(measurement_stem_for_line "$line_count")"
  fi
}

measurement_command_env_path_for_line() {
  local line_count="$1"
  if [[ "$line_count" == "$perf_lines" ]]; then
    printf '%s\n' "$perf_command_env_output_path"
  else
    printf 'target/lanius-measurements/%s.command-env.txt\n' "$(measurement_stem_for_line "$line_count")"
  fi
}

measurement_command_status_path_for_line() {
  local line_count="$1"
  if [[ "$line_count" == "$perf_lines" ]]; then
    printf '%s\n' "$perf_command_status_output_path"
  else
    printf 'target/lanius-measurements/%s.status.txt\n' "$(measurement_stem_for_line "$line_count")"
  fi
}

measurement_responsiveness_path_for_line() {
  local line_count="$1"
  if [[ "$line_count" == "$perf_lines" ]]; then
    printf '%s\n' "$perf_responsiveness_output_path"
  else
    printf 'target/lanius-measurements/%s.responsiveness.txt\n' "$(measurement_stem_for_line "$line_count")"
  fi
}

measurement_resource_usage_path_for_line() {
  local line_count="$1"
  if [[ "$line_count" == "$perf_lines" ]]; then
    printf '%s\n' "$perf_resource_usage_output_path"
  else
    printf 'target/lanius-measurements/%s.resource-usage.txt\n' "$(measurement_stem_for_line "$line_count")"
  fi
}

measurement_summary_path_for_line() {
  local line_count="$1"
  if [[ "$line_count" == "$perf_lines" ]]; then
    printf '%s\n' "$perf_measurement_summary_output_path"
  else
    printf 'target/lanius-measurements/%s.summary.tsv\n' "$(measurement_stem_for_line "$line_count")"
  fi
}

pareas_source_path_for_line() {
  local line_count="$1"
  if [[ "$line_count" == "$perf_lines" ]]; then
    printf '%s\n' "$perf_pareas_source_path"
  else
    printf 'target/lanius-measurements/pareas-%sl.par\n' "$line_count"
  fi
}

pareas_source_sha256_path_for_line() {
  local line_count="$1"
  if [[ "$line_count" == "$perf_lines" ]]; then
    printf '%s\n' "$perf_pareas_source_sha256_output_path"
  else
    printf 'target/lanius-measurements/pareas-%sl.source.sha256.txt\n' "$line_count"
  fi
}

pareas_binary_sha256_path_for_line() {
  local line_count="$1"
  if [[ "$line_count" == "$perf_lines" ]]; then
    printf '%s\n' "$perf_pareas_binary_sha256_output_path"
  else
    printf 'target/lanius-measurements/pareas-%sl.compiler.sha256.txt\n' "$line_count"
  fi
}

pareas_output_path_for_line() {
  local line_count="$1"
  if [[ "$line_count" == "$perf_lines" ]]; then
    printf '%s\n' "$perf_pareas_output_path"
  else
    printf 'target/lanius-measurements/pareas-%sl.out\n' "$line_count"
  fi
}

pareas_stdout_path_for_line() {
  local line_count="$1"
  if [[ "$line_count" == "$perf_lines" ]]; then
    printf '%s\n' "$perf_pareas_stdout_path"
  else
    printf 'target/lanius-measurements/pareas-%sl.stdout.txt\n' "$line_count"
  fi
}

measurement_required_artifacts() {
  printf '%s\n' 'lanius_stdout,perfetto_trace,readback_summary,vram_csv,source_replay,source_sha256,bench_binary_sha256,hardware_identity,command_environment,command_status,responsiveness_probe,resource_usage,measurement_summary'
}

measurement_optional_comparison_artifacts() {
  printf '%s\n' 'pareas_source,pareas_source_sha256,pareas_binary_sha256,pareas_output,pareas_stdout'
}

measurement_artifact_manifest_schema() {
  printf '%s\n' 'lanius.measurement-artifacts.v1'
}

measurement_required_artifact_manifest_fields() {
  printf '%s\n' 'checkpoint,name,required,path,producer,status_field,status_artifact,claim,claim_source,claim_fields'
}

measurement_timing_policy() {
  printf '%s\n' 'compile-latency-claims-use-benchmark-best-ms-wall-time-is-provenance'
}

measurement_cold_start_policy() {
  printf '%s\n' 'excluded-from-claimable-compile-latency-captured-as-wrapper-wall-time'
}

measurement_compile_latency_claim_source() {
  printf '%s\n' 'benchmark-stdout-best-ms-local-run-only'
}

measurement_runtime_validation_policy() {
  printf '%s\n' 'validate-output-only-not-runtime-performance-claim'
}

measurement_claim_provenance_schema() {
  printf '%s\n' 'lanius.measurement-claim-provenance.v1'
}

measurement_baseline_separation_schema() {
  printf '%s\n' 'lanius.measurement-baseline-separation.v1'
}

measurement_required_claim_provenance_fields() {
  printf '%s\n' 'claim_provenance_schema,baseline_separation_schema,paper_baseline_policy,paper_baseline_numbers_status,local_evidence_status_policy,local_performance_claim_policy,local_performance_claim_source,local_performance_claim_status,local_performance_claim_blockers,local_vram_claim_source,local_pareas_claim_source,scaling_claim_policy,scaling_claim_source,scaling_claim_status,scaling_claim_blockers,paper_pass_order_schema,paper_pass_order_source,paper_pass_order,paper_pass_alignment_policy,paper_pass_alignment_status,paper_pass_alignment_blockers'
}

measurement_paper_baseline_policy() {
  printf '%s\n' 'reference-only-not-local-performance-evidence'
}

measurement_paper_baseline_numbers_status() {
  printf '%s\n' 'reference-only-not-ingested'
}

measurement_local_evidence_status_policy() {
  printf '%s\n' 'claimable-only-from-fresh-local-artifacts'
}

measurement_local_performance_claim_policy() {
  printf '%s\n' 'blocked-until-pass-contracts-claimable-and-local-artifacts-complete'
}

measurement_local_performance_claim_source() {
  printf '%s\n' 'benchmark-stdout-best-ms-plus-local-artifact-freshness'
}

measurement_local_performance_claim_status() {
  if [[ "$(measurement_pass_contract_readiness_status)" == "claimable" ]]; then
    printf '%s\n' 'artifact-dependent'
  else
    printf '%s\n' 'blocked'
  fi
}

measurement_local_performance_claim_blockers() {
  if [[ "$(measurement_pass_contract_readiness_status)" == "claimable" ]]; then
    printf '%s\n' 'local_artifacts_and_repeatability_must_be_complete'
  else
    printf 'pass_contracts:%s:loop_%s:fallback_%s:claim_%s:%s\n' \
      "$(measurement_pass_contract_readiness_status)" \
      "$(measurement_pass_contract_loop_status)" \
      "$(measurement_pass_contract_fallback_status)" \
      "$(measurement_pass_contract_claim_status)" \
      "$(measurement_pass_contract_claim_blockers)"
  fi
}

measurement_local_vram_claim_source() {
  printf '%s\n' 'nvidia-smi-local-csv-plus-status-artifact'
}

measurement_local_pareas_claim_source() {
  printf '%s\n' 'local-pareas-source-output-stdout-compiler-hash'
}

measurement_scaling_claim_source() {
  printf '%s\n' 'multi-checkpoint-local-artifacts-plus-claimable-parallel-pass-contracts-and-paper-order'
}

measurement_scaling_claim_policy() {
  printf '%s\n' 'no-scaling-claims-while-pass-contracts-or-paper-alignment-blocked'
}

measurement_scaling_claim_status() {
  printf '%s\n' 'blocked'
}

measurement_scaling_claim_blocker_list() {
  local blockers=multi_checkpoint_rollup_required
  if [[ "$(measurement_paper_pass_alignment_status)" != "claimable" ]]; then
    blockers="paper_pass_alignment:$(measurement_paper_pass_alignment_status):$(measurement_paper_pass_alignment_blockers),${blockers}"
  elif [[ "$(measurement_pass_contract_readiness_status)" != "claimable" ]]; then
    blockers="pass_contracts:$(measurement_pass_contract_readiness_status):loop_$(measurement_pass_contract_loop_status):fallback_$(measurement_pass_contract_fallback_status):claim_$(measurement_pass_contract_claim_status):$(measurement_pass_contract_claim_blockers),${blockers}"
  fi
  printf '%s\n' "$blockers"
}

measurement_scaling_claim_blockers() {
  if [[ "$(measurement_pass_contract_readiness_status)" == "claimable" &&
    "$(measurement_paper_pass_alignment_status)" == "claimable" ]]; then
    printf '%s\n' 'multi_checkpoint_rollup_required'
  else
    printf '%s\n' "$(measurement_scaling_claim_blocker_list)"
  fi
}

measurement_paper_pass_order_schema() {
  printf '%s\n' 'lanius.paper-pass-order.v1'
}

measurement_paper_pass_order_source() {
  printf '%s\n' 'docs/CompilationOnTheGPU.md:figure-1;docs/ParallelCodeGeneration.md:chapter-3'
}

measurement_paper_pass_order() {
  printf '%s\n' 'lexical_analysis,parsing,semantic_analysis,intermediate_code_generation,optimization,machine_code_generation'
}

measurement_paper_pass_alignment_policy() {
  printf '%s\n' 'parallel-pass-contracts-must-cover-paper-order-before-scale-claims'
}

measurement_paper_pass_alignment_status() {
  printf '%s\n' 'blocked'
}

measurement_paper_pass_alignment_blockers() {
  printf 'optimization_contract_narrow_single_pass_dead_values,pass_contracts:%s:loop_%s:fallback_%s:claim_%s:%s\n' \
    "$(measurement_pass_contract_readiness_status)" \
    "$(measurement_pass_contract_loop_status)" \
    "$(measurement_pass_contract_fallback_status)" \
    "$(measurement_pass_contract_claim_status)" \
    "$(measurement_pass_contract_claim_blockers)"
}

measurement_parallel_pass_contract_schema() {
  printf '%s\n' 'lanius.parallel-pass-contracts.v1'
}

measurement_parallel_pass_contract_policy() {
  printf '%s\n' 'scale-claims-require-behavioral-record-boundary-evidence'
}

measurement_parallel_pass_contract_groups() {
  printf '%s\n' 'record_invariant,semantic_contract,execution_contract,measurement_scaffold'
}

measurement_parallel_pass_contract_order_policy() {
  printf '%s\n' 'paper-pass-order-record-boundary-sequence'
}

measurement_parallel_pass_contract_execution_order() {
  measurement_parallel_pass_contract_groups
}

measurement_required_parallel_pass_contract_fields() {
  printf '%s\n' 'contract_schema,pass_group,paper_pass_stage,record_boundary,parallel_primitives,evidence_shape,loop_status,fallback_status,claim_boundary'
}

measurement_pass_contract_status_schema() {
  printf '%s\n' 'lanius.parallel-pass-contract-status.v1'
}

measurement_pass_contract_loop_policy() {
  printf '%s\n' 'scale-claims-require-unbounded-pass-loops'
}

measurement_pass_contract_loop_status() {
  printf '%s\n' 'bounded'
}

measurement_pass_contract_fallback_status() {
  printf '%s\n' 'fail-closed'
}

measurement_pass_contract_claim_status() {
  printf '%s\n' 'blocked'
}

measurement_pass_contract_claim_blockers() {
  printf '%s\n' 'bounded_pass_loops,fail_closed_passes'
}

measurement_pass_contract_readiness_status() {
  if [[ "$(measurement_pass_contract_loop_status)" == "unbounded" &&
    "$(measurement_pass_contract_fallback_status)" == "none" &&
    "$(measurement_pass_contract_claim_status)" == "claimable" ]]; then
    printf '%s\n' 'claimable'
  else
    printf '%s\n' 'blocked'
  fi
}

measurement_required_pass_contract_status_fields() {
  printf '%s\n' 'pass_contract_status_schema,pass_contract_loop_policy,pass_contract_loop_status,pass_contract_fallback_status,pass_contract_claim_status,pass_contract_claim_blockers,pass_contract_readiness_status'
}

measurement_timeout_provenance_schema() {
  printf '%s\n' 'lanius.timeout-provenance.v1'
}

measurement_required_timeout_provenance_fields() {
  printf '%s\n' 'timeout_provenance_schema,timeout_scope,timeout_ms,timeout_seconds,timeout_source,timeout_enforced_by,timeout_exit_code,timeout_exit_code_means_timed_out'
}

measurement_timeout_scope() {
  printf '%s\n' 'wrapper-process-wall-clock-bound'
}

measurement_timeout_source() {
  printf '%s\n' 'LANIUS_PERF_COMMAND_TIMEOUT_MS'
}

measurement_timeout_enforced_by() {
  printf '%s\n' 'timeout'
}

measurement_timeout_exit_code() {
  printf '%s\n' '124'
}

measurement_timeout_exit_code_means_timed_out() {
  printf '%s\n' 'true'
}

measurement_readback_summary_schema() {
  printf '%s\n' 'lanius.readback-summary.v1'
}

measurement_required_readback_summary_fields() {
  printf '%s\n' 'readback_summary_schema,line_count,source,phase,target,trace_path,readback_timeout_ms,span_count,total_ms,max_span_ms'
}

measurement_vram_csv_schema() {
  printf '%s\n' 'lanius.vram-csv.v1'
}

measurement_required_vram_csv_columns() {
  printf '%s\n' 'timestamp,index,name,memory.used,memory.total,utilization.gpu'
}

measurement_hardware_identity_schema() {
  printf '%s\n' 'lanius.hardware-identity.v1'
}

measurement_required_hardware_identity_fields() {
  printf '%s\n' 'hardware_identity_schema,target,uname,nvidia_smi_status'
}

measurement_command_environment_schema() {
  printf '%s\n' 'lanius.command-environment.v1'
}

measurement_required_command_environment_fields() {
  printf '%s\n' 'command_environment_schema,timestamp_utc,cwd,line_count,source,phase,target,iterations,measurement_timing_policy,cold_start_policy,compile_latency_claim_source,runtime_validation_policy,claim_provenance_schema,baseline_separation_schema,paper_baseline_policy,paper_baseline_numbers_status,local_evidence_status_policy,local_performance_claim_policy,local_performance_claim_source,local_performance_claim_status,local_performance_claim_blockers,local_vram_claim_source,local_pareas_claim_source,scaling_claim_policy,scaling_claim_source,scaling_claim_status,scaling_claim_blockers,paper_pass_order_schema,paper_pass_order_source,paper_pass_order,paper_pass_alignment_policy,paper_pass_alignment_status,paper_pass_alignment_blockers,parallel_pass_contract_schema,parallel_pass_contract_policy,parallel_pass_contract_groups,parallel_pass_contract_order_policy,parallel_pass_contract_execution_order,pass_contract_status_schema,pass_contract_loop_policy,pass_contract_loop_status,pass_contract_fallback_status,pass_contract_claim_status,pass_contract_claim_blockers,pass_contract_readiness_status,timeout_provenance_schema,timeout_scope,timeout_source,timeout_ms,timeout_seconds,readback_timeout_ms,vram_sample_interval_ms,source_seed,responsiveness_probe_timeout_ms,responsiveness_probe_timeout_seconds,git_head,rustc_version,cargo_version,slangc_version'
}

measurement_responsiveness_probe_schema() {
  printf '%s\n' 'lanius.responsiveness-probe.v1'
}

measurement_required_responsiveness_probe_fields() {
  printf '%s\n' 'responsiveness_probe_schema,line_count,source,phase,target,timeout_ms,timeout_seconds,probe_command,probe_exit_status,responsive,elapsed_ms'
}

measurement_command_status_schema() {
  printf '%s\n' 'lanius.command-status.v1'
}

measurement_required_status_fields() {
  printf '%s\n' 'command_status_schema,lanius_exit_status,lanius_wall_elapsed_ms,measurement_timing_policy,cold_start_policy,compile_latency_claim_source,runtime_validation_policy,timeout_provenance_schema,timeout_scope,timeout_ms,timeout_seconds,timeout_source,timeout_enforced_by,timeout_exit_code,timeout_exit_code_means_timed_out,line_count,source,phase,target,source_seed,iterations,readback_timeout_ms,machine_responsive_after,responsiveness_probe_status,responsiveness_probe_path,lanius_stdout_path,perfetto_trace_path,resource_usage_status,resource_usage_path'
}

measurement_optional_status_fields() {
  printf '%s\n' 'nvidia_smi_exit_status,vram_sample_interval_ms,vram_output_path,pareas_exit_status,pareas_wall_elapsed_ms,pareas_bin_path,pareas_source_path,pareas_output_path,pareas_stdout_path'
}

measurement_required_summary_fields() {
  printf '%s\n' 'measurement_summary_schema,line_count,source,phase,target,evidence_provenance,measurement_evidence_policy,paper_numbers_accepted,comparison_baseline_policy,freshness_policy,measurement_timing_policy,cold_start_policy,compile_latency_claim_source,runtime_validation_policy,claim_provenance_schema,baseline_separation_schema,paper_baseline_policy,paper_baseline_numbers_status,local_evidence_status_policy,local_performance_claim_policy,local_performance_claim_source,local_performance_claim_status,local_performance_claim_blockers,local_vram_claim_source,local_pareas_claim_source,scaling_claim_policy,scaling_claim_source,scaling_claim_status,scaling_claim_blockers,paper_pass_order_schema,paper_pass_order_source,paper_pass_order,paper_pass_alignment_policy,paper_pass_alignment_status,paper_pass_alignment_blockers,parallel_pass_contract_schema,parallel_pass_contract_policy,parallel_pass_contract_groups,parallel_pass_contract_order_policy,parallel_pass_contract_execution_order,pass_contract_status_schema,pass_contract_loop_policy,pass_contract_loop_status,pass_contract_fallback_status,pass_contract_claim_status,pass_contract_claim_blockers,pass_contract_readiness_status,timeout_provenance_schema,timeout_scope,timeout_source,timeout_enforced_by,timeout_exit_code,timeout_exit_code_means_timed_out,source_control_policy,source_control_state,source_control_revision,repeatability_policy,minimum_iterations_for_claim,repeatability_status,required_artifacts_complete,missing_required_artifacts,evidence_status_schema,local_performance_evidence_status,local_performance_claim_status,local_performance_claim_blockers,local_readback_evidence_status,local_vram_evidence_status,local_pareas_evidence_status,scaling_claim_status,scaling_claim_blockers,production_readiness_evidence_complete,production_readiness_blockers,evidence_freshness_schema,evidence_freshness_status,stale_artifacts,stale_artifact_checks,claim_readiness_schema,claim_readiness_policy,claim_readiness_required_evidence_classes,claim_readiness_required_statuses,claim_readiness_status,claimable_measurement_claims,claim_readiness_blockers,claim_scope_policy,claim_scope_key,source_seed,iterations,timeout_ms,timeout_seconds,readback_timeout_ms,vram_sample_interval_ms,lanius_exit_status,timed_out,lanius_wall_elapsed_ms,best_ms,throughput_lines_per_second,readback_span_count,readback_total_ms,readback_max_span_ms,max_vram_bytes,nvidia_smi_exit_status,resource_user_seconds,resource_system_seconds,resource_max_rss_kb,resource_usage_status,source_replay_line_count,source_sha256,bench_binary_sha256,hardware_identity_sha256,command_environment_sha256,machine_responsive_after,responsiveness_probe_status,pareas_exit_status,pareas_timed_out,pareas_wall_elapsed_ms,pareas_source_sha256,pareas_binary_sha256,lanius_pareas_wall_ratio,lanius_stdout_path,perfetto_trace_path,readback_summary_path,vram_output_path,source_replay_path,source_sha256_path,bench_binary_sha256_path,hardware_output_path,command_env_path,command_status_path,responsiveness_probe_path,resource_usage_path,pareas_source_path,pareas_source_sha256_path,pareas_binary_sha256_path,pareas_output_path,pareas_stdout_path'
}

measurement_evidence_status_schema() {
  printf '%s\n' 'lanius.measurement-evidence-status.v1'
}

measurement_required_evidence_status_fields() {
  printf '%s\n' 'evidence_status_schema,local_performance_evidence_status,local_performance_claim_status,local_performance_claim_blockers,local_readback_evidence_status,local_vram_evidence_status,local_pareas_evidence_status,scaling_claim_status,scaling_claim_blockers,pass_contract_claim_status,pass_contract_claim_blockers,pass_contract_readiness_status,production_readiness_evidence_complete,production_readiness_blockers'
}

measurement_evidence_freshness_schema() {
  printf '%s\n' 'lanius.measurement-evidence-freshness.v1'
}

measurement_required_evidence_freshness_fields() {
  printf '%s\n' 'evidence_freshness_schema,evidence_freshness_status,stale_artifacts,stale_artifact_checks'
}

measurement_claim_readiness_schema() {
  printf '%s\n' 'lanius.measurement-claim-readiness.v1'
}

measurement_claim_readiness_policy() {
  printf '%s\n' 'complete-local-evidence-only'
}

measurement_claim_scope_policy() {
  printf '%s\n' 'exact-local-checkpoint-hardware-source-binary-only'
}

measurement_source_control_policy() {
  printf '%s\n' 'git-head-plus-status-in-command-environment-hash'
}

measurement_repeatability_policy() {
  printf '%s\n' 'claimable-metrics-require-at-least-three-iterations'
}

measurement_minimum_iterations_for_claim() {
  printf '%s\n' '3'
}

measurement_required_claim_readiness_fields() {
  printf '%s\n' 'claim_readiness_schema,claim_readiness_policy,claim_readiness_required_evidence_classes,claim_readiness_required_statuses,claim_readiness_status,claimable_measurement_claims,claim_readiness_blockers'
}

measurement_claim_readiness_required_evidence_classes() {
  printf '%s\n' 'local_performance,local_performance_claim,local_readback,local_vram,local_pareas,resource_usage,responsiveness,source_control,freshness,repeatability,paper_pass_alignment,parallel_pass_contracts,scaling_claim'
}

measurement_claim_readiness_required_statuses() {
  printf '%s\n' 'local_performance_evidence_status=complete;local_performance_claim_status=claimable;local_readback_evidence_status=complete;local_vram_evidence_status=complete;local_pareas_evidence_status=complete;resource_usage_status=0;machine_responsive_after=true;source_control_state=clean-or-dirty;source_control_revision=local-git-commit-sha;evidence_freshness_status=complete;repeatability_status=complete;paper_pass_alignment_status=claimable;pass_contract_loop_status=unbounded;pass_contract_fallback_status=none;pass_contract_claim_status=claimable;pass_contract_readiness_status=claimable;scaling_claim_status=claimable'
}

measurement_claim_fields_for_artifact() {
  case "$1" in
    lanius_stdout)
      printf '%s\n' 'best_ms,throughput_lines_per_second'
      ;;
    perfetto_trace)
      printf '%s\n' 'readback_span_count,readback_total_ms,readback_max_span_ms'
      ;;
    readback_summary)
      printf '%s\n' 'readback_span_count,readback_total_ms,readback_max_span_ms'
      ;;
    vram_csv)
      printf '%s\n' 'max_vram_bytes,nvidia_smi_exit_status'
      ;;
    source_replay)
      printf '%s\n' 'source_replay_path,source_replay_line_count'
      ;;
    source_sha256)
      printf '%s\n' 'source_sha256'
      ;;
    bench_binary_sha256)
      printf '%s\n' 'bench_binary_sha256'
      ;;
    hardware_identity)
      printf '%s\n' 'hardware_identity_sha256'
      ;;
    command_environment)
      printf '%s\n' 'command_environment_sha256,source_control_state,source_control_revision,paper_baseline_numbers_status,local_evidence_status_policy,local_performance_claim_status,local_performance_claim_blockers,scaling_claim_status,scaling_claim_blockers,paper_pass_order,paper_pass_alignment_status,paper_pass_alignment_blockers,pass_contract_loop_status,pass_contract_fallback_status,pass_contract_claim_status,pass_contract_claim_blockers,pass_contract_readiness_status'
      ;;
    command_status)
      printf '%s\n' 'lanius_exit_status,timed_out,lanius_wall_elapsed_ms,measurement_timing_policy,cold_start_policy,compile_latency_claim_source,runtime_validation_policy,timeout_provenance_schema,timeout_scope,timeout_ms,timeout_seconds,timeout_source,timeout_enforced_by,timeout_exit_code,timeout_exit_code_means_timed_out,nvidia_smi_exit_status,pareas_exit_status,pareas_wall_elapsed_ms,machine_responsive_after,resource_usage_status'
      ;;
    responsiveness_probe)
      printf '%s\n' 'machine_responsive_after,responsiveness_probe_status'
      ;;
    resource_usage)
      printf '%s\n' 'resource_user_seconds,resource_system_seconds,resource_max_rss_kb,resource_usage_status'
      ;;
    measurement_summary)
      printf '%s\n' 'production_readiness_evidence_complete,production_readiness_blockers,claim_readiness_status,claimable_measurement_claims,claim_readiness_blockers,measurement_timing_policy,cold_start_policy,compile_latency_claim_source,runtime_validation_policy,claim_provenance_schema,baseline_separation_schema,paper_baseline_policy,paper_baseline_numbers_status,local_evidence_status_policy,local_performance_claim_policy,local_performance_claim_source,local_performance_claim_status,local_performance_claim_blockers,local_vram_claim_source,local_pareas_claim_source,scaling_claim_policy,scaling_claim_source,scaling_claim_status,scaling_claim_blockers,paper_pass_order_schema,paper_pass_order_source,paper_pass_order,paper_pass_alignment_policy,paper_pass_alignment_status,paper_pass_alignment_blockers,parallel_pass_contract_schema,parallel_pass_contract_policy,parallel_pass_contract_groups,parallel_pass_contract_order_policy,parallel_pass_contract_execution_order,pass_contract_status_schema,pass_contract_loop_policy,pass_contract_loop_status,pass_contract_fallback_status,pass_contract_claim_status,pass_contract_claim_blockers,pass_contract_readiness_status,timeout_provenance_schema,timeout_scope,timeout_ms,timeout_seconds,timeout_source,timeout_enforced_by,timeout_exit_code,timeout_exit_code_means_timed_out'
      ;;
    pareas_source)
      printf '%s\n' 'pareas_source_path'
      ;;
    pareas_source_sha256)
      printf '%s\n' 'pareas_source_sha256'
      ;;
    pareas_binary_sha256)
      printf '%s\n' 'pareas_binary_sha256'
      ;;
    pareas_output)
      printf '%s\n' 'pareas_exit_status'
      ;;
    pareas_stdout)
      printf '%s\n' 'pareas_wall_elapsed_ms,lanius_pareas_wall_ratio'
      ;;
    *)
      printf '%s\n' 'none'
      ;;
  esac
}

print_checkpoint_evidence_artifact() {
  local checkpoint="$1"
  local name="$2"
  local required="$3"
  local path="$4"
  local producer="$5"
  local status_field="$6"
  local status_artifact="$7"
  local claim="$8"
  local claim_source
  shift 8
  if [[ "$required" == "true" ]]; then
    if [[ "$name" == "measurement_summary" ]]; then
      claim_source=derived_local_artifacts
    else
      claim_source=local_artifact
    fi
  else
    claim_source=optional_local_comparison_artifact
  fi

  printf '  evidence_artifact: checkpoint=%s name=%s required=%s path=%q producer=%s status_field=%s status_artifact=%s claim=%s claim_source=%s claim_fields=%s' \
    "$checkpoint" \
    "$name" \
    "$required" \
    "$path" \
    "$producer" \
    "$status_field" \
    "$status_artifact" \
    "$claim" \
    "$claim_source" \
    "$(measurement_claim_fields_for_artifact "$name")"
  local field
  for field in "$@"; do
    printf ' %s' "$field"
  done
  printf '\n'
}

emit_perf_checkpoint_plan() {
  local line_count="$1"
  local nvidia_smi="$2"
  local pareas_bin="$3"
  local stdout_path
  local trace_path
  local readback_summary_path
  local vram_path
  local source_replay_path
  local source_sha256_path
  local bench_sha256_path
  local hardware_path
  local command_env_path
  local command_status_path
  local responsiveness_path
  local resource_usage_path
  local measurement_summary_path
  local pareas_source_path
  local pareas_source_sha256_path
  local pareas_binary_sha256_path
  local pareas_output_path
  local pareas_stdout_path

  stdout_path="$(measurement_stdout_path_for_line "$line_count")"
  trace_path="$(measurement_trace_path_for_line "$line_count")"
  readback_summary_path="$(measurement_readback_summary_path_for_line "$line_count")"
  vram_path="$(measurement_vram_path_for_line "$line_count")"
  source_replay_path="$(measurement_source_replay_path_for_line "$line_count")"
  source_sha256_path="$(measurement_source_sha256_path_for_line "$line_count")"
  bench_sha256_path="$(measurement_bench_sha256_path_for_line "$line_count")"
  hardware_path="$(measurement_hardware_path_for_line "$line_count")"
  command_env_path="$(measurement_command_env_path_for_line "$line_count")"
  command_status_path="$(measurement_command_status_path_for_line "$line_count")"
  responsiveness_path="$(measurement_responsiveness_path_for_line "$line_count")"
  resource_usage_path="$(measurement_resource_usage_path_for_line "$line_count")"
  measurement_summary_path="$(measurement_summary_path_for_line "$line_count")"
  pareas_source_path="$(pareas_source_path_for_line "$line_count")"
  pareas_source_sha256_path="$(pareas_source_sha256_path_for_line "$line_count")"
  pareas_binary_sha256_path="$(pareas_binary_sha256_path_for_line "$line_count")"
  pareas_output_path="$(pareas_output_path_for_line "$line_count")"
  pareas_stdout_path="$(pareas_stdout_path_for_line "$line_count")"

  printf 'checkpoint_%sl:\n' "$line_count"
  printf '  line_count: %s\n' "$line_count"
  printf '  iterations: %s\n' "$perf_iters"
  printf '  timeout_ms: %s\n' "$perf_timeout_ms"
  printf '  timeout_seconds: %s\n' "$perf_timeout_seconds"
  printf '  readback_timeout_ms: %s\n' "$perf_readback_timeout_ms"
  printf '  vram_sample_interval_ms: %s\n' "$perf_vram_sample_interval_ms"
  printf '  responsiveness_probe_timeout_ms: %s\n' "$perf_responsiveness_timeout_ms"
  printf '  responsiveness_probe_timeout_seconds: %s\n' "$perf_responsiveness_timeout_seconds"
  printf '  source: %s\n' "$perf_source"
  printf '  source_seed: %s\n' "$perf_seed"
  printf '  phase: %s\n' "$perf_phase"
  printf '  target: x86_64-elf\n'
  printf '  gpu_timing_env: LANIUS_GPU_TIMING=1 LANIUS_GPU_COMPILE_HOST_TIMING=1\n'
  printf '  measurement_timing_policy: %s\n' "$(measurement_timing_policy)"
  printf '  cold_start_policy: %s\n' "$(measurement_cold_start_policy)"
  printf '  compile_latency_claim_source: %s\n' "$(measurement_compile_latency_claim_source)"
  printf '  runtime_validation_policy: %s\n' "$(measurement_runtime_validation_policy)"
  printf '  claim_provenance_schema: %s\n' "$(measurement_claim_provenance_schema)"
  printf '  baseline_separation_schema: %s\n' "$(measurement_baseline_separation_schema)"
  printf '  required_claim_provenance_fields: %s\n' "$(measurement_required_claim_provenance_fields)"
  printf '  paper_baseline_policy: %s\n' "$(measurement_paper_baseline_policy)"
  printf '  paper_baseline_numbers_status: %s\n' "$(measurement_paper_baseline_numbers_status)"
  printf '  local_evidence_status_policy: %s\n' "$(measurement_local_evidence_status_policy)"
  printf '  local_performance_claim_policy: %s\n' "$(measurement_local_performance_claim_policy)"
  printf '  local_performance_claim_source: %s\n' "$(measurement_local_performance_claim_source)"
  printf '  local_performance_claim_status: %s\n' "$(measurement_local_performance_claim_status)"
  printf '  local_performance_claim_blockers: %s\n' "$(measurement_local_performance_claim_blockers)"
  printf '  local_vram_claim_source: %s\n' "$(measurement_local_vram_claim_source)"
  printf '  local_pareas_claim_source: %s\n' "$(measurement_local_pareas_claim_source)"
  printf '  scaling_claim_policy: %s\n' "$(measurement_scaling_claim_policy)"
  printf '  scaling_claim_source: %s\n' "$(measurement_scaling_claim_source)"
  printf '  scaling_claim_status: %s\n' "$(measurement_scaling_claim_status)"
  printf '  scaling_claim_blockers: %s\n' "$(measurement_scaling_claim_blockers)"
  printf '  paper_pass_order_schema: %s\n' "$(measurement_paper_pass_order_schema)"
  printf '  paper_pass_order_source: %s\n' "$(measurement_paper_pass_order_source)"
  printf '  paper_pass_order: %s\n' "$(measurement_paper_pass_order)"
  printf '  paper_pass_alignment_policy: %s\n' "$(measurement_paper_pass_alignment_policy)"
  printf '  paper_pass_alignment_status: %s\n' "$(measurement_paper_pass_alignment_status)"
  printf '  paper_pass_alignment_blockers: %s\n' "$(measurement_paper_pass_alignment_blockers)"
  printf '  parallel_pass_contract_schema: %s\n' "$(measurement_parallel_pass_contract_schema)"
  printf '  parallel_pass_contract_policy: %s\n' "$(measurement_parallel_pass_contract_policy)"
  printf '  parallel_pass_contract_groups: %s\n' "$(measurement_parallel_pass_contract_groups)"
  printf '  parallel_pass_contract_order_policy: %s\n' "$(measurement_parallel_pass_contract_order_policy)"
  printf '  parallel_pass_contract_execution_order: %s\n' "$(measurement_parallel_pass_contract_execution_order)"
  printf '  required_parallel_pass_contract_fields: %s\n' "$(measurement_required_parallel_pass_contract_fields)"
  printf '  pass_contract_status_schema: %s\n' "$(measurement_pass_contract_status_schema)"
  printf '  required_pass_contract_status_fields: %s\n' "$(measurement_required_pass_contract_status_fields)"
  printf '  pass_contract_loop_policy: %s\n' "$(measurement_pass_contract_loop_policy)"
  printf '  pass_contract_loop_status: %s\n' "$(measurement_pass_contract_loop_status)"
  printf '  pass_contract_fallback_status: %s\n' "$(measurement_pass_contract_fallback_status)"
  printf '  pass_contract_claim_status: %s\n' "$(measurement_pass_contract_claim_status)"
  printf '  pass_contract_claim_blockers: %s\n' "$(measurement_pass_contract_claim_blockers)"
  printf '  pass_contract_readiness_status: %s\n' "$(measurement_pass_contract_readiness_status)"
  printf '  parallel_pass_contract_record_invariant: contract_schema=%s pass_group=record_invariant paper_pass_stage=paper_record_boundary record_boundary=public_record_invariants parallel_primitives=record_boundary_claim evidence_shape=record-invariant loop_status=%s fallback_status=%s claim_boundary=behavioral-evidence-only\n' "$(measurement_parallel_pass_contract_schema)" "$(measurement_pass_contract_loop_status)" "$(measurement_pass_contract_fallback_status)"
  printf '  parallel_pass_contract_semantic_contract: contract_schema=%s pass_group=semantic_contract paper_pass_stage=paper_semantic_boundary record_boundary=typed_identity_contracts parallel_primitives=structured_record_contract evidence_shape=semantic-contract loop_status=%s fallback_status=%s claim_boundary=behavioral-evidence-only\n' "$(measurement_parallel_pass_contract_schema)" "$(measurement_pass_contract_loop_status)" "$(measurement_pass_contract_fallback_status)"
  printf '  parallel_pass_contract_execution_contract: contract_schema=%s pass_group=execution_contract paper_pass_stage=paper_codegen_boundary record_boundary=emitted_output_contracts parallel_primitives=execution_behavior_claim evidence_shape=execution-contract loop_status=%s fallback_status=%s claim_boundary=executed-output-or-fail-closed-diagnostic\n' "$(measurement_parallel_pass_contract_schema)" "$(measurement_pass_contract_loop_status)" "$(measurement_pass_contract_fallback_status)"
  printf '  parallel_pass_contract_measurement_scaffold: contract_schema=%s pass_group=measurement_scaffold paper_pass_stage=paper_scale_boundary record_boundary=local_artifact_provenance parallel_primitives=measurement_metadata_claim evidence_shape=measurement-scaffold loop_status=%s fallback_status=%s claim_boundary=blocked-until-local-artifacts-and-contracts-claimable\n' "$(measurement_parallel_pass_contract_schema)" "$(measurement_pass_contract_loop_status)" "$(measurement_pass_contract_fallback_status)"
  printf '  timeout_provenance_schema: %s\n' "$(measurement_timeout_provenance_schema)"
  printf '  required_timeout_provenance_fields: %s\n' "$(measurement_required_timeout_provenance_fields)"
  printf '  timeout_scope: %s\n' "$(measurement_timeout_scope)"
  printf '  timeout_source: %s\n' "$(measurement_timeout_source)"
  printf '  timeout_enforced_by: %s\n' "$(measurement_timeout_enforced_by)"
  printf '  timeout_exit_code: %s\n' "$(measurement_timeout_exit_code)"
  printf '  timeout_exit_code_means_timed_out: %s\n' "$(measurement_timeout_exit_code_means_timed_out)"
  printf '  required_artifacts: %s\n' "$(measurement_required_artifacts)"
  printf '  artifact_manifest_schema: %s\n' "$(measurement_artifact_manifest_schema)"
  printf '  required_artifact_manifest_fields: %s\n' "$(measurement_required_artifact_manifest_fields)"
  printf '  readback_summary_schema: %s\n' "$(measurement_readback_summary_schema)"
  printf '  required_readback_summary_fields: %s\n' "$(measurement_required_readback_summary_fields)"
  printf '  vram_csv_schema: %s\n' "$(measurement_vram_csv_schema)"
  printf '  required_vram_csv_columns: %s\n' "$(measurement_required_vram_csv_columns)"
  printf '  hardware_identity_schema: %s\n' "$(measurement_hardware_identity_schema)"
  printf '  required_hardware_identity_fields: %s\n' "$(measurement_required_hardware_identity_fields)"
  printf '  command_environment_schema: %s\n' "$(measurement_command_environment_schema)"
  printf '  required_command_environment_fields: %s\n' "$(measurement_required_command_environment_fields)"
  printf '  responsiveness_probe_schema: %s\n' "$(measurement_responsiveness_probe_schema)"
  printf '  required_responsiveness_probe_fields: %s\n' "$(measurement_required_responsiveness_probe_fields)"
  printf '  command_status_schema: %s\n' "$(measurement_command_status_schema)"
  printf '  evidence_status_schema: %s\n' "$(measurement_evidence_status_schema)"
  printf '  required_evidence_status_fields: %s\n' "$(measurement_required_evidence_status_fields)"
  printf '  evidence_freshness_schema: %s\n' "$(measurement_evidence_freshness_schema)"
  printf '  required_evidence_freshness_fields: %s\n' "$(measurement_required_evidence_freshness_fields)"
  printf '  claim_readiness_schema: %s\n' "$(measurement_claim_readiness_schema)"
  printf '  claim_readiness_policy: %s\n' "$(measurement_claim_readiness_policy)"
  printf '  claim_readiness_required_evidence_classes: %s\n' "$(measurement_claim_readiness_required_evidence_classes)"
  printf '  claim_readiness_required_statuses: %s\n' "$(measurement_claim_readiness_required_statuses)"
  printf '  claim_scope_policy: %s\n' "$(measurement_claim_scope_policy)"
  printf '  source_control_policy: %s\n' "$(measurement_source_control_policy)"
  printf '  repeatability_policy: %s\n' "$(measurement_repeatability_policy)"
  printf '  minimum_iterations_for_claim: %s\n' "$(measurement_minimum_iterations_for_claim)"
  printf '  required_claim_readiness_fields: %s\n' "$(measurement_required_claim_readiness_fields)"
  printf '  lanius_stdout_path: %q\n' "$stdout_path"
  printf '  lanius_perfetto_trace_path: %q\n' "$trace_path"
  printf '  readback_summary_path: %q\n' "$readback_summary_path"
  printf '  vram_output_path: %q\n' "$vram_path"
  printf '  source_replay_output_path: %q\n' "$source_replay_path"
  printf '  source_sha256_output_path: %q\n' "$source_sha256_path"
  printf '  bench_sha256_output_path: %q\n' "$bench_sha256_path"
  printf '  hardware_output_path: %q\n' "$hardware_path"
  printf '  command_env_output_path: %q\n' "$command_env_path"
  printf '  command_status_output_path: %q\n' "$command_status_path"
  printf '  responsiveness_probe_output_path: %q\n' "$responsiveness_path"
  printf '  resource_usage_output_path: %q\n' "$resource_usage_path"
  printf '  measurement_summary_output_path: %q\n' "$measurement_summary_path"
  printf '  pareas_source_path: %q\n' "$pareas_source_path"
  printf '  pareas_source_sha256_output_path: %q\n' "$pareas_source_sha256_path"
  printf '  pareas_binary_sha256_output_path: %q\n' "$pareas_binary_sha256_path"
  printf '  pareas_output_path: %q\n' "$pareas_output_path"
  printf '  pareas_stdout_path: %q\n' "$pareas_stdout_path"
  printf '  required_status_fields: %s\n' "$(measurement_required_status_fields)"
  printf '  optional_status_fields: %s\n' "$(measurement_optional_status_fields)"
  printf '  required_summary_fields: %s\n' "$(measurement_required_summary_fields)"
  printf '  optional_comparison_artifacts: %s\n' "$(measurement_optional_comparison_artifacts)"
  printf '  evidence_artifacts_begin\n'
  print_checkpoint_evidence_artifact \
    "$line_count" \
    lanius_stdout \
    true \
    "$stdout_path" \
    "lanius_wrapped_command_${line_count}l" \
    lanius_exit_status \
    command_status \
    lanius_latency_throughput \
    "redirect=lanius_stdout_redirect_${line_count}l"
  print_checkpoint_evidence_artifact \
    "$line_count" \
    perfetto_trace \
    true \
    "$trace_path" \
    "lanius_wrapped_command_${line_count}l" \
    lanius_exit_status \
    command_status \
    readback_trace_source \
    env_var=LANIUS_PERFETTO_TRACE
  print_checkpoint_evidence_artifact \
    "$line_count" \
    readback_summary \
    true \
    "$readback_summary_path" \
    "readback_trace_summary_command_${line_count}l" \
    lanius_exit_status \
    command_status \
    readback_cost \
    input=perfetto_trace \
    schema="$(measurement_readback_summary_schema)" \
    fields="$(measurement_required_readback_summary_fields)" \
    "redirect=readback_trace_summary_stdout_redirect_${line_count}l"
  print_checkpoint_evidence_artifact \
    "$line_count" \
    vram_csv \
    true \
    "$vram_path" \
    "nvidia_smi_wrapped_command_${line_count}l" \
    nvidia_smi_exit_status \
    command_status \
    vram_usage \
    availability=requires_nvidia_smi \
    schema="$(measurement_vram_csv_schema)" \
    columns="$(measurement_required_vram_csv_columns)" \
    stale_check=vram_csv_header_matches_required_columns \
    "redirect=nvidia_smi_stdout_redirect_${line_count}l"
  print_checkpoint_evidence_artifact \
    "$line_count" \
    source_replay \
    true \
    "$source_replay_path" \
    "source_replay_command_${line_count}l" \
    not_captured \
    none \
    replayable_input \
    "redirect=source_replay_stdout_redirect_${line_count}l"
  print_checkpoint_evidence_artifact \
    "$line_count" \
    source_sha256 \
    true \
    "$source_sha256_path" \
    "source_sha256_command_${line_count}l" \
    not_captured \
    none \
    replay_hash \
    input=source_replay \
    "redirect=source_sha256_stdout_redirect_${line_count}l"
  print_checkpoint_evidence_artifact \
    "$line_count" \
    bench_binary_sha256 \
    true \
    "$bench_sha256_path" \
    "bench_sha256_command_${line_count}l" \
    not_captured \
    none \
    measured_binary_identity \
    input=target/release/gpu_compile_bench \
    "redirect=bench_sha256_stdout_redirect_${line_count}l"
  print_checkpoint_evidence_artifact \
    "$line_count" \
    hardware_identity \
    true \
    "$hardware_path" \
    "hardware_identity_command_${line_count}l" \
    not_captured \
    none \
    measured_machine \
    "redirect=hardware_identity_stdout_redirect_${line_count}l" \
    schema="$(measurement_hardware_identity_schema)" \
    fields="$(measurement_required_hardware_identity_fields)"
  print_checkpoint_evidence_artifact \
    "$line_count" \
    command_environment \
    true \
    "$command_env_path" \
    "command_environment_command_${line_count}l" \
    not_captured \
    none \
    reproducibility_context \
    schema="$(measurement_command_environment_schema)" \
    fields="$(measurement_required_command_environment_fields)" \
    "redirect=command_environment_stdout_redirect_${line_count}l"
  print_checkpoint_evidence_artifact \
    "$line_count" \
    command_status \
    true \
    "$command_status_path" \
    "lanius_wrapped_command_${line_count}l" \
    lanius_exit_status \
    command_status \
    timeout_and_exit_metadata \
    status_fields="$(measurement_required_status_fields)" \
    "appended_by=responsiveness_probe_command_${line_count}l,nvidia_smi_wrapped_command_${line_count}l,pareas_wrapped_command_${line_count}l"
  print_checkpoint_evidence_artifact \
    "$line_count" \
    responsiveness_probe \
    true \
    "$responsiveness_path" \
    "responsiveness_probe_command_${line_count}l" \
    responsiveness_probe_status \
    command_status \
    machine_responsiveness \
    schema="$(measurement_responsiveness_probe_schema)" \
    fields="$(measurement_required_responsiveness_probe_fields)" \
    "redirect=responsiveness_probe_stdout_redirect_${line_count}l"
  print_checkpoint_evidence_artifact \
    "$line_count" \
    resource_usage \
    true \
    "$resource_usage_path" \
    "lanius_wrapped_command_${line_count}l" \
    resource_usage_status \
    command_status \
    cpu_time_and_memory \
    fields=user_seconds,system_seconds,max_rss_kb \
    stale_check=resource_usage_command_matches_checkpoint
  print_checkpoint_evidence_artifact \
    "$line_count" \
    measurement_summary \
    true \
    "$measurement_summary_path" \
    "measurement_summary_command_${line_count}l" \
    not_captured \
    none \
    checkpoint_rollup \
    schema=lanius.measurement-summary.v1 \
    fields="$(measurement_required_summary_fields)" \
    completion_schema="$(measurement_evidence_status_schema)" \
    completion_fields="$(measurement_required_evidence_status_fields)" \
    freshness_schema="$(measurement_evidence_freshness_schema)" \
    freshness_fields="$(measurement_required_evidence_freshness_fields)" \
    claim_readiness_schema="$(measurement_claim_readiness_schema)" \
    claim_readiness_policy="$(measurement_claim_readiness_policy)" \
    claim_readiness_fields="$(measurement_required_claim_readiness_fields)" \
    inputs=lanius_stdout,readback_summary,vram_csv,source_replay,source_sha256,bench_binary_sha256,hardware_identity,command_environment,command_status,responsiveness_probe,resource_usage,pareas_source,pareas_source_sha256,pareas_binary_sha256
  print_checkpoint_evidence_artifact \
    "$line_count" \
    pareas_source \
    false \
    "$pareas_source_path" \
    "pareas_source_command_${line_count}l" \
    not_captured \
    none \
    pareas_comparison_input \
    availability=optional_comparison \
    "redirect=pareas_source_stdout_redirect_${line_count}l"
  print_checkpoint_evidence_artifact \
    "$line_count" \
    pareas_source_sha256 \
    false \
    "$pareas_source_sha256_path" \
    "pareas_source_sha256_command_${line_count}l" \
    not_captured \
    none \
    pareas_comparison_input_hash \
    availability=optional_comparison \
    input=pareas_source \
    "redirect=pareas_source_sha256_stdout_redirect_${line_count}l"
  print_checkpoint_evidence_artifact \
    "$line_count" \
    pareas_binary_sha256 \
    false \
    "$pareas_binary_sha256_path" \
    "pareas_binary_sha256_command_${line_count}l" \
    not_captured \
    none \
    pareas_compiler_identity \
    availability=requires_pareas \
    input=PAREAS_BIN \
    stale_check=pareas_binary_sha256_matches_pareas_binary \
    "redirect=pareas_binary_sha256_stdout_redirect_${line_count}l"
  print_checkpoint_evidence_artifact \
    "$line_count" \
    pareas_output \
    false \
    "$pareas_output_path" \
    "pareas_wrapped_command_${line_count}l" \
    pareas_exit_status \
    command_status \
    pareas_comparison_output \
    availability=requires_pareas
  print_checkpoint_evidence_artifact \
    "$line_count" \
    pareas_stdout \
    false \
    "$pareas_stdout_path" \
    "pareas_wrapped_command_${line_count}l" \
    pareas_exit_status \
    command_status \
    pareas_comparison_timing \
    availability=requires_pareas \
    "redirect=pareas_stdout_redirect_${line_count}l"
  printf '  evidence_artifacts_end\n'
  print_report_command \
    "hardware_identity_command_${line_count}l" \
    sh \
    -c \
    'nvidia_smi="$1"; printf "hardware_identity_schema=lanius.hardware-identity.v1\n"; printf "target=x86_64-elf\n"; printf "uname="; uname -a; if [ -n "$nvidia_smi" ] && [ -x "$nvidia_smi" ]; then printf "nvidia_smi_status=available\n"; "$nvidia_smi" --query-gpu=index,name,driver_version,memory.total --format=csv,noheader; elif command -v nvidia-smi >/dev/null 2>&1; then printf "nvidia_smi_status=available\n"; nvidia-smi --query-gpu=index,name,driver_version,memory.total --format=csv,noheader; else printf "nvidia_smi_status=unavailable\n"; fi' \
    sh \
    "$nvidia_smi"
  printf 'hardware_identity_stdout_redirect_%sl: > %q\n' "$line_count" "$hardware_path"
  print_report_command \
    "command_environment_command_${line_count}l" \
    sh \
    -c \
    'line_count="$1"; source="$2"; phase="$3"; target="$4"; iterations="$5"; timeout_ms="$6"; timeout_seconds="$7"; readback_timeout_ms="$8"; vram_sample_interval_ms="$9"; seed="${10}"; responsiveness_timeout_ms="${11}"; responsiveness_timeout_seconds="${12}"; timing_policy="${13}"; cold_start_policy="${14}"; compile_latency_claim_source="${15}"; runtime_validation_policy="${16}"; timeout_provenance_schema="${17}"; timeout_scope="${18}"; timeout_source="${19}"; parallel_pass_contract_schema="${20}"; parallel_pass_contract_policy="${21}"; parallel_pass_contract_groups="${22}"; parallel_pass_contract_order_policy="${23}"; parallel_pass_contract_execution_order="${24}"; claim_provenance_schema="${25}"; baseline_separation_schema="${26}"; paper_baseline_policy="${27}"; paper_baseline_numbers_status="${28}"; local_evidence_status_policy="${29}"; local_performance_claim_policy="${30}"; local_performance_claim_source="${31}"; local_performance_claim_status="${32}"; local_performance_claim_blockers="${33}"; local_vram_claim_source="${34}"; local_pareas_claim_source="${35}"; scaling_claim_policy="${36}"; scaling_claim_source="${37}"; scaling_claim_status="${38}"; scaling_claim_blockers="${39}"; paper_pass_order_schema="${40}"; paper_pass_order_source="${41}"; paper_pass_order="${42}"; paper_pass_alignment_policy="${43}"; paper_pass_alignment_status="${44}"; paper_pass_alignment_blockers="${45}"; pass_contract_status_schema="${46}"; pass_contract_loop_policy="${47}"; pass_contract_loop_status="${48}"; pass_contract_fallback_status="${49}"; pass_contract_claim_status="${50}"; pass_contract_claim_blockers="${51}"; pass_contract_readiness_status=blocked; if [ "$pass_contract_loop_status" = unbounded ] && [ "$pass_contract_fallback_status" = none ] && [ "$pass_contract_claim_status" = claimable ]; then pass_contract_readiness_status=claimable; fi; printf "command_environment_schema=lanius.command-environment.v1\n"; printf "timestamp_utc="; date -u +%Y-%m-%dT%H:%M:%SZ; printf "cwd=%s\n" "$PWD"; printf "line_count=%s\n" "$line_count"; printf "source=%s\n" "$source"; printf "phase=%s\n" "$phase"; printf "target=%s\n" "$target"; printf "iterations=%s\n" "$iterations"; printf "measurement_timing_policy=%s\n" "$timing_policy"; printf "cold_start_policy=%s\n" "$cold_start_policy"; printf "compile_latency_claim_source=%s\n" "$compile_latency_claim_source"; printf "runtime_validation_policy=%s\n" "$runtime_validation_policy"; printf "claim_provenance_schema=%s\n" "$claim_provenance_schema"; printf "baseline_separation_schema=%s\n" "$baseline_separation_schema"; printf "paper_baseline_policy=%s\n" "$paper_baseline_policy"; printf "paper_baseline_numbers_status=%s\n" "$paper_baseline_numbers_status"; printf "local_evidence_status_policy=%s\n" "$local_evidence_status_policy"; printf "local_performance_claim_policy=%s\n" "$local_performance_claim_policy"; printf "local_performance_claim_source=%s\n" "$local_performance_claim_source"; printf "local_performance_claim_status=%s\n" "$local_performance_claim_status"; printf "local_performance_claim_blockers=%s\n" "$local_performance_claim_blockers"; printf "local_vram_claim_source=%s\n" "$local_vram_claim_source"; printf "local_pareas_claim_source=%s\n" "$local_pareas_claim_source"; printf "scaling_claim_policy=%s\n" "$scaling_claim_policy"; printf "scaling_claim_source=%s\n" "$scaling_claim_source"; printf "scaling_claim_status=%s\n" "$scaling_claim_status"; printf "scaling_claim_blockers=%s\n" "$scaling_claim_blockers"; printf "paper_pass_order_schema=%s\n" "$paper_pass_order_schema"; printf "paper_pass_order_source=%s\n" "$paper_pass_order_source"; printf "paper_pass_order=%s\n" "$paper_pass_order"; printf "paper_pass_alignment_policy=%s\n" "$paper_pass_alignment_policy"; printf "paper_pass_alignment_status=%s\n" "$paper_pass_alignment_status"; printf "paper_pass_alignment_blockers=%s\n" "$paper_pass_alignment_blockers"; printf "parallel_pass_contract_schema=%s\n" "$parallel_pass_contract_schema"; printf "parallel_pass_contract_policy=%s\n" "$parallel_pass_contract_policy"; printf "parallel_pass_contract_groups=%s\n" "$parallel_pass_contract_groups"; printf "parallel_pass_contract_order_policy=%s\n" "$parallel_pass_contract_order_policy"; printf "parallel_pass_contract_execution_order=%s\n" "$parallel_pass_contract_execution_order"; printf "pass_contract_status_schema=%s\n" "$pass_contract_status_schema"; printf "pass_contract_loop_policy=%s\n" "$pass_contract_loop_policy"; printf "pass_contract_loop_status=%s\n" "$pass_contract_loop_status"; printf "pass_contract_fallback_status=%s\n" "$pass_contract_fallback_status"; printf "pass_contract_claim_status=%s\n" "$pass_contract_claim_status"; printf "pass_contract_claim_blockers=%s\n" "$pass_contract_claim_blockers"; printf "pass_contract_readiness_status=%s\n" "$pass_contract_readiness_status"; printf "timeout_provenance_schema=%s\n" "$timeout_provenance_schema"; printf "timeout_scope=%s\n" "$timeout_scope"; printf "timeout_source=%s\n" "$timeout_source"; printf "timeout_ms=%s\n" "$timeout_ms"; printf "timeout_seconds=%s\n" "$timeout_seconds"; printf "readback_timeout_ms=%s\n" "$readback_timeout_ms"; printf "vram_sample_interval_ms=%s\n" "$vram_sample_interval_ms"; printf "source_seed=%s\n" "$seed"; printf "responsiveness_probe_timeout_ms=%s\n" "$responsiveness_timeout_ms"; printf "responsiveness_probe_timeout_seconds=%s\n" "$responsiveness_timeout_seconds"; printf "git_head="; git rev-parse HEAD 2>/dev/null || printf "unavailable\n"; rustc_version="$(rustc --version 2>/dev/null || true)"; [ -n "$rustc_version" ] || rustc_version=unavailable; printf "rustc_version=%s\n" "$rustc_version"; cargo_version="$(cargo --version 2>/dev/null || true)"; [ -n "$cargo_version" ] || cargo_version=unavailable; printf "cargo_version=%s\n" "$cargo_version"; slangc_version=unavailable; if [ -n "${SLANGC:-}" ] && [ -x "$SLANGC" ]; then slangc_version="$("$SLANGC" --version 2>/dev/null | head -n1 || true)"; elif command -v slangc >/dev/null 2>&1; then slangc_version="$(slangc --version 2>/dev/null | head -n1 || true)"; fi; [ -n "$slangc_version" ] || slangc_version=unavailable; printf "slangc_version=%s\n" "$slangc_version"; printf "git_status_short_begin\n"; git status --short 2>/dev/null || true; printf "git_status_short_end\n"; env | LC_ALL=C sort | grep -E "^(LANIUS_|PAREAS_|NVIDIA_|CUDA|SLANGC=|PATH=)" || true' \
    sh \
    "$line_count" \
    "$perf_source" \
    "$perf_phase" \
    x86_64-elf \
    "$perf_iters" \
    "$perf_timeout_ms" \
    "$perf_timeout_seconds" \
    "$perf_readback_timeout_ms" \
    "$perf_vram_sample_interval_ms" \
    "$perf_seed" \
    "$perf_responsiveness_timeout_ms" \
    "$perf_responsiveness_timeout_seconds" \
    "$(measurement_timing_policy)" \
    "$(measurement_cold_start_policy)" \
    "$(measurement_compile_latency_claim_source)" \
    "$(measurement_runtime_validation_policy)" \
    "$(measurement_timeout_provenance_schema)" \
    "$(measurement_timeout_scope)" \
    "$(measurement_timeout_source)" \
    "$(measurement_parallel_pass_contract_schema)" \
    "$(measurement_parallel_pass_contract_policy)" \
    "$(measurement_parallel_pass_contract_groups)" \
    "$(measurement_parallel_pass_contract_order_policy)" \
    "$(measurement_parallel_pass_contract_execution_order)" \
    "$(measurement_claim_provenance_schema)" \
    "$(measurement_baseline_separation_schema)" \
    "$(measurement_paper_baseline_policy)" \
    "$(measurement_paper_baseline_numbers_status)" \
    "$(measurement_local_evidence_status_policy)" \
    "$(measurement_local_performance_claim_policy)" \
    "$(measurement_local_performance_claim_source)" \
    "$(measurement_local_performance_claim_status)" \
    "$(measurement_local_performance_claim_blockers)" \
    "$(measurement_local_vram_claim_source)" \
    "$(measurement_local_pareas_claim_source)" \
    "$(measurement_scaling_claim_policy)" \
    "$(measurement_scaling_claim_source)" \
    "$(measurement_scaling_claim_status)" \
    "$(measurement_scaling_claim_blockers)" \
    "$(measurement_paper_pass_order_schema)" \
    "$(measurement_paper_pass_order_source)" \
    "$(measurement_paper_pass_order)" \
    "$(measurement_paper_pass_alignment_policy)" \
    "$(measurement_paper_pass_alignment_status)" \
    "$(measurement_paper_pass_alignment_blockers)" \
    "$(measurement_pass_contract_status_schema)" \
    "$(measurement_pass_contract_loop_policy)" \
    "$(measurement_pass_contract_loop_status)" \
    "$(measurement_pass_contract_fallback_status)" \
    "$(measurement_pass_contract_claim_status)" \
    "$(measurement_pass_contract_claim_blockers)"
  printf 'command_environment_stdout_redirect_%sl: > %q\n' "$line_count" "$command_env_path"
  print_report_command \
    "source_replay_command_${line_count}l" \
    target/release/gpu_compile_bench \
    --phase \
    "$perf_phase" \
    --source \
    "$perf_source" \
    --lines \
    "$line_count" \
    --seed \
    "$perf_seed" \
    --dump-source
  printf 'source_replay_stdout_redirect_%sl: > %q\n' "$line_count" "$source_replay_path"
  print_report_command \
    "source_sha256_command_${line_count}l" \
    sha256sum \
    "$source_replay_path"
  printf 'source_sha256_stdout_redirect_%sl: > %q\n' "$line_count" "$source_sha256_path"
  print_report_command \
    "bench_sha256_command_${line_count}l" \
    sha256sum \
    target/release/gpu_compile_bench
  printf 'bench_sha256_stdout_redirect_%sl: > %q\n' "$line_count" "$bench_sha256_path"
  print_report_command \
    "lanius_command_${line_count}l" \
    timeout \
    "$perf_timeout_seconds" \
    env \
    LANIUS_GPU_TIMING=1 \
    LANIUS_GPU_COMPILE_HOST_TIMING=1 \
    LANIUS_READBACK=1 \
    LANIUS_READBACK_TIMEOUT_MS="$perf_readback_timeout_ms" \
    LANIUS_X86_READBACK_TIMEOUT_MS="$perf_readback_timeout_ms" \
    LANIUS_PERFETTO_TRACE="$trace_path" \
    target/release/gpu_compile_bench \
    --phase \
    "$perf_phase" \
    --emit \
    x86_64-elf \
    --source \
    "$perf_source" \
    --lines \
    "$line_count" \
    --seed \
    "$perf_seed" \
    --warmups \
    0 \
    --iters \
    "$perf_iters" \
    --allow-large \
    --validate-output
  printf 'lanius_stdout_redirect_%sl: > %q 2>&1\n' "$line_count" "$stdout_path"
  print_report_command \
    "lanius_wrapped_command_${line_count}l" \
    sh \
    -c \
    'timeout_seconds="$1"
stdout_path="$2"
status_path="$3"
trace_path="$4"
phase="$5"
source="$6"
line_count="$7"
seed="$8"
iterations="$9"
readback_timeout="${10}"
vram_sample_interval_ms="${11}"
resource_path="${12}"
timeout_ms="${13}"
timing_policy="${14}"
cold_start_policy="${15}"
compile_latency_claim_source="${16}"
runtime_validation_policy="${17}"
timeout_provenance_schema="${18}"
timeout_scope="${19}"
timeout_source="${20}"
timeout_enforced_by="${21}"
timeout_exit_code="${22}"
timeout_exit_code_means_timed_out="${23}"
target=x86_64-elf
status=0
resource_usage_status=unavailable
start_ns="$(date +%s%N 2>/dev/null || printf unavailable)"
if command -v /usr/bin/time >/dev/null 2>&1; then
  /usr/bin/time -v -o "$resource_path" timeout "$timeout_seconds" env LANIUS_GPU_TIMING=1 LANIUS_GPU_COMPILE_HOST_TIMING=1 LANIUS_READBACK=1 LANIUS_READBACK_TIMEOUT_MS="$readback_timeout" LANIUS_X86_READBACK_TIMEOUT_MS="$readback_timeout" LANIUS_PERFETTO_TRACE="$trace_path" target/release/gpu_compile_bench --phase "$phase" --emit x86_64-elf --source "$source" --lines "$line_count" --seed "$seed" --warmups 0 --iters "$iterations" --allow-large --validate-output >"$stdout_path" 2>&1 || status=$?
  if [ -s "$resource_path" ]; then
    resource_usage_status=0
  else
    resource_usage_status=1
  fi
else
  {
    printf "resource_usage_schema=lanius.resource-usage.v1\n"
    printf "resource_usage_status=unavailable\n"
    printf "reason=/usr/bin/time not found\n"
  } >"$resource_path"
  timeout "$timeout_seconds" env LANIUS_GPU_TIMING=1 LANIUS_GPU_COMPILE_HOST_TIMING=1 LANIUS_READBACK=1 LANIUS_READBACK_TIMEOUT_MS="$readback_timeout" LANIUS_X86_READBACK_TIMEOUT_MS="$readback_timeout" LANIUS_PERFETTO_TRACE="$trace_path" target/release/gpu_compile_bench --phase "$phase" --emit x86_64-elf --source "$source" --lines "$line_count" --seed "$seed" --warmups 0 --iters "$iterations" --allow-large --validate-output >"$stdout_path" 2>&1 || status=$?
fi
end_ns="$(date +%s%N 2>/dev/null || printf unavailable)"
lanius_wall_elapsed_ms=pending
case "$start_ns:$end_ns" in
  *[!0-9:]*|:*|*:) ;;
  *) lanius_wall_elapsed_ms=$(((end_ns - start_ns) / 1000000)) ;;
esac
{
  printf "command_status_schema=lanius.command-status.v1\n"
  printf "lanius_exit_status=%s\n" "$status"
  printf "lanius_wall_elapsed_ms=%s\n" "$lanius_wall_elapsed_ms"
  printf "measurement_timing_policy=%s\n" "$timing_policy"
  printf "cold_start_policy=%s\n" "$cold_start_policy"
  printf "compile_latency_claim_source=%s\n" "$compile_latency_claim_source"
  printf "runtime_validation_policy=%s\n" "$runtime_validation_policy"
  printf "timeout_provenance_schema=%s\n" "$timeout_provenance_schema"
  printf "timeout_scope=%s\n" "$timeout_scope"
  printf "timeout_ms=%s\n" "$timeout_ms"
  printf "timeout_seconds=%s\n" "$timeout_seconds"
  printf "timeout_source=%s\n" "$timeout_source"
  printf "timeout_enforced_by=%s\n" "$timeout_enforced_by"
  printf "timeout_exit_code=%s\n" "$timeout_exit_code"
  printf "timeout_exit_code_means_timed_out=%s\n" "$timeout_exit_code_means_timed_out"
  printf "line_count=%s\n" "$line_count"
  printf "source=%s\n" "$source"
  printf "phase=%s\n" "$phase"
  printf "target=%s\n" "$target"
  printf "source_seed=%s\n" "$seed"
  printf "iterations=%s\n" "$iterations"
  printf "readback_timeout_ms=%s\n" "$readback_timeout"
  printf "vram_sample_interval_ms=%s\n" "$vram_sample_interval_ms"
  printf "lanius_stdout_path=%s\n" "$stdout_path"
  printf "perfetto_trace_path=%s\n" "$trace_path"
  printf "resource_usage_status=%s\n" "$resource_usage_status"
  printf "resource_usage_path=%s\n" "$resource_path"
} >"$status_path"
exit "$status"' \
    sh \
    "${perf_timeout_seconds}s" \
    "$stdout_path" \
    "$command_status_path" \
    "$trace_path" \
    "$perf_phase" \
    "$perf_source" \
    "$line_count" \
    "$perf_seed" \
    "$perf_iters" \
    "$perf_readback_timeout_ms" \
    "$perf_vram_sample_interval_ms" \
    "$resource_usage_path" \
    "$perf_timeout_ms" \
    "$(measurement_timing_policy)" \
    "$(measurement_cold_start_policy)" \
    "$(measurement_compile_latency_claim_source)" \
    "$(measurement_runtime_validation_policy)" \
    "$(measurement_timeout_provenance_schema)" \
    "$(measurement_timeout_scope)" \
    "$(measurement_timeout_source)" \
    "$(measurement_timeout_enforced_by)" \
    "$(measurement_timeout_exit_code)" \
    "$(measurement_timeout_exit_code_means_timed_out)"
  print_report_command \
    "responsiveness_probe_command_${line_count}l" \
    sh \
    -c \
    'out="$1"; status_path="$2"; line_count="$3"; source="$4"; phase="$5"; target="$6"; timeout_ms="$7"; timeout_seconds="$8"; start_ns="$(date +%s%N 2>/dev/null || printf unavailable)"; status=0; timeout "${timeout_seconds}s" sh -c ":" >/dev/null 2>&1 || status=$?; end_ns="$(date +%s%N 2>/dev/null || printf unavailable)"; responsive=false; [ "$status" -eq 0 ] && responsive=true; elapsed_ms=pending; case "$start_ns:$end_ns" in *[!0-9:]*|:*|*:) ;; *) elapsed_ms=$(((end_ns - start_ns) / 1000000)) ;; esac; { printf "responsiveness_probe_schema=lanius.responsiveness-probe.v1\n"; printf "line_count=%s\n" "$line_count"; printf "source=%s\n" "$source"; printf "phase=%s\n" "$phase"; printf "target=%s\n" "$target"; printf "timeout_ms=%s\n" "$timeout_ms"; printf "timeout_seconds=%s\n" "$timeout_seconds"; printf "probe_command=timeout_sh_noop\n"; printf "probe_exit_status=%s\n" "$status"; printf "responsive=%s\n" "$responsive"; printf "elapsed_ms=%s\n" "$elapsed_ms"; } >"$out"; { printf "responsiveness_probe_status=%s\n" "$status"; printf "machine_responsive_after=%s\n" "$responsive"; printf "responsiveness_probe_path=%s\n" "$out"; } >>"$status_path"' \
    sh \
    "$responsiveness_path" \
    "$command_status_path" \
    "$line_count" \
    "$perf_source" \
    "$perf_phase" \
    x86_64-elf \
    "$perf_responsiveness_timeout_ms" \
    "$perf_responsiveness_timeout_seconds"
  printf 'responsiveness_probe_stdout_redirect_%sl: writes > %q and appends status to %q\n' "$line_count" "$responsiveness_path" "$command_status_path"
  print_report_command \
    "readback_trace_summary_command_${line_count}l" \
    sh \
    -c \
    'trace_path="$1"; line_count="$2"; source="$3"; phase="$4"; target="$5"; readback_timeout_ms="$6"; span_count=pending; if [ -f "$trace_path" ]; then if command -v rg >/dev/null 2>&1; then span_count="$(rg -i "host.readback|readback" "$trace_path" | wc -l | tr -d " ")"; else span_count=missing-rg; fi; fi; { printf "readback_summary_schema=lanius.readback-summary.v1\n"; printf "line_count=%s\n" "$line_count"; printf "source=%s\n" "$source"; printf "phase=%s\n" "$phase"; printf "target=%s\n" "$target"; printf "trace_path=%s\n" "$trace_path"; printf "readback_timeout_ms=%s\n" "$readback_timeout_ms"; printf "span_count=%s\n" "$span_count"; printf "total_ms=pending\n"; printf "max_span_ms=pending\n"; }' \
    sh \
    "$trace_path" \
    "$line_count" \
    "$perf_source" \
    "$perf_phase" \
    x86_64-elf \
    "$perf_readback_timeout_ms"
  printf 'readback_trace_summary_stdout_redirect_%sl: > %q\n' "$line_count" "$readback_summary_path"

  if [[ -n "$nvidia_smi" ]]; then
    print_report_command \
      "nvidia_smi_command_${line_count}l" \
      "$nvidia_smi" \
      --query-gpu=timestamp,index,name,memory.used,memory.total,utilization.gpu \
      --format=csv \
      -lms \
      "$perf_vram_sample_interval_ms"
    printf 'nvidia_smi_stdout_redirect_%sl: > %q\n' "$line_count" "$vram_path"
    print_report_command \
      "nvidia_smi_wrapped_command_${line_count}l" \
      sh \
      -c \
      'status=0; timeout "$1" "$2" --query-gpu=timestamp,index,name,memory.used,memory.total,utilization.gpu --format=csv -lms "$3" >"$4" 2>&1 || status=$?; { printf "nvidia_smi_exit_status=%s\n" "$status"; printf "timeout_seconds=%s\n" "$1"; printf "line_count=%s\n" "$6"; printf "vram_sample_interval_ms=%s\n" "$3"; printf "vram_output_path=%s\n" "$4"; } >>"$5"; exit "$status"' \
      sh \
      "$perf_timeout_seconds" \
      "$nvidia_smi" \
      "$perf_vram_sample_interval_ms" \
      "$vram_path" \
      "$command_status_path" \
      "$line_count"
  else
    printf 'nvidia_smi_command_%sl: unavailable optional; set NVIDIA_SMI or LANIUS_REQUIRE_NVIDIA_SMI=1 before a measured run that requires VRAM sampling\n' "$line_count"
    printf 'nvidia_smi_stdout_redirect_%sl: unavailable optional; intended output path > %q\n' "$line_count" "$vram_path"
    printf 'nvidia_smi_wrapped_command_%sl: unavailable optional; VRAM CSV cannot be captured without NVIDIA_SMI or nvidia-smi on PATH\n' "$line_count"
  fi

  print_report_command \
    "pareas_source_command_${line_count}l" \
    sh \
    -c \
    'lines="$1"; helpers=$(((lines > 4 ? lines - 4 : 1) / 5)); if [ "$helpers" -lt 1 ]; then helpers=1; fi; i=0; while [ "$i" -lt "$helpers" ]; do printf "fn f%s[a: int]: int {\n  var x = a + %s;\n  return x;\n}\n" "$i" "$i"; i=$((i + 1)); done; printf "fn main[]: int {\n  var acc = 0;\n"; i=0; while [ "$i" -lt "$helpers" ]; do printf "  acc = acc + f%s[%s];\n" "$i" "$i"; i=$((i + 1)); done; printf "  return acc;\n}\n"' \
    sh \
    "$line_count"
  printf 'pareas_source_stdout_redirect_%sl: > %q\n' "$line_count" "$pareas_source_path"
  print_report_command \
    "pareas_source_sha256_command_${line_count}l" \
    sha256sum \
    "$pareas_source_path"
  printf 'pareas_source_sha256_stdout_redirect_%sl: > %q\n' "$line_count" "$pareas_source_sha256_path"

  if [[ -n "$pareas_bin" ]]; then
    print_report_command \
      "pareas_binary_sha256_command_${line_count}l" \
      sha256sum \
      "$pareas_bin"
    printf 'pareas_binary_sha256_stdout_redirect_%sl: > %q\n' "$line_count" "$pareas_binary_sha256_path"
    print_report_command \
      "pareas_command_${line_count}l" \
      timeout \
      "$perf_timeout_seconds" \
      "$pareas_bin" \
      "$pareas_source_path" \
      -o \
      "$pareas_output_path"
    printf 'pareas_stdout_redirect_%sl: > %q 2>&1\n' "$line_count" "$pareas_stdout_path"
    print_report_command \
      "pareas_wrapped_command_${line_count}l" \
      sh \
      -c \
      'status=0; start_ns="$(date +%s%N 2>/dev/null || printf unavailable)"; timeout "$1" "$2" "$3" -o "$4" >"$5" 2>&1 || status=$?; end_ns="$(date +%s%N 2>/dev/null || printf unavailable)"; pareas_wall_elapsed_ms=pending; case "$start_ns:$end_ns" in *[!0-9:]*|:*|*:) ;; *) pareas_wall_elapsed_ms=$(((end_ns - start_ns) / 1000000)) ;; esac; { printf "pareas_exit_status=%s\n" "$status"; printf "pareas_wall_elapsed_ms=%s\n" "$pareas_wall_elapsed_ms"; printf "timeout_seconds=%s\n" "$1"; printf "line_count=%s\n" "$7"; printf "pareas_bin_path=%s\n" "$2"; printf "pareas_source_path=%s\n" "$3"; printf "pareas_output_path=%s\n" "$4"; printf "pareas_stdout_path=%s\n" "$5"; } >>"$6"; exit "$status"' \
      sh \
      "${perf_timeout_seconds}s" \
      "$pareas_bin" \
      "$pareas_source_path" \
      "$pareas_output_path" \
      "$pareas_stdout_path" \
      "$command_status_path" \
      "$line_count"
  else
    printf 'pareas_binary_sha256_command_%sl: unavailable optional; set PAREAS_BIN or LANIUS_REQUIRE_PAREAS=1 before claiming a local Pareas comparison\n' "$line_count"
    printf 'pareas_binary_sha256_stdout_redirect_%sl: unavailable optional; intended output path > %q\n' "$line_count" "$pareas_binary_sha256_path"
    printf 'pareas_command_%sl: unavailable optional; set PAREAS_BIN or LANIUS_REQUIRE_PAREAS=1 after building Pareas\n' "$line_count"
    printf 'pareas_stdout_redirect_%sl: unavailable optional; intended stdout path > %q\n' "$line_count" "$pareas_stdout_path"
    printf 'pareas_wrapped_command_%sl: unavailable optional; Pareas status cannot be captured without PAREAS_BIN\n' "$line_count"
  fi

  print_report_command \
    "measurement_summary_command_${line_count}l" \
    sh \
    -c \
    'out="$1"
line_count="$2"
source="$3"
phase="$4"
target="$5"
seed="$6"
iterations="$7"
timeout_seconds="$8"
readback_timeout_ms="$9"
vram_sample_interval_ms="${10}"
lanius_stdout_path="${11}"
perfetto_trace_path="${12}"
readback_summary_path="${13}"
vram_output_path="${14}"
source_replay_path="${15}"
source_sha256_path="${16}"
bench_sha256_path="${17}"
hardware_output_path="${18}"
command_env_path="${19}"
command_status_path="${20}"
responsiveness_probe_path="${21}"
resource_usage_path="${22}"
pareas_source_path="${23}"
pareas_source_sha256_path="${24}"
pareas_binary_sha256_path="${25}"
pareas_output_path="${26}"
pareas_stdout_path="${27}"
responsiveness_timeout_ms="${28}"
responsiveness_timeout_seconds="${29}"
timeout_ms="${30}"
timing_policy="${31}"
cold_start_policy="${32}"
compile_latency_claim_source="${33}"
runtime_validation_policy="${34}"
timeout_provenance_schema="${35}"
timeout_scope="${36}"
timeout_source="${37}"
timeout_enforced_by="${38}"
timeout_exit_code="${39}"
timeout_exit_code_means_timed_out="${40}"
parallel_pass_contract_schema="${41}"
parallel_pass_contract_policy="${42}"
parallel_pass_contract_groups="${43}"
parallel_pass_contract_order_policy="${44}"
parallel_pass_contract_execution_order="${45}"
claim_provenance_schema="${46}"
baseline_separation_schema="${47}"
paper_baseline_policy="${48}"
paper_baseline_numbers_status="${49}"
local_evidence_status_policy="${50}"
local_performance_claim_policy="${51}"
local_performance_claim_source="${52}"
local_performance_claim_status="${53}"
local_performance_claim_blockers="${54}"
local_vram_claim_source="${55}"
local_pareas_claim_source="${56}"
scaling_claim_policy="${57}"
scaling_claim_source="${58}"
scaling_claim_status="${59}"
scaling_claim_blockers="${60}"
paper_pass_order_schema="${61}"
paper_pass_order_source="${62}"
paper_pass_order="${63}"
paper_pass_alignment_policy="${64}"
paper_pass_alignment_status="${65}"
paper_pass_alignment_blockers="${66}"
pass_contract_status_schema="${67}"
pass_contract_loop_policy="${68}"
pass_contract_loop_status="${69}"
pass_contract_fallback_status="${70}"
pass_contract_claim_status="${71}"
pass_contract_claim_blockers="${72}"

missing_required_artifacts=""
append_missing_artifact() {
  artifact_name="$1"
  artifact_path="$2"
  if [ ! -s "$artifact_path" ]; then
    if [ -n "$missing_required_artifacts" ]; then
      missing_required_artifacts="${missing_required_artifacts},${artifact_name}"
    else
      missing_required_artifacts="$artifact_name"
    fi
  fi
}
append_missing_artifact lanius_stdout "$lanius_stdout_path"
append_missing_artifact perfetto_trace "$perfetto_trace_path"
append_missing_artifact readback_summary "$readback_summary_path"
append_missing_artifact vram_csv "$vram_output_path"
append_missing_artifact source_replay "$source_replay_path"
append_missing_artifact source_sha256 "$source_sha256_path"
append_missing_artifact bench_binary_sha256 "$bench_sha256_path"
append_missing_artifact hardware_identity "$hardware_output_path"
append_missing_artifact command_environment "$command_env_path"
append_missing_artifact command_status "$command_status_path"
append_missing_artifact responsiveness_probe "$responsiveness_probe_path"
append_missing_artifact resource_usage "$resource_usage_path"
if [ -n "$missing_required_artifacts" ]; then
  required_artifacts_complete=false
else
  required_artifacts_complete=true
  missing_required_artifacts=none
fi

source_sha256="pending"
if [ -f "$source_sha256_path" ]; then
  source_sha256="$(sed -n "1{s/[[:space:]].*//;p;q;}" "$source_sha256_path")"
fi
source_replay_line_count="pending"
if [ -f "$source_replay_path" ]; then
  source_replay_line_count="$(awk "END { print NR + 0 }" "$source_replay_path")"
  [ -n "$source_replay_line_count" ] || source_replay_line_count="missing"
fi
bench_binary_sha256="pending"
if [ -f "$bench_sha256_path" ]; then
  bench_binary_sha256="$(sed -n "1{s/[[:space:]].*//;p;q;}" "$bench_sha256_path")"
fi
command_environment_sha256="pending"
if [ -f "$command_env_path" ]; then
  if command -v sha256sum >/dev/null 2>&1; then
    command_environment_sha256="$(sha256sum "$command_env_path" | sed -n "1{s/[[:space:]].*//;p;q;}")"
    [ -n "$command_environment_sha256" ] || command_environment_sha256="missing"
  else
    command_environment_sha256="unavailable"
  fi
fi
hardware_identity_sha256="pending"
if [ -f "$hardware_output_path" ]; then
  if command -v sha256sum >/dev/null 2>&1; then
    hardware_identity_sha256="$(sha256sum "$hardware_output_path" | sed -n "1{s/[[:space:]].*//;p;q;}")"
    [ -n "$hardware_identity_sha256" ] || hardware_identity_sha256="missing"
  else
    hardware_identity_sha256="unavailable"
  fi
fi
pareas_source_sha256="not-run"
if [ -f "$pareas_source_sha256_path" ]; then
  pareas_source_sha256="$(sed -n "1{s/[[:space:]].*//;p;q;}" "$pareas_source_sha256_path")"
  [ -n "$pareas_source_sha256" ] || pareas_source_sha256="missing"
fi
pareas_binary_sha256="not-run"
if [ -f "$pareas_binary_sha256_path" ]; then
  pareas_binary_sha256="$(sed -n "1{s/[[:space:]].*//;p;q;}" "$pareas_binary_sha256_path")"
  [ -n "$pareas_binary_sha256" ] || pareas_binary_sha256="missing"
fi
status_first() {
  grep -E "^$1=" "$command_status_path" | head -n1 | cut -d= -f2-
}
status_last() {
  grep -E "^$1=" "$command_status_path" | tail -n1 | cut -d= -f2-
}
lanius_exit_status="pending"
lanius_wall_elapsed_ms="pending"
machine_responsive_after="pending"
responsiveness_probe_status="pending"
resource_usage_status="pending"
nvidia_smi_exit_status="not-run"
pareas_exit_status="not-run"
pareas_wall_elapsed_ms="not-run"
pareas_bin_path="not-run"
if [ -f "$command_status_path" ]; then
  lanius_exit_status="$(status_first lanius_exit_status)"
  [ -n "$lanius_exit_status" ] || lanius_exit_status="missing"
  lanius_wall_elapsed_ms="$(status_first lanius_wall_elapsed_ms)"
  [ -n "$lanius_wall_elapsed_ms" ] || lanius_wall_elapsed_ms="missing"
  machine_responsive_after="$(status_last machine_responsive_after)"
  [ -n "$machine_responsive_after" ] || machine_responsive_after="missing"
  responsiveness_probe_status="$(status_last responsiveness_probe_status)"
  [ -n "$responsiveness_probe_status" ] || responsiveness_probe_status="missing"
  resource_usage_status="$(status_first resource_usage_status)"
  [ -n "$resource_usage_status" ] || resource_usage_status="missing"
  maybe_nvidia_smi_exit_status="$(status_last nvidia_smi_exit_status)"
  [ -n "$maybe_nvidia_smi_exit_status" ] && nvidia_smi_exit_status="$maybe_nvidia_smi_exit_status"
  maybe_pareas_exit_status="$(status_last pareas_exit_status)"
  [ -n "$maybe_pareas_exit_status" ] && pareas_exit_status="$maybe_pareas_exit_status"
  maybe_pareas_wall_elapsed_ms="$(status_last pareas_wall_elapsed_ms)"
  [ -n "$maybe_pareas_wall_elapsed_ms" ] && pareas_wall_elapsed_ms="$maybe_pareas_wall_elapsed_ms"
  maybe_pareas_bin_path="$(status_last pareas_bin_path)"
  [ -n "$maybe_pareas_bin_path" ] && pareas_bin_path="$maybe_pareas_bin_path"
fi
timed_out="pending"
case "$lanius_exit_status" in
  124) timed_out="true" ;;
  pending|missing|"") timed_out="pending" ;;
  *) timed_out="false" ;;
esac
pareas_timed_out="not-run"
case "$pareas_exit_status" in
  124) pareas_timed_out="true" ;;
  not-run) pareas_timed_out="not-run" ;;
  pending|missing|"") pareas_timed_out="pending" ;;
  *) pareas_timed_out="false" ;;
esac
lanius_pareas_wall_ratio="pending"
case "$pareas_exit_status" in
  not-run) lanius_pareas_wall_ratio="not-run" ;;
esac
case "$lanius_wall_elapsed_ms:$pareas_wall_elapsed_ms" in
  *[!0-9:]*|:*|*:0) ;;
  *) lanius_pareas_wall_ratio="$(awk -v l="$lanius_wall_elapsed_ms" -v p="$pareas_wall_elapsed_ms" "BEGIN { printf \"%.6f\", l / p }")" ;;
esac
best_ms="pending"
if [ -f "$lanius_stdout_path" ]; then
  best_ms="$(tr " " "\n" <"$lanius_stdout_path" | sed -n "s/^best_ms=//p;q")"
  [ -n "$best_ms" ] || best_ms="missing"
fi
throughput_lines_per_second="pending"
case "$line_count:$best_ms" in
  *[!0-9:.]*|:*|*:) ;;
  *) throughput_lines_per_second="$(awk -v lines="$line_count" -v ms="$best_ms" "BEGIN { if ((ms + 0) > 0) printf \"%.6f\", (lines * 1000.0) / ms; else printf \"missing\" }")" ;;
esac
[ -n "$throughput_lines_per_second" ] || throughput_lines_per_second="missing"
readback_span_count="pending"
readback_total_ms="pending"
readback_max_span_ms="pending"
if [ -f "$readback_summary_path" ]; then
  readback_span_count="$(grep -E "^span_count=" "$readback_summary_path" | head -n1 | cut -d= -f2-)"
  [ -n "$readback_span_count" ] || readback_span_count="missing"
  readback_total_ms="$(grep -E "^total_ms=" "$readback_summary_path" | head -n1 | cut -d= -f2-)"
  [ -n "$readback_total_ms" ] || readback_total_ms="missing"
  readback_max_span_ms="$(grep -E "^max_span_ms=" "$readback_summary_path" | head -n1 | cut -d= -f2-)"
  [ -n "$readback_max_span_ms" ] || readback_max_span_ms="missing"
fi
max_vram_bytes="pending"
if [ -f "$vram_output_path" ]; then
  max_vram_bytes="$(awk -F, "NR > 1 { used = \$4; gsub(/[^0-9]/, \"\", used); if (used + 0 > max) max = used + 0 } END { if (max > 0) printf \"%.0f\", max * 1048576; else printf \"missing\" }" "$vram_output_path")"
fi
resource_user_seconds="pending"
resource_system_seconds="pending"
resource_max_rss_kb="pending"
if [ -f "$resource_usage_path" ]; then
  resource_user_seconds="$(grep -E "^\\s*User time \\(seconds\\):" "$resource_usage_path" | head -n1 | sed "s/.*: //")"
  [ -n "$resource_user_seconds" ] || resource_user_seconds="missing"
  resource_system_seconds="$(grep -E "^\\s*System time \\(seconds\\):" "$resource_usage_path" | head -n1 | sed "s/.*: //")"
  [ -n "$resource_system_seconds" ] || resource_system_seconds="missing"
  resource_max_rss_kb="$(grep -E "^\\s*Maximum resident set size \\(kbytes\\):" "$resource_usage_path" | head -n1 | sed "s/.*: //")"
  [ -n "$resource_max_rss_kb" ] || resource_max_rss_kb="missing"
fi
stale_artifacts=""
append_stale_artifact() {
  if [ -n "$stale_artifacts" ]; then
    stale_artifacts="${stale_artifacts},$1"
  else
    stale_artifacts="$1"
  fi
}
first_field_from_file() {
  grep -E "^$2=" "$1" | head -n1 | cut -d= -f2-
}
last_field_from_file() {
  grep -E "^$2=" "$1" | tail -n1 | cut -d= -f2-
}
check_file_field_equals() {
  artifact_name="$1"
  artifact_path="$2"
  field_name="$3"
  expected_value="$4"
  if [ -f "$artifact_path" ]; then
    actual_value="$(first_field_from_file "$artifact_path" "$field_name")"
    if [ "$actual_value" != "$expected_value" ]; then
      append_stale_artifact "${artifact_name}:${field_name}"
    fi
  fi
}
check_file_last_field_equals() {
  artifact_name="$1"
  artifact_path="$2"
  field_name="$3"
  expected_value="$4"
  if [ -f "$artifact_path" ]; then
    actual_value="$(last_field_from_file "$artifact_path" "$field_name")"
    if [ "$actual_value" != "$expected_value" ]; then
      append_stale_artifact "${artifact_name}:${field_name}"
    fi
  fi
}
check_file_field_present() {
  artifact_name="$1"
  artifact_path="$2"
  field_name="$3"
  if [ -f "$artifact_path" ]; then
    actual_value="$(first_field_from_file "$artifact_path" "$field_name")"
    if [ -z "$actual_value" ]; then
      append_stale_artifact "${artifact_name}:${field_name}"
    fi
  fi
}
check_vram_csv_header() {
  if [ -f "$vram_output_path" ]; then
    actual_header="$(sed -n "1p;q" "$vram_output_path" | sed "s/[[:space:]]//g; s/\\[[^]]*\\]//g")"
    expected_header="timestamp,index,name,memory.used,memory.total,utilization.gpu"
    if [ "$actual_header" != "$expected_header" ]; then
      append_stale_artifact "vram_csv:header"
    fi
  fi
}
is_unsigned_integer() {
  case "${1:-}" in
    ""|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}
is_nonnegative_number() {
  awk -v value="${1:-}" "BEGIN { exit (value ~ /^[0-9]+([.][0-9]+)?$/) ? 0 : 1 }"
}
check_metric_unsigned_if_present() {
  artifact_name="$1"
  field_name="$2"
  value="$3"
  case "$value" in
    ""|pending|missing|not-run|unavailable) return ;;
  esac
  if ! is_unsigned_integer "$value"; then
    append_stale_artifact "${artifact_name}:${field_name}:nonnumeric"
  fi
}
check_metric_number_if_present() {
  artifact_name="$1"
  field_name="$2"
  value="$3"
  case "$value" in
    ""|pending|missing|not-run|unavailable) return ;;
  esac
  if ! is_nonnegative_number "$value"; then
    append_stale_artifact "${artifact_name}:${field_name}:nonnumeric"
  fi
}
check_resource_usage_command_identity() {
  if [ "$resource_usage_status" = "0" ] && [ -f "$resource_usage_path" ]; then
    resource_usage_command="$(grep -F "Command being timed:" "$resource_usage_path" | head -n1 || true)"
    resource_usage_command_stale=false
    for expected_fragment in "target/release/gpu_compile_bench" "--phase $phase" "--emit $target" "--source $source" "--lines $line_count" "--seed $seed" "--iters $iterations"; do
      case "$resource_usage_command" in
        *"$expected_fragment"*) ;;
        *) resource_usage_command_stale=true ;;
      esac
    done
    if [ "$resource_usage_command_stale" = "true" ]; then
      append_stale_artifact "resource_usage:command"
    fi
  fi
}
check_readback_span_metrics_consistent() {
  if [ -f "$readback_summary_path" ] &&
    is_unsigned_integer "$readback_span_count" &&
    is_nonnegative_number "$readback_total_ms" &&
    is_nonnegative_number "$readback_max_span_ms"; then
    if ! awk -v spans="$readback_span_count" -v total="$readback_total_ms" -v max_span="$readback_max_span_ms" "BEGIN { if (spans == 0) { if (total == 0 && max_span == 0) exit 0; exit 1 } if (max_span <= total) exit 0; exit 1 }"; then
      append_stale_artifact "readback_summary:span-metrics"
    fi
  fi
}
check_source_replay_line_count_covers_checkpoint() {
  if [ -f "$source_replay_path" ] &&
    is_unsigned_integer "$source_replay_line_count" &&
    is_unsigned_integer "$line_count" &&
    [ "$source_replay_line_count" -lt "$line_count" ]; then
    append_stale_artifact "source_replay:line_count"
  fi
}
check_status_field_equals() {
  check_file_field_equals command_status "$command_status_path" "$1" "$2"
}
check_status_last_field_equals() {
  check_file_last_field_equals "$1" "$command_status_path" "$2" "$3"
}
check_hash_file_matches() {
  artifact_name="$1"
  input_path="$2"
  hash_path="$3"
  if [ -f "$hash_path" ]; then
    if [ ! -f "$input_path" ]; then
      append_stale_artifact "${artifact_name}:missing-input"
    elif ! command -v sha256sum >/dev/null 2>&1; then
      append_stale_artifact "${artifact_name}:sha256sum-unavailable"
    else
      recorded_hash="$(sed -n "1{s/[[:space:]].*//;p;q;}" "$hash_path")"
      current_hash="$(sha256sum "$input_path" | sed -n "1{s/[[:space:]].*//;p;q;}")"
      if [ -z "$recorded_hash" ] || [ "$recorded_hash" != "$current_hash" ]; then
        append_stale_artifact "${artifact_name}:sha256-mismatch"
      fi
    fi
  fi
}
check_hash_file_matches source_sha256 "$source_replay_path" "$source_sha256_path"
check_hash_file_matches bench_binary_sha256 target/release/gpu_compile_bench "$bench_sha256_path"
if [ -f "$pareas_source_sha256_path" ]; then
  check_hash_file_matches pareas_source_sha256 "$pareas_source_path" "$pareas_source_sha256_path"
fi
if [ -f "$pareas_binary_sha256_path" ]; then
  case "$pareas_bin_path" in
    ""|pending|missing|not-run|unavailable)
      append_stale_artifact "pareas_binary_sha256:pareas_bin_path"
      ;;
    *)
      check_hash_file_matches pareas_binary_sha256 "$pareas_bin_path" "$pareas_binary_sha256_path"
      ;;
  esac
fi
check_status_field_equals command_status_schema lanius.command-status.v1
check_status_field_equals measurement_timing_policy "$timing_policy"
check_status_field_equals cold_start_policy "$cold_start_policy"
check_status_field_equals compile_latency_claim_source "$compile_latency_claim_source"
check_status_field_equals runtime_validation_policy "$runtime_validation_policy"
check_status_field_equals timeout_provenance_schema "$timeout_provenance_schema"
check_status_field_equals timeout_scope "$timeout_scope"
check_status_field_equals timeout_ms "$timeout_ms"
check_status_field_equals timeout_seconds "$timeout_seconds"
check_status_field_equals timeout_source "$timeout_source"
check_status_field_equals timeout_enforced_by "$timeout_enforced_by"
check_status_field_equals timeout_exit_code "$timeout_exit_code"
check_status_field_equals timeout_exit_code_means_timed_out "$timeout_exit_code_means_timed_out"
check_status_field_equals line_count "$line_count"
check_status_field_equals source "$source"
check_status_field_equals phase "$phase"
check_status_field_equals target "$target"
check_status_field_equals source_seed "$seed"
check_status_field_equals iterations "$iterations"
check_status_field_equals readback_timeout_ms "$readback_timeout_ms"
check_status_field_equals vram_sample_interval_ms "$vram_sample_interval_ms"
check_status_field_equals lanius_stdout_path "$lanius_stdout_path"
check_status_field_equals perfetto_trace_path "$perfetto_trace_path"
check_status_field_equals resource_usage_path "$resource_usage_path"
check_status_field_equals responsiveness_probe_path "$responsiveness_probe_path"
if [ -f "$vram_output_path" ] || [ "$nvidia_smi_exit_status" != "not-run" ]; then
  check_status_last_field_equals vram_status nvidia_smi_exit_status "$nvidia_smi_exit_status"
  check_status_last_field_equals vram_status line_count "$line_count"
  check_status_last_field_equals vram_status timeout_seconds "$timeout_seconds"
  check_status_last_field_equals vram_status vram_sample_interval_ms "$vram_sample_interval_ms"
  check_status_last_field_equals vram_status vram_output_path "$vram_output_path"
fi
if [ "$pareas_exit_status" != "not-run" ] || [ -e "$pareas_output_path" ] || [ -e "$pareas_stdout_path" ]; then
  check_status_last_field_equals pareas_status pareas_exit_status "$pareas_exit_status"
  check_status_last_field_equals pareas_status timeout_seconds "$timeout_seconds"
  check_status_last_field_equals pareas_status line_count "$line_count"
  check_status_last_field_equals pareas_status pareas_bin_path "$pareas_bin_path"
  check_status_last_field_equals pareas_status pareas_source_path "$pareas_source_path"
  check_status_last_field_equals pareas_status pareas_output_path "$pareas_output_path"
  check_status_last_field_equals pareas_status pareas_stdout_path "$pareas_stdout_path"
fi
check_file_field_equals command_environment "$command_env_path" command_environment_schema lanius.command-environment.v1
check_file_field_equals command_environment "$command_env_path" line_count "$line_count"
check_file_field_equals command_environment "$command_env_path" source "$source"
check_file_field_equals command_environment "$command_env_path" phase "$phase"
check_file_field_equals command_environment "$command_env_path" target "$target"
check_file_field_equals command_environment "$command_env_path" iterations "$iterations"
check_file_field_equals command_environment "$command_env_path" measurement_timing_policy "$timing_policy"
check_file_field_equals command_environment "$command_env_path" cold_start_policy "$cold_start_policy"
check_file_field_equals command_environment "$command_env_path" compile_latency_claim_source "$compile_latency_claim_source"
check_file_field_equals command_environment "$command_env_path" runtime_validation_policy "$runtime_validation_policy"
check_file_field_equals command_environment "$command_env_path" claim_provenance_schema "$claim_provenance_schema"
check_file_field_equals command_environment "$command_env_path" baseline_separation_schema "$baseline_separation_schema"
check_file_field_equals command_environment "$command_env_path" paper_baseline_policy "$paper_baseline_policy"
check_file_field_equals command_environment "$command_env_path" paper_baseline_numbers_status "$paper_baseline_numbers_status"
check_file_field_equals command_environment "$command_env_path" local_evidence_status_policy "$local_evidence_status_policy"
check_file_field_equals command_environment "$command_env_path" local_performance_claim_policy "$local_performance_claim_policy"
check_file_field_equals command_environment "$command_env_path" local_performance_claim_source "$local_performance_claim_source"
check_file_field_equals command_environment "$command_env_path" local_performance_claim_status "$local_performance_claim_status"
check_file_field_equals command_environment "$command_env_path" local_performance_claim_blockers "$local_performance_claim_blockers"
check_file_field_equals command_environment "$command_env_path" local_vram_claim_source "$local_vram_claim_source"
check_file_field_equals command_environment "$command_env_path" local_pareas_claim_source "$local_pareas_claim_source"
check_file_field_equals command_environment "$command_env_path" scaling_claim_policy "$scaling_claim_policy"
check_file_field_equals command_environment "$command_env_path" scaling_claim_source "$scaling_claim_source"
check_file_field_equals command_environment "$command_env_path" scaling_claim_status "$scaling_claim_status"
check_file_field_equals command_environment "$command_env_path" scaling_claim_blockers "$scaling_claim_blockers"
check_file_field_equals command_environment "$command_env_path" paper_pass_order_schema "$paper_pass_order_schema"
check_file_field_equals command_environment "$command_env_path" paper_pass_order_source "$paper_pass_order_source"
check_file_field_equals command_environment "$command_env_path" paper_pass_order "$paper_pass_order"
check_file_field_equals command_environment "$command_env_path" paper_pass_alignment_policy "$paper_pass_alignment_policy"
check_file_field_equals command_environment "$command_env_path" paper_pass_alignment_status "$paper_pass_alignment_status"
check_file_field_equals command_environment "$command_env_path" paper_pass_alignment_blockers "$paper_pass_alignment_blockers"
check_file_field_equals command_environment "$command_env_path" parallel_pass_contract_schema "$parallel_pass_contract_schema"
check_file_field_equals command_environment "$command_env_path" parallel_pass_contract_policy "$parallel_pass_contract_policy"
check_file_field_equals command_environment "$command_env_path" parallel_pass_contract_groups "$parallel_pass_contract_groups"
check_file_field_equals command_environment "$command_env_path" parallel_pass_contract_order_policy "$parallel_pass_contract_order_policy"
check_file_field_equals command_environment "$command_env_path" parallel_pass_contract_execution_order "$parallel_pass_contract_execution_order"
check_file_field_equals command_environment "$command_env_path" pass_contract_status_schema "$pass_contract_status_schema"
check_file_field_equals command_environment "$command_env_path" pass_contract_loop_policy "$pass_contract_loop_policy"
check_file_field_equals command_environment "$command_env_path" pass_contract_loop_status "$pass_contract_loop_status"
check_file_field_equals command_environment "$command_env_path" pass_contract_fallback_status "$pass_contract_fallback_status"
check_file_field_equals command_environment "$command_env_path" pass_contract_claim_status "$pass_contract_claim_status"
check_file_field_equals command_environment "$command_env_path" pass_contract_claim_blockers "$pass_contract_claim_blockers"
pass_contract_readiness_status=blocked
if [ "$pass_contract_loop_status" = "unbounded" ] &&
  [ "$pass_contract_fallback_status" = "none" ] &&
  [ "$pass_contract_claim_status" = "claimable" ]; then
  pass_contract_readiness_status=claimable
fi
check_file_field_equals command_environment "$command_env_path" pass_contract_readiness_status "$pass_contract_readiness_status"
check_file_field_equals command_environment "$command_env_path" timeout_provenance_schema "$timeout_provenance_schema"
check_file_field_equals command_environment "$command_env_path" timeout_scope "$timeout_scope"
check_file_field_equals command_environment "$command_env_path" timeout_source "$timeout_source"
check_file_field_equals command_environment "$command_env_path" timeout_ms "$timeout_ms"
check_file_field_equals command_environment "$command_env_path" timeout_seconds "$timeout_seconds"
check_file_field_equals command_environment "$command_env_path" readback_timeout_ms "$readback_timeout_ms"
check_file_field_equals command_environment "$command_env_path" vram_sample_interval_ms "$vram_sample_interval_ms"
check_file_field_equals command_environment "$command_env_path" source_seed "$seed"
check_file_field_equals command_environment "$command_env_path" responsiveness_probe_timeout_ms "$responsiveness_timeout_ms"
check_file_field_equals command_environment "$command_env_path" responsiveness_probe_timeout_seconds "$responsiveness_timeout_seconds"
check_file_field_present command_environment "$command_env_path" rustc_version
check_file_field_present command_environment "$command_env_path" cargo_version
check_file_field_present command_environment "$command_env_path" slangc_version
check_file_field_equals readback_summary "$readback_summary_path" readback_summary_schema lanius.readback-summary.v1
check_file_field_equals readback_summary "$readback_summary_path" line_count "$line_count"
check_file_field_equals readback_summary "$readback_summary_path" source "$source"
check_file_field_equals readback_summary "$readback_summary_path" phase "$phase"
check_file_field_equals readback_summary "$readback_summary_path" target "$target"
check_file_field_equals readback_summary "$readback_summary_path" trace_path "$perfetto_trace_path"
check_file_field_equals readback_summary "$readback_summary_path" readback_timeout_ms "$readback_timeout_ms"
check_file_field_equals responsiveness_probe "$responsiveness_probe_path" responsiveness_probe_schema lanius.responsiveness-probe.v1
check_file_field_equals responsiveness_probe "$responsiveness_probe_path" line_count "$line_count"
check_file_field_equals responsiveness_probe "$responsiveness_probe_path" source "$source"
check_file_field_equals responsiveness_probe "$responsiveness_probe_path" phase "$phase"
check_file_field_equals responsiveness_probe "$responsiveness_probe_path" target "$target"
check_file_field_equals responsiveness_probe "$responsiveness_probe_path" timeout_ms "$responsiveness_timeout_ms"
check_file_field_equals responsiveness_probe "$responsiveness_probe_path" timeout_seconds "$responsiveness_timeout_seconds"
check_file_field_equals hardware_identity "$hardware_output_path" hardware_identity_schema lanius.hardware-identity.v1
check_file_field_equals hardware_identity "$hardware_output_path" target "$target"
check_vram_csv_header
check_resource_usage_command_identity
check_metric_unsigned_if_present command_status lanius_wall_elapsed_ms "$lanius_wall_elapsed_ms"
check_metric_number_if_present lanius_stdout best_ms "$best_ms"
check_metric_number_if_present lanius_stdout throughput_lines_per_second "$throughput_lines_per_second"
check_metric_unsigned_if_present readback_summary span_count "$readback_span_count"
check_metric_number_if_present readback_summary total_ms "$readback_total_ms"
check_metric_number_if_present readback_summary max_span_ms "$readback_max_span_ms"
check_metric_unsigned_if_present vram_csv max_vram_bytes "$max_vram_bytes"
check_metric_number_if_present resource_usage resource_user_seconds "$resource_user_seconds"
check_metric_number_if_present resource_usage resource_system_seconds "$resource_system_seconds"
check_metric_unsigned_if_present resource_usage resource_max_rss_kb "$resource_max_rss_kb"
check_metric_unsigned_if_present source_replay source_replay_line_count "$source_replay_line_count"
check_metric_unsigned_if_present pareas_status pareas_wall_elapsed_ms "$pareas_wall_elapsed_ms"
check_metric_number_if_present pareas_stdout lanius_pareas_wall_ratio "$lanius_pareas_wall_ratio"
check_readback_span_metrics_consistent
check_source_replay_line_count_covers_checkpoint
source_control_policy=git-head-plus-status-in-command-environment-hash
source_control_state=pending
source_control_revision=pending
is_git_commit_hash() {
  case "${1:-}" in
    ""|*[!0-9a-fA-F]*) return 1 ;;
    *) [ "${#1}" -eq 40 ] ;;
  esac
}
git_commit_is_local_to_command_environment() {
  commit="$1"
  command_cwd="$(first_field_from_file "$command_env_path" cwd)"
  if ! command -v git >/dev/null 2>&1; then
    return 1
  fi
  if [ -n "$command_cwd" ] && [ -d "$command_cwd" ]; then
    git -C "$command_cwd" cat-file -e "${commit}^{commit}" >/dev/null 2>&1
  else
    git cat-file -e "${commit}^{commit}" >/dev/null 2>&1
  fi
}
if [ -f "$command_env_path" ]; then
  git_head_value="$(first_field_from_file "$command_env_path" git_head)"
  if [ -z "$git_head_value" ] || [ "$git_head_value" = "unavailable" ]; then
    source_control_state=unavailable
    source_control_revision=unavailable
  elif ! is_git_commit_hash "$git_head_value"; then
    source_control_state=unavailable
    source_control_revision=unavailable
  elif ! git_commit_is_local_to_command_environment "$git_head_value"; then
    source_control_state=unavailable
    source_control_revision=unavailable
    append_stale_artifact "command_environment:git_head:not-local"
  elif ! grep -q "^git_status_short_begin$" "$command_env_path" || ! grep -q "^git_status_short_end$" "$command_env_path"; then
    source_control_state=unavailable
    source_control_revision="$git_head_value"
  elif awk "/^git_status_short_begin$/ { inside=1; next } /^git_status_short_end$/ { inside=0 } inside && NF { found=1 } END { exit found ? 0 : 1 }" "$command_env_path"; then
    source_control_state=dirty
    source_control_revision="$git_head_value"
  else
    source_control_state=clean
    source_control_revision="$git_head_value"
  fi
elif [ ! -f "$command_env_path" ]; then
  source_control_state=missing
  source_control_revision=missing
fi
stale_artifact_checks="source_sha256_matches_source_replay,source_replay_line_count_covers_checkpoint,bench_binary_sha256_matches_binary,pareas_source_sha256_matches_pareas_source,pareas_binary_sha256_matches_pareas_binary,command_status_schema_checkpoint_timing_policy_timeout_provenance_and_paths,vram_status_matches_checkpoint,vram_csv_header_matches_required_columns,pareas_status_matches_checkpoint,command_environment_schema_checkpoint_timing_policy_timeout_provenance_tool_versions_claim_provenance_baseline_separation_paper_pass_order_pass_contracts_loop_status_and_readiness,source_control_revision_is_local_git_commit,claim_provenance_fields_match_checkpoint,paper_baseline_and_local_evidence_separation_match_checkpoint,paper_pass_order_matches_checkpoint,paper_pass_alignment_status_matches_checkpoint,parallel_pass_contracts_match_checkpoint,parallel_pass_contract_order_matches_checkpoint,pass_contract_loop_fallback_and_readiness_status_match_checkpoint,readback_summary_matches_checkpoint,readback_summary_span_metrics_are_consistent,responsiveness_probe_matches_checkpoint,hardware_identity_matches_target,resource_usage_command_matches_checkpoint,quantitative_artifact_fields_are_numeric"
if [ -n "$stale_artifacts" ]; then
  evidence_freshness_status=stale
else
  stale_artifacts=none
  if [ "$missing_required_artifacts" = "none" ]; then
    evidence_freshness_status=complete
  else
    evidence_freshness_status=unknown
  fi
fi
value_present() {
  case "${1:-}" in
    ""|pending|missing|not-run|unavailable) return 1 ;;
    *) return 0 ;;
  esac
}
numeric_value_present() {
  value_present "$1" && is_nonnegative_number "$1"
}
unsigned_value_present() {
  value_present "$1" && is_unsigned_integer "$1"
}
append_blocker() {
  if [ -n "$production_readiness_blockers" ]; then
    production_readiness_blockers="${production_readiness_blockers},$1"
  else
    production_readiness_blockers="$1"
  fi
}
local_performance_evidence_status=incomplete
if [ "$lanius_exit_status" = "0" ] &&
  [ "$timed_out" = "false" ] &&
  unsigned_value_present "$lanius_wall_elapsed_ms" &&
  numeric_value_present "$best_ms" &&
  numeric_value_present "$throughput_lines_per_second" &&
  value_present "$source_sha256" &&
  value_present "$bench_binary_sha256" &&
  value_present "$hardware_identity_sha256" &&
  value_present "$command_environment_sha256" &&
  [ "$resource_usage_status" = "0" ] &&
  numeric_value_present "$resource_user_seconds" &&
  numeric_value_present "$resource_system_seconds" &&
  unsigned_value_present "$resource_max_rss_kb"; then
  local_performance_evidence_status=complete
elif [ "$lanius_exit_status" = "pending" ] || [ "$lanius_exit_status" = "missing" ]; then
  local_performance_evidence_status=missing
elif [ "$timed_out" = "true" ]; then
  local_performance_evidence_status=timed-out
else
  local_performance_evidence_status=failed
fi
local_readback_evidence_status=incomplete
if unsigned_value_present "$readback_span_count" &&
  numeric_value_present "$readback_total_ms" &&
  numeric_value_present "$readback_max_span_ms"; then
  local_readback_evidence_status=complete
elif [ ! -f "$readback_summary_path" ]; then
  local_readback_evidence_status=missing
fi
local_vram_evidence_status=incomplete
if [ "$nvidia_smi_exit_status" = "0" ] && unsigned_value_present "$max_vram_bytes"; then
  local_vram_evidence_status=complete
elif [ ! -f "$vram_output_path" ]; then
  local_vram_evidence_status=missing
elif [ "$nvidia_smi_exit_status" = "not-run" ] ||
  [ "$nvidia_smi_exit_status" = "pending" ] ||
  [ "$nvidia_smi_exit_status" = "missing" ]; then
  local_vram_evidence_status=missing
elif [ "$nvidia_smi_exit_status" = "124" ]; then
  local_vram_evidence_status=timed-out
else
  local_vram_evidence_status=failed
fi
local_pareas_evidence_status=incomplete
if [ "$pareas_exit_status" = "0" ] &&
  [ "$pareas_timed_out" = "false" ] &&
  unsigned_value_present "$pareas_wall_elapsed_ms" &&
  value_present "$pareas_source_sha256" &&
  value_present "$pareas_binary_sha256" &&
  [ -e "$pareas_output_path" ] &&
  [ -e "$pareas_stdout_path" ]; then
  local_pareas_evidence_status=complete
elif [ "$pareas_exit_status" = "not-run" ]; then
  local_pareas_evidence_status=not-run
elif [ "$pareas_exit_status" = "pending" ] || [ "$pareas_exit_status" = "missing" ]; then
  local_pareas_evidence_status=missing
elif [ "$pareas_timed_out" = "true" ]; then
  local_pareas_evidence_status=timed-out
else
  local_pareas_evidence_status=failed
fi
repeatability_policy=claimable-metrics-require-at-least-three-iterations
minimum_iterations_for_claim=3
repeatability_status=insufficient
case "$iterations:$minimum_iterations_for_claim" in
  *[!0-9:]*|:*|*:) repeatability_status=invalid ;;
  *)
    if [ "$iterations" -ge "$minimum_iterations_for_claim" ]; then
      repeatability_status=complete
    fi
    ;;
esac
production_readiness_blockers=""
[ "$required_artifacts_complete" = "true" ] || append_blocker "missing_required_artifacts:${missing_required_artifacts}"
[ "$local_performance_evidence_status" = "complete" ] || append_blocker "performance:${local_performance_evidence_status}"
[ "$local_performance_claim_status" = "claimable" ] || append_blocker "performance_claim:${local_performance_claim_status}:${local_performance_claim_blockers}"
[ "$local_readback_evidence_status" = "complete" ] || append_blocker "readback:${local_readback_evidence_status}"
[ "$local_vram_evidence_status" = "complete" ] || append_blocker "vram:${local_vram_evidence_status}"
[ "$local_pareas_evidence_status" = "complete" ] || append_blocker "pareas:${local_pareas_evidence_status}"
[ "$scaling_claim_status" = "claimable" ] || append_blocker "scaling_claim:${scaling_claim_status}:${scaling_claim_blockers}"
[ "$paper_pass_alignment_status" = "claimable" ] || append_blocker "paper_pass_alignment:${paper_pass_alignment_status}:${paper_pass_alignment_blockers}"
case "$source_control_state" in
  clean|dirty) ;;
  *) append_blocker "source_control:${source_control_state}" ;;
esac
[ "$pass_contract_readiness_status" = "claimable" ] || append_blocker "pass_contracts:${pass_contract_readiness_status}:loop_${pass_contract_loop_status}:fallback_${pass_contract_fallback_status}:claim_${pass_contract_claim_status}:${pass_contract_claim_blockers}"
[ "$repeatability_status" = "complete" ] || append_blocker "repeatability:${repeatability_status}:iterations_${iterations}_lt_${minimum_iterations_for_claim}"
[ "$evidence_freshness_status" = "complete" ] || append_blocker "freshness:${evidence_freshness_status}:${stale_artifacts}"
[ "$machine_responsive_after" = "true" ] || append_blocker "responsiveness:${machine_responsive_after}"
if [ -z "$production_readiness_blockers" ]; then
  production_readiness_evidence_complete=true
  production_readiness_blockers=none
else
  production_readiness_evidence_complete=false
fi
claim_readiness_status=not-claimable
claimable_measurement_claims=none
claim_readiness_blockers="$production_readiness_blockers"
claim_readiness_required_evidence_classes="local_performance,local_performance_claim,local_readback,local_vram,local_pareas,resource_usage,responsiveness,source_control,freshness,repeatability,paper_pass_alignment,parallel_pass_contracts,scaling_claim"
claim_readiness_required_statuses="local_performance_evidence_status=complete;local_performance_claim_status=claimable;local_readback_evidence_status=complete;local_vram_evidence_status=complete;local_pareas_evidence_status=complete;resource_usage_status=0;machine_responsive_after=true;source_control_state=clean-or-dirty;source_control_revision=local-git-commit-sha;evidence_freshness_status=complete;repeatability_status=complete;paper_pass_alignment_status=claimable;pass_contract_loop_status=unbounded;pass_contract_fallback_status=none;pass_contract_claim_status=claimable;pass_contract_readiness_status=claimable;scaling_claim_status=claimable"
claim_scope_policy=exact-local-checkpoint-hardware-source-binary-only
claim_scope_key="line_count:${line_count};source:${source};phase:${phase};target:${target};seed:${seed};iterations:${iterations};minimum_iterations_for_claim:${minimum_iterations_for_claim};repeatability_status:${repeatability_status};paper_pass_order:${paper_pass_order};paper_pass_alignment_status:${paper_pass_alignment_status};paper_pass_alignment_blockers:${paper_pass_alignment_blockers};parallel_pass_contract_execution_order:${parallel_pass_contract_execution_order};pass_contract_loop_status:${pass_contract_loop_status};pass_contract_fallback_status:${pass_contract_fallback_status};pass_contract_claim_status:${pass_contract_claim_status};pass_contract_readiness_status:${pass_contract_readiness_status};local_performance_claim_status:${local_performance_claim_status};scaling_claim_status:${scaling_claim_status};source_control_state:${source_control_state};source_control_revision:${source_control_revision};source_replay_line_count:${source_replay_line_count};source_sha256:${source_sha256};bench_binary_sha256:${bench_binary_sha256};hardware_identity_sha256:${hardware_identity_sha256};command_environment_sha256:${command_environment_sha256};pareas_binary_sha256:${pareas_binary_sha256}"
if [ "$production_readiness_evidence_complete" = "true" ]; then
  claim_readiness_status=claimable
  claimable_measurement_claims=checkpoint_local_latency,checkpoint_local_throughput,checkpoint_local_readback,checkpoint_local_vram,checkpoint_local_pareas_wall_ratio
  claim_readiness_blockers=none
fi
{
  printf "measurement_summary_schema=lanius.measurement-summary.v1\n"
  printf "line_count=%s\n" "$line_count"
  printf "source=%s\n" "$source"
  printf "phase=%s\n" "$phase"
  printf "target=%s\n" "$target"
  printf "evidence_provenance=local-run\n"
  printf "measurement_evidence_policy=local-artifacts-only\n"
  printf "paper_numbers_accepted=false\n"
  printf "comparison_baseline_policy=local-pareas-artifacts-only\n"
  printf "freshness_policy=hash-and-checkpoint-field-match\n"
  printf "measurement_timing_policy=%s\n" "$timing_policy"
  printf "cold_start_policy=%s\n" "$cold_start_policy"
  printf "compile_latency_claim_source=%s\n" "$compile_latency_claim_source"
  printf "runtime_validation_policy=%s\n" "$runtime_validation_policy"
  printf "claim_provenance_schema=%s\n" "$claim_provenance_schema"
  printf "baseline_separation_schema=%s\n" "$baseline_separation_schema"
  printf "paper_baseline_policy=%s\n" "$paper_baseline_policy"
  printf "paper_baseline_numbers_status=%s\n" "$paper_baseline_numbers_status"
  printf "local_evidence_status_policy=%s\n" "$local_evidence_status_policy"
  printf "local_performance_claim_policy=%s\n" "$local_performance_claim_policy"
  printf "local_performance_claim_source=%s\n" "$local_performance_claim_source"
  printf "local_performance_claim_status=%s\n" "$local_performance_claim_status"
  printf "local_performance_claim_blockers=%s\n" "$local_performance_claim_blockers"
  printf "local_vram_claim_source=%s\n" "$local_vram_claim_source"
  printf "local_pareas_claim_source=%s\n" "$local_pareas_claim_source"
  printf "scaling_claim_policy=%s\n" "$scaling_claim_policy"
  printf "scaling_claim_source=%s\n" "$scaling_claim_source"
  printf "scaling_claim_status=%s\n" "$scaling_claim_status"
  printf "scaling_claim_blockers=%s\n" "$scaling_claim_blockers"
  printf "paper_pass_order_schema=%s\n" "$paper_pass_order_schema"
  printf "paper_pass_order_source=%s\n" "$paper_pass_order_source"
  printf "paper_pass_order=%s\n" "$paper_pass_order"
  printf "paper_pass_alignment_policy=%s\n" "$paper_pass_alignment_policy"
  printf "paper_pass_alignment_status=%s\n" "$paper_pass_alignment_status"
  printf "paper_pass_alignment_blockers=%s\n" "$paper_pass_alignment_blockers"
  printf "parallel_pass_contract_schema=%s\n" "$parallel_pass_contract_schema"
  printf "parallel_pass_contract_policy=%s\n" "$parallel_pass_contract_policy"
  printf "parallel_pass_contract_groups=%s\n" "$parallel_pass_contract_groups"
  printf "parallel_pass_contract_order_policy=%s\n" "$parallel_pass_contract_order_policy"
  printf "parallel_pass_contract_execution_order=%s\n" "$parallel_pass_contract_execution_order"
  printf "pass_contract_status_schema=%s\n" "$pass_contract_status_schema"
  printf "pass_contract_loop_policy=%s\n" "$pass_contract_loop_policy"
  printf "pass_contract_loop_status=%s\n" "$pass_contract_loop_status"
  printf "pass_contract_fallback_status=%s\n" "$pass_contract_fallback_status"
  printf "pass_contract_claim_status=%s\n" "$pass_contract_claim_status"
  printf "pass_contract_claim_blockers=%s\n" "$pass_contract_claim_blockers"
  printf "pass_contract_readiness_status=%s\n" "$pass_contract_readiness_status"
  printf "timeout_provenance_schema=%s\n" "$timeout_provenance_schema"
  printf "timeout_scope=%s\n" "$timeout_scope"
  printf "timeout_source=%s\n" "$timeout_source"
  printf "timeout_enforced_by=%s\n" "$timeout_enforced_by"
  printf "timeout_exit_code=%s\n" "$timeout_exit_code"
  printf "timeout_exit_code_means_timed_out=%s\n" "$timeout_exit_code_means_timed_out"
  printf "source_control_policy=%s\n" "$source_control_policy"
  printf "source_control_state=%s\n" "$source_control_state"
  printf "source_control_revision=%s\n" "$source_control_revision"
  printf "repeatability_policy=%s\n" "$repeatability_policy"
  printf "minimum_iterations_for_claim=%s\n" "$minimum_iterations_for_claim"
  printf "repeatability_status=%s\n" "$repeatability_status"
  printf "required_artifacts_complete=%s\n" "$required_artifacts_complete"
  printf "missing_required_artifacts=%s\n" "$missing_required_artifacts"
  printf "evidence_status_schema=lanius.measurement-evidence-status.v1\n"
  printf "local_performance_evidence_status=%s\n" "$local_performance_evidence_status"
  printf "local_performance_claim_status=%s\n" "$local_performance_claim_status"
  printf "local_performance_claim_blockers=%s\n" "$local_performance_claim_blockers"
  printf "local_readback_evidence_status=%s\n" "$local_readback_evidence_status"
  printf "local_vram_evidence_status=%s\n" "$local_vram_evidence_status"
  printf "local_pareas_evidence_status=%s\n" "$local_pareas_evidence_status"
  printf "scaling_claim_status=%s\n" "$scaling_claim_status"
  printf "scaling_claim_blockers=%s\n" "$scaling_claim_blockers"
  printf "production_readiness_evidence_complete=%s\n" "$production_readiness_evidence_complete"
  printf "production_readiness_blockers=%s\n" "$production_readiness_blockers"
  printf "evidence_freshness_schema=lanius.measurement-evidence-freshness.v1\n"
  printf "evidence_freshness_status=%s\n" "$evidence_freshness_status"
  printf "stale_artifacts=%s\n" "$stale_artifacts"
  printf "stale_artifact_checks=%s\n" "$stale_artifact_checks"
  printf "claim_readiness_schema=lanius.measurement-claim-readiness.v1\n"
  printf "claim_readiness_policy=complete-local-evidence-only\n"
  printf "claim_readiness_required_evidence_classes=%s\n" "$claim_readiness_required_evidence_classes"
  printf "claim_readiness_required_statuses=%s\n" "$claim_readiness_required_statuses"
  printf "claim_readiness_status=%s\n" "$claim_readiness_status"
  printf "claimable_measurement_claims=%s\n" "$claimable_measurement_claims"
  printf "claim_readiness_blockers=%s\n" "$claim_readiness_blockers"
  printf "claim_scope_policy=%s\n" "$claim_scope_policy"
  printf "claim_scope_key=%s\n" "$claim_scope_key"
  printf "source_seed=%s\n" "$seed"
  printf "iterations=%s\n" "$iterations"
  printf "timeout_ms=%s\n" "$timeout_ms"
  printf "timeout_seconds=%s\n" "$timeout_seconds"
  printf "readback_timeout_ms=%s\n" "$readback_timeout_ms"
  printf "vram_sample_interval_ms=%s\n" "$vram_sample_interval_ms"
  printf "lanius_exit_status=%s\n" "$lanius_exit_status"
  printf "timed_out=%s\n" "$timed_out"
  printf "lanius_wall_elapsed_ms=%s\n" "$lanius_wall_elapsed_ms"
  printf "best_ms=%s\n" "$best_ms"
  printf "throughput_lines_per_second=%s\n" "$throughput_lines_per_second"
  printf "readback_span_count=%s\n" "$readback_span_count"
  printf "readback_total_ms=%s\n" "$readback_total_ms"
  printf "readback_max_span_ms=%s\n" "$readback_max_span_ms"
  printf "max_vram_bytes=%s\n" "$max_vram_bytes"
  printf "nvidia_smi_exit_status=%s\n" "$nvidia_smi_exit_status"
  printf "resource_user_seconds=%s\n" "$resource_user_seconds"
  printf "resource_system_seconds=%s\n" "$resource_system_seconds"
  printf "resource_max_rss_kb=%s\n" "$resource_max_rss_kb"
  printf "resource_usage_status=%s\n" "$resource_usage_status"
  printf "source_replay_line_count=%s\n" "$source_replay_line_count"
  printf "source_sha256=%s\n" "$source_sha256"
  printf "bench_binary_sha256=%s\n" "$bench_binary_sha256"
  printf "hardware_identity_sha256=%s\n" "$hardware_identity_sha256"
  printf "command_environment_sha256=%s\n" "$command_environment_sha256"
  printf "machine_responsive_after=%s\n" "$machine_responsive_after"
  printf "responsiveness_probe_status=%s\n" "$responsiveness_probe_status"
  printf "pareas_exit_status=%s\n" "$pareas_exit_status"
  printf "pareas_timed_out=%s\n" "$pareas_timed_out"
  printf "pareas_wall_elapsed_ms=%s\n" "$pareas_wall_elapsed_ms"
  printf "pareas_source_sha256=%s\n" "$pareas_source_sha256"
  printf "pareas_binary_sha256=%s\n" "$pareas_binary_sha256"
  printf "lanius_pareas_wall_ratio=%s\n" "$lanius_pareas_wall_ratio"
  printf "lanius_stdout_path=%s\n" "$lanius_stdout_path"
  printf "perfetto_trace_path=%s\n" "$perfetto_trace_path"
  printf "readback_summary_path=%s\n" "$readback_summary_path"
  printf "vram_output_path=%s\n" "$vram_output_path"
  printf "source_replay_path=%s\n" "$source_replay_path"
  printf "source_sha256_path=%s\n" "$source_sha256_path"
  printf "bench_binary_sha256_path=%s\n" "$bench_sha256_path"
  printf "hardware_output_path=%s\n" "$hardware_output_path"
  printf "command_env_path=%s\n" "$command_env_path"
  printf "command_status_path=%s\n" "$command_status_path"
  printf "responsiveness_probe_path=%s\n" "$responsiveness_probe_path"
  printf "resource_usage_path=%s\n" "$resource_usage_path"
  printf "pareas_source_path=%s\n" "$pareas_source_path"
  printf "pareas_source_sha256_path=%s\n" "$pareas_source_sha256_path"
  printf "pareas_binary_sha256_path=%s\n" "$pareas_binary_sha256_path"
  printf "pareas_output_path=%s\n" "$pareas_output_path"
  printf "pareas_stdout_path=%s\n" "$pareas_stdout_path"
} >"$out"' \
    sh \
    "$measurement_summary_path" \
    "$line_count" \
    "$perf_source" \
    "$perf_phase" \
    x86_64-elf \
    "$perf_seed" \
    "$perf_iters" \
    "$perf_timeout_seconds" \
    "$perf_readback_timeout_ms" \
    "$perf_vram_sample_interval_ms" \
    "$stdout_path" \
    "$trace_path" \
    "$readback_summary_path" \
    "$vram_path" \
    "$source_replay_path" \
    "$source_sha256_path" \
    "$bench_sha256_path" \
    "$hardware_path" \
    "$command_env_path" \
    "$command_status_path" \
    "$responsiveness_path" \
    "$resource_usage_path" \
    "$pareas_source_path" \
    "$pareas_source_sha256_path" \
    "$pareas_binary_sha256_path" \
    "$pareas_output_path" \
    "$pareas_stdout_path" \
    "$perf_responsiveness_timeout_ms" \
    "$perf_responsiveness_timeout_seconds" \
    "$perf_timeout_ms" \
    "$(measurement_timing_policy)" \
    "$(measurement_cold_start_policy)" \
    "$(measurement_compile_latency_claim_source)" \
    "$(measurement_runtime_validation_policy)" \
    "$(measurement_timeout_provenance_schema)" \
    "$(measurement_timeout_scope)" \
    "$(measurement_timeout_source)" \
    "$(measurement_timeout_enforced_by)" \
    "$(measurement_timeout_exit_code)" \
    "$(measurement_timeout_exit_code_means_timed_out)" \
    "$(measurement_parallel_pass_contract_schema)" \
    "$(measurement_parallel_pass_contract_policy)" \
    "$(measurement_parallel_pass_contract_groups)" \
    "$(measurement_parallel_pass_contract_order_policy)" \
    "$(measurement_parallel_pass_contract_execution_order)" \
    "$(measurement_claim_provenance_schema)" \
    "$(measurement_baseline_separation_schema)" \
    "$(measurement_paper_baseline_policy)" \
    "$(measurement_paper_baseline_numbers_status)" \
    "$(measurement_local_evidence_status_policy)" \
    "$(measurement_local_performance_claim_policy)" \
    "$(measurement_local_performance_claim_source)" \
    "$(measurement_local_performance_claim_status)" \
    "$(measurement_local_performance_claim_blockers)" \
    "$(measurement_local_vram_claim_source)" \
    "$(measurement_local_pareas_claim_source)" \
    "$(measurement_scaling_claim_policy)" \
    "$(measurement_scaling_claim_source)" \
    "$(measurement_scaling_claim_status)" \
    "$(measurement_scaling_claim_blockers)" \
    "$(measurement_paper_pass_order_schema)" \
    "$(measurement_paper_pass_order_source)" \
    "$(measurement_paper_pass_order)" \
    "$(measurement_paper_pass_alignment_policy)" \
    "$(measurement_paper_pass_alignment_status)" \
    "$(measurement_paper_pass_alignment_blockers)" \
    "$(measurement_pass_contract_status_schema)" \
    "$(measurement_pass_contract_loop_policy)" \
    "$(measurement_pass_contract_loop_status)" \
    "$(measurement_pass_contract_fallback_status)" \
    "$(measurement_pass_contract_claim_status)" \
    "$(measurement_pass_contract_claim_blockers)"
}

emit_perf_measurement_plan() {
  local nvidia_smi
  local pareas_bin

  prepare_perf_measurement_plan_values || {
    echo "# measurement-plan failed: $env_errors issue(s)" >&2
    exit 1
  }

  nvidia_smi="$(find_nvidia_smi || true)"
  pareas_bin="$(find_pareas_bin || true)"
  if [[ -z "$nvidia_smi" && -n "${NVIDIA_SMI:-}" ]]; then
    env_error "NVIDIA_SMI is set to '$NVIDIA_SMI', but that path is not executable"
  elif [[ -z "$nvidia_smi" ]] && is_truthy "${LANIUS_REQUIRE_NVIDIA_SMI:-}"; then
    env_error "LANIUS_REQUIRE_NVIDIA_SMI=1 but nvidia-smi was not found; set NVIDIA_SMI or put nvidia-smi on PATH"
  fi
  if [[ -z "$pareas_bin" && -n "${PAREAS_BIN:-}" ]]; then
    env_error "PAREAS_BIN is set to '$PAREAS_BIN', but that path is not executable"
  elif [[ -z "$pareas_bin" ]] && is_truthy "${LANIUS_REQUIRE_PAREAS:-}"; then
    env_error "LANIUS_REQUIRE_PAREAS=1 but no Pareas binary was found; set PAREAS_BIN or build ~/code/pareas"
  fi
  if [[ "$env_errors" -gt 0 ]]; then
    echo "# measurement-plan failed: $env_errors issue(s)" >&2
    exit 1
  fi

  cat <<PLAN
# Lanius no-run performance/VRAM measurement plan
measurement_plan_schema: lanius.measurement-plan.v1
mode: no-run
measurement_evidence_policy: local-artifacts-only
paper_numbers_accepted: false
comparison_baseline_policy: local-pareas-artifacts-only
freshness_policy: hash-and-checkpoint-field-match
measurement_timing_policy: $(measurement_timing_policy)
cold_start_policy: $(measurement_cold_start_policy)
compile_latency_claim_source: $(measurement_compile_latency_claim_source)
runtime_validation_policy: $(measurement_runtime_validation_policy)
claim_provenance_schema: $(measurement_claim_provenance_schema)
baseline_separation_schema: $(measurement_baseline_separation_schema)
required_claim_provenance_fields: $(measurement_required_claim_provenance_fields)
paper_baseline_policy: $(measurement_paper_baseline_policy)
paper_baseline_numbers_status: $(measurement_paper_baseline_numbers_status)
local_evidence_status_policy: $(measurement_local_evidence_status_policy)
local_performance_claim_policy: $(measurement_local_performance_claim_policy)
local_performance_claim_source: $(measurement_local_performance_claim_source)
local_performance_claim_status: $(measurement_local_performance_claim_status)
local_performance_claim_blockers: $(measurement_local_performance_claim_blockers)
local_vram_claim_source: $(measurement_local_vram_claim_source)
local_pareas_claim_source: $(measurement_local_pareas_claim_source)
scaling_claim_policy: $(measurement_scaling_claim_policy)
scaling_claim_source: $(measurement_scaling_claim_source)
scaling_claim_status: $(measurement_scaling_claim_status)
scaling_claim_blockers: $(measurement_scaling_claim_blockers)
paper_pass_order_schema: $(measurement_paper_pass_order_schema)
paper_pass_order_source: $(measurement_paper_pass_order_source)
paper_pass_order: $(measurement_paper_pass_order)
paper_pass_alignment_policy: $(measurement_paper_pass_alignment_policy)
paper_pass_alignment_status: $(measurement_paper_pass_alignment_status)
paper_pass_alignment_blockers: $(measurement_paper_pass_alignment_blockers)
parallel_pass_contract_schema: $(measurement_parallel_pass_contract_schema)
parallel_pass_contract_policy: $(measurement_parallel_pass_contract_policy)
parallel_pass_contract_groups: $(measurement_parallel_pass_contract_groups)
parallel_pass_contract_order_policy: $(measurement_parallel_pass_contract_order_policy)
parallel_pass_contract_execution_order: $(measurement_parallel_pass_contract_execution_order)
required_parallel_pass_contract_fields: $(measurement_required_parallel_pass_contract_fields)
pass_contract_status_schema: $(measurement_pass_contract_status_schema)
required_pass_contract_status_fields: $(measurement_required_pass_contract_status_fields)
pass_contract_loop_policy: $(measurement_pass_contract_loop_policy)
pass_contract_loop_status: $(measurement_pass_contract_loop_status)
pass_contract_fallback_status: $(measurement_pass_contract_fallback_status)
pass_contract_claim_status: $(measurement_pass_contract_claim_status)
pass_contract_claim_blockers: $(measurement_pass_contract_claim_blockers)
pass_contract_readiness_status: $(measurement_pass_contract_readiness_status)
timeout_provenance_schema: $(measurement_timeout_provenance_schema)
required_timeout_provenance_fields: $(measurement_required_timeout_provenance_fields)
timeout_scope: $(measurement_timeout_scope)
timeout_source: $(measurement_timeout_source)
timeout_enforced_by: $(measurement_timeout_enforced_by)
timeout_exit_code: $(measurement_timeout_exit_code)
timeout_exit_code_means_timed_out: $(measurement_timeout_exit_code_means_timed_out)
source_control_policy: $(measurement_source_control_policy)
repeatability_policy: $(measurement_repeatability_policy)
minimum_iterations_for_claim: $(measurement_minimum_iterations_for_claim)
primary_line_count: $perf_lines
checkpoints: $(join_by_comma "${perf_checkpoint_lines[@]}")
checkpoint_execution_order: $(join_by_comma "${perf_checkpoint_lines[@]}")
source_seed: $perf_seed
iterations: $perf_iters
timeout_ms: $perf_timeout_ms
timeout_seconds: $perf_timeout_seconds
readback_timeout_ms: $perf_readback_timeout_ms
vram_sample_interval_ms: $perf_vram_sample_interval_ms
responsiveness_probe_timeout_ms: $perf_responsiveness_timeout_ms
responsiveness_probe_timeout_seconds: $perf_responsiveness_timeout_seconds
source: $perf_source
phase: $perf_phase
target: x86_64-elf
required_checkpoint_artifacts: $(measurement_required_artifacts)
optional_comparison_artifacts: $(measurement_optional_comparison_artifacts)
artifact_manifest_schema: $(measurement_artifact_manifest_schema)
required_artifact_manifest_fields: $(measurement_required_artifact_manifest_fields)
readback_summary_schema: $(measurement_readback_summary_schema)
required_readback_summary_fields: $(measurement_required_readback_summary_fields)
vram_csv_schema: $(measurement_vram_csv_schema)
required_vram_csv_columns: $(measurement_required_vram_csv_columns)
hardware_identity_schema: $(measurement_hardware_identity_schema)
required_hardware_identity_fields: $(measurement_required_hardware_identity_fields)
command_environment_schema: $(measurement_command_environment_schema)
required_command_environment_fields: $(measurement_required_command_environment_fields)
responsiveness_probe_schema: $(measurement_responsiveness_probe_schema)
required_responsiveness_probe_fields: $(measurement_required_responsiveness_probe_fields)
command_status_schema: $(measurement_command_status_schema)
evidence_status_schema: $(measurement_evidence_status_schema)
required_evidence_status_fields: $(measurement_required_evidence_status_fields)
evidence_freshness_schema: $(measurement_evidence_freshness_schema)
required_evidence_freshness_fields: $(measurement_required_evidence_freshness_fields)
claim_readiness_schema: $(measurement_claim_readiness_schema)
claim_readiness_policy: $(measurement_claim_readiness_policy)
claim_readiness_required_evidence_classes: $(measurement_claim_readiness_required_evidence_classes)
claim_readiness_required_statuses: $(measurement_claim_readiness_required_statuses)
claim_scope_policy: $(measurement_claim_scope_policy)
repeatability_policy: $(measurement_repeatability_policy)
minimum_iterations_for_claim: $(measurement_minimum_iterations_for_claim)
required_claim_readiness_fields: $(measurement_required_claim_readiness_fields)
required_status_fields: $(measurement_required_status_fields)
optional_status_fields: $(measurement_optional_status_fields)
measurement_summary_schema: lanius.measurement-summary.v1
required_summary_fields: $(measurement_required_summary_fields)
lanius_stdout_path: $perf_output_path
lanius_perfetto_trace_path: $perf_trace_path
readback_summary_path: $perf_readback_summary_path
vram_output_path: $perf_vram_output_path
source_replay_output_path: $perf_source_replay_output_path
source_sha256_output_path: $perf_source_sha256_output_path
bench_sha256_output_path: $perf_bench_sha256_output_path
hardware_output_path: $perf_hardware_output_path
command_env_output_path: $perf_command_env_output_path
command_status_output_path: $perf_command_status_output_path
responsiveness_probe_output_path: $perf_responsiveness_output_path
resource_usage_output_path: $perf_resource_usage_output_path
measurement_summary_output_path: $perf_measurement_summary_output_path
pareas_source_path: $perf_pareas_source_path
pareas_source_sha256_output_path: $perf_pareas_source_sha256_output_path
pareas_binary_sha256_output_path: $perf_pareas_binary_sha256_output_path
pareas_output_path: $perf_pareas_output_path
pareas_stdout_path: $perf_pareas_stdout_path
large_case_guardrail: LANIUS_PERF_CHECKPOINT_LINES checkpoint > 20000, LANIUS_PERF_LINES > 20000, or LANIUS_PERF_ITERS > 3 requires LANIUS_ALLOW_LARGE_GENERATED_TESTS=1
PLAN

  print_report_command \
    lanius_build_command \
    cargo \
    build \
    --release \
    -p \
    laniusc \
    --bin \
    gpu_compile_bench

  local checkpoint
  for checkpoint in "${perf_checkpoint_lines[@]}"; do
    emit_perf_checkpoint_plan "$checkpoint" "$nvidia_smi" "$pareas_bin"
  done

  cat <<'PLAN'
notes:
- This report is a scaffold only; it does not compile, run Lanius, run Pareas, or start nvidia-smi.
- Run the lanius_build_command separately before the measured lanius_command so cargo build time is not included.
- Run the hardware_identity_command before each measured checkpoint and keep its output with the benchmark artifacts.
- Run the command_environment_command before each measured checkpoint so the timeout, readback, VRAM, GPU timing, Slang, CUDA, and Pareas environment is captured.
- Run the source_replay_command, source_sha256_command, and bench_sha256_command for each checkpoint so a failed or published measurement has a replayable generated input, source content hash, and exact benchmark binary hash.
- Run checkpoints in ascending order: 5k first, then 10k, then 20k. Stop at the first readback timeout, excessive VRAM growth, or machine responsiveness issue.
- Start the matching nvidia-smi sampling command immediately before each benchmark command and stop it after that command exits; the wrapped command includes a timeout fallback so the sampler cannot run indefinitely.
- Prefer the wrapped Lanius/Pareas/nvidia-smi commands plus the responsiveness_probe_command when collecting evidence because they write exit status, timeout, responsiveness, and Lanius resource-usage artifact status to the status path.
- Inspect and save the matching readback trace summary after each Lanius run; host.readback spans are the expected source for readback cost evidence.
- Write the measurement_summary_command output after the benchmark, resource usage, readback, VRAM, source hash, benchmark binary hash, hardware, environment, and status artifacts exist; it is the per-checkpoint rollup expected by production-readiness evidence.
- Treat source_control_state in the summary as part of the claim boundary; dirty-worktree measurements are exact local checkpoint evidence, not clean release evidence.
- The summary's evidence-status row keeps production_readiness_evidence_complete=false until local Lanius performance, readback, VRAM, machine-responsiveness, and Pareas comparison evidence are complete; missing optional tools must appear as not-run or missing blockers.
- Paper baseline values are reference-only metadata; the summary can only make checkpoint-local claims from fresh local Lanius, VRAM, readback, resource-usage, source/hash, hardware/env, and local Pareas artifacts.
- Pareas comparison requires a Pareas-compatible generated source at pareas_source_path plus pareas_source_sha256_output_path and a local Pareas compiler hash at pareas_binary_sha256_output_path; this scaffold records the intended commands but does not generate or run them.
PLAN
}

write_perf_measurement_plan() {
  if [[ -n "$measurement_plan_path" ]]; then
    mkdir -p "$(dirname "$measurement_plan_path")"
    emit_perf_measurement_plan >"$measurement_plan_path"
    echo "# wrote no-run measurement plan to $measurement_plan_path"
  else
    emit_perf_measurement_plan
  fi
}

emit_measurement_check_env_notes() {
  env_note "measurement_plan_schema=lanius.measurement-plan.v1"
  env_note "measurement_evidence_policy=local-artifacts-only"
  env_note "measurement_paper_numbers_accepted=false"
  env_note "measurement_comparison_baseline_policy=local-pareas-artifacts-only"
  env_note "measurement_freshness_policy=hash-and-checkpoint-field-match"
  env_note "measurement_timing_policy=$(measurement_timing_policy)"
  env_note "measurement_cold_start_policy=$(measurement_cold_start_policy)"
  env_note "measurement_compile_latency_claim_source=$(measurement_compile_latency_claim_source)"
  env_note "measurement_runtime_validation_policy=$(measurement_runtime_validation_policy)"
  env_note "measurement_claim_provenance_schema=$(measurement_claim_provenance_schema)"
  env_note "measurement_baseline_separation_schema=$(measurement_baseline_separation_schema)"
  env_note "measurement_required_claim_provenance_fields=$(measurement_required_claim_provenance_fields)"
  env_note "measurement_paper_baseline_policy=$(measurement_paper_baseline_policy)"
  env_note "measurement_paper_baseline_numbers_status=$(measurement_paper_baseline_numbers_status)"
  env_note "measurement_local_evidence_status_policy=$(measurement_local_evidence_status_policy)"
  env_note "measurement_local_performance_claim_policy=$(measurement_local_performance_claim_policy)"
  env_note "measurement_local_performance_claim_source=$(measurement_local_performance_claim_source)"
  env_note "measurement_local_performance_claim_status=$(measurement_local_performance_claim_status)"
  env_note "measurement_local_performance_claim_blockers=$(measurement_local_performance_claim_blockers)"
  env_note "measurement_local_vram_claim_source=$(measurement_local_vram_claim_source)"
  env_note "measurement_local_pareas_claim_source=$(measurement_local_pareas_claim_source)"
  env_note "measurement_scaling_claim_policy=$(measurement_scaling_claim_policy)"
  env_note "measurement_scaling_claim_source=$(measurement_scaling_claim_source)"
  env_note "measurement_scaling_claim_status=$(measurement_scaling_claim_status)"
  env_note "measurement_scaling_claim_blockers=$(measurement_scaling_claim_blockers)"
  env_note "measurement_paper_pass_order_schema=$(measurement_paper_pass_order_schema)"
  env_note "measurement_paper_pass_order_source=$(measurement_paper_pass_order_source)"
  env_note "measurement_paper_pass_order=$(measurement_paper_pass_order)"
  env_note "measurement_paper_pass_alignment_policy=$(measurement_paper_pass_alignment_policy)"
  env_note "measurement_paper_pass_alignment_status=$(measurement_paper_pass_alignment_status)"
  env_note "measurement_paper_pass_alignment_blockers=$(measurement_paper_pass_alignment_blockers)"
  env_note "measurement_parallel_pass_contract_schema=$(measurement_parallel_pass_contract_schema)"
  env_note "measurement_parallel_pass_contract_policy=$(measurement_parallel_pass_contract_policy)"
  env_note "measurement_parallel_pass_contract_groups=$(measurement_parallel_pass_contract_groups)"
  env_note "measurement_parallel_pass_contract_order_policy=$(measurement_parallel_pass_contract_order_policy)"
  env_note "measurement_parallel_pass_contract_execution_order=$(measurement_parallel_pass_contract_execution_order)"
  env_note "measurement_required_parallel_pass_contract_fields=$(measurement_required_parallel_pass_contract_fields)"
  env_note "measurement_pass_contract_status_schema=$(measurement_pass_contract_status_schema)"
  env_note "measurement_required_pass_contract_status_fields=$(measurement_required_pass_contract_status_fields)"
  env_note "measurement_pass_contract_loop_policy=$(measurement_pass_contract_loop_policy)"
  env_note "measurement_pass_contract_loop_status=$(measurement_pass_contract_loop_status)"
  env_note "measurement_pass_contract_fallback_status=$(measurement_pass_contract_fallback_status)"
  env_note "measurement_pass_contract_claim_status=$(measurement_pass_contract_claim_status)"
  env_note "measurement_pass_contract_claim_blockers=$(measurement_pass_contract_claim_blockers)"
  env_note "measurement_pass_contract_readiness_status=$(measurement_pass_contract_readiness_status)"
  env_note "measurement_timeout_provenance_schema=$(measurement_timeout_provenance_schema)"
  env_note "measurement_required_timeout_provenance_fields=$(measurement_required_timeout_provenance_fields)"
  env_note "measurement_timeout_scope=$(measurement_timeout_scope)"
  env_note "measurement_timeout_source=$(measurement_timeout_source)"
  env_note "measurement_timeout_enforced_by=$(measurement_timeout_enforced_by)"
  env_note "measurement_timeout_exit_code=$(measurement_timeout_exit_code)"
  env_note "measurement_timeout_exit_code_means_timed_out=$(measurement_timeout_exit_code_means_timed_out)"
  env_note "measurement_source_control_policy=$(measurement_source_control_policy)"
  env_note "measurement_required_artifacts=$(measurement_required_artifacts)"
  env_note "measurement_optional_comparison_artifacts=$(measurement_optional_comparison_artifacts)"
  env_note "measurement_artifact_manifest_schema=$(measurement_artifact_manifest_schema)"
  env_note "measurement_required_artifact_manifest_fields=$(measurement_required_artifact_manifest_fields)"
  env_note "measurement_readback_summary_schema=$(measurement_readback_summary_schema)"
  env_note "measurement_required_readback_summary_fields=$(measurement_required_readback_summary_fields)"
  env_note "measurement_vram_csv_schema=$(measurement_vram_csv_schema)"
  env_note "measurement_required_vram_csv_columns=$(measurement_required_vram_csv_columns)"
  env_note "measurement_hardware_identity_schema=$(measurement_hardware_identity_schema)"
  env_note "measurement_required_hardware_identity_fields=$(measurement_required_hardware_identity_fields)"
  env_note "measurement_command_environment_schema=$(measurement_command_environment_schema)"
  env_note "measurement_required_command_environment_fields=$(measurement_required_command_environment_fields)"
  env_note "measurement_responsiveness_probe_schema=$(measurement_responsiveness_probe_schema)"
  env_note "measurement_required_responsiveness_probe_fields=$(measurement_required_responsiveness_probe_fields)"
  env_note "measurement_command_status_schema=$(measurement_command_status_schema)"
  env_note "measurement_evidence_status_schema=$(measurement_evidence_status_schema)"
  env_note "measurement_required_evidence_status_fields=$(measurement_required_evidence_status_fields)"
  env_note "measurement_evidence_freshness_schema=$(measurement_evidence_freshness_schema)"
  env_note "measurement_required_evidence_freshness_fields=$(measurement_required_evidence_freshness_fields)"
  env_note "measurement_claim_readiness_schema=$(measurement_claim_readiness_schema)"
  env_note "measurement_claim_readiness_policy=$(measurement_claim_readiness_policy)"
  env_note "measurement_claim_readiness_required_evidence_classes=$(measurement_claim_readiness_required_evidence_classes)"
  env_note "measurement_claim_readiness_required_statuses=$(measurement_claim_readiness_required_statuses)"
  env_note "measurement_claim_scope_policy=$(measurement_claim_scope_policy)"
  env_note "measurement_repeatability_policy=$(measurement_repeatability_policy)"
  env_note "measurement_minimum_iterations_for_claim=$(measurement_minimum_iterations_for_claim)"
  env_note "measurement_required_claim_readiness_fields=$(measurement_required_claim_readiness_fields)"
  env_note "measurement_required_status_fields=$(measurement_required_status_fields)"
  env_note "measurement_optional_status_fields=$(measurement_optional_status_fields)"
  env_note "measurement_summary_schema=lanius.measurement-summary.v1"
  env_note "measurement_required_summary_fields=$(measurement_required_summary_fields)"

  local checkpoint
  for checkpoint in "${perf_checkpoint_lines[@]}"; do
    env_note "measurement_checkpoint_${checkpoint}l.line_count=$checkpoint"
    env_note "measurement_checkpoint_${checkpoint}l.source=$perf_source"
    env_note "measurement_checkpoint_${checkpoint}l.phase=$perf_phase"
    env_note "measurement_checkpoint_${checkpoint}l.target=x86_64-elf"
    env_note "measurement_checkpoint_${checkpoint}l.seed=$perf_seed"
    env_note "measurement_checkpoint_${checkpoint}l.iterations=$perf_iters"
    env_note "measurement_checkpoint_${checkpoint}l.timing_policy=$(measurement_timing_policy)"
    env_note "measurement_checkpoint_${checkpoint}l.cold_start_policy=$(measurement_cold_start_policy)"
    env_note "measurement_checkpoint_${checkpoint}l.compile_latency_claim_source=$(measurement_compile_latency_claim_source)"
    env_note "measurement_checkpoint_${checkpoint}l.runtime_validation_policy=$(measurement_runtime_validation_policy)"
    env_note "measurement_checkpoint_${checkpoint}l.claim_provenance_schema=$(measurement_claim_provenance_schema)"
    env_note "measurement_checkpoint_${checkpoint}l.baseline_separation_schema=$(measurement_baseline_separation_schema)"
    env_note "measurement_checkpoint_${checkpoint}l.required_claim_provenance_fields=$(measurement_required_claim_provenance_fields)"
    env_note "measurement_checkpoint_${checkpoint}l.paper_baseline_policy=$(measurement_paper_baseline_policy)"
    env_note "measurement_checkpoint_${checkpoint}l.paper_baseline_numbers_status=$(measurement_paper_baseline_numbers_status)"
    env_note "measurement_checkpoint_${checkpoint}l.local_evidence_status_policy=$(measurement_local_evidence_status_policy)"
    env_note "measurement_checkpoint_${checkpoint}l.local_performance_claim_policy=$(measurement_local_performance_claim_policy)"
    env_note "measurement_checkpoint_${checkpoint}l.local_performance_claim_source=$(measurement_local_performance_claim_source)"
    env_note "measurement_checkpoint_${checkpoint}l.local_performance_claim_status=$(measurement_local_performance_claim_status)"
    env_note "measurement_checkpoint_${checkpoint}l.local_performance_claim_blockers=$(measurement_local_performance_claim_blockers)"
    env_note "measurement_checkpoint_${checkpoint}l.local_vram_claim_source=$(measurement_local_vram_claim_source)"
    env_note "measurement_checkpoint_${checkpoint}l.local_pareas_claim_source=$(measurement_local_pareas_claim_source)"
    env_note "measurement_checkpoint_${checkpoint}l.scaling_claim_policy=$(measurement_scaling_claim_policy)"
    env_note "measurement_checkpoint_${checkpoint}l.scaling_claim_source=$(measurement_scaling_claim_source)"
    env_note "measurement_checkpoint_${checkpoint}l.scaling_claim_status=$(measurement_scaling_claim_status)"
    env_note "measurement_checkpoint_${checkpoint}l.scaling_claim_blockers=$(measurement_scaling_claim_blockers)"
    env_note "measurement_checkpoint_${checkpoint}l.paper_pass_order_schema=$(measurement_paper_pass_order_schema)"
    env_note "measurement_checkpoint_${checkpoint}l.paper_pass_order_source=$(measurement_paper_pass_order_source)"
    env_note "measurement_checkpoint_${checkpoint}l.paper_pass_order=$(measurement_paper_pass_order)"
    env_note "measurement_checkpoint_${checkpoint}l.paper_pass_alignment_policy=$(measurement_paper_pass_alignment_policy)"
    env_note "measurement_checkpoint_${checkpoint}l.paper_pass_alignment_status=$(measurement_paper_pass_alignment_status)"
    env_note "measurement_checkpoint_${checkpoint}l.paper_pass_alignment_blockers=$(measurement_paper_pass_alignment_blockers)"
    env_note "measurement_checkpoint_${checkpoint}l.parallel_pass_contract_schema=$(measurement_parallel_pass_contract_schema)"
    env_note "measurement_checkpoint_${checkpoint}l.parallel_pass_contract_policy=$(measurement_parallel_pass_contract_policy)"
    env_note "measurement_checkpoint_${checkpoint}l.parallel_pass_contract_groups=$(measurement_parallel_pass_contract_groups)"
    env_note "measurement_checkpoint_${checkpoint}l.parallel_pass_contract_order_policy=$(measurement_parallel_pass_contract_order_policy)"
    env_note "measurement_checkpoint_${checkpoint}l.parallel_pass_contract_execution_order=$(measurement_parallel_pass_contract_execution_order)"
    env_note "measurement_checkpoint_${checkpoint}l.required_parallel_pass_contract_fields=$(measurement_required_parallel_pass_contract_fields)"
    env_note "measurement_checkpoint_${checkpoint}l.pass_contract_status_schema=$(measurement_pass_contract_status_schema)"
    env_note "measurement_checkpoint_${checkpoint}l.required_pass_contract_status_fields=$(measurement_required_pass_contract_status_fields)"
    env_note "measurement_checkpoint_${checkpoint}l.pass_contract_loop_policy=$(measurement_pass_contract_loop_policy)"
    env_note "measurement_checkpoint_${checkpoint}l.pass_contract_loop_status=$(measurement_pass_contract_loop_status)"
    env_note "measurement_checkpoint_${checkpoint}l.pass_contract_fallback_status=$(measurement_pass_contract_fallback_status)"
    env_note "measurement_checkpoint_${checkpoint}l.pass_contract_claim_status=$(measurement_pass_contract_claim_status)"
    env_note "measurement_checkpoint_${checkpoint}l.pass_contract_claim_blockers=$(measurement_pass_contract_claim_blockers)"
    env_note "measurement_checkpoint_${checkpoint}l.pass_contract_readiness_status=$(measurement_pass_contract_readiness_status)"
    env_note "measurement_checkpoint_${checkpoint}l.timeout_provenance_schema=$(measurement_timeout_provenance_schema)"
    env_note "measurement_checkpoint_${checkpoint}l.required_timeout_provenance_fields=$(measurement_required_timeout_provenance_fields)"
    env_note "measurement_checkpoint_${checkpoint}l.timeout_scope=$(measurement_timeout_scope)"
    env_note "measurement_checkpoint_${checkpoint}l.timeout_source=$(measurement_timeout_source)"
    env_note "measurement_checkpoint_${checkpoint}l.timeout_enforced_by=$(measurement_timeout_enforced_by)"
    env_note "measurement_checkpoint_${checkpoint}l.timeout_exit_code=$(measurement_timeout_exit_code)"
    env_note "measurement_checkpoint_${checkpoint}l.timeout_exit_code_means_timed_out=$(measurement_timeout_exit_code_means_timed_out)"
    env_note "measurement_checkpoint_${checkpoint}l.repeatability_policy=$(measurement_repeatability_policy)"
    env_note "measurement_checkpoint_${checkpoint}l.minimum_iterations_for_claim=$(measurement_minimum_iterations_for_claim)"
    env_note "measurement_checkpoint_${checkpoint}l.timeout_ms=$perf_timeout_ms"
    env_note "measurement_checkpoint_${checkpoint}l.readback_timeout_ms=$perf_readback_timeout_ms"
    env_note "measurement_checkpoint_${checkpoint}l.vram_sample_interval_ms=$perf_vram_sample_interval_ms"
    env_note "measurement_checkpoint_${checkpoint}l.responsiveness_probe_timeout_ms=$perf_responsiveness_timeout_ms"
    env_note "measurement_checkpoint_${checkpoint}l.required_artifacts=$(measurement_required_artifacts)"
    env_note "measurement_checkpoint_${checkpoint}l.optional_comparison_artifacts=$(measurement_optional_comparison_artifacts)"
    env_note "measurement_checkpoint_${checkpoint}l.artifact_manifest_schema=$(measurement_artifact_manifest_schema)"
    env_note "measurement_checkpoint_${checkpoint}l.required_artifact_manifest_fields=$(measurement_required_artifact_manifest_fields)"
    env_note "measurement_checkpoint_${checkpoint}l.readback_summary_schema=$(measurement_readback_summary_schema)"
    env_note "measurement_checkpoint_${checkpoint}l.required_readback_summary_fields=$(measurement_required_readback_summary_fields)"
    env_note "measurement_checkpoint_${checkpoint}l.vram_csv_schema=$(measurement_vram_csv_schema)"
    env_note "measurement_checkpoint_${checkpoint}l.required_vram_csv_columns=$(measurement_required_vram_csv_columns)"
    env_note "measurement_checkpoint_${checkpoint}l.hardware_identity_schema=$(measurement_hardware_identity_schema)"
    env_note "measurement_checkpoint_${checkpoint}l.required_hardware_identity_fields=$(measurement_required_hardware_identity_fields)"
    env_note "measurement_checkpoint_${checkpoint}l.command_environment_schema=$(measurement_command_environment_schema)"
    env_note "measurement_checkpoint_${checkpoint}l.required_command_environment_fields=$(measurement_required_command_environment_fields)"
    env_note "measurement_checkpoint_${checkpoint}l.responsiveness_probe_schema=$(measurement_responsiveness_probe_schema)"
    env_note "measurement_checkpoint_${checkpoint}l.required_responsiveness_probe_fields=$(measurement_required_responsiveness_probe_fields)"
    env_note "measurement_checkpoint_${checkpoint}l.command_status_schema=$(measurement_command_status_schema)"
    env_note "measurement_checkpoint_${checkpoint}l.evidence_status_schema=$(measurement_evidence_status_schema)"
    env_note "measurement_checkpoint_${checkpoint}l.required_evidence_status_fields=$(measurement_required_evidence_status_fields)"
    env_note "measurement_checkpoint_${checkpoint}l.evidence_freshness_schema=$(measurement_evidence_freshness_schema)"
    env_note "measurement_checkpoint_${checkpoint}l.required_evidence_freshness_fields=$(measurement_required_evidence_freshness_fields)"
    env_note "measurement_checkpoint_${checkpoint}l.claim_readiness_schema=$(measurement_claim_readiness_schema)"
    env_note "measurement_checkpoint_${checkpoint}l.claim_readiness_policy=$(measurement_claim_readiness_policy)"
    env_note "measurement_checkpoint_${checkpoint}l.claim_readiness_required_evidence_classes=$(measurement_claim_readiness_required_evidence_classes)"
    env_note "measurement_checkpoint_${checkpoint}l.claim_readiness_required_statuses=$(measurement_claim_readiness_required_statuses)"
    env_note "measurement_checkpoint_${checkpoint}l.claim_scope_policy=$(measurement_claim_scope_policy)"
    env_note "measurement_checkpoint_${checkpoint}l.source_control_policy=$(measurement_source_control_policy)"
    env_note "measurement_checkpoint_${checkpoint}l.required_claim_readiness_fields=$(measurement_required_claim_readiness_fields)"
    env_note "measurement_checkpoint_${checkpoint}l.required_status_fields=$(measurement_required_status_fields)"
    env_note "measurement_checkpoint_${checkpoint}l.optional_status_fields=$(measurement_optional_status_fields)"
    env_note "measurement_checkpoint_${checkpoint}l.required_summary_fields=$(measurement_required_summary_fields)"
    env_note "measurement_checkpoint_${checkpoint}l.lanius_stdout_path=$(measurement_stdout_path_for_line "$checkpoint")"
    env_note "measurement_checkpoint_${checkpoint}l.perfetto_trace_path=$(measurement_trace_path_for_line "$checkpoint")"
    env_note "measurement_checkpoint_${checkpoint}l.readback_summary_path=$(measurement_readback_summary_path_for_line "$checkpoint")"
    env_note "measurement_checkpoint_${checkpoint}l.vram_output_path=$(measurement_vram_path_for_line "$checkpoint")"
    env_note "measurement_checkpoint_${checkpoint}l.source_replay_output_path=$(measurement_source_replay_path_for_line "$checkpoint")"
    env_note "measurement_checkpoint_${checkpoint}l.source_sha256_output_path=$(measurement_source_sha256_path_for_line "$checkpoint")"
    env_note "measurement_checkpoint_${checkpoint}l.bench_sha256_output_path=$(measurement_bench_sha256_path_for_line "$checkpoint")"
    env_note "measurement_checkpoint_${checkpoint}l.hardware_output_path=$(measurement_hardware_path_for_line "$checkpoint")"
    env_note "measurement_checkpoint_${checkpoint}l.command_env_output_path=$(measurement_command_env_path_for_line "$checkpoint")"
    env_note "measurement_checkpoint_${checkpoint}l.command_status_output_path=$(measurement_command_status_path_for_line "$checkpoint")"
    env_note "measurement_checkpoint_${checkpoint}l.responsiveness_probe_output_path=$(measurement_responsiveness_path_for_line "$checkpoint")"
    env_note "measurement_checkpoint_${checkpoint}l.resource_usage_output_path=$(measurement_resource_usage_path_for_line "$checkpoint")"
    env_note "measurement_checkpoint_${checkpoint}l.measurement_summary_output_path=$(measurement_summary_path_for_line "$checkpoint")"
    env_note "measurement_checkpoint_${checkpoint}l.pareas_source_path=$(pareas_source_path_for_line "$checkpoint")"
    env_note "measurement_checkpoint_${checkpoint}l.pareas_source_sha256_output_path=$(pareas_source_sha256_path_for_line "$checkpoint")"
    env_note "measurement_checkpoint_${checkpoint}l.pareas_binary_sha256_output_path=$(pareas_binary_sha256_path_for_line "$checkpoint")"
    env_note "measurement_checkpoint_${checkpoint}l.pareas_output_path=$(pareas_output_path_for_line "$checkpoint")"
    env_note "measurement_checkpoint_${checkpoint}l.pareas_stdout_path=$(pareas_stdout_path_for_line "$checkpoint")"
  done
}

check_perf_measurement_environment() {
  env_note "VRAM/perf planning gate is no-run: no GPU jobs, tests, or Pareas jobs are launched"
  local errors_before="$env_errors"
  prepare_perf_measurement_plan_values || true
  if [[ "$env_errors" -eq "$errors_before" ]]; then
    env_note "LANIUS_PERF_LINES=$perf_lines"
    env_note "LANIUS_PERF_SEED=$perf_seed"
    env_note "LANIUS_PERF_CHECKPOINT_LINES=$(join_by_comma "${perf_checkpoint_lines[@]}")"
    env_note "measurement_checkpoint_execution_order=$(join_by_comma "${perf_checkpoint_lines[@]}")"
    env_note "LANIUS_PERF_ITERS=$perf_iters"
    env_note "LANIUS_PERF_COMMAND_TIMEOUT_MS=$perf_timeout_ms"
    env_note "LANIUS_X86_READBACK_TIMEOUT_MS=$perf_readback_timeout_ms"
    env_note "LANIUS_VRAM_SAMPLE_INTERVAL_MS=$perf_vram_sample_interval_ms"
    env_note "LANIUS_RESPONSIVENESS_PROBE_TIMEOUT_MS=$perf_responsiveness_timeout_ms"
    env_note "LANIUS_PERF_SOURCE=$perf_source"
    env_note "LANIUS_PERF_PHASE=$perf_phase"
    env_note "LANIUS_PERF_OUTPUT_PATH=$perf_output_path"
    env_note "LANIUS_PERFETTO_TRACE=$perf_trace_path"
    env_note "LANIUS_READBACK_SUMMARY_OUTPUT_PATH=$perf_readback_summary_path"
    env_note "LANIUS_VRAM_OUTPUT_PATH=$perf_vram_output_path"
    env_note "LANIUS_SOURCE_REPLAY_OUTPUT_PATH=$perf_source_replay_output_path"
    env_note "LANIUS_SOURCE_SHA256_OUTPUT_PATH=$perf_source_sha256_output_path"
    env_note "LANIUS_BENCH_SHA256_OUTPUT_PATH=$perf_bench_sha256_output_path"
    env_note "LANIUS_HARDWARE_OUTPUT_PATH=$perf_hardware_output_path"
    env_note "LANIUS_COMMAND_ENV_OUTPUT_PATH=$perf_command_env_output_path"
    env_note "LANIUS_COMMAND_STATUS_OUTPUT_PATH=$perf_command_status_output_path"
    env_note "LANIUS_RESPONSIVENESS_OUTPUT_PATH=$perf_responsiveness_output_path"
    env_note "LANIUS_RESOURCE_USAGE_OUTPUT_PATH=$perf_resource_usage_output_path"
    env_note "LANIUS_MEASUREMENT_SUMMARY_OUTPUT_PATH=$perf_measurement_summary_output_path"
    env_note "LANIUS_PAREAS_SOURCE_PATH=$perf_pareas_source_path"
    env_note "LANIUS_PAREAS_SOURCE_SHA256_OUTPUT_PATH=$perf_pareas_source_sha256_output_path"
    env_note "LANIUS_PAREAS_BINARY_SHA256_OUTPUT_PATH=$perf_pareas_binary_sha256_output_path"
    env_note "LANIUS_PAREAS_OUTPUT_PATH=$perf_pareas_output_path"
    env_note "LANIUS_PAREAS_STDOUT_PATH=$perf_pareas_stdout_path"
    emit_measurement_check_env_notes
  fi
  check_nvidia_smi_environment
}

check_generated_environment() {
  env_note "generated/Pareas gates are still no-run in --check-env"
  check_bounded_positive_integer_env LANIUS_GENERATED_LINES 5000 20000
  check_bounded_positive_integer_env LANIUS_CAPACITY_STRESS_LINES 5000 20000
  check_positive_integer_env LANIUS_GENERATED_GATE_COMMAND_TIMEOUT_MS 120000
  check_positive_integer_env LANIUS_X86_READBACK_TIMEOUT_MS 60000
  check_positive_integer_env LANIUS_MAX_CAPACITY_STRESS_COMPILE_FLOOR_BYTES 12884901888
  env_note "LANIUS_CAPACITY_STRESS_SOURCE=${LANIUS_CAPACITY_STRESS_SOURCE:-expr-dense}"
}

check_pareas_environment() {
  local pareas_bin

  check_bounded_positive_integer_env LANIUS_PAREAS_COMPARE_ITERS 1 3
  pareas_bin="$(find_pareas_bin || true)"
  if [[ -n "$pareas_bin" ]]; then
    env_note "Pareas=$pareas_bin"
  elif [[ -n "${PAREAS_BIN:-}" ]]; then
    env_error "PAREAS_BIN is set to '$PAREAS_BIN', but that path is not executable"
  elif is_truthy "${LANIUS_REQUIRE_PAREAS:-}"; then
    env_error "LANIUS_REQUIRE_PAREAS=1 but no Pareas binary was found; set PAREAS_BIN or build ~/code/pareas"
  else
    env_note "Pareas optional: set PAREAS_BIN or LANIUS_REQUIRE_PAREAS=1 to require the comparison"
  fi
}

check_acceptance_environment() {
  if [[ "$check_env" -eq 0 ]]; then
    return
  fi

  echo "# acceptance-env check tier=$tier"
  check_required_command cargo
  check_slangc
  if tier_uses_generated_env; then
    check_generated_environment
    check_perf_measurement_environment
  fi
  if tier_uses_pareas_env; then
    check_pareas_environment
  fi

  if [[ "$env_errors" -gt 0 ]]; then
    echo "# acceptance-env check failed: $env_errors issue(s)" >&2
    exit 1
  fi
  echo "# acceptance-env check ok: no tests were compiled or executed"
}

record_named_test_reference() {
  local kind="$1"
  local target="$2"
  local test_name="$3"
  shift 3
  if [[ "$check_plan" -eq 0 || -z "$test_name" ]]; then
    return
  fi

  plan_checked_tests=$((plan_checked_tests + 1))
  local valid=1
  if ! validate_test_name "$test_name"; then
    echo "acceptance plan references invalid $kind test '$test_name' for target '$target'" >&2
    plan_invalid_tests=$((plan_invalid_tests + 1))
    valid=0
  fi
  if [[ ! "$target" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "acceptance plan references invalid $kind target '$target' for test '$test_name'" >&2
    plan_invalid_tests=$((plan_invalid_tests + 1))
    valid=0
  fi
  if [[ "$valid" -eq 0 ]]; then
    return
  fi

  local target_found=0
  local target_path
  if [[ "$#" -eq 0 ]]; then
    target_found=1
  else
    for target_path in "$@"; do
      if [[ -e "$target_path" ]]; then
        target_found=1
        break
      fi
    done
  fi
  if [[ "$target_found" -eq 0 ]]; then
    echo "acceptance plan references missing $kind target path for '$target' test filter '$test_name'" >&2
    plan_missing_tests=$((plan_missing_tests + 1))
    return
  fi
  if [[ "$#" -gt 0 ]] && ! test_reference_filter_exists "$test_name" "$@"; then
    echo "acceptance plan references missing $kind test filter '$test_name' for target '$target'" >&2
    plan_missing_tests=$((plan_missing_tests + 1))
    return
  fi

  record_plan_evidence_claim "$kind" "$target" "$test_name"
}

record_plan_evidence_claim() {
  if [[ "$check_plan" -eq 0 ]]; then
    return
  fi
  case "$kind" in
    integration|lib|bin) ;;
    *) return ;;
  esac

  case "$current_plan_lane" in
    focused)
      plan_focused_evidence=$((plan_focused_evidence + 1))
      ;;
    smoke)
      plan_smoke_evidence=$((plan_smoke_evidence + 1))
      ;;
    generated)
      plan_generated_evidence=$((plan_generated_evidence + 1))
      ;;
    properties)
      plan_properties_evidence=$((plan_properties_evidence + 1))
      case "$target" in
        cli_*|package_manifest|source_pack_package_boundaries|type_checker_modules)
          plan_property_boundary_evidence=1
          ;;
      esac
      case "$target" in
        parser_hir_records)
          plan_property_record_evidence=1
          ;;
      esac
      case "$target" in
        codegen_wasm|codegen_x86|codegen_x86_properties|stdlib_runtime_contract)
          plan_property_execution_evidence=1
          ;;
      esac
      case "$target" in
        formatter|module_visibility|type_checker_scope|type_checker_semantics)
          plan_property_semantic_evidence=1
          ;;
      esac
      ;;
    pareas)
      plan_pareas_evidence=$((plan_pareas_evidence + 1))
      ;;
  esac
}

evidence_inventory_error() {
  echo "acceptance evidence-plan error: $*" >&2
  evidence_inventory_errors=$((evidence_inventory_errors + 1))
}

require_evidence_count() {
  local label="$1"
  local count="$2"
  if [[ "$count" -eq 0 ]]; then
    evidence_inventory_error "$label has no named behavior/property evidence in the acceptance plan"
  fi
}

check_evidence_inventory_contract() {
  if [[ "$check_plan" -eq 0 ]]; then
    return
  fi

  case "$tier" in
    focused)
      require_evidence_count focused "$plan_focused_evidence"
      ;;
    smoke)
      require_evidence_count smoke "$plan_smoke_evidence"
      ;;
    generated)
      require_evidence_count generated "$plan_generated_evidence"
      ;;
    properties)
      require_evidence_count properties "$plan_properties_evidence"
      ;;
    pareas)
      require_evidence_count pareas "$plan_pareas_evidence"
      ;;
    readiness)
      require_evidence_count focused "$plan_focused_evidence"
      require_evidence_count smoke "$plan_smoke_evidence"
      require_evidence_count properties "$plan_properties_evidence"
      ;;
    all)
      require_evidence_count focused "$plan_focused_evidence"
      require_evidence_count smoke "$plan_smoke_evidence"
      require_evidence_count generated "$plan_generated_evidence"
      require_evidence_count properties "$plan_properties_evidence"
      require_evidence_count pareas "$plan_pareas_evidence"
      ;;
  esac

  case "$tier" in
    properties|readiness|all)
      if [[ "$plan_property_boundary_evidence" -eq 0 ]]; then
        evidence_inventory_error "properties lane has no public-boundary evidence"
      fi
      if [[ "$plan_property_record_evidence" -eq 0 ]]; then
        evidence_inventory_error "properties lane has no record-invariant evidence"
      fi
      if [[ "$plan_property_execution_evidence" -eq 0 ]]; then
        evidence_inventory_error "properties lane has no execution/codegen evidence"
      fi
      if [[ "$plan_property_semantic_evidence" -eq 0 ]]; then
        evidence_inventory_error "properties lane has no semantic evidence"
      fi
      ;;
  esac

  if [[ "$evidence_inventory_errors" -eq 0 ]]; then
    echo "# acceptance evidence-plan check ok: focused=$plan_focused_evidence smoke=$plan_smoke_evidence generated=$plan_generated_evidence properties=$plan_properties_evidence pareas=$plan_pareas_evidence"
  fi
}

verify_measurement_plan_contains() {
  local plan="$1"
  local label="$2"
  local needle="$3"

  if [[ "$check_plan" -eq 0 ]]; then
    return
  fi

  plan_checked_commands=$((plan_checked_commands + 1))
  if [[ "$plan" != *"$needle"* ]]; then
    echo "acceptance measurement plan missing $label: $needle" >&2
    plan_missing_commands=$((plan_missing_commands + 1))
  fi
}

measurement_checkpoint_block() {
  local plan="$1"
  local checkpoint="$2"
  local start="checkpoint_${checkpoint}l:"

  awk -v start="$start" '
    $0 == start {
      in_block = 1
      print
      next
    }
    in_block && /^checkpoint_[0-9]+l:/ {
      exit
    }
    in_block && /^notes:/ {
      exit
    }
    in_block {
      print
    }
  ' <<<"$plan"
}

verify_measurement_checkpoint_contains() {
  local plan="$1"
  local checkpoint="$2"
  local label="$3"
  local needle="$4"
  local block

  if [[ "$check_plan" -eq 0 ]]; then
    return
  fi

  block="$(measurement_checkpoint_block "$plan" "$checkpoint")"
  plan_checked_commands=$((plan_checked_commands + 1))
  if [[ -z "$block" || "$block" != *"$needle"* ]]; then
    echo "acceptance measurement checkpoint $checkpoint missing $label: $needle" >&2
    plan_missing_commands=$((plan_missing_commands + 1))
  fi
}

measurement_checkpoint_field() {
  local block="$1"
  local field="$2"

  awk -v prefix="  ${field}: " '
    index($0, prefix) == 1 {
      value = substr($0, length(prefix) + 1)
      print value
      exit
    }
  ' <<<"$block"
}

csv_has_value() {
  local csv="$1"
  local needle="$2"
  local value
  local -a values

  IFS=',' read -r -a values <<<"$csv"
  for value in "${values[@]}"; do
    if [[ "$value" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

csv_count() {
  local csv="$1"
  local -a values

  IFS=',' read -r -a values <<<"$csv"
  if [[ -z "$csv" ]]; then
    printf '%s\n' 0
  else
    printf '%s\n' "${#values[@]}"
  fi
}

verify_measurement_checkpoint_parallel_pass_contracts() {
  local plan="$1"
  local checkpoint="$2"

  if [[ "$check_plan" -eq 0 ]]; then
    return
  fi

  local block
  block="$(measurement_checkpoint_block "$plan" "$checkpoint")"
  plan_checked_commands=$((plan_checked_commands + 1))
  if [[ -z "$block" ]]; then
    echo "acceptance measurement checkpoint $checkpoint missing parallel pass-contract block" >&2
    plan_missing_commands=$((plan_missing_commands + 1))
    return
  fi

  local groups
  local execution_order
  local required_fields
  groups="$(measurement_checkpoint_field "$block" parallel_pass_contract_groups)"
  execution_order="$(measurement_checkpoint_field "$block" parallel_pass_contract_execution_order)"
  required_fields="$(measurement_checkpoint_field "$block" required_parallel_pass_contract_fields)"
  if [[ -z "$groups" || -z "$execution_order" || -z "$required_fields" ]]; then
    echo "acceptance measurement checkpoint $checkpoint missing parallel pass-contract evidence-class fields" >&2
    plan_missing_commands=$((plan_missing_commands + 1))
    return
  fi
  if [[ "$(csv_count "$groups")" -eq 0 || "$(csv_count "$groups")" -ne "$(csv_count "$execution_order")" ]]; then
    echo "acceptance measurement checkpoint $checkpoint has inconsistent parallel pass-contract evidence-class order" >&2
    plan_missing_commands=$((plan_missing_commands + 1))
    return
  fi

  local group
  local contract_line
  local contract_text
  local contract_count=0
  local record_evidence=0
  local semantic_evidence=0
  local execution_evidence=0
  local measurement_evidence=0
  local duplicate_group=0
  local -A seen_contract_groups=()

  while IFS= read -r contract_line || [[ -n "$contract_line" ]]; do
    case "$contract_line" in
      '  parallel_pass_contract_'*:*)
        case "$contract_line" in
          '  parallel_pass_contract_schema:'*|'  parallel_pass_contract_policy:'*|'  parallel_pass_contract_groups:'*|'  parallel_pass_contract_order_policy:'*|'  parallel_pass_contract_execution_order:'*)
            continue
            ;;
        esac
        contract_text="${contract_line#*: }"
        local -A contract=()
        local word
        local key
        local value
        for word in $contract_text; do
          if [[ "$word" != *=* ]]; then
            echo "acceptance measurement checkpoint $checkpoint has malformed pass-contract word '$word'" >&2
            plan_missing_commands=$((plan_missing_commands + 1))
            return
          fi
          key="${word%%=*}"
          value="${word#*=}"
          contract["$key"]="$value"
        done

        local -a required_field_values
        IFS=',' read -r -a required_field_values <<<"$required_fields"
        local required_field
        for required_field in "${required_field_values[@]}"; do
          if [[ -z "${contract[$required_field]:-}" ]]; then
            echo "acceptance measurement checkpoint $checkpoint pass contract missing required field '$required_field'" >&2
            plan_missing_commands=$((plan_missing_commands + 1))
            return
          fi
        done

        if [[ "${contract[contract_schema]}" != "$(measurement_parallel_pass_contract_schema)" \
          || "${contract[loop_status]}" != "$(measurement_pass_contract_loop_status)" \
          || "${contract[fallback_status]}" != "$(measurement_pass_contract_fallback_status)" ]]; then
          echo "acceptance measurement checkpoint $checkpoint pass contract has inconsistent schema or readiness status" >&2
          plan_missing_commands=$((plan_missing_commands + 1))
          return
        fi

        group="${contract[pass_group]}"
        if ! csv_has_value "$groups" "$group"; then
          echo "acceptance measurement checkpoint $checkpoint pass contract publishes group '$group' outside the evidence-class set" >&2
          plan_missing_commands=$((plan_missing_commands + 1))
          return
        fi
        if [[ -n "${seen_contract_groups[$group]:-}" ]]; then
          duplicate_group=1
        fi
        seen_contract_groups[$group]=1
        contract_count=$((contract_count + 1))

        case "${contract[evidence_shape]}" in
          record-invariant) record_evidence=1 ;;
          semantic-contract) semantic_evidence=1 ;;
          execution-contract) execution_evidence=1 ;;
          measurement-scaffold) measurement_evidence=1 ;;
        esac
        ;;
    esac
  done <<<"$block"

  if [[ "$duplicate_group" -eq 1 || "$contract_count" -ne "$(csv_count "$groups")" ]]; then
    echo "acceptance measurement checkpoint $checkpoint pass contracts must map one-to-one with advertised evidence classes" >&2
    plan_missing_commands=$((plan_missing_commands + 1))
    return
  fi
  local -a execution_order_values
  IFS=',' read -r -a execution_order_values <<<"$execution_order"
  local -A seen_execution_groups=()
  for group in "${execution_order_values[@]}"; do
    if [[ -z "${seen_contract_groups[$group]:-}" ]]; then
      echo "acceptance measurement checkpoint $checkpoint execution-order group '$group' has no pass contract" >&2
      plan_missing_commands=$((plan_missing_commands + 1))
      return
    fi
    if [[ -n "${seen_execution_groups[$group]:-}" ]]; then
      echo "acceptance measurement checkpoint $checkpoint execution-order group '$group' is repeated" >&2
      plan_missing_commands=$((plan_missing_commands + 1))
      return
    fi
    seen_execution_groups[$group]=1
  done
  if [[ "$record_evidence" -eq 0 || "$semantic_evidence" -eq 0 || "$execution_evidence" -eq 0 || "$measurement_evidence" -eq 0 ]]; then
    echo "acceptance measurement checkpoint $checkpoint pass contracts must include record, semantic, execution, and measurement-scaffold evidence" >&2
    plan_missing_commands=$((plan_missing_commands + 1))
    return
  fi
}

check_measurement_plan_contract() {
  if [[ "$check_plan" -eq 0 ]]; then
    return
  fi

  case "$tier" in
    generated|readiness|all) ;;
    *) return ;;
  esac

  if ! prepare_perf_measurement_plan_values; then
    echo "acceptance measurement plan defaults failed validation" >&2
    plan_missing_commands=$((plan_missing_commands + 1))
    return
  fi

  local -a checkpoints=("${perf_checkpoint_lines[@]}")
  local plan
  if ! plan="$(emit_perf_measurement_plan)"; then
    echo "acceptance measurement plan failed to render" >&2
    plan_missing_commands=$((plan_missing_commands + 1))
    return
  fi

  verify_measurement_plan_contains "$plan" target "target: x86_64-elf"
  verify_measurement_plan_contains "$plan" schema "measurement_plan_schema: lanius.measurement-plan.v1"
  verify_measurement_plan_contains "$plan" evidence-policy "measurement_evidence_policy: local-artifacts-only"
  verify_measurement_plan_contains "$plan" paper-numbers "paper_numbers_accepted: false"
  verify_measurement_plan_contains "$plan" comparison-baseline-policy "comparison_baseline_policy: local-pareas-artifacts-only"
  verify_measurement_plan_contains "$plan" freshness-policy "freshness_policy: hash-and-checkpoint-field-match"
  verify_measurement_plan_contains "$plan" timing-policy "measurement_timing_policy: $(measurement_timing_policy)"
  verify_measurement_plan_contains "$plan" cold-start-policy "cold_start_policy: $(measurement_cold_start_policy)"
  verify_measurement_plan_contains "$plan" compile-latency-claim-source "compile_latency_claim_source: $(measurement_compile_latency_claim_source)"
  verify_measurement_plan_contains "$plan" runtime-validation-policy "runtime_validation_policy: $(measurement_runtime_validation_policy)"
  verify_measurement_plan_contains "$plan" claim-provenance-schema "claim_provenance_schema: $(measurement_claim_provenance_schema)"
  verify_measurement_plan_contains "$plan" baseline-separation-schema "baseline_separation_schema: $(measurement_baseline_separation_schema)"
  verify_measurement_plan_contains "$plan" required-claim-provenance-fields "required_claim_provenance_fields: $(measurement_required_claim_provenance_fields)"
  verify_measurement_plan_contains "$plan" paper-baseline-policy "paper_baseline_policy: $(measurement_paper_baseline_policy)"
  verify_measurement_plan_contains "$plan" paper-baseline-numbers-status "paper_baseline_numbers_status: $(measurement_paper_baseline_numbers_status)"
  verify_measurement_plan_contains "$plan" local-evidence-status-policy "local_evidence_status_policy: $(measurement_local_evidence_status_policy)"
  verify_measurement_plan_contains "$plan" local-performance-claim-policy "local_performance_claim_policy: $(measurement_local_performance_claim_policy)"
  verify_measurement_plan_contains "$plan" local-performance-claim-source "local_performance_claim_source: $(measurement_local_performance_claim_source)"
  verify_measurement_plan_contains "$plan" local-performance-claim-status "local_performance_claim_status: $(measurement_local_performance_claim_status)"
  verify_measurement_plan_contains "$plan" local-performance-claim-blockers "local_performance_claim_blockers: $(measurement_local_performance_claim_blockers)"
  verify_measurement_plan_contains "$plan" local-vram-claim-source "local_vram_claim_source: $(measurement_local_vram_claim_source)"
  verify_measurement_plan_contains "$plan" local-pareas-claim-source "local_pareas_claim_source: $(measurement_local_pareas_claim_source)"
  verify_measurement_plan_contains "$plan" scaling-claim-policy "scaling_claim_policy: $(measurement_scaling_claim_policy)"
  verify_measurement_plan_contains "$plan" scaling-claim-source "scaling_claim_source: $(measurement_scaling_claim_source)"
  verify_measurement_plan_contains "$plan" scaling-claim-status "scaling_claim_status: $(measurement_scaling_claim_status)"
  verify_measurement_plan_contains "$plan" scaling-claim-blockers "scaling_claim_blockers: $(measurement_scaling_claim_blockers)"
  verify_measurement_plan_contains "$plan" paper-pass-order-schema "paper_pass_order_schema: $(measurement_paper_pass_order_schema)"
  verify_measurement_plan_contains "$plan" paper-pass-order-source "paper_pass_order_source: $(measurement_paper_pass_order_source)"
  verify_measurement_plan_contains "$plan" paper-pass-order "paper_pass_order: $(measurement_paper_pass_order)"
  verify_measurement_plan_contains "$plan" paper-pass-alignment-policy "paper_pass_alignment_policy: $(measurement_paper_pass_alignment_policy)"
  verify_measurement_plan_contains "$plan" paper-pass-alignment-status "paper_pass_alignment_status: $(measurement_paper_pass_alignment_status)"
  verify_measurement_plan_contains "$plan" paper-pass-alignment-blockers "paper_pass_alignment_blockers: $(measurement_paper_pass_alignment_blockers)"
  verify_measurement_plan_contains "$plan" parallel-pass-contract-schema "parallel_pass_contract_schema: $(measurement_parallel_pass_contract_schema)"
  verify_measurement_plan_contains "$plan" parallel-pass-contract-policy "parallel_pass_contract_policy: $(measurement_parallel_pass_contract_policy)"
  verify_measurement_plan_contains "$plan" parallel-pass-contract-groups "parallel_pass_contract_groups: $(measurement_parallel_pass_contract_groups)"
  verify_measurement_plan_contains "$plan" parallel-pass-contract-order-policy "parallel_pass_contract_order_policy: $(measurement_parallel_pass_contract_order_policy)"
  verify_measurement_plan_contains "$plan" parallel-pass-contract-execution-order "parallel_pass_contract_execution_order: $(measurement_parallel_pass_contract_execution_order)"
  verify_measurement_plan_contains "$plan" required-parallel-pass-contract-fields "required_parallel_pass_contract_fields: $(measurement_required_parallel_pass_contract_fields)"
  verify_measurement_plan_contains "$plan" pass-contract-status-schema "pass_contract_status_schema: $(measurement_pass_contract_status_schema)"
  verify_measurement_plan_contains "$plan" required-pass-contract-status-fields "required_pass_contract_status_fields: $(measurement_required_pass_contract_status_fields)"
  verify_measurement_plan_contains "$plan" pass-contract-loop-policy "pass_contract_loop_policy: $(measurement_pass_contract_loop_policy)"
  verify_measurement_plan_contains "$plan" pass-contract-loop-status "pass_contract_loop_status: $(measurement_pass_contract_loop_status)"
  verify_measurement_plan_contains "$plan" pass-contract-fallback-status "pass_contract_fallback_status: $(measurement_pass_contract_fallback_status)"
  verify_measurement_plan_contains "$plan" pass-contract-claim-status "pass_contract_claim_status: $(measurement_pass_contract_claim_status)"
  verify_measurement_plan_contains "$plan" pass-contract-claim-blockers "pass_contract_claim_blockers: $(measurement_pass_contract_claim_blockers)"
  verify_measurement_plan_contains "$plan" pass-contract-readiness-status "pass_contract_readiness_status: $(measurement_pass_contract_readiness_status)"
  verify_measurement_plan_contains "$plan" timeout-provenance-schema "timeout_provenance_schema: $(measurement_timeout_provenance_schema)"
  verify_measurement_plan_contains "$plan" required-timeout-provenance-fields "required_timeout_provenance_fields: $(measurement_required_timeout_provenance_fields)"
  verify_measurement_plan_contains "$plan" timeout-scope "timeout_scope: $(measurement_timeout_scope)"
  verify_measurement_plan_contains "$plan" timeout-source "timeout_source: $(measurement_timeout_source)"
  verify_measurement_plan_contains "$plan" timeout-enforced-by "timeout_enforced_by: $(measurement_timeout_enforced_by)"
  verify_measurement_plan_contains "$plan" timeout-exit-code "timeout_exit_code: $(measurement_timeout_exit_code)"
  verify_measurement_plan_contains "$plan" timeout-exit-code-means-timed-out "timeout_exit_code_means_timed_out: $(measurement_timeout_exit_code_means_timed_out)"
  verify_measurement_plan_contains "$plan" source-control-policy "source_control_policy: $(measurement_source_control_policy)"
  verify_measurement_plan_contains "$plan" repeatability-policy "repeatability_policy: $(measurement_repeatability_policy)"
  verify_measurement_plan_contains "$plan" minimum-iterations-for-claim "minimum_iterations_for_claim: $(measurement_minimum_iterations_for_claim)"
  verify_measurement_plan_contains "$plan" checkpoints "checkpoints: $(join_by_comma "${checkpoints[@]}")"
  verify_measurement_plan_contains "$plan" checkpoint-execution-order "checkpoint_execution_order: $(join_by_comma "${checkpoints[@]}")"
  verify_measurement_plan_contains "$plan" required-artifacts "required_checkpoint_artifacts: $(measurement_required_artifacts)"
  verify_measurement_plan_contains "$plan" optional-comparison-artifacts "optional_comparison_artifacts: $(measurement_optional_comparison_artifacts)"
  verify_measurement_plan_contains "$plan" artifact-manifest-schema "artifact_manifest_schema: $(measurement_artifact_manifest_schema)"
  verify_measurement_plan_contains "$plan" required-artifact-manifest-fields "required_artifact_manifest_fields: $(measurement_required_artifact_manifest_fields)"
  verify_measurement_plan_contains "$plan" readback-summary-schema "readback_summary_schema: $(measurement_readback_summary_schema)"
  verify_measurement_plan_contains "$plan" required-readback-summary-fields "required_readback_summary_fields: $(measurement_required_readback_summary_fields)"
  verify_measurement_plan_contains "$plan" vram-csv-schema "vram_csv_schema: $(measurement_vram_csv_schema)"
  verify_measurement_plan_contains "$plan" required-vram-csv-columns "required_vram_csv_columns: $(measurement_required_vram_csv_columns)"
  verify_measurement_plan_contains "$plan" hardware-identity-schema "hardware_identity_schema: $(measurement_hardware_identity_schema)"
  verify_measurement_plan_contains "$plan" required-hardware-identity-fields "required_hardware_identity_fields: $(measurement_required_hardware_identity_fields)"
  verify_measurement_plan_contains "$plan" command-environment-schema "command_environment_schema: $(measurement_command_environment_schema)"
  verify_measurement_plan_contains "$plan" required-command-environment-fields "required_command_environment_fields: $(measurement_required_command_environment_fields)"
  verify_measurement_plan_contains "$plan" responsiveness-probe-schema "responsiveness_probe_schema: $(measurement_responsiveness_probe_schema)"
  verify_measurement_plan_contains "$plan" required-responsiveness-probe-fields "required_responsiveness_probe_fields: $(measurement_required_responsiveness_probe_fields)"
  verify_measurement_plan_contains "$plan" command-status-schema "command_status_schema: $(measurement_command_status_schema)"
  verify_measurement_plan_contains "$plan" evidence-status-schema "evidence_status_schema: $(measurement_evidence_status_schema)"
  verify_measurement_plan_contains "$plan" required-evidence-status-fields "required_evidence_status_fields: $(measurement_required_evidence_status_fields)"
  verify_measurement_plan_contains "$plan" evidence-freshness-schema "evidence_freshness_schema: $(measurement_evidence_freshness_schema)"
  verify_measurement_plan_contains "$plan" required-evidence-freshness-fields "required_evidence_freshness_fields: $(measurement_required_evidence_freshness_fields)"
  verify_measurement_plan_contains "$plan" claim-readiness-schema "claim_readiness_schema: $(measurement_claim_readiness_schema)"
  verify_measurement_plan_contains "$plan" claim-readiness-policy "claim_readiness_policy: $(measurement_claim_readiness_policy)"
  verify_measurement_plan_contains "$plan" claim-readiness-required-evidence "claim_readiness_required_evidence_classes: $(measurement_claim_readiness_required_evidence_classes)"
  verify_measurement_plan_contains "$plan" claim-readiness-required-statuses "claim_readiness_required_statuses: $(measurement_claim_readiness_required_statuses)"
  verify_measurement_plan_contains "$plan" claim-scope-policy "claim_scope_policy: $(measurement_claim_scope_policy)"
  verify_measurement_plan_contains "$plan" required-claim-readiness-fields "required_claim_readiness_fields: $(measurement_required_claim_readiness_fields)"
  verify_measurement_plan_contains "$plan" required-status-fields "required_status_fields: $(measurement_required_status_fields)"
  verify_measurement_plan_contains "$plan" optional-status-fields "optional_status_fields: $(measurement_optional_status_fields)"
  verify_measurement_plan_contains "$plan" summary-schema "measurement_summary_schema: lanius.measurement-summary.v1"
  verify_measurement_plan_contains "$plan" required-summary-fields "required_summary_fields: $(measurement_required_summary_fields)"
  verify_measurement_plan_contains "$plan" build-command "lanius_build_command ="
  verify_measurement_plan_contains "$plan" hardware-path "hardware_output_path:"
  verify_measurement_plan_contains "$plan" readback-summary-path "readback_summary_path:"
  verify_measurement_plan_contains "$plan" command-env-path "command_env_output_path:"
  verify_measurement_plan_contains "$plan" command-status-path "command_status_output_path:"
  verify_measurement_plan_contains "$plan" responsiveness-path "responsiveness_probe_output_path:"
  verify_measurement_plan_contains "$plan" resource-usage-path "resource_usage_output_path:"
  verify_measurement_plan_contains "$plan" measurement-summary-path "measurement_summary_output_path:"
  verify_measurement_plan_contains "$plan" source-seed "source_seed: $perf_seed"
  verify_measurement_plan_contains "$plan" source-replay-path "source_replay_output_path:"
  verify_measurement_plan_contains "$plan" source-sha256-path "source_sha256_output_path:"
  verify_measurement_plan_contains "$plan" bench-sha256-path "bench_sha256_output_path:"
  verify_measurement_plan_contains "$plan" pareas-source-sha256-path "pareas_source_sha256_output_path:"
  verify_measurement_plan_contains "$plan" pareas-binary-sha256-path "pareas_binary_sha256_output_path:"

  local checkpoint
  for checkpoint in "${checkpoints[@]}"; do
    verify_measurement_plan_contains "$plan" "checkpoint-${checkpoint}" "checkpoint_${checkpoint}l:"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "line-count-${checkpoint}" "  line_count: $checkpoint"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "iterations-${checkpoint}" "  iterations: $perf_iters"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "timeout-ms-${checkpoint}" "  timeout_ms: $perf_timeout_ms"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "readback-timeout-ms-${checkpoint}" "  readback_timeout_ms: $perf_readback_timeout_ms"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "vram-sample-interval-ms-${checkpoint}" "  vram_sample_interval_ms: $perf_vram_sample_interval_ms"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "responsiveness-timeout-ms-${checkpoint}" "  responsiveness_probe_timeout_ms: $perf_responsiveness_timeout_ms"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "source-seed-${checkpoint}" "  source_seed: $perf_seed"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "target-${checkpoint}" "  target: x86_64-elf"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "gpu-timing-env-${checkpoint}" "  gpu_timing_env: LANIUS_GPU_TIMING=1 LANIUS_GPU_COMPILE_HOST_TIMING=1"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "timing-policy-${checkpoint}" "  measurement_timing_policy: $(measurement_timing_policy)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "cold-start-policy-${checkpoint}" "  cold_start_policy: $(measurement_cold_start_policy)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "compile-latency-claim-source-${checkpoint}" "  compile_latency_claim_source: $(measurement_compile_latency_claim_source)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "runtime-validation-policy-${checkpoint}" "  runtime_validation_policy: $(measurement_runtime_validation_policy)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "claim-provenance-schema-${checkpoint}" "  claim_provenance_schema: $(measurement_claim_provenance_schema)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "baseline-separation-schema-${checkpoint}" "  baseline_separation_schema: $(measurement_baseline_separation_schema)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "required-claim-provenance-fields-${checkpoint}" "  required_claim_provenance_fields: $(measurement_required_claim_provenance_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "paper-baseline-policy-${checkpoint}" "  paper_baseline_policy: $(measurement_paper_baseline_policy)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "paper-baseline-numbers-status-${checkpoint}" "  paper_baseline_numbers_status: $(measurement_paper_baseline_numbers_status)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "local-evidence-status-policy-${checkpoint}" "  local_evidence_status_policy: $(measurement_local_evidence_status_policy)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "local-performance-claim-policy-${checkpoint}" "  local_performance_claim_policy: $(measurement_local_performance_claim_policy)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "local-performance-claim-source-${checkpoint}" "  local_performance_claim_source: $(measurement_local_performance_claim_source)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "local-performance-claim-status-${checkpoint}" "  local_performance_claim_status: $(measurement_local_performance_claim_status)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "local-performance-claim-blockers-${checkpoint}" "  local_performance_claim_blockers: $(measurement_local_performance_claim_blockers)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "local-vram-claim-source-${checkpoint}" "  local_vram_claim_source: $(measurement_local_vram_claim_source)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "local-pareas-claim-source-${checkpoint}" "  local_pareas_claim_source: $(measurement_local_pareas_claim_source)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "scaling-claim-policy-${checkpoint}" "  scaling_claim_policy: $(measurement_scaling_claim_policy)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "scaling-claim-source-${checkpoint}" "  scaling_claim_source: $(measurement_scaling_claim_source)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "scaling-claim-status-${checkpoint}" "  scaling_claim_status: $(measurement_scaling_claim_status)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "scaling-claim-blockers-${checkpoint}" "  scaling_claim_blockers: $(measurement_scaling_claim_blockers)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "paper-pass-order-schema-${checkpoint}" "  paper_pass_order_schema: $(measurement_paper_pass_order_schema)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "paper-pass-order-source-${checkpoint}" "  paper_pass_order_source: $(measurement_paper_pass_order_source)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "paper-pass-order-${checkpoint}" "  paper_pass_order: $(measurement_paper_pass_order)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "paper-pass-alignment-policy-${checkpoint}" "  paper_pass_alignment_policy: $(measurement_paper_pass_alignment_policy)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "paper-pass-alignment-status-${checkpoint}" "  paper_pass_alignment_status: $(measurement_paper_pass_alignment_status)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "paper-pass-alignment-blockers-${checkpoint}" "  paper_pass_alignment_blockers: $(measurement_paper_pass_alignment_blockers)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "parallel-pass-contract-schema-${checkpoint}" "  parallel_pass_contract_schema: $(measurement_parallel_pass_contract_schema)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "parallel-pass-contract-policy-${checkpoint}" "  parallel_pass_contract_policy: $(measurement_parallel_pass_contract_policy)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "parallel-pass-contract-groups-${checkpoint}" "  parallel_pass_contract_groups: $(measurement_parallel_pass_contract_groups)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "parallel-pass-contract-order-policy-${checkpoint}" "  parallel_pass_contract_order_policy: $(measurement_parallel_pass_contract_order_policy)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "parallel-pass-contract-execution-order-${checkpoint}" "  parallel_pass_contract_execution_order: $(measurement_parallel_pass_contract_execution_order)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "required-parallel-pass-contract-fields-${checkpoint}" "  required_parallel_pass_contract_fields: $(measurement_required_parallel_pass_contract_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "pass-contract-status-schema-${checkpoint}" "  pass_contract_status_schema: $(measurement_pass_contract_status_schema)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "required-pass-contract-status-fields-${checkpoint}" "  required_pass_contract_status_fields: $(measurement_required_pass_contract_status_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "pass-contract-loop-policy-${checkpoint}" "  pass_contract_loop_policy: $(measurement_pass_contract_loop_policy)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "pass-contract-loop-status-${checkpoint}" "  pass_contract_loop_status: $(measurement_pass_contract_loop_status)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "pass-contract-fallback-status-${checkpoint}" "  pass_contract_fallback_status: $(measurement_pass_contract_fallback_status)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "pass-contract-claim-status-${checkpoint}" "  pass_contract_claim_status: $(measurement_pass_contract_claim_status)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "pass-contract-claim-blockers-${checkpoint}" "  pass_contract_claim_blockers: $(measurement_pass_contract_claim_blockers)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "pass-contract-readiness-status-${checkpoint}" "  pass_contract_readiness_status: $(measurement_pass_contract_readiness_status)"
    verify_measurement_checkpoint_parallel_pass_contracts "$plan" "$checkpoint"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "timeout-provenance-schema-${checkpoint}" "  timeout_provenance_schema: $(measurement_timeout_provenance_schema)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "required-timeout-provenance-fields-${checkpoint}" "  required_timeout_provenance_fields: $(measurement_required_timeout_provenance_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "timeout-scope-${checkpoint}" "  timeout_scope: $(measurement_timeout_scope)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "timeout-source-${checkpoint}" "  timeout_source: $(measurement_timeout_source)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "timeout-enforced-by-${checkpoint}" "  timeout_enforced_by: $(measurement_timeout_enforced_by)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "timeout-exit-code-${checkpoint}" "  timeout_exit_code: $(measurement_timeout_exit_code)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "timeout-exit-code-means-timed-out-${checkpoint}" "  timeout_exit_code_means_timed_out: $(measurement_timeout_exit_code_means_timed_out)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "required-artifacts-${checkpoint}" "  required_artifacts: $(measurement_required_artifacts)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "artifact-manifest-schema-${checkpoint}" "  artifact_manifest_schema: $(measurement_artifact_manifest_schema)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "required-artifact-manifest-fields-${checkpoint}" "  required_artifact_manifest_fields: $(measurement_required_artifact_manifest_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "readback-summary-schema-${checkpoint}" "  readback_summary_schema: $(measurement_readback_summary_schema)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "required-readback-summary-fields-${checkpoint}" "  required_readback_summary_fields: $(measurement_required_readback_summary_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "vram-csv-schema-${checkpoint}" "  vram_csv_schema: $(measurement_vram_csv_schema)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "required-vram-csv-columns-${checkpoint}" "  required_vram_csv_columns: $(measurement_required_vram_csv_columns)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "hardware-identity-schema-${checkpoint}" "  hardware_identity_schema: $(measurement_hardware_identity_schema)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "required-hardware-identity-fields-${checkpoint}" "  required_hardware_identity_fields: $(measurement_required_hardware_identity_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "command-environment-schema-${checkpoint}" "  command_environment_schema: $(measurement_command_environment_schema)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "required-command-environment-fields-${checkpoint}" "  required_command_environment_fields: $(measurement_required_command_environment_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "responsiveness-probe-schema-${checkpoint}" "  responsiveness_probe_schema: $(measurement_responsiveness_probe_schema)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "required-responsiveness-probe-fields-${checkpoint}" "  required_responsiveness_probe_fields: $(measurement_required_responsiveness_probe_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "command-status-schema-${checkpoint}" "  command_status_schema: $(measurement_command_status_schema)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-status-schema-${checkpoint}" "  evidence_status_schema: $(measurement_evidence_status_schema)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "required-evidence-status-fields-${checkpoint}" "  required_evidence_status_fields: $(measurement_required_evidence_status_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-freshness-schema-${checkpoint}" "  evidence_freshness_schema: $(measurement_evidence_freshness_schema)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "required-evidence-freshness-fields-${checkpoint}" "  required_evidence_freshness_fields: $(measurement_required_evidence_freshness_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "claim-readiness-schema-${checkpoint}" "  claim_readiness_schema: $(measurement_claim_readiness_schema)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "claim-readiness-policy-${checkpoint}" "  claim_readiness_policy: $(measurement_claim_readiness_policy)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "claim-readiness-required-evidence-${checkpoint}" "  claim_readiness_required_evidence_classes: $(measurement_claim_readiness_required_evidence_classes)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "claim-readiness-required-statuses-${checkpoint}" "  claim_readiness_required_statuses: $(measurement_claim_readiness_required_statuses)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "claim-scope-policy-${checkpoint}" "  claim_scope_policy: $(measurement_claim_scope_policy)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "source-control-policy-${checkpoint}" "  source_control_policy: $(measurement_source_control_policy)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "repeatability-policy-${checkpoint}" "  repeatability_policy: $(measurement_repeatability_policy)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "minimum-iterations-for-claim-${checkpoint}" "  minimum_iterations_for_claim: $(measurement_minimum_iterations_for_claim)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "required-claim-readiness-fields-${checkpoint}" "  required_claim_readiness_fields: $(measurement_required_claim_readiness_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "required-status-fields-${checkpoint}" "  required_status_fields: $(measurement_required_status_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "optional-status-fields-${checkpoint}" "  optional_status_fields: $(measurement_optional_status_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "required-summary-fields-${checkpoint}" "  required_summary_fields: $(measurement_required_summary_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "optional-comparison-artifacts-${checkpoint}" "  optional_comparison_artifacts: $(measurement_optional_comparison_artifacts)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-artifacts-begin-${checkpoint}" "  evidence_artifacts_begin"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-artifacts-end-${checkpoint}" "  evidence_artifacts_end"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-lanius-stdout-${checkpoint}" "  evidence_artifact: checkpoint=$checkpoint name=lanius_stdout required=true"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-lanius-stdout-status-${checkpoint}" "name=lanius_stdout required=true path="
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-lanius-stdout-status-artifact-${checkpoint}" "producer=lanius_wrapped_command_${checkpoint}l status_field=lanius_exit_status status_artifact=command_status"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-lanius-stdout-claim-fields-${checkpoint}" "claim_fields=best_ms,throughput_lines_per_second"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-perfetto-${checkpoint}" "  evidence_artifact: checkpoint=$checkpoint name=perfetto_trace required=true"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-readback-${checkpoint}" "  evidence_artifact: checkpoint=$checkpoint name=readback_summary required=true"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-readback-schema-${checkpoint}" "name=readback_summary required=true path="
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-readback-fields-${checkpoint}" "schema=$(measurement_readback_summary_schema) fields=$(measurement_required_readback_summary_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-readback-claim-fields-${checkpoint}" "claim_fields=readback_span_count,readback_total_ms,readback_max_span_ms"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-vram-${checkpoint}" "  evidence_artifact: checkpoint=$checkpoint name=vram_csv required=true"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-vram-schema-${checkpoint}" "schema=$(measurement_vram_csv_schema) columns=$(measurement_required_vram_csv_columns)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-vram-claim-fields-${checkpoint}" "claim_fields=max_vram_bytes,nvidia_smi_exit_status"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-vram-header-stale-check-${checkpoint}" "stale_check=vram_csv_header_matches_required_columns"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-resource-usage-${checkpoint}" "  evidence_artifact: checkpoint=$checkpoint name=resource_usage required=true"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-resource-usage-status-artifact-${checkpoint}" "producer=lanius_wrapped_command_${checkpoint}l status_field=resource_usage_status status_artifact=command_status"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-resource-usage-stale-check-${checkpoint}" "stale_check=resource_usage_command_matches_checkpoint"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-source-replay-status-artifact-${checkpoint}" "name=source_replay required=true"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-source-replay-status-none-${checkpoint}" "producer=source_replay_command_${checkpoint}l status_field=not_captured status_artifact=none"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-bench-sha256-${checkpoint}" "  evidence_artifact: checkpoint=$checkpoint name=bench_binary_sha256 required=true"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-bench-sha256-status-none-${checkpoint}" "producer=bench_sha256_command_${checkpoint}l status_field=not_captured status_artifact=none"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-hardware-schema-${checkpoint}" "schema=$(measurement_hardware_identity_schema) fields=$(measurement_required_hardware_identity_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-command-environment-schema-${checkpoint}" "schema=$(measurement_command_environment_schema) fields=$(measurement_required_command_environment_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-status-${checkpoint}" "  evidence_artifact: checkpoint=$checkpoint name=command_status required=true"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-responsiveness-${checkpoint}" "  evidence_artifact: checkpoint=$checkpoint name=responsiveness_probe required=true"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-responsiveness-schema-${checkpoint}" "schema=$(measurement_responsiveness_probe_schema) fields=$(measurement_required_responsiveness_probe_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-summary-${checkpoint}" "  evidence_artifact: checkpoint=$checkpoint name=measurement_summary required=true"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-summary-freshness-${checkpoint}" "freshness_schema=$(measurement_evidence_freshness_schema) freshness_fields=$(measurement_required_evidence_freshness_fields)"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-pareas-source-${checkpoint}" "  evidence_artifact: checkpoint=$checkpoint name=pareas_source required=false"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-pareas-source-sha256-${checkpoint}" "  evidence_artifact: checkpoint=$checkpoint name=pareas_source_sha256 required=false"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-pareas-source-sha256-input-${checkpoint}" "name=pareas_source_sha256 required=false path="
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-pareas-binary-sha256-${checkpoint}" "  evidence_artifact: checkpoint=$checkpoint name=pareas_binary_sha256 required=false"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-pareas-binary-sha256-stale-check-${checkpoint}" "stale_check=pareas_binary_sha256_matches_pareas_binary"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-pareas-output-${checkpoint}" "  evidence_artifact: checkpoint=$checkpoint name=pareas_output required=false"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-pareas-output-status-artifact-${checkpoint}" "producer=pareas_wrapped_command_${checkpoint}l status_field=pareas_exit_status status_artifact=command_status"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-pareas-stdout-${checkpoint}" "  evidence_artifact: checkpoint=$checkpoint name=pareas_stdout required=false"
    verify_measurement_checkpoint_contains "$plan" "$checkpoint" "evidence-pareas-stdout-claim-fields-${checkpoint}" "claim_fields=pareas_wall_elapsed_ms,lanius_pareas_wall_ratio"
    verify_measurement_plan_contains "$plan" "source-replay-command-${checkpoint}" "source_replay_command_${checkpoint}l ="
    verify_measurement_plan_contains "$plan" "source-replay-output-${checkpoint}" "source_replay_stdout_redirect_${checkpoint}l:"
    verify_measurement_plan_contains "$plan" "source-sha256-command-${checkpoint}" "source_sha256_command_${checkpoint}l ="
    verify_measurement_plan_contains "$plan" "source-sha256-output-${checkpoint}" "source_sha256_stdout_redirect_${checkpoint}l:"
    verify_measurement_plan_contains "$plan" "bench-sha256-command-${checkpoint}" "bench_sha256_command_${checkpoint}l ="
    verify_measurement_plan_contains "$plan" "bench-sha256-output-${checkpoint}" "bench_sha256_stdout_redirect_${checkpoint}l:"
    verify_measurement_plan_contains "$plan" "lanius-command-${checkpoint}" "lanius_command_${checkpoint}l ="
    verify_measurement_plan_contains "$plan" "lanius-wrapped-command-${checkpoint}" "lanius_wrapped_command_${checkpoint}l ="
    verify_measurement_plan_contains "$plan" "lanius-command-status-schema-${checkpoint}" "command_status_schema=lanius.command-status.v1"
    verify_measurement_plan_contains "$plan" "lanius-wall-status-${checkpoint}" "lanius_wall_elapsed_ms=%s"
    verify_measurement_plan_contains "$plan" "lanius-timeout-ms-status-${checkpoint}" "timeout_ms=%s"
    verify_measurement_plan_contains "$plan" "lanius-source-status-${checkpoint}" "source=%s"
    verify_measurement_plan_contains "$plan" "lanius-phase-status-${checkpoint}" "phase=%s"
    verify_measurement_plan_contains "$plan" "lanius-target-status-${checkpoint}" "target=%s"
    verify_measurement_plan_contains "$plan" "responsiveness-command-${checkpoint}" "responsiveness_probe_command_${checkpoint}l ="
    verify_measurement_plan_contains "$plan" "machine-responsive-status-${checkpoint}" "machine_responsive_after=%s"
    verify_measurement_plan_contains "$plan" "responsiveness-output-${checkpoint}" "responsiveness_probe_stdout_redirect_${checkpoint}l:"
    verify_measurement_plan_contains "$plan" "lanius-stdout-${checkpoint}" "lanius_stdout_redirect_${checkpoint}l:"
    verify_measurement_plan_contains "$plan" "readback-command-${checkpoint}" "readback_trace_summary_command_${checkpoint}l ="
    verify_measurement_plan_contains "$plan" "readback-output-${checkpoint}" "readback_trace_summary_stdout_redirect_${checkpoint}l:"
    verify_measurement_plan_contains "$plan" "hardware-command-${checkpoint}" "hardware_identity_command_${checkpoint}l ="
    verify_measurement_plan_contains "$plan" "hardware-schema-output-${checkpoint}" "hardware_identity_schema=lanius.hardware-identity.v1"
    verify_measurement_plan_contains "$plan" "hardware-nvidia-status-output-${checkpoint}" "nvidia_smi_status=unavailable"
    verify_measurement_plan_contains "$plan" "hardware-output-${checkpoint}" "hardware_identity_stdout_redirect_${checkpoint}l:"
    verify_measurement_plan_contains "$plan" "command-env-command-${checkpoint}" "command_environment_command_${checkpoint}l ="
    verify_measurement_plan_contains "$plan" "command-env-schema-output-${checkpoint}" "command_environment_schema=lanius.command-environment.v1"
    verify_measurement_plan_contains "$plan" "command-env-source-output-${checkpoint}" "source=%s"
    verify_measurement_plan_contains "$plan" "command-env-target-output-${checkpoint}" "target=%s"
    verify_measurement_plan_contains "$plan" "command-env-pass-contract-loop-status-${checkpoint}" "pass_contract_loop_status=%s"
    verify_measurement_plan_contains "$plan" "command-env-pass-contract-fallback-status-${checkpoint}" "pass_contract_fallback_status=%s"
    verify_measurement_plan_contains "$plan" "command-env-pass-contract-claim-status-${checkpoint}" "pass_contract_claim_status=%s"
    verify_measurement_plan_contains "$plan" "command-env-pass-contract-readiness-status-${checkpoint}" "pass_contract_readiness_status=%s"
    verify_measurement_plan_contains "$plan" "command-env-output-${checkpoint}" "command_environment_stdout_redirect_${checkpoint}l:"
    verify_measurement_plan_contains "$plan" "vram-command-${checkpoint}" "nvidia_smi_command_${checkpoint}l"
    verify_measurement_plan_contains "$plan" "vram-output-${checkpoint}" "nvidia_smi_stdout_redirect_${checkpoint}l:"
    verify_measurement_plan_contains "$plan" "vram-wrapped-command-${checkpoint}" "nvidia_smi_wrapped_command_${checkpoint}l"
    verify_measurement_plan_contains "$plan" "pareas-source-command-${checkpoint}" "pareas_source_command_${checkpoint}l"
    verify_measurement_plan_contains "$plan" "pareas-source-output-${checkpoint}" "pareas_source_stdout_redirect_${checkpoint}l:"
    verify_measurement_plan_contains "$plan" "pareas-source-sha256-command-${checkpoint}" "pareas_source_sha256_command_${checkpoint}l"
    verify_measurement_plan_contains "$plan" "pareas-source-sha256-output-${checkpoint}" "pareas_source_sha256_stdout_redirect_${checkpoint}l:"
    verify_measurement_plan_contains "$plan" "pareas-binary-sha256-command-${checkpoint}" "pareas_binary_sha256_command_${checkpoint}l"
    verify_measurement_plan_contains "$plan" "pareas-binary-sha256-output-${checkpoint}" "pareas_binary_sha256_stdout_redirect_${checkpoint}l:"
    verify_measurement_plan_contains "$plan" "pareas-command-${checkpoint}" "pareas_command_${checkpoint}l"
    verify_measurement_plan_contains "$plan" "pareas-output-${checkpoint}" "pareas_stdout_redirect_${checkpoint}l:"
    verify_measurement_plan_contains "$plan" "pareas-wrapped-command-${checkpoint}" "pareas_wrapped_command_${checkpoint}l"
    verify_measurement_plan_contains "$plan" "pareas-wall-status-${checkpoint}" "pareas_wall_elapsed_ms=%s"
    verify_measurement_plan_contains "$plan" "measurement-summary-command-${checkpoint}" "measurement_summary_command_${checkpoint}l ="
    verify_measurement_plan_contains "$plan" "summary-provenance-${checkpoint}" "evidence_provenance=local-run"
    verify_measurement_plan_contains "$plan" "summary-evidence-policy-${checkpoint}" "measurement_evidence_policy=local-artifacts-only"
    verify_measurement_plan_contains "$plan" "summary-paper-numbers-${checkpoint}" "paper_numbers_accepted=false"
    verify_measurement_plan_contains "$plan" "summary-comparison-baseline-policy-${checkpoint}" "comparison_baseline_policy=local-pareas-artifacts-only"
    verify_measurement_plan_contains "$plan" "summary-freshness-policy-${checkpoint}" "freshness_policy=hash-and-checkpoint-field-match"
    verify_measurement_plan_contains "$plan" "summary-timing-policy-${checkpoint}" "measurement_timing_policy=%s"
    verify_measurement_plan_contains "$plan" "summary-cold-start-policy-${checkpoint}" "cold_start_policy=%s"
    verify_measurement_plan_contains "$plan" "summary-compile-latency-claim-source-${checkpoint}" "compile_latency_claim_source=%s"
    verify_measurement_plan_contains "$plan" "summary-runtime-validation-policy-${checkpoint}" "runtime_validation_policy=%s"
    verify_measurement_plan_contains "$plan" "summary-claim-provenance-schema-${checkpoint}" "claim_provenance_schema=%s"
    verify_measurement_plan_contains "$plan" "summary-baseline-separation-schema-${checkpoint}" "baseline_separation_schema=%s"
    verify_measurement_plan_contains "$plan" "summary-paper-baseline-policy-${checkpoint}" "paper_baseline_policy=%s"
    verify_measurement_plan_contains "$plan" "summary-paper-baseline-numbers-status-${checkpoint}" "paper_baseline_numbers_status=%s"
    verify_measurement_plan_contains "$plan" "summary-local-evidence-status-policy-${checkpoint}" "local_evidence_status_policy=%s"
    verify_measurement_plan_contains "$plan" "summary-local-performance-claim-policy-${checkpoint}" "local_performance_claim_policy=%s"
    verify_measurement_plan_contains "$plan" "summary-local-performance-claim-source-${checkpoint}" "local_performance_claim_source=%s"
    verify_measurement_plan_contains "$plan" "summary-local-performance-claim-status-${checkpoint}" "local_performance_claim_status=%s"
    verify_measurement_plan_contains "$plan" "summary-local-performance-claim-blockers-${checkpoint}" "local_performance_claim_blockers=%s"
    verify_measurement_plan_contains "$plan" "summary-local-vram-claim-source-${checkpoint}" "local_vram_claim_source=%s"
    verify_measurement_plan_contains "$plan" "summary-local-pareas-claim-source-${checkpoint}" "local_pareas_claim_source=%s"
    verify_measurement_plan_contains "$plan" "summary-scaling-claim-policy-${checkpoint}" "scaling_claim_policy=%s"
    verify_measurement_plan_contains "$plan" "summary-scaling-claim-source-${checkpoint}" "scaling_claim_source=%s"
    verify_measurement_plan_contains "$plan" "summary-scaling-claim-status-${checkpoint}" "scaling_claim_status=%s"
    verify_measurement_plan_contains "$plan" "summary-scaling-claim-blockers-${checkpoint}" "scaling_claim_blockers=%s"
    verify_measurement_plan_contains "$plan" "summary-paper-pass-order-schema-${checkpoint}" "paper_pass_order_schema=%s"
    verify_measurement_plan_contains "$plan" "summary-paper-pass-order-source-${checkpoint}" "paper_pass_order_source=%s"
    verify_measurement_plan_contains "$plan" "summary-paper-pass-order-${checkpoint}" "paper_pass_order=%s"
    verify_measurement_plan_contains "$plan" "summary-paper-pass-alignment-policy-${checkpoint}" "paper_pass_alignment_policy=%s"
    verify_measurement_plan_contains "$plan" "summary-paper-pass-alignment-status-${checkpoint}" "paper_pass_alignment_status=%s"
    verify_measurement_plan_contains "$plan" "summary-paper-pass-alignment-blockers-${checkpoint}" "paper_pass_alignment_blockers=%s"
    verify_measurement_plan_contains "$plan" "summary-parallel-pass-contract-schema-${checkpoint}" "parallel_pass_contract_schema=%s"
    verify_measurement_plan_contains "$plan" "summary-parallel-pass-contract-policy-${checkpoint}" "parallel_pass_contract_policy=%s"
    verify_measurement_plan_contains "$plan" "summary-parallel-pass-contract-groups-${checkpoint}" "parallel_pass_contract_groups=%s"
    verify_measurement_plan_contains "$plan" "summary-parallel-pass-contract-order-policy-${checkpoint}" "parallel_pass_contract_order_policy=%s"
    verify_measurement_plan_contains "$plan" "summary-parallel-pass-contract-execution-order-${checkpoint}" "parallel_pass_contract_execution_order=%s"
    verify_measurement_plan_contains "$plan" "summary-pass-contract-status-schema-${checkpoint}" "pass_contract_status_schema=%s"
    verify_measurement_plan_contains "$plan" "summary-pass-contract-loop-policy-${checkpoint}" "pass_contract_loop_policy=%s"
    verify_measurement_plan_contains "$plan" "summary-pass-contract-loop-status-${checkpoint}" "pass_contract_loop_status=%s"
    verify_measurement_plan_contains "$plan" "summary-pass-contract-fallback-status-${checkpoint}" "pass_contract_fallback_status=%s"
    verify_measurement_plan_contains "$plan" "summary-pass-contract-claim-status-${checkpoint}" "pass_contract_claim_status=%s"
    verify_measurement_plan_contains "$plan" "summary-pass-contract-claim-blockers-${checkpoint}" "pass_contract_claim_blockers=%s"
    verify_measurement_plan_contains "$plan" "summary-pass-contract-readiness-status-${checkpoint}" "pass_contract_readiness_status=%s"
    verify_measurement_plan_contains "$plan" "summary-timeout-provenance-schema-${checkpoint}" "timeout_provenance_schema=%s"
    verify_measurement_plan_contains "$plan" "summary-timeout-scope-${checkpoint}" "timeout_scope=%s"
    verify_measurement_plan_contains "$plan" "summary-timeout-source-${checkpoint}" "timeout_source=%s"
    verify_measurement_plan_contains "$plan" "summary-timeout-enforced-by-${checkpoint}" "timeout_enforced_by=%s"
    verify_measurement_plan_contains "$plan" "summary-timeout-exit-code-${checkpoint}" "timeout_exit_code=%s"
    verify_measurement_plan_contains "$plan" "summary-timeout-exit-code-means-timed-out-${checkpoint}" "timeout_exit_code_means_timed_out=%s"
    verify_measurement_plan_contains "$plan" "summary-source-control-policy-${checkpoint}" "source_control_policy=%s"
    verify_measurement_plan_contains "$plan" "summary-source-control-state-${checkpoint}" "source_control_state=%s"
    verify_measurement_plan_contains "$plan" "summary-source-control-revision-${checkpoint}" "source_control_revision=%s"
    verify_measurement_plan_contains "$plan" "summary-repeatability-policy-${checkpoint}" "repeatability_policy=%s"
    verify_measurement_plan_contains "$plan" "summary-minimum-iterations-for-claim-${checkpoint}" "minimum_iterations_for_claim=%s"
    verify_measurement_plan_contains "$plan" "summary-repeatability-status-${checkpoint}" "repeatability_status=%s"
    verify_measurement_plan_contains "$plan" "summary-repeatability-blocker-${checkpoint}" 'repeatability:${repeatability_status}:iterations_'
    verify_measurement_plan_contains "$plan" "summary-artifacts-complete-${checkpoint}" "required_artifacts_complete=%s"
    verify_measurement_plan_contains "$plan" "summary-missing-artifacts-${checkpoint}" "missing_required_artifacts=%s"
    verify_measurement_plan_contains "$plan" "summary-evidence-status-schema-${checkpoint}" "evidence_status_schema=$(measurement_evidence_status_schema)"
    verify_measurement_plan_contains "$plan" "summary-performance-status-${checkpoint}" "local_performance_evidence_status=%s"
    verify_measurement_plan_contains "$plan" "summary-performance-claim-status-${checkpoint}" "local_performance_claim_status=%s"
    verify_measurement_plan_contains "$plan" "summary-performance-claim-blockers-${checkpoint}" "local_performance_claim_blockers=%s"
    verify_measurement_plan_contains "$plan" "summary-readback-status-${checkpoint}" "local_readback_evidence_status=%s"
    verify_measurement_plan_contains "$plan" "summary-vram-status-${checkpoint}" "local_vram_evidence_status=%s"
    verify_measurement_plan_contains "$plan" "summary-nvidia-smi-status-${checkpoint}" "nvidia_smi_exit_status=%s"
    verify_measurement_plan_contains "$plan" "summary-pareas-status-${checkpoint}" "local_pareas_evidence_status=%s"
    verify_measurement_plan_contains "$plan" "summary-scaling-status-${checkpoint}" "scaling_claim_status=%s"
    verify_measurement_plan_contains "$plan" "summary-scaling-blockers-${checkpoint}" "scaling_claim_blockers=%s"
    verify_measurement_plan_contains "$plan" "summary-production-complete-${checkpoint}" "production_readiness_evidence_complete=%s"
    verify_measurement_plan_contains "$plan" "summary-production-blockers-${checkpoint}" "production_readiness_blockers=%s"
    verify_measurement_plan_contains "$plan" "summary-source-control-blocker-${checkpoint}" 'source_control:${source_control_state}'
    verify_measurement_plan_contains "$plan" "summary-freshness-schema-${checkpoint}" "evidence_freshness_schema=$(measurement_evidence_freshness_schema)"
    verify_measurement_plan_contains "$plan" "summary-freshness-status-${checkpoint}" "evidence_freshness_status=%s"
    verify_measurement_plan_contains "$plan" "summary-stale-artifacts-${checkpoint}" "stale_artifacts=%s"
    verify_measurement_plan_contains "$plan" "summary-stale-checks-${checkpoint}" "stale_artifact_checks=%s"
    verify_measurement_plan_contains "$plan" "summary-source-control-local-revision-stale-check-${checkpoint}" "source_control_revision_is_local_git_commit"
    verify_measurement_plan_contains "$plan" "summary-source-replay-line-count-stale-check-${checkpoint}" "source_replay_line_count_covers_checkpoint"
    verify_measurement_plan_contains "$plan" "summary-resource-usage-stale-check-${checkpoint}" "resource_usage_command_matches_checkpoint"
    verify_measurement_plan_contains "$plan" "summary-readback-span-stale-check-${checkpoint}" "readback_summary_span_metrics_are_consistent"
    verify_measurement_plan_contains "$plan" "summary-quantitative-field-stale-check-${checkpoint}" "quantitative_artifact_fields_are_numeric"
    verify_measurement_plan_contains "$plan" "summary-vram-status-freshness-${checkpoint}" "vram_status_matches_checkpoint"
    verify_measurement_plan_contains "$plan" "summary-vram-header-stale-check-${checkpoint}" "vram_csv_header_matches_required_columns"
    verify_measurement_plan_contains "$plan" "summary-pareas-status-freshness-${checkpoint}" "pareas_status_matches_checkpoint"
    verify_measurement_plan_contains "$plan" "summary-claim-readiness-schema-${checkpoint}" "claim_readiness_schema=lanius.measurement-claim-readiness.v1"
    verify_measurement_plan_contains "$plan" "summary-claim-readiness-policy-${checkpoint}" "claim_readiness_policy=complete-local-evidence-only"
    verify_measurement_plan_contains "$plan" "summary-claim-readiness-required-evidence-${checkpoint}" "claim_readiness_required_evidence_classes=%s"
    verify_measurement_plan_contains "$plan" "summary-claim-readiness-required-statuses-${checkpoint}" "claim_readiness_required_statuses=%s"
    verify_measurement_plan_contains "$plan" "summary-claim-readiness-status-${checkpoint}" "claim_readiness_status=%s"
    verify_measurement_plan_contains "$plan" "summary-claimable-measurement-claims-${checkpoint}" "claimable_measurement_claims=%s"
    verify_measurement_plan_contains "$plan" "summary-claim-readiness-blockers-${checkpoint}" "claim_readiness_blockers=%s"
    verify_measurement_plan_contains "$plan" "summary-claim-scope-policy-${checkpoint}" "claim_scope_policy=%s"
    verify_measurement_plan_contains "$plan" "summary-claim-scope-key-${checkpoint}" "claim_scope_key=%s"
    verify_measurement_plan_contains "$plan" "summary-claim-scope-key-source-control-state-${checkpoint}" "source_control_state:"
    verify_measurement_plan_contains "$plan" "summary-claim-scope-key-source-control-revision-${checkpoint}" "source_control_revision:"
    verify_measurement_plan_contains "$plan" "summary-claim-scope-key-pass-order-${checkpoint}" "parallel_pass_contract_execution_order:"
    verify_measurement_plan_contains "$plan" "summary-claim-scope-key-repeatability-status-${checkpoint}" "repeatability_status:"
    verify_measurement_plan_contains "$plan" "summary-status-identity-stale-check-${checkpoint}" "command_status_schema_checkpoint_timing_policy_timeout_provenance_and_paths"
    verify_measurement_plan_contains "$plan" "summary-command-env-stale-check-${checkpoint}" "command_environment_schema_checkpoint_timing_policy_timeout_provenance_tool_versions_claim_provenance_baseline_separation_paper_pass_order_pass_contracts_loop_status_and_readiness"
    verify_measurement_plan_contains "$plan" "summary-paper-baseline-stale-check-${checkpoint}" "paper_baseline_and_local_evidence_separation_match_checkpoint"
    verify_measurement_plan_contains "$plan" "summary-paper-pass-order-stale-check-${checkpoint}" "paper_pass_order_matches_checkpoint"
    verify_measurement_plan_contains "$plan" "summary-paper-pass-alignment-stale-check-${checkpoint}" "paper_pass_alignment_status_matches_checkpoint"
    verify_measurement_plan_contains "$plan" "summary-claim-provenance-stale-check-${checkpoint}" "claim_provenance_fields_match_checkpoint"
    verify_measurement_plan_contains "$plan" "summary-pass-contract-stale-check-${checkpoint}" "parallel_pass_contracts_match_checkpoint"
    verify_measurement_plan_contains "$plan" "summary-pass-order-stale-check-${checkpoint}" "parallel_pass_contract_order_matches_checkpoint"
    verify_measurement_plan_contains "$plan" "summary-pass-loop-status-stale-check-${checkpoint}" "pass_contract_loop_fallback_and_readiness_status_match_checkpoint"
    verify_measurement_plan_contains "$plan" "summary-timeout-ms-${checkpoint}" "timeout_ms=%s"
    verify_measurement_plan_contains "$plan" "summary-resource-usage-status-${checkpoint}" "resource_usage_status=%s"
    verify_measurement_plan_contains "$plan" "summary-source-replay-line-count-${checkpoint}" "source_replay_line_count=%s"
    verify_measurement_plan_contains "$plan" "summary-throughput-${checkpoint}" "throughput_lines_per_second=%s"
    verify_measurement_plan_contains "$plan" "summary-hardware-identity-sha256-${checkpoint}" "hardware_identity_sha256=%s"
    verify_measurement_plan_contains "$plan" "summary-command-env-sha256-${checkpoint}" "command_environment_sha256=%s"
    verify_measurement_plan_contains "$plan" "summary-pareas-source-sha256-${checkpoint}" "pareas_source_sha256=%s"
    verify_measurement_plan_contains "$plan" "summary-pareas-binary-sha256-${checkpoint}" "pareas_binary_sha256=%s"
    verify_measurement_plan_contains "$plan" "summary-pareas-ratio-${checkpoint}" "lanius_pareas_wall_ratio=%s"
  done
}

language_slice_error() {
  echo "acceptance language-slice error: $*" >&2
  language_slice_errors=$((language_slice_errors + 1))
}

require_language_slice_evidence_count() {
  local label="$1"
  local count="$2"
  if [[ "$count" -eq 0 ]]; then
    language_slice_error "language-slice inventory has no $label evidence"
  fi
}

record_language_slice_parser_type_relation_evidence() {
  local kind="$1"
  local id="$2"
  local status="$3"
  local evidence_scope="$4"
  local evidence_test="$5"
  local evidence_contract="$6"

  case "$kind/$id" in
    parser-hir/array-literal-local-context)
      if [[ "$status" != "supported" && "$status" != "bounded" ]]; then
        language_slice_error "$kind/$id relation evidence must be supported or bounded"
      elif [[ "$evidence_scope" == "-" || "$evidence_test" == "-" || "$evidence_contract" != "semantic-contract" ]]; then
        language_slice_error "$kind/$id must cite behavior-facing semantic-contract evidence"
      else
        language_slice_array_lit_context_evidence=1
      fi
      ;;
    parser-hir/struct-literal-field-selection-context)
      if [[ "$status" != "supported" && "$status" != "bounded" ]]; then
        language_slice_error "$kind/$id relation evidence must be supported or bounded"
      elif [[ "$evidence_scope" == "-" || "$evidence_test" == "-" || "$evidence_contract" != "semantic-contract" ]]; then
        language_slice_error "$kind/$id must cite behavior-facing semantic-contract evidence"
      else
        language_slice_struct_lit_context_evidence=1
      fi
      ;;
    parser-hir/expression-result-root-records)
      if [[ "$status" != "supported" && "$status" != "bounded" ]]; then
        language_slice_error "$kind/$id relation evidence must be supported or bounded"
      elif [[ "$evidence_scope" == "-" || "$evidence_test" == "-" || "$evidence_contract" != "record-invariant" ]]; then
        language_slice_error "$kind/$id must cite behavior-facing record-invariant evidence"
      else
        language_slice_expr_result_root_evidence=1
      fi
      ;;
    parser-hir/trait-and-impl-method-declaration-records)
      if [[ "$status" != "supported" && "$status" != "bounded" ]]; then
        language_slice_error "$kind/$id method-owner evidence must be supported or bounded"
      elif [[ "$evidence_scope" == "-" || "$evidence_test" == "-" || "$evidence_contract" != "record-invariant" ]]; then
        language_slice_error "$kind/$id must cite behavior-facing method-owner record evidence"
      else
        language_slice_trait_or_inherent_method_owner_evidence=1
      fi
      ;;
    parser-hir/trait-impl-method-declaration-records)
      if [[ "$status" != "supported" && "$status" != "bounded" ]]; then
        language_slice_error "$kind/$id trait-impl method-owner evidence must be supported or bounded"
      elif [[ "$evidence_scope" == "-" || "$evidence_test" == "-" || "$evidence_contract" != "record-invariant" ]]; then
        language_slice_error "$kind/$id must cite behavior-facing trait-impl method-owner record evidence"
      else
        language_slice_trait_impl_method_owner_evidence=1
      fi
      ;;
    parser-hir/method-signature-status-records)
      if [[ "$status" == "planned" \
        && "$evidence_scope" == "-" \
        && "$evidence_test" == "-" \
        && "$evidence_contract" == "-" ]]; then
        language_slice_method_signature_status_hook=1
      elif [[ "$status" != "supported" && "$status" != "bounded" ]]; then
        language_slice_error "$kind/$id method-signature status evidence must be supported, bounded, or a planned no-evidence hook"
      elif [[ "$evidence_scope" == "-" || "$evidence_test" == "-" ]]; then
        language_slice_error "$kind/$id must cite behavior-facing method-signature status evidence"
      else
        case "$evidence_contract" in
          record-invariant|semantic-contract|fail-closed-diagnostic)
            language_slice_method_signature_status_hook=1
            language_slice_method_signature_status_evidence=1
            ;;
          *)
            language_slice_error "$kind/$id must cite record-invariant, semantic-contract, or fail-closed-diagnostic evidence"
            ;;
        esac
      fi
      ;;
    parser-hir/contextual-nearest-statement-records)
      if [[ "$status" != "supported" && "$status" != "bounded" ]]; then
        language_slice_error "$kind/$id relation evidence must be supported or bounded"
      elif [[ "$evidence_scope" == "-" || "$evidence_test" == "-" || "$evidence_contract" != "record-invariant" ]]; then
        language_slice_error "$kind/$id must cite behavior-facing record-invariant evidence"
      else
        language_slice_nearest_stmt_context_evidence=1
      fi
      ;;
    parser-hir/contextual-nearest-block-control-records)
      if [[ "$status" != "supported" && "$status" != "bounded" ]]; then
        language_slice_error "$kind/$id relation evidence must be supported or bounded"
      elif [[ "$evidence_scope" == "-" || "$evidence_test" == "-" || "$evidence_contract" != "record-invariant" ]]; then
        language_slice_error "$kind/$id must cite behavior-facing record-invariant evidence"
      else
        language_slice_nearest_block_control_context_evidence=1
      fi
      ;;
    semantics/generic-enum-constructor-context)
      if [[ "$status" != "supported" && "$status" != "bounded" ]]; then
        language_slice_error "$kind/$id relation evidence must be supported or bounded"
      elif [[ "$evidence_scope" == "-" || "$evidence_test" == "-" || "$evidence_contract" != "semantic-contract" ]]; then
        language_slice_error "$kind/$id must cite behavior-facing semantic-contract evidence"
      else
        language_slice_call_context_evidence=1
      fi
      ;;
  esac
}

record_language_slice_pass_order_evidence() {
  local kind="$1"
  local id="$2"
  local status="$3"
  local evidence_scope="$4"
  local evidence_test="$5"
  local evidence_contract="$6"

  case "$kind/$id" in
    architecture/pass-order-record-boundary-sequence)
      if [[ "$status" != "bounded" ]]; then
        language_slice_error "$kind/$id pass-order evidence must stay bounded until the record-boundary sequence is fully claimable"
      elif [[ "$evidence_scope" == "-" || "$evidence_test" == "-" || "$evidence_contract" != "measurement-scaffold" ]]; then
        language_slice_error "$kind/$id must cite no-run measurement-scaffold evidence"
      else
        language_slice_pass_order_evidence=1
      fi
      ;;
    architecture/wasm-record-pass-order|architecture/linking-gpu-pass-order)
      if [[ "$status" != "planned" \
        || "$evidence_scope" != "-" \
        || "$evidence_test" != "-" \
        || "$evidence_contract" != "-" ]]; then
        language_slice_error "$kind/$id must remain a planned gap until behavior, record, artifact, or measurement-scaffold evidence exists"
      else
        language_slice_planned_pass_order_gaps=$((language_slice_planned_pass_order_gaps + 1))
      fi
      ;;
  esac
}

record_language_slice_performance_claim_guard() {
  local kind="$1"
  local id="$2"
  local status="$3"
  local evidence_scope="$4"
  local evidence_test="$5"
  local evidence_contract="$6"
  local notes="$7"

  if [[ "$kind" != "performance" ]]; then
    return
  fi

  local valid=1
  if [[ "$status" != "bounded" ]]; then
    language_slice_error "$kind/$id performance evidence must stay bounded until local measurement artifacts and pass contracts are claimable"
    valid=0
  fi
  if [[ "$evidence_scope" != "integration:generated_10k_gates" || "$evidence_contract" != "measurement-scaffold" ]]; then
    language_slice_error "$kind/$id performance evidence must cite the no-run generated measurement scaffold"
    valid=0
  fi
  case "$evidence_test" in
    compiler_acceptance_readiness_check_plan_validates_measurement_inventory|compiler_acceptance_measurement_plan_publishes_checkpoint_evidence_manifest|compiler_acceptance_measurement_plan_publishes_claim_provenance_boundaries|compiler_acceptance_measurement_plan_publishes_parallel_pass_evidence_classes)
      ;;
    *)
      language_slice_error "$kind/$id performance evidence must cite a readiness/measurement-scaffold contract test"
      valid=0
      ;;
  esac
  if [[ "$notes" != *"no-run"* ]]; then
    language_slice_error "$kind/$id performance evidence must explicitly remain no-run"
    valid=0
  fi
  if [[ "$notes" != *"local_performance_claim_status=blocked"* || "$notes" != *"scaling_claim_status=blocked"* || "$notes" != *"claim_readiness_status=not-claimable"* ]]; then
    language_slice_error "$kind/$id performance evidence must carry blocked local-performance, scaling, and claim-readiness statuses"
    valid=0
  fi
  case "$notes" in
    *"paper_numbers_accepted=true"*|*"paper numbers accepted"*|*"local_performance_claim_status=claimable"*|*"scaling_claim_status=claimable"*|*"claim_readiness_status=claimable"*)
      language_slice_error "$kind/$id performance evidence makes a claimable or paper-backed performance assertion before the scaffold is claimable"
      valid=0
      ;;
  esac

  if [[ "$valid" -eq 1 ]]; then
    language_slice_performance_claim_guards=$((language_slice_performance_claim_guards + 1))
  fi
}

language_slice_required_gate_is_valid() {
  local gate="$1"
  local status="$2"
  local evidence_scope="$3"
  local evidence_test="$4"
  local evidence_contract="$5"
  local expected_scope="$6"
  local expected_test="$7"
  local expected_contract="$8"

  if [[ "$status" != "supported" && "$status" != "bounded" ]]; then
    language_slice_error "$gate must be supported or bounded while it is external readiness evidence"
    return 1
  fi
  if [[ "$evidence_scope" != "$expected_scope" \
    || "$evidence_test" != "$expected_test" \
    || "$evidence_contract" != "$expected_contract" ]]; then
    language_slice_error "$gate must cite $expected_scope/$expected_test as $expected_contract evidence"
    return 1
  fi
  return 0
}

record_language_slice_external_tooling_gate() {
  local kind="$1"
  local id="$2"
  local status="$3"
  local evidence_scope="$4"
  local evidence_test="$5"
  local evidence_contract="$6"

  case "$kind/$id" in
    diagnostics/registered-codes)
      if language_slice_required_gate_is_valid "$kind/$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract" \
        "lib:laniusc" "diagnostic_creation_rejects_unregistered_codes_in_debug_builds" "artifact-contract"; then
        language_slice_stable_code_registry_gate=1
        language_slice_external_tooling_gate_evidence=$((language_slice_external_tooling_gate_evidence + 1))
      fi
      ;;
    diagnostics/registry-json)
      if language_slice_required_gate_is_valid "$kind/$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract" \
        "integration:cli_diagnostics" "diagnostic_registry_json_contains_code_metadata_categories_and_unsupported_boundaries" "artifact-contract"; then
        language_slice_diagnostic_registry_json_gate=1
        language_slice_external_tooling_gate_evidence=$((language_slice_external_tooling_gate_evidence + 1))
      fi
      ;;
    tooling/diagnostic-registry-cli)
      if language_slice_required_gate_is_valid "$kind/$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract" \
        "integration:cli_diagnostics" "cli_diagnostics_registry_prints_combined_registry_json_without_compiling_source" "artifact-contract"; then
        language_slice_diagnostic_registry_cli_gate=1
        language_slice_external_tooling_gate_evidence=$((language_slice_external_tooling_gate_evidence + 1))
      fi
      ;;
    tooling/diagnostic-categories-cli)
      if language_slice_required_gate_is_valid "$kind/$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract" \
        "integration:cli_diagnostics" "cli_diagnostics_categories_groups_codes_by_stable_category_without_compiling_source" "public-boundary"; then
        language_slice_diagnostic_categories_cli_gate=1
        language_slice_external_tooling_gate_evidence=$((language_slice_external_tooling_gate_evidence + 1))
      fi
      ;;
    tooling/diagnostic-explain-cli)
      if language_slice_required_gate_is_valid "$kind/$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract" \
        "integration:cli_diagnostics" "cli_diagnostics_explain_prints_single_code_json_without_compiling_source" "public-boundary"; then
        language_slice_diagnostic_explain_cli_gate=1
        language_slice_external_tooling_gate_evidence=$((language_slice_external_tooling_gate_evidence + 1))
      fi
      ;;
    tooling/diagnostic-explain-unknown-cli)
      if language_slice_required_gate_is_valid "$kind/$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract" \
        "integration:cli_diagnostics" "cli_diagnostics_explain_reports_unknown_code_as_machine_readable_result" "public-boundary"; then
        language_slice_diagnostic_explain_unknown_cli_gate=1
        language_slice_external_tooling_gate_evidence=$((language_slice_external_tooling_gate_evidence + 1))
      fi
      ;;
    tooling/diagnostic-formats-cli)
      if language_slice_required_gate_is_valid "$kind/$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract" \
        "integration:cli_diagnostics" "cli_diagnostics_formats_prints_machine_readable_contract_without_compiling_source" "public-boundary"; then
        language_slice_diagnostic_formats_cli_gate=1
        language_slice_external_tooling_gate_evidence=$((language_slice_external_tooling_gate_evidence + 1))
      fi
      ;;
    tooling/formatter)
      if language_slice_required_gate_is_valid "$kind/$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract" \
        "integration:formatter" "formatter_is_idempotent_for_alpha_slice" "public-boundary"; then
        language_slice_formatter_library_gate=1
        language_slice_external_tooling_gate_evidence=$((language_slice_external_tooling_gate_evidence + 1))
      fi
      ;;
    tooling/formatter-cli-check)
      if language_slice_required_gate_is_valid "$kind/$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract" \
        "integration:cli_formatter" "cli_fmt_check_can_render_json_diagnostic_without_writing" "fail-closed-diagnostic"; then
        language_slice_formatter_cli_check_gate=1
        language_slice_external_tooling_gate_evidence=$((language_slice_external_tooling_gate_evidence + 1))
      fi
      ;;
    tooling/lsp-capabilities)
      if language_slice_required_gate_is_valid "$kind/$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract" \
        "integration:cli_lsp" "cli_lsp_capabilities_reports_no_run_diagnostic_contract" "public-boundary"; then
        language_slice_lsp_capabilities_gate=1
        language_slice_external_tooling_gate_evidence=$((language_slice_external_tooling_gate_evidence + 1))
      fi
      ;;
    tooling/lsp-stdio-handshake)
      if language_slice_required_gate_is_valid "$kind/$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract" \
        "integration:cli_lsp" "cli_lsp_serve_handles_initialize_shutdown_without_compiling_source" "public-boundary"; then
        language_slice_lsp_stdio_gate=1
        language_slice_external_tooling_gate_evidence=$((language_slice_external_tooling_gate_evidence + 1))
      fi
      ;;
    tooling/lsp-document-diagnostics)
      if language_slice_required_gate_is_valid "$kind/$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract" \
        "integration:cli_lsp" "cli_lsp_serve_returns_document_diagnostics_for_opened_source" "public-boundary"; then
        language_slice_lsp_document_diagnostics_gate=1
        language_slice_external_tooling_gate_evidence=$((language_slice_external_tooling_gate_evidence + 1))
      fi
      ;;
    packages/manifest-source-roots)
      if language_slice_required_gate_is_valid "$kind/$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract" \
        "integration:cli_package_manifest" "cli_package_manifest_compiles_entry_through_source_roots" "public-boundary"; then
        language_slice_package_manifest_cli_gate=1
        language_slice_external_tooling_gate_evidence=$((language_slice_external_tooling_gate_evidence + 1))
      fi
      ;;
    packages/lockfile-source-roots)
      if language_slice_required_gate_is_valid "$kind/$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract" \
        "integration:cli_package_manifest" "cli_package_lockfile_compiles_entry_through_resolved_source_roots" "public-boundary"; then
        language_slice_package_lockfile_cli_gate=1
        language_slice_external_tooling_gate_evidence=$((language_slice_external_tooling_gate_evidence + 1))
      fi
      ;;
    packages/package-lock-command)
      if language_slice_required_gate_is_valid "$kind/$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract" \
        "integration:cli_package_manifest" "cli_package_lock_generates_lockfile_that_existing_compile_path_uses" "public-boundary"; then
        language_slice_package_lock_command_gate=1
        language_slice_external_tooling_gate_evidence=$((language_slice_external_tooling_gate_evidence + 1))
      fi
      ;;
    packages/manifest-metadata-json-diagnostic)
      if language_slice_required_gate_is_valid "$kind/$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract" \
        "integration:cli_package_manifest" "cli_package_manifest_invalid_metadata_can_render_json_without_compiling_source" "fail-closed-diagnostic"; then
        language_slice_package_metadata_diagnostic_gate=1
        language_slice_external_tooling_gate_evidence=$((language_slice_external_tooling_gate_evidence + 1))
      fi
      ;;
  esac
}

require_language_slice_named_gate() {
  local label="$1"
  local value="$2"
  if [[ "$value" -eq 0 ]]; then
    language_slice_error "language-slice inventory is missing required external readiness gate: $label"
  fi
}

verify_language_slice_evidence() {
  local kind="$1"
  local id="$2"
  local status="$3"
  local evidence_scope="$4"
  local evidence_test="$5"
  local evidence_contract="$6"

  case "$status" in
    supported|bounded)
      if [[ "$evidence_scope" == "-" || "$evidence_test" == "-" ]]; then
        language_slice_error "$kind/$id has status '$status' but no evidence test"
        return
      fi
      if ! record_language_slice_evidence_contract "$kind" "$id" "$evidence_contract"; then
        return
      fi
      ;;
    planned|unsupported)
      if [[ "$evidence_scope" == "-" && "$evidence_test" == "-" && "$evidence_contract" == "-" ]]; then
        return
      fi
      if [[ "$evidence_contract" != "-" ]] && ! record_language_slice_evidence_contract "$kind" "$id" "$evidence_contract"; then
        return
      fi
      ;;
  esac

  case "$evidence_scope" in
    integration:*)
      local test_target="${evidence_scope#integration:}"
      record_named_test_reference "language-slice" "$test_target" "$evidence_test" "tests/$test_target.rs"
      ;;
    lib:laniusc)
      record_named_test_reference "language-slice" laniusc "$evidence_test" src tests
      ;;
    bin:*)
      local bin_target="${evidence_scope#bin:}"
      record_named_test_reference "language-slice" "$bin_target" "$evidence_test" src
      ;;
    -)
      language_slice_error "$kind/$id has evidence test '$evidence_test' but no evidence scope"
      ;;
    *)
      language_slice_error "$kind/$id has unsupported evidence scope '$evidence_scope'"
      ;;
  esac
}

record_language_slice_evidence_contract() {
  local kind="$1"
  local id="$2"
  local evidence_contract="$3"

  case "$evidence_contract" in
    public-boundary)
      language_slice_public_boundary_evidence=$((language_slice_public_boundary_evidence + 1))
      ;;
    artifact-contract)
      language_slice_artifact_contract_evidence=$((language_slice_artifact_contract_evidence + 1))
      ;;
    record-invariant)
      language_slice_record_invariant_evidence=$((language_slice_record_invariant_evidence + 1))
      ;;
    semantic-contract)
      language_slice_semantic_contract_evidence=$((language_slice_semantic_contract_evidence + 1))
      ;;
    execution-contract)
      language_slice_execution_contract_evidence=$((language_slice_execution_contract_evidence + 1))
      ;;
    fail-closed-diagnostic)
      language_slice_fail_closed_evidence=$((language_slice_fail_closed_evidence + 1))
      ;;
    measurement-scaffold)
      language_slice_measurement_scaffold_evidence=$((language_slice_measurement_scaffold_evidence + 1))
      ;;
    -)
      language_slice_error "$kind/$id has no behavior-facing evidence contract"
      return 1
      ;;
    *)
      language_slice_error "$kind/$id uses unsupported evidence contract '$evidence_contract'"
      return 1
      ;;
  esac
}

check_language_slice_contract() {
  if [[ "$check_plan" -eq 0 ]]; then
    return
  fi

  case "$tier" in
    readiness|all) ;;
    *) return ;;
  esac

  local path="docs/language_slice_unstable_alpha.tsv"
  if [[ ! -f "$path" ]]; then
    language_slice_error "missing $path"
    return
  fi

  local rows=0
  local line_number=0
  local kind id status evidence_scope evidence_test evidence_contract notes extra
  local -A seen_language_slice_ids=()
  while IFS=$'\t' read -r kind id status evidence_scope evidence_test evidence_contract notes extra || [[ -n "${kind:-}" ]]; do
    line_number=$((line_number + 1))
    case "${kind:-}" in
      ""|\#*) continue ;;
    esac

    plan_checked_commands=$((plan_checked_commands + 1))
    if [[ -n "${extra:-}" ]]; then
      language_slice_error "$path:$line_number has too many tab-separated fields"
      continue
    fi
    if [[ -z "${notes:-}" ]]; then
      language_slice_error "$path:$line_number must have seven tab-separated fields"
      continue
    fi
    if [[ -z "$kind" || -z "$id" || -z "$status" || -z "$evidence_scope" || -z "$evidence_test" || -z "$evidence_contract" ]]; then
      language_slice_error "$path:$line_number has an empty required field"
      continue
    fi
    if [[ -n "${seen_language_slice_ids[$id]:-}" ]]; then
      language_slice_error "$path:$line_number repeats language-slice id '$id'"
      continue
    fi
    seen_language_slice_ids[$id]=1
    case "$status" in
      supported|bounded|planned|unsupported) ;;
      *)
        language_slice_error "$path:$line_number uses unsupported status '$status'"
        continue
        ;;
    esac

    rows=$((rows + 1))
    verify_language_slice_evidence "$kind" "$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract"
    record_language_slice_parser_type_relation_evidence "$kind" "$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract"
    record_language_slice_pass_order_evidence "$kind" "$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract"
    record_language_slice_performance_claim_guard "$kind" "$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract" "$notes"
    record_language_slice_external_tooling_gate "$kind" "$id" "$status" "$evidence_scope" "$evidence_test" "$evidence_contract"
  done <"$path"

  language_slice_method_owner_evidence=$((language_slice_trait_or_inherent_method_owner_evidence + language_slice_trait_impl_method_owner_evidence))
  language_slice_parser_type_relation_evidence=$((language_slice_array_lit_context_evidence + language_slice_struct_lit_context_evidence + language_slice_call_context_evidence + language_slice_expr_result_root_evidence + language_slice_method_owner_evidence + language_slice_method_signature_status_evidence + language_slice_nearest_stmt_context_evidence + language_slice_nearest_block_control_context_evidence))
  language_slice_rows="$rows"
  if [[ "$rows" -eq 0 ]]; then
    language_slice_error "$path has no language-slice rows"
  else
    if [[ "$language_slice_trait_or_inherent_method_owner_evidence" -eq 0 ]]; then
      language_slice_error "$path is missing parser-owned trait/inherent method-owner record evidence"
    fi
    if [[ "$language_slice_trait_impl_method_owner_evidence" -eq 0 ]]; then
      language_slice_error "$path is missing parser-owned trait-impl method-owner record evidence"
    fi
    if [[ "$language_slice_method_signature_status_hook" -eq 0 ]]; then
      language_slice_error "$path is missing the parser-owned method-signature status inventory hook"
    fi
    require_language_slice_evidence_count public-boundary "$language_slice_public_boundary_evidence"
    require_language_slice_evidence_count artifact-contract "$language_slice_artifact_contract_evidence"
    require_language_slice_evidence_count record-invariant "$language_slice_record_invariant_evidence"
    require_language_slice_evidence_count semantic-contract "$language_slice_semantic_contract_evidence"
    require_language_slice_evidence_count execution-contract "$language_slice_execution_contract_evidence"
    require_language_slice_evidence_count fail-closed-diagnostic "$language_slice_fail_closed_evidence"
    require_language_slice_evidence_count measurement-scaffold "$language_slice_measurement_scaffold_evidence"
    require_language_slice_evidence_count parser-type-relation "$language_slice_parser_type_relation_evidence"
    require_language_slice_evidence_count pass-order-record-boundary "$language_slice_pass_order_evidence"
    require_language_slice_evidence_count performance-claim-guard "$language_slice_performance_claim_guards"
    require_language_slice_evidence_count external-tooling-gate "$language_slice_external_tooling_gate_evidence"
    require_language_slice_named_gate "stable diagnostic code registry" "$language_slice_stable_code_registry_gate"
    require_language_slice_named_gate "diagnostic registry JSON" "$language_slice_diagnostic_registry_json_gate"
    require_language_slice_named_gate "diagnostic registry CLI" "$language_slice_diagnostic_registry_cli_gate"
    require_language_slice_named_gate "diagnostic categories CLI" "$language_slice_diagnostic_categories_cli_gate"
    require_language_slice_named_gate "diagnostic explain CLI" "$language_slice_diagnostic_explain_cli_gate"
    require_language_slice_named_gate "diagnostic explain unknown-code CLI" "$language_slice_diagnostic_explain_unknown_cli_gate"
    require_language_slice_named_gate "diagnostic formats CLI" "$language_slice_diagnostic_formats_cli_gate"
    require_language_slice_named_gate "formatter library idempotence" "$language_slice_formatter_library_gate"
    require_language_slice_named_gate "formatter CLI check diagnostic" "$language_slice_formatter_cli_check_gate"
    require_language_slice_named_gate "LSP capabilities" "$language_slice_lsp_capabilities_gate"
    require_language_slice_named_gate "LSP stdio handshake" "$language_slice_lsp_stdio_gate"
    require_language_slice_named_gate "LSP document diagnostics" "$language_slice_lsp_document_diagnostics_gate"
    require_language_slice_named_gate "package manifest CLI compile" "$language_slice_package_manifest_cli_gate"
    require_language_slice_named_gate "package lockfile CLI compile" "$language_slice_package_lockfile_cli_gate"
    require_language_slice_named_gate "package lock command" "$language_slice_package_lock_command_gate"
    require_language_slice_named_gate "package metadata JSON diagnostic" "$language_slice_package_metadata_diagnostic_gate"
    if [[ "$language_slice_planned_pass_order_gaps" -ne 2 ]]; then
      language_slice_error "$path must track the WASM and GPU link/object pass-order gaps as planned rows"
    fi
  fi
  if [[ "$rows" -gt 0 && "$language_slice_errors" -eq 0 ]]; then
    echo "# acceptance language-slice check ok: $rows rows validated with behavior-facing evidence contracts public-boundary=$language_slice_public_boundary_evidence artifact-contract=$language_slice_artifact_contract_evidence record-invariant=$language_slice_record_invariant_evidence semantic-contract=$language_slice_semantic_contract_evidence execution-contract=$language_slice_execution_contract_evidence fail-closed-diagnostic=$language_slice_fail_closed_evidence measurement-scaffold=$language_slice_measurement_scaffold_evidence parser-type-relation=$language_slice_parser_type_relation_evidence pass-order-record-boundary=$language_slice_pass_order_evidence performance-claim-guard=$language_slice_performance_claim_guards external-tooling-gates=$language_slice_external_tooling_gate_evidence planned-pass-order-gaps=$language_slice_planned_pass_order_gaps"
  fi
}

check_acceptance_script_contract() {
  if [[ "$check_plan" -eq 0 ]]; then
    return
  fi

  case "$tier" in
    readiness|all) ;;
    *) return ;;
  esac

  local script_path="${BASH_SOURCE[0]}"
  plan_checked_commands=$((plan_checked_commands + 1))
  if [[ ! -f "$script_path" ]]; then
    echo "acceptance script missing: $script_path" >&2
    plan_missing_commands=$((plan_missing_commands + 1))
  elif [[ ! -x "$script_path" ]]; then
    echo "acceptance script is not executable: $script_path" >&2
    plan_missing_commands=$((plan_missing_commands + 1))
  else
    echo "# acceptance executable check ok: $script_path is executable"
  fi
}

test_discipline_error() {
  echo "acceptance test-discipline error: $*" >&2
  test_discipline_errors=$((test_discipline_errors + 1))
}

check_test_discipline_contract() {
  if [[ "$check_plan" -eq 0 ]]; then
    return
  fi

  case "$tier" in
    readiness|all) ;;
    *) return ;;
  esac

  shopt -s nullglob globstar
  local -a test_paths=(
    tests/*.rs
    tests/**/*.rs
  )
  if [[ "${#test_paths[@]}" -eq 0 ]]; then
    test_discipline_error "no Rust test files found to check"
    return
  fi

  local path
  local checked_test_count=0
  local -A seen_test_paths=()
  for path in "${test_paths[@]}"; do
    if [[ -n "${seen_test_paths[$path]:-}" ]]; then
      continue
    fi
    seen_test_paths[$path]=1
    checked_test_count=$((checked_test_count + 1))

    local source_probe_matches
    local manifest_source_probe_matches
    local line
    local line_no
    local manifest_probe_start_line
    local manifest_probe_window
    local manifest_probe_saw_src_root
    local product_source_segment_path
    local product_source_path
    local manifest_source_literal_path
    local manifest_join_product_path
    local manifest_src_root_join
    local manifest_src_segment_join
    local source_probe_pattern
    product_source_segment_path='(bin|cli(\.rs)?|codegen|compiler(\.rs)?|dev|formatter\.rs|gpu|lexer|lib\.rs|main\.rs|parser|reflection\.rs|type_checker)'
    product_source_path='(\.\./)?(shaders|src/'"$product_source_segment_path"')'
    manifest_source_literal_path='"/(shaders|src/'"$product_source_segment_path"')'
    manifest_join_product_path='\.join\("(shaders|src/'"$product_source_segment_path"')'
    manifest_src_root_join='\.join\("src"\)'
    manifest_src_segment_join='\.join\("'"$product_source_segment_path"')'
    source_probe_pattern="include_(str|bytes)!\\([^)]*\"$product_source_path|read(_to_string)?\\([^)]*\"$product_source_path|fs::read(_to_string)?\\([^)]*\"$product_source_path|\\.(arg|args|join)\\([^)]*\"$product_source_path|\\.(arg|args)\\([^)]*\"(rg|grep)[^\"]*$product_source_path"
    source_probe_matches="$(grep -nE "$source_probe_pattern" "$path" || true)"
    if [[ -n "$source_probe_matches" ]]; then
      while IFS= read -r match; do
        [[ -n "$match" ]] || continue
        test_discipline_error "$path:$match reads or greps compiler/shader product source; use behavior, artifact, diagnostic, or record evidence instead"
      done <<< "$source_probe_matches"
    fi

    manifest_source_probe_matches=
    line_no=0
    manifest_probe_start_line=0
    manifest_probe_window=0
    manifest_probe_saw_src_root=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      line_no=$((line_no + 1))
      if [[ "$line" == *CARGO_MANIFEST_DIR* ]]; then
        manifest_probe_start_line="$line_no"
        manifest_probe_window=8
        manifest_probe_saw_src_root=0
      fi

      if [[ "$manifest_probe_window" -gt 0 ]]; then
        if [[ "$line" =~ $manifest_src_root_join ]]; then
          manifest_probe_saw_src_root=1
        fi

        if [[ "$line" =~ $manifest_source_literal_path \
          || "$line" =~ $manifest_join_product_path \
          || ( "$manifest_probe_saw_src_root" -eq 1 && "$line" =~ $manifest_src_segment_join ) ]]; then
          manifest_source_probe_matches+="${manifest_probe_start_line}-${line_no}:${line}"$'\n'
          manifest_probe_window=0
          manifest_probe_saw_src_root=0
        else
          manifest_probe_window=$((manifest_probe_window - 1))
        fi
      fi
    done < "$path"

    if [[ -n "$manifest_source_probe_matches" ]]; then
      while IFS= read -r match; do
        [[ -n "$match" ]] || continue
        test_discipline_error "$path:$match builds a CARGO_MANIFEST_DIR path to compiler/shader product source; use behavior, artifact, diagnostic, or record evidence instead"
      done <<< "$manifest_source_probe_matches"
    fi
  done

  test_discipline_checked_files="$checked_test_count"
  if [[ "$test_discipline_errors" -eq 0 ]]; then
    echo "# acceptance test-discipline check ok: $checked_test_count Rust integration test files inventoried through behavior/evidence references; compiler/shader product-source grep audit passed"
  fi
}

plan_check_has_errors() {
  [[ "$plan_invalid_tests" -gt 0 \
    || "$plan_missing_tests" -gt 0 \
    || "$plan_missing_commands" -gt 0 \
    || "$evidence_inventory_errors" -gt 0 \
    || "$language_slice_errors" -gt 0 \
    || "$test_discipline_errors" -gt 0 ]]
}

print_plan_check_status() {
  local status="$1"
  printf '# acceptance-plan: status=%s tier=%s mode=no-run checked_tests=%s invalid_tests=%s missing_tests=%s checked_commands=%s missing_commands=%s evidence_inventory_errors=%s language_slice_errors=%s test_discipline_errors=%s focused_evidence=%s smoke_evidence=%s generated_evidence=%s properties_evidence=%s pareas_evidence=%s property_boundary_evidence=%s property_record_evidence=%s property_execution_evidence=%s property_semantic_evidence=%s language_slice_rows=%s language_slice_public_boundary_evidence=%s language_slice_artifact_contract_evidence=%s language_slice_record_invariant_evidence=%s language_slice_semantic_contract_evidence=%s language_slice_execution_contract_evidence=%s language_slice_fail_closed_evidence=%s language_slice_measurement_scaffold_evidence=%s language_slice_parser_type_relation_evidence=%s language_slice_pass_order_evidence=%s language_slice_performance_claim_guards=%s language_slice_external_tooling_gate_evidence=%s language_slice_planned_pass_order_gaps=%s test_discipline_checked_files=%s\n' \
    "$status" \
    "$tier" \
    "$plan_checked_tests" \
    "$plan_invalid_tests" \
    "$plan_missing_tests" \
    "$plan_checked_commands" \
    "$plan_missing_commands" \
    "$evidence_inventory_errors" \
    "$language_slice_errors" \
    "$test_discipline_errors" \
    "$plan_focused_evidence" \
    "$plan_smoke_evidence" \
    "$plan_generated_evidence" \
    "$plan_properties_evidence" \
    "$plan_pareas_evidence" \
    "$plan_property_boundary_evidence" \
    "$plan_property_record_evidence" \
    "$plan_property_execution_evidence" \
    "$plan_property_semantic_evidence" \
    "$language_slice_rows" \
    "$language_slice_public_boundary_evidence" \
    "$language_slice_artifact_contract_evidence" \
    "$language_slice_record_invariant_evidence" \
    "$language_slice_semantic_contract_evidence" \
    "$language_slice_execution_contract_evidence" \
    "$language_slice_fail_closed_evidence" \
    "$language_slice_measurement_scaffold_evidence" \
    "$language_slice_parser_type_relation_evidence" \
    "$language_slice_pass_order_evidence" \
    "$language_slice_performance_claim_guards" \
    "$language_slice_external_tooling_gate_evidence" \
    "$language_slice_planned_pass_order_gaps" \
    "$test_discipline_checked_files"
}

finish_plan_check() {
  if [[ "$check_plan" -eq 0 ]]; then
    return
  fi
  check_acceptance_script_contract
  check_test_discipline_contract
  check_evidence_inventory_contract
  check_measurement_plan_contract
  check_language_slice_contract
  if plan_check_has_errors; then
    print_plan_check_status failed
    echo "# acceptance-plan check failed: $plan_invalid_tests of $plan_checked_tests evidence references were invalid; $plan_missing_tests of $plan_checked_tests evidence target paths were not found; $plan_missing_commands of $plan_checked_commands no-run checks were not found; $evidence_inventory_errors evidence-plan issue(s), $language_slice_errors language-slice issue(s), and $test_discipline_errors test-discipline issue(s) were found" >&2
    exit 1
  fi
  print_plan_check_status ok
  echo "# acceptance-plan check ok: $plan_checked_tests evidence references and $plan_checked_commands no-run checks passed; no tests were compiled or executed"
}

run_cargo_test() {
  local test_target="$1"
  local test_name="${2:-}"
  shift 2 || true
  record_named_test_reference integration "$test_target" "$test_name" "tests/$test_target.rs"
  if [[ -n "$test_name" ]]; then
    run_cmd cargo test -j1 --test "$test_target" "$test_name" -- --test-threads=1 "$@"
  else
    run_cmd cargo test -j1 --test "$test_target" -- --test-threads=1 "$@"
  fi
}

run_cargo_bin_test() {
  local bin_target="$1"
  local test_name="$2"
  record_named_test_reference bin "$bin_target" "$test_name" src
  run_cmd cargo test -j1 --bin "$bin_target" "$test_name" -- --test-threads=1
}

run_cargo_lib_test() {
  local test_name="$1"
  record_named_test_reference lib laniusc "$test_name" src tests
  run_cmd cargo test -p laniusc -j1 --lib "$test_name" -- --test-threads=1
}

describe_tier() {
  case "$tier" in
    focused)
      echo "# testing-strategy tier=focused lane=CPU/model contract='library compiles, diagnostics render stably, focused source-pack/x86 behavior holds, work-queue model still matches reference transitions'"
      ;;
    smoke)
      echo "# testing-strategy tier=smoke lane=capacity-estimate contract='generated gates are discoverable and x86 stress sizing is computed without GPU submission'"
      ;;
    generated)
      echo "# testing-strategy tier=generated lane=fixed-seed-generated contract='supported generated frontend/backend cases still compile and validate at the explicitly requested size'"
      ;;
    properties)
      echo "# testing-strategy tier=properties lane=targeted-property contract='source-root boundaries, name/shape independence, executable slices, and HIR-record invariants hold on focused cases'"
      ;;
    readiness)
      echo "# testing-strategy tier=readiness lane=no-run-inventory contract='current production-readiness evidence stays syntactically concrete without launching heavy jobs'"
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
  current_plan_lane=focused
  if [[ "$list_tests" -eq 1 ]]; then
    run_cmd cargo test --test cli_package_manifest -j1 -- --list
    run_cmd cargo test --test cli_source_pack_contract -j1 -- --list
    run_cmd cargo test --test cli_formatter -j1 -- --list
    run_cmd cargo test --test cli_lsp -j1 -- --list
    run_cmd cargo test --test cli_version -j1 -- --list
    run_cmd cargo test --test formatter -j1 -- --list
    run_cmd cargo test --test package_manifest -j1 -- --list
    run_cmd cargo test -p laniusc diagnostic_renderer_includes_code_span_snippet_label_and_note -j1 --lib -- --list
    run_cmd cargo test -j1 --bin laniusc contract_file_emission_copies_without_marking_executable -- --list
    run_cmd cargo test -j1 --bin laniusc contract_descriptor_emission_rejects_incoherent_json_descriptor -- --list
    run_cmd cargo test -p laniusc source_pack_work_queue_progress_page_transitions_match_reference_model -j1 --lib -- --list
    return
  fi
  run_cmd cargo check --lib -j1
  run_cargo_lib_test diagnostic_renderer_includes_code_span_snippet_label_and_note
  run_cargo_lib_test diagnostic_json_renderer_preserves_external_fields
  run_cargo_lib_test diagnostic_code_registry_preserves_public_metadata
  run_cargo_lib_test artifact_descriptor_records_distinguish_stage_contracts
  run_cargo_lib_test artifact_descriptor_records_reject_cross_stage_shapes
  run_cargo_lib_test link_execution_output_key_must_match_partial_or_final_kind
  run_cargo_lib_test link_reduce_work_queue_inputs_must_reference_prior_groups
  run_cargo_lib_test final_link_work_queue_rejects_persisted_relocation_descriptor_summary
  run_cargo_lib_test partial_link_work_queue_rejects_mismatched_persisted_output_key
  run_cargo_lib_test linked_output_descriptor_rejects_partial_link_output_records
  run_cargo_lib_test linked_output_descriptor_rejects_partial_link_inputs_without_group
  run_cargo_lib_test linked_output_descriptor_rejects_object_domain_output_arrays
  run_cargo_lib_test persisted_descriptor_record_arrays_reject_mixed_semantic_shapes
  run_cargo_bin_test laniusc contract_file_emission_copies_without_marking_executable
  run_cargo_bin_test laniusc contract_descriptor_emission_rejects_incoherent_json_descriptor
  run_cargo_test cli_package_manifest cli_package_manifest_rejects_extra_positional_inputs
  run_cargo_test cli_package_manifest cli_package_lockfile_rejects_mixed_input_modes
  run_cargo_test cli_source_pack_contract cli_descriptor_source_pack_requires_explicit_contract_output
  run_cargo_test cli_source_pack_contract cli_descriptor_source_root_preparation_is_explicitly_unsupported
  run_cargo_test cli_source_pack_contract cli_descriptor_package_manifest_preparation_is_explicitly_unsupported
  run_cargo_test cli_formatter cli_fmt_formats_source_file_in_place
  run_cargo_test cli_formatter cli_fmt_keeps_where_predicates_one_per_line_and_check_accepts_rewrite
  run_cargo_test cli_formatter cli_fmt_check_reports_unformatted_source_without_writing
  run_cargo_test cli_lsp cli_lsp_capabilities_reports_no_run_diagnostic_contract
  run_cargo_test cli_lsp cli_lsp_serve_handles_initialize_shutdown_without_compiling_source
  run_cargo_test cli_version cli_version_reports_distribution_contract_without_compiling_source
  run_cargo_test cli_version cli_doctor_reports_no_run_toolchain_contract_without_compiling_source
  run_cargo_test cli_version cli_accepts_explicit_current_language_edition
  run_cargo_test cli_version cli_accepts_explicit_supported_target_triple
  run_cargo_test cli_version cli_rejects_unsupported_language_edition_before_compiling_source
  run_cargo_test cli_version cli_rejects_unsupported_target_triple_before_compiling_source
  run_cargo_test cli_version cli_rejects_emit_target_mismatch_before_compiling_source
  run_cargo_test formatter formatter_is_idempotent_for_alpha_slice
  run_cargo_test formatter formatter_distinguishes_unary_and_binary_minus
  run_cargo_test formatter formatter_keeps_boundary_block_comments_standalone
  run_cargo_test package_manifest package_lockfile_records_and_validates_input_identity
  run_cargo_test package_manifest package_lockfile_records_and_validates_import_graph
  run_cargo_test package_manifest package_lockfile_detects_removed_imported_file
  run_cargo_test package_manifest package_lockfile_rejects_stale_resolved_roots_and_entry_before_loading_inputs
  run_cargo_test package_manifest package_lockfile_requires_import_graph_and_input_identity
  run_cargo_test package_manifest package_lockfile_rejects_other_compiler_versions
  run_cargo_test package_manifest package_lockfile_rejects_non_reproducible_control_plane_fields
  run_cargo_test package_manifest package_lockfile_rejects_duplicate_source_identity_modules_in_one_library
  run_cargo_test package_manifest package_lockfile_rejects_import_graph_dependencies_missing_from_identity_sections
  run_cargo_lib_test source_pack_work_queue_progress_page_transitions_match_reference_model
}

run_smoke() {
  current_plan_lane=smoke
  run_cmd cargo test --test generated_10k_gates -j1 -- --list
  if [[ "$list_tests" -eq 1 ]]; then
    return
  fi
  run_cargo_test generated_10k_gates \
    compiler_acceptance_measurement_plan_writes_requested_artifact_without_stdout_plan
  run_cargo_test generated_10k_gates \
    compiler_acceptance_readiness_check_plan_validates_measurement_inventory
  run_cargo_test generated_10k_gates \
    generated_capacity_stress_x86_has_capacity_estimate_without_gpu_work \
    --ignored
}

run_generated() {
  current_plan_lane=generated
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
  current_plan_lane=properties
  if [[ "$list_tests" -eq 1 ]]; then
    run_cmd cargo test --test cli_diagnostics -j1 -- --list
    run_cmd cargo test --test cli_package_manifest -j1 -- --list
    run_cmd cargo test --test cli_stdlib_root -j1 -- --list
    run_cmd cargo test --test package_manifest -j1 -- --list
    run_cmd cargo test --test formatter -j1 -- --list
    run_cmd cargo test --test codegen_wasm -j1 -- --list
    run_cmd cargo test --test codegen_x86 -j1 -- --list
    run_cmd cargo test --test codegen_x86_properties -j1 -- --list
    run_cmd cargo test --test module_visibility -j1 -- --list
    run_cmd cargo test --test parser_hir_records -j1 -- --list
    run_cmd cargo test --test source_pack_package_boundaries -j1 -- --list
    run_cmd cargo test --test stdlib_runtime_contract -j1 -- --list
    run_cmd cargo test --test type_checker_generics -j1 -- --list
    run_cmd cargo test --test type_checker_modules -j1 -- --list
    run_cmd cargo test --test type_checker_scope -j1 -- --list
    run_cmd cargo test --test type_checker_semantics -j1 -- --list
    return
  fi
  run_cargo_test cli_diagnostics \
    diagnostic_registry_json_contains_code_metadata_categories_and_unsupported_boundaries
  run_cargo_test cli_diagnostics \
    diagnostic_output_formats_json_describes_cli_payload_contracts
  run_cargo_test cli_diagnostics \
    cli_diagnostics_registry_prints_combined_registry_json_without_compiling_source
  run_cargo_test cli_diagnostics \
    cli_diagnostics_categories_groups_codes_by_stable_category_without_compiling_source
  run_cargo_test cli_diagnostics \
    cli_diagnostics_formats_prints_machine_readable_contract_without_compiling_source
  run_cargo_test cli_diagnostics \
    cli_diagnostics_explain_prints_single_code_json_without_compiling_source
  run_cargo_test cli_diagnostics \
    cli_diagnostics_explain_reports_unknown_code_as_machine_readable_result
  run_cargo_test cli_diagnostics \
    cli_unsupported_emit_target_can_render_json_diagnostic_without_compiling_source
  run_cargo_test cli_diagnostics \
    cli_unsupported_edition_can_render_lsp_json_diagnostic_before_source_loading
  run_cargo_test cli_diagnostics \
    cli_unknown_flag_can_render_json_diagnostic_without_compiling_source
  run_cargo_test cli_diagnostics \
    cli_diagnostics_registry_accepts_diagnostic_format_after_subcommand
  run_cargo_test cli_diagnostics \
    diagnostic_lsp_json_renderer_exposes_protocol_fields_without_envelope
  run_cargo_test cli_diagnostics \
    cli_single_file_assignment_mismatch_renders_stable_diagnostic
  run_cargo_test cli_diagnostics \
    cli_single_file_syntax_error_renders_stable_diagnostic
  run_cargo_test cli_diagnostics \
    cli_single_file_syntax_error_can_render_json_diagnostic
  run_cargo_test cli_diagnostics \
    cli_check_valid_source_suppresses_target_bytes
  run_cargo_test cli_diagnostics \
    cli_check_syntax_error_can_render_json_diagnostic_without_stdout
  run_cargo_test cli_diagnostics \
    cli_check_syntax_error_can_render_lsp_json_diagnostic_without_stdout
  run_cargo_test cli_diagnostics \
    cli_source_root_import_syntax_error_renders_stable_file_diagnostic
  run_cargo_test cli_diagnostics \
    cli_check_source_root_missing_import_renders_json_category_before_compiling_source
  run_cargo_test cli_diagnostics \
    cli_linked_output_contract_descriptor_rejects_target_bytes_as_json_diagnostic
  run_cargo_test cli_package_manifest \
    cli_package_manifest_compiles_entry_through_source_roots
  run_cargo_test cli_package_manifest \
    cli_package_lockfile_compiles_entry_through_resolved_source_roots
  run_cargo_test cli_stdlib_root \
    cli_stdlib_root_reports_missing_import_before_gpu
  run_cargo_test cli_stdlib_root \
    cli_source_root_and_stdlib_root_require_path_arguments
  run_cargo_test cli_stdlib_root \
    cli_source_roots_require_existing_directories
  run_cargo_test cli_stdlib_root \
    cli_source_roots_require_exactly_one_entry_input
  run_cargo_test cli_stdlib_root \
    cli_source_roots_reject_explicit_stdlib_sources
  run_cargo_test cli_stdlib_root \
    cli_source_root_and_stdlib_root_reject_same_canonical_import_file
  run_cargo_test cli_stdlib_root \
    cli_source_root_reports_missing_import_before_gpu
  run_cargo_test cli_stdlib_root \
    cli_source_root_rejects_import_symlink_to_non_source_file_before_gpu
  run_cargo_test cli_stdlib_root \
    cli_source_root_reports_ambiguous_import_before_gpu
  run_cargo_test cli_stdlib_root \
    cli_source_root_deduplicates_repeated_roots_before_missing_import_diagnostic
  run_cargo_test package_manifest \
    package_lockfile_rejects_input_identity_with_wrong_library_root
  run_cargo_test package_manifest \
    package_lockfile_rejects_import_graph_edges_missing_from_input_identity
  run_cargo_test package_manifest \
    package_lockfile_rejects_import_graph_edge_with_wrong_library_root
  run_cargo_test formatter \
    formatter_preserves_string_and_char_literal_contents
  run_cargo_test codegen_wasm \
    wasm_executes_source_pack_function_call
  run_cargo_test codegen_x86 \
    x86_executes_while_loop_with_scalar_local_mutation
  run_cargo_test codegen_x86 \
    x86_executes_while_break_and_continue
  run_cargo_test codegen_x86 \
    x86_executes_nested_arithmetic_in_branch_conditions_and_bodies
  run_cargo_test codegen_x86 \
    x86_executes_for_array_with_break_and_continue
  run_cargo_test codegen_x86 \
    x86_rejects_loop_condition_call_before_codegen_timeout
  run_cargo_test codegen_x86 \
    x86_rejects_loop_body_assignment_call_before_codegen_timeout
  run_cargo_test codegen_x86 \
    x86_executes_array_literal_index_sum
  run_cargo_test codegen_x86 \
    x86_executes_indexed_assignment_inside_loop_branch
  run_cargo_test codegen_x86 \
    x86_rejects_unsupported_five_argument_call_in_codegen
  run_cargo_test codegen_x86 \
    x86_source_pack_rejects_unsupported_five_argument_call_with_diagnostic
  run_cargo_test codegen_x86 \
    x86_source_pack_assignment_mismatch_reports_lnc0006_diagnostic
  run_cargo_test codegen_x86 \
    x86_source_pack_unresolved_identifier_reports_lnc0005_diagnostic
  run_cargo_test codegen_x86 \
    x86_rejects_direct_recursive_call_before_lowering
  run_cargo_test codegen_x86 \
    x86_rejects_aggregate_copy_above_bounded_gpu_row_width
  run_cargo_test codegen_x86_properties \
    generated_x86_programs_are_name_and_shape_independent
  run_cargo_test codegen_x86_properties \
    generated_x86_source_pack_calls_are_name_and_shape_independent
  run_cargo_test codegen_x86_properties \
    generated_x86_loop_contained_call_rejections_are_name_independent
  run_cargo_test codegen_x86_properties \
    generated_x86_zero_divisor_rejections_are_name_and_shape_independent
  run_cargo_test module_visibility \
    imports_expose_only_public_declarations_from_imported_module_records
  run_cargo_test parser_hir_records \
    parser_hir_call_argument_records_have_contiguous_owners_and_ordinals
  run_cargo_test parser_hir_records \
    parser_hir_method_call_records_link_callee_member_and_receiver
  run_cargo_test parser_hir_records \
    parser_hir_enum_variant_records_link_variants_and_payload_types
  run_cargo_test parser_hir_records \
    parser_hir_array_literal_records_link_elements_and_spans
  run_cargo_test parser_hir_records \
    parser_hir_array_literal_local_declaration_context_feeds_type_checking
  run_cargo_test parser_hir_records \
    parser_hir_array_index_records_feed_type_checking_not_parameter_spelling
  run_cargo_test parser_hir_records \
    parser_hir_child_records_keep_source_spans_inside_recorded_owners
  run_cargo_test parser_hir_records \
    parser_hir_generic_type_arguments_link_owner_and_argument_chain
  run_cargo_test parser_hir_records \
    parser_hir_generic_type_arguments_are_source_addressable_in_source_packs
  run_cargo_test parser_hir_records \
    parser_hir_import_records_carry_source_pack_file_ids_and_token_spans
  run_cargo_test parser_hir_records \
    parser_hir_item_records_are_source_addressable_in_source_packs
  run_cargo_test parser_hir_records \
    parser_hir_match_payload_records_are_source_addressable_in_source_packs
  run_cargo_test parser_hir_records \
    parser_hir_match_payload_records_feed_type_checking_not_variant_name_decoys
  run_cargo_test parser_hir_records \
    parser_hir_struct_field_records_are_source_addressable_in_source_packs
  run_cargo_test parser_hir_records \
    parser_hir_struct_literal_field_records_feed_type_checking_not_field_spelling
  run_cargo_test parser_hir_records \
    parser_hir_module_and_import_records_publish_parser_path_nodes
  run_cargo_test source_pack_package_boundaries \
    explicit_source_pack_library_ids_are_planning_boundaries_not_package_boundaries
  run_cargo_test source_pack_package_boundaries \
    source_root_loader_rejects_same_file_across_user_and_stdlib_boundaries
  run_cargo_test type_checker_scope \
    type_checker_unresolved_identifier_diagnostic_uses_source_span_and_path
  run_cargo_test type_checker_modules \
    type_checker_entry_stdlib_root_loads_imported_module
  run_cargo_test type_checker_modules \
    type_checker_entry_source_root_loads_user_module_imports
  run_cargo_test type_checker_modules \
    source_root_imports_use_gpu_module_declarations_not_host_paths
  run_cargo_test type_checker_modules \
    source_root_loader_can_combine_user_and_stdlib_roots
  run_cargo_test type_checker_modules \
    source_root_loader_reports_missing_stdlib_module_path
  run_cargo_test type_checker_modules \
    source_root_loader_rejects_ambiguous_user_module_path
  run_cargo_test type_checker_modules \
    source_root_loader_leaves_quoted_imports_for_gpu_rejection
  run_cargo_test type_checker_modules \
    type_checker_string_import_reports_stable_diagnostic
  run_cargo_test type_checker_modules \
    type_checker_deep_import_path_reports_stable_diagnostic
  run_cargo_test type_checker_modules \
    type_checker_duplicate_source_pack_module_reports_stable_diagnostic
  run_cargo_test type_checker_modules \
    type_checker_deep_module_path_reports_stable_diagnostic
  run_cargo_test type_checker_modules \
    type_checker_source_pack_syntax_failure_reports_stable_diagnostic
  run_cargo_test type_checker_modules \
    source_root_loader_deduplicates_import_cycles_without_semantic_rejection
  run_cargo_test type_checker_modules \
    type_checker_entry_stdlib_root_type_checks_core_bool_contract
  run_cargo_test type_checker_modules \
    type_checker_entry_stdlib_root_type_checks_core_runtime_contract
  run_cargo_test type_checker_modules \
    type_checker_rejects_self_import_through_gpu_module_resolver
  run_cargo_test type_checker_modules \
    type_checker_resolves_qualified_function_calls
  run_cargo_test type_checker_modules \
    type_checker_rejects_private_cross_module_qualified_paths
  run_cargo_test type_checker_modules \
    type_checker_rejects_ambiguous_imported_names
  run_cargo_test type_checker_modules \
    type_checker_rejects_unqualified_trait_impl_for_different_module_bound
  run_cargo_test type_checker_modules \
    source_root_loader_rejects_stdlib_symlink_escape
  run_cargo_test type_checker_modules \
    source_root_loader_rejects_user_symlink_escape
  run_cargo_test stdlib_runtime_contract \
    core_runtime_descriptor_inventory_type_checks_through_stdlib_root
  run_cargo_test stdlib_runtime_contract \
    core_runtime_descriptor_is_importable_from_source_pack
  run_cargo_test stdlib_runtime_contract \
    core_panic_hook_contract_type_checks_against_unbound_runtime_service_through_stdlib_root
  run_cargo_test stdlib_runtime_contract \
    alloc_allocator_contract_type_checks_against_unbound_runtime_allocator_through_stdlib_root
  run_cargo_test stdlib_runtime_contract \
    std_fs_contract_type_checks_against_unbound_runtime_filesystem_service_through_stdlib_root
  run_cargo_test stdlib_runtime_contract \
    std_net_contract_type_checks_against_unbound_runtime_network_service_through_stdlib_root
  run_cargo_test stdlib_runtime_contract \
    std_time_contract_type_checks_against_unbound_runtime_clock_service_through_stdlib_root
  run_cargo_test type_checker_generics \
    type_checker_accepts_nested_direct_generic_function_calls
  run_cargo_test type_checker_generics \
    type_checker_accepts_nested_generic_forwarding_through_helpers
  run_cargo_test type_checker_semantics \
    type_checker_accepts_generated_let_chain_on_gpu
  run_cargo_test type_checker_semantics \
    type_checker_accepts_generated_call_argument_shapes_on_gpu
  run_cargo_test type_checker_semantics \
    type_checker_rejects_trait_impls_whose_trait_does_not_resolve_on_gpu
  run_cargo_test type_checker_semantics \
    type_checker_rejects_nonzero_call_argument_type_mismatches_on_gpu
  run_cargo_test type_checker_semantics \
    type_checker_rejects_nonzero_generic_call_argument_mismatches_on_gpu
  run_cargo_test type_checker_semantics \
    type_checker_rejects_array_literal_local_element_mismatches_on_gpu
  run_cargo_test type_checker_semantics \
    type_checker_method_calls_use_hir_member_receiver_over_global_name_spelling
  run_cargo_test type_checker_semantics \
    type_checker_resolves_methods_by_concrete_generic_receiver_instance
  run_cargo_test type_checker_semantics \
    type_checker_reports_generic_inherent_method_returns_outside_bounded_gpu_slice
  run_cargo_test type_checker_semantics \
    type_checker_accepts_direct_generic_function_at_two_concrete_types
  run_cargo_test type_checker_semantics \
    type_checker_accepts_enum_constructors_with_concrete_types
  run_cargo_test type_checker_semantics \
    type_checker_checks_multi_payload_enum_match_ordinals_on_gpu
  run_cargo_test type_checker_semantics \
    type_checker_resolves_qualified_two_arg_trait_bounds_by_decl_identity
  run_cargo_test type_checker_semantics \
    type_checker_rejects_trait_impl_methods_with_wrong_return_type_on_gpu
  run_cargo_test type_checker_semantics \
    type_checker_rejects_trait_method_dispatch_until_gpu_lookup_supports_it
}

run_readiness() {
  run_focused
  run_smoke
  run_properties
}

run_pareas() {
  current_plan_lane=pareas
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
check_acceptance_environment
if [[ "$measurement_plan" -eq 1 ]]; then
  write_perf_measurement_plan
  exit 0
fi
if [[ "$check_env" -eq 1 && "$check_plan" -eq 0 ]]; then
  exit 0
fi
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
  readiness)
    run_readiness
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

finish_plan_check
