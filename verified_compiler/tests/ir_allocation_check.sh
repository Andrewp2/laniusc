#!/usr/bin/env bash
set -euo pipefail

# Fresh self-extraction and actual allocation/read/byte-copy contracts. Keep this
# gate focused on the changed boundary; unrelated writer proofs are separate.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="${1:-$root/target/verified-compiler/extractor-current}"
out="${2:-$root/target/verified-compiler/ir-allocation}"
mkdir -p "$out/verified_compiler/tests"
out="$(cd "$out" && pwd)"
if [[ ! -x "$extractor" ]]; then
  echo "extractor executable not found: $extractor" >&2
  exit 1
fi
cd "$root/formal"
rm -f .lake/build/lib/lean/Lanius/Extraction/CurrentSourceClosure.trace
lake --no-cache build +Lanius.Extraction.CurrentSourceClosure \
  +Lanius.Memory.Allocation +Lanius.Memory.Footprint +Lanius.Memory.BufferPrefix +Lanius.Semantics.HostCall +Lanius.Semantics.RawStore \
  +Lanius.Semantics.RawSlice +Lanius.Semantics.CallProof +Lanius.Semantics.PureProof \
  +Lanius.Extraction.OutputPacking.Read +Lanius.Extraction.OutputLoop \
  +Lanius.Core.Bindings +Lanius.Semantics.SourceValue +Lanius.Semantics.TotalWhile +Lanius.World.FileRead
lake env lean -R .. --run ../verified_compiler/tests/direct_source_boundary.lean
mapfile -t sources < <(lake env lean -R .. --run ../verified_compiler/tests/print_extractor_sources.lean)
if ((${#sources[@]} == 0)); then echo "empty extractor source closure" >&2; exit 1; fi
(cd "$root" && /usr/bin/time -f 'fresh self emission: %e s' "$extractor" "${sources[@]}" > "$out/SelfCore.lean")
/usr/bin/time -f 'fresh self admission: %e s' lake run checkExtraction -- \
  -R "$out" -o "$out/SelfCore.olean" "$out/SelfCore.lean"
lean="$(lake env sh -c 'command -v lean')"
base_path="$(lake env printenv LEAN_PATH)"
/usr/bin/time -f 'fresh allocation/storage contracts: %e s' env LEAN_PATH="$out:$base_path" "$lean" -R "$root" \
  -o "$out/verified_compiler/tests/direct_ir_allocation.olean" \
  "$root/verified_compiler/tests/direct_ir_allocation.lean"
/usr/bin/time -f 'fresh scratch/read composition: %e s' env LEAN_PATH="$out:$base_path" "$lean" -R "$root" \
  -o "$out/verified_compiler/tests/direct_host_views.olean" \
  "$root/verified_compiler/tests/direct_host_views.lean"
/usr/bin/time -f 'fresh actual packed-byte copy: %e s' env LEAN_PATH="$out:$base_path" "$lean" -R "$root" \
  -o "$out/verified_compiler/tests/direct_byte_io_read.olean" \
  "$root/verified_compiler/tests/direct_byte_io_read.lean"
/usr/bin/time -f 'fresh actual byte-copy regressions: %e s' env LEAN_PATH="$out:$base_path" "$lean" -R "$root" \
  "$root/verified_compiler/tests/direct_byte_io_read_tests.lean"
/usr/bin/time -f 'fresh actual copying loop: %e s' env LEAN_PATH="$out:$base_path" "$lean" -R "$root" \
  -o "$out/verified_compiler/tests/direct_byte_io_read_loop.olean" \
  "$root/verified_compiler/tests/direct_byte_io_read_loop.lean"
/usr/bin/time -f 'fresh actual read-count branches: %e s' env LEAN_PATH="$out:$base_path" "$lean" -R "$root" \
  -o "$out/verified_compiler/tests/direct_byte_io_read_step.olean" \
  "$root/verified_compiler/tests/direct_byte_io_read_step.lean"
/usr/bin/time -f 'fresh actual outer read body: %e s' env LEAN_PATH="$out:$base_path" "$lean" -R "$root" \
  -o "$out/verified_compiler/tests/direct_byte_io_read_outer.olean" \
  "$root/verified_compiler/tests/direct_byte_io_read_outer.lean"
/usr/bin/time -f 'fresh actual outer read regressions: %e s' env LEAN_PATH="$out:$base_path" "$lean" -R "$root" \
  "$root/verified_compiler/tests/direct_byte_io_read_outer_tests.lean"
/usr/bin/time -f 'fresh actual total read declaration: %e s' env LEAN_PATH="$out:$base_path" "$lean" -R "$root" \
  -o "$out/verified_compiler/tests/direct_byte_io_read_total.olean" \
  "$root/verified_compiler/tests/direct_byte_io_read_total.lean"
/usr/bin/time -f 'fresh actual complete read function/call: %e s' env LEAN_PATH="$out:$base_path" "$lean" -R "$root" \
  -o "$out/verified_compiler/tests/direct_byte_io_read_function.olean" \
  "$root/verified_compiler/tests/direct_byte_io_read_function.lean"
/usr/bin/time -f 'fresh actual fitting-file refinement: %e s' env LEAN_PATH="$out:$base_path" "$lean" -R "$root" \
  -o "$out/verified_compiler/tests/direct_byte_io_read_file.olean" \
  "$root/verified_compiler/tests/direct_byte_io_read_file.lean"
/usr/bin/time -f 'fresh actual total read regressions: %e s' env LEAN_PATH="$out:$base_path" "$lean" -R "$root" \
  "$root/verified_compiler/tests/direct_byte_io_read_total_tests.lean"
/usr/bin/time -f 'fresh actual copying-loop regressions: %e s' env LEAN_PATH="$out:$base_path" "$lean" -R "$root" \
  "$root/verified_compiler/tests/direct_byte_io_read_loop_tests.lean"
/usr/bin/time -f 'fresh represented-storage regressions: %e s' env LEAN_PATH="$out:$base_path" "$lean" -R "$root" \
  "$root/verified_compiler/tests/direct_ir_allocation_tests.lean"

# Wrong size, missing rejection, and wrong endpoint must admit as program data
# but fail their actual-code contracts, not merely a text comparison.
for mutation in wrong-size no-rejection wrong-endpoint; do
  dir="$out/mutations/$mutation"
  mkdir -p "$dir/verified_compiler/tests"
  case "$mutation" in
    wrong-size)
      range='/^def Extracted.«verified::host».Functions.«alloc_i32» /,/^$/ '
      change='s/[*] (Lanius.TypedIR.Surface.Builtin.toUsize (Extracted.«verified::host».Constants.«I32_BYTES»))/* (Lanius.TypedIR.Surface.Builtin.toUsize (3))/'
      contract=actualAllocate ;;
    no-rejection)
      range='/^def Extracted.«verified::host».Functions.«alloc_i32» /,/^$/ '
      change='s/^    if .* then$/    if false then/'
      contract=actualReject ;;
    wrong-endpoint)
      range='/^def Extracted.«ir::body_tree».Functions.«build» /,/^$/ '
      change='s/\[«index»\] := «cursor»/[«index»] := («cursor» + 1)/'
      contract=actualEndpointStore ;;
  esac
  sed "$range{""$change"';}' "$out/SelfCore.lean" > "$dir/SelfCore.lean"
  if cmp -s "$out/SelfCore.lean" "$dir/SelfCore.lean"; then
    echo "$mutation did not change its source function" >&2; exit 1
  fi
  lake run checkExtraction -- -R "$dir" -o "$dir/SelfCore.olean" "$dir/SelfCore.lean" > "$dir/admission.log" 2>&1
  artifact="$dir/verified_compiler/tests/direct_ir_allocation.olean"
  rm -f "$artifact"
  status=0
  env LEAN_PATH="$dir:$base_path" "$lean" -R "$root" -o "$artifact" \
    "$root/verified_compiler/tests/direct_ir_allocation.lean" > "$dir/contract.log" 2>&1 || status=$?
  if [[ "$status" -ne 1 || -e "$artifact" ]] ||
      ! rg -Uq "'IRAllocationProof.$contract' depends on axioms: \\[[^]]*sorryAx" "$dir/contract.log" ||
      rg -q 'maximum.*(heartbeats|recursion depth)|index out of bounds' "$dir/contract.log"; then
    echo "$mutation did not reject the wrong behavior cleanly (status $status)" >&2; exit 1
  fi
  echo "$mutation: data admitted, actual contract rejected, no proof artifact"
done
