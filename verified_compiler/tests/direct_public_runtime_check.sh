#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="${1:-$root/target/verified-compiler/extractor-current}"
compiler="${2:-$root/target/verified-compiler/compiler-current}"
cd "$root/formal"

source=../verified_compiler/tests/public_runtime_main.lani
module=.lake/build/GeneratedDirectCore.lean
"$extractor" --lean-checked "$source" > "$module"
lake env lean -R .lake/build -o .lake/build/GeneratedDirectCore.olean "$module"
export LEAN_PATH="$(lake env printenv LEAN_PATH):$(pwd)/.lake/build"
lake env lean -R .. ../verified_compiler/tests/direct_public_runtime.lean
lake env lean -R .. --run ../verified_compiler/tests/direct_typed_core_check.lean "$source"
lake env lean -R .. --run ../verified_compiler/tests/direct_typed_core_check.lean --mutate-runtime "$source"

# Check runtime signatures, exact source bindings, callers, linking, and execution.
binary=../target/verified-compiler/direct-public-runtime.elf
"$compiler" "$source" > "$binary"
chmod +x "$binary"
status=0
timeout 5s "$binary" || status=$?
if [[ "$status" -ne 7 ]]; then
  echo "runtime fixture returned $status, expected 7" >&2
  exit 1
fi

scratch="$(mktemp -d ../target/verified-compiler/runtime-bindings.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
for change in unknown-abi wrong-abi unknown-name parameter result arity; do
  case "$change" in
    unknown-abi) rewrite='s/"lanius_alloc"/"foreign_allocator"/' ;;
    wrong-abi) rewrite='s/"lanius_alloc"/"lanius_std"/' ;;
    unknown-name) rewrite='s/fn close(/fn unknown(/' ;;
    parameter) rewrite='s/fn close(handle: i32)/fn close(handle: bool)/' ;;
    result) rewrite='s/fn close(handle: i32) -> i32/fn close(handle: i32) -> bool/' ;;
    arity) rewrite='s/fn close(handle: i32)/fn close()/' ;;
  esac
  changed="$scratch/$change.lani"
  sed "$rewrite" "$source" > "$changed"
  for mode in lean lean-checked x86; do
    command=("$extractor")
    expected=30
    if [[ "$mode" == lean-checked ]]; then command+=(--lean-checked); fi
    if [[ "$mode" == x86 ]]; then command=("$compiler"); expected=10; fi
    status=0
    "${command[@]}" "$changed" > "$scratch/output" 2> "$scratch/error" || status=$?
    if [[ "$status" -ne "$expected" || -s "$scratch/output" ]]; then
      echo "$mode failed to reject $change cleanly (exit $status)" >&2
      exit 1
    fi
  done
done

# Omitted ABIs use the default runtime policy; escaped spellings have the
# same decoded meaning. Check both against their actual emitted source tree.
for spelling in omitted escaped; do
  changed="$scratch/$spelling.lani"
  if [[ "$spelling" == omitted ]]; then
    sed 's/extern "lanius_alloc"/extern/; s/extern "lanius_std"/extern/' "$source" > "$changed"
  else
    sed 's/"lanius_alloc"/"lanius_\\alloc"/; s/"lanius_std"/"lanius_\\std"/' "$source" > "$changed"
  fi
  "$extractor" --lean-checked "$changed" > "$module"
  lake env lean -R .lake/build -o .lake/build/GeneratedDirectCore.olean "$module"
  lake env lean -R .. --run ../verified_compiler/tests/direct_typed_core_check.lean "$changed"
  "$compiler" "$changed" > "$binary"
  chmod +x "$binary"
  status=0
  timeout 5s "$binary" || status=$?
  if [[ "$status" -ne 7 ]]; then
    echo "$spelling ABI fixture returned $status, expected 7" >&2
    exit 1
  fi
done
echo "runtime imports preserve source agreement and execution"
