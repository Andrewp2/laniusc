#!/usr/bin/env bash
set -euo pipefail

# Fresh contracts for the exact admitted self-module. No claim of fresh
# admission/builder timing: those byte-identical foundations are reused.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${1:-$root/target/verified-compiler/match-metadata}"
cache="$root/target/verified-compiler/scoped-expressions"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
for proof in type_ref shape; do
  artifact="$cache/verified_compiler/tests/direct_ir_$proof.olean"
  if [[ ! -f "$artifact" || "$root/verified_compiler/tests/direct_ir_$proof.lean" -nt "$artifact" ]]; then
    echo "IR $proof contract requires rechecking before reuse" >&2; exit 1
  fi
done
cd "$root/formal"
mapfile -t sources < <(lake env lean -R .. --run ../verified_compiler/tests/print_extractor_sources.lean)
if ((${#sources[@]} == 0)); then echo 'empty source closure' >&2; exit 1; fi
(cd "$root" && /usr/bin/time -f 'current self emission: %e s' \
  target/verified-compiler/extractor-current "${sources[@]}" > "$out/SelfCore.lean")
if ! cmp -s "$out/SelfCore.lean" "$cache/SelfCore.lean" ||
    [[ ! -f "$cache/SelfCore.olean" || "$cache/SelfCore.lean" -nt "$cache/SelfCore.olean" ]]; then
  echo 'program changed or lacks admission; recheck before reuse' >&2; exit 1
fi
lean="$(lake env sh -c 'command -v lean')"
base="$(lake env printenv LEAN_PATH)"
rm -f "$out/Metadata.olean"
LEAN_PATH="$cache:$base" /usr/bin/time -f 'match metadata contracts: %e s' "$lean" -R "$root" \
  -o "$out/Metadata.olean" "$root/verified_compiler/tests/direct_match_metadata.lean"
{
  printf 'import Metadata\n'
  sed '/^import /d' "$root/verified_compiler/tests/direct_match_metadata_tests.lean"
} > "$out/Fixtures.lean"
LEAN_PATH="$out:$cache:$base" /usr/bin/time -f 'match metadata fixtures: %e s' "$lean" -R "$out" "$out/Fixtures.lean"
