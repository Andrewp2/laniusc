#!/usr/bin/env bash
set -euo pipefail

# Admission and the actual guard proof are fresh for this altered program.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="$root/target/verified-compiler/match-arm-guard-mutation"
input="$root/target/verified-compiler/match-bindings/SelfCore.lean"
mkdir -p "$out"
sed '/^def Extracted.«ir::body_tree».Functions.«arm_shape» /,/^$/ {
  s/(«arm»).«binding_count» != 0/(«arm»).«binding_count» == 0/;
}' "$input" > "$out/SelfCore.lean"
if cmp -s "$input" "$out/SelfCore.lean"; then echo 'arm mutation changed nothing' >&2; exit 1; fi
cd "$root/formal"
lean="$(lake env sh -c 'command -v lean')"
base="$(lake env printenv LEAN_PATH)"
rm -f "$out/SelfCore.olean" "$out/Guard.olean" "$out/FalseGuard.olean"
/usr/bin/time -f 'mutated self admission: %e s' lake run checkExtraction -- \
  -R "$out" -o "$out/SelfCore.olean" "$out/SelfCore.lean"
cp "$root/verified_compiler/tests/direct_match_arm_guard.lean" "$out/Guard.lean"
sed -e 's/(.boolean true)/(.boolean false)/' -e 's/rejectsWildcard/changedGuardIsFalse/g' \
  "$out/Guard.lean" > "$out/FalseGuard.lean"
LEAN_PATH="$out:$base" "$lean" -R "$out" -o "$out/FalseGuard.olean" "$out/FalseGuard.lean"
status=0
LEAN_PATH="$out:$base" "$lean" -R "$out" -o "$out/Guard.olean" "$out/Guard.lean" > "$out/contract.log" 2>&1 || status=$?
if [[ "$status" -ne 1 || -e "$out/Guard.olean" ]] ||
    rg -q 'maximum.*(heartbeats|recursion depth)|index out of bounds|unknown (constant|identifier|tactic)|lean\.(unknownIdentifier|invalidField|invalidDottedIdent)' "$out/contract.log" ||
    ! rg -Uq "'MatchArmGuardTests.rejectsWildcard' depends on axioms: \\[[^]]*sorryAx" "$out/contract.log"; then
  cat "$out/contract.log"
  echo "arm mutation was not rejected cleanly (status $status)" >&2; exit 1
fi
echo 'inverted wildcard count: data admitted, actual false guard proved, required true guard rejected without artifact'
