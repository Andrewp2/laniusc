#!/usr/bin/env bash
set -euo pipefail

# Fresh self-data, complete builder/traversal proofs, and physical/native fixtures.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
unset LEAN_PATH LEAN_SRC_PATH LEAN_SYSROOT LEAN_OPTS

# Fresh specialized proofs with authenticated current shared foundations.
catalog_check() {
  local root="$1" selfcore="$2" out="$3" mode="$4" lean check
  unset LEAN_PATH LEAN_SRC_PATH LEAN_SYSROOT LEAN_OPTS
  [[ -f "$selfcore/SelfCore.lean" && -f "$selfcore/SelfCore.olean" ]] || {
    echo "missing admitted SelfCore source/artifact pair" >&2; return 2;
  }
  selfcore="$(cd "$selfcore" && pwd)"
  mkdir -p "$out"
  out="$(mktemp -d "$(cd "$out" && pwd)/$mode.XXXXXX")"
  check="$root/verified_compiler/tests/lean-check"
  source "$check/stage.sh" || return
  mkdir -p "$out/metadata" "$out/execution"
  printf 'fresh %s specialized output: %s\n' "$mode" "$out"
  cd "$root/formal"
  checked_stage "$out/toolchain" "$out/lean-bin.txt" data lake env sh -c 'command -v lean' || return
  lean="$(< "$out/lean-bin.txt")"
  [[ -x "$lean" ]] || return 2
  cd "$root"
  checked_stage "$out/metadata" "$out/metadata.log" diagnostics \
    ruby -E UTF-8 "$check/prepare.rb" "$root" "$selfcore" "$out/metadata" "$mode" "$lean" || return
  checked_stage "$out/execution" "$out/execution.log" diagnostics \
    bash "$check/worker.sh" "$out/execution" "$out/metadata" "$root" || return
  cat "$out/metadata.log" "$out/execution.log"
}
if [[ "${1:-}" == --catalog-copy || "${1:-}" == --catalog-build || "${1:-}" == --catalog-store || "${1:-}" == --catalog-append ]]; then
  mode="${1#--}"
  selfcore="${2:?usage: ir_builder_check.sh $1 EXISTING_SELFCORE_DIR [OUT]}"
  out="${3:-$root/target/verified-compiler/$mode}"
  export -f catalog_check
  exec bash "$root/verified_compiler/tests/lean-check/bound.sh" 105 \
    bash -c 'set -euo pipefail; catalog_check "$@"' "$mode" "$root" "$selfcore" "$out" "$mode"
fi

builder_check() {
  local root="$1" extractor out preflight lean source
  shift
  source "$root/verified_compiler/tests/lean-check/stage.sh" || return
  extractor="${1:-$root/target/verified-compiler/extractor-current}"
  out="${2:-$root/target/verified-compiler/ir-builder}"
  mkdir -p "$out" || return
  out="$(cd "$out" && pwd)" || return
  cd "$root/formal" || return
  preflight="$(mktemp -d "$out/foundations.XXXXXX")" || return
  printf 'current builder foundation audit: %s\n' "$preflight"
  checked_stage "$preflight/toolchain" "$preflight/lean-bin.txt" data lake env sh -c 'command -v lean' || return
  lean="$(< "$preflight/lean-bin.txt")"
  [[ -x "$lean" ]] || return 2
  checked_stage "$preflight/provenance" '' diagnostics ruby -E UTF-8 "$root/verified_compiler/tests/lean-check/prepare.rb" \
    "$root" "$out" "$preflight" builder "$lean" preflight || return
  rm -f .lake/build/lib/lean/Lanius/Extraction/CurrentSourceClosure.trace || return
  checked_stage "$preflight/lake-build" '' diagnostics lake --no-cache build +Lanius.Extraction.CurrentSourceClosure +Lanius.Semantics.NativeReadFrame \
    +Lanius.Semantics.CountedLocal +Lanius.Semantics.PureProof +Lanius.Semantics.HostCall \
    +Lanius.Semantics.RawStore +Lanius.Semantics.RawSlice +Lanius.Semantics.SourceValue \
    +Lanius.Core.Bindings +Lanius.Extraction.OutputPacking.Byte || return
  checked_stage "$preflight/source-boundary" '' diagnostics lake env lean -R .. --run ../verified_compiler/tests/direct_source_boundary.lean || return
  checked_stage "$preflight/source-list" "$preflight/extractor-sources.txt" data lake env lean -R .. --run ../verified_compiler/tests/print_extractor_sources.lean || return
  mapfile -t sources < "$preflight/extractor-sources.txt" || return
  if ((${#sources[@]} == 0)); then echo "empty source closure" >&2; return 1; fi
  for source in "${sources[@]}"; do
    [[ "$source" == verified_compiler/src/*.lani && -f "$root/$source" ]] || { echo "invalid source-list entry: $source" >&2; return 2; }
  done
  (cd "$root" && checked_stage "$preflight/emission" "$out/SelfCore.lean" data "$extractor" "${sources[@]}") || return
  checked_stage "$preflight/syntax-header" '' diagnostics ruby -E UTF-8 "$root/verified_compiler/tests/lean-check/prepare.rb" \
    "$root" "$out" "$preflight" builder "$lean" syntax-header || return
  checked_stage "$preflight/admission" '' diagnostics lake run checkExtraction -- \
    -R "$out" -o "$out/SelfCore.olean" "$out/SelfCore.lean" || return
  catalog_check "$root" "$out" "$out" builder
}
export -f catalog_check builder_check
exec bash "$root/verified_compiler/tests/lean-check/bound.sh" 105 \
  bash -c 'set -euo pipefail; builder_check "$@"' builder "$root" "$@"
