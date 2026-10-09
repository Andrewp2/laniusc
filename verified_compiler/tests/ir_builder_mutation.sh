#!/usr/bin/env bash
set -euo pipefail

# Wrong builder/traversal code still admits as data, but cannot satisfy its
# actual-code contracts. Recheck dependencies against the mutated data.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
module="$(realpath "${1:-$root/target/verified-compiler/SelfCore.lean}")"
dir="${2:-$root/target/verified-compiler/ir-builder/stop-counter}"
kind="${3:-counter}"
function=build
mkdir -p "$dir/verified_compiler/tests"
dir="$(cd "$dir" && pwd)"
case "$kind" in
  counter)
    edit='s/«index» -= 1/«index» -= 0/'
    component=builder
    contracts=(IRBuilderProof.actualIteration IRBuilderProof.actualLoop)
    dependencies=(type_ref shape children allocation)
    ;;
  root)
    edit='s/if («ends»\[0\] != «count»)/if («count» != «count»)/'
    component=builder_call
    contracts=(IRBuilderCallProof.actualRoot IRBuilderCallProof.actualCall)
    dependencies=(type_ref shape children allocation builder)
    ;;
  first-child)
    function=first_child
    edit='s/return («parent» + 1)/return («parent»)/'
    component=builder_navigation
    contracts=(IRBuilderNavigationProof.Ready.firstChild)
    dependencies=(type_ref shape children allocation builder builder_call navigation)
    ;;
  *) echo "unknown builder/traversal mutation: $kind" >&2; exit 1 ;;
esac
sed "/^def Extracted.«ir::body_tree».Functions.«$function» /,/^$/ {$edit;}" "$module" > "$dir/SelfCore.lean"
if cmp -s "$module" "$dir/SelfCore.lean"; then echo "mutation did not change $function" >&2; exit 1; fi
cd "$root/formal"
lake run checkExtraction -- -R "$dir" -o "$dir/SelfCore.olean" "$dir/SelfCore.lean" > "$dir/admission.log" 2>&1
lean="$(lake env sh -c 'command -v lean')"
base_path="$(lake env printenv LEAN_PATH)"
for dependency in "${dependencies[@]}"; do
  env LEAN_PATH="$dir:$base_path" "$lean" -R "$root" \
    -o "$dir/verified_compiler/tests/direct_ir_$dependency.olean" \
    "$root/verified_compiler/tests/direct_ir_$dependency.lean" > "$dir/$dependency.log" 2>&1
done
artifact="$dir/verified_compiler/tests/direct_ir_$component.olean"
rm -f "$artifact"
status=0
env LEAN_PATH="$dir:$base_path" "$lean" -R "$root" -o "$artifact" \
  "$root/verified_compiler/tests/direct_ir_$component.lean" > "$dir/contract.log" 2>&1 || status=$?
if [[ "$status" -ne 1 || -e "$artifact" ]] ||
    rg -q 'maximum.*(heartbeats|recursion depth)|index out of bounds' "$dir/contract.log"; then
  echo "wrong builder $kind was not rejected cleanly (status $status)" >&2; exit 1
fi
for contract in "${contracts[@]}"; do
  if ! rg -Uq "'$contract' depends on axioms: \\[[^]]*sorryAx" "$dir/contract.log"; then
    echo "wrong builder $kind did not reject $contract" >&2; exit 1
  fi
done
echo "$kind: data admitted, actual contracts rejected, no proof artifact"
