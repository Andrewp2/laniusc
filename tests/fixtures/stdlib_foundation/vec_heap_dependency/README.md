# Heap migration to alloc::vec

`binary_heap.lani` is the attempted migration of the working heap to the new
borrowed-owner vector API. It delegates reserve, push, bulk extension, clone and
shrink through explicit Results, and obtains counted views from Vec directly.
It is a compiler reproduction, outside the production stdlib root.

## Current recheck: 2026-10-24

Root replayed the **exact unchanged** candidate and ten-line entry using
compiler checkpoint `59612b3431d7b0cdff16a6faecf881f62a675503`, with current
stdlib sources at `ec795253da2435cd632345ebb5d8f13c362df64d`. A fresh copied
stdlib replaced only `alloc/binary_heap.lani` with this retained migration.
The control used the same entry and the unchanged production heap backed by
`std::vec`.

| Replayed case | Result | Gate time | Exact log |
| --- | --- | --- | --- |
| Unchanged alloc-Vec candidate | LNC0047, missing complete native layout for a replay argument; compilation failed before native execution | 4.58 s | `observed-2026-10-24/candidate.log` |
| Current production heap control | Compilation, unchanged common strict x86 ELF/jump checker and native assertions pass; exit 0 with empty stdout/stderr | 4.48 s | `observed-2026-10-24/control.log` |

The failure points to the copied `core::cmp` module header and reports:

```text
a replay argument has no complete GPU native layout; its defining nominal
payloads or a retained checked width witness are required
```

The exact missing argument and compiler cause remain unknown. The module label
does not establish a defect in ordering. Similar native-layout diagnostics in
other captures do not identify this argument as a particular View, i32 or
nominal witness, or establish a shared cause. Imported iterator/stream and
other accepted generic paths do not establish this migration.

`OBSERVED-2026-10-24.sha256` pins the candidate, entry, this README and both
verbatim logs. The ignored source snapshot and original root logs remain under
`target/stdlib-work/heap-migration-readmission/`. Its source manifest is
`SNAPSHOT.sha256` (SHA256
`7d730587d39224a697d534b25ad0017d291cf4fc3b060bbf18c33fb90082d02d`).
No candidate, entry, production heap, vector, compiler or proof source was
changed for this recheck. The migration remains deferred; production keeps the
existing heap storage and protected `std::vec` identity.

## Historical observations: 2026-10-22

The same minimal entry failed LNC0047 against this implementation, while the
then-production heap control compiled and exited zero. The attempted migration
also failed the existing heap contracts, stateful model and allocation-failure
fixtures; its top-scores and large-construction cases compiled and ran. Those
successful cases did not establish a working migration. These larger fixture
observations are historical and were **not** rerun during the current recheck.

The historical failure remained after direct Vec view construction avoided a
separate nested-view-factory source shape. That distinction is retained without
claiming a confirmed cause for the heap migration failure.

## Replay

Prepare a fresh copy of the current stdlib and replace only the heap module.
Refuse to reuse an existing destination:

```sh
timeout --kill-after=2s 100s python3 - <<'PY'
from pathlib import Path
import shutil
copied = Path('target/stdlib-work/vec-heap-repro')
if copied.exists():
    raise SystemExit('refuse to overwrite the existing copied source root')
shutil.copytree('stdlib', copied)
shutil.copyfile(
    'tests/fixtures/stdlib_foundation/vec_heap_dependency/binary_heap.lani',
    copied / 'alloc/binary_heap.lani')
PY

timeout --kill-after=2s 100s flock -E 75 -w 35 \
  target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s \
  target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_foundation/vec_heap_dependency/main.lani \
  --stdlib-root target/stdlib-work/vec-heap-repro \
  -o target/stdlib-work/vec-heap-repro-program
```

Do not count the observed failure as a passing expected-failure test, and never
execute stale output after a failed compile. Compile the same entry with
`--stdlib-root stdlib` and a separate output path for the production control.
Any successful ELF must pass the unchanged common strict x86 checker before
bounded native execution. Record fresh compiler/shader/source identities if
rerunning after later changes. The entry only constructs a min-heap, pushes one
i32, checks its length and destroys it.
