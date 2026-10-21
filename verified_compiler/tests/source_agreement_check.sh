#!/usr/bin/env bash
set -euo pipefail

# Optional bootstrap audit of the actual ordinary output. Both output modes
# share Core meaning, and independent source bytes feed the reference checker.
# This does not add a validation tree or a typing proof to normal extraction.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="${1:-$root/target/verified-compiler/extractor-current}"
extractor="$(realpath "$extractor")"
if (( $# > 0 )); then shift; fi
fixtures=("$@")
if (( ${#fixtures[@]} == 0 )); then fixtures=(enum_match_payload_direct_lean); fi
out="$root/target/verified-compiler/source-agreement"
mkdir -p "$out"
cd "$root/formal"
lake --no-cache build +Lanius.Compiler.DirectCoreCheck +Lanius.Declarations.SourceCheckTests \
  +Lanius.Compiler.CatalogSynthesisTests +Lanius.Extraction.SourceQuote
cd "$root"
for fixture in "${fixtures[@]}"; do
  source="verified_compiler/tests/$fixture.lani"
  "$extractor" "$source" > "$out/Ordinary.lean"
  "$extractor" --lean-checked "$source" > "$out/Audited.lean"
  if rg -q 'ExprHasType|StmtHasType|extractedFrontend|extractedRawTokens' "$out/Ordinary.lean"; then
    echo 'ordinary output unexpectedly reconstructs verification data' >&2; exit 1
  fi
  case "$fixture" in
    enum_match_payload_direct_lean)
      original='.«Some» (7)'; replacement='.«Some» (8)' ;;
    surface_nested_enum)
      original='.«Number» («value»)'; replacement='.«Number» (7)' ;;
    *) echo "unsupported agreement fixture: $fixture" >&2; exit 1 ;;
  esac
  if ! rg -Fq "$original" "$out/Ordinary.lean"; then
    echo "missing same-typed mutation target for $fixture" >&2; exit 1
  fi
  {
    printf 'import Lanius.Extraction.SourceQuote\n'
    sed -n '/^import /p' "$out/Ordinary.lean" "$out/Audited.lean" \
      "$root/verified_compiler/tests/direct_source_agreement.lean" | sort -u
    printf '\nnamespace Ordinary\n'
    sed '/^import /d' "$out/Ordinary.lean"
    printf '\nend Ordinary\nnamespace Audited\n'
    sed '/^import /d' "$out/Audited.lean"
    printf '\nend Audited\nnamespace Tampered\n'
    sed '/^import /d' "$out/Ordinary.lean" | sed "s/$original/$replacement/g"
    printf '\nend Tampered\n'
    printf 'noncomputable def expectedSources : List Lanius.Extraction.SourceFile := [source_file%% "../../../%s" as "%s"]\n' "$source" "$source"
    sed '/^import /d' "$root/verified_compiler/tests/direct_source_agreement.lean"
  } > "$out/Agreement.lean"
  (cd "$root/formal" && /usr/bin/time -f "$fixture fresh source/Core agreement: %e s" \
    lake run checkExtraction -- -R "$out" "$out/Agreement.lean")
done
echo 'fresh ordinary Lean output has kernel-checked source/body agreement'
