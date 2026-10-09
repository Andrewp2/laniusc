#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
gpu="${1:-$root/debug/laniusc}"
out="$(mktemp -d "$root/target/verified-compiler/generic-angles.XXXXXX")"
trap 'rm -rf "$out"' EXIT

# Comparisons in separate statements must not form a generic argument list.
# Real type arguments must still resolve and execute.
for fixture in x86/comparison_angle_scope gpu_generic_arguments; do
  timeout 20s "$gpu" --emit x86_64 -o "$out/program" \
    "$root/verified_compiler/tests/$fixture.lani"
  status=0
  timeout 5s "$out/program" || status=$?
  if [[ "$status" -ne 37 ]]; then
    echo "$fixture: GPU-compiled program returned $status, expected 37" >&2
    exit 1
  fi
done
echo 'Separate comparisons and genuine generic arguments execute correctly'
