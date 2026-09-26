#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="${1:-$root/target/verified-compiler/extractor-current}"
compiler="${2:-$root/target/verified-compiler/compiler-current}"
bootstrap="${LANIUSC:-$root/target/debug/laniusc}"
if (($# == 0)); then
  (cd "$root" && "$bootstrap" --emit x86_64 \
    --source-root verified_compiler/src -o "$extractor" \
    verified_compiler/src/extractor.lani)
fi
if (($# < 2)); then
  (cd "$root" && "$bootstrap" --emit x86_64 \
    --source-root verified_compiler/src -o "$compiler" \
    verified_compiler/src/compiler.lani)
fi
cd "$root/formal"

source_path=../verified_compiler/tests/extract_return_code.lani
module=.lake/build/GeneratedDirectCore.lean
olean=.lake/build/GeneratedDirectCore.olean

"$extractor" --lean-checked "$source_path" > "$module"
lake env lean -R .lake/build -o "$olean" "$module"
lean_path="$(lake env printenv LEAN_PATH):$(pwd)/.lake/build"
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_frontend_check.lean "$source_path"
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_core_check.lean "$source_path"
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_core_check.lean \
  --wrong-entry "$source_path"
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_core_check.lean \
  --mutate-return "$source_path"
if wrong_typed="$(LEAN_PATH="$lean_path" lake env lean -R .. --run \
    ../verified_compiler/tests/direct_typed_frontend_check.lean \
    ../verified_compiler/tests/invalid_expression_statement.lani 2>&1)"; then
  echo "typed frontend accepted a different source" >&2
  exit 1
fi
if [[ "$wrong_typed" != *"TypedPackCheckStage.unit"* ]]; then
  echo "$wrong_typed" >&2
  exit 1
fi
echo "directly emitted typed frontend rejects a different source"
if "$extractor" --lean-checked \
  ../verified_compiler/tests/invalid_expression_statement.lani > "$module" 2>/dev/null; then
  echo "direct Lean emitter accepted a semantically invalid expression" >&2
  exit 1
fi
echo "direct Lean emitter rejects an invalid expression"
if "$extractor" \
  ../verified_compiler/tests/invalid_expression_statement.lani > "$module" 2>/dev/null; then
  echo "default Lean emitter accepted a semantically invalid expression" >&2
  exit 1
fi
echo "default Lean emitter rejects the same invalid expression"
if "$compiler" \
  ../verified_compiler/tests/invalid_expression_statement.lani > /dev/null; then
  echo "normal x86 compiler accepted a semantically invalid expression" >&2
  exit 1
fi
echo "normal x86 compiler rejects the same invalid expression"

# Two source units exercise import resolution and a cross-unit call.
main_source=../verified_compiler/tests/qualified_call_main.lani
auxiliary_source=../verified_compiler/tests/compiler_certificate_auxiliary.lani
"$extractor" --lean-checked "$main_source" "$auxiliary_source" > "$module"
if ! rg -q '^private def extractedFunction0_main : Lanius.TypedIR.Named.Function' "$module" \
  || ! rg -q '^private def extractedFunction1_auxiliary : Lanius.TypedIR.Named.Function' "$module"; then
  echo "direct Lean output lost source function names" >&2
  exit 1
fi
lake env lean -R .lake/build -o "$olean" "$module"
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_frontend_check.lean \
  "$main_source" "$auxiliary_source"
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_core_check.lean \
  "$main_source" "$auxiliary_source"
LEAN_PATH="$lean_path" lake env lean -R .. \
  ../verified_compiler/tests/direct_core_semantics.lean
# The normal x86 mode consumes the same lowered IR as --lean-checked. Its
# executable must agree with the checked two-unit Core execution above.
binary=../target/verified-compiler/direct-call-x86.elf
"$compiler" "$main_source" "$auxiliary_source" > "$binary"
chmod +x "$binary"
if timeout 5s "$binary"; then
  native_status=0
else
  native_status=$?
fi
if [[ "$native_status" -ne 7 ]]; then
  echo "x86 executable returned $native_status instead of 7" >&2
  exit 1
fi
echo "normal x86 executable agrees with directly emitted Lean Core"

# A nullary enum path is a real source expression, not just a declaration.
# Changing it to another valid variant must fail source/body agreement even
# though the mutated Core program remains well typed.
nullary_source=../verified_compiler/tests/enum_nullary_direct_lean.lani
"$extractor" --lean-checked "$nullary_source" > "$module"
lake env lean -R .lake/build -o "$olean" "$module"
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_enum_nullary_check.lean \
  "$nullary_source"

enum_source=../verified_compiler/tests/enum_equality_direct_lean.lani
"$extractor" --lean-checked "$enum_source" > "$module"
lake env lean -R .lake/build -o "$olean" "$module"
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_enum_shape_check.lean \
  "$enum_source"
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_core_check.lean "$enum_source"
enum_binary=../target/verified-compiler/direct-enum-x86.elf
"$compiler" "$enum_source" > "$enum_binary"
chmod +x "$enum_binary"
timeout 5s "$enum_binary"
echo "enum equality agrees with direct Lean Core and exits with status 0"

payload_source=../verified_compiler/tests/enum_return_pipeline.lani
"$extractor" --lean-checked "$payload_source" > "$module"
lake env lean -R .lake/build -o "$olean" "$module"
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_enum_shape_check.lean \
  "$payload_source"
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_enum_shape_check.lean \
  --wrong-payload "$payload_source"

# The auxiliary enum's unqualified Payload must resolve in its own module,
# not to the different Payload declared by the first source unit.
enum_main=../verified_compiler/tests/enum_module_main.lani
enum_auxiliary=../verified_compiler/tests/enum_module_auxiliary.lani
"$extractor" --lean-checked "$enum_main" "$enum_auxiliary" > "$module"
lake env lean -R .lake/build -o "$olean" "$module"
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_enum_multimodule_check.lean \
  "$enum_main" "$enum_auxiliary"

# Payload-bearing constructor calls are checked against their source
# expressions, including the value of each payload, and executed in both
# Lean and the ordinary x86 output.
constructor_source=../verified_compiler/tests/enum_payload_direct_lean.lani
"$extractor" --lean-checked "$constructor_source" > "$module"
lake env lean -R .lake/build -o "$olean" "$module"
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_enum_payload_check.lean \
  "$constructor_source"
LEAN_PATH="$lean_path" lake env lean -R .. \
  ../verified_compiler/tests/direct_enum_payload_semantics.lean
constructor_binary=../target/verified-compiler/direct-payload-x86.elf
"$compiler" "$constructor_source" > "$constructor_binary"
chmod +x "$constructor_binary"
timeout 5s "$constructor_binary"
echo "payload constructor execution agrees in checked Lean and x86"

# Nullary and payload-bearing enum matches are checked arm by arm against
# source. A same-type arm mutation must fail body agreement; accepted programs
# must return seven in both Lean and the normal x86 output.
for match_case in nullary payload; do
  match_source=../verified_compiler/tests/enum_match_${match_case}_direct_lean.lani
  "$extractor" --lean-checked "$match_source" > "$module"
  if ! rg -q '^private def extractedEnumeration0_Choice : Lanius.Core.EnumDecl' "$module"; then
    echo "direct Lean output lost the source enum name" >&2
    exit 1
  fi
  if ! rg -q '^  function \(id := .*bindings := \[' "$module" \
    || ! rg -q '^    let «selected» : .* := extractedVariant' "$module" \
    || ! rg -q '^    return match «selected» with' "$module" \
    || ! rg -q '^      \| extractedVariant' "$module"; then
    echo "direct Lean output lost the source-shaped enum-match body" >&2
    exit 1
  fi
  if rg -q 'Lanius.TypedIR.Named.Stmt.mk|\{ core :=' "$module"; then
    echo "representative enum match fell back to raw Core syntax" >&2
    exit 1
  fi
  lake env lean -R .lake/build -o "$olean" "$module"
  LEAN_PATH="$lean_path" lake env lean -R .. --run \
    ../verified_compiler/tests/direct_typed_core_check.lean "$match_source"
  LEAN_PATH="$lean_path" lake env lean -R .. --run \
    ../verified_compiler/tests/direct_enum_match_check.lean "$match_source"
  LEAN_PATH="$lean_path" lake env lean -R .. \
    ../verified_compiler/tests/direct_core_semantics.lean
  match_binary=../target/verified-compiler/direct-match-${match_case}-x86.elf
  "$compiler" "$match_source" > "$match_binary"
  chmod +x "$match_binary"
  if timeout 5s "$match_binary"; then
    match_status=0
  else
    match_status=$?
  fi
  if [[ "$match_status" -ne 7 ]]; then
    echo "x86 ${match_case} match returned $match_status instead of 7" >&2
    exit 1
  fi
  echo "${match_case} match execution agrees in checked Lean and x86"
done

# The proof-backed typed IR boundary accepts this directly emitted program,
# while the same body with a wrong function result type is rejected.
LEAN_PATH="$lean_path" lake env lean -R .. \
  ../verified_compiler/tests/typed_ir_boundary.lean

# A source-shaped enum match with nested arithmetic must retain the exact
# Core semantics, link to a proof-carrying program, and agree with x86.
arithmetic_source=../verified_compiler/tests/surface_enum_arithmetic.lani
"$extractor" --lean-checked "$arithmetic_source" > "$module"
if ! rg -q '^    return match «selected» with' "$module" \
  || ! rg -q '«value» \+ 2' "$module" \
  || ! rg -q '^def extractedTypedProgram : Option Lanius.TypedIR.Program :=' "$module"; then
  echo "direct Lean output lost the source-shaped checked program" >&2
  exit 1
fi
lake env lean -R .lake/build -o "$olean" "$module"
LEAN_PATH="$lean_path" lake env lean -R .. \
  ../verified_compiler/tests/direct_named_link.lean
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_core_check.lean "$arithmetic_source"
arithmetic_binary=../target/verified-compiler/direct-arithmetic-x86.elf
"$compiler" "$arithmetic_source" > "$arithmetic_binary"
chmod +x "$arithmetic_binary"
if timeout 5s "$arithmetic_binary"; then
  arithmetic_status=0
else
  arithmetic_status=$?
fi
if [[ "$arithmetic_status" -ne 18 ]]; then
  echo "x86 enum arithmetic returned $arithmetic_status instead of 18" >&2
  exit 1
fi
echo "checked Lean enum arithmetic agrees with x86"
