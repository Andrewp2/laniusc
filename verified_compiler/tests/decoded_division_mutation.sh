#!/usr/bin/env bash
set -euo pipefail

# Copy the actual relation into an isolated namespace. Removing its division
# guard must invalidate the regression, without changing production sources.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${1:-$root/target/verified-compiler/decoded-division/mutation}"
mkdir -p "$out"
base_path="$(cd "$root/formal" && lake env printenv LEAN_PATH)"
lean="$(cd "$root/formal" && lake env sh -c 'command -v lean')"
{
  printf '%s\n' 'import Lanius.X86.Machine.DivisionEncoding' \
    'namespace Lanius.X86.Machine.DecodedDivisionMutation'
  awk '/^inductive Step / {copy=1} copy && /^\/-- UD2/ {exit} copy {print}' \
    "$root/formal/Lanius/X86/Machine/Scalar.lean"
  awk '/^example \(width/ {copy=1} copy && /^-- Legitimate/ {exit} copy {print}' \
    "$root/formal/Lanius/X86/Machine/DecodedDivisionTests.lean"
  printf '%s\n' 'end Lanius.X86.Machine.DecodedDivisionMutation'
} > "$out/Guarded.lean"
env LEAN_PATH="$base_path" "$lean" -R "$out" -o "$out/Guarded.olean" \
  "$out/Guarded.lean" > "$out/guarded.log" 2>&1
sed 's/(nonDivision : instruction.isDivision = false)/(nonDivision : True)/' \
  "$out/Guarded.lean" > "$out/Unchecked.lean"
if cmp -s "$out/Guarded.lean" "$out/Unchecked.lean"; then
  echo 'mutation did not remove the guard' >&2
  exit 1
fi
rm -f "$out/Unchecked.olean"
status=0
env LEAN_PATH="$base_path" "$lean" -R "$out" -o "$out/Unchecked.olean" \
  "$out/Unchecked.lean" > "$out/unchecked.log" 2>&1 || status=$?
if [[ "$status" -ne 1 || -e "$out/Unchecked.olean" ]] || \
    ! rg -q 'succeeded but was expected to fail' "$out/unchecked.log"; then
  echo "guard removal did not invalidate the regression cleanly (status $status)" >&2
  exit 1
fi
echo 'guarded relation passes; removing the division guard fails the regression, with no proof artifact'
