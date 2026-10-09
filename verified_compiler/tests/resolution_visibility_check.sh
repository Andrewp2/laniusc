#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="${1:-$root/target/verified-compiler/extractor-direct}"
compiler="${2:-$root/target/verified-compiler/compiler-direct}"
cd "$root"

# Exercise the nominal candidate filter against all declaration kinds and
# malformed capacities before checking source-level visibility through it.
out="$(mktemp -d "$root/target/verified-compiler/resolution-test.XXXXXX")"
trap 'rm -rf "$out"' EXIT
pending=("$root/verified_compiler/tests/lowering_nominal_catalog.lani")
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
"$compiler" "${sources[@]}" > "$out/catalog.elf"
chmod +x "$out/catalog.elf"
timeout 5s "$out/catalog.elf"

# A matching explicit module path never grants visibility by itself. Both
# consumers of the shared IR must retain import and privacy checks.
reject() {
  local mode status expected
  local command=()
  for mode in lean checked x86; do
    command=("$extractor")
    expected=30
    if [[ "$mode" == checked ]]; then command+=(--lean-checked); fi
    if [[ "$mode" == x86 ]]; then command=("$compiler"); expected=10; fi
    status=0
    "${command[@]}" "$@" > /dev/null 2>/dev/null || status=$?
    if [[ "$status" -ne "$expected" ]]; then
      echo "$mode returned $status, expected clean rejection ($expected): $*" >&2
      exit 1
    fi
  done
}

reject verified_compiler/tests/resolution/no_import_call.lani \
  verified_compiler/tests/resolution/imported_enum_left.lani
reject verified_compiler/tests/resolution/private_call_main.lani \
  verified_compiler/tests/resolution/private_call_auxiliary.lani
reject verified_compiler/tests/resolution/no_import_type.lani \
  verified_compiler/tests/resolution/left.lani
reject verified_compiler/tests/qualified_call_wrong_module.lani \
  verified_compiler/tests/compiler_certificate_auxiliary.lani
reject verified_compiler/tests/resolution/imported_enum_wrong_module.lani \
  verified_compiler/tests/resolution/imported_enum_left.lani
# A declaration-kind index must retain every candidate. Neither a bare name
# nor a module prefix disambiguates two variants in the same source module.
reject verified_compiler/tests/resolution/ambiguous_local_variant.lani
reject verified_compiler/tests/resolution/ambiguous_qualified_variant.lani
reject verified_compiler/tests/resolution/private_variant.lani \
  verified_compiler/tests/resolution/call_left.lani
reject verified_compiler/tests/resolution/no_import_variant.lani \
  verified_compiler/tests/resolution/call_left.lani

# Constant resolution filters module owners and searches local values first.
# Neither optimization may bypass visibility or fall through a local nonconstant
# to an imported constant with the same spelling.
reject verified_compiler/tests/resolution/no_import_constant.lani \
  verified_compiler/tests/constant_imported_left.lani
reject verified_compiler/tests/resolution/private_constant.lani \
  verified_compiler/tests/constant_dependencies_values.lani
reject verified_compiler/tests/resolution/wrong_constant_module.lani \
  verified_compiler/tests/constant_imported_left.lani
reject verified_compiler/tests/constant_shadow_main.lani \
  verified_compiler/tests/constant_imported_left.lani
reject verified_compiler/tests/constant_variant_shadow_main.lani \
  verified_compiler/tests/constant_imported_left.lani

# Owner-span lookup must retain both imported candidates regardless of the
# order in which source units were loaded.
reject verified_compiler/tests/resolution/ambiguous_constant.lani \
  verified_compiler/tests/constant_imported_left.lani \
  verified_compiler/tests/constant_imported_right.lani
reject verified_compiler/tests/resolution/ambiguous_constant.lani \
  verified_compiler/tests/constant_imported_right.lani \
  verified_compiler/tests/constant_imported_left.lani

# Nominal lookup may filter declaration kinds, but not discard an imported ambiguity,
# expose private aliases, or accept a cycle in an alias chain.
reject verified_compiler/tests/resolution/ambiguous_type.lani \
  verified_compiler/tests/resolution/left.lani \
  verified_compiler/tests/resolution/right.lani
reject verified_compiler/tests/resolution/ambiguous_type.lani \
  verified_compiler/tests/resolution/right.lani \
  verified_compiler/tests/resolution/left.lani
reject verified_compiler/tests/resolution/private_type.lani \
  verified_compiler/tests/resolution/aliases.lani
reject verified_compiler/tests/resolution/cyclic_type.lani

# Same-spelled nominal types in different imported modules remain distinct.
"$extractor" verified_compiler/tests/resolution_qualified_main.lani \
  verified_compiler/tests/resolution/left.lani \
  verified_compiler/tests/resolution/right.lani > /dev/null
"$compiler" verified_compiler/tests/resolution_qualified_main.lani \
  verified_compiler/tests/resolution/left.lani \
  verified_compiler/tests/resolution/right.lani > /dev/null

echo "qualified resolution preserves imports, privacy, and exact module identity"
