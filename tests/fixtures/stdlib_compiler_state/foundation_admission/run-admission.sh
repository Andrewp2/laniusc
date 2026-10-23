#!/usr/bin/env bash
# Diagnostic probes only. Run from the repository root under the shared GPU lock.
set -euo pipefail
probe_dir=tests/fixtures/stdlib_compiler_state/foundation_admission
work_dir=target/stdlib-work/foundation-admission-5174a14d
compiler=${LANIUSC:-target/stdlib-build/debug/laniusc}
stdlib_root=${ADMISSION_STDLIB_ROOT:-stdlib}
mkdir -p "$work_dir/stdlib"
rm -rf -- "$work_dir/stdlib/core" "$work_dir/stdlib/alloc" "$work_dir/stdlib/std" "$work_dir/stdlib/test"
cp -R "$stdlib_root/." "$work_dir/stdlib/"
cp "$probe_dir/prototype/alloc/admission_state.lani" "$work_dir/stdlib/alloc/"
cp "$probe_dir/prototype/core/admission_static_iter.lani" "$work_dir/stdlib/core/"
cp "$probe_dir/prototype/core/admission_forward.lani" "$work_dir/stdlib/core/"
cp tests/fixtures/stdlib_foundation/iterator_dependency/core/pull_probe.lani "$work_dir/stdlib/core/"
cp tests/fixtures/stdlib_foundation/buffered_io_dependency/core/buffer_probe.lani "$work_dir/stdlib/core/"
sha256sum "$compiler" >"$work_dir/compiler.sha256"
if [[ -n ${ADMISSION_SOURCE_HEAD:-} ]]; then
    printf '%s\n' "$ADMISSION_SOURCE_HEAD" >"$work_dir/source-head.txt"
else
    git rev-parse HEAD >"$work_dir/source-head.txt"
fi
: >"$work_dir/results.txt"
run_case() {
    local label=$1
    local entry=$2
    local compile_status
    local run_status=not-run
    if timeout --kill-after=1s 7s "$compiler" --stdlib-root "$work_dir/stdlib" "$entry" -o "$work_dir/$label" >"$work_dir/$label.compile.log" 2>&1; then
        compile_status=0
    else
        compile_status=$?
    fi
    if [[ $compile_status -eq 0 ]]; then
        if timeout --kill-after=0.5s 0.5s "$work_dir/$label" >"$work_dir/$label.stdout" 2>"$work_dir/$label.stderr"; then
            run_status=0
        else
            run_status=$?
        fi
    fi
    printf '%s compile=%s run=%s\n' "$label" "$compile_status" "$run_status" >>"$work_dir/results.txt"
}
run_case shared-state-control tests/fixtures/stdlib_foundation/owned_sets_hash_map_control.lani
run_case shared-state "$probe_dir/shared_state.lani"
run_case static-iter-control tests/fixtures/stdlib_foundation/iterator_dependency/direct_control.lani
run_case static-iter "$probe_dir/static_iter.lani"
run_case forward-control tests/fixtures/stdlib_foundation/buffered_io_dependency/direct_control.lani
run_case forward "$probe_dir/forward.lani"
cat "$work_dir/results.txt"
