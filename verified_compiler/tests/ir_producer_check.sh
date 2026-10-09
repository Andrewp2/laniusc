#!/usr/bin/env bash
set -euo pipefail

# One fresh connected producer artifact. Only admission of the byte-identical
# self-program is reused; selected contracts and fixtures are checked together.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="$(realpath "${1:-$root/target/verified-compiler/extractor-current}")"
cache="$(realpath "${3:-$root/target/verified-compiler/scoped-expressions}")"
out="$root/target/verified-compiler/ir-producer"
scope="${2:-all}"
case "$scope" in
  all) artifact=Producer; proofs=(type_ref expression_kind event_store event_store_tests result_type result_type_tests event_codecs event_codecs_tests event_write decimal decimal_loop decimal_tests error integer_lowering literal_lowering negative_lowering integer_tests negative_tests event_write_tests region region_tests region_allocation region_pipeline region_allocation_tests shape children allocation builder builder_call navigation builder_navigation builder_tests lowered_tree expression_validation type_cache type_cache_store type_cache_fill type_cache_reset type_cache_invariant binary_kind binary_inference unary_inference source_cache recursive_inference expression_tests type_cache_tests type_cache_reset_tests operand_tests recursive_tests binary_tests) ;;
  events) artifact=EventProducer; proofs=(type_ref event_store event_store_tests result_type event_codecs event_codecs_tests) ;;
  lowering) artifact=LoweringProducer; proofs=(type_ref expression_kind event_store event_store_tests result_type event_codecs event_write decimal decimal_loop error integer_lowering literal_lowering negative_lowering integer_tests negative_tests event_write_tests expression_validation type_cache type_cache_store type_cache_fill type_cache_reset type_cache_invariant binary_kind binary_inference unary_inference source_cache recursive_inference expression_tests type_cache_tests type_cache_reset_tests operand_tests recursive_tests binary_tests) ;;
  decimal) artifact=DecimalProducer; proofs=(decimal decimal_loop decimal_tests error integer_lowering) ;;
  expression) artifact=ExpressionProducer; proofs=(error expression_validation expression_tests) ;;
  cache) artifact=CacheProducer; proofs=(type_ref expression_kind error expression_validation type_cache type_cache_store type_cache_fill type_cache_reset type_cache_invariant binary_kind binary_inference unary_inference source_cache recursive_inference type_cache_tests type_cache_reset_tests operand_tests recursive_tests binary_tests) ;;
  operand) artifact=OperandProducer; proofs=(type_ref expression_kind error expression_validation type_cache type_cache_store type_cache_fill type_cache_reset type_cache_invariant binary_kind binary_inference unary_inference source_cache recursive_inference operand_tests recursive_tests binary_tests) ;;
  annotations) artifact=AnnotationProducer; proofs=(type_ref result_type result_type_tests) ;;
  regions) artifact=RegionProducer; proofs=(type_ref event_store result_type event_codecs event_write decimal decimal_loop error integer_lowering literal_lowering region region_tests region_allocation region_pipeline region_allocation_tests) ;;
  *) echo 'producer scope must be all, events, lowering, decimal, expression, cache, operand, annotations or regions' >&2; exit 1 ;;
esac
mkdir -p "$out"
cd "$root/formal"
lake --no-cache build +Lanius.Extraction.CurrentSourceClosure +Lanius.Semantics.ReadOnlyMemory \
  +Lanius.Semantics.CountedLocal +Lanius.Semantics.NativeReadFrame +Lanius.Semantics.RawStore \
  +Lanius.Semantics.RawSlice +Lanius.Semantics.LoopRun +Lanius.Core.Bindings +Lanius.Memory.Allocated \
  +Lanius.Semantics.NativeStoreProof +Lanius.Semantics.ScopedEffect +Lanius.Semantics.CallProof \
  +Lanius.Semantics.LocalPair +Lanius.Semantics.PureProof +Lanius.Semantics.EffectProof +Lanius.SurfaceElaboration.Classification
lake env lean -R .. --run ../verified_compiler/tests/direct_source_boundary.lean
mapfile -t sources < <(lake env lean -R .. --run ../verified_compiler/tests/print_extractor_sources.lean)
if ((${#sources[@]} == 0)); then echo 'empty extractor source closure' >&2; exit 1; fi
(cd "$root" && /usr/bin/time -f 'current self emission: %e s' \
  "$extractor" "${sources[@]}" > "$out/SelfCore.lean")
if [[ ! -f "$cache/SelfCore.olean" || "$cache/SelfCore.lean" -nt "$cache/SelfCore.olean" ]] || \
    ! cmp -s "$out/SelfCore.lean" "$cache/SelfCore.lean"; then
  echo 'self-program changed or lacks current admission; recheck before proof reuse' >&2; exit 1
fi
{
  printf 'import SelfCore\n'
  for proof in "${proofs[@]}"; do
    sed -n '/^import Lanius/p' "$root/verified_compiler/tests/direct_ir_$proof.lean"
  done | sort -u
  for proof in "${proofs[@]}"; do
    sed '/^import /d' "$root/verified_compiler/tests/direct_ir_$proof.lean"
  done
} > "$out/$artifact.lean"
rm -f "$out/$artifact.olean" "$out/$artifact.ilean"
# Test-cache provenance only. A downstream composition can reuse these proved
# dependencies after checking their exact source, program and artifact bytes.
# This is not a compiler certificate or the trusted-output import mechanism.
{
  sha256sum "$cache/SelfCore.lean" "$cache/SelfCore.olean" "$out/SelfCore.lean" "$out/$artifact.lean" \
    "$root/formal/lean-toolchain" "$root/formal/lakefile.lean" "$root/verified_compiler/tests/ir_producer_check.sh"
  for proof in "${proofs[@]}"; do sha256sum "$root/verified_compiler/tests/direct_ir_$proof.lean"; done
  while IFS= read -r library; do sha256sum "$library"; done < <(rg --files "$root/formal/Lanius" -g '*.lean' | sort)
} > "$out/$artifact.pending.sha256"
LEAN_PATH="$cache" /usr/bin/time -f 'fresh connected producer contracts: %e s' \
  lake run checkExtraction -- -R "$out" -o "$out/$artifact.olean" "$out/$artifact.lean"
if ! sha256sum --check --status "$out/$artifact.pending.sha256"; then
  echo 'producer input changed during checking; no cache provenance accepted' >&2; exit 1
fi
sha256sum "$out/$artifact.olean" >> "$out/$artifact.pending.sha256"
mv "$out/$artifact.pending.sha256" "$out/$artifact.inputs.sha256"
if [[ "$scope" == all ]]; then
  echo 'IR storage construction, writers and physical endpoint-table producer passed'
elif [[ "$scope" == annotations ]]; then
  echo 'result-type validation and annotation contracts passed'
elif [[ "$scope" == regions ]]; then
  echo 'IR storage construction and writer pipeline contracts passed'
elif [[ "$scope" == lowering ]]; then
  echo 'frontend literal, call and match writer success/rejection contracts passed'
elif [[ "$scope" == decimal ]]; then
  echo 'integer decoding, overflow rejection and traversal contracts passed'
elif [[ "$scope" == expression ]]; then
  echo 'recursive expression validation and early-rejection checks passed'
elif [[ "$scope" == cache ]]; then
  echo 'type-cache decoding, inference, store and reuse contracts passed'
elif [[ "$scope" == operand ]]; then
  echo 'operand validation preserves failures and rejects non-value types'
else
  echo 'typed append preserves payloads, resets annotations, and frames neighboring slots'
fi
