#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="${1:-$root/target/verified-compiler/extractor-current}"
compiler="${2:-$root/target/verified-compiler/compiler-current}"
bootstrap="${LANIUSC:-$root/target/debug/laniusc}"
if (($# == 0)); then
  (cd "$root" && "$bootstrap" --emit x86_64 --source-root verified_compiler/src \
    -o "$extractor" verified_compiler/src/extractor.lani)
fi
if (($# < 2)); then
  (cd "$root" && "$bootstrap" --emit x86_64 --source-root verified_compiler/src \
    -o "$compiler" verified_compiler/src/compiler.lani)
fi
cd "$root/formal"

module=.lake/build/GeneratedDirectCore.lean
payload=../verified_compiler/tests/public_constant_payloads.lani
"$extractor" "$payload" > "$module"
lake env lean -R .lake/build -o .lake/build/GeneratedDirectCore.olean "$module"
export LEAN_PATH="$(lake env printenv LEAN_PATH):$(pwd)/.lake/build"
lake env lean -R .. ../verified_compiler/tests/direct_public_constant_payloads.lean
# The default and checked modes share the same named IR emission. The latter
# also provides the exact source evidence needed by the independent checker.
"$extractor" --lean-checked "$payload" > "$module"
lake env lean -R .lake/build -o .lake/build/GeneratedDirectCore.olean "$module"
lake env lean -R .. --run ../verified_compiler/tests/direct_typed_core_check.lean "$payload"
lake env lean -R .. --run ../verified_compiler/tests/direct_typed_core_check.lean --mutate-constant "$payload"
payload_binary=../target/verified-compiler/direct-public-constant-payloads-x86.elf
"$compiler" "$payload" > "$payload_binary"
chmod +x "$payload_binary"
status=0
timeout 5s "$payload_binary" || status=$?
if [[ "$status" -ne 0 ]]; then
  echo "constant payload fixture returned $status, expected 0" >&2
  exit 1
fi

sources=(../verified_compiler/tests/public_constant_main.lani
         ../verified_compiler/tests/public_constant_auxiliary.lani)
"$extractor" --lean-checked "${sources[@]}" > "$module"
if rg -q 'extractedConstantRef[0-9]|TypedIR\.Surface\.ConstantRef' "$module"; then
  echo "named constant declarations regressed to reference-only aliases" >&2
  exit 1
fi
lake env lean -R .lake/build -o .lake/build/GeneratedDirectCore.olean "$module"
export LEAN_PATH="$(lake env printenv LEAN_PATH):$(pwd)/.lake/build"
lake env lean -R .. ../verified_compiler/tests/direct_public_constants.lean
lake env lean -R .. --run ../verified_compiler/tests/direct_typed_core_check.lean "${sources[@]}"
lake env lean -R .. --run ../verified_compiler/tests/direct_typed_core_check.lean --mutate-constant "${sources[@]}"

binary=../target/verified-compiler/direct-public-constants-x86.elf
"$compiler" "${sources[@]}" > "$binary"
chmod +x "$binary"
status=0
timeout 5s "$binary" || status=$?
if [[ "$status" -ne 37 ]]; then
  echo "public constant fixture returned $status, expected 37" >&2
  exit 1
fi
echo "public Lean constants preserve module ownership, types, and x86 execution"

# Folding must retain source agreement, not merely produce a typed value.
# The same fixture exercises negative literals, wrapping, division/remainder,
# and a composed initializer in both the direct Lean and x86 outputs.
arithmetic=../verified_compiler/tests/constant_arithmetic_direct_lean.lani
"$extractor" "$arithmetic" > "$module"
lake env lean -R .lake/build -o .lake/build/GeneratedDirectCore.olean "$module"
lake env lean -R .. ../verified_compiler/tests/direct_constant_arithmetic.lean
"$extractor" --lean-checked "$arithmetic" > "$module"
lake env lean -R .lake/build -o .lake/build/GeneratedDirectCore.olean "$module"
lake env lean -R .. ../verified_compiler/tests/direct_constant_arithmetic.lean
lake env lean -R .. --run ../verified_compiler/tests/direct_typed_core_check.lean "$arithmetic"
lake env lean -R .. --run ../verified_compiler/tests/direct_typed_core_check.lean --mutate-constant "$arithmetic"
binary=../target/verified-compiler/direct-constant-arithmetic-x86.elf
"$compiler" "$arithmetic" > "$binary"
chmod +x "$binary"
status=0
timeout 5s "$binary" || status=$?
if [[ "$status" -ne 7 ]]; then
  echo "constant arithmetic fixture returned $status, expected 7" >&2
  exit 1
fi
echo "computed constants preserve source agreement and Lean/x86 execution"

reject_constant() {
  local expected="$1" status=0
  shift
  "$@" > /dev/null 2>&1 || status=$?
  if [[ "$status" -ne "$expected" ]]; then
    echo "invalid constant returned $status, expected a clean rejection ($expected): $*" >&2
    exit 1
  fi
}
for invalid in invalid_constant_division invalid_constant_division_overflow invalid_constant_magnitude; do
  source_path="../verified_compiler/tests/$invalid.lani"
  reject_constant 30 "$extractor" "$source_path"
  reject_constant 30 "$extractor" --lean-checked "$source_path"
  reject_constant 10 "$compiler" "$source_path"
done
echo "trapping and out-of-range constants rejected in both Lean modes and x86"
