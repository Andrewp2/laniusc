#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: tools/run_nsight_gpu_trace.sh [--dry-run] [--output-dir DIR]
       [--working-dir DIR] -- EXE [ARG ...]

Capture one complete application-bounded workload. EXE must use the NGFX SDK
bridge and write the completion receipt (see docs/nsight-gpu-trace.md).
nsight_compile is the full-compile driver. An arbitrary time-window capture is
not accepted. A successful Nsight exit alone is not proof of complete coverage.

Environment overrides:
  LANIUS_NGFX_BIN             explicit ngfx launcher path
  LANIUS_NGFX_SDK_INCLUDE     installed SDK include directory (auto-detected)
  LANIUS_NGFX_MAX_DURATION_MS safety ceiling below 10000 (default: 9999)
  LANIUS_NGFX_EVENT_BUFFER_KB  event-buffer capacity (default: 500000)
  LANIUS_NGFX_TIMESTAMPS       timestamp capacity (default: 1000000)
  LANIUS_NGFX_PC_SAMPLES       PC samples per PM interval/SM (default: 1024)
  LANIUS_NGFX_ARCHITECTURE     profiler architecture (default: Ampere GA10x)
  LANIUS_NGFX_METRIC_SET       counter set name (default: Throughput Metrics)
  LANIUS_NGFX_REAL_TIME_SHADER set to 0 to disable shader profiling
  LANIUS_NGFX_MULTI_PASS       set to 1 to collect replayed metric passes
  LANIUS_NGFX_BACKEND          wgpu backend exposed to Nsight (default: vulkan)
  LANIUS_NGFX_LOG_FILE         optional additional copy of nsight.log
EOF
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

dry_run=0
output_dir=""
working_dir=""
while (($#)); do
    case "$1" in
        --dry-run)
            dry_run=1
            shift
            ;;
        --output-dir)
            if (($# < 2)); then
                echo "error: --output-dir requires a value" >&2
                exit 2
            fi
            output_dir=$2
            shift 2
            ;;
        --working-dir)
            if (($# < 2)); then
                echo "error: --working-dir requires a value" >&2
                exit 2
            fi
            working_dir=$2
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "error: unknown wrapper option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if (($# == 0)); then
    echo "error: missing target executable after --" >&2
    usage >&2
    exit 2
fi

target=$1
shift
if [[ $target != */* ]]; then
    target=$(command -v -- "$target" || true)
fi
if [[ -z $target || ! -x $target ]]; then
    echo "error: target executable is not executable: ${target:-<not found>}" >&2
    exit 2
fi
target=$(readlink -f -- "$target")

ngfx=${LANIUS_NGFX_BIN:-}
if [[ -z $ngfx ]]; then
    mapfile -t ngfx_candidates < <(
        find /opt/nvidia/nsight-graphics-for-linux -type f \
            -path '*/host/linux-desktop-nomad-x64/ngfx' -perm -111 2>/dev/null \
            | sort -V
    )
    if ((${#ngfx_candidates[@]})); then
        ngfx=${ngfx_candidates[-1]}
    fi
fi
if [[ -z $ngfx || ! -x $ngfx ]]; then
    echo "error: Nsight Graphics CLI not found; set LANIUS_NGFX_BIN" >&2
    exit 2
fi

if [[ -z $output_dir ]]; then
    output_dir="${TMPDIR:-/tmp}/laniusc-ngfx-traces/$(date +%Y%m%d-%H%M%S)"
fi
output_dir=$(readlink -m -- "$output_dir")

max_duration_ms=${LANIUS_NGFX_MAX_DURATION_MS:-9999}
if [[ ! $max_duration_ms =~ ^[1-9][0-9]{0,3}$ ]]; then
    echo "error: LANIUS_NGFX_MAX_DURATION_MS must be an integer from 1 through 9999" >&2
    exit 2
fi
if [[ -n ${LANIUS_NGFX_START_SUBMIT+x} || -n ${LANIUS_NGFX_LIMIT_SUBMITS+x} ]]; then
    echo "error: submit windows cannot prove full coverage; use the SDK workload boundary" >&2
    exit 2
fi
if [[ ${LANIUS_NGFX_MULTI_PASS:-0} != 0 ]]; then
    echo "error: multi-pass capture needs a repeatable workload protocol; use one SDK-bounded pass" >&2
    exit 2
fi

if [[ -z $working_dir ]]; then
    working_dir=$(dirname -- "$target")
elif [[ ! -d $working_dir ]]; then
    echo "error: working directory does not exist: $working_dir" >&2
    exit 2
else
    working_dir=$(readlink -f -- "$working_dir")
fi
target_args=""
if (($#)); then
    printf -v target_args '%q ' "$@"
    target_args=${target_args% }
fi

command=(
    "$ngfx"
    "--activity=GPU Trace Profiler"
    "--platform=Linux (x86_64)"
    "--hostname=localhost"
    "--no-timeout"
    "--exe=$target"
    "--dir=$working_dir"
    "--start-with-ngfx-sdk"
    "--stop-with-ngfx-sdk"
    "--max-duration-ms=$max_duration_ms"
    "--allocated-event-buffer-memory-kb=${LANIUS_NGFX_EVENT_BUFFER_KB:-500000}"
    "--allocated-timestamps=${LANIUS_NGFX_TIMESTAMPS:-1000000}"
    "--pc-samples-per-pm-interval-per-sm=${LANIUS_NGFX_PC_SAMPLES:-1024}"
    "--architecture=${LANIUS_NGFX_ARCHITECTURE:-Ampere GA10x}"
    "--metric-set-name=${LANIUS_NGFX_METRIC_SET:-Throughput Metrics}"
    "--set-gpu-clocks=unaltered"
    "--time-every-action"
    "--auto-export"
    "--output-dir=$output_dir"
)
if [[ ${LANIUS_NGFX_REAL_TIME_SHADER:-1} == 1 ]]; then
    command+=("--real-time-shader-profiler")
fi
if [[ -n $target_args ]]; then
    command+=("--args=$target_args")
fi

printf 'Nsight output: %s\n' "$output_dir" >&2
printf 'Command:' >&2
printf ' %q' "${command[@]}" >&2
printf '\n' >&2

if ((dry_run)); then
    exit 0
fi

mkdir -p -- "$output_dir"
# Never validate an older capture or a receipt left by an earlier workload.
if [[ -n $(find "$output_dir" -mindepth 1 -print -quit) ]]; then
    echo "error: capture output directory must be empty: $output_dir" >&2
    exit 2
fi
sdk_include=${LANIUS_NGFX_SDK_INCLUDE:-}
if [[ -z $sdk_include ]]; then
    ngfx_root=$(cd -- "$(dirname -- "$ngfx")/../.." && pwd)
    mapfile -t sdk_headers < <(find "$ngfx_root/SDKs/NsightGraphicsSDK" \
        -name NGFX_GPUTrace_Vulkan.h 2>/dev/null | sort -V)
    if ((${#sdk_headers[@]})); then
        sdk_include=$(dirname -- "${sdk_headers[-1]}")
    fi
fi
if [[ ! -f $sdk_include/NGFX_GPUTrace_Vulkan.h ]]; then
    echo "error: NGFX SDK headers not found; set LANIUS_NGFX_SDK_INCLUDE" >&2
    exit 2
fi
export LANIUS_NGFX_CONTROL_LIBRARY="$output_dir/liblanius_ngfx_control.so"
"${CC:-cc}" -shared -fPIC -O2 -I "$sdk_include" \
    "$script_dir/nsight_capture_control.c" -o "$LANIUS_NGFX_CONTROL_LIBRARY" -ldl
export LANIUS_NGFX_CAPTURE_TOKEN
LANIUS_NGFX_CAPTURE_TOKEN=$(python3 -c 'import uuid; print(uuid.uuid4().hex)')
export LANIUS_NGFX_COMPLETION_FILE="$output_dir/workload-complete.json"
export LANIUS_BACKEND="${LANIUS_NGFX_BACKEND:-vulkan}"
export LANIUS_TRACE="${LANIUS_TRACE:+$LANIUS_TRACE,}gpu-labels"
set +e
"${command[@]}" 2>&1 | tee "$output_dir/nsight.log"
statuses=("${PIPESTATUS[@]}")
set -e
if [[ -n ${LANIUS_NGFX_LOG_FILE:-} ]]; then
    log_file=$(readlink -m -- "$LANIUS_NGFX_LOG_FILE")
    mkdir -p -- "$(dirname -- "$log_file")"
    if [[ $log_file != "$output_dir/nsight.log" ]]; then
        cp -- "$output_dir/nsight.log" "$log_file"
    fi
fi
if ((statuses[0] != 0 || statuses[1] != 0)); then
    echo "error: Nsight capture/export failed (${statuses[*]}); capture is incomplete" >&2
    exit 1
fi
python3 "$script_dir/validate_nsight_capture.py" "$output_dir" \
    "$LANIUS_NGFX_CAPTURE_TOKEN" "$max_duration_ms"
