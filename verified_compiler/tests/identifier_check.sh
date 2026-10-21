#!/usr/bin/env bash
set -euo pipefail

# One connected identifier check against freshly admitted extractor data.
# Scalar-expression proofs are unchanged and outside this dependency closure.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
kind="${1:-positive}"
out="${2:-$root/target/verified-compiler/identifiers/$kind}"
input="${3:-$root/target/verified-compiler/identifiers/positive/SelfCore.lean}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
if [[ "$kind" == wrong-byte ]]; then input="$(realpath "$input")"; fi
cd "$root/formal"
case "$kind" in
  positive)
    rm -f .lake/build/lib/lean/Lanius/Extraction/CurrentSourceClosure.trace
    lake --no-cache build +Lanius.Extraction.CurrentSourceClosure +Lanius.Extraction.WriterProof \
      +Lanius.Extraction.WriterCursor +Lanius.Semantics.ReadOnlyMemory
    lake env lean -R .. --run ../verified_compiler/tests/direct_source_boundary.lean
    mapfile -t sources < <(lake env lean -R .. --run ../verified_compiler/tests/print_extractor_sources.lean)
    if ((${#sources[@]} == 0)); then echo 'empty source closure' >&2; exit 1; fi
    (cd "$root" && /usr/bin/time -f 'fresh self emission: %e s' \
      target/verified-compiler/extractor-current "${sources[@]}" > "$out/SelfCore.lean")
    ;;
  wrong-byte)
    sed '/^def Extracted.«verified::lean_syntax».Functions.«source_identifier» /,/^$/ {
      s/«bytes»\[((«spelling»).«start» + «index»)\]/0/;
    }' "$input" > "$out/SelfCore.lean"
    if cmp -s "$input" "$out/SelfCore.lean"; then echo 'mutation did not change source copying' >&2; exit 1; fi
    ;;
  *) echo "unknown identifier check: $kind" >&2; exit 2 ;;
esac
rm -f "$out/SelfCore.olean" "$out/Identifiers.olean"
/usr/bin/time -f 'self admission: %e s' lake run checkExtraction -- \
  -R "$out" -o "$out/SelfCore.olean" "$out/SelfCore.lean"

# Recheck real primitive writers, not cached proofs for different program data.
{
  sed -n '/^import Lanius/p' ../verified_compiler/tests/direct_output_{text,natural}.lean | sort -u
  sed 's/^import GeneratedDirectCore$/import SelfCore/' ../verified_compiler/tests/direct_output_byte.lean
  for proof in packed_words output_text output_natural; do
    sed '/^import /d' "../verified_compiler/tests/direct_$proof.lean"
  done
} > "$out/SelfOutputByte.lean"
lean="$(lake env sh -c 'command -v lean')"
base="$(lake env printenv LEAN_PATH)"
export LEAN_PATH="$out:$base"
/usr/bin/time -f 'primitive writer contracts: %e s' "$lean" -R "$out" \
  -o "$out/SelfOutputByte.olean" "$out/SelfOutputByte.lean"
proofs=(output_writer surface_boolean symbol_spelling source_identifier escaped_identifier surface_name)
{
  printf 'import SelfOutputByte\n'
  for proof in "${proofs[@]}"; do sed -n '/^import Lanius/p' "$root/verified_compiler/tests/direct_$proof.lean"; done | sort -u
  for proof in "${proofs[@]}"; do sed '/^import /d' "$root/verified_compiler/tests/direct_$proof.lean"; done
} > "$out/Identifiers.lean"
status=0
/usr/bin/time -f 'connected identifier contracts: %e s' "$lean" -R "$out" \
  -o "$out/Identifiers.olean" "$out/Identifiers.lean" > "$out/contract.log" 2>&1 || status=$?
if [[ "$kind" == positive ]]; then
  cat "$out/contract.log"
  if [[ "$status" -ne 0 ]]; then exit "$status"; fi
  { printf 'import Identifiers\n'; sed '/^import /d' "$root/verified_compiler/tests/direct_identifier_tests.lean"; } \
    > "$out/Fixtures.lean"
  /usr/bin/time -f 'native identifier fixtures: %e s' "$lean" -R "$out" "$out/Fixtures.lean"
else
  if [[ "$status" -ne 1 || -e "$out/Identifiers.olean" ]] || \
      rg -q 'maximum.*(heartbeats|recursion depth)|index out of bounds' "$out/contract.log" || \
      ! rg -Uq "'SourceIdentifierProof.actualCall' depends on axioms: \\[[^]]*sorryAx" "$out/contract.log"; then
    cat "$out/contract.log"
    echo "wrong byte was not rejected cleanly (status $status)" >&2; exit 1
  fi
  echo 'wrong byte: data admitted, public identifier contract rejected, no proof artifact'
fi
