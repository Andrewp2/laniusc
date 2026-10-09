#!/usr/bin/env bash
set -euo pipefail

# Compose source lowering and the actual Lean printer. The producer dependency
# is reused only with exact provenance; every printer/connection source below
# is checked afresh. This gate does not claim a fresh whole-compiler proof.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="$(realpath "${1:-$root/target/verified-compiler/extractor-current}")"
cache="$(realpath "${2:-$root/target/verified-compiler/decimal}")"
producer="$root/target/verified-compiler/ir-producer"
out="$root/target/verified-compiler/literal-extraction"
if [[ ! -f "$producer/Producer.inputs.sha256" ]] ||
    ! sha256sum --check --status "$producer/Producer.inputs.sha256"; then
  echo 'producer prerequisites changed; run the connected ir_producer_check.sh gate first' >&2
  exit 1
fi
if [[ ! -f "$cache/SelfCore.olean" ]] ||
    ! rg --fixed-strings --line-regexp --quiet -- "$(sha256sum "$cache/SelfCore.olean")" \
      "$producer/Producer.inputs.sha256"; then
  echo 'producer was proved against another self-program cache; recheck with this cache first' >&2
  exit 1
fi
mkdir -p "$out"
cd "$root/formal"
lake --no-cache build +Lanius.Extraction.CurrentSourceClosure +Lanius.Extraction.WriterProof \
  +Lanius.Extraction.WriterCursor +Lanius.Extraction.WriterFrame +Lanius.Extraction.WriterCounter
lake env lean -R .. --run ../verified_compiler/tests/direct_source_boundary.lean
mapfile -t sources < <(lake env lean -R .. --run ../verified_compiler/tests/print_extractor_sources.lean)
if ((${#sources[@]} == 0)); then echo 'empty extractor source closure' >&2; exit 1; fi
(cd "$root" && "$extractor" "${sources[@]}" > "$out/SelfCore.lean")
if ! cmp -s "$out/SelfCore.lean" "$cache/SelfCore.lean" ||
    ! cmp -s "$out/SelfCore.lean" "$producer/SelfCore.lean"; then
  echo 'self-program differs from the proved producer' >&2; exit 1
fi
proofs=(output_byte packed_words output_text output_natural output_writer surface_boolean
  surface_ir output_signed surface_integer surface_dispatch symbol_spelling source_identifier
  escaped_identifier surface_name surface_local ir_pair_navigation surface_operations
  surface_unary surface_fallback surface_unary_dispatch surface_binary surface_binary_dispatch
  surface_expression_tree negative_extraction negative_extraction_tests)
{
  printf 'import Producer\n'
  for proof in "${proofs[@]}"; do sed -n '/^import Lanius/p' "$root/verified_compiler/tests/direct_$proof.lean"; done | sort -u
  for proof in "${proofs[@]}"; do sed '/^import /d' "$root/verified_compiler/tests/direct_$proof.lean"; done
} > "$out/LiteralExtraction.lean"
rm -f "$out/LiteralExtraction.olean"
LEAN_PATH="$cache:$producer" /usr/bin/time -f 'fresh printer and source connection: %e s' \
  lake run checkExtraction -- -R "$out" -o "$out/LiteralExtraction.olean" "$out/LiteralExtraction.lean"
echo 'source-to-IR-to-Lean literal connection passed'
