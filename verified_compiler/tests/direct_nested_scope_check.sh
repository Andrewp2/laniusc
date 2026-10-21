#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="${1:-$root/target/verified-compiler/extractor-current}"
compiler="${2:-$root/target/verified-compiler/compiler-current}"
cd "$root/formal"

source=../verified_compiler/tests/surface_nested_block.lani
module=.lake/build/GeneratedDirectCore.lean
"$extractor" --lean-checked "$source" > "$module"
lake env lean -R .lake/build -o .lake/build/GeneratedDirectCore.olean "$module"
export LEAN_PATH="$(lake env printenv LEAN_PATH):$(pwd)/.lake/build"
lake env lean -R .. ../verified_compiler/tests/direct_nested_scope.lean
lake env lean -R .. --run ../verified_compiler/tests/direct_typed_core_check.lean "$source"

binary=../target/verified-compiler/direct-nested-scope.elf
"$compiler" "$source" > "$binary"
chmod +x "$binary"
status=0
timeout 5s "$binary" || status=$?
if [[ "$status" -ne 7 ]]; then
  echo "nested scope fixture returned $status, expected 7" >&2
  exit 1
fi
echo "nested scopes preserve the source-derived Core and Lean/x86 execution"
