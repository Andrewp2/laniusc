#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tools/nvidia_gpu_guard.sh [--log PATH] -- COMMAND [ARG...]

Runs one NVIDIA GPU workload with conservative desktop-safety guardrails:
- refuses to start after NVIDIA mapping/Xid errors in the current boot;
- refuses overlapping guarded runs and, by default, existing compute clients;
- records framebuffer use and temperature while the command runs;
- terminates the command on a new kernel GPU error, timeout, or threshold breach.

Environment:
  LANIUS_GPU_GUARD_GPU_INDEX                    default 0
  LANIUS_GPU_GUARD_POLL_MS                      default 500
  LANIUS_GPU_GUARD_TIMEOUT_SECONDS              default 300
  LANIUS_GPU_GUARD_MAX_INITIAL_MEMORY_PERCENT   default 30
  LANIUS_GPU_GUARD_MAX_MEMORY_PERCENT           default 80
  LANIUS_GPU_GUARD_MAX_TEMPERATURE_C            default 83
  LANIUS_GPU_GUARD_ALLOW_EXISTING_COMPUTE       default 0
  LANIUS_GPU_GUARD_ALLOW_DIRTY_BOOT             default 0
  LANIUS_GPU_GUARD_LOCK_PATH                     default under XDG_RUNTIME_DIR
  LANIUS_GPU_GUARD_NVIDIA_SMI                    default nvidia-smi
  LANIUS_GPU_GUARD_JOURNALCTL                    default journalctl

This guard reduces risk; it cannot recover a GPU or desktop after a driver fault.
EOF
}

die() {
  printf 'nvidia-gpu-guard: %s\n' "$*" >&2
  exit 78
}

is_unsigned_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

is_enabled() {
  case "${1,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

kernel_error_pattern='x86/PAT: .*conflicting memory types|memtype_reserve failed|ioremap memtype_reserve failed|Failed to ioremap_wc NvKmsKapiMemory|Failed to map NvKmsKapiMemory|NVRM: Xid'

kernel_errors() {
  local output
  output="$($journalctl -b -k --no-pager -o cat "$@" 2>&1)" || {
    printf '%s\n' "$output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -E "$kernel_error_pattern" || true
}

sample_gpu() {
  local sample used total temperature
  sample="$($nvidia_smi --id="$gpu_index" --query-gpu=memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null)" || return 1
  IFS=, read -r used total temperature <<<"$sample"
  used="${used//[[:space:]]/}"
  total="${total//[[:space:]]/}"
  temperature="${temperature//[[:space:]]/}"
  is_unsigned_integer "$used" || return 1
  is_unsigned_integer "$total" || return 1
  is_unsigned_integer "$temperature" || return 1
  (( total > 0 )) || return 1
  printf '%s %s %s\n' "$used" "$total" "$temperature"
}

terminate_child() {
  [[ -n "${child_pid:-}" ]] || return 0
  kill -0 "$child_pid" 2>/dev/null || return 0
  kill -TERM -- "-$child_pid" 2>/dev/null || kill -TERM "$child_pid" 2>/dev/null || true
  local attempt
  for attempt in {1..20}; do
    kill -0 "$child_pid" 2>/dev/null || return 0
    sleep 0.05
  done
  kill -KILL -- "-$child_pid" 2>/dev/null || kill -KILL "$child_pid" 2>/dev/null || true
}

log_path=""
while (($#)); do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --log)
      (($# >= 2)) || die '--log requires a path'
      log_path="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      die "unknown option: $1 (put the workload after --)"
      ;;
  esac
done
(($#)) || die 'missing workload command after --'

gpu_index="${LANIUS_GPU_GUARD_GPU_INDEX:-0}"
poll_ms="${LANIUS_GPU_GUARD_POLL_MS:-500}"
timeout_seconds="${LANIUS_GPU_GUARD_TIMEOUT_SECONDS:-300}"
max_initial_memory_percent="${LANIUS_GPU_GUARD_MAX_INITIAL_MEMORY_PERCENT:-30}"
max_memory_percent="${LANIUS_GPU_GUARD_MAX_MEMORY_PERCENT:-80}"
max_temperature_c="${LANIUS_GPU_GUARD_MAX_TEMPERATURE_C:-83}"
allow_existing_compute="${LANIUS_GPU_GUARD_ALLOW_EXISTING_COMPUTE:-0}"
allow_dirty_boot="${LANIUS_GPU_GUARD_ALLOW_DIRTY_BOOT:-0}"
nvidia_smi="${LANIUS_GPU_GUARD_NVIDIA_SMI:-nvidia-smi}"
journalctl="${LANIUS_GPU_GUARD_JOURNALCTL:-journalctl}"
lock_path="${LANIUS_GPU_GUARD_LOCK_PATH:-${XDG_RUNTIME_DIR:-/tmp}/laniusc-nvidia-gpu-${UID}.lock}"

for value_name in gpu_index poll_ms timeout_seconds max_initial_memory_percent max_memory_percent max_temperature_c; do
  value="${!value_name}"
  is_unsigned_integer "$value" || die "$value_name must be an unsigned integer, got '$value'"
done
(( poll_ms > 0 )) || die 'poll_ms must be greater than zero'
(( timeout_seconds > 0 )) || die 'timeout_seconds must be greater than zero'
(( max_initial_memory_percent > 0 && max_initial_memory_percent <= 100 )) || die 'max_initial_memory_percent must be in 1..100'
(( max_memory_percent > 0 && max_memory_percent <= 100 )) || die 'max_memory_percent must be in 1..100'
(( max_initial_memory_percent < max_memory_percent )) || die 'initial memory threshold must be lower than runtime memory threshold'

command -v "$nvidia_smi" >/dev/null 2>&1 || die "nvidia-smi command not found: $nvidia_smi"
command -v "$journalctl" >/dev/null 2>&1 || die "journalctl command not found: $journalctl"
command -v flock >/dev/null 2>&1 || die 'flock is required'
command -v setsid >/dev/null 2>&1 || die 'setsid is required'

mkdir -p "$(dirname "$lock_path")"
exec 9>"$lock_path"
flock -n 9 || die "another guarded GPU workload holds $lock_path"

boot_errors="$(kernel_errors)" || die 'could not inspect the current kernel journal'
if [[ -n "$boot_errors" ]] && ! is_enabled "$allow_dirty_boot"; then
  printf '%s\n' "$boot_errors" >&2
  die 'current boot already contains an NVIDIA mapping or Xid error; reboot before GPU work'
fi

read -r initial_used initial_total initial_temperature < <(sample_gpu) || die "could not sample NVIDIA GPU $gpu_index"
if (( initial_used * 100 >= max_initial_memory_percent * initial_total )); then
  die "initial framebuffer use ${initial_used}/${initial_total} MiB is at or above ${max_initial_memory_percent}%"
fi
if (( initial_temperature >= max_temperature_c )); then
  die "initial GPU temperature ${initial_temperature} C is at or above ${max_temperature_c} C"
fi

existing_compute="$($nvidia_smi --id="$gpu_index" --query-compute-apps=pid,process_name,used_gpu_memory --format=csv,noheader,nounits 2>/dev/null || true)"
if [[ -n "$existing_compute" ]] && ! is_enabled "$allow_existing_compute"; then
  printf '%s\n' "$existing_compute" >&2
  die 'an existing NVIDIA compute client is active; do not overlap GPU workloads'
fi

if [[ -z "$log_path" ]]; then
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  log_path="target/lanius-gpu-guard/${timestamp}-$$.csv"
fi
mkdir -p "$(dirname "$log_path")"
printf 'timestamp_utc,elapsed_seconds,memory_used_mib,memory_total_mib,memory_percent,temperature_c\n' >"$log_path"

printf -v poll_seconds '%d.%03d' "$((poll_ms / 1000))" "$((poll_ms % 1000))"
start_epoch="$(date +%s)"
start_monotonic="$SECONDS"
child_pid=""
interrupted=false
trap 'interrupted=true; terminate_child' INT TERM HUP

printf 'nvidia-gpu-guard: starting GPU %s workload; telemetry=%s\n' "$gpu_index" "$log_path" >&2
setsid --wait -- "$@" &
child_pid=$!
guard_failure=""

while kill -0 "$child_pid" 2>/dev/null; do
  elapsed=$((SECONDS - start_monotonic))
  if (( elapsed >= timeout_seconds )); then
    guard_failure="timeout after ${timeout_seconds}s"
    break
  fi

  if ! new_kernel_errors="$(kernel_errors --since="@$start_epoch")"; then
    guard_failure='lost access to the kernel journal'
    break
  fi
  if [[ -n "$new_kernel_errors" ]]; then
    printf '%s\n' "$new_kernel_errors" >&2
    guard_failure='new NVIDIA mapping or Xid kernel error'
    break
  fi

  if ! read -r used total temperature < <(sample_gpu); then
    guard_failure="lost NVIDIA telemetry for GPU $gpu_index"
    break
  fi
  memory_percent=$((used * 100 / total))
  printf '%s,%s,%s,%s,%s,%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$elapsed" "$used" "$total" "$memory_percent" "$temperature" >>"$log_path"

  if (( used * 100 >= max_memory_percent * total )); then
    guard_failure="framebuffer use ${used}/${total} MiB reached ${max_memory_percent}%"
    break
  fi
  if (( temperature >= max_temperature_c )); then
    guard_failure="GPU temperature ${temperature} C reached ${max_temperature_c} C"
    break
  fi
  sleep "$poll_seconds"
done

if [[ "$interrupted" == true ]]; then
  terminate_child
  wait "$child_pid" 2>/dev/null || true
  printf 'nvidia-gpu-guard: interrupted; workload terminated\n' >&2
  exit 130
fi

if [[ -n "$guard_failure" ]]; then
  printf 'nvidia-gpu-guard: unsafe condition: %s; terminating workload\n' "$guard_failure" >&2
  terminate_child
  wait "$child_pid" 2>/dev/null || true
  exit 125
fi

if wait "$child_pid"; then
  status=0
else
  status=$?
fi
printf 'nvidia-gpu-guard: workload exited %s; telemetry=%s\n' "$status" "$log_path" >&2
exit "$status"
