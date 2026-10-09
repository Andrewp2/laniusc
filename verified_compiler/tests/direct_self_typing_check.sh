#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="${1:-$root/target/verified-compiler/extractor-current}"
lean_options=("${@:2}")
bootstrap="${LANIUSC:-$root/debug/laniusc}"
if (($# > 0)) && [[ ! -x "$extractor" ]]; then
  echo "extractor executable not found: $extractor" >&2
  exit 1
fi
if (($# == 0)); then
  (cd "$root" && "$bootstrap" --emit x86_64 \
    --source-root verified_compiler/src -o "$extractor" \
    verified_compiler/src/extractor.lani)
fi
cd "$root/formal"

# `include_str` sources are not tracked as Lake dependencies. Invalidate only
# this module's build trace, then let Lake rebuild it with its package metadata.
# Writing its .olean directly would break later native symbol resolution.
rm -f .lake/build/lib/lean/Lanius/Extraction/CurrentSourceClosure.trace
timeout 110s lake --no-cache build +Lanius.Extraction.CurrentSourceClosure \
  +Lanius.Extraction.OutputPacking.Expression +Lanius.Extraction.OutputPacking.Store \
  +Lanius.Semantics.Branch +Lanius.Semantics.RawStore +Lanius.Semantics.StatementProof \
  +Lanius.Semantics.CallProof +Lanius.Semantics.CallRun +Lanius.Semantics.RawSlice \
  +Lanius.Semantics.ScalarAssignment +Lanius.Semantics.LocalPair \
  +Lanius.Extraction.OutputPacking.Read +Lanius.Semantics.LoopRun \
  +Lanius.Semantics.CountedLocal +Lanius.Core.Bindings \
  +Lanius.Extraction.OutputLoop +Lanius.Extraction.OutputPacking.Nibble \
  +Lanius.Extraction.WriterFrame +Lanius.Semantics.PureProof +Lanius.Semantics.SourceValue

lake env lean -R .. --run ../verified_compiler/tests/direct_source_boundary.lean

mapfile -t sources < <(lake env lean -R .. --run \
  ../verified_compiler/tests/print_extractor_sources.lean)
if ((${#sources[@]} == 0)); then
  echo "extractor source closure is empty" >&2
  exit 1
fi

module=../target/verified-compiler/SelfCore.lean
olean=../target/verified-compiler/SelfCore.olean
(cd "$root" && /usr/bin/time -f 'self Lean emission: %e s' "$extractor" "${sources[@]}" > \
  "$root/target/verified-compiler/SelfCore.lean")
/usr/bin/time -f 'self Lean module check: %e s' \
  lake run checkExtraction -- "${lean_options[@]}" -R ../target/verified-compiler -o "$olean" "$module"
# Reuse the same contracts in the actual self-module, not just its small writer
# fixture. This is a tool proof check, not proof data emitted for every program.
proof=../target/verified-compiler/SelfOutputByte.lean
{
  sed -n '/^import Lanius/p' ../verified_compiler/tests/direct_output_text.lean \
    ../verified_compiler/tests/direct_output_hex_word.lean \
    ../verified_compiler/tests/direct_output_natural.lean | sort -u
  sed 's/^import GeneratedDirectCore$/import SelfCore/' ../verified_compiler/tests/direct_output_byte.lean
  sed '/^import /d' ../verified_compiler/tests/direct_packed_words.lean
  sed '/^import /d' ../verified_compiler/tests/direct_output_cursor.lean
  sed '/^import /d' ../verified_compiler/tests/direct_output_hex.lean
  sed '/^import /d' ../verified_compiler/tests/direct_output_hex_word.lean
  sed '/^import /d' ../verified_compiler/tests/direct_output_text.lean
  sed '/^import /d' ../verified_compiler/tests/direct_output_natural.lean
} > "$proof"
lean="$(lake env sh -c 'command -v lean')"
check_path="$(lake env printenv LEAN_PATH):$root/target/verified-compiler"
/usr/bin/time -f 'self writer contracts: %e s' \
  env LEAN_PATH="$check_path" "$lean" -R ../target/verified-compiler \
    -o ../target/verified-compiler/SelfOutputByte.olean "$proof"
/usr/bin/time -f 'self signed printer contract: %e s' \
  env LEAN_PATH="$check_path" "$lean" -R .. ../verified_compiler/tests/direct_output_signed.lean
/usr/bin/time -f 'self IR navigation contracts: %e s' \
  env LEAN_PATH="$check_path" "$lean" -R .. ../verified_compiler/tests/direct_ir_navigation.lean
mkdir -p ../target/verified-compiler/verified_compiler/tests
/usr/bin/time -f 'self IR type-reference contracts: %e s' \
  env LEAN_PATH="$check_path" "$lean" -R .. \
    -o ../target/verified-compiler/verified_compiler/tests/direct_ir_type_ref.olean \
    ../verified_compiler/tests/direct_ir_type_ref.lean
/usr/bin/time -f 'self IR shape contracts: %e s' \
  env LEAN_PATH="$check_path" "$lean" -R .. \
    -o ../target/verified-compiler/verified_compiler/tests/direct_ir_shape.olean \
    ../verified_compiler/tests/direct_ir_shape.lean
/usr/bin/time -f 'self IR child traversal contracts: %e s' \
  env LEAN_PATH="$check_path" "$lean" -R .. \
    -o ../target/verified-compiler/verified_compiler/tests/direct_ir_children.olean \
    ../verified_compiler/tests/direct_ir_children.lean
/usr/bin/time -f 'self IR represented-child regressions: %e s' \
  env LEAN_PATH="$check_path" "$lean" -R .. \
    ../verified_compiler/tests/direct_ir_children_tests.lean
env LEAN_PATH="$check_path" "$lean" -R .. --run \
  ../verified_compiler/tests/direct_self_typing_check.lean
