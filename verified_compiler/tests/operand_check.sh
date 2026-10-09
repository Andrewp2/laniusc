#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="$(realpath "${1:-$root/target/verified-compiler/extractor-cache}")"
compiler="$(realpath "${2:-$root/target/verified-compiler/compiler-cache}")"
out="$root/target/verified-compiler/operand-fixtures"
mkdir -p "$out"
bundle="$out/Operands.lean"
printf 'import Lanius.TypedIR.Surface.Link\nimport Lanius.Execution\n' > "$bundle"
for source in surface_void_call enum_match_payload_direct_lean surface_recursive_boolean surface_unary_wildcard surface_cache_scopes \
    surface_integer_operators surface_usize_operators surface_boolean_comparison \
    enum_equality_direct_lean surface_pointer_operators; do
  case "$source" in
    surface_boolean_comparison) expected=1 ;;
    enum_equality_direct_lean) expected=0 ;;
    surface_recursive_boolean|surface_cache_scopes|surface_integer_operators|surface_usize_operators|surface_pointer_operators) expected=37 ;;
    *) expected=7 ;;
  esac
  "$extractor" "$root/verified_compiler/tests/$source.lani" > "$out/$source.lean"
  printf '\nnamespace %s\n' "$source" >> "$bundle"
  sed '/^import /d' "$out/$source.lean" >> "$bundle"
  printf '\nexample : (match Lanius.Execution.run 1024 { program := extractedProgram, entrypoint := extractedEntrypoint } {} with | .returned (.signed .i32 %s) _ => true | _ => false) = true := by decide\n' "$expected" >> "$bundle"
  printf '\nend %s\n' "$source" >> "$bundle"
  "$compiler" "$root/verified_compiler/tests/$source.lani" > "$out/$source.elf"
  chmod +x "$out/$source.elf"
  status=0
  timeout 5s "$out/$source.elf" || status=$?
  if [[ "$status" != "$expected" ]]; then
    echo "$source: x86 returned $status, expected $expected" >&2
    exit 1
  fi
done
for source in invalid_void_unary invalid_void_binary invalid_unary_operand invalid_binary_operand invalid_cache_scope; do
  for mode in direct checked; do
    options=()
    if [[ "$mode" == checked ]]; then options=(--lean-checked); fi
    status=0
    "$extractor" "${options[@]}" "$root/verified_compiler/tests/$source.lani" > /dev/null 2>&1 || status=$?
    if [[ "$status" != 30 ]]; then echo "$source: $mode extraction did not reject" >&2; exit 1; fi
  done
  status=0
  "$compiler" "$root/verified_compiler/tests/$source.lani" > /dev/null 2>&1 || status=$?
  if [[ "$status" != 10 ]]; then echo "$source: shared lowering did not reject before backend validation" >&2; exit 1; fi
done
cd "$root/formal"
/usr/bin/time -f 'operand source fixtures: %e s' lake run checkExtraction -- -R "$out" "$bundle"
echo 'void calls, Choice/match, scalar/enum/pointer operators and binding scopes agree in Lean and x86; invalid operands reject'
