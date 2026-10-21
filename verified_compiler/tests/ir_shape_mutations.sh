#!/usr/bin/env bash
set -euo pipefail

# Wrong classifier implementations still admit as program data. Only the
# actual-code correctness contract should reject them, with no proof artifact.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
module="${1:-$root/target/verified-compiler/SelfCore.lean}"
out="${2:-$root/target/verified-compiler/ir-shape/mutations}"
mkdir -p "$out"
module="$(realpath "$module")"
out="$(cd "$out" && pwd)"
base_path="$(cd "$root/formal" && lake env printenv LEAN_PATH)"
lean="$(cd "$root/formal" && lake env sh -c 'command -v lean')"
mutations=("${@:3}")
if ((${#mutations[@]} == 0)); then
  mutations=(expected-last arm-wildcard shape-while)
fi
for mutation in "${mutations[@]}"; do
  dir="$out/$mutation"
  mkdir -p "$dir"
  case "$mutation" in
    expected-last)
      function=expected
      contract=IRShapeProof.actualExpected
      change='s/«arity» - 1/«arity» - 0/' ;;
    arm-wildcard)
      function=arm_shape
      contract=IRShapeProof.actualArm
      change='s/«binding_count» != 0/«binding_count» == 0/' ;;
    shape-while)
      function=shape
      contract=IRShapeProof.actualFixedShapes
      change='/StatementWhile/s/(2)/(3)/' ;;
    cast-arity)
      function=cast_shape
      contract=IRShapeProof.actualCast
      change='s/(1)/(2)/' ;;
    match-count)
      function=match_shape
      contract=IRShapeProof.actualMatchHeader
      change='s/«arm_count» <= 0/«arm_count» < 0/' ;;
    *)
      echo "unknown IR shape mutation: $mutation" >&2
      exit 1 ;;
  esac
  sed '/^def Extracted.«ir::body_tree».Functions.«'"$function"'» /,/^$/ {'"$change"';}' \
    "$module" > "$dir/SelfCore.lean"
  if cmp -s "$module" "$dir/SelfCore.lean"; then
    echo "$mutation did not change its extracted function" >&2
    exit 1
  fi
  (cd "$root/formal" && lake run checkExtraction -- -R "$dir" \
    -o "$dir/SelfCore.olean" "$dir/SelfCore.lean") > "$dir/admission.log" 2>&1
  # Imported helper contracts must be checked against this mutant's data,
  # never reused from the unmodified SelfCore module.
  mkdir -p "$dir/verified_compiler/tests"
  env LEAN_PATH="$dir:$base_path" "$lean" -R "$root" \
    -o "$dir/verified_compiler/tests/direct_ir_type_ref.olean" \
    "$root/verified_compiler/tests/direct_ir_type_ref.lean" > "$dir/type-ref.log" 2>&1
  proof="$root/verified_compiler/tests/direct_ir_shape.lean"
  if [[ "$mutation" != shape-while ]]; then
    # The fixed/payload/count tables are independent of the changed helper.
    # Keep the real models and contracts in its dependency chain, but omit
    # unrelated table proofs from this focused negative check.
    sed '/^theorem actualFixedShapes /,/^$/d;
      /^theorem actualPayloadShapes /,/^$/d;
      /^theorem actualCountedShapes /,/^$/d;
      /^#print axioms actualFixedShapes$/d;
      /^#print axioms actualPayloadShapes$/d;
      /^#print axioms actualCountedShapes$/d' "$proof" > "$dir/ShapeContract.lean"
    proof="$dir/ShapeContract.lean"
  fi
  rm -f "$dir/Contract.olean"
  status=0
  env LEAN_PATH="$dir:$base_path" "$lean" -R "$root" -o "$dir/Contract.olean" \
    "$proof" > "$dir/contract.log" 2>&1 || status=$?
  if [[ "$status" -ne 1 || -e "$dir/Contract.olean" ]]; then
    echo "$mutation did not fail cleanly (status $status)" >&2
    exit 1
  fi
  if ! rg -Uq "'$contract' depends on axioms: \\[[^]]*sorryAx" "$dir/contract.log"; then
    echo "$mutation did not fail the expected public contract" >&2
    exit 1
  fi
  if rg -q 'maximum.*(heartbeats|recursion depth)|index out of bounds' "$dir/contract.log"; then
    echo "$mutation hit an infrastructure limit instead of rejecting the wrong behavior" >&2
    exit 1
  fi
  echo "$mutation: data admitted, public classifier contract rejected, no proof artifact"
done
