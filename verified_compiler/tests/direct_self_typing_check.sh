#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="${1:-$root/target/verified-compiler/extractor-current}"
bootstrap="${LANIUSC:-$root/target/debug/laniusc}"
if (($# == 0)); then
  (cd "$root" && "$bootstrap" --emit x86_64 \
    --source-root verified_compiler/src -o "$extractor" \
    verified_compiler/src/extractor.lani)
fi
cd "$root/formal"

mapfile -t sources < <(lake env lean -R .. --run \
  ../verified_compiler/tests/print_extractor_sources.lean)
if ((${#sources[@]} == 0)); then
  echo "extractor source closure is empty" >&2
  exit 1
fi

module=../target/verified-compiler/SelfCore.lean
olean=../target/verified-compiler/SelfCore.olean
started=$SECONDS
(cd "$root" && "$extractor" "${sources[@]}" > \
  "$root/target/verified-compiler/SelfCore.lean")
echo "self Lean emission: $((SECONDS - started)) s"
started=$SECONDS
lake env lean -R ../target/verified-compiler -o "$olean" "$module"
echo "self Lean module check: $((SECONDS - started)) s"
LEAN_PATH="$(lake env printenv LEAN_PATH):$(pwd)/../target/verified-compiler" \
  lake env lean -R .. --run \
    ../verified_compiler/tests/direct_self_typing_check.lean
