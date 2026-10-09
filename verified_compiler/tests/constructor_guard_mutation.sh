#!/usr/bin/env bash
set -euo pipefail

# No program-specific proof artifact is reused across this changed program.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="$root/target/verified-compiler/constructor-guard-mutation"
input="$root/target/verified-compiler/constructor-payloads/SelfCore.lean"
mkdir -p "$out"
sed '/^def Extracted.«verified::lean_typed_body».Functions.«surface_constructor_output» /,/^$/ {
  s/while («ordinal» < («constructor»).«payload_count»)/while («ordinal» <= («constructor»).«payload_count»)/;
}' "$input" > "$out/SelfCore.lean"
if cmp -s "$input" "$out/SelfCore.lean"; then echo 'guard mutation changed nothing' >&2; exit 1; fi
cd "$root/formal"
lean="$(lake env sh -c 'command -v lean')"
base="$(lake env printenv LEAN_PATH)"
rm -f "$out/SelfCore.olean" "$out/Guard.olean"
/usr/bin/time -f 'mutated self admission: %e s' lake run checkExtraction -- \
  -R "$out" -o "$out/SelfCore.olean" "$out/SelfCore.lean"
cp "$root/verified_compiler/tests/direct_constructor_guard.lean" "$out/Guard.lean"
status=0
LEAN_PATH="$out:$base" "$lean" -R "$out" -o "$out/Guard.olean" "$out/Guard.lean" > "$out/contract.log" 2>&1 || status=$?
if [[ "$status" -ne 1 || -e "$out/Guard.olean" ]] ||
    rg -q 'maximum.*(heartbeats|recursion depth)|index out of bounds|unknown (constant|identifier|tactic)|lean\.(unknownIdentifier|invalidField|invalidDottedIdent)' "$out/contract.log" ||
    ! rg -Uq "'ConstructorGuardTests.stopsEmpty' depends on axioms: \\[[^]]*sorryAx" "$out/contract.log"; then
  cat "$out/contract.log"
  echo "guard mutation was not rejected cleanly (status $status)" >&2; exit 1
fi
echo 'wrong payload bound: data admitted, zero-payload execution contract rejected, no proof artifact'
