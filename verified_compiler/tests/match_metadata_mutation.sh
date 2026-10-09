#!/usr/bin/env bash
set -euo pipefail

# Rebuild admission and the binding contracts for the altered program; no
# program-specific proof artifact is reused across the mutation.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="$root/target/verified-compiler/match-metadata-mutation"
input="$root/target/verified-compiler/match-metadata/SelfCore.lean"
mkdir -p "$out"
sed '/^def Extracted.«verified::lean_body_shape».Functions.«match_binding_id» /,/^$/ {
  s/return («binding»).«id»/return 0/;
}' "$input" > "$out/SelfCore.lean"
if cmp -s "$input" "$out/SelfCore.lean"; then echo 'binding mutation changed nothing' >&2; exit 1; fi
{
  printf 'import SelfCore\nimport Lanius.Semantics.CallProof\nimport Lanius.Semantics.PureProof\nimport Lanius.Semantics.SourceValue\n'
  printf 'namespace MatchMetadataProof\nopen Lanius Lanius.Core Lanius.Semantics\n'
  sed -n '/^private def bindingSource/,/^\/-- The match emitter/ {
    /^\/-- The match emitter/q; p;
  }' "$root/verified_compiler/tests/direct_match_metadata.lean"
  sed -n '/^@\[core_pure_rule\] theorem actualBinding /,/^\/-- Native binding/ {
    /^\/-- Native binding/q; p;
  }' "$root/verified_compiler/tests/direct_match_metadata.lean"
  printf '#print axioms actualBindingId\nend MatchMetadataProof\n'
} > "$out/Binding.lean"
cd "$root/formal"
lean="$(lake env sh -c 'command -v lean')"
base="$(lake env printenv LEAN_PATH)"
rm -f "$out/SelfCore.olean" "$out/Binding.olean"
/usr/bin/time -f 'mutated self admission: %e s' lake run checkExtraction -- \
  -R "$out" -o "$out/SelfCore.olean" "$out/SelfCore.lean"
status=0
LEAN_PATH="$out:$base" "$lean" -R "$out" -o "$out/Binding.olean" "$out/Binding.lean" \
  > "$out/contract.log" 2>&1 || status=$?
if [[ "$status" -ne 1 || -e "$out/Binding.olean" ]] ||
    rg -q 'maximum.*(heartbeats|recursion depth)|index out of bounds|unknown (constant|identifier|tactic)|lean\.(unknownIdentifier|invalidField|invalidDottedIdent)' "$out/contract.log" ||
    ! rg -Uq "'MatchMetadataProof.actualBindingId' depends on axioms: \\[[^]]*sorryAx" "$out/contract.log"; then
  cat "$out/contract.log"
  echo "binding mutation was not rejected cleanly (status $status)" >&2; exit 1
fi
echo 'wrong binding ID: data admitted, actual execution contract rejected, no proof artifact'
