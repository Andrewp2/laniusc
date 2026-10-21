#!/usr/bin/env bash
set -euo pipefail

# Compile the regression with the Lanius compiler itself, then execute both
# the regression and the x86 image it emits. No generated Lanius or Core input.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
compiler="${1:-$root/target/verified-compiler/compiler-direct}"
out="$(mktemp -d "$root/target/verified-compiler/workspace-test.XXXXXX")"
trap 'rm -rf "$out"' EXIT
pending=("$root/verified_compiler/tests/backend_native_workspace.lani")
sources=()
declare -A seen
while ((${#pending[@]})); do
  path=${pending[0]}
  pending=("${pending[@]:1}")
  [[ ${seen[$path]+set} ]] && continue
  seen[$path]=1
  sources+=("$path")
  while read -r module; do
    pending+=("$root/verified_compiler/src/${module//:://}.lani")
  done < <(sed -n 's/^import \([^;]*\);$/\1/p' "$path")
done
"$compiler" "${sources[@]}" > "$out/regression.elf"
chmod +x "$out/regression.elf"
timeout 15s "$out/regression.elf" > "$out/result.elf"
chmod +x "$out/result.elf"
status=0
timeout 5s "$out/result.elf" || status=$?
if [[ "$status" -ne 7 ]]; then
  echo "workspace regression image returned $status, expected 7" >&2
  exit 1
fi
echo "Large native IR, accumulated call fixups, capacity rejection, and canary passed"
