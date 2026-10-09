#!/usr/bin/env bash
set -euo pipefail

# Alter the admitted implementation, not a proof model. No old program-specific
# proof artifact is loaded after this mutation.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="$root/target/verified-compiler/match-binding-guard-mutation"
input="$root/target/verified-compiler/match-bindings/SelfCore.lean"
mkdir -p "$out"
sed '/^def Extracted.«verified::lean_typed_body».Functions.«surface_match_output» /,/^$/ {
  s/while («binding» < («arm»).«binding_count»)/while («binding» <= («arm»).«binding_count»)/;
}' "$input" > "$out/SelfCore.lean"
if cmp -s "$input" "$out/SelfCore.lean"; then echo 'binding guard mutation changed nothing' >&2; exit 1; fi
cd "$root/formal"
lean="$(lake env sh -c 'command -v lean')"
base="$(lake env printenv LEAN_PATH)"
rm -f "$out/SelfCore.olean" "$out/Guard.olean"
/usr/bin/time -f 'mutated self admission: %e s' lake run checkExtraction -- \
  -R "$out" -o "$out/SelfCore.olean" "$out/SelfCore.lean"
cp "$root/verified_compiler/tests/direct_match_binding_guard.lean" "$out/Guard.lean"
status=0
LEAN_PATH="$out:$base" "$lean" -R "$out" -o "$out/Guard.olean" "$out/Guard.lean" > "$out/contract.log" 2>&1 || status=$?
if [[ "$status" -ne 1 || -e "$out/Guard.olean" ]] ||
    rg -q 'maximum.*(heartbeats|recursion depth)|index out of bounds|unknown (constant|identifier|tactic)|lean\.(unknownIdentifier|invalidField|invalidDottedIdent)' "$out/contract.log" ||
    ! rg -Uq "'MatchBindingGuardTests.stopsEmpty' depends on axioms: \\[[^]]*sorryAx" "$out/contract.log"; then
  cat "$out/contract.log"
  echo "binding guard mutation was not rejected cleanly (status $status)" >&2; exit 1
fi
echo 'wrong binding bound: data admitted, empty-loop execution contract rejected, no proof artifact'
