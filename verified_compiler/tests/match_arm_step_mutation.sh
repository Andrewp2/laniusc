#!/usr/bin/env bash
set -euo pipefail

# Fresh admission and execution of a wrong outer increment. Never load the
# old program's printer proof artifacts for the changed program.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="$root/target/verified-compiler/match-arm-step-mutation"
input="${1:-$root/target/verified-compiler/match-arm-composition/SelfCore.lean}"
mkdir -p "$out"
sed '/^def Extracted.«verified::lean_typed_body».Functions.«surface_match_output» /,/^$/ {
  s/«ordinal» += 1/«ordinal» += 2/;
}' "$input" > "$out/SelfCore.lean"
if cmp -s "$input" "$out/SelfCore.lean"; then echo 'arm increment mutation changed nothing' >&2; exit 1; fi
cd "$root/formal"
lean="$(lake env sh -c 'command -v lean')"
base="$(lake env printenv LEAN_PATH)"
rm -f "$out/SelfCore.olean" "$out/Guard.olean" "$out/Changed.olean"
/usr/bin/time -f 'mutated self admission: %e s' lake run checkExtraction -- \
  -R "$out" -o "$out/SelfCore.olean" "$out/SelfCore.lean"
cp "$root/verified_compiler/tests/direct_match_arm_step.lean" "$out/Guard.lean"
sed 's/(.signed .i32 1)/(.signed .i32 2)/g; s/(replacement := 1)/(replacement := 2)/g;
  s/theorem increments/theorem changedIncrement/; s/#print axioms increments/#print axioms changedIncrement/' \
  "$out/Guard.lean" > "$out/Changed.lean"
LEAN_PATH="$out:$base" "$lean" -R "$out" -o "$out/Changed.olean" "$out/Changed.lean"
status=0
LEAN_PATH="$out:$base" "$lean" -R "$out" -o "$out/Guard.olean" "$out/Guard.lean" > "$out/contract.log" 2>&1 || status=$?
if [[ "$status" -ne 1 || -e "$out/Guard.olean" ]] ||
    rg -q 'maximum.*(heartbeats|recursion depth)|unknown (constant|identifier|tactic)|lean\.(unknownIdentifier|invalidField|invalidDottedIdent)' "$out/contract.log" ||
    ! rg -Uq "'MatchArmStepTests.increments' depends on axioms: \\[[^]]*sorryAx" "$out/contract.log"; then
  cat "$out/contract.log"
  echo "wrong arm increment was not rejected cleanly (status $status)" >&2; exit 1
fi
echo 'wrong arm increment: data admitted, actual +2 proved, required +1 rejected without artifact'
