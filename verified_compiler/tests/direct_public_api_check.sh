#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="${1:-$root/target/verified-compiler/extractor-current}"
compiler="${2:-$root/target/verified-compiler/compiler-current}"
cd "$root/formal"

# Imported declarations must retain usable names, distinguish source modules
# and type/function namespaces, and escape Lean keywords. These files also
# test exact source-to-Core agreement and execute identically on x86.
sources=(../verified_compiler/tests/public_namespace_main.lani
         ../verified_compiler/tests/public_namespace_auxiliary.lani)
module=.lake/build/GeneratedDirectCore.lean
"$extractor" --lean-checked "${sources[@]}" > "$module"
if rg -q 'Surface.FunctionRef|extractedFunctionRef[0-9]|^def .*\.ref :' "$module"; then
  echo "source functions regained separate reference declarations" >&2
  exit 1
fi
lake env lean -R .lake/build -o .lake/build/GeneratedDirectCore.olean "$module"
export LEAN_PATH="$(lake env printenv LEAN_PATH):$(pwd)/.lake/build"
lake env lean -R .. ../verified_compiler/tests/direct_public_namespaces.lean
lake env lean -R .. --run ../verified_compiler/tests/direct_typed_core_check.lean "${sources[@]}"

binary=../target/verified-compiler/direct-public-api-x86.elf
"$compiler" "${sources[@]}" > "$binary"
chmod +x "$binary"
status=0
timeout 5s "$binary" || status=$?
if [[ "$status" -ne 16 ]]; then
  echo "public namespace fixture returned $status, expected 16" >&2
  exit 1
fi
echo "public Lean declarations preserve source namespaces and agree with x86"
