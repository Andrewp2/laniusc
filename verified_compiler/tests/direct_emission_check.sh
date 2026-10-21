#!/usr/bin/env bash
set -euo pipefail

# Check default emission in one Lean invocation. Checked mode supplies an
# independent source witness; it must not replace the normal program under test.
# Each fixture also requires both output modes to describe the same Core program.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="${1:-$root/target/verified-compiler/extractor-direct}"
compiler="${2:-$root/target/verified-compiler/compiler-direct}"
# Check the contracts against fresh output below; build their shared proof
# dependencies explicitly so this gate also works without cached proof modules.
(cd "$root/formal"; lake build +Lanius.Extraction.OutputPacking.Expression \
  +Lanius.Extraction.OutputPacking.Store +Lanius.Semantics.Branch +Lanius.Semantics.RawStore \
  +Lanius.Semantics.StatementProof +Lanius.Semantics.CallProof +Lanius.Semantics.CallRun +Lanius.Semantics.RawSlice \
  +Lanius.Semantics.ScalarAssignment +Lanius.Semantics.LocalPair \
  +Lanius.Extraction.OutputPacking.Read +Lanius.Semantics.LoopRun \
  +Lanius.Semantics.CountedLocal +Lanius.Core.Bindings \
  +Lanius.Extraction.OutputLoop +Lanius.Extraction.OutputPacking.Nibble)
out="$(mktemp -d "$root/target/verified-compiler/direct-test.XXXXXX")"
trap 'rm -rf "$out"' EXIT
bundle="$out/Emission.lean"
printf '%s\n' 'import Lanius.TypedIR.Surface.Link' 'import Lanius.Execution' \
  'import Lanius.Compiler.DirectCoreCheck' \
  'import Lanius.Extraction.OutputPacking.Expression' 'import Lanius.Extraction.OutputPacking.Store' \
  'import Lanius.Semantics.Branch' 'import Lanius.Semantics.RawStore' \
  'import Lanius.Semantics.StatementProof' 'import Lanius.Semantics.CallProof' 'import Lanius.Semantics.CallRun' \
  'import Lanius.Semantics.RawSlice' 'import Lanius.Extraction.OutputPacking.Read' \
  'import Lanius.Semantics.LoopRun' 'import Lanius.Semantics.CountedLocal' \
  'import Lanius.Semantics.ScalarAssignment' 'import Lanius.Semantics.LocalPair' \
  'import Lanius.Core.Bindings' 'import Lanius.Extraction.OutputLoop' \
  'import Lanius.Extraction.OutputPacking.Nibble' > "$bundle"

cases=(
  'surface_enum_multi_payload|direct_named_multi_payload|37|'
  'surface_parameter_arithmetic|direct_named_parameter|7|'
  'surface_boolean_comparison|direct_named_comparison|1|'
  'surface_struct_fields|direct_named_fields|7|surface_struct_types'
  'surface_unary_wildcard|direct_named_unary_wildcard|7|'
  'surface_mutation_loop|direct_named_mutation_loop|15|'
  'surface_local_declarations|direct_named_local_declarations|16|'
  'surface_integer_operators|direct_named_integer_operators|37|'
  'surface_usize_operators||37|'
  'surface_string_values|direct_named_string_values|37|'
  'surface_string_bytes||37|'
  'host_packed_words|direct_packed_words|37|../src/verified/host'
  'surface_string_output|direct_output_byte direct_packed_words direct_output_cursor direct_output_hex direct_output_hex_word direct_output_text direct_output_natural|37|../src/verified/host ../src/verified/lean_output ../src/verified/ascii'
  'surface_raw_slice_alias||37|../src/verified/host'
  'surface_slice_constant_index|direct_named_slice_index|37|'
  'typed_slice_direct_return|direct_named_memory|30|'
  'enum_match_payload_direct_lean|direct_public_enum direct_choice_run|7|'
  'return_paths||12|'
  'constant_qualified_resolution||6|constant_imported_left constant_imported_right'
  'constant_unqualified_resolution||11|constant_imported_left constant_imported_right'
  'resolution/nominal_shadow||37|resolution/left resolution/right resolution/aliases'
  'surface_projection_snapshots||37|'
  'surface_callable_hash_collision||37|'
  'public_namespace_main|direct_public_namespaces|16|public_namespace_auxiliary'
  'surface_builtin_label_shadow|direct_named_builtin_labels|7|'
  'surface_i32_minimum||37|'
  'resolution/qualified_call_candidates||31|resolution/call_left resolution/call_right'
  'resolution/qualified_call_candidates||31|resolution/call_right resolution/call_left'
  'x86/comparison_angle_scope||37|'
  'surface_recursive_boolean||37|'
  'surface_void_call||7|'
)
index=0
source_audits=()
for spec in "${cases[@]}"; do
  IFS='|' read -r source check expected auxiliary <<< "$spec"
  paths=("$root/verified_compiler/tests/$source.lani")
  if [[ -n "$auxiliary" ]]; then
    read -r -a auxiliaries <<< "$auxiliary"
    for path in "${auxiliaries[@]}"; do
      paths+=("$root/verified_compiler/tests/$path.lani")
    done
  fi
  "$extractor" "${paths[@]}" > "$out/program.lean"
  if rg -q 'ExprHasType|StmtHasType|TypedIR.Intrinsic|Data.Lookup|extractedVerifiedProgram' "$out/program.lean"; then
    echo "per-program typing reconstruction in $source" >&2
    exit 1
  fi
  if rg -q 'Surface.FunctionRef|^def .*\.ref :' "$out/program.lean"; then
    echo "duplicate function-reference declarations in $source" >&2
    exit 1
  fi
  if rg -q '^def extractedFrontend|^private def extracted(RawTokens|ParseNodes)' "$out/program.lean"; then
    echo "frontend audit evidence leaked into default output for $source" >&2
    exit 1
  fi
  printf '\nnamespace Case%s\n' "$index" >> "$bundle"
  sed '/^import /d' "$out/program.lean" >> "$bundle"
  "$extractor" --lean-checked "${paths[@]}" > "$out/evidence.lean"
  printf '\nnamespace Evidence\n' >> "$bundle"
  sed '/^import /d' "$out/evidence.lean" >> "$bundle"
  printf '\nend Evidence\nopen Evidence (extractedFrontend)\n' >> "$bundle"
  printf '\nexample : extractedProgram = Evidence.extractedProgram := rfl\n' >> "$bundle"
  printf 'example : extractedEntrypoint = Evidence.extractedEntrypoint := rfl\n' >> "$bundle"
  if [[ -n "$check" ]]; then
    read -r -a checks <<< "$check"
    for proof in "${checks[@]}"; do
      sed '/^import /d' "$root/verified_compiler/tests/$proof.lean" >> "$bundle"
    done
  fi
  if [[ "$source" == surface_projection_snapshots || "$source" == surface_string_bytes || "$source" == surface_string_output || "$source" == surface_raw_slice_alias ]]; then
    printf '\nset_option maxRecDepth 4096 in\n' >> "$bundle"
  fi
  printf '\nexample : (match Lanius.Execution.run 1024 { program := extractedProgram, entrypoint := extractedEntrypoint } {} with | .returned (.signed .i32 %s) _ => true | _ => false) = true := by decide\n' "$expected" >> "$bundle"
  # The independent source checker does not model the raw host intrinsics or
  # pointer arithmetic yet. These fixtures still execute in Lean and x86.
  if [[ "$source" != host_packed_words && "$source" != surface_slice_constant_index && "$source" != typed_slice_direct_return && "$source" != surface_projection_snapshots && "$source" != surface_string_bytes && "$source" != surface_string_output && "$source" != surface_raw_slice_alias ]]; then
    source_audits+=("$index")
    printf '\ndef sourceAudit : IO Unit := do\n  let paths : List String := [' >> "$bundle"
    separator=""
    for path in "${paths[@]}"; do
      printf '%s"%s"' "$separator" "$path" >> "$bundle"
      separator=", "
    done
    printf ']\n  let sources ← paths.mapM fun path => do\n    let bytes ← IO.FS.readBinFile (System.FilePath.mk path)\n    pure ({ path, bytes := bytes.toList.map UInt8.toNat } : Lanius.Extraction.SourceFile)\n  match Lanius.Compiler.DirectCoreCheck.checkTyped (extractedFrontend sources) sources extractedProgram extractedEntrypoint (fun _ => none) with\n  | .ok _ => pure ()\n  | .error failure => throw (IO.userError s!"source agreement failed for {paths}: {repr failure}")\n' >> "$bundle"
  fi
  printf '\nend Case%s\n' "$index" >> "$bundle"
  "$compiler" "${paths[@]}" > "$out/program.elf"
  chmod +x "$out/program.elf"
  status=0
  timeout 5s "$out/program.elf" || status=$?
  if [[ "$status" -ne "$expected" ]]; then
    echo "$source: x86 returned $status, expected $expected" >&2
    exit 1
  fi
  index=$((index + 1))
done
# Capacity errors must retain exactly the successful prefix, not erase it or
# perform an upfront all-space rejection. The general Lean contract above
# covers every supported word; this native fixture checks capacities 0..8.
# Decimal output also checks every power-of-ten boundary, maximum i32,
# capacity rejection before writes, exact digits, and surrounding canaries.
for fixture in hex_word_capacity natural_capacity; do
  "$compiler" "$root/verified_compiler/tests/$fixture.lani" \
    "$root/verified_compiler/src/verified/host.lani" \
    "$root/verified_compiler/src/verified/lean_output.lani" \
    "$root/verified_compiler/src/verified/ascii.lani" > "$out/$fixture.elf"
  chmod +x "$out/$fixture.elf"
  status=0
  timeout 5s "$out/$fixture.elf" || status=$?
  if [[ "$status" -ne 37 ]]; then
    echo "$fixture boundaries returned $status, expected 37" >&2
    exit 1
  fi
done
# Native shifts mask their count; Core instead traps outside the operand width.
# Division/remainder also trap on zero divisors and signed quotient overflow.
ulimit -c 0
trap_count=0
for spec in 'usize_shift_limit|invalidShift|132' 'usize_shift_high|invalidShift|132' \
  'usize_division_zero|divisionByZero|136' 'usize_remainder_zero|divisionByZero|136' \
  'i32_shift_negative|invalidShift|132' 'i32_shift_limit|invalidShift|132' \
  'i32_division_zero|divisionByZero|136' 'i32_remainder_zero|divisionByZero|136' \
  'i32_division_overflow|signedDivisionOverflow|136' \
  'i32_remainder_overflow|signedDivisionOverflow|136' \
  'projection_uninitialized|uninitializedLocal|132'; do
  IFS='|' read -r source reason expected <<< "$spec"
  path="$root/verified_compiler/tests/$source.lani"
  "$extractor" "$path" > "$out/program.lean"
  printf '\nnamespace Trap_%s\n' "$source" >> "$bundle"
  sed '/^import /d' "$out/program.lean" >> "$bundle"
  printf '\nexample : (match Lanius.Execution.run 128 { program := extractedProgram, entrypoint := extractedEntrypoint } {} with | .trapped .%s _ => true | _ => false) = true := by decide\n' "$reason" >> "$bundle"
  printf '\nend Trap_%s\n' "$source" >> "$bundle"
  "$compiler" "$path" > "$out/program.elf"
  chmod +x "$out/program.elf"
  status=0
  { timeout 5s "$out/program.elf"; } 2> "$out/trap.log" || status=$?
  if [[ "$status" -ne "$expected" ]]; then
    echo "$source: x86 returned $status, expected trap ($expected)" >&2
    exit 1
  fi
  trap_count=$((trap_count + 1))
done
# The record oracle also rejects same-typed field/initializer substitutions.
printf '\ndef main : IO UInt32 := do\n' >> "$bundle"
for case_index in "${source_audits[@]}"; do
  printf '  Case%s.sourceAudit\n' "$case_index" >> "$bundle"
done
printf '  Case3.main ["%s", "%s"]\n' \
  "$root/verified_compiler/tests/surface_struct_fields.lani" \
  "$root/verified_compiler/tests/surface_struct_types.lani" >> "$bundle"
(cd "$root/formal"; lake run checkExtraction -- -R "$out" --run "$bundle")
echo "$index default-output fixtures checked against Lean and x86, with checked-mode Core agreement"
echo "${#source_audits[@]} fixtures also passed exact source agreement; raw-slice source checking remains unsupported"
echo "$trap_count signed/unsigned arithmetic and uninitialized-read traps agree in Lean and x86"

# The frontend, not the Lean representation, owns these typing checks.
for invalid in invalid_call_argument invalid_call_arity invalid_call_result invalid_scope_read invalid_enum_payload invalid_missing_return invalid_partial_return invalid_loop_return invalid_body_literal invalid_negative_literal invalid_positive_minimum invalid_unary_operand invalid_binary_operand invalid_void_unary invalid_void_binary invalid_void_return invalid_duplicate_function invalid_duplicate_external invalid_function_external_collision invalid_external_function_collision; do
  for mode in direct checked; do
    options=()
    if [[ "$mode" == checked ]]; then options=(--lean-checked); fi
    status=0
    "$extractor" "${options[@]}" "$root/verified_compiler/tests/$invalid.lani" > /dev/null 2>&1 || status=$?
    if [[ "$status" -ne 30 ]]; then
      echo "$invalid: $mode extractor returned $status, expected rejection (30)" >&2
      exit 1
    fi
  done
  status=0
  "$compiler" "$root/verified_compiler/tests/$invalid.lani" > /dev/null 2>&1 || status=$?
  expected_status=10
  case "$invalid" in
    invalid_missing_return|invalid_partial_return|invalid_loop_return) expected_status=11 ;;
  esac
  if [[ "$status" -ne "$expected_status" ]]; then
    echo "$invalid: compiler returned $status, expected rejection ($expected_status)" >&2
    exit 1
  fi
done
echo "Lanius rejects malformed bodies and duplicate callables in both output paths"
