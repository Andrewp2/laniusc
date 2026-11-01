# Inherent and trait methods with the same name

The reverse-iterator increment exposed this current compiler limitation on
2026-10-28. Adding `DoubleEndedIterator<T>::next_back` beside an existing
inherent `next_back` in a collection module produces `LNC0027`:

```text
duplicate inherent methods have equivalent receiver patterns
keep one method with this name for each equivalent receiver pattern in the module
```

`reject_duplicate.lani` reduces the failure to one generic trait, one concrete
receiver and two identical method bodies. `trait_only.lani` keeps the single
public trait method; its ordinary `cursor.next_back()` call compiles and runs
with exit status 0. Keeping both definitions in different modules also made a
concrete slice call ambiguous during the increment, although generic calls
through the trait bound resolved.

The library now has one canonical public trait method for each collection
cursor. Slice iterator methods live in `core::iter` to avoid an import cycle.
The change preserves ordinary `.next_back()` call syntax and introduces no
compiler patch, alias, duplicated owner, allocation or cleanup mechanism.

Reproduce each compilation separately from the repository root:

```bash
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_compiler_state/inherent_trait_name/reject_duplicate.lani \
  --stdlib-root stdlib --emit x86_64 -o target/stdlib-work/inherent-trait-name-rejected

timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_compiler_state/inherent_trait_name/trait_only.lani \
  --stdlib-root stdlib --emit x86_64 -o target/stdlib-work/inherent-trait-name-control
```

Local receipts are `target/stdlib-work/inherent-trait-name-reject-compile.log`,
`inherent-trait-name-control-compile.log` and
`inherent-trait-name-control-native.log`. The rejection is a diagnostic
snapshot, not a language requirement or a test that compiler fixes must keep
failing. No remaining reverse-iteration runtime dependency requires supporting
these duplicate definitions.
