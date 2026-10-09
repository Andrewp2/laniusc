#!/usr/bin/env bash
set -euo pipefail

# Fresh connected name proofs, reusing admission and primitive writers only
# for byte-identical extractor output. This is not fresh artifact admission.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${1:-$root/target/verified-compiler/declaration-names}"
kind="${2:-positive}"
cache="$root/target/verified-compiler/identifiers/positive"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
if [[ "$kind" == wrong-unit-bound || "$kind" == wrong-type-bound ]]; then
  function=declaration_identifier
  namespace=DeclarationNameProof
  theorem=rejectsUnit
  artifact=RejectsUnit
  if [[ "$kind" == wrong-type-bound ]]; then
    function=type_identifier
    namespace=TypeNameProof
    theorem=rejectsIndex
    artifact=RejectsIndex
  fi
  input="${3:-$root/target/verified-compiler/declaration-names/SelfCore.lean}"
  if [[ "$(realpath "$input")" == "$out/SelfCore.lean" ]]; then
    echo 'mutation output must differ from its input directory' >&2; exit 2
  fi
  sed "/^def Extracted.«verified::lean_syntax».Functions.«$function» /,/^$/ {
    s/ >= / > /;
  }" "$input" > "$out/SelfCore.lean"
  if cmp -s "$input" "$out/SelfCore.lean"; then echo "$kind mutation changed nothing" >&2; exit 1; fi
  cd "$root/formal"
  rm -f "$out/SelfCore.olean" "$out/$artifact.olean"
  /usr/bin/time -f 'mutated self admission: %e s' lake run checkExtraction -- \
    -R "$out" -o "$out/SelfCore.olean" "$out/SelfCore.lean"
  {
    printf 'import SelfCore\nimport Lanius.Semantics.CallProof\nimport Lanius.Semantics.PureProof\nimport Lanius.Semantics.SourceValue\n'
    sed -n '/^namespace SymbolSpellingProof/,/^structure UnitSpan/ {
      /^structure UnitSpan/q;
      p;
    }' "$root/verified_compiler/tests/direct_symbol_spelling.lean"
    printf 'end SymbolSpellingProof\nnamespace %s\nopen Lanius Lanius.Core Lanius.Semantics SymbolSpellingProof\n' "$namespace"
    if [[ "$kind" == wrong-unit-bound ]]; then
      sed -n '/^def source :=/p; /^private theorem sourceFound/p' "$root/verified_compiler/tests/direct_declaration_name.lean"
      sed -n '/^abbrev Space :=/,/^def namespaceText/ {
        /^def namespaceText/q;
        p;
      }' "$root/verified_compiler/tests/direct_declaration_name.lean"
      sed -n '/^theorem rejectsUnit/,/^#print axioms iteration/ {
        /^#print axioms iteration/q;
        p;
      }' "$root/verified_compiler/tests/direct_declaration_name.lean"
    else
      sed -n '/^private def identifierSource :=/p' "$root/verified_compiler/tests/direct_type_name.lean"
      sed -n '/^theorem rejectsIndex/,/^\/-- The nominal arm/ {
        /^\/-- The nominal arm/q;
        p;
      }' "$root/verified_compiler/tests/direct_type_name.lean"
    fi
    printf '#print axioms %s\nend %s\n' "$theorem" "$namespace"
  } > "$out/$artifact.lean"
  lean="$(lake env sh -c 'command -v lean')"
  base="$(lake env printenv LEAN_PATH)"
  status=0
  LEAN_PATH="$out:$base" "$lean" -R "$out" -o "$out/$artifact.olean" "$out/$artifact.lean" \
    > "$out/contract.log" 2>&1 || status=$?
  if [[ "$status" -ne 1 || -e "$out/$artifact.olean" ]] || \
      rg -q 'maximum.*(heartbeats|recursion depth)|Unknown|unknownIdentifier|not found|synthInstanceFailed' "$out/contract.log" || \
      ! rg -Uq "'$namespace.$theorem' depends on axioms: \\[[^]]*sorryAx" "$out/contract.log"; then
    cat "$out/contract.log"
    echo "$kind mutation was not rejected cleanly (status $status)" >&2; exit 1
  fi
  echo "$kind: data admitted, actual rejection contract rejected, no proof artifact"
  exit 0
elif [[ "$kind" != positive ]]; then
  echo "unknown declaration-name check: $kind" >&2; exit 2
fi
for proof in output_byte packed_words output_text output_natural; do
  if [[ ! -f "$cache/SelfOutputByte.olean" || "$root/verified_compiler/tests/direct_$proof.lean" -nt "$cache/SelfOutputByte.olean" ]]; then
    echo "primitive $proof requires rechecking before reuse" >&2; exit 1
  fi
done
cd "$root/formal"
lake --no-cache build +Lanius.Extraction.CurrentSourceClosure +Lanius.Extraction.WriterCounterTests
lake env lean -R .. --run ../verified_compiler/tests/direct_source_boundary.lean
mapfile -t sources < <(lake env lean -R .. --run ../verified_compiler/tests/print_extractor_sources.lean)
if ((${#sources[@]} == 0)); then echo 'empty source closure' >&2; exit 1; fi
(cd "$root" && /usr/bin/time -f 'current self emission: %e s' \
  target/verified-compiler/extractor-current "${sources[@]}" > "$out/SelfCore.lean")
if ! cmp -s "$out/SelfCore.lean" "$cache/SelfCore.lean" || \
    [[ ! -f "$cache/SelfCore.olean" || "$cache/SelfCore.lean" -nt "$cache/SelfCore.olean" ]]; then
  echo 'program differs or lacks admission; recheck admission and primitive writers' >&2; exit 1
fi
cp "$cache/SelfCore.olean" "$cache/SelfOutputByte.olean" "$out/"
proofs=(output_writer surface_boolean symbol_spelling source_identifier escaped_identifier surface_name declaration_name type_name)
{
  printf 'import SelfOutputByte\n'
  for proof in "${proofs[@]}"; do sed -n '/^import Lanius/p' "$root/verified_compiler/tests/direct_$proof.lean"; done | sort -u
  for proof in "${proofs[@]}"; do sed '/^import /d' "$root/verified_compiler/tests/direct_$proof.lean"; done
} > "$out/Names.lean"
lean="$(lake env sh -c 'command -v lean')"
base="$(lake env printenv LEAN_PATH)"
export LEAN_PATH="$out:$base"
rm -f "$out/Names.olean"
options=()
if [[ "${LANIUS_PROOF_PROFILE:-0}" == 1 ]]; then options=(-Dtrace.profiler=true -Dtrace.profiler.threshold=200); fi
/usr/bin/time -f 'connected name contracts: %e s' "$lean" "${options[@]}" -R "$out" -o "$out/Names.olean" "$out/Names.lean"
{
  printf 'import Names\n'
  sed '/^import /d' "$root/verified_compiler/tests/direct_identifier_tests.lean"
  sed '/^import /d' "$root/verified_compiler/tests/direct_declaration_name_tests.lean"
} > "$out/Fixtures.lean"
/usr/bin/time -f 'native name fixtures: %e s' "$lean" -R "$out" "$out/Fixtures.lean"
