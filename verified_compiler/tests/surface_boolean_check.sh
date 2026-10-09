#!/usr/bin/env bash
set -euo pipefail

# A bounded, focused gate for actual self-extracted scalar-expression printing.
# Wrong output still admits as program data but must fail its execution proof.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
kind="${1:-positive}"
out="${2:-$root/target/verified-compiler/surface-boolean/$kind}"
input="${3:-$root/target/verified-compiler/surface-boolean/positive/SelfCore.lean}"
mkdir -p "$out/verified_compiler/tests"
out="$(cd "$out" && pwd)"
check_builder_cache() {
  for dependency in type_ref shape children allocation builder builder_call navigation builder_navigation; do
    cache="$root/target/verified-compiler/verified_compiler/tests/direct_ir_$dependency.olean"
    source="$root/verified_compiler/tests/direct_ir_$dependency.lean"
    if [[ ! -f "$cache" || "$source" -nt "$cache" ]]; then
      echo "builder dependency $dependency needs a fresh check before reuse" >&2; exit 1
    fi
  done
}
# Detect stale prerequisites before spending time on self-admission or writers.
if [[ "$kind" == positive ]]; then check_builder_cache; fi
if [[ "$kind" == wrong-spelling ]]; then input="$(realpath "$input")"; fi
cd "$root/formal"
case "$kind" in
  positive)
    rm -f .lake/build/lib/lean/Lanius/Extraction/CurrentSourceClosure.trace
    lake --no-cache build +Lanius.Extraction.CurrentSourceClosure +Lanius.Semantics.ReadOnlyMemoryTests \
      +Lanius.Extraction.WriterProof +Lanius.Extraction.WriterCursor \
      +Lanius.Extraction.WriterFrameTests +Lanius.Semantics.PureProofTests
    lake env lean -R .. --run ../verified_compiler/tests/direct_source_boundary.lean
    mapfile -t sources < <(lake env lean -R .. --run ../verified_compiler/tests/print_extractor_sources.lean)
    if ((${#sources[@]} == 0)); then echo "empty source closure" >&2; exit 1; fi
    (cd "$root" && /usr/bin/time -f 'fresh self emission: %e s' \
      target/verified-compiler/extractor-current "${sources[@]}" > "$out/SelfCore.lean")
    ;;
  wrong-spelling)
    sed '/^def Extracted.«verified::lean_typed_body».Functions.«surface_boolean_output» /,/^$/ {
      s/("true") (4)/("false") (5)/;
    }' "$input" > "$out/SelfCore.lean"
    if cmp -s "$input" "$out/SelfCore.lean"; then echo "mutation did not change the emitter" >&2; exit 1; fi
    ;;
  *) echo "unknown printer check: $kind" >&2; exit 1 ;;
esac
/usr/bin/time -f 'self admission: %e s' lake run checkExtraction -- \
  -R "$out" -o "$out/SelfCore.olean" "$out/SelfCore.lean"

# Recheck the existing writer contracts against this exact program, rather
# than reuse proof artifacts from different program data.
{
  sed -n '/^import Lanius/p' ../verified_compiler/tests/direct_output_{text,natural}.lean | sort -u
  sed 's/^import GeneratedDirectCore$/import SelfCore/' ../verified_compiler/tests/direct_output_byte.lean
  # Scalar-expression writers use bytes, UTF-8 text, and decimal numbers,
  # not hexadecimal serialization. Recheck their actual dependency closure.
  for proof in packed_words output_text output_natural; do
    sed '/^import /d' "../verified_compiler/tests/direct_$proof.lean"
  done
} > "$out/SelfOutputByte.lean"
lean="$(lake env sh -c 'command -v lean')"
base="$(lake env printenv LEAN_PATH)"
export LEAN_PATH="$out:$base"
/usr/bin/time -f 'shared writer contracts: %e s' "$lean" -R "$out" \
  -o "$out/SelfOutputByte.olean" "$out/SelfOutputByte.lean"
artifact="$out/verified_compiler/tests/direct_surface_boolean.olean"
rm -f "$artifact"
status=0
if [[ "$kind" == positive ]]; then
  # Only reuse builder dependencies when they were checked against byte-
  # identical program data. Mutated data never enters this reuse path.
  if ! cmp -s "$out/SelfCore.lean" "$root/target/verified-compiler/SelfCore.lean"; then
    echo 'builder data differs; its dependencies must be rechecked before the IR composition gate' >&2
    exit 1
  fi
  check_builder_cache
  for dependency in type_ref shape children allocation builder builder_call navigation builder_navigation; do
    cache="$root/target/verified-compiler/verified_compiler/tests/direct_ir_$dependency.olean"
    cp "$cache" "$out/verified_compiler/tests/"
  done
  # Check every connected proof source in one module. This avoids loading
  # and serializing the same dependency closure once per small proof file;
  # none of these program-specific contracts is reused from a cached olean.
  proofs=(output_writer surface_boolean surface_ir output_signed surface_integer surface_dispatch
  symbol_spelling source_identifier escaped_identifier surface_name surface_local constructor_name
    ir_pair_navigation surface_operations surface_unary surface_unary_dispatch surface_binary
    surface_binary_dispatch surface_expression_tree)
  {
    printf 'import SelfOutputByte\nimport verified_compiler.tests.direct_ir_builder_navigation\n'
    for proof in "${proofs[@]}"; do sed -n '/^import Lanius/p' "$root/verified_compiler/tests/direct_$proof.lean"; done | sort -u
    for proof in "${proofs[@]}"; do sed '/^import /d' "$root/verified_compiler/tests/direct_$proof.lean"; done
  } > "$out/SurfaceWriters.lean"
  /usr/bin/time -f 'connected scalar-expression contracts: %e s' "$lean" -R "$out" \
    -o "$out/SurfaceWriters.olean" "$out/SurfaceWriters.lean"
  {
    printf 'import SurfaceWriters\n'
    for proof in output_writer_tests surface_boolean_tests identifier_tests constructor_name_tests surface_expression_tree_tests; do
      sed '/^import /d' "$root/verified_compiler/tests/direct_$proof.lean"
    done
  } > "$out/SurfaceFixtures.lean"
  /usr/bin/time -f 'cursor and native expression fixtures: %e s' "$lean" -R "$out" "$out/SurfaceFixtures.lean"
else
  /usr/bin/time -f 'uniform writer effects: %e s' "$lean" -R "$root" \
    -o "$out/verified_compiler/tests/direct_output_writer.olean" "$root/verified_compiler/tests/direct_output_writer.lean"
  /usr/bin/time -f 'boolean contract: %e s' "$lean" -R "$root" -o "$artifact" \
    "$root/verified_compiler/tests/direct_surface_boolean.lean" > "$out/contract.log" 2>&1 || status=$?
  if [[ "$status" -ne 1 || -e "$artifact" ]] || \
      rg -q 'maximum.*(heartbeats|recursion depth)|index out of bounds' "$out/contract.log" || \
      ! rg -Uq "'SurfaceBooleanProof.actualCall' depends on axioms: \\[[^]]*sorryAx" "$out/contract.log"; then
    cat "$out/contract.log"
    echo "wrong output was not rejected cleanly (status $status)" >&2; exit 1
  fi
  echo 'wrong spelling: data admitted, actual correctness proof rejected, no proof artifact'
fi
