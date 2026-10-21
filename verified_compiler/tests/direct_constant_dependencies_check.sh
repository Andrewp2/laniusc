#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="${1:-$root/target/verified-compiler/extractor-current}"
compiler="${2:-$root/target/verified-compiler/compiler-current}"
cd "$root/formal"

lake env lean --run Lanius/Compiler/ConstantGraphCheckTests.lean

sources=(../verified_compiler/tests/constant_dependencies_main.lani
         ../verified_compiler/tests/constant_dependencies_values.lani)
module=.lake/build/GeneratedDirectCore.lean
export LEAN_PATH="$(lake env printenv LEAN_PATH):$(pwd)/.lake/build"
for mode in default checked; do
  options=()
  if [[ "$mode" == checked ]]; then options=(--lean-checked); fi
  "$extractor" "${options[@]}" "${sources[@]}" > "$module"
  lake env lean -R .lake/build -o .lake/build/GeneratedDirectCore.olean "$module"
  lake env lean -R .. ../verified_compiler/tests/direct_constant_arithmetic.lean
done
lake env lean -R .. --run ../verified_compiler/tests/direct_typed_core_check.lean "${sources[@]}"
lake env lean -R .. --run ../verified_compiler/tests/direct_typed_core_check.lean --mutate-constant "${sources[@]}"

binary=../target/verified-compiler/direct-constant-dependencies-x86.elf
"$compiler" "${sources[@]}" > "$binary"
chmod +x "$binary"
status=0
timeout 5s "$binary" || status=$?
if [[ "$status" -ne 7 ]]; then
  echo "constant dependency fixture returned $status, expected 7" >&2
  exit 1
fi

for fixture in invalid_constant_self_cycle invalid_constant_mutual_cycle; do
  source_path="../verified_compiler/tests/$fixture.lani"
  for mode in default checked x86; do
    command=("$extractor")
    expected=30
    if [[ "$mode" == checked ]]; then command+=(--lean-checked); fi
    if [[ "$mode" == x86 ]]; then command=("$compiler"); expected=10; fi
    status=0
    "${command[@]}" "$source_path" > /dev/null 2>&1 || status=$?
    if [[ "$status" -ne "$expected" ]]; then
      echo "$mode $fixture returned $status, expected a clean rejection ($expected)" >&2
      exit 1
    fi
  done
done
echo "forward, shared, imported, and shadowed constants agree with source and x86; cycles rejected"
