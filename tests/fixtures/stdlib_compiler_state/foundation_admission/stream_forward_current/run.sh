#!/usr/bin/env bash
# Run from the repository root under the shared GPU lock; inspect every status.
set -euo pipefail
work=${ADMISSION_WORK_DIR:-target/stdlib-work/stream-forward-current}
compiler=${LANIUSC:-target/stdlib-build/debug/laniusc}
stdlib_root=${ADMISSION_STDLIB_ROOT:-stdlib}
shader_root=${LANIUS_SHADER_ARTIFACT_ROOT:-target/stdlib-build/laniusc-shader-artifacts/debug/shaders}
if [[ -e "$work" ]]; then
    printf 'admission output already exists: %s\n' "$work" >&2
    exit 2
fi
mkdir -p -- "$work/stdlib" "$work/shaders"
cp -RL -- "$stdlib_root/." "$work/stdlib/"
cp -RL -- "$shader_root/." "$work/shaders/"
cp -- "$compiler" "$work/laniusc"
chmod u+x -- "$work/laniusc"
cp tests/fixtures/stdlib_foundation/buffered_io_dependency/core/buffer_probe.lani "$work/stdlib/core/"
cp tests/fixtures/stdlib_compiler_state/foundation_admission/prototype/core/admission_forward.lani "$work/stdlib/core/"
work=$(realpath "$work")
export LANIUS_SHADER_ARTIFACT_ROOT="$work/shaders"
sha256sum "$work/laniusc" > "$work/compiler.sha256"
if [[ -n ${ADMISSION_SOURCE_HEAD:-} ]]; then
    printf '%s\n' "$ADMISSION_SOURCE_HEAD" > "$work/source-head.txt"
else
    git rev-parse HEAD > "$work/source-head.txt"
fi
: > "$work/results.txt"
run_case() {
    local label=$1 entry=$2 compile_status run_status=not-run
    if timeout --kill-after=1s 8s "$work/laniusc" --stdlib-root "$work/stdlib" "$entry" -o "$work/$label" > "$work/$label.compile.log" 2>&1; then
        compile_status=0
    else
        compile_status=$?
    fi
    if [[ $compile_status -eq 0 ]]; then
        if timeout --kill-after=1s 1s "$work/$label" > "$work/$label.stdout" 2> "$work/$label.stderr"; then
            run_status=0
        else
            run_status=$?
        fi
    fi
    printf '%s compile=%s run=%s\n' "$label" "$compile_status" "$run_status" >> "$work/results.txt"
}
base=tests/fixtures/stdlib_foundation/buffered_io_dependency
run_case imported "$base/main.lani"
run_case direct "$base/direct_control.lani"
run_case local "$base/local_control.lani"
run_case local_impl "$base/local_impl_control.lani"
run_case associated tests/fixtures/stdlib_compiler_state/foundation_admission/forward.lani
cat "$work/results.txt"
