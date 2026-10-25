# Reproducing the historical iterator layout boundary

The original [README](README.md), sources, logs and `SOURCES.sha256` remain
unchanged historical evidence. Its single-module replacement recipe assumes
that the production slice module still defines inherent `next` methods.
Shared cursor integration moves those methods into `core::iter`, so a fresh
reproduction must restore **both** historical modules.

`core/slice.lani` is copied byte for byte from compiler checkpoint
`59612b3431d7b0cdff16a6faecf881f62a675503`. Its SHA256 is
`f869b830dec77c200015cadf601739efcf1213a8d6fad51dc0a73514bffc4e66`.
The same bytes were present at `0519160c`, before raw cursor integration.
This retains the original cursor methods and their context without adding a
compatibility layer to the production library. The original nested Result
failure and passing inherent control have not been rerun for this supplement.

From the repository root, create a fresh copied source root:

```sh
timeout --kill-after=2s 100s python3 - <<'PY'
from pathlib import Path
import shutil
root = Path.cwd()
capture = root / 'tests/fixtures/stdlib_compiler_state/iterator_view_result'
copied = root / 'target/stdlib-work/iterator-view-result-paired-stdlib'
if copied.exists():
    raise SystemExit('refuse to overwrite the existing copied source root')
shutil.copytree(root / 'stdlib', copied)
for name in ('iter.lani', 'slice.lani'):
    shutil.copyfile(capture / 'core' / name, copied / 'core' / name)
PY
```

Use this paired root for `minimal.lani`, `inherent_control.lani` and
`original_admission.lani`. For example:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 \
  target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s \
  target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_compiler_state/iterator_view_result/minimal.lani \
  --stdlib-root target/stdlib-work/iterator-view-result-paired-stdlib \
  -o target/stdlib-work/iterator-view-result-paired-minimal.elf
```

Choose a distinct output path for each source. Record the compiler, shader and
dependency identities for any new run; other copied dependencies still come
from the current checkout and can change the result. Never run stale output
after a failed compilation. A successful ELF must pass the unchanged shared
x86 checker and native assertions before counting as execution evidence.

`SOURCES.sha256` still verifies the original capture. `PAIRING.sha256` pins
this supplement and the paired slice source separately; no original manifest
or observed log was replaced.
