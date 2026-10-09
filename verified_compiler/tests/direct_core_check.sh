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

bash ../verified_compiler/tests/resolution_visibility_check.sh "$extractor" "$compiler"
lake env lean -R .. --run ../verified_compiler/tests/direct_named_scope.lean
lake env lean -R .. ../verified_compiler/tests/direct_named_intrinsics.lean
lake env lean -R .. ../verified_compiler/tests/direct_named_application.lean
lake env lean -R .. ../verified_compiler/tests/direct_named_declarations.lean
lake env lean -R .. ../verified_compiler/tests/direct_named_constructor_syntax.lean
bash ../verified_compiler/tests/direct_nested_scope_check.sh "$extractor" "$compiler"
bash ../verified_compiler/tests/direct_public_runtime_check.sh "$extractor" "$compiler"

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

# String literals stay readable and preserve their exact UTF-8 bytes,
# including escapes and embedded NUL. A same-typed content change is rejected.
string_source=../verified_compiler/tests/surface_string_values.lani
"$extractor" --lean-checked "$string_source" > "$module"
if rg -q 'Lanius.TypedIR.Surface.Stmt.mk|\{ core :=' "$module"; then
  echo "string fixture fell back to raw Core syntax" >&2
  exit 1
fi
lake env lean -R .lake/build -o "$olean" "$module"
LEAN_PATH="$lean_path" lake env lean -R .. \
  ../verified_compiler/tests/direct_named_string_values.lean
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_core_check.lean "$string_source"
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_core_check.lean --mutate-string "$string_source"
echo "source-shaped Lean strings preserve bytes and reject changed content"

# Numeric conversions, pointer arithmetic, and nominal raw slices use typed
# intrinsic applications. Check their execution against the normal x86 path.
for primitive_case in numeric_conversions memory; do
  primitive_source=../verified_compiler/tests/surface_numeric_conversions.lani
  expected_status=37
  if [[ "$primitive_case" == memory ]]; then
    primitive_source=../verified_compiler/tests/typed_slice_direct_return.lani
    expected_status=30
  fi
  "$extractor" --lean-checked "$primitive_source" > "$module"
  if rg -q 'Lanius.TypedIR.Surface.Stmt.mk|\{ core :=' "$module"; then
    echo "$primitive_case fixture fell back to raw Core syntax" >&2
    exit 1
  fi
  lake env lean -R .lake/build -o "$olean" "$module"
  LEAN_PATH="$lean_path" lake env lean -R .. \
    "../verified_compiler/tests/direct_named_${primitive_case}.lean"
  primitive_binary=../target/verified-compiler/direct-${primitive_case}-x86.elf
  "$compiler" "$primitive_source" > "$primitive_binary"
  chmod +x "$primitive_binary"
  primitive_status=0
  timeout 5s "$primitive_binary" || primitive_status=$?
  if [[ "$primitive_status" -ne "$expected_status" ]]; then
    echo "$primitive_case x86 execution returned $primitive_status, expected $expected_status" >&2
    exit 1
  fi
done
for invalid_case in invalid_generic_slice_pointer invalid_generic_slice_length lean_reject_descriptor_raw_slice; do
  if "$extractor" "../verified_compiler/tests/${invalid_case}.lani" > /dev/null 2>&1; then
    echo "direct Lean emitter accepted unsupported slice input: $invalid_case" >&2
    exit 1
  fi
done
echo "typed numeric and memory intrinsics agree with x86; invalid slices rejected"

# Two source units exercise import resolution and a cross-unit call.
main_source=../verified_compiler/tests/qualified_call_main.lani
auxiliary_source=../verified_compiler/tests/compiler_certificate_auxiliary.lani
"$extractor" --lean-checked "$main_source" "$auxiliary_source" > "$module"
if ! rg -Fq 'def Extracted.«app::main».Functions.«main» : Lanius.TypedIR.Surface.Function' "$module" \
  || ! rg -Fq 'def Extracted.«app::auxiliary».Functions.«auxiliary» : Lanius.TypedIR.Surface.Function' "$module"; then
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
    || ! rg -q '^    let «selected» : .* := \(\.«' "$module" \
    || ! rg -q '^    return match «selected» with' "$module" \
    || ! rg -q '^      \| \.«' "$module"; then
    echo "direct Lean output lost the source-shaped enum-match body" >&2
    exit 1
  fi
  if rg -q 'Lanius.TypedIR.Surface.Stmt.mk|\{ core :=' "$module"; then
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
  if [[ "$match_case" == payload ]]; then
    LEAN_PATH="$lean_path" lake env lean -R .. \
      ../verified_compiler/tests/direct_public_enum.lean
  fi
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

# The emitted program retains its entrypoint; independent checking is only
# a test oracle, not a dependency of normal Lean output.
compositional_module=.lake/build/GeneratedCompositional.lean
compositional_olean=.lake/build/GeneratedCompositional.olean
"$extractor" --lean-checked \
  ../verified_compiler/tests/enum_match_payload_direct_lean.lani \
  > "$compositional_module"
lake env lean -R .lake/build -o "$compositional_olean" "$compositional_module"
LEAN_PATH="$lean_path" lake env lean -R .. \
  ../verified_compiler/tests/direct_compositional_link.lean

# The independent typing oracle accepts this directly emitted program,
# while the same body with a wrong function result type is rejected.
LEAN_PATH="$lean_path" lake env lean -R .. \
  ../verified_compiler/tests/typed_ir_boundary.lean

# A source-shaped enum match with nested arithmetic must retain the exact
# Core semantics and agree with x86.
arithmetic_source=../verified_compiler/tests/surface_enum_arithmetic.lani
"$extractor" --lean-checked "$arithmetic_source" > "$module"
if ! rg -q '^    return match «selected» with' "$module" \
  || ! rg -q '«value» \+ 2' "$module" \
  || ! rg -q '^def extractedProgram : Lanius.Core.Program :=' "$module"; then
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

# Multiple constructor payloads and match binders use the same source-shaped
# path. The nested arithmetic payload must erase to the exact source Core IR.
multi_source=../verified_compiler/tests/surface_enum_multi_payload.lani
"$extractor" --lean-checked "$multi_source" > "$module"
if ! rg -Fq '.«Pair» ((3 + 4)) (5)' "$module" \
  || ! rg -Fq '| .«Pair» «left» «right» =>' "$module"; then
  echo "direct Lean output lost multi-payload source syntax" >&2
  exit 1
fi
if rg -q 'Lanius.TypedIR.Surface.Stmt.mk|\{ core :=' "$module"; then
  echo "multi-payload match fell back to raw Core syntax" >&2
  exit 1
fi
if ! rg -q '^def extractedProgram : Lanius.Core.Program :=' "$module"; then
  echo "direct Lean output lost direct Core program" >&2
  exit 1
fi
lake env lean -R .lake/build -o "$olean" "$module"
LEAN_PATH="$lean_path" lake env lean -R .. \
  ../verified_compiler/tests/direct_named_multi_payload.lean
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_core_check.lean "$multi_source"
multi_binary=../target/verified-compiler/direct-multi-payload-x86.elf
"$compiler" "$multi_source" > "$multi_binary"
chmod +x "$multi_binary"
if timeout 5s "$multi_binary"; then
  multi_status=0
else
  multi_status=$?
fi
if [[ "$multi_status" -ne 37 ]]; then
  echo "x86 multi-payload match returned $multi_status instead of 37" >&2
  exit 1
fi
echo "checked Lean multi-payload match agrees with x86"

# Parameter names are Lean bindings backed by the exact resolved IR IDs.
# Calls resolve through signatures declared before bodies, including forward
# calls and a nested zero-argument call.
parameter_source=../verified_compiler/tests/surface_parameter_arithmetic.lani
"$extractor" --lean-checked "$parameter_source" > "$module"
if ! rg -Fq 'arguments := [«value» := ' "$module" \
  || ! rg -Fq 'return («value» + 1)' "$module" \
  || ! rg -Fq 'return Extracted.«app::main».Functions.«increment» (Extracted.«app::main».Functions.«seed» ())' "$module"; then
  echo "direct Lean output lost source-shaped parameters or calls" >&2
  exit 1
fi
if rg -q 'Lanius.TypedIR.Surface.Stmt.mk|\{ core :=' "$module"; then
  echo "parameter/call fixture fell back to raw Core syntax" >&2
  exit 1
fi
if ! rg -q '^def extractedProgram : Lanius.Core.Program :=' "$module"; then
  echo "direct Lean output lost direct Core program" >&2
  exit 1
fi
lake env lean -R .lake/build -o "$olean" "$module"
LEAN_PATH="$lean_path" lake env lean -R .. \
  ../verified_compiler/tests/direct_named_parameter.lean
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_core_check.lean "$parameter_source"
parameter_binary=../target/verified-compiler/direct-parameter-x86.elf
"$compiler" "$parameter_source" > "$parameter_binary"
chmod +x "$parameter_binary"
if timeout 5s "$parameter_binary"; then
  parameter_status=0
else
  parameter_status=$?
fi
if [[ "$parameter_status" -ne 7 ]]; then
  echo "x86 parameter call returned $parameter_status instead of 7" >&2
  exit 1
fi
echo "checked Lean parameter function agrees with x86"

# A reusable Boolean/comparison expression rule covers parameterized helpers.
comparison_source=../verified_compiler/tests/surface_boolean_comparison.lani
"$extractor" --lean-checked "$comparison_source" > "$module"
if ! rg -Fq 'return ((«value» >= 7) && («value» != 9))' "$module" \
  || ! rg -Fq 'if Extracted.«app::main».Functions.«accepted» (7) then' "$module" \
  || ! rg -Fq 'if («value» > 0) then' "$module"; then
  echo "direct Lean output lost source-shaped comparison or control flow" >&2
  exit 1
fi
if rg -q 'Lanius.TypedIR.Surface.Stmt.mk|\{ core :=' "$module"; then
  echo "comparison/control-flow fixture fell back to raw Core syntax" >&2
  exit 1
fi
if ! rg -q '^def extractedProgram : Lanius.Core.Program :=' "$module"; then
  echo "direct Lean output lost direct Core program" >&2
  exit 1
fi
lake env lean -R .lake/build -o "$olean" "$module"
LEAN_PATH="$lean_path" lake env lean -R .. \
  ../verified_compiler/tests/direct_named_comparison.lean
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_core_check.lean "$comparison_source"
comparison_binary=../target/verified-compiler/direct-comparison-x86.elf
"$compiler" "$comparison_source" > "$comparison_binary"
chmod +x "$comparison_binary"
if timeout 5s "$comparison_binary"; then
  comparison_status=0
else
  comparison_status=$?
fi
if [[ "$comparison_status" -ne 1 ]]; then
  echo "x86 Boolean comparison returned $comparison_status instead of 1" >&2
  exit 1
fi
echo "checked Lean Boolean comparison agrees with x86"

# Fields retain source names from their declaration unit. Nested projections
# distinguish same-named fields on different owners; construction uses source
# order different from declaration order. The checker rejects a same-typed
# but wrong field even though that altered Core program remains well typed.
field_source=../verified_compiler/tests/surface_struct_fields.lani
field_types=../verified_compiler/tests/surface_struct_types.lani
"$extractor" --lean-checked "$field_source" "$field_types" > "$module"
if ! rg -Fq 'return ((«record»).«value»).«value»' "$module" \
  || ! rg -q '^def extractedProgram : Lanius.Core.Program :=' "$module"; then
  echo "direct Lean output lost source-shaped nested fields or the Core program" >&2
  exit 1
fi
if rg -q 'Lanius.TypedIR.Surface.Stmt.mk|\{ core :=' "$module"; then
  echo "record fixture fell back to raw Core syntax" >&2
  exit 1
fi
lake env lean -R .. ../verified_compiler/tests/direct_named_record_syntax.lean
lake env lean -R .lake/build -o "$olean" "$module"
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_named_fields.lean "$field_source" "$field_types"
field_binary=../target/verified-compiler/direct-fields-x86.elf
"$compiler" "$field_source" "$field_types" > "$field_binary"
chmod +x "$field_binary"
field_status=0
timeout 5s "$field_binary" || field_status=$?
if [[ "$field_status" -ne 7 ]]; then
  echo "x86 nested fields returned $field_status instead of 7" >&2
  exit 1
fi
echo "checked Lean cross-module nested fields agree with x86"

# Both the selected payload and wildcard arm execute; unary operators retain
# their Core identity instead of being folded away by source notation.
unary_source=../verified_compiler/tests/surface_unary_wildcard.lani
"$extractor" --lean-checked "$unary_source" > "$module"
if rg -q 'Lanius.TypedIR.Surface.Stmt.mk|\{ core :=' "$module"; then
  echo "unary/wildcard fixture fell back to raw Core syntax" >&2
  exit 1
fi
lake env lean -R .lake/build -o "$olean" "$module"
LEAN_PATH="$lean_path" lake env lean -R .. \
  ../verified_compiler/tests/direct_named_unary_wildcard.lean
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_core_check.lean "$unary_source"
unary_binary=../target/verified-compiler/direct-unary-x86.elf
"$compiler" "$unary_source" > "$unary_binary"
chmod +x "$unary_binary"
unary_status=0
timeout 5s "$unary_binary" || unary_status=$?
if [[ "$unary_status" -ne 7 ]]; then
  echo "x86 unary/wildcard fixture returned $unary_status instead of 7" >&2
  exit 1
fi
echo "checked Lean unary operators and wildcard arms agree with x86"

# Mutation targets share the typed IR's field and local identities. Check
# both zero/multiple loop iterations and a type-preserving operator mutation.
mutation_source=../verified_compiler/tests/surface_mutation_loop.lani
"$extractor" --lean-checked "$mutation_source" > "$module"
if rg -q 'Lanius.TypedIR.Surface.Stmt.mk|\{ core :=' "$module"; then
  echo "mutation/loop fixture fell back to raw Core syntax" >&2
  exit 1
fi
lake env lean -R .lake/build -o "$olean" "$module"
LEAN_PATH="$lean_path" lake env lean -R .. \
  ../verified_compiler/tests/direct_named_mutation_loop.lean
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_core_check.lean "$mutation_source"
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_core_check.lean --mutate-assignment "$mutation_source"
mutation_binary=../target/verified-compiler/direct-mutation-x86.elf
"$compiler" "$mutation_source" > "$mutation_binary"
chmod +x "$mutation_binary"
mutation_status=0
timeout 5s "$mutation_binary" || mutation_status=$?
if [[ "$mutation_status" -ne 15 ]]; then
  echo "x86 mutation/loop fixture returned $mutation_status instead of 15" >&2
  exit 1
fi
echo "checked Lean mutation and loops agree with x86"

# Declarations without initializers and void returns retain their exact Core
# forms. A well-typed but invented zero initializer must fail source agreement.
declaration_source=../verified_compiler/tests/surface_local_declarations.lani
"$extractor" --lean-checked "$declaration_source" > "$module"
if rg -q 'Lanius.TypedIR.Surface.Stmt.mk|\{ core :=' "$module"; then
  echo "local declaration fixture fell back to raw Core syntax" >&2
  exit 1
fi
lake env lean -R .lake/build -o "$olean" "$module"
LEAN_PATH="$lean_path" lake env lean -R .. \
  ../verified_compiler/tests/direct_named_local_declarations.lean
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_core_check.lean "$declaration_source"
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_core_check.lean --mutate-initializer "$declaration_source"
declaration_binary=../target/verified-compiler/direct-declarations-x86.elf
"$compiler" "$declaration_source" > "$declaration_binary"
chmod +x "$declaration_binary"
declaration_status=0
timeout 5s "$declaration_binary" || declaration_status=$?
if [[ "$declaration_status" -ne 16 ]]; then
  echo "x86 local declarations returned $declaration_status instead of 16" >&2
  exit 1
fi
echo "checked Lean local declarations and void returns agree with x86"

# Division/remainder and bit operations retain Lanius signed semantics.
integer_source=../verified_compiler/tests/surface_integer_operators.lani
"$extractor" --lean-checked "$integer_source" > "$module"
if rg -q 'Lanius.TypedIR.Surface.Stmt.mk|\{ core :=' "$module"; then
  echo "integer operator fixture fell back to raw Core syntax" >&2
  exit 1
fi
lake env lean -R .lake/build -o "$olean" "$module"
LEAN_PATH="$lean_path" lake env lean -R .. \
  ../verified_compiler/tests/direct_named_integer_operators.lean
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_core_check.lean "$integer_source"
LEAN_PATH="$lean_path" lake env lean -R .. --run \
  ../verified_compiler/tests/direct_typed_core_check.lean --mutate-division "$integer_source"
integer_binary=../target/verified-compiler/direct-integer-operators.elf
"$compiler" "$integer_source" > "$integer_binary"
chmod +x "$integer_binary"
integer_status=0
timeout 5s "$integer_binary" || integer_status=$?
if [[ "$integer_status" -ne 37 ]]; then
  echo "x86 integer fixture returned $integer_status instead of 37" >&2
  exit 1
fi
echo "checked Lean integer operators agree with x86"

# Constants and slice indexing retain their resolved references. The separate
# source-to-Core checker does not yet model this fixture's allocation and
# raw slice construction; these checks establish local representation
# and matching Lean/native execution, not the open extractor correctness proof.
slice_source=../verified_compiler/tests/surface_slice_constant_index.lani
"$extractor" --lean-checked "$slice_source" > "$module"
if ! rg -Fq 'return «values»[Extracted.«app::main».Constants.«SLOT»]' "$module" \
  || ! rg -q '^def extractedProgram : Lanius.Core.Program :=' "$module"; then
  echo "direct Lean output lost typed slice-index syntax" >&2
  exit 1
fi
lake env lean -R .lake/build -o "$olean" "$module"
LEAN_PATH="$lean_path" lake env lean -R .. \
  ../verified_compiler/tests/direct_named_slice_index.lean
slice_binary=../target/verified-compiler/direct-slice-index-x86.elf
"$compiler" "$slice_source" > "$slice_binary"
chmod +x "$slice_binary"
if timeout 5s "$slice_binary"; then
  slice_status=0
else
  slice_status=$?
fi
if [[ "$slice_status" -ne 37 ]]; then
  echo "x86 slice-index fixture returned $slice_status instead of 37" >&2
  exit 1
fi
echo "typed Lean slice mutation and x86 execution agree"
