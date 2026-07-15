#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
guard="$repo_root/tools/nvidia_gpu_guard.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fake_bin="$tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *query-compute-apps* ]]; then
  [[ -f "${FAKE_COMPUTE_FILE:-}" ]] && cat "$FAKE_COMPUTE_FILE"
  exit 0
fi
count=0
if [[ -f "$FAKE_SAMPLE_COUNT" ]]; then
  count="$(<"$FAKE_SAMPLE_COUNT")"
fi
mapfile -t samples <"$FAKE_SAMPLE_FILE"
index="$count"
if (( index >= ${#samples[@]} )); then
  index=$((${#samples[@]} - 1))
fi
printf '%s\n' "${samples[$index]}"
printf '%s\n' "$((count + 1))" >"$FAKE_SAMPLE_COUNT"
EOF
chmod +x "$fake_bin/nvidia-smi"

cat >"$fake_bin/journalctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${FAKE_JOURNAL_FAIL:-0}" == 1 ]]; then
  printf 'journal unavailable\n' >&2
  exit 1
fi
if [[ "$*" == *--since=* ]]; then
  [[ -f "${FAKE_LIVE_JOURNAL_FILE:-}" ]] && cat "$FAKE_LIVE_JOURNAL_FILE"
else
  [[ -f "${FAKE_BOOT_JOURNAL_FILE:-}" ]] && cat "$FAKE_BOOT_JOURNAL_FILE"
fi
EOF
chmod +x "$fake_bin/journalctl"

export PATH="$fake_bin:$PATH"
export LANIUS_GPU_GUARD_NVIDIA_SMI="$fake_bin/nvidia-smi"
export LANIUS_GPU_GUARD_JOURNALCTL="$fake_bin/journalctl"
export LANIUS_GPU_GUARD_LOCK_PATH="$tmp/guard.lock"
export LANIUS_GPU_GUARD_POLL_MS=20
export LANIUS_GPU_GUARD_TIMEOUT_SECONDS=3
export FAKE_SAMPLE_FILE="$tmp/samples"
export FAKE_SAMPLE_COUNT="$tmp/sample-count"
export FAKE_BOOT_JOURNAL_FILE="$tmp/boot-journal"
export FAKE_LIVE_JOURNAL_FILE="$tmp/live-journal"
export FAKE_COMPUTE_FILE="$tmp/compute"
touch "$FAKE_BOOT_JOURNAL_FILE" "$FAKE_LIVE_JOURNAL_FILE" "$FAKE_COMPUTE_FILE"

reset_samples() {
  rm -f "$FAKE_SAMPLE_COUNT"
  printf '%s\n' "$@" >"$FAKE_SAMPLE_FILE"
}

expect_status() {
  local expected="$1"
  shift
  local status=0
  "$@" >"$tmp/stdout" 2>"$tmp/stderr" || status=$?
  if [[ "$status" -ne "$expected" ]]; then
    printf 'expected status %s, got %s\n' "$expected" "$status" >&2
    cat "$tmp/stderr" >&2
    exit 1
  fi
}

reset_samples '1000, 24000, 50'
success_log="$tmp/success.csv"
expect_status 0 "$guard" --log "$success_log" -- sh -c 'exit 0'
grep -q '^timestamp_utc,elapsed_seconds,memory_used_mib' "$success_log"

reset_samples '8000, 24000, 50'
expect_status 78 "$guard" -- sh -c 'exit 0'
grep -q 'initial framebuffer use' "$tmp/stderr"

reset_samples '1000, 24000, 50'
printf '%s\n' 'NVRM: Xid (PCI:0000:01:00): 31' >"$FAKE_BOOT_JOURNAL_FILE"
expect_status 78 "$guard" -- sh -c 'exit 0'
grep -q 'current boot already contains' "$tmp/stderr"
>"$FAKE_BOOT_JOURNAL_FILE"

reset_samples '1000, 24000, 50'
export FAKE_JOURNAL_FAIL=1
expect_status 78 "$guard" -- sh -c 'exit 0'
grep -q 'could not inspect the current kernel journal' "$tmp/stderr"
unset FAKE_JOURNAL_FAIL

reset_samples '1000, 24000, 50' '20000, 24000, 50'
expect_status 125 "$guard" -- sh -c 'while :; do sleep 1; done'
grep -q 'framebuffer use' "$tmp/stderr"

reset_samples '1000, 24000, 50'
printf '%s\n' 'Failed to map NvKmsKapiMemory 0x1' >"$FAKE_LIVE_JOURNAL_FILE"
expect_status 125 "$guard" -- sh -c 'while :; do sleep 1; done'
grep -q 'new NVIDIA mapping or Xid kernel error' "$tmp/stderr"
>"$FAKE_LIVE_JOURNAL_FILE"

reset_samples '1000, 24000, 50'
printf '%s\n' '999,other-compute,512' >"$FAKE_COMPUTE_FILE"
expect_status 0 "$guard" -- sh -c 'exit 0'
grep -q 'starting GPU 0 workload' "$tmp/stderr"

printf 'nvidia_gpu_guard_test: PASS\n'
