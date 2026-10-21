#!/usr/bin/env bash
set -euo pipefail

# Recheck all connected printer sources against fresh, byte-identical emission.
# Admission, primitive writers, and builder proofs are reused for the exact
# already-checked program. This is not a fresh per-program verification timing.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${1:-$root/target/verified-compiler/scoped-expressions}"
kind="${2:-positive}"
input="${3:-$root/target/verified-compiler/scoped-expressions/SelfCore.lean}"
cache="$root/target/verified-compiler/identifiers/positive"
mkdir -p "$out/verified_compiler/tests"
out="$(cd "$out" && pwd)"
if [[ "$kind" == wrong-local-id || "$kind" == wrong-variant-slot ]]; then
  input="$(realpath "$input")"
  if [[ "$kind" == wrong-local-id ]]; then
    sed '/^def Extracted.«verified::lean_body_shape».Functions.«expression_local_id» /,/^$/ {
      s/return («reference»).«id»/return 0/;
    }' "$input" > "$out/SelfCore.lean"
    contract=LocalId
    theorem=SurfaceLocalProof.actualId
  else
    sed '/^def Extracted.«verified::lean_syntax».Functions.«variant_slot» /,/^$/ {
      s/return «slot»/return «ordinal»/;
    }' "$input" > "$out/SelfCore.lean"
    contract=VariantSlot
    theorem=ConstructorNameProof.actualSlot
  fi
  if cmp -s "$input" "$out/SelfCore.lean"; then echo "$kind mutation changed nothing" >&2; exit 1; fi
  cd "$root/formal"
  rm -f "$out/SelfCore.olean" "$out/$contract.olean"
  /usr/bin/time -f 'mutated self admission: %e s' lake run checkExtraction -- \
    -R "$out" -o "$out/SelfCore.olean" "$out/SelfCore.lean"
  {
    printf 'import SelfCore\nimport Lanius.Semantics.CallProof\nimport Lanius.Semantics.PureProof\nimport Lanius.Semantics.SourceValue\nimport Lanius.Semantics.ReadOnlyMemory\n'
    printf 'open Lanius Lanius.Core Lanius.Semantics\n'
    if [[ "$kind" == wrong-local-id ]]; then
      sed -n '/^namespace SurfaceLocalProof/,/^private def classifierArms/ {
        /^private def classifierArms/q;
        /^open /d;
        p;
      }' "$root/verified_compiler/tests/direct_surface_local.lean"
      printf '#print axioms actualId\nend SurfaceLocalProof\n'
    else
      printf 'open Lanius.Memory\n'
      sed -n '/^namespace ConstructorNameProof/,/^def referenceType/ {
        /^def referenceType/q;
        /^open /d;
        p;
      }' "$root/verified_compiler/tests/direct_constructor_name.lean"
      printf '#print axioms actualSlot\nend ConstructorNameProof\n'
    fi
  } > "$out/$contract.lean"
  lean="$(lake env sh -c 'command -v lean')"
  base="$(lake env printenv LEAN_PATH)"
  status=0
  LEAN_PATH="$out:$base" "$lean" -R "$out" -o "$out/$contract.olean" "$out/$contract.lean" \
    > "$out/contract.log" 2>&1 || status=$?
  if [[ "$status" -ne 1 || -e "$out/$contract.olean" ]] || \
      rg -q 'maximum.*(heartbeats|recursion depth)|index out of bounds' "$out/contract.log" || \
      ! rg -Uq "'$theorem' depends on axioms: \\[[^]]*sorryAx" "$out/contract.log"; then
    cat "$out/contract.log"
    echo "$kind was not rejected cleanly (status $status)" >&2; exit 1
  fi
  echo "$kind: data admitted, actual execution contract rejected, no proof artifact"
  exit 0
elif [[ "$kind" != positive ]]; then
  echo "unknown expression check: $kind" >&2; exit 2
fi
for proof in output_byte packed_words output_text output_natural; do
  source="$root/verified_compiler/tests/direct_$proof.lean"
  if [[ ! -f "$cache/SelfOutputByte.olean" || "$source" -nt "$cache/SelfOutputByte.olean" ]]; then
    echo "primitive $proof requires rechecking before reuse" >&2; exit 1
  fi
done
for proof in type_ref shape children allocation builder builder_call navigation builder_navigation; do
  artifact="$root/target/verified-compiler/verified_compiler/tests/direct_ir_$proof.olean"
  source="$root/verified_compiler/tests/direct_ir_$proof.lean"
  if [[ ! -f "$artifact" || "$source" -nt "$artifact" ]]; then
    echo "builder $proof requires rechecking before reuse" >&2; exit 1
  fi
done
cd "$root/formal"
rm -f .lake/build/lib/lean/Lanius/Extraction/CurrentSourceClosure.trace
lake --no-cache build +Lanius.Extraction.CurrentSourceClosure +Lanius.Extraction.WriterFrameTests \
  +Lanius.Extraction.WriterProof +Lanius.Extraction.WriterCursor +Lanius.Extraction.WriterCounter
lake env lean -R .. --run ../verified_compiler/tests/direct_source_boundary.lean
mapfile -t sources < <(lake env lean -R .. --run ../verified_compiler/tests/print_extractor_sources.lean)
if ((${#sources[@]} == 0)); then echo 'empty source closure' >&2; exit 1; fi
(cd "$root" && /usr/bin/time -f 'current self emission: %e s' \
  target/verified-compiler/extractor-current "${sources[@]}" > "$out/SelfCore.lean")
if ! cmp -s "$out/SelfCore.lean" "$cache/SelfCore.lean" || \
    ! cmp -s "$out/SelfCore.lean" "$root/target/verified-compiler/SelfCore.lean" || \
    [[ ! -f "$cache/SelfCore.olean" || "$cache/SelfCore.lean" -nt "$cache/SelfCore.olean" ]]; then
  echo 'program data differs or lacks admission; recheck admission and its foundations' >&2; exit 1
fi
cp "$cache/SelfCore.olean" "$cache/SelfOutputByte.olean" "$out/"
for proof in type_ref shape children allocation builder builder_call navigation builder_navigation; do
  cp "$root/target/verified-compiler/verified_compiler/tests/direct_ir_$proof.olean" "$out/verified_compiler/tests/"
done
proofs=(output_writer surface_boolean surface_ir output_signed surface_integer surface_dispatch
  symbol_spelling source_identifier escaped_identifier surface_name surface_local constructor_name
  ir_pair_navigation surface_operations surface_unary surface_fallback surface_unary_dispatch surface_binary
  surface_binary_dispatch surface_expression_tree)
{
  printf 'import SelfOutputByte\nimport verified_compiler.tests.direct_ir_builder_navigation\n'
  for proof in "${proofs[@]}"; do sed -n '/^import Lanius/p' "$root/verified_compiler/tests/direct_$proof.lean"; done | sort -u
  for proof in "${proofs[@]}"; do sed '/^import /d' "$root/verified_compiler/tests/direct_$proof.lean"; done
} > "$out/ExpressionWriters.lean"
lean="$(lake env sh -c 'command -v lean')"
base="$(lake env printenv LEAN_PATH)"
export LEAN_PATH="$out:$base"
rm -f "$out/ExpressionWriters.olean"
/usr/bin/time -f 'connected expression/name contracts: %e s' "$lean" -R "$out" \
  -o "$out/ExpressionWriters.olean" "$out/ExpressionWriters.lean"
{
  printf 'import ExpressionWriters\n'
  for proof in output_writer_tests surface_boolean_tests identifier_tests constructor_name_tests surface_expression_tree_tests; do
    sed '/^import /d' "$root/verified_compiler/tests/direct_$proof.lean"
  done
} > "$out/Fixtures.lean"
/usr/bin/time -f 'connected native expression/name fixtures: %e s' "$lean" -R "$out" "$out/Fixtures.lean"
