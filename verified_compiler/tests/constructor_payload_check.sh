#!/usr/bin/env bash
set -euo pipefail

# Check new constructor proofs against the exact previously admitted program
# and connected expression/builder contracts. This is not a fresh full check.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${1:-$root/target/verified-compiler/constructor-payloads}"
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
  echo 'connected expression proofs differ or lack a checked artifact; recheck before reuse' >&2; exit 1
fi
for proof in type_ref shape children allocation builder builder_call navigation builder_navigation; do
  if [[ "$root/verified_compiler/tests/direct_ir_$proof.lean" -nt "$cache/verified_compiler/tests/direct_ir_$proof.olean" ]]; then
    echo "builder $proof changed; recheck before reuse" >&2; exit 1
  fi
done
cd "$root/formal"
lake --no-cache build +Lanius.Extraction.WriterCursorTests
mapfile -t sources < <(lake env lean -R .. --run ../verified_compiler/tests/print_extractor_sources.lean)
if ((${#sources[@]} == 0)); then echo 'empty source closure' >&2; exit 1; fi
(cd "$root" && /usr/bin/time -f 'current self emission: %e s' target/verified-compiler/extractor-current "${sources[@]}" > "$out/SelfCore.lean")
if ! cmp -s "$out/SelfCore.lean" "$cache/SelfCore.lean"; then
  echo 'program changed; recheck admission and connected expression proofs' >&2; exit 1
fi
{
  printf 'import ExpressionWriters\nimport Lanius.Extraction.WriterCursor\n'
  sed '/^import /d' "$root/verified_compiler/tests/direct_declaration_name.lean"
  sed '/^import /d' "$root/verified_compiler/tests/direct_type_name.lean"
  sed '/^import /d' "$root/verified_compiler/tests/direct_constructor_payload.lean"
} > "$out/Payloads.lean"
lean="$(lake env sh -c 'command -v lean')"
base="$(lake env printenv LEAN_PATH)"
rm -f "$out/Payloads.olean"
LEAN_PATH="$cache:$base" /usr/bin/time -f 'constructor payload contracts: %e s' "$lean" -R "$out" -o "$out/Payloads.olean" "$out/Payloads.lean"
{
  printf 'import Payloads\n'
  # Reuse fixture builders, not unrelated test runs.
  sed -n '/^namespace DeclarationNameTests/,/^private def check/ {
    /^private def check/q; p;
  }' "$root/verified_compiler/tests/direct_declaration_name_tests.lean"
  printf 'end DeclarationNameTests\n'
  sed -n '/^namespace SurfaceExpressionTreeTests/,/^private def read/ {
    /^private def read/q; p;
  }' "$root/verified_compiler/tests/direct_surface_expression_tree_tests.lean"
  printf 'end SurfaceExpressionTreeTests\n'
  sed '/^import /d' "$root/verified_compiler/tests/direct_constructor_payload_tests.lean"
} > "$out/Fixtures.lean"
LEAN_PATH="$out:$cache:$base" /usr/bin/time -f 'native constructor fixtures: %e s' "$lean" -R "$out" "$out/Fixtures.lean"
LEAN_PATH="$cache:$base" "$lean" "$root/verified_compiler/tests/direct_constructor_guard.lean"
