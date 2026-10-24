# Nested View result layout during iterator construction

This captures an observed compiler native-layout boundary, with the original
module and failing entry preserved byte for byte. It is not an expected-failure
test, an alternate production iterator, or a compiler fix. Capture prepared on
2026-10-23 at source checkpoint `8551c9e297303578ed9e717944c18b96166a465f`.
No compilation or native execution was performed while preparing this capture.

`core/iter.lani` is the exact original iterator module. Its `from_slice<T>`
first produces `Result<slice::View<T>,slice::ViewError>`, checks `is_err`, then
uses `unwrap_err`/`unwrap` before calling `from_view<T>`. `minimal.lani` is the
exact observed two-element reduction: it constructs `SliceIter<i32>`, directly
calls its `next` method and checks values, remaining count and fused exhaustion.
It has no Take, Chain, generic consumer, compound item or range cursor.
`original_admission.lani` preserves the complete earlier admission entry.
`inherent_control.lani` is the exact passing control using the existing
`slice::view<i32>`, View and inherent Iter operations, with matching values and
assertions. Historical source-only/pending headers in those copies are unchanged.

`SOURCES.sha256` pins every captured source, this README and the verbatim terminal
logs. `ORIGINAL_BASELINE.sha256` and `ORIGINAL_OBSERVED-01.sha256` preserve the
original ignored evidence manifests, including their original path names.
Their source hashes agree with the corresponding permanent copies here:

| Permanent source | Original SHA256 |
| --- | --- |
| `core/iter.lani` | `7560ff743ccdfe3c788d992830a1ade92c62dd69efaad4ca6c32870902f43e55` |
| `minimal.lani` | `6f2a20e9bd9dc269e0b799faddd462884f5ac043f36effd81fc8936f5769b00d` |
| `original_admission.lani` | `fc60e8ac82d165252b5dc29ae4f754b7e783cb20da1a2cab749819fa17b4cc4f` |

## Observed results

Root ran these focused gates; the results are retained under `observed/`:

| Source/version | Result | Terminal log |
| --- | --- | --- |
| Original full admission, original module | LNC0047 before native execution; 4.60 s | `original-full-failure.log` |
| `minimal.lani`, original module | LNC0047 before native execution; 4.37 s | `minimal-failure.log` |
| Same minimal source, debug tracing enabled | Same LNC0047, detail 6; 4.70 s | `minimal-debug-failure.log` |
| `inherent_control.lani` | Compile, unchanged common x86 jump checker and native assertions pass; 3.49 s | `inherent-control.log` |
| Live full admission with direct typed View construction | Compile, unchanged common x86 jump checker and native assertions pass; 5.52 s | `full-direct-view-admission.log` |

The failures were labeled at the imported `core::cmp` module header:

```text
error[LNC0047]: type-check execution failed
generic type instantiation reached a compiler boundary
a replay argument has no complete GPU native layout; its defining nominal
payloads or a retained checked width witness are required
```

That source label does not establish a defect in comparison code. Debug output
records `GenericInstantiationBoundary detail=6`. Source mapping for this exact
closure identifies nominal 17 as `ViewError`, 18 as `View`, 19 as `Iter` and 23
as `SliceIter`. Result helper targets 58, 61 and 62 are `is_err`, `unwrap` and
`unwrap_err`. The replayed `View<i32>` argument has `words:None` and witness
`4294967295`, while the enclosing `SliceIter<i32>` already has `words:Some(5)`:

```text
target=(0,0,58/61/62): View<i32>, words:None; ViewError, words:Some(1)
target=(0,0,61): SliceIter<i32>, words:Some(5); ViewError, words:Some(1)
```

These numeric identities are evidence from that source closure, not stable
compiler ABI values. The reduction demonstrates that adapters are unnecessary
to reach this missing nested View-result layout. The passing inherent control
and the already known SliceIter width narrow the boundary further; they do not
prove all generic Result or nominal-layout compositions work.

## Accepted library simplification and remaining boundary

The live `stdlib/core/iter.lani` now centralizes logical metadata validation in
its existing `from_view<T>` function. Its `from_slice<T>` constructs a typed
public View directly and delegates:

```lanius
let view: core::slice::View<T> =
    core::slice::View { values: values, start: 0, length: count };
return from_view<T>(view);
```

This removes the redundant intermediate View Result and its three generic
helpers. It preserves arbitrary `T`, the exact public API/errors, validation
before cursor creation, and the physical-backing/lifetime caller contract.
The new full admission's success establishes imported Iterator/Take/Chain and
generic-consumer dispatch for that entry. It is not a compiler repair for the
old Result composition. The captured original module has not been rerun after
its preservation here, and the original native-layout boundary remains open.

## Reproduce with the original module

Using the current production stdlib directly would select the simplified
constructor and would not reproduce the captured input. From the repository
root, prepare a **fresh copied source root** and overwrite only its iterator
module with this historical module:

```sh
timeout --kill-after=2s 100s python3 - <<'PY'
from pathlib import Path
import shutil
root = Path.cwd()
capture = root / 'tests/fixtures/stdlib_compiler_state/iterator_view_result'
copied = root / 'target/stdlib-work/iterator-view-result-stdlib'
if copied.exists():
    raise SystemExit('refuse to overwrite the existing copied source root')
shutil.copytree(root / 'stdlib', copied)
shutil.copyfile(capture / 'core/iter.lani', copied / 'core/iter.lani')
PY
```

Compile the captured minimal entry under the shared GPU lock, with a fresh
output path:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 \
  target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s \
  target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_compiler_state/iterator_view_result/minimal.lani \
  --stdlib-root target/stdlib-work/iterator-view-result-stdlib \
  -o target/stdlib-work/iterator-view-result-minimal.elf
```

Substitute `inherent_control.lani` or `original_admission.lani` and a distinct
output filename for the other captured sources. These reproduction commands
have not been run for this permanent capture. The copied dependency modules
come from the current checkout, so a later compiler or dependency change can
alter the result; record compiler/shader/source identities with any fresh run.
Never execute stale output after a failed compile. A newly successful output
must pass the unchanged shared x86 checker and its native assertions before
being counted as execution evidence.

The original root logs remain under `target/stdlib-work/iterator-admission/`
and source snapshots under `target/stdlib-work/iterator-layout-probes/`.
Neither ignored baseline was changed while creating this permanent capture.
