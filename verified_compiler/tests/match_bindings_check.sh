#!/usr/bin/env bash
set -euo pipefail

# Fresh connected constructor/match recursion. Admission and expression
# foundations are reused only after exact source and self-emission checks.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${1:-$root/target/verified-compiler/match-bindings}"
cache="$root/target/verified-compiler/scoped-expressions"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
proofs=(output_writer surface_boolean surface_ir output_signed surface_integer surface_dispatch
  symbol_spelling source_identifier escaped_identifier surface_name surface_local constructor_name
  ir_pair_navigation surface_operations surface_unary surface_fallback surface_unary_dispatch surface_binary
  surface_binary_dispatch surface_expression_tree)
{
  printf 'import SelfOutputByte\nimport verified_compiler.tests.direct_ir_builder_navigation\n'
  for proof in "${proofs[@]}"; do sed -n '/^import Lanius/p' "$root/verified_compiler/tests/direct_$proof.lean"; done | sort -u
  for proof in "${proofs[@]}"; do sed '/^import /d' "$root/verified_compiler/tests/direct_$proof.lean"; done
} > "$out/ExpressionWriters.current.lean"
if ! cmp -s "$out/ExpressionWriters.current.lean" "$cache/ExpressionWriters.lean" ||
    [[ ! -f "$cache/ExpressionWriters.olean" || "$cache/ExpressionWriters.lean" -nt "$cache/ExpressionWriters.olean" ]]; then
  echo 'expression sources differ or lack checked artifact; recheck before reuse' >&2; exit 1
fi
for proof in type_ref shape children allocation builder builder_call navigation builder_navigation; do
  artifact="$cache/verified_compiler/tests/direct_ir_$proof.olean"
  if [[ ! -f "$artifact" || "$root/verified_compiler/tests/direct_ir_$proof.lean" -nt "$artifact" ]]; then
    echo "builder $proof changed; recheck before reuse" >&2; exit 1
  fi
done
cd "$root/formal"
lake --no-cache build +Lanius.Extraction.WriterCursorTests +Lanius.Core.BindingsTests \
  +Lanius.Semantics.NaturalArithmeticTests +Lanius.Semantics.ExpressionProofTests
mapfile -t sources < <(lake env lean -R .. --run ../verified_compiler/tests/print_extractor_sources.lean)
if ((${#sources[@]} == 0)); then echo 'empty source closure' >&2; exit 1; fi
(cd "$root" && /usr/bin/time -f 'current self emission: %e s' \
  target/verified-compiler/extractor-current "${sources[@]}" > "$out/SelfCore.lean")
if ! cmp -s "$out/SelfCore.lean" "$cache/SelfCore.lean" ||
    [[ ! -f "$cache/SelfCore.olean" || "$cache/SelfCore.lean" -nt "$cache/SelfCore.olean" ]]; then
  echo 'program changed or lacks admission; recheck before reuse' >&2; exit 1
fi
{
  printf 'import ExpressionWriters\nimport Lanius.Core.Bindings\nimport Lanius.Extraction.WriterCursor\nimport Lanius.Semantics.LocalScope\n'
  sed '/^import /d' "$root/verified_compiler/tests/direct_declaration_name.lean"
  sed '/^import /d' "$root/verified_compiler/tests/direct_type_name.lean"
  sed '/^import /d' "$root/verified_compiler/tests/direct_constructor_payload.lean"
  sed '/^import /d' "$root/verified_compiler/tests/direct_match_metadata.lean"
  sed '/^import /d' "$root/verified_compiler/tests/direct_match_bindings.lean"
  sed '/^import /d' "$root/verified_compiler/tests/direct_match_arm_layout.lean"
  sed '/^import /d' "$root/verified_compiler/tests/direct_match_arm_tail.lean"
  sed '/^import /d' "$root/verified_compiler/tests/direct_match_arm.lean"
  sed '/^import /d' "$root/verified_compiler/tests/direct_match_arms.lean"
  sed '/^import /d' "$root/verified_compiler/tests/direct_surface_match.lean"
  sed '/^import /d' "$root/verified_compiler/tests/direct_recursive_expression.lean"
} > "$out/Bindings.lean"
lean="$(lake env sh -c 'command -v lean')"
base="$(lake env printenv LEAN_PATH)"
rm -f "$out/Bindings.olean"
LEAN_PATH="$cache:$base" /usr/bin/time -f 'connected recursive expression contracts: %e s' "$lean" -R "$out" \
  -o "$out/Bindings.olean" "$out/Bindings.lean"
{
  printf 'import Bindings\nnamespace DeclarationNameTests\n'
  printf 'open Lanius Lanius.Core Lanius.Semantics Lanius.Memory SymbolSpellingProof\n'
  printf 'private def referenceType : Ty := match referenceValue 0 0 with | .structure id _ => .structure id | _ => .unit\n'
  sed -n '/^def fixture/,/^private def check/ { /^private def check/q; p; }' \
    "$root/verified_compiler/tests/direct_declaration_name_tests.lean"
  printf 'end DeclarationNameTests\n'
  # Reuse only the naming fixture definition, not unrelated identifier cases.
  sed -n '/^namespace IdentifierTests/,/^private def check/ {
    /^private def check/q;
    p;
  }' "$root/verified_compiler/tests/direct_identifier_tests.lean"
  printf 'end IdentifierTests\n'
  sed '/^import /d' "$root/verified_compiler/tests/direct_surface_expression_tree_tests.lean"
  sed '/^import /d' "$root/verified_compiler/tests/direct_match_bindings_tests.lean"
} > "$out/Fixtures.lean"
LEAN_PATH="$out:$cache:$base" /usr/bin/time -f 'native match binding fixtures: %e s' \
  "$lean" -R "$out" "$out/Fixtures.lean"
cp "$root/verified_compiler/tests/direct_match_binding_guard.lean" "$out/Guard.lean"
LEAN_PATH="$cache:$base" "$lean" -R "$out" "$out/Guard.lean"
cp "$root/verified_compiler/tests/direct_match_arm_guard.lean" "$out/ArmGuard.lean"
LEAN_PATH="$cache:$base" "$lean" -R "$out" "$out/ArmGuard.lean"
cp "$root/verified_compiler/tests/direct_match_arm_step.lean" "$out/ArmStep.lean"
LEAN_PATH="$cache:$base" "$lean" -R "$out" "$out/ArmStep.lean"
cp "$root/verified_compiler/tests/direct_match_arms_guard.lean" "$out/ArmsGuard.lean"
LEAN_PATH="$cache:$base" "$lean" -R "$out" "$out/ArmsGuard.lean"
cp "$root/verified_compiler/tests/direct_match_dispatch_guard.lean" "$out/DispatchGuard.lean"
LEAN_PATH="$cache:$base" "$lean" -R "$out" "$out/DispatchGuard.lean"
