#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="$root/target/verified-compiler/match-dispatch-mutation"
input="${1:-$root/target/verified-compiler/match-arm-composition/SelfCore.lean}"
mkdir -p "$out"
sed '/^def Extracted.«verified::lean_typed_body».Functions.«surface_expression_output» /,/^$/ {
  /ExpressionMatch/ s/(true)/(false)/;
}' "$input" > "$out/SelfCore.lean"
if cmp -s "$input" "$out/SelfCore.lean"; then echo 'match dispatch mutation changed nothing' >&2; exit 1; fi
cd "$root/formal"
lean="$(lake env sh -c 'command -v lean')"
base="$(lake env printenv LEAN_PATH)"
rm -f "$out/SelfCore.olean" "$out/Guard.olean" "$out/Changed.olean"
/usr/bin/time -f 'mutated self admission: %e s' lake run checkExtraction -- \
  -R "$out" -o "$out/SelfCore.olean" "$out/SelfCore.lean"
cp "$root/verified_compiler/tests/direct_match_dispatch_guard.lean" "$out/Guard.lean"
sed 's/(arguments true)/(arguments false)/; s/alwaysEncloses/changedArgument/g' \
  "$out/Guard.lean" > "$out/Changed.lean"
LEAN_PATH="$out:$base" "$lean" -R "$out" -o "$out/Changed.olean" "$out/Changed.lean"
status=0
LEAN_PATH="$out:$base" "$lean" -R "$out" -o "$out/Guard.olean" "$out/Guard.lean" > "$out/contract.log" 2>&1 || status=$?
if [[ "$status" -ne 1 || -e "$out/Guard.olean" ]] ||
    rg -q 'maximum.*(heartbeats|recursion depth)|unknown (constant|identifier|tactic)|lean\.(unknownIdentifier|invalidField|invalidDottedIdent)' "$out/contract.log" ||
    ! rg -Uq "'MatchDispatchGuardTests.alwaysEncloses' depends on axioms: \\[[^]]*sorryAx" "$out/contract.log"; then
  cat "$out/contract.log"
  echo "wrong match argument was not rejected cleanly (status $status)" >&2; exit 1
fi
echo 'wrong match argument: fresh data admitted, false argument proved, required true argument rejected without artifact'
