#!/usr/bin/env bash
set -euo pipefail

# A focused gate for the traversal shared by normal x86 and Lean extraction.
# Supply freshly bootstrapped tools; this does not prove the tools correct.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="$(realpath "${1:-$root/target/verified-compiler/extractor-current}")"
compiler="$(realpath "${2:-$root/target/verified-compiler/compiler-current}")"
out="$(mktemp -d "$root/target/verified-compiler/tree-check.XXXXXX")"
trap 'rm -rf "$out"' EXIT

run_expected() {
  local expected="$1" binary="$2" status=0
  chmod +x "$binary"
  timeout 5s "$binary" || status=$?
  if [[ "$status" -ne "$expected" ]]; then
    echo "${binary##*/}: returned $status, expected $expected" >&2
    exit 1
  fi
}

"$compiler" "$root/verified_compiler/tests/body_tree.lani" \
  "$root/verified_compiler/src/ir/body_tree.lani" \
  "$root/verified_compiler/src/ir/body_events.lani" \
  "$root/verified_compiler/src/ir/type_ref.lani" \
  "$root/verified_compiler/src/verified/host.lani" > "$out/tree.elf"
run_expected 0 "$out/tree.elf"

source="$root/verified_compiler/tests/enum_match_payload_direct_lean.lani"
"$extractor" "$source" > "$out/GeneratedDirectCore.lean"
if rg -q 'ExprHasType|StmtHasType|TypedIR.Intrinsic|extractedFrontend|extractedVerifiedProgram' \
    "$out/GeneratedDirectCore.lean"; then
  echo "typing or frontend-audit evidence leaked into normal output" >&2
  exit 1
fi
(cd "$root/formal" && lake run checkExtraction -- -R "$out" \
  -o "$out/GeneratedDirectCore.olean" "$out/GeneratedDirectCore.lean")
base_path="$(cd "$root/formal" && lake env printenv LEAN_PATH)"
lean="$(cd "$root/formal" && lake env sh -c 'command -v lean')"
env LEAN_PATH="$out:$base_path" "$lean" -R "$root" \
  "$root/verified_compiler/tests/direct_public_enum.lean"
"$compiler" "$source" > "$out/match.elf"
run_expected 7 "$out/match.elf"

for invalid in invalid_enum_payload invalid_partial_return invalid_call_arity; do
  source="$root/verified_compiler/tests/$invalid.lani"
  for tool in "$extractor" "$compiler"; do
    if "$tool" "$source" > "$out/rejected" 2> "$out/rejection.log"; then
      echo "${tool##*/} accepted $invalid" >&2
      exit 1
    fi
    if [[ -s "$out/rejected" ]]; then
      echo "${tool##*/} emitted partial output for $invalid" >&2
      exit 1
    fi
  done
done
echo "tree traversal, Lean/x86 enum match, and malformed-input rejection passed"
