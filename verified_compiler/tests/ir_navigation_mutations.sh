#!/usr/bin/env bash
set -euo pipefail

# Mutate only the actual extracted navigation implementations. Wrong programs
# still admit as data, but must fail their public contracts without an .olean.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
module="$(realpath "${1:-$root/target/verified-compiler/SelfCore.lean}")"
out="${2:-$root/target/verified-compiler/ir-navigation/mutations}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
base_path="$(cd "$root/formal" && lake env printenv LEAN_PATH)"
lean="$(cd "$root/formal" && lake env sh -c 'command -v lean')"
mutations=(subtree-index sibling-candidate sibling-boundary sibling-result)
if (($# > 2)); then mutations=("${@:3}"); fi
for mutation in "${mutations[@]}"; do
  dir="$out/$mutation"
  mkdir -p "$dir"
  function=next_sibling
  contract=IRNavigationProof.sibling_reads
  case "$mutation" in
    subtree-index)
      function=subtree_end
      contract=IRNavigationProof.subtree_reads
      change='s/return «ends»\[«index»\]/return «ends»[0]/' ;;
    sibling-candidate) change='s/«ends»\[«current»\]/«ends»[«parent»]/' ;;
    sibling-boundary) change='s/«next» >= «ends»/«next» > «ends»/' ;;
    sibling-result) change='s/return «next»/return «current»/' ;;
    *) echo "unknown IR navigation mutation: $mutation" >&2; exit 2 ;;
  esac
  sed '/^def Extracted.«ir::body_tree».Functions.«'"$function"'» /,/^$/ {'"$change"';}' \
    "$module" > "$dir/SelfCore.lean"
  if cmp -s "$module" "$dir/SelfCore.lean"; then
    echo "$mutation did not change the extracted function" >&2
    exit 1
  fi
  (cd "$root/formal" && lake run checkExtraction -- -R "$dir" \
    -o "$dir/SelfCore.olean" "$dir/SelfCore.lean") > "$dir/admission.log" 2>&1
  rm -f "$dir/Contract.olean"
  status=0
  env LEAN_PATH="$dir:$base_path" "$lean" -R "$root" -o "$dir/Contract.olean" \
    "$root/verified_compiler/tests/direct_ir_navigation.lean" > "$dir/contract.log" 2>&1 || status=$?
  if [[ "$status" -ne 1 || -e "$dir/Contract.olean" ]] ||
      rg -q 'maximum.*(heartbeats|recursion depth)|index out of bounds' "$dir/contract.log"; then
    echo "$mutation did not fail the contract cleanly (status $status)" >&2
    exit 1
  fi
  if ! rg -Uq "'$contract' depends on axioms: \\[[^]]*sorryAx" "$dir/contract.log"; then
    echo "$mutation did not fail the expected public contract" >&2
    exit 1
  fi
  echo "$mutation: data admitted, public navigation contract rejected, no proof artifact"
done
