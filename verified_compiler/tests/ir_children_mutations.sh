#!/usr/bin/env bash
set -euo pipefail

# These mutants remain valid extracted program data. Recheck the complete
# dependency chain and require the actual traversal contract to reject them.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
module="$(realpath "${1:-$root/target/verified-compiler/SelfCore.lean}")"
out="${2:-$root/target/verified-compiler/ir-children/mutations}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
base_path="$(cd "$root/formal" && lake env printenv LEAN_PATH)"
lean="$(cd "$root/formal" && lake env sh -c 'command -v lean')"
mutations=("${@:3}")
if ((${#mutations[@]} == 0)); then mutations=(allow-cycle stop-counter); fi

for mutation in "${mutations[@]}"; do
  dir="$out/$mutation"
  mkdir -p "$dir/verified_compiler/tests"
  case "$mutation" in
    allow-cycle) change='s/«next» <= «cursor»/«next» < «cursor»/' ;;
    stop-counter) change='s/«child» += 1/«child» += 0/' ;;
    *) echo "unknown child traversal mutation: $mutation" >&2; exit 1 ;;
  esac
  sed '/^def Extracted.«ir::body_tree».Functions.«children_end» /,/^$/ {'"$change"';}' \
    "$module" > "$dir/SelfCore.lean"
  if cmp -s "$module" "$dir/SelfCore.lean"; then
    echo "$mutation did not change the child walker" >&2
    exit 1
  fi
  (cd "$root/formal" && lake run checkExtraction -- -R "$dir" \
    -o "$dir/SelfCore.olean" "$dir/SelfCore.lean") > "$dir/admission.log" 2>&1
  for dependency in direct_ir_type_ref direct_ir_shape; do
    env LEAN_PATH="$dir:$base_path" "$lean" -R "$root" \
      -o "$dir/verified_compiler/tests/$dependency.olean" \
      "$root/verified_compiler/tests/$dependency.lean" > "$dir/$dependency.log" 2>&1
  done
  artifact="$dir/verified_compiler/tests/direct_ir_children.olean"
  rm -f "$artifact"
  status=0
  env LEAN_PATH="$dir:$base_path" "$lean" -R "$root" -o "$artifact" \
    "$root/verified_compiler/tests/direct_ir_children.lean" > "$dir/contract.log" 2>&1 || status=$?
  if [[ "$status" -ne 1 || -e "$artifact" ]]; then
    echo "$mutation did not fail cleanly (status $status)" >&2
    exit 1
  fi
  for contract in actualChildren actualChildrenCorrect; do
    if ! rg -Uq "'IRChildrenProof.$contract' depends on axioms: \\[[^]]*sorryAx" "$dir/contract.log"; then
      echo "$mutation did not fail $contract" >&2
      exit 1
    fi
  done
  if rg -q 'maximum.*(heartbeats|recursion depth)|index out of bounds' "$dir/contract.log"; then
    echo "$mutation hit an infrastructure limit instead of rejecting the wrong behavior" >&2
    exit 1
  fi
  echo "$mutation: data admitted, actual traversal contract rejected, no proof artifact"
done
