#!/usr/bin/env bash
set -euo pipefail

# One small, fresh emitted artifact. This does not reuse producer proofs or
# reconstruct source typing, and is not a full compiler correctness audit.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="${1:-$root/target/verified-compiler/extractor-current}"
compiler="${2:-$root/target/verified-compiler/compiler-children-current}"
extractor="$(realpath "$extractor")"
compiler="$(realpath "$compiler")"
out="$root/target/verified-compiler/nested-enum"
mkdir -p "$out"
source="$root/verified_compiler/tests/surface_nested_enum.lani"
"$extractor" "$source" > "$out/GeneratedDirectCore.lean"
"$extractor" "$root/verified_compiler/tests/enum_match_payload_direct_lean.lani" > "$out/Choice.lean"
if rg -q 'ExprHasType|StmtHasType|TypedIR.Intrinsic|extractedFrontend|extractedRawTokens' \
    "$out/GeneratedDirectCore.lean" "$out/Choice.lean"; then
  echo 'unexpected per-program reconstruction in nested enum output' >&2
  exit 1
fi
"$compiler" "$source" > "$out/program.elf"
chmod +x "$out/program.elf"
status=0
timeout 5s "$out/program.elf" || status=$?
if [[ "$status" -ne 7 ]]; then
  echo "nested enum x86 returned $status, expected 7" >&2
  exit 1
fi
"$compiler" "$root/verified_compiler/tests/enum_match_payload_direct_lean.lani" > "$out/choice.elf"
chmod +x "$out/choice.elf"
status=0
timeout 5s "$out/choice.elf" || status=$?
if [[ "$status" -ne 7 ]]; then
  echo "Choice/Some/match x86 returned $status, expected 7" >&2
  exit 1
fi
cd "$root/formal"
lake --no-cache build +Lanius.Semantics.PureProof +Lanius.Semantics.CallProof
{
  sed -n '/^import /p' "$out/GeneratedDirectCore.lean" \
    "$out/Choice.lean" "$root/verified_compiler/tests/direct_nested_enum.lean" \
    "$root/verified_compiler/tests/direct_public_enum.lean" | \
    sed '/^import GeneratedDirectCore$/d' | sort -u
  printf '\nnamespace NestedFixture\n'
  sed '/^import /d' "$out/GeneratedDirectCore.lean"
  sed '/^import /d' "$root/verified_compiler/tests/direct_nested_enum.lean"
  printf '\nend NestedFixture\nnamespace ChoiceFixture\n'
  sed '/^import /d' "$out/Choice.lean" "$root/verified_compiler/tests/direct_public_enum.lean"
  printf '\nend ChoiceFixture\n'
} > "$out/Emission.lean"
lake run checkExtraction -- -R "$out" \
  "$out/Emission.lean"
# Change the actual emitted payload to the same-typed constant 7. This still
# elaborates as a program, but the universal roundtrip theorem must fail.
if ! rg -Fq '.«Number» («value»)' "$out/GeneratedDirectCore.lean"; then
  echo 'missing nested-payload mutation target' >&2
  exit 1
fi
sed 's/\.«Number» («value»)/.«Number» (7)/g' "$out/Emission.lean" > "$out/Mutation.lean"
if lake run checkExtraction -- -R "$out" "$out/Mutation.lean" > "$out/mutation.log" 2>&1; then
  echo 'constant-payload mutation unexpectedly preserved arbitrary values' >&2
  exit 1
fi
if ! rg -q 'no applicable proved pure contract' "$out/mutation.log"; then
  echo 'mutation failed for an unexpected reason' >&2
  exit 1
fi
for invalid in invalid_nested_enum invalid_nested_match; do
  for mode in direct checked; do
    options=()
    if [[ "$mode" == checked ]]; then options=(--lean-checked); fi
    status=0
    "$extractor" "${options[@]}" "$root/verified_compiler/tests/$invalid.lani" \
      > "$out/rejected.lean" 2> "$out/rejected.log" || status=$?
    if [[ "$status" -ne 30 || -s "$out/rejected.lean" ]]; then
      echo "$invalid was not rejected atomically by $mode extraction" >&2
      exit 1
    fi
  done
  status=0
  "$compiler" "$root/verified_compiler/tests/$invalid.lani" \
    > "$out/rejected.elf" 2> "$out/rejected-x86.log" || status=$?
  if [[ "$status" -ne 10 || -s "$out/rejected.elf" ]]; then
    echo "$invalid was not rejected atomically by x86 compilation" >&2
    exit 1
  fi
done
echo 'fresh nested enum and Choice/Some/match semantics agree with x86 execution'
